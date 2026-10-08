# Shared helpers for Focus Board: settings, messages, progress and wallpaper rendering.
# Dot-source this first: it makes the process DPI-aware before any window is created.

if (-not ('StreakNative' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class StreakNative {
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int SystemParametersInfo(int action, int param, string value, int flags);
    public static void MakeDpiAware() {
        try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return; } catch {}   // per-monitor v2
        SetProcessDPIAware();
    }
}
'@
}
[StreakNative]::MakeDpiAware()
Add-Type -AssemblyName System.Drawing, System.Windows.Forms

$StreakRoot       = $PSScriptRoot
$StreakConfigPath = Join-Path $StreakRoot 'config.json'
$StreakQuotesPath = Join-Path $StreakRoot 'quotes.txt'
$StreakWallDir    = Join-Path $StreakRoot 'generated'

$StreakDefaultQuotes = @(
    'Discipline is choosing what you want most over what you want now.',
    'Every urge you ride out makes the next one weaker.',
    'You are not your impulses. You are the one who watches them pass.',
    'The craving lasts minutes. The pride lasts all day.',
    'Small wins, stacked daily, build a different person.',
    'Your energy is precious. Spend it on what moves your life forward.',
    'Boredom is not an emergency. Get up, move, breathe.',
    'Clear mind, strong body, focused goals.',
    'You did not come this far to only come this far.',
    'Be the person your future self thanks.',
    'Urge hits? Walk, cold water, 20 push-ups. Then decide.',
    'Real confidence comes from keeping promises to yourself.',
    'One day at a time. Just win today.',
    'Comfort is the enemy of growth. Choose the harder, better path.',
    'Redirect the energy: train, build, learn, create.',
    'Late nights + phone in bed = danger zone. Phone out of the room.',
    'Feelings are visitors. Let them come and go.',
    'Self-control is a muscle. You are training it right now.',
    'Do not trade your long-term goals for a few seconds of nothing.',
    'Nobody is coming to save you. Good news: you do not need them to.',
    'Progress, not perfection. Keep showing up.',
    'You are rewiring your brain. It is uncomfortable because it is working.',
    'Your focus is your superpower. Protect it.',
    'Stay busy, stay outside, stay connected with real people.',
    'Pain of discipline weighs ounces. Pain of regret weighs tons.',
    'Win the morning, win the day.',
    'The streak is not the goal. The man you are becoming is.',
    'Hard choices, easy life. Easy choices, hard life.',
    'Look how far you have come. Do not stop now.',
    'Strength grows in the moments you think you can not go on.'
)

# ---------- settings ----------
function Get-StreakConfig {
    $now = Get-Date
    $c = [ordered]@{
        totalDays = 30; startDate = $now.ToString('yyyy-MM-dd'); startTime = $now.ToString('o')
        heading = 'STAY FOCUSED'; fontName = 'Segoe UI'
        accent = '#50C88C'; bgTop = '#0C1220'; bgBottom = '#1C1430'
        showProgress = $true; showStats = $true; showQuote = $true; showFooter = $true
        showTimer = $true; showCheckIn = $true
    }
    if (Test-Path $StreakConfigPath) {
        $saved = Get-Content $StreakConfigPath -Raw | ConvertFrom-Json
        foreach ($p in $saved.PSObject.Properties) { $c[$p.Name] = $p.Value }
        if (-not $saved.startTime) { $c.startTime = ([datetime]::ParseExact($c.startDate, 'yyyy-MM-dd', $null)).ToString('o') }
    }
    $c
}

function Save-StreakConfig($c) {
    [pscustomobject]$c | ConvertTo-Json | Set-Content $StreakConfigPath -Encoding UTF8
}

function Reset-StreakStart($c) {
    $now = Get-Date
    $c.startDate = $now.ToString('yyyy-MM-dd')
    $c.startTime = $now.ToString('o')
}

