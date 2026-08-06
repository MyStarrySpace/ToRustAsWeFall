# gdlint: disable=max-file-lines,max-returns
extends "res://scripts/scene_chunks/scene_chunk.gd"

const Layout := preload("res://scripts/fragments/layouts/stacks_open_files_layout.gd")
const ShellBuilder := preload("res://scripts/fragments/layouts/stacks_open_files_shell.gd")
const LevelDecoratorScript := preload("res://scripts/generation/level_decorator.gd")
const TypedTerminalScript := preload("res://scripts/game/objects/typed_terminal.gd")
const DrawerStairProducerScript := preload(
	"res://scripts/game/objects/drawer_stair_producer.gd"
)
const IronPurgeReceiverScript := preload(
	"res://scripts/game/objects/iron_purge_receiver.gd"
)
const SpoofAccessReceiverScript := preload(
	"res://scripts/game/objects/spoof_access_receiver.gd"
)
const EmpCutoffCircuitScript := preload(
	"res://scripts/game/objects/emp_cutoff_circuit.gd"
)
const SapscrapScript := preload("res://scripts/game/ai/sapscrap.gd")
const ArchiveSpireScene := preload(
	"res://scenes/fragments/themes/generated_stacks_archive_spire.tscn"
)

const PARTY_IDS := ["aster", "peris", "endo"]
const ASTER_ID := "aster"
const PERIS_ID := "peris"
const ARRIVAL_SITE_ID := "arrival_terminal"
const PURGE_TERMINAL_ID := "open_files_iron_purge"
const ACCESS_TERMINAL_ID := "open_files_location_spoof"
const SHELTER_AUTHORITY_KEY := "runtime:stacks_fragment:open_files_shelter"
const SHELTER_AUTHORITY_CONTRACT := "open_files_shelter/v1"
const SHELTER_AUTHORITY_VERSION := 1
const SHELTER_PHASES := ["ready", "committing", "rested"]
const INTERACTION_POSITION_TOLERANCE := 0.45
const SUPPORT_LOG_KEY := "stacks_support_team_log"

const ARRIVAL_DIALOGUE_KEYS := [
	"stacks.narration.enter",
	"stacks.aster.home",
	"stacks.peris.cold",
	"stacks.aster.terminal",
	"stacks.aster.cleaned",
	"stacks.aster.here",
	"stacks.peris.ok",
	"stacks.aster.not_sure",
	"stacks.narration.elegant",
	"stacks.narration.closet",
	"stacks.aster.archive",
	"stacks.aster.when",
	"stacks.peris.meaning",
	"stacks.aster.means",
]
const SUPPORT_DIALOGUE_KEYS := [
	"stacks.aster.cores",
	"stacks.peris.noisy",
	"stacks.narration.network_address",
	"stacks.aster.know_number",
	"stacks.aster.support_team",
	"stacks.aster.drink_machine",
	"stacks.peris.priorities",
	"stacks.narration.cleaned_terminal",
	"stacks.aster.cleaner_than_place",
	"stacks.aster.simplodrink",
	"stacks.peris.miss_machine",
	"stacks.aster.expectation",
]
const MAINTAINED_DIALOGUE_KEYS := [
	"stacks.narration.instrumented_lane",
	"stacks.aster.nonstandard",
	"stacks.aster.metrics",
	"stacks.peris.damn_cooler",
	"stacks.aster.cooling_part",
	"stacks.aster.standardization",
]
const GHOST_DIALOGUE_KEYS := [
	"stacks.narration.workspace",
	"stacks.aster.pull_archive",
	"stacks.aster.ghost_ids",
	"stacks.peris.fake_permissions",
	"stacks.aster.security_patch",
	"stacks.aster.not_the_type",
	"stacks.aster.right",
]

var _drawer_stairs: Dictionary = {}
var _sapscraps: Dictionary = {}
var _purge_terminal
var _purge_receiver
var _access_terminal
var _access_receiver
var _emp_circuit
var _narrative_interactables: Dictionary = {}
var _inspection_interactables: Dictionary = {}
var _inspection_labels: Dictionary = {}
var _shelter_interactable
var _runtime_ready := false
var _planning_active := false
var _aster_overlay_active := true
var _peris_overlay_active := true
var _decoration_audit: Dictionary = {}

var _shelter_phase := "ready"
var _shelter_commit_tick := -1.0
var _shelter_commit_day := 0
var _shelter_before_atp: Dictionary = {}
var _anxiety_seen := false
var _restoring_shelter := false
var _shelter_authority_initialized := false
var _shelter_authority_baseline: Dictionary = {}


func _build_chunk() -> void:
	_build_open_files_shell()
	_build_narrative_landmarks()
	_build_column_inspections()
	_build_shelter()
	_decoration_audit = LevelDecoratorScript.decorate_profile(self, "stacks", {
		"x0": -4.0,
		"x1": 184.0,
		"width": 48.0,
		"wall_height": 4.0,
		"ground_y": 0.0,
	})
	_initialize_shelter_authority()


func get_scene_title() -> String:
	return "The Open Files Initiative"


func get_scene_help() -> String:
	return "Read each drawer column with Aster and Peris, then use Aster at the catalog desk " \
		+ "to toggle the three category indices that form a sound deep-to-shallow stair. " \
		+ "In the second bay, redirect the Sapscraps with the iron purge, use EMP on the " \
		+ "faulted circuit, and spoof Aster's tracked location only for the optional lane."


func get_default_character() -> String:
	return ASTER_ID


func get_spawn_positions() -> Dictionary:
	return Layout.SPAWNS.duplicate(true)


func get_grid_data() -> Dictionary:
	return Layout.grid_data()


func get_preview_time_state() -> Dictionary:
	return {
		"day": 1,
		"time": 0.82,
		"routing_mode": "safe",
		"note_default": "The Open Files still answers Aster's device. Read the physical stacks, " \
			+ "predict one category set, and watch what every index actually moves.",
	}


func get_preview_abilities() -> Array:
	var abilities: Array = []
	for ability_v in AbilityData.for_context("default"):
		var ability := ability_v as Dictionary
		if str(ability.get("id", "")) == "emp":
			abilities.append(ability.duplicate(true))
	return abilities


func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors.merge({
		"arrival_terminal": Layout.RECON_TERMINAL_POS,
		"support_log": Layout.SUPPORT_LOG_POS,
		"spoof_terminal": Layout.SPOOF_TERMINAL_POS,
		"purge_terminal": Layout.PURGE_TERMINAL_POS,
		"emp_circuit": Layout.EMP_CIRCUIT_POS,
		"mule_trail": Layout.MULE_TRAIL_POS,
		"maintained_workspace": Layout.MAINTAINED_WORKSPACE_POS,
		"ghost_workspace": Layout.GHOST_WORKSPACE_POS,
		"shelter": Layout.SHELTER_POS,
	}, true)
	for bay_v in Layout.drawer_bay_specs():
		var bay := bay_v as Dictionary
		var controls := bay.get("control_positions", {}) as Dictionary
		for category_id_v in controls.keys():
			var category_id := str(category_id_v)
			anchors["%s_%s_index" % [bay.get("id", ""), category_id]] = \
				controls.get(category_id, Vector3.ZERO)
	return anchors


