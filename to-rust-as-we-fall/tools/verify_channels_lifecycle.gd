extends SceneTree

## Focused Channels lifecycle regression that deliberately avoids the all-fragment
## preview registry. This remains runnable when an unrelated fragment has a compile
## failure and covers the wipe/clear scheduler contracts directly.
## Run:
##   godot --headless --path . --script res://tools/verify_channels_lifecycle.gd

const PARTY := ["aster", "peris", "endo"]
const INTRO_SCENE := preload("res://scenes/fragments/chunks/channels_wash_intro_chunk.tscn")
const RELAY_SCENE := preload("res://scenes/fragments/chunks/wash_relay_chunk.tscn")

var _failures: Array[String] = []
var _checks := 0


class ChunkHost extends Node:
	var game_state := GameState.new()
	var scheduler := EventScheduler.new()
	var current_step := ""
	var active_character := "endo"
	var party: Array[String] = []
	var messages: Array[String] = []
	var notes: Array[String] = []

	func configure(spawns: Dictionary) -> void:
		game_state.scheduler = scheduler
		party.assign(PARTY)
		game_state.set_party(party)
		for char_id in party:
			game_state.register_character(char_id, spawns.get(char_id, Vector3.ZERO), 3.0, {
				"hp": 100.0,
				"max_hp": 100.0,
				"stamina": 100.0,
				"max_stamina": 100.0,
				"atp": 3.0,
			})

	func get_preview_game_state():
		return game_state

	func get_preview_scheduler():
		return scheduler

	func get_preview_scheduler_tick() -> float:
		return scheduler.get_current_tick()

	func get_preview_character_position(char_id: String) -> Vector3:
		return game_state.get_position(char_id)

	func set_preview_character_position(char_id: String, position: Vector3) -> void:
		game_state.snap_character_to(char_id, position)

	func get_preview_character_move_speed(_char_id: String, _running := false) -> float:
		return 3.0

	func get_preview_active_character() -> String:
		return active_character

	func get_preview_selected_characters() -> Array:
		return party.duplicate()

	func get_preview_character_stat(char_id: String, stat_name: String) -> float:
		return game_state.get_stat(char_id, stat_name)

	func set_preview_character_stat(char_id: String, stat_name: String, value: float) -> void:
		game_state.set_stat(char_id, stat_name, value)

	func adjust_preview_character_stat(char_id: String, stat_name: String, delta: float) -> void:
		game_state.adjust_stat(char_id, stat_name, delta)

	func set_preview_step(step: String) -> void:
		current_step = step

	func register_preview_interactable(_interactable: Node) -> void:
		pass

	func get_preview_dialogue_box():
		return null

	func get_preview_engram_overlay():
		return null

	func show_preview_note(text: String, _duration := 3.0) -> void:
		notes.append(text)

	func show_preview_message(text: String, _duration := 2.0) -> void:
		messages.append(text)


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures.append(message)
		push_error("  FAIL: %s" % message)


func _spawn_chunk(scene: PackedScene, chunk_id: String, spawns: Dictionary) -> Dictionary:
	var host := ChunkHost.new()
	host.configure(spawns)
	root.add_child(host)
	var chunk = scene.instantiate()
	chunk.attach_chunk_host(host, chunk_id)
	host.add_child(chunk)
	# The production preview host resets a freshly attached chunk before gameplay frames.
	# Mirror that ordering so custom chunks have their per-section arrays initialized.
	chunk.reset_preview_state()
	await process_frame
	await process_frame
	return {"host": host, "chunk": chunk, "gs": host.game_state}


func _advance(host: ChunkHost, chunk: Node, seconds: float, step := 0.1) -> void:
	var elapsed := 0.0
	while elapsed < seconds - 0.0001:
		var dt := minf(step, seconds - elapsed)
		host.scheduler.advance_ticks(dt)
		chunk.headless_process(dt)
		await process_frame
		elapsed += dt


