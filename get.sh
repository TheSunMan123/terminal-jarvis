#!/bin/bash
# Terminal Jarvis one-line installer for macOS. In Terminal or iTerm2:
#   curl -fsSL https://raw.githubusercontent.com/TheSunMan123/terminal-jarvis/main/get.sh | bash
# Downloads the latest kit from GitHub, then runs its installer (it asks a few questions).
# Run the same line again any time to update.
set -e
if [ "$(uname)" != "Darwin" ]; then
  echo "  This one is for macOS. On Windows, use the PowerShell line in the README."
  exit 1
fi
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
echo "  Downloading Terminal Jarvis..."
curl -fsSL "https://github.com/TheSunMan123/terminal-jarvis/archive/refs/heads/main.tar.gz" | tar -xz -C "$work"
kit="$(find "$work" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
# stdin is this script (piped from curl), so the installer's questions read from the keyboard instead
bash "$kit/mac/install.sh" < /dev/tty
