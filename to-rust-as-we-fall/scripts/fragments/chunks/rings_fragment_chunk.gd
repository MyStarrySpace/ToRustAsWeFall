extends "res://scripts/scene_chunks/scene_chunk.gd"

const LevelDecoratorScript := preload("res://scripts/generation/level_decorator.gd")
const RINGS_AUTHORITY_VERSION := 3
const VALID_RINGS_AUTHORITY_VERSIONS := [2, 3]
const RINGS_AUTHORITY_KEY := "runtime:rings_fragment"
const ENDO_DEPARTURE_TRAVERSAL_ID := &"rings_endo_departure"
const ENDO_DEPARTURE_DURATION := 3.0
const ENDO_DEPARTURE_DESTINATION := Vector3(-5.0, 0.5, -5.0)
const REASSIGNMENT_ACTOR := "peris"
const REASSIGNMENT_REQUIRED_PARTY := ["peris", "endo"]
const REASSIGNMENT_PARTY_RADIUS := 3.4
const OPTIONAL_READ_ACTOR := "peris"
const OPTIONAL_READ_POSITION_TOLERANCE := 0.35
const OPTIONAL_READ_HEIGHT_TOLERANCE := 1.25
const OPTIONAL_READ_CLIENT_BLOOM := "client_bloom"
const OPTIONAL_READ_PROPAGATION := "propagation"
const OPTIONAL_READ_FORGET_ME_NOT := "forget_me_not"
const OPTIONAL_READ_ACTION_IDS := [
	OPTIONAL_READ_CLIENT_BLOOM,
	OPTIONAL_READ_PROPAGATION,
	OPTIONAL_READ_FORGET_ME_NOT,
]
const ENDO_PHASE_PRESENT := "present"
const ENDO_PHASE_DEPARTING := "departing"
const ENDO_PHASE_DEPARTED := "departed"
const VALID_ENDO_PHASES := [ENDO_PHASE_PRESENT, ENDO_PHASE_DEPARTING, ENDO_PHASE_DEPARTED]
const FLOOR_CENTER := Vector3(34.0, -0.05, 0.0)
const FLOOR_SIZE := Vector3(72.0, 0.1, 30.0)
const MARCO_POS := Vector3(14.0, 0.55, -4.5)
const CLIENT_BLOOM_POS := Vector3(12.5, 0.0, -7.2)
const PROPAGATION_POS := Vector3(34.0, 0.0, 8.0)
const FORGET_ME_NOT_POS := Vector3(56.0, 0.0, 10.5)
const SPAWNS := {
	"aster": Vector3(5.0, 0.0, 0.0),
	"peris": Vector3(3.2, 0.0, 1.7),
	"endo": Vector3(1.4, 0.0, -1.7),
}

var _marco_interactable
var _client_bloom_interactable
var _propagation_interactable
var _forget_me_not_interactable

var _marco_seen := false
var _endo_departed := false
var _endo_phase := ENDO_PHASE_PRESENT
var _endo_departure_start_tick := -1.0
var _endo_departure_deadline := -1.0
var _reassignment_actor := ""
var _reassignment_commit_tick := -1.0
var _reassignment_positions: Dictionary = {}
var _client_seen := false
var _propagation_seen := false
var _forget_me_not_seen := false
var _optional_read_sources: Dictionary = {}
var _optional_read_consumed_counts: Dictionary = {
	OPTIONAL_READ_CLIENT_BLOOM: 0,
	OPTIONAL_READ_PROPAGATION: 0,
	OPTIONAL_READ_FORGET_ME_NOT: 0,
}
var _last_fragment := ""

var _flora_materials: Array[StandardMaterial3D] = []
var _decoration_audit: Dictionary = {}
var _rings_authority_baseline: Dictionary = {}
var _rings_authority_initialized := false
var _restoring_rings_authority := false
var _departure_signal_game_state


func _build_chunk() -> void:
	_add_floor(self, FLOOR_CENTER, FLOOR_SIZE, Color(0.13, 0.11, 0.1))
	_add_box(self, Vector3(34.0, 2.2, -15.2), Vector3(72.0, 4.4, 0.3), Color(0.15, 0.14, 0.12))
	_add_box(self, Vector3(34.0, 2.2, 15.2), Vector3(72.0, 4.4, 0.3), Color(0.17, 0.15, 0.13))

	for i in range(7):
		_add_light(self, Vector3(8.0 + float(i) * 9.0, 3.6, 0.0), Color(0.84, 0.64, 0.42), 2.0, 16.0)
	for i in range(6):
		_add_box(self, Vector3(10.0 + float(i) * 10.0, 1.5, -14.7), Vector3(4.4, 2.0, 0.1), Color(0.16, 0.13, 0.1), Color(0.28, 0.22, 0.14), 0.5)
		_add_box(self, Vector3(14.0 + float(i) * 10.0, 1.3, 14.7), Vector3(1.8, 2.6, 0.1), Color(0.2, 0.17, 0.14))

	_build_marco_beat()
	_build_client_bloom_read()
	_build_propagation_read()
	_build_forget_me_not_read()

	# Reuse the campaign habitat language in local fragment coordinates. Decoration is render-only.
	_decoration_audit = LevelDecoratorScript.decorate_profile(self, "rings", {
		"x0": FLOOR_CENTER.x - FLOOR_SIZE.x * 0.5,
		"x1": FLOOR_CENTER.x + FLOOR_SIZE.x * 0.5,
		"width": FLOOR_SIZE.z,
		"wall_height": 4.4,
		"ground_y": 0.0,
	})
	_connect_departure_signals()
	_initialize_rings_authority()


func _process(_delta: float) -> void:
	_update_flora_pulse()


func headless_process(_delta: float) -> void:
	_update_flora_pulse()


func get_scene_title() -> String:
	return "Rings Fragment Lab"


func get_scene_help() -> String:
	return "Gather conscious Peris and Endo beside Marco, then have Peris speak with him. Peris's three flora reads are optional and work in any order."


func get_default_character() -> String:
	return "peris"


func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)


func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors.merge({
		"marco": MARCO_POS,
		"client_bloom": CLIENT_BLOOM_POS,
		"propagation": PROPAGATION_POS,
		"forget_me_not": FORGET_ME_NOT_POS,
	}, true)
	return anchors


