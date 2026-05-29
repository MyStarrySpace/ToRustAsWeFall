class_name GridRenderer
extends Node3D

## 3D visualization of a GridWorld. Creates meshes per tile + floor collision.

var _grid: GridWorld
var _tile_meshes: Array[MeshInstance3D] = []
var _tile_materials: Array[StandardMaterial3D] = []
var _floor_body: StaticBody3D

# Default tile colors
const TILE_COLORS := {
	GridWorld.Tile.FLOOR: Color(0.12, 0.1, 0.08),
	GridWorld.Tile.WALL: Color(0.15, 0.12, 0.1),
	GridWorld.Tile.FLORA: Color(0.1, 0.18, 0.1),
	GridWorld.Tile.IRON_BLOOM: Color(0.25, 0.1, 0.05),
	GridWorld.Tile.SHELTER: Color(0.1, 0.12, 0.2),
	GridWorld.Tile.TERMINAL: Color(0.1, 0.15, 0.18),
	GridWorld.Tile.FOOD: Color(0.1, 0.16, 0.1),
	GridWorld.Tile.KEY: Color(0.2, 0.18, 0.08),
	GridWorld.Tile.LOCKED_DOOR: Color(0.18, 0.1, 0.08),
	GridWorld.Tile.HIDE_DOOR: Color(0.11, 0.09, 0.07),
}

# Tile heights (walls taller, floors thin)
const TILE_HEIGHTS := {
	GridWorld.Tile.FLOOR: 0.1,
	GridWorld.Tile.WALL: 3.0,
	GridWorld.Tile.FLORA: 0.1,
	GridWorld.Tile.IRON_BLOOM: 0.1,
	GridWorld.Tile.SHELTER: 0.1,
	GridWorld.Tile.TERMINAL: 0.1,
	GridWorld.Tile.FOOD: 0.1,
	GridWorld.Tile.KEY: 0.1,
	GridWorld.Tile.LOCKED_DOOR: 3.0,
	GridWorld.Tile.HIDE_DOOR: 2.5,
}

func setup(grid: GridWorld, style: Dictionary = {}) -> void:
	_grid = grid
	_clear()
	_build_floor_collision()
	_build_tiles(style)

func _clear() -> void:
	for child in get_children():
		child.queue_free()
	_tile_meshes.clear()
	_tile_materials.clear()

func _build_floor_collision() -> void:
	# Single StaticBody3D covering the entire grid for click raycasting
	_floor_body = StaticBody3D.new()
	_floor_body.name = "GridFloor"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var total_w: float = _grid.width * _grid.cell_size
	var total_h: float = _grid.height * _grid.cell_size
	shape.size = Vector3(total_w, 0.02, total_h)
	col.shape = shape
	_floor_body.add_child(col)
	_floor_body.position = _grid.origin + Vector3(total_w * 0.5, -0.01, total_h * 0.5)
	_floor_body.collision_layer = 1
	_floor_body.collision_mask = 0
	add_child(_floor_body)

func _build_tiles(style: Dictionary) -> void:
	var colors: Dictionary = style.get("colors", TILE_COLORS)

	for z in range(_grid.height):
		for x in range(_grid.width):
			var tile: int = _grid.get_tile(x, z)
			var tile_height: float = TILE_HEIGHTS.get(tile, 0.1)
			var tile_color: Color = colors.get(tile, Color(0.1, 0.1, 0.1))

			var mesh_inst := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(_grid.cell_size * 0.98, tile_height, _grid.cell_size * 0.98)
			mesh_inst.mesh = box

			var mat := StandardMaterial3D.new()
			mat.albedo_color = tile_color

			# Emission for special tiles
			match tile:
				GridWorld.Tile.FLORA:
					mat.emission_enabled = true
					mat.emission = Color(0.05, 0.2, 0.05)
					mat.emission_energy_multiplier = 0.5
				GridWorld.Tile.IRON_BLOOM:
					mat.emission_enabled = true
					mat.emission = Color(0.3, 0.1, 0.02)
					mat.emission_energy_multiplier = 1.0
				GridWorld.Tile.TERMINAL:
					mat.emission_enabled = true
					mat.emission = Color(0.1, 0.3, 0.35)
					mat.emission_energy_multiplier = 0.8
				GridWorld.Tile.FOOD:
					mat.emission_enabled = true
					mat.emission = Color(0.05, 0.15, 0.05)
					mat.emission_energy_multiplier = 0.3

			mesh_inst.material_override = mat
			var world_pos := _grid.grid_to_world(Vector2i(x, z))
			mesh_inst.position = Vector3(world_pos.x, tile_height * 0.5 - 0.05, world_pos.z)
			add_child(mesh_inst)
			_tile_meshes.append(mesh_inst)
			_tile_materials.append(mat)

## Update fog of war visibility. Tiles within vision_radius of char_pos are fully
## visible, explored tiles are dim, and hidden tiles are invisible.
func update_fog(char_pos: Vector3, vision_radius: float, explored: Dictionary) -> void:
	if not _grid:
		return
	var char_cell := _grid.world_to_grid(char_pos)
	var idx := 0
	for z in range(_grid.height):
		for x in range(_grid.width):
			var cell := Vector2i(x, z)
			var dist := Vector2(cell - char_cell).length()
			var mat := _tile_materials[idx]

			if dist <= vision_radius:
				# Currently visible
				mat.albedo_color.a = 1.0
				explored[cell] = true
			elif explored.has(cell):
				# Memory-visible tile.
				mat.albedo_color.a = 0.3
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			else:
				# Never seen
				mat.albedo_color.a = 0.0
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

			idx += 1
