extends Node

## Headless test runner for the data layer. Does nothing during normal use; pass
## `-- --test` to run:
##   Godot_v4.6.1-stable_win64_console.exe --headless --path level-sketch -- --test

var _passed := 0
var _failed := 0

func _ready() -> void:
	if not ("--test" in OS.get_cmdline_user_args() or "--test" in OS.get_cmdline_args()):
		return
	_run()
	print("\n[SketchTests] %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  PASS: %s" % label)
	else:
		_failed += 1
		print("  FAIL: %s" % label)

func _eq(a, b, label: String) -> void:
	_ok(a == b, "%s (got %s, want %s)" % [label, str(a), str(b)])

func _run() -> void:
	_test_cells()
	_test_rect_fill()
	_test_objects()
	_test_object_cover()
	_test_levels()
	_test_roundtrip()
	_test_height_tint()
	_test_load_id_dedup()
	_test_color_json_safe()
	_test_tint_floor_translucent()
	_test_history()
	_test_species_catalog()
	_test_replay_data()
	_test_campaign_model()
	_test_character_roster()

func _test_cells() -> void:
	var m := SketchModel.new()
	m.set_cell(2, 3, 0)
	_ok(m.has_cell(2, 3, 0), "cell placed")
	_ok(not m.has_cell(2, 3, 1), "cell is level-specific")
	_eq(str(m.get_cell(2, 3, 0).get("type", "")), "room", "cell default type is room")
	m.erase_cell(2, 3, 0)
	_ok(not m.has_cell(2, 3, 0), "cell erased")

func _test_rect_fill() -> void:
	var m := SketchModel.new()
	# Inclusive 3x2 rect = 6 cells; order of corners shouldn't matter.
	var n := m.fill_rect(5, 5, 3, 6, 0)
	_eq(n, 6, "fill_rect counts an inclusive rectangle")
	_ok(m.has_cell(3, 5, 0) and m.has_cell(5, 6, 0), "fill_rect covers both corners")
	_eq(m.erase_rect(3, 5, 4, 6, 0), 4, "erase_rect removes the overlap only")
	_ok(m.has_cell(5, 5, 0) and not m.has_cell(3, 5, 0), "erase_rect leaves cells outside it")

func _test_objects() -> void:
	var m := SketchModel.new()
	var id1 := m.add_object({"kind": SketchModel.KIND_FLORA, "x": 1, "y": 1, "level": 0})
	var id2 := m.add_object({"kind": SketchModel.KIND_SHELTER, "x": 4, "y": 4, "level": 0})
	_ok(id1 != id2, "objects get unique ids")
	_eq(m.objects.size(), 2, "two objects added")
	_eq(m.objects_on_level(0).size(), 2, "objects_on_level finds same-level objects")
	_eq(m.objects_on_level(1).size(), 0, "objects_on_level is level-specific")
	_ok(m.remove_object(id1), "object removed by id")
	_eq(m.objects.size(), 1, "one object remains")
	# Defaults fill in for a rect block-in.
	var rid := m.add_object({"kind": SketchModel.KIND_BLOCKIN, "shape": SketchModel.SHAPE_RECT, "x": 0, "y": 0, "w": 3, "h": 2})
	var ro := m.get_object(rid)
	_eq(int(ro.get("w", 0)), 3, "rect block-in keeps width")
	_eq(str(ro.get("layer", "")), SketchModel.LAYER_OBJECTS, "object defaults to the objects layer")

