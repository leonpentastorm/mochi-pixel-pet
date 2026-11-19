# Mochi on the desktop: a see-through, always-on-top window with the pixel pet.
#
# Every Claude Code session running the pixel-pet mod writes how it is doing to
# %USERPROFILE%\.claude\mochi\sessions\<session>.json. This window reads them
# once a second and:
#   - animates Mochi for the busiest state (question > done > working > idle > asleep),
#   - shows one speech line per chat that needs you, and (a toggle) one per chat
#     in progress; clicking a line opens that chat,
#   - opens the chat that needs you most when you click Mochi itself,
#   - loops a sound while a question waits or a finished chat is unseen,
#   - wanders left and right now and then while idle, or, in DVD mode, bounces
#     around the screen changing color at every wall.
# Drag Mochi to move it, drag the corner grip or turn the mouse wheel to resize,
# right-click for the menu. Settings live in %USERPROFILE%\.claude\mochi\desktop.json.
#
# Kept to ASCII: Windows PowerShell 5.1 reads a script without a BOM as ANSI.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms, System.Drawing

# Two things WPF can't do by itself: keep Mochi out of Alt+Tab, and tell which app is in front.
if (-not ('MochiNative' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MochiNative {
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")] static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int index);
  [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")] static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int index, IntPtr value);
  [DllImport("user32.dll", EntryPoint = "GetWindowLong")] static extern int GetWindowLong32(IntPtr hWnd, int index);
  [DllImport("user32.dll", EntryPoint = "SetWindowLong")] static extern int SetWindowLong32(IntPtr hWnd, int index, int value);
  [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
  [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
  const int GWL_EXSTYLE = -20;

  // How long since the last mouse or keyboard input, in milliseconds.
  public static double IdleMilliseconds() {
    LASTINPUTINFO info = new LASTINPUTINFO();
    info.cbSize = (uint)Marshal.SizeOf(info);
    if (!GetLastInputInfo(ref info)) return 0;
    return unchecked((uint)Environment.TickCount - info.dwTime);
  }
  const long WS_EX_TOOLWINDOW = 0x80, WS_EX_APPWINDOW = 0x40000;

  // The process name of the window in front ("Claude" for the Claude app), or "".
  public static string ForegroundProcess() {
    IntPtr h = GetForegroundWindow();
    if (h == IntPtr.Zero) return "";
    uint pid; GetWindowThreadProcessId(h, out pid);
    try { return System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; } catch { return ""; }
  }

  // A tool window: Windows leaves it out of Alt+Tab and the taskbar.
  public static bool HideFromAltTab(IntPtr h) {
    long ex = IntPtr.Size == 8 ? GetWindowLongPtr(h, GWL_EXSTYLE).ToInt64() : GetWindowLong32(h, GWL_EXSTYLE);
    ex = (ex | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW;
    if (IntPtr.Size == 8) SetWindowLongPtr(h, GWL_EXSTYLE, new IntPtr(ex)); else SetWindowLong32(h, GWL_EXSTYLE, (int)ex);
    long now = IntPtr.Size == 8 ? GetWindowLongPtr(h, GWL_EXSTYLE).ToInt64() : GetWindowLong32(h, GWL_EXSTYLE);
    return (now & WS_EX_TOOLWINDOW) != 0;
  }
}
'@
}

$Dir = Join-Path $env:USERPROFILE '.claude\mochi'
$SessionsDir = Join-Path $Dir 'sessions'
$FramesFile = Join-Path $Dir 'frames.json'
$SettingsFile = Join-Path $Dir 'desktop.json'
$LogFile = Join-Path $Dir 'desktop.log'
$ChimeSound = Join-Path $Dir 'chime.wav'
# A ringtone of your own can sit beside the chime as phone.mp3; it is the default when there.
$PhoneSound = Join-Path $Dir 'phone.mp3'
New-Item -ItemType Directory -Force -Path $SessionsDir | Out-Null

function Write-Log([string]$message) {
  try { Add-Content -Path $LogFile -Value ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $message) } catch { }
}

# One Mochi at a time: every Claude session tries to start one.
$isFirst = $false
$lockName = if ($env:MOCHI_SNAPSHOT) { 'Local\MochiDesktopPetTest' } else { 'Local\MochiDesktopPet' }
$script:Mutex = New-Object System.Threading.Mutex($true, $lockName, [ref]$isFirst)
if (-not $isFirst) { return }
Write-Log 'started'

# ---------------------------------------------------------------- settings

$script:S = @{
  x = $null; y = $null; scale = 4.0
  soundOn = $true; soundChoice = 'phone'; soundFile = $null
  launchWithClaude = $false; showProgress = $true; wander = $true; dvdMode = $false
  onTop = $true; napMinutes = 3
  link = $null
}
if (Test-Path $SettingsFile) {
  try {
    $saved = [IO.File]::ReadAllText($SettingsFile) | ConvertFrom-Json
    foreach ($p in $saved.PSObject.Properties) { $script:S[$p.Name] = $p.Value }
  } catch { Write-Log "settings unreadable: $_" }
}
function Save-Settings {
  try { [IO.File]::WriteAllText($SettingsFile, ($script:S | ConvertTo-Json)) } catch { Write-Log "settings not saved: $_" }
}

# ---------------------------------------------------------------- the built-in chime

function New-Chime([string]$path) {
  # Two soft bell notes and a pause, so a loop of it rings rather than drones.
  $rate = 22050
  $n = [int]($rate * 1.8)
  $samples = New-Object double[] $n
  foreach ($note in @(@(987.8, 0.0, 0.9), @(1318.5, 0.16, 1.2))) {
    $freq = $note[0]; $start = [int]($note[1] * $rate); $len = [int]($note[2] * $rate)
    for ($i = 0; $i -lt $len -and ($start + $i) -lt $n; $i++) {
      $t = $i / $rate
      $amp = [Math]::Exp(-4.5 * $t) * [Math]::Min(1.0, $i / 150.0)
      $samples[$start + $i] += 0.32 * $amp * ([Math]::Sin(2 * [Math]::PI * $freq * $t) + 0.25 * [Math]::Sin(4 * [Math]::PI * $freq * $t))
    }
  }
  $ms = New-Object IO.MemoryStream
  $w = New-Object IO.BinaryWriter($ms)
  $ascii = [Text.Encoding]::ASCII
  $w.Write($ascii.GetBytes('RIFF')); $w.Write([int](36 + $n * 2)); $w.Write($ascii.GetBytes('WAVEfmt '))
  $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1); $w.Write([int]$rate); $w.Write([int]($rate * 2))
  $w.Write([int16]2); $w.Write([int16]16); $w.Write($ascii.GetBytes('data')); $w.Write([int]($n * 2))
  foreach ($v in $samples) {
    $level = [Math]::Max(-1.0, [Math]::Min(1.0, $v)) * 32000
    $w.Write([int16]$level)
  }
  $w.Flush()
  [IO.File]::WriteAllBytes($path, $ms.ToArray())
}
if (-not (Test-Path $ChimeSound)) { try { New-Chime $ChimeSound } catch { Write-Log "chime not made: $_" } }

# ---------------------------------------------------------------- frames

$script:FramesStamp = $null
$script:Moods = @{}
$script:W = 1; $script:H = 1

# Reads frames.json (the mod rewrites it when Mochi's art changes) into bitmaps,
# every frame cropped to the pixels any frame uses.
function Import-Frames {
  $stamp = (Get-Item -LiteralPath $FramesFile).LastWriteTimeUtc
  $art = [IO.File]::ReadAllText($FramesFile) | ConvertFrom-Json
  $inked = [char[]]'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
  $minX = $art.width; $minY = $art.height; $maxX = 0; $maxY = 0
  foreach ($m in $art.moods.PSObject.Properties) {
    foreach ($f in $m.Value) {
      for ($y = 0; $y -lt $art.height; $y++) {
        $row = $f.rows[$y]
        $first = $row.IndexOfAny($inked)
        if ($first -lt 0) { continue }
        $last = $row.LastIndexOfAny($inked)
        if ($first -lt $minX) { $minX = $first }; if ($last -gt $maxX) { $maxX = $last }
        if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y }
      }
    }
  }
  $w = $maxX - $minX + 1
  $h = $maxY - $minY + 1
  $palette = New-Object 'System.Collections.Generic.Dictionary[char,byte[]]'
  foreach ($p in $art.palette.PSObject.Properties) {
    $c = [Windows.Media.ColorConverter]::ConvertFromString($p.Value)
    $palette[[char]$p.Name] = [byte[]]@($c.B, $c.G, $c.R, $c.A)
  }
  $moods = @{}
  foreach ($m in $art.moods.PSObject.Properties) {
    $list = New-Object System.Collections.ArrayList
    foreach ($f in $m.Value) {
      $px = New-Object byte[] ($w * $h * 4)
      for ($y = 0; $y -lt $h; $y++) {
        $row = $f.rows[$y + $minY]
        for ($x = 0; $x -lt $w; $x++) {
          $ch = $row[$x + $minX]
          if ($ch -eq '.') { continue }
          [Array]::Copy($palette[$ch], 0, $px, ($y * $w + $x) * 4, 4)
        }
      }
      $bmp = New-Object Windows.Media.Imaging.WriteableBitmap($w, $h, 96, 96, [Windows.Media.PixelFormats]::Bgra32, $null)
      $bmp.WritePixels((New-Object Windows.Int32Rect(0, 0, $w, $h)), $px, $w * 4, 0)
      $bmp.Freeze()
      [void]$list.Add([pscustomobject]@{ ms = [int]$f.ms; bmp = $bmp; px = $px })
    }
    $moods[$m.Name] = $list
  }
  $script:Moods = $moods
  $script:W = $w
  $script:H = $h
  $script:FramesStamp = $stamp
}

for ($i = 0; $i -lt 40 -and -not (Test-Path $FramesFile); $i++) { Start-Sleep -Milliseconds 250 }
if (-not (Test-Path $FramesFile)) { Write-Log 'no frames.json: start a Claude session with the pixel-pet mod first'; return }
Import-Frames

# ---------------------------------------------------------------- window

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Mochi" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" SizeToContent="WidthAndHeight" ResizeMode="NoResize"
        UseLayoutRounding="True">
  <StackPanel>
    <StackPanel x:Name="Lines" HorizontalAlignment="Center"/>
    <Grid x:Name="PetBox" HorizontalAlignment="Center">
      <Image x:Name="Pet" Stretch="Fill" RenderOptions.BitmapScalingMode="NearestNeighbor" Cursor="Hand"
             RenderTransformOrigin="0.5,0.5">
        <Image.RenderTransform><ScaleTransform x:Name="Facing" ScaleX="1"/></Image.RenderTransform>
      </Image>
      <Thumb x:Name="Grip" Width="12" Height="12" HorizontalAlignment="Right" VerticalAlignment="Bottom"
             Cursor="SizeNWSE" Opacity="0.35" ToolTip="Drag to resize Mochi">
        <Thumb.Template>
          <ControlTemplate TargetType="Thumb">
            <Path Data="M12,0 L12,12 L0,12 Z" Fill="#C02D1E3A"/>
          </ControlTemplate>
        </Thumb.Template>
      </Thumb>
    </Grid>
  </StackPanel>
</Window>
'@
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$lines = $win.FindName('Lines')
$petBox = $win.FindName('PetBox')
$pet = $win.FindName('Pet')
$facing = $win.FindName('Facing')
$grip = $win.FindName('Grip')

# Mochi's face, for the window, the tray and the startup shortcut.
$IconFile = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\assets\mochi.ico'))
if (Test-Path $IconFile) {
  try { $win.Icon = [Windows.Media.Imaging.BitmapFrame]::Create((New-Object Uri $IconFile)) } catch { Write-Log "window icon: $_" }
}
$win.Add_SourceInitialized({
  try {
    $hwnd = (New-Object Windows.Interop.WindowInteropHelper $win).Handle
    Write-Log "hidden from Alt+Tab: $([MochiNative]::HideFromAltTab($hwnd))"
  } catch { Write-Log "alt-tab: $_" }
})

function New-Brush([string]$color) { New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString($color)) }
$Ink = New-Brush '#2D1E3A'
$Faded = New-Brush '#6B5F78'
$LinePaper = @{ alert = (New-Brush '#FFF3C4'); done = (New-Brush '#FFFFFF'); progress = (New-Brush '#EEE8F8') }

function Set-Scale([double]$scale) {
  $script:S.scale = [Math]::Round([Math]::Max(1.5, [Math]::Min(14.0, $scale)) * 2) / 2
  $pet.Width = $script:W * $script:S.scale
  $pet.Height = $script:H * $script:S.scale
  $script:LinesKey = ''  # redraw the lines at the new size
}

# Mochi stays put by its feet: the window grows up and out from the bottom centre.
$script:Anchor = $null
function Set-Anchor {
  $script:Anchor = @{ X = $win.Left + $win.ActualWidth / 2; Y = $win.Top + $win.ActualHeight }
  Save-Position
}
function Save-Position {
  if ($null -eq $script:Anchor) { return }
  $script:S.x = $script:Anchor.X; $script:S.y = $script:Anchor.Y
  Save-Settings
}
function Apply-Anchor {
  if ($null -eq $script:Anchor) { return }
  $win.Left = $script:Anchor.X - $win.ActualWidth / 2
  $win.Top = $script:Anchor.Y - $win.ActualHeight
}
$win.Add_SizeChanged({ Apply-Anchor })
$win.Add_Loaded({
  try {
    $area = [Windows.SystemParameters]::WorkArea
    if ($null -ne $script:S.x -and $null -ne $script:S.y) {
      # Back where it was, kept on screen in case the screens changed.
      $x = [Math]::Max($area.Left + 20, [Math]::Min($area.Right - 20, [double]$script:S.x))
      $y = [Math]::Max($area.Top + 60, [Math]::Min($area.Bottom, [double]$script:S.y))
      $script:Anchor = @{ X = $x; Y = $y }
    } else {
      $script:Anchor = @{ X = $area.Right - 120; Y = $area.Bottom - 8 }
    }
    Apply-Anchor
    Write-Log ('shown at {0:0},{1:0} size {2:0}x{3:0}' -f $win.Left, $win.Top, $win.ActualWidth, $win.ActualHeight)
  } catch { Write-Log "load: $_" }
})

# ---------------------------------------------------------------- sound

$script:Player = New-Object Windows.Media.MediaPlayer
$script:IsRinging = $false
$script:Player.Add_MediaEnded({
  if ($script:IsRinging) { $script:Player.Position = [TimeSpan]::Zero; $script:Player.Play() }
})
$script:Player.Add_MediaFailed({ Write-Log "sound failed: $($_.ErrorException.Message)"; $script:IsRinging = $false })
function Get-SoundFile {
  switch ([string]$script:S.soundChoice) {
    'chime' { return $ChimeSound }
    'custom' { if ($script:S.soundFile -and (Test-Path $script:S.soundFile)) { return [string]$script:S.soundFile } }
    default { if (Test-Path $PhoneSound) { return $PhoneSound } }
  }
  return $ChimeSound
}
function Set-Ringing([bool]$on) {
  if ($on -and -not $script:IsRinging) {
    $script:IsRinging = $true
    $script:Player.Open((New-Object Uri (Get-SoundFile)))
    $script:Player.Play()
  } elseif (-not $on -and $script:IsRinging) {
    $script:IsRinging = $false
    $script:Player.Stop()
  }
}
function Restart-Ringing { if ($script:IsRinging) { Set-Ringing $false; Update-State } }
$script:Tester = New-Object Windows.Media.MediaPlayer

# ---------------------------------------------------------------- sessions

$script:Cache = @{}        # file -> last good report, so a half-written file never blinks a session away
$script:AckDone = @{}      # session -> finishedAt you have seen
$script:AckAlert = @{}     # session -> alertSince you have seen
$script:LastSeen = @{}     # session -> the last seenAt it reported
$script:HushAlert = @{}    # session -> alertSince hushed because you were in Claude (line kept)
$script:HushDone = @{}     # session -> finishedAt hushed the same way
$script:WasInFront = $false

# Whether the Claude app's window is the one in front. For tests: MOCHI_TEST_FOREGROUND=1
# pretends so; =file pretends so while a file named test-foreground sits in Mochi's folder.
function Test-ClaudeInFront {
  if ($env:MOCHI_TEST_FOREGROUND -eq 'file') { return (Test-Path (Join-Path $Dir 'test-foreground')) }
  if ($env:MOCHI_TEST_FOREGROUND) { return $true }
  try { return [MochiNative]::ForegroundProcess() -eq 'Claude' } catch { return $false }
}

# Milliseconds since the last mouse or keyboard input anywhere (0 for tests that pretend).
function Get-IdleMs {
  if ($env:MOCHI_TEST_FOREGROUND) { return 0 }
  try { return [MochiNative]::IdleMilliseconds() } catch { return [double]::MaxValue }
}
$script:FirstPoll = $true
$script:ProjectNo = @{}    # session -> its "Project N" number, for chats with no real folder
$script:ProjectCount = 0
$script:ChatNo = @{}       # session -> its number among chats in the same folder
$script:FolderCount = @{}
$script:Sessions = @()
$script:Attention = @()
$script:Mood = 'sleeping'

function Get-Now { [DateTimeOffset]::Now.ToUnixTimeMilliseconds() }
function Get-Key($s) { if ($s.session) { [string]$s.session } else { [string]$s.cli } }

# ---------------------------------------------------------------- the cloud link
# Sessions away from this PC (cloud sessions, other machines) can't write the
# sessions folder. Given the link secret (right-click > Connect cloud sessions...,
# kept in desktop.json as "link", or the MOCHI_LINK environment variable), they send
# encrypted, signed reports through ntfy.sh, and Mochi listens there. No account,
# no server of yours. From the secret come the ntfy topic, an encryption key and a
# signing key (the same construction as hooks/link.ts):
#   topic = "mochi_" + first 40 hex of SHA256("mochi-topic-v1:" + secret)
#   enc   = SHA256("mochi-enc-v1:" + secret)    mac = SHA256("mochi-mac-v1:" + secret)
#   message = base64url(nonce[16] + ciphertext + HMAC-SHA256(mac, "mochi-v1" + nonce + ciphertext))
#   keystream block i = SHA256(enc + nonce + uint32be(i))
# Anything unsigned, malformed, older than 15 minutes or replayed is dropped unread.
# Nothing from a message is ever opened or run: it only becomes a line of text.

$Utf8 = New-Object System.Text.UTF8Encoding($false)
function Get-Sha256([byte[]]$bytes) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return , $sha.ComputeHash($bytes) } finally { $sha.Dispose() }
}
function Join-Bytes { $list = New-Object System.Collections.Generic.List[byte]; foreach ($a in $args) { $list.AddRange([byte[]]$a) }; return , $list.ToArray() }
function ConvertTo-Hex([byte[]]$b) { return (($b | ForEach-Object { $_.ToString('x2') }) -join '') }
function ConvertFrom-Base64Url([string]$s) {
  $t = $s.Replace('-', '+').Replace('_', '/')
  switch ($t.Length % 4) { 2 { $t += '==' } 3 { $t += '=' } 1 { throw 'bad base64url' } }
  return , [Convert]::FromBase64String($t)
}
function Get-Counter([int]$n) { return , [byte[]]@(($n -shr 24) -band 255; ($n -shr 16) -band 255; ($n -shr 8) -band 255; $n -band 255) }
function ConvertTo-Base64Url([byte[]]$b) { return [Convert]::ToBase64String($b).TrimEnd('=').Replace('+', '-').Replace('/', '_') }

