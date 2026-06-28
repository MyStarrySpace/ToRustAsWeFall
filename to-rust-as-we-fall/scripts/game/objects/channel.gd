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

func _off() -> void:
	_flooding = false
	if is_instance_valid(_water):
		_water.visible = false

func is_flooding() -> bool:
	return _flooding

## True if (x, z) is inside this channel AND it is flooding right now — i.e. a character there gets swept.
func floods_at(x: float, z: float) -> bool:
	return _flooding and absf(x - _x) <= _half and absf(z) <= _z_half

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
