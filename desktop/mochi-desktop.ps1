# Mochi on the desktop: a see-through, always-on-top window with the pixel pet.
#
# Every Claude Code session running the pixel-pet mod writes how it is doing to
# %USERPROFILE%\.claude\mochi\sessions\<session>.json. This window reads them
# once a second and:
#   - animates Mochi for the busiest state (question > done > working > idle > asleep),
#   - shows one speech line per chat that needs you; clicking a line opens that chat,
#   - opens the chat that needs you most when you click Mochi itself,
#   - loops a sound while a question waits or a finished chat is unseen.
# Drag Mochi to move it, drag the corner grip or turn the mouse wheel to resize,
# right-click for the menu. Settings live in %USERPROFILE%\.claude\mochi\desktop.json.
#
# Kept to ASCII: Windows PowerShell 5.1 reads a script without a BOM as ANSI.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

$Dir = Join-Path $env:USERPROFILE '.claude\mochi'
$SessionsDir = Join-Path $Dir 'sessions'
$FramesFile = Join-Path $Dir 'frames.json'
$SettingsFile = Join-Path $Dir 'desktop.json'
$LogFile = Join-Path $Dir 'desktop.log'
$DefaultSound = Join-Path $Dir 'chime.wav'
New-Item -ItemType Directory -Force -Path $SessionsDir | Out-Null

function Write-Log([string]$message) {
  try { Add-Content -Path $LogFile -Value ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $message) } catch { }
}

# One Mochi at a time: every Claude session tries to start one.
$isFirst = $false
$script:Mutex = New-Object System.Threading.Mutex($true, 'Local\MochiDesktopPet', [ref]$isFirst)
if (-not $isFirst) { return }
Write-Log 'started'

# ---------------------------------------------------------------- settings

$script:S = @{ x = $null; y = $null; scale = 4.0; soundOn = $true; soundFile = $DefaultSound; autoStart = $true }
if (Test-Path $SettingsFile) {
  try {
    $saved = [IO.File]::ReadAllText($SettingsFile) | ConvertFrom-Json
    foreach ($p in $saved.PSObject.Properties) { $script:S[$p.Name] = $p.Value }
  } catch { Write-Log "settings unreadable: $_" }
}
function Save-Settings {
  try { [IO.File]::WriteAllText($SettingsFile, ($script:S | ConvertTo-Json)) } catch { Write-Log "settings not saved: $_" }
}

# ---------------------------------------------------------------- the default chime

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
if (-not (Test-Path $DefaultSound)) { try { New-Chime $DefaultSound } catch { Write-Log "chime not made: $_" } }

# ---------------------------------------------------------------- frames

for ($i = 0; $i -lt 40 -and -not (Test-Path $FramesFile); $i++) { Start-Sleep -Milliseconds 250 }
if (-not (Test-Path $FramesFile)) { Write-Log 'no frames.json: start a Claude session with the pixel-pet mod first'; return }
$art = [IO.File]::ReadAllText($FramesFile) | ConvertFrom-Json

# Crop every frame to the pixels any frame uses, so Mochi has no wide empty margins.
$minX = $art.width; $minY = $art.height; $maxX = 0; $maxY = 0
foreach ($m in $art.moods.PSObject.Properties) {
  foreach ($f in $m.Value) {
    for ($y = 0; $y -lt $art.height; $y++) {
      $row = $f.rows[$y]
      $first = $row.IndexOfAny([char[]]'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ')
      if ($first -lt 0) { continue }
      $last = $row.LastIndexOfAny([char[]]'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ')
      if ($first -lt $minX) { $minX = $first }; if ($last -gt $maxX) { $maxX = $last }
      if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y }
    }
  }
}
$script:W = $maxX - $minX + 1
$script:H = $maxY - $minY + 1

