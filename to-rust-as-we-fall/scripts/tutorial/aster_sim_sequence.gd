@tool
extends "res://scripts/tutorial/tutorial_sequence.gd"

## Aster simulation tutorial: movement, interaction, ATP, Ron, Tag Day.

var _has_moved := false
var _has_drunk := false

var _ron
var _terminal  # Forecasting terminal interactable.
var _drink_machine  # Drink machine interactable.
var _hud  # GameHUD with ATP bar and portrait.

# Terminal screen-focus cinematic (click the terminal → camera frames the
# screen, the low-fi screen swaps for a detailed readout, then the beat ends).
const TERMINAL_FOCUS_DURATION := 3.0
# Aster reads the monitor from the CHAIR side (its real front, MEASURED from the chair node — see
# _screen_facing, not an assumed world axis; the TerminalInteract marker is placed there). The focus
# camera sits TERMINAL_FOCUS_BACK back along that same facing (behind him, over his shoulder) and RISE up,
# looking down at the screen. The panel is rotated to face the same way, so the camera reads it flat
# (parallel to the display), never edge-on.
const TERMINAL_FOCUS_BACK := 2.7
const TERMINAL_FOCUS_RISE := 1.3
var _terminal_screen_world := Vector3.ZERO
var _terminal_screen_lowfi: MeshInstance3D
var _terminal_screen_detail: Node3D
var _terminal_screen_readout: Label3D
var _terminal_prev_camera_target: Node3D
var _terminal_focus_active := false  # true while the screen is up (guards re-click mid-focus)

# Exploration beat (post-drink, pre-Tag-Day)
@export var show_graybox_room := false  # the imported room model is the environment; flip on for graybox dev
@export var show_high_res_room := true
var _explore_hallway_gate  # Interactable at hallway exit
const EXPLORE_MIN_TIME := 12.0  # scheduler ticks before the workspace-progress reminder
const WORKSPACE_THREAD_REQUIRED := {
	"glass": 1,
	"paintings": 2,
	"awards": 2,
	"jstore": 2,
}
# The post-inspection fault desk is an active circuit, never a clock gate. Each case sends Aster
# to three already-visible room objects, stages the LAST candidate he reviewed, and asks him to
# commit that cause at the existing terminal. The discriminating third trace prevents a blind
# two-object coin flip while keeping every clue on something the player already learned to inspect.
const FAULT_EVIDENCE_WORK_SECONDS := 8.0
const FAULT_COMMIT_ATP_COST := 3.0
const FAULT_WRONG_ATP_COST := 1.0
const FAULT_DRINK_RECOVERY_SECONDS := 0.8
const ASTER_ROUTE_SPEED_FALLBACK := 3.0
const WORKSPACE_OBSERVATION_SECONDS_PER_BEAT := 2.0
const FAULT_SYNTHESIS_SECONDS_PER_CASE := 18.0
const PROTOCOL_SYNTHESIS_SECONDS_PER_OPERATION := 16.0
const ASTER_INACTIVE_PRESENTATION_SECONDS := 88.0
const FAULT_EVIDENCE_SOURCES := {
	"glass": {
		"zone": "GlassBeadZone",
		"target": "RoomTargetGlassBeadGame",
		"node": "FaultEvidenceGlass",
		"marker": "GlassBeadZoneMarker",
		"label": "TRACE GLASS TOPOLOGY",
	},
	"painting_teal": {
		"zone": "macabre_tealZone",
		"target": "RoomTargetMacabreTealPainting",
		"node": "FaultEvidenceTeal",
		"marker": "MacabreTealZoneMarker",
		"label": "COMPARE TEAL TRACE",
	},
	"painting_ash": {
		"zone": "hunter_ashZone",
		"target": "RoomTargetHunterAshPainting",
		"node": "FaultEvidenceAsh",
		"marker": "HunterAshZoneMarker",
		"label": "COMPARE ASH TRACE",
	},
	"awards": {
		"zone": "AwardsCenterZone",
		"target": "RoomTargetAwardsShelf",
		"node": "FaultEvidenceAwards",
		"marker": "AwardsCenterZoneMarker",
		"label": "TRACE CREDIT LEDGER",
	},
	"jstore": {
		"zone": "JStoreMainZone",
		"target": "RoomTargetJStoreShelf",
		"node": "FaultEvidenceJStore",
		"marker": "JStoreMainZoneMarker",
		"label": "TRACE FAULT ARCHIVE",
	},
}
const FAULT_REVIEW_CASES := [
	{
		"id": "normalization_recurrence",
		"brief": "FAULT 1/3: recurrence follows normalization; a local connector loss should not repeat across barriers.",
		"evidence": ["awards", "glass", "jstore"],
		"candidates": ["glass", "jstore"],
		"correct": "jstore",
		"clues": {
			"awards": "Credit ledger: the reward posted after support maintenance, not before it.",
			"glass": "Glass topology: one missing connector remains local instead of recurring across barriers.",
			"jstore": "Fault archive: the same drift returns immediately after normalization retries.",
		},
		"wrong_clue": "Connector loss would stay local. Recheck the J-store recurrence trace, stage another candidate, then recommit.",
	},
	{
		"id": "thermal_band_drift",
		"brief": "FAULT 2/3: only one visual band widens as the barrier temperature climbs.",
		"evidence": ["painting_teal", "glass", "painting_ash"],
		"candidates": ["painting_teal", "painting_ash"],
		"correct": "painting_ash",
		"clues": {
			"painting_teal": "Teal trace: its geometry stays flat through the heat band.",
			"glass": "Glass topology: every node remains connected, ruling out a missing-link cascade.",
			"painting_ash": "Ash trace: the outer band widens in step with the temperature rise.",
		},
		"wrong_clue": "The teal trace stays flat. Recheck the heat-linked ash band, stage another candidate, then recommit.",
	},
	{
		"id": "repair_attribution",
		"brief": "FAULT 3/3: system credit and actual repair authorship disagree.",
		"evidence": ["painting_teal", "awards", "jstore"],
		"candidates": ["awards", "jstore"],
		"correct": "jstore",
		"clues": {
			"painting_teal": "Maintenance trace: the support window predates the system's completion stamp.",
			"awards": "Credit ledger: it names Aster but contains no repair-author record.",
			"jstore": "Published signature: the adjustment matches support-crew work, not operator input.",
		},
		"wrong_clue": "Attribution is not repair evidence. Recheck the published signature, stage another candidate, then recommit.",
	},
]

# Three different spatial protocols follow diagnosis. They deliberately avoid adding more fault cases:
# phase alignment is an ordered walk, load balance is an any-order survey followed by a three-station
# physical branch, and authorship handoff is an information choice with a two-station persistent result.
# All pads are projected into open floor lanes; none changes the room model or drink-machine clearance.
const WORKSPACE_PROTOCOL_ORDER := ["phase_alignment", "load_balance", "authorship_handoff"]
const WORKSPACE_PROTOCOLS := {
	"phase_alignment": {
		"step": "workspace_protocol_phase_alignment",
		"label": "BARRIER PHASE WALK",
		"tint": Color(0.28, 0.72, 1.0),
		"ordered_evidence": true,
		"evidence": ["phase_origin", "phase_north", "phase_mid", "phase_south", "phase_return"],
		"choices": ["phase_sweep", "phase_isolate"],
		"execution_sites": {
			"phase_sweep": ["phase_sweep_execution"],
			"phase_isolate": ["phase_isolate_execution"],
		},
		"next": "load_balance",
	},
	"load_balance": {
		"step": "workspace_protocol_load_balance",
		"label": "FORECAST LOAD BALANCE",
		"tint": Color(0.44, 0.92, 0.58),
		"ordered_evidence": false,
		"evidence": ["load_source", "load_regulator", "load_reserve", "load_sink"],
		"choices": ["load_hold_reserve", "load_open_throughput"],
		"execution_sites": {
			"load_hold_reserve": ["reserve_anchor", "reserve_divert", "reserve_seal"],
			"load_open_throughput": ["throughput_open", "throughput_bridge", "throughput_lock"],
		},
		"next": "authorship_handoff",
	},
	"authorship_handoff": {
		"step": "workspace_protocol_authorship_handoff",
		"label": "REPAIR AUTHORSHIP HANDOFF",
		"tint": Color(0.94, 0.66, 0.28),
		"ordered_evidence": false,
		"evidence": ["authorship_ledger", "authorship_signature", "authorship_support"],
		"choices": ["authorship_name_crew", "authorship_publish_operator"],
		"execution_sites": {
			"authorship_name_crew": ["crew_context_execution", "crew_handoff_execution"],
			"authorship_publish_operator": ["operator_signature_execution", "operator_handoff_execution"],
		},
		"next": "",
	},
}

const WORKSPACE_PROTOCOL_SITES := {
	"phase_origin": {"protocol": "phase_alignment", "kind": "evidence", "pos": Vector3(2.0, 0.12, 12.0), "dwell": 5.0, "label": "READ ORIGIN PHASE", "display": "ORIGIN", "finding": "The barrier reference begins half a cycle ahead of Aster's forecast."},
	"phase_north": {"protocol": "phase_alignment", "kind": "evidence", "pos": Vector3(3.3, 0.12, 10.4), "dwell": 5.0, "label": "ALIGN NORTH NODE", "display": "NORTH", "finding": "The north node preserves the offset instead of accumulating it."},
	"phase_mid": {"protocol": "phase_alignment", "kind": "evidence", "pos": Vector3(2.2, 0.12, 8.2), "dwell": 5.0, "label": "ALIGN MID NODE", "display": "MID", "finding": "The middle node exposes one recoverable discontinuity."},
	"phase_south": {"protocol": "phase_alignment", "kind": "evidence", "pos": Vector3(3.1, 0.12, 6.0), "dwell": 5.0, "label": "ALIGN SOUTH NODE", "display": "SOUTH", "finding": "The south node can accept either a full sweep or a local isolate."},
	"phase_return": {"protocol": "phase_alignment", "kind": "evidence", "pos": Vector3(2.0, 0.12, 3.9), "dwell": 5.0, "label": "CLOSE PHASE LOOP", "display": "RETURN", "finding": "The return pulse arrives inside tolerance and unlocks two valid calibrations."},
	"phase_sweep": {"protocol": "phase_alignment", "kind": "choice", "pos": Vector3(4.0, 0.12, 4.6), "dwell": 3.2, "label": "PLAN FULL SWEEP", "display": "SWEEP", "finding": "A full sweep maximizes forecast fidelity but exposes the entire lattice."},
	"phase_isolate": {"protocol": "phase_alignment", "kind": "choice", "pos": Vector3(4.0, 0.12, 6.2), "dwell": 3.2, "label": "PLAN LOCAL ISOLATE", "display": "ISOLATE", "finding": "A local isolate protects the room while accepting a narrower forecast."},
	"phase_sweep_execution": {"protocol": "phase_alignment", "kind": "execution", "pos": Vector3(4.6, 0.12, 9.5), "dwell": 6.0, "label": "EXECUTE PHASE SWEEP", "display": "SWEEP", "finding": "The full lattice resolves into one high-fidelity forecast band."},
	"phase_isolate_execution": {"protocol": "phase_alignment", "kind": "execution", "pos": Vector3(2.0, 0.12, 7.1), "dwell": 6.0, "label": "EXECUTE ISOLATE", "display": "ISOLATE", "finding": "The unstable segment is isolated without disturbing the room perimeter."},

	"load_source": {"protocol": "load_balance", "kind": "evidence", "pos": Vector3(2.0, 0.12, 2.4), "dwell": 5.5, "label": "MEASURE SOURCE LOAD", "display": "SOURCE", "finding": "The source has enough margin for either reserve or throughput routing."},
	"load_regulator": {"protocol": "load_balance", "kind": "evidence", "pos": Vector3(4.5, 0.12, 3.2), "dwell": 5.5, "label": "MEASURE REGULATOR", "display": "REGULATOR", "finding": "The regulator can hold a reserve only if the sink remains below threshold."},
	"load_reserve": {"protocol": "load_balance", "kind": "evidence", "pos": Vector3(3.8, 0.12, 6.7), "dwell": 5.5, "label": "MEASURE RESERVE", "display": "RESERVE", "finding": "The reserve lane carries slower recovery with no attribution loss."},
	"load_sink": {"protocol": "load_balance", "kind": "evidence", "pos": Vector3(7.3, 0.12, 6.1), "dwell": 5.5, "label": "MEASURE SINK", "display": "SINK", "finding": "The sink can absorb a fast pass but leaves less thermal margin."},
	"load_hold_reserve": {"protocol": "load_balance", "kind": "choice", "pos": Vector3(3.5, 0.12, 9.0), "dwell": 3.2, "label": "PLAN RESERVE HOLD", "display": "RESERVE", "finding": "Aster chooses a slower reserve-preserving route."},
	"load_open_throughput": {"protocol": "load_balance", "kind": "choice", "pos": Vector3(6.1, 0.12, 8.8), "dwell": 3.2, "label": "PLAN THROUGHPUT", "display": "THROUGHPUT", "finding": "Aster chooses a fast route with a narrower thermal margin."},
	"reserve_anchor": {"protocol": "load_balance", "kind": "execution", "pos": Vector3(2.0, 0.12, 10.4), "dwell": 5.2, "label": "ANCHOR RESERVE", "display": "ANCHOR", "finding": "The reserve anchor takes the first share of the forecast load."},
	"reserve_divert": {"protocol": "load_balance", "kind": "execution", "pos": Vector3(3.8, 0.12, 11.7), "dwell": 5.2, "label": "DIVERT LOAD", "display": "DIVERT", "finding": "The excess load moves away from the fragile sink."},
	"reserve_seal": {"protocol": "load_balance", "kind": "execution", "pos": Vector3(5.7, 0.12, 10.5), "dwell": 5.2, "label": "SEAL RESERVE ROUTE", "display": "SEAL", "finding": "The slower route closes with a stable recovery margin."},
	"throughput_open": {"protocol": "load_balance", "kind": "execution", "pos": Vector3(7.4, 0.12, 9.5), "dwell": 5.2, "label": "OPEN FAST LANE", "display": "OPEN", "finding": "The fast lane accepts the leading edge of the load."},
	"throughput_bridge": {"protocol": "load_balance", "kind": "execution", "pos": Vector3(5.8, 0.12, 11.8), "dwell": 5.2, "label": "BRIDGE LOAD", "display": "BRIDGE", "finding": "A temporary bridge keeps the high-throughput band coherent."},
	"throughput_lock": {"protocol": "load_balance", "kind": "execution", "pos": Vector3(3.5, 0.12, 10.2), "dwell": 5.2, "label": "LOCK FAST ROUTE", "display": "LOCK", "finding": "The route locks before its thermal margin collapses."},

	"authorship_ledger": {"protocol": "authorship_handoff", "kind": "evidence", "pos": Vector3(7.0, 0.12, 13.2), "dwell": 6.0, "label": "READ CREDIT LEDGER", "display": "LEDGER", "finding": "The ledger credits Aster while omitting every support-crew identifier."},
	"authorship_signature": {"protocol": "authorship_handoff", "kind": "evidence", "pos": Vector3(4.8, 0.12, 12.8), "dwell": 6.0, "label": "READ REPAIR SIGNATURE", "display": "SIGNATURE", "finding": "The repair signature still preserves the support team's method."},
	"authorship_support": {"protocol": "authorship_handoff", "kind": "evidence", "pos": Vector3(2.2, 0.12, 12.0), "dwell": 6.0, "label": "READ SUPPORT CONTEXT", "display": "CONTEXT", "finding": "A private context channel can carry the names without exposing them publicly."},
	"authorship_name_crew": {"protocol": "authorship_handoff", "kind": "choice", "pos": Vector3(2.5, 0.12, 9.0), "dwell": 3.2, "label": "PLAN CREW CONTEXT", "display": "CREW", "finding": "Aster preserves the support crew's names in the handoff context."},
	"authorship_publish_operator": {"protocol": "authorship_handoff", "kind": "choice", "pos": Vector3(5.0, 0.12, 9.2), "dwell": 3.2, "label": "PLAN OPERATOR RECORD", "display": "OPERATOR", "finding": "Aster accepts the public operator record while retaining the repair signature."},
	"crew_context_execution": {"protocol": "authorship_handoff", "kind": "execution", "pos": Vector3(2.2, 0.12, 6.8), "dwell": 5.8, "label": "SEAL CREW CONTEXT", "display": "CONTEXT", "finding": "The crew context is sealed into the private maintenance record."},
	"crew_handoff_execution": {"protocol": "authorship_handoff", "kind": "execution", "pos": Vector3(3.8, 0.12, 5.0), "dwell": 5.8, "label": "HAND OFF CREW RECORD", "display": "HANDOFF", "finding": "The signed handoff carries the crew's work forward."},
	"operator_signature_execution": {"protocol": "authorship_handoff", "kind": "execution", "pos": Vector3(6.3, 0.12, 6.0), "dwell": 5.8, "label": "SEAL OPERATOR RECORD", "display": "OPERATOR", "finding": "The operator record is sealed without erasing the underlying signature."},
	"operator_handoff_execution": {"protocol": "authorship_handoff", "kind": "execution", "pos": Vector3(4.8, 0.12, 4.0), "dwell": 5.8, "label": "HAND OFF OPERATOR RECORD", "display": "HANDOFF", "finding": "The public handoff retains a verifiable link to the support repair."},
}
var _explore_gate_unlocked := false
var _explore_gate_fired := false
var _workspace_thread_counts: Dictionary = {}
var _workspace_zone_counts: Dictionary = {}
var _fault_evidence_interactables: Dictionary = {}
var _fault_case_evidence: Dictionary = {}
var _fault_evidence_review_counts: Dictionary = {}
var _fault_commit_history: Array = []
var _fault_case_index := -1
var _fault_selected_candidate := ""
var _fault_correct_commits := 0
var _fault_wrong_commits := 0
var _fault_wrong_atp_spent := 0.0
var _fault_case_wrong_penalized := false
var _fault_drink_recoveries := 0
var _fault_terminal_pending := false
var _fault_circuit_started := false
var _fault_circuit_complete := false
var _fault_last_clue := ""
var _workspace_protocol_layer: Node3D
var _workspace_protocol_groups: Dictionary = {}
var _workspace_protocol_sites: Dictionary = {}
var _workspace_protocol_visuals: Dictionary = {}
var _workspace_protocol_phase := ""
var _workspace_protocol_evidence: Dictionary = {}
var _workspace_protocol_choices: Dictionary = {}
var _workspace_protocol_execution_progress: Dictionary = {}
var _workspace_protocol_execution_history: Array = []
var _workspace_protocol_completed: Dictionary = {}
var _workspace_protocol_effects: Dictionary = {}
var _workspace_protocol_decisions := 0
var _workspace_protocol_started := false
var _workspace_protocol_complete := false
const HALLWAY_EXIT_CELL := Vector2i(8, 13)  # east edge of the real room, just inside the wall border

