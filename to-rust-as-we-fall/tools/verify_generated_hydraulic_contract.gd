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

const REQUIRED_METHODS := [
	"get_preview_state",
	"reset_preview_state",
	"open_first_sluice",
	"release_cistern_bridge",
	"toggle_borrowed_current",
	"activate_generated_node",
]

const REQUIRED_STATE_KEYS := [
	"hydraulic_enabled",
	"hydraulic_phase",
	"first_sluice_open",
	"cistern_bridge_installed",
	"borrowed_current_diverted",
	"borrowed_current_delivery_latched",
	"main_current_restored",
	"hydraulic_exit_unlocked",
]


class FoodHost:
	extends ChunkHostStub

	var active_character := "aster"

	func get_preview_active_character() -> String:
		return active_character

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


class HydraulicHost:
	extends ChunkHostStub

	var focus_requests: Array[Dictionary] = []

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

	verify_browser_interaction_contract(chunk)
	chunk.call("reset_preview_state")
	await process_frame
	initial = _state(chunk)

	print("\n--- Initial state and wrong-order guards ---")
	_check_reset_state(initial, "initial build")
	check(_mesh_visibility(chunk.get("_hydraulic_main_water"), false), "main water starts dry")
	check(_mesh_visibility(chunk.get("_hydraulic_spillway_water"), false), "spillway starts dry")
	check(_mesh_visibility(chunk.get("_hydraulic_exit_water"), false), "exit channel starts dry")
	check(
		_label_text(chunk.get("_hydraulic_first_label")) == "FIRST SLUICE",
		"First Sluice has a persistent world-state label"
	)
	check(
		_valid_node_count(chunk.get("_causal_feedback_links")) == 4,
		"initial build registers exactly four readable cause/effect links"
	)
	check(
		not bool(chunk.call("release_cistern_bridge")),
		"cistern cannot release before First Sluice opens"
	)
	check(
		not bool(chunk.call("toggle_borrowed_current")),
		"Borrowed Current cannot divert before the bridge is installed"
	)
	check(
		not bool(chunk.call("activate_generated_node", "exit_shelter")),
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

	print("\n--- First Sluice -> Cistern Bridge ---")
	check(bool(chunk.call("open_first_sluice")), "First Sluice opens once")
	var sluice := _state(chunk)
	check(bool(sluice.get("first_sluice_open", false)), "First Sluice state latches open")
	check(
		str(sluice.get("hydraulic_phase", "")) == PHASE_CISTERN_BRIDGE,
		"opening the sluice advances to the Cistern Bridge beat"
	)
	check(
		_mesh_visibility(chunk.get("_hydraulic_main_water"), true),
		"opening the sluice makes the main water visible"
	)
	check(
		_label_text(chunk.get("_hydraulic_first_label")) == "FLOW OPEN",
		"completed First Sluice remains legible after its interaction disables"
	)
	check(not bool(chunk.call("open_first_sluice")), "repeating First Sluice is idempotent")

	check(
		bool(chunk.call("release_cistern_bridge")), "cistern release installs the mandatory bridge"
	)
	var bridge := _state(chunk)
	check(
		bool(bridge.get("cistern_bridge_installed", false)),
		"Cistern Bridge state latches installed"
	)
	check(
		str(bridge.get("hydraulic_phase", "")) == PHASE_BORROWED_CURRENT,
		"bridge installation advances to Borrowed Current"
	)
	check(
		_label_text(chunk.get("_hydraulic_cistern_label")) == "BRIDGE INSTALLED",
		"completed Cistern Release remains legible after its interaction disables"
	)
	check(
		not bool(chunk.call("release_cistern_bridge")),
		"releasing the cistern twice cannot duplicate the bridge"
	)

	print("\n--- Borrowed Current delivery and restoration ---")
	check(
		bool(chunk.call("toggle_borrowed_current")),
		"first valid diverter use borrows the main current"
	)
	var diverted := _state(chunk)
	check(
		(
			bool(diverted.get("borrowed_current_diverted", false))
			and not bool(diverted.get("main_current_restored", false))
		),
		"diversion is visible and main current is not yet restored"
	)
	check(
		str(diverted.get("hydraulic_phase", "")) == PHASE_FOOD_SPILLWAY,
		"diversion advances to the food spillway beat"
	)
	var diverted_focus_host: Node = chunk.get("host")
	var spillway_focus: Dictionary = (
		diverted_focus_host.call("last_focus_request")
		if diverted_focus_host != null and diverted_focus_host.has_method("last_focus_request")
		else {}
	)
	check(
		(
			not spillway_focus.is_empty()
			and spillway_focus.get("target", null) == chunk.get("_hydraulic_spillway_catch")
			and not bool(spillway_focus.get("pause_gameplay", true))
			and float(spillway_focus.get("duration", 0.0)) >= 3.5
		),
		"spillway reveal keeps input live long enough to command the visible catch"
	)
	check(
		_mesh_visibility(chunk.get("_hydraulic_spillway_water"), true),
		"diversion visibly fills the spillway"
	)
	check(
		_mesh_visibility(chunk.get("_hydraulic_main_tail"), false),
		"diversion visibly drains the competing main tail"
	)
	check(
		_distinct_valid_nodes(
			[chunk.get("_hydraulic_spillway_link"), chunk.get("_hydraulic_exit_link")]
		),
		"diverter consequences have distinct feedback links"
	)

	var foraged_before := int(_state(chunk).get("atp_foraged", 0))
	check(
		bool(chunk.call("activate_generated_node", "node_04")),
		"reaching node_04 latches the diverted delivery"
	)
	var delivered := _state(chunk)
	check(
		bool(delivered.get("borrowed_current_delivery_latched", false)),
		"Borrowed Current delivery remains latched"
	)
	check(
		bool(delivered.get("borrowed_current_diverted", false)),
		"delivery does not silently restore the current"
	)
	check(
		str(delivered.get("hydraulic_phase", "")) == PHASE_RESTORE_CURRENT,
		"delivery explicitly asks the player to restore the current"
	)
	var return_focus_host: Node = chunk.get("host")
	var return_focus: Dictionary = (
		return_focus_host.call("last_focus_request")
		if return_focus_host != null and return_focus_host.has_method("last_focus_request")
		else {}
	)
	check(
		(
			not return_focus.is_empty()
			and return_focus.get("target", null) == chunk.get("_hydraulic_exit_beacon")
			and not bool(return_focus.get("pause_gameplay", true))
			and float(return_focus.get("duration", 0.0)) >= 3.5
		),
		"post-catch reveal keeps input live while showing the still-starved shelter"
	)
	check(
		_label_text(chunk.get("_hydraulic_diverter_label"))
		== "SPILLWAY CAUGHT // MAIN STARVED",
		"the persistent allocation state supports inferring the return trip"
	)
	check(
		bool(chunk.call("activate_generated_node", "node_04")),
		"revisiting a completed forage node remains harmless"
	)
	check(
		int(_state(chunk).get("atp_foraged", 0)) == foraged_before + 2,
		"revisiting node_04 cannot grind the forage reward"
	)
	check(
		not bool(chunk.call("activate_generated_node", "exit_shelter")),
		"exit stays gated while the current remains diverted"
	)

	check(
		bool(chunk.call("toggle_borrowed_current")), "second diverter use restores the main current"
	)
	var ready := _state(chunk)
	check(
		(
			not bool(ready.get("borrowed_current_diverted", true))
			and bool(ready.get("main_current_restored", false))
		),
		"restoration visibly returns flow to the main route"
	)
	check(
		bool(ready.get("hydraulic_exit_unlocked", false)),
		"bridge, delivery, and restored flow unlock the exit"
	)
	check(
		str(ready.get("hydraulic_phase", "")) == PHASE_EXIT_READY,
		"completed hydraulic solve reaches exit_ready"
	)
	check(
		_mesh_visibility(chunk.get("_hydraulic_exit_water"), true),
		"restoration visibly carries water from node_04 to the exit"
	)
	check(
		_mesh_visibility(chunk.get("_hydraulic_spillway_water"), false),
		"restoration visibly drains the borrowed spillway"
	)
	check(
		_label_text(chunk.get("_hydraulic_diverter_label")) == "MAIN FED // SPILLWAY DRY",
		"completed finite-current allocation remains legible after interaction disables"
	)
	var focus_host: Node = chunk.get("host")
	var final_focus: Dictionary = (
		focus_host.call("last_focus_request")
		if focus_host != null and focus_host.has_method("last_focus_request")
		else {}
	)
	check(
		(
			not final_focus.is_empty()
			and final_focus.get("target", null) == chunk.get("_hydraulic_exit_beacon")
			and not bool(final_focus.get("pause_gameplay", true))
			and float(final_focus.get("duration", 0.0)) >= 3.5
		),
		"shelter reveal keeps movement live long enough to accept an eager exit command"
	)
	check(
		bool(chunk.call("activate_generated_node", "exit_shelter")),
		"shelter exit succeeds after the complete solve"
	)
	check(
		bool(_state(chunk).get("shelter_reached", false)),
		"successful exit records shelter completion"
	)

	print("\n--- Reset ---")
	chunk.call("reset_preview_state")
	_check_reset_state(_state(chunk), "preview reset")

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
		_valid_node_count(chunk.get("_causal_feedback_links")) == 4,
		"in-place rebuild replaces rather than accumulates causal-link references"
	)


