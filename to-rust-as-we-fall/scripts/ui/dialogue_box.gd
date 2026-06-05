extends CanvasLayer

## Bottom-of-screen dialogue display: typewriter effect + a constant-size,
## scrolling transcript. Earlier lines stay visible but faded above; the line in
## progress sits full-opacity at the bottom. The mouse wheel reviews history; a
## new line re-follows the bottom.
##
## Timing authority: the dialogue box does NOT advance itself. Its owner (the
## tutorial sequence) feeds elapsed time in via advance_ui_time(), so a single
## clock drives real play, headless runs, the CLI, and tests identically.
## See .claude/CLAUDE.md "Dialogue & Time Authority".
##
## Advancement is click-driven by default: a click finishes the current page's
## typing, a second click advances. Auto-advance (type, hold a beat, advance on
## its own) is opt-in via the Settings autoload (auto_advance_dialogue). The data
## layer always advances through awaiting_advance() so headless/CLI never stall.
##
## Long lines paginate: the typewriter still gates page by page, but _current_text
## stays the full logical line and line_displayed/dialogue_finished fire once per
## line. Text speed is scaled by the Settings autoload.

@export var chars_per_second := 30.0
## The one shared reading beat: when auto-advance is enabled, an auto line
## (wait == false) types out, holds this many ticks, then advances. Never tuned
## per line. Acknowledge lines (wait == true) ignore this and wait for
## request_advance() regardless of the auto-advance setting.
@export var default_hold_time := 2.0

## A line longer than this splits into sentence-packed pages you advance through.
const PAGE_MAX_CHARS := 180
const READABLE_WIDTH := 720.0
## Fixed inner height of the scrolling transcript view. The panel stays a
## constant size; older lines scroll up out of view instead of growing it.
const SCROLL_HEIGHT := 104.0
## Newest-kept cap on retained transcript entries (bounds memory in long scenes).
const TRANSCRIPT_MAX := 40
## Pixels per mouse-wheel notch when reviewing history.
const SCROLL_STEP := 36.0
## Faded color for previously-shown lines in the transcript.
const HISTORY_COLOR_HEX := "55565f"

var _queue: Array[Dictionary] = []
var _current_text := ""
var _current_speaker := ""
var _displayed_chars := 0.0
var _hold_timer := 0.0
var _active := false
var _waiting_for_input := false
## Cutscene mode: the owning sequence forces auto-advance for dialogue tied to a scripted
## cutscene, so lines keep pace with the on-screen action (characters walking the corridor)
## instead of blocking on a click — regardless of the player's auto-advance preference, and
## even for `wait` lines. Hold F still speeds it; the UI lane is F-scaled.
var _cutscene_mode := false
var _style := "normal"  # "normal", "poem", "data", "fragment", "whisper"

# Pagination: [start, end) char windows over _current_text.
var _pages: Array[Vector2i] = [Vector2i(0, 0)]
var _page_index := 0

## Completed lines shown earlier in this conversation: {text, speaker, style}.
var _transcript: Array[Dictionary] = []
## Prebuilt bbcode for the faded history (rebuilt only when _transcript changes).
var _history_cache := ""
## True while the player has scrolled up to review; suspends auto-follow until
## the next line.
var _user_scrolled := false

var _panel: PanelContainer
var _speaker_label: Label
var _scroll: ScrollContainer
var _text_label: RichTextLabel
var _continue_hint: Label
var _hint_tween: Tween

signal dialogue_finished()
signal line_displayed(text: String)

func _ready() -> void:
	layer = 15
	_build_ui()
	_panel.visible = false

