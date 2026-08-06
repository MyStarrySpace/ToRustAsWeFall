extends "res://scripts/scene_chunks/scene_chunk.gd"

const LatheBuilderScript := preload("res://scripts/generation/lathe_builder.gd")
const SdfMesherScript := preload("res://scripts/generation/sdf_mesher.gd")
const InfrastructureBuilderScript := preload("res://scripts/generation/infrastructure_structure_builder.gd")
const FixedCadenceScript := preload("res://scripts/system/core/fixed_cadence.gd")
const RisingWaterCrossingScript := preload("res://scripts/game/objects/basin_water.gd")
const RisingWaterCrossingSpecScript := preload(
	"res://scripts/game/objects/rising_water_crossing_spec.gd")
const GRIME_SHADER := preload("res://resources/tile_grime.gdshader")
const WEAK_WALL_COLLAPSE_PIECE_SCENE := preload(
	"res://scenes/game/weak_wall_collapse_piece.tscn")
const DATA_FRAGMENT_AUTHORITY_VERSION := 4
const DATA_FRAGMENT_AUTHORITY_PREFIX := "chunk:data_fragment:"
const WEAK_WALL_CRUMBLE_DURATION := 0.9
const WEAK_WALL_POSITION_TOLERANCE := 0.25
const WEAK_WALL_HEIGHT_TOLERANCE := 1.25
const CONCEALMENT_TICK := 0.1
const CONCEALMENT_BOUNDARY_EPSILON := 0.0001
const EXIT_REST_PHASES := ["ready", "committing", "rested"]
const EXIT_SHELTER_NAVIGATION_REGION_CONTRACT := "exit_shelter_interaction_region/v1"
const RALLY_FORMATION_REGION_CONTRACT := "rally_formation_region/v1"

## The DATA-DRIVEN fragment loader. Point it at a `Fragment` resource (the data) and it COMPOSES the scene from
## the shared modular classes — no bespoke build code per fragment. It reads the fragment's map (floors/walls/
## lights/labels), spawns each object in `fragment.objects` via the right class (Flure / PortalPad / Capbage /
## Channel / FloraLight / Enemy / marker), and exposes the fragment's title/help/spawns/grid through the normal
## SceneChunk interface, so a DATA fragment loads through the exact same preview/elevator/act1 path as a coded one.
##
## Assign the fragment two ways: set `fragment` directly (tests), or `configure_chunk({"fragment_path": "res://..."})`
## (the preview registry / a level builder). The per-type object contract is documented on each branch of
## _spawn_object below — that branch list IS the authoring reference for a Fragment `.tres`.

const EnemyScript := preload("res://scripts/game/ai/enemy.gd")

var fragment: Fragment
var fragment_path := ""

# Spawned, kept for queries + reset (the loader owns nothing bespoke — just references to the modular objects).
var _flures: Array = []
var _portals: Array = []
var _capbages: Array = []
var _channels: Array = []
var _flora: Array = []
var _enemies: Array = []
var _scarpets: Array = []
var _candid_zones: Array = []
var _exit_shelters: Array = []
var _enemy_posts := {}        # char_id -> spawn post (re_post targets on a wipe restart)
var _scheduled := false
var _phase := "ready"
var _spotted_count := 0
var _wipe_count := 0
var _decoratives: Array = []  # DecorativeFlora — ornamental invasives (docs/DECORATIVE_FLORA.md)
var _spread_patches: Array = []  # the Verdanta patches runbacks grew (freed on host reset)
var _spike_strips: Array = []    # SpikeStrip hostile architecture (the shared DoT tick reads them)
var _infrastructure_operations: Array = [] # typed source -> receiver -> environmental consequence beats
var _infrastructure_fields: Array = []     # shared hazard/concealment polling, like Candids/SpikeStrips
var _hushblooms: Array = []      # Hushbloom stun flora (thigmonastic; pickable for the carried throw)
var _basins: Array = []          # RisingWaterCrossing instances; legacy query name kept for callers.
var _assists: Array = []         # CrossingAssist consoles (the priced perfect-launch read)
var _fall_pos := Vector3.ZERO    # where the party last wiped (the runback decor pass grows here)
var _candid_epoch := -1.0        # first absolute tick in the fixed Candid/Spike/service-field cadence
var _concealment_epoch := -1.0   # first absolute spatial-cover sample in the fixed simulation cadence
var _concealment_boundary_ticks: Dictionary = {} # party id -> exact Candid entry/exit deadlines
var _spike_crossing_events: Dictionary = {} # party/enemy id -> exact swept damage events
var _restart_deadline := -1.0    # full-wipe restart; absolute scheduler tick
var _weak_wall_deadlines := {}   # wall index -> absolute crumble tick
var _restoring_fragment_authority := false
var _exit_rest_phase := "ready"
var _exit_rest_shelter_name := ""
var _exit_rest_members: Array[String] = []
var _exit_rest_commit_tick := -1.0
var _exit_rest_commit_day := 0
var _exit_rest_before_atp: Dictionary = {}
var _exit_rest_trigger_consumed := {} # exact shelter data id -> last accepted/retracted receipt

func configure_chunk(config: Dictionary) -> void:
	if config.has("fragment"):
		fragment = config["fragment"]
	if config.has("fragment_path"):
		fragment_path = str(config["fragment_path"])

func _build_chunk() -> void:
	if fragment == null and fragment_path != "":
		fragment = load(fragment_path) as Fragment
	if fragment == null:
		push_warning("DataFragmentChunk: no fragment assigned (set `fragment` or fragment_path)")
		return
	_build_environment()
	_apply_shelters()
	for spec in fragment.objects:
		_spawn_object(spec)
	# THE portal look (docs/PORTALS.md): every spawned pad pair gets its arch + live
	# destination lens; chained one-way pads get the arch alone. One call, every fragment.
	PortalFixtures.dress_matching(_portals)
	# Loader-owned failure wiring: a full party wipe restarts the fragment when the data asks for it.
	var gs = _get_game_state()
	if gs != null and bool(fragment.params.get("restart_on_wipe", false)):
		if not gs.character_downed.is_connected(_on_fragment_character_downed):
			gs.character_downed.connect(_on_fragment_character_downed)
	_set_preview_step((fragment.id if fragment.id != "" else "data_fragment") + "_start")
	# Install simulation cadence during construction when the host is already attached. `_process`
	# retains a retry for unusual hosts which attach their scheduler after the chunk enters the tree.
	_ensure_scheduled()


## SceneChunk builds its objects before the host installs the fragment GridWorld.
## Publish graph-backed shelter regions only after that explicit lifecycle receipt;
## construction already stored the authored center and size for this pure refresh.
func on_game_state_grid_ready() -> void:
	_republish_exit_shelter_navigation_regions()


## BasinWater emits state_changed only after its scheduled commit has applied
## every per-level blocker. Refresh semantic destinations at that exact graph
## boundary so a permanent shelter never advertises a stale topology revision.
func _on_basin_navigation_state_changed(_state: int) -> void:
	_republish_exit_shelter_navigation_regions()


func _republish_exit_shelter_navigation_regions() -> void:
	for shelter_v in _exit_shelters:
		var shelter := shelter_v as Node
		if not is_instance_valid(shelter):
			continue
		var center_v: Variant = shelter.get_meta(
			"exit_shelter_center", Vector3.INF)
		var half_v: Variant = shelter.get_meta(
			"exit_shelter_half_size", Vector2.ZERO)
		if center_v is Vector3 and half_v is Vector2:
			_publish_exit_shelter_navigation_region(
				shelter, center_v as Vector3, half_v as Vector2)


# --- Environment ---

func _build_environment() -> void:
	# Ground slabs get the world-triplanar deck tile (1 tile/m) so the grid reads through the floor, like
	# the sim room and generated stretches. A floor may name its own tile ("tile": "rust_iron", ...);
	# default deck_metal.
	for f in fragment.floors:
		_add_floor(self, _v3(f, "pos"), _v3(f, "size", Vector3.ONE),
			_col(f, "color", Color(0.1, 0.1, 0.12)), str(f.get("tile", "deck_metal")))
	for w in fragment.walls:
		var wall_box := _add_box(self, _v3(w, "pos"), _v3(w, "size", Vector3.ONE), _col(w, "color", Color(0.06, 0.06, 0.08)),
			_col(w, "emission", Color.BLACK), _f(w, "energy", 0.0))
		# A wall box may name a pixel-art atlas tile ("tile": "wall_panel") — the same world-triplanar
		# 1-tile/m material the floors use, TINTED by the box colour so palette fields keep working.
		if str(w.get("tile", "")) != "":
			wall_box.material_override = _tinted_tile_material(str(w["tile"]), _col(w, "color", Color.WHITE))
	for l in fragment.lights:
		_add_light(self, _v3(l, "pos"), _col(l, "color", Color.WHITE), _f(l, "energy", 1.0), _f(l, "range", 4.0))
	for lb in fragment.labels:
		_add_label(self, str(lb.get("text", "")), _v3(lb, "pos"), _col(lb, "color", Color(0.82, 0.86, 0.92)))
	for m in fragment.meshes:
		_instance_mesh(m)
	# Revolve-tower plans (params-driven pure data from the building filler) loft here — the loader
	# owns scene nodes. Shell gets the tinted atlas material; window quads keep their emissive surface.
	for lp in fragment.params.get("lathe_buildings", []):
		_spawn_lathe_building(lp as Dictionary)
	# LANDMARK hero plans (params-driven, from the building filler): BaseShapeBuilder specs placed by
	# their gameplay anchors — the main door road-snapped to the street. Bridges between them are
	# already grid data + filler boxes; here we assemble the hero's own meshes.
	for lm in fragment.params.get("landmark_buildings", []):
		_spawn_landmark_building(lm as Dictionary)

var _weak_walls: Array = []

func _spawn_weak_wall(spec: Dictionary) -> void:
	var idx := _weak_walls.size()
	var foot := _v3(spec, "pos")
	var n := _v3(spec, "n").normalized()
	var up := Vector3.UP
	# the crack TELL on the wall face (present from first sight)
	var crack := MeshInstance3D.new()
	crack.name = "WeakWallCrack%d" % idx
	var cbm := BoxMesh.new()
	cbm.size = Vector3(0.55, 0.4, 0.1)
	crack.mesh = cbm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.3, 0.08, 0.06)
	cmat.emission_enabled = true
	cmat.emission = Color(0.85, 0.15, 0.1)
	cmat.emission_energy_multiplier = 0.9
	crack.material_override = cmat
	add_child(crack)
	crack.global_position = foot + up * 2.2 + n * 0.1
	if absf(n.dot(up)) < 0.99:
		crack.global_transform.basis = Basis(n.cross(up).normalized(), up, n)
	# Three independently moving, externally authored slabs make the committed interval visible. The
	# root's local +Z axis follows the authored outward normal, so every generated landmark reuses the
	# same UV-mapped model without baking its world orientation into the asset.
	var facade := Node3D.new()
	facade.name = "WeakWallFacade%d" % idx
	add_child(facade)
	facade.global_position = foot + n * 0.08
	if absf(n.dot(up)) < 0.99:
		facade.global_transform.basis = Basis(up.cross(n).normalized(), up, n)
	var panels: Array[MeshInstance3D] = []
	var panel_starts: Array[Vector3] = []
	for panel_index in range(3):
		var panel := WEAK_WALL_COLLAPSE_PIECE_SCENE.instantiate() as MeshInstance3D
		panel.name = "WeakWallSlab%d_%d" % [idx, panel_index]
		panel.position = Vector3((float(panel_index) - 1.0) * 0.82, 0.0, 0.0)
		panel.scale = Vector3(0.92, 0.92 + 0.04 * float(panel_index % 2), 1.0)
		facade.add_child(panel)
		panels.append(panel)
		panel_starts.append(panel.position)
	# the rubble (revealed on crumble), centred on the kill zone
	var kmin := _v3(spec, "kill_min")
	var kmax := _v3(spec, "kill_max")
	var kc := (kmin + kmax) * 0.5
	var rubble := Node3D.new()
	rubble.name = "WeakWallRubble%d" % idx
	add_child(rubble)
	rubble.global_position = Vector3(kc.x, 0.0, kc.z)
	for ri in range(4):
		var rb := MeshInstance3D.new()
		var rbm := BoxMesh.new()
		rbm.size = Vector3(0.8 - 0.1 * float(ri), 0.45, 0.7)
		rb.mesh = rbm
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.30, 0.30, 0.33)
		rb.material_override = rmat
		rubble.add_child(rb)
		rb.position = Vector3(-0.5 + 0.45 * float(ri), 0.2, -0.3 + 0.3 * float(ri % 2))
	rubble.visible = false
	# the PRY point at the wall foot
	var ia := _add_interactable(self, "WeakWall%d" % idx, "Pry the cracked wall", foot + n * 0.9,
		"PRY", "", 1.0, true, 1.5, Interactable.InteractableType.INSPECTION, false)
	var iam := _add_box(ia, Vector3(0, 0.8, 0), Vector3(0.2, 1.6, 0.2), Color(0.5, 0.42, 0.3), Color(0.9, 0.6, 0.2), 0.5)
	_outline_interactable_child(ia, iam, "WeakWall%d" % idx, 1.5)
	var entry := {
		"crumbled": false,
		"source": ia,
		"trigger_consumed": 0,
		"kill_min": kmin,
		"kill_max": kmax,
		"crack": crack,
		"rubble": rubble,
		"facade": facade,
		"panels": panels,
		"panel_starts": panel_starts,
	}
	_weak_walls.append(entry)
	ia.set_meta("weak_wall_index", idx)
	ia.set_pre_trigger_validator(_validate_weak_wall_trigger.bind(idx, ia))
	ia.interacted.connect(_on_weak_wall_pried.bind(idx, ia))

## Retired source-less helper calls are deliberately inert. The wall only begins moving after its
## own one-shot has accepted the exact nearby, ready party body and minted the next registry receipt.
func _on_weak_wall_pried(idx: int, source: Node = null) -> bool:
	var sched = _get_scheduler()
	if sched == null or idx < 0 or idx >= _weak_walls.size() \
			or bool((_weak_walls[idx] as Dictionary)["crumbled"]) \
			or _weak_wall_deadlines.has(idx) \
			or not _weak_wall_source_receipt_pending(idx, source):
		return false
	var entry := _weak_walls[idx] as Dictionary
	entry["trigger_consumed"] = _weak_wall_source_trigger_count(source)
	var deadline := float(sched.get_current_tick()) + WEAK_WALL_CRUMBLE_DURATION
	_weak_wall_deadlines[idx] = deadline
	_schedule_weak_wall_at(idx, deadline)
	_sync_weak_wall_presenters()
	_publish_fragment_authority()
	return true


func _validate_weak_wall_trigger(
		source: Node, actor: String, idx: int, expected_source: Node) -> bool:
	return idx >= 0 and idx < _weak_walls.size() \
		and source == expected_source \
		and source == (_weak_walls[idx] as Dictionary).get("source") \
		and _get_scheduler() != null \
		and not bool((_weak_walls[idx] as Dictionary).get("crumbled", false)) \
		and not _weak_wall_deadlines.has(idx) \
		and _weak_wall_actor_ready_at_source(source, actor)


func _weak_wall_actor_ready_at_source(source: Node, actor: String) -> bool:
	return _fragment_actor_ready_at_source(source, actor)


func _fragment_actor_ready_at_source(source: Node, actor: String) -> bool:
	var gs = _get_game_state()
	if gs == null or not is_instance_valid(source) or not source is Node3D \
			or actor == "" or not gs.characters.has(actor) or not gs.get_party().has(actor) \
			or fragment == null or not fragment.party_ids.has(actor) \
			or not gs.is_narratively_available(actor) or gs.is_downed(actor) \
			or gs.is_knocked_down(actor) or gs.is_moving(actor) or gs.is_resting(actor) \
			or gs.is_dodging(actor) or gs.is_endocytosing(actor) \
			or gs.is_external_traversal_active(actor) or gs.is_dragging(actor) \
			or gs.is_field_restoring(actor) or gs.is_pushing(actor):
		return false
	var source_position := _fragment_source_data_position(source)
	if not source_position.is_finite():
		return false
	if gs.grid != null and gs.grid.level_count > 1 \
			and int(gs.get_character_level(actor)) != int(gs.grid.level_for_y(source_position.y)):
		return false
	var actor_position: Vector3 = gs.get_position(actor)
	return Vector2(actor_position.x, actor_position.z).distance_to(
		Vector2(source_position.x, source_position.z)
	) <= float(source.get("interaction_radius")) + WEAK_WALL_POSITION_TOLERANCE \
		and absf(actor_position.y - source_position.y) <= WEAK_WALL_HEIGHT_TOLERANCE


func _weak_wall_source_data_position(source: Node) -> Vector3:
	return _fragment_source_data_position(source)


func _fragment_source_data_position(source: Node) -> Vector3:
	var gs = _get_game_state()
	var data_id := str(source.get("data_id")) if is_instance_valid(source) else ""
	if gs != null and data_id != "" and gs.has_interactable(data_id):
		var saved_position: Variant = gs.get_interactable(data_id).get("position", Vector3.INF)
		if saved_position is Vector3:
			return saved_position
	if source is Node3D:
		var world_position := (source as Node3D).global_position
		if gs != null and gs.coord_map != null and gs.coord_map.has_method("to_data"):
			return gs.coord_map.to_data(world_position)
		return world_position
	return Vector3.INF


func _weak_wall_source_trigger_count(source: Node) -> int:
	return _fragment_source_trigger_count(source)


func _fragment_source_trigger_count(source: Node) -> int:
	var gs = _get_game_state()
	var data_id := str(source.get("data_id")) if is_instance_valid(source) else ""
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return -1
	return int(gs.get_interactable(data_id).get("trigger_count", -1))


func _weak_wall_source_receipt_pending(idx: int, source: Node) -> bool:
	if idx < 0 or idx >= _weak_walls.size() or not is_instance_valid(source):
		return false
	var entry := _weak_walls[idx] as Dictionary
	var actor := str(source.get("active_character"))
	if not _validate_weak_wall_trigger(source, actor, idx, entry.get("source")) \
			or not bool(source.get("one_shot")) or not bool(source.get("_used")) \
			or bool(source.get("interaction_enabled")):
		return false
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return false
	var receipt: Dictionary = gs.get_interactable(data_id)
	return int(receipt.get("trigger_count", -1)) \
			== int(entry.get("trigger_consumed", 0)) + 1 \
		and str(receipt.get("last_trigger_character", "")) == actor \
		and bool(receipt.get("one_shot", false)) \
		and bool(receipt.get("triggered", false)) \
		and not bool(receipt.get("enabled", true))

func _commit_weak_wall(idx: int) -> void:
	_weak_wall_deadlines.erase(idx)
	if idx < 0 or idx >= _weak_walls.size():
		_publish_fragment_authority()
		return
	var entry := _weak_walls[idx] as Dictionary
	if bool(entry["crumbled"]):
		return
	entry["crumbled"] = true
	var gs = _get_game_state()
	var kmin := entry["kill_min"] as Vector3
	var kmax := entry["kill_max"] as Vector3
	# the debris field resolves at the commit tick (analytic, never per-frame sampled)
	for en in _enemies.duplicate():
		if en == null or not is_instance_valid(en) or not en.is_alive():
			continue
		var ep: Vector3 = gs.get_position(en.char_id) if gs != null else Vector3.ZERO
		if ep.x > kmin.x and ep.x < kmax.x and ep.z > kmin.z and ep.z < kmax.z:
			if gs != null:
				gs.command_stop(en.char_id)
			en.take_damage(float(en.max_hp))
	_set_weak_wall_presenter(idx, true)
	_publish_fragment_authority()

