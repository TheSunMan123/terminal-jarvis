# Terminal Jarvis checkup (Windows). In PowerShell:
#   irm https://raw.githubusercontent.com/TheSunMan123/terminal-jarvis/main/doctor.ps1 | iex
# Shows the settings, tests the microphone (records 4 seconds and shows what it heard) and the voice,
# and updates the speech engine script to the latest version. Changes nothing else.
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$Dir = Join-Path $env:LOCALAPPDATA "TerminalJarvis"
function Say($t, $c = "Cyan") { Write-Host $t -ForegroundColor $c }
Say ""; Say "  TERMINAL JARVIS CHECKUP"; Say "  -----------------------"
if (-not (Test-Path (Join-Path $Dir "state.json"))) { Say "  ! Not installed (no state.json). Run the installer first." "Yellow"; return }
$state = Get-Content (Join-Path $Dir "state.json") -Raw | ConvertFrom-Json
Say ("  Voice: {0}   Push-to-talk: {1} via {2}   Model: {3}" -f $state.voice, $state.ptt_key, $state.ptt_engine, $state.stt_model) "White"
Say ("  uv: {0}  (exists: {1})" -f $state.uv_exe, [bool]($state.uv_exe -and (Test-Path $state.uv_exe))) "White"

# Windows microphone privacy switches
$base = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone"
$all = (Get-ItemProperty $base -Name Value -ErrorAction SilentlyContinue).Value
$desk = (Get-ItemProperty (Join-Path $base "NonPackaged") -Name Value -ErrorAction SilentlyContinue).Value
Say ("  Microphone access: {0}   Desktop apps may use the mic: {1}" -f $(if ($all) { $all } else { "default" }), $(if ($desk) { $desk } else { "default" })) "White"
if ($all -eq "Deny" -or $desk -eq "Deny") {
  Say "  ! Windows is blocking the microphone. Settings > Privacy & security > Microphone: turn on" "Yellow"
  Say "    'Microphone access' AND 'Let desktop apps access your microphone'." "Yellow"
}

# refresh the speech engine + voice player to the latest fixes, then test the mic
$ears = Join-Path $Dir "voice\ears.py"
foreach ($f in "ears.py", "speak-worker.ps1", "launch.ps1", "jarvis-hud.ps1") {
  $dst = Join-Path $Dir "voice\$f"
  try {
    Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/TheSunMan123/terminal-jarvis/main/voice/$f" -OutFile "$dst.new"
    Move-Item "$dst.new" $dst -Force
  } catch { Say "  (could not refresh $f : $($_.Exception.Message))" "DarkGray" }
}
if ($state.uv_exe -and (Test-Path $state.uv_exe)) {
  Say ""
  $env:UV_SYSTEM_CERTS = "1"
  $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  & $state.uv_exe run --quiet --script $ears --test --state (Join-Path $Dir "state.json") 2>&1 | ForEach-Object { $l = "$_"; if ($l -notmatch 'UV_') { Write-Host $l } }
  $ErrorActionPreference = $eap
} else { Say "  ! The speech engine isn't set up (no uv). Re-run the installer." "Yellow" }

# voice test: speak one line, in the foreground, then show the voice log
Say ""; Say "  Voice test: you should hear 'Voice check, all systems online.' now..."
$say = Join-Path $Dir "say-doctor.txt"
[IO.File]::WriteAllText($say, "Voice check, all systems online.", (New-Object System.Text.UTF8Encoding($false)))
$eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dir "voice\speak-worker.ps1") $say 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
$ErrorActionPreference = $eap
$out = $null
try { Add-Type -AssemblyName System.Speech; $out = (New-Object System.Speech.Synthesis.SpeechSynthesizer).GetInstalledVoices().Count } catch { }
Say ("  Windows voices installed: {0}" -f $out) "White"
Say "  Didn't hear it? If the log below says 'fish ok', the voice was made and played: check the volume," "DarkGray"
Say "  that the laptop isn't muted, and that the 'Speakers' line above is the device you're listening on" "DarkGray"
Say "  (Bluetooth headphones, a monitor or a dock can quietly take over the sound)." "DarkGray"

# restart the Jarvis helper so the next Jarvis window uses the refreshed speech engine
$hp = Join-Path $Dir "hud.pid"
if (Test-Path $hp) { Stop-Process -Id ([int](Get-Content $hp)) -Force -ErrorAction SilentlyContinue }
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine -like "*TerminalJarvis*ears.py*--serve*" } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Say ""; Say "  Recent logs:" "White"
foreach ($f in "voice.log", "ears.log") {
  $p = Join-Path $Dir $f
  if (Test-Path $p) { Say "  [$f]" "DarkGray"; Get-Content $p -Tail 6 | ForEach-Object { Say "    $_" "DarkGray" } }
}
$stamp = Join-Path $Dir "last-greeting.txt"
if (Test-Path $stamp) { Say ("  Last greeting: {0}  (plays each time Jarvis opens; skipped if another window opened in the last minute)" -f (Get-Item $stamp).LastWriteTime) "DarkGray" }
Say ""; Say "  Done. Close every Jarvis window and open a new one to use any fixes." "White"
Say "  Still stuck? Send the lines above to whoever is helping you." "White"; Say ""
