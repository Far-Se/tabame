import 'dart:io';

import '../win32/win32.dart';
import '../win32/win_utils.dart';

void writeScript(Scripts script) {
  String? scriptCode;
  if (script == Scripts.msgBox) {
    scriptCode = """

param(
    [Parameter(Mandatory=\$true, Position=0)]
    [string]\$Title,

    [Parameter(Mandatory=\$true, Position=1)]
    [string]\$Message
)
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Speech

# Initialize TTS
\$tts = New-Object System.Speech.Synthesis.SpeechSynthesizer
\$tts.Rate = 0
\$tts.Volume = 100

[xml]\$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="\$Title"
    WindowStyle="None"
    ResizeMode="NoResize"
    WindowStartupLocation="CenterScreen"
    Background="Transparent"
    AllowsTransparency="True"
    Width="480"
    Height="240"
    ShowInTaskbar="True"
    Topmost="True">

    <Window.Resources>
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Background" Value="#1a273f"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="24,10"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontFamily" Value="Segoe UI Symbol"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#1a273f"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                    <Setter Property="Background" Value="#1a273f"/>
                </Trigger>
            </Style.Triggers>
        </Style>

    </Window.Resources>

    <Border Background="#12161b" CornerRadius="12" BorderThickness="1" BorderBrush="#374151">
        <Border.Effect>
            <DropShadowEffect Color="#000000" Opacity="0.5" BlurRadius="40" ShadowDepth="0"/>
        </Border.Effect>

        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="60"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="70"/>
            </Grid.RowDefinitions>

            <!-- Title Bar -->
            <Border Grid.Row="0" Background="#1a2027" CornerRadius="12,12,0,0" BorderThickness="0,0,0,1" BorderBrush="#374151">
                <Grid>
                    <TextBlock Text="\$Title"
                               FontSize="18"
                               FontWeight="SemiBold"
                               FontFamily="Segoe UI Symbol"
                               Foreground="#f9fafb"
                               VerticalAlignment="Center"
                               Margin="24,0,0,0"/>
                </Grid>
            </Border>

            <!-- Message Content -->
            <Border Grid.Row="1" Padding="24,20">
                <TextBlock Name="MessageText"
                           Text="\$Message"
                           FontSize="18"
                           FontFamily="Segoe UI Symbol"
                           Foreground="#d1d5db"
                           TextWrapping="Wrap"
                           TextAlignment="Center"
                           HorizontalAlignment="Center"
                           VerticalAlignment="Center"
                           LineHeight="22"/>
            </Border>

            <!-- Button Area -->
            <Border Grid.Row="2" Background="#12161b" CornerRadius="0,0,12,12" BorderThickness="0,1,0,0" BorderBrush="#374151">
                <Button Name="OKButton"
                        Content="OK"
                        Style="{StaticResource ModernButton}"
                        HorizontalAlignment="Right"
                        VerticalAlignment="Center"
                        Margin="0,0,24,0"
                        IsDefault="True"/>
            </Border>
        </Grid>
    </Border>
</Window>
"@

\$reader = New-Object System.Xml.XmlNodeReader \$xaml
\$window = [Windows.Markup.XamlReader]::Load(\$reader)
\$window.Topmost = \$true


# Get controls
\$okButton = \$window.FindName("OKButton")

# Speak the message using TTS
\$tts.SpeakAsync("\$Message") | Out-Null

# Event handlers
\$okButton.Add_Click({
    \$tts.SpeakAsyncCancelAll()
    \$window.DialogResult = \$true
    \$window.Close()
})

\$window.Add_KeyDown({
    if (\$_.Key -eq 'Space') {
        \$okButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
    }
})

# Make window draggable
\$window.Add_MouseLeftButtonDown({
    \$window.DragMove()
})

# Clean up TTS when window closes
\$window.Add_Closed({
    \$tts.Dispose()
})

# Show window
\$result = \$window.ShowDialog()

# Return result
return \$result
""";
  } else if (script == Scripts.colorPicker) {
    scriptCode = """
# ── Speed up Add-Type by compiling to a cached temp assembly ─────────────────
\$cacheDir  = Join-Path \$env:TEMP "ColorPickerCache"
\$asmPath   = Join-Path \$cacheDir "ColorPickerNative.dll"
\$srcHash   = "v3"   # bump this if you change the C# source

if (-not (Test-Path \$asmPath) -or
    (Get-Content "\$asmPath.ver" -ErrorAction SilentlyContinue) -ne \$srcHash) {

    New-Item -ItemType Directory -Force -Path \$cacheDir | Out-Null

    Add-Type @"
using System;
using System.Runtime.InteropServices;

public class MouseHook {
    private const int WH_MOUSE_LL    = 14;
    private const int WM_LBUTTONDOWN = 0x0201;

    public delegate void ClickHandler();
    public static event ClickHandler OnClick;

    private static IntPtr   _hookId = IntPtr.Zero;
    private static HookProc _proc   = HookCallback;

    public delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]   private static extern IntPtr SetWindowsHookEx(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);
    [DllImport("user32.dll")]   public  static extern bool   UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")]   private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll")] private static extern IntPtr GetModuleHandle(string lpModuleName);

    public static void Install() {
        var h = GetModuleHandle(System.Diagnostics.Process.GetCurrentProcess().MainModule.ModuleName);
        _hookId = SetWindowsHookEx(WH_MOUSE_LL, _proc, h, 0);
    }
    public static void Uninstall() { UnhookWindowsHookEx(_hookId); }

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0 && wParam == (IntPtr)WM_LBUTTONDOWN && OnClick != null) {
            OnClick.Invoke();
            return (IntPtr)1;
        }
        return CallNextHookEx(_hookId, nCode, wParam, lParam);
    }
}

public class Win32 {
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
}
"@ -OutputAssembly \$asmPath -ErrorAction Stop
    Set-Content "\$asmPath.ver" \$srcHash
} else {
    Add-Type -Path \$asmPath
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ── Config ────────────────────────────────────────────────────────────────────
\$zoom     = 11
\$gridSize = 11
\$half     = [int][math]::Floor(\$gridSize / 2)

# ── Dimensions ────────────────────────────────────────────────────────────────
\$pad     = 8
\$gridPx  = [int](\$gridSize * \$zoom)
\$swatchH = 28
\$infoH   = 22
\$innerW  = \$gridPx
\$formW   = [int](\$innerW + \$pad * 2)
\$formH   = [int](\$pad + \$gridPx + 4 + \$swatchH + 2 + \$infoH + \$pad)

# ── Pre-compute all layout constants ──────────────────────────────────────────
\$gridX     = [int]\$pad
\$gridY     = [int]\$pad
\$gridRight = [int](\$gridX + \$gridPx)
\$gridBot   = [int](\$gridY + \$gridPx)
\$divY      = [int](\$gridBot + 3)
\$swatchY   = [int](\$divY + 1)
\$swatchW   = [int]28
\$swatchPad = [int]4
\$swatchRX  = [int]\$pad
\$swatchRY  = [int](\$swatchY + \$swatchPad)
\$swatchRH  = [int](\$swatchH - \$swatchPad * 2)
\$hexX      = [int](\$pad + \$swatchW + 7)
\$hexY      = [int](\$swatchY + 5)
\$div2Y     = [int](\$swatchY + \$swatchH)
\$rgbY      = [int](\$div2Y + 3)
\$lineEnd   = [int](\$pad + \$innerW)
\$colW      = [int](\$innerW / 3)
\$cxCross   = [int](\$gridX + \$half * \$zoom)
\$cyCross   = [int](\$gridY + \$half * \$zoom)
\$cxInner   = [int](\$cxCross + 1)
\$cyInner   = [int](\$cyCross + 1)
\$zoomM2    = [int](\$zoom - 2)

# Swatch rounded-rect arc coords (pre-computed, path built once)
\$sr2   = [int]6
\$sRtS  = [int](\$swatchRX + \$swatchW - \$sr2)
\$sBtS  = [int](\$swatchRY + \$swatchRH - \$sr2)

# RGB column X positions
\$rgbCX = @( [int]\$pad, [int](\$pad + \$colW), [int](\$pad + \$colW * 2) )
\$rgbVX = @( [int](\$pad + 11), [int](\$pad + \$colW + 11), [int](\$pad + \$colW * 2 + 11) )

# ── Colors ────────────────────────────────────────────────────────────────────
\$colBg       = [System.Drawing.Color]::FromArgb(255, 18,  18,  20)
\$colBorder   = [System.Drawing.Color]::FromArgb(255, 55,  55,  65)
\$colTextSec  = [System.Drawing.Color]::FromArgb(255, 140, 140, 160)
\$colCopied   = [System.Drawing.Color]::FromArgb(255, 100, 210, 130)
\$colGridLine = [System.Drawing.Color]::FromArgb(40,  255, 255, 255)
\$colR        = [System.Drawing.Color]::FromArgb(255, 255, 90,  80)
\$colG        = [System.Drawing.Color]::FromArgb(255, 80,  200, 100)
\$colB        = [System.Drawing.Color]::FromArgb(255, 80,  150, 255)

# ── Pre-allocate ALL GDI resources once ───────────────────────────────────────
\$penGrid    = New-Object System.Drawing.Pen(\$colGridLine, 1)
\$penOuter   = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2)
\$penInner   = New-Object System.Drawing.Pen([System.Drawing.Color]::Black, 1)
\$penDiv     = New-Object System.Drawing.Pen(\$colBorder, 1)
\$penSwatch  = New-Object System.Drawing.Pen(\$colBorder, 1)
\$brushSec   = New-Object System.Drawing.SolidBrush(\$colTextSec)
\$brushR     = New-Object System.Drawing.SolidBrush(\$colR)
\$brushG     = New-Object System.Drawing.SolidBrush(\$colG)
\$brushB     = New-Object System.Drawing.SolidBrush(\$colB)
\$brushCopied= New-Object System.Drawing.SolidBrush(\$colCopied)
\$brushWhite = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
\$brushSwatch= New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Black)  # color updated per frame

\$fontHex    = New-Object System.Drawing.Font("Consolas", 11, [System.Drawing.FontStyle]::Bold)
\$fontRgb    = New-Object System.Drawing.Font("Consolas", 8,  [System.Drawing.FontStyle]::Regular)

# Swatch path — static shape, allocated once
\$swatchPath = New-Object System.Drawing.Drawing2D.GraphicsPath
\$swatchPath.AddArc(\$swatchRX, \$swatchRY, \$sr2, \$sr2, 180, 90)
\$swatchPath.AddArc(\$sRtS,     \$swatchRY, \$sr2, \$sr2, 270, 90)
\$swatchPath.AddArc(\$sRtS,     \$sBtS,     \$sr2, \$sr2,   0, 90)
\$swatchPath.AddArc(\$swatchRX, \$sBtS,     \$sr2, \$sr2,  90, 90)
\$swatchPath.CloseFigure()

# Pre-build grid line coords as flat int arrays (x1,y1,x2,y2)
\$hLines = [System.Collections.Generic.List[int[]]]::new()
for (\$i = 0; \$i -le \$gridSize; \$i++) {
    \$y = [int](\$gridY + \$i * \$zoom)
    \$hLines.Add([int[]]@(\$gridX, \$y, \$gridRight, \$y))
}
\$vLines = [System.Collections.Generic.List[int[]]]::new()
for (\$i = 0; \$i -le \$gridSize; \$i++) {
    \$x = [int](\$gridX + \$i * \$zoom)
    \$vLines.Add([int[]]@(\$x, \$gridY, \$x, \$gridBot))
}

# ── State ─────────────────────────────────────────────────────────────────────
\$script:clicked     = \$false
\$script:startTime   = [System.DateTime]::Now
\$script:currentHex  = "#------"
\$script:currentR    = 0
\$script:currentG    = 0
\$script:currentB    = 0
\$script:copied      = \$false
\$script:copiedTimer = 0

# ── Form ──────────────────────────────────────────────────────────────────────
\$form = New-Object System.Windows.Forms.Form
\$form.FormBorderStyle = 'None'
\$form.StartPosition   = 'Manual'
\$form.Text            = 'Color Picker'
\$form.Name            = 'Color Picker'
\$form.TopMost         = \$true
\$form.Width           = \$formW
\$form.Height          = \$formH
\$form.ShowInTaskbar   = \$false
\$form.BackColor       = \$colBg
\$form.Padding         = New-Object System.Windows.Forms.Padding(0)
\$form.GetType().GetProperty("DoubleBuffered",
    [System.Reflection.BindingFlags]::NonPublic -bor
    [System.Reflection.BindingFlags]::Instance
).SetValue(\$form, \$true, \$null)

# Rounded window region
\$gPath = New-Object System.Drawing.Drawing2D.GraphicsPath
\$gr2   = [int]16
\$fwR2  = [int](\$formW - \$gr2)
\$fhR2  = [int](\$formH - \$gr2)
\$gPath.AddArc(0,     0,     \$gr2, \$gr2, 180, 90)
\$gPath.AddArc(\$fwR2, 0,     \$gr2, \$gr2, 270, 90)
\$gPath.AddArc(\$fwR2, \$fhR2, \$gr2, \$gr2,   0, 90)
\$gPath.AddArc(0,     \$fhR2, \$gr2, \$gr2,  90, 90)
\$gPath.CloseFigure()
\$form.Region = New-Object System.Drawing.Region(\$gPath)

# ── Bitmap buffer ─────────────────────────────────────────────────────────────
\$bmp = New-Object System.Drawing.Bitmap(\$gridSize, \$gridSize)

# ── Paint handler — zero allocations ─────────────────────────────────────────
\$form.Add_Paint({
    param(\$sender, \$e)
    \$g = \$e.Graphics
    \$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    \$g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::Half

    # Pixel grid
    \$g.DrawImage(\$bmp, \$gridX, \$gridY, \$gridPx, \$gridPx)

    # Grid lines
    foreach (\$ln in \$hLines) { \$g.DrawLine(\$penGrid, \$ln[0], \$ln[1], \$ln[2], \$ln[3]) }
    foreach (\$ln in \$vLines) { \$g.DrawLine(\$penGrid, \$ln[0], \$ln[1], \$ln[2], \$ln[3]) }

    # Crosshair
    \$g.DrawRectangle(\$penOuter, \$cxCross, \$cyCross, \$zoom,   \$zoom)
    \$g.DrawRectangle(\$penInner, \$cxInner, \$cyInner, \$zoomM2, \$zoomM2)

    # Divider 1
    \$g.DrawLine(\$penDiv, \$pad, \$divY, \$lineEnd, \$divY)

    # Swatch (update brush color in-place — no allocation)
    \$brushSwatch.Color = [System.Drawing.Color]::FromArgb(255, \$script:currentR, \$script:currentG, \$script:currentB)
    \$g.SmoothingMode   = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    \$g.FillPath(\$brushSwatch, \$swatchPath)
    \$g.DrawPath(\$penSwatch,   \$swatchPath)
    \$g.SmoothingMode   = [System.Drawing.Drawing2D.SmoothingMode]::None

    # Hex / Copied label
    if (\$script:copied) {
        \$g.DrawString("Copied!", \$fontHex, \$brushCopied, \$hexX, \$hexY)
    } else {
        \$g.DrawString(\$script:currentHex, \$fontHex, \$brushWhite, \$hexX, \$hexY)
    }

    # Divider 2
    \$g.DrawLine(\$penDiv, \$pad, \$div2Y, \$lineEnd, \$div2Y)

    # RGB row
    \$g.DrawString("R", \$fontRgb, \$brushR, \$rgbCX[0], \$rgbY)
    \$g.DrawString("G", \$fontRgb, \$brushG, \$rgbCX[1], \$rgbY)
    \$g.DrawString("B", \$fontRgb, \$brushB, \$rgbCX[2], \$rgbY)
    \$g.DrawString(([string]\$script:currentR).PadLeft(3), \$fontRgb, \$brushSec, \$rgbVX[0], \$rgbY)
    \$g.DrawString(([string]\$script:currentG).PadLeft(3), \$fontRgb, \$brushSec, \$rgbVX[1], \$rgbY)
    \$g.DrawString(([string]\$script:currentB).PadLeft(3), \$fontRgb, \$brushSec, \$rgbVX[2], \$rgbY)
})

# ── Mouse hook ────────────────────────────────────────────────────────────────
[MouseHook]::Install()
[MouseHook]::add_OnClick({
    \$elapsed = ([System.DateTime]::Now - \$script:startTime).TotalMilliseconds
    if (\$elapsed -gt 400) { \$script:clicked = \$true }
})

# ── Cleanup ───────────────────────────────────────────────────────────────────
function Cleanup {
    [MouseHook]::Uninstall()
    \$timer.Stop()
    \$penGrid, \$penOuter, \$penInner, \$penDiv, \$penSwatch,
    \$brushSec, \$brushR, \$brushG, \$brushB, \$brushCopied, \$brushWhite, \$brushSwatch,
    \$fontHex, \$fontRgb, \$swatchPath, \$bmp | ForEach-Object { \$_.Dispose() }
    \$form.Close()
}

# ── Timer (~60 fps) ───────────────────────────────────────────────────────────
\$timer          = New-Object System.Windows.Forms.Timer
\$timer.Interval = 16

\$timer.Add_Tick({
    \$pos = [System.Windows.Forms.Cursor]::Position

    \$gfx = [System.Drawing.Graphics]::FromImage(\$bmp)
    \$gfx.CopyFromScreen(\$pos.X - \$half, \$pos.Y - \$half, 0, 0, \$bmp.Size)
    \$gfx.Dispose()

    \$color = \$bmp.GetPixel(\$half, \$half)
    \$script:currentHex = "#{0:X2}{1:X2}{2:X2}" -f \$color.R, \$color.G, \$color.B
    \$script:currentR   = \$color.R
    \$script:currentG   = \$color.G
    \$script:currentB   = \$color.B

    if (\$script:copied) { \$script:copiedTimer--; if (\$script:copiedTimer -le 0) { \$script:copied = \$false } }

    # Screen-aware positioning: flip to left/above when near screen edges
    \$screen  = [System.Windows.Forms.Screen]::FromPoint(\$pos)
    \$bounds  = \$screen.Bounds
    \$offset  = 22
    \$winLeft = if ((\$pos.X + \$offset + \$formW) -gt \$bounds.Right)  { \$pos.X - \$offset - \$formW } else { \$pos.X + \$offset }
    \$winTop  = if ((\$pos.Y + \$offset + \$formH) -gt \$bounds.Bottom) { \$pos.Y - \$offset - \$formH } else { \$pos.Y + \$offset }
    \$form.Left = [math]::Max(\$bounds.Left, \$winLeft)
    \$form.Top  = [math]::Max(\$bounds.Top,  \$winTop)

    if ([Win32]::GetAsyncKeyState(0x1B) -ne 0) { Cleanup; return }

    if (\$script:clicked) {
        \$script:clicked     = \$false
        \$hex                = \$script:currentHex
        \$script:copied      = \$true
        \$script:copiedTimer = 45

        [System.Windows.Forms.Clipboard]::SetText("\$hex RGB(\$(\$color.R),\$(\$color.G),\$(\$color.B))")

        \$rows = for (\$row = 0; \$row -lt \$gridSize; \$row++) {
            , @(for (\$col = 0; \$col -lt \$gridSize; \$col++) {
                \$px = \$bmp.GetPixel(\$col, \$row)
                @{ hex = "#{0:X2}{1:X2}{2:X2}" -f \$px.R, \$px.G, \$px.B; r = \$px.R; g = \$px.G; b = \$px.B }
            })
        }

        \$scriptDir = if (\$PSScriptRoot) { \$PSScriptRoot }
                     elseif (\$PSCommandPath) { Split-Path -Parent \$PSCommandPath }
                     else { [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }

        @{ cursor = @{ x=\$pos.X; y=\$pos.Y }; center = @{ hex=\$hex; r=\$color.R; g=\$color.G; b=\$color.B }; grid=\$rows } |
            ConvertTo-Json -Depth 5 | Out-File -FilePath (Join-Path \$scriptDir "grid.json") -Encoding UTF8

        Cleanup; return
    }

    \$form.Invalidate()
})

\$form.KeyPreview = \$true
\$form.Add_KeyDown({ if (\$_.KeyCode -eq "Escape") { Cleanup } })

# Position next to cursor before the form is shown
\$_pos0    = [System.Windows.Forms.Cursor]::Position
\$_screen0 = [System.Windows.Forms.Screen]::FromPoint(\$_pos0)
\$_bounds0 = \$_screen0.Bounds
\$_offset0 = 22
\$_left0   = if ((\$_pos0.X + \$_offset0 + \$formW) -gt \$_bounds0.Right)  { \$_pos0.X - \$_offset0 - \$formW } else { \$_pos0.X + \$_offset0 }
\$_top0    = if ((\$_pos0.Y + \$_offset0 + \$formH) -gt \$_bounds0.Bottom) { \$_pos0.Y - \$_offset0 - \$formH } else { \$_pos0.Y + \$_offset0 }
\$form.Left = [math]::Max(\$_bounds0.Left, \$_left0)
\$form.Top  = [math]::Max(\$_bounds0.Top,  \$_top0)

\$timer.Start()
[System.Windows.Forms.Application]::Run(\$form)

""";
  } else if (script == Scripts.open) {
    scriptCode = """""";
  }

  final Directory scriptsFolder = Directory("${WinUtils.getTabameAppDataFolder()}\\scripts");
  if (!scriptsFolder.existsSync()) {
    scriptsFolder.createSync(recursive: true);
  }
  if (scriptCode == null) return;
  final String scriptPath = "${scriptsFolder.path}\\${script.fileName}";
  File(scriptPath).writeAsStringSync(scriptCode);
}
