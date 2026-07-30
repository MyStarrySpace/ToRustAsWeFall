class_name Channel
extends Node3D

## A wash CHANNEL: a flood strip that surges on a scheduler cadence (a row of them phased so at least one is always
## flooding — you can't just walk across). Anything standing in it WHILE it floods is swept off; the fragment asks
## floods_at() and applies the effect (drown the hunters, wash the party back). Self-contained: owns its bed + water
## visual and its flood cadence (scheduler-driven, so replay + fast-forward safe — never a wall clock). A fragment
## composes a row of these; a level builder places + phases them.

signal telegraphed()
signal flood_started()
signal flood_ended()

## Cosmetic pre-onset tell (P9: telegraph the NEXT onset): > 0 emits `telegraphed`
## this many seconds before each onset (scheduler tag <tag>_telegraph). The tell
## is presentation only — the cadence math never reads it.
@export var telegraph_lead := 0.0

## A composing chunk that binds its OWN modeled visuals to this channel's signals
## (the piece-built scenes) turns this off; the kit then owns data + sweep only,
## and builds no bed/water meshes of its own.
@export var owns_visuals := true

const WaterShader := preload("res://resources/channels_water.gdshader")
const FixedCadenceScript := preload("res://scripts/system/core/fixed_cadence.gd")
const STATE_CONTRACT := "channel/v3"
const LEGACY_STATE_CONTRACT_V2 := "channel/v2"
const LEGACY_STATE_CONTRACT_V1 := "channel/v1"
const MIN_CADENCE := 0.000001
const SWEEP_POLL_INTERVAL := 0.5
const SWEEP_FIRST_POLL_DELAY := 0.05
const DEFAULT_SWEEP_TRAVEL_SPEED := 6.0
const DEFAULT_SWEEP_MIN_TRAVEL_DURATION := 0.45
const SWEEP_PHASE_RESERVED := "reserved"
const SWEEP_PHASE_CARRYING := "carrying"
const SWEEP_PHASE_IMPACT_PENDING := "impact_pending"
const SWEEP_PHASE_PARTY_DAMAGE_COMMITTING := "party_damage_committing"
const SWEEP_PHASE_PARTY_DOWNING_PENDING := "party_downing_pending"
const SWEEP_PHASE_ENEMY_DAMAGE_COMMITTING := "enemy_damage_committing"
const SWEEP_PHASE_ENEMY_STUN_COMMITTING := "enemy_stun_committing"

var _flooding := false
var _running := false
var _scheduler
var _game_state = null
var _bed: MeshInstance3D
var _water: MeshInstance3D
var _x := 0.0
var _half := 1.25
var _z_half := 5.0
var _z_center := 0.0
var _period := 3.0
var _dur := 1.6
var _phase := 0.0
var _tag := "channel"
var _cycle_epoch := -1.0
var _sweep_epoch := -1.0
var _next_onset_tick := -1.0
var _next_off_tick := -1.0
var _next_sweep_tick := -1.0
var _restoring := false
var _held_until := -1.0

## Configure BEFORE adding to the tree. `tag` scopes this channel's scheduler events (unique per
## channel). `z_center` shifts the strip's lateral footprint (a band that is not centred on z=0,
## e.g. the wash-ascent front band) — footprint math only, cadence untouched.
func configure(x: float, half: float, z_half: float, period: float, dur: float, phase: float,
		tag: String, z_center := 0.0) -> void:
	_x = x
	_half = half
	_z_half = z_half
	_z_center = z_center
	_period = maxf(MIN_CADENCE, period)
	_dur = maxf(MIN_CADENCE, dur)
	_phase = maxf(0.0, phase)
	_tag = tag

## THE SWEEP (P-KIT): a flooding channel carries away whatever stands in it -- the wash is the
## visible mechanism, so the consequence lives HERE, never in a chunk script. While flooding, a
## scheduler poll catches each ground-level body in the strip and starts a GameState-owned traversal
## to wherever the level's policy says "downstream" is (the dest Callable -- the only spatial policy
## a chunk supplies). Arrival charges the party's fail-forward hp bite or tumbles the enemy. A per-body
## refractory prevents the sweep -> land -> re-enter -> re-sweep death spiral.
var _sweep_enabled := false
var _sweep_gs = null
var _sweep_party: Array = []
var _sweep_dest := Callable()
var _sweep_party_hp := 6.0
var _sweep_enemy_damage := 0.0
var _sweep_enemy_stun := 2.5
var _sweep_refractory_secs := 4.0
var _sweep_enemy_resolver := Callable()
var _sweep_on_swept := Callable()
var _sweep_on_enemy_swept := Callable()
var _sweep_refractory := {}
var _sweep_active := {}
var _sweep_travel_speed := DEFAULT_SWEEP_TRAVEL_SPEED
var _sweep_min_travel_duration := DEFAULT_SWEEP_MIN_TRAVEL_DURATION
var _sweep_signal_gs = null

## dest: (id, pos) -> Vector3 landing point. opts: party_hp, enemy_stun, refractory,
## enemy_damage, travel_speed, min_travel_duration, enemy_resolver (id -> Enemy node, for the
## tumble), and bookkeeping-only on_swept/on_enemy_swept callbacks. Consequence-grade damage
## remains owned by this visible kit object; a composing chunk may only count or announce the
## arrival that the channel already resolved.
func set_sweep(gs, party_ids: Array, dest: Callable, opts: Dictionary = {}) -> void:
	_sweep_gs = gs
	_game_state = gs
	# A composed current may receive explicit wet-window requests without owning a second cadence.
	# Bind the same gameplay clock here; start() remains the opt-in that arms this Channel's cadence.
	if gs != null and gs.get("scheduler") != null:
		_scheduler = gs.get("scheduler")
	_sweep_party = party_ids.duplicate()
	_sweep_dest = dest
	_sweep_party_hp = maxf(0.0, float(opts.get("party_hp", 6.0)))
	_sweep_enemy_damage = maxf(0.0, float(opts.get("enemy_damage", 0.0)))
	_sweep_enemy_stun = maxf(0.0, float(opts.get("enemy_stun", 2.5)))
	_sweep_refractory_secs = maxf(0.0, float(opts.get("refractory", 4.0)))
	_sweep_travel_speed = maxf(MIN_CADENCE,
		float(opts.get("travel_speed", DEFAULT_SWEEP_TRAVEL_SPEED)))
	_sweep_min_travel_duration = maxf(MIN_CADENCE,
		float(opts.get("min_travel_duration", DEFAULT_SWEEP_MIN_TRAVEL_DURATION)))
	_sweep_enemy_resolver = opts.get("enemy_resolver", Callable())
	_sweep_on_swept = opts.get("on_swept", Callable())
	_sweep_on_enemy_swept = opts.get("on_enemy_swept", Callable())
	_sweep_enabled = true
	_connect_sweep_signals()
	# A sweep policy may be attached after a flooding channel was restored. Re-arm the saved poll
	# rather than waiting for the next onset and silently granting immunity for this surge.
	if _flooding and _running and _scheduler != null and _next_sweep_tick >= 0.0:
		if _sweep_epoch < 0.0:
			_sweep_epoch = _next_sweep_tick
		_schedule_sweep_at(_next_sweep_from_epoch())
	# Fresh-presenter construction can happen after GameState has already been restored. Never
	# overwrite that saved current with a constructor baseline; attach to it instead.
	var existing: Variant = _game_state.get_world_state(authority_state_key(), null) \
		if _game_state != null and _game_state.has_method("get_world_state") else null
	if existing is Dictionary and not (existing as Dictionary).is_empty():
		restore_state(existing as Dictionary)
	else:
		_publish_authoritative_state()

