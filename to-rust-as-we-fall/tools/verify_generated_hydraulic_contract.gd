extends SceneTree

## Focused regression for the teaching stretch's three-beat hydraulic puzzle.
## Boots the real generated chunk with the project's focused ChunkHostStub, avoiding
## the all-fragment preview registry so this remains an honest standalone tool.
## Run from the Godot project root:
##   ../Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     --log-file .godot/verify_generated_hydraulic_contract.log \
##     --script res://tools/verify_generated_hydraulic_contract.gd

const CHUNK_SCENE := preload("res://scenes/fragments/chunks/generated_stretch_chunk.tscn")
const SPEC_PATH := "res://data/generated_stretches/generated_teaching_channels_shelter_1_to_2.json"
const SPEC_ID := "generated_teaching_channels_shelter_1_to_2"

const PHASE_FIRST_SLUICE := "first_sluice"
const PHASE_CISTERN_BRIDGE := "cistern_bridge"
const PHASE_BORROWED_CURRENT := "borrowed_current"
const PHASE_FOOD_SPILLWAY := "food_spillway"
const PHASE_RESTORE_CURRENT := "restore_current"
const PHASE_EXIT_READY := "exit_ready"
const DELIVERY_IDLE := "idle"
const DELIVERY_TRAVELING := "traveling"
const DELIVERY_AVAILABLE := "available"
const DELIVERY_COLLECTED := "collected"
const CARGO_ELEVATED := "elevated"
const CARGO_FALLING := "falling"
const CARGO_STAGED := "staged"
const CARGO_TRANSPORTING := "transporting"
const CARGO_SEATED := "seated"

const REQUIRED_METHODS := [
	"get_preview_state",
	"reset_preview_state",
	"open_first_sluice",
	"release_cistern_bridge",
	"toggle_borrowed_current",
	"activate_generated_node",
	"get_preview_lighting_profile",
	"get_visual_hierarchy_state",
]

const REQUIRED_STATE_KEYS := [
	"hydraulic_enabled",
	"hydraulic_phase",
	"bridge_cargo_phase",
	"bridge_cargo_milestones",
	"bridge_scavenger_character_id",
	"bridge_scavenger_phase",
	"first_sluice_open",
	"cistern_bridge_installed",
	"borrowed_current_diverted",
	"borrowed_current_delivery_latched",
	"main_current_restored",
	"hydraulic_exit_unlocked",
	"spillway_delivery_phase",
	"spillway_delivery_in_transit",
	"flow_router_state",
]


class FoodHost:
	extends ChunkHostStub

	func spawn_preview_item(
		item_type: String, position: Vector3, properties: Dictionary = {}
	) -> String:
		return game_state.spawn_item(item_type, position, properties)

	func remove_preview_item(item_id: String) -> void:
		game_state.remove_item(item_id)

	func pick_up_preview_item(char_id: String, item_id: String) -> bool:
		return game_state.pick_up_item(char_id, item_id)

	func set_preview_character_position(char_id: String, position: Vector3) -> void:
		if game_state.characters.has(char_id):
			game_state.characters[char_id]["position"] = position

	func get_preview_character_stat(char_id: String, stat_name: String) -> float:
		return game_state.get_stat(char_id, stat_name)

	func set_preview_character_stat(char_id: String, stat_name: String, value: float) -> void:
		game_state.set_stat(char_id, stat_name, value)

	func adjust_preview_character_stat(char_id: String, stat_name: String, delta: float) -> void:
		game_state.adjust_stat(char_id, stat_name, delta)


class HydraulicHost:
	extends ChunkHostStub

	var focus_requests: Array[Dictionary] = []

	# This host verifies the hydraulic route independently from inventory. A
	# separate FoodHost below proves the successful physical transfer. Keeping
	# this probe inventory-less ensures an arrived payload cannot become abstract
	# node progress when no canonical item transaction is available.
	func spawn_preview_item(
		_item_type: String, _position: Vector3, _properties: Dictionary = {}
	) -> String:
		return ""

	func remove_preview_item(_item_id: String) -> void:
		pass

	func pick_up_preview_item(_char_id: String, _item_id: String) -> bool:
		return false

	func emphasize_preview_target(
		target: Node3D, duration := 0.9, pause_gameplay := false, opts: Dictionary = {}
	) -> bool:
		(
			focus_requests
			. append(
				{
					"target": target,
					"duration": duration,
					"pause_gameplay": pause_gameplay,
					"opts": opts.duplicate(true),
				}
			)
		)
		return true

	func last_focus_request() -> Dictionary:
		return focus_requests.back() if not focus_requests.is_empty() else {}

	func get_preview_character_stat(char_id: String, stat_name: String) -> float:
		return game_state.get_stat(char_id, stat_name)

	func set_preview_character_stat(char_id: String, stat_name: String, value: float) -> void:
		game_state.set_stat(char_id, stat_name, value)

	func adjust_preview_character_stat(char_id: String, stat_name: String, delta: float) -> void:
		game_state.adjust_stat(char_id, stat_name, delta)


var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("  PASS: %s" % message)
	else:
		failures.append(message)
		push_error("  FAIL: %s" % message)


func _run() -> void:
	EventLog.print_events = false
	print("\n=== Generated hydraulic contract ===")
	var host := HydraulicHost.new()
	host.setup()
	root.add_child(host)
	var chunk := CHUNK_SCENE.instantiate()
	var chunk_config := {
		"spec_path": SPEC_PATH,
		"game_mode": "neutral",
		"food_test": "neutral",
	}
	chunk.configure_chunk(chunk_config)
	host.register_party(chunk.get_spawn_positions())
	chunk.attach_chunk_host(host, "generated_stretch")
	host.add_child(chunk)
	for _frame in range(4):
		await process_frame
	host.grid = GridWorld.from_data(chunk.call("get_grid_data"))
	host.game_state.grid = host.grid
	chunk.reset_preview_state()
	await process_frame

	check(chunk != null and chunk.is_inside_tree(), "real generated teaching chunk boots")
	if chunk != null:
		await verify_hydraulic_contract(chunk)
	await verify_physical_spillway_food()

	host.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("\nGENERATED HYDRAULIC CONTRACT PASS (%d checks)" % checks)
		quit(0)
	else:
		print("\nGENERATED HYDRAULIC CONTRACT FAIL (%d/%d failed)" % [failures.size(), checks])
		quit(1)


