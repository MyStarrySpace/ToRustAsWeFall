extends Control

## The game's entry point. Its stable layout and signal wiring live in main_menu.tscn;
## this script only handles navigation behavior.

const PLAY_SCENE := "res://scenes/tutorial/peris_sim.tscn"
const BUILDER_SCENE := "res://scenes/builder/level_builder.tscn"
const FRAGMENTS_SCENE := "res://scenes/fragments/fragment_preview.tscn"
const CREATURE_SHOWCASE_ID := "creature_grammar"
const ARCHITECTURE_SHOWCASE_ID := "architecture_showcase"

const FragmentPreviewScript := preload("res://scripts/fragments/fragment_preview_sequence.gd")


func _ready() -> void:
	$MenuColumn/PlayButton.grab_focus()


func _on_play() -> void:
	get_tree().change_scene_to_file(PLAY_SCENE)


func _on_builder() -> void:
	get_tree().change_scene_to_file(BUILDER_SCENE)


func _on_fragments() -> void:
	get_tree().change_scene_to_file(FRAGMENTS_SCENE)


func _on_creatures() -> void:
	# Boot directly into the creature gallery; change_scene_to_file cannot set exports.
	FragmentPreviewScript.menu_launch_id = CREATURE_SHOWCASE_ID
	get_tree().change_scene_to_file(FRAGMENTS_SCENE)


func _on_architecture() -> void:
	FragmentPreviewScript.menu_launch_id = ARCHITECTURE_SHOWCASE_ID
	get_tree().change_scene_to_file(FRAGMENTS_SCENE)


func _on_quit() -> void:
	get_tree().quit()
