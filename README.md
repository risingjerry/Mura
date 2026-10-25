<p align="center">
  <img src="docs/images/mura-logo.png" width="112" height="112" alt="Mura logo">
</p>

# Mura — turn a finite canvas into your Mac desktop wallpaper

<p align="center">
  <strong>English</strong> · <a href="README.zh-CN.md">中文</a> · <a href="https://github.com/risingjerry/Mura/releases/latest"><strong>Download</strong></a> · <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-blue.svg"></a>
</p>

**Mura is a small macOS menu bar app: write and doodle on a blank canvas, press one button, and it becomes your desktop wallpaper, so the things you must remember are the first thing you see.**

![Demo: write a note on the Mura canvas, click Save to desktop and it becomes the macOS wallpaper; an agent then adds a reminder with dmwctl and applies it with --confirm](docs/demo.gif)

## What is Mura?

> Open a finite canvas, write or draw on it, and save it as your wallpaper.

Good for what you should see every time you open your laptop:

- the few most important things today
- one line to remind yourself
- a quick arrow, circle or line
- different notes on different screens

Mura is not a task manager. It does one thing: **it makes your desktop itself a reminder canvas.**

![Mura editor screenshot](docs/images/mura-editor.png)

![Mura color palette screenshot](docs/images/mura-colors.png)

## Install

One line in Terminal. It downloads the release, installs `Mura.app` into `/Applications`, removes the quarantine flag of the unsigned build, and opens Mura:

```bash
curl -fsSL https://raw.githubusercontent.com/risingjerry/Mura/main/script/install_release.sh | bash
```

Terminal asks for your login password if macOS needs permission.

Or install by hand: download `Mura-v1.dmg` from [Releases](https://github.com/risingjerry/Mura/releases/latest), open it, drag `Mura.app` to `/Applications`, and start it.

## Highlights

- **Finite canvas** — a clean whiteboard with text, pen, eraser, undo/redo and colors.
- **Save to desktop** — rendered as a plain PNG wallpaper. After saving there is no editor window and no live web wallpaper running.
- **Per-screen editing** on multiple displays.
- **Local first** — your canvas stays on your Mac; no account.
- **Agent friendly** — a `dmwctl` command-line tool with JSON output lets Claude Code or Codex write reminders onto your wallpaper.

## How it works

Mura is a native SwiftPM macOS menu bar app. Editing opens a bundled local canvas editor in a web view. Saving stores the board JSON and a PNG in the local workspace and applies the PNG as wallpaper; then the editor is released and macOS just shows an image. `dmwctl` reads and writes the same board files. Details: [docs/architecture/overview.md](docs/architecture/overview.md).

## Use with Claude Code / Codex

```bash
npx skills add risingjerry/Mura
```

Or copy `skills/mura` to `~/.claude/skills/` or `~/.agents/skills/`. Then say, for example:

- `Put my three most important tasks for today on my desktop wallpaper.`
- `Underline "Report due Friday" in red on the wallpaper.`
- `Restore my previous wallpaper.`

The skill makes the agent render a preview first and only change the wallpaper with `--confirm` after you agree. `dmwctl` is not inside the DMG: build it from the repo with `swift build -c release --product dmwctl` (macOS 14+, Swift toolchain). See [AGENTS.md](AGENTS.md) and [skills/mura/SKILL.md](skills/mura/SKILL.md).

## Limits and requirements

- macOS 14 or newer.
- The v1 build is ad-hoc signed and **not notarized by Apple** (see the FAQ below).
- Mura is a reminder canvas, not task management.
- The command-line tool has to be built with Swift.

## FAQ

### How do I put my to-do list on my Mac desktop wallpaper?
Install Mura, open the edit canvas, write your items with the text tool, and click Save to desktop. Or ask an agent to do it through `dmwctl`.

### macOS says Mura can't be opened, the developer can't be verified, or the app is damaged. What do I do?
v1 is not notarized, so macOS may show warnings such as "cannot be opened because the developer cannot be verified" or "Mura-v1.dmg is damaged". First try right-click → **Open**. If that is not enough, remove the quarantine flag. **Only do this for files you downloaded from the official Releases page.**

If the DMG itself will not open:

```bash
sudo xattr -rd com.apple.quarantine ~/Downloads/Mura-v1.dmg
open ~/Downloads/Mura-v1.dmg
```

Drag `Mura.app` into `/Applications`. If the app still will not open:

```bash
sudo xattr -rd com.apple.quarantine /Applications/Mura.app
open /Applications/Mura.app
```

(If `/Applications/Mura.app` does not exist yet, the second command fails with "No such file".)

### Does Mura upload my notes?
No. The canvas is stored in `~/Library/Application Support/DesktopMemoryWall`, and there is no account.

### Does it keep using resources after I save?
No. After save or cancel the editor web view is released; the desktop shows an ordinary PNG.

### Can an AI agent write my wallpaper?
Yes, see "Use with Claude Code / Codex". The agent previews by default and needs your go-ahead (`--confirm`) to change the wallpaper.

### How do I get my old wallpaper back?
Mura records the previous wallpaper before applying a new one. Ask your agent to run `dmwctl wallpaper restore --confirm`, or just pick it again in **System Settings → Wallpaper**.

## Uninstall

1. Quit Mura and drag `/Applications/Mura.app` to the Trash.
2. First choose the wallpaper you want in **System Settings → Wallpaper** (or run `dmwctl wallpaper restore --confirm`).
3. Optional: delete local data with `rm -rf ~/Library/Application\ Support/DesktopMemoryWall`.

## Credits and license

Mura is open source under the [MIT License](LICENSE). The bundled font is [LXGW WenKai](https://github.com/lxgw/LxgwWenKai), licensed under the SIL Open Font License 1.1; the full text is in [THIRD_PARTY_FONT_LICENSE-LXGWWenKai.txt](THIRD_PARTY_FONT_LICENSE-LXGWWenKai.txt).

---

If Mura keeps your desktop useful, a star helps others find it.