## ---- DISTRICT DETAIL RENDERERS (shared by the level loader and the architecture showcase;
## the showcase chunk extends this class) ----

## The plumbing detail passes (SURVEY REBUILD 1.1) — flume + ribs + fixtures grown from the survey.
## Materials by family: construction metal keeps the building tint; wheels/pipes run rust; slit
## panels and the sign face stay recessed-dark; water/cascade/terminal glow the terminal green.
func _add_plumbing_details(root: Node3D, spec: Dictionary) -> void:
	var built: Dictionary = BaseShapeBuilder.plumbing_details(spec)
	_add_lattice_mesh(root, "PlumbBody", built.get("body"),
		_tinted_tile_material(str(spec.get("tile", "facility_metal")), spec.get("color", Color(0.24, 0.35, 0.32))))
	var rust := StandardMaterial3D.new()
	rust.albedo_color = Color(0.40, 0.25, 0.16)
	rust.roughness = 0.88
	rust.metallic = 0.25
	_add_lattice_mesh(root, "PlumbRust", built.get("rust"), rust)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.06, 0.06)
	dark.roughness = 0.94
	_add_lattice_mesh(root, "PlumbDark", built.get("dark"), dark)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.16, 0.42, 0.26)
	glow.emission_enabled = true
	glow.emission = Color(0.36, 0.91, 0.50)   # terminal green — the world's ONLY standard emissive
	glow.emission_energy_multiplier = 2.4
	_add_lattice_mesh(root, "PlumbGlow", built.get("glow"), glow)
	var rail := _railing_material()
	rail.albedo_color = Color(0.52, 0.40, 0.30)   # rusted mesh railing along the flume rims
	_add_lattice_mesh(root, "PlumbRails", built.get("rails"), rail)
	# the title label rides the PHYSICAL sign board (the plate's framed plate, not floating text)
	var lbl := root.get_node_or_null("Nameplate")
	if lbl != null and built.has("nameplate_pos"):
		(lbl as Label3D).position = built["nameplate_pos"] as Vector3

## The hypelines detail passes (SURVEY REBUILD 1.2): the six arms with the walkable lane decks,
## trestles, valve wheel, sign stack, toll-gate arch, ramp, pores and mast — from the survey.
## The two flanking entry lamps are the plate's only WARM accents (amber where the plate demands).
func _add_hypelines_details(root: Node3D, spec: Dictionary) -> void:
	var built: Dictionary = BaseShapeBuilder.hypelines_details(spec)
	_add_lattice_mesh(root, "HypeBody", built.get("body"),
		_tinted_tile_material(str(spec.get("tile", "facility_metal")), spec.get("color", Color(0.26, 0.33, 0.29))))
	var rust := StandardMaterial3D.new()
	rust.albedo_color = Color(0.40, 0.25, 0.16)
	rust.roughness = 0.88
	rust.metallic = 0.25
	_add_lattice_mesh(root, "HypeRust", built.get("rust"), rust)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.07, 0.09, 0.08)
	dark.roughness = 0.94
	_add_lattice_mesh(root, "HypeDark", built.get("dark"), dark)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.16, 0.42, 0.26)
	glow.emission_enabled = true
	glow.emission = Color(0.36, 0.91, 0.50)   # terminal green — the world's ONLY standard emissive
	glow.emission_energy_multiplier = 2.4
	_add_lattice_mesh(root, "HypeGlow", built.get("glow"), glow)
	var warm := StandardMaterial3D.new()
	warm.albedo_color = Color(0.45, 0.33, 0.18)
	warm.emission_enabled = true
	warm.emission = Color(0.95, 0.64, 0.32)
	warm.emission_energy_multiplier = 1.4
	_add_lattice_mesh(root, "HypeWarm", built.get("warm"), warm)
	var rail := _railing_material()
	rail.albedo_color = Color(0.52, 0.40, 0.30)
	_add_lattice_mesh(root, "HypeRails", built.get("rails"), rail)
	var lbl := root.get_node_or_null("Nameplate")
	if lbl != null and built.has("nameplate_pos"):
		(lbl as Label3D).position = built["nameplate_pos"] as Vector3

## The cleanstreets detail passes (SURVEY REBUILD 1.3): queue fins + spikes, placards, the toll
## kiosk (its cyan cross/screen are the pavilion's only cool emissives — plate-demanded, like the
## beacon enforcement door), the warm-gold vaulted underside, perforation clusters, the monolith.
func _add_cleanstreets_details(root: Node3D, spec: Dictionary) -> void:
	var built: Dictionary = BaseShapeBuilder.cleanstreets_details(spec)
	_add_lattice_mesh(root, "CleanBody", built.get("body"),
		_tinted_tile_material(str(spec.get("tile", "facility_metal")), spec.get("color", Color(0.45, 0.47, 0.42))))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.16, 0.25, 0.22)   # desaturated verdigris panel fields
	dark.roughness = 0.9
	_add_lattice_mesh(root, "CleanPanels", built.get("dark"), dark)
	var warm := StandardMaterial3D.new()
	warm.albedo_color = Color(0.45, 0.33, 0.18)
	warm.emission_enabled = true
	warm.emission = Color(0.95, 0.64, 0.32)   # the gold under-canopy glow — the pavilion's main light
	warm.emission_energy_multiplier = 1.8
	_add_lattice_mesh(root, "CleanWarm", built.get("warm"), warm)
	var cyan := StandardMaterial3D.new()
	cyan.albedo_color = Color(0.10, 0.30, 0.34)
	cyan.emission_enabled = true
	cyan.emission = Color(0.25, 0.85, 0.95)   # the kiosk cross/screen — the sole cool accent
	cyan.emission_energy_multiplier = 2.0
	_add_lattice_mesh(root, "CleanCyan", built.get("cyan"), cyan)
	var lbl := root.get_node_or_null("Nameplate")
	if lbl != null and built.has("nameplate_pos"):
		(lbl as Label3D).position = built["nameplate_pos"] as Vector3

## The greenfields BALCONIES pass (SURVEY REBUILD 1.4): wavy bone slab rings + railings + arcade +
## amber windows + ribs + the teal-lit roof terrace, all on the survey's storey datums. Two-tone:
## bone structure over the verdigris wall box; amber windows and warm sconces are plate-demanded.
func _add_greenfields_details(root: Node3D, spec: Dictionary) -> void:
	var built: Dictionary = BaseShapeBuilder.greenfields_details(spec)
	_add_lattice_mesh(root, "GreenBone", built.get("bone"),
		_tinted_tile_material(str(spec.get("tile", "facility_metal")), Color(0.81, 0.77, 0.65)))
	var doorm := StandardMaterial3D.new()
	doorm.albedo_color = Color(0.18, 0.29, 0.24)   # dark-green leaves + the sign field
	doorm.roughness = 0.9
	_add_lattice_mesh(root, "GreenDoors", built.get("door"), doorm)
	var amber := StandardMaterial3D.new()
	amber.albedo_color = Color(0.42, 0.30, 0.14)
	amber.emission_enabled = true
	amber.emission = Color(0.95, 0.72, 0.38)   # the warm window glow (plate-demanded amber)
	amber.emission_energy_multiplier = 1.6
	_add_lattice_mesh(root, "GreenWindows", built.get("amber"), amber)
	var tealm := StandardMaterial3D.new()
	tealm.albedo_color = Color(0.10, 0.32, 0.32)
	tealm.emission_enabled = true
	tealm.emission = Color(0.22, 0.90, 0.85)   # the roof-bud bioluminescence (plate accent)
	tealm.emission_energy_multiplier = 2.2
	_add_lattice_mesh(root, "GreenBuds", built.get("teal"), tealm)
	var leafm := StandardMaterial3D.new()
	leafm.albedo_color = Color(0.24, 0.42, 0.20)
	leafm.roughness = 0.9
	_add_lattice_mesh(root, "GreenLeaf", built.get("leaf"), leafm)
	var warmm := StandardMaterial3D.new()
	warmm.albedo_color = Color(0.45, 0.33, 0.18)
	warmm.emission_enabled = true
	warmm.emission = Color(0.95, 0.64, 0.32)
	warmm.emission_energy_multiplier = 1.3
	_add_lattice_mesh(root, "GreenSconces", built.get("warm"), warmm)
	var rail := _railing_material()
	rail.albedo_color = Color(0.80, 0.76, 0.64)   # bone double-rail balustrades
	_add_lattice_mesh(root, "GreenRails", built.get("rails"), rail)
	var lbl := root.get_node_or_null("Nameplate")
	if lbl != null and built.has("nameplate_pos"):
		(lbl as Label3D).position = built["nameplate_pos"] as Vector3

## The ancourage detail passes (SURVEY REBUILD 1.5): arch idiom + glass, placards, roses, louver,
## valves, saddle stacks (the flame is the plate-demanded warm accent) and the oily root-fan.
func _add_ancourage_details(root: Node3D, spec: Dictionary) -> void:
	var built: Dictionary = BaseShapeBuilder.ancourage_details(spec)
	_add_lattice_mesh(root, "AncBody", built.get("body"),
		_tinted_tile_material(str(spec.get("tile", "facility_metal")), spec.get("color", Color(0.27, 0.36, 0.33))))
	_add_lattice_mesh(root, "AncBone", built.get("bone"),
		_tinted_tile_material("facility_metal", Color(0.80, 0.75, 0.62)))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.06, 0.07, 0.06)   # boards, foil apertures, the oily roots
	dark.roughness = 0.9
	dark.metallic = 0.15
	_add_lattice_mesh(root, "AncDark", built.get("dark"), dark)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.16, 0.42, 0.26)
	glow.emission_enabled = true
	glow.emission = Color(0.36, 0.91, 0.50)   # the arch glass + readout — terminal green
	glow.emission_energy_multiplier = 2.6
	_add_lattice_mesh(root, "AncGlow", built.get("glow"), glow)
	var warm := StandardMaterial3D.new()
	warm.albedo_color = Color(0.55, 0.30, 0.10)
	warm.emission_enabled = true
	warm.emission = Color(1.0, 0.55, 0.15)   # the flare-stack FLAME (plate-demanded)
	warm.emission_energy_multiplier = 3.0
	_add_lattice_mesh(root, "AncFlame", built.get("warm"), warm)
	var rust := StandardMaterial3D.new()
	rust.albedo_color = Color(0.40, 0.25, 0.16)
	rust.roughness = 0.88
	rust.metallic = 0.25
	_add_lattice_mesh(root, "AncRust", built.get("rust"), rust)
	var lbl := root.get_node_or_null("Nameplate")
	if lbl != null and built.has("nameplate_pos"):
		(lbl as Label3D).position = built["nameplate_pos"] as Vector3

## The pixel-art railing tile (alpha-scissor) — one post + top & bottom rails, the rest transparent;
## tiled across a card it reads as evenly-spaced balusters. FILTER_NEAREST keeps it crisp.
func _railing_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _railing_texture()
	m.albedo_color = Color(0.86, 0.82, 0.70)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 0.85
	return m

func _railing_texture() -> ImageTexture:
	var tw := 12
	var th := 24
	var img := Image.create(tw, th, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var bar := Color(0.90, 0.86, 0.72, 1.0)
	for x in range(tw):
		img.set_pixel(x, 0, bar); img.set_pixel(x, 1, bar); img.set_pixel(x, 2, bar)
		img.set_pixel(x, th - 3, bar); img.set_pixel(x, th - 2, bar); img.set_pixel(x, th - 1, bar)
	for x in range(1, 4):
		for y in range(3, th - 3):
			img.set_pixel(x, y, bar)
	return ImageTexture.create_from_image(img)

func _add_lattice_mesh(root: Node3D, mesh_name: String, mesh, mat: Material) -> void:
	if mesh == null or (mesh as ArrayMesh).get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = mesh
	mi.material_override = mat
	root.add_child(mi)

## The beacon detail passes (SURVEY REBUILD 1.6): the five great arch bays (bone ribs + amber
## shelf-grid panes), dome ribs to the lantern, oculi, cartouche, green status board, the
## enforcement vestibule (the ONE cyan accent), sconces, lantern clerestory + roof garden, beds.
func _add_beacon_details(root: Node3D, spec: Dictionary) -> void:
	var built: Dictionary = BaseShapeBuilder.beacon_details(spec)
	_add_lattice_mesh(root, "BeaconBone", built.get("bone"),
		_tinted_tile_material("facility_metal", Color(0.72, 0.65, 0.52)))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.07, 0.09, 0.08)
	dark.roughness = 0.92
	_add_lattice_mesh(root, "BeaconDark", built.get("dark"), dark)
	var amber := StandardMaterial3D.new()
	amber.albedo_color = Color(0.40, 0.28, 0.12)
	amber.emission_enabled = true
	amber.emission = Color(0.95, 0.72, 0.38)   # the shelf-grid glow (plate-demanded warm)
	amber.emission_energy_multiplier = 1.7
	_add_lattice_mesh(root, "BeaconPanes", built.get("amber"), amber)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.16, 0.42, 0.26)
	glow.emission_enabled = true
	glow.emission = Color(0.36, 0.91, 0.50)   # status board + keypads — terminal green
	glow.emission_energy_multiplier = 2.4
	_add_lattice_mesh(root, "BeaconGlow", built.get("glow"), glow)
	var cyanm := StandardMaterial3D.new()
	cyanm.albedo_color = Color(0.10, 0.30, 0.34)
	cyanm.emission_enabled = true
	cyanm.emission = Color(0.25, 0.85, 0.95)   # the enforcement chevron — the sole cool accent
	cyanm.emission_energy_multiplier = 2.2
	_add_lattice_mesh(root, "BeaconCyan", built.get("cyan"), cyanm)
	var warmm := StandardMaterial3D.new()
	warmm.albedo_color = Color(0.45, 0.33, 0.18)
	warmm.emission_enabled = true
	warmm.emission = Color(0.95, 0.64, 0.32)
	warmm.emission_energy_multiplier = 1.4
	_add_lattice_mesh(root, "BeaconSconces", built.get("warm"), warmm)
	var leafm := StandardMaterial3D.new()
	leafm.albedo_color = Color(0.24, 0.42, 0.20)
	leafm.roughness = 0.9
	_add_lattice_mesh(root, "BeaconLeaf", built.get("leaf"), leafm)
	var rail := _railing_material()
	rail.albedo_color = Color(0.78, 0.74, 0.62)
	_add_lattice_mesh(root, "BeaconRails", built.get("rails"), rail)
	var lbl := root.get_node_or_null("Nameplate")
	if lbl != null and built.has("nameplate_pos"):
		(lbl as Label3D).position = built["nameplate_pos"] as Vector3

func _add_bulwark_details(root: Node3D, spec: Dictionary) -> void:
	var built: Dictionary = BaseShapeBuilder.bulwark_details(spec)
	_add_lattice_mesh(root, "BulwarkFrame", built.get("metal"),
		_tinted_tile_material("facility_metal", Color(0.40, 0.48, 0.45)))
	_add_lattice_mesh(root, "BulwarkWeb", built.get("bone"),
		_tinted_tile_material("facility_metal", Color(0.70, 0.68, 0.60)))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.10, 0.12, 0.12)
	dark.roughness = 0.9
	_add_lattice_mesh(root, "BulwarkDark", built.get("dark"), dark)
	var rustm := StandardMaterial3D.new()
	rustm.albedo_color = Color(0.42, 0.25, 0.11)
	rustm.roughness = 1.0
	_add_lattice_mesh(root, "BulwarkRust", built.get("rust"), rustm)
	var mem := StandardMaterial3D.new()
	mem.albedo_color = Color(0.34, 0.26, 0.42)
	mem.emission_enabled = true
	mem.emission = Color(0.60, 0.42, 0.85)   # the barrier membrane's faint inner light (plate)
	mem.emission_energy_multiplier = 1.8
	mem.roughness = 0.35
	_add_lattice_mesh(root, "BulwarkMembrane", built.get("membrane"), mem)
	var glowm := StandardMaterial3D.new()
	glowm.albedo_color = Color(0.14, 0.38, 0.24)
	glowm.emission_enabled = true
	glowm.emission = Color(0.36, 0.91, 0.50)   # indicator + readout + CRT — terminal green
	glowm.emission_energy_multiplier = 2.4
	_add_lattice_mesh(root, "BulwarkGlow", built.get("glow"), glowm)
	var lbl := root.get_node_or_null("Nameplate")
	if lbl != null and built.has("nameplate_pos"):
		(lbl as Label3D).position = built["nameplate_pos"] as Vector3

func _add_zone3_details(root: Node3D, spec: Dictionary) -> void:
	var built: Dictionary = BaseShapeBuilder.zone3_details(spec)
	_add_lattice_mesh(root, "Zone3Wood", built.get("wood"),
		_tinted_tile_material("facility_metal", Color(0.33, 0.40, 0.36)))
	_add_lattice_mesh(root, "Zone3Metal", built.get("metal"),
		_tinted_tile_material("facility_metal", Color(0.42, 0.46, 0.43)))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.07, 0.08, 0.08)
	dark.roughness = 0.94
	_add_lattice_mesh(root, "Zone3Dark", built.get("dark"), dark)
	var rustm := StandardMaterial3D.new()
	rustm.albedo_color = Color(0.44, 0.24, 0.12)   # the iron creep — tendrils, climbs, drips
	rustm.roughness = 1.0
	_add_lattice_mesh(root, "Zone3Rust", built.get("rust"), rustm)
	var glowm := StandardMaterial3D.new()
	glowm.albedo_color = Color(0.12, 0.34, 0.22)
	glowm.emission_enabled = true
	glowm.emission = Color(0.36, 0.91, 0.50)   # the terminal cabinet — the ruin's one glow
	glowm.emission_energy_multiplier = 2.0
	_add_lattice_mesh(root, "Zone3Glow", built.get("glow"), glowm)
	var lbl := root.get_node_or_null("Nameplate")
	if lbl != null and built.has("nameplate_pos"):
		(lbl as Label3D).position = built["nameplate_pos"] as Vector3

func _add_honeycomb_details(root: Node3D, spec: Dictionary) -> void:
	var built: Dictionary = BaseShapeBuilder.honeycomb_details(spec)
	_add_lattice_mesh(root, "HcombBone", built.get("bone"),
		_tinted_tile_material("facility_metal", Color(0.72, 0.69, 0.58)))
	_add_lattice_mesh(root, "HcombMetal", built.get("metal"),
		_tinted_tile_material("facility_metal", Color(0.44, 0.42, 0.36)))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.09, 0.10, 0.10)
	dark.roughness = 0.92
	_add_lattice_mesh(root, "HcombDark", built.get("dark"), dark)
	var rustm := StandardMaterial3D.new()
	rustm.albedo_color = Color(0.43, 0.24, 0.11)
	rustm.roughness = 1.0
	_add_lattice_mesh(root, "HcombRust", built.get("rust"), rustm)
	var leafm := StandardMaterial3D.new()
	leafm.albedo_color = Color(0.24, 0.42, 0.20)
	leafm.roughness = 0.9
	_add_lattice_mesh(root, "HcombLeaf", built.get("leaf"), leafm)
	var warmm := StandardMaterial3D.new()
	warmm.albedo_color = Color(0.45, 0.28, 0.14)
	warmm.emission_enabled = true
	warmm.emission = Color(0.98, 0.52, 0.22)   # ember strings + sconces + beacon tips (plate warm)
	warmm.emission_energy_multiplier = 1.8
	_add_lattice_mesh(root, "HcombEmber", built.get("warm"), warmm)
	var cyanm := StandardMaterial3D.new()
	cyanm.albedo_color = Color(0.10, 0.30, 0.34)
	cyanm.emission_enabled = true
	cyanm.emission = Color(0.25, 0.85, 0.95)   # the transom + kiosk CRT (the entry's teal idiom)
	cyanm.emission_energy_multiplier = 2.0
	_add_lattice_mesh(root, "HcombCyan", built.get("cyan"), cyanm)
	var lbl := root.get_node_or_null("Nameplate")
	if lbl != null and built.has("nameplate_pos"):
		(lbl as Label3D).position = built["nameplate_pos"] as Vector3

