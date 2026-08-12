"""Assemble rendered PNG frame sequences into animated WebP loops.

Run with SYSTEM python (PIL). Reads the same anim_config.json render_anim.py
consumed, so the two stages can't drift: for each action it collects
<out>/<short>_*.png in frame order, writes vid_<prefix>_<short>.webp beside
this script, and MOTION-GUARDS the loop (first vs mid frame pixel diff) - a
static "animation" shipped once because nothing checked the frames moved.

Usage: python assemble_webp.py <prefix>          (e.g. sap, fer)
"""
import glob
import json
import os
import sys

from PIL import Image, ImageChops

SCRATCH = os.path.dirname(os.path.abspath(__file__))
CFG = json.load(open(os.path.join(SCRATCH, "anim_config.json")))
PREFIX = sys.argv[1] if len(sys.argv) > 1 else "sap"
FPS = CFG.get("fps", 24)

made = []
for act in CFG["actions"]:
    short = act["short"]
    frames = sorted(glob.glob(os.path.join(CFG["out"], "%s_*.png" % short)))
    if len(frames) < 2:
        raise SystemExit("%s: only %d frames rendered" % (short, len(frames)))
    imgs = [Image.open(f).convert("RGBA") for f in frames]

    # motion guard: the loop must actually MOVE
    diff = ImageChops.difference(imgs[0], imgs[len(imgs) // 2]).getbbox()
    moved = 0
    if diff:
        d = ImageChops.difference(imgs[0], imgs[len(imgs) // 2]).convert("L")
        moved = sum(1 for p in d.getdata() if p > 8)
    if moved < 2000:
        raise SystemExit("%s: loop is STATIC (%d changed px)" % (short, moved))

    step = act.get("step", 1)
    dur = int(round(1000.0 / FPS * step))
    out = os.path.join(SCRATCH, "vid_%s_%s.webp" % (PREFIX, short))
    imgs[0].save(out, save_all=True, append_images=imgs[1:], duration=dur,
                 loop=0, lossless=False, quality=85, method=4, exact=True)
    # exact=True keeps clean RGB under transparent pixels - without it the
    # encoder stores grey DCT garbage there, invisible in playback but a
    # phantom "edge streak" to any alpha-blind audit
    made.append({"short": short, "frames": len(imgs), "moved_px": moved,
                 "kb": round(os.path.getsize(out) / 1024.0, 1)})

print(json.dumps(made, indent=1))
