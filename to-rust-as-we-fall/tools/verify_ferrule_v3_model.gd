extends SceneTree

## Focused authoring/import guard for the Ferrule's mobile slinky presentation.
## Gameplay authority is intentionally outside this verifier: the asset is not a runtime enemy yet.

const MODEL_PATH := "res://resources/models/fauna/ferrule_v3/ferrule.gltf"
const BIN_PATH := "res://resources/models/fauna/ferrule_v3/ferrule.bin"
const BODY_TEXTURE := "res://resources/models/fauna/ferrule_v3/ferrule_body.png"
const MOUTH_TEXTURE := "res://resources/models/fauna/ferrule_v3/ferrule_mouth.png"
const SIGNAL_TEXTURE := "res://resources/models/fauna/ferrule_v3/ferrule_signal.png"
const SIGNAL_EMISSIVE := "res://resources/models/fauna/ferrule_v3/ferrule_signal_emissive.png"
const WRAPPER_PATH := "res://scenes/props/biota/ferrule_v3_visual.tscn"
const MASTER_PATH := "res://../blender/fauna/ferrule/ferrule_v3.blend"
const EXPORT_HELPER_PATH := "res://../blender/fauna/ferrule/export_ferrule_v3.py"
const EXPECTED_ANIMATIONS := ["idle", "compress", "spring", "latch"]

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_verify_portable_files()
	_verify_gltf_sidecars()
	_verify_wrapper()
	print("FERRULE V3 MODEL: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_portable_files() -> void:
	for path in [MODEL_PATH, BIN_PATH, BODY_TEXTURE, MOUTH_TEXTURE, SIGNAL_TEXTURE, SIGNAL_EMISSIVE]:
		_check(FileAccess.file_exists(path), "%s exists" % path.get_file())
	for path in [BODY_TEXTURE, MOUTH_TEXTURE, SIGNAL_TEXTURE, SIGNAL_EMISSIVE]:
		var texture := load(path) as Texture2D
		var image := texture.get_image() if texture != null else null
		_check(image != null and not image.is_empty(), "%s loads independently" % path.get_file())

	var master_path := ProjectSettings.globalize_path(MASTER_PATH)
	var export_helper_path := ProjectSettings.globalize_path(EXPORT_HELPER_PATH)
	_check(FileAccess.file_exists(master_path), "editable Blender master is retained outside runtime files")
	_check(FileAccess.file_exists(export_helper_path),
		"repeatable export helper is retained beside the Blender master")


func _verify_gltf_sidecars() -> void:
	var source := FileAccess.get_file_as_string(MODEL_PATH)
	var parsed = JSON.parse_string(source)
	_check(parsed is Dictionary, "glTF is valid JSON")
	if not parsed is Dictionary:
		return
	var document := parsed as Dictionary
	var buffers := document.get("buffers", []) as Array
	_check(not buffers.is_empty() and str((buffers[0] as Dictionary).get("uri", "")) == "ferrule.bin",
		"geometry buffer remains external")
	var image_uris: Array[String] = []
	var emissive_image_index := -1
	var images := document.get("images", []) as Array
	for image_index in range(images.size()):
		var image_v = images[image_index]
		var uri := str((image_v as Dictionary).get("uri", ""))
		if uri != "":
			image_uris.append(uri)
	_check(image_uris.has("ferrule_body.png")
		and image_uris.has("ferrule_mouth.png")
		and image_uris.has("ferrule_signal.png")
		and image_uris.has("ferrule_signal_emissive.png"),
		"glTF binds all four external paint sheets")
	if image_uris.has("ferrule_signal_emissive.png"):
		emissive_image_index = image_uris.find("ferrule_signal_emissive.png")
	var emissive_texture_index := -1
	var textures := document.get("textures", []) as Array
	for texture_index in range(textures.size()):
		if int((textures[texture_index] as Dictionary).get("source", -1)) == emissive_image_index:
			emissive_texture_index = texture_index
			break
	var signal_binds_emissive := false
	var all_materials_opaque := true
	for material_v in document.get("materials", []) as Array:
		var material := material_v as Dictionary
		if str(material.get("alphaMode", "OPAQUE")) != "OPAQUE":
			all_materials_opaque = false
		if str(material.get("name", "")) != "FerruleSignal":
			continue
		var emissive := material.get("emissiveTexture", {}) as Dictionary
		signal_binds_emissive = emissive_texture_index >= 0 \
			and int(emissive.get("index", -1)) == emissive_texture_index
		break
	_check(signal_binds_emissive,
		"FerruleSignal binds ferrule_signal_emissive.png as its emissive channel")
	_check(all_materials_opaque,
		"opaque Ferrule textures do not import through blended material paths")


func _verify_wrapper() -> void:
	var wrapper_text := FileAccess.get_file_as_string(WRAPPER_PATH)
	_check(FileAccess.file_exists(WRAPPER_PATH)
		and wrapper_text.contains("ferrule.gltf")
		and not wrapper_text.contains("sub_resource type=\"BoxMesh\"")
		and not wrapper_text.contains("sub_resource type=\"SphereMesh\"")
		and not wrapper_text.contains("sub_resource type=\"CapsuleMesh\""),
		"thin wrapper instances the portable model and owns no visible primitives")
	_check(wrapper_text.contains("../blender/fauna/ferrule/ferrule_v3.blend")
		and wrapper_text.contains("../blender/fauna/ferrule/export_ferrule_v3.py"),
		"wrapper records project-relative authoring and export sources")

	var model_packed := load(MODEL_PATH) as PackedScene
	var direct_model := model_packed.instantiate() if model_packed != null else null
	_check(direct_model != null and direct_model.get_child_count() > 0,
		"portable glTF instantiates independently of its wrapper")
	if direct_model != null:
		direct_model.free()

	var packed := load(WRAPPER_PATH) as PackedScene
	var instance := packed.instantiate() as Node3D if packed != null else null
	var model_node := instance.get_node_or_null("Model") if instance != null else null
	_check(instance != null and model_node != null and model_node.get_child_count() > 0,
		"wrapper contains a populated imported Model child")
	if instance == null:
		return
	_check(str(instance.get_meta("asset_contract", "")) == "editable_3d_v1"
		and str(instance.get_meta("visual_identity", "")) == "ferrule_slinky_v1"
		and str(instance.get_meta("motion_model", "")) == "compress_release_latch",
		"wrapper advertises the portable identity and slinky motion contract")
	var roles: Dictionary = instance.get_meta("action_roles", {})
	_check(roles.size() == 4 and roles.has("Ferrule_Compress")
		and roles.has("Ferrule_Spring") and roles.has("Ferrule_Latch")
		and str(instance.get_meta("action_chain", "")).contains("FSM mapping"),
		"wrapper maps every action to a gameplay role and records the pose chain")
	_check(instance.get_node_or_null("FacingSocket") is Marker3D
		and instance.get_node_or_null("ImpactSocket") is Marker3D
		and instance.get_node_or_null("RearAnchorSocket") is Marker3D,
		"forward, mouth-impact, and rear-anchor sockets remain explicit")
	var facing_socket := instance.get_node_or_null("FacingSocket") as Marker3D
	var impact_socket := instance.get_node_or_null("ImpactSocket") as Marker3D
	var rear_socket := instance.get_node_or_null("RearAnchorSocket") as Marker3D
	_check(facing_socket != null and impact_socket != null and rear_socket != null
		and facing_socket.position.z > 2.2
		and impact_socket.position.z > 2.0
		and rear_socket.position.z < -1.2,
		"wrapper sockets bracket the mouth-first +Z silhouette")

	var audit := {
		"mesh_count": 0,
		"uv_complete": true,
		"bounds": AABB(),
		"has_bounds": false,
		"skeleton_bones": 0,
		"animation_names": [],
		"names": [],
		"albedo_texture_paths": {},
		"emission_texture_paths": {},
		"transparent_materials": 0,
	}
	_audit_tree(instance, Transform3D.IDENTITY, audit, true)
	_check(int(audit["mesh_count"]) >= 7,
		"Ferrule retains separately readable rigid masses (%d meshes)" % int(audit["mesh_count"]))
	_check(bool(audit["uv_complete"]), "every imported visible mesh surface has UVs")
	var albedo_paths := audit["albedo_texture_paths"] as Dictionary
	_check(albedo_paths.has(BODY_TEXTURE)
		and albedo_paths.has(MOUTH_TEXTURE)
		and albedo_paths.has(SIGNAL_TEXTURE),
		"body, mouth, and signal material families retain distinct external textures")
	var emission_paths := audit["emission_texture_paths"] as Dictionary
	_check(emission_paths.has(SIGNAL_EMISSIVE),
		"imported signal material uses the external emissive texture")
	_check(int(audit["transparent_materials"]) == 0,
		"imported Ferrule materials remain opaque")
	_check(int(audit["skeleton_bones"]) >= 7,
		"rig preserves enough rigid pivots for compression and release")

	var joined_names := " ".join(audit["names"] as Array).to_lower()
	_check(joined_names.contains("mouth")
		and joined_names.contains("segment")
		and joined_names.contains("anchor")
		and joined_names.contains("signal"),
		"named mouth, segment, anchor, and signal parts survive import")
	var imported_animations := audit["animation_names"] as Array
	for expected in EXPECTED_ANIMATIONS:
		var found := false
		for animation_name in imported_animations:
			if animation_name.to_lower().contains(expected):
				found = true
				break
		_check(found, "%s animation imports" % expected)

	var bounds := audit["bounds"] as AABB
	_check(bounds.size.x >= 0.55 and bounds.size.x <= 2.4
		and bounds.size.y >= 0.85 and bounds.size.y <= 2.4
		and bounds.size.z >= 2.0 and bounds.size.z <= 5.0,
		"world-scale arch has a bounded gameplay silhouette (%s)" % bounds.size)
	_check(bounds.position.y >= -0.12 and bounds.position.y <= 0.18,
		"model origin remains a ground pivot (min y %.3f)" % bounds.position.y)
	instance.free()


func _audit_tree(node: Node, parent_transform: Transform3D, audit: Dictionary,
		is_root := false) -> void:
	(audit["names"] as Array).append(str(node.name))
	var current_transform := parent_transform
	if node is Node3D and not is_root:
		current_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh != null:
			audit["mesh_count"] = int(audit["mesh_count"]) + 1
			var transformed := current_transform * mesh.get_aabb()
			audit["bounds"] = transformed if not bool(audit["has_bounds"]) \
				else (audit["bounds"] as AABB).merge(transformed)
			audit["has_bounds"] = true
			for surface in range(mesh.get_surface_count()):
				var arrays := mesh.surface_get_arrays(surface)
				var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				var uvs := arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
				if vertices.is_empty() or uvs.size() != vertices.size():
					audit["uv_complete"] = false
				var material := mesh_instance.get_active_material(surface) as StandardMaterial3D
				if material != null:
					if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
						audit["transparent_materials"] = int(audit["transparent_materials"]) + 1
					if material.albedo_texture != null:
						(audit["albedo_texture_paths"] as Dictionary)[
							material.albedo_texture.resource_path] = true
					if material.emission_enabled and material.emission_texture != null:
						(audit["emission_texture_paths"] as Dictionary)[
							material.emission_texture.resource_path] = true
	if node is Skeleton3D:
		audit["skeleton_bones"] = maxi(int(audit["skeleton_bones"]),
			(node as Skeleton3D).get_bone_count())
	if node is AnimationPlayer:
		for animation_name in (node as AnimationPlayer).get_animation_list():
			(audit["animation_names"] as Array).append(str(animation_name))
	for child in node.get_children():
		_audit_tree(child, current_transform, audit)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		push_error("  FAIL: %s" % message)
