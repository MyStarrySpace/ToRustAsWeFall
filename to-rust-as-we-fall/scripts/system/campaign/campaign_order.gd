class_name CampaignOrder
extends RefCounted

## A hierarchical, reorderable campaign map: a tree of nodes (campaign > act > region >
## optional groups > stretch leaves) that sequences the archetype-generated stretches
## into a playable order. Stretch leaves reference a generated spec by id and carry the
## entry/exit shelters + progression stage the generator produced, so the order can be
## validated against real shelter connectivity and stage progression. Pure data — the
## game loads the manifest, the Android manager edits it; both share this JSON shape.

const SCHEMA := "trawf_campaign_order_v1"
const CONTAINER_KINDS := ["campaign", "act", "region", "group"]
const KIND_STRETCH := "stretch"

var data: Dictionary = {}


func _init(initial := {}) -> void:
	if initial is Dictionary and not initial.is_empty():
		from_dict(initial)
	else:
		data = {
			"schema": SCHEMA,
			"title": "Campaign",
			"next_id": 1,
			"root": _make_node("campaign", "Campaign"),
		}


# ----------------------------------------------------------------- construction

func _make_node(kind: String, title: String, extra := {}) -> Dictionary:
	var node := {
		"id": _alloc_id(kind),
		"kind": kind,
		"title": title,
		"children": [],
	}
	for key in extra.keys():
		node[key] = extra[key]
	return node


func _alloc_id(kind: String) -> String:
	var n := int(data.get("next_id", 1))
	data["next_id"] = n + 1
	return "%s_%03d" % [kind, n]


func root() -> Dictionary:
	return data.get("root", {})


## Build a default Act > Region > stretch tree from every generated spec in a directory.
## Stretches group by world_slot.act + region and order by (progression_stage, entry
## shelter number, id); regions order by their earliest stage.
static func build_default_from_dir(spec_dir: String) -> CampaignOrder:
	var order := CampaignOrder.new()
	var specs := _load_spec_summaries(spec_dir)
	# act -> region -> [summary]
	var by_act := {}
	for s in specs:
		var act := int(s.get("act", 1))
		var region := str(s.get("region", "Unsorted"))
		if not by_act.has(act):
			by_act[act] = {}
		if not by_act[act].has(region):
			by_act[act][region] = []
		by_act[act][region].append(s)

	var root := order.root()
	root["title"] = "To Rust As We Fall"
	var acts := by_act.keys()
	acts.sort()
	for act in acts:
		var act_node := order._make_node("act", "Act %d" % act, {"act": act})
		var regions: Array = by_act[act].keys()
		# order regions by their earliest stretch stage, then name
		regions.sort_custom(func(a, b):
			var sa := _region_min_stage(by_act[act][a])
			var sb := _region_min_stage(by_act[act][b])
			if sa != sb:
				return sa < sb
			return str(a) < str(b))
		for region in regions:
			var region_node := order._make_node("region", str(region), {"region": str(region)})
			var summaries: Array = by_act[act][region]
			summaries.sort_custom(func(a, b):
				var pa := int(a.get("stage", 1))
				var pb := int(b.get("stage", 1))
				if pa != pb:
					return pa < pb
				var ea := _shelter_number(str(a.get("entry", "")))
				var eb := _shelter_number(str(b.get("entry", "")))
				if ea != eb:
					return ea < eb
				return str(a.get("spec_id", "")) < str(b.get("spec_id", "")))
			for s in summaries:
				region_node["children"].append(order._make_node("stretch", str(s.get("title", s.get("spec_id", "Stretch"))), {
					"spec_id": str(s.get("spec_id", "")),
					"entry": str(s.get("entry", "")),
					"exit": str(s.get("exit", "")),
					"stage": int(s.get("stage", 1)),
					"region": str(region),
					"branch": "main",
				}))
			act_node["children"].append(region_node)
		root["children"].append(act_node)
	return order


