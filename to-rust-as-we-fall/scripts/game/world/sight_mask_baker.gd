class_name SightMaskBaker
extends RefCounted

## Bakes the grid's sight-blocking cells into a small texture for the perception overlay. The LOS
## march samples this BILINEARLY instead of reconstructing the depth buffer per step — so occlusion
## shadows get naturally soft edges (the bilinear gradient spans a cell), stop aliasing against
## unrelated geometry (props, creatures), and cost texture taps instead of depth reconstructions.
## A cell blocks sight when its tile is WALL or an explicit sight blocker — the same wall rule the
## detection system uses, NOT mere unwalkability semantics beyond it.
## Purely cosmetic (the player's perception view); rebaked whenever the live grid object changes.

static func bake(grid) -> Dictionary:
	if grid == null or grid.width <= 0 or grid.height <= 0:
		return {}
	var img := Image.create(grid.width, grid.height, false, Image.FORMAT_R8)
	for z in range(grid.height):
		for x in range(grid.width):
			var solid: bool = grid.get_tile(x, z) == GridWorld.Tile.WALL \
				or grid.sight_blockers.has(Vector2i(x, z))
			img.set_pixel(x, z, Color(1.0 if solid else 0.0, 0.0, 0.0))
	return {
		"texture": ImageTexture.create_from_image(img),
		"origin": Vector2(grid.origin.x, grid.origin.z),
		"cell": grid.cell_size,
		"size": Vector2(float(grid.width), float(grid.height)),
	}