# Grid system
var _grid: GridWorld
var _renderer: GridRenderer
# The room model binding — ALL model lookups/floor/occupancy flow through this (see
# RoomModelBinder). The descriptor is the scene's single declaration of its modeled room.
var _room_binder := RoomModelBinder.new()

var _data_displays: Array[MeshInstance3D] = []

const PLACEMENT_ROOT := "ScenePlacement"
# The curated display wrapper (translucent glowing beads, runtime connector
# lines, looping idle) — NOT the raw gltf, which renders dark and inert.
const GLASS_BEAD_SCENE := preload("res://scenes/tutorial/glass_bead_game_display.tscn")

# Start below max ATP so the drink refill is visible.
const ATP_START := 6.0
const ATP_MAX := GameState.ATP_MAX_PIPS

# --- Virtual overrides ---

func _build_scene() -> void:
	_apply_high_res_room_visibility()
	_build_environment()
	_build_terminal()
	_build_drink_machine()

func _build_characters() -> void:
	var in_game := not Engine.is_editor_hint()

	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)

	_player = _create_player_character("Aster", Color(0.29, 0.62, 1.0))
	_player.position = _placement_or_grid("AsterStart", Vector2i(4, 10), 0.5)
	if in_game:
		_player.grid_world = _grid
	chars.add_child(_player)
	# Characters read small in the long room — render them at double scale. Feet sit at the node
	# origin, so scaling about it keeps them grounded; the top_level path/marker overlays are unaffected.
	_player.scale = Vector3(2, 2, 2)

	_ron = _create_npc("Ron", Color(0.7, 0.6, 0.45))
	_ron.display_name = "RON"
	_ron.position = _ron_warp_spawn()
	if in_game:
		_ron.grid_world = _grid
	chars.add_child(_ron)
	_ron.scale = Vector3(2, 2, 2)
	if in_game:
		_ron.hide_for_warp()  # unformed until the portal fires (see _start_ron_warp_in)

	if in_game:
		# Camera west of the room looking east: the 14-unit-long room lays out
		# across the screen with the scene reading the right way around (the east
		# vantage showed everything mirrored — flipped 180).
		# Full look-around (pan + rotate + zoom), but CLAMPED to the room so pan/edge-scroll can never
		# drift the view off the level (the bound is derived from the grid extent).
		_setup_game_camera(_player, Vector3(-6.5, 8, 0), true)
		_bind_camera_to_level_bounds(_grid, 1.5)

func _register_characters() -> void:
	_game_state.grid = _grid
	_register_gs_character("aster", _player, _player.move_speed, {"atp": ATP_START})
	_register_gs_character("ron", _ron, _ron.move_speed)

func _setup_ui() -> void:
	# Only the ATP bar is active in this tutorial beat.
	_hud = preload("res://scenes/ui/game_hud.tscn").instantiate()
	add_child(_hud)
	_hud.add_stat_bar("atp", Color(0.3, 0.7, 0.4), ATP_MAX, ATP_START)
	_hud.bind_game_state(_game_state, "aster")

func _begin() -> void:
	_add_screen_effect("ChromaticAberration", preload("res://resources/chromatic_aberration.gdshader"))
	_enable_outline_preview()
	_connect_outline_feedback_sources(self)
	_apply_model_occupancy_to_grid()
	if OS.get_environment("ASTER_GRID_PROBE") == "1":
		_probe_model_vs_grid()
	if OS.get_environment("ASTER_Y_PROBE") == "1":
		for i in range(8):
			_ui_scheduler.schedule_after(0.05 * (i + 1), func():
				print("[YPROBE] aster_node=%.3f ron_node=%.3f gs_aster=%.3f grid_y=%.3f" % [
					_player.global_position.y, _ron.global_position.y,
					_game_state.get_position("aster").y, _grid.origin.y]), "yprobe")
	_start_fade_in()

func _apply_model_occupancy_to_grid() -> void:
	_room_binder.apply_occupancy()

## Diagnostic: where each model object sits vs what the grid thinks of those cells.
func _probe_model_vs_grid() -> void:
	for obj_name in ["Desk", "Shelf", "drink_machine", "glass_bead_game", "Rug", "Grate"]:
		var ab := _room_object_aabb(obj_name)
		if ab.size == Vector3.ZERO:
			print("[GRIDPROBE] %s: ABSENT" % obj_name)
			continue
		var a := _grid.world_to_grid(ab.position)
		var b := _grid.world_to_grid(ab.position + ab.size)
		var n_cells := 0
		var blocked := 0
		for cz in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			for cx in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
				n_cells += 1
				if not _grid.is_walkable(cx, cz):
					blocked += 1
		print("[GRIDPROBE] %-16s center=%s cells=%d blocked=%d (%s..%s)" % [obj_name, str(ab.get_center()), n_cells, blocked, str(a), str(b)])

func _enable_outline_preview() -> void:
	# The textured room is ALWAYS the visible environment now (its materials carry the authored
	# emissive/normal layers). The outline post-process toggle only governs the extra edge pass —
	# it must never hide the room (it used to, leaving the sim starting in a black void of
	# perception wireframes).
	_set_imported_outline_preview_enabled(OUTLINE_POST_PROCESS_ENABLED)
	if find_child("AsterSimRoomOutlinePreview", true, false) != null:
		_perception_mode = "outline"
		return
	_setup_perception("outline", _player)

func _set_imported_outline_preview_enabled(enabled: bool) -> void:
	for preview in find_children("AsterSimRoomOutlinePreview", "MeshInstance3D", true, false):
		if preview is MeshInstance3D:
			(preview as MeshInstance3D).visible = enabled

func _on_process(_delta: float, _spd: float) -> void:
	# GameHud handles ATP updates.
	_update_fades()
	_update_show_terminal()

	for i in range(_data_displays.size()):
		var d := _data_displays[i]
		d.position.y = 1.8 + sin(Time.get_ticks_msec() * 0.001 + i * 1.5) * 0.08  # @rendering_only: data display bobbing
		d.rotation.y += _delta * 0.15

func headless_get_state() -> Dictionary:
	var state := super.headless_get_state()
	var fault_case := _current_fault_case()
	state["explore_gate_unlocked"] = _explore_gate_unlocked
	state["workspace_thread_counts"] = _workspace_thread_counts.duplicate(true)
	state["workspace_thread_required"] = WORKSPACE_THREAD_REQUIRED.duplicate(true)
	state["workspace_zone_counts"] = _workspace_zone_counts.duplicate(true)
	state["workspace_threads_complete"] = _workspace_completed_thread_count()
	state["workspace_thread_total"] = WORKSPACE_THREAD_REQUIRED.size()
	state["workspace_review_complete"] = _workspace_review_complete()
	state["fault_review_started"] = _fault_circuit_started
	state["fault_review_complete"] = _fault_circuit_complete
	state["fault_case_index"] = _fault_case_index
	state["fault_case_number"] = _fault_case_index + 1 if not fault_case.is_empty() else 0
	state["fault_case_total"] = FAULT_REVIEW_CASES.size()
	state["fault_case_id"] = str(fault_case.get("id", ""))
	state["fault_evidence_collected"] = _fault_case_evidence.keys()
	state["fault_evidence_required"] = (fault_case.get("evidence", []) as Array).duplicate()
	state["fault_commit_candidates"] = (fault_case.get("candidates", []) as Array).duplicate()
	state["fault_selected_candidate"] = _fault_selected_candidate
	state["fault_correct_commits"] = _fault_correct_commits
	state["fault_wrong_commits"] = _fault_wrong_commits
	state["fault_wrong_atp_spent"] = _fault_wrong_atp_spent
	state["fault_wrong_atp_cost_cap"] = FAULT_WRONG_ATP_COST * FAULT_REVIEW_CASES.size()
	state["fault_drink_recoveries"] = _fault_drink_recoveries
	state["fault_terminal_pending"] = _fault_terminal_pending
	state["fault_evidence_review_counts"] = _fault_evidence_review_counts.duplicate(true)
	state["fault_commit_history"] = _fault_commit_history.duplicate(true)
	state["fault_last_clue"] = _fault_last_clue
	state["workspace_protocol_started"] = _workspace_protocol_started
	state["workspace_protocol_complete"] = _workspace_protocol_complete
	state["workspace_protocol_phase"] = _workspace_protocol_phase
	state["workspace_protocol_evidence"] = _workspace_protocol_evidence.duplicate(true)
	state["workspace_protocol_choices"] = _workspace_protocol_choices.duplicate(true)
	state["workspace_protocol_execution_progress"] = _workspace_protocol_execution_progress.duplicate(true)
	state["workspace_protocol_execution_history"] = _workspace_protocol_execution_history.duplicate(true)
	state["workspace_protocol_completed"] = _workspace_protocol_completed.duplicate(true)
	state["workspace_protocol_effects"] = _workspace_protocol_effects.duplicate(true)
	state["workspace_protocol_decision_count"] = _workspace_protocol_decisions
	state["aster_atp"] = _game_state.get_stat("aster", "atp") if _game_state != null else 0.0
	return state

func get_playtime_contract() -> Dictionary:
	var evidence_review_count := 0
	for raw_case in FAULT_REVIEW_CASES:
		var case_data: Dictionary = raw_case
		evidence_review_count += (case_data.get("evidence", []) as Array).size()
	var move_speed := maxf(float(_player.move_speed) if _player != null else ASTER_ROUTE_SPEED_FALLBACK, 0.1)
	var mandatory_recoveries := maxi(
		0,
		int(ceil((FAULT_COMMIT_ATP_COST * FAULT_REVIEW_CASES.size()) / float(ATP_MAX))) - 1
	)
	var opening_route_meters := _opening_route_meters()
	var workspace_fault_route_meters := _workspace_and_fault_minimum_route_meters()
	var protocol_route_meters := _workspace_protocol_minimum_route_meters()
	var traversal_seconds := (opening_route_meters + workspace_fault_route_meters + protocol_route_meters) / move_speed
	var workspace_observation_seconds := _workspace_required_beat_count() * WORKSPACE_OBSERVATION_SECONDS_PER_BEAT
	var fault_work_seconds := evidence_review_count * FAULT_EVIDENCE_WORK_SECONDS \
		+ mandatory_recoveries * FAULT_DRINK_RECOVERY_SECONDS
	var opening_and_handoff_work_seconds := 2.0 * FAULT_DRINK_RECOVERY_SECONDS
	var protocol_work_seconds := _workspace_protocol_shortest_work_seconds()
	var planning_seconds := workspace_observation_seconds \
		+ FAULT_REVIEW_CASES.size() * FAULT_SYNTHESIS_SECONDS_PER_CASE \
		+ WORKSPACE_PROTOCOL_ORDER.size() * PROTOCOL_SYNTHESIS_SECONDS_PER_OPERATION
	var evidence_and_diagnosis_seconds := fault_work_seconds + opening_and_handoff_work_seconds
	var meaningful_active_seconds := traversal_seconds + planning_seconds \
		+ evidence_and_diagnosis_seconds + protocol_work_seconds
	var total_play_seconds := meaningful_active_seconds + ASTER_INACTIVE_PRESENTATION_SECONDS
	var fault_review_seconds := _fault_minimum_route_meters() / move_speed \
		+ fault_work_seconds + FAULT_REVIEW_CASES.size() * FAULT_SYNTHESIS_SECONDS_PER_CASE
	var decision_count := FAULT_REVIEW_CASES.size() + WORKSPACE_PROTOCOL_ORDER.size()
	var branch_count := 0
	for raw_case in FAULT_REVIEW_CASES:
		branch_count += ((raw_case as Dictionary).get("candidates", []) as Array).size()
	for protocol_id in WORKSPACE_PROTOCOL_ORDER:
		branch_count += (WORKSPACE_PROTOCOLS[str(protocol_id)].get("choices", []) as Array).size()
	return {
		"target_id": "aster_sim",
		"meaningful_active_seconds": meaningful_active_seconds,
		"total_play_seconds": total_play_seconds,
		"max_dead_gap_seconds": 3.0,
		"max_single_mode_seconds": 42.0,
		"decision_count": decision_count,
		"branch_count": branch_count,
		"category_seconds": {
			"exploration_and_traversal": traversal_seconds,
			"evidence_and_diagnosis": evidence_and_diagnosis_seconds,
			"protocol_execution": protocol_work_seconds,
			"planning_and_decisions": planning_seconds,
		},
		"required_first_clear_seconds": 300.0,
		"target_min_seconds": 300.0,
		"target_max_seconds": 480.0,
		"modeled_first_clear_seconds": total_play_seconds,
		"meaningful_active_ratio": meaningful_active_seconds / total_play_seconds,
		"inactive_presentation_seconds": ASTER_INACTIVE_PRESENTATION_SECONDS,
		"modeled_fault_review_seconds": fault_review_seconds,
		"fault_review_station_work_seconds": fault_work_seconds,
		"minimum_fault_route_meters": _fault_minimum_route_meters(),
		"opening_route_meters": opening_route_meters,
		"workspace_and_fault_route_meters": workspace_fault_route_meters,
		"workspace_protocol_route_meters": protocol_route_meters,
		"total_measured_route_meters": opening_route_meters + workspace_fault_route_meters + protocol_route_meters,
		"movement_speed_meters_per_second": move_speed,
		"mandatory_evidence_reviews": evidence_review_count,
		"evidence_work_seconds_each": FAULT_EVIDENCE_WORK_SECONDS,
		"mandatory_terminal_commits": FAULT_REVIEW_CASES.size(),
		"commit_atp_cost_each": FAULT_COMMIT_ATP_COST,
		"wrong_commit_atp_cost_each": FAULT_WRONG_ATP_COST,
		"wrong_commit_atp_cost_cap": FAULT_WRONG_ATP_COST * FAULT_REVIEW_CASES.size(),
		"mandatory_drink_recoveries": mandatory_recoveries,
		"workspace_observation_beat_count": _workspace_required_beat_count(),
		"mandatory_protocol_count": WORKSPACE_PROTOCOL_ORDER.size(),
		"mandatory_protocol_evidence_count": _workspace_protocol_evidence_count(),
		"mandatory_protocol_action_count": _workspace_protocol_shortest_action_count(),
		"protocol_site_count": WORKSPACE_PROTOCOL_SITES.size(),
		"workspace_protocol_work_seconds": protocol_work_seconds,
		"hard_idle_lock_seconds": 0.0,
		"mode_segments": {
			"longest_story_exchange": 42.0,
			"fault_evidence_work": FAULT_EVIDENCE_WORK_SECONDS,
			"longest_protocol_station": 6.0,
			"fault_case_synthesis": FAULT_SYNTHESIS_SECONDS_PER_CASE,
			"protocol_synthesis": PROTOCOL_SYNTHESIS_SECONDS_PER_OPERATION,
		},
		"timing_basis": "exact shortest geometry from Aster's start through terminal, drink approach, all four workspace threads, three preserved fault cases, three distinct spatial protocols, and hallway; only authored timed work plus explicit observation/synthesis is active; dialogue, focus shots, fades, and idle are excluded from the active floor",
	}

