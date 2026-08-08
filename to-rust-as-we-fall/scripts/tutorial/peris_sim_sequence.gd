@tool
extends "res://scripts/tutorial/tutorial_sequence.gd"

## Peris simulation tutorial: run, stamina, Wrap, and Monos.

@export_range(0, 2) var start_phase := 0
var _visit_phase := 1

const PLACEMENT_ROOT := "ScenePlacement"
const ROOM_OCCUPANTS := [
	"Portal", "Kiosk", "CoffeeTable", "Bookshelf", "bench", "couch",
]
const REQUIRED_AUTHORED_ROOM_NODES := [
	"RoomShell", "RoomFurniture", "bench", "couch", "Portal", "Kiosk", "Armchair",
	"CoffeeTable", "Bookshelf", "Rug", "WallArtFrame", "WallArt", "WateringCan",
	"WellnessTerminal", "StrikeNotice", "CareLogbookConsole", "CareFieldKit",
	"Plant1Table", "Plant1", "Plant2Table", "Plant2", "Plant3Table", "Plant3",
	"Plant4Table", "Plant4", "Plant5Table", "Plant5", "Plant6Table", "Plant6",
	"Plant7Table", "Plant7", "Plant8Table", "Plant8", "Plant9Table", "Plant9",
	"Plant1Hanger", "Plant6Hanger",
]
const REQUIRED_ROOM_MARKERS := [
	"PortalAnchor", "KioskAnchor", "ArmchairAnchor",
	"CoffeeTableAnchor", "BookshelfAnchor", "BenchAnchor",
	"RugAnchor", "WallArtAnchor", "PerisStart", "MonosStart", "PortalStand",
	"WateringCanAnchor",
	"PaintingZoneMarker", "WellnessZoneMarker", "StrikeWarningZoneMarker",
	"LogbookConsoleAnchor", "LogbookGateMarker",
	"WellnessTerminalAnchor", "StrikeNoticeAnchor",
	"PaintingApproach", "WellnessApproach", "StrikeWarningApproach",
	"Plant1TableAnchor", "Plant2TableAnchor", "Plant3TableAnchor",
	"Plant4TableAnchor", "Plant5TableAnchor", "Plant6TableAnchor",
	"Plant7TableAnchor", "Plant8TableAnchor", "Plant9TableAnchor",
	"Plant1Approach", "Plant2Approach", "Plant3Approach",
	"Plant4Approach", "Plant5Approach", "Plant6Approach",
	"Plant7Approach", "Plant8Approach", "Plant9Approach",
]
const ROOM_GRID_STEP := 0.5
# Wall-mounted assets still snap along the floor-plan axis, while their other
# coordinate is the shallow inset needed to keep the mesh clear of the wall.
const WALL_MOUNTED_GRID_AXES := {
	"WallArtAnchor": "x",
	"WellnessTerminalAnchor": "z",
	"StrikeNoticeAnchor": "z",
}

var _has_sprinted := false
# These private names and the `protect_prompt` step token predate the canonical
# Wrap label. Keep them as replay/test schema; live ability data always uses `wrap`.
var _has_protected := false
var _protect_queued := false
var _protect_end_tick := 0.0

var _monos
var _portal_visual: MeshInstance3D
var _portal_light: OmniLight3D
var _attack_particles: OmniLight3D
var _sanction_feed_label: Label3D
var _portal_tween_active := false
# Portal-view: a SubViewport with its own World3D renders the connected room (where Monos stands) onto the
# whole circular Portal_Surface disc. The viewport camera mirrors the live camera through the portal
# each frame (rendering-only), so the disc reads as a real opening with parallax.
var _portal_view_vp: SubViewport
var _portal_view_surface: MeshInstance3D
var _portal_view_cam: Camera3D
const PORTAL_LENS_SHADER := preload("res://resources/portal_lens.gdshader")
const CanonicalCharacterAbilityScript := preload("res://scripts/game/mechanics/canonical_character_ability.gd")
# Where the portal opening stands in the Monos room's own world: centre height matches the
# Peris-side portal centre, so the two rooms line up like a doorway.
const MONOS_ROOM_PORTAL_ANCHOR := Vector3(0.0, 2.5, 0.0)
var _hud  # GameHUD

# Optional watering beat (phase 1). Peris waters the Boston fern (Plant7) out of
# HABIT — her plants are engineered to stay green, so it's a ritual, not survival (no drying). A
# watering can sits by the kiosk as a real GameState ITEM: pick it up (hand slot fills, HUD shows it),
# carry it over, water the fern. It is character texture, not a progression prerequisite.
# The fern's watering-tradition reflection
# (plant_7.line / .line_repeat) lives in its inspection zone.
var _watering_can_item_id := ""
var _watering_can_mesh: Node3D
var _watering_can_home_parent: Node
var _watering_can_home_rotation := Vector3.ZERO
var _watering_can_home_scale := Vector3.ONE
var _watering_can_outline_target
var _watering_can_outline_offset := Vector3.ZERO
var _water_plant_interactable
var _can_pickup_interactable
var _fern_exploration_interactable
var _fern_outline_target
var _plant_watered := false
var _exploration_armed := false
var _watering_signal_game_state: GameState
var _watering_source_committed_counts: Dictionary = {}
var _active_watering_source_receipt: Dictionary = {}
var _explore_time_elapsed := false
const WATERING_CAN_CONTRACT := "peris_sim.watering_can"
const WATERING_AUTHORITY_KEY := "tutorial.peris_sim.watering"
const WATERING_AUTHORITY_VERSION := 2
const WATERING_PHASE_ID := &"tutorial.peris_sim.water_fern"
const WATERING_PHASE_ACTIVE := &"watering"
const WATERING_PHASE_COMPLETE := &"watered"
const WATERING_PHASE_AVAILABLE := &"available"
const WATERING_PICKUP_SOURCE_ID := "WateringCanPickup"
const WATERING_USE_SOURCE_ID := "WaterPlantSpot"
const WATERING_PICKUP_ACTION := "watering_can_pickup"
const WATERING_USE_ACTION := "water_fern"
const WATERING_USE_DURATION := 1.2
const WATERING_USE_RADIUS := 2.0
const WATERING_INTERACTION_POSITION_TOLERANCE := 0.35
const WATERING_INTERACTION_HEIGHT_TOLERANCE := 1.35
const WATERING_HAND_OFFSET := Vector3(0.42, 1.0, 0.18)
const WATERING_CAN_POS := Vector3(2.5, 0.0, 2.0)  # floor by the kiosk, snapped in X/Z to the room plan
const FERN_POS := Vector3(7.0, 0.0, 5.0)  # fallback when the authored fern table is absent
# The watering beat drives the player to the dry fern; the input playthrough drives this point.
# It follows the authored fern table so moving the table in the editor moves the beat with it.
var DRY_PLANT_POS: Vector3:
	get:
		var p := _authored_position("Plant7Table", "Plant7TableAnchor", FERN_POS)
		return Vector3(p.x, 0.0, p.z)

# Exploration beat (phase 1, pre-Monos-arrival)
var _explore_logbook_gate  # Interactable at the logbook
var _explore_gate_unlocked := false
var _explore_gate_fired := false

# Optional-read coverage telemetry for Peris's self-directed lap. The plant
# category accepts any existing plant-group zone without moving or duplicating
# room objects; none of these reads gates the logbook.
const CARE_CONTEXT_REQUIRED := ["plant", "painting", "wellness", "strike_warning"]
const CARE_CONTEXT_PLANT_BRANCHES := [
	"shelf",
	"survivor",
	"client",
	"fern",
	"peace",
]

var _care_context_completed: Dictionary = {}
var _care_context_zone_visits: Dictionary = {}
var _care_context_plant_group := ""
var _care_context_ready := false
# Stamina and run speed are authoritative in GameState.
var _is_paused := false
var _efficiency_score := 100.0

# Fallback positions are used only when a stripped test scene omits the editor-authored nodes.
const PORTAL_PANEL := Vector3(0.5, 2.5, 3.0)   # portal panel centre on the west wall
const PORTAL_POS := Vector3(2.5, 0, 3.0)  # floor in front of the portal — clear space for Peris
const MONOS_POS := Vector3(2.5, 0, 4.0)  # open circulation cell, separate from the Wrap cast stand
const WRAP_ABILITY_ID := "wrap"
const WRAP_DEFINITION_ID := "peris_sim.wrap"
const WRAP_INPUT_ACTION := &"party_slot_2_ability_1"
const PERIS_START := Vector3(6.0, 0.5, 4.5)  # circulation lane, outside the can/fern auto-dwell radii

# Scene-local booleans/Callables cannot survive a snapshot swap: a save made while
# Peris walks into cast range would restore GameState's canonical queued ability but
# lose the only callback that advances the story. This record is the portable causal
# owner; UI, dialogue, and callbacks are rebuilt from it after GameState replaces a
# snapshot.
const PERIS_AUTHORITY_KEY := "runtime:peris_sim:sequence_authority"
const PERIS_AUTHORITY_VERSION := 1
const PERIS_AUTHORITY_CONTRACT := "peris_sim_sequence_v1"
const PERIS_CAMPAIGN_PROGRESS_KEY := "tutorial.peris_sim.progress"
const PERIS_CAMPAIGN_PROGRESS_VERSION := 1

const PERIS_PHASE_FADE_FIRST := "fade_first_visit"
const PERIS_PHASE_EXPLORATION := "exploration"
const PERIS_PHASE_FIRST_DIALOGUE := "first_visit_dialogue"
const PERIS_PHASE_FIRST_HANDOFF_WAIT := "first_visit_handoff_wait"
const PERIS_PHASE_FADE_SECOND := "fade_second_visit"
const PERIS_PHASE_SESSION_LEAD := "session_lead"
const PERIS_PHASE_ATTACK_DIALOGUE := "attack_dialogue"
const PERIS_PHASE_WRAP_PROMPT := "wrap_prompt"
const PERIS_PHASE_WRAP_QUEUED := "wrap_queued"
const PERIS_PHASE_WRAP_TARGETING := "wrap_targeting"
const PERIS_PHASE_WRAP_TARGETED := "wrap_targeted"
const PERIS_PHASE_WRAP_QUEUE_PENDING := "wrap_queue_pending"
const PERIS_PHASE_WRAP_APPROACH := "wrap_approach"
const PERIS_PHASE_WRAP_CAST := "wrap_cast"
const PERIS_PHASE_AFTERMATH := "aftermath"
const PERIS_PHASE_EFFICIENCY_LOG := "efficiency_log"
const PERIS_PHASE_SANCTION_NOTICE := "sanction_notice"
const PERIS_PHASE_SANCTION_FEED := "sanction_feed"
const PERIS_PHASE_SPIRAL_FLASH := "spiral_flash"
const PERIS_PHASE_RETRO := "retro"
const PERIS_PHASE_SIM_BAY_EXIT := "sim_bay_exit"
const PERIS_PHASE_TRANSITION := "transition"
const PERIS_PHASE_COMPLETE := "complete"

const PERIS_FADE_DURATION := 3.0
const PERIS_SESSION_LEAD_DURATION := 2.0
const PERIS_FIRST_HANDOFF_DELAY := 3.0
const PERIS_EFFICIENCY_CLOSE_DELAY := 1.6
const PERIS_TRANSITION_DURATION := 2.5
const PERIS_AUTHORITY_DEADLINE_TAG := "peris_sequence_authority_deadline"
const PERIS_WRAP_RESOLVE_TAG := "peris_wrap_authority_resolve"

var _peris_authority_signal_game_state: GameState
var _restoring_peris_authority := false

# The workspace is the modeled Crocotile room (peris-sim.gltf): floor X in [0, 14], Z in [0, 6], up
# Y in [0, 5]. The grid is that footprint at 1 cell / unit, so movement is cell-based + cooperative
# like the other gridded scenes. OPEN (no border): the whole floor is walkable. Plants/zones sit right
# up against the visual walls — a bordered grid would wall those edge cells off and make those
# exploration zones unreachable.
const GRID_ORIGIN := Vector3(0.0, 0.0, 0.0)
const GRID_SIZE := Vector2i(14, 6)
const ROOM_FLOOR_Y := 0.0  # the modeled floor's top surface
var _grid: GridWorld
var _room_layout_problems: Array[String] = []
# The room model binding — model lookups / floor surface / occupancy flow through this (RoomModelBinder).
var _room_binder := RoomModelBinder.new()

# The composed room visuals and portable props are authored directly in peris_sim.tscn so they are
# visible, selectable, and movable in the editor. Only the separate live portal-view world is
# instantiated at runtime.
const MONOS_PORTAL_ROOM_VISUAL_SCENE := preload("res://scenes/props/peris/monos_portal_room_visual.tscn")


# --- Portable Peris sequence authority --------------------------------------------------------

func _baseline_peris_authority(visit_phase: int) -> Dictionary:
	var normalized_visit := clampi(visit_phase, 1, 2)
	return {
		"version": PERIS_AUTHORITY_VERSION,
		"contract": PERIS_AUTHORITY_CONTRACT,
		"visit_phase": normalized_visit,
		"phase": PERIS_PHASE_FADE_FIRST if normalized_visit == 1 else PERIS_PHASE_FADE_SECOND,
		"step": "fade_in",
		"started_at": _scheduler.get_current_tick() if _scheduler != null else 0.0,
		"deadline": -1.0,
		"exploration": {
			"gate_unlocked": false,
			"gate_fired": false,
			"time_elapsed": false,
			"room_reads": {},
			"zone_visits": {},
			"plant_group": "",
		},
		"wrap": {
			"owner_id": "peris",
			"target_id": "monos",
			"destination": _peris_authority_v3_data(
				_layout_position("PortalStand", PORTAL_POS)),
			"duration": float(AbilityData.get_ability("default.wrap").get(
				"duration", CanonicalCharacterAbilityScript.WRAP_DURATION_SECONDS)),
			"effect_deadline": -1.0,
			"queue_accepted": false,
		},
		"has_sprinted": false,
		"has_protected": false,
		"is_paused": false,
		"efficiency_score": 100.0,
	}


func _peris_authority_state() -> Dictionary:
	if _game_state == null:
		return {}
	var raw: Variant = _game_state.get_world_state(PERIS_AUTHORITY_KEY, null)
	if not (raw is Dictionary):
		return {}
	var authority := raw as Dictionary
	if int(authority.get("version", 0)) != PERIS_AUTHORITY_VERSION \
			or str(authority.get("contract", "")) != PERIS_AUTHORITY_CONTRACT:
		return {}
	return authority.duplicate(true)


func _publish_peris_authority(authority: Dictionary) -> void:
	if _game_state == null or _restoring_peris_authority:
		return
	authority["version"] = PERIS_AUTHORITY_VERSION
	authority["contract"] = PERIS_AUTHORITY_CONTRACT
	_game_state.set_world_state(PERIS_AUTHORITY_KEY, authority.duplicate(true))


