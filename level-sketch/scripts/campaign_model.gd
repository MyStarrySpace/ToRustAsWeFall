class_name CampaignModel
extends RefCounted

## The Android manager's copy of the campaign-order tree (campaign > act > region >
## group > stretch leaf). Mirrors the game's CampaignOrder JSON shape exactly so the
## manifest is interchangeable. Pure data: the manager UI calls these ops; the tree just
## reflects the result. Loads the bundled act1_order.json manifest and stretches_index.json.

const SCHEMA := "trawf_campaign_order_v1"
const CONTAINER_KINDS := ["campaign", "act", "region", "group"]
const KIND_STRETCH := "stretch"

var data: Dictionary = {}


func _init(initial := {}) -> void:
	if initial is Dictionary and not initial.is_empty():
		from_dict(initial)
	else:
		data = {"schema": SCHEMA, "title": "Campaign", "next_id": 1, "root": _make_node("campaign", "Campaign")}


func _make_node(kind: String, title: String, extra := {}) -> Dictionary:
	var node := {"id": _alloc_id(kind), "kind": kind, "title": title, "children": []}
	for key in extra.keys():
		node[key] = extra[key]
	return node


func _alloc_id(kind: String) -> String:
	var n := int(data.get("next_id", 1))
	data["next_id"] = n + 1
	return "%s_%03d" % [kind, n]


func root() -> Dictionary:
	return data.get("root", {})


func is_container(node: Dictionary) -> bool:
	return str(node.get("kind", "")) != KIND_STRETCH


# --------------------------------------------------------------------- node ops

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


func add_node(parent_id: String, kind: String, title: String, extra := {}) -> String:
	var loc := locate(parent_id)
	if loc.is_empty() or str(loc["node"].get("kind", "")) == KIND_STRETCH:
		return ""
	var node := _make_node(kind, title, extra)
	loc["node"]["children"].append(node)
	return str(node["id"])


func remove_node(id: String) -> bool:
	var loc := locate(id)
	if loc.is_empty() or loc.get("parent") == null:
		return false
	(loc["parent"]["children"] as Array).erase(loc["node"])
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


func move_node(id: String, new_parent_id: String, index := -1) -> bool:
	if id == new_parent_id:
		return false
	var loc := locate(id)
	var dest := locate(new_parent_id)
	if loc.is_empty() or dest.is_empty() or loc.get("parent") == null:
		return false
	var node: Dictionary = loc["node"]
	if str(dest["node"].get("kind", "")) == KIND_STRETCH:
		return false
	if _is_descendant(node, new_parent_id) or str(node.get("id", "")) == new_parent_id:
		return false
	(loc["parent"]["children"] as Array).erase(node)
	var dest_children: Array = dest["node"]["children"]
	if index < 0 or index > dest_children.size():
		dest_children.append(node)
	else:
		dest_children.insert(index, node)
	return true


func move_into(id: String, parent_id: String) -> bool:
	return move_node(id, parent_id, -1)


func move_before(id: String, target_id: String) -> bool:
	return _move_relative(id, target_id, 0)


func move_after(id: String, target_id: String) -> bool:
	return _move_relative(id, target_id, 1)


func _move_relative(id: String, target_id: String, offset: int) -> bool:
	if id == target_id:
		return false
	var src := locate(id)
	var tgt := locate(target_id)
	if src.is_empty() or tgt.is_empty() or src.get("parent") == null or tgt.get("parent") == null:
		return false
	var node: Dictionary = src["node"]
	if _is_descendant(node, target_id):
		return false
	(src["parent"]["children"] as Array).erase(node)
	var t2 := locate(target_id)
	var dest_children: Array = t2["parent"]["children"]
	dest_children.insert(clampi(int(t2["index"]) + offset, 0, dest_children.size()), node)
	return true


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


