# Terminal Jarvis — Codex edition

Turns the **Codex CLI** on Windows into Jarvis:

- **Persona** — every Codex session talks like a composed, quick-witted AI chief of staff, using your name.
- **Status bar** — the model, your **5-hour** and **weekly** usage limits, context left and the current folder, always visible at the bottom.
- **The look** — a "Jarvis · Codex" Windows Terminal profile with the Jarvis colours and a HUD backdrop carrying your assistant's name, plus a desktop shortcut.

Nothing uploaded, no accounts: Codex keeps using **your own** ChatGPT login and plan.

## Requirements
- Windows 10/11 with **Windows Terminal** (Microsoft Store)
- **Codex CLI** signed in (`npm i -g @openai/codex`, then run `codex` once and log in). Codex 0.101 or newer.

## Quick install (one line)
Open **PowerShell** and paste:
```
irm https://raw.githubusercontent.com/TheSunMan123/terminal-jarvis/main/get.ps1 | iex
```
It downloads the kit and runs the installer (steps 3-8 below). Paste the same line again any time to **update**.

## Install (from a download)
1. Unzip this folder anywhere.
2. **Double-click `Install Jarvis.cmd`.** (Or in a terminal: `powershell -ExecutionPolicy Bypass -File .\install.ps1`.)
3. Answer: your name, your assistant's name (default **Jarvis**), how it should address you (default **sir**).
4. **Voice:** paste a **Fish Audio API key** for the real Jarvis voice (free account at fish.audio → API Keys; the key is stored in Windows Credential Manager, never in a file). Press **Enter** to skip and use the free Windows voice, or type `none` for silent.
5. Pick a push-to-talk key (default **Right Alt**).
6. **Close every Windows Terminal window once** (Terminal only loads new profiles and PATH changes when it starts).
7. Now just **type `codex`** in any terminal: an ordinary Terminal tab hands off to a new **Jarvis tab** in the same folder (theme, backdrop, status chip, greeting, voice). The desktop shortcut **"Jarvis (Codex)"** does the same.
8. **Voice, one-time:** in Codex type `/hooks` and **trust** the Terminal Jarvis `Stop` hook. Codex never runs a new hook until you approve it.

**Push-to-talk:** in the Jarvis window, hold your talk key and speak; let go and it's typed into Codex and sent (Windows voice typing, Win+H; the first time Windows may ask you to turn it on).
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
| Backdrop, icon, voice scripts | `%LOCALAPPDATA%\TerminalJarvis` | |

**Uninstall:** `powershell -ExecutionPolicy Bypass -File .\uninstall.ps1` — removes all of the above and puts back any status bar you had before.

## Tips
- Make it your default: Windows Terminal → Settings → Startup → Default profile → **Jarvis · Codex**.
- Change your name or the assistant's name any time: just run `install.ps1` again.
- The 5-hour / weekly limit readouts come from your ChatGPT plan; on plans without those windows Codex may leave them blank.