## An explicit restart/checkpoint clears the refractory window. Ordinary save/load preserves its
## absolute deadlines so repeated loading cannot make a body immune or repeatedly bite it.
func clear_sweep_refractory() -> void:
	_sweep_refractory.clear()
	_publish_authoritative_state()

func _ready() -> void:
	if not owns_visuals:
		return
	_bed = MeshInstance3D.new()
	_bed.name = "Bed"
	var bb := BoxMesh.new()
	bb.size = Vector3(_half * 2.0, 0.18, _z_half * 2.0)
	_bed.mesh = bb
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.05, 0.07, 0.09)
	_bed.material_override = bmat
	_bed.position = Vector3(_x, -0.16, 0.0)
	add_child(_bed)
	_water = MeshInstance3D.new()
	_water.name = "Water"
	var wm := BoxMesh.new()
	wm.size = Vector3(_half * 2.0, 0.34, _z_half * 2.0)
	_water.mesh = wm
	var wmat := ShaderMaterial.new()
	wmat.shader = WaterShader
	wmat.render_priority = 127
	_water.material_override = wmat
	_water.position = Vector3(_x, 0.12, 0.0)
	_water.visible = _flooding
	add_child(_water)

## Begin the flood cadence on the gameplay scheduler (so it pauses + fast-forwards with gameplay). Call once the
## scheduler exists; reset() cancels it. GameState is injected explicitly so the phase survives save/load.
func start(scheduler, game_state = null) -> void:
	_cancel_callbacks()
	_scheduler = scheduler
	if game_state != null:
		_game_state = game_state
	elif _sweep_gs != null:
		_game_state = _sweep_gs
	if _scheduler == null:
		return
	_running = true
	_flooding = false
	_cycle_epoch = _scheduler_tick() + _phase + 0.01
	_sweep_epoch = -1.0
	_next_off_tick = -1.0
	_next_sweep_tick = -1.0
	_schedule_onset_at(_cycle_epoch)
	_schedule_telegraph_for(_cycle_epoch)
	_apply_water_visibility()
	_publish_authoritative_state()

func _onset() -> void:
	if not _running or _scheduler == null:
		return
	# A forced onset resets this one cadence chain instead of creating a second overlapping loop.
	_cancel_callback_tags()
	var now := _scheduler_tick()
	_flooding = true
	_cycle_epoch = now
	_next_off_tick = now + _dur
	_next_onset_tick = now + _period
	_schedule_off_at(_next_off_tick)
	_schedule_onset_at(_next_onset_tick)
	if _sweep_enabled:
		_sweep_epoch = now + SWEEP_FIRST_POLL_DELAY
		_schedule_sweep_at(_sweep_epoch)
	else:
		_sweep_epoch = -1.0
		_next_sweep_tick = -1.0
	_schedule_telegraph_for(_next_onset_tick)
	_apply_water_visibility()
	_publish_authoritative_state()
	flood_started.emit()

func _off() -> void:
	if not _running:
		return
	_flooding = false
	_sweep_epoch = -1.0
	_next_off_tick = -1.0
	_next_sweep_tick = -1.0
	if _scheduler != null:
		_scheduler.cancel_tag(_tag + "_off")
		_scheduler.cancel_tag(_tag + "_sweep")
	_apply_water_visibility()
	_publish_authoritative_state()
	flood_ended.emit()

func is_flooding() -> bool:
	return _flooding

## True if (x, z) is inside this channel AND it is flooding right now — i.e. a character there gets swept.
func floods_at(x: float, z: float) -> bool:
	return _flooding and absf(x - _x) <= _half and absf(z - _z_center) <= _z_half

func _sweep_poll() -> void:
	_next_sweep_tick = -1.0
	if not _flooding or not _sweep_enabled or _sweep_gs == null or _scheduler == null:
		return
	var now: float = float(_scheduler.get_current_tick())
	# Publishable transactions created below must already contain the continuing cadence. Otherwise
	# a save from `external_traversal_started` would reconstruct the carry but silently lose the
	# remainder of this wet phase's catch polls.
	if _flooding and _running:
		_schedule_sweep_at(now + SWEEP_POLL_INTERVAL)
	for id_v in _sweep_gs.characters.keys():
		var id := str(id_v)
		if _sweep_active.has(id) or _sweep_gs.is_external_traversal_active(id):
			continue
		if now < float(_sweep_refractory.get(id, -100.0)):
			continue
		var p: Vector3 = _sweep_gs.get_position(id)
		if p.y > 1.5 or not floods_at(p.x, p.z):
			continue
		var target_kind := "party" if id in _sweep_party else "enemy"
		if target_kind == "enemy":
			if not _sweep_enemy_resolver.is_valid():
				continue
			var candidate: Variant = _sweep_enemy_resolver.call(id)
			if candidate == null:
				continue
		if not _begin_sweep_traversal(id, p, target_kind, now):
			continue


## Compose this current with an externally-authored wet window. Some levels already own a shared
## flood cadence and visible water across several differently-shaped footprints; they still route a
## caught body through this reusable Channel transaction instead of duplicating a teleport/death
## shortcut. The caller may request the carry only at its exact wet-footprint consequence tick.
## Channel remains the owner of RESERVED -> CARRYING -> IMPACT, damage, and downstream callbacks.
func request_sweep_body(id: String, target_kind: String = "enemy") -> bool:
	if not _sweep_enabled or _sweep_gs == null or _scheduler == null \
			or target_kind not in ["party", "enemy"] \
			or not _sweep_gs.characters.has(id) \
			or _sweep_active.has(id) \
			or _sweep_gs.is_external_traversal_active(id):
		return false
	if target_kind == "enemy":
		if not _sweep_enemy_resolver.is_valid():
			return false
		var candidate: Variant = _sweep_enemy_resolver.call(id)
		if candidate == null:
			return false
	return _begin_sweep_traversal(
		id, _sweep_gs.get_position(id), target_kind, _scheduler_tick())


