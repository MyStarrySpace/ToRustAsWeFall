extends SceneTree

## Focused regression for generated interaction navigation.
##
## Every generated action must persist a typed, reachable interaction region in
## the same graph used by player movement.  The Rally probe deliberately parks
## one party member on the canonical approach vertex and proves that a servicing
## member already standing on another accepted region vertex is selected without
## a hidden move, teleport, or direct state mutation.

const StretchGeneratorScript := preload(
	"res://scripts/generation/stretch_generator.gd"
)
const RuntimeRegistryScript := preload(
	"res://scripts/generation/generated_node_runtime_registry.gd"
)
const InteractionControllerScript := preload(
	"res://scripts/game/characters/character_interaction_controller.gd"
)
const RunSessionScript := preload("res://scripts/generation/run_session.gd")
const CHAIN_SPEC_PATH := (
	"res://data/generated_stretches/generated_chain_nested_poc_shelter_2_to_3.json"
)
const RANDOM_WALK_SPEC_PATH := (
	"res://data/generated_stretches/generated_random_walk_poc_shelter_3_to_4.json"
)

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var run_session := RunSessionScript.new(777)
	run_session.start()
	var cases: Array[Dictionary] = [
		{
			"label": "chain/nested",
			"spec": StretchGeneratorScript.load_spec(CHAIN_SPEC_PATH),
		},
		{
			"label": "random-walk",
			"spec": StretchGeneratorScript.load_spec(RANDOM_WALK_SPEC_PATH),
		},
		{
			"label": "run-session seed 777",
			"spec": run_session.spec.duplicate(true),
		},
		{
			"label": "survival seed 808",
			"spec": StretchGeneratorScript.generate({
				"id": "generated_actionable_approach_survival",
				"seed": 808,
				"complexity_tier": "hard",
				"progression_stage": 4,
				"limitations": {
					"required": {"archetypes": ["12", "13", "14"]},
					"allowed": {
						"archetypes": ["11", "12", "13", "14", "15", "16"],
						"flora": ["scarpet", "flure", "capbage", "seefern"],
						"enemies": ["sapscraps", "naturalizers"],
					},
				},
			}),
		},
	]
	for case_v in cases:
		_verify_case(case_v)
	_verify_fail_closed_validation(cases[2].get("spec", {}) as Dictionary)
	_finish()


