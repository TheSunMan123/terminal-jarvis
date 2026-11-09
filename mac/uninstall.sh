#!/bin/bash
# Terminal Jarvis for Codex - macOS uninstaller:  bash ~/.terminal-jarvis/mac/uninstall.sh
# Removes the persona block, status bar line, voice hook, the codex() function, the iTerm2 profile,
# the Keychain key (if the installer saved it) and ~/.terminal-jarvis. Everything else is left as it was.
TJ="$HOME/.terminal-jarvis"
[ -f "$TJ/state.env" ] && . "$TJ/state.env"
UV="${TJ_UV:-$(command -v uv)}"
[ -f "$TJ/ears.pid" ] && kill "$(cat "$TJ/ears.pid")" 2>/dev/null
if [ -x "$UV" ]; then
  "$UV" run --quiet --script "$TJ/mac/setup.py" --uninstall
else
  echo "  ! uv not found: remove the terminal-jarvis blocks from ~/.codex/AGENTS.md, ~/.codex/config.toml,"
  echo "    ~/.codex/hooks.json and ~/.zshrc by hand."
fi
rm -rf "$TJ"
echo "  Terminal Jarvis removed. Open a new terminal window; Codex is back to normal."
