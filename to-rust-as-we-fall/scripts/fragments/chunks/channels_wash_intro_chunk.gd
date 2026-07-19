extends "res://scripts/fragments/chunks/data_fragment_chunk.gd"

## The CHANNELS WASH-INTRO — now DATA + thin behavior. The map, the spawnable objects (channels / capbages /
## flure / portals / guards / exit marker) and the logic knobs live in `channels_wash_intro.tres`; the
## DataFragmentChunk base COMPOSES them. This subclass holds ONLY the unique mechanics the data can't express:
## the wash DROWNS a lured guard, FLUSHES a player who stands in a flooding channel, Capbage concealment, and the
## win on reaching the exit — plus the dialogue beats. (CHANNELS_DESIGN.md "Entry teaching".)
##
## The teaching it stages: three phased channels (≥1 always flooding) you can't walk across; a FLURE whose reach
## is larger than the guards' player-sense, so lighting it pulls them into the wash to DROWN rather than at you; a
## CAPBAGE tight hide; and a PORTAL as the safe crossing once the guards are gone.

const FRAGMENT := preload("res://data/fragments/channels_wash_intro.tres")

# Act-1 slot wiring metadata (the region this fragment occupies in the campaign graph).
const WORLD_SLOT := {
	"slot_id": "act1_channels_wash_intro",
	"act": 1,
	"region": "Channels / Endo's Junction (wash intro)",
	"entry_shelter_id": "endo_junction",
	"exit_shelter_id": "channels_spiral_top",
	"canonical_party": ["aster", "peris", "endo"],
	"preview_party_preset": "full_party_full_health",
	"next_slot": "act1_channels_first_spiral",
}

var _drowned := 0
var _drowned_ids := {}                # char_id -> true: dedupe the drown (once per hunter, one line)
var _washed_back := 0                 # how many times a party member was flushed by a channel
var _last_outcome := ""
var _exit_waiting_notified := false   # one cue per partial gather; re-arms if everyone leaves
var _flure: Flure                     # cached from the loader's flures()[0]
var _portal_near: PortalPad           # cached from the loader's _portals (near bank / far bank)
var _portal_far: PortalPad

# Logic knobs read from the fragment's params (the .tres is the source of truth).
var _party_ids: Array = []
var _exit_pos := Vector3.ZERO
var _exit_radius := 3.75
var _wash_back := Vector3.ZERO
var _flure_attract := 32.0
var _enemy_detect := 4.0

func _build_chunk() -> void:
	fragment = FRAGMENT
	super._build_chunk()              # the loader builds the map + spawns every object from the data
	_party_ids = Array(fragment.party_ids)
	var p: Dictionary = fragment.params
	_exit_pos = p.get("exit_pos", _exit_pos)
	_exit_radius = float(p.get("exit_radius", _exit_radius))
	_wash_back = p.get("wash_back_pos", _wash_back)
	_flure_attract = float(p.get("flure_attract", _flure_attract))
	_enemy_detect = float(p.get("enemy_detect", _enemy_detect))
	# Wire the gameplay signals the loader leaves to the behavior (the beats + the lure reaction).
	if not _flures.is_empty():
		_flure = _flures[0]
		_flure.flure_activated.connect(_on_flure_activated)
	if _portals.size() >= 1:
		_portal_near = _portals[0]
	if _portals.size() >= 2:
		_portal_far = _portals[1]
	for prt in _portals:
		# A grouped crossing emits stepped_through once per member; interacted is
		# the single player command and therefore the right feedback boundary.
		prt.interacted.connect(_on_portal_interacted)
	for cap in _capbages:
		cap.tucked_in.connect(_on_capbage_tucked)
	reset_preview_state()

# --- Per-frame mechanics (the unique behavior; the loader/objects own everything else) ---

func _update(_delta: float) -> void:
	if _phase == "ready":
		_phase = "active"
	if _phase in ["complete", "failed"]:
		return
	_ensure_scheduled()               # the loader starts each Channel's flood cadence
	var gs = _get_game_state()
	if gs == null:
		return

	# Hide tiers are the LOADER's shared pass now (Capbage FULL > Scarpet MEDIUM > exposed).
	_update_shared_concealment()

	# Drown: guards caught in this update are announced together so a two-hunter
	# sweep reads as one result instead of a modal line per body.
	var drowned_names: Array[String] = []
	for enemy in _enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var ep: Vector3 = gs.get_position(enemy.char_id) if gs.characters.has(enemy.char_id) else enemy.position
		if _any_channel_floods_at(ep.x, ep.z):
			var drowned_name := _drown_enemy(enemy)
			if drowned_name != "":
				drowned_names.append(drowned_name)

	# Flush: a member standing in a flooding channel is swept back to the section start (snapping out clears the
	# footprint so it can't re-fire). The portal is the safe way across — the channels themselves are lethal.
	var washed_names: Array[String] = []
	for cid in _party_ids:
		if not gs.characters.has(cid):
			continue
		var mp := _get_character_position(cid)
		if _any_channel_floods_at(mp.x, mp.z):
			gs.command_stop(cid)
			_set_character_position(cid, _wash_back)
			_washed_back += 1
			washed_names.append(str(cid).capitalize())
	_announce_wash_results(drowned_names, washed_names)

	# Win: every hunter must have been taken by the wash, and the whole authored party
	# must be conscious and gathered at the far exit. Nobody advances alone.
	if _drowned < _enemies.size():
		return
	for cid in _party_ids:
		if not gs.characters.has(cid) or gs.is_downed(cid):
			return
	var at_exit := 0
	for cid in _party_ids:
		var fp := _get_character_position(cid)
		if Vector2(fp.x - _exit_pos.x, fp.z - _exit_pos.z).length() <= _exit_radius:
			at_exit += 1
	if at_exit < _party_ids.size():
		if at_exit == 0:
			_exit_waiting_notified = false
		elif not _exit_waiting_notified:
			_exit_waiting_notified = true
			_show_message("// EXIT // gather the whole party on the far pad", 2.4)
		return
	_complete()

