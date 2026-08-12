"""
Ferrule texture sheets - "faithful" take.

Reproduces the shipped ferrule look by rebuilding the structure that was reverse
engineered from resources/models/fauna/ferrule/ferrule_body.png:

  * 49-colour palette:  6 olive base tones x 8 additive brightness steps (47 after
    one collision) + one seam black + one warm scratch gold.
  * 16 px armour sub-blocks, each block picks one of the 6 tones.
  * a per-pixel brightness field quantised to 8 levels and drawn at 3 px granularity
    (nearest upscale, hard edges only).
  * a 2 px seam of the darkest colour along the top and left of every 64 px plate,
    which is what draws the plate grid across the atlas.
  * 176 warm scratch marks (702 px total) running down-left at slope ~ -2.2,
    from single-pixel flecks up to 18 px streaks. Marks never cross a seam.

Everything is nearest-neighbour / integer: no gradients, no antialiasing, no blur.
Deterministic: SEED below drives every draw.

Output: ferrule_body.png (256), ferrule_mouth.png / ferrule_signal.png /
ferrule_signal_emissive.png (64). All RGBA, alpha == 255 everywhere.
"""

import os
import numpy as np
from PIL import Image

SEED = 20260803
OUT = os.path.dirname(os.path.abspath(__file__))

# ----------------------------------------------------------------------------
# palette - lifted verbatim from the shipped atlas (49 colours, nothing invented)
# ----------------------------------------------------------------------------

RAMPS = [
    [(14, 16, 15), (15, 17, 16), (16, 18, 16), (17, 19, 17),
     (18, 20, 17), (19, 21, 17), (20, 22, 18), (21, 23, 18)],
    [(19, 21, 18), (20, 22, 18), (21, 23, 19), (22, 24, 19),
     (23, 25, 19), (24, 26, 20), (25, 27, 20), (26, 28, 21)],
    [(25, 26, 18), (26, 27, 19), (27, 28, 19), (28, 29, 20),
     (29, 30, 20), (30, 31, 21), (31, 32, 21), (32, 33, 22)],
    [(31, 30, 18), (32, 31, 19), (33, 32, 19), (34, 33, 20),
     (35, 34, 20), (36, 35, 21), (37, 36, 21), (38, 37, 22)],
    [(40, 36, 20), (41, 37, 21), (42, 38, 21), (43, 39, 22),
     (44, 40, 22), (45, 41, 23), (46, 42, 23), (47, 43, 24)],
    [(46, 40, 21), (47, 41, 22), (48, 42, 22), (49, 43, 23),
     (50, 44, 23), (51, 45, 24), (52, 46, 24), (53, 47, 25)],
]
SEAM = (10, 12, 11)
SCRATCH = (83, 68, 29)

SIZE = 256
BLOCK = 16      # armour sub-block edge
PLATE = 64      # atlas tile edge (the seam grid)
NOISE_PX = 3    # brightness field is drawn at 3 px granularity

# scratch component sizes, matching the shipped histogram exactly (176 marks / 702 px)
MARK_SIZES = ([1] * 37 + [2] * 35 + [3] * 13 + [4] * 34 + [5] * 19 + [6] * 9 +
              [7] * 11 + [8] * 6 + [9] * 4 + [11] * 1 + [12] * 2 + [13] * 2 +
              [14] * 1 + [17] * 1 + [18] * 1)

MARK_DIR = (-2.2, 1.0)   # down-left, the shipped scratch angle
MARK_STEP = 0.62         # sub-pixel walk -> ~3 px per scanline


def save_rgba(arr_rgb, path):
    """arr_rgb: HxWx3 uint8 -> opaque RGBA png, no resampling anywhere."""
    h, w, _ = arr_rgb.shape
    out = np.empty((h, w, 4), np.uint8)
    out[..., :3] = arr_rgb
    out[..., 3] = 255
    Image.fromarray(out, "RGBA").save(path)
    return out


# ----------------------------------------------------------------------------
# body atlas
# ----------------------------------------------------------------------------

