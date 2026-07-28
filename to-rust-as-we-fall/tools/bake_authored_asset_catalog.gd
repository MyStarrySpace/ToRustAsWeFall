extends SceneTree

## Deterministically exports tooling-only construction scenes into portable, UV-mapped model kits.
## Runtime scenes must reference the resulting OBJ/MTL/PNG files and never these bake sources.
##
##   ..\Godot_v4.7-stable_win64_console.exe --headless --path . \
##     --script tools/bake_authored_asset_catalog.gd

const OUTPUT_ROOT := "res://resources/models"

const EXPORTS := [
	# Procedural-stretch biome landmarks. The exported groups are material families so every
	# landmark remains straightforward to retexture in Blockbench or another DCC editor.
	{"source": "res://tools/asset_sources/biome_landmarks_source.tscn", "folder": "generated-biomes/channels_pump_house", "file": "channels_pump_house_structure", "names": ["ChannelsPumpDrum", "ChannelsServiceWing"], "base": Color(0.16, 0.27, 0.26), "grime": Color(0.055, 0.09, 0.085), "wear": Color(0.34, 0.46, 0.44), "px_per_m": 20},
	{"source": "res://tools/asset_sources/biome_landmarks_source.tscn", "folder": "generated-biomes/channels_pump_house", "file": "channels_pump_house_fixtures", "names": ["ChannelsPumpCap", "ChannelsRiser", "ChannelsOpenTrough", "ChannelsValveLeft", "ChannelsValveRight"], "base": Color(0.31, 0.13, 0.065), "grime": Color(0.10, 0.035, 0.018), "wear": Color(0.56, 0.25, 0.11), "px_per_m": 20},
	{"source": "res://tools/asset_sources/biome_landmarks_source.tscn", "folder": "generated-biomes/channels_pump_house", "file": "channels_pump_house_flow", "names": ["ChannelsFlowStrip"], "base": Color(0.08, 0.42, 0.27), "grime": Color(0.02, 0.13, 0.075), "wear": Color(0.22, 0.92, 0.50)},
	{"source": "res://tools/asset_sources/biome_landmarks_source.tscn", "folder": "generated-biomes/stacks_archive_spire", "file": "stacks_archive_spire_structure", "names": ["StacksTallStack", "StacksMidStack", "StacksRearStack", "StacksScanPostLeft", "StacksScanPostRight"], "base": Color(0.20, 0.25, 0.28), "grime": Color(0.065, 0.08, 0.09), "wear": Color(0.42, 0.50, 0.54), "px_per_m": 20},
	{"source": "res://tools/asset_sources/biome_landmarks_source.tscn", "folder": "generated-biomes/stacks_archive_spire", "file": "stacks_archive_spire_drawers", "names": ["StacksDrawerBandA", "StacksDrawerBandB", "StacksDrawerBandC", "StacksDrawerBandD"], "base": Color(0.35, 0.24, 0.17), "grime": Color(0.12, 0.075, 0.045), "wear": Color(0.58, 0.43, 0.30)},
	{"source": "res://tools/asset_sources/biome_landmarks_source.tscn", "folder": "generated-biomes/stacks_archive_spire", "file": "stacks_archive_spire_scan", "names": ["StacksScanBeam"], "base": Color(0.18, 0.50, 0.70), "grime": Color(0.04, 0.16, 0.24), "wear": Color(0.45, 0.86, 1.0)},
	{"source": "res://tools/asset_sources/biome_landmarks_source.tscn", "folder": "generated-biomes/stacks_archive_spire", "file": "stacks_archive_spire_terminal", "names": ["StacksTerminalKiosk"], "base": Color(0.08, 0.36, 0.19), "grime": Color(0.02, 0.12, 0.05), "wear": Color(0.36, 0.91, 0.50)},
	{"source": "res://tools/asset_sources/biome_landmarks_source.tscn", "folder": "generated-biomes/garden_root_pavilion", "file": "garden_root_pavilion_structure", "names": ["GardenTerrace", "GardenColumnNW", "GardenColumnNE", "GardenColumnSW", "GardenColumnSE", "GardenCanopy"], "base": Color(0.29, 0.38, 0.30), "grime": Color(0.09, 0.13, 0.09), "wear": Color(0.52, 0.63, 0.52), "px_per_m": 20},
	{"source": "res://tools/asset_sources/biome_landmarks_source.tscn", "folder": "generated-biomes/garden_root_pavilion", "file": "garden_root_pavilion_roots", "names": ["GardenRootTrellisLeft", "GardenRootTrellisRight"], "base": Color(0.24, 0.15, 0.085), "grime": Color(0.08, 0.045, 0.022), "wear": Color(0.43, 0.29, 0.15)},
	{"source": "res://tools/asset_sources/biome_landmarks_source.tscn", "folder": "generated-biomes/garden_root_pavilion", "file": "garden_root_pavilion_foliage", "names": ["GardenFoliageLeft", "GardenFoliageRight"], "base": Color(0.20, 0.42, 0.22), "grime": Color(0.05, 0.14, 0.055), "wear": Color(0.38, 0.66, 0.39)},
	{"source": "res://tools/asset_sources/biome_landmarks_source.tscn", "folder": "generated-biomes/garden_root_pavilion", "file": "garden_root_pavilion_tended_nodes", "names": ["GardenTendedNodeLeft", "GardenTendedNodeRight"], "base": Color(0.08, 0.38, 0.29), "grime": Color(0.02, 0.12, 0.085), "wear": Color(0.20, 0.86, 0.58)},
	{"source": "res://tools/asset_sources/biome_landmarks_source.tscn", "folder": "generated-biomes/deadzone_chembrane_ruin", "file": "deadzone_chembrane_ruin_structure", "names": ["DeadzonePylonLeft", "DeadzonePylonRight", "DeadzoneCollapsedHeader", "DeadzoneFailedRelay"], "base": Color(0.21, 0.17, 0.16), "grime": Color(0.065, 0.045, 0.04), "wear": Color(0.42, 0.34, 0.30), "px_per_m": 20},
	{"source": "res://tools/asset_sources/biome_landmarks_source.tscn", "folder": "generated-biomes/deadzone_chembrane_ruin", "file": "deadzone_chembrane_ruin_chembrane", "names": ["DeadzoneChembraneLeft", "DeadzoneChembraneRight"], "base": Color(0.28, 0.22, 0.25), "grime": Color(0.09, 0.065, 0.075), "wear": Color(0.48, 0.39, 0.43)},
	{"source": "res://tools/asset_sources/biome_landmarks_source.tscn", "folder": "generated-biomes/deadzone_chembrane_ruin", "file": "deadzone_chembrane_ruin_roots", "names": ["DeadzoneDeadRootLeft", "DeadzoneDeadRootRight"], "base": Color(0.13, 0.095, 0.075), "grime": Color(0.04, 0.027, 0.018), "wear": Color(0.30, 0.22, 0.16)},
	{"source": "res://tools/asset_sources/biome_landmarks_source.tscn", "folder": "generated-biomes/deadzone_chembrane_ruin", "file": "deadzone_chembrane_ruin_warning", "names": ["DeadzoneWarningBeacon"], "base": Color(0.32, 0.075, 0.045), "grime": Color(0.11, 0.015, 0.008), "wear": Color(0.78, 0.15, 0.08)},
	# Peris's room: every visible gameplay prop that used to be assembled in peris_sim_sequence.gd.
	{"source": "res://tools/asset_sources/peris_room_props_source.tscn", "folder": "peris-sim/props/watering_can", "file": "watering_can", "names": ["WateringCanBody", "WateringCanSpout"], "base": Color(0.45, 0.55, 0.60), "grime": Color(0.18, 0.22, 0.24), "wear": Color(0.72, 0.80, 0.82)},
	{"source": "res://tools/asset_sources/peris_room_props_source.tscn", "folder": "peris-sim/props/wellness_terminal", "file": "wellness_terminal_housing", "names": ["WellnessHousing"], "base": Color(0.20, 0.23, 0.30), "grime": Color(0.08, 0.09, 0.12), "wear": Color(0.42, 0.46, 0.56)},
	{"source": "res://tools/asset_sources/peris_room_props_source.tscn", "folder": "peris-sim/props/wellness_terminal", "file": "wellness_terminal_display", "names": ["WellnessDisplay"], "base": Color(0.35, 0.48, 0.62), "grime": Color(0.10, 0.16, 0.23), "wear": Color(0.58, 0.72, 0.86)},
	{"source": "res://tools/asset_sources/peris_room_props_source.tscn", "folder": "peris-sim/props/strike_notice", "file": "strike_notice_card", "names": ["StrikeCard"], "base": Color(0.85, 0.80, 0.68), "grime": Color(0.35, 0.31, 0.25), "wear": Color(0.96, 0.93, 0.84)},
	{"source": "res://tools/asset_sources/peris_room_props_source.tscn", "folder": "peris-sim/props/strike_notice", "file": "strike_notice_warning", "names": ["StrikeWarningStrip"], "base": Color(0.50, 0.20, 0.20), "grime": Color(0.18, 0.05, 0.05), "wear": Color(0.76, 0.35, 0.30)},
	{"source": "res://tools/asset_sources/peris_room_props_source.tscn", "folder": "peris-sim/props/logbook_console", "file": "logbook_console_housing", "names": ["LogbookHousing"], "base": Color(0.20, 0.22, 0.25), "grime": Color(0.07, 0.08, 0.10), "wear": Color(0.42, 0.45, 0.48)},
	{"source": "res://tools/asset_sources/peris_room_props_source.tscn", "folder": "peris-sim/props/logbook_console", "file": "logbook_console_display", "names": ["LogbookDisplay"], "base": Color(0.75, 0.55, 0.35), "grime": Color(0.27, 0.16, 0.08), "wear": Color(0.95, 0.78, 0.50)},
	{"source": "res://tools/asset_sources/peris_room_props_source.tscn", "folder": "peris-sim/props/care_field_kit", "file": "care_field_kit_case", "names": ["CareKitCase"], "base": Color(0.32, 0.42, 0.31), "grime": Color(0.12, 0.17, 0.12), "wear": Color(0.55, 0.66, 0.52)},
	{"source": "res://tools/asset_sources/peris_room_props_source.tscn", "folder": "peris-sim/props/care_field_kit", "file": "care_field_kit_clasp", "names": ["CareKitClasp"], "base": Color(0.78, 0.58, 0.24), "grime": Color(0.30, 0.19, 0.05), "wear": Color(0.98, 0.82, 0.42)},
	{"source": "res://tools/asset_sources/peris_room_props_source.tscn", "folder": "peris-sim/props/plant_table", "file": "plant_table", "names": ["PlantTableTop", "PlantTableLegNW", "PlantTableLegNE", "PlantTableLegSW", "PlantTableLegSE"], "base": Color(0.34, 0.23, 0.18), "grime": Color(0.12, 0.07, 0.05), "wear": Color(0.58, 0.42, 0.30)},
	{"source": "res://tools/asset_sources/peris_room_props_source.tscn", "folder": "peris-sim/portal_room", "file": "monos_portal_room_shell", "names": ["PortalRoomFloor", "PortalRoomBackWall", "PortalRoomSideWall"], "base": Color(0.15, 0.14, 0.18), "grime": Color(0.045, 0.04, 0.06), "wear": Color(0.30, 0.28, 0.35), "px_per_m": 16},
	{"source": "res://tools/asset_sources/peris_room_props_source.tscn", "folder": "peris-sim/portal_room", "file": "monos_portal_figure", "names": ["MonosPortalBody", "MonosPortalHead"], "base": Color(0.63, 0.53, 0.38), "grime": Color(0.26, 0.20, 0.12), "wear": Color(0.82, 0.72, 0.54)},
	# Mother Flure mechanisms. Their construction scene is tooling-only; the runtime chunk
	# instantiates the portable wrappers so portal, carried gear, and lifting membrane keep
	# unmistakable physical identities while their live state stays authoritative elsewhere.
	{"source": "res://tools/asset_sources/mother_flure_mechanisms_source.tscn", "folder": "mother-flure/portal_frame", "file": "portal_frame", "names": ["PortalOuterRing", "PortalInnerRing", "PortalFoot", "PortalCoilLeft", "PortalCoilRight", "PortalCableLeft", "PortalCableRight"], "base": Color(0.19, 0.18, 0.16), "grime": Color(0.055, 0.045, 0.035), "wear": Color(0.66, 0.47, 0.24), "px_per_m": 40},
	{"source": "res://tools/asset_sources/mother_flure_mechanisms_source.tscn", "folder": "mother-flure/mother_gear", "file": "mother_gear", "names": ["GearRing", "GearHub", "GearSpoke0", "GearSpoke1", "GearSpoke2", "GearSpoke3", "GearSpoke4", "GearSpoke5", "GearSpoke6", "GearSpoke7", "GearTooth0", "GearTooth1", "GearTooth2", "GearTooth3", "GearTooth4", "GearTooth5", "GearTooth6", "GearTooth7", "GearTooth8", "GearTooth9", "GearTooth10", "GearTooth11", "GearGripLeft", "GearGripRight"], "base": Color(0.49, 0.34, 0.16), "grime": Color(0.10, 0.065, 0.025), "wear": Color(0.90, 0.72, 0.38), "px_per_m": 48},
	{"source": "res://tools/asset_sources/mother_flure_mechanisms_source.tscn", "folder": "mother-flure/rings_membrane", "file": "rings_membrane", "names": ["MembraneVane0", "MembraneVane1", "MembraneVane2", "MembraneVane3", "MembraneVane4", "MembraneVane5", "MembraneVane6", "MembraneVane7", "MembraneTendon", "MembraneAnchorLeft", "MembraneAnchorCenter", "MembraneAnchorRight"], "base": Color(0.15, 0.25, 0.17), "grime": Color(0.035, 0.075, 0.045), "wear": Color(0.48, 0.84, 0.56), "px_per_m": 40},
]


