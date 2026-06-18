extends "res://scripts/scene_chunks/scene_chunk.gd"

## WASH RELAY — the early-stretch traversal gauntlet.
##
## A linear run of distinct PUZZLE SECTIONS, each a timed water hazard on one shared cadence. Standing
## in an ACTIVE section's footprint when it floods washes you back to the start shelter. Sections differ
## by TYPE (the verb) and by how they're DISABLED for the party:
##   flush   — a lowered channel floods            (disable: OVERRIDE — a runner crosses + presses it)
##   current — water washes across a narrow walk    (disable: TIMING  — read the cadence, cross between)
##   jet     — floor nozzles erupt                  (disable: OVERRIDE)
##   plate   — a gap whose bridge needs a held plate (disable: PLATE  — one stays on the plate for others)
##   sluice  — a gate slams the threshold           (disable: TIMING)
## Reach the chunk end with the whole party; a RETURN device pulls washed members back up.
## All hazards fire on the gameplay SCHEDULER (recurring per-section onsets) — fast-forward + replay safe.

const PARTY_IDS := ["aster", "peris", "endo"]
const START_POS := Vector3(3.0, 0.5, 0.0)
const SPAWNS := {
	"aster": Vector3(3.0, 0.5, 0.0), "peris": Vector3(2.0, 0.5, 1.2), "endo": Vector3(2.0, 0.5, -1.2),
}
const SECTIONS := [
	{"type": "flush",   "x0": 6.0,  "x1": 11.0, "phase": 0.0, "disable": "override"},
	{"type": "current", "x0": 14.0, "x1": 19.0, "phase": 2.5, "disable": "timing"},
	{"type": "jet",     "x0": 22.0, "x1": 27.0, "phase": 1.2, "disable": "override"},
	{"type": "plate",   "x0": 30.0, "x1": 35.0, "phase": 3.6, "disable": "plate"},
	{"type": "sluice",  "x0": 38.0, "x1": 41.0, "phase": 0.8, "disable": "timing"},
]
const FLOOR_Z_HALF := 4.0
const CHUNK_END_X := 44.0
const RETURN_POS := Vector3(44.0, 0.5, 2.5)
const RETURN_LANDING := Vector3(43.0, 0.5, 0.0)
const FLOW_PERIOD := 6.0
const FLOOD_DURATION := 1.4
const FIRST_FLOOD := 2.5
const PLATE_RADIUS := 1.4          # how close a character must be to "hold" a plate

var _phase := "ready"
var _disabled := []                # per section — override pressed OR (plate currently held)
var _override_locked := []         # per section — an override has been pressed (latched)
var _flooding := []                # cosmetic surge window
var _plate_held := []              # per section — a character is on the plate this frame
var _washed := {}
var _scheduled := false
var _flow_strips: Array = []

# --- Build ---

func _section_color(t: String) -> Color:
	match t:
		"flush":   return Color(0.15, 0.30, 0.55)
		"current": return Color(0.20, 0.45, 0.70)
		"jet":     return Color(0.40, 0.55, 0.85)
		"plate":   return Color(0.55, 0.35, 0.10)
		"sluice":  return Color(0.45, 0.20, 0.10)
	return Color(0.2, 0.3, 0.5)