function Get-LinkKeys([string]$secret) {
  return [pscustomobject]@{
    topic = 'mochi_' + (ConvertTo-Hex (Get-Sha256 $Utf8.GetBytes("mochi-topic-v1:$secret"))).Substring(0, 40)
    enc = Get-Sha256 $Utf8.GetBytes("mochi-enc-v1:$secret")
    mac = Get-Sha256 $Utf8.GetBytes("mochi-mac-v1:$secret")
  }
}

# Checks the signature, then decrypts; $null for anything that doesn't check out.
function Open-LinkMessage($keys, [string]$text) {
  if ($text.Length -lt 64 -or $text.Length -gt 4000 -or $text -notmatch '^[A-Za-z0-9_-]+$') { return $null }
  try { $raw = ConvertFrom-Base64Url $text } catch { return $null }
  if ($raw.Length -lt 49) { return $null }
  $nonce = [byte[]]$raw[0..15]
  $ct = [byte[]]$raw[16..($raw.Length - 33)]
  $tag = [byte[]]$raw[($raw.Length - 32)..($raw.Length - 1)]
  $h = New-Object Security.Cryptography.HMACSHA256 -ArgumentList (, [byte[]]$keys.mac)
  try { $want = $h.ComputeHash((Join-Bytes $Utf8.GetBytes('mochi-v1') $nonce $ct)) } finally { $h.Dispose() }
  $diff = 0
  for ($i = 0; $i -lt 32; $i++) { $diff = $diff -bor ($want[$i] -bxor $tag[$i]) }
  if ($diff -ne 0) { return $null }
  $pt = New-Object byte[] $ct.Length
  for ($i = 0; $i -lt $ct.Length; $i += 32) {
    $n = [int]($i / 32)
    $ks = Get-Sha256 (Join-Bytes $keys.enc $nonce (Get-Counter $n))
    for ($j = 0; $j -lt 32 -and ($i + $j) -lt $ct.Length; $j++) { $pt[$i + $j] = $ct[$i + $j] -bxor $ks[$j] }
  }
  try { return $Utf8.GetString($pt) | ConvertFrom-Json } catch { return $null }
}

