class_name Channel
extends Node3D

## A wash CHANNEL: a flood strip that surges on a scheduler cadence (a row of them phased so at least one is always
## flooding — you can't just walk across). Anything standing in it WHILE it floods is swept off; the fragment asks
## floods_at() and applies the effect (drown the hunters, wash the party back). Self-contained: owns its bed + water
## visual and its flood cadence (scheduler-driven, so replay + fast-forward safe — never a wall clock). A fragment
## composes a row of these; a level builder places + phases them.

const WaterShader := preload("res://resources/channels_water.gdshader")

var _flooding := false
var _scheduler
var _bed: MeshInstance3D
var _water: MeshInstance3D
var _x := 0.0
var _half := 1.25
var _z_half := 5.0
var _period := 3.0
var _dur := 1.6
var _phase := 0.0
var _tag := "channel"

## Configure BEFORE adding to the tree. `tag` scopes this channel's scheduler events (unique per channel).
func configure(x: float, half: float, z_half: float, period: float, dur: float, phase: float, tag: String) -> void:
	_x = x
	_half = half
	_z_half = z_half
	_period = period
	_dur = dur
	_phase = phase
	_tag = tag

## THE SWEEP (P-KIT): a flooding channel carries away whatever stands in it -- the wash is the
## visible mechanism, so the consequence lives HERE, never in a chunk script. While flooding, a
## scheduler poll sweeps each ground-level body in the strip: stop it, carry it to wherever the
## level's policy says "downstream" is (the dest Callable -- the only part a chunk supplies),
## charge the party a fail-forward hp bite, and tumble (stun) enemies. A per-body refractory
## prevents the sweep -> land -> re-enter -> re-sweep death spiral.
var _sweep_enabled := false
var _sweep_gs = null
var _sweep_party: Array = []
var _sweep_dest := Callable()
var _sweep_party_hp := 6.0
var _sweep_enemy_stun := 2.5
var _sweep_refractory_secs := 4.0
var _sweep_enemy_resolver := Callable()
var _sweep_on_swept := Callable()
var _sweep_refractory := {}

## dest: (id, pos) -> Vector3 landing point. opts: party_hp, enemy_stun, refractory,
## enemy_resolver (id -> Enemy node, for the tumble), on_bite-style on_swept (id) -> void.
func set_sweep(gs, party_ids: Array, dest: Callable, opts: Dictionary = {}) -> void:
	_sweep_gs = gs
	_sweep_party = party_ids
	_sweep_dest = dest
	_sweep_party_hp = float(opts.get("party_hp", 6.0))
	_sweep_enemy_stun = float(opts.get("enemy_stun", 2.5))
	_sweep_refractory_secs = float(opts.get("refractory", 4.0))
	_sweep_enemy_resolver = opts.get("enemy_resolver", Callable())
	_sweep_on_swept = opts.get("on_swept", Callable())
	_sweep_enabled = true

## Refractory is derived pacing state -- a restart/checkpoint clears it so the next wash is fresh.
func clear_sweep_refractory() -> void:
	_sweep_refractory.clear()

func _ready() -> void:
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
	_water.visible = false
	add_child(_water)

## Begin the flood cadence on the gameplay scheduler (so it pauses + fast-forwards with gameplay). Call once the
## scheduler exists; reset() cancels it.
func start(scheduler) -> void:
	_scheduler = scheduler
	if _scheduler == null:
		return
	_scheduler.schedule_after(_phase + 0.01, _onset, _tag + "_onset")

func _onset() -> void:
	_flooding = true
	if is_instance_valid(_water):
		_water.visible = true
	if _scheduler != null:
		_scheduler.schedule_after(_dur, _off, _tag + "_off")
		_scheduler.schedule_after(_period, _onset, _tag + "_onset")
	if _sweep_enabled and _scheduler != null:
		_scheduler.cancel_tag(_tag + "_sweep")
		_scheduler.schedule_after(0.05, _sweep_poll, _tag + "_sweep")

func _off() -> void:
	_flooding = false
	if is_instance_valid(_water):
		_water.visible = false

func is_flooding() -> bool:
	return _flooding

## True if (x, z) is inside this channel AND it is flooding right now — i.e. a character there gets swept.
func floods_at(x: float, z: float) -> bool:
	return _flooding and absf(x - _x) <= _half and absf(z) <= _z_half

func _sweep_poll() -> void:
	if not _flooding or not _sweep_enabled or _sweep_gs == null or _scheduler == null:
		return
	var now: float = float(_scheduler.get_current_tick())
	for id_v in _sweep_gs.characters.keys():
		var id := str(id_v)
		if now < float(_sweep_refractory.get(id, -100.0)):
			continue
		var p: Vector3 = _sweep_gs.get_position(id)
		if p.y > 1.5 or not floods_at(p.x, p.z):
			continue
		_sweep_refractory[id] = now + _sweep_refractory_secs
		_sweep_gs.command_stop(id)
		if _sweep_dest.is_valid():
			_sweep_gs.snap_character_to(id, _sweep_dest.call(id, p))
		if id in _sweep_party:
			_sweep_gs.adjust_stat(id, "hp", -_sweep_party_hp)
			if _sweep_on_swept.is_valid():
				_sweep_on_swept.call(id)
		elif _sweep_enemy_resolver.is_valid():
			var foe = _sweep_enemy_resolver.call(id)
			if foe != null and foe.has_method("stun"):
				foe.stun(_sweep_enemy_stun)
	_scheduler.schedule_after(0.5, _sweep_poll, _tag + "_sweep")

## Force a flood onset now (scripted beats / tests).
func flood_now() -> void:
	_onset()

func reset() -> void:
	_flooding = false
	if is_instance_valid(_water):
		_water.visible = false
	if _scheduler != null:
		_scheduler.cancel_tag(_tag + "_onset")
		_scheduler.cancel_tag(_tag + "_off")
		_scheduler.cancel_tag(_tag + "_sweep")
	_sweep_refractory.clear()
