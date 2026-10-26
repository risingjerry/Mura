---
name: mura
description: Put the user's to-do list for a day onto their macOS desktop wallpaper, drawn in an Excalidraw-style hand-drawn look, with the `mura` CLI. Use when the user (or a plan you made with them) settles what they will do today or tomorrow and it should be the first thing they see ("put tomorrow's plan on my wallpaper", "把明天要做的写到桌面上", "我做完了第二件", "更新桌面待办"), when they finish or drop an item, or when they want the previous wallpaper back. macOS only.
---

# Mura — the day's list on the wallpaper

Each day is a small Markdown file. Editing **today** redraws the wallpaper at once; any other day switches in by itself after midnight (a LaunchAgent runs `mura tick` every 5 minutes). Mura lays everything out; you never pass coordinates.

Every command prints one JSON object: `{"ok": true, "command": ..., "data": {...}, "warnings": [...]?}` or `{"ok": false, "error": {"code", "message"}}`. Exit 0 ok, 1 failure, 2 usage. `mura help` lists every command.

## First contact

```sh
mura doctor     # fonts installed? schedule loaded? timezone? what is on screen?
```

- Command missing: `git clone https://github.com/risingjerry/Mura && cd Mura && script/install.sh` (needs Xcode command line tools; installs to `~/.local/bin/mura`, downloads the fonts, installs the midnight switch).
- `schedule.loaded` false → `mura setup` (or tell the user that other days will not switch in by themselves).
- If the user lives in another timezone than the Mac's clock, set it once: `mura config set timezone Asia/Shanghai`. "today" and the midnight switch follow it.

## Recipes

```sh
# Plan tomorrow (replaces that day). Markdown: '# title', '- [ ] item', '! ' = important, '- [x]' = done, '> note'
mura plan --date tomorrow --stdin <<'EOF'
# Tuesday
- [ ] ! Ship the release notes
- [ ] 2pm design review
- [ ] Gym, 45 min
> Do the hardest thing first.
EOF

mura add "Call the bank" --important          # append to today (wallpaper updates now)
mura show                                       # numbered items
mura done 2                                     # tick item 2 (also: undone N, rm N)
mura render --date tomorrow                     # PNG previews without touching the wallpaper; look at data.images[].file
mura undo                                       # put back the wallpaper from before the last change
```

Dates: `today` (default), `tomorrow`, `yesterday`, `+N`, `-N`, `YYYY-MM-DD`.

## Rules

- Write only what the user decided. Do not invent tasks, motivational notes or titles they did not ask for. Keep items short (one line each, about 5–40 characters); the layout shrinks text and finally hides overflow as "…and N more".
- Use `!` for at most one or two truly important items.
- To change one item, use `done`/`undone`/`rm`/`add`; use `plan` only to replace the whole day. Read with `mura show` before editing a day someone else may have written.
- Editing today changes the visible desktop immediately and is reversible with `mura undo`. If the user only wants to prepare, use `--no-apply` or plan a future date.
- Read `warnings` in every response and relay them (e.g. fonts missing, schedule not installed, only the current Space updated).
- Never edit files under `~/Library/Application Support/Mura` by hand while also running commands; use the CLI.

## Errors

| `error.code` | Meaning | Do |
|---|---|---|
| `usage` | bad flag, date or item number | fix the call; `mura show` for numbers |
| `not_found` | nothing to undo, no display | report |
| `network` / `checksum` | font download failed in `mura setup` | retry later; rendering falls back to system fonts |
| `wallpaper` | macOS refused the image | report with the message |
| `spaces` (warning) | only the current desktop Space got the wallpaper | report; `mura config set spaces current` makes this the normal mode |