# Encrypts and signs, as a remote session does (for the tests).
function New-LinkMessage($keys, [string]$plaintext, [byte[]]$nonce = $null) {
  if (-not $nonce) { $nonce = New-Object byte[] 16; $rng = [Security.Cryptography.RandomNumberGenerator]::Create(); $rng.GetBytes($nonce); $rng.Dispose() }
  $pt = $Utf8.GetBytes($plaintext)
  $ct = New-Object byte[] $pt.Length
  for ($i = 0; $i -lt $pt.Length; $i += 32) {
    $n = [int]($i / 32)
    $ks = Get-Sha256 (Join-Bytes $keys.enc $nonce (Get-Counter $n))
    for ($j = 0; $j -lt 32 -and ($i + $j) -lt $pt.Length; $j++) { $ct[$i + $j] = $pt[$i + $j] -bxor $ks[$j] }
  }
  $h = New-Object Security.Cryptography.HMACSHA256 -ArgumentList (, [byte[]]$keys.mac)
  try { $tag = $h.ComputeHash((Join-Bytes $Utf8.GetBytes('mochi-v1') $nonce $ct)) } finally { $h.Dispose() }
  return ConvertTo-Base64Url (Join-Bytes $nonce $ct $tag)
}

# A checked report becomes a session like a local one, with only plain text in it.
function ConvertFrom-LinkReport($m) {
  if ($null -eq $m -or $m.v -ne 1 -or [string]$m.k -notmatch '^[0-9a-f]{16}$') { return $null }
  $project = (([string]$m.p) -replace '[\x00-\x1F\x7F]', '').Trim()
  if ($project.Length -gt 40) { $project = $project.Substring(0, 40) }
  $alert = if ($m.a -eq 'question' -or $m.a -eq 'permission') { [string]$m.a } else { $null }
  $mood = if ($m.m -eq 'working') { 'working' } else { 'idle' }
  return [pscustomobject]@{
    v = 1; session = $null; cli = "remote_$($m.k)"; project = $project; cwd = ''
    mood = $mood; alert = $alert; alertSince = [double]$m.as; startedAt = [double]$m.s; finishedAt = [double]$m.f
    updated = [double]$m.u; ended = [bool]$m.e; remote = $true
  }
}

