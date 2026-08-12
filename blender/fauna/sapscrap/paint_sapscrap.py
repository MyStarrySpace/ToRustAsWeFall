"""Paint the Sapscrap sheets through its UV manifest.

The turnaround's read: a plum-purple micro-mosaic shell with ochre staining,
pale bone claws/teeth, near-black gullet. Per-face flat tones follow anatomy
(lit crowns, dark underside), a mosaic grain rides on top, and the ochre
blotches cluster on the upper flanks the way the paintings stain them.
"""
import json
import os
import numpy as np
from PIL import Image, ImageDraw

SEED = 20260804
OUT = ("c:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/"
       "resources/models/fauna/sapscrap")
SHELL_RES = 512
CLAW_RES = 256

PLUM = [
    (52, 30, 42), (64, 37, 52), (76, 44, 61), (88, 51, 70),
    (101, 59, 80), (114, 68, 90), (128, 78, 101), (141, 89, 111),
    (155, 101, 122), (168, 114, 133),
]
OCHRE = [(142, 100, 44), (160, 116, 52), (176, 130, 60)]
SEAM = (30, 16, 24)
BONE = [(120, 110, 96), (140, 130, 114), (158, 148, 131), (176, 166, 148),
        (194, 184, 166), (210, 200, 182)]
BONE_SEAM = (86, 78, 66)

rng = np.random.default_rng(SEED)
man = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                  "uv_manifest_sap.json")))
z0, z1 = man["z_range"]


def px(uv, res):
    return [(u * res, (1.0 - v) * res) for u, v in uv]


def border_lines(faces, res, draw, seam, width=2, crease_deg=35.0):
    """Seams on CREASES, not on UV islands.

    This drew a dark rim along every island boundary, and smart_project's islands
    are packing accidents — their borders land mid-facet, so the shell wore 42
    stitched patches in arbitrary places (the director's "why does it look like
    it's made of patchwork"). A seam is form language: it belongs where two faces
    meet at a real angle, and on true mesh boundaries (the maw rim), never where
    the unwrapper happened to cut.
    """
    import math
    thresh = math.cos(math.radians(crease_deg))
    edges = {}
    for fi, f in enumerate(faces):
        vids = f.get("vid")
        if not vids:                      # old manifest: fall back to island rims
            vids = list(range(len(f["uv"])))
        for i in range(len(vids)):
            key = (f["object"], min(vids[i], vids[(i + 1) % len(vids)]),
                   max(vids[i], vids[(i + 1) % len(vids)]))
            edges.setdefault(key, []).append((fi, i))
    for key, owners in edges.items():
        crease = len(owners) == 1        # a true boundary edge always draws
        if len(owners) == 2:
            n1 = faces[owners[0][0]].get("n"); n2 = faces[owners[1][0]].get("n")
            if n1 and n2:
                dot = sum(a * b for a, b in zip(n1, n2))
                crease = dot < thresh
        if not crease:
            continue
        for fi, i in owners:             # draw in EACH owner's own UV space, so
            poly = faces[fi]["uv"]        # the line lands on both sides of a cut
            a, b = poly[i], poly[(i + 1) % len(poly)]
            draw.line([(a[0] * res, (1 - a[1]) * res),
                       (b[0] * res, (1 - b[1]) * res)], fill=seam, width=width)


def paint_shell():
    im = Image.new("RGB", (SHELL_RES, SHELL_RES), SEAM)
    d = ImageDraw.Draw(im)
    faces = man["body"]
    for f in faces:
        h = (f["wz"] - z0) / (z1 - z0 + 1e-9)
        idx = 2.2 + 4.2 * h + 2.0 * max(0.0, f["nz"]) - 1.6 * max(0.0, -f["nz"])
        idx += rng.uniform(-1.1, 1.1)
        d.polygon(px(f["uv"], SHELL_RES),
                  fill=PLUM[int(np.clip(round(idx), 0, len(PLUM) - 1))])
    border_lines(faces, SHELL_RES, d, SEAM)

    a = np.asarray(im).astype(int)
    # micro-mosaic: 4px tile grid, +-1 tone, the turnaround's knitted look
    tile = rng.integers(-6, 7, size=(SHELL_RES // 4, SHELL_RES // 4, 1))
    a = np.clip(a + np.kron(tile, np.ones((4, 4, 1), dtype=int)), 0, 255)
    im = Image.fromarray(a.astype(np.uint8))
    d = ImageDraw.Draw(im)

    # ochre staining on high, upward faces - blotches, not flecks
    highs = [f for f in faces
             if (f["wz"] - z0) / (z1 - z0 + 1e-9) > 0.45 and f["nz"] > -0.2]
    for _ in range(60):
        f = highs[int(rng.integers(0, len(highs)))]
        poly = f["uv"]
        cx = sum(q[0] for q in poly) / len(poly) + rng.uniform(-0.012, 0.012)
        cy = sum(q[1] for q in poly) / len(poly) + rng.uniform(-0.012, 0.012)
        x, y = cx * SHELL_RES, (1 - cy) * SHELL_RES
        c = OCHRE[int(rng.integers(0, len(OCHRE)))]
        w = int(rng.integers(3, 9))
        hgt = int(rng.integers(3, 9))
        for dy in range(hgt):
            for dx in range(w):
                if rng.random() < 0.62:
                    xi, yi = int(x + dx - w / 2), int(y + dy - hgt / 2)
                    if 0 <= xi < SHELL_RES and 0 <= yi < SHELL_RES:
                        im.putpixel((xi, yi), c)
    im.convert("RGBA").save(f"{OUT}/sapscrap_shell.png")


def paint_claw():
    im = Image.new("RGB", (CLAW_RES, CLAW_RES), BONE_SEAM)
    d = ImageDraw.Draw(im)
    faces = man["signal"]
    for f in faces:
        h = (f["wz"] - z0) / (z1 - z0 + 1e-9)
        idx = 1.6 + 2.2 * h + 1.6 * max(0.0, f["nz"]) + rng.uniform(-0.8, 0.8)
        d.polygon(px(f["uv"], CLAW_RES),
                  fill=BONE[int(np.clip(round(idx), 0, len(BONE) - 1))])
    border_lines(faces, CLAW_RES, d, BONE_SEAM, width=1)
    a = np.asarray(im).astype(int)
    tile = rng.integers(-5, 6, size=(CLAW_RES // 4, CLAW_RES // 4, 1))
    a = np.clip(a + np.kron(tile, np.ones((4, 4, 1), dtype=int)), 0, 255)
    Image.fromarray(a.astype(np.uint8)).convert("RGBA").save(
        f"{OUT}/sapscrap_claw.png")


def paint_mouth():
    m = 64
    rng2 = np.random.default_rng(SEED + 1)
    a = np.full((m, m, 3), (16, 11, 14), dtype=np.uint8)
    blocks = rng2.integers(0, 3, size=(m // 4, m // 4))
    a = np.clip(a.astype(int) + np.kron(blocks, np.ones((4, 4), dtype=int))[..., None] * 3,
                0, 255).astype(np.uint8)
    Image.fromarray(a, "RGB").convert("RGBA").save(f"{OUT}/sapscrap_mouth.png")


paint_shell()
paint_claw()
paint_mouth()
for n in ("sapscrap_shell", "sapscrap_claw", "sapscrap_mouth"):
    im = Image.open(f"{OUT}/{n}.png")
    print(n, im.size, "colours:", len(im.convert("RGB").getcolors(999999)))