func _verify_case(case_def: Dictionary) -> void:
	var label := str(case_def.get("label", "generated case"))
	var spec: Dictionary = case_def.get("spec", {})
	check(
		not spec.is_empty() and bool(spec.get("success", true)),
		"[%s] fixture generates or loads" % label
	)
	if spec.is_empty() or not bool(spec.get("success", true)):
		return
	var grid := GridWorld.from_data(spec.get("navigation_grid", {}))
	var spec_id := str(spec.get("id", ""))
	var validation := StretchGeneratorScript.validate_actionable_interaction_approaches(
		spec
	)
	check(
		bool(validation.get("valid", false)),
		"[%s] generator's required approach validator accepts the concrete spec" % label
	)
	var actionable_count := 0
	var rally_contract: Dictionary = {}
	for node_v in spec.get("nodes", []):
		if not (node_v is Dictionary):
			continue
		var node := node_v as Dictionary
		if not RuntimeRegistryScript.node_is_actionable(node, spec_id):
			continue
		actionable_count += 1
		var contract: Dictionary = node.get("interaction_approach", {})
		var primary: Dictionary = contract.get("approach_vertex", {})
		var primary_cell := _cell(primary.get("cell", null))
		var primary_level := int(primary.get("level", -1))
		var region: Array = contract.get("region_vertices", [])
		check(
			str(contract.get("contract_id", ""))
				== "generated_interaction_approach_v1"
			and primary_cell != Vector2i(-999999, -999999)
			and primary_level >= 0,
			"[%s/%s] action persists a typed approach vertex"
				% [label, str(node.get("id", "node"))]
		)
		check(
			is_equal_approx(float(contract.get("interaction_radius", NAN)), 1.8)
			and is_equal_approx(float(contract.get("acceptance_radius", NAN)), 1.95),
			"[%s/%s] action persists the shipped interaction and acceptance radii"
				% [label, str(node.get("id", "node"))]
		)
		if primary_cell == Vector2i(-999999, -999999) or primary_level < 0:
			continue
		check(
			grid.is_walkable(primary_cell.x, primary_cell.y, {}, {}, primary_level),
			"[%s/%s] primary approach is walkable on its declared level"
				% [label, str(node.get("id", "node"))]
		)
		check(
			region.size() >= 2,
			"[%s/%s] interaction region retains an alternate Rally arrival"
				% [label, str(node.get("id", "node"))]
		)
		var required_from: Dictionary = contract.get("required_from_vertex", {})
		var from_cell := _cell(required_from.get("cell", null))
		var from_level := int(required_from.get("level", -1))
		var every_region_vertex_valid := not region.is_empty()
		for vertex_v in region:
			if not (vertex_v is Dictionary):
				every_region_vertex_valid = false
				continue
			var vertex := vertex_v as Dictionary
			var cell := _cell(vertex.get("cell", null))
			var level := int(vertex.get("level", -1))
			if cell == Vector2i(-999999, -999999) or level < 0 \
					or not grid.is_walkable(cell.x, cell.y, {}, {}, level) \
					or from_cell == Vector2i(-999999, -999999) or from_level < 0 \
					or grid.find_multi_level_plan(
						from_cell, from_level, cell, level).is_empty():
				every_region_vertex_valid = false
		check(
			every_region_vertex_valid,
			"[%s/%s] every accepted arrival is graph-reachable from its required predecessor"
				% [label, str(node.get("id", "node"))]
		)
		if rally_contract.is_empty() and region.size() >= 2:
			rally_contract = contract
	check(actionable_count > 0, "[%s] fixture contains actionable generated nodes" % label)
	check(
		_test_rally_occupied_primary(grid, rally_contract),
		"[%s] Rally-occupied primary resolves to the servicing actor's reachable region cell"
			% label
	)


