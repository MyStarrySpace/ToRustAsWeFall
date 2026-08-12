# VORONOI-BRANCH vasculature (director's variant, 2026-07-28): generate the
# Voronoi cells first, then GROW the veins as a branching tree constrained to the
# cell-edge graph — "like a fractal tree but not quite". The uniform F2-F1 web
# read as a net; real growth is HIERARCHICAL: a few roots, trunks that split as
# they climb, taper with depth, and bud into glow nodes at the growing tips. The
# Voronoi boundaries supply the organic wiggle a recursive fractal lacks.
#
# Pipeline per variant:
#   1. Jittered-grid Voronoi sites on a TORUS (seamless tiling for free).
#   2. The edge graph: corner nodes ~ the meeting points of each 2x2 site quad
#      (a jittered approximation of the Voronoi vertices — exact circumcenters
#      are unnecessary at texture scale), edges between adjacent corners.
#   3. Tree growth: roots enter from the tile's wrap seam (so trunks flow across
#      tiles), then a priority walk outward — branch chance and step budget fall
#      with depth, every node claimed once (it is a TREE, never a net).
#   4. Draw: each traversed edge is a tapered stroke (width ~ decay^depth) with
#      a sine wobble; unclaimed cells stay BARE (negative space — the old web's
#      missing ingredient). Tips bud into biolume nodes.
#   5. Outputs: albedo + emissive + height-derived normal, palette-authored.
#
# Run:  python gen_vasculature_branch.py   (writes samples to the scratchpad
#       preview dir given by VB_OUT, or ./vb_samples next to this script)

from PIL import Image, ImageDraw, ImageFilter
import math, os, zlib, json
import numpy as np

_PAL = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                                   "to-rust-as-we-fall", "data", "palettes",
                                   "level_palettes.json"), encoding="utf-8"))
def _role(level, role):
    h = _PAL[level][role].lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])

VEIN_DARK = _role("channels", "vein_bark") * 0.82
VEIN_LIT = _role("channels", "vein_ridge")
NODE_BLUE = _role("channels", "biolume_blue")
NODE_VIOLET = _role("channels", "biolume_violet")

def _rng(*parts):
    return np.random.RandomState(zlib.crc32(":".join(map(str, parts)).encode()) & 0x7fffffff)

# ---------------------------------------------------------------- graph build
def build_graph(n, tag):
    """Corner-node graph of a jittered-grid Voronoi on the unit torus.
    Nodes: one per grid cell corner region, jittered. Edges: 4-neighbour wraps."""
    r = _rng(tag, "sites", n)
    jitter = 0.62 / n
    nodes = {}
    for i in range(n):
        for j in range(n):
            nodes[(i, j)] = ((i + 0.5) / n + r.uniform(-jitter, jitter),
                             (j + 0.5) / n + r.uniform(-jitter, jitter))
    edges = {}
    for (i, j) in nodes:
        edges[(i, j)] = [((i + 1) % n, j), ((i - 1) % n, j),
                         ((i, (j + 1) % n)), ((i, (j - 1) % n))]
    return nodes, edges

def grow_tree(nodes, edges, n, tag, roots, branch_p, max_depth, up_bias):
    """The not-quite-fractal tree: a priority walk over the cell graph.
    Returns [(a, b, depth)] parent->child segments and the set of tip nodes."""
    r = _rng(tag, "grow")
    claimed = {}
    segs = []
    frontier = []
    root_cols = r.choice(n, size=roots, replace=False)
    for c in root_cols:
        node = (int(c), 0)
        claimed[node] = 0
        frontier.append((node, 0))
    while frontier:
        idx = r.randint(len(frontier))
        node, depth = frontier.pop(idx)
        if depth >= max_depth:
            continue
        nexts = [nb for nb in edges[node] if nb not in claimed]
        if not nexts:
            continue
        take = 1 + (1 if r.rand() < branch_p * (1.0 - depth / max_depth) else 0)
        weights = []
        for nb in nexts:
            dy = (nb[1] - node[1])
            w = 1.0 + up_bias * (1.0 if dy == 1 or dy < -1 else 0.0)
            weights.append(w)
        weights = np.array(weights) / np.sum(weights)
        picks = r.choice(len(nexts), size=min(take, len(nexts)), replace=False, p=weights)
        for p in picks:
            nb = nexts[int(p)]
            claimed[nb] = depth + 1
            segs.append((node, nb, depth + 1))
            frontier.append((nb, depth + 1))
    tips = set(claimed) - {a for (a, _b, _d) in segs}
    return segs, tips, claimed

