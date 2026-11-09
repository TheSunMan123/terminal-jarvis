# Terminal Jarvis for Codex - installer (Windows).
# Gives the Codex CLI a Jarvis-style persona, a status bar with the model and your 5-hour / weekly limits,
# and a "Jarvis - Codex" Windows Terminal profile with the Jarvis colours and backdrop.
# Nothing is sent anywhere and no API keys are needed: Codex keeps using your own ChatGPT login.
# Run:  powershell -ExecutionPolicy Bypass -File install.ps1
#   (optional, no prompts:  -User "Alex" -Assistant "Jarvis" -Address "sir" -Voice windows|fish|none
#    -FishVoiceId <id> [-FishModel s1] [-FishKeySlot <existing Credential Manager entry>])
#    -PttKey rightalt|capslock|f8|f9|scrolllock|none
param([string]$User, [string]$Assistant, [string]$Address, [string]$Voice, [string]$FishVoiceId, [string]$FishModel, [string]$FishKeySlot, [string]$PttKey)
$ErrorActionPreference = "Stop"
$Kit = Split-Path -Parent $MyInvocation.MyCommand.Path
$Home_ = $env:USERPROFILE
$CodexDir = Join-Path $Home_ ".codex"
$InstallDir = Join-Path $env:LOCALAPPDATA "TerminalJarvis"
$FragDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\TerminalJarvis"
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Dot = [char]0x00B7
$Mark = "# terminal-jarvis"

function Say($t, $c = "Cyan") { Write-Host $t -ForegroundColor $c }
function Ask($q, $def) {
  $a = Read-Host ("{0}{1}" -f $q, $(if ($def) { " [$def]" } else { "" }))
  if ([string]::IsNullOrWhiteSpace($a)) { return $def } else { return $a.Trim() }
}

Say ""
Say "  TERMINAL JARVIS  //  Codex edition"
Say "  ----------------------------------"
Say ""

# --- checks ---------------------------------------------------------------
$ShimDir = Join-Path $InstallDir "bin"
$codex = Get-Command codex -CommandType Application, ExternalScript -All -ErrorAction SilentlyContinue |
  Where-Object { (Split-Path -Parent $_.Source).TrimEnd('\') -ne $ShimDir.TrimEnd('\') } | Select-Object -First 1
if (-not $codex) { Say "  ! Codex CLI not found on PATH. Install it first (npm i -g @openai/codex), then re-run." "Yellow"; exit 1 }
$wtPkg = Get-ChildItem (Join-Path $env:LOCALAPPDATA "Packages") -Directory -Filter "Microsoft.WindowsTerminal*" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $wtPkg) { Say "  ! Windows Terminal not found. Install it from the Microsoft Store, then re-run." "Yellow"; exit 1 }

# --- questions ------------------------------------------------------------
if (-not $User) { $User = Ask "  Your name" $env:USERNAME }
if (-not $Assistant) { $Assistant = Ask "  Your assistant's name" "Jarvis" }
if (-not $Address) { $Address = Ask "  How should $Assistant address you (sir, ma'am, boss, your name...)" "sir" }
$Assistant = ($Assistant -replace '[^\p{L}\p{N} \-]', '').Trim(); if (-not $Assistant) { $Assistant = "Jarvis" }

New-Item -ItemType Directory -Force $InstallDir | Out-Null
$state = @{ user = $User; assistant = $Assistant; address = $Address; installed = (Get-Date).ToString("s"); codex_exe = $codex.Source }

# --- 1. persona: a marked block in ~/.codex/AGENTS.md (Codex reads it in every session) ---
New-Item -ItemType Directory -Force $CodexDir | Out-Null
$agents = Join-Path $CodexDir "AGENTS.md"
$persona = [IO.File]::ReadAllText((Join-Path $Kit "persona.md"), $Utf8)
$persona = $persona.Replace("{{ASSISTANT}}", $Assistant).Replace("{{USER}}", $User).Replace("{{ADDRESS}}", $Address)
$block = "<!-- terminal-jarvis:start -->`r`n" + $persona.Trim() + "`r`n<!-- terminal-jarvis:end -->"
$existing = ""
if (Test-Path $agents) {
  $existing = [IO.File]::ReadAllText($agents, $Utf8)
  Copy-Item $agents (Join-Path $InstallDir "AGENTS.md.backup") -Force
}
$existing = [regex]::Replace($existing, '(?s)\r?\n?<!-- terminal-jarvis:start -->.*?<!-- terminal-jarvis:end -->\r?\n?', "`r`n").Trim()
$new = if ($existing) { $existing + "`r`n`r`n" + $block + "`r`n" } else { $block + "`r`n" }
[IO.File]::WriteAllText($agents, $new, $Utf8)
Say "  + Persona: $Assistant - applies to EVERY Codex session on this PC (terminal and Codex app), not just the Jarvis window" "Green"

# --- 2. status bar: Codex's built-in items, set under [tui] in ~/.codex/config.toml ---
$cfg = Join-Path $CodexDir "config.toml"
$items = '["model-with-reasoning", "five-hour-limit", "weekly-limit", "context-remaining", "current-dir"]'
$line = "status_line = $items  $Mark"
$lines = @(); if (Test-Path $cfg) { $lines = [IO.File]::ReadAllLines($cfg, $Utf8); Copy-Item $cfg (Join-Path $InstallDir "config.toml.backup") -Force }
$tuiIdx = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq "[tui]") { $tuiIdx = $i; break } }
$out = New-Object System.Collections.Generic.List[string]
if ($tuiIdx -lt 0) {
  # [tui] must be added as a top-level table; append it at the end
  foreach ($l in $lines) { $out.Add($l) }
  $out.Add(""); $out.Add("[tui]"); $out.Add($line)
} else {
  $end = $lines.Count
  for ($i = $tuiIdx + 1; $i -lt $lines.Count; $i++) { if ($lines[$i].TrimStart().StartsWith("[")) { $end = $i; break } }
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($i -gt $tuiIdx -and $i -lt $end -and $lines[$i] -match '^\s*status_line\s*=') {
      if (-not $lines[$i].Contains($Mark)) { $state.previous_status_line = $lines[$i] }
      continue
    }
    $out.Add($lines[$i])
    if ($i -eq $tuiIdx) { $out.Add($line) }
  }
}
[IO.File]::WriteAllLines($cfg, $out, $Utf8)
Say "  + Status bar: model, 5-hour limit, weekly limit, context left, folder" "Green"

