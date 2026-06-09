extends "res://scripts/scene_chunks/scene_chunk.gd"

const FLOOR_CENTER := Vector3(58.0, -0.05, 0.0)
const FLOOR_SIZE := Vector3(120.0, 0.1, 54.0)
const WORLD_SLOT := {
	"slot_id": "act1_mother_flure",
	"act": 1,
	"region": "Mother Flure Chamber",
	"entry_shelter_id": "shelter_5",
	"exit_shelter_id": "shelter_6",
	"entry_anchor": "processing_stacks_exit",
	"exit_anchor": "residential_rings_approach",
	"canonical_party": ["aster", "peris", "endo"],
	"preview_party_preset": "full_party_full_health",
	"next_slot": "act1_residential_rings",
}

const BOARD_ORIGIN := Vector3(42.0, 0.0, -18.0)
const BOARD_CELL_SIZE := 6.0
const BOARD_ROWS := ["A", "B", "C", "D", "E", "F"]
const ROOT_CENTER_Y := 0.42
const ROOT_SWARM_Y_OFFSET := -0.32
const ROOT_GAP := 0.6
const ROOT_WIDTH := 4.2
const ROOT_SWARM_EXTRA_LENGTH := 2.2
const ROOT_SWARM_EXTRA_WIDTH := 0.7

const BASE_PORTAL_POS := Vector3(24.0, 0.45, 0.0)
const HIDE_SPOT_POS := Vector3(32.0, 0.0, 17.0)
const COLLAPSE_POS := Vector3(44.0, 0.0, 20.0)
const GEAR_POS := Vector3(35.0, 0.42, 8.4)
const INSTALL_SOCKET_POS := Vector3(86.0, 0.55, 0.0)
const MOTHER_POS := Vector3(100.0, 0.95, 0.0)
const REPAIR_POINT_ORDER := ["edge_relief", "load_regulator", "bloom_bypass"]
const CORRECT_REPAIR_ID := "load_regulator"
const REPAIR_POINT_DEFS := {
	"edge_relief": {
		"label": "EDGE RELIEF",
		"position": Vector3(81.4, 0.55, -4.0),
		"color": Color(0.56, 0.72, 0.88),
		"flare_root": "spine_gate",
		"flare_direction": 1,
		"flare_note": "The edge relief drinks pressure that was never the real problem. The spine gate drops back into the carry lane and the gear spits back out.",
	},
	"load_regulator": {
		"label": "LOAD REGULATOR",
		"position": INSTALL_SOCKET_POS,
		"color": Color(0.72, 0.9, 0.58),
	},
	"bloom_bypass": {
		"label": "BLOOM BYPASS",
		"position": Vector3(81.4, 0.55, 4.0),
		"color": Color(0.88, 0.72, 0.96),
		"flare_root": "tending_step",
		"flare_direction": 1,
		"flare_note": "The bloom bypass sheds signal into the south lane instead of taking weight off the mother. The tending step skews and the gear gets rejected.",
	},
}

const TERM_ALPHA_POS := Vector3(16.0, 0.85, -8.0)
const TERM_BETA_POS := Vector3(16.0, 0.85, 0.0)
const TERM_GAMMA_POS := Vector3(16.0, 0.85, 8.0)

const SERVICE_ALPHA_POS := Vector3(84.0, 0.25, -11.8)
const SERVICE_BETA_POS := Vector3(83.5, 0.25, 1.5)
const SERVICE_GAMMA_POS := Vector3(70.0, 0.25, 14.0)
const REMOTE_SPAWN_OFFSET := Vector3(-2.8, 0.0, 0.0)

const BODY_POSITIONS := {
	"body_a": Vector3(50.0, 0.18, 24.0),
	"body_b": Vector3(55.0, 0.18, 24.6),
	"body_c": Vector3(60.0, 0.18, 23.6),
	"body_d": Vector3(65.0, 0.18, 24.2),
}
const BODY_NAMES := {
	"body_a": "Brobla",
	"body_b": "Senchy",
	"body_c": "Worker 3",
	"body_d": "Worker 4",
}

const SPAWNS := {
	"aster": Vector3(8.0, 0.5, 0.0),
	"peris": Vector3(5.8, 0.5, 1.8),
	"endo": Vector3(3.6, 0.5, -1.8),
}

const TERMINAL_ORDER := ["term_alpha", "term_beta", "term_gamma"]
const TERMINAL_SERVICES := {
	"term_alpha": ["north_rail", "spine_gate", "survey_rib", "mother_veil"],
	"term_beta": ["socket_brace", "bloom_curtain", "crossbar"],
	"term_gamma": ["gear_latch", "carry_spur", "tending_step"],
}
const TERMINAL_SERVICE_POSITIONS := {
	"term_alpha": SERVICE_ALPHA_POS,
	"term_beta": SERVICE_BETA_POS,
	"term_gamma": SERVICE_GAMMA_POS,
}

const ROOT_ORDER := [
	"north_rail",
	"spine_gate",
	"survey_rib",
	"gear_latch",
	"mother_veil",
	"socket_brace",
	"bloom_curtain",
	"crossbar",
	"carry_spur",
	"tending_step",
]
const ROOT_DEFS := {
	"north_rail": {"label": "NORTH RAIL", "short": "A", "orientation": "horizontal", "length": 3, "fixed_line": 0, "anchor": 0, "min_anchor": 0, "max_anchor": 3, "terminal": "term_alpha", "color": Color(0.52, 0.34, 0.18), "swarm_color": Color(0.84, 0.58, 0.24)},
	"spine_gate": {"label": "SPINE GATE", "short": "B", "orientation": "vertical", "length": 2, "fixed_line": 3, "anchor": 1, "min_anchor": 0, "max_anchor": 3, "terminal": "term_alpha", "color": Color(0.48, 0.32, 0.18), "swarm_color": Color(0.86, 0.6, 0.28)},
	"survey_rib": {"label": "SURVEY RIB", "short": "C", "orientation": "horizontal", "length": 2, "fixed_line": 0, "anchor": 4, "min_anchor": 3, "max_anchor": 4, "terminal": "term_alpha", "color": Color(0.58, 0.38, 0.22), "swarm_color": Color(0.9, 0.64, 0.3)},
	"gear_latch": {"label": "GEAR LATCH", "short": "D", "orientation": "horizontal", "length": 2, "fixed_line": 1, "anchor": 0, "min_anchor": 0, "max_anchor": 2, "terminal": "term_gamma", "color": Color(0.44, 0.3, 0.18), "swarm_color": Color(0.82, 0.54, 0.24)},
	"mother_veil": {"label": "MOTHER VEIL", "short": "E", "orientation": "vertical", "length": 2, "fixed_line": 5, "anchor": 1, "min_anchor": 1, "max_anchor": 3, "terminal": "term_alpha", "color": Color(0.56, 0.36, 0.2), "swarm_color": Color(0.94, 0.68, 0.32)},
	"socket_brace": {"label": "SOCKET BRACE", "short": "F", "orientation": "vertical", "length": 2, "fixed_line": 1, "anchor": 2, "min_anchor": 2, "max_anchor": 4, "terminal": "term_beta", "color": Color(0.5, 0.34, 0.18), "swarm_color": Color(0.84, 0.6, 0.26)},
	"bloom_curtain": {"label": "BLOOM CURTAIN", "short": "G", "orientation": "vertical", "length": 2, "fixed_line": 4, "anchor": 2, "min_anchor": 2, "max_anchor": 4, "terminal": "term_beta", "color": Color(0.54, 0.36, 0.2), "swarm_color": Color(0.92, 0.66, 0.3)},
	"crossbar": {"label": "CROSSBAR", "short": "H", "orientation": "horizontal", "length": 3, "fixed_line": 3, "anchor": 2, "min_anchor": 1, "max_anchor": 3, "terminal": "term_beta", "color": Color(0.46, 0.3, 0.16), "swarm_color": Color(0.8, 0.54, 0.22)},
	"carry_spur": {"label": "CARRY SPUR", "short": "I", "orientation": "vertical", "length": 3, "fixed_line": 0, "anchor": 3, "min_anchor": 2, "max_anchor": 3, "terminal": "term_gamma", "color": Color(0.42, 0.28, 0.16), "swarm_color": Color(0.76, 0.52, 0.24)},
	"tending_step": {"label": "TENDING STEP", "short": "J", "orientation": "horizontal", "length": 2, "fixed_line": 4, "anchor": 3, "min_anchor": 2, "max_anchor": 4, "terminal": "term_gamma", "color": Color(0.6, 0.42, 0.22), "swarm_color": Color(0.94, 0.7, 0.36)},
}

const PORTAL_DURATION := 11.0
const ROOT_SLIDE_DURATION := 2.8
const ROOT_SWARM_LAG := 0.95
const ROOT_SWARM_DURATION := 1.5
const ROOT_HAZARD_DAMAGE := 8.0
const ROOT_HAZARD_INTERVAL := 0.85
const BODY_YIELD_PER_CORPSE := 2

var _roots: Dictionary = {}
var _active_terminal_id := ""
var _portal_open_until := 0.0
var _peris_remote_terminal := ""
var _collapse_cleared := false
var _gear_item_id := ""
var _gear_installed := false
var _installed_repair_id := ""
var _mother_tended := false
var _endo_cloak_until := 0.0
var _hazard_cooldowns: Dictionary = {}
var _log_entries_seen: Array[String] = []
var _body_remaining: Dictionary = {}
var _repair_attempts: Array[String] = []

