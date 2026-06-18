extends "res://scripts/scene_chunks/scene_chunk.gd"

## WASH RELAY — the early-stretch traversal puzzle (first slice).
##
## A linear run of WASH SECTIONS. One large pipe floods each section on a TIMED CADENCE; any character
## standing on a flooding section is WASHED back to the start shelter (the stretch's return point).
## Each section ends in an OVERRIDE button on a safe ledge: a character who crosses and presses it
## STOPS that section's flow, so the rest of the party can walk across safely. Reach the chunk end with
## the whole party. A RETURN device at the chunk end pulls washed members back up (the "drop a sloperope
## / hit the terminal" recovery) instead of making them re-cross.
##
## The wash fires on the gameplay SCHEDULER (recurring per-section onsets), not per-frame — so it's
## fast-forward + replay safe. (Enemies-washed + the spiral overlook entrance come in later passes.)

const PARTY_IDS := ["aster", "peris", "endo"]

const START_POS := Vector3(3.0, 0.5, 0.0)        # the start-shelter return point (washouts land here)
const SPAWNS := {
	"aster": Vector3(3.0, 0.5, 0.0),
	"peris": Vector3(2.0, 0.5, 1.2),
	"endo":  Vector3(2.0, 0.5, -1.2),
}

# Each section: an X-band the wash sweeps + the override button just past it on a safe ledge.
const SECTIONS := [
	{"x0": 6.0,  "x1": 13.0, "override": Vector3(15.0, 0.5, 0.0), "phase": 0.0},
	{"x0": 17.0, "x1": 24.0, "override": Vector3(26.0, 0.5, 0.0), "phase": 3.0},
]
const FLOOR_Z_HALF := 4.0
const CHUNK_END_X := 30.0                         # whole party past this == chunk complete
const RETURN_POS := Vector3(30.0, 0.5, 2.5)       # the chunk-end sloperope/terminal
const RETURN_LANDING := Vector3(29.0, 0.5, 0.0)   # where a returned member is dropped

const FLOW_PERIOD := 6.0          # seconds between floods of a section
const FLOOD_DURATION := 1.4       # how long the surge holds (cosmetic window; wash resolves at onset)
const FIRST_FLOOD := 2.5          # grace before the first surge

var _phase := "ready"             # ready | active | complete
var _flow_on := [true, true]      # per section — an override flips it off
var _flooding := [false, false]   # cosmetic surge window
var _washed := {}                 # char_id -> true while waiting at the start shelter
var _scheduled := false
var _flow_strips: Array[MeshInstance3D] = []
var _return_used := false

# --- Build ---

func _build_chunk() -> void:
	# continuous walkway; the wash is a hazard ON the floor, sections are X-bands of it
	_add_floor(self, Vector3(17.0, -0.05, 0.0), Vector3(36.0, 0.1, FLOOR_Z_HALF * 2.0), Color(0.10, 0.11, 0.13))
	_add_floor(self, START_POS + Vector3(-1.0, -0.05, 0.0), Vector3(8.0, 0.12, FLOOR_Z_HALF * 2.0 + 1.0), Color(0.09, 0.13, 0.16))  # start shelter pad
	# side walls
	var wc := Color(0.13, 0.14, 0.16)
	_add_box(self, Vector3(17.0, 1.6, -FLOOR_Z_HALF - 0.2), Vector3(36.0, 3.2, 0.4), wc)
	_add_box(self, Vector3(17.0, 1.6, FLOOR_Z_HALF + 0.2), Vector3(36.0, 3.2, 0.4), wc)
	# the one large pipe overhead, spanning the wash sections (the flow source)
	var px0: float = SECTIONS[0]["x0"]; var px1: float = SECTIONS[SECTIONS.size() - 1]["x1"]
	_add_box(self, Vector3((px0 + px1) * 0.5, 4.4, FLOOR_Z_HALF - 0.4), Vector3(px1 - px0 + 2.0, 1.2, 1.2), Color(0.2, 0.19, 0.18))
	# per-section: an outflow spout + a floor flow-strip (pulses while flooding)
	for i in range(SECTIONS.size()):
		var s: Dictionary = SECTIONS[i]
		var cx: float = (float(s["x0"]) + float(s["x1"])) * 0.5
		_add_box(self, Vector3(cx, 3.6, FLOOR_Z_HALF - 0.4), Vector3(1.0, 0.8, 0.8), Color(0.22, 0.21, 0.2))  # spout
		var strip := _add_box(self, Vector3(cx, 0.04, 0.0), Vector3(float(s["x1"]) - float(s["x0"]), 0.06, FLOOR_Z_HALF * 2.0 - 0.4), Color(0.2, 0.4, 0.7))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.15, 0.3, 0.55); mat.emission_enabled = true
		mat.emission = Color(0.25, 0.5, 0.9); mat.emission_energy_multiplier = 0.4
		strip.material_override = mat
		_flow_strips.append(strip)
	_build_interactables()

