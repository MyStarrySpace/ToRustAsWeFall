extends "res://scripts/scene_chunks/scene_chunk.gd"

const LatheBuilderScript := preload("res://scripts/generation/lathe_builder.gd")
const SdfMesherScript := preload("res://scripts/generation/sdf_mesher.gd")
const GRIME_SHADER := preload("res://resources/tile_grime.gdshader")

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
var _scarpets: Array = []
var _candid_zones: Array = []
var _exit_shelters: Array = []
var _enemy_posts := {}        # char_id -> spawn post (re_post targets on a wipe restart)
var _scheduled := false
var _phase := "ready"
var _spotted_count := 0
var _wipe_count := 0

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
	_apply_shelters()
	for spec in fragment.objects:
		_spawn_object(spec)
	# Loader-owned failure wiring: a full party wipe restarts the fragment when the data asks for it.
	var gs = _get_game_state()
	if gs != null and bool(fragment.params.get("restart_on_wipe", false)):
		if not gs.character_downed.is_connected(_on_fragment_character_downed):
			gs.character_downed.connect(_on_fragment_character_downed)
	_set_preview_step((fragment.id if fragment.id != "" else "data_fragment") + "_start")

# --- Environment ---

func _build_environment() -> void:
	# Ground slabs get the world-triplanar deck tile (1 tile/m) so the grid reads through the floor, like
	# the sim room and generated stretches. A floor may name its own tile ("tile": "rust_iron", ...);
	# default deck_metal.
	for f in fragment.floors:
		_add_floor(self, _v3(f, "pos"), _v3(f, "size", Vector3.ONE),
			_col(f, "color", Color(0.1, 0.1, 0.12)), str(f.get("tile", "deck_metal")))
	for w in fragment.walls:
		var wall_box := _add_box(self, _v3(w, "pos"), _v3(w, "size", Vector3.ONE), _col(w, "color", Color(0.06, 0.06, 0.08)),
			_col(w, "emission", Color.BLACK), _f(w, "energy", 0.0))
		# A wall box may name a pixel-art atlas tile ("tile": "wall_panel") — the same world-triplanar
		# 1-tile/m material the floors use, TINTED by the box colour so palette fields keep working.
		if str(w.get("tile", "")) != "":
			wall_box.material_override = _tinted_tile_material(str(w["tile"]), _col(w, "color", Color.WHITE))
	for l in fragment.lights:
		_add_light(self, _v3(l, "pos"), _col(l, "color", Color.WHITE), _f(l, "energy", 1.0), _f(l, "range", 4.0))
	for lb in fragment.labels:
		_add_label(self, str(lb.get("text", "")), _v3(lb, "pos"), _col(lb, "color", Color(0.82, 0.86, 0.92)))
	for m in fragment.meshes:
		_instance_mesh(m)
	# Revolve-tower plans (params-driven pure data from the building filler) loft here — the loader
	# owns scene nodes. Shell gets the tinted atlas material; window quads keep their emissive surface.
	for lp in fragment.params.get("lathe_buildings", []):
		_spawn_lathe_building(lp as Dictionary)
	# LANDMARK hero plans (params-driven, from the building filler): BaseShapeBuilder specs placed by
	# their gameplay anchors — the main door road-snapped to the street. Bridges between them are
	# already grid data + filler boxes; here we assemble the hero's own meshes.
	for lm in fragment.params.get("landmark_buildings", []):
		_spawn_landmark_building(lm as Dictionary)

var _weak_walls: Array = []