func get_preview_time_state() -> Dictionary:
	return {
		"day": 2,
		"time": 0.46,
		"routing_mode": "safe",
		"note_default": "Marco and Endo carry the required story beat. The flora reads add worldbuilding without becoming a route checklist.",
	}


func get_preview_state() -> Dictionary:
	var traversal := _endo_departure_state()
	var progress := 1.0 if _endo_phase == ENDO_PHASE_DEPARTED else 0.0
	var remaining := 0.0
	if not traversal.is_empty():
		progress = float(traversal.get("progress", 0.0))
		remaining = float(traversal.get("remaining", 0.0))
	return {
		"marco_seen": _marco_seen,
		"reassignment_named": _marco_seen,
		"endo_departed": _endo_departed,
		"endo_phase": _endo_phase,
		"endo_departure_progress": progress,
		"endo_departure_remaining": remaining,
		"endo_departure_start_tick": _endo_departure_start_tick,
		"endo_departure_deadline": _endo_departure_deadline,
		"reassignment_actor": _reassignment_actor,
		"reassignment_commit_tick": _reassignment_commit_tick,
		"reassignment_positions": _serialize_reassignment_positions(),
		"client_seen": _client_seen,
		"propagation_seen": _propagation_seen,
		"forget_me_not_seen": _forget_me_not_seen,
		"optional_read_consumed_counts": _portable_optional_read_counts(),
		"ambient_read_count": int(_client_seen) + int(_propagation_seen) + int(_forget_me_not_seen),
		"complete": _endo_departed,
		"last_fragment": _last_fragment,
	}


func get_decoration_audit() -> Dictionary:
	return _decoration_audit.duplicate(true)


func reset_preview_state() -> void:
	_restoring_rings_authority = true
	var gs = _get_game_state()
	if gs != null and gs.has_method("is_external_traversal_active") \
			and gs.is_external_traversal_active("endo"):
		var traversal: Dictionary = gs.get_external_traversal_state("endo")
		if StringName(str(traversal.get("traversal_id", ""))) == ENDO_DEPARTURE_TRAVERSAL_ID:
			gs.cancel_external_traversal("endo", &"rings_reset")
	if host != null and host.has_method("restore_preview_character_for_restart"):
		host.call("restore_preview_character_for_restart", "endo", SPAWNS["endo"])
	elif gs != null and not gs.characters.has("endo"):
		# Explicit scenario reset is the only path allowed to recreate the authored starting roster.
		gs.register_character("endo", SPAWNS["endo"], 3.0, {
			"hp": 100.0,
			"stamina": 100.0,
			"atp": 6.0,
		})
	_set_character_visible("endo", true)
	_set_character_status("endo", "")
	_marco_seen = false
	_endo_departed = false
	_endo_phase = ENDO_PHASE_PRESENT
	_endo_departure_start_tick = -1.0
	_endo_departure_deadline = -1.0
	_reassignment_actor = ""
	_reassignment_commit_tick = -1.0
	_reassignment_positions.clear()
	_client_seen = false
	_propagation_seen = false
	_forget_me_not_seen = false
	_last_fragment = ""
	for interactable in [
		_marco_interactable,
		_client_bloom_interactable,
		_propagation_interactable,
		_forget_me_not_interactable,
	]:
		if is_instance_valid(interactable):
			interactable.reset()
			interactable.set_interaction_enabled(true)
	_reset_optional_read_consumed_counts_to_registry()
	_restoring_rings_authority = false
	_rings_authority_baseline = _baseline_rings_authority_state()
	_rings_authority_initialized = true
	_publish_rings_authority()


## Retained for callers that still probe the old automation API. The endpoint helper is
## intentionally inert: automation and deterministic tapes must resolve the semantic target
## returned by get_playthrough_interaction_target() and enter through the ordinary coordinator.
func trigger_rings_reassignment_beat() -> bool:
	return false


func get_playthrough_interaction_target(action_id: String) -> Node3D:
	match action_id:
		"marco", "marco_reassignment", "rings_reassignment":
			return _marco_interactable as Node3D
		"client_bloom", "rings_client_bloom":
			return _client_bloom_interactable as Node3D
		"propagation", "rings_propagation":
			return _propagation_interactable as Node3D
		"forget_me_not", "rings_forget_me_not":
			return _forget_me_not_interactable as Node3D
		_:
			return null


func _build_marco_beat() -> void:
	var marco_root := Node3D.new()
	marco_root.position = MARCO_POS
	add_child(marco_root)
	_add_box(marco_root, Vector3.ZERO, Vector3(0.7, 1.5, 0.45), Color(0.18, 0.16, 0.14), Color(0.24, 0.16, 0.1), 0.18)
	_add_label(self, "MARCO // FORMER CLIENT", MARCO_POS + Vector3(0.0, 2.2, 0.0))
	_marco_interactable = _add_inspection_interactable(
		self,
		"MarcoInteractable",
		"Marco",
		MARCO_POS + Vector3(0.0, 0.2, 0.0),
		"SPEAK",
		"peris",
		1.8,
		true
	)
	_marco_interactable.set(
		"consequence_preview",
		"With conscious Endo gathered nearby, Peris starts the reassignment conversation")
	_marco_interactable.set_pre_trigger_validator(_validate_marco_reassignment_trigger)
	_marco_interactable.interacted.connect(_on_marco_interacted.bind(_marco_interactable))


func _build_client_bloom_read() -> void:
	_add_flora_cluster(CLIENT_BLOOM_POS, Color(0.94, 0.74, 0.44), 1.0, 4)
	_add_label(self, "CLIENT BLOOM // OPTIONAL", CLIENT_BLOOM_POS + Vector3(0.0, 2.0, 0.0))
	_client_bloom_interactable = _add_inspection_interactable(
		self,
		"ClientBloomInteractable",
		"Client Bloom",
		CLIENT_BLOOM_POS + Vector3(0.0, 0.3, 0.0),
		"READ",
		"peris",
		1.7,
		true
	)
	_client_bloom_interactable.set("consequence_preview", "Hear one optional trace of Peris's former client")
	_configure_optional_read_source(
		_client_bloom_interactable, OPTIONAL_READ_CLIENT_BLOOM,
		_on_client_bloom_interacted)