func _trigger_vine_tend(chunk: Node, gs: GameState) -> bool:
	var source: Node = chunk.find_child("ClimbvineTendAnchor", true, false)
	if source == null:
		return false
	if gs.is_moving("peris"):
		gs.command_stop("peris")
	gs.snap_character_to("peris", chunk.RETURN_LANDING)
	source.set("active_character", "peris")
	return bool(source.call("_trigger", false))


func _trigger_vine_climb(chunk: Node, gs: GameState, active: String) -> bool:
	var source: Node = chunk.find_child("ClimbLine", true, false)
	if source == null:
		return false
	var waiting: Array = (chunk.get("_washed") as Dictionary).keys()
	waiting.sort()
	if not waiting.has(active):
		return false
	for id_v in waiting:
		var id := str(id_v)
		if gs.is_moving(id):
			gs.command_stop(id)
		gs.snap_character_to(id, chunk.CLIMB_POS)
	source.set("active_character", active)
	return bool(source.call("_trigger", false))


func _dispose(host: Node) -> void:
	host.queue_free()
	await process_frame
	await process_frame


func _run() -> void:
	EventLog.print_events = false
	_verify_pick_interactor()
	await _verify_intro()
	await _verify_relay_completion()
	await _verify_relay_retry_contract()
	await _verify_relay_wipe()
	if _failures.is_empty():
		print("\nCHANNELS LIFECYCLE PASS (%d checks)" % _checks)
		quit(0)
	else:
		print("\nCHANNELS LIFECYCLE FAIL (%d/%d failed)" % [_failures.size(), _checks])
		quit(1)


func _verify_pick_interactor() -> void:
	print("\n=== Interaction ownership ===")
	var gs := GameState.new()
	gs.register_character("aster", Vector3.ZERO)
	gs.register_character("peris", Vector3(4.0, 0.0, 0.0))
	gs.down_character("aster")
	_check(gs.pick_interactor("", Vector3(0.1, 0.0, 0.0), ["aster", "peris"]) == "peris",
		"downed nearest member is excluded from interaction assignment")


