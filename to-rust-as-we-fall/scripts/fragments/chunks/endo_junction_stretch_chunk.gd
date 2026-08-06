extends "res://scripts/scene_chunks/scene_chunk.gd"

const LevelDecoratorScript := preload("res://scripts/generation/level_decorator.gd")
const HazardFieldScript := preload("res://scripts/game/objects/hazard_field.gd")
const PartyGateScript := preload("res://scripts/game/objects/party_gate_3d.gd")
const ReturnGrateMesh := preload("res://resources/models/channels/endo_return_grate/endo_return_grate.obj")

const WORLD_SLOT := {
	"slot_id": "act1_endo_junction_to_shelter_1",
	"act": 1,
	"region": "Channels / Endo's Junction",
	"entry_shelter_id": "endo_junction",
	"exit_shelter_id": "shelter_1",
	"entry_anchor": "endo_junction_work_area",
	"exit_anchor": "shelter_1_hearth",
	"canonical_party": ["aster", "peris", "endo"],
	"preview_party_preset": "full_party_full_health",
	"next_slot": "act1_channels_first_spiral",
}

const FLOOR_CENTER := Vector3(47.0, -0.05, 0.0)
const FLOOR_SIZE := Vector3(98.0, 0.1, 36.0)
const JUNCTION_POS := Vector3(7.0, 0.45, 0.0)
const WALL_MARKS_POS := Vector3(15.0, 0.45, -4.8)
const GUIDE_MARK_POS := Vector3(23.0, 0.45, -4.2)
const FORAGE_CACHE_POS := Vector3(31.0, 0.45, 5.5)
const SAFE_LEDGE_POS := Vector3(35.0, 0.45, -5.2)
const SAFE_LEDGE_END := Vector3(53.0, 0.5, -5.2)
const SAFE_LEDGE_CENTER := Vector3(44.0, 0.45, -5.2)
const RISKY_BLOOM_POS := Vector3(35.0, 0.45, 5.6)
const RISKY_BLOOM_END := Vector3(53.0, 0.5, 5.6)
const RISKY_BLOOM_CENTER := Vector3(44.0, 0.45, 5.6)
const HIDE_SLOT_POS := Vector3(56.5, 0.45, -5.0)
const SHORTCUT_LOCK_POS := Vector3(64.0, 0.45, -7.0)
const SHORTCUT_GATE_POS := Vector3(64.0, 0.0, -9.25)
const SHELTER_APPROACH_POS := Vector3(74.0, 0.45, 0.0)
const SHELTER_POS := Vector3(86.0, 0.45, 0.0)

const PARTY_IDS := ["aster", "peris", "endo"]
const INTERACT_RADIUS := 2.6
const INTERACTION_POSITION_TOLERANCE := 0.15
const SHELTER_RADIUS := 3.2
const SHELTER_ATP_COST := 1.0
const SAFE_TRAVERSAL_SPEED := 2.6
const DIRECT_TRAVERSAL_SPEED := 3.25
const DIRECT_BLOOM_DAMAGE_PER_TICK := 4.0
const DIRECT_BLOOM_TICK_INTERVAL := 1.0
const DIRECT_BLOOM_TAG := "endo_junction_direct_bloom"
const SAFE_TRAVERSAL_ID := &"endo_junction_safe_ledge"
const DIRECT_TRAVERSAL_ID := &"endo_junction_direct_bloom"
const SHORTCUT_GATE_AUTHORITY_ID := "endo_junction_return_grate"
const SHORTCUT_OPENING_DURATION := 1.4
const ENDO_AUTHORITY_VERSION := 3
const SHELTER_REST_PHASES := ["ready", "committing", "rested"]
const CACHE_PHASE_AVAILABLE := "available"
const CACHE_PHASE_CLAIMING := "claiming"
const CACHE_PHASE_CLAIMED := "claimed"
const CACHE_PHASES := [CACHE_PHASE_AVAILABLE, CACHE_PHASE_CLAIMING, CACHE_PHASE_CLAIMED]
const CACHE_ITEM_TYPE := "lysate"
const VALID_ROUTE_PHASES := [
	"junction", "junction_read", "safe_marked", "foraged",
	"safe_crossing", "direct_crossing", "safe_route", "direct_route",
	"shelter_approach", "complete",
]

const SPAWNS := {
	"aster": Vector3(4.8, 0.0, 1.6),
	"peris": Vector3(3.1, 0.0, -0.2),
	"endo": Vector3(3.7, 0.0, -2.4),
}

var _junction_interactable
var _route_interactable
var _cache_interactable
var _safe_interactable
var _direct_interactable
var _shortcut_interactable
var _shelter_interactable
var _entry_guide: Node3D
var _direct_bloom_field
var _shortcut_gate: PartyGate3D
var _shortcut_grate_mesh: MeshInstance3D

var _junction_material: StandardMaterial3D
var _safe_material: StandardMaterial3D
var _direct_material: StandardMaterial3D
var _cache_material: StandardMaterial3D
var _shortcut_material: StandardMaterial3D
var _shelter_material: StandardMaterial3D

var _junction_read := false
var _safe_route_marked := false
var _forage_collected := false
var _danger_resolved := false
var _shortcut_unlocked := false
var _shelter_reached := false
var _shelter_rested := false
var _first_night_beat_fired := false
var _first_night_beat_count := 0
var _route_choice := ""
var _route_phase := "junction"
var _last_outcome := ""
var _direct_damage_total := 0.0
var _segments_completed: Array[String] = []
var _cache_item_id := ""
var _cache_phase := CACHE_PHASE_AVAILABLE
var _cache_claimed_by := ""
var _cache_claim_serial := 0
var _crossing_actor := ""
var _crossing_deadline := -1.0
var _shelter_rest_phase := "ready"
var _shelter_rest_commit_tick := -1.0
var _shelter_rest_commit_day := 0
var _shelter_rest_before_atp: Dictionary = {}
var _endo_authority_initialized := false
var _restoring_endo_authority := false
var _endo_authority_baseline: Dictionary = {}
var _traversal_signal_game_state = null

func _build_chunk() -> void:
	_build_shell()
	_build_junction()
	_build_route_marks()
	_build_forage_cache()
	_build_crossing()
	_build_hide_and_shortcut()
	_build_shelter()
	LevelDecoratorScript.decorate_profile(self, "endo_stretch", {
		"x1": FLOOR_CENTER.x + FLOOR_SIZE.x * 0.5,
		"width": FLOOR_SIZE.z,
		"spacing": 13.0,
		"floor_tint": Color(0.22, 0.29, 0.31),
		"floor_emission_energy": 0.34,
		"signs": ["ENDO'S JUNCTION", "SAFE LEDGE", "SHORT BLOOM", "SHELTER 1  >"],
	})
	_initialize_endo_authority()
	_normalize_endo_source_receipt_registry()
	_bind_traversal_signals()
	_apply_interactable_truth()
	_update_visual_state()
	_set_preview_step(_step_for_route_phase())

func _process(delta: float) -> void:
	_update_stretch(delta)

func headless_process(delta: float) -> void:
	_update_stretch(delta)

func get_scene_title() -> String:
	return "Endo's Junction to Shelter 1"

func get_scene_help() -> String:
	return "Read Endo's junction to reveal the maintenance ledge, or physically cross the shorter rust bloom and let its visible cadence decide who is hurt. The starch cache and return grate are optional; bring the conscious party to Shelter 1 to rest."

func get_default_character() -> String:
	return "endo"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)


## The authored walk graph agrees with the visible fork: the central rust mass is not traversable,
## so the party must use either the northern ledge or the southern bloom lane. The return channel is
## a side loop; its one-cell throat is owned by PartyGate3D and never gates forward shelter progress.
func get_grid_data() -> Dictionary:
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [-3.0, 0.0, -18.0],
		"cell_size": 1.0,
		"width": 102,
		"height": 36,
		"walkable_regions": [
			{"min": [-1.0, -8.0], "max": [35.9, 7.9]},
			{"min": [34.0, -6.9], "max": [53.9, -3.4]},
			{"min": [34.0, 3.4], "max": [53.9, 7.9]},
			{"min": [52.0, -8.0], "max": [96.0, 7.9]},
			{"min": [28.0, -13.2], "max": [65.9, -10.2]},
			{"min": [28.0, -13.2], "max": [32.9, -7.1]},
			{"min": [61.8, -10.8], "max": [66.1, -7.1]},
		],
		"risk_regions": [
			{
				"min": [36.0, RISKY_BLOOM_CENTER.z - 1.75],
				"max": [52.0, RISKY_BLOOM_CENTER.z + 1.75],
				"penalty": 28.0,
				"recoverable": true,
			},
		],
	}


## The preview host installs GridWorld after the chunk enters the tree. Re-running setup is safe:
## PartyGate3D first retracts its old derived blockers, then rebuilds them from saved phase truth.
func on_game_state_grid_ready() -> void:
	_setup_shortcut_gate()

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors.merge({
		"junction": JUNCTION_POS,
		"wall_marks": WALL_MARKS_POS,
		"guide_mark": GUIDE_MARK_POS,
		"forage_cache": FORAGE_CACHE_POS,
		"safe_ledge": SAFE_LEDGE_POS,
		"risky_bloom": RISKY_BLOOM_POS,
		"hide_slot": HIDE_SLOT_POS,
		"shortcut_lock": SHORTCUT_LOCK_POS,
		"shelter_approach": SHELTER_APPROACH_POS,
		"shelter": SHELTER_POS,
	}, true)
	return anchors

func get_world_slot() -> Dictionary:
	return WORLD_SLOT.duplicate(true)

func get_preview_time_state() -> Dictionary:
	return {
		"day": 1,
		"time": 0.58,
		"routing_mode": "safe",
		"note_default": "This slice is world-slotted as the route from Endo's maintained junction into Shelter 1, but the preview boots with Aster, Peris, and Endo fully restored so the level can be tuned in isolation.",
	}

## Keep the first-night story state, but establish a Web-readable moonlight floor. The host
## applies this after its shared day/night curve, including on subsequent clock updates.
func get_preview_lighting_profile() -> Dictionary:
	return {
		"ambient_energy_floor": 0.62,
		"directional_energy_floor": 0.5,
		"glow_intensity_floor": 0.34,
		"ambient_color": Color(0.28, 0.36, 0.46),
		"directional_color": Color(0.46, 0.58, 0.78),
		"color_mix": 0.72,
	}

func get_preview_ui_defaults() -> Dictionary:
	return {
		"instructions_visible": false,
		"overlay_collapsed": true,
	}

