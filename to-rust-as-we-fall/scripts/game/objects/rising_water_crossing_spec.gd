class_name RisingWaterCrossingSpec
extends RefCounted

## Portable authoring and procedural-generation contract for a water crossing
## whose one state variable rewrites the traversable map. The state list is ordered but unbounded;
## every entry independently declares elevations, walkability, and catch policy.

const CONTRACT := "rising_water_crossing_spec/v1"
const OBJECT_TYPE := "rising_water_crossing"
const LEGACY_OBJECT_TYPE := "basin"


static func normalize(raw: Dictionary) -> Dictionary:
	var spec := raw.duplicate(true)
	spec["type"] = OBJECT_TYPE
	if str(spec.get("tag", "")).strip_edges() == "":
		spec["tag"] = str(spec.get("name", "water_crossing")).to_snake_case()
	if not spec.has("float_level"):
		spec["float_level"] = 1
	if not spec.has("telegraph_lead"):
		spec["telegraph_lead"] = 2.5
	if not spec.has("platform_motion_lead"):
		spec["platform_motion_lead"] = spec["telegraph_lead"]
	if not spec.has("rota") or not (spec.get("rota") is Array) \
			or (spec.get("rota") as Array).is_empty():
		spec["rota"] = [
			{"level": 0, "dwell": 8.0},
			{"level": 1, "dwell": 6.0},
		]
	if not spec.has("safe_cells"):
		spec["safe_cells"] = []
	if not spec.has("recovery_cells"):
		spec["recovery_cells"] = []
	if not spec.has("recovery_level"):
		spec["recovery_level"] = 0
	if not spec.has("dwellers"):
		spec["dwellers"] = []
	if not spec.has("sweep"):
		spec["sweep"] = {
			"party_hp": 5.0,
			"enemy_damage": 999.0,
			"travel_speed": 7.0,
			"refractory": 4.0,
		}
	if not spec.has("water_states") or not (spec.get("water_states") is Array) \
			or (spec.get("water_states") as Array).is_empty():
		var water_y: Array = spec.get("water_y", [-0.4, 2.35, 3.1]) as Array
		var float_y: Array = spec.get("float_y", [0.15, 2.55, 3.25]) as Array
		var count := mini(water_y.size(), float_y.size())
		var states: Array = []
		for index in range(count):
			var is_first := index == 0
			var is_last := index == count - 1
			var state_name := "LEVEL_%d" % index
			if count == 3:
				state_name = ["LOW", "MID", "HIGH"][index]
			states.append({
				"name": state_name,
				"water_y": float(water_y[index]),
				"float_y": float(float_y[index]),
				"floor_walkable": is_first,
				"floats_walkable": not is_first and (count == 2 or not is_last),
				"catches_floor": not is_first,
				"catches_floats": is_last and count > 2,
			})
		spec["water_states"] = states
	spec["archetype_contract"] = CONTRACT
	return spec


