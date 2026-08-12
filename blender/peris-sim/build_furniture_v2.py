# Peris sim furniture v2 — clean single-mesh objects + hand-paintable textures.
#
# The area script for Peris's room, built on the shared pipeline in
# blender/paintlib/ (see blender/skills/paintable-exports/SKILL.md). It keeps
# only what is Peris-specific: the piece builders, the Monos feed room, the
# j-store recolours, and the export layout. Everything reusable — the Builder
# mesh kit, per-face UV islands, the couch/bench paint grammar, per-object
# materials, GLTF + BlockBench OBJ exports — lives in paintlib.
#
# Run:  blender.exe -b --python build_furniture_v2.py
# Outputs (game-ready, committed):
#   to-rust-as-we-fall/resources/models/peris-sim/peris-furniture.gltf (+bins/textures)
#   to-rust-as-we-fall/resources/models/peris-sim/props/plant_displays/*.gltf
#   to-rust-as-we-fall/resources/models/peris-sim/portal_room/monos-room.gltf
#   props/watering_can + props/logbook_console OBJ+PNG (prop-scene paths)
# Source (gitignored):
#   blender/peris-sim/obj-exports/   one OBJ+MTL+texture per piece (BlockBench)
#   blender/peris-sim/painted/       drop hand-painted <Name>_tex.png here — it
#                                    wins over the generated starter on rebuild
#   blender/peris-sim/furniture_v2.blend

import bpy
import math
import os
import shutil
import sys
import numpy as np
from mathutils import Vector, Matrix

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "blender"))
import paintlib as pl
from paintlib import Builder, DETAIL_SCREEN, DETAIL_RUG, DETAIL_ART, \
    DETAIL_SPINES, DETAIL_SHELF_BACK, DETAIL_PHOTO, DETAIL_MONO_WALL, DETAIL_DOOR

RES = os.path.join(ROOT, "to-rust-as-we-fall", "resources", "models", "peris-sim")
SRC = os.path.join(ROOT, "blender", "peris-sim")
OBJX = os.path.join(SRC, "obj-exports")
PAINTED = os.path.join(SRC, "painted")
os.makedirs(os.path.join(RES, "props", "plant_displays"), exist_ok=True)
os.makedirs(os.path.join(RES, "portal_room"), exist_ok=True)
os.makedirs(OBJX, exist_ok=True)
os.makedirs(PAINTED, exist_ok=True)


# ------------------------------------------------------------- the pieces ----
def build_armchair():
    b = Builder()
    lh = 0.12                      # leg height / seat base
    b.box((0, 0, lh + 0.17), (0.94, 0.80, 0.34), "chair_pink", skip=("bottom",))     # seat base
    b.box((0, 0.31, 0.12 + 0.515), (0.94, 0.18, 1.03), "chair_pink")                 # back
    for sx in (-1, 1):
        b.box((sx * 0.435, -0.04, lh + 0.25), (0.145, 0.72, 0.50), "chair_pink")     # arms
    b.box((0, -0.06, lh + 0.39), (0.62, 0.58, 0.10), "cushion")                      # seat cushion
    b.box((0, 0.245, lh + 0.62), (0.60, 0.12, 0.42), "cushion")                      # back cushion
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((sx * 0.40, sy * 0.33, lh / 2), (0.08, 0.08, lh), "wood", skip=("top",))
    return b.finish("Armchair")


def build_coffee_table():
    b = Builder()
    b.box((0, 0, 0.43), (1.00, 0.60, 0.06), "wood_light")                            # top
    b.box((0, 0, 0.37), (0.86, 0.46, 0.06), "wood", skip=("top",))                   # apron
    # legs run all the way to the tabletop underside — they sit outboard of the
    # inset apron, so stopping at the apron leaves a visible gap under the top
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((sx * 0.44, sy * 0.24, 0.20), (0.07, 0.07, 0.40), "wood", skip=("top",))
    return b.finish("CoffeeTable")