func _build_ui() -> void:
	# Bottom-centered, constant-size panel capped to a readable column width.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	margin.offset_top = -(SCROLL_HEIGHT + 96.0)
	margin.offset_bottom = 0
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size.x = READABLE_WIDTH
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.02, 0.04, 0.93)
	panel_style.border_color = Color(0.18, 0.2, 0.28, 0.7)
	panel_style.set_border_width_all(1)
	panel_style.border_width_left = 3
	panel_style.set_corner_radius_all(3)
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 14
	panel_style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vbox)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 12)
	_speaker_label.add_theme_color_override("font_color", Color(0.45, 0.65, 0.9, 0.95))
	_speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_speaker_label)

	# Fixed-height viewport: the transcript label grows inside, the box clips +
	# scrolls. mouse_filter IGNORE so clicks/wheel reach _unhandled_input, where
	# we drive advance (click) and review (wheel) ourselves.
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(READABLE_WIDTH - 40.0, SCROLL_HEIGHT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_scroll)

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.scroll_active = false
	_text_label.custom_minimum_size.x = READABLE_WIDTH - 40.0
	_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_label.add_theme_font_size_override("normal_font_size", 16)
	_text_label.add_theme_constant_override("line_separation", 5)
	_text_label.add_theme_color_override("default_color", Color(0.78, 0.78, 0.84))
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_text_label)

	_continue_hint = Label.new()
	_continue_hint.text = ""
	_continue_hint.add_theme_font_size_override("font_size", 12)
	_continue_hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7, 0.85))
	_continue_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_continue_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_continue_hint)

	# Gentle pulse so the continue indicator reads as "waiting on you".
	_hint_tween = create_tween().set_loops()
	_hint_tween.tween_property(_continue_hint, "modulate:a", 0.35, 0.7).set_trans(Tween.TRANS_SINE)
	_hint_tween.tween_property(_continue_hint, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)

# --- Effective speed (base × style × Settings text-speed preset) ---

func _settings() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("Settings")

func _effective_cps() -> float:
	var cps := chars_per_second
	if _style == "fragment":
		cps *= 0.4
	elif _style == "poem":
		cps *= 0.7
	elif _style == "whisper":
		cps *= 0.25
	var s := _settings()
	if s != null and s.has_method("text_cps_scale"):
		cps *= float(s.call("text_cps_scale"))
	return cps

func _effective_hold() -> float:
	var s := _settings()
	if s != null and s.has_method("text_hold_scale"):
		return default_hold_time * float(s.call("text_hold_scale"))
	return default_hold_time

## Auto-advance (type, hold, advance on its own) is opt-in. Default: click-only.
func _auto_advance_enabled() -> bool:
	if _cutscene_mode:
		return true
	var s := _settings()
	if s != null and s.has_method("is_auto_advance_dialogue"):
		return bool(s.call("is_auto_advance_dialogue"))
	return false

## Force auto-advance for a scripted cutscene (e.g. Tag Day): lines advance on the shared
## reading beat (hold F to speed) and never block on a click — even `wait` lines — so the
## dialogue stays synced to the on-screen action. The owning sequence sets this.
func set_cutscene_mode(on: bool) -> void:
	_cutscene_mode = on

# --- Advancement ---

## Advance the dialogue by delta_ticks of dialogue time. The owner feeds this
## (real play, headless, CLI, tests all call it), so the box has no clock of
## its own. delta_ticks is already fast-forward-scaled by the caller.
func advance_ui_time(delta_ticks: float) -> void:
	if not _active:
		return
	var dt := maxf(0.0, delta_ticks)
	var page_end := _pages[_page_index].y

	if _displayed_chars < float(page_end):
		# Typing the current page.
		_displayed_chars += _effective_cps() * dt
		_render_visible()
		if int(_displayed_chars) >= page_end:
			_displayed_chars = float(page_end)
			_on_page_typed()
		return

	# Current page fully shown. With auto-advance off (default) the box waits for
	# an explicit advance (a click or the data layer); the clock does nothing.
	if not _auto_advance_enabled():
		return
	if _is_last_page():
		# A cutscene line never blocks on a click — it rides the shared beat so it stays in
		# step with the on-screen action (a paused-for-input line would desync the cutscene).
		if _waiting_for_input and not _cutscene_mode:
			return  # await request_advance()
		_hold_timer -= dt
		if _hold_timer <= 0.0:
			_advance()
	else:
		# Intermediate page gate: hold the beat, then reveal the next page.
		_hold_timer -= dt
		if _hold_timer <= 0.0:
			_next_page()

## Explicit advance: a real click and any data-layer command share this path.
## Completes the current page's typing; once a page is shown, moves to the next
## page or (on the last page) ends the line.
func request_advance() -> void:
	if not _active:
		return
	_user_scrolled = false
	var page_end := _pages[_page_index].y
	if _displayed_chars < float(page_end):
		_displayed_chars = float(page_end)
		_render_visible()
		_on_page_typed()
		return
	if _is_last_page():
		_advance()
	else:
		_next_page()

