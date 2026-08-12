extends "res://scripts/scene_chunks/scene_chunk.gd"

const StretchGeneratorScript := preload("res://scripts/generation/stretch_generator.gd")
const CatalogScript := preload("res://scripts/generation/stretch_archetype_catalog.gd")
const CapabilitiesScript := preload("res://scripts/generation/stretch_capabilities.gd")
const SpiralCoordMapScript := preload("res://scripts/generation/spiral_coord_map.gd")
const AtpScarcityClockScript := preload("res://scripts/system/simulation/atp_scarcity_clock.gd")
const GameSettingsScript := preload("res://scripts/system/settings.gd")
const RuntimeRegistryScript := preload("res://scripts/generation/generated_node_runtime_registry.gd")
const BiomesScript := preload("res://scripts/generation/biomes.gd")
const ClimbvineReturnScript := preload("res://scripts/game/objects/climbvine_return.gd")
const BranchSpanProducerScript := preload("res://scripts/game/objects/branch_span_producer.gd")
const GridRiskFieldScript := preload("res://scripts/game/objects/grid_risk_field.gd")
const ZoneTransitionFloorShader := preload("res://resources/zone_transition_floor.gdshader")

const DEFAULT_SPEC_PATH := "res://data/generated_stretches/generated_sample_teaching_first_fork.json"
const PARTY_IDS := ["aster", "peris", "endo"]
const FULL_HP := 100.0
const FULL_STAMINA := 100.0
const FOOD_TEST_NEUTRAL := GameSettingsScript.FOOD_TEST_NEUTRAL
const FOOD_TEST_RETURN_LOOP := GameSettingsScript.FOOD_TEST_EXPEDITION
const FOOD_TEST_SCARCITY := GameSettingsScript.FOOD_TEST_SCARCITY
const SCARCITY_DRAIN_TAG := "generated_stretch_atp_scarcity"
const THEME_HAZARD_TICK := 0.25
const ROUTE_RISK_TICK := 0.5
const ROUTE_RISK_DAMAGE_RATE_SCALE := 1.0
const GENERATED_RUNTIME_AUTHORITY_VERSION := 1
const GENERATED_RUNTIME_AUTHORITY_PREFIX := "runtime:generated_stretch:"
const RESOURCE_CLAIM_VERSION := 1
const RESOURCE_PHASE_AVAILABLE := "available"
const RESOURCE_PHASE_CLAIMING := "claiming"
const RESOURCE_PHASE_CLAIMED := "claimed"
const RESOURCE_KIND_GENERATED := "generated"
const RESOURCE_KIND_PHYSICAL_FOOD := "physical_food"
const EXIT_TRANSACTION_VERSION := 1
const EXIT_PHASE_AVAILABLE := "available"
const EXIT_PHASE_COMMITTING := "committing"
const EXIT_PHASE_COMPLETE := "complete"
const FEEDBACK_BINDING_LYSATE_TO_CARRIER := "physical_lysate_source_to_carrier_v1"
const FEEDBACK_BINDING_PAYLOAD_TO_CARRIER := "physical_payload_source_to_carrier_v1"
const FEEDBACK_BINDING_PARTY_TO_SHELTER := "party_to_canonical_shelter_v1"

@export var default_spec_path := DEFAULT_SPEC_PATH

var _config: Dictionary = {}
var _spec: Dictionary = {}
var _generation_fallback: Dictionary = {}

# When the level is warped onto a helix (the default for a generated stretch — the player walks a linear grid
# while the WORLD spirals around a centre), this is the flat-data<->warped-world map. Null = flat render. The
# data layer (grid/movement/detection) stays flat regardless; only the floor render, node dressing, interactable
# zones, and the installed GameState.coord_map (character render + click inverse) go through it.
var _coord_map = null

# The meta-template (macro shape) this stretch is built on — spiral by default; owns the coord_map + return-point
# strategy. A future config selects other shapes (rectangle/ring hub).
var _meta_template: MetaTemplate = null

# The playable grid the chunk renders and installs. New specs weave branch topology before solving and persist
# that authoritative result in navigation_grid; spine_navigation_grid is only the bare macro path used to derive
# the helix and recovery anchors. `_woven_nav` is the runtime copy plus any meta-template base cells.
var _woven_nav: Dictionary = {}
## Runtime-only coordinate delta introduced when a meta-template prepends and
## renormalizes grid cells. Generated specs remain immutable; published
## interaction contracts are projected into this final grid frame instead.
var _runtime_navigation_cell_delta := Vector2i.ZERO
## Fail-closed construction diagnostics keyed by generated node id. These are
## read by the pure route preflight and never written into the saved spec.
var _runtime_interaction_contract_errors: Dictionary = {}

# Recovery points are tended upper anchors that deploy to a lower deck and only permit the return climb.
# `_drop_downs` is a compatibility readback and must stay empty: no paired forward portal may bypass
# unresolved puzzle beats.
var _drop_downs: Array = []
var _climbvines: Array = []
var _branch_span_producers: Array = []
var _branch_span_by_id: Dictionary = {}
var _branch_gap_cells: Dictionary = {}
# Chunk construction runs before its host installs this generated navigation
# snapshot into GameState. Never bind a mechanism to the outgoing level's grid;
# the host's on_game_state_grid_ready receipt opens this build boundary.
var _branch_span_grid_ready := false

# Salvage caches placed at the far end of each branch spoke — the OPTIONAL reward that makes exploring a spoke
# (instead of pushing straight down the spine to the shelter) worth the day/night time it costs.
var _branch_caches: Array = []
var _physical_food_item_ids: Array[String] = []
var _generated_resource_item_ids: Array[String] = []
var _generated_resource_item_by_node: Dictionary = {}
var _resource_claims: Dictionary = {}
var _physical_food_spawned_count := 0
var _nominal_food_atp := 0.0
var _scarcity_clock = AtpScarcityClockScript.new()
var _catalog := CatalogScript.new()
var _node_markers: Dictionary = {}
var _node_targets: Dictionary = {}
var _node_interactables: Dictionary = {}
var _node_focus_lights: Dictionary = {}
var _decorative_fill_light: OmniLight3D
var _node_content_nodes: Dictionary = {}
var _generated_capbages: Array = []
var _generated_scarpets: Array = []
var _generated_hushblooms: Array = []
var _generated_section_states: Dictionary = {}
var _generated_section_links: Dictionary = {}
var _generated_party_endpoints: Dictionary = {}
var _route_surfaces: Dictionary = {}
var _spatial_feature_roots: Array[Node3D] = []
var _theme_landmark_roots: Array[Node3D] = []
var _theme_setpiece_roots: Array[Node3D] = []
var _infrastructure_runtime: Array = []
var _theme_hazard_accumulator := 0.0
var _theme_hazard_damage_total := 0.0
var _theme_hazard_contacts: Dictionary = {}
var _theme_hazard_armed := false
var _theme_hazard_next_tick := -1.0
var _route_risk_field: Node = null
var _route_risk_contacts: Dictionary = {}
var _restoring_generated_authority := false
var _generated_runtime_baseline: Dictionary = {}
var _zone_transition_floor_cell_count := 0
var _content_marker_count := 0
var _spatial_fixture_count := 0
var _route_choice := ""
var _route_phase := "unstarted"
var _completed_nodes: Array[String] = []
var _activated_routes: Array[String] = []
var _produced_chain_states: Dictionary = {}
var _delivered_resource_nodes: Array[String] = []
var _resources_collected := 0
var _shortcut_unlocked := false
var _shelter_reached := false
var _shelter_rested := false
var _exit_shelter_transaction: Dictionary = {}
var _last_outcome := ""
var _risky_damage_total := 0.0
var _pressure_taken := 0.0
var _rests_taken := 0
var _first_shelter_beat_fired := false
var _unsupported_placeholder_count := 0
var _omitted_content_count := 0
var _active_loadout := "spotlight"
var _active_party: Array[String] = ["aster", "peris", "endo"]
var _active_capabilities: Dictionary = {}
var _enforce_stage := true
var _node_approach_used: Dictionary = {}
var _blocked_nodes: Array[String] = []
var _generated_route_game_state: GameState

var _wipe_recoveries := 0
var _preserve_carried_resources_on_detach := false


func configure_chunk(config: Dictionary) -> void:
	_config = GameSettingsScript.normalize_generated_play_config(config)
	_load_spec_from_config()
	if _built:
		_clear_generated_children()
		_build_chunk()


func is_generation_preview() -> bool:
	return true


func get_generation_seed() -> int:
	if not _spec.is_empty():
		return int(_spec.get("source", {}).get("seed", _spec.get("settings", {}).get("seed", 0)))
	return int(_config.get("seed", 0))


func _exit_tree() -> void:
	_detach_generated_route_arrival_authority()
	_dispose_scarcity_clock()
	_cancel_theme_hazard_tick()
	if not _preserve_carried_resources_on_detach:
		_clear_physical_food_items()


func detach_chunk_host() -> void:
	_detach_generated_route_arrival_authority()
	_dispose_scarcity_clock()
	if not _preserve_carried_resources_on_detach:
		_clear_physical_food_items()
	super.detach_chunk_host()


## Once claimed, lysate is party inventory rather than chunk-owned scenery. The
## roguelite host opts into this handoff immediately before a normal descent; a
## standalone preview reset or a fresh run still clears the outgoing fixture.
func preserve_carried_resources_on_detach() -> void:
	_preserve_carried_resources_on_detach = true


func _build_chunk() -> void:
	_ensure_spec_loaded()
	_ensure_graybox_layout()
	_ensure_navigation_layout()
	# Tall generated architecture uses the shared camera fade. The outline-safe clip
	# prevents its dissolve from feeding white speckles into the outline pass.
	set_meta("camera_occlusion_outline_safe_clip", true)
	_watch_for_party_wipe()

	_cancel_scarcity_drain()
	_clear_physical_food_items()
	name = "GeneratedStretchChunk_%s" % str(_spec.get("id", "stretch"))
	_unsupported_placeholder_count = 0
	_omitted_content_count = 0
	_content_marker_count = 0
	_spatial_fixture_count = 0
	_node_markers.clear()
	_node_targets.clear()
	_node_interactables.clear()
	_node_focus_lights.clear()
	_decorative_fill_light = null
	_node_content_nodes.clear()
	_generated_capbages.clear()
	_generated_scarpets.clear()
	_generated_hushblooms.clear()
	_generated_section_states.clear()
	_generated_section_links.clear()
	for endpoint_v in _generated_party_endpoints.values():
		if is_instance_valid(endpoint_v) and endpoint_v is Node:
			(endpoint_v as Node).queue_free()
	_generated_party_endpoints.clear()
	_route_surfaces.clear()
	_spatial_feature_roots.clear()
	_theme_landmark_roots.clear()
	_theme_setpiece_roots.clear()
	_infrastructure_runtime.clear()
	_theme_hazard_accumulator = 0.0
	_theme_hazard_damage_total = 0.0
	_theme_hazard_contacts.clear()
	_route_risk_field = null
	_route_risk_contacts.clear()
	_zone_transition_floor_cell_count = 0
	_drop_downs.clear()
	_climbvines.clear()
	_branch_span_producers.clear()
	_branch_span_by_id.clear()
	_branch_span_grid_ready = false
	_branch_gap_cells.clear()
	_branch_caches.clear()
	_physical_food_spawned_count = 0
	_nominal_food_atp = 0.0
	_woven_nav = {}
	_runtime_navigation_cell_delta = Vector2i.ZERO
	_runtime_interaction_contract_errors.clear()
	_build_coord_map()
	_ensure_woven_grid()
	_refresh_branch_gap_cells()

	# The tiled walkable floor IS the level — abstract scaffolding over it (a big foundation slab, straight
	# route-connector boxes, big role pads, a palette legend) would be redundant clutter. Only the
	# floor + the per-node markers/interactables the player actually uses are built.
	_build_foundation()

	# Everything _build_generated_nodes adds (markers, labels, content, interactables, outline targets) is authored
	# FLAT; capture the boundary so the warp pass below re-seats only those children onto the helix — the floor
	# (warped per vertex in _build_walkable_floor) and the fill light are placed already warped, and taking the
	# warp a second time would carry them off the deck.
	var flat_child_start := get_child_count()
	_build_spatial_features()
	_build_theme_landmarks()
	_build_infrastructure_operations()
	_build_theme_setpieces()
	_build_route_risk_field()
	_build_generated_nodes()

	# Branch caches are authored FLAT like the node dressing, so build them BEFORE the warp pass and let it re-seat
	# them onto the helix too (keeps their interactable + outline target together on the deck).
	_build_branch_content()
	_configure_food_branch_caches()
	if _coord_map != null:
		for i in range(flat_child_start, get_child_count()):
			_warp_child(get_child(i))
		# Physical-source pick hulls cannot be centred until every independently
		# warped marker mesh has reached its final transform. The shared helper only
		# touches targets carrying the explicit generated-source opt-in contract.
		align_opt_in_pick_targets_to_highlights()
	_build_return_points()
	_ensure_branch_span_producers_ready()
	_register_shelter_regions()
	reset_preview_state()


## Shelter SANCTUARY registration: the entry pad and every shelter-role node become GameState
## shelter regions, sized by their pad footprints — the detection gate, the strike gate, and the
## revive watch all read these, so "standing in the shelter" actually means safe (a shelter that
## was only a marker let enemies attack you inside it — the 2026-07-12 report). Regions live in
## the FLAT data frame (character positions stay flat under the helix warp) and are logged
## (KIND_ADD_SHELTER), like interactable registration.
func _register_shelter_regions() -> void:
	var gs = _get_game_state()
	if gs == null or not gs.has_method("add_shelter_region"):
		return
	var done := {}
	for node_v in _spec.get("nodes", []) as Array:
		var node := node_v as Dictionary
		var role := str(node.get("role", ""))
		var nid := str(node.get("id", ""))
		if not (
			role in ["shelter", "shelter_arrival", "entry"] or nid in ["entry", "exit_shelter"]
		):
			continue
		var p := _vec3(node.get("position", []), Vector3.INF)
		if p == Vector3.INF:
			continue
		var half := _node_pad_size(role if role != "" else "shelter") * 0.5
		gs.add_shelter_region(
			Vector2(p.x - half.x - 0.4, p.z - half.z - 0.4),
			Vector2(p.x + half.x + 0.4, p.z + half.z + 0.4)
		)
		done[nid] = true

	# a spec may carry entry/exit as bare anchors rather than nodes — cover those too
	for aid in ["entry", "exit_shelter"]:
		if done.has(aid):
			continue
		var ap := _anchor_position(str(aid))
		if ap == Vector3.INF:
			continue
		gs.add_shelter_region(Vector2(ap.x - 3.3, ap.z - 2.6), Vector2(ap.x + 3.3, ap.z + 2.6))


func _food_test_mode() -> String:
	var requested := str(_config.get("food_test", FOOD_TEST_NEUTRAL)).strip_edges().to_lower()
	if requested in [FOOD_TEST_RETURN_LOOP, FOOD_TEST_SCARCITY]:
		return requested
	return FOOD_TEST_NEUTRAL


func _game_mode_id() -> String:
	# food_test controls the active mechanics, so an explicit value is authoritative.
	# This keeps the briefing truthful even if a caller supplies a stale mode label.
	if _config.has("food_test"):
		match _food_test_mode():
			FOOD_TEST_RETURN_LOOP:
				return "expedition"
			FOOD_TEST_SCARCITY:
				return "scarcity"
			_:
				return "neutral"
	var configured := str(_config.get("game_mode", "")).strip_edges().to_lower()
	if configured in ["neutral", "expedition", "scarcity"]:
		return configured
	match _food_test_mode():
		FOOD_TEST_RETURN_LOOP:
			return "expedition"
		FOOD_TEST_SCARCITY:
			return "scarcity"
	return "neutral"


func _generated_completion_ready() -> bool:
	return _shelter_rested and _route_phase == "complete" \
		and _last_outcome == "success" and _first_shelter_beat_fired


func _food_economy_help() -> String:
	var physical_rule := (
		"Optional detour caches hold carried lysate; it occupies one hand and restores only its "
		+ "carrier after endocytosis. Shelter rest spends one ATP per member who starts rest."
	)
	if _food_test_mode() == FOOD_TEST_SCARCITY:
		return (
			"EXPERIMENTAL SCARCITY — First movement starts a %s ATP drain every %.0f seconds "
			+ "per character. ATP can reach zero; a later tick begun at zero costs %s HP, "
			+ "which an active WRAP can absorb. %s"
		) % [
			_atp_amount_text(_scarcity_drain_amount()),
			_scarcity_drain_interval(),
			_atp_amount_text(_scarcity_zero_atp_hp_drain()),
			physical_rule,
		]
	return "FOOD — No passive ATP drain. %s" % physical_rule


