extends SceneTree

## Focused proof for IronPurgeReceiver. This uses a real TypedTerminal and real Enemy FSMs so the
## spent source receipt, transaction seams, deferred lure, and snapshot restoration share the
## production authority paths.

const ReceiverScript := preload("res://scripts/game/objects/iron_purge_receiver.gd")
const TerminalScript := preload("res://scripts/game/objects/typed_terminal.gd")

const RECEIVER_ID := "verify_archive_iron_purge"
const TERMINAL_ID := "verify_archive_iron_terminal"
const ENEMY_AVAILABLE := "verify_sapscrap_available"
const ENEMY_COMMITTED := "verify_sapscrap_committed"
const LURE_DURATION := 3.0

var checks := 0
var failures := 0
var scheduler: EventScheduler
var game_state: GameState
var host: Node3D
var receiver
var terminal
var enemy_available: Enemy
var enemy_committed: Enemy
var fixture_retracted := Vector3.ZERO
var fixture_exposed := Vector3.ZERO
var baseline_state: Dictionary = {}
var baseline_scheduler: Dictionary = {}
var exposed_seam_state: Dictionary = {}
var exposed_seam_scheduler: Dictionary = {}
var applying_seam_state: Dictionary = {}
var applying_seam_scheduler: Dictionary = {}
var pending_state: Dictionary = {}
var pending_scheduler: Dictionary = {}
var fixture_commit_signals := 0
var target_lured_signals := 0
var command_gate_checked := false
var fixture_signal_enemy_states: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _build_fixture()
	_verify_binding_contract()
	_verify_exact_terminal_and_deferred_lure()
	_verify_pending_deadline_restore()
	_verify_applying_seam_restore()
	_verify_completed_restore_idempotence()
	_verify_snapshot_absence_retracts_future()
	print("IRON PURGE RECEIVER: %d checks, %d failures" % [checks, failures])
	host.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures > 0 else 0)


func _build_fixture() -> void:
	scheduler = EventScheduler.new()
	game_state = GameState.new()
	game_state.scheduler = scheduler
	game_state.grid = GridWorld.new()
	game_state.grid.create_room(24, 14, true)
	var actor_position := _cell(2, 2)
	var available_position := _cell(7, 4)
	var committed_position := _cell(7, 9)
	fixture_retracted = _cell(19, 7)
	fixture_exposed = _cell(14, 7)
	game_state.register_character("aster", actor_position, 3.0, {"hp": 100.0})
	game_state.register_character(
		ENEMY_AVAILABLE,
		available_position,
		2.0,
		{"hp": 50.0}
	)
	game_state.register_character(
		ENEMY_COMMITTED,
		committed_position,
		2.0,
		{"hp": 50.0}
	)
	host = Node3D.new()
	root.add_child(host)
	enemy_available = _make_enemy(ENEMY_AVAILABLE, available_position)
	enemy_committed = _make_enemy(ENEMY_COMMITTED, committed_position)
	host.add_child(enemy_available)
	host.add_child(enemy_committed)
	await process_frame
	enemy_available.activate()
	enemy_committed.activate()
	enemy_available.set_detection_targets([])
	enemy_committed.set_detection_targets([])
	enemy_committed.call("_change_state", "alert")

	receiver = ReceiverScript.new()
	host.add_child(receiver)
	check(receiver.configure(
			game_state,
			RECEIVER_ID,
			TERMINAL_ID,
			fixture_retracted,
			fixture_exposed,
			Vector3(2.4, 1.8, 1.8),
			[ENEMY_AVAILABLE, ENEMY_COMMITTED],
			LURE_DURATION
		),
		"receiver configures one measured physical fixture and stable target plan")
	check(
		receiver.bind_enemy(enemy_available) and receiver.bind_enemy(enemy_committed),
		"receiver binds both real Enemy presenters by char_id"
	)
	receiver.fixture_exposed_committed.connect(_on_fixture_committed)
	receiver.target_lured.connect(_on_target_lured)
	game_state.world_state_changed.connect(_capture_receiver_seams)

	terminal = TerminalScript.new()
	host.add_child(terminal)
	check(terminal.configure(
			game_state,
			actor_position,
			TERMINAL_ID,
			"signal",
			receiver,
			"aster",
			1.5
		),
		"real TypedTerminal configures the exact signal/lure source")
	terminal.terminal_command_committed.connect(_verify_command_gate)
	baseline_scheduler = _round_trip(scheduler.serialize())
	baseline_state = _round_trip(game_state.serialize())


