class_name StacksOpenFilesLayout
extends RefCounted

## Authored spatial contract for The Open Files Initiative.
##
## This file owns immutable measurements and causal relationships. Runtime mechanisms own every
## mutable consequence: category selection, graded drawer motion, collision, rot failure, dynamic
## blockers, Sapscrap attraction, access state, and inter-level links. In particular, drawer cells
## are never permanent grid links; a solved drawer column commits and restores its own link.

const GRID_ORIGIN := Vector3(-4.0, 0.0, -24.0)
const GRID_CELL_SIZE := 1.0
const GRID_WIDTH := 188
const GRID_HEIGHT := 48
const GRID_LEVEL_COUNT := 3
const GRID_LEVEL_HEIGHT := 4.0

const LEVEL_ENTRY := 0
const LEVEL_TRANSFER := 1
const LEVEL_SHELTER := 2

const SPAWNS := {
	"aster": Vector3(5.0, 0.0, 0.0),
	"peris": Vector3(3.0, 0.0, 1.6),
	"endo": Vector3(3.0, 0.0, -1.6),
}

# Compatibility names consumed by the current chunk while its mechanisms migrate to the richer
# specs below.
const RECON_TERMINAL_POS := Vector3(15.5, 0.5, -5.0)
const SUPPORT_LOG_POS := Vector3(68.5, 4.5, 1.5)
const SPOOF_TERMINAL_POS := Vector3(78.5, 4.5, 12.0)
const MULE_TRAIL_POS := Vector3(106.0, 4.5, 20.0)
const MAINTAINED_WORKSPACE_POS := Vector3(93.5, 4.5, 20.0)
const GHOST_WORKSPACE_POS := Vector3(101.0, 4.5, 20.0)
const BRIDGE_TERMINAL_POS := Vector3(127.0, 8.5, 0.0)
const BRIDGE_START := Vector3(132.5, 8.12, 0.0)
const BRIDGE_END := Vector3(145.5, 8.12, 0.0)
const SHELTER_POS := Vector3(169.0, 8.5, 0.0)
const SHELTER_SIZE := Vector2(10.0, 8.0)

const PURGE_TERMINAL_POS := Vector3(109.5, 4.5, 11.5)
const IRON_FIXTURE_RETRACTED_POS := Vector3(131.0, 4.5, -10.5)
const IRON_FIXTURE_EXPOSED_POS := Vector3(126.5, 4.5, -10.5)
const EMP_CIRCUIT_POS := Vector3(124.5, 4.5, 3.5)

const CATEGORY_IDS := [
	"sensory",
	"motor",
	"memory",
	"affect",
	"language",
	"executive",
]

const CATEGORY_DEPTH_EXTENSIONS := {
	"sensory": 3.60,
	"motor": 2.50,
	"memory": 1.40,
	"affect": 3.60,
	"language": 2.50,
	"executive": 1.40,
}

const CATEGORY_SPECS := [
	{
		"id": "sensory",
		"label": "SENSORY",
		"depth": "deep",
		"extension": 3.60,
		"tint": Color(0.22, 0.78, 0.88),
	},
	{
		"id": "motor",
		"label": "MOTOR",
		"depth": "mid",
		"extension": 2.50,
		"tint": Color(0.30, 0.66, 0.78),
	},
	{
		"id": "memory",
		"label": "MEMORY",
		"depth": "shallow",
		"extension": 1.40,
		"tint": Color(0.40, 0.57, 0.70),
	},
	{
		"id": "affect",
		"label": "AFFECT",
		"depth": "deep",
		"extension": 3.60,
		"tint": Color(0.27, 0.76, 0.57),
	},
	{
		"id": "language",
		"label": "LANGUAGE",
		"depth": "mid",
		"extension": 2.50,
		"tint": Color(0.37, 0.65, 0.50),
	},
	{
		"id": "executive",
		"label": "EXECUTIVE",
		"depth": "shallow",
		"extension": 1.40,
		"tint": Color(0.48, 0.55, 0.45),
	},
]

const BAY_1_CATEGORY_LEVER_POSITIONS := {
	"sensory": Vector3(24.5, 0.9, 12.0),
	"motor": Vector3(28.5, 0.9, 12.0),
	"memory": Vector3(32.5, 0.9, 12.0),
	"affect": Vector3(36.5, 0.9, 12.0),
	"language": Vector3(40.5, 0.9, 12.0),
	"executive": Vector3(44.5, 0.9, 12.0),
}