func _workspace_required_beat_count() -> int:
	var count := 0
	for required in WORKSPACE_THREAD_REQUIRED.values():
		count += int(required)
	return count

func _workspace_protocol_evidence_count() -> int:
	var count := 0
	for protocol_id in WORKSPACE_PROTOCOL_ORDER:
		count += (WORKSPACE_PROTOCOLS[str(protocol_id)].get("evidence", []) as Array).size()
	return count

func _workspace_protocol_shortest_action_count() -> int:
	var count := 0
	for protocol_id_variant in WORKSPACE_PROTOCOL_ORDER:
		var protocol: Dictionary = WORKSPACE_PROTOCOLS[str(protocol_id_variant)]
		count += (protocol.get("evidence", []) as Array).size() + 1
		var shortest_execution := 1000000
		for choice_id_variant in protocol.get("choices", []):
			var execution: Array = (protocol.get("execution_sites", {}) as Dictionary).get(str(choice_id_variant), [])
			shortest_execution = mini(shortest_execution, execution.size())
		count += 0 if shortest_execution == 1000000 else shortest_execution
	return count

func _workspace_protocol_shortest_work_seconds() -> float:
	var total := 0.0
	for protocol_id_variant in WORKSPACE_PROTOCOL_ORDER:
		var protocol: Dictionary = WORKSPACE_PROTOCOLS[str(protocol_id_variant)]
		for evidence_id_variant in protocol.get("evidence", []):
			total += float(WORKSPACE_PROTOCOL_SITES[str(evidence_id_variant)].get("dwell", 0.0))
		var shortest_branch := INF
		for choice_id_variant in protocol.get("choices", []):
			var choice_id := str(choice_id_variant)
			var branch_work := float(WORKSPACE_PROTOCOL_SITES[choice_id].get("dwell", 0.0))
			for execution_id_variant in (protocol.get("execution_sites", {}) as Dictionary).get(choice_id, []):
				branch_work += float(WORKSPACE_PROTOCOL_SITES[str(execution_id_variant)].get("dwell", 0.0))
			shortest_branch = minf(shortest_branch, branch_work)
		total += 0.0 if is_inf(shortest_branch) else shortest_branch
	return total

func _opening_route_meters() -> float:
	var start := _contract_marker_position("AsterStart", Vector3(4.5, 0.0, 11.5))
	var terminal := _fault_terminal_contract_position()
	var drink_approach := _contract_marker_position("DrinkMachineApproach", Vector3(7.0, 0.0, 3.08))
	return _horizontal_distance(start, terminal) + _horizontal_distance(terminal, drink_approach)

func _workspace_and_fault_minimum_route_meters() -> float:
	var survey_ids := ["glass", "painting_teal", "awards", "jstore"]
	var survey_positions: Array[Vector3] = []
	for evidence_id in survey_ids:
		survey_positions.append(_fault_evidence_contract_position(str(evidence_id)))
	var start := _contract_marker_position("DrinkMachineApproach", Vector3(7.0, 0.0, 3.08))
	var terminal := _fault_terminal_contract_position()
	var first_case: Dictionary = FAULT_REVIEW_CASES[0]
	var first_ids: Array = first_case.get("evidence", [])
	var best := INF
	for survey_order_variant in _index_permutations(survey_positions.size()):
		var survey_order: Array = survey_order_variant
		var previous := start
		var distance := 0.0
		for raw_index in survey_order:
			var next: Vector3 = survey_positions[int(raw_index)]
			distance += _horizontal_distance(previous, next)
			previous = next
		for fault_order_variant in _index_permutations(first_ids.size()):
			var fault_order: Array = fault_order_variant
			var ordered_ids: Array[String] = []
			for raw_index in fault_order:
				ordered_ids.append(str(first_ids[int(raw_index)]))
			if not _fault_order_stages_correct(first_case, ordered_ids):
				continue
			var fault_distance := distance
			var fault_previous := previous
			for evidence_id in ordered_ids:
				var next := _fault_evidence_contract_position(evidence_id)
				fault_distance += _horizontal_distance(fault_previous, next)
				fault_previous = next
			fault_distance += _horizontal_distance(fault_previous, terminal)
			best = minf(best, fault_distance)
	var total := 0.0 if is_inf(best) else best
	for case_index in range(1, FAULT_REVIEW_CASES.size()):
		total += _fault_case_minimum_route_from(FAULT_REVIEW_CASES[case_index], terminal)
	return total

func _fault_minimum_route_meters() -> float:
	var total := 0.0
	for raw_case in FAULT_REVIEW_CASES:
		total += _fault_case_minimum_route_meters(raw_case as Dictionary)
	return total

func _fault_case_minimum_route_meters(case_data: Dictionary) -> float:
	return _fault_case_minimum_route_from(case_data, _fault_terminal_contract_position())

func _fault_case_minimum_route_from(case_data: Dictionary, start_position: Vector3) -> float:
	var ids: Array = case_data.get("evidence", [])
	if ids.is_empty():
		return 0.0
	var terminal_position := _fault_terminal_contract_position()
	var best := INF
	for permutation_variant in _index_permutations(ids.size()):
		var permutation: Array = permutation_variant
		var order: Array[String] = []
		for raw_index in permutation:
			order.append(str(ids[int(raw_index)]))
		if not _fault_order_stages_correct(case_data, order):
			continue
		var distance := 0.0
		var previous := start_position
		for evidence_id in order:
			var next := _fault_evidence_contract_position(str(evidence_id))
			distance += _horizontal_distance(previous, next)
			previous = next
		distance += _horizontal_distance(previous, terminal_position)
		best = minf(best, distance)
	return 0.0 if best == INF else best

func _fault_order_stages_correct(case_data: Dictionary, order: Array[String]) -> bool:
	var correct := str(case_data.get("correct", ""))
	var other_candidate := ""
	for candidate in (case_data.get("candidates", []) as Array):
		if str(candidate) != correct:
			other_candidate = str(candidate)
			break
	return other_candidate == "" or order.find(correct) > order.find(other_candidate)

func _workspace_protocol_minimum_route_meters() -> float:
	var states: Array = [{"position": _fault_terminal_contract_position(), "distance": 0.0}]
	for protocol_id_variant in WORKSPACE_PROTOCOL_ORDER:
		var protocol_id := str(protocol_id_variant)
		var protocol: Dictionary = WORKSPACE_PROTOCOLS[protocol_id]
		var next_states: Array = []
		for state_variant in states:
			var state: Dictionary = state_variant
			for choice_id_variant in protocol.get("choices", []):
				var route := _workspace_protocol_choice_route(
					protocol_id, state.get("position", Vector3.ZERO), str(choice_id_variant)
				)
				next_states.append({
					"position": route.get("end_position", state.get("position", Vector3.ZERO)),
					"distance": float(state.get("distance", 0.0)) + float(route.get("distance", 0.0)),
				})
		states = next_states
	var hallway := _contract_marker_position("HallwayExit", Vector3(8.4, 0.0, 13.5))
	var best := INF
	for state_variant in states:
		var state: Dictionary = state_variant
		best = minf(best, float(state.get("distance", 0.0))
			+ _horizontal_distance(state.get("position", Vector3.ZERO), hallway))
	return 0.0 if is_inf(best) else best

func _workspace_protocol_choice_route(protocol_id: String, start_position: Vector3, choice_id: String) -> Dictionary:
	var protocol: Dictionary = WORKSPACE_PROTOCOLS[protocol_id]
	var evidence_ids: Array = protocol.get("evidence", [])
	var choice_position := _workspace_protocol_site_position(choice_id)
	var distance := 0.0
	var previous := start_position
	if bool(protocol.get("ordered_evidence", false)):
		for evidence_id_variant in evidence_ids:
			var next := _workspace_protocol_site_position(str(evidence_id_variant))
			distance += _horizontal_distance(previous, next)
			previous = next
		distance += _horizontal_distance(previous, choice_position)
	else:
		distance += _shortest_protocol_evidence_route(previous, evidence_ids, choice_position)
	previous = choice_position
	for execution_id_variant in (protocol.get("execution_sites", {}) as Dictionary).get(choice_id, []):
		var next := _workspace_protocol_site_position(str(execution_id_variant))
		distance += _horizontal_distance(previous, next)
		previous = next
	return {"distance": distance, "end_position": previous}

func _shortest_protocol_evidence_route(start_position: Vector3, evidence_ids: Array, end_position: Vector3) -> float:
	if evidence_ids.is_empty():
		return _horizontal_distance(start_position, end_position)
	var best := INF
	for order_variant in _index_permutations(evidence_ids.size()):
		var order: Array = order_variant
		var previous := start_position
		var distance := 0.0
		for raw_index in order:
			var next := _workspace_protocol_site_position(str(evidence_ids[int(raw_index)]))
			distance += _horizontal_distance(previous, next)
			previous = next
		distance += _horizontal_distance(previous, end_position)
		best = minf(best, distance)
	return 0.0 if is_inf(best) else best

func _index_permutations(count: int) -> Array:
	var remaining: Array[int] = []
	for index in range(count):
		remaining.append(index)
	var out: Array = []
	_append_index_permutations([], remaining, out)
	return out

func _append_index_permutations(prefix: Array, remaining: Array[int], out: Array) -> void:
	if remaining.is_empty():
		out.append(prefix.duplicate())
		return
	for index in range(remaining.size()):
		var next_prefix := prefix.duplicate()
		next_prefix.append(remaining[index])
		var next_remaining := remaining.duplicate()
		next_remaining.remove_at(index)
		_append_index_permutations(next_prefix, next_remaining, out)

func _fault_terminal_contract_position() -> Vector3:
	if _terminal != null and is_instance_valid(_terminal):
		return _terminal.global_position
	var marker := _placement_node("TerminalInteract")
	return marker.global_position if marker != null else Vector3(6.4, 0.0, 7.75)

func _fault_evidence_contract_position(evidence_id: String) -> Vector3:
	var live = _fault_evidence_interactables.get(evidence_id)
	if live is Node3D and is_instance_valid(live):
		return (live as Node3D).global_position
	var config: Dictionary = FAULT_EVIDENCE_SOURCES.get(evidence_id, {})
	var source := find_child(str(config.get("zone", "")), true, false) as Node3D
	if source != null:
		return source.global_position
	var marker := _placement_node(str(config.get("marker", "")))
	return marker.global_position if marker != null else Vector3.ZERO

func _workspace_protocol_site_position(site_id: String) -> Vector3:
	var live = _workspace_protocol_sites.get(site_id)
	if live is Node3D and is_instance_valid(live):
		return (live as Node3D).global_position
	return WORKSPACE_PROTOCOL_SITES.get(site_id, {}).get("pos", Vector3.ZERO)

func _contract_marker_position(marker_name: String, fallback: Vector3) -> Vector3:
	var marker := _placement_node(marker_name)
	return marker.global_position if marker != null else fallback

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _get_speed_recipients() -> Array:
	var recipients := []
	if _terminal:
		recipients.append(_terminal)
	if _drink_machine:
		recipients.append(_drink_machine)
	return recipients

## The imported room model is the environment (the graybox is a fallback for headless/dev toggles).
## STRUCTURAL, not visual: the model's geometry drives props/occupancy/anchors even when a render
## toggle (outline post-process fallback) hides it — headless runs exercise the same data layer.
func _use_room_model() -> bool:
	return not show_graybox_room and _room_binder.active()


## All MeshInstance3Ds under the named object(s) of the room model. Multiple nodes can share a name
## (the composed export has eight "j-store" journals, two "Award N" plaques) — gather every match.
func _room_model_meshes(object_name: String) -> Array:
	return _room_binder.object_meshes([object_name])


func _room_model_meshes_multi(object_names: Array) -> Array:
	return _room_binder.object_meshes(object_names)

func _model_prop(object_names: Array) -> Dictionary:
	if show_graybox_room:
		return {}
	return _room_binder.prop(object_names)

func _room_object_aabb(object_name: String) -> AABB:
	return _room_binder.object_aabb(object_name)

func _room_object_placed(object_name: String) -> bool:
	return _room_binder.object_placed(object_name)

func _model_or_marker(object_name: String, marker_name: String, fallback_position: Vector3) -> Vector3:
	if show_graybox_room:
		return _placement_or_position(marker_name, fallback_position)
	return _room_binder.anchor(object_name, _placement_node(marker_name), fallback_position)

func _placement_node(marker_name: String) -> Node3D:
	var root := get_node_or_null(PLACEMENT_ROOT)
	if root == null:
		return null
	return root.find_child(marker_name, true, false) as Node3D

func _placement_or_position(marker_name: String, fallback_position: Vector3) -> Vector3:
	var marker := _placement_node(marker_name)
	return marker.global_position if marker != null else fallback_position

func _placement_or_grid(marker_name: String, fallback_cell: Vector2i, y: float = 0.0) -> Vector3:
	var fallback := _grid.grid_to_world(fallback_cell)
	fallback.y = y
	return _placement_or_position(marker_name, fallback)

## Ron's authored warp-in spot: the RonStartMarker placed under the room model, resolved through the
## shared spawn helper (snaps off the wall border onto a walkable, grounded cell). Falls back to the
## old RonStart marker / grid cell if it's missing.
func _ron_warp_spawn() -> Vector3:
	return _spawn_at_marker(_grid, "RonStartMarker", _placement_or_grid("RonStart", Vector2i(3, 12), _grid.origin.y))

func _local_for_parent(parent: Node3D, world_pos: Vector3) -> Vector3:
	return parent.to_local(world_pos) if parent != null else world_pos

