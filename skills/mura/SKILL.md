---
name: mura
description: Write reminders, notes or simple drawings onto the user's macOS desktop wallpaper with Mura's `dmwctl` command-line tool. Use when the user wants something to show on their desktop background ("put today's top 3 tasks on my wallpaper", "remind me on my desktop", "把提醒写到桌面壁纸上", "更新桌面看板") or wants to restore the previous wallpaper. macOS only.
---

# Mura — reminders on the wallpaper

Mura keeps one finite canvas ("board") per workspace and renders it into a normal PNG wallpaper. `dmwctl` edits that board from the terminal. Every command prints one JSON object `{"ok": bool, "message": string, "data": {...}}` and exits 0 on success, 1 on failure. Always pass `--json` (accepted for clarity; output is JSON either way).

## First contact

```sh
dmwctl status --json        # if the command is missing, see below
dmwctl diagnostics --json   # data.editor.ready should be true
```

`dmwctl` is not shipped inside the `.dmg`. If it is missing, build it from the repo: `git clone https://github.com/risingjerry/Mura && cd Mura && swift build -c release --product dmwctl`, then run `.build/release/dmwctl`. Use `swift run dmwctl ...` inside the clone as an alternative. Requires macOS 14+ and the Swift toolchain.

Use `--workspace /tmp/mura-test` while experimenting so the user's real board is untouched. The default workspace is `~/Library/Application Support/DesktopMemoryWall`.

## Safety rules

- Reading and rendering a preview are safe. `board blank`, `board write` take a snapshot of the previous board first.
- `wallpaper apply --confirm` and `wallpaper restore --confirm` change what the user sees on screen. Render a preview first, show the user the file path, and add `--confirm` only after they agree (or they asked for the change explicitly).
- Without `--confirm` those two commands fail with a confirmation error; never work around that.
- Do not invent reminder content. Put on the wall only what the user told you.

## Recipe: put reminders on the wallpaper

```sh
dmwctl displays list --json                       # find the main display size
dmwctl board blank --json                         # fresh canvas at main display size (snapshots the old one)
dmwctl board patch --text "Ship the report" --x 160 --y 160 --width 1200 --height 160 --font-size 96 --json
dmwctl board patch --text "Call the dentist" --x 160 --y 360 --font-size 96 --json
dmwctl board stroke --points "160,330;900,330" --color "#c0392b" --width 8 --json   # an underline
dmwctl render preview --json                      # data.file is a PNG to look at
dmwctl render preview --wallpaper --json          # writes the wallpaper render
dmwctl wallpaper apply --confirm --json           # only after the user agrees
```

Add to what is already there instead of blanking: skip `board blank`, run `dmwctl board read --json` first to see existing elements and their coordinates (`data.elements`), then `board patch` below them.

## Commands

| Command | Effect |
|---|---|
| `status` | active board summary, main display, whether a render exists |
| `diagnostics` | board, display count, editor and font readiness, last audit events |
| `displays list` | display profiles (id, size, scale) |
| `board read` | full active board JSON |
| `board blank [--width N --height N]` | new empty board (snapshot first) |
| `board patch --text T [--x --y --width --height --font-size --color]` | add a text element (`board text` is an alias) |
| `board stroke --points "x,y;x,y;..." [--color --width]` | add a freehand line, at least two points |
| `board write --file board.json` | replace the board from a JSON file (snapshot first) |
| `render preview [--width N --height N] [--wallpaper]` | render PNG; `--wallpaper` writes the wallpaper file |
| `wallpaper apply --confirm` | apply the latest wallpaper render, remembering the previous one |
| `wallpaper restore --confirm` | put the previous wallpaper back |
| `audit tail` | last audit events |

## Style

Start blank. Use very large text (80-120 for a 1920x1080 canvas; if it is not readable from normal desktop distance it is too small). Short, concrete lines, a few per screen. Warm paper background, dark ink, sparse red/blue accents. Do not turn the wall into a task database.

## Errors

- `ok: false` with "Missing argument: ..." — a required flag is missing; read the message.
- confirmation required — you forgot `--confirm`; ask the user first.
- `diagnostics` shows `editor.ready` false — the editor/font assets are missing from this build; rebuild from the repo.

More: `docs/architecture/tool-parity.md` in the repo maps every UI action to its command.
