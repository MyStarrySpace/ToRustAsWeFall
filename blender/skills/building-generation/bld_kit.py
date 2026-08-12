"""
bld_kit.py — THE ARCHITECTURE PARTS KIT (§3 knob option sets, §5 element sheets).

Every §3 knob option is a parametric part builder here, matched against its
reference sheet in reference-images/architecture/sheets/ (windows / doors / crowns /
projections / columns / signage / signforms / materials_decay).

Style rules baked in (from the sheets): structural members are BONE-CREAM, panels are
teal with pixel tiles, apertures carry pale BACKLIT MEMBRANE or hex-cell panes, moss
accents drape edges, bolt studs run along frames, rust gathers at joints.

Conventions:
- Deterministic (helpers.h01) — no randf, no wall clock.
- WALL parts (windows, doors, projections, wall panels): local frame X=width, Y=up,
  Z=outward; ALL local offsets are baked into vertices; every sub-object is placed
  with the same (loc, n) via place(). Text/lights use local_pt(loc, n, v).
- FREESTANDING parts (crowns, columns, sign monuments): world Z-up, base at z=0,
  built at origin; caller translates.
- Part fn signature: fn(M, objs, lights, loc, n?) -> appends bpy objects to objs,
  light specs ('POINT', world_loc, color, energy, radius) to lights.
- Knob dispatch tables at the bottom (WINDOWS/DOORS/CROWNS/PROJECTIONS/STRUCTURES/
  SIGN_FORMS) map §3 option names -> builders for the whole-building assembler.

Import (no demo on import):
    sys.path.insert(0, r"...\\blender\\skills\\building-generation")
    import bld_kit as K; importlib.reload(K)
"""
import bpy, bmesh, math, sys
from mathutils import Vector

SKILL = r"C:\Users\quest\Programming\Games\ToRustAsWeFall\blender\skills\building-generation"
if SKILL not in sys.path: sys.path.insert(0, SKILL)
import helpers as H

TAU = math.tau
def rad(d): return math.radians(d)

# ============================================================ PALETTE (sRGB 0..1)
TEAL   = (0.150, 0.255, 0.248)
TEAL_D = (0.092, 0.158, 0.152)
TEAL_L = (0.252, 0.330, 0.282)
SEAMC  = (0.058, 0.094, 0.090)
RUST   = (0.300, 0.165, 0.085)
RUST_L = (0.420, 0.245, 0.130)
RUST_D = (0.140, 0.075, 0.045)
BONE   = (0.500, 0.462, 0.372)
BONE_D = (0.330, 0.300, 0.238)
BONE_L = (0.615, 0.575, 0.478)
MEMB   = (0.640, 0.610, 0.500)
MEMB_S = (0.400, 0.375, 0.300)
CREAM  = (0.560, 0.480, 0.310)
GREEN  = (0.360, 0.910, 0.500)
GREEN_D= (0.030, 0.085, 0.045)
WARM   = (0.760, 0.640, 0.330)
CYAN   = (0.550, 0.880, 0.960)
FLAME  = (1.000, 0.450, 0.120)
MOSS   = (0.085, 0.110, 0.055)
PLANT  = (0.145, 0.205, 0.085)
PLANT_D= (0.300, 0.250, 0.125)
NAVY   = (0.085, 0.115, 0.200)
PINKSUB= (0.400, 0.290, 0.265)
PAV    = (0.100, 0.112, 0.116)
PAV_S  = (0.034, 0.040, 0.044)
DARKGL = (0.012, 0.018, 0.020)

def mixc(a, b, t): return (a[0]+(b[0]-a[0])*t, a[1]+(b[1]-a[1])*t, a[2]+(b[2]-a[2])*t)
def shc(c, f): return (min(1, c[0]*f), min(1, c[1]*f), min(1, c[2]*f))

# ============================================================ PIXEL TILES
def make_tile(name, T, painter, **kw):
    if name in bpy.data.images: bpy.data.images.remove(bpy.data.images[name])
    grid = [[(0.0, 0.0, 0.0, 1.0)] * T for _ in range(T)]
    painter(grid, T, **kw)
    img = bpy.data.images.new(name, T, T, alpha=True)
    px = [0.0] * (T * T * 4)
    for y in range(T):
        for x in range(T):
            c = grid[y][x]; k = (y * T + x) * 4
            px[k] = c[0]; px[k+1] = c[1]; px[k+2] = c[2]; px[k+3] = c[3]
    img.pixels = px; img.pack()
    return img

def _put(grid, x, y, c, a=1.0):
    T = len(grid); grid[y % T][x % T] = (c[0], c[1], c[2], a)

def _blend(grid, x, y, c, f):
    T = len(grid); b = grid[y % T][x % T]
    m = mixc((b[0], b[1], b[2]), c, f)
    grid[y % T][x % T] = (m[0], m[1], m[2], b[3])