func _publish_peris_phase(
		phase: String,
		deadline := -1.0,
		extra: Dictionary = {}
	) -> Dictionary:
	var authority := _peris_authority_state()
	if authority.is_empty():
		authority = _baseline_peris_authority(_visit_phase)
	authority["visit_phase"] = _visit_phase
	authority["phase"] = phase
	authority["step"] = _current_step
	authority["started_at"] = _scheduler.get_current_tick() if _scheduler != null else 0.0
	authority["deadline"] = deadline
	authority["has_sprinted"] = _has_sprinted
	authority["has_protected"] = _has_protected
	authority["is_paused"] = _is_paused
	authority["efficiency_score"] = _efficiency_score
	authority["exploration"] = _peris_exploration_authority_state()
	for key_v in extra.keys():
		authority[key_v] = (extra[key_v] as Dictionary).duplicate(true) \
			if extra[key_v] is Dictionary else extra[key_v]
	_publish_peris_authority(authority)
	return authority


func _publish_peris_observation_state() -> void:
	var authority := _peris_authority_state()
	if authority.is_empty():
		return
	authority["exploration"] = _peris_exploration_authority_state()
	authority["has_sprinted"] = _has_sprinted
	authority["has_protected"] = _has_protected
	authority["is_paused"] = _is_paused
	authority["efficiency_score"] = _efficiency_score
	_publish_peris_authority(authority)


func _peris_exploration_authority_state() -> Dictionary:
	return {
		"gate_unlocked": _explore_gate_unlocked,
		"gate_fired": _explore_gate_fired,
		"time_elapsed": _explore_time_elapsed,
		"room_reads": _care_context_completed.duplicate(true),
		"zone_visits": _care_context_zone_visits.duplicate(true),
		"plant_group": _care_context_plant_group,
	}


func _restore_peris_exploration_state(authority: Dictionary) -> void:
	var exploration_v: Variant = authority.get("exploration", {})
	var exploration: Dictionary = exploration_v as Dictionary \
		if exploration_v is Dictionary else {}
	_explore_gate_unlocked = bool(exploration.get("gate_unlocked", false))
	_explore_gate_fired = bool(exploration.get("gate_fired", false))
	_explore_time_elapsed = bool(exploration.get("time_elapsed", false))
	var reads_v: Variant = exploration.get("room_reads", {})
	_care_context_completed = (reads_v as Dictionary).duplicate(true) \
		if reads_v is Dictionary else {}
	var visits_v: Variant = exploration.get("zone_visits", {})
	_care_context_zone_visits = (visits_v as Dictionary).duplicate(true) \
		if visits_v is Dictionary else {}
	_care_context_plant_group = str(exploration.get("plant_group", ""))
	_care_context_ready = _explore_gate_unlocked


func _peris_authority_v3_data(value: Vector3) -> Array:
	if not value.is_finite():
		return []
	return [value.x, value.y, value.z]


func _peris_authority_v3(value: Variant) -> Vector3:
	if not (value is Array) or (value as Array).size() != 3:
		return Vector3.INF
	var encoded := value as Array
	for component in encoded:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] \
				or not is_finite(float(component)):
			return Vector3.INF
	return Vector3(float(encoded[0]), float(encoded[1]), float(encoded[2]))


func _peris_wrap_authority(authority := {}) -> Dictionary:
	var source: Dictionary = authority if authority is Dictionary and not authority.is_empty() \
		else _peris_authority_state()
	var wrap_v: Variant = source.get("wrap", {})
	return (wrap_v as Dictionary).duplicate(true) if wrap_v is Dictionary else {}


func _connect_peris_authority_signals() -> void:
	if _game_state == null:
		return
	if _peris_authority_signal_game_state != null \
			and _peris_authority_signal_game_state != _game_state \
			and _peris_authority_signal_game_state.ability_fired.is_connected(
				_on_peris_authority_ability_fired):
		_peris_authority_signal_game_state.ability_fired.disconnect(
			_on_peris_authority_ability_fired)
	_peris_authority_signal_game_state = _game_state
	if not _game_state.ability_fired.is_connected(_on_peris_authority_ability_fired):
		_game_state.ability_fired.connect(_on_peris_authority_ability_fired)


func _on_peris_authority_ability_fired(
		character_id: String,
		ability_id: String,
		_target_position: Vector3
	) -> void:
	if _restoring_peris_authority or character_id != "peris" \
			or ability_id != WRAP_ABILITY_ID:
		return
	var phase := str(_peris_authority_state().get("phase", ""))
	if phase not in [PERIS_PHASE_WRAP_QUEUE_PENDING, PERIS_PHASE_WRAP_APPROACH]:
		return
	_commit_wrap_cast_authority()


func _commit_wrap_cast_authority() -> void:
	var authority := _peris_authority_state()
	if authority.is_empty():
		return
	var phase := str(authority.get("phase", ""))
	if phase in [
		PERIS_PHASE_WRAP_CAST, PERIS_PHASE_AFTERMATH, PERIS_PHASE_EFFICIENCY_LOG,
		PERIS_PHASE_SANCTION_NOTICE, PERIS_PHASE_SANCTION_FEED, PERIS_PHASE_SPIRAL_FLASH,
		PERIS_PHASE_RETRO, PERIS_PHASE_SIM_BAY_EXIT, PERIS_PHASE_TRANSITION,
		PERIS_PHASE_COMPLETE,
	]:
		return
	if _game_state == null or _game_state.get_damage_shield("monos") <= 0.0:
		return
	_has_protected = true
	_protect_queued = false
	var wrap := _peris_wrap_authority(authority)
	var duration := maxf(0.001, float(wrap.get(
		"duration", CanonicalCharacterAbilityScript.WRAP_DURATION_SECONDS)))
	_protect_end_tick = _scheduler.get_current_tick() + duration
	wrap["queue_accepted"] = true
	wrap["effect_deadline"] = _protect_end_tick
	_publish_peris_phase(PERIS_PHASE_WRAP_CAST, _scheduler.get_current_tick(), {"wrap": wrap})
	_apply_wrap_cast_presenter(duration)
	_scheduler.cancel_tag(PERIS_WRAP_RESOLVE_TAG)
	_scheduler.schedule_after(0.0, _start_aftermath, PERIS_WRAP_RESOLVE_TAG)


func _apply_wrap_cast_presenter(duration: float) -> void:
	_face_peris_to_portal()
	if _hud:
		_hud.set_ability_state(WRAP_ABILITY_ID, "active", duration)
		_hud.show_message("Peris: WRAP! Shielding Monos from incoming damage.", 2.0)
	if _attack_particles:
		_attack_particles.light_energy = 0.5
	if _portal_light:
		_portal_light.light_color = Color(0.9, 0.7, 0.3)
		_portal_light.light_energy = 4.0


func _issue_wrap_queue_from_authority() -> void:
	if _game_state == null or _scheduler == null:
		return
	var authority := _peris_authority_state()
	var phase := str(authority.get("phase", ""))
	if phase not in [PERIS_PHASE_WRAP_QUEUE_PENDING, PERIS_PHASE_WRAP_APPROACH]:
		return
	if _game_state.get_damage_shield("monos") > 0.0:
		_commit_wrap_cast_authority()
		return
	if _game_state.has_queued_ability("peris"):
		if phase != PERIS_PHASE_WRAP_APPROACH:
			var queued_wrap := _peris_wrap_authority(authority)
			queued_wrap["queue_accepted"] = true
			_publish_peris_phase(PERIS_PHASE_WRAP_APPROACH, -1.0, {"wrap": queued_wrap})
		return
	var wrap := _peris_wrap_authority(authority)
	var destination := _peris_authority_v3(wrap.get("destination", null))
	if not destination.is_finite():
		destination = _layout_position("PortalStand", PORTAL_POS)
		wrap["destination"] = _peris_authority_v3_data(destination)
	var duration := maxf(0.001, float(wrap.get(
		"duration", CanonicalCharacterAbilityScript.WRAP_DURATION_SECONDS)))
	var result := _game_state.queue_canonical_ability(
		"peris",
		WRAP_ABILITY_ID,
		destination,
		{
			"target_id": "monos",
			"allowed_target_ids": ["monos"],
			"duration": duration,
			"approach_range": 2.5,
		}
	)
	if not bool(result.get("accepted", false)):
		# The committed command could not be reconstructed (for example, an edited
		# snapshot removed Monos). Return to the explicit target-confirm step instead
		# of silently completing or leaving an inert executing beat.
		_protect_queued = true
		_current_step = "confirm_protect"
		_is_paused = true
		_publish_peris_phase(PERIS_PHASE_WRAP_TARGETED)
		_restore_wrap_targeted_presenter()
		return
	# An in-range cast emits ability_fired before queue_canonical_ability returns.
	# Never overwrite the resulting cast/aftermath phase with the older approach.
	if str(_peris_authority_state().get("phase", "")) \
			in [PERIS_PHASE_WRAP_QUEUE_PENDING, PERIS_PHASE_WRAP_APPROACH]:
		wrap["queue_accepted"] = true
		_publish_peris_phase(PERIS_PHASE_WRAP_APPROACH, -1.0, {"wrap": wrap})


func _arm_peris_authority_deadline(authority: Dictionary) -> void:
	if _scheduler == null:
		return
	var phase := str(authority.get("phase", ""))
	var tag := _peris_authority_deadline_tag(phase)
	_scheduler.cancel_tag(tag)
	var deadline := float(authority.get("deadline", -1.0))
	if deadline < float(authority.get("started_at", -1.0)) or deadline < 0.0:
		return
	if deadline <= _scheduler.get_current_tick():
		_on_peris_authority_deadline(phase, deadline)
	else:
		_scheduler.schedule_at(
			deadline,
			_on_peris_authority_deadline.bind(phase, deadline),
			tag)


func _peris_authority_deadline_tag(phase: String) -> String:
	return "%s:%s" % [PERIS_AUTHORITY_DEADLINE_TAG, phase]


func _peris_authority_deadline_phases() -> Array[String]:
	return [
		PERIS_PHASE_FADE_FIRST, PERIS_PHASE_FIRST_HANDOFF_WAIT,
		PERIS_PHASE_FADE_SECOND, PERIS_PHASE_SESSION_LEAD,
		PERIS_PHASE_EFFICIENCY_LOG, PERIS_PHASE_TRANSITION,
	]


func _on_peris_authority_deadline(expected_phase: String, expected_deadline: float) -> void:
	var authority := _peris_authority_state()
	if str(authority.get("phase", "")) != expected_phase \
			or not is_equal_approx(float(authority.get("deadline", -1.0)), expected_deadline):
		return
	match expected_phase:
		PERIS_PHASE_FADE_FIRST:
			_start_workspace()
		PERIS_PHASE_FIRST_HANDOFF_WAIT:
			_start_transition_out()
		PERIS_PHASE_FADE_SECOND:
			_start_session_begins()
		PERIS_PHASE_SESSION_LEAD:
			_start_attack()
		PERIS_PHASE_EFFICIENCY_LOG:
			_start_sanction_notice()
		PERIS_PHASE_TRANSITION:
			_complete()


func _clear_peris_authority_callbacks() -> void:
	if _scheduler != null:
		for phase in _peris_authority_deadline_phases():
			_scheduler.cancel_tag(_peris_authority_deadline_tag(phase))
		for tag in [
			PERIS_AUTHORITY_DEADLINE_TAG, PERIS_WRAP_RESOLVE_TAG,
			"workspace", "session_begins", "attack", "alert_monos", "aftermath",
			"efficiency_log", "sanction_notice", "sanction_feed", "spiral_flash",
			"retro", "sim_bay_exit", "transition_out", "complete",
		]:
			_scheduler.cancel_tag(tag)
	if _dialogue != null:
		for connection_v in _dialogue.dialogue_finished.get_connections():
			var connection := connection_v as Dictionary
			_dialogue.dialogue_finished.disconnect(connection.callable)
		_dialogue.clear()
	_dlg_chain_keys.clear()
	_dlg_chain_index = 0
	_dlg_chain_next = Callable()


func _restore_peris_move_input(enabled: bool) -> void:
	if _player == null:
		return
	if _player.has_method("restore_move_input_enabled"):
		_player.restore_move_input_enabled(enabled)
	else:
		_player.set("_move_enabled", enabled)


func _restore_peris_authority_after_snapshot() -> void:
	if _scheduler == null or _game_state == null:
		return
	_clear_peris_authority_callbacks()
	var authority := _peris_authority_state()
	if authority.is_empty():
		authority = _baseline_peris_authority(_visit_phase)
		_publish_peris_authority(authority)
	_visit_phase = clampi(int(authority.get("visit_phase", 1)), 1, 2)
	_has_sprinted = bool(authority.get("has_sprinted", false))
	_has_protected = bool(authority.get("has_protected", false))
	_is_paused = bool(authority.get("is_paused", false))
	_efficiency_score = float(authority.get("efficiency_score", 100.0))
	_restore_peris_exploration_state(authority)
	var phase := str(authority.get("phase", ""))
	var saved_step := str(authority.get("step", ""))
	if saved_step != "":
		_current_step = saved_step
	var wrap := _peris_wrap_authority(authority)
	_protect_end_tick = maxf(0.0, float(wrap.get("effect_deadline", -1.0)))
	_protect_queued = phase in [
		PERIS_PHASE_WRAP_TARGETED, PERIS_PHASE_WRAP_QUEUE_PENDING,
		PERIS_PHASE_WRAP_APPROACH,
	]
	_restoring_peris_authority = true
	match phase:
		PERIS_PHASE_FADE_FIRST, PERIS_PHASE_FADE_SECOND:
			_current_step = "fade_in"
			_restore_peris_move_input(false)
			_fade_start_tick = float(authority.get("started_at", _scheduler.get_current_tick()))
			_update_fades()
		PERIS_PHASE_EXPLORATION:
			_current_step = "workspace"
			_restore_peris_move_input(true)
			_set_exploration_armed(true, true)
			_set_interactable_projection(_explore_logbook_gate, _explore_gate_unlocked, true)
		PERIS_PHASE_FIRST_DIALOGUE:
			_current_step = "monos_breakthrough"
			_restore_peris_move_input(true)
			_present_first_visit_dialogue()
		PERIS_PHASE_FIRST_HANDOFF_WAIT:
			_current_step = "monos_breakthrough"
			_restore_peris_move_input(true)
		PERIS_PHASE_SESSION_LEAD:
			_current_step = "session_begins"
			_restore_session_lead_presenter()
		PERIS_PHASE_ATTACK_DIALOGUE:
			_current_step = "attack"
			_present_attack_dialogue()
		PERIS_PHASE_WRAP_PROMPT:
			_current_step = "protect_prompt"
			_restore_wrap_prompt_presenter()
		PERIS_PHASE_WRAP_QUEUED:
			_current_step = "run_prompt"
			_restore_wrap_queued_presenter()
		PERIS_PHASE_WRAP_TARGETING:
			_current_step = "click_monos"
			_restore_wrap_targeting_presenter()
		PERIS_PHASE_WRAP_TARGETED:
			_current_step = "confirm_protect"
			_restore_wrap_targeted_presenter()
		PERIS_PHASE_WRAP_QUEUE_PENDING, PERIS_PHASE_WRAP_APPROACH:
			_current_step = "executing"
			_restore_wrap_executing_presenter()
		PERIS_PHASE_WRAP_CAST:
			_current_step = "executing"
			_apply_wrap_cast_presenter(maxf(
				0.0, _protect_end_tick - _scheduler.get_current_tick()))
		PERIS_PHASE_AFTERMATH:
			_current_step = "aftermath"
			_present_aftermath_dialogue()
		PERIS_PHASE_EFFICIENCY_LOG:
			_current_step = "efficiency_log"
			if float(authority.get("deadline", -1.0)) < 0.0:
				_present_efficiency_log()
			else:
				_restore_efficiency_log_presenter()
		PERIS_PHASE_SANCTION_NOTICE:
			_current_step = "sanction_notice"
			_present_sanction_notice()
		PERIS_PHASE_SANCTION_FEED:
			_current_step = "sanction_feed"
			_present_sanction_feed()
		PERIS_PHASE_SPIRAL_FLASH:
			_current_step = "spiral_flash"
			_present_spiral_flash()
		PERIS_PHASE_RETRO:
			_current_step = "retro"
			_present_retro()
		PERIS_PHASE_SIM_BAY_EXIT:
			_current_step = "sim_bay_exit"
			_present_sim_bay_exit()
		PERIS_PHASE_TRANSITION:
			_current_step = "transition_out"
			_restore_peris_move_input(false)
			_fade_start_tick = float(authority.get("started_at", _scheduler.get_current_tick()))
			_update_fades()
		PERIS_PHASE_COMPLETE:
			_current_step = "complete"
			_restore_peris_move_input(false)
			requested_scene_change = str(authority.get("destination", ""))
	_restoring_peris_authority = false
	if phase in [
		PERIS_PHASE_FADE_FIRST, PERIS_PHASE_FIRST_HANDOFF_WAIT,
		PERIS_PHASE_FADE_SECOND, PERIS_PHASE_SESSION_LEAD,
		PERIS_PHASE_EFFICIENCY_LOG, PERIS_PHASE_TRANSITION,
	]:
		_arm_peris_authority_deadline(authority)
	elif phase in [PERIS_PHASE_WRAP_QUEUE_PENDING, PERIS_PHASE_WRAP_APPROACH]:
		_issue_wrap_queue_from_authority()
	elif phase == PERIS_PHASE_WRAP_CAST:
		_scheduler.schedule_after(0.0, _start_aftermath, PERIS_WRAP_RESOLVE_TAG)


