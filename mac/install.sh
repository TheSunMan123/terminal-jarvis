#!/bin/bash
# Terminal Jarvis for Codex - macOS installer.
#   bash mac/install.sh            (or the one-liner: curl -fsSL .../get.sh | bash)
# Copies the kit to ~/.terminal-jarvis, makes sure "uv" (a small Python runner from astral.sh) is available,
# then hands over to setup.py, which asks the questions and does the rest.
set -e
KIT="$(cd "$(dirname "$0")/.." && pwd)"
TJ="$HOME/.terminal-jarvis"

if [ "$(uname)" != "Darwin" ]; then echo "  macOS only. On Windows run install.ps1."; exit 1; fi

echo
echo "  TERMINAL JARVIS  //  Codex edition  //  macOS"
echo "  ---------------------------------------------"
echo

# --- Codex CLI -------------------------------------------------------------
CODEX=""
for c in "$(command -v codex 2>/dev/null || true)" /opt/homebrew/bin/codex /usr/local/bin/codex \
         "$HOME/.npm-global/bin/codex" "$HOME/.local/bin/codex" "$HOME/.volta/bin/codex"; do
  if [ -n "$c" ] && [ -x "$c" ]; then CODEX="$c"; break; fi
done
if [ -z "$CODEX" ]; then
  echo "  ! Codex CLI not found. Install it first (brew install codex, or npm i -g @openai/codex),"
  echo "    run 'codex' once to sign in, then run this again."
  exit 1
fi

# --- uv (runs the Python helpers with their own Python; nothing touches the system Python) ----
UV=""
for c in "$(command -v uv 2>/dev/null || true)" "$HOME/.local/bin/uv" "$HOME/.cargo/bin/uv" /opt/homebrew/bin/uv "$TJ/uv/uv"; do
  if [ -n "$c" ] && [ -x "$c" ]; then UV="$c"; break; fi
done
if [ -z "$UV" ]; then
  echo "  Setting up uv (a small Python runner from astral.sh)..."
  mkdir -p "$TJ/uv"
  # private copy: no PATH or shell-profile changes; removed by the uninstaller
  curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="$TJ/uv" sh >/dev/null
  UV="$TJ/uv/uv"
fi
if [ ! -x "$UV" ]; then echo "  ! Could not set up uv. Check your internet connection and try again."; exit 1; fi

# --- copy the kit ------------------------------------------------------------
mkdir -p "$TJ/assets"
rm -rf "$TJ/voice" "$TJ/mac"
cp -R "$KIT/voice" "$KIT/mac" "$TJ/"
cp "$KIT/persona.md" "$TJ/persona.md"
cp "$KIT/assets/backdrop-base.png" "$TJ/assets/backdrop-base.png"
chmod +x "$TJ/mac/"*.sh

export UV_SYSTEM_CERTS=1
exec "$UV" run --quiet --script "$TJ/mac/setup.py" --codex "$CODEX" --uv "$UV" "$@"
