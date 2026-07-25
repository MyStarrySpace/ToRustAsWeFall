class_name LevelPalette
extends RefCounted

## THE level-palette authority (docs/LEVEL_PALETTES.md): every asset color traces to a
## row in data/palettes/level_palettes.json. Godot-side consumers call
## `LevelPalette.color("channels", "water")`; `_global` rows are cross-level invariants
## (terminal green, the portal trio, the Curecumin item gold). A missing level or role is
## LOUD (push_error + magenta) — a typo must never ship as a silently-wrong color.

const PALETTE_PATH := "res://data/palettes/level_palettes.json"
const MISSING := Color(1.0, 0.0, 1.0)

static var _data: Dictionary = {}

static func _load() -> void:
	if not _data.is_empty():
		return
	var text := FileAccess.get_file_as_string(PALETTE_PATH)
	if text.is_empty():
		push_error("LevelPalette: %s missing/empty" % PALETTE_PATH)
		_data = {"_global": {}}
		return
	var parsed: Variant = JSON.parse_string(text)
	_data = parsed if parsed is Dictionary else {"_global": {}}

## A level role: color("channels", "water"). Section hues: color("channels", "sections/jet").
static func color(level: String, role: String) -> Color:
	_load()
	var table: Variant = _data.get(level)
	if not (table is Dictionary):
		push_error("LevelPalette: unknown level '%s'" % level)
		return MISSING
	var node: Variant = table
	for part in role.split("/"):
		if node is Dictionary and (node as Dictionary).has(part):
			node = node[part]
		else:
			push_error("LevelPalette: unknown role '%s' in level '%s'" % [role, level])
			return MISSING
	if node is String:
		return Color.html(node)
	push_error("LevelPalette: role '%s' in '%s' is not a color" % [role, level])
	return MISSING

## A cross-level invariant: global_color("portal_route").
static func global_color(role: String) -> Color:
	return color("_global", role)