func _add_open_files_details(root: Node3D, spec: Dictionary) -> void:
	var built: Dictionary = BaseShapeBuilder.open_files_details(spec)
	_add_lattice_mesh(root, "OfBone", built.get("bone"),
		_tinted_tile_material("facility_metal", Color(0.58, 0.60, 0.55)))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.09, 0.10, 0.11)
	dark.roughness = 0.92
	_add_lattice_mesh(root, "OfDark", built.get("dark"), dark)
	var warmm := StandardMaterial3D.new()
	warmm.albedo_color = Color(0.45, 0.30, 0.15)
	warmm.emission_enabled = true
	warmm.emission = Color(0.95, 0.66, 0.30)
	warmm.emission_energy_multiplier = 1.6
	_add_lattice_mesh(root, "OfSconces", built.get("warm"), warmm)
	var glowm := StandardMaterial3D.new()
	glowm.albedo_color = Color(0.12, 0.34, 0.22)
	glowm.emission_enabled = true
	glowm.emission = Color(0.36, 0.91, 0.50)   # the sign text + console CRTs — terminal green
	glowm.emission_energy_multiplier = 2.2
	_add_lattice_mesh(root, "OfGlow", built.get("glow"), glowm)
	var cyanm := StandardMaterial3D.new()
	cyanm.albedo_color = Color(0.10, 0.30, 0.34)
	cyanm.emission_enabled = true
	cyanm.emission = Color(0.25, 0.85, 0.95)   # the portal pour + scan beam (plate-demanded cyan)
	cyanm.emission_energy_multiplier = 2.4
	_add_lattice_mesh(root, "OfCyan", built.get("cyan"), cyanm)
	var lbl := root.get_node_or_null("Nameplate")
	if lbl != null and built.has("nameplate_pos"):
		(lbl as Label3D).position = built["nameplate_pos"] as Vector3

## The Aghora material family (both Aghora kinds share it): verdigris metal, near-black, warm
## amber interiors, the district's MAGENTA neon, foliage, and dull canvas.
func _add_aghora_buckets(root: Node3D, prefix: String, built: Dictionary) -> void:
	_add_lattice_mesh(root, "%sMetal" % prefix, built.get("metal"),
		_tinted_tile_material("facility_metal", Color(0.40, 0.46, 0.44)))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.09, 0.10)
	dark.roughness = 0.92
	_add_lattice_mesh(root, "%sDark" % prefix, built.get("dark"), dark)
	var amber := StandardMaterial3D.new()
	amber.albedo_color = Color(0.42, 0.30, 0.14)
	amber.emission_enabled = true
	amber.emission = Color(0.98, 0.72, 0.36)   # the warm interior light spilling from every cell
	amber.emission_energy_multiplier = 1.6
	_add_lattice_mesh(root, "%sAmber" % prefix, built.get("amber"), amber)
	var neon := StandardMaterial3D.new()
	neon.albedo_color = Color(0.30, 0.10, 0.28)
	neon.emission_enabled = true
	neon.emission = Color(0.92, 0.32, 0.86)   # the Aghora's magenta — the counterfeit agora's mark
	neon.emission_energy_multiplier = 3.2
	_add_lattice_mesh(root, "%sNeon" % prefix, built.get("neon"), neon)
	var leafm := StandardMaterial3D.new()
	leafm.albedo_color = Color(0.24, 0.42, 0.20)
	leafm.roughness = 0.9
	_add_lattice_mesh(root, "%sLeaf" % prefix, built.get("leaf"), leafm)
	var clothm := StandardMaterial3D.new()
	clothm.albedo_color = Color(0.38, 0.26, 0.24)
	clothm.roughness = 1.0
	clothm.cull_mode = BaseMaterial3D.CULL_DISABLED   # awning/flag sheets read from both sides
	_add_lattice_mesh(root, "%sCloth" % prefix, built.get("cloth"), clothm)
	var lbl := root.get_node_or_null("Nameplate")
	if lbl != null and built.has("nameplate_pos"):
		(lbl as Label3D).position = built["nameplate_pos"] as Vector3

func _add_aghora_exchange_details(root: Node3D, spec: Dictionary) -> void:
	_add_aghora_buckets(root, "Aghora", BaseShapeBuilder.aghora_exchange_details(spec))

func _add_aghora_stack_details(root: Node3D, spec: Dictionary) -> void:
	_add_aghora_buckets(root, "AghoraStk", BaseShapeBuilder.aghora_stack_details(spec))

## The NUTECH facility (GDD 11.2): grey institutional concrete, mostly-dark window grids with a
## pale cool-white lit minority, the glowing white roofline board, the terminal-green status
## indicator — abandoned, but still legible as a working facility.
func _add_facility_checkpoint_details(root: Node3D, spec: Dictionary) -> void:
	var built: Dictionary = BaseShapeBuilder.facility_checkpoint_details(spec)
	_add_lattice_mesh(root, "CpFrame", built.get("frame"),
		_tinted_tile_material("facility_metal", Color(0.66, 0.68, 0.70)))
	var greenm := StandardMaterial3D.new()
	greenm.albedo_color = Color(0.16, 0.4, 0.24)
	greenm.emission_enabled = true
	greenm.emission = Color(0.36, 0.91, 0.5)
	greenm.emission_energy_multiplier = 2.2
	_add_lattice_mesh(root, "CpGreen", built.get("green"), greenm)
	var darkm := StandardMaterial3D.new()
	darkm.albedo_color = Color(0.06, 0.07, 0.08)
	darkm.roughness = 0.92
	_add_lattice_mesh(root, "CpDark", built.get("dark"), darkm)
	var lampm := StandardMaterial3D.new()
	lampm.albedo_color = Color(0.7, 0.78, 0.9)
	lampm.emission_enabled = true
	lampm.emission = Color(0.72, 0.84, 1.0)
	lampm.emission_energy_multiplier = 2.6
	_add_lattice_mesh(root, "CpLamp", built.get("lamp"), lampm)
	var boardm := StandardMaterial3D.new()
	boardm.albedo_color = Color(0.85, 0.87, 0.86)
	boardm.emission_enabled = true
	boardm.emission = Color(0.95, 0.97, 0.94)
	boardm.emission_energy_multiplier = 1.4
	_add_lattice_mesh(root, "CpBoard", built.get("board"), boardm)

func _add_nutech_details(root: Node3D, spec: Dictionary) -> void:
	var built: Dictionary = BaseShapeBuilder.nutech_details(spec)
	_add_lattice_mesh(root, "NtConcrete", built.get("concrete"),
		_tinted_tile_material("facility_metal", Color(0.50, 0.51, 0.52)))
	_add_lattice_mesh(root, "NtMetal", built.get("metal"),
		_tinted_tile_material("facility_metal", Color(0.38, 0.42, 0.42)))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.07, 0.08, 0.09)
	dark.roughness = 0.92
	_add_lattice_mesh(root, "NtDark", built.get("dark"), dark)
	var litm := StandardMaterial3D.new()
	litm.albedo_color = Color(0.28, 0.32, 0.36)
	litm.emission_enabled = true
	litm.emission = Color(0.80, 0.88, 1.0)   # the pale institutional interior light
	litm.emission_energy_multiplier = 1.3
	_add_lattice_mesh(root, "NtLit", built.get("lit"), litm)
	var whitem := StandardMaterial3D.new()
	whitem.albedo_color = Color(0.72, 0.74, 0.72)
	whitem.emission_enabled = true
	whitem.emission = Color(0.95, 0.97, 0.94)   # the NUTECH board — white, still powered
	whitem.emission_energy_multiplier = 1.3
	_add_lattice_mesh(root, "NtWhite", built.get("white"), whitem)
	var greenm := StandardMaterial3D.new()
	greenm.albedo_color = Color(0.10, 0.26, 0.16)
	greenm.emission_enabled = true
	greenm.emission = Color(0.36, 0.91, 0.50)   # terminal green — the institution's standard
	greenm.emission_energy_multiplier = 1.8
	_add_lattice_mesh(root, "NtGreen", built.get("green"), greenm)
	var lbl := root.get_node_or_null("Nameplate")
	if lbl != null and built.has("nameplate_pos"):
		(lbl as Label3D).position = built["nameplate_pos"] as Vector3

## Loca's Watchtower (the Act 1 boss landmark): cold masonry + the cool-blue institutional light
## the GDD names ("glowing cool blue from interior lighting"), cyan beacon tips, the red-brown
## containment tangles, and the fever-red core in the summit cage — Loca's bound chamber.
func _add_watchtower_details(root: Node3D, spec: Dictionary) -> void:
	var built: Dictionary = BaseShapeBuilder.watchtower_details(spec)
	_add_lattice_mesh(root, "WtStone", built.get("stone"),
		_tinted_tile_material("facility_metal", Color(0.48, 0.52, 0.58)))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.07, 0.08, 0.10)
	dark.roughness = 0.92
	_add_lattice_mesh(root, "WtDark", built.get("dark"), dark)
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0.08, 0.13, 0.24)
	blue.emission_enabled = true
	blue.emission = Color(0.36, 0.66, 1.0)   # the watchtower's cool blue, visible from a long way off
	blue.emission_energy_multiplier = 2.1
	_add_lattice_mesh(root, "WtBlue", built.get("blue"), blue)
	var tipm := StandardMaterial3D.new()
	tipm.albedo_color = Color(0.12, 0.24, 0.30)
	tipm.emission_enabled = true
	tipm.emission = Color(0.45, 0.90, 1.0)   # beacon gems — the cold cyan-white scanner family
	tipm.emission_energy_multiplier = 3.0
	_add_lattice_mesh(root, "WtTips", built.get("tips"), tipm)
	var rustm := StandardMaterial3D.new()
	rustm.albedo_color = Color(0.44, 0.17, 0.11)   # the wire/tau tangles: matte red-brown
	rustm.roughness = 0.98
	_add_lattice_mesh(root, "WtTangles", built.get("rust"), rustm)
	var corem := StandardMaterial3D.new()
	corem.albedo_color = Color(0.38, 0.07, 0.09)
	corem.emission_enabled = true
	corem.emission = Color(1.0, 0.30, 0.26)   # the fever-red bound state (the plate's summit glow)
	corem.emission_energy_multiplier = 2.8
	_add_lattice_mesh(root, "WtCore", built.get("core"), corem)
	var lbl := root.get_node_or_null("Nameplate")
	if lbl != null and built.has("nameplate_pos"):
		(lbl as Label3D).position = built["nameplate_pos"] as Vector3

func _spawn_landmark_building(lm: Dictionary) -> void:
	var kind := str(lm.get("kind", ""))
	if not BaseShapeBuilder.SPECS.has(kind):
		return
	# the SAME seeded variant the filler surveyed (anchors/lanes came from it — the visual must match)
	var spec: Dictionary = BaseShapeBuilder.generate(kind, int(lm.get("spec_seed", 0)))
	# a placement may overlay survey-table vars (e.g. the bazaar disabling a stair whose flank
	# faces a measured sub-alley) — layered into spec.vars exactly where roll_vars land
	var tv: Dictionary = lm.get("table_vars", {})
	if not tv.is_empty():
		var spec_vars: Dictionary = spec.get("vars", {})
		for tk in tv.keys():
			var cur: Dictionary = (spec_vars.get(tk, {}) as Dictionary).duplicate(true)
			cur.merge(tv[tk] as Dictionary, true)
			spec_vars[tk] = cur
		spec["vars"] = spec_vars
	var ent: Dictionary = LatticeBuilder.entrances(spec)
	var root := Node3D.new()
	root.name = "Landmark_%s" % kind
	add_child(root)
	root.position = _v3(lm, "pos")
	root.rotation = Vector3(0.0, float(lm.get("yaw", 0.0)), 0.0)
	# a diorama slot may scale the whole landmark into its declared envelope (the paranucleus's
	# facility slots); full-size placements omit the key
	var lm_scale := float(lm.get("scale", 1.0))
	if lm_scale != 1.0:
		root.scale = Vector3.ONE * lm_scale
	var body := BaseShapeBuilder.base_mesh(spec, ent.get("reserved", []))
	if body != null:
		body.surface_set_material(0, _tinted_tile_material(str(spec.get("tile", "facility_metal")),
			spec.get("color", Color(0.4, 0.4, 0.42))))
		var bi := MeshInstance3D.new()
		bi.name = "Body"
		bi.mesh = body
		root.add_child(bi)
	# entrance meshes (stone surround + dark/teal leaves)
	var mats := {"stone": _tinted_tile_material("facility_metal", Color(0.66, 0.62, 0.50))}
	var darkm := StandardMaterial3D.new()
	darkm.albedo_color = Color(0.05, 0.05, 0.06)
	var tealm := StandardMaterial3D.new()
	tealm.albedo_color = Color(0.10, 0.28, 0.30)
	tealm.emission_enabled = true
	tealm.emission = Color(0.22, 0.82, 0.86)
	mats["dark"] = darkm
	mats["accent"] = tealm
	for mk in ["stone", "dark", "accent"]:
		var em: Variant = ent.get(mk)
		if em != null and (em as ArrayMesh).get_surface_count() > 0:
			var ei := MeshInstance3D.new()
			ei.name = "Ent%s" % mk.capitalize()
			ei.mesh = em
			ei.material_override = mats[mk]
			root.add_child(ei)
	# the district glass: emissive per-pane vertex colour on a plain material (no shader dependency)
	var glassm := StandardMaterial3D.new()
	glassm.vertex_color_use_as_albedo = true
	glassm.emission_enabled = true
	glassm.emission = Color(1.0, 0.75, 0.4)
	glassm.emission_energy_multiplier = 0.8
	match str(spec.get("lattice", "")):
		"voronoi":
			var vor: Dictionary = LatticeBuilder.voronoi(spec.get("size", Vector3(4.2, 5.2, 3.6)), {"reserved": ent.get("reserved", [])})
			var vm := MeshInstance3D.new()
			vm.name = "VoronoiMembrane"
			vm.mesh = vor["frame"]
			vm.material_override = _tinted_tile_material("facility_metal", Color(0.72, 0.70, 0.66))
			vm.visibility_range_end = float(vor.get("lod_switch", 30.0))
			vm.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			root.add_child(vm)
			for fd in (vor["faces"] as Array):
				var f := fd as Dictionary
				var quad := MeshInstance3D.new()
				quad.name = "VoronoiFar"
				var qm := QuadMesh.new()
				qm.size = Vector2(float(f["w"]), float(f["h"]))
				quad.mesh = qm
				var fm := StandardMaterial3D.new()
				fm.albedo_texture = f["tex"]
				fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				fm.alpha_scissor_threshold = 0.4
				quad.material_override = fm
				var n3 := f["n"] as Vector3
				quad.transform = Transform3D(Basis(f["u"] as Vector3, Vector3.UP, n3), (f["c"] as Vector3) + n3 * 0.06)
				quad.visibility_range_begin = float(vor.get("lod_switch", 30.0))
				quad.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				root.add_child(quad)
		"honeyframe":
			var ov := {"reserved": ent.get("reserved", [])}
			var lov: Dictionary = spec.get("lattice_overrides", {})
			for lk in lov.keys():
				ov[lk] = lov[lk]
			var built: Dictionary = LatticeBuilder.honeyframe_tiered(spec, ov) if int(spec.get("tiers", 1)) > 1 \
				else LatticeBuilder.honeyframe(spec.get("size", Vector3(4.5, 8.0, 5.5)), ov)
			for pair in [["frame", null], ["glass", glassm]]:
				var mm: Variant = built.get(str((pair as Array)[0]))
				if mm == null or (mm as ArrayMesh).get_surface_count() == 0:
					continue
				var mi2 := MeshInstance3D.new()
				mi2.name = "Honey%s" % str((pair as Array)[0]).capitalize()
				mi2.mesh = mm
				mi2.material_override = (pair as Array)[1] if (pair as Array)[1] != null else _tinted_tile_material("facility_metal", Color(0.72, 0.69, 0.58))
				root.add_child(mi2)
	# the district's survey-driven detail passes (flumes, arms, canopies, balconies, roots...):
	# the landmark is a PLAYABLE piece of the level, not a bald massing
	match str(spec.get("composite", "")):
		"plumbing_lobed":
			_add_plumbing_details(root, spec)
		"hypelines_mound":
			_add_hypelines_details(root, spec)
		"canopy_piers":
			_add_cleanstreets_details(root, spec)
		"greenfields_stack":
			_add_greenfields_details(root, spec)
		"ancourage_domes":
			_add_ancourage_details(root, spec)
		"beacon_domed":
			_add_beacon_details(root, spec)
		"bulwark_towers":
			_add_bulwark_details(root, spec)
		"zone3_split":
			_add_zone3_details(root, spec)
		"watchtower_tiers":
			_add_watchtower_details(root, spec)
	if str(spec.get("kind", "")) == "honeycomb_cooperative":
		_add_honeycomb_details(root, spec)
	if str(spec.get("composite", "")) == "open_files_awnings":
		_add_open_files_details(root, spec)
	if str(spec.get("composite", "")) == "aghora_domed":
		_add_aghora_exchange_details(root, spec)
	if str(spec.get("kind", "")) == "aghora_stack":
		_add_aghora_stack_details(root, spec)
	if str(spec.get("kind", "")) == "nutech_facility":
		_add_nutech_details(root, spec)
	if str(spec.get("kind", "")) == "facility_checkpoint":
		_add_facility_checkpoint_details(root, spec)
	if InfrastructureBuilderScript.is_infrastructure(spec):
		_add_infrastructure_details(root, spec, BuildingSurvey.from_spec(spec))

## Shared by live procedural fragments and the architecture showcase/bake. Material roles are kept
## separate so the portable atlas preserves readable construction layers and service-flow lights.
func _add_infrastructure_details(root: Node3D, spec: Dictionary, survey: BuildingSurvey) -> void:
	var built: Dictionary = InfrastructureBuilderScript.build(spec, survey)
	_add_lattice_mesh(root, "InfraMetal", built.get("metal"),
		_tinted_tile_material("facility_metal", Color(0.46, 0.50, 0.47)))
	_add_lattice_mesh(root, "InfraRust", built.get("rust"),
		_tinted_tile_material("rust_iron", Color(0.48, 0.25, 0.14)))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.055, 0.065, 0.07)
	dark.roughness = 0.94
	_add_lattice_mesh(root, "InfraDark", built.get("dark"), dark)
	var input_mat := StandardMaterial3D.new()
	input_mat.albedo_color = Color(0.10, 0.24, 0.31)
	input_mat.emission_enabled = true
	input_mat.emission = Color(0.42, 0.72, 0.95)
	input_mat.emission_energy_multiplier = 2.0
	_add_lattice_mesh(root, "InfraInputs", built.get("input_glow"), input_mat)
	var output_mat := StandardMaterial3D.new()
	output_mat.albedo_color = Color(0.08, 0.28, 0.15)
	output_mat.emission_enabled = true
	output_mat.emission = Color(0.36, 0.91, 0.50)
	output_mat.emission_energy_multiplier = 2.0
	_add_lattice_mesh(root, "InfraOutputs", built.get("output_glow"), output_mat)

