[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallerPath,

    [Parameter(Mandatory = $true)]
    [string]$Sha256Path,

    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [Parameter(Mandatory = $false)]
    [string]$ExpectedVersion = '',

    [Parameter(Mandatory = $false)]
    [string]$ExpectedPublisher = '',

    [Parameter(Mandatory = $false)]
    [switch]$RequireSigned,

    [Parameter(Mandatory = $false)]
    [switch]$RunSilentInstallSmoke,

    [Parameter(Mandatory = $false)]
    [switch]$RunUpdateSmoke
)

$ErrorActionPreference = 'Stop'
$script:SignToolPath = $null

function Find-SignTool {
    $command = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $roots = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'),
        (Join-Path $env:ProgramFiles 'Windows Kits\10\bin')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    $candidate = $roots |
        ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter signtool.exe -File -Recurse -ErrorAction SilentlyContinue } |
        Where-Object { $_.FullName -match '\\x64\\' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (-not $candidate) {
        throw 'signtool.exe was not found in PATH or the Windows SDK.'
    }
    return $candidate.FullName
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-PortableExecutable([System.IO.FileInfo]$File) {
    $stream = [System.IO.File]::OpenRead($File.FullName)
    try {
        return $stream.ReadByte() -eq 0x4d -and $stream.ReadByte() -eq 0x5a
    }
    finally {
        $stream.Dispose()
    }
}

function Assert-Signed([string]$Path, [string]$Publisher, [bool]$Required) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($Required -and $signature.Status -ne 'Valid') {
        throw "Authenticode signature is not valid for $Path. Status: $($signature.Status)."
    }
    if ($Required) {
        if (-not $script:SignToolPath) {
            $script:SignToolPath = Find-SignTool
        }
        & $script:SignToolPath verify /pa /all /tw $Path
        if ($LASTEXITCODE -ne 0) {
            throw "signtool timestamp/chain verification failed for $Path with exit code $LASTEXITCODE."
        }
    }
    if ($Publisher -and $signature.SignerCertificate -and
        $signature.SignerCertificate.Subject -notlike "*$Publisher*") {
        throw "Signer subject for $Path does not contain the expected publisher '$Publisher'. Actual: $($signature.SignerCertificate.Subject)"
    }
    if ($Publisher -and -not $signature.SignerCertificate) {
        throw "No signer certificate was found for $Path."
    }
}

function Invoke-SilentInstaller([string]$Path, [string[]]$Arguments) {
    $process = Start-Process -FilePath $Path -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "Installer command failed with exit code $($process.ExitCode): $Path $($Arguments -join ' ')"
    }
}

if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
    throw "Store installer does not exist: $InstallerPath"
}
if (-not (Test-Path -LiteralPath $Sha256Path -PathType Leaf)) {
    throw "Store installer checksum does not exist: $Sha256Path"
}
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Store installer manifest does not exist: $ManifestPath"
}

