[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDir,

    [Parameter(Mandatory = $true)]
    [string]$ExePath,

    [Parameter(Mandatory = $true)]
    [string]$MsiPath,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $false)]
    [string]$ExeSha256Path = '',

    [Parameter(Mandatory = $false)]
    [string]$MsiSha256Path = '',

    [Parameter(Mandatory = $false)]
    [string]$StageDir = '',

    [Parameter(Mandatory = $false)]
    [string]$RepoRoot = '',

    [Parameter(Mandatory = $false)]
    [string]$InnoCompilerPath = '',

    [Parameter(Mandatory = $false)]
    [string]$WixPath = ''
)

$ErrorActionPreference = 'Stop'

function Get-FullPath([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path)
}

function Get-InnoCompiler([string]$RequestedPath) {
    if ($RequestedPath) {
        $resolved = (Resolve-Path -LiteralPath $RequestedPath).Path
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            throw "Inno Setup compiler does not exist: $RequestedPath"
        }
        return $resolved
    }

    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
    if ($candidates.Count -eq 0) {
        throw 'ISCC.exe was not found. Install Inno Setup 6 or pass -InnoCompilerPath.'
    }
    return $candidates[0]
}

function Get-Wix([string]$RequestedPath) {
    if ($RequestedPath) {
        $resolved = (Resolve-Path -LiteralPath $RequestedPath).Path
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            throw "WiX executable does not exist: $RequestedPath"
        }
        return $resolved
    }

    $command = Get-Command wix.exe -ErrorAction SilentlyContinue
    if (-not $command) {
        $command = Get-Command wix -ErrorAction SilentlyContinue
    }
    if (-not $command) {
        throw 'wix.exe was not found. Install the pinned WiX .NET tool or pass -WixPath.'
    }
    return $command.Source
}

function Write-Sha256([string]$ArtifactPath, [string]$ChecksumPath) {
    $checksumParent = Split-Path -Parent $ChecksumPath
    if ($checksumParent) {
        New-Item -ItemType Directory -Path $checksumParent -Force | Out-Null
    }
    $hash = (Get-FileHash -LiteralPath $ArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $line = "$hash  $([System.IO.Path]::GetFileName($ArtifactPath))"
    [System.IO.File]::WriteAllText($ChecksumPath, $line, [System.Text.UTF8Encoding]::new($false))
}

$repoRootValue = $RepoRoot
if ([string]::IsNullOrWhiteSpace($repoRootValue)) {
    $repoRootValue = Join-Path $PSScriptRoot '..\..'
}
$repoRootResolved = (Resolve-Path -LiteralPath $repoRootValue).Path
$releaseRoot = (Resolve-Path -LiteralPath $ReleaseDir).Path
$exeFullPath = Get-FullPath $ExePath
$msiFullPath = Get-FullPath $MsiPath

$versionMatch = [regex]::Match($Version.Trim(), '^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$')
if (-not $versionMatch.Success) {
    throw "Version must begin with three numeric components (for example 2.0.0): $Version"
}
$appVersion = "$($versionMatch.Groups[1].Value).$($versionMatch.Groups[2].Value).$($versionMatch.Groups[3].Value)"
$versionInfoVersion = "$appVersion.0"

foreach ($required in @('tabame.exe', 'flutter_windows.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $releaseRoot $required) -PathType Leaf)) {
        throw "Windows release directory is missing $required beside tabame.exe: $releaseRoot"
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $releaseRoot 'data') -PathType Container)) {
    throw "Windows release directory is missing the Flutter data directory: $releaseRoot"
}

$ownsTemporaryStage = [string]::IsNullOrWhiteSpace($StageDir)
$stageRoot = if ($ownsTemporaryStage) {
    Join-Path ([System.IO.Path]::GetTempPath()) ('tabame-installer-stage-' + [guid]::NewGuid().ToString('N'))
}
else {
    Get-FullPath $StageDir
}