func _spawn_lathe_building(lp: Dictionary) -> void:
	var profile: Dictionary = LatheBuilderScript.make_profile(lp)
	var built: Dictionary = LatheBuilderScript.build(profile)
	if built["mesh"] == null:
		return
	var mesh := built["mesh"] as ArrayMesh
	mesh.surface_set_material(0, _tinted_tile_material(str(lp.get("tile", "facility_metal")),
		_col(lp, "color", Color(0.4, 0.4, 0.42))))
	var mi := MeshInstance3D.new()
	mi.name = "LatheTower"
	mi.mesh = mesh
	add_child(mi)
	if bool(lp.get("coil", false)):
		var coil: Dictionary = SdfMesherScript.build(LatheBuilderScript.coil_prims(lp), 0.2)
		if coil["mesh"] != null:
			var ci := MeshInstance3D.new()
			ci.name = "LatheCoil"
			ci.mesh = coil["mesh"]
			ci.material_override = _tinted_tile_material("rust_iron",
				_col(lp, "color", Color(0.35, 0.25, 0.18)).lightened(0.12))
			add_child(ci)

# tile+tint -> material, cached: a district can carry hundreds of textured boxes but only a handful
# of (tile, palette-drift) combinations after quantising the tint.
var _tile_mat_cache: Dictionary = {}

## Pixel-art tile with PERLIN-VARIED DENSITY (tile_grime.gdshader) — the building/hero material.
## The tile is object-space locked (no swim), grime/rust/brightness ride a WORLD-space noise field so
## the tiling stops reading uniform and varies per facade + per building. Tint is LIFTED (the tile
## albedo is mid-dark) and quantised for cache hits while the Perlin palette drift stays visible.
func _tinted_tile_material(tile_name: String, tint: Color) -> ShaderMaterial:
	var lifted := Color(minf(tint.r * 2.6, 1.2), minf(tint.g * 2.6, 1.2), minf(tint.b * 2.6, 1.2))
	var key := "%s:%d,%d,%d" % [tile_name, int(lifted.r * 24.0), int(lifted.g * 24.0), int(lifted.b * 24.0)]
	if _tile_mat_cache.has(key):
		return _tile_mat_cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = GRIME_SHADER
	# Prefer the surface's 8x8 VARIATION ATLAS (per-metre hand-varied cells); the
	# single tile remains the fallback for stems without one.
	var atlas_path := "res://resources/textures/atlases/" + tile_name + "_var8.png"
	var tex = load(atlas_path) if ResourceLoader.exists(atlas_path) else null
	if tex != null:
		mat.set_shader_parameter("atlas_cells", 8.0)
	else:
		tex = load(TILE_DIR + tile_name + ".png")
	if tex != null:
		mat.set_shader_parameter("tile_tex", tex)
	mat.set_shader_parameter("tint", lifted)
	# a rusty tile already carries decay — soften the shader's extra rust so it doesn't double up
	if tile_name == "rust_iron":
		mat.set_shader_parameter("rust_amount", 0.3)
		mat.set_shader_parameter("grime_amount", 0.55)
	_tile_mat_cache[key] = mat
	return mat

## Instance a placed model (a static modeled prop). The level MESH (the whole environment) goes through
## get_environment_model() instead — the host loads + warps that.
func _instance_mesh(spec: Dictionary) -> void:
	var path := str(spec.get("path", ""))
	if path == "":
		return
	var packed := load(path)
	if packed == null or not (packed is PackedScene):
		push_warning("DataFragmentChunk: mesh '%s' is not a loadable PackedScene" % path)
		return
	var node := (packed as PackedScene).instantiate()
	if node is Node3D:
		var n3 := node as Node3D
		var r := _v3(spec, "rot")
		n3.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))), _v3(spec, "pos"))
		var sc := _v3(spec, "scale", Vector3.ONE)
		if sc != Vector3.ONE:
			n3.scale = sc
	add_child(node)

## Declared shelter rects -> GameState shelter regions (sanctuary from detection/strikes + the revive
## watch's ground). Data, not behavior: the fragment says WHERE is safe; the engine enforces it.
func _apply_shelters() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for sh in fragment.shelters:
		var mn: Vector2 = sh.get("min", Vector2.ZERO)
		var mx: Vector2 = sh.get("max", Vector2.ZERO)
		gs.add_shelter_region(mn, mx)

# --- Object spawning: one branch per object `type`. This list is the .tres authoring contract. ---

func _spawn_object(spec: Dictionary) -> void:
	var gs = _get_game_state()
	match str(spec.get("type", "")):
		"weak_wall":
			# {pos:Vector3 (wall foot), n:Vector3 (outward), kill_min:Vector3, kill_max:Vector3}
			# A structural WEAK POINT consumed from a landmark's gameplay anchors: pry the strut and
			# the facade crumbles on a scheduled beat — enemies inside the kill zone die, rubble
			# remains. The generated-district cousin of the set-piece showcase's bay D.
			_spawn_weak_wall(spec)
		"flure":
			# {pos:Vector3, targets:Array[String], attract:float, radius:float, color:Color}
			var fl := Flure.new()
			fl.name = _name(spec, "Flure")
			fl.configure(gs, _v3(spec, "pos"), _str_arr(spec, "targets"),
				_f(spec, "attract", 32.0), _f(spec, "radius", 1.6), _col(spec, "color", Color(0.95, 0.78, 0.2)))
			if spec.has("settle"):
				fl.settle_pos = _v3(spec, "settle")
			fl.lure_duration = _f(spec, "duration", fl.lure_duration)
			if _f(spec, "dwell", 0.0) > 0.0:
				fl.interactable_type = Interactable.InteractableType.TIMED_ACTION
				fl.dwell_time = _f(spec, "dwell", 2.0)
			if spec.has("one_shot"):
				fl.one_shot = bool(spec["one_shot"])
			fl.set_enemy_resolver(_enemy_by_id)
			add_child(fl)
			_register_interactable(fl)
			_flures.append(fl)
		"portal_pad":
			# {pos:Vector3, dest:Vector3, radius:float, color:Color}
			var p := PortalPad.new()
			p.name = _name(spec, "PortalPad")
			p.configure(gs, _v3(spec, "pos"), _v3(spec, "dest"), _f(spec, "radius", 1.2),
				_col(spec, "color", Color(0.55, 0.42, 0.98)))
			p.set_group_provider(_selected_party_ids)
			add_child(p)
			_register_interactable(p)
			_portals.append(p)
		"capbage":
			# {pos:Vector3, radius:float}
			var cap := Capbage.new()
			cap.name = _name(spec, "Capbage")
			cap.configure(gs, _v3(spec, "pos"), _f(spec, "radius", 1.4))
			add_child(cap)
			_register_interactable(cap)
			_capbages.append(cap)
		"channel":
			# {x:float, half:float, z_half:float, period:float, dur:float, phase:float, tag:String}
			var ch := Channel.new()
			ch.name = _name(spec, "Channel")
			ch.configure(_f(spec, "x", 0.0), _f(spec, "half", 1.25), _f(spec, "z_half", 5.0),
				_f(spec, "period", 3.0), _f(spec, "dur", 1.6), _f(spec, "phase", 0.0),
				str(spec.get("tag", "ch_%d" % _channels.size())))
			add_child(ch)
			_channels.append(ch)
		"flora_light":
			# {pos:Vector3, opts:Dictionary}
			var bloom := FloraLight.new()
			bloom.name = _name(spec, "FloraLight")
			bloom.position = _v3(spec, "pos")
			bloom.configure(spec.get("opts", {}) as Dictionary)
			add_child(bloom)
			_flora.append(bloom)
		"candid_zone":
			# {pos:Vector3, half:Vector2, dot:float} — biofilm ground: scan-blind (CONCEAL_FULL) + hp
			# drain while standing in it. The risk-inversion floor (ECOLOGY_COMBOS Card 2).
			var cz := CandidZone.new()
			cz.name = _name(spec, "CandidZone")
			var half = spec.get("half", Vector2(3.0, 3.0))
			cz.configure(_v3(spec, "pos"), half if half is Vector2 else Vector2(3.0, 3.0), _f(spec, "dot", 4.0))
			add_child(cz)
			_candid_zones.append(cz)
		"hushbloom":
			# {pos:Vector3, opts?:Dictionary} — the thigmonastic stun flower (flora_taxonomy): any
			# body in its trigger radius fires the burst (freeze enemies, SEAL portals); pickable.
			var hb := Hushbloom.new()
			hb.name = _name(spec, "Hushbloom")
			hb.configure(_get_game_state(), _v3(spec, "pos"), spec.get("opts", {}) as Dictionary)
			hb.set_enemy_provider(func() -> Array: return _enemies)
			hb.set_portal_provider(func() -> Array: return _portals)
			add_child(hb)
			_register_interactable(hb)
			_hushblooms.append(hb)
		"scarpet":
			# {pos:Vector3, radius:float} — a MEDIUM-tier hide mat (the loader's concealment pass reads it)
			var mat := Scarpet.new()
			mat.name = _name(spec, "Scarpet")
			mat.configure(_v3(spec, "pos"), _f(spec, "radius", 1.65))
			add_child(mat)
			_scarpets.append(mat)
		"decorative_flora":
			# {species:String, pos:Vector3, opts?:Dictionary} — ornamental invasive
			# (docs/DECORATIVE_FLORA.md): pure scenery with no interaction or stat value.
			var deco := DecorativeFlora.new()
			deco.name = _name(spec, "Deco")
			deco.configure(str(spec.get("species", "curbelia")), _v3(spec, "pos"),
				spec.get("opts", {}) as Dictionary)
			add_child(deco)
			_decoratives.append(deco)
		"spike_strip":
			# {pos:Vector3, half:Vector2, dot:float} — anti-loiter studs (hostile architecture,
			# SET_PIECES 21): a symmetric damage floor — ANYONE standing on it drains hp, so
			# lure/push enemies across it to hurt them (and budget your own crossings).
			var strip := SpikeStrip.new()
			strip.name = _name(spec, "SpikeStrip")
			var shalf = spec.get("half", Vector2(2.0, 0.6))
			strip.configure(_v3(spec, "pos"), shalf if shalf is Vector2 else Vector2(2.0, 0.6),
				_f(spec, "dot", 6.0))
			add_child(strip)
			_spike_strips.append(strip)
		"infrastructure_operation":
			# A generated typed service exchange: two explicit verbs, two spatial cause/effect markers,
			# and a nearby field whose cost/cover state actually changes on completion.
			_spawn_infrastructure_operation(spec)
		"exit_shelter":
			# {pos:Vector3, radius:float, label:String, color:Color} — the fragment's win pad: rest -> complete
			_spawn_exit_shelter(spec)
		"enemy":
			# {id:String, pos:Vector3, speed:float, detect:float, targets:Array[String], roam?:{radius:float}, patrol?:Array}
			_spawn_enemy(spec, gs)
		"belt":
			_spawn_belt(spec)
		"silo":
			_spawn_silo(spec)
		"sump":
			_spawn_sump(spec)
		"crawl":
			# a data-declared CrawlTunnel (the gangway grammar): authored squeeze path, optional
			# exit_level so a deck gangway delivers you to the ground plane
			var cr := CrawlTunnel.new()
			cr.name = str(spec.get("name", "CrawlTunnel"))
			cr.description = str(spec.get("desc", "Squeeze through"))
			cr.tutorial_label = str(spec.get("label", "CRAWL"))
			var cr_wps: Array = []
			for wp_v in (spec.get("waypoints", []) as Array):
				cr_wps.append(wp_v if wp_v is Vector3 else _v3({"p": wp_v}, "p"))
			cr.configure(_get_game_state(), _v3(spec, "pos"), cr_wps,
				_f(spec, "radius", 1.4), _f(spec, "speed", 1.1))
			cr.exit_level = int(spec.get("exit_level", -1))
			cr.set_group_provider(_selected_party_ids)
			add_child(cr)
			_register_interactable(cr)
			var cr_stub := _add_box(cr, Vector3(0.0, 0.3, 0.0), Vector3(0.45, 0.6, 0.45),
				Color(0.11, 0.12, 0.13))
			_outline_interactable_child(cr, cr_stub, cr.name, 1.5)
		"rising_water_crossing", "basin":
			# {tag, pos:Vector3, plane_size:Vector2, floor_min/floor_max:Vector2 (world XZ),
			#  safe_cells/float_cells:[[x,z]...], float_level, rota:[{level,dwell}...],
			#  telegraph_lead, water_y/float_y:[3], outfall:Vector3,
			#  recovery_cells:[[x,z]...], recovery_level:int, sweep:{...},
			#  dwellers:[{id,refuge,home,radius}...]} — the bowl-scale water rota
			#  (docs/BALANCING_BASIN.md); BasinWater owns states + catches + eviction.
			var report: Dictionary = RisingWaterCrossingSpecScript.validate(
				spec, fragment.party_ids.size())
			if not bool(report.get("valid", false)):
				push_error("Invalid rising-water crossing '%s': %s" % [
					_name(spec, "RisingWaterCrossing"), str(report.get("errors", []))])
				return
			var normalized := report.get("normalized", {}) as Dictionary
			var basin = RisingWaterCrossingScript.new()
			basin.name = _name(spec, "Basin")
			basin.configure(gs, normalized)
			basin.set_party_ids(Array(fragment.party_ids))
			basin.set_enemy_resolver(_enemy_by_id)
			basin.state_changed.connect(_on_basin_navigation_state_changed)
			add_child(basin)
			_basins.append(basin)
		"rota_chart":
			# {pos:Vector3, basin_tag:String, radius?, label?, desc?} — the fill schedule as a
			# physical info surface (the Basin's FORESIGHT branch); reading it reports the rota
			# from the basin's authoritative record via a host note.
			var chart := RotaChart.new()
			chart.name = _name(spec, "RotaChart")
			chart.configure(gs, spec)
			chart.chart_read.connect(func(text: String): _show_note(text, 4.0))
			add_child(chart)
			_register_interactable(chart)
		"crossing_assist":
			# {pos:Vector3, lip:Vector3, dest:Vector3, basin_tag:String, target_state:int,
			#  stamina_cost:float, cooldown:float, required_character?, radius?, label?, desc?}
			# — the priced perfect-launch read (the Basin's RESOURCE branch): hold the group at
			# the lip, launch on the exact commit of the target water state.
			var assist := CrossingAssist.new()
			assist.name = _name(spec, "CrossingAssist")
			assist.configure(gs, spec)
			assist.set_group_provider(_selected_party_ids)
			assist.set_party_provider(_playable_party_ids)
			assist.set_basin_resolver(_basin_by_tag)
			assist.read_refused.connect(func(reason: String):
				# A correction is state, not a toast: retain it until the next
				# explicit assist attempt replaces it with staging/armed feedback.
				_show_note(_crossing_assist_refusal_note(reason), 0.0))
			assist.staging_started.connect(func():
				# A zero-duration preview note is persistent until the next explicit state cue.
				_show_note("CROSSING STAGING // the full group is moving to the safe hold line.", 0.0))
			assist.read_logged.connect(func(_launch_tick: float):
				_show_note("CROSSING ARMED // the staged group launches on the next MID beat.", 0.0))
			assist.crossing_launched.connect(func():
				_show_note("CROSSING LAUNCHED // the full group is moving to the south shelter.", 3.0))
			add_child(assist)
			_register_interactable(assist)
			_assists.append(assist)
		"marker":
			# {pos:Vector3, size:Vector3, color:Color, energy:float, label:String}
			var color := _col(spec, "color", Color(0.3, 0.7, 0.55))
			_add_box(self, _v3(spec, "pos") - Vector3(0, 0.18, 0), _v3(spec, "size", Vector3(1, 0.4, 1)),
				color * 0.4, color, _f(spec, "energy", 1.0))
			var lbl := str(spec.get("label", ""))
			if lbl != "":
				_add_label(self, lbl, _v3(spec, "pos") + Vector3(0, 1.4, 0), color)
		_:
			push_warning("DataFragmentChunk: unknown object type '%s'" % str(spec.get("type", "")))


func _spawn_infrastructure_operation(spec: Dictionary) -> void:
	var built := _add_infrastructure_operation(spec)
	if built.is_empty():
		return
	var operation = built.get("operation")
	_infrastructure_operations.append(operation)
	_infrastructure_fields.append(built.get("field"))
	if is_instance_valid(operation) and operation.has_method("set_authority_publisher"):
		operation.call(
			"set_authority_publisher",
			Callable(self, "_publish_fragment_authority")
		)


func _spawn_enemy(spec: Dictionary, gs) -> void:
	if gs == null:
		return
	var enemy := (Naturalizer.new() as Enemy) if str(spec.get("class", "")) == "naturalizer" else EnemyScript.new()
	var eid := str(spec.get("id", "enemy_%d" % _enemies.size()))
	var already_registered: bool = bool(gs.characters.has(eid))
	enemy.name = "Enemy_%s" % eid
	enemy.position = gs.get_position(eid) if already_registered else _v3(spec, "pos")
	enemy.move_speed = _f(spec, "speed", 2.4)
	enemy.detection_range = _f(spec, "detect", 4.0)
	enemy._detection_targets.assign(_str_arr(spec, "targets"))
	add_child(enemy)
	enemy.char_id = eid
	enemy.game_state = gs
	if not already_registered:
		gs.register_character(eid, enemy.position, enemy.move_speed, {"detection_range": float(enemy.detection_range)})
	if not already_registered and int(spec.get("level", 0)) > 0 and gs.has_method("set_character_level"):
		# a HIGH-LINE enemy: lives on an upper grid floor (deck sentries); same-floor moves ride
		# its level's plane, and the detection vertical band keeps it blind to the ground below
		gs.set_character_level(eid, int(spec["level"]))
	if not already_registered and bool(spec.get("coop_exempt", false)) and gs.has_method("set_coop_exempt"):
		gs.set_coop_exempt(eid)
	if enemy.has_method("activate"):
		enemy.activate()
	_enemy_posts[eid] = enemy.position
	if enemy.has_signal("target_spotted"):
		enemy.target_spotted.connect(_on_fragment_target_spotted)
	if spec.has("roam") and enemy.has_method("set_roam"):
		var roam: Dictionary = spec["roam"]
		enemy.set_roam(enemy.position, _f(roam, "radius", 4.0))
	elif spec.has("patrol") and enemy.has_method("set_patrol"):
		var pts: Array[Vector3] = []
		for p in (spec["patrol"] as Array):
			pts.append(p if p is Vector3 else _v3({"p": p}, "p"))
		enemy.set_patrol(pts)
	_enemies.append(enemy)

# --- Scheduler-driven cadence (channels) ---

func _process(delta: float) -> void:
	_update(delta)

func headless_process(delta: float) -> void:
	_update(delta)

func _update(_delta: float) -> void:
	_ensure_scheduled()
	_sync_weak_wall_presenters()

## The LOADER owns the hide-tier pass: Capbage = FULL beats Scarpet = MEDIUM beats exposed, from each
## member's REAL position on an explicit fixed simulation cadence. Chunks never re-implement hide
## logic, and neither render frames nor headless presenter polling are allowed to commit this truth.
func _update_shared_concealment() -> void:
	if fragment == null or (_capbages.is_empty() and _scarpets.is_empty() and _candid_zones.is_empty() \
			and _infrastructure_fields.is_empty()):
		return
	var gs = _get_game_state()
	if gs == null:
		return
	for cid_v in fragment.party_ids:
		var cid := str(cid_v)
		if not gs.characters.has(cid):
			continue
		_update_character_shared_concealment(cid)