$script:Remote = @{}          # remote_<k> -> its latest report
$script:LinkKeys = $null
$script:LinkClient = $null
$script:LinkConnect = $null   # the request being made
$script:LinkReader = $null    # the open stream
$script:LinkLine = $null      # the line being read
$script:LinkHeard = 0         # when the stream last said anything (ntfy sends keepalives)
$script:LinkNext = 0          # when to connect again
$script:LinkBackoff = 5000
$script:LinkCancel = $null

function Get-LinkSecret {
  $v = [string]$script:S.link
  if (-not $v) { $v = [Environment]::GetEnvironmentVariable('MOCHI_LINK', 'Process') }
  if (-not $v) { $v = [Environment]::GetEnvironmentVariable('MOCHI_LINK', 'User') }
  $v = "$v".Trim()
  if ($v -match '^[A-Za-z0-9_-]{43}$') { return $v } else { return '' }
}

function Stop-Link {
  try { if ($script:LinkCancel) { $script:LinkCancel.Cancel() } } catch { }
  try { if ($script:LinkReader) { $script:LinkReader.Dispose() } } catch { }
  $script:LinkConnect = $null; $script:LinkReader = $null; $script:LinkLine = $null; $script:LinkCancel = $null
}

function Start-Link {
  Stop-Link
  $secret = Get-LinkSecret
  $script:LinkKeys = if ($secret) { Get-LinkKeys $secret } else { $null }
  $script:Remote = @{}
  if (-not $script:LinkKeys) { return }
  if (-not $script:LinkClient) {
    Add-Type -AssemblyName System.Net.Http
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $script:LinkClient = New-Object System.Net.Http.HttpClient
    $script:LinkClient.Timeout = [Threading.Timeout]::InfiniteTimeSpan
    $script:LinkClient.DefaultRequestHeaders.Add('User-Agent', 'mochi-pixel-pet')
  }
  $script:LinkNext = 0
  Write-Log 'link: on'
}

# Called once a second; never waits on the network.
function Update-Link {
  if (-not $script:LinkKeys) { return }
  $now = Get-Now
  try {
    if ($script:LinkReader) {
      # Every line that has come in since the last tick.
      for ($i = 0; $i -lt 50; $i++) {
        if (-not $script:LinkLine) { $script:LinkLine = $script:LinkReader.ReadLineAsync() }
        if (-not $script:LinkLine.IsCompleted) { break }
        $line = $script:LinkLine.Result
        $script:LinkLine = $null
        if ($null -eq $line) { throw 'stream closed' }
        $script:LinkHeard = $now
        $script:LinkBackoff = 5000
        if ($line.Length -gt 8000) { continue }
        try { $evt = $line | ConvertFrom-Json } catch { continue }
        if ($evt.event -ne 'message') { continue }
        $s = ConvertFrom-LinkReport (Open-LinkMessage $script:LinkKeys ([string]$evt.message))
        if ($null -eq $s) { continue }
        if ([Math]::Abs($now - $s.updated) -gt 900000) { continue }          # stale or far-off clock
        $old = $script:Remote[$s.cli]
        if ($old -and $s.updated -le $old.updated) { continue }             # replayed
        $script:Remote[$s.cli] = $s
      }
      if ($now - $script:LinkHeard -gt 120000) { throw 'stream silent' }
      return
    }
    if ($script:LinkConnect) {
      if (-not $script:LinkConnect.IsCompleted) {
        if ($now - $script:LinkHeard -gt 30000) { throw 'connect timed out' }
        return
      }
      $res = $script:LinkConnect.Result
      $script:LinkConnect = $null
      if (-not $res.IsSuccessStatusCode) { throw "ntfy said $([int]$res.StatusCode)" }
      $script:LinkReader = New-Object IO.StreamReader($res.Content.ReadAsStreamAsync().Result, $Utf8)
      $script:LinkHeard = $now
      return
    }
    if ($now -lt $script:LinkNext) { return }
    $script:LinkCancel = New-Object Threading.CancellationTokenSource
    $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, "https://ntfy.sh/$($script:LinkKeys.topic)/json")
    $script:LinkConnect = $script:LinkClient.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead, $script:LinkCancel.Token)
    $script:LinkHeard = $now
  } catch {
    Write-Log "link: $($_.Exception.Message -replace '[\r\n]+', ' ')"
    Stop-Link
    $script:LinkNext = $now + $script:LinkBackoff
    $script:LinkBackoff = [Math]::Min($script:LinkBackoff * 2, 300000)
  }
}

# Makes a new secret (any old one stops working), saves it, and puts it on the clipboard.
function New-LinkSecret {
  $bytes = New-Object byte[] 32
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create(); $rng.GetBytes($bytes); $rng.Dispose()
  $script:S.link = ConvertTo-Base64Url $bytes
  Save-Settings
  Start-Link
}

function Read-Sessions {
  $now = Get-Now
  Update-Link
  $live = New-Object System.Collections.ArrayList
  foreach ($f in @(Get-ChildItem -Path $SessionsDir -Filter '*.json' -ErrorAction SilentlyContinue)) {
    $s = $null
    try { $s = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json } catch { $s = $script:Cache[$f.FullName] }
    if ($null -eq $s) { continue }
    $script:Cache[$f.FullName] = $s
    $age = $now - [double]$s.updated
    if ($age -gt 86400000) { Remove-Item -LiteralPath $f.FullName -ErrorAction SilentlyContinue; continue }
    if ($s.ended -or $age -gt 45000) { continue }
    [void]$live.Add($s)
  }
  # A remote session sends a heartbeat every 10 minutes; one silent for 25 is gone.
  foreach ($k in @($script:Remote.Keys)) {
    $s = $script:Remote[$k]
    if ($s.ended -or ($now - $s.updated) -gt 1500000) { $script:Remote.Remove($k); continue }
    [void]$live.Add($s)
  }
  return , $live
}

function Get-Ack($table, $key) { if ($table.ContainsKey($key)) { [double]$table[$key] } else { 0.0 } }

function Test-DonePending($s) {
  $finished = [double]$s.finishedAt
  return ($finished -gt 0) -and ($finished -gt [double]$s.startedAt) -and (-not $s.alert) -and
    ($s.mood -ne 'working') -and ($finished -gt (Get-Ack $script:AckDone (Get-Key $s)))
}

function Open-Session($s) {
  $id = if ($s) { [string]$s.session } else { '' }
  if ($id -match '^local_[A-Za-z0-9-]{1,64}$') {
    $url = "claude://code/continue?session=$id&source=desktop_action"
  } else {
    $url = 'claude://code/continue?session=last&source=desktop_action'
  }
  if ($env:MOCHI_SNAPSHOT) { Write-Log "test: would open $url"; return }  # tests never open the app
  # Only ever the Claude app's own continue link, built here from a checked id or 'last'.
  if ($url -notmatch '^claude://code/continue\?session=(last|local_[A-Za-z0-9-]{1,64})&source=desktop_action$') { Write-Log 'open refused'; return }
  try { Start-Process $url } catch { Write-Log "open failed: $_" }
}

function Set-Seen($s) {
  $key = Get-Key $s
  $script:AckDone[$key] = [double]$s.finishedAt
  $script:AckAlert[$key] = [double]$s.alertSince
}

# A clicked line goes away until something new happens in that chat:
# a new question, a new finished reply, or a new turn starting.
$script:DismissAlert = @{}     # session -> alertSince whose line was clicked away
$script:DismissProgress = @{}  # session -> startedAt whose "working" line was clicked away
function Invoke-LineClick($line) {
  $s = $line.session
  $key = Get-Key $s
  Set-Seen $s
  if ($line.style -eq 'alert') { $script:DismissAlert[$key] = [double]$s.alertSince }
  if ($line.style -eq 'progress') { $script:DismissProgress[$key] = [double]$s.startedAt }
  Open-Session $s
  Update-State
}

