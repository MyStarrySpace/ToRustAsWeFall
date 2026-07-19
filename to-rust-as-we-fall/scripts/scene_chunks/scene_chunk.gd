class_name SceneChunk
extends Node3D

const INTERACTABLE_SCENE := preload("res://scenes/game/interactable.tscn")
const CAUSAL_FEEDBACK_LINK_SCRIPT := preload("res://scripts/game/world/causal_feedback_link.gd")

var host: Node = null
var chunk_name := ""
var _built := false
var _interactables: Array = []
var _causal_feedback_links: Array = []
var _causal_feedback_wired := false

func attach_chunk_host(next_host: Node, next_chunk_name := "") -> void:
	host = next_host
	if next_chunk_name != "":
		chunk_name = next_chunk_name

func detach_chunk_host() -> void:
	host = null
	_interactables.clear()
	for link in _causal_feedback_links:
		if link != null and is_instance_valid(link):
			link.call("set_source_hovered", false)
			link.call("set_planning_active", false)
			link.call("set_latched", false)
	_causal_feedback_links.clear()

func configure_chunk(_config: Dictionary) -> void:
	pass

func _ready() -> void:
	if _built:
		return
	_built = true
	_build_chunk()

func _build_chunk() -> void:
	pass

func get_scene_title() -> String:
	if chunk_name != "":
		return chunk_name.capitalize()
	return name

func get_scene_help() -> String:
	return ""

func get_default_character() -> String:
	return "aster"

func get_spawn_positions() -> Dictionary:
	return {}

func get_preview_anchors() -> Dictionary:
	return get_spawn_positions()

func get_preview_character_state() -> Dictionary:
	return {}

## Per-character party presence at this story beat, read from a PartyPresence child
## node if one is present. Empty => no override (host keeps its full roster).
func get_party_presence() -> Dictionary:
	for child in get_children():
		if child is PartyPresence:
			return (child as PartyPresence).presence_map()
	return {}

func get_preview_time_state() -> Dictionary:
	return {}

func get_preview_abilities() -> Array:
	return []

func get_world_slot() -> Dictionary:
	return {}

func get_preview_state() -> Dictionary:
	return {}

func update_preview_overlay_states(_overlay_states: Dictionary, _current_tick: float, _delta: float) -> void:
	pass

func get_preview_overlay_status(_overlay_id: String, _current_tick: float) -> Array:
	return []

func reset_preview_state() -> void:
	pass

func headless_process(_delta: float) -> void:
	pass

func handle_preview_ability(_ability_id: String, _ability: Dictionary = {}) -> Dictionary:
	return {}

func on_preview_character_selected(_char_id: String) -> void:
	pass

func on_preview_routing_changed(_mode: String) -> void:
	pass

func _dialogue_box() -> Node:
	if host != null and host.has_method("get_preview_dialogue_box"):
		return host.call("get_preview_dialogue_box")
	return null

func _engram_overlay() -> Node:
	if host != null and host.has_method("get_preview_engram_overlay"):
		return host.call("get_preview_engram_overlay")
	return null

func _show_note(text: String, duration := 3.0) -> void:
	if host != null and host.has_method("show_preview_note"):
		host.call("show_preview_note", text, duration)

func _show_message(text: String, duration := 2.0) -> void:
	if host != null and host.has_method("show_preview_message"):
		host.call("show_preview_message", text, duration)

func _set_preview_step(step: String) -> void:
	if host != null and host.has_method("set_preview_step"):
		host.call("set_preview_step", step)

## Preview-only continuation hook. Campaign/tutorial hosts deliberately need not
## implement it, so a chunk can offer a seamless lab handoff without changing
## runtime progression ownership.
func _request_preview_handoff(entry_id: String) -> void:
	if host != null and host.has_method("request_preview_handoff"):
		host.call("request_preview_handoff", entry_id)

func _get_character_position(char_id: String) -> Vector3:
	if host != null and host.has_method("get_preview_character_position"):
		return host.call("get_preview_character_position", char_id)
	return Vector3.ZERO

func _get_character_move_speed(char_id: String, running := false) -> float:
	if host != null and host.has_method("get_preview_character_move_speed"):
		return float(host.call("get_preview_character_move_speed", char_id, running))
	return 3.0

func _set_character_position(char_id: String, position: Vector3) -> void:
	if host != null and host.has_method("set_preview_character_position"):
		host.call("set_preview_character_position", char_id, position)

func _get_active_character() -> String:
	if host != null and host.has_method("get_preview_active_character"):
		return str(host.call("get_preview_active_character"))
	return ""

func _get_character_stat(char_id: String, stat_name: String) -> float:
	if host != null and host.has_method("get_preview_character_stat"):
		return float(host.call("get_preview_character_stat", char_id, stat_name))
	return 0.0

func _set_character_stat(char_id: String, stat_name: String, value: float) -> void:
	if host != null and host.has_method("set_preview_character_stat"):
		host.call("set_preview_character_stat", char_id, stat_name, value)

func _adjust_character_stat(char_id: String, stat_name: String, delta: float) -> void:
	if host != null and host.has_method("adjust_preview_character_stat"):
		host.call("adjust_preview_character_stat", char_id, stat_name, delta)

func _set_character_status(char_id: String, status: String) -> void:
	if host != null and host.has_method("set_preview_character_status"):
		host.call("set_preview_character_status", char_id, status)

func _set_character_visible(char_id: String, visible: bool) -> void:
	if host != null and host.has_method("set_preview_character_visible"):
		host.call("set_preview_character_visible", char_id, visible)

func _set_ability_state(ability_id: String, state: String, remaining := 0.0) -> void:
	if host != null and host.has_method("set_preview_ability_state"):
		host.call("set_preview_ability_state", ability_id, state, remaining)

func _get_routing_mode() -> String:
	if host != null and host.has_method("get_preview_routing_mode"):
		return str(host.call("get_preview_routing_mode"))
	return "safe"

func _spawn_item(item_type: String, position: Vector3, properties: Dictionary = {}) -> String:
	if host != null and host.has_method("spawn_preview_item"):
		return str(host.call("spawn_preview_item", item_type, position, properties))
	return ""

func _remove_item(item_id: String) -> void:
	if host != null and host.has_method("remove_preview_item"):
		host.call("remove_preview_item", item_id)

func _pick_up_item(char_id: String, item_id: String) -> bool:
	if host != null and host.has_method("pick_up_preview_item"):
		return bool(host.call("pick_up_preview_item", char_id, item_id))
	return false

func _drop_item(char_id: String, item_id: String) -> bool:
	if host != null and host.has_method("drop_preview_item"):
		return bool(host.call("drop_preview_item", char_id, item_id))
	return false

func _transfer_item(from_id: String, to_id: String, item_id: String) -> bool:
	if host != null and host.has_method("transfer_preview_item"):
		return bool(host.call("transfer_preview_item", from_id, to_id, item_id))
	return false

func _endocytose_item(char_id: String, item_id: String) -> bool:
	if host != null and host.has_method("endocytose_preview_item"):
		return bool(host.call("endocytose_preview_item", char_id, item_id))
	return false