def build_bookshelf():
    # Low and deep: shoulder height beside the couch (2m-tall pieces), not a tower.
    b = Builder()
    w, d, h, t = 1.20, 0.50, 1.60, 0.045
    b.box((0, d * 0.5 - 0.015, h / 2), (w - 2 * t, 0.03, h - 2 * t), "wood_light",
          detail=DETAIL_SHELF_BACK)                                                  # back panel
    for sx in (-1, 1):
        b.box((sx * (w / 2 - t / 2), 0, h / 2), (t, d, h), "wood")                   # sides
    b.box((0, 0, h - t / 2), (w - 2 * t, d, t), "wood")                              # top
    b.box((0, 0, 0.21), (w - 2 * t, d, 0.42), "wood_light", detail=DETAIL_DOOR)      # base cabinet
    for z in (0.72, 1.15):
        b.box((0, 0, z), (w - 2 * t, d - 0.05, t), "wood")                           # shelves
    return b.finish("Bookshelf")


def build_kiosk():
    b = Builder()
    b.box((0, 0, 0.45), (0.70, 0.55, 0.90), "kiosk_body")                            # base cabinet
    b.box((0, 0.05, 1.02), (0.62, 0.40, 0.24), "kiosk_body")                         # console head
    b.box((0, -0.16, 1.24), (0.58, 0.10, 0.40), "dark")                              # screen slab
    b.box((0, -0.215, 1.24), (0.48, 0.012, 0.30), "screen", skip=("top", "bottom", "+x", "-x", "+y"),
          detail=DETAIL_SCREEN)                                                      # screen face
    b.box((0, -0.33, 0.92), (0.56, 0.16, 0.05), "wood_light")                        # tray
    return b.finish("Kiosk")


def build_portal():
    """Portal group: Portal (empty) > Portal_Frame / Portal_AccentRing /
    Portal_Surface / Portal_Node0..2. Local origin = portal centre; the ring lies
    in the XZ plane facing Blender -Y (Godot +Z). Dimensions match the original
    export (frame r 1.50, surface r 1.14) so the wall placement carries over."""
    group = bpy.data.objects.new("Portal", None)
    bpy.context.collection.objects.link(group)

    b = Builder()
    b.annulus((0, 0, 0), 1.50, 1.17, 0.23, "portal_frame", front=-0.115)
    frame = b.finish("Portal_Frame")

    b = Builder()
    b.annulus((0, 0, 0), 1.17, 1.02, 0.07, "portal_ring", front=-0.09)
    accent = b.finish("Portal_AccentRing")

    b = Builder()
    b.disc((0, -0.02, 0), 1.14, "portal_surface", flip=True)
    surface = b.finish("Portal_Surface")

    nodes = []
    for i, ang in enumerate((90, 210, 330)):
        a = math.radians(ang)
        b = Builder()
        b.box((1.335 * math.cos(a), 0.0, 1.335 * math.sin(a)), (0.20, 0.26, 0.20), "portal_node")
        nodes.append(b.finish("Portal_Node%d" % i))

    for ob in [frame, accent, surface] + nodes:
        ob.parent = group
    return group


def build_rug():
    b = Builder()
    b.box((0, 0, 0.011), (2.60, 1.70, 0.022), "rug_field", skip=("bottom",), detail=DETAIL_RUG)
    return b.finish("Rug")


def build_wall_art_frame():
    b = Builder()
    w, h, t = 2.00, 1.30, 0.07
    # frame: four bars around the canvas, open centre
    b.box((0, 0, h / 2 - t / 2), (w, 0.06, t), "art_frame")
    b.box((0, 0, -h / 2 + t / 2), (w, 0.06, t), "art_frame")
    b.box((-w / 2 + t / 2, 0, 0), (t, 0.06, h - 2 * t), "art_frame")
    b.box((w / 2 - t / 2, 0, 0), (t, 0.06, h - 2 * t), "art_frame")
    return b.finish("WallArtFrame")


def build_wall_art():
    b = Builder()
    b.box((0, 0.012, 0), (1.90, 0.024, 1.20), "art_canvas",
          skip=("top", "bottom", "+x", "-x", "+y"), detail=DETAIL_ART)
    return b.finish("WallArt")