func _resolve_initial_visit_phase() -> int:
	if start_phase > 0:
		return start_phase
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("get_campaign_state"):
		var progress_v: Variant = save_manager.get_campaign_state(
			PERIS_CAMPAIGN_PROGRESS_KEY, null)
		if progress_v is Dictionary:
			var progress := progress_v as Dictionary
			if int(progress.get("version", 0)) == PERIS_CAMPAIGN_PROGRESS_VERSION:
				return clampi(int(progress.get("next_visit_phase", _visit_phase)), 1, 2)
	return clampi(_visit_phase, 1, 2)


func _publish_peris_campaign_progress(second_visit_complete := false) -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("set_campaign_state"):
		return
	save_manager.set_campaign_state(PERIS_CAMPAIGN_PROGRESS_KEY, {
		"version": PERIS_CAMPAIGN_PROGRESS_VERSION,
		"next_visit_phase": 2,
		"first_visit_complete": true,
		"second_visit_complete": second_visit_complete,
	})


## The scene's Marker3Ds are the editable floor plan. Constants above are only
## deterministic fallbacks for tests/tools that instantiate the script without
## the authored placement tree.
func _layout_position(marker_name: String, fallback: Vector3) -> Vector3:
	var placement := find_child(PLACEMENT_ROOT, true, false)
	if placement == null:
		return fallback
	var marker := placement.find_child(marker_name, true, false) as Node3D
	return marker.global_position if marker != null else fallback


func _authored_room_node(node_name: String) -> Node3D:
	var room := find_child("PerisRoom", true, false) as Node3D
	if room == null:
		return null
	return room.find_child(node_name, true, false) as Node3D


func _authored_position(node_name: String, marker_name: String, fallback: Vector3) -> Vector3:
	var authored := _authored_room_node(node_name)
	return authored.global_position if authored != null else _layout_position(marker_name, fallback)


func _portal_panel_position() -> Vector3:
	return _authored_position("Portal", "PortalAnchor", PORTAL_PANEL)


func _portal_basis() -> Basis:
	var portal := _authored_room_node("Portal")
	return portal.global_basis.orthonormalized() if portal != null else Basis(Vector3.UP, PI * 0.5)


func _portal_face() -> Vector3:
	return (_portal_basis() * Vector3.BACK).normalized()


## Floor interaction points follow the visible node. `local_floor_offset` rotates with the prop,
## so moving a wall fixture to another wall does not strand its clickable zone at the old marker.
func _authored_floor_interaction_position(
	node_name: String,
	marker_name: String,
	fallback: Vector3,
	local_floor_offset: Vector3
) -> Vector3:
	var authored := _authored_room_node(node_name)
	if authored == null:
		return _layout_position(marker_name, fallback)
	var point := authored.global_position
	point.y = ROOM_FLOOR_Y
	return point + authored.global_basis.orthonormalized() * local_floor_offset


func _set_interaction_approach(interactable: Node, marker_name: String, fallback: Vector3) -> void:
	if interactable != null:
		interactable.set_meta("interaction_target_position", _layout_position(marker_name, fallback))


# --- Virtual method overrides ---

func _build_scene() -> void:
	_build_grid()
	_build_environment()
	# Occupancy depends on the post-layout world AABBs, so derive it only after
	# every modeled assembly has been moved to its authored marker.
	_room_binder.apply_occupancy()

## A single-level walkable plane over the modeled floor (open, no border).
func _build_grid() -> void:
	_grid = GridWorld.new()
	_grid.origin = GRID_ORIGIN
	_grid.create_room(GRID_SIZE.x, GRID_SIZE.y, false)
	# The scene's ONE declaration of its modeled room: the floor surface (overlays/raycast ride it),
	# grid seams aligned to the model's floor, and the re-export guards. setup() lifts grid.origin.y
	# to the floor top so every ground overlay sits on the modeled floor, not inside the slab.
	_room_binder.setup(self, _grid, {
		"root_name": "PerisRoom",
		"floor_surface_y": ROOM_FLOOR_Y,
		"grid_origin_xz": Vector2(0, 0),
		"occupants": ROOM_OCCUPANTS,
		"gltf_path": "res://resources/models/peris-sim/peris-sim.gltf",
		"wired_materials": [],
	})
	_build_portal()

func _build_characters() -> void:
	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)

	_player = _create_player_character("Peris", Color(1.0, 0.67, 0.27))
	_player.position = _layout_position("PerisStart", PERIS_START)
	if not Engine.is_editor_hint():
		_player.grid_world = _grid
	chars.add_child(_player)

	_monos = _create_npc("Monos", Color(0.6, 0.5, 0.35))
	_monos.display_name = "MONOS"
	_monos.position = _layout_position("MonosStart", MONOS_POS)
	_monos.visible = false
	if not Engine.is_editor_hint():
		_monos.grid_world = _grid
	chars.add_child(_monos)

	if not Engine.is_editor_hint():
		# The modeled room is small (14x6); pull the follow camera up/back so the whole floor frames,
		# keeping the far corners (plant stand / bookshelf) clickable.
		_setup_game_camera(_player, Vector3(0, 14, 10), true)
		_bind_camera_to_level_bounds(_grid, 0.5)

func _register_characters() -> void:
	_game_state.grid = _grid
	_register_gs_character("peris", _player, GameState.WALK_SPEED, {
		"stamina": GameState.STAMINA_MAX,
	})
	_register_gs_character("monos", _monos, _monos.move_speed)

func _setup_ui() -> void:
	_thought_label.add_theme_color_override("font_color", Color(0.75, 0.6, 0.45))

	_hud = preload("res://scenes/ui/game_hud.tscn").instantiate()
	add_child(_hud)
	_hud.add_stat_bar("sta", Color(0.3, 0.5, 0.7), GameState.STAMINA_MAX, GameState.STAMINA_MAX)
	_hud.show_pause_toggle(false)
	_hud.show_run_toggle(false)
	var wrap_binding := AbilityData.binding(WRAP_ABILITY_ID)
	_hud.add_ability(WRAP_ABILITY_ID, AbilityData.get_ability(WRAP_DEFINITION_ID).get("display_name", "WRAP"),
		InputHints.label_for_action(WRAP_INPUT_ACTION, str(wrap_binding.get("keybind", ""))),
		wrap_binding.get("color", Color(0.8, 0.55, 0.2)),
		WRAP_INPUT_ACTION, "peris", "Peris", 1, 0)
	_hud.pause_toggled.connect(_on_pause_toggled)
	# Step guards decide when run toggles are allowed.
	_hud.run_toggled.connect(_on_hud_run_toggled)
	_hud.ability_pressed.connect(_on_hud_ability_pressed)
	# Keep run input gated by step.
	_hud.bind_game_state(_game_state, "peris", false)


func _on_hud_run_toggled(_running: bool) -> void:
	_toggle_run()


func _on_hud_ability_pressed(ability_id: String) -> void:
	if ability_id == WRAP_ABILITY_ID:
		_on_protect_pressed()

func _begin() -> void:
	_connect_peris_authority_signals()
	_add_screen_effect("ChromaticAberration", preload("res://resources/chromatic_aberration.gdshader"))
	_visit_phase = _resolve_initial_visit_phase()
	_enter_step("fade_in")
	_player.set_move_enabled(false)
	# The room is DRESSED from the first frame, in BOTH phases — plants on their furniture, the
	# wall pieces, the logbook console (dressing tied to the workspace step would pop in seconds
	# after the fade, and phase 2 would show a plantless room). Interactions stay dark until the
	# phase-1 workspace step arms them.
	_build_exploration_objects()
	if _game_state.get_world_state(PERIS_AUTHORITY_KEY, null) == null:
		_publish_peris_authority(_baseline_peris_authority(_visit_phase))
	_fade_rect.color = Color(0.15, 0.1, 0.03, 1)
	_fade_start_tick = _scheduler.get_current_tick()
	if _visit_phase == 1:
		var first_fade := _publish_peris_phase(
			PERIS_PHASE_FADE_FIRST, _scheduler.get_current_tick() + PERIS_FADE_DURATION)
		_arm_peris_authority_deadline(first_fade)
	else:
		# Phase 2 resumes mid-session.
		_monos.visible = true
		_portal_light.light_color = Color(0.9, 0.6, 0.3)
		_portal_light.light_energy = 3.0
		var second_fade := _publish_peris_phase(
			PERIS_PHASE_FADE_SECOND, _scheduler.get_current_tick() + PERIS_FADE_DURATION)
		_arm_peris_authority_deadline(second_fade)

func _compute_speed() -> float:
	var spd := 10.0 if Input.is_action_pressed("fast_forward") else 1.0
	if _is_paused or _current_step in ["alert_monos", "protect_prompt", "run_prompt", "click_monos", "confirm_protect"]:
		spd = 0.0
	return spd

func _on_process(delta: float, spd: float) -> void:
	_update_fades()
	_sync_watering_can_presenter()

	# GameState and GameHUD handle stats, running, and queued Wrap.

	if _portal_light and not _portal_tween_active:
		_portal_light.light_energy = 1.5 + sin(Time.get_ticks_msec() * 0.002) * 0.3  # @rendering_only: portal glow

	# Attack light flash
	if _attack_particles and _attack_particles.visible:
		_attack_particles.light_energy = 3.0 + sin(Time.get_ticks_msec() * 0.015) * 2.0  # @rendering_only: attack flash

	_update_portal_view()  # @rendering_only: portal lens camera mirror

	# Wrap ability display from scheduler ticks. The legacy `_protect_*` state names
	# remain private so existing deterministic tutorial replays keep their step contract.
	if _protect_end_tick > 0 and _hud:
		var remaining := maxf(0, _protect_end_tick - _scheduler.get_current_tick())
		_hud.set_ability_state(WRAP_ABILITY_ID, "active", remaining)
		if remaining <= 0:
			_protect_end_tick = 0.0

func headless_get_state() -> Dictionary:
	_plant_watered = _is_plant_watered_authoritatively()
	var state := super.headless_get_state()
	state.merge({
		"visit_phase": _visit_phase,
		"peris_authority": _peris_authority_state(),
		"plant_watered": _plant_watered,
		"watering_phase": str(_watering_phase()),
		"watering_can_item_id": _resolve_watering_can_item_id(),
		"explore_gate_unlocked": _explore_gate_unlocked,
		"room_read_counts": _care_context_completed.duplicate(true),
		"room_read_zone_visits": _care_context_zone_visits.duplicate(true),
		"room_read_count": _care_context_completed_count(),
		"room_reads_optional": true,
		"logbook_ready": _care_context_ready,
		"wrap_queued": _protect_queued,
		"wrap_used": _has_protected,
	}, true)
	return state
func get_playtime_contract() -> Dictionary:
	var move_speed := maxf(float(_player.move_speed) if _player != null else GameState.WALK_SPEED, 0.1)
	var start := _layout_position("PerisStart", PERIS_START)
	var logbook := _logbook_contract_position()
	var mandatory_route_meters := _horizontal_distance(start, logbook)
	var mandatory_active_seconds := mandatory_route_meters / move_speed + 0.8
	var optional_worldbuilding_seconds := 60.0
	var meaningful_active_seconds := mandatory_active_seconds + optional_worldbuilding_seconds
	return {
		"target_id": "peris_sim",
		"meaningful_active_seconds": meaningful_active_seconds,
		"total_play_seconds": meaningful_active_seconds + 24.0,
		"max_dead_gap_seconds": 3.0,
		"max_single_mode_seconds": 30.0,
		"decision_count": 1,
		"branch_count": CARE_CONTEXT_REQUIRED.size(),
		"category_seconds": {
			"required_traversal_and_interaction": mandatory_active_seconds,
			"optional_worldbuilding": optional_worldbuilding_seconds,
		},
		"required_first_clear_seconds": mandatory_active_seconds,
		"target_min_seconds": 30.0,
		"target_max_seconds": 90.0,
		"modeled_first_clear_seconds": meaningful_active_seconds,
		"mandatory_route_meters": mandatory_route_meters,
		"mandatory_optional_reads": 0,
		"mandatory_watering_actions": 0,
		"optional_interactable_count": 12,
		"progression_gate": "logbook",
		"free_exploration": true,
		"timing_basis": "direct logbook progression plus an optional 30-90 second character and worldbuilding lap",
	}

func _logbook_contract_position() -> Vector3:
	if _explore_logbook_gate != null and is_instance_valid(_explore_logbook_gate):
		return _explore_logbook_gate.global_position
	return _layout_position("LogbookGateMarker", Vector3(12.5, 0.0, 3.5))

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _update_fades() -> void:
	if _current_step == "fade_in":
		_update_fade_in(PERIS_FADE_DURATION)
	elif _current_step == "transition_out":
		_update_fade_out(Color(0.03, 0.03, 0.04), PERIS_TRANSITION_DURATION)

# --- Target selection (click Monos) ---

