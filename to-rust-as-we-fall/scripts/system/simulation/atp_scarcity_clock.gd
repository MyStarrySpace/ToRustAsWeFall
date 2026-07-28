class_name AtpScarcityClock
extends RefCounted

## Reusable scheduler-backed pressure clock for the opt-in generated-stretch
## scarcity experiment. It owns timing and authoritative ATP/HP mutation only;
## scenes remain responsible for deciding when movement begins the clock and
## for presenting its feedback.

signal drained(total: float, per_character: Dictionary)
signal health_drained(total: float, per_character: Dictionary)
signal pressure_applied(
	atp_total: float,
	atp_per_character: Dictionary,
	hp_total: float,
	hp_per_character: Dictionary,
	absorbed_total: float,
	absorbed_per_character: Dictionary
)
signal pressure_started()

const DEFAULT_TAG := "generated_stretch_atp_scarcity"
const STATE_CONTRACT := "atp_scarcity_clock/v1"
const DEFAULT_INTERVAL_SECONDS := 60.0
const DEFAULT_DRAIN_ATP := 1.0
const DEFAULT_FLOOR_ATP := 0.0
const DEFAULT_ZERO_ATP_HP_DRAIN := 5.0
const MIN_INTERVAL_SECONDS := 5.0

var interval_seconds := DEFAULT_INTERVAL_SECONDS
var drain_atp := DEFAULT_DRAIN_ATP
var floor_atp := DEFAULT_FLOOR_ATP
var zero_atp_hp_drain := DEFAULT_ZERO_ATP_HP_DRAIN

var _scheduler = null
var _game_state = null
var _character_ids: Array[String] = []
var _tag := DEFAULT_TAG
var _ticks := 0
var _atp_drained := 0.0
var _hp_drained := 0.0
var _hp_absorbed := 0.0
var _started := false
var _running := false
var _armed := false
var _next_tick := -1.0
var _processing_tick := false
var _restoring := false


func configure(
		scheduler,
		game_state,
		character_ids: Array[String],
		settings: Dictionary = {},
		tag := DEFAULT_TAG
	) -> void:
	reset()
	_disconnect_game_state_signals()
	_scheduler = scheduler
	_game_state = game_state
	set_character_ids(character_ids)
	_tag = tag
	interval_seconds = maxf(
		MIN_INTERVAL_SECONDS,
		float(settings.get("drain_interval_seconds", DEFAULT_INTERVAL_SECONDS))
	)
	drain_atp = maxf(
		0.0,
		GameState.quantize_atp(float(settings.get("drain_atp", DEFAULT_DRAIN_ATP)))
	)
	zero_atp_hp_drain = maxf(
		0.0,
		float(settings.get("zero_atp_hp_drain", DEFAULT_ZERO_ATP_HP_DRAIN))
	)
	# Scarcity is explicitly allowed to exhaust ATP. HP pressure starts on a later
	# tick whose character began at zero, making the threshold and reaction window
	# deterministic rather than converting a partially consumed pip into damage.
	floor_atp = DEFAULT_FLOOR_ATP
	_connect_game_state_signals()


func set_character_ids(character_ids: Array[String]) -> void:
	_character_ids.clear()
	for raw_id in character_ids:
		var char_id := str(raw_id)
		if char_id != "" and not _character_ids.has(char_id):
			_character_ids.append(char_id)
	# A generated stretch can gain an active member after the existing roster has
	# exhausted every pressure target. Treat that just like a physical refill.
	if _started and _running and not _armed:
		_arm()


func begin() -> bool:
	if _started or _scheduler == null or _game_state == null or drain_atp <= 0.0:
		return false
	_started = true
	_running = true
	_arm()
	if _armed:
		pressure_started.emit()
	_publish_authoritative_state()
	return _armed


func stop() -> void:
	if _scheduler != null:
		_scheduler.cancel_tag(_tag)
	_running = false
	_armed = false
	_next_tick = -1.0
	_publish_authoritative_state()


func reset() -> void:
	stop()
	_ticks = 0
	_atp_drained = 0.0
	_hp_drained = 0.0
	_hp_absorbed = 0.0
	_started = false
	_processing_tick = false
	_publish_authoritative_state()


## Terminal lifecycle cleanup. `stop()` intentionally retains started=true so a
## successful shelter cannot re-arm the same run; `reset()` permits a restart,
## while `dispose()` also releases the GameState subscriptions.
func dispose() -> void:
	reset()
	_disconnect_game_state_signals()
	_scheduler = null
	_game_state = null
	_character_ids.clear()


func is_started() -> bool:
	return _started


func is_armed() -> bool:
	return _armed


