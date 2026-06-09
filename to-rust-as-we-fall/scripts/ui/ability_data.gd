class_name AbilityData

## Ability display names, descriptions, and tuning — the single source of truth, loaded from
## data/abilities/en/abilities.xlsx (mirrors DialogueData). Mechanics (keybind / owner / color) stay in
## code as the canonical bindings; this owns the player-facing CONTENT so it can be edited + translated
## like dialogue.
##
## xlsx columns: key, display_name, duration, cooldown, message, note
## Keys are "<context>.<ability_id>" — e.g. "channels_rhythm.aster_focus", "refuge_run.peris_tune",
## "peris_sim.protect". A chunk pulls its whole ability set with for_context("<chunk>").
##
## Usage:
##   AbilityData.load_dir("res://data/abilities/en/")
##   var a := AbilityData.get_ability("refuge_run.peris_tune")   # {id, display_name, duration, ...}
##   var all := AbilityData.for_context("refuge_run")            # Array of those dicts, id set

const DIR := "res://data/abilities/en/"

static var _abilities: Dictionary = {}  # "context.id" -> {id, display_name, duration, cooldown, message, note}
static var _loaded := false

## Load every abilities workbook in a directory. Translation: point at another locale dir.
static func load_dir(dir_path: String = DIR) -> void:
	_abilities.clear()
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
	reader.close()

static func _to_float(cell) -> float:
	var s := str(cell).strip_edges()
	return float(s) if s != "" else 0.0

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
	var result: Array = []
	for key in _abilities.keys():
		if str(key).begins_with(prefix):
			result.append(get_ability(key))
	return result
