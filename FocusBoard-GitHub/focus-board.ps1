# Focus Board: design what your desktop shows and manage the challenge.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:cfg = Get-StreakConfig
$isNew = -not (Test-Path $StreakConfigPath)

# ---------- layout helpers ----------
# Layout is written at 96 DPI and scaled to the screen's DPI (e.g. 1.25 at 125%)
$probe = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $k = $probe.DpiX / 96; $probe.Dispose()
function Add-Control($parent, $ctl, [int]$x, [int]$y, [int]$w, [int]$h) {
    $ctl.SetBounds([int]($x * $k), [int]($y * $k), [int]($w * $k), [int]($h * $k))
    $parent.Controls.Add($ctl)
    $ctl
}
function New-Label([string]$text) { $l = New-Object System.Windows.Forms.Label; $l.Text = $text; $l.AutoSize = $false; $l }
function New-Group([string]$text) { $g = New-Object System.Windows.Forms.GroupBox; $g.Text = $text; $g }

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Focus Board'
$form.AutoScaleMode = 'None'
$form.Font = New-Object System.Drawing.Font 'Segoe UI', 9
$form.ClientSize = New-Object System.Drawing.Size ([int](1100 * $k)), ([int](600 * $k))
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$iconBmp = New-StreakIconBitmap 64
$form.Icon = [System.Drawing.Icon]::FromHandle($iconBmp.GetHicon())

# ---------- challenge ----------
$gChallenge = Add-Control $form (New-Group 'Challenge') 12 8 410 118
Add-Control $gChallenge (New-Label 'Length (days)') 14 28 110 22 | Out-Null
$numDays = Add-Control $gChallenge (New-Object System.Windows.Forms.NumericUpDown) 130 25 80 24
$numDays.Minimum = 1; $numDays.Maximum = 3650; $numDays.Value = [int]$script:cfg.totalDays
$lblStatus = Add-Control $gChallenge (New-Label '') 14 56 385 22
$lblStatus.ForeColor = [System.Drawing.Color]::DimGray
$btnRestart = Add-Control $gChallenge (New-Object System.Windows.Forms.Button) 14 80 200 28
$btnRestart.Text = 'Restart streak from now'

# ---------- look ----------
$gLook = Add-Control $form (New-Group 'Look') 12 132 410 128
Add-Control $gLook (New-Label 'Heading') 14 28 80 22 | Out-Null
$txtHeading = Add-Control $gLook (New-Object System.Windows.Forms.TextBox) 100 25 295 24
$txtHeading.Text = $script:cfg.heading
Add-Control $gLook (New-Label 'Font') 14 60 80 22 | Out-Null
$cmbFont = Add-Control $gLook (New-Object System.Windows.Forms.ComboBox) 100 57 295 24
$cmbFont.DropDownStyle = 'DropDownList'
[System.Drawing.FontFamily]::Families | ForEach-Object { [void]$cmbFont.Items.Add($_.Name) }
$cmbFont.SelectedItem = $script:cfg.fontName
if ($cmbFont.SelectedIndex -lt 0) { $cmbFont.SelectedItem = 'Segoe UI' }
Add-Control $gLook (New-Label 'Colours') 14 94 80 22 | Out-Null

function New-ColorButton([string]$text, [string]$key, [int]$x) {
    $b = Add-Control $gLook (New-Object System.Windows.Forms.Button) $x 89 95 28
    $b.Text = $text; $b.Tag = $key; $b.FlatStyle = 'Flat'
    Set-ButtonColor $b $script:cfg[$key]
    $b.Add_Click({
        $dlg = New-Object System.Windows.Forms.ColorDialog
        $dlg.FullOpen = $true; $dlg.Color = ConvertTo-StreakColor $script:cfg[$this.Tag]
        if ($dlg.ShowDialog() -eq 'OK') {
            $script:cfg[$this.Tag] = '#{0:X2}{1:X2}{2:X2}' -f $dlg.Color.R, $dlg.Color.G, $dlg.Color.B
            Set-ButtonColor $this $script:cfg[$this.Tag]
            Update-Preview
        }
    })
    $b
}
function Set-ButtonColor($b, [string]$hex) {
    $c = ConvertTo-StreakColor $hex
    $b.BackColor = $c
    $b.ForeColor = if ($c.GetBrightness() -gt 0.55) { [System.Drawing.Color]::Black } else { [System.Drawing.Color]::White }
}
New-ColorButton 'Accent' 'accent' 100 | Out-Null
New-ColorButton 'Background 1' 'bgTop' 200 | Out-Null
New-ColorButton 'Background 2' 'bgBottom' 300 | Out-Null