## During click_monos the player is in "select" click mode; the shared input
## controller reports the clicked ground position here. We only decide whether
## it's close enough to Monos — no raycasting in the sequence.
func _on_target_selected(world_pos: Vector3) -> void:
	if _current_step != "click_monos":
		return
	var monos_pos := _layout_position("MonosStart", MONOS_POS)
	var dist_to_monos := Vector2(world_pos.x - monos_pos.x, world_pos.z - monos_pos.z).length()
	if dist_to_monos < 2.5:
		if _player.ground_clicked.is_connected(_on_target_selected):
			_player.ground_clicked.disconnect(_on_target_selected)
		_player.set_click_mode("move")
		_tutorial_prompt.hide_prompt()
		_start_confirm_protect()
	else:
		_show_correction("peris_sim.correct.target_monos")

func _toggle_pause() -> void:
	# Only allow unpause at the confirm_protect step
	if _current_step == "confirm_protect":
		_start_executing()
		return
	# Correction: trying to unpause during the ordered tutorial
	if _current_step in ["alert_monos", "protect_prompt", "run_prompt", "click_monos"]:
		_show_correction("peris_sim.correct.not_yet")
		return
	_is_paused = not _is_paused
	if _hud:
		_hud.set_paused(_is_paused)

func _on_pause_toggled(is_paused: bool) -> void:
	if _current_step == "confirm_protect" and not is_paused:
		_start_executing()
		return
	if _current_step in ["alert_monos", "protect_prompt", "run_prompt", "click_monos"]:
		_show_correction("peris_sim.correct.not_yet")
		return
	_is_paused = is_paused

func _toggle_run() -> void:
	if _game_state == null:
		return
	# Run is only valid at run_prompt.
	if _current_step == "run_prompt":
		_has_sprinted = true
		_game_state.set_running("peris", true)
		_player.set_running(true)
		_start_click_monos()
		return
	if _current_step == "protect_prompt":
		_has_sprinted = true
		_game_state.set_running("peris", true)
		_player.set_running(true)
		_show_thought(DialogueData.text("peris_sim.protect_remind"))
		return
	if _current_step in ["alert_monos", "click_monos", "confirm_protect"]:
		return
	# Normal run toggle.
	_game_state.toggle_running("peris")
	var now_running := _game_state.is_running("peris")
	if now_running:
		_has_sprinted = true
	_player.set_running(now_running)

func _show_correction(key: String) -> void:
	_show_thought(DialogueData.text(key))

# --- Event-driven steps ---

func _start_workspace() -> void:
	_enter_step("workspace")
	_player.set_move_enabled(true)
	# Phase 1 wanders the room while the new client's session stalls; the
	# exploration gate is where the spoofed signal finally breaks through.
	_show_thought(DialogueData.text("peris.sim_expand.opening.line"))
	_build_exploration_objects()   # idempotent — the room was dressed at _begin
	_reset_care_context_progress()
	_set_exploration_armed(true)   # the wander step is where the room becomes touchable
	_explore_gate_unlocked = false
	_explore_gate_fired = false
	_explore_time_elapsed = false
	_publish_peris_phase(PERIS_PHASE_EXPLORATION)
	# Teach the reveal-all overlay while the player is hunting the room for what to interact with.
	# UI lane so the hint shows even if gameplay is paused, and speeds with hold-F like the rest.
	_ui_scheduler.schedule_after(2.5, _show_exploration_highlight_hint, "highlight_hint")
	_unlock_exploration_gate()


func _show_exploration_highlight_hint() -> void:
	if _tutorial_prompt != null and _current_step == "workspace":
		_tutorial_prompt.show_action_prompt(
			"highlight", "Reveal interactions", 4.0, "Shift")

func _unlock_exploration_gate() -> void:
	# The logbook is the progression gate. Plants and room documents remain optional
	# characterization reads and never become a prerequisite checklist.
	_explore_time_elapsed = true
	_maybe_unlock_exploration_gate()
	_publish_peris_observation_state()

func _reset_care_context_progress() -> void:
	_care_context_completed.clear()
	for category in CARE_CONTEXT_REQUIRED:
		_care_context_completed[category] = false
	_care_context_zone_visits.clear()
	_care_context_plant_group = ""
	_care_context_ready = false

func _care_context_completed_count() -> int:
	var completed := _care_context_plant_groups_completed_count()
	for category in ["painting", "wellness", "strike_warning"]:
		if bool(_care_context_completed.get(category, false)):
			completed += 1
	return completed

func _care_context_plant_groups_completed_count() -> int:
	var completed := 0
	for branch_id in CARE_CONTEXT_PLANT_BRANCHES:
		if int(_care_context_zone_visits.get(branch_id, 0)) > 0:
			completed += 1
	return completed

func _care_context_total_required_count() -> int:
	return CARE_CONTEXT_PLANT_BRANCHES.size() + 3

func _care_context_complete() -> bool:
	return _care_context_completed_count() == _care_context_total_required_count()

func _register_care_context_zone(zone: Node, category: String, branch_id: String) -> void:
	if zone == null or not zone.has_signal("interacted"):
		return
	var callback := Callable(self, "_on_care_context_zone_interacted").bind(category, branch_id)
	if not zone.is_connected("interacted", callback):
		zone.connect("interacted", callback)

func _on_care_context_zone_interacted(category: String, branch_id: String) -> void:
	if _visit_phase != 1 or _current_step != "workspace" or not CARE_CONTEXT_REQUIRED.has(category):
		return
	var visit_key := branch_id if branch_id != "" else category
	_care_context_zone_visits[visit_key] = int(_care_context_zone_visits.get(visit_key, 0)) + 1
	_care_context_completed[category] = true
	if category == "plant" and _care_context_plant_group == "":
		_care_context_plant_group = branch_id
	# These counters are observation telemetry only. Re-reading or skipping any
	# room object cannot delay opening Monos's file.
	_publish_peris_observation_state()

func _on_exploration_gate_interacted() -> void:
	if not _explore_gate_unlocked or _explore_gate_fired:
		return
	_explore_gate_fired = true
	_publish_peris_observation_state()
	_hide_thought()
	_start_monos_breakthrough()

func _face_peris_to_portal() -> void:
	if _player == null:
		return
	var panel := _portal_panel_position()
	var target := Vector3(panel.x, _player.global_position.y, panel.z)
	if target.distance_to(_player.global_position) > 0.1:
		_player.look_at(target, Vector3.UP)

func _start_monos_breakthrough() -> void:
	_enter_step("monos_breakthrough")
	_face_peris_to_portal()
	_monos.visible = true
	_portal_light.light_color = Color(0.9, 0.6, 0.3)
	_portal_light.light_energy = 3.0
	_publish_peris_phase(PERIS_PHASE_FIRST_DIALOGUE)
	_present_first_visit_dialogue()


func _present_first_visit_dialogue() -> void:
	_monos.visible = true
	_face_peris_to_portal()
	_portal_light.light_color = Color(0.9, 0.6, 0.3)
	_portal_light.light_energy = 3.0
	_dialogue_chain([
		"peris_sim.monos.late",
		"peris_sim.peris.purpose",
		"peris_sim.monos.turn",
		"peris_sim.monos.opening",
		"peris_sim.monos.real",
		"peris_sim.monos.heart",
		"peris_sim.monos.mind",
		"peris_sim.peris.fight",
	], _on_first_visit_dialogue_finished)


func _on_first_visit_dialogue_finished() -> void:
	var authority := _publish_peris_phase(
		PERIS_PHASE_FIRST_HANDOFF_WAIT,
		_scheduler.get_current_tick() + PERIS_FIRST_HANDOFF_DELAY)
	_arm_peris_authority_deadline(authority)

func _start_session_begins() -> void:
	_enter_step("session_begins")
	_restore_session_lead_presenter()
	var authority := _publish_peris_phase(
		PERIS_PHASE_SESSION_LEAD,
		_scheduler.get_current_tick() + PERIS_SESSION_LEAD_DURATION)
	_arm_peris_authority_deadline(authority)


func _restore_session_lead_presenter() -> void:
	_monos.visible = true
	_face_peris_to_portal()
	_portal_tween_active = true
	var t := create_tween()
	t.tween_property(_portal_light, "light_energy", 4.0, 0.4)
	t.tween_property(_portal_light, "light_energy", 3.0, 0.6)
	t.tween_callback(_finish_portal_tween)


func _finish_portal_tween() -> void:
	_portal_tween_active = false

func _start_attack() -> void:
	_enter_step("attack")
	_publish_peris_phase(PERIS_PHASE_ATTACK_DIALOGUE)
	_present_attack_dialogue()


func _present_attack_dialogue() -> void:
	_monos.visible = true
	_attack_particles.visible = true
	_attack_particles.light_color = Color(0.9, 0.15, 0.05)
	_attack_particles.light_energy = 5.0
	_portal_light.light_color = Color(0.8, 0.2, 0.1)
	_camera.shake(0.15, 6.0)
	DialogueData.say_to(_dialogue, "peris_sim.monos.hit")
	DialogueData.say_to(_dialogue, "peris_sim.peris.alarm")
	DialogueData.say_to(_dialogue, "peris_sim.monos.help")
	DialogueData.say_to(_dialogue, "peris_sim.system.overtime")
	_dialogue.dialogue_finished.connect(_on_attack_dialogue_finished, CONNECT_ONE_SHOT)


func _on_attack_dialogue_finished() -> void:
	_start_alert_monos()

# --- Strict ordered tutorial sequence ---

func _start_alert_monos() -> void:
	_enter_step("alert_monos")
	_start_protect_prompt()

func _start_protect_prompt() -> void:
	_enter_step("protect_prompt")
	_is_paused = true
	_player.set_move_enabled(false)
	_publish_peris_phase(PERIS_PHASE_WRAP_PROMPT)
	_restore_wrap_prompt_presenter()


func _restore_wrap_prompt_presenter() -> void:
	var alert := _monos.get_node_or_null("AlertMark") as Label3D
	if alert == null:
		alert = Label3D.new()
		alert.name = "AlertMark"
		alert.text = "!"
		alert.font_size = 72
		alert.pixel_size = 0.012
		alert.modulate = Color(1, 1, 1, 0.95)
		alert.outline_modulate = Color(0, 0, 0, 0.6)
		alert.outline_size = 5
		alert.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		alert.position = Vector3(0, 1.8, 0)
		_monos.add_child(alert)
	_is_paused = true
	_restore_peris_move_input(false)
	if _hud:
		_hud.set_paused(true)
	DialogueData.say_to(_dialogue, "peris_sim.peris.protect_him")
	_dialogue.dialogue_finished.connect(_show_wrap_queue_prompt, CONNECT_ONE_SHOT)


func _show_wrap_queue_prompt() -> void:
	_tutorial_prompt.show_action_prompt(
		WRAP_INPUT_ACTION,
		"Queue Wrap",
		0.0,
		str(AbilityData.binding(WRAP_ABILITY_ID).get("keybind", ""))
	)

func _start_run_prompt() -> void:
	_enter_step("run_prompt")
	_publish_peris_phase(PERIS_PHASE_WRAP_QUEUED)
	_restore_wrap_queued_presenter()


func _restore_wrap_queued_presenter() -> void:
	_is_paused = true
	_restore_peris_move_input(false)
	_tutorial_prompt.show_action_prompt("run", "Toggle Run", 0.0, "R")
	if _hud:
		_hud.set_paused(true)
		_hud.set_ability_state(WRAP_ABILITY_ID, "queued")
		_hud.show_run_toggle(true)

func _start_click_monos() -> void:
	_enter_step("click_monos")
	_publish_peris_phase(PERIS_PHASE_WRAP_TARGETING)
	_restore_wrap_targeting_presenter()


func _restore_wrap_targeting_presenter() -> void:
	_is_paused = true
	_restore_peris_move_input(true)
	# Clicks select a target rather than move; the shared controller reports the
	# clicked ground position to _on_target_selected.
	_player.set_click_mode("select")
	if not _player.ground_clicked.is_connected(_on_target_selected):
		_player.ground_clicked.connect(_on_target_selected)
	_tutorial_prompt.show_action_prompt("select", "Select Monos as Wrap target", 0.0, "LMB")

func _start_confirm_protect() -> void:
	_enter_step("confirm_protect")
	_protect_queued = true
	_publish_peris_phase(PERIS_PHASE_WRAP_TARGETED)
	_restore_wrap_targeted_presenter()


func _restore_wrap_targeted_presenter() -> void:
	_is_paused = true
	_restore_peris_move_input(false)
	_player.set_click_mode("move")
	var shield := _monos.get_node_or_null("ShieldMark") as Label3D
	if shield == null:
		shield = Label3D.new()
		shield.name = "ShieldMark"
		shield.text = "SHIELD"
		shield.font_size = 36
		shield.pixel_size = 0.01
		shield.modulate = Color(0.8, 0.6, 0.2, 0.9)
		shield.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		shield.position = Vector3(0, 2.2, 0)
		_monos.add_child(shield)
	if _hud:
		_hud.set_paused(true)
		_hud.set_ability_state(WRAP_ABILITY_ID, "queued")
	_tutorial_prompt.show_action_prompt("pause", "Unpause", 0.0, "Space")

func _start_executing() -> void:
	_enter_step("executing")
	_is_paused = false
	_restore_wrap_executing_presenter()
	var wrap := _peris_wrap_authority()
	if wrap.is_empty():
		wrap = (_baseline_peris_authority(2).get("wrap", {}) as Dictionary).duplicate(true)
	_publish_peris_phase(PERIS_PHASE_WRAP_QUEUE_PENDING, -1.0, {"wrap": wrap})
	_issue_wrap_queue_from_authority()


func _restore_wrap_executing_presenter() -> void:
	_is_paused = false
	if _hud:
		_hud.set_paused(false)
	_tutorial_prompt.hide_prompt()
	_hide_thought()
	_restore_peris_move_input(true)
	_player.set_click_mode("move")
	_protect_queued = false

func _on_protect_pressed() -> void:
	if _has_protected:
		return
	# The direct Peris ability slot is only valid at protect_prompt.
	if _current_step == "protect_prompt":
		_tutorial_prompt.hide_prompt()
		if _hud:
			_hud.set_ability_state(WRAP_ABILITY_ID, "queued")
		_start_run_prompt()
		return
	if _current_step in ["alert_monos", "run_prompt", "click_monos", "confirm_protect"]:
		return

func _fire_queued_protect() -> void:
	# Compatibility seam for old tests/replays. Production progression follows
	# GameState.ability_fired, which survives queued-ability reconstruction.
	_commit_wrap_cast_authority()

func _start_aftermath() -> void:
	_enter_step("aftermath")
	_publish_peris_phase(PERIS_PHASE_AFTERMATH)
	_present_aftermath_dialogue()


func _present_aftermath_dialogue() -> void:
	_attack_particles.visible = false
	_portal_light.light_color = Color(0.8, 0.6, 0.3)
	_portal_light.light_energy = 2.0
	DialogueData.say_to(_dialogue, "peris_sim.monos.thanks")
	_dialogue.dialogue_finished.connect(_on_aftermath_dialogue_finished, CONNECT_ONE_SHOT)


func _on_aftermath_dialogue_finished() -> void:
	_start_efficiency_log()