# --- 3. backdrop with the assistant's name ----------------------------------
Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile((Join-Path $Kit "assets\backdrop-base.png"))
$bmp = New-Object System.Drawing.Bitmap $img
$img.Dispose()
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = "AntiAlias"; $g.TextRenderingHint = "AntiAliasGridFit"
$letters = $Assistant.ToUpper() -replace ' ', ''
$title = if ($letters.Length -le 8) { (($letters.ToCharArray()) -join ".") + "." } else { $Assistant.ToUpper() }
$fTitle = New-Object System.Drawing.Font("Bahnschrift", 26, [System.Drawing.GraphicsUnit]::Pixel)
$fMono = New-Object System.Drawing.Font("Consolas", 14, [System.Drawing.GraphicsUnit]::Pixel)
$tx = 1600; $ty = 1290   # under the J art
$g.DrawString($title, $fTitle, (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(150, 246, 236, 222))), $tx, ($ty - 36))
$g.DrawString("NEURAL LINK  //  ACTIVE   $Dot   CODEX CHANNEL", $fMono, (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(120, 255, 194, 92))), $tx, $ty)
$g.FillEllipse((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(190, 255, 77, 61))), ($tx - 20), ($ty + 4), 9, 9)
$g.Dispose()
Get-ChildItem $InstallDir -Filter "backdrop-*.png" -ErrorAction SilentlyContinue | Remove-Item -Force
$backdrop = Join-Path $InstallDir ("backdrop-{0:yyyyMMddHHmmss}.png" -f (Get-Date))   # new name each time: Terminal caches images by path
$bmp.Save($backdrop, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Copy-Item (Join-Path $Kit "assets\jarvis.ico") (Join-Path $InstallDir "jarvis.ico") -Force
Say "  + Backdrop: $title" "Green"

# --- 4. Windows Terminal profile + colour scheme (a fragment: your own settings.json is not touched) ---
$cmd = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $InstallDir 'voice\launch.ps1')`""
$profileName = "$Assistant $Dot Codex"
$frag = [ordered]@{
  profiles = @([ordered]@{
    guid = "{7d3a2f4e-5b1c-4c8e-9a6d-1f0e2b3c4d5e}"
    name = $profileName
    commandline = $cmd
    startingDirectory = "%USERPROFILE%"
    icon = (Join-Path $InstallDir "jarvis.ico").Replace("\", "/")
    colorScheme = "Terminal Jarvis"
    backgroundImage = $backdrop.Replace("\", "/")
    backgroundImageStretchMode = "uniformToFill"
    backgroundImageAlignment = "bottomRight"
    backgroundImageOpacity = 1.0
    opacity = 100
    useAcrylic = $false
    cursorShape = "filledBox"
    tabTitle = $Assistant
    suppressApplicationTitle = $true   # keeps the window title = assistant name (push-to-talk only acts in this window)
  })
  # colours taken from the J art: navy ground, warm white text, gold cursor, arc-reactor cyan, armour red
  schemes = @([ordered]@{
    name = "Terminal Jarvis"; background = "#06101B"; foreground = "#EAF1F8"; cursorColor = "#FFC247"; selectionBackground = "#5A2A1E"
    black = "#0B1A2B"; red = "#FF4D3D"; green = "#5FD6A8"; yellow = "#FFC247"; blue = "#4AA8FF"; purple = "#E07BFF"; cyan = "#3FD8FF"; white = "#E6EDF5"
    brightBlack = "#6B8299"; brightRed = "#FF8070"; brightGreen = "#8CF0C8"; brightYellow = "#FFDC8A"; brightBlue = "#8CCBFF"; brightPurple = "#EFB0FF"; brightCyan = "#9BEBFF"; brightWhite = "#FFFFFF"
  })
}
New-Item -ItemType Directory -Force $FragDir | Out-Null
[IO.File]::WriteAllText((Join-Path $FragDir "terminal-jarvis.json"), ($frag | ConvertTo-Json -Depth 6), $Utf8)
Say "  + Windows Terminal profile: '$profileName'" "Green"

# --- 5. desktop shortcut that opens straight into it ---------------------------
$wt = Get-Command wt.exe -ErrorAction SilentlyContinue
if ($wt) {
  $lnk = Join-Path ([Environment]::GetFolderPath("Desktop")) "$Assistant (Codex).lnk"
  $sh = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
  $sh.TargetPath = $wt.Source
  $sh.Arguments = "-p `"$profileName`""
  $sh.IconLocation = (Join-Path $InstallDir "jarvis.ico")
  $sh.Save()
  $state.shortcut = $lnk
  Say "  + Desktop shortcut: $Assistant (Codex)" "Green"
}

