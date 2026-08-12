"""ORGANIC VASCULATURE overlay — the vein-tendrils that overgrow the channels iron.

Director's method (docs/CHANNELS_CONCEPT.md plate C): draw the organic detail as
TEXTURE via a Voronoi-inspired method. The Voronoi/Worley CELL EDGES form a branching
vein network naturally: for each pixel take the two nearest seed distances F1, F2 —
the cell boundary is where (F2 - F1) is small, i.e. equidistant from two seeds. Ridge
those boundaries into thickened veins, thicker near junctions, and drop bioluminescent
NODES (blue/purple) at some seeds — the mushroom/crystal clusters.

Output (TILEABLE — seeds wrap on a torus so the overlay tiles on the walls/drum):
- vasculature_albedo.png  RGBA — dark red-brown veins, alpha = vein coverage (0 off
  the veins), so it composites OVER the iron as a detail albedo layer.
- vasculature_emissive.png RGB — the glowing junction clusters (blue/purple), black
  elsewhere; feeds an emission layer so the clusters self-light.

Deterministic (crc32 seeds). Run:  py gen_vasculature.py
"""
from PIL import Image
import math, os, zlib, json
import numpy as np

T = 256                      # texture size (px)
DENSITY = 8                  # ~cells across the tile (vein network coarseness)
VEIN_W = 0.044               # cell-edge band half-width (thicker = fatter veins)
NODE_FRAC = 0.0                  # cluster glow now lives in the 3D BiolumeCluster PROPS —
WARP = 0.075                 # domain-warp amount — bends the straight cell edges into
                             # branching organic tendrils (integer freqs keep it tiling)

# Colors come from the palette authority (data/palettes/level_palettes.json,
# channels row) — the trunks, the wall overlay, and the cluster props all read
# as ONE organism because they share the same roles. Never hard-code an rgb.
_PAL = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                                   "to-rust-as-we-fall", "data", "palettes",
                                   "level_palettes.json"), encoding="utf-8"))
def _role(level, role):
    h = _PAL[level][role].lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])

VEIN_DARK = _role("channels", "vein_bark") * 0.82    # deep vein red-brown
VEIN_LIT = _role("channels", "vein_ridge")           # lit crest of a vein
NODE_BLUE = _role("channels", "biolume_blue")        # bioluminescent cluster (blue)
NODE_VIOLET = _role("channels", "biolume_violet")    # bioluminescent cluster (violet)


def _rng(*parts):
    return np.random.RandomState(zlib.crc32(":".join(map(str, parts)).encode()) & 0x7fffffff)


def _seeds(n, tag):
    r = _rng(tag, n)
    pts = r.rand(n, 2)                                   # in [0,1)
    node = r.rand(n) < NODE_FRAC
    violet = r.rand(n) < 0.4
    return pts, node, violet


