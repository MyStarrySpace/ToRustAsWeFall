# CONCEPT FLORA — the seven tendable species rebuilt AGAINST their ENT concept
# cards (blender/previews/ENT-0xx_*.png; canon: flora_image_prompts.md).
# Exec-included after concept_pass1.py; overrides the earlier flora builders.

def build_seefern():
    """CARD ENT-014_tended: the knee-high fern-LANTERN — near-shadow dark blades
    whose light is the bright teal VASCULATURE (CS seefern_vein emissive): a
    rachis strip running base-to-tip plus herringbone leaflet vein dashes on
    EVERY mature frond, and a glowing curl-ring at every frond tip (the card's
    tip circles). AFFORDANCE = the EYES: each vein dash carries a dark oval stud
    sitting ON the glow so the surrounding vein-light rings it — dozens of
    outward-facing eyes = "this plant SEES" (vision-extension read before any
    interaction). Five mature fronds fan from a faintly-glowing mossy pad strewn
    with dark pebbles; two young fronds sit shorter and steeper, each with one
    dim eye and a small fiddlehead ring."""
    H = (0.0, 0.0, 0.03, 0.14)
    chains = []
    for k in range(7):                                        # lumpy moss pad mound
        ang = k * math.tau / 7.0 + 0.23
        r_out = 0.24 + 0.04 * ((k * 5) % 3)
        chains.append([H, (0.55 * r_out * math.cos(ang), 0.55 * r_out * math.sin(ang), 0.025, 0.07),
                       (r_out * math.cos(ang), r_out * math.sin(ang), 0.012, 0.035)])
    ob = _skin_growth("Seefern", chains, decimate=0.28, jitter=0.015, sub_levels=2)
    moss = _flat_mat("cf_seefern_moss", CH("moss"), _dim(CS("seefern_vein"), 0.3), 0.8)
    leaf = _flat_mat("cf_seefern_leaf", _dim(CS("seefern_leaf"), 0.45), rough=0.9)
    vein = _flat_mat("cf_seefern_vein", _dim(CS("seefern_vein"), 0.5), CS("seefern_vein"), 1.4)
    eye = _flat_mat("cf_seefern_eye", _dim(CS("seefern_leaf"), 0.18), rough=0.95)
    stone = _flat_mat("cf_seefern_stone", _dim(CH("ground"), 0.55), rough=0.9)
    for m in (moss, leaf, vein, eye, stone):
        ob.data.materials.append(m)
    # (azimuth, tilt-from-vertical, length, width) — 5 mature + 2 young curled
    fronds = [(0.3, 0.12, 0.62, 0.19), (1.5, 0.34, 0.52, 0.18),
              (2.7, 0.40, 0.50, 0.17), (3.9, 0.44, 0.46, 0.16),
              (5.1, 0.36, 0.42, 0.15),
              (0.95, 0.58, 0.28, 0.09), (4.5, 0.62, 0.26, 0.09)]
    studs = []
    bm = _bmesh.new()
    bm.from_mesh(ob.data)
    for fi, (a, t, L, W) in enumerate(fronds):
        dx, dy = math.sin(a), -math.cos(a)                    # outward lean direction
        ax = (math.sin(t) * dx, math.sin(t) * dy, math.cos(t))
        wx, wy = math.cos(a), math.sin(a)                     # in-blade width direction
        base = (dx * 0.05, dy * 0.05, 0.07)

        def at(f, side=0.0):
            return (base[0] + ax[0] * f * L + wx * side,
                    base[1] + ax[1] * f * L + wy * side,
                    base[2] + ax[2] * f * L)
        _bev_box_r(bm, at(0.5), (W, 0.02, L), 1, rot=(t, 0.0, a), bevel=0.008)   # dark blade
        _bev_box_r(bm, at(0.46), (W * 0.2, 0.028, L * 0.92), 2, rot=(t, 0.0, a),
                   bevel=0.006)                # rachis vein — thicker in Y, pierces both faces
        young = L < 0.3
        if young:
            studs.append((*at(0.5), 0.018, 3, 0.8))           # young: one dim eye on the rachis
        else:
            for di, f in enumerate((0.38, 0.56, 0.74)):       # herringbone dashes, both sides
                s = W * 0.24 * (1.0 if (di + fi) % 2 == 0 else -1.0)
                _bev_box_r(bm, at(f, s), (W * 0.3, 0.026, L * 0.14), 2,
                           rot=(t, 0.0, a), bevel=0.005)      # leaflet vein dash
                studs.append((*at(f, s), 0.021, 3, 0.8))      # eye ON the dash, glow rings it
            studs.append((*at(0.86), 0.019, 3, 0.8))          # upper rachis eye
        hs_torus(bm, at(1.02), 0.035 if young else 0.045, 0.012, 2,   # tip curl-ring (all fronds)
                 major_segs=10, minor_segs=6,
                 axis='Y' if abs(dy) > abs(dx) else 'X')
    bm.to_mesh(ob.data)
    bm.free()
    for (sa, sr, srad) in ((0.5, 0.24, 0.05), (1.7, 0.19, 0.035), (2.9, 0.27, 0.045),
                           (3.8, 0.17, 0.03), (4.9, 0.25, 0.05), (5.9, 0.21, 0.033)):
        studs.append((sr * math.cos(sa), sr * math.sin(sa), 0.045, srad, 4, 0.6))
    _stud_spheres(ob, studs)
    ob["no_atlas"] = 1
    return ob


def build_scarpet():
    """Scarpet (card ENT-015_tended): the low two-tone moss carpet — the
    CONCEAL_MEDIUM hide you lie UNDER. One connected skinned MAT (rough oval
    ~1.2 x 0.9, well under 0.16 tall): pale greenish-brown living moss (CS
    scarpet_green) worked through with rust scar patches (metabolized iron
    precipitated in the tissue — 'this plant has been working here') shading to
    dark worn brown in the oldest zones, plus pale bleached substrate peeking
    past the fringed edge ('the iron is gone here' — siderophores route around
    it). Slightly raised irregular fringe lip; pillowy stud texture; no hard
    parts, no glow."""
    center = (0.0, 0.0, 0.05, 0.065)
    n = 10
    mids, edges = [], []
    for i in range(n):
        a = (2.0 * math.pi) * i / n
        ex = 0.60 * math.cos(a)
        ey = 0.45 * math.sin(a)
        wob = 0.92 + 0.05 * ((i * 5) % 3)              # irregular fringe, deterministic
        er = 0.045 + 0.006 * ((i * 2 + 1) % 3)
        ez = 0.052 + 0.013 * ((i + 1) % 2)             # alternating raised fringe lip
        mids.append((ex * 0.55, ey * 0.55, 0.05, 0.056))
        edges.append((ex * wob, ey * wob, ez, er))
    chains = [[center, mids[i], edges[i]] for i in range(n)]
    chains.append(mids + [mids[0]])                     # inner ring welds the spokes flat
    chains.append(edges + [edges[0]])                   # fringe ring closes the mat
    ob = _skin_growth("Scarpet", chains, decimate=0.20, jitter=0.015, sub_levels=2)
    moss = _flat_mat("cf_scarpet_moss_m", CS("scarpet_green"), rough=0.9)
    rust = _flat_mat("cf_scarpet_rust_m", _dim(CH("rust"), 0.8), rough=0.85)
    worn = _flat_mat("cf_scarpet_worn_m", CS("root_worn"), rough=0.85)
    pale = _flat_mat("cf_scarpet_scar_m", CS("resolution_root_pale"), rough=0.95)
    for m in (moss, rust, worn, pale):
        ob.data.materials.append(m)
    _stud_spheres(ob, [
        # rust scar patches worked through the green (flat, squash 0.3)
        (-0.18, 0.10, 0.095, 0.10, 1, 0.3),
        (0.22, -0.14, 0.090, 0.085, 1, 0.3),
        (0.05, 0.22, 0.086, 0.075, 1, 0.3),
        (-0.36, -0.11, 0.076, 0.070, 1, 0.3),
        (0.38, 0.11, 0.074, 0.065, 1, 0.3),
        # darker fully-metabolized zones shading the older scars
        (0.02, -0.05, 0.095, 0.080, 2, 0.3),
        (-0.28, 0.20, 0.072, 0.060, 2, 0.3),
        (0.28, -0.26, 0.066, 0.055, 2, 0.3),
        # pillowy living-moss bumps (keeps the mat reading soft, not slab-like)
        (-0.08, -0.22, 0.090, 0.065, 0, 0.45),
        (0.14, 0.06, 0.095, 0.060, 0, 0.45),
        (-0.42, 0.04, 0.070, 0.050, 0, 0.45),
        (0.45, -0.05, 0.068, 0.048, 0, 0.45),
        # bleached substrate scars peeking past the fringe (the 'iron is gone' read)
        (-0.55, -0.24, 0.012, 0.085, 3, 0.25),
        (0.52, 0.27, 0.010, 0.078, 3, 0.25),
        (0.05, -0.47, 0.010, 0.072, 3, 0.25)])
    ob["no_atlas"] = 1
    return ob


