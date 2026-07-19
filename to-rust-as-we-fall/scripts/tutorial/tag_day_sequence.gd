@tool
extends "res://scripts/tutorial/tutorial_sequence.gd"

## Tag Day checkpoint, citizen failure, corridor walk, and Aster clearance.

const LevelDecoratorScript := preload("res://scripts/generation/level_decorator.gd")

var _data_overlay: CanvasLayer
var _bystanders: Array = []
var _citizen  # Node3D + npc.gd at device to Aster's right.
var _naturalizer_1  # Node3D + npc.gd
var _naturalizer_2  # Node3D + npc.gd
var _citizen_light: OmniLight3D  # Light above citizen's device
var _witness_interactables: Dictionary = {}
var _return_scanner_interactable: Area3D
var _witness_receipt_label: Label3D
var _witness_record_choice := ""
var _witness_record_resolved := false
var _return_scan_resolved := false
var _witness_auto_resolved := false
var _return_scan_auto_resolved := false
var _escort_field_interactables: Dictionary = {}
var _escort_field_order: Array[String] = []
var _escort_field_index := 0
var _escort_field_resolved := false
var _escort_field_auto_resolved := false
var _escort_presentation_finished := false
var _escort_started_tick := -1.0
var _escort_presentation_finished_tick := -1.0
var _escort_field_finished_tick := -1.0
var _escort_pending_site_id := ""
# Focused headless verification may replace the eleven shader-heavy evidence
# consoles with simple visible proxies. Normal game/runtime construction never
# sets this; witness/return visuals and all production field consoles stay full.
var focused_verifier_lightweight_station_visuals := false
# The focused pacing verifier needs one real scene-tree boot to prove that the
# authored interaction hooks wire up.  It can omit the shader-heavy production
# shell for that boot; normal game, desktop, Web, and editor construction leave
# this false and still build the complete checkpoint/corridor environment.
var focused_verifier_minimal_scene_boot := false

# Psy-Knapse device positions.
const DEVICE_SPACING := 2.2
const ASTER_DEVICE_POS := Vector3(6, 0, 0)
const CITIZEN_DEVICE_POS := Vector3(6 + DEVICE_SPACING, 0, 0)  # To Aster's right

# Naturalizer standing positions (near the back wall, out of the way)
const NK_STAND_POS_1 := Vector3(13.2, 0, -5.5)
const NK_STAND_POS_2 := Vector3(14.8, 0, -5.5)

# Corridor waypoints
const CORRIDOR_ENTRANCE := Vector3(14, 0, -8)
const CORRIDOR_A_END := Vector3(14, 0, -16)
const CORRIDOR_B_END := Vector3(24, 0, -17)
const CORRIDOR_C_END := Vector3(24, 0, -25)
const CORRIDOR_D_END := Vector3(19, 0, -27)
const DEAD_END := Vector3(17, 0, -28)

const BASE_NPC_SPEED := 2.0

# Tag Day's two player-owned beats. The observation seals live at the end of the
# escort corridor, so choosing a record and later returning to PSY-1 is a real
# there-and-back route rather than two buttons beside Aster's spawn.
const ASTER_CHECKPOINT_SPEED := 2.35
const WITNESS_PUBLIC_POS := Vector3(20, 0, -27)
const WITNESS_PRIVATE_POS := Vector3(17, 0, -28)
const WITNESS_WORK_SECONDS := 5.0
const RETURN_SCAN_WORK_SECONDS := 4.0
const ACTIVITY_GATE_FALLBACK_SECONDS := 45.0
const ESCORT_FIELD_FALLBACK_SECONDS := 300.0
const WITNESS_FALLBACK_TAG := "tag_day_witness_fallback"
const RETURN_SCAN_FALLBACK_TAG := "tag_day_return_scan_fallback"
const ESCORT_FIELD_FALLBACK_TAG := "tag_day_escort_field_fallback"
const LEGACY_PRESENTATION_SECONDS := 198.7

# The 16 authored poem/Naturalizer lines take 103.4 seconds at the dialogue
# box's default 30 cps (poem register 0.7x) and four-second corridor hold. The
# field circuit runs at the same time: it does not add a second copy of the
# presentation to the first-clear model.
const ESCORT_PRESENTATION_SECONDS := 103.4

# Aster reconstructs the incident while it is happening: the circuit begins at
# the failed PSY booth, crosses both halves of the live queue, audits the report
# and medical override, then follows the escort through each corridor turn. The
# verbs and positions are intentionally different work, not ten copies of one
# nearby button. Dwell is analysis/recording time and remains scheduler-backed.
const ESCORT_FIELD_SITE_DEFS := [
	{
		"id": "scan_failure",
		"name": "TagDayScanFailureRecord",
		"position": Vector3(8.2, 0, -3.0),
		"dwell": 8.0,
		"verb": "RECONSTRUCT FAILED SCAN",
		"label": "SCAN FAILURE",
		"color": Color(0.22, 0.62, 0.94),
	},
	{
		"id": "east_queue_witness",
		"name": "TagDayEastQueueWitness",
		"position": Vector3(24.0, 0, 4.0),
		"dwell": 9.0,
		"verb": "RECORD EAST QUEUE TESTIMONY",
		"label": "QUEUE WITNESS E",
		"color": Color(0.30, 0.74, 0.86),
	},
	{
		"id": "west_queue_witness",
		"name": "TagDayWestQueueWitness",
		"position": Vector3(0.0, 0, 4.0),
		"dwell": 9.0,
		"verb": "RECORD WEST QUEUE TESTIMONY",
		"label": "QUEUE WITNESS W",
		"color": Color(0.34, 0.70, 0.72),
	},
	{
		"id": "report_provenance",
		"name": "TagDayReportProvenance",
		"position": Vector3(26.0, 0, -5.0),
		"dwell": 10.0,
		"verb": "AUTHENTICATE REPORT ORIGIN",
		"label": "REPORT PROVENANCE",
		"color": Color(0.92, 0.48, 0.20),
	},
	{
		"id": "medical_override",
		"name": "TagDayMedicalOverride",
		"position": Vector3(1.0, 0, -5.0),
		"dwell": 10.0,
		"verb": "AUDIT MEDICAL OVERRIDE",
		"label": "MEDICAL OVERRIDE",
		"color": Color(0.84, 0.32, 0.24),
	},
	{
		"id": "custody_threshold",
		"name": "TagDayCustodyThreshold",
		"position": Vector3(14.0, 0, -10.0),
		"dwell": 9.0,
		"verb": "MARK CUSTODY THRESHOLD",
		"label": "CUSTODY THRESHOLD",
		"color": Color(0.86, 0.60, 0.22),
	},
	{
		"id": "gait_variance",
		"name": "TagDayGaitVariance",
		"position": Vector3(20.0, 0, -17.0),
		"dwell": 10.0,
		"verb": "CORRELATE ESCORT GAIT",
		"label": "GAIT VARIANCE",
		"color": Color(0.78, 0.54, 0.25),
	},
	{
		"id": "grip_telemetry",
		"name": "TagDayGripTelemetry",
		"position": Vector3(24.0, 0, -22.0),
		"dwell": 10.0,
		"verb": "CAPTURE GRIP TELEMETRY",
		"label": "GRIP TELEMETRY",
		"color": Color(0.84, 0.38, 0.22),
	},
	{
		"id": "iron_shadow",
		"name": "TagDayIronShadowSample",
		"position": Vector3(21.0, 0, -27.0),
		"dwell": 11.0,
		"verb": "SAMPLE IRON SHADOW",
		"label": "IRON SHADOW",
		"color": Color(0.72, 0.28, 0.18),
	},
	{
		"id": "report_echo",
		"name": "TagDayReportEchoTriangulation",
		"position": Vector3(24.0, 0, -19.0),
		"dwell": 12.0,
		"verb": "TRIANGULATE REPORT ECHO",
		"label": "REPORT ECHO",
		"color": Color(0.76, 0.30, 0.24),
	},
	{
		"id": "erasure_receipt",
		"name": "TagDayErasureReceipt",
		"position": Vector3(17.0, 0, -29.0),
		"dwell": 12.0,
		"verb": "SEAL ERASURE RECEIPT",
		"label": "ERASURE RECEIPT",
		"color": Color(0.62, 0.24, 0.20),
	},
]

# An OPEN walkable plane spanning the checkpoint room AND the twisted corridor down to the dead end
# (world X[-4,28], Z[-28,6]). No internal walls: the citizen's scripted command_walk_path waypoints carry
# the twist, so the grid just makes the cinematic's NPC movement cell-based + cooperative like the rest.
const GRID_ORIGIN := Vector3(-4.0, 0.0, -28.0)
const GRID_SIZE := Vector2i(32, 34)
var _grid: GridWorld

# --- Virtual overrides ---

