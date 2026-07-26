class_name Hushbloom
extends Interactable

signal burst_fired(at: Vector3)
signal picked(character_id: String, item_id: String)

const FixedCadenceScript := preload("res://scripts/system/core/fixed_cadence.gd")
const BiotaPlaceholderCatalogScript := preload(
	"res://scripts/game/objects/biota_placeholder_catalog.gd")
const VISUAL_KEY := "flora/hushbloom"
const SIGNAL_CHARGED_EMISSION := 0.5
const SIGNAL_SPENT_EMISSION := 0.0
const POLL := 0.25

## HUSHBLOOM (flora_taxonomy): a small nodding flower holding neuroactive compounds — thigmonastic:
## ANY body entering its trigger radius makes it release a STUN BURST (canon: "fires on ANY body",
## so the counterplay is LEADING a pursuer across it). The burst freezes enemies (Enemy.stun) and
## SEALS portals (PortalPad.stun) in its radius — the portal-stun is the chase framework's
## expert-solution mechanic. After a release the core is visibly empty and regenerates over time;
## a charged bloom can be PICKED (click) and carried for a thrown burst (the chunk owns the throw).
## Self-contained like Flure: owns its visual, its proximity poll (scheduler cadence — never
## per-frame), and its burst; the loader injects game state + enemy/portal providers.

const STATE_CONTRACT := "hushbloom/v2"
const PHASE_CHARGED := "charged"
const PHASE_RECHARGING := "recharging"
const PHASE_DISCHARGED := "discharged"
const PHASE_PICKING := "picking"
const PHASE_PICKED := "picked"

@export var trigger_radius := 1.5
@export var stun_radius := 3.4
@export var stun_secs := 6.0
@export var regen_secs := 90.0
@export var pickable := true
## Stable authored identity for save/load and deterministic replay. When omitted, the node name
## and authored origin form an instance-independent fallback identity.
@export var authority_id := ""

var _gs
var _charged := true
var _enemy_provider: Callable = Callable()
var _portal_provider: Callable = Callable()
var _petal_mat: StandardMaterial3D
var _head: MeshInstance3D
var _body: MeshInstance3D
var _visual_root: Node3D
var _visual_meshes: Array[MeshInstance3D] = []
var _effect_origin := Vector3.INF
var _authored_origin := Vector3.ZERO
var _resolved_authority_id := ""
var _armed_poll_tick := -1.0
var _recharge_tick := -1.0
var _restoring_authority := false
var _configured := false

func configure(gs, world_pos: Vector3, opts: Dictionary = {}) -> void:
	_cancel_authoritative_callbacks()
	_gs = gs
	position = world_pos
	_authored_origin = world_pos
	trigger_radius = float(opts.get("trigger_radius", trigger_radius))
	stun_radius = float(opts.get("stun_radius", stun_radius))
	stun_secs = float(opts.get("stun_secs", stun_secs))
	regen_secs = float(opts.get("regen_secs", regen_secs))
	pickable = bool(opts.get("pickable", pickable))
	interaction_radius = 1.1
	interactable_type = InteractableType.INSPECTION
	one_shot = true
	description = "Take the charged hushbloom"
	tutorial_label = "TAKE"
	interaction_enabled = pickable
	_resolved_authority_id = _resolve_authority_id(world_pos)
	_configured = true
	if is_inside_tree():
		_restore_authoritative_runtime()

## Providers: callables returning the live enemy nodes / PortalPads the burst may reach.
func set_enemy_provider(cb: Callable) -> void:
	_enemy_provider = cb

func set_portal_provider(cb: Callable) -> void:
	_portal_provider = cb

func _ready() -> void:
	juice_profile = "plant"   # flora rustle on hover + trigger (InteractableJuice)
	# Exported authority_id may be assigned after configure() but before add_child(). Resolve it at
	# attachment time so authored IDs always win over the deterministic fallback.
	_resolved_authority_id = _resolve_authority_id(_authored_origin)
	if get_node_or_null("CollisionShape3D") == null:
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var sh := SphereShape3D.new()
		sh.radius = interaction_radius
		cs.shape = sh
		add_child(cs)
	_build_visual()
	super._ready()
	if not pickable:
		set_interaction_enabled(false)
	if not interacted.is_connected(_on_picked):
		interacted.connect(_on_picked)
	_wire_outline()
	_ensure_authority_record()
	_restore_authoritative_runtime()