def build_hushbloom():
    """Hushbloom (card ENT-017_charged): a NODDING stun-flower. A slender
    purple-tinted stem arcs up ~0.7 m and droops — the closed pale-lavender
    bloom hangs from the nod, 5 petals folded INWARD converging under a core
    stud (the drooped closed bell = a held CHARGE, per canon the pre-trigger
    state of the GABA-mimetic stun). The card's low comb-leaf pad spreads at
    the base: three rachises with paired tilted leaflets, each attachment
    carrying a swollen faintly-glowing PULVINUS node — the alternating
    big/small stem beads repeat the same pulvinus read up the arc. Emission
    stays faint (0.9): a charge held, not a lamp."""
    base = (0.0, 0.0, 0.02, 0.032)
    spine = [base,
             (0.01, 0.0, 0.20, 0.015), (0.03, 0.01, 0.38, 0.022),
             (0.07, 0.01, 0.53, 0.012), (0.14, 0.02, 0.63, 0.018),
             (0.23, 0.02, 0.66, 0.010), (0.30, 0.02, 0.62, 0.016)]
    pads = [(0.16, 0.10, 0.30, 0.18), (-0.20, 0.06, -0.36, 0.10),
            (0.02, -0.20, 0.05, -0.36)]
    chains = [spine]
    for (mx, my, tx, ty) in pads:
        chains.append([base, (mx, my, 0.05, 0.013), (tx, ty, 0.07, 0.007)])
    ob = _skin_growth("Hushbloom", chains, decimate=0.2, jitter=0.012, sub_levels=2)
    stem = _flat_mat("cf_hushbloom_stem_m", CS("hushbloom_stem"))
    bloom = _flat_mat("cf_hushbloom_bloom_m", _dim(CS("hushbloom_bloom"), 0.75),
                      CS("hushbloom_bloom"), 0.9)
    leaf = _flat_mat("cf_hushbloom_leaf_m", _dim(CS("scarpet_green"), 0.7))
    for m in (stem, bloom, leaf):
        ob.data.materials.append(m)
    core = (0.30, 0.02, 0.55)
    bm = _bmesh.new()
    bm.from_mesh(ob.data)
    for k in range(5):                       # petals folded inward: tops flare, tips
        a = 0.3 + k * math.pi * 2.0 / 5.0    # tuck under the hanging core (closed bell)
        _bev_box_r(bm, (core[0] + math.cos(a) * 0.032,
                        core[1] + math.sin(a) * 0.032, core[2] + 0.015),
                   (0.05, 0.022, 0.10), 1, rot=(0.0, 0.55, a), bevel=0.006)
    for (mx, my, tx, ty) in pads:            # comb leaflets: paired, splayed open
        ang = math.atan2(ty, tx)
        for t in (0.5, 0.72, 0.94):
            pz = 0.045 + 0.03 * t
            for s in (-1.0, 1.0):
                _bev_box_r(bm, (tx * t - math.sin(ang) * s * 0.048,
                                ty * t + math.cos(ang) * s * 0.048, pz),
                           (0.075, 0.026, 0.011), 2,
                           rot=(0.18 * s, -0.12, ang + s * 1.25), bevel=0.006)
    bm.to_mesh(ob.data)
    bm.free()
    studs = [(core[0], core[1], core[2], 0.030, 1, 0.85)]          # bloom core
    studs += [(0.03, 0.01, 0.40, 0.014, 1, 0.8),                   # stem pulvini
              (0.14, 0.02, 0.645, 0.012, 1, 0.8)]
    for (mx, my, tx, ty) in pads:                                  # pad pulvini
        for t in (0.5, 0.72, 0.94):
            studs.append((tx * t, ty * t, 0.053 + 0.03 * t, 0.012, 1, 0.75))
    _stud_spheres(ob, studs)
    ob["no_atlas"] = 1
    return ob