func _build_scene() -> void:
	_build_grid()
	if focused_verifier_minimal_scene_boot:
		_build_focused_verifier_environment()
		return
	_build_environment()
	_build_corridor()
	_build_checkpoint_decorations()

func _build_focused_verifier_environment() -> void:
	var environment := Node3D.new()
	environment.name = "Environment"
	add_child(environment)
	# Later story beats recolor this light. Keeping it present makes the minimal
	# boot structurally complete even though the verifier never advances there.
	_citizen_light = OmniLight3D.new()
	_citizen_light.name = "FocusedVerifierCitizenLight"
	_citizen_light.position = CITIZEN_DEVICE_POS + Vector3(0, 2, 0)
	_citizen_light.light_color = Color(0.3, 0.3, 0.35)
	_citizen_light.light_energy = 1.5
	environment.add_child(_citizen_light)

func _build_grid() -> void:
	_grid = GridWorld.new()
	_grid.origin = GRID_ORIGIN
	_grid.create_room(GRID_SIZE.x, GRID_SIZE.y, false)

func _build_characters() -> void:
	var chars_node := Node3D.new()
	chars_node.name = "Characters"
	add_child(chars_node)

	# Aster at his Psy-Knapse device
	_player = _create_player_character("Aster", Color(0.29, 0.62, 1.0))
	_player.position = ASTER_DEVICE_POS + Vector3(0, 0.5, 0)
	if not Engine.is_editor_hint():
		_player.grid_world = _grid
	chars_node.add_child(_player)

	# Citizen (CZN-217) at the device to Aster's right
	_citizen = _create_npc("CZN-217", Color(0.5, 0.45, 0.4))
	_citizen.position = CITIZEN_DEVICE_POS
	chars_node.add_child(_citizen)

	# Other citizens at their own devices (further right)
	for i in range(3):
		var npc := _create_npc("CZN-%03d" % (400 + i), Color(0.4, 0.4, 0.45))
		npc.position = CITIZEN_DEVICE_POS + Vector3((i + 1) * DEVICE_SPACING, 0, 0)
		chars_node.add_child(npc)
		_bystanders.append(npc)

	# Naturalizers standing near the back wall
	_naturalizer_1 = _create_npc("NK-01", Color(0.85, 0.85, 0.88))
	_naturalizer_1.position = NK_STAND_POS_1
	chars_node.add_child(_naturalizer_1)

	_naturalizer_2 = _create_npc("NK-02", Color(0.85, 0.85, 0.88))
	_naturalizer_2.position = NK_STAND_POS_2
	chars_node.add_child(_naturalizer_2)

	if not Engine.is_editor_hint():
		_setup_game_camera(_player, Vector3(0, 10, 7))
		_bind_camera_to_level_bounds(_grid)
		# Dialogue is commonly advanced near the screen edge; enabling free-look on
		# that same frame must not launch the camera away from Aster. Tag Day teaches
		# WASD pan explicitly, so edge-scroll is deliberately disabled here.
		_camera.edge_scroll_margin = 0.0

func _register_characters() -> void:
	_game_state.grid = _grid
	# The checkpoint enforces an orderly walking pace. At 2.35 m/s the authored
	# witness-and-return route contributes about 38 seconds of active traversal.
	_register_gs_character("aster", _player, ASTER_CHECKPOINT_SPEED)
	_register_gs_character("citizen", _citizen, BASE_NPC_SPEED)

	for i in range(_bystanders.size()):
		var id := "czn_%d" % (400 + i)
		_register_gs_character(id, _bystanders[i], BASE_NPC_SPEED)

	_register_gs_character("nk1", _naturalizer_1, BASE_NPC_SPEED)
	_register_gs_character("nk2", _naturalizer_2, BASE_NPC_SPEED)

func _setup_ui() -> void:
	# Aster's data-view perception (managed by base class)
	_setup_perception("data", _player)
	# Data perception cannot read past the dead-end alcove.
	_perception_material.set_shader_parameter("blackout_pos", DEAD_END + Vector3(0, 1.0, -1.0))
	_perception_material.set_shader_parameter("blackout_radius", 4.0)
	_perception_material.set_shader_parameter("blackout_blend", 2.5)

	_data_overlay = preload("res://scenes/ui/tag_day_data_overlay.tscn").instantiate() as CanvasLayer
	add_child(_data_overlay)

func _begin() -> void:
	# Tag Day alternates player-owned checkpoint work with a scripted escort. During
	# that escort, dialogue rides the shared beat (hold F to speed) so the poem stays
	# synchronized with the citizen's walk instead of waiting on clicks.
	if _dialogue != null and _dialogue.has_method("set_cutscene_mode"):
		_dialogue.set_cutscene_mode(true)
	_build_active_play_stations()
	_start_arrive()

# --- Event-driven steps ---

func _start_arrive() -> void:
	_enter_step("arrive")
	_player.set_move_enabled(false)
	if not _game_state.character_arrived.is_connected(_on_character_arrived):
		_game_state.character_arrived.connect(_on_character_arrived)
	DialogueData.say_to(_dialogue, "tag_day.checkpoint_id")
	# Citizen tries small talk, Aster shuts them down, then scan fails
	_scheduler.schedule_after(2.0, func():
		_dialogue_chain(
			["tag_day.citizen.talk", "tag_day.aster.shush", "tag_day.citizen.scan",
			 "tag_day.murmur.01", "tag_day.murmur.02"],
			func(): _scheduler.schedule_after(1.5, _start_citizen_scan, "citizen_scan")
		)
	, "citizen_talk")

func _on_character_arrived(id: String) -> void:
	if id != "aster" or _escort_pending_site_id == "":
		return
	var site_id := _escort_pending_site_id
	_escort_pending_site_id = ""
	if not _escort_field_interactables.has(site_id):
		return
	var interactable: Node = _escort_field_interactables[site_id]
	if interactable != null and is_instance_valid(interactable) \
		and interactable.has_method("on_interaction_arrived"):
		interactable.call("on_interaction_arrived")

func _start_citizen_scan() -> void:
	_enter_step("citizen_scan")
	# The citizen's device scan fails
	_citizen_light.light_color = Color(0.8, 0.1, 0.05)
	_citizen_light.light_energy = 6.0
	DialogueData.say_to(_dialogue, "tag_day.scan_failed")
	# Do not open the player-controlled route beneath an unfinished cutscene line.
	# Switching cutscene mode off while this line is still active would freeze its
	# auto-advance and leave the dialogue panel covering the witness stations.
	if _dialogue != null and _dialogue.is_active():
		_dialogue.dialogue_finished.connect(_start_witness_record_choice, CONNECT_ONE_SHOT)
	else:
		_scheduler.schedule_after(0.1, _start_witness_record_choice, "witness_choice")

func _start_witness_record_choice() -> void:
	if not _enter_step("witness_choice"):
		return
	_witness_record_choice = ""
	_witness_record_resolved = false
	_witness_auto_resolved = false
	if _dialogue != null and _dialogue.has_method("set_cutscene_mode"):
		_dialogue.set_cutscene_mode(false)
	_player.set_move_enabled(true)
	_camera.enable_free_look(40.0)
	# Keep Aster in frame when control returns. Looking directly through the narrow
	# doorway can put the isometric camera behind the checkpoint wall in WebGL.
	_camera.recenter()
	_set_witness_interactables_enabled(true)
	_tutorial_prompt.show_prompt("[Interact] — follow the Wellness corridor and choose a witness record")
	# Compatibility is deliberately headless/test-only. A normal desktop or Web
	# session cannot pass this mandatory choice by standing still.
	if _legacy_compatibility_fallback_allowed():
		_scheduler.schedule_after(
			ACTIVITY_GATE_FALLBACK_SECONDS,
			func(): trigger_witness_record("public_log", true),
			WITNESS_FALLBACK_TAG
		)

func trigger_witness_record(choice_id: String, auto_resolved := false) -> void:
	if _current_step != "witness_choice" or _witness_record_resolved:
		return
	if not _witness_interactables.has(choice_id):
		return
	_witness_record_resolved = true
	_witness_record_choice = choice_id
	_witness_auto_resolved = auto_resolved
	# Do not cancel the tag from inside its own fallback callback: the native
	# scheduler's pop-next test seam is intentionally non-reentrant there.
	if not auto_resolved:
		_scheduler.cancel_tag(WITNESS_FALLBACK_TAG)
	if _player != null and _player.has_method("cancel_interaction_target"):
		_player.cancel_interaction_target()
	_game_state.command_stop("aster")
	_player.set_move_enabled(false)
	_camera.recenter()
	_set_witness_interactables_enabled(false)
	_tutorial_prompt.hide_prompt()
	_update_witness_receipt()
	if not auto_resolved:
		if choice_id == "private_trace":
			_show_thought("PRIVATE TRACE RETAINED  //  OMITTED FROM INCIDENT LEDGER")
		else:
			_show_thought("DUTY LOG FILED  //  INCIDENT INDEXED FOR COMPLIANCE")
	if _dialogue != null and _dialogue.has_method("set_cutscene_mode"):
		_dialogue.set_cutscene_mode(true)
	_scheduler.schedule_after(0.5, _start_naturalizers_grip, "nk_grip")

