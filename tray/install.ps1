# Starts Claude Usage Tray now and, with -Startup, every time you sign in to Windows.
#   powershell -ExecutionPolicy Bypass -File install.ps1 [-Startup] [-Uninstall]
param([switch]$Startup, [switch]$Uninstall)

$script = Join-Path $PSScriptRoot 'ClaudeUsageTray.ps1'
$shortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'Claude Usage Tray.lnk'
# Through a headless console host: when Windows Terminal is the default terminal,
# a plain powershell.exe opens as a Terminal tab that -WindowStyle Hidden cannot hide.
$conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
$arguments = "--headless `"$((Get-Command powershell.exe).Source)`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""

if ($Uninstall) {
    Remove-Item $shortcut -ErrorAction SilentlyContinue
    # Only the tray app itself: started with -File on this exact script
    # (conhost passes the path on without its quotes).
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.TrimEnd().Replace('"', '').EndsWith("-File $script") } |
        ForEach-Object { Stop-Process -Id $_.ProcessId }
    Write-Output 'Claude Usage Tray removed.'
    return
}

if ($Startup) {
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($shortcut)
    $link.TargetPath = $conhost
    $link.Arguments = $arguments
    $link.WindowStyle = 7
    $link.Description = 'Shows Claude usage in the taskbar'
    $link.Save()
    Write-Output "Starts at sign-in: $shortcut"
}

Start-Process $conhost -ArgumentList $arguments -WindowStyle Hidden
Write-Output 'Claude Usage Tray is running. If its icons are hidden, drag them from the ^ overflow onto the taskbar.'