func _start_efficiency_log() -> void:
	_enter_step("efficiency_log")
	_efficiency_score = 62.0
	_publish_peris_phase(PERIS_PHASE_EFFICIENCY_LOG)
	_present_efficiency_log()


func _present_efficiency_log() -> void:
	_restore_efficiency_log_presenter()
	DialogueData.say_to(_dialogue, "peris_sim.system.complete")
	_dialogue.dialogue_finished.connect(_on_efficiency_log_dialogue_finished, CONNECT_ONE_SHOT)


func _restore_efficiency_log_presenter() -> void:
	_monos.fade_out(1.5)
	# Sync portal closure with Monos fade.
	_portal_tween_active = true
	var t := create_tween()
	t.tween_property(_portal_light, "light_energy", 0.0, 1.5)
	t.parallel().tween_property(_portal_visual, "scale", Vector3(1.0, 0.0, 1.0), 1.5)
	t.tween_callback(_finish_portal_tween)


func _on_efficiency_log_dialogue_finished() -> void:
	var authority := _publish_peris_phase(
		PERIS_PHASE_EFFICIENCY_LOG,
		_scheduler.get_current_tick() + PERIS_EFFICIENCY_CLOSE_DELAY)
	_arm_peris_authority_deadline(authority)

func _start_sanction_notice() -> void:
	_enter_step("sanction_notice")
	_publish_peris_phase(PERIS_PHASE_SANCTION_NOTICE)
	_present_sanction_notice()


func _present_sanction_notice() -> void:
	_show_sanction_feed_visual(
		"SANCTION MODE",
		"CLIENT FEED DISCONNECTED\nCASELOAD REASSIGNED",
		Color(0.75, 0.82, 0.7)
	)
	DialogueData.say_to(_dialogue, "peris_sim.system.sanction_notice")
	_dialogue.dialogue_finished.connect(_on_sanction_notice_finished, CONNECT_ONE_SHOT)


func _on_sanction_notice_finished() -> void:
	_start_sanction_feed()

func _start_sanction_feed() -> void:
	_enter_step("sanction_feed")
	_publish_peris_phase(PERIS_PHASE_SANCTION_FEED)
	_present_sanction_feed()


func _present_sanction_feed() -> void:
	_show_sanction_feed_visual(
		"RESTORATIVE MODE",
		"GEL LOOP\nSOAP LOOP\nPLANT TIMELAPSE",
		Color(0.6, 0.85, 0.78)
	)
	DialogueData.say_to(_dialogue, "peris_sim.system.wellness_feed")
	DialogueData.say_to(_dialogue, "peris_sim.peris.sanction_reaction")
	_dialogue.dialogue_finished.connect(_on_sanction_feed_finished, CONNECT_ONE_SHOT)


func _on_sanction_feed_finished() -> void:
	_start_spiral_flash()

func _start_spiral_flash() -> void:
	_enter_step("spiral_flash")
	_publish_peris_phase(PERIS_PHASE_SPIRAL_FLASH)
	_present_spiral_flash()


func _present_spiral_flash() -> void:
	_show_sanction_feed_visual(
		"FRAME DROP",
		"SPIRAL SIGNAL DETECTED",
		Color(0.55, 0.65, 1.0)
	)
	DialogueData.say_to(_dialogue, "peris_sim.system.spiral_flash")
	_dialogue.dialogue_finished.connect(_on_spiral_flash_finished, CONNECT_ONE_SHOT)


func _on_spiral_flash_finished() -> void:
	_start_retro()

func _start_retro() -> void:
	_enter_step("retro")
	_publish_peris_phase(PERIS_PHASE_RETRO)
	_present_retro()


func _present_retro() -> void:
	_show_sanction_feed_visual(
		"RESTORATIVE MODE",
		"ARCHIVE FOOTAGE",
		Color(0.68, 0.78, 0.72)
	)
	DialogueData.say_to(_dialogue, "peris_sim.peris.retro")
	_dialogue.dialogue_finished.connect(_on_retro_finished, CONNECT_ONE_SHOT)


func _on_retro_finished() -> void:
	_start_sim_bay_exit()

func _start_sim_bay_exit() -> void:
	_enter_step("sim_bay_exit")
	_player.set_move_enabled(false)
	_publish_peris_phase(PERIS_PHASE_SIM_BAY_EXIT)
	_present_sim_bay_exit()


func _present_sim_bay_exit() -> void:
	_restore_peris_move_input(false)
	if _sanction_feed_label:
		_sanction_feed_label.visible = false
	DialogueData.say_to(_dialogue, "peris_sim.worker.okay")
	DialogueData.say_to(_dialogue, "peris_sim.worker.medical")
	_dialogue.dialogue_finished.connect(_on_sim_bay_exit_finished, CONNECT_ONE_SHOT)


func _on_sim_bay_exit_finished() -> void:
	_start_transition_out()

func _start_transition_out() -> void:
	_enter_step("transition_out")
	_player.set_move_enabled(false)
	_fade_start_tick = _scheduler.get_current_tick()
	var destination := "res://scenes/tutorial/aster_sim.tscn" \
		if _visit_phase == 1 else "res://scenes/tutorial/tag_day.tscn"
	var authority := _publish_peris_phase(
		PERIS_PHASE_TRANSITION,
		_scheduler.get_current_tick() + PERIS_TRANSITION_DURATION,
		{"destination": destination})
	_arm_peris_authority_deadline(authority)

func _complete() -> void:
	var authority := _peris_authority_state()
	if str(authority.get("phase", "")) != PERIS_PHASE_TRANSITION:
		return
	var finishing_visit := _visit_phase
	var destination := str(authority.get(
		"destination",
		"res://scenes/tutorial/aster_sim.tscn" if finishing_visit == 1 \
			else "res://scenes/tutorial/tag_day.tscn"))
	# Wrap's finite shield belongs to the simulation session. Retire its derived expiry
	# callback before the session handoff so no disposable sim effect or stale wake-up
	# survives into the next scene/save boundary.
	if _game_state != null and _game_state.get_damage_shield("monos") > 0.0:
		_game_state.clear_damage_shield("monos")
	_enter_step("complete")
	if finishing_visit == 1:
		# First half opens the game, then hands off to Aster's sim.
		_visit_phase = 2
		_publish_peris_campaign_progress(false)
	else:
		_publish_peris_campaign_progress(true)
	_publish_peris_phase(PERIS_PHASE_COMPLETE, -1.0, {"destination": destination})
	_change_scene_or_record(destination)

# Run/pause/Wrap keys arrive as HUD signals (run_toggled / pause_toggled /
# ability_pressed), mapped from the input map by GameHUD — see _setup_ui.

# --- Environment ---

## ScenePlacement retains measured fallback/approach markers. Visible placement is owned by the
## editor-authored nodes under PerisRoom.
func get_room_layout_problems() -> Array[String]:
	return _room_layout_problems.duplicate()


func _validate_room_plan() -> void:
	var placement := find_child(PLACEMENT_ROOT, true, false)
	if placement == null:
		_room_layout_problems.append("ScenePlacement floor plan is missing")
		return
	var room_plan := placement.find_child("RoomPlan", true, false)
	if room_plan == null:
		_room_layout_problems.append("RoomPlan measurement guide is missing")
	elif "room_size" in room_plan:
		var measured_size: Vector2 = room_plan.get("room_size")
		if not measured_size.is_equal_approx(Vector2(GRID_SIZE)):
			_room_layout_problems.append("RoomPlan is %s but the movement grid is %s" % [measured_size, GRID_SIZE])

	for marker_name in REQUIRED_ROOM_MARKERS:
		var marker := placement.find_child(marker_name, true, false) as Node3D
		if marker == null:
			_room_layout_problems.append("missing placement marker '%s'" % marker_name)
			continue
		var p := marker.global_position
		if p.x < 0.0 or p.x > GRID_SIZE.x or p.z < 0.0 or p.z > GRID_SIZE.y:
			_room_layout_problems.append("marker '%s' is outside the 14 m x 6 m room at %s" % [marker_name, p])
		var grid_axes: String = WALL_MOUNTED_GRID_AXES.get(marker_name, "xz")
		var is_off_grid := (grid_axes.contains("x") and not _is_room_grid_value(p.x)) \
			or (grid_axes.contains("z") and not _is_room_grid_value(p.z))
		if is_off_grid:
			_room_layout_problems.append("marker '%s' is off the %.1f m X/Z grid at %s" % [
				marker_name, ROOM_GRID_STEP, p])
		if marker.get_parent() != null and marker.get_parent().name == "FurnitureMarkers":
			var quarter_turns := marker.global_transform.basis.get_euler().y / (PI * 0.5)
			if absf(quarter_turns - roundf(quarter_turns)) > 0.001:
				_room_layout_problems.append("furniture marker '%s' is not aligned to a 90-degree axis" % marker_name)

	var room := find_child("PerisRoom", true, false) as Node3D
	if room == null:
		_room_layout_problems.append("authored PerisRoom node is missing")
	else:
		for node_name in REQUIRED_AUTHORED_ROOM_NODES:
			if room.find_child(node_name, true, false) == null:
				_room_layout_problems.append("missing editor-authored room node '%s'" % node_name)

	var monos := placement.find_child("MonosStart", true, false) as Node3D
	var protect := placement.find_child("PortalStand", true, false) as Node3D
	if monos != null and protect != null:
		var monos_cell := Vector2i(floori(monos.global_position.x), floori(monos.global_position.z))
		var protect_cell := Vector2i(floori(protect.global_position.x), floori(protect.global_position.z))
		if monos_cell == protect_cell:
			_room_layout_problems.append("MonosStart and PortalStand reserve the same grid cell %s" % monos_cell)


func _is_room_grid_value(value: float) -> bool:
	return absf(value / ROOM_GRID_STEP - roundf(value / ROOM_GRID_STEP)) <= 0.001

func _build_environment() -> void:
	# Static geometry, props, collision, and lighting live in peris_sim.tscn. Runtime setup only
	# validates and binds those authored nodes; it never creates a second invisible layout.
	_room_layout_problems.clear()
	_validate_room_plan()
	for problem in _room_layout_problems:
		push_warning("Peris room layout: %s" % problem)

# --- Portal ---

## The modeled portal is the wall-mounted frame; this builds only the GAMEPLAY portal layer
## (the morphing glow/light/attack flash and labels the session steps drive), in front of it.
func _build_portal() -> void:
	# The gameplay layers inherit the editor-authored portal transform.
	var portal_panel := _portal_panel_position()
	var portal_face := _portal_face()
	var portal_surface := portal_panel + portal_face * 0.10

	_portal_visual = MeshInstance3D.new()
	_portal_visual.name = "PortalGlowSurface"
	# The gameplay glow layer is a RING hugging the circular frame (the session/attack/sanction
	# flash colour), leaving the whole disc inside it free for the live view.
	var pv := TorusMesh.new()
	pv.inner_radius = 1.2
	pv.outer_radius = 1.42
	_portal_visual.mesh = pv
	var pvm := StandardMaterial3D.new()
	pvm.albedo_color = Color(0.8, 0.5, 0.2, 0.25)
	pvm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pvm.emission_enabled = true
	pvm.emission = Color(0.6, 0.35, 0.15)
	pvm.emission_energy_multiplier = 1.2
	pvm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_portal_visual.material_override = pvm
	# TorusMesh lies flat around Y; pitch it so the ring stands in the portal plane.
	_portal_visual.global_transform = Transform3D(
		_portal_basis() * Basis(Vector3.RIGHT, PI * 0.5), portal_surface)
	add_child(_portal_visual)

	_portal_light = OmniLight3D.new()
	_portal_light.position = portal_panel + portal_face * 0.5
	_portal_light.light_color = Color(0.8, 0.5, 0.25)
	_portal_light.light_energy = 1.5
	_portal_light.omni_range = 5.0
	add_child(_portal_light)

	_build_portal_view()

	_attack_particles = OmniLight3D.new()
	_attack_particles.position = _layout_position("MonosStart", MONOS_POS) + Vector3(0, 1.0, 0)
	_attack_particles.light_color = Color(0.9, 0.15, 0.05)
	_attack_particles.light_energy = 0
	_attack_particles.omni_range = 4.0
	_attack_particles.visible = false
	add_child(_attack_particles)

	var lbl := Label3D.new()
	lbl.text = "FEED TERMINAL"
	lbl.font_size = 22
	lbl.pixel_size = 0.006
	# Keep this as signage attached to the portal, not a screen-space banner that
	# grows over the entire room when the camera pulls back.
	lbl.fixed_size = false
	lbl.modulate = Color(0.7, 0.5, 0.3, 0.6)
	lbl.position = portal_surface + Vector3(0, 1.95, 0)  # clear of the frame ring's top arc
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(lbl)

	_sanction_feed_label = Label3D.new()
	_sanction_feed_label.name = "SanctionFeedLabel"
	_sanction_feed_label.text = ""
	_sanction_feed_label.font_size = 28
	_sanction_feed_label.pixel_size = 0.009
	_sanction_feed_label.modulate = Color(0.6, 0.85, 0.78, 0.95)
	_sanction_feed_label.outline_modulate = Color(0.03, 0.04, 0.03, 0.8)
	_sanction_feed_label.outline_size = 4
	_sanction_feed_label.position = portal_surface + portal_face * 0.1
	_sanction_feed_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sanction_feed_label.visible = false
	add_child(_sanction_feed_label)

## The portal actually SHOWS what's through it: a SubViewport with its OWN World3D renders the connected
## room — where Monos stands — and that live view is textured onto the portal surface. Its own world keeps
## it fully self-contained (a true portal to ELSEWHERE, not a security-camera of this room), so there's no
## coupling to the main camera, no feedback, and Monos is visible through the portal before he steps through.
func _build_portal_view() -> void:
	_portal_view_vp = SubViewport.new()
	_portal_view_vp.name = "PortalViewViewport"
	_portal_view_vp.size = Vector2i(512, 512)    # resized to the live window each frame
	_portal_view_vp.own_world_3d = true          # a separate space beyond the portal
	_portal_view_vp.transparent_bg = false
	_portal_view_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_portal_view_vp.handle_input_locally = false
	add_child(_portal_view_vp)
	_build_monos_room(_portal_view_vp)

	# The modeled circular Portal_Surface disc IS the lens: the live view fills the whole
	# portal opening instead of a pasted quad. SCREEN_UV sampling + the mirrored viewport
	# camera make it read as a hole in the wall.
	var lens: MeshInstance3D = null
	var portal := _authored_room_node("Portal")
	if portal != null:
		for mi in portal.find_children("*", "MeshInstance3D", true, false):
			if String(mi.name).begins_with("Portal_Surface"):
				lens = mi
				break
	if lens == null:
		# Stripped test scenes have no modeled portal; a disc stands in so the layer exists.
		lens = MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 1.14
		disc.bottom_radius = 1.14
		disc.height = 0.02
		lens.mesh = disc
		lens.global_transform = Transform3D(
			_portal_basis() * Basis(Vector3.RIGHT, PI * 0.5),
			_portal_panel_position() - _portal_face() * 0.02)
		add_child(lens)
	lens.name = "PortalViewSurface"
	var mat := ShaderMaterial.new()
	mat.shader = PORTAL_LENS_SHADER
	mat.set_shader_parameter("view_texture", _portal_view_vp.get_texture())
	lens.material_override = mat
	_portal_view_surface = lens

