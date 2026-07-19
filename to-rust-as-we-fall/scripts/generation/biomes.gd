class_name Biomes
extends RefCounted

## BIOMES are named CONTENT presets — a coherent slice of the flora/fauna/structure palette that gives a stretch
## its character (the flooded Channels vs the vertical Stacks vs an overgrown Garden vs a failed dead zone). A
## biome is realized purely through the generator's EXISTING `limitations.allowed` machinery (no new generation
## logic): `settings.biome` restricts content to that biome's lists. The roster/solver invariants are unaffected
## — specialist capabilities ride the party, and the bare pair's base capabilities don't depend on placed content.
## All ids are canonical content_palette.json keys (fauna use the renamed roster: Sapscraps/Aembers/Flares/Redactors).

const BIOME_SEQUENCE := ["channels", "stacks", "garden", "cleanstreets", "deadzone"]

const BIOMES := {
	"channels": {
		"display": "Plumbing Power Project",
		"flora": ["scarpet", "flure", "capbage", "seefern"],
		"enemies": ["hidras", "naturalizers", "redactors", "aembers", "flares"],
		"structures": ["shelter", "water_control", "pipe", "terminal", "shortcut_gate", "hide_slot"],
		"theme": {
			"source_area": "Plumbing Power Project / Channels",
			"floor_tile": "deck_metal",
			"risk_tile": "rust_iron",
			"light_color": [0.58, 0.82, 0.96, 1.0],
			"light_energy": 1.35,
			"building_vocabulary": ["octagonal pump-house", "service wing", "external flume"],
			"feature_vocabulary": ["valve bank", "flow strip", "open channel trough"],
			"landmarks": [{
				"id": "channels_pump_house",
				"kind": "building_feature_cluster",
				"scene": "res://scenes/fragments/themes/generated_channels_pump_house.tscn",
				"asset_contract": "editable_3d_v1",
				"editable_assets": [
					"res://resources/models/generated-biomes/channels_pump_house/channels_pump_house_structure.obj",
					"res://resources/models/generated-biomes/channels_pump_house/channels_pump_house_fixtures.obj",
					"res://resources/models/generated-biomes/channels_pump_house/channels_pump_house_flow.obj",
				],
				"anchor_structures": ["water_control", "pipe", "terminal"],
				"clearance": 3.8,
				"primary_read": "Flow infrastructure ties the nearby control to the route's hydraulic state.",
				"feedback_role": "The lit trough and valve bank repeat the Channels flow language from first sight.",
			}],
		},
	},
	"stacks": {
		"display": "The Open Files Initiative",
		"flora": ["climbvine", "flure", "hushbloom", "doma"],
		"enemies": ["spikers", "tanglers", "gnawers", "sapscraps"],
		"structures": ["shelter", "junction", "barrier", "carry_gear", "terminal"],
		"theme": {
			"source_area": "The Open Files Initiative / Stacks",
			"floor_tile": "facility_metal",
			"risk_tile": "grate",
			"light_color": [0.63, 0.76, 0.94, 1.0],
			"light_energy": 1.25,
			"building_vocabulary": ["drawer-stack spire", "archive canyon", "service catwalk"],
			"feature_vocabulary": ["scan arch", "terminal kiosk", "live drawer bands"],
			"landmarks": [{
				"id": "stacks_archive_spire",
				"kind": "building_feature_cluster",
				"scene": "res://scenes/fragments/themes/generated_stacks_archive_spire.tscn",
				"asset_contract": "editable_3d_v1",
				"editable_assets": [
					"res://resources/models/generated-biomes/stacks_archive_spire/stacks_archive_spire_structure.obj",
					"res://resources/models/generated-biomes/stacks_archive_spire/stacks_archive_spire_drawers.obj",
					"res://resources/models/generated-biomes/stacks_archive_spire/stacks_archive_spire_scan.obj",
					"res://resources/models/generated-biomes/stacks_archive_spire/stacks_archive_spire_terminal.obj",
				],
				"anchor_structures": ["terminal", "junction", "carry_gear", "barrier"],
				"clearance": 3.6,
				"primary_read": "The archive's scan throat frames nearby terminals as parts of one information route.",
				"feedback_role": "Cyan scan light and green drawer cells distinguish observed data from dead storage.",
			}],
		},
	},
	"garden": {
		"display": "Greenfields Collective",
		"flora": ["seefern", "scarpet", "capbage", "hushbloom", "gasafoetida", "snapbloom"],
		"enemies": ["meebs", "candids", "toxos", "gnawers"],
		"structures": ["shelter", "forage_cache", "terminal", "root_slide"],
		"theme": {
			"source_area": "Greenfields Collective / Flora Garden",
			"floor_tile": "rock",
			"risk_tile": "sand",
			"light_color": [0.62, 0.92, 0.68, 1.0],
			"light_energy": 1.2,
			"building_vocabulary": ["root pavilion", "terraced planter", "overgrown shelter frame"],
			"feature_vocabulary": ["root trellis", "tended-light cluster", "forage bed"],
			"landmarks": [{
				"id": "garden_root_pavilion",
				"kind": "building_feature_cluster",
				"scene": "res://scenes/fragments/themes/generated_garden_root_pavilion.tscn",
				"asset_contract": "editable_3d_v1",
				"editable_assets": [
					"res://resources/models/generated-biomes/garden_root_pavilion/garden_root_pavilion_structure.obj",
					"res://resources/models/generated-biomes/garden_root_pavilion/garden_root_pavilion_roots.obj",
					"res://resources/models/generated-biomes/garden_root_pavilion/garden_root_pavilion_foliage.obj",
					"res://resources/models/generated-biomes/garden_root_pavilion/garden_root_pavilion_tended_nodes.obj",
				],
				"anchor_structures": ["root_slide", "forage_cache", "shelter"],
				"clearance": 3.9,
				"primary_read": "Tended roots connect refuge, forage, and traversal as one maintained living system.",
				"feedback_role": "Healthy teal nodes sit on living roots while failed growth remains dark and brittle.",
			}],
		},
	},
	"cleanstreets": {
		"display": "The Cleanstreets Initiative",
		"flora": ["scarpet", "flure", "capbage", "seefern", "hushbloom"],
		"enemies": ["naturalizers", "redactors", "gnawers", "spikers"],
		"structures": ["shelter", "terminal", "class_gate", "shortcut_gate", "junction", "hide_slot", "barrier", "carry_gear"],
		"theme": {
			"source_area": "The Cleanstreets Initiative / Transit Plazas",
			"floor_tile": "wall_panel",
			"risk_tile": "facility_metal",
			"light_color": [0.92, 0.78, 0.52, 1.0],
			"light_energy": 1.35,
			"building_vocabulary": ["toll-canopy pavilion", "sweeping arterial", "memorial traffic island"],
			"feature_vocabulary": ["anti-loiter stud lane", "slanted no-rest bench", "flow-optimization queue fin"],
			"landmarks": [{
				"id": "cleanstreets_toll_pavilion",
				"kind": "building_feature_cluster",
				"scene": "res://scenes/fragments/themes/generated_cleanstreets_toll_pavilion.tscn",
				"asset_contract": "editable_3d_v1",
				"editable_assets": [
					"res://resources/models/cleanstreets/toll_pavilion/cleanstreets_toll_pavilion_structure.obj",
					"res://resources/models/cleanstreets/toll_pavilion/cleanstreets_toll_pavilion_fixtures.obj",
					"res://resources/models/cleanstreets/toll_pavilion/cleanstreets_toll_pavilion_screen.obj",
					"res://resources/models/cleanstreets/toll_pavilion/cleanstreets_toll_pavilion_studs.obj",
				],
				"anchor_structures": ["terminal", "class_gate", "shortcut_gate", "junction", "hide_slot", "barrier", "carry_gear"],
				"clearance": 4.8,
				"primary_read": "The immaculate arterial narrows through a toll pavilion whose furniture is designed to prevent rest.",
				"feedback_role": "Pale road panels identify the public route; dark studded cells identify the painful direct lane before movement is committed.",
			}],
			"route_setpieces": [{
				"id": "anti_loiter_stud_lane",
				"kind": "symmetric_damage_lane",
				"scene": "res://scenes/fragments/themes/generated_cleanstreets_spike_lane.tscn",
				"asset_contract": "editable_3d_v1",
				"editable_assets": [
					"res://resources/models/cleanstreets/spike_lane/cleanstreets_spike_lane_road.obj",
					"res://resources/models/cleanstreets/spike_lane/cleanstreets_spike_lane_curbs.obj",
					"res://resources/models/cleanstreets/spike_lane/cleanstreets_spike_lane_studs.obj",
				],
				"count": 5,
				"damage_per_second": 4.0,
				"primary_read": "The metal studs occupy cells the route preview already marks as risky.",
				"leverage": "SAFE routing bends around the studded direct lane; a fast direct order trades health for time.",
				"failure_prediction": "Standing or stopping on the studs drains health continuously, rather than dealing an unexplained hit later.",
			}],
		},
	},
	"deadzone": {
		"display": "The Dead Zone",
		"flora": ["scarpet", "forget_me_nots", "resolution_roots"],
		"enemies": ["toxos", "crusts", "candids", "redactors"],
		"structures": ["shelter", "terminal", "membrane"],
		"theme": {
			"source_area": "The Dead Zone",
			"floor_tile": "rust_iron",
			"risk_tile": "rock",
			"light_color": [0.72, 0.58, 0.54, 1.0],
			"light_energy": 1.05,
			"building_vocabulary": ["quarantine ruin", "failed relay shell", "collapsed service frame"],
			"feature_vocabulary": ["chembrane breach", "dead root ribs", "failing warning beacon"],
			"landmarks": [{
				"id": "deadzone_chembrane_ruin",
				"kind": "building_feature_cluster",
				"scene": "res://scenes/fragments/themes/generated_deadzone_chembrane_ruin.tscn",
				"asset_contract": "editable_3d_v1",
				"editable_assets": [
					"res://resources/models/generated-biomes/deadzone_chembrane_ruin/deadzone_chembrane_ruin_structure.obj",
					"res://resources/models/generated-biomes/deadzone_chembrane_ruin/deadzone_chembrane_ruin_chembrane.obj",
					"res://resources/models/generated-biomes/deadzone_chembrane_ruin/deadzone_chembrane_ruin_roots.obj",
					"res://resources/models/generated-biomes/deadzone_chembrane_ruin/deadzone_chembrane_ruin_warning.obj",
				],
				"anchor_structures": ["membrane", "terminal"],
				"clearance": 4.0,
				"primary_read": "The breached chembrane shows that local containment failed around one shared boundary.",
				"feedback_role": "Intact ribs retain a weak signal while the breach and dead roots remain visibly inert.",
			}],
		},
	},
}