func _build_propagation_read() -> void:
	_add_label(self, "PROPAGATION TRACE // OPTIONAL", PROPAGATION_POS + Vector3(0.0, 2.5, 0.0))
	for i in range(4):
		_add_flora_cluster(
			PROPAGATION_POS + Vector3(-4.0 + float(i) * 2.6, 0.0, -1.0 + float(i % 2) * 1.2),
			Color(0.78, 0.58, 0.36),
			0.8 + float(i) * 0.08,
			3
		)
	_propagation_doorframe(PROPAGATION_POS + Vector3(0.0, 1.4, 2.2))
	_propagation_interactable = _add_inspection_interactable(
		self,
		"PropagationInteractable",
		"Propagation Trace",
		PROPAGATION_POS + Vector3(0.0, 0.3, 0.0),
		"READ",
		"peris",
		1.8,
		true
	)
	_propagation_interactable.set("consequence_preview", "Hear an optional trace of the routes residents used")
	_configure_optional_read_source(
		_propagation_interactable, OPTIONAL_READ_PROPAGATION,
		_on_propagation_interacted)


func _build_forget_me_not_read() -> void:
	_add_label(self, "FORGET-ME-NOT // OPTIONAL", FORGET_ME_NOT_POS + Vector3(0.0, 2.6, 0.0), Color(0.76, 0.84, 0.96))
	_add_box(self, FORGET_ME_NOT_POS + Vector3(0.0, 0.25, 0.0), Vector3(7.0, 0.5, 6.0), Color(0.12, 0.11, 0.1))
	_add_flora_cluster(FORGET_ME_NOT_POS + Vector3(-0.8, 0.0, -0.6), Color(0.58, 0.72, 0.95), 1.1, 5)
	_add_flora_cluster(FORGET_ME_NOT_POS + Vector3(1.1, 0.0, 0.9), Color(0.66, 0.78, 0.98), 0.9, 4)
	_forget_me_not_interactable = _add_inspection_interactable(
		self,
		"ForgetMeNotInteractable",
		"Forget-Me-Not",
		FORGET_ME_NOT_POS + Vector3(0.0, 0.3, 0.0),
		"READ",
		"peris",
		1.8,
		true
	)
	_forget_me_not_interactable.set("consequence_preview", "Hear one optional relational memory")
	_configure_optional_read_source(
		_forget_me_not_interactable, OPTIONAL_READ_FORGET_ME_NOT,
		_on_forget_me_not_interacted)


func _add_flora_cluster(position: Vector3, color: Color, height_scale: float, stems: int) -> void:
	var root := Node3D.new()
	root.position = position
	add_child(root)
	for i in range(stems):
		var stem := MeshInstance3D.new()
		var stem_mesh := CylinderMesh.new()
		stem_mesh.top_radius = 0.03
		stem_mesh.bottom_radius = 0.05
		stem_mesh.height = (0.42 + float(i) * 0.08) * height_scale
		stem.mesh = stem_mesh
		stem.material_override = _make_material(color.darkened(0.45))
		stem.position = Vector3(-0.25 + float(i) * 0.14, 0.18 + float(i) * 0.03, -0.1 + sin(float(i)) * 0.08)
		root.add_child(stem)

		var bloom := MeshInstance3D.new()
		var bloom_mesh := SphereMesh.new()
		bloom_mesh.radius = 0.11 + float(i) * 0.012
		bloom_mesh.height = 0.24 + float(i) * 0.03
		bloom.mesh = bloom_mesh
		var bloom_material := _make_material(color, color, 0.42)
		bloom.material_override = bloom_material
		bloom.position = stem.position + Vector3(0.0, 0.3 + float(i) * 0.07, 0.0)
		root.add_child(bloom)
		_flora_materials.append(bloom_material)


func _propagation_doorframe(position: Vector3) -> void:
	_add_box(self, position + Vector3(-2.0, 0.0, 0.0), Vector3(0.3, 2.8, 0.6), Color(0.18, 0.16, 0.14))
	_add_box(self, position + Vector3(2.0, 0.0, 0.0), Vector3(0.3, 2.8, 0.6), Color(0.18, 0.16, 0.14))
	_add_box(self, position + Vector3(0.0, 1.3, 0.0), Vector3(4.3, 0.3, 0.6), Color(0.18, 0.16, 0.14))


func _update_flora_pulse() -> void:
	var pulse := 0.25 + 0.12 * sin(Time.get_ticks_msec() * 0.003) # @rendering_only
	for material in _flora_materials:
		if material != null:
			material.emission_energy_multiplier = 0.34 + pulse


func _on_marco_interacted(source: Node = null) -> void:
	if _endo_phase != ENDO_PHASE_PRESENT or _marco_seen:
		return
	var preflight := _reassignment_party_preflight(source)
	if not bool(preflight.get("complete", false)):
		var blocked := preflight.get("blocked", []) as Array
		_show_message(
			str(blocked[0]) if not blocked.is_empty()
				else "Peris and Endo must gather beside Marco.",
			2.2)
		return
	var gs = _get_game_state()
	if gs == null or not gs.has_method("command_external_traversal"):
		_rearm_marco_interaction()
		_show_message("The reassignment authority is unavailable.", 2.0)
		return
	var render_destination := ENDO_DEPARTURE_DESTINATION
	if gs.coord_map != null and gs.coord_map.has_method("to_world"):
		render_destination = gs.coord_map.to_world(ENDO_DEPARTURE_DESTINATION)
	if not gs.command_external_traversal(
			"endo",
			ENDO_DEPARTURE_TRAVERSAL_ID,
			ENDO_DEPARTURE_DESTINATION,
			gs.get_render_position("endo"),
			render_destination,
			ENDO_DEPARTURE_DURATION,
			&"locked"
		):
		_rearm_marco_interaction()
		_show_message("Endo cannot leave while another action has control of him.", 2.0)
		return
	var traversal := _endo_departure_state()
	_marco_seen = true
	_endo_departed = false
	_endo_phase = ENDO_PHASE_DEPARTING
	_endo_departure_start_tick = float(traversal.get("start_tick", _get_scheduler_tick()))
	_endo_departure_deadline = float(traversal.get(
		"end_tick", _endo_departure_start_tick + ENDO_DEPARTURE_DURATION))
	_reassignment_actor = str(preflight.get("actor", ""))
	_reassignment_commit_tick = _endo_departure_start_tick
	_reassignment_positions = (
		preflight.get("positions", {}) as Dictionary).duplicate(true)
	_last_fragment = "reassignment"
	_set_character_status("endo", "departing")
	if is_instance_valid(_marco_interactable):
		_marco_interactable.set_interaction_enabled(false)
	_clear_dialogue()
	for key in [
		"ring.marco.entry.narration",
		"ring.marco.entry.marco.warn",
		"ring.marco.entry.peris.name",
		"ring.marco.entry.marco.correct",
		"ring.reassignment.marco.pair",
		"ring.reassignment.peris.start",
		"ring.reassignment.marco.scatter",
		"ring.reassignment.peris.shift",
		"ring.after_marco.endo.watch",
		"ring.departure.narration",
		"ring.departure.aster.question",
		"ring.departure.peris.read",
		"ring.departure.endo.turn",
		"ring.departure.peris.explain",
		"ring.departure.narration.closing",
	]:
		_say_key(key)
	_set_preview_step("rings_endo_departing")
	_show_note("Marco names the reassignment pattern. Endo is walking out through the west junction.", 4.5)
	_publish_rings_authority()