$palette = New-Object 'System.Collections.Generic.Dictionary[char,byte[]]'
foreach ($p in $art.palette.PSObject.Properties) {
  $c = [Windows.Media.ColorConverter]::ConvertFromString($p.Value)
  $palette[[char]$p.Name] = [byte[]]@($c.B, $c.G, $c.R, $c.A)
}
$script:Moods = @{}
foreach ($m in $art.moods.PSObject.Properties) {
  $list = New-Object System.Collections.ArrayList
  foreach ($f in $m.Value) {
    $px = New-Object byte[] ($script:W * $script:H * 4)
    for ($y = 0; $y -lt $script:H; $y++) {
      $row = $f.rows[$y + $minY]
      for ($x = 0; $x -lt $script:W; $x++) {
        $ch = $row[$x + $minX]
        if ($ch -eq '.') { continue }
        $bgra = $palette[$ch]
        [Array]::Copy($bgra, 0, $px, ($y * $script:W + $x) * 4, 4)
      }
    }
    $bmp = New-Object Windows.Media.Imaging.WriteableBitmap($script:W, $script:H, 96, 96, [Windows.Media.PixelFormats]::Bgra32, $null)
    $bmp.WritePixels((New-Object Windows.Int32Rect(0, 0, $script:W, $script:H)), $px, $script:W * 4, 0)
    $bmp.Freeze()
    [void]$list.Add([pscustomobject]@{ ms = [int]$f.ms; bmp = $bmp })
  }
  $script:Moods[$m.Name] = $list
}

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
      <Image x:Name="Pet" Stretch="Fill" RenderOptions.BitmapScalingMode="NearestNeighbor" Cursor="Hand"/>
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
$grip = $win.FindName('Grip')

$Ink = New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString('#2D1E3A'))
$Paper = New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString('#FFFFFF'))
$AlertPaper = New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString('#FFF3C4'))

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
  $script:S.x = $script:Anchor.X; $script:S.y = $script:Anchor.Y
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
      $script:Anchor = @{ X = [double]$script:S.x; Y = [double]$script:S.y }
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
  if ($script:S.soundFile -and (Test-Path $script:S.soundFile)) { return [string]$script:S.soundFile }
  return $DefaultSound
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
$script:Tester = New-Object Windows.Media.MediaPlayer

# ---------------------------------------------------------------- sessions

$script:Cache = @{}        # file -> last good report, so a half-written file never blinks a session away
$script:AckDone = @{}      # session -> finishedAt you have seen
$script:AckAlert = @{}     # session -> alertSince you have seen
$script:FirstPoll = $true
$script:Sessions = @()
$script:Attention = @()
$script:Mood = 'sleeping'
$script:MoodSince = [Diagnostics.Stopwatch]::StartNew()

function Get-Now { [DateTimeOffset]::Now.ToUnixTimeMilliseconds() }
function Get-Key($s) { if ($s.session) { [string]$s.session } else { [string]$s.cli } }

function Read-Sessions {
  $now = Get-Now
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
  try { Start-Process $url } catch { Write-Log "open failed: $_" }
}

function Set-Seen($s) {
  $key = Get-Key $s
  $script:AckDone[$key] = [double]$s.finishedAt
  $script:AckAlert[$key] = [double]$s.alertSince
}

function New-Line([string]$text, $session, [bool]$isAlert) {
  $border = New-Object Windows.Controls.Border
  $border.CornerRadius = New-Object Windows.CornerRadius(7)
  $border.BorderBrush = $Ink
  $border.BorderThickness = New-Object Windows.Thickness(2)
  $border.Background = $(if ($isAlert) { $AlertPaper } else { $Paper })
  $border.Padding = New-Object Windows.Thickness(8, 3, 8, 3)
  $border.Margin = New-Object Windows.Thickness(0, 0, 0, 3)
  $border.HorizontalAlignment = 'Center'
  $border.Cursor = [Windows.Input.Cursors]::Hand
  $border.ToolTip = 'Open this chat'
  $label = New-Object Windows.Controls.TextBlock
  $label.Text = $text
  $label.Foreground = $Ink
  $label.FontFamily = New-Object Windows.Media.FontFamily('Consolas')
  $label.FontWeight = 'Bold'
  $label.FontSize = [Math]::Max(11, 7 + $script:S.scale * 1.4)
  $border.Child = $label
  $border.Tag = $session
  $border.Add_MouseLeftButtonUp({
    param($sender, $e)
    try {
      $e.Handled = $true
      $s = $sender.Tag
      Set-Seen $s
      Open-Session $s
      Update-State
    } catch { Write-Log "line click: $_" }
  })
  return $border
}

