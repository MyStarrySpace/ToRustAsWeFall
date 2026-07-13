class_name Naturalizer
extends Enemy

## NATURALIZER (fauna_roster L34): institutional enforcement — fixed-route scan patrol, a lethal
## contact strike on whatever its scan flags, the granule-pack tell before it fires. Chase canon
## (chase_scene_framework.md): PROTOCOL HESITATION around iron-feeding fauna — inside a registered
## hesitation zone (a Chelator cluster's apron) it moves at a crawl, which is the chase's
## signature environmental lever. Zones are checked on a scheduler cadence (never per-frame), and
## the slow is a real logged speed change — replay and fast-forward safe like every other move.

const HESITATION_FACTOR := 0.45
const HESITATION_POLL := 0.4

var _hesitation_zones: Array = []   # [{pos: Vector3, radius: float}]
var _hesitating := false
var _nat_base_speed := 0.0
var _scan_ring: MeshInstance3D

func _ready() -> void:
	# the clean enforcement white is the BASE color (state repaints return to it)
	color = Color(0.92, 0.94, 0.96)
	super._ready()
	_nat_base_speed = move_speed

func add_hesitation_zone(pos: Vector3, radius: float) -> void:
	_hesitation_zones.append({"pos": pos, "radius": radius})
	_arm_hesitation_poll()

func activate() -> void:
	super.activate()
	_arm_hesitation_poll()

func _hes_tag() -> String:
	return "nat_hes_%s" % char_id

func _arm_hesitation_poll() -> void:
	var sched = _get_scheduler()
	if sched == null or _hesitation_zones.is_empty():
		return
	sched.cancel_tag(_hes_tag())
	sched.schedule_after(HESITATION_POLL, _hesitation_poll, _hes_tag())

func _hesitation_poll() -> void:
	if game_state != null and game_state.characters.has(char_id) and is_alive():
		var p: Vector3 = game_state.get_position(char_id)
		var inside := false
		for z_v in _hesitation_zones:
			var z := z_v as Dictionary
			var zp: Vector3 = z["pos"]
			if Vector2(p.x - zp.x, p.z - zp.z).length() <= float(z["radius"]):
				inside = true
				break
		if inside != _hesitating:
			_hesitating = inside
			game_state.change_move_speed(char_id,
				_nat_base_speed * HESITATION_FACTOR if inside else _nat_base_speed)
	var sched = _get_scheduler()
	if sched != null:
		sched.schedule_after(HESITATION_POLL, _hesitation_poll, _hes_tag())

func is_hesitating() -> bool:
	return _hesitating

## Clean white enforcement body + the rotating scanner ring (TASKS 20.6's read), cool blue lamps.
func _build_visual() -> void:
	super._build_visual()
	if _mesh != null and _mesh.material_override is StandardMaterial3D:
		var m := _mesh.material_override as StandardMaterial3D
		m.albedo_color = Color(0.92, 0.94, 0.96)
	_scan_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	_scan_ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.55, 0.75, 1.0)
	rm.emission_enabled = true
	rm.emission = Color(0.55, 0.78, 1.0)
	rm.emission_energy_multiplier = 1.6
	_scan_ring.material_override = rm
	_scan_ring.position = Vector3(0, 1.1, 0)
	add_child(_scan_ring)

func _process(delta: float) -> void:
	super._process(delta)
	# @rendering_only — the scanner line sweep, pure cosmetics
	if _scan_ring != null and is_instance_valid(_scan_ring):
		_scan_ring.rotate_y(delta * 2.4)
