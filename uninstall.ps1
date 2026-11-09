# Terminal Jarvis for Codex - uninstaller. Removes the persona block, the status bar line, the Terminal profile,
# the shortcut and the installed files. Anything else in your Codex files is left as it was.
# Run:  powershell -ExecutionPolicy Bypass -File uninstall.ps1
$ErrorActionPreference = "Stop"
$CodexDir = Join-Path $env:USERPROFILE ".codex"
$InstallDir = Join-Path $env:LOCALAPPDATA "TerminalJarvis"
$FragDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\TerminalJarvis"
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Mark = "# terminal-jarvis"
$state = @{}
if (Test-Path (Join-Path $InstallDir "state.json")) { $state = Get-Content (Join-Path $InstallDir "state.json") -Raw | ConvertFrom-Json }

$agents = Join-Path $CodexDir "AGENTS.md"
if (Test-Path $agents) {
  $t = [IO.File]::ReadAllText($agents, $Utf8)
  $t = [regex]::Replace($t, '(?s)\r?\n?<!-- terminal-jarvis:start -->.*?<!-- terminal-jarvis:end -->\r?\n?', "`r`n").Trim()
  if ($t) { [IO.File]::WriteAllText($agents, $t + "`r`n", $Utf8) } else { Remove-Item $agents -Force }
}
$cfg = Join-Path $CodexDir "config.toml"
if (Test-Path $cfg) {
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($l in [IO.File]::ReadAllLines($cfg, $Utf8)) {
    if ($l.Contains($Mark)) { if ($state.previous_status_line) { $out.Add($state.previous_status_line) }; continue }
    $out.Add($l)
  }
  [IO.File]::WriteAllLines($cfg, $out, $Utf8)
}
$hooksFile = Join-Path $CodexDir "hooks.json"
if (Test-Path $hooksFile) {
  try {
    $h = Get-Content $hooksFile -Raw | ConvertFrom-Json
    if ($h.hooks -and $h.hooks.PSObject.Properties["Stop"]) {
      $h.hooks.Stop = @($h.hooks.Stop | Where-Object { -not ((@($_.hooks) | ForEach-Object { $_.command }) -join " ").Contains("TerminalJarvis") })
      [IO.File]::WriteAllText($hooksFile, (ConvertTo-Json $h -Depth 10), $Utf8)
    }
  } catch { Write-Host "  (could not edit hooks.json - remove the TerminalJarvis Stop hook by hand)" -ForegroundColor Yellow }
}
$pttPid = Join-Path $InstallDir "hud.pid"
if (Test-Path $pttPid) { Stop-Process -Id ([int](Get-Content $pttPid)) -Force -ErrorAction SilentlyContinue }

$shimDir = (Join-Path $InstallDir "bin").TrimEnd('\')
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath) {
  $kept = @($userPath -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ne $shimDir) })
  [Environment]::SetEnvironmentVariable("Path", ($kept -join ';'), "User")
}

$docs = [Environment]::GetFolderPath("MyDocuments")
foreach ($pf in @((Join-Path $docs "WindowsPowerShell\profile.ps1"), (Join-Path $docs "PowerShell\profile.ps1"))) {
  if (-not (Test-Path $pf)) { continue }
  try {
    $b = [IO.File]::ReadAllBytes($pf)
    $enc = if ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { [Text.Encoding]::Unicode }
      elseif ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { New-Object Text.UTF8Encoding($true) }
      else { try { [void](New-Object Text.UTF8Encoding($false, $true)).GetString($b); $Utf8 } catch { [Text.Encoding]::Default } }
    $t = [IO.File]::ReadAllText($pf, $enc)
    if ($t -notmatch '# >>> terminal-jarvis >>>') { continue }
    $t = [regex]::Replace($t, '(?s)\r?\n?# >>> terminal-jarvis >>>.*?# <<< terminal-jarvis <<<\r?\n?', "`r`n").Trim()
    if ($t) { [IO.File]::WriteAllText($pf, $t + "`r`n", $enc) } else { Remove-Item $pf -Force }
  } catch { Write-Host "  (could not edit $pf - remove the terminal-jarvis block by hand)" -ForegroundColor Yellow }
}

if ($state.fish_key_slot -eq "terminal-jarvis-fish") { cmdkey /delete:terminal-jarvis-fish | Out-Null }
if (Test-Path $FragDir) { Remove-Item $FragDir -Recurse -Force }
if ($state.shortcut -and (Test-Path $state.shortcut)) { Remove-Item $state.shortcut -Force }
if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
Write-Host "  Terminal Jarvis removed. Codex is back to normal." -ForegroundColor Green
