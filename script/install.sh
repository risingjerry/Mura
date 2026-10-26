#!/bin/sh
# Installs mura to ~/.local/bin, downloads the handwriting fonts and installs the midnight switch.
#   From a clone:  script/install.sh [--no-schedule]          (builds from source; needs Xcode command line tools)
#   One line:      curl -fsSL https://raw.githubusercontent.com/risingjerry/Mura/main/script/install.sh | sh
#                  (downloads the prebuilt universal binary from the latest release)
set -eu
BIN="$HOME/.local/bin"
mkdir -p "$BIN"
here=$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)
if [ -n "$here" ] && [ -f "$here/../Package.swift" ]; then
  command -v swift >/dev/null || { echo "Swift toolchain missing: run 'xcode-select --install' first" >&2; exit 1; }
  (cd "$here/.." && swift build -c release --product mura)
  install -m 755 "$here/../.build/release/mura" "$BIN/mura"
else
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL -o "$tmp/mura.tar.gz" https://github.com/risingjerry/Mura/releases/latest/download/mura-macos-universal.tar.gz
  tar -xzf "$tmp/mura.tar.gz" -C "$tmp"
  install -m 755 "$tmp/mura" "$BIN/mura"
fi
"$BIN/mura" setup "$@"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "Add ~/.local/bin to your PATH to call 'mura' directly." >&2 ;; esac