function New-Line([string]$text, $session, [string]$style) {
  $border = New-Object Windows.Controls.Border
  $border.CornerRadius = New-Object Windows.CornerRadius(7)
  $border.BorderBrush = $(if ($style -eq 'progress') { $Faded } else { $Ink })
  $border.BorderThickness = New-Object Windows.Thickness(2)
  $border.Background = $LinePaper[$style]
  $border.Padding = New-Object Windows.Thickness(8, 3, 8, 3)
  $border.Margin = New-Object Windows.Thickness(0, 0, 0, 3)
  $border.HorizontalAlignment = 'Center'
  $border.Cursor = [Windows.Input.Cursors]::Hand
  $border.ToolTip = 'Open this chat'
  $label = New-Object Windows.Controls.TextBlock
  $label.Text = $text
  $label.Foreground = $(if ($style -eq 'progress') { $Faded } else { $Ink })
  $label.FontFamily = New-Object Windows.Media.FontFamily('Consolas')
  $label.FontWeight = 'Bold'
  $label.FontSize = [Math]::Max(11, 7 + $script:S.scale * 1.4)
  $border.Child = $label
  $border.Tag = [pscustomobject]@{ session = $session; style = $style }
  $border.Add_MouseLeftButtonUp({
    param($sender, $e)
    try {
      $e.Handled = $true
      Invoke-LineClick $sender.Tag
    } catch { Write-Log "line click: $_" }
  })
  return $border
}

function Update-Lines {
  $key = (@($script:Attention | ForEach-Object { "$($_.text)|$($_.style)" }) -join "`n") + "|$($script:S.scale)"
  if ($key -eq $script:LinesKey) { return }
  $script:LinesKey = $key
  $lines.Children.Clear()
  foreach ($a in $script:Attention) { [void]$lines.Children.Add((New-Line $a.text $a.session $a.style)) }
  if ($script:Attention.Count -gt 0) {
    # A little tail from the speech lines down to Mochi's head.
    $tail = New-Object Windows.Shapes.Path
    $tail.Data = [Windows.Media.Geometry]::Parse('M0,0 L12,0 L6,8 Z')
    $tail.Fill = $Ink
    $tail.HorizontalAlignment = 'Center'
    $tail.Margin = New-Object Windows.Thickness(0, -3, 0, 0)
    [void]$lines.Children.Add($tail)
  }
}

function Update-State {
  if ((Test-Path $FramesFile) -and (Get-Item -LiteralPath $FramesFile).LastWriteTimeUtc -ne $script:FramesStamp) {
    # New art from the mod: draw with it from now on.
    try { Import-Frames; Set-Scale $script:S.scale; Write-Log 'art reloaded' } catch { Write-Log "art reload: $_" }
  }

  $sessions = Read-Sessions
  if ($script:FirstPoll) {
    # What was already done or waiting before Mochi started counts as seen: no sound for old news.
    foreach ($s in $sessions) { Set-Seen $s }
    $script:FirstPoll = $false
  }

  # Are you in Claude right now? Coming to its window hushes whatever was ringing; being in
  # it and active (input in the last 2 minutes) means a new question or reply is in front of
  # you, so it never rings. The lines stay either way, until you answer or open them.
  $inFront = Test-ClaudeInFront
  $cameToFront = $inFront -and -not $script:WasInFront
  $script:WasInFront = $inFront
  $watching = $inFront -and (Get-IdleMs) -lt 120000
  $script:FrontState = "in front $inFront, watching $watching"

  # You typed in a chat (its prompt box reports it): with Claude in front, that chat is seen.
  foreach ($s in $sessions) {
    $key = Get-Key $s
    $seen = [double]$s.seenAt
    if ($seen -le (Get-Ack $script:LastSeen $key)) { continue }
    $script:LastSeen[$key] = $seen
    if (-not $inFront) { continue }
    if ($s.alert -and $seen -ge [double]$s.alertSince) { $script:AckAlert[$key] = [double]$s.alertSince }
    if ([double]$s.finishedAt -gt 0 -and $seen -ge [double]$s.finishedAt) { $script:AckDone[$key] = [double]$s.finishedAt }
  }
  $script:Sessions = $sessions

  # Names: a chat with no real project folder (the app's scratch folders) is
  # "Project 1", "Project 2"...; chats sharing a folder are told apart as
  # "<folder> #1", "#2"... Numbers are handed out as Mochi first sees each chat
  # and kept while it runs.
  $byProject = @{}
  foreach ($s in ($sessions | Sort-Object { [double]$_.startedAt })) {
    $key = Get-Key $s
    $base = [string]$s.project
    if ($base -match '^scratch-\d{4}-\d{2}-\d{2}' -or [string]$s.cwd -match '[\\/]scratch-workspaces[\\/]' -or -not $base) {
      if (-not $script:ProjectNo.ContainsKey($key)) { $script:ProjectNo[$key] = ++$script:ProjectCount }
      $base = "Project $($script:ProjectNo[$key])"
    } elseif (-not $script:ChatNo.ContainsKey($key)) {
      if (-not $script:FolderCount.ContainsKey($base)) { $script:FolderCount[$base] = 0 }
      $script:ChatNo[$key] = ++$script:FolderCount[$base]
    }
    if (-not $byProject.ContainsKey($base)) { $byProject[$base] = New-Object System.Collections.ArrayList }
    [void]$byProject[$base].Add($s)
  }
  $named = foreach ($base in $byProject.Keys) {
    $group = $byProject[$base]
    foreach ($s in $group) {
      $name = $base
      if ($group.Count -gt 1 -and $script:ChatNo.ContainsKey((Get-Key $s))) { $name = "$base #$($script:ChatNo[(Get-Key $s)])" }
      if ($s.remote) { $name = [string][char]0x2601 + " $name" }  # a cloud: it runs away from this PC
      [pscustomobject]@{ s = $s; name = $name }
    }
  }

  $attention = New-Object System.Collections.ArrayList
  $ring = $false
  $ringAlert = $false
  $ringDone = $false
  foreach ($n in ($named | Sort-Object { [double]$_.s.alertSince })) {
    $s = $n.s
    if ($s.alert) {
      # The line stays until the question is answered or you click it; the waving and the
      # sound stop once seen or hushed.
      $key = Get-Key $s
      $since = [double]$s.alertSince
      if ($since -le (Get-Ack $script:DismissAlert $key)) { continue }
      $what = if ($s.alert -eq 'question') { 'has a question!' } else { 'needs your approval!' }
      [void]$attention.Add([pscustomobject]@{ text = "$($n.name): $what"; session = $s; style = 'alert' })
      if ($since -gt (Get-Ack $script:AckAlert $key) -and $since -gt (Get-Ack $script:HushAlert $key)) {
        if ($watching -or $cameToFront) { $script:HushAlert[$key] = $since } else { $ring = $true; $ringAlert = $true }
      }
    }
  }
  foreach ($n in ($named | Sort-Object { - [double]$_.s.finishedAt })) {
    if (Test-DonePending $n.s) {
      [void]$attention.Add([pscustomobject]@{ text = "$($n.name): done " + [char]0x2713; session = $n.s; style = 'done' })
      $key = Get-Key $n.s
      $at = [double]$n.s.finishedAt
      if ($at -gt (Get-Ack $script:HushDone $key)) {
        if ($watching -or $cameToFront) { $script:HushDone[$key] = $at } else { $ring = $true; $ringDone = $true }
      }
    }
  }
  $needsYou = $attention.Count
  if ($script:S.showProgress) {
    foreach ($n in ($named | Sort-Object { [double]$_.s.startedAt })) {
      if ($n.s.mood -eq 'working' -and -not $n.s.alert -and [double]$n.s.startedAt -gt (Get-Ack $script:DismissProgress (Get-Key $n.s))) {
        [void]$attention.Add([pscustomobject]@{ text = "$($n.name): working" + [char]0x2026; session = $n.s; style = 'progress' })
      }
    }
  }
  $script:Attention = @($attention | Select-Object -First 8)
  $script:NeedsYou = $needsYou -gt 0

  $mood = 'idle'
  if ($sessions.Count -eq 0) { $mood = 'sleeping' }
  elseif ($ringAlert) { $mood = 'alert' }
  elseif ($ringDone) { $mood = 'happy' }
  elseif (@($sessions | Where-Object { $_.mood -eq 'working' }).Count -gt 0) { $mood = 'working' }
  elseif (@($sessions | Where-Object { $_.mood -ne 'sleeping' }).Count -eq 0) { $mood = 'sleeping' }
  $script:Mood = $mood

  $tip = if ($sessions.Count -eq 0) { 'Mochi: no Claude chats running' } else {
    'Mochi' + "`n" + ((@($named | ForEach-Object { "$($_.name): $($_.s.mood)" })) -join "`n") + "`nClick to open, drag to move, right-click for options"
  }
  $petBox.ToolTip = $tip

  Update-Lines
  Set-Ringing ($ring -and [bool]$script:S.soundOn)
}