func _build_chunk() -> void:
	_add_floor(self, Vector3(22.0, -0.05, 0.0), Vector3(46.0, 0.1, FLOOR_Z_HALF * 2.0), Color(0.10, 0.11, 0.13))
	_add_floor(self, START_POS + Vector3(-1.0, -0.05, 0.0), Vector3(8.0, 0.12, FLOOR_Z_HALF * 2.0 + 1.0), Color(0.09, 0.13, 0.16))
	var wc := Color(0.13, 0.14, 0.16)
	_add_box(self, Vector3(22.0, 1.6, -FLOOR_Z_HALF - 0.2), Vector3(46.0, 3.2, 0.4), wc)
	_add_box(self, Vector3(22.0, 1.6, FLOOR_Z_HALF + 0.2), Vector3(46.0, 3.2, 0.4), wc)
	# one large pipe spanning the gauntlet (the shared flow source)
	var px0: float = SECTIONS[0]["x0"]; var px1: float = SECTIONS[SECTIONS.size() - 1]["x1"]
	_add_box(self, Vector3((px0 + px1) * 0.5, 4.4, FLOOR_Z_HALF - 0.4), Vector3(px1 - px0 + 2.0, 1.2, 1.2), Color(0.2, 0.19, 0.18))

	for i in range(SECTIONS.size()):
		var s: Dictionary = SECTIONS[i]
		var t := str(s["type"]); var x0: float = s["x0"]; var x1: float = s["x1"]; var cx := (x0 + x1) * 0.5; var w := x1 - x0
		# per-type graybox dressing (distinct silhouettes)
		match t:
			"flush":
				_add_box(self, Vector3(cx, -0.18, 0.0), Vector3(w, 0.2, FLOOR_Z_HALF * 1.6), Color(0.06, 0.08, 0.1))   # lowered channel
				_add_box(self, Vector3(cx, 3.4, FLOOR_Z_HALF - 0.4), Vector3(1.0, 0.9, 0.9), Color(0.22, 0.21, 0.2))   # spout
			"current":
				_add_box(self, Vector3(cx, -0.12, FLOOR_Z_HALF * 0.7), Vector3(w, 0.3, 2.2), Color(0.06, 0.08, 0.1))
				_add_box(self, Vector3(cx, -0.12, -FLOOR_Z_HALF * 0.7), Vector3(w, 0.3, 2.2), Color(0.06, 0.08, 0.1))
			"jet":
				for jx in [x0 + w * 0.25, cx, x1 - w * 0.25]:
					for jz in [-1.6, 0.0, 1.6]:
						_add_box(self, Vector3(jx, 0.04, jz), Vector3(0.6, 0.08, 0.6), Color(0.07, 0.07, 0.09))
			"plate":
				_add_box(self, Vector3(cx, 0.06, 0.0), Vector3(w, 0.12, 1.6), Color(0.12, 0.13, 0.16))                 # the bridge plank
				_add_box(self, Vector3(x0 - 1.2, 0.04, 0.0), Vector3(1.0, 0.1, 1.8), Color(0.55, 0.35, 0.1))          # the pressure plate
			"sluice":
				_add_box(self, Vector3(x0, 1.7, 0.0), Vector3(0.3, 3.4, FLOOR_Z_HALF * 2.0), Color(0.16, 0.16, 0.18))
				_add_box(self, Vector3(x1, 1.7, 0.0), Vector3(0.3, 3.4, FLOOR_Z_HALF * 2.0), Color(0.16, 0.16, 0.18))
				_add_box(self, Vector3(cx, 3.3, 0.0), Vector3(w, 0.5, FLOOR_Z_HALF * 2.0), Color(0.16, 0.16, 0.18))
		# the active-flow indicator strip (pulses while flooding)
		var strip := _add_box(self, Vector3(cx, 0.03, 0.0), Vector3(w, 0.06, FLOOR_Z_HALF * 1.7), _section_color(t))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _section_color(t) * 0.6; mat.emission_enabled = true
		mat.emission = _section_color(t); mat.emission_energy_multiplier = 0.4
		strip.material_override = mat
		_flow_strips.append(strip)
		# the disable control: an override console past the section, or a held plate before it
		if str(s["disable"]) == "override":
			var ov := _add_interactable(self, "Override%d" % i, "Flow override", Vector3(x1 + 1.5, 0.5, 0.0),
				"OVERRIDE", "", 1.0, true, 1.6, Interactable.InteractableType.HOLD_ACTION)
			ov.interacted.connect(func() -> void: _on_override(i))
	_build_return()

func _build_return() -> void:
	var ret := _add_interactable(self, "ReturnDevice", "Drop sloperope", RETURN_POS,
		"DROP LINE", "", 1.4, false, 1.8, Interactable.InteractableType.HOLD_ACTION)
	ret.interacted.connect(func() -> void: _on_return_device())

# --- Wash cadence (scheduler-driven; fires at exact ticks) ---

func _ensure_scheduled() -> void:
	if _scheduled:
		return
	var sched = _get_scheduler()
	if sched == null:
		return
	_scheduled = true
	for i in range(SECTIONS.size()):
		sched.schedule_after(FIRST_FLOOD + float(SECTIONS[i]["phase"]), _make_onset(i), "wash_onset_%d" % i)

func _make_onset(i: int) -> Callable:
	return func() -> void: _flood_onset(i)

func _flood_onset(i: int) -> void:
	var sched = _get_scheduler()
	if _phase == "active" and not _section_disabled(i):
		_wash_section(i)
		_flooding[i] = true
		_set_strip(i, 2.6)
		if sched != null:
			sched.schedule_after(FLOOD_DURATION, func() -> void: _set_flood_off(i), "wash_off_%d" % i)
	if sched != null:
		sched.schedule_after(FLOW_PERIOD, _make_onset(i), "wash_onset_%d" % i)

func _set_flood_off(i: int) -> void:
	_flooding[i] = false
	_set_strip(i, 0.4)

