[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath
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

$certificatePath = [Environment]::GetEnvironmentVariable('TABAME_STORE_SIGNING_CERTIFICATE_PATH')
$certificatePassword = [Environment]::GetEnvironmentVariable('TABAME_STORE_SIGNING_CERTIFICATE_PASSWORD')
$timestampUrl = [Environment]::GetEnvironmentVariable('TABAME_STORE_TIMESTAMP_URL')
if ([string]::IsNullOrWhiteSpace($certificatePath) -or -not (Test-Path -LiteralPath $certificatePath -PathType Leaf)) {
    throw 'TABAME_STORE_SIGNING_CERTIFICATE_PATH is not a readable file.'
}
if ([string]::IsNullOrWhiteSpace($certificatePassword)) {
    throw 'TABAME_STORE_SIGNING_CERTIFICATE_PASSWORD is not set.'
}
if ([string]::IsNullOrWhiteSpace($timestampUrl)) {
    $timestampUrl = 'http://timestamp.digicert.com'
}

$resolvedFile = (Resolve-Path -LiteralPath $FilePath).Path
$signtool = Find-SignTool
& $signtool sign /fd SHA256 /td SHA256 /tr $timestampUrl /f $certificatePath /p $certificatePassword $resolvedFile
if ($LASTEXITCODE -ne 0) {
    throw "signtool failed for $resolvedFile with exit code $LASTEXITCODE."
}