func _apply_high_res_room_visibility() -> void:
	var high_res_scene := find_child("AsterRoom", true, false) as Node3D
	if high_res_scene != null:
		high_res_scene.visible = show_high_res_room
		var high_res_room := high_res_scene.find_child("default", true, false) as Node3D
		if high_res_room != null:
			high_res_room.visible = show_high_res_room
		for light in high_res_scene.find_children("*", "Light3D", true, false):
			if light is Light3D:
				(light as Light3D).visible = show_high_res_room
	else:
		var high_res_room := find_child("default", true, false) as Node3D
		if high_res_room != null:
			high_res_room.visible = show_high_res_room
		var high_res_spot := find_child("SpotLight3D", true, false) as Light3D
		if high_res_spot != null:
			high_res_spot.visible = show_high_res_room

func _create_graybox_outline_target(
		parent: Node3D,
		target_name: String,
		center: Vector3,
		size: Vector3,
		meshes: Array,
		element_id: String,
		radius: float = 1.0
	) -> Node3D:
	# Thin wrapper over the shared base helper, kept for the existing call sites.
	return _create_outline_target(parent, target_name, center, size, meshes, element_id, radius)

# --- Per-frame visual helpers ---

func _update_fades() -> void:
	if _current_step == "fade_in":
		_update_fade_in(2.0)
	elif _current_step == "transition_out":
		_update_fade_out(Color(0.05, 0.03, 0.01), 2.0)

func _update_show_terminal() -> void:
	if _current_step == "show_terminal" and not _has_moved and _player.is_moving():
		_has_moved = true
		_terminal.hide_tutorial_label()

# --- Event-driven steps ---

func _start_fade_in() -> void:
	_current_step = "fade_in"
	_player.set_move_enabled(false)
	_fade_from(Color(0, 0, 0, 1), 2.5, _start_working, "working")

func _start_working() -> void:
	_current_step = "working"
	# Brief settle after the fade, then Ron warps in (no long dead-air idle).
	_scheduler.schedule_after(0.5, _start_ron_warp_in, "ron_warp_in")

func _start_ron_warp_in() -> void:
	_current_step = "ron_warp_in"
	# Ron arrives through a portal: a cosmetic flash at his marker + his body materializing. The
	# logical hand-off to the approach rides the scheduler (a tween never gates a step).
	if _ron != null:
		var portal := WarpPortal.new()
		add_child(portal)
		portal.global_position = Vector3(_ron.global_position.x, _grid.origin.y, _ron.global_position.z)
		portal.play(WarpPortal.GREEN, 1.4)
		if _ron.has_method("warp_in"):
			_ron.warp_in(1.3)
	_scheduler.schedule_after(1.3, _start_ron_approaches, "ron_approaches")

func _start_ron_approaches() -> void:
	_current_step = "ron_approaches"
	_hide_thought()
	_ron.walk_to(_player.global_position + Vector3(1.5, 0, 0.5))
	_scheduler.schedule_after(3.0, _start_ron_greeting, "ron_greeting")

func _start_ron_greeting() -> void:
	_current_step = "ron_greeting"
	_ron.stop()
	DialogueData.say_to(_dialogue, "aster_sim.ron.greeting")
	DialogueData.say_to(_dialogue, "aster_sim.ron.name")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_show_terminal, "show_terminal"),
		CONNECT_ONE_SHOT
	)

func _start_show_terminal() -> void:
	_current_step = "show_terminal"
	# The TerminalInteract marker sits in FRONT of the monitor (the chair side), so the interaction walks
	# Aster there to read it face-on instead of standing at the side of the desk.
	if _terminal and _terminal.has_method("set_interaction_enabled"):
		_terminal.set_interaction_enabled(true)
	_terminal.show_tutorial_label()
	_player.set_move_enabled(true)
	# Terminal interaction triggers _on_terminal_interacted (signal-driven)

func _on_terminal_interacted() -> void:
	if _terminal_focus_active:
		return  # already showing the screen; ignore re-clicks mid-focus
	if _current_step == "fault_review":
		_on_fault_terminal_interacted()
	elif _current_step == "show_terminal":
		_scheduler.cancel_tag("drink_redirect")
		# The controller already walked Aster to the reading spot (queued glow on the desk in his colour
		# while en route); the FIRST read drives the tutorial forward.
		_start_terminal_focus()
	else:
		# Later reads just re-show the screen — the monitor stays readable, but the tutorial doesn't move.
		_replay_terminal_focus()

# Aster has reached the terminal's reading spot → frame the screen from the FRONT, swap in the detailed
# readout, hold a beat, then continue. Scheduler-driven so it runs headless and respects F.
func _start_terminal_focus() -> void:
	_current_step = "terminal_focus"
	_player.set_move_enabled(false)
	_begin_terminal_screen_focus()
	_scheduler.schedule_after(TERMINAL_FOCUS_DURATION, _end_terminal_focus, "terminal_focus")

func _end_terminal_focus() -> void:
	_end_terminal_screen_focus()
	_player.set_move_enabled(true)
	_rearm_interactable(_terminal)  # the monitor stays re-readable after the first time
	_start_terminal_data()

## Re-read the monitor after the tutorial has moved past it: same screen + framing, but no step change
## and no progression — purely a look.
func _replay_terminal_focus() -> void:
	_player.set_move_enabled(false)
	_begin_terminal_screen_focus()
	_scheduler.schedule_after(TERMINAL_FOCUS_DURATION, _end_terminal_reread, "terminal_reread")

func _end_terminal_reread() -> void:
	_end_terminal_screen_focus()
	_player.set_move_enabled(true)
	_rearm_interactable(_terminal)

## Re-arm a one-shot interactable so it can be used again (its trigger disabled it). Safe for a
## HOLD_ACTION too: the dwell only re-fires on a fresh body-enter, so re-arming while the character is
## still standing in range does not immediately re-trigger.
func _rearm_interactable(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_method("reset"):
		node.reset()
	if node.has_method("set_interaction_enabled"):
		node.set_interaction_enabled(true)

## The horizontal unit direction the desk monitor FACES — toward the chair, where someone sits to read
## it. Measured from the actual chair node so the framing matches the modeled desk instead of an assumed
## axis (the monitor faces +X here, not +Z). Falls back to +X if the chair can't be found.
func _screen_facing() -> Vector3:
	var chair := find_child("*hair*", true, false) as Node3D
	if chair != null:
		var f: Vector3 = chair.global_position - _terminal_screen_world
		f.y = 0.0
		if f.length() > 0.05:
			return f.normalized()
	return Vector3(1, 0, 0)

func _begin_terminal_screen_focus() -> void:
	_terminal_focus_active = true
	if _terminal_screen_lowfi != null:
		_terminal_screen_lowfi.visible = false
	var facing := _screen_facing()
	if _terminal_screen_detail != null:
		_terminal_screen_detail.visible = true
		# Turn the readable panel to face the chair (the real monitor's front) so the camera reads it flat.
		_terminal_screen_detail.rotation.y = atan2(facing.x, facing.z)
	# Hide Aster's floating nameplate so it doesn't dominate the tight screen shot.
	var label = _player.get_node_or_null("Label3D") if _player != null else null
	if label != null:
		label.visible = false
	if _camera != null:
		_terminal_prev_camera_target = _camera.target
		# Sit the camera back along the monitor's facing (on the chair side) and a little up, looking at
		# the screen head-on — parallel to the display, not edge-on. Fixed override so it ignores whatever
		# gameplay angle the player left the camera at.
		var off := facing * TERMINAL_FOCUS_BACK + Vector3(0.0, TERMINAL_FOCUS_RISE, 0.0)
		_camera.lock_to(_terminal_screen_world, off)

func _end_terminal_screen_focus() -> void:
	_terminal_focus_active = false
	if _terminal_screen_detail != null:
		_terminal_screen_detail.visible = false
	if _terminal_screen_lowfi != null:
		_terminal_screen_lowfi.visible = true
	var label = _player.get_node_or_null("Label3D") if _player != null else null
	if label != null:
		label.visible = true
	if _camera != null:
		_camera.target = _terminal_prev_camera_target
		_camera.unlock()

func _start_terminal_data() -> void:
	_current_step = "terminal_data"
	# Brief beat for the screen-focus camera to settle back before Ron pipes up.
	_scheduler.schedule_after(0.4, _start_ron_drinks, "ron_drinks")

func _start_ron_drinks() -> void:
	_current_step = "ron_drinks"
	# Ron points out the drink machine BEFORE the prompt appears, so grabbing a drink reads as a
	# response to him rather than coming out of nowhere. The prompt opens as he finishes the line.
	DialogueData.say_to(_dialogue, "aster_sim.ron.drinks")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_walk_to_drink, "walk_to_drink"),
		CONNECT_ONE_SHOT
	)

func _start_walk_to_drink() -> void:
	_current_step = "walk_to_drink"
	if _drink_machine and _drink_machine.has_method("set_interaction_enabled"):
		_drink_machine.set_interaction_enabled(true)
	_drink_machine.show_tutorial_label()
	# Hint if the player skips the drink too long.
	_scheduler.schedule_after(8.0, _show_drink_redirect, "drink_redirect")

func _show_drink_redirect() -> void:
	if not _has_drunk and _current_step == "walk_to_drink":
		_show_thought(DialogueData.text("aster_sim.drink_redirect.thought"))

func _on_drink_interacted() -> void:
	if _current_step == "fault_review" and _fault_circuit_started and not _fault_circuit_complete:
		_recover_fault_review_atp()
	elif not _has_drunk and _current_step == "walk_to_drink":
		# First drink: the ATP tutorial.
		_has_drunk = true
		_scheduler.cancel_tag("drink_redirect")
		_start_drink()
	elif _has_drunk:
		# Already topped up — Aster waves it off, with a glance toward Tag Day.
		_show_thought(DialogueData.text("aster_sim.drink_again.thought"))
		_rearm_interactable(_drink_machine)

func _start_drink() -> void:
	_current_step = "drink"
	_game_state.set_stat("aster", "atp", ATP_MAX)
	_hide_thought()
	_rearm_interactable(_drink_machine)  # stays usable; a second go gives the "all good on drinks" line
	_scheduler.schedule_after(2.0, _start_ron_move_fast, "ron_move_fast")

func _start_ron_move_fast() -> void:
	_current_step = "ron_move_fast"
	var hallway_world := _grid.grid_to_world(HALLWAY_EXIT_CELL)
	if _ron and _ron.has_method("walk_to"):
		_ron.walk_to(_placement_or_position(
			"RonExitTarget",
			Vector3(hallway_world.x - 1.0, 0.0, hallway_world.z)
	))
	DialogueData.say_to(_dialogue, "aster_sim.ron.move_fast")
	_dialogue_chain([
		"aster_sim.ron.lighting",
		"aster_sim.aster.lighting",
		"aster_sim.ron.tag_day_jobs",
	], func(): _scheduler.schedule_after(0, _start_explore_workspace, "explore_workspace"))

func _start_explore_workspace() -> void:
	_current_step = "explore_workspace"
	# The room itself is the active beat: each thread reveals a different part of Aster's relationship
	# to work, status, and private pleasure. Time only drives a reminder; waiting can never open the exit.
	_reset_workspace_progress()
	_reset_fault_review_state()
	_build_exploration_objects()
	_build_workspace_protocols()
	_reset_workspace_protocol_state()
	_explore_gate_unlocked = false
	_explore_gate_fired = false
	if _tutorial_prompt != null and _tutorial_prompt.has_method("show_prompt"):
		_tutorial_prompt.show_prompt(
			"Look around Aster's workspace: game, paintings, awards, and J-stores.",
			5.0
		)
	_scheduler.schedule_after(EXPLORE_MIN_TIME, _show_workspace_progress_hint, "explore_progress_hint")

func _unlock_exploration_gate() -> void:
	# Compatibility seam for callers that used the old timer callback. The gate still obeys the
	# characterization contract; calling this method cannot bypass the four active-play threads.
	_maybe_unlock_exploration_gate()

func _maybe_unlock_exploration_gate() -> void:
	if _explore_gate_unlocked or not _workspace_review_complete():
		return
	if not _fault_circuit_started:
		_start_fault_review_circuit()
		return
	if not _fault_circuit_complete:
		return
	if not _workspace_protocol_started:
		_start_workspace_protocol_operation(str(WORKSPACE_PROTOCOL_ORDER[0]))
		return
	if not _workspace_protocol_complete:
		return
	_explore_gate_unlocked = true
	_scheduler.cancel_tag("explore_progress_hint")
	if _explore_hallway_gate and _explore_hallway_gate.has_method("show_tutorial_label"):
		_explore_hallway_gate.show_tutorial_label()
	if _tutorial_prompt != null and _tutorial_prompt.has_method("show_prompt"):
		_tutorial_prompt.show_prompt("Fault review complete. Continue to the hallway.", 3.0)

func _reset_workspace_progress() -> void:
	_workspace_thread_counts.clear()
	for thread_id in WORKSPACE_THREAD_REQUIRED:
		_workspace_thread_counts[thread_id] = 0
	_workspace_zone_counts.clear()

func _reset_fault_review_state() -> void:
	_fault_evidence_interactables.clear()
	_fault_case_evidence.clear()
	_fault_evidence_review_counts.clear()
	_fault_commit_history.clear()
	_fault_case_index = -1
	_fault_selected_candidate = ""
	_fault_correct_commits = 0
	_fault_wrong_commits = 0
	_fault_wrong_atp_spent = 0.0
	_fault_case_wrong_penalized = false
	_fault_drink_recoveries = 0
	_fault_terminal_pending = false
	_fault_circuit_started = false
	_fault_circuit_complete = false
	_fault_last_clue = ""

func _reset_workspace_protocol_state() -> void:
	_workspace_protocol_phase = ""
	_workspace_protocol_evidence.clear()
	_workspace_protocol_choices.clear()
	_workspace_protocol_execution_progress.clear()
	_workspace_protocol_execution_history.clear()
	_workspace_protocol_completed.clear()
	_workspace_protocol_effects.clear()
	_workspace_protocol_decisions = 0
	_workspace_protocol_started = false
	_workspace_protocol_complete = false
	if is_instance_valid(_workspace_protocol_layer):
		_workspace_protocol_layer.visible = false
	for group in _workspace_protocol_groups.values():
		if is_instance_valid(group):
			group.visible = false
	for site_id in _workspace_protocol_sites:
		_set_workspace_protocol_site_enabled(str(site_id), false)

func _register_workspace_zone(zone: Node, thread_id: String, contribution_limit: int) -> void:
	if zone == null or not zone.has_signal("interacted"):
		return
	var zone_id := str(zone.name)
	var callback := Callable(self, "_on_workspace_zone_interacted").bind(
		thread_id,
		zone_id,
		maxi(1, contribution_limit)
	)
	if not zone.is_connected("interacted", callback):
		zone.connect("interacted", callback)

func _on_workspace_zone_interacted(thread_id: String, zone_id: String, contribution_limit: int) -> void:
	if _current_step != "explore_workspace" or not WORKSPACE_THREAD_REQUIRED.has(thread_id):
		return
	var prior_zone_count := int(_workspace_zone_counts.get(zone_id, 0))
	if prior_zone_count >= contribution_limit:
		return
	_workspace_zone_counts[zone_id] = prior_zone_count + 1
	var required := int(WORKSPACE_THREAD_REQUIRED[thread_id])
	_workspace_thread_counts[thread_id] = mini(
		int(_workspace_thread_counts.get(thread_id, 0)) + 1,
		required
	)
	_maybe_unlock_exploration_gate()

func _workspace_completed_thread_count() -> int:
	var completed := 0
	for thread_id in WORKSPACE_THREAD_REQUIRED:
		if int(_workspace_thread_counts.get(thread_id, 0)) >= int(WORKSPACE_THREAD_REQUIRED[thread_id]):
			completed += 1
	return completed

