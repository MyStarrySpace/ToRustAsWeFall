extends SceneTree

## Visual-honesty contract for Mother Flure's three fixed mechanisms. Gameplay phase/timing
## authority is covered by verify_mother_flure_save_authority.gd; this guard makes sure those
## phases are presented by truthful portable objects rather than boxes and spheres.

const HostScript := preload("res://tools/mother_flure_authority_host.gd")
const MotherScript := preload("res://scripts/fragments/chunks/mother_flure_chunk.gd")
const FIXTURE_ID := "mother_flure_visual_asset_fixture"
const GEAR_IDENTITY := "mother_gear_v1"
const ASSETS := [
	{
		"label": "portal frame",
		"stem": "res://resources/models/mother-flure/portal_frame/portal_frame",
		"scene": "res://scenes/props/mother_flure/portal_frame.tscn",
		"identity": "mother_portal_frame_v1",
		"min_size": Vector3(1.6, 2.2, 0.2),
	},
	{
		"label": "Mother Gear",
		"stem": "res://resources/models/mother-flure/mother_gear/mother_gear",
		"scene": "res://scenes/props/mother_flure/mother_gear.tscn",
		"identity": GEAR_IDENTITY,
		"min_size": Vector3(1.7, 0.2, 1.3),
	},
	{
		"label": "Rings membrane",
		"stem": "res://resources/models/mother-flure/rings_membrane/rings_membrane",
		"scene": "res://scenes/props/mother_flure/rings_membrane.tscn",
		"identity": "mother_rings_membrane_v1",
		"min_size": Vector3(2.5, 2.0, 0.2),
	},
]

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for spec_v in ASSETS:
		_verify_portable_asset(spec_v as Dictionary)
	_verify_repeatable_source()
	var pair := await _boot()
	_verify_runtime_portals(pair.chunk)
	_verify_shared_gear_identity(pair.host, pair.chunk)
	_verify_lifting_membrane(pair.chunk)
	await _discard(pair.host)
	print("MOTHER FLURE VISUAL ASSETS: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_portable_asset(spec: Dictionary) -> void:
	var label := str(spec["label"])
	var stem := str(spec["stem"])
	for extension in [".obj", ".mtl", ".png"]:
		_check(FileAccess.file_exists(stem + extension),
			"%s ships its external %s" % [label, extension.trim_prefix(".").to_upper()])
	var obj_text := FileAccess.get_file_as_string(stem + ".obj")
	_check(obj_text.contains("mtllib %s.mtl" % stem.get_file())
		and (obj_text.contains("\nvt ") or obj_text.begins_with("vt ")),
		"%s OBJ binds its MTL and contains editable UV coordinates" % label)

	var mesh := load(stem + ".obj") as ArrayMesh
	_check(mesh != null and mesh.get_surface_count() > 0,
		"%s imports independently as an ArrayMesh" % label)
	var uv_complete := mesh != null and mesh.get_surface_count() > 0
	if mesh != null:
		for surface in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface)
			uv_complete = uv_complete \
				and not (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).is_empty()
	_check(uv_complete, "%s has UVs on every imported surface" % label)

	var scene_path := str(spec["scene"])
	var scene_text := FileAccess.get_file_as_string(scene_path)
	_check(scene_text.contains("ext_resource type=\"Mesh\"")
		and scene_text.contains("ext_resource type=\"Texture2D\"")
		and not scene_text.contains("sub_resource type=\"BoxMesh\"")
		and not scene_text.contains("sub_resource type=\"CylinderMesh\"")
		and not scene_text.contains("sub_resource type=\"SphereMesh\"")
		and not scene_text.contains("sub_resource type=\"TorusMesh\""),
		"%s wrapper is thin and contains no visible primitive geometry" % label)
	var packed := load(scene_path) as PackedScene
	var instance := packed.instantiate() as Node3D if packed != null else null
	var model := instance.find_child("Model", true, false) as MeshInstance3D \
		if instance != null else null
	_check(instance != null
		and str(instance.get_meta("asset_contract", "")) == "editable_3d_v1"
		and str(instance.get_meta("visual_identity", "")) == str(spec["identity"])
		and model != null and model.mesh is ArrayMesh,
		"%s wrapper exposes its portable visual identity" % label)
	if model != null and model.mesh != null:
		var actual := model.mesh.get_aabb().size
		var minimum: Vector3 = spec["min_size"]
		_check(actual.x >= minimum.x and actual.y >= minimum.y and actual.z >= minimum.z,
			"%s silhouette is mechanism-sized (%s)" % [label, actual])
	if instance != null:
		instance.free()


func _verify_repeatable_source() -> void:
	var source_path := "res://tools/asset_sources/mother_flure_mechanisms_source.tscn"
	var catalog_path := "res://tools/bake_authored_asset_catalog.gd"
	var source_text := FileAccess.get_file_as_string(source_path)
	var catalog_text := FileAccess.get_file_as_string(catalog_path)
	_check(FileAccess.file_exists(source_path)
		and source_text.contains("metadata/tooling_only = true"),
		"Mother mechanism construction recipe is retained as tooling-only source")
	for family in ["portal_frame", "mother_gear", "rings_membrane"]:
		_check(catalog_text.contains("\"folder\": \"mother-flure/%s\"" % family),
			"repeatable catalog exports the %s family" % family)
	_check(catalog_text.contains("ASSET_FAMILY"),
		"catalog can rebake Mother assets without touching unrelated hand-edited families")