# --------------------------------------------------------------------- node ops

## Returns {node, parent, index} for an id, or {} if not found.
func locate(id: String) -> Dictionary:
	return _locate_in(root(), null, id)


func _locate_in(node: Dictionary, parent, target: String) -> Dictionary:
	if str(node.get("id", "")) == target:
		var idx := -1
		if parent != null:
			idx = (parent.get("children", []) as Array).find(node)
		return {"node": node, "parent": parent, "index": idx}
	for child in node.get("children", []):
		if child is Dictionary:
			var found := _locate_in(child, node, target)
			if not found.is_empty():
				return found
	return {}


## Add a new container/stretch under a parent. Stretch leaves can't take children.
func add_node(parent_id: String, kind: String, title: String, extra := {}) -> String:
	var loc := locate(parent_id)
	if loc.is_empty():
		return ""
	var parent: Dictionary = loc["node"]
	if str(parent.get("kind", "")) == KIND_STRETCH:
		return ""  # a stretch is a leaf
	var node := _make_node(kind, title, extra)
	parent["children"].append(node)
	return str(node["id"])


func remove_node(id: String) -> bool:
	var loc := locate(id)
	if loc.is_empty() or loc.get("parent") == null:
		return false  # can't remove the root
	var parent: Dictionary = loc["parent"]
	(parent["children"] as Array).erase(loc["node"])
	return true


func rename_node(id: String, title: String) -> bool:
	var loc := locate(id)
	if loc.is_empty():
		return false
	loc["node"]["title"] = title
	return true


func set_field(id: String, key: String, value) -> bool:
	var loc := locate(id)
	if loc.is_empty():
		return false
	loc["node"][key] = value
	return true


## Move a node to a new parent at an index (the drag-and-drop / reparent operation).
## Rejects moving a node into its own subtree or making a stretch a parent.
func move_node(id: String, new_parent_id: String, index := -1) -> bool:
	if id == new_parent_id:
		return false
	var loc := locate(id)
	var dest := locate(new_parent_id)
	if loc.is_empty() or dest.is_empty() or loc.get("parent") == null:
		return false
	var node: Dictionary = loc["node"]
	var dest_node: Dictionary = dest["node"]
	if str(dest_node.get("kind", "")) == KIND_STRETCH:
		return false  # can't nest under a stretch leaf
	if _is_descendant(node, new_parent_id) or str(node.get("id", "")) == new_parent_id:
		return false  # would create a cycle
	var old_parent: Dictionary = loc["parent"]
	(old_parent["children"] as Array).erase(node)
	var dest_children: Array = dest_node["children"]
	if index < 0 or index > dest_children.size():
		dest_children.append(node)
	else:
		dest_children.insert(index, node)
	return true


## Reorder a node among its siblings by delta (-1 up, +1 down).
func reorder_sibling(id: String, delta: int) -> bool:
	var loc := locate(id)
	if loc.is_empty() or loc.get("parent") == null:
		return false
	var siblings: Array = loc["parent"]["children"]
	var i := int(loc["index"])
	var j := clampi(i + delta, 0, siblings.size() - 1)
	if i == j:
		return false
	var node = siblings[i]
	siblings.remove_at(i)
	siblings.insert(j, node)
	return true


## Outdent: move a node up to become a sibling of its parent (right after it).
func outdent(id: String) -> bool:
	var loc := locate(id)
	if loc.is_empty() or loc.get("parent") == null:
		return false
	var parent: Dictionary = loc["parent"]
	var grand := locate(str(parent.get("id", "")))
	if grand.is_empty() or grand.get("parent") == null:
		return false  # parent is root; nothing to outdent into
	var grand_parent: Dictionary = grand["parent"]
	return move_node(id, str(grand_parent.get("id", "")), int(grand["index"]) + 1)