func verify_hydraulic_contract(chunk: Node) -> void:
	print("\n--- Public contract ---")
	var api_ready := true
	for method_name in REQUIRED_METHODS:
		var present := chunk.has_method(str(method_name))
		check(present, "chunk exposes %s()" % method_name)
		api_ready = api_ready and present
	if not api_ready:
		return

	var initial := _state(chunk)
	check(
		str(initial.get("spec_id", "")) == SPEC_ID, "verifier is running the intended teaching spec"
	)
	var state_ready := true
	for key in REQUIRED_STATE_KEYS:
		var present := initial.has(str(key))
		check(present, "preview state exposes %s" % key)
		state_ready = state_ready and present
	if not state_ready:
		return
	var visual: Dictionary = chunk.call("get_visual_hierarchy_state")
	var lighting: Dictionary = chunk.call("get_preview_lighting_profile")
	check(
		str(visual.get("contract_id", "")) == "generated_visual_hierarchy_v1",
		"generated teaching stretch exposes its semantic visual hierarchy contract"
	)
	check(str(visual.get("biome", "")) == "channels", "saved teaching fixture resolves to Channels")
	check(
		float(lighting.get("ambient_energy_ceiling", 1.0)) < 0.62
		and float(lighting.get("directional_energy_ceiling", 1.0)) < 1.0,
		"generated lighting profile lowers broad day fill instead of flattening object contrast"
	)
	check(
		float(visual.get("decorative_fill_energy", 0.0)) > 0.0
		and float(visual.get("decorative_fill_energy", 0.0))
		< float(visual.get("interactive_light_energy", 0.0)),
		"decorative fill stays below the focused interaction-light level"
	)
	check(
		_light_energy(chunk.get("_hydraulic_first_landmark_light"))
		> _light_energy(chunk.get("_hydraulic_cistern_light")),
		"initial lighting singles out the available First Sluice without lighting locked controls equally"
	)

	await verify_browser_interaction_contract(chunk)
	chunk.call("reset_preview_state")
	await process_frame
	initial = _state(chunk)

	print("\n--- Initial state and wrong-order guards ---")
	_check_reset_state(initial, "initial build")
	var briefing := str(chunk.call("_hydraulic_help"))
	check(
		briefing.contains("Route one finite current")
		and not briefing.contains("Open the First Sluice")
		and not briefing.contains("release the Cistern Bridge"),
		"briefing states the causal goal without listing the solution sequence"
	)
	check(
		_has_external_highlight(chunk.get("_hydraulic_first_target")),
		"the teaching intervention alone receives the persistent answer marker"
	)
	check(
		not _has_external_highlight(chunk.get("_hydraulic_cistern_target"))
		and not _has_external_highlight(chunk.get("_hydraulic_diverter_target")),
		"practice and transfer targets start without persistent answer markers"
	)
	check(_mesh_visibility(chunk.get("_hydraulic_main_water"), false), "main water starts dry")
	check(
		_mesh_visibility(chunk.get("_hydraulic_bridge_current"), false),
		"the bridge channel starts dry instead of implying an untriggered current"
	)
	check(_mesh_visibility(chunk.get("_hydraulic_spillway_water"), false), "spillway starts dry")
	check(_mesh_visibility(chunk.get("_hydraulic_exit_water"), false), "exit channel starts dry")
	check(
		_bridge_blockers_match(chunk, true) and not _bridge_route_exists(chunk),
		"the real generated navigation grid has no route across the cistern gap before cargo seats"
	)
	var cargo: Node3D = chunk.get("_hydraulic_bridge_cargo")
	var cargo_instance_id := cargo.get_instance_id() if cargo != null else 0
	check(
		cargo != null and cargo.visible and chunk.get("_hydraulic_bridge_model") != null,
		"one visible portable bridge model exists from the opening shot onward"
	)
	var scavenger_v: Variant = chunk.get("_hydraulic_scavenger")
	var scavenger: Enemy = scavenger_v as Enemy if scavenger_v is Enemy else null
	var scavenger_id := str(initial.get("bridge_scavenger_character_id", ""))
	var hydraulic_host_v: Variant = chunk.get("host")
	var hydraulic_game_state_v: Variant = (
		hydraulic_host_v.get("game_state") if hydraulic_host_v is Node else null
	)
	check(
		scavenger != null,
		"the breakaway beat uses a recognizable Enemy actor rather than an unexplained animation"
	)
	check(
		scavenger != null
		and scavenger.char_id == scavenger_id
		and scavenger_id.begins_with("generated_hydraulic_scavenger:")
		and hydraulic_game_state_v is GameState
		and (hydraulic_game_state_v as GameState).characters.has(scavenger_id),
		"the scavenger is one stable-id GameState character, not a presenter proxy"
	)
	check(
		scavenger != null and not scavenger.has_meta("scripted_setpiece_actor"),
		"the authoritative body carries no scripted-setpiece escape hatch"
	)
	check(
		chunk.get("_hydraulic_lysate_source") is Node3D,
		"the scavenger has a visible lysate destination connected to the landing basin"
	)
	check(
		_label_text(chunk.get("_hydraulic_first_label")) == "FIRST SLUICE",
		"First Sluice has a persistent world-state label"
	)
	var initial_link_count := _valid_node_count(chunk.get("_causal_feedback_links"))
	check(
		initial_link_count >= 4,
		"initial build registers the four hydraulic cause/effect links (plus any generated-section links)"
	)
	check(
		not _trigger_control(chunk, "_hydraulic_cistern_control"),
		"cistern cannot release before First Sluice opens"
	)
	check(
		not bool(chunk.call("_run_solution_world_action", "release_cistern_bridge"))
		and str(_state(chunk).get("bridge_cargo_phase", "")) == CARGO_ELEVATED,
		"an out-of-order headless replay action cannot force-stage or move the cargo"
	)
	check(
		not _trigger_control(chunk, "_hydraulic_diverter_control"),
		"Borrowed Current cannot divert before the bridge is installed"
	)
	check(
		not _trigger_generated_node(chunk, "exit_shelter"),
		"shelter exit is gated before the hydraulic solve"
	)
	var blocked := _state(chunk)
	check(
		(
			not bool(blocked.get("shelter_reached", false))
			and not bool(blocked.get("hydraulic_exit_unlocked", false))
		),
		"a blocked exit attempt cannot complete or unlock the stretch"
	)

	# Wrong-order probes intentionally service distant exact Interactables. Rebuild
	# the unchanged construction baseline before the causal playthrough so those
	# negative probes cannot strand the actor beyond an unresolved topology cut.
	chunk.call("reset_preview_state")
	await process_frame
	var manual_solution: Dictionary = chunk.call("get_solution_script")
	var manual_branch_actions: Array = manual_solution.get("branch_actions", [])
	var manual_branch_results := {}
	for branch_action_v in manual_branch_actions:
		if not (branch_action_v is Dictionary):
			continue
		var branch_action := branch_action_v as Dictionary
		if str(branch_action.get("before_node", "")) != "node_02":
			continue
		manual_branch_results[str(branch_action.get("id", ""))] = bool(chunk.call(
			"_run_solution_world_action",
			str(branch_action.get("action", "")),
			branch_action
		))

	print("\n--- First Sluice -> Cistern Bridge ---")
	check(_trigger_control(chunk, "_hydraulic_first_control"), "First Sluice opens once")
	var sluice := _state(chunk)
	check(bool(sluice.get("first_sluice_open", false)), "First Sluice state latches open")
	check(
		str(sluice.get("hydraulic_phase", "")) == PHASE_CISTERN_BRIDGE,
		"opening the sluice advances to the Cistern Bridge beat"
	)
	check(
		_mesh_partial_visible(chunk.get("_hydraulic_main_water")),
		"opening the sluice starts a visible cistern-side flow front"
	)
	check(
		_mesh_visibility(chunk.get("_hydraulic_bridge_current"), false)
		and _mesh_visibility(chunk.get("_hydraulic_main_tail"), false),
		"opening the sluice does not falsely show the later downstream surge"
	)
	check(
		_label_text(chunk.get("_hydraulic_first_label")) == "FLOW OPEN",
		"completed First Sluice remains legible after its interaction disables"
	)
	check(
		not _has_external_highlight(chunk.get("_hydraulic_cistern_target")),
		"cistern practice relies on its wet-state read and hover relationship, not an answer arrow"
	)
	check(
		not _trigger_control(chunk, "_hydraulic_cistern_control"),
		"opening water early cannot teleport cargo off its still-elevated rack"
	)
	check(
		not _trigger_control(chunk, "_hydraulic_first_control"),
		"repeating First Sluice is idempotent"
	)
	var cargo_scheduler = _chunk_scheduler(chunk)
	var elevated_position := cargo.global_position if cargo != null else Vector3.ZERO
	if cargo_scheduler != null:
		cargo_scheduler.pause()
		cargo_scheduler.advance_ticks(5.0)
		chunk.call("_update_hydraulic_cargo_sequence", 5.0)
	check(
		str(_state(chunk).get("bridge_cargo_phase", "")) == CARGO_ELEVATED
		and cargo != null
		and cargo.global_position.is_equal_approx(elevated_position),
		"pausing freezes the enemy and elevated cargo before contact"
	)
	if cargo_scheduler != null:
		cargo_scheduler.resume()

	await _advance_hydraulic_sequence(chunk, 1.8)
	var falling := _state(chunk)
	check(
		str(falling.get("bridge_cargo_phase", "")) == CARGO_FALLING,
		"scavenger contact deterministically dislodges the elevated cargo"
	)
	check(
		_bridge_blockers_match(chunk, true),
		"falling cargo cannot open navigation through the gap"
	)
	await _advance_hydraulic_sequence(chunk, 1.05)
	var staged := _state(chunk)
	check(
		str(staged.get("bridge_cargo_phase", "")) == CARGO_STAGED,
		"the same cargo lands in the cistern staging basin"
	)
	check(
		_label_text(chunk.get("_hydraulic_bridge_cargo_label"))
		== "CARGO STAGED // SCAVENGER CLEARING",
		"the staged span preserves the visible enemy-clearance step"
	)
	check(
		not _is_mouse_pickable(chunk.get("_hydraulic_cistern_target"))
		and not _trigger_control(chunk, "_hydraulic_cistern_control"),
		"staged cargo cannot be released while the scavenger is still crossing its route"
	)
	await _advance_hydraulic_sequence(chunk, 1.45)
	var intro_milestones: Array = _state(chunk).get("bridge_cargo_milestones", [])
	check(
		_milestone_events(intro_milestones).slice(0, 4)
		== [
			"cargo_elevated_on_breakaway_rack",
			"scavenger_dislodged_cargo",
			"cargo_staged_in_basin",
			"scavenger_reached_lysate_source",
		],
		"the opening beat records the readable enemy -> fall -> basin -> lysate chain in order"
	)
	check(
		_scavenger_milestone_ticks_match_physical_route(chunk, intro_milestones),
		"cargo-event ticks derive from body travel distance, speed, and the physical fall"
	)
	check(
		_label_text(chunk.get("_hydraulic_bridge_cargo_label"))
		== "CARGO STAGED // NEEDS CURRENT"
		and _is_mouse_pickable(chunk.get("_hydraulic_cistern_target"))
		and _light_energy(chunk.get("_hydraulic_cistern_light"))
		> _light_energy(chunk.get("_hydraulic_first_landmark_light")),
		"only enemy clearance transfers emphasis and interaction to the cistern release"
	)

	check(
		_trigger_control(chunk, "_hydraulic_cistern_control"),
		"cistern release starts carrying the staged span"
	)
	var transporting := _state(chunk)
	var transport_start_position := cargo.global_position if cargo != null else Vector3.ZERO
	if cargo_scheduler != null:
		cargo_scheduler.pause()
		cargo_scheduler.advance_ticks(5.0)
		chunk.call("_update_hydraulic_cargo_sequence", 5.0)
	check(
		str(_state(chunk).get("bridge_cargo_phase", "")) == CARGO_TRANSPORTING
		and cargo != null
		and cargo.global_position.is_equal_approx(transport_start_position),
		"pausing freezes the cargo and cannot finish bridge transport"
	)
	if cargo_scheduler != null:
		cargo_scheduler.resume()
	check(
		str(transporting.get("bridge_cargo_phase", "")) == CARGO_TRANSPORTING
		and not bool(transporting.get("cistern_bridge_installed", false)),
		"release enters a visible transport state instead of instantly swapping in a bridge"
	)
	check(
		_mesh_partial_visible(chunk.get("_hydraulic_bridge_current")),
		"releasing the cistern starts the visible surge that carries the cargo"
	)
	check(
		_bridge_blockers_match(chunk, true) and not _bridge_route_exists(chunk),
		"the gap remains non-traversable for the full cargo transport"
	)
	check(
		_label_text(chunk.get("_hydraulic_cistern_label"))
		== "CURRENT RELEASED // CARGO AFLOAT",
		"the cistern and cargo labels describe the unfolding consequence"
	)
	var staged_position := cargo.global_position if cargo != null else Vector3.ZERO
	await _advance_hydraulic_sequence(chunk, 1.5)
	check(
		cargo != null
		and cargo.get_instance_id() == cargo_instance_id
		and cargo.global_position.distance_to(staged_position) > 0.5,
		"the original cargo visibly travels downstream rather than being replaced"
	)
	check(
		not bool(_state(chunk).get("cistern_bridge_installed", false))
		and _bridge_blockers_match(chunk, true)
		and not _bridge_route_exists(chunk),
		"mid-transport visuals cannot make the unfinished bridge traversable"
	)
	await _advance_hydraulic_sequence(chunk, 1.55)
	var bridge := _state(chunk)
	check(
		bool(bridge.get("cistern_bridge_installed", false))
		and str(bridge.get("bridge_cargo_phase", "")) == CARGO_SEATED,
		"only the seated cargo latches the mandatory bridge installed"
	)
	check(
		str(bridge.get("hydraulic_phase", "")) == PHASE_EXIT_READY
		and bool(bridge.get("hydraulic_exit_unlocked", false)),
		"seating the span feeds the mandatory main route and opens the optional allocation fork"
	)
	check(
		_bridge_blockers_match(chunk, false) and _bridge_route_exists(chunk),
		"navigation opens only after the same cargo seats across the gap"
	)
	check(
		_mesh_partial_visible(chunk.get("_hydraulic_main_tail")),
		"the downstream flow front starts only after the cargo has seated as a bridge"
	)
	check(
		_label_text(chunk.get("_hydraulic_cistern_label")) == "BRIDGE SEATED",
		"completed Cistern Release remains legible after its interaction disables"
	)
	check(
		not _has_external_highlight(chunk.get("_hydraulic_diverter_target")),
		"finite-current allocation is an independent application with no answer arrow"
	)
	check(
		_light_energy(chunk.get("_hydraulic_diverter_light"))
		> _light_energy(chunk.get("_hydraulic_cistern_light")),
		"installing the bridge transfers local emphasis to the available diverter"
	)
	check(
		not _trigger_control(chunk, "_hydraulic_cistern_control"),
		"releasing the cistern twice cannot duplicate the bridge"
	)

	print("\n--- Borrowed Current delivery and restoration ---")
	check(
		_trigger_control(chunk, "_hydraulic_diverter_control"),
		"first valid diverter use borrows the main current"
	)
	var diverted := _state(chunk)
	check(
		(
			bool(diverted.get("borrowed_current_diverted", false))
			and not bool(diverted.get("main_current_restored", false))
			and str(diverted.get("spillway_delivery_phase", "")) == DELIVERY_TRAVELING
		),
		"diversion starves the main route and launches one physical delivery"
	)
	check(
		str(diverted.get("hydraulic_phase", "")) == PHASE_FOOD_SPILLWAY,
		"diversion advances to the food spillway beat"
	)
	check(
		(
			(diverted.get("flow_router_state", {}) as Dictionary).get("current_route") == &"spillway"
			and ((diverted.get("flow_router_state", {}) as Dictionary).get("pending_flows", []) as Array).size() == 1
			and str((((diverted.get("flow_router_state", {}) as Dictionary).get("pending_flows", []) as Array)[0] as Dictionary).get("route", "")) == "spillway"
		),
		"the reusable router records the delivery's captured spillway route"
	)
	check(
		_mesh_partial_visible(chunk.get("_hydraulic_spillway_water")),
		"diversion begins a visible traveling flow front instead of toggling the whole path"
	)
	check(
		_mesh_visibility(chunk.get("_hydraulic_main_tail"), false),
		"diversion visibly drains the competing main tail"
	)
	check(
		_is_mouse_pickable(chunk.get("_hydraulic_diverter_target"))
		and not _is_mouse_pickable(chunk.get("_hydraulic_catch_target")),
		"the reversible valve stays live while the not-yet-arrived catch stays unavailable"
	)
	check(
		_distinct_valid_nodes(
			[chunk.get("_hydraulic_spillway_link"), chunk.get("_hydraulic_exit_link")]
		),
		"diverter consequences have distinct feedback links"
	)
	check(
		not _trigger_generated_node(chunk, "exit_shelter"),
		"the shelter is genuinely unavailable while the finite current is diverted"
	)
	check(
		_trigger_control(chunk, "_hydraulic_diverter_control"),
		"the player may restore the main route before the optional delivery arrives"
	)
	var restored_early := _state(chunk)
	check(
		(
			not bool(restored_early.get("borrowed_current_diverted", true))
			and bool(restored_early.get("main_current_restored", false))
			and bool(restored_early.get("hydraulic_exit_unlocked", false))
			and str(restored_early.get("spillway_delivery_phase", "")) == DELIVERY_TRAVELING
		),
		"restoring early reopens the shelter without erasing the captured spillway payload"
	)
	check(
		(restored_early.get("flow_router_state", {}) as Dictionary).get("current_route") == &"main"
		and str(((((restored_early.get("flow_router_state", {}) as Dictionary).get("pending_flows", []) as Array)[0]) as Dictionary).get("route", "")) == "spillway",
		"valve restoration changes future flow while the launched payload keeps its old route"
	)
	var marker: MeshInstance3D = (chunk.get("_hydraulic_spillway_food_cache") as Dictionary).get("marker", null)
	var marker_start := marker.global_position if marker != null else Vector3.ZERO
	await _advance_hydraulic_sequence(chunk, 1.3)
	check(
		marker != null and marker.visible and marker.global_position.distance_to(marker_start) > 0.25,
		"the same visible lysate object moves along the captured route"
	)
	await _advance_hydraulic_sequence(chunk, 1.4)
	var delivered := _state(chunk)
	check(
		str(delivered.get("spillway_delivery_phase", "")) == DELIVERY_AVAILABLE
		and bool(delivered.get("borrowed_current_delivery_latched", false))
		and bool(delivered.get("hydraulic_exit_unlocked", false)),
		"captured-route delivery arrives while the independently restored shelter stays open"
	)
	check(
		_is_mouse_pickable(chunk.get("_hydraulic_catch_target")) and marker != null and marker.visible,
		"arrival makes the persistent payload and its physical pickup available"
	)
	check(
		not _trigger_generated_node(chunk, "node_04"),
		"an inventory-less host cannot turn the optional physical payload into abstract progress"
	)
	check(
		marker != null and marker.visible
		and str(_state(chunk).get("spillway_delivery_phase", "")) == DELIVERY_AVAILABLE,
		"failed pickup leaves the physical lysate in the catch"
	)
	# This probe intentionally skipped the optional food, but it still has to solve the
	# topology that the generated contract declares mandatory. Activate the emitted
	# branch producers just as a live player would before asserting that the shelter is
	# available; otherwise this test would be asking the real route blockers to disappear.
	for branch_action_v in manual_branch_actions:
		if not (branch_action_v is Dictionary):
			continue
		var branch_action := branch_action_v as Dictionary
		if str(branch_action.get("before_node", "")) != "exit_shelter":
			continue
		manual_branch_results[str(branch_action.get("id", ""))] = bool(chunk.call(
			"_run_solution_world_action",
			str(branch_action.get("action", "")),
			branch_action
		))
	var manual_branches_resolved := (
		manual_branch_actions.size() == 2
		and manual_branch_results.size() == manual_branch_actions.size()
		and manual_branch_results.values().all(func(result): return bool(result))
	)
	check(
		manual_branches_resolved
		and bool(chunk.call("_all_mandatory_branch_spans_bridged")),
		"the manual solve bridges both emitted mandatory topology cuts"
	)
	# EXIT now validates the exact authored shelter rather than accepting any sanctuary
	# registered in GameState. Put the full conscious active roster on that pad before
	# invoking the direct interaction seam this verifier intentionally uses.
	var exit_region: Dictionary = chunk.call("_exit_shelter_region")
	var exit_center: Vector3 = exit_region.get("center", Vector3.INF)
	var exit_offsets := [Vector3(0.0, 0.0, -1.1), Vector3.ZERO, Vector3(0.0, 0.0, 1.1)]
	var manual_host: Node = chunk.get("host")
	if manual_host != null and exit_center != Vector3.INF:
		var manual_party: Array = _state(chunk).get("active_party", [])
		for index in range(manual_party.size()):
			manual_host.call(
				"set_preview_character_position",
				str(manual_party[index]),
				exit_center + (exit_offsets[index] if index < exit_offsets.size() else Vector3.ZERO)
			)
	check(
		_trigger_generated_node(chunk, "exit_shelter"),
		"the mandatory solve can finish without taking the optional food"
	)
	check(
		bool(_state(chunk).get("shelter_reached", false)),
		"successful exit records shelter completion"
	)
	var completed_state := _state(chunk)
	var completed_host: Node = chunk.get("host")
	var completed_game_state: GameState = (
		completed_host.get("game_state")
		if completed_host != null and completed_host.get("game_state") is GameState
		else null
	)
	var expected_paid_rest_count := 0
	if completed_game_state != null:
		for character_id_v in completed_state.get("active_party", []):
			var character_id := str(character_id_v)
			if not completed_game_state.characters.has(character_id):
				continue
			if completed_game_state.is_resting(character_id):
				expected_paid_rest_count += 1
	check(
		is_equal_approx(
			float(completed_state.get("effective_party_atp", 0.0)),
			float(completed_state.get("effective_party_atp_capacity", -1.0))
			- float(expected_paid_rest_count)
		),
		"shelter arrival charges exactly the bodies that begin canonical rest, never the party abstractly"
	)

	print("\n--- Reset ---")
	chunk.call("reset_preview_state")
	_check_reset_state(_state(chunk), "preview reset")
	check(
		_trigger_control(chunk, "_hydraulic_first_control"),
		"coarse-step probe opens First Sluice"
	)
	await _advance_hydraulic_sequence(chunk, 4.3)
	var coarse_intro: Array = _state(chunk).get("bridge_cargo_milestones", [])
	check(
		str(_state(chunk).get("bridge_cargo_phase", "")) == CARGO_STAGED
		and _scavenger_milestone_ticks_match_physical_route(chunk, coarse_intro),
		"one coarse scheduler step preserves body arrival, cargo fall, and lysate arrival order"
	)
	chunk.call("reset_preview_state")

	print("\n--- Emitted hydraulic replay ---")
	var solution: Dictionary = chunk.call("get_solution_script")
	var world_actions: Array = solution.get("world_actions", [])
	var branch_actions: Array = solution.get("branch_actions", [])
	var emitted_spec: Dictionary = chunk.get("_spec")
	var optional_world_actions: Array = (
		emitted_spec.get("systems_contract", {}).get(
			"optional_world_actions", []
		)
	)
	check(
		world_actions.size() == 2
		and str((world_actions[0] as Dictionary).get("action", "")) == "open_sluice"
		and str((world_actions[0] as Dictionary).get("before_node", "")) == "node_02"
		and bool((world_actions[0] as Dictionary).get("required_for_exit", false))
		and str((world_actions[0] as Dictionary).get("route_role", ""))
			== "mandatory_main_route"
		and str((world_actions[1] as Dictionary).get("action", "")) == "release_bridge"
		and str((world_actions[1] as Dictionary).get("before_node", "")) == "node_03"
		and bool((world_actions[1] as Dictionary).get("required_for_exit", false))
		and str((world_actions[1] as Dictionary).get("route_role", ""))
			== "mandatory_main_route",
		"the golden solution emits only the two mandatory main-route interventions"
	)
	var expected_branch_boundaries := ["node_02", "exit_shelter"]
	var mandatory_branches_valid := branch_actions.size() == expected_branch_boundaries.size()
	for branch_index in range(branch_actions.size()):
		var branch_action_v: Variant = branch_actions[branch_index]
		if not (branch_action_v is Dictionary) \
				or branch_index >= expected_branch_boundaries.size():
			mandatory_branches_valid = false
			continue
		var branch_action := branch_action_v as Dictionary
		mandatory_branches_valid = mandatory_branches_valid \
			and str(branch_action.get("action", "")) == "activate" \
			and str(branch_action.get("runtime_handler", "")) == "branch_span_producer" \
			and str(branch_action.get("role", "")) == "mandatory_producer" \
			and bool(branch_action.get("required_for_progress", false)) \
			and bool(branch_action.get("cannot_bypass_unresolved", false)) \
			and bool(branch_action.get("wait_for_completion", false)) \
			and str(branch_action.get("expected_phase", "")) == "bridged" \
			and str(branch_action.get("before_node", "")) \
				== expected_branch_boundaries[branch_index] \
			and not (branch_action.get("consumer_cells", []) as Array).is_empty()
	check(
		mandatory_branches_valid,
		"the golden solution emits both non-bypassable branch producers at their route cuts"
	)
	var mandatory_node_actions: Array = solution.get("actions", [])
	check(
		not mandatory_node_actions.any(func(action):
			return action is Dictionary and str((action as Dictionary).get("node", "")) == "node_04"),
		"the golden solution does not claim that it caught the optional spillway reward"
	)
	var optional_projection_valid := true
	for solution_path_v in emitted_spec.get("solution_paths", []):
		if not (solution_path_v is Dictionary):
			continue
		var node_04_approach := {}
		for approach_v in (solution_path_v as Dictionary).get("approach_per_node", []):
			if approach_v is Dictionary and str((approach_v as Dictionary).get("node", "")) == "node_04":
				node_04_approach = approach_v as Dictionary
				break
		optional_projection_valid = optional_projection_valid \
			and str(node_04_approach.get("approach_id", "")) == "skip_optional_interaction" \
			and str(node_04_approach.get("optional_runtime_handler", "")) \
				== "authored_hydraulic_spillway_food_v1"
	check(optional_projection_valid,
		"solution paths mark node_04 as an optional interaction while retaining its real handler")
	var expected_optional_actions := ["divert", "restore", "catch"]
	var optional_actions_valid := optional_world_actions.size() == expected_optional_actions.size()
	for optional_index in range(optional_world_actions.size()):
		var optional_action_v: Variant = optional_world_actions[optional_index]
		if not (optional_action_v is Dictionary):
			optional_actions_valid = false
			continue
		var optional_action := optional_action_v as Dictionary
		optional_actions_valid = optional_actions_valid \
			and optional_index < expected_optional_actions.size() \
			and str(optional_action.get("action", "")) == expected_optional_actions[optional_index] \
			and not bool(optional_action.get("required_for_exit", true)) \
			and str(optional_action.get("route_role", "")) == "optional_risk_reward" \
			and str(optional_action.get("before_node", "")) == "node_04"
		if str(optional_action.get("action", "")) == "divert":
			var capture: Dictionary = optional_action.get("captured_route_timing", {})
			optional_actions_valid = optional_actions_valid \
				and str(capture.get("captured_route", "")) == "spillway" \
				and str(capture.get("route_captured_at", "")) == "launch" \
				and is_equal_approx(float(capture.get("travel_delay_seconds", 0.0)), 2.6) \
				and bool(capture.get("valve_changes_after_launch_do_not_redirect", false))
		elif str(optional_action.get("action", "")) == "restore":
			optional_actions_valid = optional_actions_valid \
				and str(optional_action.get("in_flight_payload_effect", "")) \
					== "continues_on_captured_spillway_route"
		elif str(optional_action.get("action", "")) == "catch":
			optional_actions_valid = optional_actions_valid \
				and str(optional_action.get("requires", "")) == "one_free_carrier_hand" \
				and is_zero_approx(float(optional_action.get("atp_change_on_pickup", -1.0)))
	check(
		optional_actions_valid,
		"optional divert, restore, and catch preserve captured-route timing and physical pickup costs"
	)
	var replay: Dictionary = chunk.call("replay_generated_solution")
	check(bool(replay.get("complete", false)), "emitted node and hydraulic actions complete the stretch")
	check(
		int(replay.get("world_steps", 0)) == world_actions.size() + branch_actions.size(),
		"replay consumes every emitted hydraulic intervention and mandatory branch producer"
	)
	check(
		bool(_state(chunk).get("main_current_restored", false)),
		"minimal replay finishes with the bridge-fed main current visibly ready"
	)
	check(
		str(_state(chunk).get("spillway_delivery_phase", "")) == DELIVERY_IDLE
		and not (_state(chunk).get("completed_nodes", []) as Array).has("node_04"),
		"minimal replay skips the optional catch without manufacturing delivery or completion"
	)
	chunk.call("reset_preview_state")
	var consumed_world_actions := {}
	var node_02_count := int(chunk.call(
		"_apply_solution_world_actions_before_node", solution, "node_02", consumed_world_actions
	))
	var node_03_count := int(chunk.call(
		"_apply_solution_world_actions_before_node", solution, "node_03", consumed_world_actions
	))
	var exit_shelter_count := int(chunk.call(
		"_apply_solution_world_actions_before_node",
		solution,
		"exit_shelter",
		consumed_world_actions
	))
	var repeated_exit_shelter_count := int(chunk.call(
		"_apply_solution_world_actions_before_node",
		solution,
		"exit_shelter",
		consumed_world_actions
	))
	var first_node_04_count := int(
		chunk.call(
			"_apply_solution_world_actions_before_node",
			solution,
			"node_04",
			consumed_world_actions
		)
	)
	var repeated_node_04_count := int(
		chunk.call(
			"_apply_solution_world_actions_before_node",
			solution,
			"node_04",
			consumed_world_actions
		)
	)
	check(
		node_02_count == 2
		and node_03_count == 1
		and exit_shelter_count == 1
		and repeated_exit_shelter_count == 0,
		"declared boundaries apply two hydraulic and two branch actions exactly once")
	check(first_node_04_count == 0, "the mandatory boundary emits no hidden spillway action")
	check(repeated_node_04_count == 0, "a repeated traversal boundary cannot replay world actions")
	check(
		not bool(_state(chunk).get("borrowed_current_diverted", false))
		and bool(_state(chunk).get("main_current_restored", false))
		and str(_state(chunk).get("spillway_delivery_phase", "")) == DELIVERY_IDLE,
		"mandatory replay leaves the optional finite-current decision untouched"
	)
	chunk.call("reset_preview_state")

	print("\n--- In-place rebuild ---")
	(
		chunk
		. call(
			"configure_chunk",
			{
				"spec_path": SPEC_PATH,
				"game_mode": "neutral",
				"food_test": "neutral",
			}
		)
	)
	await process_frame
	check(
		_valid_node_count(chunk.get("_causal_feedback_links")) == initial_link_count,
		"in-place rebuild replaces rather than accumulates causal-link references"
	)


