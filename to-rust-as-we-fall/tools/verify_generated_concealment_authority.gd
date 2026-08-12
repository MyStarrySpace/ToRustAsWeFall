extends SceneTree

## Generated cover is sampled by a saved fixed cadence. This regression keeps
## render/headless frame frequency from becoming gameplay authority and proves
## that same-instance rollback and a fresh presenter consume the same remainder.

const CHUNK_SCENE := preload("res://scenes/fragments/chunks/generated_stretch_chunk.tscn")
const Catalog := preload("res://scripts/generation/stretch_spec_catalog.gd")
const EPSILON := 0.0001

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var source := await _boot_pair()
	var host: ChunkHostStub = source.host
	var chunk: Node = source.chunk
	var scarpet_origin := _first_cover_origin(chunk, "scarpet")
	check(scarpet_origin.is_finite(),
		"generated fixture exposes real Scarpet cover")

	host.game_state.snap_character_to("aster", Vector3(5000.0, 0.0, 5000.0))
	_advance_to(host, float(chunk.get("_theme_hazard_next_tick")) + EPSILON)
	check(_tier(host) == GameState.CONCEAL_NONE,
		"saved cover cadence establishes a clear baseline")

	host.game_state.snap_character_to("aster", scarpet_origin)
	var scarpet_deadline := float(chunk.get("_theme_hazard_next_tick"))
	var midpoint := (
		float(host.scheduler.get_current_tick())
		+ (scarpet_deadline - float(host.scheduler.get_current_tick())) * 0.5
	)
	_advance_to(host, midpoint)
	check(_tier(host) == GameState.CONCEAL_NONE,
		"moving onto Scarpet does not grant concealment before the saved boundary")
	for _frame in range(8):
		chunk.call("_process", 3.0)
	check(_tier(host) == GameState.CONCEAL_NONE,
		"render/headless process calls cannot grant generated concealment")

	var saved_scheduler := _json_round_trip(host.scheduler.serialize())
	var saved_state := _json_round_trip(host.game_state.serialize())
	_advance_to(host, scarpet_deadline + EPSILON)
	check(_tier(host) == GameState.CONCEAL_MEDIUM,
		"Scarpet grants MEDIUM concealment at its fixed-cadence boundary")

	host.scheduler.clear()
	host.scheduler.deserialize(saved_scheduler)
	host.game_state.deserialize(saved_state)
	chunk.call("on_game_state_snapshot_restored")
	chunk.call("on_game_state_snapshot_restored")
	check(
		_tier(host) == GameState.CONCEAL_NONE
			and is_equal_approx(
				float(chunk.get("_theme_hazard_next_tick")), scarpet_deadline
			),
		"same-instance rollback restores the sampled tier and original deadline once"
	)
	_advance_to(host, scarpet_deadline - EPSILON)
	check(_tier(host) == GameState.CONCEAL_NONE,
		"same-instance rollback cannot sample cover before the original deadline")
	_advance_to(host, scarpet_deadline + EPSILON)
	check(_tier(host) == GameState.CONCEAL_MEDIUM,
		"same-instance rollback consumes only the saved cover remainder")

	var fresh := await _boot_pair()
	var fresh_host: ChunkHostStub = fresh.host
	var fresh_chunk: Node = fresh.chunk
	fresh_host.scheduler.clear()
	fresh_host.scheduler.deserialize(saved_scheduler)
	fresh_host.game_state.deserialize(saved_state)
	fresh_chunk.call("on_game_state_snapshot_restored")
	fresh_chunk.call("on_game_state_snapshot_restored")
	check(
		_tier(fresh_host) == GameState.CONCEAL_NONE
			and is_equal_approx(
				float(fresh_chunk.get("_theme_hazard_next_tick")), scarpet_deadline
			),
		"fresh generated presenter restores the same cover midpoint and deadline"
	)
	for _frame in range(8):
		fresh_chunk.call("_process", 3.0)
	check(_tier(fresh_host) == GameState.CONCEAL_NONE,
		"fresh presenter render calls cannot consume the saved cover remainder")
	_advance_to(fresh_host, scarpet_deadline + EPSILON)
	check(_tier(fresh_host) == GameState.CONCEAL_MEDIUM,
		"fresh generated presenter consumes only the saved cover remainder")

	fresh_host.game_state.snap_character_to("aster", Vector3(5000.0, 0.0, 5000.0))
	var open_deadline := float(fresh_chunk.get("_theme_hazard_next_tick"))
	check(_tier(fresh_host) == GameState.CONCEAL_MEDIUM,
		"the previous sampled tier persists between fixed boundaries")
	_advance_to(fresh_host, open_deadline + EPSILON)
	check(_tier(fresh_host) == GameState.CONCEAL_NONE,
		"open ground replaces MEDIUM with NONE only at the next fixed boundary")

	host.queue_free()
	fresh_host.queue_free()
	await process_frame
	print("GENERATED CONCEALMENT AUTHORITY: %d checks, %d failures" % [
		_checks, _failures,
	])
	quit(0 if _failures == 0 else 1)


func _boot_pair() -> Dictionary:
	var host := ChunkHostStub.new()
	host.setup()
	root.add_child(host)
	var chunk := CHUNK_SCENE.instantiate()
	chunk.configure_chunk({
		"spec_path": Catalog.teaching_path(),
		"game_mode": "neutral",
		"food_test": "neutral",
	})
	host.register_party(chunk.get_spawn_positions())
	chunk.attach_chunk_host(host, "generated_stretch")
	host.add_child(chunk)
	for _frame in range(4):
		await process_frame
	host.grid = GridWorld.from_data(chunk.call("get_grid_data"))
	host.game_state.grid = host.grid
	chunk.call("reset_preview_state")
	await process_frame
	return {"host": host, "chunk": chunk}


func _first_cover_origin(chunk: Node, kind: String) -> Vector3:
	var field_name := "_generated_%ss" % kind
	var covers_v: Variant = chunk.get(field_name)
	if not (covers_v is Array):
		return Vector3.INF
	for cover_v in covers_v as Array:
		if cover_v is Node and is_instance_valid(cover_v) \
				and (cover_v as Node).has_method("get_concealment_origin"):
			var origin_v: Variant = (cover_v as Node).call("get_concealment_origin")
			if origin_v is Vector3:
				return origin_v as Vector3
	return Vector3.INF


func _tier(host: ChunkHostStub) -> int:
	return int(host.game_state.get_character_concealment("aster"))


func _advance_to(host: ChunkHostStub, deadline: float) -> void:
	var now := float(host.scheduler.get_current_tick())
	if deadline > now:
		host.scheduler.advance_ticks(deadline - now)


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
