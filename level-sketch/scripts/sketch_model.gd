class_name SketchModel
extends RefCounted

## Standalone data layer for the level-sketch tool.
##
## The world is a 2D grid (x, y) viewed top-down. Every element also carries an
## integer height `level`, so the same (x, y) can hold content on several stacked
## levels. Two layers:
##   - "level"   : terrain room cells (the walkable floor footprint)
##   - "objects" : placed entities — flora, fauna, shelters, building/object block-ins
##
## Pure data + JSON. No rendering here; GridView reads this and draws it, applying
## height_tint() so off-level content reads as faded orange (above) / blue (below).

const SCHEMA_VERSION := 1

const LAYER_LEVEL := "level"
const LAYER_OBJECTS := "objects"

# Object kinds. Cells are terrain; these live on the objects layer.
const KIND_FLORA := "flora"
const KIND_FAUNA := "fauna"
const KIND_SHELTER := "shelter"
const KIND_BLOCKIN := "blockin"

const SHAPE_CELL := "cell"
const SHAPE_RECT := "rect"
const SHAPE_CIRCLE := "circle"

# --- Height tint tuning (shared, pure) ---
const TINT_ABOVE := Color(1.0, 0.5, 0.1)     # higher levels skew orange
const TINT_BELOW := Color(0.2, 0.5, 1.0)     # lower levels skew blue
const TINT_ALPHA_FALLOFF := 0.24              # alpha lost per level of difference
const TINT_ALPHA_FLOOR := 0.14               # never fully invisible
const TINT_BLEND_PER_LEVEL := 0.3            # colour pull toward the tint per level
const TINT_BLEND_MAX := 0.72

# Terrain cells keyed by Vector3i(grid_x, grid_y, level) -> { "type": String }.
var cells: Dictionary = {}
# Placed objects (see _normalize_object for the schema).
var objects: Array = []
var _next_id: int = 1

# ---------------------------------------------------------------- Terrain cells

func set_cell(x: int, y: int, level: int, type := "room") -> void:
	cells[Vector3i(x, y, level)] = {"type": type}

func erase_cell(x: int, y: int, level: int) -> bool:
	return cells.erase(Vector3i(x, y, level))

func has_cell(x: int, y: int, level: int) -> bool:
	return cells.has(Vector3i(x, y, level))

func get_cell(x: int, y: int, level: int) -> Dictionary:
	return cells.get(Vector3i(x, y, level), {})

## Fill an inclusive grid rectangle with cells on `level`. Returns the count changed.
func fill_rect(x0: int, y0: int, x1: int, y1: int, level: int, type := "room") -> int:
	var count := 0
	for cell in _rect_cells(x0, y0, x1, y1):
		set_cell(cell.x, cell.y, level, type)
		count += 1
	return count

## Erase every cell in an inclusive grid rectangle on `level`. Returns count removed.
func erase_rect(x0: int, y0: int, x1: int, y1: int, level: int) -> int:
	var count := 0
	for cell in _rect_cells(x0, y0, x1, y1):
		if erase_cell(cell.x, cell.y, level):
			count += 1
	return count

static func _rect_cells(x0: int, y0: int, x1: int, y1: int) -> Array:
	var out: Array = []
	for gx in range(mini(x0, x1), maxi(x0, x1) + 1):
		for gy in range(mini(y0, y1), maxi(y0, y1) + 1):
			out.append(Vector2i(gx, gy))
	return out

# ---------------------------------------------------------------------- Objects

## Add an object from a partial spec; missing fields get sane defaults. Returns id.
func add_object(spec: Dictionary) -> int:
	var obj := _normalize_object(spec)
	obj["id"] = _next_id
	_next_id += 1
	objects.append(obj)
	return int(obj["id"])

func remove_object(id: int) -> bool:
	for i in range(objects.size()):
		if int(objects[i].get("id", -1)) == id:
			objects.remove_at(i)
			return true
	return false

func get_object(id: int) -> Dictionary:
	for obj in objects:
		if int(obj.get("id", -1)) == id:
			return obj
	return {}

func objects_on_level(level: int) -> Array:
	var out: Array = []
	for obj in objects:
		if int(obj.get("level", 0)) == level:
			out.append(obj)
	return out

## Topmost object whose footprint covers grid (x, y) on `level` (last drawn wins).
func object_at(x: int, y: int, level: int) -> Dictionary:
	for i in range(objects.size() - 1, -1, -1):
		var obj: Dictionary = objects[i]
		if int(obj.get("level", 0)) == level and _object_covers(obj, x, y):
			return obj
	return {}

static func _object_covers(obj: Dictionary, x: int, y: int) -> bool:
	var ox := int(obj.get("x", 0))
	var oy := int(obj.get("y", 0))
	match str(obj.get("shape", SHAPE_CELL)):
		SHAPE_RECT:
			var w := int(obj.get("w", 1))
			var h := int(obj.get("h", 1))
			return x >= ox and x < ox + w and y >= oy and y < oy + h
		SHAPE_CIRCLE:
			var r := float(obj.get("r", 1.0))
			# Cell-center distance against the circle radius (origin = circle centre).
			var dx := (float(x) + 0.5) - (float(ox) + 0.5)
			var dy := (float(y) + 0.5) - (float(oy) + 0.5)
			return dx * dx + dy * dy <= r * r
		_:
			return x == ox and y == oy