func verify_browser_interaction_contract(chunk: Node) -> void:
	print("\n--- Browser interaction targets ---")
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
		_check_delegate_target_resolution(node_target, "%s generated-node target" % node_id)
		_check_delegate_target_resolution(control_target, "%s outline target" % label)
	for node_id in ["entry", "exit_shelter"]:
		var boundary_target: Node = node_targets.get(node_id, null)
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
	var diverter_node_size := _box_collision_size(diverter_node_target)
	var diverter_control_size := _box_collision_size(diverter_target)
	var diverter_horizontal_clearance := 0.0
	if diverter_node_target is Node3D and diverter_target is Node3D:
		var node_center := (diverter_node_target as Node3D).global_position
		var control_center := (diverter_target as Node3D).global_position
		diverter_horizontal_clearance = Vector2(node_center.x, node_center.z).distance_to(
			Vector2(control_center.x, control_center.z)
		)
	var required_diverter_clearance := (
		maxf(diverter_node_size.x, diverter_node_size.z) * 0.5
		+ maxf(diverter_control_size.x, diverter_control_size.z) * 0.5
		+ 0.3
	)
	check(
		(
			diverter_node_size != Vector3.ZERO
			and diverter_control_size != Vector3.ZERO
			and diverter_horizontal_clearance >= required_diverter_clearance
		),
		"Borrowed Current target stays clear of node_03's nearer mouse-pick volume"
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
		_label_text(chunk.get("_hydraulic_exit_label")) == "RESTORE MAIN CURRENT",
		"exit beacon label initially communicates the hydraulic prerequisite"
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
		_label_text(chunk.get("_hydraulic_cistern_label")) == "CISTERN LOCKED",
		"initial Cistern status explicitly communicates its locked state"
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

	check(bool(chunk.call("open_first_sluice")), "interaction-target probe opens First Sluice")
	check(
		not _is_mouse_pickable(first_target),
		"completed First Sluice outline stops intercepting mouse picks"
	)
	check(
		_is_mouse_pickable(cistern_target),
		"Cistern Release outline becomes pickable after First Sluice"
	)
	check(
		not _is_mouse_pickable(diverter_target),
		"Borrowed Current outline stays locked until the bridge is installed"
	)
	_check_only_hydraulic_next_highlight(
		hydraulic_targets, cistern_target, "post-sluice Cistern Release step"
	)
	check(
		_label_text(chunk.get("_hydraulic_first_label")) == "FLOW OPEN",
		"First Sluice status transitions to FLOW OPEN after activation"
	)
	check(
		_label_text(chunk.get("_hydraulic_cistern_label")) == "CISTERN RELEASE",
		"Cistern status transitions from locked to its available action"
	)
	check(
		_label_text(chunk.get("_hydraulic_diverter_label")) == "CURRENT LOCKED",
		"diverter status remains locked until the bridge is installed"
	)

	check(
		bool(chunk.call("release_cistern_bridge")),
		"interaction-target probe installs the Cistern Bridge"
	)
	check(
		not _is_mouse_pickable(cistern_target),
		"completed Cistern Release outline stops intercepting mouse picks"
	)
	check(
		_is_mouse_pickable(diverter_target),
		"Borrowed Current outline becomes pickable after the bridge is installed"
	)
	_check_only_hydraulic_next_highlight(
		hydraulic_targets, diverter_target, "post-bridge Borrowed Current step"
	)
	check(
		_label_text(chunk.get("_hydraulic_cistern_label")) == "BRIDGE INSTALLED",
		"Cistern status transitions to BRIDGE INSTALLED after activation"
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
		node_04_delegate != null and str(node_04_delegate.get("tutorial_label")) == "CATCH CURRENT",
		"neutral node_04 delegate names the hydraulic action CATCH CURRENT"
	)
	var catch_description := (
		str(node_04_delegate.get("description")).to_lower() if node_04_delegate != null else ""
	)
	check(
		"catch" in catch_description and "borrowed current" in catch_description,
		"node_04 delegate truthfully describes catching the borrowed-current delivery"
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
		bool(chunk.call("toggle_borrowed_current")),
		"visual-guidance probe diverts Borrowed Current"
	)
	check(
		not _is_mouse_pickable(diverter_target),
		"diverted control yields pointer ownership to the spillway catch"
	)
	check(
		_is_mouse_pickable(catch_target),
		"spillway catch becomes mouse-pickable for its active delivery step"
	)
	check(
		(
			node_04_delegate is CollisionObject3D
			and (node_04_delegate as CollisionObject3D).input_ray_pickable
		),
		"active spillway step exposes its delegated receiver Area as an occlusion-safe pointer fallback"
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
		_label_text(chunk.get("_hydraulic_diverter_label")) == "SPILLWAY FED // MAIN STARVED",
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

	check(
		bool(chunk.call("activate_generated_node", "node_04")),
		"visual-guidance probe catches the borrowed current at node_04"
	)
	check(
		not _is_mouse_pickable(catch_target),
		"completed catch releases pointer ownership for the return step"
	)
	check(
		(
			node_04_delegate is CollisionObject3D
			and not (node_04_delegate as CollisionObject3D).input_ray_pickable
		),
		"completed catch disables its redundant receiver pointer surface"
	)
	check(
		_is_mouse_pickable(diverter_target),
		"Borrowed Current becomes mouse-pickable again for flow restoration"
	)
	_check_no_hydraulic_next_highlight(hydraulic_targets, "restore-current inference step")
	check(
		_label_text(chunk.get("_hydraulic_diverter_label")) == "SPILLWAY CAUGHT // MAIN STARVED",
		"caught delivery preserves the unresolved finite-current state"
	)
	check(
		_relationship_label(chunk.get("_hydraulic_exit_link"))
		== "RETURN FLOW TO FEED THE SHELTER",
		"post-catch relationship communicates the missing causal repair"
	)

	check(
		bool(chunk.call("toggle_borrowed_current")),
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
		_label_text(chunk.get("_hydraulic_exit_label")) == "SHELTER ROUTE OPEN",
		"restored exit beacon label confirms the route is open"
	)


func verify_physical_spillway_food() -> void:
	print("\n--- Expedition spillway food transaction ---")
	var host := FoodHost.new()
	host.setup()
	root.add_child(host)
	var chunk := CHUNK_SCENE.instantiate()
	(
		chunk
		. configure_chunk(
			{
				"spec_path": SPEC_PATH,
				"game_mode": "expedition",
				"food_test": "return_loop",
			}
		)
	)
	host.register_party(chunk.get_spawn_positions())
	chunk.attach_chunk_host(host, "generated_stretch")
	host.add_child(chunk)
	for _frame in range(4):
		await process_frame
	chunk.reset_preview_state()
	await process_frame

	var initial := _state(chunk)
	check(
		bool(initial.get("hydraulic_spillway_food_enabled", false)),
		"Expedition replaces the spillway's abstract refill with tangible lysate"
	)
	check(
		bool(initial.get("hydraulic_spillway_food_available", false)),
		"the tangible spillway reward starts available"
	)
	var cache: Dictionary = chunk.get("_hydraulic_spillway_food_cache")
	var marker: MeshInstance3D = cache.get("marker", null)
	var interactable: Node = cache.get("interactable", null)
	check(
		marker != null and is_instance_valid(marker) and marker.visible,
		"the available spillway lysate has an independent green marker"
	)
	check(
		interactable != null and bool(interactable.get("interaction_enabled")),
		"the spillway node remains retryable while its food is available"
	)
	check(
		interactable != null and str(interactable.get("tutorial_label")) == "CATCH LYSATE",
		"Expedition names node_04's tangible-food action CATCH LYSATE"
	)

	check(bool(chunk.call("open_first_sluice")), "food test opens First Sluice")
	check(bool(chunk.call("release_cistern_bridge")), "food test installs Cistern Bridge")
	check(bool(chunk.call("toggle_borrowed_current")), "food test diverts Borrowed Current")
	var catch_position := marker.global_position if marker != null else Vector3.ZERO
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
		bool(chunk.call("activate_generated_node", "node_04")),
		"full hands do not block mandatory spillway delivery"
	)
	var failed_pickup := _state(chunk)
	check(
		bool(failed_pickup.get("borrowed_current_delivery_latched", false)),
		"hydraulic delivery latches even when food cannot be carried"
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
		bool(chunk.call("toggle_borrowed_current")),
		"full hands cannot prevent restoring the main current and unlocking the exit"
	)

	host.game_state.remove_item(filler_ids[0])
	check(
		bool(chunk.call("activate_generated_node", "node_04")),
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
	chunk.call("activate_generated_node", "node_04")
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
		bool(reset.get("hydraulic_spillway_food_available", false)) and marker.visible,
		"preview reset rearms the same tangible spillway opportunity"
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
		"Expedition reset keeps node_04's retry Area from intercepting mouse picks"
	)
	check(
		not _is_mouse_pickable(reset_catch_target),
		"Expedition reset keeps the inactive catch target non-pickable until current is diverted"
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
	check(checked >= 6, "outline-ownership probe covers every generated teaching node")


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


func _mesh_visibility(raw: Variant, expected: bool) -> bool:
	if not (raw is Array) or (raw as Array).is_empty():
		return false
	for mesh_v in raw as Array:
		if not (mesh_v is VisualInstance3D) or not is_instance_valid(mesh_v):
			return false
		if bool((mesh_v as VisualInstance3D).visible) != expected:
			return false
	return true


func _label_text(raw: Variant) -> String:
	return str((raw as Label3D).text) if raw is Label3D and is_instance_valid(raw) else ""


func _valid_node_count(raw: Variant) -> int:
	if not (raw is Array):
		return 0
	var count := 0
	for node_v in raw as Array:
		if node_v is Node and is_instance_valid(node_v):
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
