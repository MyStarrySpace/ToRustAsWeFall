extends "res://scripts/scene_chunks/scene_chunk.gd"

const WORLD_SLOT := {
	"slot_id": "act1_endo_junction_to_shelter_1",
	"act": 1,
	"region": "Channels / Endo's Junction",
	"entry_shelter_id": "endo_junction",
	"exit_shelter_id": "shelter_1",
	"entry_anchor": "endo_junction_work_area",
	"exit_anchor": "shelter_1_hearth",
	"canonical_party": ["aster", "peris", "endo"],
	"preview_party_preset": "full_party_full_health",
	"next_slot": "act1_channels_first_spiral",
}

const FLOOR_CENTER := Vector3(47.0, -0.05, 0.0)
const FLOOR_SIZE := Vector3(98.0, 0.1, 36.0)
const JUNCTION_POS := Vector3(7.0, 0.45, 0.0)
const WALL_MARKS_POS := Vector3(15.0, 0.45, -4.8)
const GUIDE_MARK_POS := Vector3(23.0, 0.45, -4.2)
const FORAGE_CACHE_POS := Vector3(31.0, 0.45, 5.5)
const SAFE_LEDGE_POS := Vector3(43.0, 0.45, -5.2)
const RISKY_BLOOM_POS := Vector3(43.5, 0.45, 5.6)
const HIDE_SLOT_POS := Vector3(56.5, 0.45, -5.0)
const SHORTCUT_LOCK_POS := Vector3(64.0, 0.45, -1.4)
const SHELTER_APPROACH_POS := Vector3(74.0, 0.45, 0.0)
const SHELTER_POS := Vector3(86.0, 0.45, 0.0)

const INTERACT_RADIUS := 2.6
const SHELTER_RADIUS := 3.2
const DIRECT_DAMAGE_ASTER := 10.0
const DIRECT_DAMAGE_PERIS := 8.0
const DIRECT_DAMAGE_ENDO := 14.0

const SPAWNS := {
	"aster": Vector3(4.8, 0.5, 1.6),
	"peris": Vector3(3.1, 0.5, -0.2),
	"endo": Vector3(3.7, 0.5, -2.4),
}

var _junction_interactable
var _route_interactable
var _cache_interactable
var _safe_interactable
var _direct_interactable
var _shortcut_interactable
var _shelter_interactable

var _junction_material: StandardMaterial3D
var _safe_material: StandardMaterial3D
var _direct_material: StandardMaterial3D
var _cache_material: StandardMaterial3D
var _shortcut_material: StandardMaterial3D
var _shelter_material: StandardMaterial3D

var _junction_read := false
var _safe_route_marked := false
var _forage_collected := false
var _danger_resolved := false
var _shortcut_unlocked := false
var _shelter_reached := false
var _shelter_rested := false
var _first_night_beat_fired := false
var _first_night_beat_count := 0
var _route_choice := ""
var _route_phase := "junction"
var _last_outcome := ""
var _direct_damage_total := 0.0
var _segments_completed: Array[String] = []
var _cache_item_id := ""

func _build_chunk() -> void:
	_build_shell()
	_build_junction()
	_build_route_marks()
	_build_forage_cache()
	_build_crossing()
	_build_hide_and_shortcut()
	_build_shelter()
	reset_preview_state()

func _process(delta: float) -> void:
	_update_stretch(delta)

func headless_process(delta: float) -> void:
	_update_stretch(delta)

func get_scene_title() -> String:
	return "Endo's Junction to Shelter 1"

func get_scene_help() -> String:
	return "Run the first real shelter stretch as a topped-off party: let Endo read his wall, have Aster mark the route, choose safe guidance or a risky direct bloom, collect food, unlock the return shortcut, and reach Shelter 1."

func get_default_character() -> String:
	return "endo"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors.merge({
		"junction": JUNCTION_POS,
		"wall_marks": WALL_MARKS_POS,
		"guide_mark": GUIDE_MARK_POS,
		"forage_cache": FORAGE_CACHE_POS,
		"safe_ledge": SAFE_LEDGE_POS,
		"risky_bloom": RISKY_BLOOM_POS,
		"hide_slot": HIDE_SLOT_POS,
		"shortcut_lock": SHORTCUT_LOCK_POS,
		"shelter_approach": SHELTER_APPROACH_POS,
		"shelter": SHELTER_POS,
	}, true)
	return anchors

