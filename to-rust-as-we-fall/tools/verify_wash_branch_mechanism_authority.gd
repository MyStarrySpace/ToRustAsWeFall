extends SceneTree

## Focused anti-proxy contract for Wash Relay's optional branches.
##
## The branch switch is only an intervention. Authority changes at an observable world endpoint:
##   * lever: the visible gate reaches the top, then collision/navigation/cache release together;
##   * valve: the visible pollen stock finishes venting, then the cache is exposed;
##   * decoy: the real guard reaches the beacon, and the cache remains available only for that lure window.
## Every resulting reward is one source-tagged GameState lysate item. Its claim publishes the exact
## actor/item reservation before pickup, and reward strength rises with the physical detour risk.

const RelayScene := preload("res://scenes/fragments/chunks/wash_relay_chunk.tscn")
const PARTY: Array[String] = ["aster", "peris", "endo"]
const AUTHORITY_KEY := "chunk:wash_relay"
const LEVER_DURATION := 1.4
const VALVE_DURATION := 1.8
const GATE_LIFT_HEIGHT := 2.1
const DECOY_ARRIVAL_RADIUS := 0.7

var _checks := 0
var _failures := 0


class RelayHost extends Node:
	var game_state := GameState.new()
	var scheduler := EventScheduler.new()
	var active_character := "aster"
	var party: Array[String] = PARTY.duplicate()

	func configure(spawns: Dictionary) -> void:
		game_state.scheduler = scheduler
		game_state.set_party(party)
		for char_id in party:
			game_state.register_character(char_id, spawns.get(char_id, Vector3.ZERO), 3.0, {
				"hp": 100.0, "max_hp": 100.0,
				"stamina": 100.0, "max_stamina": 100.0,
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

	func set_preview_character_position(char_id: String, value: Vector3) -> void:
		game_state.snap_character_to(char_id, value)

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

	func spawn_preview_item(item_type: String, position: Vector3, properties: Dictionary = {}) -> String:
		return game_state.spawn_item(item_type, position, properties)

	func remove_preview_item(item_id: String) -> void:
		game_state.remove_item(item_id)

	func pick_up_preview_item(char_id: String, item_id: String) -> bool:
		return game_state.pick_up_item(char_id, item_id)

	func get_preview_item_state(item_id: String) -> Dictionary:
		return game_state.items.get(item_id, {}).duplicate(true)

	func set_preview_step(_step: String) -> void:
		pass

	func register_preview_interactable(_interactable: Node) -> void:
		pass

	func get_preview_dialogue_box():
		return null

	func get_preview_engram_overlay():
		return null

	func show_preview_note(_text: String, _duration := 3.0) -> void:
		pass

	func show_preview_message(_text: String, _duration := 2.0) -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var pair: Dictionary = await _boot()
	var host: RelayHost = pair.get("host") as RelayHost
	var chunk: Node = pair.get("chunk") as Node
	var baseline := _capture(host)
	var lever_index := _branch_index(chunk, "lever")
	var valve_index := _branch_index(chunk, "valve")
	var decoy_index := _branch_index(chunk, "decoy")
	check(lever_index >= 0, "generated branch set contains a physical counterweight test")
	check(valve_index >= 0, "generated branch set contains a pollen-flow test")
	check(decoy_index >= 0, "generated branch set contains a guard-relocation test")

	if lever_index >= 0:
		await _verify_lever(host, chunk, baseline, lever_index)
	if valve_index >= 0:
		await _verify_valve(host, chunk, baseline, valve_index)
	if decoy_index >= 0:
		await _verify_decoy(host, chunk, baseline, decoy_index)
	await _verify_reward_authority(host, chunk, baseline)

	await _discard(host)
	print("WASH BRANCH MECHANISM AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_lever(host: RelayHost, chunk: Node, baseline: Dictionary, branch_index: int) -> void:
	_apply_capture(host, chunk, baseline)
	var runtime := _runtime_branch(chunk, branch_index)
	var initial := _branch_state(chunk, branch_index)
	var gate: Node3D = runtime.get("gate_visual") as Node3D
	var body: StaticBody3D = runtime.get("gate_body") as StaticBody3D
	var base: Transform3D = runtime.get("gate_base_transform", Transform3D.IDENTITY)
	check(str(initial.get("mechanism_phase", "")) == "idle"
		and not bool(initial.get("cache_available", true)),
		"counterweight starts closed with its cache unavailable")
	check(bool(initial.get("topology_blocked", false)) and body != null and body.collision_layer == 1,
		"counterweight owns both navigation and physical collision at baseline")
	check(str((initial.get("mechanism_context", {}) as Dictionary).get("mechanism", "")) \
		== "counterweight_gate", "counterweight saves typed causal context")

	var switch: Node = runtime.get("switch")
	check(_trigger_exact_source(host, switch, "aster"),
		"nearby ready party body uses the exact counterweight lever")
	var started := _branch_state(chunk, branch_index)
	check(str(started.get("mechanism_phase", "")) == "raising"
		and float(started.get("phase_deadline", -1.0)) > float(started.get("phase_started_at", 0.0)),
		"lever commits a finite raising phase instead of an unlocked boolean")
	check(not bool(started.get("cache_available", true))
		and bool(started.get("topology_blocked", false)),
		"raising keeps cache and topology closed")

	_advance(host, chunk, LEVER_DURATION * 0.5)
	var midpoint := _branch_state(chunk, branch_index)
	var lift := 0.0
	if gate != null:
		lift = (gate.transform.origin - base.origin).dot(base.basis.y.normalized())
	check(str(midpoint.get("mechanism_phase", "")) == "raising"
		and float(midpoint.get("phase_progress", 0.0)) > 0.49
		and float(midpoint.get("phase_progress", 1.0)) < 0.51,
		"counterweight midpoint is scheduler-derived")
	check(lift > 0.9 and lift < GATE_LIFT_HEIGHT - 0.5,
		"the gate visibly occupies its saved midpoint")
	check(bool(midpoint.get("topology_blocked", false)) and body.collision_layer == 1,
		"mid-animation cannot be used as an early passage")
	var midpoint_capture := _capture(host)

	_advance(host, chunk, LEVER_DURATION * 0.5 + 0.001)
	var opened := _branch_state(chunk, branch_index)
	check(str(opened.get("mechanism_phase", "")) == "clear"
		and bool(opened.get("cache_available", false)),
		"counterweight endpoint exposes the cache")
	check(not bool(opened.get("topology_blocked", true)) and body.collision_layer == 0,
		"counterweight endpoint atomically releases navigation and collision")

	_apply_capture(host, chunk, midpoint_capture)
	_apply_capture(host, chunk, midpoint_capture)
	runtime = _runtime_branch(chunk, branch_index)
	body = runtime.get("gate_body") as StaticBody3D
	var rolled := _branch_state(chunk, branch_index)
	check(str(rolled.get("mechanism_phase", "")) == "raising"
		and bool(rolled.get("topology_blocked", false)) and body.collision_layer == 1,
		"repeated same-instance restore retracts an already-open gate to the exact midpoint")
	var remaining := float(rolled.get("phase_deadline", 0.0)) - host.scheduler.get_current_tick()
	_advance(host, chunk, remaining + 0.001)
	check(str(_branch_state(chunk, branch_index).get("mechanism_phase", "")) == "clear",
		"idempotent restore arms exactly one counterweight completion")

	var fresh_pair: Dictionary = await _boot()
	var fresh_host: RelayHost = fresh_pair.get("host") as RelayHost
	var fresh: Node = fresh_pair.get("chunk") as Node
	_apply_capture(fresh_host, fresh, midpoint_capture)
	var fresh_mid := _branch_state(fresh, branch_index)
	check(str(fresh_mid.get("mechanism_phase", "")) == "raising"
		and bool(fresh_mid.get("topology_blocked", false))
		and not bool(fresh_mid.get("cache_available", true)),
		"fresh counterweight presenter reconstructs the same closed midpoint")
	remaining = float(fresh_mid.get("phase_deadline", 0.0)) - fresh_host.scheduler.get_current_tick()
	_advance(fresh_host, fresh, remaining + 0.001)
	check(str(_branch_state(fresh, branch_index).get("mechanism_phase", "")) == "clear",
		"fresh counterweight consumes only its saved remainder")
	await _discard(fresh_host)


func _verify_valve(host: RelayHost, chunk: Node, baseline: Dictionary, branch_index: int) -> void:
	_apply_capture(host, chunk, baseline)
	var runtime := _runtime_branch(chunk, branch_index)
	var initial := _branch_state(chunk, branch_index)
	var plumes: Array = runtime.get("vent_plumes", [])
	check(not plumes.is_empty() and (plumes[0] as Node3D).visible,
		"pollen valve begins with a visible stock over the cache")
	check(not bool(initial.get("cache_available", true))
		and not bool(initial.get("topology_blocked", true)),
		"pollen is an exposure/flow gate, not a recoloured movement blocker")
	check(str((initial.get("mechanism_context", {}) as Dictionary).get("stock", "")) == "pollen",
		"valve saves the stock it is clearing")

	var switch: Node = runtime.get("switch")
	check(_trigger_exact_source(host, switch, "aster"),
		"nearby ready party body uses the exact pollen valve")
	var started := _branch_state(chunk, branch_index)
	check(str(started.get("mechanism_phase", "")) == "venting"
		and not bool(started.get("cache_available", true)),
		"valve commits venting without exposing the cache early")
	_advance(host, chunk, VALVE_DURATION * 0.5)
	var midpoint := _branch_state(chunk, branch_index)
	var plume: Node3D = plumes[0] as Node3D
	check(str(midpoint.get("mechanism_phase", "")) == "venting"
		and float(midpoint.get("phase_progress", 0.0)) > 0.49
		and float(midpoint.get("phase_progress", 1.0)) < 0.51,
		"pollen clearance midpoint is scheduler-derived")
	check(plume.visible and plume.scale.x < 0.65 and plume.scale.x > 0.08,
		"the plume visibly streams away during the saved interval")
	check(not bool(midpoint.get("cache_available", true)),
		"mid-vent save cannot grant the clearance endpoint")
	var midpoint_capture := _capture(host)

	_advance(host, chunk, VALVE_DURATION * 0.5 + 0.001)
	var clear := _branch_state(chunk, branch_index)
	check(str(clear.get("mechanism_phase", "")) == "clear"
		and bool(clear.get("cache_available", false)),
		"pollen endpoint exposes the cache")
	check(not (plumes[0] as Node3D).visible,
		"cleared pollen presenter retracts the actual cloud")

	_apply_capture(host, chunk, midpoint_capture)
	_apply_capture(host, chunk, midpoint_capture)
	runtime = _runtime_branch(chunk, branch_index)
	plumes = runtime.get("vent_plumes", [])
	var rolled := _branch_state(chunk, branch_index)
	check(str(rolled.get("mechanism_phase", "")) == "venting"
		and (plumes[0] as Node3D).visible and not bool(rolled.get("cache_available", true)),
		"same-instance rollback reconstructs the pollen stock and closed cache")

	var fresh_pair: Dictionary = await _boot()
	var fresh_host: RelayHost = fresh_pair.get("host") as RelayHost
	var fresh: Node = fresh_pair.get("chunk") as Node
	_apply_capture(fresh_host, fresh, midpoint_capture)
	var fresh_mid := _branch_state(fresh, branch_index)
	check(str(fresh_mid.get("mechanism_phase", "")) == "venting"
		and not bool(fresh_mid.get("cache_available", true)),
		"fresh valve presenter reconstructs the in-flight clearance")
	var remaining := float(fresh_mid.get("phase_deadline", 0.0)) - fresh_host.scheduler.get_current_tick()
	_advance(fresh_host, fresh, remaining + 0.001)
	check(str(_branch_state(fresh, branch_index).get("mechanism_phase", "")) == "clear",
		"fresh valve consumes only its saved remainder")
	await _discard(fresh_host)


func _verify_decoy(host: RelayHost, chunk: Node, baseline: Dictionary, branch_index: int) -> void:
	_apply_capture(host, chunk, baseline)
	var runtime := _runtime_branch(chunk, branch_index)
	var guard = runtime.get("guard")
	var guard_id := str(guard.char_id) if is_instance_valid(guard) else ""
	var initial_pos := host.game_state.get_position(guard_id) if guard_id != "" else Vector3.ZERO
	# The boot capture may catch the ambient roamer a fraction away from its post.
	# Rejected/absent authority must reconstruct authored construction truth, not
	# that incidental baseline-frame position.
	var authored_posts: Dictionary = chunk.get("_branch_guard_spawns")
	var authored_post: Vector3 = authored_posts.get(guard_id, initial_pos)
	var initial := _branch_state(chunk, branch_index)
	check(guard_id != "" and not bool(initial.get("cache_available", true)),
		"decoy cache begins guarded and unavailable")
	check(runtime.get("gate_visual") == null and (runtime.get("vent_plumes", []) as Array).is_empty(),
		"decoy has no fake gate or recoloured pollen proxy")
	check(str((initial.get("mechanism_context", {}) as Dictionary).get("guard_id", "")) == guard_id,
		"decoy context names the real body whose movement matters")

	var switch: Node = runtime.get("switch")
	check(_trigger_exact_source(host, switch, "aster"),
		"nearby ready party body lights the exact branch beacon")
	var started := _branch_state(chunk, branch_index)
	check(str(started.get("mechanism_phase", "")) == "luring"
		and not bool(started.get("cache_available", true)),
		"lighting the beacon begins a saved luring phase without semantic unlock")
	check(str(guard.get_state()) == "lured" and host.game_state.is_character_distracted(guard_id),
		"the reusable Enemy lure state owns the guard response")
	# Exact activation necessarily stages Aster at the beacon. The authored play is to light it,
	# then clear the arrival pocket while the guard walks inward; standing on the lure target until
	# contact correctly makes even a distracted guard break into its inner-reach response.
	host.game_state.command_stop("aster")
	host.game_state.snap_character_to("aster", Vector3.ZERO)
	_advance(host, chunk, 0.6)
	var midpoint := _branch_state(chunk, branch_index)
	var moved_pos := host.game_state.get_position(guard_id)
	check(str(midpoint.get("mechanism_phase", "")) == "luring"
		and moved_pos.distance_to(initial_pos) > 0.5,
		"the guard physically travels while the cache stays closed")
	check(not bool(midpoint.get("cache_available", true)),
		"an in-flight guard does not count as safely relocated")
	var midpoint_capture := _capture(host)

	var reached_window := _advance_until_phase(host, chunk, branch_index, "window", 4.0)
	var window := _branch_state(chunk, branch_index)
	var context: Dictionary = window.get("mechanism_context", {})
	var lure_target: Vector3 = chunk.call(
		"_branch_decode_vec3", context.get("lure_target", []), Vector3.INF)
	check(reached_window and bool(window.get("cache_available", false)),
		"cache opens only after the branch enters the arrival-backed lure window "
		+ "(phase=%s guard=%s target=%s moving=%s state=%s)" % [
			str(window.get("mechanism_phase", "")),
			str(host.game_state.get_position(guard_id)),
			str(lure_target),
			str(host.game_state.is_moving(guard_id)),
			str(guard.get_state()),
		])
	check(host.game_state.get_position(guard_id).distance_to(lure_target) \
		<= DECOY_ARRIVAL_RADIUS + 0.05,
		"window authority is backed by the real guard body at the beacon "
		+ "(distance=%.3f)" % host.game_state.get_position(guard_id).distance_to(
			lure_target))
	check(float(context.get("arrival_tick", -1.0)) >= float(window.get("phase_started_at", 0.0)),
		"arrival tick is persisted beside the original lure deadline")
	var window_capture := _capture(host)

	# Letting the finite distraction lapse closes an uncollected cache and re-arms the beacon.
	var remaining := float(window.get("phase_deadline", 0.0)) - host.scheduler.get_current_tick()
	_advance(host, chunk, remaining + 0.001)
	var expired := _branch_state(chunk, branch_index)
	check(str(expired.get("mechanism_phase", "")) == "idle"
		and not bool(expired.get("cache_available", true)),
		"expired lure window returns the guarded cache to its retryable baseline")
	check(bool((runtime.get("switch") as Node).call("is_interaction_enabled")),
		"expired beacon can be used again instead of soft-locking the branch")

	# Restoring the window and taking the exact physical lysate commits the reward once and cancels
	# branch expiry ownership.
	_apply_capture(host, chunk, window_capture)
	var reward_before := _branch_state(chunk, branch_index)
	var source_pos: Vector3 = reward_before.get("reward_source_pos", Vector3.ZERO)
	var cache: Node = _runtime_branch(chunk, branch_index).get("cache")
	check(_trigger_exact_source(host, cache, "aster"),
		"exact arrival-backed lysate source accepts its nearby carrier")
	var collected := _branch_state(chunk, branch_index)
	check(bool(collected.get("collected", false))
		and str(collected.get("reward_phase", "")) == "claimed"
		and str(collected.get("reward_item_holder", "")) == "aster"
		and str(collected.get("mechanism_phase", "")) == "clear",
		"lysate pickup during the physical window commits the exact item and terminal branch phase")
	check(_wash_reward_item_count(
		host, str(collected.get("reward_source_key", ""))) == 1,
		"arrival-backed source owns exactly one physical reward identity")

	# Same-instance and fresh restores must put the body back in flight, never leave it at the future beacon.
	_apply_capture(host, chunk, midpoint_capture)
	_apply_capture(host, chunk, midpoint_capture)
	runtime = _runtime_branch(chunk, branch_index)
	guard = runtime.get("guard")
	guard_id = str(guard.char_id)
	var rolled := _branch_state(chunk, branch_index)
	check(str(rolled.get("mechanism_phase", "")) == "luring"
		and not bool(rolled.get("cache_available", true))
		and host.game_state.get_position(guard_id).distance_to(initial_pos) > 0.5,
		"repeated rollback reconstructs the moving guard and closed cache")
	check(_advance_until_phase(host, chunk, branch_index, "window", 4.0),
		"idempotent rollback arms one arrival poll chain")

	var fresh_pair: Dictionary = await _boot()
	var fresh_host: RelayHost = fresh_pair.get("host") as RelayHost
	var fresh: Node = fresh_pair.get("chunk") as Node
	_apply_capture(fresh_host, fresh, midpoint_capture)
	var fresh_mid := _branch_state(fresh, branch_index)
	check(str(fresh_mid.get("mechanism_phase", "")) == "luring"
		and not bool(fresh_mid.get("cache_available", true)),
		"fresh decoy presenter reconstructs the in-flight guard")
	check(_advance_until_phase(fresh_host, fresh, branch_index, "window", 4.0),
		"fresh decoy earns availability through the remaining physical travel")
	await _discard(fresh_host)

	# A malformed causal identity rolls back both branch and guard instead of mixing unrelated futures.
	var corrupt := midpoint_capture.duplicate(true)
	var corrupt_gs: Dictionary = corrupt.get("game_state", {}) as Dictionary
	var corrupt_world: Dictionary = corrupt_gs.get("world_state", {}) as Dictionary
	var wash: Dictionary = corrupt_world.get(AUTHORITY_KEY, {}) as Dictionary
	var saved_branches: Array = wash.get("branches", [])
	if branch_index >= 0 and branch_index < saved_branches.size():
		var saved_branch: Dictionary = (saved_branches[branch_index] as Dictionary).duplicate(true)
		var bad_context: Dictionary = (saved_branch.get("mechanism_context", {}) as Dictionary).duplicate(true)
		bad_context["guard_id"] = "not_the_branch_guard"
		saved_branch["mechanism_context"] = bad_context
		saved_branches[branch_index] = saved_branch
	wash["branches"] = saved_branches
	corrupt_world[AUTHORITY_KEY] = wash
	corrupt_gs["world_state"] = corrupt_world
	corrupt["game_state"] = corrupt_gs
	_apply_capture(host, chunk, corrupt)
	var rejected := _branch_state(chunk, branch_index)
	runtime = _runtime_branch(chunk, branch_index)
	guard = runtime.get("guard")
	guard_id = str(guard.char_id)
	check(str(rejected.get("mechanism_phase", "")) == "idle"
		and not bool(rejected.get("cache_available", true)),
		"malformed decoy context rolls the branch back closed")
	var rejected_guard_position := host.game_state.get_position(guard_id)
	check(Vector2(rejected_guard_position.x, rejected_guard_position.z).distance_to(
		Vector2(authored_post.x, authored_post.z)) < 0.001
		and not host.game_state.is_character_distracted(guard_id),
		"malformed context cannot retain a borrowed guard future (got %s, post %s, distracted %s)" % [
			rejected_guard_position,
			authored_post,
			str(host.game_state.is_character_distracted(guard_id)),
		])

	# Missing Wash authority is construction truth even when interactable/enemy snapshots came from the future.
	var absent := window_capture.duplicate(true)
	var absent_gs: Dictionary = absent.get("game_state", {}) as Dictionary
	var absent_world: Dictionary = absent_gs.get("world_state", {}) as Dictionary
	absent_world.erase(AUTHORITY_KEY)
	absent_gs["world_state"] = absent_world
	absent["game_state"] = absent_gs
	_apply_capture(host, chunk, absent)
	var retracted := _branch_state(chunk, branch_index)
	runtime = _runtime_branch(chunk, branch_index)
	guard = runtime.get("guard")
	guard_id = str(guard.char_id)
	check(str(retracted.get("mechanism_phase", "")) == "idle"
		and not bool(retracted.get("cache_available", true)),
		"absent authority retracts a future decoy window")
	var retracted_guard_position := host.game_state.get_position(guard_id)
	check(Vector2(retracted_guard_position.x, retracted_guard_position.z).distance_to(
		Vector2(authored_post.x, authored_post.z)) < 0.001,
		"absent authority returns the guard to its authored post (got %s, post %s)" % [
			retracted_guard_position,
			authored_post,
		])


func _verify_reward_authority(host: RelayHost, chunk: Node, baseline: Dictionary) -> void:
	_apply_capture(host, chunk, baseline)
	var preview: Dictionary = chunk.call("get_preview_state")
	var branches: Array = preview.get("branches", [])
	var open_index := _branch_index(chunk, "open")
	var lever_index := _branch_index(chunk, "lever")
	var valve_index := _branch_index(chunk, "valve")
	var decoy_index := _branch_index(chunk, "decoy")
	check(open_index >= 0, "the branch curriculum includes a sparse guidance lysate source")

	for branch_v in branches:
		var branch: Dictionary = branch_v
		var item_id := str(branch.get("reward_item_id", ""))
		var item: Dictionary = host.game_state.items.get(item_id, {})
		var properties: Dictionary = item.get("properties", {})
		check(item_id != "" and str(item.get("type", "")) == "lysate"
			and str(item.get("location", "")) == "ground"
			and str(properties.get("source_wash_relay", "")) \
				== str(branch.get("reward_source_key", ""))
			and int(properties.get("wash_reward_atp", 0)) == int(branch.get("reward_atp", -1))
			and str(properties.get("display_name", "")).contains(
				"%d ATP" % int(branch.get("reward_atp", -1))),
			"branch %s exposes one source-tagged physical lysate item with readable value" \
				% str(branch.get("gap", "?")))
		var runtime_branch := _runtime_branch(chunk, branches.find(branch_v))
		var branch_cache: Node = runtime_branch.get("cache")
		var has_proxy_box := false
		var has_cradle := false
		for mesh_node in branch_cache.find_children("*", "MeshInstance3D", true, false) \
				if branch_cache != null else []:
			var mesh: Mesh = (mesh_node as MeshInstance3D).mesh
			has_proxy_box = has_proxy_box or mesh is BoxMesh
			has_cradle = has_cradle or mesh is CylinderMesh
		check(has_cradle and not has_proxy_box,
			"branch %s uses a dark cradle affordance, not a generic reward box" \
				% str(branch.get("gap", "?")))
	var drain: Dictionary = preview.get("drain_reward", {})
	var drain_item: Dictionary = host.game_state.items.get(str(drain.get("item_id", "")), {})
	check(str(drain_item.get("type", "")) == "lysate"
		and str((drain_item.get("properties", {}) as Dictionary).get("source_wash_relay", "")) \
			== "wash_relay:drain"
		and bool(drain.get("item_at_source", false)),
		"the drain detour exposes a real concentrated-lysate source")
	var drain_cache: Node = chunk.find_child("DrainCache", true, false)
	var drain_has_proxy_box := false
	var drain_has_cradle := false
	for mesh_node in drain_cache.find_children("*", "MeshInstance3D", true, false) \
			if drain_cache != null else []:
		var mesh: Mesh = (mesh_node as MeshInstance3D).mesh
		drain_has_proxy_box = drain_has_proxy_box or mesh is BoxMesh
		drain_has_cradle = drain_has_cradle or mesh is CylinderMesh
	check(drain_has_cradle and not drain_has_proxy_box,
		"drain reward uses a dark cradle affordance, not a generic reward box")

	if open_index >= 0 and lever_index >= 0 and valve_index >= 0 and decoy_index >= 0:
		var open_reward := int(_branch_state(chunk, open_index).get("reward_atp", 0))
		var lever_reward := int(_branch_state(chunk, lever_index).get("reward_atp", 0))
		var valve_reward := int(_branch_state(chunk, valve_index).get("reward_atp", 0))
		var decoy_reward := int(_branch_state(chunk, decoy_index).get("reward_atp", 0))
		var drain_reward := int(drain.get("reward_atp", 0))
		check(open_reward < lever_reward and open_reward < valve_reward
			and lever_reward < decoy_reward and valve_reward < decoy_reward
			and decoy_reward < drain_reward,
			"reward strength rises strictly with guidance < mechanism < guard < current-plus-guard risk")

	if open_index < 0:
		return
	var runtime := _runtime_branch(chunk, open_index)
	var cache: Node = runtime.get("cache")
	var source_pos: Vector3 = runtime.get("reward_source_pos", Vector3.ZERO)

	# Distance is still enforced when a direct/headless caller bypasses the walk-to controller.
	cache.set("active_character", "aster")
	host.game_state.snap_character_to("aster", source_pos + Vector3(5.0, 0.0, 0.0))
	check(not bool(cache.call("_trigger", false)),
		"remote selected portrait cannot spend the branch cache")
	var after_far := _branch_state(chunk, open_index)
	check(str(after_far.get("reward_phase", "")) == "available"
		and bool(after_far.get("reward_item_at_source", false))
		and str(after_far.get("reward_item_holder", "")) == "",
		"out-of-range claim leaves the same physical item at its source")

	# Both hands full blocks before any reservation or item movement.
	_apply_capture(host, chunk, baseline)
	runtime = _runtime_branch(chunk, open_index)
	cache = runtime.get("cache")
	source_pos = runtime.get("reward_source_pos", Vector3.ZERO)
	host.game_state.snap_character_to("aster", source_pos)
	for slot_i in range(2):
		var filler := host.game_state.spawn_item(
			"seed", source_pos, {"display_name": "hand filler %d" % slot_i})
		check(host.game_state.pick_up_item("aster", filler),
			"full-hand fixture fills slot %d through the ordinary pickup contract" % slot_i)
	cache.set("active_character", "aster")
	check(not bool(cache.call("_trigger", false)),
		"full hands are rejected before the branch source accepts a receipt")
	var after_full := _branch_state(chunk, open_index)
	check(str(after_full.get("reward_phase", "")) == "available"
		and bool(after_full.get("reward_item_at_source", false))
		and host.game_state.get_hand_items("aster").size() == 2,
		"full hands cannot consume, clone, or reserve the source lysate")

	# Capture from the exact GameState.item_picked_up signal seam. Wash authority must already say
	# CLAIMING while the item registry says the reserved actor holds that exact identity.
	_apply_capture(host, chunk, baseline)
	runtime = _runtime_branch(chunk, open_index)
	cache = runtime.get("cache")
	source_pos = runtime.get("reward_source_pos", Vector3.ZERO)
	var expected_item_id := str(runtime.get("reward_item_id", ""))
	var capture_box := {"snapshot": {}, "item_id": ""}
	var pickup_probe := func(char_id: String, item_id: String) -> void:
		if char_id == "aster" and item_id == expected_item_id \
				and (capture_box.get("snapshot", {}) as Dictionary).is_empty():
			capture_box["item_id"] = item_id
			capture_box["snapshot"] = _capture(host)
	host.game_state.item_picked_up.connect(pickup_probe)
	check(_trigger_exact_source(host, cache, "aster"),
		"exact branch cache source begins the item transaction")
	host.game_state.item_picked_up.disconnect(pickup_probe)
	var signal_capture: Dictionary = capture_box.get("snapshot", {})
	check(not signal_capture.is_empty()
		and _saved_branch_reward_phase(signal_capture, open_index) == "claiming",
		"item-pickup signal snapshot sees the published CLAIMING reservation")
	var completed := _branch_state(chunk, open_index)
	check(str(completed.get("reward_phase", "")) == "claimed"
		and str(completed.get("reward_item_holder", "")) == "aster"
		and int(completed.get("reward_claim_serial", 0)) == 1,
		"ordinary pickup finalizes the exact item once for the reserved actor")
	host.game_state.set_stat("aster", "atp", 0.0)
	check(host.game_state.endocytose_item("aster", expected_item_id),
		"claimed Wash lysate enters the canonical endocytosis transaction")
	host.scheduler.advance_ticks(2.01)
	check(is_equal_approx(
		host.game_state.get_stat("aster", "atp"),
		float(completed.get("reward_atp", 0))),
		"physical source restores its authored ATP value through ordinary digestion")

	_apply_capture(host, chunk, signal_capture)
	_apply_capture(host, chunk, signal_capture)
	var reconciled := _branch_state(chunk, open_index)
	check(str(reconciled.get("reward_phase", "")) == "claimed"
		and str(reconciled.get("reward_item_holder", "")) == "aster"
		and int(reconciled.get("reward_claim_serial", 0)) == 1,
		"same-instance signal-time restore reconciles once without cloning or replaying pickup")

	var fresh_pair: Dictionary = await _boot()
	var fresh_host: RelayHost = fresh_pair.get("host") as RelayHost
	var fresh: Node = fresh_pair.get("chunk") as Node
	_apply_capture(fresh_host, fresh, signal_capture)
	var fresh_claim := _branch_state(fresh, open_index)
	check(str(fresh_claim.get("reward_phase", "")) == "claimed"
		and str(fresh_claim.get("reward_item_holder", "")) == "aster"
		and _wash_reward_item_count(fresh_host, str(fresh_claim.get("reward_source_key", ""))) == 1,
		"fresh signal-time restore preserves one exact claimed item")
	await _discard(fresh_host)

	# Corrupt only the holder while leaving the saved Aster reservation intact. Restore must fail
	# closed in CLAIMING rather than silently crediting Peris or minting a replacement at the source.
	var wrong_holder := signal_capture.duplicate(true)
	var wrong_gs: Dictionary = wrong_holder.get("game_state", {})
	var wrong_chars: Dictionary = wrong_gs.get("characters", {})
	var wrong_items: Dictionary = wrong_gs.get("items", {})
	var claimed_item_id := str(capture_box.get("item_id", ""))
	for char_id in ["aster", "peris"]:
		var char_record: Dictionary = (wrong_chars.get(char_id, {}) as Dictionary).duplicate(true)
		var hands: Array = (char_record.get("hands", [null, null]) as Array).duplicate(true)
		for hand_i in range(hands.size()):
			if hands[hand_i] == claimed_item_id:
				hands[hand_i] = null
		if char_id == "peris":
			hands[0] = claimed_item_id
		char_record["hands"] = hands
		wrong_chars[char_id] = char_record
	var wrong_item: Dictionary = (wrong_items.get(claimed_item_id, {}) as Dictionary).duplicate(true)
	wrong_item["holder"] = "peris"
	wrong_item["location"] = "hand"
	wrong_items[claimed_item_id] = wrong_item
	wrong_gs["characters"] = wrong_chars
	wrong_gs["items"] = wrong_items
	wrong_holder["game_state"] = wrong_gs
	_apply_capture(host, chunk, wrong_holder)
	var rejected := _branch_state(chunk, open_index)
	check(str(rejected.get("reward_phase", "")) == "claiming"
		and str(rejected.get("reward_claimed_by", "")) == "aster"
		and str(rejected.get("reward_item_holder", "")) == "peris"
		and not bool(rejected.get("cache_available", true)),
		"wrong-holder injection stays unresolved and cannot retarget or respawn the reward")

	# Legacy counter-only saves retain solved topology but recover a visible source. No character is
	# guessed, no hand is credited, and the stale branch_loot number has no authority.
	var legacy := baseline.duplicate(true)
	var legacy_gs: Dictionary = legacy.get("game_state", {})
	var legacy_world: Dictionary = legacy_gs.get("world_state", {})
	var legacy_wash: Dictionary = legacy_world.get(AUTHORITY_KEY, {})
	legacy_wash["version"] = 4
	legacy_wash["branch_loot"] = 99
	legacy_wash.erase("drain_reward")
	var legacy_branches: Array = legacy_wash.get("branches", [])
	for branch_i in range(legacy_branches.size()):
		var old_branch: Dictionary = (legacy_branches[branch_i] as Dictionary).duplicate(true)
		old_branch.erase("reward_item_id")
		old_branch.erase("reward_phase")
		old_branch.erase("reward_claimed_by")
		old_branch.erase("reward_claim_serial")
		old_branch["collected"] = branch_i == open_index
		legacy_branches[branch_i] = old_branch
	legacy_wash["branches"] = legacy_branches
	legacy_world[AUTHORITY_KEY] = legacy_wash
	legacy_gs["world_state"] = legacy_world
	var legacy_items: Dictionary = legacy_gs.get("items", {})
	for item_id_v in legacy_items.keys().duplicate():
		var item: Dictionary = legacy_items[item_id_v]
		var properties: Dictionary = item.get("properties", {})
		if str(properties.get("source_wash_relay", "")) != "":
			legacy_items.erase(item_id_v)
	legacy_gs["items"] = legacy_items
	legacy["game_state"] = legacy_gs
	_apply_capture(host, chunk, legacy)
	var legacy_branch := _branch_state(chunk, open_index)
	check(str(legacy_branch.get("reward_phase", "")) == "available"
		and bool(legacy_branch.get("reward_item_at_source", false))
		and str(legacy_branch.get("reward_item_holder", "")) == ""
		and host.game_state.get_hand_items("aster").is_empty()
		and host.game_state.get_hand_items("peris").is_empty(),
		"legacy proxy reward migrates to one ground source and never mints into a hand")


func _saved_branch_reward_phase(capture: Dictionary, branch_index: int) -> String:
	var gs: Dictionary = capture.get("game_state", {})
	var world: Dictionary = gs.get("world_state", {})
	var wash: Dictionary = world.get(AUTHORITY_KEY, {})
	var branches: Array = wash.get("branches", [])
	if branch_index < 0 or branch_index >= branches.size():
		return ""
	return str((branches[branch_index] as Dictionary).get("reward_phase", ""))


func _wash_reward_item_count(host: RelayHost, source_key: String) -> int:
	var count := 0
	for item_v in host.game_state.items.values():
		var item: Dictionary = item_v
		var properties: Dictionary = item.get("properties", {})
		if str(properties.get("source_wash_relay", "")) == source_key:
			count += 1
	return count


func _boot() -> Dictionary:
	var resource = load("res://data/fragments/wash_relay.tres")
	var host := RelayHost.new()
	host.configure(resource.spawns)
	root.add_child(host)
	var chunk: Node = RelayScene.instantiate()
	chunk.call("attach_chunk_host", host, "wash_relay")
	host.add_child(chunk)
	await process_frame
	host.game_state.grid = GridWorld.from_data(chunk.call("get_grid_data"))
	chunk.call("reset_preview_state")
	chunk.call("headless_process", 0.0)
	await process_frame
	return {"host": host, "chunk": chunk}


func _branch_index(chunk: Node, kind: String) -> int:
	var branches: Array = chunk.get("_branches")
	for branch_index in range(branches.size()):
		var branch: Dictionary = branches[branch_index]
		if str(branch.get("gate_kind", "")) == kind:
			return branch_index
	return -1


func _runtime_branch(chunk: Node, branch_index: int) -> Dictionary:
	var branches: Array = chunk.get("_branches")
	return branches[branch_index] as Dictionary if branch_index >= 0 and branch_index < branches.size() else {}


func _branch_state(chunk: Node, branch_index: int) -> Dictionary:
	var state: Dictionary = chunk.call("get_preview_state")
	var branches: Array = state.get("branches", [])
	return branches[branch_index] as Dictionary if branch_index >= 0 and branch_index < branches.size() else {}


func _trigger_exact_source(host: RelayHost, source: Node, actor: String) -> bool:
	if not is_instance_valid(source) or not host.game_state.characters.has(actor):
		return false
	var data_id := str(source.get("data_id"))
	if data_id == "" or not host.game_state.has_interactable(data_id):
		return false
	host.game_state.command_stop(actor)
	host.game_state.snap_character_to(
		actor,
		host.game_state.get_interactable(data_id).get(
			"position", Vector3.INF))
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))


func _advance(host: RelayHost, chunk: Node, seconds: float) -> void:
	host.scheduler.advance_ticks(maxf(0.0, seconds))
	chunk.call("headless_process", 0.0)


func _advance_until_phase(
		host: RelayHost, chunk: Node, branch_index: int, wanted: String, budget: float) -> bool:
	var spent := 0.0
	while spent <= budget + 0.000001:
		if str(_branch_state(chunk, branch_index).get("mechanism_phase", "")) == wanted:
			return true
		_advance(host, chunk, 0.1)
		spent += 0.1
	return false


func _capture(host: RelayHost) -> Dictionary:
	return _json_round_trip({
		"scheduler": host.scheduler.serialize(),
		"game_state": host.game_state.serialize(),
	})


func _apply_capture(host: RelayHost, chunk: Node, capture: Dictionary) -> void:
	host.scheduler.clear()
	host.scheduler.deserialize(capture.get("scheduler", {}))
	host.game_state.deserialize(capture.get("game_state", {}))
	_notify_snapshot_restored(chunk)
	chunk.call("headless_process", 0.0)


func _notify_snapshot_restored(node: Node) -> void:
	if node.has_method("on_game_state_snapshot_restored"):
		node.call("on_game_state_snapshot_restored")
	for child in node.get_children():
		_notify_snapshot_restored(child)


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _discard(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
	await process_frame
	await process_frame


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