## The reassignment is a shared physical conversation, not a remote story flag. This
## pure validator runs before Interactable records a trigger or consumes the one-shot.
func _validate_marco_reassignment_trigger(source: Node, actor: String) -> bool:
	return bool(_reassignment_physical_preflight(source, actor).get("complete", false))


## The callback repeats physical truth and additionally requires the trigger receipt,
## so a compatibility helper or direct callback cannot manufacture the departure.
func _reassignment_party_preflight(source: Node) -> Dictionary:
	var actor := str(source.get("active_character")) if source != null else ""
	var outcome := _reassignment_physical_preflight(source, actor)
	if not bool(outcome.get("complete", false)):
		return outcome
	var gs = _get_game_state()
	if not _marco_semantic_trigger_pending(source, gs):
		outcome["complete"] = false
		(outcome["blocked"] as Array).append(
			"Speak with Marco through the world interaction.")
	return outcome


func _reassignment_physical_preflight(source: Node, actor: String) -> Dictionary:
	var outcome := {
		"complete": false,
		"actor": "",
		"positions": {},
		"blocked": [],
	}
	var blocked := outcome["blocked"] as Array
	var gs = _get_game_state()
	if source == null or source != _marco_interactable:
		blocked.append("Use Marco's world interaction.")
		return outcome
	if actor != REASSIGNMENT_ACTOR:
		blocked.append("Peris must speak with Marco.")
		return outcome
	outcome["actor"] = actor
	if gs == null:
		blocked.append("The party authority is unavailable.")
		return outcome

	var party: Array = gs.get_party() if gs.has_method("get_party") else []
	var marco_position := _marco_data_position(gs)
	for char_id_v in REASSIGNMENT_REQUIRED_PARTY:
		var char_id := str(char_id_v)
		if not gs.characters.has(char_id):
			blocked.append("%s is not present." % char_id.capitalize())
			continue
		if not party.has(char_id):
			blocked.append("%s is not in the available party." % char_id.capitalize())
			continue
		if (gs.has_method("is_narratively_available")
				and not bool(gs.is_narratively_available(char_id))) \
				or (gs.has_method("is_downed") and bool(gs.is_downed(char_id))) \
				or (gs.has_method("is_knocked_down") and bool(gs.is_knocked_down(char_id))):
			blocked.append("%s must be conscious." % char_id.capitalize())
			continue
		if _reassignment_character_busy(gs, char_id):
			blocked.append("%s must finish their current action." % char_id.capitalize())
			continue
		var position: Vector3 = gs.get_position(char_id)
		(outcome["positions"] as Dictionary)[char_id] = position
		if _flat_distance(position, marco_position) > REASSIGNMENT_PARTY_RADIUS:
			blocked.append("%s must gather beside Marco." % char_id.capitalize())
	if not blocked.is_empty():
		return outcome
	outcome["complete"] = true
	return outcome


## `interacted` is emitted only after the one-shot's canonical data record has
## accepted Peris and disabled itself. Requiring that receipt prevents calling the
## chunk callback directly even when bodies have been manually placed nearby.
func _marco_semantic_trigger_pending(source: Node, gs) -> bool:
	if source == null or source != _marco_interactable \
			or str(source.get("active_character")) != REASSIGNMENT_ACTOR \
			or not bool(source.get("_used")):
		return false
	if gs == null:
		return false
	var data_id := str(source.get("data_id"))
	if data_id.is_empty() or not gs.interactables.has(data_id):
		return false
	var spec: Dictionary = gs.interactables[data_id]
	return bool(spec.get("triggered", false)) and not bool(spec.get("enabled", true))


func _reassignment_character_busy(gs, char_id: String) -> bool:
	return (gs.has_method("is_moving") and bool(gs.is_moving(char_id))) \
		or (gs.has_method("is_resting") and bool(gs.is_resting(char_id))) \
		or (gs.has_method("is_dodging") and bool(gs.is_dodging(char_id))) \
		or (gs.has_method("is_endocytosing") and bool(gs.is_endocytosing(char_id))) \
		or (gs.has_method("is_external_traversal_active")
			and bool(gs.is_external_traversal_active(char_id))) \
		or (gs.has_method("is_dragging") and bool(gs.is_dragging(char_id))) \
		or (gs.has_method("is_field_restoring") and bool(gs.is_field_restoring(char_id)))


func _marco_data_position(gs) -> Vector3:
	var position := MARCO_POS + Vector3(0.0, 0.2, 0.0)
	if is_instance_valid(_marco_interactable):
		position = _marco_interactable.global_position
		if gs != null and gs.coord_map != null and gs.coord_map.has_method("to_data"):
			position = gs.coord_map.to_data(position)
	return position


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The three ambient memories are observations, not remote flags. Each is owned by its own
## physical one-shot and accepts only a ready Peris body standing on that source's navigation
## floor. The source is bound into the callback so another read (or a manually emitted signal)
## cannot be substituted after the preflight.
func _configure_optional_read_source(
		source: Node, action_id: String, owner_callback: Callable
	) -> void:
	if not is_instance_valid(source) or action_id not in OPTIONAL_READ_ACTION_IDS:
		return
	_optional_read_sources[action_id] = source
	source.set_meta("rings_optional_read_action", action_id)
	source.set_pre_trigger_validator(
		_validate_optional_read_trigger.bind(action_id, source))
	source.interacted.connect(owner_callback.bind(source))