## A caught body enters the same locked, scheduler-owned traversal used by every other physical
## carry/climb in the game. Its data position and render position now advance together; the body is
## never still logically standing at the mouth while a presentation pretends the current moved it.
##
## The reservation is authoritative BEFORE GameState starts the traversal. GameState emits
## `external_traversal_started` synchronously, so installing this receipt afterward creates a torn
## save: the body is owned by the current but the current denies owning it. The reserved phase also
## contains enough geometry to finish reconstruction if a save happens from the reservation's own
## world-state signal.
func _begin_sweep_traversal(id: String, origin: Vector3, target_kind: String, now: float) -> bool:
	if not _sweep_dest.is_valid() or not _sweep_gs.has_method("command_external_traversal"):
		return false
	var destination_value: Variant = _sweep_dest.call(id, origin)
	if not destination_value is Vector3:
		return false
	var destination := destination_value as Vector3
	if not destination.is_finite():
		return false
	var distance := origin.distance_to(destination)
	var duration := maxf(_sweep_min_travel_duration, distance / _sweep_travel_speed)
	var render_origin: Vector3 = _sweep_gs.get_render_position(id) \
		if _sweep_gs.has_method("get_render_position") else origin
	var render_destination: Vector3 = destination
	if _sweep_gs.coord_map != null:
		render_destination = _sweep_gs.coord_map.to_world(destination)
	var traversal_id := _sweep_traversal_id(id)
	var refractory_tick := now + _sweep_refractory_secs
	# A damage shield is consulted AT THE CATCH — the wave hits the body the
	# moment the water takes it, and a Wrap that was live THEN protects the
	# whole ride, however far downstream the landing is (sweep-to-start made
	# rides longer than any shield window). The shield spends now; only the
	# unabsorbed REMAINDER travels to the arrival impact, which stays the
	# one boundary where hp/stun bookkeeping happens.
	var catch_hp := _sweep_party_hp
	if target_kind == "party" and _sweep_gs != null 			and _sweep_gs.has_method("_resolve_incoming_damage"):
		catch_hp = float(_sweep_gs.call("_resolve_incoming_damage", id, _sweep_party_hp))
	var pending := {
		"traversal_id": String(traversal_id),
		"phase": SWEEP_PHASE_RESERVED,
		"target_kind": target_kind,
		"started_tick": now,
		"impact_tick": now + duration,
		"data_origin": _v3_to_portable(origin),
		"data_destination": _v3_to_portable(destination),
		"render_origin": _v3_to_portable(render_origin),
		"render_destination": _v3_to_portable(render_destination),
		"party_hp": catch_hp,
		"enemy_damage": _sweep_enemy_damage,
		"enemy_stun": _sweep_enemy_stun,
		"refractory_tick": refractory_tick,
	}
	_sweep_active[id] = pending
	_sweep_refractory[id] = refractory_tick
	_publish_authoritative_state()

	var accepted := bool(_sweep_gs.command_external_traversal(
		id, traversal_id, destination, render_origin, render_destination, duration, &"locked"))
	# A save/load listener may reconstruct the just-published reservation synchronously. In that
	# case the original command correctly refuses a second traversal; the exact owned traversal is
	# nevertheless the accepted result.
	if not accepted and _has_matching_external_traversal(id, String(traversal_id)):
		accepted = true
	if not accepted:
		if _sweep_active.has(id) and str((_sweep_active[id] as Dictionary).get(
				"traversal_id", "")) == String(traversal_id):
			_sweep_active.erase(id)
		if is_equal_approx(float(_sweep_refractory.get(id, -1.0)), refractory_tick):
			_sweep_refractory.erase(id)
		_publish_authoritative_state()
		return false
	if _sweep_active.has(id):
		pending = _sweep_active[id] as Dictionary
		if str(pending.get("traversal_id", "")) == String(traversal_id) \
				and str(pending.get("phase", "")) == SWEEP_PHASE_RESERVED:
			pending["phase"] = SWEEP_PHASE_CARRYING
			_sweep_active[id] = pending
			_publish_authoritative_state()
	return true


## Arrival is the impact boundary. Damage, stun, and bookkeeping all happen here, after the body is
## visibly downstream, never at the earlier poll that merely discovered it in the water.
func _on_external_traversal_finished(id: String, traversal_id: StringName) -> void:
	if not _sweep_active.has(id):
		return
	var pending: Dictionary = _sweep_active[id]
	if str(pending.get("traversal_id", "")) != String(traversal_id):
		return
	pending["phase"] = SWEEP_PHASE_IMPACT_PENDING
	_sweep_active[id] = pending
	# GameState erased its traversal before emitting this signal. Publish the explicit arrival
	# transaction before damage/stun can emit their own synchronous stat/death signals.
	_publish_authoritative_state()
	_drive_sweep_impact(id)


func _on_external_traversal_cancelled(
		id: String, traversal_id: StringName, _reason: StringName) -> void:
	if not _sweep_active.has(id):
		return
	var pending: Dictionary = _sweep_active[id]
	if str(pending.get("traversal_id", "")) != String(traversal_id):
		return
	# Cancellation freezes the body where the interrupt happened. It is not an arrival, so the
	# downstream bite/stun must not be smuggled through as though the carry completed.
	if str(pending.get("phase", "")) in [SWEEP_PHASE_RESERVED, SWEEP_PHASE_CARRYING]:
		_sweep_active.erase(id)
		_apply_water_visibility()
		_publish_authoritative_state()


func _drive_sweep_impact(id: String) -> void:
	if not _sweep_active.has(id) or _sweep_gs == null:
		return
	var pending: Dictionary = _sweep_active[id]
	var phase := str(pending.get("phase", ""))
	var target_kind := str(pending.get("target_kind", ""))
	if target_kind == "party":
		_drive_party_impact(id, pending, phase)
		return
	if target_kind == "enemy":
		_drive_enemy_impact(id, pending, phase)
		return
	push_error("Channel %s discarded invalid impact target %s for %s" % [_tag, target_kind, id])
	_complete_sweep_transaction(id, target_kind)