def build_flure():
    """Card ENT-016_tended — FLURE, the iron DECOY (flora_image_prompts: trumpet
    flower atop a slender stem, iron haze at the base). Waist-high: a green
    skin-growth stem rises from a dark splayed basal rosette into a RADIAL
    iron-bronze petal collar (CS flure_bronze) — 9 tilted wedges fanned around a
    tapered throat cone, jagged rim via alternating petal lengths — around a
    glowing filament core (CS flure_core, emit 1.4) with three filament cones
    poking above the rim. Faintly-emissive rust dust settles around the base:
    the visible iron-broadcast signal players read as 'plant me as a decoy'."""
    stem = [(0.0, 0.0, 0.0, 0.055), (0.005, 0.0, 0.16, 0.026),
            (0.01, 0.005, 0.34, 0.036), (0.015, 0.01, 0.5, 0.02),
            (0.02, 0.01, 0.64, 0.03)]
    chains = [stem]
    chains.append([stem[2], (0.09, 0.03, 0.4, 0.014), (0.13, 0.05, 0.46, 0.008)])
    chains.append([stem[1], (-0.08, -0.04, 0.22, 0.013), (-0.12, -0.06, 0.28, 0.007)])
    ob = _skin_growth("Flure", chains, decimate=0.22, jitter=0.012, sub_levels=2)
    stem_m = _flat_mat("cf_flure_stem", CS("scarpet_green"), rough=0.8)
    bronze = _flat_mat("cf_flure_bronze", CS("flure_bronze"), rough=0.45)
    throat = _flat_mat("cf_flure_throat", _dim(CS("flure_bronze"), 0.55), rough=0.6)
    core = _flat_mat("cf_flure_core", _dim(CS("flure_core"), 0.7), CS("flure_core"), 1.4)
    rosette = _flat_mat("cf_flure_rosette", _dim(CS("scarpet_green"), 0.5), rough=0.85)
    dust = _flat_mat("cf_flure_dust", _dim(CS("flure_bronze"), 0.85),
                     _dim(CS("flure_bronze"), 0.9), 0.8)
    for m in (stem_m, bronze, throat, core, rosette, dust):
        ob.data.materials.append(m)
    bm = _bmesh.new()
    bm.from_mesh(ob.data)
    n0 = len(bm.faces)                                    # trumpet throat cone
    ret = _bmesh.ops.create_cone(bm, cap_ends=True, segments=9,
                                 radius1=0.035, radius2=0.145, depth=0.26)
    _bmesh.ops.transform(bm, matrix=mathutils.Matrix.Translation((0.0, 0.0, 0.79)),
                         verts=ret["verts"])
    _hs_tag(bm, n0, 2)
    for i in range(9):                                    # the petal collar fan
        a = i * math.pi * 2.0 / 9.0
        length = 0.32 if i % 2 == 0 else 0.27             # jagged rim teeth
        tilt = 0.6
        rc = math.sin(tilt) * length * 0.5 + 0.02
        zc = 0.66 + math.cos(tilt) * length * 0.5
        _bev_box_r(bm, (rc * math.cos(a), rc * math.sin(a), zc),
                   (0.115, 0.018, length), 1,
                   rot=(tilt, 0.0, a + math.pi / 2.0), bevel=0.008)
    for i in range(6):                                    # basal rosette leaves
        a = i * math.pi / 3.0 + 0.26
        _bev_box_r(bm, (0.15 * math.cos(a), 0.15 * math.sin(a), 0.055),
                   (0.085, 0.014, 0.3), 4,
                   rot=(1.22, 0.0, a + math.pi / 2.0), bevel=0.006)
    for (fx, fy, ft) in ((0.02, 0.01, 0.1), (-0.03, 0.02, -0.14), (0.0, -0.03, 0.05)):
        n0 = len(bm.faces)                                # filaments above the rim
        ret = _bmesh.ops.create_cone(bm, cap_ends=True, segments=5,
                                     radius1=0.011, radius2=0.004, depth=0.16)
        mtx = (mathutils.Matrix.Translation((fx, fy, 0.96))
               @ mathutils.Matrix.Rotation(ft, 4, 'X'))
        _bmesh.ops.transform(bm, matrix=mtx, verts=ret["verts"])
        _hs_tag(bm, n0, 3)
    bm.to_mesh(ob.data)
    bm.free()
    _stud_spheres(ob, [(0.0, 0.0, 0.875, 0.05, 3, 0.8),   # the glowing core
                       (0.22, 0.09, 0.008, 0.022, 5, 0.35),
                       (-0.19, 0.16, 0.008, 0.018, 5, 0.35),
                       (0.05, -0.26, 0.008, 0.02, 5, 0.35),
                       (-0.28, -0.1, 0.008, 0.017, 5, 0.35),
                       (0.31, -0.14, 0.008, 0.015, 5, 0.35),
                       (-0.09, 0.3, 0.008, 0.016, 5, 0.35),
                       (0.14, 0.2, 0.06, 0.013, 5, 0.5),
                       (-0.16, -0.18, 0.1, 0.012, 5, 0.5)])
    ob["no_atlas"] = 1
    return ob


def build_capbage():
    """Card ENT-018_tended_open (OPEN state): a closet-scale head — ~1.3 m tall,
    ~1.2 m wide — of overlapping waxy leaf tiers around a pale inner bulb, the
    bottom ring sprawling outward with tips drooping toward the ground (the
    card's rosette skirt), each tier above steeper than the last until the top
    ring cups inward, a faint luminous seam-line tracing the tier boundaries,
    and the APEX OPEN: a near-black hollow capping the top with the pale apical
    meristem bud just visible above the recess. The AFFORDANCE is the cavity —
    the dark opening framed by the parted topmost leaves reads as a doorway:
    this is the plant you HIDE inside (CONCEAL_FULL, the tight-tier hide)."""
    head = [(0.0, 0.0, 0.05, 0.30), (0.02, -0.02, 0.32, 0.46),
            (-0.01, 0.02, 0.64, 0.52), (0.01, 0.0, 0.92, 0.40),
            (0.0, 0.01, 1.06, 0.22)]
    chains = [head]
    for (dx, dy) in ((0.34, 0.12), (-0.30, 0.20), (0.10, -0.36), (-0.24, -0.26)):
        chains.append([head[0], (dx, dy, 0.03, 0.09)])        # root toes gripping the substrate
    ob = _skin_growth("Capbage", chains, decimate=0.16, jitter=0.015)
    inner = _flat_mat("cf_capbage_inner", _dim(CH("moss"), 0.5), rough=0.85)    # dim inner bulb
    leaf = _flat_mat("cf_capbage_leaf", _dim(CH("moss"), 0.42), rough=0.8)      # dim waxy leaves
    seam = _flat_mat("cf_capbage_seam", _dim(CH("flora"), 0.4), CH("flora"), 0.5)
    hollow = _flat_mat("cf_capbage_hollow", _dim(CH("ground"), 0.12), rough=0.95)
    bud = _flat_mat("cf_capbage_bud", CS("resolution_root_pale"), rough=0.6)
    for m in (inner, leaf, seam, hollow, bud):
        ob.data.materials.append(m)
    bm = _bmesh.new()
    bm.from_mesh(ob.data)
    tiers = ((7, 0.00, 0.32, 0.34, -0.10, (0.54, 0.30, 0.05)),    # (count, a0, ring_r, z, tilt, size)
             (7, 0.45, 0.28, 0.63, 0.55, (0.48, 0.26, 0.045)),    # skirt droops, then steeper
             (6, 0.22, 0.20, 0.92, 1.10, (0.40, 0.22, 0.04)))     # each tier — top ring cups the cavity
    for (n, a0, rr, zc, tilt, size) in tiers:
        for i in range(n):
            a = a0 + math.tau * i / n
            t = tilt + 0.07 * math.sin(i * 2.7)                    # slight deterministic per-leaf spread
            _bev_box_r(bm, (rr * math.cos(a), rr * math.sin(a), zc),
                       size, 1, rot=(0.0, -t, a), bevel=0.012)
    hs_torus(bm, (0.0, 0.0, 0.50), 0.52, 0.018, 2, major_segs=14, minor_segs=6, axis='Z')
    hs_torus(bm, (0.0, 0.0, 0.79), 0.45, 0.016, 2, major_segs=14, minor_segs=6, axis='Z')
    bm.to_mesh(ob.data)
    bm.free()
    _stud_spheres(ob, [(0.0, 0.0, 1.14, 0.28, 3, 0.5),            # the dark hollow capping the apex
                       (0.0, 0.0, 1.30, 0.075, 4, 0.7)])          # apical meristem bud above the recess
    ob["no_atlas"] = 1
    return ob