function Invoke-PetClick {
  # Open the chat that needs you most (or the one you used last), and hush the sound.
  $target = if ($script:Attention.Count -gt 0) { $script:Attention[0].session } else {
    $script:Sessions | Sort-Object { - [double]$_.updated } | Select-Object -First 1
  }
  foreach ($s in $script:Sessions) { Set-Seen $s }
  Open-Session $target
  Update-State
}

# ---------------------------------------------------------------- moving about
#
# One act at a time: standing (''), a walk, or the wall routine that ends every
# walk (bonk -> fallen -> getup -> groom, then off the other way or a rest).
# Above that, flying: DVD mode (the toggle) or the zoomies (after a long nap,
# until you catch Mochi with the cursor). In DVD mode the cursor on Mochi holds it.

Add-Type -AssemblyName System.Windows.Forms
$script:Rng = New-Object Random
$script:Clock = [Diagnostics.Stopwatch]::StartNew()
$script:LastMotion = 0
$script:Dragging = $false
$script:Act = ''
$script:ActUntil = 0
$script:AfterGetup = 'groom'
$script:Heading = 1                       # the way Mochi faces: 1 right, -1 left
$script:NextWalk = 6000 + $script:Rng.Next(0, 10000)
$script:Bouncing = $false
$script:Held = $false
$script:Zoomies = $false
$script:SleepSince = 0
$script:AwakeUntil = 0
$script:Vel = @{ X = 150.0; Y = -150.0 }
$script:Tint = 0
$script:CurrentFrame = $null

# Caught after the zoomies, Mochi stays up a minute even if every chat sleeps.
function Get-Mood {
  if ($script:Mood -eq 'sleeping' -and $script:Clock.ElapsedMilliseconds -lt $script:AwakeUntil) { return 'idle' }
  return $script:Mood
}

function Start-Act([string]$act, [int]$ms) {
  $script:Act = $act
  $script:ActUntil = $script:Clock.ElapsedMilliseconds + $ms
}

function Stop-Acts {
  if ($script:Act -eq '') { return }
  $script:Act = ''
  $script:NextWalk = $script:Clock.ElapsedMilliseconds + $script:Rng.Next(8000, 25000)
  Save-Position
}

# Whether the cursor is on one of Mochi's drawn pixels, not the clear space around it.
function Test-CursorOnPet {
  $f = $script:CurrentFrame
  if ($null -eq $f -or $pet.ActualWidth -le 0) { return $false }
  $cursor = [System.Windows.Forms.Cursor]::Position
  $a = $pet.PointToScreen((New-Object Windows.Point(0, 0)))
  $b = $pet.PointToScreen((New-Object Windows.Point($pet.ActualWidth, $pet.ActualHeight)))
  $x0 = [Math]::Min($a.X, $b.X); $x1 = [Math]::Max($a.X, $b.X)
  $y0 = [Math]::Min($a.Y, $b.Y); $y1 = [Math]::Max($a.Y, $b.Y)
  if ($cursor.X -lt $x0 -or $cursor.X -ge $x1 -or $cursor.Y -lt $y0 -or $cursor.Y -ge $y1) { return $false }
  $cx = [int][Math]::Floor(($cursor.X - $x0) / ($x1 - $x0) * $script:W)
  $cy = [int][Math]::Floor(($cursor.Y - $y0) / ($y1 - $y0) * $script:H)
  # A pixel of slack all round, so a flying Mochi is not too hard to catch.
  for ($dy = -1; $dy -le 1; $dy++) {
    for ($dx = -1; $dx -le 1; $dx++) {
      $x = $cx + $dx; $y = $cy + $dy
      if ($x -ge 0 -and $x -lt $script:W -and $y -ge 0 -and $y -lt $script:H -and $f.px[($y * $script:W + $x) * 4 + 3] -gt 0) { return $true }
    }
  }
  return $false
}

function Step-Motion {
  $t = $script:Clock.ElapsedMilliseconds
  $dt = [Math]::Min(100, $t - $script:LastMotion) / 1000.0
  $script:LastMotion = $t
  if ($script:Dragging -or $null -eq $script:Anchor) { return }
  $area = [Windows.SystemParameters]::WorkArea
  $w = $win.ActualWidth
  $h = $win.ActualHeight
  $mood = Get-Mood

  # Napping too long brings on the zoomies; a chat waking up ends them.
  if ($mood -eq 'sleeping' -and -not $script:S.dvdMode) {
    if ($script:SleepSince -eq 0) { $script:SleepSince = $t }
    elseif (-not $script:Zoomies -and $t - $script:SleepSince -ge [double]$script:S.napMinutes * 60000) { $script:Zoomies = $true }
  } else {
    $script:SleepSince = 0
    if ($script:Zoomies -and $script:Mood -ne 'sleeping') { $script:Zoomies = $false }
  }

  # Flying: DVD mode (parked while a chat needs you) or the zoomies.
  if (($script:S.dvdMode -and -not $script:NeedsYou) -or $script:Zoomies) {
    if (-not $script:Bouncing) {
      $script:Bouncing = $true
      $script:Act = ''
      $speed = 150.0
      $script:Vel = @{ X = $speed * $(if ($script:Rng.Next(2) -eq 0) { -1 } else { 1 }); Y = - $speed }
    }
    if (Test-CursorOnPet) {
      if ($script:Zoomies) {
        # Caught! Back on its feet where it was caught, and awake for a while.
        $script:Zoomies = $false
        $script:Bouncing = $false
        $script:Held = $false
        $script:SleepSince = 0
        $script:AwakeUntil = $t + 60000
        $script:AfterGetup = ''
        Start-Act 'getup' 540
        Save-Position
        return
      }
      $script:Held = $true
      return
    }
    $script:Held = $false
    $x = $script:Anchor.X + $script:Vel.X * $dt
    $y = $script:Anchor.Y + $script:Vel.Y * $dt
    $hit = $false
    if ($x - $w / 2 -lt $area.Left) { $x = $area.Left + $w / 2; $script:Vel.X = [Math]::Abs($script:Vel.X); $hit = $true }
    if ($x + $w / 2 -gt $area.Right) { $x = $area.Right - $w / 2; $script:Vel.X = - [Math]::Abs($script:Vel.X); $hit = $true }
    if ($y - $h -lt $area.Top) { $y = $area.Top + $h; $script:Vel.Y = [Math]::Abs($script:Vel.Y); $hit = $true }
    if ($y -gt $area.Bottom) { $y = $area.Bottom; $script:Vel.Y = - [Math]::Abs($script:Vel.Y); $hit = $true }
    if ($hit) { $script:Tint = ($script:Tint + 1) % 5 }
    $script:Anchor = @{ X = $x; Y = $y }
    Apply-Anchor
    return
  }
  if ($script:Bouncing) {
    $script:Bouncing = $false
    $script:Held = $false
    $script:NextWalk = $t + $script:Rng.Next(8000, 25000)
    Save-Position
  }

  # The wall routine plays out, unless a chat needs Mochi for something else.
  if ($script:Act -in @('bonk', 'fallen', 'getup', 'groom')) {
    if ($mood -ne 'idle') { Stop-Acts; return }
    if ($t -lt $script:ActUntil) { return }
    switch ($script:Act) {
      'bonk' { Start-Act 'fallen' 1800 }
      'fallen' { $script:AfterGetup = 'groom'; Start-Act 'getup' 540 }
      'getup' { if ($script:AfterGetup -eq 'groom') { Start-Act 'groom' 2720 } else { Stop-Acts } }
      'groom' {
        if ($script:S.wander -and $script:Rng.Next(2) -eq 0) { $script:Heading = - $script:Heading; $script:Act = 'walk' } else { Stop-Acts }
      }
    }
    return
  }

  # Walking: all the way to the edge of the screen, and into it.
  $half = 8 * $script:S.scale          # half of Mochi's body: the clear margin round it may hang off screen
  $left = $area.Left + $half
  $right = $area.Right - $half
  if ($script:Act -eq 'walk') {
    if ($mood -ne 'idle' -or -not $script:S.wander) { Stop-Acts; return }
    $x = $script:Anchor.X + $script:Heading * 34.0 * ($script:S.scale / 4) * $dt
    $isAtWall = $x -le $left -or $x -ge $right
    $x = [Math]::Max($left, [Math]::Min($right, $x))
    $script:Anchor = @{ X = $x; Y = $script:Anchor.Y }
    Apply-Anchor
    if ($isAtWall) { Start-Act 'bonk' 450 }
    return
  }
  if ($script:S.wander -and $mood -eq 'idle' -and $t -ge $script:NextWalk) {
    $dir = if ($script:Rng.Next(2) -eq 0) { -1 } else { 1 }
    if ($script:Anchor.X - 40 -lt $left) { $dir = 1 }
    if ($script:Anchor.X + 40 -gt $right) { $dir = -1 }
    if ($env:MOCHI_WALK_DIR) { $dir = [int]$env:MOCHI_WALK_DIR }  # for testing
    $script:Heading = $dir
    $script:Act = 'walk'
  }
}