const BAY_2_CATEGORY_LEVER_POSITIONS := {
	"sensory": Vector3(89.5, 4.9, 11.5),
	"motor": Vector3(93.5, 4.9, 11.5),
	"memory": Vector3(97.5, 4.9, 11.5),
	"affect": Vector3(101.5, 4.9, 11.5),
	"language": Vector3(105.5, 4.9, 11.5),
	"executive": Vector3(109.5, 4.9, 11.5),
}

const LEVEL_REGION_SPECS := [
	# Entry and the pressure-free teaching bay.
	{"id": "entry_apron", "level": LEVEL_ENTRY, "min": [-3.0, -7.0], "max": [20.0, 7.0]},
	{"id": "drawer_bay_one", "level": LEVEL_ENTRY, "min": [16.0, -17.0], "max": [50.0, 17.0]},
	# The first drawer stair lands beside the mandatory support intake.
	{"id": "bay_one_landing", "level": LEVEL_TRANSFER, "min": [22.0, -11.0], "max": [50.0, -4.0]},
	{"id": "support_crosswalk", "level": LEVEL_TRANSFER, "min": [44.0, -6.0], "max": [83.0, 6.0]},
	{"id": "support_intake", "level": LEVEL_TRANSFER, "min": [62.0, -10.0], "max": [78.0, 6.0]},
	# The second bay is broad enough for drawer cover and Sapscrap routing decisions.
	{"id": "drawer_bay_two", "level": LEVEL_TRANSFER, "min": [82.0, -17.0], "max": [115.0, 14.0]},
	# Optional tracked-access spur; the main route never depends on this footprint.
	{"id": "spoof_vestibule", "level": LEVEL_TRANSFER, "min": [76.0, 10.0], "max": [82.0, 21.0]},
	{"id": "maintained_lane", "level": LEVEL_TRANSFER, "min": [80.0, 18.0], "max": [112.0, 22.0]},
	# The faulted circuit opens the north mouth of this short regroup loop.
	{"id": "emp_north_mouth", "level": LEVEL_TRANSFER, "min": [116.0, -12.0], "max": [120.0, -9.0]},
	{"id": "emp_side_passage", "level": LEVEL_TRANSFER, "min": [120.0, -13.0], "max": [130.0, 5.0]},
	{"id": "emp_south_mouth", "level": LEVEL_TRANSFER, "min": [116.0, 3.0], "max": [120.0, 5.0]},
	# The second stair reaches a short upper catwalk and then the shelter.
	{"id": "bay_two_landing", "level": LEVEL_SHELTER, "min": [88.0, -11.0], "max": [115.0, -4.0]},
	{"id": "upper_route_west", "level": LEVEL_SHELTER, "min": [106.0, -6.0], "max": [133.0, 6.0]},
	{"id": "upper_route_span", "level": LEVEL_SHELTER, "min": [133.0, -3.0], "max": [145.0, 3.0]},
	{"id": "upper_route_east", "level": LEVEL_SHELTER, "min": [145.0, -6.0], "max": [181.0, 6.0]},
	{"id": "shelter", "level": LEVEL_SHELTER, "min": [158.0, -10.0], "max": [181.0, 10.0]},
]

const SHELTER_REST_DIALOGUE_KEYS := [
	"stacks.rest.narration.open",
	"stacks.rest.narration.peris_quiet",
	"stacks.rest.peris.breath",
	"stacks.rest.peris.cant",
	"stacks.rest.peris.silence",
	"stacks.rest.peris.try_again",
	"stacks.rest.peris.scared",
	"stacks.rest.peris.ask",
	"stacks.rest.peris.wait_for_answer",
	"stacks.rest.aster.start",
	"stacks.rest.aster.models",
	"stacks.rest.aster.focus",
	"stacks.rest.aster.application",
	"stacks.rest.aster.peris",
	"stacks.rest.peris.listening",
	"stacks.rest.peris.huh",
	"stacks.rest.peris.focus",
	"stacks.rest.peris.breath_settles",
	"stacks.rest.aster.notice",
	"stacks.rest.peris.yeah",
	"stacks.rest.narration.close",
]