func _spawn_weak_wall(spec: Dictionary) -> void:
	var idx := _weak_walls.size()
	var foot := _v3(spec, "pos")
	var n := _v3(spec, "n").normalized()
	var up := Vector3.UP
	# the crack TELL on the wall face (present from first sight)
	var crack := MeshInstance3D.new()
	crack.name = "WeakWallCrack%d" % idx
	var cbm := BoxMesh.new()
	cbm.size = Vector3(0.55, 0.4, 0.1)
	crack.mesh = cbm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.3, 0.08, 0.06)
	cmat.emission_enabled = true
	cmat.emission = Color(0.85, 0.15, 0.1)
	cmat.emission_energy_multiplier = 0.9
	crack.material_override = cmat
	add_child(crack)
	crack.global_position = foot + up * 2.2 + n * 0.1
	if absf(n.dot(up)) < 0.99:
		crack.global_transform.basis = Basis(n.cross(up).normalized(), up, n)
	# the rubble (revealed on crumble), centred on the kill zone
	var kmin := _v3(spec, "kill_min")
	var kmax := _v3(spec, "kill_max")
	var kc := (kmin + kmax) * 0.5
	var rubble := Node3D.new()
	rubble.name = "WeakWallRubble%d" % idx
	add_child(rubble)
	rubble.global_position = Vector3(kc.x, 0.0, kc.z)
	for ri in range(4):
		var rb := MeshInstance3D.new()
		var rbm := BoxMesh.new()
		rbm.size = Vector3(0.8 - 0.1 * float(ri), 0.45, 0.7)
		rb.mesh = rbm
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.30, 0.30, 0.33)
		rb.material_override = rmat
		rubble.add_child(rb)
		rb.position = Vector3(-0.5 + 0.45 * float(ri), 0.2, -0.3 + 0.3 * float(ri % 2))
	rubble.visible = false
	# the PRY point at the wall foot
	var ia := _add_interactable(self, "WeakWall%d" % idx, "Pry the cracked wall", foot + n * 0.9,
		"PRY", "", 1.0, true, 1.5, Interactable.InteractableType.INSPECTION, false)
	var iam := _add_box(ia, Vector3(0, 0.8, 0), Vector3(0.2, 1.6, 0.2), Color(0.5, 0.42, 0.3), Color(0.9, 0.6, 0.2), 0.5)
	_outline_interactable_child(ia, iam, "WeakWall%d" % idx, 1.5)
	var entry := {"crumbled": false, "kill_min": kmin, "kill_max": kmax, "crack": crack, "rubble": rubble}
	_weak_walls.append(entry)
	ia.interacted.connect(func() -> void: _on_weak_wall_pried(idx))

func _on_weak_wall_pried(idx: int) -> void:
	var sched = _get_scheduler()
	if sched == null or idx >= _weak_walls.size() or bool((_weak_walls[idx] as Dictionary)["crumbled"]):
		return
	sched.schedule_after(0.9, func() -> void: _commit_weak_wall(idx), "weak_wall_%d" % idx)

func _commit_weak_wall(idx: int) -> void:
	var entry := _weak_walls[idx] as Dictionary
	if bool(entry["crumbled"]):
		return
	entry["crumbled"] = true
	var gs = _get_game_state()
	var kmin := entry["kill_min"] as Vector3
	var kmax := entry["kill_max"] as Vector3
	# the debris field resolves at the commit tick (analytic, never per-frame sampled)
	for en in _enemies.duplicate():
		if en == null or not is_instance_valid(en) or not en.is_alive():
			continue
		var ep: Vector3 = gs.get_position(en.char_id) if gs != null else Vector3.ZERO
		if ep.x > kmin.x and ep.x < kmax.x and ep.z > kmin.z and ep.z < kmax.z:
			if gs != null:
				gs.command_stop(en.char_id)
			en.take_damage(float(en.max_hp))
	var crack := entry["crack"] as Node3D
	if crack != null and is_instance_valid(crack):
		crack.visible = false
	var rubble := entry["rubble"] as Node3D
	if rubble != null and is_instance_valid(rubble):
		rubble.visible = true