try {
    if (Test-Path -LiteralPath $stageRoot) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

    Get-ChildItem -LiteralPath $releaseRoot -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $stageRoot -Recurse -Force
    }

    $unwantedExtensions = @('.exp', '.ilk', '.lib', '.map', '.pdb')
    Get-ChildItem -LiteralPath $stageRoot -Recurse -File -Force |
        Where-Object { $unwantedExtensions -contains $_.Extension.ToLowerInvariant() } |
        Remove-Item -Force

    $nestedSqlite = Join-Path $stageRoot 'windows\sqlite3.dll'
    $rootSqlite = Join-Path $stageRoot 'sqlite3.dll'
    if (Test-Path -LiteralPath $nestedSqlite -PathType Leaf) {
        if (Test-Path -LiteralPath $rootSqlite -PathType Leaf) {
            Remove-Item -LiteralPath $nestedSqlite -Force
        }
        else {
            Move-Item -LiteralPath $nestedSqlite -Destination $rootSqlite -Force
        }
    }

    Copy-Item -LiteralPath (Join-Path $repoRootResolved 'LICENSE') -Destination (Join-Path $stageRoot 'LICENSE') -Force

    foreach ($outputPath in @($exeFullPath, $msiFullPath)) {
        $parent = Split-Path -Parent $outputPath
        if ($parent) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
            Remove-Item -LiteralPath $outputPath -Force
        }
    }

    $innoCompiler = Get-InnoCompiler $InnoCompilerPath
    $innoSource = Join-Path $repoRootResolved 'packaging\windows\installer\Tabame.iss'
    if (-not (Test-Path -LiteralPath $innoSource -PathType Leaf)) {
        throw "Inno Setup source does not exist: $innoSource"
    }
    $exeBaseName = [System.IO.Path]::GetFileNameWithoutExtension($exeFullPath)
    $innoArguments = @(
        "/DAppVersion=$appVersion",
        "/DVersionInfoVersion=$versionInfoVersion",
        "/DPayloadDir=$stageRoot",
        "/DOutputDir=$(Split-Path -Parent $exeFullPath)",
        "/DOutputBaseName=$exeBaseName",
        "/DRepoRoot=$repoRootResolved",
        $innoSource
    )
    & $innoCompiler @innoArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup compilation failed with exit code $LASTEXITCODE."
    }
    if (-not (Test-Path -LiteralPath $exeFullPath -PathType Leaf)) {
        throw "Inno Setup did not create the expected installer: $exeFullPath"
    }

    $wix = Get-Wix $WixPath
    $wixSource = Join-Path $repoRootResolved 'packaging\windows\installer\Tabame.wxs'
    if (-not (Test-Path -LiteralPath $wixSource -PathType Leaf)) {
        throw "WiX source does not exist: $wixSource"
    }
    $wixArguments = @(
        'build',
        '-arch', 'x64',
        '-ext', 'WixToolset.UI.wixext',
        '-d', "AppVersion=$appVersion",
        '-d', "PayloadDir=$stageRoot",
        '-d', "RepoRoot=$repoRootResolved",
        '-out', $msiFullPath,
        $wixSource
    )
    & $wix @wixArguments
    if ($LASTEXITCODE -ne 0) {
        throw "WiX compilation failed with exit code $LASTEXITCODE."
    }
    if (-not (Test-Path -LiteralPath $msiFullPath -PathType Leaf)) {
        throw "WiX did not create the expected installer: $msiFullPath"
    }

    if ([string]::IsNullOrWhiteSpace($ExeSha256Path)) {
        $ExeSha256Path = "$exeFullPath.sha256"
    }
    if ([string]::IsNullOrWhiteSpace($MsiSha256Path)) {
        $MsiSha256Path = "$msiFullPath.sha256"
    }
    $exeShaFullPath = Get-FullPath $ExeSha256Path
    $msiShaFullPath = Get-FullPath $MsiSha256Path
    Write-Sha256 $exeFullPath $exeShaFullPath
    Write-Sha256 $msiFullPath $msiShaFullPath

    Write-Output "Created $exeFullPath"
    Write-Output "Created $exeShaFullPath"
    Write-Output "Created $msiFullPath"
    Write-Output "Created $msiShaFullPath"
}
finally {
    if ($ownsTemporaryStage -and (Test-Path -LiteralPath $stageRoot)) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force
    }
}