func verify_browser_interaction_contract(chunk: Node) -> void:
	print("\n--- Browser interaction targets ---")
	# Start from the honest opening state. The target audit advances the same
	# GameState-owned scavenger movement plans as live play when it needs later controls.
	var node_targets_v: Variant = chunk.get("_node_targets")
	var node_targets: Dictionary = (
		node_targets_v as Dictionary if node_targets_v is Dictionary else {}
	)
	_check_generated_node_outline_ownership(chunk, node_targets)
	var controls := [
		{
			"node_id": "node_01",
			"label": "First Sluice",
			"control": chunk.get("_hydraulic_first_control"),
		},
		{
			"node_id": "node_02",
			"label": "Cistern Release",
			"control": chunk.get("_hydraulic_cistern_control"),
		},
		{
			"node_id": "node_03",
			"label": "Borrowed Current",
			"control": chunk.get("_hydraulic_diverter_control"),
		},
	]
	var control_targets: Dictionary = {}
	for entry_v in controls:
		var entry := entry_v as Dictionary
		var node_id := str(entry["node_id"])
		var label := str(entry["label"])
		var control: Node = entry["control"]
		var node_target: Node = node_targets.get(node_id, null)
		var control_target := _linked_outline_target(control)
		control_targets[node_id] = control_target
		var expects_generated_target := node_id == "node_02"
		check(
			(node_target != null) == expects_generated_target,
			(
				"node_02 keeps its physical-lysate target"
				if expects_generated_target
				else "%s remains layout-only beside its authored hydraulic control" % node_id
			)
		)
		if node_target != null:
			var collision_size := _box_collision_size(node_target)
			check(
				collision_size != Vector3.ZERO and collision_size.x <= 2.4 and collision_size.z <= 2.4,
				"%s generated-node target keeps a compact mouse-pick footprint" % node_id
			)
			check(
				(
					control is Node3D
					and not _box_contains_world_point(node_target, (control as Node3D).global_position)
				),
				"%s generated-node target cannot steal %s's mouse pick" % [node_id, label]
			)
		check(
			control is CollisionObject3D and not (control as CollisionObject3D).input_ray_pickable,
			"%s invisible Area cannot steal another hydraulic target's mouse pick" % label
		)
		var prompt_copy := str(control.get("tutorial_label")) if control != null else ""
		check(
			prompt_copy.begins_with("{command} // "),
			"%s hover prompt derives its interaction input from the live command binding" % label
		)
		check(
			InputLabels.expand(prompt_copy).begins_with(InputLabels.action_label("command")),
			"%s hover prompt resolves to the player's current command binding" % label
		)
		if node_target != null:
			_check_delegate_target_resolution(node_target, "%s generated-node target" % node_id)
		_check_delegate_target_resolution(control_target, "%s outline target" % label)
	for node_id in ["entry", "exit_shelter"]:
		var boundary_target: Node = node_targets.get(node_id, null)
		if node_id == "entry":
			check(boundary_target == null, "entry boundary remains traversal-only")
		else:
			var boundary_size := _box_collision_size(boundary_target)
			check(
				boundary_size != Vector3.ZERO and boundary_size.x <= 2.4 and boundary_size.z <= 2.4,
				"%s target stays compact so another helix layer cannot steal control picks" % node_id
			)
			_check_delegate_target_resolution(boundary_target, "%s generated-node target" % node_id)

	var first_target: Node = control_targets.get("node_01", null)
	var cistern_target: Node = control_targets.get("node_02", null)
	var diverter_target: Node = control_targets.get("node_03", null)
	var catch_target: Node = node_targets.get("node_04", null)
	var exit_target: Node = node_targets.get("exit_shelter", null)
	var diverter_node_target: Node = node_targets.get("node_03", null)
	check(
		diverter_node_target == null and diverter_target != null,
		"Borrowed Current uses only its authored control, with no generic node_03 pick volume"
	)
	var node_03_flat_v: Variant = chunk.call("_node_position", "node_03")
	var node_04_flat_v: Variant = chunk.call("_node_position", "node_04")
	var expected_diverter_world := Vector3.INF
	if node_03_flat_v is Vector3 and node_04_flat_v is Vector3:
		var expected_diverter_flat := (
			(node_03_flat_v as Vector3).lerp(node_04_flat_v as Vector3, 0.4) + Vector3.UP * 0.05
		)
		var expected_world_v: Variant = chunk.call("_warp_pos", expected_diverter_flat)
		if expected_world_v is Vector3:
			expected_diverter_world = expected_world_v as Vector3
	var diverter_control_v: Variant = chunk.get("_hydraulic_diverter_control")
	var diverter_control: Node3D = (
		diverter_control_v as Node3D if diverter_control_v is Node3D else null
	)
	check(
		(
			diverter_control != null
			and expected_diverter_world != Vector3.INF
			and diverter_control.global_position.distance_to(expected_diverter_world) <= 0.05
		),
		"Borrowed Current remains centered on the authored node_03-to-node_04 route"
	)
	var exit_beacon_v: Variant = chunk.get("_hydraulic_exit_beacon")
	var exit_beacon: MeshInstance3D = (
		exit_beacon_v as MeshInstance3D if exit_beacon_v is MeshInstance3D else null
	)
	var exit_delegate: Node = null
	if exit_target != null and exit_target.has_method("get_interaction_delegate"):
		exit_delegate = exit_target.call("get_interaction_delegate")
	var exit_target_position := _resolved_target_position(exit_target)
	var exit_highlight_meshes_v: Variant = (
		exit_target.get("_highlight_meshes") if exit_target != null else []
	)
	var retired_exit_target := chunk.get_node_or_null(NodePath("GeneratedNodeTarget_exit_shelter"))
	check(
		exit_target != null and str(exit_target.name) == "HydraulicExitBeaconTarget",
		"exit_shelter uses a dedicated visible-beacon target"
	)
	check(
		(
			exit_beacon != null
			and exit_target_position != Vector3.INF
			and exit_target_position.distance_to(exit_beacon.global_position) <= 1.25
		),
		"exit interaction resolves at the visible hydraulic beacon"
	)
	var host_v: Variant = chunk.get("host")
	var game_state_v: Variant = host_v.get("game_state") if host_v is Node else null
	if game_state_v is GameState:
		var game_state := game_state_v as GameState
		var prior_position := game_state.get_position("aster")
		var exit_data_position := exit_target_position
		var coord_map_v: Variant = chunk.call("get_coord_map")
		if coord_map_v != null and coord_map_v.has_method("to_data"):
			exit_data_position = coord_map_v.call("to_data", exit_target_position)
		game_state.snap_character_to("aster", exit_data_position)
		check(
			game_state.is_at_shelter("aster"),
			(
				"the visible exit-beacon destination is physically inside the registered shelter "
				+ "(world=%s, data=%s, shelters=%s)"
				% [exit_target_position, exit_data_position, game_state.get("_shelters")]
			)
		)
		game_state.snap_character_to("aster", prior_position)
	check(
		(
			exit_beacon != null
			and exit_highlight_meshes_v is Array
			and (exit_highlight_meshes_v as Array).has(exit_beacon)
		),
		"exit outline highlights the visible hydraulic beacon"
	)
	check(
		(
			retired_exit_target != null
			and retired_exit_target != exit_target
			and not _is_mouse_pickable(retired_exit_target)
		),
		"opaque shelter dressing cannot retain the old exit mouse target"
	)
	check(
		exit_delegate != null and str(exit_delegate.get("tutorial_label")) == "SHELTER LOCKED",
		"locked exit beacon truthfully names its unavailable state"
	)
	check(
		_label_text(chunk.get("_hydraulic_exit_label")) == "SHELTER CHANNEL // DRY",
		"exit beacon initially communicates observed state instead of prescribing the answer"
	)
	var hydraulic_targets: Array[Node] = [
		first_target,
		cistern_target,
		diverter_target,
		catch_target,
		exit_target,
	]
	var landmark_meshes_v: Variant = chunk.get("_hydraulic_first_landmark_meshes")
	var landmark_bounds := _combined_live_mesh_bounds(landmark_meshes_v)
	var lever_mesh_v: Variant = chunk.find_child("FirstSluiceControlHandle", true, false)
	var lever_bounds := _combined_live_mesh_bounds([lever_mesh_v])
	check(
		_valid_live_mesh_count(landmark_meshes_v) >= 4,
		"First Sluice landmark is a multi-mesh silhouette, not another small lever"
	)
	check(
		(
			landmark_bounds.size.y > 0.0
			and lever_bounds.size.y > 0.0
			and landmark_bounds.size.y >= lever_bounds.size.y * 3.0
		),
		"First Sluice landmark is visibly taller than its honest interaction lever"
	)
	_check_only_hydraulic_next_highlight(
		hydraulic_targets, first_target, "initial First Sluice step"
	)
	check(
		_label_text(chunk.get("_hydraulic_first_label")) == "FIRST SLUICE",
		"initial First Sluice status names the available first action"
	)
	check(
		_label_text(chunk.get("_hydraulic_cistern_label"))
		== "LOOSE SPAN ON RACK // CISTERN DRY",
		"initial Cistern status communicates the elevated span and missing water"
	)
	check(
		_label_text(chunk.get("_hydraulic_diverter_label")) == "CURRENT LOCKED",
		"initial diverter status explicitly communicates its locked state"
	)
	check(_is_mouse_pickable(first_target), "First Sluice outline starts mouse-pickable")
	check(
		not _is_mouse_pickable(cistern_target),
		"locked Cistern Release outline cannot intercept mouse picks"
	)
	check(
		not _is_mouse_pickable(diverter_target),
		"locked Borrowed Current outline cannot intercept mouse picks"
	)
	check(
		not _is_mouse_pickable(catch_target),
		"inactive spillway catch outline cannot intercept earlier hydraulic steps"
	)

	check(
		_trigger_control(chunk, "_hydraulic_first_control"),
		"interaction-target probe opens First Sluice"
	)
	check(
		not _is_mouse_pickable(first_target),
		"completed First Sluice outline stops intercepting mouse picks"
	)
	check(
		not _is_mouse_pickable(cistern_target)
		and _label_text(chunk.get("_hydraulic_cistern_label"))
		== "WAIT // SCAVENGER APPROACHING",
		"Cistern Release stays unavailable while the real scavenger approaches the rack"
	)
	check(
		not _is_mouse_pickable(diverter_target),
		"Borrowed Current outline stays locked until the bridge is installed"
	)
	_check_no_hydraulic_next_highlight(
		hydraulic_targets, "post-sluice guided Cistern Release practice"
	)
	check(
		_label_text(chunk.get("_hydraulic_first_label")) == "FLOW OPEN",
		"First Sluice status transitions to FLOW OPEN after activation"
	)
	check(
		bool(chunk.call("_advance_hydraulic_scavenger_chain_for_headless")),
		"interaction-target probe advances the actual scavenger body through rack and lysate arrival"
	)
	check(
		_is_mouse_pickable(cistern_target),
		"Cistern Release becomes pickable only after cargo lands and the scavenger clears"
	)
	check(
		_label_text(chunk.get("_hydraulic_cistern_label"))
		== "CISTERN CHARGED // CARGO STAGED",
		"Cistern status transitions from dry to its available current release"
	)
	check(
		_label_text(chunk.get("_hydraulic_diverter_label")) == "CURRENT LOCKED",
		"diverter status remains locked until the bridge is installed"
	)

	check(
		_trigger_control(chunk, "_hydraulic_cistern_control"),
		"interaction-target probe releases current onto the staged span"
	)
	check(
		not _is_mouse_pickable(cistern_target),
		"active Cistern Release outline stops intercepting duplicate mouse picks"
	)
	check(
		not _is_mouse_pickable(diverter_target),
		"Borrowed Current stays locked while the cargo is visibly in transit"
	)
	check(
		_label_text(chunk.get("_hydraulic_cistern_label"))
		== "CURRENT RELEASED // CARGO AFLOAT",
		"Cistern status names the intermediate carry state"
	)
	await _advance_hydraulic_sequence(chunk, 3.001)
	check(
		_is_mouse_pickable(diverter_target),
		"Borrowed Current outline becomes pickable only after the bridge is seated"
	)
	_check_only_hydraulic_next_highlight(
		hydraulic_targets, exit_target, "post-bridge optional-allocation fork"
	)
	check(
		_label_text(chunk.get("_hydraulic_cistern_label")) == "BRIDGE SEATED",
		"Cistern status transitions to BRIDGE SEATED after the transport completes"
	)
	check(
		_label_text(chunk.get("_hydraulic_diverter_label")) == "MAIN FED // SPILLWAY DRY",
		"available diverter exposes the finite-current baseline"
	)

	var node_04_target: Node = node_targets.get("node_04", null)
	var node_04_delegate: Node = null
	if node_04_target != null and node_04_target.has_method("get_interaction_delegate"):
		node_04_delegate = node_04_target.call("get_interaction_delegate")
	var catch_mesh_v: Variant = chunk.get("_hydraulic_spillway_catch")
	var catch_mesh: MeshInstance3D = (
		catch_mesh_v as MeshInstance3D if catch_mesh_v is MeshInstance3D else null
	)
	check(
		node_04_target != null and node_04_delegate != null,
		"node_04 catch has a live outline target and interaction delegate"
	)
	_check_delegate_target_resolution(node_04_target, "node_04 catch outline target")
	check(
		node_04_delegate != null and str(node_04_delegate.get("tutorial_label")) == "CATCH EMPTY",
		"neutral node_04 delegate truthfully starts as an empty catch"
	)
	var catch_description := (
		str(node_04_delegate.get("description")).to_lower() if node_04_delegate != null else ""
	)
	check(
		"optional" in catch_description or "divert" in catch_description,
		"node_04 delegate truthfully describes the optional diverted delivery"
	)
	var catch_target_position := _resolved_target_position(node_04_target)
	var catch_world_position := catch_mesh.global_position if catch_mesh != null else Vector3.INF
	var catch_collision_size := _box_collision_size(node_04_target)
	var catch_collision_bounds := _box_collision_world_bounds(node_04_target)
	var catch_mesh_bounds := _combined_live_mesh_bounds([catch_mesh])
	check(
		(
			catch_target_position != Vector3.INF
			and catch_world_position != Vector3.INF
			and catch_target_position.distance_to(catch_world_position) <= 1.25
		),
		"node_04 interaction target resolves at the visible food-spillway catch"
	)
	check(
		(
			catch_collision_size != Vector3.ZERO
			and catch_collision_size.x <= 2.4
			and catch_collision_size.y >= 3.6
			and catch_collision_size.z <= 2.4
		),
		"node_04 catch keeps a compact horizontal footprint with a camera-safe pick column"
	)
	check(
		(
			catch_collision_bounds.size != Vector3.ZERO
			and catch_mesh_bounds.size != Vector3.ZERO
			and catch_collision_bounds.position.y >= catch_mesh_bounds.position.y - 0.01
		),
		"node_04 catch hit box starts above the visible catch base instead of inside the deck"
	)
	var highlighted_meshes_v: Variant = (
		node_04_target.get("_highlight_meshes") if node_04_target != null else []
	)
	check(
		(
			catch_mesh != null
			and highlighted_meshes_v is Array
			and (highlighted_meshes_v as Array).has(catch_mesh)
		),
		"node_04 outline highlights the visible food-spillway catch"
	)

	check(
		_trigger_control(chunk, "_hydraulic_diverter_control"),
		"visual-guidance probe diverts Borrowed Current"
	)
	check(
		_is_mouse_pickable(diverter_target),
		"diverter remains operable while a captured-route payload travels"
	)
	check(
		not _is_mouse_pickable(catch_target),
		"spillway catch remains unavailable until the visible payload arrives"
	)
	check(
		(
			node_04_delegate is CollisionObject3D
			and not (node_04_delegate as CollisionObject3D).input_ray_pickable
		),
		"traveling delivery cannot be clicked into an early abstract catch"
	)
	check(
		(
			node_04_delegate is Area3D
			and (node_04_delegate as Area3D).body_entered.is_connected(
				Callable(chunk, "_on_hydraulic_catch_body_entered")
			)
		),
		"active spillway destination completes on character arrival when foreground deck wins the click"
	)
	_check_no_hydraulic_next_highlight(hydraulic_targets, "diverted-current catch transfer step")
	check(
		_label_text(chunk.get("_hydraulic_diverter_label")) == "SPILLWAY FED // LYSATE TRAVELING",
		"diverter exposes both sides of the finite-current tradeoff during delivery"
	)
	check(
		_relationship_label(chunk.get("_hydraulic_spillway_link"))
		== "BORROWED FLOW FEEDS SPILLWAY",
		"spillway relationship names the fed branch"
	)
	check(
		_relationship_label(chunk.get("_hydraulic_exit_link"))
		== "DIVERSION STARVES THE SHELTER",
		"shelter relationship names the diversion cost"
	)

	await _advance_hydraulic_sequence(chunk, 2.7)
	check(_is_mouse_pickable(catch_target), "arrived lysate enables the physical catch")
	check(
		not _trigger_generated_node(chunk, "node_04"),
		"inventory-less probe cannot convert arrived lysate into an abstract success"
	)
	check(
		_is_mouse_pickable(catch_target),
		"failed physical transfer leaves the same arrived payload available"
	)
	check(
		(
			node_04_delegate is CollisionObject3D
			and (node_04_delegate as CollisionObject3D).input_ray_pickable
		),
		"arrived catch retains its receiver pointer surface until physical pickup"
	)
	check(
		_is_mouse_pickable(diverter_target),
		"Borrowed Current becomes mouse-pickable again for flow restoration"
	)
	_check_no_hydraulic_next_highlight(hydraulic_targets, "restore-current inference step")
	check(
		_label_text(chunk.get("_hydraulic_diverter_label")) == "SPILLWAY FED // MAIN STARVED",
		"arrived delivery preserves the unresolved finite-current allocation"
	)
	check(
		_relationship_label(chunk.get("_hydraulic_exit_link"))
		== "DIVERSION STARVES THE SHELTER",
		"post-arrival relationship still communicates the diversion cost"
	)

	check(
		_trigger_control(chunk, "_hydraulic_diverter_control"),
		"visual-guidance probe restores the main current"
	)
	_check_only_hydraulic_next_highlight(hydraulic_targets, exit_target, "exit-ready shelter step")
	check(
		_label_text(chunk.get("_hydraulic_diverter_label")) == "MAIN FED // SPILLWAY DRY",
		"restored diverter exposes the final finite-current allocation"
	)
	check(
		_relationship_label(chunk.get("_hydraulic_exit_link"))
		== "MAIN CURRENT FEEDS THE SHELTER",
		"restored relationship confirms the shelter feed"
	)
	check(
		exit_delegate != null and str(exit_delegate.get("tutorial_label")) == "ENTER SHELTER",
		"restored exit beacon becomes the explicit ENTER SHELTER action"
	)
	check(
		_label_text(chunk.get("_hydraulic_exit_label")) == "SHELTER ROUTE // OPEN",
		"restored exit beacon label confirms the route is open"
	)