var _terminal_materials: Dictionary = {}
var _terminal_labels: Dictionary = {}
var _portal_base_fill: MeshInstance3D
var _portal_base_material: StandardMaterial3D
var _portal_remote_fill: MeshInstance3D
var _portal_remote_material: StandardMaterial3D
var _portal_remote_label: Label3D
var _portal_entry_interactable
var _portal_return_interactable
var _gear_interactable
var _install_interactable
var _repair_interactables: Dictionary = {}
var _collapse_interactable
var _mother_interactable

var _body_materials: Dictionary = {}
var _body_labels: Dictionary = {}
var _mother_bloom_materials: Array[StandardMaterial3D] = []
var _repair_point_materials: Dictionary = {}
var _repair_point_labels: Dictionary = {}

var _aster_overlay_root: Node3D
var _peris_overlay_root: Node3D
var _endo_overlay_root: Node3D
var _peris_overlay_labels: Dictionary = {}
var _endo_overlay_materials: Dictionary = {}

func _build_chunk() -> void:
	_build_chamber_shell()
	_build_terminal_bank()
	_build_root_board()
	_build_service_alcoves()
	_build_portal_bank()
	_build_gear_station()
	_build_install_socket()
	_build_mother()
	_build_collapse_offshoot()
	_build_hide_spot()
	_build_overlay_roots()
	reset_preview_state()

func _process(delta: float) -> void:
	_update_runtime(delta)

func headless_process(delta: float) -> void:
	_update_runtime(delta)

func get_scene_title() -> String:
	return "Mother Flure"

func get_scene_help() -> String:
	return "Pilot the full Mother chamber with the in-game preview stack: the board still matters, but the solve is diagnosis now. Aster reads the old logistics, Peris reads the mother's stress, and Endo has to carry the gear to the repair point that actually matches the fault."

func get_default_character() -> String:
	return "aster"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors.merge({
		"portal_bank": BASE_PORTAL_POS,
		"gear": GEAR_POS,
		"install_socket": INSTALL_SOCKET_POS,
		"edge_relief": _repair_point_position("edge_relief"),
		"load_regulator": _repair_point_position("load_regulator"),
		"bloom_bypass": _repair_point_position("bloom_bypass"),
		"mother": MOTHER_POS,
		"collapse": COLLAPSE_POS,
		"hide_spot": HIDE_SPOT_POS,
		"service_alpha": SERVICE_ALPHA_POS,
		"service_beta": SERVICE_BETA_POS,
		"service_gamma": SERVICE_GAMMA_POS,
	}, true)
	return anchors

func get_world_slot() -> Dictionary:
	return WORLD_SLOT.duplicate(true)

func get_preview_time_state() -> Dictionary:
	return {
		"day": 5,
		"time": 0.61,
		"routing_mode": "safe",
		"note_default": "This preview drops the full Mother chamber into the regular game UI with the party topped off. The board is only the first layer now: read the old logistics, diagnose the mother's actual fault, then decide which repair point Endo should commit the carry to.",
	}

func get_preview_abilities() -> Array:
	# Display names + descriptions + tuning live in data/abilities/en/abilities.xlsx (per-context rows).
	return AbilityData.for_context("mother_ferrolure")
func get_preview_state() -> Dictionary:
	var current_tick := _get_scheduler_tick()
	var roots := {}
	for root_id in ROOT_ORDER:
		if not _roots.has(root_id):
			continue
		var root: Dictionary = _roots[root_id]
		var cells: Array[String] = []
		for cell in _root_cells(root):
			cells.append(_cell_name(cell))
		roots[root_id] = {
			"anchor": int(root.get("anchor", 0)),
			"cells": cells,
			"moving": current_tick < float(root.get("swarm_end", 0.0)),
			"terminal": str(root.get("terminal", "")),
			"orientation": str(root.get("orientation", "")),
		}
	return {
		"active_terminal": _active_terminal_id,
		"portal_open": _is_portal_open(current_tick),
		"portal_time_remaining": maxf(0.0, _portal_open_until - current_tick),
		"peris_remote_terminal": _peris_remote_terminal,
		"collapse_cleared": _collapse_cleared,
		"gear_installed": _gear_installed,
		"installed_repair": _installed_repair_id,
		"gear_pocket_open": _is_gear_pocket_open(),
		"socket_lane_open": _is_socket_lane_open(),
		"mother_lane_clear": _is_mother_lane_clear(),
		"mother_tended": _mother_tended,
		"repair_attempts": _repair_attempts.duplicate(),
		"repair_target": CORRECT_REPAIR_ID,
		"diagnosis": _diagnosis_summary(),
		"endo_cloak_remaining": maxf(0.0, _endo_cloak_until - current_tick),
		"log_entries_seen": _log_entries_seen.duplicate(),
		"roots": roots,
		"bodies": _body_remaining.duplicate(true),
		"gear_item": _gear_item_id,
	}

func reset_preview_state() -> void:
	_active_terminal_id = ""
	_portal_open_until = 0.0
	_peris_remote_terminal = ""
	_collapse_cleared = false
	_gear_installed = false
	_installed_repair_id = ""
	_mother_tended = false
	_endo_cloak_until = 0.0
	_hazard_cooldowns.clear()
	_log_entries_seen.clear()
	_repair_attempts.clear()
	_body_remaining = {}
	for body_id in BODY_POSITIONS.keys():
		_body_remaining[body_id] = BODY_YIELD_PER_CORPSE
	for root_id in ROOT_ORDER:
		if not _roots.has(root_id):
			continue
		var root: Dictionary = _roots[root_id]
		var initial_anchor := int(root.get("initial_anchor", 0))
		root["anchor"] = initial_anchor
		root["anim_start"] = 0.0
		root["anim_end"] = 0.0
		root["swarm_start"] = 0.0
		root["swarm_end"] = 0.0
		var root_pos := _root_world_center(root, initial_anchor)
		var swarm_pos := root_pos + Vector3(0.0, ROOT_SWARM_Y_OFFSET, 0.0)
		root["anim_from_pos"] = root_pos
		root["anim_to_pos"] = root_pos
		root["swarm_from_pos"] = swarm_pos
		root["swarm_to_pos"] = swarm_pos
		_apply_root_pose(root_id, root_pos, swarm_pos)
	_spawn_gear(GEAR_POS)
	_update_terminal_visuals()
	_update_portal_visuals()
	_update_body_visuals()
	_update_mother_visuals()
	_update_overlay_label_states()

func handle_preview_ability(ability_id: String, _ability: Dictionary = {}) -> Dictionary:
	var current_tick := _get_scheduler_tick()
	match ability_id:
		"aster_focus":
			if _is_portal_open(current_tick):
				_portal_open_until = maxf(_portal_open_until, current_tick + 4.0)
				_update_portal_visuals()
				return {"note": "Aster steadies the active portal bank for another four seconds."}
			return {"note": "TRACE is strongest after a portal bank is already live."}
		"peris_tune":
			return {"characters": {"peris": {"sta_delta": 10.0}}}
		"endo_patch":
			_endo_cloak_until = maxf(_endo_cloak_until, current_tick + 24.0)
			return {"characters": {"endo": {"sta_delta": 6.0}}}
		_:
			return {}

func update_preview_overlay_states(overlay_states: Dictionary, current_tick: float, _delta: float) -> void:
	if _aster_overlay_root != null:
		_aster_overlay_root.visible = bool(overlay_states.get("aster", false))
	if _peris_overlay_root != null:
		_peris_overlay_root.visible = bool(overlay_states.get("peris", false))
	if _endo_overlay_root != null:
		_endo_overlay_root.visible = bool(overlay_states.get("endo", false))
	_update_overlay_label_states()
	_update_portal_overlay(current_tick)

func get_preview_overlay_status(overlay_id: String, current_tick: float) -> Array:
	match overlay_id:
		"aster":
			return [
				"Portal bank: %s" % (_portal_label(_active_terminal_id) if _is_portal_open(current_tick) else "idle"),
				"Live service braid: %s  |  Ghost load: %s" % [_active_service_overlay_label(), _aster_load_read()],
				"Shows terminal IDs, route ties, and the old Unit NV maintenance ghost over the chamber.",
			]
		"peris":
			return [
				"Mother stress: %s  |  Board pulse: %s" % [_mother_stress_label(), _peris_board_read()],
				"Care read: %s" % _peris_fault_read(),
				"Memory blur: %s  |  Caretaker traces layered" % _peris_memory_blur_read(),
				"Dormant buds, flora memory, and caretaker echoes stack together instead of forcing portrait swaps.",
			]
		"endo":
			return [
				"Food sources: %d units left  |  Gear: %s" % [_body_units_remaining(), "mounted" if _gear_installed else "loose"],
				"Carry lane: %s  |  Repair target: %s" % [("open" if _is_socket_lane_open() else "closed"), _endo_repair_read()],
				"Cloak: %.1fs" % maxf(0.0, _endo_cloak_until - current_tick),
			]
		_:
			return []

func activate_terminal(terminal_id: String) -> bool:
	if not TERMINAL_SERVICES.has(terminal_id):
		return false
	if _peris_remote_terminal != "" and _peris_remote_terminal != terminal_id:
		_show_message("Peris is still inside another service bay.", 1.2)
		return false
	_active_terminal_id = terminal_id
	_portal_open_until = _get_scheduler_tick() + PORTAL_DURATION
	_update_terminal_visuals()
	_update_portal_visuals()
	_surface_terminal_log(terminal_id)
	_set_preview_step("mother_%s_online" % terminal_id)
	_show_note("%s opens. Peris can cross while the bank holds." % _portal_label(terminal_id), 3.2)
	return true