static func biome_ids() -> Array:
	return BIOME_SEQUENCE.duplicate()

static func has_biome(id: String) -> bool:
	return BIOMES.has(id)

static func display_name(id: String) -> String:
	return str(BIOMES.get(id, {}).get("display", id.capitalize()))

## The generator `limitations` block for a biome — restricts content to the biome's lists via `allowed`.
static func limitations_for(id: String) -> Dictionary:
	var b: Dictionary = BIOMES.get(id, {})
	if b.is_empty():
		return {}
	return {"allowed": {
		"flora": (b.get("flora", []) as Array).duplicate(),
		"enemies": (b.get("enemies", []) as Array).duplicate(),
		"structures": (b.get("structures", []) as Array).duplicate(),
	}}

## The rendered identity of a procedural stretch. Content limits answer WHAT can occur; this contract also
## answers what the place was built for, which surface language it uses, and which authored district landmark
## frames a compatible systemic node. It is plain data so the run can serialize and replay the same theme.
static func theme_contract_for(id: String, seed: int = 0) -> Dictionary:
	var biome: Dictionary = BIOMES.get(id, {})
	var theme: Dictionary = (biome.get("theme", {}) as Dictionary).duplicate(true)
	if theme.is_empty():
		return {}
	theme["contract_id"] = "main_game_area_theme_v1"
	theme["id"] = id
	theme["display_name"] = display_name(id)
	var landmarks: Array = theme.get("landmarks", [])
	if landmarks.size() > 1:
		var rotated: Array = []
		var start := posmod(int(hash("theme-landmarks:%s:%d" % [id, seed])), landmarks.size())
		for i in range(landmarks.size()):
			rotated.append((landmarks[(start + i) % landmarks.size()] as Dictionary).duplicate(true))
		theme["landmarks"] = rotated
	return theme