func get_world_slot() -> Dictionary:
	return WORLD_SLOT.duplicate(true)

func get_preview_time_state() -> Dictionary:
	return {
		"day": 1,
		"time": 0.58,
		"routing_mode": "safe",
		"note_default": "This slice is world-slotted as the route from Endo's maintained junction into Shelter 1, but the preview boots with Aster, Peris, and Endo fully restored so the level can be tuned in isolation.",
	}

func get_preview_abilities() -> Array:
	# Display names + descriptions + tuning live in data/abilities/en/abilities.xlsx (per-context rows).
	return AbilityData.for_context("endo_junction_stretch")
func get_preview_state() -> Dictionary:
	return {
		"world_slot": get_world_slot(),
		"route_phase": _route_phase,
		"route_choice": _route_choice,
		"last_outcome": _last_outcome,
		"junction_read": _junction_read,
		"safe_route_marked": _safe_route_marked,
		"forage_collected": _forage_collected,
		"cache_item": _cache_item_id,
		"danger_resolved": _danger_resolved,
		"shortcut_unlocked": _shortcut_unlocked,
		"shelter_reached": _shelter_reached,
		"shelter_rested": _shelter_rested,
		"first_night_beat_fired": _first_night_beat_fired,
		"first_night_beat_count": _first_night_beat_count,
		"direct_damage_total": _direct_damage_total,
		"party_min_hp": _party_min_hp(),
		"segments_completed": _segments_completed.duplicate(),
		"stretch": {
			"boundary": "Endo's exterior junction work area to Shelter 1",
			"difficulty_target": "first main-level shelter stretch",
			"enemy_density": "low; one route-pressure bloom instead of a full chase",
			"foraging": "one Endo-readable starch cache",
			"food_cost": 1,
			"shelter_quality": "warm first-night refuge",
			"shortcut": "return grate at the shelter approach",
		},
	}

func get_preview_overlay_status(overlay_id: String, _current_tick: float) -> Array:
	match overlay_id:
		"aster":
			return [
				"DATA: Endo's wall marks line up with a shelter symbol and one usable maintenance ledge.",
				"Route: %s" % ("marked" if _safe_route_marked else "unresolved"),
				"Choice: %s" % (_route_choice if _route_choice != "" else _get_routing_mode()),
			]
		"peris":
			return [
				"FOG: the refuge feels lived-in, not abandoned.",
				"Plant memory: %s" % ("settling inside Shelter 1" if _shelter_reached else "pulling toward the warm room"),
				"Food cache: %s" % ("collected" if _forage_collected else "still tucked in the wall"),
			]
		"endo":
			return [
				"SURVIVAL: junction -> cache -> ledge or bloom -> shortcut -> shelter.",
				"Shortcut: %s" % ("open" if _shortcut_unlocked else "locked"),
				"Next: %s" % _current_instruction(),
			]
		_:
			return []

func reset_preview_state() -> void:
	if _cache_item_id != "":
		_remove_item(_cache_item_id)
	_cache_item_id = ""
	_junction_read = false
	_safe_route_marked = false
	_forage_collected = false
	_danger_resolved = false
	_shortcut_unlocked = false
	_shelter_reached = false
	_shelter_rested = false
	_first_night_beat_fired = false
	_first_night_beat_count = 0
	_route_choice = ""
	_route_phase = "junction"
	_last_outcome = ""
	_direct_damage_total = 0.0
	_segments_completed.clear()
	_set_preview_step("endo_junction_stretch_start")
	_reset_story_interactables()
	_update_visual_state()