func use_portal() -> bool:
	if _peris_remote_terminal == "":
		if not _is_portal_open(_get_scheduler_tick()):
			_show_message("No portal bank is stable right now.", 1.2)
			return false
		_peris_remote_terminal = _active_terminal_id
		_set_character_position("peris", _terminal_service_spawn(_active_terminal_id))
		_set_preview_step("mother_%s_remote" % _active_terminal_id)
		_show_message("Peris crosses into %s." % _terminal_service_label(_active_terminal_id), 1.3)
		_update_portal_visuals()
		return true
	if not _is_portal_open(_get_scheduler_tick()) or _active_terminal_id != _peris_remote_terminal:
		_show_message("Aster needs the matching bank live to bring Peris back.", 1.3)
		return false
	_peris_remote_terminal = ""
	_set_character_position("peris", BASE_PORTAL_POS + Vector3(2.6, 0.0, 0.0))
	_show_message("Peris returns through %s." % _portal_label(_active_terminal_id), 1.2)
	_update_portal_visuals()
	return true

func activate_fragment(root_id: String) -> bool:
	var direction := _default_move_direction(root_id)
	if direction == 0:
		_show_message("That root has no clean drift from here.", 1.2)
		return false
	return activate_fragment_move(root_id, direction)

func activate_fragment_move(root_id: String, direction: int) -> bool:
	if not _roots.has(root_id):
		return false
	if _get_active_character() != "peris":
		_say("These buds only answer to Peris.", "ASTER")
		return false
	var root: Dictionary = _roots[root_id]
	var terminal_id := str(root.get("terminal", ""))
	if _peris_remote_terminal != terminal_id:
		_show_message("Peris needs the matching service bay first.", 1.2)
		return false
	var current_tick := _get_scheduler_tick()
	if current_tick < float(root.get("swarm_end", 0.0)):
		_show_message("%s is still settling." % _fragment_label(root_id), 1.2)
		return false
	var target_anchor := int(root.get("anchor", 0)) + clampi(direction, -1, 1)
	if target_anchor < int(root.get("min_anchor", 0)) or target_anchor > int(root.get("max_anchor", 0)):
		_show_message("That bud on %s doesn't answer anymore." % _fragment_label(root_id), 1.3)
		return false
	var blocker := _blocking_root_for(root_id, target_anchor)
	if blocker != "":
		_show_message("%s is still braced somewhere deeper in the board." % _fragment_label(root_id), 1.4)
		return false
	var from_anchor := int(root.get("anchor", 0))
	root["anchor"] = target_anchor
	root["anim_start"] = current_tick
	root["anim_end"] = current_tick + ROOT_SLIDE_DURATION
	root["swarm_start"] = float(root.get("anim_end", current_tick)) + ROOT_SWARM_LAG
	root["swarm_end"] = float(root.get("swarm_start", current_tick)) + ROOT_SWARM_DURATION
	root["anim_from_pos"] = _root_node(root).position
	root["anim_to_pos"] = _root_world_center(root, target_anchor)
	root["swarm_from_pos"] = _root_swarm_node(root).position
	root["swarm_to_pos"] = Vector3(root.get("anim_to_pos", Vector3.ZERO)) + Vector3(0.0, ROOT_SWARM_Y_OFFSET, 0.0)
	_set_preview_step("mother_%s_%s_%d" % [root_id, "forward" if target_anchor > from_anchor else "back", target_anchor])
	_show_note("Peris wakes one of %s's dormant buds. The root drifts and the Techo mat follows." % _fragment_label(root_id), 3.6)
	_update_overlay_label_states()
	return true

func clear_collapse() -> bool:
	var active_char := _get_active_character()
	if active_char != "endo":
		match active_char:
			"aster":
				_say("They might have called me a beast, but I'm still not the type for this.", "ASTER")
			"peris":
				_say("It's too heavy. I can't move it.", "PERIS")
		return false
	if _collapse_cleared:
		_show_message("The offshoot is already open.", 1.0)
		return false
	_collapse_cleared = true
	_set_preview_step("mother_collapse_open")
	_show_note("Endo shifts the debris. The preserved workers are accessible now.", 3.4)
	_update_body_visuals()
	return true

func harvest_body(body_id: String) -> bool:
	if not _collapse_cleared:
		_show_message("The debris still blocks the bodies.", 1.2)
		return false
	if not BODY_POSITIONS.has(body_id):
		return false
	if _get_active_character() != "endo":
		_say("Only Endo can actually draw anything usable out of them.", "PERIS")
		return false
	if int(_body_remaining.get(body_id, 0)) <= 0:
		_show_message("%s is spent." % BODY_NAMES.get(body_id, body_id), 1.1)
		return false
	if not _has_free_hand_slots("endo", 1):
		_show_message("Endo needs a free hand before he can absorb more starch.", 1.3)
		return false
	var item_id := _spawn_item("lysate", BODY_POSITIONS[body_id], {
		"display_name": "Lysate",
		"display_names_by_character": {"aster": "Lysate", "peris": "Lysate", "endo": "Starch"},
		"visual_color": Color(0.78, 0.66, 0.38),
		"atp_restore": 3.0,
	})
	if not _pick_up_item("endo", item_id):
		_remove_item(item_id)
		return false
	_body_remaining[body_id] = maxi(int(_body_remaining.get(body_id, 0)) - 1, 0)
	_update_body_visuals()
	_set_preview_step("mother_%s_harvested" % body_id)
	_show_note("Endo pulls another hand-unit of starch from %s." % BODY_NAMES.get(body_id, body_id), 2.8)
	return true

func pick_up_gear() -> bool:
	if _gear_installed:
		_show_message("The gear is already mounted.", 1.0)
		return false
	if _gear_item_id == "":
		return false
	if _get_active_character() != "endo":
		_say("It wants both hands. That's Endo.", "PERIS")
		return false
	if not _is_gear_pocket_open():
		_show_message("The west side still feels pinned shut.", 1.3)
		return false
	if not _pick_up_item("endo", _gear_item_id):
		_show_message("Endo needs both hands clear to carry the gear.", 1.3)
		return false
	_set_preview_step("mother_gear_carried")
	_show_note("Endo lifts the mother gear with both hands.", 2.8)
	_update_overlay_label_states()
	_update_gear_interactable_position()
	return true

func install_gear() -> bool:
	return install_gear_at(CORRECT_REPAIR_ID)

func install_gear_at(repair_id: String) -> bool:
	if not REPAIR_POINT_DEFS.has(repair_id):
		return false
	if _gear_installed:
		return false
	if _get_active_character() != "endo":
		_say("The mount is mechanical. Let Endo set it.", "ASTER")
		return false
	if not _is_socket_lane_open():
		_show_message("The carry route still reads too tight.", 1.2)
		return false
	if not _endo_holds_gear():
		_show_message("Endo needs to be carrying the gear first.", 1.2)
		return false
	if not _repair_attempts.has(repair_id):
		_repair_attempts.append(repair_id)
	if repair_id != CORRECT_REPAIR_ID:
		_reject_wrong_repair(repair_id)
		return true
	_remove_item(_gear_item_id)
	_gear_item_id = ""
	_gear_installed = true
	_installed_repair_id = repair_id
	_set_preview_step("mother_gear_installed")
	_show_note("The load regulator takes the gear cleanly. The mother's stress profile loosens instead of flaring and the east side begins to unravel.", 3.8)
	_update_mother_visuals()
	_update_overlay_label_states()
	_update_gear_interactable_position()
	return true

func tend_mother() -> bool:
	if _get_active_character() != "peris":
		_say("She answers to Peris, not to us.", "ASTER")
		return false
	if not _gear_installed:
		_show_message("The mechanism still needs the gear.", 1.2)
		return false
	if _installed_repair_id != CORRECT_REPAIR_ID:
		_show_message("Peris can feel the load still being routed wrong.", 1.2)
		return false
	if not _is_mother_lane_clear():
		_show_message("The mother still reads walled in.", 1.2)
		return false
	if _mother_tended:
		_show_message("The mother is already awake.", 1.0)
		return false
	_mother_tended = true
	_set_preview_step("mother_bloomed")
	_clear_dialogue()
	_say("You're all right. You just needed the load to move.", "PERIS")
	_say("The chamber's opening toward the Rings. That's our handoff.", "ASTER")
	_show_note("Mother Ferrolure stabilized. This preview now runs the full board, carry, and consume loop together.", 4.0)
	_update_mother_visuals()
	_update_overlay_label_states()
	return true

func _update_runtime(_delta: float) -> void:
	var current_tick := _get_scheduler_tick()
	_update_portal_timeout(current_tick)
	_update_root_animation(current_tick)
	_update_lane_hazards(current_tick)
	_update_terminal_pulse(current_tick)
	_update_overlay_label_states()
	_update_gear_interactable_position()

func _update_portal_timeout(current_tick: float) -> void:
	if _active_terminal_id == "" or _portal_open_until > current_tick:
		return
	_active_terminal_id = ""
	_portal_open_until = 0.0
	if _peris_remote_terminal != "":
		_show_note("The remote bank closes. Aster can reopen the same terminal to bring Peris back.", 3.1)
	else:
		_show_message("The portal bank winds down.", 1.1)
	_update_terminal_visuals()
	_update_portal_visuals()

