# Terminal Jarvis — Codex edition

Turns the **Codex CLI** on **Windows** and **macOS** into Jarvis:

- **Persona** — every Codex session talks like a composed, quick-witted AI chief of staff, using your name.
- **Status bar** — the model, your **5-hour** and **weekly** usage limits, context left and the current folder, always visible at the bottom.
- **The look** — Jarvis colours and a HUD backdrop carrying your assistant's name (Windows Terminal profile on Windows; iTerm2 profile on Mac).
- **Voice** — reads the opening of every reply aloud (the Fish Audio Jarvis voice with your free key, or the built-in voice), plus a spoken greeting.
- **Push-to-talk** — hold a key, speak, let go: your words are typed into Codex and sent. Speech is recognised **on your own computer** (a local Whisper model); audio never leaves it.

Nothing uploaded, no accounts: Codex keeps using **your own** ChatGPT login and plan.

**On a Mac?** Jump to [macOS](#macos).

## Requirements
- Windows 10/11 with **Windows Terminal** (Microsoft Store)
- **Codex CLI** signed in (`npm i -g @openai/codex`, then run `codex` once and log in). Codex 0.101 or newer.

## Quick install (one line)
Open **PowerShell** and paste:
```
irm https://raw.githubusercontent.com/TheSunMan123/terminal-jarvis/main/get.ps1 | iex
```
It downloads the kit and runs the installer (steps 3-8 below). Paste the same line again any time to **update**.

> **Run it in a plain PowerShell window, not inside Codex.** Don't ask Codex to install or update this kit. Codex runs commands in a sandbox with no internet and no write access to its own settings folder, so it fails with errors like *"cloned into the permitted temporary folder but can't connect to GitHub"*. Close Codex, open **Windows PowerShell** from the Start menu (admin not needed), and paste the line there.
>
> - *"Running scripts is disabled on this system"*: run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`, answer **Y**, then paste the line again.
> - *Connection / SSL errors in PowerShell itself*: your network or antivirus is blocking GitHub. Download the ZIP instead (green **Code** button → **Download ZIP**) and follow "Install (from a download)" below.

## Install (from a download)
1. Unzip this folder anywhere.
2. **Double-click `Install Jarvis.cmd`.** (Or in a terminal: `powershell -ExecutionPolicy Bypass -File .\install.ps1`.)
3. Answer: your name, your assistant's name (default **Jarvis**), how it should address you (default **sir**).
4. **Voice:** paste a **Fish Audio API key** for the real Jarvis voice (free account at fish.audio → API Keys; the key is stored in Windows Credential Manager, never in a file). Press **Enter** to skip and use the free Windows voice, or type `none` for silent.
5. Pick a push-to-talk key (default **Right Alt**). The installer then downloads the speech engine and model (~250 MB the first time, a minute or two).
6. **Close every Windows Terminal window once** (Terminal only loads new profiles and PATH changes when it starts).
7. Now just **type `codex`** in any terminal: an ordinary Terminal tab hands off to a new **Jarvis tab** in the same folder (theme, backdrop, status chip, greeting, voice). The desktop shortcut **"Jarvis (Codex)"** does the same.
8. **Voice, one-time:** in Codex type `/hooks` and **trust** the Terminal Jarvis `Stop` hook. Codex never runs a new hook until you approve it.

**Push-to-talk:** in the Jarvis window, hold your talk key and speak (the chip shows **● LISTENING**, then **TRANSCRIBING**); let go and your words are typed into Codex and sent. Speech is recognised on your PC by a local Whisper model (`base.en`, ~150 MB, downloaded once by the installer through [uv](https://docs.astral.sh/uv/), which brings its own Python, so nothing touches your system Python). The talk key only works while the Jarvis window is in front. If the speech engine can't be set up, the installer falls back to Windows voice typing (Win+H). Options: `-SttModel small.en` (more accurate, slower) or `tiny.en` (fastest); `-PttEngine windows` to use Windows voice typing.
**Status chip:** pinned beside the tabs: the model and your usage-limit bars (5-hour + weekly on paid plans, monthly on free), read from Codex's own session records. Shown only in the Jarvis window.
**Scripts are untouched:** `codex exec`, `codex login`, `codex mcp`, piped input/output and Codex's own child processes go straight to plain Codex. The **Codex desktop app** gets the persona only (it has no terminal to theme).

From then on, Jarvis reads the first paragraph of every reply aloud. Mute: set `"voice_muted": true` in `%LOCALAPPDATA%\TerminalJarvis\state.json` (or re-run the installer and type `none` at the key prompt).

## What it changes (and how to undo)
| What | Where | Note |
|---|---|---|
| Persona block | `%USERPROFILE%\.codex\AGENTS.md` | Between `terminal-jarvis` markers; anything else in the file is kept. Applies to **every** Codex session (terminal and Codex app). |
| Status bar | `%USERPROFILE%\.codex\config.toml` → `[tui] status_line` | One line, tagged `# terminal-jarvis`. A backup of the original file is saved. |
| Terminal profile + colours | `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\TerminalJarvis` | Your own Terminal settings are not edited. |
| Voice hook | `%USERPROFILE%\.codex\hooks.json` → `Stop` | Speaks the opening of each reply. Other hooks in the file are kept. |
| HUD helper (readout + push-to-talk) | `%LOCALAPPDATA%\TerminalJarvis\voice\jarvis-hud.ps1` | Started by the Jarvis profile, quits when its window closes. Listens only for the talk key, only in the Jarvis window. |
| Fish key | Windows Credential Manager → `terminal-jarvis-fish` | Only if you chose Fish. Never written to a file. |
| `codex` launcher | `%LOCALAPPDATA%\TerminalJarvis\bin\codex.cmd`, added to the front of your **user** PATH | Routes interactive `codex` into the Jarvis tab; everything else passes through. |
| `codex` in PowerShell | `Documents\WindowsPowerShell\profile.ps1` and `Documents\PowerShell\profile.ps1` | A small `codex` function between `terminal-jarvis` markers, so PowerShell opens Jarvis even when another Codex sits earlier on the **system** PATH. The rest of your profile is kept. If your script policy was Windows' default *Restricted*, it is set to **RemoteSigned** for your user only (so profiles can load); uninstall leaves that setting alone. Command Prompt (cmd) has no profile, so there `codex` follows PATH order: use PowerShell or the desktop shortcut. |
| Backdrop, icon, voice scripts, speech model | `%LOCALAPPDATA%\TerminalJarvis` (incl. `models\`, and a private `uv\` if you didn't already have uv) | |

**Uninstall:** `powershell -ExecutionPolicy Bypass -File .\uninstall.ps1` — removes all of the above and puts back any status bar you had before.

## Tips
- Make it your default: Windows Terminal → Settings → Startup → Default profile → **Jarvis · Codex**.
- Change your name or the assistant's name any time: just run `install.ps1` again.
- The 5-hour / weekly limit readouts come from your ChatGPT plan; on plans without those windows Codex may leave them blank.

## macOS
**Needs:** macOS 12 or newer, the **Codex CLI** signed in (`brew install codex` or `npm i -g @openai/codex`, then run `codex` once). **iTerm2** ([iterm2.com](https://iterm2.com), free) is recommended for the full look; Terminal.app works too, with colours but no backdrop.

**Install / update (one line).** Open Terminal or iTerm2 (not inside Codex) and paste:
```
curl -fsSL https://raw.githubusercontent.com/TheSunMan123/terminal-jarvis/main/get.sh | bash
```
It asks your name, the assistant's name, how it should address you, a Fish Audio key (optional; press Return for macOS's British "Daniel" voice, or type `none`), and a push-to-talk key (default **Right Option**). Then it downloads the speech model (~150 MB, once).

**Then:**
1. Open a **new** terminal window and type `codex`. In iTerm2 the tab switches to the Jarvis profile (colours + J backdrop) and switches back when Codex exits. You get the greeting, and the status bar shows your limits.
2. **Voice, one-time:** in Codex type `/hooks` and trust the Terminal Jarvis `Stop` hook.
3. **Push-to-talk, one-time permissions:** the first time you hold the talk key, macOS asks to let your terminal app use the **Microphone**: allow it. Then open **System Settings → Privacy & Security** and turn your terminal app (Terminal or iTerm2) on under **Accessibility** *and* **Input Monitoring**. These let it notice the talk key and type your words. Quit and reopen the terminal app afterwards.
4. Hold **Right Option**, speak, let go: a soft *tink* when it starts listening, a *pop* when your words are sent. It only works while a terminal app is in front, and only while a Jarvis Codex session is running.

**What it changes:** the same Codex files as on Windows (`~/.codex/AGENTS.md`, `config.toml` status line, `hooks.json` Stop hook), a small `codex()` function in `~/.zshrc` (and `~/.bashrc` / `~/.bash_profile` if you have them), an iTerm2 Dynamic Profile (`~/Library/Application Support/iTerm2/DynamicProfiles/terminal-jarvis.json`), your Fish key in the **Keychain** (`terminal-jarvis-fish`, if given), and everything else in `~/.terminal-jarvis`.

**Uninstall:** `bash ~/.terminal-jarvis/mac/uninstall.sh` — removes all of the above and puts back any status bar you had before.

**Mute:** set `"voice_muted": true` in `~/.terminal-jarvis/state.json`. **Logs:** `~/.terminal-jarvis/ears.log` (push-to-talk) and `voice.log`.
