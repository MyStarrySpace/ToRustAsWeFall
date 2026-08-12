"""
gen_building_sheets.py — render the §5 KIT-OF-PARTS SHEETS from bld_kit.py.

One labeled row per §3 knob (windows / doors / crowns / projections / columns /
signage / signforms) + the materials+decay swatch sheet — each matched against its
reference in reference-images/architecture/sheets/<name>.png.

Run:  python /c/tmp/blsend.py < blender/skills/building-generation/gen_building_sheets.py
Renders C:\\tmp\\kitsheet_<name>.png for every sheet.
"""
import bpy, bmesh, math, sys, importlib
from mathutils import Vector

SKILL = r"C:\Users\quest\Programming\Games\ToRustAsWeFall\blender\skills\building-generation"
if SKILL not in sys.path: sys.path.insert(0, SKILL)
import helpers as H
importlib.reload(H)
import bld_kit as K
importlib.reload(K)

OUT = r"C:\tmp"

# (label, fn, slot_width, lift) — lift = z offset for wall parts whose origin is the aperture centre
SHEETS = {
    'windows': [
        ("(1)\nmembrane-pore", K.win_membrane_pore, 2.7, 1.65),
        ("(2)\ncapillary-slit pair", K.win_capillary_pair, 2.7, 1.95),
        ("(3)\nbalcony-bay", K.win_balcony_bay, 3.0, 2.15),
        ("(4)\ndrawer-window band", K.win_drawer_band, 3.2, 1.55),
        ("(5)\nrolling shutter", K.win_shuttered, 2.7, 1.45),
        ("(6)\nhoneycomb cell", K.win_honeycomb_cell, 2.7, 1.45),
        ("(7)\nrose aperture + vent", K.win_rose_spoked, 3.6, 1.55),
    ],
    'doors': [
        ("(1)\niris-membrane pore", K.door_dilating, 3.4, 0.0),
        ("(2)\ncycling dwelling-slab", K.door_cycling_slab, 3.4, 0.0),
        ("(3)\ntag-reader scan-arch", K.door_scan_arch, 3.6, 0.0),
        ("(4)\n'Flow Optimization'\ntoll-meter gate", K.door_toll_gate, 3.2, 0.0),
        ("(5)\nsealed blast-bulkhead", K.door_blast_bulkhead, 3.4, 0.0),
    ],
    'crowns': [
        ("(1)\ndomed cap", K.crown_domed_cap, 3.6, 0.0),
        ("(2)\nbranched canopy", K.crown_branched_canopy, 3.4, 0.0),
        ("(3)\nplanted terrace", K.crown_planted_terrace, 3.2, 0.0),
        ("(4)\nrenewable crown", K.crown_renewable, 3.4, 0.0),
        ("(5)\nmembrane vent-cap", K.crown_pore_vent_cap, 2.9, 0.0),
        ("(6)\nspire cluster", K.crown_spired_cluster, 3.2, 0.0),
        ("(7)\nvent flare-stack", K.crown_flare_stack, 3.0, 0.0),
    ],
    'projections': [
        ("(1)\nmembrane-awning", K.proj_translucent_canopy, 3.0, 3.0),
        ("(2)\nmetal slat-canopy", K.proj_slat_canopy, 3.0, 3.0),
        ("(3)\ncantilevered balcony", K.proj_cantilever_balcony, 3.0, 2.2),
        ("(4)\nsignage bracket-arm", K.proj_signage_bracket, 2.8, 0.0),
        ("(5)\nanti-homeless\nno-stand ledge", K.proj_hostile_ledge, 2.8, 2.6),
        ("(6)\ncurved entry-hood", K.proj_entry_hood, 3.0, 0.0),
        ("(7)\ntransit-viaduct conduit", K.proj_transit_viaduct, 4.0, 0.0),
    ],
    'columns': [
        ("(1)\nbranching\ntree-column", K.col_tree_column, 3.6, 0.0),
        ("(2)\nmushroom-canopy\ncolumn", K.col_mushroom, 4.2, 0.0),
        ("(3)\nwaisted\nload pier", K.col_tapered_pier, 2.8, 0.0),
        ("(4)\nclustered\nbuttress-fin", K.col_buttress_fin, 3.2, 0.0),
        ("(5)\nvine-ribs\nwall webbing", K.col_vine_rib_web, 3.2, 0.0),
        ("(6)\nopen strut-truss\nelevated conduit", K.col_strut_truss, 4.0, 0.0),
    ],
    'signage': [
        ("(1)\ninstitutional-project\nwall-plaque", K.sign_wall_plaque, 3.6, 0.0),
        ("(2)\ngovernment-aspirational\nbacklit arch-banner", K.sign_arch_banner, 4.6, 0.0),
        ("(3)\ncorporate-rebrand\nhanging bracket-sign", K.sign_bracket_hanging, 3.4, 0.0),
        ("(4)\npicturesque-community\nmonument-plaque", K.sign_monument, 4.0, 0.0),
    ],
    'signforms': [
        ("(1)\nregulatory placards", K.signform_regulatory, 3.4, 0.0),
        ("(2)\nsector designator", K.signform_numeric, 2.6, 0.0),
        ("(3)\nstatus readout board", K.signform_status, 3.0, 0.0),
        ("(4)\nfloor toll projection", K.signform_floor_toll, 2.8, 0.0),
        ("(5)\ndistrict emblems", K.signform_emblems, 4.4, 0.0),
    ],
}

