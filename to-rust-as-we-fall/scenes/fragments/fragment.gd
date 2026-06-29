class_name Fragment
extends Resource

## A FRAGMENT as DATA: the declarative description of a gameplay chunk — its map (floor/walls/lights/labels), the
## party spawn points, and the list of spawnable gameplay OBJECTS with the parameters each needs. A loader
## (DataFragmentChunk) reads this and COMPOSES the scene from the shared modular classes (Flure / PortalPad /
## Capbage / Channel / FloraLight / Enemy), so a fragment is pure data + reusable objects rather than bespoke
## per-chunk build code. This is the unit a level builder produces and the loader consumes.
##
## Save instances as `.tres` (the data) under `data/fragments/`. Author the `objects` list with one dictionary per
## spawnable; each dictionary's `type` selects the class, the rest are that class's configure() parameters (see
## DataFragmentChunk._spawn_object for the per-type contract). Vector3/Color values are stored natively in the
## .tres, so the data round-trips through the inspector and a future level-builder UI.

@export var id: String = ""
@export var title: String = ""
@export var help: String = ""
@export var default_character: String = ""
@export var party_ids: PackedStringArray = PackedStringArray()

## char_id -> spawn Vector3 (where the host places each party member). Stored as a Dictionary so the .tres keeps it.
@export var spawns: Dictionary = {}

# --- Map / environment (each entry a Dictionary; see the keys below) ---
@export var floors: Array[Dictionary] = []   # {pos:Vector3, size:Vector3, color:Color}  (adds collision for nav/ray)
@export var walls: Array[Dictionary] = []    # {pos:Vector3, size:Vector3, color:Color, emission?:Color, energy?:float}
@export var lights: Array[Dictionary] = []   # {pos:Vector3, color:Color, energy:float, range:float}
@export var labels: Array[Dictionary] = []   # {text:String, pos:Vector3, color?:Color}

## The spawnable gameplay objects. Each entry: {type:String, ...params}. Supported types + their params live in
## DataFragmentChunk._spawn_object — flure / portal_pad / capbage / channel / flora_light / enemy / marker.
@export var objects: Array[Dictionary] = []

## Optional grid data (the GridWorld contract dict) — omit for a gridless fragment.
@export var grid: Dictionary = {}

## Optional LEVEL MESH: a modeled environment (a .glb/.gltf/.tscn) the chunk plays inside — the DataFragmentChunk
## returns it from get_environment_model(), and the preview host loads it, applies deck collision + the occlusion
## wrap, and (for a warped scene) installs the coord map. Empty = a procedural/graybox-only fragment.
@export var environment_model: String = ""

## Optional placed model instances: each {path:String (a .glb/.tscn/.obj), pos:Vector3, rot:Vector3 (deg), scale:Vector3}.
## For static modeled props a level builder drops in alongside the procedural geometry. The loader instances each.
@export var meshes: Array[Dictionary] = []

## Optional preview metadata (day/time/routing/note) the host reads for get_preview_time_state().
@export var time_state: Dictionary = {}

## Fragment-specific LOGIC knobs a thin behavior subclass reads (win thresholds, hazard targets, named anchors —
## anything the unique mechanics need that isn't a spawnable). Pure data so the .tres stays the full source of
## truth; the subclass holds only behavior. E.g. the wash-intro stores exit_pos/exit_radius/wash_back_pos here.
@export var params: Dictionary = {}