func _verify_binding_contract() -> void:
	var wrong_id := Enemy.new()
	wrong_id.char_id = "not_authored"
	wrong_id.game_state = game_state
	check(not receiver.bind_enemy(wrong_id),
		"binding rejects an Enemy whose char_id is not in the authored target plan")
	var foreign_state := GameState.new()
	foreign_state.scheduler = EventScheduler.new()
	var foreign := Enemy.new()
	foreign.char_id = ENEMY_AVAILABLE
	foreign.game_state = foreign_state
	check(not receiver.bind_enemy(foreign),
		"binding rejects a matching char_id owned by another GameState")
	wrong_id.free()
	foreign.free()


func _verify_exact_terminal_and_deferred_lure() -> void:
	var forged := {
		"family": "terminal",
		"subtype": "signal",
		"effect": "lure",
		"source_id": terminal.terminal_source_id(),
		"source_authority_key": terminal.authority_state_key(),
		"source_trigger_count": 1,
		"actor": "aster",
		"source_position": _vector_data(game_state.get_position("aster")),
		"accepted_tick": scheduler.get_current_tick(),
	}
	check(not receiver.can_accept_terminal_command(forged),
		"a command dictionary cannot replace the unspent physical source receipt")
	terminal.active_character = "aster"
	check(bool(terminal.call("_trigger", false)),
		"ordinary TypedTerminal trigger consumes and delivers its one-shot receipt")
	check(command_gate_checked,
		"terminal commit edge exercised every exact command-field rejection")
	check(
		str(receiver.get_state().get("phase", "")) == receiver.PHASE_EXPOSED
			and receiver.get_fixture_visual().global_position.is_equal_approx(fixture_exposed),
		"accepted receipt commits and physically exposes the sacrificial iron fixture"
	)
	check(
		receiver.get_fixture_visual().find_child("CollisionShape3D", true, false)
			is CollisionShape3D,
		"exposed iron is a visible fixture with physical collision, not a marker")
	check(
		str(fixture_signal_enemy_states.get(ENEMY_AVAILABLE, "")) == "idle"
			and str(fixture_signal_enemy_states.get(ENEMY_COMMITTED, "")) == "alert",
		"fixture commit signal occurs before either Enemy FSM is touched")
	check(
		not exposed_seam_state.is_empty()
			and _snapshot_enemy_state(exposed_seam_state, ENEMY_AVAILABLE) == "idle"
			and _snapshot_enemy_state(exposed_seam_state, ENEMY_COMMITTED) == "alert",
		"save seam contains the complete exposed cause before any enemy consequence")
	check(
		_target_status(ENEMY_AVAILABLE) == receiver.TARGET_APPLIED
			and enemy_available.get_state() == "lured"
			and game_state.is_character_distracted(ENEMY_AVAILABLE),
		"available Sapscrap accepts the proven lure immediately")
	check(
		_target_status(ENEMY_COMMITTED) == receiver.TARGET_PENDING
			and enemy_committed.get_state() == "alert"
			and float(receiver.get_state().get("next_reconcile_deadline", -1.0))
				> scheduler.get_current_tick(),
		"temporarily committed Sapscrap retains a saved retry deadline")
	check(not applying_seam_state.is_empty()
			and _snapshot_enemy_state(applying_seam_state, ENEMY_AVAILABLE) == "idle",
		"per-target applying receipt commits before Enemy.lure_to")
	pending_scheduler = _round_trip(scheduler.serialize())
	pending_state = _round_trip(game_state.serialize())
	scheduler.advance_ticks(1.3)
	check(
		_target_status(ENEMY_COMMITTED) == receiver.TARGET_APPLIED
			and enemy_committed.get_state() == "lured"
			and game_state.is_character_distracted(ENEMY_COMMITTED)
			and float(receiver.get_state().get("next_reconcile_deadline", 0.0)) < 0.0,
		"deterministic retry lures the deferred target when its FSM becomes available")
	var accepted_command := terminal.get_state().get("command", {}) as Dictionary
	check(not receiver.accept_terminal_command(accepted_command),
		"spent purge command cannot activate the receiver twice")


