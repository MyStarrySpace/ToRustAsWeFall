class_name ContentFingerprint
extends RefCounted

## Versioned content identity for persona provenance.
##
## Authored fragments deliberately hash the resource bytes rather than a
## platform-specific loaded Resource representation.  Native and Web runners
## can therefore identify the same authored content with the same digest.
## Generated specifications hash a canonical semantic projection.  Runtime and
## platform bookkeeping is removed recursively; changes to actual generated
## content remain identity changes.

const AUTHORED_FRAGMENT_SCHEMA := "authored_fragment_resource_bytes_v1"
const GENERATED_SPEC_SCHEMA := "generated_spec_semantic_v1"
const GAMEPLAY_BUILD_SCHEMA := "gameplay_build_resource_set_bytes_v1"

# This is intentionally a fixed, reviewed set rather than a directory walk.
# The authored fragment has its own content identity; this set identifies the
# shipped scene-host, movement, interaction, navigation, consequence/event,
# presentation, HUD, Web-observation, and persona-input behavior that turns
# those bytes into a human-playable run on Native or Web.
# Hashing paths and exact bytes makes the result independent of filesystem
# timestamps, import-cache metadata, platform, and file enumeration order.
# Text scene files are deliberately excluded from this byte schema because an
# export may remap them to binary resources. Their feedback/input behavior is
# represented here by the portable scripts that own those contracts.
const GAMEPLAY_BUILD_RESOURCE_PATHS := [
	"res://project.godot",
	"res://scenes/fragments/fragment.gd",
	"res://scripts/fragments/chunks/data_fragment_chunk.gd",
	"res://scripts/fragments/fragment_preview_sequence.gd",
	"res://scripts/fragments/preview_web_e2e_controller.gd",
	"res://scripts/fragments/puzzle_fragment_runner.gd",
	"res://scripts/game/characters/character_interaction_controller.gd",
	"res://scripts/game/characters/locomotion_juice.gd",
	"res://scripts/game/characters/player.gd",
	"res://scripts/game/characters/selection_controller.gd",
	"res://scripts/game/objects/basin_water.gd",
	"res://scripts/game/objects/basin_water_compat.gd",
	"res://scripts/game/objects/moving_platform_passenger_system.gd",
	"res://scripts/game/objects/moving_platform_3d.gd",
	"res://scripts/game/objects/rising_water_crossing_spec.gd",
	"res://scripts/generation/rising_water_crossing_generator.gd",
	"res://scripts/game/objects/crossing_assist.gd",
	"res://scripts/game/objects/interactable.gd",
	"res://scripts/game/world/causal_feedback_link.gd",
	"res://scripts/game/world/consequence_presentation_controller.gd",
	"res://scripts/game/world/grid_world.gd",
	"res://scripts/game/world/path_render_manager.gd",
	"res://scripts/game/world/path_renderer.gd",
	"res://scripts/system/core/event_log.gd",
	"res://scripts/system/core/fixed_cadence.gd",
	"res://scripts/system/core/game_event.gd",
	"res://scripts/system/core/game_state.gd",
	"res://scripts/testing/content_fingerprint.gd",
	"res://scripts/testing/persona_decision_trace.gd",
	"res://scripts/testing/persona_player_controller.gd",
	"res://scripts/testing/player_observation_controller.gd",
	"res://scripts/ui/game_hud.gd",
	"res://scripts/ui/rally_hold_indicator.gd",
	"res://tools/agent_player_input_driver.gd",
]

const GENERATED_METADATA_KEYS := [
	"elapsed_ms",
	"execution_platform",
	"generated_at",
	"generated_at_ms",
	"invocation_id",
	"platform",
	"platform_metadata",
	"repeat_index",
	"run_id",
	"runtime",
	"runtime_metadata",
	"timestamp",
	"timestamp_ms",
	"trace_id",
	"wall_clock",
	"wall_clock_ms",
]


static func authored_fragment_resource(path: String) -> Dictionary:
	var normalized_path := path.strip_edges()
	if normalized_path == "":
		return {"ok": false, "error": "authored fragment resource path is required"}
	if not FileAccess.file_exists(normalized_path):
		return {"ok": false, "error": "authored fragment resource does not exist: %s" % normalized_path}
	var bytes := FileAccess.get_file_as_bytes(normalized_path)
	if bytes.is_empty():
		# An empty file is still content, but a read error must not masquerade as
		# the stable SHA-256 of empty bytes.
		var probe := FileAccess.open(normalized_path, FileAccess.READ)
		if probe == null:
			return {"ok": false, "error": "cannot read authored fragment resource: %s" % normalized_path}
		probe.close()
	return {
		"ok": true,
		"content_fingerprint_schema": AUTHORED_FRAGMENT_SCHEMA,
		"content_fingerprint": _sha256_bytes(bytes),
	}


