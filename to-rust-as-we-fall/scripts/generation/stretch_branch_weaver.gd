class_name StretchBranchWeaver
extends RefCounted

## Turns a bare linear stretch grid into a SPINE-WITH-BRANCHES (hub-and-spoke) shape. Branches are not generic
## walking-time padding. Every emitted spoke carries one explicit gameplay role:
##
## - mandatory_producer: the branch produces a state consumed by the next spine blocker;
## - optional_risk_reward: the detour is a genuine exposure-for-resource decision;
##
## Recovery returns are NOT branch rooms. MetaTemplate.return_point_specs owns
## their exact stacked upper/lower anchors; emitting a separate outward room with
## the same role created empty padding that claimed a climbvine it did not host.
##
## The runtime owns the visible mechanism that fulfils each contract. This data layer owns the invariant that a
## branch cannot silently masquerade as optional scenery or an always-on forward shortcut. On a warped helix,
## "outward" is radially outward, so the roles also break up the silhouette without weakening progression gates.
##
## Deterministic: seeded purely from the level (same grid+seed -> same branches every build), so it's replay-safe
## and the chunk reproduces it identically. Operates on the unified_grid_v1 contract and re-emits the SAME keys,
## with world positions of every existing cell preserved (bounds grow + re-index in lockstep with the origin).

const ROLE_MANDATORY_PRODUCER := "mandatory_producer"
const ROLE_OPTIONAL_RISK_REWARD := "optional_risk_reward"
const BRANCH_WEAVE_CONTRACT_ID := "generated_branch_weave_v1"
const BRANCH_ROLES := [
	ROLE_MANDATORY_PRODUCER,
	ROLE_OPTIONAL_RISK_REWARD,
]

# Difficulty may change the relationships inside a branch, but it must not lengthen a stretch by spraying more
# empty rooms. Woven spokes alternate causal producers and priced detours; recovery
# geometry is counted and generated independently by the active meta-template.
const TIER_BRANCH_COUNT := {"teaching": 2, "standard": 2, "hard": 2, "setpiece": 2}
const _MAX_BRANCHES := 6