func _verify_pending_deadline_restore() -> void:
	scheduler.clear()
	scheduler.deserialize(pending_scheduler)
	game_state.deserialize(pending_state)
	enemy_available.on_game_state_snapshot_restored()
	enemy_committed.on_game_state_snapshot_restored()
	terminal.on_game_state_snapshot_restored()
	check(receiver.on_game_state_snapshot_restored(),
		"pending-target snapshot restores receiver authority")
	var restored_deadline := float(
		receiver.get_state().get("next_reconcile_deadline", -1.0)
	)
	check(is_equal_approx(restored_deadline, 0.1),
		"pending restore preserves the exact absolute retry deadline")
	scheduler.advance_ticks(0.099)
	check(_target_status(ENEMY_COMMITTED) == receiver.TARGET_PENDING
			and is_equal_approx(
				float(receiver.get_state().get("next_reconcile_deadline", -1.0)),
				restored_deadline
			),
		"deferred target is not reconciled before its saved deadline")
	scheduler.advance_ticks(0.001)
	check(_target_status(ENEMY_COMMITTED) == receiver.TARGET_PENDING
			and float(receiver.get_state().get("next_reconcile_deadline", -1.0))
				> restored_deadline,
		"saved deadline fires once and publishes the next deterministic retry")


func _verify_applying_seam_restore() -> void:
	var commit_signals_before := fixture_commit_signals
	scheduler.clear()
	scheduler.deserialize(applying_seam_scheduler)
	game_state.deserialize(applying_seam_state)
	enemy_available.on_game_state_snapshot_restored()
	enemy_committed.on_game_state_snapshot_restored()
	terminal.on_game_state_snapshot_restored()
	check(receiver.on_game_state_snapshot_restored(),
		"applying-seam restore accepts its own receiver authority")
	check(receiver.on_game_state_snapshot_restored(),
		"repeated applying-seam attachment remains valid")
	check(
		fixture_commit_signals == commit_signals_before
			and receiver.get_fixture_visual().global_position.is_equal_approx(fixture_exposed),
		"restore reconstructs the physical cause without replaying the terminal signal")
	check(
		_target_status(ENEMY_AVAILABLE) == receiver.TARGET_PENDING
			and enemy_available.get_state() == "idle",
		"torn applying receipt repairs to pending when Enemy authority has no lure")
	scheduler.advance_ticks(0.01)
	check(
		_target_status(ENEMY_AVAILABLE) == receiver.TARGET_APPLIED
			and enemy_available.get_state() == "lured",
		"restored retry applies the missing lure exactly once")
	scheduler.advance_ticks(1.3)
	check(
		_target_status(ENEMY_COMMITTED) == receiver.TARGET_APPLIED
			and enemy_committed.get_state() == "lured",
		"restored committed target remains pending until its original FSM releases")


func _verify_completed_restore_idempotence() -> void:
	var completed_scheduler := _round_trip(scheduler.serialize())
	var completed_state := _round_trip(game_state.serialize())
	var fixture_signals_before := fixture_commit_signals
	var lure_signals_before := target_lured_signals
	receiver.get_fixture_visual().position = Vector3.ZERO
	enemy_available.call("_change_state", "idle")
	scheduler.clear()
	scheduler.deserialize(completed_scheduler)
	game_state.deserialize(completed_state)
	enemy_available.on_game_state_snapshot_restored()
	enemy_committed.on_game_state_snapshot_restored()
	terminal.on_game_state_snapshot_restored()
	check(receiver.on_game_state_snapshot_restored(),
		"completed purge authority restores on the same presenter")
	check(receiver.on_game_state_snapshot_restored(),
		"completed purge authority tolerates repeated attachment")
	check(
		receiver.get_fixture_visual().global_position.is_equal_approx(fixture_exposed)
			and _target_status(ENEMY_AVAILABLE) == receiver.TARGET_APPLIED
			and _target_status(ENEMY_COMMITTED) == receiver.TARGET_APPLIED,
		"completed save restores fixture and both target receipts from GameState truth")
	check(
		fixture_commit_signals == fixture_signals_before
			and target_lured_signals == lure_signals_before,
		"completed restore emits no synthetic terminal or lure consequence")


