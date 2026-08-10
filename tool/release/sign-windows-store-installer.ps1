[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$StageDir,

    [Parameter(Mandatory = $true)]
    [string]$CertificatePath,

    [Parameter(Mandatory = $true)]
    [string]$CertificatePassword,

    [Parameter(Mandatory = $false)]
    [string]$TimestampUrl = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'

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

function Test-PortableExecutable([System.IO.FileInfo]$File) {
    $stream = [System.IO.File]::OpenRead($File.FullName)
    try {
        return $stream.ReadByte() -eq 0x4d -and $stream.ReadByte() -eq 0x5a
    }
    finally {
        $stream.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $StageDir -PathType Container)) {
    throw "Store installer staging directory does not exist: $StageDir"
}
if (-not (Test-Path -LiteralPath $CertificatePath -PathType Leaf)) {
    throw "Signing certificate does not exist: $CertificatePath"
}
if ([string]::IsNullOrWhiteSpace($CertificatePassword)) {
    throw 'A signing certificate password is required.'
}
if ([string]::IsNullOrWhiteSpace($TimestampUrl)) {
    throw 'A timestamp URL is required.'
}

$signTool = Find-SignTool
$portableExtensions = @('.cpl', '.dll', '.exe', '.ocx', '.scr', '.sys')
$peFiles = @(Get-ChildItem -LiteralPath $StageDir -Recurse -File -Force |
    Where-Object { $portableExtensions -contains $_.Extension.ToLowerInvariant() } |
    Where-Object { Test-PortableExecutable $_ } |
    Sort-Object FullName)
if ($peFiles.Count -eq 0) {
    throw "No portable executable files were found in the staging directory: $StageDir"
}

foreach ($file in $peFiles) {
    & $signTool sign /fd SHA256 /td SHA256 /tr $TimestampUrl /f $CertificatePath /p $CertificatePassword $file.FullName
    if ($LASTEXITCODE -ne 0) {
        throw "signtool failed for $($file.FullName) with exit code $LASTEXITCODE."
    }
}

Write-Output "Signed $($peFiles.Count) staged PE file(s)."
