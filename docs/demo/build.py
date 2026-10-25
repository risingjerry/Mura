#!/usr/bin/env python3
"""Render docs/demo.gif: HTML frames -> headless Chrome (2x) -> ffmpeg palette GIF.

Built around the real screenshot docs/images/mura-editor.png (parts of the canvas are
hidden and revealed to suggest writing). Rendered illustration only; no real wallpaper is changed.
Rebuild:  python3 docs/demo/build.py   (needs Google Chrome + ffmpeg)
"""
import html, os, pathlib, shutil, subprocess, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SHOT = (ROOT / "docs/images/mura-editor.png").as_uri()
OUT = ROOT / "docs/demo.gif"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 960, 600
K = 0.48          # screenshot "display" px (2000 wide) -> stage px
PAPER = "#fff8df"  # canvas colour sampled from the screenshot

# regions of the canvas (display px: x0,y0,x1,y1) revealed in order
HEAD = (575, 320, 1370, 415)
REGIONS = {
    "underline": (575, 415, 1370, 450),
    "l1": (600, 450, 1170, 512), "l2": (600, 512, 1170, 566), "l3": (600, 566, 1170, 626),
    "green": (1385, 490, 1690, 640), "blue": (1360, 700, 1660, 810), "orange": (530, 820, 1160, 920),
}
ORDER = ["underline", "l1", "l2", "l3", "green", "blue", "orange"]

def box(r, extra=""):
    x0, y0, x1, y1 = [v * K for v in r]
    return f"left:{x0:.1f}px;top:{y0:.1f}px;width:{x1-x0:.1f}px;height:{y1-y0:.1f}px;{extra}"

def editor(head_frac, done, ring=False, cursor=False):
    covers = []
    x0, y0, x1, y1 = HEAD
    if head_frac < 1:
        nx = x0 + (x1 - x0) * head_frac
        covers.append(f'<div class="cv" style="{box((nx, y0, x1, y1))}"></div>')
    for k in ORDER:
        if k not in done:
            covers.append(f'<div class="cv" style="{box(REGIONS[k])}"></div>')
    extra = ""
    if ring:
        extra += f'<div class="ring" style="{box((1885, 4, 2025, 50))}"></div>'
    if cursor:
        extra += f'<svg class="cur" style="left:{1960*K:.0f}px;top:{34*K:.0f}px" width="26" height="26" viewBox="0 0 24 24"><path d="M3 2l7 19 3-8 8-3z" fill="#111" stroke="#fff" stroke-width="1.5"/></svg>'
    return f'<div class="layer ed"><img src="{SHOT}"/>{"".join(covers)}{extra}</div>'

def desktop(opacity=1.0, text=False):
    t = '<div class="note">Call the dentist</div>' if text else ""
    return f'''<div class="layer dt" style="opacity:{opacity}">
<div class="wp"><img src="{SHOT}"/></div>{t}
<div class="menu"><b>Finder</b><span>File</span><span>Edit</span><span>View</span><span>Go</span><span>Window</span><span>Help</span><em>Tue 9:41 AM</em></div></div>'''

TERM = [
    ('$ dmwctl board patch --text "Call the dentist" --x 160 --y 860 --font-size 96 --json', '{"ok": true, ...}'),
    ('$ dmwctl render preview --wallpaper --json', '{"ok": true, ...}'),
    ('$ dmwctl wallpaper apply --confirm --json', '{"ok": true, ...}'),
]

def terminal(n, typed=None, outs=0, opacity=1.0):
    rows = []
    for i in range(n):
        cmd, out = TERM[i]
        c = cmd if not (i == n - 1 and typed is not None) else cmd[:typed]
        rows.append(f'<div class="cmd">{html.escape(c)}</div>')
        if i < outs:
            rows.append(f'<div class="out">{html.escape(out)}</div>')
    return f'''<div class="term" style="opacity:{opacity}"><div class="bar"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i>&nbsp; agent session (illustrative)</div>
<div class="tb"><div class="u">Put "Call the dentist" on my wallpaper.</div>{"".join(rows)}</div></div>'''

