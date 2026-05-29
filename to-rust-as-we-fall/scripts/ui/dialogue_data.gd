class_name DialogueData

## Loads dialogue from per-scene CSV files. Single source of truth for all text.
## CSV columns: key, speaker, style, wait, text, context
##
## Usage:
##   DialogueData.load_dir("res://data/dialogue/en/")
##   var line = DialogueData.get_line("aster_sim.ron.greeting")
##   dialogue_box.say(line.text, line.speaker, line.style, line.wait)
##
## For translation: load a different directory (e.g. "res://data/dialogue/ja/")

static var _lines: Dictionary = {}  # key → DialogueLine
static var _loaded := false

## Load all dialogue files (xlsx and csv) in a directory
static func load_dir(dir_path: String) -> void:
	_lines.clear()
	var dir := DirAccess.open(dir_path)
	if not dir:
		push_error("DialogueData: Could not open directory %s" % dir_path)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			if file_name.ends_with(".xlsx"):
				_load_xlsx_file(dir_path.path_join(file_name))
			elif file_name.ends_with(".csv"):
				_load_csv_file(dir_path.path_join(file_name))
		file_name = dir.get_next()
	_loaded = true

## Load an xlsx workbook (each sheet becomes a batch of dialogue lines)
static func _load_xlsx_file(path: String) -> void:
	var reader := XlsxReader.new()
	if reader.open(path) != OK:
		push_error("DialogueData: Could not open %s" % path)
		return
	for sheet_name in reader.get_sheet_names():
		var rows := reader.get_sheet_data(sheet_name)
		if rows.is_empty():
			continue
		var first_row: Array = rows[0]
		var start := 1 if first_row.size() > 0 and str(first_row[0]).strip_edges().to_lower() == "key" else 0
		for i in range(start, rows.size()):
			var row: Array = rows[i]
			if row.size() < 5 or str(row[0]).strip_edges() == "":
				continue
			var line := DialogueLine.new()
			line.key = str(row[0]).strip_edges()
			line.speaker = str(row[1]).strip_edges() if row.size() > 1 else ""
			line.style = str(row[2]).strip_edges() if row.size() > 2 else "normal"
			line.wait = str(row[3]).strip_edges().to_lower() == "true" if row.size() > 3 else false
			line.text = str(row[4]).strip_edges() if row.size() > 4 else ""
			line.context = str(row[5]).strip_edges() if row.size() > 5 else ""
			if line.style == "thought":
				line.is_thought = true
				line.style = "normal"
			_lines[line.key] = line
	reader.close()

## Load a single CSV file (merges into existing lines, fallback for non-xlsx)
static func _load_csv_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("DialogueData: Could not open %s" % path)
		return

	var header_line := file.get_csv_line()
	var col_key := _find_col(header_line, "key")
	var col_speaker := _find_col(header_line, "speaker")
	var col_style := _find_col(header_line, "style")
	var col_wait := _find_col(header_line, "wait")
	var col_text := _find_col(header_line, "text")
	var col_context := _find_col(header_line, "context")

	if col_key < 0 or col_text < 0:
		push_error("DialogueData: CSV missing required columns (key, text) in %s" % path)
		return

	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() <= col_key or row[col_key].strip_edges() == "":
			continue

		var line := DialogueLine.new()
		line.key = row[col_key].strip_edges()
		line.speaker = row[col_speaker].strip_edges() if col_speaker >= 0 and col_speaker < row.size() else ""
		line.style = row[col_style].strip_edges() if col_style >= 0 and col_style < row.size() else "normal"
		line.wait = (row[col_wait].strip_edges().to_lower() == "true") if col_wait >= 0 and col_wait < row.size() else false
		var raw_text := row[col_text].strip_edges() if col_text < row.size() else ""
		line.text = raw_text.replace("|", "\n")
		line.context = row[col_context].strip_edges() if col_context >= 0 and col_context < row.size() else ""

		if line.style == "thought":
			line.is_thought = true
			line.style = "normal"

		_lines[line.key] = line

static func _find_col(header: PackedStringArray, name: String) -> int:
	for i in range(header.size()):
		if header[i].strip_edges().to_lower() == name.to_lower():
			return i
	return -1

## Get a single dialogue line by key
static func get_line(key: String) -> DialogueLine:
	if not _loaded:
		load_dir("res://data/dialogue/en/")
	if key in _lines:
		return _lines[key]
	push_warning("DialogueData: key not found: %s" % key)
	var fallback := DialogueLine.new()
	fallback.key = key
	fallback.text = "[MISSING: %s]" % key
	return fallback

## Get multiple lines by key prefix (e.g. "tag_day.poem" returns poem.01 through poem.14)
static func get_lines(prefix: String) -> Array[DialogueLine]:
	if not _loaded:
		load_dir("res://data/dialogue/en/")
	var result: Array[DialogueLine] = []
	# Collect all matching keys, sorted
	var keys: Array[String] = []
	for k in _lines.keys():
		if (k as String).begins_with(prefix):
			keys.append(k)
	keys.sort()
	for k in keys:
		result.append(_lines[k])
	return result

## Get text only (shorthand for simple cases)
static func text(key: String) -> String:
	return get_line(key).text

## Check whether a dialogue key exists in the loaded tables.
static func has_key(key: String) -> bool:
	if not _loaded:
		load_dir("res://data/dialogue/en/")
	return key in _lines

## Send a line directly to a dialogue box node
static func say_to(dialogue_box: Node, key: String) -> void:
	var line := get_line(key)
	if line.is_thought:
		# Thoughts use a separate display path.
		return
	dialogue_box.say(line.text, line.speaker, line.style, line.wait)

## Send multiple lines (by prefix) to a dialogue box
static func say_sequence_to(dialogue_box: Node, prefix: String) -> void:
	var lines := get_lines(prefix)
	for line in lines:
		dialogue_box.say(line.text, line.speaker, line.style, line.wait)

## Check if dialogue data is loaded
static func is_loaded() -> bool:
	return _loaded

## Dialogue line data container
class DialogueLine:
	var key := ""
	var speaker := ""
	var style := "normal"
	var wait := false
	var text := ""
	var context := ""
	var is_thought := false
