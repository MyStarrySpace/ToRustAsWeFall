extends "res://scripts/scene_chunks/scene_chunk.gd"

## The DATA-DRIVEN fragment loader. Point it at a `Fragment` resource (the data) and it COMPOSES the scene from
## the shared modular classes — no bespoke build code per fragment. It reads the fragment's map (floors/walls/
## lights/labels), spawns each object in `fragment.objects` via the right class (Flure / PortalPad / Capbage /
## Channel / FloraLight / Enemy / marker), and exposes the fragment's title/help/spawns/grid through the normal
## SceneChunk interface, so a DATA fragment loads through the exact same preview/elevator/act1 path as a coded one.
##
## Assign the fragment two ways: set `fragment` directly (tests), or `configure_chunk({"fragment_path": "res://..."})`
## (the preview registry / a level builder). The per-type object contract is documented on each branch of
## _spawn_object below — that branch list IS the authoring reference for a Fragment `.tres`.

const EnemyScript := preload("res://scripts/game/ai/enemy.gd")

var fragment: Fragment
var fragment_path := ""

# Spawned, kept for queries + reset (the loader owns nothing bespoke — just references to the modular objects).
var _flures: Array = []
var _portals: Array = []
var _capbages: Array = []
var _channels: Array = []
var _flora: Array = []
var _enemies: Array = []
var _scheduled := false

func configure_chunk(config: Dictionary) -> void:
	if config.has("fragment"):
		fragment = config["fragment"]
	if config.has("fragment_path"):
		fragment_path = str(config["fragment_path"])

func _build_chunk() -> void:
	if fragment == null and fragment_path != "":
		fragment = load(fragment_path) as Fragment
	if fragment == null:
		push_warning("DataFragmentChunk: no fragment assigned (set `fragment` or fragment_path)")
		return
	_build_environment()
	for spec in fragment.objects:
		_spawn_object(spec)
	_set_preview_step((fragment.id if fragment.id != "" else "data_fragment") + "_start")

# --- Environment ---

func _build_environment() -> void:
	for f in fragment.floors:
		_add_floor(self, _v3(f, "pos"), _v3(f, "size", Vector3.ONE), _col(f, "color", Color(0.1, 0.1, 0.12)))
	for w in fragment.walls:
		_add_box(self, _v3(w, "pos"), _v3(w, "size", Vector3.ONE), _col(w, "color", Color(0.06, 0.06, 0.08)),
			_col(w, "emission", Color.BLACK), _f(w, "energy", 0.0))
	for l in fragment.lights:
		_add_light(self, _v3(l, "pos"), _col(l, "color", Color.WHITE), _f(l, "energy", 1.0), _f(l, "range", 4.0))
	for lb in fragment.labels:
		_add_label(self, str(lb.get("text", "")), _v3(lb, "pos"), _col(lb, "color", Color(0.82, 0.86, 0.92)))

# --- Object spawning: one branch per object `type`. This list is the .tres authoring contract. ---

func _spawn_object(spec: Dictionary) -> void:
	var gs = _get_game_state()
	match str(spec.get("type", "")):
		"flure":
			# {pos:Vector3, targets:Array[String], attract:float, radius:float, color:Color}
			var fl := Flure.new()
			fl.name = _name(spec, "Flure")
			fl.configure(gs, _v3(spec, "pos"), _str_arr(spec, "targets"),
				_f(spec, "attract", 32.0), _f(spec, "radius", 1.6), _col(spec, "color", Color(0.95, 0.78, 0.2)))
			add_child(fl)
			_register_interactable(fl)
			_flures.append(fl)
		"portal_pad":
			# {pos:Vector3, dest:Vector3, radius:float, color:Color}
			var p := PortalPad.new()
			p.name = _name(spec, "PortalPad")
			p.configure(gs, _v3(spec, "pos"), _v3(spec, "dest"), _f(spec, "radius", 1.2),
				_col(spec, "color", Color(0.55, 0.42, 0.98)))
			add_child(p)
			_register_interactable(p)
			_portals.append(p)
		"capbage":
			# {pos:Vector3, radius:float}
			var cap := Capbage.new()
			cap.name = _name(spec, "Capbage")
			cap.configure(gs, _v3(spec, "pos"), _f(spec, "radius", 1.4))
			add_child(cap)
			_register_interactable(cap)
			_capbages.append(cap)
		"channel":
			# {x:float, half:float, z_half:float, period:float, dur:float, phase:float, tag:String}
			var ch := Channel.new()
			ch.name = _name(spec, "Channel")
			ch.configure(_f(spec, "x", 0.0), _f(spec, "half", 1.25), _f(spec, "z_half", 5.0),
				_f(spec, "period", 3.0), _f(spec, "dur", 1.6), _f(spec, "phase", 0.0),
				str(spec.get("tag", "ch_%d" % _channels.size())))
			add_child(ch)
			_channels.append(ch)
		"flora_light":
			# {pos:Vector3, opts:Dictionary}
			var bloom := FloraLight.new()
			bloom.name = _name(spec, "FloraLight")
			bloom.position = _v3(spec, "pos")
			bloom.configure(spec.get("opts", {}) as Dictionary)
			add_child(bloom)
			_flora.append(bloom)
		"enemy":
			# {id:String, pos:Vector3, speed:float, detect:float, targets:Array[String], roam?:{radius:float}, patrol?:Array}
			_spawn_enemy(spec, gs)
		"marker":
			# {pos:Vector3, size:Vector3, color:Color, energy:float, label:String}
			var color := _col(spec, "color", Color(0.3, 0.7, 0.55))
			_add_box(self, _v3(spec, "pos") - Vector3(0, 0.18, 0), _v3(spec, "size", Vector3(1, 0.4, 1)),
				color * 0.4, color, _f(spec, "energy", 1.0))
			var lbl := str(spec.get("label", ""))
			if lbl != "":
				_add_label(self, lbl, _v3(spec, "pos") + Vector3(0, 1.4, 0), color)
		_:
			push_warning("DataFragmentChunk: unknown object type '%s'" % str(spec.get("type", "")))

