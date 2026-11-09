# Terminal Jarvis: runs whenever you type "codex" (via the small codex.cmd placed first on your PATH).
# - typed in an ordinary Windows Terminal tab -> opens the Jarvis tab (theme, backdrop, HUD, greeting, voice)
#   in the same window and folder, carrying your arguments along;
# - already inside the Jarvis tab, or in another terminal -> starts Jarvis right here;
# - scripted use (codex exec, login, mcp, piped input/output, Codex's own child processes) -> plain Codex, untouched.
$Dir = Join-Path $env:LOCALAPPDATA "TerminalJarvis"
$JarvisGuid = "{7d3a2f4e-5b1c-4c8e-9a6d-1f0e2b3c4d5e}"
$state = $null
try { $state = Get-Content (Join-Path $Dir "state.json") -Raw | ConvertFrom-Json } catch { }

function Find-RealCodex {
  if ($state -and $state.codex_exe -and (Test-Path $state.codex_exe)) { return $state.codex_exe }
  $bin = (Join-Path $Dir "bin").TrimEnd('\')
  foreach ($c in (Get-Command codex -CommandType Application, ExternalScript -All -ErrorAction SilentlyContinue)) {
    if ((Split-Path -Parent $c.Source).TrimEnd('\') -ne $bin) { return $c.Source }
  }
  return $null
}
$real = Find-RealCodex
if (-not $real) { Write-Host "  Codex CLI not found. Install it, then try again." -ForegroundColor Yellow; exit 1 }

$plain = @("exec", "e", "review", "login", "logout", "mcp", "mcp-server", "app-server", "app", "completion", "sandbox",
  "debug", "apply", "a", "cloud", "features", "help", "doctor", "update", "proto", "--version", "-V", "--help", "-h")
$scripted = [Console]::IsInputRedirected -or [Console]::IsOutputRedirected
if ($env:TERMINAL_JARVIS -or -not $state -or $scripted -or ($args.Count -gt 0 -and $plain -contains [string]$args[0])) {
  & $real @args
  exit $LASTEXITCODE
}

$launch = Join-Path $Dir "voice\launch.ps1"
$wt = Get-Command wt.exe -ErrorAction SilentlyContinue
if ($env:WT_SESSION -and $wt -and $env:WT_PROFILE_ID -ne $JarvisGuid) {
  $here = (Get-Location).ProviderPath
  if ($here.EndsWith('\')) { $here += '.' }          # "C:\" would escape the closing quote
  $profileName = "{0} {1} Codex" -f $state.assistant, [char]0x00B7
  $wtArgs = @("-w", "0", "new-tab", "-p", "`"$profileName`"", "-d", "`"$here`"",
    "powershell.exe", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$launch`"")
  foreach ($a in $args) { $wtArgs += ('"' + (([string]$a) -replace '"', '\"' -replace ';', '\;') + '"') }
  Start-Process $wt.Source -ArgumentList $wtArgs
  Write-Host ("  " + [char]0x25C6 + " " + $state.assistant + " is opening in a new tab.") -ForegroundColor Cyan
  exit 0
}

& $launch @args
exit $LASTEXITCODE
