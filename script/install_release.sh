#!/usr/bin/env bash
set -euo pipefail

repo="${MURA_REPO:-risingjerry/Mura}"
app_name="Mura"
asset_name="Mura-v1.dmg"
checksum_name="$asset_name.sha256"
version="${MURA_VERSION:-latest}"
install_dir="${MURA_INSTALL_DIR:-/Applications}"
app_path="$install_dir/$app_name.app"

need_sudo() {
  [[ ! -w "$install_dir" ]] && [[ "$(id -u)" != "0" ]]
}
run_privileged() {
  if need_sudo; then sudo "$@"; else "$@"; fi
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/mura-install.XXXXXX")"
temp_mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/mura-mount.XXXXXX")"
mount_dir="$temp_mount_dir"
did_attach=0
cleanup() {
  set +e
  if [[ "$did_attach" == "1" ]]; then
    hdiutil detach "$mount_dir" -quiet >/dev/null 2>&1 || true
    hdiutil detach "/private$mount_dir" -quiet >/dev/null 2>&1 || true
    hdiutil detach "$mount_dir" -force -quiet >/dev/null 2>&1 || true
    hdiutil detach "/private$mount_dir" -force -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir" "$temp_mount_dir" 2>/dev/null || true
}
trap cleanup EXIT

if [[ "$version" == "latest" ]]; then
  release_base="https://github.com/$repo/releases/latest/download"
else
  release_base="https://github.com/$repo/releases/download/$version"
fi

dmg_path="$tmp_dir/$asset_name"
checksum_path="$tmp_dir/$checksum_name"

if [[ -n "${MURA_DMG_PATH:-}" ]]; then
  echo "Using local DMG: $MURA_DMG_PATH"
  cp "$MURA_DMG_PATH" "$dmg_path"
else
  dmg_url="$release_base/$asset_name"
  checksum_url="$release_base/$checksum_name"
  echo "Downloading $app_name from $dmg_url"
  curl --http1.1 -fL --retry 5 --retry-all-errors --progress-bar "$dmg_url" -o "$dmg_path"
  if curl --http1.1 -fL --retry 3 --retry-all-errors --silent --show-error "$checksum_url" -o "$checksum_path"; then
    expected="$(awk '{print $1}' "$checksum_path")"
    actual="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
    if [[ "$expected" != "$actual" ]]; then
      echo "Checksum mismatch for $asset_name" >&2
      echo "expected: $expected" >&2
      echo "actual:   $actual" >&2
      exit 1
    fi
    echo "Checksum verified"
  else
    echo "Checksum file not available; continuing without checksum verification"
  fi
fi

# curl downloads normally do not get a quarantine flag, but remove it anyway so
# Safari/manual downloads and copied files follow the same path.
xattr -rd com.apple.quarantine "$dmg_path" 2>/dev/null || true
xattr -d com.apple.FinderInfo "$dmg_path" 2>/dev/null || true

existing_volume="/Volumes/Mura v1"
if [[ -d "$existing_volume/$app_name.app" ]]; then
  echo "Using already mounted DMG volume: $existing_volume"
  mount_dir="$existing_volume"
else
  echo "Mounting DMG"
  hdiutil attach "$dmg_path" -mountpoint "$mount_dir" -nobrowse -quiet
  did_attach=1
fi

source_app="$mount_dir/$app_name.app"
if [[ ! -d "$source_app" ]]; then
  echo "Could not find $app_name.app inside the DMG" >&2
  exit 1
fi

# Close a running copy before replacing it.
osascript -e 'tell application "Mura" to quit' >/dev/null 2>&1 || true
pkill -x "$app_name" >/dev/null 2>&1 || true

if [[ -d "$app_path" ]]; then
  echo "Replacing existing $app_path"
  run_privileged rm -rf "$app_path"
fi

echo "Installing to $app_path"
run_privileged ditto "$source_app" "$app_path"

# This is the key for the unsigned GitHub build: not signing, just removing the
# macOS download quarantine marker from the installed app.
run_privileged xattr -rd com.apple.quarantine "$app_path" 2>/dev/null || true
run_privileged xattr -d com.apple.FinderInfo "$app_path" 2>/dev/null || true
find "$app_path" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true

echo "Opening $app_name"
open "$app_path"

echo "$app_name installed and opened: $app_path"
