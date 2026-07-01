class_name SpiralMetaTemplate
extends MetaTemplate

## The DESCENDING-SPIRAL meta-template. The fall-to PLANE is the spiral's own lower turns (walkable, warped); the
## RETURN POINTS are placed where a cell and the cell one full turn ahead sit stacked (the ahead cell directly
## BELOW): a DROP portal takes you down that shortcut, and a CLIMBVINE takes you back UP the same stack. The
## STRETCHES are the spine segments between. So the spiral realizes the whole meta-grammar within one warped space
## (no separate hub coordinate system needed — that's what the circle/rectangle-hub templates add).

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
	var period_cells := int(round(coord_map.period_s()))
	if period_cells < 6 or period_cells > grid.width - 3:
		return []
	var deck_y := float((spine_nav.get("origin", [0.0, 0.45, 0.0]) as Array)[1])
	var specs: Array = []
	var cx := int(round(period_cells * 0.5))
	while cx + period_cells < grid.width - 1 and specs.size() < _MAX_RETURN_POINTS:
		var pair := _find_stacked_pair(grid, cx, period_cells)
		if not pair.is_empty():
			var upper: Vector2i = pair["upper"]
			var lower: Vector2i = pair["lower"]
			var upper_flat: Vector3 = grid.grid_to_world(upper); upper_flat.y = deck_y
			var lower_flat: Vector3 = grid.grid_to_world(lower); lower_flat.y = deck_y
			# Both directions at each stacked overlap: fall DOWN a loop, or climb the vine back UP.
			specs.append({"kind": "drop", "upper": upper_flat, "lower": lower_flat})
			specs.append({"kind": "climb", "upper": upper_flat, "lower": lower_flat})
		cx += period_cells
	return specs

## At column `cx`, the walkable cell nearest the centre row whose cell one full turn ahead (directly below on the
## descending helix) is also walkable — the stacked overlap a return point bridges. Empty if none.
func _find_stacked_pair(grid, cx: int, period_cells: int) -> Dictionary:
	var mid := int(grid.height / 2)
	for dz in range(grid.height):
		for cz in ([mid] if dz == 0 else [mid + dz, mid - dz]):
			if cz < 0 or cz >= grid.height:
				continue
			if grid.is_walkable(cx, cz) and grid.is_walkable(cx + period_cells, cz):
				return {"upper": Vector2i(cx, cz), "lower": Vector2i(cx + period_cells, cz)}
	return {}
