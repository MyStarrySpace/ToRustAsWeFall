# The house palette and the face-tag registries. Area scripts extend both:
#
#   import paintlib as pl
#   pl.register_parts({"pipe_rust": {"rgb": (0.30, 0.16, 0.09)}})
#   MY_DETAIL = pl.register_detail("valve_dial", my_painter_fn)
#
# A part: {"rgb": base color, optional "emit": glow color}. A part with "emit"
# is the ONLY thing that gives its object an emissive texture/material layer —
# plain props never carry a phantom emission channel.

# Base colors follow the hand-painted couch/bench set (measured from the
# artist's own textures).
PARTS = {
    "chair_pink":  {"rgb": (0.86, 0.56, 0.55)},
    "cushion":     {"rgb": (0.93, 0.88, 0.78)},
    "wood":        {"rgb": (0.60, 0.42, 0.25)},
    "wood_light":  {"rgb": (0.80, 0.62, 0.40)},
    "ceramic":     {"rgb": (0.90, 0.90, 0.88)},
    "mug_teal":    {"rgb": (0.30, 0.62, 0.60)},
    "book_red":    {"rgb": (0.72, 0.34, 0.30)},
    "book_grn":    {"rgb": (0.42, 0.55, 0.38)},
    "book_must":   {"rgb": (0.80, 0.66, 0.34)},
    "plush_peach": {"rgb": (0.90, 0.66, 0.55)},
    "plush_blue":  {"rgb": (0.55, 0.70, 0.82)},
    "kiosk_body":  {"rgb": (0.72, 0.68, 0.82)},
    "dark":        {"rgb": (0.18, 0.18, 0.20)},
    "screen":      {"rgb": (0.10, 0.16, 0.12), "emit": (0.36, 0.91, 0.50)},  # terminal green
    "portal_frame": {"rgb": (0.18, 0.19, 0.22)},
    "portal_node": {"rgb": (0.75, 0.78, 0.80)},
    "portal_ring": {"rgb": (0.30, 0.55, 0.58), "emit": (0.45, 0.95, 0.98)},
    "portal_surface": {"rgb": (0.06, 0.08, 0.10)},
    "rug_field":   {"rgb": (0.85, 0.77, 0.63)},
    "rug_border":  {"rgb": (0.72, 0.42, 0.33)},
    "art_frame":   {"rgb": (0.55, 0.38, 0.22)},
    "art_canvas":  {"rgb": (0.84, 0.79, 0.68)},
    "photo_pic":   {"rgb": (0.78, 0.72, 0.62)},
    "stand_wood":  {"rgb": (0.66, 0.48, 0.30)},
    "basket":      {"rgb": (0.78, 0.55, 0.40)},
    "cord":        {"rgb": (0.42, 0.36, 0.28)},
    # institutional interiors (the Monos feed room and kin)
    "mono_wall":   {"rgb": (0.42, 0.47, 0.48)},
    "mono_wall_lo": {"rgb": (0.33, 0.38, 0.40)},
    "mono_floor":  {"rgb": (0.22, 0.24, 0.26)},
    "mono_trim":   {"rgb": (0.16, 0.18, 0.20)},
    "mono_light":  {"rgb": (0.80, 0.84, 0.78), "emit": (0.75, 0.82, 0.72)},
}

PART_IDS = {name: i for i, name in enumerate(PARTS)}
ID_PARTS = {i: name for name, i in PART_IDS.items()}

# Per-part glow intensity for parts that carry "emit"; anything unlisted glows at 1.0.
EMIT_STRENGTH = {"screen": 2.0, "portal_ring": 1.6, "mono_light": 1.6}


# Optional paint FAMILY per part: the baseline face grammar (grain streaks, panel
# seams, speckle) keys on hardcoded name sets from the couch/bench era — a family
# lets an area part opt into those baselines by declaration instead of by name:
#   pl.register_parts({"crate_wood": {"rgb": ..., "family": "wood"}})
# Families: "wood" | "fabric" | "panel" | "speckled".
PART_FAMILY = {}


def register_parts(parts, emit_strength=None):
    """Add area-specific parts (call BEFORE building). Existing names are updated."""
    for name, spec in parts.items():
        if name not in PART_IDS:
            new_id = len(PART_IDS)
            PART_IDS[name] = new_id
            ID_PARTS[new_id] = name
        fam = spec.get("family")
        if fam:
            PART_FAMILY[name] = fam
        else:
            PART_FAMILY.pop(name, None)   # re-registering without a family clears it
        PARTS[name] = spec
    if emit_strength:
        EMIT_STRENGTH.update(emit_strength)


# Detail tags select a painter for a face beyond the flat fill + edge border.
# Built-in painters live in atlas.py; area scripts add their own:
#   MY_DETAIL = register_detail("hazard_stripes", paint_fn)
# where paint_fn(tile, mask, base, isl, px_per_m) writes into the (h, w, 3) tile.
DETAIL_NONE, DETAIL_SCREEN, DETAIL_RUG, DETAIL_ART, DETAIL_SPINES, \
    DETAIL_SHELF_BACK, DETAIL_PHOTO, DETAIL_MONO_WALL, DETAIL_DOOR = range(9)

DETAIL_PAINTERS = {}   # detail id -> paint fn; atlas.py registers the built-ins
_next_detail = 9


def register_detail(name, paint_fn):
    global _next_detail
    detail_id = _next_detail
    _next_detail += 1
    DETAIL_PAINTERS[detail_id] = paint_fn
    return detail_id


# CARD ART — painters for `Builder.card` pieces, where the TEXTURE is the form:
# a grate drawn as pixel art on one plane, a leaf, a fern frond. Unlike a detail
# painter (which decorates a solid face) a card painter owns RGBA, because the
# transparent texels ARE the silhouette. Separate registry so the two can never
# be confused: a detail painter that wrote alpha would punch holes in solid props.
# Signature: fn(tile_rgba, isl, px_per_m) -> writes into the (h, w, 4) tile.
CARD_PAINTERS = {}
_next_card_art = 1


def register_card_art(name, paint_fn):
    global _next_card_art
    art_id = _next_card_art
    _next_card_art += 1
    CARD_PAINTERS[art_id] = paint_fn
    return art_id