func _verify_intro() -> void:
	print("\n=== Channels Wash Intro ===")
	var resource = load("res://data/fragments/channels_wash_intro.tres")
	var ctx := await _spawn_chunk(INTRO_SCENE, "channels_wash_intro", resource.spawns)
	var host: ChunkHost = ctx["host"]
	var chunk: Node = ctx["chunk"]
	var gs: GameState = ctx["gs"]
	_check(bool(resource.params.get("restart_on_wipe", false)), "intro opts into full-wipe restart")
	await _advance(host, chunk, 0.1)
	chunk._channel_onset(0)
	_check(bool(chunk.get_preview_state()["any_channel_flooding"]), "intro wipe begins during an active flood")
	for char_id in PARTY:
		gs.down_character(char_id)
	# Inspect at the restart callback itself, before the next gameplay frame re-arms a
	# fresh cadence (section zero is intentionally authored with a near-zero phase).
	host.scheduler.advance_ticks(1.5)
	for char_id in PARTY:
		_check(not gs.is_downed(char_id) and gs.get_stat(char_id, "hp") > 0.0,
			"intro wipe restores %s" % char_id)
		_check(gs.get_position(char_id).distance_to(resource.spawns[char_id]) < 0.01,
			"intro wipe snaps %s to authored spawn" % char_id)
	_check(not bool(chunk.get_preview_state()["any_channel_flooding"]), "intro wipe clears in-flight floods")
	_check(host.current_step == "channels_wash_intro_restart", "intro publishes restart step")
	_check(int(chunk.get("_wipe_count")) == 1, "intro restart preserves wipe count")
	await _advance(host, chunk, 0.1)
	gs.down_character("endo")
	gs.snap_character_to("aster", resource.params["exit_pos"])
	chunk.headless_process(0.0)
	_check(not bool(chunk.get_preview_state()["complete"]), "conscious survivor cannot leave downed crew")
	# Queue another full-wipe callback, then recover the party and clear before it fires.
	# Completion must retract that stale restart as part of channel quiescence.
	gs.down_character("aster")
	gs.down_character("peris")
	for char_id in PARTY:
		gs.restore_character(char_id)
	# This room's authored lesson is now explicit: the wash must take every hunter and
	# the whole party must gather at the far shelter before the preview can chain onward.
	for enemy in (chunk.get("_enemies") as Array):
		gs.snap_character_to(str(enemy.char_id), Vector3(11.0, 0.5, 0.5))
	chunk.call("_channel_onset", 0)
	host.scheduler.advance_ticks(0.06)
	var wash_arrival := float(host.scheduler.get_current_tick())
	for enemy in (chunk.get("_enemies") as Array):
		var carry: Dictionary = gs.get_external_traversal_state(str(enemy.char_id))
		wash_arrival = maxf(wash_arrival, float(carry.get("end_tick", wash_arrival)))
	host.scheduler.advance_ticks(maxf(0.0,
		wash_arrival - float(host.scheduler.get_current_tick()) + 0.01))
	host.messages.clear()
	gs.snap_character_to("aster", resource.params["exit_pos"])
	gs.snap_character_to("peris", resource.spawns["peris"])
	gs.snap_character_to("endo", resource.spawns["endo"])
	chunk.headless_process(0.0)
	chunk.headless_process(0.0)
	_check(not bool(chunk.get_preview_state()["complete"]), "one member at the far pad cannot leave crew")
	_check(host.messages.size() == 1 and host.messages[0].contains("whole party"),
		"partial exit gather gives one clear nonblocking cue without per-frame spam")
	for char_id in PARTY:
		gs.snap_character_to(char_id, resource.params["exit_pos"])
	chunk.headless_process(0.0)
	_check(bool(chunk.get_preview_state()["complete"]), "drowned hunters + whole conscious party complete intro")
	_check(host.current_step == "channels_wash_intro_complete", "intro publishes completion step")
	_check(not bool(chunk.get_preview_state()["any_channel_flooding"]), "intro channels stop on clear")
	host.scheduler.advance_ticks(1.6)
	_check(bool(chunk.get_preview_state()["complete"]), "intro clear cancels pending wipe restart")
	await _advance(host, chunk, 4.0)
	_check(not bool(chunk.get_preview_state()["any_channel_flooding"]), "intro channels stay stopped")
	await _dispose(host)


func _verify_relay_completion() -> void:
	print("\n=== Wash Relay completion ===")
	var resource = load("res://data/fragments/wash_relay.tres")
	var ctx := await _spawn_chunk(RELAY_SCENE, "wash_relay", resource.spawns)
	var host: ChunkHost = ctx["host"]
	var chunk: Node = ctx["chunk"]
	var gs: GameState = ctx["gs"]
	gs.grid = GridWorld.from_data(chunk.get_grid_data())
	chunk.reset_preview_state()
	await _advance(host, chunk, 0.1)
	gs.snap_character_to("endo", Vector3(28.8, 0.5, 0.0))
	gs.down_character("endo")
	chunk.headless_process(0.0)
	_check(not bool((chunk.get_preview_state()["sections"] as Array)[3]["plate_held"]),
		"downed body cannot hold relay plate")
	for char_id in PARTY:
		gs.snap_character_to(char_id, Vector3(85.0, 0.5, 0.0))
	chunk.headless_process(0.0)
	_check(not bool(chunk.get_preview_state()["complete"]), "downed body blocks relay completion")
	gs.restore_character("endo")
	chunk.headless_process(0.0)
	_check(bool(chunk.get_preview_state()["complete"]), "conscious party completes relay")
	_check(host.current_step == "wash_relay_complete", "relay publishes completion step")
	var counts: Array = []
	for section in (chunk.get_preview_state()["sections"] as Array):
		counts.append(int(section["flood_count"]))
	await _advance(host, chunk, 8.0)
	var after_counts: Array = []
	for section in (chunk.get_preview_state()["sections"] as Array):
		after_counts.append(int(section["flood_count"]))
	_check(after_counts == counts, "relay flood cadence stops after clear")
	_check(not bool(chunk.get_preview_state()["drain_flooding"]), "relay drain stops after clear")
	await _dispose(host)