# ---------- what to show ----------
$gShow = Add-Control $form (New-Group 'Show on desktop') 12 266 410 106
$checks = @{}
$items = @(
    @('showProgress', 'Progress bar', 14, 24), @('showStats', 'Days done / remaining', 210, 24),
    @('showQuote', 'Daily message', 14, 50),   @('showFooter', 'Dates line', 210, 50),
    @('showTimer', 'Live timer', 14, 76),      @('showCheckIn', 'Check-in popup at login', 210, 76)
)
foreach ($i in $items) {
    $cb = Add-Control $gShow (New-Object System.Windows.Forms.CheckBox) $i[2] $i[3] 190 24
    $cb.Text = $i[1]; $cb.Checked = [bool]$script:cfg[$i[0]]
    $checks[$i[0]] = $cb
}

# ---------- messages ----------
$gMsgs = Add-Control $form (New-Group 'Daily messages (one per line, a new one each day)') 12 378 410 202
$txtQuotes = Add-Control $gMsgs (New-Object System.Windows.Forms.TextBox) 14 24 382 166
$txtQuotes.Multiline = $true; $txtQuotes.ScrollBars = 'Vertical'; $txtQuotes.WordWrap = $false
$txtQuotes.Lines = [string[]](Get-StreakQuotes)

# ---------- preview + actions ----------
Add-Control $form (New-Label 'Preview') 440 12 200 20 | Out-Null
$pic = Add-Control $form (New-Object System.Windows.Forms.PictureBox) 440 34 648 365
$pic.SizeMode = 'Zoom'; $pic.BorderStyle = 'FixedSingle'
$lblHint = Add-Control $form (New-Label 'The preview updates as you edit. Nothing changes on your desktop until you click Apply.') 440 406 648 40
$lblHint.ForeColor = [System.Drawing.Color]::DimGray

$gBlock = Add-Control $form (New-Group 'Adult-site blocking (DNS)') 440 446 648 80
$lblBlock = Add-Control $gBlock (New-Label '') 14 32 330 24
$lblBlock.Font = New-Object System.Drawing.Font 'Segoe UI', 9, ([System.Drawing.FontStyle]::Bold)
$btnBlock = Add-Control $gBlock (New-Object System.Windows.Forms.Button) 350 26 140 32
$btnBlock.Text = 'Block adult sites'
$btnUnblock = Add-Control $gBlock (New-Object System.Windows.Forms.Button) 496 26 138 32
$btnUnblock.Text = 'Unblock'

$btnApply = Add-Control $form (New-Object System.Windows.Forms.Button) 440 540 220 40
$btnApply.Text = 'Apply to desktop'
$btnApply.Font = New-Object System.Drawing.Font 'Segoe UI', 10, ([System.Drawing.FontStyle]::Bold)
$btnShare = Add-Control $form (New-Object System.Windows.Forms.Button) 668 540 120 40
$btnShare.Text = 'Share...'
$lblApplied = Add-Control $form (New-Label '') 798 550 290 40
$lblApplied.ForeColor = [System.Drawing.Color]::SeaGreen

# ---------- behaviour ----------
function Read-Form {
    $script:cfg.totalDays = [int]$numDays.Value
    $script:cfg.heading   = $txtHeading.Text
    $script:cfg.fontName  = [string]$cmbFont.SelectedItem
    foreach ($k in $checks.Keys) { $script:cfg[$k] = $checks[$k].Checked }
}

function Update-Status {
    $p = Get-StreakProgress $script:cfg
    $started = ([datetime]::Parse($script:cfg.startTime)).ToString('dd MMM yyyy, h:mm tt')
    $lblStatus.Text = if ($p.done) { "Completed! Started $started" } else { "Day $($p.dayNum) of $($p.total)  -  started $started" }
}

function Update-Preview {
    Read-Form
    Update-Status
    $quotes = @($txtQuotes.Lines | Where-Object { $_.Trim() })
    if (-not $quotes.Count) { $quotes = @(' ') }
    $W = 1280; $H = 720
    $bmp = New-StreakWallpaper $script:cfg $quotes $W $H
    if ($script:cfg.showTimer) {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.TextRenderingHint = 'AntiAliasGridFit'
        $font = New-Object System.Drawing.Font $script:cfg.fontName, ([float]($H * $StreakTimerSlot.fontPx)), ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
        $fmt = New-Object System.Drawing.StringFormat; $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
        $rect = New-Object System.Drawing.RectangleF 0, ([float]($H * ($StreakTimerSlot.centerY - $StreakTimerSlot.height / 2))), $W, ([float]($H * $StreakTimerSlot.height))
        $g.DrawString((Get-StreakTimerText $script:cfg), $font, (New-Object System.Drawing.SolidBrush (ConvertTo-StreakColor $script:cfg.accent)), $rect, $fmt)
        $g.Dispose()
    }
    $old = $pic.Image; $pic.Image = $bmp
    if ($old) { $old.Dispose() }
}

