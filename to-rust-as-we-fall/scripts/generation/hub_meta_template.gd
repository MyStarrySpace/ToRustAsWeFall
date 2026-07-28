class_name HubMetaTemplate
extends MetaTemplate

## The parameterised HUB meta-template: the stretch generates AROUND a chosen SHAPE (circle / rectangle / any
## polygon) as its hub. The shape is a PARAMETER — plug in `{type:"rect", aspect:1.8}`, `{type:"hexagon"}`,
## `{type:"polygon", points:[...]}`, etc. The circle case reproduces the spiral. Gated recovery climbvines sit
## where a loop stacks directly over the loop below, exactly as the spiral. The shelter connects to the base (the
## shape's interior) — see the chunk's base-plane wiring.

const HubShapeCoordMapScript := preload("res://scripts/generation/hub_shape_coord_map.gd")
const _MAX_RETURN_POINTS := 4
const DEFAULT_BASE_CELLS := 10

var _shape: Dictionary = {"type": "circle"}
var _base_cells := DEFAULT_BASE_CELLS

func _init(shape := {"type": "circle"}) -> void:
	_shape = shape.duplicate(true) if shape is Dictionary else {"type": "circle"}
	# The shape can carry its own base depth (0 = no base floor); default a modest base.
	_base_cells = int(_shape.get("base_cells", DEFAULT_BASE_CELLS))

func template_id() -> String:
	return "hub:%s" % str(_shape.get("type", "circle"))

## Flat cells of the flat BASE FLOOR (the shape as a floor) the chunk prepends before the entry. 0 = no base.
func base_cells() -> int:
	return maxi(0, _base_cells)

func build_coord_map(spine_nav: Dictionary):
	if spine_nav.is_empty():
		return null
	return HubShapeCoordMapScript.from_grid(spine_nav, _shape, 0.0, 6.0, 0.45, base_cells())

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