## Mirrors the live camera through the portal into the Monos-room world so the lens disc
## shows the connected room with true parallax. Rendering-only: nothing gameplay reads it.
func _update_portal_view() -> void:
	if _portal_view_vp == null or _portal_view_cam == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var vp_size := Vector2i(get_viewport().get_visible_rect().size)
	if vp_size.x > 0 and vp_size.y > 0 and _portal_view_vp.size != vp_size:
		_portal_view_vp.size = vp_size
	var portal_xf := Transform3D(_portal_basis(), _portal_panel_position())
	var anchor := Transform3D(Basis(), MONOS_ROOM_PORTAL_ANCHOR)
	_portal_view_cam.fov = cam.fov
	_portal_view_cam.global_transform = anchor * (portal_xf.affine_inverse() * cam.global_transform)

## The space BEYOND the portal — a small graybox room with Monos standing in it, lit so it reads through
## the portal. Built into the SubViewport's own world. Stand-in geometry for now; swap for the real
## modeled facility room when it exists.
func _build_monos_room(vp: SubViewport) -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 2.5, 6.0)
	vp.add_child(cam)
	cam.look_at(Vector3(0.0, 1.6, -2.0), Vector3.UP)   # orient AFTER it's in the tree (look_at needs a global xform)
	_portal_view_cam = cam   # per-frame mirror of the live camera (rendering-only)
	# Lighting for the fresh world (no scene env): cool ambient + a key light, matching Peris's room mood.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.06, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.42, 0.52)
	e.ambient_light_energy = 1.0
	env.environment = e
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(35.0), 0.0)
	key.light_color = Color(0.95, 0.88, 0.8)
	key.light_energy = 1.1
	vp.add_child(key)
	# Floor + back wall + side wall (graybox).
	var visual := MONOS_PORTAL_ROOM_VISUAL_SCENE.instantiate() as Node3D
	visual.name = "MonosPortalRoomVisual"
	vp.add_child(visual)
	# Monos stands at his console; a warm key over him makes the figure read
	# through the lens from gameplay camera angles.
	var glow := OmniLight3D.new()
	glow.position = Vector3(0.9, 2.2, -2.0)
	glow.light_color = Color(0.9, 0.62, 0.35)
	glow.light_energy = 2.6
	glow.omni_range = 5.0
	vp.add_child(glow)

func _show_sanction_feed_visual(title: String, body: String, color: Color) -> void:
	if _sanction_feed_label:
		_sanction_feed_label.text = "%s\n%s" % [title, body]
		_sanction_feed_label.modulate = Color(color.r, color.g, color.b, 0.95)
		_sanction_feed_label.visible = true
	if _portal_visual:
		_portal_visual.scale = Vector3.ONE
		var mat := _portal_visual.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(color.r, color.g, color.b, 0.3)
			mat.emission = color
			mat.emission_energy_multiplier = 1.8
	if _portal_light:
		_portal_light.light_color = color
		_portal_light.light_energy = 2.4

# --- Exploration objects (phase 1, pre-Monos-arrival) ---
# The modeled room (peris-sim.gltf + peris-furniture.gltf) carries all cosmetic decor — rug, shelves,
# sofas, props — so there is no procedural decoration pass; gameplay objects live below.

var _exploration_objects_built := false
var _exploration_interactables: Array = []

func _build_exploration_objects() -> void:
	# Idempotent: built at _begin (the room is dressed from the first frame); a direct
	# _start_workspace (tests) re-enters harmlessly. The watering beat is a REAL data-layer item,
	# so it exists only in the phase that plays it.
	if Engine.is_editor_hint() or _exploration_objects_built:
		return
	_exploration_objects_built = true
	var env: Node3D = self
	_build_peris_plants(env)
	if _visit_phase == 1:
		_build_watering_beat(env)
	else:
		var authored_can := _authored_room_node("WateringCan")
		if authored_can != null:
			authored_can.visible = false
	_build_peris_painting(env)
	_build_peris_wellness_feed(env)
	_build_peris_strike_warning(env)
	_build_peris_logbook_gate(env)
	# built before the workspace step: everything stays dark until the step arms it
	_set_exploration_armed(false)

func _set_exploration_armed(armed: bool, restoring := false) -> void:
	_exploration_armed = armed
	for ia in _exploration_interactables:
		if ia != null and is_instance_valid(ia) and ia.has_method("set_interaction_enabled"):
			if ia in [_water_plant_interactable, _can_pickup_interactable,
					_fern_exploration_interactable]:
				continue
			var enable := armed
			if ia == _explore_logbook_gate:
				# Opening Monos's file is the canonical progression gate; every
				# other room interaction is optional worldbuilding.
				enable = armed
			_set_interactable_projection(ia, enable, restoring)
	_refresh_watering_interactions(restoring)

func _build_peris_plants(parent: Node3D) -> void:
	# Visual plants and tables are scene-authored. Runtime creates only their verbs and derives
	# collision/interaction positions from the movable nodes.
	var care_groups := ["shelf", "shelf", "client", "survivor", "shelf", "survivor", "fern", "client", "peace"]
	for i in range(care_groups.size()):
		var plant_number := i + 1
		var table := _authored_room_node("Plant%dTable" % plant_number)
		var plant_node := _authored_room_node("Plant%d" % plant_number)
		if table == null or plant_node == null:
			push_warning("Peris room is missing editor-authored Plant%d/table nodes" % plant_number)
			continue
		var table_pos := table.global_position
		if _grid != null:
			_grid.add_dynamic_blocker(_grid.world_to_grid(table_pos), "peris_plant_table_%d" % plant_number)

		var target := _outline_object_meshes(parent, "Plant%dOutline" % plant_number,
			_collect_mesh_instances(plant_node), "peris_plant_%d" % plant_number, 0.7)

		# The zone lives on the floor under the display — an elevated support (hanging basket,
		# bookshelf tray) must still meet the walking character's proximity dwell.
		var zone_pos := Vector3(table_pos.x, ROOM_FLOOR_Y, table_pos.z)
		var zone_name := "Plant%dZone" % plant_number
		var zone: Area3D
		if plant_number == 7:
			zone = _make_exploration_sequence_zone(parent, zone_pos, zone_name,
				["peris.sim_expand.plant_7.line", "peris.sim_expand.plant_7.line_repeat"], 0.7, 0.6)
		else:
			zone = _make_exploration_zone(parent, zone_pos, zone_name,
				"peris.sim_expand.plant_%d.line" % plant_number, 0.7, 0.6)
		zone.set_meta("interaction_target_position", _authored_floor_interaction_position(
			"Plant%dTable" % plant_number,
			"Plant%dApproach" % plant_number,
			Vector3(table_pos.x, 0.0, table_pos.z - 1.0),
			Vector3(0.0, 0.0, -1.0)
		))
		_exploration_interactables.append(zone)
		_register_care_context_zone(zone, "plant", str(care_groups[i]))
		_set_room_target_interaction_delegate(target, zone)
		if plant_number == 7:
			_fern_exploration_interactable = zone
			_fern_outline_target = target


## The watering can is a REAL item (spawn_item + pick_up_item), not a flag: the beat teaches the
## hand-slot inventory. The dry fern's water spot only accepts a character actually HOLDING it.
func _build_watering_beat(parent: Node3D) -> void:
	# The can sits on the floor beside Peris's kiosk, mirrored by a data-layer item. Separating it
	# from the fern turns the beat back into an actual carry instead of two overlapping auto-dwells.
	var can_pos := _authored_position("WateringCan", "WateringCanAnchor", WATERING_CAN_POS)
	var fern_pos := _authored_position("Plant7Table", "Plant7TableAnchor", FERN_POS)
	_watering_can_mesh = _authored_room_node("WateringCan")
	if _watering_can_mesh == null:
		push_warning("Peris room is missing its editor-authored WateringCan")
		return
	_watering_can_home_parent = _watering_can_mesh.get_parent()
	_watering_can_home_rotation = _watering_can_mesh.rotation
	_watering_can_home_scale = _watering_can_mesh.scale
	_watering_can_mesh.visible = true

	_watering_can_item_id = _ensure_watering_can_item(can_pos)

	_can_pickup_interactable = _create_interactable(parent, can_pos, "WateringCanPickup",
		1.25, 0.7, "PICK UP", true)
	_configure_watering_source(
		_can_pickup_interactable, WATERING_PICKUP_ACTION)
	_can_pickup_interactable.interacted.connect(
		_on_watering_can_picked.bind(_can_pickup_interactable))
	_exploration_interactables.append(_can_pickup_interactable)
	_watering_can_outline_target = _outline_object_meshes(parent, "WateringCanOutline",
		_collect_mesh_instances(_watering_can_mesh), "watering_can", 0.5)
	if _watering_can_outline_target != null:
		_watering_can_outline_offset = _watering_can_outline_target.global_position \
			- _watering_can_mesh.global_position
	_set_room_target_interaction_delegate(
		_watering_can_outline_target, _can_pickup_interactable)
	# The PICK UP prompt shows when the workspace step arms the room (the can exists from the
	# first frame, but the intro fade is not the time to advertise it).

	# The water spot sits ON the fern (Plant7).
	_water_plant_interactable = _create_interactable(parent, fern_pos, "WaterPlantSpot",
		1.8, 0.9, "WATER", true)
	_configure_watering_source(
		_water_plant_interactable, WATERING_USE_ACTION)
	_water_plant_interactable.interacted.connect(
		_on_plant_watered.bind(_water_plant_interactable))
	_exploration_interactables.append(_water_plant_interactable)
	_initialize_watering_authority()
	_wire_watering_authority_signals()
	_sync_watering_can_presenter()
	_refresh_watering_interactions()


func _configure_watering_source(source: Node, action_id: String) -> void:
	if not is_instance_valid(source):
		return
	source.set_meta("watering_action_id", action_id)
	source.set("one_shot", true)
	source.set("required_character", "peris")
	source.set_pre_trigger_validator(
		_validate_watering_source_trigger.bind(action_id, source))


func _watering_source_for_action(action_id: String) -> Node:
	if action_id == WATERING_PICKUP_ACTION:
		return _can_pickup_interactable
	if action_id == WATERING_USE_ACTION:
		return _water_plant_interactable
	return null


func _watering_action_ids() -> Array[String]:
	return [WATERING_PICKUP_ACTION, WATERING_USE_ACTION]


func _validate_watering_source_trigger(
		source: Node, actor: String, action_id: String, expected_source: Node) -> bool:
	return is_instance_valid(source) and source == expected_source \
		and _watering_source_for_action(action_id) == source \
		and _watering_actor_ready_at_source(source, actor) \
		and _watering_action_ready(action_id)


func _watering_actor_ready_at_source(source: Node, actor: String) -> bool:
	if _game_state == null or not is_instance_valid(source) or not (source is Node3D) \
			or actor != "peris" or not _game_state.characters.has(actor) \
			or not _game_state.is_narratively_available(actor) \
			or _game_state.is_downed(actor) or _game_state.is_knocked_down(actor) \
			or _game_state.is_moving(actor) or _game_state.is_resting(actor) \
			or _game_state.is_dodging(actor) or _game_state.is_endocytosing(actor) \
			or _game_state.is_external_traversal_active(actor) \
			or _game_state.is_dragging(actor) or _game_state.is_field_restoring(actor) \
			or _game_state.is_pushing(actor):
		return false
	var source_position := (source as Node3D).global_position
	if _game_state.grid != null and _game_state.grid.level_count > 1 \
			and int(_game_state.get_character_level(actor)) != int(
				_game_state.grid.level_for_y(source_position.y)):
		return false
	var actor_position := _game_state.get_position(actor)
	var radius := float(source.get("interaction_radius")) \
		+ WATERING_INTERACTION_POSITION_TOLERANCE
	return Vector2(actor_position.x, actor_position.z).distance_to(
		Vector2(source_position.x, source_position.z)) <= radius \
		and absf(actor_position.y - source_position.y) \
			<= WATERING_INTERACTION_HEIGHT_TOLERANCE


func _watering_action_ready(action_id: String) -> bool:
	if _game_state == null or not _exploration_armed:
		return false
	var item_id := _resolve_watering_can_item_id()
	if item_id == "" or not _game_state.items.has(item_id):
		return false
	var item := _game_state.items[item_id] as Dictionary
	if action_id == WATERING_PICKUP_ACTION:
		return str(item.get("location", "")) == "ground" \
			and _watering_phase() != WATERING_PHASE_ACTIVE \
			and _game_state.has_free_hands("peris", 1)
	if action_id == WATERING_USE_ACTION:
		return not _is_plant_watered_authoritatively() \
			and _watering_phase() != WATERING_PHASE_ACTIVE \
			and str(item.get("holder", "")) == "peris" \
			and str(item.get("location", "")) == "hand" \
			and _game_state.get_hand_items("peris").has(item_id)
	return false


func _watering_source_trigger_count(source: Node) -> int:
	if _game_state == null or not is_instance_valid(source):
		return -1
	var data_id := str(source.get("data_id"))
	if data_id == "" or not _game_state.has_interactable(data_id):
		return -1
	return int(_game_state.get_interactable(data_id).get("trigger_count", -1))


func _watering_source_receipt(source: Node, action_id: String) -> Dictionary:
	if not is_instance_valid(source):
		return {}
	var actor := str(source.get("active_character"))
	if not _validate_watering_source_trigger(source, actor, action_id, source) \
			or not bool(source.get("one_shot")) or not bool(source.get("_used")) \
			or bool(source.get("interaction_enabled")):
		return {}
	var data_id := str(source.get("data_id"))
	if data_id == "" or not _game_state.has_interactable(data_id):
		return {}
	var registry := _game_state.get_interactable(data_id)
	var trigger_count := int(registry.get("trigger_count", -1))
	if not bool(registry.get("one_shot", false)) \
			or not bool(registry.get("triggered", false)) \
			or bool(registry.get("enabled", true)) \
			or str(registry.get("last_trigger_character", "")) != actor \
			or trigger_count != int(
				_watering_source_committed_counts.get(action_id, 0)) + 1:
		return {}
	return {
		"action": action_id,
		"actor": actor,
		"source_data_id": data_id,
		"trigger_count": trigger_count,
	}


func _consume_watering_source_receipt(
		source: Node, action_id: String) -> Dictionary:
	var receipt := _watering_source_receipt(source, action_id)
	if receipt.is_empty():
		return {}
	_watering_source_committed_counts[action_id] = int(
		receipt.get("trigger_count", 0))
	_active_watering_source_receipt = receipt
	var current := _watering_authority_state()
	_publish_watering_receipt(
		StringName(str(current.get("phase", WATERING_PHASE_AVAILABLE))),
		_resolve_watering_can_item_id()
	)
	return receipt