static func validate() -> Dictionary:
	var errors: Array[String] = []
	for id_v in biome_ids():
		var id := str(id_v)
		var theme := theme_contract_for(id)
		if theme.is_empty():
			errors.append("Biome '%s' has no area theme" % id)
			continue
		for field in ["source_area", "floor_tile", "risk_tile"]:
			if str(theme.get(field, "")).strip_edges() == "":
				errors.append("Biome '%s' theme is missing %s" % [id, field])
		for tile_field in ["floor_tile", "risk_tile"]:
			var tile_path := "res://resources/models/elevator/tiles/%s.png" % str(theme.get(tile_field, ""))
			if not ResourceLoader.exists(tile_path):
				errors.append("Biome '%s' references missing %s" % [id, tile_path])
		if (theme.get("building_vocabulary", []) as Array).is_empty() \
				or (theme.get("feature_vocabulary", []) as Array).is_empty():
			errors.append("Biome '%s' needs both building and feature vocabulary" % id)
		for landmark_v in theme.get("landmarks", []):
			if not (landmark_v is Dictionary):
				errors.append("Biome '%s' has a malformed landmark" % id)
				continue
			var landmark := landmark_v as Dictionary
			var scene_path := str(landmark.get("scene", ""))
			if scene_path == "" or not ResourceLoader.exists(scene_path):
				errors.append("Biome '%s' landmark scene is missing: %s" % [id, scene_path])
			_validate_editable_assets(id, "landmark", landmark, errors)
			if (landmark.get("anchor_structures", []) as Array).is_empty():
				errors.append("Biome '%s' landmark has no systemic anchor structures" % id)
			if str(landmark.get("primary_read", "")).strip_edges() == "" \
					or str(landmark.get("feedback_role", "")).strip_edges() == "":
				errors.append("Biome '%s' landmark lacks a readable causal/feedback role" % id)
		for setpiece_v in theme.get("route_setpieces", []):
			if not (setpiece_v is Dictionary):
				errors.append("Biome '%s' has a malformed route setpiece" % id)
				continue
			var setpiece := setpiece_v as Dictionary
			var setpiece_scene := str(setpiece.get("scene", ""))
			if setpiece_scene == "" or not ResourceLoader.exists(setpiece_scene):
				errors.append("Biome '%s' route setpiece scene is missing: %s" % [id, setpiece_scene])
			_validate_editable_assets(id, "route setpiece", setpiece, errors)
			for causal_field in ["primary_read", "leverage", "failure_prediction"]:
				if str(setpiece.get(causal_field, "")).strip_edges() == "":
					errors.append("Biome '%s' route setpiece lacks %s" % [id, causal_field])
	return {"valid": errors.is_empty(), "errors": errors, "theme_count": BIOMES.size()}