func _build_interactables() -> void:
	for i in range(SECTIONS.size()):
		var s: Dictionary = SECTIONS[i]
		var ov := _add_interactable(self, "Override%d" % i, "Flow override", s["override"],
			"OVERRIDE", "", 1.0, true, 1.6, Interactable.InteractableType.HOLD_ACTION)
		ov.interacted.connect(func() -> void: _on_override(i))
	var ret := _add_interactable(self, "ReturnDevice", "Drop sloperope", RETURN_POS,
		"DROP LINE", "", 1.4, false, 1.8, Interactable.InteractableType.HOLD_ACTION)
	ret.interacted.connect(func() -> void: _on_return_device())

# --- Wash cadence (scheduler-driven; fires at exact ticks regardless of frame rate) ---

func _ensure_scheduled() -> void:
	if _scheduled:
		return
	var sched = _get_scheduler()
	if sched == null:
		return
	_scheduled = true
	for i in range(SECTIONS.size()):
		var delay: float = FIRST_FLOOD + float(SECTIONS[i]["phase"])
		sched.schedule_after(delay, _make_onset(i), "wash_onset_%d" % i)

func _make_onset(i: int) -> Callable:
	return func() -> void: _flood_onset(i)

func _flood_onset(i: int) -> void:
	var sched = _get_scheduler()
	if _phase == "active" and bool(_flow_on[i]):
		_wash_section(i)
		_flooding[i] = true
		_set_strip_flooding(i, true)
		if sched != null:
			sched.schedule_after(FLOOD_DURATION, func() -> void: _set_flood_off(i), "wash_off_%d" % i)
	# keep the cadence going (a stopped section still ticks; it just doesn't wash)
	if sched != null:
		sched.schedule_after(FLOW_PERIOD, _make_onset(i), "wash_onset_%d" % i)

func _set_flood_off(i: int) -> void:
	_flooding[i] = false
	_set_strip_flooding(i, false)

func _wash_section(i: int) -> void:
	var s: Dictionary = SECTIONS[i]
	var x0: float = s["x0"]; var x1: float = s["x1"]
	for char_id in PARTY_IDS:
		if _washed.has(char_id):
			continue
		var p := _get_character_position(char_id)
		if p.x >= x0 and p.x <= x1 and abs(p.z) <= FLOOR_Z_HALF:
			_wash_character(char_id)

func _wash_character(char_id: String) -> void:
	_washed[char_id] = true
	_set_character_position(char_id, START_POS)
	var gs = _get_game_state()
	if gs != null and gs.has_method("stop_character"):
		gs.stop_character(char_id)

# --- Interactions ---

func _on_override(i: int) -> void:
	if i < 0 or i >= _flow_on.size():
		return
	_flow_on[i] = false
	_set_flood_off(i)
	# the strip goes dim/green = safe
	if i < _flow_strips.size() and is_instance_valid(_flow_strips[i]):
		var mat := _flow_strips[i].material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color(0.12, 0.22, 0.16); mat.emission = Color(0.1, 0.4, 0.2); mat.emission_energy_multiplier = 0.3
	_say("// SECTION %d FLOW // OVERRIDE ENGAGED" % (i + 1))

