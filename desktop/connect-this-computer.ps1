# Connects this computer's Claude sessions to desktop Mochi on another PC.
#
# Run it yourself on the computer whose sessions you want Mochi to show:
#   powershell -NoProfile -ExecutionPolicy Bypass -File connect-this-computer.ps1
# It asks for the link key (on the PC with Mochi: right-click Mochi > Cloud sessions >
# Copy link key) and saves it to %USERPROFILE%\.claude\mochi\link.json. That is all
# it does: it downloads, installs and starts nothing. New Claude sessions here then
# send their status to Mochi through ntfy.sh, encrypted and signed with the key.
# To undo it, run it with -Disconnect, or delete link.json.

param([switch]$Disconnect)
$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:USERPROFILE '.claude\mochi'
$file = Join-Path $dir 'link.json'

if ($Disconnect) {
  if (Test-Path $file) { Remove-Item -LiteralPath $file }
  'Disconnected: this computer no longer reports to Mochi (for sessions started from now on).'
  return
}

# Read like a password, so the key isn't left on screen.
$secure = Read-Host 'Paste the link key (it stays hidden)' -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr).Trim() } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
if ($key -notmatch '^[A-Za-z0-9_-]{43}$') { throw 'That is not a Mochi link key (43 letters, digits, - or _).' }
New-Item -ItemType Directory -Force -Path $dir | Out-Null
[IO.File]::WriteAllText($file, ('{"link":"' + $key + '","send":true}'), (New-Object System.Text.UTF8Encoding($false)))
"Connected. Saved to $file"
'Start a new Claude chat here (or run /reload-plugins) for it to take effect.'
