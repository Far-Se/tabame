param(
    [Parameter(Mandatory = $true)][string]$UpdateRoot,
    [Parameter(Mandatory = $true)][string]$InstallRoot,
    [Parameter(Mandatory = $true)][int]$ParentId,
    [Parameter(Mandatory = $true)][ValidatePattern('^\d+-\d+$')][string]$Token
)

# This helper is copied outside the managed payload before it starts. It never
# stops an existing Tabame session, elevates, or touches the user data directory.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$lockStream = $null
$journal = @()
$replacementStarted = $false
$child = $null
$pending = $null
$ready = $false
$committed = $false
$recovering = $false
$install = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$root = [IO.Path]::GetFullPath($UpdateRoot).TrimEnd('\')
$exe = Join-Path $install 'tabame.exe'
$backup = Join-Path $root 'backup'
$stage = Join-Path $root 'stage'
$journalPath = Join-Path $root 'journal.json'
$pendingPath = Join-Path $root 'pending.json'
$managedPath = Join-Path $root 'installed-files.json'
$logPath = Join-Path $root 'update.log'

function Write-Log([string]$Message) {
    Add-Content -LiteralPath $logPath -Value "[$([DateTime]::UtcNow.ToString('o'))] $Message"
}

function Assert-NoLinks([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing a reparse point: $cursor"
            }
        }
        $cursor = Split-Path -Parent $cursor
    }
}

