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
const ExitFixedCadenceScript := preload("res://scripts/system/core/fixed_cadence.gd")
const WASH_INTRO_AUTHORITY_VERSION := 2
const ENEMY_WASH_DAMAGE := 100000.0
const ENEMY_WASH_EDGE_Z := 6.35
const EXIT_SPATIAL_INTERVAL := 0.1

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
var _exit_spatial_epoch := -1.0       # fixed cadence for the whole-party exit predicate
var _next_exit_spatial_tick := -1.0
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
	_configure_channel_sweeps()
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

# --- Presenter update (gameplay consequences remain scheduler-owned) ---

func _update(_delta: float) -> void:
	if _phase == "ready":
		_phase = "active"
	if _phase in ["complete", "failed"]:
		return
	_ensure_scheduled()               # the loader starts each Channel's flood cadence

	# Hide tiers are the LOADER's shared pass now (Capbage FULL > Scarpet MEDIUM > exposed).
	_update_shared_concealment()

func _any_channel_floods_at(x: float, z: float) -> bool:
	for ch in _channels:
		if is_instance_valid(ch) and ch.floods_at(x, z):
			return true
	return false

## Attach policy to the visible Channel kit. The kit owns stopping, carrying, damage, refractory,
## and saved cadence; these callbacks only update this room's saved counters and feedback.
func _configure_channel_sweeps() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for channel in _channels:
		if not is_instance_valid(channel) or not channel.has_method("set_sweep"):
			continue
		channel.set_sweep(gs, _party_ids, _wash_destination, {
			"party_hp": 0.0,
			"enemy_damage": ENEMY_WASH_DAMAGE,
			"enemy_stun": 0.0,
			"refractory": 4.0,
			"enemy_resolver": _enemy_for_id,
			"on_swept": _on_party_channel_swept,
			"on_enemy_swept": _on_enemy_channel_swept,
		})

func _wash_destination(char_id: String, position: Vector3) -> Vector3:
	if char_id in _party_ids:
		# `_wash_back` is authored as gameplay feet data, not the half-unit
		# presentation height used by nearby props. Re-derive its graph floor at
		# consequence time so a stale visual-height baseline cannot wash a body
		# between navigation levels.
		var gs = _get_game_state()
		if gs != null and gs.grid != null:
			var level: int = gs.grid.level_for_y(_wash_back.y)
			var cell: Vector2i = gs.grid.nearest_walkable_cell(
				gs.grid.world_to_grid(_wash_back), level)
			if gs.grid.is_in_bounds(cell.x, cell.y) \
					and gs.grid.is_walkable(cell.x, cell.y, {}, {}, level):
				var graph_position: Vector3 = gs.grid.grid_to_world(cell, level)
				return Vector3(_wash_back.x, graph_position.y, _wash_back.z)
		return _wash_back
	var downstream_sign := signf(position.z)
	if is_zero_approx(downstream_sign):
		downstream_sign = 1.0
	return Vector3(position.x, 0.5, downstream_sign * ENEMY_WASH_EDGE_Z)

func _enemy_for_id(char_id: String):
	for enemy in _enemies:
		if is_instance_valid(enemy) and str(enemy.char_id) == char_id:
			return enemy
	return null


func _hunter_has_physical_wash_result(char_id: String) -> bool:
	var enemy = _enemy_for_id(char_id)
	var gs = _get_game_state()
	if enemy == null or gs == null or not gs.characters.has(char_id) \
			or not _hunter_has_dead_authority(char_id):
		return false
	var body_position: Vector3 = gs.get_position(char_id)
	return body_position.is_finite() \
		and absf(body_position.z) >= ENEMY_WASH_EDGE_Z - 0.01


