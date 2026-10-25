# Agent guide — Mura

Mura is a native macOS menu bar app (SwiftPM, macOS 14+) that turns a blank finite canvas into a static desktop wallpaper. `dmwctl` is its primitive command-line tool: it reads and edits the same board, renders it, and can apply it as wallpaper. If you only want to *use* Mura from an agent (write a reminder onto the wallpaper), read `skills/mura/SKILL.md`; this file is for working on the repo.

## Product intent

A local, lightweight memory surface: a clean whiteboard on the wallpaper. It must not keep a live web wallpaper or heavy overlay running while idle; after save or cancel the editor WebView is released and macOS shows a normal PNG.

## Layout

- `Sources/MemoryWallCore` — board, element, display and preference models.
- `Sources/MemoryWallWorkspace` — file workspace, board store, snapshots, audit log.
- `Sources/MemoryWallRenderer` — AppKit PNG renderer with render budgets.
- `Sources/MemoryWallWallpaper` — display discovery, wallpaper apply/restore, hotkey facade.
- `Sources/MemoryWallEditorBridge` — WKWebView bridge plus bundled editor HTML and the LXGW WenKai font.
- `Sources/MemoryWallAgentTools` — command registry used by `dmwctl` (`ToolRegistry.swift`).
- `Sources/dmwctl` — the CLI entry point. `App/DesktopMemoryWallApp` — the SwiftUI menu bar app.
- `EditorWeb/` — source of the canvas editor; `script/build_editor_assets.sh` bundles it into the app resources.
- `docs/architecture/` (overview, `tool-parity.md` mapping each UI action to a `dmwctl` command), `docs/operations/`, `docs/release/v1.md`.

## Build, test, run

```sh
swift test                              # all unit tests; CI runs the same
swift build --product dmwctl            # the CLI
swift run dmwctl --workspace /tmp/dmw diagnostics --json
script/build_and_run.sh                 # package and open the app (needs the editor assets build, i.e. Node)
```

Use `--workspace DIR` for any experiment so the real workspace under `~/Library/Application Support/DesktopMemoryWall` is untouched.

## Style defaults for content written to the wall

- Start blank. No planner templates, default tasks, or inferred reminder content.
- Very large text; if it is unreadable from normal desktop distance it is too small.
- Hand-drawn feel: warm paper background, dark ink, sparse red/blue accents.
- Short, concrete reminders. Do not turn the wall into a project-management database.

## Rules

- `dmwctl` output is one JSON object `{ok, message, data}`; exit code 0 on success, 1 on failure. Keep that contract and keep commands primitive (`status`, `board read|blank|patch|stroke|write`, `render preview`, `wallpaper apply|restore`, `displays list`, `diagnostics`, `audit tail`); judgment belongs in prompts, not in workflow-shaped commands.
- Preview before applying a wallpaper when operating autonomously. `wallpaper apply` and `wallpaper restore` require `--confirm`; never pass it without the user's go-ahead, because it changes the visible desktop.
- Keep data local in the workspace; never sync or upload reminders.
- Keep `THIRD_PARTY_FONT_LICENSE-LXGWWenKai.txt` with the bundled font.
- Update `docs/architecture/tool-parity.md` when adding or changing a command.
- No personal data in the repo (names, local paths, real reminder contents).