func verify_physical_spillway_food() -> void:
	print("\n--- Canonical spillway food transaction ---")
	var host := FoodHost.new()
	host.setup()
	root.add_child(host)
	var chunk := CHUNK_SCENE.instantiate()
	(
		chunk
		. configure_chunk(
			{
				"spec_path": SPEC_PATH,
				"game_mode": "neutral",
				"food_test": "neutral",
			}
		)
	)
	host.register_party(chunk.get_spawn_positions())
	chunk.attach_chunk_host(host, "generated_stretch")
	host.add_child(chunk)
	for _frame in range(4):
		await process_frame
	host.grid = GridWorld.from_data(chunk.call("get_grid_data"))
	host.game_state.grid = host.grid
	chunk.reset_preview_state()
	await process_frame

	var initial := _state(chunk)
	check(
		bool(initial.get("hydraulic_spillway_food_enabled", false)),
		"Neutral mode authors the spillway reward as tangible lysate"
	)
	check(
		not bool(initial.get("hydraulic_spillway_food_available", true))
		and str(initial.get("spillway_delivery_phase", "")) == DELIVERY_IDLE,
		"the tangible spillway reward starts upstream and dormant"
	)
	var cache: Dictionary = chunk.get("_hydraulic_spillway_food_cache")
	var marker: MeshInstance3D = cache.get("marker", null)
	var interactable: Node = cache.get("interactable", null)
	check(
		marker != null and is_instance_valid(marker) and not marker.visible,
		"the persistent spillway lysate is not pre-placed at its destination"
	)
	check(
		interactable != null and not bool(interactable.get("interaction_enabled")),
		"the catch cannot be serviced before a payload physically arrives"
	)
	check(
		interactable != null and str(interactable.get("tutorial_label")) == "CATCH EMPTY",
		"The dormant tangible-food action truthfully names an empty catch"
	)

	check(_trigger_control(chunk, "_hydraulic_first_control"), "food test opens First Sluice")
	chunk.call("_force_bridge_cargo_staged_for_headless")
	check(
		_trigger_control(chunk, "_hydraulic_cistern_control"),
		"food test releases current onto staged cargo"
	)
	await _advance_hydraulic_sequence(chunk, 3.001)
	check(
		bool(_state(chunk).get("cistern_bridge_installed", false)),
		"food test seats the carried bridge before using the downstream diverter"
	)
	check(
		_trigger_control(chunk, "_hydraulic_diverter_control"),
		"food test diverts Borrowed Current"
	)
	check(
		str(_state(chunk).get("spillway_delivery_phase", "")) == DELIVERY_TRAVELING
		and marker.visible
		and not bool(interactable.get("interaction_enabled")),
		"diversion launches the visible payload without enabling an early pickup"
	)
	await _advance_hydraulic_sequence(chunk, 2.7)
	check(
		str(_state(chunk).get("spillway_delivery_phase", "")) == DELIVERY_AVAILABLE
		and bool(_state(chunk).get("borrowed_current_delivery_latched", false))
		and marker.visible
		and bool(interactable.get("interaction_enabled")),
		"scheduler arrival retains one physical lysate in the catch"
	)
	var catch_position_v: Variant = chunk.call(
		"_generated_interaction_data_position", interactable
	)
	var catch_position := (
		catch_position_v as Vector3
		if catch_position_v is Vector3
		else Vector3.INF
	)
	check(
		catch_position != Vector3.INF,
		"spillway pickup fixture uses the catch's authoritative data-space position"
	)
	host.set_preview_character_position("aster", catch_position)
	if interactable != null and "active_character" in interactable:
		interactable.set("active_character", "aster")

	var filler_ids: Array[String] = []
	for index in range(2):
		var filler_id: String = host.game_state.spawn_item(
			"test_filler", catch_position, {"hand_slots": 1, "display_name": "Filler %d" % index}
		)
		if host.game_state.pick_up_item("aster", filler_id):
			filler_ids.append(filler_id)
	check(filler_ids.size() == 2, "test setup fills both of Aster's hands")
	var item_count_before_failure: int = host.game_state.items.size()
	check(
		not _trigger_generated_node(chunk, "node_04"),
		"full hands block only the optional physical pickup"
	)
	var failed_pickup := _state(chunk)
	check(
		bool(failed_pickup.get("borrowed_current_delivery_latched", false))
		and str(failed_pickup.get("spillway_delivery_phase", "")) == DELIVERY_AVAILABLE,
		"the arrived payload remains authoritative when food cannot be carried"
	)
	check(
		not bool(failed_pickup.get("hydraulic_spillway_food_collected", true)),
		"a failed pickup does not consume the tangible food latch"
	)
	check(
		int(failed_pickup.get("physical_food_spawned_count", -1)) == 0,
		"a failed pickup does not increment the physical-food counter"
	)
	check(
		host.game_state.items.size() == item_count_before_failure,
		"a failed pickup removes its temporary ground item instead of leaking it"
	)
	check(
		marker.visible and bool(interactable.get("interaction_enabled")),
		"a failed pickup leaves the marker and interaction available for retry"
	)
	check(
		_trigger_control(chunk, "_hydraulic_diverter_control"),
		"full hands cannot prevent restoring the independent main current"
	)

	host.game_state.remove_item(filler_ids[0])
	check(
		_trigger_generated_node(chunk, "node_04"),
		"freeing one hand allows a later spillway-food retry"
	)
	var collected := _state(chunk)
	check(
		bool(collected.get("hydraulic_spillway_food_collected", false)),
		"the successful retry latches tangible spillway food"
	)
	check(
		int(collected.get("physical_food_spawned_count", 0)) == 1,
		"the successful retry creates exactly one carried lysate"
	)
	check(
		not marker.visible and not bool(interactable.get("interaction_enabled")),
		"the successful retry clears its marker and disables duplicate interaction"
	)
	var hands_after_success: Array = host.game_state.get_hand_items("aster")
	var spillway_item_id := ""
	for item_id_v in hands_after_success:
		var item_id := str(item_id_v)
		if not filler_ids.has(item_id):
			spillway_item_id = item_id
			break
	check(spillway_item_id != "", "the successful reward occupies Aster's free hand")
	check(
		not _trigger_generated_node(chunk, "node_04"),
		"spent catch Interactable rejects a duplicate physical pickup"
	)
	check(
		int(_state(chunk).get("physical_food_spawned_count", 0)) == 1,
		"direct duplicate activation cannot spawn a second spillway reward"
	)

	chunk.reset_preview_state()
	var reset := _state(chunk)
	check(
		spillway_item_id == "" or not host.game_state.items.has(spillway_item_id),
		"preview reset removes the prior spillway item from hands and world state"
	)
	check(
		not bool(reset.get("hydraulic_spillway_food_available", true))
		and str(reset.get("spillway_delivery_phase", "")) == DELIVERY_IDLE
		and not marker.visible,
		"preview reset returns the same payload upstream instead of pre-filling the catch"
	)
	var reset_node_targets_v: Variant = chunk.get("_node_targets")
	var reset_node_targets: Dictionary = (
		reset_node_targets_v as Dictionary if reset_node_targets_v is Dictionary else {}
	)
	var reset_catch_target_v: Variant = reset_node_targets.get("node_04", null)
	var reset_catch_target: Node = (
		reset_catch_target_v as Node if reset_catch_target_v is Node else null
	)
	check(
		interactable != null and not bool(interactable.get("input_ray_pickable")),
		"Reset keeps node_04's retry Area from intercepting mouse picks"
	)
	check(
		not _is_mouse_pickable(reset_catch_target),
		"Reset keeps the inactive catch target non-pickable until current is diverted"
	)

	host.queue_free()
	await process_frame
	await process_frame


