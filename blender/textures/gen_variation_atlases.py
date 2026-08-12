"""Per-surface VARIATION ATLASES for structural tiling (the Aster-floor technique).

Each atlas is an N x N grid of 32 px cells. Every cell is painted by the shared
gen_tiles painter for that surface with its own deterministic seed (structural
variety per metre), then the whole atlas is modulated by a PERIODIC two-octave
Perlin field — brightness drifts in patches spanning 2-4 metres, with wear specks
concentrating where the field runs low — quantized through the 4x4 Bayer matrix
in fixed palette steps so the result stays pixel-art rather than smooth gradient.

Mapped world-aligned at 1 m = 1 cell (Closest + REPEAT wraps every N metres), a
surface shows a different tile on every metre and the wear reads as handmade
patchiness instead of one tile stamped per metre. The field's lattice indices
wrap at the atlas period, so the REPEAT seam is exactly continuous.

Deterministic: every seed derives from zlib.crc32 (never Python's per-process
randomized hash()), so a rebuild reproduces the identical atlases.

Run:  py gen_variation_atlases.py   (writes blender/textures/atlases/<stem>_var8.png
      + 4x previews to C:/tmp/var_atlas_<stem>.png)
"""
from PIL import Image
import math, os, random, sys, zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_tiles import (T, BAYER, sh, m_rock, m_metal, m_grate, m_rust, m_deck, m_panel,
                       d_deck, d_panel)

N = 8                              # cells per atlas side; atlas wraps every N metres
STEMS = {"deck_metal": m_deck, "grate": m_grate, "wall_panel": m_panel,
         "facility_metal": m_metal, "rust_iron": m_rust, "rock": m_rock}
# wear-speck density per stem where the field runs low (grate stays crisp: its bar
# grid must read continuously across cells, brightness drift alone carries it)
WEAR = {"deck_metal": 0.22, "wall_panel": 0.22, "facility_metal": 0.22,
        "rust_iron": 0.55, "rock": 0.45, "grate": 0.0}
# Blotchy organic painters cover the WHOLE canvas in one pass (features wrap at the
# atlas border, flowing across metre cells — per-cell painting clips them straight
# at every cell edge). Structural painters stay per-cell: their features are grid-
# periodic, so cells align seamlessly by construction.
ATLAS_PAINTED = {"rust_iron", "rock"}
# Per-cell distress at the painter's own contrast scale, for stems whose per-cell
# output is (near-)identical — m_deck/m_panel use no rng at all, m_metal only faint
# streak specks. Without it every metre renders as the same stamped tile.
DISTRESS = {"deck_metal": d_deck, "wall_panel": d_panel, "facility_metal": None}
STEP = 0.035                       # one palette step of brightness (dither quantum) — calmed: the 0.06 speckle read as NOISE at gameplay distance (director)
AMP = 0.085                        # peak brightness swing from the field — calmed with STEP


def _seed(*parts):
    return zlib.crc32(":".join(str(p) for p in parts).encode()) & 0xffffffff


# ---- periodic gradient Perlin: lattice indices wrap at `period`, so the field tiles ----
_grad_cache = {}

def _grad(ix, iy, period, seed):
    key = (ix % period, iy % period, seed)
    got = _grad_cache.get(key)
    if got is None:
        a = _seed(seed, key[0], key[1]) * (math.tau / 4294967296.0)
        got = (math.cos(a), math.sin(a))
        _grad_cache[key] = got
    return got

def _fade(t):
    return t * t * t * (t * (t * 6 - 15) + 10)

def pnoise(u, v, period, seed):
    x0, y0 = math.floor(u), math.floor(v)
    fx, fy = u - x0, v - y0
    total = 0.0
    for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
        gx, gy = _grad(x0 + dx, y0 + dy, period, seed)
        wx = _fade(fx) if dx else 1.0 - _fade(fx)
        wy = _fade(fy) if dy else 1.0 - _fade(fy)
        total += wx * wy * (gx * (fx - dx) + gy * (fy - dy))
    return total                   # roughly [-0.7, 0.7]