func handle_preview_ability(ability_id: String, _ability: Dictionary = {}) -> Dictionary:
	match ability_id:
		"aster_focus":
			if _junction_read and not _safe_route_marked:
				_safe_route_marked = true
				_route_phase = "safe_marked"
				_mark_segment("route_marked")
				_update_visual_state()
				return {"note": "Aster translates Endo's scratch marks into a safe ledge path."}
			return {"note": "Aster needs Endo's wall read before TRACE has enough context."}
		"peris_tune":
			return {"characters": {"aster": {"sta_delta": 8.0}, "peris": {"sta_delta": 12.0}, "endo": {"sta_delta": 8.0}}}
		"endo_patch":
			if not _junction_read:
				return {"characters": {"endo": {"sta_delta": 8.0}}, "note": "Endo taps the junction marks and waits for the others to read his route."}
			return {"characters": {"endo": {"sta_delta": 10.0}}, "note": "Endo's survival pass highlights the cache, the ledge, and the shelter lock."}
		_:
			return {}

func on_preview_routing_changed(mode: String) -> void:
	if mode == "direct":
		_show_note("Direct routing cuts through the hot bloom. It is shorter and recoverable, but the party pays HP before shelter rest.", 2.8)
	else:
		_show_note("Safe routing follows Endo's maintenance marks and preserves health for the first-night shelter beat.", 2.8)

func read_junction() -> bool:
	if _junction_read:
		return true
	if not _require_station("endo", JUNCTION_POS, "Endo's junction marks"):
		return false
	_junction_read = true
	_route_phase = "junction_read"
	_mark_segment("junction_read")
	_set_preview_step("endo_junction_read")
	_clear_dialogue()
	_say_key("endo_stretch.entry.aster_space")
	_say_key("endo_stretch.entry.peris_home")
	_say_key("endo_stretch.route.endo_gesture")
	_complete_interactable(_junction_interactable)
	_update_visual_state()
	return true

func mark_safe_route() -> bool:
	if _safe_route_marked:
		return true
	if not _junction_read:
		_show_message("Endo needs to show the junction marks first.", 1.3)
		return false
	if not _require_station("aster", GUIDE_MARK_POS, "the translated route mark"):
		return false
	_safe_route_marked = true
	_route_phase = "safe_marked"
	_mark_segment("route_marked")
	_set_preview_step("endo_junction_route_marked")
	_show_message("Aster maps the ledge route to Shelter 1.", 1.5)
	_complete_interactable(_route_interactable)
	_update_visual_state()
	return true

func collect_forage() -> bool:
	if _forage_collected:
		return true
	if not _require_station("endo", FORAGE_CACHE_POS, "the wall cache"):
		return false
	if not _has_free_hand_slots("endo", 1):
		_show_message("Endo needs a free hand for the starch cache.", 1.2)
		return false
	_cache_item_id = _spawn_item("lysate", FORAGE_CACHE_POS, {
		"display_name": "Junction Starch",
		"display_names_by_character": {"aster": "Lysate", "peris": "Lysate", "endo": "Starch"},
		"visual_color": Color(0.78, 0.66, 0.38),
		"atp_restore": 2.0,
	})
	if _cache_item_id == "" or not _pick_up_item("endo", _cache_item_id):
		if _cache_item_id != "":
			_remove_item(_cache_item_id)
		_cache_item_id = ""
		return false
	_forage_collected = true
	_route_phase = "foraged"
	_mark_segment("forage")
	_set_preview_step("endo_junction_forage")
	_say_key("endo_stretch.forage.peris")
	_complete_interactable(_cache_interactable)
	_update_visual_state()
	return true

func commit_safe_route() -> bool:
	if _danger_resolved:
		return _route_choice == "safe"
	if not _safe_route_marked:
		_show_message("Mark the safe ledge before committing the quiet route.", 1.4)
		return false
	if not _require_station("endo", SAFE_LEDGE_POS, "the safe ledge"):
		return false
	_route_choice = "safe"
	_danger_resolved = true
	_route_phase = "safe_route"
	_last_outcome = "clean_crossing"
	_mark_segment("safe_route")
	_set_preview_step("endo_junction_safe_route")
	_adjust_character_stat("endo", "sta", -6.0)
	_show_message("Endo threads the maintenance ledge without drawing the bloom.", 1.7)
	_complete_interactable(_safe_interactable)
	_complete_interactable(_direct_interactable)
	_update_visual_state()
	return true

