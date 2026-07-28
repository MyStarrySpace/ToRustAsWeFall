class_name AbilityData

## Ability display names, bindings, and provisional tuning loaded from
## data/abilities/en/abilities.xlsx (mirrors DialogueData). ABILITY_ORDER is the implemented-cast
## authority: localized data can describe or tune those casts, but cannot create new ones.
##
## xlsx columns: key, display_name, duration, cooldown, message, note
## Keys are "<context>.<ability_id>" — e.g. "default.emp" or "peris_sim.wrap". Contextual verbs
## such as HACK, SCAN, and TEND live on compatible world targets instead of masquerading as casts.
##
## Usage:
##   AbilityData.load_dir("res://data/abilities/en/")
##   var a := AbilityData.get_ability("default.wrap")   # {id, display_name, duration, ...}
##   var all := AbilityData.for_context("peris_sim")    # Array of canonical dicts, id set

const DIR := "res://data/abilities/en/"

## Canonical party order so for_context() is independent of the xlsx row order.
## Currently implemented early-game casts. Later GDD commitments (Inflame, Barrier/Restore, and
## Suppress) stay canonical but unavailable until their full runtime contracts are authored.
## Aster's hacking/scan register and Peris's flora tending/reading remain contextual world verbs
## owned by the target object, not reskinned buttons.
const ABILITY_ORDER := ["emp", "wrap"]
const CANONICAL_NAMED_ABILITIES := {
	"emp": "aster",
	"wrap": "peris",
	"inflame": "myke",
	"barrier": "oli",
	"restore": "oli",
	"suppress": "tyreg",
}
const CONTEXTUAL_VERBS := {
	"aster": ["hack", "scan"],
	"peris": ["tend", "read_flora"],
}

static var _abilities: Dictionary = {}  # "context.id" -> {id, display_name, duration, cooldown, message, note}
static var _bindings: Dictionary = {}   # ability_id -> {owner, keybind, keycode, color, stamina_cost, active_status}
static var _loaded := false

## Load every abilities workbook in a directory. Translation: point at another locale dir.
static func load_dir(dir_path: String = DIR) -> void:
	_abilities.clear()
	_bindings.clear()
	var dir := DirAccess.open(dir_path)
	if not dir:
		push_error("AbilityData: Could not open directory %s" % dir_path)
		_loaded = true
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		# Skip Excel lock files (~$abilities.xlsx) and hidden files.
		if not dir.current_is_dir() and not file_name.begins_with("~$") and not file_name.begins_with("."):
			if file_name.ends_with(".xlsx"):
				_load_xlsx_file(dir_path.path_join(file_name))
		file_name = dir.get_next()
	_loaded = true

static func _load_xlsx_file(path: String) -> void:
	var reader := XlsxReader.new()
	if reader.open(path) != OK:
		push_error("AbilityData: could not open %s" % path)
		return
	for sheet_name in reader.get_sheet_names():
		var rows := reader.get_sheet_data(sheet_name)
		if rows.is_empty():
			continue
		if str(sheet_name).strip_edges().to_lower() == "bindings":
			_parse_bindings(rows)
		else:
			_parse_content(rows)
	reader.close()

## "abilities" sheet: per-context content rows (key = "<context>.<ability_id>").
static func _parse_content(rows: Array) -> void:
	var first_row: Array = rows[0]
	var start := 1 if first_row.size() > 0 and str(first_row[0]).strip_edges().to_lower() == "key" else 0
	for i in range(start, rows.size()):
		var row: Array = rows[i]
		if row.size() < 2 or str(row[0]).strip_edges() == "":
			continue
		var key := str(row[0]).strip_edges()
		var dot := key.rfind(".")
		_abilities[key] = {
			"id": key.substr(dot + 1) if dot >= 0 else key,
			"display_name": str(row[1]).strip_edges() if row.size() > 1 else "",
			"duration": _to_float(row[2]) if row.size() > 2 else 0.0,
			"cooldown": _to_float(row[3]) if row.size() > 3 else 0.0,
			"message": str(row[4]).strip_edges() if row.size() > 4 else "",
			"note": str(row[5]).strip_edges() if row.size() > 5 else "",
		}