# ---------------------------------------------------------------- draw
def _wrap_pts(pa, pb):
    """Shortest torus offset so a seam-crossing edge draws on both sides."""
    dx = pb[0] - pa[0]; dy = pb[1] - pa[1]
    if dx > 0.5: dx -= 1.0
    if dx < -0.5: dx += 1.0
    if dy > 0.5: dy -= 1.0
    if dy < -0.5: dy += 1.0
    return dx, dy

def render(tag, size=512, cells=13, roots=4, branch_p=0.55, max_depth=26,
           up_bias=1.4, base_w=0.022, decay=0.90, tip_frac=0.6):
    nodes, edges = build_graph(cells, tag)
    segs, tips, claimed = grow_tree(nodes, edges, cells, tag, roots,
                                    branch_p, max_depth, up_bias)
    r = _rng(tag, "draw")
    height = Image.new("F", (size, size), 0.0)
    hd = ImageDraw.Draw(height)
    # CHAINS, not edges: veins must FLOW through junctions, so walk each root-to-
    # tip path, unroll it on the torus, Chaikin-smooth it, and stamp circles with
    # a CONTINUOUS taper along the whole chain — no elbows, no width jumps.
    children = {}
    for (a, b, d) in segs:
        children.setdefault(a, []).append(b)
    chain_list = []
    def walk(node, path_depth, chain):
        kids = children.get(node, [])
        if not kids:
            chain_list.append((chain[:], path_depth))
            return
        for ki, kid in enumerate(kids):
            if ki == 0:
                walk(kid, path_depth + 1, chain + [kid])
            else:
                chain_list.append((chain[:], path_depth))
                walk(kid, path_depth + 1, [node, kid])
    for rt in [n for n in claimed if claimed[n] == 0]:
        walk(rt, 0, [rt])
    def unroll(chain):
        pts = [nodes[chain[0]]]
        for k in range(1, len(chain)):
            dx, dy = _wrap_pts(pts[-1], nodes[chain[k]])
            pts.append((pts[-1][0] + dx, pts[-1][1] + dy))
        return pts
    def chaikin(pts, iters=3):
        for _ in range(iters):
            if len(pts) < 3:
                return pts
            out = [pts[0]]
            for k in range(len(pts) - 1):
                a, b = pts[k], pts[k + 1]
                out.append((a[0] * 0.75 + b[0] * 0.25, a[1] * 0.75 + b[1] * 0.25))
                out.append((a[0] * 0.25 + b[0] * 0.75, a[1] * 0.25 + b[1] * 0.75))
            out.append(pts[-1])
            pts = out
        return pts
    for chain, start_depth in chain_list:
        if len(chain) < 2:
            continue
        pts = chaikin(unroll(chain))
        total = len(pts) - 1
        for k in range(total):
            frac = k / max(1, total)
            depth_here = start_depth + frac * len(chain)
            w = base_w * (decay ** depth_here) * size
            lift = 1.0 - 0.55 * min(1.0, depth_here / max_depth)
            x, y = pts[k]
            steps = max(1, int(math.hypot(pts[k + 1][0] - x, pts[k + 1][1] - y) * size / 2))
            for st in range(steps):
                t = st / steps
                px = x + (pts[k + 1][0] - x) * t
                py = y + (pts[k + 1][1] - y) * t
                for ox in (-1, 0, 1):
                    for oy in (-1, 0, 1):
                        cx, cy = (px % 1.0 + ox) * size, (py % 1.0 + oy) * size
                        hd.ellipse([cx - w / 2, cy - w / 2, cx + w / 2, cy + w / 2], fill=lift)
    h = np.array(height)
    h8 = Image.fromarray((np.clip(h, 0, 1) * 255).astype(np.uint8), "L")
    h = np.array(h8.filter(ImageFilter.GaussianBlur(size / 340))).astype(np.float32) / 255.0
    # albedo: veins as raised bark over transparency (overlay usage)
    alb = np.zeros((size, size, 4))
    m = np.clip(h, 0, 1)
    col = VEIN_DARK[None, None, :] * (1 - m[..., None]) + VEIN_LIT[None, None, :] * m[..., None]
    alb[..., :3] = col
    alb[..., 3] = np.clip(m * 2.2, 0, 1)
    # emissive: the growing tips bud into biolume nodes
    emi = np.zeros((size, size, 3))
    ed = Image.new("F", (size, size), 0.0)
    edd = ImageDraw.Draw(ed)
    tip_list = [t for t in tips if r.rand() < tip_frac]
    tip_violet = {t: r.rand() < 0.4 for t in tip_list}
    for t in tip_list:
        x, y = nodes[t]
        rad = size * r.uniform(0.008, 0.016)
        for ox in (-1, 0, 1):
            for oy in (-1, 0, 1):
                cx, cy = (x + ox) * size, (y + oy) * size
                edd.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=1.0)
    e8 = Image.fromarray((np.clip(np.array(ed), 0, 1) * 255).astype(np.uint8), "L")
    eh = np.array(e8.filter(ImageFilter.GaussianBlur(size / 256))).astype(np.float32) / 255.0
    glow_col = NODE_BLUE * 0.65 + NODE_VIOLET * 0.35
    emi = eh[..., None] * glow_col[None, None, :]
    # normal from height
    gy, gx = np.gradient(h * 14.0)
    nz = 1.0 / np.sqrt(gx ** 2 + gy ** 2 + 1.0)
    nrm = np.stack([-gx * nz, gy * nz, nz], axis=-1) * 0.5 + 0.5
    return (Image.fromarray((np.clip(alb, 0, 1) * 255).astype(np.uint8), "RGBA"),
            Image.fromarray((np.clip(emi, 0, 1) * 255).astype(np.uint8), "RGB"),
            Image.fromarray((np.clip(nrm, 0, 1) * 255).astype(np.uint8), "RGB"),
            len(segs), len(tips))