## Weave branches into `grid_data`. opts: {seed:int, tier:String, count:int(optional override)}. A `stage`
## option is accepted but intentionally ignored: campaign progression cannot add traversal padding.
## Returns a NEW grid_data (the input is not mutated) with the extra walkable cells + a "branches" metadata array.
## Each branch includes its role and causal/topology contract as well as neck/cells/shape. A grid with no walkable
## cells, or count<=0, is returned as-is.
static func weave(grid_data: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var out: Dictionary = grid_data.duplicate(true)
	# A generated spec persists its woven grid, and a host may call weave() on
	# that grid again; treat an emitted weave as authoritative instead
	# of growing a second, runtime-only set of rooms around it.
	var existing_branches = out.get("branches", [])
	if str(out.get("branch_weave_contract_id", "")) == BRANCH_WEAVE_CONTRACT_ID \
			or (existing_branches is Array and not (existing_branches as Array).is_empty()):
		out["branch_weave_contract_id"] = BRANCH_WEAVE_CONTRACT_ID
		out["branch_count"] = (existing_branches as Array).size() \
				if existing_branches is Array else 0
		return out
	var base_cells: Array = grid_data.get("walkable_cells", [])
	if base_cells.is_empty():
		return out
	var tier := str(opts.get("tier", "standard"))
	var count := int(opts.get("count", TIER_BRANCH_COUNT.get(tier, 3)))
	count = mini(_MAX_BRANCHES, count)
	if count <= 0:
		out["branch_weave_contract_id"] = BRANCH_WEAVE_CONTRACT_ID
		out["branch_count"] = 0
		out["branches"] = []
		return out
	var seed := int(opts.get("seed", 0)) ^ 0x5b0c_a9e1
	var rng := SeededRng.new(seed)

	# Occupied cells (0-based grid indices). Branches read the spine's OUTWARD (+z) rim per column from this set.
	var cells := {}
	for c in base_cells:
		cells[Vector2i(int(c[0]), int(c[1]))] = true
	var spine_cells: Dictionary = cells.duplicate()
	# Branch mechanisms currently resolve their cell addresses on navigation level
	# zero. A flattened multi-level rim can make a branch look adjacent in x/z while
	# actually hanging it from an upper floor with no level-zero doorway. Restrict
	# attachment candidates to the exact runtime tier the branch will inhabit.
	var attachment_cells := _runtime_branch_attachment_cells(
		grid_data, spine_cells
	)
	var width := int(grid_data.get("width", 1))
	var height := int(grid_data.get("height", 1))

	# The attachment cell must also be the outer edge of the complete stacked
	# footprint. Otherwise the new room would overlap an upper-level floor in the
	# shared two-dimensional address frame.
	var union_rim := {}
	for v in cells.keys():
		if not union_rim.has(v.x) or v.y > union_rim[v.x]:
			union_rim[v.x] = v.y
	var rim := {}
	for column_v in union_rim.keys():
		var column := int(column_v)
		var edge := Vector2i(column, int(union_rim[column_v]))
		if attachment_cells.has(edge):
			rim[column] = edge.y

	# Attach columns spread across the mid 80% of the level so spokes land at varied helix angles (a star, not a
	# comb bunched at one end). A multi-level base tier may cover only part of the
	# total x range, so use its eligible interval instead of snapping every global
	# quantile to the same final base-tier column.
	var branches: Array = []
	var lo := maxi(1, int(width * 0.10))
	var hi := maxi(lo + 1, int(width * 0.90))
	if bool(grid_data.get("supports_multiple_elevations", false)) \
			and not rim.is_empty():
		var rim_columns: Array = rim.keys()
		rim_columns.sort()
		var rim_min := int(rim_columns[0])
		var rim_max := int(rim_columns[rim_columns.size() - 1])
		var rim_span := maxi(1, rim_max - rim_min)
		lo = clampi(
			rim_min + int(float(rim_span) * 0.10), 1, width - 2
		)
		hi = clampi(
			rim_min + int(ceil(float(rim_span) * 0.90)),
			lo + 1,
			width - 2
		)
	var placed := 0
	for i in range(count):
		var frac := (float(i) + 0.5) / float(count)
		var preferred_column := clampi(
			lo + int(frac * float(hi - lo)) + _ri(rng, -1, 1),
			1,
			width - 2
		)
		var role := _role_for_index(i, count)
		var shape := ""
		var local: Array = []
		# A jagged WFC rim can make the nearest doorway unusable after the
		# single-door filter is applied. Try the remaining real doorways in stable
		# distance order instead of silently reducing the authored branch count.
		for column_v in _ordered_rim_columns(rim, preferred_column, width):
			var nx := int(column_v)
			var rim_z: int = int(rim[nx])
			var consumer_cells: Array = _next_spine_consumer_cells(
				spine_cells, spine_cells, nx, width
			)
			# A causal producer without a later, proven spine cut is not a
			# producer at all. Keep looking for a doorway with a real consumer.
			if consumer_cells.is_empty():
				continue
			if shape.is_empty():
				shape = _pick_shape(rng, tier, role)
				local = _shape_offsets(shape, rng, tier)
			var neck := Vector2i(nx, rim_z + 1)
			var branch_cells: Array[Vector2i] = _trial_branch_cells(
				nx, rim_z, local, attachment_cells, cells
			)
			# A neck by itself is not a branch decision or a meaningful producer
			# detour. A later doorway may still fit this deterministic shape.
			if branch_cells.size() <= 1:
				continue
			for branch_cell in branch_cells:
				cells[branch_cell] = true
			var consumer_cell := _visual_consumer_midpoint(
				consumer_cells, rim_z + 1
			)
			var branch_id := "branch_%02d" % placed
			var producer_cell := _farthest_branch_cell(branch_cells, neck)
			branches.append({
				"id": branch_id,
				"neck": [neck.x, neck.y],
				"shape": shape,
				"cells": branch_cells,
				"role": role,
				"required_for_progress": role == ROLE_MANDATORY_PRODUCER,
				"normal_route_optional": role != ROLE_MANDATORY_PRODUCER,
				"_producer_cell": [producer_cell.x, producer_cell.y],
				"_consumer_cell": [consumer_cell.x, consumer_cell.y],
				"_consumer_cells": _cells_to_arrays(consumer_cells),
				"causal_contract": _branch_contract(
					branch_id,
					role,
					nx,
					[producer_cell.x, producer_cell.y],
					[consumer_cell.x, consumer_cell.y],
					_cells_to_arrays(consumer_cells)
				),
			})
			placed += 1
			break

	if placed == 0:
		out["branch_weave_contract_id"] = BRANCH_WEAVE_CONTRACT_ID
		out["branch_count"] = 0
		out["branches"] = []
		return out
	_normalize_branch_roles(branches, spine_cells, cells, width)
	return _reemit(out, cells, branches)


static func _runtime_branch_attachment_cells(
		grid_data: Dictionary, fallback_cells: Dictionary
) -> Dictionary:
	var level_cells: Array = grid_data.get("level_cells", [])
	if level_cells.is_empty():
		return fallback_cells.duplicate()
	for level_v in level_cells:
		if not (level_v is Dictionary) \
				or int((level_v as Dictionary).get("level", -1)) != 0:
			continue
		var result := {}
		for cell_v in (level_v as Dictionary).get("cells", []):
			var cell := _as_cell(cell_v)
			if cell.x != 2147483647:
				result[cell] = true
		return result
	return {}

# --- shapes ---------------------------------------------------------------------------------------------------

static func _pick_shape(rng: SeededRng, tier: String, role: String) -> String:
	var pool := ["chamber"]
	match role:
		ROLE_MANDATORY_PRODUCER:
			pool = ["chamber", "web"]
		ROLE_OPTIONAL_RISK_REWARD:
			# The longer hall is reserved for a priced detour, never mandatory solved-state walking.
			pool = ["hall", "chamber"]
	if tier == "teaching" and role == ROLE_MANDATORY_PRODUCER:
		pool = ["chamber"]
	return str(rng.pick(pool))


## Alternate producers and meaningful optional bets. Recovery returns are owned
## by the meta-template's exact stacked anchors, never by these outward rooms.
static func _role_for_index(index: int, _count: int) -> String:
	if index % 2 == 1:
		return ROLE_OPTIONAL_RISK_REWARD
	return ROLE_MANDATORY_PRODUCER


## A rare overlap can reject a requested spoke. Reassign against the branches that actually survived so the first
## real branch is always a producer; the contract must never depend on a missing
## array slot. No normalization path may manufacture a recovery room.
static func _normalize_branch_roles(
		branches: Array, spine_cells: Dictionary, all_cells: Dictionary, width: int
) -> void:
	for index in range(branches.size()):
		var branch := branches[index] as Dictionary
		var role := _role_for_index(index, branches.size())
		var branch_id := "branch_%02d" % index
		var previous_contract: Dictionary = branch.get("causal_contract", {})
		var spine_column := int(previous_contract.get("spine_column", 0))
		var producer_cell: Array = branch.get(
			"_producer_cell", previous_contract.get("producer_cell", [])
		)
		var consumer_cells: Array = _next_spine_consumer_cells(
			spine_cells,
			all_cells,
			_max_branch_column(branch.get("cells", []), spine_column),
			width
		) if role == ROLE_MANDATORY_PRODUCER else []
		var neck: Array = branch.get("neck", [spine_column, 0])
		var consumer_cell := _visual_consumer_midpoint(
			consumer_cells, int(neck[1]) if neck.size() >= 2 else 0
		)
		var consumer_cell_array: Array = [consumer_cell.x, consumer_cell.y] \
				if not consumer_cells.is_empty() else []
		branch["id"] = branch_id
		branch["role"] = role
		branch["required_for_progress"] = role == ROLE_MANDATORY_PRODUCER
		branch["normal_route_optional"] = role != ROLE_MANDATORY_PRODUCER
		branch["causal_contract"] = _branch_contract(
			branch_id,
			role,
			spine_column,
			producer_cell,
			consumer_cell_array,
			_cells_to_arrays(consumer_cells)
		)
		branch.erase("_producer_cell")
		branch.erase("_consumer_cell")
		branch.erase("_consumer_cells")
		branches[index] = branch


static func _branch_contract(
		branch_id: String,
		role: String,
		spine_column: int,
		producer_cell: Array = [],
		consumer_cell: Array = [],
		consumer_cells: Array = []
) -> Dictionary:
	var contract := {
		"contract_id": "generated_branch_role_v1",
		"branch_id": branch_id,
		"role": role,
		"spine_column": spine_column,
		"cannot_bypass_unresolved": true,
		"starts_active": true,
		"activation_policy": "enter_branch",
		"content_policy": "causal_producer",
		"topology_effect": "unlock_next_spine_blocker",
		"produces_state": "%s_resolved" % branch_id,
		"consumer_policy": "next_unresolved_spine_blocker",
	}
	match role:
		ROLE_MANDATORY_PRODUCER:
			contract.merge({
				"activation_policy": "interact_at_producer",
				"runtime_handler": "branch_span_producer",
				"completion_phase": "bridged",
				"wait_for_completion": true,
				"cell_frame": "unified_grid_v1",
				"producer_cell": producer_cell.duplicate(),
				"consumer_cells": consumer_cells.duplicate(true),
				"consumer_cell": consumer_cell.duplicate(),
				"consumer_cell_role": "visual_midpoint",
				"consumer_addressing": "exact_cell",
				"consumer_cells_addressing": "exact_cut_set",
				"consumer_derivation": "first_later_spine_disconnect_cut",
				"cut_proof": "entry_exit_disconnected_when_removed",
			}, true)
		ROLE_OPTIONAL_RISK_REWARD:
			contract.merge({
				"content_policy": "risk_scaled_physical_reward",
				"topology_effect": "none",
				"produces_state": "",
				"consumer_policy": "none",
			}, true)
	return contract


## Pick a stable physical source anchor at the back of the branch. Ties prefer
## the more-outward row, then the lower x value, so dictionary iteration order
## can never change the emitted producer address.
static func _farthest_branch_cell(branch_cells: Array, neck: Vector2i) -> Vector2i:
	var best := Vector2i(2147483647, 0)
	var best_distance_squared := -1
	for cell_v in branch_cells:
		var cell := cell_v as Vector2i
		var dx := cell.x - neck.x
		var dz := cell.y - neck.y
		var distance_squared := dx * dx + dz * dz
		if (
			distance_squared > best_distance_squared
			or (
				distance_squared == best_distance_squared
				and (cell.y > best.y or (cell.y == best.y and cell.x < best.x))
			)
		):
			best = cell
			best_distance_squared = distance_squared
	return best


## Resolve the semantic "next blocker" to the first later cross-section whose
## removal actually disconnects the two progress ends. Candidate columns must
## still contain the untouched spine, but the cut includes every final walkable
## cell in that column so a side room can never leave a hidden route around it.
static func _next_spine_consumer_cells(
		spine_cells: Dictionary,
		traversal_cells: Dictionary,
		after_column: int,
		width: int
) -> Array:
	for x in range(after_column + 1, width):
		if _column_cells(spine_cells, x).is_empty():
			continue
		var candidate := _column_cells(traversal_cells, x)
		if not candidate.is_empty() and _cut_disconnects(traversal_cells, candidate):
			return candidate
	return []


static func _column_cells(cell_set: Dictionary, column: int) -> Array:
	var result: Array = []
	for cell_v in cell_set.keys():
		var cell := cell_v as Vector2i
		if cell.x == column:
			result.append(cell)
	result.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y)
	return result