func snapshot() -> Dictionary:
	var next_drain_in := -1.0
	if _armed and _scheduler != null and _next_tick >= 0.0:
		next_drain_in = maxf(0.0, _next_tick - float(_scheduler.get_current_tick()))
	return {
		"contract": STATE_CONTRACT,
		"interval_seconds": interval_seconds,
		"drain_per_character": drain_atp,
		"floor_per_character": floor_atp,
		"hp_drain_at_zero_per_character": zero_atp_hp_drain,
		"ticks": _ticks,
		"atp_drained": _atp_drained,
		"hp_drained": _hp_drained,
		"hp_absorbed": _hp_absorbed,
		"started": _started,
		"running": _running,
		"armed": _armed,
		"next_tick": _next_tick,
		"next_drain_in": next_drain_in,
		"tag": _tag,
		"character_ids": _character_ids.duplicate(),
	}


## Restore an active pressure clock from authoritative saved data. Scheduler Callables are derived:
## the snapshot carries the remaining interval and this method arms one fresh callback. It emits no
## synthetic gameplay signals and never grants a new full interval after a mid-tick reload.
func restore(snapshot_state: Dictionary) -> bool:
	if str(snapshot_state.get("contract", "")) != STATE_CONTRACT \
			or _scheduler == null or _game_state == null:
		return false
	var saved_interval := float(snapshot_state.get("interval_seconds", -1.0))
	var saved_drain := float(snapshot_state.get("drain_per_character", -1.0))
	var saved_floor := float(snapshot_state.get("floor_per_character", -1.0))
	var saved_hp_drain := float(snapshot_state.get("hp_drain_at_zero_per_character", -1.0))
	var saved_next_tick := float(snapshot_state.get("next_tick", -1.0))
	var saved_next := float(snapshot_state.get("next_drain_in", -1.0))
	if saved_interval < MIN_INTERVAL_SECONDS or saved_drain < 0.0 \
			or saved_floor < 0.0 or saved_hp_drain < 0.0 or saved_next < -1.0:
		return false

	_restoring = true
	if _scheduler != null:
		_scheduler.cancel_tag(_tag)
	_tag = str(snapshot_state.get("tag", _tag))
	interval_seconds = saved_interval
	drain_atp = GameState.quantize_atp(saved_drain)
	floor_atp = saved_floor
	zero_atp_hp_drain = saved_hp_drain
	var saved_character_ids: Array[String] = []
	for char_id_v in snapshot_state.get("character_ids", []):
		saved_character_ids.append(str(char_id_v))
	set_character_ids(saved_character_ids)
	_ticks = maxi(0, int(snapshot_state.get("ticks", 0)))
	_atp_drained = maxf(0.0, float(snapshot_state.get("atp_drained", 0.0)))
	_hp_drained = maxf(0.0, float(snapshot_state.get("hp_drained", 0.0)))
	_hp_absorbed = maxf(0.0, float(snapshot_state.get("hp_absorbed", 0.0)))
	_started = bool(snapshot_state.get("started", false))
	_running = bool(snapshot_state.get("running", _started))
	_armed = false
	_next_tick = -1.0
	_processing_tick = false

	if _started and _running and bool(snapshot_state.get("armed", false)):
		# Production GameState snapshots preserve the scheduler clock, so an absolute
		# deadline remains correct even if this world-state record was last published
		# when the interval was armed. Older standalone snapshots fall back to remaining.
		var remaining := (
			maxf(0.0, saved_next_tick - float(_scheduler.get_current_tick()))
			if saved_next_tick >= 0.0 else maxf(0.0, saved_next)
		)
		_next_tick = float(_scheduler.get_current_tick()) + remaining
		_scheduler.schedule_after(remaining, _on_tick, _tag)
		_armed = true
	_restoring = false
	return true


## Stable GameState key used by production saves. The RefCounted clock owns no independent
## persistence store; it publishes portable data into GameState and can rebuild from it after load.
func authority_state_key() -> String:
	return "simulation:atp_scarcity:%s" % _tag


func restore_from_authority() -> bool:
	if _game_state == null or not _game_state.has_method("get_world_state"):
		return false
	var saved: Variant = _game_state.get_world_state(authority_state_key(), null)
	return restore(saved as Dictionary) if saved is Dictionary else false


func _publish_authoritative_state() -> void:
	if _restoring or _game_state == null or not _game_state.has_method("set_world_state"):
		return
	_game_state.set_world_state(authority_state_key(), snapshot())


func _arm() -> void:
	if not _started or not _running or _scheduler == null or _game_state == null \
			or drain_atp <= 0.0 or not _has_pressure_target():
		return
	_scheduler.cancel_tag(_tag)
	_next_tick = float(_scheduler.get_current_tick()) + interval_seconds
	_scheduler.schedule_after(interval_seconds, _on_tick, _tag)
	_armed = true


