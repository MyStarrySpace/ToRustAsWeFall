class_name TypedTerminal
extends Interactable

## Save-authoritative physical source for the Open Files terminal vocabulary.
##
## The terminal consumes its ordinary one-shot Interactable receipt, publishes one exact typed
## command, then offers that command to a receiver. The receiver owns the consequence. Publishing
## before delivery makes the only save seam repairable without replaying the physical interaction.

signal terminal_command_committed(command: Dictionary)
signal terminal_command_delivered(command: Dictionary)
signal terminal_command_pending(command: Dictionary)
signal terminal_authority_rejected(reason: String)

const STATE_CONTRACT := "typed_terminal/v1"
const AUTHORITY_VERSION := 1
const AUTHORITY_PREFIX := "gameplay:typed_terminal:"
const SOURCE_PREFIX := "typed_terminal:"
const POSITION_EPSILON := 0.05

const SUBTYPES := {
	"door": {
		"effect": "open", "verb": "OPEN", "description": "Access-door terminal",
		"preview": "Open the terminal's linked physical access",
		"tint": Color(0.32, 0.86, 0.58),
	},
	"recon": {
		"effect": "reveal", "verb": "SCAN DATA", "description": "Linked-data terminal",
		"preview": "Reveal the linked system's own metadata without changing it",
		"tint": Color(0.29, 0.74, 1.0),
	},
	"credential": {
		"effect": "authorize", "verb": "SPOOF LOCATION",
		"description": "Tracked-access spoof terminal",
		"preview": "Authorize linked access by spoofing Aster's own reported location",
		"tint": Color(0.42, 0.90, 0.62),
	},
	"route": {
		"effect": "reroute", "verb": "REFLAG ROUTE", "description": "Route-control terminal",
		"preview": "Reflag this terminal's explicitly linked route controller",
		"tint": Color(0.50, 0.72, 0.90),
	},
	"signal": {
		"effect": "lure", "verb": "ROUTE SIGNAL", "description": "Signal-routing terminal",
		"preview": "Route this terminal's signal to its linked receiver",
		"tint": Color(0.80, 0.56, 0.92),
	},
	"flow": {
		"effect": "hold", "verb": "HOLD FLOW", "description": "Flow-hold terminal",
		"preview": "Hold the linked flow at its current boundary",
		"tint": Color(0.26, 0.82, 0.78),
	},
}

var _stable_id := ""
var _subtype := ""
var _effect := ""
var _receiver: Node
var _configured := false
var _last_restore_valid := true
var _last_delivery := false
var _housing: MeshInstance3D
var _display: MeshInstance3D
var _status_label: Label3D


func configure(
		game_state: GameState,
		world_position: Vector3,
		stable_id: String,
		subtype_id: String,
		receiver: Node,
		required_actor := "",
		radius := 1.8
	) -> bool:
	var normalized_id := stable_id.strip_edges()
	var normalized_subtype := subtype_id.strip_edges().to_lower()
	if _configured or game_state == null or normalized_id.is_empty() \
			or not SUBTYPES.has(normalized_subtype) or radius <= 0.0 \
			or receiver == null or not is_instance_valid(receiver) \
			or not receiver.has_method("can_accept_terminal_command") \
			or not receiver.has_method("accept_terminal_command"):
		return false
	_stable_id = normalized_id
	_subtype = normalized_subtype
	_effect = str((SUBTYPES[_subtype] as Dictionary).get("effect", ""))
	_receiver = receiver
	_configured = true
	position = world_position
	name = "TypedTerminal_%s" % _stable_id
	description = str((SUBTYPES[_subtype] as Dictionary).get("description", "Terminal"))
	consequence_preview = str((SUBTYPES[_subtype] as Dictionary).get("preview", ""))
	tutorial_label = str((SUBTYPES[_subtype] as Dictionary).get("verb", "OPERATE"))
	required_character = required_actor.strip_edges()
	interaction_radius = radius
	dwell_time = 0.0
	one_shot = true
	interactable_type = InteractableType.INSPECTION
	interaction_enabled = true
	_build_terminal_visual()
	var source_id := terminal_source_id()
	if game_state.has_interactable(source_id):
		if not _registered_source_matches(game_state.get_interactable(source_id), world_position):
			_configured = false
			return false
	else:
		game_state.register_interactable({
			"id": source_id,
			"position": world_position,
			"requires_hold": false,
			"interactable_type": InteractableType.INSPECTION,
			"hold_time": 0.0,
			"one_shot": true,
			"required_character": required_character,
			"radius": interaction_radius,
			"tutorial_label": tutorial_label,
			"enabled": true,
		})
	bind_data(game_state, source_id)
	set_movement_authority(game_state)
	if game_state.scheduler != null:
		set_scheduler(game_state.scheduler)
	set_pre_trigger_validator(_validate_physical_trigger)
	if not interacted.is_connected(_on_terminal_interacted):
		interacted.connect(_on_terminal_interacted)
	return sync_from_game_state()