func commit_direct_route() -> bool:
	if _danger_resolved:
		return _route_choice == "direct" and _party_min_hp() > 0.0
	if not _require_station("", RISKY_BLOOM_POS, "the short bloom"):
		return false
	_route_choice = "direct"
	_danger_resolved = true
	_route_phase = "direct_route"
	_last_outcome = "recoverable_damage"
	_direct_damage_total = DIRECT_DAMAGE_ASTER + DIRECT_DAMAGE_PERIS + DIRECT_DAMAGE_ENDO
	_mark_segment("direct_route")
	_set_preview_step("endo_junction_direct_route")
	_adjust_character_stat("aster", "hp", -DIRECT_DAMAGE_ASTER)
	_adjust_character_stat("peris", "hp", -DIRECT_DAMAGE_PERIS)
	_adjust_character_stat("endo", "hp", -DIRECT_DAMAGE_ENDO)
	_say_key("endo_stretch.direct.aster")
	_show_message("The direct bloom burns, but the party stays on its feet.", 1.7)
	_complete_interactable(_safe_interactable)
	_complete_interactable(_direct_interactable)
	_update_visual_state()
	return _party_min_hp() > 0.0

func unlock_shortcut() -> bool:
	if not _danger_resolved:
		_show_message("Resolve the crossing before opening the return grate.", 1.2)
		return false
	if _shortcut_unlocked:
		return true
	if not _require_station("endo", SHORTCUT_LOCK_POS, "the return grate latch"):
		return false
	_shortcut_unlocked = true
	_route_phase = "shelter_approach"
	_mark_segment("shortcut")
	_set_preview_step("endo_junction_shortcut_open")
	_show_message("Endo opens a return grate back toward the junction.", 1.7)
	_complete_interactable(_shortcut_interactable)
	_update_visual_state()
	return true

func reach_shelter() -> bool:
	if _shelter_rested:
		return true
	if not _danger_resolved:
		_show_message("The shelter path is still exposed.", 1.2)
		return false
	if not _party_near(SHELTER_POS, SHELTER_RADIUS):
		_show_message("Move someone into Shelter 1 first.", 1.2)
		return false
	_shelter_reached = true
	_shelter_rested = true
	_route_phase = "complete"
	_last_outcome = "shelter_rested"
	_mark_segment("shelter")
	_set_preview_step("endo_junction_shelter_1")
	_restore_party()
	_fire_first_night_beat()
	_complete_interactable(_shelter_interactable)
	_update_visual_state()
	return true

func rest_shelter() -> bool:
	return reach_shelter()

func _build_shell() -> void:
	_add_floor(self, FLOOR_CENTER, FLOOR_SIZE, Color(0.055, 0.066, 0.072))
	_add_box(self, Vector3(FLOOR_CENTER.x, 2.2, -18.1), Vector3(FLOOR_SIZE.x, 4.4, 0.3), Color(0.11, 0.13, 0.14))
	_add_box(self, Vector3(FLOOR_CENTER.x, 2.2, 18.1), Vector3(FLOOR_SIZE.x, 4.4, 0.3), Color(0.11, 0.13, 0.14))
	_add_box(self, Vector3(-1.0, 2.2, 0.0), Vector3(0.3, 4.4, FLOOR_SIZE.z), Color(0.09, 0.11, 0.12))
	_add_box(self, Vector3(96.5, 2.2, 0.0), Vector3(0.3, 4.4, FLOOR_SIZE.z), Color(0.09, 0.11, 0.12))
	for i in range(9):
		var blend := float(i) / 8.0
		_add_light(self, Vector3(7.0 + float(i) * 10.0, 3.8, -1.0 + sin(float(i) * 1.7) * 1.4), Color(0.38 + blend * 0.2, 0.48 + blend * 0.1, 0.56 - blend * 0.08), 1.15 + blend * 0.7, 13.0)
	_add_label(self, "ENDO'S JUNCTION", JUNCTION_POS + Vector3(2.6, 2.7, -4.0), Color(0.68, 0.9, 0.74))
	_add_label(self, "SHELTER 1", SHELTER_POS + Vector3(0.0, 2.85, 0.0), Color(0.98, 0.82, 0.52))