func _spawn_landmark_building(lm: Dictionary) -> void:
	var kind := str(lm.get("kind", ""))
	if not BaseShapeBuilder.SPECS.has(kind):
		return
	var spec: Dictionary = BaseShapeBuilder.generate(kind)
	var ent: Dictionary = LatticeBuilder.entrances(spec)
	var root := Node3D.new()
	root.name = "Landmark_%s" % kind
	add_child(root)
	root.position = _v3(lm, "pos")
	root.rotation = Vector3(0.0, float(lm.get("yaw", 0.0)), 0.0)
	var body := BaseShapeBuilder.base_mesh(spec, ent.get("reserved", []))
	if body != null:
		body.surface_set_material(0, _tinted_tile_material(str(spec.get("tile", "facility_metal")),
			spec.get("color", Color(0.4, 0.4, 0.42))))
		var bi := MeshInstance3D.new()
		bi.name = "Body"
		bi.mesh = body
		root.add_child(bi)
	# entrance meshes (stone surround + dark/teal leaves)
	var mats := {"stone": _tinted_tile_material("facility_metal", Color(0.66, 0.62, 0.50))}
	var darkm := StandardMaterial3D.new()
	darkm.albedo_color = Color(0.05, 0.05, 0.06)
	var tealm := StandardMaterial3D.new()
	tealm.albedo_color = Color(0.10, 0.28, 0.30)
	tealm.emission_enabled = true
	tealm.emission = Color(0.22, 0.82, 0.86)
	mats["dark"] = darkm
	mats["accent"] = tealm
	for mk in ["stone", "dark", "accent"]:
		var em: Variant = ent.get(mk)
		if em != null and (em as ArrayMesh).get_surface_count() > 0:
			var ei := MeshInstance3D.new()
			ei.name = "Ent%s" % mk.capitalize()
			ei.mesh = em
			ei.material_override = mats[mk]
			root.add_child(ei)
	# the district glass: emissive per-pane vertex colour on a plain material (no shader dependency)
	var glassm := StandardMaterial3D.new()
	glassm.vertex_color_use_as_albedo = true
	glassm.emission_enabled = true
	glassm.emission = Color(1.0, 0.75, 0.4)
	glassm.emission_energy_multiplier = 0.8
	match str(spec.get("lattice", "")):
		"voronoi":
			var vor: Dictionary = LatticeBuilder.voronoi(spec.get("size", Vector3(4.2, 5.2, 3.6)), {"reserved": ent.get("reserved", [])})
			var vm := MeshInstance3D.new()
			vm.name = "VoronoiMembrane"
			vm.mesh = vor["frame"]
			vm.material_override = _tinted_tile_material("facility_metal", Color(0.72, 0.70, 0.66))
			vm.visibility_range_end = float(vor.get("lod_switch", 30.0))
			vm.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			root.add_child(vm)
			for fd in (vor["faces"] as Array):
				var f := fd as Dictionary
				var quad := MeshInstance3D.new()
				quad.name = "VoronoiFar"
				var qm := QuadMesh.new()
				qm.size = Vector2(float(f["w"]), float(f["h"]))
				quad.mesh = qm
				var fm := StandardMaterial3D.new()
				fm.albedo_texture = f["tex"]
				fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				fm.alpha_scissor_threshold = 0.4
				quad.material_override = fm
				var n3 := f["n"] as Vector3
				quad.transform = Transform3D(Basis(f["u"] as Vector3, Vector3.UP, n3), (f["c"] as Vector3) + n3 * 0.06)
				quad.visibility_range_begin = float(vor.get("lod_switch", 30.0))
				quad.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				root.add_child(quad)
		"honeyframe":
			var ov := {"reserved": ent.get("reserved", [])}
			var built: Dictionary = LatticeBuilder.honeyframe_tiered(spec, ov) if int(spec.get("tiers", 1)) > 1 \
				else LatticeBuilder.honeyframe(spec.get("size", Vector3(4.5, 8.0, 5.5)), ov)
			for pair in [["frame", null], ["glass", glassm]]:
				var mm: Variant = built.get(str((pair as Array)[0]))
				if mm == null or (mm as ArrayMesh).get_surface_count() == 0:
					continue
				var mi2 := MeshInstance3D.new()
				mi2.name = "Honey%s" % str((pair as Array)[0]).capitalize()
				mi2.mesh = mm
				mi2.material_override = (pair as Array)[1] if (pair as Array)[1] != null else _tinted_tile_material("facility_metal", Color(0.72, 0.69, 0.58))
				root.add_child(mi2)

func _spawn_lathe_building(lp: Dictionary) -> void:
	var profile: Dictionary = LatheBuilderScript.make_profile(lp)
	var built: Dictionary = LatheBuilderScript.build(profile)
	if built["mesh"] == null:
		return
	var mesh := built["mesh"] as ArrayMesh
	mesh.surface_set_material(0, _tinted_tile_material(str(lp.get("tile", "facility_metal")),
		_col(lp, "color", Color(0.4, 0.4, 0.42))))
	var mi := MeshInstance3D.new()
	mi.name = "LatheTower"
	mi.mesh = mesh
	add_child(mi)
	if bool(lp.get("coil", false)):
		var coil: Dictionary = SdfMesherScript.build(LatheBuilderScript.coil_prims(lp), 0.2)
		if coil["mesh"] != null:
			var ci := MeshInstance3D.new()
			ci.name = "LatheCoil"
			ci.mesh = coil["mesh"]
			ci.material_override = _tinted_tile_material("rust_iron",
				_col(lp, "color", Color(0.35, 0.25, 0.18)).lightened(0.12))
			add_child(ci)