func _verify_fail_closed_validation(source_spec: Dictionary) -> void:
	if source_spec.is_empty():
		check(false, "approach validator rejection fixture exists")
		return
	var missing := source_spec.duplicate(true)
	var missing_nodes: Array = missing.get("nodes", [])
	var corrupted_index := -1
	for index in range(missing_nodes.size()):
		if missing_nodes[index] is Dictionary \
				and RuntimeRegistryScript.node_is_actionable(
					missing_nodes[index] as Dictionary, str(missing.get("id", ""))):
			corrupted_index = index
			var node := missing_nodes[index] as Dictionary
			node.erase("interaction_approach")
			missing_nodes[index] = node
			break
	missing["nodes"] = missing_nodes
	check(corrupted_index >= 0, "approach validator rejection fixture has an actionable node")
	check(
		not bool(StretchGeneratorScript.validate_actionable_interaction_approaches(
			missing).get("valid", true)),
		"generator validation fails closed when an actionable approach is missing"
	)
	var migrated_missing := StretchGeneratorScript.canonicalize_spec(
		missing.duplicate(true))
	check(
		bool(StretchGeneratorScript.validate_actionable_interaction_approaches(
			migrated_missing).get("valid", false)),
		"canonicalization migrates the one allowed legacy case: an actually absent key"
	)

	# An absent legacy contract is intentionally migratable. Once a contract is
	# explicitly present, however, canonicalization must preserve it verbatim so
	# validation, load, and save all refuse the bad authoring instead of quietly
	# projecting a different playable truth.
	var malformed_cases: Array[Dictionary] = [
		{"id": "explicit_empty", "label": "explicit empty contract",
			"error": "primary interaction approach is not walkable"},
		{"id": "explicit_null", "label": "explicit null contract",
			"error": "has no interaction approach dictionary"},
		{"id": "explicit_array", "label": "explicit array contract",
			"error": "has no interaction approach dictionary"},
		{"id": "explicit_string", "label": "explicit string contract",
			"error": "has no interaction approach dictionary"},
		{"id": "wrong_handler", "label": "wrong handler"},
		{"id": "wrong_predecessor", "label": "wrong predecessor"},
		{"id": "wrong_component", "label": "wrong component"},
		{"id": "wrong_level", "label": "wrong graph level"},
		{"id": "missing_primary", "label": "missing primary region vertex"},
		{"id": "duplicate_primary", "label": "duplicate primary region vertex"},
		{"id": "reordered_primary", "label": "reordered unique primary region vertex",
			"error": "does not place its primary vertex first"},
		{"id": "missing_alternate", "label": "missing alternate region vertex"},
		{"id": "duplicate_alternate", "label": "duplicate alternate region vertex"},
		{"id": "out_of_radius_approach", "label": "out-of-radius visible approach"},
		{"id": "out_of_radius_region", "label": "out-of-radius region vertex"},
		{"id": "disconnected_region", "label": "predecessor-disconnected region vertex",
			"error": "unreachable from"},
		{"id": "wrong_interaction_radius", "label": "wrong interaction radius"},
		{"id": "wrong_acceptance_radius", "label": "wrong acceptance radius"},
		{"id": "missing_interaction_radius", "label": "missing interaction radius"},
		{"id": "missing_acceptance_radius", "label": "missing acceptance radius"},
		{"id": "typed_interaction_radius", "label": "non-numeric interaction radius"},
		{"id": "typed_acceptance_radius", "label": "non-numeric acceptance radius"},
		{"id": "fractional_vertex_cell", "label": "fractional vertex cell",
			"error": "primary interaction approach is not walkable"},
		{"id": "near_integer_vertex_cell", "label": "near-integer vertex cell",
			"error": "primary interaction approach is not walkable"},
		{"id": "extra_vertex_cell", "label": "extra-coordinate vertex cell",
			"error": "primary interaction approach is not walkable"},
		{"id": "typed_vertex_cell", "label": "non-numeric vertex cell",
			"error": "primary interaction approach is not walkable"},
		{"id": "fractional_vertex_level", "label": "fractional vertex level",
			"error": "primary interaction approach is not walkable"},
		{"id": "near_integer_vertex_level", "label": "near-integer vertex level",
			"error": "primary interaction approach is not walkable"},
		{"id": "typed_vertex_level", "label": "non-numeric vertex level",
			"error": "primary interaction approach is not walkable"},
	]
	for case_index in range(malformed_cases.size()):
		var case_def := malformed_cases[case_index] as Dictionary
		var malformed := source_spec.duplicate(true)
		var mutation := _mutate_explicit_contract_case(
			malformed, str(case_def.get("id", "")), corrupted_index)
		var label := str(case_def.get("label", "malformed contract"))
		check(
			bool(mutation.get("applied", false)),
			"explicit malformed-contract fixture applies: %s" % label
		)
		if not bool(mutation.get("applied", false)):
			continue
		var node_id := str(mutation.get("node_id", ""))
		var malformed_probe := _explicit_contract_probe(malformed, node_id)
		var canonical := StretchGeneratorScript.canonicalize_spec(
			malformed.duplicate(true))
		check(
			JSON.stringify(_explicit_contract_probe(canonical, node_id))
				== JSON.stringify(malformed_probe),
			"canonicalization does not silently migrate explicit %s" % label
		)
		var validation := StretchGeneratorScript.validate_actionable_interaction_approaches(
			canonical)
		check(
			not bool(validation.get("valid", true)),
			"validator refuses explicit %s" % label
		)
		var intended_error := str(case_def.get("error", ""))
		if intended_error != "":
			check(
				("; ".join(validation.get("errors", []))).contains(intended_error),
				"validator reaches the intended %s rejection" % label
			)

		var stem := "generated_actionable_malformed_%02d" % case_index
		var save_path := "user://%s_save.json" % stem
		_remove_fixture(save_path)
		check(
			not StretchGeneratorScript.save_spec(malformed.duplicate(true), save_path)
			and not FileAccess.file_exists(save_path),
			"save refuses explicit %s without writing a replacement" % label
		)
		var load_path := "user://%s_load.json" % stem
		_remove_fixture(load_path)
		var wrote_fixture := _write_json_fixture(load_path, malformed)
		check(wrote_fixture, "load-refusal fixture writes for %s" % label)
		if wrote_fixture:
			check(
				StretchGeneratorScript.load_spec(load_path).is_empty(),
				"load refuses explicit %s" % label
			)
		_remove_fixture(load_path)
		_remove_fixture(save_path)