func _workspace_review_complete() -> bool:
	return _workspace_completed_thread_count() == WORKSPACE_THREAD_REQUIRED.size()

func _show_workspace_progress_hint() -> void:
	if _current_step != "explore_workspace" or _explore_gate_unlocked:
		return
	var remaining: Array[String] = []
	for thread_id in WORKSPACE_THREAD_REQUIRED:
		if int(_workspace_thread_counts.get(thread_id, 0)) < int(WORKSPACE_THREAD_REQUIRED[thread_id]):
			remaining.append(_workspace_thread_label(str(thread_id)))
	if _tutorial_prompt != null and _tutorial_prompt.has_method("show_prompt"):
		_tutorial_prompt.show_prompt(
			"Workspace review %d/%d — still to inspect: %s." % [
				_workspace_completed_thread_count(),
				WORKSPACE_THREAD_REQUIRED.size(),
				", ".join(remaining),
			],
			6.0
		)

func _workspace_thread_label(thread_id: String) -> String:
	match thread_id:
		"glass":
			return "glass bead game"
		"paintings":
			return "paintings"
		"awards":
			return "awards"
		"jstore":
			return "J-stores"
		_:
			return thread_id

func _start_fault_review_circuit() -> void:
	if _fault_circuit_started:
		return
	_fault_circuit_started = true
	_fault_circuit_complete = false
	_fault_case_index = 0
	_current_step = "fault_review"
	_scheduler.cancel_tag("explore_progress_hint")
	_build_fault_review_interactables()
	_rearm_interactable(_terminal)
	_rearm_interactable(_drink_machine)
	_start_fault_case()

func _build_fault_review_interactables() -> void:
	if not _fault_evidence_interactables.is_empty():
		return
	for evidence_id in FAULT_EVIDENCE_SOURCES:
		var config: Dictionary = FAULT_EVIDENCE_SOURCES[evidence_id]
		var source := find_child(str(config.get("zone", "")), true, false) as Node3D
		if source == null:
			continue
		if source.has_method("set_interaction_enabled"):
			source.call("set_interaction_enabled", false)
		var parent := source.get_parent() as Node3D
		if parent == null:
			continue
		var evidence := _create_interactable(
			parent,
			source.position,
			str(config.get("node", "FaultEvidence")),
			float(source.get("interaction_radius")),
			FAULT_EVIDENCE_WORK_SECONDS,
			str(config.get("label", "REVIEW FAULT EVIDENCE")),
			false,
			Interactable.InteractableType.TIMED_ACTION
		)
		# Data registration represents click-gated actions as non-hold interactions; the view's
		# explicit TIMED_ACTION restores the scheduler-backed work ring after Aster arrives.
		evidence.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
		evidence.set("dwell_time", FAULT_EVIDENCE_WORK_SECONDS)
		evidence.set("one_shot", false)
		evidence.set("required_character", "aster")
		evidence.set("description", "Fault Evidence: %s" % _fault_evidence_label(str(evidence_id)))
		evidence.set_meta("fault_evidence_id", str(evidence_id))
		evidence.interacted.connect(_on_fault_evidence_reviewed.bind(str(evidence_id)))
		evidence.set_interaction_enabled(false)
		_fault_evidence_interactables[str(evidence_id)] = evidence
		var target := find_child(str(config.get("target", "")), true, false)
		_set_room_target_interaction_delegate(target, evidence)

	# The journalism approach shares the awards geometry. It keeps its original name and first line,
	# but yields picking to the one timed ledger trace during the fault circuit.
	var journalism_zone := find_child("AwardsJournalismZone", true, false)
	if journalism_zone != null and journalism_zone.has_method("set_interaction_enabled"):
		journalism_zone.call("set_interaction_enabled", false)

func _start_fault_case() -> void:
	var case_data := _current_fault_case()
	if case_data.is_empty():
		_complete_fault_review_circuit()
		return
	_fault_case_evidence.clear()
	_fault_selected_candidate = ""
	_fault_case_wrong_penalized = false
	_fault_last_clue = str(case_data.get("brief", ""))
	_set_fault_evidence_enabled(case_data.get("evidence", []) as Array)
	_rearm_interactable(_terminal)
	if _terminal != null and _terminal.has_method("hide_tutorial_label"):
		_terminal.hide_tutorial_label()
	_update_fault_terminal_readout()
	_show_fault_prompt(
		"%s\nReview %s. The last candidate traced is staged for the terminal." % [
			str(case_data.get("brief", "")),
			_fault_evidence_list_text(case_data.get("evidence", []) as Array),
		],
		8.0
	)

func _set_fault_evidence_enabled(required: Array) -> void:
	for evidence_id in _fault_evidence_interactables:
		var evidence = _fault_evidence_interactables[evidence_id]
		if evidence == null or not is_instance_valid(evidence):
			continue
		if required.has(str(evidence_id)):
			_rearm_interactable(evidence)
			if evidence.has_method("show_tutorial_label"):
				evidence.call_deferred("show_tutorial_label")
		else:
			evidence.set_interaction_enabled(false)

func _on_fault_evidence_reviewed(evidence_id: String) -> void:
	if _current_step != "fault_review" or _fault_circuit_complete or _fault_terminal_pending:
		return
	var case_data := _current_fault_case()
	var required: Array = case_data.get("evidence", [])
	if not required.has(evidence_id):
		return
	_fault_case_evidence[evidence_id] = true
	_fault_evidence_review_counts[evidence_id] = int(_fault_evidence_review_counts.get(evidence_id, 0)) + 1
	var candidates: Array = case_data.get("candidates", [])
	if candidates.has(evidence_id):
		_fault_selected_candidate = evidence_id
	var clues: Dictionary = case_data.get("clues", {})
	_fault_last_clue = str(clues.get(evidence_id, "Evidence registered."))
	var message := "%s\nEvidence %d/%d." % [
		_fault_last_clue,
		_fault_case_evidence.size(),
		required.size(),
	]
	if _fault_case_evidence_complete():
		message += " Candidate staged: %s. Check the terminal to commit, or trace another candidate to change it." % \
			_fault_evidence_label(_fault_selected_candidate)
		if _terminal != null and _terminal.has_method("show_tutorial_label"):
			_terminal.show_tutorial_label()
	_show_fault_prompt(message, 7.0)
	_update_fault_terminal_readout()

func _on_fault_terminal_interacted() -> void:
	if _fault_terminal_pending:
		return
	if _fault_circuit_complete:
		_replay_terminal_focus()
		return
	var case_data := _current_fault_case()
	if not _fault_case_evidence_complete():
		var missing := _fault_missing_evidence()
		_fault_last_clue = "Trace the missing evidence first: %s." % _fault_evidence_list_text(missing)
		_show_fault_prompt(_fault_last_clue, 6.0)
		_rearm_interactable(_terminal)
		_update_fault_terminal_readout()
		return
	if _fault_selected_candidate == "":
		_fault_last_clue = "Trace one of the two candidate objects again to stage a commit."
		_show_fault_prompt(_fault_last_clue, 6.0)
		_rearm_interactable(_terminal)
		_update_fault_terminal_readout()
		return
	var atp := _game_state.get_stat("aster", "atp")
	if atp < FAULT_COMMIT_ATP_COST:
		_fault_last_clue = "Commit needs %d ATP; the evidence stays staged. Refill at the drink machine, then return." % \
			int(FAULT_COMMIT_ATP_COST)
		_show_fault_prompt(_fault_last_clue, 7.0)
		_rearm_interactable(_terminal)
		_rearm_interactable(_drink_machine)
		if _drink_machine != null and _drink_machine.has_method("show_tutorial_label"):
			_drink_machine.show_tutorial_label()
		_update_fault_terminal_readout()
		return
	_fault_terminal_pending = true
	_player.set_move_enabled(false)
	_update_fault_terminal_readout()
	_begin_terminal_screen_focus()
	_scheduler.schedule_after(
		TERMINAL_FOCUS_DURATION,
		_resolve_fault_terminal_commit,
		"fault_terminal_commit"
	)

func _resolve_fault_terminal_commit() -> void:
	if not _fault_terminal_pending or _fault_circuit_complete:
		return
	_fault_terminal_pending = false
	_end_terminal_screen_focus()
	_player.set_move_enabled(true)
	var case_data := _current_fault_case()
	var candidate := _fault_selected_candidate
	var correct := candidate == str(case_data.get("correct", ""))
	if not correct:
		var penalty := 0.0
		if not _fault_case_wrong_penalized:
			penalty = minf(FAULT_WRONG_ATP_COST, _game_state.get_stat("aster", "atp"))
			_game_state.adjust_stat("aster", "atp", -penalty)
			_fault_wrong_atp_spent += penalty
			_fault_case_wrong_penalized = true
		_fault_wrong_commits += 1
		_fault_commit_history.append({
			"case_id": str(case_data.get("id", "")),
			"candidate": candidate,
			"correct": false,
			"atp_cost": penalty,
		})
		_fault_selected_candidate = ""
		_fault_last_clue = str(case_data.get("wrong_clue", "Recheck the discriminating trace and recommit."))
		var cost_text := "-%d ATP" % int(penalty) if penalty > 0.0 else "ATP penalty already capped for this case"
		_show_fault_prompt("Commit rejected (%s). %s" % [cost_text, _fault_last_clue], 9.0)
		_rearm_interactable(_terminal)
		_update_fault_terminal_readout()
		return

	_game_state.adjust_stat("aster", "atp", -FAULT_COMMIT_ATP_COST)
	_fault_correct_commits += 1
	_fault_commit_history.append({
		"case_id": str(case_data.get("id", "")),
		"candidate": candidate,
		"correct": true,
		"atp_cost": FAULT_COMMIT_ATP_COST,
	})
	_fault_last_clue = "Commit accepted: %s." % _fault_evidence_label(candidate)
	_fault_case_index += 1
	if _fault_case_index >= FAULT_REVIEW_CASES.size():
		_complete_fault_review_circuit()
	else:
		_start_fault_case()

func _recover_fault_review_atp() -> void:
	if _fault_terminal_pending:
		_rearm_interactable(_drink_machine)
		return
	var before := _game_state.get_stat("aster", "atp")
	_has_drunk = true
	if before < ATP_MAX:
		_game_state.set_stat("aster", "atp", ATP_MAX)
		_fault_drink_recoveries += 1
		_fault_last_clue = "ATP restored to %d/%d. The staged evidence and commit remain intact." % [
			int(ATP_MAX), int(ATP_MAX),
		]
	else:
		_fault_last_clue = "ATP is already full; return to the active evidence circuit."
	_show_fault_prompt(_fault_last_clue, 6.0)
	_rearm_interactable(_drink_machine)
	if _drink_machine != null and _drink_machine.has_method("hide_tutorial_label"):
		_drink_machine.hide_tutorial_label()
	_update_fault_terminal_readout()

func _complete_fault_review_circuit() -> void:
	_fault_circuit_complete = true
	_fault_terminal_pending = false
	_fault_selected_candidate = ""
	for evidence in _fault_evidence_interactables.values():
		if evidence != null and is_instance_valid(evidence):
			evidence.set_interaction_enabled(false)
	_rearm_interactable(_terminal)
	_update_fault_terminal_readout()
	_maybe_unlock_exploration_gate()

func _start_workspace_protocol_operation(protocol_id: String) -> void:
	if not WORKSPACE_PROTOCOLS.has(protocol_id) or not _fault_circuit_complete:
		return
	_workspace_protocol_started = true
	_workspace_protocol_complete = false
	_workspace_protocol_phase = protocol_id
	_workspace_protocol_evidence[protocol_id] = {}
	_workspace_protocol_execution_progress[protocol_id] = 0
	var protocol: Dictionary = WORKSPACE_PROTOCOLS[protocol_id]
	_current_step = str(protocol.get("step", "workspace_protocol"))
	if is_instance_valid(_workspace_protocol_layer):
		_workspace_protocol_layer.visible = true
	for group_id_variant in _workspace_protocol_groups:
		var group_id := str(group_id_variant)
		var group = _workspace_protocol_groups[group_id]
		if is_instance_valid(group):
			group.visible = group_id == protocol_id
	for site_id_variant in _workspace_protocol_sites:
		_set_workspace_protocol_site_enabled(str(site_id_variant), false)
	var evidence: Array = protocol.get("evidence", [])
	if bool(protocol.get("ordered_evidence", false)):
		if not evidence.is_empty():
			_set_workspace_protocol_site_enabled(str(evidence[0]), true, true)
	else:
		for evidence_id_variant in evidence:
			_set_workspace_protocol_site_enabled(str(evidence_id_variant), true, true)
	_update_workspace_protocol_readout()
	if _tutorial_prompt != null and _tutorial_prompt.has_method("show_prompt"):
		var instruction := "Follow the marked phase nodes in order." if bool(protocol.get("ordered_evidence", false)) \
			else "Survey every marked instrument in any order."
		_tutorial_prompt.show_prompt("%s // %s" % [str(protocol.get("label", "WORKSPACE PROTOCOL")), instruction], 8.0)

func _set_workspace_protocol_site_enabled(site_id: String, enabled: bool, show_label: bool = false) -> void:
	var site = _workspace_protocol_sites.get(site_id)
	if not is_instance_valid(site):
		return
	if enabled and site.has_method("reset"):
		site.reset()
	if site.has_method("set_interaction_enabled"):
		site.set_interaction_enabled(enabled)
	if enabled and show_label and site.has_method("show_tutorial_label"):
		site.call_deferred("show_tutorial_label")
	elif site.has_method("hide_tutorial_label"):
		site.hide_tutorial_label()

func _on_workspace_protocol_site_interacted(site_id: String) -> void:
	if not _workspace_protocol_started or _workspace_protocol_complete or not WORKSPACE_PROTOCOL_SITES.has(site_id):
		return
	var spec: Dictionary = WORKSPACE_PROTOCOL_SITES[site_id]
	var protocol_id := str(spec.get("protocol", ""))
	if protocol_id != _workspace_protocol_phase or not WORKSPACE_PROTOCOLS.has(protocol_id):
		return
	var site = _workspace_protocol_sites.get(site_id)
	if not is_instance_valid(site) or not site.is_interaction_enabled():
		return
	var protocol: Dictionary = WORKSPACE_PROTOCOLS[protocol_id]
	var kind := str(spec.get("kind", "evidence"))
	if kind == "evidence":
		_resolve_workspace_protocol_evidence(protocol_id, site_id, protocol, spec)
	elif kind == "choice":
		_resolve_workspace_protocol_choice(protocol_id, site_id, protocol, spec)
	elif kind == "execution":
		_resolve_workspace_protocol_execution(protocol_id, site_id, protocol, spec)

func _resolve_workspace_protocol_evidence(
		protocol_id: String, site_id: String, protocol: Dictionary, spec: Dictionary
	) -> void:
	var completed: Dictionary = _workspace_protocol_evidence.get(protocol_id, {})
	if bool(completed.get(site_id, false)):
		return
	var evidence: Array = protocol.get("evidence", [])
	if bool(protocol.get("ordered_evidence", false)):
		var expected_index := completed.size()
		if expected_index >= evidence.size() or str(evidence[expected_index]) != site_id:
			_rearm_interactable(_workspace_protocol_sites.get(site_id))
			return
	completed[site_id] = true
	_workspace_protocol_evidence[protocol_id] = completed
	_set_workspace_protocol_site_enabled(site_id, false)
	_show_fault_prompt(str(spec.get("finding", "Protocol evidence recorded.")), 5.0)
	if completed.size() < evidence.size():
		if bool(protocol.get("ordered_evidence", false)):
			_set_workspace_protocol_site_enabled(str(evidence[completed.size()]), true, true)
		_update_workspace_protocol_readout()
		return
	for choice_id_variant in protocol.get("choices", []):
		_set_workspace_protocol_site_enabled(str(choice_id_variant), true, true)
	_show_fault_prompt("Evidence complete. Commit one marked protocol plan.", 6.0)
	_update_workspace_protocol_readout()