static func grid_data() -> Dictionary:
	var level_regions := _level_region_specs()
	var walkable_regions: Array[Dictionary] = []
	for region in level_regions:
		walkable_regions.append({
			"min": (region.get("min", []) as Array).duplicate(),
			"max": (region.get("max", []) as Array).duplicate(),
		})
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [GRID_ORIGIN.x, GRID_ORIGIN.y, GRID_ORIGIN.z],
		"cell_size": GRID_CELL_SIZE,
		"width": GRID_WIDTH,
		"height": GRID_HEIGHT,
		"level_count": GRID_LEVEL_COUNT,
		"level_height": GRID_LEVEL_HEIGHT,
		"walkable_regions": walkable_regions,
		"level_regions": level_regions,
		"level_cells": _level_cell_specs(),
		"wall_cells": _rack_wall_cells(),
		# Drawer-stair links are committed, removed, saved, and restored by their mechanisms.
		"links": [],
	}


static func category_specs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for category in CATEGORY_SPECS:
		result.append((category as Dictionary).duplicate(true))
	return result


static func drawer_bay_specs() -> Array[Dictionary]:
	return [
		_drawer_bay_one_spec(),
		_drawer_bay_two_spec(),
	]


static func drawer_bay_spec(bay_id: String) -> Dictionary:
	for bay in drawer_bay_specs():
		if str(bay.get("id", "")) == bay_id:
			return bay
	return {}


static func drawer_link_cells() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for bay in drawer_bay_specs():
		for column in bay.get("columns", []):
			result.append({
				"bay_id": bay.get("id", ""),
				"column_id": column.get("id", ""),
				"cell": (column.get("link_cell", []) as Array).duplicate(),
				"from_level": column.get("from_level", LEVEL_ENTRY),
				"to_level": column.get("to_level", LEVEL_TRANSFER),
			})
	return result


static func sapscrap_specs() -> Array[Dictionary]:
	return [
		{
			"id": "bay_two_sapscrap_west",
			"species_id": "sapscrap",
			"level": LEVEL_TRANSFER,
			"spawn_position": Vector3(88.5, 4.5, -2.5),
			"patrol_points": [
				Vector3(88.5, 4.5, -2.5),
				Vector3(96.5, 4.5, -5.5),
				Vector3(102.5, 4.5, 1.5),
				Vector3(92.5, 4.5, 5.5),
			],
			"pressure_role": "crossing_pressure",
			"speed_profile": "faster_than_walk_slower_than_run",
			"iron_fixture_id": "bay_two_sacrificial_iron",
		},
		{
			"id": "bay_two_sapscrap_east",
			"species_id": "sapscrap",
			"level": LEVEL_TRANSFER,
			"spawn_position": Vector3(109.5, 4.5, 4.5),
			"patrol_points": [
				Vector3(109.5, 4.5, 4.5),
				Vector3(113.0, 4.5, -3.5),
				Vector3(103.5, 4.5, -7.5),
				Vector3(99.0, 4.5, 4.5),
			],
			"pressure_role": "catalog_desk_pressure",
			"speed_profile": "faster_than_walk_slower_than_run",
			"iron_fixture_id": "bay_two_sacrificial_iron",
		},
	]


static func purge_spec() -> Dictionary:
	return {
		"id": "bay_two_iron_purge",
		"level": LEVEL_TRANSFER,
		"terminal_position": PURGE_TERMINAL_POS,
		"required_character": "aster",
		"contextual_action": "hack_purge",
		"fixture_id": "bay_two_sacrificial_iron",
		"fixture_retracted_position": IRON_FIXTURE_RETRACTED_POS,
		"fixture_exposed_position": IRON_FIXTURE_EXPOSED_POS,
		"fixture_size": Vector3(2.4, 1.8, 1.8),
		"fixture_travel": IRON_FIXTURE_EXPOSED_POS - IRON_FIXTURE_RETRACTED_POS,
		"attraction_position": IRON_FIXTURE_EXPOSED_POS,
		"iron_strength": 3.0,
		"initial_state": "retracted",
		"affected_sapscrap_ids": [
			"bay_two_sapscrap_west",
			"bay_two_sapscrap_east",
		],
		"data_link": {
			"from": PURGE_TERMINAL_POS,
			"to": IRON_FIXTURE_EXPOSED_POS,
			"register": "aster_data",
		},
		"tradeoff": {
			"clears_lane": "drawer_bay_two_west",
			"concentrates_at": "emp_side_passage_north",
		},
	}