func _watering_source_receipt_is_active(
		receipt: Dictionary, action_id: String, source: Node) -> bool:
	return not receipt.is_empty() \
		and receipt == _active_watering_source_receipt \
		and str(receipt.get("action", "")) == action_id \
		and str(receipt.get("actor", "")) == "peris" \
		and str(receipt.get("source_data_id", "")) == str(source.get("data_id")) \
		and int(receipt.get("trigger_count", -1)) \
			== _watering_source_trigger_count(source)


func _baseline_watering_authority() -> Dictionary:
	var counts := {}
	for action_id in _watering_action_ids():
		counts[action_id] = maxi(
			0, int(_watering_source_committed_counts.get(action_id, 0)))
	return {
		"version": WATERING_AUTHORITY_VERSION,
		"authority_id": WATERING_AUTHORITY_KEY,
		"phase": str(WATERING_PHASE_AVAILABLE),
		"item_id": _resolve_watering_can_item_id(),
		"mechanism_id": str(WATERING_PHASE_ID),
		"source_committed_counts": counts,
	}


func _initialize_watering_authority() -> void:
	if _game_state == null:
		return
	for action_id in _watering_action_ids():
		if not _watering_source_committed_counts.has(action_id):
			_watering_source_committed_counts[action_id] = maxi(
				0, _watering_source_trigger_count(
					_watering_source_for_action(action_id)))
	if _game_state.get_world_state(WATERING_AUTHORITY_KEY, null) == null:
		_game_state.set_world_state(
			WATERING_AUTHORITY_KEY, _baseline_watering_authority())


func _watering_authority_state() -> Dictionary:
	if _game_state == null:
		return {}
	var raw: Variant = _game_state.get_world_state(WATERING_AUTHORITY_KEY, null)
	if not (raw is Dictionary):
		return _baseline_watering_authority()
	var saved := (raw as Dictionary).duplicate(true)
	var version := int(saved.get("version", 0))
	if version == 1 \
			and str(saved.get("authority_id", "")) == WATERING_AUTHORITY_KEY:
		saved["version"] = WATERING_AUTHORITY_VERSION
		saved["source_committed_counts"] = {
			WATERING_PICKUP_ACTION: maxi(
				0, _watering_source_trigger_count(_can_pickup_interactable)),
			WATERING_USE_ACTION: maxi(
				0, _watering_source_trigger_count(_water_plant_interactable)),
		}
	elif version != WATERING_AUTHORITY_VERSION \
			or str(saved.get("authority_id", "")) != WATERING_AUTHORITY_KEY:
		return _baseline_watering_authority()
	var counts_v: Variant = saved.get("source_committed_counts", null)
	if not (counts_v is Dictionary):
		return _baseline_watering_authority()
	var counts := counts_v as Dictionary
	for action_id in _watering_action_ids():
		if int(counts.get(action_id, -1)) < 0:
			return _baseline_watering_authority()
	var phase := StringName(str(saved.get("phase", "")))
	if phase not in [
		WATERING_PHASE_AVAILABLE, WATERING_PHASE_ACTIVE, WATERING_PHASE_COMPLETE,
	]:
		return _baseline_watering_authority()
	saved["source_committed_counts"] = counts.duplicate(true)
	return saved


func _on_watering_can_picked(source: Node = null) -> void:
	var receipt := _consume_watering_source_receipt(
		source, WATERING_PICKUP_ACTION)
	if not _watering_source_receipt_is_active(
		receipt, WATERING_PICKUP_ACTION, _can_pickup_interactable):
		_active_watering_source_receipt.clear()
		return
	_watering_can_item_id = _resolve_watering_can_item_id()
	if _watering_can_item_id == "":
		_active_watering_source_receipt.clear()
		return
	if not _game_state.pick_up_item("peris", _watering_can_item_id):
		_active_watering_source_receipt.clear()
		_refresh_watering_interactions()
		return
	_active_watering_source_receipt.clear()
	_sync_watering_can_presenter()
	_refresh_watering_interactions()
	if not _plant_watered and _water_plant_interactable != null \
			and _water_plant_interactable.has_method("show_tutorial_label"):
		_water_plant_interactable.show_tutorial_label()

func _on_plant_watered(source: Node = null) -> void:
	var source_receipt := _consume_watering_source_receipt(
		source, WATERING_USE_ACTION)
	if not _watering_source_receipt_is_active(
		source_receipt, WATERING_USE_ACTION, _water_plant_interactable):
		_active_watering_source_receipt.clear()
		return
	if _is_plant_watered_authoritatively() or _watering_phase() == WATERING_PHASE_ACTIVE:
		_active_watering_source_receipt.clear()
		return
	_watering_can_item_id = _resolve_watering_can_item_id()
	var item: Dictionary = _game_state.items.get(_watering_can_item_id, {})
	if str(item.get("holder", "")) != "peris" \
			or str(item.get("location", "")) != "hand":
		_active_watering_source_receipt.clear()
		return  # need the can in hand first (the WATER prompt only appears after pickup, so this is rare)
	if _game_state.is_moving("peris") or _game_state.is_downed("peris") \
			or _horizontal_distance(_game_state.get_position("peris"), _watering_fern_position()) \
				> WATERING_USE_RADIUS:
		_active_watering_source_receipt.clear()
		return
	var started := _game_state.command_begin_mechanism_phase(
		WATERING_PHASE_ID,
		WATERING_PHASE_ACTIVE,
		WATERING_USE_DURATION,
		WATERING_PHASE_COMPLETE,
		{
			"actor": "peris",
			"item_id": _watering_can_item_id,
			"target": "boston_fern",
			"source_contract": WATERING_CAN_CONTRACT,
			"source_data_id": str(source_receipt.get("source_data_id", "")),
			"source_trigger_count": int(source_receipt.get("trigger_count", 0)),
		}
	)
	if not started:
		_active_watering_source_receipt.clear()
		_refresh_watering_interactions()
		return
	_publish_watering_receipt(WATERING_PHASE_ACTIVE, _watering_can_item_id)
	_active_watering_source_receipt.clear()
	_refresh_watering_interactions()


func _commit_plant_watered() -> void:
	if _watering_phase() != WATERING_PHASE_COMPLETE:
		return
	var item_id := _resolve_watering_can_item_id()
	var item: Dictionary = _game_state.items.get(item_id, {})
	if str(item.get("holder", "")) != "peris" \
			or str(item.get("location", "")) != "hand" \
			or _game_state.is_downed("peris") or _game_state.is_moving("peris") \
			or _horizontal_distance(_game_state.get_position("peris"), _watering_fern_position()) \
				> WATERING_USE_RADIUS:
		_game_state.command_reset_mechanism_phase(
			WATERING_PHASE_ID, &"watering_commit_invalid")
		return
	_plant_watered = true
	_publish_watering_receipt(WATERING_PHASE_COMPLETE, item_id)
	# Watering is USE, not an implicit DROP. The reusable can remains visibly in
	# Peris's canonical hand until the player explicitly puts it down.
	_show_thought(DialogueData.text("peris.sim_expand.plant_7.look"))
	_sync_watering_can_presenter()
	_refresh_watering_interactions()


func _ensure_watering_can_item(can_pos: Vector3) -> String:
	var existing := _resolve_watering_can_item_id()
	if existing != "" or _game_state == null:
		return existing
	return _game_state.spawn_item("watering_can", can_pos, {
		"display_name": "Watering Can",
		"hand_slots": 1,
		"endocytosis_allowed": false,
		"source_contract": WATERING_CAN_CONTRACT,
	})


func _resolve_watering_can_item_id() -> String:
	if _game_state == null:
		return ""
	if _watering_can_item_id != "" and _game_state.items.has(_watering_can_item_id):
		var cached := _game_state.items[_watering_can_item_id] as Dictionary
		if str((cached.get("properties", {}) as Dictionary).get(
				"source_contract", "")) == WATERING_CAN_CONTRACT:
			return _watering_can_item_id
	_watering_can_item_id = ""
	var item_ids := _game_state.items.keys()
	item_ids.sort()
	for item_id_variant in item_ids:
		var item_id := str(item_id_variant)
		var item := _game_state.items[item_id_variant] as Dictionary
		if str((item.get("properties", {}) as Dictionary).get(
				"source_contract", "")) == WATERING_CAN_CONTRACT:
			_watering_can_item_id = item_id
			break
	return _watering_can_item_id


func _watering_phase_state() -> Dictionary:
	if _game_state == null:
		return {}
	var state := _game_state.get_mechanism_phase_state(WATERING_PHASE_ID)
	var phase := StringName(str(state.get("phase", "")))
	if phase not in [WATERING_PHASE_ACTIVE, WATERING_PHASE_COMPLETE]:
		return {}
	var metadata := state.get("metadata", {}) as Dictionary
	var item_id := _resolve_watering_can_item_id()
	if item_id == "" or str(metadata.get("actor", "")) != "peris" \
			or str(metadata.get("item_id", "")) != item_id \
			or str(metadata.get("target", "")) != "boston_fern" \
			or str(metadata.get("source_contract", "")) != WATERING_CAN_CONTRACT \
			or str(metadata.get("source_data_id", "")) != WATERING_USE_SOURCE_ID \
			or int(metadata.get("source_trigger_count", -1)) != int(
				_watering_source_committed_counts.get(WATERING_USE_ACTION, 0)):
		return {}
	return state


func _watering_phase() -> StringName:
	return StringName(str(_watering_phase_state().get("phase", "")))


func _is_plant_watered_authoritatively() -> bool:
	return _watering_phase() == WATERING_PHASE_COMPLETE


func _publish_watering_receipt(phase: StringName, item_id: String) -> void:
	if _game_state == null:
		return
	var counts := {}
	for action_id in _watering_action_ids():
		counts[action_id] = maxi(
			0, int(_watering_source_committed_counts.get(action_id, 0)))
	_game_state.set_world_state(WATERING_AUTHORITY_KEY, {
		"version": WATERING_AUTHORITY_VERSION,
		"authority_id": WATERING_AUTHORITY_KEY,
		"phase": str(phase),
		"item_id": item_id,
		"mechanism_id": str(WATERING_PHASE_ID),
		"source_committed_counts": counts,
	})


func _watering_fern_position() -> Vector3:
	return _authored_position("Plant7Table", "Plant7TableAnchor", FERN_POS)


func _wire_watering_authority_signals() -> void:
	if _game_state == null:
		return
	if _watering_signal_game_state != null and _watering_signal_game_state != _game_state:
		_disconnect_watering_authority_signals(_watering_signal_game_state)
	_watering_signal_game_state = _game_state
	if not _game_state.mechanism_phase_completed.is_connected(_on_watering_phase_completed):
		_game_state.mechanism_phase_completed.connect(_on_watering_phase_completed)
	if not _game_state.mechanism_phase_reset.is_connected(_on_watering_phase_reset):
		_game_state.mechanism_phase_reset.connect(_on_watering_phase_reset)
	if not _game_state.movement_started.is_connected(_on_watering_movement_started):
		_game_state.movement_started.connect(_on_watering_movement_started)
	if not _game_state.item_picked_up.is_connected(_on_watering_item_changed):
		_game_state.item_picked_up.connect(_on_watering_item_changed)
	if not _game_state.item_dropped.is_connected(_on_watering_item_changed):
		_game_state.item_dropped.connect(_on_watering_item_changed)
	if not _game_state.item_transferred.is_connected(_on_watering_item_transferred):
		_game_state.item_transferred.connect(_on_watering_item_transferred)
	if not _game_state.stat_changed.is_connected(_on_watering_stat_changed):
		_game_state.stat_changed.connect(_on_watering_stat_changed)


func _disconnect_watering_authority_signals(state: GameState) -> void:
	if state.mechanism_phase_completed.is_connected(_on_watering_phase_completed):
		state.mechanism_phase_completed.disconnect(_on_watering_phase_completed)
	if state.mechanism_phase_reset.is_connected(_on_watering_phase_reset):
		state.mechanism_phase_reset.disconnect(_on_watering_phase_reset)
	if state.movement_started.is_connected(_on_watering_movement_started):
		state.movement_started.disconnect(_on_watering_movement_started)
	if state.item_picked_up.is_connected(_on_watering_item_changed):
		state.item_picked_up.disconnect(_on_watering_item_changed)
	if state.item_dropped.is_connected(_on_watering_item_changed):
		state.item_dropped.disconnect(_on_watering_item_changed)
	if state.item_transferred.is_connected(_on_watering_item_transferred):
		state.item_transferred.disconnect(_on_watering_item_transferred)
	if state.stat_changed.is_connected(_on_watering_stat_changed):
		state.stat_changed.disconnect(_on_watering_stat_changed)


func _on_watering_phase_completed(mechanism_id: StringName, phase: StringName) -> void:
	if mechanism_id == WATERING_PHASE_ID and phase == WATERING_PHASE_COMPLETE:
		_commit_plant_watered()


func _on_watering_phase_reset(mechanism_id: StringName, _reason: StringName) -> void:
	if mechanism_id != WATERING_PHASE_ID:
		return
	_plant_watered = false
	_publish_watering_receipt(&"available", _resolve_watering_can_item_id())
	_refresh_watering_interactions()


func _on_watering_movement_started(id: String) -> void:
	if id == "peris" and _watering_phase() == WATERING_PHASE_ACTIVE:
		_game_state.command_reset_mechanism_phase(WATERING_PHASE_ID, &"actor_moved")


func _on_watering_item_changed(_char_id: String, item_id: String) -> void:
	if item_id != _resolve_watering_can_item_id():
		return
	if _watering_phase() == WATERING_PHASE_ACTIVE and not _peris_holds_watering_can():
		_game_state.command_reset_mechanism_phase(WATERING_PHASE_ID, &"item_released")
	_sync_watering_can_presenter()
	_refresh_watering_interactions()


func _on_watering_item_transferred(_from_id: String, _to_id: String, item_id: String) -> void:
	_on_watering_item_changed("", item_id)


func _on_watering_stat_changed(id: String, stat: String, value: float) -> void:
	if id == "peris" and stat == "hp" and value <= 0.0 \
			and _watering_phase() == WATERING_PHASE_ACTIVE:
		_game_state.command_reset_mechanism_phase(WATERING_PHASE_ID, &"actor_downed")


func _peris_holds_watering_can() -> bool:
	var item_id := _resolve_watering_can_item_id()
	if _game_state == null or item_id == "" or not _game_state.characters.has("peris"):
		return false
	var item := _game_state.items[item_id] as Dictionary
	return str(item.get("holder", "")) == "peris" \
		and str(item.get("location", "")) == "hand" \
		and _game_state.get_hand_items("peris").has(item_id)