func _update_character_shared_concealment(cid: String) -> void:
	var gs = _get_game_state()
	if gs == null or not gs.characters.has(cid):
		return
	var pos: Vector3 = gs.get_position(cid)
	var tier: int = GameState.CONCEAL_NONE
	for cap in _capbages:
		if is_instance_valid(cap) and cap.conceals(pos):
			tier = GameState.CONCEAL_FULL
			break
	if tier == GameState.CONCEAL_NONE:
		for cz in _candid_zones:
			if is_instance_valid(cz) and cz.covers(pos):
				tier = GameState.CONCEAL_FULL
				break
	if tier == GameState.CONCEAL_NONE:
		for mat in _scarpets:
			if is_instance_valid(mat) and mat.conceals(pos):
				tier = GameState.CONCEAL_MEDIUM
				break
	if tier == GameState.CONCEAL_NONE:
		for service_field in _infrastructure_fields:
			if is_instance_valid(service_field) and service_field.conceals(pos):
				tier = GameState.CONCEAL_FULL
				break
	gs.set_character_concealment(cid, tier)

## The fragment's win pad: a click-gated INSPECTION interactable; resting there completes the fragment.
func _spawn_exit_shelter(spec: Dictionary) -> void:
	var p := _v3(spec, "pos")
	var color := _col(spec, "color", Color(0.3, 0.7, 0.45))
	var pad_w: float = _f(spec, "radius", 1.2) * 2.0
	var pad := _add_box(self, p + Vector3(0, 0.1, 0), Vector3(pad_w, 0.2, pad_w), Color(0.2, 0.28, 0.22), color, 0.5, _name(spec, "ExitShelterPad") + "Pad")
	var label := str(spec.get("label", "SHELTER"))
	if label != "":
		_add_label(self, label, p + Vector3(0, 2.0, 0), Color(0.6, 0.9, 0.65))
	var it := _add_object_interactable(self, _name(spec, "ExitShelter"), "Shelter", p + Vector3(0, 0.1, 0),
		"REST PARTY", [pad], "", 0.0, false, _f(spec, "radius", 1.2), Interactable.InteractableType.INSPECTION)
	# Keep the exact authored exit region on the control. GameState.is_at_shelter() answers whether a
	# body is in any sanctuary; completion must prove every configured party member reached THIS one.
	var shalf := maxf(_f(spec, "radius", 1.2) * 1.5, 1.8)
	it.set_meta("exit_shelter_center", p)
	it.set_meta("exit_shelter_half_size", Vector2(shalf, shalf))
	_publish_exit_shelter_navigation_region(it, p, Vector2(shalf, shalf))
	it.set_interaction_route_preflight(
		_preflight_exit_shelter_route.bind(it),
		_present_exit_shelter_route_refusal.bind(it))
	it.set_pre_trigger_validator(_validate_exit_shelter_trigger.bind(it))
	it.interacted.connect(_on_exit_shelter_rested.bind(it))
	it.interaction_rejected.connect(
		_on_exit_shelter_interaction_rejected.bind(it))
	_exit_shelters.append(it)
	_exit_rest_trigger_consumed[str(it.get("data_id"))] = maxi(
		0, _fragment_source_trigger_count(it))
	# A pad the game CALLS a shelter must BE one: register the sanctuary region around it — the
	# detection gate, the strike gate, and the revive watch all read gs shelter regions, and a
	# label alone registers nothing (the attacked-in-the-shelter report, 2026-07-12).
	var gs = _get_game_state()
	if gs != null and gs.has_method("add_shelter_region"):
		gs.add_shelter_region(Vector2(p.x - shalf, p.z - shalf), Vector2(p.x + shalf, p.z + shalf))


## Publish the exact graph vertices from which this source can be serviced.  The
## shelter rectangle may overlap another stacked floor in XZ, but that lower
## vertex is not the balcony shelter and must never satisfy arrival or rest.
## Restrict the accepted graph region to the source's real interaction reach so
## standing in a far corner does not bypass the visible pad itself.
func _publish_exit_shelter_navigation_region(
		it: Node, center: Vector3, half_size: Vector2
	) -> void:
	var gs = _get_game_state()
	if not is_instance_valid(it):
		return
	# Republish is replace-not-merge. A host that temporarily has no graph, or an
	# authored shelter with no valid vertices, must not retain a stale formation
	# target from an earlier walkability revision.
	it.remove_meta("interaction_navigation_region")
	it.remove_meta("rally_formation_region")
	it.set_meta("exit_shelter_level", 0)
	if gs == null or gs.grid == null:
		return
	var grid = gs.grid
	var shelter_level := int(grid.level_for_y(center.y)) \
		if grid.has_method("level_for_y") else 0
	it.set_meta("exit_shelter_level", shelter_level)
	var source_cell: Vector2i = grid.world_to_grid(center)
	var graph_cell_size := maxf(0.001, float(grid.cell_size))
	var search_x := ceili(half_size.x / graph_cell_size) + 1
	var search_z := ceili(half_size.y / graph_cell_size) + 1
	var source_reach := float(it.get("interaction_radius")) \
		+ WEAK_WALL_POSITION_TOLERANCE
	var region_vertices: Array = []
	var approach_vertex: Dictionary = {}
	var approach_distance := INF
	for dz in range(-search_z, search_z + 1):
		for dx in range(-search_x, search_x + 1):
			var cell := source_cell + Vector2i(dx, dz)
			if not grid.is_in_bounds(cell.x, cell.y) \
					or not grid.is_walkable(cell.x, cell.y, {}, {}, shelter_level):
				continue
			var graph_position: Vector3 = grid.grid_to_world(cell, shelter_level)
			if absf(graph_position.x - center.x) > half_size.x + 0.0001 \
					or absf(graph_position.z - center.z) > half_size.y + 0.0001:
				continue
			var distance := Vector2(
				graph_position.x - center.x,
				graph_position.z - center.z
			).length()
			if distance > source_reach + 0.0001:
				continue
			var vertex := {"cell": cell, "level": shelter_level}
			region_vertices.append(vertex)
			if cell == source_cell:
				approach_vertex = vertex.duplicate(true)
				approach_distance = -1.0
			elif approach_distance >= 0.0 \
					and (approach_vertex.is_empty() \
						or distance < approach_distance - 0.0001):
				approach_vertex = vertex.duplicate(true)
				approach_distance = distance
	if region_vertices.is_empty():
		return
	var region := {
		"contract_id": EXIT_SHELTER_NAVIGATION_REGION_CONTRACT,
		"source_data": GameEvent.v3_to_arr(center),
		"shelter_half_size": [half_size.x, half_size.y],
		"interaction_radius": float(it.get("interaction_radius")),
		"acceptance_radius": source_reach,
		"authored_level": shelter_level,
		"arrival_policy": "primary_then_nearest",
		"approach_vertex": approach_vertex,
		"region_vertices": region_vertices,
	}
	if grid.has_method("get_path_walkability_revision"):
		region["graph_revision"] = int(grid.get_path_walkability_revision())
	it.set_meta("interaction_navigation_region", region)
	if not _exit_shelter_navigation_region_valid(it):
		it.remove_meta("interaction_navigation_region")
		return

	# The visible shelter pad is also a semantic Rally destination. REST keeps the
	# strict source-reach service vertices above, but a formation needs every
	# connected walkable vertex inside the authored shelter rectangle so the whole
	# roster can park there without enlarging the interaction radius or sanctuary.
	# The wire stays JSON-portable so GameState can log/replay it without scene
	# nodes or Vector2i values. Canonical ordering makes the formation deterministic.
	var approach_cell := approach_vertex.get("cell", Vector2i.ZERO) as Vector2i
	var formation_allowed := {}
	for dz in range(-search_z, search_z + 1):
		for dx in range(-search_x, search_x + 1):
			var formation_cell := source_cell + Vector2i(dx, dz)
			if not grid.is_in_bounds(formation_cell.x, formation_cell.y) \
					or not grid.is_walkable(
						formation_cell.x, formation_cell.y, {}, {}, shelter_level):
				continue
			var formation_position: Vector3 = grid.grid_to_world(
				formation_cell, shelter_level)
			if absf(formation_position.x - center.x) > half_size.x + 0.0001 \
					or absf(formation_position.z - center.z) > half_size.y + 0.0001:
				continue
			formation_allowed[formation_cell] = true
	if not formation_allowed.has(approach_cell):
		return
	var rally_cells: Array[Vector2i] = []
	for rally_cell_v in formation_allowed.keys():
		var rally_cell := rally_cell_v as Vector2i
		var connected_path: Array = grid.find_path(
			approach_cell, rally_cell, {}, false, {}, {},
			shelter_level, formation_allowed)
		if connected_path.is_empty():
			continue
		rally_cells.append(rally_cell)
	rally_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.y == b.y else a.y < b.y)
	var portable_cells: Array = []
	for rally_cell in rally_cells:
		portable_cells.append([rally_cell.x, rally_cell.y])
	var graph_revision := int(grid.get_path_walkability_revision()) \
		if grid.has_method("get_path_walkability_revision") else 0
	it.set_meta("rally_formation_region", {
		"contract_id": RALLY_FORMATION_REGION_CONTRACT,
		"semantic_id": str(it.get("data_id")),
		"label": "SHELTER // RALLY PARTY HERE",
		"authored_level": shelter_level,
		"graph_revision": graph_revision,
		"approach_cell": [approach_cell.x, approach_cell.y],
		"cells": portable_cells,
	})
	if not _exit_shelter_rally_formation_region_valid(it):
		it.remove_meta("rally_formation_region")


func _on_exit_shelter_rested(it: Node = null) -> bool:
	if _phase == "complete" or _exit_rest_phase == "committing" \
			or not _exit_shelter_source_receipt_pending(it):
		return false
	_exit_rest_trigger_consumed[str(it.get("data_id"))] = _fragment_source_trigger_count(it)
	_publish_fragment_authority()
	_sync_host_clock_to_game_state()
	var rest_outcome := _preflight_canonical_exit_shelter_rest(it)
	if not bool(rest_outcome.get("complete", false)):
		var blocked: Array = rest_outcome.get("blocked", [])
		var reason := str(blocked[0]) if not blocked.is_empty() else "the party cannot settle yet"
		_show_note("SHELTER WAITING // %s." % reason, 2.6)
		_apply_exit_shelter_presenters()
		return false
	var rest_members: Array = rest_outcome.get("rest_members", []) as Array
	if rest_members.is_empty():
		_complete_exit_shelter_rest(rest_outcome, true)
		_show_note("The full ready party secured the shelter. No recovery charge was needed.", 2.8)
		return true
	var gs = _get_game_state()
	_exit_rest_phase = "committing"
	_phase = "committing"
	_exit_rest_shelter_name = str(it.name)
	_exit_rest_members.assign(rest_members)
	_exit_rest_commit_tick = _get_scheduler_tick()
	_exit_rest_commit_day = gs.get_game_day()
	_exit_rest_before_atp = (
		rest_outcome.get("before_atp", {}) as Dictionary).duplicate(true)
	_apply_exit_shelter_presenters()
	_publish_fragment_authority()
	if not bool(gs.command_party_rest(_exit_rest_members)):
		_retract_exit_rest_commit()
		_show_note("SHELTER WAITING // the atomic party rest was rejected.", 2.6)
		return false
	_complete_exit_shelter_rest(rest_outcome, true)
	_show_note("The full party settled in; canonical shelter recovery has started.", 2.8)
	return true


func _validate_exit_shelter_trigger(source: Node, actor: String, expected_source: Node) -> bool:
	if not (source == expected_source and _exit_shelters.has(source) \
		and _phase != "complete" and _exit_rest_phase != "committing" \
		and _exit_shelter_navigation_region_valid(source) \
		and _fragment_actor_ready_at_source(source, actor)):
		return false
	return bool(_preflight_canonical_exit_shelter_rest(source).get(
		"complete", false))


## REST PARTY is one collective command.  Refuse before the interaction
## controller picks a route when the full roster is not already settled, so a
## visible click cannot silently reinterpret the verb as a singleton move.
func _preflight_exit_shelter_route(
		source: Node, _actor: String, expected_source: Node
	) -> Dictionary:
	if not is_instance_valid(source) or source != expected_source \
			or not _exit_shelters.has(source):
		return {
			"accepted": false,
			"code": "exit_shelter_unavailable",
			"message": "That shelter is unavailable.",
			"cue": "SHELTER WAITING // SHELTER UNAVAILABLE",
		}
	if not _exit_shelter_navigation_region_valid(source):
		return {
			"accepted": false,
			"code": "invalid_route_preflight",
			"message": "The shelter route contract is unavailable.",
			"cue": "RESOLVE FIRST // ROUTE CONTRACT UNAVAILABLE",
		}
	var outcome := _preflight_canonical_exit_shelter_rest(source)
	if bool(outcome.get("complete", false)):
		return {"accepted": true, "code": ""}
	var blocked: Array = outcome.get("blocked", []) as Array
	var reason := str(blocked[0]) if not blocked.is_empty() \
		else "the party cannot settle yet"
	return {
		"accepted": false,
		"code": "exit_shelter_waiting",
		"message": reason,
		"cue": "SHELTER WAITING // %s." % reason,
	}


## Validate the exact typed contract before either route or trigger authority can
## proceed.  A missing/stale metadata blob must not fall back to an approximate
## position on a stacked map: that would recreate the below-the-balcony bug.
func _exit_shelter_navigation_region_valid(source: Node) -> bool:
	if not is_instance_valid(source) \
			or not source.has_meta("interaction_navigation_region"):
		return false
	var region_v: Variant = source.get_meta("interaction_navigation_region")
	if not (region_v is Dictionary):
		return false
	var region := region_v as Dictionary
	var gs = _get_game_state()
	if gs == null or gs.grid == null \
			or str(region.get("contract_id", "")) \
				!= EXIT_SHELTER_NAVIGATION_REGION_CONTRACT:
		return false
	var grid = gs.grid
	var expected_level := int(source.get_meta("exit_shelter_level", -1))
	if expected_level < 0 \
			or int(region.get("authored_level", -1)) != expected_level:
		return false
	var center_v: Variant = source.get_meta(
		"exit_shelter_center", Vector3.INF)
	var half_v: Variant = source.get_meta(
		"exit_shelter_half_size", Vector2.ZERO)
	var approach_v: Variant = region.get("approach_vertex", null)
	var vertices_v: Variant = region.get("region_vertices", null)
	if not (center_v is Vector3) or not (half_v is Vector2) \
			or not (approach_v is Dictionary) \
			or (approach_v as Dictionary).is_empty() \
			or not (vertices_v is Array) or (vertices_v as Array).is_empty():
		return false
	var approach := approach_v as Dictionary
	var approach_cell_v: Variant = approach.get("cell", null)
	var approach_level := int(approach.get("level", -1))
	if not (approach_cell_v is Vector2i) or approach_level != expected_level:
		return false
	var center := center_v as Vector3
	var half_size := half_v as Vector2
	var source_reach := float(source.get("interaction_radius")) \
		+ WEAK_WALL_POSITION_TOLERANCE
	if not is_equal_approx(
			float(region.get("acceptance_radius", -1.0)), source_reach):
		return false
	var approach_present := false
	for vertex_v in (vertices_v as Array):
		if not (vertex_v is Dictionary):
			return false
		var vertex := vertex_v as Dictionary
		var cell_v: Variant = vertex.get("cell", null)
		var level := int(vertex.get("level", -1))
		if not (cell_v is Vector2i) or level != expected_level:
			return false
		var cell := cell_v as Vector2i
		if not grid.is_in_bounds(cell.x, cell.y) \
				or not grid.is_walkable(cell.x, cell.y, {}, {}, level):
			return false
		var graph_position: Vector3 = grid.grid_to_world(cell, level)
		if absf(graph_position.x - center.x) > half_size.x + 0.0001 \
				or absf(graph_position.z - center.z) > half_size.y + 0.0001 \
				or Vector2(
					graph_position.x - center.x,
					graph_position.z - center.z
				).length() > source_reach + 0.0001:
			return false
		if cell == (approach_cell_v as Vector2i) and level == approach_level:
			approach_present = true
	return approach_present


## The Rally wire is a separate, wider formation contract over the same exact
## shelter rectangle and authored level. It remains fail-closed on stale graph
## revisions, malformed/non-canonical portable cells, insufficient capacity, or
## any vertex disconnected from the interaction approach within the region.
func _exit_shelter_rally_formation_region_valid(source: Node) -> bool:
	if not _exit_shelter_navigation_region_valid(source) \
			or not source.has_meta("rally_formation_region"):
		return false
	var rally_v: Variant = source.get_meta("rally_formation_region")
	if not (rally_v is Dictionary):
		return false
	var rally := rally_v as Dictionary
	var gs = _get_game_state()
	if gs == null or gs.grid == null or rally.size() != 7 \
			or str(rally.get("contract_id", "")) \
				!= RALLY_FORMATION_REGION_CONTRACT \
			or str(rally.get("semantic_id", "")) != str(source.get("data_id")) \
			or str(rally.get("label", "")) != "SHELTER // RALLY PARTY HERE":
		return false
	var grid = gs.grid
	var expected_level := int(source.get_meta("exit_shelter_level", -1))
	var current_revision := int(grid.get_path_walkability_revision()) \
		if grid.has_method("get_path_walkability_revision") else 0
	if expected_level < 0 \
			or int(rally.get("authored_level", -1)) != expected_level \
			or int(rally.get("graph_revision", -1)) != current_revision:
		return false
	var interaction := source.get_meta(
		"interaction_navigation_region", {}) as Dictionary
	var interaction_approach := interaction.get(
		"approach_vertex", {}) as Dictionary
	var approach_cell_v: Variant = interaction_approach.get("cell", null)
	var portable_approach_v: Variant = rally.get("approach_cell", null)
	if not (approach_cell_v is Vector2i) \
			or not (portable_approach_v is Array) \
			or (portable_approach_v as Array).size() != 2:
		return false
	var approach_cell := approach_cell_v as Vector2i
	if int((portable_approach_v as Array)[0]) != approach_cell.x \
			or int((portable_approach_v as Array)[1]) != approach_cell.y:
		return false
	var cells_v: Variant = rally.get("cells", null)
	if not (cells_v is Array):
		return false
	var required_capacity := maxi(
		1, fragment.party_ids.size() if fragment != null else 1)
	if (cells_v as Array).size() < required_capacity:
		return false
	var center_v: Variant = source.get_meta(
		"exit_shelter_center", Vector3.INF)
	var half_v: Variant = source.get_meta(
		"exit_shelter_half_size", Vector2.ZERO)
	if not (center_v is Vector3) or not (half_v is Vector2):
		return false
	var center := center_v as Vector3
	var half_size := half_v as Vector2
	var cells: Array[Vector2i] = []
	var allowed_cells := {}
	for portable_cell_v in (cells_v as Array):
		if not (portable_cell_v is Array) \
				or (portable_cell_v as Array).size() != 2 \
				or not ((portable_cell_v as Array)[0] is int) \
				or not ((portable_cell_v as Array)[1] is int):
			return false
		var cell := Vector2i(
			int((portable_cell_v as Array)[0]),
			int((portable_cell_v as Array)[1]))
		if allowed_cells.has(cell) \
				or not grid.is_in_bounds(cell.x, cell.y) \
				or not grid.is_walkable(cell.x, cell.y, {}, {}, expected_level):
			return false
		var position: Vector3 = grid.grid_to_world(cell, expected_level)
		if absf(position.x - center.x) > half_size.x + 0.0001 \
				or absf(position.z - center.z) > half_size.y + 0.0001:
			return false
		allowed_cells[cell] = true
		cells.append(cell)
	if not allowed_cells.has(approach_cell):
		return false
	var canonical_cells: Array[Vector2i] = cells.duplicate()
	canonical_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.y == b.y else a.y < b.y)
	if canonical_cells != cells:
		return false
	for cell in cells:
		if grid.find_path(
				approach_cell, cell, {}, false, {}, {},
				expected_level, allowed_cells).is_empty():
			return false
	return true