static func emp_circuit_spec() -> Dictionary:
	return {
		"id": "bay_two_faulted_cutoff",
		"level": LEVEL_TRANSFER,
		"position": EMP_CIRCUIT_POS,
		"interaction_position": Vector3(123.0, 4.5, 3.5),
		"required_character": "aster",
		"required_ability": "emp",
		"target_kind": "electronic_circuit",
		"electronic": true,
		"initial_state": "faulted_closed",
		"commit_state": "power_cut_open",
		"affected_cells": _world_rect_cells(
			Vector2(116.0, -12.0),
			Vector2(116.0, -9.0)
		),
		"route_from": Vector3(114.5, 4.5, -10.0),
		"route_to": Vector3(121.5, 4.5, -10.0),
		"regroup_anchor": Vector3(125.0, 4.5, -3.5),
		"biological_targets_affected": false,
		"data_link": {
			"from": EMP_CIRCUIT_POS,
			"to": Vector3(116.5, 4.5, -10.0),
			"register": "aster_data",
		},
	}


static func optional_lane_spec() -> Dictionary:
	return {
		"id": "spoofed_maintained_lane",
		"level": LEVEL_TRANSFER,
		"terminal_position": SPOOF_TERMINAL_POS,
		"required_character": "aster",
		"required_ability": "spoof_location",
		"reported_location_target": "maintained_lane_tracker",
		"gate_cells": _world_rect_cells(Vector2(76.0, 15.0), Vector2(82.0, 17.0)),
		"entry_position": Vector3(80.0, 4.5, 14.0),
		"lane_position": MAINTAINED_WORKSPACE_POS,
		"optional": true,
		"main_route_dependency": false,
		"enemy_route_changes": false,
		"rejection_reason": "reported_location_mismatch",
	}


static func support_terminal_spec() -> Dictionary:
	return {
		"id": "mandatory_support_intake",
		"level": LEVEL_TRANSFER,
		"position": SUPPORT_LOG_POS,
		"mandatory": true,
		"route_role": "causal_record_and_party_thread",
		"dialogue_ranges": [
			{
				"from": "stacks.narration.network_address",
				"through": "stacks.peris.priorities",
			},
			{
				"from": "stacks.narration.cleaned_terminal",
				"through": "stacks.aster.expectation",
			},
		],
	}


static func narrative_landmark_specs() -> Array[Dictionary]:
	return [
		{
			"id": "arrival_cleaned_terminal",
			"level": LEVEL_ENTRY,
			"position": RECON_TERMINAL_POS,
			"mandatory": true,
			"role": "arrival_causal_framing",
			"dialogue_range": {
				"from": "stacks.narration.enter",
				"through": "stacks.aster.means",
			},
		},
		support_terminal_spec(),
		{
			"id": "instrumented_lane",
			"level": LEVEL_TRANSFER,
			"position": MAINTAINED_WORKSPACE_POS,
			"mandatory": false,
			"role": "anonymous_care_trace",
			"dialogue_range": {
				"from": "stacks.narration.instrumented_lane",
				"through": "stacks.aster.standardization",
			},
		},
		{
			"id": "ghost_workspace",
			"level": LEVEL_TRANSFER,
			"position": GHOST_WORKSPACE_POS,
			"mandatory": false,
			"role": "ghost_id_exemption_trace",
			"dialogue_range": {
				"from": "stacks.narration.workspace",
				"through": "stacks.aster.right",
			},
		},
		{
			"id": "mule_case_trail",
			"level": LEVEL_TRANSFER,
			"position": MULE_TRAIL_POS,
			"mandatory": false,
			"role": "sick_leave_and_incident_record_trail",
			"dialogue_pending": true,
		},
		{
			"id": "upper_shelter",
			"level": LEVEL_SHELTER,
			"position": SHELTER_POS,
			"size": SHELTER_SIZE,
			"mandatory": true,
			"role": "party_rest_release",
			"dialogue_keys": SHELTER_REST_DIALOGUE_KEYS.duplicate(),
		},
	]