## The shared outline/hover wiring (the Flure pattern) — every visible interactable carries the
## outline grammar; --test-chunk-interactable-outlines enforces it.
func _wire_outline() -> void:
	var mgr := OutlineFeedbackManager.ensure(self)
	if mgr == null or _visual_meshes.is_empty():
		return
	var meshes: Array = []
	for mesh in _visual_meshes:
		if mesh != null and is_instance_valid(mesh):
			meshes.append(mesh)
	var bounds := OutlineFeedbackManager.combined_world_bounds(meshes)
	var target := mgr.outline_meshes(self, str(name) + "Outline", meshes, "hushbloom",
		maxf(1.0, interaction_radius))
	if target == null:
		return
	if target is Node3D:
		(target as Node3D).global_position = bounds.position + bounds.size * 0.5
	if target.has_method("set_interaction_delegate"):
		target.call("set_interaction_delegate", self)
	set_outline_target(target)

func _build_visual() -> void:
	_visual_root = BiotaPlaceholderCatalogScript.instantiate(VISUAL_KEY)
	if _visual_root == null:
		push_error("Hushbloom could not instantiate its portable biota presenter")
		return
	_visual_root.name = "HushbloomVisual"
	_visual_root.set_meta("gameplay_visual_key", VISUAL_KEY)
	add_child(_visual_root)
	_body = _visual_root.get_node_or_null("Body") as MeshInstance3D
	_head = _visual_root.get_node_or_null("Signal") as MeshInstance3D
	_visual_meshes.clear()
	if _body != null:
		_visual_meshes.append(_body)
	if _head != null:
		_visual_meshes.append(_head)
	if _body == null or _head == null:
		push_error("Hushbloom portable presenter requires Body and Signal meshes")
		return
	# Signal state is instance-local. Mutating the scene material directly would make
	# one discharged bloom dim every other bloom that shares the packed resource.
	var source_material := _head.material_override as StandardMaterial3D
	if source_material == null:
		push_error("Hushbloom portable Signal mesh is missing its textured material")
		return
	_petal_mat = source_material.duplicate(true) as StandardMaterial3D
	_petal_mat.resource_local_to_scene = true
	_head.material_override = _petal_mat


func get_visual_presenter() -> Node3D:
	return _visual_root

func _sched():
	return _gs.scheduler if _gs != null else null

func _poll_tag() -> String:
	return "hush_poll_%s" % str(absi(authority_state_key().hash()))


func _regen_tag() -> String:
	return "hush_regen_%s" % str(absi(authority_state_key().hash()))


func _pick_finalize_tag() -> String:
	return "hush_pick_finalize_%s" % str(absi(authority_state_key().hash()))

func _arm_poll() -> void:
	var sched = _sched()
	if sched == null or str(_authority_or_default().get("phase", "")) != PHASE_CHARGED:
		return
	sched.cancel_tag(_poll_tag())
	var saved := _authority_or_default()
	var deadline := _next_poll_deadline(
		float(saved.get("poll_anchor_tick", _scheduler_tick())), _scheduler_tick())
	_armed_poll_tick = deadline
	sched.schedule_at(deadline, _proximity_poll.bind(deadline), _poll_tag())

func _proximity_poll(expected_tick: float = -1.0) -> void:
	if expected_tick >= 0.0 and not is_equal_approx(expected_tick, _armed_poll_tick):
		return
	_armed_poll_tick = -1.0
	if str(_authority_or_default().get("phase", "")) == PHASE_CHARGED \
			and _gs != null and is_visible_in_tree():
		var effect_position := get_effect_origin()
		for id_v in _gs.characters.keys():
			var p: Vector3 = _gs.get_position(str(id_v))
			if Vector2(p.x - effect_position.x, p.z - effect_position.z).length() <= trigger_radius:
				burst(str(id_v))
				break
	if str(_authority_or_default().get("phase", "")) == PHASE_CHARGED:
		_arm_poll()

