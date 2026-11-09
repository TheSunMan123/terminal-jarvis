# Terminal Jarvis: what the "Jarvis - Codex" Terminal profile runs. Starts the HUD helper (status readout +
# push-to-talk; it quits by itself after the Jarvis windows close), greets you, then runs Codex in this tab.
$Dir = Join-Path $env:LOCALAPPDATA "TerminalJarvis"
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @("-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", "`"$(Join-Path $Dir 'voice\jarvis-hud.ps1')`"")

# Welcome back: spoken + a short banner, on the first launch only (not again for 30 minutes)
try {
  $state = Get-Content (Join-Path $Dir "state.json") -Raw | ConvertFrom-Json
  $stamp = Join-Path $Dir "last-greeting.txt"
  $due = -not (Test-Path $stamp) -or (((Get-Date) - (Get-Item $stamp).LastWriteTime).TotalMinutes -ge 30)
  if ($due) {
    Set-Content -Path $stamp -Value (Get-Date).ToString("s")
    $hr = (Get-Date).Hour
    $part = if ($hr -ge 5 -and $hr -lt 12) { "morning" } elseif ($hr -ge 12 -and $hr -lt 17) { "afternoon" } else { "evening" }
    $addr = if ($state.address) { $state.address } else { "sir" }
    $line = "Good $part, $addr. Welcome back. All systems are online."
    $name = (([string]$state.assistant).ToUpper().Replace(" ", "").ToCharArray() -join ".") + "."
    Write-Host ""
    Write-Host ("   " + [char]0x25C6 + " " + $name) -ForegroundColor Cyan -NoNewline
    Write-Host ("   " + [char]0x00B7 + "   NEURAL LINK ACTIVE   " + [char]0x00B7 + "   CODEX CHANNEL") -ForegroundColor DarkYellow
    Write-Host ("   " + $line) -ForegroundColor White
    Write-Host ""
    if ($state.voice -and $state.voice -ne "none" -and -not $state.voice_muted) {
      $say = Join-Path $Dir ("say-{0}.txt" -f [guid]::NewGuid().ToString("N").Substring(0, 8))
      [IO.File]::WriteAllText($say, $line, (New-Object System.Text.UTF8Encoding($false)))
      Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$(Join-Path $Dir 'voice\speak-worker.ps1')`"", "`"$say`"")
    }
    Start-Sleep -Milliseconds 1600   # let the banner be seen before Codex takes the screen
  }
} catch { }

$env:TERMINAL_JARVIS = "1"   # anything Codex starts that calls "codex" again gets plain Codex
$real = $null
try { $real = (Get-Content (Join-Path $Dir "state.json") -Raw | ConvertFrom-Json).codex_exe } catch { }
if (-not $real -or -not (Test-Path $real)) { $real = "codex" }
& $real @args