func terminal_source_id() -> String:
	return SOURCE_PREFIX + _stable_id if not _stable_id.is_empty() else ""


func authority_state_key() -> String:
	return AUTHORITY_PREFIX + _stable_id if not _stable_id.is_empty() else ""


func get_family() -> String:
	return "terminal"


func get_subtype() -> String:
	return _subtype


func get_effect() -> String:
	return _effect


func get_stable_id() -> String:
	return _stable_id


func get_receiver() -> Node:
	return _receiver


func get_visual_meshes() -> Array:
	var meshes: Array = []
	for mesh in [_housing, _display]:
		if is_instance_valid(mesh):
			meshes.append(mesh)
	return meshes


func get_state() -> Dictionary:
	var saved := _saved_authority()
	var phase := str(saved.get("phase", "ready")) if not saved.is_empty() else "ready"
	return {
		"contract": STATE_CONTRACT,
		"configured": _configured,
		"stable_id": _stable_id,
		"source_id": terminal_source_id(),
		"authority_key": authority_state_key(),
		"family": "terminal",
		"subtype": _subtype,
		"effect": _effect,
		"phase": phase,
		"command": (saved.get("command", {}) as Dictionary).duplicate(true) \
			if saved.get("command", null) is Dictionary else {},
		"last_restore_valid": _last_restore_valid,
		"last_delivery": _last_delivery,
		"interaction_enabled": is_interaction_enabled(),
	}


func reset_terminal(reason: StringName = &"terminal_reset") -> bool:
	if not _configured or _game_state == null:
		return false
	var trigger_count := 0
	if _game_state.has_interactable(terminal_source_id()):
		trigger_count = int(_game_state.get_interactable(
			terminal_source_id()).get("trigger_count", 0))
	_game_state.set_world_state(authority_state_key(), {
		"contract": STATE_CONTRACT,
		"version": AUTHORITY_VERSION,
		"stable_id": _stable_id,
		"phase": "reset",
		"reset_reason": str(reason),
		"reset_tick": _scheduler_tick(),
		"source_trigger_count": trigger_count,
	})
	reset()
	_last_restore_valid = true
	_last_delivery = false
	_apply_terminal_visual("ready")
	return true


func sync_from_game_state() -> bool:
	if not _configured or _game_state == null:
		_last_restore_valid = false
		return false
	var saved := _saved_authority()
	if saved.is_empty() or _valid_reset(saved):
		_last_restore_valid = true
		_last_delivery = false
		_apply_terminal_visual("ready")
		return true
	if not _valid_accepted(saved):
		_last_restore_valid = false
		_last_delivery = false
		_apply_terminal_visual("invalid")
		terminal_authority_rejected.emit("invalid_saved_authority")
		return false
	_last_restore_valid = true
	var command := (saved.get("command", {}) as Dictionary).duplicate(true)
	_last_delivery = _deliver_if_needed(command)
	_apply_terminal_visual("accepted")
	return true


func on_game_state_snapshot_restored() -> void:
	super.on_game_state_snapshot_restored()
	sync_from_game_state()


func _validate_physical_trigger(source: Node, actor: String) -> bool:
	if source != self or not _configured or not _last_restore_valid or actor.is_empty():
		return false
	if not required_character.is_empty() and actor != required_character:
		return false
	var saved := _saved_authority()
	if not saved.is_empty() and not _valid_reset(saved):
		return false
	if not _game_state.characters.has(actor) or _game_state.is_downed(actor) \
			or _game_state.is_knocked_down(actor) or _game_state.is_moving(actor):
		return false
	var source_spec: Dictionary = _game_state.get_interactable(terminal_source_id())
	var source_position := _source_position(source_spec)
	return _game_state.get_position(actor).distance_to(source_position) \
		<= interaction_radius + POSITION_EPSILON


