#!/bin/sh
# Builds mura from this checkout, installs it to ~/.local/bin, downloads the fonts and installs the midnight switch.
# Usage: script/install.sh [--no-schedule]
set -eu
cd "$(dirname "$0")/.."
command -v swift >/dev/null || { echo "Swift toolchain missing: run 'xcode-select --install' first" >&2; exit 1; }
swift build -c release --product mura
mkdir -p "$HOME/.local/bin"
install -m 755 .build/release/mura "$HOME/.local/bin/mura"
"$HOME/.local/bin/mura" setup "$@"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "Add ~/.local/bin to your PATH to call 'mura' directly." >&2 ;; esac