func _verify_snapshot_absence_retracts_future() -> void:
	var fixture_signals_before := fixture_commit_signals
	scheduler.clear()
	scheduler.deserialize(baseline_scheduler)
	game_state.deserialize(baseline_state)
	enemy_available.on_game_state_snapshot_restored()
	enemy_committed.on_game_state_snapshot_restored()
	terminal.on_game_state_snapshot_restored()
	check(receiver.on_game_state_snapshot_restored(),
		"baseline snapshot restores valid retracted receiver authority")
	check(
		str(receiver.get_state().get("phase", "")) == receiver.PHASE_RETRACTED
			and receiver.get_fixture_visual().global_position.is_equal_approx(
				fixture_retracted
			),
		"rollback retracts the future iron fixture instead of retaining presentation state")
	check(
		terminal.is_interaction_enabled()
			and fixture_commit_signals == fixture_signals_before,
		"rollback rearms its exact terminal source without emitting a synthetic purge")


func _verify_command_gate(command: Dictionary) -> void:
	check(receiver.can_accept_terminal_command(command),
		"exact spent signal/lure command passes receiver preflight")
	for mutation in [
		{"subtype": "credential"},
		{"effect": "reroute"},
		{"actor": ENEMY_AVAILABLE},
		{"source_trigger_count": int(command.get("source_trigger_count", 0)) + 1},
		{"source_authority_key": "gameplay:typed_terminal:wrong"},
		{"accepted_tick": float(command.get("accepted_tick", 0.0)) + 1.0},
		{"source_position": [999.0, 0.0, 999.0]},
	]:
		var wrong := command.duplicate(true)
		for key in mutation:
			wrong[key] = mutation[key]
		check(not receiver.can_accept_terminal_command(wrong),
			"receiver rejects mutated receipt field %s" % str(mutation.keys()[0]))
	command_gate_checked = true


func _capture_receiver_seams(key: String, value: Variant) -> void:
	if key != receiver.authority_state_key() or not value is Dictionary:
		return
	var record := value as Dictionary
	if str(record.get("phase", "")) != receiver.PHASE_EXPOSED:
		return
	if exposed_seam_state.is_empty():
		exposed_seam_scheduler = _round_trip(scheduler.serialize())
		exposed_seam_state = _round_trip(game_state.serialize())
	for receipt in record.get("target_receipts", []) as Array:
		if receipt is Dictionary \
				and str((receipt as Dictionary).get("status", "")) \
					== receiver.TARGET_APPLYING \
				and applying_seam_state.is_empty():
			applying_seam_scheduler = _round_trip(scheduler.serialize())
			applying_seam_state = _round_trip(game_state.serialize())
			break


func _on_fixture_committed(_state: Dictionary) -> void:
	fixture_commit_signals += 1
	fixture_signal_enemy_states = {
		ENEMY_AVAILABLE: enemy_available.get_state(),
		ENEMY_COMMITTED: enemy_committed.get_state(),
	}


func _on_target_lured(_char_id: String, _state: Dictionary) -> void:
	target_lured_signals += 1


func _make_enemy(enemy_id: String, spawn_position: Vector3) -> Enemy:
	var enemy: Enemy
	if enemy_id == ENEMY_AVAILABLE:
		enemy = Sapscrap.new()
	else:
		enemy = Enemy.new()
	enemy.name = enemy_id
	enemy.char_id = enemy_id
	enemy.game_state = game_state
	enemy.position = spawn_position
	enemy.move_speed = 2.0
	enemy.detection_range = 0.0
	return enemy


func _target_status(enemy_id: String) -> String:
	for receipt in receiver.get_state().get("target_receipts", []) as Array:
		if receipt is Dictionary and str((receipt as Dictionary).get("char_id", "")) == enemy_id:
			return str((receipt as Dictionary).get("status", ""))
	return ""


func _snapshot_enemy_state(snapshot: Dictionary, enemy_id: String) -> String:
	var world_state := snapshot.get("world_state", {}) as Dictionary
	var enemy_state := world_state.get("runtime:enemy:" + enemy_id, {}) as Dictionary
	return str(enemy_state.get("state", ""))


func _cell(x: int, z: int) -> Vector3:
	return game_state.grid.grid_to_world(Vector2i(x, z))


func _vector_data(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
		return
	failures += 1
	push_error("FAIL: %s" % label)