func _exocytose_item(char_id: String, item_id: String) -> bool:
	if host != null and host.has_method("exocytose_preview_item"):
		return bool(host.call("exocytose_preview_item", char_id, item_id))
	return false

func _get_hand_items(char_id: String) -> Array:
	if host != null and host.has_method("get_preview_hand_items"):
		return host.call("get_preview_hand_items", char_id)
	return []

func _get_hand_slots(char_id: String) -> Array:
	if host != null and host.has_method("get_preview_hand_slots"):
		return host.call("get_preview_hand_slots", char_id)
	return []

func _get_internal_items(char_id: String) -> Array:
	if host != null and host.has_method("get_preview_internal_items"):
		return host.call("get_preview_internal_items", char_id)
	return []

func _get_item_state(item_id: String) -> Dictionary:
	if host != null and host.has_method("get_preview_item_state"):
		var state: Variant = host.call("get_preview_item_state", item_id)
		return state if state is Dictionary else {}
	return {}

func _get_item_display_name(item_id: String, char_id := "") -> String:
	if host != null and host.has_method("get_preview_item_display_name"):
		return str(host.call("get_preview_item_display_name", item_id, char_id))
	return item_id

func _get_collection_items() -> Array:
	if host != null and host.has_method("get_preview_collection_items"):
		return host.call("get_preview_collection_items")
	return []

func _get_scheduler_tick() -> float:
	if host != null and host.has_method("get_preview_scheduler_tick"):
		return float(host.call("get_preview_scheduler_tick"))
	return 0.0

func _get_game_state():
	if host != null and host.has_method("get_preview_game_state"):
		return host.call("get_preview_game_state")
	return null

func _get_scheduler():
	if host != null and host.has_method("get_preview_scheduler"):
		return host.call("get_preview_scheduler")
	return null

## Registry id for a chunk interactable: namespaced by chunk so two chunks sharing
## an authored node name can't collide in GameState. The scene-tree node keeps the
## authored name (tests / lookups match on it); only the data id is namespaced.
func _interactable_data_id(node_name: String) -> String:
	if chunk_name == "":
		return node_name
	return "%s_%s" % [chunk_name, node_name]

func _clear_dialogue() -> void:
	var dialogue_box: Node = _dialogue_box()
	if dialogue_box != null and dialogue_box.has_method("clear"):
		dialogue_box.call("clear")

func _say(text: String, speaker := "", style := "normal", wait := false) -> void:
	var dialogue_box: Node = _dialogue_box()
	if dialogue_box != null and dialogue_box.has_method("say"):
		dialogue_box.call("say", text, speaker, style, wait)

func _say_key(key: String) -> void:
	var dialogue_box: Node = _dialogue_box()
	if dialogue_box == null or not dialogue_box.has_method("say") or key == "":
		return
	var line := DialogueData.get_line(key)
	dialogue_box.call("say", line.text, line.speaker, line.style, line.wait)

func _register_interactable(interactable: Node) -> void:
	_interactables.append(interactable)
	if host != null and host.has_method("register_preview_interactable"):
		host.call("register_preview_interactable", interactable)

## When a scene's data layer is FLAT but its world is WARPED (a coord_map is installed — e.g. the channels
## helix), the interactable proximity zones have to move onto the warped deck too. A character body renders
## at its WARPED world position, so a zone left at its flat authored position would never overlap it — the
## hold-dwell (which arms on Area3D body-enter) could never fire. This repositions every registered
## interactable's Area3D through the map. Idempotent: each remembers its FLAT authored position, so a
## re-warp (or a swapped map) always re-derives from the original instead of compounding. The data-layer
## interactable spec keeps its flat position (triggering checks character/enabled, never world distance),
## and a click still maps back through the map to a flat move target, so navigation stays in the flat frame.
func warp_interactables_onto_coord_map(coord_map) -> void:
	if coord_map == null:
		return
	for it in _interactables:
		if not is_instance_valid(it) or not (it is Node3D):
			continue
		if not it.has_meta("flat_authored_position"):
			it.set_meta("flat_authored_position", it.global_position)
		it.global_position = coord_map.to_world(it.get_meta("flat_authored_position"))
		# The interactable's linked outline target (the pickable hull + glow shells) lives under the CHUNK
		# ROOT, not under `it`, so it isn't in _interactables and wouldn't be warped — it'd stay flat off the
		# deck, breaking hover + the queued-glow origin on the helix. Carry it onto the deck too. (Skip a
		# target that's a descendant of `it`: it already rides `it`'s move.)
		var tgt = it.get("_outline_target") if ("_outline_target" in it) else null
		if tgt != null and is_instance_valid(tgt) and (tgt is Node3D) and not it.is_ancestor_of(tgt):
			if not tgt.has_meta("flat_authored_position"):
				tgt.set_meta("flat_authored_position", tgt.global_position)
			tgt.global_position = coord_map.to_world(tgt.get_meta("flat_authored_position"))