func _has_pressure_target() -> bool:
	if _game_state == null:
		return false
	for char_id in _character_ids:
		if not _game_state.characters.has(char_id):
			continue
		if bool(_game_state.characters[char_id].stats.get("dead", false)):
			continue
		var atp := float(_game_state.get_stat(char_id, "atp"))
		var hp := float(_game_state.get_stat(char_id, "hp"))
		if atp > floor_atp or (atp <= floor_atp and zero_atp_hp_drain > 0.0 and hp > 0.0):
			return true
	return false


func _connect_game_state_signals() -> void:
	if _game_state == null:
		return
	var movement_callback := Callable(self, "_on_movement_started")
	if _game_state.has_signal("movement_started") \
			and not _game_state.is_connected("movement_started", movement_callback):
		_game_state.connect("movement_started", movement_callback)
	var stat_callback := Callable(self, "_on_stat_changed")
	if _game_state.has_signal("stat_changed") \
			and not _game_state.is_connected("stat_changed", stat_callback):
		_game_state.connect("stat_changed", stat_callback)


func _disconnect_game_state_signals() -> void:
	if _game_state == null:
		return
	var movement_callback := Callable(self, "_on_movement_started")
	if _game_state.has_signal("movement_started") \
			and _game_state.is_connected("movement_started", movement_callback):
		_game_state.disconnect("movement_started", movement_callback)
	var stat_callback := Callable(self, "_on_stat_changed")
	if _game_state.has_signal("stat_changed") \
			and _game_state.is_connected("stat_changed", stat_callback):
		_game_state.disconnect("stat_changed", stat_callback)


func _on_movement_started(char_id: String) -> void:
	if _character_ids.has(char_id):
		begin()


## When every tracked member is both ATP-empty and out of HP, the timer goes idle
## instead of scheduling permanent no-op work. A later physical ATP refill or HP
## restoration re-arms the same run without resetting its evidence counters.
func _on_stat_changed(char_id: String, stat: String, value: float) -> void:
	if _processing_tick or not _started or not _running or _armed \
			or stat not in ["atp", "hp"]:
		return
	if _character_ids.has(char_id) and value > 0.0:
		_arm()
		_publish_authoritative_state()


func _on_tick() -> void:
	_armed = false
	_next_tick = -1.0
	if not _started or not _running or _game_state == null:
		return
	_processing_tick = true
	var drained_by_character := {}
	var hp_drained_by_character := {}
	var hp_absorbed_by_character := {}
	var total := 0.0
	var hp_total := 0.0
	var absorbed_total := 0.0
	for char_id in _character_ids:
		if not _game_state.characters.has(char_id):
			continue
		if bool(_game_state.characters[char_id].stats.get("dead", false)):
			continue
		var before := float(_game_state.get_stat(char_id, "atp"))
		if before > floor_atp:
			var amount := minf(drain_atp, before - floor_atp)
			if amount > 0.0:
				_game_state.adjust_stat(char_id, "atp", -amount, _tag)
				drained_by_character[char_id] = amount
				total += amount
			continue
		if zero_atp_hp_drain <= 0.0:
			continue
		var hp_before := float(_game_state.get_stat(char_id, "hp"))
		if hp_before <= 0.0:
			continue
		var shield_before := float(_game_state.get_damage_shield(char_id)) \
				if _game_state.has_method("get_damage_shield") else 0.0
		_game_state.adjust_stat(char_id, "hp", -zero_atp_hp_drain, _tag)
		var shield_after := float(_game_state.get_damage_shield(char_id)) \
				if _game_state.has_method("get_damage_shield") else 0.0
		var absorbed_amount := maxf(0.0, shield_before - shield_after)
		if absorbed_amount > 0.0:
			hp_absorbed_by_character[char_id] = absorbed_amount
			absorbed_total += absorbed_amount
		var hp_amount := maxf(0.0, hp_before - float(_game_state.get_stat(char_id, "hp")))
		if hp_amount > 0.0:
			hp_drained_by_character[char_id] = hp_amount
			hp_total += hp_amount
	_processing_tick = false
	_ticks += 1
	_atp_drained += total
	_hp_drained += hp_total
	_hp_absorbed += absorbed_total
	if total > 0.0:
		drained.emit(total, drained_by_character)
	if hp_total > 0.0:
		health_drained.emit(hp_total, hp_drained_by_character)
	pressure_applied.emit(
		total,
		drained_by_character,
		hp_total,
		hp_drained_by_character,
		absorbed_total,
		hp_absorbed_by_character
	)
	_arm()
	_publish_authoritative_state()