func get_playthrough_interaction_target(action_id: String) -> Node3D:
	match action_id:
		"arrival_terminal", "stacks_terminal", "scan_data":
			return _narrative_interactables.get(ARRIVAL_SITE_ID) as Node3D
		"spoof_terminal", "spoof_location":
			return _access_terminal as Node3D
		"purge_terminal", "iron_purge":
			return _purge_terminal as Node3D
		"support_log", "maintained_workspace", "ghost_workspace", "mule_trail":
			return _narrative_interactables.get(action_id) as Node3D
		"shelter", "shelter_rest", "stacks_shelter_rest":
			return _shelter_interactable as Node3D
	if action_id.begins_with("drawer_bay_"):
		var category_split := action_id.rsplit("_", false, 1)
		if category_split.size() == 2:
			var producer = _drawer_stairs.get(category_split[0])
			if is_instance_valid(producer):
				return producer.call("get_index_interactable", category_split[1]) as Node3D
	return _inspection_interactables.get(action_id) as Node3D \
		if _inspection_interactables.has(action_id) else null


func get_preview_state() -> Dictionary:
	_ensure_runtime_ready()
	var drawer_states := {}
	for bay_id_v in _drawer_stairs.keys():
		var bay_id := str(bay_id_v)
		var producer = _drawer_stairs.get(bay_id)
		drawer_states[bay_id] = producer.call("get_state") \
			if is_instance_valid(producer) else {}
	var sapscrap_states := {}
	for enemy_id_v in _sapscraps.keys():
		var enemy_id := str(enemy_id_v)
		sapscrap_states[enemy_id] = _enemy_report(_sapscraps.get(enemy_id) as Enemy)
	return {
		"contract": "open_files_encounter/v2",
		"drawer_bays": drawer_states,
		"iron_purge": _purge_receiver.get_state() \
			if is_instance_valid(_purge_receiver) else {},
		"spoofed_access": _access_receiver.get_state() \
			if is_instance_valid(_access_receiver) else {},
		"emp_cutoff": _emp_circuit.get_state() \
			if is_instance_valid(_emp_circuit) else {},
		"sapscraps": sapscrap_states,
		"narrative_seen": _narrative_seen_ids(),
		"shelter_phase": _shelter_phase,
		"rest_scene_seen": _anxiety_seen,
		"complete": _anxiety_seen,
		"terminal_effects": [
			"scan_data", "toggle_global_index", "expose_iron_fixture",
			"authorize_tracked_access", "emp_power_cut",
		],
	}


func get_decoration_audit() -> Dictionary:
	return _decoration_audit.duplicate(true)


func get_preview_overlay_status(overlay_id: String, _current_tick: float) -> Array:
	match overlay_id:
		"aster":
			return [
				"SCAN DATA reads category, height, and fixed depth; it reveals no patrol arrows.",
				"Each catalog index controls every drawer of its category across the whole bay.",
				"The purge exposes physical iron; the location spoof opens only Aster's optional access lane.",
				"EMP can fail-open the marked circuit. It does not disable biological Sapscraps.",
			]
		"peris":
			return [
				"READ CONDITION marks damp, Scarpet-grown drawers that cannot bear a character.",
				"The maintained lane is warmer and carefully instrumented, but its caretaker remains unnamed.",
			]
		"endo":
			return [
				"Extended drawers are physical cover even when they do not form the stair you predicted.",
				"Gather all three conscious party members inside the final shelter before resting.",
			]
	return []


func set_preview_planning_feedback(active: bool) -> void:
	_planning_active = active
	super.set_preview_planning_feedback(active)


func update_preview_overlay_states(
		overlay_states: Dictionary, _current_tick: float, _delta: float
	) -> void:
	_aster_overlay_active = bool(overlay_states.get("aster", false))
	_peris_overlay_active = bool(overlay_states.get("peris", false))
	_update_inspection_presenters()


func on_game_state_grid_ready() -> void:
	_ensure_runtime_ready()
	_apply_shelter_presenter()


## Compatibility probes remain deliberately inert. Gameplay changes require physical receipts.
func trigger_stacks_bank(_bank_id: String) -> bool:
	return false


func trigger_stacks_shelter_rest(_play_dialogue := true) -> bool:
	return false


func _build_open_files_shell() -> void:
	ShellBuilder.build(self, Layout, ArchiveSpireScene)


func _build_narrative_landmarks() -> void:
	_build_narrative_console(
		ARRIVAL_SITE_ID, Layout.RECON_TERMINAL_POS, "CLEANED CORE DIRECTORY",
		Color(0.29, 0.74, 1.0), ARRIVAL_DIALOGUE_KEYS,
		"The terminal's cleaned-data metadata is now visible in Aster's data layer."
	)
	_build_narrative_console(
		"support_log", Layout.SUPPORT_LOG_POS, "CLEANED SUPPORT INTAKE",
		Color(0.28, 0.84, 0.54), SUPPORT_DIALOGUE_KEYS,
		"The support report is cleaner than the abandoned room that produced it."
	)
	_build_narrative_console(
		"maintained_workspace", Layout.MAINTAINED_WORKSPACE_POS, "UNOFFICIAL SENSOR WALL",
		Color(0.94, 0.63, 0.30), MAINTAINED_DIALOGUE_KEYS,
		"This pocket was kept instrumented and cool after the surrounding district was abandoned."
	)
	_build_narrative_console(
		"ghost_workspace", Layout.GHOST_WORKSPACE_POS, "SURVIVING WORKSPACE",
		Color(0.34, 0.74, 0.92), GHOST_DIALOGUE_KEYS,
		"The workspace survived because somebody maintained exemptions by hand."
	)
	_add_box(self, Layout.MULE_TRAIL_POS + Vector3(0.0, 0.72, 0.0),
		Vector3(2.0, 1.45, 1.1), Color(0.055, 0.045, 0.065),
		Color(0.52, 0.40, 0.72), 0.35, "MuleTrailPendingHousing")
	_add_label(self, "MLR CASE TRAIL // FRAGMENT HEADERS ONLY",
		Layout.MULE_TRAIL_POS + Vector3(0.0, 2.2, 0.0), Color(0.68, 0.55, 0.84))