func _present_exit_shelter_route_refusal(
		source: Node,
		_actor: String,
		result: Dictionary,
		expected_source: Node
	) -> void:
	if not is_instance_valid(source) or source != expected_source \
			or not _exit_shelters.has(source):
		return
	var cue := str(result.get("cue", "")).strip_edges()
	if cue.is_empty():
		_present_exit_shelter_waiting(source)
	else:
		_show_note(cue, 0.0)


## Interactable owns the exact red result pulse.  This owner supplies the
## durable correction beside it, naming the first failed collective condition
## instead of letting repeated REST clicks appear successful but do nothing.
func _on_exit_shelter_interaction_rejected(
		source: Node, _required_character: String, expected_source: Node
	) -> void:
	if not is_instance_valid(source) or source != expected_source \
			or not _exit_shelters.has(source):
		return
	_present_exit_shelter_waiting(source)


func _present_exit_shelter_waiting(source: Node) -> void:
	var blocked: Array = _preflight_canonical_exit_shelter_rest(
		source).get("blocked", []) as Array
	var reason := str(blocked[0]) if not blocked.is_empty() \
		else "the party cannot settle yet"
	_show_note("SHELTER WAITING // %s." % reason, 0.0)


func _exit_shelter_source_receipt_pending(source: Node) -> bool:
	if not is_instance_valid(source) or not _exit_shelters.has(source):
		return false
	var actor := str(source.get("active_character"))
	if not _validate_exit_shelter_trigger(source, actor, source) \
			or bool(source.get("one_shot")) or bool(source.get("_used")) \
			or not bool(source.get("interaction_enabled")):
		return false
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return false
	var receipt: Dictionary = gs.get_interactable(data_id)
	return int(receipt.get("trigger_count", -1)) \
			== int(_exit_rest_trigger_consumed.get(data_id, 0)) + 1 \
		and str(receipt.get("last_trigger_character", "")) == actor \
		and not bool(receipt.get("one_shot", true)) \
		and bool(receipt.get("triggered", false)) \
		and bool(receipt.get("enabled", false))


## A subclass may reject an otherwise real shelter edge for encounter-specific reasons before the
## shared rest owner runs. Consume that exact count and rearm the same presenter; never let the
## rejected edge become credit for a later call.
func _retract_exit_shelter_source_receipt(source: Node) -> void:
	if not is_instance_valid(source) or not _exit_shelters.has(source):
		return
	var data_id := str(source.get("data_id"))
	_exit_rest_trigger_consumed[data_id] = maxi(
		int(_exit_rest_trigger_consumed.get(data_id, 0)),
		maxi(0, _fragment_source_trigger_count(source)))
	if source.has_method("reset"):
		source.reset()
	_publish_fragment_authority()


func _reconcile_accepted_exit_shelter_source_receipts() -> bool:
	var changed := false
	for shelter_v in _exit_shelters:
		var shelter := shelter_v as Node
		if not is_instance_valid(shelter):
			continue
		var data_id := str(shelter.get("data_id"))
		var source_count := maxi(0, _fragment_source_trigger_count(shelter))
		var consumed := maxi(0, int(_exit_rest_trigger_consumed.get(data_id, 0)))
		if source_count <= consumed:
			continue
		_exit_rest_trigger_consumed[data_id] = source_count
		changed = true
		# No owner phase means the snapshot landed after Interactable acceptance but before this
		# callback. Retract that orphan edge; the player must deliberately inspect again.
		if _exit_rest_phase == "ready" and _phase != "complete" \
				and shelter.has_method("reset"):
			shelter.reset()
	return changed


func _reset_exit_shelter_receipts_to_registry() -> void:
	_exit_rest_trigger_consumed.clear()
	for shelter_v in _exit_shelters:
		var shelter := shelter_v as Node
		if not is_instance_valid(shelter):
			continue
		var gs = _get_game_state()
		var data_id := str(shelter.get("data_id"))
		var receipt: Dictionary = gs.get_interactable(data_id) \
			if gs != null and data_id != "" and gs.has_interactable(data_id) else {}
		if bool(receipt.get("triggered", false)) or not bool(receipt.get("enabled", true)) \
				or bool(shelter.get("_used")) \
				or not bool(shelter.get("interaction_enabled")):
			shelter.reset()
		_exit_rest_trigger_consumed[data_id] = maxi(
			0, _fragment_source_trigger_count(shelter))


func _portable_fragment_int_map(raw: Dictionary) -> Dictionary:
	var portable := {}
	for key_v in raw.keys():
		portable[str(key_v)] = maxi(0, int(raw[key_v]))
	return portable


func _validated_fragment_int_map(raw: Variant) -> Dictionary:
	return _portable_fragment_int_map(raw as Dictionary) if raw is Dictionary else {}


## Pure preflight for the exact authored exit. The subset that actually needs daytime recovery is
## still one canonical party-rest batch; already-full members contribute spatial/conscious presence
## without being charged. At night every settled member belongs to the paid batch.
func _preflight_canonical_exit_shelter_rest(it: Node) -> Dictionary:
	var outcome := {
		"complete": false,
		"rest_members": [],
		"already_full": [],
		"blocked": [],
		"before_atp": {},
	}
	var gs = _get_game_state()
	if fragment == null or fragment.party_ids.is_empty():
		(outcome["blocked"] as Array).append("no party is assigned to this fragment")
		return outcome
	if gs == null or gs.scheduler == null:
		(outcome["blocked"] as Array).append("shelter authority is unavailable")
		return outcome
	if it == null or not is_instance_valid(it):
		(outcome["blocked"] as Array).append("the exit shelter is unavailable")
		return outcome

	var needs_rest: Array[String] = []
	for char_id_v in fragment.party_ids:
		var char_id := str(char_id_v)
		if not gs.characters.has(char_id):
			(outcome["blocked"] as Array).append("%s is not present" % char_id.capitalize())
			continue
		if gs.is_downed(char_id) or gs.is_knocked_down(char_id):
			(outcome["blocked"] as Array).append("%s must be revived" % char_id.capitalize())
			continue
		if int(gs.get_character_level(char_id)) \
				!= int(it.get_meta("exit_shelter_level", -1)) \
				or not _character_inside_exit_shelter(gs.get_position(char_id), it):
			(outcome["blocked"] as Array).append("%s is outside this shelter" % char_id.capitalize())
			continue
		if not gs.is_at_shelter(char_id):
			(outcome["blocked"] as Array).append("%s is outside sanctuary ground" % char_id.capitalize())
			continue
		# A member already solo-resting here (the sanctuary revive leaves them recovering) is
		# ABSORBED by the party rest, never a blocker — they fall through to need classification
		# and command_party_rest hands their recovery to the batch.
		if gs.is_moving(char_id) or gs.is_dodging(char_id) or gs.is_endocytosing(char_id) \
				or gs.is_external_traversal_active(char_id) or gs.is_dragging(char_id) \
				or gs.is_field_restoring(char_id):
			(outcome["blocked"] as Array).append(
				"%s is committed to another action" % char_id.capitalize()
			)
			continue
		var hp_full: bool = gs.get_stat(char_id, "hp") >= gs.get_stat_cap(char_id, "hp")
		var stamina_full: bool = gs.get_stat(char_id, "stamina") \
			>= gs.get_stat_cap(char_id, "stamina")
		var needs_canonical_rest: bool = not hp_full or not stamina_full \
			or gs.get_time_of_day() >= GameState.NIGHT_START
		if not needs_canonical_rest:
			(outcome["already_full"] as Array).append(char_id)
			continue
		if gs.get_stat(char_id, "atp") < 1.0:
			(outcome["blocked"] as Array).append("%s cannot pay one ATP" % char_id.capitalize())
			continue
		needs_rest.append(char_id)
	if not (outcome["blocked"] as Array).is_empty():
		return outcome
	if not needs_rest.is_empty() and not bool(gs.can_party_rest(needs_rest)):
		(outcome["blocked"] as Array).append("the recovery party cannot settle yet")
		return outcome
	for char_id in needs_rest:
		(outcome["before_atp"] as Dictionary)[char_id] = gs.get_stat(char_id, "atp")
	(outcome["rest_members"] as Array).assign(needs_rest)
	outcome["complete"] = true
	return outcome


func _complete_exit_shelter_rest(outcome := {}, update_step := false) -> void:
	if _exit_rest_phase == "rested" and _phase == "complete":
		return
	_cancel_exit_rest_callback()
	_exit_rest_phase = "rested"
	_phase = "complete"
	_clear_exit_rest_commit_context()
	_apply_exit_shelter_presenters()
	_publish_fragment_authority()
	if update_step:
		_set_preview_step(
			(fragment.id if fragment != null and fragment.id != "" else "data_fragment")
			+ "_complete")


func _retract_exit_rest_commit() -> void:
	_cancel_exit_rest_callback()
	_phase = "ready"
	_exit_rest_phase = "ready"
	_clear_exit_rest_commit_context()
	_apply_exit_shelter_presenters()
	_publish_fragment_authority()


func _clear_exit_rest_commit_context() -> void:
	_exit_rest_shelter_name = ""
	_exit_rest_members.clear()
	_exit_rest_commit_tick = -1.0
	_exit_rest_commit_day = 0
	_exit_rest_before_atp.clear()


func _exit_rest_tag() -> String:
	return "data_fragment_exit_rest:%s" % _fragment_authority_key().sha256_text().substr(0, 12)


func _cancel_exit_rest_callback() -> void:
	var scheduler = _get_scheduler()
	if scheduler != null:
		scheduler.cancel_tag(_exit_rest_tag())


func _arm_exit_rest_callback() -> void:
	var scheduler = _get_scheduler()
	if scheduler == null or _exit_rest_phase != "committing":
		return
	scheduler.cancel_tag(_exit_rest_tag())
	scheduler.schedule_at(
		maxf(_get_scheduler_tick(), _exit_rest_commit_tick),
		_resume_committed_exit_rest.bind(_exit_rest_commit_tick),
		_exit_rest_tag())


func _resume_committed_exit_rest(expected_tick: float) -> void:
	if _exit_rest_phase != "committing" \
			or not is_equal_approx(_exit_rest_commit_tick, expected_tick):
		return
	if _authored_party_rest_effect_matches(
		_exit_rest_members, _exit_rest_before_atp, _exit_rest_commit_day):
		_complete_exit_shelter_rest({}, true)
		return
	var shelter := _find_exit_rest_shelter(_exit_rest_shelter_name)
	var preflight := _preflight_canonical_exit_shelter_rest(shelter)
	if not _exit_rest_preflight_matches_commit(preflight):
		_retract_exit_rest_commit()
		return
	var gs = _get_game_state()
	if gs != null and bool(gs.command_party_rest(_exit_rest_members)):
		_complete_exit_shelter_rest({}, true)
	else:
		_retract_exit_rest_commit()


func _exit_rest_preflight_matches_commit(preflight: Dictionary) -> bool:
	var gs = _get_game_state()
	if gs == null or gs.get_game_day() != _exit_rest_commit_day \
			or not bool(preflight.get("complete", false)) \
			or (preflight.get("rest_members", []) as Array) != _exit_rest_members:
		return false
	for char_id in _exit_rest_members:
		if not _exit_rest_before_atp.has(char_id) \
				or not is_equal_approx(
					gs.get_stat(char_id, "atp"),
					float(_exit_rest_before_atp[char_id])):
			return false
	return true


func _find_exit_rest_shelter(shelter_name: String) -> Node:
	for shelter_v in _exit_shelters:
		var shelter := shelter_v as Node
		if is_instance_valid(shelter) and (
				shelter_name.is_empty() or str(shelter.name) == shelter_name):
			return shelter
	return null


func _character_inside_exit_shelter(world_position: Vector3, it: Node) -> bool:
	var center_v: Variant = it.get_meta("exit_shelter_center", Vector3.INF)
	var half_v: Variant = it.get_meta("exit_shelter_half_size", Vector2.ZERO)
	if not center_v is Vector3 or not half_v is Vector2:
		return false
	var center := center_v as Vector3
	var half := half_v as Vector2
	return absf(world_position.x - center.x) <= half.x \
		and absf(world_position.z - center.z) <= half.y


func _apply_exit_shelter_presenters() -> void:
	var completed := _phase == "complete"
	var enabled := not completed and _exit_rest_phase != "committing"
	for it in _exit_shelters:
		if not is_instance_valid(it):
			continue
		if it.has_method("restore_one_shot_presenter"):
			it.call("restore_one_shot_presenter", completed, enabled)
		elif it.has_method("set_interaction_enabled"):
			it.call("set_interaction_enabled", enabled)

func _on_fragment_target_spotted(target_id: String) -> void:
	if fragment == null or _phase == "complete" or not (target_id in Array(fragment.party_ids)):
		return
	_spotted_count += 1
	_publish_fragment_authority()
	_show_note("Spotted. It's coming.", 2.0)

## A member beaten to 0 hp stays where they fell (the engine owns the down). The loader's only job:
## notice a FULL wipe and restart the fragment from the entry when the data asked for that.
func _on_fragment_character_downed(cid: String) -> void:
	if fragment == null or _phase == "complete" or not (cid in Array(fragment.party_ids)):
		return
	_show_note("%s is down. They stay where they fell." % cid.capitalize(), 2.4)
	var gs = _get_game_state()
	if gs == null or not gs.is_party_downed(Array(fragment.party_ids)):
		return
	_wipe_count += 1
	# Where the run ended — the runback decor pass landscapes over this spot (logged state, so a
	# replayed run regrows its Verdanta in the same places).
	_fall_pos = gs.get_position(cid)
	_show_note("It takes everyone. From the top.", 2.6)
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(_restart_tag())
		_restart_deadline = float(sched.get_current_tick()) + 1.5
		_schedule_fragment_restart_at(_restart_deadline)
	_publish_fragment_authority()

func _restart_tag() -> String:
	return "frag_restart_" + (fragment.id if fragment != null and fragment.id != "" else "data_fragment")

## Full wipe -> restart from the entry: every member restored at their spawn (logged restore + snap,
## so the restart replays), every enemy re-posted, the flure re-armed.
func _restart_fragment() -> void:
	_restart_deadline = -1.0
	var gs = _get_game_state()
	if gs == null or fragment == null:
		return
	for cid_v in fragment.party_ids:
		var cid := str(cid_v)
		if not gs.characters.has(cid):
			continue
		gs.restore_character(cid)
		if fragment.spawns.has(cid):
			gs.snap_character_to(cid, fragment.spawns[cid])
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.has_method("re_post") and _enemy_posts.has(enemy.char_id):
			enemy.re_post(_enemy_posts[enemy.char_id])
	for fl in _flures:
		if is_instance_valid(fl):
			fl.reset_flure()
	_apply_downed_at_start()
	_apply_runback_decor()
	_phase = "ready"
	_apply_exit_shelter_presenters()
	_publish_fragment_authority()
	_set_preview_step((fragment.id if fragment.id != "" else "data_fragment") + "_restart")

## The runback decor pass (docs/DECORATIVE_FLORA.md): each wipe makes the level prettier and
## deader. Verdanta SPREADS (+1 patch near where the party fell — your failures get landscaped
## over), Festoona DROOPS for the rest of the run, Lilypall re-rolls its raft arrangement.
## Deterministic: seeded from the fragment id + wipe count + the logged fall position, so a
## replayed run regrows identically. Curbelia is untouched — contract plantings don't care.
func _apply_runback_decor() -> void:
	if _wipe_count <= 0 or _decoratives.is_empty():
		return
	for deco_v in _decoratives:
		var deco := deco_v as DecorativeFlora
		if deco == null or not is_instance_valid(deco):
			continue
		if deco.species == "festoona":
			deco.set_drooped(true)
		elif deco.species == "lilypall":
			deco.reroll(hash(fragment.id) + _wipe_count)
	var h := hash("%s_verdanta_%d" % [fragment.id, _wipe_count])
	var ang := float(h % 628) * 0.01
	var off := Vector3(cos(ang), 0.0, sin(ang)) * (0.8 + float((h / 628) % 10) * 0.12)
	var patch := DecorativeFlora.new()
	patch.name = "VerdantaSpread%d" % _wipe_count
	patch.configure("verdanta", Vector3(_fall_pos.x, 0.0, _fall_pos.z) + off,
		{"radius": 0.9, "wall": false})
	add_child(patch)
	_decoratives.append(patch)
	_spread_patches.append(patch)

## The host's live selection (the portal group provider — a click moves whoever is selected).
func _selected_party_ids() -> Array:
	if host != null and host.has_method("get_preview_selected_characters"):
		return host.call("get_preview_selected_characters")
	return []

## The same live roster the host presents as selectable/playable. This stays
## separate from the current selection so collective kit verbs can fail closed
## instead of silently degrading to whichever singleton happens to be active.
func _playable_party_ids() -> Array:
	if host != null and host.has_method("get_preview_available_party_ids"):
		var provided: Variant = host.call("get_preview_available_party_ids")
		if provided is Array:
			return (provided as Array).duplicate()
	var gs = _get_game_state()
	if gs == null or fragment == null:
		return []
	var live_party: Array = gs.get_party()
	var result: Array = []
	for cid_v in fragment.party_ids:
		var cid := str(cid_v)
		if live_party.has(cid) and gs.characters.has(cid) \
				and gs.is_narratively_available(cid):
			result.append(cid)
	return result

func _crossing_assist_refusal_note(reason: String) -> String:
	match reason:
		"full party not selected":
			return "ASSIST WAITING // select the full playable party before arming."
		"group not staged":
			return "ASSIST WAITING // get the full party onto the upper deck before arming."
		"route or busy", "launch route or busy":
			return "ASSIST WAITING // the full selected group needs one clear route."
		"unsafe staging route":
			return "ASSIST WAITING // the hold formation is not safe through the water change."
		"group unavailable", "staging interrupted":
			return "ASSIST WAITING // staging stopped; the stamina charge was returned."
		"wrong character":
			return "ASSIST WAITING // Aster must log this rota."
		"stamina":
			return "ASSIST WAITING // Aster needs more stamina."
		"already armed":
			return "CROSSING ALREADY ARMED // hold at the mouth."
		"already staging":
			return "CROSSING STAGING // the full group is still moving to the safe hold line."
		"cooldown":
			return "ASSIST COOLING DOWN // use the rota or wait."
		_:
			return "ASSIST WAITING // the crossing could not be armed."

func _enemy_by_id(cid: String):
	for enemy in _enemies:
		if is_instance_valid(enemy) and str(enemy.char_id) == cid:
			return enemy
	return null

## Freed while the scheduler lives (preview reloads): retract every tag this loader owns.
func _exit_tree() -> void:
	var gs = _get_game_state()
	if gs != null and gs.movement_started.is_connected(_on_spatial_movement_started):
		gs.movement_started.disconnect(_on_spatial_movement_started)
	if gs != null and gs.movement_cancelled.is_connected(_on_spatial_movement_cancelled):
		gs.movement_cancelled.disconnect(_on_spatial_movement_cancelled)
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag(_restart_tag())
	sched.cancel_tag(_candid_tag())
	sched.cancel_tag(_concealment_tag())
	for cid_v in _concealment_boundary_ticks.keys():
		sched.cancel_tag(_concealment_boundary_tag(str(cid_v)))
	_concealment_boundary_ticks.clear()
	for cid_v in _spike_crossing_events.keys():
		sched.cancel_tag(_spike_crossing_tag(str(cid_v)))
	_spike_crossing_events.clear()
	for idx_v in _weak_wall_deadlines.keys():
		sched.cancel_tag(_weak_wall_tag(int(idx_v)))
	for fl in _flures:
		if is_instance_valid(fl):
			sched.cancel_tag("flure_reset_" + str(fl.name))

