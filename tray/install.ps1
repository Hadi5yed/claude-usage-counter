# Starts Claude Usage Tray now and, with -Startup, every time you sign in to Windows.
#   powershell -ExecutionPolicy Bypass -File install.ps1 [-Startup] [-Uninstall]
param([switch]$Startup, [switch]$Uninstall)

$script = Join-Path $PSScriptRoot 'ClaudeUsageTray.ps1'
$shortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'Claude Usage Tray.lnk'
$arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""

if ($Uninstall) {
    Remove-Item $shortcut -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -like '*ClaudeUsageTray.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId }
    Write-Output 'Claude Usage Tray removed.'
    return
}

if ($Startup) {
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($shortcut)
    $link.TargetPath = (Get-Command powershell.exe).Source
    $link.Arguments = $arguments
    $link.WindowStyle = 7
    $link.Description = 'Shows Claude usage in the taskbar'
    $link.Save()
    Write-Output "Starts at sign-in: $shortcut"
}

Start-Process powershell.exe -ArgumentList $arguments -WindowStyle Hidden
Write-Output 'Claude Usage Tray is running. If its icons are hidden, drag them from the ^ overflow onto the taskbar.'