func _build_narrative_console(
		site_id: String, world_position: Vector3, title: String, tint: Color,
		dialogue_keys: Array, note: String
	) -> void:
	var housing := _add_box(self, world_position + Vector3(0.0, 0.70, 0.0),
		Vector3(2.2, 1.55, 1.25), Color(0.045, 0.055, 0.057), tint, 0.18,
		"%sHousing" % site_id.to_pascal_case())
	var display := _add_box(self, world_position + Vector3(0.0, 1.02, 0.66),
		Vector3(1.55, 0.58, 0.06), tint.darkened(0.72), tint, 1.15,
		"%sDisplay" % site_id.to_pascal_case())
	_add_label(self, title, world_position + Vector3(0.0, 2.25, 0.0), tint)
	var interactable := _add_object_interactable(
		self, "%sRecord" % site_id.to_pascal_case(), title.capitalize(), world_position,
		"READ", [housing, display], ASTER_ID, 0.0, true, 1.65,
		Interactable.InteractableType.INSPECTION
	)
	interactable.set("consequence_preview", "Read this surviving record through Aster's data layer")
	interactable.set_pre_trigger_validator(_validate_narrative_trigger.bind(interactable))
	interactable.interacted.connect(
		_on_narrative_interacted.bind(interactable, site_id, dialogue_keys, note)
	)
	_narrative_interactables[site_id] = interactable


func _validate_narrative_trigger(source: Node, actor: String, expected_source: Node) -> bool:
	return source != null and source == expected_source and actor == ASTER_ID \
		and _actor_can_interact_here(_get_game_state(), actor, source)


func _on_narrative_interacted(
		source: Node, site_id: String, dialogue_keys: Array, note: String
	) -> void:
	if source != _narrative_interactables.get(site_id) \
			or not _semantic_trigger_receipt_is_pending(source, ASTER_ID):
		return
	if site_id == "support_log":
		_ensure_support_log_entry()
	_clear_dialogue()
	for key_v in dialogue_keys:
		_say_key(str(key_v))
	_show_note(note, 4.2)
	_apply_shelter_presenter()


func _ensure_support_log_entry() -> Dictionary:
	var journal := get_node_or_null("/root/EngramJournal")
	if journal == null or not journal.has_method("ensure_story_log_entry"):
		return {}
	return journal.call("ensure_story_log_entry", SUPPORT_LOG_KEY,
		DialogueData.text("stacks.engram.support_log.title"),
		DialogueData.text("stacks.engram.support_log.body"), {
			"scene_name": "The Open Files Initiative", "act": 1, "day": 1,
			"location": "The Open Files Initiative", "sub_location": "Support Team Thread",
			"trigger_type": "story", "trigger_context": "support_team_log",
			"position": Layout.SUPPORT_LOG_POS,
		}, {"caption": "Support team maintenance log", "trigger_context": "support_team_log"})


func _build_column_inspections() -> void:
	for bay_v in Layout.drawer_bay_specs():
		var bay := bay_v as Dictionary
		var bay_id := str(bay.get("id", ""))
		var columns := bay.get("columns", []) as Array
		var aster_positions := bay.get("aster_inspection_positions", []) as Array
		var peris_positions := bay.get("peris_inspection_positions", []) as Array
		for index in range(columns.size()):
			var column := columns[index] as Dictionary
			var column_id := str(column.get("id", ""))
			_build_column_inspection(
				bay_id, column, "aster", aster_positions[index] as Vector3, ASTER_ID,
				"SCAN TAG PLATES", Color(0.29, 0.74, 1.0)
			)
			_build_column_inspection(
				bay_id, column, "peris", peris_positions[index] as Vector3, PERIS_ID,
				"READ CONDITION", Color(0.95, 0.69, 0.27)
			)
			var max_y := 0.0
			for module_v in column.get("modules", []) as Array:
				var module := module_v as Dictionary
				max_y = maxf(max_y,
					(module.get("wall_face_position", Vector3.ZERO) as Vector3).y)
			var label_position := Vector3(
				float((column.get("link_world_position", Vector3.ZERO) as Vector3).x),
				max_y + 1.2,
				-8.9
			)
			var aster_label := _add_label(
				self, _aster_column_text(column), label_position, Color(0.42, 0.86, 1.0)
			)
			aster_label.pixel_size = 0.006
			aster_label.font_size = 34
			aster_label.no_depth_test = true
			aster_label.set_meta("camera_occlusion_exempt", true)
			var peris_label := _add_label(
				self, _peris_column_text(column),
				label_position + Vector3(0.0, -0.8, 0.0), Color(1.0, 0.72, 0.30)
			)
			peris_label.pixel_size = 0.006
			peris_label.font_size = 34
			peris_label.no_depth_test = true
			peris_label.set_meta("camera_occlusion_exempt", true)
			_inspection_labels["%s:%s" % [bay_id, column_id]] = {
				"aster": aster_label,
				"peris": peris_label,
			}
	_update_inspection_presenters()


func _build_column_inspection(
		bay_id: String,
		column: Dictionary,
		register_id: String,
		world_position: Vector3,
		required_character: String,
		action_label: String,
		tint: Color
	) -> void:
	var column_id := str(column.get("id", ""))
	var key := "%s_%s_%s" % [bay_id, column_id, register_id]
	var plate := _add_box(
		self, world_position + Vector3(0.0, 0.12, 0.0),
		Vector3(1.15, 0.12, 1.15), tint.darkened(0.78), tint, 0.65,
		"%sInspectionPlate" % key.to_pascal_case()
	)
	var source := _add_object_interactable(
		self, "%sInspection" % key.to_pascal_case(),
		"%s column %s" % [action_label.capitalize(), column_id],
		world_position, action_label, [plate], required_character, 0.0, true, 1.65,
		Interactable.InteractableType.INSPECTION
	)
	source.set(
		"consequence_preview",
		"Reveal category, height, and extension depth in Aster's data layer"
		if register_id == "aster"
		else "Mark damp or Scarpet-rotted drawers in Peris's condition layer"
	)
	source.set_pre_trigger_validator(
		_validate_column_inspection.bind(source, required_character))
	source.interacted.connect(
		_on_column_inspected.bind(source, bay_id, column_id, register_id, required_character)
	)
	_inspection_interactables[key] = source


func _validate_column_inspection(
		source: Node, actor: String, expected_source: Node, required_character: String
	) -> bool:
	return source == expected_source and actor == required_character \
		and _actor_can_interact_here(_get_game_state(), actor, source)


func _on_column_inspected(
		source: Node,
		_bay_id: String,
		_column_id: String,
		register_id: String,
		required_character: String
	) -> void:
	if not _semantic_trigger_receipt_is_pending(source, required_character):
		return
	_update_inspection_presenters()
	var message := (
		"Tag-plate metadata retained. Category depth is global; its height depends on the column."
		if register_id == "aster"
		else "Condition read retained. Amber rot marks identify steps that cannot bear weight."
	)
	_show_note(message, 3.2)