func _validate_optional_read_trigger(
		source: Node, actor: String, action_id: String, expected_source: Node
	) -> bool:
	return is_instance_valid(source) and source == expected_source \
		and _optional_read_sources.get(action_id) == source \
		and not _optional_read_seen(action_id) \
		and _optional_read_actor_ready_at_source(source, actor)


func _optional_read_actor_ready_at_source(source: Node, actor: String) -> bool:
	var gs = _get_game_state()
	if gs == null or not is_instance_valid(source) or not (source is Node3D) \
			or actor != OPTIONAL_READ_ACTOR or not gs.characters.has(actor) \
			or not gs.get_party().has(actor) \
			or (gs.has_method("is_narratively_available")
				and not bool(gs.is_narratively_available(actor))) \
			or (gs.has_method("is_downed") and bool(gs.is_downed(actor))) \
			or (gs.has_method("is_knocked_down") and bool(gs.is_knocked_down(actor))) \
			or _optional_read_character_busy(gs, actor):
		return false
	var source_position := _optional_read_source_data_position(source)
	if not source_position.is_finite():
		return false
	if gs.grid != null and gs.grid.level_count > 1 \
			and int(gs.get_character_level(actor)) != int(
				gs.grid.level_for_y(source_position.y)):
		return false
	var actor_position: Vector3 = gs.get_position(actor)
	var radius := float(source.get("interaction_radius")) \
		+ OPTIONAL_READ_POSITION_TOLERANCE
	return _flat_distance(actor_position, source_position) <= radius \
		and absf(actor_position.y - source_position.y) \
			<= OPTIONAL_READ_HEIGHT_TOLERANCE


func _optional_read_character_busy(gs, actor: String) -> bool:
	return (gs.has_method("is_moving") and bool(gs.is_moving(actor))) \
		or (gs.has_method("is_resting") and bool(gs.is_resting(actor))) \
		or (gs.has_method("is_dodging") and bool(gs.is_dodging(actor))) \
		or (gs.has_method("is_endocytosing") and bool(gs.is_endocytosing(actor))) \
		or (gs.has_method("is_external_traversal_active")
			and bool(gs.is_external_traversal_active(actor))) \
		or (gs.has_method("is_dragging") and bool(gs.is_dragging(actor))) \
		or (gs.has_method("is_field_restoring")
			and bool(gs.is_field_restoring(actor))) \
		or (gs.has_method("is_pushing") and bool(gs.is_pushing(actor)))


func _optional_read_source_data_position(source: Node) -> Vector3:
	var gs = _get_game_state()
	var data_id := str(source.get("data_id")) if is_instance_valid(source) else ""
	if gs != null and data_id != "" and gs.has_interactable(data_id):
		var saved_position: Variant = gs.get_interactable(data_id).get(
			"position", Vector3.INF)
		if saved_position is Vector3:
			return saved_position
	if source is Node3D:
		var world_position := (source as Node3D).global_position
		if gs != null and gs.coord_map != null and gs.coord_map.has_method("to_data"):
			return gs.coord_map.to_data(world_position)
		return world_position
	return Vector3.INF


func _optional_read_source_trigger_count(source: Node) -> int:
	var gs = _get_game_state()
	var data_id := str(source.get("data_id")) if is_instance_valid(source) else ""
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return -1
	return int(gs.get_interactable(data_id).get("trigger_count", -1))


func _optional_read_source_receipt_count(source: Node, action_id: String) -> int:
	if not is_instance_valid(source) or _optional_read_sources.get(action_id) != source \
			or action_id not in OPTIONAL_READ_ACTION_IDS \
			or _optional_read_seen(action_id):
		return -1
	var actor := str(source.get("active_character"))
	if not _optional_read_actor_ready_at_source(source, actor) \
			or not bool(source.get("one_shot")) or not bool(source.get("_used")) \
			or bool(source.get("interaction_enabled")):
		return -1
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return -1
	var receipt: Dictionary = gs.get_interactable(data_id)
	var trigger_count := int(receipt.get("trigger_count", -1))
	if not bool(receipt.get("one_shot", false)) \
			or not bool(receipt.get("triggered", false)) \
			or bool(receipt.get("enabled", true)) \
			or str(receipt.get("last_trigger_character", "")) != actor \
			or trigger_count != int(
				_optional_read_consumed_counts.get(action_id, 0)) + 1:
		return -1
	return trigger_count


func _consume_optional_read_source_receipt(
		source: Node, action_id: String
	) -> bool:
	var trigger_count := _optional_read_source_receipt_count(source, action_id)
	if trigger_count < 0:
		return false
	_optional_read_consumed_counts[action_id] = trigger_count
	return true


func _optional_read_seen(action_id: String) -> bool:
	match action_id:
		OPTIONAL_READ_CLIENT_BLOOM:
			return _client_seen
		OPTIONAL_READ_PROPAGATION:
			return _propagation_seen
		OPTIONAL_READ_FORGET_ME_NOT:
			return _forget_me_not_seen
		_:
			return false


func _on_client_bloom_interacted(source: Node = null) -> bool:
	if not _consume_optional_read_source_receipt(
			source, OPTIONAL_READ_CLIENT_BLOOM):
		return false
	_client_seen = true
	_last_fragment = "client_bloom"
	_clear_dialogue()
	_say("Hello? ...No answer. Just the bloom still listening.", "PERIS")
	_say("The flora kept the emotional outline of the room after the client left it.", "ASTER", "data")
	_show_note("Optional client bloom: relationship residue, not a route gate.", 4.0)
	_publish_rings_authority()
	return true


