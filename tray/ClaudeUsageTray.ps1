# Claude Usage Tray: shows the usage-counter mod's figures as taskbar icons,
# one number per rate-limit window (5-hour and weekly), like HWiNFO's sensors.
# Reads %USERPROFILE%\.claude\usage-counter\usage.json, which the mod writes.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace ClaudeUsage -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool DestroyIcon(System.IntPtr handle);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetProcessDPIAware();
'@
# Sharp icons on scaled displays: SmallIconSize then reports the real tray size.
[ClaudeUsage.Native]::SetProcessDPIAware() | Out-Null

$created = $false
# ::new, not New-Object: New-Object never writes back through [ref].
$mutex = [System.Threading.Mutex]::new($true, 'Local\ClaudeUsageTray', [ref]$created)
if (-not $created) { exit }

$UsageFile = Join-Path $env:USERPROFILE '.claude\usage-counter\usage.json'
$Windows = @(
    @{ Kind = 'five_hour'; Label = '5-hour' },
    @{ Kind = 'seven_day'; Label = 'Weekly' }
)

function Get-Countdown([string]$resetsAt) {
    $at = [DateTimeOffset]::MinValue
    if (-not $resetsAt -or -not [DateTimeOffset]::TryParse($resetsAt, [ref]$at)) { return '' }
    $left = $at - [DateTimeOffset]::Now
    if ($left.TotalMinutes -le 0) { return 'reset' }
    if ($left.Days -gt 0) { return 'resets in {0}d {1}h' -f $left.Days, $left.Hours }
    if ($left.Hours -gt 0) { return 'resets in {0}h {1}m' -f $left.Hours, $left.Minutes }
    return 'resets in {0}m' -f [Math]::Max(1, $left.Minutes)
}

function New-NumberIcon([string]$text, [System.Drawing.Color]$back) {
    $size = [System.Windows.Forms.SystemInformation]::SmallIconSize.Width
    $bitmap = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $brush = New-Object System.Drawing.SolidBrush($back)
    $g.FillRectangle($brush, 0, 0, $size, $size)

    $em = if ($text.Length -ge 3) { $size * 0.42 } else { $size * 0.62 }
    $font = New-Object System.Drawing.Font('Segoe UI', $em, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = 'Center'
    $format.LineAlignment = 'Center'
    $rect = New-Object System.Drawing.RectangleF(0, 0, $size, ($size + 1))
    $g.DrawString($text, $font, [System.Drawing.Brushes]::White, $rect, $format)

    $handle = $bitmap.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($handle).Clone()
    [ClaudeUsage.Native]::DestroyIcon($handle) | Out-Null
    $font.Dispose(); $brush.Dispose(); $g.Dispose(); $bitmap.Dispose()
    return $icon
}

function Get-LevelColor([double]$percent) {
    if ($percent -ge 90) { return [System.Drawing.Color]::FromArgb(200, 40, 40) }
    if ($percent -ge 70) { return [System.Drawing.Color]::FromArgb(205, 120, 0) }
    return [System.Drawing.Color]::FromArgb(30, 120, 70)
}

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Items.Add('Refresh', $null, { Update-Icons }) | Out-Null
$menu.Items.Add('Exit', $null, {
    foreach ($w in $Windows) { $w.Tray.Visible = $false; $w.Tray.Dispose() }
    [System.Windows.Forms.Application]::Exit()
}) | Out-Null

foreach ($w in $Windows) {
    $w.Tray = New-Object System.Windows.Forms.NotifyIcon
    $w.Tray.ContextMenuStrip = $menu
    $w.Tray.Visible = $true
}

function Update-Icons {
    $data = $null
    # The file is the mod's, but read it as untrusted: small, valid JSON only.
    if ((Test-Path $UsageFile -PathType Leaf) -and (Get-Item $UsageFile).Length -le 65536) {
        try { $data = Get-Content $UsageFile -Raw | ConvertFrom-Json } catch { }
    }

    foreach ($w in $Windows) {
        $text = '-'
        $back = [System.Drawing.Color]::FromArgb(90, 90, 90)
        $tip = "Claude $($w.Label): waiting for Claude Code to report usage"

        try {
            $limit = $null
            if ($data) { $limit = @($data.limits) | Where-Object { $_.kind -eq $w.Kind } | Select-Object -First 1 }
            $used = 0.0
            if ($limit -and [double]::TryParse([string]$limit.percentUsed, [ref]$used) -and -not [double]::IsNaN($used)) {
                $countdown = Get-Countdown $limit.resetsAt
                # Past its reset time, the window has started over at 0%.
                $percent = if ($countdown -eq 'reset') { 0 } else { [int][Math]::Round([Math]::Min(999, [Math]::Max(0, $used))) }
                $text = [string]$percent
                $back = Get-LevelColor $percent
                $tip = "Claude $($w.Label): $percent%"
                if ($countdown -and $countdown -ne 'reset') { $tip += ", $countdown" }
                $updated = [DateTimeOffset]::MinValue
                if ([DateTimeOffset]::TryParse([string]$data.updatedAt, [ref]$updated)) {
                    $tip += "`nUpdated " + $updated.ToLocalTime().ToString('HH:mm')
                }
            }
        } catch { }

        $old = $w.Tray.Icon
        $w.Tray.Icon = New-NumberIcon $text $back
        if ($old) { $old.Dispose() }
        # NotifyIcon tooltips are capped at 63 characters.
        $w.Tray.Text = if ($tip.Length -gt 63) { $tip.Substring(0, 63) } else { $tip }
    }
}

Update-Icons
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 15000
$timer.Add_Tick({ Update-Icons })
$timer.Start()

[System.Windows.Forms.Application]::Run()
$mutex.ReleaseMutex()