# Being dragged about by the cursor: once a press has moved Mochi, not on a plain click.
$script:DragFrom = $null
function Test-Grabbed {
  if ($null -eq $script:DragFrom) { return $false }
  return [Math]::Abs($win.Left - $script:DragFrom[0]) -ge 3 -or [Math]::Abs($win.Top - $script:DragFrom[1]) -ge 3
}

function Get-Animation {
  if (Test-Grabbed) { return "hold$($script:Tint)" }
  if ($script:Bouncing) { if ($script:Held) { return "hold$($script:Tint)" }; return "bounce$($script:Tint)" }
  if ($script:Act) { return $script:Act }
  return (Get-Mood)
}

function Get-Facing { if ($script:Act -and -not $script:Bouncing -and -not (Test-Grabbed)) { return $script:Heading }; return 1 }

# ---------------------------------------------------------------- input

$pet.Add_MouseLeftButtonDown({
  param($sender, $e)
  try {
    $left = $win.Left; $top = $win.Top
    $script:Dragging = $true
    $script:DragFrom = @($left, $top)
    try { $win.DragMove() } finally { $script:Dragging = $false; $script:DragFrom = $null }
    if ([Math]::Abs($win.Left - $left) -lt 3 -and [Math]::Abs($win.Top - $top) -lt 3) {
      Invoke-PetClick
    } else {
      Set-Anchor
    }
  } catch { Write-Log "pet click: $_" }
})
$pet.Add_MouseWheel({
  param($sender, $e)
  try { Set-Scale ($script:S.scale + [Math]::Sign($e.Delta) * 0.5); Save-Settings } catch { Write-Log "wheel: $_" }
})
$grip.Add_DragStarted({ $script:GripStart = $script:S.scale; $script:GripMoved = 0.0; $script:Dragging = $true })
$grip.Add_DragDelta({
  param($sender, $e)
  try {
    $script:GripMoved += ($e.HorizontalChange + $e.VerticalChange) / 2
    Set-Scale ($script:GripStart + $script:GripMoved / [Math]::Max(8, $script:W))
  } catch { Write-Log "grip: $_" }
})
$grip.Add_DragCompleted({ $script:Dragging = $false; Save-Settings })
$petBox.Add_MouseEnter({ $grip.Opacity = 0.9 })
$petBox.Add_MouseLeave({ $grip.Opacity = 0.35 })

# ---------------------------------------------------------------- menu