func _verify_relay_retry_contract() -> void:
	print("\n=== Wash Relay retry + guidance contract ===")
	var resource = load("res://data/fragments/wash_relay.tres")
	var ctx := await _spawn_chunk(RELAY_SCENE, "wash_relay", resource.spawns)
	var host: ChunkHost = ctx["host"]
	var chunk: Node = ctx["chunk"]
	var gs: GameState = ctx["gs"]
	gs.grid = GridWorld.from_data(chunk.get_grid_data())
	chunk.reset_preview_state()
	await _advance(host, chunk, 0.1)
	var initial: Dictionary = chunk.get_preview_state()
	_check(not bool(initial["climb_available"]),
		"CLIMB is absent until Peris tends and deploys the upper vine")
	_check(int(initial["guidance_count"]) == int(initial["section_count"]),
		"every relay section has one local guidance stage")
	_check(int(initial["guidance_section"]) == 0, "spawn shows only the opening section guidance")

	var sections: Array = initial["sections"]
	var first: Dictionary = sections[0]
	var first_mid := Vector3((float(first["x0"]) + float(first["x1"])) * 0.5, 0.5, 0.0)
	host.messages.clear()
	gs.snap_character_to("aster", first_mid)
	chunk.call("_wash_section", 0)
	_check(int(chunk.get_preview_state()["current_carry_count"]) == 1
			and int(chunk.get_preview_state()["washed_count"]) == 0,
		"caught Aster enters the real current without being granted shelter arrival")
	_check(host.messages.size() == 1 and host.messages[0].contains("Aster"),
		"wash feedback is one immediate character-specific HUD message")
	await _advance(host, chunk,
		chunk.WASH_CURRENT_KNOCK_DURATION + chunk.WASH_CURRENT_RETURN_MAX + 0.1)
	_check(int(chunk.get_preview_state()["washed_count"]) == 1,
		"Aster waits at the start only after the physical return lands")
	# The waiting marker cannot grant secret immunity: walking Aster back into the same hazard washes him again.
	gs.snap_character_to("aster", first_mid)
	chunk.headless_process(0.0)
	chunk.call("_wash_section", 0)
	_check(int(chunk.get_preview_state()["sweep_count"]) == 2,
		"a marked character can be washed again (no hidden flood immunity)")
	await _advance(host, chunk,
		chunk.WASH_CURRENT_KNOCK_DURATION + chunk.WASH_CURRENT_RETURN_MAX + 0.1)
	gs.snap_character_to("aster", first_mid)
	chunk.headless_process(0.0)
	chunk.call("_wash_section", 0)
	_check(not host.notes.is_empty() and host.notes[-1].contains("RUN"),
		"third failure gives one nonblocking RUN hint")
	await _advance(host, chunk,
		chunk.WASH_CURRENT_KNOCK_DURATION + chunk.WASH_CURRENT_RETURN_MAX + 0.1)
	# Walking out of the shelter clears only the waiting-at-start marker.
	gs.snap_character_to("aster", Vector3(float(first["x0"]) - 0.25, 0.5, 0.0))
	var retry_release_tick := float(
		chunk.get_preview_state().get("next_spatial_authority_tick", -1.0)
	)
	await _advance(
		host,
		chunk,
		maxf(0.0, retry_release_tick - float(host.scheduler.get_current_tick()) + 0.001)
	)
	_check(int(chunk.get_preview_state()["washed_count"]) == 0,
		"leaving the start shelter restores normal retry state at the saved spatial boundary")

	var override_i := -1
	for i in range(sections.size()):
		if str((sections[i] as Dictionary)["disable"]) == "override":
			override_i = i
			break
	_check(override_i >= 0, "relay exposes a held override section")
	if override_i >= 0:
		var override: Dictionary = sections[override_i]
		gs.snap_character_to("aster", Vector3(float(override["x1"]) + 1.5, 0.5, 0.0))
		chunk.headless_process(0.0)
		_check(bool(chunk.call("_section_disabled", override_i)),
			"a retrying washed character can hold an override normally")

	gs.snap_character_to("peris", chunk.RETURN_LANDING)
	chunk.call("_on_sloperope", "peris")
	_check(not bool(chunk.get_preview_state()["climb_available"])
			and not gs.has_mechanism_phase(&"wash_relay_sloperope:deployment"),
		"retired upper helper cannot manufacture a Climbvine source receipt")
	_check(_trigger_vine_tend(chunk, gs),
		"exact upper Interactable accepts the physical Peris body")
	await _advance(host, chunk, chunk.SLOPEROPE_DEPLOY_DURATION + 0.1)
	_check(bool(chunk.get_preview_state()["climb_available"]),
		"Peris tending the upper anchor grows the vine before CLIMB becomes available")
	chunk.reset_preview_state()
	_check(not bool(chunk.get_preview_state()["climb_available"]), "reset hides and disables CLIMB again")
	chunk.call("_wash_character", "aster")
	await _advance(host, chunk,
		chunk.WASH_CURRENT_KNOCK_DURATION + chunk.WASH_CURRENT_RETURN_MAX + 0.1)
	var aster_hp_before := gs.get_stat("aster", "hp")
	var aster_stamina_before := gs.get_stat("aster", "stamina")
	var aster_atp_before := gs.get_stat("aster", "atp")
	gs.snap_character_to("peris", chunk.RETURN_LANDING)
	_check(_trigger_vine_tend(chunk, gs),
		"reset permits a new exact upper-source TEND")
	await _advance(host, chunk, chunk.SLOPEROPE_DEPLOY_DURATION + 0.1)
	var peris_before := gs.get_position("peris")
	gs.snap_character_to("aster", chunk.CLIMB_POS)
	chunk.call("_on_climb")
	_check(not gs.is_external_traversal_active("aster"),
		"retired lower helper cannot manufacture a Climbvine source receipt")
	_check(_trigger_vine_climb(chunk, gs, "aster"),
		"exact lower Interactable accepts the physically gathered waiting body")
	_check(gs.is_external_traversal_active("aster"),
		"a stranded member at the lower mouth begins a physical climb instead of teleporting")
	await _advance(host, chunk, chunk.SLOPEROPE_CLIMB_DURATION + 0.1)
	_check(gs.get_position("aster").distance_to(resource.params["return_landing"]) < 0.01,
		"the deployed physical line reunites crew still waiting at start")
	_check(gs.get_position("peris").distance_to(peris_before) < 0.01,
		"the climb does not teleport crew who were never washed")
	_check(is_equal_approx(gs.get_stat("aster", "hp"), aster_hp_before)
		and is_equal_approx(gs.get_stat("aster", "stamina"), aster_stamina_before)
		and is_equal_approx(gs.get_stat("aster", "atp"), aster_atp_before),
		"the climb changes location only and restores no stats")
	await _dispose(host)


func _verify_relay_wipe() -> void:
	print("\n=== Wash Relay wipe ===")
	var resource = load("res://data/fragments/wash_relay.tres")
	var ctx := await _spawn_chunk(RELAY_SCENE, "wash_relay", resource.spawns)
	var host: ChunkHost = ctx["host"]
	var chunk: Node = ctx["chunk"]
	var gs: GameState = ctx["gs"]
	gs.grid = GridWorld.from_data(chunk.get_grid_data())
	chunk.reset_preview_state()
	await _advance(host, chunk, 0.1)
	for char_id in PARTY:
		gs.down_character(char_id)
	await _advance(host, chunk, 1.6)
	for char_id in PARTY:
		_check(not gs.is_downed(char_id) and gs.get_stat(char_id, "hp") > 0.0,
			"relay wipe restores %s" % char_id)
		_check(gs.get_position(char_id).distance_to(resource.spawns[char_id]) < 0.01,
			"relay wipe snaps %s to authored spawn" % char_id)
	_check(host.current_step == "wash_relay_restart", "relay publishes restart step")
	await _dispose(host)