func _start_naturalizers_grip() -> void:
	_enter_step("naturalizers_grip")
	# Naturalizers approach slowly.
	_game_state.change_move_speed("nk1", 1.5)
	_game_state.change_move_speed("nk2", 1.5)
	_game_state.command_move_to_pos("nk1", CITIZEN_DEVICE_POS + Vector3(0, 0, -0.6))
	_game_state.command_move_to_pos("nk2", CITIZEN_DEVICE_POS + Vector3(0, 0, 0.6))
	# Let enforcers reach the citizen before walking.
	_scheduler.schedule_after(5.0, _begin_corridor_walk, "corridor_walk")
	# Report label appears above the escort during the walk
	_scheduler.schedule_after(10.0, _show_report_label, "report_label")

func _show_report_label() -> void:
	var lbl := Label3D.new()
	lbl.name = "ReportLabel"
	lbl.text = "REPORT FILED  |  CAUSE: MENTAL INSTABILITY"
	lbl.font_size = 48
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.8, 0.3, 0.2, 0.0)
	lbl.outline_modulate = Color(0, 0, 0, 0.5)
	lbl.outline_size = 4
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_naturalizer_1.add_child(lbl)
	lbl.position = Vector3(0, 2.0, 0)
	var tween := create_tween()
	tween.tween_property(lbl, "modulate:a", 0.9, 1.0)
	tween.tween_interval(8.0)
	tween.tween_property(lbl, "modulate:a", 0.0, 2.0)

func _begin_corridor_walk() -> void:
	_enter_step("corridor_walk")
	_escort_started_tick = _scheduler.get_current_tick()
	_escort_presentation_finished_tick = -1.0
	_escort_field_finished_tick = -1.0
	_escort_presentation_finished = false
	_escort_field_resolved = false
	_escort_field_auto_resolved = false
	_escort_field_index = 0
	_escort_pending_site_id = ""

	# Snap formation before the corridor walk.
	_game_state.command_stop("citizen")
	_game_state.command_stop("nk1")
	_game_state.command_stop("nk2")
	_citizen.global_position = Vector3(CITIZEN_DEVICE_POS.x, 0, CITIZEN_DEVICE_POS.z)
	_naturalizer_1.global_position = CITIZEN_DEVICE_POS + Vector3(0, 0, -0.6)
	_naturalizer_2.global_position = CITIZEN_DEVICE_POS + Vector3(0, 0, 0.6)

	# Slow walk leaves room for poem and fragments.
	_game_state.change_move_speed("citizen", 0.4)
	_game_state.change_move_speed("nk1", 0.4)
	_game_state.change_move_speed("nk2", 0.4)

	# Explicit corners prevent wall-cutting.
	var corner_AB := Vector3(14, 0, -17)   # Turn from A (along Z) to B (along X)
	var corner_BC := Vector3(24, 0, -17)   # Turn from B (along X) to C (along Z)
	var corner_CD := Vector3(24, 0, -27)   # Turn from C (along Z) to D (along X)

	var citizen_path: Array[Vector3] = [
		CORRIDOR_ENTRANCE,
		CORRIDOR_A_END, corner_AB,
		CORRIDOR_B_END, corner_BC,
		CORRIDOR_C_END, corner_CD,
		CORRIDOR_D_END, DEAD_END,
	]
	_game_state.command_walk_path("citizen", citizen_path)

	# NKs flank the citizen.
	var nk1_path: Array[Vector3] = [
		CORRIDOR_ENTRANCE + Vector3(-0.6, 0, 0),         # A: moving along -Z, offset in -X
		CORRIDOR_A_END + Vector3(-0.6, 0, 0),
		corner_AB + Vector3(-0.6, 0, 0),
		CORRIDOR_B_END + Vector3(0, 0, -0.6),            # B: moving along +X, offset in -Z
		corner_BC + Vector3(0, 0, -0.6),
		CORRIDOR_C_END + Vector3(-0.6, 0, 0),            # C: moving along -Z, offset in -X
		corner_CD + Vector3(-0.6, 0, 0),
		CORRIDOR_D_END + Vector3(0, 0, -0.6),            # D: moving along -X, offset in -Z
		DEAD_END + Vector3(-0.6, 0, 0),
	]
	_game_state.command_walk_path("nk1", nk1_path)

	var nk2_path: Array[Vector3] = [
		CORRIDOR_ENTRANCE + Vector3(0.6, 0, 0),          # A: offset in +X
		CORRIDOR_A_END + Vector3(0.6, 0, 0),
		corner_AB + Vector3(0.6, 0, 0),
		CORRIDOR_B_END + Vector3(0, 0, 0.6),             # B: offset in +Z
		corner_BC + Vector3(0, 0, 0.6),
		CORRIDOR_C_END + Vector3(0.6, 0, 0),             # C: offset in +X
		corner_CD + Vector3(0.6, 0, 0),
		CORRIDOR_D_END + Vector3(0, 0, 0.6),             # D: offset in +Z
		DEAD_END + Vector3(0.6, 0, 0),
	]
	_game_state.command_walk_path("nk2", nk2_path)

	# Poem and NK lines alternate in one scheduler chain.
	_dialogue.default_hold_time = 4.0
	_scheduler.schedule_after(2.0, _start_pan_prompt, "pan_prompt")
	# Capture the corridor_walk step before handing control back; contract drivers
	# still see the authored story beat, then the player-owned evidence substeps.
	_scheduler.schedule_after(0.1, _start_escort_field_record, "escort_field_record")

	# Merged stanzas fit inside the corridor walk.
	_dialogue_chain([
		"tag_day.poem.01",    # Stanza 1: idea/reality, motion/act
		"tag_day.nk_chat.01",
		"tag_day.poem.02",    # Falls the Shadow / For Thine is the Kingdom
		"tag_day.nk_chat.02",
		"tag_day.poem.03",    # Stanza 2: conception/creation, emotion/response
		"tag_day.nk_chat.03",
		"tag_day.nk_chat.04",
		"tag_day.poem.04",    # Falls the Shadow / Life is very long
		"tag_day.nk_chat.05",
		"tag_day.nk_chat.06",
		"tag_day.poem.05",    # Stanza 3: desire/spasm, potency/existence, essence/descent
		"tag_day.nk_chat.07",
		"tag_day.nk_chat.08",
		"tag_day.poem.06",    # Falls the Shadow / For Thine is the Kingdom
		"tag_day.nk_chat.09",
		"tag_day.nk_chat.10",
	], _on_poem_finished)


func _start_pan_prompt() -> void:
	_camera.enable_free_look(40.0)
	_tutorial_prompt.show_prompt(_camera_control_prompt_text())
	# F prompt appears after early banter.
	_scheduler.schedule_after(20.0, _show_fastforward_prompt, "ff_prompt")


func _camera_control_prompt_text() -> String:
	var pan_labels := [
		InputHints.label_for_action("camera_pan_forward", "W"),
		InputHints.label_for_action("camera_pan_left", "A"),
		InputHints.label_for_action("camera_pan_back", "S"),
		InputHints.label_for_action("camera_pan_right", "D"),
	]
	var rotate_left := InputHints.label_for_action("camera_rotate_left", "Q")
	var rotate_right := InputHints.label_for_action("camera_rotate_right", "E")
	return "%s — pan camera   •   %s / %s — rotate view" % [" / ".join(pan_labels), rotate_left, rotate_right]

func _show_fastforward_prompt() -> void:
	_tutorial_prompt.show_prompt("F — fast-forward time")

func _on_poem_finished() -> void:
	_escort_presentation_finished = true
	_escort_presentation_finished_tick = _scheduler.get_current_tick()
	_try_finish_escort_field_record()

func _start_fragments() -> void:
	_enter_step("fragments")
	_player.set_move_enabled(false)
	_set_all_escort_field_interactables_enabled(false)
	_scheduler.cancel_tag(ESCORT_FIELD_FALLBACK_TAG)
	_tutorial_prompt.hide_prompt()
	_dialogue.default_hold_time = 2.5
	# Stuttering prayer fragments with gaps, then "world ends" x3, then bang
	_dialogue_chain([
		"tag_day.fragment.01", "tag_day.fragment.02", "tag_day.fragment.03",
		"tag_day.fragment.04",
		"tag_day.fragment.07",
	], _on_bang, 1.5)

func _on_bang() -> void:
	_enter_step("neutralization")
	_camera.shake(0.5, 3.0)
	_dialogue.clear()
	_game_state.command_stop("citizen")
	_game_state.command_stop("nk1")
	_game_state.command_stop("nk2")
	_citizen.fade_out(2.0)
	_scheduler.schedule_after(2.5, _fragment_whimper, "whimper")

