class_name DialogueData

## Loads dialogue from CSV. Single source of truth for all text in the game.
## CSV columns: key, speaker, style, wait, text, context
##
## Usage:
##   DialogueData.load_csv("res://data/dialogue/en.csv")
##   var line = DialogueData.get_line("aster_sim.ron.greeting")
##   dialogue_box.say(line.text, line.speaker, line.style, line.wait)
##
## For translation: load a different CSV (e.g. "res://data/dialogue/ja.csv")

static var _lines: Dictionary = {}  # key → DialogueLine
static var _loaded := false

## Call once at startup or when switching language
static func load_csv(path: String) -> void:
	_lines.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("DialogueData: Could not open %s" % path)
		return

	# Read header
	var header_line := file.get_csv_line()
	# Find column indices
	var col_key := _find_col(header_line, "key")
	var col_speaker := _find_col(header_line, "speaker")
	var col_style := _find_col(header_line, "style")
	var col_wait := _find_col(header_line, "wait")
	var col_text := _find_col(header_line, "text")
	var col_context := _find_col(header_line, "context")

	if col_key < 0 or col_text < 0:
		push_error("DialogueData: CSV missing required columns (key, text)")
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
		line.text = row[col_text].strip_edges() if col_text < row.size() else ""
		line.context = row[col_context].strip_edges() if col_context >= 0 and col_context < row.size() else ""

		# Style "thought" is treated as style "normal" with speaker="" for the dialogue box
		if line.style == "thought":
			line.is_thought = true
			line.style = "normal"

		_lines[line.key] = line

	_loaded = true

static func _find_col(header: PackedStringArray, name: String) -> int:
	for i in range(header.size()):
		if header[i].strip_edges().to_lower() == name.to_lower():
			return i
	return -1

## Get a single dialogue line by key
static func get_line(key: String) -> DialogueLine:
	if not _loaded:
		load_csv("res://data/dialogue/en.csv")
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
		load_csv("res://data/dialogue/en.csv")
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

## Send a line directly to a dialogue box node
static func say_to(dialogue_box: Node, key: String) -> void:
	var line := get_line(key)
	if line.is_thought:
		# Thoughts use a different display path — caller handles this
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