function Child-Path([string]$Base, [string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or $Relative.Contains(':') -or
        $Relative.Contains('..') -or [IO.Path]::IsPathRooted($Relative)) {
        throw "Unsafe package path: $Relative"
    }
    $resolved = [IO.Path]::GetFullPath((Join-Path $Base $Relative))
    if (-not $resolved.StartsWith($Base.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path leaves its intended directory: $resolved"
    }
    Assert-NoLinks $resolved
    return $resolved
}

function Remove-WorkDirectory([string]$Path) {
    # Every recursive removal is restricted to these two updater-owned folders.
    $resolved = [IO.Path]::GetFullPath($Path)
    if (($resolved -ne (Join-Path $root 'stage')) -and ($resolved -ne (Join-Path $root 'backup'))) {
        throw "Refusing cleanup outside updater workspace: $resolved"
    }
    Assert-NoLinks $resolved
    if (Test-Path -LiteralPath $resolved) {
        foreach ($item in Get-ChildItem -LiteralPath $resolved -Recurse -Force) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing cleanup containing a reparse point: $($item.FullName)"
            }
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

function Other-Instances {
    # ExecutablePath distinguishes different portable installations. Failure to
    # query processes is fatal: never assume a locked/running app is safe to edit.
    return @(Get-CimInstance Win32_Process -Filter "Name = 'tabame.exe'" | Where-Object {
        $_.ProcessId -ne $ParentId -and
        ([string]::IsNullOrEmpty($_.ExecutablePath) -or $_.ExecutablePath -eq $exe)
    })
}

function Write-Json([string]$Path, $Value) {
    $temporary = "$Path.tmp"
    [IO.File]::WriteAllText($temporary, (ConvertTo-Json -InputObject $Value -Depth 8 -Compress))
    if (Test-Path -LiteralPath $Path) {
        [IO.File]::Replace($temporary, $Path, $null)
    } else {
        [IO.File]::Move($temporary, $Path)
    }
}

function Restore-Backup {
    foreach ($entry in $script:journal) {
        $target = Child-Path $install $entry.path
        if ($entry.existed) {
            Copy-Item -LiteralPath (Child-Path $backup $entry.path) -Destination $target -Force
        } elseif (Test-Path -LiteralPath $target -PathType Leaf) {
            Remove-Item -LiteralPath $target -Force
        }
    }
    Remove-Item -LiteralPath $journalPath -Force -ErrorAction SilentlyContinue
}

function Start-Tabame([bool]$WithHealthToken) {
    $launchArguments = '-update-relaunch'
    if ($WithHealthToken) { $launchArguments += " -update-token=$Token" }
    return Start-Process -FilePath $exe -WorkingDirectory $install -ArgumentList $launchArguments -WindowStyle Hidden -PassThru
}

try {
    Assert-NoLinks $root
    Assert-NoLinks $install
    if ($install -eq [IO.Path]::GetPathRoot($install).TrimEnd('\') -or $install -eq $root -or
        $install.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The installation must not be inside the updater workspace.'
    }
    $lockStream = [IO.File]::Open((Join-Path $root 'update.lock'), 'OpenOrCreate', 'ReadWrite', 'ReadWrite')
    $lockStream.Lock(0, [long]::MaxValue)
    $pending = Get-Content -LiteralPath $pendingPath -Raw | ConvertFrom-Json
    if ($pending.schema -ne 1 -or $pending.installDirectory -ne $install -or
        $pending.sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Invalid update descriptor.' }
    $parent = Get-Process -Id $ParentId -ErrorAction Stop
    if ($parent.Path -ne $exe) { throw 'The parent does not belong to this installation.' }
    if (@(Other-Instances).Count -gt 0) { throw 'Another Tabame window is open; deferring the update.' }

    # Acknowledge before waiting. Until this marker, Dart continues to own startup.
    [IO.File]::WriteAllText((Join-Path $root "ready-$Token"), 'ready')
    $ready = $true
    if (-not $parent.WaitForExit(15000)) { throw 'Startup handoff timed out.' }
    if (@(Other-Instances).Count -gt 0) { throw 'Another instance started during handoff.' }

    # An interrupted previous transaction is recovered before another attempt.
    if (Test-Path -LiteralPath $journalPath) {
        $previousResult = $null
        if (Test-Path -LiteralPath (Join-Path $root 'result.json')) {
            $previousResult = Get-Content -LiteralPath (Join-Path $root 'result.json') -Raw | ConvertFrom-Json
        }
        if ($null -ne $previousResult -and $previousResult.success -and $previousResult.sha256 -eq $pending.sha256) {
            # The application acknowledged startup before a cleanup interruption.
            $committed = $true
            $null = Start-Tabame $false
            Write-Json $managedPath $previousResult.files
            Remove-Item -LiteralPath $journalPath, $pendingPath -Force
            exit 0
        } else {
            $recovering = $true
            $journal = @(Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json)
            Restore-Backup
            $journal = @()
            $recovering = $false
        }
    }
    $archivePath = Join-Path $root 'package.zip'
    if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pending.sha256) {
        throw 'The staged package checksum changed.'
    }
    Remove-WorkDirectory $stage
    Remove-WorkDirectory $backup
    New-Item -ItemType Directory -Path $stage, $backup | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $expandedBytes = [long]0
        foreach ($entry in $archive.Entries) {
            $relative = $entry.FullName.Replace('/', '\')
            if ($relative.EndsWith('\')) { continue }
            # Packages contain app binaries and Flutter's data tree only. This
            # also protects legacy portable folders containing settings/plugins.
            if ($relative -notmatch '^(?:[^\\]+\.(?:exe|dll)|data\\.+|windows\\sqlite3\.dll)$') {
                throw "Unexpected application payload: $relative"
            }
            if (-not $names.Add($relative) -or $names.Count -gt 50000) { throw 'Duplicate or excessive package entries.' }
            $expandedBytes += $entry.Length
            if ($expandedBytes -gt 3GB) { throw 'Expanded package exceeds the size limit.' }
            $target = Child-Path $stage $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $false)
        }
    } finally { $archive.Dispose() }
    foreach ($required in @('tabame.exe', 'flutter_windows.dll', 'data\icudtl.dat', 'data\app.so', 'data\flutter_assets\pubspec.yaml')) {
        if (-not (Test-Path -LiteralPath (Join-Path $stage $required) -PathType Leaf)) { throw "Missing package file: $required" }
    }
    $spec = Get-Content -LiteralPath (Join-Path $stage 'data\flutter_assets\pubspec.yaml') -Raw
    if ($spec -notmatch '(?m)^version:\s*([^\s+]+)' -or ('v' + $Matches[1]) -ne $pending.version) {
        throw 'The release tag and packaged application version disagree.'
    }

    # Complete all backups before the first replacement. The journal is durable
    # before mutation, including files that did not exist in the old version.
    foreach ($file in Get-ChildItem -LiteralPath $stage -Recurse -File) {
        $relative = $file.FullName.Substring($stage.Length + 1)
        $target = Child-Path $install $relative
        $existed = Test-Path -LiteralPath $target -PathType Leaf
        if ($existed) {
            $saved = Child-Path $backup $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $saved) -Force | Out-Null
            Copy-Item -LiteralPath $target -Destination $saved
        }
        $journal += @{ path = $relative; existed = $existed; install = $true }
    }
    # Remove obsolete files only when a previous successful update owned them.
    # User-added files and the installer's uninstaller are never inferred as owned.
    if (Test-Path -LiteralPath $managedPath) {
        foreach ($relative in @(Get-Content -LiteralPath $managedPath -Raw | ConvertFrom-Json)) {
            if ($names.Contains($relative)) { continue }
            if ($relative -notmatch '^(?:[^\\]+\.(?:exe|dll)|data\\.+|windows\\sqlite3\.dll)$') {
                throw 'Invalid managed application file.'
            }
            $target = Child-Path $install $relative
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                $saved = Child-Path $backup $relative
                New-Item -ItemType Directory -Path (Split-Path -Parent $saved) -Force | Out-Null
                Copy-Item -LiteralPath $target -Destination $saved
                $journal += @{ path = $relative; existed = $true; install = $false }
            }
        }
    }
    Write-Json $journalPath $journal
    $replacementStarted = $true
    foreach ($entry in $journal) {
        $target = Child-Path $install $entry.path
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        if ($entry.install) {
            Copy-Item -LiteralPath (Child-Path $stage $entry.path) -Destination $target -Force
        } else {
            Remove-Item -LiteralPath $target -Force
        }
    }
    $child = Start-Tabame $true
    $healthy = Join-Path $root "healthy-$Token"
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    while (-not (Test-Path -LiteralPath $healthy)) {
        if ($child.HasExited -or [DateTime]::UtcNow -ge $deadline) { throw 'The updated app did not acknowledge startup.' }
        Start-Sleep -Milliseconds 250
    }
    if ((Get-Content -LiteralPath $healthy -Raw) -ne $pending.version) { throw 'The restarted version is incorrect.' }
    # Committing the transaction ends the rollback window. Cleanup failures must
    # never turn a healthy app into a rollback attempt against running binaries.
    Write-Json (Join-Path $root 'result.json') @{ success = $true; version = $pending.version; sha256 = $pending.sha256; files = @($names) }
    $committed = $true
    $replacementStarted = $false
    Write-Json $managedPath @($names)
    Remove-Item -LiteralPath $journalPath, $pendingPath -Force
    Remove-WorkDirectory $backup
    Remove-WorkDirectory $stage
    Remove-Item -LiteralPath $archivePath -Force
    Write-Log "Installed $($pending.version)."
} catch {
    $failure = $_.Exception.Message
    Write-Log $failure
    if ($committed) { exit 0 }
    if ($recovering) {
        Write-Log 'Interrupted recovery retained its pending descriptor, journal, and backup.'
        exit 1
    }
    if ($replacementStarted) {
        if ($null -ne $child -and -not $child.HasExited) {
            # Only the child launched by this transaction can be stopped.
            Stop-Process -Id $child.Id -Force
            $child.WaitForExit()
        }
        try {
            if (@(Other-Instances).Count -gt 0) { throw 'Close other Tabame windows before recovery.' }
            Restore-Backup
            Write-Log 'Restored the previous application files.'
        } catch {
            Write-Log "Recovery failed; retained backup and journal: $($_.Exception.Message)"
            exit 1
        }
    }
    if ($ready -and $null -ne $pending) {
        Write-Json (Join-Path $root 'result.json') @{ success = $false; version = $pending.version; sha256 = $pending.sha256; error = $failure }
        # Prevent automatic restart loops; an explicit check may stage it again.
        Remove-Item -LiteralPath $pendingPath -Force -ErrorAction SilentlyContinue
        if (@(Other-Instances).Count -eq 0 -and -not (Get-Process -Id $ParentId -ErrorAction SilentlyContinue)) {
            $null = Start-Tabame $false
        }
    }
} finally {
    if ($null -ne $lockStream) { $lockStream.Dispose() }
    [IO.File]::WriteAllText((Join-Path $root "done-$Token"), 'done')
    foreach ($marker in @("ready-$Token", "healthy-$Token")) {
        Remove-Item -LiteralPath (Join-Path $root $marker) -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
}
