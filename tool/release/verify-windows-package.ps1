[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,

    [Parameter(Mandatory = $false)]
    [string]$Sha256Path
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
    throw "Windows package does not exist: $PackagePath"
}

if ($Sha256Path -and (Test-Path -LiteralPath $Sha256Path -PathType Leaf)) {
    $expected = (Get-Content -LiteralPath $Sha256Path -Raw).Trim().Split()[0].ToLowerInvariant()
    $actual = (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($expected -ne $actual) {
        throw "Windows package checksum mismatch. Expected $expected, got $actual."
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tabame-windows-smoke-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $tempRoot -Force
    $executable = Get-ChildItem -LiteralPath $tempRoot -Recurse -Filter 'tabame.exe' -File | Select-Object -First 1
    if (-not $executable) {
        throw "Windows package does not contain tabame.exe."
    }

    $releaseRoot = $executable.Directory.FullName
    foreach ($required in @('flutter_windows.dll', 'data')) {
        if (-not (Test-Path -LiteralPath (Join-Path $releaseRoot $required))) {
            throw "Windows package is missing $required beside tabame.exe."
        }
    }

    $nestedSqlite = Join-Path $releaseRoot 'windows\sqlite3.dll'
    $rootSqlite = Join-Path $releaseRoot 'sqlite3.dll'
    if (-not (Test-Path -LiteralPath $rootSqlite -PathType Leaf)) {
        if (Test-Path -LiteralPath $nestedSqlite -PathType Leaf) {
            throw 'Windows package contains sqlite3.dll only in the nested windows directory.'
        }
        throw 'Windows package is missing sqlite3.dll beside tabame.exe.'
    }

    Write-Output "Windows package layout smoke passed: $($executable.FullName)"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