func _fragment_whimper() -> void:
	DialogueData.say_to(_dialogue, "tag_day.fragment.08")
	_dialogue.dialogue_finished.connect(func():
		_scheduler.schedule_after(1.0, _start_lockdown, "lockdown")
	, CONNECT_ONE_SHOT)

func _start_lockdown() -> void:
	_enter_step("lockdown")
	_citizen_light.light_energy = 4.0
	_camera.shake(0.15, 8.0)
	_dialogue_chain(
		["tag_day.lockdown", "tag_day.groan", "tag_day.report_blocked"],
		func(): _scheduler.schedule_after(1.5, _start_return_focus, "return_focus")
	)

func _start_return_focus() -> void:
	_enter_step("return_focus")
	_camera.disable_free_look()
	# Citizen's light dims back down
	_citizen_light.light_color = Color(0.3, 0.3, 0.35)
	_citizen_light.light_energy = 1.5
	_scheduler.schedule_after(0.2, _start_return_to_scanner, "return_to_scanner")

func _start_return_to_scanner() -> void:
	if not _enter_step("return_to_scanner"):
		return
	_return_scan_resolved = false
	_return_scan_auto_resolved = false
	if _dialogue != null and _dialogue.has_method("set_cutscene_mode"):
		_dialogue.set_cutscene_mode(false)
	_player.set_move_enabled(true)
	_camera.enable_free_look(40.0)
	_camera.recenter()
	if _return_scanner_interactable != null:
		_return_scanner_interactable.set_interaction_enabled(true)
		_return_scanner_interactable.call_deferred("show_tutorial_label")
	_tutorial_prompt.show_prompt("[Interact] — return to PSY-1 and complete Aster's scan")
	if _legacy_compatibility_fallback_allowed():
		_scheduler.schedule_after(
			ACTIVITY_GATE_FALLBACK_SECONDS,
			func(): trigger_return_scanner(true),
			RETURN_SCAN_FALLBACK_TAG
		)

func trigger_return_scanner(auto_resolved := false) -> void:
	if _current_step != "return_to_scanner" or _return_scan_resolved:
		return
	_return_scan_resolved = true
	_return_scan_auto_resolved = auto_resolved
	if not auto_resolved:
		_scheduler.cancel_tag(RETURN_SCAN_FALLBACK_TAG)
	if _player != null and _player.has_method("cancel_interaction_target"):
		_player.cancel_interaction_target()
	_game_state.command_stop("aster")
	_player.set_move_enabled(false)
	_camera.disable_free_look()
	if _return_scanner_interactable != null:
		_return_scanner_interactable.set_interaction_enabled(false)
	_tutorial_prompt.hide_prompt()
	if _dialogue != null and _dialogue.has_method("set_cutscene_mode"):
		_dialogue.set_cutscene_mode(true)
	_scheduler.schedule_after(0.3, _start_aster_scans, "aster_scans")

func _start_aster_scans() -> void:
	_current_step = "aster_scans"
	# Aster's scan light.
	_citizen_light.light_color = (
		Color(0.48, 0.3, 0.86)
		if _witness_record_choice == "private_trace"
		else Color(0.2, 0.5, 0.9)
	)
	_citizen_light.light_energy = 4.0
	_citizen_light.position = ASTER_DEVICE_POS + Vector3(0, 2, 0)
	DialogueData.say_to(_dialogue, "tag_day.scan_passed")
	_dialogue.dialogue_finished.connect(func():
		_scheduler.schedule_after(0.5, _start_blue_transition, "blue_transition")
	, CONNECT_ONE_SHOT)

func _start_blue_transition() -> void:
	_enter_step("clearance")
	_citizen_light.light_color = Color(0.15, 0.4, 0.85)
	_citizen_light.light_energy = 6.0
	_dialogue.default_hold_time = 2.0
	# Blue fade into the elevator. The fade is a cosmetic tween, but the step
	# transition rides the scheduler so fast-forward reaches it at the same tick.
	_fade_rect.color = Color(0.1, 0.2, 0.5, 0.0)
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, 2.0)
	_scheduler.schedule_after(2.0, _on_sequence_complete, "blue_complete")

func _on_sequence_complete() -> void:
	_enter_step("complete")
	_change_scene_or_record("res://scenes/tutorial/elevator.tscn")


# --- Active checkpoint route ---

func _build_active_play_stations() -> void:
	if not _witness_interactables.is_empty():
		return
	var environment := find_child("Environment", false, false) as Node3D
	if environment == null:
		return

	var public_log := _create_interactable(
		environment, WITNESS_PUBLIC_POS, "TagDayPublicWitnessSeal",
		1.35, WITNESS_WORK_SECONDS, "FILE DUTY LOG", true,
		Interactable.InteractableType.TIMED_ACTION
	)
	public_log.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
	public_log.set("required_character", "aster")
	public_log.interacted.connect(trigger_witness_record.bind("public_log"))
	public_log.interaction_requested.connect(_on_witness_route_requested.bind("public_log"))
	_add_activity_station_visual(public_log, Color(0.2, 0.58, 0.86), "DUTY LOG")
	_witness_interactables["public_log"] = public_log

	var private_trace := _create_interactable(
		environment, WITNESS_PRIVATE_POS, "TagDayPrivateWitnessSeal",
		1.35, WITNESS_WORK_SECONDS, "KEEP PRIVATE TRACE", true,
		Interactable.InteractableType.TIMED_ACTION
	)
	private_trace.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
	private_trace.set("required_character", "aster")
	private_trace.interacted.connect(trigger_witness_record.bind("private_trace"))
	private_trace.interaction_requested.connect(_on_witness_route_requested.bind("private_trace"))
	_add_activity_station_visual(private_trace, Color(0.62, 0.34, 0.82), "PRIVATE TRACE")
	_witness_interactables["private_trace"] = private_trace

	_return_scanner_interactable = _create_interactable(
		environment, ASTER_DEVICE_POS, "TagDayReturnScanner",
		1.4, RETURN_SCAN_WORK_SECONDS, "COMPLETE PSY-1 SCAN", true,
		Interactable.InteractableType.TIMED_ACTION
	)
	_return_scanner_interactable.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
	_return_scanner_interactable.set("required_character", "aster")
	_return_scanner_interactable.interacted.connect(trigger_return_scanner)
	_return_scanner_interactable.interaction_requested.connect(_on_return_scanner_route_requested)
	_add_activity_station_visual(
		_return_scanner_interactable, Color(0.22, 0.5, 0.88), "PSY-1 RETURN")

	for raw_site in ESCORT_FIELD_SITE_DEFS:
		var site: Dictionary = raw_site
		var site_id := str(site["id"])
		var field_station := _create_interactable(
			environment,
			site["position"] as Vector3,
			str(site["name"]),
			1.3,
			float(site["dwell"]),
			str(site["verb"]),
			true,
			Interactable.InteractableType.TIMED_ACTION
		)
		field_station.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
		field_station.set("required_character", "aster")
		field_station.interacted.connect(_on_escort_field_site_interacted.bind(site_id))
		field_station.interaction_requested.connect(
			_on_escort_field_route_requested.bind(site_id)
		)
		_unbind_default_interaction_controller(field_station)
		call_deferred("_unbind_default_interaction_controller", field_station)
		_add_activity_station_visual(
			field_station, site["color"] as Color, str(site["label"]), true
		)
		_escort_field_interactables[site_id] = field_station
		_escort_field_order.append(site_id)

	_witness_receipt_label = Label3D.new()
	_witness_receipt_label.name = "WitnessReceipt"
	_witness_receipt_label.text = "WITNESS RECORD  //  AWAITING ROUTE"
	_witness_receipt_label.font_size = 26
	_witness_receipt_label.pixel_size = 0.007
	_witness_receipt_label.modulate = Color(0.35, 0.42, 0.55, 0.72)
	_witness_receipt_label.outline_modulate = Color(0, 0, 0, 0.8)
	_witness_receipt_label.outline_size = 6
	_witness_receipt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_witness_receipt_label.position = Vector3(18.5, 2.25, -27.5)
	environment.add_child(_witness_receipt_label)

	_set_witness_interactables_enabled(false)
	_return_scanner_interactable.set_interaction_enabled(false)
	_set_all_escort_field_interactables_enabled(false)