func _on_propagation_interacted(source: Node = null) -> bool:
	if not _consume_optional_read_source_receipt(
			source, OPTIONAL_READ_PROPAGATION):
		return false
	_propagation_seen = true
	_last_fragment = "propagation"
	_clear_dialogue()
	_say("It spread along the routes people used to take home.", "PERIS")
	_say("Not random growth. It is following habit, warmth, and repeated contact.", "ASTER", "data")
	_show_note("Optional propagation trace: it adds context but changes no progression state.", 4.0)
	_publish_rings_authority()
	return true


func _on_forget_me_not_interacted(source: Node = null) -> bool:
	if not _consume_optional_read_source_receipt(
			source, OPTIONAL_READ_FORGET_ME_NOT):
		return false
	_forget_me_not_seen = true
	_last_fragment = "forget_me_not"
	_clear_dialogue()
	_say("This one remembers before either of us had language for it.", "PERIS")
	_say("The room feels domestic again for half a second, and then it doesn't.", "", "fragment")
	_show_note("Optional forget-me-not memory: richness without a memory gate.", 4.2)
	_publish_rings_authority()
	return true


func rings_authority_key() -> String:
	return RINGS_AUTHORITY_KEY


func _portable_optional_read_counts() -> Dictionary:
	var portable := {}
	for action_id in OPTIONAL_READ_ACTION_IDS:
		portable[action_id] = maxi(
			0, int(_optional_read_consumed_counts.get(action_id, 0)))
	return portable


func _normalized_optional_read_counts(raw: Variant) -> Dictionary:
	var normalized := {}
	var counts := raw as Dictionary if raw is Dictionary else {}
	for action_id in OPTIONAL_READ_ACTION_IDS:
		normalized[action_id] = maxi(0, int(counts.get(action_id, 0)))
	return normalized


func _reset_optional_read_consumed_counts_to_registry() -> void:
	for action_id in OPTIONAL_READ_ACTION_IDS:
		var source: Node = _optional_read_sources.get(action_id)
		_optional_read_consumed_counts[action_id] = maxi(
			0, _optional_read_source_trigger_count(source))


func _valid_optional_read_authority(
		saved: Dictionary, saved_version: int
	) -> bool:
	if saved_version < 3:
		return true
	var counts_v: Variant = saved.get("optional_read_consumed_counts", null)
	if not counts_v is Dictionary:
		return false
	var counts := counts_v as Dictionary
	for action_id in OPTIONAL_READ_ACTION_IDS:
		if not counts.has(action_id):
			return false
		var saved_count := int(counts.get(action_id, -1))
		var source: Node = _optional_read_sources.get(action_id)
		var source_count := _optional_read_source_trigger_count(source)
		if saved_count < 0 or source_count < 0 or saved_count > source_count:
			return false
		if _saved_optional_read_seen(saved, action_id) and saved_count <= 0:
			return false
	return true


func _saved_optional_read_seen(saved: Dictionary, action_id: String) -> bool:
	match action_id:
		OPTIONAL_READ_CLIENT_BLOOM:
			return bool(saved.get("client_seen", false))
		OPTIONAL_READ_PROPAGATION:
			return bool(saved.get("propagation_seen", false))
		OPTIONAL_READ_FORGET_ME_NOT:
			return bool(saved.get("forget_me_not_seen", false))
		_:
			return false


## Interactable records acceptance before emitting `interacted`. A save made on that synchronous
## edge therefore has a source count newer than this owner's count but no information receipt.
## Consume the stale identity without granting the read; projection rearms that exact source.
func _reconcile_accepted_optional_read_source_receipts() -> bool:
	var changed := false
	for action_id in OPTIONAL_READ_ACTION_IDS:
		var source: Node = _optional_read_sources.get(action_id)
		var source_count := maxi(0, _optional_read_source_trigger_count(source))
		var consumed_count := maxi(
			0, int(_optional_read_consumed_counts.get(action_id, 0)))
		if source_count > consumed_count:
			_optional_read_consumed_counts[action_id] = source_count
			changed = true
	return changed


func _project_optional_read_source(action_id: String) -> void:
	var source: Node = _optional_read_sources.get(action_id)
	if not is_instance_valid(source):
		return
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return
	var seen := _optional_read_seen(action_id)
	var spec: Dictionary = gs.get_interactable(data_id)
	if seen:
		gs.set_interactable_enabled(data_id, false)
		if source.has_method("restore_one_shot_presenter"):
			source.restore_one_shot_presenter(true, false)
		return
	if bool(spec.get("triggered", false)):
		_rearm_optional_read_source(source)
		return
	gs.set_interactable_enabled(data_id, true)
	if source.has_method("restore_one_shot_presenter"):
		source.restore_one_shot_presenter(false, true)


func _rearm_optional_read_source(source: Node) -> void:
	if not is_instance_valid(source):
		return
	if source.is_node_ready():
		source.reset()
		if source.has_method("restore_one_shot_presenter"):
			source.restore_one_shot_presenter(false, true)
		return
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs != null and data_id != "" and gs.has_interactable(data_id):
		gs.reset_interactable(data_id)
	source.set("_used", false)
	source.set("interaction_enabled", true)


func _baseline_rings_authority_state() -> Dictionary:
	return {
		"version": RINGS_AUTHORITY_VERSION,
		"authority_id": rings_authority_key(),
		"endo_phase": ENDO_PHASE_PRESENT,
		"endo_departure_start_tick": -1.0,
		"endo_departure_deadline": -1.0,
		"endo_departure_destination": _vector3_to_array(ENDO_DEPARTURE_DESTINATION),
		"reassignment_actor": "",
		"reassignment_commit_tick": -1.0,
		"reassignment_positions": {},
		"marco_seen": false,
		"endo_departed": false,
		"client_seen": false,
		"propagation_seen": false,
		"forget_me_not_seen": false,
		"optional_read_consumed_counts": _portable_optional_read_counts(),
		"last_fragment": "",
	}


func _rings_authority_state() -> Dictionary:
	return {
		"version": RINGS_AUTHORITY_VERSION,
		"authority_id": rings_authority_key(),
		"endo_phase": _endo_phase,
		"endo_departure_start_tick": _endo_departure_start_tick,
		"endo_departure_deadline": _endo_departure_deadline,
		"endo_departure_destination": _vector3_to_array(ENDO_DEPARTURE_DESTINATION),
		"reassignment_actor": _reassignment_actor,
		"reassignment_commit_tick": _reassignment_commit_tick,
		"reassignment_positions": _serialize_reassignment_positions(),
		"marco_seen": _marco_seen,
		"endo_departed": _endo_departed,
		"client_seen": _client_seen,
		"propagation_seen": _propagation_seen,
		"forget_me_not_seen": _forget_me_not_seen,
		"optional_read_consumed_counts": _portable_optional_read_counts(),
		"last_fragment": _last_fragment,
	}