## True when the box can't progress on its own and is waiting for an advance
## (a click, or a data-layer advance). The headless/CLI drivers poll this and
## call request_advance() — the equivalent of the player clicking — so click-only
## mode never stalls them.
func awaiting_advance() -> bool:
	if not _active:
		return false
	if _displayed_chars < float(_pages[_page_index].y):
		return false
	if _is_last_page():
		return (_waiting_for_input and not _cutscene_mode) or not _auto_advance_enabled()
	return not _auto_advance_enabled()

func _is_last_page() -> bool:
	return _page_index >= _pages.size() - 1

## Called when the current page has finished typing.
func _on_page_typed() -> void:
	if _is_last_page():
		line_displayed.emit(_current_text)
	_hold_timer = _effective_hold()
	_show_continue_hint()

func _next_page() -> void:
	_page_index += 1
	# _displayed_chars already sits at the next page's start (== prev page end).
	_continue_hint.text = ""
	_render_visible()

func _render_visible() -> void:
	var page := _pages[_page_index]
	var count := mini(int(_displayed_chars), page.y)
	# The in-progress line accumulates from its start, so a multi-page line builds
	# up in the scroll view (pages are reading gates, not separate screens).
	_text_label.text = _compose_text(_current_text.substr(0, count))
	_follow_bottom()

## Faded history (cached) above + the full-opacity in-progress text at the bottom.
func _compose_text(current_visible: String) -> String:
	if _history_cache == "":
		return current_visible
	return _history_cache + "\n\n" + current_visible

func _history_line_bbcode(entry: Dictionary) -> String:
	var prefix := ""
	var sp := String(entry.get("speaker", ""))
	if sp != "":
		prefix = "%s  " % sp
	return "[color=#%s]%s%s[/color]" % [HISTORY_COLOR_HEX, prefix, String(entry.get("text", ""))]

func _append_to_transcript(text: String, speaker: String, style: String) -> void:
	_transcript.append({"text": text, "speaker": speaker, "style": style})
	while _transcript.size() > TRANSCRIPT_MAX:
		_transcript.pop_front()
	_rebuild_history_cache()

func _rebuild_history_cache() -> void:
	var parts: Array[String] = []
	for entry in _transcript:
		parts.append(_history_line_bbcode(entry))
	_history_cache = "\n\n".join(parts)

## Pin the scroll to the newest text unless the player has scrolled up to review.
func _follow_bottom() -> void:
	if _scroll == null or _user_scrolled:
		return
	_scroll.set_deferred("scroll_vertical", 1 << 20)

func _scroll_by(amount: float) -> void:
	if _scroll == null:
		return
	_user_scrolled = true
	_scroll.scroll_vertical = maxi(0, _scroll.scroll_vertical + int(amount))
	# Re-follow if the player has scrolled back to the bottom.
	var sb := _scroll.get_v_scroll_bar()
	if sb != null and float(_scroll.scroll_vertical) >= sb.max_value - sb.page - 1.0:
		_user_scrolled = false

func _show_continue_hint() -> void:
	if _pages.size() > 1:
		_continue_hint.text = "%d / %d   ▸" % [_page_index + 1, _pages.size()]
	else:
		_continue_hint.text = "▸"

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				request_advance()
				if is_inside_tree():
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP:
				_scroll_by(-SCROLL_STEP)
				if is_inside_tree():
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_by(SCROLL_STEP)
				if is_inside_tree():
					get_viewport().set_input_as_handled()

func _advance() -> void:
	if _queue.is_empty():
		_active = false
		_panel.visible = false
		_transcript.clear()
		_history_cache = ""
		dialogue_finished.emit()
		return
	# The line that just finished joins the faded history above the next one.
	_append_to_transcript(_current_text, _current_speaker, _style)
	_show_next()