# tile+tint -> material, cached: a district can carry hundreds of textured boxes but only a handful
# of (tile, palette-drift) combinations after quantising the tint.
var _tile_mat_cache: Dictionary = {}

## Pixel-art tile with PERLIN-VARIED DENSITY (tile_grime.gdshader) — the building/hero material.
## The tile is object-space locked (no swim), grime/rust/brightness ride a WORLD-space noise field so
## the tiling stops reading uniform and varies per facade + per building. Tint is LIFTED (the tile
## albedo is mid-dark) and quantised for cache hits while the Perlin palette drift stays visible.
func _tinted_tile_material(tile_name: String, tint: Color) -> ShaderMaterial:
	var lifted := Color(minf(tint.r * 2.6, 1.2), minf(tint.g * 2.6, 1.2), minf(tint.b * 2.6, 1.2))
	var key := "%s:%d,%d,%d" % [tile_name, int(lifted.r * 24.0), int(lifted.g * 24.0), int(lifted.b * 24.0)]
	if _tile_mat_cache.has(key):
		return _tile_mat_cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = GRIME_SHADER
	var tex = load(TILE_DIR + tile_name + ".png")
	if tex != null:
		mat.set_shader_parameter("tile_tex", tex)
	mat.set_shader_parameter("tint", lifted)
	# a rusty tile already carries decay — soften the shader's extra rust so it doesn't double up
	if tile_name == "rust_iron":
		mat.set_shader_parameter("rust_amount", 0.3)
		mat.set_shader_parameter("grime_amount", 0.55)
	_tile_mat_cache[key] = mat
	return mat

## Instance a placed model (a static modeled prop). The level MESH (the whole environment) goes through
## get_environment_model() instead — the host loads + warps that.
func _instance_mesh(spec: Dictionary) -> void:
	var path := str(spec.get("path", ""))
	if path == "":
		return
	var packed := load(path)
	if packed == null or not (packed is PackedScene):
		push_warning("DataFragmentChunk: mesh '%s' is not a loadable PackedScene" % path)
		return
	var node := (packed as PackedScene).instantiate()
	if node is Node3D:
		var n3 := node as Node3D
		var r := _v3(spec, "rot")
		n3.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))), _v3(spec, "pos"))
		var sc := _v3(spec, "scale", Vector3.ONE)
		if sc != Vector3.ONE:
			n3.scale = sc
	add_child(node)

## Declared shelter rects -> GameState shelter regions (sanctuary from detection/strikes + the revive
## watch's ground). Data, not behavior: the fragment says WHERE is safe; the engine enforces it.
func _apply_shelters() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for sh in fragment.shelters:
		var mn: Vector2 = sh.get("min", Vector2.ZERO)
		var mx: Vector2 = sh.get("max", Vector2.ZERO)
		gs.add_shelter_region(mn, mx)

# --- Object spawning: one branch per object `type`. This list is the .tres authoring contract. ---

