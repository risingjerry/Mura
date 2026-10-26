#!/usr/bin/env python3
"""Rebuilds docs/demo.gif: an agent plans tomorrow, the desktop switches at midnight, a task gets ticked.

Needs a built `mura` (with `mura setup` fonts), Google Chrome and ffmpeg. All content is made up.
    python3 docs/demo/build.py [--mura .build/release/mura] [--out docs/demo.gif]
"""
import argparse, html, json, os, shutil, subprocess, tempfile
from pathlib import Path

W, H = 1200, 750
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PROMPT = "Tomorrow: release notes first, design review at 2pm, gym in the evening. Put it on my wallpaper."
PLAN = 'mura plan --date tomorrow --title Tuesday "! Finish the release notes" "2pm design review" "Gym, 45 min"'


def mura(binary, home, *args):
    out = subprocess.run([binary, *args], env={**os.environ, "MURA_HOME": str(home)}, capture_output=True, text=True)
    data = json.loads(out.stdout)
    assert data["ok"], data
    return data["data"]


def walls(binary, work):
    home = work / "home"
    fonts = Path.home() / "Library/Application Support/Mura/fonts"
    if fonts.exists():
        shutil.copytree(fonts, home / "fonts")
    day = "2026-10-27"
    mura(binary, home, "plan", "--date", day, "--title", "Tuesday", "! Finish the release notes", "2pm design review",
         "Gym, 45 min", "--note", "Hardest thing first.")
    first = mura(binary, home, "render", "--date", day, "--size", "2400x1500", "--out", str(work / "a"))["images"][0]["file"]
    mura(binary, home, "done", "1", "--date", day)
    second = mura(binary, home, "render", "--date", day, "--size", "2400x1500", "--out", str(work / "b"))["images"][0]["file"]
    return first, second


def frame(wall, clock, lines, show_terminal=True, wall_under=None, fade=1.0):
    under = f'<img class="wall" src="file://{wall_under}">' if wall_under else ""
    bg = f'<img class="wall" style="opacity:{fade}" src="file://{wall}">' if wall else '<div class="wall plain"></div>'
    term = ""
    if show_terminal:
        body = "".join(f'<div class="{cls}">{html.escape(text)}</div>' for cls, text in lines)
        term = f'<div class="term"><div class="bar"><i></i><i></i><i></i><span>claude</span></div><div class="body">{body}</div></div>'
    return f"""<!doctype html><meta charset="utf-8"><style>
    *{{margin:0;box-sizing:border-box}} body{{width:{W}px;height:{H}px;overflow:hidden;position:relative;font-family:-apple-system,Helvetica,sans-serif;background:#000}}
    .wall{{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}}
    .plain{{background:linear-gradient(135deg,#1d3557,#457b9d 55%,#a8dadc)}}
    .menu{{position:absolute;top:0;left:0;right:0;height:26px;background:rgba(245,240,230,.72);backdrop-filter:blur(8px);font-size:13px;display:flex;align-items:center;justify-content:space-between;padding:0 16px;color:#222}}
    .term{{position:absolute;right:28px;bottom:28px;width:560px;background:#1e1e1e;border-radius:10px;box-shadow:0 18px 50px rgba(0,0,0,.45);overflow:hidden}}
    .bar{{height:28px;background:#2d2d2d;display:flex;align-items:center;padding:0 10px;gap:7px;color:#999;font-size:12px}}
    .bar i{{width:11px;height:11px;border-radius:50%;background:#ff5f57}} .bar i:nth-child(2){{background:#febc2e}} .bar i:nth-child(3){{background:#28c840}}
    .bar span{{margin-left:auto;margin-right:auto;transform:translateX(-30px)}}
    .body{{padding:14px 16px;font:13.5px/1.55 Menlo,monospace;color:#e6e6e6;min-height:150px}}
    .user{{color:#fff}} .user::before{{content:"> ";color:#d97757}} .tool{{color:#8fd18f}} .tool::before{{content:"⏺ ";color:#8fd18f}}
    .out{{color:#9a9a9a;padding-left:18px}} .out::before{{content:"⎿ "}} .say{{color:#e6e6e6}} .say::before{{content:"⏺ ";color:#fff}}
    </style>{under}{bg}<div class="menu"><b></b><span>{clock}</span></div>{term}"""


def build(binary, out):
    work = Path(tempfile.mkdtemp(prefix="mura-demo-"))
    wall1, wall2 = walls(binary, work)
    frames = []  # (html, seconds)
    for i in range(0, len(PROMPT) + 1, 6):
        frames.append((frame(None, "Mon 22:41", [("user", PROMPT[:i])]), 0.06))
    done_prompt = [("user", PROMPT)]
    frames.append((frame(None, "Mon 22:41", done_prompt + [("tool", PLAN)]), 1.0))
    frames.append((frame(None, "Mon 22:41", done_prompt + [("tool", PLAN), ("out", "ok · 2026-10-27 · switches in after midnight")]), 1.2))
    frames.append((frame(None, "Mon 22:41", done_prompt + [("tool", PLAN), ("out", "ok · 2026-10-27 · switches in after midnight"),
                                                         ("say", "Done. Tomorrow's list will be on your desktop when you wake up.")]), 1.8))
    frames.append((frame(None, "Mon 23:59", [], show_terminal=False), 0.8))
    for k in range(1, 6):
        frames.append((frame(wall1, "Tue 00:00", [], show_terminal=False, fade=k / 5), 0.08))
    frames.append((frame(wall1, "Tue 00:00", [], show_terminal=False), 2.4))
    ticked = "Release notes are done."
    for i in range(0, len(ticked) + 1, 4):
        frames.append((frame(wall1, "Tue 10:12", [("user", ticked[:i])]), 0.06))
    frames.append((frame(wall1, "Tue 10:12", [("user", ticked), ("tool", "mura done 1")]), 0.9))
    for k in range(1, 5):
        frames.append((frame(wall2, "Tue 10:12", [("user", ticked), ("tool", "mura done 1"), ("out", "ok · wallpaper updated")],
                             wall_under=wall1, fade=k / 4), 0.08))
    frames.append((frame(wall2, "Tue 10:12", [], show_terminal=False), 3.0))

    concat = []
    for n, (page, seconds) in enumerate(frames):
        src, png = work / f"f{n:03}.html", work / f"f{n:03}.png"
        src.write_text(page)
        subprocess.run([CHROME, "--headless=new", "--hide-scrollbars", "--allow-file-access-from-files", f"--window-size={W},{H}",
                        f"--screenshot={png}", f"file://{src}"], check=True, capture_output=True)
        concat += [f"file '{png}'", f"duration {seconds}"]
    concat.append(f"file '{work / f'f{len(frames) - 1:03}.png'}'")
    (work / "list.txt").write_text("\n".join(concat))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", str(work / "list.txt"),
                    "-vf", "fps=12,scale=900:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=4",
                    str(out)], check=True)
    shutil.rmtree(work)
    print(out, os.path.getsize(out), "bytes")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--mura", default=".build/release/mura")
    parser.add_argument("--out", default="docs/demo.gif")
    args = parser.parse_args()
    build(os.path.abspath(args.mura), Path(args.out))