func _on_terminal_interacted() -> void:
	if not _terminal_receipt_pending():
		return
	var command := _build_command()
	if command.is_empty():
		return
	var authority := {
		"contract": STATE_CONTRACT,
		"version": AUTHORITY_VERSION,
		"stable_id": _stable_id,
		"phase": "accepted",
		"family": "terminal",
		"subtype": _subtype,
		"effect": _effect,
		"command": command.duplicate(true),
	}
	_game_state.set_world_state(authority_state_key(), authority)
	terminal_command_committed.emit(command.duplicate(true))
	_last_delivery = _deliver_if_needed(command)
	_apply_terminal_visual("accepted")


func _build_command() -> Dictionary:
	var source: Dictionary = _game_state.get_interactable(terminal_source_id())
	if not _registry_receipt_matches(source, active_character):
		return {}
	var source_position := _source_position(source)
	return {
		"family": "terminal",
		"subtype": _subtype,
		"effect": _effect,
		"source_id": terminal_source_id(),
		"source_authority_key": authority_state_key(),
		"source_trigger_count": int(source.get("trigger_count", 0)),
		"actor": active_character,
		"source_position": [source_position.x, source_position.y, source_position.z],
		"accepted_tick": _scheduler_tick(),
	}


func _deliver_if_needed(command: Dictionary) -> bool:
	if not is_instance_valid(_receiver):
		terminal_command_pending.emit(command.duplicate(true))
		return false
	if bool(_receiver.call("can_accept_terminal_command", command)) \
			and bool(_receiver.call("accept_terminal_command", command)):
		terminal_command_delivered.emit(command.duplicate(true))
		return true
	terminal_command_pending.emit(command.duplicate(true))
	return false


func _terminal_receipt_pending() -> bool:
	if _game_state == null or not _game_state.has_interactable(terminal_source_id()) \
			or not one_shot or not _used or is_interaction_enabled():
		return false
	var source: Dictionary = _game_state.get_interactable(terminal_source_id())
	return _registry_receipt_matches(source, active_character)


func _registry_receipt_matches(source: Dictionary, actor: String) -> bool:
	return bool(source.get("one_shot", false)) \
		and bool(source.get("triggered", false)) \
		and not bool(source.get("enabled", true)) \
		and int(source.get("trigger_count", 0)) > 0 \
		and str(source.get("last_trigger_character", "")) == actor \
		and _source_position(source).distance_to(position) <= POSITION_EPSILON


func _registered_source_matches(source: Dictionary, authored_position: Vector3) -> bool:
	return not source.is_empty() \
		and _source_position(source).distance_to(authored_position) <= POSITION_EPSILON \
		and bool(source.get("one_shot", false)) \
		and str(source.get("required_character", "")) == required_character \
		and is_equal_approx(float(source.get("radius", 0.0)), interaction_radius)


func _source_position(source: Dictionary) -> Vector3:
	var raw: Variant = source.get("position", Vector3(INF, INF, INF))
	if raw is Vector3:
		return raw as Vector3
	if raw is Array and raw.size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3(INF, INF, INF)


func _saved_authority() -> Dictionary:
	if not _configured or _game_state == null or not _game_state.has_method("get_world_state"):
		return {}
	var raw: Variant = _game_state.get_world_state(authority_state_key(), {})
	return raw as Dictionary if raw is Dictionary else {}