func _update_root_animation(current_tick: float) -> void:
	for root_id in ROOT_ORDER:
		if not _roots.has(root_id):
			continue
		var root: Dictionary = _roots[root_id]
		var root_node := _root_node(root)
		var swarm_node := _root_swarm_node(root)
		var anim_start := float(root.get("anim_start", 0.0))
		var anim_end := float(root.get("anim_end", 0.0))
		if anim_end > anim_start and current_tick < anim_end:
			var t := clampf((current_tick - anim_start) / maxf(anim_end - anim_start, 0.001), 0.0, 1.0)
			root_node.position = Vector3(root.get("anim_from_pos", root_node.position)).lerp(Vector3(root.get("anim_to_pos", root_node.position)), t)
		elif anim_end > 0.0:
			root_node.position = Vector3(root.get("anim_to_pos", root_node.position))
		var swarm_start := float(root.get("swarm_start", 0.0))
		var swarm_end := float(root.get("swarm_end", 0.0))
		if swarm_end > swarm_start and current_tick < swarm_start:
			swarm_node.position = Vector3(root.get("swarm_from_pos", swarm_node.position))
		elif swarm_end > swarm_start and current_tick < swarm_end:
			var swarm_t := clampf((current_tick - swarm_start) / maxf(swarm_end - swarm_start, 0.001), 0.0, 1.0)
			swarm_node.position = Vector3(root.get("swarm_from_pos", swarm_node.position)).lerp(Vector3(root.get("swarm_to_pos", swarm_node.position)), swarm_t)
		elif swarm_end > 0.0:
			swarm_node.position = Vector3(root.get("swarm_to_pos", swarm_node.position))
		_update_root_world_label(root)

func _update_lane_hazards(current_tick: float) -> void:
	if _mother_tended:
		return
	for char_id in ["aster", "peris", "endo"]:
		if char_id == "endo" and current_tick < _endo_cloak_until:
			continue
		if current_tick < float(_hazard_cooldowns.get(char_id, 0.0)):
			continue
		if not _character_in_any_hazard(_get_character_position(char_id)):
			continue
		_hazard_cooldowns[char_id] = current_tick + ROOT_HAZARD_INTERVAL
		_adjust_character_stat(char_id, "hp", -ROOT_HAZARD_DAMAGE)
		_show_message("%s gets clipped by the Techo mat." % _display_name(char_id), 1.1)

func _update_terminal_pulse(current_tick: float) -> void:
	for terminal_id in _terminal_materials.keys():
		var material: StandardMaterial3D = _terminal_materials[terminal_id]
		if material == null:
			continue
		var active: bool = terminal_id == _active_terminal_id and _is_portal_open(current_tick)
		material.emission_energy_multiplier = 0.65 + 0.2 * (0.5 + 0.5 * sin(current_tick * 6.0)) if active else 0.26

func _surface_terminal_log(terminal_id: String) -> void:
	if terminal_id in _log_entries_seen:
		return
	_log_entries_seen.append(terminal_id)
	match terminal_id:
		"term_alpha":
			_clear_dialogue()
			_say("Shift log surfaced: substrate panels, scanner modules, feed-tube nodes. Unit NV.", "ENGRAM", "data")
			_say("The old freight signatures all bottleneck through the center spindle.", "ASTER")
		"term_beta":
			_clear_dialogue()
			_say("Removal authorization withdrawn. Chr-a rerouted the supply chain instead of cutting through the mother.", "ENGRAM", "data")
			_say("She's hurting at the core. The edge lanes are just carrying the noise.", "PERIS")
		"term_gamma":
			_clear_dialogue()
			_say("Incident log: 12-F collapsed under heavy load. Four workers died and were left sealed in the wing.", "ENGRAM", "data")
			_say("Carry still works if we take the center mount. Anything else will just kick back.", "ENDO")

func _build_chamber_shell() -> void:
	_add_floor(self, FLOOR_CENTER, FLOOR_SIZE, Color(0.07, 0.065, 0.06))
	_add_box(self, Vector3(58.0, 2.1, -27.1), Vector3(120.0, 4.2, 0.3), Color(0.12, 0.11, 0.1))
	_add_box(self, Vector3(58.0, 2.1, 27.1), Vector3(120.0, 4.2, 0.3), Color(0.12, 0.11, 0.1))
	_add_box(self, Vector3(-0.1, 2.1, 0.0), Vector3(0.3, 4.2, 54.0), Color(0.12, 0.11, 0.1))
	_add_box(self, Vector3(116.1, 2.1, 0.0), Vector3(0.3, 4.2, 54.0), Color(0.12, 0.11, 0.1))
	for x_pos in [10.0, 26.0, 42.0, 58.0, 74.0, 90.0, 106.0]:
		_add_light(self, Vector3(x_pos, 4.1, 0.0), Color(0.58, 0.54, 0.48), 1.45, 14.0)
	var board_center := Vector3(60.0, 0.01, 0.0)
	_add_box(self, board_center, Vector3(36.0, 0.05, 36.0), Color(0.14, 0.1, 0.08), Color(0.28, 0.2, 0.12), 0.14)
	_add_box(self, board_center, Vector3(36.6, 0.18, 0.28), Color(0.3, 0.22, 0.14))
	_add_box(self, board_center, Vector3(0.28, 0.18, 36.6), Color(0.3, 0.22, 0.14))
	for col in range(7):
		var x_pos := BOARD_ORIGIN.x + float(col) * BOARD_CELL_SIZE
		_add_box(self, Vector3(x_pos, 0.12, 0.0), Vector3(0.14, 0.18, 36.0), Color(0.22, 0.18, 0.12))
	for row in range(7):
		var z_pos := BOARD_ORIGIN.z + float(row) * BOARD_CELL_SIZE
		_add_box(self, Vector3(60.0, 0.12, z_pos), Vector3(36.0, 0.18, 0.14), Color(0.22, 0.18, 0.12))
	_add_label(self, "PORTAL BANK 12", TERM_BETA_POS + Vector3(2.2, 2.65, 0.0), Color(0.8, 0.88, 0.96))
	_add_label(self, "COLLAPSED 12-F", COLLAPSE_POS + Vector3(8.0, 2.5, 0.0), Color(0.82, 0.72, 0.6))
	_add_label(self, "MOTHER FERROLURE", MOTHER_POS + Vector3(-1.0, 3.2, 0.0), Color(0.94, 0.82, 0.58))
	_add_label(self, "LOT CLOT CHAMBER", Vector3(60.0, 2.8, -22.8), Color(0.72, 0.62, 0.46))

func _build_terminal_bank() -> void:
	_build_terminal("term_alpha", TERM_ALPHA_POS, "TERM-12A", "PORTAL-12A")
	_build_terminal("term_beta", TERM_BETA_POS, "TERM-12B", "PORTAL-12B")
	_build_terminal("term_gamma", TERM_GAMMA_POS, "TERM-12C", "PORTAL-12C")

func _build_root_board() -> void:
	for root_id in ROOT_ORDER:
		_build_root(root_id)

func _build_service_alcoves() -> void:
	for terminal_id in TERMINAL_ORDER:
		_build_service_alcove(terminal_id)

func _build_service_alcove(terminal_id: String) -> void:
	var base_pos: Vector3 = TERMINAL_SERVICE_POSITIONS[terminal_id]
	var service_roots: Array = TERMINAL_SERVICES[terminal_id]
	var platform_depth := maxf(9.0, float(service_roots.size()) * 3.6 + 2.0)
	_add_box(self, base_pos + Vector3(0.0, -0.06, 0.0), Vector3(8.4, 0.14, platform_depth), Color(0.11, 0.1, 0.09))
	_add_box(self, base_pos + Vector3(-3.8, 1.1, 0.0), Vector3(0.24, 2.2, platform_depth), Color(0.16, 0.14, 0.12))
	_add_box(self, base_pos + Vector3(0.0, 1.1, -platform_depth * 0.5), Vector3(8.4, 2.2, 0.24), Color(0.16, 0.14, 0.12))
	_add_label(self, _terminal_service_label(terminal_id).to_upper(), base_pos + Vector3(0.0, 2.35, 0.0), Color(0.84, 0.76, 0.62))
	for index in range(service_roots.size()):
		var root_id := str(service_roots[index])
		var row_pos := _service_row_position(terminal_id, index, service_roots.size())
		_add_box(self, row_pos + Vector3(0.0, 0.16, 0.0), Vector3(5.8, 0.08, 1.7), Color(0.18, 0.14, 0.1), Color(0.34, 0.22, 0.14), 0.08)
		_add_label(self, str(ROOT_DEFS[root_id].get("label", root_id)), row_pos + Vector3(0.0, 1.45, 0.52), Color(0.9, 0.78, 0.56))
		for direction in [-1, 1]:
			var bud_pos := row_pos + Vector3(-1.55 if direction < 0 else 1.55, 0.14, -0.48)
			_add_box(self, bud_pos + Vector3(0.0, 0.18, 0.0), Vector3(0.54, 0.36, 0.54), Color(0.24, 0.18, 0.12), Color(0.72, 0.54, 0.26), 0.22)
			_add_label(self, _bud_label(direction), bud_pos + Vector3(0.0, 0.86, 0.0), Color(0.96, 0.8, 0.52))
			var interactable = _add_inspection_interactable(
				self,
				"%s_%s_%s" % [terminal_id.capitalize(), root_id.capitalize(), "neg" if direction < 0 else "pos"],
				"%s / %s" % [ROOT_DEFS[root_id].get("label", root_id), _bud_label(direction)],
				bud_pos,
				"SHIFT",
				"peris"
			)
			interactable.interacted.connect(Callable(self, "activate_fragment_move").bind(root_id, direction))

