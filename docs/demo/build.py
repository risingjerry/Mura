#!/usr/bin/env python3
"""Rebuilds docs/demo.gif: an agent plans tomorrow, the desktop switches at midnight, a task gets ticked.

Needs a built `mura` (with `mura setup` fonts), Google Chrome and ffmpeg. All content is made up.
    python3 docs/demo/build.py [--mura .build/release/mura] [--lang en|zh] [--out docs/demo.gif]
"""
import argparse, html, json, os, shutil, subprocess, tempfile
from pathlib import Path

W, H = 1200, 750
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TEXT = {
    "en": dict(prompt="Tomorrow: release notes first, design review at 2pm, gym in the evening. Put it on my wallpaper.",
               title="Tuesday", items=["! Finish the release notes", "2pm design review", "Gym, 45 min"], note="Hardest thing first.",
               ok="ok · 2026-10-27 · switches in after midnight", reply="Done. Tomorrow's list will be on your desktop when you wake up.",
               finished="Release notes are done.", updated="ok · wallpaper updated",
               clocks=["Mon 22:41", "Mon 23:59", "Tue 00:00", "Tue 10:12"]),
    "zh": dict(prompt="明天先写完发布说明，下午两点评审设计，晚上去健身。帮我放到桌面上。",
               title="周二", items=["! 写完发布说明", "14:00 设计评审", "健身 45 分钟"], note="先做最难的那件事。",
               ok="ok · 2026-10-27 · 零点后自动换上", reply="好了，明天醒来桌面上就是这张清单。",
               finished="发布说明写完了。", updated="ok · 壁纸已更新",
               clocks=["周一 22:41", "周一 23:59", "周二 00:00", "周二 10:12"]),
}


def mura(binary, home, *args):
    out = subprocess.run([binary, *args], env={**os.environ, "MURA_HOME": str(home)}, capture_output=True, text=True)
    data = json.loads(out.stdout)
    assert data["ok"], data
    return data["data"]


def walls(binary, work, t):
    home = work / "home"
    fonts = Path.home() / "Library/Application Support/Mura/fonts"
    if fonts.exists():
        shutil.copytree(fonts, home / "fonts")
    day = "2026-10-27"
    mura(binary, home, "plan", "--date", day, "--title", t["title"], *t["items"], "--note", t["note"])
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
    .body{{padding:14px 16px;font:13.5px/1.55 Menlo,'PingFang SC',monospace;color:#e6e6e6;min-height:150px}}
    .user{{color:#fff}} .user::before{{content:"> ";color:#d97757}} .tool{{color:#8fd18f}} .tool::before{{content:"⏺ ";color:#8fd18f}}
    .out{{color:#9a9a9a;padding-left:18px}} .out::before{{content:"⎿ "}} .say{{color:#e6e6e6}} .say::before{{content:"⏺ ";color:#fff}}
    </style>{under}{bg}<div class="menu"><b></b><span>{clock}</span></div>{term}"""


def build(binary, out, lang):
    t = TEXT[lang]
    PROMPT, (c1, c2, c3, c4) = t["prompt"], t["clocks"]
    PLAN = "mura plan --date tomorrow --title " + t["title"] + " " + " ".join(f'"{i}"' for i in t["items"])
    work = Path(tempfile.mkdtemp(prefix="mura-demo-"))
    wall1, wall2 = walls(binary, work, t)
    frames = []  # (html, seconds)
    step = 6 if lang == "en" else 2
    for i in range(0, len(PROMPT) + 1, step):
        frames.append((frame(None, c1, [("user", PROMPT[:i])]), 0.06))
    done_prompt = [("user", PROMPT)]
    frames.append((frame(None, c1, done_prompt + [("tool", PLAN)]), 1.0))
    frames.append((frame(None, c1, done_prompt + [("tool", PLAN), ("out", t["ok"])]), 1.2))
    frames.append((frame(None, c1, done_prompt + [("tool", PLAN), ("out", t["ok"]),
                                                         ("say", t["reply"])]), 1.8))
    frames.append((frame(None, c2, [], show_terminal=False), 0.8))
    for k in range(1, 6):
        frames.append((frame(wall1, c3, [], show_terminal=False, fade=k / 5), 0.08))
    frames.append((frame(wall1, c3, [], show_terminal=False), 2.4))
    ticked = t["finished"]
    for i in range(0, len(ticked) + 1, 4 if lang == "en" else 1):
        frames.append((frame(wall1, c4, [("user", ticked[:i])]), 0.06))
    frames.append((frame(wall1, c4, [("user", ticked), ("tool", "mura done 1")]), 0.9))
    for k in range(1, 5):
        frames.append((frame(wall2, c4, [("user", ticked), ("tool", "mura done 1"), ("out", t["updated"])],
                             wall_under=wall1, fade=k / 4), 0.08))
    frames.append((frame(wall2, c4, [], show_terminal=False), 3.0))

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
    parser.add_argument("--lang", choices=sorted(TEXT), default="en")
    parser.add_argument("--out")
    args = parser.parse_args()
    out = Path(args.out or ("docs/demo.gif" if args.lang == "en" else f"docs/demo-{args.lang}.gif"))
    build(os.path.abspath(args.mura), out, args.lang)