def page(layers, caption):
    cap = f'<div class="capw"><div class="cap">{html.escape(caption)}</div></div>' if caption else ""
    return f'''<!doctype html><meta charset="utf-8"><style>
*{{box-sizing:border-box;margin:0}}
body{{width:{W}px;height:{H}px;background:#111;position:relative;overflow:hidden;font-family:-apple-system,"SF Pro Text","Helvetica Neue",sans-serif}}
.layer{{position:absolute;inset:0;overflow:hidden}}
.ed img{{position:absolute;left:0;top:0;width:{W}px;height:{W*1280/2048:.0f}px}}
.cv{{position:absolute;background:{PAPER}}}
.ring{{position:absolute;border:3px solid #ff6a3d;border-radius:12px;box-shadow:0 0 0 5px rgba(255,106,61,.3)}}
.cur{{position:absolute}}
.wp{{position:absolute;inset:0;overflow:hidden;background:{PAPER}}}
.dt .wp img{{display:block;position:absolute;width:{2048*600/1006:.0f}px;left:{-(235*600/1006)-54:.0f}px;top:{-(164*600/1006):.0f}px}}
.menu{{position:absolute;left:0;right:0;top:0;height:24px;background:rgba(255,255,255,.55);backdrop-filter:blur(8px);font-size:12px;color:#222;display:flex;gap:16px;align-items:center;padding:0 14px}}
.menu em{{margin-left:auto;font-style:normal}}
.note{{position:absolute;left:35px;top:452px;font:54px/1.1 "Kaiti SC","Songti SC",serif;color:#13213c}}
.term{{position:absolute;left:110px;top:120px;width:740px;height:300px;border-radius:12px;background:#1c1d22;box-shadow:0 18px 40px rgba(0,0,0,.45);overflow:hidden;z-index:5}}
.bar{{height:30px;background:#2a2b31;display:flex;align-items:center;padding:0 12px;gap:7px;color:#9a9ca5;font-size:12px}}
.bar i{{width:11px;height:11px;border-radius:50%;display:inline-block}}
.tb{{padding:14px 16px;font:12px/1.5 Menlo,monospace;color:#e9ecf5}}
.u{{background:#34364a;border-radius:10px;padding:8px 12px;margin:0 0 12px 120px;font-family:-apple-system,sans-serif;font-size:14px;color:#fff}}
.cmd{{margin-top:6px;color:#e9ecf5}} .out{{color:#7ee0a0}}
.capw{{position:absolute;left:0;right:0;bottom:16px;display:flex;justify-content:center;z-index:9}}
.cap{{background:rgba(17,24,39,.88);color:#fff;font-size:17px;font-weight:600;padding:9px 20px;border-radius:999px}}
</style>{layers}{cap}'''

def frames():
    f = []
    ed = lambda hf, done, **k: editor(hf, done, **k)
    f.append((page(ed(0, []), "Open the canvas and write"), 0.7))
    for hf in (0.25, 0.5, 0.75, 1):
        f.append((page(ed(hf, []), "Open the canvas and write"), 0.35))
    done = []
    for k in ORDER:
        done.append(k)
        f.append((page(ed(1, list(done)), "Add a line, a list, a quick doodle"), 0.45 if k != "orange" else 1.0))
    f.append((page(ed(1, ORDER, ring=True, cursor=True), "Click “Save to desktop”"), 1.1))
    f.append((page(ed(1, ORDER, ring=True, cursor=True) + desktop(0.5), ""), 0.2))
    D = "Saved: your canvas is now the wallpaper. No editor keeps running."
    f.append((page(desktop(1), D), 2.0))
    C = "Or ask your agent: it drives dmwctl"
    f.append((page(desktop(1) + terminal(1, 0), C), 0.6))
    cmd = TERM[0][0]
    f.append((page(desktop(1) + terminal(1, len(cmd) // 2), C), 0.6))
    f.append((page(desktop(1) + terminal(1, None, 1), C), 0.8))
    f.append((page(desktop(1) + terminal(2, None, 1), C), 0.6))
    f.append((page(desktop(1) + terminal(2, None, 2), C), 0.6))
    f.append((page(desktop(1) + terminal(3, None, 2), "Applying needs --confirm: preview first, then agree"), 1.0))
    f.append((page(desktop(1) + terminal(3, None, 3), "Applying needs --confirm: preview first, then agree"), 1.0))
    f.append((page(desktop(1) + terminal(3, None, 3, 0.35), "Applying needs --confirm: preview first, then agree"), 0.25))
    f.append((page(desktop(1, text=True), "Your reminder is on the desktop"), 2.6))
    return f

def main():
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="demo-frames-"))
    try:
        lst = []
        for i, (doc, sec) in enumerate(frames()):
            h = tmp / f"f{i:02d}.html"; h.write_text(doc)
            p = tmp / f"f{i:02d}.png"
            subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                            "--force-device-scale-factor=2", f"--window-size={W},{H}",
                            "--allow-file-access-from-files", "--virtual-time-budget=500",
                            f"--screenshot={p}", h.as_uri()],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            lst += [f"file '{p}'", f"duration {sec}"]
        lst.append(lst[-2])
        (tmp / "list.txt").write_text("\n".join(lst))
        vf = f"fps=10,scale={W}:-1:flags=lanczos"
        pal = tmp / "pal.png"
        base = ["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", str(tmp / "list.txt")]
        subprocess.run(base + ["-vf", vf + ",palettegen=max_colors=128", str(pal)], check=True)
        subprocess.run(base + ["-i", str(pal), "-lavfi", vf + "[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=4",
                               "-loop", "0", str(OUT)], check=True)
        if shutil.which("gifsicle"):
            subprocess.run(["gifsicle", "-O3", "--lossy=40", "-b", str(OUT)], check=False)
        if os.environ.get("KEEP_FRAMES"):
            shutil.copytree(tmp, ROOT / "docs/demo/_frames", dirs_exist_ok=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if __name__ == "__main__":
    main()