func _build_portal_bank() -> void:
	_add_box(self, BASE_PORTAL_POS + Vector3(-0.72, 1.2, 0.0), Vector3(0.18, 2.2, 0.18), Color(0.22, 0.2, 0.18))
	_add_box(self, BASE_PORTAL_POS + Vector3(0.72, 1.2, 0.0), Vector3(0.18, 2.2, 0.18), Color(0.22, 0.2, 0.18))
	_add_box(self, BASE_PORTAL_POS + Vector3(0.0, 2.22, 0.0), Vector3(1.56, 0.18, 0.18), Color(0.22, 0.2, 0.18))
	_portal_base_fill = _add_box(self, BASE_PORTAL_POS + Vector3(0.0, 1.08, 0.0), Vector3(1.2, 1.84, 0.08), Color(0.18, 0.16, 0.14), Color(0.76, 0.56, 0.28), 0.2)
	_portal_base_material = _portal_base_fill.material_override
	_portal_entry_interactable = _add_inspection_interactable(self, "MotherPortalEntry", "Portal Entry", BASE_PORTAL_POS + Vector3(0.0, 0.2, 0.0), "CROSS", "peris")
	_portal_entry_interactable.interacted.connect(func() -> void: use_portal())
	_portal_remote_fill = _add_box(self, Vector3(2000.0, 1.08, 2000.0), Vector3(1.2, 1.84, 0.08), Color(0.18, 0.16, 0.14), Color(0.92, 0.66, 0.32), 0.2)
	_portal_remote_material = _portal_remote_fill.material_override
	_portal_remote_label = _add_label(self, "RETURN", Vector3(2000.0, 3.0, 2000.0), Color(0.94, 0.76, 0.46))
	_portal_return_interactable = _add_inspection_interactable(self, "MotherPortalReturn", "Portal Return", Vector3(2000.0, 0.2, 2000.0), "RETURN", "peris")
	_portal_return_interactable.interacted.connect(func() -> void: use_portal())

func _build_gear_station() -> void:
	_add_box(self, GEAR_POS + Vector3(0.0, -0.1, 0.0), Vector3(3.8, 0.28, 3.4), Color(0.12, 0.1, 0.08))
	_add_box(self, GEAR_POS + Vector3(0.0, 0.38, 0.0), Vector3(2.1, 0.26, 2.1), Color(0.18, 0.14, 0.1), Color(0.46, 0.3, 0.16), 0.22)
	_add_label(self, "MOTHER GEAR", GEAR_POS + Vector3(0.0, 2.2, 0.0), Color(0.88, 0.76, 0.58))
	_gear_interactable = _add_inspection_interactable(self, "MotherGearInteractable", "Mother Gear", GEAR_POS + Vector3(0.0, 0.25, 0.0), "LIFT")
	_gear_interactable.interacted.connect(func() -> void: pick_up_gear())

func _build_install_socket() -> void:
	_add_box(self, INSTALL_SOCKET_POS + Vector3(-2.3, -0.06, 0.0), Vector3(9.6, 0.18, 10.2), Color(0.12, 0.1, 0.08))
	for repair_id in REPAIR_POINT_ORDER:
		var repair_pos := _repair_point_position(repair_id)
		var repair_color: Color = REPAIR_POINT_DEFS[repair_id].get("color", Color(0.72, 0.82, 0.94))
		_add_box(self, repair_pos + Vector3(0.0, 0.48, 0.0), Vector3(1.9, 0.7, 1.9), Color(0.16, 0.16, 0.18))
		var mount := _add_box(self, repair_pos + Vector3(0.0, 0.78, 0.0), Vector3(1.14, 0.24, 1.14), Color(0.18, 0.2, 0.24), repair_color, 0.22)
		_repair_point_materials[repair_id] = mount.material_override
		_repair_point_labels[repair_id] = _add_label(self, str(REPAIR_POINT_DEFS[repair_id].get("label", repair_id)).to_upper(), repair_pos + Vector3(0.0, 2.1, 0.0), repair_color.lightened(0.15))
		var interactable := _add_inspection_interactable(self, "%sRepairInteractable" % repair_id.capitalize(), str(REPAIR_POINT_DEFS[repair_id].get("label", repair_id)), repair_pos + Vector3(0.0, 0.2, 0.0), "MOUNT")
		interactable.interacted.connect(Callable(self, "install_gear_at").bind(repair_id))
		_repair_interactables[repair_id] = interactable
		if repair_id == CORRECT_REPAIR_ID:
			_install_interactable = interactable

func _build_mother() -> void:
	for i in range(3):
		_add_box(self, MOTHER_POS + Vector3(-1.0 + float(i), 0.45, 0.0), Vector3(1.1, 0.9, 2.2), Color(0.24, 0.18, 0.12))
	for bloom_offset in [Vector3(-1.4, 1.8, 0.8), Vector3(-0.2, 2.15, -0.5), Vector3(1.0, 1.9, 0.4), Vector3(0.2, 2.5, 0.0)]:
		var bloom := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.42
		mesh.height = 0.84
		bloom.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.56, 0.46, 0.22)
		material.emission_enabled = true
		material.emission = Color(0.82, 0.58, 0.24)
		material.emission_energy_multiplier = 0.12
		bloom.material_override = material
		bloom.position = MOTHER_POS + bloom_offset
		add_child(bloom)
		_mother_bloom_materials.append(material)
	_mother_interactable = _add_inspection_interactable(self, "MotherTendInteractable", "Mother Ferrolure", MOTHER_POS + Vector3(-2.2, 0.4, 0.0), "TEND")
	_mother_interactable.interacted.connect(func() -> void: tend_mother())

func _build_collapse_offshoot() -> void:
	_add_box(self, Vector3(50.0, 0.01, 18.0), Vector3(28.0, 0.04, 8.0), Color(0.1, 0.085, 0.08))
	_add_box(self, Vector3(50.0, 1.3, 22.1), Vector3(28.0, 2.6, 0.3), Color(0.14, 0.12, 0.1))
	_add_box(self, Vector3(50.0, 1.3, 13.9), Vector3(28.0, 2.6, 0.3), Color(0.14, 0.12, 0.1))
	for debris_offset in [Vector3(-1.2, 0.55, -0.4), Vector3(0.2, 0.48, 0.2), Vector3(1.4, 0.6, -0.15)]:
		_add_box(self, COLLAPSE_POS + debris_offset, Vector3(1.4, 1.0, 1.0), Color(0.28, 0.24, 0.18))
	_collapse_interactable = _add_inspection_interactable(self, "MotherCollapseInteractable", "Collapsed Debris", COLLAPSE_POS + Vector3(0.0, 0.2, 0.0), "SHIFT")
	_collapse_interactable.interacted.connect(func() -> void: clear_collapse())
	for body_id in BODY_POSITIONS.keys():
		var pos: Vector3 = BODY_POSITIONS[body_id]
		var body := _add_box(self, pos, Vector3(2.2, 0.3, 0.86), Color(0.34, 0.28, 0.22))
		_body_materials[body_id] = body.material_override
		_body_labels[body_id] = _add_label(self, BODY_NAMES.get(body_id, body_id).to_upper(), pos + Vector3(0.0, 1.25, 0.0), Color(0.8, 0.72, 0.64))
		var interactable = _add_inspection_interactable(self, "%sInteractable" % body_id.capitalize(), BODY_NAMES.get(body_id, body_id), pos + Vector3(0.0, 0.22, 0.0), "ABSORB")
		interactable.interacted.connect(Callable(self, "harvest_body").bind(body_id))

func _build_hide_spot() -> void:
	_add_box(self, HIDE_SPOT_POS + Vector3(0.0, -0.02, 0.0), Vector3(7.4, 0.08, 6.0), Color(0.08, 0.1, 0.09))
	_add_box(self, HIDE_SPOT_POS + Vector3(-3.7, 1.2, 0.0), Vector3(0.2, 2.4, 6.0), Color(0.14, 0.16, 0.14))
	_add_box(self, HIDE_SPOT_POS + Vector3(0.0, 1.2, -3.0), Vector3(7.4, 2.4, 0.2), Color(0.14, 0.16, 0.14))
	_add_light(self, HIDE_SPOT_POS + Vector3(0.0, 1.8, 0.0), Color(0.7, 0.54, 0.32), 1.25, 8.0)
	_add_label(self, "CARETAKER ALCOVE", HIDE_SPOT_POS + Vector3(0.0, 2.3, 0.0), Color(0.88, 0.76, 0.62))