func _verify_runtime_portals(chunk) -> void:
	var base_model := chunk._portal_base_frame.find_child(
		"Model", true, false) as MeshInstance3D
	var remote_model := chunk._portal_remote_frame.find_child(
		"Model", true, false) as MeshInstance3D
	_check(str(chunk._portal_base_frame.get_meta("visual_identity", "")) \
			== "mother_portal_frame_v1"
		and base_model != null and base_model.mesh is ArrayMesh,
		"base portal instantiates the external ring hardware")
	_check(str(chunk._portal_remote_frame.get_meta("visual_identity", "")) \
			== "mother_portal_frame_v1"
		and remote_model != null and remote_model.mesh == base_model.mesh,
		"remote mouth reuses the same external portal hardware")
	_check(chunk._portal_base_fill.mesh is CylinderMesh
		and str(chunk._portal_base_fill.get_meta("runtime_state_visual", "")) == "portal_lens"
		and not (chunk._portal_base_fill.mesh is BoxMesh),
		"only the live elliptical portal lens remains procedural")

	chunk._active_terminal_id = "term_beta"
	chunk._portal_open_until = chunk._get_scheduler_tick() + 5.0
	chunk._update_portal_visuals()
	_check(chunk._portal_remote_frame.visible
		and chunk._portal_remote_frame.position.is_equal_approx(
			chunk._terminal_service_position("term_beta")),
		"opening a terminal reveals a framed remote mouth at the real service bay")


func _verify_shared_gear_identity(host, chunk) -> void:
	var state: Dictionary = chunk.get_preview_state()
	var item_id := str(state.get("gear_item", ""))
	var item: Dictionary = host.game_state.items.get(item_id, {})
	var properties: Dictionary = item.get("properties", {})
	var installed_model := chunk._installed_gear_root.find_child(
		"Model", true, false) as MeshInstance3D
	_check(str(properties.get("visual_identity", "")) == GEAR_IDENTITY
		and str(properties.get("visual_scene", "")) \
			== "res://scenes/props/mother_flure/mother_gear.tscn",
		"loose authoritative gear names the shared authored visual")
	_check(str(chunk._installed_gear_root.get_meta("visual_identity", "")) == GEAR_IDENTITY
		and installed_model != null and installed_model.mesh is ArrayMesh,
		"installed socket view instantiates that same authored gear identity")

	var presenter_text := FileAccess.get_file_as_string(
		"res://scripts/fragments/fragment_preview_sequence.gd")
	_check(presenter_text.contains("if visual_kind == \"mother_gear\":")
		and presenter_text.contains("MOTHER_GEAR_VISUAL_SCENE.instantiate()")
		and not presenter_text.contains("\"gear\", \"mother_gear\":"),
		"ground and carried item presenter uses the authored gear instead of a TorusMesh proxy")

	host.game_state.snap_character_to("endo", chunk.GEAR_POS)
	_check(host.game_state.pick_up_item("endo", item_id)
		and str((host.game_state.items[item_id] as Dictionary).get("location", "")) == "hand"
		and str(((host.game_state.items[item_id] as Dictionary).get(
			"properties", {}) as Dictionary).get("visual_identity", "")) == GEAR_IDENTITY,
		"two-hand carry preserves the exact same visual identity in GameState")
	chunk._gear_installed = true
	chunk._installed_repair_id = chunk.CORRECT_REPAIR_ID
	chunk._update_mother_visuals()
	_check(chunk._installed_gear_root.visible,
		"committed repair reveals the authored gear rather than a replacement sphere")


func _verify_lifting_membrane(chunk) -> void:
	var membrane_model: MeshInstance3D = chunk._rings_membrane_mesh
	_check(str(chunk._exit_gate_root.get_meta("visual_identity", "")) \
		== "mother_rings_membrane_v1"
		and membrane_model != null and membrane_model.mesh is ArrayMesh
		and not (membrane_model.mesh is BoxMesh),
		"Rings gate uses the external ribbed chembrane, not the old box beacon")
	var exit_position: Vector3 = chunk.EXIT_POS
	var start_y := exit_position.y
	chunk._rings_gate_phase = chunk.RINGS_GATE_PHASE_OPENING
	chunk._rings_gate_started_at = 10.0
	chunk._rings_gate_deadline = 12.0
	chunk._update_timed_physical_presenters(11.0)
	var midpoint_y: float = chunk._exit_gate_root.position.y
	chunk._rings_gate_phase = chunk.RINGS_GATE_PHASE_OPEN
	chunk._update_timed_physical_presenters(12.0)
	_check(midpoint_y > start_y
		and midpoint_y < start_y + chunk.RINGS_GATE_OPEN_OFFSET.y
		and chunk._exit_gate_root.position.is_equal_approx(
			chunk.EXIT_POS + chunk.RINGS_GATE_OPEN_OFFSET),
		"saved opening progress visibly lifts the same physical membrane to its endpoint")


func _boot() -> Dictionary:
	var host = HostScript.new()
	host.setup(false)
	var chunk = MotherScript.new()
	host.register_party(chunk.get_spawn_positions())
	for char_id in chunk.CANONICAL_PARTY:
		host.game_state.set_stat(str(char_id), "hp", 100.0)
		host.game_state.set_stat(str(char_id), "stamina", 100.0)
		host.game_state.set_stat(str(char_id), "atp", 8.0)
	root.add_child(host)
	chunk.attach_chunk_host(host, FIXTURE_ID)
	host.add_child(chunk)
	await process_frame
	await process_frame
	chunk.reset_preview_state()
	return {"host": host, "chunk": chunk}


func _discard(host: Node) -> void:
	if host != null and is_instance_valid(host):
		host.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		push_error("  FAIL: %s" % message)
