"""Paint the Ferrule v3 sheets onto its unwrapped UV islands.

Reads uv_manifest.json (face UV polygons + world normal/height) and paints each
face as its own flat facet tone - the concept's grammar of individually-read
facets - instead of tiling a level atlas across the body.

Shading model per face:
  - base olive ramp indexed by world height (darker low, lighter high)
  - lit from above: normal z tips the tone up or down two steps
  - deterministic per-face jitter so neighbouring facets never merge
  - 1px darker seam drawn on every face edge (the painted plate-seam read)
  - rust flecks biased to low, downward faces; sparse pale scratches high up
"""
import json
import os
import numpy as np
from PIL import Image, ImageDraw

SEED = 20260803
OUT = ("c:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/"
       "resources/models/fauna/ferrule_v3")
BODY_RES = 512
SIGNAL_RES = 128

STONE = [
    (16, 15, 10), (22, 20, 13), (28, 26, 16), (34, 31, 19),
    (41, 37, 22), (48, 44, 26), (56, 51, 30), (64, 58, 34),
    (74, 67, 40), (84, 76, 46),
]
SEAM = (8, 8, 6)
RUST = [(84, 58, 26), (102, 70, 30), (122, 84, 36)]
SCRATCH = [(96, 90, 64), (116, 108, 78)]
LIME = [(126, 176, 44), (146, 196, 52), (166, 212, 62), (182, 224, 74)]
GLOW = [(120, 160, 40), (170, 214, 60), (206, 240, 96), (232, 252, 140)]

rng = np.random.default_rng(SEED)
man = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                  "uv_manifest.json")))
z0, z1 = man["z_range"]


def face_tone(f):
    h = (f["wz"] - z0) / (z1 - z0 + 1e-9)
    idx = 2.0 + 4.5 * h                    # height ramp
    idx += 2.2 * max(0.0, f["nz"])         # lit from above
    idx -= 1.8 * max(0.0, -f["nz"])        # undersides read dark
    idx += rng.uniform(-1.2, 1.2)          # facet-to-facet variation
    return STONE[int(np.clip(round(idx), 0, len(STONE) - 1))]


def px(uv, res):
    return [(u * res, (1.0 - v) * res) for u, v in uv]


def paint_body():
    im = Image.new("RGB", (BODY_RES, BODY_RES), SEAM)
    d = ImageDraw.Draw(im)
    faces = man["body"]
    for f in faces:
        poly = px(f["uv"], BODY_RES)
        d.polygon(poly, fill=face_tone(f))
    # Seams only on island borders: an edge used by exactly one face of an
    # island is a boundary. Outlining every face reads as wireframe instead.
    from collections import Counter
    edges = Counter()
    for f in faces:
        poly = f["uv"]
        for i in range(len(poly)):
            a = (round(poly[i][0], 4), round(poly[i][1], 4))
            bpt = (round(poly[(i + 1) % len(poly)][0], 4),
                   round(poly[(i + 1) % len(poly)][1], 4))
            edges[(f["island"], min(a, bpt), max(a, bpt))] += 1
    for (isl, a, bpt), count in edges.items():
        if count == 1:
            d.line([(a[0] * BODY_RES, (1 - a[1]) * BODY_RES),
                    (bpt[0] * BODY_RES, (1 - bpt[1]) * BODY_RES)],
                   fill=SEAM, width=2)

    a = np.asarray(im).astype(int)

    # pixel grain: +-1 step ordered noise, quantised back to the ramp family
    grain = rng.integers(-3, 4, size=(BODY_RES, BODY_RES, 1))
    a = np.clip(a + grain, 0, 255)

    im = Image.fromarray(a.astype(np.uint8))
    d = ImageDraw.Draw(im)

    # rust flecks: biased toward low faces
    lows = [f for f in man["body"] if (f["wz"] - z0) / (z1 - z0 + 1e-9) < 0.45]
    for _ in range(110):
        f = lows[int(rng.integers(0, len(lows)))]
        poly = f["uv"]
        cx = sum(p[0] for p in poly) / len(poly)
        cy = sum(p[1] for p in poly) / len(poly)
        u = cx + rng.uniform(-0.010, 0.010)
        v = cy + rng.uniform(-0.010, 0.010)
        x = int(np.clip(u * BODY_RES, 0, BODY_RES - 2))
        y = int(np.clip((1 - v) * BODY_RES, 0, BODY_RES - 2))
        c = RUST[int(rng.integers(0, len(RUST)))]
        d.rectangle([x, y, x + 1, y + 1], fill=c)

    # pale scratches on high, upward faces
    highs = [f for f in man["body"]
             if (f["wz"] - z0) / (z1 - z0 + 1e-9) > 0.55 and f["nz"] > 0.2]
    for _ in range(28):
        f = highs[int(rng.integers(0, len(highs)))]
        poly = f["uv"]
        cx = sum(p[0] for p in poly) / len(poly)
        cy = sum(p[1] for p in poly) / len(poly)
        x, y = cx * BODY_RES, (1 - cy) * BODY_RES
        ln = int(rng.integers(3, 9))
        sx = 1 if rng.random() < 0.5 else -1
        c = SCRATCH[int(rng.integers(0, len(SCRATCH)))]
        for i in range(ln):
            d.point((x + sx * i, y + i), fill=c)

    im.convert("RGBA").save(f"{OUT}/ferrule_body.png")