func _mutate_explicit_contract_case(
	spec: Dictionary, case_id: String, actionable_index: int
	) -> Dictionary:
	var nodes: Array = spec.get("nodes", [])
	if actionable_index < 0 or actionable_index >= nodes.size() \
			or not (nodes[actionable_index] is Dictionary):
		return {}
	var node := (nodes[actionable_index] as Dictionary).duplicate(true)
	var node_id := str(node.get("id", ""))
	if case_id in [
		"explicit_empty", "explicit_null", "explicit_array", "explicit_string"
	]:
		match case_id:
			"explicit_empty":
				node["interaction_approach"] = {}
			"explicit_null":
				node["interaction_approach"] = null
			"explicit_array":
				node["interaction_approach"] = ["malformed"]
			"explicit_string":
				node["interaction_approach"] = "malformed"
		nodes[actionable_index] = node
		spec["nodes"] = nodes
		return {"applied": true, "node_id": node_id}
	var contract := (node.get("interaction_approach", {}) as Dictionary).duplicate(true)
	if contract.is_empty():
		return {}
	var primary := (contract.get("approach_vertex", {}) as Dictionary).duplicate(true)
	var region := (contract.get("region_vertices", []) as Array).duplicate(true)
	if primary.is_empty() or region.size() < 2:
		return {}
	match case_id:
		"wrong_handler":
			contract["handler_id"] = "malformed_runtime_handler"
		"wrong_predecessor":
			contract["required_from_node_id"] = "malformed_predecessor"
		"wrong_component":
			contract["component_id"] = "entry_component:malformed"
		"wrong_level":
			var wrong_level := GridWorld.from_data(
				spec.get("navigation_grid", {})).level_count + 1
			primary["level"] = wrong_level
			contract["approach_vertex"] = primary
			var first := (region[0] as Dictionary).duplicate(true)
			first["level"] = wrong_level
			region[0] = first
			contract["region_vertices"] = region
		"missing_primary":
			region.remove_at(0)
			contract["region_vertices"] = region
		"duplicate_primary":
			region.append(primary.duplicate(true))
			contract["region_vertices"] = region
		"reordered_primary":
			var alternate: Variant = region[1]
			region[1] = region[0]
			region[0] = alternate
			contract["region_vertices"] = region
		"missing_alternate":
			contract["region_vertices"] = [primary.duplicate(true)]
		"duplicate_alternate":
			region.append((region[1] as Dictionary).duplicate(true))
			contract["region_vertices"] = region
		"out_of_radius_approach":
			var approach := _vec3(node.get("approach_position", []), Vector3.INF)
			if not approach.is_finite():
				return {}
			node["approach_position"] = [approach.x + 100.0, approach.y, approach.z]
		"out_of_radius_region":
			var far_vertex := _far_walkable_region_vertex(spec, contract, node)
			if far_vertex.is_empty():
				return {}
			region[1] = far_vertex
			contract["region_vertices"] = region
		"disconnected_region":
			var disconnected := _append_isolated_walkable_vertex(
				spec, int(primary.get("level", 0)))
			if disconnected.is_empty():
				return {}
			region[1] = disconnected
			contract["region_vertices"] = region
		"wrong_interaction_radius":
			contract["interaction_radius"] = 99.0
		"wrong_acceptance_radius":
			contract["acceptance_radius"] = 99.0
		"missing_interaction_radius":
			contract.erase("interaction_radius")
		"missing_acceptance_radius":
			contract.erase("acceptance_radius")
		"typed_interaction_radius":
			contract["interaction_radius"] = "1.8"
		"typed_acceptance_radius":
			contract["acceptance_radius"] = true
		"fractional_vertex_cell":
			primary["cell"] = [float((primary.get("cell", []) as Array)[0]) + 0.5,
				(primary.get("cell", []) as Array)[1]]
			contract["approach_vertex"] = primary
		"near_integer_vertex_cell":
			primary["cell"] = [
				float((primary.get("cell", []) as Array)[0]) + 0.00001,
				(primary.get("cell", []) as Array)[1],
			]
			contract["approach_vertex"] = primary
		"extra_vertex_cell":
			var extra_cell := (primary.get("cell", []) as Array).duplicate(true)
			extra_cell.append(999)
			primary["cell"] = extra_cell
			contract["approach_vertex"] = primary
		"typed_vertex_cell":
			primary["cell"] = ["13", true]
			contract["approach_vertex"] = primary
		"fractional_vertex_level":
			primary["level"] = float(primary.get("level", 0)) + 0.5
			contract["approach_vertex"] = primary
		"near_integer_vertex_level":
			primary["level"] = float(primary.get("level", 0)) + 0.00001
			contract["approach_vertex"] = primary
		"typed_vertex_level":
			primary["level"] = "0"
			contract["approach_vertex"] = primary
		_:
			return {}
	node["interaction_approach"] = contract
	nodes[actionable_index] = node
	spec["nodes"] = nodes
	return {"applied": true, "node_id": node_id}


