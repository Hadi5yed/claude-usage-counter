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

# A tray icon registered under its own GUID. WinForms' NotifyIcon has no GUID,
# so Windows files every icon of powershell.exe under one entry and they pin
# and unpin together; with a GUID each icon is its own entry in the overflow
# and in Settings > Personalization > Taskbar > Other system tray icons.
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace ClaudeUsage {
    public class TrayIcon : NativeWindow, IDisposable {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct NotifyIconData {
            public int cbSize; public IntPtr hWnd; public int uID; public int uFlags; public int uCallbackMessage; public IntPtr hIcon;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szTip;
            public int dwState; public int dwStateMask;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szInfo;
            public int uVersion;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string szInfoTitle;
            public int dwInfoFlags; public Guid guidItem; public IntPtr hBalloonIcon;
        }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern bool Shell_NotifyIcon(int message, ref NotifyIconData data);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int RegisterWindowMessage(string name);
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);

        const int NIM_ADD = 0, NIM_MODIFY = 1, NIM_DELETE = 2, NIM_SETVERSION = 4;
        const int NIF_MESSAGE = 0x1, NIF_ICON = 0x2, NIF_TIP = 0x4, NIF_GUID = 0x20, NIF_SHOWTIP = 0x80;
        const int WM_CONTEXTMENU = 0x7B, WM_TRAY = 0x8001;
        static readonly int WM_TASKBARCREATED = RegisterWindowMessage("TaskbarCreated");

        readonly Guid id;
        readonly int fallbackId;
        bool useGuid = true, isAdded;
        Icon icon;
        string tip = "";
        public ContextMenuStrip Menu;

        public TrayIcon(Guid id, int fallbackId) {
            this.id = id;
            this.fallbackId = fallbackId;
            CreateHandle(new CreateParams());
        }

        NotifyIconData Data(int flags) {
            var d = new NotifyIconData();
            d.cbSize = Marshal.SizeOf(typeof(NotifyIconData));
            d.hWnd = Handle;
            d.uID = fallbackId;
            d.uFlags = flags | (useGuid ? NIF_GUID : 0);
            d.guidItem = useGuid ? id : Guid.Empty;
            d.uCallbackMessage = WM_TRAY;
            d.hIcon = icon != null ? icon.Handle : IntPtr.Zero;
            d.szTip = tip;
            d.uVersion = 4;
            return d;
        }

        public void Update(Icon newIcon, string newTip) {
            var old = icon;
            icon = newIcon;
            tip = newTip ?? "";
            var d = Data(NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP);
            if (!isAdded || !Shell_NotifyIcon(NIM_MODIFY, ref d)) Add();
            if (old != null && old != icon) old.Dispose();
        }

        void Add() {
            // A crashed run can leave this GUID registered; clear it first.
            var stale = Data(0);
            Shell_NotifyIcon(NIM_DELETE, ref stale);
            var d = Data(NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP);
            isAdded = Shell_NotifyIcon(NIM_ADD, ref d);
            if (!isAdded && useGuid) {
                // Windows ties a GUID to one program's path; elsewhere fall back to an ID.
                useGuid = false;
                d = Data(NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP);
                isAdded = Shell_NotifyIcon(NIM_ADD, ref d);
            }
            if (isAdded) Shell_NotifyIcon(NIM_SETVERSION, ref d);
        }

        protected override void WndProc(ref Message m) {
            if (m.Msg == WM_TRAY) {
                if (((int)m.LParam.ToInt64() & 0xFFFF) == WM_CONTEXTMENU && Menu != null) {
                    SetForegroundWindow(Handle);
                    Menu.Show(Cursor.Position);
                }
                return;
            }
            if (m.Msg == WM_TASKBARCREATED) {
                // Explorer restarted: the taskbar forgot every icon.
                isAdded = false;
                if (icon != null) Add();
                return;
            }
            base.WndProc(ref m);
        }

        public void Dispose() {
            if (isAdded) {
                var d = Data(0);
                Shell_NotifyIcon(NIM_DELETE, ref d);
                isAdded = false;
            }
            if (icon != null) icon.Dispose();
            DestroyHandle();
        }
    }
}
'@

$created = $false
# ::new, not New-Object: New-Object never writes back through [ref].
$mutex = [System.Threading.Mutex]::new($true, 'Local\ClaudeUsageTray', [ref]$created)
if (-not $created) { exit }

$UsageFile = Join-Path $env:USERPROFILE '.claude\usage-counter\usage.json'
# Each GUID is that icon's identity to Windows; never reuse or change them.
$Windows = @(
    @{ Kind = 'five_hour'; Label = '5-hour'; Id = [guid]'1068662a-eb87-436f-b76c-ee8bd273cdd2'; FallbackId = 1 },
    @{ Kind = 'seven_day'; Label = 'Weekly'; Id = [guid]'7495279c-71b1-47dc-9e25-e1bd2a2df00e'; FallbackId = 2 }
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
    $brush = New-Object System.Drawing.SolidBrush($back)
    # Unsmoothed fill: hard, fully opaque edges rather than a soft half-pixel rim.
    $g.FillRectangle($brush, 0, 0, $size, $size)

    # The digits as outlines, scaled to fill the square and centred on their
    # ink, which reads larger and sharper at 16-24 px than drawn text.
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $family = New-Object System.Drawing.FontFamily('Segoe UI')
    $path.AddString($text, $family, [int][System.Drawing.FontStyle]::Bold, 100, (New-Object System.Drawing.PointF(0, 0)), [System.Drawing.StringFormat]::GenericTypographic)
    $ink = $path.GetBounds()
    $scale = [Math]::Min($size * 0.84 / $ink.Width, $size * 0.62 / $ink.Height)
    $matrix = New-Object System.Drawing.Drawing2D.Matrix
    $matrix.Translate([Math]::Round(($size - $ink.Width * $scale) / 2), [Math]::Round(($size - $ink.Height * $scale) / 2))
    $matrix.Scale($scale, $scale)
    $matrix.Translate(-$ink.X, -$ink.Y)
    $path.Transform($matrix)
    $g.SmoothingMode = 'AntiAlias'
    $g.PixelOffsetMode = 'HighQuality'
    $g.FillPath([System.Drawing.Brushes]::White, $path)

    $handle = $bitmap.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($handle).Clone()
    [ClaudeUsage.Native]::DestroyIcon($handle) | Out-Null
    $matrix.Dispose(); $family.Dispose(); $path.Dispose(); $brush.Dispose(); $g.Dispose(); $bitmap.Dispose()
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
    foreach ($w in $Windows) { $w.Tray.Dispose() }
    [System.Windows.Forms.Application]::Exit()
}) | Out-Null

foreach ($w in $Windows) {
    $w.Tray = New-Object ClaudeUsage.TrayIcon($w.Id, $w.FallbackId)
    $w.Tray.Menu = $menu
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

        # Tooltips hold 127 characters.
        $w.Tray.Update((New-NumberIcon $text $back), $(if ($tip.Length -gt 127) { $tip.Substring(0, 127) } else { $tip }))
    }
}

Update-Icons
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 15000
$timer.Add_Tick({ Update-Icons })
$timer.Start()

[System.Windows.Forms.Application]::Run()
$mutex.ReleaseMutex()