func _drive_party_impact(id: String, pending: Dictionary, phase: String) -> void:
	if not _sweep_gs.characters.has(id):
		_complete_sweep_transaction(id, "party")
		return
	if phase == SWEEP_PHASE_IMPACT_PENDING:
		var hp_before := float(_sweep_gs.get_stat(id, "hp"))
		var shield_before := _party_shield(id)
		var incoming := maxf(0.0, float(pending.get("party_hp", _sweep_party_hp)))
		var shield_after := maxf(0.0, shield_before - incoming)
		var hp_after := maxf(0.0, hp_before - maxf(0.0, incoming - shield_before))
		pending["hp_before"] = hp_before
		pending["hp_after"] = hp_after
		pending["shield_before"] = shield_before
		pending["shield_after"] = shield_after
		pending["phase"] = SWEEP_PHASE_PARTY_DAMAGE_COMMITTING
		_sweep_active[id] = pending
		_publish_authoritative_state()
		_sweep_gs.adjust_stat(id, "hp", -incoming)
		_continue_party_damage(id)
		return
	if phase == SWEEP_PHASE_PARTY_DAMAGE_COMMITTING:
		var hp_now := float(_sweep_gs.get_stat(id, "hp"))
		var shield_now := _party_shield(id)
		var hp_before := float(pending.get("hp_before", hp_now))
		var hp_after := float(pending.get("hp_after", hp_now))
		var shield_before := float(pending.get("shield_before", shield_now))
		var shield_after := float(pending.get("shield_after", shield_now))
		if is_equal_approx(hp_now, hp_after) and is_equal_approx(shield_now, shield_after):
			_continue_party_damage(id)
			return
		if is_equal_approx(hp_now, hp_before) and is_equal_approx(shield_now, shield_before):
			_sweep_gs.adjust_stat(
				id, "hp", -maxf(0.0, float(pending.get("party_hp", _sweep_party_hp))))
			_continue_party_damage(id)
			return
		# A save from damage-shield feedback can observe the shield debit before set_stat emits the
		# HP signal. Complete the already-resolved residual damage as an absolute value rather than
		# charging the shield a second time.
		if is_equal_approx(hp_now, hp_before) and is_equal_approx(shield_now, shield_after):
			_sweep_gs.set_stat(id, "hp", hp_after)
			_continue_party_damage(id)
			return
		push_error("Channel %s found an unrecognised partial party impact for %s" % [_tag, id])
		return
	if phase == SWEEP_PHASE_PARTY_DOWNING_PENDING:
		if _sweep_gs.has_method("is_downed") and not _sweep_gs.is_downed(id) \
				and _sweep_gs.has_method("down_character"):
			_sweep_gs.down_character(id)
		_complete_sweep_transaction(id, "party")


func _continue_party_damage(id: String) -> void:
	if not _sweep_active.has(id):
		return
	var pending: Dictionary = _sweep_active[id]
	if str(pending.get("phase", "")) != SWEEP_PHASE_PARTY_DAMAGE_COMMITTING:
		return
	var hp_after := float(pending.get("hp_after", _sweep_gs.get_stat(id, "hp")))
	if hp_after <= 0.0 and _sweep_gs.has_method("is_downed") and not _sweep_gs.is_downed(id):
		pending["phase"] = SWEEP_PHASE_PARTY_DOWNING_PENDING
		_sweep_active[id] = pending
		_publish_authoritative_state()
		if _sweep_gs.has_method("down_character"):
			_sweep_gs.down_character(id)
	_complete_sweep_transaction(id, "party")


func _drive_enemy_impact(id: String, pending: Dictionary, phase: String) -> void:
	if not _sweep_enemy_resolver.is_valid():
		_complete_sweep_transaction(id, "enemy")
		return
	var foe: Variant = _sweep_enemy_resolver.call(id)
	if foe == null:
		_complete_sweep_transaction(id, "enemy")
		return
	if phase == SWEEP_PHASE_IMPACT_PENDING:
		var hp_before := _enemy_hp(foe, id)
		var damage := maxf(0.0, float(pending.get("enemy_damage", _sweep_enemy_damage)))
		pending["enemy_hp_before"] = hp_before
		pending["enemy_hp_after"] = maxf(0.0, hp_before - damage)
		pending["phase"] = SWEEP_PHASE_ENEMY_DAMAGE_COMMITTING
		_sweep_active[id] = pending
		_publish_authoritative_state()
		if damage > 0.0 and foe.has_method("take_damage"):
			foe.take_damage(damage)
		_continue_enemy_damage(id, foe)
		return
	if phase == SWEEP_PHASE_ENEMY_DAMAGE_COMMITTING:
		var hp_now := _enemy_hp(foe, id)
		var hp_before := float(pending.get("enemy_hp_before", hp_now))
		var hp_after := float(pending.get("enemy_hp_after", hp_now))
		if is_equal_approx(hp_now, hp_after):
			_continue_enemy_damage(id, foe)
			return
		if is_equal_approx(hp_now, hp_before):
			var damage := maxf(0.0, float(pending.get("enemy_damage", _sweep_enemy_damage)))
			if damage > 0.0 and foe.has_method("take_damage"):
				foe.take_damage(damage)
			_continue_enemy_damage(id, foe)
			return
		push_error("Channel %s found an unrecognised partial enemy impact for %s" % [_tag, id])
		return
	if phase == SWEEP_PHASE_ENEMY_STUN_COMMITTING:
		if not _enemy_stun_has_committed(foe):
			var stun_duration := maxf(
				0.0, float(pending.get("enemy_stun", _sweep_enemy_stun)))
			if stun_duration > 0.0 and foe.has_method("stun"):
				foe.stun(stun_duration)
		_complete_sweep_transaction(id, "enemy")


func _continue_enemy_damage(id: String, foe: Variant) -> void:
	if not _sweep_active.has(id):
		return
	var pending: Dictionary = _sweep_active[id]
	if str(pending.get("phase", "")) != SWEEP_PHASE_ENEMY_DAMAGE_COMMITTING:
		return
	var foe_alive: bool = not foe.has_method("is_alive") or bool(foe.call("is_alive"))
	var stun_duration := maxf(0.0, float(pending.get("enemy_stun", _sweep_enemy_stun)))
	if foe_alive and stun_duration > 0.0 and foe.has_method("stun"):
		pending["phase"] = SWEEP_PHASE_ENEMY_STUN_COMMITTING
		_sweep_active[id] = pending
		_publish_authoritative_state()
		if not _enemy_stun_has_committed(foe):
			foe.stun(stun_duration)
	_complete_sweep_transaction(id, "enemy")


func _complete_sweep_transaction(id: String, target_kind: String) -> void:
	if not _sweep_active.has(id):
		return
	_sweep_active.erase(id)
	_apply_water_visibility()
	# The consequence receipt disappears before bookkeeping-only callbacks run. A save raised by a
	# callback therefore cannot replay damage/stun or invoke the callback twice.
	_publish_authoritative_state()
	if target_kind == "party" and _sweep_on_swept.is_valid():
		_sweep_on_swept.call(id)
	elif target_kind == "enemy" and _sweep_on_enemy_swept.is_valid():
		_sweep_on_enemy_swept.call(id)


func _party_shield(id: String) -> float:
	return float(_sweep_gs.get_damage_shield(id)) \
		if _sweep_gs != null and _sweep_gs.has_method("get_damage_shield") else 0.0


