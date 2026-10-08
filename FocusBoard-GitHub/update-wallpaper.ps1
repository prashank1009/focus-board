# Draws today's challenge wallpaper and applies it.
# -Popup : also show the daily check-in dialog (used at logon)
# -PreviewOnly <path> : render image to a path without changing the wallpaper
param(
    [switch]$Popup,
    [string]$PreviewOnly
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

if (-not (Test-Path $StreakConfigPath)) {
    [System.Windows.Forms.MessageBox]::Show('No challenge found. Open Focus Board to start one.', 'Focus Board') | Out-Null
    exit 1
}

if ($PreviewOnly) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-StreakWallpaper (Get-StreakConfig) (Get-StreakQuotes) $b.Width $b.Height
    $bmp.Save($PreviewOnly, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    exit 0
}

Update-StreakDesktop

# ---------- logon check-in ----------
$config = Get-StreakConfig
if (-not ($Popup -and $config.showCheckIn)) { exit 0 }
$p = Get-StreakProgress $config

if ($p.done) {
    [System.Windows.Forms.MessageBox]::Show("You completed all $($p.total) days! Open Focus Board to start a new challenge.", 'Challenge complete') | Out-Null
    exit 0
}
$msg = "Day $($p.dayNum) of $($p.total)`n$($p.passed) days done, $($p.remain) to go.`n`n$(Get-QuoteOfDay (Get-StreakQuotes))`n`nStill on track?"
$ans = [System.Windows.Forms.MessageBox]::Show($msg, 'Daily check-in', 'YesNo', 'Information')
if ($ans -eq 'No') {
    $confirm = [System.Windows.Forms.MessageBox]::Show("Restart the $($p.total)-day challenge from now?`nA slip is not the end - just begin again.", 'Restart?', 'YesNo', 'Question')
    if ($confirm -eq 'Yes') {
        Reset-StreakStart $config
        Save-StreakConfig $config
        Update-StreakDesktop
    }
}