static func floor_specs() -> Array[Dictionary]:
	return [
		{
			"name": "EntryApronFloor",
			"level": LEVEL_ENTRY,
			"position": Vector3(8.5, -0.05, 0.0),
			"size": Vector3(23.0, 0.1, 14.0),
		},
		{
			"name": "TeachingBayFloor",
			"level": LEVEL_ENTRY,
			"position": Vector3(33.0, -0.05, 0.0),
			"size": Vector3(34.0, 0.1, 34.0),
		},
		{
			"name": "TeachingBayLanding",
			"level": LEVEL_TRANSFER,
			"position": Vector3(36.0, 3.95, -7.5),
			"size": Vector3(28.0, 0.1, 7.0),
		},
		{
			"name": "SupportCrosswalk",
			"level": LEVEL_TRANSFER,
			"position": Vector3(63.5, 3.95, 0.0),
			"size": Vector3(39.0, 0.1, 12.0),
		},
		{
			"name": "TransferBayFloor",
			"level": LEVEL_TRANSFER,
			"position": Vector3(98.5, 3.95, -1.5),
			"size": Vector3(33.0, 0.1, 31.0),
		},
		{
			"name": "MaintainedLaneFloor",
			"level": LEVEL_TRANSFER,
			"position": Vector3(94.0, 3.95, 20.0),
			"size": Vector3(36.0, 0.1, 4.0),
		},
		{
			"name": "MaintainedLaneVestibule",
			"level": LEVEL_TRANSFER,
			"position": Vector3(79.0, 3.95, 15.5),
			"size": Vector3(6.0, 0.1, 11.0),
		},
		{
			"name": "EmpRegroupLoop",
			"level": LEVEL_TRANSFER,
			"position": Vector3(125.0, 3.95, -4.0),
			"size": Vector3(10.0, 0.1, 18.0),
		},
		{
			"name": "EmpNorthMouth",
			"level": LEVEL_TRANSFER,
			"position": Vector3(118.0, 3.95, -10.5),
			"size": Vector3(4.0, 0.1, 3.0),
		},
		{
			"name": "EmpSouthMouth",
			"level": LEVEL_TRANSFER,
			"position": Vector3(118.0, 3.95, 4.0),
			"size": Vector3(4.0, 0.1, 2.0),
		},
		{
			"name": "TransferBayLanding",
			"level": LEVEL_SHELTER,
			"position": Vector3(101.5, 7.95, -7.5),
			"size": Vector3(27.0, 0.1, 7.0),
		},
		{
			"name": "UpperRouteWest",
			"level": LEVEL_SHELTER,
			"position": Vector3(119.5, 7.95, 0.0),
			"size": Vector3(27.0, 0.1, 12.0),
		},
		{
			"name": "UpperConnector",
			"level": LEVEL_SHELTER,
			"position": Vector3(139.0, 7.95, 0.0),
			"size": Vector3(12.0, 0.1, 6.0),
		},
		{
			"name": "UpperRouteEast",
			"level": LEVEL_SHELTER,
			"position": Vector3(163.0, 7.95, 0.0),
			"size": Vector3(36.0, 0.1, 20.0),
		},
	]


static func blocker_specs() -> Array[Dictionary]:
	return [
		{
			"name": "TeachingBayArchiveBackstop",
			"level": LEVEL_ENTRY,
			"position": Vector3(33.5, 1.9, -15.0),
			"size": Vector3(29.0, 3.8, 4.0),
		},
		{
			"name": "TransferBayArchiveBackstop",
			"level": LEVEL_TRANSFER,
			"position": Vector3(100.0, 5.9, -15.0),
			"size": Vector3(28.0, 3.8, 4.0),
		},
		{
			"name": "MaintainedLaneCableCabinet",
			"level": LEVEL_TRANSFER,
			"position": Vector3(96.0, 5.6, 22.0),
			"size": Vector3(7.0, 3.2, 1.0),
		},
	]