func _any_channel_floods_at(x: float, z: float) -> bool:
	for ch in _channels:
		if is_instance_valid(ch) and ch.floods_at(x, z):
			return true
	return false

func _drown_enemy(enemy) -> String:
	if not is_instance_valid(enemy) or not enemy.is_alive():
		return ""
	# Dedupe: take_damage doesn't necessarily flip is_alive() the same frame, and the body can sit in the flooding
	# strip for a tick or two — without this the drown counted (and announced) twice.
	if _drowned_ids.has(enemy.char_id):
		return ""
	_drowned_ids[enemy.char_id] = true
	if enemy.has_method("take_damage"):
		enemy.take_damage(enemy.max_hp)   # die() doesn't zero hp; full damage downs it cleanly
	_drowned += 1
	var gs = _get_game_state()
	if gs != null and gs.characters.has(enemy.char_id):
		gs.set_character_distracted(enemy.char_id, false)
	return "Hunter %d" % (_enemies.find(enemy) + 1)

func _announce_wash_results(drowned_names: Array[String], washed_names: Array[String]) -> void:
	var results: Array[String] = []
	if not drowned_names.is_empty():
		results.append("%s swept away" % ", ".join(drowned_names))
	if not washed_names.is_empty():
		results.append("%s swept back to shelter" % ", ".join(washed_names))
	if not results.is_empty():
		_show_message("// WASH // %s" % "  |  ".join(results), 2.4)

## Force channel `i` to flood now — scripted beats / tests. (The cadence itself lives in the Channel object.)
func _channel_onset(i: int) -> void:
	if _phase in ["complete", "failed"]:
		return
	if i >= 0 and i < _channels.size() and is_instance_valid(_channels[i]):
		_channels[i].flood_now()

# --- Beats ---

## Light the flure (the lure logic lives in the Flure object; this gates on phase + delegates). Kept for the
## data-layer playthrough + tests that trigger it by name. The Flure also self-fires on a real click.
func activate_flure() -> bool:
	if _phase in ["complete", "failed"] or _flure == null:
		return false
	return _flure.activate()

func _on_flure_activated(_pulled: int) -> void:
	if _phase in ["complete", "failed"]:
		return
	_last_outcome = "flure_lit"
	_set_preview_step("channels_wash_intro_flure")
	_show_message("// FLURE // signal up — the hunters lock onto it", 2.2)

func _on_portal_interacted() -> void:
	if _phase in ["complete", "failed"]:
		return
	_show_message("// PORTAL // crossing queued", 1.6)

func _on_capbage_tucked() -> void:
	_show_message("// HIDE // tucked into the Capbage", 1.6)

func _complete() -> void:
	if _phase == "complete":
		return
	_phase = "complete"
	_last_outcome = "complete"
	_quiesce_channels()
	_set_preview_step("channels_wash_intro_complete")
	_say("Across. The spiral's below us now.", "ASTER")
	_request_preview_handoff("wash_relay")

## Completion and preview teardown both leave the host scheduler alive. Retract the
## Channel-owned recurring callbacks and hide their water so a cleared room never keeps
## presenting a flood that can no longer affect anything.
func _quiesce_channels() -> void:
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(_restart_tag())
	for ch in _channels:
		if is_instance_valid(ch):
			ch.reset()
	_scheduled = false

## The data-loader restart restores/re-posts actors and preserves the runback count/decor.
## Reset only this subclass's per-run mechanics afterward so an in-flight Channel flood
## cannot survive the wipe and immediately wash the restored party again.
func _restart_fragment() -> void:
	super._restart_fragment()
	_quiesce_channels()
	_drowned = 0
	_drowned_ids = {}
	_washed_back = 0
	_last_outcome = ""
	_exit_waiting_notified = false

func _exit_tree() -> void:
	_quiesce_channels()
	super._exit_tree()

# --- Scene chunk interface (title/help/spawns/grid/time come from the fragment via the base) ---

func get_world_slot() -> Dictionary:
	return WORLD_SLOT.duplicate(true)

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	if fragment != null:
		anchors.merge((fragment.params.get("anchors", {}) as Dictionary), true)
	return anchors

func reset_preview_state() -> void:
	super.reset_preview_state()       # resets flures + channels + scheduling, sets the start step
	_quiesce_channels()               # also retracts any pending full-wipe restart callback
	_phase = "ready"
	_drowned = 0
	_drowned_ids = {}
	_washed_back = 0
	_last_outcome = ""
	_exit_waiting_notified = false

func get_preview_state() -> Dictionary:
	var any_flooding := false
	var flooding: Array = []
	for ch in _channels:
		var f: bool = is_instance_valid(ch) and ch.is_flooding()
		flooding.append(f)
		if f:
			any_flooding = true
	var enemies_alive := 0
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.is_alive():
			enemies_alive += 1
	return {
		"phase": _phase,
		"complete": _phase == "complete",
		"flure_active": _flure.is_active() if _flure != null else false,
		"any_channel_flooding": any_flooding,
		"flooding": flooding,
		"drowned": _drowned,
		"enemies_alive": enemies_alive,
		"flure_attract_range": _flure_attract,
		"player_sense_range": _enemy_detect,
		"last_outcome": _last_outcome,
		"exit_waiting_notified": _exit_waiting_notified,
	}