func _build_overlay_roots() -> void:
	_aster_overlay_root = Node3D.new()
	add_child(_aster_overlay_root)
	for terminal_id in TERMINAL_ORDER:
		var terminal_pos: Vector3 = _terminal_position(terminal_id)
		var service_pos: Vector3 = TERMINAL_SERVICE_POSITIONS[terminal_id]
		_add_overlay_label(_aster_overlay_root, _portal_label(terminal_id), terminal_pos + Vector3(0.0, 2.5, 0.0), Color(0.58, 0.86, 1.0))
		_add_link_overlay(terminal_pos + Vector3(0.0, 1.4, 0.0), service_pos + Vector3(0.0, 1.4, 0.0), Color(0.58, 0.86, 1.0))
		_add_overlay_label(_aster_overlay_root, _terminal_service_label(terminal_id).to_upper(), service_pos + Vector3(0.0, 2.35, 0.0), Color(0.58, 0.86, 1.0))
	_add_layout_ghost(_aster_overlay_root, Vector3(60.0, 0.12, 0.0), Vector2(36.0, 36.0), Color(0.46, 0.76, 0.98))
	_add_layout_ghost(_aster_overlay_root, Vector3(50.0, 0.12, 19.0), Vector2(28.0, 8.0), Color(0.38, 0.66, 0.88))
	_aster_overlay_root.visible = false

	_peris_overlay_root = Node3D.new()
	add_child(_peris_overlay_root)
	_peris_overlay_labels["mother"] = _add_overlay_label(_peris_overlay_root, "MOTHER: STALLED", MOTHER_POS + Vector3(0.0, 3.2, 0.0), Color(1.0, 0.82, 0.48))
	_peris_overlay_labels["care"] = _add_overlay_label(_peris_overlay_root, "CARETAKER TRACE", HIDE_SPOT_POS + Vector3(0.0, 1.9, 0.0), Color(0.82, 0.7, 0.96))
	_peris_overlay_labels["blur"] = _add_overlay_label(_peris_overlay_root, "WORKER MEMORY BLUR", Vector3(57.0, 2.0, 21.0), Color(0.7, 0.74, 1.0))
	for terminal_id in TERMINAL_ORDER:
		var service_roots: Array = TERMINAL_SERVICES[terminal_id]
		for index in range(service_roots.size()):
			var root_id := str(service_roots[index])
			var row_pos := _service_row_position(terminal_id, index, service_roots.size())
			_peris_overlay_labels[root_id] = _add_overlay_label(_peris_overlay_root, "", row_pos + Vector3(0.0, 2.05, 0.0), Color(0.98, 0.78, 0.46))
	_peris_overlay_root.visible = false

	_endo_overlay_root = Node3D.new()
	add_child(_endo_overlay_root)
	_add_endo_beacon("hide", "HIDE SLOT", HIDE_SPOT_POS + Vector3(0.0, 1.8, 0.0), Color(0.64, 0.82, 0.96))
	_add_endo_beacon("gear", "MOTHER GEAR", GEAR_POS + Vector3(0.0, 1.8, 0.0), Color(0.96, 0.78, 0.46))
	_add_endo_beacon("socket", "REPAIR ARRAY", INSTALL_SOCKET_POS + Vector3(-1.6, 1.9, 0.0), Color(0.76, 0.92, 0.54))
	_add_endo_beacon("repair_center", "LOAD REGULATOR", _repair_point_position(CORRECT_REPAIR_ID) + Vector3(0.0, 1.8, 0.0), Color(0.86, 0.98, 0.62))
	_add_endo_beacon("bodies", "FOOD SOURCE", Vector3(57.0, 1.9, 24.0), Color(0.92, 0.7, 0.54))
	_add_endo_beacon("carry", "CARRY LINE", Vector3(60.0, 1.7, 0.0), Color(0.72, 0.94, 0.62))
	_endo_overlay_root.visible = false

func _build_terminal(terminal_id: String, position: Vector3, label_text: String, portal_label: String) -> void:
	_add_box(self, position, Vector3(2.2, 1.5, 1.2), Color(0.1, 0.12, 0.14))
	var screen := _add_box(self, position + Vector3(0.0, 0.9, 0.42), Vector3(1.55, 0.5, 0.08), Color(0.12, 0.16, 0.2), Color(0.18, 0.34, 0.5), 0.42)
	_terminal_materials[terminal_id] = screen.material_override
	_terminal_labels[terminal_id] = _add_label(self, portal_label, position + Vector3(0.0, 1.72, -0.82), Color(0.72, 0.66, 0.54))
	_add_label(self, label_text, position + Vector3(0.0, 2.2, 0.0), Color(0.76, 0.84, 0.92))
	var interactable = _add_inspection_interactable(self, "%sInteractable" % terminal_id.capitalize(), label_text, position + Vector3(0.0, 0.2, 0.0), "HACK", "aster")
	interactable.interacted.connect(Callable(self, "activate_terminal").bind(terminal_id))

func _build_root(root_id: String) -> void:
	var def: Dictionary = ROOT_DEFS[root_id]
	var anchor := int(def.get("anchor", 0))
	var root_pos := _root_world_center(def, anchor)
	var size := _root_size(def)
	var swarm_size := _root_swarm_size(def)
	var root_color: Color = def.get("color", Color(0.5, 0.34, 0.18))
	var root_node := _add_box(self, root_pos, size, root_color, root_color.lightened(0.08), 0.18)
	var swarm_node := _add_box(self, root_pos + Vector3(0.0, ROOT_SWARM_Y_OFFSET, 0.0), swarm_size, Color(0.16, 0.12, 0.08), def.get("swarm_color", Color(0.82, 0.56, 0.2)), 0.48)
	var world_label := _add_label(self, "%s %s" % [def.get("short", ""), def.get("label", root_id)], root_pos + Vector3(0.0, 1.85, 0.0), Color(0.9, 0.78, 0.56))
	_roots[root_id] = {
		"id": root_id,
		"label": def.get("label", root_id.to_upper()),
		"short": def.get("short", root_id.substr(0, 1).to_upper()),
		"orientation": def.get("orientation", "horizontal"),
		"length": int(def.get("length", 2)),
		"fixed_line": int(def.get("fixed_line", 0)),
		"anchor": anchor,
		"initial_anchor": anchor,
		"min_anchor": int(def.get("min_anchor", anchor)),
		"max_anchor": int(def.get("max_anchor", anchor)),
		"terminal": str(def.get("terminal", "")),
		"node": root_node,
		"swarm_node": swarm_node,
		"world_label": world_label,
		"size": size,
		"swarm_size": swarm_size,
		"anim_start": 0.0,
		"anim_end": 0.0,
		"swarm_start": 0.0,
		"swarm_end": 0.0,
		"anim_from_pos": root_pos,
		"anim_to_pos": root_pos,
		"swarm_from_pos": root_pos + Vector3(0.0, ROOT_SWARM_Y_OFFSET, 0.0),
		"swarm_to_pos": root_pos + Vector3(0.0, ROOT_SWARM_Y_OFFSET, 0.0),
	}

func _update_terminal_visuals() -> void:
	for terminal_id in _terminal_materials.keys():
		var material: StandardMaterial3D = _terminal_materials[terminal_id]
		var active: bool = terminal_id == _active_terminal_id and _is_portal_open(_get_scheduler_tick())
		if material != null:
			material.albedo_color = Color(0.18, 0.24, 0.3) if active else Color(0.12, 0.16, 0.2)
			material.emission = Color(0.46, 0.78, 1.0) if active else Color(0.18, 0.34, 0.5)
			material.emission_enabled = true
		if _terminal_labels.has(terminal_id):
			_terminal_labels[terminal_id].modulate = Color(0.98, 0.8, 0.5) if active else Color(0.72, 0.66, 0.54)

func _update_portal_visuals() -> void:
	var open := _is_portal_open(_get_scheduler_tick())
	if _portal_base_fill != null:
		_portal_base_fill.visible = open
	if _portal_base_material != null:
		_portal_base_material.emission_energy_multiplier = 0.84 if open else 0.12
	var remote_pos := Vector3(2000.0, 1.08, 2000.0)
	var label_pos := Vector3(2000.0, 3.0, 2000.0)
	if open:
		remote_pos = _terminal_service_position(_active_terminal_id) + Vector3(0.0, 1.08, 0.0)
		label_pos = _terminal_service_position(_active_terminal_id) + Vector3(0.0, 2.9, 0.0)
		_portal_return_interactable.position = _terminal_service_position(_active_terminal_id) + Vector3(-1.25, 0.2, 0.0)
	else:
		_portal_return_interactable.position = Vector3(2000.0, 0.2, 2000.0)
	if _portal_remote_fill != null:
		_portal_remote_fill.position = remote_pos
		_portal_remote_fill.visible = open
	if _portal_remote_material != null:
		_portal_remote_material.emission_energy_multiplier = 0.92 if open else 0.12
	if _portal_remote_label != null:
		_portal_remote_label.position = label_pos
		_portal_remote_label.visible = open
		_portal_remote_label.text = _terminal_service_label(_active_terminal_id).to_upper() if open else "RETURN"

func _update_portal_overlay(current_tick: float) -> void:
	if _portal_base_material != null and _is_portal_open(current_tick):
		_portal_base_material.emission_energy_multiplier = 0.65 + 0.22 * sin(current_tick * 7.4)
	if _portal_remote_material != null and _is_portal_open(current_tick):
		_portal_remote_material.emission_energy_multiplier = 0.72 + 0.22 * sin(current_tick * 7.4 + 0.4)

func _update_body_visuals() -> void:
	for body_id in BODY_POSITIONS.keys():
		var remaining := int(_body_remaining.get(body_id, 0))
		if _body_materials.has(body_id):
			var material: StandardMaterial3D = _body_materials[body_id]
			material.albedo_color = Color(0.18, 0.16, 0.14) if remaining <= 0 else (Color(0.36, 0.28, 0.2) if _collapse_cleared else Color(0.26, 0.22, 0.18))
		if _body_labels.has(body_id):
			_body_labels[body_id].modulate = Color(0.52, 0.48, 0.44) if remaining <= 0 else Color(0.82, 0.74, 0.66)