## Enemy nodes are presenters during restore and may receive their attachment callback after this
## chunk. Read the already-deserialized GameState record so a fresh load cannot discard a valid
## drown receipt merely because the Enemy node still shows its construction-default live pose.
func _hunter_has_dead_authority(char_id: String) -> bool:
	var gs = _get_game_state()
	if gs == null or not gs.has_method("get_world_state"):
		return false
	var raw: Variant = gs.get_world_state("runtime:enemy:%s" % char_id, null)
	if not raw is Dictionary:
		return false
	var saved := raw as Dictionary
	return int(saved.get("version", 0)) == 1 \
		and str(saved.get("char_id", "")) == char_id \
		and str(saved.get("state", "")) == "dead" \
		and float(saved.get("hp", 1.0)) <= 0.0


func _all_hunters_physically_drowned() -> bool:
	if _enemies.is_empty() or _drowned_ids.size() != _enemies.size():
		return false
	for enemy in _enemies:
		if not is_instance_valid(enemy):
			return false
		var char_id := str(enemy.char_id)
		if not _drowned_ids.has(char_id) or not _hunter_has_physical_wash_result(char_id):
			return false
	return true


## Whole-party exit truth is sampled only on this saved scheduler cadence. Render frames and
## manually invoked headless presenters can project the room, but cannot discover or complete
## an exit. The future edge is published before each predicate read so a signal-time save
## reconstructs one later poll rather than replaying the callback currently being consumed.
func _restart_exit_spatial_authority() -> void:
	var scheduler = _get_scheduler()
	_cancel_exit_spatial_authority_callback()
	if scheduler == null:
		_exit_spatial_epoch = -1.0
		_next_exit_spatial_tick = -1.0
		return
	var now := float(scheduler.get_current_tick())
	_exit_spatial_epoch = now
	_next_exit_spatial_tick = ExitFixedCadenceScript.next_strict_tick(
		_exit_spatial_epoch, EXIT_SPATIAL_INTERVAL, now)
	_publish_fragment_authority()
	_arm_exit_spatial_authority(_next_exit_spatial_tick)


func _arm_exit_spatial_authority(deadline: float) -> void:
	var scheduler = _get_scheduler()
	if scheduler == null or deadline <= float(scheduler.get_current_tick()):
		return
	scheduler.cancel_tag(_exit_spatial_authority_tag())
	scheduler.schedule_at(
		deadline,
		_exit_spatial_authority_tick.bind(deadline),
		_exit_spatial_authority_tag())


func _exit_spatial_authority_tick(expected_tick: float) -> void:
	if not is_equal_approx(_next_exit_spatial_tick, expected_tick):
		return
	if _phase in ["complete", "failed"]:
		_stop_exit_spatial_authority()
		_publish_fragment_authority()
		return
	var now := _get_scheduler_tick()
	_next_exit_spatial_tick = ExitFixedCadenceScript.next_strict_tick(
		_exit_spatial_epoch, EXIT_SPATIAL_INTERVAL, now)
	_publish_fragment_authority()
	_evaluate_exit_spatial_authority()
	if _phase in ["complete", "failed"]:
		return
	_arm_exit_spatial_authority(_next_exit_spatial_tick)
	_publish_fragment_authority()


func _evaluate_exit_spatial_authority() -> void:
	var gs = _get_game_state()
	if gs == null or not _all_hunters_physically_drowned():
		return
	for cid_v in _party_ids:
		var cid := str(cid_v)
		if not gs.characters.has(cid) or gs.is_downed(cid):
			return
	var at_exit := 0
	for cid_v in _party_ids:
		var cid := str(cid_v)
		var position := _get_character_position(cid)
		if Vector2(
			position.x - _exit_pos.x,
			position.z - _exit_pos.z
		).length() <= _exit_radius:
			at_exit += 1
	if at_exit < _party_ids.size():
		if at_exit == 0:
			if _exit_waiting_notified:
				_exit_waiting_notified = false
				_publish_fragment_authority()
		elif not _exit_waiting_notified:
			_exit_waiting_notified = true
			_publish_fragment_authority()
			_show_message("// EXIT // gather the whole party on the far pad", 2.4)
		return
	_complete()


func _exit_spatial_authority_tag() -> String:
	return "channels_wash_intro_exit:%s" % (
		_fragment_authority_key().sha256_text().substr(0, 12)
	)


