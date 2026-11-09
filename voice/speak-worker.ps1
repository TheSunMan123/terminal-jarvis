# Terminal Jarvis voice - speaks one text file: Fish Audio (your key, your voice ID) or the built-in Windows voice.
param([string]$SayFile)
$ErrorActionPreference = "Stop"
$Dir = Join-Path $env:LOCALAPPDATA "TerminalJarvis"
$text = [IO.File]::ReadAllText($SayFile, [Text.Encoding]::UTF8); Remove-Item $SayFile -Force -ErrorAction SilentlyContinue
$state = Get-Content (Join-Path $Dir "state.json") -Raw | ConvertFrom-Json
$log = Join-Path $Dir "voice.log"
function Log($m) { Add-Content -Path $log -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) }

# Playback goes through Windows Media Foundation (the modern WASAPI audio path Windows itself uses).
# The older winmm path (SoundPlayer, and SAPI speaking directly) plays pure silence on some laptops
# (Intel Smart Sound), so it's only the fallback.
function Play-File($path) {
  try {
    Add-Type -AssemblyName PresentationCore
    $p = New-Object System.Windows.Media.MediaPlayer
    $p.Volume = 1.0
    $p.Open([Uri]$path)
    $t0 = Get-Date
    while (-not $p.NaturalDuration.HasTimeSpan) {
      if (((Get-Date) - $t0).TotalSeconds -gt 5) { throw "media player could not open the audio" }
      Start-Sleep -Milliseconds 50
    }
    $len = $p.NaturalDuration.TimeSpan.TotalMilliseconds
    $p.Play()
    Start-Sleep -Milliseconds ([int]$len + 250)
    $p.Close()
    Log ("played {0:N1}s via Media Foundation" -f ($len / 1000))
  } catch {
    Log "Media Foundation playback failed ($($_.Exception.Message)); using the old player"
    (New-Object System.Media.SoundPlayer $path).PlaySync()
  }
}

function Speak-Windows($t) {
  Add-Type -AssemblyName System.Speech
  $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
  try { $s.SelectVoiceByHints([System.Speech.Synthesis.VoiceGender]::Male) } catch {}
  $s.Rate = 0
  $wav = Join-Path $Dir "reply-windows.wav"
  $s.SetOutputToWaveFile($wav); $s.Speak($t); $s.SetOutputToNull(); $s.Dispose()
  Play-File $wav
}

if ($state.voice -eq "fish") {
  try {
    . (Join-Path $Dir "voice\creds.ps1")
    $slot = if ($state.fish_key_slot) { $state.fish_key_slot } else { "terminal-jarvis-fish" }
    $key = [TJCred]::Read($slot)
    if (-not $key) { throw "no Fish key in Credential Manager slot '$slot'" }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $body = @{ text = $text; reference_id = $state.fish_voice_id; format = "wav" } | ConvertTo-Json -Compress
    $wav = Join-Path $Dir "reply.wav"
    $t0 = Get-Date
    Invoke-WebRequest -Uri "https://api.fish.audio/v1/tts" -Method Post -UseBasicParsing -TimeoutSec 30 `
      -Headers @{ Authorization = "Bearer $key"; model = $(if ($state.fish_model) { $state.fish_model } else { "s1" }) } `
      -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($body)) -OutFile $wav
    Log ("fish ok {0:N1}s, {1} chars" -f ((Get-Date) - $t0).TotalSeconds, $text.Length)
    Play-File $wav
    exit 0
  } catch {
    Log "fish failed, using Windows voice: $($_.Exception.Message)"
  }
}
Speak-Windows $text