func _resolve_workspace_protocol_choice(
		protocol_id: String, site_id: String, protocol: Dictionary, spec: Dictionary
	) -> void:
	if not _workspace_protocol_evidence_complete(protocol_id):
		_rearm_interactable(_workspace_protocol_sites.get(site_id))
		return
	_workspace_protocol_choices[protocol_id] = site_id
	_workspace_protocol_decisions += 1
	_workspace_protocol_execution_progress[protocol_id] = 0
	for choice_id_variant in protocol.get("choices", []):
		_set_workspace_protocol_site_enabled(str(choice_id_variant), false)
	var execution: Array = (protocol.get("execution_sites", {}) as Dictionary).get(site_id, [])
	if not execution.is_empty():
		_set_workspace_protocol_site_enabled(str(execution[0]), true, true)
	_show_fault_prompt("%s Execute the committed route at every marked station." % str(spec.get("finding", "Plan committed.")), 7.0)
	_update_workspace_protocol_readout()

func _resolve_workspace_protocol_execution(
		protocol_id: String, site_id: String, protocol: Dictionary, spec: Dictionary
	) -> void:
	var choice_id := str(_workspace_protocol_choices.get(protocol_id, ""))
	var execution: Array = (protocol.get("execution_sites", {}) as Dictionary).get(choice_id, [])
	var progress := int(_workspace_protocol_execution_progress.get(protocol_id, 0))
	if progress >= execution.size() or str(execution[progress]) != site_id:
		_rearm_interactable(_workspace_protocol_sites.get(site_id))
		return
	_set_workspace_protocol_site_enabled(site_id, false)
	_workspace_protocol_execution_history.append({
		"protocol": protocol_id,
		"choice": choice_id,
		"site": site_id,
	})
	progress += 1
	_workspace_protocol_execution_progress[protocol_id] = progress
	_show_fault_prompt(str(spec.get("finding", "Protocol execution recorded.")), 5.0)
	if progress < execution.size():
		_set_workspace_protocol_site_enabled(str(execution[progress]), true, true)
		_update_workspace_protocol_readout()
		return
	_workspace_protocol_completed[protocol_id] = true
	_apply_workspace_protocol_choice(protocol_id, choice_id)
	var next_protocol := str(protocol.get("next", ""))
	if next_protocol != "":
		_start_workspace_protocol_operation(next_protocol)
	else:
		_complete_workspace_protocols()

func _workspace_protocol_evidence_complete(protocol_id: String) -> bool:
	if not WORKSPACE_PROTOCOLS.has(protocol_id):
		return false
	var completed: Dictionary = _workspace_protocol_evidence.get(protocol_id, {})
	return completed.size() == (WORKSPACE_PROTOCOLS[protocol_id].get("evidence", []) as Array).size()

func _apply_workspace_protocol_choice(protocol_id: String, choice_id: String) -> void:
	match choice_id:
		"phase_sweep":
			_workspace_protocol_effects["alignment_mode"] = "full_sweep"
			_workspace_protocol_effects["forecast_fidelity"] = "high"
		"phase_isolate":
			_workspace_protocol_effects["alignment_mode"] = "local_isolate"
			_workspace_protocol_effects["room_exposure"] = "contained"
		"load_hold_reserve":
			_workspace_protocol_effects["load_mode"] = "reserve_hold"
			_workspace_protocol_effects["thermal_margin"] = "wide"
		"load_open_throughput":
			_workspace_protocol_effects["load_mode"] = "fast_throughput"
			_workspace_protocol_effects["thermal_margin"] = "narrow"
		"authorship_name_crew":
			_workspace_protocol_effects["authorship_mode"] = "crew_context"
			_workspace_protocol_effects["support_context_preserved"] = true
		"authorship_publish_operator":
			_workspace_protocol_effects["authorship_mode"] = "operator_record"
			_workspace_protocol_effects["repair_signature_preserved"] = true
	_workspace_protocol_effects["last_protocol"] = protocol_id

func _complete_workspace_protocols() -> void:
	_workspace_protocol_complete = true
	_workspace_protocol_phase = "complete"
	for site_id_variant in _workspace_protocol_sites:
		_set_workspace_protocol_site_enabled(str(site_id_variant), false)
	_current_step = "explore_workspace"
	_update_workspace_protocol_readout()
	_maybe_unlock_exploration_gate()

func _update_workspace_protocol_readout() -> void:
	if _terminal_screen_readout == null:
		return
	if _workspace_protocol_complete:
		_terminal_screen_readout.text = "WORKSPACE VALIDATION // CLEARED\n\n3/3 protocols executed.\nAlignment: %s\nLoad: %s\nAuthorship: %s" % [
			str(_workspace_protocol_effects.get("alignment_mode", "recorded")),
			str(_workspace_protocol_effects.get("load_mode", "recorded")),
			str(_workspace_protocol_effects.get("authorship_mode", "recorded")),
		]
		return
	if not WORKSPACE_PROTOCOLS.has(_workspace_protocol_phase):
		return
	var protocol: Dictionary = WORKSPACE_PROTOCOLS[_workspace_protocol_phase]
	var evidence: Dictionary = _workspace_protocol_evidence.get(_workspace_protocol_phase, {})
	var choice := str(_workspace_protocol_choices.get(_workspace_protocol_phase, "none"))
	var execution_progress := int(_workspace_protocol_execution_progress.get(_workspace_protocol_phase, 0))
	_terminal_screen_readout.text = "WORKSPACE VALIDATION // %s\n\nEVIDENCE: %d/%d\nPLAN: %s\nEXECUTION: %d" % [
		str(protocol.get("label", "PROTOCOL")), evidence.size(),
		(protocol.get("evidence", []) as Array).size(), choice, execution_progress,
	]

func _current_fault_case() -> Dictionary:
	if _fault_case_index < 0 or _fault_case_index >= FAULT_REVIEW_CASES.size():
		return {}
	return FAULT_REVIEW_CASES[_fault_case_index]

func _fault_case_evidence_complete() -> bool:
	var case_data := _current_fault_case()
	for evidence_id in (case_data.get("evidence", []) as Array):
		if not _fault_case_evidence.has(str(evidence_id)):
			return false
	return not case_data.is_empty()

func _fault_missing_evidence() -> Array:
	var missing := []
	for evidence_id in (_current_fault_case().get("evidence", []) as Array):
		if not _fault_case_evidence.has(str(evidence_id)):
			missing.append(str(evidence_id))
	return missing

func _fault_evidence_label(evidence_id: String) -> String:
	match evidence_id:
		"glass":
			return "glass topology"
		"painting_teal":
			return "teal trace"
		"painting_ash":
			return "ash trace"
		"awards":
			return "credit ledger"
		"jstore":
			return "J-store fault archive"
		_:
			return evidence_id

func _fault_evidence_list_text(evidence_ids: Array) -> String:
	var labels: Array[String] = []
	for evidence_id in evidence_ids:
		labels.append(_fault_evidence_label(str(evidence_id)))
	return ", ".join(labels)

func _show_fault_prompt(text: String, duration: float) -> void:
	if _tutorial_prompt != null and _tutorial_prompt.has_method("show_prompt"):
		_tutorial_prompt.show_prompt(text, duration)

func _update_fault_terminal_readout() -> void:
	if _terminal_screen_readout == null:
		return
	if _fault_circuit_complete:
		_terminal_screen_readout.text = \
			"FAULT REVIEW // CLEARED\n\n3/3 causes committed.\nWorkspace disconnect route released."
		return
	var case_data := _current_fault_case()
	if case_data.is_empty():
		return
	var evidence_lines: Array[String] = []
	for evidence_id in (case_data.get("evidence", []) as Array):
		evidence_lines.append("[%s] %s" % [
			"X" if _fault_case_evidence.has(str(evidence_id)) else " ",
			_fault_evidence_label(str(evidence_id)),
		])
	var staged := _fault_evidence_label(_fault_selected_candidate) if _fault_selected_candidate != "" else "none"
	_terminal_screen_readout.text = \
		"FAULT REVIEW // CASE %d/%d\n%s\n\n%s\n\nSTAGED: %s\nATP: %d/%d" % [
			_fault_case_index + 1,
			FAULT_REVIEW_CASES.size(),
			str(case_data.get("brief", "")),
			"\n".join(evidence_lines),
			staged,
			int(_game_state.get_stat("aster", "atp")),
			int(ATP_MAX),
		]

func _on_exploration_gate_interacted() -> void:
	if not _explore_gate_unlocked or _explore_gate_fired:
		return
	_explore_gate_fired = true
	_start_tag_notify()

func _start_tag_notify() -> void:
	_current_step = "tag_notify"
	DialogueData.say_to(_dialogue, "aster_sim.device.tag_verify")
	DialogueData.say_to(_dialogue, "aster_sim.ron.tag_notify")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_walk_to_exit, "walk_to_exit"),
		CONNECT_ONE_SHOT
	)

func _start_walk_to_exit() -> void:
	_current_step = "walk_to_exit"
	DialogueData.say_to(_dialogue, "aster_sim.tag_routine")
	_dialogue.dialogue_finished.connect(
		func(): _scheduler.schedule_after(0, _start_transition_out, "transition_out"),
		CONNECT_ONE_SHOT
	)

func _start_transition_out() -> void:
	_current_step = "transition_out"
	_player.set_move_enabled(false)
	_fade_start_tick = _scheduler.get_current_tick()
	_scheduler.schedule_after(2.5, _complete, "complete")

func _complete() -> void:
	_current_step = "complete"
	_change_scene_or_record("res://scenes/tutorial/peris_sim.tscn")

# --- Environment ---

func _build_environment() -> void:
	# Load grid from level data
	_grid = GridWorld.new()
	_grid.load_from_json("res://data/levels/aster_sim.json")
	# The scene's ONE declaration of its modeled room: floor surface (overlays/raycast ride it),
	# grid seams aligned to the floor tiles, furniture occupancy, and the re-export guards.
	_room_binder.setup(self, _grid, {
		"root_name": "AsterRoom",
		"floor_surface_y": 0.063,  # the Room model's real floor TOP (measured) — characters/overlays ride it
		"grid_origin_xz": Vector2(-0.5, -0.42),
		"occupants": ["Desk", "drink_machine"],
		"gltf_path": "res://resources/models/aster-sim/room/aster-sim-room-hi-res.gltf",
		"wired_materials": ["aster-sim-room-hi-res_1", "aster-sim-room-hi-res_8"],
		"wired_normal_materials": ["aster-sim-room-hi-res_1"],
	})

	# Grid renderer creates floor collision and tile meshes.
	_renderer = GridRenderer.new()
	_renderer.name = "Environment"
	var warm_colors := {
		GridWorld.Tile.FLOOR: Color(0.12, 0.1, 0.08),
		GridWorld.Tile.WALL: Color(0.15, 0.12, 0.1),
		GridWorld.Tile.FLORA: Color(0.1, 0.18, 0.1),
		GridWorld.Tile.IRON_BLOOM: Color(0.25, 0.1, 0.05),
		GridWorld.Tile.SHELTER: Color(0.1, 0.12, 0.2),
		GridWorld.Tile.TERMINAL: Color(0.1, 0.15, 0.18),
		GridWorld.Tile.FOOD: Color(0.1, 0.16, 0.1),
	}
	_renderer.setup(_grid, {"colors": warm_colors})
	add_child(_renderer)
	_apply_graybox_visibility()

	var env_node := _renderer
	var use_imported_room_lighting := show_high_res_room and not show_graybox_room

	# Drink machine.
	var drink_cells := _grid.find_tiles(GridWorld.Tile.FOOD)
	if not drink_cells.is_empty():
		var drink_world := _placement_or_grid("DrinkMachineAnchor", drink_cells[0], 0.0)
		_add_drink_machine_visual(env_node, drink_world)

	if not use_imported_room_lighting:
		_ensure_directional_light(env_node)

		var desk_area := _placement_or_grid("DataMotesCenter", Vector2i(3, 4), 1.8)
		_ensure_omni_light(
			env_node,
			"DeskLight",
			_placement_or_position("DeskLight", Vector3(desk_area.x, 2.5, desk_area.z)),
			Color(0.9, 0.75, 0.5),
			2.0,
			6.0
		)

		_ensure_omni_light(
			env_node,
			"DataLight",
			_placement_or_position("DataLight", Vector3(desk_area.x, 2.0, desk_area.z)),
			Color(0.3, 0.6, 0.8),
			1.0,
			4.0
		)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK if use_imported_room_lighting else Color(0.06, 0.05, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK if use_imported_room_lighting else Color(0.4, 0.35, 0.28)
	env.ambient_light_energy = 0.0 if use_imported_room_lighting else 0.5
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.15
	we.environment = env
	env_node.add_child(we)

func _apply_graybox_visibility() -> void:
	if show_graybox_room:
		return
	# Hide EVERY graybox mesh, including ones nested under the floor's StaticBody — collision
	# stays live for click raycasts; only the visuals go.
	for child in _renderer.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).visible = false

func _ensure_directional_light(parent: Node3D) -> DirectionalLight3D:
	var scene_light := _placement_node("WarmDirectionalLight") as DirectionalLight3D
	if scene_light != null:
		return scene_light
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "WarmDirectionalLight"
	dir_light.rotation_degrees = Vector3(-45, 30, 0)
	dir_light.light_color = Color(0.95, 0.85, 0.7)
	dir_light.light_energy = 0.7
	dir_light.shadow_enabled = true
	parent.add_child(dir_light)
	return dir_light

func _ensure_omni_light(
		parent: Node3D,
		light_name: String,
		fallback_position: Vector3,
		light_color: Color,
		light_energy: float,
		omni_range: float
	) -> OmniLight3D:
	var scene_light := _placement_node(light_name) as OmniLight3D
	if scene_light != null:
		return scene_light
	var light := OmniLight3D.new()
	light.name = light_name
	light.position = _local_for_parent(parent, fallback_position)
	light.light_color = light_color
	light.light_energy = light_energy
	light.omni_range = omni_range
	parent.add_child(light)
	return light

func _add_desk(parent: Node3D, pos: Vector3) -> void:
	# With the real room model active, the MODEL's desk is the desk: skip the graybox boxes and wrap
	# the imported meshes in the outline target so hover/SHIFT light the actual furniture.
	if _use_room_model():
		var model_meshes := _room_model_meshes("Desk")
		if not model_meshes.is_empty():
			# Centre + size from the PLACED model, so the hover/proximity volume follows the furniture.
			# An unplaced (identity, origin-piled) desk keeps the graybox anchor for its volume.
			var ab := _room_object_aabb("Desk")
			var placed := _room_object_placed("Desk") and ab.size != Vector3.ZERO
			var center := ab.get_center() if placed else pos + Vector3(0.0, 0.75, -0.1)
			var size := (ab.size + Vector3(0.4, 0.4, 0.4)) if placed else Vector3(2.4, 1.2, 1.8)
			_create_graybox_outline_target(parent, "RoomTargetDesk", center, size, model_meshes, "desk", 1.45)
			return
	var meshes: Array = []
	# Desktop surface
	var desk := MeshInstance3D.new()
	var db := BoxMesh.new()
	db.size = Vector3(2.0, 0.08, 1.0)
	desk.mesh = db
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.18, 0.14, 0.1)
	dm.roughness = 0.3
	desk.material_override = dm
	desk.position = pos + Vector3(0, 0.75, 0)
	parent.add_child(desk)
	meshes.append(desk)

	for x in [-0.8, 0.8]:
		for z in [-0.4, 0.4]:
			var leg := MeshInstance3D.new()
			var lb := BoxMesh.new()
			lb.size = Vector3(0.06, 0.75, 0.06)
			leg.mesh = lb
			leg.material_override = dm
			leg.position = pos + Vector3(x, 0.375, z)
			parent.add_child(leg)
			meshes.append(leg)

	# Chair.
	var chair := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.25
	cm.bottom_radius = 0.25
	cm.height = 0.08
	chair.mesh = cm
	var chair_mat := StandardMaterial3D.new()
	chair_mat.albedo_color = Color(0.2, 0.15, 0.12)
	chair.material_override = chair_mat
	chair.position = pos + Vector3(0, 0.5, -0.7)
	parent.add_child(chair)
	meshes.append(chair)

	_create_graybox_outline_target(parent, "RoomTargetDesk",
		pos + Vector3(0.0, 0.75, -0.1), Vector3(2.4, 1.2, 1.8), meshes, "desk", 1.45)