func _add_activity_station_visual(
	interactable: Area3D,
	color: Color,
	station_label: String,
	allow_focused_proxy := false
) -> void:
	var assembly := Node3D.new()
	assembly.name = "%sAssembly" % interactable.name
	interactable.add_child(assembly)
	if focused_verifier_lightweight_station_visuals and allow_focused_proxy:
		var proxy := MeshInstance3D.new()
		proxy.name = "FocusedVerifierVisualProxy"
		var proxy_mesh := BoxMesh.new()
		proxy_mesh.size = Vector3(0.72, 0.9, 0.56)
		proxy.mesh = proxy_mesh
		var proxy_material := StandardMaterial3D.new()
		proxy_material.albedo_color = color.darkened(0.45)
		proxy.material_override = proxy_material
		proxy.position.y = 0.45
		assembly.add_child(proxy)
		interactable.set_meta("focused_visual_proxy", true)
		return

	var pedestal := MeshInstance3D.new()
	var pedestal_mesh := CylinderMesh.new()
	pedestal_mesh.top_radius = 0.38
	pedestal_mesh.bottom_radius = 0.52
	pedestal_mesh.height = 0.9
	pedestal.mesh = pedestal_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.58)
	material.metallic = 0.42
	material.roughness = 0.48
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.35
	pedestal.material_override = material
	pedestal.position.y = 0.45
	assembly.add_child(pedestal)

	var reader := MeshInstance3D.new()
	var reader_mesh := BoxMesh.new()
	reader_mesh.size = Vector3(0.72, 0.18, 0.56)
	reader.mesh = reader_mesh
	reader.material_override = material
	reader.position = Vector3(0, 1.02, 0)
	assembly.add_child(reader)

	var label := Label3D.new()
	label.text = station_label
	label.font_size = 24
	label.pixel_size = 0.006
	label.modulate = color.lightened(0.25)
	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.outline_size = 5
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 1.42, 0)
	assembly.add_child(label)

	var target := _outline_object_meshes(
		interactable,
		"%sOutline" % interactable.name,
		_collect_mesh_instances(assembly),
		"tag_day.%s" % interactable.name.to_snake_case(),
		0.75
	)
	_set_room_target_interaction_delegate(target, interactable)
	# The Area3D owns picking and routes the authored corridor path. The outline
	# body remains visual-only so it cannot issue a second generic straight route.
	if target != null:
		target.set("hover_enabled", false)
		target.set("collision_layer", 0)
		target.set("input_ray_pickable", false)

func _set_witness_interactables_enabled(enabled: bool) -> void:
	for interactable in _witness_interactables.values():
		if interactable == null or not is_instance_valid(interactable):
			continue
		interactable.set_interaction_enabled(enabled)
		if enabled:
			interactable.call_deferred("show_tutorial_label")

func _unbind_default_interaction_controller(interactable: Node) -> void:
	# These stations own authored multi-turn routes. Letting the generic controller
	# also plan a straight target first does redundant cooperative A* work and can
	# briefly show a wall-cutting route before this scene replaces it.
	if _player == null:
		return
	var controller: Node = _player.get_node_or_null("CharacterInteractionController")
	if controller == null:
		return
	var callback := Callable(controller, "_on_interaction_requested")
	if interactable.is_connected("interaction_requested", callback):
		interactable.disconnect("interaction_requested", callback)

func _legacy_compatibility_fallback_allowed(runtime_display_name := "") -> bool:
	var display_name := runtime_display_name
	if display_name == "":
		display_name = DisplayServer.get_name()
	return display_name == "headless" or _running_under_test_flags()

func _start_escort_field_record() -> void:
	if _escort_field_resolved or _escort_field_order.is_empty():
		return
	_player.set_move_enabled(true)
	_camera.enable_free_look(40.0)
	_camera.recenter()
	_enable_current_escort_field_site()
	# Old scheduler-only contract drivers cannot issue world clicks. Their seam is
	# isolated to headless/test runtimes and is intentionally longer than the real
	# shortest field circuit, so focused real-input validation wins the race.
	if _legacy_compatibility_fallback_allowed():
		_scheduler.schedule_after(
			ESCORT_FIELD_FALLBACK_SECONDS,
			_complete_escort_field_record.bind(true),
			ESCORT_FIELD_FALLBACK_TAG
		)

func _enable_current_escort_field_site() -> void:
	_set_all_escort_field_interactables_enabled(false)
	var site_id := current_escort_field_site_id()
	if site_id == "":
		return
	var interactable: Area3D = _escort_field_interactables[site_id]
	interactable.set_interaction_enabled(true)
	interactable.call_deferred("show_tutorial_label")
	# This is a substep assignment, not _enter_step(): entering a step clears the
	# dialogue-finished callback that owns the still-running poem presentation.
	_current_step = "escort_record_%s" % site_id
	var site_number := _escort_field_index + 1
	_tutorial_prompt.show_prompt(
		"[Interact] — incident field record %d/%d: %s" % [
			site_number,
			_escort_field_order.size(),
			str(interactable.get("tutorial_label")),
		]
	)

func _set_all_escort_field_interactables_enabled(enabled: bool) -> void:
	for interactable in _escort_field_interactables.values():
		if interactable == null or not is_instance_valid(interactable):
			continue
		interactable.set_interaction_enabled(enabled)

func current_escort_field_site_id() -> String:
	if _escort_field_index < 0 or _escort_field_index >= _escort_field_order.size():
		return ""
	return _escort_field_order[_escort_field_index]

func _on_escort_field_site_interacted(site_id: String) -> void:
	if _escort_field_resolved or site_id != current_escort_field_site_id():
		return
	_escort_field_index += 1
	if _escort_field_index >= _escort_field_order.size():
		_complete_escort_field_record(false)
	else:
		_enable_current_escort_field_site()

func _complete_escort_field_record(auto_resolved := false) -> void:
	if _escort_field_resolved:
		return
	_escort_field_resolved = true
	_escort_field_auto_resolved = auto_resolved
	_escort_field_index = _escort_field_order.size()
	_escort_pending_site_id = ""
	_escort_field_finished_tick = _scheduler.get_current_tick()
	if not auto_resolved:
		_scheduler.cancel_tag(ESCORT_FIELD_FALLBACK_TAG)
	if _player != null and _player.has_method("cancel_interaction_target"):
		_player.cancel_interaction_target()
	_game_state.command_stop("aster")
	_set_all_escort_field_interactables_enabled(false)
	_current_step = "escort_record_complete"
	_tutorial_prompt.show_prompt("INCIDENT FIELD RECORD COMPLETE  //  remain with the escort")
	_try_finish_escort_field_record()

func _try_finish_escort_field_record() -> void:
	if not _escort_field_resolved or not _escort_presentation_finished:
		return
	_start_fragments()

func _on_escort_field_route_requested(
	_target: Node,
	_world_position: Vector3,
	site_id: String
) -> void:
	if _escort_field_resolved or site_id != current_escort_field_site_id():
		return
	if _escort_pending_site_id == site_id and _game_state.is_moving("aster"):
		return
	_escort_pending_site_id = site_id
	var interactable: Node = _escort_field_interactables[site_id]
	interactable.set("active_character", "aster")
	_game_state.command_walk_path("aster", _escort_field_route(site_id, _witness_record_choice))

func _escort_field_route(site_id: String, witness_choice: String) -> Array[Vector3]:
	var route: Array[Vector3] = []
	match site_id:
		"scan_failure":
			if witness_choice == "private_trace":
				route.append(CORRIDOR_D_END)
			route.append(Vector3(24, 0, -27))
			route.append(Vector3(24, 0, -17))
			route.append(Vector3(14, 0, -17))
			route.append(CORRIDOR_A_END)
			route.append(CORRIDOR_ENTRANCE)
			route.append(Vector3(8.2, 0, -3.0))
		"east_queue_witness":
			route.append(Vector3(8.2, 0, 4.0))
			route.append(Vector3(24.0, 0, 4.0))
		"west_queue_witness":
			route.append(Vector3(0.0, 0, 4.0))
		"report_provenance":
			route.append(Vector3(26.0, 0, 4.0))
			route.append(Vector3(26.0, 0, -5.0))
		"medical_override":
			route.append(Vector3(1.0, 0, -5.0))
		"custody_threshold":
			route.append(Vector3(12.0, 0, -5.0))
			route.append(CORRIDOR_ENTRANCE)
			route.append(Vector3(14.0, 0, -10.0))
		"gait_variance":
			route.append(CORRIDOR_A_END)
			route.append(Vector3(14.0, 0, -17.0))
			route.append(Vector3(20.0, 0, -17.0))
		"grip_telemetry":
			route.append(Vector3(24.0, 0, -17.0))
			route.append(Vector3(24.0, 0, -22.0))
		"iron_shadow":
			route.append(Vector3(24.0, 0, -27.0))
			route.append(Vector3(21.0, 0, -27.0))
		"report_echo":
			# Compare the official broadcast upstream after sampling the dead-end
			# iron shadow; this purposeful backtrack distinguishes cause from report.
			route.append(Vector3(24.0, 0, -27.0))
			route.append(Vector3(24.0, 0, -19.0))
		"erasure_receipt":
			route.append(Vector3(24.0, 0, -27.0))
			route.append(CORRIDOR_D_END)
			route.append(Vector3(17.0, 0, -29.0))
	return route