func _test_object_cover() -> void:
	var m := SketchModel.new()
	var rid := m.add_object({"kind": SketchModel.KIND_BLOCKIN, "shape": SketchModel.SHAPE_RECT, "x": 2, "y": 2, "w": 3, "h": 2, "level": 0})
	_ok(not m.object_at(2, 2, 0).is_empty(), "rect covers its origin corner")
	_ok(not m.object_at(4, 3, 0).is_empty(), "rect covers its far corner")
	_ok(m.object_at(5, 2, 0).is_empty(), "rect excludes the cell past its width")
	_ok(m.object_at(2, 2, 1).is_empty(), "rect cover is level-specific")
	var cid := m.add_object({"kind": SketchModel.KIND_BLOCKIN, "shape": SketchModel.SHAPE_CIRCLE, "x": 10, "y": 10, "r": 2.0, "level": 0})
	_ok(not m.object_at(10, 10, 0).is_empty(), "circle covers its centre")
	_ok(not m.object_at(11, 10, 0).is_empty(), "circle covers a cell within radius")
	_ok(m.object_at(13, 13, 0).is_empty(), "circle excludes a cell beyond radius")
	_ok(rid != cid, "rect and circle are distinct objects")

func _test_levels() -> void:
	var m := SketchModel.new()
	m.set_cell(0, 0, 0)
	m.set_cell(0, 0, 2)
	m.add_object({"kind": SketchModel.KIND_FLORA, "x": 0, "y": 0, "level": -1})
	_eq(m.used_levels(), [-1, 0, 2], "used_levels is sorted and de-duplicated across cells + objects")

func _test_roundtrip() -> void:
	var m := SketchModel.new()
	m.fill_rect(0, 0, 4, 4, 0)
	m.set_cell(0, 0, 1)
	m.add_object({"kind": SketchModel.KIND_SHELTER, "x": 2, "y": 2, "level": 0})
	m.add_object({"kind": SketchModel.KIND_BLOCKIN, "shape": SketchModel.SHAPE_CIRCLE, "x": 3, "y": 3, "r": 1.5, "level": 1})
	var restored := SketchModel.from_json(m.to_json())
	_eq(restored.cells.size(), m.cells.size(), "roundtrip preserves cell count")
	_eq(restored.objects.size(), m.objects.size(), "roundtrip preserves object count")
	_ok(restored.has_cell(0, 0, 1), "roundtrip preserves a level-1 cell")
	_ok(not restored.object_at(3, 3, 1).is_empty(), "roundtrip preserves a circle block-in's footprint")
	# A freshly added object after load must not reuse an existing id.
	var new_id := restored.add_object({"kind": SketchModel.KIND_FLORA, "x": 9, "y": 9})
	var ids := {}
	for obj in restored.objects:
		_ok(not ids.has(int(obj["id"])), "object id %s is unique after load" % str(obj["id"]))
		ids[int(obj["id"])] = true
	_ok(new_id > 0, "post-load add returns a fresh id")

func _test_height_tint() -> void:
	var base := Color(0.4, 0.7, 0.5, 1.0)
	_eq(SketchModel.height_tint(base, 0), base, "same-level content is untouched (opaque)")
	var above := SketchModel.height_tint(base, 2)
	var below := SketchModel.height_tint(base, -2)
	_ok(above.a < base.a and below.a < base.a, "off-level content fades")
	_ok(absf(above.a - below.a) < 0.0001, "fade depends on distance, not direction")
	# Above skews orange (more red than the base), below skews blue (more blue).
	_ok(above.r > base.r, "levels above skew warmer (orange)")
	_ok(below.b > base.b, "levels below skew cooler (blue)")
	var far := SketchModel.height_tint(base, 99)
	_ok(far.a >= SketchModel.TINT_ALPHA_FLOOR - 0.0001, "very distant levels never drop below the alpha floor")

func _test_load_id_dedup() -> void:
	var m := SketchModel.new()
	# A hand-edited save with out-of-order / non-positive / duplicate ids must load with
	# every object holding a unique id (the old running-max scheme collided).
	m.from_dict({"objects": [
		{"id": 2, "kind": "flora", "x": 0, "y": 0},
		{"id": 0, "kind": "flora", "x": 1, "y": 0},
		{"id": 3, "kind": "flora", "x": 2, "y": 0},
		{"id": 3, "kind": "flora", "x": 3, "y": 0},
	]})
	_eq(m.objects.size(), 4, "all objects load")
	var ids := {}
	var unique := true
	for obj in m.objects:
		if ids.has(int(obj["id"])):
			unique = false
		ids[int(obj["id"])] = true
	_ok(unique, "from_dict assigns unique ids despite collisions / non-positive ids")
	var nid := m.add_object({"kind": "flora", "x": 9, "y": 9})
	_ok(not ids.has(nid), "a fresh add after load does not collide with loaded ids")