func _update_mother_visuals() -> void:
	for material in _mother_bloom_materials:
		if _mother_tended:
			material.albedo_color = Color(0.82, 0.68, 0.26)
			material.emission = Color(1.0, 0.82, 0.34)
			material.emission_energy_multiplier = 1.1
		elif _gear_installed:
			material.albedo_color = Color(0.68, 0.56, 0.22)
			material.emission = Color(0.96, 0.74, 0.3)
			material.emission_energy_multiplier = 0.52
		elif not _repair_attempts.is_empty():
			material.albedo_color = Color(0.62, 0.42, 0.24)
			material.emission = Color(0.88, 0.34, 0.22)
			material.emission_energy_multiplier = 0.28
		else:
			material.albedo_color = Color(0.56, 0.46, 0.22)
			material.emission = Color(0.82, 0.58, 0.24)
			material.emission_energy_multiplier = 0.12
	for repair_id in REPAIR_POINT_ORDER:
		if not _repair_point_materials.has(repair_id):
			continue
		var material: StandardMaterial3D = _repair_point_materials[repair_id]
		if material == null:
			continue
		var base_color: Color = REPAIR_POINT_DEFS[repair_id].get("color", Color(0.72, 0.82, 0.94))
		if _installed_repair_id == repair_id:
			material.albedo_color = base_color.lightened(0.16)
			material.emission_energy_multiplier = 0.9
		elif _repair_attempts.has(repair_id):
			material.albedo_color = base_color.darkened(0.25)
			material.emission_energy_multiplier = 0.18
		else:
			material.albedo_color = Color(0.18, 0.2, 0.24)
			material.emission_energy_multiplier = 0.26
		if _repair_point_labels.has(repair_id):
			_repair_point_labels[repair_id].modulate = base_color.lightened(0.16) if _installed_repair_id == repair_id else (base_color.darkened(0.15) if _repair_attempts.has(repair_id) else base_color)

func _update_overlay_label_states() -> void:
	if _peris_overlay_labels.has("mother"):
		_peris_overlay_labels["mother"].text = "MOTHER: %s" % _mother_stress_label().to_upper()
	for root_id in ROOT_ORDER:
		if not _peris_overlay_labels.has(root_id) or not _roots.has(root_id):
			continue
		_peris_overlay_labels[root_id].text = "%s  %s" % [_fragment_label(root_id), _root_trace_state(root_id)]
	if _endo_overlay_materials.has("gear"):
		_endo_overlay_materials["gear"].emission_energy_multiplier = 0.12 if _gear_installed else 0.62
	if _endo_overlay_materials.has("bodies"):
		_endo_overlay_materials["bodies"].emission_energy_multiplier = 0.18 if _body_units_remaining() <= 0 else 0.7
	if _endo_overlay_materials.has("carry"):
		_endo_overlay_materials["carry"].emission_energy_multiplier = 0.82 if _is_socket_lane_open() else 0.18
	if _endo_overlay_materials.has("socket"):
		_endo_overlay_materials["socket"].emission_energy_multiplier = 0.84 if _is_socket_lane_open() else 0.24
	if _endo_overlay_materials.has("repair_center"):
		_endo_overlay_materials["repair_center"].emission_energy_multiplier = 0.96 if _gear_installed else (0.72 if _diagnosis_ready() else 0.28)

func _add_overlay_label(parent: Node3D, text: String, position: Vector3, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = position
	label.pixel_size = 0.009
	label.font_size = 38
	label.modulate = color
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.48)
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
	return label

func _add_link_overlay(from: Vector3, to: Vector3, color: Color) -> void:
	var segment := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.12, maxf(from.distance_to(to), 0.12))
	segment.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.62
	segment.material_override = material
	segment.position = (from + to) * 0.5
	_aster_overlay_root.add_child(segment)
	segment.look_at(to, Vector3.UP, true)

func _add_layout_ghost(parent: Node3D, position: Vector3, size: Vector2, color: Color) -> void:
	var ghost := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, 0.05, size.y)
	ghost.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.16)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.34
	ghost.material_override = material
	ghost.position = position
	parent.add_child(ghost)

func _add_endo_beacon(id: String, text: String, position: Vector3, color: Color) -> void:
	var beacon := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.24
	mesh.height = 0.48
	beacon.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.12)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.68
	beacon.material_override = material
	beacon.position = position
	_endo_overlay_root.add_child(beacon)
	_add_overlay_label(_endo_overlay_root, text, position + Vector3(0.0, 0.95, 0.0), color)
	_endo_overlay_materials[id] = material

func _repair_point_position(repair_id: String) -> Vector3:
	return Vector3(REPAIR_POINT_DEFS.get(repair_id, {}).get("position", INSTALL_SOCKET_POS))

func _repair_point_label(repair_id: String) -> String:
	return str(REPAIR_POINT_DEFS.get(repair_id, {}).get("label", repair_id.to_upper()))

func _spawn_gear(position: Vector3) -> void:
	if _gear_item_id != "":
		_remove_item(_gear_item_id)
	_gear_item_id = _spawn_item("mother_gear", position, {
		"display_name": "Mother Gear",
		"visual_kind": "mother_gear",
		"visual_color": Color(0.84, 0.7, 0.44),
	})
	_update_gear_interactable_position()

func _update_gear_interactable_position() -> void:
	if _gear_interactable == null:
		return
	if _gear_installed or _gear_item_id == "":
		_gear_interactable.position = Vector3(2000.0, 0.2, 2000.0)
		return
	var state := _get_item_state(_gear_item_id)
	if str(state.get("location", "ground")) != "ground":
		_gear_interactable.position = Vector3(2000.0, 0.2, 2000.0)
		return
	var item_pos: Vector3 = state.get("position", GEAR_POS)
	_gear_interactable.position = item_pos + Vector3(0.0, 0.2, 0.0)

func _reject_wrong_repair(repair_id: String) -> void:
	var current_tick := _get_scheduler_tick()
	_installed_repair_id = ""
	_remove_item(_gear_item_id)
	_gear_item_id = ""
	_apply_wrong_repair_shift(repair_id, current_tick)
	var recovery_pos := HIDE_SPOT_POS + Vector3(1.4 * float(_repair_attempts.size()), 0.24, 0.0)
	_spawn_gear(recovery_pos)
	_endo_cloak_until = maxf(_endo_cloak_until, current_tick + 18.0)
	_hazard_cooldowns.erase("endo")
	_set_ability_state("endo_patch", "ready", 0.0)
	_set_preview_step("mother_%s_rejected" % repair_id)
	_show_note(str(REPAIR_POINT_DEFS[repair_id].get("flare_note", "The chamber rejects the mount and kicks the gear back into the alcove.")), 4.2)
	_update_mother_visuals()
	_update_overlay_label_states()

func _apply_wrong_repair_shift(repair_id: String, current_tick: float) -> void:
	if not REPAIR_POINT_DEFS.has(repair_id):
		return
	var root_id := str(REPAIR_POINT_DEFS[repair_id].get("flare_root", ""))
	var direction := int(REPAIR_POINT_DEFS[repair_id].get("flare_direction", 0))
	if root_id == "" or direction == 0 or not _roots.has(root_id):
		return
	var root: Dictionary = _roots[root_id]
	var target_anchor := clampi(
		int(root.get("anchor", 0)) + direction,
		int(root.get("min_anchor", 0)),
		int(root.get("max_anchor", 0))
	)
	if target_anchor == int(root.get("anchor", 0)):
		return
	if _blocking_root_for(root_id, target_anchor) != "":
		return
	root["anchor"] = target_anchor
	root["anim_start"] = current_tick
	root["anim_end"] = current_tick + ROOT_SLIDE_DURATION * 0.7
	root["swarm_start"] = float(root.get("anim_end", current_tick)) + ROOT_SWARM_LAG * 0.5
	root["swarm_end"] = float(root.get("swarm_start", current_tick)) + ROOT_SWARM_DURATION
	root["anim_from_pos"] = _root_node(root).position
	root["anim_to_pos"] = _root_world_center(root, target_anchor)
	root["swarm_from_pos"] = _root_swarm_node(root).position
	root["swarm_to_pos"] = Vector3(root.get("anim_to_pos", Vector3.ZERO)) + Vector3(0.0, ROOT_SWARM_Y_OFFSET, 0.0)

func _diagnosis_ready() -> bool:
	return "term_alpha" in _log_entries_seen and "term_beta" in _log_entries_seen

func _diagnosis_summary() -> String:
	if _mother_tended:
		return "resolved through the load regulator"
	if _gear_installed:
		return "load regulator mounted"
	if _diagnosis_ready():
		return "core load jam; center spindle wants the gear"
	if "term_alpha" in _log_entries_seen:
		return "old traffic signatures still converge through the center"
	if "term_beta" in _log_entries_seen:
		return "mother is stressed, but the edges look secondary"
	return "partial read only"

func _aster_load_read() -> String:
	if _mother_tended:
		return "handoff open"
	if _diagnosis_ready():
		return "center spindle still owns the freight load"
	if "term_alpha" in _log_entries_seen:
		return "construction ghost converges toward the middle"
	return "ghost map incomplete"

func _peris_fault_read() -> String:
	if _mother_tended:
		return "she's taking the weight cleanly again"
	if _gear_installed:
		return "the core is easing instead of flaring"
	if _diagnosis_ready():
		return "the pain is pooled at her core; edge vents are only echoes"
	if "term_beta" in _log_entries_seen:
		return "the outer lanes hurt, but the knot is deeper"
	return "she feels stalled, not venting"

func _endo_repair_read() -> String:
	if _mother_tended:
		return "handoff complete"
	if _gear_installed:
		return _repair_point_label(_installed_repair_id).to_lower()
	if _diagnosis_ready():
		return _repair_point_label(CORRECT_REPAIR_ID).to_lower()
	if _repair_attempts.is_empty():
		return "unconfirmed"
	return "rejected: %s" % _repair_point_label(str(_repair_attempts[_repair_attempts.size() - 1])).to_lower()

func _terminal_position(terminal_id: String) -> Vector3:
	match terminal_id:
		"term_alpha": return TERM_ALPHA_POS
		"term_beta": return TERM_BETA_POS
		"term_gamma": return TERM_GAMMA_POS
		_: return Vector3.ZERO