func _sync_watering_can_presenter() -> void:
	if not is_instance_valid(_watering_can_mesh) or _game_state == null:
		return
	var item_id := _resolve_watering_can_item_id()
	if item_id == "":
		_watering_can_mesh.visible = false
		return
	var item := _game_state.items[item_id] as Dictionary
	match str(item.get("location", "ground")):
		"ground":
			if is_instance_valid(_watering_can_home_parent) \
					and _watering_can_mesh.get_parent() != _watering_can_home_parent:
				_watering_can_mesh.reparent(_watering_can_home_parent, true)
			_watering_can_mesh.visible = true
			_watering_can_mesh.global_position = item.get(
				"position", _watering_can_mesh.global_position) as Vector3
			_watering_can_mesh.rotation = _watering_can_home_rotation
			_watering_can_mesh.scale = _watering_can_home_scale
			if is_instance_valid(_can_pickup_interactable):
				_can_pickup_interactable.global_position = _watering_can_mesh.global_position
		"hand":
			var holder_id := str(item.get("holder", ""))
			var holder := get_game_state_character_node(holder_id)
			if holder == null:
				_watering_can_mesh.visible = false
				return
			if _watering_can_mesh.get_parent() != holder:
				_watering_can_mesh.reparent(holder, false)
			_watering_can_mesh.visible = true
			_watering_can_mesh.position = WATERING_HAND_OFFSET
			_watering_can_mesh.rotation = Vector3(0.0, 0.0, deg_to_rad(-18.0))
			_watering_can_mesh.scale = _watering_can_home_scale
		_:
			_watering_can_mesh.visible = false
	if is_instance_valid(_watering_can_outline_target) and _watering_can_mesh.visible:
		_watering_can_outline_target.global_position = _watering_can_mesh.global_position \
			+ _watering_can_outline_offset


func _refresh_watering_interactions(restoring := false) -> void:
	_plant_watered = _is_plant_watered_authoritatively()
	var item_id := _resolve_watering_can_item_id()
	var item: Dictionary = _game_state.items.get(item_id, {}) if _game_state != null else {}
	var ground := str(item.get("location", "")) == "ground"
	var held := _peris_holds_watering_can()
	var watering := _watering_phase() == WATERING_PHASE_ACTIVE
	_set_interactable_projection(
		_can_pickup_interactable, _exploration_armed and ground and not watering, restoring)
	_set_interactable_projection(
		_water_plant_interactable,
		_exploration_armed and held and not watering and not _plant_watered,
		restoring)
	_set_interactable_projection(
		_fern_exploration_interactable,
		_exploration_armed and (not held or _plant_watered) and not watering,
		restoring)
	if _fern_outline_target != null:
		var delegate = _water_plant_interactable \
			if held and not _plant_watered else _fern_exploration_interactable
		_set_room_target_interaction_delegate(_fern_outline_target, delegate)


func _set_interactable_projection(interactable, enabled: bool, restoring := false) -> void:
	if interactable == null or not is_instance_valid(interactable):
		return
	if interactable in [_can_pickup_interactable, _water_plant_interactable]:
		_set_watering_source_projection(interactable, enabled, restoring)
		return
	if interactable.has_method("is_interaction_enabled") \
			and bool(interactable.call("is_interaction_enabled")) == enabled:
		return
	if restoring and interactable.has_method("restore_one_shot_presenter"):
		interactable.call("restore_one_shot_presenter", false, enabled)
	elif interactable.has_method("set_interaction_enabled"):
		interactable.call("set_interaction_enabled", enabled)


func _set_watering_source_projection(
		source: Node, enabled: bool, restoring := false) -> void:
	if _game_state == null or not is_instance_valid(source):
		return
	var data_id := str(source.get("data_id"))
	if data_id != "" and _game_state.has_interactable(data_id):
		var registry := _game_state.get_interactable(data_id)
		var action_id := str(source.get_meta("watering_action_id", ""))
		var committed := int(
			_watering_source_committed_counts.get(action_id, 0))
		var source_count := int(registry.get("trigger_count", 0))
		if enabled and bool(registry.get("triggered", false)) \
				and source_count <= committed:
			source.call("reset")
		elif bool(registry.get("enabled", true)) != enabled:
			_game_state.set_interactable_enabled(data_id, enabled)
	if restoring and source.has_method("restore_one_shot_presenter"):
		source.call("restore_one_shot_presenter", false, enabled)
	elif source.has_method("set_interaction_enabled"):
		source.call("set_interaction_enabled", enabled)


func _ensure_watering_sources_registered_after_restore() -> void:
	if _game_state == null:
		return
	var raw: Variant = _game_state.get_world_state(WATERING_AUTHORITY_KEY, null)
	var saved_counts: Dictionary = {}
	if raw is Dictionary and (raw as Dictionary).get(
			"source_committed_counts", null) is Dictionary:
		saved_counts = ((raw as Dictionary).get(
			"source_committed_counts", {}) as Dictionary).duplicate(true)
	for action_id in _watering_action_ids():
		var source := _watering_source_for_action(action_id)
		if not is_instance_valid(source):
			continue
		var data_id := WATERING_PICKUP_SOURCE_ID \
			if action_id == WATERING_PICKUP_ACTION else WATERING_USE_SOURCE_ID
		if not _game_state.has_interactable(data_id):
			_game_state.register_interactable({
				"id": data_id,
				"position": (source as Node3D).global_position,
				"requires_hold": int(source.get("interactable_type")) \
					== Interactable.InteractableType.HOLD_ACTION,
				"interactable_type": int(source.get("interactable_type")),
				"hold_time": float(source.get("dwell_time")),
				"one_shot": true,
				"required_character": "peris",
				"radius": float(source.get("interaction_radius")),
				"tutorial_label": str(source.get("tutorial_label")),
				"enabled": false,
				"trigger_count": maxi(0, int(saved_counts.get(action_id, 0))),
			})
		if source.has_method("bind_data"):
			source.call("bind_data", _game_state, data_id)
		_configure_watering_source(source, action_id)


func _restore_watering_source_authority() -> void:
	if _game_state == null:
		return
	_ensure_watering_sources_registered_after_restore()
	var raw: Variant = _game_state.get_world_state(WATERING_AUTHORITY_KEY, null)
	var authority := _watering_authority_state()
	var saved_counts := (
		authority.get("source_committed_counts", {}) as Dictionary
	).duplicate(true)
	var changed := not (raw is Dictionary) \
		or int((raw as Dictionary).get("version", 0)) \
			!= WATERING_AUTHORITY_VERSION
	for action_id in _watering_action_ids():
		var source_count := maxi(0, _watering_source_trigger_count(
			_watering_source_for_action(action_id)))
		var committed := maxi(0, int(saved_counts.get(action_id, 0)))
		if source_count != committed:
			# A newer source count is the accepted-before-owner seam. A lower
			# count means the snapshot predates the source registry. In
			# both cases the registry visible in this save is the next receipt
			# baseline; neither difference grants an item or watering result.
			saved_counts[action_id] = source_count
			changed = true
		_watering_source_committed_counts[action_id] = int(
			saved_counts.get(action_id, source_count))
	authority["source_committed_counts"] = saved_counts
	var mechanism_phase := StringName(str(
		_game_state.get_mechanism_phase_state(WATERING_PHASE_ID).get(
			"phase", "")))
	var authoritative_phase := WATERING_PHASE_AVAILABLE
	if mechanism_phase == WATERING_PHASE_ACTIVE:
		authoritative_phase = WATERING_PHASE_ACTIVE
	elif mechanism_phase == WATERING_PHASE_COMPLETE:
		authoritative_phase = WATERING_PHASE_COMPLETE
	if StringName(str(authority.get("phase", ""))) != authoritative_phase:
		authority["phase"] = str(authoritative_phase)
		changed = true
	authority["item_id"] = _resolve_watering_can_item_id()
	authority["mechanism_id"] = str(WATERING_PHASE_ID)
	if changed:
		_game_state.set_world_state(
			WATERING_AUTHORITY_KEY, authority.duplicate(true))


func on_game_state_snapshot_restored() -> void:
	_connect_peris_authority_signals()
	_wire_watering_authority_signals()
	_restore_watering_source_authority()
	_watering_can_item_id = _resolve_watering_can_item_id()
	_plant_watered = _is_plant_watered_authoritatively()
	_exploration_armed = _current_step == "workspace"
	_sync_watering_can_presenter()
	_refresh_watering_interactions(true)
	_restore_peris_authority_after_snapshot()


func apply_save_snapshot(data: Dictionary) -> void:
	# TutorialSequence restores GameState (and therefore invokes our presenter
	# hook) before it restores the saved DialogueBox/portable continuation. Attach
	# plain-dialogue completions only after that base work, so its exact dialogue
	# restoration cannot disconnect the authoritative next-phase dispatcher.
	super.apply_save_snapshot(data)
	_reattach_peris_dialogue_continuation()


func _reattach_peris_dialogue_continuation() -> void:
	if _dialogue == null:
		return
	var phase := str(_peris_authority_state().get("phase", ""))
	var callback := Callable()
	match phase:
		PERIS_PHASE_ATTACK_DIALOGUE:
			callback = _on_attack_dialogue_finished
		PERIS_PHASE_WRAP_PROMPT:
			callback = _show_wrap_queue_prompt
		PERIS_PHASE_AFTERMATH:
			callback = _on_aftermath_dialogue_finished
		PERIS_PHASE_EFFICIENCY_LOG:
			if float(_peris_authority_state().get("deadline", -1.0)) < 0.0:
				callback = _on_efficiency_log_dialogue_finished
		PERIS_PHASE_SANCTION_NOTICE:
			callback = _on_sanction_notice_finished
		PERIS_PHASE_SANCTION_FEED:
			callback = _on_sanction_feed_finished
		PERIS_PHASE_SPIRAL_FLASH:
			callback = _on_spiral_flash_finished
		PERIS_PHASE_RETRO:
			callback = _on_retro_finished
		PERIS_PHASE_SIM_BAY_EXIT:
			callback = _on_sim_bay_exit_finished
	if callback.is_valid() and not _dialogue.dialogue_finished.is_connected(callback):
		_dialogue.dialogue_finished.connect(callback, CONNECT_ONE_SHOT)


func _maybe_unlock_exploration_gate() -> void:
	if _explore_gate_unlocked:
		return
	_care_context_ready = true
	_explore_gate_unlocked = true
	if _explore_logbook_gate != null:
		if _explore_logbook_gate.has_method("reset"):
			_explore_logbook_gate.reset()
		elif _explore_logbook_gate.has_method("set_interaction_enabled"):
			_explore_logbook_gate.set_interaction_enabled(true)
		_explore_logbook_gate.set("one_shot", false)
		if _explore_logbook_gate.has_method("show_tutorial_label"):
			_explore_logbook_gate.show_tutorial_label()

func _build_peris_painting(parent: Node3D) -> void:
	# The furniture GLTF already contains the measured wall art. Reuse it instead of laying a
	# second procedural painting over the same wall; retain a fallback for stripped test assets.
	var visual_meshes: Array = _room_binder.object_meshes(["WallArtFrame", "WallArt"])
	if visual_meshes.is_empty():
		push_warning("Peris room is missing the portable WallArt/WallArtFrame asset")
	var zone_pos := _authored_floor_interaction_position(
		"WallArtFrame", "PaintingZoneMarker", Vector3(8.5, 0, 0.5), Vector3(0, 0, 0.4)
	)
	var zone := _make_exploration_zone(parent,
		zone_pos,
		"PaintingZone",
		"peris.sim_expand.painting.line",
		1.3, 0.6)
	zone.set_meta("interaction_target_position", zone_pos + Vector3(0.5, 0, 1.0))
	_exploration_interactables.append(zone)
	_register_care_context_zone(zone, "painting", "PaintingZone")
	var target := _outline_object_meshes(parent, "PaintingOutline",
		visual_meshes, "peris_painting", 0.95)
	_set_room_target_interaction_delegate(target, zone)

func _build_peris_wellness_feed(parent: Node3D) -> void:
	# Mounted on the modeled left wall (X~0), near the back corner.
	var terminal := _authored_room_node("WellnessTerminal")
	if terminal == null:
		push_warning("Peris room is missing its editor-authored WellnessTerminal")
		return
	var zone_pos := _authored_floor_interaction_position(
		"WellnessTerminal", "WellnessZoneMarker", Vector3(0.5, 0, 0.5), Vector3(0.5, 0, 0)
	)
	var zone := _make_exploration_zone(parent,
		zone_pos,
		"WellnessZone",
		"peris.sim_expand.wellness.line",
		1.0, 0.6)
	zone.set_meta("interaction_target_position", zone_pos + Vector3(2.0, 0, 1.0))
	_exploration_interactables.append(zone)
	_register_care_context_zone(zone, "wellness", "WellnessZone")
	var target := _outline_object_meshes(parent, "WellnessOutline",
		_collect_mesh_instances(terminal), "peris_wellness", 0.8)
	_set_room_target_interaction_delegate(target, zone)

func _build_peris_strike_warning(parent: Node3D) -> void:
	# Pinned to the modeled right wall (X~14), near the open front corner.
	var notice := _authored_room_node("StrikeNotice")
	if notice == null:
		push_warning("Peris room is missing its editor-authored StrikeNotice")
		return
	var zone_pos := _authored_floor_interaction_position(
		"StrikeNotice", "StrikeWarningZoneMarker", Vector3(13.5, 0, 2.5), Vector3(-0.5, 0, 0)
	)
	var area := _make_exploration_zone(parent,
		zone_pos,
		"StrikeWarningZone",
		"",
		1.0, 0.8)  # re-inspectable: re-opening the warning replays the document + Peris's line
	area.set_meta("interaction_target_position", zone_pos + Vector3(-1.0, 0, 0))
	_exploration_interactables.append(area)
	area.connect("interacted", _on_strike_warning_interacted.bind(area))
	_register_care_context_zone(area, "strike_warning", "StrikeWarningZone")
	var target := _outline_object_meshes(parent, "StrikeWarningOutline",
		_collect_mesh_instances(notice), "peris_strike_warning", 0.7)
	_set_room_target_interaction_delegate(target, area)


func _on_strike_warning_interacted(area: Node) -> void:
	_play_focused_dialogue_keys([
		"peris.sim_expand.strike_warning.notification",
		"peris.sim_expand.strike_warning.line",
	], area)

func _build_peris_logbook_gate(parent: Node3D) -> void:
	# Logbook is the gate to Monos — by the modeled bookshelf on the right side.
	var console := _authored_room_node("CareLogbookConsole")
	if console == null:
		push_warning("Peris room is missing its editor-authored CareLogbookConsole")
		return
	var pos := console.global_position
	var label := Label3D.new()
	label.name = "CareLogbookLabel"
	label.text = "CARE LOGBOOK"
	label.font_size = 26
	label.pixel_size = 0.006
	label.modulate = Color(0.72, 0.92, 0.82, 0.9)
	label.outline_modulate = Color(0.02, 0.03, 0.03, 0.9)
	label.outline_size = 5
	label.position = pos + Vector3(0.0, 0.72, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
	var gate_pos := _authored_floor_interaction_position(
		"CareLogbookConsole", "LogbookGateMarker", Vector3(12.5, 0, 3.5), Vector3(-0.5, 0, 0)
	)
	var gate := _create_interactable(parent, gate_pos, "LogbookGate", 1.6, 0.8,
		"Continue", false, Interactable.InteractableType.HOLD_ACTION, "peris.logbook_gate")
	gate.connect("interacted", _on_exploration_gate_interacted)
	_explore_logbook_gate = gate
	_exploration_interactables.append(gate)
	var target := _outline_object_meshes(parent, "LogbookOutline",
		_collect_mesh_instances(console), "peris_logbook", 1.0)
	_set_room_target_interaction_delegate(target, gate)