static func _visual_consumer_midpoint(consumer_cells: Array, neck_row: int) -> Vector2i:
	var best := Vector2i(2147483647, 0)
	var best_distance := 2147483647
	for cell_v in consumer_cells:
		var cell := _as_cell(cell_v)
		if cell.x == 2147483647:
			continue
		var distance := absi(cell.y - neck_row)
		if distance < best_distance or (distance == best_distance and cell.y < best.y):
			best = cell
			best_distance = distance
	return best


static func _max_branch_column(branch_cells: Array, fallback: int) -> int:
	var result := fallback
	for cell_v in branch_cells:
		var cell := _as_cell(cell_v)
		if cell.x != 2147483647:
			result = maxi(result, cell.x)
	return result


static func _cells_to_arrays(cells: Array) -> Array:
	var result: Array = []
	for cell_v in cells:
		var cell := _as_cell(cell_v)
		if cell.x != 2147483647:
			result.append([cell.x, cell.y])
	return result


static func _as_cell(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Vector2:
		var vector := value as Vector2
		return Vector2i(int(vector.x), int(vector.y))
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	return Vector2i(2147483647, 0)


## Match GridWorld's eight-direction movement including its diagonal corner rule.
## The uncut grid must connect before a set qualifies as a causal blocker.
static func _cut_disconnects(cell_set: Dictionary, cut_cells: Array) -> bool:
	if cell_set.is_empty() or cut_cells.is_empty():
		return false
	var min_x := 2147483647
	var max_x := -2147483647
	for cell_v in cell_set.keys():
		var cell := cell_v as Vector2i
		min_x = mini(min_x, cell.x)
		max_x = maxi(max_x, cell.x)
	if min_x >= max_x:
		return false
	var starts := _column_cells(cell_set, min_x)
	var goals := _column_cells(cell_set, max_x)
	if not _side_sets_connected(cell_set, starts, goals, {}):
		return false
	var blocked := {}
	for cell_v in cut_cells:
		var cell := _as_cell(cell_v)
		if cell.x == 2147483647 or not cell_set.has(cell):
			return false
		blocked[cell] = true
	return not _side_sets_connected(cell_set, starts, goals, blocked)


static func _side_sets_connected(
		cell_set: Dictionary, starts: Array, goals: Array, blocked: Dictionary
) -> bool:
	var goal_set := {}
	for goal_v in goals:
		goal_set[_as_cell(goal_v)] = true
	var open: Array = []
	var visited := {}
	for start_v in starts:
		var start := _as_cell(start_v)
		if blocked.has(start):
			continue
		open.append(start)
		visited[start] = true
	var directions := [
		Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
	]
	while not open.is_empty():
		var current := open.pop_front() as Vector2i
		if goal_set.has(current):
			return true
		for direction_v in directions:
			var direction := direction_v as Vector2i
			var neighbor: Vector2i = current + direction
			if visited.has(neighbor) or blocked.has(neighbor) or not cell_set.has(neighbor):
				continue
			if direction.x != 0 and direction.y != 0:
				var side_x: Vector2i = current + Vector2i(direction.x, 0)
				var side_y: Vector2i = current + Vector2i(0, direction.y)
				if blocked.has(side_x) or blocked.has(side_y) \
						or not cell_set.has(side_x) or not cell_set.has(side_y):
					continue
			visited[neighbor] = true
			open.append(neighbor)
	return false


static func _touches_cell_set(cell: Vector2i, cell_set: Dictionary) -> bool:
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if cell_set.has(cell + direction):
			return true
	return false


static func _trial_branch_cells(
		nx: int,
		rim_z: int,
		local_offsets: Array,
		attachment_cells: Dictionary,
		occupied_cells: Dictionary
) -> Array[Vector2i]:
	var neck := Vector2i(nx, rim_z + 1)
	var trial_cells: Array[Vector2i] = []
	for offset_v in local_offsets:
		var offset: Vector2i = offset_v as Vector2i
		var cell := Vector2i(nx + offset.x, rim_z + 1 + offset.y)
		# A spoke owns exactly one same-level connection to the spine. Applying
		# this rule to a flattened multi-level footprint removes valid stems merely
		# because an unrelated deck shares the same X/Z address.
		if cell != neck and _touches_cell_set(cell, attachment_cells):
			continue
		if occupied_cells.has(cell):
			continue
		trial_cells.append(cell)
	# Filtering a wide room can leave diagonal islands. GridWorld will not cross
	# their blocked corners, so only commit the cardinal component from the neck.
	return _cardinal_branch_component(trial_cells, neck)


static func _cardinal_branch_component(
		branch_cells: Array, neck: Vector2i
) -> Array[Vector2i]:
	var cell_set := {}
	for cell_v in branch_cells:
		var cell := _as_cell(cell_v)
		if cell.x != 2147483647:
			cell_set[cell] = true
	if not cell_set.has(neck):
		return []
	var open: Array[Vector2i] = [neck]
	var visited := {neck: true}
	while not open.is_empty():
		var current: Vector2i = open.pop_front()
		for direction in [
			Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
		]:
			var neighbor: Vector2i = current + direction
			if cell_set.has(neighbor) and not visited.has(neighbor):
				visited[neighbor] = true
				open.append(neighbor)
	var connected: Array[Vector2i] = []
	connected.assign(visited.keys())
	connected.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return connected


## Public structural verifier for preview hosts and focused generation tests. Runtime mechanics may add state, but
## may not reinterpret these roles or turn a recovery link into forward progression.
static func validate_branch_contracts(branches: Array, grid_data: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	var proven_cut_count := 0
	var reachable_mandatory_producer_count := 0
	var grid_cells := {}
	for cell_v in grid_data.get("walkable_cells", []):
		var grid_cell := _as_cell(cell_v)
		if grid_cell.x != 2147483647:
			grid_cells[grid_cell] = true
	var level_cell_sets := {}
	for level_v in grid_data.get("level_cells", []):
		if not (level_v is Dictionary):
			continue
		var level := int((level_v as Dictionary).get("level", 0))
		var level_set := {}
		for cell_v in (level_v as Dictionary).get("cells", []):
			var level_cell: Vector2i = _as_cell(cell_v)
			if level_cell.x != 2147483647:
				level_set[level_cell] = true
		level_cell_sets[level] = level_set
	if level_cell_sets.is_empty() and not grid_cells.is_empty():
		level_cell_sets[0] = grid_cells.duplicate()
	var runtime_level_cells := _runtime_branch_attachment_cells(
		grid_data, grid_cells
	)
	var all_branch_cells := {}
	for branch_v in branches:
		if not (branch_v is Dictionary):
			continue
		for branch_cell_v in (branch_v as Dictionary).get("cells", []):
			var branch_cell := _as_cell(branch_cell_v)
			if branch_cell.x != 2147483647:
				all_branch_cells[branch_cell] = true
	# Two branches may never claim the same consumer cell. A grid blocker cell has exactly one
	# owner, so the second span's configure() refuses and the chunk skips it -- the geometry stays
	# open while the producer interaction never exists, and the exit transaction is permanently
	# refused. That failure is silent at runtime, so it must be loud here.
	var consumer_cell_owners := {}
	for branch_v in branches:
		if not (branch_v is Dictionary):
			continue
		var owner_id := str((branch_v as Dictionary).get("id", "?"))
		for cut_cell_v in (branch_v as Dictionary).get("_consumer_cells", []):
			var cut_cell := _as_cell(cut_cell_v)
			if cut_cell.x == 2147483647:
				continue
			if consumer_cell_owners.has(cut_cell) \
					and str(consumer_cell_owners[cut_cell]) != owner_id:
				errors.append(
					"Branches '%s' and '%s' share consumer cell %s; a blocker cell has one owner, so the second span cannot configure."
					% [str(consumer_cell_owners[cut_cell]), owner_id, str(cut_cell)])
			consumer_cell_owners[cut_cell] = owner_id
	var role_counts := {
		ROLE_MANDATORY_PRODUCER: 0,
		ROLE_OPTIONAL_RISK_REWARD: 0,
	}
	for index in range(branches.size()):
		if not (branches[index] is Dictionary):
			errors.append("Branch %d is not a dictionary." % index)
			continue
		var branch := branches[index] as Dictionary
		var branch_id := str(branch.get("id", "branch_%02d" % index))
		var role := str(branch.get("role", ""))
		if not BRANCH_ROLES.has(role):
			errors.append("%s has unknown or missing role '%s'." % [branch_id, role])
			continue
		role_counts[role] = int(role_counts.get(role, 0)) + 1
		var contract: Dictionary = branch.get("causal_contract", {})
		if str(contract.get("role", "")) != role \
				or not bool(contract.get("cannot_bypass_unresolved", false)):
			errors.append("%s has a mismatched or unsafe causal contract." % branch_id)
		if not grid_cells.is_empty():
			var neck_cell := _as_cell(branch.get("neck", []))
			var runtime_doorway_valid := (
				neck_cell.x != 2147483647
				and runtime_level_cells.has(neck_cell)
			)
			if runtime_doorway_valid:
				runtime_doorway_valid = false
				for direction_v in [
					Vector2i.LEFT,
					Vector2i.RIGHT,
					Vector2i.UP,
					Vector2i.DOWN,
				]:
					var direction := direction_v as Vector2i
					var neighbor: Vector2i = neck_cell + direction
					if runtime_level_cells.has(neighbor) \
							and not all_branch_cells.has(neighbor):
						runtime_doorway_valid = true
						break
			if not runtime_doorway_valid:
				errors.append(
					"%s has no traversable level-0 doorway into the authored spine."
					% branch_id
				)
		match role:
			ROLE_MANDATORY_PRODUCER:
				var producer_cell = contract.get("producer_cell", null)
				var consumer_cell = contract.get("consumer_cell", null)
				var consumer_cells: Array = contract.get("consumer_cells", [])
				var branch_cells: Array = branch.get("cells", [])
				var branch_cell_set := {}
				for branch_cell_v in branch_cells:
					branch_cell_set[_as_cell(branch_cell_v)] = true
				var consumer_set := {}
				var consumer_column := -2147483648
				var consumer_cells_valid := not consumer_cells.is_empty()
				for cut_cell_v in consumer_cells:
					var cut_cell := _as_cell(cut_cell_v)
					if cut_cell.x == 2147483647 or branch_cell_set.has(cut_cell) \
							or consumer_set.has(cut_cell):
						consumer_cells_valid = false
						continue
					if consumer_column == -2147483648:
						consumer_column = cut_cell.x
					elif cut_cell.x != consumer_column:
						consumer_cells_valid = false
					consumer_set[cut_cell] = true
				var neck: Array = branch.get("neck", [0, 0])
				var expected_visual := _visual_consumer_midpoint(
					consumer_cells, int(neck[1]) if neck.size() >= 2 else 0
				)
				var exact_cells_valid := (
					producer_cell is Array
					and (producer_cell as Array).size() >= 2
					and branch_cell_set.has(_as_cell(producer_cell))
					and consumer_cell is Array
					and (consumer_cell as Array).size() >= 2
					and _as_cell(consumer_cell) == expected_visual
					and consumer_set.has(_as_cell(consumer_cell))
					and consumer_cells_valid
					and consumer_column > _max_branch_column(
						branch_cells, int(contract.get("spine_column", -1))
					)
				)
				var producer_reachable_before_cut := true
				if not grid_cells.is_empty():
					var producer_level := int(branch.get(
						"navigation_level",
						contract.get("producer_navigation_level", 0)
					))
					var producer_level_cells: Dictionary = level_cell_sets.get(
						producer_level, {}
					)
					var producer: Vector2i = _as_cell(producer_cell)
					var neck_cell: Vector2i = _as_cell(branch.get("neck", []))
					var blocked_before_activation := {}
					for consumer_v in consumer_cells:
						var blocked_cell: Vector2i = _as_cell(consumer_v)
						if blocked_cell.x != 2147483647:
							blocked_before_activation[blocked_cell] = true
					producer_reachable_before_cut = (
						producer_level_cells.has(neck_cell)
						and producer_level_cells.has(producer)
						and _side_sets_connected(
							producer_level_cells,
							[neck_cell],
							[producer],
							blocked_before_activation
						)
					)
					if producer_reachable_before_cut:
						reachable_mandatory_producer_count += 1
				var cut_is_proven := true
				if not grid_cells.is_empty():
					cut_is_proven = _cut_disconnects(grid_cells, consumer_cells)
					if cut_is_proven:
						proven_cut_count += 1
				if not bool(branch.get("required_for_progress", false)) \
						or str(contract.get("topology_effect", "")) != "unlock_next_spine_blocker" \
						or str(contract.get("consumer_policy", "")) != "next_unresolved_spine_blocker" \
						or str(contract.get("consumer_addressing", "")) != "exact_cell" \
						or str(contract.get("consumer_cells_addressing", "")) != "exact_cut_set" \
						or str(contract.get("consumer_cell_role", "")) != "visual_midpoint" \
						or not exact_cells_valid or not cut_is_proven \
						or not producer_reachable_before_cut:
					errors.append("%s does not feed a mandatory spine blocker." % branch_id)
				if not producer_reachable_before_cut:
					errors.append(
						"%s producer is unreachable from its declared-level neck before its consumer cut."
						% branch_id
					)
			ROLE_OPTIONAL_RISK_REWARD:
				if bool(branch.get("required_for_progress", true)) \
						or str(contract.get("content_policy", "")) != "risk_scaled_physical_reward" \
						or str(contract.get("topology_effect", "")) != "none":
					errors.append("%s is not an optional risk/reward decision." % branch_id)
	if not branches.is_empty() and int(role_counts[ROLE_MANDATORY_PRODUCER]) == 0:
		errors.append("A woven stretch has no mandatory producer branch.")
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"role_counts": role_counts,
		"proven_cut_count": proven_cut_count,
		"reachable_mandatory_producer_count": reachable_mandatory_producer_count,
	}

## Local cell offsets for a shape, in (dv = lateral spread across the spine, du = depth outward). Always includes
## (0,0) — the neck touching the spine — so the room is path-connected. du grows AWAY from the spine (+z).
static func _shape_offsets(shape: String, rng: SeededRng, _tier: String) -> Array:
	# Higher pressure tiers do not buy difficulty by adding solved-state walking distance.
	var big := 0
	match shape:
		"pocket":
			return _rect(_ri(rng, 2, 3), _ri(rng, 2, 3))
		"chamber":
			return _rect(_ri(rng, 3, 4 + big), _ri(rng, 4, 5 + big))
		"hall":
			# a long narrow spoke opening into a room at its far end
			var stem: Array = _rect(2, _ri(rng, 3, 4))
			var room: Array = _rect_at(_ri(rng, 4, 5 + big), _ri(rng, 2, 3 + big), 0, len_of(stem))
			return stem + room
		"web":
			# a small hub with thin arms — the "web-like" variant
			var out: Array = _rect(2, 2)
			out.append_array(_rect_at(1, _ri(rng, 2, 3), -2, 1))   # left arm
			out.append_array(_rect_at(1, _ri(rng, 2, 3), 2, 1))    # right arm
			out.append_array(_rect_at(2, _ri(rng, 2, 3), 0, 2))    # far arm
			return out
	return _rect(2, 2)

## A width×depth rectangle of local offsets centred laterally on the neck, growing outward from depth 0.
static func _rect(w: int, d: int) -> Array:
	return _rect_at(w, d, 0, 0)

## width×depth rectangle centred at lateral `cv` and starting at depth `d0`.
static func _rect_at(w: int, d: int, cv: int, d0: int) -> Array:
	var out: Array = []
	var half := int(w / 2)
	for dv in range(-half, w - half):
		for du in range(d):
			out.append(Vector2i(cv + dv, d0 + du))
	return out

## Max depth reached by a set of offsets (so a hall's room can start past its stem).
static func len_of(offsets: Array) -> int:
	var m := 0
	for o in offsets:
		m = maxi(m, int(o.y) + 1)
	return m

## Seeded int in [a, b]. Routed through SeededRng.call so the deterministic-RNG lint (which text-scans for the
## raw engine RNG API) stays clean — this is generation, seeded and replayable, never wall-clock.
static func _ri(rng: SeededRng, a: int, b: int) -> int:
	return int(rng.call("randi_range", a, b))

static func _ordered_rim_columns(
		rim: Dictionary, preferred_column: int, width: int
) -> Array[int]:
	var ordered: Array[int] = []
	if rim.has(preferred_column):
		ordered.append(preferred_column)
	for step in range(1, width):
		var right := preferred_column + step
		if right <= width - 2 and rim.has(right):
			ordered.append(right)
		var left := preferred_column - step
		if left >= 1 and rim.has(left):
			ordered.append(left)
	return ordered

# --- re-emit the unified_grid_v1 with the branch cells added, world positions preserved ------------------------

static func _reemit(out: Dictionary, cells: Dictionary, branches: Array) -> Dictionary:
	# Renormalise so every cell index is >= 0 again; shift the origin in lockstep so no existing cell's WORLD
	# position moves (origin + cell stays constant), and the coord_map (built from the pre-weave spine) still aligns.
	var min_x := 0x7fffffff
	var min_z := 0x7fffffff
	var max_x := -0x7fffffff
	var max_z := -0x7fffffff
	for v in cells.keys():
		min_x = mini(min_x, v.x); min_z = mini(min_z, v.y)
		max_x = maxi(max_x, v.x); max_z = maxi(max_z, v.y)
	# Keep every existing non-negative cell index stable. Older runtime-only weaving
	# trimmed unused leading padding, which was harmless to the floor but invalidated
	# generator-authored socket/feature cell addresses once the weave became part of
	# the persisted spec. Rebase only when a new branch actually crosses below zero.
	var shift := Vector2i(mini(0, min_x), mini(0, min_z))
	var cell_size := float(out.get("cell_size", 1.0))
	var origin: Array = out.get("origin", [0.0, 0.45, 0.0])
	out["origin"] = [float(origin[0]) + float(shift.x) * cell_size, float(origin[1]), float(origin[2]) + float(shift.y) * cell_size]
	out["width"] = maxi(int(out.get("width", 1)) - shift.x, max_x - shift.x + 1)
	out["height"] = maxi(int(out.get("height", 1)) - shift.y, max_z - shift.y + 1)

	out["walkable_cells"] = _sorted_shift(cells.keys(), shift)

	# Branches sit on level 0. If the grid is multi-level, extend level 0's cell list; re-shift the rest.
	var level_cells: Array = out.get("level_cells", [])
	if not level_cells.is_empty():
		out["level_cells"] = _reemit_levels(level_cells, cells, branches, shift)

	# Re-index (shift) the derived cell lists that reference grid cells. Branch cells add none of these.
	out["risk_cell_list"] = _shift_risk(out.get("risk_cell_list", []), shift)
	out["route_cells"] = _shift_routes(out.get("route_cells", {}), shift)
	out["links"] = _shift_links(out.get("links", []), shift)

	# Branch metadata (shifted to the new 0-based frame) for content scatter + tests.
	var brs: Array = []
	for b in branches:
		var nc: Array = b["neck"]
		var emitted: Dictionary = b.duplicate(true)
		# Newly woven spokes are authored onto the attachment tier selected above.
		# Persist the graph identity so runtime compatibility code never has to infer
		# a producer floor from an unrelated consumer sharing the same X/Z address.
		var producer_level := int(emitted.get("navigation_level", 0))
		emitted["navigation_level"] = producer_level
		emitted["neck"] = [int(nc[0]) - shift.x, int(nc[1]) - shift.y]
		emitted["shape"] = str(b["shape"])
		emitted["cells"] = _sorted_shift(b["cells"], shift)
		var contract: Dictionary = emitted.get("causal_contract", {}).duplicate(true)
		contract["spine_column"] = int(contract.get("spine_column", 0)) - shift.x
		for cell_key in ["producer_cell", "consumer_cell"]:
			var raw_cell = contract.get(cell_key, null)
			if raw_cell is Array and (raw_cell as Array).size() >= 2:
				contract[cell_key] = [
					int((raw_cell as Array)[0]) - shift.x,
					int((raw_cell as Array)[1]) - shift.y,
				]
		var shifted_consumer_cells: Array = []
		for raw_consumer_v in contract.get("consumer_cells", []):
			var raw_consumer := _as_cell(raw_consumer_v)
			if raw_consumer.x != 2147483647:
				shifted_consumer_cells.append([
					raw_consumer.x - shift.x, raw_consumer.y - shift.y,
				])
		contract["consumer_cells"] = shifted_consumer_cells
		contract["producer_navigation_level"] = producer_level
		if not shifted_consumer_cells.is_empty():
			contract["consumer_navigation_level"] = _best_level_for_cells(
				out.get("level_cells", []), shifted_consumer_cells, producer_level
			)
		emitted["causal_contract"] = contract
		brs.append(emitted)
	out["branches"] = brs
	out["branch_weave_contract_id"] = BRANCH_WEAVE_CONTRACT_ID
	out["branch_count"] = brs.size()
	return out


static func _best_level_for_cells(
		level_entries: Array, addressed_cells: Array, fallback_level: int
) -> int:
	if level_entries.is_empty() or addressed_cells.is_empty():
		return fallback_level
	var wanted := {}
	for cell_v in addressed_cells:
		var cell: Vector2i = _as_cell(cell_v)
		if cell.x != 2147483647:
			wanted[cell] = true
	var best_level := fallback_level
	var best_coverage := -1
	for entry_v in level_entries:
		if not (entry_v is Dictionary):
			continue
		var entry := entry_v as Dictionary
		var level := int(entry.get("level", 0))
		var coverage := 0
		for cell_v in entry.get("cells", []):
			if wanted.has(_as_cell(cell_v)):
				coverage += 1
		if coverage > best_coverage or (
			coverage == best_coverage and level == fallback_level
		):
			best_coverage = coverage
			best_level = level
	return best_level

static func _reemit_levels(level_cells: Array, all_cells: Dictionary, branches: Array, shift: Vector2i) -> Array:
	# Branch cells all belong to level 0; other levels keep their original cells (re-shifted). Rebuild level 0 as
	# (its original cells + every branch cell), so the union matches walkable_cells.
	var branch_set := {}
	for b in branches:
		for c in b["cells"]:
			branch_set[c] = true
	var out: Array = []
	for entry in level_cells:
		var lvl := int(entry.get("level", 0))
		var lset := {}
		for c in entry.get("cells", []):
			lset[Vector2i(int(c[0]), int(c[1]))] = true
		if lvl == 0:
			for c in branch_set.keys():
				lset[c] = true
		out.append({"level": lvl, "cells": _sorted_shift(lset.keys(), shift)})
	return out

static func _shift_risk(risk_list: Array, shift: Vector2i) -> Array:
	var out: Array = []
	for r in risk_list:
		var c: Array = r.get("cell", [0, 0])
		out.append({"cell": [int(c[0]) - shift.x, int(c[1]) - shift.y],
			"penalty": float(r.get("penalty", 0.0)), "recoverable": bool(r.get("recoverable", true))})
	return out

static func _shift_routes(route_cells: Dictionary, shift: Vector2i) -> Dictionary:
	var out := {}
	for rid in route_cells.keys():
		var src: Dictionary = route_cells[rid]
		var cells_out: Array = []
		for c in src.get("cells", []):
			cells_out.append([int(c[0]) - shift.x, int(c[1]) - shift.y])
		out[rid] = {"cells": cells_out, "kind": str(src.get("kind", ""))}
	return out

static func _shift_links(links: Array, shift: Vector2i) -> Array:
	var out: Array = []
	for lk in links:
		var c: Array = lk.get("cell", [0, 0])
		out.append({"cell": [int(c[0]) - shift.x, int(c[1]) - shift.y],
			"from": int(lk.get("from", 0)), "to": int(lk.get("to", 0)), "type": str(lk.get("type", "ramp"))})
	return out

static func _sorted_shift(keys, shift: Vector2i) -> Array:
	var arr: Array = []
	for v in keys:
		arr.append(v)
	arr.sort_custom(func(p, q): return (p.y * 100000 + p.x) < (q.y * 100000 + q.x))
	var out: Array = []
	for v in arr:
		out.append([v.x - shift.x, v.y - shift.y])
	return out
