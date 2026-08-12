"""
gen_building.py — PARAMETRIC BUILDING GENERATOR (the §3 knob taxonomy of
ARCHITECTURE_FABLE_BUILD_SPEC.md). Buildings are presets over enumerated knobs;
each archetype must match its reference image in reference-images/architecture/.

First shipped archetype: plumbing_power_project (§4.3) —
  shell=spiral_organic_mass (tall lobed-column drum + external climbing trough-ramp +
  flanking piers) · crown=domed_cap+cupola · window=hairline_slit (capsule) ·
  door=service_hatch+entry_hood · furniture=rotary_valve_wheel×4 + ground stub ·
  sign=institutional_project · decay=ferric_bleed (seam-seeded, baked into tiles) ·
  emissive=terminal_green flow-strip + fluid_spill_glow.

Contract (skill rules): deterministic (helpers.h01, never randf), faceted low-poly,
32px/m box-projected pixel tiles, NEAR build_building + FAR build_building_far
impostor from the same params.

Run:  python /c/tmp/blsend.py < blender/skills/building-generation/gen_building.py
"""
import bpy, bmesh, math, sys, importlib
from mathutils import Vector

SKILL = r"C:\Users\quest\Programming\Games\ToRustAsWeFall\blender\skills\building-generation"
if SKILL not in sys.path: sys.path.insert(0, SKILL)
import helpers as H
importlib.reload(H)
import bld_kit as BK
importlib.reload(BK)

TAU = math.tau
def rad(d): return math.radians(d)

# ============================================================ PALETTE (sRGB 0..1)
TEAL   = (0.150, 0.255, 0.248)      # dark blue-leaning verdigris
TEAL_D = (0.092, 0.158, 0.152)
TEAL_L = (0.252, 0.330, 0.282)      # highlights toward olive-khaki
SEAMC  = (0.058, 0.094, 0.090)
RUST   = (0.300, 0.165, 0.085)      # burnt umber
RUST_L = (0.420, 0.245, 0.130)
RUST_D = (0.140, 0.075, 0.045)
CREAM  = (0.560, 0.480, 0.310)      # worn tan stencil
GREEN  = (0.360, 0.910, 0.500)      # terminal green #5ce87f
PAV    = (0.100, 0.112, 0.116)
PAV_S  = (0.034, 0.040, 0.044)
MOSS   = (0.055, 0.075, 0.050)
DARKGL = (0.012, 0.018, 0.020)

def mixc(a, b, t): return (a[0]+(b[0]-a[0])*t, a[1]+(b[1]-a[1])*t, a[2]+(b[2]-a[2])*t)
def shc(c, f): return (min(1, c[0]*f), min(1, c[1]*f), min(1, c[2]*f))

# ============================================================ PIXEL TILE FACTORY
def make_tile(name, T, painter, **kw):
    if name in bpy.data.images: bpy.data.images.remove(bpy.data.images[name])
    grid = [[(0.0, 0.0, 0.0, 1.0)] * T for _ in range(T)]  # grid[y][x], y=0 bottom
    painter(grid, T, **kw)
    img = bpy.data.images.new(name, T, T, alpha=True)
    px = [0.0] * (T * T * 4)
    for y in range(T):
        for x in range(T):
            c = grid[y][x]; k = (y * T + x) * 4
            px[k] = c[0]; px[k+1] = c[1]; px[k+2] = c[2]; px[k+3] = c[3]
    img.pixels = px; img.pack()
    return img