## Deterministically convert generated grid bounds into the complete runtime
## object. Cell bounds are inclusive. The generator chooses topology; this
## builder owns coordinate conversion, defaults, and portable serialization.
static func from_grid_rect(params: Dictionary) -> Dictionary:
	var origin: Vector3 = params.get("grid_origin", Vector3.ZERO)
	var cell_size := maxf(0.01, float(params.get("cell_size", 1.5)))
	var floor_min_cell := _cell(params.get("floor_min_cell", Vector2i.ZERO))
	var floor_max_cell := _cell(params.get("floor_max_cell", floor_min_cell))
	var float_min_cell := _cell(params.get("float_min_cell", floor_min_cell))
	var float_max_cell := _cell(params.get("float_max_cell", floor_max_cell))
	var min_cell := Vector2i(
		mini(floor_min_cell.x, floor_max_cell.x),
		mini(floor_min_cell.y, floor_max_cell.y))
	var max_cell := Vector2i(
		maxi(floor_min_cell.x, floor_max_cell.x),
		maxi(floor_min_cell.y, floor_max_cell.y))
	var float_cells: Array = []
	for z in range(mini(float_min_cell.y, float_max_cell.y), \
			maxi(float_min_cell.y, float_max_cell.y) + 1):
		for x in range(mini(float_min_cell.x, float_max_cell.x), \
				maxi(float_min_cell.x, float_max_cell.x) + 1):
			float_cells.append([x, z])
	var world_min := origin + Vector3(
		float(min_cell.x) * cell_size, 0.0, float(min_cell.y) * cell_size)
	var world_max := origin + Vector3(
		float(max_cell.x) * cell_size, 0.0, float(max_cell.y) * cell_size)
	var center := (world_min + world_max) * 0.5
	var floor_y := float(params.get("floor_y", origin.y))
	var deck_y := float(params.get("deck_y", floor_y + cell_size * 1.8))
	center.y = floor_y
	var recovery_cells: Array = (params.get("recovery_cells", []) as Array).duplicate(true)
	var safe_cells: Array = (params.get("safe_cells", []) as Array).duplicate(true)
	for recovery in recovery_cells:
		if not safe_cells.has(recovery):
			safe_cells.append(recovery)
	var outfall: Vector3 = params.get("outfall", center) as Vector3
	if not recovery_cells.is_empty() and not params.has("outfall"):
		var recovery := _cell(recovery_cells[0])
		outfall = origin + Vector3(
			float(recovery.x) * cell_size, floor_y - origin.y,
			float(recovery.y) * cell_size)
	var spec := {
		"type": OBJECT_TYPE,
		"name": str(params.get("name", "RisingWaterCrossing")),
		"tag": str(params.get("tag", "generated_water_crossing")),
		"pos": center,
		"plane_size": Vector2(
			float(max_cell.x - min_cell.x + 1) * cell_size,
			float(max_cell.y - min_cell.y + 1) * cell_size),
		"floor_min": Vector2(world_min.x - cell_size * 0.5, world_min.z - cell_size * 0.5),
		"floor_max": Vector2(world_max.x + cell_size * 0.5, world_max.z + cell_size * 0.5),
		"safe_cells": safe_cells,
		"float_cells": float_cells,
		"float_level": int(params.get("float_level", 1)),
		"rota": (params.get("rota", [
			{"level": 0, "dwell": 8.0},
			{"level": 1, "dwell": 6.0},
			{"level": 2, "dwell": 4.0},
			{"level": 1, "dwell": 6.0},
		]) as Array).duplicate(true),
		"telegraph_lead": float(params.get("telegraph_lead", 2.5)),
		"platform_motion_lead": float(params.get(
			"platform_motion_lead", params.get("telegraph_lead", 2.5))),
		"water_states": (params.get("water_states", [
			{
				"name": "LOW",
				"water_y": floor_y - 0.5,
				"float_y": floor_y + 0.12,
				"floor_walkable": true,
				"floats_walkable": false,
				"catches_floor": false,
				"catches_floats": false,
			},
			{
				"name": "MID",
				"water_y": deck_y - 0.25,
				"float_y": deck_y - 0.12,
				"floor_walkable": false,
				"floats_walkable": true,
				"catches_floor": true,
				"catches_floats": false,
			},
			{
				"name": "HIGH",
				"water_y": deck_y + 0.35,
				"float_y": deck_y + 0.6,
				"floor_walkable": false,
				"floats_walkable": false,
				"catches_floor": true,
				"catches_floats": true,
			},
		]) as Array).duplicate(true),
		"outfall": outfall,
		"recovery_cells": recovery_cells,
		"recovery_level": int(params.get("recovery_level", 0)),
		"sweep": (params.get("sweep", {}) as Dictionary).duplicate(true),
		"dwellers": (params.get("dwellers", []) as Array).duplicate(true),
		"generated_from": {
			"contract": "rising_water_crossing_grid_rect/v1",
			"floor_min_cell": [min_cell.x, min_cell.y],
			"floor_max_cell": [max_cell.x, max_cell.y],
			"float_min_cell": [float_min_cell.x, float_min_cell.y],
			"float_max_cell": [float_max_cell.x, float_max_cell.y],
			"cell_size": cell_size,
		},
	}
	return normalize(spec)


