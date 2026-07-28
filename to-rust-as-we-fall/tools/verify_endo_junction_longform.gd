extends Node

## Focused causal, optionality, environment, and recovery-authority audit for Endo's Junction.
## The planning duration band is evaluated by human first-clear playtests; this verifier must not
## turn that band into extra mandatory stations.
## Run:
##   ../Godot_v4.7-stable_win64_console.exe --headless --path . \
##     res://tools/verify_endo_junction_longform.tscn

const PREVIEW_SCENE := preload("res://scenes/fragments/endo_junction_stretch_preview.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	EventLog.print_events = false
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures.append(message)
		push_error("  FAIL: %s" % message)


func _run() -> void:
	var safe_preview := await _spawn_preview()
	var safe_chunk: Node = safe_preview.find_child("Chunk_endo_junction_stretch", true, false) if safe_preview != null else null
	_check(safe_chunk != null, "Endo Junction boots in its shared playable preview")
	if safe_chunk != null:
		_verify_environment(safe_preview, safe_chunk)
		_verify_safe_information_route(safe_preview, safe_chunk)
	await _dispose(safe_preview)

	var direct_preview := await _spawn_preview()
	var direct_chunk: Node = direct_preview.find_child("Chunk_endo_junction_stretch", true, false) if direct_preview != null else null
	_check(direct_chunk != null, "Endo Junction boots independently for the direct branch")
	if direct_chunk != null:
		_verify_direct_tradeoff(direct_preview, direct_chunk)
	await _dispose(direct_preview)
	_finish()


func _spawn_preview() -> Node:
	var preview := PREVIEW_SCENE.instantiate()
	preview.set("suppress_scene_change", true)
	get_tree().root.add_child(preview)
	for _frame in range(14):
		await get_tree().process_frame
	return preview


func _verify_environment(preview: Node, chunk: Node) -> void:
	print("\n=== Endo Junction authored route ===")
	_check(chunk.find_child("EndoJunctionFieldwork", true, false) == null,
		"the shelter approach contains no appended evidence-station circuit")
	_check(chunk.find_children("EndoJunctionField_*", "Interactable", true, false).is_empty(),
		"no mandatory fieldwork checklist posts remain")
	_check(chunk.find_child("EndoJunctionAuthoredPulseCircuit", true, false) == null,
		"the unrelated pulse-circuit asset is not instantiated")
	_check(chunk.find_child("EndoJunctionRouteFloor", true, false) != null
			and chunk.find_child("EndoJunctionEntryApron", true, false) != null,
		"the compact route keeps its readable floor and entry composition")
	_check(chunk.find_child("EndoJunctionHideSlot", true, false) == null,
		"the hide slot is architecture rather than another click target")
	var return_grate := chunk.find_child("EndoJunctionReturnGrateMesh", true, false) as MeshInstance3D
	var grate_material := return_grate.mesh.surface_get_material(0) as BaseMaterial3D \
		if return_grate != null and return_grate.mesh != null \
			and return_grate.mesh.get_surface_count() > 0 else null
	_check(return_grate != null
			and return_grate.mesh != null
			and return_grate.mesh.resource_path.ends_with("endo_return_grate.obj")
			and return_grate.get_child_count() == 0
			and grate_material != null
			and grate_material.albedo_texture != null
			and grate_material.albedo_texture.resource_path.ends_with("endo-junction_grate.png"),
		"the authoritative return blocker uses its portable UV-mapped model, not runtime box art")

	var decoration := chunk.find_child("LevelDecoration", true, false)
	var audit: Dictionary = decoration.get_meta("decoration_audit", {}) if decoration != null else {}
	_check(decoration != null and not audit.is_empty(),
		"the compact shell keeps the shared building-quality decoration pass")

	var expected := [
		"EndoJunctionReadInteractable",
		"EndoJunctionRouteMarkInteractable",
		"EndoJunctionCacheInteractable",
		"EndoJunctionSafeRouteInteractable",
		"EndoJunctionDirectRouteInteractable",
		"EndoJunctionShortcutInteractable",
		"EndoJunctionShelterInteractable",
	]
	var gs = preview.get("_game_state")
	for node_name in expected:
		var station := chunk.find_child(node_name, true, false)
		_check(station != null, "%s remains a physical interactable" % node_name)
		if station != null:
			var data_id := str(station.get("data_id"))
			_check(data_id != "" and gs != null and gs.has_interactable(data_id),
				"%s registers through the shared GameState" % node_name)


func _verify_safe_information_route(preview: Node, chunk: Node) -> void:
	print("\n=== Endo Junction information-for-safety branch ===")
	preview.call("headless_select_character", "endo")
	preview.call("headless_set_character_position", "endo", chunk.SAFE_LEDGE_POS)
	_check(not bool(chunk.call("commit_safe_route")),
		"the safe ledge requires the information that identifies it")

	_move_and_call(preview, chunk, "endo", chunk.JUNCTION_POS, "read_junction",
		"Endo reads the maintained junction")
	_move_and_call(preview, chunk, "aster", chunk.GUIDE_MARK_POS, "mark_safe_route",
		"Aster translates the wall marks into the safe ledge")
	_move_and_call(preview, chunk, "endo", chunk.SAFE_LEDGE_POS, "commit_safe_route",
		"Endo commits to the health-preserving ledge")
	var state: Dictionary = chunk.call("get_preview_state")
	_check(str(state.get("route_phase", "")) == "safe_crossing"
			and bool(state.get("crossing_active", false))
			and not bool(state.get("danger_resolved", true)),
		"the ledge is a saved in-flight traversal rather than an instant completion flag")
	preview.call("headless_advance", 8.0, 0.1)
	state = chunk.call("get_preview_state")
	_check(str(state.get("route_choice", "")) == "safe"
			and str(state.get("route_phase", "")) == "safe_route"
			and is_equal_approx(float(state.get("party_min_hp", 0.0)), 100.0),
		"reaching the far lip resolves the information route and preserves party health")
	_check(not bool(state.get("forage_collected", false)),
		"crossing does not silently consume the optional starch cache")

	_move_and_call(preview, chunk, "endo", chunk.FORAGE_CACHE_POS, "collect_forage",
		"the physical starch cache remains an optional resource choice")
	_move_and_call(preview, chunk, "endo", chunk.SHORTCUT_LOCK_POS, "unlock_shortcut",
		"the return grate begins an optional backtracking improvement")
	preview.call("headless_advance", chunk.SHORTCUT_OPENING_DURATION + 0.1, 0.05)
	state = chunk.call("get_preview_state")
	_check(bool(state.get("shortcut_unlocked", false))
			and str(state.get("shortcut_phase", "")) == PartyGate3D.PHASE_OPEN,
		"the optional grate becomes open only after its physical lift deadline")
	_complete_shelter_rest(preview, chunk, "the informed route")


func _verify_direct_tradeoff(preview: Node, chunk: Node) -> void:
	print("\n=== Endo Junction direct-risk branch ===")
	_move_and_call(preview, chunk, "aster", chunk.RISKY_BLOOM_POS, "commit_direct_route",
		"one character can knowingly enter the visible bloom without servicing unrelated stations")
	var state: Dictionary = chunk.call("get_preview_state")
	_check(str(state.get("route_phase", "")) == "direct_crossing"
			and bool(state.get("crossing_active", false)),
		"the risky route begins as a locked spatial traversal")
	preview.call("headless_advance", 8.0, 0.1)
	state = chunk.call("get_preview_state")
	_check(str(state.get("route_choice", "")) == "direct"
			and str(state.get("route_phase", "")) == "direct_route"
			and float(state.get("direct_damage_total", 0.0)) > 0.0
			and float(state.get("party_min_hp", 0.0)) > 0.0,
		"the shorter route spends real health but remains recoverable")
	_check(not bool(state.get("junction_read", false))
			and not bool(state.get("forage_collected", false))
			and not bool(state.get("shortcut_unlocked", false)),
		"the direct branch leaves optional information, food, and shortcut actions untouched")
	_complete_shelter_rest(preview, chunk, "the direct route")
	state = chunk.call("get_preview_state")
	_check(not bool(state.get("shortcut_unlocked", false)),
		"Shelter 1 is reachable without turning the return grate into a forward gate")


func _complete_shelter_rest(preview: Node, chunk: Node, route_label: String) -> void:
	preview.call("headless_set_character_position", "aster", chunk.SHELTER_POS)
	_check(not bool(chunk.call("reach_shelter")),
		"%s cannot trigger a lone-character night skip" % route_label)
	var atp_before := {}
	for char_id in ["aster", "peris", "endo"]:
		preview.call("headless_set_character_position", char_id, chunk.SHELTER_POS)
		atp_before[char_id] = float(preview.call("get_preview_character_stat", char_id, "atp"))
	_check(bool(chunk.call("reach_shelter")),
		"%s brings the full conscious party to explicit shelter rest" % route_label)
	var state: Dictionary = chunk.call("get_preview_state")
	_check(str(state.get("route_phase", "")) == "complete"
			and bool(state.get("shelter_rested", false)),
		"%s reaches the original Shelter 1 completion contract" % route_label)
	for char_id in ["aster", "peris", "endo"]:
		_check(is_equal_approx(
			float(preview.call("get_preview_character_stat", char_id, "atp")),
			float(atp_before[char_id]) - chunk.SHELTER_ATP_COST
		), "%s pays one ATP through shared shelter-rest authority" % char_id.capitalize())


func _move_and_call(preview: Node, chunk: Node, character_id: String, position: Vector3,
		method_name: String, label: String) -> void:
	preview.call("headless_select_character", character_id)
	preview.call("headless_set_character_position", character_id, position)
	_check(bool(chunk.call(method_name)), label)


func _dispose(preview: Node) -> void:
	if preview != null and is_instance_valid(preview):
		preview.set_process(false)
		preview.set_physics_process(false)
		if preview.has_method("_teardown_sequence"):
			preview.call("_teardown_sequence")
		preview.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	if _failures.is_empty():
		print("\nEndo Junction causal-route verification: ALL PASSED")
		get_tree().quit(0)
	else:
		print("\nEndo Junction causal-route verification: %d FAILED" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
		get_tree().quit(1)
