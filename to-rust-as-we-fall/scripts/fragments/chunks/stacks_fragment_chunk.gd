extends "res://scripts/scene_chunks/scene_chunk.gd"

const STACKS_STORY_KEY := "stacks_support_team_log"
const FLOOR_CENTER := Vector3(32.0, -0.05, 0.0)
const FLOOR_SIZE := Vector3(68.0, 0.1, 24.0)
const SUPPORT_LOG_POS := Vector3(10.0, 0.6, -3.5)
const TERMINAL_POS := Vector3(26.0, 0.8, 0.0)
const SIGNAL_POS := Vector3(42.0, 0.8, -7.2)
const ARCHIVE_POS := Vector3(56.0, 0.8, 6.2)
const SPAWNS := {
	"aster": Vector3(4.0, 0.5, 0.0),
	"peris": Vector3(2.0, 0.5, 1.6),
	"endo": Vector3(0.0, 0.5, -1.6),
}

var _support_log_interactable
var _terminal_interactable
var _signal_interactable
var _archive_interactable

var _support_log_seen := false
var _terminal_seen := false
var _signal_seen := false
var _archive_seen := false
var _last_station := ""

func _build_chunk() -> void:
	_add_floor(self, FLOOR_CENTER, FLOOR_SIZE, Color(0.05, 0.055, 0.065))
	_add_box(self, Vector3(32.0, 2.0, -12.1), Vector3(68.0, 4.0, 0.3), Color(0.1, 0.1, 0.12))
	_add_box(self, Vector3(32.0, 2.0, 12.1), Vector3(68.0, 4.0, 0.3), Color(0.1, 0.1, 0.12))

	for i in range(5):
		_add_light(self, Vector3(8.0 + float(i) * 12.0, 3.8, 0.0), Color(0.58, 0.68, 0.82), 1.7, 14.0)

	for x_pos in [14.0, 28.0, 40.0, 52.0]:
		_add_server_rack(Vector3(x_pos, 0.9, 8.0))
		_add_server_rack(Vector3(x_pos, 0.9, -8.0))

	_build_support_log_station()
	_build_terminal_station()
	_build_signal_station()
	_build_archive_station()

func get_scene_title() -> String:
	return "Stacks Fragment Lab"

func get_scene_help() -> String:
	return "Walk Aster through the support log, terminal, signal wall, and archive workspace."

func get_default_character() -> String:
	return "aster"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors.merge({
		"support_log": SUPPORT_LOG_POS,
		"terminal": TERMINAL_POS,
		"signal": SIGNAL_POS,
		"archive": ARCHIVE_POS,
	}, true)
	return anchors

func get_preview_time_state() -> Dictionary:
	return {
		"day": 1,
		"time": 0.34,
		"routing_mode": "safe",
		"note_default": "Stacks boots as a clean support lane: everyone starts topped off so you can focus on reading the fragment and testing the full HUD.",
	}

func get_preview_abilities() -> Array:
	# Display names + descriptions + tuning live in data/abilities/en/abilities.xlsx (per-context rows).
	return AbilityData.for_context("stacks_fragment")
func get_preview_state() -> Dictionary:
	return {
		"support_log_seen": _support_log_seen,
		"terminal_seen": _terminal_seen,
		"signal_seen": _signal_seen,
		"archive_seen": _archive_seen,
		"last_station": _last_station,
	}

func reset_preview_state() -> void:
	_support_log_seen = false
	_terminal_seen = false
	_signal_seen = false
	_archive_seen = false
	_last_station = ""
	for interactable in [_support_log_interactable, _terminal_interactable, _signal_interactable, _archive_interactable]:
		if interactable != null and interactable.has_method("reset"):
			interactable.reset()

func handle_preview_ability(ability_id: String, _ability: Dictionary = {}) -> Dictionary:
	match ability_id:
		"peris_tune":
			return {
				"characters": {
					"peris": {"sta_delta": 14.0},
					"aster": {"sta_delta": 6.0},
				},
			}
		"endo_patch":
			return {
				"characters": {
					"aster": {"hp_delta": 8.0},
					"endo": {"sta_delta": 10.0},
				},
			}
		_:
			return {}

func _add_server_rack(position: Vector3) -> void:
	var rack := Node3D.new()
	rack.position = position
	add_child(rack)
	_add_box(rack, Vector3.ZERO, Vector3(2.4, 1.8, 1.6), Color(0.08, 0.09, 0.11))
	for slot in range(5):
		_add_box(
			rack,
			Vector3(0.0, -0.55 + float(slot) * 0.28, 0.82),
			Vector3(1.9, 0.1, 0.08),
			Color(0.08, 0.1, 0.12),
			Color(0.18, 0.34, 0.46),
			0.55
		)

func _build_support_log_station() -> void:
	_add_box(self, SUPPORT_LOG_POS + Vector3(0.0, 0.0, 0.0), Vector3(1.6, 1.2, 1.0), Color(0.12, 0.14, 0.18))
	_add_box(
		self,
		SUPPORT_LOG_POS + Vector3(0.0, 0.82, 0.38),
		Vector3(1.2, 0.4, 0.08),
		Color(0.12, 0.18, 0.22),
		Color(0.22, 0.42, 0.58),
		0.7
	)
	_add_label(self, "SUPPORT LOG", SUPPORT_LOG_POS + Vector3(0.0, 2.2, 0.0))
	_support_log_interactable = _add_inspection_interactable(
		self,
		"SupportLogInteractable",
		"Support Log",
		SUPPORT_LOG_POS + Vector3(0.0, 0.3, 0.0),
		"LOG",
		"aster"
	)
	_support_log_interactable.interacted.connect(_on_support_log_interacted)