func _valid_accepted(saved: Dictionary) -> bool:
	if saved.is_empty() or str(saved.get("contract", "")) != STATE_CONTRACT \
			or int(saved.get("version", 0)) != AUTHORITY_VERSION \
			or str(saved.get("stable_id", "")) != _stable_id \
			or str(saved.get("phase", "")) != "accepted" \
			or str(saved.get("family", "")) != "terminal" \
			or str(saved.get("subtype", "")) != _subtype \
			or str(saved.get("effect", "")) != _effect:
		return false
	var command_v: Variant = saved.get("command", null)
	if not (command_v is Dictionary):
		return false
	var command := command_v as Dictionary
	var actor := str(command.get("actor", ""))
	var source_position := _source_position({"position": command.get("source_position", [])})
	if str(command.get("family", "")) != "terminal" \
			or str(command.get("subtype", "")) != _subtype \
			or str(command.get("effect", "")) != _effect \
			or str(command.get("source_id", "")) != terminal_source_id() \
			or str(command.get("source_authority_key", "")) != authority_state_key() \
			or actor.is_empty() or int(command.get("source_trigger_count", 0)) <= 0 \
			or not source_position.is_finite() or source_position.distance_to(position) > POSITION_EPSILON \
			or not is_finite(float(command.get("accepted_tick", -1.0))) \
			or float(command.get("accepted_tick", -1.0)) < 0.0:
		return false
	if not _game_state.has_interactable(terminal_source_id()):
		return false
	var source: Dictionary = _game_state.get_interactable(terminal_source_id())
	return _registry_receipt_matches(source, actor) \
		and int(source.get("trigger_count", 0)) \
			== int(command.get("source_trigger_count", -1))


func _valid_reset(saved: Dictionary) -> bool:
	return not saved.is_empty() \
		and str(saved.get("contract", "")) == STATE_CONTRACT \
		and int(saved.get("version", 0)) == AUTHORITY_VERSION \
		and str(saved.get("stable_id", "")) == _stable_id \
		and str(saved.get("phase", "")) == "reset" \
		and is_finite(float(saved.get("reset_tick", -1.0))) \
		and int(saved.get("source_trigger_count", -1)) >= 0


func _scheduler_tick() -> float:
	if _game_state != null and _game_state.scheduler != null:
		return float(_game_state.scheduler.get_current_tick())
	return 0.0


func _build_terminal_visual() -> void:
	var tint := (SUBTYPES[_subtype] as Dictionary).get("tint", Color(0.3, 0.9, 0.6)) as Color
	_housing = MeshInstance3D.new()
	_housing.name = "TerminalHousing"
	var housing_mesh := BoxMesh.new()
	housing_mesh.size = Vector3(1.15, 1.35, 0.82)
	_housing.mesh = housing_mesh
	_housing.position = Vector3(0.0, 0.67, 0.0)
	_housing.material_override = _terminal_material(Color(0.035, 0.05, 0.052), tint, 0.12)
	add_child(_housing)
	_display = MeshInstance3D.new()
	_display.name = "TerminalDisplay"
	var display_mesh := BoxMesh.new()
	display_mesh.size = Vector3(0.78, 0.44, 0.06)
	_display.mesh = display_mesh
	_display.position = Vector3(0.0, 0.90, 0.44)
	add_child(_display)
	_status_label = Label3D.new()
	_status_label.name = "TerminalStatus"
	_status_label.position = Vector3(0.0, 1.55, 0.0)
	_status_label.font_size = 28
	_status_label.pixel_size = 0.006
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.no_depth_test = true
	_status_label.set_meta("camera_occlusion_exempt", true)
	add_child(_status_label)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := SphereShape3D.new()
	shape.radius = interaction_radius
	collision.shape = shape
	add_child(collision)
	_apply_terminal_visual("ready")


func _apply_terminal_visual(phase: String) -> void:
	if not is_instance_valid(_display) or not is_instance_valid(_status_label):
		return
	var base_tint := (SUBTYPES[_subtype] as Dictionary).get(
		"tint", Color(0.3, 0.9, 0.6)) as Color
	var tint := base_tint
	var text := "%s // READY" % _subtype.to_upper()
	match phase:
		"accepted":
			text = "%s // ACCEPTED" % _effect.to_upper()
			tint = base_tint.lightened(0.12)
		"invalid":
			text = "AUTHORITY INVALID"
			tint = Color(0.96, 0.20, 0.16)
	_display.material_override = _terminal_material(tint.darkened(0.72), tint, 1.75)
	_status_label.text = text
	_status_label.modulate = tint


func _terminal_material(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.emission_enabled = energy > 0.0
	material.emission = emission
	material.emission_energy_multiplier = energy
	return material