func get_preview_state() -> Dictionary:
	var crossing := _current_crossing_state()
	var gate_state: Dictionary = _shortcut_gate.get_authority_state() \
		if _shortcut_gate != null else {}
	return {
		"world_slot": get_world_slot(),
		"route_phase": _route_phase,
		"route_choice": _route_choice,
		"last_outcome": _last_outcome,
		"junction_read": _junction_read,
		"safe_route_marked": _safe_route_marked,
		"forage_collected": _forage_collected,
		"cache_item": _cache_item_id,
		"cache_phase": _cache_phase,
		"cache_claimed_by": _cache_claimed_by,
		"cache_claim_serial": _cache_claim_serial,
		"cache_item_at_source": _endo_cache_item_at_source(),
		"cache_item_holder": _endo_cache_item_holder(),
		"danger_resolved": _danger_resolved,
		"shortcut_unlocked": _shortcut_unlocked,
		"shelter_reached": _shelter_reached,
		"shelter_rested": _shelter_rested,
		"shelter_rest_phase": _shelter_rest_phase,
		"first_night_beat_fired": _first_night_beat_fired,
		"first_night_beat_count": _first_night_beat_count,
		"direct_damage_total": _direct_damage_total,
		"crossing_actor": _crossing_actor,
		"crossing_active": not crossing.is_empty(),
		"crossing_progress": float(crossing.get("progress", 1.0 if _danger_resolved else 0.0)),
		"crossing_deadline": _crossing_deadline,
		"bloom_field": _direct_bloom_field.get_state() \
			if _direct_bloom_field != null else {},
		"shortcut_phase": str(gate_state.get("phase", PartyGate3D.PHASE_CLOSED)),
		"party_min_hp": _party_min_hp(),
		"segments_completed": _segments_completed.duplicate(),
		"stretch": {
			"boundary": "Endo's exterior junction work area to Shelter 1",
			"difficulty_target": "first main-level shelter stretch",
			"enemy_density": "low; one route-pressure bloom instead of a full chase",
			"foraging": "one Endo-readable starch cache",
			"food_cost": 1,
			"shelter_quality": "warm first-night refuge",
			"shortcut": "optional physically blocked return channel after the crossing",
		},
	}

func get_preview_overlay_status(overlay_id: String, _current_tick: float) -> Array:
	match overlay_id:
		"aster":
			return [
				"DATA: Endo's wall marks align with one usable maintenance ledge.",
				"Route: %s" % ("marked" if _safe_route_marked else "unresolved"),
				"Choice: %s" % (_route_choice if _route_choice != "" else _get_routing_mode()),
			]
		"peris":
			return [
				"FOG: the refuge feels lived-in, not abandoned.",
				"Plant memory: %s" % ("settling inside Shelter 1" if _shelter_reached else "pulling toward the warm room"),
				"Food cache: %s" % ("collected" if _forage_collected else "still tucked in the wall"),
			]
		"endo":
			return [
				"SURVIVAL: read for the ledge, or pay health through the bloom.",
				"Shortcut: %s" % ("open" if _shortcut_unlocked else "locked"),
				"Next: %s" % _current_instruction(),
			]
		_:
			return []

func reset_preview_state() -> void:
	_cancel_owned_crossing(&"endo_junction_reset")
	_cancel_endo_shelter_rest_callback()
	_reset_endo_cache_to_source()
	_junction_read = false
	_safe_route_marked = false
	_forage_collected = false
	_danger_resolved = false
	_shortcut_unlocked = false
	_shelter_reached = false
	_shelter_rested = false
	_shelter_rest_phase = "ready"
	_clear_endo_shelter_rest_context()
	_first_night_beat_fired = false
	_first_night_beat_count = 0
	_route_choice = ""
	_route_phase = "junction"
	_last_outcome = ""
	_direct_damage_total = 0.0
	_segments_completed.clear()
	_crossing_actor = ""
	_crossing_deadline = -1.0
	_reset_shortcut_gate_authority()
	if _direct_bloom_field != null:
		# A reset is a new authored attempt. Force a fresh cadence even when the previous attempt
		# happened to leave the field active, so no opaque callback from that attempt survives.
		_direct_bloom_field.set_active(false)
		_direct_bloom_field.set_active(true)
	_set_preview_step("endo_junction_stretch_start")
	_reset_story_interactables()
	_apply_interactable_truth()
	_update_visual_state()
	_publish_endo_authority()

func on_preview_routing_changed(mode: String) -> void:
	if mode == "direct":
		_show_note("Direct routing cuts through the hot bloom. It is shorter and recoverable, but the party pays HP before shelter rest.", 2.8)
	else:
		_show_note("Safe routing follows Endo's maintenance marks and preserves health for the first-night shelter beat.", 2.8)

func read_junction(source: Node = null) -> bool:
	if not _endo_control_receipt_pending(source, "junction"):
		return false
	_junction_read = true
	if _route_phase == "junction":
		_route_phase = "junction_read"
	_mark_segment("junction_read")
	_set_preview_step("endo_junction_read")
	_clear_dialogue()
	_show_message("Endo's wall marks reveal a maintained ledge around the bloom.", 2.4)
	_complete_interactable(_junction_interactable)
	_apply_interactable_truth()
	_update_visual_state()
	_publish_endo_authority()
	return true

func mark_safe_route(source: Node = null) -> bool:
	if not _endo_control_receipt_pending(source, "route"):
		return false
	_safe_route_marked = true
	if _route_phase not in ["safe_crossing", "direct_crossing", "safe_route", "direct_route",
			"shelter_approach", "complete"]:
		_route_phase = "safe_marked"
	_mark_segment("route_marked")
	_set_preview_step("endo_junction_route_marked")
	_show_message("Aster maps the ledge route to Shelter 1.", 1.5)
	_complete_interactable(_route_interactable)
	_update_visual_state()
	_publish_endo_authority()
	return true

func collect_forage(source: Node = null) -> bool:
	if not _endo_control_receipt_pending(source, "cache"):
		return false
	var actor := str(source.get("active_character"))
	var gs = _get_game_state()
	if gs == null:
		return false

	# Reserve this exact, already-visible source item and actor before GameState emits its synchronous
	# pickup signal. A signal-time save therefore sees CLAIMING rather than an unowned checklist bit.
	_cache_phase = CACHE_PHASE_CLAIMING
	_cache_claimed_by = actor
	_cache_claim_serial += 1
	_apply_interactable_truth()
	_publish_endo_authority()
	if not _pick_up_item(actor, _cache_item_id):
		_cache_phase = CACHE_PHASE_AVAILABLE
		_cache_claimed_by = ""
		_rearm_endo_control(source)
		_apply_interactable_truth()
		_publish_endo_authority()
		return false
	_complete_endo_cache_claim(true)
	return true


func _complete_endo_cache_claim(show_story := false) -> void:
	_cache_phase = CACHE_PHASE_CLAIMED
	_forage_collected = true
	if _route_phase not in ["safe_crossing", "direct_crossing", "safe_route", "direct_route",
			"shelter_approach", "complete"]:
		_route_phase = "foraged"
	_mark_segment("forage")
	_set_preview_step("endo_junction_forage")
	if show_story:
		_say_key("endo_stretch.forage.peris")
	_complete_interactable(_cache_interactable)
	_update_visual_state()
	_apply_interactable_truth()
	_publish_endo_authority()

func commit_safe_route(source: Node = null) -> bool:
	if not _endo_control_receipt_pending(source, "safe"):
		return false
	var actor := str(source.get("active_character"))
	if not _begin_route_traversal(
		"safe", actor, SAFE_TRAVERSAL_ID, SAFE_LEDGE_END, SAFE_TRAVERSAL_SPEED
	):
		_show_message("Endo cannot enter the ledge traversal yet.", 1.2)
		_rearm_endo_control(source)
		return false
	_show_message("Endo commits to the maintenance ledge; the crossing completes only at its far lip.", 1.9)
	_complete_interactable(_safe_interactable)
	_complete_interactable(_direct_interactable)
	_update_visual_state()
	return true

func commit_direct_route(source: Node = null) -> bool:
	if not _endo_control_receipt_pending(source, "direct"):
		return false
	var actor := str(source.get("active_character"))
	if not _begin_route_traversal(
		"direct", actor, DIRECT_TRAVERSAL_ID, RISKY_BLOOM_END, DIRECT_TRAVERSAL_SPEED
	):
		_show_message("That character cannot enter the bloom traversal yet.", 1.2)
		_rearm_endo_control(source)
		return false
	_clear_dialogue()
	_say_key("endo_stretch.direct.aster")
	_show_message("%s enters the shorter bloom. Its pulse hurts only bodies actually inside it." \
		% _display_name(actor), 2.0)
	_complete_interactable(_safe_interactable)
	_complete_interactable(_direct_interactable)
	_update_visual_state()
	return true

func unlock_shortcut(source: Node = null) -> bool:
	if not _endo_control_receipt_pending(source, "shortcut"):
		return false
	if _shortcut_gate == null or not _shortcut_gate.begin_open():
		_show_message("The return grate needs Endo at its latch before it can move.", 1.4)
		_rearm_endo_control(source)
		return false
	_last_outcome = "shortcut_opening"
	_show_message("Endo releases the grate. Its blocked throat stays solid until the lift finishes.", 1.8)
	_complete_interactable(_shortcut_interactable)
	_update_visual_state()
	_publish_endo_authority()
	return true

func reach_shelter(source: Node = null) -> bool:
	if not _endo_control_receipt_pending(source, "shelter"):
		return false
	_sync_host_clock_to_game_state()
	var preflight := _preflight_endo_shelter_rest()
	var blocked := preflight.get("blocked", []) as Array
	if not blocked.is_empty():
		_show_message(str(blocked[0]), 1.7)
		_rearm_endo_control(source)
		return false
	var gs = _get_game_state()
	if gs == null:
		_rearm_endo_control(source)
		return false

	# Publish the enclosing transaction before GameState emits any batch-rest feedback. A snapshot
	# taken by the first ATP signal can therefore prove either the complete atomic effect or the
	# exact pre-command intent, without replaying one member's payment.
	_shelter_rest_phase = "committing"
	_shelter_rest_commit_tick = _get_scheduler_tick()
	_shelter_rest_commit_day = gs.get_game_day()
	_shelter_rest_before_atp = (
		preflight.get("before_atp", {}) as Dictionary).duplicate(true)
	_apply_interactable_truth()
	_publish_endo_authority()
	if not bool(gs.command_party_rest(PARTY_IDS)):
		_shelter_rest_phase = "ready"
		_clear_endo_shelter_rest_context()
		_rearm_endo_control(source)
		_apply_interactable_truth()
		_publish_endo_authority()
		_show_message("The party cannot settle into the shelter yet.", 1.5)
		return false
	_complete_endo_shelter_rest(true)
	return true


func _complete_endo_shelter_rest(show_story := false) -> void:
	if _shelter_rest_phase == "rested":
		return
	_cancel_endo_shelter_rest_callback()
	_shelter_rest_phase = "rested"
	_shelter_reached = true
	_shelter_rested = true
	_route_phase = "complete"
	_last_outcome = "shelter_rested"
	_mark_segment("shelter")
	_set_preview_step("endo_junction_shelter_1")
	if show_story:
		_fire_first_night_beat()
	_complete_interactable(_shelter_interactable)
	_clear_endo_shelter_rest_context()
	_update_visual_state()
	_apply_interactable_truth()
	_publish_endo_authority()

