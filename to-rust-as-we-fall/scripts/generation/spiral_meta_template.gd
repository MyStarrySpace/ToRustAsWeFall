class_name SpiralMetaTemplate
extends MetaTemplate

## The DESCENDING-SPIRAL meta-template. The fall-to PLANE is the spiral's own lower turns (walkable, warped); the
## RETURN POINTS are placed where a cell and the cell one full turn ahead sit stacked (the ahead cell directly
## BELOW). Peris tends an anchor on the already-reached upper turn; its vine visibly grows down to the lower turn,
## where it becomes a lower -> upper recovery climb. There is deliberately NO paired forward drop portal: it made
## the next turn reachable before its blockers were resolved and read as an unexplained second staircase.

const SpiralCoordMapScript := preload("res://scripts/generation/spiral_coord_map.gd")

const _MAX_RETURN_POINTS := 3

func template_id() -> String:
	return "spiral"

func build_coord_map(spine_nav: Dictionary):
	if spine_nav.is_empty():
		return null
	return SpiralCoordMapScript.from_grid(spine_nav)

func return_point_specs(spine_nav: Dictionary, coord_map) -> Array:
	if coord_map == null or spine_nav.is_empty():
		return []
	var grid = GridWorld.from_data(spine_nav)
	var period_cells := int(round(coord_map.period_s() / maxf(grid.cell_size, 0.001)))
	if period_cells < 6 or period_cells > grid.width - 3:
		return []
	var specs: Array = []
	var cx := int(round(period_cells * 0.5))
	while cx + period_cells < grid.width - 1 and specs.size() < _MAX_RETURN_POINTS:
		var pair := _find_gated_return_pair(
			grid, cx, period_cells, coord_map
		)
		if not pair.is_empty():
			var upper: Vector2i = pair["upper"]
			var lower: Vector2i = pair["lower"]
			var upper_level := int(pair.get("upper_level", 0))
			var lower_level := int(pair.get("lower_level", 0))
			var upper_flat: Vector3 = grid.grid_to_world(upper, upper_level)
			var lower_flat: Vector3 = grid.grid_to_world(lower, lower_level)
			var return_spec := gated_climbvine_spec(upper_flat, lower_flat, specs.size())
			return_spec["upper_spine_order"] = upper.x
			return_spec["lower_spine_order"] = lower.x
			return_spec["upper_navigation_level"] = upper_level
			return_spec["lower_navigation_level"] = lower_level
			specs.append(return_spec)
		cx += period_cells
	return specs