func _enemy_hp(foe: Variant, id: String) -> float:
	if foe != null and foe.has_method("get_hp"):
		return float(foe.call("get_hp"))
	if _sweep_gs != null and _sweep_gs.characters.has(id):
		return float(_sweep_gs.get_stat(id, "hp"))
	return 0.0


func _enemy_stun_has_committed(foe: Variant) -> bool:
	return foe != null and foe.has_method("is_stunned") and bool(foe.call("is_stunned"))

## Force a flood onset now (scripted beats / tests).
func flood_now() -> void:
	if _scheduler == null:
		_flooding = true
		_apply_water_visibility()
		_publish_authoritative_state()
		return
	_running = true
	_onset()

## The valve verb: quiet this channel for `duration` seconds. An in-flight flood
## ends immediately; onsets the hold swallows skip to the first cadence beat after
## it lifts (epoch arithmetic — analytic, replay/fast-forward safe). Presentation
## reacts through the existing flood_ended/telegraphed signals; the hold is data.
func hold(duration: float) -> void:
	if _scheduler == null or not _running:
		return
	_held_until = _scheduler_tick() + maxf(0.0, duration)
	if _flooding:
		_off()
	_cancel_callback_tags()
	var next := _cycle_epoch
	while next <= _held_until:
		next += _period
	_schedule_onset_at(next)
	_schedule_telegraph_for(next)
	_publish_authoritative_state()

func held_until() -> float:
	return _held_until

func _schedule_telegraph_for(onset_tick: float) -> void:
	if telegraph_lead <= 0.0 or _scheduler == null:
		return
	_scheduler.cancel_tag(_tag + "_telegraph")
	_scheduler.schedule_after(maxf(0.0, onset_tick - telegraph_lead - _scheduler_tick()),
		_emit_telegraph, _tag + "_telegraph")

func _emit_telegraph() -> void:
	if _running and not _flooding:
		telegraphed.emit()

func reset() -> void:
	_restoring = true
	_cancel_owned_sweeps(&"channel_reset")
	_restoring = false
	_cancel_callbacks()
	_running = false
	_flooding = false
	_cycle_epoch = -1.0
	_sweep_epoch = -1.0
	_next_onset_tick = -1.0
	_next_off_tick = -1.0
	_next_sweep_tick = -1.0
	_apply_water_visibility()
	_sweep_refractory.clear()
	_sweep_active.clear()
	_publish_authoritative_state()


## Portable cadence truth. Cycle epoch and deadlines are absolute gameplay-scheduler ticks, so a
## snapshot taken halfway through either the wet or dry phase does not restart that phase on load.
func get_state() -> Dictionary:
	return {
		"contract": STATE_CONTRACT,
		"tag": _tag,
		"running": _running,
		"flooding": _flooding,
		"cycle_epoch": _cycle_epoch,
		"sweep_epoch": _sweep_epoch,
		"next_onset_tick": _next_onset_tick,
		"next_off_tick": _next_off_tick,
		"next_sweep_tick": _next_sweep_tick,
		"next_onset_in": _remaining_until(_next_onset_tick),
		"next_off_in": _remaining_until(_next_off_tick),
		"next_sweep_in": _remaining_until(_next_sweep_tick),
		"held_until": _held_until,
		"period": _period,
		"duration": _dur,
		"phase": _phase,
		"sweep_refractory": _portable_refractory(),
		"active_sweeps": _portable_active_sweeps(),
	}


func serialize_state() -> Dictionary:
	return get_state().duplicate(true)


## Reattach presentation and fresh Callables to the authoritative GameState record. No synthetic
## onset/off/sweep is emitted during restore; due transitions execute exactly once on the scheduler.
func restore_state(snapshot: Dictionary) -> bool:
	var contract := str(snapshot.get("contract", ""))
	if contract not in [STATE_CONTRACT, LEGACY_STATE_CONTRACT_V2, LEGACY_STATE_CONTRACT_V1]:
		return false
	if str(snapshot.get("tag", "")) != _tag or _scheduler == null or _game_state == null:
		return false
	var saved_period := float(snapshot.get("period", -1.0))
	var saved_duration := float(snapshot.get("duration", -1.0))
	var saved_phase := float(snapshot.get("phase", -1.0))
	if saved_period < MIN_CADENCE or saved_duration < MIN_CADENCE or saved_phase < 0.0:
		return false
	var refractory: Variant = _validated_refractory(snapshot.get("sweep_refractory", {}))
	if refractory == null:
		return false
	var active: Variant = _validated_active_sweeps(
		snapshot.get("active_sweeps", {})
			if contract in [STATE_CONTRACT, LEGACY_STATE_CONTRACT_V2] else {},
		contract)
	if active == null:
		return false
	if not _active_sweeps_match_game_state(active as Dictionary):
		return false
	if contract == LEGACY_STATE_CONTRACT_V2:
		_hydrate_v2_sweep_transactions(active as Dictionary, refractory as Dictionary)

	_restoring = true
	_cancel_callbacks()
	_period = saved_period
	_dur = saved_duration
	_phase = saved_phase
	_running = bool(snapshot.get("running", false))
	_flooding = bool(snapshot.get("flooding", false)) if _running else false
	_cycle_epoch = float(snapshot.get("cycle_epoch", -1.0))
	_sweep_epoch = float(snapshot.get("sweep_epoch", -1.0))
	_next_onset_tick = _saved_deadline(snapshot, "next_onset_tick", "next_onset_in")
	_next_off_tick = _saved_deadline(snapshot, "next_off_tick", "next_off_in")
	_next_sweep_tick = _saved_deadline(snapshot, "next_sweep_tick", "next_sweep_in")
	if _sweep_epoch < 0.0 and _next_sweep_tick >= 0.0:
		# v1 records written during the migration may only carry their next poll deadline.
		_sweep_epoch = _next_sweep_tick
	_sweep_refractory = (refractory as Dictionary).duplicate(true)
	_sweep_active = (active as Dictionary).duplicate(true)
	_connect_sweep_signals()

	if _running:
		if _next_onset_tick < 0.0:
			_restoring = false
			return false
		if _flooding and _next_off_tick < 0.0:
			_restoring = false
			return false
		# Preserve original callback order for coincident boundaries: the old wet phase ends before
		# the next onset begins. Normal authored channels have duration < period.
		if _flooding:
			_schedule_off_at(maxf(_scheduler_tick(), _next_off_tick))
		_schedule_onset_at(maxf(_scheduler_tick(), _next_onset_tick))
		if _flooding and _sweep_enabled and _sweep_epoch >= 0.0:
			_schedule_sweep_at(_next_sweep_from_epoch())
	else:
		_sweep_epoch = -1.0
		_next_onset_tick = -1.0
		_next_off_tick = -1.0
		_next_sweep_tick = -1.0
	_apply_water_visibility()
	_restoring = false
	_reconcile_sweep_transactions()
	return true