func _spawn_object(spec: Dictionary) -> void:
	var gs = _get_game_state()
	match str(spec.get("type", "")):
		"weak_wall":
			# {pos:Vector3 (wall foot), n:Vector3 (outward), kill_min:Vector3, kill_max:Vector3}
			# A structural WEAK POINT consumed from a landmark's gameplay anchors: pry the strut and
			# the facade crumbles on a scheduled beat — enemies inside the kill zone die, rubble
			# remains. The generated-district cousin of the set-piece showcase's bay D.
			_spawn_weak_wall(spec)
		"flure":
			# {pos:Vector3, targets:Array[String], attract:float, radius:float, color:Color}
			var fl := Flure.new()
			fl.name = _name(spec, "Flure")
			fl.configure(gs, _v3(spec, "pos"), _str_arr(spec, "targets"),
				_f(spec, "attract", 32.0), _f(spec, "radius", 1.6), _col(spec, "color", Color(0.95, 0.78, 0.2)))
			if spec.has("settle"):
				fl.settle_pos = _v3(spec, "settle")
			fl.lure_duration = _f(spec, "duration", fl.lure_duration)
			if _f(spec, "dwell", 0.0) > 0.0:
				fl.interactable_type = Interactable.InteractableType.TIMED_ACTION
				fl.dwell_time = _f(spec, "dwell", 2.0)
			if spec.has("one_shot"):
				fl.one_shot = bool(spec["one_shot"])
			fl.set_enemy_resolver(_enemy_by_id)
			add_child(fl)
			_register_interactable(fl)
			_flures.append(fl)
		"portal_pad":
			# {pos:Vector3, dest:Vector3, radius:float, color:Color}
			var p := PortalPad.new()
			p.name = _name(spec, "PortalPad")
			p.configure(gs, _v3(spec, "pos"), _v3(spec, "dest"), _f(spec, "radius", 1.2),
				_col(spec, "color", Color(0.55, 0.42, 0.98)))
			p.set_group_provider(_selected_party_ids)
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
		"candid_zone":
			# {pos:Vector3, half:Vector2, dot:float} — biofilm ground: scan-blind (CONCEAL_FULL) + hp
			# drain while standing in it. The risk-inversion floor (ECOLOGY_COMBOS Card 2).
			var cz := CandidZone.new()
			cz.name = _name(spec, "CandidZone")
			var half = spec.get("half", Vector2(3.0, 3.0))
			cz.configure(_v3(spec, "pos"), half if half is Vector2 else Vector2(3.0, 3.0), _f(spec, "dot", 4.0))
			add_child(cz)
			_candid_zones.append(cz)
		"scarpet":
			# {pos:Vector3, radius:float} — a MEDIUM-tier hide mat (the loader's concealment pass reads it)
			var mat := Scarpet.new()
			mat.name = _name(spec, "Scarpet")
			mat.configure(_v3(spec, "pos"), _f(spec, "radius", 1.65))
			add_child(mat)
			_scarpets.append(mat)
		"exit_shelter":
			# {pos:Vector3, radius:float, label:String, color:Color} — the fragment's win pad: rest -> complete
			_spawn_exit_shelter(spec)
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
	_enemy_posts[eid] = enemy.position
	if enemy.has_signal("target_spotted"):
		enemy.target_spotted.connect(_on_fragment_target_spotted)
	if spec.has("roam") and enemy.has_method("set_roam"):
		var roam: Dictionary = spec["roam"]
		enemy.set_roam(enemy.position, _f(roam, "radius", 4.0))
	elif spec.has("patrol") and enemy.has_method("set_patrol"):
		var pts: Array[Vector3] = []
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
	_update_shared_concealment()

## The LOADER owns the hide-tier pass: Capbage = FULL beats Scarpet = MEDIUM beats exposed, from each
## member's REAL position every frame. Chunks never re-implement hide logic.
func _update_shared_concealment() -> void:
	if fragment == null or (_capbages.is_empty() and _scarpets.is_empty() and _candid_zones.is_empty()):
		return
	var gs = _get_game_state()
	if gs == null:
		return
	for cid_v in fragment.party_ids:
		var cid := str(cid_v)
		if not gs.characters.has(cid):
			continue
		var pos: Vector3 = gs.get_position(cid)
		var tier: int = GameState.CONCEAL_NONE
		for cap in _capbages:
			if is_instance_valid(cap) and cap.conceals(pos):
				tier = GameState.CONCEAL_FULL
				break
		if tier == GameState.CONCEAL_NONE:
			for cz in _candid_zones:
				if is_instance_valid(cz) and cz.covers(pos):
					tier = GameState.CONCEAL_FULL
					break
		if tier == GameState.CONCEAL_NONE:
			for mat in _scarpets:
				if is_instance_valid(mat) and mat.conceals(pos):
					tier = GameState.CONCEAL_MEDIUM
					break
		gs.set_character_concealment(cid, tier)

## The fragment's win pad: a click-gated INSPECTION interactable; resting there completes the fragment.
func _spawn_exit_shelter(spec: Dictionary) -> void:
	var p := _v3(spec, "pos")
	var color := _col(spec, "color", Color(0.3, 0.7, 0.45))
	var pad_w: float = _f(spec, "radius", 1.2) * 2.0
	var pad := _add_box(self, p + Vector3(0, 0.1, 0), Vector3(pad_w, 0.2, pad_w), Color(0.2, 0.28, 0.22), color, 0.5, _name(spec, "ExitShelterPad") + "Pad")
	var label := str(spec.get("label", "SHELTER"))
	if label != "":
		_add_label(self, label, p + Vector3(0, 2.0, 0), Color(0.6, 0.9, 0.65))
	var it := _add_object_interactable(self, _name(spec, "ExitShelter"), "Shelter", p + Vector3(0, 0.1, 0),
		"Rest", [pad], "", 0.0, true, _f(spec, "radius", 1.2), Interactable.InteractableType.INSPECTION)
	it.interacted.connect(_on_exit_shelter_rested.bind(it))
	_exit_shelters.append(it)