func _valid_rings_authority(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var saved := raw as Dictionary
	var saved_version := int(saved.get("version", 0))
	var phase := str(saved.get("endo_phase", ""))
	if saved_version not in VALID_RINGS_AUTHORITY_VERSIONS \
			or str(saved.get("authority_id", "")) != rings_authority_key() \
			or phase not in VALID_ENDO_PHASES \
			or not _valid_optional_read_authority(saved, saved_version):
		return false
	var start_tick := float(saved.get("endo_departure_start_tick", -1.0))
	var deadline := float(saved.get("endo_departure_deadline", -1.0))
	match phase:
		ENDO_PHASE_PRESENT:
			var positions_v: Variant = saved.get("reassignment_positions", null)
			return not bool(saved.get("marco_seen", true)) \
				and not bool(saved.get("endo_departed", true)) \
				and str(saved.get("reassignment_actor", "")).is_empty() \
				and float(saved.get("reassignment_commit_tick", 0.0)) < 0.0 \
				and positions_v is Dictionary \
				and (positions_v as Dictionary).is_empty()
		ENDO_PHASE_DEPARTING:
			return bool(saved.get("marco_seen", false)) \
				and not bool(saved.get("endo_departed", true)) \
				and start_tick >= 0.0 and deadline > start_tick \
				and _valid_reassignment_evidence(saved, start_tick)
		ENDO_PHASE_DEPARTED:
			return bool(saved.get("marco_seen", false)) \
				and bool(saved.get("endo_departed", false)) \
				and _valid_reassignment_evidence(saved, start_tick)
		_:
			return false


func _valid_reassignment_evidence(saved: Dictionary, departure_start_tick: float) -> bool:
	if str(saved.get("reassignment_actor", "")) != REASSIGNMENT_ACTOR:
		return false
	var commit_tick := float(saved.get("reassignment_commit_tick", -1.0))
	if commit_tick < 0.0 or departure_start_tick < 0.0 \
			or not is_equal_approx(commit_tick, departure_start_tick):
		return false
	var positions_v: Variant = saved.get("reassignment_positions", null)
	if not positions_v is Dictionary:
		return false
	var positions := positions_v as Dictionary
	var marco_position := _marco_data_position(_get_game_state())
	for char_id_v in REASSIGNMENT_REQUIRED_PARTY:
		var char_id := str(char_id_v)
		if not positions.has(char_id) or not _valid_vector3_array(positions[char_id]):
			return false
		var position := _array_to_vector3(positions[char_id])
		if _flat_distance(position, marco_position) > REASSIGNMENT_PARTY_RADIUS + 0.001:
			return false
	return true


func _initialize_rings_authority() -> void:
	if _rings_authority_initialized:
		return
	var gs = _get_game_state()
	if gs == null or not gs.has_method("get_world_state"):
		return
	_rings_authority_initialized = true
	_rings_authority_baseline = _baseline_rings_authority_state()
	var raw: Variant = gs.get_world_state(rings_authority_key(), null)
	if _valid_rings_authority(raw):
		_restore_rings_authority(raw as Dictionary, true)
	else:
		_publish_rings_authority()


func _publish_rings_authority() -> void:
	if _restoring_rings_authority:
		return
	var gs = _get_game_state()
	if gs != null and gs.has_method("set_world_state"):
		gs.set_world_state(rings_authority_key(), _rings_authority_state())


func on_game_state_snapshot_restored() -> void:
	super.on_game_state_snapshot_restored()
	_connect_departure_signals()
	_rings_authority_initialized = true
	if _rings_authority_baseline.is_empty():
		_rings_authority_baseline = _baseline_rings_authority_state()
	var gs = _get_game_state()
	var raw: Variant = gs.get_world_state(rings_authority_key(), null) \
		if gs != null and gs.has_method("get_world_state") else null
	if _valid_rings_authority(raw):
		_restore_rings_authority(raw as Dictionary, true)
	else:
		# Absence is the pre-interaction baseline. Do not manufacture a gameplay event while loading.
		_restore_rings_authority(_rings_authority_baseline.duplicate(true), false)


func _restore_rings_authority(
		saved: Dictionary, publish_normalization := true
	) -> void:
	_restoring_rings_authority = true
	var saved_version := int(saved.get("version", 2))
	_endo_phase = str(saved.get("endo_phase", ENDO_PHASE_PRESENT))
	_endo_departure_start_tick = float(saved.get("endo_departure_start_tick", -1.0))
	_endo_departure_deadline = float(saved.get("endo_departure_deadline", -1.0))
	_reassignment_actor = str(saved.get("reassignment_actor", ""))
	_reassignment_commit_tick = float(saved.get("reassignment_commit_tick", -1.0))
	_reassignment_positions = _deserialize_reassignment_positions(
		saved.get("reassignment_positions", {}))
	_marco_seen = bool(saved.get("marco_seen", false))
	_endo_departed = bool(saved.get("endo_departed", false))
	_client_seen = bool(saved.get("client_seen", false))
	_propagation_seen = bool(saved.get("propagation_seen", false))
	_forget_me_not_seen = bool(saved.get("forget_me_not_seen", false))
	_last_fragment = str(saved.get("last_fragment", ""))
	var normalized := false
	if saved_version >= 3:
		_optional_read_consumed_counts = _normalized_optional_read_counts(
			saved.get("optional_read_consumed_counts", {}))
	else:
		# Version 2 knew which memories were seen but not which exact source receipt owned them.
		# Burn the restored registry edge at its current monotonic count; unseen accepted edges are
		# rearmed below instead of being promoted into information the player never obtained.
		_reset_optional_read_consumed_counts_to_registry()
		normalized = true
	if _reconcile_accepted_optional_read_source_receipts():
		normalized = true

	var gs = _get_game_state()
	match _endo_phase:
		ENDO_PHASE_PRESENT:
			_set_character_visible("endo", gs != null and gs.characters.has("endo"))
			_set_character_status("endo", "")
		ENDO_PHASE_DEPARTING:
			# GameState owns the interpolated path and its remaining callback. This hook only mirrors it.
			_set_character_visible("endo", gs != null and gs.characters.has("endo"))
			_set_character_status("endo", "departing")
		ENDO_PHASE_DEPARTED:
			_set_character_status("endo", "")
			_set_character_visible("endo", false)
	_restoring_rings_authority = false
	_apply_rings_interactable_state()
	_set_preview_step(_preview_step_for_endo_phase())
	if normalized and publish_normalization:
		_publish_rings_authority()


func _preview_step_for_endo_phase() -> String:
	match _endo_phase:
		ENDO_PHASE_DEPARTING:
			return "rings_endo_departing"
		ENDO_PHASE_DEPARTED:
			return "rings_fragment_complete"
		_:
			return "rings"


func _apply_rings_interactable_state() -> void:
	var resolved := {
		_marco_interactable: _marco_seen,
	}
	for interactable_v in resolved.keys():
		var interactable = interactable_v
		if not is_instance_valid(interactable):
			continue
		var should_be_enabled := not bool(resolved[interactable_v])
		if bool(interactable.get("interaction_enabled")) != should_be_enabled:
			interactable.set_interaction_enabled(should_be_enabled)
	for action_id in OPTIONAL_READ_ACTION_IDS:
		_project_optional_read_source(action_id)


func _connect_departure_signals() -> void:
	var gs = _get_game_state()
	if gs == _departure_signal_game_state:
		return
	if _departure_signal_game_state != null and is_instance_valid(_departure_signal_game_state):
		if _departure_signal_game_state.external_traversal_finished.is_connected(
				_on_external_traversal_finished):
			_departure_signal_game_state.external_traversal_finished.disconnect(
				_on_external_traversal_finished)
		if _departure_signal_game_state.external_traversal_cancelled.is_connected(
				_on_external_traversal_cancelled):
			_departure_signal_game_state.external_traversal_cancelled.disconnect(
				_on_external_traversal_cancelled)
	_departure_signal_game_state = gs
	if gs == null:
		return
	if not gs.external_traversal_finished.is_connected(_on_external_traversal_finished):
		gs.external_traversal_finished.connect(_on_external_traversal_finished)
	if not gs.external_traversal_cancelled.is_connected(_on_external_traversal_cancelled):
		gs.external_traversal_cancelled.connect(_on_external_traversal_cancelled)


func _on_external_traversal_finished(char_id: String, traversal_id: StringName) -> void:
	if char_id != "endo" or traversal_id != ENDO_DEPARTURE_TRAVERSAL_ID \
			or _endo_phase != ENDO_PHASE_DEPARTING:
		return
	_finalize_endo_departure()


func _on_external_traversal_cancelled(
		char_id: String, traversal_id: StringName, reason: StringName
	) -> void:
	if _restoring_rings_authority or char_id != "endo" \
			or traversal_id != ENDO_DEPARTURE_TRAVERSAL_ID \
			or _endo_phase != ENDO_PHASE_DEPARTING:
		return
	_endo_phase = ENDO_PHASE_PRESENT
	_endo_departed = false
	_marco_seen = false
	_endo_departure_start_tick = -1.0
	_endo_departure_deadline = -1.0
	_reassignment_actor = ""
	_reassignment_commit_tick = -1.0
	_reassignment_positions.clear()
	_last_fragment = ""
	_set_character_status("endo", "")
	_rearm_marco_interaction()
	_set_preview_step("rings")
	_show_message("Endo's departure was interrupted (%s). Speak with Marco to try again." % String(reason), 2.4)
	_publish_rings_authority()


func _finalize_endo_departure() -> void:
	if _endo_phase == ENDO_PHASE_DEPARTED:
		return
	_endo_phase = ENDO_PHASE_DEPARTED
	_endo_departed = true
	_marco_seen = true
	_set_character_status("endo", "")
	# Hiding first makes the preview sanitize active selection before the canonical roster disappears.
	_set_character_visible("endo", false)
	var gs = _get_game_state()
	if gs != null:
		var party: Array = gs.get_party()
		party.erase("endo")
		if gs.get_party() != party:
			gs.set_party(party)
		if gs.characters.has("endo"):
			gs.unregister_character("endo")
	_set_preview_step("rings_fragment_complete")
	_show_note("Endo reaches the west junction and leaves the active party. The ambient reads remain optional.", 4.5)
	_publish_rings_authority()


func _rearm_marco_interaction() -> void:
	if not is_instance_valid(_marco_interactable):
		return
	_marco_interactable.reset()
	_marco_interactable.set_interaction_enabled(true)


func _endo_departure_state() -> Dictionary:
	var gs = _get_game_state()
	if gs == null or not gs.has_method("get_external_traversal_state"):
		return {}
	var state: Dictionary = gs.get_external_traversal_state("endo")
	if state.is_empty() or StringName(str(state.get("traversal_id", ""))) \
			!= ENDO_DEPARTURE_TRAVERSAL_ID:
		return {}
	return state


func _vector3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _valid_vector3_array(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 3:
		return false
	for component in value as Array:
		if not (component is int or component is float):
			return false
	return true


func _array_to_vector3(value: Variant) -> Vector3:
	if not _valid_vector3_array(value):
		return Vector3.INF
	var values := value as Array
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func _serialize_reassignment_positions() -> Dictionary:
	var out := {}
	for char_id_v in _reassignment_positions.keys():
		var char_id := str(char_id_v)
		var position_v: Variant = _reassignment_positions[char_id_v]
		if position_v is Vector3:
			out[char_id] = _vector3_to_array(position_v as Vector3)
	return out


func _deserialize_reassignment_positions(value: Variant) -> Dictionary:
	var out := {}
	if not value is Dictionary:
		return out
	for char_id_v in (value as Dictionary).keys():
		var char_id := str(char_id_v)
		var position_v: Variant = (value as Dictionary)[char_id_v]
		if _valid_vector3_array(position_v):
			out[char_id] = _array_to_vector3(position_v)
	return out