func _create_holo_display(pos: Vector3) -> MeshInstance3D:
	var display := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.8, 0.5, 0.02)
	display.mesh = pb
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.3, 0.4, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.15, 0.4, 0.55)
	mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	display.material_override = mat
	display.position = pos
	return display

func _add_drink_machine_visual(parent: Node3D, pos: Vector3) -> void:
	# The composed model carries the real drink machine: wrap ITS meshes, skip the graybox boxes.
	var prop := _model_prop(["drink_machine"])
	var meshes: Array = []
	if prop.is_empty():
		var body := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(0.8, 1.8, 0.6)
		body.mesh = bb
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.2, 0.18, 0.15)
		body.material_override = bm
		body.position = pos + Vector3(0, 0.9, 0)
		parent.add_child(body)
		meshes.append(body)

		var screen := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.5, 0.3, 0.02)
		screen.mesh = sb
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.2, 0.5, 0.3, 0.9)
		sm.emission_enabled = true
		sm.emission = Color(0.15, 0.4, 0.25)
		sm.emission_energy_multiplier = 1.0
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		screen.material_override = sm
		screen.position = pos + Vector3(0, 1.4, -0.32)
		parent.add_child(screen)
		meshes.append(screen)

		var lbl := Label3D.new()
		lbl.text = "DRINKS"
		lbl.font_size = 36
		lbl.pixel_size = 0.01
		lbl.modulate = Color(0.4, 0.7, 0.5, 0.7)
		lbl.position = pos + Vector3(0, 1.75, -0.32)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		parent.add_child(lbl)

	_create_graybox_outline_target(parent, "RoomTargetDrinkMachine",
		prop.center if not prop.is_empty() else pos + Vector3(0.0, 0.95, 0.0),
		prop.size if not prop.is_empty() else Vector3(1.2, 2.1, 1.0),
		prop.meshes if not prop.is_empty() else meshes, "drink_machine", 1.2)

# --- Terminal Interactable ---

func _build_terminal() -> void:
	var term_cells := _grid.find_tiles(GridWorld.Tile.TERMINAL)
	var term_pos := Vector3(3, 0, 0)
	if not term_cells.is_empty():
		term_pos = _placement_or_grid("TerminalAnchor", term_cells[0], 0.0)
	# The terminal lives ON the desk: with the room model active it follows the placed desk.
	term_pos = _model_or_marker("Desk", "TerminalAnchor", term_pos)

	if not Engine.is_editor_hint():
		_terminal = preload("res://scenes/game/interactable.tscn").instantiate()
		_terminal.name = "Terminal"
		_terminal.description = "Forecasting Terminal"
		_terminal.apply_interactable_spec("aster.terminal")
		_terminal.position = _local_for_parent(self, _placement_or_position("TerminalInteract", term_pos + Vector3(0, 0.8, 0)))
		add_child(_terminal)
		_terminal.interacted.connect(_on_terminal_interacted)

	var env_node: Node = find_child("Environment", false, false)
	if env_node:
		_add_desk(env_node, term_pos)
		_set_room_target_interaction_delegate(find_child("RoomTargetDesk", true, false), _terminal)
		_terminal_screen_world = term_pos + Vector3(0, 1.5, 0)
		var display := _create_holo_display(_terminal_screen_world)
		env_node.add_child(display)
		_data_displays.append(display)
		_terminal_screen_lowfi = display
		_terminal_screen_detail = _create_terminal_screen_detail(_terminal_screen_world)
		env_node.add_child(_terminal_screen_detail)
		# Face both screens the way the modeled monitor does — toward the chair, not the default +Z.
		var screen_yaw := atan2(_screen_facing().x, _screen_facing().z)
		display.rotation.y = screen_yaw
		_terminal_screen_detail.rotation.y = screen_yaw

## The detailed screen shown while the terminal is in focus. Placeholder art:
## a brighter framed panel plus a forecast readout, swapped in for the low-fi
## holo display when the player checks the terminal.
func _create_terminal_screen_detail(world_pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "TerminalScreenDetail"
	root.position = world_pos
	root.visible = false

	var panel := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.7, 1.05)
	panel.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.10, 0.14)
	mat.emission_enabled = true
	mat.emission = Color(0.12, 0.34, 0.5)
	mat.emission_energy_multiplier = 1.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# A real, fixed screen facing +Z (the side Aster reads it from); the focus camera frames it head-on
	# from that front, so there's no need to billboard it (a swivelling screen reads as fake).
	panel.material_override = mat
	root.add_child(panel)

	var readout := Label3D.new()
	readout.no_depth_test = true
	# Aster's monitor message thread, from the GDD's opening of his workspace: the system credits Aster
	# for work the support crew actually did and rewards him with a drink-machine upgrade; Aster deflects
	# the credit; the system insists he did it all. This sets up the drink-machine ATP beat (the mugs on
	# his shelf are these rewards, accumulated). Characterisation in subtext — no narration needed.
	readout.text = "SYSTEM: Congrats on your hard work, task NVU-MAINT-0734-NORM. Your reward is an upgrade to your drink machine!\n\nASTER: You should thank the support crew. They did most of it.\n\nSYSTEM: But you did all the hard work!"
	readout.font_size = 22
	readout.pixel_size = 0.0030
	readout.width = 540  # wrap boundary (px) so the long crew line folds inside the panel
	readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	readout.modulate = Color(0.6, 0.85, 1.0)
	readout.outline_modulate = Color(0, 0, 0, 0.6)
	readout.outline_size = 6
	readout.position = Vector3(0, 0, 0.02)
	root.add_child(readout)
	_terminal_screen_readout = readout
	return root

# --- Drink Machine Interactable ---

func _build_drink_machine() -> void:
	var drink_cells := _grid.find_tiles(GridWorld.Tile.FOOD)
	var machine_pos := Vector3(8, 0, -3)
	if not drink_cells.is_empty():
		machine_pos = _placement_or_grid("DrinkMachineAnchor", drink_cells[0], 0.0)
	machine_pos = _model_or_marker("drink_machine", "DrinkMachineAnchor", machine_pos)

	if not Engine.is_editor_hint():
		_drink_machine = preload("res://scenes/game/interactable.tscn").instantiate()
		_drink_machine.name = "DrinkMachine"
		_drink_machine.description = "Drink Machine"
		_drink_machine.apply_interactable_spec("aster.drink_machine")
		_drink_machine.position = _local_for_parent(self, _placement_or_position("DrinkMachineInteract", machine_pos + Vector3(0, 0.9, 0)))
		# The proximity sphere stays centered on the machine face, but a click must stop Aster at the
		# measured floor point in front of it. Aster is displayed/collided at 2x scale, so using the
		# interaction sphere's centre as the destination embeds half of his capsule in the cabinet.
		var approach_position := _placement_or_position(
			"DrinkMachineApproach",
			Vector3(machine_pos.x, _grid.origin.y, machine_pos.z + 1.5)
		)
		_drink_machine.set_meta("interaction_target_position", approach_position)
		add_child(_drink_machine)
		_drink_machine.interacted.connect(_on_drink_interacted)
		var room_target := find_child("RoomTargetDrinkMachine", true, false)
		if room_target != null:
			# The modeled surface target and the Area3D are both click-pickable. Give both paths the
			# same destination so clicking either cannot regress to the cabinet centre.
			room_target.set_meta("interaction_target_position", approach_position)
		_set_room_target_interaction_delegate(room_target, _drink_machine)

# --- Exploration objects (post-drink, pre-Tag-Day) ---

func _build_exploration_objects() -> void:
	if Engine.is_editor_hint():
		return
	var env: Node3D = self
	if _renderer != null:
		env = _renderer
	_build_glass_bead_game(env)
	_build_painting_panel(env, Vector2i(6, 1), Vector2i(6, 3), "macabre_teal",
		Color(0.15, 0.38, 0.42), "aster.sim_expand.painting_1.line")
	_build_painting_panel(env, Vector2i(11, 1), Vector2i(11, 3), "hunter_ash",
		Color(0.4, 0.3, 0.18), "aster.sim_expand.painting_2.line")
	_build_awards_shelf(env)
	_build_jstore_shelf(env)
	_build_hallway_exit(env)

func _build_workspace_protocols() -> void:
	if Engine.is_editor_hint() or is_instance_valid(_workspace_protocol_layer):
		return
	_workspace_protocol_layer = Node3D.new()
	_workspace_protocol_layer.name = "AsterWorkspaceProtocols"
	add_child(_workspace_protocol_layer)
	for protocol_id_variant in WORKSPACE_PROTOCOL_ORDER:
		_build_workspace_protocol_group(str(protocol_id_variant))
	_workspace_protocol_layer.visible = false

func _build_workspace_protocol_group(protocol_id: String) -> void:
	var protocol: Dictionary = WORKSPACE_PROTOCOLS[protocol_id]
	var tint: Color = protocol.get("tint", Color(0.35, 0.75, 1.0))
	var group := Node3D.new()
	group.name = "AsterProtocolGroup_%s" % protocol_id
	_workspace_protocol_layer.add_child(group)
	_workspace_protocol_groups[protocol_id] = group
	_add_workspace_protocol_frame(group, protocol_id, protocol, tint)
	for site_id_variant in WORKSPACE_PROTOCOL_SITES:
		var site_id := str(site_id_variant)
		var spec: Dictionary = WORKSPACE_PROTOCOL_SITES[site_id]
		if str(spec.get("protocol", "")) == protocol_id:
			_spawn_workspace_protocol_site(group, site_id, spec, tint)
	var datum_index := 0
	var evidence: Array = protocol.get("evidence", [])
	for index in range(1, evidence.size()):
		_add_workspace_protocol_datum(
			group, protocol_id, datum_index,
			_workspace_protocol_site_position(str(evidence[index - 1])),
			_workspace_protocol_site_position(str(evidence[index])), tint
		)
		datum_index += 1
	if evidence.is_empty():
		return
	var branch_origin := _workspace_protocol_site_position(str(evidence[-1]))
	for choice_id_variant in protocol.get("choices", []):
		var choice_id := str(choice_id_variant)
		var choice_position := _workspace_protocol_site_position(choice_id)
		_add_workspace_protocol_datum(group, protocol_id, datum_index, branch_origin, choice_position, tint)
		datum_index += 1
		var previous := choice_position
		for execution_id_variant in (protocol.get("execution_sites", {}) as Dictionary).get(choice_id, []):
			var next := _workspace_protocol_site_position(str(execution_id_variant))
			_add_workspace_protocol_datum(group, protocol_id, datum_index, previous, next, tint)
			datum_index += 1
			previous = next

func _spawn_workspace_protocol_site(
		parent: Node3D, site_id: String, spec: Dictionary, tint: Color
	) -> void:
	var position: Vector3 = spec.get("pos", Vector3.ZERO)
	var kind := str(spec.get("kind", "evidence"))
	var meshes: Array = []
	var base := MeshInstance3D.new()
	base.name = "AsterProtocolVisual_%s_Base" % site_id
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.24 if kind == "evidence" else 0.29
	base_mesh.bottom_radius = 0.29 if kind == "evidence" else 0.34
	base_mesh.height = 0.08
	base.mesh = base_mesh
	base.material_override = _workspace_protocol_material(tint.darkened(0.45), 0.45)
	base.position = position + Vector3(0.0, 0.04, 0.0)
	parent.add_child(base)
	meshes.append(base)

	var beacon := MeshInstance3D.new()
	beacon.name = "AsterProtocolVisual_%s_Beacon" % site_id
	var beacon_mesh := CylinderMesh.new()
	beacon_mesh.top_radius = 0.04
	beacon_mesh.bottom_radius = 0.10 if kind == "evidence" else 0.14
	beacon_mesh.height = 0.52 if kind == "evidence" else 0.68
	beacon.mesh = beacon_mesh
	var beacon_color := tint
	if kind == "choice":
		beacon_color = Color(1.0, 0.72, 0.25)
	elif kind == "execution":
		beacon_color = Color(0.48, 1.0, 0.62)
	beacon.material_override = _workspace_protocol_material(beacon_color, 2.2)
	beacon.position = position + Vector3(0.0, beacon_mesh.height * 0.5 + 0.08, 0.0)
	parent.add_child(beacon)
	meshes.append(beacon)

	var glyph := MeshInstance3D.new()
	glyph.name = "AsterProtocolVisual_%s_Glyph" % site_id
	var glyph_mesh := BoxMesh.new()
	glyph_mesh.size = Vector3(0.30 if kind == "choice" else 0.20, 0.045, 0.30 if kind == "execution" else 0.20)
	glyph.mesh = glyph_mesh
	glyph.material_override = _workspace_protocol_material(beacon_color.lightened(0.18), 2.8)
	glyph.position = position + Vector3(0.0, beacon.position.y - position.y + beacon_mesh.height * 0.5 + 0.04, 0.0)
	glyph.rotation.y = PI * 0.25
	parent.add_child(glyph)
	meshes.append(glyph)

	var target := _create_graybox_outline_target(
		parent, "AsterProtocolTarget_%s" % site_id,
		position + Vector3(0.0, 0.40, 0.0), Vector3(0.9, 1.0, 0.9),
		meshes, "aster_protocol_%s" % site_id, 0.9
	)
	var interactable_spec := {
		"position": position,
		"radius": 0.9,
		"hold_time": float(spec.get("dwell", 5.0)),
		"one_shot": false,
		"requires_hold": false,
		"required_character": "aster",
		"tutorial_label": str(spec.get("label", "RUN PROTOCOL")),
		"description": "Workspace Protocol: %s" % str(spec.get("display", site_id)),
		"enabled": false,
	}
	var site := InteractableFactory.spawn(
		_game_state, parent, "AsterProtocol_%s" % site_id, interactable_spec,
		_scheduler, _dialogue, "aster"
	)
	site.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
	site.set("dwell_time", float(spec.get("dwell", 5.0)))
	site.set("one_shot", false)
	site.set("required_character", "aster")
	site.set_meta("workspace_protocol_site_id", site_id)
	_set_room_target_interaction_delegate(target, site)
	_connect_interactable_outline_feedback(site)
	site.interacted.connect(_on_workspace_protocol_site_interacted.bind(site_id))
	site.set_interaction_enabled(false)
	_workspace_protocol_sites[site_id] = site
	_workspace_protocol_visuals[site_id] = target