def write_final(variant_name, kw, size=1024):
    """The chosen variant becomes THE vasculature overlay set (the filenames the
    triplanar shader loads). 1024 for the drum-scale read."""
    res = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                       "to-rust-as-we-fall", "resources", "textures", "vasculature")
    alb, emi, nrm, ns, nt = render(variant_name, size=size, **kw)
    alb.save(os.path.join(res, "vasculature_albedo.png"))
    emi.save(os.path.join(res, "vasculature_emissive.png"))
    nrm.save(os.path.join(res, "vasculature_normal.png"))
    print(f"[VB-FINAL] {variant_name} ({ns} segments, {nt} tips) -> resources/textures/vasculature/")

if __name__ == "__main__":
    out = os.environ.get("VB_OUT") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "vb_samples")
    os.makedirs(out, exist_ok=True)
    if os.environ.get("VB_FINAL"):
        name = os.environ["VB_FINAL"]
        finals = {
            "sparse_trunks": dict(cells=13, roots=3, branch_p=0.42, max_depth=30, up_bias=1.8, base_w=0.024, decay=0.90),
            "mid_web": dict(cells=15, roots=5, branch_p=0.6, max_depth=24, up_bias=1.2, base_w=0.02, decay=0.88),
            "dense_capillary": dict(cells=18, roots=6, branch_p=0.78, max_depth=30, up_bias=0.9, base_w=0.017, decay=0.9),
        }
        write_final(name, finals[name])
        raise SystemExit
    variants = {
        "sparse_trunks": dict(cells=13, roots=3, branch_p=0.42, max_depth=30, up_bias=1.8, base_w=0.024, decay=0.90),
        "mid_web": dict(cells=15, roots=5, branch_p=0.6, max_depth=24, up_bias=1.2, base_w=0.02, decay=0.88),
        "dense_capillary": dict(cells=18, roots=6, branch_p=0.78, max_depth=30, up_bias=0.9, base_w=0.017, decay=0.9),
    }
    for name, kw in variants.items():
        alb, emi, nrm, ns, nt = render(name, **kw)
        alb.save(os.path.join(out, f"vb_{name}_albedo.png"))
        emi.save(os.path.join(out, f"vb_{name}_emissive.png"))
        nrm.save(os.path.join(out, f"vb_{name}_normal.png"))
        # preview composite: albedo over dark iron + emissive add, tiled 2x2 to prove the seam
        base = np.array([0.055, 0.06, 0.07])
        a = np.array(alb).astype(np.float32) / 255.0
        e = np.array(emi).astype(np.float32) / 255.0
        comp = base[None, None, :] * (1 - a[..., 3:]) + a[..., :3] * a[..., 3:]
        comp = np.clip(comp + e * 1.4, 0, 1)
        t = np.tile(comp, (2, 2, 1))
        Image.fromarray((t * 255).astype(np.uint8)).save(os.path.join(out, f"vb_{name}_preview.png"))
        print(f"[VB] {name}: {ns} segments, {nt} tips -> vb_{name}_preview.png")