func _on_exit_shelter_rested(it: Node = null) -> void:
	if _phase == "complete":
		return
	# A downed activator cannot rest the party home (the controller never dispatches one in real
	# play; this guards the data-layer path to the same truth).
	var gs = _get_game_state()
	if it != null and gs != null and gs.is_downed(str(it.get("active_character"))):
		return
	_phase = "complete"
	_show_note("Safe ground. Rest.", 2.5)
	_set_preview_step((fragment.id if fragment != null and fragment.id != "" else "data_fragment") + "_complete")

func _on_fragment_target_spotted(target_id: String) -> void:
	if fragment == null or _phase == "complete" or not (target_id in Array(fragment.party_ids)):
		return
	_spotted_count += 1
	_show_note("Spotted. It's coming.", 2.0)

## A member beaten to 0 hp stays where they fell (the engine owns the down). The loader's only job:
## notice a FULL wipe and restart the fragment from the entry when the data asked for that.
func _on_fragment_character_downed(cid: String) -> void:
	if fragment == null or _phase == "complete" or not (cid in Array(fragment.party_ids)):
		return
	_show_note("%s is down. They stay where they fell." % cid.capitalize(), 2.4)
	var gs = _get_game_state()
	if gs == null or not gs.is_party_downed(Array(fragment.party_ids)):
		return
	_wipe_count += 1
	_show_note("It takes everyone. From the top.", 2.6)
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(_restart_tag())
		sched.schedule_after(1.5, _restart_fragment, _restart_tag())

func _restart_tag() -> String:
	return "frag_restart_" + (fragment.id if fragment != null and fragment.id != "" else "data_fragment")

## Full wipe -> restart from the entry: every member restored at their spawn (logged restore + snap,
## so the restart replays), every enemy re-posted, the flure re-armed.
func _restart_fragment() -> void:
	var gs = _get_game_state()
	if gs == null or fragment == null:
		return
	for cid_v in fragment.party_ids:
		var cid := str(cid_v)
		if not gs.characters.has(cid):
			continue
		gs.restore_character(cid)
		if fragment.spawns.has(cid):
			gs.snap_character_to(cid, fragment.spawns[cid])
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.has_method("re_post") and _enemy_posts.has(enemy.char_id):
			enemy.re_post(_enemy_posts[enemy.char_id])
	for fl in _flures:
		if is_instance_valid(fl):
			fl.reset_flure()
	_apply_downed_at_start()
	_phase = "ready"
	_set_preview_step((fragment.id if fragment.id != "" else "data_fragment") + "_restart")

## The host's live selection (the portal group provider — a click moves whoever is selected).
func _selected_party_ids() -> Array:
	if host != null and host.has_method("get_preview_selected_characters"):
		return host.call("get_preview_selected_characters")
	return []

func _enemy_by_id(cid: String):
	for enemy in _enemies:
		if is_instance_valid(enemy) and str(enemy.char_id) == cid:
			return enemy
	return null

## Freed while the scheduler lives (preview reloads): retract every tag this loader owns.
func _exit_tree() -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag(_restart_tag())
	sched.cancel_tag(_candid_tag())
	for fl in _flures:
		if is_instance_valid(fl):
			sched.cancel_tag("flure_reset_" + str(fl.name))

const CANDID_TICK := 0.5

func _candid_tag() -> String:
	return "candid_dot_" + (fragment.id if fragment != null and fragment.id != "" else "data_fragment")

func _arm_candid_tick() -> void:
	var sched = _get_scheduler()
	if sched == null or _candid_zones.is_empty():
		return
	sched.cancel_tag(_candid_tag())
	sched.schedule_after(CANDID_TICK, _on_candid_tick, _candid_tag())