def build():
    n = DENSITY * DENSITY
    pts, is_node, is_violet = _seeds(n, "vasc")
    # pixel grid coords in [0,1)
    ys, xs = np.mgrid[0:T, 0:T].astype(np.float32) / T
    px0 = np.stack([xs, ys], axis=-1)                    # (T,T,2) UNWARPED (round nodes)
    px = px0.copy()
    # DOMAIN WARP: perturb the sampling coords with a few tiling sine octaves so the
    # Voronoi boundaries bend and branch like real tendrils instead of straight edges.
    tau = math.tau
    wx = (WARP * np.sin(tau * (2 * ys + xs)) + 0.5 * WARP * np.sin(tau * (3 * xs - ys))
          + 0.25 * WARP * np.sin(tau * (5 * ys)))
    wy = (WARP * np.cos(tau * (2 * xs + ys)) + 0.5 * WARP * np.cos(tau * (3 * ys - xs))
          + 0.25 * WARP * np.cos(tau * (5 * xs)))
    px = px + np.stack([wx, wy], axis=-1).astype(np.float32)

    # F1/F2 over a TILING torus: replicate seeds in the 8 neighbours, keep the two
    # smallest distances per pixel — the cell boundary is where they tie. On finding a
    # new nearest, the old nearest becomes the runner-up (so F2 stays correct).
    f1 = np.full((T, T), 9.0, np.float32)
    f2 = np.full((T, T), 9.0, np.float32)
    for i in range(n):
        for ox in (-1.0, 0.0, 1.0):
            for oy in (-1.0, 0.0, 1.0):
                d = px - np.array([pts[i, 0] + ox, pts[i, 1] + oy], np.float32)
                dist = np.sqrt(d[..., 0] ** 2 + d[..., 1] ** 2)
                closer1 = dist < f1
                f2 = np.where(closer1, f1, np.minimum(f2, dist))
                f1 = np.where(closer1, dist, f1)

    edge = f2 - f1                                        # 0 on the cell boundary
    # thickness swells toward junctions (where 3 cells meet, edge stays small over a
    # wider area) — a soft ridge with a slightly organic wobble from a sine of F1.
    wobble = VEIN_W * (1.0 + 0.35 * np.sin(f1 * 40.0))
    vein = np.clip(1.0 - edge / wobble, 0.0, 1.0)        # 1 on the vein, 0 off
    vein = vein ** 1.6                                    # sharpen the vein core

    # albedo: dark vein body, lit crest toward the core; alpha = vein coverage
    crest = vein ** 2.5
    col = VEIN_DARK[None, None, :] * (1.0 - crest[..., None]) + VEIN_LIT[None, None, :] * crest[..., None]
    alb = np.zeros((T, T, 4), np.float32)
    alb[..., :3] = col
    alb[..., 3] = vein * 0.92

    # emissive: glowing clusters at node seeds — a soft blob at each, blue or violet.
    emi = np.zeros((T, T, 3), np.float32)
    for i in range(n):
        if not is_node[i]:
            continue
        c = NODE_VIOLET if is_violet[i] else NODE_BLUE
        r = _rng("noder", i)
        rad = 0.010 + 0.012 * r.rand()                   # small tight clusters, not blobs
        for ox in (-1.0, 0.0, 1.0):
            for oy in (-1.0, 0.0, 1.0):
                d = px0 - np.array([pts[i, 0] + ox, pts[i, 1] + oy], np.float32)  # unwarped = round
                dist = np.sqrt(d[..., 0] ** 2 + d[..., 1] ** 2)
                blob = np.clip(1.0 - dist / rad, 0.0, 1.0) ** 2
                emi = np.maximum(emi, blob[..., None] * c[None, None, :])
        # a few brighter caps (mushroom heads) clustered around the node
        rr = _rng("spk", i)
        for _ in range(rr.randint(4, 9)):
            a = rr.rand() * math.tau
            pr = rad * (0.5 + rr.rand())
            sx = int((pts[i, 0] + math.cos(a) * pr) % 1.0 * T)
            sy = int((pts[i, 1] + math.sin(a) * pr) % 1.0 * T)
            emi[sy, sx] = np.minimum(1.0, c * 1.15)
            for dd in ((0, 1), (1, 0)):
                emi[(sy + dd[0]) % T, (sx + dd[1]) % T] = c * 0.75
    emi = np.clip(emi, 0.0, 1.0)
    # the clusters also darken their footprint into the albedo (they sit ON the veins)
    node_mask = emi.max(axis=-1)
    alb[..., 3] = np.clip(alb[..., 3] + node_mask * 0.6, 0.0, 1.0)
    alb[..., :3] = alb[..., :3] * (1.0 - 0.5 * node_mask[..., None]) \
        + np.array([0.12, 0.10, 0.18])[None, None, :] * node_mask[..., None]

    # NORMAL MAP: the veins stand PROUD of the iron. Height = the vein ridge plus a
    # rounder bump under each cluster; the tangent-space normal is its gradient, so the
    # tendrils catch light in 3D relief. Rolled gradients keep it seamlessly tileable.
    height = vein * 0.8 + node_mask * 0.5
    gx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * 0.5
    gy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * 0.5
    strength = 2.4
    nx = -gx * strength
    ny = -gy * strength
    nz = np.ones_like(height)
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.stack([nx * inv, ny * inv, nz * inv], axis=-1)
    nrm_img = ((nrm * 0.5 + 0.5) * 255).astype(np.uint8)

    return (Image.fromarray((alb * 255).astype(np.uint8), "RGBA"),
            Image.fromarray((emi * 255).astype(np.uint8), "RGB"),
            Image.fromarray(nrm_img, "RGB"))


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    game = os.path.normpath(os.path.join(here, "..", "..", "to-rust-as-we-fall",
                                         "resources", "textures", "vasculature"))
    os.makedirs(game, exist_ok=True)
    alb, emi, nrm = build()
    alb.save(os.path.join(game, "vasculature_albedo.png"))
    emi.save(os.path.join(game, "vasculature_emissive.png"))
    nrm.save(os.path.join(game, "vasculature_normal.png"))
    # eyeball previews (3x) + a composite over a mock iron grey
    alb.resize((T * 3, T * 3), Image.NEAREST).save(r"C:\tmp\vasc_albedo.png")
    emi.resize((T * 3, T * 3), Image.NEAREST).save(r"C:\tmp\vasc_emissive.png")
    nrm.resize((T * 3, T * 3), Image.NEAREST).save(r"C:\tmp\vasc_normal.png")
    iron = Image.new("RGB", (T, T), (46, 42, 48))
    comp = Image.alpha_composite(iron.convert("RGBA"), alb).convert("RGB")
    ea = np.asarray(emi).astype(np.float32)
    ca = np.asarray(comp).astype(np.float32)
    comp = Image.fromarray(np.clip(ca + ea * 0.9, 0, 255).astype(np.uint8), "RGB")
    comp.resize((T * 3, T * 3), Image.NEAREST).save(r"C:\tmp\vasc_on_iron.png")
    print("wrote vasculature overlay + previews (C:/tmp/vasc_*.png)")