func _cancel_exit_spatial_authority_callback() -> void:
	var scheduler = _get_scheduler()
	if scheduler != null:
		scheduler.cancel_tag(_exit_spatial_authority_tag())


func _stop_exit_spatial_authority() -> void:
	_cancel_exit_spatial_authority_callback()
	_exit_spatial_epoch = -1.0
	_next_exit_spatial_tick = -1.0


func _restore_exit_spatial_authority(saved: Dictionary, saved_version: int) -> bool:
	_cancel_exit_spatial_authority_callback()
	if _phase in ["complete", "failed"]:
		var terminal_normalized := _exit_spatial_epoch >= 0.0 or _next_exit_spatial_tick >= 0.0
		_exit_spatial_epoch = -1.0
		_next_exit_spatial_tick = -1.0
		return terminal_normalized
	var now := _get_scheduler_tick()
	var normalized := saved_version < WASH_INTRO_AUTHORITY_VERSION
	if saved_version >= 2:
		_exit_spatial_epoch = float(saved.get("exit_spatial_epoch", -1.0))
		_next_exit_spatial_tick = float(saved.get("next_exit_spatial_tick", -1.0))
	else:
		_exit_spatial_epoch = now
		_next_exit_spatial_tick = ExitFixedCadenceScript.next_strict_tick(
			_exit_spatial_epoch, EXIT_SPATIAL_INTERVAL, now)
	if not is_finite(_exit_spatial_epoch) or _exit_spatial_epoch < 0.0 \
			or not is_finite(_next_exit_spatial_tick) \
			or _next_exit_spatial_tick <= now:
		_exit_spatial_epoch = now
		_next_exit_spatial_tick = ExitFixedCadenceScript.next_strict_tick(
			_exit_spatial_epoch, EXIT_SPATIAL_INTERVAL, now)
		normalized = true
	_arm_exit_spatial_authority(_next_exit_spatial_tick)
	return normalized


func _on_party_channel_swept(char_id: String) -> void:
	if not (char_id in _party_ids):
		return
	_washed_back += 1
	_last_outcome = "party_swept:%s" % char_id
	_publish_fragment_authority()
	_announce_wash_results([], [char_id.capitalize()])

func _on_enemy_channel_swept(char_id: String) -> void:
	if _drowned_ids.has(char_id):
		return
	if not _hunter_has_physical_wash_result(char_id):
		return
	_drowned_ids[char_id] = true
	_drowned = _drowned_ids.size()
	_last_outcome = "hunter_swept:%s" % char_id
	_publish_fragment_authority()
	_announce_wash_results([_hunter_label(char_id)], [])

func _hunter_label(char_id: String) -> String:
	for idx in range(_enemies.size()):
		var enemy = _enemies[idx]
		if is_instance_valid(enemy) and str(enemy.char_id) == char_id:
			return "Hunter %d" % (idx + 1)
	return "Hunter"

## Dedupe is now the saved on-arrival bookkeeping above; there is deliberately no direct-drown helper.

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

## Retired compatibility seam. A wash can only start from the exact Flure Interactable accepting
## the staged body; callers may observe `flure_activated`, never synthesize that physical cause.
func activate_flure() -> bool:
	return false

func _on_flure_activated(_pulled: int) -> void:
	if _phase in ["complete", "failed"]:
		return
	_last_outcome = "flure_lit"
	_publish_fragment_authority()
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
	_stop_exit_spatial_authority()
	_quiesce_channels()
	_publish_fragment_authority()
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
	_stop_exit_spatial_authority()
	super._restart_fragment()
	_quiesce_channels()
	_drowned = 0
	_drowned_ids = {}
	_washed_back = 0
	_last_outcome = ""
	_exit_waiting_notified = false
	_restart_exit_spatial_authority()

func _exit_tree() -> void:
	_stop_exit_spatial_authority()
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
	_stop_exit_spatial_authority()
	super.reset_preview_state()       # resets flures + channels + scheduling, sets the start step
	_quiesce_channels()               # also retracts any pending full-wipe restart callback
	_phase = "ready"
	_drowned = 0
	_drowned_ids = {}
	_washed_back = 0
	_last_outcome = ""
	_exit_waiting_notified = false
	_configure_channel_sweeps()
	_restart_exit_spatial_authority()