def build_climbvine():
    """Card ENT-020_deployed: a DEPLOYED Climbvine — one rope-like segmented
    skin-growth chain hanging near-vertical ~1.8 m down an implied wall at +Y,
    bead alternation (r 0.05/0.03) giving the fibrous inter-node segments, with
    a slight S-wander. The AFFORDANCE is the hanging rope itself (you CLIMB it)
    plus the dark adventitious grip-root clusters at each wall-contact node —
    climbvine_node stud knots with small splayed rootlet cones bracing the
    substrate (canon: the rootlets read "this vine grips"). Alternating
    fiber/dim banding echoes the card's segment read; two short side tendrils."""
    pts = [(0.000, -0.030, 1.80, 0.050),
           (0.030, -0.050, 1.65, 0.030),
           (0.060, -0.040, 1.50, 0.050),
           (0.080, -0.060, 1.35, 0.030),
           (0.060, -0.030, 1.20, 0.050),
           (0.020, -0.060, 1.05, 0.030),
           (-0.030, -0.050, 0.90, 0.050),
           (-0.060, -0.070, 0.75, 0.030),
           (-0.070, -0.040, 0.60, 0.050),
           (-0.050, -0.070, 0.45, 0.030),
           (-0.020, -0.060, 0.30, 0.050),
           (0.010, -0.080, 0.15, 0.030),
           (0.030, -0.070, 0.05, 0.045)]
    tendril_a = [pts[2], (0.20, -0.09, 1.40, 0.028), (0.32, -0.13, 1.28, 0.018)]
    tendril_b = [pts[8], (-0.22, -0.10, 0.52, 0.028), (-0.33, -0.15, 0.42, 0.018)]
    ob = _skin_growth("Climbvine", [pts, tendril_a, tendril_b],
                      decimate=0.28, jitter=0.012, sub_levels=2)
    fiber = _flat_mat("cf_climbvine_fiber_m", CS("climbvine_fiber"))
    node = _flat_mat("cf_climbvine_node_m", CS("climbvine_node"), rough=0.9)
    fiber_dim = _flat_mat("cf_climbvine_fiber_dim_m", _dim(CS("climbvine_fiber"), 0.76))
    for m in (fiber, node, fiber_dim):
        ob.data.materials.append(m)
    bm = _bmesh.new()
    bm.from_mesh(ob.data)
    for f in bm.faces:                       # alternate fiber banding per segment
        cz = sum(v.co.z for v in f.verts) / len(f.verts)
        if int(cz / 0.15) % 2:
            f.material_index = 2
    for (nx, nz, angs) in ((0.00, 1.80, (2.6, 3.6, -2.4)),   # rootlet splays at
                           (0.06, 1.20, (2.2, 3.9, -2.0)),   # each grip node,
                           (-0.07, 0.60, (2.8, 3.4, -1.7))): # hugging the wall
        for a in angs:
            n0 = len(bm.faces)
            ret = _bmesh.ops.create_cone(bm, cap_ends=True, segments=4,
                                         radius1=0.013, radius2=0.003, depth=0.1)
            mtx = (mathutils.Matrix.Translation((nx + math.sin(a) * 0.055, -0.015,
                                                 nz + math.cos(a) * 0.055))
                   @ mathutils.Matrix.Rotation(a, 4, 'Y'))
            _bmesh.ops.transform(bm, matrix=mtx, verts=ret["verts"])
            _hs_tag(bm, n0, 1)
    bm.to_mesh(ob.data)
    bm.free()
    _stud_spheres(ob, [
        (0.00, -0.012, 1.80, 0.065, 1, 0.80),   # anchor knot at the top lip
        (0.06, -0.012, 1.20, 0.055, 1, 0.80),   # grip-root nodes where the
        (-0.07, -0.012, 0.60, 0.055, 1, 0.80)]) # rope touches the wall
    ob["no_atlas"] = 1
    return ob


def build_gasafoetida():
    """Card ENT-019_tended (Gasafoetida): ONE tall umbellifer stalk (CS
    gasafoetida_stalk) rising ~1.1 m to a flat-topped green umbel platform
    crowned by a CLUSTER of six upright ovoid pod-cones (CS gasafoetida_pod,
    queasy faint emission 0.8), each apex sealed with a glossy amber resin cap
    — the pod cluster IS the affordance: individually pickable, fist-sized
    held TOOLS (the sulfur repellent). A bright amber resin drop weeps at the
    lower-stalk wound-point (the reactive-chemistry tell) above two whorls of
    pinnate comb-toothed leaves, and grey gas-haze blobs rise off the cones
    (the volatile-compounds warning). Silhouette law: stalk-with-pinecones-
    on-top."""
    stalk_chain = [(0.000, 0.000, 0.00, 0.075), (0.015, -0.010, 0.28, 0.055),
                   (-0.010, 0.015, 0.58, 0.048), (0.020, 0.000, 0.86, 0.042),
                   (-0.005, -0.015, 1.08, 0.035)]
    ob = _skin_growth("Gasafoetida", [stalk_chain], decimate=0.18, jitter=0.012,
                      sub_levels=2)
    stalk = _flat_mat("cf_gasafoetida_stalk", CS("gasafoetida_stalk"))
    pod = _flat_mat("cf_gasafoetida_pod", CS("gasafoetida_pod"),
                    _dim(CS("gasafoetida_pod"), 0.6), emit_strength=0.8)
    resin = _flat_mat("cf_gasafoetida_resin", _dim(CG("warning_amber"), 0.7),
                      CG("warning_amber"), emit_strength=1.4)
    leaf = _flat_mat("cf_gasafoetida_leaf", _dim(CS("gasafoetida_stalk"), 0.8))
    haze = _flat_mat("cf_gasafoetida_haze", _dim(CS("gasafoetida_pod"), 0.55),
                     rough=1.0)
    for m in (stalk, pod, resin, leaf, haze):
        ob.data.materials.append(m)
    studs = [(0.01, -0.01, 1.24, 0.090, 1, 1.3),          # centre pod-cone
             (0.01, -0.01, 1.36, 0.024, 2, 0.8)]          # its resin seal cap
    for i in range(5):                                    # the umbel ring of cones
        a = math.tau * i / 5.0 + 0.3
        px, py = 0.135 * math.cos(a), 0.135 * math.sin(a)
        studs.append((px, py, 1.21, 0.082, 1, 1.3))
        studs.append((px, py, 1.32, 0.022, 2, 0.8))       # apex resin cap
    studs.append((0.055, 0.015, 0.46, 0.045, 2, 1.6))     # resin drop at the wound-point
    _stud_spheres(ob, studs)
    bm = _bmesh.new()
    bm.from_mesh(ob.data)
    hs_prism(bm, (0.0, 0.0, 1.10), 0.23, 0.20, 0.06, 0, sides=9, bevel=0.012)
    for (count, phase, z0, ln, droop, teeth) in ((6, 0.22, 0.38, 0.36, 0.22, 3),
                                                 (3, 1.15, 0.24, 0.24, 0.34, 2)):
        for i in range(count):                            # pinnate comb-leaf whorls
            az = phase + math.tau * i / count
            ca, sa = math.cos(az), math.sin(az)
            rc = 0.05 + 0.5 * ln * math.cos(droop)
            _bev_box_r(bm, (rc * ca, rc * sa, z0 - 0.5 * ln * math.sin(droop)),
                       (ln, 0.026, 0.018), 3, rot=(0.0, droop, az), bevel=0.006)
            for k in range(teeth):                        # upward leaflet teeth
                d = 0.09 + k * (ln - 0.09) / (teeth + 1)
                _bev_box_r(bm, ((0.05 + d) * ca, (0.05 + d) * sa,
                                z0 - d * math.sin(droop) + 0.035),
                           (0.02, 0.05, 0.06), 3, rot=(0.0, droop * 1.6, az),
                           bevel=0.005)
    bm.to_mesh(ob.data)
    bm.free()
    ob["no_atlas"] = 1
    return ob



# ---- FLORA v3: pushed toward the ENT card RENDERS after inspecting them directly.
# ---- (The ENT source models are billboard CARDS — 4-vert quads carrying painted
# ---- textures — so they cannot serve as 3D props for a rotating camera. The cards
# ---- are the visual target; these are real geometry built to hit it.)