func _normalize_object(spec: Dictionary) -> Dictionary:
	var shape := str(spec.get("shape", SHAPE_CELL))
	var obj := {
		"kind": str(spec.get("kind", KIND_FLORA)),
		"shape": shape,
		"x": int(spec.get("x", 0)),
		"y": int(spec.get("y", 0)),
		"level": int(spec.get("level", 0)),
		"layer": str(spec.get("layer", LAYER_OBJECTS)),
	}
	if shape == SHAPE_RECT:
		obj["w"] = maxi(1, int(spec.get("w", 1)))
		obj["h"] = maxi(1, int(spec.get("h", 1)))
	elif shape == SHAPE_CIRCLE:
		obj["r"] = maxf(0.5, float(spec.get("r", 1.0)))
	# Store colour as a plain [r,g,b] array so it survives JSON (a Color stringifies
	# to "(r, g, b, a)" and would be lost on reload).
	if spec.has("color"):
		var c = spec["color"]
		if c is Color:
			obj["color"] = [c.r, c.g, c.b]
		elif c is Array and (c as Array).size() >= 3:
			obj["color"] = [float(c[0]), float(c[1]), float(c[2])]
	if spec.has("label"):
		obj["label"] = str(spec["label"])
	return obj

# ----------------------------------------------------------------------- Levels

## Sorted, de-duplicated list of every level that holds any content.
func used_levels() -> Array:
	var seen := {}
	for key in cells.keys():
		seen[int((key as Vector3i).z)] = true
	for obj in objects:
		seen[int(obj.get("level", 0))] = true
	var out := seen.keys()
	out.sort()
	return out

func is_empty() -> bool:
	return cells.is_empty() and objects.is_empty()

func clear() -> void:
	cells.clear()
	objects.clear()
	_next_id = 1

# ---------------------------------------------------------------- Serialization

func to_dict() -> Dictionary:
	var cell_list: Array = []
	for key in cells.keys():
		var c: Vector3i = key
		var data: Dictionary = cells[key]
		cell_list.append({"x": c.x, "y": c.y, "level": c.z, "type": data.get("type", "room")})
	return {
		"schema": SCHEMA_VERSION,
		"cells": cell_list,
		"objects": objects.duplicate(true),
		"next_id": _next_id,
	}

func from_dict(data: Dictionary) -> void:
	clear()
	for raw in data.get("cells", []):
		if raw is Dictionary:
			set_cell(int(raw.get("x", 0)), int(raw.get("y", 0)), int(raw.get("level", 0)), str(raw.get("type", "room")))
	# Reconstruct ids so every loaded object is unique regardless of input order or
	# duplicate/non-positive ids in a hand-edited save. First note all valid explicit
	# ids; then assign in order, keeping a free explicit id or drawing a fresh one.
	var max_id := 0
	for raw in data.get("objects", []):
		if raw is Dictionary and int(raw.get("id", 0)) > 0:
			max_id = maxi(max_id, int(raw.get("id", 0)))
	var used := {}
	var counter := max_id + 1
	for raw in data.get("objects", []):
		if not (raw is Dictionary):
			continue
		var obj := _normalize_object(raw)
		var rid := int(raw.get("id", 0))
		if rid > 0 and not used.has(rid):
			obj["id"] = rid
		else:
			while used.has(counter):
				counter += 1
			obj["id"] = counter
			counter += 1
		used[int(obj["id"])] = true
		objects.append(obj)
	_next_id = maxi(int(data.get("next_id", 0)), counter)

func to_json() -> String:
	return JSON.stringify(to_dict(), "\t")

static func from_json(text: String) -> SketchModel:
	var model := SketchModel.new()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		model.from_dict(parsed)
	return model

# ------------------------------------------------------------ Height tint (pure)

## Fade + colour-shift a base colour for content sitting `delta` levels away from the
## viewing level (delta = element_level - view_level). delta 0 returns the base
## untouched; above skews orange and below skews blue, both fading toward TINT_ALPHA_FLOOR.
static func height_tint(base: Color, delta: int) -> Color:
	if delta == 0:
		return base
	var magnitude := absi(delta)
	# Floor the FINAL alpha (not just the multiplier) so a translucent base still never
	# fades below the floor — capped at the base's own alpha so it can't get brighter.
	var floor_a := minf(TINT_ALPHA_FLOOR, base.a)
	var final_a := clampf(base.a * (1.0 - magnitude * TINT_ALPHA_FALLOFF), floor_a, base.a)
	var tint := TINT_ABOVE if delta > 0 else TINT_BELOW
	var blend := clampf(magnitude * TINT_BLEND_PER_LEVEL, 0.0, TINT_BLEND_MAX)
	var rgb := Color(base.r, base.g, base.b).lerp(tint, blend)
	return Color(rgb.r, rgb.g, rgb.b, final_a)