func _on_witness_route_requested(
	_target: Node,
	_world_position: Vector3,
	choice_id: String
) -> void:
	if _current_step != "witness_choice" or _witness_record_resolved:
		return
	_game_state.command_walk_path("aster", _witness_route(choice_id))

func _on_return_scanner_route_requested(_target: Node, _world_position: Vector3) -> void:
	if _current_step != "return_to_scanner" or _return_scan_resolved:
		return
	_game_state.command_walk_path("aster", _return_scanner_route())

func _witness_route(choice_id: String) -> Array[Vector3]:
	var route: Array[Vector3] = [
		CORRIDOR_ENTRANCE,
		CORRIDOR_A_END,
		Vector3(14, 0, -17),
		Vector3(24, 0, -17),
		Vector3(24, 0, -27),
	]
	if choice_id == "private_trace":
		route.append(CORRIDOR_D_END)
		route.append(WITNESS_PRIVATE_POS)
	else:
		route.append(WITNESS_PUBLIC_POS)
	return route

func _return_scanner_route() -> Array[Vector3]:
	# Both evidence branches now finish at the erasure receipt in the dead-end
	# alcove, so the safe return always exits through D before retracing the turns.
	var route: Array[Vector3] = [CORRIDOR_D_END]
	route.append(Vector3(24, 0, -27))
	route.append(Vector3(24, 0, -17))
	route.append(Vector3(14, 0, -17))
	route.append(CORRIDOR_A_END)
	route.append(CORRIDOR_ENTRANCE)
	route.append(ASTER_DEVICE_POS)
	return route

func _update_witness_receipt() -> void:
	if _witness_receipt_label == null:
		return
	if _witness_record_choice == "private_trace":
		_witness_receipt_label.text = "PRIVATE TRACE  //  LOCAL RETENTION ONLY"
		_witness_receipt_label.modulate = Color(0.68, 0.42, 0.9, 0.9)
	else:
		_witness_receipt_label.text = "DUTY LOG  //  INCIDENT INDEXED"
		_witness_receipt_label.modulate = Color(0.3, 0.62, 0.92, 0.9)

func _polyline_distance(start: Vector3, route: Array[Vector3]) -> float:
	var total := 0.0
	var previous := start
	for point in route:
		total += previous.distance_to(point)
		previous = point
	return total

func _escort_field_site_position(site_id: String) -> Vector3:
	for raw_site in ESCORT_FIELD_SITE_DEFS:
		var site: Dictionary = raw_site
		if str(site["id"]) == site_id:
			var position: Vector3 = site["position"]
			return position
	return Vector3.ZERO

func _authored_escort_field_order() -> Array[String]:
	# Runtime construction fills `_escort_field_order` from these same definitions.
	# Falling back to the definitions keeps the analytic contract pure: tooling can
	# measure it without booting a renderer or mutating the scene tree.
	if not _escort_field_order.is_empty():
		return _escort_field_order.duplicate()
	var authored_order: Array[String] = []
	for raw_site in ESCORT_FIELD_SITE_DEFS:
		authored_order.append(str((raw_site as Dictionary)["id"]))
	return authored_order

func _escort_field_route_distance(witness_choice: String) -> float:
	var previous := (
		WITNESS_PRIVATE_POS if witness_choice == "private_trace" else WITNESS_PUBLIC_POS
	)
	var total := 0.0
	for site_id in _authored_escort_field_order():
		var route := _escort_field_route(site_id, witness_choice)
		total += _polyline_distance(previous, route)
		previous = _escort_field_site_position(site_id)
	return total

func _escort_field_work_seconds() -> float:
	var total := 0.0
	for raw_site in ESCORT_FIELD_SITE_DEFS:
		total += float((raw_site as Dictionary)["dwell"])
	return total

func _maximum_single_active_mode_seconds(witness_choice: String) -> float:
	var maximum := _polyline_distance(ASTER_DEVICE_POS, _witness_route(witness_choice)) \
		/ ASTER_CHECKPOINT_SPEED
	var previous := (
		WITNESS_PRIVATE_POS if witness_choice == "private_trace" else WITNESS_PUBLIC_POS
	)
	for site_id in _authored_escort_field_order():
		var route_seconds := _polyline_distance(
			previous, _escort_field_route(site_id, witness_choice)
		) / ASTER_CHECKPOINT_SPEED
		maximum = maxf(maximum, route_seconds)
		previous = _escort_field_site_position(site_id)
	maximum = maxf(maximum, _polyline_distance(previous, _return_scanner_route()) \
		/ ASTER_CHECKPOINT_SPEED)
	maximum = maxf(maximum, WITNESS_WORK_SECONDS)
	maximum = maxf(maximum, RETURN_SCAN_WORK_SECONDS)
	for raw_site in ESCORT_FIELD_SITE_DEFS:
		maximum = maxf(maximum, float((raw_site as Dictionary)["dwell"]))
	return maximum

func _branch_playtime_metrics(witness_choice: String) -> Dictionary:
	var authored_order := _authored_escort_field_order()
	var witness_out := _polyline_distance(ASTER_DEVICE_POS, _witness_route(witness_choice))
	var field_route := _escort_field_route_distance(witness_choice)
	var final_site := _escort_field_site_position(authored_order[-1])
	var scanner_return := _polyline_distance(final_site, _return_scanner_route())
	var field_work := _escort_field_work_seconds()
	var field_active := field_route / ASTER_CHECKPOINT_SPEED + field_work
	var total_route := witness_out + field_route + scanner_return
	var total_work := WITNESS_WORK_SECONDS + field_work + RETURN_SCAN_WORK_SECONDS
	var meaningful_active := total_route / ASTER_CHECKPOINT_SPEED + total_work
	var checkpoint_transit := (witness_out + scanner_return) / ASTER_CHECKPOINT_SPEED
	var field_traversal := field_route / ASTER_CHECKPOINT_SPEED
	# The old cinematic already contains the poem/Naturalizer presentation. Only
	# field work beyond that overlapping 103.4-second window extends elapsed time.
	var modeled_elapsed := LEGACY_PRESENTATION_SECONDS \
		+ (witness_out + scanner_return) / ASTER_CHECKPOINT_SPEED \
		+ WITNESS_WORK_SECONDS + RETURN_SCAN_WORK_SECONDS - 1.0 \
		+ maxf(0.0, field_active - ESCORT_PRESENTATION_SECONDS)
	return {
		"choice": witness_choice,
		"route_meters": total_route,
		"field_route_meters": field_route,
		"station_work_seconds": total_work,
		"field_active_seconds": field_active,
		"meaningful_active_seconds": meaningful_active,
		"checkpoint_transit_seconds": checkpoint_transit,
		"field_traversal_seconds": field_traversal,
		"max_single_mode_seconds": _maximum_single_active_mode_seconds(witness_choice),
		"presentation_overlap_seconds": minf(field_active, ESCORT_PRESENTATION_SECONDS),
		"modeled_elapsed_seconds": modeled_elapsed,
	}

func get_playtime_contract() -> Dictionary:
	var public_metrics := _branch_playtime_metrics("public_log")
	var private_metrics := _branch_playtime_metrics("private_trace")
	var shortest: Dictionary = (
		public_metrics
		if float(public_metrics["modeled_elapsed_seconds"])
			<= float(private_metrics["modeled_elapsed_seconds"])
		else private_metrics
	)
	var modeled_first_clear := float(shortest["modeled_elapsed_seconds"])
	var modeled_active := float(shortest["meaningful_active_seconds"])
	return {
		"target_min_seconds": 240.0,
		"target_max_seconds": 360.0,
		"minimum_active_route_meters": float(shortest["route_meters"]),
		"escort_field_route_meters": float(shortest["field_route_meters"]),
		"minimum_station_work_seconds": float(shortest["station_work_seconds"]),
		"modeled_meaningful_active_seconds": modeled_active,
		"meaningful_active_seconds": modeled_active,
		"modeled_meaningful_active_ratio": modeled_active / modeled_first_clear,
		"meaningful_active_ratio": modeled_active / modeled_first_clear,
		"active_ratio": modeled_active / modeled_first_clear,
		"modeled_first_clear_seconds": modeled_first_clear,
		"total_play_seconds": modeled_first_clear,
		"modeled_passive_or_presentation_only_seconds": modeled_first_clear - modeled_active,
		"escort_presentation_seconds": ESCORT_PRESENTATION_SECONDS,
		"escort_presentation_overlap_seconds": float(shortest["presentation_overlap_seconds"]),
		"escort_field_active_seconds": float(shortest["field_active_seconds"]),
		"escort_field_site_count": ESCORT_FIELD_SITE_DEFS.size(),
		"mandatory_click_gate_count": ESCORT_FIELD_SITE_DEFS.size() + 2,
		"max_single_control_removed_gap_seconds": 5.0,
		"max_dead_gap_seconds": 5.0,
		"max_single_mode_seconds": float(shortest["max_single_mode_seconds"]),
		"category_seconds": {
			"checkpoint_transit": float(shortest["checkpoint_transit_seconds"]),
			"escort_field_traversal": float(shortest["field_traversal_seconds"]),
			"incident_station_work": float(shortest["station_work_seconds"]),
		},
		"decision_count": 1,
		"branch_count": 2,
		"shortest_first_clear_branch": str(shortest["choice"]),
		"normal_input_auto_fallback_enabled": false,
		"compatibility_fallback_scope": "headless_or_test_driver_only",
		"target_metric": "meaningful_active_seconds",
		"timing_basis": "authored polyline distance at 2.35 m/s plus scheduler-backed TIMED_ACTION work; corridor poem/Naturalizer presentation overlaps the mandatory field circuit once; no idle or fallback waiting counted",
	}