func _aster_column_text(column: Dictionary) -> String:
	var lines: Array[String] = []
	var modules := (column.get("modules", []) as Array).duplicate()
	modules.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("height", 0)) < int(b.get("height", 0))
	)
	for module_v in modules:
		var module := module_v as Dictionary
		lines.append("H%d  %s  // %s" % [
			int(module.get("height", 0)) + 1,
			str(module.get("category", "")).to_upper(),
			str(module.get("depth", "")).to_upper(),
		])
	return "\n".join(lines)


func _peris_column_text(column: Dictionary) -> String:
	var rotten := column.get("rotten_categories", []) as Array
	if rotten.is_empty():
		return "LOAD READ // SOUND"
	var labels: Array[String] = []
	for category_v in rotten:
		labels.append(str(category_v).to_upper())
	return "ROT / SCARPET // %s" % ", ".join(labels)


func _inspection_triggered(interaction_key: String) -> bool:
	var source = _inspection_interactables.get(interaction_key)
	var gs = _get_game_state()
	if not is_instance_valid(source) or gs == null:
		return false
	var data_id := str(source.get("data_id"))
	return not data_id.is_empty() and gs.has_interactable(data_id) \
		and bool(gs.get_interactable(data_id).get("triggered", false))


func _update_inspection_presenters() -> void:
	for bay_v in Layout.drawer_bay_specs():
		var bay := bay_v as Dictionary
		var bay_id := str(bay.get("id", ""))
		for column_v in bay.get("columns", []) as Array:
			var column := column_v as Dictionary
			var column_id := str(column.get("id", ""))
			var labels := _inspection_labels.get(
				"%s:%s" % [bay_id, column_id], {}) as Dictionary
			var aster_label := labels.get("aster") as Label3D
			var peris_label := labels.get("peris") as Label3D
			if is_instance_valid(aster_label):
				aster_label.visible = _aster_overlay_active and _inspection_triggered(
					"%s_%s_aster" % [bay_id, column_id])
			if is_instance_valid(peris_label):
				peris_label.visible = _peris_overlay_active and _inspection_triggered(
					"%s_%s_peris" % [bay_id, column_id])


func _ensure_runtime_ready() -> void:
	if _runtime_ready:
		return
	var gs = _get_game_state()
	if gs == null or _get_scheduler() == null or gs.grid == null:
		return
	_spawn_sapscraps(gs)
	_build_drawer_stairs(gs)
	_build_iron_purge(gs)
	_build_spoofed_access(gs)
	_build_emp_cutoff(gs)
	_runtime_ready = _drawer_stairs.size() == Layout.drawer_bay_specs().size() \
		and _sapscraps.size() == Layout.sapscrap_specs().size() \
		and is_instance_valid(_purge_terminal) and is_instance_valid(_purge_receiver) \
		and is_instance_valid(_access_terminal) and is_instance_valid(_access_receiver) \
		and is_instance_valid(_emp_circuit)
	_apply_shelter_presenter()


func _spawn_sapscraps(gs: GameState) -> void:
	for spec_v in Layout.sapscrap_specs():
		var spec := spec_v as Dictionary
		var enemy_id := str(spec.get("id", ""))
		if _sapscraps.has(enemy_id):
			continue
		var spawn_position := spec.get("spawn_position", Vector3.ZERO) as Vector3
		var patrol: Array[Vector3] = []
		for point_v in spec.get("patrol_points", []) as Array:
			patrol.append(point_v as Vector3)
		var enemy := SapscrapScript.new() as Enemy
		enemy.char_id = enemy_id
		enemy.game_state = gs
		enemy.name = enemy_id.to_pascal_case()
		var already_registered := bool(gs.characters.has(enemy_id))
		var saved_authority: Variant = gs.get_world_state("runtime:enemy:" + enemy_id, {}) \
			if gs.has_method("get_world_state") else {}
		enemy.position = gs.get_position(enemy_id) if already_registered else spawn_position
		add_child(enemy)
		if not already_registered:
			gs.register_character(enemy_id, spawn_position, enemy.move_speed, {
				"detection_range": enemy.detection_range,
			})
		enemy.activate()
		enemy.set_detection_targets(PARTY_IDS)
		if not (saved_authority is Dictionary and not (saved_authority as Dictionary).is_empty()):
			enemy.configure_patrol(patrol)
			enemy.begin_home_behavior()
		_sapscraps[enemy_id] = enemy


func _build_drawer_stairs(gs: GameState) -> void:
	for bay_v in Layout.drawer_bay_specs():
		var bay := bay_v as Dictionary
		var bay_id := str(bay.get("id", ""))
		if _drawer_stairs.has(bay_id):
			continue
		var producer := DrawerStairProducerScript.new()
		producer.name = bay_id.to_pascal_case()
		add_child(producer)
		var topology := {
			"valid_active_sets": [bay.get("solution_categories", [])],
			"links": _drawer_link_specs(bay),
			"route_blocker_cells": [],
			"route_blocker_tag": "",
		}
		if not bool(producer.configure(
			gs, bay_id, _drawer_index_specs(bay), topology, {
				"duration": 1.35,
				"interaction_radius": 1.8,
				"required_character": ASTER_ID,
				"stagger_fraction": 0.07,
			}
		)):
			producer.queue_free()
			push_error("Open Files drawer stair rejected bay %s" % bay_id)
			continue
		_drawer_stairs[bay_id] = producer
		for source_v in producer.get_index_interactables():
			var source := source_v as Interactable
			source.active_character = _get_active_character()
			_register_interactable(source)
			source.show_tutorial_label()
			_add_drawer_index_links(producer, source, bay, str(
				source.get_meta("drawer_stair_index_id", "")))
		producer.index_transition_started.connect(_on_drawer_transition_started)
		producer.index_transition_completed.connect(_on_drawer_transition_completed)
		producer.staircase_state_changed.connect(
			_on_drawer_staircase_changed.bind(producer)
		)