def p_metal(grid, T, seed=0.0):
    for y in range(T):
        for x in range(T):
            f = 1.0 + 0.05 * ((x * 5 + x // 3) % 3 - 1)
            c = shc(TEAL, f * (0.90 + 0.12 * H.h01(x * 3.3 + y * 7.7 + seed)))
            if y == T - 1: c = SEAMC
            if y == 0: c = shc(TEAL, 0.76)
            _put(grid, x, y, c)
    for (cx, cy) in ((2, 2), (T - 3, 2), (2, T - 3), (T - 3, T - 3), (T // 2, T // 2)):
        _put(grid, cx, cy, TEAL_L); _put(grid, cx, cy - 1, SEAMC)
    for i in range(10):
        _put(grid, int(H.h01(i * 3.1 + seed) * T), int(H.h01(i * 7.9 + seed * 2) * T), RUST)

def p_bone(grid, T, seed=0.0):
    """Warm bone/cream structural member surface: segment seams + pores + rust flecks."""
    for y in range(T):
        for x in range(T):
            f = 0.90 + 0.16 * H.h01(x * 5.7 + y * 3.1 + seed)
            c = shc(BONE, f)
            if (y % 16) == 0: c = shc(BONE_D, 0.95)              # segment seam
            elif (y % 16) == 1: c = BONE_L                        # lit lip
            if H.h01(x * 9.4 + y * 6.2 + seed * 3) < 0.04: c = shc(BONE_D, 0.85)  # pores
            _put(grid, x, y, c)
    for i in range(6):
        _put(grid, int(H.h01(i * 4.2 + seed) * T), int(H.h01(i * 8.8 + seed) * T), RUST)

def p_rust(grid, T, seed=0.0):
    for y in range(T):
        for x in range(T):
            f = 0.8 + 0.32 * H.h01(x * 5.1 + y * 3.7 + seed)
            _put(grid, x, y, shc(RUST, f))
    for b in range(10):
        cx = int(H.h01(b * 4.7 + seed) * T); cy = int(H.h01(b * 8.3 + seed) * T)
        r = 2 + int(H.h01(b * 2.9) * 4)
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if dx * dx + dy * dy <= r * r:
                    dd = (dx * dx + dy * dy) / (r * r + 0.1)
                    tgt = RUST_L if H.h01(b * 6.1 + dx + dy * 7) > 0.35 else RUST_D
                    _put(grid, cx + dx, cy + dy, mixc(tgt, RUST, dd))

def p_grate(grid, T, seed=0.0):
    bar = mixc(TEAL_D, RUST_D, 0.55)
    for y in range(T):
        for x in range(T):
            if (x % 4 < 1) or (y % 4 < 1):
                top = (x % 8 == 0) or (y % 8 == 0)
                _put(grid, x, y, shc(bar, 1.2 if top else 0.85))
            else:
                _put(grid, x, y, (0, 0, 0), 0.0)

def p_paving(grid, T, seed=0.0, moss=0.35):
    for y in range(T):
        row = y // 16; off = (row % 2) * 16
        for x in range(T):
            sx = (x + off) % 32
            stone = ((x + off) // 32, row)
            tv = 0.82 + 0.3 * H.h01(stone[0] * 13.7 + stone[1] * 5.3 + seed)
            c = shc(PAV, tv)
            if sx < 2 or y % 16 < 2: c = PAV_S
            elif H.h01(x * 3.3 + y * 9.1 + seed) < 0.05: c = shc(PAV, tv * 1.3)
            if H.h01(x * 7.7 + y * 3.9 + seed * 5) < moss * 0.12: c = MOSS
            _put(grid, x, y, c)

def p_shingle(grid, T, seed=0.0, rust=0.6):
    sw, sh = 8, 5
    for y in range(T):
        row = y // sh; ly = y % sh; off = (row % 2) * (sw // 2)
        for x in range(T):
            lx = (x - off) % sw
            tv = 0.86 + 0.20 * H.h01(row * 7.31 + ((x - off) // sw) * 3.17 + seed)
            c = shc(TEAL, tv)
            d = abs(lx - (sw - 1) / 2.0) / ((sw - 1) / 2.0)
            edge = int(round(1 + 2.0 * d * d))
            if ly == edge: c = SEAMC
            elif ly == edge + 1: c = shc(TEAL_L, tv * 0.9)
            elif ly < edge: c = shc(c, 0.8)
            _put(grid, x, y, c)
    overlay_ferric(grid, T, seed=seed, rust=rust)

def _voronoi_cells(grid, T, seeds, cell_col, edge_col, edge_w=1.4, hole=False, seed=0.0):
    for y in range(T):
        for x in range(T):
            d1 = d2 = 1e9; c1 = 0
            for i, (sx, sy) in enumerate(seeds):
                dx = min(abs(x - sx), T - abs(x - sx))
                dy = min(abs(y - sy), T - abs(y - sy))
                dd = math.hypot(dx, dy)
                if dd < d1: d2 = d1; d1 = dd; c1 = i
                elif dd < d2: d2 = dd
            on_edge = (d2 - d1) < edge_w
            if on_edge:
                _put(grid, x, y, edge_col)
            elif hole:
                _put(grid, x, y, (0, 0, 0), 0.0)
            else:
                tv = 0.88 + 0.2 * H.h01(c1 * 7.9 + seed)
                _put(grid, x, y, shc(cell_col, tv))

def p_membrane(grid, T, seed=0.0):
    """Pale translucent basement-membrane cells (backlit pane)."""
    seeds = [(int(H.h01(i * 3.7 + seed) * T), int(H.h01(i * 8.1 + seed * 2) * T)) for i in range(7)]
    _voronoi_cells(grid, T, seeds, MEMB, MEMB_S, edge_w=1.6, seed=seed)

def p_voronoi_screen(grid, T, seed=0.0):
    """Open Voronoi cellular mesh-screen: bone web, real alpha holes."""
    seeds = [(int(H.h01(i * 5.3 + seed) * T), int(H.h01(i * 2.9 + seed * 3) * T)) for i in range(8)]
    _voronoi_cells(grid, T, seeds, MEMB, shc(BONE, 0.9), edge_w=2.6, hole=True, seed=seed)

def _hex_seeds(T, s):
    """Offset-brick lattice that tiles EXACTLY (T divisible by s) — its Voronoi is a
    hex-cell tessellation. No duplicate seeds under the wrap (duplicates flood the
    tile with 'edge' colour, since d2-d1 == 0 everywhere near them)."""
    n = max(2, T // s)
    seeds = []
    for r in range(n):
        off = (r % 2) * (s // 2)
        for c in range(n):
            seeds.append(((c * s + off) % T, (r * s) % T))
    return seeds

def p_hexpane(grid, T, seed=0.0, warm=False):
    """Rounded-hex cell glazing (honeycomb pane); warm variant = backlit banner."""
    col = shc(WARM, 1.1) if warm else shc(MEMB, 1.05)
    edge = shc(TEAL_D, 1.1) if not warm else mixc(RUST_D, WARM, 0.35)
    _voronoi_cells(grid, T, _hex_seeds(T, 16), col, edge, edge_w=1.0, seed=seed)

def p_hexrelief(grid, T, seed=0.0):
    """Raised rounded-hexagon relief tiling a teal wall."""
    _voronoi_cells(grid, T, _hex_seeds(T, 16), shc(TEAL, 1.12), shc(SEAMC, 1.15), edge_w=1.0, seed=seed)
    for y in range(T):
        for x in range(T):
            c = grid[y][x]
            if c[3] > 0 and (c[0], c[1], c[2]) != SEAMC and grid[(y + 1) % T][x][:3] == SEAMC:
                _put(grid, x, y, shc(TEAL_L, 1.05))              # lit top lip per cell

def p_cabling(grid, T, seed=0.0):
    """Wrapped-conduit vertical cabling, bone-cream."""
    tube = 8
    for y in range(T):
        for x in range(T):
            lx = x % tube
            prof = 1.0 - abs(lx - tube / 2 + 0.5) / (tube / 2) * 0.55
            c = shc(BONE, 0.62 + 0.5 * prof)
            band = (y + int(H.h01((x // tube) * 7.3 + seed) * 20)) % 26
            if band < 3: c = shc(BONE_D, 0.9 + 0.2 * (band == 1))   # wrap bands
            if lx == 0: c = shc(BONE_D, 0.72)
            _put(grid, x, y, c)

def p_substrate(grid, T, seed=0.0):
    """Muted pinkish substrate with meandering vessel grooves."""
    for y in range(T):
        for x in range(T):
            f = 0.88 + 0.2 * H.h01(x * 4.9 + y * 7.7 + seed)
            _put(grid, x, y, shc(PINKSUB, f))
    for v in range(4):
        x = int(H.h01(v * 9.7 + seed) * T)
        for y in range(T):
            x = (x + int(H.h01(v * 3.1 + y * 1.7 + seed) * 3) - 1) % T
            _blend(grid, x, y, shc(PINKSUB, 0.55), 0.8)
            _blend(grid, x + 1, y, shc(PINKSUB, 0.7), 0.5)

def p_diamond(grid, T, seed=0.0):
    base = shc(TEAL, 0.8)
    for y in range(T):
        for x in range(T):
            _put(grid, x, y, shc(base, 0.9 + 0.1 * H.h01(x * 3.1 + y * 5.7 + seed)))
    for gy in range(0, T, 8):
        for gx in range(0, T, 8):
            for (dx, dy) in ((2, 1), (3, 2), (2, 3), (1, 2)):
                _put(grid, gx + dx, gy + dy, shc(TEAL_L, 1.1))
            for (dx, dy) in ((3, 3), (2, 4), (4, 2)):
                _put(grid, gx + dx, gy + dy, SEAMC)

def p_tracery(grid, T, seed=0.0):
    """Whiplash vine-rib tracery: raised bone lines over teal."""
    p_metal(grid, T, seed=seed)
    for k in range(3):
        x = int(H.h01(k * 5.9 + seed) * T)
        amp = 4 + int(H.h01(k * 2.3) * 6)
        ph = H.h01(k * 8.8 + seed) * TAU
        for y in range(T):
            xx = int(x + amp * math.sin(y / T * TAU + ph)) % T
            _put(grid, xx, y, BONE)
            _put(grid, xx + 1, y, shc(BONE_D, 0.9))

def p_plaster(grid, T, seed=0.0):
    """Cream plaque face with hairline cracks."""
    for y in range(T):
        for x in range(T):
            f = 0.90 + 0.14 * H.h01(x * 6.3 + y * 2.9 + seed)
            _put(grid, x, y, shc((0.66, 0.62, 0.52), f))
    for k in range(4):
        x = int(H.h01(k * 7.1 + seed) * T); y = int(H.h01(k * 3.3 + seed) * T)
        L = 6 + int(H.h01(k * 5.5) * 14)
        for i in range(L):
            x = (x + int(H.h01(k + i * 2.7) * 3) - 1) % T
            y = (y + 1) % T
            _put(grid, x, y, (0.42, 0.39, 0.32))

def p_readout(grid, T, seed=0.0):
    """Terminal-green status board: header + text-run rows."""
    for y in range(T):
        for x in range(T):
            _put(grid, x, y, shc(GREEN_D, 0.85 + 0.3 * H.h01(x * 1.7 + y * 3.9 + seed)))
    def row_text(y, x0, x1, bright):
        x = x0
        while x < x1:
            L = 2 + int(H.h01(x * 3.3 + y * 7.1 + seed) * 5)
            for i in range(min(L, x1 - x)):
                _put(grid, x + i, y, shc(GREEN, bright))
                _put(grid, x + i, y + 1, shc(GREEN, bright))
            x += L + 2 + int(H.h01(x * 1.9 + y) * 3)
    row_text(T - 8, 5, T - 14, 0.85)                              # header
    for x in range(4, T - 4): _put(grid, x, T - 12, shc(GREEN, 0.5))
    for r in range(6):
        row_text(T - 18 - r * 6, 5, T - 6, 0.55 + 0.25 * H.h01(r * 4.4 + seed))
    row_text(6, 5, T // 2, 0.4)                                   # footer stamp

def p_toll(grid, T, seed=0.0):
    """Floor toll projection: border dashes, arrow, figure, text bands."""
    for y in range(T):
        for x in range(T):
            _put(grid, x, y, (0.004, 0.010, 0.006))
    g = lambda f: shc(GREEN, f)
    for i in range(0, T, 6):                                      # dashed border
        for k in range(3):
            _put(grid, (i + k) % T, 2, g(0.8)); _put(grid, (i + k) % T, T - 3, g(0.8))
            _put(grid, 2, (i + k) % T, g(0.8)); _put(grid, T - 3, (i + k) % T, g(0.8))
    cx = T // 2
    for i in range(10):                                           # arrow shaft + head
        _put(grid, cx, T - 14 - i, g(0.9)); _put(grid, cx + 1, T - 14 - i, g(0.9))
    for k in range(5):
        for s in (-1, 1):
            _put(grid, cx + s * k, T - 14 - 9 + k, g(0.9))
    for (dx, dy) in ((0, 0), (0, 1), (0, 2), (-1, 3), (1, 3), (0, 4), (-1, -1), (1, -1)):
        _put(grid, cx + dx, T // 2 - 6 + dy, g(1.0))              # figure blob
        _put(grid, cx + 1 + dx, T // 2 - 6 + dy, g(1.0))
    for x in range(8, T - 8, 3):                                  # text bands
        _put(grid, x, T - 8, g(0.7)); _put(grid, x + 1, T - 8, g(0.7))
        _put(grid, x, 8, g(0.7)); _put(grid, x + 1, 8, g(0.7))

def p_solar(grid, T, seed=0.0):
    for y in range(T):
        for x in range(T):
            c = shc(NAVY, 0.9 + 0.25 * H.h01((x // 8) * 5.1 + (y // 8) * 3.3 + seed))
            if x % 8 == 0 or y % 8 == 0: c = shc(BONE, 0.7)
            _put(grid, x, y, c)

# ---- decay overlays (compose over p_metal) ----
def overlay_ferric(grid, T, seed=0.0, rust=1.0):
    nd = int(4 + rust * 9)
    for dd in range(nd):
        x0 = int(H.h01(dd * 9.13 + seed * 3.1) * T)
        y0 = min(T - 1, T - 1 - int(H.h01(dd * 2.3) * 4))
        L = int(6 + H.h01(dd * 5.37 + seed) * T * 0.6 * rust)
        for i in range(L):
            y = y0 - i
            if y < 0: break
            f = 0.7 * (1.0 - i / max(1, L)) + 0.15
            _blend(grid, x0, y, RUST, f)
            if i < L * 0.5: _blend(grid, x0 + 1, y, RUST, f * 0.5)

def overlay_dust(grid, T, seed=0.0):
    for y in range(T):
        for x in range(T):
            near_seam = (y % (T // 2)) in (1, 2, 3)
            pr = 0.55 if near_seam else 0.13
            if H.h01(x * 7.7 + y * 5.1 + seed) < pr:
                _blend(grid, x, y, mixc(RUST_L, BONE_D, 0.35), 0.65)

def overlay_char(grid, T, seed=0.0):
    for b in range(4):
        cx = int(H.h01(b * 3.9 + seed) * T); cy = int(H.h01(b * 8.1 + seed) * T * 0.5)
        r = 6 + int(H.h01(b * 5.7) * 8)
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                dd = math.hypot(dx, dy)
                if dd <= r and H.h01(dx * 3.1 + dy * 7.7 + b) > dd / r * 0.55:
                    _blend(grid, cx + dx, cy + dy, (0.030, 0.026, 0.022), 0.85)

def overlay_weep(grid, T, seed=0.0):
    for k in range(5):
        x0 = int(H.h01(k * 6.6 + seed) * T); y0 = int((0.55 + 0.4 * H.h01(k * 2.2)) * T)
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                if dx * dx + dy * dy <= 5:
                    _blend(grid, x0 + dx, y0 + dy, mixc(MEMB, PLANT, 0.35), 0.85)
        L = int(10 + H.h01(k * 4.4) * T * 0.8)
        for i in range(L):
            y = y0 - 3 - i
            if y < 0: break
            f = 0.7 * (1 - i / L) + 0.15
            _blend(grid, x0, y, mixc(MEMB, PLANT, 0.5), f)
            _blend(grid, x0 + 1, y, mixc(MEMB, PLANT, 0.6), f * 0.5)

def overlay_crack(grid, T, seed=0.0):
    cx, cy = T // 2, int(T * 0.55)
    for k in range(5):
        x, y = cx, cy
        ang = H.h01(k * 3.7 + seed) * TAU
        L = 8 + int(H.h01(k * 6.1) * (T // 2))
        for i in range(L):
            x = int(x + math.cos(ang)) ; y = int(y + math.sin(ang))
            ang += (H.h01(k * 9.9 + i * 2.3) - 0.5) * 0.9
            _put(grid, x, y, (0.020, 0.032, 0.030))
            _put(grid, x + 1, y, (0.020, 0.032, 0.030))
            _blend(grid, x - 1, y, SEAMC, 0.5)
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            if dx * dx + dy * dy <= 4: _blend(grid, cx + dx, cy + dy, SEAMC, 0.8)

def overlay_candid(grid, T, seed=0.0):
    for b in range(5):
        cx = int(H.h01(b * 8.3 + seed) * T); cy = int(H.h01(b * 3.1 + seed) * T * 0.5)
        r = 3 + int(H.h01(b * 6.7) * 5)
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                dd = math.hypot(dx, dy)
                if dd <= r and H.h01(dx * 5.5 + dy * 3.3 + b * 7) > dd / r * 0.6:
                    _blend(grid, cx + dx, cy + dy, (0.72, 0.70, 0.64), 0.8)
        for i in range(int(r * 2.5)):                             # creeping strands
            a = H.h01(b * 4.1 + i) * TAU
            rr = r + i * 0.6
            _blend(grid, cx + int(math.cos(a) * rr), cy + int(math.sin(a) * rr), (0.68, 0.66, 0.60), 0.45)

def overlay_dripcrust(grid, T, seed=0.0):
    """Desaturated rust-brown molten drip-crust from the top edge (NOT pink-red)."""
    dun = (0.310, 0.220, 0.150)
    for x in range(T):
        L = int((0.12 + 0.5 * H.h01(x * 0.37 + seed) * H.h01(x * 3.1)) * T)
        if H.h01(x * 7.3 + seed) < 0.25: L = int(L * 1.8)
        for i in range(L):
            y = T - 1 - i
            f = 0.95 if i < L - 2 else 0.75
            _blend(grid, x, y, shc(dun, 0.8 + 0.35 * H.h01(x * 1.9 + i * 3.7)), f)
        if L > 4:
            _blend(grid, x, T - 1 - L, shc(dun, 1.25), 0.9)       # rounded lit tip

def compose(base, *overlays):
    def painter(grid, T, seed=0.0, **kw):
        base(grid, T, seed=seed)
        for ov in overlays: ov(grid, T, seed=seed)
    return painter

# ============================================================ MATERIALS
def tile_mat(name, img, tile_m=1.0, rough=0.85, metal=0.0, alpha=False, emis=0.0, emis_col=None):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes.get('Principled BSDF')
    b.inputs['Roughness'].default_value = rough; b.inputs['Metallic'].default_value = metal
    tc = nt.nodes.new('ShaderNodeTexCoord'); mp = nt.nodes.new('ShaderNodeMapping')
    mp.inputs['Scale'].default_value = (1.0 / tile_m,) * 3
    ti = nt.nodes.new('ShaderNodeTexImage')
    ti.image = img; ti.interpolation = 'Closest'; ti.projection = 'BOX'; ti.projection_blend = 0.2
    nt.links.new(tc.outputs['Object'], mp.inputs['Vector'])
    nt.links.new(mp.outputs['Vector'], ti.inputs['Vector'])
    nt.links.new(ti.outputs['Color'], b.inputs['Base Color'])
    if emis > 0:
        try:
            b.inputs['Emission Strength'].default_value = emis
            if emis_col:
                b.inputs['Emission Color'].default_value = (*emis_col, 1.0)
            else:
                nt.links.new(ti.outputs['Color'], b.inputs['Emission Color'])
        except Exception: pass
    if alpha:
        nt.links.new(ti.outputs['Alpha'], b.inputs['Alpha']); H.alpha_flags(m)
    return m

def emis_mat(name, col, strength):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes): nt.nodes.remove(n)
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    em = nt.nodes.new('ShaderNodeEmission')
    em.inputs['Color'].default_value = (col[0], col[1], col[2], 1.0)
    em.inputs['Strength'].default_value = strength
    nt.links.new(em.outputs[0], out.inputs[0])
    return m

def build_mats():
    M = {}
    M['metal'] = tile_mat('k_metal', make_tile('kt_metal', 32, p_metal, seed=2.0))
    M['ferric'] = tile_mat('k_ferric', make_tile('kt_ferric', 64, compose(p_metal, overlay_ferric), seed=6.0))
    M['bone'] = tile_mat('k_bone', make_tile('kt_bone', 32, p_bone, seed=1.0), rough=0.8)
    M['rust'] = tile_mat('k_rust', make_tile('kt_rust', 32, p_rust, seed=3.0), rough=0.9)
    M['grate'] = tile_mat('k_grate', make_tile('kt_grate', 32, p_grate), alpha=True)
    M['paving'] = tile_mat('k_paving', make_tile('kt_paving', 64, p_paving, seed=5.0), tile_m=3.2, rough=0.4)
    M['shingle'] = tile_mat('k_shingle', make_tile('kt_shingle', 64, p_shingle, seed=1.0), tile_m=2.0)
    M['membrane'] = tile_mat('k_membrane', make_tile('kt_membrane', 32, p_membrane), rough=0.45, emis=0.30)
    M['hexpane'] = tile_mat('k_hexpane', make_tile('kt_hexpane', 64, p_hexpane), tile_m=0.9, rough=0.45, emis=0.6)
    M['hexwarm'] = tile_mat('k_hexwarm', make_tile('kt_hexwarm', 64, p_hexpane, warm=True), tile_m=0.9, rough=0.5, emis=1.8)
    M['hexrelief'] = tile_mat('k_hexrelief', make_tile('kt_hexrelief', 64, p_hexrelief), tile_m=1.2)
    M['cabling'] = tile_mat('k_cabling', make_tile('kt_cabling', 32, p_cabling), rough=0.7)
    M['substrate'] = tile_mat('k_substrate', make_tile('kt_substrate', 32, p_substrate), rough=0.75)
    M['diamond'] = tile_mat('k_diamond', make_tile('kt_diamond', 32, p_diamond), rough=0.6, metal=0.1)
    M['voronoi'] = tile_mat('k_voronoi', make_tile('kt_voronoi', 32, p_voronoi_screen), alpha=True, rough=0.75)
    M['tracery'] = tile_mat('k_tracery', make_tile('kt_tracery', 64, p_tracery, seed=4.0), tile_m=1.6)
    M['plaster'] = tile_mat('k_plaster', make_tile('kt_plaster', 32, p_plaster), rough=0.8)
    M['readout'] = tile_mat('k_readout', make_tile('kt_readout', 64, p_readout), rough=0.4, emis=1.5)
    M['toll'] = tile_mat('k_toll', make_tile('kt_toll', 64, p_toll), rough=0.6, emis=2.2)
    M['solar'] = tile_mat('k_solar', make_tile('kt_solar', 32, p_solar), rough=0.3)
    for nm, ov in (('dust', overlay_dust), ('char', overlay_char), ('weep', overlay_weep),
                   ('crack', overlay_crack), ('candid', overlay_candid), ('dripcrust', overlay_dripcrust)):
        M[nm] = tile_mat('k_' + nm, make_tile('kt_' + nm, 64, compose(p_metal, ov), seed=7.0))
    M['teal_dark'] = H.matp('k_teal_dark', TEAL_D, rough=0.85)
    M['teal_flat'] = H.matp('k_teal_flat', (0.115, 0.175, 0.155), rough=0.8)
    M['trim'] = H.matp('k_trim', shc(TEAL_L, 0.78), rough=0.75)
    M['dark'] = H.matp('k_dark', DARKGL, rough=0.95)
    M['cream'] = H.matp('k_cream', CREAM, rough=0.7)
    M['bone_flat'] = H.matp('k_bone_flat', BONE, rough=0.8)
    M['moss'] = H.matp('k_moss', MOSS, rough=0.95)
    M['plant'] = H.matp('k_plant', PLANT, rough=0.9)
    M['plant_dry'] = H.matp('k_plant_dry', PLANT_D, rough=0.9)
    M['glossgreen'] = H.matp('k_glossgreen', (0.055, 0.115, 0.075), rough=0.22)
    M['screen'] = emis_mat('k_screen', GREEN, 1.8)
    M['cyanbar'] = emis_mat('k_cyanbar', CYAN, 2.5)
    M['flame'] = emis_mat('k_flame', (1.0, 0.42, 0.10), 2.2)
    M['haze'] = emis_mat('k_haze', (0.35, 0.36, 0.38), 0.25)
    M['fluid'] = emis_mat('k_fluid', (0.32, 0.88, 0.44), 3.5)
    M['toll_img'] = None                                           # built on demand (UV quad)
    return M

# ============================================================ GEOMETRY UTILS
def bx(bm, cx, cy, cz, sx, sy, sz):
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    v = [bm.verts.new((cx + a * hx, cy + b * hy, cz + c * hz))
         for (a, b, c) in ((-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1))]
    for f in ((0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)):
        bm.faces.new([v[i] for i in f])
    return v

def prism(bm, pts, z0, z1):
    lo = [bm.verts.new((p[0], p[1], z0)) for p in pts]
    hi = [bm.verts.new((p[0], p[1], z1)) for p in pts]
    n = len(pts)
    try: bm.faces.new(list(reversed(lo)))
    except Exception: pass
    try: bm.faces.new(hi)
    except Exception: pass
    for i in range(n):
        bm.faces.new([lo[i], lo[(i + 1) % n], hi[(i + 1) % n], hi[i]])

def ring(bm, outer, inner, z0, z1):
    """Annulus prism between two same-count closed outlines (frame with a hole)."""
    n = len(outer)
    of = [bm.verts.new((p[0], p[1], z1)) for p in outer]
    inf = [bm.verts.new((p[0], p[1], z1)) for p in inner]
    ob = [bm.verts.new((p[0], p[1], z0)) for p in outer]
    ib = [bm.verts.new((p[0], p[1], z0)) for p in inner]
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([of[i], of[j], inf[j], inf[i]])              # front annulus
        bm.faces.new([ib[i], ib[j], ob[j], ob[i]])                # back annulus
        bm.faces.new([ob[i], ob[j], of[j], of[i]])                # outer wall
        bm.faces.new([inf[i], inf[j], ib[j], ib[i]])              # inner wall

def sweep(bm, frames, prof, scales=None, cap0=True, cap1=True):
    rings = []
    for i, (o, u, v) in enumerate(frames):
        s = scales[i] if scales else 1.0
        rings.append([bm.verts.new(o + u * (a * s) + v * (b * s)) for (a, b) in prof])
    n = len(prof)
    for i in range(len(rings) - 1):
        for k in range(n):
            try: bm.faces.new([rings[i][k], rings[i][(k+1) % n], rings[i+1][(k+1) % n], rings[i+1][k]])
            except Exception: pass
    if cap0:
        try: bm.faces.new(list(reversed(rings[0])))
        except Exception: pass
    if cap1:
        try: bm.faces.new(rings[-1])
        except Exception: pass
    return rings

def cyl(bm, p0, p1, r, nseg=10, cap=True):
    p0 = Vector(p0); p1 = Vector(p1)
    t = (p1 - p0).normalized()
    u = t.cross(Vector((0, 0, 1)))
    if u.length < 1e-4: u = t.cross(Vector((1, 0, 0)))
    u.normalize(); v = t.cross(u)
    prof = [(math.cos(k / nseg * TAU) * r, math.sin(k / nseg * TAU) * r) for k in range(nseg)]
    sweep(bm, [(p0, u, v), (p1, u, v)], prof, cap0=cap, cap1=cap)

def cone(bm, c, r, h, nseg=6):
    c = Vector(c)
    base = [bm.verts.new(c + Vector((math.cos(k / nseg * TAU) * r, math.sin(k / nseg * TAU) * r, 0))) for k in range(nseg)]
    apex = bm.verts.new(c + Vector((0, 0, h)))
    try: bm.faces.new(list(reversed(base)))
    except Exception: pass
    for k in range(nseg):
        bm.faces.new([base[k], base[(k + 1) % nseg], apex])

def lathe(bm, rows, seg=12, cap_bot=True, apex=None):
    rings = []
    for (z, r) in rows:
        rings.append([bm.verts.new((math.cos(k / seg * TAU) * r, math.sin(k / seg * TAU) * r, z)) for k in range(seg)])
    for i in range(len(rings) - 1):
        for k in range(seg):
            bm.faces.new([rings[i][k], rings[i][(k+1) % seg], rings[i+1][(k+1) % seg], rings[i+1][k]])
    if cap_bot:
        try: bm.faces.new(list(reversed(rings[0])))
        except Exception: pass
    if apex is not None:
        av = bm.verts.new((0, 0, apex))
        for k in range(seg):
            bm.faces.new([rings[-1][k], rings[-1][(k + 1) % seg], av])
    else:
        try: bm.faces.new(rings[-1])
        except Exception: pass
    return rings

def bez_sweep(bm, p0, p1, p2, r0, r1, NS=7, seg=8):
    p0, p1, p2 = Vector(p0), Vector(p1), Vector(p2)
    frames = []; scales = []
    for i in range(NS):
        t = i / (NS - 1)
        o = p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
        tan = ((p1 - p0) * (1 - t) + (p2 - p1) * t).normalized()
        u = tan.cross(Vector((0, 0, 1)))
        if u.length < 1e-4: u = Vector((1, 0, 0))
        u.normalize(); v = tan.cross(u).normalized()
        frames.append((o, u, v))
        scales.append(r0 + (r1 - r0) * H.smooth(t))
    prof = [(math.cos(k / seg * TAU), math.sin(k / seg * TAU)) for k in range(seg)]
    sweep(bm, frames, prof, scales)

def oval(cx, cy, rx, ry, n=14):
    return [(cx + math.cos(k / n * TAU) * rx, cy + math.sin(k / n * TAU) * ry) for k in range(n)]

def capsule(w, h, ch=None):
    w2, t2 = w / 2, h / 2
    ch = ch if ch is not None else w * 0.55
    return [(-w2 + ch * 0.7, -t2), (w2 - ch * 0.7, -t2), (w2, -t2 + ch), (w2, t2 - ch),
            (w2 - ch * 0.7, t2), (-w2 + ch * 0.7, t2), (-w2, t2 - ch), (-w2, -t2 + ch)]

def arch(w, h, spring=0.55, n_arc=7, pointed=False):
    """Closed arch outline sitting on y=0: sides up to spring*h, arc to apex h."""
    w2 = w / 2; ys = h * spring
    pts = [(-w2, 0), (w2, 0), (w2, ys)]
    if pointed:
        for k in range(1, n_arc):
            t = k / n_arc
            x = w2 * math.cos(t * math.pi / 2)
            y = ys + (h - ys) * math.sin(t * math.pi / 2) ** 0.8
            pts.append((x, y))
        pts.append((0, h))
        for k in range(n_arc - 1, 0, -1):
            t = k / n_arc
            pts.append((-w2 * math.cos(t * math.pi / 2), ys + (h - ys) * math.sin(t * math.pi / 2) ** 0.8))
    else:
        for k in range(1, n_arc * 2):
            a = k / (n_arc * 2) * math.pi
            pts.append((w2 * math.cos(a), ys + (h - ys) * math.sin(a)))
    pts.append((-w2, ys))
    return pts

def inset(pts, t):
    """Shrink a closed outline toward its centroid (frame inner edge)."""
    cx = sum(p[0] for p in pts) / len(pts); cy = sum(p[1] for p in pts) / len(pts)
    out = []
    for (x, y) in pts:
        d = math.hypot(x - cx, y - cy)
        f = max(0.05, (d - t) / d) if d > 1e-6 else 0.0
        out.append((cx + (x - cx) * f, cy + (y - cy) * f))
    return out

def frame_quat(n): return Vector(n).to_track_quat('Z', 'Y')

def place(o, loc, n=None):
    o.location = Vector(loc)
    if n is not None:
        o.rotation_euler = frame_quat(n).to_euler()

def local_pt(loc, n, v):
    return Vector(loc) + frame_quat(n) @ Vector(v)

def studs(bm, pts, z, s=0.07, every=2):
    for p in pts[::every]:
        bx(bm, p[0], p[1], z, s, s, s)

def finishp(bm, name, mat, loc, n):
    o = H.finish(bm, name, mat); place(o, loc, n)
    return o

def add_text(objs, body, size, mat, loc, n=None, spacing=1.1, extrude=0.015, name="KIT_txt"):
    c = bpy.data.curves.new(name, 'FONT')
    c.body = body; c.align_x = 'CENTER'; c.align_y = 'CENTER'
    c.size = size; c.space_line = spacing; c.extrude = extrude
    o = bpy.data.objects.new(name, c)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(mat)
    if n is not None:
        place(o, loc, n)
    else:
        o.location = Vector(loc); o.rotation_euler = (math.pi / 2, 0, 0)
    objs.append(o)
    return o

def tufts(bm_moss, bm_dry, spots, seed=0.0):
    for i, (x, y, z, s) in enumerate(spots):
        tgt = bm_dry if H.h01(i * 3.3 + seed) < 0.4 else bm_moss
        cone(tgt, (x, y, z), s, s * (2.2 + H.h01(i * 7.7) * 1.5), 5)
        cone(tgt, (x + s * 0.7, y + s * 0.3, z), s * 0.6, s * 1.6, 5)

# ============================================================ WINDOWS (§3.5)
def win_membrane_pore(M, objs, lights, loc, n=(0, -1, 0)):
    bm = bmesh.new()
    o_out = oval(0, 0, 0.78, 0.98, 16)
    ring(bm, o_out, inset(o_out, 0.16), -0.10, 0.14)
    studs(bm, o_out, 0.06, 0.08, 2)
    for (sx, sy) in ((0, 1.08), (-0.5, 0.95), (0.5, 0.95)):       # top spikes
        bx(bm, sx, sy, 0.02, 0.09, 0.16, 0.09)
    objs.append(finishp(bm, "KIT_win_pore", M['bone'], loc, n))
    bm = bmesh.new(); prism(bm, inset(o_out, 0.14), -0.06, 0.0)
    objs.append(finishp(bm, "KIT_win_pore_pane", M['membrane'], loc, n))

def win_capillary_pair(M, objs, lights, loc, n=(0, -1, 0)):
    bm = bmesh.new(); bp = bmesh.new()
    for sx in (-0.36, 0.36):
        cap = [(sx + x, 0.42 + y) for (x, y) in capsule(0.46, 1.9)]
        ring(bm, cap, inset(cap, 0.10), -0.08, 0.12)
        prism(bp, inset(cap, 0.09), -0.04, 0.02)
    stem = [(-0.30, -1.55), (0.30, -1.55), (0.34, -0.9), (0.52, -0.62),
            (0.30, -0.55), (0.0, -0.72), (-0.30, -0.55), (-0.52, -0.62), (-0.34, -0.9)]
    prism(bm, stem, -0.09, 0.10)                                   # Y-branch stem
    for sx in (-0.36, 0.36):
        bx(bm, sx, -0.62, 0.0, 0.24, 0.5, 0.16)
    objs.append(finishp(bm, "KIT_win_cap", M['bone'], loc, n))
    objs.append(finishp(bp, "KIT_win_cap_pane", M['membrane'], loc, n))

def win_balcony_bay(M, objs, lights, loc, n=(0, -1, 0)):
    a = [(x, y - 1.3) for (x, y) in arch(1.35, 2.6, 0.6, pointed=True)]
    bm = bmesh.new(); ring(bm, a, inset(a, 0.13), -0.10, 0.13)
    objs.append(finishp(bm, "KIT_win_bay", M['bone'], loc, n))
    bm = bmesh.new(); prism(bm, inset(a, 0.12), -0.35, -0.28)
    objs.append(finishp(bm, "KIT_win_bay_dark", M['dark'], loc, n))
    bm = bmesh.new()                                               # balcony basket
    bx(bm, 0, -1.36, 0.34, 1.7, 0.14, 0.8)                         # floor
    for i in range(5):
        px = -0.66 + i * 0.33
        bx(bm, px, -1.05, 0.66, 0.07, 0.5, 0.07)                   # posts
    bx(bm, 0, -0.82, 0.66, 1.6, 0.08, 0.10)                        # rail
    ppts = [(-0.85, -1.43), (0.85, -1.43), (0.55, -1.95), (-0.55, -1.95)]
    prism(bm, ppts, 0.05, 0.62)                                    # under-cone
    objs.append(finishp(bm, "KIT_win_bay_balc", M['metal'], loc, n))
    bmm = bmesh.new(); bmd = bmesh.new()
    tufts(bmm, bmd, ((-0.6, -1.25, 0.72, 0.10), (0.15, -1.27, 0.74, 0.09), (0.6, -1.26, 0.7, 0.08)))
    objs.append(finishp(bmm, "KIT_win_bay_moss", M['plant'], loc, n))
    objs.append(finishp(bmd, "KIT_win_bay_dry", M['plant_dry'], loc, n))

def win_drawer_band(M, objs, lights, loc, n=(0, -1, 0)):
    bm = bmesh.new()
    bx(bm, 0, 0, 0.0, 2.3, 1.8, 0.34)
    objs.append(finishp(bm, "KIT_win_drawer_cab", M['metal'], loc, n))
    bm = bmesh.new()
    for row, ry in ((0, 0.62), (1, -0.62)):
        for i in range(3):
            cx = -0.72 + i * 0.72
            bx(bm, cx, ry, 0.20, 0.62, 0.40, 0.08)
            bx(bm, cx, ry + 0.06, 0.26, 0.22, 0.05, 0.05)          # handle
    objs.append(finishp(bm, "KIT_win_drawer_faces", M['ferric'], loc, n))
    bm = bmesh.new(); bx(bm, 0, 0, 0.19, 1.95, 0.52, 0.05)
    objs.append(finishp(bm, "KIT_win_drawer_screen", M['readout'], loc, n))

def win_shuttered(M, objs, lights, loc, n=(0, -1, 0)):
    a = [(x, y - 1.15) for (x, y) in arch(1.25, 2.3, 0.62, pointed=False)]
    bm = bmesh.new(); ring(bm, a, inset(a, 0.12), -0.10, 0.12)
    objs.append(finishp(bm, "KIT_win_shut_frame", M['bone'], loc, n))
    bm = bmesh.new(); prism(bm, inset(a, 0.11), -0.30, -0.24)
    objs.append(finishp(bm, "KIT_win_shut_dark", M['dark'], loc, n))
    bm = bmesh.new()
    for i in range(8):                                             # rolled slats, half-lowered
        y = 0.98 - i * 0.175
        bx(bm, 0, y, -0.05, 1.02, 0.16, 0.06 + 0.015 * (i % 2))
    bx(bm, 0, 0.98 - 7 * 0.175 - 0.12, -0.02, 1.06, 0.09, 0.10)    # bottom lip
    objs.append(finishp(bm, "KIT_win_shut_slats", M['rust'], loc, n))

def win_honeycomb_cell(M, objs, lights, loc, n=(0, -1, 0)):
    hexo = [(math.cos(a) * 0.62, 0.25 + math.sin(a) * 0.85) for a in
            [rad(90 + k * 60 - 30) for k in range(6)]]
    hexo = [(x, y) for (x, y) in hexo]
    bm = bmesh.new(); ring(bm, hexo, inset(hexo, 0.11), -0.09, 0.12)
    objs.append(finishp(bm, "KIT_win_hex_frame", M['metal'], loc, n))
    bm = bmesh.new(); prism(bm, inset(hexo, 0.10), -0.05, 0.01)
    objs.append(finishp(bm, "KIT_win_hex_pane", M['hexpane'], loc, n))
    bm = bmesh.new(); bx(bm, 0, -0.88, 0.22, 1.2, 0.36, 0.5)       # sill planter
    objs.append(finishp(bm, "KIT_win_hex_sill", M['teal_dark'], loc, n))
    bmm = bmesh.new(); bmd = bmesh.new()
    tufts(bmm, bmd, ((-0.4, -0.68, 0.32, 0.10), (0.0, -0.66, 0.35, 0.12), (0.42, -0.68, 0.3, 0.09)), seed=2)
    objs.append(finishp(bmm, "KIT_win_hex_pl", M['plant'], loc, n))
    objs.append(finishp(bmd, "KIT_win_hex_pd", M['plant_dry'], loc, n))

def win_rose_spoked(M, objs, lights, loc, n=(0, -1, 0)):
    bm = bmesh.new()
    o_out = oval(0, 0, 0.88, 0.88, 16)
    ring(bm, o_out, inset(o_out, 0.14), -0.09, 0.12)
    for k in range(8):                                             # spokes
        a = k / 8 * TAU
        ux, uy = math.cos(a), math.sin(a)
        L = 0.74; mx, my = ux * L / 2, uy * L / 2
        b2 = [(mx - uy * 0.035 + ux * -L / 2, my + ux * 0.035 + uy * -L / 2)]
        # thin radial box via manual quad prism
        w = 0.045
        pts = [(-uy * w + ux * 0.12, ux * w + uy * 0.12), (uy * w + ux * 0.12, -ux * w + uy * 0.12),
               (uy * w + ux * L, -ux * w + uy * L), (-uy * w + ux * L, ux * w + uy * L)]
        prism(bm, pts, -0.02, 0.07)
    cyl(bm, (0, 0, -0.02), (0, 0, 0.09), 0.16, 8)                  # hub
    objs.append(finishp(bm, "KIT_win_rose", M['bone'], loc, n))
    bm = bmesh.new(); prism(bm, inset(o_out, 0.13), -0.06, -0.01)
    objs.append(finishp(bm, "KIT_win_rose_pane", M['membrane'], loc, n))
    # companion spoked vent wheel
    bm = bmesh.new()
    v_out = oval(1.62, 0.0, 0.44, 0.44, 12)
    ring(bm, v_out, inset(v_out, 0.09), -0.06, 0.08)
    for k in range(6):
        a = k / 6 * TAU
        ux, uy = math.cos(a), math.sin(a)
        w = 0.035; L = 0.36
        pts = [(1.62 - uy * w, ux * w), (1.62 + uy * w, -ux * w),
               (1.62 + uy * w + ux * L, -ux * w + uy * L), (1.62 - uy * w + ux * L, ux * w + uy * L)]
        prism(bm, pts, -0.02, 0.05)
    objs.append(finishp(bm, "KIT_win_vent", M['bone'], loc, n))
    bm = bmesh.new(); prism(bm, inset(v_out, 0.08), -0.05, -0.02)
    bx(bm, 1.62, -0.62, -0.02, 0.10, 0.4, 0.03)                    # rust weep below
    objs.append(finishp(bm, "KIT_win_vent_dark", M['dark'], loc, n))

# ============================================================ DOORS (§3.6) — origin at ground
def door_dilating(M, objs, lights, loc, n=(0, -1, 0)):
    bm = bmesh.new()
    o_out = [(x, 1.5 + y) for (x, y) in oval(0, 0, 1.05, 1.38, 16)]
    ring(bm, o_out, inset(o_out, 0.18), -0.12, 0.16)
    studs(bm, o_out, 0.08, 0.10, 1)
    objs.append(finishp(bm, "KIT_door_iris_frame", M['bone'], loc, n))
    bm = bmesh.new()
    inner = inset(o_out, 0.20)
    cx = sum(p[0] for p in inner) / len(inner); cy = sum(p[1] for p in inner) / len(inner)
    for i in range(len(inner)):                                    # iris wedges -> centre slit
        j = (i + 1) % len(inner)
        tip = (cx * 0.94 + inner[i][0] * 0.06, cy + (inner[i][1] - cy) * 0.10)
        zz = -0.05 - 0.025 * (i % 2)
        try:
            prism(bm, [inner[i], inner[j], tip], zz, zz + 0.05)
        except Exception: pass
    objs.append(finishp(bm, "KIT_door_iris_leaves", M['membrane'], loc, n))
    bm = bmesh.new(); prism(bm, [(-0.05, 0.7), (0.05, 0.7), (0.05, 2.3), (-0.05, 2.3)], -0.10, -0.04)
    objs.append(finishp(bm, "KIT_door_iris_slit", M['dark'], loc, n))
    bmm = bmesh.new(); bmd = bmesh.new()
    tufts(bmm, bmd, ((-0.7, 0.12, 0.05, 0.11), (0.55, 0.1, 0.05, 0.10), (0.05, 0.06, 0.05, 0.08)), seed=3)
    objs.append(finishp(bmm, "KIT_door_iris_m", M['moss'], loc, n))
    objs.append(finishp(bmd, "KIT_door_iris_d", M['plant_dry'], loc, n))

def door_cycling_slab(M, objs, lights, loc, n=(0, -1, 0)):
    a = arch(1.55, 2.95, 0.75, pointed=False)
    bm = bmesh.new(); ring(bm, a, inset(a, 0.14), -0.10, 0.14)
    objs.append(finishp(bm, "KIT_door_slab_frame", M['metal'], loc, n))
    bm = bmesh.new()
    leaf = [(p[0] * 0.86, 0.35 + p[1] * 0.86) for p in inset(a, 0.13)]   # caught mid-cycle: lifted
    prism(bm, leaf, -0.06, 0.04)
    objs.append(finishp(bm, "KIT_door_slab_leaf", M['plaster'], loc, n))
    bm = bmesh.new(); prism(bm, inset(a, 0.12), -0.30, -0.24)
    objs.append(finishp(bm, "KIT_door_slab_dark", M['dark'], loc, n))
    bm = bmesh.new(); bx(bm, 0.95, 1.5, 0.05, 0.22, 0.5, 0.10)
    objs.append(finishp(bm, "KIT_door_slab_panel", M['teal_dark'], loc, n))
    bm = bmesh.new(); bx(bm, 0.95, 1.58, 0.11, 0.15, 0.2, 0.02)
    objs.append(finishp(bm, "KIT_door_slab_scr", M['screen'], loc, n))

def door_scan_arch(M, objs, lights, loc, n=(0, -1, 0)):
    a = arch(1.7, 3.05, 0.6, pointed=True)
    bm = bmesh.new(); ring(bm, a, inset(a, 0.15), -0.12, 0.15)
    studs(bm, a, 0.08, 0.08, 3)
    objs.append(finishp(bm, "KIT_door_scan_frame", M['bone'], loc, n))
    bm = bmesh.new(); prism(bm, inset(a, 0.14), -0.55, -0.48)
    objs.append(finishp(bm, "KIT_door_scan_dark", M['dark'], loc, n))
    bm = bmesh.new(); bx(bm, 0, 1.45, 0.0, 1.42, 0.06, 0.05)       # the scan-bar
    objs.append(finishp(bm, "KIT_door_scan_bar", M['cyanbar'], loc, n))
    lights.append(('POINT', local_pt(loc, n, (0, 1.45, 0.45)), CYAN, 30, 0.5))
    bm = bmesh.new(); bx(bm, -1.02, 1.35, 0.10, 0.24, 0.8, 0.12)
    objs.append(finishp(bm, "KIT_door_scan_post", M['teal_dark'], loc, n))
    bm = bmesh.new(); bx(bm, -1.02, 1.45, 0.17, 0.18, 0.5, 0.02)
    objs.append(finishp(bm, "KIT_door_scan_scr", M['readout'], loc, n))

def door_toll_gate(M, objs, lights, loc, n=(0, -1, 0)):
    a = arch(1.15, 2.95, 0.52, pointed=False)
    bm = bmesh.new(); ring(bm, a, inset(a, 0.13), -0.10, 0.13)
    objs.append(finishp(bm, "KIT_door_toll_frame", M['bone'], loc, n))
    bm = bmesh.new()
    sp = [(-0.42, 1.72), (0.42, 1.72), (0.42, 2.62), (-0.42, 2.62)]
    prism(bm, sp, -0.02, 0.06)
    objs.append(finishp(bm, "KIT_door_toll_scr", M['readout'], loc, n))
    bm = bmesh.new()
    cyl(bm, (0, 0.0, 0.02), (0, 1.35, 0.02), 0.07, 8)              # turnstile post
    hub = Vector((0, 1.05, 0.02))
    for k in range(3):
        aa = k / 3 * TAU + 0.5
        tip = hub + Vector((math.sin(aa) * 0.52, 0.12, math.cos(aa) * 0.52))
        cyl(bm, hub, tip, 0.045, 6)
    objs.append(finishp(bm, "KIT_door_toll_stile", M['rust'], loc, n))
    bm = bmesh.new(); prism(bm, inset(a, 0.12), -0.30, -0.24)
    objs.append(finishp(bm, "KIT_door_toll_dark", M['dark'], loc, n))

def door_blast_bulkhead(M, objs, lights, loc, n=(0, -1, 0)):
    bm = bmesh.new()
    o_out = [(x, 1.48 + y) for (x, y) in oval(0, 0, 1.02, 1.4, 16)]
    ring(bm, o_out, inset(o_out, 0.16), -0.12, 0.15)
    studs(bm, o_out, 0.08, 0.10, 1)
    objs.append(finishp(bm, "KIT_door_blast_frame", M['bone'], loc, n))
    bm = bmesh.new()
    leaf = inset(o_out, 0.17)
    prism(bm, leaf, -0.05, 0.05)
    for k in range(6):                                             # radial ribs
        aa = k / 6 * TAU + 0.26
        ux, uy = math.cos(aa), math.sin(aa) * 1.3
        w = 0.10
        pts = [(-math.sin(aa) * w + ux * 0.2, 1.48 + math.cos(aa) * w + uy * 0.2),
               (math.sin(aa) * w + ux * 0.2, 1.48 - math.cos(aa) * w + uy * 0.2),
               (math.sin(aa) * w + ux * 0.78, 1.48 - math.cos(aa) * w + uy * 0.78),
               (-math.sin(aa) * w + ux * 0.78, 1.48 + math.cos(aa) * w + uy * 0.78)]
        try: prism(bm, pts, 0.05, 0.11)
        except Exception: pass
    objs.append(finishp(bm, "KIT_door_blast_leaf", M['ferric'], loc, n))
    bm = bmesh.new()
    cyl(bm, (0, 1.48, 0.05), (0, 1.48, 0.16), 0.24, 10)
    cyl(bm, (0, 1.48, 0.16), (0, 1.48, 0.24), 0.13, 8)
    objs.append(finishp(bm, "KIT_door_blast_hub", M['rust'], loc, n))

# ============================================================ CROWNS (§3.3) — Z-up at origin
def crown_domed_cap(M, objs, lights, loc=(0, 0, 0)):
    L = Vector(loc)
    bm = bmesh.new()
    lathe(bm, [(0.0, 1.30), (0.18, 1.34), (0.35, 1.28), (0.9, 1.05), (1.4, 0.72), (1.75, 0.38)], 14, apex=1.95)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_cr_dome", M['shingle']))
    bm = bmesh.new()
    for k in range(6):                                             # base membrane ovals
        a = k / 6 * TAU
        ux, uy = math.cos(a), math.sin(a)
        c = Vector((ux * 1.12, uy * 1.12, 0.55)) + L
        b2 = bmesh.new()
        pts = oval(0, 0, 0.18, 0.26, 10)
        prism(b2, pts, -0.03, 0.05)
        me = bpy.data.meshes.new("kd"); b2.to_mesh(me); b2.free()
        for p in me.polygons: p.use_smooth = False
        ob = bpy.data.objects.new("KIT_cr_dome_pane", me)
        bpy.context.scene.collection.objects.link(ob)
        ob.data.materials.append(M['membrane'])
        place(ob, c, (ux, uy, 0.45))
        objs.append(ob)
    bm = bmesh.new()
    lathe(bm, [(1.88, 0.30), (2.0, 0.36), (2.34, 0.34), (2.42, 0.27)], 10, apex=2.75)
    cyl(bm, (0, 0, 2.72), (0, 0, 2.88), 0.05, 6)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_cr_dome_cupola", M['metal']))

def crown_branched_canopy(M, objs, lights, loc=(0, 0, 0)):
    L = Vector(loc)
    bm = bmesh.new()
    lathe(bm, [(0.0, 0.95), (0.25, 0.85), (0.5, 0.7)], 12)
    for (dx, dy, h, r0) in ((0.45, 0.1, 2.9, 0.40), (-0.4, 0.25, 2.55, 0.34), (-0.1, -0.4, 2.2, 0.30)):
        bez_sweep(bm, (dx * 0.4, dy * 0.4, 0.4), (dx * 0.9, dy * 0.9, h * 0.55), (dx * 2.2, dy * 2.2, h), r0, 0.05)
        bez_sweep(bm, (dx * 0.5, dy * 0.5, 0.9), (dx * 1.2, dy * 1.2, 1.3), (dx * 2.0, dy * 2.0, 1.1), r0 * 0.4, 0.03, NS=5)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_cr_branch", M['shingle']))

def crown_planted_terrace(M, objs, lights, loc=(0, 0, 0)):
    L = Vector(loc)
    bm = bmesh.new()
    lathe(bm, [(0.0, 1.15), (0.15, 1.22), (0.62, 1.28), (0.75, 1.18), (0.78, 1.02)], 14)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_cr_terrace", M['hexrelief']))
    bmm = bmesh.new(); bmd = bmesh.new()
    spots = []
    for k in range(9):
        a = k / 9 * TAU
        rr = 0.55 + 0.35 * H.h01(k * 3.1)
        spots.append((math.cos(a) * rr, math.sin(a) * rr, 0.66, 0.13 + 0.07 * H.h01(k * 7.7)))
    tufts(bmm, bmd, spots, seed=5)
    for vv in bmm.verts: vv.co += L
    for vv in bmd.verts: vv.co += L
    objs.append(H.finish(bmm, "KIT_cr_terrace_pl", M['plant']))
    objs.append(H.finish(bmd, "KIT_cr_terrace_pd", M['plant_dry']))
    bm = bmesh.new()
    for k in range(3):                                             # trailing vines
        a = k / 3 * TAU + 0.7
        bx(bm, math.cos(a) * 1.26, math.sin(a) * 1.26, 0.28, 0.06, 0.06, 0.6)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_cr_terrace_vine", M['moss']))

def crown_renewable(M, objs, lights, loc=(0, 0, 0)):
    L = Vector(loc)
    bm = bmesh.new()
    lathe(bm, [(0.0, 1.15), (0.5, 1.0), (1.1, 0.72), (1.5, 0.5)], 12)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_cr_renew", M['shingle']))
    so = bpy.data.objects
    bm = bmesh.new(); bx(bm, 0, 0, 0, 1.05, 0.75, 0.06)
    me = bpy.data.meshes.new("ks"); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = False
    ob = so.new("KIT_cr_solar", me); bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(M['solar'])
    ob.location = L + Vector((-0.55, -0.35, 1.35)); ob.rotation_euler = (rad(38), rad(8), rad(20))
    objs.append(ob)
    bm = bmesh.new()
    cyl(bm, (0.35, 0.25, 1.4), (0.35, 0.25, 2.75), 0.05, 8)
    bx(bm, 0.35, 0.25, 2.8, 0.3, 0.12, 0.12)
    for k in range(3):
        a = k / 3 * TAU + 0.4
        # blades in the XZ-ish rotor plane
        tip = Vector((0.35 + math.cos(a) * 0.75, 0.13, 2.8 + math.sin(a) * 0.75))
        cyl(bm, (0.35, 0.16, 2.8), tip, 0.035, 5)
    bx(bm, 0.62, 0.25, 2.8, 0.28, 0.05, 0.16)                      # tail vane
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_cr_turbine", M['bone']))

def crown_pore_vent_cap(M, objs, lights, loc=(0, 0, 0)):
    L = Vector(loc)
    bm = bmesh.new()
    lathe(bm, [(0.0, 0.55), (0.3, 0.85), (0.75, 0.95), (1.25, 0.62), (1.55, 0.34), (1.75, 0.40), (1.85, 0.36)], 12)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_cr_vent", M['metal']))
    for k in range(6):
        a = k / 6 * TAU + 0.3
        ux, uy = math.cos(a), math.sin(a)
        b2 = bmesh.new()
        prism(b2, oval(0, 0, 0.16, 0.22, 10), -0.03, 0.04)
        me = bpy.data.meshes.new("kv"); b2.to_mesh(me); b2.free()
        for p in me.polygons: p.use_smooth = False
        ob = bpy.data.objects.new("KIT_cr_vent_pane", me)
        bpy.context.scene.collection.objects.link(ob)
        ob.data.materials.append(M['membrane'])
        place(ob, L + Vector((ux * 0.88, uy * 0.88, 0.75)), (ux, uy, 0.2))
        objs.append(ob)
    bm = bmesh.new()                                               # dark open throat
    lathe(bm, [(1.84, 0.30), (1.86, 0.28)], 10)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_cr_vent_throat", M['dark']))

def crown_spired_cluster(M, objs, lights, loc=(0, 0, 0)):
    L = Vector(loc)
    bm = bmesh.new()
    lathe(bm, [(0.0, 1.05), (0.22, 0.95)], 10)
    specs = ((0, 0, 3.1, 0.34), (0.55, 0.25, 2.4, 0.26), (-0.5, 0.3, 2.7, 0.28),
             (0.25, -0.5, 2.1, 0.22), (-0.35, -0.45, 1.8, 0.20))
    for (dx, dy, h, r0) in specs:
        rows = [(0.2, r0), (h * 0.35, r0 * 0.75), (h * 0.7, r0 * 0.42)]
        rings = []
        for (z, r) in rows:
            rings.append([bm.verts.new((dx + math.cos(k / 8 * TAU) * r + dx * z * 0.06,
                                        dy + math.sin(k / 8 * TAU) * r + dy * z * 0.06, z)) for k in range(8)])
        for i in range(len(rings) - 1):
            for k in range(8):
                bm.faces.new([rings[i][k], rings[i][(k+1) % 8], rings[i+1][(k+1) % 8], rings[i+1][k]])
        av = bm.verts.new((dx * (1 + h * 0.06), dy * (1 + h * 0.06), h))
        for k in range(8):
            bm.faces.new([rings[-1][k], rings[-1][(k + 1) % 8], av])
        try: bm.faces.new(list(reversed(rings[0])))
        except Exception: pass
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_cr_spires", M['metal']))

def crown_flare_stack(M, objs, lights, loc=(0, 0, 0)):
    L = Vector(loc)
    bm = bmesh.new()
    lathe(bm, [(0.0, 0.78), (0.35, 0.62), (1.0, 0.30), (1.7, 0.26), (2.1, 0.42), (2.3, 0.5)], 10)
    for k in range(4):                                             # crown prongs
        a = k / 4 * TAU + 0.4
        bx(bm, math.cos(a) * 0.46, math.sin(a) * 0.46, 2.42, 0.10, 0.10, 0.3)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_cr_flare", M['ferric']))
    bm = bmesh.new()
    lathe(bm, [(2.3, 0.07), (2.52, 0.19), (2.85, 0.10), (3.1, 0.04)], 8, apex=3.32)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_cr_flame", M['flame']))
    lights.append(('POINT', L + Vector((0, 0, 2.75)), FLAME, 120, 0.5))
    for k in range(3):                                             # warm base panes
        a = k / 3 * TAU + 0.9
        ux, uy = math.cos(a), math.sin(a)
        b2 = bmesh.new(); prism(b2, oval(0, 0, 0.13, 0.2, 8), -0.02, 0.03)
        me = bpy.data.meshes.new("kf"); b2.to_mesh(me); b2.free()
        for p in me.polygons: p.use_smooth = False
        ob = bpy.data.objects.new("KIT_cr_flare_pane", me)
        bpy.context.scene.collection.objects.link(ob)
        ob.data.materials.append(M['hexwarm'])
        place(ob, L + Vector((ux * 0.6, uy * 0.6, 0.42)), (ux, uy, 0.25))
        objs.append(ob)

# ============================================================ PROJECTIONS (§3.7) — wall frame
def proj_translucent_canopy(M, objs, lights, loc, n=(0, -1, 0)):
    bm = bmesh.new()
    for sx in (-0.85, 0.85):
        prism(bm, [(sx - 0.05, 0.0), (sx + 0.05, 0.0), (sx + 0.05, 0.16), (sx - 0.05, 0.16)], 0.0, 1.25)
        prism(bm, [(sx - 0.04, -0.72), (sx + 0.04, -0.72), (sx + 0.04, 0.06), (sx - 0.04, 0.06)], 0.0, 0.06)
    for i in range(4):                                             # rib bars under the sheet
        zz = 0.12 + i * 0.36
        bx(bm, 0, 0.13 - zz * 0.28, zz, 1.8, 0.07, 0.07)
    objs.append(finishp(bm, "KIT_pr_canopy_frame", M['bone'], loc, n))
    bm = bmesh.new()
    sheet = [(-0.92, 0.2), (0.92, 0.2), (0.92, 0.16), (-0.92, 0.16)]
    lo = [bm.verts.new((p[0], p[1] - 0.0, 0.0)) for p in sheet]
    hi = [bm.verts.new((p[0], p[1] - 0.42, 1.38)) for p in sheet]
    for f in ((0, 1, 5, 4),):
        pass
    bm.faces.new([lo[0], lo[1], hi[1], hi[0]])
    bm.faces.new([lo[3], lo[2], hi[2], hi[3]])
    bm.faces.new([lo[0], hi[0], hi[3], lo[3]])
    bm.faces.new([lo[1], lo[2], hi[2], hi[1]])
    for sx in (-0.55, 0.2):                                        # membrane drips
        bx(bm, sx, -0.32, 1.30, 0.08, 0.22, 0.05)
    objs.append(finishp(bm, "KIT_pr_canopy_sheet", M['membrane'], loc, n))

def proj_slat_canopy(M, objs, lights, loc, n=(0, -1, 0)):
    bm = bmesh.new()
    for sx in (-0.8, 0.8):
        prism(bm, [(sx - 0.05, -0.65), (sx + 0.05, -0.65), (sx + 0.05, 0.08), (sx - 0.05, 0.08)], 0.0, 0.07)
        prism(bm, [(sx - 0.05, 0.0), (sx + 0.05, 0.0), (sx + 0.05, 0.14), (sx - 0.05, 0.14)], 0.0, 1.15)
    objs.append(finishp(bm, "KIT_pr_slat_frame", M['bone'], loc, n))
    bm = bmesh.new()
    for i in range(7):
        t = i / 6.0
        bx(bm, 0, 0.12 - t * 0.62, 0.12 + t * 1.05, 1.7, 0.05, 0.17)
    bx(bm, 0, -0.55, 1.24, 1.74, 0.07, 0.09)
    objs.append(finishp(bm, "KIT_pr_slats", M['ferric'], loc, n))

def proj_cantilever_balcony(M, objs, lights, loc, n=(0, -1, 0)):
    bm = bmesh.new()
    bx(bm, 0, 0.0, 0.55, 1.9, 0.16, 1.1)                           # slab
    w = [(-0.95, -0.08), (0.95, -0.08), (0.55, -0.5), (-0.55, -0.5)]
    prism(bm, w, 0.1, 1.0)                                         # taper underside
    objs.append(finishp(bm, "KIT_pr_balc_slab", M['metal'], loc, n))
    bm = bmesh.new()
    for i in range(5):
        px = -0.8 + i * 0.4
        bx(bm, px, 0.35, 1.06, 0.07, 0.55, 0.07)
    bx(bm, 0, 0.64, 1.06, 1.86, 0.07, 0.09)
    bx(bm, 0, 0.34, 1.06, 1.86, 0.05, 0.06)
    objs.append(finishp(bm, "KIT_pr_balc_rail", M['bone'], loc, n))

def proj_signage_bracket(M, objs, lights, loc, n=(0, -1, 0)):
    bm = bmesh.new()
    bx(bm, 0, 2.3, 0.06, 0.3, 0.9, 0.12)                           # wall plate
    bx(bm, 0, 2.62, 0.6, 0.10, 0.10, 1.2)                          # arm
    lo = bm.verts.new((0, 2.2, 0.12)); hi = bm.verts.new((0, 2.58, 1.05))
    cyl(bm, (0, 2.24, 0.14), (0, 2.56, 1.02), 0.045, 6)            # brace
    objs.append(finishp(bm, "KIT_pr_brk_arm", M['bone'], loc, n))
    bm = bmesh.new()
    for sx in (-0.28, 0.28):
        cyl(bm, (sx, 2.58, 0.9), (sx, 2.06, 0.9), 0.022, 5)        # chains
    objs.append(finishp(bm, "KIT_pr_brk_chain", M['rust'], loc, n))
    bm = bmesh.new()
    pl = [(x, 1.55 + y) for (x, y) in oval(0, 0, 0.5, 0.62, 12)]
    ring(bm, pl, inset(pl, 0.08), 0.86, 0.96)
    objs.append(finishp(bm, "KIT_pr_brk_ring", M['metal'], loc, n))
    bm = bmesh.new(); prism(bm, inset(pl, 0.07), 0.88, 0.94)
    objs.append(finishp(bm, "KIT_pr_brk_face", M['glossgreen'], loc, n))

def proj_hostile_ledge(M, objs, lights, loc, n=(0, -1, 0)):
    bm = bmesh.new()
    top = [(-0.8, 0.55), (0.8, 0.55), (0.8, 0.5), (-0.8, 0.5)]
    lo = [bm.verts.new((p[0], p[1], 0.0)) for p in top]
    hi = [bm.verts.new((p[0], p[1] - 0.42, 0.6)) for p in top]     # slanted no-stand top
    bm.faces.new([lo[0], lo[1], hi[1], hi[0]])
    bm.faces.new([lo[3], lo[2], hi[2], hi[3]])
    bm.faces.new([lo[0], hi[0], hi[3], lo[3]])
    bm.faces.new([lo[1], lo[2], hi[2], hi[1]])
    bx(bm, 0, 0.22, 0.03, 1.6, 0.5, 0.08)
    for sx in (-0.6, 0, 0.6):
        pts = [(sx - 0.04, 0.0), (sx + 0.04, 0.0), (sx + 0.04, 0.46), (sx - 0.04, 0.46)]
        prism(bm, pts, 0.0, 0.5)
    objs.append(finishp(bm, "KIT_pr_ledge", M['metal'], loc, n))

def proj_entry_hood(M, objs, lights, loc, n=(0, -1, 0)):
    a = arch(1.35, 2.5, 0.72, pointed=False)
    bm = bmesh.new(); ring(bm, a, inset(a, 0.12), -0.08, 0.10)
    objs.append(finishp(bm, "KIT_pr_hood_frame", M['bone'], loc, n))
    bm = bmesh.new(); prism(bm, inset(a, 0.11), -0.25, -0.18)
    objs.append(finishp(bm, "KIT_pr_hood_leaf", M['dark'], loc, n))
    bm = bmesh.new()                                               # curved faceted hood shell
    NS = 5
    rings2 = []
    for i in range(NS):
        t = i / (NS - 1)
        aa = t * math.pi / 2
        y = 2.5 + 0.85 * math.sin(aa) - 0.85 * (1 - math.cos(aa)) * 0.35
        z = 1.05 * math.cos(aa)
        rings2.append([bm.verts.new((x, y - 2.5 + 2.5, z)) for x in (-0.85, -0.3, 0.3, 0.85)])
    # correct: sweep rows from wall outward-down over the door
    for i in range(NS - 1):
        for k in range(3):
            bm.faces.new([rings2[i][k], rings2[i][k+1], rings2[i+1][k+1], rings2[i+1][k]])
    bmesh.ops.solidify(bm, geom=bm.faces[:] + bm.verts[:] + bm.edges[:], thickness=0.06)
    objs.append(finishp(bm, "KIT_pr_hood_shell", M['hexpane'], loc, n))
    bm = bmesh.new()
    for sx in (-0.85, 0.85):                                       # cheeks
        pts = [(sx - 0.05, 2.42), (sx + 0.05, 2.42), (sx + 0.05, 3.3), (sx - 0.05, 3.3)]
        prism(bm, pts, 0.0, 0.5)
    objs.append(finishp(bm, "KIT_pr_hood_cheeks", M['bone'], loc, n))

def proj_transit_viaduct(M, objs, lights, loc, n=(0, -1, 0)):
    bm = bmesh.new()
    p0 = Vector((0, 0.0, 0.9)); p1 = Vector((0, 1.1, 0.9)); p2a = Vector((-0.7, 2.15, 0.9)); p2b = Vector((0.7, 2.15, 0.9))
    bez_sweep(bm, p0, p1, p2a, 0.16, 0.10)
    bez_sweep(bm, p0, p1, p2b, 0.16, 0.10)
    bx(bm, 0, 0.35, 0.9, 0.5, 0.7, 0.34)
    objs.append(finishp(bm, "KIT_pr_via_leg", M['bone'], loc, n))
    bm = bmesh.new()
    cyl(bm, (-1.5, 2.35, 0.9), (1.5, 2.35, 0.9), 0.55, 10)
    for fx in (-1.0, 0.0, 1.0):
        cyl(bm, (fx - 0.07, 2.35, 0.9), (fx + 0.07, 2.35, 0.9), 0.62, 10)
    objs.append(finishp(bm, "KIT_pr_via_tube", M['metal'], loc, n))
    bm = bmesh.new()
    for wx in (-1.25, -0.45, 0.45, 1.25):
        b2 = oval(wx, 2.35, 0.22, 0.3, 8)
        prism(bm, [(p[0], p[1] - 2.35 + 2.35) for p in b2], 1.42, 1.5)
    o = H.finish(bm, "KIT_pr_via_win", M['hexwarm'])
    # windows lie on the tube flank: rebuild simple — place pane boxes instead
    bpy.data.objects.remove(o, do_unlink=True)
    bm = bmesh.new()
    for wx in (-1.25, -0.45, 0.45, 1.25):
        bx(bm, wx, 2.35 - 0.56, 0.9, 0.42, 0.06, 0.5)
    objs.append(finishp(bm, "KIT_pr_via_win", M['hexwarm'], loc, n))
    lights.append(('POINT', local_pt(loc, n, (0, 2.0, 0.9)), WARM, 25, 0.6))

# ============================================================ COLUMNS (§3.13) — Z-up
def col_tree_column(M, objs, lights, loc=(0, 0, 0)):
    L = Vector(loc)
    bm = bmesh.new()
    bx(bm, 0, 0, 0.15, 1.5, 1.5, 0.3)
    lathe(bm, [(0.3, 0.5), (0.5, 0.42), (1.6, 0.34), (2.8, 0.30)], 10)
    for k in range(4):
        a = k / 4 * TAU + 0.4
        tip = Vector((math.cos(a) * 1.0, math.sin(a) * 1.0, 4.45))
        bez_sweep(bm, (0, 0, 2.7), (math.cos(a) * 0.45, math.sin(a) * 0.45, 3.7), tip, 0.15, 0.09)
    for k in range(2):                                             # crossing inner limbs
        a = k * math.pi + 1.2
        bez_sweep(bm, (math.cos(a) * 0.2, math.sin(a) * 0.2, 3.0),
                  (math.cos(a + 1.5) * 0.5, math.sin(a + 1.5) * 0.5, 3.7),
                  (math.cos(a + 2.6) * 0.95, math.sin(a + 2.6) * 0.95, 4.45), 0.09, 0.06, NS=5)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_col_tree", M['bone']))
    bm = bmesh.new()
    lathe(bm, [(4.45, 1.3), (4.62, 1.3), (4.62, 1.05), (4.45, 1.05)], 14, cap_bot=False)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_col_tree_plat", M['metal']))
    bm = bmesh.new()
    for k in range(10):
        a = k / 10 * TAU
        bx(bm, math.cos(a) * 1.16, math.sin(a) * 1.16, 5.0, 0.09, 0.09, 0.75)
    r_out = [(math.cos(k / 14 * TAU) * 1.22, math.sin(k / 14 * TAU) * 1.22) for k in range(14)]
    ring(bm, [(x, y) for (x, y) in r_out], [(x * 0.92, y * 0.92) for (x, y) in r_out], 5.36, 5.45)
    for vv in bm.verts:
        vv.co = Vector((vv.co.x, vv.co.y, vv.co.z)) + L
    objs.append(H.finish(bm, "KIT_col_tree_rail", M['bone']))
    bm = bmesh.new()
    bx(bm, 0.35, 0.12, 1.5, 0.07, 0.07, 2.2)
    bx(bm, 0.30, 0.22, 0.8, 0.06, 0.06, 1.1)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_col_tree_vine", M['moss']))

def col_mushroom(M, objs, lights, loc=(0, 0, 0)):
    L = Vector(loc)
    bm = bmesh.new()
    bx(bm, 0, 0, 0.15, 1.6, 1.6, 0.3)
    lathe(bm, [(0.3, 0.62), (0.8, 0.42), (2.2, 0.32), (3.3, 0.5), (4.0, 1.15), (4.35, 1.7), (4.5, 1.75), (4.62, 1.55), (4.68, 0.9)], 12, apex=4.72)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_col_mush", M['hexrelief']))
    bm = bmesh.new()
    for k in range(6):                                             # flare ribs
        a = k / 6 * TAU
        bez_sweep(bm, (math.cos(a) * 0.34, math.sin(a) * 0.34, 2.2),
                  (math.cos(a) * 0.6, math.sin(a) * 0.6, 3.6),
                  (math.cos(a) * 1.68, math.sin(a) * 1.68, 4.45), 0.09, 0.05, NS=5)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_col_mush_ribs", M['bone']))

def col_tapered_pier(M, objs, lights, loc=(0, 0, 0)):
    L = Vector(loc)
    bm = bmesh.new()
    bx(bm, 0, 0, 0.2, 1.5, 1.5, 0.4)
    bx(bm, 0, 0, 0.55, 1.2, 1.2, 0.3)
    prof = [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)]
    frames = []
    for (z, s) in ((0.7, 1.0), (1.6, 0.82), (2.6, 0.72), (3.6, 0.82), (4.2, 0.95)):
        frames.append((Vector((0, 0, z)), Vector((1, 0, 0)), Vector((0, 1, 0))))
    sweep(bm, frames, prof, scales=[1.0, 0.82, 0.72, 0.82, 0.95])
    bx(bm, 0, 0, 4.42, 1.25, 1.25, 0.28)
    bx(bm, 0, 0, 4.66, 1.05, 1.05, 0.2)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_col_pier", M['hexrelief']))

def col_buttress_fin(M, objs, lights, loc=(0, 0, 0)):
    L = Vector(loc)
    bm = bmesh.new()
    bx(bm, 0, 0, 0.15, 1.7, 1.7, 0.3)
    for k in range(4):
        a = k / 4 * TAU
        ux, uy = math.cos(a), math.sin(a)
        fin = [(0.12, 0.3), (0.85, 0.3), (0.8, 1.4), (0.45, 2.6), (0.3, 3.8), (0.24, 4.9), (0.12, 4.9)]
        b2 = bmesh.new()
        prism(b2, fin, -0.07, 0.07)
        for vv in b2.verts:
            x, z = vv.co.x, vv.co.y
            w = vv.co.z
            vv.co = Vector((ux * x - uy * w, uy * x + ux * w, z))
        me = bpy.data.meshes.new("kfin"); b2.to_mesh(me); b2.free()
        for p in me.polygons: p.use_smooth = False
        ob = bpy.data.objects.new("KIT_col_fin", me)
        bpy.context.scene.collection.objects.link(ob)
        ob.data.materials.append(M['metal'])
        ob.location = L
        objs.append(ob)
    lathe(bm, [(0.3, 0.28), (3.6, 0.2), (4.9, 0.14)], 8, apex=5.5)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_col_fin_core", M['metal']))
    bmm = bmesh.new(); bmd = bmesh.new()
    tufts(bmm, bmd, ((0.55, 0.3, 0.3, 0.12), (-0.5, -0.4, 0.3, 0.10)), seed=8)
    for vv in bmm.verts: vv.co += L
    for vv in bmd.verts: vv.co += L
    objs.append(H.finish(bmm, "KIT_col_fin_m", M['moss']))
    objs.append(H.finish(bmd, "KIT_col_fin_d", M['plant_dry']))

def col_vine_rib_web(M, objs, lights, loc, n=(0, -1, 0)):
    bm = bmesh.new()
    bx(bm, 0, 2.3, -0.10, 2.1, 4.6, 0.16)
    objs.append(finishp(bm, "KIT_col_web_panel", M['hexrelief'], loc, n))
    bm = bmesh.new()
    def rib(px, py, qx, qy, mx, my, r0=0.09, r1=0.05):
        bez_sweep(bm, (px, py, 0.02), (mx, my, 0.10), (qx, qy, 0.02), r0, r1, NS=6, seg=6)
    rib(0.0, 0.1, 0.85, 4.4, -0.7, 2.3)
    rib(0.0, 0.1, -0.85, 4.3, 0.75, 2.2)
    rib(-0.15, 0.4, -0.9, 3.0, -0.75, 1.2)
    rib(0.15, 0.5, 0.9, 3.2, 0.8, 1.4)
    rib(-0.6, 4.55, 0.6, 4.55, 0.0, 4.1)
    objs.append(finishp(bm, "KIT_col_web_ribs", M['bone'], loc, n))
    bm = bmesh.new()
    ro = oval(0, 2.3, 0.58, 0.58, 12)
    ring(bm, ro, inset(ro, 0.10), 0.04, 0.14)
    for k in range(6):
        a = k / 6 * TAU
        ux, uy = math.cos(a), math.sin(a)
        w = 0.04
        pts = [(-uy * w + ux * 0.12, 2.3 + ux * w + uy * 0.12), (uy * w + ux * 0.12, 2.3 - ux * w + uy * 0.12),
               (uy * w + ux * 0.5, 2.3 - ux * w + uy * 0.5), (-uy * w + ux * 0.5, 2.3 + ux * w + uy * 0.5)]
        prism(bm, pts, 0.05, 0.11)
    objs.append(finishp(bm, "KIT_col_web_rose", M['bone'], loc, n))
    bm = bmesh.new(); prism(bm, inset(ro, 0.09), 0.0, 0.05)
    objs.append(finishp(bm, "KIT_col_web_rose_pane", M['membrane'], loc, n))
    bmm = bmesh.new(); bmd = bmesh.new()
    tufts(bmm, bmd, ((-0.9, 0.5, 0.05, 0.12), (0.95, 2.6, 0.05, 0.10), (-0.85, 3.6, 0.05, 0.09)), seed=4)
    objs.append(finishp(bmm, "KIT_col_web_m", M['plant'], loc, n))
    objs.append(finishp(bmd, "KIT_col_web_d", M['plant_dry'], loc, n))

def col_strut_truss(M, objs, lights, loc=(0, 0, 0)):
    L = Vector(loc)
    bm = bmesh.new()
    bx(bm, 0, 0, 0.15, 1.7, 1.1, 0.3)
    lathe(bm, [(0.3, 0.34), (1.1, 0.28), (2.1, 0.24)], 8)
    for sx in (-0.8, 0.8):
        bez_sweep(bm, (0, 0, 2.0), (sx * 0.5, 0, 2.9), (sx, 0, 3.6), 0.16, 0.11, NS=5)
        bx(bm, sx, 0, 3.7, 0.4, 0.5, 0.16)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_col_truss_leg", M['bone']))
    bm = bmesh.new()
    cyl(bm, (-1.5, 0, 4.25), (1.5, 0, 4.25), 0.56, 10)
    for fx in (-1.05, 0.0, 1.05):
        cyl(bm, (fx - 0.07, 0, 4.25), (fx + 0.07, 0, 4.25), 0.63, 10)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_col_truss_tube", M['metal']))
    bm = bmesh.new()
    for wx in (-1.28, -0.5, 0.5, 1.28):
        bx(bm, wx, -0.56, 4.25, 0.44, 0.06, 0.52)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_col_truss_win", M['hexwarm']))
    lights.append(('POINT', L + Vector((0, -1.0, 4.25)), WARM, 25, 0.5))

# ============================================================ SIGNAGE (§3.9)
def sign_wall_plaque(M, objs, lights, loc=(0, 0, 0)):
    L = Vector(loc)
    bm = bmesh.new()
    bx(bm, 0, 0, 1.65, 1.9, 0.16, 2.3)
    bx(bm, 0, -0.02, 2.86, 2.05, 0.2, 0.16)
    bx(bm, 0, -0.02, 0.44, 2.05, 0.2, 0.16)
    bx(bm, -0.98, -0.02, 1.65, 0.16, 0.2, 2.3)
    bx(bm, 0.98, -0.02, 1.65, 0.16, 0.2, 2.3)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_sg_plaque", M['metal']))
    bm = bmesh.new(); bx(bm, 0, -0.09, 1.65, 1.72, 0.05, 2.0)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_sg_plaque_face", M['plaster']))
    dk = H.matp('k_sg_green', (0.16, 0.28, 0.18), rough=0.7)
    add_text(objs, "The", 0.20, dk, L + Vector((0, -0.13, 2.52)))
    add_text(objs, "PLUMBING\nPOWER\nPROJECT", 0.34, dk, L + Vector((0, -0.13, 1.55)), spacing=1.25)
    bm = bmesh.new()
    bx(bm, 0, -0.13, 2.74, 0.10, 0.03, 0.16)                       # leaf emblem
    bx(bm, 0, -0.13, 2.80, 0.18, 0.03, 0.06)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_sg_plaque_leaf", M['cream']))

def sign_arch_banner(M, objs, lights, loc=(0, 0, 0)):
    L = Vector(loc)
    bm = bmesh.new()
    for sx in (-1.5, 1.5):
        bx(bm, sx, 0, 1.3, 0.3, 0.3, 2.6)
        bx(bm, sx, 0, 0.2, 0.5, 0.5, 0.4)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_sg_banner_posts", M['metal']))
    bm = bmesh.new()
    NS = 9
    frames = []
    for i in range(NS):
        t = i / (NS - 1)
        x = -1.5 + 3.0 * t
        z = 2.5 + 0.75 * math.sin(t * math.pi)
        frames.append((Vector((x, 0, z)), Vector((0, 1, 0)), Vector((0, 0, 1))))
    prof = [(-0.14, -0.42), (0.14, -0.42), (0.14, 0.42), (-0.14, 0.42)]
    sweep(bm, frames, prof)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_sg_banner_arch", M['ferric']))
    bm = bmesh.new()
    for i in range(NS - 1):
        t0 = i / (NS - 1); t1 = (i + 1) / (NS - 1)
        for (ta, tb) in ((t0, t1),):
            xa = -1.5 + 3.0 * ta; xb = -1.5 + 3.0 * tb
            za = 2.5 + 0.75 * math.sin(ta * math.pi); zb = 2.5 + 0.75 * math.sin(tb * math.pi)
            v0 = bm.verts.new((xa, -0.15, za - 0.36)); v1 = bm.verts.new((xb, -0.15, zb - 0.36))
            v2 = bm.verts.new((xb, -0.15, zb + 0.36)); v3 = bm.verts.new((xa, -0.15, za + 0.36))
            bm.faces.new([v0, v1, v2, v3])
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_sg_banner_glow", M['hexwarm']))
    dk = H.matp('k_sg_dark', (0.14, 0.11, 0.05), rough=0.6)
    add_text(objs, "The", 0.16, dk, L + Vector((0, -0.17, 3.36)))
    add_text(objs, "OPEN FILES", 0.30, dk, L + Vector((0, -0.17, 3.05)))
    add_text(objs, "INITIATIVE", 0.17, dk, L + Vector((0, -0.17, 2.78)))
    bm = bmesh.new()
    for sx in (-0.9, -0.2, 0.6):                                   # moss drips under the arch
        bx(bm, sx, 0, 2.1 + 0.5 * math.sin((sx + 1.5) / 3 * math.pi) - 0.2, 0.07, 0.07, 0.5)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_sg_banner_moss", M['moss']))

def sign_bracket_hanging(M, objs, lights, loc=(0, 0, 0)):
    L = Vector(loc)
    bm = bmesh.new()
    bx(bm, 0, 0, 2.9, 0.35, 0.35, 1.6)                             # wall stub post
    bx(bm, 0.62, 0, 3.55, 1.25, 0.10, 0.10)                        # arm
    cyl(bm, (0.12, 0, 3.0), (1.1, 0, 3.5), 0.04, 6)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_sg_brk_arm", M['metal']))
    bm = bmesh.new()
    for sx in (0.55, 1.05):
        cyl(bm, (sx, 0, 3.5), (sx, 0, 2.95), 0.022, 5)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_sg_brk_chains", M['rust']))
    bm = bmesh.new()
    ov = oval(0.8, 0, 0.62, 0.5, 14)
    ring(bm, [(p[0], p[1]) for p in ov], inset(ov, 0.09), 2.0, 2.14)
    for vv in bm.verts:
        vv.co = Vector((vv.co.x, vv.co.z - 2.07, vv.co.y + 2.35)) + L   # stand the oval upright
    objs.append(H.finish(bm, "KIT_sg_brk_ring", M['ferric']))
    bm = bmesh.new()
    prism(bm, inset(ov, 0.08), 2.02, 2.1)
    for vv in bm.verts:
        vv.co = Vector((vv.co.x, vv.co.z - 2.07, vv.co.y + 2.35)) + L
    objs.append(H.finish(bm, "KIT_sg_brk_face", M['glossgreen']))
    pale = H.matp('k_sg_pale', (0.62, 0.68, 0.56), rough=0.5)
    add_text(objs, "The", 0.13, pale, L + Vector((0.8, -0.06, 2.5)))
    add_text(objs, "HYPELINES", 0.20, pale, L + Vector((0.8, -0.06, 2.26)))
    bm = bmesh.new()
    for sx in (0.5, 0.95):
        bx(bm, sx, 0, 1.7, 0.05, 0.05, 0.35)                       # rust drips below
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_sg_brk_drip", M['rust']))

def sign_monument(M, objs, lights, loc=(0, 0, 0)):
    L = Vector(loc)
    bm = bmesh.new()
    a = arch(1.9, 2.6, 0.62, pointed=False)
    b2 = [(x, y) for (x, y) in a]
    lo = [bm.verts.new((p[0], -0.2, p[1] + 0.5)) for p in b2]
    hi = [bm.verts.new((p[0], 0.2, p[1] + 0.5)) for p in b2]
    try: bm.faces.new(list(reversed(lo)))
    except Exception: pass
    try: bm.faces.new(hi)
    except Exception: pass
    for i in range(len(b2)):
        j = (i + 1) % len(b2)
        bm.faces.new([lo[i], lo[j], hi[j], hi[i]])
    bx(bm, 0, 0, 0.3, 2.6, 0.9, 0.6)                               # base plinth
    for sx in (-1.05, 1.05):
        bx(bm, sx, -0.25, 0.75, 0.5, 0.45, 0.35)                   # planter troughs
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_sg_mon", M['ferric']))
    bm = bmesh.new(); bx(bm, 0, -0.21, 1.85, 1.5, 0.04, 1.7)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_sg_mon_face", M['plaster']))
    dk = H.matp('k_sg_green2', (0.18, 0.30, 0.20), rough=0.7)
    add_text(objs, "The", 0.15, dk, L + Vector((0, -0.24, 2.55)))
    add_text(objs, "GREENFIELDS\nCOLLECTIVE", 0.21, dk, L + Vector((0, -0.24, 2.2)), spacing=1.2)
    add_text(objs, "EST. 2417\nPLOT 7B\nIRRIGATION: OFFLINE", 0.105, dk, L + Vector((0, -0.24, 1.5)), spacing=1.35)
    bmm = bmesh.new(); bmd = bmesh.new()
    tufts(bmm, bmd, ((-1.05, -0.35, 0.9, 0.14), (-0.85, -0.3, 0.9, 0.10), (1.0, -0.35, 0.9, 0.13), (1.2, -0.3, 0.9, 0.09)), seed=6)
    for vv in bmm.verts: vv.co += L
    for vv in bmd.verts: vv.co += L
    objs.append(H.finish(bmm, "KIT_sg_mon_pl", M['plant']))
    objs.append(H.finish(bmd, "KIT_sg_mon_pd", M['plant_dry']))

# ---- sign FORMS (§5.5b) ----
def signform_regulatory(M, objs, lights, loc=(0, 0, 0)):
    L = Vector(loc)
    plates = (((-0.55, 2.6), 1.05, 0.55, "NO LOITERING\n· NO SITTING ·\nNO RESTING", 0.075),
              ((-0.5, 1.85), 1.35, 0.72, "STANDING ONLY\nBEYOND\nTHIS POINT  →", 0.095),
              ((-0.82, 1.05), 0.85, 0.5, "KEEP AISLE\nCLEAR", 0.085),
              ((0.18, 1.05), 0.85, 0.55, "VIOLATORS\nWILL BE\nCITED", 0.075))
    for i, ((cx, cz), w, h, txt, ts) in enumerate(plates):
        bm = bmesh.new()
        bx(bm, cx, 0, cz, w, 0.08, h)
        bx(bm, cx, -0.01, cz + h / 2, w + 0.06, 0.08, 0.05)
        bx(bm, cx, -0.01, cz - h / 2, w + 0.06, 0.08, 0.05)
        bx(bm, cx - w / 2, -0.01, cz, 0.05, 0.08, h + 0.06)
        bx(bm, cx + w / 2, -0.01, cz, 0.05, 0.08, h + 0.06)
        for vv in bm.verts: vv.co += L
        objs.append(H.finish(bm, "KIT_sf_reg", M['metal'] if i % 2 == 0 else M['ferric']))
        add_text(objs, txt, ts, M['cream'], L + Vector((cx, -0.06, cz)), spacing=1.3)

def signform_numeric(M, objs, lights, loc=(0, 0, 0)):
    L = Vector(loc)
    bm = bmesh.new()
    bx(bm, 0, 0, 1.5, 1.15, 0.1, 1.75)
    for (sx, sz) in ((-0.48, 0.72), (0.48, 0.72), (-0.48, 2.28), (0.48, 2.28)):
        bx(bm, sx, -0.03, sz, 0.09, 0.1, 0.09)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_sf_num", M['ferric']))
    add_text(objs, "6", 1.35, M['bone_flat'], L + Vector((0, -0.08, 1.42)), extrude=0.05)

def signform_status(M, objs, lights, loc=(0, 0, 0)):
    L = Vector(loc)
    bm = bmesh.new()
    bx(bm, 0, 0, 1.55, 1.5, 0.12, 1.85)
    bx(bm, 0, -0.03, 2.52, 1.62, 0.12, 0.12)
    bx(bm, 0, -0.03, 0.58, 1.62, 0.12, 0.12)
    bx(bm, -0.78, -0.03, 1.55, 0.12, 0.12, 2.0)
    bx(bm, 0.78, -0.03, 1.55, 0.12, 0.12, 2.0)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_sf_status", M['ferric']))
    bm = bmesh.new(); bx(bm, 0, -0.07, 1.55, 1.32, 0.03, 1.62)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_sf_status_scr", M['readout']))
    lights.append(('POINT', L + Vector((0, -0.5, 1.55)), GREEN, 14, 0.4))

def signform_floor_toll(M, objs, lights, loc=(0, 0, 0)):
    """UV-mapped shadeless quad — the projection maps the toll tile exactly once."""
    L = Vector(loc)
    bm = bmesh.new()
    v = [bm.verts.new((x, y, 0)) for (x, y) in ((-0.65, -0.95), (0.65, -0.95), (0.65, 0.95), (-0.65, 0.95))]
    f = bm.faces.new(v)
    uvl = bm.loops.layers.uv.new("UVMap")
    for loop, uvco in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        loop[uvl].uv = uvco
    me = bpy.data.meshes.new("ktoll"); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = False
    ob = bpy.data.objects.new("KIT_sf_toll", me)
    bpy.context.scene.collection.objects.link(ob)
    m = bpy.data.materials.new("k_toll_uv"); m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes): nt.nodes.remove(nd)
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    em = nt.nodes.new('ShaderNodeEmission'); em.inputs['Strength'].default_value = 2.4
    ti = nt.nodes.new('ShaderNodeTexImage')
    ti.image = bpy.data.images.get('kt_toll') or make_tile('kt_toll', 64, p_toll)
    ti.interpolation = 'Closest'
    nt.links.new(ti.outputs['Color'], em.inputs['Color'])
    nt.links.new(em.outputs[0], out.inputs[0])
    ob.data.materials.append(m)
    ob.location = L + Vector((0, -0.3, 0.9))
    ob.rotation_euler = (rad(58), 0, 0)                            # tilted up for the sheet read
    objs.append(ob)
    lights.append(('POINT', L + Vector((0, -0.9, 0.7)), GREEN, 18, 0.5))

def signform_emblems(M, objs, lights, loc=(0, 0, 0)):
    L = Vector(loc)
    for i in range(4):
        cx = -1.32 + i * 0.88
        bm = bmesh.new()
        bx(bm, cx, 0, 1.5, 0.8, 0.09, 1.05)
        for vv in bm.verts: vv.co += L
        objs.append(H.finish(bm, "KIT_sf_emb_plate", M['ferric' if i % 2 else 'metal']))
        bm = bmesh.new()
        if i == 0:                                                 # crest
            prism(bm, [(cx - 0.22, 1.1), (cx + 0.22, 1.1), (cx + 0.18, 1.62), (cx, 1.78), (cx - 0.18, 1.62)], -0.06, -0.01)
            bx(bm, cx, 1.86, -0.03, 0.3, 0.08, 0.07)
        elif i == 1:                                               # three-cell honeycomb
            for (hx, hz) in ((0, 1.72), (-0.15, 1.44), (0.15, 1.44)):
                prism(bm, [(cx + hx + math.cos(rad(90 + k * 60)) * 0.14, hz + math.sin(rad(90 + k * 60)) * 0.14) for k in range(6)], -0.06, -0.01)
        elif i == 2:                                               # four-point sparkle
            prism(bm, [(cx, 1.9), (cx + 0.07, 1.57), (cx + 0.4, 1.5), (cx + 0.07, 1.43), (cx, 1.1), (cx - 0.07, 1.43), (cx - 0.4, 1.5), (cx - 0.07, 1.57)], -0.06, -0.01)
        else:                                                      # smiley-flower + HPP
            for k in range(6):
                a = k / 6 * TAU
                prism(bm, oval(cx + math.cos(a) * 0.2, 1.62 + math.sin(a) * 0.2, 0.09, 0.09, 8), -0.05, -0.01)
            prism(bm, oval(cx, 1.62, 0.11, 0.11, 8), -0.06, -0.005)
        for vv in bm.verts:
            vv.co = Vector((vv.co.x, vv.co.z, vv.co.y)) + L        # relief: local z -> depth(y)
        objs.append(H.finish(bm, "KIT_sf_emb", M['bone_flat']))
        if i == 3:
            add_text(objs, "HPP", 0.09, M['cream'], L + Vector((cx, -0.06, 1.22)))

# ============================================================ KNOB DISPATCH (§3 option -> builder)
WINDOWS = {
    'pore_round': win_membrane_pore,
    'hairline_slit': win_capillary_pair,      # branching-pair realization
    'balcony_bay': win_balcony_bay,
    'drawer_face': win_drawer_band,
    'shuttered_metal': win_shuttered,
    'honeycomb_cell': win_honeycomb_cell,
    'rose_spoked': win_rose_spoked,
}
DOORS = {
    'dilating_aperture': door_dilating,
    'cycling_slab': door_cycling_slab,
    'scan_arch': door_scan_arch,
    'toll_gate': door_toll_gate,
    'blast_bulkhead': door_blast_bulkhead,
}
CROWNS = {
    'domed_cap': crown_domed_cap,
    'branched_canopy': crown_branched_canopy,
    'balcony_terrace': crown_planted_terrace,
    'renewable_crown': crown_renewable,
    'pore_vent_cap': crown_pore_vent_cap,
    'spired_cluster': crown_spired_cluster,
    'flare_stack': crown_flare_stack,
}
PROJECTIONS = {
    'translucent_canopy': proj_translucent_canopy,
    'slat_canopy': proj_slat_canopy,
    'cantilever_balcony': proj_cantilever_balcony,
    'signage_bracket': proj_signage_bracket,
    'hostile_ledge': proj_hostile_ledge,
    'entry_hood': proj_entry_hood,
    'transit_viaduct': proj_transit_viaduct,
}
STRUCTURES = {
    'branching_tree_column': col_tree_column,
    'mushroom_canopy_column': col_mushroom,
    'tapered_pier': col_tapered_pier,
    'buttress_fin': col_buttress_fin,
    'vine_rib_web': col_vine_rib_web,          # wall part (takes n)
    'strut_truss': col_strut_truss,
}
SIGN_REGISTERS = {
    'institutional_project': sign_wall_plaque,
    'government_aspirational': sign_arch_banner,
    'corporate_rebrand': sign_bracket_hanging,
    'picturesque_community': sign_monument,
}
SIGN_FORMS = {
    'regulatory_placard': signform_regulatory,
    'numeric_designator': signform_numeric,
    'status_readout': signform_status,
    'projected_floor_text': signform_floor_toll,
    'district_emblem': signform_emblems,
}
WALL_PARTS = {win_membrane_pore, win_capillary_pair, win_balcony_bay, win_drawer_band,
              win_shuttered, win_honeycomb_cell, win_rose_spoked,
              door_dilating, door_cycling_slab, door_scan_arch, door_toll_gate, door_blast_bulkhead,
              proj_translucent_canopy, proj_slat_canopy, proj_cantilever_balcony,
              proj_signage_bracket, proj_hostile_ledge, proj_entry_hood, proj_transit_viaduct,
              col_vine_rib_web}