static func generated_spec(specification: Dictionary) -> Dictionary:
	var semantic_payload: Variant = _generated_semantic_value(specification)
	return {
		"ok": true,
		"content_fingerprint_schema": GENERATED_SPEC_SCHEMA,
		"content_fingerprint": canonical_hash(semantic_payload),
		"semantic_payload": semantic_payload,
	}


static func gameplay_build() -> Dictionary:
	var resource_bytes := {}
	var inventory := gameplay_build_resource_inventory()
	var seen_paths := {}
	for path in inventory:
		if path == "" or seen_paths.has(path):
			return {
				"ok": false,
				"error": "gameplay-build resource inventory contains an empty or duplicate path",
			}
		seen_paths[path] = true
		if not FileAccess.file_exists(path):
			return {
				"ok": false,
				"error": "gameplay-build resource does not exist: %s" % path,
			}
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.is_empty():
			# Empty source is legal in theory; distinguish it from a failed read.
			var probe := FileAccess.open(path, FileAccess.READ)
			if probe == null:
				return {
					"ok": false,
					"error": "cannot read gameplay-build resource: %s" % path,
				}
			probe.close()
		resource_bytes[path] = bytes
	return gameplay_build_from_resource_bytes(resource_bytes)


static func gameplay_build_resource_inventory() -> Array[String]:
	var inventory: Array[String] = []
	for path_value in GAMEPLAY_BUILD_RESOURCE_PATHS:
		inventory.append(str(path_value))
	inventory.sort()
	return inventory


## Pure hashing seam used by the regression verifier. Production run metadata
## must call gameplay_build(), which reads the reviewed fixed inventory itself.
static func gameplay_build_from_resource_bytes(resource_bytes: Dictionary) -> Dictionary:
	var inventory: Array[String] = []
	for path_value in resource_bytes.keys():
		var path := str(path_value)
		if path == "" or not (resource_bytes[path_value] is PackedByteArray):
			return {
				"ok": false,
				"error": "gameplay-build resource bytes are invalid for: %s" % path,
			}
		inventory.append(path)
	inventory.sort()
	var resources := {}
	for path in inventory:
		var bytes := resource_bytes[path] as PackedByteArray
		resources[path] = {
			"byte_length": bytes.size(),
			"sha256": _sha256_bytes(bytes),
		}
	return {
		"ok": true,
		"gameplay_build_fingerprint_schema": GAMEPLAY_BUILD_SCHEMA,
		"gameplay_build_fingerprint": canonical_hash({
			"schema": GAMEPLAY_BUILD_SCHEMA,
			"resources": resources,
		}),
		"gameplay_build_resource_inventory": inventory,
		"gameplay_build_resource_manifest": resources,
	}


static func is_supported_schema(schema: String) -> bool:
	return schema in [AUTHORED_FRAGMENT_SCHEMA, GENERATED_SPEC_SCHEMA]


static func is_supported_gameplay_build_schema(schema: String) -> bool:
	return schema == GAMEPLAY_BUILD_SCHEMA


static func canonical_hash(value: Variant) -> String:
	var normalized: Variant = _json_safe(value)
	var encoded := JSON.stringify(normalized, "", true, true)
	# Match the trace hash contract: normalize JSON numeric types before hashing.
	var reparsed: Variant = JSON.parse_string(encoded)
	return JSON.stringify(reparsed, "", true, true).sha256_text()


static func _generated_semantic_value(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		var keys: Array[String] = []
		for raw_key in (value as Dictionary).keys():
			var key := str(raw_key)
			if key.to_lower() not in GENERATED_METADATA_KEYS:
				keys.append(key)
		keys.sort()
		for key in keys:
			result[key] = _generated_semantic_value((value as Dictionary).get(key))
		return result
	if value is Array:
		var result: Array = []
		for item in value as Array:
			result.append(_generated_semantic_value(item))
		return result
	return _json_safe(value)


static func _json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return value
		TYPE_FLOAT:
			return float(value) if is_finite(float(value)) else null
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)
		TYPE_VECTOR2:
			return [value.x, value.y]
		TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3:
			return [value.x, value.y, value.z]
		TYPE_VECTOR3I:
			return [value.x, value.y, value.z]
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			var array: Array = []
			for item in value:
				array.append(_json_safe(item))
			return array
		TYPE_DICTIONARY:
			var result := {}
			var keys: Array[String] = []
			for raw_key in (value as Dictionary).keys():
				keys.append(str(raw_key))
			keys.sort()
			for key in keys:
				result[key] = _json_safe((value as Dictionary).get(key))
			return result
		_:
			return str(value)


static func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	var started := context.start(HashingContext.HASH_SHA256)
	if started != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()