func _show_next() -> void:
	var entry: Dictionary = _queue.pop_front()
	_current_text = entry.get("text", "")
	_current_speaker = entry.get("speaker", "")
	_style = entry.get("style", "normal")
	_waiting_for_input = entry.get("wait_for_input", false)
	_displayed_chars = 0.0
	_hold_timer = 0.0
	_user_scrolled = false
	_continue_hint.text = ""
	_pages = _paginate(_current_text)
	_page_index = 0

	_speaker_label.text = _current_speaker
	_speaker_label.visible = _current_speaker != ""

	# Style the panel + in-progress text color based on type.
	var panel_style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	match _style:
		"poem":
			_text_label.add_theme_color_override("default_color", Color(0.62, 0.62, 0.68))
			panel_style.border_color = Color(0.3, 0.22, 0.14, 0.6)
			_speaker_label.add_theme_color_override("font_color", Color(0.55, 0.45, 0.4, 0.8))
		"fragment":
			_text_label.add_theme_color_override("default_color", Color(0.52, 0.47, 0.42, 0.85))
			panel_style.border_color = Color(0.4, 0.16, 0.12, 0.6)
			_speaker_label.add_theme_color_override("font_color", Color(0.6, 0.4, 0.35, 0.8))
		"whisper":
			_text_label.add_theme_color_override("default_color", Color(0.45, 0.43, 0.4, 0.5))
			panel_style.border_color = Color(0.2, 0.12, 0.1, 0.4)
			_speaker_label.add_theme_color_override("font_color", Color(0.4, 0.36, 0.34, 0.6))
		"data":
			_text_label.add_theme_color_override("default_color", Color(0.35, 0.55, 0.75))
			panel_style.border_color = Color(0.18, 0.32, 0.5, 0.7)
			_speaker_label.add_theme_color_override("font_color", Color(0.35, 0.6, 0.85, 0.9))
		_:
			_text_label.add_theme_color_override("default_color", Color(0.78, 0.78, 0.84))
			panel_style.border_color = Color(0.18, 0.2, 0.28, 0.7)
			_speaker_label.add_theme_color_override("font_color", Color(0.45, 0.65, 0.9, 0.95))

	_panel.visible = true
	_active = true
	_render_visible()

# --- Pagination ---

## Split text into [start, end) char windows, packing whole sentences up to
## PAGE_MAX_CHARS. A short line is a single page (no behavior change).
func _paginate(text: String) -> Array[Vector2i]:
	var n := text.length()
	var pages: Array[Vector2i] = []
	if n <= PAGE_MAX_CHARS:
		pages.append(Vector2i(0, n))
		return pages

	# Sentence boundary offsets: just past the whitespace following . ! ?
	var boundaries: Array[int] = []
	var i := 0
	while i < n:
		var c := text[i]
		if c == "." or c == "!" or c == "?":
			var j := i + 1
			while j < n and (text[j] == '"' or text[j] == "'" or text[j] == ")" or text[j] == "." or text[j] == "!" or text[j] == "?"):
				j += 1
			var k := j
			while k < n and text[k] == " ":
				k += 1
			if k > j and k < n:
				boundaries.append(k)
			i = maxi(k, i + 1)
		else:
			i += 1

	var start := 0
	var bi := 0
	while start < n:
		var page_end := n
		if n - start > PAGE_MAX_CHARS:
			var last_ok := -1
			for idx in range(bi, boundaries.size()):
				if boundaries[idx] - start <= PAGE_MAX_CHARS:
					last_ok = boundaries[idx]
				else:
					break
			page_end = last_ok if last_ok > start else mini(start + PAGE_MAX_CHARS, n)
		while bi < boundaries.size() and boundaries[bi] <= page_end:
			bi += 1
		pages.append(Vector2i(start, page_end))
		start = page_end
	return pages

# --- Public API ---

## Queue a single line of dialogue
func say(text: String, speaker := "", style := "normal", wait := false) -> void:
	_queue.append({
		"text": text,
		"speaker": speaker,
		"style": style,
		"wait_for_input": wait,
	})
	if _queue.size() > 3:
		push_warning("DialogueBox: queue depth %d; upstream timing may be pushing lines too fast" % _queue.size())
	if not _active:
		_show_next()

## Queue multiple lines
func say_sequence(lines: Array[Dictionary]) -> void:
	for line in lines:
		_queue.append(line)
	if not _active:
		_show_next()

## Force clear
func clear() -> void:
	_queue.clear()
	_current_text = ""
	_current_speaker = ""
	_displayed_chars = 0.0
	_hold_timer = 0.0
	_waiting_for_input = false
	_active = false
	_pages = [Vector2i(0, 0)]
	_page_index = 0
	_transcript.clear()
	_history_cache = ""
	_user_scrolled = false
	_panel.visible = false
	if _text_label != null:
		_text_label.text = ""
	if _continue_hint != null:
		_continue_hint.text = ""

func is_active() -> bool:
	return _active