func _build_terminal_station() -> void:
	_add_box(self, TERMINAL_POS, Vector3(2.2, 1.4, 1.2), Color(0.1, 0.12, 0.14))
	_add_box(
		self,
		TERMINAL_POS + Vector3(0.0, 0.92, 0.44),
		Vector3(1.6, 0.55, 0.08),
		Color(0.12, 0.16, 0.2),
		Color(0.16, 0.34, 0.52),
		0.8
	)
	_add_label(self, "NORMALIZATION TERMINAL", TERMINAL_POS + Vector3(0.0, 2.4, 0.0))
	_terminal_interactable = _add_inspection_interactable(
		self,
		"TerminalInteractable",
		"Normalization Terminal",
		TERMINAL_POS + Vector3(0.0, 0.3, 0.0),
		"READ",
		"aster"
	)
	_terminal_interactable.interacted.connect(_on_terminal_interacted)

func _build_signal_station() -> void:
	_add_box(self, SIGNAL_POS + Vector3(0.0, 0.0, -1.1), Vector3(6.8, 0.08, 1.8), Color(0.18, 0.15, 0.08), Color(0.4, 0.3, 0.14), 0.25)
	_add_box(self, SIGNAL_POS + Vector3(0.0, 1.3, -2.0), Vector3(6.0, 2.4, 0.18), Color(0.11, 0.11, 0.09), Color(0.42, 0.34, 0.18), 0.55)
	for i in range(4):
		_add_box(
			self,
			SIGNAL_POS + Vector3(-1.8 + float(i) * 1.2, 1.2, -1.88),
			Vector3(0.44, 1.3 + 0.14 * float(i % 2), 0.08),
			Color(0.12, 0.16, 0.14),
			Color(0.52, 0.74, 0.28) if i < 2 else Color(0.8, 0.62, 0.24),
			0.65
		)
	_add_label(self, "CUSTOM SIGNAL WALL", SIGNAL_POS + Vector3(0.0, 2.7, -1.2))
	_signal_interactable = _add_inspection_interactable(
		self,
		"SignalInteractable",
		"Custom Signal Wall",
		SIGNAL_POS + Vector3(0.0, 0.3, -0.9),
		"SCAN",
		"aster"
	)
	_signal_interactable.interacted.connect(_on_signal_interacted)

func _build_archive_station() -> void:
	_add_box(self, ARCHIVE_POS, Vector3(2.6, 1.0, 1.4), Color(0.14, 0.12, 0.1))
	for i in range(4):
		_add_box(
			self,
			ARCHIVE_POS + Vector3(-0.6 + float(i) * 0.4, 0.65, 0.66),
			Vector3(0.18, 0.72, 0.1),
			Color(0.24, 0.2, 0.14),
			Color(0.42, 0.34, 0.18),
			0.22
		)
	_add_label(self, "TUNED WORKSPACE", ARCHIVE_POS + Vector3(0.0, 2.3, 0.0))
	_archive_interactable = _add_inspection_interactable(
		self,
		"ArchiveInteractable",
		"Tuned Workspace",
		ARCHIVE_POS + Vector3(0.0, 0.3, 0.0),
		"ARCHIVE",
		"aster"
	)
	_archive_interactable.interacted.connect(_on_archive_interacted)

func _on_support_log_interacted() -> void:
	_support_log_seen = true
	_last_station = "support_log"
	_set_preview_step("stacks_support_log")

	var context := {}
	if host != null and host.has_method("get_capture_context"):
		context = host.call("get_capture_context")
	context["scene_name"] = "Stacks Fragment Lab"
	context["location"] = "Stacks Fragment Lab"
	context["sub_location"] = "Support Log"
	context["trigger_type"] = "story"
	context["trigger_context"] = "support_team_log"
	context["position"] = SUPPORT_LOG_POS
	context["caption"] = "Support team maintenance log"

	var entry := EngramJournal.ensure_story_log_entry(
		STACKS_STORY_KEY,
		DialogueData.text("stacks.engram.support_log.title"),
		DialogueData.text("stacks.engram.support_log.body"),
		context,
		{
			"caption": "Support team maintenance log",
			"trigger_context": "support_team_log",
			"attached_data": {
				"channel": "#ependyma-core",
			},
		}
	)
	var overlay := _engram_overlay()
	if overlay != null and not entry.is_empty():
		overlay.open_overlay_for_entry(int(entry.get("id", -1)))
	_show_note("The support thread opens in Aster's Engram. J or Esc closes it.", 4.2)

func _on_terminal_interacted() -> void:
	_terminal_seen = true
	_last_station = "terminal"
	_set_preview_step("stacks_terminal")
	_clear_dialogue()
	_say_key("stacks.narration.cleaned_terminal")
	_say_key("stacks.aster.cleaner_than_place")
	_say_key("stacks.aster.expectation")
	_show_note("The official feed is polished, but the room around it is not.", 3.4)

func _on_signal_interacted() -> void:
	_signal_seen = true
	_last_station = "signal"
	_set_preview_step("stacks_signal")
	_clear_dialogue()
	_say_key("stacks.narration.instrumented_lane")
	_say_key("stacks.aster.nonstandard")
	_say_key("stacks.aster.metrics")
	_show_note("This lane is tuned by hand. The room starts reading like somebody cared about the right signals.", 4.0)

func _on_archive_interacted() -> void:
	_archive_seen = true
	_last_station = "archive"
	_set_preview_step("stacks_archive")
	_clear_dialogue()
	_say_key("stacks.narration.workspace")
	_say_key("stacks.aster.ghost_ids")
	_say_key("stacks.peris.fake_permissions")
	_show_note("The archive turns admiration into suspicion: somebody hid good data on purpose.", 4.0)