def build_body(rng):
    img = np.zeros((SIZE, SIZE, 3), np.uint8)

    # 6-tone field, one tone per 16 px sub-block
    nb = SIZE // BLOCK
    tones = rng.integers(0, len(RAMPS), size=(nb, nb))

    # brightness field: 8 levels, drawn at 3 px granularity (hard nearest steps)
    nn = (SIZE + NOISE_PX - 1) // NOISE_PX
    levels = rng.integers(0, 8, size=(nn, nn))

    ramp_lut = np.array(RAMPS, np.uint8)               # 6 x 8 x 3
    idx = np.arange(SIZE)
    tone_px = tones[np.repeat(idx // BLOCK, 1)][:, idx // BLOCK]
    lvl_px = levels[idx // NOISE_PX][:, idx // NOISE_PX]
    img[:] = ramp_lut[tone_px, lvl_px]

    # warm scratches / flecks - placed before the seam so the seam stays unbroken
    taken = np.zeros((SIZE, SIZE), bool)
    seam = np.zeros((SIZE, SIZE), bool)
    seam[:, (idx % PLATE) < 2] = True
    seam[(idx % PLATE) < 2, :] = True

    sizes = MARK_SIZES[:]
    rng.shuffle(sizes)
    dx, dy = MARK_DIR
    length = (dx * dx + dy * dy) ** 0.5
    ux, uy = dx / length, dy / length

    # a coarse density field so wear clumps the way the shipped sheet does,
    # instead of dusting the atlas perfectly evenly
    dens = rng.random((8, 8)) ** 1.7
    dens /= dens.sum()
    cells = np.arange(64)

    for want in sizes:
        for _attempt in range(400):
            c = int(rng.choice(cells, p=dens.ravel()))
            x0 = float((c % 8) * 32 + rng.integers(0, 32))
            y0 = float((c // 8) * 32 + rng.integers(0, 32))
            px = []
            t = 0.0
            while len(px) < want and t < want * 4.0:
                cx = int(np.floor(x0 + ux * t)) % SIZE
                cy = int(np.floor(y0 + uy * t)) % SIZE
                if (cy, cx) not in px:
                    px.append((cy, cx))
                t += MARK_STEP
            if len(px) < want:
                continue
            if any(seam[p] or taken[p] for p in px):
                continue
            # keep marks from fusing into one blob: no 8-neighbour contact either
            clash = False
            for (cy, cx) in px:
                ys = [(cy - 1) % SIZE, cy, (cy + 1) % SIZE]
                xs = [(cx - 1) % SIZE, cx, (cx + 1) % SIZE]
                if taken[np.ix_(ys, xs)].any():
                    clash = True
                    break
            if clash:
                continue
            for p in px:
                taken[p] = True
                img[p] = SCRATCH
            break

    # 2 px plate seam, top + left of every 64 px tile (wraps, so it tiles)
    img[seam] = SEAM
    return img


# ----------------------------------------------------------------------------
# mouth void - 8 near-black values, per-pixel dust, faintly warm.
# The shipped void is not pure noise: a dark speckled base carries three barely
# visible concentric rings of the lighter values (a pupil dot at the centre, a
# ring near r=17 and one near r=34), which is what keeps it from reading flat.
# ----------------------------------------------------------------------------

MOUTH_DARK = ([4] * 779 + [5] * 822 + [6] * 1064 + [7] * 978)
MOUTH_LIGHT = ([9] * 117 + [10] * 106 + [11] * 136 + [12] * 94)
MOUTH_RINGS = ((0.0, 1.6), (17.4, 2.0), (34.3, 1.2))   # (radius, half width)


def build_mouth(rng):
    yy, xx = np.mgrid[0:64, 0:64]
    rad = np.sqrt((xx - 31.5) ** 2 + (yy - 31.5) ** 2)

    ring = np.zeros((64, 64), bool)
    for r0, w in MOUTH_RINGS:
        ring |= np.abs(rad - r0) <= w
    # ragged, pixel-art ring edges: drop ~30% of ring pixels back to the base
    ring &= rng.random((64, 64)) > 0.40

    dark = np.array(MOUTH_DARK)
    light = np.array(MOUTH_LIGHT)
    v = rng.choice(dark, size=(64, 64))
    v[ring] = rng.choice(light, size=int(ring.sum()))
    v = v.astype(np.uint8)
    return np.stack([v + 1, v, v], axis=-1).astype(np.uint8)   # R highest -> warm


# ----------------------------------------------------------------------------
# signal albedo - lime fluorescence, hard-stepped diagonal banding
# ----------------------------------------------------------------------------

def build_signal(rng):
    """Broad diagonal sweep (like the shipped sheet) + a 7 px diagonal sawtooth,
    both quantised to hard steps. No smooth ramp anywhere."""
    y, x = np.mgrid[0:64, 0:64]
    d = x + y                                        # 0..126, diagonal

    tri = 1.0 - np.abs(d - 63.0) / 63.0              # broad triangle 0..1
    broad = np.floor(tri * 5.999).astype(int)        # 6 hard bands

    saw = d % 7                                      # the fine diagonal banding
    fine = (saw >= 3).astype(int) + (saw >= 5).astype(int)

    # sparse single-step dither keeps the bands from reading as vector shapes
    dither = (rng.random((64, 64)) < 0.06).astype(int)
    step = np.clip(broad + fine + dither, 0, 7)

    # Envelope taken from the shipped sheet (R 135..220, G 188..245, B 8..23) so
    # the lime stays acid; a higher blue reads pastel and loses the fluorescence.
    r = (138 + step * 8).astype(np.uint8)            # 138..194
    g = (188 + step * 6).astype(np.uint8)            # 188..230
    b = (12 + step * 2).astype(np.uint8)             # 12..26
    return np.stack([r, g, b], axis=-1)


# ----------------------------------------------------------------------------
# signal emissive - mostly bright, hard striations, no smooth falloff
# ----------------------------------------------------------------------------

def build_emissive(rng):
    """Mostly bright: a stepped glow core (no smooth falloff) cut by darker
    diagonal striations, so the mask drives an uneven, vent-like glow."""
    y, x = np.mgrid[0:64, 0:64]
    rad = np.sqrt((x - 31.5) ** 2 + (y - 31.5) ** 2) / 42.0
    core = np.clip(1.0 - rad, 0.0, 1.0)
    core_step = np.floor(core * 5.0).astype(int) + 2        # 2..6, never dead

    stri = (x * 2 + y) % 11                                 # diagonal striations
    dark = (stri < 3).astype(int) + (stri < 1).astype(int)
    speck = (rng.random((64, 64)) < 0.06).astype(int)

    step = np.clip(core_step - dark - speck, 0, 6)

    # a few deeper vent lines, still lime-family so the mask stays "mostly bright"
    for _ in range(6):
        sx = int(rng.integers(0, 64))
        sy = int(rng.integers(0, 64))
        for t in range(int(rng.integers(8, 22))):
            px = int(sx - 2.2 * t * 0.45) % 64
            py = int(sy + t * 0.45) % 64
            step[py, px] = max(0, step[py, px] - 2)

    r = (86 + step * 12).astype(np.uint8)                   # 86..158
    g = (158 + step * 15).astype(np.uint8)                  # 158..248
    b = (3 + step).astype(np.uint8)                         # 3..9
    return np.stack([r, g, b], axis=-1)


def main():
    rng = np.random.default_rng(SEED)
    body = build_body(rng)
    save_rgba(body, os.path.join(OUT, "ferrule_body.png"))
    save_rgba(build_mouth(rng), os.path.join(OUT, "ferrule_mouth.png"))
    save_rgba(build_signal(rng), os.path.join(OUT, "ferrule_signal.png"))
    save_rgba(build_emissive(rng), os.path.join(OUT, "ferrule_signal_emissive.png"))

    # --- report -------------------------------------------------------------
    import collections
    cols = collections.Counter(map(tuple, body.reshape(-1, 3)))
    print("body distinct colours:", len(cols))
    print("body mean:", body.reshape(-1, 3).mean(0).round(2))
    print("seam px:", cols[SEAM], " scratch px:", cols[SCRATCH])
    for name in ("ferrule_body.png", "ferrule_mouth.png", "ferrule_signal.png",
                 "ferrule_signal_emissive.png"):
        a = np.array(Image.open(os.path.join(OUT, name)))
        print(name, a.shape, "alpha min", a[..., 3].min(),
              "colours", len(set(map(tuple, a.reshape(-1, 4)))))


if __name__ == "__main__":
    main()