func _far_walkable_region_vertex(
	spec: Dictionary, contract: Dictionary, node: Dictionary
	) -> Dictionary:
	var grid := GridWorld.from_data(spec.get("navigation_grid", {}))
	var primary: Dictionary = contract.get("approach_vertex", {})
	var primary_level := int(primary.get("level", -1))
	var source := _vec3(node.get("approach_position", []), Vector3.INF)
	var required: Dictionary = contract.get("required_from_vertex", {})
	var required_cell := _cell(required.get("cell", null))
	var required_level := int(required.get("level", -1))
	if primary_level < 0 or primary_level >= grid.level_count \
			or required_cell == Vector2i(-999999, -999999) \
			or required_level < 0 or not source.is_finite():
		return {}
	var best := {}
	var best_distance := float(contract.get("acceptance_radius", 0.0)) + 0.001
	for y in range(grid.height):
		for x in range(grid.width):
			if not grid.is_walkable(x, y, {}, {}, primary_level):
				continue
			var cell := Vector2i(x, y)
			if grid.find_multi_level_plan(
				required_cell, required_level, cell, primary_level).is_empty():
				continue
			var world := grid.grid_to_world(cell, primary_level)
			var distance := Vector2(world.x - source.x, world.z - source.z).length()
			if distance <= best_distance:
				continue
			best_distance = distance
			best = {"cell": [cell.x, cell.y], "level": primary_level}
	return best


func _append_isolated_walkable_vertex(spec: Dictionary, level: int) -> Dictionary:
	var navigation := (spec.get("navigation_grid", {}) as Dictionary).duplicate(true)
	var grid := GridWorld.from_data(navigation)
	if level < 0 or level >= grid.level_count:
		return {}
	for y in range(grid.height):
		for x in range(grid.width):
			var candidate := Vector2i(x, y)
			if grid.is_walkable(x, y, {}, {}, level):
				continue
			var isolated := true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var neighbor := candidate + Vector2i(dx, dy)
					if grid.is_walkable(
						neighbor.x, neighbor.y, {}, {}, level):
						isolated = false
						break
				if not isolated:
					break
			if not isolated:
				continue
			var walkable := (navigation.get("walkable_cells", []) as Array).duplicate(true)
			walkable.append([candidate.x, candidate.y])
			navigation["walkable_cells"] = walkable
			# Multi-level grids can restrict each deck independently. Retain that
			# contract while adding the deliberately disconnected test vertex.
			var level_cells := (navigation.get("level_cells", []) as Array).duplicate(true)
			for entry_index in range(level_cells.size()):
				if level_cells[entry_index] is Dictionary \
						and int((level_cells[entry_index] as Dictionary).get(
							"level", -1)) == level:
					var entry := (level_cells[entry_index] as Dictionary).duplicate(true)
					var cells := (entry.get("cells", []) as Array).duplicate(true)
					cells.append([candidate.x, candidate.y])
					entry["cells"] = cells
					level_cells[entry_index] = entry
					break
			if not level_cells.is_empty():
				navigation["level_cells"] = level_cells
			spec["navigation_grid"] = navigation
			return {"cell": [candidate.x, candidate.y], "level": level}
	return {}