static func spire_specs() -> Array[Dictionary]:
	return [
		{
			"name": "EntryIndexSpire",
			"position": Vector3(14.0, 0.0, 5.0),
			"scale": 1.10,
			"yaw": 90.0,
		},
		{
			"name": "TeachingBayIndexSpire",
			"position": Vector3(34.0, 0.0, -15.0),
			"scale": 1.45,
			"yaw": 0.0,
		},
		{
			"name": "SupportIndexSpire",
			"position": Vector3(67.0, 4.0, -5.0),
			"scale": 1.15,
			"yaw": 90.0,
		},
		{
			"name": "TransferBayIndexSpire",
			"position": Vector3(100.0, 4.0, -15.0),
			"scale": 1.55,
			"yaw": 0.0,
		},
		{
			"name": "MaintainedIndexSpire",
			"position": Vector3(94.0, 4.0, 20.0),
			"scale": 1.20,
			"yaw": 180.0,
		},
		{
			"name": "ShelterIndexSpire",
			"position": Vector3(163.0, 8.0, -6.5),
			"scale": 1.25,
			"yaw": -90.0,
		},
	]


static func light_specs() -> Array[Dictionary]:
	return [
		{
			"position": Vector3(13.0, 3.8, 0.0),
			"color": Color(0.18, 0.31, 0.35),
			"energy": 1.10,
			"range": 16.0,
		},
		{
			"position": Vector3(34.0, 3.8, -6.0),
			"color": Color(0.22, 0.70, 0.82),
			"energy": 1.45,
			"range": 15.0,
		},
		{
			"position": Vector3(34.0, 3.8, 12.0),
			"color": Color(0.24, 0.56, 0.50),
			"energy": 1.25,
			"range": 13.0,
		},
		{
			"position": Vector3(68.0, 7.8, 0.0),
			"color": Color(0.25, 0.63, 0.60),
			"energy": 1.35,
			"range": 15.0,
		},
		{
			"position": Vector3(99.0, 7.8, -4.0),
			"color": Color(0.19, 0.48, 0.54),
			"energy": 1.30,
			"range": 16.0,
		},
		{
			"position": Vector3(109.0, 7.8, 11.0),
			"color": Color(0.86, 0.43, 0.20),
			"energy": 1.65,
			"range": 12.0,
		},
		{
			"position": Vector3(94.0, 7.2, 20.0),
			"color": Color(0.84, 0.58, 0.29),
			"energy": 1.65,
			"range": 13.0,
		},
		{
			"position": Vector3(126.0, 7.7, -7.0),
			"color": Color(0.30, 0.72, 0.88),
			"energy": 1.45,
			"range": 11.0,
		},
		{
			"position": Vector3(125.0, 11.8, 0.0),
			"color": Color(0.24, 0.56, 0.58),
			"energy": 1.35,
			"range": 16.0,
		},
		{
			"position": Vector3(169.0, 11.4, 0.0),
			"color": Color(0.92, 0.67, 0.34),
			"energy": 2.20,
			"range": 16.0,
		},
	]


# Compatibility patrols remain finite for the existing chunk. Canonical Sapscrap routing is exposed
# by sapscrap_specs(); the location-spoof path intentionally does not encode an enemy reroute.
static func primary_patrol() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for point in sapscrap_specs()[0].get("patrol_points", []):
		points.append(point)
	return points


static func spoof_patrol() -> Array[Vector3]:
	return primary_patrol()


static func bridge_sentry_patrol() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for point in sapscrap_specs()[1].get("patrol_points", []):
		points.append(point)
	return points


static func level_floor_y(level: int) -> float:
	return float(level) * GRID_LEVEL_HEIGHT


static func level_actor_y(level: int) -> float:
	return level_floor_y(level) + 0.5


static func world_to_cell(world_position: Vector3) -> Vector2i:
	return Vector2i(
		floori((world_position.x - GRID_ORIGIN.x) / GRID_CELL_SIZE),
		floori((world_position.z - GRID_ORIGIN.z) / GRID_CELL_SIZE)
	)


static func world_to_cell_array(world_position: Vector3) -> Array:
	var cell := world_to_cell(world_position)
	return [cell.x, cell.y]