def build_scarpet():
    """CARD ENT-015_tended: NOT a smooth mat — a DENSE VOXEL MASS of hundreds of
    small upright blades crowding a dark soil bed, green shot through with rust-
    orange senescing blades and a few pale spikes standing proud. Low enough to
    lie under (CONCEAL_MEDIUM): the mass tops out ~0.3 m over a 1.2 x 1.0 bed."""
    bm = _bmesh.new()
    M_SOIL, M_GREEN, M_GREEN_D, M_RUST, M_PALE = 0, 1, 2, 3, 4
    _bev_box(bm, (0, 0, 0.035), (1.24, 1.02, 0.07), M_SOIL, bevel=0.012)     # soil bed
    for sx in (-0.62, 0.62):                                                  # bed kerb
        _bev_box(bm, (sx, 0, 0.055), (0.06, 1.02, 0.11), M_SOIL, bevel=0.01)
    for sy in (-0.51, 0.51):
        _bev_box(bm, (0, sy, 0.055), (1.24, 0.06, 0.11), M_SOIL, bevel=0.01)
    # the blade mass: a deterministic lattice with per-blade jitter, height falloff
    # toward the edges so the clump reads as a mound rather than a flat brush.
    cols, rows = 17, 14
    for j in range(rows):
        for i in range(cols):
            u = (i + 0.5) / cols - 0.5
            v = (j + 0.5) / rows - 0.5
            h = ((i * 7 + j * 13) % 11)                                       # stable pseudo-random
            k = (i * 5 + j * 3) % 7
            jx = ((h % 3) - 1) * 0.018
            jy = ((k % 3) - 1) * 0.018
            edge = 1.0 - min(1.0, (abs(u) * 2.0) ** 2 + (abs(v) * 2.0) ** 2) * 0.55
            bh = (0.13 + 0.030 * h) * max(0.35, edge)                         # blade height
            if bh < 0.08:
                continue
            mat = M_GREEN
            if h in (2, 6):
                mat = M_RUST
            elif h in (4, 9):
                mat = M_GREEN_D
            elif h == 10 and k == 3:
                mat = M_PALE
            _bev_box_r(bm, (u * 1.1 + jx, v * 0.92 + jy, 0.07 + bh * 0.5),
                       (0.038, 0.034, bh), mat,
                       rot=(0.14 * (jy / 0.018 if jy else 0.0),
                            0.12 * (jx / 0.018 if jx else 0.0),
                            0.3 * ((h % 5) - 2)), bevel=0.006)
    for (px, py, ph) in ((-0.24, 0.18, 0.30), (0.30, -0.12, 0.27), (0.06, 0.34, 0.25)):
        _bev_box_r(bm, (px, py, 0.07 + ph * 0.5), (0.035, 0.035, ph), M_PALE,
                   rot=(0.0, 0.0, 0.6), bevel=0.005)                          # pale spikes proud
    return _hs_finish("Scarpet", bm, [
        _flat_mat("cf3_scarpet_soil", _dim(CH("ground"), 0.55), rough=0.95),
        _flat_mat("cf3_scarpet_green", CS("scarpet_blade"), rough=0.9),
        _flat_mat("cf3_scarpet_greend", CS("scarpet_blade_deep"), rough=0.9),
        _flat_mat("cf3_scarpet_rust", CS("scarpet_senesce"), rough=0.85),
        _flat_mat("cf3_scarpet_pale", CS("resolution_root_pale"), rough=0.9)])


def build_climbvine():
    """CARD ENT-020_deployed: a PALE rope-vine (bone/beige, not green) hanging
    down a surface in a slack curve — a chain of segments with periodic SWOLLEN
    knuckles, small dark grip-roots spiking out under each knuckle where it grabs.
    Wall piece: the back hugs +Y, the rope descends the face."""
    y = -0.06
    seg = [(0.60, y, 1.92, 0.055), (0.44, y, 1.72, 0.05), (0.28, y, 1.50, 0.062),
           (0.14, y, 1.26, 0.048), (0.02, y, 1.02, 0.06), (-0.08, y, 0.78, 0.046),
           (-0.14, y, 0.54, 0.058), (-0.16, y, 0.30, 0.044), (-0.14, y, 0.10, 0.05)]
    chains = [seg]
    chains.append([seg[2], (0.42, y - 0.04, 1.38, 0.03), (0.52, y - 0.05, 1.22, 0.02)])
    chains.append([seg[5], (-0.26, y - 0.04, 0.66, 0.028), (-0.36, y - 0.05, 0.52, 0.018)])
    ob = _skin_growth("Climbvine", chains, decimate=0.3, jitter=0.008, sub_levels=2)
    fiber = _flat_mat("cf3_vine_fiber", CS("climbvine_fiber"), rough=0.9)
    knuckle = _flat_mat("cf3_vine_knuckle", _dim(CS("climbvine_fiber"), 0.88), rough=0.85)
    node = _flat_mat("cf3_vine_node", CS("climbvine_node"), rough=0.95)
    for m in (fiber, knuckle, node):
        ob.data.materials.append(m)
    knuckles = [(0.28, y, 1.50, 0.135), (0.02, y, 1.02, 0.128),
                (-0.14, y, 0.54, 0.122), (0.44, y, 1.72, 0.105),
                (0.14, y, 1.26, 0.088), (-0.08, y, 0.78, 0.084)]
    _stud_spheres(ob, [(x, yy, z, r, 1, 0.85) for (x, yy, z, r) in knuckles])
    grips = []
    for (kx, ky, kz, kr) in knuckles:                        # grip-roots under each knuckle
        for d in (-1.0, 1.0):
            grips.append((kx + d * kr * 0.85, ky - 0.03, kz - kr * 0.55, 0.026, 2, 1.0))
        grips.append((kx, ky - 0.05, kz - kr * 0.8, 0.022, 2, 1.0))
    _stud_spheres(ob, grips)
    ob["no_atlas"] = 1
    return ob