MATERIALS_ROW = [('metal', "riveted\npanel-seam"), ('diamond', "diamond-plate"), ('grate', "crosshatch\ngrating"),
                 ('membrane', "basement-\nmembrane"), ('cabling', "wrapped\ncabling"), ('substrate', "grooved\nsubstrate"),
                 ('shingle', "fish-scale\nshingle"), ('tracery', "whiplash\ntracery"), ('voronoi', "cellular\nmesh-screen"),
                 ('hexrelief', "honeycomb\nrelief")]
DECAY_ROW = [('ferric', "ferric\nbleed"), ('dust', "oxide\ndust"), ('char', "char-burn\ncrust"),
             ('weep', "weeping\ncorrosion"), ('crack', "collapse-scar\ncracking"), ('candid', "candid\nfungal mat"),
             ('dripcrust', "molten\ndrip-crust")]

def env_and_cam(cx, width, maxh, res=(1680, 760)):
    H.demo_env(bg=(0.006, 0.008, 0.010), strength=0.35)
    kl = bpy.data.lights.new("KEY", 'AREA'); kl.energy = 900 * max(6.0, width / 2.5); kl.size = width * 0.9
    kl.color = (1.0, 0.96, 0.88)
    ko = bpy.data.objects.new("KEY", kl); bpy.context.scene.collection.objects.link(ko)
    ko.location = (cx - width * 0.12, -14, maxh + 9)
    ko.rotation_euler = (Vector((cx, 0, maxh * 0.4)) - Vector(ko.location)).to_track_quat('-Z', 'Y').to_euler()
    sun = H.demo_sun((cx - 8, -22, 18), (cx, 0, maxh * 0.4), 1.8)
    sun.data.color = (1.0, 0.97, 0.90)
    fill = H.demo_sun((cx + 12, -16, 6), (cx, 0, maxh * 0.4), 0.4)
    fill.data.color = (0.72, 0.80, 0.88)
    try: fill.data.use_shadow = False
    except Exception: pass
    lens = 60.0
    half_w = width / 2 + 1.4
    half_h = maxh / 2 + 1.1
    sensor_w = 36.0; sensor_h = sensor_w * res[1] / res[0]
    D = max(half_w / (sensor_w / 2 / lens), half_h / (sensor_h / 2 / lens))
    H.demo_cam((cx, -D, maxh * 0.42), (cx, 0, maxh * 0.42), lens=lens)