func rest_shelter(source: Node = null) -> bool:
	return reach_shelter(source)

func _build_shell() -> void:
	# The first-night palette still needs a readable physical surface when the compatibility
	# renderer (or the `fog off` diagnostic) bypasses the fullscreen perception pass. A low,
	# cool emission is applied by the final decoration material above so the textured deck remains.
	var route_floor := _add_floor(self, FLOOR_CENTER, FLOOR_SIZE, Color(0.12, 0.145, 0.165))
	route_floor.name = "EndoJunctionRouteFloor"
	_add_box(self, Vector3(17.0, 0.02, 0.0), Vector3(36.0, 0.035, 16.0),
		Color(0.105, 0.135, 0.15), Color(0.12, 0.28, 0.32), 0.48,
		"EndoJunctionEntryApron")
	var half_x := FLOOR_SIZE.x * 0.5
	var half_z := FLOOR_SIZE.z * 0.5
	_add_box(self, Vector3(FLOOR_CENTER.x, 2.2, -half_z - 0.1), Vector3(FLOOR_SIZE.x, 4.4, 0.3), Color(0.11, 0.13, 0.14))
	_add_box(self, Vector3(FLOOR_CENTER.x, 2.2, half_z + 0.1), Vector3(FLOOR_SIZE.x, 4.4, 0.3), Color(0.11, 0.13, 0.14))
	_add_box(self, Vector3(FLOOR_CENTER.x - half_x - 0.1, 2.2, 0.0), Vector3(0.3, 4.4, FLOOR_SIZE.z), Color(0.09, 0.11, 0.12))
	_add_box(self, Vector3(FLOOR_CENTER.x + half_x + 0.1, 2.2, 0.0), Vector3(0.3, 4.4, FLOOR_SIZE.z), Color(0.09, 0.11, 0.12))
	for i in range(8):
		var blend := float(i) / 7.0
		var light_x := lerpf(JUNCTION_POS.x, SHELTER_POS.x, blend)
		_add_light(self, Vector3(light_x, 3.8, -1.0 + sin(float(i) * 1.7) * 1.4), Color(0.38 + blend * 0.2, 0.48 + blend * 0.1, 0.56 - blend * 0.08), 1.1 + blend * 0.65, 14.0)
	_add_label(self, "ENDO'S JUNCTION", JUNCTION_POS + Vector3(2.6, 2.7, -4.0), Color(0.68, 0.9, 0.74))
	_add_label(self, "SHELTER 1", SHELTER_POS + Vector3(0.0, 2.85, 0.0), Color(0.98, 0.82, 0.52))

func _build_junction() -> void:
	_junction_material = _make_material(Color(0.14, 0.16, 0.15), Color(0.52, 0.92, 0.66), 1.3)
	_add_box(self, JUNCTION_POS + Vector3(0.0, -0.02, 0.0), Vector3(9.0, 0.2, 8.0),
		Color(0.12, 0.16, 0.145), Color(0.24, 0.58, 0.36), 0.36,
		"EndoJunctionConsolePad")
	var station := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.45
	mesh.bottom_radius = 0.62
	mesh.height = 1.8
	station.mesh = mesh
	station.material_override = _junction_material
	station.position = JUNCTION_POS + Vector3(0.0, 0.9, 0.0)
	add_child(station)
	_build_entry_guide()
	_junction_interactable = _add_object_interactable(self, "EndoJunctionReadInteractable", "Endo's Junction Console", JUNCTION_POS, "ENDO: READ CONSOLE", [station], "endo", 0.0, true, INTERACT_RADIUS, Interactable.InteractableType.INSPECTION)
	_configure_endo_control(_junction_interactable, "junction", read_junction)

func _build_entry_guide() -> void:
	_entry_guide = Node3D.new()
	_entry_guide.name = "EndoJunctionEntryGuide"
	add_child(_entry_guide)
	var start: Vector3 = SPAWNS["endo"]
	var finish := Vector3(JUNCTION_POS.x, 0.04, JUNCTION_POS.z)
	start.y = 0.04
	for i in range(5):
		var t := float(i + 1) / 6.0
		var guide_pos := start.lerp(finish, t)
		_add_box(_entry_guide, guide_pos, Vector3(0.42, 0.04, 0.42),
			Color(0.08, 0.18, 0.12), Color(0.38, 1.0, 0.62), 1.45,
			"EndoJunctionEntryGuideDot%d" % i)
	for offset in [Vector3(1.05, 0.04, 0.0), Vector3(-1.05, 0.04, 0.0),
			Vector3(0.0, 0.04, 1.05), Vector3(0.0, 0.04, -1.05)]:
		_add_box(_entry_guide, JUNCTION_POS + offset, Vector3(0.5, 0.05, 0.5),
			Color(0.08, 0.18, 0.12), Color(0.38, 1.0, 0.62), 1.6)
	var guide_label := _add_label(_entry_guide, "ENDO: READ\nJUNCTION CONSOLE",
		JUNCTION_POS + Vector3(0.0, 2.45, 1.3), Color(0.7, 1.0, 0.78))
	guide_label.no_depth_test = true
	guide_label.render_priority = 2

func _build_route_marks() -> void:
	_add_box(self, WALL_MARKS_POS + Vector3(0.0, 0.5, -0.4), Vector3(8.5, 1.0, 0.18), Color(0.14, 0.16, 0.16), Color(0.44, 0.68, 0.58), 0.12)
	_add_label(self, "WALL MARKS", WALL_MARKS_POS + Vector3(0.0, 1.65, -0.4), Color(0.66, 0.9, 0.75))
	_route_interactable = _add_interactable(self, "EndoJunctionRouteMarkInteractable", "Translated Route Mark", GUIDE_MARK_POS, "MARK ROUTE", "aster", 3.4, true, INTERACT_RADIUS, Interactable.InteractableType.TIMED_ACTION, false)
	# The wall marks are ~8 units away, beyond auto-outline's reach — give the mark its OWN co-located post so
	# the interactable has a visible object to outline+glow.
	var rmark := _add_box(_route_interactable, Vector3(0.0, 0.5, 0.0), Vector3(0.4, 1.0, 0.4), Color(0.18, 0.3, 0.26), Color(0.44, 0.68, 0.58), 0.5)
	_outline_interactable_child(_route_interactable, rmark, "EndoJunctionRouteMarkInteractable", INTERACT_RADIUS)
	_configure_endo_control(_route_interactable, "route", mark_safe_route)

func _build_forage_cache() -> void:
	_cache_material = _make_material(Color(0.28, 0.22, 0.12), Color(0.9, 0.64, 0.24), 0.32)
	_add_box(self, FORAGE_CACHE_POS + Vector3(0.0, 0.28, 0.0), Vector3(3.4, 0.56, 1.6), Color(0.2, 0.15, 0.09), Color(0.7, 0.42, 0.16), 0.18)
	var cache := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.42
	mesh.height = 0.84
	cache.mesh = mesh
	cache.material_override = _cache_material
	cache.position = FORAGE_CACHE_POS + Vector3(0.0, 0.8, 0.0)
	add_child(cache)
	_add_label(self, "STARCH CACHE", FORAGE_CACHE_POS + Vector3(0.0, 1.85, 0.0), Color(0.96, 0.78, 0.42))
	_cache_interactable = _add_object_interactable(self, "EndoJunctionCacheInteractable", "Wall Cache", FORAGE_CACHE_POS, "RECOVER CACHE", [cache], "", 4.0, true, INTERACT_RADIUS, Interactable.InteractableType.TIMED_ACTION)
	_configure_endo_control(_cache_interactable, "cache", collect_forage)
	_ensure_endo_cache_source_item()

func _build_crossing() -> void:
	_safe_material = _make_material(Color(0.1, 0.16, 0.18), Color(0.52, 0.78, 0.86), 0.18)
	_direct_material = _make_material(Color(0.22, 0.1, 0.07), Color(0.86, 0.28, 0.12), 0.28)
	_add_box(self, SAFE_LEDGE_CENTER + Vector3(0.0, -0.02, 0.0), Vector3(18.0, 0.16, 3.0), Color(0.09, 0.14, 0.16), Color(0.38, 0.64, 0.72), 0.16)
	_add_label(self, "SAFE LEDGE", SAFE_LEDGE_CENTER + Vector3(0.0, 1.65, 0.0), Color(0.64, 0.88, 0.96))
	var safe_beacon := _add_box(self, SAFE_LEDGE_POS + Vector3(0.0, 0.55, 0.0), Vector3(0.55, 1.1, 0.55), Color(0.12, 0.25, 0.27), Color(0.52, 0.78, 0.86), 0.35)
	_safe_interactable = _add_object_interactable(self, "EndoJunctionSafeRouteInteractable", "Safe Ledge", SAFE_LEDGE_POS, "THREAD LEDGE", [safe_beacon], "endo", 4.2, true, INTERACT_RADIUS, Interactable.InteractableType.TIMED_ACTION)
	_configure_endo_control(_safe_interactable, "safe", commit_safe_route)
	_add_box(self, RISKY_BLOOM_CENTER + Vector3(0.0, -0.02, 0.0), Vector3(18.0, 0.16, 3.5), Color(0.18, 0.08, 0.055), Color(0.82, 0.22, 0.08), 0.24)
	_add_label(self, "SHORT BLOOM", RISKY_BLOOM_CENTER + Vector3(0.0, 1.65, 0.0), Color(0.98, 0.56, 0.32))
	var bloom_beacon := _add_box(self, RISKY_BLOOM_POS + Vector3(0.0, 0.55, 0.0), Vector3(0.55, 1.1, 0.55), Color(0.3, 0.1, 0.06), Color(0.92, 0.28, 0.1), 0.5)
	_direct_interactable = _add_object_interactable(self, "EndoJunctionDirectRouteInteractable", "Short Bloom", RISKY_BLOOM_POS, "CUT BLOOM", [bloom_beacon], "", 4.2, true, INTERACT_RADIUS, Interactable.InteractableType.TIMED_ACTION)
	_configure_endo_control(_direct_interactable, "direct", commit_direct_route)
	# The center is visibly and topologically occupied. A route choice is a route, not a label placed
	# on an otherwise open rectangle that can be walked around without engaging its consequence.
	_add_box(self, Vector3(44.0, 0.72, 0.15), Vector3(17.2, 1.44, 5.7),
		Color(0.1, 0.075, 0.065), Color(0.32, 0.12, 0.07), 0.08,
		"EndoJunctionCrossingRustMass")
	for x in [38.0, 41.0, 44.0, 47.0, 50.0]:
		var pulse := _add_box(self, Vector3(float(x), 0.18, RISKY_BLOOM_CENTER.z),
			Vector3(0.7, 0.32, 2.5), Color(0.32, 0.09, 0.045),
			Color(1.0, 0.25, 0.06), 0.65, "EndoJunctionBloomPulse%d" % int(x))
		pulse.material_override = _direct_material
	_build_direct_bloom_field()