def field(stem, x, y):
    """Two octaves in cell units at pixel (x, y): coarse ~4 m patches + ~2 m detail."""
    u, v = (x + 0.5) / T, (y + 0.5) / T
    return (pnoise(u / 4.0, v / 4.0, N // 4, _seed(stem, "coarse"))
            + 0.5 * pnoise(u / 2.0, v / 2.0, N // 2, _seed(stem, "fine")))


def dither_field(stem, x, y):
    """0 = render the wear SMOOTH (continuous gradient), 1 = render it fully
    Bayer-DITHERED (crisp pixel-art steps). A broad periodic Perlin field, so the
    surface drifts organically between smooth patches and dithered patches instead
    of being uniformly dithered — the director's smooth/dithered-blend idea."""
    u, v = (x + 0.5) / T, (y + 0.5) / T
    d = pnoise(u / 4.0, v / 4.0, N // 4, _seed(stem, "dither"))
    return max(0.0, min(1.0, 0.5 + d * 1.6))


def distress(px, rng):
    """Per-cell handmade wear on an otherwise pixel-identical painter output:
    a shallow dent blob, a couple of scratches, maybe an edge stain."""
    if rng.random() < 0.4:                                     # dent: dimmed blob
        cx, cy = rng.randrange(4, T - 4), rng.randrange(4, T - 4)
        r = rng.randint(2, 4)
        for y in range(-r, r + 1):
            for x in range(-r, r + 1):
                if x * x + y * y <= r * r:
                    px[cx + x, cy + y] = sh(px[cx + x, cy + y], 0.86)
    for _ in range(rng.randint(0, 2)):                          # scratches
        x, y = rng.randint(3, T - 8), rng.randint(3, T - 8)
        dx, dy = rng.choice([(1, 0), (0, 1), (1, 1), (1, -1)])
        f = rng.choice([0.72, 1.25])
        for i in range(rng.randint(3, 6)):
            xx, yy = x + dx * i, y + dy * i
            if 0 <= xx < T and 0 <= yy < T:
                px[xx, yy] = sh(px[xx, yy], f)
    if rng.random() < 0.3:                                      # stain creeping from one edge
        side = rng.randrange(4)
        span0, span1 = rng.randint(4, 12), rng.randint(18, 27)
        depth = rng.randint(2, 4)
        for s in range(span0, span1):
            for d in range(depth):
                x, y = (s, d) if side == 0 else (s, T - 1 - d) if side == 1 \
                    else (d, s) if side == 2 else (T - 1 - d, s)
                px[x, y] = sh(px[x, y], 0.9 - 0.02 * (depth - d))


def build_atlas(stem, painter):
    atlas = Image.new("RGBA", (N * T, N * T), (0, 0, 0, 255))
    if stem in ATLAS_PAINTED:
        painter(atlas.load(), random.Random(_seed(stem, "atlas")), N * T)
    else:
        for cy in range(N):
            for cx in range(N):
                tile = Image.new("RGBA", (T, T), (0, 0, 0, 255))
                rng = random.Random(_seed(stem, cx, cy))
                painter(tile.load(), rng)
                if stem in DISTRESS:
                    specific = DISTRESS[stem]
                    (specific or distress)(tile.load(), rng)
                atlas.paste(tile, (cx * T, cy * T))
    px = atlas.load()
    wear = WEAR[stem]
    for y in range(N * T):
        for x in range(N * T):
            n = field(stem, x, y)
            # Two renderings of the same wear drift, blended by a Perlin mask:
            #   SMOOTH    — the raw continuous brightness factor.
            #   DITHERED  — the drift quantized to palette steps, Bayer-dithered.
            # Where the mask is high the surface reads as crisp pixel-art steps;
            # where low it reads as a smooth gradient; the Perlin field drifts
            # organically between the two.
            f_smooth = 1.0 + AMP * n
            k = AMP * n / STEP
            kbase = math.floor(k)
            kk = kbase + (1 if ((k - kbase) * 16.0) > BAYER[y % 4][x % 4] else 0)
            f_dither = 1.0 + STEP * kk
            mask = dither_field(stem, x, y)
            f = f_smooth + (f_dither - f_smooth) * mask
            if abs(f - 1.0) > 1e-4:
                px[x, y] = sh(px[x, y], f)
            if wear > 0.0:
                r = (_seed(stem, "wear", x, y) % 1000) / 1000.0
                if n < -0.35 and r < min(0.25, (-n - 0.35) * wear):
                    px[x, y] = sh(px[x, y], 0.68)          # worn/dirty pocket
                elif n > 0.35 and r < min(0.12, (n - 0.35) * wear * 0.5):
                    px[x, y] = sh(px[x, y], 1.22)          # fresh scuff/scratch
    return atlas


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.join(here, "atlases")
    # the runtime copy: _tinted_tile_material / _tile_material sample these for
    # per-metre variety on runtime-tiled surfaces (the single-tile leopard fix)
    game_dir = os.path.normpath(os.path.join(
        here, "..", "..", "to-rust-as-we-fall", "resources", "textures", "atlases"))
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(game_dir, exist_ok=True)
    for stem, painter in STEMS.items():
        atlas = build_atlas(stem, painter)
        name = "%s_var%d.png" % (stem, N)
        atlas.save(os.path.join(out_dir, name))
        atlas.save(os.path.join(game_dir, name))
        atlas.resize((N * T * 4, N * T * 4), Image.NEAREST).save(
            "C:/tmp/var_atlas_%s.png" % stem)
        print("wrote", name)
