# Terminal Jarvis one-line installer. In PowerShell:
#   irm https://raw.githubusercontent.com/TheSunMan123/terminal-jarvis/main/get.ps1 | iex
# Downloads the latest kit from GitHub, then runs its installer (it asks a few questions).
# Run the same line again any time to update.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$repo = "TheSunMan123/terminal-jarvis"
$work = Join-Path $env:TEMP ("terminal-jarvis-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null
try {
  Write-Host "  Downloading Terminal Jarvis..." -ForegroundColor Cyan
  $zip = Join-Path $work "kit.zip"
  Invoke-WebRequest -UseBasicParsing "https://github.com/$repo/archive/refs/heads/main.zip" -OutFile $zip
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [IO.Compression.ZipFile]::ExtractToDirectory($zip, $work)
  $kit = Get-ChildItem $work -Directory | Select-Object -First 1
  & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kit.FullName "install.ps1")
} finally {
  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