func _build_junction() -> void:
	_junction_material = _make_material(Color(0.14, 0.16, 0.15), Color(0.52, 0.8, 0.58), 0.24)
	_add_box(self, JUNCTION_POS + Vector3(0.0, -0.02, 0.0), Vector3(9.0, 0.2, 8.0), Color(0.08, 0.09, 0.085))
	var station := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.45
	mesh.bottom_radius = 0.62
	mesh.height = 1.8
	station.mesh = mesh
	station.material_override = _junction_material
	station.position = JUNCTION_POS + Vector3(0.0, 0.9, 0.0)
	add_child(station)
	_junction_interactable = _add_inspection_interactable(self, "EndoJunctionReadInteractable", "Endo's Junction Marks", JUNCTION_POS, "READ", "endo", INTERACT_RADIUS)
	_junction_interactable.interacted.connect(read_junction)

func _build_route_marks() -> void:
	_add_box(self, WALL_MARKS_POS + Vector3(0.0, 0.5, -0.4), Vector3(8.5, 1.0, 0.18), Color(0.14, 0.16, 0.16), Color(0.44, 0.68, 0.58), 0.12)
	_add_label(self, "WALL MARKS", WALL_MARKS_POS + Vector3(0.0, 1.65, -0.4), Color(0.66, 0.9, 0.75))
	_route_interactable = _add_inspection_interactable(self, "EndoJunctionRouteMarkInteractable", "Translated Route Mark", GUIDE_MARK_POS, "MARK", "aster", INTERACT_RADIUS)
	# The wall marks are ~8 units away, beyond auto-outline's reach — give the mark its OWN co-located post so
	# the interactable has a visible object to outline+glow.
	var rmark := _add_box(_route_interactable, Vector3(0.0, 0.5, 0.0), Vector3(0.4, 1.0, 0.4), Color(0.18, 0.3, 0.26), Color(0.44, 0.68, 0.58), 0.5)
	_outline_interactable_child(_route_interactable, rmark, "EndoJunctionRouteMarkInteractable", INTERACT_RADIUS)
	_route_interactable.interacted.connect(mark_safe_route)

func _build_forage_cache() -> void:
	_cache_material = _make_material(Color(0.28, 0.22, 0.12), Color(0.9, 0.64, 0.24), 0.32)
	_add_box(self, FORAGE_CACHE_POS + Vector3(0.0, 0.28, 0.0), Vector3(3.4, 0.56, 1.6), Color(0.2, 0.15, 0.09), Color(0.7, 0.42, 0.16), 0.18)
	var cache := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.42
	mesh.height = 0.84
	cache.mesh = mesh
	cache.material_override = _cache_material
	cache.position = FORAGE_CACHE_POS + Vector3(0.0, 0.8, 0.0)
	add_child(cache)
	_add_label(self, "STARCH CACHE", FORAGE_CACHE_POS + Vector3(0.0, 1.85, 0.0), Color(0.96, 0.78, 0.42))
	_cache_interactable = _add_inspection_interactable(self, "EndoJunctionCacheInteractable", "Wall Cache", FORAGE_CACHE_POS, "TAKE", "endo", INTERACT_RADIUS)
	_cache_interactable.interacted.connect(collect_forage)

func _build_crossing() -> void:
	_safe_material = _make_material(Color(0.1, 0.16, 0.18), Color(0.52, 0.78, 0.86), 0.18)
	_direct_material = _make_material(Color(0.22, 0.1, 0.07), Color(0.86, 0.28, 0.12), 0.28)
	_add_box(self, SAFE_LEDGE_POS + Vector3(0.0, -0.02, 0.0), Vector3(17.0, 0.16, 3.0), Color(0.09, 0.14, 0.16), Color(0.38, 0.64, 0.72), 0.16)
	_add_label(self, "SAFE LEDGE", SAFE_LEDGE_POS + Vector3(0.0, 1.65, 0.0), Color(0.64, 0.88, 0.96))
	_safe_interactable = _add_inspection_interactable(self, "EndoJunctionSafeRouteInteractable", "Safe Ledge", SAFE_LEDGE_POS, "THREAD", "endo", INTERACT_RADIUS)
	_safe_interactable.interacted.connect(commit_safe_route)
	_add_box(self, RISKY_BLOOM_POS + Vector3(0.0, -0.02, 0.0), Vector3(16.0, 0.16, 3.5), Color(0.18, 0.08, 0.055), Color(0.82, 0.22, 0.08), 0.24)
	_add_label(self, "SHORT BLOOM", RISKY_BLOOM_POS + Vector3(0.0, 1.65, 0.0), Color(0.98, 0.56, 0.32))
	_direct_interactable = _add_inspection_interactable(self, "EndoJunctionDirectRouteInteractable", "Short Bloom", RISKY_BLOOM_POS, "CUT", "", INTERACT_RADIUS)
	_direct_interactable.interacted.connect(commit_direct_route)

