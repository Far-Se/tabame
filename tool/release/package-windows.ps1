[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDir,

    [Parameter(Mandatory = $true)]
    [string]$ZipPath,

    [Parameter(Mandatory = $true)]
    [string]$Sha256Path,

    [Parameter(Mandatory = $false)]
    [long]$SourceDateEpoch = 0
)

$ErrorActionPreference = 'Stop'

$releaseRoot = (Resolve-Path -LiteralPath $ReleaseDir).Path
if (-not (Test-Path -LiteralPath (Join-Path $releaseRoot 'tabame.exe') -PathType Leaf)) {
    throw "Windows release directory does not contain tabame.exe: $releaseRoot"
}

$sqliteDll = Join-Path $releaseRoot 'windows\sqlite3.dll'
if (Test-Path -LiteralPath $sqliteDll -PathType Leaf) {
    Move-Item -LiteralPath $sqliteDll -Destination (Join-Path $releaseRoot 'sqlite3.dll') -Force
}
else {
    Write-Warning "sqlite3.dll was not found in $releaseRoot\windows; continuing without moving it."
}

if ($SourceDateEpoch -le 0) {
    $environmentEpoch = [Environment]::GetEnvironmentVariable('SOURCE_DATE_EPOCH')
    if ($environmentEpoch -and $environmentEpoch -match '^[0-9]+$') {
        $SourceDateEpoch = [long]$environmentEpoch
    }
    else {
        $gitEpoch = (git -C (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) log -1 --format=%ct 2>$null).Trim()
        if ($gitEpoch -notmatch '^[0-9]+$') {
            throw 'SourceDateEpoch must be supplied or available from SOURCE_DATE_EPOCH/git.'
        }
        $SourceDateEpoch = [long]$gitEpoch
    }
}

$zipParent = Split-Path -Parent $ZipPath
$shaParent = Split-Path -Parent $Sha256Path
if ($zipParent) {
    New-Item -ItemType Directory -Path $zipParent -Force | Out-Null
}
if ($shaParent) {
    New-Item -ItemType Directory -Path $shaParent -Force | Out-Null
}

$zipPathResolved = [System.IO.Path]::GetFullPath($ZipPath)
$shaPathResolved = [System.IO.Path]::GetFullPath($Sha256Path)
if (Test-Path -LiteralPath $zipPathResolved) {
    Remove-Item -LiteralPath $zipPathResolved -Force
}
if (Test-Path -LiteralPath $shaPathResolved) {
    Remove-Item -LiteralPath $shaPathResolved -Force
}

Add-Type -AssemblyName System.IO.Compression
$zipStream = [System.IO.File]::Open($zipPathResolved, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
$archive = [System.IO.Compression.ZipArchive]::new($zipStream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
try {
    $zipTimestamp = [DateTimeOffset]::FromUnixTimeSeconds($SourceDateEpoch)
    $releaseFiles = Get-ChildItem -LiteralPath $releaseRoot -Recurse -File -Force |
        Sort-Object FullName
    foreach ($file in $releaseFiles) {
        $relativePath = $file.FullName.Substring($releaseRoot.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
        $entry = $archive.CreateEntry($relativePath, [System.IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = $zipTimestamp
        $input = [System.IO.File]::OpenRead($file.FullName)
        $output = $entry.Open()
        try {
            $input.CopyTo($output)
        }
        finally {
            $output.Dispose()
            $input.Dispose()
        }
    }
}
finally {
    $archive.Dispose()
    $zipStream.Dispose()
}

$hash = (Get-FileHash -LiteralPath $zipPathResolved -Algorithm SHA256).Hash.ToLowerInvariant()
$hashLine = "$hash  $([System.IO.Path]::GetFileName($zipPathResolved))"
[System.IO.File]::WriteAllText($shaPathResolved, $hashLine, [System.Text.UTF8Encoding]::new($false))

Write-Output "Created $zipPathResolved"
Write-Output "Created $shaPathResolved"