$numDays.Add_ValueChanged({ Update-Preview })
$txtHeading.Add_TextChanged({ Update-Preview })
$cmbFont.Add_SelectedIndexChanged({ Update-Preview })
$txtQuotes.Add_TextChanged({ Update-Preview })
foreach ($cb in $checks.Values) { $cb.Add_CheckedChanged({ Update-Preview }) }

$btnRestart.Add_Click({
    $ans = [System.Windows.Forms.MessageBox]::Show("Restart the streak from now?`nThe day count and live timer go back to zero.", 'Restart streak', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    Read-Form
    Reset-StreakStart $script:cfg
    Save-StreakConfig $script:cfg
    Update-StreakDesktop
    Update-Preview
    $lblApplied.Text = "Streak restarted at $((Get-Date).ToString('h:mm tt'))."
})

$btnApply.Add_Click({
    $form.Cursor = 'WaitCursor'
    try {
        Read-Form
        Save-StreakConfig $script:cfg
        Save-StreakQuotes $txtQuotes.Lines
        Update-StreakDesktop
        if ($script:cfg.showTimer) { Start-StreakTimer }
        $lblApplied.Text = "Desktop updated at $((Get-Date).ToString('h:mm tt'))."
    } finally { $form.Cursor = 'Default' }
})

function Update-BlockStatus {
    $on = $false
    try { $on = Test-StreakDnsBlock } catch {}
    if ($on) {
        $lblBlock.Text = 'ON - adult sites are blocked'; $lblBlock.ForeColor = [System.Drawing.Color]::SeaGreen
    } else {
        $lblBlock.Text = 'OFF - adult sites are not blocked'; $lblBlock.ForeColor = [System.Drawing.Color]::Firebrick
    }
    $btnBlock.Enabled = -not $on; $btnUnblock.Enabled = $on
}

$btnBlock.Add_Click({
    $form.Cursor = 'WaitCursor'
    try {
        if (Set-StreakDnsBlock $true) { $lblApplied.Text = 'Adult sites blocked. Restart your browser.' }
        else { $lblApplied.Text = 'Blocking was not turned on (admin permission needed).' }
    } finally { $form.Cursor = 'Default'; Update-BlockStatus }
})

$btnUnblock.Add_Click({
    # A little friction for weak moments
    Add-Type -AssemblyName Microsoft.VisualBasic
    $phrase = 'I choose to unblock'
    $typed = [Microsoft.VisualBasic.Interaction]::InputBox("Turning protection off. Pause and think about why you started.`n`nTo continue, type exactly:`n$phrase", 'Unblock')
    if ($typed -cne $phrase) { return }
    $form.Cursor = 'WaitCursor'
    try {
        if (-not (Set-StreakDnsBlock $false)) { return }
        if (Test-StreakDnsBlock) {
            # The family DNS was also chosen in Windows Settings; Focus Board leaves the user's own setting alone
            $lblApplied.Text = 'Still blocked by your Windows network settings.'
            [System.Windows.Forms.MessageBox]::Show("Focus Board's blocking is off, but this network is also set to the family DNS in Windows Settings, so sites stay blocked.`n`nTo change that: Settings > Network & internet > Wi-Fi > Hardware properties > DNS server assignment > Edit.", 'Unblock') | Out-Null
        } else { $lblApplied.Text = 'Blocking turned off.' }
    } finally { $form.Cursor = 'Default'; Update-BlockStatus }
})

$btnShare.Add_Click({
    $form.Cursor = 'WaitCursor'
    try {
        $zip = New-StreakSharePackage
        $lblApplied.Text = 'FocusBoard.zip saved to your Desktop.'
        Start-Process explorer.exe "/select,`"$zip`""
    } finally { $form.Cursor = 'Default' }
})

# Keep the preview's timer ticking
$tick = New-Object System.Windows.Forms.Timer
$tick.Interval = 1000
$tick.Add_Tick({ if ($script:cfg.showTimer -and $form.ContainsFocus) { Update-Preview } })
$tick.Start()

$form.Add_Shown({
    Update-Preview
    Update-BlockStatus
    if ($isNew) { $lblApplied.Text = 'New challenge - set it up, then click Apply.' }
})
[System.Windows.Forms.Application]::Run($form)