func outdent(id: String) -> bool:
	var loc := locate(id)
	if loc.is_empty() or loc.get("parent") == null:
		return false
	var grand := locate(str(loc["parent"].get("id", "")))
	if grand.is_empty() or grand.get("parent") == null:
		return false
	return move_node(id, str(grand["parent"].get("id", "")), int(grand["index"]) + 1)


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


func placed_spec_ids() -> Dictionary:
	var ids := {}
	for st in flatten_stretches():
		ids[str(st.get("spec_id", ""))] = true
	return ids


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

func validate(known_spec_ids := []) -> Dictionary:
	var issues := []
	var stretches := flatten_stretches()
	var seen := {}
	var entry_of := {}
	for st in stretches:
		var sid := str(st.get("spec_id", ""))
		if sid == "":
			issues.append(_issue("warning", "stretch_no_spec", "A stretch has no spec.", st))
		else:
			if seen.has(sid):
				issues.append(_issue("warning", "duplicate_stretch", "'%s' is placed more than once." % sid, st))
			seen[sid] = true
			if not known_spec_ids.is_empty() and not known_spec_ids.has(sid):
				issues.append(_issue("error", "missing_spec", "References a missing spec: %s" % sid, st))
		var entry := str(st.get("entry", ""))
		if entry != "":
			if not entry_of.has(entry):
				entry_of[entry] = 0
			entry_of[entry] += 1
	for i in range(stretches.size() - 1):
		var a: Dictionary = stretches[i]
		var b: Dictionary = stretches[i + 1]
		if str(a.get("exit", "")) != "" and str(b.get("entry", "")) != "" and str(a.get("exit", "")) != str(b.get("entry", "")):
			issues.append(_issue("warning", "shelter_gap", "%s exits at %s but %s enters at %s." % [a.get("title", ""), a.get("exit", ""), b.get("title", ""), b.get("entry", "")], b))
		if int(b.get("stage", 1)) < int(a.get("stage", 1)):
			issues.append(_issue("warning", "stage_regression", "Stage drops %d -> %d at %s." % [int(a.get("stage", 1)), int(b.get("stage", 1)), b.get("title", "")], b))
	for entry in entry_of.keys():
		if int(entry_of[entry]) > 1:
			issues.append(_issue("info", "branch", "Branch: %d stretches start at %s." % [int(entry_of[entry]), entry], null))
	for sid in known_spec_ids:
		if not seen.has(str(sid)):
			issues.append(_issue("info", "orphan_spec", "Not placed yet: %s" % sid, null))
	var errors := 0
	var warnings := 0
	for it in issues:
		match str(it.get("severity", "")):
			"error":
				errors += 1
			"warning":
				warnings += 1
	return {"ok": errors == 0, "error_count": errors, "warning_count": warnings, "stretch_count": stretches.size(), "issues": issues}


func _issue(severity: String, code: String, message: String, node) -> Dictionary:
	var out := {"severity": severity, "code": code, "message": message}
	if node is Dictionary:
		out["node_id"] = str((node as Dictionary).get("id", ""))
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
		max_seen[0] = maxi(max_seen[0], int(parts[parts.size() - 1]))
	if not (node.get("children") is Array):
		node["children"] = []
	for child in node.get("children", []):
		if child is Dictionary:
			_reid_pass(child, max_seen, used)


func to_json() -> String:
	return JSON.stringify(to_dict(), "\t")


static func from_json(text: String) -> CampaignModel:
	var parsed: Variant = JSON.parse_string(text)
	return CampaignModel.new(parsed if parsed is Dictionary else {})


# ------------------------------------------------------------- bundled file I/O

static func load_manifest(path: String) -> CampaignModel:
	return from_json(_read(path))


## The Add-Stretch palette source: [{spec_id, title, act, region, entry, exit, stage, tier}].
static func load_index(path: String) -> Array:
	var parsed: Variant = JSON.parse_string(_read(path))
	if parsed is Dictionary and (parsed as Dictionary).get("stretches") is Array:
		return (parsed as Dictionary)["stretches"]
	return []


static func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""
