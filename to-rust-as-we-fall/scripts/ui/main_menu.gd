extends Control

## The game's entry point. Built procedurally (the project keeps .tscn files thin). Each option boots a scene via
## change_scene_to_file — Play into the story intro, Level Builder into the in-game builder, Fragments into the
## chunk/roguelike picker. The builder IS the game in a builder mode; this is how you reach it.

const TERMINAL_GREEN := Color(0.36, 0.91, 0.5)      # #5ce87f — the project's terminal green
const DIM := Color(0.55, 0.62, 0.68)

const PLAY_SCENE := "res://scenes/tutorial/peris_sim.tscn"
const BUILDER_SCENE := "res://scenes/builder/level_builder.tscn"
const FRAGMENTS_SCENE := "res://scenes/fragments/fragment_preview.tscn"
const CREATURE_SHOWCASE_ID := "creature_grammar"
const ARCHITECTURE_SHOWCASE_ID := "architecture_showcase"

const FragmentPreviewScript := preload("res://scripts/fragments/fragment_preview_sequence.gd")

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.04, 0.05)
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.add_theme_constant_override("separation", 14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)

	var title := Label.new()
	title.text = "TO RUST AS WE FALL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", TERMINAL_GREEN)
	col.add_child(title)

	var sub := Label.new()
	sub.text = "// iron rises. the cells hold."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", DIM)
	col.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	col.add_child(spacer)

	_add_menu_button(col, "Play", _on_play)
	_add_menu_button(col, "Level Builder", _on_builder)
	_add_menu_button(col, "Fragments", _on_fragments)
	_add_menu_button(col, "Creature Showcase", _on_creatures)
	_add_menu_button(col, "Architecture Showcase", _on_architecture)
	_add_menu_button(col, "Quit", _on_quit)

func _add_menu_button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 46)
	b.add_theme_font_size_override("font_size", 20)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _on_play() -> void:
	get_tree().change_scene_to_file(PLAY_SCENE)

func _on_builder() -> void:
	get_tree().change_scene_to_file(BUILDER_SCENE)

func _on_fragments() -> void:
	get_tree().change_scene_to_file(FRAGMENTS_SCENE)

func _on_creatures() -> void:
	# Boot the fragment preview DIRECTLY into the creature gallery (the static one-shot override —
	# change_scene_to_file can't set exports).
	FragmentPreviewScript.menu_launch_id = CREATURE_SHOWCASE_ID
	get_tree().change_scene_to_file(FRAGMENTS_SCENE)

func _on_architecture() -> void:
	FragmentPreviewScript.menu_launch_id = ARCHITECTURE_SHOWCASE_ID
	get_tree().change_scene_to_file(FRAGMENTS_SCENE)

func _on_quit() -> void:
	get_tree().quit()