func authority_state_key() -> String:
	return "kit:channel:%s" % _tag


func restore_from_authority() -> bool:
	if _game_state == null or not _game_state.has_method("get_world_state"):
		return false
	var saved: Variant = _game_state.get_world_state(authority_state_key(), null)
	return restore_state(saved as Dictionary) if saved is Dictionary else false


## Called by the production save loader after it replaces GameState and clears scheduler Callables.
func on_game_state_snapshot_restored() -> void:
	if restore_from_authority():
		return
	# No authority record means the loaded save predates this channel's existence/configuration.
	# Retract every later local claim. Publishing here would itself recreate the absent object and
	# turn a rollback into a state mutation, so absence remains genuinely absent.
	_restore_absent_state()


func _restore_absent_state() -> void:
	_restoring = true
	_cancel_callbacks()
	_cancel_owned_sweeps(&"channel_absent_restore")
	_running = false
	_flooding = false
	_cycle_epoch = -1.0
	_sweep_epoch = -1.0
	_next_onset_tick = -1.0
	_next_off_tick = -1.0
	_next_sweep_tick = -1.0
	_sweep_refractory.clear()
	_sweep_active.clear()
	_apply_water_visibility()
	_restoring = false


func _cancel_owned_sweeps(reason: StringName) -> void:
	if _sweep_gs == null or not _sweep_gs.has_method("is_external_traversal_active"):
		_sweep_active.clear()
		return
	var ids := _sweep_active.keys()
	for id_v in ids:
		var id := str(id_v)
		if not _sweep_gs.is_external_traversal_active(id):
			continue
		var traversal: Dictionary = _sweep_gs.get_external_traversal_state(id)
		if str(traversal.get("traversal_id", "")) == String(_sweep_traversal_id(id)):
			_sweep_gs.cancel_external_traversal(id, reason)
	_sweep_active.clear()


func _sweep_traversal_id(id: String) -> StringName:
	return StringName("channel_sweep/%s/%s" % [_tag, id])


func _connect_sweep_signals() -> void:
	if _sweep_signal_gs == _sweep_gs:
		return
	_disconnect_sweep_signals()
	_sweep_signal_gs = _sweep_gs
	if _sweep_signal_gs == null:
		return
	if _sweep_signal_gs.has_signal("external_traversal_finished") \
			and not _sweep_signal_gs.external_traversal_finished.is_connected(
				_on_external_traversal_finished):
		_sweep_signal_gs.external_traversal_finished.connect(_on_external_traversal_finished)
	if _sweep_signal_gs.has_signal("external_traversal_cancelled") \
			and not _sweep_signal_gs.external_traversal_cancelled.is_connected(
				_on_external_traversal_cancelled):
		_sweep_signal_gs.external_traversal_cancelled.connect(_on_external_traversal_cancelled)


func _disconnect_sweep_signals() -> void:
	if _sweep_signal_gs == null or not is_instance_valid(_sweep_signal_gs):
		_sweep_signal_gs = null
		return
	if _sweep_signal_gs.has_signal("external_traversal_finished") \
			and _sweep_signal_gs.external_traversal_finished.is_connected(
				_on_external_traversal_finished):
		_sweep_signal_gs.external_traversal_finished.disconnect(_on_external_traversal_finished)
	if _sweep_signal_gs.has_signal("external_traversal_cancelled") \
			and _sweep_signal_gs.external_traversal_cancelled.is_connected(
				_on_external_traversal_cancelled):
		_sweep_signal_gs.external_traversal_cancelled.disconnect(_on_external_traversal_cancelled)
	_sweep_signal_gs = null


func _schedule_onset_at(deadline: float) -> void:
	if _scheduler == null or not _running:
		return
	_scheduler.cancel_tag(_tag + "_onset")
	_next_onset_tick = maxf(_scheduler_tick(), deadline)
	_scheduler.schedule_after(
		maxf(0.0, _next_onset_tick - _scheduler_tick()), _onset, _tag + "_onset"
	)


func _schedule_off_at(deadline: float) -> void:
	if _scheduler == null or not _running:
		return
	_scheduler.cancel_tag(_tag + "_off")
	_next_off_tick = maxf(_scheduler_tick(), deadline)
	_scheduler.schedule_after(
		maxf(0.0, _next_off_tick - _scheduler_tick()), _off, _tag + "_off"
	)


func _schedule_sweep_at(deadline: float) -> void:
	if _scheduler == null or not _running or not _flooding or not _sweep_enabled:
		return
	_scheduler.cancel_tag(_tag + "_sweep")
	_next_sweep_tick = maxf(_scheduler_tick(), deadline)
	_scheduler.schedule_after(
		maxf(0.0, _next_sweep_tick - _scheduler_tick()), _sweep_poll, _tag + "_sweep"
	)


func _cancel_callback_tags() -> void:
	if _scheduler == null:
		return
	_scheduler.cancel_tag(_tag + "_onset")
	_scheduler.cancel_tag(_tag + "_off")
	_scheduler.cancel_tag(_tag + "_sweep")
	_scheduler.cancel_tag(_tag + "_telegraph")


func _cancel_callbacks() -> void:
	_cancel_callback_tags()


func _scheduler_tick() -> float:
	return float(_scheduler.get_current_tick()) if _scheduler != null else 0.0


func _remaining_until(deadline: float) -> float:
	return maxf(0.0, deadline - _scheduler_tick()) if deadline >= 0.0 else -1.0


func _saved_deadline(snapshot: Dictionary, absolute_key: String, remaining_key: String) -> float:
	var absolute := float(snapshot.get(absolute_key, -1.0))
	if absolute >= 0.0:
		return absolute
	var remaining := float(snapshot.get(remaining_key, -1.0))
	return _scheduler_tick() + remaining if remaining >= 0.0 else -1.0


## Sweep polls are a fixed analytic sequence inside one wet phase. Persisting its first absolute
## tick lets any later save derive the next poll without logging every empty half-second callback.
func _next_sweep_from_epoch() -> float:
	if _sweep_epoch < 0.0:
		return -1.0
	return FixedCadenceScript.next_strict_tick(
		_sweep_epoch, SWEEP_POLL_INTERVAL, _scheduler_tick())


func _portable_refractory() -> Dictionary:
	var out := {}
	var ids := _sweep_refractory.keys()
	ids.sort()
	for id_v in ids:
		out[str(id_v)] = float(_sweep_refractory[id_v])
	return out


func _validated_refractory(raw: Variant) -> Variant:
	if not raw is Dictionary:
		return null
	var out := {}
	for id_v in (raw as Dictionary).keys():
		var id := str(id_v)
		if id.is_empty():
			return null
		var deadline := float((raw as Dictionary)[id_v])
		if not is_finite(deadline):
			return null
		out[id] = deadline
	return out


