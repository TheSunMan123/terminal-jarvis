#!/bin/bash
# Terminal Jarvis (macOS): what typing "codex" runs (via the small codex() function in ~/.zshrc).
# - scripted use (codex exec, login, mcp, piped input/output, Codex's own child processes) -> plain Codex
# - otherwise: Jarvis colours (iTerm2: the full profile with the backdrop), a spoken greeting,
#   push-to-talk while the session runs, then Codex. Everything is put back when Codex exits.
TJ="$HOME/.terminal-jarvis"
[ -f "$TJ/state.env" ] && . "$TJ/state.env"
if [ -z "$TJ_CODEX" ] || [ ! -x "$TJ_CODEX" ]; then TJ_CODEX="$(command -v codex)"; fi
if [ -z "$TJ_CODEX" ]; then echo "  Codex CLI not found. Install it, then try again."; exit 1; fi

case "$1" in
  exec|e|review|login|logout|mcp|mcp-server|app-server|app|completion|sandbox|debug|apply|a|cloud|features|help|doctor|update|proto|--version|-V|--help|-h)
    exec "$TJ_CODEX" "$@" ;;
esac
if [ -n "$TERMINAL_JARVIS" ] || [ ! -t 0 ] || [ ! -t 1 ] || [ ! -f "$TJ/state.env" ]; then exec "$TJ_CODEX" "$@"; fi

# --- look ---------------------------------------------------------------------
prev_profile="$ITERM_PROFILE"
if [ "$TERM_PROGRAM" = "iTerm.app" ] && [ -n "$TJ_PROFILE" ]; then
  printf '\033]1337;SetProfile=%s\007' "$TJ_PROFILE"          # whole profile: colours + J backdrop
else
  # other terminals: navy background, warm white text, gold cursor (standard OSC colour codes)
  printf '\033]11;#06101B\007\033]10;#EAF1F8\007\033]12;#FFC247\007'
fi
mkdir -p "$TJ/sessions"
echo $$ > "$TJ/sessions/$$"
restore() {
  rm -f "$TJ/sessions/$$"
  if [ "$TERM_PROGRAM" = "iTerm.app" ] && [ -n "$TJ_PROFILE" ]; then
    printf '\033]1337;SetProfile=%s\007' "${prev_profile:-Default}"
  else
    printf '\033]111\007\033]110\007\033]112\007'
  fi
}
trap restore EXIT
trap 'exit 129' TERM HUP     # (Ctrl+C belongs to Codex; the EXIT trap still restores afterwards)

# --- push-to-talk engine (one per Mac; quits ~20 s after the last Jarvis session) ------------
if [ "$TJ_PTT_KEY" != "none" ] && [ -n "$TJ_PTT_KEY" ] && [ -x "$TJ_UV" ]; then
  if ! { [ -f "$TJ/ears.pid" ] && kill -0 "$(cat "$TJ/ears.pid" 2>/dev/null)" 2>/dev/null; }; then
    UV_SYSTEM_CERTS=1 nohup "$TJ_UV" run --quiet --script "$TJ/voice/ears.py" --mac --state "$TJ/state.json" \
      >>"$TJ/ears.log" 2>&1 < /dev/null &
    disown 2>/dev/null || true
  fi
fi

# --- welcome back: banner + spoken greeting each launch (skipped if another opened in the last minute) ---
stamp="$TJ/last-greeting"
if [ ! -f "$stamp" ] || [ $(( $(date +%s) - $(stat -f %m "$stamp" 2>/dev/null || echo 0) )) -ge 60 ]; then
  touch "$stamp"
  hr=$(date +%H); hr=${hr#0}
  if [ "$hr" -ge 5 ] && [ "$hr" -lt 12 ]; then part=morning; elif [ "$hr" -ge 12 ] && [ "$hr" -lt 17 ]; then part=afternoon; else part=evening; fi
  line="Good $part, ${TJ_ADDRESS:-sir}. Welcome back. All systems are online."
  name="$(echo "${TJ_ASSISTANT:-Jarvis}" | tr '[:lower:]' '[:upper:]' | tr -d ' ' | sed 's/./&./g')"
  printf '\n   \033[96m\xe2\x97\x86 %s\033[0m   \033[33m\xc2\xb7   NEURAL LINK ACTIVE   \xc2\xb7   CODEX CHANNEL\033[0m\n   %s\n\n' "$name" "$line"
  if [ "$TJ_VOICE" != "none" ] && [ -x "$TJ_UV" ]; then
    UV_SYSTEM_CERTS=1 "$TJ_UV" run --quiet --script "$TJ/mac/speak.py" --say "$line" >/dev/null 2>&1 &
  fi
  sleep 1.6   # let the banner be seen before Codex takes the screen
fi

export TERMINAL_JARVIS=1   # anything Codex starts that calls "codex" again gets plain Codex
"$TJ_CODEX" "$@"
