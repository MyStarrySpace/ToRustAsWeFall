extends SceneTree

## Regression for generated route pressure after de-proxying it from route choice.
## The reusable field owns fixed-tick, position-selective consequences; the generated
## chunk only composes it over the already-visible risk_cell_list and records feedback.

const GridRiskFieldScript := preload("res://scripts/game/objects/grid_risk_field.gd")
const CHUNK_SCENE := preload("res://scenes/fragments/chunks/generated_stretch_chunk.tscn")
const SPEC_PATH := "res://data/generated_stretches/generated_sample_survival_run.json"
const FIELD_TAG := "authority_grid_risk"

var _checks := 0
var _failures := 0


class AuthorityHost:
	extends ChunkHostStub

	func get_preview_character_stat(char_id: String, stat_name: String) -> float:
		return game_state.get_stat(char_id, stat_name)

	func set_preview_character_stat(char_id: String, stat_name: String, value: float) -> void:
		game_state.set_stat(char_id, stat_name, value)

	func adjust_preview_character_stat(char_id: String, stat_name: String, delta: float) -> void:
		game_state.adjust_stat(char_id, stat_name, delta)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	_verify_field_authority()
	await _verify_generated_chunk_integration()
	print("GENERATED PRESSURE FIELD AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_field_authority() -> void:
	var grid: GridWorld = _make_grid()
	var source_scheduler := EventScheduler.new()
	var source_state := _make_state(source_scheduler, grid)
	var before_field_existed := _capture(source_scheduler, source_state)
	var source_hits := [0]
	var source = GridRiskFieldScript.new()
	root.add_child(source)
	source.setup(
		source_state,
		source_scheduler,
		grid,
		[{"cell": [2, 1], "penalty": 6.0}],
		["aster", "peris"],
		{
			"tag": FIELD_TAG,
			"interval": 2.0,
			"damage_rate_scale": 1.0,
			"active": true,
			"on_bite": func(_id, _damage, _cell, _penalty): source_hits[0] += 1,
		}
	)
	check(source.is_character_exposed("aster") and not source.is_character_exposed("peris"),
		"field exposure is derived from each body's current grid cell")
	source_scheduler.advance_ticks(0.75)
	var midpoint := _capture(source_scheduler, source_state)
	var midpoint_record: Dictionary = source_state.get_world_state(source.authority_state_key(), {})
	check(bool(midpoint_record.get("active", false))
			and is_equal_approx(float(midpoint_record.get("next_tick", -1.0)), 2.0)
			and int(midpoint_record.get("risk_cell_count", 0)) == 1,
		"active field stores identity, fixed cadence deadline, and spatial-cell context")
	source_scheduler.advance_ticks(1.249)
	check(is_equal_approx(source_state.get_stat("aster", "hp"), 100.0)
			and source_hits[0] == 0,
		"mid-exposure save has no endpoint-style early damage")
	source_scheduler.advance_ticks(0.001)
	check(is_equal_approx(source_state.get_stat("aster", "hp"), 88.0)
			and is_equal_approx(source_state.get_stat("peris", "hp"), 100.0)
			and source_hits[0] == 1,
		"deadline damages only the member physically occupying the marked cell")

	# Same-presenter rollback retracts damage and returns to the exact remaining interval.
	source_scheduler.advance_ticks(2.0)
	var hits_before_rollback := int(source_hits[0])
	_apply_capture(source_scheduler, source_state, source, midpoint)
	check(is_equal_approx(source_state.get_stat("aster", "hp"), 100.0)
			and is_equal_approx(float(source.get_state().get("next_tick_in", -1.0)), 1.25),
		"same-presenter rollback restores HP and intermediate exposure cadence")
	source_scheduler.advance_ticks(1.249)
	check(is_equal_approx(source_state.get_stat("aster", "hp"), 100.0),
		"same-presenter restore cannot bite one millisecond early")
	source_scheduler.advance_ticks(0.001)
	check(is_equal_approx(source_state.get_stat("aster", "hp"), 88.0)
			and source_hits[0] == hits_before_rollback + 1,
		"same-presenter restore re-arms exactly one consequence")

	# A fresh presenter reconstructs saved policy rather than its deliberately wrong defaults.
	var fresh_grid: GridWorld = _make_grid()
	var fresh_scheduler := EventScheduler.new()
	var fresh_state := _make_state(fresh_scheduler, fresh_grid)
	fresh_scheduler.deserialize(midpoint.get("scheduler", {}))
	fresh_state.deserialize(midpoint.get("game_state", {}))
	fresh_state.scheduler = fresh_scheduler
	fresh_state.grid = fresh_grid
	var fresh_hits := [0]
	var fresh = GridRiskFieldScript.new()
	root.add_child(fresh)
	fresh.setup(
		fresh_state,
		fresh_scheduler,
		fresh_grid,
		[{"cell": [2, 1], "penalty": 1.0}],
		["endo"],
		{
			"tag": FIELD_TAG,
			"interval": 30.0,
			"damage_rate_scale": 0.1,
			"active": false,
			"restore_existing_authority": true,
			"on_bite": func(_id, _damage, _cell, _penalty): fresh_hits[0] += 1,
		}
	)
	check(fresh.is_active()
			and is_equal_approx(float(fresh.get_state().get("next_tick_in", -1.0)), 1.25),
		"fresh presenter restores the saved active phase and absolute remainder")
	fresh_scheduler.advance_ticks(1.25)
	check(is_equal_approx(fresh_state.get_stat("aster", "hp"), 88.0)
			and is_equal_approx(fresh_state.get_stat("peris", "hp"), 100.0)
			and fresh_hits[0] == 1,
		"fresh presenter applies saved cell severity and roster exactly once")

	# Position is re-evaluated on every tick: leaving stops cost; a different member entering takes it.
	fresh_state.snap_character_to("aster", fresh_grid.grid_to_world(Vector2i(0, 0)))
	fresh_state.snap_character_to("peris", fresh_grid.grid_to_world(Vector2i(2, 1)))
	fresh_scheduler.advance_ticks(2.0)
	check(is_equal_approx(fresh_state.get_stat("aster", "hp"), 88.0)
			and is_equal_approx(fresh_state.get_stat("peris", "hp"), 88.0)
			and fresh_hits[0] == 2,
		"each cadence samples live positions instead of retaining route-wide exposure")

	# A generated terrain field is authored active at construction. Authority absence retracts
	# later contacts/callbacks, then rebuilds exactly one fresh baseline cadence without inventing
	# a world-state record during restoration.
	_apply_capture(source_scheduler, source_state, source, before_field_existed)
	source.on_game_state_snapshot_restored()
	var hp_after_absence := float(source_state.get_stat("aster", "hp"))
	var hits_after_absence := int(source_hits[0])
	check(source.is_active()
			and is_equal_approx(float(source.get_state().get("next_tick_in", -1.0)), 2.0)
			and source_state.get_world_state(source.authority_state_key(), null) == null,
		"authority absence restores authored-active terrain and idempotently arms one fresh cadence")
	source_scheduler.advance_ticks(1.999)
	check(is_equal_approx(source_state.get_stat("aster", "hp"), hp_after_absence)
			and source_state.get_world_state(source.authority_state_key(), null) == null,
		"absence restoration emits no damage and does not publish before the baseline deadline")
	source_scheduler.advance_ticks(0.001)
	check(is_equal_approx(source_state.get_stat("aster", "hp"), hp_after_absence - 12.0)
			and source_hits[0] == hits_after_absence + 1,
		"authored baseline resumes once at its fresh deterministic deadline")

	var coarse := _run_projection([6.001])
	var fine_steps: Array = []
	for _i in range(60):
		fine_steps.append(0.1)
	fine_steps.append(0.001)
	var fine := _run_projection(fine_steps)
	check(is_equal_approx(float(coarse.hp), float(fine.hp))
			and int(coarse.contacts) == int(fine.contacts)
			and is_equal_approx(float(coarse.damage_total), float(fine.damage_total)),
		"one coarse advance and many render-like advances produce identical pressure")

	source.free()
	fresh.free()


func _verify_generated_chunk_integration() -> void:
	var pair := await _boot_chunk()
	var host: AuthorityHost = pair.host
	var chunk: Node = pair.chunk
	var preview: Dictionary = chunk.call("get_preview_state")
	var field_state: Dictionary = preview.get("route_risk_field", {})
	check(bool(field_state.get("active", false))
			and int(field_state.get("risk_cell_count", 0)) > 0
			and chunk.get_node_or_null("GeneratedRouteRiskField") != null,
		"generated stretch realizes risk data as one active spatial kit owner")
	check(chunk.find_child("GeneratedFloorRisk_L*", true, false) != null,
		"the field's dangerous cells have visible rust-marked floor geometry")

	var hp_before := _party_stats(host.game_state, "hp")
	var stamina_before := _party_stats(host.game_state, "stamina")
	check(not bool(chunk.call("choose_generated_route", "risky_optional_02_03", false)),
		"semantic risky-route helper cannot activate traversal")
	check(_party_stats(host.game_state, "hp") == hp_before
			and _party_stats(host.game_state, "stamina") == stamina_before
			and is_equal_approx(float(chunk.call("get_preview_state").get("risky_damage_total", -1.0)), 0.0),
		"rejected semantic route call applies no abstract whole-party tax")
	check(
		bool(chunk.call(
			"_headless_traverse_generated_route",
			"risky_optional_02_03",
			"aster"
		)),
		"route activates only after a canonical body walks its authored surface"
	)

	var nav: Dictionary = chunk.call("get_grid_data")
	var risk_entries: Array = nav.get("risk_cell_list", [])
	var risk_cell_raw: Array = (risk_entries[0] as Dictionary).get("cell", [])
	var risk_cell := Vector2i(int(risk_cell_raw[0]), int(risk_cell_raw[1]))
	var safe_cell := _first_safe_cell(nav)
	host.game_state.snap_character_to("aster", host.grid.grid_to_world(risk_cell))
	host.game_state.snap_character_to("peris", host.grid.grid_to_world(safe_cell))
	host.game_state.snap_character_to("endo", host.grid.grid_to_world(safe_cell + Vector2i(0, 1)))
	var aster_before := float(host.game_state.get_stat("aster", "hp"))
	var peris_before := float(host.game_state.get_stat("peris", "hp"))
	var endo_before := float(host.game_state.get_stat("endo", "hp"))
	host.scheduler.advance_ticks(0.5)
	check(float(host.game_state.get_stat("aster", "hp")) < aster_before
			and is_equal_approx(float(host.game_state.get_stat("peris", "hp")), peris_before)
			and is_equal_approx(float(host.game_state.get_stat("endo", "hp")), endo_before),
		"physical contact charges only the member on the marked generated cell")
	check(float(chunk.call("get_preview_state").get("risky_damage_total", 0.0)) > 0.0
			and str(chunk.call("get_preview_state").get("last_outcome", "")).begins_with("risk_cell_contact:aster"),
		"chunk bookkeeping reports the kit's real contact instead of manufacturing it")

	host.queue_free()
	await process_frame


func _run_projection(steps: Array) -> Dictionary:
	var grid: GridWorld = _make_grid()
	var scheduler := EventScheduler.new()
	var state := _make_state(scheduler, grid)
	var field = GridRiskFieldScript.new()
	root.add_child(field)
	field.setup(state, scheduler, grid, [{"cell": [2, 1], "penalty": 6.0}], ["aster"], {
		"tag": "frame_grid_risk_%d" % field.get_instance_id(),
		"interval": 2.0,
		"damage_rate_scale": 1.0,
		"active": true,
	})
	for step_v in steps:
		scheduler.advance_ticks(float(step_v))
	var result := {
		"hp": state.get_stat("aster", "hp"),
		"contacts": int(field.get_state().get("contact_ticks", {}).get("aster", 0)),
		"damage_total": float(field.get_state().get("damage_total", 0.0)),
	}
	field.free()
	return result


func _boot_chunk() -> Dictionary:
	var host := AuthorityHost.new()
	host.setup()
	root.add_child(host)
	var chunk := CHUNK_SCENE.instantiate()
	chunk.configure_chunk({"spec_path": SPEC_PATH, "game_mode": "neutral", "food_test": "neutral"})
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


func _make_grid() -> GridWorld:
	var grid := GridWorld.new()
	grid.create_room(8, 5)
	return grid


func _make_state(scheduler, grid) -> GameState:
	var state := GameState.new()
	state.scheduler = scheduler
	state.grid = grid
	state.register_character("aster", grid.grid_to_world(Vector2i(2, 1)), 3.0,
		{"hp": 100.0, "stamina": 100.0})
	state.register_character("peris", grid.grid_to_world(Vector2i(0, 0)), 3.0,
		{"hp": 100.0, "stamina": 100.0})
	state.register_character("endo", grid.grid_to_world(Vector2i(0, 1)), 3.0,
		{"hp": 100.0, "stamina": 100.0})
	return state


func _first_safe_cell(nav: Dictionary) -> Vector2i:
	var risks := {}
	for entry_v in nav.get("risk_cell_list", []):
		var raw: Array = (entry_v as Dictionary).get("cell", [])
		risks[Vector2i(int(raw[0]), int(raw[1]))] = true
	for raw_v in nav.get("walkable_cells", []):
		var raw := raw_v as Array
		var cell := Vector2i(int(raw[0]), int(raw[1]))
		if not risks.has(cell) and not risks.has(cell + Vector2i(0, 1)):
			return cell
	return Vector2i.ZERO


func _party_stats(state: GameState, stat: String) -> Dictionary:
	var values := {}
	for id in ["aster", "peris", "endo"]:
		values[id] = float(state.get_stat(id, stat))
	return values


func _capture(scheduler, state: GameState) -> Dictionary:
	return _json_round_trip({
		"scheduler": scheduler.serialize(),
		"game_state": state.serialize(),
	})


func _apply_capture(scheduler, state: GameState, presenter, capture: Dictionary) -> void:
	scheduler.clear()
	scheduler.deserialize(capture.get("scheduler", {}))
	state.deserialize(capture.get("game_state", {}))
	presenter.on_game_state_snapshot_restored()


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