def build_seefern():
    """CARD ENT-014_tended: a fern-LANTERN — dark translucent blades whose light
    is the bright teal vasculature. Denser than a few fronds: seven blades fanning
    from a mossy pad, each carrying a bright rachis strip with herringbone leaflet
    dashes, a dark EYE stud on each dash (the 'this plant sees' affordance), and a
    curled fiddlehead tip on the young ones."""
    bm = _bmesh.new()
    M_MOSS, M_LEAF, M_VEIN, M_EYE = 0, 1, 2, 3
    hs_prism(bm, (0, 0, 0.03), 0.26, 0.30, 0.06, M_MOSS, sides=9, bevel=0.012)  # mossy pad
    studs = []
    fronds = [(0.25, 0.10, 0.70, 0.20), (1.15, 0.30, 0.60, 0.185),
              (2.05, 0.36, 0.55, 0.175), (2.95, 0.40, 0.50, 0.165),
              (3.85, 0.34, 0.58, 0.18), (4.75, 0.26, 0.64, 0.19),
              (5.60, 0.52, 0.30, 0.10)]
    for fi, (a, tilt, L, W) in enumerate(fronds):
        dx, dy = math.sin(a), math.cos(a)
        for k in range(4):                                                    # blade in 4 steps
            t = (k + 0.5) / 4.0
            zc = 0.06 + math.cos(tilt) * L * t
            rr = math.sin(tilt) * L * t
            _bev_box_r(bm, (dx * rr, dy * rr, zc), (W * (1.15 - 0.45 * t), 0.03, L / 3.4),
                       M_LEAF, rot=(tilt, 0.0, a), bevel=0.006)
            _bev_box_r(bm, (dx * rr, dy * rr - 0.018, zc),
                       (W * 0.10, 0.036, L / 3.8), M_VEIN, rot=(tilt, 0.0, a), bevel=0.003)
            if k < 3 and L > 0.4:                                             # leaflet dashes + eyes
                for side in (-1.0, 1.0):
                    ox = dx * rr + math.cos(a) * side * W * 0.30
                    oy = dy * rr - math.sin(a) * side * W * 0.30
                    _bev_box_r(bm, (ox, oy - 0.02, zc), (W * 0.30, 0.032, 0.020), M_VEIN,
                               rot=(tilt, 0.0, a), bevel=0.003)
                    studs.append((ox, oy - 0.042, zc, 0.019, M_EYE, 0.7))
        tipz = 0.06 + math.cos(tilt) * L * 1.02
        tipr = math.sin(tilt) * L * 1.02
        hs_torus(bm, (dx * tipr, dy * tipr, tipz), 0.075 if L > 0.4 else 0.055, 0.019,
                 M_VEIN, major_segs=10, minor_segs=5, axis='Y')               # fiddlehead donut
    ob = _hs_finish("Seefern", bm, [
        _flat_mat("cf3_fern_moss", _dim(CH("moss"), 0.8), _dim(CS("seefern_vein"), 0.25), 0.6),
        _flat_mat("cf3_fern_leaf", CS("seefern_leaf"), rough=0.92),
        _flat_mat("cf3_fern_vein", CS("seefern_vein_core"), CS("seefern_vein"), 1.5),
        _flat_mat("cf3_fern_eye", _dim(CS("seefern_leaf"), 0.16), rough=0.95)])
    _stud_spheres(ob, studs)
    return ob


# ---- FLORA v4: FOLIAGE IS DRAWN ------------------------------------------------------------
# (Director, 2026-08-10.) Leaves are pixel-art CARDS, never solid leaf-shaped meshes.
# What holds the form stays modelled — a pad, a stem, a vine's body — and what
# REPEATS is drawn. A frond built from stacked boxes spends ~14 primitives to alias
# into mush at gameplay distance; the same frond drawn on one card keeps its blade
# silhouette, its vein and its eye-marks crisp at every distance, and leaves the
# detail where an artist can repaint it. Scale is the house scale: 1 m = 32 px
# (Seefern runs at 48 for its eye-marks).

# ---- STATE VARIANTS ------------------------------------------------------------------------
# Every tendable species has states the spec treats as the point of the tending
# loop — wild vs tended, charged vs triggered, open vs sealed — and until now each
# species shipped exactly one body, so tending had nothing to show for itself.
#
# A variant is one more node in the same gltf, named `<Piece>__<state>`. The
# DEFAULT state also ships under the bare `<Piece>` name, so every existing lookup
# keeps working untouched and a caller opts in to a state by asking for one.

# Each species' DEFAULT state is the one that keeps the bare piece name, and it is
# not the same word for every species: a fern's resting state is how well it has
# been tended, a stun plant's is whether it is loaded. Getting this wrong ships a
# gltf with no bare `Hushbloom` node at all and every existing lookup breaks.
FLORA_DEFAULT_STATE = {
    "Seefern": "tended",
    "Scarpet": "tended",
    "Hushbloom": "charged",
}


def piece_state_name(piece, state):
    """`Seefern` for that species' default state, `Seefern__wild` for the rest."""
    if not state or state == FLORA_DEFAULT_STATE.get(piece, "tended"):
        return piece
    return "%s__%s" % (piece, state)