func _portable_active_sweeps() -> Dictionary:
	var out := {}
	var ids := _sweep_active.keys()
	ids.sort()
	for id_v in ids:
		var id := str(id_v)
		var pending: Dictionary = _sweep_active[id_v]
		var portable := {
			"traversal_id": str(pending.get("traversal_id", "")),
			"phase": str(pending.get("phase", "")),
			"target_kind": str(pending.get("target_kind", "")),
			"started_tick": float(pending.get("started_tick", -1.0)),
			"impact_tick": float(pending.get("impact_tick", -1.0)),
			"data_origin": (pending.get("data_origin", []) as Array).duplicate(),
			"data_destination": (pending.get("data_destination", []) as Array).duplicate(),
			"render_origin": (pending.get("render_origin", []) as Array).duplicate(),
			"render_destination": (pending.get("render_destination", []) as Array).duplicate(),
			"party_hp": float(pending.get("party_hp", 0.0)),
			"enemy_damage": float(pending.get("enemy_damage", 0.0)),
			"enemy_stun": float(pending.get("enemy_stun", 0.0)),
			"refractory_tick": float(pending.get(
				"refractory_tick", _sweep_refractory.get(id, -1.0))),
		}
		for key in [
			"hp_before", "hp_after", "shield_before", "shield_after",
			"enemy_hp_before", "enemy_hp_after",
		]:
			if pending.has(key):
				portable[key] = float(pending[key])
		out[id] = portable
	return out


func _validated_active_sweeps(raw: Variant, contract: String) -> Variant:
	if not raw is Dictionary:
		return null
	var out := {}
	for id_v in (raw as Dictionary).keys():
		var id := str(id_v)
		var value: Variant = (raw as Dictionary)[id_v]
		if id.is_empty() or not value is Dictionary:
			return null
		var pending := value as Dictionary
		var traversal_id := str(pending.get("traversal_id", ""))
		var phase := str(pending.get(
			"phase", SWEEP_PHASE_CARRYING
				if contract == LEGACY_STATE_CONTRACT_V2 else ""))
		var target_kind := str(pending.get("target_kind", ""))
		var started_tick := float(pending.get("started_tick", -1.0))
		var impact_tick := float(pending.get("impact_tick", -1.0))
		var party_hp := float(pending.get("party_hp", -1.0))
		var enemy_damage := float(pending.get("enemy_damage", -1.0))
		var enemy_stun := float(pending.get("enemy_stun", -1.0))
		if traversal_id != String(_sweep_traversal_id(id)) \
				or phase not in [
					SWEEP_PHASE_RESERVED,
					SWEEP_PHASE_CARRYING,
					SWEEP_PHASE_IMPACT_PENDING,
					SWEEP_PHASE_PARTY_DAMAGE_COMMITTING,
					SWEEP_PHASE_PARTY_DOWNING_PENDING,
					SWEEP_PHASE_ENEMY_DAMAGE_COMMITTING,
					SWEEP_PHASE_ENEMY_STUN_COMMITTING,
				] \
				or target_kind not in ["party", "enemy"] \
				or not is_finite(started_tick) or not is_finite(impact_tick) \
				or impact_tick <= started_tick \
				or not is_finite(party_hp) or party_hp < 0.0 \
				or not is_finite(enemy_damage) or enemy_damage < 0.0 \
				or not is_finite(enemy_stun) or enemy_stun < 0.0:
			return null
		if target_kind == "party" and phase in [
				SWEEP_PHASE_ENEMY_DAMAGE_COMMITTING, SWEEP_PHASE_ENEMY_STUN_COMMITTING]:
			return null
		if target_kind == "enemy" and phase in [
				SWEEP_PHASE_PARTY_DAMAGE_COMMITTING, SWEEP_PHASE_PARTY_DOWNING_PENDING]:
			return null
		var normalized := {
			"traversal_id": traversal_id,
			"phase": phase,
			"target_kind": target_kind,
			"started_tick": started_tick,
			"impact_tick": impact_tick,
			"party_hp": party_hp,
			"enemy_damage": enemy_damage,
			"enemy_stun": enemy_stun,
		}
		if contract == STATE_CONTRACT:
			for key in ["data_origin", "data_destination", "render_origin", "render_destination"]:
				var vector_value: Variant = _validated_portable_v3(pending.get(key, null))
				if vector_value == null:
					return null
				normalized[key] = vector_value
			var refractory_tick := float(pending.get("refractory_tick", -1.0))
			if not is_finite(refractory_tick) or refractory_tick < started_tick:
				return null
			normalized["refractory_tick"] = refractory_tick
		if phase in [SWEEP_PHASE_PARTY_DAMAGE_COMMITTING, SWEEP_PHASE_PARTY_DOWNING_PENDING]:
			for key in ["hp_before", "hp_after", "shield_before", "shield_after"]:
				var number := float(pending.get(key, -1.0))
				if not is_finite(number) or number < 0.0:
					return null
				normalized[key] = number
		if phase in [SWEEP_PHASE_ENEMY_DAMAGE_COMMITTING, SWEEP_PHASE_ENEMY_STUN_COMMITTING]:
			for key in ["enemy_hp_before", "enemy_hp_after"]:
				var number := float(pending.get(key, -1.0))
				if not is_finite(number) or number < 0.0:
					return null
				normalized[key] = number
		out[id] = normalized
	return out


func _active_sweeps_match_game_state(active: Dictionary) -> bool:
	if _sweep_gs == null or not _sweep_gs.has_method("get_external_traversal_state"):
		return active.is_empty()
	for id_v in active.keys():
		var id := str(id_v)
		if not _sweep_gs.characters.has(id):
			return false
		var pending: Dictionary = active[id_v]
		var phase := str(pending.get("phase", ""))
		if _sweep_gs.is_external_traversal_active(id):
			var traversal: Dictionary = _sweep_gs.get_external_traversal_state(id)
			if str(traversal.get("traversal_id", "")) != str(pending.get(
					"traversal_id", "")):
				return false
			if phase not in [SWEEP_PHASE_RESERVED, SWEEP_PHASE_CARRYING]:
				return false
		elif phase == SWEEP_PHASE_CARRYING and not pending.has("data_destination"):
			# A v2 carry without a GameState traversal cannot prove whether it arrived or was
			# cancelled, so rejecting is safer than inventing either an impact or immunity.
			return false
	# The reverse check catches a torn snapshot where GameState carries a body for this channel but
	# its pending impact record was omitted. Silently accepting that state would grant free passage.
	for id_v in _sweep_gs.characters.keys():
		var id := str(id_v)
		if not _sweep_gs.is_external_traversal_active(id):
			continue
		var traversal: Dictionary = _sweep_gs.get_external_traversal_state(id)
		if str(traversal.get("traversal_id", "")) == String(_sweep_traversal_id(id)) \
				and not active.has(id):
			return false
	return true