func _test_color_json_safe() -> void:
	var m := SketchModel.new()
	m.add_object({"kind": SketchModel.KIND_BLOCKIN, "shape": SketchModel.SHAPE_RECT, "x": 0, "y": 0, "w": 1, "h": 1, "color": Color(1.0, 0.0, 0.0)})
	_ok(m.objects[0].get("color") is Array, "a Color is normalized to a [r,g,b] array")
	var restored := SketchModel.from_json(m.to_json())
	var rc = restored.objects[0].get("color")
	_ok(rc is Array and (rc as Array).size() >= 3, "color survives the JSON roundtrip as an array")
	if rc is Array and (rc as Array).size() >= 3:
		_ok(absf(float(rc[0]) - 1.0) < 0.001 and absf(float(rc[1])) < 0.001, "color channel values are preserved")

func _test_tint_floor_translucent() -> void:
	var base := Color(0.4, 0.6, 0.5, 0.5)
	var far := SketchModel.height_tint(base, 99)
	_ok(far.a <= base.a + 0.0001, "tinted alpha never exceeds the (translucent) base alpha")
	_ok(far.a >= minf(SketchModel.TINT_ALPHA_FLOOR, base.a) - 0.0001, "translucent base still respects the alpha floor")

func _test_history() -> void:
	var m := SketchModel.new()
	var h := SketchHistory.new(m)
	_ok(not h.can_undo() and not h.can_redo(), "fresh history has nothing to undo/redo")
	m.set_cell(1, 1, 0)
	h.commit()
	_ok(h.can_undo(), "after an edit + commit, undo is available")
	m.set_cell(2, 2, 0)
	h.commit()
	_eq(m.cells.size(), 2, "two cells placed")
	h.undo()
	_eq(m.cells.size(), 1, "undo removes the last edit")
	_ok(h.can_redo(), "redo is available after an undo")
	h.undo()
	_eq(m.cells.size(), 0, "undo back to the empty baseline")
	_ok(not h.can_undo(), "no further undo past the baseline")
	h.redo()
	_eq(m.cells.size(), 1, "redo restores the first edit")
	# A fresh edit after an undo truncates the redo branch.
	h.undo()
	m.add_object({"kind": "spikers", "x": 0, "y": 0})
	h.commit()
	_ok(not h.can_redo(), "a new edit after undo clears the redo branch")
	_eq(m.objects.size(), 1, "the new branch's edit is present")
	_ok(not h.commit(), "committing with no change records nothing")

func _test_species_catalog() -> void:
	_ok(SpeciesCatalog.all_flora().size() >= 8, "flora roster is populated")
	_ok(SpeciesCatalog.all_fauna().size() >= 13, "fauna roster covers the 13 enemies")
	_eq(SpeciesCatalog.category_of("seefern"), "flora", "seefern is flora")
	_eq(SpeciesCatalog.category_of("spikers"), "fauna", "spikers is fauna")
	_eq(SpeciesCatalog.category_of("shelter"), "", "non-species kinds have no category")
	_eq(SpeciesCatalog.display_name("forget_me_nots"), "Forget-me-nots", "display name resolves")
	# Every roster entry has a unique id and a real colour.
	var ids := {}
	for e in SpeciesCatalog.all_flora() + SpeciesCatalog.all_fauna():
		_ok(not ids.has(e["id"]), "species id %s is unique" % str(e["id"]))
		ids[e["id"]] = true
		_ok(e["color"] is Color, "species %s has a colour" % str(e["id"]))
	# A placed species keeps its id as the object kind and renders via the catalog.
	var m := SketchModel.new()
	var oid := m.add_object({"kind": "naturalizers", "x": 0, "y": 0, "level": 0})
	_eq(str(m.get_object(oid).get("kind")), "naturalizers", "placed species keeps its kind")
	var restored := SketchModel.from_json(m.to_json())
	_eq(str(restored.objects[0].get("kind")), "naturalizers", "species kind survives save/load")