$startupDir = [Environment]::GetFolderPath('Startup')
if (-not $startupDir) { $startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup' }
$StartupLink = Join-Path $startupDir 'Mochi.lnk'
function Set-StartWithWindows([bool]$on) {
  if ($on) {
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($StartupLink)
    $link.TargetPath = Join-Path $PSHOME 'powershell.exe'
    $link.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$PSCommandPath`""
    $link.WindowStyle = 7
    $link.Description = 'Mochi, the Claude desktop pet'
    if (Test-Path $IconFile) { $link.IconLocation = "$IconFile,0" }
    $link.Save()
  } elseif (Test-Path $StartupLink) {
    Remove-Item -LiteralPath $StartupLink
  }
}

$menu = New-Object Windows.Controls.ContextMenu
function Add-MenuItem($parent, [string]$header, [scriptblock]$action, $isChecked = $null) {
  $item = New-Object Windows.Controls.MenuItem
  $item.Header = $header
  if ($null -ne $isChecked) { $item.IsCheckable = $true; $item.IsChecked = [bool]$isChecked }
  if ($action) {
    $item.Add_Click({
      param($sender, $e)
      try { & $sender.Tag $sender } catch { Write-Log "menu: $_" }
    })
    $item.Tag = $action
  }
  [void]$parent.Items.Add($item)
  return $item
}

[void](Add-MenuItem $menu 'Open Claude' { Open-Session $null })
$sizeMenu = Add-MenuItem $menu 'Size' $null
foreach ($size in @(@('Small', 3), @('Medium', 4), @('Large', 6), @('Huge', 9))) {
  $sizeItem = Add-MenuItem $sizeMenu $size[0] { param($item) Set-Scale ([double]$item.CommandParameter); Save-Settings }
  $sizeItem.CommandParameter = $size[1]
}
[void](Add-MenuItem $menu 'Show chats in progress' { param($item) $script:S.showProgress = $item.IsChecked; Save-Settings; Update-State } $script:S.showProgress)
[void](Add-MenuItem $menu 'Wander around' { param($item) $script:S.wander = $item.IsChecked; Save-Settings } $script:S.wander)
[void](Add-MenuItem $menu 'DVD bounce mode' { param($item) $script:S.dvdMode = $item.IsChecked; Save-Settings } $script:S.dvdMode)
[void](Add-MenuItem $menu 'Always on top' { param($item) $script:S.onTop = $item.IsChecked; $win.Topmost = $item.IsChecked; Save-Settings } ($script:S.onTop -ne $false))
[void]$menu.Items.Add((New-Object Windows.Controls.Separator))

$soundMenu = Add-MenuItem $menu 'Sound' $null
[void](Add-MenuItem $soundMenu 'Sound on' { param($item) $script:S.soundOn = $item.IsChecked; Save-Settings; Update-State } $script:S.soundOn)
[void]$soundMenu.Items.Add((New-Object Windows.Controls.Separator))
$script:SoundItems = @{}
function Set-SoundChoice([string]$choice) {
  $script:S.soundChoice = $choice; Save-Settings
  foreach ($k in @($script:SoundItems.Keys)) { $script:SoundItems[$k].IsChecked = ($k -eq $choice) }
  Restart-Ringing
}
$script:SoundItems['phone'] = Add-MenuItem $soundMenu 'Phone ringtone' { Set-SoundChoice 'phone' } ($script:S.soundChoice -eq 'phone')
$script:SoundItems['chime'] = Add-MenuItem $soundMenu 'Chime' { Set-SoundChoice 'chime' } ($script:S.soundChoice -eq 'chime')
$script:SoundItems['custom'] = Add-MenuItem $soundMenu 'Your own sound file...' {
  $dialog = New-Object Microsoft.Win32.OpenFileDialog
  $dialog.Title = 'Sound for Mochi'
  $dialog.Filter = 'Sound files (*.wav;*.mp3;*.wma;*.m4a)|*.wav;*.mp3;*.wma;*.m4a|All files (*.*)|*.*'
  if ($dialog.ShowDialog()) { $script:S.soundFile = $dialog.FileName; Set-SoundChoice 'custom' }
  else { Set-SoundChoice ([string]$script:S.soundChoice) }
} ($script:S.soundChoice -eq 'custom')
[void]$soundMenu.Items.Add((New-Object Windows.Controls.Separator))
[void](Add-MenuItem $soundMenu 'Play it once' { $script:Tester.Open((New-Object Uri (Get-SoundFile))); $script:Tester.Play() })

[void]$menu.Items.Add((New-Object Windows.Controls.Separator))
# Cloud sessions: the link key goes on the clipboard, never in a file other than desktop.json.
function Copy-LinkKey([bool]$fresh) {
  if ($fresh -or -not (Get-LinkSecret)) { New-LinkSecret }
  [Windows.Clipboard]::SetText((Get-LinkSecret))
  [void][Windows.MessageBox]::Show(
    "Mochi's cloud link key is on your clipboard.`n`n" +
    "Where your cloud sessions run, add an environment variable named MOCHI_LINK with this key as its value " +
    "(for cloud sessions: your cloud environment's settings). For another computer, see 'Cloud and remote sessions' in Mochi's README.`n`n" +
    "Keep the key private, like a password. Updates travel through ntfy.sh encrypted and signed with it; " +
    "ntfy.sh sees only scrambled bytes. 'New link key' cuts off every session using the old one.",
    'Mochi: cloud sessions')
}
$cloudMenu = Add-MenuItem $menu 'Cloud sessions' $null
[void](Add-MenuItem $cloudMenu 'Copy link key' { Copy-LinkKey $false })
[void](Add-MenuItem $cloudMenu 'New link key (cuts off the old one)' { Copy-LinkKey $true })
[void](Add-MenuItem $cloudMenu 'Turn off' { $script:S.link = $null; Save-Settings; Start-Link; Update-State })
[void](Add-MenuItem $menu 'Start when Claude starts' { param($item) $script:S.launchWithClaude = $item.IsChecked; Save-Settings } ($script:S.launchWithClaude -eq $true))
[void](Add-MenuItem $menu 'Start with Windows (adds Mochi.lnk to your Startup folder)' { param($item) Set-StartWithWindows $item.IsChecked } (Test-Path $StartupLink))
[void]$menu.Items.Add((New-Object Windows.Controls.Separator))
[void](Add-MenuItem $menu 'Quit Mochi' { Set-Ringing $false; $win.Close() })
$petBox.ContextMenu = $menu

# ---------------------------------------------------------------- run

Set-Scale ([double]$script:S.scale)
$win.Topmost = ($script:S.onTop -ne $false)
$pet.Source = $script:Moods['sleeping'][0].bmp
$script:Anim = ''
$script:AnimSince = [Diagnostics.Stopwatch]::StartNew()

$animation = New-Object Windows.Threading.DispatcherTimer
$animation.Interval = [TimeSpan]::FromMilliseconds(30)
$animation.Add_Tick({
  try {
    Step-Motion
    $name = Get-Animation
    if ($name -ne $script:Anim) { $script:Anim = $name; $script:AnimSince.Restart() }
    $flip = Get-Facing
    if ($facing.ScaleX -ne $flip) { $facing.ScaleX = $flip }
    $frames = $script:Moods[$name]
    if ($null -eq $frames) { $frames = $script:Moods['idle'] }
    $total = 0; foreach ($f in $frames) { $total += $f.ms }
    $t = $script:AnimSince.ElapsedMilliseconds % [Math]::Max(1, $total)
    foreach ($f in $frames) {
      if ($t -lt $f.ms) {
        $script:CurrentFrame = $f
        if (-not [object]::ReferenceEquals($pet.Source, $f.bmp)) { $pet.Source = $f.bmp }
        break
      }
      $t -= $f.ms
    }
  } catch { Write-Log "animate: $_" }
})
$poll = New-Object Windows.Threading.DispatcherTimer
$poll.Interval = [TimeSpan]::FromSeconds(1)
$poll.Add_Tick({ try { Update-State } catch { Write-Log "poll: $_" } })

try { Start-Link } catch { Write-Log "link: $_" }
try { Update-State } catch { Write-Log "first poll: $_" }
$animation.Start()
$poll.Start()
# A tray icon with Mochi's face: Mochi has no taskbar button and stays out of Alt+Tab,
# so this is where to find it. Left-click hides or shows it; right-click for the menu.
$script:Tray = New-Object System.Windows.Forms.NotifyIcon
try { $script:Tray.Icon = if (Test-Path $IconFile) { New-Object System.Drawing.Icon($IconFile) } else { [System.Drawing.SystemIcons]::Application } } catch { Write-Log "tray icon: $_" }
$script:Tray.Text = 'Mochi'
function Switch-Visible { if ($win.IsVisible) { $win.Hide() } else { $win.Show(); Apply-Anchor } }
$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$trayMenu.Items.Add('Show or hide Mochi', $null, { try { Switch-Visible } catch { Write-Log "tray: $_" } })
[void]$trayMenu.Items.Add('Open Claude', $null, { Open-Session $null })
[void]$trayMenu.Items.Add('-')
[void]$trayMenu.Items.Add('Quit Mochi', $null, { Set-Ringing $false; $win.Close() })
$script:Tray.ContextMenuStrip = $trayMenu
$script:Tray.Add_MouseClick({ param($sender, $e) if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { try { Switch-Visible } catch { Write-Log "tray: $_" } } })
$script:Tray.Visible = $true

$win.Add_Closed({
  Save-Position
  $script:Tray.Visible = $false
  $script:Tray.Dispose()
  Write-Log 'quit'
  [Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
})

# For testing: with MOCHI_SNAPSHOT set to a file prefix, save MOCHI_SNAPSHOT_COUNT
# pictures of the window (4 by default) MOCHI_SNAPSHOT_MS apart (1500 by default),
# as <prefix>-1.png ..., then quit. The first stroll starts after a second.
if ($env:MOCHI_SNAPSHOT) {
  $script:Shots = 0
  $script:ShotCount = if ($env:MOCHI_SNAPSHOT_COUNT) { [int]$env:MOCHI_SNAPSHOT_COUNT } else { 4 }
  $script:NextWalk = 1000
  $snap = New-Object Windows.Threading.DispatcherTimer
  $snap.Interval = [TimeSpan]::FromMilliseconds($(if ($env:MOCHI_SNAPSHOT_MS) { [int]$env:MOCHI_SNAPSHOT_MS } else { 1500 }))
  $snap.Add_Tick({
    try {
      $script:Shots++
      $content = $win.Content
      $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap([int][Math]::Ceiling($content.ActualWidth), [int][Math]::Ceiling($content.ActualHeight), 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
      $bmp.Render($content)
      $png = New-Object Windows.Media.Imaging.PngBitmapEncoder
      $png.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
      $out = [IO.File]::Create("$($env:MOCHI_SNAPSHOT)-$($script:Shots).png")
      $png.Save($out); $out.Close()
      Write-Log ("snapshot {0}: mood {1}, anim {2}, {3} lines, ringing {4}, at {5:0},{6:0}, $($script:FrontState)" -f $script:Shots, $script:Mood, $script:Anim, $script:Attention.Count, $script:IsRinging, $win.Left, $win.Top)
      if ($env:MOCHI_TEST_CLICK -and $script:Shots -eq [int]$env:MOCHI_TEST_CLICK -and $script:Attention.Count -gt 0) {
        Write-Log "test: clicking the line '$($script:Attention[0].text)'"
        Invoke-LineClick $script:Attention[0]
      }
      if ($script:Shots -ge $script:ShotCount) { Set-Ringing $false; $win.Close() }
    } catch { Write-Log "snapshot: $_" }
  })
  $snap.Start()
}

# Show, then run the message loop until Mochi quits (not ShowDialog: hiding a dialog would end it).
$win.Show()
[Windows.Threading.Dispatcher]::Run()
$script:Mutex.ReleaseMutex()