# --- 5b. typing "codex" anywhere opens Jarvis: a tiny codex.cmd placed first on your user PATH --------------
if (Test-Path (Join-Path $InstallDir "voice")) { Remove-Item (Join-Path $InstallDir "voice") -Recurse -Force }
Copy-Item (Join-Path $Kit "voice") (Join-Path $InstallDir "voice") -Recurse -Force
New-Item -ItemType Directory -Force $ShimDir | Out-Null
Copy-Item (Join-Path $Kit "voice\codex.cmd") (Join-Path $ShimDir "codex.cmd") -Force
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$parts = @($userPath -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ne $ShimDir.TrimEnd('\')) })
[Environment]::SetEnvironmentVariable("Path", (@($ShimDir) + $parts) -join ';', "User")
Say "  + Type 'codex' in any terminal and $Assistant opens (scripts like 'codex exec' stay plain Codex)" "Green"

# PATH order alone isn't enough: Windows searches the SYSTEM path before the user path, so a Codex installed
# system-wide (or a terminal started before the PATH change) skips the shim. A 'codex' function in the
# PowerShell profiles always wins over anything on PATH, so add one to Windows PowerShell and PowerShell 7.
$ProfBlock = @'
# >>> terminal-jarvis >>>  (typing codex opens Jarvis; removed by Terminal Jarvis uninstall.ps1)
function codex {
  $shim = Join-Path $env:LOCALAPPDATA 'TerminalJarvis\bin\codex.cmd'
  if (-not (Test-Path $shim)) {
    $real = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($real) { & $real.Source @args }; return
  }
  if ($MyInvocation.ExpectingInput) { $input | & $shim @args } else { & $shim @args }
}
# <<< terminal-jarvis <<<
'@
function Get-FileEnc($path) {
  $b = [IO.File]::ReadAllBytes($path)
  if ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { return [Text.Encoding]::Unicode }
  if ($b.Length -ge 2 -and $b[0] -eq 0xFE -and $b[1] -eq 0xFF) { return [Text.Encoding]::BigEndianUnicode }
  if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return (New-Object Text.UTF8Encoding($true)) }
  try { [void](New-Object Text.UTF8Encoding($false, $true)).GetString($b); return $Utf8 } catch { return [Text.Encoding]::Default }
}
$docs = [Environment]::GetFolderPath("MyDocuments")
$profFiles = @((Join-Path $docs "WindowsPowerShell\profile.ps1"), (Join-Path $docs "PowerShell\profile.ps1"))
foreach ($pf in $profFiles) {
  try {
    New-Item -ItemType Directory -Force (Split-Path -Parent $pf) | Out-Null
    if (Test-Path $pf) {
      $enc = Get-FileEnc $pf
      $t = [IO.File]::ReadAllText($pf, $enc)
      $t = [regex]::Replace($t, '(?s)\r?\n?# >>> terminal-jarvis >>>.*?# <<< terminal-jarvis <<<\r?\n?', "`r`n").TrimEnd()
      if ($t) { $t += "`r`n`r`n" }
      [IO.File]::WriteAllText($pf, $t + $ProfBlock + "`r`n", $enc)
    } else {
      [IO.File]::WriteAllText($pf, $ProfBlock + "`r`n", $Utf8)
    }
  } catch { Say "  (could not add the codex shortcut to $pf : $($_.Exception.Message))" "Yellow" }
}
# Profiles only load when scripts are allowed. Windows' out-of-the-box "Restricted" policy blocks them, so switch
# just this user to RemoteSigned (the usual setting: your own local scripts run, downloaded ones must be signed).
$pol = Get-ExecutionPolicy
if ($pol -eq "Restricted" -or $pol -eq "Undefined") {
  try {
    Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force -ErrorAction Stop
    Say "  + PowerShell script policy for your user: $pol -> RemoteSigned (so your PowerShell profile loads)" "Green"
  } catch { Say "  ! PowerShell profiles are blocked by policy ($pol). Typing codex in PowerShell may open plain Codex; use the desktop shortcut." "Yellow" }
} elseif ($pol -eq "AllSigned") {
  Say "  ! PowerShell policy is AllSigned, so the codex shortcut in your profile won't load. Use the desktop shortcut." "Yellow"
}
Say "  + PowerShell: 'codex' goes through $Assistant even if another Codex comes first on your PATH" "Green"

# Report what a fresh Command Prompt would run (cmd has no profile, so only PATH order counts there).
$exts = @($env:PATHEXT -split ';' | Where-Object { $_ })
$firstHit = $null
foreach ($d in @(([Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")) -split ';' | Where-Object { $_ })) {
  foreach ($x in $exts) {
    $p = Join-Path ([Environment]::ExpandEnvironmentVariables($d)) ("codex" + $x)
    if (Test-Path -LiteralPath $p -PathType Leaf) { $firstHit = $p; break }
  }
  if ($firstHit) { break }
}
if ($firstHit -and ((Split-Path -Parent $firstHit).TrimEnd('\') -ne $ShimDir.TrimEnd('\'))) {
  Say "  ! Note: Command Prompt (cmd) will still run plain Codex ($firstHit comes first on the system PATH)." "DarkGray"
  Say "    PowerShell and the desktop shortcut open $Assistant; that's where to use it." "DarkGray"
}

# --- 6. voice: speaks the opening of each Codex reply (Codex "Stop" hook in ~/.codex/hooks.json) ---------
$JarvisVoiceId = "05b36da8574341d0803391491850db20"   # public "Jarvis" voice on fish.audio
. (Join-Path $Kit "voice\creds.ps1")
if (-not $Voice) {
  Say ""
  Say "  VOICE: $Assistant reads the start of every reply aloud."
  Say "    For the real Jarvis voice, paste a Fish Audio API key (free account at fish.audio -> API Keys)."
  Say "    Press Enter to skip and use the free built-in Windows voice instead. Type 'none' for silent." "DarkGray"
  $sec = Read-Host "  Fish Audio API key (hidden as you paste)" -AsSecureString
  $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
  if ($plain) { $plain = $plain.Trim() }
  if ($plain -eq "none") { $Voice = "none" }
  elseif ($plain) {
    [void][TJCred]::Write("terminal-jarvis-fish", "fish-audio", $plain)
    $FishKeySlot = "terminal-jarvis-fish"; $Voice = "fish"
    Say "    Key saved in Windows Credential Manager (never written to a file)." "DarkGray"
  } else { $Voice = "windows" }
  $plain = $null
}
$Voice = $Voice.ToLower(); if ($Voice -notin @("none", "windows", "fish")) { $Voice = "windows" }
if ($Voice -eq "fish" -and -not $FishKeySlot) {
  $existingKey = [TJCred]::Read("terminal-jarvis-fish")
  if ($existingKey) { $FishKeySlot = "terminal-jarvis-fish" } else {
    $sec = Read-Host "  Fish Audio API key (hidden as you paste)" -AsSecureString
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    if ($plain) { [void][TJCred]::Write("terminal-jarvis-fish", "fish-audio", $plain.Trim()); $FishKeySlot = "terminal-jarvis-fish" } else { $Voice = "windows" }
    $plain = $null
  }
  $existingKey = $null
}
$state.voice = $Voice
if ($Voice -eq "fish") {
  $state.fish_voice_id = $(if ($FishVoiceId) { $FishVoiceId } else { $JarvisVoiceId })
  $state.fish_model = $(if ($FishModel) { $FishModel } else { "s2.1-pro-free" })
  $state.fish_key_slot = $FishKeySlot
}
$hooksFile = Join-Path $CodexDir "hooks.json"
$hookCmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $InstallDir "voice\speak.ps1") + '"'
$hooks = $null
if (Test-Path $hooksFile) {
  Copy-Item $hooksFile (Join-Path $InstallDir "hooks.json.backup") -Force
  try { $hooks = Get-Content $hooksFile -Raw | ConvertFrom-Json } catch { $hooks = $null }
}
if (-not $hooks) { $hooks = New-Object PSObject }
if (-not $hooks.PSObject.Properties["hooks"]) { $hooks | Add-Member -NotePropertyName hooks -NotePropertyValue (New-Object PSObject) }
$stop = @()
if ($hooks.hooks.PSObject.Properties["Stop"]) {
  $stop = @($hooks.hooks.Stop | Where-Object { -not ((@($_.hooks) | ForEach-Object { $_.command }) -join " ").Contains("TerminalJarvis") })
}
if ($Voice -ne "none") { $stop += [pscustomobject]@{ hooks = @([pscustomobject]@{ type = "command"; command = $hookCmd; timeout = 15 }) } }
if ($hooks.hooks.PSObject.Properties["Stop"]) { $hooks.hooks.Stop = $stop } else { $hooks.hooks | Add-Member -NotePropertyName Stop -NotePropertyValue $stop }
[IO.File]::WriteAllText($hooksFile, (ConvertTo-Json $hooks -Depth 10), $Utf8)
Say "  + Voice: $Voice" "Green"

# --- 7. push-to-talk: hold a key in the Jarvis window -> Windows voice typing -> release sends it -------------
if (-not $PttKey) {
  Say ""
  Say "  Push-to-talk: hold a key in the $Assistant window and speak; let go and it's sent to Codex."
  Say "    rightalt (default) / capslock / f8 / f9 / scrolllock / none"
  $PttKey = Ask "  Talk key" "rightalt"
}
$state.ptt_key = $PttKey.ToLower()
$state.ptt_auto_send = $true
# the HUD helper (status readout + push-to-talk) is started by the Jarvis profile itself and quits when its
# windows close; nothing is added to Windows startup. Restart a running one so it picks up new settings.
$old = Join-Path $InstallDir "hud.pid"
if (Test-Path $old) { Stop-Process -Id ([int](Get-Content $old)) -Force -ErrorAction SilentlyContinue }
if ($state.ptt_key -ne "none") {
  Say "  + Push-to-talk: hold $($state.ptt_key.ToUpper()) in the $Assistant window (uses Windows voice typing; first time, Windows may ask to turn it on)" "Green"
}
Say "  + Status readout: $Assistant, model and your usage-limit bars, pinned beside the tabs" "Green"

[IO.File]::WriteAllText((Join-Path $InstallDir "state.json"), ($state | ConvertTo-Json), $Utf8)
Say ""
Say "  $Assistant is online, $Address. Close ALL Windows Terminal windows once, then just type  codex  -" "White"
Say "  or use the '$Assistant (Codex)' desktop shortcut. (The Codex desktop app gets the persona only.)" "White"
if ($Voice -ne "none") {
  Say "  ONE-TIME STEP for the voice: in Codex type  /hooks  and trust the Terminal Jarvis 'Stop' hook." "Yellow"
  Say "  (Codex never runs a new hook until you approve it - that's a Codex security rule.)" "DarkGray"
}
Say "  New profile not in the Terminal dropdown yet? Close ALL Windows Terminal windows once and reopen." "DarkGray"
Say "  (Restart any open Codex sessions to pick up the persona and status bar.  Undo everything: uninstall.ps1)" "DarkGray"
Say ""