func _add_workspace_protocol_frame(
		parent: Node3D, protocol_id: String, protocol: Dictionary, tint: Color
	) -> void:
	var evidence: Array = protocol.get("evidence", [])
	if evidence.is_empty():
		return
	var origin := _workspace_protocol_site_position(str(evidence[0]))
	var frame := Node3D.new()
	frame.name = "AsterProtocolFrame_%s" % protocol_id
	parent.add_child(frame)
	for x_offset in [-0.72, 0.72]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.055, 1.05, 0.055)
		post.mesh = post_mesh
		post.material_override = _workspace_protocol_material(tint, 1.6)
		post.position = origin + Vector3(x_offset, 0.56, 0.0)
		frame.add_child(post)
	var header := MeshInstance3D.new()
	var header_mesh := BoxMesh.new()
	header_mesh.size = Vector3(1.50, 0.06, 0.06)
	header.mesh = header_mesh
	header.material_override = _workspace_protocol_material(tint, 2.0)
	header.position = origin + Vector3(0.0, 1.08, 0.0)
	frame.add_child(header)
	var label := Label3D.new()
	label.name = "AsterProtocolLabel_%s" % protocol_id
	label.text = "// %s //" % str(protocol.get("label", "WORKSPACE PROTOCOL"))
	label.font_size = 40
	label.pixel_size = 0.0015
	label.fixed_size = true
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = tint.lightened(0.2)
	label.outline_modulate = Color(0.01, 0.02, 0.04, 0.9)
	label.outline_size = 8
	label.position = origin + Vector3(0.0, 1.28, 0.0)
	frame.add_child(label)
	var light := OmniLight3D.new()
	light.name = "AsterProtocolLight_%s" % protocol_id
	light.position = origin + Vector3(0.0, 1.65, 0.0)
	light.light_color = tint
	light.light_energy = 0.32
	light.omni_range = 3.2
	light.shadow_enabled = false
	frame.add_child(light)

func _add_workspace_protocol_datum(
		parent: Node3D, protocol_id: String, index: int,
		start: Vector3, finish: Vector3, tint: Color
	) -> void:
	var delta := finish - start
	delta.y = 0.0
	var length := delta.length()
	if length <= 0.05:
		return
	var datum := MeshInstance3D.new()
	datum.name = "AsterProtocolDatum_%s_%02d" % [protocol_id, index]
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.035, 0.012, length)
	datum.mesh = mesh
	datum.material_override = _workspace_protocol_material(tint.darkened(0.15), 1.1)
	datum.position = (start + finish) * 0.5 + Vector3(0.0, 0.015, 0.0)
	datum.rotation.y = atan2(delta.x, delta.z)
	parent.add_child(datum)

func _workspace_protocol_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.45
	material.roughness = 0.30
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = emission_energy
	return material

func _build_glass_bead_game(parent: Node3D) -> void:
	var bead_cell := Vector2i(7, 5)
	var world := _placement_or_grid("GlassBeadAnchor", bead_cell, 0.0)
	# The STANDALONE animated bead game (idle animation, bead connectors, glow) is the real prop:
	# instantiate it where the room model's embedded copy sits (or the marker), HIDE the embedded
	# static copy so they don't double-render, and wrap the animated meshes for hover/highlight.
	var embedded := _model_prop(["glass_bead_game"])
	var game := GLASS_BEAD_SCENE.instantiate() as Node3D
	if game != null:
		var spot := world
		if not embedded.is_empty():
			var c: Vector3 = embedded.center
			var s: Vector3 = embedded.size
			spot = Vector3(c.x, c.y - s.y * 0.5, c.z)
			for m in embedded.meshes:
				(m as MeshInstance3D).visible = false
		add_child(game)
		game.global_position = spot
		# The display script drives materials, connector lines, and the idle loop.
		var game_meshes: Array = game.find_children("*", "MeshInstance3D", true, false)
		var game_target := _create_graybox_outline_target(parent, "RoomTargetGlassBeadGame",
			spot + Vector3(0.0, 0.75, 0.0), Vector3(1.4, 1.4, 1.4), game_meshes, "glass_bead_game", 1.0)
		var game_zone := _make_exploration_zone(
			parent, _local_for_parent(parent, _placement_or_position("GlassBeadZoneMarker", world)),
			"GlassBeadZone", "aster.sim_expand.glass_bead.line", 1.4, 0.6)
		_set_room_target_interaction_delegate(game_target, game_zone)
		_register_workspace_zone(game_zone, "glass", 1)
		return
	var meshes: Array = []
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.35
	bm.bottom_radius = 0.4
	bm.height = 0.12
	base.mesh = bm
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.08, 0.08, 0.12)
	base_mat.metallic = 0.5
	base_mat.roughness = 0.3
	base_mat.emission_enabled = true
	base_mat.emission = Color(0.15, 0.2, 0.35)
	base_mat.emission_energy_multiplier = 0.4
	base.material_override = base_mat
	base.position = world + Vector3(0, 0.55, 0)
	parent.add_child(base)
	meshes.append(base)
	for i in range(8):
		var bead := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.1
		bead.mesh = sm
		var bead_mat := StandardMaterial3D.new()
		bead_mat.albedo_color = Color(0.85, 0.9, 1.0, 0.8)
		bead_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bead_mat.emission_enabled = true
		bead_mat.emission = Color(0.5, 0.7, 1.0)
		bead_mat.emission_energy_multiplier = 1.2
		bead_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bead.material_override = bead_mat
		var angle := i * TAU / 8.0
		bead.position = world + Vector3(cos(angle) * 0.25, 0.9 + sin(angle * 2.0) * 0.08, sin(angle) * 0.25)
		parent.add_child(bead)
		meshes.append(bead)
	var target := _create_graybox_outline_target(parent, "RoomTargetGlassBeadGame",
		world + Vector3(0.0, 0.75, 0.0), Vector3(1.2, 1.1, 1.2), meshes, "glass_bead_game", 1.0)
	var zone := _make_exploration_zone(
		parent, _local_for_parent(parent, _placement_or_position("GlassBeadZoneMarker", world)),
		"GlassBeadZone",
		"aster.sim_expand.glass_bead.line",
		1.4, 0.6
	)
	_set_room_target_interaction_delegate(target, zone)
	_register_workspace_zone(zone, "glass", 1)

func _build_painting_panel(parent: Node3D, canvas_cell: Vector2i, zone_cell: Vector2i, zone_name: String, palette: Color, line_key: String) -> void:
	var marker_prefix := _exploration_marker_prefix(zone_name)
	var canvas_world := _placement_or_grid(marker_prefix + "Canvas", canvas_cell, 0.0)
	# Model painting (macabre_teal = "Painting 1", hunter_ash = "Painting 2"): wrap the real canvas.
	var model_name: String = "Painting 1" if zone_name == "macabre_teal" else "Painting 2"
	var prop := _model_prop([model_name])
	if not prop.is_empty():
		var model_target := _create_graybox_outline_target(parent, "RoomTarget%sPainting" % marker_prefix,
			prop.center, prop.size, prop.meshes, "%s_painting" % zone_name, 0.95)
		var model_zone_world := _placement_or_grid(marker_prefix + "ZoneMarker", zone_cell, 0.0)
		var model_zone := _make_exploration_sequence_zone(
			parent,
			_local_for_parent(parent, model_zone_world),
			zone_name + "Zone",
			[line_key, "aster.sim_expand.collection_community.line"],
			1.4,
			0.6
		)
		_set_room_target_interaction_delegate(model_target, model_zone)
		_register_workspace_zone(model_zone, "paintings", 2)
		return
	var panel := MeshInstance3D.new()
	var qb := BoxMesh.new()
	qb.size = Vector3(1.4, 1.0, 0.06)
	panel.mesh = qb
	var pm := StandardMaterial3D.new()
	pm.albedo_color = palette
	pm.roughness = 0.7
	panel.material_override = pm
	# Canvas frame.
	var frame := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(1.5, 1.1, 0.04)
	frame.mesh = fb
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.06, 0.06, 0.07)
	frame.material_override = fm
	panel.position = canvas_world + Vector3(0, 1.8, 0.02)
	frame.position = canvas_world + Vector3(0, 1.8, 0.0)
	parent.add_child(frame)
	parent.add_child(panel)
	var target_name := "RoomTarget%sPainting" % marker_prefix
	var target := _create_graybox_outline_target(parent, target_name,
		canvas_world + Vector3(0.0, 1.8, 0.03), Vector3(1.8, 1.35, 0.35), [frame, panel],
		"%s_painting" % zone_name, 0.95)
	var zone_world := _placement_or_grid(marker_prefix + "ZoneMarker", zone_cell, 0.0)
	var zone := _make_exploration_sequence_zone(
		parent,
		_local_for_parent(parent, zone_world),
		zone_name + "Zone",
		[line_key, "aster.sim_expand.collection_community.line"],
		1.4,
		0.6
	)
	_set_room_target_interaction_delegate(target, zone)
	_register_workspace_zone(zone, "paintings", 2)

func _build_awards_shelf(parent: Node3D) -> void:
	var shelf_cell := Vector2i(14, 2)
	var world := _placement_or_grid("AwardsShelf", shelf_cell, 0.0)
	# Model awards ("Award 1"/"Award 2"): wrap the real plaques.
	var prop := _model_prop(["Award 1", "Award 2"])
	if not prop.is_empty():
		var model_target := _create_graybox_outline_target(parent, "RoomTargetAwardsShelf",
			prop.center, prop.size, prop.meshes, "awards_shelf", 1.35)
		var model_center_zone := _make_exploration_sequence_zone(
			parent,
			_local_for_parent(parent, _placement_or_position("AwardsCenterZoneMarker", world + Vector3(0, 0, -0.4))),
			"AwardsCenterZone",
			["aster.sim_expand.awards.line", "aster.sim_expand.awards.journalism_line"],
			0.9,
			0.6
		)
		var model_journalism_zone := _make_exploration_zone(
			parent,
			_local_for_parent(parent, _placement_or_position("AwardsJournalismZoneMarker", world + Vector3(0, 0, 0.6))),
			"AwardsJournalismZone",
			"aster.sim_expand.awards.journalism_line",
			0.9,
			0.6
		)
		_set_room_target_interaction_delegate(model_target, model_center_zone)
		_register_workspace_zone(model_center_zone, "awards", 2)
		_register_workspace_zone(model_journalism_zone, "awards", 1)
		return
	var meshes: Array = []
	var shelf := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.25, 0.6, 2.0)
	shelf.mesh = sb
	var shelf_mat := StandardMaterial3D.new()
	shelf_mat.albedo_color = Color(0.15, 0.13, 0.1)
	shelf_mat.roughness = 0.4
	shelf.material_override = shelf_mat
	shelf.position = world + Vector3(0.6, 1.3, 0)
	parent.add_child(shelf)
	meshes.append(shelf)
	# Plaques.
	for i in range(6):
		var plaque := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.08, 0.22, 0.18)
		plaque.mesh = pb
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.55, 0.45, 0.18) if i % 2 == 0 else Color(0.65, 0.65, 0.68)
		pm.metallic = 0.6
		pm.roughness = 0.3
		plaque.material_override = pm
		plaque.position = world + Vector3(0.5, 1.35, -0.7 + i * 0.28)
		parent.add_child(plaque)
		meshes.append(plaque)
	var target := _create_graybox_outline_target(parent, "RoomTargetAwardsShelf",
		world + Vector3(0.55, 1.3, 0.0), Vector3(1.0, 1.2, 2.35), meshes, "awards_shelf", 1.35)
	# Two approach zones.
	var center_zone := _make_exploration_sequence_zone(
		parent,
		_local_for_parent(parent, _placement_or_position("AwardsCenterZoneMarker", world + Vector3(0, 0, -0.4))),
		"AwardsCenterZone",
		["aster.sim_expand.awards.line", "aster.sim_expand.awards.journalism_line"],
		0.9,
		0.6
	)
	var journalism_zone := _make_exploration_zone(
		parent,
		_local_for_parent(parent, _placement_or_position("AwardsJournalismZoneMarker", world + Vector3(0, 0, 0.6))),
		"AwardsJournalismZone",
		"aster.sim_expand.awards.journalism_line",
		0.9,
		0.6
	)
	_set_room_target_interaction_delegate(target, center_zone)
	_register_workspace_zone(center_zone, "awards", 2)
	_register_workspace_zone(journalism_zone, "awards", 1)

func _build_jstore_shelf(parent: Node3D) -> void:
	var shelf_cell := Vector2i(14, 5)
	var world := _placement_or_grid("JStoreShelf", shelf_cell, 0.0)
	# Model journals + mugs: wrap the real shelf contents, skip the graybox set.
	var prop := _model_prop(["j-store", "mug", "Shelf"])
	var meshes: Array = []
	if prop.is_empty():
		var shelf := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.25, 1.0, 2.0)
		shelf.mesh = sb
		var shelf_mat := StandardMaterial3D.new()
		shelf_mat.albedo_color = Color(0.15, 0.13, 0.1)
		shelf.material_override = shelf_mat
		shelf.position = world + Vector3(0.6, 1.1, 0)
		parent.add_child(shelf)
		meshes.append(shelf)
		# J-store spines.
		var spine_colors := [
			Color(0.15, 0.2, 0.35),
			Color(0.35, 0.18, 0.15),
			Color(0.18, 0.3, 0.2),
			Color(0.3, 0.25, 0.15),
			Color(0.2, 0.2, 0.3),
			Color(0.3, 0.2, 0.25),
		]
		for i in range(10):
			var spine := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(0.05, 0.4, 0.15)
			spine.mesh = pb
			var pm := StandardMaterial3D.new()
			pm.albedo_color = spine_colors[i % spine_colors.size()]
			spine.material_override = pm
			spine.position = world + Vector3(0.5, 0.9, -0.9 + i * 0.18)
			parent.add_child(spine)
			meshes.append(spine)
		# Empty mugs.
		for i in range(12):
			var mug := MeshInstance3D.new()
			var mb := CylinderMesh.new()
			mb.top_radius = 0.05
			mb.bottom_radius = 0.05
			mb.height = 0.1
			mug.mesh = mb
			var mm := StandardMaterial3D.new()
			mm.albedo_color = Color(0.25, 0.2, 0.18)
			mug.material_override = mm
			var row := i / 6
			var col := i % 6
			mug.position = world + Vector3(0.5, 1.7, -0.7 + col * 0.22 + row * 0.05)
			parent.add_child(mug)
			meshes.append(mug)
	var target := _create_graybox_outline_target(parent, "RoomTargetJStoreShelf",
		prop.center if not prop.is_empty() else world + Vector3(0.55, 1.15, 0.0),
		prop.size if not prop.is_empty() else Vector3(1.0, 1.8, 2.35),
		prop.meshes if not prop.is_empty() else meshes, "jstore_shelf", 1.45)
	var main_zone := _make_exploration_sequence_zone(parent, _local_for_parent(parent, _placement_or_position("JStoreMainZoneMarker", world + Vector3(0, 0, -0.4))),
		"JStoreMainZone",
		[
			"aster.sim_expand.bookshelf.line",
			"aster.sim_expand.bookshelf.articles_line",
		],
		0.9, 0.6)
	_set_room_target_interaction_delegate(target, main_zone)
	_register_workspace_zone(main_zone, "jstore", 2)

func _build_hallway_exit(parent: Node3D) -> void:
	var world := _placement_or_grid("HallwayExit", HALLWAY_EXIT_CELL, 0.0)
	# Archway frame.
	var arch := MeshInstance3D.new()
	var ab := BoxMesh.new()
	ab.size = Vector3(0.2, 2.8, 1.2)
	arch.mesh = ab
	var am := StandardMaterial3D.new()
	am.albedo_color = Color(0.12, 0.1, 0.08)
	arch.material_override = am
	arch.position = world + Vector3(0.6, 1.4, 0)
	parent.add_child(arch)
	_ensure_omni_light(
		parent,
		"HallwayExitLight",
		_placement_or_position("HallwayExitLight", world + Vector3(1.1, 1.8, 0)),
		Color(1.0, 0.85, 0.6),
		1.4,
		4.0
	)
	# Reuses Interactable plumbing for the timed gate.
	var gate := _create_interactable(parent, _local_for_parent(parent, world), "HallwayGate", 2.2, 0.8,
		"Continue", false, Interactable.InteractableType.HOLD_ACTION, "aster.hallway_gate")
	gate.connect("interacted", _on_exploration_gate_interacted)
	_explore_hallway_gate = gate

func _exploration_marker_prefix(zone_name: String) -> String:
	match zone_name:
		"macabre_teal":
			return "MacabreTeal"
		"hunter_ash":
			return "HunterAsh"
		_:
			return zone_name