func _test_replay_data() -> void:
	# The bundled generated-stretch replays load and interpolate the party over time.
	var samples := ReplayData.list_samples()
	_ok(samples.size() >= 1, "at least one bundled replay sample is present")
	if samples.is_empty():
		return
	var data := ReplayData.new()
	_ok(data.load_path(str(samples[0]["path"])), "a replay sample loads")
	var level := data.level()
	_ok((level.get("nodes", []) as Array).size() >= 2, "replay level has nodes")
	_ok((level.get("routes", []) as Array).size() >= 1, "replay level has routes")
	var solutions := data.solutions()
	_eq(solutions.size(), 2, "replay carries spotlight + shadow solutions")
	_ok(data.duration(0) > 0.0, "spotlight solution has a positive duration")
	# At t=0 the party sits at the first node; partway through it has moved.
	var start := data.characters_at(0, 0.0)
	_ok(start.size() >= 2, "characters are positioned at t=0")
	var mid := data.characters_at(0, data.duration(0) * 0.5)
	var moved := false
	for id in start.keys():
		if mid.has(id) and (start[id] as Vector2).distance_to(mid[id]) > 0.01:
			moved = true
	_ok(moved, "the party moves between t=0 and the midpoint")
	# The solved trail and caption grow with time.
	_ok(data.visited_nodes(0, 0.0).size() < data.visited_nodes(0, data.duration(0)).size(),
		"more nodes are solved by the end than at the start")
	_ok(str(data.frame_at(0, data.duration(0)).get("caption", "")) != "", "the final frame has a caption")
	# Spotlight and shadow diverge on at least one node's approach.
	var sh := {}
	for entry in (solutions[1] as Dictionary).get("node_approaches", []):
		sh[str(entry.get("node", ""))] = str(entry.get("approach_id", ""))
	var diverged := false
	for entry in (solutions[0] as Dictionary).get("node_approaches", []):
		var nid := str(entry.get("node", ""))
		var aid := str(entry.get("approach_id", ""))
		if aid != "" and sh.has(nid) and sh[nid] != aid:
			diverged = true
	_ok(diverged, "spotlight and shadow solutions differ on at least one node")