func _build_hide_and_shortcut() -> void:
	_add_box(self, HIDE_SLOT_POS + Vector3(0.0, -0.03, 0.0), Vector3(7.0, 0.18, 3.2), Color(0.07, 0.11, 0.1))
	_add_box(self, HIDE_SLOT_POS + Vector3(-3.3, 1.2, 0.0), Vector3(0.25, 2.4, 3.2), Color(0.1, 0.14, 0.12))
	_add_label(self, "HIDE SLOT", HIDE_SLOT_POS + Vector3(0.0, 1.8, 0.0), Color(0.62, 0.88, 0.68))
	# This branch is a literal return channel. Its walls leave one east throat, and that throat is
	# the PartyGate3D blocker below; opening it changes both collision and the host GridWorld.
	_add_box(self, Vector3(46.5, -0.015, -11.7), Vector3(37.0, 0.14, 3.0),
		Color(0.075, 0.1, 0.105), Color(0.15, 0.34, 0.38), 0.16,
		"EndoJunctionReturnChannelFloor")
	_add_box(self, Vector3(46.5, 1.15, -13.35), Vector3(37.0, 2.3, 0.28),
		Color(0.085, 0.11, 0.115), Color.BLACK, 0.0,
		"EndoJunctionReturnChannelOuterWall")
	_add_box(self, Vector3(46.5, 1.15, -10.05), Vector3(31.0, 2.3, 0.28),
		Color(0.085, 0.11, 0.115), Color.BLACK, 0.0,
		"EndoJunctionReturnChannelInnerWall")
	_build_shortcut_gate()
	_add_label(self, "RETURN GRATE", SHORTCUT_LOCK_POS + Vector3(0.0, 1.7, 0.0), Color(0.94, 0.78, 0.46))
	_shortcut_interactable = _add_object_interactable(self, "EndoJunctionShortcutInteractable", "Return Grate", SHORTCUT_LOCK_POS, "OPEN GRATE", [_shortcut_grate_mesh], "endo", 4.0, true, INTERACT_RADIUS, Interactable.InteractableType.TIMED_ACTION)
	_configure_endo_control(_shortcut_interactable, "shortcut", unlock_shortcut)


func _build_direct_bloom_field() -> void:
	var gs = _get_game_state()
	var scheduler = _get_scheduler()
	if gs == null or scheduler == null:
		return
	var had_saved_authority := gs.get_world_state(
		"kit:hazard_field:%s" % DIRECT_BLOOM_TAG, null) is Dictionary
	_direct_bloom_field = HazardFieldScript.new()
	_direct_bloom_field.name = "EndoJunctionDirectBloomField"
	add_child(_direct_bloom_field)
	_direct_bloom_field.setup(
		gs,
		scheduler,
		Vector2(36.0, RISKY_BLOOM_CENTER.z - 1.75),
		Vector2(52.0, RISKY_BLOOM_CENTER.z + 1.75),
		PARTY_IDS,
		{
			"dps_tick": DIRECT_BLOOM_DAMAGE_PER_TICK,
			"interval": DIRECT_BLOOM_TICK_INTERVAL,
			"tag": DIRECT_BLOOM_TAG,
			"on_bite": Callable(self, "_on_direct_bloom_bite"),
			"restore_existing_authority": true,
		}
	)
	if not had_saved_authority:
		_direct_bloom_field.set_active(true)


func _build_shortcut_gate() -> void:
	_shortcut_gate = PartyGateScript.new() as PartyGate3D
	_shortcut_gate.name = "EndoJunctionReturnPartyGate"
	_shortcut_gate.authority_id = SHORTCUT_GATE_AUTHORITY_ID
	_shortcut_gate.required_members = PackedStringArray(["endo"])
	_shortcut_gate.readiness_radius = INTERACT_RADIUS + 0.2
	_shortcut_gate.opening_duration = SHORTCUT_OPENING_DURATION
	_shortcut_gate.navigation_padding = Vector2(0.2, 0.15)
	_shortcut_gate.position = SHORTCUT_GATE_POS

	var markers := Node3D.new()
	markers.name = "Markers"
	_shortcut_gate.add_child(markers)
	var anchor := Marker3D.new()
	anchor.name = "InteractionAnchor"
	anchor.position = SHORTCUT_LOCK_POS - SHORTCUT_GATE_POS
	markers.add_child(anchor)

	var blocker_body := StaticBody3D.new()
	blocker_body.name = "RubbleBlocker"
	_shortcut_gate.add_child(blocker_body)
	var blocker_shape := CollisionShape3D.new()
	blocker_shape.name = "BlockerShape"
	var blocker_box := BoxShape3D.new()
	blocker_box.size = Vector3(4.5, 2.35, 0.72)
	blocker_shape.shape = blocker_box
	blocker_shape.position = Vector3(0.0, 1.175, 0.0)
	blocker_body.add_child(blocker_shape)

	_shortcut_grate_mesh = MeshInstance3D.new()
	_shortcut_grate_mesh.name = "EndoJunctionReturnGrateMesh"
	_shortcut_grate_mesh.mesh = ReturnGrateMesh
	var source_material := ReturnGrateMesh.surface_get_material(0) as StandardMaterial3D
	if source_material != null:
		# Keep the external texture/material authoritative while giving this presenter its own
		# emission state. Mutating the imported resource directly would leak gate feedback between
		# concurrent chunk instances.
		_shortcut_material = source_material.duplicate() as StandardMaterial3D
		_shortcut_material.emission_enabled = true
		_shortcut_material.emission = Color(0.9, 0.76, 0.42)
		_shortcut_material.emission_energy_multiplier = 0.14
		_shortcut_grate_mesh.set_surface_override_material(0, _shortcut_material)
	_shortcut_grate_mesh.position = Vector3.ZERO
	_shortcut_gate.add_child(_shortcut_grate_mesh)
	add_child(_shortcut_gate)
	_shortcut_gate.opened.connect(_on_shortcut_gate_opened)
	_shortcut_gate.blocked.connect(_on_shortcut_gate_blocked)
	_setup_shortcut_gate()


func _setup_shortcut_gate() -> void:
	if _shortcut_gate == null:
		return
	var gs = _get_game_state()
	if gs == null:
		return
	_shortcut_gate.setup(gs, gs.grid, 0, PARTY_IDS)
	_update_visual_state()

func _build_shelter() -> void:
	_shelter_material = _make_material(Color(0.2, 0.17, 0.11), Color(0.98, 0.74, 0.36), 0.3)
	_add_box(self, SHELTER_POS + Vector3(0.0, -0.03, 0.0), Vector3(10.0, 0.22, 8.0), Color(0.12, 0.1, 0.08))
	_add_box(self, SHELTER_POS + Vector3(4.9, 1.8, 0.0), Vector3(0.3, 3.6, 8.0), Color(0.16, 0.13, 0.1))
	_add_box(self, SHELTER_POS + Vector3(0.0, 1.8, -3.9), Vector3(10.0, 3.6, 0.3), Color(0.16, 0.13, 0.1))
	_add_box(self, SHELTER_POS + Vector3(0.0, 3.45, 0.0), Vector3(10.0, 0.16, 8.0), Color(0.09, 0.08, 0.075))
	var hearth := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.42
	mesh.bottom_radius = 0.7
	mesh.height = 0.9
	hearth.mesh = mesh
	hearth.material_override = _shelter_material
	hearth.position = SHELTER_POS + Vector3(0.0, 0.55, 0.0)
	add_child(hearth)
	# A real refuge composition: warm central hearth, two bed platforms, dry stores, a threshold
	# canopy, and wall ribs. These stay clear of the hearth interaction radius.
	_add_box(self, SHELTER_POS + Vector3(-2.8, 0.28, -2.55), Vector3(3.2, 0.5, 1.35), Color(0.24, 0.19, 0.12), Color(0.75, 0.48, 0.2), 0.08)
	_add_box(self, SHELTER_POS + Vector3(-2.8, 0.28, 2.55), Vector3(3.2, 0.5, 1.35), Color(0.24, 0.19, 0.12), Color(0.75, 0.48, 0.2), 0.08)
	_add_box(self, SHELTER_POS + Vector3(2.9, 0.65, -2.6), Vector3(1.45, 1.3, 1.5), Color(0.18, 0.16, 0.12))
	_add_box(self, SHELTER_POS + Vector3(2.9, 1.55, -2.6), Vector3(1.65, 0.18, 1.7), Color(0.34, 0.28, 0.18))
	for rib_z in [-3.55, 3.55]:
		_add_box(self, SHELTER_POS + Vector3(0.0, 2.15, float(rib_z)), Vector3(9.2, 0.18, 0.22), Color(0.42, 0.34, 0.22))
	_add_label(self, "HEARTH // REST", SHELTER_POS + Vector3(0.0, 2.15, 0.0), Color(1.0, 0.82, 0.5))
	_add_light(self, SHELTER_POS + Vector3(0.0, 2.1, 0.0), Color(1.0, 0.74, 0.38), 2.0, 11.5)
	_shelter_interactable = _add_object_interactable(self, "EndoJunctionShelterInteractable", "Shelter 1 Hearth", SHELTER_POS, "REST PARTY", [hearth], "", 3.0, true, SHELTER_RADIUS, Interactable.InteractableType.TIMED_ACTION)
	_configure_endo_control(_shelter_interactable, "shelter", reach_shelter)
	# The hearth room is a SHELTER: register the sanctuary region the detection/strike gates and
	# the revive watch read (a shelter that is only a room lets enemies attack you inside it —
	# the 2026-07-12 report). Sized to the built room slab (10 x 8 around SHELTER_POS).
	var gs = _get_game_state()
	if gs != null and gs.has_method("add_shelter_region"):
		gs.add_shelter_region(Vector2(SHELTER_POS.x - 5.0, SHELTER_POS.z - 4.0),
			Vector2(SHELTER_POS.x + 5.0, SHELTER_POS.z + 4.0))

func _update_stretch(_delta: float) -> void:
	# Traversal and gate signals own semantic completion. Render/headless calls are presentation
	# projections only and can never convert a teleported body or presenter pose into route truth.
	_update_visual_state()


