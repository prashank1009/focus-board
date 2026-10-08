# Removes the desktop icon, login shortcuts, the daily task and the running timer.
# Your settings and wallpaper stay as-is; run setup.ps1 to reinstall.
$startup = [Environment]::GetFolderPath('Startup')
Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Focus Board.lnk') -ErrorAction SilentlyContinue
Remove-Item (Join-Path $startup 'Streak Wallpaper.lnk') -ErrorAction SilentlyContinue
Remove-Item (Join-Path $startup 'Streak Timer.lnk') -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'StreakWallpaperDaily' -Confirm:$false -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*timer-widget.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Write-Host 'Focus Board removed.'