function Update-Lines {
  $key = (@($script:Attention | ForEach-Object { "$($_.text)|$($_.isAlert)" }) -join "`n") + "|$($script:S.scale)"
  if ($key -eq $script:LinesKey) { return }
  $script:LinesKey = $key
  $lines.Children.Clear()
  foreach ($a in $script:Attention) { [void]$lines.Children.Add((New-Line $a.text $a.session $a.isAlert)) }
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
  $sessions = Read-Sessions
  if ($script:FirstPoll) {
    # What was already done or waiting before Mochi started counts as seen: no sound for old news.
    foreach ($s in $sessions) { Set-Seen $s }
    $script:FirstPoll = $false
  }
  $script:Sessions = $sessions

  # Names, with a number where two chats share a project.
  $seen = @{}
  $named = foreach ($s in ($sessions | Sort-Object { [double]$_.startedAt })) {
    $name = [string]$s.project
    if ($seen.ContainsKey($name)) { $seen[$name]++; $name = "$name ($($seen[$name]))" } else { $seen[$name] = 1 }
    [pscustomobject]@{ s = $s; name = $name }
  }

  $attention = New-Object System.Collections.ArrayList
  $ring = $false
  foreach ($n in ($named | Sort-Object { [double]$_.s.alertSince })) {
    $s = $n.s
    if ($s.alert) {
      $what = if ($s.alert -eq 'question') { 'has a question!' } else { 'needs your approval!' }
      [void]$attention.Add([pscustomobject]@{ text = "$($n.name): $what"; session = $s; isAlert = $true })
      if ([double]$s.alertSince -gt (Get-Ack $script:AckAlert (Get-Key $s))) { $ring = $true }
    }
  }
  foreach ($n in ($named | Sort-Object { - [double]$_.s.finishedAt })) {
    if (Test-DonePending $n.s) {
      [void]$attention.Add([pscustomobject]@{ text = "$($n.name): done " + [char]0x2713; session = $n.s; isAlert = $false })
      $ring = $true
    }
  }
  $script:Attention = @($attention | Select-Object -First 6)

  $mood = 'idle'
  if ($sessions.Count -eq 0) { $mood = 'sleeping' }
  elseif (@($sessions | Where-Object { $_.alert }).Count -gt 0) { $mood = 'alert' }
  elseif ($attention.Count -gt 0) { $mood = 'happy' }
  elseif (@($sessions | Where-Object { $_.mood -eq 'working' }).Count -gt 0) { $mood = 'working' }
  elseif (@($sessions | Where-Object { $_.mood -ne 'sleeping' }).Count -eq 0) { $mood = 'sleeping' }
  if ($mood -ne $script:Mood) { $script:Mood = $mood; $script:MoodSince.Restart() }

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

# ---------------------------------------------------------------- input

$pet.Add_MouseLeftButtonDown({
  param($sender, $e)
  try {
    $left = $win.Left; $top = $win.Top
    $win.DragMove()
    if ([Math]::Abs($win.Left - $left) -lt 3 -and [Math]::Abs($win.Top - $top) -lt 3) {
      Invoke-PetClick
    } else {
      Set-Anchor; Save-Settings
    }
  } catch { Write-Log "pet click: $_" }
})
$pet.Add_MouseWheel({
  param($sender, $e)
  try { Set-Scale ($script:S.scale + [Math]::Sign($e.Delta) * 0.5); Save-Settings } catch { Write-Log "wheel: $_" }
})
$grip.Add_DragStarted({ $script:GripStart = $script:S.scale; $script:GripMoved = 0.0 })
$grip.Add_DragDelta({
  param($sender, $e)
  try {
    $script:GripMoved += ($e.HorizontalChange + $e.VerticalChange) / 2
    Set-Scale ($script:GripStart + $script:GripMoved / [Math]::Max(8, $script:W))
  } catch { Write-Log "grip: $_" }
})
$grip.Add_DragCompleted({ Save-Settings })
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
[void]$menu.Items.Add((New-Object Windows.Controls.Separator))
[void](Add-MenuItem $menu 'Sound' { param($item) $script:S.soundOn = $item.IsChecked; Save-Settings; Update-State } $script:S.soundOn)
[void](Add-MenuItem $menu 'Choose sound file...' {
  $dialog = New-Object Microsoft.Win32.OpenFileDialog
  $dialog.Title = 'Sound for Mochi'
  $dialog.Filter = 'Sound files (*.wav;*.mp3;*.wma;*.m4a)|*.wav;*.mp3;*.wma;*.m4a|All files (*.*)|*.*'
  if ($dialog.ShowDialog()) {
    $script:S.soundFile = $dialog.FileName; Save-Settings
    if ($script:IsRinging) { Set-Ringing $false; Update-State }
  }
})
[void](Add-MenuItem $menu 'Use the default chime' {
  $script:S.soundFile = $DefaultSound; Save-Settings
  if ($script:IsRinging) { Set-Ringing $false; Update-State }
})
[void](Add-MenuItem $menu 'Play the sound once' { $script:Tester.Open((New-Object Uri (Get-SoundFile))); $script:Tester.Play() })
[void]$menu.Items.Add((New-Object Windows.Controls.Separator))
[void](Add-MenuItem $menu 'Start when Claude starts' { param($item) $script:S.autoStart = $item.IsChecked; Save-Settings } ($script:S.autoStart -ne $false))
[void](Add-MenuItem $menu 'Start with Windows' { param($item) Set-StartWithWindows $item.IsChecked } (Test-Path $StartupLink))
[void]$menu.Items.Add((New-Object Windows.Controls.Separator))
[void](Add-MenuItem $menu 'Quit Mochi' { Set-Ringing $false; $win.Close() })
$petBox.ContextMenu = $menu

# ---------------------------------------------------------------- run

Set-Scale ([double]$script:S.scale)
$pet.Source = $script:Moods['sleeping'][0].bmp

$animation = New-Object Windows.Threading.DispatcherTimer
$animation.Interval = [TimeSpan]::FromMilliseconds(40)
$animation.Add_Tick({
  try {
    $frames = $script:Moods[$script:Mood]
    $total = 0; foreach ($f in $frames) { $total += $f.ms }
    $t = $script:MoodSince.ElapsedMilliseconds % [Math]::Max(1, $total)
    foreach ($f in $frames) {
      if ($t -lt $f.ms) { if (-not [object]::ReferenceEquals($pet.Source, $f.bmp)) { $pet.Source = $f.bmp }; break }
      $t -= $f.ms
    }
  } catch { Write-Log "animate: $_" }
})
$poll = New-Object Windows.Threading.DispatcherTimer
$poll.Interval = [TimeSpan]::FromSeconds(1)
$poll.Add_Tick({ try { Update-State } catch { Write-Log "poll: $_" } })

try { Update-State } catch { Write-Log "first poll: $_" }
$animation.Start()
$poll.Start()
$win.Add_Closed({ Save-Settings; Write-Log 'quit' })

# For testing: with MOCHI_SNAPSHOT set to a file prefix, save four pictures of the
# window 1.5 s apart (<prefix>-1.png ...) and quit.
if ($env:MOCHI_SNAPSHOT) {
  $script:Shots = 0
  $snap = New-Object Windows.Threading.DispatcherTimer
  $snap.Interval = [TimeSpan]::FromMilliseconds(1500)
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
      Write-Log "snapshot $($script:Shots): mood $($script:Mood), $($script:Attention.Count) lines, ringing $($script:IsRinging)"
      if ($script:Shots -ge 4) { Set-Ringing $false; $win.Close() }
    } catch { Write-Log "snapshot: $_" }
  })
  $snap.Start()
}
[void]$win.ShowDialog()
$script:Mutex.ReleaseMutex()