func _food_test_settings() -> Dictionary:
	var raw: Variant = _config.get("food_test_settings", {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


func _scarcity_drain_interval() -> float:
	return maxf(
		AtpScarcityClockScript.MIN_INTERVAL_SECONDS,
		float(_food_test_settings().get(
			"drain_interval_seconds", AtpScarcityClockScript.DEFAULT_INTERVAL_SECONDS
		))
	)


func _scarcity_drain_amount() -> float:
	return maxf(
		0.0,
		GameState.quantize_atp(float(_food_test_settings().get(
			"drain_atp", AtpScarcityClockScript.DEFAULT_DRAIN_ATP
		)))
	)


func _scarcity_zero_atp_hp_drain() -> float:
	return maxf(
		0.0,
		float(_food_test_settings().get(
			"zero_atp_hp_drain", AtpScarcityClockScript.DEFAULT_ZERO_ATP_HP_DRAIN
		))
	)


func _theme_help() -> String:
	if str(_spec.get("biome", "")) != "cleanstreets":
		return ""
	return " CLEANSTREETS — SAFE avoids marked anti-loiter cells when a detour exists; DIRECT crosses the studs and continuously spends health for time."


## Whether this stretch renders as a helix (the default) or stays a flat grid. Generated stretches spiral so a
## long level curls compactly around a centre (the player still walks a linear grid); a hand-authored builder
## level or a test can opt OUT with config "spiral": false to keep the painted flat layout.
func _spiral_enabled() -> bool:
	if _config.has("spiral"):
		return bool(_config["spiral"])

	# A hand-authored / ASCII level (from the builder) plays as the FLAT layout the user drew — no spiral warp,
	# no woven branch spokes. Fixed specs identify that authored spatial
	# projection explicitly; the schema check keeps legacy local drafts
	# readable without pretending they satisfy current acceptance.
	if str(_spec.get("source", {}).get("spatial_projection", "")) \
			== "authored_flat_v1" \
			or str(_spec.get("schema", "")) == "authored_ascii_v1":
		return false
	return true


## Resolve the META-TEMPLATE (macro shape) for this stretch. The hub SHAPE is a PARAMETER: pass config
## "hub_shape" = {type:"circle"|"rect"|"hexagon"|"triangle"|"polygon", ...} to generate the level AROUND that shape
## as its hub (circle == the plain spiral). Flat/authored levels get the no-warp base template.
func _resolve_meta_template() -> MetaTemplate:
	if not _spiral_enabled():
		return MetaTemplate.new()
	var shape = _config.get("hub_shape", null)
	if shape is Dictionary and not (shape as Dictionary).is_empty():
		return HubMetaTemplate.new(shape)
	match str(_config.get("meta_template", "spiral")):
		"flat":
			return MetaTemplate.new()
		"hub":
			return HubMetaTemplate.new({"type": "circle"})
		_:
			return SpiralMetaTemplate.new()


## Build the coord_map for this stretch THROUGH its meta-template (the spiral warps onto a descending helix; the
## flat template returns null). Cleared + rebuilt every time the chunk (re)builds.
func _build_coord_map() -> void:
	_meta_template = _resolve_meta_template()
	var spine_nav := _spine_navigation_grid()
	var profile := _spatial_profile()
	if (
		_meta_template != null
		and _meta_template.template_id() == "spiral"
		and not profile.is_empty()
	):
		_coord_map = SpiralCoordMapScript.from_grid(
			spine_nav,
			float(profile.get("spiral_turns", 0.0)),
			float(profile.get("spiral_min_radius", 0.0)),
			float(profile.get("spiral_descent_per_turn", 6.0)),
			float(profile.get("spiral_base_y", 0.45))
		)
	else:
		_coord_map = _meta_template.build_coord_map(spine_nav)


## The bare macro path is deliberately separate from the authoritative playable topology. It is used only by
## coordinate maps and meta-template recovery anchors; all pathing, collision, solving, and replay use
## `navigation_grid`. Legacy specs predate the split and fall back to that key.
func _spine_navigation_grid() -> Dictionary:
	var spine_v: Variant = _spec.get("spine_navigation_grid", {})
	if spine_v is Dictionary and not (spine_v as Dictionary).is_empty():
		return spine_v as Dictionary
	return _spec.get("navigation_grid", {})


## Presentation-only dimensions for a generated stretch. These never rewrite the semantic node graph or replay
## decisions: WFC consumes the room pitch while the coord-map consumes the helix values. A chunk config may
## override the saved profile for QA without silently changing the authored default.
func _spatial_profile() -> Dictionary:
	var profile: Dictionary = _spec.get("settings", {}).get("spatial_profile", {}).duplicate(true)
	var override_v: Variant = _config.get("spatial_profile", {})
	if override_v is Dictionary:
		profile.merge(override_v as Dictionary, true)
	return profile


func get_coord_map():
	return _coord_map


## A spiral's authored X axis becomes its tangent. The ordinary +Z camera then
## looks straight down the deployment formation and through the stacked turns,
## hiding otherwise healthy party members. Interpret this radial offset in the
## live coord-map basis so the current deck stays face-on throughout the route.
func get_preview_camera_profile() -> Dictionary:
	if _coord_map == null:
		return {}
	return {
		"follow_offset": Vector3(9.0, 12.0, 0.0),
		"follow_basis_map": _coord_map,
		"reset_yaw": true,
	}


## The playable grid = the spine woven with branch spokes (when spiralling). Built once; both the floor render and
## the installed GameState grid read this, so the walkable floor, collision, detection and pathing all agree.
func _ensure_woven_grid() -> void:
	if not _woven_nav.is_empty():
		return
	_runtime_navigation_cell_delta = Vector2i.ZERO
	_ensure_navigation_layout()
	var playable: Dictionary = _spec.get("navigation_grid", {})
	if playable.is_empty():
		return
	# Current specs already own their branch topology before solver analysis. A `branches` key, including an
	# intentionally empty array, marks that authoritative schema. Runtime weaving remains only for legacy specs.
	if playable.has("branches"):
		_woven_nav = playable.duplicate(true)
	elif _spiral_enabled() and bool(_config.get("branches", true)):
		var BranchWeaver = load("res://scripts/generation/stretch_branch_weaver.gd")
		var weave_options := {
			"seed": _weave_seed(),
			"tier":
			str(
				_spec.get("source", {}).get(
					"complexity_tier",
					_spec.get("settings", {}).get("complexity_tier", "standard")
				)
			),
			"stage": _progression_stage(),
		}
		var profile := _spatial_profile()
		if profile.has("branch_room_count"):
			weave_options["count"] = maxi(0, int(profile["branch_room_count"]))
		_woven_nav = (
			BranchWeaver
			. weave(playable, weave_options)
		)
	else:
		_woven_nav = playable.duplicate(true)

	# The hub template's flat BASE FLOOR (the shape as a floor) — prepend it before the entry so the party rests +
	# walks on it, then steps onto the descending deck. The coord_map maps these front cells (s < 0) to the flat base.
	# Older persisted multi-level specs flattened every woven spoke into level 0,
	# even when its only spine doorway (and its causal consumer cut) lived on an
	# upper level. Seat each branch on the level containing its real non-branch
	# doorway before either the rendered floor or GameState grid is built.
	_woven_nav = _align_branch_navigation_levels(_woven_nav)

	var base_n := 0
	if _meta_template != null and _meta_template.has_method("base_cells"):
		base_n = int(_meta_template.call("base_cells"))
	if base_n > 0:
		_woven_nav = _prepend_base_to_grid(_woven_nav, base_n)


## Deterministic seed for the branch weave — from the level's own seed so the same spec always grows the same
## spokes (replay-safe; the chunk reproduces them every build).
func _align_branch_navigation_levels(nav: Dictionary) -> Dictionary:
	var level_entries: Array = nav.get("level_cells", [])
	var branches: Array = nav.get("branches", [])
	if int(nav.get("level_count", 1)) <= 1 \
			or level_entries.is_empty() or branches.is_empty():
		return nav
	var out := nav.duplicate(true)
	var level_sets := {}
	var entry_templates := {}
	for entry_v in level_entries:
		if not (entry_v is Dictionary):
			continue
		var entry := (entry_v as Dictionary).duplicate(true)
		var level := int(entry.get("level", 0))
		var cells := {}
		for cell_v in entry.get("cells", []):
			var cell := _cell_from_address(cell_v)
			if cell != Vector2i(-2147483648, -2147483648):
				cells[cell] = true
		level_sets[level] = cells
		entry_templates[level] = entry
	if level_sets.is_empty():
		return nav

	var branch_cell_union := {}
	for branch_v in branches:
		if not (branch_v is Dictionary):
			continue
		for cell_v in (branch_v as Dictionary).get("cells", []):
			var cell := _cell_from_address(cell_v)
			if cell != Vector2i(-2147483648, -2147483648):
				branch_cell_union[cell] = true

	var aligned_branches: Array = []
	var branch_level_cells := {}
	for branch_v in branches:
		if not (branch_v is Dictionary):
			continue
		var branch := (branch_v as Dictionary).duplicate(true)
		var neck := _cell_from_address(branch.get("neck", []))
		var contract := (branch.get("causal_contract", {}) as Dictionary).duplicate(true)
		var consumer_cells := _branch_consumer_cells(contract)
		var declared_level := int(branch.get(
			"navigation_level", contract.get("producer_navigation_level", 0)
		))
		var doorway_neighbors_by_level: Dictionary = {}
		var consumer_coverage_by_level: Dictionary = {}
		var level_ids: Array = level_sets.keys()
		level_ids.sort()
		for level_v in level_ids:
			var level := int(level_v)
			var allowed := level_sets[level] as Dictionary
			var doorway_neighbors := 0
			if neck != Vector2i(-2147483648, -2147483648):
				for direction in [
					Vector2i.LEFT,
					Vector2i.RIGHT,
					Vector2i.UP,
					Vector2i.DOWN,
				]:
					var neighbor: Vector2i = neck + (direction as Vector2i)
					if allowed.has(neighbor) and not branch_cell_union.has(neighbor):
						doorway_neighbors += 1
			var consumer_coverage := 0
			for consumer in consumer_cells:
				if allowed.has(consumer):
					consumer_coverage += 1
			doorway_neighbors_by_level[level] = doorway_neighbors
			consumer_coverage_by_level[level] = consumer_coverage

		# The branch producer belongs to its authored doorway. A consumer on another
		# stacked deck is an effect, not permission to lift the producer off a valid
		# declared floor. Compatibility realignment is reserved for old specs whose
		# declared floor has no physical doorway at all.
		var best_level: int = declared_level
		if int(doorway_neighbors_by_level.get(declared_level, 0)) <= 0:
			var best_doorway_count: int = 0
			var best_consumer_tiebreak: int = -1
			for level_v in level_ids:
				var candidate_level: int = int(level_v)
				var doorway_count: int = int(
					doorway_neighbors_by_level.get(candidate_level, 0)
				)
				var consumer_tiebreak: int = int(
					consumer_coverage_by_level.get(candidate_level, 0)
				)
				if doorway_count > best_doorway_count or (
					doorway_count == best_doorway_count
					and doorway_count > 0
					and consumer_tiebreak > best_consumer_tiebreak
				):
					best_doorway_count = doorway_count
					best_consumer_tiebreak = consumer_tiebreak
					best_level = candidate_level
		var consumer_level: int = best_level
		if not consumer_cells.is_empty():
			var best_consumer_coverage: int = -1
			for level_v in level_ids:
				var consumer_candidate_level: int = int(level_v)
				var coverage: int = int(
					consumer_coverage_by_level.get(consumer_candidate_level, 0)
				)
				if coverage > best_consumer_coverage or (
					coverage == best_consumer_coverage
					and consumer_candidate_level == best_level
				):
					best_consumer_coverage = coverage
					consumer_level = consumer_candidate_level
		branch["navigation_level"] = best_level
		contract["producer_navigation_level"] = best_level
		if not consumer_cells.is_empty():
			contract["consumer_navigation_level"] = consumer_level
		branch["causal_contract"] = contract
		if not branch_level_cells.has(best_level):
			branch_level_cells[best_level] = {}
		for cell_v in branch.get("cells", []):
			var cell := _cell_from_address(cell_v)
			if cell != Vector2i(-2147483648, -2147483648):
				(branch_level_cells[best_level] as Dictionary)[cell] = true
		aligned_branches.append(branch)

	# Remove old flattened copies, then add every spoke to exactly one level.
	for level_v in level_sets.keys():
		var cells := level_sets[level_v] as Dictionary
		for branch_cell in branch_cell_union.keys():
			cells.erase(branch_cell)
	for level_v in branch_level_cells.keys():
		if not level_sets.has(level_v):
			level_sets[level_v] = {}
			entry_templates[level_v] = {"level": int(level_v)}
		var cells := level_sets[level_v] as Dictionary
		for branch_cell in (branch_level_cells[level_v] as Dictionary).keys():
			cells[branch_cell] = true

	var aligned_entries: Array = []
	var aligned_levels: Array = level_sets.keys()
	aligned_levels.sort()
	for level_v in aligned_levels:
		var entry := (entry_templates[level_v] as Dictionary).duplicate(true)
		entry["level"] = int(level_v)
		entry["cells"] = _sorted_grid_cell_addresses(
			(level_sets[level_v] as Dictionary).keys()
		)
		aligned_entries.append(entry)
	out["branches"] = aligned_branches
	out["level_cells"] = aligned_entries
	return out


func _sorted_grid_cell_addresses(cells: Array) -> Array:
	var ordered: Array[Vector2i] = []
	for cell_v in cells:
		var cell := _cell_from_address(cell_v)
		if cell != Vector2i(-2147483648, -2147483648):
			ordered.append(cell)
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	var result: Array = []
	for cell in ordered:
		result.append([cell.x, cell.y])
	return result


func _weave_seed() -> int:
	return int(_spec.get("source", {}).get("seed", _spec.get("settings", {}).get("seed", 0)))


func _nav_grid() -> Dictionary:
	_ensure_woven_grid()
	return _woven_nav if not _woven_nav.is_empty() else _spec.get("navigation_grid", {})


func _refresh_branch_gap_cells() -> void:
	_branch_gap_cells.clear()
	for branch_v in _nav_grid().get("branches", []):
		if not (branch_v is Dictionary):
			continue
		var branch := branch_v as Dictionary
		if str(branch.get("role", "")) != "mandatory_producer":
			continue
		var contract: Dictionary = branch.get("causal_contract", {})
		for consumer in _branch_consumer_cells(contract):
			_branch_gap_cells[consumer] = str(branch.get("id", ""))


func _cell_from_address(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Vector2:
		var vector := value as Vector2
		return Vector2i(int(vector.x), int(vector.y))
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	return Vector2i(-2147483648, -2147483648)


func _branch_consumer_cells(contract: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var addresses: Array = contract.get("consumer_cells", [])
	if addresses.is_empty():
		addresses = [contract.get("consumer_cell", [])]
	for address_v in addresses:
		var cell := _cell_from_address(address_v)
		if cell != Vector2i(-2147483648, -2147483648) and not result.has(cell):
			result.append(cell)
	return result


## Prepend a flat BASE FLOOR block (base_cells x height) immediately BEFORE the
## spine's first walkable column, then renormalise so indices are >= 0 again.
## Generated grids retain padding inside their declared bounds, so grid column zero
## is not necessarily floor; attaching there leaves an invisible non-walkable moat
## between the base and entry. Shifting the origin in lockstep preserves every
## existing cell's WORLD position. Records _base_x_range for shelter/spawn placement.
var _base_x_range := Vector2i(0, 0)  # [min_x, max_x) of base columns in the FINAL (shifted) grid; empty if none


func _prepend_base_to_grid(nav: Dictionary, base_cells: int) -> Dictionary:
	if base_cells <= 0 or nav.is_empty():
		return nav
	var out: Dictionary = nav.duplicate(true)
	var cs := float(nav.get("cell_size", 1.0))
	var height := int(nav.get("height", 1))
	var cells := {}
	var playable_min_x := 2147483647
	for c in nav.get("walkable_cells", []):
		var cell := Vector2i(int(c[0]), int(c[1]))
		cells[cell] = true
		playable_min_x = mini(playable_min_x, cell.x)
	if playable_min_x == 2147483647:
		return nav
	var base_start_x := playable_min_x - base_cells
	for bx in range(base_start_x, playable_min_x):
		for bz in range(height):
			cells[Vector2i(bx, bz)] = true

	var min_x := 2147483647
	var min_z := 2147483647
	var max_x := -2147483647
	var max_z := -2147483647
	# Renormalise (shift so min index = 0); origin shifts the opposite way so world positions are preserved.
	for v in cells.keys():
		min_x = mini(min_x, v.x)
		min_z = mini(min_z, v.y)
		max_x = maxi(max_x, v.x)
		max_z = maxi(max_z, v.y)
	var shift := Vector2i(min_x, min_z)
	# Every persisted interaction vertex uses the pre-template frame. The final
	# navigation data below stores `cell - shift`, so record that exact projection
	# once and apply it only to runtime copies of those contracts.
	_runtime_navigation_cell_delta = -shift
	var origin: Array = out.get("origin", [0.0, 0.45, 0.0])
	out["origin"] = [
		float(origin[0]) + float(shift.x) * cs,
		float(origin[1]),
		float(origin[2]) + float(shift.y) * cs
	]
	out["width"] = (max_x - min_x) + 1
	out["height"] = (max_z - min_z) + 1
	out["walkable_cells"] = _shift_cell_list(cells.keys(), shift)
	out["risk_cell_list"] = _shift_risk_list(out.get("risk_cell_list", []), shift)
	out["route_cells"] = _shift_route_cells(out.get("route_cells", {}), shift)
	out["links"] = _shift_link_list(out.get("links", []), shift)
	out["branches"] = _shift_branch_list(out.get("branches", []), shift)
	var level_cells: Array = out.get("level_cells", [])
	if not level_cells.is_empty():
		var base_set := {}
		for bx in range(base_start_x, playable_min_x):
			for bz in range(height):
				base_set[Vector2i(bx, bz)] = true
		out["level_cells"] = _shift_levels_with_base(level_cells, base_set, shift)

	# The base columns, in the FINAL shifted frame, are the first base_cells columns.
	_base_x_range = Vector2i(0, base_cells)
	return out


func _shift_cell_list(keys, shift: Vector2i) -> Array:
	var arr: Array = []
	for v in keys:
		arr.append(v)
	arr.sort_custom(func(p, q): return (p.y * 100000 + p.x) < (q.y * 100000 + q.x))
	var out: Array = []
	for v in arr:
		out.append([v.x - shift.x, v.y - shift.y])
	return out


func _shift_risk_list(risk_list: Array, shift: Vector2i) -> Array:
	var out: Array = []
	for r in risk_list:
		var c: Array = r.get("cell", [0, 0])
		out.append(
			{
				"cell": [int(c[0]) - shift.x, int(c[1]) - shift.y],
				"penalty": float(r.get("penalty", 0.0)),
				"recoverable": bool(r.get("recoverable", true))
			}
		)
	return out


func _shift_route_cells(route_cells: Dictionary, shift: Vector2i) -> Dictionary:
	var out := {}
	for rid in route_cells.keys():
		var src: Dictionary = route_cells[rid]
		var cells_out: Array = []
		for c in src.get("cells", []):
			cells_out.append([int(c[0]) - shift.x, int(c[1]) - shift.y])
		out[rid] = {"cells": cells_out, "kind": str(src.get("kind", ""))}
	return out


func _shift_link_list(links: Array, shift: Vector2i) -> Array:
	var out: Array = []
	for lk in links:
		var c: Array = lk.get("cell", [0, 0])
		out.append(
			{
				"cell": [int(c[0]) - shift.x, int(c[1]) - shift.y],
				"from": int(lk.get("from", 0)),
				"to": int(lk.get("to", 0)),
				"type": str(lk.get("type", "ramp"))
			}
		)
	return out


## Branch contracts address exact producer/consumer cells. The meta-template base renormalizes every grid cell,
## so these addresses must move in the same frame as walkable/risk/link data or the visible mechanism and its
## navigation blocker would silently point at different places.
func _shift_branch_list(branches: Array, shift: Vector2i) -> Array:
	var out: Array = []
	for branch_v in branches:
		if not (branch_v is Dictionary):
			continue
		var branch := (branch_v as Dictionary).duplicate(true)
		branch["neck"] = _shift_cell_address(branch.get("neck", []), shift)
		var shifted_cells: Array = []
		for cell_v in branch.get("cells", []):
			shifted_cells.append(_shift_cell_address(cell_v, shift))
		branch["cells"] = shifted_cells
		var contract: Dictionary = branch.get("causal_contract", {}).duplicate(true)
		if not contract.is_empty():
			contract["producer_cell"] = _shift_cell_address(
				contract.get("producer_cell", []), shift
			)
			contract["consumer_cell"] = _shift_cell_address(
				contract.get("consumer_cell", []), shift
			)
			var shifted_consumers: Array = []
			for consumer_v in contract.get("consumer_cells", []):
				shifted_consumers.append(_shift_cell_address(consumer_v, shift))
			if not shifted_consumers.is_empty():
				contract["consumer_cells"] = shifted_consumers
			if contract.has("spine_column"):
				contract["spine_column"] = int(contract["spine_column"]) - shift.x
			branch["causal_contract"] = contract
		out.append(branch)
	return out


func _shift_cell_address(value: Variant, shift: Vector2i) -> Array:
	if value is Array and (value as Array).size() >= 2:
		return [int((value as Array)[0]) - shift.x, int((value as Array)[1]) - shift.y]
	if value is Vector2i:
		var cell := value as Vector2i
		return [cell.x - shift.x, cell.y - shift.y]
	return []


static func _interaction_contract_vertex(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var raw := value as Dictionary
	var cell_v: Variant = raw.get("cell", null)
	var cell: Vector2i
	if cell_v is Vector2i:
		cell = cell_v as Vector2i
	elif cell_v is Vector2 and (cell_v as Vector2).is_finite():
		var vector := cell_v as Vector2
		cell = Vector2i(int(vector.x), int(vector.y))
	elif cell_v is Array and (cell_v as Array).size() >= 2:
		cell = Vector2i(int((cell_v as Array)[0]), int((cell_v as Array)[1]))
	else:
		return {}
	if not raw.has("level"):
		return {}
	return {"cell": cell, "level": int(raw.get("level", -1))}


static func _project_interaction_vertex_to_runtime_grid(
		value: Variant, cell_delta: Vector2i
	) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var projected := (value as Dictionary).duplicate(true)
	var vertex := _interaction_contract_vertex(value)
	if vertex.is_empty():
		return projected
	var cell: Vector2i = vertex.get("cell", Vector2i.ZERO)
	projected["cell"] = [cell.x + cell_delta.x, cell.y + cell_delta.y]
	projected["level"] = int(vertex.get("level", 0))
	return projected


## Project a persisted interaction contract into the final runtime grid frame.
## The input is never modified; this is intentionally a pure data transform so
## Hub base-floor renormalization cannot stale the source snapshot.
static func _project_interaction_approach_to_runtime_grid(
		authored: Dictionary, cell_delta: Vector2i
	) -> Dictionary:
	if authored.is_empty():
		return {}
	var projected := authored.duplicate(true)
	for key in ["approach_vertex", "required_from_vertex", "component_anchor"]:
		if projected.has(key):
			projected[key] = _project_interaction_vertex_to_runtime_grid(
				authored.get(key, {}), cell_delta)
	var projected_region: Array = []
	for vertex_v in authored.get("region_vertices", []):
		projected_region.append(
			_project_interaction_vertex_to_runtime_grid(vertex_v, cell_delta))
	projected["region_vertices"] = projected_region
	var component_anchor := _interaction_contract_vertex(
		projected.get("component_anchor", {}))
	if not component_anchor.is_empty() \
			and str(projected.get("component_id", "")).begins_with(
				"entry_component:"):
		var anchor_cell: Vector2i = component_anchor.get("cell", Vector2i.ZERO)
		projected["component_id"] = "entry_component:%d:%d:%d" % [
			int(component_anchor.get("level", 0)),
			anchor_cell.x,
			anchor_cell.y,
		]
	return projected


static func _project_entry_component_id(
		value: String, cell_delta: Vector2i
	) -> String:
	var parts := value.split(":")
	if parts.size() != 4 or parts[0] != "entry_component" \
			or not parts[1].is_valid_int() \
			or not parts[2].is_valid_int() \
			or not parts[3].is_valid_int():
		return value
	return "entry_component:%d:%d:%d" % [
		int(parts[1]),
		int(parts[2]) + cell_delta.x,
		int(parts[3]) + cell_delta.y,
	]


## Convert the generator's persisted content receipt into the live interaction
## controller's accepted-region shape. This is a frame transform only: it never
## chooses a new standing cell or widens the generator-approved region.
static func _project_content_navigation_to_runtime_interaction_region(
		authored: Dictionary, cell_delta: Vector2i
	) -> Dictionary:
	if authored.is_empty():
		return {}
	var approach := _project_interaction_vertex_to_runtime_grid(
		authored.get("content_vertex", {}), cell_delta)
	var projected_region: Array = []
	var region_v: Variant = authored.get("reachable_region", null)
	if region_v is Array:
		for vertex_v in region_v as Array:
			projected_region.append(
				_project_interaction_vertex_to_runtime_grid(vertex_v, cell_delta))
	return {
		"contract_id": str(authored.get("contract_id", "")),
		"binding_id": str(authored.get("binding_id", "")),
		"kind": str(authored.get("kind", "")),
		"component_id": _project_entry_component_id(
			str(authored.get("component_id", "")), cell_delta),
		"content_vertex": approach.duplicate(true),
		"approach_vertex": approach,
		"region_vertices": projected_region,
		"radius": authored.get("radius", null),
		"arrival_policy": str(authored.get("arrival_policy", "")),
	}


static func _interaction_component_vertex(value: String) -> Dictionary:
	var parts := value.split(":")
	if parts.size() != 4 or parts[0] != "entry_component" \
			or not parts[1].is_valid_int() \
			or not parts[2].is_valid_int() \
			or not parts[3].is_valid_int():
		return {}
	return {
		"cell": Vector2i(int(parts[2]), int(parts[3])),
		"level": int(parts[1]),
	}


func _runtime_interaction_vertex_walkable(
		nav: Dictionary, value: Variant
	) -> bool:
	var vertex := _interaction_contract_vertex(value)
	if vertex.is_empty():
		return false
	var cell: Vector2i = vertex.get("cell", Vector2i.ZERO)
	var level := int(vertex.get("level", -1))
	if level < 0 or level >= int(nav.get("level_count", 1)) \
			or cell.x < 0 or cell.y < 0 \
			or cell.x >= int(nav.get("width", 0)) \
			or cell.y >= int(nav.get("height", 0)):
		return false
	var global_walkable := false
	for address_v in nav.get("walkable_cells", []):
		if _cell_from_address(address_v) == cell:
			global_walkable = true
			break
	if not global_walkable:
		return false
	for entry_v in nav.get("level_cells", []):
		if not (entry_v is Dictionary) \
				or int((entry_v as Dictionary).get("level", -1)) != level:
			continue
		for address_v in (entry_v as Dictionary).get("cells", []):
			if _cell_from_address(address_v) == cell:
				return true
		return false
	return true


func _runtime_interaction_vertex_position(
		nav: Dictionary, value: Variant
	) -> Vector3:
	var vertex := _interaction_contract_vertex(value)
	if vertex.is_empty():
		return Vector3.INF
	var origin := _vec3(nav.get("origin", []), Vector3.ZERO)
	var cell_size := float(nav.get("cell_size", 1.0))
	var level_height := float(nav.get("level_height", 0.0))
	var cell: Vector2i = vertex.get("cell", Vector2i.ZERO)
	return origin + Vector3(
		(float(cell.x) + 0.5) * cell_size,
		float(int(vertex.get("level", 0))) * level_height,
		(float(cell.y) + 0.5) * cell_size
	)


func _invalid_runtime_interaction_contract(
		code: String, detail: String
	) -> Dictionary:
	return {
		"accepted": false,
		"code": code,
		"message": "This object's marked approach does not match the live navigation grid.",
		"cue": "RESOLVE FIRST // ROUTE CONTRACT INVALID",
		"detail": detail,
	}


## Structural validation is performed against the final rendered/installed
## navigation snapshot, never the pre-template generated spec.
func _validate_runtime_interaction_approach(
		contract: Dictionary, source_position: Vector3
	) -> Dictionary:
	if str(contract.get("contract_id", "")) != "generated_interaction_approach_v1":
		return _invalid_runtime_interaction_contract(
			"interaction_contract_version", "unexpected contract id")
	var nav := _nav_grid()
	var primary := _interaction_contract_vertex(
		contract.get("approach_vertex", {}))
	if primary.is_empty() or not _runtime_interaction_vertex_walkable(
			nav, contract.get("approach_vertex", {})):
		return _invalid_runtime_interaction_contract(
			"interaction_primary_unwalkable", "primary vertex is not walkable")
	var primary_in_region := false
	var region: Array = contract.get("region_vertices", [])
	if region.is_empty():
		return _invalid_runtime_interaction_contract(
			"interaction_region_empty", "accepted region is empty")
	for vertex_v in region:
		var vertex := _interaction_contract_vertex(vertex_v)
		if vertex.is_empty() or not _runtime_interaction_vertex_walkable(nav, vertex_v):
			return _invalid_runtime_interaction_contract(
				"interaction_region_unwalkable", "accepted region contains an invalid vertex")
		primary_in_region = primary_in_region or vertex == primary
	if not primary_in_region:
		return _invalid_runtime_interaction_contract(
			"interaction_primary_outside_region", "primary vertex is outside accepted region")
	for key in ["required_from_vertex", "component_anchor"]:
		if contract.has(key) and not _runtime_interaction_vertex_walkable(
				nav, contract.get(key, {})):
			return _invalid_runtime_interaction_contract(
				"interaction_%s_unwalkable" % key,
				"%s is not walkable" % key)
	var component_anchor := _interaction_contract_vertex(
		contract.get("component_anchor", {}))
	if not component_anchor.is_empty():
		var anchor_cell: Vector2i = component_anchor.get("cell", Vector2i.ZERO)
		var expected_component := "entry_component:%d:%d:%d" % [
			int(component_anchor.get("level", 0)),
			anchor_cell.x,
			anchor_cell.y,
		]
		if str(contract.get("component_id", "")) != expected_component:
			return _invalid_runtime_interaction_contract(
				"interaction_component_mismatch", "component id does not match its anchor")
	var primary_position := _runtime_interaction_vertex_position(
		nav, contract.get("approach_vertex", {}))
	var tolerance := maxf(0.05, float(nav.get("cell_size", 1.0)) * 0.1)
	if source_position == Vector3.INF or primary_position == Vector3.INF \
			or source_position.distance_to(primary_position) > tolerance:
		return _invalid_runtime_interaction_contract(
			"interaction_source_mismatch", "visible source is not centered on its primary vertex")
	return {"accepted": true, "code": ""}


## A generated HIDE click must use the exact persisted, connected graph region
## that also owns bodily concealment. A malformed receipt visibly refuses before
## any movement instead of degrading into resolve-nearest/teleport semantics.
func _validate_runtime_content_navigation(
		contract: Dictionary,
		category: String,
		content_id: String,
		source_position: Vector3
	) -> Dictionary:
	var expected_binding := RuntimeRegistryScript.generated_content_binding(
		category, content_id)
	var expected_navigation := RuntimeRegistryScript.generated_content_navigation(
		category, content_id)
	if str(contract.get("contract_id", "")) \
			!= StretchGeneratorScript.CONTENT_NAVIGATION_CONTRACT_ID:
		return _invalid_runtime_interaction_contract(
			"content_navigation_contract_version", "unexpected content contract id")
	if expected_binding == "" \
			or str(contract.get("binding_id", "")) != expected_binding:
		return _invalid_runtime_interaction_contract(
			"content_navigation_binding", "content binding id does not match runtime")
	if str(contract.get("kind", "")) \
			!= str(expected_navigation.get("kind", "")):
		return _invalid_runtime_interaction_contract(
			"content_navigation_kind", "content navigation kind does not match runtime")
	if str(contract.get("arrival_policy", "")) \
			!= str(expected_navigation.get("arrival_policy", "")):
		return _invalid_runtime_interaction_contract(
			"content_navigation_arrival_policy", "arrival policy does not match runtime")
	var radius_v: Variant = contract.get("radius", null)
	if typeof(radius_v) not in [TYPE_INT, TYPE_FLOAT] \
			or not is_finite(float(radius_v)) \
			or not is_equal_approx(
				float(radius_v), float(expected_navigation.get("radius", -1.0))):
		return _invalid_runtime_interaction_contract(
			"content_navigation_radius", "standing radius does not match runtime")
	var nav := _nav_grid()
	var primary := _interaction_contract_vertex(
		contract.get("approach_vertex", {}))
	if primary.is_empty() or not _runtime_interaction_vertex_walkable(
			nav, contract.get("approach_vertex", {})):
		return _invalid_runtime_interaction_contract(
			"content_navigation_primary", "content vertex is not walkable")
	var region_v: Variant = contract.get("region_vertices", null)
	if not (region_v is Array) or (region_v as Array).is_empty():
		return _invalid_runtime_interaction_contract(
			"content_navigation_region_empty", "accepted content region is empty")
	var component_anchor := _interaction_component_vertex(
		str(contract.get("component_id", "")))
	if component_anchor.is_empty() or not _runtime_interaction_vertex_walkable(
			nav, component_anchor):
		return _invalid_runtime_interaction_contract(
			"content_navigation_component", "entry component anchor is not walkable")
	var runtime_grid := GridWorld.from_data(nav)
	var anchor_cell: Vector2i = component_anchor.get("cell", Vector2i.ZERO)
	var anchor_level := int(component_anchor.get("level", -1))
	var primary_in_region := false
	var radius := float(radius_v)
	var tolerance := maxf(0.01, float(nav.get("cell_size", 1.0)) * 0.02)
	for vertex_v in region_v as Array:
		var vertex := _interaction_contract_vertex(vertex_v)
		if vertex.is_empty() or not _runtime_interaction_vertex_walkable(nav, vertex_v):
			return _invalid_runtime_interaction_contract(
				"content_navigation_region", "accepted region contains an invalid vertex")
		primary_in_region = primary_in_region or vertex == primary
		var cell: Vector2i = vertex.get("cell", Vector2i.ZERO)
		var level := int(vertex.get("level", -1))
		if runtime_grid.find_multi_level_plan(
				anchor_cell, anchor_level, cell, level).is_empty():
			return _invalid_runtime_interaction_contract(
				"content_navigation_disconnected", "accepted cell is outside entry graph component")
		var vertex_position := _runtime_interaction_vertex_position(nav, vertex_v)
		if not source_position.is_finite() or vertex_position == Vector3.INF \
				or Vector2(
					vertex_position.x - source_position.x,
					vertex_position.z - source_position.z
				).length() > radius + tolerance:
			return _invalid_runtime_interaction_contract(
				"content_navigation_outside_body", "accepted cell lies outside concealment body")
	if not primary_in_region:
		return _invalid_runtime_interaction_contract(
			"content_navigation_primary_outside_region",
			"content vertex is outside its accepted region")
	return {"accepted": true, "code": ""}


func _generated_content_route_preflight(
		_source: Node, _actor: String, refusal: Dictionary
	) -> Dictionary:
	return refusal.duplicate(true)


func _shift_levels_with_base(level_cells: Array, base_set: Dictionary, shift: Vector2i) -> Array:
	var out: Array = []
	for entry in level_cells:
		var lvl := int(entry.get("level", 0))
		var lset := {}
		for c in entry.get("cells", []):
			lset[Vector2i(int(c[0]), int(c[1]))] = true
		if lvl == 0:
			for c in base_set.keys():
				lset[c] = true
		out.append({"level": lvl, "cells": _shift_cell_list(lset.keys(), shift)})
	return out


## The warp transform at a flat point: on a spiral, the oriented helix frame (right = radial, up = world up,
## forward = tangent) lifted per level; flat, just a translation. Used to place a slab/marker onto the deck.
func _warp_xform(flat: Vector3) -> Transform3D:
	if _coord_map == null:
		return Transform3D(Basis.IDENTITY, flat)
	return _coord_map.to_xform(flat)


## The warped world POINT at a flat point — for per-vertex warping (floor tile corners), where each vertex
## takes its own place on the helix instead of riding one rigid cell frame.
func _warp_pos(flat: Vector3) -> Vector3:
	if _coord_map == null:
		return flat
	return _coord_map.to_world(flat)


## Re-seat one already-built (flat-authored) child onto the helix at its own (s, lane) — its authored height above
## the deck rides along (to_xform carries the per-level lift). Boxes/labels/zones all warp uniformly this way.
func _warp_child(child: Node) -> void:
	if not (child is Node3D):
		return
	var n3 := child as Node3D
	# Match SceneChunk.warp_interactables_onto_coord_map's data-position contract.
	# Generated stretches warp their own top-level dressing before the host installs
	# the coord map, so the generic pass never gets a chance to retain this source.
	# Interaction routing needs the exact authored x/y/z (especially the stacked
	# level); the rendered helix point cannot uniquely reconstruct that floor.
	if not n3.has_meta("flat_authored_position"):
		n3.set_meta("flat_authored_position", n3.position)
	n3.transform = _coord_map.to_xform(n3.position) * Transform3D(n3.basis, Vector3.ZERO)


func get_scene_title() -> String:
	_ensure_spec_loaded()
	if bool(_generation_fallback.get("active", false)):
		return "GENERATION FALLBACK — %s" % str(_spec.get("title", "Generated Stretch"))
	return str(_spec.get("title", "Generated Stretch"))


func get_scene_help() -> String:
	_ensure_spec_loaded()
	var tier := str(_spec.get("source", {}).get("complexity_tier", "generated")).capitalize()
	var composition: Dictionary = _spec.get("composition", {})
	var layout_help := ""
	if bool(composition.get("uses_random_walk", false)):
		layout_help = (
			"%s archetype stretch generated by a seeded random walk. Read each node, then choose between the spine and its branches."
			% tier
		)
	elif bool(composition.get("has_nested", false)):
		layout_help = (
			"%s archetype stretch with chained and nested puzzle rooms. Branches may rejoin, return upward, or bridge the next break."
			% tier
		)
	else:
		layout_help = (
			"%s archetype stretch. Read the route markers: some branches are optional supplies, while others carry the path forward."
			% tier
		)
	var fallback_help := ""
	if bool(_generation_fallback.get("active", false)):
		fallback_help = (
			"GENERATION FALLBACK: requested %s seed %d; showing %s seed %d. %s  "
			% [
				str(_generation_fallback.get("requested_tier", "unknown")).capitalize(),
				int(_generation_fallback.get("requested_seed", 0)),
				str(_generation_fallback.get("actual_tier", "unknown")).capitalize(),
				int(_generation_fallback.get("actual_seed", 0)),
				str(_generation_fallback.get("error", "Generation failed.")),
			]
		)
	return "%s%s  %s%s" % [fallback_help, layout_help, _food_economy_help(), _theme_help()]


func get_default_character() -> String:
	return "aster"


func get_preview_character_state() -> Dictionary:
	if bool(_config.get("preserve_party_state", false)):
		return {}
	return _full_party_state()


func get_preview_time_state() -> Dictionary:
	return {
		"day": 1,
		"time": 0.28,
		"advance_time": true,
		"show_time": true,
	}


## Generated stretches opt into a darker district field without changing tutorial or cutscene
## environments. Broad ambient/sun light still reveals traversable geometry; local semantic lights
## and emission carry controls, hazards, resources, and live state changes above that baseline.
func get_preview_lighting_profile() -> Dictionary:
	var hierarchy := _visual_hierarchy()
	return {
		"contract_id": str(hierarchy.get("contract_id", "")),
		"background_color": _color_from_array(
			hierarchy.get("background_color", []), Color(0.008, 0.015, 0.019)
		),
		"ambient_color": _color_from_array(
			hierarchy.get("ambient_color", []), Color(0.12, 0.20, 0.21)
		),
		"directional_color": _color_from_array(
			hierarchy.get("directional_color", []), Color(0.36, 0.50, 0.52)
		),
		"background_mix": float(hierarchy.get("background_mix", 0.8)),
		"color_mix": float(hierarchy.get("color_mix", 0.7)),
		"ambient_energy_ceiling": float(hierarchy.get("ambient_energy_ceiling", 0.42)),
		"directional_energy_ceiling": float(
			hierarchy.get("directional_energy_ceiling", 0.72)
		),
		"glow_intensity_floor": float(hierarchy.get("glow_intensity_floor", 0.24)),
	}


func get_visual_hierarchy_state() -> Dictionary:
	var hierarchy := _visual_hierarchy()
	return {
		"contract_id": str(hierarchy.get("contract_id", "")),
		"biome": _generated_biome_id(),
		"profile": get_preview_lighting_profile(),
		"decorative_fill_energy": (
			_decorative_fill_light.light_energy
			if _decorative_fill_light != null and is_instance_valid(_decorative_fill_light)
			else 0.0
		),
		"interactive_light_energy": float(hierarchy.get("interactive_light_energy", 1.05)),
		"inactive_light_energy": float(hierarchy.get("inactive_light_energy", 0.05)),
		"node_focus_light_count": _node_focus_lights.size(),
	}


func _visual_hierarchy() -> Dictionary:
	_ensure_spec_loaded()
	var theme: Dictionary = _spec.get("area_theme", {})
	var explicit: Variant = theme.get("visual_hierarchy", {})
	if explicit is Dictionary and not (explicit as Dictionary).is_empty():
		return (explicit as Dictionary).duplicate(true)
	return BiomesScript.visual_hierarchy_for(_generated_biome_id())


func _generated_biome_id() -> String:
	var theme: Dictionary = _spec.get("area_theme", {})
	var settings: Dictionary = _spec.get("settings", {})
	var slot: Dictionary = _spec.get("world_slot", {})
	var candidates := [
		str(theme.get("id", "")),
		str(settings.get("biome", _spec.get("biome", ""))),
		str(theme.get("source_area", "")),
		str(slot.get("region", "")),
	]
	for candidate_v in candidates:
		var candidate := str(candidate_v).strip_edges().to_lower()
		if candidate == "":
			continue
		for biome_id_v in BiomesScript.biome_ids():
			var biome_id := str(biome_id_v)
			if candidate == biome_id or candidate.contains(biome_id):
				return biome_id
		if candidate.contains("plumbing"):
			return "channels"
		if candidate.contains("open files") or candidate.contains("archive"):
			return "stacks"
		if candidate.contains("greenfields") or candidate.contains("flora garden"):
			return "garden"
		if candidate.contains("cleanstreets") or candidate.contains("transit plaza"):
			return "cleanstreets"
		if candidate.contains("dead zone"):
			return "deadzone"
	return "channels"


## A full wipe leaves nobody to act, so the stretch itself answers: after a short beat the party
## comes to at the entry shelter, conscious at revive HP, having lost the ground since -- a
## section, never the run. Derived end to end: the wipe is detected from the downed transition,
## the beat rides the gameplay scheduler, and the recovery verb refuses unless everyone is down.
func _watch_for_party_wipe() -> void:
	var gs = _get_game_state()
	if gs == null or not gs.has_signal("character_downed"):
		return
	if not gs.character_downed.is_connected(_on_party_member_downed):
		gs.character_downed.connect(_on_party_member_downed)

func _wipe_party_roster() -> Array:
	var gs = _get_game_state()
	var roster: Array = []
	if gs == null:
		return roster
	for char_id in PARTY_IDS:
		if gs.characters.has(char_id):
			roster.append(char_id)
	return roster

func _on_party_member_downed(_char_id: String) -> void:
	var gs = _get_game_state()
	var roster := _wipe_party_roster()
	if gs == null or roster.is_empty() or not gs.is_party_downed(roster):
		return
	var sched = _get_scheduler()
	if sched == null:
		_recover_party_from_wipe()
		return
	sched.cancel_tag("generated_wipe_recovery")
	sched.schedule_after(2.0, _recover_party_from_wipe, "generated_wipe_recovery")

func _recover_party_from_wipe() -> void:
	var gs = _get_game_state()
	var roster := _wipe_party_roster()
	if gs == null or roster.is_empty():
		return
	var at := _anchor_position("entry")
	if at == Vector3.INF:
		var spawns := get_spawn_positions()
		at = _vec3(spawns.get(str(roster[0]), Vector3.ZERO), Vector3.ZERO) 			if spawns.get(str(roster[0]), null) != null else Vector3.ZERO
	if gs.recover_wiped_party(roster, at):
		_wipe_recoveries += 1

func get_spawn_positions() -> Dictionary:
	_ensure_spec_loaded()
	var positions := {}
	var anchors: Dictionary = _spec.get("anchors", {})
	for char_id in PARTY_IDS:
		if anchors.has(char_id):
			positions[char_id] = _vec3(anchors[char_id], Vector3.ZERO)
	positions["entry"] = _anchor_position("entry")
	positions["exit_shelter"] = _anchor_position("exit_shelter")
	return positions


func get_preview_anchors() -> Dictionary:
	_ensure_spec_loaded()
	var result := {}
	var anchors: Dictionary = _spec.get("anchors", {})
	for key in anchors.keys():
		result[str(key)] = _vec3(anchors[key], Vector3.ZERO)
	return result


func get_world_slot() -> Dictionary:
	_ensure_spec_loaded()
	var slot: Dictionary = _spec.get("world_slot", {}).duplicate(true)
	if not slot.has("preview_party_preset"):
		slot["preview_party_preset"] = "full_party_full_health"
	if not slot.has("canonical_party"):
		slot["canonical_party"] = PARTY_IDS.duplicate()
	return slot


func get_generation_spec() -> Dictionary:
	_ensure_spec_loaded()
	return _spec.duplicate(true)


func get_generation_fallback_state() -> Dictionary:
	return _generation_fallback.duplicate(true)


func get_graybox_state() -> Dictionary:
	_ensure_spec_loaded()
	_ensure_graybox_layout()
	return _graybox_state()


func _effective_party_atp_total() -> float:
	var members := _shelter_rest_members()
	if host == null or not host.has_method("get_preview_character_stat"):
		return float(members.size()) * GameState.ATP_MAX_PIPS
	var total := 0.0
	for char_id in members:
		total += _get_character_stat(char_id, "atp")
	return total


func _effective_party_atp_capacity() -> float:
	return float(_shelter_rest_members().size()) * GameState.ATP_MAX_PIPS


func _scarcity_state() -> Dictionary:
	var clock_state: Dictionary = _scarcity_clock.snapshot()
	return {
		"scarcity_drain_interval": float(clock_state.get(
			"interval_seconds", _scarcity_drain_interval()
		)),
		"scarcity_drain_per_character": float(clock_state.get(
			"drain_per_character", _scarcity_drain_amount()
		)),
		"scarcity_atp_floor_per_character": float(clock_state.get(
			"floor_per_character", AtpScarcityClockScript.DEFAULT_FLOOR_ATP
		)),
		"scarcity_zero_atp_hp_drain_per_character": float(clock_state.get(
			"hp_drain_at_zero_per_character", _scarcity_zero_atp_hp_drain()
		)),
		"scarcity_drain_ticks": int(clock_state.get("ticks", 0)),
		"scarcity_atp_drained": float(clock_state.get("atp_drained", 0.0)),
		"scarcity_hp_drained": float(clock_state.get("hp_drained", 0.0)),
		"scarcity_hp_absorbed": float(clock_state.get("hp_absorbed", 0.0)),
		"scarcity_active": _food_test_mode() == FOOD_TEST_SCARCITY and not _shelter_reached,
		"scarcity_clock_started": bool(clock_state.get("started", false)),
		"scarcity_drain_armed": bool(clock_state.get("armed", false)),
		"scarcity_next_drain_in": float(clock_state.get("next_drain_in", -1.0)),
		"scarcity_drain_tag": str(clock_state.get("tag", SCARCITY_DRAIN_TAG)),
		"scarcity_character_ids": (clock_state.get("character_ids", []) as Array).duplicate(),
	}


func _physical_food_cache_count(available_only := false) -> int:
	var count := 0
	for cache in _branch_caches:
		if not bool(cache.get("physical_food", false)):
			continue
		if available_only and bool(cache.get("collected", false)):
			continue
		count += 1
	return count


func _physical_food_opportunity_count(available_only := false) -> int:
	return _physical_food_cache_count(available_only)


func _branch_food_profiles() -> Array:
	var profiles: Array = []
	for cache in _branch_caches:
		profiles.append({
			"index": int(cache.get("index", -1)),
			"shape": str(cache.get("shape", "")),
			"risk_score": float(cache.get("risk_score", 0.0)),
			"detour_cells": float(cache.get("detour_cells", 0.0)),
			"hazard_penalty": float(cache.get("hazard_penalty", 0.0)),
			"food_atp": float(cache.get("food_atp", BRANCH_ATP)),
		})
	return profiles


func _real_content_counts() -> Dictionary:
	return {
		"capbage": _generated_capbages.size(),
		"scarpet": _generated_scarpets.size(),
		"hushbloom": _generated_hushblooms.size(),
	}


func get_preview_state() -> Dictionary:
	_ensure_spec_loaded()
	var generation := {
		"generation_fallback": get_generation_fallback_state(),
		"game_mode": _game_mode_id(),
		"food_test": _food_test_mode(),
		"physical_food_spawned_count": _physical_food_spawned_count,
		"physical_food_cache_count": _physical_food_cache_count(),
		"physical_food_cache_available_count": _physical_food_cache_count(true),
		"physical_food_opportunity_count": _physical_food_opportunity_count(),
		"physical_food_opportunity_available_count": _physical_food_opportunity_count(true),
		"branch_food_profiles": _branch_food_profiles(),
		"nominal_food_atp": _nominal_food_atp,
		"effective_party_atp": _effective_party_atp_total(),
		"effective_party_atp_capacity": _effective_party_atp_capacity(),
		"contract_id": "stretch_generation_v1",
		"spec_id": str(_spec.get("id", "")),
		"schema": str(_spec.get("schema", "")),
		"title": str(_spec.get("title", "")),
		"biome": str(_spec.get("biome", "")),
		"area_theme": (_spec.get("area_theme", {}) as Dictionary).duplicate(true),
		"zone_transition": (_spec.get("zone_transition", {}) as Dictionary).duplicate(true),
		"themed_landmarks": (_spec.get("themed_landmarks", []) as Array).duplicate(true),
		"themed_setpieces": (_spec.get("themed_setpieces", []) as Array).duplicate(true),
		"infrastructure_operations": (_spec.get("infrastructure_operations", []) as Array).duplicate(true),
		"theme_hazard_damage_total": _theme_hazard_damage_total,
		"route_risk_field": _route_risk_field_state(),
		"complexity_tier": str(_spec.get("source", {}).get("complexity_tier", "")),
		"resolved_budget": _spec.get("budget", {}).duplicate(true),
		"limitations": _spec.get("settings", {}).get("limitations", {}).duplicate(true),
		"world_slot": get_world_slot(),
		"palette_usage": _spec.get("palette_usage", {}).duplicate(true),
		"archetype_chain": _spec.get("archetype_chain", []).duplicate(true),
		"composition": _spec.get("composition", {}).duplicate(true),
		"graybox": _graybox_state(),
		"navigation": get_navigation_state(),
		"chain_count":
		int(
			_spec.get("composition", {}).get(
				"chain_count", (_spec.get("archetype_chain", []) as Array).size()
			)
		),
		"nested_archetype_count": int(_spec.get("composition", {}).get("nested_count", 0)),
		"nested_depth": int(_spec.get("composition", {}).get("nested_depth", 0)),
		"uses_random_walk": bool(_spec.get("composition", {}).get("uses_random_walk", false)),
		"walk_element_count": int(_spec.get("composition", {}).get("walk_element_count", 0)),
		"walk_archetype_count": int(_spec.get("composition", {}).get("walk_archetype_count", 0)),
		"node_count": _nodes().size(),
		"route_count": _routes().size(),
		"completed_nodes": _completed_nodes.duplicate(),
		"activated_routes": _activated_routes.duplicate(),
		"produced_chain_states": _produced_chain_states.duplicate(true),
		"delivered_resource_nodes": _delivered_resource_nodes.duplicate(),
		"route_choice": _route_choice,
		"route_phase": _route_phase,
		"resources_collected": _resources_collected,
		"shortcut_unlocked": _shortcut_unlocked,
		"shelter_reached": _shelter_reached,
		"shelter_rested": _shelter_rested,
		"completion_ready": _generated_completion_ready(),
		"first_shelter_beat_fired": _first_shelter_beat_fired,
		"last_outcome": _last_outcome,
		"risky_damage_total": _risky_damage_total,
		"pressure_taken": _pressure_taken,
		"rests_taken": _rests_taken,
		"unsupported_placeholder_count": _unsupported_placeholder_count,
		"omitted_content_count": _omitted_content_count,
		"content_marker_count": _content_marker_count,
		"real_content_counts": _real_content_counts(),
		"spatial_fixture_count": _spatial_fixture_count,
		"themed_landmark_count": _theme_landmark_roots.size(),
		"themed_setpiece_count": _theme_setpiece_roots.size(),
		"zone_transition_floor_cell_count": _zone_transition_floor_cell_count,
		"climbvine_count": _climbvines.size(),
		"climbvine_states": _climbvine_states(),
		"branch_span_count": get_branch_span_count(),
		"branch_span_states": _branch_span_states(),
		"active_loadout": _active_loadout,
		"active_party": _active_party.duplicate(),
		"blocked_nodes": _blocked_nodes.duplicate(),
		"solution_path": get_active_solution_path(),
		"solution_summary": _spec.get("headless", {}).get("solution_summary", {}).duplicate(true),
	}
	generation.merge(_scarcity_state())
	var state := {
		"game_mode": _game_mode_id(),
		"food_test": _food_test_mode(),
		"physical_food_spawned_count": _physical_food_spawned_count,
		"physical_food_cache_count": _physical_food_cache_count(),
		"physical_food_cache_available_count": _physical_food_cache_count(true),
		"physical_food_opportunity_count": _physical_food_opportunity_count(),
		"physical_food_opportunity_available_count": _physical_food_opportunity_count(true),
		"branch_food_profiles": _branch_food_profiles(),
		"nominal_food_atp": _nominal_food_atp,
		"effective_party_atp": _effective_party_atp_total(),
		"effective_party_atp_capacity": _effective_party_atp_capacity(),
		"contract_id": "generated_stretch_chunk_v1",
		"spec_id": generation["spec_id"],
		"world_slot": generation["world_slot"],
		"preview_party_preset": "full_party_full_health",
		"route_choice": _route_choice,
		"route_phase": _route_phase,
		"shelter_reached": _shelter_reached,
		"shelter_rested": _shelter_rested,
		"completion_ready": _generated_completion_ready(),
		"shortcut_unlocked": _shortcut_unlocked,
		"first_shelter_beat_fired": _first_shelter_beat_fired,
		"last_outcome": _last_outcome,
		"risky_damage_total": _risky_damage_total,
		"pressure_taken": _pressure_taken,
		"rests_taken": _rests_taken,
		"unsupported_placeholder_count": _unsupported_placeholder_count,
		"omitted_content_count": _omitted_content_count,
		"real_content_counts": _real_content_counts(),
		"spatial_fixture_count": _spatial_fixture_count,
		"themed_landmark_count": _theme_landmark_roots.size(),
		"themed_setpiece_count": _theme_setpiece_roots.size(),
		"zone_transition_floor_cell_count": _zone_transition_floor_cell_count,
		"theme_hazard_damage_total": _theme_hazard_damage_total,
		"route_risk_field": _route_risk_field_state(),
		"drop_down_count": _drop_downs.size(),
		"climbvine_count": _climbvines.size(),
		"climbvine_states": _climbvine_states(),
		"branch_span_count": get_branch_span_count(),
		"branch_span_states": _branch_span_states(),
		"branch_cache_count": _branch_caches.size(),
		"active_loadout": _active_loadout,
		"active_party": _active_party.duplicate(),
		"blocked_nodes": _blocked_nodes.duplicate(),
		"produced_chain_states": _produced_chain_states.duplicate(true),
		"delivered_resource_nodes": _delivered_resource_nodes.duplicate(),
		"solution_path": get_active_solution_path(),
		"graybox": generation["graybox"],
		"navigation": generation["navigation"],
		"generation": generation,
	}
	state.merge(_scarcity_state())
	return state


## The unified-grid traversal layer (GridWorld.from_data contract): the preview installs this as the
## scene grid, so characters route on cells with per-cell route risk and ramp links across elevations.
## The semantic nodes/routes (the solver's and replay artifact's representation) are unchanged.
func get_grid_data() -> Dictionary:
	_ensure_spec_loaded()
	_ensure_graybox_layout()
	_ensure_navigation_layout()
	return _nav_grid().duplicate(true)


func get_navigation_state() -> Dictionary:
	_ensure_spec_loaded()
	_ensure_navigation_layout()
	var nav_grid := _nav_grid()
	return {
		"contract_id": str(nav_grid.get("contract_id", "")),
		"walkable_cell_count": (nav_grid.get("walkable_cells", []) as Array).size(),
		"link_count": (nav_grid.get("links", []) as Array).size(),
		"level_count": int(nav_grid.get("level_count", 1)),
		"entry_node": str(nav_grid.get("entry_anchor", "")),
		"exit_node": str(nav_grid.get("exit_anchor", "")),
		"supports_multiple_elevations": bool(nav_grid.get("supports_multiple_elevations", false)),
		"elevation_indices": nav_grid.get("elevation_indices", []),
	}


func get_generated_node_position(node_id: String) -> Vector3:
	_ensure_spec_loaded()
	var node := _find_node(node_id)
	if node.is_empty():
		return Vector3.INF
	return _vec3(node.get("position", []), Vector3.INF)


func _clear_physical_food_items() -> void:
	for item_id in _physical_food_item_ids:
		if item_id != "":
			_remove_item(item_id)
	_physical_food_item_ids.clear()


func _reset_physical_food_state() -> void:
	_clear_physical_food_items()
	_physical_food_spawned_count = 0
	_nominal_food_atp = 0.0

	for cache in _branch_caches:
		if bool(cache.get("physical_food", false)):
			cache["collected"] = false
			_set_branch_cache_available_visual(cache, true)
			var interactable = cache.get("interactable", null)
			if interactable != null and interactable.has_method("set_interaction_enabled"):
				interactable.call("set_interaction_enabled", true)


func _configure_scarcity_clock() -> void:
	var started_callback := Callable(self, "_on_scarcity_pressure_started")
	if not _scarcity_clock.is_connected("pressure_started", started_callback):
		_scarcity_clock.connect("pressure_started", started_callback)
	var applied_callback := Callable(self, "_on_scarcity_pressure_applied")
	if not _scarcity_clock.is_connected("pressure_applied", applied_callback):
		_scarcity_clock.connect("pressure_applied", applied_callback)
	var settings := _food_test_settings()
	if _food_test_mode() != FOOD_TEST_SCARCITY:
		settings["drain_atp"] = 0.0
		settings["zero_atp_hp_drain"] = 0.0
	_scarcity_clock.configure(
		_get_scheduler(),
		_get_game_state(),
		_shelter_rest_members(),
		settings,
		SCARCITY_DRAIN_TAG
	)


func _cancel_scarcity_drain() -> void:
	_scarcity_clock.stop()


func _dispose_scarcity_clock() -> void:
	_scarcity_clock.dispose()


func begin_scarcity_clock() -> bool:
	if _food_test_mode() != FOOD_TEST_SCARCITY or _shelter_reached:
		return false
	return _scarcity_clock.begin()


func _on_scarcity_pressure_started() -> void:
	_show_message(
		(
			"EXPERIMENTAL SCARCITY — movement started a %s ATP drain every %.0f seconds "
			+ "per character. At zero ATP, later ticks cost %s HP; an active WRAP can absorb it."
		) % [
			_atp_amount_text(_scarcity_drain_amount()),
			_scarcity_drain_interval(),
			_atp_amount_text(_scarcity_zero_atp_hp_drain()),
		],
		2.8
	)


func _on_scarcity_pressure_applied(
		atp_total: float,
		atp_by_character: Dictionary,
		hp_total: float,
		hp_by_character: Dictionary,
		absorbed_total: float,
		absorbed_by_character: Dictionary
	) -> void:
	var atp_affected := _scarcity_display_names(atp_by_character)
	var hp_affected := _scarcity_display_names(hp_by_character)
	var absorbed_affected := _scarcity_display_names(absorbed_by_character)
	var parts: Array[String] = []
	if atp_total > 0.0:
		parts.append(
			"%s lost %s ATP total" % [", ".join(atp_affected), _atp_amount_text(atp_total)]
		)
	if hp_total > 0.0:
		parts.append(
			"ATP EMPTY — %s lost %s HP total" % [", ".join(hp_affected), _atp_amount_text(hp_total)]
		)
	if absorbed_total > 0.0:
		parts.append(
			"WRAP absorbed %s zero-ATP damage for %s"
			% [_atp_amount_text(absorbed_total), ", ".join(absorbed_affected)]
		)
	if parts.is_empty():
		return
	var newly_empty: Array[String] = []
	for char_id_v in atp_by_character.keys():
		var char_id := str(char_id_v)
		if _get_character_stat(char_id, "atp") <= 0.0:
			newly_empty.append(char_id.capitalize())
	newly_empty.sort()
	var consequence := " Endocytose carried lysate before the next tick."
	if hp_total <= 0.0 and not newly_empty.is_empty():
		consequence = (
			" %s reached zero; their next zero-ATP tick costs %s HP."
			% [", ".join(newly_empty), _atp_amount_text(_scarcity_zero_atp_hp_drain())]
		)
	_show_message("SCARCITY — %s.%s" % ["; ".join(parts), consequence], 2.8)


func _scarcity_display_names(per_character: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for char_id_v in per_character.keys():
		result.append(str(char_id_v).capitalize())
	result.sort()
	return result


func _process(_delta: float) -> void:
	_ensure_branch_span_producers_ready()
	_update_generated_party_endpoints()
	_ensure_theme_hazard_tick()
	_publish_generated_runtime_authority()


## Generated flora uses the same positional hide tiers as data-authored chunks.
## The reusable flora objects preserve their flat simulation origins even though
## their visible roots are subsequently bent onto the spiral coordinate map.
func _update_generated_flora_concealment() -> void:
	if _generated_capbages.is_empty() and _generated_scarpets.is_empty() \
			and _infrastructure_runtime.is_empty():
		return
	var gs = _get_game_state()
	if gs == null or not gs.has_method("set_character_concealment"):
		return
	var members: Array = _active_party if not _active_party.is_empty() else PARTY_IDS
	for char_id_v in members:
		var char_id := str(char_id_v)
		if not gs.characters.has(char_id):
			continue
		var position: Vector3 = gs.get_position(char_id)
		var tier := GameState.CONCEAL_NONE
		for capbage in _generated_capbages:
			if is_instance_valid(capbage) and bool(capbage.call("conceals", position)):
				tier = GameState.CONCEAL_FULL
				break
		if tier == GameState.CONCEAL_NONE:
			for scarpet in _generated_scarpets:
				if is_instance_valid(scarpet) and bool(scarpet.call("conceals", position)):
					tier = GameState.CONCEAL_MEDIUM
					break
		if tier == GameState.CONCEAL_NONE:
			for runtime_v in _infrastructure_runtime:
				var field = (runtime_v as Dictionary).get("field", null)
				if field != null and is_instance_valid(field) and field.has_method("conceals") \
						and bool(field.call("conceals", position)):
					tier = GameState.CONCEAL_FULL
					break
		gs.set_character_concealment(char_id, tier)


func _theme_hazard_tag() -> String:
	return "generated_theme_hazard:%s" % _generated_runtime_authority_key()


func _cancel_theme_hazard_tick() -> void:
	var scheduler = _get_scheduler()
	if scheduler != null:
		scheduler.cancel_tag(_theme_hazard_tag())
	_theme_hazard_armed = false
	_theme_hazard_next_tick = -1.0


func _ensure_theme_hazard_tick() -> void:
	if _theme_hazard_armed or _shelter_reached \
			or (_theme_setpiece_roots.is_empty() and _infrastructure_runtime.is_empty()
				and _generated_capbages.is_empty() and _generated_scarpets.is_empty()):
		return
	_arm_theme_hazard_tick(THEME_HAZARD_TICK)


func _arm_theme_hazard_tick(delay := THEME_HAZARD_TICK) -> void:
	var scheduler = _get_scheduler()
	if scheduler == null:
		return
	delay = maxf(0.000001, delay)
	scheduler.cancel_tag(_theme_hazard_tag())
	_theme_hazard_armed = true
	_theme_hazard_next_tick = _sequence_tick() + delay
	scheduler.schedule_after(delay, _on_theme_hazard_tick, _theme_hazard_tag())
	_publish_generated_runtime_authority()


func _on_theme_hazard_tick() -> void:
	_theme_hazard_armed = false
	_theme_hazard_next_tick = -1.0
	# The same saved spatial cadence owns cover sampling. Render/headless presenter frequency
	# therefore cannot grant or retract concealment, and rollback preserves the sampled tier until
	# the original absolute boundary.
	_update_generated_flora_concealment()
	_apply_theme_hazard_tick()
	_ensure_theme_hazard_tick()


## Cleanstreets studs are immediate, local feedback rather than a delayed abstract node penalty. Their source
## cells already carry navigation risk, so SAFE avoids them where an alternate lane exists and DIRECT may spend
## health for time. One fixture wins per scheduler tick to prevent overlapping authored nodes from multiplying
## damage. This must never use render-frame delta: Movie Maker FPS and fast-forward cannot change the cost.
func _apply_theme_hazard_tick() -> void:
	if (_theme_setpiece_roots.is_empty() and _infrastructure_runtime.is_empty()) or _shelter_reached:
		return
	var hazard_party: Array = _active_party if not _active_party.is_empty() else PARTY_IDS
	for char_id_v in hazard_party:
		var char_id := str(char_id_v)
		var position := _get_character_position(char_id)
		var highest_dps := 0.0
		for setpiece in _theme_setpiece_roots:
			if not is_instance_valid(setpiece) or not setpiece.has_method("covers_flat"):
				continue
			if bool(setpiece.call("covers_flat", position)):
				highest_dps = maxf(highest_dps, float(setpiece.get("damage_per_second")))
		for runtime_v in _infrastructure_runtime:
			var runtime := runtime_v as Dictionary
			var operation = runtime.get("operation")
			if operation == null or not is_instance_valid(operation) or not operation.has_method("get_state"):
				continue
			var state: Dictionary = operation.call("get_state")
			var field_state: Dictionary = state.get("field", {})
			if not bool(field_state.get("hazardous", false)):
				continue
			var spec: Dictionary = runtime.get("spec", {})
			var center := _vec3(spec.get("effect_pos", []), Vector3.ZERO)
			var half_raw: Variant = spec.get("effect_half", [0.66, 0.66])
			var half := Vector2(0.66, 0.66)
			if half_raw is Array and (half_raw as Array).size() >= 2:
				half = Vector2(float(half_raw[0]), float(half_raw[1]))
			elif half_raw is Vector2:
				half = half_raw as Vector2
			if absf(position.x - center.x) <= half.x and absf(position.z - center.z) <= half.y:
				highest_dps = maxf(highest_dps, float(field_state.get("damage_per_second", 0.0)))
		if highest_dps <= 0.0:
			_theme_hazard_contacts.erase(char_id)
			continue
		var damage := highest_dps * THEME_HAZARD_TICK
		_adjust_character_stat(char_id, "hp", -damage)
		_theme_hazard_damage_total += damage
		_last_outcome = "marked_route_hazard:%s" % char_id
		if not _theme_hazard_contacts.has(char_id):
			_theme_hazard_contacts[char_id] = true
			_show_note(
				"MARKED ROUTE HAZARD // %s is taking continuous damage. The linked service controls clear it."
				% char_id.capitalize(),
				2.4
			)
	_publish_generated_runtime_authority()


## Risk is a place, not a menu price. Generated navigation already names and visibly
## tints every risk cell; this reusable field owns the fixed-cadence consequence for
## bodies actually standing on those cells. Cleanstreets' authored setpieces already
## provide their own spatial damage volumes, so they do not receive a duplicate field.
func _build_route_risk_field() -> void:
	_route_risk_field = null
	var nav := _nav_grid()
	var entries: Array = nav.get("risk_cell_list", [])
	if entries.is_empty():
		return
	if str(_spec.get("biome", "")) == "cleanstreets" and not _theme_setpiece_roots.is_empty():
		return
	var gs = _get_game_state()
	var scheduler = _get_scheduler()
	if gs == null or scheduler == null:
		return
	var risk_grid = GridWorld.from_data(nav)
	if risk_grid == null:
		return
	var field = GridRiskFieldScript.new()
	field.name = "GeneratedRouteRiskField"
	add_child(field)
	field.call("setup", gs, scheduler, risk_grid, entries, _active_party, {
		"tag": "generated_route_risk:%s" % _generated_runtime_authority_key(),
		"interval": ROUTE_RISK_TICK,
		# Navigation penalty units become HP/second. Crossing quickly therefore costs
		# less than loitering, while cautious routing can avoid the marked cells entirely.
		"damage_rate_scale": ROUTE_RISK_DAMAGE_RATE_SCALE,
		"active": true,
		"on_bite": Callable(self, "_on_route_risk_bite"),
	})
	_route_risk_field = field


func _on_route_risk_bite(
	character_id: String, damage: float, cell: Vector2i, penalty: float
) -> void:
	_risky_damage_total += damage
	# Legacy pressure telemetry mirrors actual spatial HP loss.
	_pressure_taken += damage
	_route_phase = "impact"
	_last_outcome = "risk_cell_contact:%s:%d:%d" % [character_id, cell.x, cell.y]
	if not _route_risk_contacts.has(character_id):
		_route_risk_contacts[character_id] = true
		_show_note(
			"MARKED FLOOR // %s is taking %.1f HP/s here. Move through or route around it."
			% [character_id.capitalize(), penalty * ROUTE_RISK_DAMAGE_RATE_SCALE],
			2.8
		)
	_publish_generated_runtime_authority()


func _route_risk_field_state() -> Dictionary:
	if _route_risk_field != null and is_instance_valid(_route_risk_field) \
			and _route_risk_field.has_method("get_state"):
		return (_route_risk_field.call("get_state") as Dictionary).duplicate(true)
	return {}


func reset_preview_state() -> void:
	_cancel_scarcity_drain()
	_cancel_theme_hazard_tick()
	_stop_generated_party_rest()
	_reset_generated_interaction_receipts()
	_reset_generated_resource_items()
	_reset_physical_food_state()
	_initialize_resource_claim_authority()
	# Generated and branch rewards exist before anyone interacts with them. Their
	# exact GameState item ids are part of the reset baseline; interaction only moves
	# those items from the source into the servicing character's hand.
	_materialize_resource_sources()
	_exit_shelter_transaction = _new_exit_shelter_transaction()
	_ensure_branch_span_producers_ready()
	for span in _branch_span_producers:
		if is_instance_valid(span) and span.has_method("reset"):
			span.call("reset")
	for climbvine in _climbvines:
		if is_instance_valid(climbvine) and climbvine.has_method("reset"):
			climbvine.call("reset")
	_theme_hazard_accumulator = 0.0
	_theme_hazard_damage_total = 0.0
	_theme_hazard_contacts.clear()
	for hushbloom in _generated_hushblooms:
		if is_instance_valid(hushbloom) and not bool(hushbloom.call("is_charged")):
			hushbloom.call("_recharge")
	for runtime_v in _infrastructure_runtime:
		var infrastructure_operation = (runtime_v as Dictionary).get("operation")
		if infrastructure_operation != null and is_instance_valid(infrastructure_operation) \
				and infrastructure_operation.has_method("reset_operation"):
			infrastructure_operation.call("reset_operation")
	_route_choice = ""
	_route_phase = "unstarted"
	_completed_nodes.clear()
	_activated_routes.clear()
	_produced_chain_states.clear()
	_delivered_resource_nodes.clear()
	_resources_collected = 0
	_shortcut_unlocked = false
	_shelter_reached = false
	_shelter_rested = false
	_last_outcome = "ready"
	_risky_damage_total = 0.0
	_route_risk_contacts.clear()
	if _route_risk_field != null and is_instance_valid(_route_risk_field) \
			and _route_risk_field.has_method("reset"):
		_route_risk_field.call("reset", true)
	_pressure_taken = 0.0
	_rests_taken = 0
	_first_shelter_beat_fired = false
	_node_approach_used.clear()
	_blocked_nodes.clear()
	_rearm_exit_shelter_interaction()
	set_active_loadout(_active_loadout)
	_restore_party()
	_reset_generated_party_positions()
	_configure_scarcity_clock()
	_set_preview_step("generated_stretch_ready")
	_ensure_theme_hazard_tick()
	_ensure_generated_route_arrival_authority()
	# Keep an immutable construction/reset baseline. A snapshot made before this stretch had any
	# world-state record must restore this state, not whatever scene-local flags a later timeline left
	# behind on the same chunk instance.
	_generated_runtime_baseline = _generated_runtime_authority_state().duplicate(true)
	_publish_generated_runtime_authority()


func _reset_generated_interaction_receipts() -> void:
	# A preview/replay reset is a new construction baseline, not a snapshot restore.
	# Clear both the presenter's local one-shot latch and GameState's triggered bit
	# before the new physical sources and mechanism phases are initialized.
	var reset_instances := {}
	for source_v in _node_interactables.values():
		if source_v is Node and is_instance_valid(source_v) \
				and (source_v as Node).has_method("reset"):
			(source_v as Node).call("reset")
			if source_v is CollisionObject3D:
				# Generated nodes are clicked through their visible outline target;
				# the meshless Area is never allowed to steal that pointer ray.
				(source_v as CollisionObject3D).input_ray_pickable = false
			reset_instances[(source_v as Node).get_instance_id()] = true
	for cache_v in _branch_caches:
		if not (cache_v is Dictionary):
			continue
		var cache_source: Node = (cache_v as Dictionary).get("interactable", null)
		if cache_source == null or not is_instance_valid(cache_source) \
				or reset_instances.has(cache_source.get_instance_id()) \
				or not cache_source.has_method("reset"):
			continue
		cache_source.call("reset")
		reset_instances[cache_source.get_instance_id()] = true


## Choose which party is solving the stretch. "spotlight" is the full party (a
## specialist is on hand); "shadow" is the Aster+Peris pair. The active loadout's
## capabilities decide which approach each puzzle node accepts — and whether it blocks.
func set_active_loadout(loadout_id: String) -> void:
	var roster = _roster()
	for loadout in CapabilitiesScript.loadouts(roster):
		if str(loadout.get("id", "")) == loadout_id:
			_active_loadout = loadout_id
			_active_party.clear()
			for cid in loadout.get("party", []):
				_active_party.append(str(cid))
			_active_capabilities = (loadout.get("base_capabilities", {}) as Dictionary).duplicate()
			_enforce_stage = bool(loadout.get("enforce_stage", false))
			_scarcity_clock.set_character_ids(_shelter_rest_members())
			_sync_route_risk_character_ids()
			_publish_generated_runtime_authority()
			return

	# An unrecognised loadout id should never reach here (the only ids are spotlight/shadow);
	# warn rather than silently masquerade as spotlight, so a typo is caught instead of hidden.
	if loadout_id != "spotlight":
		push_warning(
			"generated_stretch_chunk: unknown loadout '%s' — defaulting to spotlight" % loadout_id
		)
	_active_loadout = "spotlight"
	_active_party.clear()
	for cid in CapabilitiesScript.normalize_roster(roster).get("enabled", []) as Array:
		_active_party.append(str(cid))
	_active_capabilities = CapabilitiesScript.roster_capabilities(roster)
	_enforce_stage = true
	_scarcity_clock.set_character_ids(_shelter_rest_members())
	_sync_route_risk_character_ids()
	_publish_generated_runtime_authority()


func _sync_route_risk_character_ids() -> void:
	if _route_risk_field != null and is_instance_valid(_route_risk_field) \
			and _route_risk_field.has_method("set_character_ids"):
		_route_risk_field.call("set_character_ids", _active_party)


## The enabled roster this stretch was generated for (the enable/disable choices), read from
## the spec. Empty means the full canonical six.
func _roster():
	var configured = _spec.get("source", {}).get(
		"roster", _spec.get("settings", {}).get("roster", [])
	)
	if configured is Array and not (configured as Array).is_empty():
		return configured
	# Persisted world slots already state who is actually present. Falling back to
	# the global six-character roster made three-character stretches require absent,
	# uninitialized members to pay the shelter-rest cost.
	return _spec.get("world_slot", {}).get("canonical_party", [])


## How far the player is assumed to have progressed — the first-play full party may only
## use techniques taught up to this stage. Read from the spec the generator produced.
func _progression_stage() -> int:
	return int(
		_spec.get("source", {}).get(
			"progression_stage", _spec.get("settings", {}).get("progression_stage", 99)
		)
	)


## The first approach the active party can field on this node, given its own
## capabilities plus any tool placed on the node. Marked blocked when none fit.
func _resolve_node_approach(node: Dictionary) -> Dictionary:
	var handler_id := _runtime_handler_for_node(node)
	var resolved := RuntimeRegistryScript.handler_approach(handler_id)
	if resolved.is_empty():
		return {"approach_id": "", "kind": "unsupported", "party": "", "blocked": true}
	return resolved


func _runtime_handler_for_node(node: Dictionary) -> String:
	return RuntimeRegistryScript.handler_for_node(node, str(_spec.get("id", "")))


func _generated_interaction_data_position(source: Node) -> Vector3:
	# The walk-to point and the readiness check must be the SAME contract. The authored/projected
	# approach can land outside the contract's own acceptance region -- the shelter's sat a cell
	# short of it -- and then the servicing actor arrives, settles, and is refused for not standing
	# on an apron it was never sent to. When a typed approach contract exists, its approach vertex
	# IS the walk-to point, so arrival and acceptance cannot disagree.
	if source != null and source.has_meta("interaction_navigation_region"):
		var region_v: Variant = source.get_meta("interaction_navigation_region")
		var region_gs = _get_game_state()
		if region_v is Dictionary and region_gs != null and region_gs.grid != null:
			var vertex_v: Variant = (region_v as Dictionary).get("approach_vertex", null)
			if vertex_v is Dictionary:
				var vertex := vertex_v as Dictionary
				var cell_v: Variant = vertex.get("cell", null)
				if cell_v is Array and (cell_v as Array).size() >= 2:
					return region_gs.grid.grid_to_world(
						Vector2i(int((cell_v as Array)[0]), int((cell_v as Array)[1])),
						int(vertex.get("level", 0)))
	if source != null and source.has_meta("generated_interaction_data_position"):
		var authored_position: Variant = source.get_meta(
			"generated_interaction_data_position", Vector3.ZERO
		)
		if authored_position is Vector3:
			return authored_position
	var gs = _get_game_state()
	var data_id := str(source.get("data_id")) if source != null else ""
	if gs != null and data_id != "" and gs.has_interactable(data_id):
		var position: Variant = gs.get_interactable(data_id).get("position", Vector3.ZERO)
		if position is Vector3:
			return position
	var world_position := (
		(source as Node3D).global_position if source is Node3D else Vector3.ZERO
	)
	if gs != null and gs.coord_map != null and gs.coord_map.has_method("to_data"):
		return gs.coord_map.to_data(world_position)
	return world_position


func _generated_actor_ready_at(source: Node, actor: String) -> bool:
	var gs = _get_game_state()
	if gs == null or source == null or actor == "" or not gs.characters.has(actor):
		return false
	if gs.has_method("is_narratively_available") \
			and not bool(gs.call("is_narratively_available", actor)):
		return false
	if gs.is_downed(actor) or gs.is_knocked_down(actor) \
			or gs.is_moving(actor) or gs.is_resting(actor) or gs.is_dodging(actor) \
			or gs.is_endocytosing(actor) or gs.is_external_traversal_active(actor) \
			or gs.is_dragging(actor) or gs.is_field_restoring(actor):
		return false
	return _generated_actor_occupies_interactable(source, actor)


func _generated_actor_occupies_interactable(source: Node, actor: String) -> bool:
	var gs = _get_game_state()
	if gs == null or source == null or actor == "" or not gs.characters.has(actor) \
			or gs.is_downed(actor) or gs.is_knocked_down(actor):
		return false
	var actor_position: Vector3 = gs.get_position(actor)
	# Generated nodes publish their accepted graph vertices to the ordinary
	# interaction controller. That typed region is also the authoritative
	# physical-arrival contract here: a Rally may legitimately park the servicing
	# body on a non-primary apron vertex, while another floor can share its X/Z.
	# Fall back to the legacy radius only for nodes with no typed region at all.
	var interaction_region_v: Variant = (
		source.get_meta("interaction_navigation_region")
		if source.has_meta("interaction_navigation_region") else null
	)
	if interaction_region_v is Dictionary \
			and not (interaction_region_v as Dictionary).is_empty():
		if gs.grid == null or not gs.has_method("get_character_level"):
			return false
		var actor_cell: Vector2i = gs.grid.world_to_grid(actor_position)
		var actor_level := int(gs.get_character_level(actor))
		for vertex_v in (interaction_region_v as Dictionary).get(
				"region_vertices", []):
			var vertex := _interaction_contract_vertex(vertex_v)
			if not vertex.is_empty() \
					and vertex.get("cell", Vector2i(-1, -1)) == actor_cell \
					and int(vertex.get("level", -1)) == actor_level:
				return true
		return false
	var source_position := _generated_interaction_data_position(source)
	if gs.grid != null and gs.grid.has_method("level_for_y") \
			and int(gs.get_character_level(actor)) != int(
				gs.grid.call("level_for_y", source_position.y)
			):
		# Stacked floors can share an x/z address. Horizontal overlap through the
		# ceiling is not physical proximity to the source on the other deck.
		return false
	var radius := float(source.get("interaction_radius")) + 0.15
	return Vector2(actor_position.x, actor_position.z).distance_to(
		Vector2(source_position.x, source_position.z)
	) <= radius


func _generated_interactable_receipt_pending(source: Node, require_one_shot: bool) -> bool:
	if source == null:
		return false
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return false
	var spec: Dictionary = gs.get_interactable(data_id)
	if bool(spec.get("one_shot", false)) != require_one_shot \
			or not bool(spec.get("triggered", false)):
		return false
	if require_one_shot:
		return bool(source.get("_used")) \
			and not bool(source.get("interaction_enabled")) \
			and not gs.is_interactable_enabled(data_id)
	# A repeatable receipt is consumed synchronously by its callback. The callback
	# resets this registry latch before returning, so a stale/public helper call
	# cannot reuse a prior physical interaction.
	return not bool(source.get("_used")) and bool(source.get("interaction_enabled"))


func _generated_node_progression_is_ready(node_id: String) -> bool:
	var predecessor := _required_progression_predecessor(node_id)
	if predecessor == "" or _completed_nodes.has(predecessor):
		return true
	for route_v in _routes():
		if not (route_v is Dictionary):
			continue
		var route := route_v as Dictionary
		var source_id := str(route.get("from", ""))
		var source_node := _find_node(source_id)
		if str(route.get("to", "")) == node_id \
				and _activated_routes.has(str(route.get("id", ""))) \
				and (
					_runtime_handler_for_node(source_node) == ""
					or _completed_nodes.has(source_id)
				):
			return true
	return false


func _generated_chain_is_ready(node: Dictionary) -> bool:
	var input_ref := str(node.get("runtime_chain_input_ref", ""))
	return input_ref == "" or _produced_chain_states.has(input_ref)


func _accepted_generated_interaction_gate() -> Dictionary:
	return {"accepted": true, "code": ""}


## Pure lookup of the first unresolved emitted branch action that must occur
## before `node_id`. This shares the solution ordering used by headless replay,
## but never walks to, triggers, advances, or mutates the producer.
func _required_unresolved_branch_action_before_node(node_id: String) -> Dictionary:
	var golden_path: Array = _spec.get("headless", {}).get("golden_path", [])
	for action_v in _ordered_solution_branch_actions():
		if not (action_v is Dictionary):
			continue
		var action := action_v as Dictionary
		if not bool(action.get("required_for_progress", false)) \
				or str(action.get("runtime_handler", "")) != "branch_span_producer":
			continue
		if not _branch_action_requires_resolution_before_node(
				action, node_id, golden_path):
			continue
		var branch_id := str(action.get("branch_id", action.get("target", "")))
		var span = _branch_span_by_id.get(branch_id, null)
		if span != null and is_instance_valid(span) \
				and bool(span.call("is_bridged")):
			continue
		var unresolved := action.duplicate(true)
		unresolved["branch_id"] = branch_id
		unresolved["runtime_missing"] = span == null or not is_instance_valid(span)
		if span != null and is_instance_valid(span) and span.has_method("get_state"):
			var state_v: Variant = span.call("get_state")
			if state_v is Dictionary:
				unresolved["runtime_phase"] = str(
					(state_v as Dictionary).get("phase", "dormant"))
		return unresolved
	return {}


## Fresh specs publish the exact typed destinations disconnected by each cut.
## That graph relation is authoritative even for optional nodes absent from the
## golden path. `before_nodes` remains only as a compatibility projection for
## older persisted specs that predate affected-node coverage.
## `affected_node_ids` is authoritative only WITHIN ITS DOMAIN. The solver builds it in
## `_affected_nodes_for_consumer_cut`, which walks the node list and skips every node carrying no
## `interaction_approach` — so the set enumerates typed interaction regions the cut disconnects, and
## says nothing whatever about a node that is not one. Reading that silence as "no resolution
## required" opened the gate on a cut that still blocked physical passage: the caller then reported
## success having activated nothing, which is a fail-OPEN in a progression gate. For a node outside
## the domain we fall back to the legacy `before_nodes` projection — the behaviour that gated it
## before affected-node coverage existed.
func _node_is_typed_interaction_region(node_id: String) -> bool:
	for node_v in _spec.get("nodes", []):
		if node_v is Dictionary and str((node_v as Dictionary).get("id", "")) == node_id:
			return (node_v as Dictionary).get("interaction_approach", null) is Dictionary
	return false


func _branch_action_requires_resolution_before_node(
		action: Dictionary, node_id: String, golden_path: Array
	) -> bool:
	if action.has("affected_node_ids") and _node_is_typed_interaction_region(node_id):
		var affected_v: Variant = action.get("affected_node_ids", null)
		if not (affected_v is Array):
			return false
		for affected_id_v in affected_v as Array:
			if str(affected_id_v) == node_id:
				return true
		return false
	var before_nodes: Array = action.get(
		"before_nodes", [str(action.get("before_node", ""))])
	var requested_index := golden_path.find(node_id)
	var scheduled_index := 2147483647
	var scheduled_here := false
	for before_node_v in before_nodes:
		var before_node_id := str(before_node_v)
		scheduled_here = scheduled_here or before_node_id == node_id
		var before_index := golden_path.find(before_node_id)
		if before_index >= 0:
			scheduled_index = mini(scheduled_index, before_index)
	return scheduled_here or (requested_index >= 0 \
		and scheduled_index <= requested_index)


## Authoritative, read-only interaction gate used both before route commitment
## and again at physical arrival. It returns data only; visual feedback lives in
## `_present_generated_interaction_refusal` and runs only after a real attempt.
func _query_generated_node_interaction_gate(
		source: Node, actor: String, node_id: String, expected_source: Node
	) -> Dictionary:
	if source == null or source != expected_source \
			or source != _node_interactables.get(node_id, null):
		return {
			"accepted": false,
			"code": "generated_source_mismatch",
			"message": "That object's interaction source is unavailable.",
			"cue": "RESOLVE FIRST // SOURCE CONTRACT UNAVAILABLE",
			"focus_node_id": node_id,
		}
	if _runtime_interaction_contract_errors.has(node_id):
		return (_runtime_interaction_contract_errors[node_id] as Dictionary).duplicate(true)
	var gs = _get_game_state()
	if actor == "" or gs == null or not gs.characters.has(actor):
		return {
			"accepted": false,
			"code": "generated_actor_unavailable",
			"message": "No available party member can service that object.",
			"cue": "RESOLVE FIRST // SELECT AN AVAILABLE CHARACTER",
			"focus_node_id": node_id,
		}
	if _completed_nodes.has(node_id):
		return {
			"accepted": false,
			"code": "generated_node_complete",
			"message": "That change has already taken effect.",
			"cue": "RESOLVE FIRST // FOLLOW THE NEXT LIT CHANGE",
			"focus_node_id": node_id,
		}
	var node := _find_node(node_id)
	if node.is_empty() or _runtime_handler_for_node(node) == "":
		return {
			"accepted": false,
			"code": "generated_handler_unavailable",
			"message": "That marker has no available interaction.",
			"cue": "RESOLVE FIRST // INTERACTION UNAVAILABLE",
			"focus_node_id": node_id,
		}
	var branch_action := _required_unresolved_branch_action_before_node(node_id)
	if not branch_action.is_empty():
		var branch_id := str(branch_action.get("branch_id", ""))
		if bool(branch_action.get("runtime_missing", false)):
			return {
				"accepted": false,
				"code": "mandatory_branch_runtime_missing",
				"message": "The required branch-span control is unavailable.",
				"cue": "RESOLVE FIRST // BRANCH CONTROL UNAVAILABLE",
				"focus_branch_id": branch_id,
			}
		var phase := str(branch_action.get("runtime_phase", "dormant"))
		return {
			"accepted": false,
			"code": "mandatory_branch_unresolved",
			"message": (
				"The lit branch span is still extending; wait for it to seat."
				if phase == "extending"
				else "The route crosses an open cut. Work the lit EXTEND terminal first."
			),
			"cue": "RESOLVE FIRST // WAIT FOR THE LIT SPAN" if (
				phase == "extending"
			) else "RESOLVE FIRST // EXTEND",
			"focus_branch_id": branch_id,
		}
	if not _generated_node_progression_is_ready(node_id):
		var predecessor := _required_progression_predecessor(node_id)
		var predecessor_node := _find_node(predecessor)
		var predecessor_title := str(
			predecessor_node.get("title", predecessor)).strip_edges()
		return {
			"accepted": false,
			"code": "generated_progression_required",
			"message": "A previous visible change has not taken effect yet.",
			"cue": "RESOLVE FIRST // %s" % predecessor_title.to_upper(),
			"focus_node_id": predecessor,
		}
	if not _generated_chain_is_ready(node):
		var input_ref := str(node.get("runtime_chain_input_ref", ""))
		var producer_id := ""
		for candidate_v in _spec.get("nodes", []):
			if candidate_v is Dictionary and str(
					(candidate_v as Dictionary).get("runtime_chain_output_ref", "")) == input_ref:
				producer_id = str((candidate_v as Dictionary).get("id", ""))
				break
		var producer := _find_node(producer_id)
		var producer_title := str(producer.get(
			"title", input_ref.replace(":", " -> "))).strip_edges()
		return {
			"accepted": false,
			"code": "generated_chain_input_required",
			"message": "The required upstream state has not arrived yet.",
			"cue": "RESOLVE FIRST // %s" % producer_title.to_upper(),
			"focus_node_id": producer_id,
		}
	var approach := _resolve_node_approach(node)
	if bool(approach.get("blocked", false)):
		return {
			"accepted": false,
			"code": "generated_capability_required",
			"message": "The current party loadout has no way through that change.",
			"cue": "RESOLVE FIRST // CHANGE PARTY APPROACH",
			"focus_node_id": node_id,
		}
	var handler_id := _runtime_handler_for_node(node)
	if handler_id in [
		RuntimeRegistryScript.HANDLER_PHYSICAL_LYSATE,
		RuntimeRegistryScript.HANDLER_PHYSICAL_PAYLOAD,
	]:
		if not gs.has_method("has_free_hand") \
				or not bool(gs.call("has_free_hand", actor)):
			return {
				"accepted": false,
				"code": "generated_free_hand_required",
				"message": "%s needs a free hand for that visible source." % actor.capitalize(),
				"cue": "RESOLVE FIRST // FREE A HAND",
				"focus_node_id": node_id,
			}
		var source_id := _node_resource_source_id(node_id)
		var claim_v: Variant = _resource_claims.get(source_id, {})
		if not (claim_v is Dictionary) \
				or not _resource_claim_item_is_at_source(gs, claim_v as Dictionary):
			return {
				"accepted": false,
				"code": "generated_source_item_missing",
				"message": "The marked physical source is no longer present there.",
				"cue": "RESOLVE FIRST // RECOVER THE MARKED SOURCE",
				"focus_node_id": node_id,
			}
	if node_id == "exit_shelter":
		var payload_delivery := _required_payload_delivery()
		if not bool(payload_delivery.get("ready", false)):
			var payload_node := str(payload_delivery.get("node_id", ""))
			var payload_reason := str(payload_delivery.get("reason", "missing"))
			return {
				"accepted": false,
				"code": "generated_payload_delivery_required",
				"outcome": "payload_delivery_blocked:%s:%s" % [
					payload_node, payload_reason],
				"message": "A required physical load has not reached shelter in a party member's hand.",
				"cue": "RESOLVE FIRST // RECOVER THE LIT LOAD",
				"focus_node_id": payload_node,
			}
	return _accepted_generated_interaction_gate()


## Presentation-only half of the route gate. It is invoked after a real click
## is rejected (or after an arrival-time race), never by the read-only query.
func _present_generated_interaction_refusal(
		source: Node,
		_actor: String,
		result: Dictionary,
		node_id: String,
		expected_source: Node
	) -> void:
	if source == null or source != expected_source \
			or source != _node_interactables.get(node_id, null):
		return
	var focus_target: Node3D = null
	var focus_branch_id := str(result.get("focus_branch_id", ""))
	if focus_branch_id != "":
		var span = _branch_span_by_id.get(focus_branch_id, null)
		if span != null and is_instance_valid(span) \
				and span.has_method("get_producer_interactable"):
			var producer_v: Variant = span.call("get_producer_interactable")
			if producer_v is Node3D and is_instance_valid(producer_v):
				focus_target = producer_v as Node3D
				if focus_target.has_method("set_highlight"):
					focus_target.call("set_highlight", true)
				if focus_target.has_method("show_tutorial_label"):
					focus_target.call("show_tutorial_label")
	var focus_node_id := str(result.get("focus_node_id", ""))
	if focus_node_id != "":
		_highlight_node(focus_node_id, true)
		var node_target_v: Variant = _node_targets.get(focus_node_id, null)
		if focus_target == null and node_target_v is Node3D \
				and is_instance_valid(node_target_v):
			focus_target = node_target_v as Node3D
	_show_message(str(result.get(
		"message", "That interaction is not ready yet.")), 2.4)
	var cue := str(result.get("cue", "RESOLVE FIRST // FOLLOW THE LIT CHANGE"))
	if not cue.begins_with("RESOLVE FIRST //"):
		cue = "RESOLVE FIRST // %s" % cue
	_show_note(cue, 4.0)
	if focus_target != null:
		# The CharacterInteractionController/Interactable has just emitted a red
		# result on the exact object the player clicked. Let that receipt survive
		# multiple rendered frames before showing an off-screen prerequisite; an
		# immediate camera cut would make a correct rejection visually unprovable.
		var focus_timer := get_tree().create_timer(0.6)
		focus_timer.timeout.connect(
			_focus_generated_interaction_prerequisite.bind(
				focus_target.get_instance_id()))


func _focus_generated_interaction_prerequisite(target_instance_id: int) -> void:
	var target_v: Object = instance_from_id(target_instance_id)
	if not (target_v is Node3D) or not is_instance_valid(target_v):
		return
	_request_preview_focus(
		target_v as Node3D,
		1.6,
		false,
		{
			"reason": "generated_interaction_prerequisite",
			"hold": 0.45,
			"offscreen_only": true,
		}
	)


func _validate_generated_node_trigger(
	source: Node, actor: String, node_id: String, expected_source: Node
) -> bool:
	if source == null or source != expected_source \
			or source != _node_interactables.get(node_id, null):
		return false
	if not _generated_actor_ready_at(source, actor):
		var actor_label := actor.capitalize() if actor != "" else "The selected character"
		var readiness_refusal := {
			"accepted": false,
			"code": "generated_actor_not_at_interaction_region",
			"message": "%s has not reached and settled on the marked interaction apron." % actor_label,
			"cue": "RESOLVE FIRST // APPROACH THE MARKED OBJECT",
			"focus_node_id": node_id,
		}
		_present_generated_interaction_refusal(
			source, actor, readiness_refusal, node_id, expected_source)
		return false
	var gate := _query_generated_node_interaction_gate(
		source, actor, node_id, expected_source)
	if bool(gate.get("accepted", false)):
		return true
	# State can change while the selected servicer is walking. Re-run the same
	# pure contract at arrival and present the now-current prerequisite before
	# Interactable emits the exact red source-token result.
	_present_generated_interaction_refusal(
		source, actor, gate, node_id, expected_source)
	return false


func _rearm_generated_node_control(source: Node) -> void:
	if source != null and source.has_method("reset"):
		source.call("reset")
	_apply_resource_claim_presenters()


func _rearm_resource_source(source: Node) -> void:
	if source != null and is_instance_valid(source) and source.has_method("reset"):
		source.call("reset")
	_apply_resource_claim_presenters()


## Generated geometry may put a later marker within clicking distance, but causal
## progression still follows the semantic node chain. A non-main route may bypass
## that chain only after the route itself has been explicitly activated from a
## completed source node. This keeps every seed honest without hard-coding node ids.
func _node_progression_ready(node_id: String) -> bool:
	var predecessor := _required_progression_predecessor(node_id)
	if predecessor == "" or _completed_nodes.has(predecessor):
		return true
	for route_v in _routes():
		if not (route_v is Dictionary):
			continue
		var route := route_v as Dictionary
		var source_id := str(route.get("from", ""))
		var source_node := _find_node(source_id)
		if (
			str(route.get("to", "")) == node_id
			and _activated_routes.has(str(route.get("id", "")))
			and (
				_runtime_handler_for_node(source_node) == ""
				or _completed_nodes.has(source_id)
			)
		):
			return true
	var predecessor_node := _find_node(predecessor)
	var predecessor_title := str(predecessor_node.get("title", predecessor)).strip_edges()
	_route_phase = "blocked"
	_last_outcome = "order_blocked:%s:%s" % [node_id, predecessor]
	_set_preview_step("generated_stretch_order_blocked")
	_highlight_node(predecessor, true)
	_show_message("A previous change has not taken effect yet.", 1.4)
	_show_note("RESOLVE FIRST // %s" % predecessor_title, 3.0)
	return false


func _required_progression_predecessor(node_id: String) -> String:
	var nodes := _nodes()
	var node_index := -1
	for index in range(nodes.size()):
		var node_v: Variant = nodes[index]
		if node_v is Dictionary and str((node_v as Dictionary).get("id", "")) == node_id:
			node_index = index
			break
	if node_index <= 0:
		return ""
	for index in range(node_index - 1, -1, -1):
		var previous_v: Variant = nodes[index]
		if not (previous_v is Dictionary):
			continue
		var previous := previous_v as Dictionary
		if bool(previous.get("optional", false)):
			continue
		if _runtime_handler_for_node(previous) == "":
			continue
		if previous.has("runtime_progression_required") and not bool(previous.get("runtime_progression_required", false)):
			continue
		var previous_id := str(previous.get("id", ""))
		# The party begins inside the entry boundary; the first interior beat is ready.
		return "" if previous_id == "entry" else previous_id
	return ""


## Compatibility stub that always refuses. Generated progress begins only in
## _on_generated_node_interacted after the exact one-shot has been consumed.
func activate_generated_node(_node_id: String, _interaction_actor := "") -> bool:
	return false


func _commit_generated_node_from_receipt(node_id: String, source: Node) -> bool:
	_ensure_spec_loaded()
	if source == null or source != _node_interactables.get(node_id, null) \
			or not _generated_interactable_receipt_pending(source, true):
		return false
	var interaction_actor := str(source.get("active_character"))
	if not _generated_actor_ready_at(source, interaction_actor):
		return false
	var node := _find_node(node_id)
	if node.is_empty():
		_last_outcome = "missing_node:%s" % node_id
		return false
	var handler_id := _runtime_handler_for_node(node)
	if handler_id == "":
		# Spatial/decorative archetypes are deliberately not actions. Walking through
		# their room-piece is sufficient; they never become invisible checkpoints.
		_last_outcome = "layout_only:%s" % node_id
		return false
	if not _completed_nodes.has(node_id) and not _node_progression_ready(node_id):
		return false
	if not _completed_nodes.has(node_id) and not _chain_progression_ready(node):
		return false
	var approach := _resolve_node_approach(node)
	if bool(approach.get("blocked", false)):
		if not _blocked_nodes.has(node_id):
			_blocked_nodes.append(node_id)
		_route_phase = "blocked"
		_last_outcome = "blocked:%s" % node_id
		_set_preview_step("generated_stretch_blocked")
		_show_note(
			(
				"%s has no way through %s."
				% [_active_loadout.capitalize(), str(node.get("title", node_id))]
			),
			2.0
		)
		return false

	_node_approach_used[node_id] = approach
	var first_completion := not _completed_nodes.has(node_id)
	match handler_id:
		RuntimeRegistryScript.HANDLER_PHYSICAL_LYSATE:
			if first_completion and not _secure_generated_resource_from_receipt(
				node, interaction_actor, source
			):
				return false
		RuntimeRegistryScript.HANDLER_PHYSICAL_PAYLOAD:
			if first_completion and not _secure_generated_resource_from_receipt(
				node, interaction_actor, source
			):
				return false
		RuntimeRegistryScript.HANDLER_CANONICAL_SHELTER_ARRIVAL:
			if not _reach_exit_shelter():
				return false
	if first_completion and not _completed_nodes.has(node_id):
		_completed_nodes.append(node_id)
		var chain_output_ref := str(node.get("runtime_chain_output_ref", ""))
		if chain_output_ref != "":
			_produced_chain_states[chain_output_ref] = node_id
		# Every playable section must resolve its advertised local cause -> effect
		# transition. Chain outputs are optional progression data; nesting this under
		# that condition left ordinary sections permanently showing their pre-action
		# prediction even after the interaction had completed.
		_apply_generated_section_transition(node, true, interaction_actor)
	if first_completion and handler_id == RuntimeRegistryScript.HANDLER_PHYSICAL_LYSATE:
		_show_message("Lysate secured for a later ATP decision.", 1.8)
	elif first_completion and handler_id == RuntimeRegistryScript.HANDLER_PHYSICAL_PAYLOAD:
		_show_message("Physical load secured. Keep it in an active carrier's hand until shelter.", 2.2)
	if handler_id != RuntimeRegistryScript.HANDLER_CANONICAL_SHELTER_ARRIVAL:
		_route_phase = "moving"
		_last_outcome = "node:%s" % node_id
		_set_preview_step("generated_stretch_%s" % node_id)
	_highlight_node(node_id, true)
	_publish_generated_runtime_authority()
	return true


## Update the presenter only when it was created by a concrete runtime handler
## binding. Completion never recolors or rescales an arbitrary mesh guessed from
## section prose; the handler's real item/shelter state is the world
## consequence, while this exact link only compares prediction with observation.
func _apply_generated_section_transition(
	node: Dictionary, animate := true, interaction_actor := ""
) -> void:
	var node_id := str(node.get("id", ""))
	if node_id == "" or not _generated_section_states.has(node_id):
		return
	var section: Dictionary = node.get("playable_section", {})
	var state := _generated_section_states[node_id] as Dictionary
	var handler_id := _runtime_handler_for_node(node)
	if (
		str(state.get("runtime_handler", "")) != handler_id
		or (
			str(state.get("runtime_binding_id", ""))
			!= _generated_feedback_binding_id(handler_id)
		)
	):
		return
	state["state"] = "complete"
	state["observed_effect"] = str(section.get("completed_preview", section.get("after_state", "changed")))
	_generated_section_states[node_id] = state
	var interactable: Node = _node_interactables.get(node_id, null)
	if interactable != null and is_instance_valid(interactable):
		# The post-state remains inspectable, but no longer lies by offering the same
		# pre-commit verb after the consequence has already happened.
		interactable.set("tutorial_label", "REVIEW RESULT")
		interactable.set("consequence_preview", state["observed_effect"])
		interactable.set("dwell_time", 0.0)
		interactable.set("interactable_type", Interactable.InteractableType.INSPECTION)
	var party_endpoint: Node = _generated_party_endpoints.get(node_id, null)
	if party_endpoint != null and is_instance_valid(party_endpoint):
		if interaction_actor != "":
			party_endpoint.set_meta("character_id", interaction_actor)
		party_endpoint.set_meta("locked_character", true)
	var target = state.get("target", null)
	if target is Node3D and is_instance_valid(target):
		(target as Node3D).set_meta("generated_section_state", "complete")
		(target as Node3D).set_meta("generated_observed_effect", state["observed_effect"])
	var link = _generated_section_links.get(node_id, null)
	if link != null and is_instance_valid(link):
		link.call("set_feedback_mode", "complete")
		link.call("set_latched", animate)
		if animate:
			link.call("flash", 1.6, 1.35)
			link.call("pulse_arrival", 1.25, 1.0)
			get_tree().create_timer(1.75).timeout.connect(func():
				if is_instance_valid(link):
					link.call("set_latched", false)
			)


func _generated_feedback_binding_id(handler_id: String) -> String:
	match handler_id:
		RuntimeRegistryScript.HANDLER_PHYSICAL_LYSATE:
			return FEEDBACK_BINDING_LYSATE_TO_CARRIER
		RuntimeRegistryScript.HANDLER_PHYSICAL_PAYLOAD:
			return FEEDBACK_BINDING_PAYLOAD_TO_CARRIER
		RuntimeRegistryScript.HANDLER_CANONICAL_SHELTER_ARRIVAL:
			return FEEDBACK_BINDING_PARTY_TO_SHELTER
	return ""


## Headless/playtest readout without exposing live node references.
func get_generated_section_state(node_id: String) -> Dictionary:
	if not _generated_section_states.has(node_id):
		return {}
	var state := (_generated_section_states[node_id] as Dictionary).duplicate()
	var source = state.get("source", null)
	var target = state.get("target", null)
	state["source_name"] = str(source.name) if source is Node and is_instance_valid(source) else ""
	state["target_name"] = str(target.name) if target is Node and is_instance_valid(target) else ""
	state.erase("source")
	state.erase("target")
	return state


func _chain_progression_ready(node: Dictionary) -> bool:
	var input_ref := str(node.get("runtime_chain_input_ref", ""))
	if input_ref == "" or _produced_chain_states.has(input_ref):
		return true
	var producer_id := ""
	for candidate_v in _nodes():
		if candidate_v is Dictionary and str((candidate_v as Dictionary).get("runtime_chain_output_ref", "")) == input_ref:
			producer_id = str((candidate_v as Dictionary).get("id", ""))
			break
	_route_phase = "blocked"
	_last_outcome = "chain_state_missing:%s:%s" % [str(node.get("id", "")), input_ref]
	_set_preview_step("generated_stretch_chain_state_blocked")
	if producer_id != "":
		_highlight_node(producer_id, true)
	_show_message("The required upstream state has not arrived yet.", 1.6)
	_show_note("MISSING INPUT // %s" % input_ref.replace(":", " → "), 3.0)
	return false


func _headless_activate_generated_node(node_id: String) -> bool:
	# The generated solution can place a proven blocker before the requested
	# physical source. A headless activation is already a deterministic journey
	# helper, so it must execute that emitted mandatory detour through the live
	# producer instead of attempting an impossible path or opening the cut by fiat.
	if not _headless_resolve_required_branch_actions_before_node(node_id):
		return false
	var source: Node = _node_interactables.get(node_id, null)
	if source == null or not is_instance_valid(source):
		_last_outcome = "headless_missing_interactable:%s" % node_id
		return false
	var interaction_actor := _headless_generated_interaction_actor(node_id)
	if interaction_actor == "":
		_last_outcome = "headless_no_actor:%s" % node_id
		return false
	if node_id == "exit_shelter" and host != null:
		var region := _exit_shelter_region()
		var center: Vector3 = region.get("center", Vector3.INF)
		if center == Vector3.INF:
			_last_outcome = "headless_missing_exit_region"
			return false
		var companion_offsets := [
			Vector3(0.0, 0.0, -1.1),
			Vector3.ZERO,
			Vector3(0.0, 0.0, 1.1),
		]
		var companion_index := 0
		for actor_v in _active_party:
			var actor := str(actor_v)
			# Shelter arrival has two simultaneous physical predicates: the whole
			# party must occupy the sanctuary, and the servicing actor must occupy
			# the exact one-shot anchor. Giving every actor a generic center offset
			# satisfied the first while leaving Aster just outside interaction range.
			var target := _generated_interaction_data_position(source)
			if actor != interaction_actor:
				var offset: Vector3 = (
					companion_offsets[companion_index]
					if companion_index < companion_offsets.size()
					else Vector3.ZERO
				)
				target = center + offset
				companion_index += 1
			if not _headless_move_character_to(actor, target):
				_last_outcome = "headless_exit_move_failed:%s" % actor
				return false
	else:
		if not _headless_move_character_to(
			interaction_actor, _generated_interaction_data_position(source)
		):
			_last_outcome = "headless_node_move_failed:%s:%s" % [
				node_id, interaction_actor
			]
			return false
	source.set("active_character", interaction_actor)
	var triggered := bool(source.call("_trigger", false))
	if not triggered:
		_last_outcome = "headless_trigger_rejected:%s:%s" % [
			node_id, interaction_actor
		]
	return triggered


## Read-only diagnostic seam for focused integration tests. It exposes the same
## production route gate a shipped pointer command queries, together with the
## exact clicked surface's public red/green presentation receipt. It never moves
## a character, triggers an interaction, or mutates scenario state.
func _headless_generated_interaction_diagnostics(node_id: String) -> Dictionary:
	var source: Node = _node_interactables.get(node_id, null)
	if source == null or not is_instance_valid(source):
		return {
			"gate": {
				"accepted": false,
				"code": "generated_source_mismatch",
			},
			"presentation": {},
		}
	var actor := _headless_generated_interaction_actor(node_id)
	var gate := _query_generated_node_interaction_gate(
		source, actor, node_id, source)
	var presentation: Dictionary = {}
	if source.has_method("get_player_interaction_presentation"):
		var presentation_v: Variant = source.call(
			"get_player_interaction_presentation")
		if presentation_v is Dictionary:
			presentation = (presentation_v as Dictionary).duplicate(true)
	return {
		"gate": gate.duplicate(true),
		"presentation": presentation,
	}


func _headless_resolve_required_branch_actions_before_node(node_id: String) -> bool:
	var golden_path: Array = _spec.get("headless", {}).get("golden_path", [])
	for action_v in _ordered_solution_branch_actions():
		if not (action_v is Dictionary):
			continue
		var action := action_v as Dictionary
		if not _branch_action_requires_resolution_before_node(
				action, node_id, golden_path):
			continue
		var branch_id := str(action.get("branch_id", action.get("target", "")))
		var span = _branch_span_by_id.get(branch_id, null)
		if span != null and is_instance_valid(span) \
				and bool(span.call("is_bridged")):
			continue
		if not _headless_activate_branch_span(action):
			_last_outcome = "required_branch_action_failed:%s:%s" % [
				branch_id, node_id
			]
			return false
	return true


func _headless_generated_interaction_actor(node_id: String) -> String:
	var node := _find_node(node_id)
	var handler_id := _runtime_handler_for_node(node)
	var candidates: Array[String] = []
	var active := _get_active_character()
	if active != "":
		candidates.append(active)
	for candidate_v in _active_party:
		var candidate := str(candidate_v)
		if candidate != "" and not candidates.has(candidate):
			candidates.append(candidate)
	var gs = _get_game_state()
	for candidate in candidates:
		if gs == null or not gs.characters.has(candidate) or gs.is_downed(candidate):
			continue
		if handler_id in [
			RuntimeRegistryScript.HANDLER_PHYSICAL_LYSATE,
			RuntimeRegistryScript.HANDLER_PHYSICAL_PAYLOAD,
		] and (not gs.has_method("has_free_hand") or not bool(gs.call("has_free_hand", candidate))):
			continue
		return candidate
	return ""


## Compatibility stub that always refuses. A route becomes active only after a canonical body
## walks its authored surface and arrives at the exact destination.
func choose_generated_route(_route_id: String, _activate_target := true) -> bool:
	return false


func _record_generated_route_arrival(route_id: String, actor: String) -> bool:
	_ensure_spec_loaded()
	var route := _find_route(route_id)
	var gs = _get_game_state()
	if route.is_empty() or gs == null or not gs.characters.has(actor) \
			or not _generated_route_source_is_ready(route):
		return false
	var surface: Dictionary = route.get("surface", {})
	var destination := _vec3(
		surface.get("to", []), _node_position(str(route.get("to", "")))
	)
	if destination == Vector3.INF or not _headless_character_reached(actor, destination):
		return false
	_route_choice = route_id
	if not _activated_routes.has(route_id):
		_activated_routes.append(route_id)
	var risk := _route_risk_value(route)
	var kind := _route_kind(route)
	if kind == "risky" or risk > 1:
		if str(_spec.get("biome", "")) == "cleanstreets" and not _theme_setpiece_roots.is_empty():
			# Cleanstreets makes the route price spatial and continuous: the visible studs on the
			# route-risk cells deal it. Do not also levy the generic destination-wide near-miss tax.
			_show_note("DIRECT LANE // Active studs spend health only while crossed.", 2.2)
		else:
			# Choosing a semantic route is planning, not impact. The marked GridRiskField
			# cells charge only bodies that physically enter them on a scheduler beat.
			_show_note(
				"RISKY ROUTE // Rust-marked cells spend health while occupied; speed or route around them.",
				2.6
			)
		_route_phase = "recovering" if str(route.get("recovery", "")) != "" else "danger"
	elif kind == "shortcut":
		_shortcut_unlocked = true
		_route_phase = "shortcut"
	else:
		_route_phase = "moving"
	_last_outcome = "route:%s" % route_id
	_set_preview_step("generated_stretch_%s" % route_id)
	_publish_generated_runtime_authority()
	return true


## Ordinary GameState movement owns generated route arrival. The signal is the
## receipt boundary; the existing route check still requires a ready source and
## the canonical body on the exact authored destination cell. Presenter updates,
## teleports, and render frames never call this path.
func _on_generated_character_arrived(actor: String) -> void:
	if actor == "" or not _active_party.has(actor) or _shelter_reached:
		return
	# Spec order is deterministic. If authored routes share a destination, one
	# arrival can commit only the first still-uncommitted ready route.
	for route_v in _routes():
		if not (route_v is Dictionary):
			continue
		var route := route_v as Dictionary
		var route_id := str(route.get("id", ""))
		if route_id == "" or _activated_routes.has(route_id):
			continue
		if _record_generated_route_arrival(route_id, actor):
			return


func _ensure_generated_route_arrival_authority() -> bool:
	var gs = _get_game_state()
	var callback := Callable(self, "_on_generated_character_arrived")
	if _generated_route_game_state != gs:
		if _generated_route_game_state != null \
				and is_instance_valid(_generated_route_game_state) \
				and _generated_route_game_state.character_arrived.is_connected(callback):
			_generated_route_game_state.character_arrived.disconnect(callback)
		_generated_route_game_state = gs
	if gs == null:
		return false
	if not gs.character_arrived.is_connected(callback):
		gs.character_arrived.connect(callback)
	return true


func _detach_generated_route_arrival_authority() -> void:
	var gs = _generated_route_game_state
	var callback := Callable(self, "_on_generated_character_arrived")
	if gs != null and is_instance_valid(gs) \
			and gs.character_arrived.is_connected(callback):
		gs.character_arrived.disconnect(callback)
	_generated_route_game_state = null


func _generated_route_source_is_ready(route: Dictionary) -> bool:
	var source_id := str(route.get("from", ""))
	var source_node := _find_node(source_id)
	if source_id == "" or source_node.is_empty():
		return false
	# Layout-only nodes are terrain, not switches. Requiring them in
	# `_completed_nodes` would make their outgoing route impossible because they
	# deliberately own no Interactable. Actionable sources still require their
	# exact physical consequence before a body can commit to the next route.
	return (
		_runtime_handler_for_node(source_node) == ""
		or _completed_nodes.has(source_id)
	)


func _headless_traverse_generated_route(route_id: String, actor := "") -> bool:
	var route := _find_route(route_id)
	if route.is_empty():
		return false
	var traveler := actor
	if traveler == "":
		traveler = _headless_generated_interaction_actor(str(route.get("to", "")))
	if traveler == "":
		return false
	var surface: Dictionary = route.get("surface", {})
	var waypoints: Array[Vector3] = []
	for key in ["from", "midpoint", "to"]:
		var fallback := (
			_node_position(str(route.get("from", "")))
			if key == "from"
			else _node_position(str(route.get("to", "")))
		)
		var point := _vec3(surface.get(key, []), fallback)
		if point != Vector3.INF and (waypoints.is_empty() or not waypoints.back().is_equal_approx(point)):
			waypoints.append(point)
	for point in waypoints:
		if not _headless_move_character_to(traveler, point):
			return false
	# The ordinary GameState arrival signal normally committed this route at the
	# final waypoint. Keep the explicit receipt only for headless hosts that do
	# not expose/forward that signal, without publishing the same arrival twice.
	if _activated_routes.has(route_id):
		return true
	return _record_generated_route_arrival(route_id, traveler)


func _solution_world_actions(solution: Dictionary = {}) -> Array:
	var resolved := solution
	if resolved.is_empty():
		resolved = _spec.get("headless", {}).get("solution", {})
	return resolved.get("world_actions", [])


func _solution_branch_actions(solution: Dictionary = {}) -> Array:
	var resolved := solution
	if resolved.is_empty():
		resolved = _spec.get("headless", {}).get("solution", {})
	return resolved.get("branch_actions", [])


func _ordered_solution_branch_actions(solution: Dictionary = {}) -> Array:
	var ordered: Array = []
	for action_v in _solution_branch_actions(solution):
		if action_v is Dictionary:
			ordered.append(action_v)
	ordered.sort_custom(func(a: Variant, b: Variant) -> bool:
		var action_a := a as Dictionary
		var action_b := b as Dictionary
		var order_a := int(action_a.get("solution_order", 2147483647))
		var order_b := int(action_b.get("solution_order", 2147483647))
		if order_a != order_b:
			return order_a < order_b
		return str(action_a.get("branch_id", action_a.get("target", ""))) \
			< str(action_b.get("branch_id", action_b.get("target", "")))
	)
	return ordered


func _run_solution_world_action(_action_id: String, action: Dictionary = {}) -> bool:
	if str(action.get("runtime_handler", "")) == "branch_span_producer":
		return _headless_activate_branch_span(action)
	return false


func _headless_advance_scheduler_to(target_tick: float) -> bool:
	var scheduler = _get_scheduler()
	if scheduler == null:
		return false
	var now := float(scheduler.get_current_tick())
	if target_tick > now:
		scheduler.advance_ticks(target_tick - now)
	return float(scheduler.get_current_tick()) >= target_tick - 0.000001


func _headless_move_character_to(actor: String, target: Vector3) -> bool:
	var gs = _get_game_state()
	var scheduler = _get_scheduler()
	if gs == null or scheduler == null or not gs.characters.has(actor):
		return false
	# Headless movement consumes the same SAFE/DIRECT choice exposed by the host.
	# Focused hosts do not have the preview controller that normally mirrors this
	# setting into GameState, so commit the logged routing command when needed.
	var cautious := _get_routing_mode() != "direct"
	if bool(gs.is_route_cautious()) != cautious:
		gs.set_route_mode(cautious)
	# Exercise the same stable graph-location boundary as hover/click playback.
	# Generated interactions can live on another authored deck; a raw position
	# command would preserve the current floor and silently approach through it.
	var navigation_location: Dictionary = {}
	var accepted := false
	if gs.grid != null:
		navigation_location = gs.resolve_navigation_location(actor, target)
		if navigation_location.is_empty():
			return false
		accepted = bool(gs.command_move_to_navigation_location(actor, navigation_location))
	else:
		accepted = bool(gs.command_move_to_pos(actor, target))
	if not accepted:
		return false
	# Movement is an ordinary deterministic plan. Jumping to its analytic deadline
	# executes the normal arrival callback without fabricating an endpoint state.
	for _attempt in range(8):
		if not bool(gs.is_moving(actor)):
			return _headless_character_reached(actor, target, navigation_location)
		var plan_end_tick := float(gs.get_plan_end_tick(actor))
		var now := float(scheduler.get_current_tick())
		if plan_end_tick < now:
			return false
		var advance := maxf(plan_end_tick - now, 0.000001)
		scheduler.advance_ticks(advance)
	return not bool(gs.is_moving(actor)) \
		and _headless_character_reached(actor, target, navigation_location)


func _headless_character_reached(
		actor: String,
		target: Vector3,
		navigation_location: Dictionary = {}
	) -> bool:
	var gs = _get_game_state()
	if gs == null or not gs.characters.has(actor) or bool(gs.is_downed(actor)):
		return false
	var actual: Vector3 = gs.get_position(actor)
	if gs.grid != null:
		var resolved := navigation_location
		if resolved.is_empty():
			resolved = gs.resolve_navigation_location(actor, target)
		if resolved.is_empty():
			return false
		return int(gs.get_character_level(actor)) == int(resolved.get("level", -1)) \
			and gs.grid.world_to_grid(actual) == resolved.get("cell", Vector2i(-1, -1))
	return actual.distance_to(target) <= 0.05


func _headless_activate_branch_span(action: Dictionary) -> bool:
	_ensure_branch_span_producers_ready()
	var branch_id := str(action.get("branch_id", action.get("target", "")))
	var span = _branch_span_by_id.get(branch_id, null)
	if span == null or not is_instance_valid(span):
		_last_outcome = "missing_branch_span:%s" % branch_id
		return false
	if bool(span.call("is_bridged")):
		return true
	var gs = _get_game_state()
	var scheduler = _get_scheduler()
	if gs == null or scheduler == null:
		return false
	var state: Dictionary = span.call("get_state")
	var actor := str(action.get("character", ""))
	if actor.is_empty() or not gs.characters.has(actor):
		var healthiest_hp := -1.0
		for candidate_v in _active_party:
			var candidate := str(candidate_v)
			if not gs.characters.has(candidate) or bool(gs.is_downed(candidate)):
				continue
			var candidate_hp := float(gs.get_stat(candidate, "hp"))
			if candidate_hp > healthiest_hp:
				actor = candidate
				healthiest_hp = candidate_hp
	if actor.is_empty():
		return false
	var detour_return_position: Vector3 = gs.get_position(actor)
	var producer_position: Vector3 = state.get("producer_data_position", Vector3.ZERO)
	if not _headless_move_character_to(actor, producer_position):
		_last_outcome = "branch_span_producer_move_failed:%s:%s" % [
			branch_id, actor
		]
		return false
	var producer: Node = span.call("get_producer_interactable")
	if producer == null or not is_instance_valid(producer):
		return false
	producer.set("active_character", actor)
	if not bool(producer.call("_trigger", false)):
		_last_outcome = "branch_span_producer_trigger_rejected:%s:%s" % [
			branch_id, actor
		]
		_headless_move_character_to(actor, detour_return_position)
		return false
	if bool(action.get("wait_for_completion", true)):
		var committed: Dictionary = span.call("get_state")
		if not _headless_advance_scheduler_to(
			float(scheduler.get_current_tick()) + maxf(0.0, float(committed.get("remaining", 0.0)))
		):
			return false
	var completed := bool(span.call("is_bridged"))
	# Walk back to the schematic position from which this mandatory detour began;
	# later presence checks then inherit a real, replayable route history.
	var returned := _headless_move_character_to(actor, detour_return_position)
	if not completed:
		_last_outcome = "branch_span_producer_incomplete:%s:%s" % [branch_id, actor]
	elif not returned:
		_last_outcome = "branch_span_return_move_failed:%s:%s" % [branch_id, actor]
	return completed and returned


func _apply_solution_world_actions_before_node(
	solution: Dictionary, node_id: String, consumed_action_indices: Dictionary = {}
) -> int:
	var applied := 0
	var groups := [
		{"namespace": "world", "actions": _solution_world_actions(solution)},
		{"namespace": "branch", "actions": _solution_branch_actions(solution)},
	]
	for group_v in groups:
		var group := group_v as Dictionary
		var records: Array = group.get("actions", [])
		for action_index in range(records.size()):
			var action_key := "%s:%d" % [str(group.get("namespace", "action")), action_index]
			if consumed_action_indices.has(action_key):
				continue
			var action_v: Variant = records[action_index]
			if not (action_v is Dictionary):
				continue
			var action := action_v as Dictionary
			if str(action.get("before_node", "")) != node_id:
				continue
			if _run_solution_world_action(str(action.get("action", "")), action):
				consumed_action_indices[action_key] = true
				applied += 1
	return applied


func run_generated_golden_path() -> bool:
	_ensure_spec_loaded()
	reset_preview_state()
	set_active_loadout("spotlight")
	_route_phase = "golden"
	var solution: Dictionary = _spec.get("headless", {}).get("solution", {})
	var path: Array = _spec.get("headless", {}).get("golden_path", [])
	if path.is_empty():
		path = ["entry", "exit_shelter"]
	var consumed_world_actions := {}
	for node_id in path:
		var resolved_node_id := str(node_id)
		_apply_solution_world_actions_before_node(
			solution, resolved_node_id, consumed_world_actions
		)
		_headless_activate_generated_node(resolved_node_id)
	if not _shelter_rested and _blocked_nodes.is_empty():
		_headless_activate_generated_node("exit_shelter")
	_route_choice = "golden_path"
	return _shelter_rested


## The emitted solution as replayable data (spec.headless.solution) — the ordered, per-node approach a full party
## takes to clear the golden path. For tests + an in-game/Android replay to CONSUME (not re-derive).
func get_solution_script() -> Dictionary:
	_ensure_spec_loaded()
	return (_spec.get("headless", {}).get("solution", {}) as Dictionary).duplicate(true)


## REPLAY the emitted solution end-to-end at the data layer, CONSUMING spec.headless.solution (not re-deriving the
## plan): drive each node in the solution's order and check the approach that actually clears it MATCHES the emitted
## approach_id — so the shipped solution data faithfully describes a real playthrough. Returns
## {complete, steps, approach_mismatches, blocked}. `complete` proves the emitted solution beats the puzzle.
func replay_generated_solution() -> Dictionary:
	_ensure_spec_loaded()
	reset_preview_state()
	var sol: Dictionary = _spec.get("headless", {}).get("solution", {})
	set_active_loadout(str(sol.get("loadout", "spotlight")))
	_route_phase = "solution_replay"
	var actions: Array = sol.get("actions", [])
	var actions_by_node := {}
	for action_v in actions:
		if action_v is Dictionary:
			actions_by_node[str((action_v as Dictionary).get("node", ""))] = action_v
	var path: Array = _spec.get("headless", {}).get("golden_path", [])
	if path.is_empty():
		path.assign(actions_by_node.keys())
	var mismatches := 0
	var steps := 0
	var world_steps := 0
	var consumed_world_actions := {}
	for node_id_v in path:
		var node_id := str(node_id_v)
		world_steps += _apply_solution_world_actions_before_node(
			sol, node_id, consumed_world_actions
		)
		var action_v: Variant = actions_by_node.get(node_id, null)
		if not (action_v is Dictionary):
			_headless_activate_generated_node(node_id)
			continue
		var action := action_v as Dictionary
		_headless_activate_generated_node(node_id)
		steps += 1
		var used: Dictionary = _node_approach_used.get(node_id, {})
		var used_id := str(used.get("id", used.get("approach_id", "")))
		var want_id := str(action.get("approach_id", ""))

		# Only real puzzle approaches are comparable — traverse / entry / exit carry no chosen approach.
		if want_id != "" and want_id != "traverse" and used_id != "" and used_id != want_id:
			mismatches += 1
	if not _shelter_rested and _blocked_nodes.is_empty():
		_headless_activate_generated_node("exit_shelter")
	_route_choice = "solution_replay"
	return {
		"complete": _shelter_rested,
		"steps": steps,
		"world_steps": world_steps,
		"approach_mismatches": mismatches,
		"blocked": _blocked_nodes.duplicate(),
	}


## The shadow solution: the same node spine solved by the Aster+Peris pair alone.
## Each puzzle node falls through to its shadow approach (no specialist on hand), so a
## completed shadow run is a genuinely different solution path than the golden run.
func run_generated_shadow_path() -> bool:
	_ensure_spec_loaded()
	reset_preview_state()
	set_active_loadout("shadow")
	_route_phase = "shadow"
	var solution: Dictionary = _spec.get("headless", {}).get("solution", {})
	var path: Array = _spec.get("headless", {}).get("golden_path", [])
	if path.is_empty():
		path = ["entry", "exit_shelter"]
	var consumed_world_actions := {}
	for node_id in path:
		var resolved_node_id := str(node_id)
		_apply_solution_world_actions_before_node(
			solution, resolved_node_id, consumed_world_actions
		)
		_headless_activate_generated_node(resolved_node_id)
	if not _shelter_rested and _blocked_nodes.is_empty():
		_headless_activate_generated_node("exit_shelter")
	_route_choice = "shadow_path"
	return _shelter_rested


## The approaches the active party actually used, in the order nodes were cleared —
## the data an in-game or Android replay animates.
func get_active_solution_path() -> Array:
	var path := []
	for node_id in _completed_nodes:
		var approach: Dictionary = _node_approach_used.get(node_id, {})
		(
			path
			. append(
				{
					"node": node_id,
					"approach_id": str(approach.get("id", approach.get("approach_id", ""))),
					"kind": str(approach.get("kind", "")),
					"party": str(approach.get("party", "")),
					"label": str(approach.get("label", "")),
					"risk": str(approach.get("risk", "")),
				}
			)
		)
	return path


func run_generated_risky_recovery() -> bool:
	_ensure_spec_loaded()
	reset_preview_state()
	var solution: Dictionary = _spec.get("headless", {}).get("solution", {})
	var risky_route := {}
	for route in _routes():
		if route is Dictionary and _route_kind(route as Dictionary) == "risky":
			risky_route = (route as Dictionary).duplicate(true)
			break
	if risky_route.is_empty():
		_route_choice = "no_risky_route"
		_route_phase = "recovered"
		return run_generated_golden_path()
	var path: Array = _spec.get("headless", {}).get("golden_path", [])
	var source_id := str(risky_route.get("from", ""))
	var source_index := path.find(source_id)
	if source_index < 0:
		_route_choice = "risky_recovery_invalid_source"
		return false
	var consumed_world_actions := {}
	for index in range(source_index + 1):
		var prefix_node_id := str(path[index])
		_apply_solution_world_actions_before_node(
			solution, prefix_node_id, consumed_world_actions
		)
		_headless_activate_generated_node(prefix_node_id)
	if not _headless_traverse_generated_route(str(risky_route.get("id", ""))):
		return false
	var risky_target_id := str(risky_route.get("to", ""))
	_apply_solution_world_actions_before_node(solution, risky_target_id, consumed_world_actions)
	_headless_activate_generated_node(risky_target_id)
	for index in range(source_index + 1, path.size()):
		var suffix_node_id := str(path[index])
		_apply_solution_world_actions_before_node(
			solution, suffix_node_id, consumed_world_actions
		)
		_headless_activate_generated_node(suffix_node_id)
	_headless_activate_generated_node("exit_shelter")
	if _route_choice == "" or _route_choice == "no_risky_route":
		_route_choice = "risky_recovery"
	return _shelter_rested


## A failed traversal: the party commits to the risky route and takes the
## pressure, but is stranded short of the next shelter — the stretch is never
## crossed. Returns false (the run did not reach safety).
func run_generated_failed_traversal() -> bool:
	_ensure_spec_loaded()
	reset_preview_state()
	for route in _routes():
		if route is Dictionary and _route_kind(route as Dictionary) == "risky":
			var route_data := route as Dictionary
			var source_id := str(route_data.get("from", ""))
			var source_node := _find_node(source_id)
			if _runtime_handler_for_node(source_node) != "" \
					and not _completed_nodes.has(source_id) \
					and not _headless_activate_generated_node(source_id):
				continue
			if _headless_traverse_generated_route(str(route_data.get("id", ""))):
				break
	if _route_choice == "":
		_route_choice = "failed_traversal"
	_route_phase = "failed"
	_shelter_reached = false
	_shelter_rested = false
	_last_outcome = "stranded"
	_set_preview_step("generated_stretch_failed")
	return _shelter_rested


func _load_spec_from_config() -> void:
	_spec.clear()
	_generation_fallback.clear()
	var raw_spec: Variant = _config.get("spec", {})
	if raw_spec is Dictionary and not (raw_spec as Dictionary).is_empty():
		var canonical_spec := StretchGeneratorScript.canonicalize_spec(raw_spec as Dictionary)
		var spec_validation := StretchGeneratorScript.validate_spec_acceptance(
			canonical_spec)
		if bool(spec_validation.get("valid", false)):
			_spec = canonical_spec
			_ensure_graybox_layout()
			_ensure_navigation_layout()
			return
		if StretchGeneratorScript._legacy_snapshot_requires_full_regeneration(
				canonical_spec, spec_validation):
			var regenerated_legacy := StretchGeneratorScript.generate(
				(canonical_spec.get("settings", {}) as Dictionary).duplicate(true))
			if bool(regenerated_legacy.get("success", false)):
				_spec = regenerated_legacy
				_generation_fallback = {
					"active": true,
					"requested_seed": int(
						canonical_spec.get("settings", {}).get("seed", 0)),
					"requested_tier": str(
						canonical_spec.get("settings", {}).get(
							"complexity_tier", "unknown")),
					"error": "stale inline snapshot rejected; complete snapshot regenerated from settings",
				}
				push_warning(
					"generated_stretch: rejected stale inline snapshot and regenerated its complete spatial/solver snapshot from settings")
				_record_generation_fallback_actual()
				return
		_generation_fallback = {
			"active": true,
			"requested_seed": int(canonical_spec.get("settings", {}).get("seed", 0)),
			"requested_tier": str(
				canonical_spec.get("settings", {}).get("complexity_tier", "unknown")
			),
			"error": "; ".join(spec_validation.get("errors", [])),
		}
		push_warning(
			"generated_stretch: rejected stale or malformed supplied spec; loading an explicit fallback (%s)"
			% str(_generation_fallback.get("error", "invalid fixed content"))
		)
	var raw_settings: Variant = _config.get("settings", {})
	if raw_settings is Dictionary and not (raw_settings as Dictionary).is_empty():
		var generation_settings := (raw_settings as Dictionary).duplicate(true)
		if _config.has("seed"):
			generation_settings["seed"] = int(_config.get("seed", generation_settings.get("seed", 1)))
		var generated: Dictionary = StretchGeneratorScript.generate(generation_settings)
		if bool(generated.get("success", false)):
			_spec = generated
			_ensure_graybox_layout()
			_ensure_navigation_layout()
			return
		_generation_fallback = {
			"active": true,
			"requested_seed": int(generation_settings.get("seed", 0)),
			"requested_tier": str(generation_settings.get("complexity_tier", "unknown")),
			"error": _generation_failure_summary(generated),
		}
		push_warning(
			"generated_stretch: requested %s seed %d failed; loading an explicit fallback (%s)"
			% [
				str(_generation_fallback.get("requested_tier", "unknown")),
				int(_generation_fallback.get("requested_seed", 0)),
				str(_generation_fallback.get("error", "generation failed")),
			]
		)
	var path := str(_config.get("spec_path", default_spec_path))
	var loaded := StretchGeneratorScript.load_spec(path, true)
	if not loaded.is_empty():
		# A saved case is a configuration snapshot, not a frozen result. Supplying a
		# seed regenerates the same profile so N/custom QA variations exercise the
		# current generator rules rather than stale serialized geometry.
		if _config.has("seed") and loaded.get("settings", {}) is Dictionary:
			var loaded_settings := (loaded.get("settings", {}) as Dictionary).duplicate(true)
			loaded_settings["seed"] = int(_config.get("seed", loaded_settings.get("seed", 1)))
			var regenerated: Dictionary = StretchGeneratorScript.generate(loaded_settings)
			if bool(regenerated.get("success", false)):
				loaded = regenerated
			else:
				if _generation_fallback.is_empty():
					_generation_fallback = {
						"active": true,
						"requested_seed": int(loaded_settings.get("seed", 0)),
						"requested_tier": str(loaded_settings.get("complexity_tier", "unknown")),
						"error": _generation_failure_summary(regenerated),
					}
				push_warning(
					"generated_stretch: seed variation failed; saved fallback is visibly labeled (%s)"
					% str(_generation_fallback.get("error", "generation failed"))
				)
		_spec = loaded
		_record_generation_fallback_actual()
		_ensure_graybox_layout()
		_ensure_navigation_layout()


func _record_generation_fallback_actual() -> void:
	if _generation_fallback.is_empty() or _spec.is_empty():
		return
	_generation_fallback["active"] = true
	_generation_fallback["actual_seed"] = int(
		_spec.get("source", {}).get("seed", _spec.get("settings", {}).get("seed", 0))
	)
	_generation_fallback["actual_tier"] = str(
		_spec.get("source", {}).get(
			"complexity_tier", _spec.get("settings", {}).get("complexity_tier", "unknown")
		)
	)


func _generation_failure_summary(result: Dictionary) -> String:
	var direct_error := str(result.get("error", "")).strip_edges()
	if direct_error != "":
		return direct_error
	var validation: Variant = result.get("validation", {})
	if validation is Dictionary:
		for key in (validation as Dictionary).keys():
			var section: Variant = (validation as Dictionary)[key]
			if section is Dictionary:
				var errors: Variant = (section as Dictionary).get("errors", [])
				if errors is Array and not (errors as Array).is_empty():
					return str((errors as Array)[0])
			elif key == "errors" and section is Array and not (section as Array).is_empty():
				return str((section as Array)[0])
	return "Generator validation failed."


func _ensure_spec_loaded() -> void:
	if not _spec.is_empty():
		return
	_config = {"spec_path": default_spec_path}
	_load_spec_from_config()
	if _spec.is_empty():
		_spec = (
			StretchGeneratorScript
			. generate(
				{
					"id": "generated_fallback_stretch",
					"title": "Generated Fallback Stretch",
					"seed": 1701,
					"complexity_tier": "teaching",
				}
			)
		)
	_record_generation_fallback_actual()
	_ensure_graybox_layout()
	_ensure_navigation_layout()


func _clear_generated_children() -> void:
	_detach_generated_route_arrival_authority()
	for child in get_children():
		child.free()

	_causal_feedback_links.clear()
	_interactables.clear()
	_node_markers.clear()
	_node_targets.clear()
	_node_interactables.clear()
	_generated_capbages.clear()
	_generated_scarpets.clear()
	_generated_hushblooms.clear()
	_route_surfaces.clear()
	_spatial_feature_roots.clear()
	_theme_landmark_roots.clear()
	_theme_setpiece_roots.clear()
	_theme_hazard_contacts.clear()
	_route_risk_field = null
	_route_risk_contacts.clear()


func _build_foundation() -> void:
	# The floor is built FROM the walkable grid cells as atlas TILES — so the visible surface (and its collision)
	# is EXACTLY where the player can walk. A big rectangular slab would eat clicks the grid then rejects.
	_build_walkable_floor()
	var graybox: Dictionary = _spec.get("graybox", {})
	var bounds: Dictionary = graybox.get("bounds", {})
	var bounds_center := _vec3(bounds.get("center", []), Vector3(12.0, 0.0, 0.0))
	var bounds_size := _vec3(bounds.get("size", []), Vector3(24.0, 3.0, 10.0))
	var min_point := _vec3(bounds.get("min", []), bounds_center - bounds_size * 0.5)
	var theme: Dictionary = _spec.get("area_theme", {})
	var hierarchy := _visual_hierarchy()
	# The fill hangs 8 m above the middle of the deck — expressed, like every other placement in this
	# chunk, in the FLAT authoring frame and put where it belongs by the coord map. The deck's own
	# vertices take that warp one at a time, so a fill left flat would hang off the side of the helix
	# instead of over the walkway: on a 76-unit spiral the flat midpoint lands 40 m from the warped
	# deck's centre, past the light's own range, and the deck it is meant to fill gets nothing. Height
	# rides through as a lift, so the light keeps its 8 m of clearance over the deck at that arc, and
	# lighting a floor from above rather than from the spiral's axis is what puts light on an upward-
	# facing surface at all. A flat stretch warps through identity and is placed exactly as authored.
	_decorative_fill_light = _add_light(
		self,
		_warp_pos(Vector3(bounds_center.x, min_point.y + 8.0, bounds_center.z)),
		_color_from_array(theme.get("light_color", []), Color(0.72, 0.86, 0.96)),
		float(theme.get("light_energy", 1.25))
			* float(hierarchy.get("decorative_fill_scale", 0.34)),
		maxf(34.0, bounds_size.x * 0.5)
	)
	_decorative_fill_light.set_meta("visual_role", "decorative_fill")


## Draw a tiled floor quad for every WALKABLE grid cell (per level), risky cells rusted, and give it collision so
## the player's ground-click raycast only lands where they can actually move. Visible floor == traversable floor.
func _build_walkable_floor() -> void:
	var nav: Dictionary = _nav_grid()
	if nav.is_empty():
		return
	var grid = GridWorld.from_data(nav)
	var cell := float(nav.get("cell_size", 1.0))
	var risk := {}
	for r in nav.get("risk_cell_list", []):
		if r is Dictionary and r.has("cell"):
			risk[Vector2i(int((r.cell as Array)[0]), int((r.cell as Array)[1]))] = true
	var cells_by_level := {}
	var level_cells: Array = nav.get("level_cells", [])
	if not level_cells.is_empty():
		for entry in level_cells:
			if entry is Dictionary:
				cells_by_level[int(entry.get("level", 0))] = entry.get("cells", [])
	else:
		cells_by_level[0] = nav.get("walkable_cells", [])
	for lvl in cells_by_level.keys():
		_build_floor_surface(grid, int(lvl), cells_by_level[lvl], risk, cell)


func _build_floor_surface(grid, lvl: int, cells: Array, risk: Dictionary, cell: float) -> void:
	var st_main := SurfaceTool.new()
	st_main.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_risk := SurfaceTool.new()
	st_risk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_edge := SurfaceTool.new()
	st_edge.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_transition := SurfaceTool.new()
	st_transition.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_risk := false
	var has_edge := false
	var has_transition := false
	var h := cell * 0.5
	var transition: Dictionary = _spec.get("zone_transition", {})
	var entry_node := _find_node("entry")
	var transition_enabled := (
		not transition.is_empty()
		and not entry_node.is_empty()
		and int(entry_node.get("elevation_index", 0)) == lvl
	)
	var entry_flat := _anchor_position("entry")
	var transition_length := maxf(
		cell * 3.0,
		float(transition.get("length_cells", 6)) * cell
	)
	# WHERE THE DECK ACTUALLY ENDS. A brink is a property of the emitted SURFACE, not of the walkable
	# set: a branch gap and a feature-owned cell are both real openings, so the cells beside them are
	# brinks even though the grid calls their neighbours walkable. Skipping either test here gives the
	# tile at the lip of a drop the same read as one in the middle of the deck, which is the whole
	# thing the brink surface exists to prevent.
	var emitted_cells := {}
	for cp in cells:
		var scan := Vector2i(int((cp as Array)[0]), int((cp as Array)[1]))
		if _branch_gap_cells.has(scan):
			continue
		if _spatial_feature_replaces_flat_cell(grid.grid_to_world(scan, lvl), lvl):
			continue
		emitted_cells[scan] = true
	for cp in cells:
		var v := Vector2i(int((cp as Array)[0]), int((cp as Array)[1]))
		# Mandatory branch output replaces this authored tile. The data cell remains in GridWorld so the
		# authoritative phase can block it while dormant/extending and open it when the physical span seats.
		if _branch_gap_cells.has(v):
			continue
		var w: Vector3 = grid.grid_to_world(v, lvl)
		if _spatial_feature_replaces_flat_cell(w, lvl):
			continue
		var is_risk: bool = risk.has(v)
		# Orthogonal only. A diagonal neighbour touches at a corner, which is not a walkable seam and
		# not something the player can step across, so a missing one does not make this tile a brink.
		var is_edge: bool = (
			not emitted_cells.has(v + Vector2i(1, 0))
			or not emitted_cells.has(v + Vector2i(-1, 0))
			or not emitted_cells.has(v + Vector2i(0, 1))
			or not emitted_cells.has(v + Vector2i(0, -1))
		)
		if is_risk:
			has_risk = true

		# Top surface at floor Y (+0.02 so overlays read above it); a thin SOLID slab so the click-raycast
		# reliably lands on it (a flat zero-thickness trimesh doesn't register a downward ray). Each tile's
		# top CORNERS are warped through the coord map individually — adjacent cells share their flat corner
		# points, so their warped vertices coincide and the deck stays watertight with a tile seam on every
		# data-cell boundary at every lane (a rigid per-cell frame left wedge gaps where the warp fans the
		# outer lanes). Flat levels warp through identity and get the same axis-aligned tile as before.
		var flat_corners := [
			w + Vector3(-h, 0.0, -h),
			w + Vector3(h, 0.0, -h),
			w + Vector3(h, 0.0, h),
			w + Vector3(-h, 0.0, h),
		]
		var corners := [
			_warp_pos(flat_corners[0]),
			_warp_pos(flat_corners[1]),
			_warp_pos(flat_corners[2]),
			_warp_pos(flat_corners[3]),
		]
		var transition_distance := Vector2(w.x - entry_flat.x, w.z - entry_flat.z).length()
		var uses_transition := transition_enabled and not is_risk \
			and transition_distance <= transition_length + h
		if uses_transition:
			has_transition = true
			_zone_transition_floor_cell_count += 1
			var corner_blends: Array[float] = []
			for flat_corner_v in flat_corners:
				var flat_corner := flat_corner_v as Vector3
				var corner_distance := Vector2(
					flat_corner.x - entry_flat.x,
					flat_corner.z - entry_flat.z
				).length()
				corner_blends.append(clampf(corner_distance / transition_length, 0.0, 1.0))
			_add_floor_slab(st_transition, corners, 0.16, corner_blends)
		else:
			# A RISK cell that is also a brink stays on the risk surface. The rust tint is the only
			# carrier of "this tile hurts", and nothing else in the frame says it; the brink read
			# survives the loss because the risk tint is already the most separated floor colour from
			# the void, so the tile's outer boundary still draws itself against the drop.
			var target := st_main
			if is_risk:
				target = st_risk
			elif is_edge:
				target = st_edge
				has_edge = true
			_add_floor_slab(target, corners, 0.16)
	var theme: Dictionary = _spec.get("area_theme", {})
	var hierarchy := _visual_hierarchy()
	var floor_tile := str(theme.get("floor_tile", "deck_metal"))
	var risk_tile := str(theme.get("risk_tile", "rust_iron"))
	_commit_floor_surface(
		st_main,
		"GeneratedFloor_L%d" % lvl,
		_generated_floor_material(
			floor_tile,
			_color_from_array(hierarchy.get("floor_tint", []), Color(0.38, 0.46, 0.46))
		),
		lvl
	)
	if has_edge:
		_commit_floor_surface(
			st_edge,
			"GeneratedFloorEdge_L%d" % lvl,
			_generated_floor_edge_material(
				_color_from_array(hierarchy.get("edge_tint", []), Color(0.62, 0.74, 0.74))
			),
			lvl
		)
	if has_risk:
		_commit_floor_surface(
			st_risk,
			"GeneratedFloorRisk_L%d" % lvl,
			_generated_floor_material(
				risk_tile,
				_color_from_array(hierarchy.get("risk_tint", []), Color(0.42, 0.27, 0.18))
			),
			lvl
		)
	if has_transition:
		_commit_floor_surface(
			st_transition,
			"GeneratedZoneTransition_L%d" % lvl,
			_zone_transition_floor_material(transition),
			lvl
		)


## The brink is PAINT, and paint covers the tread. It carries the deck tint lifted toward its own
## light rather than a second material's colour, so the walkway still reads as one surface with a
## marked border. Dropping the tile is what lets the tint reach the frame at all: the deck tile
## averages 0.22 brightness, so a tinted deck slab in a district capped at 0.42 ambient renders at
## roughly one 8-bit step above black, and a rim built that way is invisible however it is tinted.
func _generated_floor_edge_material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.88
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _generated_floor_material(tile_name: String, tint: Color) -> StandardMaterial3D:
	var material := _tiled_floor_material(tile_name)
	material.albedo_color = tint
	material.roughness = 0.92
	return material


func _zone_transition_floor_material(transition: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = ZoneTransitionFloorShader
	var tile_root := "res://resources/models/elevator/tiles/"
	var from_texture = load(tile_root + str(transition.get("from_floor_tile", "deck_metal")) + ".png")
	var to_texture = load(tile_root + str(transition.get("to_floor_tile", "deck_metal")) + ".png")
	if from_texture != null:
		material.set_shader_parameter("from_texture", from_texture)
	if to_texture != null:
		material.set_shader_parameter("to_texture", to_texture)
	var from_light := _color_from_array(
		transition.get("from_light_color", []), Color(0.5, 0.55, 0.58)
	)
	var to_light := _color_from_array(
		transition.get("to_light_color", []), Color(0.5, 0.55, 0.58)
	)
	material.set_shader_parameter("threshold_tint", from_light.lerp(to_light, 0.5))
	material.set_shader_parameter(
		"surface_tint",
		_color_from_array(_visual_hierarchy().get("floor_tint", []), Color(0.38, 0.46, 0.46))
	)
	return material


## Feature prefabs own the visible standing surface and its raycast collision. Excluding those cells from the
## generic solid floor is what makes the grate gaps visually real while the authoritative GridWorld remains
## unchanged. The comparison happens in flat data space, before any helix warp.
func _spatial_feature_replaces_flat_cell(flat_position: Vector3, level: int) -> bool:
	for feature_v in _spec.get("spatial_features", []):
		if not (feature_v is Dictionary):
			continue
		var feature := feature_v as Dictionary
		if not bool(feature.get("floor_replacement", false)) \
				or int(feature.get("elevation_index", 0)) != level:
			continue
		var center := _vec3(feature.get("position", []), Vector3.INF)
		var footprint := _vec3(feature.get("footprint", []), Vector3.ZERO)
		if center == Vector3.INF or footprint == Vector3.ZERO:
			continue
		if absf(flat_position.x - center.x) <= footprint.x * 0.5 - 0.01 \
				and absf(flat_position.z - center.z) <= footprint.z * 0.5 - 0.01:
			return true
	return false


## Instantiate authored room-piece features selected by WFC. The generator supplies only data bindings and a
## causal contract; mesh, grate spacing, rail collision, sockets, supports and lighting remain editor-authored
## nodes in the prefab. This root is built in flat space and warped with the other node dressing below.
func _build_spatial_features() -> void:
	for feature_v in _spec.get("spatial_features", []):
		if not (feature_v is Dictionary):
			continue
		var feature := feature_v as Dictionary
		var scene_path := str(feature.get("scene", ""))
		var packed := load(scene_path) as PackedScene
		if packed == null:
			continue
		var root := packed.instantiate() as Node3D
		if root == null:
			continue
		var node_id := str(feature.get("node_id", "node"))
		root.name = "GeneratedSpatialFeature_%s" % node_id
		root.position = _vec3(feature.get("position", []), Vector3.ZERO)
		root.set_meta("contract_id", str(feature.get("contract_id", "")))
		root.set_meta("feature_kind", str(feature.get("kind", "")))
		root.set_meta("node_id", node_id)
		root.set_meta("archetype_id", str(feature.get("archetype_id", "")))
		root.set_meta("causal_model", (feature.get("causal_model", {}) as Dictionary).duplicate(true))
		root.add_to_group("generated_spatial_feature")
		var label := root.get_node_or_null("DeckLabel") as Label3D
		if label != null:
			match str(feature.get("feature_variant", "")):
				"signal_roost":
					label.text = "SIGNAL / RESPONSE DECK"
				"split_perch":
					label.text = "DISTRACTION / TASK DECK"
				"charge_intersection":
					label.text = "BAIT LINE / IMPACT TARGET"
				"dose_crossing":
					label.text = "SHORT DOSE / SAFE DETOUR"
				_:
					label.text = "GRATED SYSTEM DECK"
		add_child(root)
		_spatial_feature_roots.append(root)
		_spatial_fixture_count += 1


## Main-game area identity for roguelite stretches. These are authored district clusters placed by the
## generator beside compatible systemic nodes; this presenter only instantiates and seats them on the same
## flat-to-helix transform as the node they frame. No building geometry is synthesized here.
func _build_theme_landmarks() -> void:
	for landmark_v in _spec.get("themed_landmarks", []):
		if not (landmark_v is Dictionary):
			continue
		var landmark := landmark_v as Dictionary
		var scene_path := str(landmark.get("scene", ""))
		var packed := load(scene_path) as PackedScene
		if packed == null:
			continue
		var root := packed.instantiate() as Node3D
		if root == null:
			continue
		_apply_decorative_landmark_hierarchy(root)
		var landmark_id := str(landmark.get("id", "district_landmark"))
		root.name = "GeneratedThemeLandmark_%s" % landmark_id
		root.position = _vec3(landmark.get("position", []), Vector3.ZERO)
		root.rotation.y = float(landmark.get("rotation_y", 0.0))
		root.set_meta("contract_id", str(landmark.get("contract_id", "")))
		root.set_meta("theme_id", str(landmark.get("theme_id", "")))
		root.set_meta("source_area", str(landmark.get("source_area", "")))
		root.set_meta("anchor_node_id", str(landmark.get("anchor_node_id", "")))
		root.set_meta("primary_read", str(landmark.get("primary_read", "")))
		root.set_meta("feedback_role", str(landmark.get("feedback_role", "")))
		root.add_to_group("generated_theme_landmark")
		add_child(root)
		_theme_landmark_roots.append(root)
		_spatial_fixture_count += 1


## Theme landmarks are generator-proven off-route scenery. Recede only their opaque,
## non-emissive mass; authored signal strips, warning lamps, transparency, labels, and
## gameplay fixtures retain their original materials. Each material is duplicated so a
## generated instance never mutates the source prefab or another level instance.
func _apply_decorative_landmark_hierarchy(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var original := mesh_instance.material_override
		if original is StandardMaterial3D:
			var source := original as StandardMaterial3D
			if (
				not source.emission_enabled
				and source.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
			):
				var material := source.duplicate() as StandardMaterial3D
				var scale := clampf(
					float(_visual_hierarchy().get("landmark_albedo_scale", 0.62)), 0.25, 1.0
				)
				var color := material.albedo_color
				material.albedo_color = Color(
					color.r * scale, color.g * scale, color.b * scale, color.a
				)
				mesh_instance.material_override = material
				mesh_instance.set_meta("visual_role", "decorative_mass")
	for child in node.get_children():
		_apply_decorative_landmark_hierarchy(child)


## The generator has already proven port compatibility and reachable placement. The presenter uses
## SceneChunk's shared materializer, so this is the same interaction/feedback object as a data fragment,
## merely seated in the generated stretch's flat frame before the normal helix warp pass.
func _build_infrastructure_operations() -> void:
	for operation_v in _spec.get("infrastructure_operations", []):
		if not (operation_v is Dictionary):
			continue
		var operation_spec := (operation_v as Dictionary).duplicate(true)
		var built := _add_infrastructure_operation(operation_spec)
		if built.is_empty():
			continue
		built["spec"] = operation_spec
		_infrastructure_runtime.append(built)
		var operation = built.get("operation")
		if is_instance_valid(operation) and operation.has_method("set_authority_publisher"):
			operation.call(
				"set_authority_publisher",
				Callable(self, "_publish_generated_runtime_authority")
			)
		_spatial_fixture_count += 3 # source control, receiver control, environmental field


func _infrastructure_operation_authority_state() -> Dictionary:
	var states: Dictionary = {}
	for runtime_v in _infrastructure_runtime:
		var operation = (runtime_v as Dictionary).get("operation")
		if not is_instance_valid(operation) or not operation.has_method("serialize_state"):
			continue
		var operation_state: Dictionary = operation.call("serialize_state")
		var operation_id := str(operation_state.get("operation_id", ""))
		if operation_id != "":
			states[operation_id] = operation_state
	return states


func _restore_infrastructure_operation_authority(states: Variant) -> void:
	for idx in range(_infrastructure_runtime.size()):
		var operation = (_infrastructure_runtime[idx] as Dictionary).get("operation")
		if not is_instance_valid(operation) or not operation.has_method("restore_state"):
			continue
		var operation_state: Variant = {}
		if states is Dictionary:
			operation_state = (states as Dictionary).get(str(operation.get("operation_id")), {})
		elif states is Array and idx < (states as Array).size():
			operation_state = (states as Array)[idx]
		operation.call("restore_state", operation_state)


## Interactive district fixtures use authored scenes just like landmarks, but sit ON navigation risk cells.
## Their scripts retain the flat-space coverage used by GameState after the visible root is wrapped onto a helix.
func _build_theme_setpieces() -> void:
	for setpiece_v in _spec.get("themed_setpieces", []):
		if not (setpiece_v is Dictionary):
			continue
		var setpiece := setpiece_v as Dictionary
		var scene_path := str(setpiece.get("scene", ""))
		var packed := load(scene_path) as PackedScene
		if packed == null:
			continue
		var root := packed.instantiate() as Node3D
		if root == null:
			continue
		root.name = "GeneratedThemeSetpiece_%s" % str(setpiece.get("id", "route_setpiece"))
		if root.has_method("configure"):
			root.call("configure", setpiece)
		else:
			root.position = _vec3(setpiece.get("position", []), Vector3.ZERO)
			root.rotation.y = float(setpiece.get("rotation_y", 0.0))
		root.set_meta("contract_id", str(setpiece.get("contract_id", "")))
		root.set_meta("theme_id", str(setpiece.get("theme_id", "")))
		root.set_meta("setpiece_kind", str(setpiece.get("kind", "")))
		root.set_meta("risk_cell", (setpiece.get("risk_cell", []) as Array).duplicate())
		root.set_meta("primary_read", str(setpiece.get("primary_read", "")))
		root.set_meta("leverage", str(setpiece.get("leverage", "")))
		root.set_meta("failure_prediction", str(setpiece.get("failure_prediction", "")))
		root.add_to_group("generated_theme_setpiece")
		add_child(root)
		_theme_setpiece_roots.append(root)
		_spatial_fixture_count += 1


## A thin box (floor tile with thickness) built from four already-warped TOP corner points (order: -s-lane,
## +s-lane, +s+lane, -s+lane in the flat frame). Its top sits +0.02 above the corners (just above the deck so
## overlays read) and drops `thick` straight down. A closed solid so its trimesh collision is a dependable ray
## target from above (a flat quad isn't). Because the corners are warped per-vertex, adjacent cells share
## corner points and the deck tiles watertight on flat AND warped levels alike.
func _add_floor_slab(
	st: SurfaceTool,
	corners: Array,
	thick: float,
	corner_blends: Array[float] = []
) -> void:
	var lift := Vector3.UP * 0.02
	var drop := Vector3.DOWN * thick
	var A: Vector3 = corners[0] + lift
	var B: Vector3 = corners[1] + lift
	var C: Vector3 = corners[2] + lift
	var D: Vector3 = corners[3] + lift
	var E := A + drop
	var F := B + drop
	var G := C + drop
	var H := D + drop
	var blends: Array[float] = [1.0, 1.0, 1.0, 1.0]
	if corner_blends.size() == 4:
		blends = corner_blends
	var ca := Color(float(blends[0]), 0.0, 0.0, 1.0)
	var cb := Color(float(blends[1]), 0.0, 0.0, 1.0)
	var cc := Color(float(blends[2]), 0.0, 0.0, 1.0)
	var cd := Color(float(blends[3]), 0.0, 0.0, 1.0)
	# WINDING DECIDES THE NORMAL, and _tri_auto derives the normal from the winding. These two faces
	# were wound so the TOP of the slab pointed DOWN (measured: (0.13, -0.96, -0.24) on the first
	# vertices), which meant every generated floor was lit from behind and rendered black — on both
	# renderers, at any light energy, immune to fog and overlays, and still visible in silhouette only
	# because the material disables culling. Wind the top counter-clockwise from above and the bottom
	# the other way, so each face is lit from the side you can actually stand on.
	_tri_auto(st, A, B, C, ca, cb, cc)
	_tri_auto(st, A, C, D, ca, cc, cd)  # top
	_tri_auto(st, E, G, F, ca, cc, cb)
	_tri_auto(st, E, H, G, ca, cd, cc)  # bottom
	_tri_auto(st, A, B, F, ca, cb, cb)
	_tri_auto(st, A, F, E, ca, cb, ca)  # -lane side
	_tri_auto(st, D, H, G, cd, cd, cc)
	_tri_auto(st, D, G, C, cd, cc, cc)  # +lane side
	_tri_auto(st, A, E, H, ca, ca, cd)
	_tri_auto(st, A, H, D, ca, cd, cd)  # -s side
	_tri_auto(st, B, C, G, cb, cc, cc)
	_tri_auto(st, B, G, F, cb, cc, cb)  # +s side


## Emit one triangle with its face normal derived from the (possibly warped) vertices themselves.
func _tri_auto(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	color_a := Color.WHITE,
	color_b := Color.WHITE,
	color_c := Color.WHITE
) -> void:
	var n := (b - a).cross(c - a)
	st.set_normal(n.normalized() if n.length_squared() > 1e-12 else Vector3.UP)
	st.set_color(color_a)
	st.add_vertex(a)
	st.set_color(color_b)
	st.add_vertex(b)
	st.set_color(color_c)
	st.add_vertex(c)


func _commit_floor_surface(
		st: SurfaceTool, node_name: String, mat: Material, navigation_level: int
	) -> void:
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.set_meta("navigation_level", navigation_level)
	# THE GROUND IS NEVER AN OCCLUDER. Camera occlusion fades geometry between the camera and the
	# party, and it decides what qualifies from AABB height against a minimum (the preview passes
	# 2.0). A floor slab is 0.16 thick and should never pass that gate — but every level's floor is
	# committed as ONE merged surface, so on a warped/spiral stretch its bounding box spans the whole
	# descent (measured 14.88 m) and sails through. The result was the entire walkable surface faded
	# out: generated levels rendered as black silhouettes in play, on both renderers, immune to fog,
	# overlays and lighting because fading is none of those things.
	mi.set_meta("camera_occlusion_exempt", true)
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = node_name + "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	# Physics rays hit the collision body, not the visible mesh. Preserve which
	# generated graph floor was clicked so Player can invert a warped world hit in
	# that surface's data frame instead of silently flattening it to level zero.
	body.set_meta("navigation_level", navigation_level)
	# Ground commands use Player's explicit layer-1 physics ray. The viewport object picker must
	# pierce this walkable shell so a slightly grazing view cannot give the floor a target's RMB.
	body.input_ray_pickable = false
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)


func _build_generated_routes() -> void:
	for route in _routes():
		if not (route is Dictionary):
			continue
		var route_def := route as Dictionary
		var from_pos := _node_position(str(route_def.get("from", "")))
		var to_pos := _node_position(str(route_def.get("to", "")))
		if from_pos == Vector3.INF or to_pos == Vector3.INF:
			continue
		_build_route_segment(route_def, from_pos, to_pos)


func _build_route_segment(route: Dictionary, from_pos: Vector3, to_pos: Vector3) -> void:
	var middle := (from_pos + to_pos) * 0.5
	var delta := to_pos - from_pos
	var horizontal_length := maxf(0.8, sqrt(delta.x * delta.x + delta.z * delta.z))
	var width := maxf(0.4, float(route.get("width", route.get("surface", {}).get("width", 1.2))))
	var route_rotation := Vector3(0.0, atan2(delta.z, delta.x), -atan2(delta.y, horizontal_length))

	# Visual-only accent (no collision) — the tiled walkable floor owns click collision, so a straight route box
	# spanning non-walkable cells can't eat a click.
	var route_box := _add_graybox_slab(
		self,
		middle + Vector3(0.0, 0.045, 0.0),
		Vector3(horizontal_length, 0.09, width),
		_route_color(route),
		"Route_%s" % str(route.get("id", "")),
		route_rotation,
		false
	)
	_route_surfaces[str(route.get("id", ""))] = route_box
	var label_pos := middle + Vector3(0.0, 0.82, 0.0)
	var route_label := "%s / R%d" % [_route_kind(route).to_upper(), _route_risk_value(route)]
	if _route_kind(route) == "risky":
		route_label = "RISKY // MARKED FLOOR HURTS WHILE OCCUPIED"
	_add_label(
		self,
		route_label,
		label_pos,
		_route_color(route).lightened(0.28)
	)


## Build the meta-template's one-way recovery points. The upper anchor is reached through ordinary forward
## progression, Peris tends it, and the authored vine deploys down to the later/lower turn. Only the lower mouth
## becomes traversable, so this can recover already-solved ground without becoming a forward puzzle bypass.
## Deployment and climbing are GameState state machines; this node only presents and binds those states.
func _build_return_points() -> void:
	if _coord_map == null or _meta_template == null:
		return
	var gs = _get_game_state()
	var scheduler = _get_scheduler()
	if gs == null or scheduler == null:
		return
	var specs: Array = _meta_template.return_point_specs(
		_spine_navigation_grid(), _coord_map
	)
	var climbs := 0
	for spec in specs:
		var kind := str(spec.get("kind", ""))
		# Refuse unknown return nouns instead of silently turning one into a portal-like rectangle.
		if kind != "climb":
			push_warning("Generated return point rejected unsupported kind '%s'" % kind)
			continue
		var upper: Vector3 = spec.get("upper", Vector3.ZERO)
		var lower: Vector3 = spec.get("lower", Vector3.ZERO)
		var climbvine = ClimbvineReturnScript.new()
		climbvine.name = "ClimbvineReturn_%02d" % climbs
		var return_id := "%s_climbvine_%02d" % [str(_spec.get("id", "generated_stretch")), climbs]
		var configured := bool(climbvine.configure(
			gs,
			scheduler,
			lower,
			upper,
			_coord_map.to_world(lower),
			_coord_map.to_world(upper),
			{
				"return_id": return_id,
				"interaction_radius": 1.65,
				"deployment_duration": 2.5,
				"climb_duration": 3.4,
			}
		))
		if not configured:
			climbvine.free()
			push_warning("Generated climbvine '%s' could not bind its authoritative state" % return_id)
			continue
		climbvine.set_group_provider(Callable(self, "_climbvine_selected_group"))
		add_child(climbvine)
		for interactable in climbvine.get_interactables():
			_register_interactable(interactable)
		_climbvines.append(climbvine)
		climbs += 1


func _climbvine_selected_group() -> Array:
	if host != null and host.has_method("get_preview_selected_characters"):
		var selected: Variant = host.call("get_preview_selected_characters")
		if selected is Array and not (selected as Array).is_empty():
			return (selected as Array).duplicate()
	var active := _get_active_character()
	if active != "":
		return [active]
	return _active_party.duplicate()


## Compatibility readback for forward drops, which must stay absent (recovery is the gated climbvine climb).
func get_drop_down_count() -> int:
	return _drop_downs.size()


func get_climbvine_count() -> int:
	return _climbvines.size()


func _climbvine_states() -> Array:
	var states: Array = []
	for climbvine in _climbvines:
		if is_instance_valid(climbvine) and climbvine.has_method("get_state"):
			states.append(climbvine.call("get_state"))
	return states


## Hosts call this immediately after installing get_grid_data() as GameState.grid. It closes the construction
## ordering gap without making the reusable mechanism depend on the preview shell. Later `_process` retries are
## idempotent, but remain closed until this explicit receipt proves the outgoing grid has been replaced.
func on_game_state_grid_ready() -> void:
	_branch_span_grid_ready = true
	_ensure_branch_span_producers_ready()


## Production loading replaces GameState after the chunk has already configured its presenters.
## Rebuild scheduler-owned helpers from their portable GameState records; no local preview flag is
## allowed to grant a fresh interval or suppress a callback that was active at save time.
func on_game_state_snapshot_restored() -> void:
	_ensure_generated_route_arrival_authority()
	if _route_risk_field != null and is_instance_valid(_route_risk_field) \
			and _route_risk_field.has_method("on_game_state_snapshot_restored"):
		_route_risk_field.call("on_game_state_snapshot_restored")
	_restore_generated_runtime_authority()
	if _scarcity_clock != null and _scarcity_clock.has_method("restore_from_authority"):
		_scarcity_clock.call("restore_from_authority")
	_ensure_branch_span_producers_ready()


func _generated_runtime_authority_key() -> String:
	var spec_id := str(_spec.get("id", "stretch"))
	return "%s%s:%d" % [GENERATED_RUNTIME_AUTHORITY_PREFIX, spec_id, get_generation_seed()]


## Complete JSON-safe generated-level truth. Costs already live on characters/items in GameState;
## this record owns the matching progression/topology side so a rollback cannot refund one while
## retaining the other. Absolute ticks preserve every in-flight hazard commitment.
func _generated_runtime_authority_state() -> Dictionary:
	var state := {
		"version": GENERATED_RUNTIME_AUTHORITY_VERSION,
		"spec_id": str(_spec.get("id", "")),
		"seed": get_generation_seed(),
		"route_choice": _route_choice,
		"route_phase": _route_phase,
		"completed_nodes": _completed_nodes.duplicate(),
		"activated_routes": _activated_routes.duplicate(),
		"produced_chain_states": _produced_chain_states.duplicate(true),
		"delivered_resource_nodes": _delivered_resource_nodes.duplicate(),
		"resource_claims": _resource_claims.duplicate(true),
		"exit_shelter_transaction": _exit_shelter_transaction.duplicate(true),
		"resources_collected": _resources_collected,
		"shortcut_unlocked": _shortcut_unlocked,
		"shelter_reached": _shelter_reached,
		"shelter_rested": _shelter_rested,
		"last_outcome": _last_outcome,
		"risky_damage_total": _risky_damage_total,
		"route_risk_contacts": _route_risk_contacts.duplicate(true),
		"pressure_taken": _pressure_taken,
		"rests_taken": _rests_taken,
		"first_shelter_beat_fired": _first_shelter_beat_fired,
		"active_loadout": _active_loadout,
		"active_party": _active_party.duplicate(),
		"active_capabilities": _active_capabilities.duplicate(true),
		"enforce_stage": _enforce_stage,
		"node_approach_used": _node_approach_used.duplicate(true),
		"blocked_nodes": _blocked_nodes.duplicate(),
		"infrastructure": _infrastructure_operation_authority_state(),
		"theme_hazard_damage_total": _theme_hazard_damage_total,
		"theme_hazard_contacts": _theme_hazard_contacts.duplicate(true),
		"theme_hazard_armed": _theme_hazard_armed,
		"theme_hazard_next_tick": _theme_hazard_next_tick,
	}
	return state


func _publish_generated_runtime_authority() -> void:
	if _restoring_generated_authority:
		return
	var gs = _get_game_state()
	if gs == null or not gs.has_method("set_world_state") or _spec.is_empty():
		return
	gs.set_world_state(_generated_runtime_authority_key(), _generated_runtime_authority_state())


func _restore_generated_runtime_authority() -> bool:
	var gs = _get_game_state()
	var scheduler = _get_scheduler()
	if gs == null or not gs.has_method("get_world_state"):
		return false
	var saved: Variant = gs.get_world_state(_generated_runtime_authority_key(), {})
	if not (saved is Dictionary) \
			or int(saved.get("version", 0)) != GENERATED_RUNTIME_AUTHORITY_VERSION \
			or str(saved.get("spec_id", "")) != str(_spec.get("id", "")) \
			or int(saved.get("seed", get_generation_seed())) != get_generation_seed():
		# Absence is authoritative: it means the save predates all generated-stretch progress. Never
		# publish the current scene locals here; on same-instance rollback those are the discarded
		# future and could retain a completed bridge, collected reward, or unlocked shelter.
		if _generated_runtime_baseline.is_empty():
			push_warning("generated_stretch_chunk: no construction baseline available for legacy restore")
			return false
		var baseline := _generated_runtime_baseline.duplicate(true)
		if bool(baseline.get("theme_hazard_armed", false)):
			baseline["theme_hazard_next_tick"] = _sequence_tick() + THEME_HAZARD_TICK
		gs.set_world_state(_generated_runtime_authority_key(), baseline)
		return _restore_generated_runtime_authority()
	_restoring_generated_authority = true
	_cancel_theme_hazard_tick()
	_route_choice = str(saved.get("route_choice", ""))
	_route_phase = str(saved.get("route_phase", "unstarted"))
	_completed_nodes.assign(saved.get("completed_nodes", []))
	_activated_routes.assign(saved.get("activated_routes", []))
	_produced_chain_states = (saved.get("produced_chain_states", {}) as Dictionary).duplicate(true)
	# `prepared_nested_nodes` was a legacy two-click metadata gate. Deliberately do
	# not read it: an old save may contain the key, but it cannot resurrect a
	# non-physical preparation phase or make the next interaction mean something
	# different from the visible pickup in the current runtime.
	_delivered_resource_nodes.assign(saved.get("delivered_resource_nodes", []))
	_resource_claims = (saved.get("resource_claims", {}) as Dictionary).duplicate(true)
	_exit_shelter_transaction = (
		(saved.get("exit_shelter_transaction", _new_exit_shelter_transaction()) as Dictionary)
		.duplicate(true)
	)
	_resources_collected = int(saved.get("resources_collected", 0))
	_shortcut_unlocked = bool(saved.get("shortcut_unlocked", false))
	_shelter_reached = bool(saved.get("shelter_reached", false))
	_shelter_rested = bool(saved.get("shelter_rested", false))
	_last_outcome = str(saved.get("last_outcome", "ready"))
	_risky_damage_total = float(saved.get("risky_damage_total", 0.0))
	_route_risk_contacts = (saved.get("route_risk_contacts", {}) as Dictionary).duplicate(true)
	_pressure_taken = float(saved.get("pressure_taken", 0.0))
	_rests_taken = int(saved.get("rests_taken", 0))
	_first_shelter_beat_fired = bool(saved.get("first_shelter_beat_fired", false))
	_active_loadout = str(saved.get("active_loadout", _active_loadout))
	_active_party.assign(saved.get("active_party", _active_party))
	_sync_route_risk_character_ids()
	_active_capabilities = (saved.get("active_capabilities", {}) as Dictionary).duplicate(true)
	_enforce_stage = bool(saved.get("enforce_stage", _enforce_stage))
	_node_approach_used = (saved.get("node_approach_used", {}) as Dictionary).duplicate(true)
	_blocked_nodes.assign(saved.get("blocked_nodes", []))
	_theme_hazard_damage_total = float(saved.get("theme_hazard_damage_total", 0.0))
	_theme_hazard_contacts = (saved.get("theme_hazard_contacts", {}) as Dictionary).duplicate(true)
	_theme_hazard_armed = bool(saved.get("theme_hazard_armed", false))
	_theme_hazard_next_tick = float(saved.get("theme_hazard_next_tick", -1.0))
	_restore_infrastructure_operation_authority(saved.get("infrastructure", {}))
	_reconcile_resource_claims_after_restore()
	_reconcile_exit_shelter_transaction_after_restore()
	_restore_generated_section_presenters()
	_restore_resource_claim_source_presenters()
	if _shelter_reached:
		_disable_exit_shelter_interaction()
	else:
		_rearm_exit_shelter_interaction()
	if _theme_hazard_armed and scheduler != null:
		_arm_theme_hazard_tick(maxf(0.000001, _theme_hazard_next_tick - _sequence_tick()))
	_restoring_generated_authority = false
	# Claim/exit reconciliation may have completed a transaction that a signal-time
	# snapshot caught between its canonical sub-steps. Persist the normalized whole
	# after restoration; unchanged records remain a GameState no-op.
	_publish_generated_runtime_authority()
	return true


func _restore_generated_section_presenters() -> void:
	for node_v in _nodes():
		if not (node_v is Dictionary):
			continue
		var node := node_v as Dictionary
		var node_id := str(node.get("id", ""))
		# Every generated action is a one-shot presenter, including actions that
		# intentionally have no causal-link overlay. Same-instance rollback must
		# retract its local `_used` latch before any restored deferred receipt can
		# consume it again. Gating this behind `_generated_section_states` left a
		# one-shot control visually enabled but permanently spent after rollback.
		var interactable: Node = _node_interactables.get(node_id, null)
		if interactable != null and is_instance_valid(interactable) \
				and interactable.has_method("restore_one_shot_presenter"):
			var spent := _completed_nodes.has(node_id)
			interactable.call("restore_one_shot_presenter", spent, not spent)
		if not _generated_section_states.has(node_id):
			continue
		var state := _generated_section_states[node_id] as Dictionary
		state["state"] = "predicted"
		state.erase("observed_effect")
		var target = state.get("target", null)
		if target is Node3D and is_instance_valid(target):
			(target as Node3D).set_meta("generated_section_state", "predicted")
		_generated_section_states[node_id] = state
		var link = _generated_section_links.get(node_id, null)
		if link != null and is_instance_valid(link):
			link.call("set_feedback_mode", "predicted")
			link.call("set_latched", false)
		if interactable != null and is_instance_valid(interactable):
			interactable.set(
				"tutorial_label",
				RuntimeRegistryScript.initial_action_label(
					node, _runtime_handler_for_node(node)
				)
			)
			interactable.set(
				"consequence_preview",
				str(node.get("playable_section", {}).get("predicted_effect", ""))
			)
			var duration := _generated_interaction_duration(node)
			interactable.set("dwell_time", duration)
			interactable.set(
				"interactable_type",
				(
					Interactable.InteractableType.TIMED_ACTION
					if duration > 0.0
					else Interactable.InteractableType.INSPECTION
				)
			)
		if _completed_nodes.has(node_id):
			_apply_generated_section_transition(node, false)


func _restore_resource_claim_source_presenters() -> void:
	var gs = _get_game_state()
	var source_ids: Array = _resource_claims.keys()
	source_ids.sort()
	for source_id_v in source_ids:
		var source_id := str(source_id_v)
		var claim_v: Variant = _resource_claims.get(source_id, {})
		if not (claim_v is Dictionary):
			continue
		var claim := claim_v as Dictionary
		var source := _resource_claim_source_interactable(source_id)
		if source == null or not is_instance_valid(source):
			continue
		var phase := str(claim.get("phase", RESOURCE_PHASE_AVAILABLE))
		var available := (
			phase == RESOURCE_PHASE_AVAILABLE
			and _resource_claim_item_is_at_source(gs, claim)
		)
		if available and source.has_method("reset"):
			# An accepted-trigger snapshot can observe the Interactable's one-shot
			# bit before this owner publishes CLAIMING. Restoring that boundary
			# re-arms the untouched exact item instead of granting or wedging it.
			source.call("reset")
		elif source.has_method("restore_one_shot_presenter"):
			source.call(
				"restore_one_shot_presenter",
				phase != RESOURCE_PHASE_AVAILABLE,
				false
			)
		if source == _node_interactables.get(str(claim.get("node_id", "")), null) \
				and source is CollisionObject3D:
			# Generated node meshes own pointer selection; the invisible Area
			# remains a movement/dwell delegate even after reset.
			(source as CollisionObject3D).input_ray_pickable = false


func _ensure_branch_span_producers_ready() -> void:
	if not _branch_span_grid_ready or not _branch_span_producers.is_empty():
		return
	var gs = _get_game_state()
	var scheduler = _get_scheduler()
	if gs == null or scheduler == null or gs.grid == null:
		return
	_build_branch_span_producers(gs, scheduler)


func _build_branch_span_producers(gs, scheduler) -> void:
	var nav := _nav_grid()
	var cell_size := float(nav.get("cell_size", 1.0))
	for branch_v in nav.get("branches", []):
		if not (branch_v is Dictionary):
			continue
		var branch := branch_v as Dictionary
		if str(branch.get("role", "")) != "mandatory_producer":
			continue
		var branch_id := str(branch.get("id", ""))
		var contract: Dictionary = branch.get("causal_contract", {})
		var producer_cell := _cell_from_address(contract.get("producer_cell", []))
		var consumer_cell := _cell_from_address(contract.get("consumer_cell", []))
		var consumer_cells := _branch_consumer_cells(contract)
		if branch_id.is_empty() \
				or producer_cell == Vector2i(-2147483648, -2147483648) \
				or consumer_cell == Vector2i(-2147483648, -2147483648) \
				or consumer_cells.is_empty():
			push_warning("Mandatory generated branch rejected incomplete exact-cell contract")
			continue

		var producer_level := int(branch.get(
			"navigation_level", contract.get("producer_navigation_level", 0)
		))
		var consumer_level := int(contract.get(
			"consumer_navigation_level", producer_level
		))
		var producer_data: Vector3 = gs.grid.grid_to_world(
			producer_cell, producer_level
		)
		var consumer_data: Vector3 = gs.grid.grid_to_world(
			consumer_cell, consumer_level
		)
		var producer_render := _warp_pos(producer_data + Vector3(0.0, 0.04, 0.0))
		var min_consumer_row := consumer_cell.y
		var max_consumer_row := consumer_cell.y
		for blocked_cell in consumer_cells:
			min_consumer_row = mini(min_consumer_row, blocked_cell.y)
			max_consumer_row = maxi(max_consumer_row, blocked_cell.y)
		var span_width := maxf(
			2.4, float(max_consumer_row - min_consumer_row + 1) * cell_size
		)
		var span_start := _warp_pos(
			consumer_data + Vector3(-cell_size * 0.72, 0.08, 0.0)
		)
		var span_end := _warp_pos(
			consumer_data + Vector3(cell_size * 0.72, 0.08, 0.0)
		)
		var mechanism_id := str(contract.get(
			"mechanism_id", "%s_branch_span_%s" % [str(_spec.get("id", "stretch")), branch_id]
		))
		var blocker_tag := str(contract.get(
			"blocker_tag", "generated_branch_span_gap:%s" % mechanism_id
		))
		var span = BranchSpanProducerScript.new()
		span.name = "BranchSpanProducer_%s" % branch_id
		var configured := bool(span.configure(
			gs,
			scheduler,
			producer_data,
			producer_render,
			span_start,
			span_end,
			consumer_cells,
			{
				"mechanism_id": mechanism_id,
				"blocker_tag": blocker_tag,
				"duration": float(contract.get("duration", 2.4)),
				"interaction_radius": float(contract.get("interaction_radius", 1.8)),
				"span_width": span_width,
				"required_character": str(contract.get("required_character", "")),
			}
		))
		if not configured:
			span.free()
			push_warning(
				"Mandatory branch span '%s' could not bind its exact producer/consumer contract"
				% branch_id
			)
			continue
		add_child(span)
		for interactable in span.get_interactables():
			if "active_character" in interactable:
				interactable.active_character = _get_active_character()
			_register_interactable(interactable)
		_branch_span_producers.append(span)
		_branch_span_by_id[branch_id] = span


func get_branch_span_count() -> int:
	_ensure_branch_span_producers_ready()
	return _branch_span_producers.size()


func _branch_span_states() -> Array:
	_ensure_branch_span_producers_ready()
	var states: Array = []
	for branch_id_v in _branch_span_by_id.keys():
		var branch_id := str(branch_id_v)
		var span = _branch_span_by_id[branch_id]
		if span != null and is_instance_valid(span) and span.has_method("get_state"):
			var state: Dictionary = span.call("get_state")
			state["branch_id"] = branch_id
			states.append(state)
	states.sort_custom(func(a: Dictionary, b: Dictionary):
		return str(a.get("branch_id", "")) < str(b.get("branch_id", ""))
	)
	return states


func _mandatory_branch_ids() -> Array[String]:
	var ids: Array[String] = []
	for branch_v in _nav_grid().get("branches", []):
		if branch_v is Dictionary \
				and str((branch_v as Dictionary).get("role", "")) == "mandatory_producer":
			ids.append(str((branch_v as Dictionary).get("id", "")))
	return ids


func _all_mandatory_branch_spans_bridged() -> bool:
	_ensure_branch_span_producers_ready()
	for branch_id in _mandatory_branch_ids():
		var span = _branch_span_by_id.get(branch_id, null)
		if span == null or not is_instance_valid(span) or not bool(span.call("is_bridged")):
			return false
	return true


## Place a LYSATE CACHE at the far end of every branch spoke: an optional, one-shot carried reward the player has
## to detour off the spine to reach. The branch risk buys a larger reserve, but the lysate still occupies a hand
## and changes ATP only after explicit endocytosis. Warped onto the helix like the node dressing.
const BRANCH_ATP := 2


func _build_branch_content() -> void:
	if _coord_map == null:
		return
	var nav := _nav_grid()
	var branches: Array = nav.get("branches", [])
	if branches.is_empty():
		return
	var grid = GridWorld.from_data(nav)
	for i in range(branches.size()):
		var b: Dictionary = branches[i]
		# Only the explicit risk/reward role earns a resource cache. Mandatory
		# producers and recovery returns must be realized by their own causal kit;
		# dressing either one as another lysate closet would lie about its verb.
		if str(b.get("role", "")) != "optional_risk_reward":
			continue
		var far := _branch_far_cell(b.get("cells", []), b.get("neck", [0, 0]))
		if far == Vector2i(2147483647, 0):
			continue
		var food_profile := _branch_food_profile(b, far)
		var reward_atp := int(food_profile.get("food_atp", BRANCH_ATP))
		var flat: Vector3 = grid.grid_to_world(
			far, int(b.get("navigation_level", 0))
		)
		var service_bay := _build_branch_service_bay(i, flat, reward_atp)
		var service_light: OmniLight3D = service_bay.get("light", null)
		var service_meshes: Array[MeshInstance3D] = []
		service_meshes.assign(service_bay.get("meshes", []))
		var interactable := _add_inspection_interactable(
			self,
			"BranchCacheZone_%d" % i,
			"Salvage cache",
			flat + Vector3(0.0, 0.12, 0.0),
			"SALVAGE",
			"",
			1.6,
			true
		)
		_add_outline_target(
			self,
			"BranchCacheTarget_%d" % i,
			flat + Vector3(0.0, 0.5, 0.0),
			Vector3(1.2, 1.0, 1.2),
			service_meshes,
			"branch_cache_%d" % i,
			interactable
		)

		var cache := {
			"index": i,
			"branch_id": str(b.get("id", "branch_%02d" % i)),
			"role": str(b.get("role", "optional_risk_reward")),
			"navigation_level": int(b.get("navigation_level", 0)),
			"cell": [far.x, far.y],
			"shape": str(b.get("shape", "")),
			"risk_score": float(food_profile.get("risk_score", 0.0)),
			"detour_cells": float(food_profile.get("detour_cells", 0.0)),
			"hazard_penalty": float(food_profile.get("hazard_penalty", 0.0)),
			"food_atp": reward_atp,
			"collected": false,
			"interactable": interactable,
			"light": service_light,
		}
		interactable.set_pre_trigger_validator(
			_validate_branch_cache_trigger.bind(i, interactable)
		)
		interactable.interacted.connect(
			Callable(self, "_on_branch_cache_interacted").bind(i, interactable)
		)
		_branch_caches.append(cache)


func _configure_food_branch_caches() -> void:
	if _branch_caches.is_empty():
		return
	var grid = GridWorld.from_data(_nav_grid())
	for cache in _branch_caches:
		var raw_cell: Array = cache.get("cell", [])
		if raw_cell.size() >= 2:
			cache["position"] = grid.grid_to_world(
				Vector2i(int(raw_cell[0]), int(raw_cell[1])),
				int(cache.get("navigation_level", 0))
			)
		cache["physical_food"] = true
		var interactable = cache.get("interactable", null)
		if interactable != null:
			var reward_atp := int(cache.get("food_atp", BRANCH_ATP))
			# The exact world cache is the finite source. A failed preflight never
			# consumes it; a successful receipt spends it once and the saved claim
			# owns all later presentation.
			interactable.set("one_shot", true)
			interactable.set("tutorial_label", "TAKE LYSATE")
			interactable.set(
				"description",
				(
					"Carryable Lysate (+%d ATP when consumed; occupies one hand). "
					+ "Exposure score %.1f is route cost, not direct HP damage. R runs at stamina cost."
				) % [reward_atp, float(cache.get("risk_score", 0.0))]
			)
		_set_branch_cache_available_visual(cache, not bool(cache.get("collected", false)))


func _branch_food_profile(branch: Dictionary, far: Vector2i) -> Dictionary:
	var neck_raw: Array = branch.get("neck", [far.x, far.y])
	var neck := Vector2i(int(neck_raw[0]), int(neck_raw[1])) if neck_raw.size() >= 2 else far
	var detour_cells := Vector2(far.x - neck.x, far.y - neck.y).length()
	var branch_cells: Array = branch.get("cells", [])
	var branch_cell_set := {}
	for raw_cell in branch_cells:
		if raw_cell is Array and raw_cell.size() >= 2:
			branch_cell_set[Vector2i(int(raw_cell[0]), int(raw_cell[1]))] = true
	var hazard_penalty := 0.0
	for risk_entry in _nav_grid().get("risk_cell_list", []):
		var risk_cell_raw: Array = risk_entry.get("cell", [])
		if risk_cell_raw.size() < 2:
			continue
		var risk_cell := Vector2i(int(risk_cell_raw[0]), int(risk_cell_raw[1]))
		if branch_cell_set.has(risk_cell):
			hazard_penalty += float(risk_entry.get("penalty", 0.0))
	var risk_score := detour_cells * 1.5 + float(branch_cells.size()) * 0.15 + hazard_penalty * 0.2
	var reward_atp := BRANCH_ATP
	if risk_score >= 9.0:
		reward_atp = 4
	elif risk_score >= 6.0:
		reward_atp = 3
	return {
		"risk_score": snappedf(risk_score, 0.1),
		"detour_cells": snappedf(detour_cells, 0.1),
		"hazard_penalty": snappedf(hazard_penalty, 0.1),
		"food_atp": reward_atp,
	}
## Each optional spoke terminates in a small, readable service bay instead of a lone reward cube on empty floor.
## The low plinth and paired gauge posts add silhouette without obscuring the route; the label makes the detour's
## purpose legible before the player commits to it. The whole assembly is one flat-authored root, so the existing
## warp pass seats it consistently on the helix.
func _build_branch_service_bay(index: int, flat: Vector3, reward_atp: int) -> Dictionary:
	var bay := Node3D.new()
	bay.name = "BranchServiceBay_%d" % index
	bay.position = flat
	add_child(bay)
	var steel := Color(0.12, 0.18, 0.19)
	var signal_color := Color(0.50, 0.78, 0.34).lightened(0.06 * float(reward_atp - BRANCH_ATP))
	var meshes: Array[MeshInstance3D] = []
	meshes.append(_add_box(
		bay,
		Vector3(0.0, 0.08, 0.0),
		Vector3(2.35, 0.14, 1.85),
		steel,
		signal_color,
		0.14,
		"ServicePlinth"
	))
	for side in [-0.88, 0.88]:
		meshes.append(_add_box(
			bay,
			Vector3(side, 0.62, 0.62),
			Vector3(0.14, 1.15, 0.14),
			steel,
			signal_color,
			0.42,
			"GaugePost"
		))
	meshes.append(_add_box(
		bay,
		Vector3(0.0, 1.18, 0.62),
		Vector3(1.9, 0.12, 0.12),
		steel,
		signal_color,
		0.48,
		"GaugeBeam"
	))
	_add_label(
		bay,
		"LYSATE CACHE %02d  //  STORES +%d ATP" % [index + 1, reward_atp],
		Vector3(0.0, 1.65, 0.62),
		signal_color.lightened(0.22)
	)
	var hierarchy := _visual_hierarchy()
	var focus_light := _add_light(
		bay,
		Vector3(0.0, 1.28, 0.12),
		signal_color.lightened(0.12),
		float(hierarchy.get("interactive_light_energy", 1.05)) * 0.78,
		float(hierarchy.get("interactive_light_range", 4.4))
	)
	focus_light.set_meta("visual_role", "resource_focus")
	_spatial_fixture_count += 1
	return {"light": focus_light, "meshes": meshes}


func _set_branch_cache_available_visual(cache: Dictionary, available: bool) -> void:
	var focus_light: OmniLight3D = cache.get("light", null)
	if focus_light != null and is_instance_valid(focus_light):
		focus_light.visible = available


func _set_interactable_copy(interactable: Node, label: String, description: String) -> void:
	if interactable == null or not is_instance_valid(interactable):
		return
	interactable.set("tutorial_label", label)
	interactable.set("description", description)
	var expanded_label := InputLabels.expand(label)

	for child in interactable.get_children():
		if child is Label3D:
			(child as Label3D).text = expanded_label
			break


func _set_outline_target_enabled(target: Node, enabled: bool) -> void:
	if target == null or not is_instance_valid(target):
		return
	target.set("hover_enabled", enabled)
	target.set("collision_layer", 4 if enabled else 0)
	target.set("input_ray_pickable", enabled)
	if not enabled:
		if target.has_method("set_hover_feedback"):
			target.call("set_hover_feedback", false)
		if target.has_method("set_highlight"):
			target.call("set_highlight", false)


func _sequence_tick() -> float:
	var scheduler = _get_scheduler()
	if scheduler != null and scheduler.has_method("get_current_tick"):
		return float(scheduler.get_current_tick())
	return _get_scheduler_tick()


## Every openable mechanism this stretch realizes, as the solvability validator's inventory: the
## blocker tag each holds on the grid, and the control positions a player must reach to open it. A
## mechanism absent from this inventory reads as permanent scenery to the greedy validator, so any
## new gated seam must list itself here to be provable open.
func get_gate_inventory() -> Array:
	var gates: Array = []
	for span_v in _branch_span_producers:
		if span_v == null or not is_instance_valid(span_v):
			continue
		gates.append({
			"tag": str(span_v.get("_blocker_tag")),
			"producer_positions": [span_v.get("_producer_data_position")],
		})
	return gates


func get_playthrough_interaction_target(action_id: String) -> Node3D:
	# Deterministic playthrough tapes resolve stable semantic targets, then enter the
	# ordinary click -> walk -> dwell -> interact path. No puzzle state changes here.
	for action_v in _solution_branch_actions():
		if not (action_v is Dictionary) or str((action_v as Dictionary).get("id", "")) != action_id:
			continue
		_ensure_branch_span_producers_ready()
		var branch_id := str((action_v as Dictionary).get(
			"branch_id", (action_v as Dictionary).get("target", "")
		))
		var span = _branch_span_by_id.get(branch_id, null)
		if span != null and is_instance_valid(span):
			return span.call("get_producer_interactable") as Node3D
		return null
	if action_id == "enter_shelter":
		return _node_targets.get("exit_shelter", null)
	return null


## The cell in a branch furthest from its neck (the back of the room) — where the reward sits, so the player has
## to walk the whole spoke to claim it.
# The cache trio (marker, interactable, outline target) is authored flat here; the _build_chunk warp pass
# re-seats all of them onto the helix together (same path as the node dressing).
func _branch_far_cell(cells: Array, neck: Array) -> Vector2i:
	var nx := int((neck as Array)[0]) if neck.size() >= 2 else 0
	var nz := int((neck as Array)[1]) if neck.size() >= 2 else 0
	var best := Vector2i(2147483647, 0)
	var best_d := -1.0
	for c in cells:
		var v := Vector2i(int((c as Array)[0]), int((c as Array)[1]))
		var d := Vector2(v.x - nx, v.y - nz).length()
		if d > best_d:
			best_d = d
			best = v
	return best


func _branch_cache_for_index(index: int) -> Dictionary:
	for cache in _branch_caches:
		if int(cache.get("index", -1)) == index:
			return cache
	return {}


func _validate_branch_cache_trigger(
	source: Node, actor: String, index: int, expected_source: Node
) -> bool:
	var cache := _branch_cache_for_index(index)
	if cache.is_empty() or source == null or source != expected_source \
			or source != cache.get("interactable", null) \
			or bool(cache.get("collected", false)) \
			or not _generated_actor_ready_at(source, actor):
		return false
	var source_id := _physical_cache_source_id(cache)
	var claim_v: Variant = _resource_claims.get(source_id, {})
	var gs = _get_game_state()
	return (
		_resource_claim_phase(source_id) == RESOURCE_PHASE_AVAILABLE
		and claim_v is Dictionary
		and _resource_claim_item_is_at_source(gs, claim_v as Dictionary)
		and gs != null
		and gs.has_method("has_free_hand")
		and bool(gs.call("has_free_hand", actor))
	)


func _branch_cache_receipt_pending(source: Node, index: int) -> bool:
	var cache := _branch_cache_for_index(index)
	return (
		not cache.is_empty()
		and source != null
		and source == cache.get("interactable", null)
		and _generated_interactable_receipt_pending(source, true)
	)


func _on_branch_cache_interacted(index: int, expected_source: Node) -> void:
	if not _branch_cache_receipt_pending(expected_source, index):
		return
	var cache := _branch_cache_for_index(index)
	if cache.is_empty() \
			or not _collect_physical_branch_food_from_receipt(
				cache, index, expected_source
			):
		_rearm_resource_source(expected_source)


## Always-refusing stub. A branch reward exists only after the exact bound
## cache accepts a nearby body's interaction and its one-shot receipt is consumed.
func _collect_branch_reward(_index: int) -> bool:
	return false


func _collect_physical_branch_food_from_receipt(
	cache: Dictionary, index: int, source: Node
) -> bool:
	if not _branch_cache_receipt_pending(source, index):
		return false
	var reward_atp := float(cache.get("food_atp", BRANCH_ATP))
	var pickup := _transfer_physical_lysate_from_receipt(
		cache,
		{
			"display_name": "Branch Lysate",
			"display_names_by_character":
			{
				"aster": "Lysate",
				"peris": "Lysate",
				"endo": "Starch",
			},
			"visual_color": Color(0.66, 0.82, 0.4),
			"atp_restore": reward_atp,
			"branch_cache_index": index,
		},
		source
	)
	if pickup.is_empty():
		return false
	var recipient := str(pickup.get("recipient", ""))
	_last_outcome = "physical_food:%s:%d" % [recipient, index]
	_show_message(
		(
			"%s now carries lysate (+%s ATP when consumed). Their portrait shows the carrier."
			% [recipient.capitalize(), _atp_amount_text(reward_atp)]
		),
		2.8
	)
	return true


func _atp_amount_text(value: float) -> String:
	return "%d" % int(value) if is_equal_approx(value, roundf(value)) else "%.1f" % value


func _node_resource_source_id(node_id: String) -> String:
	return "node:%s" % node_id


func _physical_cache_source_id(cache: Dictionary) -> String:
	var explicit_id := str(cache.get("resource_source_id", ""))
	if explicit_id != "":
		return explicit_id
	var branch_id := str(cache.get("branch_id", ""))
	if branch_id != "":
		return "branch_cache:%s" % branch_id
	return "branch_cache:index_%d" % int(cache.get("index", -1))


func _generated_resource_source_position(node: Dictionary) -> Vector3:
	var node_id := str(node.get("id", ""))
	var position := _node_position(node_id)
	if position == Vector3.INF:
		return position
	var role := str(node.get("role", "route"))
	var pad_size := _vec3(
		node.get("footprint", node.get("floor_size", [])), _node_pad_size(role)
	)
	return _vec3(
		node.get("approach_position", []),
		position + Vector3(0.0, 0.0, pad_size.z * 0.34)
	)


func _generated_resource_contract(node: Dictionary) -> Dictionary:
	var node_id := str(node.get("id", ""))
	var source_id := _node_resource_source_id(node_id)
	var is_food := (
		str(node.get("reward_kind", "")) == "food"
		or str(node.get("survival_kind", "")) == "forage"
	)
	var display_name := str(node.get("title", "Lysate" if is_food else "Generated Tool"))
	var item_type := "lysate" if is_food else str(
		node.get("resource_item_type", "generated_tool")
	)
	var reward_atp := maxi(1, int(node.get("reward_atp", node.get("atp_reward", 2))))
	return {
		"source_id": source_id,
		"node_id": node_id,
		"progression_node_id": node_id,
		"resource_kind": RESOURCE_KIND_GENERATED,
		"item_type": item_type,
		"source_position": _generated_resource_source_position(node),
		"counts_physical_food": is_food,
		"properties":
		{
			"display_name": display_name,
			"visual_kind": "food" if is_food else "tool",
			"visual_color": _role_color(str(node.get("role", "foraging"))).lightened(0.25),
			"generated_node_id": node_id,
			"systems_verb": str(node.get("systems_beat", {}).get("verb", "intervene")),
			"chain_state_ref": str(node.get("runtime_chain_output_ref", "")),
			"carry_payload": bool(node.get("carry_payload", false)),
			"hand_slots": 1,
			"atp_restore": float(reward_atp) if is_food else 0.0,
			"endocytosis_allowed": is_food,
			"consumable": is_food,
		},
	}


func _physical_cache_resource_contract(
	cache: Dictionary, properties: Dictionary = {}
) -> Dictionary:
	var source_id := _physical_cache_source_id(cache)
	var node_id := str(properties.get("generated_node_id", ""))
	var source_position := _vec3(cache.get("position", []), Vector3.INF)
	var resolved_properties := properties.duplicate(true)
	if resolved_properties.is_empty():
		var reward_atp := float(cache.get("food_atp", BRANCH_ATP))
		resolved_properties = {
			"display_name": "Branch Lysate",
			"display_names_by_character":
			{
				"aster": "Lysate",
				"peris": "Lysate",
				"endo": "Starch",
			},
			"visual_color": Color(0.66, 0.82, 0.4),
			"atp_restore": reward_atp,
			"branch_cache_index": int(cache.get("index", -1)),
		}
	return {
		"source_id": source_id,
		"node_id": node_id,
		"progression_node_id": node_id,
		"resource_kind": RESOURCE_KIND_PHYSICAL_FOOD,
		"item_type": "lysate",
		"source_position": source_position,
		"counts_physical_food": true,
		"properties": resolved_properties,
	}


func _new_resource_claim(
	contract: Dictionary
) -> Dictionary:
	var source_id := str(contract.get("source_id", ""))
	var node_id := str(contract.get("node_id", ""))
	var source_position := _vec3(contract.get("source_position", []), Vector3.INF)
	var properties := (contract.get("properties", {}) as Dictionary).duplicate(true)
	properties["generated_resource_source_id"] = source_id
	properties["generated_node_id"] = node_id
	if source_position != Vector3.INF:
		properties["generated_resource_source_position"] = _vec3_array(source_position)
	return {
		"version": RESOURCE_CLAIM_VERSION,
		"phase": RESOURCE_PHASE_AVAILABLE,
		"source_id": source_id,
		"node_id": node_id,
		"progression_node_id": str(contract.get("progression_node_id", node_id)),
		"resource_kind": str(contract.get("resource_kind", "")),
		"recipient": "",
		"item_id": "",
		"item_type": str(contract.get("item_type", "")),
		"source_position": (
			_vec3_array(source_position) if source_position != Vector3.INF else []
		),
		"properties": properties,
		"counts_physical_food": bool(contract.get("counts_physical_food", false)),
		"claim_tick": -1.0,
		"claimed_tick": -1.0,
	}


func _initialize_resource_claim_authority() -> void:
	_resource_claims.clear()
	for node_v in _nodes():
		if not (node_v is Dictionary):
			continue
		var node := node_v as Dictionary
		var handler := _runtime_handler_for_node(node)
		if handler not in [
			RuntimeRegistryScript.HANDLER_PHYSICAL_LYSATE,
			RuntimeRegistryScript.HANDLER_PHYSICAL_PAYLOAD,
		]:
			continue
		var node_id := str(node.get("id", ""))
		if node_id == "":
			continue
		var contract := _generated_resource_contract(node)
		_resource_claims[str(contract.get("source_id", ""))] = _new_resource_claim(contract)
	for cache_v in _branch_caches:
		if not (cache_v is Dictionary) or not bool((cache_v as Dictionary).get("physical_food", false)):
			continue
		var cache := cache_v as Dictionary
		var source_id := _physical_cache_source_id(cache)
		cache["resource_source_id"] = source_id
		_resource_claims[source_id] = _new_resource_claim(
			_physical_cache_resource_contract(cache)
		)


func _ensure_resource_source_item(source_id: String) -> String:
	var claim_v: Variant = _resource_claims.get(source_id, {})
	if not (claim_v is Dictionary):
		return ""
	var claim := claim_v as Dictionary
	var gs = _get_game_state()
	if gs == null:
		return ""
	if _resource_claim_item_is_valid(gs, claim):
		return str(claim.get("item_id", ""))
	# A nonempty missing id means a previously materialized identity was destroyed.
	# Never mint a replacement for that ambiguous history.
	if str(claim.get("item_id", "")) != "":
		return ""
	var source_position := _vec3(claim.get("source_position", []), Vector3.INF)
	var item_type := str(claim.get("item_type", ""))
	if source_position == Vector3.INF or item_type == "":
		return ""
	var properties := (claim.get("properties", {}) as Dictionary).duplicate(true)
	properties["generated_resource_source_id"] = source_id
	properties["generated_node_id"] = str(claim.get("node_id", ""))
	properties["generated_resource_source_position"] = _vec3_array(source_position)
	var item_id := _spawn_item(item_type, source_position, properties)
	if item_id == "":
		return ""
	claim["item_id"] = item_id
	claim["properties"] = properties
	_resource_claims[source_id] = claim
	return item_id


func _materialize_resource_sources() -> void:
	var source_ids: Array = _resource_claims.keys()
	source_ids.sort()
	for source_id_v in source_ids:
		_ensure_resource_source_item(str(source_id_v))
	_rebuild_resource_claim_indexes()
	_apply_resource_claim_presenters()


func _resource_claim_phase(source_id: String) -> String:
	var claim_v: Variant = _resource_claims.get(source_id, {})
	if not (claim_v is Dictionary):
		return RESOURCE_PHASE_AVAILABLE
	return str((claim_v as Dictionary).get("phase", RESOURCE_PHASE_AVAILABLE))


func _resource_claim_item_is_valid(gs, claim: Dictionary) -> bool:
	var item_id := str(claim.get("item_id", ""))
	if item_id == "" or gs == null or not ("items" in gs) \
			or not (gs.items as Dictionary).has(item_id):
		return false
	var item := (gs.items as Dictionary).get(item_id, {}) as Dictionary
	var properties := item.get("properties", {}) as Dictionary
	return (
		str(properties.get("generated_resource_source_id", ""))
		== str(claim.get("source_id", ""))
		and str(properties.get("generated_node_id", ""))
		== str(claim.get("node_id", ""))
	)


func _resource_claim_item_is_held(gs, claim: Dictionary) -> bool:
	if not _resource_claim_item_is_valid(gs, claim):
		return false
	var item_id := str(claim.get("item_id", ""))
	var item := (gs.items as Dictionary).get(item_id, {}) as Dictionary
	var holder := str(item.get("holder", ""))
	return (
		str(item.get("location", "")) == "hand"
		and holder != ""
		and gs.has_method("get_hand_items")
		and (gs.call("get_hand_items", holder) as Array).has(item_id)
	)


func _resource_claim_item_is_at_source(gs, claim: Dictionary) -> bool:
	if not _resource_claim_item_is_valid(gs, claim):
		return false
	var item_id := str(claim.get("item_id", ""))
	var item := (gs.items as Dictionary).get(item_id, {}) as Dictionary
	var source_position := _vec3(claim.get("source_position", []), Vector3.INF)
	var item_position := item.get("position", Vector3.INF) as Vector3
	return (
		source_position != Vector3.INF
		and str(item.get("location", "")) == "ground"
		and str(item.get("holder", "")) == ""
		and item_position.distance_to(source_position) <= 0.01
	)


func _resource_claim_item_holder(gs, claim: Dictionary) -> String:
	if not _resource_claim_item_is_held(gs, claim):
		return ""
	var item_id := str(claim.get("item_id", ""))
	return str(((gs.items as Dictionary).get(item_id, {}) as Dictionary).get("holder", ""))


func _commit_resource_claim_progression(claim: Dictionary) -> void:
	var node_id := str(claim.get("progression_node_id", ""))
	if node_id == "":
		return
	if not _completed_nodes.has(node_id):
		_completed_nodes.append(node_id)
	var node := _find_node(node_id)
	if node.is_empty():
		return
	var chain_output_ref := str(node.get("runtime_chain_output_ref", ""))
	if chain_output_ref != "":
		_produced_chain_states[chain_output_ref] = node_id
	_apply_generated_section_transition(node, false, str(claim.get("recipient", "")))


func _rebuild_resource_claim_indexes() -> void:
	_generated_resource_item_ids.clear()
	_physical_food_item_ids.clear()
	_generated_resource_item_by_node.clear()
	_resources_collected = 0
	_physical_food_spawned_count = 0
	_nominal_food_atp = 0.0
	var gs = _get_game_state()
	var source_ids: Array = _resource_claims.keys()
	source_ids.sort()
	for source_id_v in source_ids:
		var claim_v: Variant = _resource_claims.get(source_id_v, {})
		if not (claim_v is Dictionary):
			continue
		var claim := claim_v as Dictionary
		var node_id := str(claim.get("node_id", ""))
		var item_id := str(claim.get("item_id", ""))
		var kind := str(claim.get("resource_kind", ""))
		var claimed := str(claim.get("phase", "")) == RESOURCE_PHASE_CLAIMED
		if claimed and node_id != "":
			_generated_resource_item_by_node[node_id] = item_id
		if claimed and kind == RESOURCE_KIND_GENERATED:
			_resources_collected += 1
		if claimed and bool(claim.get(
			"counts_physical_food", kind == RESOURCE_KIND_PHYSICAL_FOOD
		)):
			_physical_food_spawned_count += 1
			_nominal_food_atp += float(
				(claim.get("properties", {}) as Dictionary).get("atp_restore", BRANCH_ATP)
			)
		if item_id == "" or gs == null or not ("items" in gs) \
				or not (gs.items as Dictionary).has(item_id):
			continue
		if kind == RESOURCE_KIND_GENERATED:
			_generated_resource_item_ids.append(item_id)
		else:
			_physical_food_item_ids.append(item_id)


func _apply_resource_claim_presenters() -> void:
	for cache_v in _branch_caches:
		if not (cache_v is Dictionary):
			continue
		var cache := cache_v as Dictionary
		var source_id := _physical_cache_source_id(cache)
		var claimed := _resource_claim_phase(source_id) == RESOURCE_PHASE_CLAIMED
		var available := (
			not claimed
			and _resource_claim_item_is_at_source(
				_get_game_state(), _resource_claims.get(source_id, {}) as Dictionary
			)
		)
		cache["collected"] = claimed
		_set_branch_cache_available_visual(cache, available)
		var interactable = cache.get("interactable", null)
		if interactable != null and interactable.has_method("set_interaction_enabled"):
			interactable.call("set_interaction_enabled", available)


func _resource_claim_mutation_authorized(source_id: String, source: Node) -> bool:
	if _restoring_generated_authority:
		return source == null
	var claim_v: Variant = _resource_claims.get(source_id, {})
	if not (claim_v is Dictionary) or source == null \
			or source != _resource_claim_source_interactable(source_id) \
			or not _generated_interactable_receipt_pending(source, true):
		return false
	var recipient := str((claim_v as Dictionary).get("recipient", ""))
	return recipient == "" or str(source.get("active_character")) == recipient


func _finish_resource_claim(source_id: String, source: Node = null) -> Dictionary:
	if not _resource_claim_mutation_authorized(source_id, source):
		return {}
	var claim_v: Variant = _resource_claims.get(source_id, {})
	if not (claim_v is Dictionary):
		return {}
	var claim := claim_v as Dictionary
	claim["phase"] = RESOURCE_PHASE_CLAIMED
	claim["claimed_tick"] = _sequence_tick()
	_resource_claims[source_id] = claim
	_commit_resource_claim_progression(claim)
	_rebuild_resource_claim_indexes()
	_apply_resource_claim_presenters()
	_publish_generated_runtime_authority()
	return {
		"recipient": str(claim.get("recipient", "")),
		"item_id": str(claim.get("item_id", "")),
		"source_id": source_id,
	}


func _return_resource_claim_to_available(source_id: String, source: Node = null) -> void:
	if not _resource_claim_mutation_authorized(source_id, source):
		return
	var claim_v: Variant = _resource_claims.get(source_id, {})
	if not (claim_v is Dictionary):
		return
	var claim := claim_v as Dictionary
	claim["phase"] = RESOURCE_PHASE_AVAILABLE
	claim["recipient"] = ""
	claim["claim_tick"] = -1.0
	claim["claimed_tick"] = -1.0
	_resource_claims[source_id] = claim
	_rebuild_resource_claim_indexes()
	_apply_resource_claim_presenters()
	_publish_generated_runtime_authority()


func _resume_resource_claim(
	source_id: String, allow_pickup := false, source: Node = null
) -> Dictionary:
	if not _resource_claim_mutation_authorized(source_id, source):
		return {}
	var claim_v: Variant = _resource_claims.get(source_id, {})
	if not (claim_v is Dictionary):
		return {}
	var claim := claim_v as Dictionary
	if str(claim.get("phase", "")) == RESOURCE_PHASE_CLAIMED:
		return {
			"recipient": str(claim.get("recipient", "")),
			"item_id": str(claim.get("item_id", "")),
			"source_id": source_id,
		}
	if str(claim.get("phase", "")) != RESOURCE_PHASE_CLAIMING:
		return {}
	var recipient := str(claim.get("recipient", ""))
	var gs = _get_game_state()
	if gs == null or not ("characters" in gs) \
			or not (gs.characters as Dictionary).has(recipient):
		return {}

	if not _resource_claim_item_is_valid(gs, claim):
		# A committed source id may not create a successor item. If the exact item
		# disappeared, fail closed as consumed so loading cannot duplicate it.
		return _finish_resource_claim(source_id, source)
	if _resource_claim_item_is_held(gs, claim):
		var actual_holder := _resource_claim_item_holder(gs, claim)
		if actual_holder != recipient:
			# A save hook or corrupt snapshot cannot turn another party member into
			# the servicing actor. Keep the reserved transaction unresolved and never
			# launder the physical item into progression for the wrong character.
			return {}
		return _finish_resource_claim(source_id, source)
	if _resource_claim_item_is_at_source(gs, claim):
		if not allow_pickup:
			# The commitment publication preceded pickup. Loading that boundary
			# restores the untouched source and asks for a fresh interaction.
			_return_resource_claim_to_available(source_id, source)
			return {}
		var item_id := str(claim.get("item_id", ""))
		if not _pick_up_item(recipient, item_id):
			_return_resource_claim_to_available(source_id, source)
			return {}
		return _finish_resource_claim(source_id, source)
	# The exact item exists but is no longer at its source (for example it was
	# dropped after pickup). Physical location wins: the source is consumed.
	return _finish_resource_claim(source_id, source)


func _begin_resource_claim(
	source_id: String,
	node_id: String,
	progression_node_id: String,
	resource_kind: String,
	recipient: String,
	item_type: String,
	properties: Dictionary,
	counts_physical_food: bool,
	source: Node = null
) -> Dictionary:
	var phase := _resource_claim_phase(source_id)
	if phase == RESOURCE_PHASE_CLAIMED:
		return {}
	var claim_v: Variant = _resource_claims.get(source_id, {})
	if not (claim_v is Dictionary):
		return {}
	var claim := claim_v as Dictionary
	var gs = _get_game_state()
	if source == null or source != _resource_claim_source_interactable(source_id) \
			or str(source.get("active_character")) != recipient \
			or not _generated_interactable_receipt_pending(source, true) \
			or not _generated_actor_ready_at(source, recipient) \
			or gs == null \
			or not ("characters" in gs) \
			or not (gs.characters as Dictionary).has(recipient):
		return {}
	if phase == RESOURCE_PHASE_CLAIMING:
		return _resume_resource_claim(source_id, true, source)
	if not _resource_claim_item_is_at_source(gs, claim):
		return {}
	claim["phase"] = RESOURCE_PHASE_CLAIMING
	claim["recipient"] = recipient
	if str(claim.get("progression_node_id", "")) == "":
		claim["progression_node_id"] = progression_node_id
	if str(claim.get("node_id", "")) == "":
		claim["node_id"] = node_id
	if str(claim.get("resource_kind", "")) == "":
		claim["resource_kind"] = resource_kind
	if str(claim.get("item_type", "")) == "":
		claim["item_type"] = item_type
	if (claim.get("properties", {}) as Dictionary).is_empty():
		claim["properties"] = properties.duplicate(true)
	claim["counts_physical_food"] = bool(
		claim.get("counts_physical_food", counts_physical_food)
	)
	claim["claim_tick"] = _sequence_tick()
	_resource_claims[source_id] = claim
	# The commitment already names an extant source item. Publish it before pickup
	# can emit observer-visible feedback, then move that exact identity.
	_publish_generated_runtime_authority()
	return _resume_resource_claim(source_id, true, source)


func _resource_claim_source_interactable(source_id: String) -> Node:
	var claim_v: Variant = _resource_claims.get(source_id, {})
	if not (claim_v is Dictionary):
		return null
	var claim := claim_v as Dictionary
	var node_id := str(claim.get("node_id", ""))
	if node_id != "" and _node_interactables.get(node_id, null) is Node:
		return _node_interactables.get(node_id, null) as Node
	for cache_v in _branch_caches:
		if cache_v is Dictionary \
				and _physical_cache_source_id(cache_v as Dictionary) == source_id:
			return (cache_v as Dictionary).get("interactable", null) as Node
	return null


func _resource_claim_template_for_source(source_id: String) -> Dictionary:
	for node_v in _nodes():
		if not (node_v is Dictionary):
			continue
		var node := node_v as Dictionary
		if _node_resource_source_id(str(node.get("id", ""))) != source_id:
			continue
		var handler := _runtime_handler_for_node(node)
		if handler in [
			RuntimeRegistryScript.HANDLER_PHYSICAL_LYSATE,
			RuntimeRegistryScript.HANDLER_PHYSICAL_PAYLOAD,
		]:
			return _new_resource_claim(_generated_resource_contract(node))
	for cache_v in _branch_caches:
		if cache_v is Dictionary \
				and _physical_cache_source_id(cache_v as Dictionary) == source_id:
			return _new_resource_claim(
				_physical_cache_resource_contract(cache_v as Dictionary)
			)
	return {}


func _reconcile_resource_claims_after_restore() -> void:
	var normalized := {}
	for source_id_v in _resource_claims.keys():
		var source_id := str(source_id_v)
		var claim_v: Variant = _resource_claims.get(source_id_v, {})
		if not (claim_v is Dictionary):
			continue
		var claim := (claim_v as Dictionary).duplicate(true)
		if int(claim.get("version", 0)) != RESOURCE_CLAIM_VERSION \
				or str(claim.get("source_id", "")) != source_id \
				or str(claim.get("phase", "")) not in [
					RESOURCE_PHASE_AVAILABLE,
					RESOURCE_PHASE_CLAIMING,
					RESOURCE_PHASE_CLAIMED,
				]:
			continue
		var template := _resource_claim_template_for_source(source_id)
		for field in [
			"node_id",
			"progression_node_id",
			"resource_kind",
			"item_type",
			"source_position",
			"properties",
			"counts_physical_food",
		]:
			if not claim.has(field) or (
				claim[field] is String and str(claim[field]) == ""
			) or (
				claim[field] is Array and (claim[field] as Array).is_empty()
			) or (
				claim[field] is Dictionary and (claim[field] as Dictionary).is_empty()
			):
				claim[field] = template.get(field, claim.get(field))
		normalized[source_id] = claim
	_resource_claims = normalized
	if _resource_claims.is_empty():
		# Compatibility for an authority record written before source transactions.
		# Only construction-state saves take this path; an old collected resource has
		# no stable mapping and therefore fails closed instead of being duplicated.
		_initialize_resource_claim_authority()
	var source_ids: Array = _resource_claims.keys()
	source_ids.sort()
	for source_id_v in source_ids:
		var source_id := str(source_id_v)
		var claim := _resource_claims[source_id] as Dictionary
		var phase := _resource_claim_phase(source_id)
		if phase == RESOURCE_PHASE_CLAIMING:
			_resume_resource_claim(source_id)
		elif phase == RESOURCE_PHASE_CLAIMED:
			_commit_resource_claim_progression(claim)
		elif _resource_claim_item_is_valid(_get_game_state(), claim):
			if not _resource_claim_item_is_at_source(_get_game_state(), claim):
				_finish_resource_claim(source_id)
		elif str(claim.get("item_id", "")) == "":
			# Compatibility for a pre-source-seam untouched fixture. New authority
			# always has a nonempty id, so a missing committed id never takes this path.
			_ensure_resource_source_item(source_id)
		else:
			_finish_resource_claim(source_id)
	_rebuild_resource_claim_indexes()
	_apply_resource_claim_presenters()


## Always-refusing stub. Physical lysate moves only from the callback of
## its exact bound one-shot Interactable.
func _try_collect_physical_lysate(
	_cache: Dictionary, _properties: Dictionary, _interaction_actor := ""
) -> Dictionary:
	return {}


func _transfer_physical_lysate_from_receipt(
	cache: Dictionary, _properties: Dictionary, source: Node
) -> Dictionary:
	if cache.is_empty():
		return {}
	var source_id := _physical_cache_source_id(cache)
	if source == null \
			or source != cache.get("interactable", null) \
			or source != _resource_claim_source_interactable(source_id) \
			or not _generated_interactable_receipt_pending(source, true) \
			or _resource_claim_phase(source_id) != RESOURCE_PHASE_AVAILABLE:
		return {}
	var recipient := str(source.get("active_character"))
	if not _generated_actor_ready_at(source, recipient):
		return {}
	var gs = _get_game_state()
	if gs == null or not ("characters" in gs) \
			or not (gs.characters as Dictionary).has(recipient):
		return {}
	if gs.has_method("has_free_hand") and not bool(gs.call("has_free_hand", recipient)):
		return {}
	var claim := _resource_claims.get(source_id, {}) as Dictionary
	if claim.is_empty() or not _resource_claim_item_is_at_source(gs, claim):
		return {}
	var node_id := str(claim.get("node_id", ""))
	var pickup := _begin_resource_claim(
		source_id,
		node_id,
		str(claim.get("progression_node_id", node_id)),
		str(claim.get("resource_kind", RESOURCE_KIND_PHYSICAL_FOOD)),
		recipient,
		str(claim.get("item_type", "lysate")),
		claim.get("properties", {}) as Dictionary,
		bool(claim.get("counts_physical_food", true)),
		source
	)
	return pickup


## How many branch salvage caches exist / were collected — for tests + overlays.
func get_branch_cache_count() -> int:
	return _branch_caches.size()


func _build_generated_nodes() -> void:
	for node in _nodes():
		if not (node is Dictionary):
			continue
		_build_generated_node(node as Dictionary)


func _build_generated_resource_cradle(
	node_id: String, source_position: Vector3, color: Color
) -> MeshInstance3D:
	var cradle := _add_box(
		self,
		source_position + Vector3(0.0, 0.08, 0.0),
		Vector3(1.15, 0.12, 0.92),
		color.darkened(0.72),
		color.darkened(0.08),
		0.24,
		"ResourceCradle_%s" % node_id
	)
	for side in [-0.48, 0.48]:
		_add_box(
			self,
			source_position + Vector3(side, 0.28, 0.0),
			Vector3(0.08, 0.38, 0.92),
			color.darkened(0.68),
			color.darkened(0.16),
			0.18,
			"ResourceCradleRail_%s" % node_id
		)
	cradle.set_meta("visual_role", "physical_source_housing")
	cradle.set_meta("generated_node_id", node_id)
	return cradle


func _build_generated_node(node: Dictionary) -> void:
	var node_id := str(node.get("id", "node"))
	var pos := _node_position(node_id)
	if pos == Vector3.INF:
		return
	var role := str(node.get("role", "route"))
	var pad_size := _vec3(node.get("footprint", node.get("floor_size", [])), _node_pad_size(role))
	var highlight_meshes: Array[MeshInstance3D] = []
	var handler_id := _runtime_handler_for_node(node)
	var actionable := handler_id != ""
	var base_role_color := _role_color(role)
	var physical_source_handler := handler_id in [
		RuntimeRegistryScript.HANDLER_PHYSICAL_LYSATE,
		RuntimeRegistryScript.HANDLER_PHYSICAL_PAYLOAD,
	]
	var ground_resource_handler := physical_source_handler
	var approach := _vec3(
		node.get("approach_position", []), pos + Vector3(0.0, 0.0, pad_size.z * 0.34)
	)
	var marker_albedo := (
		base_role_color.lightened(0.04) if actionable else base_role_color.darkened(0.42)
	)
	var marker_emission := (
		base_role_color.lightened(0.18) if actionable else base_role_color.darkened(0.36)
	)
	var marker_emission_energy := 0.34 if actionable else 0.035

	# A compact marker post the player reads + clicks, plus the content markers below — never a big role
	# pad over the tiled floor. Elevation posts show when a node sits on an upper floor.
	_build_elevation_posts(pos, pad_size, int(node.get("elevation_index", 0)), base_role_color)
	highlight_meshes.append_array(_build_node_content_markers(node, pos))
	if handler_id == "":
		# A layout record has no verb or lifecycle. Its real room-piece and dressing
		# remain, but it does not gain a titled cube or phantom interaction.
		return
	var marker: MeshInstance3D = null
	if ground_resource_handler:
		# This is a source housing, not the reward. The visible reward is the exact
		# GameState item materialized at the same flat/data position.
		marker = _build_generated_resource_cradle(node_id, approach, base_role_color)
		highlight_meshes.append(marker)
		_node_markers[node_id] = marker
	elif not physical_source_handler:
		marker = _add_box(
			self,
			pos + Vector3(0.0, 0.42, 0.0),
			Vector3(0.9, 0.84, 0.9),
			marker_albedo,
			marker_emission,
			marker_emission_energy,
			"NodeMarker_%s" % node_id
		)
		marker.set_meta("visual_role", "interactive_anchor")
		highlight_meshes.append(marker)
		_node_markers[node_id] = marker
	if actionable:
		var hierarchy := _visual_hierarchy()
		var focus_position := approach if physical_source_handler else pos
		var focus_light := _add_light(
			self,
			focus_position + Vector3(0.0, 1.45, 0.0),
			base_role_color.lightened(0.18),
			float(hierarchy.get("interactive_light_energy", 1.05)) * 0.55,
			float(hierarchy.get("interactive_light_range", 4.4))
		)
		focus_light.set_meta("visual_role", "interactive_focus")
		focus_light.set_meta("generated_node_id", node_id)
		_node_focus_lights[node_id] = focus_light
	# Authored feature prefabs carry their own edge label. Repeating the generic node title over
	# it obscures the sockets and turns the causal composition into a block of floating copy.
	if (
		not physical_source_handler
		and (node.get("spatial_feature", {}) as Dictionary).is_empty()
	):
		_add_label(
			self,
			str(node.get("title", node_id)).to_upper(),
			pos + Vector3(0.0, 1.78, 0.0),
			Color(0.88, 0.93, 0.95)
		)
	var action_verb := RuntimeRegistryScript.initial_action_label(node, handler_id)
	var work_duration := _generated_interaction_duration(node)
	var interaction_type := (
		Interactable.InteractableType.TIMED_ACTION
		if work_duration > 0.0
		else Interactable.InteractableType.INSPECTION
	)

	var interactable := _add_interactable(
		self,
		"GeneratedNode_%s" % node_id,
		str(node.get("title", node_id)),
		approach + Vector3(0.0, 0.12, 0.0),
		action_verb,
		"",
		work_duration,
		true,
		1.8,
		interaction_type,
		false
	)
	var section: Dictionary = node.get("playable_section", {})
	if not section.is_empty():
		interactable.set("consequence_preview", str(section.get("predicted_effect", "")))
		interactable.set_meta("playable_section", section.duplicate(true))
	# Procedural stretches can put several actionable nodes in one camera view. Persistent
	# binding billboards turn that composition into a wall of repeated "Right-click" copy;
	# the shared outline cursor still exposes this same action verb on hover.
	if interactable.has_method("hide_tutorial_label_immediate"):
		interactable.call("hide_tutorial_label_immediate")
	var authored_interaction_approach: Dictionary = node.get(
		"interaction_approach", {})
	var interaction_approach := _project_interaction_approach_to_runtime_grid(
		authored_interaction_approach, _runtime_navigation_cell_delta)
	if not interaction_approach.is_empty():
		var contract_validation := _validate_runtime_interaction_approach(
			interaction_approach, approach)
		if not bool(contract_validation.get("accepted", false)):
			contract_validation["focus_node_id"] = node_id
			_runtime_interaction_contract_errors[node_id] = \
				contract_validation.duplicate(true)
			interactable.set_meta(
				"runtime_interaction_navigation_error",
				contract_validation.duplicate(true)
			)
			interaction_approach.clear()
	if not interaction_approach.is_empty():
		# CharacterInteractionController consumes this exact typed region through
		# the ordinary outline/delegate click path. The visible source itself is
		# built at node.approach_position, which the generator projects from the
		# contract's primary graph vertex.
		interactable.set_meta(
			"interaction_navigation_region",
			interaction_approach.duplicate(true)
		)
		interactable.set_meta("flat_authored_position", approach)
		interactable.set_meta("generated_interaction_data_position", approach)
	interactable.set_pre_trigger_validator(
		_validate_generated_node_trigger.bind(node_id, interactable)
	)
	interactable.set_interaction_route_preflight(
		_query_generated_node_interaction_gate.bind(node_id, interactable),
		_present_generated_interaction_refusal.bind(node_id, interactable)
	)
	_node_interactables[node_id] = interactable
	var target_size := Vector3(maxf(1.8, pad_size.x), 1.35, maxf(1.8, pad_size.z))
	var target_position := approach if physical_source_handler else pos
	var target_center := target_position + Vector3(0.0, 0.58, 0.0)
	if ground_resource_handler:
		# The cradle union spans about 1.15 x 0.45 x 0.92. Keep a modest visible-edge
		# allowance, but do not turn the surrounding room footprint into an invisible
		# click surface: nested/folded layouts can place another visible pickup behind
		# this one along the camera ray.
		target_size = Vector3(1.35, 0.62, 1.12)
		target_center = approach + Vector3(0.0, 0.25, 0.0)
	elif physical_source_handler:
		target_size = Vector3(1.8, 1.35, 1.8)
	var target := _add_outline_target(
		self,
		"GeneratedNodeTarget_%s" % node_id,
		target_center,
		target_size,
		highlight_meshes,
		node_id,
		interactable
	)

	# Cross-wire BOTH directions: the target already delegates to the interactable; the interactable
	# must point back so hover/SHIFT light the node's real marker meshes, not whatever geometry the
	# auto-outline would collect from the interactable itself (a dwell ring is a flat, unreadable circle).
	if target != null and interactable.has_method("set_outline_target"):
		interactable.call("set_outline_target", target)
		# Every generated-node pick hull follows its visible marker meshes through
		# layout warps.  The authored navigation region remains the interaction
		# approach contract; this alignment only keeps the mouse target on-screen
		# with the presentation a player can actually see.
		target.set_meta(
			"align_pick_target_to_highlights_after_warp", true)
		if not interaction_approach.is_empty():
			target.set_meta(
				"interaction_navigation_region",
				interaction_approach.duplicate(true)
			)

		interactable.input_ray_pickable = false
	# set_outline_target connects the exact source-token success presentation.
	# Keep it ahead of the consequence callback: a one-shot pickup commits by
	# disabling/removing its source presenter, so committing first could erase the
	# target before its green result pulse received the same signal.
	interactable.interacted.connect(
		Callable(self, "_on_generated_node_interacted").bind(node_id, interactable)
	)
	_node_targets[node_id] = target
	_wire_generated_section_feedback(node, interactable)


func _on_generated_node_interacted(node_id: String, interactable: Node) -> void:
	if interactable == null or not is_instance_valid(interactable):
		return
	if not _commit_generated_node_from_receipt(node_id, interactable):
		_rearm_generated_node_control(interactable)


## Resolve only concrete endpoints owned by the implemented runtime handler. The
## prose roles/categories in `playable_section` remain explanatory copy; they are
## never allowed to select a mesh, invent a target, or become gameplay authority.
func _generated_section_runtime_feedback_binding(
	node: Dictionary, interactable: Node3D
) -> Dictionary:
	var node_id := str(node.get("id", ""))
	if node_id == "" or interactable == null or not is_instance_valid(interactable):
		return {}
	var handler_id := _runtime_handler_for_node(node)
	var party_endpoint: Node3D
	match handler_id:
		RuntimeRegistryScript.HANDLER_PHYSICAL_LYSATE:
			party_endpoint = _generated_section_party_target(node_id)
			return {
				"runtime_binding_id": FEEDBACK_BINDING_LYSATE_TO_CARRIER,
				"runtime_handler": handler_id,
				"source": interactable,
				"target": party_endpoint,
				"default_label": "LYSATE ENTERS THIS CHARACTER'S HAND",
			}
		RuntimeRegistryScript.HANDLER_PHYSICAL_PAYLOAD:
			party_endpoint = _generated_section_party_target(node_id)
			return {
				"runtime_binding_id": FEEDBACK_BINDING_PAYLOAD_TO_CARRIER,
				"runtime_handler": handler_id,
				"source": interactable,
				"target": party_endpoint,
				"default_label": "LOAD ENTERS THIS CHARACTER'S HAND",
			}
		RuntimeRegistryScript.HANDLER_CANONICAL_SHELTER_ARRIVAL:
			party_endpoint = _generated_section_party_target(node_id)
			return {
				"runtime_binding_id": FEEDBACK_BINDING_PARTY_TO_SHELTER,
				"runtime_handler": handler_id,
				"source": party_endpoint,
				"target": interactable,
				"default_label": "PARTY ENTERS SHELTER",
			}
	return {}


## Materialize a handler-owned cause -> effect edge. Hover and planning pause use
## the shared SceneChunk perception query, which sees through the union of every
## present conscious party member rather than granting global visibility.
func _wire_generated_section_feedback(node: Dictionary, interactable: Node3D) -> void:
	var binding := _generated_section_runtime_feedback_binding(node, interactable)
	if binding.is_empty():
		return
	var node_id := str(node.get("id", ""))
	var visual_source := binding.get("source", null) as Node3D
	var target := binding.get("target", null) as Node3D
	if (
		visual_source == null
		or not is_instance_valid(visual_source)
		or target == null
		or not is_instance_valid(target)
		or visual_source == target
	):
		return
	var section: Dictionary = node.get("playable_section", {})
	var owner_character := _get_active_character()
	var link := _add_causal_feedback_link(
		visual_source,
		target,
		_character_color(owner_character),
		{
			"name": "GeneratedSectionLink_%s" % node_id,
			"interaction_source": interactable,
			"label": str(
				section.get("relationship_label", binding.get("default_label", "CHANGES"))
			),
			# The cursor already names the relation and exact consequence. Keeping
			# every fixed-size Label3D visible in planning mode turns the overview
			# into a wall of text; the rings/dashes carry the spatial connection.
			"show_label": false,
			"feedback_mode": "predicted",
			"visibility_policy": "contextual",
			"owner_character": owner_character,
			"source_offset": Vector3(0.0, 0.95, 0.0),
			"target_offset": Vector3(0.0, 0.95, 0.0),
			"arc_height": 1.65,
			"dash_count": 9,
			"flow_speed": 0.32,
			"draw_duration": 0.45,
			# Generated previews reserve persistent HUD drawers at the bottom. Do not
			# render half-clipped rings through those controls during planning pause.
			"viewport_safe_margins": Vector4(42.0, 66.0, 42.0, 146.0),
		}
	)
	if link != null:
		_generated_section_links[node_id] = link
		_generated_section_states[node_id] = {
			"state": "predicted",
			"runtime_binding_id": str(binding.get("runtime_binding_id", "")),
			"runtime_handler": str(binding.get("runtime_handler", "")),
			"source": visual_source,
			"target": target,
			"predicted_effect": str(section.get("predicted_effect", "")),
		}


func _generated_section_cause_target(
		node_id: String, _source_role := "", _source_category := "") -> Node3D:
	var state_v: Variant = _generated_section_states.get(node_id, {})
	if state_v is Dictionary:
		var source = (state_v as Dictionary).get("source", null)
		if source is Node3D and is_instance_valid(source):
			return source as Node3D
	return null


func _generated_section_effect_target(
		node_id: String, _effect_role := "", _effect_category := "", exclude: Node3D = null
	) -> Node3D:
	var state_v: Variant = _generated_section_states.get(node_id, {})
	if state_v is Dictionary:
		var target = (state_v as Dictionary).get("target", null)
		if target is Node3D and is_instance_valid(target) and target != exclude:
			return target as Node3D
	return null


func _generated_section_party_target(node_id: String) -> Node3D:
	if _generated_party_endpoints.has(node_id):
		var existing: Node3D = _generated_party_endpoints[node_id] as Node3D
		if existing != null and is_instance_valid(existing):
			return existing
	var endpoint := Node3D.new()
	endpoint.name = "GeneratedPartyEndpoint_%s" % node_id
	endpoint.top_level = true
	endpoint.set_meta("character_id", _get_active_character())
	endpoint.set_meta("locked_character", false)
	add_child(endpoint)
	_generated_party_endpoints[node_id] = endpoint
	_update_generated_party_endpoint(endpoint)
	return endpoint


func _update_generated_party_endpoints() -> void:
	for endpoint_v in _generated_party_endpoints.values():
		if is_instance_valid(endpoint_v) and endpoint_v is Node3D:
			_update_generated_party_endpoint(endpoint_v as Node3D)


func _update_generated_party_endpoint(endpoint: Node3D) -> void:
	if endpoint == null or host == null:
		return
	var character_id := str(endpoint.get_meta("character_id", _get_active_character()))
	if not bool(endpoint.get_meta("locked_character", false)):
		character_id = _get_active_character()
		endpoint.set_meta("character_id", character_id)
	if host.has_method("get_preview_character_node"):
		var character_node = host.call("get_preview_character_node", character_id)
		if character_node is Node3D and is_instance_valid(character_node):
			endpoint.global_position = (character_node as Node3D).global_position


func _generated_action_verb(node: Dictionary) -> String:
	return RuntimeRegistryScript.initial_action_label(node, _runtime_handler_for_node(node))


func _generated_interaction_duration(node: Dictionary) -> float:
	match _runtime_handler_for_node(node):
		RuntimeRegistryScript.HANDLER_CANONICAL_SHELTER_ARRIVAL:
			return 1.4
		RuntimeRegistryScript.HANDLER_PHYSICAL_LYSATE:
			return 0.7
		RuntimeRegistryScript.HANDLER_PHYSICAL_PAYLOAD:
			return 1.0
	return 0.0


## Character palette shared by generated feedback endpoints.
func _character_color(character: String) -> Color:
	match character:
		"aster":
			return Color(0.29, 0.62, 1.0)
		"peris":
			return Color(1.0, 0.67, 0.27)
		"endo":
			return Color(0.4, 0.72, 0.55)
		_:
			return Color(0.7, 0.72, 0.76)


func _build_node_content_markers(node: Dictionary, pos: Vector3) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	var label_parts: Array[String] = []
	var node_id := str(node.get("id", "node"))
	_node_content_nodes[node_id] = {
		"flora": [], "enemies": [], "structures": [], "dressing": []
	}
	var offsets := [Vector3(-1.45, 0.35, -1.0), Vector3(1.45, 0.35, -1.0), Vector3(0.0, 0.35, 1.15)]
	var placements: Array = node.get("content_placements", [])
	# Presence of this field is the content-realization contract, including an
	# intentionally empty list. Falling back to the raw palette arrays when the
	# generator emitted no bindings would resurrect every omitted noun as a proxy.
	if node.has("content_placements"):
		for raw_placement in placements:
			if not (raw_placement is Dictionary):
				continue
			var placement := raw_placement as Dictionary
			var category := str(placement.get("category", ""))
			var key := str(placement.get("id", ""))
			if not RuntimeRegistryScript.generated_content_is_realized(category, key):
				_omitted_content_count += 1
				continue
			var support := str(placement.get("support", _catalog.support_level(category, key)))
			var marker_pos := _vec3(placement.get("position", []), pos)
			var marker_size := _vec3(placement.get("size", []), Vector3(0.8, 0.8, 0.8))
			var marker := _add_content_marker(
				placement,
				marker_pos,
				marker_size,
				_content_color(category, support),
				"Generated_%s_%s" % [category, key]
			)
			if marker == null:
				_omitted_content_count += 1
				continue
			marker.set_meta("generated_node_id", node_id)
			marker.set_meta("generated_content_category", category)
			marker.set_meta("generated_content_id", key)
			var realized := bool(marker.get_meta("generated_content_realized", false))
			if not realized:
				_omitted_content_count += 1
				marker.queue_free()
				continue
			_register_generated_content_node(node_id, category, marker)
			meshes.append(marker)
			_content_marker_count += 1
			var content_label := _add_label(
				self,
				_content_player_label(category, key, realized),
				marker_pos + Vector3(0.0, marker_size.y * 0.55 + 0.34, 0.0),
				(
					_content_color(category, support).lightened(0.25)
					if realized
					else _content_color(category, support).darkened(0.42)
				)
			)
			content_label.set_meta("generated_proxy_label", false)
			content_label.set_meta("generated_content_id", key)
			if not (node.get("spatial_feature", {}) as Dictionary).is_empty():
				content_label.pixel_size = 0.0045
				content_label.font_size = 40
			label_parts.append(_content_summary_token(category, key, realized))
		if (node.get("spatial_feature", {}) as Dictionary).is_empty():
			_add_content_summary_labels(node, pos, label_parts, meshes.size())
		return meshes

	var marker_index := 0
	for category in ["flora", "enemies", "structures"]:
		var values: Array = node.get(category, [])
		for value in values:
			var key := str(value)
			if not RuntimeRegistryScript.generated_content_is_realized(category, key):
				_omitted_content_count += 1
				continue
			var marker_pos: Vector3 = (
				pos
				+ offsets[marker_index % offsets.size()]
				+ Vector3(0.0, float(marker_index / offsets.size()) * 0.52, 0.0)
			)
			var support := _catalog.support_level(category, key)
			var fallback_placement := {
				"category": category,
				"id": key,
				"support": support,
				"shape": "plant_cluster" if category == "flora" else "structure_box",
			}
			var fallback_marker := _add_content_marker(
				fallback_placement,
				marker_pos,
				Vector3(0.74, 0.58, 0.74),
				_content_color(category, support),
				"Generated_%s_%s" % [category, key]
			)
			if fallback_marker == null:
				_omitted_content_count += 1
				continue
			fallback_marker.set_meta("generated_node_id", node_id)
			fallback_marker.set_meta("generated_content_category", category)
			fallback_marker.set_meta("generated_content_id", key)
			var realized := bool(fallback_marker.get_meta("generated_content_realized", false))
			if not realized:
				_omitted_content_count += 1
				fallback_marker.queue_free()
				continue
			_register_generated_content_node(node_id, category, fallback_marker)
			meshes.append(fallback_marker)
			_content_marker_count += 1
			var fallback_label := _add_label(
				self,
				_content_player_label(category, key, realized),
				marker_pos + Vector3(0.0, 0.72, 0.0),
				(
					_content_color(category, support).lightened(0.25)
					if realized
					else _content_color(category, support).darkened(0.42)
				)
			)
			fallback_label.set_meta("generated_proxy_label", false)
			fallback_label.set_meta("generated_content_id", key)
			label_parts.append(_content_summary_token(category, key, realized))
			marker_index += 1
	if label_parts.is_empty():
		return meshes
	_add_label(self, " ".join(label_parts), pos + Vector3(0.0, 2.22, 0.0), Color(0.62, 0.7, 0.74))
	return meshes


func _register_generated_content_node(node_id: String, category: String, content_node: Node3D) -> void:
	if not _node_content_nodes.has(node_id):
		_node_content_nodes[node_id] = {}
	var categories := _node_content_nodes[node_id] as Dictionary
	var entries: Array = categories.get(category, [])
	entries.append(content_node)
	categories[category] = entries
	_node_content_nodes[node_id] = categories


func _build_palette_legend() -> void:
	var usage: Dictionary = _spec.get("palette_usage", {})
	var legend := "Palette "
	var sections: Array[String] = []
	for category in ["flora", "enemies", "structures"]:
		sections.append("%s:%s" % [category, ",".join(_string_array(usage.get(category, [])))])
	legend += " | ".join(sections)
	_add_label(
		self, legend, _anchor_position("entry") + Vector3(6.5, 2.2, -3.4), Color(0.68, 0.74, 0.78)
	)
	var composition: Dictionary = _spec.get("composition", {})
	if not composition.is_empty() and int(composition.get("chain_count", 0)) > 0:
		var composition_label := (
			"Composition chain:%d nested:%d depth:%d"
			% [
				int(composition.get("chain_count", 0)),
				int(composition.get("nested_count", 0)),
				int(composition.get("nested_depth", 0))
			]
		)
		if bool(composition.get("uses_random_walk", false)):
			composition_label = (
				"Random walk elements:%d archetypes:%d"
				% [
					int(composition.get("walk_element_count", 0)),
					int(composition.get("walk_archetype_count", 0))
				]
			)
		_add_label(
			self,
			composition_label,
			_anchor_position("entry") + Vector3(6.5, 2.75, -3.4),
			Color(0.74, 0.68, 0.84)
		)


func _ensure_graybox_layout() -> void:
	if _spec.is_empty():
		return
	var graybox: Dictionary = _spec.get("graybox", {})
	var nodes_have_placements := false
	for node in _spec.get("nodes", []):
		if node is Dictionary and (node as Dictionary).has("content_placements"):
			nodes_have_placements = true
			break
	if (
		str(graybox.get("contract_id", "")) == "generated_stretch_graybox_v1"
		and nodes_have_placements
	):
		return

	var settings: Dictionary = _spec.get("settings", {})
	if not settings.is_empty():
		var regenerated := StretchGeneratorScript.generate(settings)
		if bool(regenerated.get("success", false)):
			for key in ["graybox", "nodes", "routes", "anchors"]:
				if regenerated.has(key):
					_spec[key] = regenerated.get(key)
			if regenerated.has("navigation"):
				_spec["navigation"] = regenerated.get("navigation")
			return

	_apply_local_graybox_fallback()


func _ensure_navigation_layout() -> void:
	if _spec.is_empty():
		return
	var nav_grid: Dictionary = _spec.get("navigation_grid", {})
	if str(nav_grid.get("contract_id", "")) == GridWorld.GRID_DATA_CONTRACT_ID:
		return
	var settings: Dictionary = _spec.get("settings", {})
	if not settings.is_empty():
		var regenerated := StretchGeneratorScript.generate(settings)
		if bool(regenerated.get("success", false)) and regenerated.has("navigation_grid"):
			# Navigation, node positions, room pieces, and graybox bounds are one spatial snapshot. Copying only
			# the grid lets saved dressing from an older generator revision drift off the walkable floor.
			for key in ["navigation_grid", "graybox", "nodes", "routes", "anchors", "navigation", "roompieces"]:
				if regenerated.has(key):
					_spec[key] = regenerated.get(key)
			return
	_spec["navigation_grid"] = StretchGeneratorScript.build_navigation_grid_from_spec(_spec)


func _apply_local_graybox_fallback() -> void:
	var nodes: Array = _spec.get("nodes", [])
	var routes: Array = _spec.get("routes", [])
	var min_point := Vector3(1e+20, 1e+20, 1e+20)
	var max_point := Vector3(-1e+20, -1e+20, -1e+20)
	var elevations: Array[int] = []
	var placement_count := 0
	for i in range(nodes.size()):
		if not (nodes[i] is Dictionary):
			continue
		var node: Dictionary = nodes[i]
		var elevation_index := 0 if i == 0 or i == nodes.size() - 1 else i % 3
		var pos := _vec3(node.get("position", []), Vector3(float(i) * 12.0, 0.45, 0.0))
		pos.y = 0.45 + float(elevation_index) * 0.72
		var footprint := _node_pad_size(str(node.get("role", "mixed")))
		node["position"] = _vec3_array(pos)
		node["elevation_index"] = elevation_index
		node["surface_y"] = pos.y
		node["elevation_meters"] = pos.y - 0.45
		node["footprint"] = _vec3_array(footprint)
		node["floor_size"] = _vec3_array(footprint)
		node["approach_position"] = _vec3_array(pos + Vector3(0.0, 0.0, footprint.z * 0.34))
		node["content_placements"] = _fallback_content_placements(node, pos, footprint)
		placement_count += (node["content_placements"] as Array).size()
		nodes[i] = node
		if not elevations.has(elevation_index):
			elevations.append(elevation_index)
		var half := footprint * 0.5 + Vector3.ONE
		min_point = (pos - half) if i == 0 else min_point.min(pos - half)
		max_point = (
			(pos + half + Vector3(0.0, 3.0, 0.0))
			if i == 0
			else max_point.max(pos + half + Vector3(0.0, 3.0, 0.0))
		)
	for i in range(routes.size()):
		if not (routes[i] is Dictionary):
			continue
		var route: Dictionary = routes[i]
		route["width"] = 1.15 if _route_kind(route) == "risky" else 1.65
		routes[i] = route
	elevations.sort()
	_spec["nodes"] = nodes
	_spec["routes"] = routes
	_spec["anchors"] = _rebuild_anchors_from_nodes(nodes)
	_spec["graybox"] = {
		"contract_id": "generated_stretch_graybox_v1",
		"surface_y_base": 0.45,
		"elevation_step": 0.72,
		"elevation_indices": elevations,
		"elevation_count": elevations.size(),
		"supports_click_to_move": true,
		"supports_outline_targets": true,
		"supports_multiple_elevations": elevations.size() > 1,
		"node_surface_count": nodes.size(),
		"route_surface_count": routes.size(),
		"content_placement_count": placement_count,
		"bounds":
		{
			"min": _vec3_array(min_point),
			"max": _vec3_array(max_point),
			"center": _vec3_array((min_point + max_point) * 0.5),
			"size": _vec3_array(max_point - min_point),
		},
	}


func _fallback_content_placements(node: Dictionary, pos: Vector3, footprint: Vector3) -> Array:
	var placements := []
	var slot_index := 0
	for category in ["flora", "enemies", "structures"]:
		var values: Array = node.get(category, [])
		for value in values:
			var key := str(value)
			if not RuntimeRegistryScript.generated_content_is_realized(category, key):
				continue
			var size := _fallback_content_size(category)
			var offset := Vector3(
				-footprint.x * 0.22 + slot_index * 0.65,
				size.y * 0.5,
				-footprint.z * 0.16 + slot_index * 0.34
			)
			(
				placements
				. append(
					{
						"id": key,
						"category": category,
						"support": _catalog.support_level(category, key),
						"shape":
						(
							"enemy_volume"
							if category == "enemies"
							else ("plant_cluster" if category == "flora" else "structure_box")
						),
						"size": _vec3_array(size),
						"local_offset": _vec3_array(offset),
						"position": _vec3_array(pos + offset),
						"rotation_y_degrees": float(slot_index * 31),
						"label": key,
					}
				)
			)
			slot_index += 1
	return placements


func _fallback_content_size(category: String) -> Vector3:
	match category:
		"flora":
			return Vector3(1.2, 1.0, 1.2)
		"enemies":
			return Vector3(1.4, 1.1, 1.4)
		"structures":
			return Vector3(1.6, 1.2, 1.0)
		_:
			return Vector3.ONE


func _rebuild_anchors_from_nodes(nodes: Array) -> Dictionary:
	var anchors: Dictionary = _spec.get("anchors", {}).duplicate(true)
	if not anchors.has("aster"):
		anchors["aster"] = [0.0, 0.5, 1.6]
	if not anchors.has("peris"):
		anchors["peris"] = [-1.6, 0.5, 0.0]
	if not anchors.has("endo"):
		anchors["endo"] = [-1.2, 0.5, -1.8]
	for node in nodes:
		if node is Dictionary:
			anchors[str((node as Dictionary).get("id", ""))] = (node as Dictionary).get(
				"position", [0.0, 0.45, 0.0]
			)
	return anchors


func _graybox_state() -> Dictionary:
	var graybox: Dictionary = _spec.get("graybox", {})
	var nav_grid: Dictionary = _spec.get("navigation_grid", {})
	return {
		"contract_id": str(graybox.get("contract_id", "")),
		"navigation_contract_id":
		str(graybox.get("navigation_contract_id", nav_grid.get("contract_id", ""))),
		"supports_click_to_move": bool(graybox.get("supports_click_to_move", false)),
		"supports_outline_targets": bool(graybox.get("supports_outline_targets", false)),
		"supports_multiple_elevations": bool(graybox.get("supports_multiple_elevations", false)),
		"elevation_count": int(graybox.get("elevation_count", 0)),
		"node_surface_count": int(graybox.get("node_surface_count", _nodes().size())),
		"route_surface_count": int(graybox.get("route_surface_count", _routes().size())),
		"navigation_node_count": int(graybox.get("navigation_node_count", _nodes().size())),
		"navigation_edge_count": int(graybox.get("navigation_edge_count", _routes().size())),
		"content_placement_count":
		int(graybox.get("content_placement_count", _content_marker_count)),
		"instanced_content_marker_count": _content_marker_count,
		"spatial_feature_count": int(graybox.get("spatial_feature_count", 0)),
		"instanced_spatial_feature_count": _spatial_feature_roots.size(),
		"themed_landmark_count": int(graybox.get("themed_landmark_count", 0)),
		"instanced_themed_landmark_count": _theme_landmark_roots.size(),
		"zone_transition_floor_cell_count": _zone_transition_floor_cell_count,
		"outline_target_count": _node_targets.size(),
		"route_surface_instance_count": _route_surfaces.size(),
		"bounds": graybox.get("bounds", {}).duplicate(true),
	}


func _add_graybox_slab(
	parent: Node3D,
	position: Vector3,
	size: Vector3,
	color: Color,
	node_name := "",
	rotation := Vector3.ZERO,
	add_collision := true
) -> MeshInstance3D:
	var mesh := _add_box(parent, position, size, color, color.lightened(0.08), 0.05, node_name)
	mesh.rotation = rotation
	if add_collision:
		var body := StaticBody3D.new()
		body.name = "%sCollision" % (node_name if node_name != "" else "GrayboxSlab")
		body.position = position
		body.rotation = rotation
		body.collision_layer = 1
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		parent.add_child(body)
	return mesh


func _build_elevation_posts(
	pos: Vector3, pad_size: Vector3, elevation_index: int, color: Color
) -> void:
	if elevation_index <= 0:
		return
	var post_height := maxf(0.24, pos.y - 0.28)
	var corners := [
		Vector3(-pad_size.x * 0.42, -post_height * 0.5 - 0.03, -pad_size.z * 0.42),
		Vector3(pad_size.x * 0.42, -post_height * 0.5 - 0.03, -pad_size.z * 0.42),
		Vector3(-pad_size.x * 0.42, -post_height * 0.5 - 0.03, pad_size.z * 0.42),
		Vector3(pad_size.x * 0.42, -post_height * 0.5 - 0.03, pad_size.z * 0.42),
	]
	for i in range(corners.size()):
		_add_box(
			self,
			pos + corners[i],
			Vector3(0.16, post_height, 0.16),
			color.darkened(0.22),
			Color.BLACK,
			0.0,
			"ElevationPost_%d" % i
		)


func _content_player_label(category: String, key: String, realized: bool) -> String:
	if realized:
		var entry := _catalog.get_content(category, key)
		return str(entry.get("display_name", key.replace("_", " ").capitalize())).to_upper()
	match category:
		"flora":
			return "AMBIENT GROWTH"
		"enemies":
			return "THREAT SIGN"
		"structures":
			return "INERT STRUCTURE"
		_:
			return "SCENERY"


func _content_summary_token(category: String, key: String, realized: bool) -> String:
	if realized:
		return "%s:%s" % [category.substr(0, 1), key]
	match category:
		"flora":
			return "f:ambient"
		"enemies":
			return "e:sign"
		"structures":
			return "s:inert"
		_:
			return "scenery"


func _first_generated_content_mesh(root: Node) -> MeshInstance3D:
	for child in root.get_children():
		if child is MeshInstance3D:
			var mesh_child := child as MeshInstance3D
			if not str(mesh_child.name).contains("InteractableProgressRing") \
					and not str(mesh_child.name).contains("Outline"):
				return mesh_child
		var nested := _first_generated_content_mesh(child)
		if nested != null:
			return nested
	return null


func _generated_hushbloom_enemies() -> Array:
	var result: Array = []
	for candidate in find_children("*", "", true, false):
		if candidate is Enemy:
			result.append(candidate)
	return result


func _generated_hushbloom_portals() -> Array:
	var result: Array = []
	for candidate in find_children("*", "", true, false):
		if candidate is PortalPad:
			result.append(candidate)
	return result


## Materialize only named content whose canonical verb exists in the reusable kit.
func _add_real_content_marker(
	placement: Dictionary,
	marker_pos: Vector3,
	marker_size: Vector3,
	node_name: String
) -> MeshInstance3D:
	if str(placement.get("category", "")) != "flora":
		return null
	var key := str(placement.get("id", ""))
	var runtime_root: Node3D = null
	match key:
		"capbage":
			var capbage := Capbage.new()
			capbage.name = "%s_Runtime" % node_name
			var runtime_navigation := RuntimeRegistryScript.generated_content_navigation(
				"flora", "capbage")
			var body_conceal_radius := float(runtime_navigation.get("radius", 0.45))
			capbage.configure(
				_get_game_state(),
				marker_pos,
				maxf(
					float(runtime_navigation.get("interaction_radius", 1.4)),
					float(placement.get("conceal_radius", 1.4))
				),
				body_conceal_radius
			)
			capbage.set_concealment_origin(marker_pos)
			var authored_navigation_v: Variant = placement.get("navigation", null)
			var authored_navigation := authored_navigation_v as Dictionary \
				if authored_navigation_v is Dictionary else {}
			var navigation_contract := \
				_project_content_navigation_to_runtime_interaction_region(
					authored_navigation,
					_runtime_navigation_cell_delta
				)
			var navigation_validation := _validate_runtime_content_navigation(
				navigation_contract, "flora", "capbage", marker_pos)
			if bool(navigation_validation.get("accepted", false)):
				capbage.set_meta(
					"interaction_navigation_region",
					navigation_contract.duplicate(true)
				)
			else:
				var error_key := "content:%s:%s" % [
					node_name, str(placement.get("position", []))]
				_runtime_interaction_contract_errors[error_key] = \
					navigation_validation.duplicate(true)
				capbage.set_meta(
					"runtime_interaction_navigation_error",
					navigation_validation.duplicate(true)
				)
				capbage.set_interaction_route_preflight(
					Callable(self, "_generated_content_route_preflight").bind(
						navigation_validation.duplicate(true))
				)
			runtime_root = capbage
			add_child(capbage)
			_register_interactable(capbage)
			_generated_capbages.append(capbage)
		"scarpet":
			var scarpet := Scarpet.new()
			scarpet.name = "%s_Runtime" % node_name
			scarpet.configure(
				marker_pos,
				maxf(1.65, float(placement.get("conceal_radius", 1.65))),
				false
			)
			scarpet.set_concealment_origin(marker_pos)
			runtime_root = scarpet
			add_child(scarpet)
			_generated_scarpets.append(scarpet)
		"hushbloom":
			var hushbloom := Hushbloom.new()
			hushbloom.name = "%s_Runtime" % node_name
			var options: Dictionary = (placement.get("runtime_options", {}) as Dictionary).duplicate(true)
			# Generated stretches do not yet own the carried-Hushbloom inventory
			# lifecycle. Keep the honest proximity-stun verb and do not offer a TAKE
			# action that would silently discard the picked plant.
			options["pickable"] = false
			hushbloom.configure(_get_game_state(), marker_pos, options)
			hushbloom.set_effect_origin(marker_pos)
			hushbloom.set_enemy_provider(Callable(self, "_generated_hushbloom_enemies"))
			hushbloom.set_portal_provider(Callable(self, "_generated_hushbloom_portals"))
			runtime_root = hushbloom
			add_child(hushbloom)
			_generated_hushblooms.append(hushbloom)
		_:
			return null
	if runtime_root == null:
		return null
	runtime_root.rotation.y = deg_to_rad(float(placement.get("rotation_y_degrees", 0.0)))
	runtime_root.set_meta("generated_content_realized", true)
	runtime_root.set_meta("generated_semantic_target", true)
	runtime_root.set_meta("generated_content_id", key)
	runtime_root.set_meta("generated_simulation_position", marker_pos)
	runtime_root.set_meta("generated_nominal_size", marker_size)
	var visual := _first_generated_content_mesh(runtime_root)
	if visual == null:
		return null
	visual.set_meta("generated_content_realized", true)
	visual.set_meta("generated_semantic_target", true)
	visual.set_meta("generated_content_runtime_root", runtime_root)
	return visual


func _add_content_marker(
	placement: Dictionary,
	marker_pos: Vector3,
	marker_size: Vector3,
	_color: Color,
	node_name: String
) -> MeshInstance3D:
	var real_marker := _add_real_content_marker(placement, marker_pos, marker_size, node_name)
	if real_marker != null:
		return real_marker
	# Omission is the only honest fallback. A generic box would still occupy the
	# authored socket and visually imply that the missing mechanism exists.
	return null


func _add_content_summary_labels(
	_node: Dictionary, pos: Vector3, label_parts: Array[String], _placement_count: int
) -> void:
	if label_parts.is_empty():
		return
	_add_label(self, " ".join(label_parts), pos + Vector3(0.0, 2.36, 0.0), Color(0.62, 0.7, 0.74))


func _add_outline_target(
	parent: Node3D,
	target_name: String,
	center: Vector3,
	size: Vector3,
	meshes: Array[MeshInstance3D],
	node_id: String,
	delegate: Node
) -> StaticBody3D:
	# Build through the shared outline system so the target is actually bound to a
	# feedback manager in gameplay (an unbound target never lights). Stretch tuning is
	# slimmer than the room default (smaller particle budget, taller highlight box).
	var metadata := {"generated_node_id": node_id}
	var opts := {
		"outline_highlight_height": maxf(0.8, size.y * 0.5),
		"selected_feedback_duration": 1.4,
		"hover_object_outline_width": 0.075,
		"selected_object_glow_strength": 3.2,
		"selected_particle_count": 130,
		"outline_particles_per_mesh": 96,
		"debug_particle_anchor_enabled": false,
		"delegate": delegate,
		"metadata": metadata,
	}
	return (
		_outline_target(
			parent, target_name, center, size, meshes, node_id, maxf(size.x, size.z) * 0.5, opts
		)
		as StaticBody3D
	)


func _new_exit_shelter_transaction() -> Dictionary:
	return {
		"version": EXIT_TRANSACTION_VERSION,
		"phase": EXIT_PHASE_AVAILABLE,
		"roster": [],
		"rest_plan": {},
		"payload_node_ids": [],
		"payload_item_ids": [],
		"started_tick": -1.0,
		"completed_tick": -1.0,
	}


func _exit_shelter_region() -> Dictionary:
	var exit_node := _find_node("exit_shelter")
	var center := Vector3.INF
	var half := Vector3(3.3, 0.0, 2.4)
	if not exit_node.is_empty():
		center = _vec3(exit_node.get("position", []), Vector3.INF)
		var role := str(exit_node.get("role", "shelter"))
		half = _node_pad_size(role if role != "" else "shelter") * 0.5
	if center == Vector3.INF:
		center = _anchor_position("exit_shelter")
		half = Vector3(3.3, 0.0, 2.6)
	return {"center": center, "half": half + Vector3(0.4, 0.0, 0.4)}


func _is_character_in_exact_exit_shelter(character_id: String) -> bool:
	var region := _exit_shelter_region()
	var center: Vector3 = region.get("center", Vector3.INF)
	if center == Vector3.INF:
		return false
	var half: Vector3 = region.get("half", Vector3.ZERO)
	var position := _get_character_position(character_id)
	return (
		position.x >= center.x - half.x
		and position.x <= center.x + half.x
		and position.z >= center.z - half.z
		and position.z <= center.z + half.z
	)


func _required_payload_delivery() -> Dictionary:
	var required_nodes: Array[String] = []
	for node_v in _nodes():
		if not (node_v is Dictionary):
			continue
		var node := node_v as Dictionary
		if (
			_runtime_handler_for_node(node) == RuntimeRegistryScript.HANDLER_PHYSICAL_PAYLOAD
			and bool(node.get("runtime_progression_required", false))
		):
			required_nodes.append(str(node.get("id", "")))

	var gs = _get_game_state()
	var has_inventory_authority: bool = (
		gs != null
		and "characters" in gs
		and "items" in gs
		and gs.has_method("get_hand_items")
	)
	var item_ids: Array[String] = []
	for node_id in required_nodes:
		if not _completed_nodes.has(node_id):
			return {"ready": false, "node_id": node_id, "reason": "payload_not_secured"}
		# A hostless data-layer test cannot create authoritative inventory. Completion
		# is its explicit simulation seam; full previews must prove the exact item is
		# still in an active carrier hand.
		if not has_inventory_authority:
			continue
		var item_id := str(_generated_resource_item_by_node.get(node_id, ""))
		if item_id == "" or not (gs.items as Dictionary).has(item_id):
			return {"ready": false, "node_id": node_id, "reason": "payload_missing"}
		var item: Dictionary = (gs.items as Dictionary).get(item_id, {})
		var carrier := str(item.get("holder", ""))
		if (
			str(item.get("location", "")) != "hand"
			or not _active_party.has(carrier)
			or not (gs.call("get_hand_items", carrier) as Array).has(item_id)
		):
			return {"ready": false, "node_id": node_id, "reason": "payload_not_carried"}
		item_ids.append(item_id)
	return {"ready": true, "node_ids": required_nodes, "item_ids": item_ids}


func _preflight_exit_shelter_transaction(payload_delivery: Dictionary) -> Dictionary:
	var outcome := {
		"ready": false,
		"roster": _shelter_rest_members(),
		"rest_plan": {},
		"payload_node_ids": (payload_delivery.get("node_ids", []) as Array).duplicate(),
		"payload_item_ids": (payload_delivery.get("item_ids", []) as Array).duplicate(),
		"blocked": [],
	}
	var roster := outcome["roster"] as Array
	if roster.is_empty():
		(outcome["blocked"] as Array).append("no active party members")
		return outcome
	# Hostless generator proof explicitly simulates party/economy presentation. Full
	# previews below must pass the same exact authored-region and GameState guards.
	if host == null:
		for char_id_v in roster:
			(outcome["rest_plan"] as Dictionary)[str(char_id_v)] = {"mode": "simulated"}
		outcome["ready"] = true
		return outcome
	var gs = _get_game_state()
	if gs == null or not ("characters" in gs) or gs.get("scheduler") == null:
		(outcome["blocked"] as Array).append("GameState shelter authority is unavailable")
		return outcome
	for char_id_v in roster:
		var char_id := str(char_id_v)
		if not (gs.characters as Dictionary).has(char_id):
			(outcome["blocked"] as Array).append("%s is not present" % char_id.capitalize())
			continue
		if float(gs.call("get_stat", char_id, "hp")) <= 0.0 \
				or bool(gs.call("is_downed", char_id)) \
				or bool(gs.call("is_knocked_down", char_id)):
			(outcome["blocked"] as Array).append("%s must be conscious" % char_id.capitalize())
			continue
		if not _is_character_in_exact_exit_shelter(char_id):
			(outcome["blocked"] as Array).append(
				"%s is outside the authored exit shelter" % char_id.capitalize()
			)
			continue
		if bool(gs.call("is_resting", char_id)):
			(outcome["rest_plan"] as Dictionary)[char_id] = {"mode": "already_resting"}
			continue
		if (
			bool(gs.call("is_dodging", char_id))
			or bool(gs.call("is_endocytosing", char_id))
			or bool(gs.call("is_external_traversal_active", char_id))
			or bool(gs.call("is_dragging", char_id))
			or bool(gs.call("is_field_restoring", char_id))
		):
			(outcome["blocked"] as Array).append(
				"%s is committed to another action" % char_id.capitalize()
			)
			continue
		var hp_full := float(gs.call("get_stat", char_id, "hp")) \
			>= float(gs.call("get_stat_cap", char_id, "hp"))
		var stamina_full := float(gs.call("get_stat", char_id, "stamina")) \
			>= float(gs.call("get_stat_cap", char_id, "stamina"))
		var needs_rest := not hp_full or not stamina_full \
			or float(gs.call("get_time_of_day")) >= GameState.NIGHT_START
		if not needs_rest:
			(outcome["rest_plan"] as Dictionary)[char_id] = {"mode": "already_full"}
			continue
		var atp_before := float(gs.call("get_stat", char_id, "atp"))
		if atp_before < 1.0:
			(outcome["blocked"] as Array).append("%s cannot pay one ATP" % char_id.capitalize())
			continue
		(outcome["rest_plan"] as Dictionary)[char_id] = {
			"mode": "start",
			"atp_before": atp_before,
			"atp_after": atp_before - 1.0,
		}
	var start_members: Array = []
	for char_id_v in roster:
		var char_id := str(char_id_v)
		var plan := (outcome["rest_plan"] as Dictionary).get(char_id, {}) as Dictionary
		if str(plan.get("mode", "")) == "start":
			start_members.append(char_id)
	if (outcome["blocked"] as Array).is_empty() and not start_members.is_empty():
		if not gs.has_method("can_party_rest") \
				or not bool(gs.call("can_party_rest", start_members)):
			(outcome["blocked"] as Array).append(
				"the paid-rest roster cannot commit as one atomic batch"
			)
	outcome["ready"] = (outcome["blocked"] as Array).is_empty()
	return outcome


func _restore_paid_rest_after_signal_snapshot(gs, character_id: String) -> bool:
	# GameState's own snapshot restore helper is deliberately silent and arms the
	# canonical one-second rest cadence. This closes the narrow stat_changed seam in
	# which ATP was charged but _do_rest had not yet installed its resting record.
	if not gs.has_method("_restore_resting"):
		return false
	gs.call(
		"_restore_resting",
		{
			character_id:
			{
				"pip_seconds": GameState.REST_SECONDS_PER_PIP,
				"remaining_to_tick": 1.0,
			}
		}
	)
	return bool(gs.call("is_resting", character_id))


func _apply_completed_exit_shelter_transaction(announce: bool) -> void:
	_shelter_reached = true
	_shelter_rested = true
	if not _completed_nodes.has("exit_shelter"):
		_completed_nodes.append("exit_shelter")
	var exit_node := _find_node("exit_shelter")
	if not exit_node.is_empty():
		var chain_output_ref := str(exit_node.get("runtime_chain_output_ref", ""))
		if chain_output_ref != "":
			_produced_chain_states[chain_output_ref] = "exit_shelter"
		_apply_generated_section_transition(exit_node, false)
	_cancel_scarcity_drain()
	_disable_exit_shelter_interaction()
	_highlight_node("exit_shelter", true)
	_finalize_generated_stretch_completion(announce)


func _finalize_generated_stretch_completion(announce: bool) -> void:
	var was_complete := _generated_completion_ready()
	_route_phase = "complete"
	_last_outcome = "success"
	_first_shelter_beat_fired = true
	_set_preview_step("generated_stretch_complete")
	_publish_generated_runtime_authority()
	if not announce or was_complete:
		return
	_announce_generated_stretch_complete()


func _announce_generated_stretch_complete() -> void:
	var rest_plan := _exit_shelter_transaction.get("rest_plan", {}) as Dictionary
	var paid_rest := false
	for plan_v in rest_plan.values():
		if plan_v is Dictionary and str((plan_v as Dictionary).get("mode", "")) == "start":
			paid_rest = true
			break
	if paid_rest:
		_show_message("STRETCH COMPLETE — canonical shelter rest has started.", 4.5)
		_show_note("SHELTER SECURED // Recovery now follows the normal timed rest lifecycle.", 5.0)
	else:
		# `paid_rest` reads the rest plan and nothing else, so this can only speak about the rest
		# charge. Scarcity drains ATP on its own schedule and is counted nowhere near here -- claiming
		# no ATP was spent contradicts a meter the player just watched fall.
		_show_message("STRETCH COMPLETE — the party reached shelter with nobody needing rest.", 4.5)
		_show_note("SHELTER SECURED // No recovery was needed; no rest charge was taken.", 5.0)


func _resume_exit_shelter_transaction(announce := false) -> bool:
	if int(_exit_shelter_transaction.get("version", 0)) != EXIT_TRANSACTION_VERSION:
		return false
	var phase := str(_exit_shelter_transaction.get("phase", EXIT_PHASE_AVAILABLE))
	if phase == EXIT_PHASE_COMPLETE:
		_apply_completed_exit_shelter_transaction(announce)
		return true
	if phase != EXIT_PHASE_COMMITTING:
		return false
	var gs = _get_game_state()
	var rest_plan := _exit_shelter_transaction.get("rest_plan", {}) as Dictionary
	if host != null and gs == null:
		return false
	if gs != null:
		var roster: Array = _exit_shelter_transaction.get("roster", [])
		var start_members: Array = []
		for char_id_v in roster:
			var char_id := str(char_id_v)
			var plan := rest_plan.get(char_id, {}) as Dictionary
			if str(plan.get("mode", "")) != "start":
				continue
			var current_atp := float(gs.call("get_stat", char_id, "atp"))
			var atp_before := float(plan.get("atp_before", current_atp))
			var atp_after := float(plan.get("atp_after", atp_before - 1.0))
			if bool(gs.call("is_resting", char_id)):
				if not is_equal_approx(current_atp, atp_after):
					return false
				continue
			if is_equal_approx(current_atp, atp_before):
				start_members.append(char_id)
			elif is_equal_approx(current_atp, atp_after):
				if not _restore_paid_rest_after_signal_snapshot(gs, char_id):
					return false
			else:
				# A committed transaction never guesses whether an unrelated ATP change
				# was payment. Stop rather than charge twice or manufacture a refund.
				return false
		# GameState installs every ATP payment and every rest record before emitting
		# feedback. A signal-time save therefore cannot contain a paid prefix of the
		# roster; the outer EXIT transaction was already durable before this call.
		if not start_members.is_empty():
			if not gs.has_method("command_party_rest") \
					or not bool(gs.call("command_party_rest", start_members)):
				return false
	for item_id_v in _exit_shelter_transaction.get("payload_item_ids", []):
		var item_id := str(item_id_v)
		if item_id != "" and gs != null and "items" in gs \
				and (gs.items as Dictionary).has(item_id):
			_remove_item(item_id)
	for node_id_v in _exit_shelter_transaction.get("payload_node_ids", []):
		var node_id := str(node_id_v)
		if node_id != "" and not _delivered_resource_nodes.has(node_id):
			_delivered_resource_nodes.append(node_id)
	var paid_count := 0
	for plan_v in rest_plan.values():
		if plan_v is Dictionary and str((plan_v as Dictionary).get("mode", "")) == "start":
			paid_count += 1
	if paid_count > 0:
		_rests_taken += 1
	_exit_shelter_transaction["phase"] = EXIT_PHASE_COMPLETE
	_exit_shelter_transaction["completed_tick"] = _sequence_tick()
	_apply_completed_exit_shelter_transaction(announce)
	_rebuild_resource_claim_indexes()
	_publish_generated_runtime_authority()
	return true


func _reconcile_exit_shelter_transaction_after_restore() -> void:
	if _exit_shelter_transaction.is_empty():
		_exit_shelter_transaction = _new_exit_shelter_transaction()
	if int(_exit_shelter_transaction.get("version", 0)) != EXIT_TRANSACTION_VERSION \
			or str(_exit_shelter_transaction.get("phase", "")) not in [
				EXIT_PHASE_AVAILABLE,
				EXIT_PHASE_COMMITTING,
				EXIT_PHASE_COMPLETE,
			]:
		_exit_shelter_transaction = _new_exit_shelter_transaction()
		_shelter_reached = false
		_shelter_rested = false
		return
	var phase := str(_exit_shelter_transaction.get("phase", EXIT_PHASE_AVAILABLE))
	if phase in [EXIT_PHASE_COMMITTING, EXIT_PHASE_COMPLETE]:
		_resume_exit_shelter_transaction(false)


func _reach_exit_shelter() -> bool:
	var exit_phase := str(_exit_shelter_transaction.get("phase", EXIT_PHASE_AVAILABLE))
	if exit_phase in [EXIT_PHASE_COMMITTING, EXIT_PHASE_COMPLETE]:
		return _resume_exit_shelter_transaction(true)
	if not _node_progression_ready("exit_shelter"):
		return false
	if not _all_mandatory_branch_spans_bridged():
		_route_phase = "blocked"
		_last_outcome = "mandatory_branch_span_unresolved"
		_show_message("A downstream break is still open. Work the producer in its side branch.", 2.2)
		_show_note("ROUTE INCOMPLETE // Follow the branch linkage back to its producer.", 3.5)
		return false
	var payload_delivery := _required_payload_delivery()
	if not bool(payload_delivery.get("ready", false)):
		var missing_node := str(payload_delivery.get("node_id", ""))
		_route_phase = "blocked"
		_last_outcome = "payload_delivery_blocked:%s:%s" % [
			missing_node, str(payload_delivery.get("reason", "missing"))
		]
		if missing_node != "":
			_highlight_node(missing_node, true)
		_show_message("A required physical load did not reach shelter in an active carrier's hand.", 2.2)
		_show_note("DELIVERY BLOCKED // Recover the highlighted load before resting.", 3.5)
		return false
	var preflight := _preflight_exit_shelter_transaction(payload_delivery)
	if not bool(preflight.get("ready", false)):
		var blocked: Array = preflight.get("blocked", [])
		var reason := str(blocked[0]) if not blocked.is_empty() else "the shelter outcome was rejected"
		_show_message("Shelter arrival is not complete: %s." % reason, 2.2)
		return false
	_exit_shelter_transaction = {
		"version": EXIT_TRANSACTION_VERSION,
		"phase": EXIT_PHASE_COMMITTING,
		"roster": (preflight.get("roster", []) as Array).duplicate(),
		"rest_plan": (preflight.get("rest_plan", {}) as Dictionary).duplicate(true),
		"payload_node_ids": (preflight.get("payload_node_ids", []) as Array).duplicate(),
		"payload_item_ids": (preflight.get("payload_item_ids", []) as Array).duplicate(),
		"started_tick": _sequence_tick(),
		"completed_tick": -1.0,
	}
	_route_phase = "exit_committing"
	_last_outcome = "exit_shelter_committing"
	# The full roster, exact shelter, payment plan, and payload identities are
	# authoritative before the first command_rest stat signal or payload removal.
	_publish_generated_runtime_authority()
	_disable_exit_shelter_interaction()
	return _resume_exit_shelter_transaction(true)


func _disable_exit_shelter_interaction() -> void:
	var interactable: Node = _node_interactables.get("exit_shelter", null)
	if interactable != null and is_instance_valid(interactable):
		if interactable.has_method("set_interaction_enabled"):
			interactable.call("set_interaction_enabled", false)
		interactable.set("input_ray_pickable", false)
	_set_outline_target_enabled(_node_targets.get("exit_shelter", null), false)


func _rearm_exit_shelter_interaction() -> void:
	var interactable: Node = _node_interactables.get("exit_shelter", null)
	if interactable != null and is_instance_valid(interactable):
		if interactable.has_method("set_interaction_enabled"):
			interactable.call("set_interaction_enabled", true)
		# Generated-node interaction is delegated through the visible outline target.
		interactable.set("input_ray_pickable", false)
	_set_outline_target_enabled(_node_targets.get("exit_shelter", null), true)


## Always-refusing stub. Generated resources are finite physical sources,
## not rewards a caller can request by naming a node and portrait.
func _secure_generated_resource(
	_node: Dictionary, _interaction_actor := ""
) -> bool:
	return false


## The generated node's exact one-shot receipt transfers its already-materialized
## item. It occupies a hand and changes ATP only after explicit endocytosis.
func _secure_generated_resource_from_receipt(
	node: Dictionary, interaction_actor: String, source: Node
) -> bool:
	var node_id := str(node.get("id", ""))
	var source_id := _node_resource_source_id(node_id)
	if _resource_claim_phase(source_id) == RESOURCE_PHASE_CLAIMED:
		return false
	var recipient := interaction_actor
	if source == null or source != _node_interactables.get(node_id, null) \
			or source != _resource_claim_source_interactable(source_id) \
			or str(source.get("active_character")) != recipient \
			or not _generated_interactable_receipt_pending(source, true) \
			or not _generated_actor_ready_at(source, recipient) \
			or recipient == "" or not _active_party.has(recipient):
		return false
	var gs = _get_game_state()
	if gs != null and (
		not ("characters" in gs)
		or not (gs.characters as Dictionary).has(recipient)
	):
		return false
	if gs != null and gs.has_method("has_free_hand") and not bool(gs.call("has_free_hand", recipient)):
		_show_message("%s needs a free hand for this resource." % recipient.capitalize(), 1.5)
		return false
	var claim := _resource_claims.get(source_id, {}) as Dictionary
	if claim.is_empty():
		return false
	var pickup := _begin_resource_claim(
		source_id,
		node_id,
		node_id,
		RESOURCE_KIND_GENERATED,
		recipient,
		str(claim.get("item_type", "")),
		claim.get("properties", {}) as Dictionary,
		bool(claim.get("counts_physical_food", false)),
		source
	)
	if pickup.is_empty():
		_show_message("The resource could not be transferred.", 1.3)
		return false
	_last_outcome = "resource_held:%s:%s" % [node_id, recipient]
	_show_note(
		"HELD BY %s // Click the portrait holding icon to lock this carrier."
		% recipient.to_upper(),
		3.0
	)
	return true


func _reset_generated_resource_items() -> void:
	for item_id in _generated_resource_item_ids:
		_remove_item(item_id)
	_generated_resource_item_ids.clear()
	_generated_resource_item_by_node.clear()
	_resource_claims.clear()


func _restore_party(preserve_atp := false) -> void:
	# A deeper roguelite stretch inherits the authoritative party economy from the
	# preceding stretch. Reset local puzzle state without minting HP, stamina, or ATP;
	# the opening stretch and isolated previews still receive their clean fixture.
	if bool(_config.get("preserve_party_state", false)):
		return
	if not preserve_atp:
		_restore_party_full()
		return
	for char_id in PARTY_IDS:
		_set_character_stat(char_id, "hp", FULL_HP)
		_set_character_stat(char_id, "stamina", FULL_STAMINA)
		_set_character_visible(char_id, true)
		_set_character_status(char_id, "")


func _restore_party_full() -> void:
	for char_id in PARTY_IDS:
		_set_character_stat(char_id, "hp", FULL_HP)
		_set_character_stat(char_id, "stamina", FULL_STAMINA)
		_set_character_stat(char_id, "atp", GameState.ATP_MAX_PIPS)
		_set_character_visible(char_id, true)
		_set_character_status(char_id, "")


func _shelter_rest_members() -> Array[String]:
	var members: Array[String] = []
	var source: Array = _active_party if not _active_party.is_empty() else PARTY_IDS
	for char_id_variant in source:
		var char_id := str(char_id_variant)
		if char_id != "" and not members.has(char_id):
			members.append(char_id)
	return members


func _stop_generated_party_rest() -> void:
	var gs = _get_game_state()
	if gs == null or not gs.has_method("is_resting") or not gs.has_method("command_stop_rest"):
		return
	for char_id in _shelter_rest_members():
		if bool(gs.call("is_resting", char_id)):
			gs.call("command_stop_rest", char_id)


func _reset_generated_party_positions() -> void:
	var spawns := get_spawn_positions()
	for char_id in _shelter_rest_members():
		if not spawns.has(char_id):
			continue
		var spawn: Vector3 = spawns[char_id]
		# Replay setup is often invoked on an already-restored construction
		# snapshot. Do not record fake teleport commands for characters that are
		# already at their exact authored starts; the recorded run should begin
		# with the player's first ordinary movement.
		if not _get_character_position(char_id).is_equal_approx(spawn):
			_set_character_position(char_id, spawn)


func _highlight_node(node_id: String, selected: bool) -> void:
	var marker: MeshInstance3D = _node_markers.get(node_id, null)
	if marker == null:
		return
	var node := _find_node(node_id)
	var role_color := _role_color(str(node.get("role", "")))
	var actionable := _runtime_handler_for_node(node) != ""
	if selected:
		marker.material_override = _make_material(
			role_color.lightened(0.26), role_color.lightened(0.48), 0.55
		)
	elif actionable:
		marker.material_override = _make_material(
			role_color.lightened(0.04), role_color.lightened(0.18), 0.34
		)
	else:
		marker.material_override = _make_material(
			role_color.darkened(0.42), role_color.darkened(0.36), 0.035
		)
	var focus_light: OmniLight3D = _node_focus_lights.get(node_id, null)
	if focus_light != null and is_instance_valid(focus_light):
		var hierarchy := _visual_hierarchy()
		var active_energy := float(hierarchy.get("interactive_light_energy", 1.05))
		var resting_energy := (
			float(hierarchy.get("completed_light_energy", 0.22))
			if _completed_nodes.has(node_id)
			else active_energy * 0.55
		)
		focus_light.light_energy = active_energy if selected else resting_energy


func _full_party_state() -> Dictionary:
	return {
		"aster":
		{"hp": FULL_HP, "stamina": FULL_STAMINA, "atp": GameState.ATP_MAX_PIPS, "visible": true},
		"peris":
		{"hp": FULL_HP, "stamina": FULL_STAMINA, "atp": GameState.ATP_MAX_PIPS, "visible": true},
		"endo":
		{"hp": FULL_HP, "stamina": FULL_STAMINA, "atp": GameState.ATP_MAX_PIPS, "visible": true},
	}


func _nodes() -> Array:
	_ensure_spec_loaded()
	return _spec.get("nodes", [])


func _routes() -> Array:
	_ensure_spec_loaded()
	return _spec.get("routes", [])


func _find_node(node_id: String) -> Dictionary:
	for node in _nodes():
		if node is Dictionary and str((node as Dictionary).get("id", "")) == node_id:
			return (node as Dictionary).duplicate(true)
	return {}


func _find_route(route_id: String) -> Dictionary:
	for route in _routes():
		if route is Dictionary and str((route as Dictionary).get("id", "")) == route_id:
			return (route as Dictionary).duplicate(true)
	return {}


func _anchor_position(anchor_id: String) -> Vector3:
	var anchors: Dictionary = _spec.get("anchors", {})
	if anchors.has(anchor_id):
		return _vec3(anchors[anchor_id], Vector3.ZERO)
	return _node_position(anchor_id)


func _node_position(node_id: String) -> Vector3:
	var node := _find_node(node_id)
	if not node.is_empty():
		return _vec3(node.get("position", []), Vector3.ZERO)
	var anchors: Dictionary = _spec.get("anchors", {})
	if anchors.has(node_id):
		var anchor := _vec3(anchors[node_id], Vector3.ZERO)
		return Vector3(anchor.x, 0.0, anchor.z)
	return Vector3.INF


func _vec3(raw: Variant, fallback: Vector3) -> Vector3:
	if raw is Vector3:
		return raw as Vector3
	if raw is Array and (raw as Array).size() >= 3:
		return Vector3(float((raw as Array)[0]), float((raw as Array)[1]), float((raw as Array)[2]))
	return fallback


func _color_from_array(raw: Variant, fallback: Color) -> Color:
	if raw is Color:
		return raw as Color
	if raw is Array and (raw as Array).size() >= 3:
		return Color(
			float((raw as Array)[0]),
			float((raw as Array)[1]),
			float((raw as Array)[2]),
			float((raw as Array)[3]) if (raw as Array).size() >= 4 else 1.0
		)
	return fallback


func _vec3_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _node_pad_size(role: String) -> Vector3:
	match role:
		"entry", "boundary":
			return Vector3(4.2, 0.12, 3.4)
		"shelter", "shelter_arrival":
			return Vector3(6.6, 0.14, 4.8)
		"pressure", "route_pressure", "danger":
			return Vector3(4.8, 0.12, 2.6)
		"shortcut":
			return Vector3(3.6, 0.12, 3.6)
		"foraging":
			return Vector3(4.8, 0.12, 3.8)
		"guidance":
			return Vector3(4.2, 0.12, 3.4)
		"setpiece":
			return Vector3(5.8, 0.12, 4.4)
		_:
			return Vector3(3.4, 0.12, 2.8)


func _role_color(role: String) -> Color:
	match role:
		"entry":
			return Color(0.18, 0.28, 0.34)
		"boundary":
			return Color(0.16, 0.22, 0.2)
		"resource", "foraging":
			return Color(0.18, 0.32, 0.2)
		"guidance":
			return Color(0.16, 0.25, 0.36)
		"pressure", "route_pressure", "danger":
			return Color(0.38, 0.16, 0.12)
		"shortcut":
			return Color(0.28, 0.22, 0.38)
		"setpiece":
			return Color(0.34, 0.26, 0.15)
		"shelter", "shelter_arrival":
			return Color(0.34, 0.27, 0.16)
		_:
			return Color(0.2, 0.22, 0.24)


func _route_color(route: Dictionary) -> Color:
	var kind := _route_kind(route)
	match kind:
		"risky":
			return Color(0.72, 0.24, 0.14)
		"safe":
			return Color(0.24, 0.48, 0.42)
		"shortcut":
			return Color(0.48, 0.36, 0.68)
		_:
			return Color(0.28, 0.34, 0.38)


func _route_kind(route: Dictionary) -> String:
	var kind := str(route.get("kind", ""))
	if kind != "":
		return kind
	return str(route.get("risk", "safe"))


func _route_risk_value(route: Dictionary) -> int:
	var raw: Variant = route.get("risk", route.get("kind", 0))
	if raw is int or raw is float:
		return int(raw)
	match str(raw):
		"risky":
			return 2
		"danger":
			return 2
		"safe":
			return 0
		"shortcut":
			return 0
		_:
			return 0


func _content_color(category: String, support: String) -> Color:
	if support != "implemented":
		return Color(0.46, 0.48, 0.5)
	match category:
		"flora":
			return Color(0.24, 0.56, 0.34)
		"enemies":
			return Color(0.68, 0.28, 0.18)
		"structures":
			return Color(0.36, 0.42, 0.52)
		_:
			return Color(0.5, 0.5, 0.5)


func _string_array(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw is Array:
		for value in raw:
			result.append(str(value))
	return result