static func validate(spec_v: Dictionary, party_size := 0) -> Dictionary:
	var spec := normalize(spec_v)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if not (spec.get("pos") is Vector3):
		errors.append("pos must be Vector3")
	if not (spec.get("plane_size") is Vector2) \
			or (spec.get("plane_size") as Vector2).x <= 0.0 \
			or (spec.get("plane_size") as Vector2).y <= 0.0:
		errors.append("plane_size must be a positive Vector2")
	if not (spec.get("floor_min") is Vector2) or not (spec.get("floor_max") is Vector2):
		errors.append("floor_min and floor_max must be Vector2")
	elif (spec.get("floor_min") as Vector2).x >= (spec.get("floor_max") as Vector2).x \
			or (spec.get("floor_min") as Vector2).y >= (spec.get("floor_max") as Vector2).y:
		errors.append("floor bounds must have positive area")
	var float_cells: Array = spec.get("float_cells", []) as Array
	if float_cells.is_empty():
		errors.append("float_cells must contain the moving-platform route")
	elif not _all_unique_cells(float_cells):
		errors.append("float_cells must be unique portable grid cells")
	if int(spec.get("float_level", 0)) <= 0:
		errors.append("float_level must name a deck above the bowl floor")
	var water_states: Array = spec.get("water_states", []) as Array
	if water_states.size() < 2:
		errors.append("water_states must contain at least two authored maps")
	var previous_water_y := -INF
	for state_index in range(water_states.size()):
		if not (water_states[state_index] is Dictionary):
			errors.append("every water state must be a dictionary")
			continue
		var state := water_states[state_index] as Dictionary
		if str(state.get("name", "")).strip_edges() == "":
			errors.append("water state %d requires a name" % state_index)
		var state_water_y := float(state.get("water_y", NAN))
		if is_nan(state_water_y) or state_water_y <= previous_water_y:
			errors.append("water state elevations must increase in list order")
		previous_water_y = state_water_y
		if not state.has("float_y"):
			errors.append("water state %d requires float_y" % state_index)
	var rota: Array = spec.get("rota", []) as Array
	var states := {}
	for entry_v in rota:
		if not (entry_v is Dictionary):
			errors.append("every rota entry must be a dictionary")
			continue
		var entry := entry_v as Dictionary
		var state := int(entry.get("level", -1))
		states[state] = true
		if state < 0 or state >= water_states.size() \
				or float(entry.get("dwell", 0.0)) <= 0.0:
			errors.append("rota entries require a valid water-state index and positive dwell")
	for state_index in range(water_states.size()):
		if not states.has(state_index):
			warnings.append("water state %d is never entered by the rota" % state_index)
	var recovery_cells: Array = spec.get("recovery_cells", []) as Array
	if party_size > 0 and recovery_cells.size() < party_size:
		errors.append("recovery_cells needs one vertex per party member")
	var safe_cells: Array = spec.get("safe_cells", []) as Array
	for recovery in recovery_cells:
		if not safe_cells.has(recovery):
			errors.append("every recovery cell must also be safe")
	if float(spec.get("telegraph_lead", 0.0)) <= 0.0:
		warnings.append("no rise telegraph is authored")
	return {
		"contract": CONTRACT,
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"normalized": spec,
	}


static func _cell(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Vector2:
		return Vector2i(int((value as Vector2).x), int((value as Vector2).y))
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	return Vector2i.ZERO


static func _all_unique_cells(values: Array) -> bool:
	var seen := {}
	for value in values:
		if not (value is Vector2i or value is Vector2 \
				or (value is Array and (value as Array).size() >= 2)):
			return false
		var cell := _cell(value)
		if seen.has(cell):
			return false
		seen[cell] = true
	return true