func _build_hide_and_shortcut() -> void:
	_add_box(self, HIDE_SLOT_POS + Vector3(0.0, -0.03, 0.0), Vector3(7.0, 0.18, 3.2), Color(0.07, 0.11, 0.1))
	_add_box(self, HIDE_SLOT_POS + Vector3(-3.3, 1.2, 0.0), Vector3(0.25, 2.4, 3.2), Color(0.1, 0.14, 0.12))
	_add_label(self, "HIDE SLOT", HIDE_SLOT_POS + Vector3(0.0, 1.8, 0.0), Color(0.62, 0.88, 0.68))
	_shortcut_material = _make_material(Color(0.15, 0.15, 0.14), Color(0.9, 0.76, 0.42), 0.14)
	_add_box(self, SHORTCUT_LOCK_POS + Vector3(0.0, 0.45, 0.0), Vector3(2.2, 0.9, 2.2), Color(0.16, 0.14, 0.12), Color(0.82, 0.62, 0.28), 0.16)
	_add_label(self, "RETURN GRATE", SHORTCUT_LOCK_POS + Vector3(0.0, 1.7, 0.0), Color(0.94, 0.78, 0.46))
	_shortcut_interactable = _add_inspection_interactable(self, "EndoJunctionShortcutInteractable", "Return Grate", SHORTCUT_LOCK_POS, "OPEN", "endo", INTERACT_RADIUS)
	_shortcut_interactable.interacted.connect(unlock_shortcut)

func _build_shelter() -> void:
	_shelter_material = _make_material(Color(0.2, 0.17, 0.11), Color(0.98, 0.74, 0.36), 0.3)
	_add_box(self, SHELTER_POS + Vector3(0.0, -0.03, 0.0), Vector3(10.0, 0.22, 8.0), Color(0.12, 0.1, 0.08))
	_add_box(self, SHELTER_POS + Vector3(4.9, 1.8, 0.0), Vector3(0.3, 3.6, 8.0), Color(0.16, 0.13, 0.1))
	_add_box(self, SHELTER_POS + Vector3(0.0, 1.8, -3.9), Vector3(10.0, 3.6, 0.3), Color(0.16, 0.13, 0.1))
	_add_box(self, SHELTER_POS + Vector3(0.0, 3.45, 0.0), Vector3(10.0, 0.16, 8.0), Color(0.09, 0.08, 0.075))
	var hearth := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.42
	mesh.bottom_radius = 0.7
	mesh.height = 0.9
	hearth.mesh = mesh
	hearth.material_override = _shelter_material
	hearth.position = SHELTER_POS + Vector3(0.0, 0.55, 0.0)
	add_child(hearth)
	_add_light(self, SHELTER_POS + Vector3(0.0, 2.1, 0.0), Color(1.0, 0.74, 0.38), 2.0, 11.5)
	_shelter_interactable = _add_inspection_interactable(self, "EndoJunctionShelterInteractable", "Shelter 1 Hearth", SHELTER_POS, "REST", "", SHELTER_RADIUS)
	_shelter_interactable.interacted.connect(reach_shelter)

func _update_stretch(_delta: float) -> void:
	if _danger_resolved and not _shelter_reached and _party_near(SHELTER_POS, SHELTER_RADIUS):
		reach_shelter()