## Release the stun: freeze every enemy and seal every portal within stun_radius. One shot per
## charge; the core regenerates on the scheduler.
func burst(trigger_body_id := "") -> bool:
	_ensure_authority_record()
	_restore_authoritative_runtime(false)
	var saved := _authority_or_default()
	if str(saved.get("phase", "")) != PHASE_CHARGED:
		return false
	var effect_position := get_effect_origin()
	var enemies := _list(_enemy_provider)
	var portals := _list(_portal_provider)
	var context := Hushbloom.describe_burst(effect_position, enemies, portals, stun_radius)
	var now := _scheduler_tick()
	var recharge_deadline := now + regen_secs \
		if _sched() != null and regen_secs > 0.0 else -1.0
	context["trigger_body_id"] = trigger_body_id
	context["start_tick"] = now
	context["effect_end_tick"] = now + maxf(0.0, stun_secs)
	context["stun_secs"] = stun_secs
	context["stun_radius"] = stun_radius
	saved["phase"] = PHASE_RECHARGING if recharge_deadline >= 0.0 else PHASE_DISCHARGED
	saved["recharge_tick"] = recharge_deadline
	saved["last_effect"] = context.duplicate(true)
	# Commit the empty/recharge phase before any target's stun mutates world state.
	_publish_authority(saved)
	Hushbloom.apply_described_burst(context, enemies, portals, stun_secs)
	burst_fired.emit(effect_position)
	return true

## The shared burst resolution — also the THROWN use (a carried bloom bursting at a target point;
## the chunk that owns the carry calls this directly).
static func burst_at(pos: Vector3, enemies: Array, portals: Array, radius: float, secs: float) -> void:
	for e in enemies:
		if e == null or not is_instance_valid(e) or not e.has_method("stun"):
			continue
		# the DATA position is the truth (enemy nodes only sync per-frame — stale headless)
		var ep: Vector3 = (e as Node3D).global_position
		if "game_state" in e and e.game_state != null and "char_id" in e 				and e.game_state.characters.has(e.char_id):
			ep = e.game_state.get_position(e.char_id)
		if Vector2(ep.x - pos.x, ep.z - pos.z).length() <= radius:
			e.stun(secs)
	for pad in portals:
		if pad == null or not is_instance_valid(pad) or not pad.has_method("stun"):
			continue
		var pp: Vector3 = (pad as Node3D).global_position
		if Vector2(pp.x - pos.x, pp.z - pos.z).length() <= radius:
			pad.stun(secs)

## Pure target classification shared by planted and thrown blooms. It allows the planted bloom to
## publish the exact causal context before consequences fire.
static func describe_burst(pos: Vector3, enemies: Array, portals: Array, radius: float) -> Dictionary:
	var enemy_ids: Array = []
	var portal_ids: Array = []
	for e in enemies:
		if e == null or not is_instance_valid(e) or not e.has_method("stun") or not (e is Node3D):
			continue
		# The DATA position is the truth (enemy nodes only sync per-frame -- stale headless).
		var ep: Vector3 = (e as Node3D).global_position
		if "game_state" in e and e.game_state != null and "char_id" in e \
				and e.game_state.characters.has(e.char_id):
			ep = e.game_state.get_position(e.char_id)
		if Vector2(ep.x - pos.x, ep.z - pos.z).length() <= radius:
			enemy_ids.append(Hushbloom._effect_target_id(e, "enemy"))
	for pad in portals:
		if pad == null or not is_instance_valid(pad) or not pad.has_method("stun") \
				or not (pad is Node3D):
			continue
		var pp: Vector3 = (pad as Node3D).global_position
		if Vector2(pp.x - pos.x, pp.z - pos.z).length() <= radius:
			portal_ids.append(Hushbloom._effect_target_id(pad, "portal"))
	return {
		"origin": [pos.x, pos.y, pos.z],
		"enemy_ids": enemy_ids,
		"portal_ids": portal_ids,
	}


## Apply only targets classified at commitment; a moving body cannot cross the radius between the
## authority write and the consequence and silently change which prediction was resolved.
static func apply_described_burst(context: Dictionary, enemies: Array, portals: Array, secs: float) -> void:
	var enemy_ids: Array = context.get("enemy_ids", []) as Array
	var portal_ids: Array = context.get("portal_ids", []) as Array
	for e in enemies:
		if e != null and is_instance_valid(e) and e.has_method("stun") \
				and enemy_ids.has(Hushbloom._effect_target_id(e, "enemy")):
			e.stun(secs)
	for pad in portals:
		if pad != null and is_instance_valid(pad) and pad.has_method("stun") \
				and portal_ids.has(Hushbloom._effect_target_id(pad, "portal")):
			pad.stun(secs)