func _begin_route_traversal(
		choice: String,
		actor: String,
		traversal_id: StringName,
		destination: Vector3,
		speed: float
	) -> bool:
	var gs = _get_game_state()
	if gs == null or not gs.characters.has(actor) or gs.is_downed(actor) \
			or gs.is_external_traversal_active(actor):
		return false
	var origin: Vector3 = gs.get_position(actor)
	var duration := maxf(0.25, origin.distance_to(destination) / maxf(speed, 0.1))
	if not gs.command_external_traversal(
		actor,
		traversal_id,
		destination,
		gs.get_render_position(actor),
		destination,
		duration,
		&"locked"
	):
		return false
	var traversal: Dictionary = gs.get_external_traversal_state(actor)
	_route_choice = choice
	_route_phase = "%s_crossing" % choice
	_crossing_actor = actor
	_crossing_deadline = float(traversal.get("end_tick", _get_scheduler_tick() + duration))
	_last_outcome = "%s_crossing_committed" % choice
	_set_preview_step("endo_junction_%s_crossing" % choice)
	_bind_traversal_signals()
	_publish_endo_authority()
	return true


func _current_crossing_state() -> Dictionary:
	var gs = _get_game_state()
	if gs == null or _crossing_actor == "" or not gs.characters.has(_crossing_actor) \
			or not gs.is_external_traversal_active(_crossing_actor):
		return {}
	var traversal: Dictionary = gs.get_external_traversal_state(_crossing_actor)
	var expected := SAFE_TRAVERSAL_ID if _route_phase == "safe_crossing" else DIRECT_TRAVERSAL_ID
	return traversal if StringName(str(traversal.get("traversal_id", ""))) == expected else {}


func _resolve_route_from_positions() -> void:
	if _route_phase not in ["safe_crossing", "direct_crossing"] or _crossing_actor == "":
		return
	var gs = _get_game_state()
	if gs == null or not gs.characters.has(_crossing_actor) \
			or gs.is_external_traversal_active(_crossing_actor):
		return
	var expected_destination := SAFE_LEDGE_END \
		if _route_phase == "safe_crossing" else RISKY_BLOOM_END
	var arrived: bool = gs.get_position(_crossing_actor).distance_to(expected_destination) <= 0.2
	if not arrived:
		# Cancellation, incapacitation, or a malformed save can never grant the far-side outcome.
		_retract_cancelled_crossing(&"missing_destination")
		return
	var completed_choice := _route_choice
	_danger_resolved = true
	_route_phase = "%s_route" % completed_choice
	_last_outcome = "clean_crossing" if completed_choice == "safe" else "recoverable_spatial_damage"
	_crossing_actor = ""
	_crossing_deadline = -1.0
	_mark_segment("%s_route" % completed_choice)
	_set_preview_step("endo_junction_%s_route" % completed_choice)
	if completed_choice == "safe":
		_show_message("Endo reaches the far lip of the maintenance ledge.", 1.5)
	else:
		_show_message("The bloom crossing clears; only bodies caught in its pulses paid health.", 1.7)
	_apply_interactable_truth()
	_update_visual_state()
	_publish_endo_authority()


func _bind_traversal_signals() -> void:
	var gs = _get_game_state()
	if gs == null or gs == _traversal_signal_game_state:
		return
	if _traversal_signal_game_state != null:
		if _traversal_signal_game_state.external_traversal_finished.is_connected(
				_on_external_traversal_finished):
			_traversal_signal_game_state.external_traversal_finished.disconnect(
				_on_external_traversal_finished)
		if _traversal_signal_game_state.external_traversal_cancelled.is_connected(
				_on_external_traversal_cancelled):
			_traversal_signal_game_state.external_traversal_cancelled.disconnect(
				_on_external_traversal_cancelled)
	_traversal_signal_game_state = gs
	if not gs.external_traversal_finished.is_connected(_on_external_traversal_finished):
		gs.external_traversal_finished.connect(_on_external_traversal_finished)
	if not gs.external_traversal_cancelled.is_connected(_on_external_traversal_cancelled):
		gs.external_traversal_cancelled.connect(_on_external_traversal_cancelled)


func _on_external_traversal_finished(char_id: String, traversal_id: StringName) -> void:
	if char_id != _crossing_actor:
		return
	var expected := SAFE_TRAVERSAL_ID if _route_phase == "safe_crossing" else DIRECT_TRAVERSAL_ID
	if traversal_id == expected:
		_resolve_route_from_positions()


func _on_external_traversal_cancelled(
		char_id: String, traversal_id: StringName, reason: StringName
	) -> void:
	if char_id != _crossing_actor:
		return
	var expected := SAFE_TRAVERSAL_ID if _route_phase == "safe_crossing" else DIRECT_TRAVERSAL_ID
	if traversal_id == expected:
		_retract_cancelled_crossing(reason)


func _retract_cancelled_crossing(reason: StringName) -> void:
	if _route_phase not in ["safe_crossing", "direct_crossing"]:
		return
	_route_choice = ""
	_route_phase = "foraged" if _forage_collected else (
		"safe_marked" if _safe_route_marked else (
			"junction_read" if _junction_read else "junction"
		)
	)
	_crossing_actor = ""
	_crossing_deadline = -1.0
	_last_outcome = "crossing_cancelled:%s" % String(reason)
	_apply_interactable_truth()
	_update_visual_state()
	_publish_endo_authority()


func _cancel_owned_crossing(reason: StringName) -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for char_id in PARTY_IDS:
		if not gs.characters.has(char_id) or not gs.is_external_traversal_active(char_id):
			continue
		var traversal: Dictionary = gs.get_external_traversal_state(char_id)
		var traversal_id := StringName(str(traversal.get("traversal_id", "")))
		if traversal_id in [SAFE_TRAVERSAL_ID, DIRECT_TRAVERSAL_ID]:
			gs.cancel_external_traversal(char_id, reason)


func _on_direct_bloom_bite(char_id: String) -> void:
	_direct_damage_total += DIRECT_BLOOM_DAMAGE_PER_TICK
	_last_outcome = "bloom_bit:%s" % char_id
	_show_message("%s is inside the rust bloom pulse." % _display_name(char_id), 1.1)
	_publish_endo_authority()


func _on_shortcut_gate_opened() -> void:
	_sync_shortcut_from_gate()


func _on_shortcut_gate_blocked(_reason: StringName) -> void:
	if _shortcut_gate == null or _shortcut_gate.state == PartyGate3D.State.OPEN:
		return
	_last_outcome = "shortcut_failed_party_check"
	if _shortcut_interactable != null and _danger_resolved:
		_shortcut_interactable.set_interaction_enabled(true)
	_show_message("Endo left the latch before the return grate cleared; it settles closed.", 1.6)
	_update_visual_state()
	_publish_endo_authority()


func _sync_shortcut_from_gate() -> void:
	if _shortcut_gate == null:
		return
	var gate_open := _shortcut_gate.state == PartyGate3D.State.OPEN
	if gate_open == _shortcut_unlocked:
		return
	_shortcut_unlocked = gate_open
	if gate_open:
		_route_phase = "shelter_approach" if _route_phase != "complete" else _route_phase
		_last_outcome = "shortcut_open"
		_mark_segment("shortcut")
		_set_preview_step("endo_junction_shortcut_open")
		_show_message("The lifted grate exposes the physical return channel toward the junction.", 1.6)
	_apply_interactable_truth()
	_update_visual_state()
	_publish_endo_authority()

func _complete_interactable(interactable: Node) -> void:
	if interactable != null and interactable.has_method("set_interaction_enabled"):
		interactable.call("set_interaction_enabled", false)


## Every Endo Junction consequence begins at its one physical control. Interactable performs this
## pure validation before it records the exact actor's trigger; the callback below then requires
## that consumed one-shot receipt so direct helpers and manually emitted signals remain inert.
func _configure_endo_control(control: Node, action_id: String, callback: Callable) -> void:
	if not is_instance_valid(control):
		return
	control.set("one_shot", true)
	control.set_pre_trigger_validator(
		_validate_endo_control_trigger.bind(action_id, control))
	control.interacted.connect(callback.bind(control))
	if action_id == "shelter":
		control.interaction_rejected.connect(
			_on_endo_shelter_interaction_rejected.bind(control))


## The shared target pulse makes a rejection spatially visible. The shelter also
## names the first failed party precondition so the player can change a specific
## prediction instead of guessing why the red pulse appeared.
func _on_endo_shelter_interaction_rejected(
		source: Node, _required_character: String, expected_source: Node
	) -> void:
	if not is_instance_valid(source) or source != expected_source \
			or source != _shelter_interactable:
		return
	var blocked := _preflight_endo_shelter_rest().get("blocked", []) as Array
	var reason := str(blocked[0]) if not blocked.is_empty() \
		else "Shelter 1 cannot accept the party yet."
	_show_message(reason, 2.4)


func _validate_endo_control_trigger(
	source: Node,
	actor: String,
	action_id: String,
	expected_source: Node
) -> bool:
	if not is_instance_valid(source) or source != expected_source \
			or source != _endo_control_for_action(action_id):
		return false
	return _endo_interaction_actor_ready_at(
		source, actor, _endo_required_actor(action_id)
	) and _endo_control_action_ready(action_id, actor)


func _endo_control_receipt_pending(source: Node, action_id: String) -> bool:
	if not is_instance_valid(source) or source != _endo_control_for_action(action_id):
		return false
	var actor := str(source.get("active_character"))
	return _validate_endo_control_trigger(source, actor, action_id, source) \
		and _endo_consumed_source_receipt(source, actor)


func _endo_consumed_source_receipt(source: Node, actor: String) -> bool:
	if not is_instance_valid(source) or str(source.get("active_character")) != actor \
			or not bool(source.get("one_shot")) \
			or not bool(source.get("_used")) \
			or bool(source.get("interaction_enabled")):
		return false
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return false
	var spec: Dictionary = gs.get_interactable(data_id)
	return bool(spec.get("one_shot", false)) \
		and bool(spec.get("triggered", false)) \
		and not gs.is_interactable_enabled(data_id)


func _endo_interaction_actor_ready_at(
	source: Node, actor: String, expected_actor := ""
) -> bool:
	var gs = _get_game_state()
	if gs == null or not is_instance_valid(source) or not (source is Node3D) \
			or actor not in PARTY_IDS or not gs.characters.has(actor) \
			or (expected_actor != "" and actor != expected_actor) \
			or not gs.is_narratively_available(actor) \
			or gs.is_downed(actor) or gs.is_knocked_down(actor) \
			or gs.is_moving(actor) or gs.is_resting(actor) or gs.is_dodging(actor) \
			or gs.is_endocytosing(actor) or gs.is_external_traversal_active(actor) \
			or gs.is_dragging(actor) or gs.is_field_restoring(actor) \
			or gs.is_pushing(actor):
		return false
	var required_actor := str(source.get("required_character"))
	if required_actor != "" and actor != required_actor:
		return false
	var source_position := _endo_control_data_position(source)
	var actor_position: Vector3 = gs.get_position(actor)
	var radius: float = float(source.get("interaction_radius")) \
		+ INTERACTION_POSITION_TOLERANCE
	return Vector2(actor_position.x, actor_position.z).distance_to(
		Vector2(source_position.x, source_position.z)) <= radius