func _spawn_enemy(spec: Dictionary, gs) -> void:
	if gs == null:
		return
	var enemy := EnemyScript.new()
	var eid := str(spec.get("id", "enemy_%d" % _enemies.size()))
	enemy.name = "Enemy_%s" % eid
	enemy.position = _v3(spec, "pos")
	enemy.move_speed = _f(spec, "speed", 2.4)
	enemy.detection_range = _f(spec, "detect", 4.0)
	enemy._detection_targets.assign(_str_arr(spec, "targets"))
	add_child(enemy)
	enemy.char_id = eid
	enemy.game_state = gs
	gs.register_character(eid, enemy.position, enemy.move_speed, {"detection_range": float(enemy.detection_range)})
	if enemy.has_method("activate"):
		enemy.activate()
	if spec.has("roam") and enemy.has_method("set_roam"):
		var roam: Dictionary = spec["roam"]
		enemy.set_roam(enemy.position, _f(roam, "radius", 4.0))
	elif spec.has("patrol") and enemy.has_method("set_patrol"):
		var pts: Array = []
		for p in (spec["patrol"] as Array):
			pts.append(p if p is Vector3 else _v3({"p": p}, "p"))
		enemy.set_patrol(pts)
	_enemies.append(enemy)

# --- Scheduler-driven cadence (channels) ---

func _process(delta: float) -> void:
	_update(delta)

func headless_process(delta: float) -> void:
	_update(delta)

func _update(_delta: float) -> void:
	_ensure_scheduled()

func _ensure_scheduled() -> void:
	if _scheduled or _channels.is_empty():
		return
	var sched = _get_scheduler()
	if sched == null:
		return
	_scheduled = true
	for ch in _channels:
		ch.start(sched)

# --- SceneChunk interface (driven by the fragment data) ---

func get_scene_title() -> String:
	return fragment.title if fragment != null and fragment.title != "" else "Data Fragment"

func get_scene_help() -> String:
	return fragment.help if fragment != null else ""

func get_default_character() -> String:
	if fragment != null and fragment.default_character != "":
		return fragment.default_character
	return "aster"

func get_spawn_positions() -> Dictionary:
	return (fragment.spawns as Dictionary).duplicate(true) if fragment != null else {}

func get_grid_data() -> Dictionary:
	return (fragment.grid as Dictionary).duplicate(true) if fragment != null and not fragment.grid.is_empty() else {}

func get_preview_time_state() -> Dictionary:
	return (fragment.time_state as Dictionary).duplicate(true) if fragment != null else {}

func get_preview_abilities() -> Array:
	return []

func reset_preview_state() -> void:
	for fl in _flures:
		if is_instance_valid(fl):
			fl.reset_flure()
	for ch in _channels:
		if is_instance_valid(ch):
			ch.reset()
	_scheduled = false
	_set_preview_step((fragment.id if fragment != null and fragment.id != "" else "data_fragment") + "_start")

# Accessors so a test / the host can reach the composed objects.
func flures() -> Array: return _flures
func portals() -> Array: return _portals
func capbages() -> Array: return _capbages
func channels() -> Array: return _channels
func flora() -> Array: return _flora
func enemies() -> Array: return _enemies

# --- Dictionary readers (tolerant defaults so a sparse .tres still loads) ---

func _v3(d: Dictionary, key: String, def := Vector3.ZERO) -> Vector3:
	var v = d.get(key, def)
	return v if v is Vector3 else def

func _col(d: Dictionary, key: String, def: Color) -> Color:
	var v = d.get(key, def)
	return v if v is Color else def

func _f(d: Dictionary, key: String, def: float) -> float:
	var v = d.get(key, def)
	return float(v) if (v is float or v is int) else def

func _str_arr(d: Dictionary, key: String) -> Array:
	var out: Array = []
	for s in (d.get(key, []) as Array):
		out.append(str(s))
	return out

func _name(spec: Dictionary, fallback: String) -> String:
	return str(spec.get("name", "%s_%d" % [fallback, _flures.size() + _portals.size() + _capbages.size() + _channels.size() + _flora.size()]))