func _section_disabled(i: int) -> bool:
	if bool(_override_locked[i]):
		return true
	if str(SECTIONS[i]["disable"]) == "plate":
		return _plate_held[i]
	return false

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
	if i < 0 or i >= _override_locked.size():
		return
	_override_locked[i] = true
	_set_flood_off(i)
	_set_strip(i, 0.15)
	_say("// SECTION %d FLOW // OVERRIDE ENGAGED" % (i + 1))

func _on_return_device() -> void:
	var n := _washed.size()
	for char_id in _washed.keys():
		_set_character_position(char_id, RETURN_LANDING)
	_washed.clear()
	if n > 0:
		_say("// LINE DROPPED // %d crew recovered" % n)

func _set_strip(i: int, energy: float) -> void:
	if i < _flow_strips.size() and is_instance_valid(_flow_strips[i]):
		var mat := _flow_strips[i].material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = energy

# --- Lifecycle ---

func _process(_delta: float) -> void:
	_update()

func headless_process(_delta: float) -> void:
	_update()

func _plate_x(i: int) -> float:
	return float(SECTIONS[i]["x0"]) - 1.2

func _update() -> void:
	if _phase == "ready":
		_phase = "active"
	_ensure_scheduled()
	# refresh plate-held state (a character standing on a plate disables that section while held)
	for i in range(SECTIONS.size()):
		if str(SECTIONS[i]["disable"]) != "plate":
			continue
		var held := false
		var px := _plate_x(i)
		for char_id in PARTY_IDS:
			if _washed.has(char_id):
				continue
			var p := _get_character_position(char_id)
			if abs(p.x - px) <= PLATE_RADIUS and abs(p.z) <= 1.6:
				held = true
				break
		if held != _plate_held[i]:
			_plate_held[i] = held
			_set_strip(i, 0.15 if held else 0.4)
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
	return "A gauntlet of timed water hazards on one cadence. Flush channels and jet nozzles wash you back to the start shelter; cross-current narrows and the sluice gate are pure timing; a held plate keeps the bridge for the party. Run an OVERRIDE for the flush/jet sections, hold the plate for the bridge, and time the rest."

func get_default_character() -> String:
	return "endo"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

func get_grid_data() -> Dictionary:
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [-2.0, 0.0, -6.0], "cell_size": 1.0, "width": 50, "height": 12,
		"walkable_regions": [{"min": [-1.0, -FLOOR_Z_HALF], "max": [48.0, FLOOR_Z_HALF]}],
	}

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors["start_shelter"] = START_POS
	anchors["chunk_end"] = Vector3(CHUNK_END_X + 1.0, 0.5, 0.0)
	anchors["return_device"] = RETURN_POS
	for i in range(SECTIONS.size()):
		anchors["section_%s" % SECTIONS[i]["type"]] = Vector3((float(SECTIONS[i]["x0"]) + float(SECTIONS[i]["x1"])) * 0.5, 0.5, 0.0)
	return anchors

func get_preview_time_state() -> Dictionary:
	return {"day": 2, "time": 0.5, "routing_mode": "safe",
		"note_default": "Read the flood beat. Override the flush/jet, hold the plate for the bridge, time the current and the sluice."}

func get_preview_abilities() -> Array:
	return []

func get_preview_overlay_status(_overlay_id: String, _current_tick: float) -> Array:
	return []

func reset_preview_state() -> void:
	var n := SECTIONS.size()
	_phase = "ready"
	_override_locked = []; _flooding = []; _plate_held = []
	for i in range(n):
		_override_locked.append(false); _flooding.append(false); _plate_held.append(false)
	_washed.clear()
	var gs = _get_game_state()
	if gs != null:
		for char_id in PARTY_IDS:
			if gs.characters.has(char_id):
				gs.snap_character_to(char_id, SPAWNS.get(char_id, START_POS))
	for i in range(_flow_strips.size()):
		_set_strip(i, 0.4)
	_set_preview_step("wash_relay_briefing")

func get_preview_state() -> Dictionary:
	var secs: Array = []
	for i in range(SECTIONS.size()):
		secs.append({"type": SECTIONS[i]["type"], "disable": SECTIONS[i]["disable"],
			"flooding": _flooding[i] if i < _flooding.size() else false,
			"disabled": _section_disabled(i), "overridden": _override_locked[i] if i < _override_locked.size() else false,
			"plate_held": _plate_held[i] if i < _plate_held.size() else false})
	return {
		"phase": _phase, "complete": _phase == "complete",
		"sections": secs, "section_count": SECTIONS.size(),
		"washed_count": _washed.size(), "washed": _washed.keys(),
		"flow_period": FLOW_PERIOD, "flood_duration": FLOOD_DURATION,
	}
