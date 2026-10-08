# Installs Focus Board: desktop icon, login autostart, daily wallpaper refresh. Then opens the app.
# Safe to re-run: it never resets your challenge or your design.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$ps     = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$hidden = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File'
$icon   = Join-Path $StreakRoot 'icon.ico'
Save-StreakIcon $icon

$wsh = New-Object -ComObject WScript.Shell
function New-Shortcut([string]$path, [string]$script, [string]$extraArgs = '') {
    $l = $wsh.CreateShortcut($path)
    $l.TargetPath = $ps
    $l.Arguments = "$hidden `"$(Join-Path $StreakRoot $script)`" $extraArgs".Trim()
    $l.WorkingDirectory = $StreakRoot
    $l.IconLocation = "$icon,0"
    $l.WindowStyle = 7
    $l.Save()
}

# Desktop icon to open the designer
New-Shortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Focus Board.lnk') 'focus-board.ps1'

# At login (Startup folder, no admin needed): wallpaper + check-in, and the live timer
$startup = [Environment]::GetFolderPath('Startup')
New-Shortcut (Join-Path $startup 'Streak Wallpaper.lnk') 'update-wallpaper.ps1' '-Popup'
New-Shortcut (Join-Path $startup 'Streak Timer.lnk') 'timer-widget.ps1'

# Every day just after midnight (and on wake if missed): refresh wallpaper
$action   = New-ScheduledTaskAction -Execute $ps -Argument "$hidden `"$(Join-Path $StreakRoot 'update-wallpaper.ps1')`""
$trigger  = New-ScheduledTaskTrigger -Daily -At '00:01'
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName 'StreakWallpaperDaily' -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null

if (Test-Path $StreakConfigPath) {
    Update-StreakDesktop
    if ((Get-StreakConfig).showTimer) { Start-StreakTimer }
}

Start-Process $ps -ArgumentList "$hidden `"$(Join-Path $StreakRoot 'focus-board.ps1')`""