func _endo_control_data_position(source: Node) -> Vector3:
	var gs = _get_game_state()
	var data_id := str(source.get("data_id")) if is_instance_valid(source) else ""
	if gs != null and data_id != "" and gs.has_interactable(data_id):
		var position: Variant = gs.get_interactable(data_id).get("position", Vector3.ZERO)
		if position is Vector3:
			return position
	var world_position := (source as Node3D).global_position \
		if source is Node3D else Vector3.ZERO
	if gs != null and gs.coord_map != null and gs.coord_map.has_method("to_data"):
		return gs.coord_map.to_data(world_position)
	return world_position


func _endo_control_action_ready(action_id: String, actor: String) -> bool:
	match action_id:
		"junction":
			return not _junction_read
		"route":
			return _junction_read and not _safe_route_marked \
				and _route_phase not in [
					"safe_crossing", "direct_crossing", "safe_route", "direct_route",
					"shelter_approach", "complete",
				]
		"cache":
			return _cache_phase == CACHE_PHASE_AVAILABLE \
				and _endo_cache_item_at_source() \
				and _has_free_hand_slots(actor, 1)
		"safe":
			return _safe_route_marked and not _danger_resolved \
				and _route_phase not in ["safe_crossing", "direct_crossing"]
		"direct":
			return not _danger_resolved \
				and _route_phase not in ["safe_crossing", "direct_crossing"]
		"shortcut":
			return _danger_resolved and not _shortcut_unlocked \
				and _shortcut_gate != null \
				and _shortcut_gate.state == PartyGate3D.State.CLOSED
		"shelter":
			return _danger_resolved and not _shelter_rested \
				and _shelter_rest_phase == "ready" \
				and (_preflight_endo_shelter_rest().get("blocked", []) as Array).is_empty()
	return false


func _endo_control_for_action(action_id: String) -> Node:
	match action_id:
		"junction":
			return _junction_interactable
		"route":
			return _route_interactable
		"cache":
			return _cache_interactable
		"safe":
			return _safe_interactable
		"direct":
			return _direct_interactable
		"shortcut":
			return _shortcut_interactable
		"shelter":
			return _shelter_interactable
	return null


func _endo_required_actor(action_id: String) -> String:
	match action_id:
		"junction", "safe", "shortcut":
			return "endo"
		"route":
			return "aster"
	return ""


func _rearm_endo_control(source: Node) -> void:
	if is_instance_valid(source) and source.has_method("reset"):
		source.reset()
	_apply_interactable_truth()


func _reset_story_interactables() -> void:
	for interactable in [
		_junction_interactable,
		_route_interactable,
		_cache_interactable,
		_safe_interactable,
		_direct_interactable,
		_shortcut_interactable,
		_shelter_interactable,
	]:
		if interactable == null:
			continue
		if interactable.has_method("reset"):
			interactable.call("reset")
		if interactable.has_method("show_tutorial_label"):
			interactable.call("show_tutorial_label")

func _has_free_hand_slots(char_id: String, required_slots: int) -> bool:
	var free_count := 0
	for slot in _get_hand_slots(char_id):
		if slot == null:
			free_count += 1
			if free_count >= required_slots:
				return true
	return false

func _endo_cache_source_id() -> String:
	return "%s:forage_cache" % endo_authority_key()


func _spawn_endo_cache_source_item(properties := {}) -> String:
	var item_properties := {
		"display_name": "Junction Starch",
		"display_names_by_character": {
			"aster": "Lysate",
			"peris": "Lysate",
			"endo": "Starch",
		},
		"visual_color": Color(0.78, 0.66, 0.38),
		"atp_restore": 2.0,
		"hand_slots": 1,
		"endocytosis_allowed": true,
		"source_endo_forage_cache": _endo_cache_source_id(),
	}
	item_properties.merge(properties as Dictionary, true)
	return _spawn_item(CACHE_ITEM_TYPE, FORAGE_CACHE_POS, item_properties)


func _is_endo_cache_item(item_id: String) -> bool:
	var item := _get_item_state(item_id)
	if item.is_empty() or str(item.get("type", "")) != CACHE_ITEM_TYPE:
		return false
	var properties: Dictionary = item.get("properties", {})
	return str(properties.get("source_endo_forage_cache", "")) == _endo_cache_source_id()


func _find_endo_cache_item_id() -> String:
	var gs = _get_game_state()
	if gs == null or not "items" in gs:
		return ""
	var candidates: Array[String] = []
	for item_id_v in gs.items.keys():
		var item_id := str(item_id_v)
		if _is_endo_cache_item(item_id):
			candidates.append(item_id)
	candidates.sort()
	return candidates[0] if not candidates.is_empty() else ""


func _remove_endo_cache_items(keep_id := "") -> void:
	var gs = _get_game_state()
	if gs == null or not "items" in gs:
		return
	var remove_ids: Array[String] = []
	for item_id_v in gs.items.keys():
		var item_id := str(item_id_v)
		if item_id != keep_id and _is_endo_cache_item(item_id):
			remove_ids.append(item_id)
	for item_id in remove_ids:
		_remove_item(item_id)


func _reset_endo_cache_to_source(properties := {}) -> void:
	_remove_endo_cache_items()
	_cache_item_id = _spawn_endo_cache_source_item(properties)
	_cache_phase = CACHE_PHASE_AVAILABLE
	_cache_claimed_by = ""
	_cache_claim_serial = 0
	_forage_collected = false


func _ensure_endo_cache_source_item() -> String:
	if _is_endo_cache_item(_cache_item_id):
		_remove_endo_cache_items(_cache_item_id)
		return _cache_item_id
	_cache_item_id = _find_endo_cache_item_id()
	if _cache_item_id == "":
		_cache_item_id = _spawn_endo_cache_source_item()
	_remove_endo_cache_items(_cache_item_id)
	return _cache_item_id


func _endo_cache_item_at_source() -> bool:
	if not _is_endo_cache_item(_cache_item_id):
		return false
	var item := _get_item_state(_cache_item_id)
	return str(item.get("location", "")) == "ground" \
		and (item.get("position", FORAGE_CACHE_POS) as Vector3).distance_to(
			FORAGE_CACHE_POS) <= 0.05


func _endo_cache_item_holder() -> String:
	var item := _get_item_state(_cache_item_id)
	return str(item.get("holder", "")) if not item.is_empty() else ""


## Reconcile the synchronous pickup seam from item truth. A mismatched holder remains CLAIMING:
## restore never retargets the reservation, moves that item, or mints a replacement reward.
func _reconcile_endo_cache_transaction() -> bool:
	var changed := false
	if _is_endo_cache_item(_cache_item_id):
		_remove_endo_cache_items(_cache_item_id)
	match _cache_phase:
		CACHE_PHASE_AVAILABLE:
			# A displaced or missing exact item is inconsistent physical truth. Leave the cache
			# closed instead of choosing another tagged item or minting a replacement reward.
			_cache_claimed_by = ""
			_forage_collected = false
		CACHE_PHASE_CLAIMING:
			if _endo_cache_item_at_source():
				_cache_phase = CACHE_PHASE_AVAILABLE
				_cache_claimed_by = ""
				_forage_collected = false
				changed = true
			elif _is_endo_cache_item(_cache_item_id) \
					and _endo_cache_item_holder() == _cache_claimed_by:
				_cache_phase = CACHE_PHASE_CLAIMED
				_forage_collected = true
				changed = true
			# Wrong holder, moved ground item, or missing exact item: remain CLAIMING and disabled.
		CACHE_PHASE_CLAIMED:
			if _endo_cache_item_at_source():
				_cache_phase = CACHE_PHASE_AVAILABLE
				_cache_claimed_by = ""
				_forage_collected = false
				changed = true
			else:
				_forage_collected = true
	return changed


func _apply_endo_cache_semantic_projection() -> void:
	_forage_collected = _cache_phase == CACHE_PHASE_CLAIMED
	if _forage_collected:
		_mark_segment("forage")
		if _route_phase not in [
			"safe_crossing", "direct_crossing", "safe_route", "direct_route",
			"shelter_approach", "complete",
		]:
			_route_phase = "foraged"
		return
	_segments_completed.erase("forage")
	if _route_phase == "foraged":
		_route_phase = "safe_marked" if _safe_route_marked \
			else ("junction_read" if _junction_read else "junction")


func _full_conscious_party_near(position: Vector3, radius: float) -> bool:
	var gs = _get_game_state()
	if gs == null:
		return false
	for char_id in ["aster", "peris", "endo"]:
		if not gs.characters.has(char_id) or gs.is_downed(char_id):
			return false
		if _get_character_position(char_id).distance_to(position) > radius:
			return false
	return true

func _preflight_endo_shelter_rest() -> Dictionary:
	var outcome := _preflight_authored_party_rest(
		SHELTER_POS, Vector2(SHELTER_RADIUS * 2.0, SHELTER_RADIUS * 2.0), PARTY_IDS)
	var blocked := outcome.get("blocked", []) as Array
	if blocked.is_empty() and not _full_conscious_party_near(SHELTER_POS, SHELTER_RADIUS):
		blocked.append("Bring Aster, Peris, and Endo fully inside Shelter 1.")
	return outcome

func _party_min_hp() -> float:
	var min_hp := 999.0
	for char_id in ["aster", "peris", "endo"]:
		min_hp = minf(min_hp, _get_character_stat(char_id, "hp"))
	return min_hp

func _clear_endo_shelter_rest_context() -> void:
	_shelter_rest_commit_tick = -1.0
	_shelter_rest_commit_day = 0
	_shelter_rest_before_atp.clear()


func _endo_shelter_rest_tag() -> String:
	return "endo_party_rest:%s" % endo_authority_key().sha256_text().substr(0, 12)


func _cancel_endo_shelter_rest_callback() -> void:
	var scheduler = _get_scheduler()
	if scheduler != null:
		scheduler.cancel_tag(_endo_shelter_rest_tag())


func _arm_endo_shelter_rest_callback() -> void:
	var scheduler = _get_scheduler()
	if scheduler == null or _shelter_rest_phase != "committing":
		return
	scheduler.cancel_tag(_endo_shelter_rest_tag())
	scheduler.schedule_at(
		maxf(_get_scheduler_tick(), _shelter_rest_commit_tick),
		_resume_committed_endo_shelter_rest.bind(_shelter_rest_commit_tick),
		_endo_shelter_rest_tag())