func _linked_outline_target(control: Node) -> Node:
	if control == null or not is_instance_valid(control):
		return null
	var target_v: Variant = control.get("_outline_target")
	return target_v as Node if target_v is Node and is_instance_valid(target_v) else null


func _check_generated_node_outline_ownership(chunk: Node, node_targets: Dictionary) -> void:
	var checked := 0
	for node_id_v in node_targets.keys():
		var node_id := str(node_id_v)
		var explicit_target_v: Variant = node_targets.get(node_id, null)
		var explicit_target: Node = (
			explicit_target_v as Node
			if explicit_target_v is Node and is_instance_valid(explicit_target_v)
			else null
		)
		var delegate: Node = null
		if explicit_target != null and explicit_target.has_method("get_interaction_delegate"):
			var delegate_v: Variant = explicit_target.call("get_interaction_delegate")
			if delegate_v is Node and is_instance_valid(delegate_v):
				delegate = delegate_v as Node
		check(
			delegate != null and str(delegate.name) == "GeneratedNode_%s" % node_id,
			"%s explicit target delegates to its generated-node interactable" % node_id
		)
		check(
			delegate != null and _linked_outline_target(delegate) == explicit_target,
			"%s generated-node interactable links exactly to its explicit target" % node_id
		)
		check(
			delegate is Area3D and not bool(delegate.get("input_ray_pickable")),
			"%s generated-node Area cannot intercept mouse picks" % node_id
		)
		if node_id == "entry":
			check(
				not _is_mouse_pickable(explicit_target),
				"entry outline stays non-pickable so its helix projection cannot cover the catch"
			)
		elif node_id == "node_04":
			check(
				not _is_mouse_pickable(explicit_target),
				"node_04 catch target stays non-pickable until its hydraulic step becomes active"
			)
		else:
			check(
				_is_mouse_pickable(explicit_target),
				(
					"%s explicit outline target remains the generated node's mouse-pick surface"
					% node_id
				)
			)
		var fallback_name := "GeneratedNode_%sOutline" % node_id
		var fallback := chunk.get_node_or_null(NodePath(fallback_name))
		check(
			fallback == null,
			"%s has no stale automatic sibling outline target to intercept the ray" % node_id
		)
		checked += 1
	check(
		checked == 3
		and node_targets.has("node_02")
		and node_targets.has("node_04")
		and node_targets.has("exit_shelter"),
		"outline ownership covers only the three implemented generated handlers"
	)