def paint_signal():
    im = Image.new("RGB", (SIGNAL_RES, SIGNAL_RES), LIME[0])
    d = ImageDraw.Draw(im)
    for f in man["signal"]:
        poly = px(f["uv"], SIGNAL_RES)
        idx = int(np.clip(round(1.5 + 1.6 * f["nz"] + rng.uniform(-0.8, 0.8)),
                          0, len(LIME) - 1))
        d.polygon(poly, fill=LIME[idx])

    a = np.asarray(im).astype(int)
    gx, gy = np.meshgrid(np.arange(SIGNAL_RES), np.arange(SIGNAL_RES))
    band = (((gx + gy) // 5) % 2) * 6 - 3
    a = np.clip(a + band[..., None], 0, 255)
    Image.fromarray(a.astype(np.uint8)).convert("RGBA").save(
        f"{OUT}/ferrule_signal.png")

    em = Image.new("RGB", (SIGNAL_RES, SIGNAL_RES), GLOW[1])
    d = ImageDraw.Draw(em)
    for f in man["signal"]:
        poly = px(f["uv"], SIGNAL_RES)
        idx = int(np.clip(round(2.0 + 1.2 * f["nz"]), 0, len(GLOW) - 1))
        d.polygon(poly, fill=GLOW[idx])
    a = np.asarray(em).astype(int)
    band2 = (((gx * 2 + gy) // 4) % 2) * 14 - 7
    a = np.clip(a + band2[..., None], 0, 255)
    Image.fromarray(a.astype(np.uint8)).convert("RGBA").save(
        f"{OUT}/ferrule_signal_emissive.png")


def paint_mouth():
    m = 64
    rng2 = np.random.default_rng(SEED + 1)
    a = np.zeros((m, m, 3), dtype=np.uint8)
    a[:, :] = (13, 11, 8)
    blocks = rng2.integers(0, 3, size=(m // 4, m // 4))
    a += (np.kron(blocks, np.ones((4, 4), dtype=int))[..., None] * 3).astype(np.uint8)
    for _ in range(50):
        x, y = rng2.integers(0, m, 2)
        a[y, x] = (25, 21, 15)
    Image.fromarray(a, "RGB").convert("RGBA").save(f"{OUT}/ferrule_mouth.png")


paint_body()
paint_signal()
paint_mouth()
for n in ("ferrule_body", "ferrule_signal", "ferrule_signal_emissive", "ferrule_mouth"):
    im = Image.open(f"{OUT}/{n}.png")
    print(n, im.size, im.mode, "colours:", len(im.convert("RGB").getcolors(999999)))