static func _effect_target_id(target: Object, fallback_prefix: String) -> String:
	if "char_id" in target and str(target.get("char_id")) != "":
		return str(target.get("char_id"))
	if target.has_method("authority_state_key"):
		return str(target.call("authority_state_key"))
	if target is Node and str((target as Node).name) != "":
		return str((target as Node).name)
	if target is Node3D:
		var pos := (target as Node3D).global_position
		return "%s@%.3f,%.3f,%.3f" % [fallback_prefix, pos.x, pos.y, pos.z]
	return "%s:unnamed" % fallback_prefix


func _list(provider: Callable) -> Array:
	if provider.is_valid():
		var out = provider.call()
		if out is Array:
			return out
	return []

func _recharge() -> void:
	var saved := _authority_or_default()
	if str(saved.get("phase", "")) != PHASE_RECHARGING:
		return
	saved["phase"] = PHASE_CHARGED
	saved["recharge_tick"] = -1.0
	_publish_authority(saved)

func is_charged() -> bool:
	return _charged


func get_effect_origin() -> Vector3:
	return global_position if _effect_origin == Vector3.INF else _effect_origin


## Coordinate-map presenters call this before moving the visible root. Ordinary
## authored scenes retain the original global-position behavior.
func set_effect_origin(origin: Vector3) -> void:
	_effect_origin = origin
	if _configured and not get_authority_state().is_empty():
		var saved := _authority_or_default()
		saved["effect_origin"] = _v3_to_value(origin)
		_publish_authority(saved)

## Pick the charged bloom (the carry verb): the plant becomes a canonical GameState item in the
## interacting character's hand. Publish PICKING before spawning the item so a signal-time save can
## never retain a physical item while leaving a second charged plant behind. A restored PICKING
## record is terminal whenever its source-tagged item exists; when it does not, the interaction is
## visibly retryable because no physical consequence committed.
func pick() -> bool:
	_ensure_authority_record()
	_restore_authoritative_runtime(false)
	var saved := _authority_or_default()
	var phase := str(saved.get("phase", ""))
	if phase == PHASE_PICKING and _source_item_id() == "":
		# A snapshot taken after publication but before spawn owns no item and paid no cost. Permit the
		# same physical interaction to retry instead of trapping the plant in a phantom transaction.
		saved["phase"] = PHASE_CHARGED
		phase = PHASE_CHARGED
	if phase != PHASE_CHARGED or _gs == null:
		return false
	var actor := str(active_character)
	if actor == "" or not _gs.characters.has(actor):
		return false
	var actor_pos: Vector3 = _gs.get_position(actor)
	if Vector2(actor_pos.x - _authored_origin.x, actor_pos.z - _authored_origin.z).length() > 2.0:
		return false
	var hands: Array = (_gs.characters[actor] as Dictionary).get("hands", []) as Array
	if not hands.has(null):
		return false
	saved["phase"] = PHASE_PICKING
	saved["picked_at_tick"] = _scheduler_tick()
	saved["picked_by"] = actor
	saved["carried_item_id"] = ""
	saved["recharge_tick"] = -1.0
	_publish_authority(saved)
	var item_id := str(_gs.spawn_item("hushbloom", _authored_origin, {
		"source_hushbloom": authority_state_key(),
		"source_authority_id": _resolved_authority_id,
		"stun_radius": stun_radius,
		"stun_duration": stun_secs,
	}))
	if item_id == "" or not _gs.pick_up_item(actor, item_id):
		if item_id != "" and _gs.items.has(item_id):
			_gs.remove_item(item_id)
		saved["phase"] = PHASE_CHARGED
		saved["picked_at_tick"] = -1.0
		saved["picked_by"] = ""
		saved["carried_item_id"] = ""
		_publish_authority(saved)
		return false
	saved["phase"] = PHASE_PICKED
	saved["carried_item_id"] = item_id
	_publish_authority(saved)
	picked.emit(actor, item_id)
	return true