func _terminal_service_position(terminal_id: String) -> Vector3:
	return Vector3(TERMINAL_SERVICE_POSITIONS.get(terminal_id, Vector3.ZERO))

func _terminal_service_spawn(terminal_id: String) -> Vector3:
	return _terminal_service_position(terminal_id) + REMOTE_SPAWN_OFFSET

func _terminal_service_label(terminal_id: String) -> String:
	match terminal_id:
		"term_alpha": return "north/east service bay"
		"term_beta": return "central service bay"
		"term_gamma": return "west/south service bay"
		_: return "service bay"

func _portal_label(terminal_id: String) -> String:
	match terminal_id:
		"term_alpha": return "PORTAL-12A"
		"term_beta": return "PORTAL-12B"
		"term_gamma": return "PORTAL-12C"
		_: return "PORTAL"

func _active_service_overlay_label() -> String:
	if _active_terminal_id == "" or not TERMINAL_SERVICES.has(_active_terminal_id):
		return "no braid selected"
	return _terminal_service_label(_active_terminal_id)

func _fragment_label(root_id: String) -> String:
	return str(_roots.get(root_id, {}).get("label", root_id.to_upper()))

func _display_name(char_id: String) -> String:
	match char_id:
		"aster": return "Aster"
		"peris": return "Peris"
		"endo": return "Endo"
		_: return char_id.capitalize()

func _root_node(root: Dictionary) -> MeshInstance3D:
	return root.get("node")

func _root_swarm_node(root: Dictionary) -> MeshInstance3D:
	return root.get("swarm_node")

func _root_world_center(root: Dictionary, anchor: int) -> Vector3:
	var orientation := str(root.get("orientation", "horizontal"))
	var length := int(root.get("length", 2))
	var fixed_line := int(root.get("fixed_line", 0))
	if orientation == "horizontal":
		return Vector3(BOARD_ORIGIN.x + (float(anchor) + float(length) * 0.5) * BOARD_CELL_SIZE, ROOT_CENTER_Y, BOARD_ORIGIN.z + (float(fixed_line) + 0.5) * BOARD_CELL_SIZE)
	return Vector3(BOARD_ORIGIN.x + (float(fixed_line) + 0.5) * BOARD_CELL_SIZE, ROOT_CENTER_Y, BOARD_ORIGIN.z + (float(anchor) + float(length) * 0.5) * BOARD_CELL_SIZE)

func _root_size(root: Dictionary) -> Vector3:
	var orientation := str(root.get("orientation", "horizontal"))
	var length := int(root.get("length", 2))
	if orientation == "horizontal":
		return Vector3(float(length) * BOARD_CELL_SIZE - ROOT_GAP, ROOT_WIDTH * 0.2, ROOT_WIDTH)
	return Vector3(ROOT_WIDTH, ROOT_WIDTH * 0.2, float(length) * BOARD_CELL_SIZE - ROOT_GAP)

func _root_swarm_size(root: Dictionary) -> Vector3:
	var size := _root_size(root)
	var orientation := str(root.get("orientation", "horizontal"))
	if orientation == "horizontal":
		return Vector3(size.x + ROOT_SWARM_EXTRA_LENGTH, 0.06, size.z + ROOT_SWARM_EXTRA_WIDTH)
	return Vector3(size.x + ROOT_SWARM_EXTRA_WIDTH, 0.06, size.z + ROOT_SWARM_EXTRA_LENGTH)

func _service_row_position(terminal_id: String, index: int, count: int) -> Vector3:
	var base_pos := _terminal_service_position(terminal_id)
	return base_pos + Vector3(0.0, 0.0, (float(index) - float(count - 1) * 0.5) * 3.6)

func _bud_label(direction: int) -> String:
	return "LEFT BUD" if direction < 0 else "RIGHT BUD"

func _default_move_direction(root_id: String) -> int:
	if not _roots.has(root_id):
		return 0
	var root: Dictionary = _roots[root_id]
	var anchor := int(root.get("anchor", 0))
	var initial_anchor := int(root.get("initial_anchor", anchor))
	if anchor <= initial_anchor and anchor < int(root.get("max_anchor", anchor)):
		return 1
	if anchor > int(root.get("min_anchor", anchor)):
		return -1
	return 0

func _update_root_world_label(root: Dictionary) -> void:
	var world_label: Label3D = root.get("world_label")
	if world_label != null:
		world_label.position = _root_node(root).position + Vector3(0.0, 1.85, 0.0)

func _apply_root_pose(root_id: String, root_pos: Vector3, swarm_pos: Vector3) -> void:
	if not _roots.has(root_id):
		return
	_root_node(_roots[root_id]).position = root_pos
	_root_swarm_node(_roots[root_id]).position = swarm_pos
	_update_root_world_label(_roots[root_id])

func _root_cells(root: Dictionary) -> Array[Vector2i]:
	return _root_cells_for_anchor(root, int(root.get("anchor", 0)))

func _root_cells_for_anchor(root: Dictionary, anchor: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var length := int(root.get("length", 2))
	var fixed_line := int(root.get("fixed_line", 0))
	if str(root.get("orientation", "horizontal")) == "horizontal":
		for step in range(length):
			cells.append(Vector2i(anchor + step, fixed_line))
	else:
		for step in range(length):
			cells.append(Vector2i(fixed_line, anchor + step))
	return cells

func _cell_name(cell: Vector2i) -> String:
	return "%s%d" % [BOARD_ROWS[cell.y], cell.x + 1]

func _mother_stress_label() -> String:
	if _mother_tended:
		return "blooming"
	if _gear_installed:
		return "easing"
	if not _repair_attempts.is_empty():
		return "flaring"
	return "stalled"

func _peris_board_read() -> String:
	if _mother_tended or _is_mother_lane_clear():
		return "open toward the mother"
	if _gear_installed:
		return "east side thinning"
	if not _repair_attempts.is_empty():
		return "core still misread"
	if _is_socket_lane_open():
		return "center line breathing"
	if _is_gear_pocket_open():
		return "west pocket exposed"
	return "still knotted"

func _peris_memory_blur_read() -> String:
	if _collapse_cleared and _body_units_remaining() <= 0:
		return "fading from the collapse wing"
	if _collapse_cleared:
		return "clustering near the collapse wing"
	return "distant and intermittent"

func _root_trace_state(root_id: String) -> String:
	if not _roots.has(root_id):
		return ""
	var root: Dictionary = _roots[root_id]
	var current_tick := _get_scheduler_tick()
	if current_tick < float(root.get("swarm_end", 0.0)):
		return "SHIVERING"
	var anchor := int(root.get("anchor", 0))
	var initial_anchor := int(root.get("initial_anchor", anchor))
	var min_anchor := int(root.get("min_anchor", anchor))
	var max_anchor := int(root.get("max_anchor", anchor))
	if anchor == initial_anchor:
		return "FAMILIAR"
	if anchor == min_anchor or anchor == max_anchor:
		return "STRAINED"
	return "DISTURBED"

func _blocking_root_for(root_id: String, target_anchor: int) -> String:
	if not _roots.has(root_id):
		return ""
	var target_cells := _root_cells_for_anchor(_roots[root_id], target_anchor)
	for other_id in ROOT_ORDER:
		if other_id == root_id or not _roots.has(other_id):
			continue
		for target_cell in target_cells:
			if _root_cells(_roots[other_id]).has(target_cell):
				return other_id
	return ""

func _character_in_any_hazard(char_pos: Vector3) -> bool:
	for root_id in ROOT_ORDER:
		if not _roots.has(root_id):
			continue
		var root: Dictionary = _roots[root_id]
		if _point_in_hazard_band(char_pos, _root_node(root).position, Vector3(root.get("size", Vector3.ONE)) + Vector3(0.4, 0.0, 0.4)):
			return true
		if _point_in_hazard_band(char_pos, _root_swarm_node(root).position, Vector3(root.get("swarm_size", Vector3.ONE)) + Vector3(0.5, 0.0, 0.5)):
			return true
	return false

func _point_in_hazard_band(point: Vector3, center: Vector3, size: Vector3) -> bool:
	return absf(point.x - center.x) <= size.x * 0.5 and absf(point.z - center.z) <= size.z * 0.5

func _is_portal_open(current_tick: float) -> bool:
	return _active_terminal_id != "" and current_tick <= _portal_open_until

func _body_units_remaining() -> int:
	var total := 0
	for remaining in _body_remaining.values():
		total += int(remaining)
	return total

func _has_free_hand_slots(char_id: String, required_slots: int) -> bool:
	var free_count := 0
	for slot in _get_hand_slots(char_id):
		if slot == null:
			free_count += 1
			if free_count >= required_slots:
				return true
	return false

func _endo_holds_gear() -> bool:
	if _gear_item_id == "":
		return false
	var state := _get_item_state(_gear_item_id)
	return str(state.get("holder", "")) == "endo" and str(state.get("location", "")) == "hand"

func _lane_cells_clear(row: int, start_col: int, end_col: int) -> bool:
	for root_id in ROOT_ORDER:
		if not _roots.has(root_id):
			continue
		for cell in _root_cells(_roots[root_id]):
			if cell.y == row and cell.x >= start_col and cell.x <= end_col:
				return false
	return true

func _is_gear_pocket_open() -> bool:
	return int(_roots.get("gear_latch", {}).get("anchor", 0)) >= 1 and int(_roots.get("socket_brace", {}).get("anchor", 2)) >= 3

func _is_socket_lane_open() -> bool:
	return _lane_cells_clear(2, 0, 3)

func _is_mother_lane_clear() -> bool:
	return _lane_cells_clear(2, 0, 5)