def build_book_stack():
    b = Builder()
    b.box((0, 0, 0.02), (0.20, 0.15, 0.04), "book_red", detail=DETAIL_SPINES)
    b.box((0.012, -0.01, 0.055), (0.18, 0.13, 0.03), "book_grn", detail=DETAIL_SPINES)
    b.box((-0.01, 0.008, 0.0875), (0.16, 0.12, 0.035), "book_must", detail=DETAIL_SPINES)
    return b.finish("BookStack")


def build_jar():
    b = Builder()
    b.ngon_prism((0, 0), 0.045, 0.05, 0.075, "ceramic", cap_top=False)
    b.ngon_prism((0, 0), 0.052, 0.052, 0.025, "wood", z0=0.075)
    return b.finish("Jar")


def build_photo():
    b = Builder()
    b.box((0, 0, 0.09), (0.22, 0.03, 0.18), "wood")
    b.box((0, -0.017, 0.095), (0.17, 0.006, 0.13), "photo_pic",
          skip=("top", "bottom", "+x", "-x", "+y"), detail=DETAIL_PHOTO)
    return b.finish("Photo")


def build_mug(name, part):
    b = Builder()
    b.ngon_prism((0, 0), 0.048, 0.042, 0.105, part, cap_top=False)
    b.ngon_prism((0, 0), 0.036, 0.036, 0.004, "dark", z0=0.02)                      # coffee
    b.box((0.062, 0, 0.058), (0.028, 0.02, 0.055), part)                            # handle
    return b.finish(name)


def build_cup_saucer():
    b = Builder()
    b.ngon_prism((0, 0), 0.075, 0.06, 0.018, "ceramic")
    b.ngon_prism((0, 0), 0.042, 0.034, 0.045, "ceramic", z0=0.018, cap_top=False)
    return b.finish("CupSaucer")