func _valid_live_mesh_count(raw: Variant) -> int:
	if not (raw is Array):
		return 0
	var count := 0
	for mesh_v in raw as Array:
		if (
			mesh_v is MeshInstance3D
			and is_instance_valid(mesh_v)
			and (mesh_v as MeshInstance3D).mesh != null
			and (mesh_v as MeshInstance3D).visible
		):
			count += 1
	return count


func _combined_live_mesh_bounds(raw: Variant) -> AABB:
	if not (raw is Array):
		return AABB()
	var bounds := AABB()
	var started := false
	for mesh_v in raw as Array:
		if not (mesh_v is MeshInstance3D) or not is_instance_valid(mesh_v):
			continue
		var mesh := mesh_v as MeshInstance3D
		if mesh.mesh == null or not mesh.visible:
			continue
		var world_bounds := mesh.global_transform * mesh.mesh.get_aabb()
		if started:
			bounds = bounds.merge(world_bounds)
		else:
			bounds = world_bounds
			started = true
	return bounds


func _check_only_hydraulic_next_highlight(
	targets: Array[Node], expected: Node, phase_label: String
) -> void:
	var reason_targets: Array[Node] = []
	var active_outline_targets: Array[Node] = []
	for target in targets:
		if target == null or not is_instance_valid(target):
			continue
		var reasons_v: Variant = target.get("_external_highlight_reasons")
		if (
			reasons_v is Dictionary
			and bool((reasons_v as Dictionary).get("hydraulic_next_step", false))
		):
			reason_targets.append(target)
		if (
			target.has_method("has_active_mesh_outline")
			and bool(target.call("has_active_mesh_outline"))
		):
			active_outline_targets.append(target)
	check(
		reason_targets.size() == 1 and reason_targets[0] == expected,
		"%s gives hydraulic_next_step only to the current target" % phase_label
	)
	check(
		active_outline_targets.size() == 1 and active_outline_targets[0] == expected,
		"%s visibly outlines only the current hydraulic target" % phase_label
	)