static func _drawer_bay_one_spec() -> Dictionary:
	return {
		"id": "drawer_bay_one",
		"label": "INDEX LESSON",
		"role": "safe_teach",
		"pressure_profile": "inspection_only",
		"from_level": LEVEL_ENTRY,
		"to_level": LEVEL_TRANSFER,
		"stack_face_z": -12.5,
		"catalog_desk_position": Vector3(34.5, 0.5, 12.0),
		"control_positions": BAY_1_CATEGORY_LEVER_POSITIONS.duplicate(true),
		"categories": category_specs(),
		"columns": [
			_drawer_column_spec(
				"bay_one_column_a",
				"drawer_bay_one",
				25.5,
				-12.5,
				LEVEL_ENTRY,
				LEVEL_TRANSFER,
				["sensory", "motor", "memory"],
				[]
			),
			_drawer_column_spec(
				"bay_one_column_b",
				"drawer_bay_one",
				33.5,
				-12.5,
				LEVEL_ENTRY,
				LEVEL_TRANSFER,
				["affect", "language", "executive"],
				["language"]
			),
			_drawer_column_spec(
				"bay_one_column_c",
				"drawer_bay_one",
				41.5,
				-12.5,
				LEVEL_ENTRY,
				LEVEL_TRANSFER,
				["executive", "sensory", "motor"],
				[]
			),
		],
		"solution_categories": ["sensory", "motor", "memory"],
		"aster_inspection_positions": [
			Vector3(25.5, 0.5, -7.5),
			Vector3(33.5, 0.5, -7.5),
			Vector3(41.5, 0.5, -7.5),
		],
		"peris_inspection_positions": [
			Vector3(25.5, 0.5, -9.0),
			Vector3(33.5, 0.5, -9.0),
			Vector3(41.5, 0.5, -9.0),
		],
		"nearby_useful_wrong_category": "affect",
		"wrong_activation_use": "drawer_cover",
		"runtime_link_contract": "drawer_stair_committed_link/v1",
	}


static func _drawer_bay_two_spec() -> Dictionary:
	return {
		"id": "drawer_bay_two",
		"label": "INDEX TRANSFER",
		"role": "transfer_under_pressure",
		"pressure_profile": "sapscrap_routing",
		"from_level": LEVEL_TRANSFER,
		"to_level": LEVEL_SHELTER,
		"stack_face_z": -12.5,
		"catalog_desk_position": Vector3(99.5, 4.5, 11.5),
		"control_positions": BAY_2_CATEGORY_LEVER_POSITIONS.duplicate(true),
		"categories": category_specs(),
		"columns": [
			_drawer_column_spec(
				"bay_two_column_a",
				"drawer_bay_two",
				91.5,
				-12.5,
				LEVEL_TRANSFER,
				LEVEL_SHELTER,
				["sensory", "motor", "memory"],
				["motor"]
			),
			_drawer_column_spec(
				"bay_two_column_b",
				"drawer_bay_two",
				99.5,
				-12.5,
				LEVEL_TRANSFER,
				LEVEL_SHELTER,
				["affect", "language", "executive"],
				[]
			),
			_drawer_column_spec(
				"bay_two_column_c",
				"drawer_bay_two",
				107.5,
				-12.5,
				LEVEL_TRANSFER,
				LEVEL_SHELTER,
				["memory", "affect", "sensory"],
				["affect"]
			),
		],
		"solution_categories": ["affect", "language", "executive"],
		"aster_inspection_positions": [
			Vector3(91.5, 4.5, -7.5),
			Vector3(99.5, 4.5, -7.5),
			Vector3(107.5, 4.5, -7.5),
		],
		"peris_inspection_positions": [
			Vector3(91.5, 4.5, -9.0),
			Vector3(99.5, 4.5, -9.0),
			Vector3(107.5, 4.5, -9.0),
		],
		"nearby_useful_wrong_category": "sensory",
		"wrong_activation_use": "drawer_cover_and_iron_exposure",
		"runtime_link_contract": "drawer_stair_committed_link/v1",
	}


static func _drawer_column_spec(
	column_id: String,
	bay_id: String,
	column_x: float,
	stack_face_z: float,
	from_level: int,
	to_level: int,
	assignments: Array,
	rotten_categories: Array
) -> Dictionary:
	var modules: Array[Dictionary] = []
	for height in range(assignments.size()):
		var category_id := str(assignments[height])
		modules.append(_drawer_module_spec(
			bay_id,
			column_id,
			column_x,
			stack_face_z,
			from_level,
			height,
			category_id,
			category_id in rotten_categories
		))
	var link_world := Vector3(
		column_x,
		level_floor_y(from_level),
		stack_face_z + 1.5
	)
	return {
		"id": column_id,
		"bay_id": bay_id,
		"column": column_id,
		"link_cell": world_to_cell_array(link_world),
		"link_cell_space": "grid_local",
		"link_world_position": link_world,
		"from_level": from_level,
		"to_level": to_level,
		"rotten_categories": rotten_categories.duplicate(),
		"modules": modules,
		"top_landing_position": Vector3(
			column_x,
			level_floor_y(to_level),
			stack_face_z + 1.5
		),
	}