func _on_picked() -> void:
	pick()


func authority_state_key() -> String:
	var resolved := _resolved_authority_id
	if resolved.is_empty():
		resolved = authority_id.strip_edges()
	if resolved.is_empty():
		resolved = str(name).strip_edges()
	if resolved.is_empty():
		resolved = "unconfigured"
	return "gameplay:hushbloom:%s" % resolved


func get_authority_state() -> Dictionary:
	if _gs == null or not _gs.has_method("get_world_state"):
		return {}
	var value: Variant = _gs.get_world_state(authority_state_key(), {})
	if not (value is Dictionary):
		return {}
	var saved := (value as Dictionary).duplicate(true)
	if str(saved.get("contract", "")) != STATE_CONTRACT \
			or str(saved.get("authority_id", "")) != _resolved_authority_id:
		return {}
	return saved


func get_effect_state() -> Dictionary:
	var saved := _authority_or_default()
	var now := _scheduler_tick()
	var phase := str(saved.get("phase", PHASE_CHARGED))
	saved["recharge_remaining"] = maxf(
		0.0, float(saved.get("recharge_tick", -1.0)) - now) \
		if phase == PHASE_RECHARGING else 0.0
	saved["next_poll_tick"] = _next_poll_deadline(
		float(saved.get("poll_anchor_tick", now)), now) \
		if phase == PHASE_CHARGED else -1.0
	return saved


func on_game_state_snapshot_restored() -> void:
	super.on_game_state_snapshot_restored()
	_restore_authoritative_runtime()


func _default_authority_record() -> Dictionary:
	return {
		"contract": STATE_CONTRACT,
		"authority_id": _resolved_authority_id,
		"phase": PHASE_CHARGED,
		"poll_anchor_tick": _scheduler_tick(),
		"recharge_tick": -1.0,
		"picked_at_tick": -1.0,
		"picked_by": "",
		"carried_item_id": "",
		"effect_origin": _v3_to_value(get_effect_origin()),
		"trigger_radius": trigger_radius,
		"stun_radius": stun_radius,
		"stun_secs": stun_secs,
		"regen_secs": regen_secs,
		"pickable": pickable,
		"last_effect": {},
	}


func _authority_or_default() -> Dictionary:
	var saved := get_authority_state()
	return _default_authority_record() if saved.is_empty() else saved


func _ensure_authority_record() -> void:
	if not _configured or _gs == null or not get_authority_state().is_empty():
		return
	_publish_authority(_default_authority_record())


func _publish_authority(saved: Dictionary) -> void:
	if _restoring_authority or _gs == null or not _gs.has_method("set_world_state"):
		return
	_gs.set_world_state(authority_state_key(), saved.duplicate(true))
	_restore_authoritative_runtime(false)


func _restore_authoritative_runtime(allow_due_transition := true) -> void:
	if not _configured:
		return
	_cancel_authoritative_callbacks()
	_ensure_authority_record()
	var saved := _authority_or_default()
	var phase := str(saved.get("phase", PHASE_CHARGED))
	var presented_phase := phase
	if phase == PHASE_PICKING:
		presented_phase = PHASE_PICKED if _source_item_id() != "" else PHASE_CHARGED
	var recharge_deadline := float(saved.get("recharge_tick", -1.0))
	if allow_due_transition and phase == PHASE_RECHARGING and recharge_deadline >= 0.0 \
			and recharge_deadline <= _scheduler_tick() + 0.000001:
		_recharge()
		return

	_restoring_authority = true
	trigger_radius = float(saved.get("trigger_radius", trigger_radius))
	stun_radius = float(saved.get("stun_radius", stun_radius))
	stun_secs = float(saved.get("stun_secs", stun_secs))
	regen_secs = float(saved.get("regen_secs", regen_secs))
	pickable = bool(saved.get("pickable", pickable))
	_effect_origin = _v3_from_value(saved.get("effect_origin", get_effect_origin()))
	_charged = presented_phase == PHASE_CHARGED
	_recharge_tick = recharge_deadline if phase == PHASE_RECHARGING else -1.0
	_apply_runtime_surface(presented_phase)
	if phase == PHASE_RECHARGING and recharge_deadline >= 0.0 and _sched() != null:
		_sched().schedule_at(
			recharge_deadline, _on_recharge_deadline.bind(recharge_deadline), _regen_tag())
	elif phase == PHASE_PICKING and _source_item_id() != "" and _sched() != null:
		var pending_item_id := _source_item_id()
		# Restore never emits the pickup or grants another item. It rebuilds one owed zero-delay
		# finalization, so a subsequent save cannot preserve PICKING after the item is spent.
		_sched().schedule_at(_scheduler_tick(),
			_finalize_restored_pick.bind(pending_item_id), _pick_finalize_tag())
	elif phase == PHASE_CHARGED:
		_arm_poll()
	_restoring_authority = false


