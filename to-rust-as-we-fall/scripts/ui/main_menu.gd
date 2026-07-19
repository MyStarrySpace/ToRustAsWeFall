extends Control

## The game's entry point. Its stable layout and signal wiring live in main_menu.tscn;
## this script only handles navigation behavior.

const PLAY_SCENE := "res://scenes/tutorial/peris_sim.tscn"
const ELEVATOR_SCENE := "res://scenes/tutorial/elevator.tscn"
const BUILDER_SCENE := "res://scenes/builder/level_builder.tscn"
const FRAGMENTS_SCENE := "res://scenes/fragments/fragment_preview.tscn"
const CREATURE_SHOWCASE_ID := "creature_grammar"
const ARCHITECTURE_SHOWCASE_ID := "architecture_showcase"

const FragmentPreviewScript := preload("res://scripts/fragments/fragment_preview_sequence.gd")


func _ready() -> void:
	if OS.has_feature("web") and _web_query_value("scene") == "elevator":
		call_deferred("_launch_elevator_web_probe")
		return
	$MenuColumn/PlayButton.grab_focus()


func _web_query_value(name: String) -> String:
	var bridge := Engine.get_singleton("JavaScriptBridge")
	if bridge == null:
		return ""
	return str(bridge.call(
		"eval",
		"new URLSearchParams(window.location.search).get('%s') || ''" % name,
		true
	))


## Web exports normally begin at the campaign menu. This opt-in probe keeps browser QA fast while
## preserving the exact production scene and authored chunk lifecycle being tested.
func _launch_elevator_web_probe() -> void:
	var packed := load(ELEVATOR_SCENE) as PackedScene
	if packed == null:
		push_error("MainMenu: elevator browser probe could not load")
		return
	var elevator := packed.instantiate()
	elevator.set("start_chunk", _web_query_value("start_chunk"))
	get_tree().root.add_child(elevator)
	get_tree().current_scene = elevator
	queue_free()


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