function Get-StreakQuotes {
    if (Test-Path $StreakQuotesPath) {
        $q = @(Get-Content $StreakQuotesPath -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($q.Count) { return $q }
    }
    $StreakDefaultQuotes
}

function Save-StreakQuotes([string[]]$lines) {
    $lines | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Set-Content $StreakQuotesPath -Encoding UTF8
}

function Get-QuoteOfDay($quotes) { $quotes[((Get-Date).Date - [datetime]'2000-01-01').Days % $quotes.Count] }

function Get-StreakProgress($c) {
    $start  = [datetime]::ParseExact($c.startDate, 'yyyy-MM-dd', $null)
    $total  = [int]$c.totalDays
    $today  = (Get-Date).Date
    $passed = [math]::Max(0, ($today - $start).Days)
    $done   = $passed -ge $total
    $passed = [math]::Min($passed, $total)
    @{ start = $start; total = $total; today = $today; passed = $passed; remain = $total - $passed
       dayNum = [math]::Min($passed + 1, $total); done = $done }
}

function Get-StreakTimerText($c) {
    $t = (Get-Date) - [datetime]::Parse($c.startTime)
    if ($t.Ticks -lt 0) { $t = [TimeSpan]::Zero }
    '{0}d  {1:00}h  {2:00}m  {3:00}s' -f [int][math]::Floor($t.TotalDays), $t.Hours, $t.Minutes, $t.Seconds
}

function ConvertTo-StreakColor([string]$hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }

# Live timer slot on the wallpaper (fractions of screen size), shared by the widget and the preview
$StreakTimerSlot = @{ widthFrac = 0.3; centerY = 700 / 1080; height = 110 / 1080; fontPx = 46 / 1080 }

# ---------- rendering ----------
function New-StreakWallpaper($c, $quotes, [int]$W, [int]$H) {
    $p = Get-StreakProgress $c
    $s = $H / 1080.0   # layout is designed at 1080p and scaled

    $bmp = New-Object System.Drawing.Bitmap $W, $H
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'

    $rect = New-Object System.Drawing.Rectangle 0, 0, $W, $H
    $g.FillRectangle((New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, (ConvertTo-StreakColor $c.bgTop), (ConvertTo-StreakColor $c.bgBottom), 60), $rect)

    $accent = ConvertTo-StreakColor $c.accent
    $accentB = New-Object System.Drawing.SolidBrush $accent
    $white  = [System.Drawing.Brushes]::White
    $muted  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(160, 170, 190))
    $center = New-Object System.Drawing.StringFormat
    $center.Alignment = 'Center'; $center.LineAlignment = 'Center'
    $fontName = $c.fontName
    $font = { param($size, $style = 'Regular') New-Object System.Drawing.Font $fontName, ([float]($size * $s)), ([System.Drawing.FontStyle]$style), ([System.Drawing.GraphicsUnit]::Pixel) }
    $box  = { param($y, $h) New-Object System.Drawing.RectangleF ([float]($W * 0.1)), ([float]($y * $s)), ([float]($W * 0.8)), ([float]($h * $s)) }

    if ($p.done) {
        $g.DrawString('CHALLENGE COMPLETE', (& $font 40 'Bold'), $accentB, (& $box 260 60), $center)
        $g.DrawString("$($p.total) / $($p.total) days", (& $font 150 'Bold'), $white, (& $box 340 200), $center)
        $g.DrawString('You kept your promise. Start a new, longer challenge.', (& $font 34), $muted, (& $box 560 60), $center)
    } else {
        if ($c.heading) { $g.DrawString($c.heading, (& $font 32 'Bold'), $accentB, (& $box 200 50), $center) }
        $g.DrawString("DAY $($p.dayNum)", (& $font 170 'Bold'), $white, (& $box 260 220), $center)
        $g.DrawString("of $($p.total)", (& $font 40), $muted, (& $box 470 60), $center)
        if ($c.showProgress) {
            $barW = $W * 0.5; $barH = 18 * $s; $barX = ($W - $barW) / 2; $barY = 560 * $s
            $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(60, 255, 255, 255))), [float]$barX, [float]$barY, [float]$barW, [float]$barH)
            if ($p.passed -gt 0) { $g.FillRectangle($accentB, [float]$barX, [float]$barY, [float]($barW * $p.passed / $p.total), [float]$barH) }
        }
        if ($c.showStats) {
            $g.DrawString("$($p.passed) days done   |   $($p.remain) days remaining", (& $font 36 'Bold'), $white, (& $box 600 60), $center)
        }
    }
    if ($c.showQuote) {
        $g.DrawString([char]0x201C + (Get-QuoteOfDay $quotes) + [char]0x201D, (& $font 38 'Italic'), $white, (& $box 790 160), $center)
    }
    if ($c.showFooter) {
        $g.DrawString("Started $($p.start.ToString('dd MMM yyyy'))   -   Today $($p.today.ToString('dddd, dd MMM yyyy'))", (& $font 22), $muted, (& $box 980 40), $center)
    }
    $g.Dispose()
    $bmp
}

