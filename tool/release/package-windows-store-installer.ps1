[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDir,

    [Parameter(Mandatory = $true)]
    [string]$InstallerPath,

    [Parameter(Mandatory = $true)]
    [string]$Sha256Path,

    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [Parameter(Mandatory = $true)]
    [string]$SbomPath,

    [Parameter(Mandatory = $true)]
    [string]$PartnerCenterMetadataPath,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $false)]
    [string]$StageDir,

    [Parameter(Mandatory = $false)]
    [switch]$UseExistingStage,

    [Parameter(Mandatory = $false)]
    [string]$SourceDateEpoch = '0',

    [Parameter(Mandatory = $false)]
    [string]$CommitSha = '',

    [Parameter(Mandatory = $false)]
    [string]$DependencyJsonPath = '',

    [Parameter(Mandatory = $false)]
    [string]$RepoRoot = '',

    [Parameter(Mandatory = $false)]
    [string]$SignToolScriptPath = ''
)

$ErrorActionPreference = 'Stop'

function Write-JsonNoBom([object]$Value, [string]$Path) {
    $json = $Value | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Get-FullPath([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path)
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-InnoCompiler {
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
    if ($candidates.Count -eq 0) {
        throw 'ISCC.exe was not found. Install the pinned Inno Setup 6 toolchain before packaging.'
    }
    return $candidates[0]
}

function Get-RelativePath([string]$Root, [string]$Path) {
    return $Path.Substring($Root.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
}

$repoRootValue = $RepoRoot
if ([string]::IsNullOrWhiteSpace($repoRootValue)) {
    $repoRootValue = Join-Path $PSScriptRoot '..\..'
}
$repoRootResolved = (Resolve-Path -LiteralPath $repoRootValue).Path
$releaseRoot = (Resolve-Path -LiteralPath $ReleaseDir).Path
$installerFullPath = Get-FullPath $InstallerPath
$shaFullPath = Get-FullPath $Sha256Path
$manifestFullPath = Get-FullPath $ManifestPath
$sbomFullPath = Get-FullPath $SbomPath
$metadataFullPath = Get-FullPath $PartnerCenterMetadataPath

$versionMatch = [regex]::Match($Version.Trim(), '^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$')
if (-not $versionMatch.Success) {
    throw "Version must be a three-part numeric version such as 2.0.0: $Version"
}
$appVersion = "$($versionMatch.Groups[1].Value).$($versionMatch.Groups[2].Value).$($versionMatch.Groups[3].Value)"
$versionInfoVersion = "$appVersion.0"

$epoch = 0L
if (-not [string]::IsNullOrWhiteSpace($SourceDateEpoch)) {
    if ($SourceDateEpoch -notmatch '^\d+$') {
        throw "SourceDateEpoch must be an integer: $SourceDateEpoch"
    }
    $epoch = [long]$SourceDateEpoch
}

if ([string]::IsNullOrWhiteSpace($CommitSha)) {
    $CommitSha = (git -C $repoRootResolved rev-parse HEAD 2>$null).Trim()
}

$stageRoot = $null
$ownsTemporaryStage = $false
try {
    if ($UseExistingStage) {
        if ([string]::IsNullOrWhiteSpace($StageDir)) {
            throw 'UseExistingStage requires StageDir.'
        }
        $stageRoot = (Resolve-Path -LiteralPath $StageDir).Path
    }
    else {
        if ([string]::IsNullOrWhiteSpace($StageDir)) {
            $stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('tabame-store-stage-' + [guid]::NewGuid().ToString('N'))
            $ownsTemporaryStage = $true
        }
        else {
            $stageRoot = Get-FullPath $StageDir
            if (Test-Path -LiteralPath $stageRoot) {
                Remove-Item -LiteralPath $stageRoot -Recurse -Force
            }
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

        $licensePath = Join-Path $repoRootResolved 'LICENSE'
        if (-not (Test-Path -LiteralPath $licensePath -PathType Leaf)) {
            throw "The repository license was not found: $licensePath"
        }
        Copy-Item -LiteralPath $licensePath -Destination (Join-Path $stageRoot 'LICENSE') -Force

        $noticePath = Join-Path $repoRootResolved 'packaging\windows\store-installer\THIRD-PARTY-NOTICES.txt'
        if (-not (Test-Path -LiteralPath $noticePath -PathType Leaf)) {
            throw "The Store third-party notice file was not found: $noticePath"
        }
        Copy-Item -LiteralPath $noticePath -Destination (Join-Path $stageRoot 'THIRD-PARTY-NOTICES.txt') -Force
    }

    $requiredFiles = @('tabame.exe', 'flutter_windows.dll', 'sqlite3.dll')
    foreach ($requiredFile in $requiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $stageRoot $requiredFile) -PathType Leaf)) {
            throw "Store installer staging is missing $requiredFile beside tabame.exe."
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $stageRoot 'data') -PathType Container)) {
        throw 'Store installer staging is missing the Flutter data directory.'
    }

    $outputDirectories = @(
        (Split-Path -Parent $installerFullPath),
        (Split-Path -Parent $shaFullPath),
        (Split-Path -Parent $manifestFullPath),
        (Split-Path -Parent $sbomFullPath),
        (Split-Path -Parent $metadataFullPath)
    ) | Where-Object { $_ }
    foreach ($directory in $outputDirectories) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    foreach ($output in @($installerFullPath, $shaFullPath, $manifestFullPath, $sbomFullPath, $metadataFullPath)) {
        if (Test-Path -LiteralPath $output -PathType Leaf) {
            Remove-Item -LiteralPath $output -Force
        }
    }

    $issPath = Join-Path $repoRootResolved 'packaging\windows\store-installer\Tabame.iss'
    if (-not (Test-Path -LiteralPath $issPath -PathType Leaf)) {
        throw "The Inno Setup source file was not found: $issPath"
    }
    $compiler = Get-InnoCompiler
    $outputBaseName = [System.IO.Path]::GetFileNameWithoutExtension($installerFullPath)
    $compilerArguments = @(
        "/DAppVersion=$appVersion",
        "/DVersionInfoVersion=$versionInfoVersion",
        "/DReleaseDir=$stageRoot",
        "/DOutputDir=$(Split-Path -Parent $installerFullPath)",
        "/DOutputBaseName=$outputBaseName",
        "/DRepoRoot=$repoRootResolved"
    )
    if (-not [string]::IsNullOrWhiteSpace($SignToolScriptPath)) {
        $signToolScriptResolved = (Resolve-Path -LiteralPath $SignToolScriptPath).Path
        $compilerArguments += "/DStoreSignToolScript=$signToolScriptResolved"
    }
    $compilerArguments += $issPath

    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup compilation failed with exit code $LASTEXITCODE."
    }
    if (-not (Test-Path -LiteralPath $installerFullPath -PathType Leaf)) {
        throw "Inno Setup did not create the expected installer: $installerFullPath"
    }

    $installerHash = Get-Sha256 $installerFullPath
    $hashLine = "$installerHash  $([System.IO.Path]::GetFileName($installerFullPath))"
    [System.IO.File]::WriteAllText($shaFullPath, $hashLine, [System.Text.UTF8Encoding]::new($false))

    $installedFiles = @(
        Get-ChildItem -LiteralPath $stageRoot -Recurse -File -Force |
            Sort-Object FullName |
            ForEach-Object {
                [ordered]@{
                    path = Get-RelativePath $stageRoot $_.FullName
                    size = $_.Length
                    sha256 = Get-Sha256 $_.FullName
                }
            }
    )

    $manifest = [ordered]@{
        schemaVersion = 1
        artifactType = 'storeInstaller'
        installerType = 'Inno Setup EXE'
        route = 'storeInstaller'
        appVersion = $appVersion
        packageVersion = $versionInfoVersion
        architecture = 'x64'
        minimumWindowsVersion = '10.0.19045'
        profile = 'storeInstaller'
        source = [ordered]@{
            commit = $CommitSha
            sourceDateEpoch = $epoch
            dartDependencyGraph = if ($DependencyJsonPath) { [System.IO.Path]::GetFileName($DependencyJsonPath) } else { $null }
        }
        installer = [ordered]@{
            file = [System.IO.Path]::GetFileName($installerFullPath)
            sha256 = $installerHash
            updateMode = 'in-place'
            closeApplications = 'force'
            restartApplications = $false
            silentInstallSwitches = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
            silentUninstallSwitches = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
            installExitCodes = @(0, 3010)
        }
        installRoot = '%LOCALAPPDATA%\Programs\Tabame'
        appDataRoot = '%LOCALAPPDATA%\Tabame'
        files = $installedFiles
    }
    Write-JsonNoBom $manifest $manifestFullPath

    $components = @(
        [ordered]@{
            type = 'application'
            name = 'Tabame'
            version = $appVersion
            'bom-ref' = 'pkg:generic/tabame@' + $appVersion
        }
    )
    if (-not [string]::IsNullOrWhiteSpace($DependencyJsonPath)) {
        if (-not (Test-Path -LiteralPath $DependencyJsonPath -PathType Leaf)) {
            throw "Dependency graph was not found: $DependencyJsonPath"
        }
        $dependencyGraph = Get-Content -LiteralPath $DependencyJsonPath -Raw | ConvertFrom-Json
        foreach ($package in @($dependencyGraph.packages)) {
            if ($package.name -and $package.version -and $package.name -ne 'tabame') {
                $components += [ordered]@{
                    type = 'library'
                    name = [string]$package.name
                    version = [string]$package.version
                    'bom-ref' = 'pkg:dart/' + [string]$package.name + '@' + [string]$package.version
                    purl = 'pkg:dart/' + [string]$package.name + '@' + [string]$package.version
                }
            }
        }
    }
    $sbom = [ordered]@{
        bomFormat = 'CycloneDX'
        specVersion = '1.5'
        version = 1
        metadata = [ordered]@{
            timestamp = [DateTimeOffset]::FromUnixTimeSeconds($epoch).ToString('o')
            component = [ordered]@{
                type = 'application'
                name = 'Tabame'
                version = $appVersion
            }
            properties = @(
                [ordered]@{ name = 'tabame.distribution-profile'; value = 'storeInstaller' }
                [ordered]@{ name = 'tabame.source-commit'; value = $CommitSha }
                [ordered]@{ name = 'tabame.installer-sha256'; value = $installerHash }
            )
        }
        components = $components
    }
    Write-JsonNoBom $sbom $sbomFullPath

    $partnerMetadata = [ordered]@{
        schemaVersion = 1
        route = 'storeInstaller'
        productName = 'Tabame'
        version = $appVersion
        installerType = 'EXE'
        architecture = 'x64'
        languages = @('en-US')
        minimumWindowsVersion = '10.0.19045'
        installerFile = [System.IO.Path]::GetFileName($installerFullPath)
        sha256 = $installerHash
        downloadUrl = $null
        downloadUrlStatus = 'REQUIRED_BEFORE_PARTNER_CENTER_SUBMISSION'
        silentInstallSwitches = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
        silentUninstallSwitches = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
        updateMode = 'in-place'
        closeApplications = 'force'
        restartApplications = $false
        installReturnCodes = @(0, 3010)
        installScope = 'per-user'
        sourceCommit = $CommitSha
        signing = [ordered]@{
            required = $true
            timestamped = $true
            certificateSecret = 'TABAME_STORE_SIGNING_CERTIFICATE_BASE64'
        }
    }
    Write-JsonNoBom $partnerMetadata $metadataFullPath

    Write-Output "Created $installerFullPath"
    Write-Output "Created $shaFullPath"
    Write-Output "Created $manifestFullPath"
    Write-Output "Created $sbomFullPath"
    Write-Output "Created $metadataFullPath"
}
finally {
    if ($ownsTemporaryStage -and $stageRoot -and (Test-Path -LiteralPath $stageRoot)) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force
    }
}