def _seefern_frond_art(tile, isl, px_per_m, vein_gain=1.0, eye_open=1.0):
    """CARD ENT-014_tended, drawn. The spec is emphatic about two things and both
    are the painter's job.

    The VASCULATURE IS THE LIGHT: "bright glowing veins ... the vasculature-as-
    lantern is the read at any distance", with the tissue between veins "darker
    translucent green, almost shadowed". So the veins are written into the card's
    EMISSIVE plane and the tissue is left nearly black — a fern that emits nothing
    is not a Seefern, whatever its silhouette.

    The EYE-MARKINGS ARE THE AFFORDANCE: "a darker oval mark at each leaflet's
    CENTER, ringed by the brighter vein-glow", telling the player this plant sees.
    Each leaflet therefore gets a dark oval at its middle with lit vein texels
    around it, not a dot at its tip.

    The silhouette is PINNATE: leaflets are cut apart by real alpha notches, in
    the spec's rounded-diamond shape, so the frond reads as a fern and not a
    plank. Rows run base-to-tip (v-up)."""
    ph, pw = tile.shape[:2]
    emit = isl["emit"]
    tissue = _dim(CS("seefern_leaf"), 0.55)          # "almost shadowed"
    tissue_d = _dim(CS("seefern_leaf"), 0.35)
    # STATE is the vein brightness and the eye aperture, exactly as the spec puts
    # it: wild glows low with the eyes nearly closed, tended runs at full with the
    # eyes clearly outward-facing, stressed burns overdriven with them wide open.
    vein = _clamp_rgb(_dim(CS("seefern_vein"), vein_gain))
    core = _clamp_rgb(_dim(CS("seefern_vein_core"), min(1.0, vein_gain)))
    eye = _dim(CS("seefern_leaf"), 0.12)
    tile[:, :, 3] = 0.0
    mid = int(round((pw - 1) * 0.5))

    # the rachis: bright base-to-tip, and the brightest thing on the card
    for row in range(ph):
        tile[row, mid, :3] = core
        tile[row, mid, 3] = 1.0
        emit[row, mid] = vein

    pitch = max(2, int(round(0.055 * px_per_m)))     # leaflet spacing along the rachis
    for row in range(0, ph, pitch):
        t = row / float(max(1, ph - 1))
        reach = int(round((pw * 0.5) * (1.0 - 0.55 * t)))
        if reach < 1:
            continue
        half = max(1, pitch // 2)                    # the leaflet's own half-height
        for side in (-1, 1):
            for k in range(1, reach + 1):
                # rounded diamond: narrow at the rachis, full mid-leaflet, tapering out
                span = int(round(half * (1.0 - abs(k - reach * 0.5) / max(1.0, reach))))
                for dy in range(-span, span + 1):
                    r2 = row + dy
                    col = mid + side * k
                    if not (0 <= r2 < ph and 0 <= col < pw):
                        continue
                    tile[r2, col, :3] = tissue if dy == 0 else tissue_d
                    tile[r2, col, 3] = 1.0
                    if dy == 0:                      # the branching vein into the leaflet
                        emit[r2, col] = _dim(vein, 0.85)
                        tile[r2, col, :3] = vein
            # the EYE: a dark oval at the leaflet's centre, ringed by lit vein
            ec = mid + side * max(1, int(round(reach * 0.55)))
            if 0 <= ec < pw and eye_open > 0.25:
                tile[row, ec, :3] = eye
                emit[row, ec] = (0.0, 0.0, 0.0)      # the pupil does not glow
                for dy in (-1, 1):
                    r2 = row + dy
                    if 0 <= r2 < ph and tile[r2, ec, 3] > 0.5:
                        tile[r2, ec, :3] = core       # the ring around it
                        emit[r2, ec] = vein
                if eye_open > 1.15:                   # wide open: the pupil widens too
                    wc = ec + side
                    if 0 <= wc < pw and tile[row, wc, 3] > 0.5:
                        tile[row, wc, :3] = eye
                        emit[row, wc] = (0.0, 0.0, 0.0)

    # the fiddlehead: a young tip curling back on itself, drawn as a lit hook
    for (dy, dx) in ((1, 0), (2, 0), (3, 1), (3, 2), (2, 3), (1, 3), (0, 2)):
        r2, c2 = ph - 1 - dy, mid + dx - 1
        if 0 <= r2 < ph and 0 <= c2 < pw:
            tile[r2, c2, :3] = core
            tile[r2, c2, 3] = 1.0
            emit[r2, c2] = vein


def _clamp_rgb(c):
    return tuple(min(1.0, max(0.0, v)) for v in c)


# One art per STATE. For a drawn species a state is a REPAINT, not a remodel —
# which is most of the argument for cards: three Seeferns cost three textures and
# no extra geometry at all.
SEEFERN_STATES = {
    "tended":   (1.00, 1.00),
    "wild":     (0.45, 0.20),
    "stressed": (1.55, 1.35),
}
SEEFERN_FROND_ART = {}
for _st, (_g, _e) in SEEFERN_STATES.items():
    def _mk_seefern(gain, aperture):
        def _paint(tile, isl, px_per_m):
            _seefern_frond_art(tile, isl, px_per_m, vein_gain=gain, eye_open=aperture)
        return _paint
    SEEFERN_FROND_ART[_st] = pl.register_card_art("seefern_frond_" + _st,
                                                  _mk_seefern(_g, _e))
SEEFERN_FROND = SEEFERN_FROND_ART["tended"]


def build_seefern(state="tended"):
    """The fern-LANTERN, its blades DRAWN. Seven fronds fan from a modelled mossy
    pad; each frond is ONE card carrying the blade, the glowing rachis, the
    leaflets and the eye-marks. The pad stays geometry because it is what the fern
    stands on; the foliage is texture because foliage repeats.

    The three states differ almost entirely in their PAINT — wild glows low with
    the eyes nearly shut, tended runs at full, stressed burns overdriven with them
    wide. A wild specimen is also smaller, per the spec's smaller light range."""
    b = Builder()
    scale = {"tended": 1.0, "wild": 0.82, "stressed": 1.06}.get(state, 1.0)
    b.ngon_prism((0, 0), 0.26 * scale, 0.30 * scale, 0.06, "seefern_pad", sides=9)
    fronds = [(0.25, 0.10, 0.70, 0.20), (1.15, 0.30, 0.60, 0.185),
              (2.05, 0.36, 0.55, 0.175), (2.95, 0.40, 0.50, 0.165),
              (3.85, 0.34, 0.58, 0.18), (4.75, 0.26, 0.64, 0.19),
              (5.60, 0.52, 0.30, 0.10)]
    art = SEEFERN_FROND_ART.get(state, SEEFERN_FROND_ART["tended"])
    for (a, tilt, L, W) in fronds:
        L *= scale
        rr = math.sin(tilt) * L * 0.5
        zc = 0.06 + math.cos(tilt) * L * 0.5
        b.card((math.sin(a) * rr, math.cos(a) * rr, zc), (W * 1.15 * scale, L),
               "seefern_blade", axis='Y', art=art, rot=(tilt, 0.0, a))
    return b.finish(piece_state_name("Seefern", state))


def _scarpet_mat_art(tile, isl, px_per_m, iron=0.55):
    """CARD ENT-015: the TWO-TONE MOSS CARPET, drawn. The spec's silhouette
    priority is the two colours read at a glance — pale green living moss shot
    through with rust-orange patches where iron has precipitated in the tissue —
    and its affordance is the SUBSTRATE: under a fully metabolized patch the
    ground is scoured bleach-pale, which is what tells a player the iron is gone
    here and why siderophores arc around it.

    So the carpet is painted in three passes: living moss, the rust scars worked
    through it like wound tissue, and the bleached substrate showing where the
    moss has finished its work and thinned. The boundary is irregular and the
    edge is ragged — a rug, never a rectangle — because a straight edge would
    read as a decal laid on the floor instead of something that grew there."""
    ph, pw = tile.shape[:2]
    green = CS("scarpet_blade")
    green_d = CS("scarpet_blade_deep")
    rust = CS("scarpet_senesce")
    rust_d = _dim(CS("scarpet_senesce"), 0.55)
    bleach = _dim(CH("ground"), 1.9)

    def h2(x, y, s):                                   # deterministic value noise
        n = (x * 73856093) ^ (y * 19349663) ^ (s * 83492791)
        n = (n ^ (n >> 13)) & 0xFFFFFFF
        return (n % 1000) / 1000.0

    def smooth(x, y, cell, s):
        gx, gy = x // cell, y // cell
        fx, fy = (x % cell) / cell, (y % cell) / cell
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        a, b = h2(gx, gy, s), h2(gx + 1, gy, s)
        c, d = h2(gx, gy + 1, s), h2(gx + 1, gy + 1, s)
        return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

    cell = max(3, int(round(0.22 * px_per_m)))
    cx, cy = (pw - 1) * 0.5, (ph - 1) * 0.5
    for y in range(ph):
        for x in range(pw):
            # ragged boundary: a circle pushed in and out by low-frequency noise
            dx, dy = (x - cx) / cx, (y - cy) / cy
            r = (dx * dx + dy * dy) ** 0.5
            if r > 0.62 + 0.34 * smooth(x, y, cell * 2, 5):
                tile[y, x, 3] = 0.0
                continue
            tile[y, x, 3] = 1.0
            # STATE is how far the moss has got through the iron: a wild patch is
            # mostly green with limited streaking, a tended one is worked through,
            # a senescent one has metabolized everything and is nearly all rust.
            worked = smooth(x, y, cell, 1) + (iron - 0.55)
            fleck = h2(x, y, 9)
            if worked > 0.66:                          # fully metabolized: scoured
                col = bleach if fleck > 0.72 else rust_d
            elif worked > 0.52:                        # the rust scar itself
                col = rust if fleck > 0.35 else rust_d
            else:                                      # living moss, leafy fleck
                col = green if fleck > 0.42 else green_d
            tile[y, x, :3] = col


def _scarpet_tuft_art(tile, isl, px_per_m):
    """A pillowy rise of the same carpet seen edge-on: the spec puts the body of
    the mat 5-10 cm off the substrate, so a few of these keep it from reading as
    a decal painted on the floor. Domed top, ragged edges, same two tones."""
    ph, pw = tile.shape[:2]
    green = CS("scarpet_blade")
    green_d = CS("scarpet_blade_deep")
    rust = CS("scarpet_senesce")
    tile[:, :, 3] = 0.0
    cx = (pw - 1) * 0.5
    for x in range(pw):
        t = abs(x - cx) / max(1.0, cx)
        top = int(round(ph * (1.0 - 0.45 * t * t)))    # the dome
        n = ((x * 37) % 5) - 2
        top = max(1, min(ph, top + n))
        for y in range(top):
            tile[y, x, 3] = 1.0
            k = ((x * 13 + y * 7) % 11)
            tile[y, x, :3] = rust if k == 2 else (green if k > 4 else green_d)


SCARPET_STATES = {"tended": 0.55, "wild": 0.30, "senescent": 0.86}
SCARPET_MAT_ART = {}
for _st, _iron in SCARPET_STATES.items():
    def _mk_scarpet(iron):
        def _paint(tile, isl, px_per_m):
            _scarpet_mat_art(tile, isl, px_per_m, iron=iron)
        return _paint
    SCARPET_MAT_ART[_st] = pl.register_card_art("scarpet_mat_" + _st, _mk_scarpet(_iron))
SCARPET_MAT = SCARPET_MAT_ART["tended"]
SCARPET_TUFT = pl.register_card_art("scarpet_tuft", _scarpet_tuft_art)


def build_scarpet(state="tended"):
    """CARD ENT-015 — the two-tone moss carpet, DRAWN. The spec's form is a low
    dense mat "rising 5-10 centimetres off the substrate", and the runtime agrees:
    scarpet.gd is a mat you STAND ON, not cover you hide inside. The previous
    build stood a 0.3 m mass of ~240 blade boxes, which was neither.

    The carpet is one ground card carrying the living moss, the rust scars and
    the bleached substrate the metabolized patches leave behind; a low ring of
    pillow tufts gives it the body the spec asks for so it never reads as a decal
    painted on the floor."""
    b = Builder()
    # a wild patch is small, a tended one has spread; the spec makes patch SIZE
    # part of the state as much as the colour balance is
    size = {"tended": 1.0, "wild": 0.68, "senescent": 0.94}.get(state, 1.0)
    art = SCARPET_MAT_ART.get(state, SCARPET_MAT_ART["tended"])
    b.card((0, 0, 0.012), (1.36 * size, 1.14 * size), "scarpet_mat", axis='Z', art=art)
    tufts = [(-0.34, -0.22, 0.44, 0.9), (0.28, -0.30, 0.40, -0.4),
             (0.40, 0.20, 0.36, 1.9), (-0.16, 0.34, 0.42, 2.7),
             (-0.50, 0.10, 0.30, 0.3), (0.10, -0.02, 0.34, 1.2)]
    for (px, py, w, yaw) in tufts:
        b.card((px * size, py * size, 0.045), (w * size, 0.09), "scarpet_moss",
               axis='Y', art=SCARPET_TUFT, rot=(0.0, 0.0, yaw))
    return b.finish(piece_state_name("Scarpet", state))


def _hushbloom_leaf_art(tile, isl, px_per_m, splay=1.0, pulv_gain=1.0):
    """CARD ENT-017_charged: a COMPOUND LEAF, drawn. The card's read is a dark
    rachis carrying BRIGHT paired leaflets stepping along it — the comb, which is
    the spec's silhouette priority — and the swollen PULVINUS at each attachment,
    which is the affordance: the swelling is what tells a player these leaflets
    fold reactively, before they have ever triggered one.

    Both are marks, so both are painted. The rachis runs dark purple-olive, the
    leaflets are pale and paired in opposite ranks, and each pair sits on a
    brighter bead. Rows run base-to-tip (v-up)."""
    ph, pw = tile.shape[:2]
    rachis = _dim(CS("hushbloom_stem"), 0.55)
    rachis_d = _dim(CS("hushbloom_stem"), 0.32)
    leaflet = CS("hushbloom_bloom")
    leaflet_d = _dim(CS("hushbloom_bloom"), 0.55)
    pulv = _dim(CS("hushbloom_bloom"), 1.0)
    tile[:, :, 3] = 0.0
    mid = int(round((pw - 1) * 0.5))
    for row in range(ph):
        tile[row, mid, :3] = rachis if row % 4 else rachis_d
        tile[row, mid, 3] = 1.0
    pairs = max(4, min(12, int(round(0.5 + ph / max(2.0, 0.055 * px_per_m)))))
    for p in range(pairs):
        t = (p + 0.5) / float(pairs)
        row = int(round(t * (ph - 1)))
        # STATE is the SPLAY: charged leaflets stand open across the full width,
        # triggered ones have folded inward along the rachis into a narrow fan.
        reach = int(round((pw * 0.5) * (1.0 - 0.42 * t) * splay))
        if reach < 1:
            continue
        for side in (-1, 1):
            for k in range(1, reach + 1):
                col = mid + side * k
                if not (0 <= col < pw):
                    continue
                # the leaflet: bright, with its darker underside trailing behind
                tile[row, col, :3] = leaflet if k < reach else leaflet_d
                tile[row, col, 3] = 1.0
            pc = mid + side
            if 0 <= pc < pw:
                # a deflated pulvinus is the "already fired" read
                tile[row, pc, :3] = _dim(pulv, pulv_gain)
                tile[row, pc, 3] = 1.0
    if ph >= 2:
        tile[ph - 1, mid, :3] = pulv
        tile[ph - 1, mid, 3] = 1.0


HUSHBLOOM_STATES = {          # (leaflet splay, pulvinus brightness)
    "charged":    (1.00, 1.00),
    "triggered":  (0.34, 0.42),
    "recharging": (0.42, 0.72),
}
HUSHBLOOM_LEAF_ART = {}
for _st, (_sp, _pg) in HUSHBLOOM_STATES.items():
    def _mk_hush(splay, gain):
        def _paint(tile, isl, px_per_m):
            _hushbloom_leaf_art(tile, isl, px_per_m, splay=splay, pulv_gain=gain)
        return _paint
    HUSHBLOOM_LEAF_ART[_st] = pl.register_card_art("hushbloom_leaf_" + _st,
                                                   _mk_hush(_sp, _pg))
HUSHBLOOM_LEAF = HUSHBLOOM_LEAF_ART["charged"]


def build_hushbloom(state="charged"):
    """CARD ENT-017_charged — the comb-leaf stun plant, DRAWN.

    The card shows one thing and the spec says the same: a plant "lower and more
    spread than upright, fern-like in posture", a wide low rosette of compound
    leaves arcing outward over a small damp mound, bright paired leaflets
    stepping along dark rachises, green sprigs crowding the base. There is no
    flower on it. The previous build stood a nodding stem with a closed lavender
    bell hanging off the nod — a bloom that appears in no state card and in no
    line of the spec, which also made the plant read tall when the whole species
    reads low.

    Cards carry the leaves, because a comb of leaflets is repetition and its
    pulvini are marks. The mound stays geometry, because it is what the plant
    sits on."""
    b = Builder()
    b.ngon_prism((0, 0), 0.20, 0.26, 0.05, "hushbloom_soil", sides=9)
    # low and WIDE: the leaves arc out near the horizontal, not up
    leaves = [(0.30, 1.14, 0.52), (1.10, 1.22, 0.46), (1.95, 1.08, 0.50),
              (2.70, 1.26, 0.44), (3.55, 1.12, 0.52), (4.35, 1.20, 0.47),
              (5.10, 1.06, 0.49), (5.85, 1.24, 0.43)]
    art = HUSHBLOOM_LEAF_ART.get(state, HUSHBLOOM_LEAF_ART["charged"])
    # a triggered leaf droops: the spec has the compound leaf hanging along the
    # stem in a folded fan once it has fired
    droop = {"charged": 0.0, "triggered": 0.22, "recharging": 0.14}.get(state, 0.0)
    for (a, tilt, L) in leaves:
        tilt += droop
        rr = math.sin(tilt) * L * 0.5
        zc = 0.05 + math.cos(tilt) * L * 0.5
        b.card((math.sin(a) * rr, math.cos(a) * rr, zc), (L * 0.46, L),
               "hushbloom_leaf", axis='Y', art=art, rot=(tilt, 0.0, a))
    # the sprigs crowding the mound edge, as the card shows
    for i in range(7):
        a = i * math.tau / 7.0 + 0.4
        b.box((math.sin(a) * 0.21, math.cos(a) * 0.21, 0.075),
              (0.05, 0.05, 0.07), "hushbloom_sprig")
    return b.finish(piece_state_name("Hushbloom", state))