function Set-StreakWallpaper($bmp) {
    New-Item -ItemType Directory -Force $StreakWallDir | Out-Null
    Get-ChildItem $StreakWallDir -Filter '*.png' | Remove-Item -Force -ErrorAction SilentlyContinue
    # Unique filename so Windows doesn't serve a cached wallpaper
    $file = Join-Path $StreakWallDir ("wallpaper-{0}.png" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10'   # Fill
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name TileWallpaper  -Value '0'
    [StreakNative]::SystemParametersInfo(0x0014, 0, $file, 0x01 -bor 0x02) | Out-Null
}

function Update-StreakDesktop {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-StreakWallpaper (Get-StreakConfig) (Get-StreakQuotes) $b.Width $b.Height
    Set-StreakWallpaper $bmp
    $bmp.Dispose()
}

function Start-StreakTimer {
    # The widget allows only one copy, so this is safe to call repeatedly
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$(Join-Path $StreakRoot 'timer-widget.ps1')`""
}

# ---------- adult-site blocking (DNS) ----------
# True when every connected adapter uses the Cloudflare for Families resolver
function Test-StreakDnsBlock {
    $up = @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' })
    if (-not $up.Count) { return $false }
    foreach ($a in $up) {
        $dns = (Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4).ServerAddresses
        if ($dns -notcontains '1.1.1.3') { return $false }
    }
    $true
}

# Runs dns-block.ps1 as admin (shows the Windows UAC prompt). Returns $true on success.
function Set-StreakDnsBlock([bool]$on) {
    $mode = if ($on) { 'On' } else { 'Off' }
    try {
        $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -WindowStyle Hidden `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $StreakRoot 'dns-block.ps1')`" -Mode $mode"
        $p.ExitCode -eq 0
    } catch { $false }   # UAC prompt was declined
}

# ---------- sharing ----------
# Zips the app without personal data (settings, messages, generated wallpapers). Returns the zip path.
function New-StreakSharePackage {
    $files = 'common.ps1', 'focus-board.ps1', 'setup.ps1', 'uninstall.ps1', 'update-wallpaper.ps1',
             'timer-widget.ps1', 'dns-block.ps1', 'install.bat', 'README.txt', 'LICENSE'
    $zip = Join-Path ([Environment]::GetFolderPath('Desktop')) 'FocusBoard.zip'
    $stage = Join-Path $env:TEMP 'FocusBoard'
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory $stage | Out-Null
    foreach ($f in $files) { Copy-Item (Join-Path $StreakRoot $f) $stage }
    Compress-Archive -Path $stage -DestinationPath $zip -Force
    Remove-Item $stage -Recurse -Force
    $zip
}

# App icon: green progress ring with an upward chevron on a dark rounded tile
function New-StreakIconBitmap([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $r = $size * 0.2
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $r, $r, 180, 90); $path.AddArc($size - $r - 1, 0, $r, $r, 270, 90)
    $path.AddArc($size - $r - 1, $size - $r - 1, $r, $r, 0, 90); $path.AddArc(0, $size - $r - 1, $r, $r, 90, 90)
    $path.CloseFigure()
    $rect = New-Object System.Drawing.Rectangle 0, 0, $size, $size
    $g.FillPath((New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.Color]::FromArgb(18, 26, 46)), ([System.Drawing.Color]::FromArgb(40, 28, 68)), 60), $path)
    $m = $size * 0.16; $d = $size - 2 * $m; $w = [float]($size * 0.09)
    $track = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(60, 255, 255, 255)), $w
    $ring  = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(80, 200, 140)), $w
    $ring.StartCap = 'Round'; $ring.EndCap = 'Round'
    $g.DrawEllipse($track, [float]$m, [float]$m, [float]$d, [float]$d)
    $g.DrawArc($ring, [float]$m, [float]$m, [float]$d, [float]$d, -90, 270)
    $chev = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), ([float]($size * 0.08))
    $chev.StartCap = 'Round'; $chev.EndCap = 'Round'; $chev.LineJoin = 'Round'
    $cx = $size / 2
    $g.DrawLines($chev, [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF ([float]($cx - $size * 0.13)), ([float]($size * 0.56))),
        (New-Object System.Drawing.PointF ([float]$cx), ([float]($size * 0.42))),
        (New-Object System.Drawing.PointF ([float]($cx + $size * 0.13)), ([float]($size * 0.56)))))
    $g.Dispose()
    $bmp
}

function Save-StreakIcon([string]$path) {
    # .ico holding a single 256px PNG image (supported by Windows Vista and later)
    $bmp = New-StreakIconBitmap 256
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    $png = $ms.ToArray()
    $bw = New-Object System.IO.BinaryWriter ([System.IO.File]::Create($path))
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]1)          # header: icon, 1 image
    $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0)   # 256x256, no palette
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$png.Length); $bw.Write([uint32]22)
    $bw.Write($png)
    $bw.Close()
}
