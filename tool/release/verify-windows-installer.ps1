[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ExePath,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedVersion,

    [Parameter(Mandatory = $false)]
    [string]$ExeSha256Path = '',

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

if (-not (Test-Path -LiteralPath $ExePath -PathType Leaf)) {
    throw "Installer does not exist: $ExePath"
}

if ([string]::IsNullOrWhiteSpace($ExeSha256Path)) {
    $ExeSha256Path = "$ExePath.sha256"
}
Assert-Checksum $ExePath $ExeSha256Path

$expectedNumericVersion = ([regex]::Match($ExpectedVersion, '^\d+\.\d+\.\d+')).Value
if (-not $expectedNumericVersion) {
    throw "ExpectedVersion must begin with three numeric components: $ExpectedVersion"
}

$exeVersion = (Get-Item -LiteralPath $ExePath).VersionInfo.ProductVersion
if (-not $exeVersion -or -not $exeVersion.StartsWith($expectedNumericVersion, [System.StringComparison]::Ordinal)) {
    throw "EXE ProductVersion '$exeVersion' does not match expected version $expectedNumericVersion."
}

if ($RunInstallSmoke) {
    $temporaryRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
    $smokeRoot = Join-Path $temporaryRoot ('tabame-installer-smoke-' + [guid]::NewGuid().ToString('N'))
    $installRoot = Join-Path $smokeRoot 'app'
    $markerRoot = Join-Path $env:LOCALAPPDATA 'Tabame'
    $markerPath = Join-Path $markerRoot ('installer-smoke-' + [guid]::NewGuid().ToString('N') + '.txt')
    New-Item -ItemType Directory -Path $smokeRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $markerRoot -Force | Out-Null
    [System.IO.File]::WriteAllText($markerPath, 'Installer uninstall must preserve this user-data marker.')
    $appProcess = $null

    try {
        $installArguments = @(
            '/VERYSILENT',
            '/SUPPRESSMSGBOXES',
            '/NORESTART',
            '/SP-',
            "/DIR=`"$installRoot`""
        )
        $installProcess = Start-Process `
            -FilePath (Resolve-Path -LiteralPath $ExePath).Path `
            -ArgumentList ($installArguments -join ' ') `
            -Wait `
            -PassThru `
            -WindowStyle Hidden
        if ($installProcess.ExitCode -notin @(0, 3010)) {
            throw "Silent Inno Setup install failed with exit code $($installProcess.ExitCode)."
        }

        foreach ($required in @('tabame.exe', 'flutter_windows.dll', 'data')) {
            if (-not (Test-Path -LiteralPath (Join-Path $installRoot $required))) {
                throw "Inno Setup install is missing $required."
            }
        }

        $installedExecutable = Join-Path $installRoot 'tabame.exe'
        $appProcess = Start-Process -FilePath $installedExecutable -PassThru
        Start-Sleep -Seconds 2
        $appProcess.Refresh()
        if ($appProcess.HasExited) {
            throw 'Tabame exited before the uninstall close-process smoke could run.'
        }

        $uninstaller = Join-Path $installRoot 'unins000.exe'
        $uninstallProcess = Start-Process `
            -FilePath $uninstaller `
            -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' `
            -Wait `
            -PassThru `
            -WindowStyle Hidden
        if ($uninstallProcess.ExitCode -notin @(0, 3010)) {
            throw "Silent Inno Setup uninstall failed with exit code $($uninstallProcess.ExitCode)."
        }
        $appProcess.Refresh()
        if (-not $appProcess.HasExited) {
            throw 'Inno Setup uninstall did not close the running Tabame process.'
        }

        if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
            throw 'Installer uninstall removed data from %LOCALAPPDATA%\Tabame.'
        }
    }
    finally {
        if ($appProcess -and -not $appProcess.HasExited) {
            Stop-Process -Id $appProcess.Id -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
            Remove-Item -LiteralPath $markerPath -Force
        }
        if (Test-Path -LiteralPath $smokeRoot) {
            Remove-Item -LiteralPath $smokeRoot -Recurse -Force
        }
    }
}

Write-Output "Windows installer verification passed for Tabame $expectedNumericVersion."