func _resume_committed_endo_shelter_rest(expected_tick: float) -> void:
	if _shelter_rest_phase != "committing" \
			or not is_equal_approx(_shelter_rest_commit_tick, expected_tick):
		return
	if _authored_party_rest_effect_matches(
			PARTY_IDS, _shelter_rest_before_atp, _shelter_rest_commit_day):
		_complete_endo_shelter_rest(true)
		return
	var preflight := _preflight_endo_shelter_rest()
	if not _endo_shelter_preflight_matches_commit(preflight):
		_shelter_rest_phase = "ready"
		_clear_endo_shelter_rest_context()
		_apply_interactable_truth()
		_publish_endo_authority()
		return
	var gs = _get_game_state()
	if gs != null and bool(gs.command_party_rest(PARTY_IDS)):
		_complete_endo_shelter_rest(true)
	else:
		_shelter_rest_phase = "ready"
		_clear_endo_shelter_rest_context()
		_apply_interactable_truth()
		_publish_endo_authority()


func _endo_shelter_preflight_matches_commit(preflight: Dictionary) -> bool:
	var gs = _get_game_state()
	if gs == null or gs.get_game_day() != _shelter_rest_commit_day \
			or not (preflight.get("blocked", []) as Array).is_empty() \
			or preflight.get("members", []) != PARTY_IDS:
		return false
	for char_id in PARTY_IDS:
		if not _shelter_rest_before_atp.has(char_id) \
				or not is_equal_approx(
					gs.get_stat(char_id, "atp"),
					float(_shelter_rest_before_atp[char_id])):
			return false
	return true

func _fire_first_night_beat() -> void:
	if _first_night_beat_fired:
		return
	_first_night_beat_fired = true
	_first_night_beat_count += 1
	_clear_dialogue()
	_say_key("endo_stretch.shelter.peris")
	_say_key("endo_stretch.shelter.aster")
	_say_key("endo_stretch.shelter.endo_rest")
	_show_note("Shelter 1 reached. The full party spends one ATP each and beds down for the first night.", 4.0)

func _mark_segment(segment: String) -> void:
	if not _segments_completed.has(segment):
		_segments_completed.append(segment)


func _apply_interactable_truth() -> void:
	for action_id in [
		"junction", "route", "cache", "safe", "direct", "shortcut", "shelter",
	]:
		_set_interactable_enabled(
			_endo_control_for_action(action_id),
			_endo_control_owner_enabled(action_id))


func _endo_control_owner_enabled(action_id: String) -> bool:
	match action_id:
		"junction":
			return not _junction_read
		"route":
			return _junction_read and not _safe_route_marked \
				and _route_phase not in [
					"safe_crossing", "direct_crossing", "safe_route", "direct_route",
					"shelter_approach", "complete",
				]
		"cache":
			return _cache_phase == CACHE_PHASE_AVAILABLE \
				and _endo_cache_item_at_source()
		"safe", "direct":
			return not _danger_resolved \
				and _route_phase not in ["safe_crossing", "direct_crossing"]
		"shortcut":
			var gate_closed := _shortcut_gate == null \
				or _shortcut_gate.state == PartyGate3D.State.CLOSED
			return _danger_resolved and not _shortcut_unlocked and gate_closed
		"shelter":
			return not _shelter_rested and _shelter_rest_phase != "committing"
	return false


func _set_interactable_enabled(interactable: Node, enabled: bool) -> void:
	if interactable != null and interactable.has_method("set_interaction_enabled"):
		interactable.call("set_interaction_enabled", enabled)


func endo_authority_key() -> String:
	var owner := chunk_name if chunk_name != "" else "endo_junction_stretch"
	return "runtime:endo_junction:%s" % owner


func _endo_authority_state() -> Dictionary:
	return {
		"version": ENDO_AUTHORITY_VERSION,
		"authority_id": endo_authority_key(),
		"route_phase": _route_phase,
		"route_choice": _route_choice,
		"last_outcome": _last_outcome,
		"junction_read": _junction_read,
		"safe_route_marked": _safe_route_marked,
		"forage_collected": _forage_collected,
		"cache_item_id": _cache_item_id,
		"cache_phase": _cache_phase,
		"cache_claimed_by": _cache_claimed_by,
		"cache_claim_serial": _cache_claim_serial,
		"cache_source_id": _endo_cache_source_id(),
		"danger_resolved": _danger_resolved,
		"crossing_actor": _crossing_actor,
		"crossing_deadline": _crossing_deadline,
		"direct_damage_total": _direct_damage_total,
		"shortcut_unlocked": _shortcut_unlocked,
		"shelter_reached": _shelter_reached,
		"shelter_rested": _shelter_rested,
		"shelter_rest_phase": _shelter_rest_phase,
		"shelter_rest_commit_tick": _shelter_rest_commit_tick,
		"shelter_rest_commit_day": _shelter_rest_commit_day,
		"shelter_rest_before_atp": _shelter_rest_before_atp.duplicate(true),
		"first_night_beat_fired": _first_night_beat_fired,
		"first_night_beat_count": _first_night_beat_count,
		"segments_completed": _segments_completed.duplicate(),
	}


func _baseline_endo_authority_state() -> Dictionary:
	return {
		"version": ENDO_AUTHORITY_VERSION,
		"authority_id": endo_authority_key(),
		"route_phase": "junction",
		"route_choice": "",
		"last_outcome": "",
		"junction_read": false,
		"safe_route_marked": false,
		"forage_collected": false,
		"cache_item_id": _cache_item_id,
		"cache_phase": CACHE_PHASE_AVAILABLE,
		"cache_claimed_by": "",
		"cache_claim_serial": 0,
		"cache_source_id": _endo_cache_source_id(),
		"danger_resolved": false,
		"crossing_actor": "",
		"crossing_deadline": -1.0,
		"direct_damage_total": 0.0,
		"shortcut_unlocked": false,
		"shelter_reached": false,
		"shelter_rested": false,
		"shelter_rest_phase": "ready",
		"shelter_rest_commit_tick": -1.0,
		"shelter_rest_commit_day": 0,
		"shelter_rest_before_atp": {},
		"first_night_beat_fired": false,
		"first_night_beat_count": 0,
		"segments_completed": [],
	}