func _check_no_hydraulic_next_highlight(targets: Array[Node], phase_label: String) -> void:
	var reason_targets: Array[Node] = []
	for target in targets:
		if target == null or not is_instance_valid(target):
			continue
		var reasons_v: Variant = target.get("_external_highlight_reasons")
		if (
			reasons_v is Dictionary
			and bool((reasons_v as Dictionary).get("hydraulic_next_step", false))
		):
			reason_targets.append(target)
	check(
		reason_targets.is_empty(),
		"%s omits the persistent hydraulic answer highlight" % phase_label
	)


func _relationship_label(raw: Variant) -> String:
	if raw is Node and is_instance_valid(raw) and raw.has_method("get_relationship_label"):
		return str(raw.call("get_relationship_label"))
	return ""


func _box_collision_size(target: Node) -> Vector3:
	if target == null or not is_instance_valid(target):
		return Vector3.ZERO
	for child in target.get_children():
		if child is CollisionShape3D:
			var shape := (child as CollisionShape3D).shape
			if shape is BoxShape3D:
				return (shape as BoxShape3D).size
	return Vector3.ZERO


func _box_collision_world_bounds(target: Node) -> AABB:
	if target == null or not is_instance_valid(target):
		return AABB()
	for child in target.get_children():
		if child is CollisionShape3D:
			var collision := child as CollisionShape3D
			if collision.shape is BoxShape3D:
				var size := (collision.shape as BoxShape3D).size
				return collision.global_transform * AABB(-size * 0.5, size)
	return AABB()


func _box_contains_world_point(target: Node, world_point: Vector3) -> bool:
	if not (target is Node3D) or not is_instance_valid(target):
		return false
	var size := _box_collision_size(target)
	if size == Vector3.ZERO:
		return false
	var local_point := (target as Node3D).to_local(world_point)
	var half_size := size * 0.5
	return (
		absf(local_point.x) <= half_size.x
		and absf(local_point.y) <= half_size.y
		and absf(local_point.z) <= half_size.z
	)


func _is_mouse_pickable(target: Node) -> bool:
	return (
		target is CollisionObject3D
		and is_instance_valid(target)
		and bool(target.get("input_ray_pickable"))
		and int(target.get("collision_layer")) != 0
	)


func _resolved_target_position(target: Node) -> Vector3:
	if target == null or not is_instance_valid(target):
		return Vector3.INF
	if target.has_method("get_interaction_target_position"):
		var position_v: Variant = target.call(
			"get_interaction_target_position", Vector3(3.0, 2.0, -4.0), Vector3.INF
		)
		if position_v is Vector3:
			return position_v
	return Vector3.INF


