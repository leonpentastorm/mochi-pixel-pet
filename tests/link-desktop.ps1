# Checks the desktop pet's half of the cloud link (desktop/mochi-desktop.ps1):
# loads only the link's functions, then prints the test vector hooks/link.ts
# must match and checks signatures, tampering and the report conversion.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\link-desktop.ps1
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot '..\desktop\mochi-desktop.ps1'
$text = [IO.File]::ReadAllText($script)
$from = $text.IndexOf('$Utf8 = New-Object System.Text.UTF8Encoding')
$to = $text.IndexOf('$script:Remote = @{}')
if ($from -lt 0 -or $to -lt $from) { throw 'link block not found' }
. ([scriptblock]::Create($text.Substring($from, $to - $from)))

$fail = 0
function Check([string]$what, [bool]$ok) { if ($ok) { "ok   $what" } else { "FAIL $what"; $script:fail++ } }

$secret = 'A' * 43
$keys = Get-LinkKeys $secret
$nonce = [byte[]](0..15)
$plain = '{"v":1,"k":"0123456789abcdef","p":"my-repo","m":"working","a":null,"as":0,"s":1000,"f":0,"u":2000}'
$sealed = New-LinkMessage $keys $plain $nonce
"topic  $($keys.topic)"
"sealed $sealed"

$open = Open-LinkMessage $keys $sealed
Check 'opens its own message' ($open.p -eq 'my-repo' -and $open.m -eq 'working')

$chars = $sealed.ToCharArray()
$chars[30] = if ($chars[30] -eq 'A') { 'B' } else { 'A' }
Check 'refuses a tampered message' ($null -eq (Open-LinkMessage $keys (-join $chars)))
Check 'refuses another key' ($null -eq (Open-LinkMessage (Get-LinkKeys ('B' * 43)) $sealed))
Check 'refuses junk' ($null -eq (Open-LinkMessage $keys 'hello world'))

$long = '{"v":1,"k":"0123456789abcdef","p":"' + ('x' * 100) + '","m":"working","a":null,"as":0,"s":0,"f":0,"u":1}'
Check 'opens a multi-block message' ((Open-LinkMessage $keys (New-LinkMessage $keys $long)).p.Length -eq 100)

$evil = [pscustomobject]@{ v = 1; k = '0123456789abcdef'; p = "a`r`nb" + ('y' * 60); m = 'rm -rf'; a = 'open http://x'; as = 0; s = 0; f = 0; u = 1 }
$s = ConvertFrom-LinkReport $evil
Check 'strips control characters and caps the name' ($s.project -notmatch '[\r\n]' -and $s.project.Length -le 40)
Check 'only known moods and alerts' ($s.mood -eq 'idle' -and $null -eq $s.alert)
Check 'never carries an app session id' ($null -eq $s.session -and $s.remote)
Check 'refuses a bad id' ($null -eq (ConvertFrom-LinkReport ([pscustomobject]@{ v = 1; k = '../x' })))

if ($fail) { "$fail failed"; exit 1 } else { 'all passed' }