func headless_get_anchor_positions() -> Dictionary:
	var anchors := {
		"aster_scanner": ASTER_DEVICE_POS,
		"public_witness": WITNESS_PUBLIC_POS,
		"private_witness": WITNESS_PRIVATE_POS,
	}
	for site_id in _escort_field_order:
		anchors["escort_%s" % site_id] = _escort_field_site_position(site_id)
	return anchors

func headless_get_state() -> Dictionary:
	var state := super.headless_get_state()
	state["witness_record_choice"] = _witness_record_choice
	state["witness_record_resolved"] = _witness_record_resolved
	state["return_scan_resolved"] = _return_scan_resolved
	state["witness_auto_resolved"] = _witness_auto_resolved
	state["return_scan_auto_resolved"] = _return_scan_auto_resolved
	state["escort_field_site_count"] = _escort_field_order.size()
	state["escort_field_completed_count"] = _escort_field_index
	state["escort_field_current_site_id"] = current_escort_field_site_id()
	state["escort_field_resolved"] = _escort_field_resolved
	state["escort_field_auto_resolved"] = _escort_field_auto_resolved
	state["escort_presentation_finished"] = _escort_presentation_finished
	state["escort_started_tick"] = _escort_started_tick
	state["escort_presentation_finished_tick"] = _escort_presentation_finished_tick
	state["escort_field_finished_tick"] = _escort_field_finished_tick
	state["escort_presentation_measured_seconds"] = (
		_escort_presentation_finished_tick - _escort_started_tick
		if _escort_started_tick >= 0.0 and _escort_presentation_finished_tick >= 0.0
		else -1.0
	)
	state["escort_field_measured_seconds"] = (
		_escort_field_finished_tick - _escort_started_tick
		if _escort_started_tick >= 0.0 and _escort_field_finished_tick >= 0.0
		else -1.0
	)
	return state


func _build_checkpoint_decorations() -> void:
	var environment := find_child("Environment", false, false) as Node3D
	if environment == null:
		return
	# The shared building-quality grammar assumes a straight, centered corridor.
	# Two offset spans dress the clinical checkpoint walls without drawing facade
	# panels across the Wellness doorway at x=14, z=-8.
	for span in [
		{"name": "CheckpointWestDatum", "x0": -4.0, "x1": 12.4, "signs": ["CHECKPOINT 7-B"]},
		{"name": "CheckpointEastDatum", "x0": 15.6, "x1": 28.0, "signs": ["PSY-KNAPSE ARRAY"]},
	]:
		var anchor := Node3D.new()
		anchor.name = str(span["name"])
		anchor.position.z = -1.0  # room walls are centered between z=-8 and z=6
		environment.add_child(anchor)
		LevelDecoratorScript.decorate_profile(anchor, "tag_checkpoint", {
			"x0": float(span["x0"]),
			"x1": float(span["x1"]),
			"signs": span["signs"],
		})

	# A continuous surface datum makes the four turns legible without adding
	# collision or changing the authored GridWorld route.
	_add_checkpoint_route_datum(environment, Vector3(14, 0.022, -12), Vector3(0.10, 0.018, 7.2), 0)
	_add_checkpoint_route_datum(environment, Vector3(20, 0.022, -17), Vector3(9.2, 0.018, 0.10), 1)
	_add_checkpoint_route_datum(environment, Vector3(24, 0.022, -22), Vector3(0.10, 0.018, 7.2), 2)
	_add_checkpoint_route_datum(environment, Vector3(20.5, 0.022, -27), Vector3(6.2, 0.018, 0.10), 3)

func _add_checkpoint_route_datum(parent: Node3D, pos: Vector3, size: Vector3, index: int) -> void:
	var datum := MeshInstance3D.new()
	datum.name = "WellnessRouteDatum%d" % index
	var mesh := BoxMesh.new()
	mesh.size = size
	datum.mesh = mesh
	var material := StandardMaterial3D.new()
	var color := Color(0.26, 0.58, 0.82).lerp(Color(0.72, 0.24, 0.12), float(index) / 4.0)
	material.albedo_color = color.darkened(0.38)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.75
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	datum.material_override = material
	datum.position = pos
	parent.add_child(datum)


# --- Environment Build ---

func _build_environment() -> void:
	var env_node := Node3D.new()
	env_node.name = "Environment"
	add_child(env_node)

	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(32, 0.1, 16)
	floor_mesh.mesh = floor_box
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.14, 0.16, 0.20)
	floor_mat.metallic = 0.28
	floor_mat.roughness = 0.74
	floor_mesh.material_override = floor_mat
	floor_mesh.position = Vector3(12, -0.05, -2)
	env_node.add_child(floor_mesh)

	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(12, -0.01, -2)
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(32, 0.02, 16)
	floor_col.shape = floor_shape
	floor_body.add_child(floor_col)
	env_node.add_child(floor_body)

	# Main-room walls with doorway.
	_add_wall(env_node, Vector3(4.5, 1.5, -8), Vector3(17, 3, 0.3))
	_add_wall(env_node, Vector3(21.5, 1.5, -8), Vector3(13, 3, 0.3))
	_add_wall(env_node, Vector3(12, 1.5, 6), Vector3(32, 3, 0.3))
	_add_wall(env_node, Vector3(-4, 1.5, -2), Vector3(0.3, 3, 14))
	_add_wall(env_node, Vector3(28, 1.5, -2), Vector3(0.3, 3, 14))

	# Psy-Knapse device row.
	for i in range(5):
		var dev_pos := ASTER_DEVICE_POS + Vector3(i * DEVICE_SPACING, 0, 0)
		_add_booth(env_node, dev_pos, "PSY-%d" % (i + 1))

	# Lane dividers between devices.
	for i in range(6):
		var marker := MeshInstance3D.new()
		var line := BoxMesh.new()
		line.size = Vector3(0.05, 0.02, 1.2)
		marker.mesh = line
		var line_mat := StandardMaterial3D.new()
		line_mat.albedo_color = Color(0.15, 0.15, 0.2)
		marker.material_override = line_mat
		marker.position = ASTER_DEVICE_POS + Vector3(i * DEVICE_SPACING + DEVICE_SPACING * 0.5, 0.01, 0)
		env_node.add_child(marker)

	for i in range(4):
		var ceiling_light := MeshInstance3D.new()
		var cl_box := BoxMesh.new()
		cl_box.size = Vector3(4, 0.05, 1.5)
		ceiling_light.mesh = cl_box
		var cl_mat := StandardMaterial3D.new()
		cl_mat.albedo_color = Color(0.6, 0.6, 0.65)
		cl_mat.emission_enabled = true
		cl_mat.emission = Color(0.5, 0.5, 0.55)
		cl_mat.emission_energy_multiplier = 0.5
		ceiling_light.material_override = cl_mat
		ceiling_light.position = Vector3(3 + i * 7, 2.95, -1)
		env_node.add_child(ceiling_light)
		var work_light := OmniLight3D.new()
		work_light.name = "CheckpointWorkLight%d" % i
		work_light.position = Vector3(3 + i * 7, 2.52, -1)
		work_light.light_color = Color(0.62, 0.72, 0.9)
		work_light.light_energy = 1.25
		work_light.omni_range = 7.2
		work_light.shadow_enabled = false
		env_node.add_child(work_light)

	# Clinical fluorescent directional light
	var dir_light := DirectionalLight3D.new()
	dir_light.transform = Transform3D(
		Basis(Vector3(1, 0, 0), -PI / 3.0),
		Vector3(0, 8, 0)
	)
	dir_light.light_color = Color(0.75, 0.75, 0.8)
	dir_light.light_energy = 0.86
	dir_light.shadow_enabled = true
	env_node.add_child(dir_light)

	# Ambient fill
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.04, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.46, 0.56)
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.1
	world_env.environment = env
	env_node.add_child(world_env)

	# Verification sign
	var overhead := MeshInstance3D.new()
	var oh_box := BoxMesh.new()
	oh_box.size = Vector3(3, 0.1, 0.6)
	overhead.mesh = oh_box
	var oh_mat := StandardMaterial3D.new()
	oh_mat.albedo_color = Color(0.15, 0.15, 0.2)
	oh_mat.emission_enabled = true
	oh_mat.emission = Color(0.1, 0.12, 0.2)
	oh_mat.emission_energy_multiplier = 0.3
	overhead.material_override = oh_mat
	var sign_x := ASTER_DEVICE_POS.x + 2.0 * DEVICE_SPACING
	overhead.position = Vector3(sign_x, 2.6, 0)
	env_node.add_child(overhead)
	var sign_lbl := Label3D.new()
	sign_lbl.text = "TAG DAY  //  VERIFICATION  7-B"
	sign_lbl.font_size = 32
	sign_lbl.pixel_size = 0.008
	sign_lbl.modulate = Color(0.3, 0.4, 0.6, 0.7)
	sign_lbl.position = Vector3(sign_x, 2.6, -0.04)
	env_node.add_child(sign_lbl)

	# Light above citizen's device (used for scan result + lockdown)
	_citizen_light = OmniLight3D.new()
	_citizen_light.position = CITIZEN_DEVICE_POS + Vector3(0, 2, 0)
	_citizen_light.light_color = Color(0.3, 0.3, 0.35)
	_citizen_light.light_energy = 1.5
	_citizen_light.omni_range = 4.0
	env_node.add_child(_citizen_light)