const CANDID_TICK := 0.5

func _candid_tag() -> String:
	return "candid_dot_" + (fragment.id if fragment != null and fragment.id != "" else "data_fragment")


func _concealment_tag() -> String:
	return "fragment_concealment_" + (
		fragment.id if fragment != null and fragment.id != "" else "data_fragment")


func _concealment_boundary_tag(cid: String) -> String:
	return "%s_boundary_%s" % [_concealment_tag(), cid]


func _has_shared_concealment_sources() -> bool:
	return not _capbages.is_empty() or not _scarpets.is_empty() \
		or not _candid_zones.is_empty() or not _infrastructure_fields.is_empty()


## Candid is an axis-aligned terrain volume, so its entry/exit moments are analytically knowable from
## the same committed movement segments predictive detection reads. Schedule those exact boundaries
## ahead of the detection event; the fixed cadence remains the fallback for non-analytic/moving cover.
func _on_spatial_movement_started(cid: String) -> void:
	if fragment == null:
		return
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if gs == null or sched == null:
		return
	_arm_spike_crossing_events(cid)
	if not fragment.party_ids.has(cid):
		return
	sched.cancel_tag(_concealment_boundary_tag(cid))
	_concealment_boundary_ticks.erase(cid)
	_update_character_shared_concealment(cid)
	if _candid_zones.is_empty() or not gs.is_moving(cid):
		return
	var candidates: Array[float] = []
	for cz in _candid_zones:
		if not is_instance_valid(cz):
			continue
		var center := Vector2(cz.global_position.x, cz.global_position.z)
		for boundary_tick in gs.predict_axis_aligned_region_boundary_ticks(
				cid, center, cz.half_size):
			candidates.append(float(boundary_tick))
			# `covers` includes the edge. The paired epsilon sample changes truth immediately after
			# an EXIT without moving an ENTRY later than its exact protective boundary.
			candidates.append(float(boundary_tick) + CONCEALMENT_BOUNDARY_EPSILON)
	candidates.sort()
	var unique_ticks: Array[float] = []
	for candidate in candidates:
		if unique_ticks.is_empty() \
				or absf(candidate - unique_ticks[unique_ticks.size() - 1]) > 0.00001:
			unique_ticks.append(candidate)
	if unique_ticks.is_empty():
		return
	_concealment_boundary_ticks[cid] = unique_ticks
	_schedule_next_concealment_boundary(cid)


func _on_spatial_movement_cancelled(cid: String) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag(_spike_crossing_tag(cid))
	_spike_crossing_events.erase(cid)
	if fragment != null and fragment.party_ids.has(cid):
		sched.cancel_tag(_concealment_boundary_tag(cid))
		_concealment_boundary_ticks.erase(cid)


func _schedule_next_concealment_boundary(cid: String) -> void:
	var sched = _get_scheduler()
	if sched == null or not _concealment_boundary_ticks.has(cid):
		return
	var pending: Array = _concealment_boundary_ticks[cid]
	var now := float(sched.get_current_tick())
	while not pending.is_empty() and float(pending[0]) < now - 0.000001:
		pending.pop_front()
	if pending.is_empty():
		_concealment_boundary_ticks.erase(cid)
		return
	_concealment_boundary_ticks[cid] = pending
	sched.schedule_at(
		maxf(now, float(pending[0])),
		_on_concealment_boundary.bind(cid),
		_concealment_boundary_tag(cid))


func _on_concealment_boundary(cid: String) -> void:
	_update_character_shared_concealment(cid)
	if not _concealment_boundary_ticks.has(cid):
		return
	var pending: Array = _concealment_boundary_ticks[cid]
	if not pending.is_empty():
		pending.pop_front()
	if pending.is_empty():
		_concealment_boundary_ticks.erase(cid)
		return
	_concealment_boundary_ticks[cid] = pending
	_schedule_next_concealment_boundary(cid)


func _spike_crossing_tag(cid: String) -> String:
	return "%s_spike_crossing_%s" % [_candid_tag(), cid]


func _spike_crossing_event_before(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("tick", 0.0)) < float(b.get("tick", 0.0))


## A thin strip can be entered and exited between two 0.5-second samples. Integrate the exact
## positive-duration overlap of every committed movement segment and deliver that damage at the
## interval's end. The fixed cadence handles only parked bodies, so travel is never double charged.
func _arm_spike_crossing_events(cid: String) -> void:
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if gs == null or sched == null:
		return
	sched.cancel_tag(_spike_crossing_tag(cid))
	_spike_crossing_events.erase(cid)
	if _spike_strips.is_empty() or not gs.characters.has(cid) or not gs.is_moving(cid):
		return
	var is_party_member := fragment != null and fragment.party_ids.has(cid)
	var enemy = _enemy_by_id(cid)
	if not is_party_member and enemy == null:
		return
	var events: Array[Dictionary] = []
	for strip in _spike_strips:
		if not is_instance_valid(strip):
			continue
		var center := Vector2(strip.global_position.x, strip.global_position.z)
		for interval_v in gs.predict_axis_aligned_region_occupancy_intervals(
				cid, center, strip.half_size):
			var interval := interval_v as Dictionary
			var start_tick := float(interval.get("start_tick", -1.0))
			var end_tick := float(interval.get("end_tick", -1.0))
			var exposure := maxf(0.0, end_tick - start_tick)
			if exposure <= 0.000001:
				continue
			events.append({
				"tick": end_tick,
				"damage": float(strip.dot_per_sec) * exposure,
				"source": str(strip.name),
			})
	if events.is_empty():
		return
	events.sort_custom(_spike_crossing_event_before)
	_spike_crossing_events[cid] = events
	_schedule_next_spike_crossing(cid)


func _schedule_next_spike_crossing(cid: String) -> void:
	var sched = _get_scheduler()
	if sched == null or not _spike_crossing_events.has(cid):
		return
	var pending: Array = _spike_crossing_events[cid]
	if pending.is_empty():
		_spike_crossing_events.erase(cid)
		return
	var event := pending[0] as Dictionary
	sched.schedule_at(
		maxf(float(sched.get_current_tick()), float(event.get("tick", 0.0))),
		_on_spike_crossing_damage.bind(cid),
		_spike_crossing_tag(cid))


func _on_spike_crossing_damage(cid: String) -> void:
	if not _spike_crossing_events.has(cid):
		return
	var pending: Array = _spike_crossing_events[cid]
	if pending.is_empty():
		_spike_crossing_events.erase(cid)
		return
	var event := pending.pop_front() as Dictionary
	var damage := maxf(0.0, float(event.get("damage", 0.0)))
	var gs = _get_game_state()
	if damage > 0.0 and gs != null and gs.characters.has(cid):
		if fragment != null and fragment.party_ids.has(cid):
			gs.adjust_stat(cid, "hp", -damage, str(event.get("source", "spike_strip")))
		else:
			var enemy = _enemy_by_id(cid)
			if enemy != null and enemy.is_alive():
				enemy.take_damage(damage)
	if pending.is_empty():
		_spike_crossing_events.erase(cid)
		return
	_spike_crossing_events[cid] = pending
	_schedule_next_spike_crossing(cid)


func _arm_concealment_tick() -> void:
	var sched = _get_scheduler()
	if sched == null or not _has_shared_concealment_sources():
		return
	if _concealment_epoch < 0.0:
		_concealment_epoch = float(sched.get_current_tick()) + CONCEALMENT_TICK
		_publish_fragment_authority()
	_schedule_concealment_at(_next_fixed_tick(
		_concealment_epoch, CONCEALMENT_TICK))


func _on_concealment_tick() -> void:
	_update_shared_concealment()
	_arm_concealment_tick()


func _arm_candid_tick() -> void:
	var sched = _get_scheduler()
	if sched == null or (_candid_zones.is_empty() and _spike_strips.is_empty() \
			and _infrastructure_fields.is_empty()):
		return
	if _candid_epoch < 0.0:
		_candid_epoch = float(sched.get_current_tick()) + CANDID_TICK
		_publish_fragment_authority()
	_schedule_candid_at(_next_fixed_tick(_candid_epoch, CANDID_TICK))

func _on_candid_tick() -> void:
	var gs = _get_game_state()
	if gs != null and fragment != null:
		for cid_v in fragment.party_ids:
			var cid := str(cid_v)
			if not gs.characters.has(cid):
				continue
			var pos: Vector3 = gs.get_position(cid)
			for cz in _candid_zones:
				if is_instance_valid(cz) and cz.covers(pos):
					gs.adjust_stat(cid, "hp", -cz.dot_per_sec * CANDID_TICK)
					break
			# Moving exposure is integrated from the committed segment, so a thin strip cannot be
			# skipped between samples and this parked cadence never double-charges the same travel.
			if not gs.is_moving(cid):
				for strip in _spike_strips:
					if is_instance_valid(strip) and strip.covers(pos):
						gs.adjust_stat(cid, "hp", -strip.dot_per_sec * CANDID_TICK)
						break
			for service_field in _infrastructure_fields:
				if is_instance_valid(service_field) and service_field.is_hazardous() \
						and service_field.covers(pos):
					gs.adjust_stat(cid, "hp", -service_field.dot_per_sec * CANDID_TICK)
					break
	# Hostile architecture is indiscriminate: an enemy standing on the studs drains too — that's
	# the tactic (lure/push them across it). Candid biofilm never hurts fauna; only the strips do.
	if gs != null and not _spike_strips.is_empty():
		for enemy in _enemies:
			if not is_instance_valid(enemy) or not enemy.is_alive():
				continue
			if not gs.characters.has(enemy.char_id):
				continue
			if gs.is_moving(enemy.char_id):
				continue
			var epos: Vector3 = gs.get_position(enemy.char_id)
			for strip in _spike_strips:
				if is_instance_valid(strip) and strip.covers(epos):
					enemy.take_damage(strip.dot_per_sec * CANDID_TICK)
					break
	_arm_candid_tick()

func _ensure_scheduled() -> void:
	if _scheduled:
		return
	if _channels.is_empty() and _candid_zones.is_empty() and _spike_strips.is_empty() \
			and _infrastructure_fields.is_empty() and _basins.is_empty() \
			and not _has_shared_concealment_sources():
		return
	var sched = _get_scheduler()
	if sched == null:
		return
	var gs = _get_game_state()
	if gs != null and (_has_shared_concealment_sources() or not _spike_strips.is_empty()):
		if not gs.movement_started.is_connected(_on_spatial_movement_started):
			gs.movement_started.connect(_on_spatial_movement_started)
		if not gs.movement_cancelled.is_connected(_on_spatial_movement_cancelled):
			gs.movement_cancelled.connect(_on_spatial_movement_cancelled)
	_scheduled = true
	for ch in _channels:
		ch.start(sched, _get_game_state())
	for basin in _basins:
		basin.start(sched, _get_game_state())
	_arm_candid_tick()
	_arm_concealment_tick()
	if gs != null:
		for cid_v in gs.characters.keys():
			var cid := str(cid_v)
			if gs.is_moving(cid):
				_on_spatial_movement_started(cid)
	_publish_fragment_authority()


## Scene-local Callables are deliberately absent from EventScheduler snapshots. This record is the
## fragment loader's portable gameplay truth: it keeps the shared damage cadence, wipe restart,
## weak-wall commitments, and loader-owned progression on the same absolute simulation timeline.
func _fragment_authority_key() -> String:
	var stable_id := fragment.id if fragment != null and fragment.id != "" else fragment_path
	if stable_id == "":
		stable_id = chunk_name if chunk_name != "" else "data_fragment"
	return DATA_FRAGMENT_AUTHORITY_PREFIX + stable_id


func _fragment_authority_state() -> Dictionary:
	var weak_walls: Array = []
	for idx in range(_weak_walls.size()):
		var wall: Dictionary = _weak_walls[idx]
		weak_walls.append({
			"crumbled": bool(wall.get("crumbled", false)),
			"deadline": float(_weak_wall_deadlines.get(idx, -1.0)),
			"trigger_consumed": maxi(0, int(wall.get("trigger_consumed", 0))),
		})
	var infrastructure: Dictionary = {}
	for operation in _infrastructure_operations:
		if not is_instance_valid(operation) or not operation.has_method("serialize_state"):
			continue
		var operation_state: Dictionary = operation.call("serialize_state")
		var operation_id := str(operation_state.get("operation_id", ""))
		if operation_id != "":
			infrastructure[operation_id] = operation_state
	return {
		"version": DATA_FRAGMENT_AUTHORITY_VERSION,
		"fragment_id": fragment.id if fragment != null else "",
		"phase": _phase,
		"scheduled": _scheduled,
		"candid_epoch": _candid_epoch,
		"concealment_epoch": _concealment_epoch,
		"restart_deadline": _restart_deadline,
		"spotted_count": _spotted_count,
		"wipe_count": _wipe_count,
		"fall_pos": [_fall_pos.x, _fall_pos.y, _fall_pos.z],
		"exit_rest_phase": _exit_rest_phase,
		"exit_rest_shelter_name": _exit_rest_shelter_name,
		"exit_rest_members": _exit_rest_members.duplicate(),
		"exit_rest_commit_tick": _exit_rest_commit_tick,
		"exit_rest_commit_day": _exit_rest_commit_day,
		"exit_rest_before_atp": _exit_rest_before_atp.duplicate(true),
		"exit_rest_trigger_consumed": _portable_fragment_int_map(
			_exit_rest_trigger_consumed),
		"weak_walls": weak_walls,
		"infrastructure": infrastructure,
	}


func _publish_fragment_authority() -> void:
	if _restoring_fragment_authority:
		return
	var gs = _get_game_state()
	if gs != null and gs.has_method("set_world_state"):
		gs.set_world_state(_fragment_authority_key(), _fragment_authority_state())