func _test_campaign_model() -> void:
	# The bundled campaign manifest + index load, and the model supports the tree edits
	# the manager UI drives (hierarchy, drag/reparent, validation, roundtrip).
	var index := CampaignModel.load_index("res://campaign/stretches_index.json")
	_ok(index.size() >= 1, "bundled stretches index loads")
	var manifest := CampaignModel.load_manifest("res://campaign/act1_order.json")
	_ok(manifest.flatten_stretches().size() >= 1, "bundled campaign manifest loads with stretches")

	var m := CampaignModel.new()
	var act := m.add_node(str(m.root()["id"]), "act", "Act 1")
	var region := m.add_node(act, "region", "Channels")
	var group := m.add_node(region, "group", "Sub-area")
	_ok(group != "", "multi-level hierarchy: group nests under region under act")
	var s1 := m.add_node(region, "stretch", "S1", {"spec_id": "s1", "entry": "shelter_1", "exit": "shelter_2", "stage": 1})
	var s2 := m.add_node(region, "stretch", "S2", {"spec_id": "s2", "entry": "shelter_2", "exit": "shelter_3", "stage": 2})
	_eq(m.add_node(s1, "group", "x"), "", "cannot nest under a stretch leaf")
	_eq(m.flatten_stretches().size(), 2, "two stretches placed")

	# Drag semantics: into / before / after, with cycle guard.
	_ok(m.move_into(s2, group), "move_into nests a stretch under a group")
	_eq(str(m.locate(s2)["parent"].get("id", "")), group, "moved stretch is now under the group")
	_ok(not m.move_into(region, group), "cannot move a container under its own descendant")
	_ok(m.move_before(group, s1), "move_before reorders a node ahead of a sibling")

	# Validation flags a stage regression + missing spec.
	var bad := CampaignModel.new()
	var r := bad.add_node(str(bad.root()["id"]), "region", "R")
	bad.add_node(r, "stretch", "A", {"spec_id": "a", "entry": "shelter_1", "exit": "shelter_2", "stage": 3})
	bad.add_node(r, "stretch", "B", {"spec_id": "ghost", "entry": "shelter_9", "exit": "shelter_9", "stage": 1})
	var rep := bad.validate(["a"])
	var codes := {}
	for it in rep.get("issues", []):
		codes[str(it.get("code", ""))] = true
	_ok(codes.has("stage_regression"), "validation flags a stage regression")
	_ok(codes.has("missing_spec"), "validation flags a missing-spec reference")
	_ok(int(rep.get("error_count", 0)) >= 1, "missing spec is an error")

	# JSON roundtrip preserves the tree.
	var restored := CampaignModel.from_json(m.to_json())
	_eq(restored.flatten_stretches().size(), m.flatten_stretches().size(), "roundtrip preserves stretch count")

	# id-repair: a manifest with duplicate + empty ids loads with unique ids.
	var dup := CampaignModel.new({"next_id": 1, "root": {"id": "campaign_001", "kind": "campaign", "title": "C", "children": [
		{"id": "region_001", "kind": "region", "title": "a", "children": []},
		{"id": "region_001", "kind": "region", "title": "b", "children": []},
		{"id": "", "kind": "region", "title": "c", "children": []}]}})
	var seen := {}
	var uniq := true
	var stk := [dup.root()]
	while not stk.is_empty():
		var n = stk.pop_back()
		var nid := str(n.get("id", ""))
		if nid == "" or seen.has(nid):
			uniq = false
		seen[nid] = true
		for c in n.get("children", []):
			stk.append(c)
	_ok(uniq, "id-repair yields unique ids for duplicate/empty input")

	# A stretch leaf with nested nodes is flagged.
	var lf := CampaignModel.new({"root": {"id": "campaign_001", "kind": "campaign", "title": "C", "children": [
		{"id": "stretch_001", "kind": "stretch", "title": "S", "spec_id": "s", "children": [
			{"id": "stretch_002", "kind": "stretch", "title": "n", "spec_id": "n", "children": []}]}]}})
	var lc := {}
	for it in lf.validate([]).get("issues", []):
		lc[str(it.get("code", ""))] = true
	_ok(lc.has("leaf_has_children"), "a stretch leaf with nested nodes is flagged")

func _test_character_roster() -> void:
	# The cast mirrors the game roster, with enable/disable that changes the combat capability.
	_eq(CharacterRoster.CHARACTERS.size(), 6, "six characters in the cast")
	_eq(CharacterRoster.default_enabled().size(), 6, "all six enabled by default")
	_ok(CharacterRoster.always_on("aster") and CharacterRoster.always_on("peris"), "the minimum pair is permanent")
	_ok(not CharacterRoster.always_on("myke"), "Myke is toggleable")
	_ok(CharacterRoster.has_combat(CharacterRoster.default_enabled()), "the full cast fields a combat specialist")
	_ok(not CharacterRoster.has_combat(["aster", "peris", "endo"]), "without Myke/Tyreg there is no combat specialist")
	_ok(CharacterRoster.enabled_capabilities(["aster", "peris"]).has("flora"), "the pair still provides flora/cover")
	# Save/load roundtrip, then restore the default.
	CharacterRoster.save_enabled(["aster", "peris", "endo"])
	var loaded := CharacterRoster.load_enabled()
	_ok(loaded.has("endo") and not loaded.has("myke"), "a saved roster (no Myke) round-trips")
	_ok(loaded.has("aster") and loaded.has("peris"), "load always keeps the minimum pair")
	CharacterRoster.save_enabled(CharacterRoster.default_enabled())