## Indent: nest a node under its immediately-preceding sibling.
func indent(id: String) -> bool:
	var loc := locate(id)
	if loc.is_empty() or loc.get("parent") == null:
		return false
	var siblings: Array = loc["parent"]["children"]
	var i := int(loc["index"])
	if i <= 0:
		return false
	var prev = siblings[i - 1]
	if not (prev is Dictionary) or str((prev as Dictionary).get("kind", "")) == KIND_STRETCH:
		return false
	return move_node(id, str((prev as Dictionary).get("id", "")), -1)


# -------------------------------------------------------------------- traversal

## All stretch leaves in depth-first (play) order.
func flatten_stretches() -> Array:
	var out := []
	_collect_stretches(root(), out)
	return out


func _collect_stretches(node: Dictionary, out: Array) -> void:
	if str(node.get("kind", "")) == KIND_STRETCH:
		out.append(node)
		return
	for child in node.get("children", []):
		if child is Dictionary:
			_collect_stretches(child, out)


func _is_descendant(node: Dictionary, target_id: String) -> bool:
	for child in node.get("children", []):
		if not (child is Dictionary):
			continue
		if str((child as Dictionary).get("id", "")) == target_id:
			return true
		if _is_descendant(child, target_id):
			return true
	return false


# ------------------------------------------------------------------- validation

## Validate the order: shelter connectivity along each chain, stage monotonicity,
## duplicate/orphaned/missing stretches. `known_spec_ids` (optional) flags references to
## specs that don't exist and stretches present on disk but absent from the tree.
func validate(known_spec_ids := []) -> Dictionary:
	var issues := []
	var stretches := flatten_stretches()
	var seen_specs := {}
	var entry_of := {}  # entry shelter -> [stretch]
	var exit_set := {}

	for st in stretches:
		var sid := str(st.get("spec_id", ""))
		if sid == "":
			issues.append(_issue("warning", "stretch_no_spec", "A stretch node has no spec_id.", st))
		else:
			if seen_specs.has(sid):
				issues.append(_issue("warning", "duplicate_stretch", "Stretch '%s' is placed more than once." % sid, st))
			seen_specs[sid] = true
			if not known_spec_ids.is_empty() and not known_spec_ids.has(sid):
				issues.append(_issue("error", "missing_spec", "Stretch references a spec that does not exist: %s" % sid, st))
		var entry := str(st.get("entry", ""))
		if entry != "":
			if not entry_of.has(entry):
				entry_of[entry] = []
			entry_of[entry].append(st)
		var ex := str(st.get("exit", ""))
		if ex != "":
			exit_set[ex] = true

	# Connectivity + stage monotonicity along the flattened chain.
	for i in range(stretches.size() - 1):
		var a: Dictionary = stretches[i]
		var b: Dictionary = stretches[i + 1]
		if str(a.get("exit", "")) != "" and str(b.get("entry", "")) != "" and str(a.get("exit", "")) != str(b.get("entry", "")):
			issues.append(_issue("warning", "shelter_gap", "Exit shelter '%s' of '%s' does not meet entry '%s' of '%s'." % [a.get("exit", ""), a.get("spec_id", a.get("id", "")), b.get("entry", ""), b.get("spec_id", b.get("id", ""))], b))
		if int(b.get("stage", 1)) < int(a.get("stage", 1)):
			issues.append(_issue("warning", "stage_regression", "Progression stage drops from %d to %d at '%s'." % [int(a.get("stage", 1)), int(b.get("stage", 1)), b.get("spec_id", b.get("id", ""))], b))

	# Fork detection (a branch): two stretches sharing an entry shelter.
	for entry in entry_of.keys():
		if (entry_of[entry] as Array).size() > 1:
			issues.append(_issue("info", "branch", "Branch: %d stretches start at shelter '%s'." % [(entry_of[entry] as Array).size(), entry], null))

	# Orphans: specs on disk not placed in the tree.
	for sid in known_spec_ids:
		if not seen_specs.has(str(sid)):
			issues.append(_issue("info", "orphan_spec", "Generated stretch not placed in the order: %s" % sid, null))

	var errors := 0
	var warnings := 0
	for it in issues:
		match str(it.get("severity", "")):
			"error":
				errors += 1
			"warning":
				warnings += 1
	return {
		"ok": errors == 0,
		"error_count": errors,
		"warning_count": warnings,
		"stretch_count": stretches.size(),
		"issues": issues,
	}