func _drawer_index_specs(bay: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var controls := bay.get("control_positions", {}) as Dictionary
	for category_v in bay.get("categories", []) as Array:
		var category := category_v as Dictionary
		var category_id := str(category.get("id", ""))
		var modules: Array[Dictionary] = []
		for column_v in bay.get("columns", []) as Array:
			var column := column_v as Dictionary
			for module_v in column.get("modules", []) as Array:
				var module := module_v as Dictionary
				if str(module.get("category", "")) == category_id:
					modules.append(module.duplicate(true))
		result.append({
			"index_id": category_id,
			"label": category.get("label", category_id),
			"tint": category.get("tint", Color(0.35, 0.75, 0.85)),
			"lever_data_position": controls.get(category_id, Vector3.ZERO),
			"lever_render_position": controls.get(category_id, Vector3.ZERO),
			"drawer_modules": modules,
		})
	return result


func _drawer_link_specs(bay: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for column_v in bay.get("columns", []) as Array:
		var column := column_v as Dictionary
		result.append({
			"column_id": column.get("id", ""),
			"cell": column.get("link_cell", []),
			"from_level": column.get("from_level", -1),
			"to_level": column.get("to_level", -1),
			"type": "ramp",
			"bidirectional": true,
		})
	return result


func _add_drawer_index_links(
		producer: Node3D, source: Node3D, bay: Dictionary, category_id: String
	) -> void:
	if category_id.is_empty():
		return
	var link_index := 0
	for column_v in bay.get("columns", []) as Array:
		var column := column_v as Dictionary
		for module_v in column.get("modules", []) as Array:
			var module := module_v as Dictionary
			if str(module.get("category", "")) != category_id:
				continue
			var marker := Node3D.new()
			marker.name = "%s%sLinkTarget%d" % [
				str(bay.get("id", "")).to_pascal_case(), category_id.to_pascal_case(), link_index]
			marker.position = module.get("extended_position", Vector3.ZERO)
			producer.add_child(marker)
			_add_causal_feedback_link(source, marker, Color(0.29, 0.74, 1.0), {
				"name": "%sDataLink" % marker.name,
				"interaction_source": source,
				"label": "",
				"visibility_policy": "hover_only",
				"owner_character": ASTER_ID,
				"path_style": "dashes",
				"feedback_mode": "predicted",
				"flow_speed": 0.26,
				"source_offset": Vector3(0.0, 0.8, 0.0),
				"target_offset": Vector3.ZERO,
				"arc_height": 0.7,
			})
			link_index += 1


func _on_drawer_transition_started(
		index_id: String, target_extended: bool, _state: Dictionary
	) -> void:
	_show_note("%s index %s every %s drawer." % [
		index_id.to_upper(), "extends" if target_extended else "retracts",
		index_id.to_upper()], 2.4)


func _on_drawer_transition_completed(
		_index_id: String, _extended: bool, _state: Dictionary
	) -> void:
	_request_preview_shake(0.08, 5.0)


func _on_drawer_staircase_changed(
		ready: bool, _solved_columns: Array[String], _state: Dictionary, producer: Node
	) -> void:
	if ready:
		_show_note("The active categories now form one sound deep-to-shallow stair.", 3.0)
		_request_preview_focus(producer, 0.75, false)
		_set_preview_step(
			"stacks_transfer" if producer.get_stair_id() == "drawer_bay_one"
			else "stacks_shelter_route"
		)


func _register_typed_terminal(terminal: Node, outline_name: String) -> void:
	terminal.set("active_character", _get_active_character())
	_register_interactable(terminal)
	if terminal.has_method("show_tutorial_label"):
		terminal.call("show_tutorial_label")
	var meshes: Array = terminal.call("get_visual_meshes")
	var target := _outline_object(
		self, outline_name + "Outline", meshes,
		str(terminal.call("terminal_source_id")), float(terminal.get("interaction_radius"))
	)
	if target != null:
		if target.has_method("set_interaction_delegate"):
			target.call("set_interaction_delegate", terminal)
		terminal.call("set_outline_target", target)


func _build_iron_purge(gs: GameState) -> void:
	var spec := Layout.purge_spec()
	var receiver := IronPurgeReceiverScript.new()
	if not bool(receiver.configure(
		gs, str(spec.get("id", "")), PURGE_TERMINAL_ID,
		spec.get("fixture_retracted_position", Vector3.ZERO),
		spec.get("fixture_exposed_position", Vector3.ZERO),
		spec.get("fixture_size", Vector3.ONE),
		spec.get("affected_sapscrap_ids", []), 18.0
	)):
		receiver.free()
		push_error("Open Files iron purge receiver rejected its authored fixture")
		return
	add_child(receiver)
	_purge_receiver = receiver
	for enemy_id_v in spec.get("affected_sapscrap_ids", []) as Array:
		var enemy = _sapscraps.get(str(enemy_id_v))
		if is_instance_valid(enemy):
			receiver.bind_enemy(enemy)
	var terminal := TypedTerminalScript.new()
	if not bool(terminal.configure(
		gs, spec.get("terminal_position", Vector3.ZERO), PURGE_TERMINAL_ID,
		"signal", receiver, ASTER_ID, 1.85
	)):
		terminal.free()
		push_error("Open Files iron purge terminal could not bind its receiver")
		return
	add_child(terminal)
	_purge_terminal = terminal
	terminal.description = "Iron-purge terminal"
	terminal.tutorial_label = "HACK PURGE"
	terminal.consequence_preview = "Expose the linked sacrificial iron fixture"
	_register_typed_terminal(terminal, "OpenFilesIronPurgeTerminal")
	terminal.terminal_command_delivered.connect(_on_purge_delivered)
	_add_causal_feedback_link(terminal, receiver.get_fixture_visual(),
		Color(0.29, 0.74, 1.0), {
			"name": "OpenFilesIronPurgeDataLink",
			"interaction_source": terminal,
			"label": "",
			"visibility_policy": "hover_only",
			"owner_character": ASTER_ID,
			"path_style": "dashes",
			"feedback_mode": "predicted",
			"flow_speed": 0.30,
			"source_offset": Vector3(0.0, 0.9, 0.0),
			"target_offset": Vector3(0.0, 0.5, 0.0),
			"arc_height": 1.0,
		})


func _on_purge_delivered(_command: Dictionary) -> void:
	_show_note(
		"The purge exposed sacrificial iron. Sapscraps leave one lane and crowd that source.",
		3.8
	)
	_request_preview_focus(_purge_receiver, 0.9, false)


func _build_spoofed_access(gs: GameState) -> void:
	var spec := Layout.optional_lane_spec()
	var receiver := SpoofAccessReceiverScript.new()
	if not bool(receiver.configure(
		gs, str(spec.get("id", "")), spec.get("entry_position", Vector3.ZERO),
		spec.get("gate_cells", []), {"gate_size": Vector3(7.0, 3.2, 0.45)}
	)):
		receiver.free()
		push_error("Open Files spoofed-access receiver rejected its optional gate")
		return
	add_child(receiver)
	_access_receiver = receiver
	var terminal := TypedTerminalScript.new()
	if not bool(terminal.configure(
		gs, spec.get("terminal_position", Vector3.ZERO), ACCESS_TERMINAL_ID,
		"credential", receiver, ASTER_ID, 1.85
	)):
		terminal.free()
		push_error("Open Files location-spoof terminal could not bind its access gate")
		return
	add_child(terminal)
	_access_terminal = terminal
	terminal.description = "Tracked-access location-spoof terminal"
	terminal.tutorial_label = "SPOOF LOCATION"
	terminal.consequence_preview = "Authorize only the linked optional maintenance lane"
	_register_typed_terminal(terminal, "OpenFilesLocationSpoofTerminal")
	terminal.terminal_command_delivered.connect(_on_access_spoof_delivered)
	_add_causal_feedback_link(terminal, receiver, Color(0.29, 0.74, 1.0), {
		"name": "OpenFilesSpoofAccessDataLink",
		"interaction_source": terminal,
		"label": "",
		"visibility_policy": "hover_only",
		"owner_character": ASTER_ID,
		"path_style": "dashes",
		"feedback_mode": "predicted",
		"flow_speed": 0.30,
		"source_offset": Vector3(0.0, 0.9, 0.0),
		"target_offset": Vector3(0.0, 1.0, 0.0),
		"arc_height": 0.9,
	})


func _on_access_spoof_delivered(_command: Dictionary) -> void:
	_show_note(
		"Aster's reported location now satisfies this tracker. Only the optional lane opened.",
		3.4
	)
	_request_preview_focus(_access_receiver, 0.8, false)


func _build_emp_cutoff(gs: GameState) -> void:
	var spec := Layout.emp_circuit_spec()
	var circuit := EmpCutoffCircuitScript.new()
	if not bool(circuit.configure(
		gs, str(spec.get("id", "")), spec.get("position", Vector3.ZERO),
		spec.get("affected_cells", []), {
			"gate_local_position": Vector3(-8.0, 1.6, -13.5),
			"gate_size": Vector3(0.55, 3.2, 3.2),
		}
	)):
		circuit.free()
		push_error("Open Files EMP cutoff rejected its authored route")
		return
	add_child(circuit)
	_emp_circuit = circuit
	circuit.power_cut_committed.connect(_on_emp_cutoff_committed)


func _on_emp_cutoff_committed(_circuit_id: String, _state: Dictionary) -> void:
	_show_note("EMP cut the faulted circuit's power. The short regroup route failed open.", 3.0)
	_request_preview_shake(0.10, 7.0)


func _enemy_report(enemy: Enemy) -> Dictionary:
	if enemy == null or not is_instance_valid(enemy):
		return {}
	return {
		"id": enemy.char_id,
		"name": enemy.display_name,
		"state": enemy.get_state(),
		"emp_compatible": enemy.emp_compatible,
		"speed": enemy.move_speed,
		"pursuit_speed": enemy.pursuit_speed,
		"detection_range": enemy.detection_range,
		"position": _get_game_state().get_position(enemy.char_id) \
			if _get_game_state() != null and _get_game_state().characters.has(enemy.char_id) \
			else enemy.position,
	}


func _build_shelter() -> void:
	var shelter_pad := _add_authored_shelter_region(
		self, Layout.SHELTER_POS, Layout.SHELTER_SIZE)
	_add_box(self, Layout.SHELTER_POS + Vector3(0.0, 1.55, 4.15),
		Vector3(10.6, 3.1, 0.34), Color(0.105, 0.083, 0.057))
	_add_box(self, Layout.SHELTER_POS + Vector3(5.15, 1.55, 0.0),
		Vector3(0.34, 3.1, 8.3), Color(0.105, 0.083, 0.057))
	_add_box(self, Layout.SHELTER_POS + Vector3(-5.15, 1.55, 0.0),
		Vector3(0.34, 3.1, 8.3), Color(0.105, 0.083, 0.057))
	_shelter_interactable = _add_interactable(
		self, "OpenFilesShelterRest", "Rest with the party", Layout.SHELTER_POS,
		"REST PARTY", "", 1.2, true, 2.6, Interactable.InteractableType.HOLD_ACTION
	)
	_shelter_interactable.set_meta(
		"interaction_activation_contract", "proximity_rest")
	_shelter_interactable.set_meta("authored_shelter_pad", shelter_pad)
	_shelter_interactable.set("consequence_preview",
		"Settle here with Aster, Peris, and Endo after reading the cleaned support record")
	_shelter_interactable.set_pre_trigger_validator(_validate_shelter_trigger)
	_shelter_interactable.interacted.connect(
		_on_shelter_interacted.bind(_shelter_interactable))
	_apply_shelter_presenter()


func _validate_shelter_trigger(source: Node, actor: String) -> bool:
	if source == null or source != _shelter_interactable or _shelter_phase != "ready" \
			or not _shelter_context_ready():
		return false
	if actor not in PARTY_IDS or not _actor_can_interact_here(_get_game_state(), actor, source):
		return false
	var preflight := _preflight_authored_party_rest(
		Layout.SHELTER_POS, Layout.SHELTER_SIZE, PARTY_IDS
	)
	return (preflight.get("blocked", []) as Array).is_empty()


func _on_shelter_interacted(source: Node) -> void:
	if source != _shelter_interactable or _shelter_phase != "ready":
		return
	var actor := str(source.get("active_character"))
	if not _semantic_trigger_receipt_is_pending(source, actor):
		return
	var preflight := _preflight_authored_party_rest(
		Layout.SHELTER_POS, Layout.SHELTER_SIZE, PARTY_IDS
	)
	var blocked := preflight.get("blocked", []) as Array
	if not blocked.is_empty():
		_rearm_shelter()
		_show_message(str(blocked[0]), 1.8)
		return
	var gs = _get_game_state()
	if gs == null:
		_rearm_shelter()
		return
	_shelter_phase = "committing"
	_shelter_commit_tick = _get_scheduler_tick()
	_shelter_commit_day = gs.get_game_day()
	_shelter_before_atp = (preflight.get("before_atp", {}) as Dictionary).duplicate(true)
	_apply_shelter_presenter()
	_publish_shelter_authority()
	if not bool(gs.command_party_rest(PARTY_IDS)):
		_shelter_phase = "ready"
		_clear_shelter_commit_context()
		_rearm_shelter()
		_publish_shelter_authority()
		_show_message("The party could not settle into this shelter.", 1.8)
		return
	_complete_shelter_rest(true)


func _complete_shelter_rest(show_story: bool) -> void:
	if _shelter_phase == "rested":
		return
	_cancel_shelter_callback()
	_shelter_phase = "rested"
	_anxiety_seen = true
	_clear_shelter_commit_context()
	if show_story:
		_clear_dialogue()
		for key in [
			"stacks.rest.narration.open",
			"stacks.rest.narration.peris_quiet",
			"stacks.rest.peris.breath",
			"stacks.rest.peris.cant",
			"stacks.rest.peris.silence",
			"stacks.rest.peris.try_again",
			"stacks.rest.peris.scared",
			"stacks.rest.peris.ask",
			"stacks.rest.peris.wait_for_answer",
			"stacks.rest.aster.start",
			"stacks.rest.aster.models",
			"stacks.rest.aster.focus",
			"stacks.rest.aster.application",
			"stacks.rest.aster.peris",
			"stacks.rest.peris.listening",
			"stacks.rest.peris.huh",
			"stacks.rest.peris.focus",
			"stacks.rest.peris.breath_settles",
			"stacks.rest.aster.notice",
			"stacks.rest.peris.yeah",
			"stacks.rest.narration.close",
		]:
			_say_key(key)
		_show_note("Focus on what matters. The fear eases enough to keep moving.", 4.0)
	_set_preview_step("stacks_fragment_complete")
	_apply_shelter_presenter()
	_publish_shelter_authority()


func _shelter_context_ready() -> bool:
	return _narrative_interactable_triggered(ARRIVAL_SITE_ID) \
		and _narrative_interactable_triggered("support_log")


func _apply_shelter_presenter() -> void:
	if not is_instance_valid(_shelter_interactable):
		return
	var enabled := _shelter_phase == "ready" and _shelter_context_ready()
	if _shelter_interactable.is_interaction_enabled() != enabled:
		_shelter_interactable.set_interaction_enabled(enabled)
	if enabled:
		_shelter_interactable.set("tutorial_label", "REST PARTY")
		_shelter_interactable.set("description", "Rest with the party")
	elif _shelter_phase == "rested":
		_shelter_interactable.set("tutorial_label", "RESTED")
	else:
		_shelter_interactable.set("tutorial_label", "READ ARRIVAL + SUPPORT RECORDS")


func _rearm_shelter() -> void:
	if not is_instance_valid(_shelter_interactable):
		return
	_shelter_interactable.reset()
	_apply_shelter_presenter()


func _actor_can_interact_here(gs, actor: String, source: Node) -> bool:
	if gs == null or source == null or not (source is Node3D) or not gs.characters.has(actor):
		return false
	var party: Array = gs.get_party() if gs.has_method("get_party") else []
	if not party.is_empty() and not party.has(actor):
		return false
	if (gs.has_method("is_narratively_available") and not gs.is_narratively_available(actor)) \
			or gs.is_downed(actor) or gs.is_knocked_down(actor) or gs.is_moving(actor):
		return false
	var source_position := (source as Node3D).global_position
	if gs.coord_map != null and gs.coord_map.has_method("to_data"):
		source_position = gs.coord_map.to_data(source_position)
	var radius := float(source.get("interaction_radius"))
	return Vector2(
		gs.get_position(actor).x - source_position.x,
		gs.get_position(actor).z - source_position.z
	).length() <= radius + INTERACTION_POSITION_TOLERANCE


func _semantic_trigger_receipt_is_pending(source: Node, actor: String) -> bool:
	if source == null or str(source.get("active_character")) != actor \
			or not bool(source.get("one_shot")) or not bool(source.get("_used")) \
			or bool(source.call("is_interaction_enabled")):
		return false
	var gs = _get_game_state()
	if gs == null:
		return false
	var data_id := str(source.get("data_id"))
	if data_id.is_empty() or not gs.has_interactable(data_id):
		return false
	var receipt: Dictionary = gs.get_interactable(data_id)
	return bool(receipt.get("one_shot", false)) and bool(receipt.get("triggered", false)) \
		and not bool(receipt.get("enabled", true))


func _narrative_interactable_triggered(site_id: String) -> bool:
	var interactable = _narrative_interactables.get(site_id)
	var gs = _get_game_state()
	if not is_instance_valid(interactable) or gs == null:
		return false
	var data_id := str(interactable.get("data_id"))
	if data_id.is_empty() or not gs.has_interactable(data_id):
		return false
	return bool(gs.get_interactable(data_id).get("triggered", false))


func _narrative_seen_ids() -> Array[String]:
	var seen: Array[String] = []
	var ids: Array = _narrative_interactables.keys()
	ids.sort()
	for site_id_v in ids:
		var site_id := str(site_id_v)
		if _narrative_interactable_triggered(site_id):
			seen.append(site_id)
	return seen


func shelter_authority_key() -> String:
	return SHELTER_AUTHORITY_KEY


func _baseline_shelter_authority() -> Dictionary:
	return {
		"contract": SHELTER_AUTHORITY_CONTRACT,
		"version": SHELTER_AUTHORITY_VERSION,
		"authority_id": shelter_authority_key(),
		"phase": "ready",
		"members": PARTY_IDS.duplicate(),
		"commit_tick": -1.0,
		"commit_day": 0,
		"before_atp": {},
		"anxiety_seen": false,
	}


func _shelter_authority_state() -> Dictionary:
	return {
		"contract": SHELTER_AUTHORITY_CONTRACT,
		"version": SHELTER_AUTHORITY_VERSION,
		"authority_id": shelter_authority_key(),
		"phase": _shelter_phase,
		"members": PARTY_IDS.duplicate(),
		"commit_tick": _shelter_commit_tick,
		"commit_day": _shelter_commit_day,
		"before_atp": _shelter_before_atp.duplicate(true),
		"anxiety_seen": _anxiety_seen,
	}


func _valid_shelter_authority(raw: Variant) -> bool:
	if not (raw is Dictionary):
		return false
	var saved := raw as Dictionary
	var phase := str(saved.get("phase", ""))
	var valid: bool = not (str(saved.get("contract", "")) != SHELTER_AUTHORITY_CONTRACT \
			or int(saved.get("version", 0)) != SHELTER_AUTHORITY_VERSION \
			or str(saved.get("authority_id", "")) != shelter_authority_key() \
			or phase not in SHELTER_PHASES \
			or saved.get("members", []) != PARTY_IDS \
			or bool(saved.get("anxiety_seen", false)) != (phase == "rested"))
	if not valid:
		return false
	var before_v: Variant = saved.get("before_atp", null)
	valid = before_v is Dictionary
	if phase == "committing":
		valid = valid and float(saved.get("commit_tick", -1.0)) >= 0.0 \
			and int(saved.get("commit_day", 0)) >= 1
		if valid:
			var before := before_v as Dictionary
			for char_id in PARTY_IDS:
				valid = valid and before.has(char_id) and float(before.get(char_id, 0.0)) >= 1.0
	else:
		valid = valid and is_equal_approx(float(saved.get("commit_tick", -1.0)), -1.0) \
			and (before_v as Dictionary).is_empty()
	return valid


func _initialize_shelter_authority() -> void:
	if _shelter_authority_initialized:
		return
	var gs = _get_game_state()
	if gs == null or not gs.has_method("get_world_state"):
		return
	_shelter_authority_initialized = true
	_shelter_authority_baseline = _baseline_shelter_authority()
	var raw: Variant = gs.get_world_state(shelter_authority_key(), null)
	if _valid_shelter_authority(raw):
		_restore_shelter_authority(raw as Dictionary)
	else:
		_restore_shelter_authority(_shelter_authority_baseline)
		_publish_shelter_authority()


func _publish_shelter_authority() -> void:
	if _restoring_shelter:
		return
	var gs = _get_game_state()
	if gs != null and gs.has_method("set_world_state"):
		gs.set_world_state(shelter_authority_key(), _shelter_authority_state())


func _restore_shelter_authority(saved: Dictionary) -> void:
	_restoring_shelter = true
	_cancel_shelter_callback()
	_shelter_phase = str(saved.get("phase", "ready"))
	_shelter_commit_tick = float(saved.get("commit_tick", -1.0))
	_shelter_commit_day = int(saved.get("commit_day", 0))
	_shelter_before_atp = (saved.get("before_atp", {}) as Dictionary).duplicate(true)
	_anxiety_seen = bool(saved.get("anxiety_seen", false))
	_apply_shelter_presenter()
	_restoring_shelter = false
	if _shelter_phase == "committing":
		_arm_shelter_callback()


func _clear_shelter_commit_context() -> void:
	_shelter_commit_tick = -1.0
	_shelter_commit_day = 0
	_shelter_before_atp.clear()


func _shelter_callback_tag() -> String:
	return "open_files_party_rest:%s" % shelter_authority_key().sha256_text().substr(0, 12)


func _cancel_shelter_callback() -> void:
	var scheduler = _get_scheduler()
	if scheduler != null:
		scheduler.cancel_tag(_shelter_callback_tag())


func _arm_shelter_callback() -> void:
	var scheduler = _get_scheduler()
	if scheduler == null or _shelter_phase != "committing":
		return
	scheduler.cancel_tag(_shelter_callback_tag())
	scheduler.schedule_at(maxf(_get_scheduler_tick(), _shelter_commit_tick),
		_resume_committed_shelter_rest.bind(_shelter_commit_tick), _shelter_callback_tag())


func _resume_committed_shelter_rest(expected_tick: float) -> void:
	if _shelter_phase != "committing" \
			or not is_equal_approx(_shelter_commit_tick, expected_tick):
		return
	if _authored_party_rest_effect_matches(PARTY_IDS, _shelter_before_atp, _shelter_commit_day):
		_complete_shelter_rest(true)
		return
	var preflight := _preflight_authored_party_rest(
		Layout.SHELTER_POS, Layout.SHELTER_SIZE, PARTY_IDS
	)
	if not (preflight.get("blocked", []) as Array).is_empty():
		_shelter_phase = "ready"
		_clear_shelter_commit_context()
		_apply_shelter_presenter()
		_publish_shelter_authority()
		return
	var gs = _get_game_state()
	if gs != null and bool(gs.command_party_rest(PARTY_IDS)):
		_complete_shelter_rest(true)


func reset_preview_state() -> void:
	_cancel_shelter_callback()
	_ensure_runtime_ready()
	_reset_runtime_terminal(_purge_terminal)
	_reset_runtime_terminal(_access_terminal)
	if is_instance_valid(_purge_receiver) and _purge_receiver.has_method("reset"):
		_purge_receiver.call("reset", &"open_files_reset")
	if is_instance_valid(_access_receiver):
		_access_receiver.reset_access(&"open_files_reset")
	if is_instance_valid(_emp_circuit) and _emp_circuit.has_method("reset"):
		_emp_circuit.call("reset", &"open_files_reset")
	for producer_v in _drawer_stairs.values():
		var producer = producer_v
		if is_instance_valid(producer):
			producer.reset(&"open_files_reset")
	for interactable_v in _narrative_interactables.values():
		var interactable := interactable_v as Node
		if is_instance_valid(interactable):
			interactable.call("reset")
	for interactable_v in _inspection_interactables.values():
		var interactable := interactable_v as Node
		if is_instance_valid(interactable):
			interactable.call("reset")
	if is_instance_valid(_shelter_interactable):
		_shelter_interactable.reset()
	for spec_v in Layout.sapscrap_specs():
		var spec := spec_v as Dictionary
		var enemy_id := str(spec.get("id", ""))
		var patrol: Array[Vector3] = []
		for point_v in spec.get("patrol_points", []) as Array:
			patrol.append(point_v as Vector3)
		_reset_enemy(
			_sapscraps.get(enemy_id) as Enemy,
			spec.get("spawn_position", Vector3.ZERO),
			patrol
		)
	_restoring_shelter = true
	_shelter_phase = "ready"
	_anxiety_seen = false
	_clear_shelter_commit_context()
	_restoring_shelter = false
	_shelter_authority_initialized = true
	_shelter_authority_baseline = _baseline_shelter_authority()
	_apply_shelter_presenter()
	_update_inspection_presenters()
	_publish_shelter_authority()
	_set_preview_step("stacks_entry")


func _reset_runtime_terminal(terminal) -> void:
	if not is_instance_valid(terminal):
		return
	if terminal.has_method("reset_terminal"):
		terminal.call("reset_terminal", &"open_files_reset")
	elif terminal.has_method("reset"):
		terminal.call("reset")


func _reset_enemy(enemy: Enemy, post: Vector3, patrol: Array[Vector3]) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	enemy.configure_patrol(patrol)
	enemy.set_detection_targets(PARTY_IDS)
	enemy.re_post(post)


func on_game_state_snapshot_restored() -> void:
	super.on_game_state_snapshot_restored()
	_cancel_shelter_callback()
	_ensure_runtime_ready()
	var presenters: Array = []
	presenters.append_array(_drawer_stairs.values())
	presenters.append_array(_sapscraps.values())
	presenters.append_array([
		_purge_receiver, _purge_terminal, _access_receiver, _access_terminal, _emp_circuit,
	])
	for presenter in presenters:
		if is_instance_valid(presenter) \
				and presenter.has_method("on_game_state_snapshot_restored"):
			presenter.call("on_game_state_snapshot_restored")
	_shelter_authority_initialized = true
	if _shelter_authority_baseline.is_empty():
		_shelter_authority_baseline = _baseline_shelter_authority()
	var gs = _get_game_state()
	var raw: Variant = gs.get_world_state(shelter_authority_key(), null) \
		if gs != null and gs.has_method("get_world_state") else null
	if _valid_shelter_authority(raw):
		_restore_shelter_authority(raw as Dictionary)
	else:
		_restore_shelter_authority(_shelter_authority_baseline.duplicate(true))
		_publish_shelter_authority()
	_apply_shelter_presenter()
	_update_inspection_presenters()


func _exit_tree() -> void:
	_cancel_shelter_callback()
