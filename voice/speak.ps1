# Terminal Jarvis voice - Codex "Stop" hook. Codex pipes the finished turn as JSON on stdin; this picks the
# reply's opening paragraph and hands it to speak-worker.ps1 in the background, so Codex never waits on audio.
$ErrorActionPreference = "SilentlyContinue"
$Dir = Join-Path $env:LOCALAPPDATA "TerminalJarvis"
try { $state = Get-Content (Join-Path $Dir "state.json") -Raw | ConvertFrom-Json } catch { exit 0 }
if (-not $state.voice -or $state.voice -eq "none" -or $state.voice_muted) { exit 0 }
$raw = [Console]::In.ReadToEnd()
try { $j = $raw | ConvertFrom-Json } catch { exit 0 }
if ($j.stop_hook_active) { exit 0 }
$msg = [string]$j.last_assistant_message
if ([string]::IsNullOrWhiteSpace($msg)) { exit 0 }

# opening paragraph that is prose (skip code blocks, tables, headings), markdown stripped
$text = ""
foreach ($p in [regex]::Split($msg.Trim(), '\r?\n\s*\r?\n')) {
  $t = $p.Trim()
  if (-not $t -or $t.StartsWith('```') -or $t.StartsWith('|') -or $t.StartsWith('#')) { continue }
  $text = $t; break
}
if (-not $text) { exit 0 }
$text = [regex]::Replace($text, '\[([^\]]+)\]\([^)]+\)', '$1')          # links -> their text
$text = [regex]::Replace($text, '`([^`]+)`', '$1')                       # inline code
$text = $text -replace '[*_#>]', '' -replace '\s+', ' '
if ($text.Length -gt 420) {
  $cut = $text.Substring(0, 420); $end = [Math]::Max($cut.LastIndexOf('. '), [Math]::Max($cut.LastIndexOf('? '), $cut.LastIndexOf('! ')))
  $text = if ($end -gt 120) { $cut.Substring(0, $end + 1) } else { $cut }
}

# a new reply interrupts the previous one
$pidFile = Join-Path $Dir "speaking.pid"
if (Test-Path $pidFile) { $old = Get-Content $pidFile; if ($old) { Stop-Process -Id ([int]$old) -Force -ErrorAction SilentlyContinue } }
$sayFile = Join-Path $Dir ("say-{0}.txt" -f [guid]::NewGuid().ToString("N").Substring(0, 8))
[IO.File]::WriteAllText($sayFile, $text, (New-Object System.Text.UTF8Encoding($false)))
$p = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$(Join-Path $Dir 'voice\speak-worker.ps1')`"", "`"$sayFile`"")
Set-Content -Path $pidFile -Value $p.Id
exit 0
