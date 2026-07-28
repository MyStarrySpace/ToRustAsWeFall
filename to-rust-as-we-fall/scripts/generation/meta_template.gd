class_name MetaTemplate
extends RefCounted

## A META-TEMPLATE is a level's MACRO shape. Every template is the same grammar:
##   1. a PLANE you fall down to (the spiral's lower turns; or a circle/rectangle hub disc),
##   2. RETURN POINTS connecting the stretches back UP to it from one side (gated climbvines),
##   3. puzzle/survival STRETCHES strung between the return points.
## Concretely a template provides the flat<->world WARP (a coord_map) and the RETURN-POINT specs; the chunk builds
## the geometry from them. The spiral is one instance (SpiralMetaTemplate); a rectangle/ring hub is another. This
## base is the FLAT (no-warp) template — an authored level plays as drawn.

## Stable id (for config selection + tests).
func template_id() -> String:
	return "flat"

## The flat-data <-> warped-world map for this shape, or null for a flat template. The chunk installs it as
## GameState.coord_map (characters render + clicks invert through it) and warps its own floor/dressing with it.
func build_coord_map(_spine_nav: Dictionary):
	return null

## Return points connect failed/lower positions back to ALREADY-REACHED upper ground. They are never forward-drop
## shortcuts. A return starts dormant; Peris tends its upper anchor, the vine visibly grows down to the lower deck,
## and only then may the party climb lower -> upper. Points are FLAT data coordinates; the chunk warps them onto
## the world shape. Empty = none.
func return_point_specs(_spine_nav: Dictionary, _coord_map) -> Array:
	return []


## One schema for every macro shape keeps the topology promise independent of its silhouette.
func gated_climbvine_spec(upper: Vector3, lower: Vector3, anchor_index: int) -> Dictionary:
	return {
		"contract_id": "gated_climbvine_return_v1",
		"id": "recovery_return_%02d" % anchor_index,
		"kind": "climb",
		"role": "recovery_return",
		"upper": upper,
		"lower": lower,
		"starts_active": false,
		"requires_upper_activation": true,
		"activation_policy": "tend_upper_anchor",
		"activation_character": "peris",
		"traversal_direction": "lower_to_upper",
		"topology_effect": "backtrack_only",
		"forward_traversal": false,
		"cannot_bypass_unresolved": true,
	}


## Shared physical anchor resolver for looping meta-templates. WFC may shift a
## spine sideways, and setpieces may distribute it across several navigation
## levels, so the return contract cannot probe level zero at one ideal column.
## Both endpoints remain actual walkable (cell, level) pairs exactly one loop
## apart. A bounded lane offset permits a short, readable diagonal vine without
## inventing either endpoint. The later endpoint must also render physically
## below the earlier one: "lower" is a world-space promise, not a semantic label.
func _find_gated_return_pair(
	grid, ideal_x: int, period_cells: int, coord_map
) -> Dictionary:
	var search_radius := maxi(
		0, int(floor(float(period_cells - 1) * 0.5))
	)
	for offset in range(search_radius + 1):
		var columns: Array[int] = []
		if offset == 0:
			columns.append(ideal_x)
		else:
			columns.append(ideal_x - offset)
			columns.append(ideal_x + offset)
		for candidate_x in columns:
			if candidate_x < 1 \
					or candidate_x + period_cells >= grid.width - 1:
				continue
			var pair := _find_gated_return_pair_at_column(
				grid, candidate_x, period_cells, coord_map
			)
			if not pair.is_empty():
				return pair
	return {}


func _find_gated_return_pair_at_column(
	grid, upper_x: int, period_cells: int, coord_map
) -> Dictionary:
	var best := {}
	var best_lane_delta: int = int(grid.height) + 1
	var best_level_delta: int = int(grid.level_count) + 1
	var best_center_cost: int = int(grid.height) * 2 + 1
	var mid := int(grid.height / 2)
	var max_lane_delta := maxi(1, int(ceil(float(grid.height) * 0.25)))
	for upper_level in range(grid.level_count):
		for upper_z in range(grid.height):
			if not grid.is_walkable(
				upper_x, upper_z, {}, {}, upper_level
			):
				continue
			var upper_cell := Vector2i(upper_x, upper_z)
			var upper_flat: Vector3 = grid.grid_to_world(
				upper_cell, upper_level
			)
			var upper_render: Vector3 = coord_map.to_world(upper_flat)
			for lower_level in range(grid.level_count):
				for lower_z in range(grid.height):
					if not grid.is_walkable(
						upper_x + period_cells,
						lower_z,
						{},
						{},
						lower_level
					):
						continue
					var lane_delta := absi(lower_z - upper_z)
					if lane_delta > max_lane_delta:
						continue
					var lower_cell := Vector2i(
						upper_x + period_cells, lower_z
					)
					var lower_flat: Vector3 = grid.grid_to_world(
						lower_cell, lower_level
					)
					if coord_map.to_world(lower_flat).y \
							>= upper_render.y - 0.1:
						continue
					var level_delta := absi(lower_level - upper_level)
					var center_cost := (
						absi(upper_z - mid) + absi(lower_z - mid)
					)
					if lane_delta < best_lane_delta \
							or (
								lane_delta == best_lane_delta
								and level_delta < best_level_delta
							) \
							or (
								lane_delta == best_lane_delta
								and level_delta == best_level_delta
								and center_cost < best_center_cost
							):
						best_lane_delta = lane_delta
						best_level_delta = level_delta
						best_center_cost = center_cost
						best = {
							"upper": upper_cell,
							"lower": lower_cell,
							"upper_level": upper_level,
							"lower_level": lower_level,
						}
	return best


## Public structural guard for generation tests and runtime hosts. A new template cannot quietly reintroduce the
## old paired drop portal or an always-on stair that skips unresolved work.
func validate_return_point_specs(specs: Array) -> Dictionary:
	var errors: Array[String] = []
	for index in range(specs.size()):
		if not (specs[index] is Dictionary):
			errors.append("Return point %d is not a dictionary." % index)
			continue
		var spec := specs[index] as Dictionary
		var label := str(spec.get("id", "return_%02d" % index))
		if str(spec.get("kind", "")) != "climb":
			errors.append("%s is a forward/drop return; only gated climbs are allowed." % label)
		if str(spec.get("role", "")) != "recovery_return":
			errors.append("%s lacks the recovery_return role." % label)
		if bool(spec.get("starts_active", true)):
			errors.append("%s starts active instead of waiting for its upper anchor." % label)
		if not bool(spec.get("requires_upper_activation", false)) \
				or str(spec.get("activation_policy", "")) != "tend_upper_anchor":
			errors.append("%s is not gated by tending the upper anchor." % label)
		if str(spec.get("activation_character", "")) != "peris":
			errors.append("%s does not assign the tending action to Peris." % label)
		if str(spec.get("traversal_direction", "")) != "lower_to_upper" \
				or str(spec.get("topology_effect", "")) != "backtrack_only" \
				or bool(spec.get("forward_traversal", true)):
			errors.append("%s can advance rather than return to resolved space." % label)
		if spec.has("upper_spine_order") and spec.has("lower_spine_order") \
				and int(spec.get("upper_spine_order", 0)) >= int(spec.get("lower_spine_order", 0)):
			errors.append("%s does not return from later/lower progress to earlier/upper progress." % label)
		if not bool(spec.get("cannot_bypass_unresolved", false)):
			errors.append("%s does not declare the unresolved-blocker invariant." % label)
	return {"valid": errors.is_empty(), "errors": errors, "return_count": specs.size()}