# Plush toys are BlockBench-style box animals: chunky tapered bodies, oversized
# heads, painted faces (eyes/nose on the -y face) and a lighter belly patch.
def _paint_plush_face(tile, mask, base, isl, px_per_m):
    if isl.get("name") != "-y":
        return
    h, w = tile.shape[:2]
    if w < 6 or h < 6:
        return
    dark = pl.shade(base, 0.4)
    ey = int(h * 0.62)
    tile[ey, max(1, int(w * 0.28))] = dark
    tile[ey, min(w - 2, int(w * 0.72))] = dark
    tile[int(h * 0.42), w // 2] = dark                       # nose
    if w >= 10:
        tile[int(h * 0.40), w // 2 - 1] = dark               # nose 2px on big faces


def _paint_plush_belly(tile, mask, base, isl, px_per_m):
    if isl.get("name") != "-y":
        return
    h, w = tile.shape[:2]
    if w < 8 or h < 8:
        return
    light = pl.shade(base, 1.18)
    tile[2:h - 3, w // 4:w - w // 4] = light


DET_PLUSH_FACE = pl.register_detail("plush_face", _paint_plush_face)
DET_PLUSH_BELLY = pl.register_detail("plush_belly", _paint_plush_belly)


def build_plush_cat():
    b = Builder()
    b.tapered_box((0, 0.01, 0), (0.13, 0.11), (0.17, 0.14), 0.14, "plush_peach",
                  z0=0.015, detail=DET_PLUSH_BELLY)                                  # body
    for sx in (-1, 1):
        b.box((sx * 0.075, 0.02, 0.055), (0.05, 0.09, 0.08), "plush_peach")          # haunches
        b.box((sx * 0.045, -0.055, 0.04), (0.04, 0.05, 0.08), "plush_peach")         # front paws
    b.box((0, -0.005, 0.21), (0.13, 0.11, 0.11), "plush_peach", detail=DET_PLUSH_FACE)  # head
    for sx in (-1, 1):
        b.tapered_box((sx * 0.042, -0.002, 0), (0.008, 0.02), (0.048, 0.028), 0.055,
                      "plush_peach", z0=0.263)                                       # pointy ears
    b.box((0.075, 0.085, 0.025), (0.035, 0.09, 0.035), "plush_peach")                # tail out
    b.box((0.075, 0.115, 0.075), (0.035, 0.03, 0.075), "plush_peach")                # tail curl up
    return b.finish("Plush_Cat")


def build_plush_bear():
    b = Builder()
    for sx in (-1, 1):
        b.box((sx * 0.05, -0.045, 0.032), (0.065, 0.075, 0.06), "plush_blue")        # feet
    b.tapered_box((0, 0, 0), (0.15, 0.12), (0.20, 0.16), 0.17, "plush_blue",
                  z0=0.02, detail=DET_PLUSH_BELLY)                                   # body
    for sx in (-1, 1):
        b.box((sx * 0.105, -0.01, 0.145), (0.05, 0.06, 0.10), "plush_blue")          # arms
    b.box((0, -0.002, 0.245), (0.15, 0.13, 0.12), "plush_blue", detail=DET_PLUSH_FACE)  # head
    b.box((0, -0.075, 0.225), (0.07, 0.03, 0.05), "cushion")                         # muzzle
    for sx in (-1, 1):
        b.box((sx * 0.058, 0.0, 0.315), (0.05, 0.03, 0.045), "plush_blue")           # ears
    return b.finish("Plush_Bear")


def build_plant_stand_tall():
    b = Builder()
    b.box((0, 0, 0.93), (0.40, 0.40, 0.04), "stand_wood")                           # top
    b.box((0, 0, 0.45), (0.32, 0.32, 0.035), "wood_light")                          # mid shelf (decor)
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((sx * 0.165, sy * 0.165, 0.455), (0.05, 0.05, 0.91), "stand_wood")
    return b.finish("PlantStandTall")


def build_plant_stand_short():
    b = Builder()
    b.box((0, 0, 0.26), (0.40, 0.40, 0.04), "stand_wood")
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((sx * 0.15, sy * 0.15, 0.12), (0.055, 0.055, 0.24), "stand_wood", skip=("top",))
    return b.finish("PlantStandShort")


def build_hanging_basket():
    """The support surface a hanging plant rests on — its own object so the scene's
    Plant%dTable node has a measurable top at the basket rim."""
    b = Builder()
    b.ngon_prism((0, 0), 0.175, 0.12, 0.13, "basket", cap_top=False)
    b.ngon_prism((0, 0), 0.13, 0.13, 0.012, "basket", z0=0.118)                     # inner shelf/rim
    return b.finish("HangingBasket")


def build_hanging_arm():
    """Wall bracket + arm + three cords, hung tip at local origin, pointing -Y off
    the wall (Godot +Z). The basket hangs DROP metres below the arm tip."""
    DROP = 0.62
    b = Builder()
    b.box((0, 0.36, DROP + 0.08), (0.12, 0.04, 0.34), "stand_wood")                  # wall plate
    b.box((0, 0.17, DROP + 0.185), (0.055, 0.42, 0.055), "stand_wood")               # arm out
    b.box((0, -0.02, DROP + 0.10), (0.04, 0.04, 0.14), "stand_wood")                 # hook drop
    for i, ang in enumerate((90, 210, 330)):
        a = math.radians(ang)
        x1, y1 = 0.13 * math.cos(a), -0.02 + 0.13 * math.sin(a)
        # thin cord from hook tip to basket rim spread
        v0 = Vector((0, -0.02, DROP + 0.03))
        v1 = Vector((x1, y1, 0.10))
        mid = (v0 + v1) / 2
        length = (v1 - v0).length
        d = (v1 - v0).normalized()
        cf = b.box((mid.x, mid.y, mid.z), (0.016, 0.016, length), "cord")
        # orient the cord box along the hang direction (each shared vert exactly once)
        rot = Vector((0, 0, 1)).rotation_difference(d).to_matrix().to_4x4()
        piv = Matrix.Translation(mid)
        xform = piv @ rot @ piv.inverted()
        for v in {v for f in cf for v in f.verts}:
            v.co = xform @ v.co
    return b.finish("HangingArm")


def build_floor_plinth():
    b = Builder()
    b.box((0, 0, 0.05), (0.52, 0.52, 0.10), "stand_wood")
    b.box((0, 0, 0.115), (0.44, 0.44, 0.03), "wood_light")
    return b.finish("FloorPlinth")


def build_shelf_tray():
    b = Builder()
    b.box((0, 0, 0.015), (0.30, 0.24, 0.03), "wood_light")
    return b.finish("ShelfTray")


def build_watering_can():
    """Stylized garden can matching the atlas grammar; ships as its own small OBJ+PNG
    prop (scenes/props/peris/watering_can.tscn keeps its paths)."""
    b = Builder()
    b.ngon_prism((0, 0), 0.105, 0.13, 0.22, "mug_teal", cap_top=False)               # body
    b.ngon_prism((0, 0), 0.055, 0.055, 0.012, "wood_light", z0=0.21)                 # rim ring
    # spout: tapered prism leaning out of the body
    spout = b.box((0.17, 0, 0.17), (0.16, 0.045, 0.045), "mug_teal")
    rot = Matrix.Rotation(math.radians(-35.0), 4, "Y")
    piv = Matrix.Translation(Vector((0.17, 0, 0.17)))
    xform = piv @ rot @ piv.inverted()
    for v in {v for f in spout for v in f.verts}:
        v.co = xform @ v.co
    b.box((0.235, 0, 0.245), (0.05, 0.06, 0.02), "wood_light")                       # rosette head
    b.box((-0.10, 0, 0.26), (0.14, 0.035, 0.035), "cushion")                         # top handle bar
    b.box((-0.16, 0, 0.19), (0.035, 0.035, 0.12), "cushion")                         # handle drop
    return b.finish("WateringCan")


def build_logbook_console():
    """The care logbook reading console: pedestal + wood desk top + an angled
    display rising at the back. Origin sits MID-HEIGHT (floor at local -0.5) so
    the scene's existing (y=0.5) placement and the kit-return contract (anchor +
    0.55 = the desk top) keep working untouched. The display face is a separate
    object because the prop scene drives its emission itself."""
    b = Builder()
    b.box((0, 0, 0.0), (0.55, 0.40, 1.0), "dark")                        # pedestal (floor -0.5..0.5)
    b.box((0, 0, 0.525), (0.62, 0.50, 0.05), "wood_light")               # desk top (top at 0.55)
    b.box((0.02, 0, -0.47), (0.66, 0.54, 0.06), "dark")                  # base skid
    housing_screen = b.box((0.10, 0, 0.78), (0.08, 0.46, 0.42), "dark")  # display housing
    rot = Matrix.Rotation(math.radians(-18.0), 4, "Y")
    piv = Matrix.Translation(Vector((0.10, 0, 0.60)))
    xform = piv @ rot @ piv.inverted()
    for v in {v for f in housing_screen for v in f.verts}:
        v.co = xform @ v.co
    housing = b.finish("LogbookHousing")

    b = Builder()
    face = b.box((0.055, 0, 0.78), (0.012, 0.38, 0.32), "screen",
                 skip=("top", "bottom", "+y", "-y", "+x"), detail=DETAIL_SCREEN)
    for v in {v for f in face for v in f.verts}:
        v.co = xform @ v.co
    display = b.finish("LogbookDisplay")
    return housing, display


# --------------------------------------------------------------- monos room ----
def build_monos_room():
    """The feed office beyond the portal: institutional counterpart to Peris's warm
    room. Open front at y=0 (the portal plane); interior extends +Y (Godot -Z)."""
    W, D, H, T = 7.0, 5.6, 3.6, 0.12
    b = Builder()
    b.box((0, D / 2, -T / 2), (W, D, T), "mono_floor")                               # floor
    b.box((0, D - T / 2, H / 2), (W, T, H), "mono_wall", detail=DETAIL_MONO_WALL)    # back wall
    for sx in (-1, 1):
        b.box((sx * (W / 2 - T / 2), D / 2, H / 2), (T, D, H), "mono_wall_lo")       # side walls
    b.box((0, D / 2, H + T / 2), (W, D, T), "mono_trim")                             # ceiling
    b.box((0, D - T - 0.02, 0.45), (W - 2 * T, 0.04, 0.90), "mono_trim",
          skip=("top", "bottom", "+x", "-x", "+y"))                                  # wainscot band
    b.box((0, D / 2, H - 0.10), (2.6, 0.5, 0.06), "mono_light")                      # light slab
    shell = b.finish("MonosRoomShell")

    b = Builder()
    b.annulus((0, 0, 0), 1.50, 1.17, 0.18, "portal_frame", front=0.0)
    b.annulus((0, 0, 0), 1.17, 1.02, 0.06, "portal_ring", front=0.0)
    b.disc((0, 0.05, 0), 1.14, "portal_surface", flip=False)
    his_portal = b.finish("MonosPortal")
    his_portal.location = (0.0, D - T - 0.05, 2.1)

    console = build_kiosk()
    console.name = "MonosConsole"
    console.location = (1.9, D - 1.1, 0)
    console.rotation_euler = (0, 0, math.radians(200))

    shelf = build_bookshelf()
    shelf.name = "MonosShelf"
    shelf.location = (-W / 2 + 0.55, D - 0.75, 0)
    shelf.rotation_euler = (0, 0, math.radians(90))

    return [shell, his_portal, console, shelf]


# ------------------------------------------------------------------ j-stores ----
def build_jstores():
    """Aster's j-store data devices, recoloured for Peris's shelf: same mesh + UVs,
    hue-replaced texture copies (pink and purple)."""
    aster_dir = os.path.join(ROOT, "to-rust-as-we-fall", "resources", "models",
                             "aster-sim", "room")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(aster_dir, "j-store.gltf"))
    imported = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    assert imported, "j-store import produced no mesh"
    src = imported[0]
    src.parent = None
    src.matrix_world = Matrix.Identity(4)

    def tinted_material(tag, hue, sat_scale=1.0):
        alb = bpy.data.images.load(os.path.join(aster_dir, "aster-sim-room-hi-res_8.png"))
        emi = bpy.data.images.load(os.path.join(aster_dir, "aster-sim-room-hi-res_8_emissive.png"))
        out = {}
        for img, kind in ((alb, "albedo"), (emi, "emissive")):
            w, hgt = img.size
            px = np.array(img.pixels[:], dtype=np.float32).reshape(hgt, w, 4)
            px = pl.hue_replace(px, hue, sat_scale=sat_scale)
            copy = bpy.data.images.new("jstore_%s_%s" % (tag, kind), w, hgt, alpha=True)
            copy.pixels[:] = px.ravel()
            # source-side save only — the gltf exporter writes the runtime copy
            # beside peris-furniture.gltf itself
            copy.filepath_raw = os.path.join(SRC, "renders", "jstore_%s_%s.png" % (tag, kind))
            copy.file_format = "PNG"
            copy.save()
            out[kind] = copy
        return pl.make_atlas_material("JStore_%s" % tag, out["albedo"], out["emissive"], 1.0)

    variants = []
    for tag, hue, sat_scale in (("Pink", 0.91, 1.6), ("Purple", 0.76, 1.0)):
        ob = src.copy()
        ob.data = src.data.copy()
        ob.name = "JStore_%s" % tag
        ob.data.materials.clear()
        ob.data.materials.append(tinted_material(tag.lower(), hue, sat_scale))
        bpy.context.collection.objects.link(ob)
        variants.append(ob)
    bpy.data.objects.remove(src, do_unlink=True)
    return variants


# ------------------------------------------------------------------- main ----
def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(os.path.join(SRC, "renders"), exist_ok=True)

    furniture = [
        build_armchair(), build_coffee_table(), build_bookshelf(), build_kiosk(),
        build_portal(), build_rug(), build_wall_art_frame(), build_wall_art(),
        build_book_stack(), build_jar(), build_photo(),
        build_mug("Mug_Teal", "mug_teal"), build_mug("Mug_Cream", "cushion"),
        build_cup_saucer(), build_plush_cat(), build_plush_bear(),
    ]
    displays = [
        build_plant_stand_tall(), build_plant_stand_short(),
        build_hanging_basket(), build_hanging_arm(),
        build_floor_plinth(), build_shelf_tray(),
    ]
    monos = build_monos_room()
    jstores = build_jstores()
    can = build_watering_can()
    logbook_housing, logbook_display = build_logbook_console()

    # every object gets its OWN paintable texture; a hand-painted file in
    # painted/ wins over the generated starter. Tiny detail-carrying props get
    # double density so painted faces/details have pixels to land on.
    px_overrides = {"Plush_Cat": 64.0, "Plush_Bear": 64.0, "Photo": 64.0,
                    "Mug_Teal": 64.0, "Mug_Cream": 64.0, "CupSaucer": 64.0,
                    "Jar": 64.0, "WateringCan": 64.0}
    furn_meshes = pl.all_mesh_children(furniture) + displays
    sizes = {}
    for ob in furn_meshes + [can, logbook_housing, logbook_display]:
        sizes[ob.name] = pl.texture_object(
            ob, OBJX, px_per_m=px_overrides.get(ob.name, 32.0), painted_dir=PAINTED)
    for ob in pl.all_mesh_children(monos):
        sizes[ob.name] = pl.texture_object(ob, OBJX, px_per_m=16.0, painted_dir=PAINTED)

    # sanity: every UV inside [0,1]
    for ob in furn_meshes + pl.all_mesh_children(monos):
        uvs = ob.data.uv_layers.active.data
        for uv in uvs:
            assert -0.001 <= uv.uv[0] <= 1.001 and -0.001 <= uv.uv[1] <= 1.001, ob.name
    print("[BUILD] textured objects: %s" % {k: v for k, v in sorted(sizes.items())})

    pl.export_gltf(furniture + jstores, os.path.join(RES, "peris-furniture.gltf"))
    disp_dir = os.path.join(RES, "props", "plant_displays")
    for ob in displays:
        pl.export_gltf([ob], os.path.join(disp_dir, ob.name.lower() + ".gltf"))
    pl.export_gltf(monos, os.path.join(RES, "portal_room", "monos-room.gltf"))

    # BlockBench hand-off: every piece as its own OBJ + MTL + texture copy.
    for root in furniture + jstores + displays + [can, logbook_housing, logbook_display]:
        pl.export_obj([root], os.path.join(OBJX, root.name + ".obj"))
    pl.export_obj(monos, os.path.join(OBJX, "MonosRoom.obj"))

    # Prop scenes keep their established runtime paths (mesh OBJ + PNG, the scene
    # supplies the material): watering can + the logbook console.
    can_dir = os.path.join(RES, "props", "watering_can")
    shutil.copyfile(os.path.join(OBJX, "WateringCan_tex.png"),
                    os.path.join(can_dir, "watering_can.png"))
    pl.export_obj([can], os.path.join(can_dir, "watering_can.obj"), with_materials=False)
    log_dir = os.path.join(RES, "props", "logbook_console")
    shutil.copyfile(os.path.join(OBJX, "LogbookHousing_tex.png"),
                    os.path.join(log_dir, "logbook_console_housing.png"))
    shutil.copyfile(os.path.join(OBJX, "LogbookDisplay_tex.png"),
                    os.path.join(log_dir, "logbook_console_display.png"))
    pl.export_obj([logbook_housing], os.path.join(log_dir, "logbook_console_housing.obj"),
                  with_materials=False)
    pl.export_obj([logbook_display], os.path.join(log_dir, "logbook_console_display.obj"),
                  with_materials=False)

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "furniture_v2.blend"))
    print("[BUILD] done")


main()