def p_shingle(grid, T, seed=0.0, rust=0.5):
    """Fine quilted scale plate (~0.25m) + superimposed 1m panel grid w/ rivets +
    seam-seeded ferric_bleed drips + crust patches at panel junctions (§3.8/§3.10)."""
    sw, sh = 8, 5
    for y in range(T):
        row = y // sh; ly = y % sh; off = (row % 2) * (sw // 2)
        for x in range(T):
            lx = (x - off) % sw; col = (x - off) // sw
            tv = 0.86 + 0.20 * H.h01(row * 7.31 + col * 3.17 + seed)
            c = shc(TEAL, tv)
            d = abs(lx - (sw - 1) / 2.0) / ((sw - 1) / 2.0)
            edge = int(round(1 + 2.0 * d * d))
            if ly == edge: c = SEAMC
            elif ly == edge + 1: c = shc(TEAL_L, tv * 0.90)
            elif ly < edge: c = shc(c, 0.80)
            if H.h01(x * 17.3 + y * 11.7 + seed * 7) < 0.05: c = shc(c, 0.72)  # grime speckle
            grid[y][x] = (c[0], c[1], c[2], 1.0)
    for s in (0, T // 2):                               # 1m panel grid + rivets
        for i in range(T):
            grid[s][i] = (SEAMC[0], SEAMC[1], SEAMC[2], 1.0)
            grid[i][s] = (SEAMC[0], SEAMC[1], SEAMC[2], 1.0)
        for i in range(4, T, 8):
            rv = shc(TEAL_L, 1.05)
            grid[(s + 1) % T][i] = (rv[0], rv[1], rv[2], 1.0)
            grid[i][(s + 1) % T] = (rv[0], rv[1], rv[2], 1.0)
    for b in range(3):                                  # crust patches at panel junctions
        cx = (T // 2) * int(H.h01(b * 3.1 + seed) * 2)
        cy = (T // 2) * int(H.h01(b * 7.7 + seed) * 2)
        r = 3 + int(H.h01(b * 4.3 + seed) * 5 * rust)
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if dx * dx + dy * dy <= r * r:
                    dd = (dx * dx + dy * dy) / (r * r + 0.1)
                    tgt = RUST_L if H.h01(b * 6.1 + dx + dy * 7) > 0.4 else RUST_D
                    bpx = grid[(cy + dy) % T][(cx + dx) % T]
                    m = mixc((bpx[0], bpx[1], bpx[2]), tgt, (1 - dd) * 0.55 * rust)
                    grid[(cy + dy) % T][(cx + dx) % T] = (m[0], m[1], m[2], 1.0)
    nd = int(4 + rust * 10)                             # drips seeded at the panel seams
    for dd in range(nd):
        x0 = int(H.h01(dd * 9.13 + seed * 3.1) * T)
        y0 = min(T - 1, (T // 2 if H.h01(dd * 1.7 + seed) < 0.5 else T) - 1 - int(H.h01(dd * 2.3) * 3))
        L = int(6 + H.h01(dd * 5.37 + seed) * T * 0.55 * rust)
        for i in range(L):
            y = y0 - i
            if y < 0: break
            f = (0.70 * (1.0 - i / max(1, L)) + 0.15)
            cols = ((0, f), (1, f * 0.5)) if i < L * 0.5 else ((0, f),)   # taper
            for xo, ff in cols:
                x = (x0 + xo) % T
                b = grid[y][x]
                m = mixc((b[0], b[1], b[2]), RUST, ff)
                grid[y][x] = (m[0], m[1], m[2], 1.0)

def p_metal(grid, T, seed=0.0):
    """Teal facility metal: brushed verticals, course seam, rivets, rust specks."""
    for y in range(T):
        for x in range(T):
            f = 1.0 + 0.05 * ((x * 5 + x // 3) % 3 - 1)
            c = shc(TEAL, f * (0.90 + 0.12 * H.h01(x * 3.3 + y * 7.7 + seed)))
            if y == T - 1: c = SEAMC
            if y == 0: c = shc(TEAL, 0.76)
            grid[y][x] = (c[0], c[1], c[2], 1.0)
    for (cx, cy) in ((2, 2), (T - 3, 2), (2, T - 3), (T - 3, T - 3), (T // 2, T // 2)):
        grid[cy][cx] = (TEAL_L[0], TEAL_L[1], TEAL_L[2], 1.0)
        grid[(cy - 1) % T][cx] = (SEAMC[0], SEAMC[1], SEAMC[2], 1.0)
    for i in range(12):
        x = int(H.h01(i * 3.1 + seed) * T); y = int(H.h01(i * 7.9 + seed * 2) * T)
        grid[y][x] = (RUST[0], RUST[1], RUST[2], 1.0)

def p_rust(grid, T, seed=0.0):
    """Rusted iron for pipes / wheels / trough ribs."""
    for y in range(T):
        for x in range(T):
            f = 0.8 + 0.32 * H.h01(x * 5.1 + y * 3.7 + seed)
            c = shc(RUST, f)
            grid[y][x] = (c[0], c[1], c[2], 1.0)
    for b in range(10):
        cx = int(H.h01(b * 4.7 + seed) * T); cy = int(H.h01(b * 8.3 + seed) * T)
        r = 2 + int(H.h01(b * 2.9) * 4)
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if dx * dx + dy * dy <= r * r:
                    dd = (dx * dx + dy * dy) / (r * r + 0.1)
                    tgt = RUST_L if H.h01(b * 6.1 + dx + dy * 7) > 0.35 else RUST_D
                    m = mixc(tgt, RUST, dd)
                    grid[(cy + dy) % T][(cx + dx) % T] = (m[0], m[1], m[2], 1.0)

def p_grate(grid, T, seed=0.0):
    """Fine mesh grating with real alpha holes (trough parapet)."""
    bar = mixc(TEAL_D, RUST_D, 0.55)
    for y in range(T):
        for x in range(T):
            on = (x % 4 < 1) or (y % 4 < 1)
            if on:
                top = (x % 8 == 0) or (y % 8 == 0)
                c = shc(bar, 1.2 if top else 0.85)
                grid[y][x] = (c[0], c[1], c[2], 1.0)
            else:
                grid[y][x] = (0, 0, 0, 0.0)

def p_paving(grid, T, seed=0.0, moss=0.35):
    """Big flagstones, staggered, damp; moss specks."""
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
            grid[y][x] = (c[0], c[1], c[2], 1.0)

# ============================================================ MATERIALS
def tile_mat(name, img, tile_m=1.0, rough=0.85, metal=0.0, alpha=False):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes.get('Principled BSDF')
    b.inputs['Roughness'].default_value = rough; b.inputs['Metallic'].default_value = metal
    tc = nt.nodes.new('ShaderNodeTexCoord'); tc.location = (-700, 0)
    mp = nt.nodes.new('ShaderNodeMapping'); mp.location = (-500, 0)
    mp.inputs['Scale'].default_value = (1.0 / tile_m, 1.0 / tile_m, 1.0 / tile_m)
    ti = nt.nodes.new('ShaderNodeTexImage'); ti.location = (-300, 0)
    ti.image = img; ti.interpolation = 'Closest'; ti.projection = 'BOX'; ti.projection_blend = 0.2
    nt.links.new(tc.outputs['Object'], mp.inputs['Vector'])
    nt.links.new(mp.outputs['Vector'], ti.inputs['Vector'])
    nt.links.new(ti.outputs['Color'], b.inputs['Base Color'])
    if alpha:
        nt.links.new(ti.outputs['Alpha'], b.inputs['Alpha']); H.alpha_flags(m)
    return m

def emis_mat(name, col, strength):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes): nt.nodes.remove(n)
    out = nt.nodes.new('ShaderNodeOutputMaterial'); out.location = (200, 0)
    em = nt.nodes.new('ShaderNodeEmission')
    em.inputs['Color'].default_value = (col[0], col[1], col[2], 1.0)
    em.inputs['Strength'].default_value = strength
    nt.links.new(em.outputs[0], out.inputs[0])
    return m

def build_mats():
    M = {}
    M['shingle'] = tile_mat('shingle', make_tile('t_shingle', 64, p_shingle, seed=1.0, rust=1.0), tile_m=2.0)
    M['shingle_lite'] = tile_mat('shingle_lite', make_tile('t_shingle_l', 64, p_shingle, seed=4.0, rust=0.4), tile_m=2.0)
    M['metal'] = tile_mat('metal_teal', make_tile('t_metal', 32, p_metal, seed=2.0), tile_m=1.0)
    M['rust'] = tile_mat('rust_iron', make_tile('t_rust', 32, p_rust, seed=3.0), tile_m=1.0, rough=0.9)
    M['grate'] = tile_mat('grate', make_tile('t_grate', 32, p_grate), tile_m=1.0, rough=0.8, alpha=True)
    M['paving'] = tile_mat('paving', make_tile('t_paving', 64, p_paving, seed=5.0), tile_m=3.2, rough=0.18)
    M['dark'] = H.matp('dark_inset', DARKGL, rough=0.95)
    M['moss'] = H.matp('moss', MOSS, rough=0.95)
    M['cream'] = H.matp('cream', CREAM, rough=0.7)
    M['teal_flat'] = H.matp('teal_flat', (0.115, 0.175, 0.155), rough=0.8)
    M['teal_dark'] = H.matp('teal_dark', TEAL_D, rough=0.85)
    M['trim'] = H.matp('trim_verdigris', shc(TEAL_L, 0.78), rough=0.75)
    M['fluid'] = emis_mat('fluid_green', (0.32, 0.88, 0.44), 3.5)
    M['fluid_dim'] = emis_mat('fluid_dim', mixc(GREEN, (0, 0, 0), 0.3), 1.2)
    M['pool'] = emis_mat('pool_green', mixc(GREEN, (0.01, 0.04, 0.02), 0.5), 1.0)
    M['screen'] = emis_mat('screen_green', GREEN, 1.8)
    return M

# ============================================================ GEOMETRY UTILS
def bx(bm, cx, cy, cz, sx, sy, sz):
    """Axis-aligned box, centre (cx,cy,cz), full sizes."""
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    v = [bm.verts.new((cx + a * hx, cy + b * hy, cz + c * hz))
         for (a, b, c) in ((-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1))]
    for f in ((0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)):
        bm.faces.new([v[i] for i in f])
    return v

def prism(bm, pts, z0, z1):
    """Closed 2D outline in XY, extruded z0..z1."""
    lo = [bm.verts.new((p[0], p[1], z0)) for p in pts]
    hi = [bm.verts.new((p[0], p[1], z1)) for p in pts]
    n = len(pts)
    try: bm.faces.new(list(reversed(lo)))
    except Exception: pass
    try: bm.faces.new(hi)
    except Exception: pass
    for i in range(n):
        bm.faces.new([lo[i], lo[(i + 1) % n], hi[(i + 1) % n], hi[i]])

def sweep(bm, frames, prof, scales=None, cap0=True, cap1=True):
    """frames: list of (origin, u, v). prof: closed 2D polygon [(a,b)]. Rings bridged."""
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

def place(o, loc, n=None):
    o.location = loc
    if n is not None:
        o.rotation_euler = Vector(n).to_track_quat('Z', 'Y').to_euler()

# ============================================================ SHELL: lobed lathe drum
class Shell:
    """spiral_organic_mass drum: profile lathe with tall vertical melted-column lobes.
    The lobe bump is (0.5+0.5cos)^sharp — sharp>1 narrows the pods and opens deep
    grooves between them (the ref's near-vertical buttress-column feet)."""
    def __init__(self, profile, seg=48, lobe_n=8, lobe_amp=0.17, lobe_top=7.0,
                 lobe_sharp=1.8, macro_amp=0.04, macro_top=6.0, phase_az=286.0):
        self.profile = profile; self.seg = seg
        self.lobe_n = lobe_n; self.lobe_amp = lobe_amp; self.lobe_top = lobe_top
        self.lobe_sharp = lobe_sharp
        self.macro_amp = macro_amp; self.macro_top = macro_top
        self.ph = rad(phase_az)

    def base_r(self, h):
        P = self.profile
        if h <= P[0][0]: return P[0][1]
        for i in range(len(P) - 1):
            (h0, r0), (h1, r1) = P[i], P[i + 1]
            if h0 <= h <= h1:
                t = (h - h0) / max(1e-6, h1 - h0)
                return r0 + (r1 - r0) * t
        return P[-1][1]

    def amp(self, h):
        return self.lobe_amp * max(0.0, 1.0 - h / self.lobe_top) + 0.012

    def mamp(self, h):
        return self.macro_amp * max(0.0, 1.0 - h / self.macro_top)

    def radial(self, az, h):
        th = rad(az)
        bump = (0.5 + 0.5 * math.cos(self.lobe_n * (th - self.ph))) ** self.lobe_sharp
        m = (1.0 + self.amp(h) * bump
             + self.mamp(h) * math.cos(2 * (th - self.ph) + 0.8))
        return self.base_r(h) * m

    def surf(self, az, h, extra=0.0):
        th = rad(az); r = self.radial(az, h) + extra
        return Vector((r * math.cos(th), r * math.sin(th), h))

    def normal(self, az, h):
        th = rad(az)
        dr = (self.radial(az, h + 0.25) - self.radial(az, h - 0.25)) / 0.5
        n = Vector((math.cos(th), math.sin(th), -dr)); n.normalize()
        return n

    def build(self, name, mat, apex_h):
        bm = bmesh.new(); rings = []
        for (h, r) in self.profile:
            ring = []
            for j in range(self.seg):
                az = j / self.seg * 360.0
                rr = self.radial(az, h)
                th = rad(az)
                ring.append(bm.verts.new((rr * math.cos(th), rr * math.sin(th), h)))
            rings.append(ring)
        for i in range(len(rings) - 1):
            for k in range(self.seg):
                bm.faces.new([rings[i][k], rings[i][(k+1) % self.seg],
                              rings[i+1][(k+1) % self.seg], rings[i+1][k]])
        apex = bm.verts.new((0, 0, apex_h))
        top = rings[-1]
        for k in range(self.seg):
            bm.faces.new([top[k], top[(k+1) % self.seg], apex])
        bot = rings[0]; base = bm.verts.new((0, 0, -0.25))
        for k in range(self.seg):
            bm.faces.new([bot[(k+1) % self.seg], bot[k], base])
        return H.finish(bm, name, mat)

# ============================================================ TROUGH (spiral ramp)
TS = 0.90                                                # global trough scale
TR_PROF = [(a * TS, b * TS) for (a, b) in
           [(-0.95, 0.50), (-1.02, -0.18), (-0.66, -0.60), (0.0, -0.74), (0.66, -0.60),
            (1.02, -0.18), (0.95, 0.50), (0.70, 0.50), (0.60, -0.26), (0.0, -0.42),
            (-0.60, -0.26), (-0.70, 0.50)]]
FL_PROF = [(a * TS, b * TS) for (a, b) in
           [(-0.56, 0.36), (0.56, 0.36), (0.56, 0.48), (-0.56, 0.48)]]

def build_trough(shell, M, spec, objs, lights):
    n = spec.get('stations', 96)
    az0, az1 = spec['az0'], spec['az1']
    h0, h1 = spec['h0'], spec['h1']
    off0 = spec.get('clearance', 1.05)
    frames = []; scales = []; meta = []
    for i in range(n):
        t = i / (n - 1)
        az = az0 + (az1 - az0) * t
        h = h0 + (h1 - h0) * (t ** 0.7)                # eased: steep climb across the front
        ro = off0 - 0.8 * H.smooth((t - 0.6) / 0.4)    # top wrap hugs in under the cornice
        if t > 0.93:                                   # plunge into the wall
            k = H.smooth((t - 0.93) / 0.025)
            ro = ro + (-2.0 - ro) * min(1.0, k)
        R = shell.radial(az, h) + ro
        th = rad(az)
        o = Vector((R * math.cos(th), R * math.sin(th), h))
        u = Vector((math.cos(th), math.sin(th), 0.0))
        v = Vector((0.0, 0.0, 1.0))
        s = 1.0
        if i == 0: s = 0.45
        elif i == 1: s = 0.80
        if 0.88 < t < 0.93: s = 1.08                   # entry collar
        frames.append((o, u, v)); scales.append(s); meta.append((az, h, t, R))
    bm = bmesh.new()
    sweep(bm, frames, TR_PROF, scales)
    objs.append(H.finish(bm, "PPP_trough", M['metal']))
    # fluid strip riding high in the channel (visible sliver + glow through the mesh)
    bm = bmesh.new()
    fi = [i for i in range(2, n) if meta[i][2] < 0.935]
    sweep(bm, [frames[i] for i in fi], FL_PROF, cap0=True, cap1=True)
    objs.append(H.finish(bm, "PPP_trough_fluid", M['fluid']))
    # ribs (segmented underside)
    bm = bmesh.new()
    for i in range(3, n - 4, 5):
        fr = [frames[i], frames[i + 1]]
        sweep(bm, fr, TR_PROF, [1.07, 1.07])
    objs.append(H.finish(bm, "PPP_trough_ribs", M['rust']))
    # parapet: mesh panels + posts + flat cap, lower passes only
    bm = bmesh.new(); bmp = bmesh.new()
    rail_h = 0.50; side_off = 0.825 * TS; rim_top = 0.5 * TS
    for side in (-side_off, side_off):
        for i in range(2, n - 1):
            if meta[i][2] > 0.55: continue             # top wrap runs bare under the eave
            (o0, u0, v0), (o1, u1, v1) = frames[i], frames[i + 1]
            p0 = o0 + u0 * side + v0 * rim_top
            p1 = o1 + u1 * side + v1 * rim_top
            a = bm.verts.new(p0); b = bm.verts.new(p1)
            c = bm.verts.new(p1 + Vector((0, 0, rail_h))); d = bm.verts.new(p0 + Vector((0, 0, rail_h)))
            bm.faces.new([a, b, c, d])
            up = Vector((0, 0, rail_h))
            a2 = bmp.verts.new(p0 + up + u0 * 0.03); b2 = bmp.verts.new(p1 + up + u1 * 0.03)
            c2 = bmp.verts.new(p1 + up - u1 * 0.03); d2 = bmp.verts.new(p0 + up - u0 * 0.03)
            bmp.faces.new([a2, b2, c2, d2])
            if i % 4 == 0:
                bx(bmp, p0.x, p0.y, p0.z + rail_h / 2, 0.05, 0.05, rail_h)
    objs.append(H.finish(bm, "PPP_trough_rail", M['grate']))
    objs.append(H.finish(bmp, "PPP_trough_posts", M['teal_dark']))
    # brackets to the drum
    for i in range(6, n - 10, 7):
        az, h, t, R = meta[i]
        if h < 9.0 and 260 < (az % 360) < 296: continue   # keep the sign face clear
        th = rad(az)
        wall = shell.radial(az, h - 0.5)
        inner = R - 1.0 * TS
        L = inner - wall + 0.4
        if L < 0.3: continue
        cx = (wall - 0.2 + inner) / 2
        ux, uy = math.cos(th), math.sin(th)
        c = Vector((cx * ux, cx * uy, h - 0.5))
        b2 = bmesh.new()
        bx(b2, 0, 0, 0, L, 0.22, 0.30)
        for vv in b2.verts:
            x, y, z = vv.co
            vv.co = Vector((c.x + x * ux - y * uy, c.y + x * uy + y * ux, c.z + z))
        b2m = bpy.data.meshes.new("brk"); b2.to_mesh(b2m); b2.free()
        for p in b2m.polygons: p.use_smooth = False
        ob = bpy.data.objects.new("PPP_bracket", b2m)
        bpy.context.scene.collection.objects.link(ob)
        ob.data.materials.append(M['teal_dark'])
        objs.append(ob)
    # glow lights along the fluid (green wash onto walls + mesh)
    for tt in (0.18, 0.45, 0.72):
        i = int(tt * (n - 1)); o = frames[i][0]
        lights.append(('POINT', o + Vector((0, 0, 0.5)), GREEN, 20, 0.5))
    # drips of glowing fluid: below the nose and below the wall entry
    bm = bmesh.new()
    az_n, h_n = meta[0][0], meta[0][1]
    p = shell.surf(az_n, h_n - 1.1, 0.06)
    bx(bm, p.x, p.y, p.z - 0.6, 0.06, 0.06, 1.6)
    az_e = az0 + (az1 - az0) * 0.94; h_e = h0 + (h1 - h0) * (0.94 ** 0.7)
    p = shell.surf(az_e, h_e - 1.0, 0.05)
    bx(bm, p.x, p.y, p.z - 0.7, 0.05, 0.05, 1.5)
    objs.append(H.finish(bm, "PPP_drips", M['fluid_dim']))

# ============================================================ PARTS
def slit_window(shell, M, objs, az, h, w=0.32, tall=1.7, dark_arch=False):
    """Capsule slit (rounded BOTH ends): trim ring proud of the wall, dark pane a
    hair prouder than the ring face so the slit reads as an opening."""
    n = shell.normal(az, h)
    mats = (M['dark'], M['dark']) if dark_arch else (M['trim'], M['dark'])
    for (grow, depth, back, mat) in ((0.055, 0.20, -0.19, mats[0]),
                                     (-0.04, 0.11, -0.09, mats[1])):
        w2 = w / 2 + grow; t2 = tall / 2 + grow; ch = max(0.06, w * 0.55 + grow)
        pts = [(-w2 + ch * 0.7, -t2), (w2 - ch * 0.7, -t2), (w2, -t2 + ch),
               (w2, t2 - ch), (w2 - ch * 0.7, t2),
               (-w2 + ch * 0.7, t2), (-w2, t2 - ch), (-w2, -t2 + ch)]
        bm = bmesh.new(); prism(bm, pts, 0.0, depth)
        o = H.finish(bm, "PPP_win", mat)
        place(o, shell.surf(az, h, back), n)
        objs.append(o)

def valve_wheel(M, objs, loc, n, R=0.55, seed=0.0, standoff=0.18):
    bm = bmesh.new()
    NS = 12; tube = 0.05 + R * 0.06
    prof = [(tube, tube), (tube, -tube), (-tube, -tube), (-tube, tube)]
    frames = []
    for k in range(NS + 1):
        a = k / NS * TAU
        c = Vector((math.cos(a) * R, math.sin(a) * R, 0))
        u = Vector((math.cos(a), math.sin(a), 0)); v = Vector((0, 0, 1))
        frames.append((c, u, v))
    sweep(bm, frames, prof, cap0=False, cap1=False)
    ns = 4 + int(H.h01(seed * 3.7) * 2)
    for k in range(ns):
        a = k / ns * TAU + seed
        ux, uy = math.cos(a), math.sin(a)
        b2 = []
        for (rr, tt) in ((0.07, 0.05), (R - 0.02, 0.04)):
            for (sy, sz) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                b2.append(bm.verts.new((ux * rr - uy * sy * tt, uy * rr + ux * sy * tt, sz * tt)))
        for f in ((0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7),(3,2,1,0)):
            try: bm.faces.new([b2[i] for i in f])
            except Exception: pass
    cyl(bm, (0, 0, -0.08), (0, 0, 0.08), 0.11, 8)
    cyl(bm, (0, 0, -standoff - 0.05), (0, 0, 0), 0.06, 6)
    o = H.finish(bm, "PPP_wheel", M['rust'])
    place(o, loc, n)
    objs.append(o)

def wall_pipe(shell, M, objs, az, h_top, h_bot, r=0.30):
    """A pipe that HUGS the drum: a polyline following the profile at +0.45."""
    th = rad(az); ux, uy = math.cos(th), math.sin(th)
    def P(hh, extra=0.45):
        rr = shell.radial(az, hh) + extra
        return Vector((rr * ux, rr * uy, hh))
    bm = bmesh.new()
    hs = [h_bot + 0.9]
    hh = h_bot + 1.5
    while hh < h_top - 0.4:
        hs.append(hh); hh += 1.5
    hs.append(h_top)
    for i in range(len(hs) - 1):
        cyl(bm, P(hs[i]), P(hs[i + 1]), r)
    for i in range(1, len(hs) - 1, 2):                  # flange couplings at joints
        p = P(hs[i]); d = (P(hs[i + 1]) - P(hs[i - 1])).normalized()
        cyl(bm, p - d * 0.12, p + d * 0.12, r + 0.10)
    cyl(bm, P(h_top), P(h_top) + Vector((0, 0, 0.22)), r + 0.1)   # top cap
    p0 = P(h_bot + 0.9)                                            # bottom elbow to ground
    p1 = Vector((p0.x + ux * 0.55, p0.y + uy * 0.55, h_bot + 0.35))
    p2 = Vector((p0.x + ux * 1.1, p0.y + uy * 1.1, h_bot + 0.18))
    cyl(bm, p0, p1, r); cyl(bm, p1, p2, r)
    cyl(bm, p2, p2 + Vector((0, 0, -0.6)), r)
    cyl(bm, p2 + Vector((0, 0, -0.35)), p2 + Vector((0, 0, -0.15)), r + 0.1)
    objs.append(H.finish(bm, "PPP_pipe", M['rust']))
    hv = h_bot + 4.6
    stub = P(hv)
    bm = bmesh.new()
    cyl(bm, stub, stub + Vector((ux * 0.30, uy * 0.30, 0)), 0.09, 6)
    cyl(bm, stub + Vector((ux * 0.05, uy * 0.05, 0)), stub + Vector((ux * 0.12, uy * 0.12, 0)), 0.30, 10)
    objs.append(H.finish(bm, "PPP_pipe_stub", M['rust']))
    valve_wheel(M, objs, stub + Vector((ux * 0.38, uy * 0.38, 0)), Vector((ux, uy, 0)), R=0.40, seed=9.0, standoff=0.05)

def sign_panel(shell, M, objs, az, h, wtxt, wpan=2.9, hpan=2.2):
    n = shell.normal(az, h)
    bm = bmesh.new()
    bx(bm, 0, 0, 0.07, wpan, hpan, 0.14)
    o = H.finish(bm, "PPP_sign", M['metal'])
    place(o, shell.surf(az, h, 0.10), n)
    objs.append(o)
    bm = bmesh.new()
    for (sx, sy, px, py) in ((wpan, 0.12, 0, hpan / 2), (wpan, 0.12, 0, -hpan / 2),
                             (0.12, hpan, wpan / 2, 0), (0.12, hpan, -wpan / 2, 0)):
        bx(bm, px, py, 0.13, sx + 0.12, sy + 0.02, 0.10)
    o = H.finish(bm, "PPP_sign_border", M['rust'])
    place(o, shell.surf(az, h, 0.10), n)
    objs.append(o)
    c = bpy.data.curves.new("PPP_sign_text", 'FONT')
    c.body = wtxt; c.align_x = 'CENTER'; c.align_y = 'CENTER'
    c.size = 0.50; c.space_line = 1.18; c.extrude = 0.02
    to = bpy.data.objects.new("PPP_sign_text", c)
    bpy.context.scene.collection.objects.link(to)
    to.data.materials.append(M['cream'])
    place(to, shell.surf(az, h, 0.26), n)
    objs.append(to)

def entry(shell, M, objs, lights, az, w=1.3, ht=2.4):
    n = shell.normal(az, ht / 2)
    th = rad(az); ux, uy = math.cos(th), math.sin(th)
    bm = bmesh.new()
    bx(bm, 0, 0, 0.0, w + 0.5, ht + 0.4, 0.9)          # frame block
    o = H.finish(bm, "PPP_door_frame", M['metal'])
    place(o, shell.surf(az, ht / 2 + 0.1, -0.35), n); objs.append(o)
    bm = bmesh.new()
    bx(bm, 0, 0, 0.0, w, ht, 0.9)                       # deep dark recess
    o = H.finish(bm, "PPP_door_inset", M['dark'])
    place(o, shell.surf(az, ht / 2 + 0.1, -0.72), n); objs.append(o)
    # console cabinet tucked INSIDE the recess: 0.8w x 1.6h, lit green screen
    # (placed-prism local frame: X=width, Y=up, Z=outward)
    base = shell.surf(az, 0.0, -0.55)
    bm = bmesh.new()
    bx(bm, 0, 0.8, 0.19, 0.8, 1.6, 0.38)                # cabinet body
    bx(bm, 0, 1.5, 0.33, 0.86, 0.18, 0.50)              # visor ledge over the screen
    o = H.finish(bm, "PPP_console", M['teal_dark'])
    place(o, base, n); objs.append(o)
    bm = bmesh.new()
    bx(bm, 0, 0, 0.0, 0.56, 0.62, 0.03)
    o = H.finish(bm, "PPP_screen", M['screen'])
    o.location = base + Vector((ux * 0.42, uy * 0.42, 1.05))
    o.rotation_euler = Vector((ux, uy, 0.22)).to_track_quat('Z', 'Y').to_euler()
    objs.append(o)
    lights.append(('POINT', base + Vector((ux * 0.7, uy * 0.7, 1.3)), GREEN, 18, 0.4))
    # entry_hood: prominent faceted tent-hood over the door, anchored to the DOOR face
    bm = bmesh.new()
    apex = Vector((0, ht + 1.35, 0.05))
    rim = [Vector((math.sin(rad(a)) * (w / 2 + 0.75), ht + 0.24, math.cos(rad(a)) * 1.45))
           for a in (-75, -45, -15, 15, 45, 75)]
    for i in range(len(rim) - 1):
        bm.faces.new([bm.verts.new(apex), bm.verts.new(rim[i]), bm.verts.new(rim[i + 1])])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.001)
    bmesh.ops.solidify(bm, geom=bm.faces[:] + bm.verts[:] + bm.edges[:], thickness=0.08)
    o = H.finish(bm, "PPP_hood", M['shingle_lite'])
    pd = shell.surf(az, 1.6, -0.30)
    place(o, Vector((pd.x, pd.y, 0.15)), n)
    objs.append(o)

def spill(shell, M, objs, lights, az):
    """fluid_spill_glow: tall niche + glowing figure + stepped cascade + pool."""
    n = shell.normal(az, 1.6)
    th = rad(az); ux, uy = math.cos(th), math.sin(th)
    bm = bmesh.new(); bx(bm, 0, 0, 0.0, 1.5, 2.4, 0.55)
    o = H.finish(bm, "PPP_niche_frame", M['metal'])
    place(o, shell.surf(az, 1.75, -0.22), n); objs.append(o)
    bm = bmesh.new(); bx(bm, 0, 0, 0.0, 1.15, 2.05, 0.55)
    o = H.finish(bm, "PPP_niche_dark", M['dark'])
    place(o, shell.surf(az, 1.72, -0.40), n); objs.append(o)
    # glowing figure in the niche (~1.9 m)
    bm = bmesh.new()
    for (hh, rr) in ((0.35, 0.22), (0.75, 0.17), (1.15, 0.20), (1.5, 0.13), (1.75, 0.10)):
        cyl(bm, (0, 0, hh - 0.22), (0, 0, hh + 0.16), rr, 6)
    o = H.finish(bm, "PPP_spill_fig", M['fluid'])
    b = shell.surf(az, 0.9, -0.34)
    o.location = Vector((b.x, b.y, 0.55)); objs.append(o)
    # steps + cascading fluid + pool at the foot of the steps
    bm = bmesh.new(); bmf = bmesh.new()
    wall = shell.radial(az, 0.4)
    for i, (out, top) in enumerate(((0.42, 0.66), (0.92, 0.46), (1.42, 0.28), (1.9, 0.12))):
        cx = wall + out
        bx(bm, cx * ux, cx * uy, top / 2, 0.6, 1.05, top)
        bx(bmf, cx * ux, cx * uy, top + 0.012, 0.26, 0.45, 0.025)
        bx(bmf, (cx + 0.25) * ux, (cx + 0.25) * uy, top / 2 + 0.02, 0.04, 0.3, top + 0.02)
    objs.append(H.finish(bm, "PPP_steps", M['paving']))
    objs.append(H.finish(bmf, "PPP_step_fluid", M['fluid']))
    bm = bmesh.new()
    pc = Vector(((wall + 2.75) * ux, (wall + 2.75) * uy, 0.02))
    ring = []
    for i in range(11):
        a = i / 11 * TAU
        rr = 0.8 * (0.7 + 0.55 * H.h01(i * 3.3 + 1.0))
        ring.append(bm.verts.new(pc + Vector((math.cos(a) * rr, math.sin(a) * rr, 0))))
    bm.faces.new(ring)
    objs.append(H.finish(bm, "PPP_pool", M['pool']))
    lights.append(('POINT', pc + Vector((0, 0, 0.8)), GREEN, 45, 0.7))
    lights.append(('POINT', Vector((b.x, b.y, 1.7)), GREEN, 22, 0.5))

def ground_stub(shell, M, objs, az, length=2.2):
    th = rad(az); ux, uy = math.cos(th), math.sin(th)
    wall = shell.radial(az, 0.5)
    bm = bmesh.new()
    p0 = Vector(((wall - 0.3) * ux, (wall - 0.3) * uy, 0.55))
    p1 = Vector(((wall + length) * ux, (wall + length) * uy, 0.55))
    cyl(bm, p0, p1, 0.20)
    cyl(bm, p1 - Vector((ux * 0.35, uy * 0.35, 0)), p1 - Vector((ux * 0.12, uy * 0.12, 0)), 0.29)
    objs.append(H.finish(bm, "PPP_stub", M['rust']))
    valve_wheel(M, objs, p1 + Vector((ux * 0.12, uy * 0.12, 0)), Vector((ux, uy, 0)), R=0.60, seed=17.0, standoff=0.07)

def cupola(M, objs, base_h):
    bm = bmesh.new()
    rows = [(base_h - 0.28, 0.55), (base_h - 0.1, 0.66), (base_h + 0.55, 0.62), (base_h + 0.68, 0.5)]
    SEG = 10; rings = []
    for (h, r) in rows:
        rings.append([bm.verts.new((math.cos(k / SEG * TAU) * r, math.sin(k / SEG * TAU) * r, h)) for k in range(SEG)])
    for phi in (25, 50, 75):
        r = 0.5 * math.cos(rad(phi)); h = base_h + 0.68 + 0.5 * math.sin(rad(phi))
        rings.append([bm.verts.new((math.cos(k / SEG * TAU) * r, math.sin(k / SEG * TAU) * r, h)) for k in range(SEG)])
    for i in range(len(rings) - 1):
        for k in range(SEG):
            bm.faces.new([rings[i][k], rings[i][(k+1) % SEG], rings[i+1][(k+1) % SEG], rings[i+1][k]])
    apex = bm.verts.new((0, 0, base_h + 1.22))
    for k in range(SEG):
        bm.faces.new([rings[-1][k], rings[-1][(k+1) % SEG], apex])
    cyl(bm, (0, 0, base_h + 1.18), (0, 0, base_h + 1.38), 0.05, 6)
    cyl(bm, (0, 0, base_h + 1.38), (0, 0, base_h + 1.52), 0.11, 6)
    objs.append(H.finish(bm, "PPP_cupola", M['metal']))

def wing(shell, M, objs, foot_az, foot_dist, foot_r, top_az, top_h, top_r, bulge=1.2):
    p0 = Vector((math.cos(rad(foot_az)) * foot_dist, math.sin(rad(foot_az)) * foot_dist, -0.5))
    p2 = shell.surf(top_az, top_h, -0.9)
    mid = (p0 + p2) / 2
    outd = Vector((mid.x, mid.y, 0)).normalized()
    p1 = mid + outd * bulge + Vector((0, 0, -0.4))
    def bez(t):
        a = p0.lerp(p1, t); b = p1.lerp(p2, t); return a.lerp(b, t)
    frames = []; scales = []
    NS = 9
    for i in range(NS):
        t = i / (NS - 1)
        o = bez(t)
        tan = ((p1 - p0) * (1 - t) + (p2 - p1) * t).normalized()
        u = tan.cross(Vector((0, 0, 1)))
        if u.length < 1e-4: u = Vector((1, 0, 0))
        u.normalize(); v = tan.cross(u).normalized()
        frames.append((o, u, v))
        scales.append(foot_r + (top_r - foot_r) * H.smooth(t))
    prof = [(math.cos(k / 12 * TAU), math.sin(k / 12 * TAU)) for k in range(12)]
    bm = bmesh.new()
    sweep(bm, frames, prof, scales)
    objs.append(H.finish(bm, "PPP_wing", M['shingle_lite']))

def roof_clutter(shell, M, objs, spots):
    """Small sheds + flanged vent stacks around the dome base."""
    bmb = bmesh.new(); bms = bmesh.new()
    for spot in spots:
        az, h, s, kind = spot
        if kind == 'stack':
            p = shell.surf(az, h, -0.4)
            cyl(bms, (p.x, p.y, h - 0.3), (p.x, p.y, h + 1.7), 0.18)
            for fh in (h + 0.4, h + 1.1):
                cyl(bms, (p.x, p.y, fh), (p.x, p.y, fh + 0.14), 0.26)
            cyl(bms, (p.x, p.y, h + 1.7), (p.x, p.y, h + 1.85), 0.28)
        else:
            p = shell.surf(az, h, -0.6)
            bx(bmb, p.x, p.y, p.z - 0.15 + s * 0.5, s * 0.9, s * 0.9, s)
            bx(bmb, p.x, p.y, p.z - 0.15 + s + 0.07, s * 1.1, s * 1.1, 0.14)
    objs.append(H.finish(bmb, "PPP_vents", M['teal_dark']))
    objs.append(H.finish(bms, "PPP_stacks", M['rust']))

# ============================================================ SHELL: drawer_stack_monolith
def p_rack(grid, T, seed=0.0):
    """Server-rack bay: unit rows with terminal-green LED dots (emissive via tile_mat)."""
    unit_h = 9
    for y in range(T):
        row = y // unit_h; ly = y % unit_h
        for x in range(T):
            c = shc((0.030, 0.052, 0.050), 0.85 + 0.3 * H.h01(x * 3.7 + row * 9.1 + seed))
            if ly == 0: c = shc(TEAL_D, 0.85)                     # shelf rail
            elif ly == 1: c = shc(TEAL_D, 1.15)
            if x % 32 in (0, 1): c = shc(TEAL_D, 0.9)             # column rail
            grid[y][x] = (c[0], c[1], c[2], 1.0)
        if 2 < ly < 7:                                            # LED dots
            for x in range(3, T, 4):
                hv = H.h01(x * 7.3 + row * 3.9 + seed * 2)
                if hv < 0.30:
                    g = GREEN if hv < 0.24 else (0.95, 0.65, 0.25)
                    f = 0.5 + 0.5 * H.h01(x * 1.7 + row)
                    grid[y][x] = (g[0] * f, g[1] * f, g[2] * f, 1.0)

def obox(bm, c, u, v, wu, tv, hz):
    """Oriented box: centre c, tangential axis u (width wu), radial axis v (thick tv), height hz."""
    pts = [c + u * (su * wu / 2) + v * (sv * tv / 2) for (su, sv) in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    lo = [bm.verts.new((p.x, p.y, c.z - hz / 2)) for p in pts]
    hi = [bm.verts.new((p.x, p.y, c.z + hz / 2)) for p in pts]
    try: bm.faces.new(list(reversed(lo))); bm.faces.new(hi)
    except Exception: pass
    for i in range(4):
        bm.faces.new([lo[i], lo[(i + 1) % 4], hi[(i + 1) % 4], hi[i]])

FIN_PROF = [(-0.30, -0.5), (0.30, -0.5), (0.5, -0.28), (0.5, 0.28),
            (0.30, 0.5), (-0.30, 0.5), (-0.5, 0.28), (-0.5, -0.28)]

def build_monolith(P, objs, lights):
    """Open Files: a radial ring of tapered RACK-FINS around a core, server-rack
    channels between them, canted stepped tips as the crown, cyan lit-tunnel entry."""
    MK = BK.build_mats()
    MK['rack'] = BK.tile_mat('rack_bay', BK.make_tile('t_rack', 64, p_rack, seed=3.0), tile_m=2.0, rough=0.6, emis=1.3)
    N = P.get('fins', 14)
    front = P['front_az']
    base_z = 0.55
    fins = []                                            # (az, rb, rt, h, w, d)
    for i in range(N):
        az = i * 360.0 / N + (H.h01(i * 3.13) - 0.5) * 8.0
        dd = (az - front + 180) % 360 - 180
        if abs(dd) < 13.0:                               # portal gap
            az = front + 16.0 * (1 if dd >= 0 else -1)
        h = 11.8 + 5.2 * H.h01(i * 7.71)
        rb = P.get('r_base', 5.6) + (H.h01(i * 5.3) - 0.5) * 0.7
        rt = P.get('r_top', 3.1) + (H.h01(i * 9.9) - 0.5) * 0.5
        w = 1.05 + 0.40 * H.h01(i * 2.7)
        d = 1.60 + 0.40 * H.h01(i * 6.1)
        fins.append((az, rb, rt, h, w, d))
    bm_f = bmesh.new(); bm_rib = bmesh.new()
    for i, (az, rb, rt, h, w, d) in enumerate(fins):
        th = rad(az)
        dirv = Vector((math.cos(th), math.sin(th), 0))
        u = Vector((-math.sin(th), math.cos(th), 0))
        zs = [0, 1.4, 3.2, 6.0, 9.0, max(9.6, h - 3.0), h - 1.1, h - 0.35, h]
        rings = []; corners = []
        for z in zs:
            t = min(1.0, z / h)
            r = rb + (rt - rb) * (t ** 1.12) + 0.9 * max(0.0, 1 - z / 1.8) ** 1.6
            ww = w * (1 - 0.30 * t); ddp = d * (1 - 0.22 * t)
            if z >= h - 1.2:
                k = (z - (h - 1.2)) / 1.2
                ddp *= (1 - 0.5 * k); ww *= (1 - 0.3 * k)
                r += (0.15 + 0.45 * H.h01(i * 1.91)) * k  # canted tip, varied lean
            o = dirv * r + Vector((0, 0, base_z + z))
            rings.append([bm_f.verts.new(o + u * (px * ww) + dirv * (py * ddp)) for (px, py) in FIN_PROF])
            corners.append((o + u * (0.30 * ww) + dirv * (0.5 * ddp + 0.04),
                            o + u * (-0.30 * ww) + dirv * (0.5 * ddp + 0.04)))
        np_ = len(FIN_PROF)
        for k in range(len(rings) - 1):
            for j in range(np_):
                bm_f.faces.new([rings[k][j], rings[k][(j + 1) % np_],
                                rings[k + 1][(j + 1) % np_], rings[k + 1][j]])
        try:
            bm_f.faces.new(list(reversed(rings[0]))); bm_f.faces.new(rings[-1])
        except Exception: pass
        for (ca, cb) in ((0, 1),):                        # bone edge ribs along outer corners
            for k in range(len(corners) - 1):
                cyl(bm_rib, corners[k][0], corners[k + 1][0], 0.07, 6, cap=False)
                cyl(bm_rib, corners[k][1], corners[k + 1][1], 0.07, 6, cap=False)
        cyl(bm_rib, corners[-1][0], corners[-1][1], 0.07, 6, cap=False)
        if H.h01(i * 4.4) < 0.5:                          # stepped tip block, riding the tip cant
            tip_o = rings[-1][0].co                       # anchor on the final ring
            tipo = Vector(((tip_o.x + rings[-1][4].co.x) / 2, (tip_o.y + rings[-1][4].co.y) / 2,
                           base_z + h + 0.28))
            obox(bm_f, tipo, u, dirv, w * 0.5, d * 0.4, 0.6)
    objs.append(H.finish(bm_f, "OFI_fins", MK['ferric']))
    objs.append(H.finish(bm_rib, "OFI_ribs", MK['bone']))
    # ---- rack channels between fins ----
    bm_rk = bmesh.new(); bm_sh = bmesh.new(); bm_un = bmesh.new()
    grille_spots = []
    for i in range(N):
        a0, rb0, rt0, h0, w0, d0 = fins[i]
        a1, rb1, rt1, h1, w1, d1 = fins[(i + 1) % N]
        if (a1 - a0) % 360 > 180: continue
        az = (a0 + ((a1 - a0) % 360) / 2) % 360
        dd = (az - front + 180) % 360 - 180
        if abs(dd) < 15.0: continue                       # portal gap stays open
        th = rad(az)
        dirv = Vector((math.cos(th), math.sin(th), 0))
        u = Vector((-math.sin(th), math.cos(th), 0))
        hc = 0.62 * min(h0, h1) + 2.2 * H.h01(i * 8.8)
        rbc = (rb0 + rb1) / 2 - 0.28; rtc = (rt0 + rt1) / 2 - 0.18
        gap = rad(((a1 - a0) % 360)) * (rbc + 1)
        wc = max(1.0, min(2.4, gap - 0.65))
        href = (h0 + h1) / 2
        def rch(z):
            return rbc + (rtc - rbc) * (min(1.0, z / href) ** 1.12) + 0.9 * max(0.0, 1 - z / 1.8) ** 1.6
        zs = [0.35, 2.0, 4.5, 7.0, hc]
        rings = []
        for z in zs:
            o = dirv * rch(z) + Vector((0, 0, base_z + z))
            rings.append([bm_rk.verts.new(o + u * (px * wc) + dirv * (py * 0.30))
                          for (px, py) in ((-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5))])
        for k in range(len(rings) - 1):
            for j in range(4):
                bm_rk.faces.new([rings[k][j], rings[k][(j + 1) % 4], rings[k + 1][(j + 1) % 4], rings[k + 1][j]])
        try:
            bm_rk.faces.new(list(reversed(rings[0]))); bm_rk.faces.new(rings[-1])
        except Exception: pass
        o = dirv * (rch(hc) + 0.1) + Vector((0, 0, base_z + hc + 0.12))
        obox(bm_sh, o, u, dirv, wc + 0.3, 0.55, 0.24)     # cap ledge
        z = 1.6
        while z < hc - 0.8:                               # rack shelf bars
            oo = dirv * (rch(z) + 0.18) + Vector((0, 0, base_z + z))
            obox(bm_sh, oo, u, dirv, wc + 0.12, 0.10, 0.09)
            z += 1.75
        for k in range(4):                                # protruding drawer units
            zz = 1.2 + H.h01(i * 6.6 + k * 3.3) * (hc - 2.4)
            xx = (H.h01(i * 2.2 + k * 7.7) - 0.5) * (wc - 0.7)
            oo = dirv * (rch(zz) + 0.25) + u * xx + Vector((0, 0, base_z + zz))
            obox(bm_un, oo, u, dirv, 0.55, 0.34, 0.30)
        if i % 5 == 2 and hc > 8:
            grille_spots.append((az, base_z + hc * 0.55, rch(hc * 0.55)))
    objs.append(H.finish(bm_rk, "OFI_racks", MK['rack']))
    objs.append(H.finish(bm_sh, "OFI_shelves", MK['teal_dark']))
    objs.append(H.finish(bm_un, "OFI_units", MK['metal']))
    for (az, gz, gr) in grille_spots:                     # pierced oval grilles over some bays
        th = rad(az); nvec = (math.cos(th), math.sin(th), 0.12)
        loc = Vector((math.cos(th) * (gr + 0.32), math.sin(th) * (gr + 0.32), gz))
        ov = BK.oval(0, 0, 0.72, 1.15, 14)
        bm = bmesh.new(); BK.ring(bm, ov, BK.inset(ov, 0.12), -0.06, 0.10)
        o = H.finish(bm, "OFI_grille_ring", MK['bone']); place(o, loc, nvec); objs.append(o)
        bm = bmesh.new(); BK.prism(bm, BK.inset(ov, 0.11), -0.02, 0.02)
        o = H.finish(bm, "OFI_grille", MK['voronoi']); place(o, loc, nvec); objs.append(o)
    # ---- core + crown ----
    bm = bmesh.new()
    lathe_rows = [(base_z, 4.9), (6.0, 4.1), (11.0, 3.3), (14.5, 2.5), (16.2, 1.5)]
    rgs = []
    for (z, r) in lathe_rows:
        rgs.append([bm.verts.new((math.cos(k / 14 * TAU) * r, math.sin(k / 14 * TAU) * r, z)) for k in range(14)])
    for k in range(len(rgs) - 1):
        for j in range(14):
            bm.faces.new([rgs[k][j], rgs[k][(j + 1) % 14], rgs[k + 1][(j + 1) % 14], rgs[k + 1][j]])
    apexv = bm.verts.new((0, 0, 17.1))
    for j in range(14):
        bm.faces.new([rgs[-1][j], rgs[-1][(j + 1) % 14], apexv])
    objs.append(H.finish(bm, "OFI_core", MK['ferric']))
    # central rack bay climbing the core above the sign (the tall centre column)
    def core_r(z):
        rows = lathe_rows + [(17.1, 0.0)]
        for k in range(len(rows) - 1):
            (z0, r0), (z1, r1) = rows[k], rows[k + 1]
            if z0 <= z <= z1:
                return r0 + (r1 - r0) * (z - z0) / max(1e-6, z1 - z0)
        return rows[-1][1]
    thc = rad(front)
    dirc = Vector((math.cos(thc), math.sin(thc), 0))
    uc = Vector((-math.sin(thc), math.cos(thc), 0))
    bm = bmesh.new(); bm2 = bmesh.new()
    zs_c = [8.9, 10.4, 12.2, 14.0]
    rings_c = []
    for z in zs_c:
        o = dirc * (core_r(z) + 0.18) + Vector((0, 0, z))
        rings_c.append([bm.verts.new(o + uc * (px * 1.7) + dirc * (py * 0.3))
                        for (px, py) in ((-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5))])
    for k in range(len(rings_c) - 1):
        for j in range(4):
            bm.faces.new([rings_c[k][j], rings_c[k][(j + 1) % 4], rings_c[k + 1][(j + 1) % 4], rings_c[k + 1][j]])
    try:
        bm.faces.new(list(reversed(rings_c[0]))); bm.faces.new(rings_c[-1])
    except Exception: pass
    z = 9.6
    while z < 13.8:
        oo = dirc * (core_r(z) + 0.36) + Vector((0, 0, z))
        obox(bm2, oo, uc, dirc, 1.82, 0.10, 0.09)
        z += 1.45
    objs.append(H.finish(bm, "OFI_core_rack", MK['rack']))
    objs.append(H.finish(bm2, "OFI_core_rack_sh", MK['teal_dark']))
    BK.crown_spired_cluster(MK, objs, lights, (0, 0, 15.4))
    # ---- portal: lit tunnel + scan bar ----
    th = rad(front)
    nvec = (math.cos(th), math.sin(th), 0)
    ploc = Vector((math.cos(th) * 6.30, math.sin(th) * 6.30, base_z))
    pw, ph, chm = 3.3, 4.7, 1.0
    outer = [(-pw / 2 + 0.3, 0), (pw / 2 - 0.3, 0), (pw / 2, 0.35), (pw / 2, ph - chm),
             (pw / 2 - chm, ph), (-pw / 2 + chm, ph), (-pw / 2, ph - chm), (-pw / 2, 0.35)]
    bm = bmesh.new(); BK.ring(bm, outer, BK.inset(outer, 0.36), -0.5, 0.45)
    o = H.finish(bm, "OFI_portal_frame", MK['ferric']); place(o, ploc, nvec); objs.append(o)
    bm = bmesh.new()                                      # hollow tunnel: tube walls + back plate
    BK.ring(bm, BK.inset(outer, 0.35), BK.inset(outer, 0.62), -2.4, -0.45)
    BK.prism(bm, BK.inset(outer, 0.60), -2.4, -2.28)
    o = H.finish(bm, "OFI_portal_tunnel", MK['dark']); place(o, ploc, nvec); objs.append(o)
    bm = bmesh.new(); bx(bm, 0, 2.25, -0.52, pw - 0.7, 0.05, 0.05)
    o = H.finish(bm, "OFI_scanbar", MK['cyanbar']); place(o, ploc, nvec); objs.append(o)
    bm = bmesh.new(); bx(bm, 0, 0.06, -1.5, pw - 1.1, 0.05, 2.1)
    o = H.finish(bm, "OFI_floorglow", emis_mat('cyan_floor', (0.35, 0.62, 0.70), 2.0))
    place(o, ploc, nvec); objs.append(o)
    lights.append(('POINT', BK.local_pt(ploc, nvec, (0, 2.6, -1.2)), (0.55, 0.88, 0.96), 22, 0.8))
    lights.append(('POINT', BK.local_pt(ploc, nvec, (0, 1.0, 1.6)), (0.55, 0.88, 0.96), 40, 0.6))
    lights.append(('POINT', BK.local_pt(ploc, nvec, (0, 0.5, 3.2)), (0.45, 0.75, 0.85), 30, 0.9))
    # ---- sign + crest above the portal ----
    bm = bmesh.new(); bx(bm, 0, 6.05, 0.10, 3.8, 1.55, 0.35)
    o = H.finish(bm, "OFI_sign_back", MK['metal']); place(o, ploc, nvec); objs.append(o)
    bm = bmesh.new(); bx(bm, 0, 6.05, 0.30, 3.2, 1.05, 0.10)
    o = H.finish(bm, "OFI_sign_panel", H.matp('ofi_panel', (0.030, 0.048, 0.042), rough=0.5))
    place(o, ploc, nvec); objs.append(o)
    bm = bmesh.new()
    for (sx, sy, px, py) in ((3.4, 0.09, 0, 6.60), (3.4, 0.09, 0, 5.50), (0.09, 1.20, -1.65, 6.05), (0.09, 1.20, 1.65, 6.05)):
        bx(bm, px, py, 0.32, sx, sy, 0.10)
    o = H.finish(bm, "OFI_sign_border", MK['rust']); place(o, ploc, nvec); objs.append(o)
    gt = emis_mat('ofi_green_text', GREEN, 1.9)
    BK.add_text(objs, "The Open Files Initiative", 0.30, gt, BK.local_pt(ploc, nvec, (0, 6.26, 0.40)), n=nvec)
    BK.add_text(objs, "Records Access Is A Civil Right", 0.13, gt, BK.local_pt(ploc, nvec, (0, 5.76, 0.40)), n=nvec)
    lights.append(('POINT', BK.local_pt(ploc, nvec, (0, 6.05, 1.0)), GREEN, 16, 0.5))
    bm = bmesh.new(); bx(bm, 0, 7.85, 0.02, 1.25, 1.25, 0.30)
    o = H.finish(bm, "OFI_crest_back", MK['teal_dark']); place(o, ploc, nvec); objs.append(o)
    bm = bmesh.new()
    BK.prism(bm, [(-0.30, 7.45), (0.30, 7.45), (0.24, 8.05), (0, 8.25), (-0.24, 8.05)], 0.18, 0.32)
    o = H.finish(bm, "OFI_crest", MK['bone']); place(o, ploc, nvec); objs.append(o)
    # ---- plinth apron + street furniture ----
    bm = bmesh.new()
    for (rr, hh) in ((9.2, 0.30), (7.9, 0.58)):
        ring_lo = [bm.verts.new((math.cos(k / 16 * TAU) * rr, math.sin(k / 16 * TAU) * rr, 0)) for k in range(16)]
        ring_hi = [bm.verts.new((math.cos(k / 16 * TAU) * rr, math.sin(k / 16 * TAU) * rr, hh)) for k in range(16)]
        for j in range(16):
            bm.faces.new([ring_lo[j], ring_lo[(j + 1) % 16], ring_hi[(j + 1) % 16], ring_hi[j]])
        try: bm.faces.new(ring_hi)
        except Exception: pass
    objs.append(H.finish(bm, "OFI_plinth", MK['paving']))
    for s in (-1, 1):                                     # terminal kiosks
        th2 = rad(front + s * 19)
        kloc = Vector((math.cos(th2) * 7.9, math.sin(th2) * 7.9, 0))
        nv2 = (math.cos(th2), math.sin(th2), 0)
        bm = bmesh.new()
        bx(bm, 0, 0.55, 0.0, 0.55, 1.1, 0.4)
        bx(bm, 0, 1.25, 0.12, 0.62, 0.5, 0.5)
        o = H.finish(bm, "OFI_kiosk", MK['teal_dark']); place(o, kloc, nv2); objs.append(o)
        bm = bmesh.new(); bx(bm, 0, 1.28, 0.40, 0.5, 0.36, 0.03)
        o = H.finish(bm, "OFI_kiosk_scr", MK['readout']); place(o, kloc, nv2); objs.append(o)
        lights.append(('POINT', BK.local_pt(kloc, nv2, (0, 1.5, 0.8)), GREEN, 10, 0.3))
    for s in (-1, 1):                                     # street lamps, warm
        th2 = rad(front + s * 38)
        lp = Vector((math.cos(th2) * 8.8, math.sin(th2) * 8.8, 0))
        bm = bmesh.new()
        cyl(bm, lp, lp + Vector((0, 0, 3.5)), 0.07, 6)
        arm = lp + Vector((0, 0, 3.5))
        tip = arm + Vector((-math.cos(th2) * 0.6, -math.sin(th2) * 0.6, 0.15))
        cyl(bm, arm, tip, 0.05, 6)
        bx(bm, tip.x, tip.y, tip.z - 0.18, 0.28, 0.28, 0.28)
        objs.append(H.finish(bm, "OFI_lamp", MK['rust']))
        lights.append(('POINT', tip + Vector((0, 0, -0.42)), (1.0, 0.72, 0.42), 55, 0.5))
    bm = bmesh.new()
    for k in range(9):                                    # bollard row on the apron rim
        th2 = rad(front - 44 + k * 11)
        bp = Vector((math.cos(th2) * 9.6, math.sin(th2) * 9.6, 0))
        cyl(bm, bp, bp + Vector((0, 0, 0.55)), 0.075, 6)
        cyl(bm, bp + Vector((0, 0, 0.55)), bp + Vector((0, 0, 0.64)), 0.10, 6)
    objs.append(H.finish(bm, "OFI_bollards", MK['teal_dark']))

# ============================================================ ASSEMBLER
PLUMBING = {
    'name': 'plumbing_power_project',
    'shell': 'spiral_organic_mass',
    'storeys': 3,
    'profile': [(0.00, 4.70), (0.80, 4.88), (2.00, 4.86), (3.50, 4.78), (5.00, 4.66),
                (6.50, 4.52), (8.00, 4.40), (9.50, 4.30), (11.00, 4.24), (12.40, 4.18),
                (13.00, 4.02), (13.30, 4.50), (13.72, 4.50), (13.98, 3.88),
                (14.35, 3.66), (14.85, 3.30), (15.42, 2.72), (15.92, 2.02),
                (16.28, 1.28), (16.52, 0.64)],
    'apex_h': 16.70,
    'seg': 48, 'lobe_n': 8, 'lobe_amp': 0.17, 'lobe_top': 7.0, 'lobe_sharp': 1.8,
    'macro_amp': 0.04, 'macro_top': 6.0,
    'front_az': 286.0,
    'crown': 'domed_cap', 'crown_finial': 'cupola',
    'trough': {'az0': 203.0, 'az1': 700.0, 'h0': 7.2, 'h1': 12.75, 'clearance': 1.05, 'stations': 96},
    'windows': [(270, 10.3, 0.30, 1.7), (276.5, 10.3, 0.30, 1.7), (283, 10.3, 0.30, 1.7),
                (246, 10.0, 0.30, 1.5), (302, 10.6, 0.28, 1.4), (212, 9.6, 0.28, 1.4),
                (266, 14.55, 0.24, 1.0), (274, 14.55, 0.24, 1.0)],
    'wheels': [(231, 2.95, 0.60), (245, 2.85, 0.68), (232, 1.30, 0.68), (246, 1.35, 0.56)],
    'pipe': {'az': 303.0, 'h_top': 12.3, 'h_bot': 0.0},
    'sign': {'az': 282.0, 'h': 5.5, 'text': "PLUMBING\nPOWER\nPROJECT"},
    'door_az': 286.0,
    'spill_az': 262.0,
    'stub_az': 205.0,
    'wings': [(332, 6.5, 1.2, 318, 11.8, 0.85, 2.2), (226, 5.9, 1.0, 222, 6.4, 0.75, 1.8)],
    'arch_void': (324, 2.5, 0.85, 4.6),
    'clutter': [(292, 13.80, 0.5, 'box'), (298, 13.45, 0.0, 'stack')],
    'camera': {'az': 275.0, 'dist': 33.0, 'h': 3.6, 'target': 8.4, 'lens': 56},
    'moss_r': 6.6,
}

OPEN_FILES = {
    'name': 'open_files_initiative',
    'shell': 'drawer_stack_monolith',
    'storeys': 6,
    'fins': 12, 'r_base': 5.6, 'r_top': 3.1,
    'front_az': 270.0,
    'apex_h': 18.5,
    'warm_fill': True,                                   # sepia-haze register
    'key_energy': 19000, 'sun_energy': 1.7,
    'camera': {'az': 272.0, 'dist': 37.0, 'h': 3.2, 'target': 9.2, 'lens': 50},
    'moss_r': 0.0,
}

def build_building(P, M):
    objs = []; lights = []
    if P.get('shell') == 'drawer_stack_monolith':
        build_monolith(P, objs, lights)
        return objs, lights, None
    shell = Shell(P['profile'], seg=P['seg'], lobe_n=P['lobe_n'], lobe_amp=P['lobe_amp'],
                  lobe_top=P['lobe_top'], lobe_sharp=P.get('lobe_sharp', 1.8),
                  macro_amp=P['macro_amp'], macro_top=P['macro_top'],
                  phase_az=P['front_az'])
    objs.append(shell.build("PPP_drum", M['shingle'], P['apex_h']))
    for w in P.get('wings', []):
        wing(shell, M, objs, *w)
    if P.get('arch_void'):
        az, h, w, tall = P['arch_void']
        slit_window(shell, M, objs, az, h, w, tall, dark_arch=True)
    if P.get('trough'):
        build_trough(shell, M, P['trough'], objs, lights)
    for (az, h, w, tall) in P.get('windows', []):
        slit_window(shell, M, objs, az, h, w, tall)
    for (az, h, r) in P.get('wheels', []):
        n = shell.normal(az, h)
        valve_wheel(M, objs, shell.surf(az, h, 0.18), n, R=r, seed=az * 0.1, standoff=0.22)
    if P.get('pipe'):
        wall_pipe(shell, M, objs, P['pipe']['az'], P['pipe']['h_top'], P['pipe']['h_bot'])
    if P.get('sign'):
        sign_panel(shell, M, objs, P['sign']['az'], P['sign']['h'], P['sign']['text'])
    if P.get('door_az') is not None:
        entry(shell, M, objs, lights, P['door_az'])
    if P.get('spill_az') is not None:
        spill(shell, M, objs, lights, P['spill_az'])
    if P.get('stub_az') is not None:
        ground_stub(shell, M, objs, P['stub_az'])
    if P.get('crown_finial') == 'cupola':
        cupola(M, objs, P['apex_h'] - 0.04)
    if P.get('clutter'):
        roof_clutter(shell, M, objs, P['clutter'])
    # ---- §3 KNOB DISPATCH: mount bld_kit parts by option name ----
    if any(k in P for k in ('kit_windows', 'kit_door', 'kit_projections', 'kit_crown', 'kit_structures')):
        MK = BK.build_mats()
        for spec in P.get('kit_windows', []):
            BK.WINDOWS[spec['type']](MK, objs, lights,
                                     shell.surf(spec['az'], spec['h'], spec.get('out', -0.02)),
                                     shell.normal(spec['az'], spec['h']))
        d = P.get('kit_door')
        if d:
            BK.DOORS[d['type']](MK, objs, lights,
                                shell.surf(d['az'], 0.0, d.get('out', -0.05)),
                                shell.normal(d['az'], 1.4))
        for spec in P.get('kit_projections', []):
            BK.PROJECTIONS[spec['type']](MK, objs, lights,
                                         shell.surf(spec['az'], spec.get('h', 0.0), spec.get('out', -0.02)),
                                         shell.normal(spec['az'], max(1.0, spec.get('h', 0.0))))
        c = P.get('kit_crown')
        if c:
            BK.CROWNS[c['type']](MK, objs, lights, (0, 0, c.get('z', P['apex_h'])))
        for spec in P.get('kit_structures', []):
            fn = BK.STRUCTURES[spec['type']]
            if fn in BK.WALL_PARTS:
                fn(MK, objs, lights, shell.surf(spec['az'], spec.get('h', 0.0), -0.02),
                   shell.normal(spec['az'], max(1.0, spec.get('h', 2.0))))
            else:
                th2 = rad(spec['az'])
                fn(MK, objs, lights, (math.cos(th2) * spec['dist'], math.sin(th2) * spec['dist'], 0.0))
    return objs, lights, shell

# ============================================================ FAR IMPOSTOR
def build_building_far(P, M, tex_res=512, az=None):
    """FAR LOD: build the NEAR mesh, snapshot it to a transparent texture from the
    front azimuth, delete it, return one alpha-clipped quad carrying the render."""
    objs, lights, shell = build_building(P, M)
    az = az if az is not None else P['front_az']
    hmax = P['apex_h'] + 2.2
    sc = bpy.context.scene
    cam = bpy.data.cameras.new("far_cam"); cam.type = 'ORTHO'; cam.ortho_scale = hmax * 1.15
    co = bpy.data.objects.new("far_cam", cam); sc.collection.objects.link(co)
    th = rad(az)
    co.location = (math.cos(th) * 60, math.sin(th) * 60, hmax / 2)
    co.rotation_euler = (Vector((0, 0, hmax / 2)) - Vector(co.location)).to_track_quat('-Z', 'Y').to_euler()
    old_cam, old_x, old_y, old_transp = sc.camera, sc.render.resolution_x, sc.render.resolution_y, sc.render.film_transparent
    sc.camera = co; sc.render.resolution_x = tex_res; sc.render.resolution_y = tex_res
    sc.render.film_transparent = True
    path = r"C:\tmp\_far_impostor.png"
    old_path = sc.render.filepath; sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    sc.camera, sc.render.resolution_x, sc.render.resolution_y = old_cam, old_x, old_y
    sc.render.film_transparent = old_transp; sc.render.filepath = old_path
    for o in objs: bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.objects.remove(co, do_unlink=True)
    img = bpy.data.images.load(path); img.pack()
    bm = bmesh.new()
    s = hmax * 1.15 / 2
    v = [bm.verts.new((-s, 0, hmax / 2 - s)), bm.verts.new((s, 0, hmax / 2 - s)),
         bm.verts.new((s, 0, hmax / 2 + s)), bm.verts.new((-s, 0, hmax / 2 + s))]
    f = bm.faces.new(v)
    uvl = bm.loops.layers.uv.new("UVMap")
    for loop, uvco in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        loop[uvl].uv = uvco
    o = H.finish(bm, P['name'] + "_far")
    # shadeless impostor: emission x alpha reproduces the baked lighting as-is
    m = bpy.data.materials.new(P['name'] + "_far_mat"); m.use_nodes = True
    H.alpha_flags(m)
    nt = m.node_tree
    for nd in list(nt.nodes): nt.nodes.remove(nd)
    out = nt.nodes.new('ShaderNodeOutputMaterial'); out.location = (400, 0)
    mix = nt.nodes.new('ShaderNodeMixShader'); mix.location = (200, 0)
    tp = nt.nodes.new('ShaderNodeBsdfTransparent'); tp.location = (0, -120)
    em = nt.nodes.new('ShaderNodeEmission'); em.location = (0, 120)
    ti = nt.nodes.new('ShaderNodeTexImage'); ti.location = (-260, 0)
    ti.image = img; ti.interpolation = 'Closest'
    nt.links.new(ti.outputs['Color'], em.inputs['Color'])
    nt.links.new(ti.outputs['Alpha'], mix.inputs['Fac'])
    nt.links.new(tp.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    o.data.materials.append(m)
    o.rotation_euler = (0, 0, th + math.pi / 2)
    return o

# ============================================================ DEMO / RENDER
if __name__ == "__main__" or True:
    ACTIVE = OPEN_FILES                                  # switch preset here (PLUMBING / OPEN_FILES)
    H.wipe()
    M = build_mats()
    objs, lights, shell = build_building(ACTIVE, M)
    # ground: paving + optional moss ring
    bm = bmesh.new()
    v = [bm.verts.new(p) for p in ((-90, -90, 0), (90, -90, 0), (90, 90, 0), (-90, 90, 0))]
    bm.faces.new(v)
    H.finish(bm, "ground", M['paving'])
    mr = ACTIVE.get('moss_r', 6.6)
    if mr > 0:
        bm = bmesh.new()
        ring = [bm.verts.new((math.cos(k / 14 * TAU) * (mr + 1.2 * H.h01(k * 3.1)),
                              math.sin(k / 14 * TAU) * (mr + 1.2 * H.h01(k * 5.7)), 0.012)) for k in range(14)]
        bm.faces.new(ring)
        H.finish(bm, "moss_ring", M['moss'])
    # lights: ONE soft dominant key, faint cool fill/rim, near-black ambient
    H.demo_env(bg=(0.007, 0.009, 0.011), strength=0.30)
    kl = bpy.data.lights.new("KEY", 'AREA'); kl.energy = ACTIVE.get('key_energy', 30000); kl.size = 16
    kl.color = (1.0, 0.96, 0.88)
    ko = bpy.data.objects.new("KEY", kl); bpy.context.scene.collection.objects.link(ko)
    ko.location = (-14, -28, 25)
    ko.rotation_euler = (Vector((0, 0, 7)) - Vector(ko.location)).to_track_quat('-Z', 'Y').to_euler()
    sun = H.demo_sun((-12, -30, 36), (0, 0, 7), ACTIVE.get('sun_energy', 2.6)); sun.data.color = (1.0, 0.97, 0.90)
    rim = H.demo_sun((16, 30, 24), (0, 0, 8), 0.85); rim.data.color = (0.75, 0.83, 0.90)
    if ACTIVE.get('warm_fill'):                          # sepia haze register (Open Files)
        wf = H.demo_sun((6, -34, 8), (0, 0, 6), 0.5); wf.data.color = (1.0, 0.82, 0.58)
        try: wf.data.use_shadow = False
        except Exception: pass
    for (kind, loc, col, e, r) in lights:
        l = bpy.data.lights.new("P", kind); l.energy = e; l.color = col
        l.shadow_soft_size = r
        lo = bpy.data.objects.new("P", l); bpy.context.scene.collection.objects.link(lo)
        lo.location = loc
    # camera: low, slightly up-tilted, longer lens (ref framing)
    CAM = ACTIVE.get('camera', {'az': 275.0, 'dist': 33.0, 'h': 3.6, 'target': 8.4, 'lens': 56})
    th = rad(CAM['az'])
    H.demo_cam((math.cos(th) * CAM['dist'], math.sin(th) * CAM['dist'], CAM['h']),
               (0, 0, CAM['target']), lens=CAM['lens'])
    sc = bpy.context.scene
    try:
        sc.eevee.use_raytracing = True
    except Exception: pass
    for look in ('AgX - High Contrast', 'High Contrast'):
        try:
            sc.view_settings.look = look; break
        except Exception: pass
    try: sc.view_settings.exposure = 0.2
    except Exception: pass
    try:                                                # soft glow halo on the emissives
        sc.use_nodes = True
        nt = sc.node_tree
        for nd in list(nt.nodes): nt.nodes.remove(nd)
        rl = nt.nodes.new('CompositorNodeRLayers')
        gl = nt.nodes.new('CompositorNodeGlare')
        try: gl.glare_type = 'FOG_GLOW'
        except Exception: pass
        for attr, val in (('threshold', 1.0), ('size', 7), ('mix', -0.4)):
            try: setattr(gl, attr, val)
            except Exception: pass
        for sock, val in (('Threshold', 1.0), ('Strength', 0.6), ('Size', 0.6)):
            try: gl.inputs[sock].default_value = val
            except Exception: pass
        cmp = nt.nodes.new('CompositorNodeComposite')
        nt.links.new(rl.outputs['Image'], gl.inputs['Image'])
        nt.links.new(gl.outputs['Image'], cmp.inputs['Image'])
    except Exception: pass
    H.demo_render(r"C:\tmp\bldg_%s.png" % ACTIVE['name'], w=1152, h=1440)
    import os
    os.makedirs(r"C:\Users\quest\Programming\Games\ToRustAsWeFall\blender\generators", exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=r"C:\Users\quest\Programming\Games\ToRustAsWeFall\blender\generators\gen_building_%s.blend" % ACTIVE['name'])
    tv = sum(len(o.data.vertices) for o in bpy.data.objects if o.type == 'MESH')
    print("BLDG %s objects=%d verts=%d" % (ACTIVE['name'], len(bpy.data.objects), tv))
