extends CanvasLayer

@onready var grid_map: GridMap
@onready var editor: Node3D

var _palette_buttons: Array[Button] = []
var _info_label: Label
var _rotation_label: Label

const BLOCK_LABELS: Array[String] = [
	"1: Wall", "2: Floor", "3: Pipe (auto)", "4: Flora",
	"5: Iron Bloom", "6: Terminal", "7: Shelter", "8: Membrane"
]

const BLOCK_COLORS: Array[Color] = [
	Color(0.45, 0.35, 0.28),
	Color(0.25, 0.25, 0.28),
	Color(0.3, 0.6, 0.55),
	Color(0.2, 0.65, 0.4),
	Color(0.7, 0.3, 0.1),
	Color(0.15, 0.4, 0.6),
	Color(0.25, 0.35, 0.6),
	Color(0.55, 0.4, 0.48),
]

const ROTATION_LABELS: Array[String] = ["0°", "90°", "180°", "270°"]

func _ready() -> void:
	editor = get_parent()
	grid_map = editor.get_node("GridMap")

	_build_ui()

	# Connect to editor signals
	editor.block_changed.connect(_on_block_changed)
	editor.orientation_changed.connect(_on_orientation_changed)

func _build_ui() -> void:
	# Controls info — top left
	_info_label = Label.new()
	_info_label.position = Vector2(12, 12)
	_info_label.add_theme_font_size_override("font_size", 13)
	_info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 0.85))
	_info_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_info_label.add_theme_constant_override("shadow_offset_x", 1)
	_info_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_info_label)

	# Palette — bottom of screen
	var palette_container := VBoxContainer.new()
	palette_container.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	palette_container.position = Vector2(12, -12)
	palette_container.offset_top = -300
	palette_container.offset_bottom = -12
	add_child(palette_container)

	var title := Label.new()
	title.text = "BLOCKS"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	palette_container.add_child(title)

	for i in range(BLOCK_LABELS.size()):
		var btn := Button.new()
		btn.text = BLOCK_LABELS[i]
		btn.custom_minimum_size = Vector2(140, 28)
		btn.add_theme_font_size_override("font_size", 12)

		# Style
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.12, 0.14, 0.85)
		style.border_color = BLOCK_COLORS[i].darkened(0.3)
		style.set_border_width_all(2)
		style.set_corner_radius_all(3)
		style.set_content_margin_all(4)
		btn.add_theme_stylebox_override("normal", style)

		var style_hover := style.duplicate()
		style_hover.bg_color = Color(0.18, 0.18, 0.2, 0.9)
		style_hover.border_color = BLOCK_COLORS[i]
		btn.add_theme_stylebox_override("hover", style_hover)

		var style_pressed := style.duplicate()
		style_pressed.bg_color = BLOCK_COLORS[i].darkened(0.5)
		style_pressed.border_color = BLOCK_COLORS[i].lightened(0.2)
		btn.add_theme_stylebox_override("pressed", style_pressed)

		var idx := i
		btn.pressed.connect(func(): editor.select_block(idx))
		palette_container.add_child(btn)
		_palette_buttons.append(btn)

	# Rotation indicator
	_rotation_label = Label.new()
	_rotation_label.add_theme_font_size_override("font_size", 12)
	_rotation_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	palette_container.add_child(_rotation_label)

	_highlight_selected(0)

func _process(_delta: float) -> void:
	var cell_count := grid_map.get_used_cells().size()
	var rot_idx: int = editor._rotation_index
	_info_label.text = "Left-click: Place | Right-click: Erase\n"
	_info_label.text += "Middle/Right-drag: Orbit | Shift+Mid: Pan | Scroll: Zoom\n"
	_info_label.text += "1-8: Select block | Q/E: Cycle | R: Rotate\n"
	_info_label.text += "\nBlocks: %d" % cell_count

	_rotation_label.text = "R: Rotate [%s]" % ROTATION_LABELS[rot_idx]

func _highlight_selected(index: int) -> void:
	for i in range(_palette_buttons.size()):
		var btn := _palette_buttons[i]
		if i == index:
			var active := StyleBoxFlat.new()
			active.bg_color = BLOCK_COLORS[i].darkened(0.5)
			active.border_color = BLOCK_COLORS[i].lightened(0.3)
			active.set_border_width_all(2)
			active.set_corner_radius_all(3)
			active.set_content_margin_all(4)
			btn.add_theme_stylebox_override("normal", active)
			btn.add_theme_color_override("font_color", Color.WHITE)
		else:
			var inactive := StyleBoxFlat.new()
			inactive.bg_color = Color(0.12, 0.12, 0.14, 0.85)
			inactive.border_color = BLOCK_COLORS[i].darkened(0.3)
			inactive.set_border_width_all(2)
			inactive.set_corner_radius_all(3)
			inactive.set_content_margin_all(4)
			btn.add_theme_stylebox_override("normal", inactive)
			btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))

func _on_block_changed(index: int) -> void:
	_highlight_selected(index)

func _on_orientation_changed(_rot: int) -> void:
	pass  # Rotation label updates in _process
