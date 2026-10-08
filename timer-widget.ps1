# Live streak timer on the desktop: sits just above the wallpaper, below all apps, survives Win+D.
# Its background is the matching patch of the wallpaper, so it looks painted on.
# Follows config.json (start time, font, accent colour, show/hide) and the current wallpaper live.
$ErrorActionPreference = 'Stop'

# Only one copy at a time
$mutex = New-Object System.Threading.Mutex $false, 'Local\StreakTimerWidget'
if (-not $mutex.WaitOne(0)) { exit 0 }

. (Join-Path $PSScriptRoot 'common.ps1')   # also makes us DPI-aware, so positions line up with the wallpaper

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Desk {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string cls, string name);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] static extern IntPtr GetWindowLongPtr(IntPtr h, int idx);
    [DllImport("user32.dll")] static extern IntPtr SetWindowLongPtr(IntPtr h, int idx, IntPtr val);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);

    // Turn h into a desktop widget: no taskbar/Alt+Tab entry, never takes focus,
    // owned by the desktop window so it survives Win+D
    public static void Setup(IntPtr h) {
        long ex = GetWindowLongPtr(h, -20).ToInt64() | 0x80 | 0x08000000;   // TOOLWINDOW | NOACTIVATE
        SetWindowLongPtr(h, -20, new IntPtr(ex));
        SetWindowLongPtr(h, -8, FindWindow("Progman", null));               // owner = desktop
        KeepBehindApps(h);
    }

    // Keep h directly above the desktop and below every app window
    public static void KeepBehindApps(IntPtr h) {
        IntPtr progman = FindWindow("Progman", null);
        IntPtr above = GetWindow(progman, 3);   // GW_HWNDPREV: window just above the desktop
        if (above == h || above == IntPtr.Zero) return;
        SetWindowPos(h, above, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010);   // NOSIZE | NOMOVE | NOACTIVATE
    }
}
'@

# Geometry in physical screen pixels (slot reserved on the wallpaper)
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$W = $screen.Width; $H = $screen.Height
$fw = [int]($W * $StreakTimerSlot.widthFrac); $fh = [int]($H * $StreakTimerSlot.height)
$fx = $screen.X + [int](($W - $fw) / 2); $fy = $screen.Y + [int]($H * $StreakTimerSlot.centerY - $fh / 2)

$center = New-Object System.Drawing.StringFormat
$center.Alignment = 'Center'; $center.LineAlignment = 'Center'
$script:cfg = $null; $script:configStamp = $null
$script:font = $null; $script:brush = $null
$script:wall = $null; $script:wallName = $null

function Sync-Config {
    if (-not (Test-Path $StreakConfigPath)) { return }
    $stamp = (Get-Item $StreakConfigPath).LastWriteTime
    if ($stamp -eq $script:configStamp) { return }
    $script:configStamp = $stamp
    $script:cfg   = Get-StreakConfig
    $script:font  = New-Object System.Drawing.Font $script:cfg.fontName, ([float]($H * $StreakTimerSlot.fontPx)), ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
    $script:brush = New-Object System.Drawing.SolidBrush (ConvertTo-StreakColor $script:cfg.accent)
}

function Sync-Wallpaper {
    $f = Get-ChildItem $StreakWallDir -Filter '*.png' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
    if (-not $f -or $f.Name -eq $script:wallName) { return }
    $img = [System.Drawing.Image]::FromFile($f.FullName)
    if ($script:wall) { $script:wall.Dispose() }
    $script:wall = New-Object System.Drawing.Bitmap $img   # copy, so the file isn't locked
    $img.Dispose()
    $script:wallName = $f.Name
}

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = 'None'
$form.ShowInTaskbar   = $false
$form.StartPosition   = 'Manual'
$form.BackColor       = [System.Drawing.Color]::FromArgb(20, 19, 40)
$form.SetBounds($fx, $fy, $fw, $fh)
$pic = New-Object System.Windows.Forms.PictureBox
$pic.Dock = 'Fill'
$form.Controls.Add($pic)

function Show-Timer {
    Sync-Config; Sync-Wallpaper
    $visible = $script:cfg -and $script:cfg.showTimer
    if ($form.Visible -ne $visible) { $form.Visible = $visible }
    if (-not $visible) { return }

    $bmp = New-Object System.Drawing.Bitmap $fw, $fh
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.TextRenderingHint = 'AntiAliasGridFit'
    if ($script:wall) {
        $sc  = $script:wall.Width / $W
        $src = New-Object System.Drawing.RectangleF ([float](($fx - $screen.X) * $sc)), ([float](($fy - $screen.Y) * $sc)), ([float]($fw * $sc)), ([float]($fh * $sc))
        $g.DrawImage($script:wall, (New-Object System.Drawing.RectangleF 0, 0, $fw, $fh), $src, 'Pixel')
    } else { $g.Clear($form.BackColor) }
    $g.DrawString((Get-StreakTimerText $script:cfg), $script:font, $script:brush, (New-Object System.Drawing.RectangleF 0, 0, $fw, $fh), $center)
    $g.Dispose()
    $old = $pic.Image; $pic.Image = $bmp
    if ($old) { $old.Dispose() }
}

$form.Add_Shown({ [Desk]::Setup($form.Handle) })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    try { Show-Timer; if ($form.Visible) { [Desk]::KeepBehindApps($form.Handle) } } catch {}   # e.g. wallpaper mid-rewrite; retry next second
})
$timer.Start()

[System.Windows.Forms.Application]::Run($form)
$mutex.ReleaseMutex()
