# Run Flutter build command
Start-Process "flutter" "build windows" -NoNewWindow -Wait

# Close the application tabame.exe if it's running
$process = Get-Process -Name "tabame" -ErrorAction SilentlyContinue
if ($process) {
    Stop-Process -Name "tabame" -Force
    Write-Output "tabame.exe has been closed."
} else {
    Write-Output "tabame.exe is not running."
}

$destinationPath = "C:\Users\Far Se\AppData\Local\Tabame"
$sourcePath = "E:\Projects\tabame\build\windows\runner\Release"

# Ensure the destination directory exists
if (-Not (Test-Path -Path $destinationPath)) {
    New-Item -ItemType Directory -Path $destinationPath
}

# Perform the copy operation
Copy-Item -Path "$sourcePath\*" -Destination $destinationPath -Recurse -Force

Write-Output "Files have been copied from E:\Tabame to C:\Tabame."

$tabameExecutable = Join-Path -Path $destinationPath -ChildPath "tabame.exe"
if (Test-Path -Path $tabameExecutable) {
    Start-Process -FilePath $tabameExecutable
    Write-Output "tabame.exe has been started from $destinationPath."
} else {
    Write-Output "tabame.exe was not found in $destinationPath."
}