func _complete_interactable(interactable: Node) -> void:
	if interactable != null and interactable.has_method("set_interaction_enabled"):
		interactable.call("set_interaction_enabled", false)

func _reset_story_interactables() -> void:
	for interactable in [
		_junction_interactable,
		_route_interactable,
		_cache_interactable,
		_safe_interactable,
		_direct_interactable,
		_shortcut_interactable,
		_shelter_interactable,
	]:
		if interactable == null:
			continue
		if interactable.has_method("reset"):
			interactable.call("reset")
		if interactable.has_method("show_tutorial_label"):
			interactable.call("show_tutorial_label")

func _require_station(char_id: String, station_pos: Vector3, label: String) -> bool:
	if char_id != "" and _get_active_character() != char_id:
		_show_message("%s needs to handle %s." % [_display_name(char_id), label], 1.2)
		return false
	var actor := char_id if char_id != "" else _get_active_character()
	if actor == "":
		actor = "aster"
	var dist := _get_character_position(actor).distance_to(station_pos)
	if dist > INTERACT_RADIUS:
		_show_message("Move %s to %s first." % [_display_name(actor), label], 1.2)
		return false
	return true

func _has_free_hand_slots(char_id: String, required_slots: int) -> bool:
	var free_count := 0
	for slot in _get_hand_slots(char_id):
		if slot == null:
			free_count += 1
			if free_count >= required_slots:
				return true
	return false

func _party_near(position: Vector3, radius: float) -> bool:
	for char_id in ["aster", "peris", "endo"]:
		if _get_character_position(char_id).distance_to(position) <= radius:
			return true
	return false

func _party_min_hp() -> float:
	var min_hp := 999.0
	for char_id in ["aster", "peris", "endo"]:
		min_hp = minf(min_hp, _get_character_stat(char_id, "hp"))
	return min_hp

func _restore_party() -> void:
	for char_id in ["aster", "peris", "endo"]:
		_set_character_stat(char_id, "hp", 100.0)
		_set_character_stat(char_id, "sta", 100.0)
		_set_character_stat(char_id, "atp", GameState.ATP_MAX_PIPS)
		_set_character_status(char_id, "rested")

func _fire_first_night_beat() -> void:
	if _first_night_beat_fired:
		return
	_first_night_beat_fired = true
	_first_night_beat_count += 1
	_clear_dialogue()
	_say_key("endo_stretch.shelter.peris")
	_say_key("endo_stretch.shelter.aster")
	_say_key("endo_stretch.shelter.endo_rest")
	_show_note("Shelter 1 reached. The preview restores the party, while the slot remains the first Endo junction stretch.", 4.0)

func _mark_segment(segment: String) -> void:
	if not _segments_completed.has(segment):
		_segments_completed.append(segment)

func _current_instruction() -> String:
	match _route_phase:
		"junction":
			return "read the wall marks with Endo"
		"junction_read":
			return "have Aster mark the safe route"
		"safe_marked":
			return "collect the cache or commit the ledge"
		"foraged":
			return "choose ledge or short bloom"
		"safe_route", "direct_route":
			return "open the return grate"
		"shelter_approach":
			return "enter Shelter 1"
		"complete":
			return "rested"
		_:
			return "follow Endo's shelter marks"

func _display_name(char_id: String) -> String:
	match char_id:
		"aster": return "Aster"
		"peris": return "Peris"
		"endo": return "Endo"
		_: return char_id.capitalize()

func _update_visual_state() -> void:
	if _junction_material != null:
		_junction_material.emission_energy_multiplier = 0.65 if _junction_read else 0.24
	if _safe_material != null:
		_safe_material.emission_energy_multiplier = 0.62 if _safe_route_marked else 0.16
	if _direct_material != null:
		_direct_material.emission_energy_multiplier = 0.55 if _route_choice == "direct" else 0.24
	if _cache_material != null:
		_cache_material.emission_energy_multiplier = 0.08 if _forage_collected else 0.32
	if _shortcut_material != null:
		_shortcut_material.emission_energy_multiplier = 0.85 if _shortcut_unlocked else 0.14
	if _shelter_material != null:
		_shelter_material.emission_energy_multiplier = 1.05 if _shelter_reached else 0.3
