[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ExePath,

    [Parameter(Mandatory = $true)]
    [string]$MsiPath,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedVersion,

    [Parameter(Mandatory = $false)]
    [string]$ExeSha256Path = '',

    [Parameter(Mandatory = $false)]
    [string]$MsiSha256Path = '',

    [Parameter(Mandatory = $false)]
    [switch]$RunInstallSmoke
)

$ErrorActionPreference = 'Stop'

function Assert-Checksum([string]$ArtifactPath, [string]$ChecksumPath) {
    if (-not (Test-Path -LiteralPath $ChecksumPath -PathType Leaf)) {
        throw "Checksum file does not exist: $ChecksumPath"
    }
    $expected = (Get-Content -LiteralPath $ChecksumPath -Raw).Trim().Split()[0].ToLowerInvariant()
    $actual = (Get-FileHash -LiteralPath $ArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($expected -ne $actual) {
        throw "Checksum mismatch for $ArtifactPath. Expected $expected, got $actual."
    }
}

function Get-MsiProperty([string]$DatabasePath, [string]$PropertyName) {
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $database = $installer.GetType().InvokeMember(
        'OpenDatabase',
        [System.Reflection.BindingFlags]::InvokeMethod,
        $null,
        $installer,
        [object[]]@([string]$DatabasePath, [int32]0)
    )
    $query = "SELECT ``Value`` FROM ``Property`` WHERE ``Property``='$PropertyName'"
    $view = $database.GetType().InvokeMember(
        'OpenView',
        [System.Reflection.BindingFlags]::InvokeMethod,
        $null,
        $database,
        [object[]]@($query)
    )
    $view.GetType().InvokeMember(
        'Execute',
        [System.Reflection.BindingFlags]::InvokeMethod,
        $null,
        $view,
        $null
    ) | Out-Null
    $record = $view.GetType().InvokeMember(
        'Fetch',
        [System.Reflection.BindingFlags]::InvokeMethod,
        $null,
        $view,
        $null
    )
    if (-not $record) {
        return $null
    }
    return $record.GetType().InvokeMember(
        'StringData',
        [System.Reflection.BindingFlags]::GetProperty,
        $null,
        $record,
        [object[]]@(1)
    )
}

function Invoke-MsiExec([string]$ArgumentList, [string]$Description) {
    # msiexec.exe is a GUI-subsystem executable. Invoking it directly with &
    # can return before it finishes and leave $LASTEXITCODE unset, especially
    # under PowerShell 7 on GitHub-hosted runners.
    $process = Start-Process `
        -FilePath "$env:SystemRoot\System32\msiexec.exe" `
        -ArgumentList $ArgumentList `
        -Wait `
        -PassThru `
        -WindowStyle Hidden
    if ($process.ExitCode -notin @(0, 1641, 3010)) {
        throw "$Description failed with Windows Installer exit code $($process.ExitCode)."
    }
}

foreach ($artifact in @($ExePath, $MsiPath)) {
    if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
        throw "Installer does not exist: $artifact"
    }
}

if ([string]::IsNullOrWhiteSpace($ExeSha256Path)) {
    $ExeSha256Path = "$ExePath.sha256"
}
if ([string]::IsNullOrWhiteSpace($MsiSha256Path)) {
    $MsiSha256Path = "$MsiPath.sha256"
}
Assert-Checksum $ExePath $ExeSha256Path
Assert-Checksum $MsiPath $MsiSha256Path

$expectedNumericVersion = ([regex]::Match($ExpectedVersion, '^\d+\.\d+\.\d+')).Value
if (-not $expectedNumericVersion) {
    throw "ExpectedVersion must begin with three numeric components: $ExpectedVersion"
}

$exeVersion = (Get-Item -LiteralPath $ExePath).VersionInfo.ProductVersion
if (-not $exeVersion -or -not $exeVersion.StartsWith($expectedNumericVersion, [System.StringComparison]::Ordinal)) {
    throw "EXE ProductVersion '$exeVersion' does not match expected version $expectedNumericVersion."
}

$msiFullPath = (Resolve-Path -LiteralPath $MsiPath).Path
$msiName = Get-MsiProperty $msiFullPath 'ProductName'
$msiVersion = Get-MsiProperty $msiFullPath 'ProductVersion'
$msiProductCode = Get-MsiProperty $msiFullPath 'ProductCode'
if ($msiName -ne 'Tabame') {
    throw "MSI ProductName is '$msiName', expected 'Tabame'."
}
if ($msiVersion -ne $expectedNumericVersion) {
    throw "MSI ProductVersion is '$msiVersion', expected '$expectedNumericVersion'."
}
if ($msiProductCode -notmatch '^\{[0-9A-Fa-f-]{36}\}$') {
    throw "MSI ProductCode is invalid: $msiProductCode"
}

if ($RunInstallSmoke) {
    $temporaryRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
    $smokeRoot = Join-Path $temporaryRoot ('tabame-installer-smoke-' + [guid]::NewGuid().ToString('N'))
    $innoInstallRoot = Join-Path $smokeRoot 'inno'
    $msiInstallRoot = Join-Path $smokeRoot 'msi'
    $msiInstallLog = Join-Path $smokeRoot 'msi-install.log'
    $msiUninstallLog = Join-Path $smokeRoot 'msi-uninstall.log'
    $markerRoot = Join-Path $env:LOCALAPPDATA 'Tabame'
    $markerPath = Join-Path $markerRoot ('installer-smoke-' + [guid]::NewGuid().ToString('N') + '.txt')
    New-Item -ItemType Directory -Path $smokeRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $markerRoot -Force | Out-Null
    [System.IO.File]::WriteAllText($markerPath, 'Installer uninstall must preserve this user-data marker.')

    try {
        $innoArguments = @(
            '/VERYSILENT',
            '/SUPPRESSMSGBOXES',
            '/NORESTART',
            '/SP-',
            "/DIR=`"$innoInstallRoot`""
        )
        $innoProcess = Start-Process -FilePath (Resolve-Path -LiteralPath $ExePath).Path -ArgumentList ($innoArguments -join ' ') -Wait -PassThru -WindowStyle Hidden
        if ($innoProcess.ExitCode -notin @(0, 3010)) {
            throw "Silent Inno Setup install failed with exit code $($innoProcess.ExitCode)."
        }
        foreach ($required in @('tabame.exe', 'flutter_windows.dll', 'data')) {
            if (-not (Test-Path -LiteralPath (Join-Path $innoInstallRoot $required))) {
                throw "Inno Setup install is missing $required."
            }
        }
        $uninstaller = Join-Path $innoInstallRoot 'unins000.exe'
        $uninstallProcess = Start-Process -FilePath $uninstaller -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -Wait -PassThru -WindowStyle Hidden
        if ($uninstallProcess.ExitCode -notin @(0, 3010)) {
            throw "Silent Inno Setup uninstall failed with exit code $($uninstallProcess.ExitCode)."
        }

        # Inno's uninstaller runs before the MSI smoke. Recreate the shared
        # parent defensively, then quote every path as one msiexec command line.
        New-Item -ItemType Directory -Path $smokeRoot -Force | Out-Null
        $msiInstallArguments = "/i `"$msiFullPath`" /qn /norestart INSTALLFOLDER=`"$msiInstallRoot`" /l*v `"$msiInstallLog`""
        Invoke-MsiExec $msiInstallArguments 'Silent MSI install'
        foreach ($required in @('tabame.exe', 'flutter_windows.dll', 'data')) {
            if (-not (Test-Path -LiteralPath (Join-Path $msiInstallRoot $required))) {
                throw "MSI install is missing $required."
            }
        }
        $msiUninstallArguments = "/x $msiProductCode /qn /norestart /l*v `"$msiUninstallLog`""
        Invoke-MsiExec $msiUninstallArguments 'Silent MSI uninstall'

        if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
            throw 'Installer uninstall removed data from %LOCALAPPDATA%\Tabame.'
        }
    }
    catch {
        foreach ($logPath in @($msiInstallLog, $msiUninstallLog)) {
            if (Test-Path -LiteralPath $logPath -PathType Leaf) {
                Write-Host "--- Tail of $logPath ---"
                Get-Content -LiteralPath $logPath -Tail 120 | Write-Host
            }
        }
        throw
    }
    finally {
        if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
            Remove-Item -LiteralPath $markerPath -Force
        }
        if (Test-Path -LiteralPath $smokeRoot) {
            Remove-Item -LiteralPath $smokeRoot -Recurse -Force
        }
    }
}

Write-Output "Windows installer verification passed for Tabame $expectedNumericVersion."
