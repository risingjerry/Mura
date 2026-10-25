# Agent Tool Parity

Every visible user action has a primitive `dmwctl` equivalent over the same workspace. The active product path is coordinate-based; template commands are deprecated and intentionally return a removal message.

| UI action | CLI primitive | Workspace effect | Safety gate |
|---|---|---|---|
| Open menu/status | `dmwctl status --json` | Reads active board, display, render state | None |
| Open edit mode | `dmwctl board read --json` | Reads `boards/active-board.json` | None |
| Start blank canvas | `dmwctl board blank --width 1920 --height 1080 --json` | Snapshots previous board, writes blank finite board | Snapshot first |
| Add text | `dmwctl board patch --text "..." --x 120 --y 120 --json` | Adds a text element at board coordinates | Audit event |
| Add stroke | `dmwctl board stroke --points "10,10;80,40" --json` | Adds a freedraw element at board coordinates | Audit event |
| Replace board | `dmwctl board write --file board.json --json` | Snapshots previous board, replaces active board | Snapshot first |
| Render preview | `dmwctl render preview --width 1920 --height 1080 --json` | Writes `renders/previews/*.png` | No wallpaper apply |
| Render wallpaper image | `dmwctl render preview --wallpaper --json` | Writes `renders/latest-wallpaper.png` | No wallpaper apply |
| Apply wallpaper | `dmwctl wallpaper apply --confirm --json` | Stores previous wallpaper snapshot, calls wallpaper backend | `--confirm` required |
| Restore previous wallpaper | `dmwctl wallpaper restore --confirm --json` | Reads latest wallpaper snapshot, reapplies previous image | `--confirm` required |
| List displays | `dmwctl displays list --json` | Reads display profiles | None |
| Diagnostics | `dmwctl diagnostics --json` | Reads board/display/render/audit/editor/font summary | None |

Commands are intentionally primitive. Higher-level choices, such as what reminders belong on the wall, should live in prompts or `AGENTS.md`, not in app code.