func _valid_endo_authority(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var saved := raw as Dictionary
	var phase := str(saved.get("route_phase", ""))
	var choice := str(saved.get("route_choice", ""))
	var actor := str(saved.get("crossing_actor", ""))
	var crossing := phase in ["safe_crossing", "direct_crossing"]
	var rest_phase := str(saved.get("shelter_rest_phase", ""))
	var before_atp: Variant = saved.get("shelter_rest_before_atp", null)
	var cache_phase := str(saved.get("cache_phase", ""))
	var cache_actor := str(saved.get("cache_claimed_by", ""))
	if int(saved.get("version", 0)) != ENDO_AUTHORITY_VERSION \
			or str(saved.get("authority_id", "")) != endo_authority_key() \
			or phase not in VALID_ROUTE_PHASES \
			or choice not in ["", "safe", "direct"] \
			or rest_phase not in SHELTER_REST_PHASES \
			or not before_atp is Dictionary \
			or cache_phase not in CACHE_PHASES \
			or str(saved.get("cache_item_id", "")) == "" \
			or str(saved.get("cache_source_id", "")) != _endo_cache_source_id() \
			or int(saved.get("cache_claim_serial", -1)) < 0 \
			or float(saved.get("direct_damage_total", -1.0)) < 0.0:
		return false
	var forage_collected := bool(saved.get("forage_collected", false))
	if cache_phase == CACHE_PHASE_AVAILABLE:
		if cache_actor != "" or forage_collected:
			return false
	elif cache_phase == CACHE_PHASE_CLAIMING:
		if cache_actor not in PARTY_IDS or forage_collected \
				or int(saved.get("cache_claim_serial", 0)) < 1:
			return false
	elif cache_actor not in PARTY_IDS or not forage_collected \
			or int(saved.get("cache_claim_serial", 0)) < 1:
		return false
	var rested := bool(saved.get("shelter_rested", false))
	if (rest_phase == "rested") != rested:
		return false
	if rest_phase == "rested" and phase != "complete":
		return false
	if rest_phase == "committing":
		if rested or float(saved.get("shelter_rest_commit_tick", -1.0)) < 0.0:
			return false
		for char_id in PARTY_IDS:
			if not (before_atp as Dictionary).has(char_id):
				return false
	elif float(saved.get("shelter_rest_commit_tick", -1.0)) >= 0.0 \
			or not (before_atp as Dictionary).is_empty():
		return false
	if crossing:
		return actor in PARTY_IDS \
			and choice == phase.trim_suffix("_crossing") \
			and float(saved.get("crossing_deadline", -1.0)) >= 0.0
	return actor == "" and float(saved.get("crossing_deadline", -1.0)) < 0.0


func _tag_legacy_endo_cache_item(item_id: String) -> bool:
	var gs = _get_game_state()
	if gs == null or not "items" in gs or not gs.items.has(item_id):
		return false
	var item: Dictionary = (gs.items[item_id] as Dictionary).duplicate(true)
	if str(item.get("type", "")) != CACHE_ITEM_TYPE:
		return false
	var properties: Dictionary = (item.get("properties", {}) as Dictionary).duplicate(true)
	properties["source_endo_forage_cache"] = _endo_cache_source_id()
	properties["legacy_endo_cache_migration"] = true
	item["properties"] = properties
	gs.items[item_id] = item
	return true


func _normalized_endo_authority(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var saved := (raw as Dictionary).duplicate(true)
	var saved_version := int(saved.get("version", 0))
	if saved_version in [1, 2]:
		saved["version"] = ENDO_AUTHORITY_VERSION
		if saved_version == 1:
			var legacy_rested := bool(saved.get("shelter_rested", false))
			saved["shelter_rest_phase"] = "rested" if legacy_rested else "ready"
			saved["shelter_rest_commit_tick"] = -1.0
			saved["shelter_rest_commit_day"] = 0
			saved["shelter_rest_before_atp"] = {}
		var legacy_collected := bool(saved.get("forage_collected", false))
		var legacy_item_id := str(saved.get("cache_item_id", ""))
		if legacy_collected:
			var migrated_item := _tag_legacy_endo_cache_item(legacy_item_id)
			var legacy_item := _get_item_state(legacy_item_id) if migrated_item else {}
			var legacy_holder := str(legacy_item.get("holder", ""))
			if legacy_holder not in PARTY_IDS:
				legacy_holder = "endo"
			saved["cache_item_id"] = (
				legacy_item_id
				if legacy_item_id != ""
				else "legacy_consumed:%s" % _endo_cache_source_id().sha256_text().substr(0, 12))
			saved["cache_phase"] = CACHE_PHASE_CLAIMED
			saved["cache_claimed_by"] = legacy_holder
			saved["cache_claim_serial"] = 1
		else:
			_reset_endo_cache_to_source({"legacy_source_recovery": true})
			saved["cache_item_id"] = _cache_item_id
			saved["cache_phase"] = CACHE_PHASE_AVAILABLE
			saved["cache_claimed_by"] = ""
			saved["cache_claim_serial"] = 0
		saved["cache_source_id"] = _endo_cache_source_id()
	return saved if _valid_endo_authority(saved) else {}


func _initialize_endo_authority() -> void:
	if _endo_authority_initialized:
		return
	var gs = _get_game_state()
	if gs == null or not gs.has_method("get_world_state"):
		return
	_endo_authority_initialized = true
	_endo_authority_baseline = _baseline_endo_authority_state()
	var raw: Variant = gs.get_world_state(endo_authority_key(), null)
	var normalized := _normalized_endo_authority(raw)
	if not normalized.is_empty():
		_restore_endo_authority(normalized)
		if int((raw as Dictionary).get("version", 0)) != ENDO_AUTHORITY_VERSION:
			_publish_endo_authority()
	else:
		_publish_endo_authority()


func _publish_endo_authority() -> void:
	if _restoring_endo_authority or not _endo_authority_initialized:
		return
	var gs = _get_game_state()
	if gs != null and gs.has_method("set_world_state"):
		gs.set_world_state(endo_authority_key(), _endo_authority_state())


## Interactable owns only the brief accepted-source edge; this chunk owns the lasting outcome.
## A save can be captured synchronously after GameState spends a one-shot but before the callback
## publishes Endo authority. Re-arm every source from owner truth on attachment so that seam grants
## nothing and remains retryable. Completed owner phases are disabled again by
## `_apply_interactable_truth`, so no completed consequence can be repeated.
func _normalize_endo_source_receipt_registry() -> void:
	var gs = _get_game_state()
	for action_id in [
		"junction", "route", "cache", "safe", "direct", "shortcut", "shelter",
	]:
		var source: Node = _endo_control_for_action(action_id)
		if not is_instance_valid(source):
			continue
		source.set("one_shot", true)
		var enabled := _endo_control_owner_enabled(action_id)
		var data_id := str(source.get("data_id"))
		if gs != null and data_id != "" and gs.has_interactable(data_id):
			var spec: Dictionary = gs.get_interactable(data_id)
			# This is restore normalization, not a new player command. Mutate the freshly loaded
			# registry record in place so attachment emits no reset/enable event or trigger signal.
			spec["one_shot"] = true
			spec["triggered"] = false
			spec["enabled"] = enabled
			gs.interactables[data_id] = spec
		if source.has_method("restore_one_shot_presenter"):
			source.restore_one_shot_presenter(false, enabled)


## Restore semantic facts only. GameState itself restores movement, stats, inventory, and the
## mechanism records; replaying any of those effects here would duplicate consequences on load.
func on_game_state_snapshot_restored() -> void:
	super.on_game_state_snapshot_restored()
	_cancel_endo_shelter_rest_callback()
	_endo_authority_initialized = true
	_bind_traversal_signals()
	if _endo_authority_baseline.is_empty():
		_endo_authority_baseline = _baseline_endo_authority_state()
	var gs = _get_game_state()
	var raw: Variant = gs.get_world_state(endo_authority_key(), null) \
		if gs != null and gs.has_method("get_world_state") else null
	var normalized := _normalized_endo_authority(raw)
	if not normalized.is_empty():
		_restore_endo_authority(normalized)
	else:
		# Absence means the snapshot predates this chunk's first semantic interaction. Keep the key
		# absent while retracting the presenter's future; this is important for rollback diagnostics.
		# An older GameState also has no authored cache item, so baseline migration may create that
		# one source here. Present v3 transaction restores never replace a missing exact item.
		var baseline_item_id := str(_endo_authority_baseline.get("cache_item_id", ""))
		if not _is_endo_cache_item(baseline_item_id):
			_reset_endo_cache_to_source({"legacy_absent_authority_recovery": true})
			_endo_authority_baseline = _baseline_endo_authority_state()
		_restore_endo_authority(_endo_authority_baseline)
	_restore_authored_mechanisms_after_snapshot()
	_resolve_route_from_positions()
	_sync_shortcut_from_gate()
	_normalize_endo_source_receipt_registry()
	_apply_interactable_truth()
	if _shelter_rest_phase == "committing":
		_arm_endo_shelter_rest_callback()


func _restore_endo_authority(saved: Dictionary) -> void:
	_restoring_endo_authority = true
	_cancel_endo_shelter_rest_callback()
	_junction_read = bool(saved.get("junction_read", false))
	_safe_route_marked = bool(saved.get("safe_route_marked", false))
	_forage_collected = bool(saved.get("forage_collected", false))
	_cache_item_id = str(saved.get("cache_item_id", ""))
	_cache_phase = str(saved.get("cache_phase", CACHE_PHASE_AVAILABLE))
	_cache_claimed_by = str(saved.get("cache_claimed_by", ""))
	_cache_claim_serial = maxi(0, int(saved.get("cache_claim_serial", 0)))
	_danger_resolved = bool(saved.get("danger_resolved", false))
	_shortcut_unlocked = bool(saved.get("shortcut_unlocked", false))
	_shelter_reached = bool(saved.get("shelter_reached", false))
	_shelter_rested = bool(saved.get("shelter_rested", false))
	_shelter_rest_phase = str(saved.get("shelter_rest_phase", "ready"))
	_shelter_rest_commit_tick = float(saved.get("shelter_rest_commit_tick", -1.0))
	_shelter_rest_commit_day = int(saved.get("shelter_rest_commit_day", 0))
	_shelter_rest_before_atp = (
		saved.get("shelter_rest_before_atp", {}) as Dictionary).duplicate(true)
	_first_night_beat_fired = bool(saved.get("first_night_beat_fired", false))
	_first_night_beat_count = maxi(int(saved.get("first_night_beat_count", 0)), 0)
	_route_choice = str(saved.get("route_choice", ""))
	_route_phase = str(saved.get("route_phase", "junction"))
	_last_outcome = str(saved.get("last_outcome", ""))
	_direct_damage_total = maxf(float(saved.get("direct_damage_total", 0.0)), 0.0)
	_crossing_actor = str(saved.get("crossing_actor", ""))
	_crossing_deadline = float(saved.get("crossing_deadline", -1.0))
	_segments_completed.clear()
	for segment_v in saved.get("segments_completed", []):
		var segment := str(segment_v)
		if segment != "" and not _segments_completed.has(segment):
			_segments_completed.append(segment)
	var cache_normalized := _reconcile_endo_cache_transaction()
	_apply_endo_cache_semantic_projection()
	_restoring_endo_authority = false
	_update_visual_state()
	_set_preview_step(_step_for_route_phase())
	if cache_normalized:
		_publish_endo_authority()


func _restore_authored_mechanisms_after_snapshot() -> void:
	if _shortcut_gate != null:
		_shortcut_gate.on_game_state_snapshot_restored()
	if _direct_bloom_field == null:
		return
	var gs = _get_game_state()
	var had_saved_hazard := gs != null \
		and gs.get_world_state(_direct_bloom_field.authority_state_key(), null) is Dictionary
	_direct_bloom_field.on_game_state_snapshot_restored()
	if not had_saved_hazard:
		# Unlike a dynamically spawned fire, this bloom is part of the authored baseline. An old save
		# without a kit record therefore reconstructs it active, with a fresh scheduler cadence.
		_direct_bloom_field.set_active(true)


func _reset_shortcut_gate_authority() -> void:
	if _shortcut_gate == null:
		return
	var gs = _get_game_state()
	if gs == null or not gs.has_method("set_world_state"):
		return
	gs.set_world_state(_shortcut_gate.authority_state_key(), {
		"contract": PartyGate3D.STATE_CONTRACT,
		"authority_id": SHORTCUT_GATE_AUTHORITY_ID,
		"phase": PartyGate3D.PHASE_CLOSED,
		"start_tick": -1.0,
		"end_tick": -1.0,
		"required_members": ["endo"],
	})
	_shortcut_gate.on_game_state_snapshot_restored()


func _step_for_route_phase() -> String:
	match _route_phase:
		"junction": return "endo_junction_stretch_start"
		"junction_read": return "endo_junction_read"
		"safe_marked": return "endo_junction_route_marked"
		"foraged": return "endo_junction_forage"
		"safe_crossing": return "endo_junction_safe_crossing"
		"direct_crossing": return "endo_junction_direct_crossing"
		"safe_route": return "endo_junction_safe_route"
		"direct_route": return "endo_junction_direct_route"
		"shelter_approach": return "endo_junction_shortcut_open"
		"complete": return "endo_junction_shelter_1"
	return "endo_junction_stretch_start"


func _current_instruction() -> String:
	match _route_phase:
		"junction":
			return "bring Endo to the glowing junction console and read it"
		"junction_read":
			return "have Aster mark the safe route"
		"safe_marked":
			return "collect the cache or commit the ledge"
		"foraged":
			return "choose ledge or short bloom"
		"safe_crossing", "direct_crossing":
			return "let the committed crossing reach its far lip"
		"safe_route", "direct_route":
			return "continue to Shelter 1; the return grate is optional"
		"shelter_approach":
			return "enter Shelter 1"
		"complete":
			return "rested"
		_:
			return "follow Endo's shelter marks"

func _display_name(char_id: String) -> String:
	match char_id:
		"aster": return "Aster"
		"peris": return "Peris"
		"endo": return "Endo"
		_: return char_id.capitalize()

func _update_visual_state() -> void:
	if _junction_material != null:
		_junction_material.emission_energy_multiplier = 0.35 if _junction_read else 1.3
	if _entry_guide != null:
		_entry_guide.visible = not _junction_read
	if _safe_material != null:
		_safe_material.emission_energy_multiplier = 0.62 if _safe_route_marked else 0.16
	if _direct_material != null:
		_direct_material.emission_energy_multiplier = 0.55 if _route_choice == "direct" else 0.24
	if _cache_material != null:
		_cache_material.emission_energy_multiplier = 0.08 if _forage_collected else 0.32
	var shortcut_phase := PartyGate3D.PHASE_CLOSED
	var shortcut_progress := 0.0
	if _shortcut_gate != null:
		var saved: Dictionary = _shortcut_gate.get_authority_state()
		shortcut_phase = str(saved.get("phase", PartyGate3D.PHASE_CLOSED))
		if shortcut_phase == PartyGate3D.PHASE_OPENING:
			var start := float(saved.get("start_tick", _get_scheduler_tick()))
			var finish := float(saved.get("end_tick", start + SHORTCUT_OPENING_DURATION))
			shortcut_progress = clampf(
				(_get_scheduler_tick() - start) / maxf(finish - start, 0.000001), 0.0, 1.0)
		elif shortcut_phase == PartyGate3D.PHASE_OPEN:
			shortcut_progress = 1.0
	if _shortcut_material != null:
		_shortcut_material.emission_energy_multiplier = \
			lerpf(0.14, 0.85, shortcut_progress)
	if _shortcut_grate_mesh != null:
		_shortcut_grate_mesh.position.y = lerpf(0.0, 2.65, shortcut_progress)
	if _shelter_material != null:
		_shelter_material.emission_energy_multiplier = 1.05 if _shelter_reached else 0.3
