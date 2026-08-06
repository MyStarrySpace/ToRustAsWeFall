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

var _web_e2e_enabled := false
var _web_e2e_bridge = null


func _ready() -> void:
	if OS.has_feature("web") and _web_query_value("scene") == "elevator":
		call_deferred("_launch_elevator_web_probe")
		return
	_setup_web_e2e_probe()
	$MenuColumn/PlayButton.grab_focus()


func _process(_delta: float) -> void:
	if not _web_e2e_enabled:
		return
	var fragments_button := $MenuColumn/FragmentsButton as Control
	var viewport_size := get_viewport_rect().size
	var button_rect := fragments_button.get_global_rect()
	_publish_web_e2e_state({
		"version": 1,
		"stage": "main_menu",
		"ready": fragments_button.is_visible_in_tree(),
		"viewport": {"width": viewport_size.x, "height": viewport_size.y},
		"click_targets": {
			"fragments": {
				"x": button_rect.get_center().x,
				"y": button_rect.get_center().y,
				"visible": fragments_button.is_visible_in_tree(),
			},
		},
	})


## Browser release QA still enters through the production Fragments button. The query only chooses
## the registry entry that button will open; it cannot drive a character or mutate level state.
func _setup_web_e2e_probe() -> void:
	if not OS.has_feature("web") or _web_query_value("e2e") != "1":
		set_process(false)
		return
	var requested_fragment := _web_query_value("fragment")
	var requested_entry: Dictionary = \
		FragmentPreviewScript.get_web_e2e_preview_entry(requested_fragment)
	if requested_fragment == "" or requested_entry.is_empty():
		push_error("MainMenu: invalid e2e fragment '%s'" % requested_fragment)
		set_process(false)
		return
	# E2E-only contract fixtures never enter the ordinary fragment picker or its
	# persistent id route. The query selects one immutable launch entry; play still
	# begins only when the browser clicks the real Fragments button below.
	FragmentPreviewScript.menu_launch_entry = requested_entry.duplicate(true)
	_web_e2e_bridge = Engine.get_singleton("JavaScriptBridge")
	_web_e2e_enabled = _web_e2e_bridge != null
	set_process(_web_e2e_enabled)


func _publish_web_e2e_state(payload: Dictionary) -> void:
	if _web_e2e_bridge == null:
		return
	_web_e2e_bridge.call(
		"eval",
		"window.__trawfE2E = %s;" % JSON.stringify(payload),
		true
	)


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
