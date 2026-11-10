#!/bin/bash
# Terminal Jarvis (macOS): check / request the three permissions push-to-talk needs
# (Microphone, Accessibility, Input Monitoring).
# Run this from the SAME terminal app you use for Jarvis (Terminal, iTerm2, ...): macOS grants the
# permissions to that app.   bash ~/.terminal-jarvis/mac/permissions.sh
TJ="$HOME/.terminal-jarvis"
[ -f "$TJ/state.env" ] && . "$TJ/state.env"
if [ -z "$TJ_UV" ] || [ ! -x "$TJ_UV" ]; then TJ_UV="$(command -v uv)"; fi
if [ -z "$TJ_UV" ]; then echo "  uv not found. Re-run the Terminal Jarvis installer."; exit 1; fi
UV_SYSTEM_CERTS=1 "$TJ_UV" run --quiet --script "$TJ/voice/ears.py" --permissions --state "$TJ/state.json"
# restart the background listener so it picks up anything just granted
if [ -f "$TJ/ears.pid" ]; then kill "$(cat "$TJ/ears.pid" 2>/dev/null)" 2>/dev/null; rm -f "$TJ/ears.pid"; fi
echo "  Open a new Jarvis session (type codex) and hold your talk key. Log: $TJ/ears.log"