$expectedHash = (Get-Content -LiteralPath $Sha256Path -Raw).Trim().Split()[0].ToLowerInvariant()
$actualHash = Get-Sha256 $InstallerPath
if ($expectedHash -ne $actualHash) {
    throw "Store installer checksum mismatch. Expected $expectedHash, got $actualHash."
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($manifest.artifactType -ne 'storeInstaller') {
    throw "Unexpected artifact type in Store installer manifest: $($manifest.artifactType)"
}
if ($manifest.installer.sha256 -ne $actualHash) {
    throw 'Store installer manifest hash does not match the installer.'
}
if ($ExpectedVersion) {
    $versionInfo = (Get-Item -LiteralPath $InstallerPath).VersionInfo
    $actualProductVersion = ([string]$versionInfo.ProductVersion).Trim()
    $acceptedProductVersions = @($ExpectedVersion, "$ExpectedVersion.0")
    if ($acceptedProductVersions -notcontains $actualProductVersion) {
        throw "Installer version mismatch. Expected $($acceptedProductVersions -join ' or '), got $actualProductVersion."
    }
    if ($manifest.appVersion -ne $ExpectedVersion) {
        throw "Store installer manifest version mismatch. Expected $ExpectedVersion, got $($manifest.appVersion)."
    }
}

Assert-Signed $InstallerPath $ExpectedPublisher ([bool]$RequireSigned)

if ($RunSilentInstallSmoke) {
    $smokeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('tabame-store-installer-smoke-' + [guid]::NewGuid().ToString('N'))
    $dataRoot = Join-Path $env:LOCALAPPDATA 'Tabame'
    $sentinel = Join-Path $dataRoot ('store-installer-smoke-' + [guid]::NewGuid().ToString('N') + '.txt')
    $runningProcess = $null
    New-Item -ItemType Directory -Path $smokeRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $dataRoot -Force | Out-Null
    Set-Content -LiteralPath $sentinel -Value 'installer-data-retention-check' -NoNewline
    try {
        $installArguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', "/DIR=`"$smokeRoot`"")
        Invoke-SilentInstaller $InstallerPath $installArguments

        foreach ($required in @('tabame.exe', 'flutter_windows.dll', 'sqlite3.dll', 'data')) {
            $requiredPath = Join-Path $smokeRoot $required
            if (-not (Test-Path -LiteralPath $requiredPath)) {
                throw "Silent install is missing $required beside the installed executable."
            }
        }
        $uninstaller = Join-Path $smokeRoot 'unins000.exe'
        if (-not (Test-Path -LiteralPath $uninstaller -PathType Leaf)) {
            throw 'Silent install did not create the Inno Setup uninstaller.'
        }
        Assert-Signed $uninstaller $ExpectedPublisher ([bool]$RequireSigned)

        if ($RunUpdateSmoke) {
            $powershellPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
            if (-not (Test-Path -LiteralPath $powershellPath -PathType Leaf)) {
                throw "Windows PowerShell was not found for the update shutdown smoke: $powershellPath"
            }

            # Use a harmless process with the installed executable's image path
            # so the smoke test exercises Inno's Restart Manager handling
            # without starting Tabame's desktop UI on the CI runner.
            Copy-Item -LiteralPath $powershellPath -Destination (Join-Path $smokeRoot 'tabame.exe') -Force
            $runningProcess = Start-Process `
                -FilePath (Join-Path $smokeRoot 'tabame.exe') `
                -ArgumentList @('-NoLogo', '-NoProfile', '-WindowStyle', 'Hidden', '-Command', 'Start-Sleep -Seconds 30') `
                -WindowStyle Hidden `
                -PassThru
            Start-Sleep -Seconds 2
            if ($runningProcess.HasExited) {
                throw 'The update shutdown smoke process exited before the installer ran.'
            }

            Invoke-SilentInstaller $InstallerPath $installArguments
            if (-not $runningProcess.WaitForExit(15000)) {
                Stop-Process -Id $runningProcess.Id -Force -ErrorAction SilentlyContinue
                throw 'The installer did not close the running Tabame process before updating.'
            }
            $runningProcess = $null
        }

        $installedPeFiles = @(Get-ChildItem -LiteralPath $smokeRoot -Recurse -File -Force |
            Where-Object { @('.cpl', '.dll', '.exe', '.ocx', '.scr', '.sys') -contains $_.Extension.ToLowerInvariant() } |
            Where-Object { Test-PortableExecutable $_ })
        if ($RequireSigned) {
            foreach ($peFile in $installedPeFiles) {
                Assert-Signed $peFile.FullName $ExpectedPublisher $true
            }
        }

        Invoke-SilentInstaller $InstallerPath $installArguments
        if (-not (Test-Path -LiteralPath $sentinel -PathType Leaf)) {
            throw 'Reinstall did not preserve the app-data sentinel.'
        }

        Invoke-SilentInstaller $uninstaller @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')
        if (Test-Path -LiteralPath (Join-Path $smokeRoot 'tabame.exe')) {
            throw 'Silent uninstall left the installed executable behind.'
        }
        if (-not (Test-Path -LiteralPath $sentinel -PathType Leaf)) {
            throw 'Silent uninstall removed the app-data sentinel.'
        }
        Write-Output 'Store installer silent install, reinstall, uninstall, and data-retention smoke passed.'
    }
    finally {
        if ($runningProcess -and -not $runningProcess.HasExited) {
            Stop-Process -Id $runningProcess.Id -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $smokeRoot) {
            Remove-Item -LiteralPath $smokeRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $sentinel) {
            Remove-Item -LiteralPath $sentinel -Force
        }
    }
}

Write-Output "Store installer verification passed: $InstallerPath"