func _check_delegate_target_resolution(target: Node, label: String) -> void:
	check(
		(
			target != null
			and is_instance_valid(target)
			and target.has_method("get_interaction_delegate")
			and target.has_method("get_interaction_target_position")
		),
		"%s exposes the outline delegate-position contract" % label
	)
	if (
		target == null
		or not is_instance_valid(target)
		or not target.has_method("get_interaction_delegate")
		or not target.has_method("get_interaction_target_position")
	):
		return
	var delegate_v: Variant = target.call("get_interaction_delegate")
	check(
		delegate_v is Node and is_instance_valid(delegate_v),
		"%s delegates to a live interactable" % label
	)
	if not (delegate_v is Node) or not is_instance_valid(delegate_v):
		return
	var delegate := delegate_v as Node
	var expected := Vector3.INF
	if delegate.has_method("get_interaction_target_position"):
		var expected_v: Variant = delegate.call(
			"get_interaction_target_position", Vector3(3.0, 2.0, -4.0), Vector3.INF
		)
		if expected_v is Vector3:
			expected = expected_v
	elif delegate is Node3D:
		expected = (delegate as Node3D).global_position
	var resolved := _resolved_target_position(target)
	check(
		(
			expected != Vector3.INF
			and resolved != Vector3.INF
			and resolved.distance_to(expected) <= 0.01
		),
		"%s resolves through its warped delegate instead of stale flat metadata" % label
	)


func _state(chunk: Node) -> Dictionary:
	var state_v: Variant = chunk.call("get_preview_state")
	return state_v as Dictionary if state_v is Dictionary else {}


func _chunk_game_state(chunk: Node) -> GameState:
	var host_v: Variant = chunk.get("host")
	var game_state_v: Variant = host_v.get("game_state") if host_v is Node else null
	return game_state_v as GameState if game_state_v is GameState else null


func _trigger_control(chunk: Node, field_name: String, actor := "aster") -> bool:
	var source_v: Variant = chunk.get(field_name)
	return (
		_trigger_exact_interactable(chunk, source_v as Node, actor)
		if source_v is Node
		else false
	)


func _trigger_generated_node(chunk: Node, node_id: String, actor := "aster") -> bool:
	var sources_v: Variant = chunk.get("_node_interactables")
	if not (sources_v is Dictionary):
		return false
	var source_v: Variant = (sources_v as Dictionary).get(node_id, null)
	return (
		_trigger_exact_interactable(chunk, source_v as Node, actor)
		if source_v is Node
		else false
	)


func _trigger_exact_interactable(chunk: Node, source: Node, actor: String) -> bool:
	var game_state := _chunk_game_state(chunk)
	if source == null or not is_instance_valid(source) \
			or game_state == null or not game_state.characters.has(actor):
		return false
	var position_v: Variant = chunk.call(
		"_generated_interaction_data_position", source
	)
	if not (position_v is Vector3):
		return false
	game_state.snap_character_to(actor, position_v as Vector3)
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))


func _mesh_visibility(raw: Variant, expected: bool) -> bool:
	if not (raw is Array) or (raw as Array).is_empty():
		return false
	for mesh_v in raw as Array:
		if not (mesh_v is VisualInstance3D) or not is_instance_valid(mesh_v):
			return false
		if bool((mesh_v as VisualInstance3D).visible) != expected:
			return false
	return true


func _mesh_any_visible(raw: Variant) -> bool:
	if not (raw is Array) or (raw as Array).is_empty():
		return false
	for mesh_v in raw as Array:
		if mesh_v is VisualInstance3D and is_instance_valid(mesh_v) \
				and bool((mesh_v as VisualInstance3D).visible):
			return true
	return false


func _mesh_partial_visible(raw: Variant) -> bool:
	return _mesh_any_visible(raw) and not _mesh_visibility(raw, true)


func _bridge_blockers_match(chunk: Node, expected_blocked: bool) -> bool:
	var host_v: Variant = chunk.get("host")
	var game_state_v: Variant = host_v.get("game_state") if host_v is Node else null
	if not (game_state_v is GameState) or (game_state_v as GameState).grid == null:
		return false
	var cells: Array = chunk.call("_hydraulic_bridge_blocker_cells")
	if cells.is_empty():
		return false
	var blockers: Dictionary = (game_state_v as GameState).grid.dynamic_blockers
	for cell_v in cells:
		var cell := cell_v as Vector2i
		if blockers.has(cell) != expected_blocked:
			return false
	return true


func _bridge_route_exists(chunk: Node) -> bool:
	var host_v: Variant = chunk.get("host")
	var game_state_v: Variant = host_v.get("game_state") if host_v is Node else null
	if not (game_state_v is GameState) or (game_state_v as GameState).grid == null:
		return false
	var from_v: Variant = chunk.call("_node_position", "node_02")
	var to_v: Variant = chunk.call("_node_position", "node_03")
	if not (from_v is Vector3) or not (to_v is Vector3):
		return false
	var grid = (game_state_v as GameState).grid
	var from_cell: Vector2i = grid.world_to_grid(from_v as Vector3)
	var to_cell: Vector2i = grid.world_to_grid(to_v as Vector3)
	return not grid.find_path(from_cell, to_cell).is_empty()


func _chunk_scheduler(chunk: Node) -> Variant:
	var host_v: Variant = chunk.get("host")
	return host_v.get("scheduler") if host_v is Node else null


func _milestone_events(milestones: Array) -> Array[String]:
	var events: Array[String] = []
	for milestone_v in milestones:
		if milestone_v is Dictionary:
			events.append(str((milestone_v as Dictionary).get("event", "")))
	return events


func _milestone_sequence_ticks(milestones: Array) -> Array[float]:
	var ticks: Array[float] = []
	for milestone_v in milestones:
		if milestone_v is Dictionary:
			ticks.append(float((milestone_v as Dictionary).get("sequence_tick", -1.0)))
	return ticks


func _scavenger_milestone_ticks_match_physical_route(chunk: Node, milestones: Array) -> bool:
	if milestones.size() < 4:
		return false
	var route_v: Variant = chunk.get("_bridge_scavenger_route")
	var scavenger_v: Variant = chunk.get("_hydraulic_scavenger")
	if not (route_v is Array) or (route_v as Array).size() < 4 \
			or not (scavenger_v is Enemy):
		return false
	var route := route_v as Array
	var speed := float((scavenger_v as Enemy).move_speed)
	if speed <= 0.0:
		return false
	var approach_duration := (route[0] as Vector3).distance_to(route[1] as Vector3) / speed
	var retreat_duration := (
		(route[1] as Vector3).distance_to(route[2] as Vector3)
		+ (route[2] as Vector3).distance_to(route[3] as Vector3)
	) / speed
	var fall_duration := float(chunk.get("_bridge_cargo_fall_end_tick")) \
		- float(chunk.get("_bridge_cargo_fall_start_tick"))
	var expected := [
		0.0,
		snappedf(approach_duration, 0.001),
		snappedf(approach_duration + fall_duration, 0.001),
		snappedf(approach_duration + retreat_duration, 0.001),
	]
	var actual := _milestone_sequence_ticks(milestones).slice(0, 4)
	if actual.size() != expected.size():
		print("  SCAVENGER TICK DIAGNOSTIC actual=%s expected=%s" % [actual, expected])
		return false
	for index in range(expected.size()):
		if absf(float(actual[index]) - float(expected[index])) > 0.002:
			print("  SCAVENGER TICK DIAGNOSTIC actual=%s expected=%s" % [actual, expected])
			return false
	return true


func _advance_hydraulic_sequence(chunk: Node, seconds: float) -> void:
	var host_v: Variant = chunk.get("host")
	var scheduler_v: Variant = host_v.get("scheduler") if host_v is Node else null
	if scheduler_v != null:
		scheduler_v.advance_ticks(seconds)
	chunk.call("_update_hydraulic_cargo_sequence", seconds)
	chunk.call("_update_hydraulic_flow_visuals")
	chunk.call("_update_spillway_delivery_visual")
	await process_frame


func _light_energy(raw: Variant) -> float:
	return (
		(raw as Light3D).light_energy
		if raw is Light3D and is_instance_valid(raw)
		else -1.0
	)


func _label_text(raw: Variant) -> String:
	return str((raw as Label3D).text) if raw is Label3D and is_instance_valid(raw) else ""


func _has_external_highlight(target: Variant) -> bool:
	if not (target is Node) or not is_instance_valid(target):
		return false
	var reasons: Variant = (target as Node).get("_external_highlight_reasons")
	return (
		reasons is Dictionary
		and (reasons as Dictionary).has("hydraulic_next_step")
	)


func _valid_node_count(raw: Variant) -> int:
	if not (raw is Array):
		return 0
	var count := 0
	for node_v in raw as Array:
		if is_instance_valid(node_v) and node_v is Node:
			count += 1
	return count


func _distinct_valid_nodes(raw: Array) -> bool:
	return (
		raw.size() == 2
		and raw[0] is Node
		and raw[1] is Node
		and is_instance_valid(raw[0])
		and is_instance_valid(raw[1])
		and raw[0] != raw[1]
	)


func _check_reset_state(state: Dictionary, source: String) -> void:
	check(
		bool(state.get("hydraulic_enabled", false)),
		"%s enables hydraulics for the teaching spec" % source
	)
	check(
		str(state.get("hydraulic_phase", "")) == PHASE_FIRST_SLUICE,
		"%s starts at First Sluice" % source
	)
	check(
		str(state.get("bridge_cargo_phase", "")) == CARGO_ELEVATED,
		"%s restores the same bridge cargo to its elevated breakaway rack" % source
	)
	var milestones: Array = state.get("bridge_cargo_milestones", [])
	check(
		milestones.size() == 1
		and str((milestones[0] as Dictionary).get("event", ""))
		== "cargo_elevated_on_breakaway_rack",
		"%s restarts the deterministic cargo milestone trace" % source
	)
	check(not bool(state.get("first_sluice_open", true)), "%s closes First Sluice" % source)
	check(
		not bool(state.get("cistern_bridge_installed", true)),
		"%s removes the installed bridge" % source
	)
	check(
		not bool(state.get("borrowed_current_diverted", true)), "%s clears the diversion" % source
	)
	check(
		not bool(state.get("borrowed_current_delivery_latched", true)),
		"%s clears the optional delivery latch" % source
	)
	check(
		not bool(state.get("main_current_restored", true)),
		"%s clears the post-diversion restoration latch" % source
	)
	check(
		not bool(state.get("hydraulic_exit_unlocked", true)),
		"%s relocks the hydraulic exit gate" % source
	)
	check(not bool(state.get("shelter_reached", true)), "%s clears shelter completion" % source)