func _on_candid_tick() -> void:
	var gs = _get_game_state()
	if gs != null and fragment != null:
		for cid_v in fragment.party_ids:
			var cid := str(cid_v)
			if not gs.characters.has(cid):
				continue
			var pos: Vector3 = gs.get_position(cid)
			for cz in _candid_zones:
				if is_instance_valid(cz) and cz.covers(pos):
					gs.adjust_stat(cid, "hp", -cz.dot_per_sec * CANDID_TICK)
					break
	_arm_candid_tick()

func _ensure_scheduled() -> void:
	if _scheduled:
		return
	if _channels.is_empty() and _candid_zones.is_empty():
		return
	var sched = _get_scheduler()
	if sched == null:
		return
	_scheduled = true
	for ch in _channels:
		ch.start(sched)
	_arm_candid_tick()

# --- SceneChunk interface (driven by the fragment data) ---

func get_scene_title() -> String:
	return fragment.title if fragment != null and fragment.title != "" else "Data Fragment"

func get_scene_help() -> String:
	return fragment.help if fragment != null else ""

func get_default_character() -> String:
	if fragment != null and fragment.default_character != "":
		return fragment.default_character
	return "aster"

## The level mesh (a modeled environment). The preview host loads + warps it; empty = procedural-only.
func get_environment_model() -> String:
	return fragment.environment_model if fragment != null else ""

func get_spawn_positions() -> Dictionary:
	return (fragment.spawns as Dictionary).duplicate(true) if fragment != null else {}

func get_grid_data() -> Dictionary:
	return (fragment.grid as Dictionary).duplicate(true) if fragment != null and not fragment.grid.is_empty() else {}

## Whether the FIELD regenerates stamina here (false = only shelter ground does; the closed
## economy the stamina-tension fragments are priced in).
func preview_field_stamina_regen() -> bool:
	return bool(fragment.params.get("stamina_field_regen", true)) if fragment != null else true

func get_preview_time_state() -> Dictionary:
	return (fragment.time_state as Dictionary).duplicate(true) if fragment != null else {}

## Anchors = the spawns + whatever the data's params.anchors names (posts, doors, hides, exits).
func get_preview_anchors() -> Dictionary:
	var anchors: Dictionary = {}
	if fragment != null:
		for k in fragment.spawns.keys():
			anchors[str(k)] = fragment.spawns[k]
		var pa: Dictionary = fragment.params.get("anchors", {})
		for k in pa.keys():
			anchors[str(k)] = pa[k]
	return anchors

func get_preview_state() -> Dictionary:
	var downed: Array = []
	var gs = _get_game_state()
	if gs != null and fragment != null:
		for cid_v in fragment.party_ids:
			if gs.is_downed(str(cid_v)):
				downed.append(str(cid_v))
	var lure_active := false
	for fl in _flures:
		if is_instance_valid(fl) and fl.is_active():
			lure_active = true
	return {
		"phase": _phase,
		"complete": _phase == "complete",
		"downed": downed,
		"spotted_count": _spotted_count,
		"wipe_count": _wipe_count,
		"lure_active": lure_active,
	}

func get_preview_abilities() -> Array:
	return []

## A fragment can open with members ALREADY DOWN where they spawned (params.downed_at_start:
## ["aster", ...]) — the retrieve scenarios' opening state. Applied on every reset/restart so the
## story state survives host resets; the DownedBodyManager grows the carry zone off the signal.
func _apply_downed_at_start() -> void:
	var gs = _get_game_state()
	if gs == null or fragment == null:
		return
	for cid_v in (fragment.params.get("downed_at_start", []) as Array):
		var cid := str(cid_v)
		if not gs.characters.has(cid):
			continue
		# The authored opening state, FULLY: back to where the story left them, then down. A reset
		# that re-downed them wherever they happened to lie would drift the scenario.
		if fragment.spawns.has(cid):
			gs.snap_character_to(cid, fragment.spawns[cid])
		if not gs.is_downed(cid):
			gs.down_character(cid)

func reset_preview_state() -> void:
	_apply_downed_at_start()
	for fl in _flures:
		if is_instance_valid(fl):
			fl.reset_flure()
	for ch in _channels:
		if is_instance_valid(ch):
			ch.reset()
	_phase = "ready"
	_spotted_count = 0
	_wipe_count = 0
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.has_method("re_post") and _enemy_posts.has(enemy.char_id):
			enemy.re_post(_enemy_posts[enemy.char_id])
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