static func _validate_editable_assets(
		biome_id: String,
		role: String,
		definition: Dictionary,
		errors: Array[String]
) -> void:
	if str(definition.get("asset_contract", "")) != "editable_3d_v1":
		return
	var assets := definition.get("editable_assets", []) as Array
	if assets.is_empty():
		errors.append("Biome '%s' %s declares editable_3d_v1 without source assets" % [biome_id, role])
		return
	for asset_v in assets:
		var asset_path := str(asset_v)
		var extension := asset_path.get_extension().to_lower()
		if extension not in ["obj", "gltf", "glb", "bbmodel"]:
			errors.append("Biome '%s' %s has a non-portable editable asset: %s" % [biome_id, role, asset_path])
			continue
		if not FileAccess.file_exists(asset_path) or not ResourceLoader.exists(asset_path):
			errors.append("Biome '%s' %s editable asset is missing or cannot import: %s" % [biome_id, role, asset_path])
			continue
		if extension == "obj":
			var base_path := asset_path.trim_suffix(".obj")
			for sidecar in [base_path + ".mtl", base_path + ".png"]:
				if not FileAccess.file_exists(sidecar):
					errors.append("Biome '%s' %s OBJ is missing its paintable sidecar: %s" % [biome_id, role, sidecar])

## Pick a biome deterministically from an arbitrary string key (the roguelike keys on run-seed/depth/branch so a
## descent rotates biomes and two forks can lead to different regions).
static func for_key(key: String) -> String:
	var ids: Array = biome_ids()
	if ids.is_empty():
		return ""
	# Keep the established branch-to-biome deal stable; run depth sequencing is handled separately below.
	return str(ids[abs(int(hash("biome:" + key))) % ids.size()])

## Pick a biome for a run DEPTH deterministically. A seeded offset and direction walk the explicit
## registry before repeating, so adjacent procedural stretches never silently reuse the same district identity.
static func for_depth(seed: int, depth: int) -> String:
	var ids := biome_ids()
	if ids.is_empty():
		return ""
	var start := posmod(int(hash("biome-sequence:%d" % seed)), ids.size())
	var direction := 1 if posmod(int(hash("biome-direction:%d" % seed)), 2) == 0 else -1
	return str(ids[posmod(start + depth * direction, ids.size())])