## "bindings" sheet: per-ability_id mechanics (owner / keybind / color / stamina_cost / status).
static func _parse_bindings(rows: Array) -> void:
	var first_row: Array = rows[0]
	var start := 1 if first_row.size() > 0 and str(first_row[0]).strip_edges().to_lower() == "id" else 0
	var columns := {}
	for column_index in range(first_row.size()):
		columns[str(first_row[column_index]).strip_edges().to_lower()] = column_index
	for i in range(start, rows.size()):
		var row: Array = rows[i]
		if row.size() < 2 or str(row[0]).strip_edges() == "":
			continue
		var id := str(row[0]).strip_edges()
		# A workbook row cannot silently rewrite a character's kit. The GDD-backed manifest above
		# must change deliberately before a new cast ability becomes live.
		if not ABILITY_ORDER.has(id):
			push_warning("AbilityData: ignored non-canonical ability binding '%s'" % id)
			continue
		var keybind := str(_row_value(row, columns, "keybind", 2)).strip_edges()
		var binding := {
			"owner": str(_row_value(row, columns, "owner", 1)).strip_edges(),
			"keybind": keybind,
			"keycode": _keycode_for(keybind),
			# Cast abilities spend stamina. There is intentionally no ATP field here: ATP is
			# exclusively the shelter-rest budget and cannot be authored as a cast cost.
			"stamina_cost": _to_float(_row_value(row, columns, "stamina_cost", -1)),
			"active_status": str(_row_value(row, columns, "active_status", 5)).strip_edges(),
		}
		var color_str := str(_row_value(row, columns, "color", 3)).strip_edges()
		if color_str != "":
			binding["color"] = _to_color(color_str)
		_bindings[id] = binding

static func _row_value(row: Array, columns: Dictionary, column_name: String, fallback_index: int):
	var index := int(columns.get(column_name, fallback_index))
	return row[index] if index >= 0 and index < row.size() else ""

static func _to_float(cell) -> float:
	var s := str(cell).strip_edges()
	return float(s) if s != "" else 0.0

## A keybind string ("Z") -> its keycode. Empty -> 0.
static func _keycode_for(keybind: String) -> int:
	var k := keybind.strip_edges()
	if k == "":
		return 0
	return OS.find_keycode_from_string(k)

## An "r,g,b" (or "r,g,b,a") float string -> Color. Blank/garbage -> opaque white.
static func _to_color(s: String) -> Color:
	var parts := s.split(",", false)
	if parts.size() < 3:
		return Color.WHITE
	var a := float(parts[3]) if parts.size() > 3 else 1.0
	return Color(float(parts[0]), float(parts[1]), float(parts[2]), a)

## The per-ability mechanics (owner / keybind / keycode / color / stamina_cost / active_status) for an
## ability_id, or {} if absent. Keyed by bare ability_id (the binding is the same across every context).
static func binding(ability_id: String) -> Dictionary:
	if not _loaded:
		load_dir()
	return (_bindings.get(ability_id, {}) as Dictionary).duplicate(true)

static func is_canonical_ability(ability_id: String) -> bool:
	return ABILITY_ORDER.has(ability_id)

## The ability dict for a key, or {} if absent. Lazy-loads on first access. Copy-on-read.
static func get_ability(key: String) -> Dictionary:
	if not _loaded:
		load_dir()
	return (_abilities.get(key, {}) as Dictionary).duplicate(true)

## Whether a key is defined.
static func has(key: String) -> bool:
	if not _loaded:
		load_dir()
	return _abilities.has(key)

## Every ability whose key is "<context>.*", as dicts (id set), in sheet order. This is the array a
## chunk's get_preview_abilities() returns — the canonical bindings (keybind/owner/color) are applied
## downstream by the HUD layer, keyed on id.
static func for_context(context: String) -> Array:
	if not _loaded:
		load_dir()
	var prefix := context + "."
	var found := {}
	for key in _abilities.keys():
		if str(key).begins_with(prefix):
			var a := get_ability(key)
			var id := str(a.get("id", ""))
			if is_canonical_ability(id):
				found[id] = a
	# Canonical party order first, then any extras in sheet order.
	var result: Array = []
	for id in ABILITY_ORDER:
		if found.has(id):
			result.append(found[id])
			found.erase(id)
	for id in found.keys():
		result.append(found[id])
	return result