func _on_return_device() -> void:
	var returned := 0
	for char_id in _washed.keys():
		_set_character_position(char_id, RETURN_LANDING)
		returned += 1
	_washed.clear()
	if returned > 0:
		_say("// LINE DROPPED // %d crew recovered" % returned)
	_return_used = true

func _set_strip_flooding(i: int, on: bool) -> void:
	if i >= _flow_strips.size() or not is_instance_valid(_flow_strips[i]):
		return
	if not bool(_flow_on[i]):
		return
	var mat := _flow_strips[i].material_override as StandardMaterial3D
	if mat != null:
		mat.emission_energy_multiplier = 2.4 if on else 0.4

# --- Lifecycle ---

func _process(_delta: float) -> void:
	_update()

func headless_process(_delta: float) -> void:
	_update()

func _update() -> void:
	if _phase == "ready":
		_phase = "active"
	_ensure_scheduled()
	if _phase == "active":
		var all_through := true
		for char_id in PARTY_IDS:
			if _get_character_position(char_id).x < CHUNK_END_X:
				all_through = false
				break
		if all_through:
			_phase = "complete"
			_say("// CHUNK CLEAR")

# --- Scene/preview interface ---

func get_scene_title() -> String:
	return "Wash Relay"

func get_scene_help() -> String:
	return "One pipe floods each section on a beat. Send a runner across, hit the OVERRIDE to kill that section's flow, then bring the party through. Washed crew drop to the start shelter — climb back or drop a line from the chunk end."

func get_default_character() -> String:
	return "endo"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

func get_grid_data() -> Dictionary:
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [-2.0, 0.0, -6.0],
		"cell_size": 1.0,
		"width": 38,
		"height": 12,
		"walkable_regions": [
			{"min": [-1.0, -FLOOR_Z_HALF], "max": [34.0, FLOOR_Z_HALF]},
		],
	}

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors.merge({
		"start_shelter": START_POS,
		"override_1": SECTIONS[0]["override"],
		"override_2": SECTIONS[1]["override"],
		"return_device": RETURN_POS,
		"chunk_end": Vector3(CHUNK_END_X + 1.0, 0.5, 0.0),
	}, true)
	return anchors

func get_preview_time_state() -> Dictionary:
	return {
		"day": 2,
		"time": 0.5,
		"routing_mode": "safe",
		"note_default": "Read the flood beat. Override each section's flow for the crew, and don't get washed.",
	}

func get_preview_abilities() -> Array:
	return []

func get_preview_overlay_status(_overlay_id: String, _current_tick: float) -> Array:
	return []

func reset_preview_state() -> void:
	_phase = "ready"
	_flow_on = [true, true]
	_flooding = [false, false]
	_washed.clear()
	_return_used = false
	var gs = _get_game_state()
	if gs != null:
		for char_id in PARTY_IDS:
			if gs.characters.has(char_id):
				gs.snap_character_to(char_id, SPAWNS.get(char_id, START_POS))
	for i in range(_flow_strips.size()):
		if is_instance_valid(_flow_strips[i]):
			var mat := _flow_strips[i].material_override as StandardMaterial3D
			if mat != null:
				mat.albedo_color = Color(0.15, 0.3, 0.55); mat.emission = Color(0.25, 0.5, 0.9); mat.emission_energy_multiplier = 0.4
	_set_preview_step("wash_relay_briefing")

func get_preview_state() -> Dictionary:
	return {
		"phase": _phase,
		"complete": _phase == "complete",
		"flow_on": _flow_on.duplicate(),
		"flooding": _flooding.duplicate(),
		"washed_count": _washed.size(),
		"washed": _washed.keys(),
		"return_used": _return_used,
		"flow_period": FLOW_PERIOD,
		"flood_duration": FLOOD_DURATION,
		"section_count": SECTIONS.size(),
	}