func _on_recharge_deadline(expected_tick: float) -> void:
	var saved := get_authority_state()
	if str(saved.get("phase", "")) != PHASE_RECHARGING \
			or not is_equal_approx(float(saved.get("recharge_tick", -1.0)), expected_tick):
		return
	_recharge()


func _finalize_restored_pick(expected_item_id: String) -> void:
	var saved := get_authority_state()
	if str(saved.get("phase", "")) != PHASE_PICKING \
			or expected_item_id == "" or _source_item_id() != expected_item_id:
		return
	saved["phase"] = PHASE_PICKED
	saved["carried_item_id"] = expected_item_id
	_publish_authority(saved)


func _apply_runtime_surface(phase: String) -> void:
	visible = phase != PHASE_PICKED
	_used = phase == PHASE_PICKED
	set_interaction_enabled(phase == PHASE_CHARGED and pickable)
	if _head != null:
		# The external signal family is the charged compound reservoir. Body leaves
		# remain after a burst; the luminous crown returns only when authority says
		# the bloom has recharged.
		_head.visible = phase == PHASE_CHARGED
	if _petal_mat == null:
		return
	match phase:
		PHASE_CHARGED:
			_petal_mat.emission_enabled = true
			_petal_mat.emission_energy_multiplier = SIGNAL_CHARGED_EMISSION
			_petal_mat.albedo_color = Color.WHITE
		PHASE_PICKED:
			_petal_mat.emission_energy_multiplier = SIGNAL_SPENT_EMISSION
			_petal_mat.albedo_color = Color(0.24, 0.24, 0.26)
		_:
			_petal_mat.emission_energy_multiplier = SIGNAL_SPENT_EMISSION
			_petal_mat.albedo_color = Color(0.38, 0.38, 0.4)


func _source_item_id() -> String:
	if _gs == null:
		return ""
	var expected_key := authority_state_key()
	for item_id_v in _gs.items.keys():
		var item_id := str(item_id_v)
		var item: Dictionary = _gs.items[item_id_v]
		var properties: Dictionary = item.get("properties", {}) as Dictionary
		if str(item.get("type", "")) == "hushbloom" \
				and str(properties.get("source_hushbloom", "")) == expected_key:
			return item_id
	return ""


func _next_poll_deadline(anchor: float, now: float) -> float:
	return FixedCadenceScript.next_strict_tick(anchor, POLL, now)


func _cancel_authoritative_callbacks() -> void:
	if _sched() != null:
		_sched().cancel_tag(_poll_tag())
		_sched().cancel_tag(_regen_tag())
		_sched().cancel_tag(_pick_finalize_tag())
	_armed_poll_tick = -1.0
	_recharge_tick = -1.0


func _scheduler_tick() -> float:
	return float(_sched().get_current_tick()) if _sched() != null else 0.0


func _resolve_authority_id(origin: Vector3) -> String:
	var explicit := authority_id.strip_edges()
	if not explicit.is_empty():
		return explicit
	var node_id := str(name).strip_edges()
	if node_id.is_empty():
		node_id = "hushbloom"
	return "%s@%s" % [node_id, _vector_signature(origin)]


func _vector_signature(value: Vector3) -> String:
	return "%.3f,%.3f,%.3f" % [value.x, value.y, value.z]


func _v3_to_value(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _v3_from_value(value: Variant) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array and (value as Array).size() >= 3:
		return Vector3(
			float((value as Array)[0]),
			float((value as Array)[1]),
			float((value as Array)[2])
		)
	return Vector3.INF


func _exit_tree() -> void:
	_cancel_authoritative_callbacks()