## Extend the loader's versioned record instead of keeping another scene-local truth. Enemy FSM/HP
## and Channel cadence have their own kit records; this payload owns only room-level bookkeeping.
func _fragment_authority_state() -> Dictionary:
	var state: Dictionary = super._fragment_authority_state()
	var drowned_ids: Array = _drowned_ids.keys()
	drowned_ids.sort()
	state["wash_intro"] = {
		"version": WASH_INTRO_AUTHORITY_VERSION,
		"drowned_ids": drowned_ids,
		"washed_back": _washed_back,
		"last_outcome": _last_outcome,
		"exit_waiting_notified": _exit_waiting_notified,
		"exit_spatial_epoch": _exit_spatial_epoch,
		"next_exit_spatial_tick": _next_exit_spatial_tick,
	}
	return state

func on_game_state_snapshot_restored() -> void:
	_cancel_exit_spatial_authority_callback()
	super.on_game_state_snapshot_restored()
	var gs = _get_game_state()
	var raw: Variant = gs.get_world_state(_fragment_authority_key(), null) \
			if gs != null and gs.has_method("get_world_state") else null
	if not raw is Dictionary:
		_retract_wash_intro_bookkeeping()
		return
	var saved: Variant = (raw as Dictionary).get("wash_intro", null)
	if not saved is Dictionary:
		_restore_legacy_drowned_ids()
		if _restore_exit_spatial_authority({}, 0):
			_publish_fragment_authority()
		return
	var saved_intro := saved as Dictionary
	var saved_version := int(saved_intro.get("version", 0))
	if saved_version not in [1, WASH_INTRO_AUTHORITY_VERSION]:
		_restore_legacy_drowned_ids()
		if _restore_exit_spatial_authority({}, 0):
			_publish_fragment_authority()
		return
	_drowned_ids.clear()
	for id_v in (saved_intro.get("drowned_ids", []) as Array):
		var char_id := str(id_v)
		# The room record is provenance, not a substitute body. Reject edited or signal-seam
		# bookkeeping unless the same stable Enemy is dead at the downstream wash endpoint.
		if _hunter_has_physical_wash_result(char_id):
			_drowned_ids[char_id] = true
	_drowned = _drowned_ids.size()
	_washed_back = maxi(0, int(saved_intro.get("washed_back", 0)))
	_last_outcome = str(saved_intro.get("last_outcome", ""))
	_exit_waiting_notified = bool(saved_intro.get("exit_waiting_notified", false))
	if _restore_exit_spatial_authority(saved_intro, saved_version):
		_publish_fragment_authority()

func _retract_fragment_presenter_to_defaults() -> void:
	super._retract_fragment_presenter_to_defaults()
	_retract_wash_intro_bookkeeping()

func _retract_wash_intro_bookkeeping() -> void:
	_stop_exit_spatial_authority()
	_drowned = 0
	_drowned_ids.clear()
	_washed_back = 0
	_last_outcome = ""
	_exit_waiting_notified = false

func _restore_legacy_drowned_ids() -> void:
	_retract_wash_intro_bookkeeping()
	var gs = _get_game_state()
	if gs == null:
		return
	for enemy in _enemies:
		if not is_instance_valid(enemy):
			continue
		var char_id := str(enemy.char_id)
		if _hunter_has_physical_wash_result(char_id):
			_drowned_ids[char_id] = true
	_drowned = _drowned_ids.size()

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
		"drowned_ids": _drowned_ids.keys(),
		"washed_back": _washed_back,
		"enemies_alive": enemies_alive,
		"flure_attract_range": _flure_attract,
		"player_sense_range": _enemy_detect,
		"last_outcome": _last_outcome,
		"exit_waiting_notified": _exit_waiting_notified,
		"exit_spatial_epoch": _exit_spatial_epoch,
		"next_exit_spatial_tick": _next_exit_spatial_tick,
		"exit_spatial_interval": EXIT_SPATIAL_INTERVAL,
	}