func _normalized_fragment_authority(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var saved := (raw as Dictionary).duplicate(true)
	var saved_version := int(saved.get("version", 0))
	if saved_version in [1, 2, 3]:
		if saved_version in [1, 2]:
			if saved_version == 1:
				var legacy_complete := str(saved.get("phase", "")) == "complete"
				saved["exit_rest_phase"] = "rested" if legacy_complete else "ready"
				saved["exit_rest_shelter_name"] = ""
				saved["exit_rest_members"] = []
				saved["exit_rest_commit_tick"] = -1.0
				saved["exit_rest_commit_day"] = 0
				saved["exit_rest_before_atp"] = {}
			var migrated_exit_counts := {}
			for shelter_v in _exit_shelters:
				var shelter := shelter_v as Node
				var shelter_id := str(shelter.get("data_id"))
				migrated_exit_counts[shelter_id] = maxi(
					0, _fragment_source_trigger_count(shelter))
			saved["exit_rest_trigger_consumed"] = migrated_exit_counts
			# Legacy records predate exact weak-wall receipts. Preserve their physical endpoint/deadline,
			# but consume only the registry count already visible at that saved tick; never infer a pry.
			var migrated_walls: Array = []
			var legacy_walls: Array = saved.get("weak_walls", []) as Array
			for idx in range(_weak_walls.size()):
				var wall_state: Dictionary = (
					legacy_walls[idx] as Dictionary).duplicate(true) \
					if idx < legacy_walls.size() and legacy_walls[idx] is Dictionary else {}
				var source: Node = (_weak_walls[idx] as Dictionary).get("source")
				wall_state["trigger_consumed"] = maxi(
					0, _weak_wall_source_trigger_count(source))
				migrated_walls.append(wall_state)
			saved["weak_walls"] = migrated_walls
		# V3 already owns exact interaction receipts, but predates the explicit spatial-cover clock.
		# Start that new cadence from the restored scheduler tick rather than inventing a past sample.
		saved["concealment_epoch"] = -1.0
		saved["version"] = DATA_FRAGMENT_AUTHORITY_VERSION
	if int(saved.get("version", 0)) != DATA_FRAGMENT_AUTHORITY_VERSION:
		return {}
	var expected_id := fragment.id if fragment != null else ""
	if str(saved.get("fragment_id", expected_id)) != expected_id:
		return {}
	var concealment_epoch := float(saved.get("concealment_epoch", -1.0))
	if not is_finite(concealment_epoch) or concealment_epoch < -1.0:
		return {}
	var exit_counts_v: Variant = saved.get("exit_rest_trigger_consumed", null)
	if not exit_counts_v is Dictionary:
		return {}
	var exit_counts := exit_counts_v as Dictionary
	for shelter_v in _exit_shelters:
		var shelter := shelter_v as Node
		var shelter_id := str(shelter.get("data_id"))
		var saved_count := int(exit_counts.get(shelter_id, -1))
		var source_count := _fragment_source_trigger_count(shelter)
		if saved_count < 0 or source_count < 0 or saved_count > source_count:
			return {}
	var wall_states_v: Variant = saved.get("weak_walls", null)
	if not wall_states_v is Array:
		return {}
	var wall_states := wall_states_v as Array
	for idx in range(_weak_walls.size()):
		if idx >= wall_states.size() or not wall_states[idx] is Dictionary:
			return {}
		var state := wall_states[idx] as Dictionary
		var deadline := float(state.get("deadline", -1.0))
		var consumed := int(state.get("trigger_consumed", -1))
		var source: Node = (_weak_walls[idx] as Dictionary).get("source")
		var source_count := _weak_wall_source_trigger_count(source)
		if not is_finite(deadline) or deadline < -1.0 or consumed < 0 \
				or source_count < 0 or consumed > source_count:
			return {}
	return saved


## Production save restore clears opaque Callables before replacing GameState. Reattach exactly one
## callback per committed deadline; never restart a full interval and never replay a consequence here.
func on_game_state_snapshot_restored() -> void:
	super.on_game_state_snapshot_restored()
	# Restore each child registry mirror before projecting the chunk-owned wall phase. The owner
	# override then survives a later generic presenter walk without reopening a committed collapse.
	for wall_v in _weak_walls:
		var source: Node = (wall_v as Dictionary).get("source")
		if is_instance_valid(source) and source.has_method("on_game_state_snapshot_restored"):
			source.on_game_state_snapshot_restored()
	for shelter_v in _exit_shelters:
		var shelter := shelter_v as Node
		if is_instance_valid(shelter) and shelter.has_method("on_game_state_snapshot_restored"):
			shelter.on_game_state_snapshot_restored()
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(_restart_tag())
		sched.cancel_tag(_candid_tag())
		sched.cancel_tag(_concealment_tag())
		sched.cancel_tag(_exit_rest_tag())
		for idx in range(_weak_walls.size()):
			sched.cancel_tag(_weak_wall_tag(idx))
	var gs = _get_game_state()
	var raw: Variant = gs.get_world_state(_fragment_authority_key(), null) \
			if gs != null and gs.has_method("get_world_state") else null
	var saved := _normalized_fragment_authority(raw)
	if saved.is_empty():
		_retract_fragment_presenter_to_defaults()
		return
	var migrated := int((raw as Dictionary).get("version", 0)) \
		!= DATA_FRAGMENT_AUTHORITY_VERSION

	_restoring_fragment_authority = true
	_phase = str(saved.get("phase", "ready"))
	if _phase not in ["ready", "active", "failed", "committing", "complete"]:
		_phase = "ready"
	_scheduled = bool(saved.get("scheduled", false))
	_candid_epoch = float(saved.get("candid_epoch", -1.0))
	_concealment_epoch = float(saved.get("concealment_epoch", -1.0))
	_restart_deadline = float(saved.get("restart_deadline", -1.0))
	_spotted_count = maxi(0, int(saved.get("spotted_count", 0)))
	_wipe_count = maxi(0, int(saved.get("wipe_count", 0)))
	_fall_pos = _fragment_vec3(saved.get("fall_pos", []), Vector3.ZERO)
	_exit_rest_phase = str(saved.get(
		"exit_rest_phase", "rested" if _phase == "complete" else "ready"))
	if _exit_rest_phase not in EXIT_REST_PHASES:
		_exit_rest_phase = "ready"
	_exit_rest_shelter_name = str(saved.get("exit_rest_shelter_name", ""))
	_exit_rest_members.clear()
	for member_v in saved.get("exit_rest_members", []) as Array:
		var member_id := str(member_v)
		if member_id != "" and not _exit_rest_members.has(member_id):
			_exit_rest_members.append(member_id)
	_exit_rest_commit_tick = float(saved.get("exit_rest_commit_tick", -1.0))
	_exit_rest_commit_day = int(saved.get("exit_rest_commit_day", 0))
	_exit_rest_before_atp = (
		saved.get("exit_rest_before_atp", {}) as Dictionary).duplicate(true)
	_exit_rest_trigger_consumed = _validated_fragment_int_map(
		saved.get("exit_rest_trigger_consumed", {}))
	if _exit_rest_phase == "committing" and (
			_phase != "committing" or _exit_rest_members.is_empty()
			or _exit_rest_commit_tick < 0.0 or _exit_rest_before_atp.is_empty()):
		_exit_rest_phase = "ready"
		_phase = "ready"
		_clear_exit_rest_commit_context()
	elif _exit_rest_phase == "rested":
		_phase = "complete"
	_weak_wall_deadlines.clear()
	var wall_states: Array = saved.get("weak_walls", []) as Array
	for idx in range(_weak_walls.size()):
		var state: Dictionary = wall_states[idx] as Dictionary if idx < wall_states.size() \
				and wall_states[idx] is Dictionary else {}
		var wall := _weak_walls[idx] as Dictionary
		wall["trigger_consumed"] = maxi(0, int(state.get("trigger_consumed", 0)))
		var crumbled := bool(state.get("crumbled", false))
		_set_weak_wall_presenter(idx, crumbled)
		var deadline := float(state.get("deadline", -1.0))
		if not crumbled and deadline >= 0.0:
			_weak_wall_deadlines[idx] = deadline
	var reconciled_weak_wall_receipt := _reconcile_accepted_weak_wall_source_receipts()
	var reconciled_exit_receipt := _reconcile_accepted_exit_shelter_source_receipts()
	_restore_infrastructure_presenters(saved.get("infrastructure", {}))
	_apply_exit_shelter_presenters()
	if sched != null and _scheduled and _concealment_epoch < 0.0 \
			and _has_shared_concealment_sources():
		_concealment_epoch = float(sched.get_current_tick()) + CONCEALMENT_TICK
	_restoring_fragment_authority = false
	if migrated or reconciled_weak_wall_receipt or reconciled_exit_receipt:
		_publish_fragment_authority()

	if sched == null:
		return
	if _scheduled and _candid_epoch >= 0.0 and (not _candid_zones.is_empty() \
			or not _spike_strips.is_empty() or not _infrastructure_fields.is_empty()):
		_schedule_candid_at(_next_fixed_tick(_candid_epoch, CANDID_TICK))
	if _scheduled and _concealment_epoch >= 0.0 and _has_shared_concealment_sources():
		_schedule_concealment_at(_next_fixed_tick(
			_concealment_epoch, CONCEALMENT_TICK))
	if _restart_deadline >= 0.0:
		_schedule_fragment_restart_at(_restart_deadline)
	if _exit_rest_phase == "committing":
		_arm_exit_rest_callback()
	for idx_v in _weak_wall_deadlines.keys():
		_schedule_weak_wall_at(int(idx_v), float(_weak_wall_deadlines[idx_v]))
	_sync_weak_wall_presenters()


func _retract_fragment_presenter_to_defaults() -> void:
	_restoring_fragment_authority = true
	_phase = "ready"
	_scheduled = false
	_candid_epoch = -1.0
	_concealment_epoch = -1.0
	_restart_deadline = -1.0
	_spotted_count = 0
	_wipe_count = 0
	_fall_pos = Vector3.ZERO
	_exit_rest_phase = "ready"
	_clear_exit_rest_commit_context()
	_reset_exit_shelter_receipts_to_registry()
	_weak_wall_deadlines.clear()
	for idx in range(_weak_walls.size()):
		_retract_weak_wall_source_to_ready(idx)
		_set_weak_wall_presenter(idx, false)
	_restore_infrastructure_presenters({})
	_apply_exit_shelter_presenters()
	_restoring_fragment_authority = false


func _schedule_candid_at(deadline: float) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag(_candid_tag())
	sched.schedule_after(maxf(0.0, deadline - float(sched.get_current_tick())),
		_on_candid_tick, _candid_tag())


func _schedule_concealment_at(deadline: float) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag(_concealment_tag())
	sched.schedule_after(maxf(0.0, deadline - float(sched.get_current_tick())),
		_on_concealment_tick, _concealment_tag())


func _schedule_fragment_restart_at(deadline: float) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag(_restart_tag())
	sched.schedule_after(maxf(0.0, deadline - float(sched.get_current_tick())),
		_restart_fragment, _restart_tag())


func _weak_wall_tag(idx: int) -> String:
	return "%s:weak_wall:%d" % [_fragment_authority_key(), idx]


func _schedule_weak_wall_at(idx: int, deadline: float) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	var tag := _weak_wall_tag(idx)
	sched.cancel_tag(tag)
	sched.schedule_after(maxf(0.0, deadline - float(sched.get_current_tick())),
		_commit_weak_wall.bind(idx), tag)


## An accepted Interactable edge can be serialized synchronously before this owner callback begins.
## At that seam the wall has not moved and no deadline exists, so loading consumes the orphan count
## and re-arms the same source. It never grants a free collapse or leaves a permanently dead pry point.
func _reconcile_accepted_weak_wall_source_receipts() -> bool:
	var changed := false
	for idx in range(_weak_walls.size()):
		var wall := _weak_walls[idx] as Dictionary
		var source: Node = wall.get("source")
		var source_count := maxi(0, _weak_wall_source_trigger_count(source))
		var consumed := maxi(0, int(wall.get("trigger_consumed", 0)))
		if source_count > consumed:
			wall["trigger_consumed"] = source_count
			changed = true
		if not bool(wall.get("crumbled", false)) and not _weak_wall_deadlines.has(idx):
			var gs = _get_game_state()
			var data_id := str(source.get("data_id")) if is_instance_valid(source) else ""
			var receipt: Dictionary = gs.get_interactable(data_id) \
				if gs != null and data_id != "" and gs.has_interactable(data_id) else {}
			if bool(receipt.get("triggered", false)) \
					or not bool(receipt.get("enabled", true)) \
					or bool(source.get("_used")) \
					or not bool(source.get("interaction_enabled")):
				source.reset()
				wall["trigger_consumed"] = maxi(
					int(wall.get("trigger_consumed", 0)),
					maxi(0, _weak_wall_source_trigger_count(source)))
				changed = true
		_project_weak_wall_source(idx)
	return changed


func _retract_weak_wall_source_to_ready(idx: int) -> void:
	if idx < 0 or idx >= _weak_walls.size():
		return
	var wall := _weak_walls[idx] as Dictionary
	var source: Node = wall.get("source")
	if not is_instance_valid(source):
		wall["trigger_consumed"] = 0
		return
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	var receipt: Dictionary = gs.get_interactable(data_id) \
		if gs != null and data_id != "" and gs.has_interactable(data_id) else {}
	if bool(receipt.get("triggered", false)) or not bool(receipt.get("enabled", true)) \
			or bool(source.get("_used")) or not bool(source.get("interaction_enabled")):
		source.reset()
	wall["trigger_consumed"] = maxi(0, _weak_wall_source_trigger_count(source))


func _project_weak_wall_source(idx: int) -> void:
	if idx < 0 or idx >= _weak_walls.size():
		return
	var wall := _weak_walls[idx] as Dictionary
	var source: Node = wall.get("source")
	if not is_instance_valid(source):
		return
	var spent := bool(wall.get("crumbled", false)) or _weak_wall_deadlines.has(idx)
	if source.has_method("restore_one_shot_presenter"):
		source.restore_one_shot_presenter(spent, not spent)
	else:
		source.set("_used", spent)
		source.set_interaction_enabled(not spent)


func _next_fixed_tick(epoch: float, interval: float) -> float:
	return FixedCadenceScript.next_strict_tick(epoch, interval, _get_scheduler_tick())


func _set_weak_wall_presenter(idx: int, crumbled: bool) -> void:
	if idx < 0 or idx >= _weak_walls.size():
		return
	var wall: Dictionary = _weak_walls[idx]
	wall["crumbled"] = crumbled
	_apply_weak_wall_visual_progress(idx, 1.0 if crumbled else 0.0)
	var rubble = wall.get("rubble", null)
	if is_instance_valid(rubble):
		rubble.visible = crumbled
	_project_weak_wall_source(idx)


## The deadline is authority; slab transforms are a pure, reload-safe projection. Staggering the
## three panels slightly gives the player a readable outward wave without adding hidden sub-timers.
func _sync_weak_wall_presenters() -> void:
	var now := _get_scheduler_tick()
	for idx in range(_weak_walls.size()):
		var wall: Dictionary = _weak_walls[idx]
		if bool(wall.get("crumbled", false)):
			_apply_weak_wall_visual_progress(idx, 1.0)
			continue
		var deadline := float(_weak_wall_deadlines.get(idx, -1.0))
		var progress := 0.0
		if deadline >= 0.0:
			progress = clampf(
				1.0 - (deadline - now) / WEAK_WALL_CRUMBLE_DURATION,
				0.0,
				1.0
			)
		_apply_weak_wall_visual_progress(idx, progress)


func _apply_weak_wall_visual_progress(idx: int, progress: float) -> void:
	if idx < 0 or idx >= _weak_walls.size():
		return
	var wall: Dictionary = _weak_walls[idx]
	var panels: Array = wall.get("panels", [])
	var starts: Array = wall.get("panel_starts", [])
	for panel_index in range(mini(panels.size(), starts.size())):
		var panel = panels[panel_index]
		if not is_instance_valid(panel):
			continue
		var stagger := 0.045 * float(panel_index)
		var local_progress := clampf((progress - stagger) / (1.0 - stagger), 0.0, 1.0)
		var eased := local_progress * local_progress * (3.0 - 2.0 * local_progress)
		var start: Vector3 = starts[panel_index]
		panel.position = start + Vector3(
			0.08 * (float(panel_index) - 1.0) * eased,
			-0.12 * eased,
			(1.35 + 0.12 * float(panel_index)) * eased
		)
		panel.rotation = Vector3(
			-1.48 * eased,
			0.08 * (float(panel_index) - 1.0) * eased,
			0.035 * (1.0 - float(panel_index)) * eased
		)
		panel.visible = true
	var crack = wall.get("crack", null)
	if is_instance_valid(crack):
		crack.visible = progress < 0.08


func _restore_infrastructure_presenters(states: Variant) -> void:
	for idx in range(_infrastructure_operations.size()):
		var operation = _infrastructure_operations[idx]
		if not is_instance_valid(operation):
			continue
		var state: Variant = {}
		if states is Dictionary:
			state = (states as Dictionary).get(str(operation.get("operation_id")), {})
		elif states is Array and idx < (states as Array).size():
			# Development saves from before stable-ID snapshots used construction ordering. The operation
			# rejects those unversioned records to baseline rather than guessing at a different identity.
			state = (states as Array)[idx]
		if operation.has_method("restore_state"):
			operation.call("restore_state", state)


func _fragment_vec3(raw: Variant, fallback: Vector3) -> Vector3:
	if raw is Array and raw.size() == 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return fallback

# --- SceneChunk interface (driven by the fragment data) ---

func get_scene_title() -> String:
	return fragment.title if fragment != null and fragment.title != "" else "Data Fragment"

func get_scene_help() -> String:
	return fragment.help if fragment != null else ""

func get_default_character() -> String:
	if fragment != null and fragment.default_character != "":
		return fragment.default_character
	return "aster"

## The level mesh (a modeled environment). The preview host loads + warps it; empty = procedural-only.
func get_environment_model() -> String:
	return fragment.environment_model if fragment != null else ""

func get_spawn_positions() -> Dictionary:
	return (fragment.spawns as Dictionary).duplicate(true) if fragment != null else {}

func get_grid_data() -> Dictionary:
	return (fragment.grid as Dictionary).duplicate(true) if fragment != null and not fragment.grid.is_empty() else {}

## Whether the FIELD regenerates stamina here (false = only shelter ground does; the closed
## economy the stamina-tension fragments are priced in).
func preview_field_stamina_regen() -> bool:
	return bool(fragment.params.get("stamina_field_regen", true)) if fragment != null else true

func get_preview_time_state() -> Dictionary:
	return (fragment.time_state as Dictionary).duplicate(true) if fragment != null else {}

## Anchors = the spawns + whatever the data's params.anchors names (posts, doors, hides, exits).
func get_preview_anchors() -> Dictionary:
	var anchors: Dictionary = {}
	if fragment != null:
		for k in fragment.spawns.keys():
			anchors[str(k)] = fragment.spawns[k]
		var pa: Dictionary = fragment.params.get("anchors", {})
		for k in pa.keys():
			anchors[str(k)] = pa[k]
	return anchors

func get_preview_state() -> Dictionary:
	var downed: Array = []
	var gs = _get_game_state()
	if gs != null and fragment != null:
		for cid_v in fragment.party_ids:
			if gs.is_downed(str(cid_v)):
				downed.append(str(cid_v))
	var lure_active := false
	for fl in _flures:
		if is_instance_valid(fl) and fl.is_active():
			lure_active = true
	var basin_states: Array = []
	for basin in _basins:
		if is_instance_valid(basin):
			basin_states.append(basin.get_state())
	return {
		"phase": _phase,
		"exit_rest_phase": _exit_rest_phase,
		"complete": _phase == "complete",
		"downed": downed,
		"spotted_count": _spotted_count,
		"wipe_count": _wipe_count,
		"lure_active": lure_active,
		"basin_states": basin_states,
	}

func get_preview_abilities() -> Array:
	return AbilityData.for_context("data_fragment")

## A fragment can open with members ALREADY DOWN where they spawned (params.downed_at_start:
## ["aster", ...]) — the retrieve scenarios' opening state. Applied on every reset/restart so the
## story state survives host resets; the DownedBodyManager grows the carry zone off the signal.
func _apply_downed_at_start() -> void:
	var gs = _get_game_state()
	if gs == null or fragment == null:
		return
	for cid_v in (fragment.params.get("downed_at_start", []) as Array):
		var cid := str(cid_v)
		if not gs.characters.has(cid):
			continue
		# The authored opening state, FULLY: back to where the story left them, then down. A reset
		# that re-downed them wherever they happened to lie would drift the scenario.
		if fragment.spawns.has(cid):
			gs.snap_character_to(cid, fragment.spawns[cid])
		if not gs.is_downed(cid):
			gs.down_character(cid)

func reset_preview_state() -> void:
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(_restart_tag())
		sched.cancel_tag(_candid_tag())
		sched.cancel_tag(_concealment_tag())
		sched.cancel_tag(_exit_rest_tag())
		for idx in range(_weak_walls.size()):
			sched.cancel_tag(_weak_wall_tag(idx))
	_restart_deadline = -1.0
	_candid_epoch = -1.0
	_concealment_epoch = -1.0
	_weak_wall_deadlines.clear()
	# A reset re-arms a CLEAN world: members bedded down when it fired must wake, or the stale
	# engine rest blocks every actor-gated interaction in the fresh scenario (reachable since the
	# party rest learned to absorb solo resters and so actually commits mid-test).
	var reset_gs = _get_game_state()
	if reset_gs != null and fragment != null:
		for cid_v in fragment.party_ids:
			if reset_gs.is_resting(str(cid_v)):
				reset_gs.command_stop_rest(str(cid_v))
	_apply_downed_at_start()
	for fl in _flures:
		if is_instance_valid(fl):
			fl.reset_flure()
	for ch in _channels:
		if is_instance_valid(ch):
			ch.reset()
	for basin in _basins:
		if is_instance_valid(basin):
			basin.reset()
	for assist in _assists:
		if is_instance_valid(assist):
			assist.reset_assist()
	_phase = "ready"
	_exit_rest_phase = "ready"
	_clear_exit_rest_commit_context()
	_reset_exit_shelter_receipts_to_registry()
	_spotted_count = 0
	_wipe_count = 0
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.has_method("re_post") and _enemy_posts.has(enemy.char_id):
			enemy.re_post(_enemy_posts[enemy.char_id])
	# Decor back to the authored state: runback-grown Verdanta patches go away and authored
	# ornamentals return to their initial runback appearance.
	for patch in _spread_patches:
		if is_instance_valid(patch):
			_decoratives.erase(patch)
			patch.queue_free()
	_spread_patches.clear()
	for deco_v in _decoratives:
		var deco := deco_v as DecorativeFlora
		if deco != null and is_instance_valid(deco):
			deco.reset_decoration()
	for operation in _infrastructure_operations:
		if is_instance_valid(operation) and operation.has_method("reset_operation"):
			operation.call("reset_operation")
	_fall_pos = Vector3.ZERO
	_scheduled = false
	for idx in range(_weak_walls.size()):
		_retract_weak_wall_source_to_ready(idx)
		_set_weak_wall_presenter(idx, false)
	_apply_exit_shelter_presenters()
	_publish_fragment_authority()
	_set_preview_step((fragment.id if fragment != null and fragment.id != "" else "data_fragment") + "_start")

# Accessors so a test / the host can reach the composed objects.
func flures() -> Array: return _flures
func portals() -> Array: return _portals
func capbages() -> Array: return _capbages
func channels() -> Array: return _channels
func flora() -> Array: return _flora
func enemies() -> Array: return _enemies
func decoratives() -> Array: return _decoratives
func hushblooms() -> Array: return _hushblooms
func basins() -> Array: return _basins
func assists() -> Array: return _assists

## Resolve a spawned basin by its authored tag (the cross-reference id CrossingAssist uses).
func _basin_by_tag(tag: String) -> Variant:
	for basin in _basins:
		if is_instance_valid(basin) and str(basin.get_state().get("tag", "")) == tag:
			return basin
	push_warning("DataFragmentChunk: no basin with tag '%s'" % tag)
	return null
func spike_strips() -> Array: return _spike_strips
func infrastructure_operations() -> Array: return _infrastructure_operations
func infrastructure_fields() -> Array: return _infrastructure_fields

# --- Dictionary readers (tolerant defaults so a sparse .tres still loads) ---

func _v3(d: Dictionary, key: String, def := Vector3.ZERO) -> Vector3:
	var v = d.get(key, def)
	return v if v is Vector3 else def

func _col(d: Dictionary, key: String, def: Color) -> Color:
	var v = d.get(key, def)
	return v if v is Color else def

func _f(d: Dictionary, key: String, def: float) -> float:
	var v = d.get(key, def)
	return float(v) if (v is float or v is int) else def

func _str_arr(d: Dictionary, key: String) -> Array:
	var out: Array = []
	for s in (d.get(key, []) as Array):
		out.append(str(s))
	return out

func _name(spec: Dictionary, fallback: String) -> String:
	return str(spec.get("name", "%s_%d" % [fallback, _flures.size() + _portals.size() + _capbages.size() + _channels.size() + _flora.size()]))