# --- Corridor Build ---

func _build_corridor() -> void:
	var env_node: Node = find_child("Environment", false, false)
	if not env_node:
		return

	var floor_color := Color(0.105, 0.115, 0.145)

	# Segment A: straight away from doorway (x=13-15, z=-8 to z=-16)
	_add_corridor_floor(env_node, Vector3(14, -0.05, -12), Vector3(2, 0.1, 8), floor_color)
	_add_corridor_collision(env_node, Vector3(14, -0.01, -12), Vector3(2, 0.02, 8))
	_add_wall(env_node, Vector3(12.85, 1.5, -12), Vector3(0.3, 3, 8))
	_add_wall(env_node, Vector3(15.15, 1.5, -12), Vector3(0.3, 3, 8))

	# Segment B: turn right (x=15-25, z=-16 to z=-18)
	_add_corridor_floor(env_node, Vector3(20, -0.05, -17), Vector3(10, 0.1, 2), floor_color)
	_add_corridor_collision(env_node, Vector3(20, -0.01, -17), Vector3(10, 0.02, 2))
	_add_wall(env_node, Vector3(20, 1.5, -15.85), Vector3(10, 3, 0.3))
	_add_wall(env_node, Vector3(20, 1.5, -18.15), Vector3(10, 3, 0.3))

	# Segment C: turn away again (x=23-25, z=-18 to z=-26)
	_add_corridor_floor(env_node, Vector3(24, -0.05, -22), Vector3(2, 0.1, 8), floor_color)
	_add_corridor_collision(env_node, Vector3(24, -0.01, -22), Vector3(2, 0.02, 8))
	_add_wall(env_node, Vector3(22.85, 1.5, -22), Vector3(0.3, 3, 8))
	_add_wall(env_node, Vector3(25.15, 1.5, -22), Vector3(0.3, 3, 8))

	# Segment D: turn left into dead-end (x=16-23, z=-26 to z=-28)
	_add_corridor_floor(env_node, Vector3(19.5, -0.05, -27), Vector3(7, 0.1, 2), floor_color)
	_add_corridor_collision(env_node, Vector3(19.5, -0.01, -27), Vector3(7, 0.02, 2))
	_add_wall(env_node, Vector3(19.5, 1.5, -25.85), Vector3(7, 3, 0.3))
	_add_wall(env_node, Vector3(19.5, 1.5, -28.15), Vector3(7, 3, 0.3))

	# Dead end alcove (x=16-18, z=-28 to z=-30)
	_add_corridor_floor(env_node, Vector3(17, -0.05, -29), Vector3(2, 0.1, 2), floor_color)
	_add_corridor_collision(env_node, Vector3(17, -0.01, -29), Vector3(2, 0.02, 2))
	_add_wall(env_node, Vector3(15.85, 1.5, -29), Vector3(0.3, 3, 2))
	_add_wall(env_node, Vector3(18.15, 1.5, -29), Vector3(0.3, 3, 2))
	_add_wall(env_node, Vector3(17, 1.5, -30.15), Vector3(2, 3, 0.3))

	# "Wellness Wing" sign above the corridor entrance
	var ww_sign := MeshInstance3D.new()
	var ww_box := BoxMesh.new()
	ww_box.size = Vector3(2.5, 0.1, 0.4)
	ww_sign.mesh = ww_box
	var ww_mat := StandardMaterial3D.new()
	ww_mat.albedo_color = Color(0.12, 0.12, 0.18)
	ww_mat.emission_enabled = true
	ww_mat.emission = Color(0.08, 0.1, 0.18)
	ww_mat.emission_energy_multiplier = 0.3
	ww_sign.material_override = ww_mat
	ww_sign.position = Vector3(CORRIDOR_ENTRANCE.x, 2.6, CORRIDOR_ENTRANCE.z + 0.2)
	env_node.add_child(ww_sign)
	var ww_lbl := Label3D.new()
	ww_lbl.text = "WELLNESS WING"
	ww_lbl.font_size = 36
	ww_lbl.pixel_size = 0.008
	ww_lbl.modulate = Color(0.3, 0.4, 0.6, 0.7)
	ww_lbl.position = Vector3(CORRIDOR_ENTRANCE.x, 2.6, CORRIDOR_ENTRANCE.z + 0.17)
	env_node.add_child(ww_lbl)

	_add_corridor_ceiling(env_node, Vector3(14, 2.95, -12), Vector3(1.5, 0.05, 3), 0.3)
	_add_corridor_ceiling(env_node, Vector3(20, 2.95, -17), Vector3(4, 0.05, 1.5), 0.2)
	_add_corridor_ceiling(env_node, Vector3(24, 2.95, -22), Vector3(1.5, 0.05, 3), 0.15)
	_add_corridor_ceiling(env_node, Vector3(17, 2.95, -28), Vector3(1.5, 0.05, 1.5), 0.1)

	# Corridor lights grow dimmer and redder.
	_add_corridor_light(env_node, Vector3(14, 2.5, -12), 1.25, Color(0.46, 0.38, 0.31))
	_add_corridor_light(env_node, Vector3(20, 2.5, -17), 1.05, Color(0.43, 0.30, 0.22))
	_add_corridor_light(env_node, Vector3(24, 2.5, -22), 0.86, Color(0.40, 0.24, 0.17))
	_add_corridor_light(env_node, Vector3(17, 2.5, -29), 0.72, Color(0.36, 0.18, 0.13))

func _add_corridor_floor(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat
	mesh_inst.position = pos
	parent.add_child(mesh_inst)

func _add_corridor_collision(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)

func _add_corridor_ceiling(parent: Node3D, pos: Vector3, size: Vector3, emission_energy: float) -> void:
	var ceiling := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = size
	ceiling.mesh = cb
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.5, 0.5, 0.55)
	cm.emission_enabled = true
	cm.emission = Color(0.4, 0.4, 0.45)
	cm.emission_energy_multiplier = emission_energy
	ceiling.material_override = cm
	ceiling.position = pos
	parent.add_child(ceiling)

func _add_corridor_light(parent: Node3D, pos: Vector3, energy: float, color: Color) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 5.0
	parent.add_child(light)

func _add_booth(parent: Node3D, pos: Vector3, label_text: String) -> void:
	for z_off in [-0.6, 0.6]:
		var pillar := MeshInstance3D.new()
		var pbox := BoxMesh.new()
		pbox.size = Vector3(0.15, 2.5, 0.15)
		pillar.mesh = pbox
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.18, 0.18, 0.22)
		pillar.material_override = pmat
		pillar.position = pos + Vector3(0, 1.25, z_off)
		parent.add_child(pillar)

	var bar := MeshInstance3D.new()
	var barmesh := BoxMesh.new()
	barmesh.size = Vector3(0.15, 0.15, 1.35)
	bar.mesh = barmesh
	var barmat := StandardMaterial3D.new()
	barmat.albedo_color = Color(0.18, 0.18, 0.22)
	bar.material_override = barmat
	bar.position = pos + Vector3(0, 2.5, 0)
	parent.add_child(bar)

	var lbl := Label3D.new()
	lbl.text = label_text
	lbl.font_size = 36
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.3, 0.4, 0.6, 0.7)
	lbl.position = pos + Vector3(0, 2.2, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(lbl)
