class_name HubMetaTemplate
extends MetaTemplate

## The parameterised HUB meta-template: the stretch generates AROUND a chosen SHAPE (circle / rectangle / any
## polygon) as its hub. The shape is a PARAMETER — plug in `{type:"rect", aspect:1.8}`, `{type:"hexagon"}`,
## `{type:"polygon", points:[...]}`, etc. The circle case reproduces the spiral. Return points (drop portals +
## climbvines) sit where a loop stacks directly over the loop below, exactly as the spiral. The shelter connects
## to the base (the shape's interior) — see the chunk's base-plane wiring.

const HubShapeCoordMapScript := preload("res://scripts/generation/hub_shape_coord_map.gd")
const _MAX_RETURN_POINTS := 4

var _shape: Dictionary = {"type": "circle"}

func _init(shape := {"type": "circle"}) -> void:
	_shape = shape.duplicate(true) if shape is Dictionary else {"type": "circle"}

func template_id() -> String:
	return "hub:%s" % str(_shape.get("type", "circle"))

func build_coord_map(spine_nav: Dictionary):
	if spine_nav.is_empty():
		return null
	return HubShapeCoordMapScript.from_grid(spine_nav, _shape)

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
	while cx + period_cells < grid.width - 1 and specs.size() < _MAX_RETURN_POINTS * 2:
		var pair := _find_stacked_pair(grid, cx, period_cells)
		if not pair.is_empty():
			var upper: Vector2i = pair["upper"]
			var lower: Vector2i = pair["lower"]
			var upper_flat: Vector3 = grid.grid_to_world(upper); upper_flat.y = deck_y
			var lower_flat: Vector3 = grid.grid_to_world(lower); lower_flat.y = deck_y
			specs.append({"kind": "drop", "upper": upper_flat, "lower": lower_flat})
			specs.append({"kind": "climb", "upper": upper_flat, "lower": lower_flat})
		cx += period_cells
	return specs

func _find_stacked_pair(grid, cx: int, period_cells: int) -> Dictionary:
	var mid := int(grid.height / 2)
	for dz in range(grid.height):
		for cz in ([mid] if dz == 0 else [mid + dz, mid - dz]):
			if cz < 0 or cz >= grid.height:
				continue
			if grid.is_walkable(cx, cz) and grid.is_walkable(cx + period_cells, cz):
				return {"upper": Vector2i(cx, cz), "lower": Vector2i(cx + period_cells, cz)}
	return {}
