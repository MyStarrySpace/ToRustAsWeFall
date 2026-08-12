# paintlib — the project's paintable-asset pipeline, shared by every area build
# script (peris-sim furniture, endo junction, elevator/bridge, building elements,
# enemies, flora...). One import gives an area script the whole flow:
#
#   Builder            faceted clean-topology meshes with per-face part/detail tags
#   texture_object     per-object hand-paintable texture (per-face UV islands,
#                      couch/bench edge-highlight paint, emissive only where a part
#                      glows, painted/ overrides win over generated starters)
#   export_gltf        game-ready GLTF into to-rust-as-we-fall/resources/models/
#   export_obj         one OBJ + MTL + texture per piece — the BlockBench hand-off
#
# See blender/skills/paintable-exports/SKILL.md for the conventions and the
# worked example (blender/peris-sim/build_furniture_v2.py).

from .palette import (
    PARTS, PART_IDS, ID_PARTS, EMIT_STRENGTH,
    DETAIL_NONE, DETAIL_SCREEN, DETAIL_RUG, DETAIL_ART, DETAIL_SPINES,
    DETAIL_SHELF_BACK, DETAIL_PHOTO, DETAIL_MONO_WALL, DETAIL_DOOR,
    register_parts, register_detail, register_card_art, CARD_PAINTERS,
)
from .builder import Builder
from .atlas import (
    unwrap_and_pack, paint_atlas, texture_object, make_atlas_material,
    hue_replace, shade,
)
from .export import all_mesh_children, export_gltf, export_obj