func _explicit_contract_probe(spec: Dictionary, node_id: String) -> Dictionary:
	for node_v in spec.get("nodes", []):
		if node_v is Dictionary and str((node_v as Dictionary).get("id", "")) == node_id:
			var node := node_v as Dictionary
			var contract_v: Variant = node.get("interaction_approach", null)
			var contract_copy: Variant = contract_v
			if contract_v is Dictionary:
				contract_copy = (contract_v as Dictionary).duplicate(true)
			elif contract_v is Array:
				contract_copy = (contract_v as Array).duplicate(true)
			var approach_v: Variant = node.get("approach_position", null)
			var approach_copy: Variant = approach_v
			if approach_v is Array:
				approach_copy = (approach_v as Array).duplicate(true)
			return {
				"interaction_approach": contract_copy,
				"approach_position": approach_copy,
			}
	return {}


func _write_json_fixture(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
	return true


func _remove_fixture(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _vec3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array and (value as Array).size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback


func _test_rally_occupied_primary(grid: GridWorld, contract: Dictionary) -> bool:
	if contract.is_empty():
		return false
	var region: Array = contract.get("region_vertices", [])
	if region.size() < 2 or not (region[0] is Dictionary) \
			or not (region[1] is Dictionary):
		return false
	var primary := region[0] as Dictionary
	var alternate := region[1] as Dictionary
	var primary_cell := _cell(primary.get("cell", null))
	var primary_level := int(primary.get("level", -1))
	var alternate_cell := _cell(alternate.get("cell", null))
	var alternate_level := int(alternate.get("level", -1))
	if primary_cell == Vector2i(-999999, -999999) \
			or alternate_cell == Vector2i(-999999, -999999) \
			or primary_level != alternate_level:
		return false
	var scheduler := EventScheduler.new()
	var state := GameState.new()
	state.grid = grid
	state.scheduler = scheduler
	state.event_log = EventLog.new()
	# Fixture placement establishes the pre-command world. The movement itself is
	# still the shipped Rally command; no character dictionary or transform is
	# mutated behind the gameplay boundary.
	state.register_character(
		"blocker", grid.grid_to_world(primary_cell, primary_level), 3.0, {})
	state.register_character(
		"servicer", grid.grid_to_world(alternate_cell, alternate_level), 3.0, {})
	var moved := state.command_rally_members(
		["blocker", "servicer"], grid.grid_to_world(primary_cell, primary_level))
	if moved != 2:
		return false
	var safety := 0
	while (state.is_moving("blocker") or state.is_moving("servicer")) \
			and safety < 2000:
		safety += 1
		scheduler.advance(0.05)
	if state.is_moving("blocker") or state.is_moving("servicer"):
		return false
	var blocker_cell := grid.world_to_grid(state.get_position("blocker"))
	var servicer_cell := grid.world_to_grid(state.get_position("servicer"))
	if blocker_cell != primary_cell or servicer_cell == primary_cell:
		return false
	var resolved: Dictionary = InteractionControllerScript.resolve_reachable_interaction_location(
		state, "servicer", contract
	)
	return not resolved.is_empty() \
		and int(resolved.get("level", -1)) == state.get_character_level("servicer") \
		and resolved.get("cell", Vector2i(-999999, -999999)) == servicer_cell


func _cell(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i(-999999, -999999)


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  [PASS] %s" % label)
		return
	_failures += 1
	push_error("  [FAIL] %s" % label)


func _finish() -> void:
	print(
		"Generated actionable approaches: %d checks, %d failures"
		% [_checks, _failures]
	)
	quit(1 if _failures > 0 else 0)