def add_lights(specs):
    for (kind, loc, col, e, r) in specs:
        l = bpy.data.lights.new("P", kind); l.energy = e; l.color = col; l.shadow_soft_size = r
        lo = bpy.data.objects.new("P", l); bpy.context.scene.collection.objects.link(lo)
        lo.location = loc

def render(path, res=(1680, 760)):
    sc = bpy.context.scene
    try: sc.eevee.use_raytracing = True
    except Exception: pass
    for look in ('AgX - High Contrast', 'High Contrast'):
        try:
            sc.view_settings.look = look; break
        except Exception: pass
    try: sc.view_settings.exposure = 0.2
    except Exception: pass
    H.demo_render(path, w=res[0], h=res[1])

SHEET_MAXH = {'windows': 4.4, 'doors': 4.3, 'crowns': 4.6, 'projections': 5.2,
              'columns': 6.2, 'signage': 4.6, 'signforms': 3.9}

def run_sheet(name, entries):
    H.wipe()
    M = K.build_mats()
    objs = []; lights = []
    x = 0.0
    for (label, fn, slot, lift) in entries:
        x += slot / 2
        if fn in K.WALL_PARTS:
            fn(M, objs, lights, (x, 0, lift), (0, -1, 0))
        else:
            fn(M, objs, lights, (x, 0, 0))
        K.add_text(objs, label, 0.17, M['cream'], (x, 0, -0.75), spacing=1.25)
        x += slot / 2
    width = x
    add_lights(lights)
    env_and_cam(width / 2, width, SHEET_MAXH.get(name, 5.6))
    render(OUT + "\\kitsheet_%s.png" % name)
    print("SHEET %s objects=%d" % (name, len(bpy.data.objects)))

def swatch(M, objs, matkey, loc):
    L = Vector(loc)
    bm = bmesh.new()
    K.bx(bm, 0, 0, 0.0, 1.15, 0.1, 1.55)
    K.bx(bm, 0, -0.01, 0.80, 1.24, 0.1, 0.08)
    K.bx(bm, 0, -0.01, -0.80, 1.24, 0.1, 0.08)
    K.bx(bm, -0.60, -0.01, 0, 0.08, 0.1, 1.68)
    K.bx(bm, 0.60, -0.01, 0, 0.08, 0.1, 1.68)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_swatch_frame", M['ferric']))
    if matkey in ('grate', 'voronoi'):
        bm = bmesh.new(); K.bx(bm, 0, -0.02, 0, 1.02, 0.02, 1.42)
        for vv in bm.verts: vv.co += L
        objs.append(H.finish(bm, "KIT_swatch_back", M['dark']))
    bm = bmesh.new(); K.bx(bm, 0, -0.06, 0, 1.02, 0.02, 1.42)
    for vv in bm.verts: vv.co += L
    objs.append(H.finish(bm, "KIT_swatch_face", M[matkey]))

def run_materials_sheet():
    H.wipe()
    M = K.build_mats()
    objs = []
    slot = 1.55
    for i, (key, label) in enumerate(MATERIALS_ROW):
        x = i * slot
        swatch(M, objs, key, (x, 0, 3.1))
        K.add_text(objs, label, 0.13, M['cream'], (x, 0, 2.05), spacing=1.2)
    for i, (key, label) in enumerate(DECAY_ROW):
        x = (i + 1.5) * slot
        swatch(M, objs, key, (x, 0, 0.85))
        K.add_text(objs, label, 0.13, M['cream'], (x, 0, -0.2), spacing=1.2)
    width = len(MATERIALS_ROW) * slot
    env_and_cam(width / 2 - slot / 2, width, 4.9, res=(1680, 900))
    render(OUT + "\\kitsheet_materials.png", res=(1680, 900))
    print("SHEET materials objects=%d" % len(bpy.data.objects))

if __name__ == "__main__" or True:
    for nm, entries in SHEETS.items():
        run_sheet(nm, entries)
    run_materials_sheet()
    print("ALL KIT SHEETS DONE")