func _make_material(
	color: Color,
	emission := Color.BLACK,
	emission_energy := 0.0,
	transparency := BaseMaterial3D.TRANSPARENCY_DISABLED
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = transparency
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	return material

const TILE_DIR := "res://resources/models/elevator/tiles/"
const SKIRT_GRIME_SHADER := preload("res://resources/tile_grime.gdshader")
var _skirt_mat_cache: Dictionary = {}

## THE DISTRICT SKIRT: wrap this chunk's play space in the connective-fabric economy
## (ARCHITECTURE_DESIGN.md §4.18-4.24) so a generated level reads as streets cut through an
## inhabited intermediate zone instead of a room on a void. The chunk's grid becomes the street
## set of a synthetic fragment expanded by a margin ring; BuildingFiller packs the ring (program
## buildings, props, viaduct skyline — landmarks off by default), and the output renders here.
## The filler's own reservation grid + audit keep every box out of the play columns.
func _build_district_skirt(grid_data: Dictionary, seed_v: int, margin := 6, filler_opts: Dictionary = {}) -> Dictionary:
	var cs := float(grid_data.get("cell_size", 1.5))
	var org: Array = grid_data.get("origin", [0.0, 0.0, 0.0])
	var w := int(grid_data.get("width", 0))
	var h := int(grid_data.get("height", 0))
	if w <= 0 or h <= 0:
		return {}
	var synth := Fragment.new()
	var cells: Array = []
	for c in grid_data.get("walkable_cells", []):
		cells.append([int(c[0]) + margin, int(c[1]) + margin])
	synth.grid = {"contract_id": "unified_grid_v1", "cell_size": cs,
		"origin": [float(org[0]) - float(margin) * cs, 0.0, float(org[2]) - float(margin) * cs],
		"width": w + margin * 2, "height": h + margin * 2, "walkable_cells": cells}
	var opts := filler_opts.duplicate(true)
	if not opts.has("landmarks"):
		opts["landmarks"] = false
	var stats: Dictionary = BuildingFiller.fill(synth, seed_v, opts)
	# the skirt ground: a darker apron under the ring, its top just below the play floors
	var ww := float(w + margin * 2) * cs
	var hh := float(h + margin * 2) * cs
	_add_box(self, Vector3(float(org[0]) - float(margin) * cs + ww * 0.5, -0.08,
		float(org[2]) - float(margin) * cs + hh * 0.5), Vector3(ww, 0.1, hh), Color(0.055, 0.06, 0.065))
	for wb in synth.walls:
		var wd := wb as Dictionary
		var box := _add_box(self, wd.get("pos", Vector3.ZERO), wd.get("size", Vector3.ONE),
			wd.get("color", Color(0.1, 0.1, 0.11)), wd.get("emission", Color.BLACK),
			float(wd.get("energy", 0.0)))
		if str(wd.get("tile", "")) != "":
			box.material_override = _skirt_tile_material(str(wd["tile"]), wd.get("color", Color.WHITE))
	for lt in synth.lights:
		var ld := lt as Dictionary
		_add_light(self, ld.get("pos", Vector3.ZERO), ld.get("color", Color.WHITE),
			float(ld.get("energy", 1.0)), float(ld.get("range", 8.0)))
	for lp in (stats.get("lathes", []) as Array):
		_skirt_lathe(lp as Dictionary)
	return stats

## SILO DROP CHUTES (SET_PIECES.md #26): vented stockpiles this chunk hosts.
var _silos: Array = []
## EXTRACTION BORE SUMPS (SET_PIECES.md #27): reversible wellhead-pump sumps this chunk hosts.
var _sumps: Array = []

## An EXTRACTION BORE SUMP (SET_PIECES.md #27): the decommissioned siphon well as a REVERSIBLE
## water-height set piece (the water family, extraction-reflavored). CONTROL: the wellhead pump
## lever, placed apart. EFFECT cycles DRAINED -> MID -> FLOODED on a scheduled beat: DRAINED opens
## the pit floor so you can climb down for the salvage under the wall; FLOODED seals the pit,
## raises the float platform into a LEDGE link (a climb to a vantage), and DROWNS whatever is
## penned in the pit; MID is neither. Fully reversible — flood then drain and the ledge is gone,
## the pit open again (unlike the one-shot silo/belt). Owns its penned scrap, so it drowns in any
## host. Two-read: a resource bore AND a CSF siphon site.
func _spawn_sump(spec: Dictionary) -> void:
	var idx := _sumps.size()
	var pos: Vector3 = spec.get("pos", Vector3.ZERO)
	var pit_min: Vector3 = spec.get("pit_min", pos + Vector3(-1.5, 0, -1.5))
	var pit_max: Vector3 = spec.get("pit_max", pos + Vector3(1.5, 0, 1.5))
	var pit_c := (pit_min + pit_max) * 0.5
	var pit_cells: Array = spec.get("pit_cells", [])
	var ledge_cell: Array = spec.get("ledge_cell", [])
	var ledge_level := int(spec.get("ledge_level", 1))
	# the wellhead casing + rim
	for t in range(2):
		_add_box(self, pos + Vector3(0, 0.6 + 1.1 * float(t), 0),
			Vector3(2.6 - 0.5 * float(t), 1.1, 2.6 - 0.5 * float(t)),
			Color(0.15, 0.16, 0.15).darkened(0.03 * float(t)))
	_add_box(self, Vector3(pit_c.x, -0.35, pit_c.z),
		Vector3(pit_max.x - pit_min.x + 0.4, 0.5, pit_max.z - pit_min.z + 0.4), Color(0.08, 0.09, 0.1))
	_add_label(self, str(spec.get("label_text", "BORE %d — SIPHON DECOMMISSIONED" % (idx + 1))),
		pos + Vector3(0, 3.0, 0), Color(0.5, 0.62, 0.6))
	# the salvage under the wall (reachable ONLY when drained — an INSPECTION reward in the pit)
	var salvage := _add_interactable(self, "SumpSalvage%d" % idx, "Lift the wellhead cache",
		Vector3(pit_c.x, 0.1, pit_c.z), "SALVAGE", "", 1.0, true, 1.4,
		Interactable.InteractableType.INSPECTION, false)
	var salv_m := _add_box(salvage, Vector3(0, 0.2, 0), Vector3(0.5, 0.4, 0.5),
		Color(0.24, 0.2, 0.12), Color(0.85, 0.6, 0.25), 0.6)
	_outline_interactable_child(salvage, salv_m, "SumpSalvage%d" % idx, 1.4)
	# the water plane (cosmetic; the logical water is the state) + the float platform
	var water := _add_box(self, Vector3(pit_c.x, -0.05, pit_c.z),
		Vector3(pit_max.x - pit_min.x, 0.12, pit_max.z - pit_min.z),
		Color(0.16, 0.28, 0.34), Color(0.2, 0.5, 0.6), 0.35, "SumpWater%d" % idx)
	water.visible = false
	var plat := _add_box(self, Vector3(pit_c.x, 0.05, pit_c.z), Vector3(1.6, 0.24, 1.6),
		Color(0.4, 0.34, 0.22), Color.BLACK, 0.0, "SumpPlatform%d" % idx)
	# the CONTROL: the wellhead pump lever, placed apart
	var pump := _add_interactable(self, "SumpPump%d" % idx, "Work the wellhead pump",
		spec.get("pump_pos", pos + Vector3(3.0, 0, 0)), "PUMP", "", 1.4, false, 1.6,
		Interactable.InteractableType.TIMED_ACTION, false)
	var pump_m := _add_box(pump, Vector3(0, 0.55, 0), Vector3(0.35, 1.1, 0.35),
		Color(0.2, 0.36, 0.42), Color(0.3, 0.7, 0.85), 0.5)
	_outline_interactable_child(pump, pump_m, "SumpPump%d" % idx, 1.6)
	# the penned scrap (drowns at FLOOD) — the sump owns it, so the drown lands in any host
	var pen = null
	if bool(spec.get("pit_enemy", true)):
		var gs0 = _get_game_state()
		if gs0 != null:
			pen = Enemy.new()
			pen.name = "SumpScrap%d" % idx
			pen.position = Vector3(pit_c.x, 0.4, pit_c.z)
			pen.scale = Vector3.ONE * 0.6
			pen.color = Color(0.4, 0.2, 0.12)
			pen.move_speed = 1.6
			pen.detection_range = 0.0
			add_child(pen)
			pen.char_id = "sump_scrap_%d" % idx
			pen.game_state = gs0
			gs0.register_character(pen.char_id, pen.position, pen.move_speed, {})
			if gs0.has_method("set_coop_exempt"):
				gs0.set_coop_exempt(pen.char_id)
			pen.activate()
			pen.set_roam(Vector3(pit_c.x, 0.0, pit_c.z), 1.0)
	var entry := {"state": 1, "pending": -1, "pit_cells": pit_cells, "ledge_cell": ledge_cell,
		"ledge_level": ledge_level, "water": water, "plat": plat, "pit_c": pit_c,
		"pen": pen, "salvage": salvage, "idx": idx}
	_sumps.append(entry)
	pump.interacted.connect(func() -> void: _on_sump_pumped(idx))
	# the live grid is assigned by the host AFTER _build_chunk, so apply the initial MID state
	# deferred (by which point _game_state.grid exists); the visual apply is idempotent
	call_deferred("_apply_sump", idx)

func _on_sump_pumped(idx: int) -> void:
	var sched = _get_scheduler()
	if sched == null or idx >= _sumps.size():
		return
	var entry := _sumps[idx] as Dictionary
	if int(entry["pending"]) >= 0:
		return
	entry["pending"] = (int(entry["state"]) + 1) % 3
	_show_note(["The pump draws the bore down—", "The level settles—", "The bore floods back up—"][int(entry["pending"])], 1.4)
	sched.schedule_after(1.2, func() -> void: _commit_sump(idx), "sump_%d" % idx)

func _commit_sump(idx: int) -> void:
	var entry := _sumps[idx] as Dictionary
	if int(entry["pending"]) < 0:
		return
	entry["state"] = int(entry["pending"])
	entry["pending"] = -1
	_apply_sump(idx)
	# the DROWN: flooding takes whatever is penned in the pit (analytic, at the commit tick)
	if int(entry["state"]) == 2:
		var pen = entry["pen"]
		if pen != null and is_instance_valid(pen) and pen.is_alive():
			var gs = _get_game_state()
			if gs != null:
				gs.command_stop(pen.char_id)
			pen.take_damage(float(pen.max_hp))

## DRAINED(0): pit floor walkable (climb down for the salvage), ledge down. MID(1): sealed, neither.
## FLOODED(2): pit sealed (water), the ledge LINK up, salvage locked. Reversible each commit.
func _apply_sump(idx: int) -> void:
	var entry := _sumps[idx] as Dictionary
	var st := int(entry["state"])
	var gs = _get_game_state()
	var drained := st == 0
	var flooded := st == 2
	# pit floor: a walkable trough only when drained (blocked at MID/FLOOD)
	if gs != null and gs.grid != null:
		for c in (entry["pit_cells"] as Array):
			var cell := Vector2i(int(c[0]), int(c[1]))
			if drained:
				gs.grid.remove_dynamic_blocker(cell)
			else:
				gs.grid.add_dynamic_blocker(cell, "sump_%d" % idx)
		# the ledge LINK: the risen platform is a climb up, only while flooded (reversible)
		var lc: Array = entry["ledge_cell"]
		if lc.size() == 2 and gs.grid.has_method("add_inter_level_link"):
			var lcell := Vector2i(int(lc[0]), int(lc[1]))
			var lvl := int(entry["ledge_level"])
			if flooded:
				# the ledge must be a REAL floor the router can reach: raise the grid's level
				# count so find_multi_level_path/links_from surface the new link (single-level
				# atom grids default to count 1)
				if gs.grid.has_method("set_level_count"):
					gs.grid.set_level_count(maxi(gs.grid.level_count, lvl + 1))
				gs.grid.add_inter_level_link(lcell, 0, lvl, "ramp")
			elif gs.grid.has_method("remove_inter_level_link"):
				gs.grid.remove_inter_level_link(lcell, 0, lvl)
	# the salvage is grabbable only when the pit is drained and open
	var salv = entry["salvage"]
	if salv != null and is_instance_valid(salv) and gs != null:
		gs.set_interactable_enabled(_interactable_data_id(str(salv.name)), drained)
	# cosmetic: water shows when not drained, rises at flood; the platform lifts to the ledge
	var water = entry["water"]
	if water != null and is_instance_valid(water):
		water.visible = not drained
		var wy := 0.35 if flooded else -0.05
		water.position.y = wy
	var plat = entry["plat"]
	if plat != null and is_instance_valid(plat):
		plat.position.y = 1.4 if flooded else (0.05 if not drained else -0.35)

## A DERELICT RESOURCE BELT (SET_PIECES.md #25

## A SILO DROP CHUTE (SET_PIECES.md #26): the between-zone stockpile as a set piece. CONTROL: a
## vent-hatch lever placed apart. EFFECT (one scheduled beat after the pull, the weak-wall law —
## analytic, never per-frame): the hoard avalanches — anything GROUND-LEVEL standing in the spill
## rect is buried (enemies die, a party member is hurt but never killed: fail-forward), and the
## scree piles into a climbable RAMP (a runtime ramp link up to `ramp_to_level` at `ramp_cell`).
## Two-read: a grain silo AND a ferritin store voiding its sequestered iron.
func _spawn_silo(spec: Dictionary) -> void:
	var idx := _silos.size()
	var pos: Vector3 = spec.get("pos", Vector3.ZERO)
	var spill_min: Vector3 = spec.get("spill_min", pos + Vector3(-1.5, 0, -1.5))
	var spill_max: Vector3 = spec.get("spill_max", pos + Vector3(1.5, 0, 1.5))
	var spill_c := (spill_min + spill_max) * 0.5
	# the silo drum: three shrinking tiers + the chute mouth aimed at the spill
	var tier_r := [1.5, 1.3, 1.05]
	for t in range(3):
		_add_box(self, pos + Vector3(0, 1.0 + 2.0 * float(t), 0),
			Vector3(float(tier_r[t]) * 2.0, 2.0, float(tier_r[t]) * 2.0),
			Color(0.16, 0.15, 0.14).darkened(0.04 * float(t)))
	_add_box(self, pos + Vector3(0, 6.3, 0), Vector3(1.6, 0.5, 1.6), Color(0.12, 0.11, 0.1))
	var chute_dir := (Vector3(spill_c.x, 0, spill_c.z) - Vector3(pos.x, 0, pos.z)).normalized()
	var chute_p := pos + chute_dir * 1.6 + Vector3(0, 1.3, 0)
	_add_box(self, chute_p, Vector3(0.9, 0.9, 0.9), Color(0.13, 0.12, 0.11))
	_add_box(self, chute_p + chute_dir * 0.5 - Vector3(0, 0.55, 0), Vector3(0.7, 0.2, 0.7),
		Color(0.1, 0.09, 0.08))
	# a stock glint at the throat — the hoard is still in there
	_add_box(self, pos + Vector3(0, 5.2, 0) + chute_dir * (float(tier_r[0]) - 0.1),
		Vector3(0.5, 0.3, 0.12) if absf(chute_dir.x) < 0.5 else Vector3(0.12, 0.3, 0.5),
		Color(0.2, 0.14, 0.08), Color(0.85, 0.55, 0.2), 0.5)
	_add_label(self, str(spec.get("label_text", "STORE SILO %d — SEALED" % (idx + 1))),
		pos + Vector3(0, 7.2, 0), Color(0.6, 0.55, 0.48))
	# the scree ramp (revealed on vent): stepped facets from the chute foot up to the ramp top
	var ramp_root := Node3D.new()
	ramp_root.name = "SiloScree%d" % idx
	add_child(ramp_root)
	var ramp_top: Vector3 = spec.get("ramp_top", spill_c + Vector3(0, 2.0, 0))
	var foot := Vector3(spill_c.x, 0.0, spill_c.z)
	var steps := 5
	for st in range(steps):
		var t2 := (float(st) + 0.5) / float(steps)
		var sp := foot.lerp(Vector3(ramp_top.x, 0.0, ramp_top.z), t2)
		var sh := maxf(ramp_top.y * t2, 0.25)
		ramp_root.add_child(_scree_box(sp, sh, 1.7 - t2 * 0.5))
	ramp_root.visible = false
	# the CONTROL: the vent-hatch lever, apart from the spill
	var lever := _add_interactable(self, "SiloVent%d" % idx, "Vent the silo hatch",
		spec.get("lever_pos", pos + Vector3(2.0, 0, 2.0)), "VENT HATCH", "", 1.4, true, 1.6,
		Interactable.InteractableType.TIMED_ACTION)
	var lever_m := _add_box(lever, Vector3(0, 0.55, 0), Vector3(0.3, 1.1, 0.3),
		Color(0.34, 0.28, 0.2), Color(0.85, 0.55, 0.2), 0.4)
	_outline_interactable_child(lever, lever_m, "SiloVent%d" % idx, 1.6)
	_silos.append({"vented": false, "spill_min": spill_min, "spill_max": spill_max,
		"ramp_cell": spec.get("ramp_cell", []), "ramp_to_level": int(spec.get("ramp_to_level", 0)),
		"scree": ramp_root})
	lever.interacted.connect(func() -> void: _on_silo_vented(idx))

func _scree_box(at: Vector3, height: float, side: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(side, height, side)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.18, 0.12)
	mi.material_override = mat
	mi.position = at + Vector3(0, height * 0.5, 0)
	return mi

func _on_silo_vented(idx: int) -> void:
	var sched = _get_scheduler()
	if sched == null or idx >= _silos.size() or bool((_silos[idx] as Dictionary)["vented"]):
		return
	_show_note("The hatch grinds open. The whole hoard shifts—", 1.4)
	sched.schedule_after(0.8, func() -> void: _commit_silo(idx), "silo_%d" % idx)

func _commit_silo(idx: int) -> void:
	var entry := _silos[idx] as Dictionary
	if bool(entry["vented"]):
		return
	entry["vented"] = true
	var gs = _get_game_state()
	var kmin := entry["spill_min"] as Vector3
	var kmax := entry["spill_max"] as Vector3
	if gs != null:
		# the spill resolves at the commit tick, GROUND LEVEL only (a deck walker above the
		# rect is eight meters over the pile)
		for id_v in gs.characters.keys():
			var cid := str(id_v)
			var cp: Vector3 = gs.get_position(cid)
			if cp.y > 2.0 or cp.x < kmin.x or cp.x > kmax.x or cp.z < kmin.z or cp.z > kmax.z:
				continue
			var en = call("_enemy_by_id", cid) if has_method("_enemy_by_id") else null
			if en != null and is_instance_valid(en) and en.is_alive():
				gs.command_stop(cid)
				en.take_damage(float(en.max_hp))
			elif not cid.begins_with("enemy") and not cid.begins_with("chelator"):
				gs.adjust_stat(cid, "hp", -20.0)
				_show_note("The spill takes %s off their feet — buried to the waist, hurt." % cid.capitalize(), 2.6)
		var rc: Array = entry["ramp_cell"]
		var lvl := int(entry["ramp_to_level"])
		if rc.size() == 2 and lvl >= 1 and gs.grid != null and gs.grid.has_method("add_inter_level_link"):
			gs.grid.add_inter_level_link(Vector2i(int(rc[0]), int(rc[1])), 0, lvl, "ramp")
			_show_note("The scree piles into a climbable ramp — all the way up to the line.", 3.0)
	var scree := entry["scree"] as Node3D
	if scree != null and is_instance_valid(scree):
		scree.visible = true

## A DERELICT RESOURCE BELT (SET_PIECES.md #25; canon: the powered resource belt element rides
## a standing character at belt speed). The EFFECT is a fast EXPOSED transit down the old supply
## line; the CONTROL is the substation breaker spawned apart from it (the set-piece grammar:
## control and effect separated). Dead until the breaker is reset. Emits simple trough + post
## visuals for the level middle segment of the run.
func _spawn_belt(spec: Dictionary) -> BeltLine:
	var bl := BeltLine.new()
	bl.name = str(spec.get("name", "BeltLine"))
	bl.description = str(spec.get("desc", "Ride the old resource belt"))
	bl.tutorial_label = str(spec.get("label", "RIDE BELT"))
	var wps: Array = []
	for wv in (spec.get("waypoints", []) as Array):
		if wv is Vector3:
			wps.append(wv)
	bl.configure(_get_game_state(), spec.get("pos", Vector3.ZERO), wps,
		float(spec.get("radius", 1.4)), float(spec.get("speed", 4.2)))
	bl.exit_level = int(spec.get("exit_level", -1))
	bl.powered = bool(spec.get("powered", false))
	if has_method("_selected_party_ids"):
		bl.set_group_provider(Callable(self, "_selected_party_ids"))
	add_child(bl)
	_register_interactable(bl)
	var stub := _add_box(bl, Vector3(0.0, 0.25, 0.0), Vector3(0.7, 0.5, 0.7), Color(0.13, 0.14, 0.16))
	_outline_interactable_child(bl, stub, bl.name, 1.6)
	bl.refused.connect(func() -> void:
		_show_note("Dead line. The substation breaker is cut somewhere nearby.", 2.6))
	# trough + posts along each LEVEL (constant-y) run of the line
	var prev: Vector3 = spec.get("pos", Vector3.ZERO)
	for wv2 in wps:
		var seg: Vector3 = wv2
		if absf(seg.y - prev.y) < 0.05 and prev.distance_to(seg) > 1.5:
			var mid := (prev + seg) * 0.5
			var run := prev.distance_to(seg)
			var horiz := absf(seg.x - prev.x) > absf(seg.z - prev.z)
			_add_box(self, Vector3(mid.x, seg.y - 0.12, mid.z),
				Vector3(run, 0.16, 1.3) if horiz else Vector3(1.3, 0.16, run),
				Color(0.1, 0.11, 0.13))
			for t: float in [0.2, 0.5, 0.8]:
				var pp := prev.lerp(seg, t)
				if pp.y > 0.6:
					_add_box(self, Vector3(pp.x, pp.y * 0.5 - 0.1, pp.z),
						Vector3(0.22, pp.y - 0.2, 0.22), Color(0.12, 0.12, 0.14))
		prev = seg
	if spec.has("breaker_pos"):
		var brk := _add_interactable(self, str(spec.get("name", "BeltLine")) + "Breaker",
			"Reset the substation breaker", spec.get("breaker_pos", Vector3.ZERO), "RESET BREAKER",
			"", 1.2, true, 1.6, Interactable.InteractableType.TIMED_ACTION, false)
		var brk_mesh := _add_box(brk, Vector3(0.0, 0.45, 0.0), Vector3(0.45, 0.9, 0.45),
			Color(0.18, 0.24, 0.26), Color(0.32, 0.72, 0.82), 0.45)
		_outline_interactable_child(brk, brk_mesh, str(spec.get("name", "BeltLine")) + "Breaker", 1.6)
		brk.interacted.connect(func() -> void:
			bl.set_powered(true)
			_show_note("The breaker bites. Down the line, the old belt shudders and starts to move.", 3.0))
	return bl

## Loft one of the skirt's revolve-tower plans (the reference silhouettes).
func _skirt_lathe(lp: Dictionary) -> void:
	var profile: Dictionary = LatheBuilder.make_profile(lp)
	var built: Dictionary = LatheBuilder.build(profile)
	if built["mesh"] == null:
		return
	var mesh := built["mesh"] as ArrayMesh
	mesh.surface_set_material(0, _skirt_tile_material(str(lp.get("tile", "facility_metal")),
		lp.get("color", Color(0.4, 0.4, 0.42))))
	var mi := MeshInstance3D.new()
	mi.name = "SkirtLatheTower"
	mi.mesh = mesh
	add_child(mi)
	if bool(lp.get("coil", false)):
		var coil: Dictionary = SdfMesher.build(LatheBuilder.coil_prims(lp), 0.2)
		if coil["mesh"] != null:
			var ci := MeshInstance3D.new()
			ci.name = "SkirtLatheCoil"
			ci.mesh = coil["mesh"]
			ci.material_override = _skirt_tile_material("rust_iron", Color(0.4, 0.29, 0.21))
			add_child(ci)

## tile+tint -> cached grime-shader material (the district skirt's textured boxes).
func _skirt_tile_material(tile_name: String, tint: Color) -> ShaderMaterial:
	var lifted := Color(minf(tint.r * 2.6, 1.2), minf(tint.g * 2.6, 1.2), minf(tint.b * 2.6, 1.2))
	var key := "%s:%d,%d,%d" % [tile_name, int(lifted.r * 24.0), int(lifted.g * 24.0), int(lifted.b * 24.0)]
	if _skirt_mat_cache.has(key):
		return _skirt_mat_cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = SKIRT_GRIME_SHADER
	var tex = load(TILE_DIR + tile_name + ".png")
	if tex != null:
		mat.set_shader_parameter("tile_tex", tex)
	mat.set_shader_parameter("tint", lifted)
	if tile_name == "rust_iron":
		mat.set_shader_parameter("rust_amount", 0.3)
		mat.set_shader_parameter("grime_amount", 0.55)
	_skirt_mat_cache[key] = mat
	return mat


## A pixel-atlas material that tiles across a surface in world space (the sim-room / bridge / generated-stretch
## technique): 1 tile/m, NEAREST sampled, world-triplanar so it repeats crisply regardless of the mesh's size or
## UVs — and, because the repeat is anchored to world coords, each tile seam lands on a grid-cell boundary, so
## the grid reads through the floor. Shared home for every chunk (generated_stretch inherits this).
func _tiled_floor_material(tile_name: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex = load(TILE_DIR + tile_name + ".png")
	if tex != null:
		m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _add_box(
	parent: Node3D,
	position: Vector3,
	size: Vector3,
	color: Color,
	emission := Color.BLACK,
	emission_energy := 0.0,
	name := ""
) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	if name != "":
		mesh.name = name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _make_material(color, emission, emission_energy)
	mesh.position = position
	parent.add_child(mesh)
	return mesh

## A tiled ground slab. Passing `tile` (a pixel-atlas tile name from TILE_DIR) textures the top with the
## world-triplanar 1-tile/m deck material — each grid cell reads as one tile, so the grid is visible, matching
## the sim-room / generated-stretch look. Omit `tile` for the old flat-colored slab (every existing caller).
func _add_floor(parent: Node3D, position: Vector3, size: Vector3, color: Color, tile := "") -> MeshInstance3D:
	var floor := _add_box(parent, position, size, color)
	if tile != "":
		floor.material_override = _tiled_floor_material(tile)
	var body := StaticBody3D.new()
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return floor

func _add_light(
	parent: Node3D,
	position: Vector3,
	color: Color,
	energy: float,
	range_value: float
) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	parent.add_child(light)
	return light

func _add_label(
	parent: Node3D,
	text: String,
	position: Vector3,
	color := Color(0.82, 0.86, 0.92)
) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = position
	label.pixel_size = 0.01
	label.font_size = 52
	label.modulate = color
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.55)
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
	return label

## A SHELTER REST POINT: registers the data-layer shelter region, lays a warm pad, and wires a
## REST interactable that beds the ACTIVE character down (GameState.command_rest — heals on the
## scheduler, costs ATP pips, night-skips when everyone conscious is asleep). One call per shelter;
## every chunk with a shelter should use this instead of bespoke wiring.
func _add_rest_point(parent: Node3D, center: Vector3, size: Vector2 = Vector2(5.0, 5.0)) -> Area3D:
	var gs = _get_game_state()
	if gs != null:
		gs.add_shelter_region(
			Vector2(center.x - size.x * 0.5, center.z - size.y * 0.5),
			Vector2(center.x + size.x * 0.5, center.z + size.y * 0.5))
	_add_floor(parent, center + Vector3(0.0, 0.03, 0.0), Vector3(size.x, 0.08, size.y), Color(0.16, 0.14, 0.1))
	# Rest is the ONE justified proximity action ("bed down where you stand"), so opt into HOLD_ACTION
	# explicitly — the click-gated default must not silently turn resting into a click.
	var rest = _add_interactable(
		parent, "RestInteractable", "Rest", center, "REST", "", 1.2, false, 2.5,
		Interactable.InteractableType.HOLD_ACTION)
	rest.interacted.connect(func():
		var inner_gs = _get_game_state()
		if inner_gs != null and str(rest.active_character) != "":
			inner_gs.command_rest(str(rest.active_character)))
	return rest

## Create a chunk interactable. ACTIVATION DEFAULTS TO CLICK-GATED (INSPECTION): the player clicks it, the
## character walks over, it fires on arrival. Pass TIMED_ACTION for an action with a work/hold beat (salvage,
## tend, survey). Pass HOLD_ACTION (proximity auto-dwell) ONLY for a justified proximity action — currently
## just rest points. A new level that omits the type ships CLICK-GATED, never accidental proximity. Every
## visible interactable is auto-wired to an OutlineSurfaceTarget (shared outline+glow shaders); for a
## procedural mesh added after this call, prefer _add_object_interactable with explicit meshes. See the
## InteractableType enum doc and the --test-chunk-interactable-outlines guard.
func _add_interactable(
	parent: Node3D,
	node_name: String,
	description: String,
	position: Vector3,
	tutorial_label: String,
	required_character := "",
	dwell_time := 1.0,
	one_shot := false,
	interaction_radius := 1.5,
	interactable_type := Interactable.InteractableType.INSPECTION,
	auto_outline := true
) -> Area3D:
	var spec := {
		"position": position,
		"description": description,
		"requires_hold": interactable_type == Interactable.InteractableType.HOLD_ACTION,
		"hold_time": dwell_time,
		"one_shot": one_shot,
		"required_character": required_character,
		"radius": interaction_radius,
		"tutorial_label": tutorial_label,
	}
	var interactable = InteractableFactory.spawn(
		_get_game_state(),
		parent,
		_interactable_data_id(node_name),
		spec,
		_get_scheduler(),
		_dialogue_box(),
		_get_active_character()
	)
	# Keep the authored scene-tree name so lookups/tests that match on it still work
	# (the data-layer id stays namespaced via _interactable_data_id).
	interactable.name = node_name
	# Mirror the spec onto the node directly so a host-less standalone preview (no
	# GameState to bind against) still has every field populated.
	interactable.description = description
	interactable.tutorial_label = tutorial_label
	interactable.required_character = required_character
	interactable.dwell_time = dwell_time
	interactable.one_shot = one_shot
	interactable.interaction_radius = interaction_radius
	interactable.interactable_type = interactable_type
	_register_interactable(interactable)
	if interactable.has_method("show_tutorial_label"):
		interactable.call("show_tutorial_label")
	if auto_outline:
		_auto_outline_interactable(interactable, parent, position, interaction_radius)
		# A caller often appends the dressing mesh right AFTER this returns, so the first pass found nothing.
		# Retry once deferred to catch the late mesh (no-op if already wired). For a WARPED scene the outline
		# must exist before the warp pass — those call sites use _add_object_interactable with explicit meshes.
		if "_outline_target" in interactable and interactable.get("_outline_target") == null:
			call_deferred("_auto_outline_interactable", interactable, parent, position, interaction_radius)
	return interactable

## Auto-wire the shared outline+shimmer to whatever object meshes sit AT this interactable's spot, so
## every chunk interactable highlights like a tutorial object without each call site listing meshes.
## Collects MeshInstance3D under `parent` whose bounds-centre is within the interaction radius (the
## floor/walls sit far from any single object, so they're excluded), skipping outline shells. No-op if
## no mesh is found or an outline target is already linked (e.g. _add_object_interactable did it).
func _auto_outline_interactable(interactable: Node, parent: Node3D, position: Vector3, radius: float) -> void:
	if interactable == null:
		return
	if "_outline_target" in interactable and interactable.get("_outline_target") != null:
		return
	# Cap the collect radius: it gathers the object's OWN co-located meshes, not distant walls a big
	# interaction radius would otherwise reach.
	var meshes := _collect_meshes_near(parent, position, clampf(radius, 0.6, 1.6), interactable)
	if meshes.is_empty():
		return
	var target := _outline_object(parent, str(interactable.name) + "Outline", meshes,
		_interactable_data_id(str(interactable.name)), radius)
	if target == null:
		return
	if target.has_method("set_interaction_delegate"):
		target.call("set_interaction_delegate", interactable)
	if interactable.has_method("set_outline_target"):
		interactable.call("set_outline_target", target)

## MeshInstance3D under `node` whose world AABB centre is within `radius` of `position`, excluding:
## outline shells; meshes another OutlineSurfaceTarget already owns (one mesh, one outline owner);
## and meshes living under a DIFFERENT interactable's subtree (its dwell ring, dressing, verb disc —
## grabbing a neighbour's parts merges two objects into one oversized pick body that eats the hover
## ray: the hub-wheel bug, where the crawl mouth's outline body swallowed the wheel entirely).
func _collect_meshes_near(node: Node, position: Vector3, radius: float, for_interactable: Node = null) -> Array:
	var out: Array = []
	for mi in OutlineFeedbackManager.collect_mesh_instances(node):
		if mi == null or mi.mesh == null or mi.name == "ObjectOutlineShell" \
				or mi.name == "InteractableProgressRing":
			continue
		if mi.has_meta("outline_owner_id") and is_instance_id_valid(int(mi.get_meta("outline_owner_id"))):
			continue
		var owner_ia := _owning_interactable(mi)
		if owner_ia != null and owner_ia != for_interactable:
			continue
		var world_aabb: AABB = mi.global_transform * mi.mesh.get_aabb()
		var center := world_aabb.position + world_aabb.size * 0.5
		if center.distance_to(position) <= radius:
			out.append(mi)
	return out

## The interactable a node belongs to (nearest ancestor with the interactable signature), or null.
func _owning_interactable(node: Node) -> Node:
	var cur := node
	while cur != null:
		if cur.has_signal("interacted") and "interaction_radius" in cur:
			return cur
		cur = cur.get_parent()
	return null

func _add_inspection_interactable(
	parent: Node3D,
	node_name: String,
	description: String,
	position: Vector3,
	tutorial_label: String,
	required_character := "",
	interaction_radius := 1.5,
	one_shot := false
) -> Area3D:
	return _add_interactable(
		parent,
		node_name,
		description,
		position,
		tutorial_label,
		required_character,
		0.0,
		one_shot,
		interaction_radius,
		Interactable.InteractableType.INSPECTION
	)

# --- Object outlines (hover/selected edge outline + surface-emitted particles) ---
# Any chunk can outline an object's meshes; the shared OutlineFeedbackManager for
# this chunk's branch (the host sequence's, or a created one) drives the feedback —
# so chunk outlines are live in gameplay, not just tutorials.

var _outline_feedback_manager: OutlineFeedbackManager = null

func _outline_system() -> OutlineFeedbackManager:
	if _outline_feedback_manager == null or not is_instance_valid(_outline_feedback_manager):
		_outline_feedback_manager = OutlineFeedbackManager.ensure(self)
	return _outline_feedback_manager

## Outline an object whose meshes are `meshes`, sizing the box from their world
## bounds. opts overrides OutlineFeedbackManager.OUTLINE_DEFAULTS (plus "delegate" /
## "metadata"). Returns the target, or null with no usable mesh.
func _outline_object(
	parent: Node3D,
	target_name: String,
	meshes: Array,
	element_id: String,
	radius := 1.0,
	opts: Dictionary = {}
) -> Node3D:
	var system := _outline_system()
	if system == null:
		return null
	return system.outline_meshes(parent, target_name, meshes, element_id, radius, opts)

## Outline an object with an explicit center/size box (when the meshes' bounds don't
## match the silhouette you want to pick, e.g. a tall marker over a flat pad).
func _outline_target(
	parent: Node3D,
	target_name: String,
	center: Vector3,
	size: Vector3,
	meshes: Array,
	element_id: String,
	radius := 1.0,
	opts: Dictionary = {}
) -> Node3D:
	var system := _outline_system()
	if system == null:
		return null
	return system.create_outline_target(parent, target_name, center, size, meshes, element_id, radius, opts)

# --- Cause -> effect feedback ---------------------------------------------------------------
# Chunks register relationships here instead of inventing bespoke beams, camera cuts, or pause
# behavior. The one language is: hover the cause, hold reveal-all, or pause to plan; activation
# can latch/flash the same link while a consequence unfolds.

func _wire_causal_feedback_manager() -> void:
	if _causal_feedback_wired:
		return
	var system := _outline_system()
	if system == null:
		return
	if not system.hovered_target_changed.is_connected(_on_causal_hovered_target_changed):
		system.hovered_target_changed.connect(_on_causal_hovered_target_changed)
	if not system.selected_target_changed.is_connected(_on_causal_selected_target_changed):
		system.selected_target_changed.connect(_on_causal_selected_target_changed)
	_causal_feedback_wired = true

## Register a readable cause -> effect relationship between any two 3D nodes.
## opts: label, source_offset, target_offset, arc_height, dash_count, target_highlight,
## visibility_query, visibility_policy, owner_character, character_tint, path_style,
## flow_speed, feedback_mode, draw_duration, name.
## Preview hosts automatically supply the shared party-perception query.
func _add_causal_feedback_link(
		source: Node3D,
		target: Node3D,
		tint := Color(1.0, 0.64, 0.2),
		opts: Dictionary = {}
	) -> Node3D:
	if source == null or target == null:
		return null
	_wire_causal_feedback_manager()
	var resolved_opts := opts.duplicate()
	if not resolved_opts.has("visibility_query") and host != null \
			and host.has_method("can_party_perceive_feedback_link"):
		resolved_opts["visibility_query"] = Callable(host, "can_party_perceive_feedback_link")
	var link := CAUSAL_FEEDBACK_LINK_SCRIPT.new() as Node3D
	add_child(link)
	link.call("configure", source, target, tint, resolved_opts)
	_causal_feedback_links.append(link)
	return link


func _on_causal_hovered_target_changed(target: Node) -> void:
	for link in _causal_feedback_links:
		if link != null and is_instance_valid(link):
			link.call("set_source_hovered", bool(link.call("matches_source", target)))


func _on_causal_selected_target_changed(target: Node) -> void:
	for link in _causal_feedback_links:
		if link != null and is_instance_valid(link) and bool(link.call("matches_source", target)):
			link.call("flash", 1.5, 1.25)


## Fragment preview planning-pause hook. Kept separate from reveal-all so either input can be
## released without hiding a relationship the other still requests.
func set_preview_planning_feedback(active: bool) -> void:
	for link in _causal_feedback_links:
		if link != null and is_instance_valid(link):
			link.call("set_planning_active", active)
	for child in get_children():
		_forward_preview_planning_feedback(child, active)


func _forward_preview_planning_feedback(node: Node, active: bool) -> void:
	if node.has_method("set_preview_planning_feedback"):
		node.call("set_preview_planning_feedback", active)
		return
	for child in node.get_children():
		_forward_preview_planning_feedback(child, active)


func _flash_causal_feedback(source: Node, duration := 1.25, strength := 1.0) -> void:
	for link in _causal_feedback_links:
		if link != null and is_instance_valid(link) and bool(link.call("matches_source", source)):
			link.call("flash", duration, strength)


func _set_causal_feedback_latched(source: Node, active: bool) -> void:
	for link in _causal_feedback_links:
		if link != null and is_instance_valid(link) and bool(link.call("matches_source", source)):
			link.call("set_latched", active)


func _set_causal_feedback_mode(source: Node, mode: String) -> void:
	for link in _causal_feedback_links:
		if link != null and is_instance_valid(link) and bool(link.call("matches_source", source)):
			link.call("set_feedback_mode", mode)


## Ask the preview host for a short, guarded camera emphasis. Full campaign hosts and headless
## chunk stubs safely no-op; the gameplay relationship remains valid without presentation.
func _request_preview_focus(target: Node3D, duration := 0.9, pause_gameplay := false, opts: Dictionary = {}) -> bool:
	if host == null or target == null or not host.has_method("emphasize_preview_target"):
		return false
	return bool(host.call("emphasize_preview_target", target, duration, pause_gameplay, opts))


func _request_preview_shake(intensity := 0.12, decay := 7.0) -> void:
	if host != null and host.has_method("shake_preview_camera"):
		host.call("shake_preview_camera", intensity, decay)


func get_causal_feedback_state() -> Dictionary:
	var states: Array = []
	var visible_count := 0
	for link in _causal_feedback_links:
		if link == null or not is_instance_valid(link):
			continue
		var state: Dictionary = link.call("get_feedback_state")
		states.append(state)
		if bool(state.get("visible", false)):
			visible_count += 1
	return {"count": states.size(), "visible_count": visible_count, "links": states}

## Create an interactable for an OBJECT and cross-wire it to the shared outline+particle highlight, so
## the object gets the hover OUTLINE and the click/active SHIMMER — the SAME feedback tutorial objects
## get (Aster's sim). This is the chunk equivalent of the tutorial's _outline_object_meshes +
## _set_room_target_interaction_delegate: the meshless interactable forwards hover/SHIFT to the
## OutlineSurfaceTarget wrapping `meshes` (the real silhouette), instead of showing nothing. Use this
## for any chunk object the player can act on, so chunk interactables and tutorial objects highlight
## identically through the one OutlineFeedbackManager.
func _add_object_interactable(
	parent: Node3D,
	node_name: String,
	description: String,
	position: Vector3,
	tutorial_label: String,
	meshes: Array,
	required_character := "",
	dwell_time := 1.0,
	one_shot := false,
	interaction_radius := 1.5,
	interactable_type := Interactable.InteractableType.HOLD_ACTION
) -> Area3D:
	var interactable := _add_interactable(parent, node_name, description, position, tutorial_label,
		required_character, dwell_time, one_shot, interaction_radius, interactable_type, false)
	var target := _outline_object(parent, node_name + "Outline", meshes,
		_interactable_data_id(node_name), interaction_radius)
	if target != null:
		if target.has_method("set_interaction_delegate"):
			target.call("set_interaction_delegate", interactable)
		if interactable.has_method("set_outline_target"):
			interactable.call("set_outline_target", target)
	return interactable

## Wire the shared outline+glow to an interactable's OWN child mesh, creating the outline target AS A CHILD
## of the interactable. On a WARPED scene (the channels helix) this is what makes the outline ride the warp:
## the interactable, its dressing mesh, and the outline target all move together under warp_interactables_
## onto_coord_map. Use for a procedural interactable whose visual is its child (build the mesh as a child of
## the interactable first, then call this). On flat scenes it behaves like any other outline.
func _outline_interactable_child(interactable: Node3D, mesh: MeshInstance3D, element_name: String, radius := 1.5) -> Node3D:
	if interactable == null or mesh == null:
		return null
	var target := _outline_object(interactable, element_name + "Outline", [mesh], _interactable_data_id(element_name), radius)
	if target == null:
		return null
	# outline_meshes sets target.position from the mesh's WORLD bounds; as a CHILD of the off-origin
	# interactable that becomes a wrong LOCAL offset (a double-count that strands the target at the authored
	# spot). Re-anchor by GLOBAL position onto the mesh so the target sits on it and rides the interactable's
	# warp as a child onto the helix deck.
	if (target is Node3D) and (mesh is Node3D):
		(target as Node3D).global_position = (mesh as Node3D).global_position
	if target.has_method("set_interaction_delegate"):
		target.call("set_interaction_delegate", interactable)
	if interactable.has_method("set_outline_target"):
		interactable.call("set_outline_target", target)
	return target