static func _drawer_module_spec(
	bay_id: String,
	column_id: String,
	column_x: float,
	stack_face_z: float,
	from_level: int,
	height: int,
	category_id: String,
	rotten: bool
) -> Dictionary:
	var category := _category_spec(category_id)
	var extension := float(category.get("extension", 0.0))
	var body_size := Vector3(3.4, 0.68, extension + 0.75)
	var floor_y := level_floor_y(from_level)
	var wall_face_position := Vector3(
		column_x,
		floor_y + 0.55 + float(height) * 1.20,
		stack_face_z
	)
	var closed_position := wall_face_position - Vector3.BACK * body_size.z * 0.5
	var extended_position := closed_position + Vector3.BACK * extension
	return {
		"id": "%s_%s_h%d" % [column_id, category_id, height],
		"bay_id": bay_id,
		"column": column_id,
		"category": category_id,
		"depth": category.get("depth", ""),
		"height": height,
		"height_meters": wall_face_position.y - floor_y,
		"wall_face_position": wall_face_position,
		"closed_position": closed_position,
		"extended_position": extended_position,
		"extension": extension,
		"extension_direction": Vector3.BACK,
		"visual_scale": body_size,
		"collision_size": body_size,
		"tag_plate_position": wall_face_position + Vector3.BACK * 0.08,
		"tint": category.get("tint", Color.WHITE),
		"rotten": rotten,
		"iron_exposure_strength": 0.45 if bay_id == "drawer_bay_two" else 0.0,
		"attracts_sapscraps_when_extended": bay_id == "drawer_bay_two",
	}


static func _category_spec(category_id: String) -> Dictionary:
	for category in CATEGORY_SPECS:
		if str((category as Dictionary).get("id", "")) == category_id:
			return (category as Dictionary).duplicate(true)
	return {}


static func _level_region_specs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for region in LEVEL_REGION_SPECS:
		result.append((region as Dictionary).duplicate(true))
	return result


static func _level_cell_specs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for level in range(GRID_LEVEL_COUNT):
		result.append({
			"level": level,
			"cells": _cells_for_level(level),
		})
	return result


static func _cells_for_level(level: int) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	var walls: Dictionary = {}
	for raw_cell in _rack_wall_cells():
		var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
		walls[cell] = true
	for region in LEVEL_REGION_SPECS:
		if int((region as Dictionary).get("level", -1)) != level:
			continue
		var min_raw := (region as Dictionary).get("min", [0.0, 0.0]) as Array
		var max_raw := (region as Dictionary).get("max", [0.0, 0.0]) as Array
		var min_cell := world_to_cell(Vector3(float(min_raw[0]), 0.0, float(min_raw[1])))
		var max_cell := world_to_cell(Vector3(float(max_raw[0]), 0.0, float(max_raw[1])))
		for cell_z in range(min_cell.y, max_cell.y + 1):
			for cell_x in range(min_cell.x, max_cell.x + 1):
				var cell := Vector2i(cell_x, cell_z)
				if not seen.has(cell) and not walls.has(cell):
					seen[cell] = true
					result.append([cell.x, cell.y])
	return result


static func _world_rect_cells(min_world: Vector2, max_world: Vector2) -> Array:
	var result: Array = []
	var min_cell := world_to_cell(Vector3(min_world.x, 0.0, min_world.y))
	var max_cell := world_to_cell(Vector3(max_world.x, 0.0, max_world.y))
	for cell_z in range(min_cell.y, max_cell.y + 1):
		for cell_x in range(min_cell.x, max_cell.x + 1):
			result.append([cell_x, cell_z])
	return result


static func _rack_wall_cells() -> Array:
	var cells: Array = []
	for bounds in [
		[19, 48, -17, -13],
		[86, 114, -17, -13],
		[92, 100, 21, 23],
	]:
		for world_z in range(int(bounds[2]), int(bounds[3])):
			for world_x in range(int(bounds[0]), int(bounds[1])):
				var cell := world_to_cell(Vector3(float(world_x), 0.0, float(world_z)))
				cells.append([cell.x, cell.y])
	return cells