func _issue(severity: String, code: String, message: String, node) -> Dictionary:
	var out := {"severity": severity, "code": code, "message": message}
	if node is Dictionary:
		out["node_id"] = str((node as Dictionary).get("id", ""))
		out["spec_id"] = str((node as Dictionary).get("spec_id", ""))
	return out


# ---------------------------------------------------------------- serialization

func to_dict() -> Dictionary:
	return data.duplicate(true)


func from_dict(raw: Dictionary) -> void:
	data = raw.duplicate(true)
	if not data.has("schema"):
		data["schema"] = SCHEMA
	if not (data.get("root") is Dictionary):
		data["root"] = _make_node("campaign", "Campaign")
	# Repair ids / next_id so edits never collide, even on a hand-authored manifest.
	var max_seen := [0]
	_reid_pass(root(), max_seen, {})
	if int(data.get("next_id", 1)) <= max_seen[0]:
		data["next_id"] = max_seen[0] + 1


func _reid_pass(node: Dictionary, max_seen: Array, used: Dictionary) -> void:
	var id := str(node.get("id", ""))
	if id == "" or used.has(id):
		id = _alloc_id(str(node.get("kind", "node")))
		node["id"] = id
	used[id] = true
	var parts := id.split("_")
	if parts.size() > 0:
		var tail := int(parts[parts.size() - 1])
		max_seen[0] = maxi(max_seen[0], tail)
	if not (node.get("children") is Array):
		node["children"] = []
	for child in node.get("children", []):
		if child is Dictionary:
			_reid_pass(child, max_seen, used)


func to_json() -> String:
	return JSON.stringify(to_dict(), "\t")


static func from_json(text: String) -> CampaignOrder:
	var parsed: Variant = JSON.parse_string(text)
	return CampaignOrder.new(parsed if parsed is Dictionary else {})


# --------------------------------------------------------------- spec summaries

## Lightweight metadata for every generated spec in a directory (skips the replays
## subdir) — the index the Android "Add Stretch" tool and orphan-check read.
static func _load_spec_summaries(spec_dir: String) -> Array:
	var out := []
	var dir := DirAccess.open(spec_dir)
	if dir == null:
		return out
	var names := []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".json"):
			names.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for n in names:
		var spec := _load_json("%s/%s" % [spec_dir, n])
		if spec.is_empty():
			continue
		var slot: Dictionary = spec.get("world_slot", {})
		out.append({
			"spec_id": str(spec.get("id", n.get_basename())),
			"title": str(spec.get("title", n.get_basename())),
			"act": int(slot.get("act", 1)),
			"region": str(slot.get("region", "Unsorted")),
			"entry": str(slot.get("entry_shelter_id", "")),
			"exit": str(slot.get("exit_shelter_id", "")),
			"stage": int(spec.get("source", {}).get("progression_stage", 1)),
			"tier": str(spec.get("source", {}).get("complexity_tier", "")),
		})
	return out


static func spec_summaries(spec_dir: String) -> Array:
	return _load_spec_summaries(spec_dir)


static func _region_min_stage(summaries: Array) -> int:
	var m := 9999
	for s in summaries:
		m = mini(m, int(s.get("stage", 1)))
	return m


static func _shelter_number(shelter_id: String) -> int:
	var digits := ""
	for c in shelter_id:
		if c >= "0" and c <= "9":
			digits += c
	return int(digits) if digits != "" else 9999


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
