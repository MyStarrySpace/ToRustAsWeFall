extends SceneTree

## Midpoint exploit regression for GameState's own authoritative registries. The snapshot takes the
## same JSON round trip as SaveManager and restores the scheduler clock before GameState phases.

var checks := 0
var failures := 0


func _init() -> void:
	var scheduler := EventScheduler.new()
	var source := GameState.new()
	source.scheduler = scheduler
	_build_state(source)

	# Let every operation become visibly in-progress, but leave enough time to distinguish a genuine
	# continuation from a reset, free completion, or endpoint-only commit.
	scheduler.advance_ticks(0.15)
	var source_positions := {
		"mover": source.get_position("mover"),
		"dodger": source.get_position("dodger"),
		"dragger": source.get_position("dragger"),
		"body": source.get_position("body"),
		"slide": source.get_physics_position("slide"),
		"thrown": source.get_physics_position("thrown"),
	}
	var source_pendulum_angle := source.get_pendulum_angle("pendulum")
	var source_stamina := source.get_stat("mover", "stamina")
	var source_sleep_hp := source.get_stat("sleeper", "hp")
	var scheduler_snapshot := _json_round_trip(scheduler.serialize())
	var snapshot := _json_round_trip(source.serialize())
	var expected_next_rng := source.rng_registry.get_rng(&"snapshot.exploit", 7).randi()

	var loaded_scheduler := EventScheduler.new()
	loaded_scheduler.deserialize(scheduler_snapshot)
	var loaded := GameState.new()
	loaded.scheduler = loaded_scheduler
	# Shelter geometry is scene infrastructure, rebuilt before applying a production save.
	loaded.add_shelter_region(Vector2(-2.0, 8.0), Vector2(2.0, 12.0))
	# Model a scene that has already spawned a later wave before the player loads this older save.
	# Snapshot application must replace, rather than merge, the authoritative actor roster.
	loaded.register_character("future_wave_enemy", Vector3(99.0, 0.0, 99.0), 4.0,
		{"hp": 100.0, "stamina": 100.0, "detection_range": 8.0})
	loaded.set_coop_exempt("future_wave_enemy", true)
	loaded._set_rest_deprived("future_wave_enemy", true)
	var restored_signals := [0]
	loaded.snapshot_restored.connect(func(_snapshot): restored_signals[0] += 1)
	loaded.deserialize(snapshot)

	check(restored_signals[0] == 1, "snapshot restoration exposes one presenter rebind seam")
	check(not loaded.characters.has("future_wave_enemy")
		and not loaded.explored.has("future_wave_enemy")
		and not loaded.is_rest_deprived("future_wave_enemy"),
		"loading a pre-wave snapshot retracts actors and derived state spawned afterward")
	check(loaded.is_moving("mover") and loaded.get_position("mover").is_equal_approx(
		source_positions["mover"]), "ordinary movement resumes at its exact midpoint")
	check(loaded.is_running("mover") and is_equal_approx(
		loaded.get_stat("mover", "stamina"), source_stamina),
		"running policy and already-paid stamina survive reload")
	check(loaded.is_dodging("dodger") and loaded.get_position("dodger").is_equal_approx(
		source_positions["dodger"]), "dodge movement remains an active state")
	loaded.toggle_running("dodger")
	loaded.command_stop("dodger")
	check(loaded.is_dodging("dodger") and loaded.is_moving("dodger")
		and not loaded.is_running("dodger"),
		"run/stop inputs cannot orphan a reloaded dodge callback")
	check(not loaded.command_move_to_pos("dodger", Vector3(99.0, 0.0, 0.0)),
		"movement cannot cancel a reloaded dodge")
	check(loaded.is_knocked_down("exhausted")
		and not loaded.command_move_to_pos("exhausted", Vector3(99.0, 0.0, 0.0)),
		"failed-dodge knockdown cannot be skipped by loading")
	check(loaded.is_endocytosing("eater") and loaded.items.has("item_1")
		and loaded.get_hand_items("eater").has("item_1"),
		"endocytosis retains its item, hand commitment, and active timer")
	check(loaded.is_resting("sleeper") and is_equal_approx(
		loaded.get_stat("sleeper", "hp"), source_sleep_hp),
		"rest does not grant free healing or refund its committed ATP")
	check(loaded.is_field_restoring("oli") and loaded.is_downed("fallen"),
		"field restore remains rooted and incomplete")
	check(loaded.has_queued_ability("peris") and loaded.is_moving("peris"),
		"canonical ability approach and payload remain queued")
	check(loaded.is_dragging("dragger") and loaded.get_drag_target("dragger") == "body"
		and loaded.get_position("dragger").is_equal_approx(source_positions["dragger"])
		and loaded.get_position("body").is_equal_approx(source_positions["body"]),
		"drag ownership, load position, and slowed movement survive reload")
	check(loaded.get_hand_slots("dragger") == ["carry:body", "carry:body"],
		"two-hand carry occupation cannot be cleared by loading")
	check(loaded.is_physics_moving("slide") and loaded.get_physics_position("slide").is_equal_approx(
		source_positions["slide"]), "ground physics motion resumes at its midpoint")
	check(loaded.is_physics_airborne("thrown")
		and loaded.get_physics_position("thrown").distance_to(
			source_positions["thrown"]) < 0.001,
		"airborne physics preserves horizontal and ballistic midpoint state")
	check(loaded.has_interactable("one_shot")
		and not loaded.is_interactable_enabled("one_shot")
		and bool(loaded.get_interactable("one_shot").get("triggered", false)),
		"triggered one-shot consequences remain spent")
	check(loaded.flora.has("flora_1") and loaded.get_flora_stage("flora_1") == 0,
		"flora identity and growth state survive reload")
	check(loaded.get_party() == ["aster", "peris", "mover"]
		and loaded.get_split_members() == ["peris"],
		"party order and active split membership survive reload")
	check(loaded.get_game_day() == 3 and is_equal_approx(loaded.get_time_of_day(), 0.4)
		and loaded.is_rest_deprived("mover"),
		"live clock anchor and rest deprivation cannot be reset by loading")
	check(is_equal_approx(loaded.get_pendulum_angle("pendulum"), source_pendulum_angle),
		"pendulum phase and damping age remain continuous")
	check(loaded.rng_registry.get_rng(&"snapshot.exploit", 7).randi() == expected_next_rng,
		"loading cannot reroll a consumed deterministic RNG stream")

	# The original dodge had 0.20s left and the knockdown 1.45s. Reloading must preserve those
	# distinct remaining windows rather than restarting either duration.
	loaded_scheduler.advance_ticks(0.21)
	check(not loaded.is_dodging("dodger")
		and loaded.get_position("dodger").is_equal_approx(Vector3(3.0, 0.0, 4.0)),
		"reloaded dodge completes once after only its saved remainder")
	check(loaded.is_knocked_down("exhausted"),
		"longer knockdown remains active after dodge recovery")
	loaded_scheduler.advance_ticks(1.25)
	check(not loaded.is_knocked_down("exhausted"),
		"knockdown completes after its original deadline")

	# Endocytosis had 3.85s left. The item must remain unavailable until that exact remaining timer.
	loaded_scheduler.advance_ticks(2.38)
	check(loaded.is_endocytosing("eater") and loaded.items.has("item_1"),
		"reloaded endocytosis cannot be fast-completed for free")
	loaded_scheduler.advance_ticks(0.02)
	check(not loaded.is_endocytosing("eater") and not loaded.items.has("item_1")
		and loaded.get_stat("eater", "atp") > 1.0,
		"endocytosis resolves once at its original deadline")

	# The canonical WRAP approach should resolve through the same queue, spending stamina exactly once.
	loaded_scheduler.advance_ticks(1.5)
	check(not loaded.has_queued_ability("peris")
		and loaded.get_damage_shield("aster") > 0.0
		and loaded.get_stat("peris", "stamina") == 85.0,
		"queued canonical ability completes once after the restored approach")

	# Oli's cast began at t=0 and should finish at t=8, not eight seconds after loading.
	loaded_scheduler.advance_ticks(2.5)
	check(not loaded.is_field_restoring("oli") and not loaded.is_downed("fallen"),
		"field restore finishes at its original committed deadline")
	check(loaded.get_position("mover").is_equal_approx(Vector3(12.0, 0.0, 0.0)),
		"ordinary movement reaches its original destination without a reload teleport")
	check(not loaded.is_physics_moving("slide") and not loaded.is_physics_airborne("thrown"),
		"restored physics operations settle rather than freezing or restarting")

	var next_item := loaded.spawn_item("lysate", Vector3.ZERO)
	check(next_item == "item_3", "item sequence prevents duplicate IDs after loading")
	_verify_mid_push_snapshot()

	print("GAME STATE SNAPSHOT AUTHORITY: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _build_state(gs: GameState) -> void:
	gs.set_base_seed(12345)
	gs.rng_registry.get_rng(&"snapshot.exploit", 7).randi()
	gs.rng_registry.get_rng(&"snapshot.exploit", 7).randi()
	gs.register_character("mover", Vector3.ZERO, 3.0,
		{"hp": 100.0, "stamina": 100.0, "atp": 4.0})
	gs.register_character("dodger", Vector3(0.0, 0.0, 4.0), 3.0,
		{"hp": 100.0, "stamina": 100.0, "dodge_unlocked": true})
	gs.register_character("exhausted", Vector3(0.0, 0.0, 6.0), 3.0,
		{"hp": 100.0, "stamina": 0.0, "dodge_unlocked": true})
	gs.register_character("eater", Vector3(0.0, 0.0, 8.0), 3.0,
		{"hp": 100.0, "stamina": 100.0, "atp": 1.0})
	gs.register_character("sleeper", Vector3(0.0, 0.0, 10.0), 3.0,
		{"hp": 50.0, "stamina": 50.0, "atp": 4.0})
	gs.register_character("oli", Vector3(0.0, 0.0, 14.0), 3.0,
		{"hp": 100.0, "stamina": 100.0, "atp": 4.0})
	gs.register_character("fallen", Vector3(1.0, 0.0, 14.0), 3.0,
		{"hp": 0.0, "stamina": 0.0, "narrative_available": false})
	gs.register_character("aster", Vector3(0.0, 0.0, 20.0), 3.0,
		{"hp": 100.0, "stamina": 100.0, "atp": 4.0})
	gs.register_character("peris", Vector3(20.0, 0.0, 20.0), 3.0,
		{"hp": 100.0, "stamina": 100.0, "atp": 4.0})
	gs.register_character("dragger", Vector3(0.0, 0.0, 24.0), 3.0,
		{"hp": 100.0, "stamina": 100.0, "atp": 4.0})
	gs.register_character("body", Vector3(1.0, 0.0, 24.0), 3.0,
		{"hp": 0.0, "stamina": 0.0, "narrative_available": false})

	gs.add_shelter_region(Vector2(-2.0, 8.0), Vector2(2.0, 12.0))
	gs.game_day = 3
	gs.game_time = 0.4
	gs._set_rest_deprived("mover", true)
	gs.set_party(["aster", "peris", "mover"])
	gs.start_split(["peris"])

	gs.set_running("mover", true)
	gs.command_move_to_pos("mover", Vector3(12.0, 0.0, 0.0))
	gs.set_running("dodger", true)
	check(gs.dodge_roll("dodger", Vector3.RIGHT) and not gs.is_running("dodger"),
		"setup commits dodge as the sole locomotion state")
	check(not gs.dodge_roll("exhausted", Vector3.RIGHT) and gs.is_knocked_down("exhausted"),
		"setup commits failed-dodge knockdown")

	var lysate := gs.spawn_item("lysate", gs.get_position("eater"), {
		"atp_restore": 2.0,
		"endocytosis_duration": 4.0,
	})
	check(lysate == "item_1" and gs.pick_up_item("eater", lysate)
		and gs.endocytose_item("eater", lysate), "setup commits endocytosis")
	# Reserve a second ID so the post-load sequence assertion detects counter rollback.
	gs.spawn_item("lysate", Vector3(50.0, 0.0, 50.0))
	check(gs.command_rest("sleeper"), "setup commits paid shelter rest")
	check(gs.command_field_restore("oli", "fallen"), "setup commits field restore")
	var queued := gs.queue_canonical_ability("peris", "wrap", gs.get_position("aster"), {
		"target_id": "aster",
		"allowed_target_ids": ["aster", "peris", "mover"],
		"approach_range": 9.0,
	})
	check(bool(queued.get("queued", false)), "setup queues canonical WRAP approach")
	check(gs.command_start_drag("dragger", "body"), "setup commits two-hand drag")
	gs.command_move_to_pos("dragger", Vector3(6.0, 0.0, 24.0))

	gs.register_physics_object("slide", Vector3(0.0, 0.0, 50.0), 0.5, 2.0, 0.6, true)
	gs._apply_physics_movement("slide", Vector3(0.0, 0.0, 50.0),
		Vector3(8.0, 0.0, 50.0), 4.0)
	gs.register_physics_object("thrown", Vector3(0.0, 1.0, 60.0), 0.5, 2.0, 0.6, true)
	gs.throw_physics_object("thrown", Vector3(4.0, 5.0, 0.0))
	gs.register_pendulum("pendulum", Vector3(100.0, 5.0, 100.0), 3.0, 0.6,
		Vector3.FORWARD, 0.4, 0.3, 0.05)

	gs.register_interactable({
		"id": "one_shot", "position": Vector3(2.0, 0.0, 2.0), "one_shot": true,
	})
	check(gs.trigger_interactable("one_shot", "aster"), "setup spends one-shot interactable")
	gs.flora["flora_1"] = {
		"position": Vector3(3.0, 0.0, 3.0), "stage": 0, "tended_today": true,
		"harvested_day": -1, "planted_day": 3, "species": "climbvine",
		"harvest_item_type": "", "harvest_item_properties": {},
	}
	gs._flora_seq = 1


func _verify_mid_push_snapshot() -> void:
	var grid := GridWorld.new()
	grid.create_room(10, 6, false)
	var scheduler := EventScheduler.new()
	var source := GameState.new()
	source.scheduler = scheduler
	source.grid = grid
	source.register_character("pusher", grid.grid_to_world(Vector2i(2, 2)), 3.0,
		{"hp": 100.0, "stamina": 100.0})
	source.register_physics_object(
		"crate", grid.grid_to_world(Vector2i(3, 2)), 0.5, 2.0, 0.6, true)
	check(source.command_push_object("pusher", "crate", Vector2i(6, 2)),
		"setup commits a multi-step push plan")
	scheduler.advance_ticks(0.2)
	var mid_crate := source.get_physics_position("crate")
	var scheduler_snapshot := _json_round_trip(scheduler.serialize())
	var snapshot := _json_round_trip(source.serialize())

	var loaded_scheduler := EventScheduler.new()
	loaded_scheduler.deserialize(scheduler_snapshot)
	var loaded := GameState.new()
	loaded.scheduler = loaded_scheduler
	loaded.grid = grid
	loaded.deserialize(snapshot)
	check(loaded.is_pushing("pusher") and loaded.is_physics_moving("crate")
		and loaded.get_physics_position("crate").is_equal_approx(mid_crate),
		"push plan and in-flight shove resume together")
	loaded_scheduler.advance_ticks(5.0)
	check(not loaded.is_pushing("pusher")
		and grid.world_to_grid(loaded.get_physics_position("crate")) == Vector2i(6, 2),
		"reloaded multi-step push reaches its original target")


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