func _hydrate_v2_sweep_transactions(active: Dictionary, refractory: Dictionary) -> void:
	# v2 already paired each entry with a GameState traversal but did not duplicate its geometry in
	# the Channel record because it had no pre-start reservation phase. Hydrate that geometry before
	# any later v3 publication, otherwise the first post-load cadence event would write an invalid
	# half-migrated transaction.
	for id_v in active.keys():
		var id := str(id_v)
		var pending: Dictionary = active[id_v]
		var traversal: Dictionary = _sweep_gs.get_external_traversal_state(id)
		for key in ["data_origin", "data_destination", "render_origin", "render_destination"]:
			var value: Variant = traversal.get(key, Vector3.ZERO)
			if value is Vector3:
				pending[key] = _v3_to_portable(value as Vector3)
		pending["refractory_tick"] = float(refractory.get(
			id, pending.get("started_tick", 0.0)))
		active[id] = pending


func _validated_portable_v3(raw: Variant) -> Variant:
	if not raw is Array or (raw as Array).size() != 3:
		return null
	var out: Array = []
	for value in raw as Array:
		var number := float(value)
		if not is_finite(number):
			return null
		out.append(number)
	return out


func _v3_to_portable(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _portable_to_v3(value: Variant) -> Vector3:
	var data := value as Array
	return Vector3(float(data[0]), float(data[1]), float(data[2]))


## A snapshot can legally land in any synchronous signal boundary:
## - reservation published, traversal not started yet;
## - GameState traversal started, reservation not promoted yet;
## - GameState arrival committed, Channel finish listener not entered yet;
## - damage/stun mutated downstream state, transaction not yet retired.
## Reconciliation inspects the paired GameState/body receipt and advances only the missing edge.
func _reconcile_sweep_transactions() -> void:
	if _restoring or _sweep_gs == null or _sweep_active.is_empty():
		return
	var ids := _sweep_active.keys()
	ids.sort()
	for id_v in ids:
		var id := str(id_v)
		if not _sweep_active.has(id):
			continue
		var pending: Dictionary = _sweep_active[id]
		var phase := str(pending.get("phase", ""))
		match phase:
			SWEEP_PHASE_RESERVED:
				if _has_matching_external_traversal(id, str(pending.get("traversal_id", ""))):
					pending["phase"] = SWEEP_PHASE_CARRYING
					_sweep_active[id] = pending
					_publish_authoritative_state()
				else:
					_resume_reserved_sweep(id, pending)
			SWEEP_PHASE_CARRYING:
				if not _has_matching_external_traversal(
						id, str(pending.get("traversal_id", ""))):
					_reconcile_finished_or_cancelled_carry(id, pending)
			SWEEP_PHASE_IMPACT_PENDING, \
			SWEEP_PHASE_PARTY_DAMAGE_COMMITTING, \
			SWEEP_PHASE_PARTY_DOWNING_PENDING, \
			SWEEP_PHASE_ENEMY_DAMAGE_COMMITTING, \
			SWEEP_PHASE_ENEMY_STUN_COMMITTING:
				_drive_sweep_impact(id)


func _resume_reserved_sweep(id: String, pending: Dictionary) -> void:
	if not pending.has("data_destination") or not _sweep_gs.characters.has(id):
		_sweep_active.erase(id)
		_publish_authoritative_state()
		return
	var destination := _portable_to_v3(pending.get("data_destination", []))
	var now := _scheduler_tick()
	var impact_tick := float(pending.get("impact_tick", now))
	if now >= impact_tick - MIN_CADENCE:
		if _sweep_gs.get_position(id).is_equal_approx(destination):
			pending["phase"] = SWEEP_PHASE_IMPACT_PENDING
			_sweep_active[id] = pending
			_publish_authoritative_state()
			_drive_sweep_impact(id)
		else:
			_sweep_active.erase(id)
			_publish_authoritative_state()
		return
	var render_origin: Vector3 = _sweep_gs.get_render_position(id) \
		if _sweep_gs.has_method("get_render_position") else _sweep_gs.get_position(id)
	var render_destination := _portable_to_v3(pending.get("render_destination", []))
	var traversal_id := StringName(str(pending.get("traversal_id", "")))
	var accepted := bool(_sweep_gs.command_external_traversal(
		id,
		traversal_id,
		destination,
		render_origin,
		render_destination,
		maxf(MIN_CADENCE, impact_tick - now),
		&"locked"))
	if accepted or _has_matching_external_traversal(id, String(traversal_id)):
		if _sweep_active.has(id):
			pending = _sweep_active[id]
			pending["phase"] = SWEEP_PHASE_CARRYING
			_sweep_active[id] = pending
			_publish_authoritative_state()
		return
	_sweep_active.erase(id)
	_publish_authoritative_state()


func _reconcile_finished_or_cancelled_carry(id: String, pending: Dictionary) -> void:
	if not pending.has("data_destination") or not _sweep_gs.characters.has(id):
		_sweep_active.erase(id)
		_publish_authoritative_state()
		return
	var destination := _portable_to_v3(pending.get("data_destination", []))
	var arrived: bool = _scheduler_tick() >= float(
		pending.get("impact_tick", INF)) - MIN_CADENCE \
		and _sweep_gs.get_position(id).is_equal_approx(destination)
	if not arrived:
		_sweep_active.erase(id)
		_publish_authoritative_state()
		return
	pending["phase"] = SWEEP_PHASE_IMPACT_PENDING
	_sweep_active[id] = pending
	_publish_authoritative_state()
	_drive_sweep_impact(id)


func _has_matching_external_traversal(id: String, traversal_id: String) -> bool:
	if _sweep_gs == null or not _sweep_gs.has_method("is_external_traversal_active") \
			or not _sweep_gs.is_external_traversal_active(id):
		return false
	var traversal: Dictionary = _sweep_gs.get_external_traversal_state(id)
	return str(traversal.get("traversal_id", "")) == traversal_id


func _apply_water_visibility() -> void:
	if is_instance_valid(_water):
		# A current already carrying a body remains visible through its trailing impact even if the
		# cadence's catch window closed first. It cannot catch anyone new once `_flooding` is false.
		_water.visible = _flooding or not _sweep_active.is_empty()


func _publish_authoritative_state() -> void:
	if _restoring or _game_state == null or not _game_state.has_method("set_world_state"):
		return
	_game_state.set_world_state(authority_state_key(), serialize_state())


func _exit_tree() -> void:
	# Teardown removes Callables only. The world record remains available to a reconstruction.
	_cancel_callbacks()
	_disconnect_sweep_signals()