func _init() -> void:
	var baker = load("res://scripts/generation/uv_atlas_baker.gd")
	var instances := {}
	var failed := false
	var family_filter := OS.get_environment("ASSET_FAMILY").strip_edges()
	for raw_spec in EXPORTS:
		var spec := raw_spec as Dictionary
		if family_filter != "" and not str(spec["folder"]).begins_with(family_filter):
			continue
		var source_path := str(spec["source"])
		if not instances.has(source_path):
			var packed := load(source_path) as PackedScene
			if packed == null:
				push_error("[ASSET CATALOG] Cannot load bake source %s" % source_path)
				failed = true
				continue
			instances[source_path] = packed.instantiate()
		var source := instances.get(source_path) as Node3D
		if source == null:
			failed = true
			continue
		var mesh := _combine_named_meshes(source, spec["names"] as Array)
		if mesh == null or mesh.get_surface_count() == 0:
			push_error("[ASSET CATALOG] No geometry selected for %s" % str(spec["file"]))
			failed = true
			continue
		var baked: Dictionary = baker.bake(mesh, {
			"base_color": spec["base"],
			"grime_color": spec["grime"],
			"wear_color": spec["wear"],
			"px_per_m": int(spec.get("px_per_m", 32)),
		})
		if baked.is_empty():
			failed = true
			continue
		var output_dir := OUTPUT_ROOT.path_join(str(spec["folder"]))
		var absolute_dir := ProjectSettings.globalize_path(output_dir)
		if DirAccess.make_dir_recursive_absolute(absolute_dir) != OK:
			push_error("[ASSET CATALOG] Cannot create %s" % absolute_dir)
			failed = true
			continue
		var path_base := absolute_dir.path_join(str(spec["file"]))
		if not baker.export_obj(baked, path_base):
			failed = true
			continue
		print("[ASSET CATALOG] %s.obj (islands=%d, atlas=%dx%d)" % [
			path_base, int(baked["islands"]),
			(baked["image"] as Image).get_width(), (baked["image"] as Image).get_height(),
		])
	for value in instances.values():
		(value as Node).free()
	quit(1 if failed else 0)


func _combine_named_meshes(root: Node3D, names: Array) -> ArrayMesh:
	var selected := {}
	for value in names:
		selected[str(value)] = true
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_selected(root, Transform3D.IDENTITY, selected, tool, true)
	return tool.commit()


func _append_selected(
		node: Node,
		parent_transform: Transform3D,
		selected: Dictionary,
		tool: SurfaceTool,
		is_root: bool = false
) -> void:
	var current := parent_transform
	if node is Node3D and not is_root:
		current = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and selected.has(node.name):
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for surface in range(mesh.get_surface_count()):
				tool.append_from(mesh, surface, current)
	for child in node.get_children():
		_append_selected(child, current, selected, tool)
