extends "res://scripts/scene_chunks/scene_chunk.gd"

const LevelDecoratorScript := preload("res://scripts/generation/level_decorator.gd")

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

const FLOOR_CENTER := Vector3(140.0, -0.05, 0.0)
const FLOOR_SIZE := Vector3(284.0, 0.1, 44.0)
const JUNCTION_POS := Vector3(7.0, 0.45, 0.0)
const WALL_MARKS_POS := Vector3(15.0, 0.45, -4.8)
const GUIDE_MARK_POS := Vector3(23.0, 0.45, -4.2)
const FORAGE_CACHE_POS := Vector3(31.0, 0.45, 5.5)
const SAFE_LEDGE_POS := Vector3(43.0, 0.45, -5.2)
const RISKY_BLOOM_POS := Vector3(43.5, 0.45, 5.6)
const HIDE_SLOT_POS := Vector3(254.0, 0.45, -7.0)
const SHORTCUT_LOCK_POS := Vector3(260.0, 0.45, -1.4)
const SHELTER_APPROACH_POS := Vector3(266.0, 0.45, 0.0)
const SHELTER_POS := Vector3(274.0, 0.45, 0.0)

const PARTY_ROUTE_SPEED_METERS_PER_SECOND := 2.5
const THEORETICAL_SPRINT_SPEED_METERS_PER_SECOND := 6.0
const ORIENTATION_SECONDS := 4.0
const BASE_DECISION_SECONDS := 3.5
const FIELD_DECISION_SECONDS := 3.5

# Three measured field loops turn the old junction-to-hearth corridor into the first full-party
# survival lesson. Evidence can be gathered in any order, but each loop requires all five distinct
# reads, an explicit plan, and a spatial execution station. Both plans are valid and persistent:
# the player is choosing what resource to preserve, not hunting for a hidden correct button.
const FIELD_OPERATIONS := {
	"conduit": {
		"label": "CONDUIT LOAD SURVEY",
		"start": Vector3(48.0, 0.45, 0.0),
		"end": Vector3(134.0, 0.45, 0.0),
		"tint": Color(0.34, 0.78, 0.68),
		"evidence": ["conduit_pressure", "conduit_root", "conduit_grate", "conduit_spore", "conduit_latch"],
		"choices": ["conduit_brace", "conduit_buffer"],
		"resolution_sites": {
			"conduit_brace": "conduit_brace_execution",
			"conduit_buffer": "conduit_buffer_execution",
		},
		"next": "signal",
	},
	"signal": {
		"label": "SHELTER SIGNAL TRACE",
		"start": Vector3(134.0, 0.45, 0.0),
		"end": Vector3(220.0, 0.45, 0.0),
		"tint": Color(0.46, 0.70, 0.94),
		"evidence": ["signal_memory", "signal_echo", "signal_pin", "signal_vine", "signal_draft"],
		"choices": ["signal_memory_beacon", "signal_data_beacon"],
		"resolution_sites": {
			"signal_memory_beacon": "signal_memory_execution",
			"signal_data_beacon": "signal_data_execution",
		},
		"next": "approach",
	},
	"approach": {
		"label": "REFUGE ENTRY PLAN",
		"start": Vector3(220.0, 0.45, 0.0),
		"end": Vector3(266.0, 0.45, 0.0),
		"tint": Color(0.92, 0.69, 0.34),
		"evidence": ["approach_seam", "approach_growth", "approach_hinge", "approach_heat", "approach_floor"],
		"choices": ["approach_warm", "approach_sealed"],
		"resolution_sites": {
			"approach_warm": "approach_warm_execution",
			"approach_sealed": "approach_sealed_execution",
		},
		"next": "",
	},
}

const FIELD_SITES := {
	# Conduit evidence: a full-width maintenance loop with one specialist read per system.
	"conduit_pressure": {"operation": "conduit", "kind": "evidence", "role": "aster", "pos": Vector3(56.0, 0.45, -12.0), "dwell": 3.2, "verb": "MODEL PRESSURE", "display": "PRESSURE", "finding": "Aster isolates a pressure loss at the north race."},
	"conduit_root": {"operation": "conduit", "kind": "evidence", "role": "peris", "pos": Vector3(72.0, 0.45, 11.0), "dwell": 3.4, "verb": "READ ROOT LOAD", "display": "ROOT LOAD", "finding": "Peris feels living roots absorbing every third pulse."},
	"conduit_grate": {"operation": "conduit", "kind": "evidence", "role": "endo", "pos": Vector3(88.0, 0.45, -11.0), "dwell": 3.6, "verb": "TEST GRATE", "display": "GRATE", "finding": "Endo finds the grate sound but under-braced."},
	"conduit_spore": {"operation": "conduit", "kind": "evidence", "role": "peris", "pos": Vector3(104.0, 0.45, 12.0), "dwell": 3.4, "verb": "TRACE SPORE WAKE", "display": "SPORE WAKE", "finding": "The spore wake bends away from the living buffer."},
	"conduit_latch": {"operation": "conduit", "kind": "evidence", "role": "endo", "pos": Vector3(116.0, 0.45, 0.0), "dwell": 3.6, "verb": "PACE LATCH", "display": "LATCH", "finding": "The service latch can carry one deliberate reroute."},
	"conduit_brace": {"operation": "conduit", "kind": "choice", "role": "endo", "pos": Vector3(124.0, 0.45, -6.0), "dwell": 2.4, "verb": "PLAN HARD BRACE", "display": "BRACE", "finding": "The party will preserve the dry service lane."},
	"conduit_buffer": {"operation": "conduit", "kind": "choice", "role": "peris", "pos": Vector3(124.0, 0.45, 6.0), "dwell": 2.4, "verb": "PLAN ROOT BUFFER", "display": "BUFFER", "finding": "The party will preserve stamina through the living buffer."},
	"conduit_brace_execution": {"operation": "conduit", "kind": "resolution", "role": "endo", "pos": Vector3(130.0, 0.45, -10.0), "dwell": 4.5, "verb": "SEAT BRACE", "display": "SEAT BRACE", "finding": "Endo locks the service race against the next pulse."},
	"conduit_buffer_execution": {"operation": "conduit", "kind": "resolution", "role": "peris", "pos": Vector3(130.0, 0.45, 10.0), "dwell": 4.5, "verb": "FEED BUFFER", "display": "FEED ROOTS", "finding": "Peris settles the living buffer into the conduit rhythm."},

	# Signal evidence: reconstruct whether Shelter 1's beacon is machine or remembered life.
	"signal_memory": {"operation": "signal", "kind": "evidence", "role": "peris", "pos": Vector3(142.0, 0.45, 12.0), "dwell": 3.4, "verb": "RECALL SIGNAL", "display": "MEMORY", "finding": "Peris remembers the beacon as warmth, not an alarm."},
	"signal_echo": {"operation": "signal", "kind": "evidence", "role": "aster", "pos": Vector3(158.0, 0.45, -12.0), "dwell": 3.2, "verb": "CORRELATE ECHO", "display": "ECHO", "finding": "Aster proves the echo repeats from one fixed refuge source."},
	"signal_pin": {"operation": "signal", "kind": "evidence", "role": "endo", "pos": Vector3(174.0, 0.45, 11.0), "dwell": 3.6, "verb": "READ GUIDE PIN", "display": "GUIDE PIN", "finding": "Endo's guide pin points to the protected service face."},
	"signal_vine": {"operation": "signal", "kind": "evidence", "role": "peris", "pos": Vector3(190.0, 0.45, -11.0), "dwell": 3.4, "verb": "FOLLOW VINE", "display": "VINE", "finding": "A living vine carries heat toward Shelter 1."},
	"signal_draft": {"operation": "signal", "kind": "evidence", "role": "aster", "pos": Vector3(202.0, 0.45, 0.0), "dwell": 3.2, "verb": "MAP DRAFT", "display": "DRAFT", "finding": "The warm draft and beacon share the same protected opening."},
	"signal_memory_beacon": {"operation": "signal", "kind": "choice", "role": "peris", "pos": Vector3(210.0, 0.45, 6.0), "dwell": 2.4, "verb": "PLAN LIVING BEACON", "display": "LIVING", "finding": "The party will tune the signal through the refuge vine."},
	"signal_data_beacon": {"operation": "signal", "kind": "choice", "role": "aster", "pos": Vector3(210.0, 0.45, -6.0), "dwell": 2.4, "verb": "PLAN DATA BEACON", "display": "DATA", "finding": "The party will pin the signal to Aster's measured echo."},
	"signal_memory_execution": {"operation": "signal", "kind": "resolution", "role": "peris", "pos": Vector3(216.0, 0.45, 10.0), "dwell": 4.5, "verb": "TUNE VINE", "display": "TUNE VINE", "finding": "The living beacon settles into a warm, steady pulse."},
	"signal_data_execution": {"operation": "signal", "kind": "resolution", "role": "aster", "pos": Vector3(216.0, 0.45, -10.0), "dwell": 4.5, "verb": "PIN ECHO", "display": "PIN ECHO", "finding": "Aster fixes a clean data cadence on the shelter door."},

	# Approach evidence: inspect the actual refuge before deciding how to open it.
	"approach_seam": {"operation": "approach", "kind": "evidence", "role": "aster", "pos": Vector3(226.0, 0.45, -11.0), "dwell": 3.2, "verb": "TRACE DOOR SEAM", "display": "SEAM", "finding": "Aster maps one intact pressure seam along the refuge face."},
	"approach_growth": {"operation": "approach", "kind": "evidence", "role": "peris", "pos": Vector3(234.0, 0.45, 11.0), "dwell": 3.4, "verb": "READ DOOR GROWTH", "display": "GROWTH", "finding": "The door growth is dormant, not hostile."},
	"approach_hinge": {"operation": "approach", "kind": "evidence", "role": "endo", "pos": Vector3(242.0, 0.45, -11.0), "dwell": 3.6, "verb": "TEST HINGE", "display": "HINGE", "finding": "Endo finds the lower hinge able to take a slow opening."},
	"approach_heat": {"operation": "approach", "kind": "evidence", "role": "peris", "pos": Vector3(250.0, 0.45, 11.0), "dwell": 3.4, "verb": "CHECK HEAT", "display": "HEAT", "finding": "Shelter heat is stable enough to share with the corridor."},
	"approach_floor": {"operation": "approach", "kind": "evidence", "role": "endo", "pos": Vector3(256.0, 0.45, 0.0), "dwell": 3.6, "verb": "CHECK THRESHOLD", "display": "THRESHOLD", "finding": "The threshold will hold either a warm opening or a hard seal."},
	"approach_warm": {"operation": "approach", "kind": "choice", "role": "peris", "pos": Vector3(260.0, 0.45, 6.0), "dwell": 2.4, "verb": "PLAN WARM ENTRY", "display": "WARM", "finding": "The party will preserve recovery and accept a softer seal."},
	"approach_sealed": {"operation": "approach", "kind": "choice", "role": "endo", "pos": Vector3(260.0, 0.45, -6.0), "dwell": 2.4, "verb": "PLAN SEALED ENTRY", "display": "SEALED", "finding": "The party will preserve the hard boundary and spend stamina."},
	"approach_warm_execution": {"operation": "approach", "kind": "resolution", "role": "peris", "pos": Vector3(264.0, 0.45, 10.0), "dwell": 4.5, "verb": "WAKE HEAT VEIN", "display": "WAKE HEAT", "finding": "Peris opens a warm vein into the shelter threshold."},
	"approach_sealed_execution": {"operation": "approach", "kind": "resolution", "role": "endo", "pos": Vector3(264.0, 0.45, -10.0), "dwell": 4.5, "verb": "DOG SEAL", "display": "DOG SEAL", "finding": "Endo dogs the outer seal before opening the return grate."},
}

const INTERACT_RADIUS := 2.6
const SHELTER_RADIUS := 3.2
const SHELTER_ATP_COST := 1.0
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
var _field_sites: Dictionary = {}
var _field_route_visuals: Dictionary = {}
var _entry_guide: Node3D

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
var _field_phase := ""
var _field_evidence: Dictionary = {}
var _field_choices: Dictionary = {}
var _field_operations_completed: Dictionary = {}
var _field_effects: Dictionary = {}
var _field_findings: Array[String] = []
var _playtime_contract_cache: Dictionary = {}

func _build_chunk() -> void:
	_build_shell()
	_build_junction()
	_build_route_marks()
	_build_forage_cache()
	_build_crossing()
	_build_fieldwork()
	_build_hide_and_shortcut()
	_build_shelter()
	LevelDecoratorScript.decorate_profile(self, "endo_stretch", {
		"x1": FLOOR_CENTER.x + FLOOR_SIZE.x * 0.5,
		"width": FLOOR_SIZE.z,
		"spacing": 13.0,
		"floor_tint": Color(0.22, 0.29, 0.31),
		"floor_emission_energy": 0.34,
		"signs": ["ENDO'S JUNCTION", "CONDUIT SURVEY", "SHELTER SIGNAL", "REFUGE ENTRY", "SHELTER 1  >"],
	})
	reset_preview_state()

func _process(delta: float) -> void:
	_update_stretch(delta)

func headless_process(delta: float) -> void:
	_update_stretch(delta)

func get_scene_title() -> String:
	return "Endo's Junction to Shelter 1"

func get_scene_help() -> String:
	return "Run the first real shelter stretch as a topped-off party: bring Endo to the glowing junction console and read it, collect the cache, choose the ledge or bloom, then use all three specialists to survey the conduit, reconstruct the shelter signal, plan the refuge entry, open the return grate, and bring the full conscious party to Shelter 1 to spend one ATP each on rest."

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
	for site_id in FIELD_SITES.keys():
		anchors["field_%s" % site_id] = FIELD_SITES[site_id].get("pos", Vector3.ZERO)
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

## Keep the first-night story state, but establish a Web-readable moonlight floor. The host
## applies this after its shared day/night curve, including on subsequent clock updates.
func get_preview_lighting_profile() -> Dictionary:
	return {
		"ambient_energy_floor": 0.62,
		"directional_energy_floor": 0.5,
		"glow_intensity_floor": 0.34,
		"ambient_color": Color(0.28, 0.36, 0.46),
		"directional_color": Color(0.46, 0.58, 0.78),
		"color_mix": 0.72,
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
		"fieldwork": {
			"phase": _field_phase,
			"completed_evidence": _field_evidence.duplicate(true),
			"choices": _field_choices.duplicate(true),
			"operations_completed": _field_operations_completed.duplicate(true),
			"operation_count": _field_operations_completed.size(),
			"effects": _field_effects.duplicate(true),
			"findings": _field_findings.duplicate(),
		},
		"playtime_contract": get_playtime_contract(),
		"stretch": {
			"boundary": "Endo's exterior junction work area to Shelter 1",
			"difficulty_target": "first main-level shelter stretch",
			"enemy_density": "low; one route-pressure bloom instead of a full chase",
			"foraging": "one Endo-readable starch cache",
			"food_cost": 1,
			"shelter_quality": "warm first-night refuge",
			"shortcut": "return grate after three full-party field loops",
		},
	}

func get_playtime_contract() -> Dictionary:
	# This is a geometric lower-bound model, not a content-author guess. Every route term comes from
	# authored station coordinates; every work term is the Interactable's actual dwell. The direct
	# bloom is a few seconds shorter but is not the clean route because it deliberately spends HP.
	if not _playtime_contract_cache.is_empty():
		return _playtime_contract_cache.duplicate(true)
	var operation_routes := {}
	var field_route_meters := 0.0
	var field_work_seconds := 0.0
	for operation_id_variant in FIELD_OPERATIONS.keys():
		var operation_id := str(operation_id_variant)
		var operation_route := _shortest_field_operation_route(operation_id)
		operation_routes[operation_id] = operation_route
		field_route_meters += operation_route
		var operation: Dictionary = FIELD_OPERATIONS[operation_id]
		for site_id in operation.get("evidence", []):
			field_work_seconds += float(FIELD_SITES[str(site_id)].get("dwell", 0.0))
		var shortest_branch_work := INF
		for choice_id_variant in operation.get("choices", []):
			var choice_id := str(choice_id_variant)
			var resolution_id := str((operation.get("resolution_sites", {}) as Dictionary).get(choice_id, ""))
			var branch_work := float(FIELD_SITES[choice_id].get("dwell", 0.0))
			if resolution_id != "":
				branch_work += float(FIELD_SITES[resolution_id].get("dwell", 0.0))
			shortest_branch_work = minf(shortest_branch_work, branch_work)
		field_work_seconds += 0.0 if is_inf(shortest_branch_work) else shortest_branch_work

	var start := SPAWNS["endo"]
	var station_safe_base_route := start.distance_to(JUNCTION_POS) \
		+ JUNCTION_POS.distance_to(GUIDE_MARK_POS) \
		+ GUIDE_MARK_POS.distance_to(FORAGE_CACHE_POS) \
		+ FORAGE_CACHE_POS.distance_to(SAFE_LEDGE_POS) \
		+ SAFE_LEDGE_POS.distance_to(FIELD_OPERATIONS["conduit"].get("start", Vector3.ZERO))
	var focus_safe_base_route := start.distance_to(JUNCTION_POS) \
		+ JUNCTION_POS.distance_to(FORAGE_CACHE_POS) \
		+ FORAGE_CACHE_POS.distance_to(SAFE_LEDGE_POS) \
		+ SAFE_LEDGE_POS.distance_to(FIELD_OPERATIONS["conduit"].get("start", Vector3.ZERO))
	var direct_base_route := start.distance_to(JUNCTION_POS) \
		+ JUNCTION_POS.distance_to(FORAGE_CACHE_POS) \
		+ FORAGE_CACHE_POS.distance_to(RISKY_BLOOM_POS) \
		+ RISKY_BLOOM_POS.distance_to(FIELD_OPERATIONS["conduit"].get("start", Vector3.ZERO))
	var tail_route := (FIELD_OPERATIONS["approach"].get("end", Vector3.ZERO) as Vector3).distance_to(SHORTCUT_LOCK_POS) \
		+ SHORTCUT_LOCK_POS.distance_to(SHELTER_POS)
	var station_safe_route_meters := station_safe_base_route + field_route_meters + tail_route
	var focus_safe_route_meters := focus_safe_base_route + field_route_meters + tail_route
	var direct_route_meters := direct_base_route + field_route_meters + tail_route
	var base_station_safe_work := 3.4 + 4.0 + 4.2 + 4.0 + 3.0
	var base_focus_safe_work := 4.0 + 4.2 + 4.0 + 3.0
	var base_direct_work := 4.0 + 4.2 + 4.0 + 3.0
	var field_decision_total := FIELD_DECISION_SECONDS * float(FIELD_OPERATIONS.size())
	var station_safe_nonmovement := base_station_safe_work + field_work_seconds + BASE_DECISION_SECONDS + field_decision_total
	var focus_safe_nonmovement := base_focus_safe_work + field_work_seconds + BASE_DECISION_SECONDS + field_decision_total
	var direct_nonmovement := base_direct_work + field_work_seconds + BASE_DECISION_SECONDS + field_decision_total
	var station_safe_active := station_safe_route_meters / PARTY_ROUTE_SPEED_METERS_PER_SECOND + station_safe_nonmovement
	var focus_safe_active := focus_safe_route_meters / PARTY_ROUTE_SPEED_METERS_PER_SECOND + focus_safe_nonmovement
	var direct_active := direct_route_meters / PARTY_ROUTE_SPEED_METERS_PER_SECOND \
		+ direct_nonmovement
	var clean_total := minf(station_safe_active, focus_safe_active) + ORIENTATION_SECONDS
	var station_clean_total := station_safe_active + ORIENTATION_SECONDS
	var shortest_active := minf(focus_safe_active, direct_active)
	var shortest_total := shortest_active + ORIENTATION_SECONDS
	var theoretical_sprint_total := minf(
		focus_safe_route_meters / THEORETICAL_SPRINT_SPEED_METERS_PER_SECOND + focus_safe_nonmovement,
		direct_route_meters / THEORETICAL_SPRINT_SPEED_METERS_PER_SECOND + direct_nonmovement
	) + ORIENTATION_SECONDS
	_playtime_contract_cache = {
		"target_seconds_min": 180.0,
		"target_seconds_max": 300.0,
		"modeled_shortest_first_clear_seconds": shortest_total,
		"modeled_clean_first_clear_seconds": clean_total,
		"modeled_station_marked_clean_seconds": station_clean_total,
		"modeled_theoretical_full_sprint_seconds": theoretical_sprint_total,
		"modeled_meaningful_active_seconds": shortest_active,
		"modeled_active_ratio": shortest_active / shortest_total,
		"safe_route_meters": minf(station_safe_route_meters, focus_safe_route_meters),
		"station_marked_safe_route_meters": station_safe_route_meters,
		"focus_safe_route_meters": focus_safe_route_meters,
		"direct_route_meters": direct_route_meters,
		"shortest_field_route_meters": field_route_meters,
		"route_meters_by_operation": operation_routes,
		"mandatory_action_count_clean": 4 + FIELD_OPERATIONS.size() * 7 + 2,
		"mandatory_timed_action_count_clean": 2 + FIELD_OPERATIONS.size() * 7 + 2,
		"station_marked_timed_action_count_clean": 3 + FIELD_OPERATIONS.size() * 7 + 2,
		"mandatory_field_evidence_count": FIELD_OPERATIONS.size() * 5,
		"decision_count": 1 + FIELD_OPERATIONS.size(),
		"branch_variant_count": 2 * int(pow(2, FIELD_OPERATIONS.size())),
		"timing_basis": "exact geometric shortest paths through authored evidence, Aster Focus safe-route shortcut, shortest valid execution branch, 2.5 m/s party pace, authored TIMED_ACTION dwell, explicit planning allowance; no dialogue, idle, or reset time counted",
	}
	return _playtime_contract_cache.duplicate(true)

func get_preview_overlay_status(overlay_id: String, _current_tick: float) -> Array:
	match overlay_id:
		"aster":
			return [
				"DATA: Endo's wall marks line up with a shelter symbol and three measured maintenance loops.",
				"Route: %s" % ("marked" if _safe_route_marked else "unresolved"),
				"Field loop: %s" % (_field_phase if _field_phase != "" else "locked"),
			]
		"peris":
			return [
				"FOG: the refuge feels lived-in, not abandoned.",
				"Plant memory: %s" % ("settling inside Shelter 1" if _shelter_reached else "pulling through the refuge signal"),
				"Food cache: %s" % ("collected" if _forage_collected else "still tucked in the wall"),
			]
		"endo":
			return [
				"SURVIVAL: junction -> route -> conduit -> signal -> refuge entry -> shelter.",
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
	_field_phase = ""
	_field_evidence.clear()
	_field_choices.clear()
	_field_operations_completed.clear()
	_field_effects.clear()
	_field_findings.clear()
	_set_preview_step("endo_junction_stretch_start")
	_reset_story_interactables()
	_reset_field_interactables()
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
			return {"note": "Aster needs Endo's junction-console read before TRACE has enough context."}
		"peris_tune":
			return {"characters": {"aster": {"sta_delta": 8.0}, "peris": {"sta_delta": 12.0}, "endo": {"sta_delta": 8.0}}}
		"endo_patch":
			if not _junction_read:
				return {"characters": {"endo": {"sta_delta": 8.0}}, "note": "Endo wakes the junction console and waits for the others to read his route."}
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
	if not _require_station("endo", JUNCTION_POS, "Endo's junction console"):
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
		_show_message("Endo needs to read the junction console first.", 1.3)
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
	if not _forage_collected:
		_show_message("Collect the junction cache before leaving the maintained sector.", 1.4)
		return false
	if not _require_station("endo", SAFE_LEDGE_POS, "the safe ledge"):
		return false
	_route_choice = "safe"
	_danger_resolved = true
	_route_phase = "fieldwork"
	_last_outcome = "clean_crossing"
	_mark_segment("safe_route")
	_set_preview_step("endo_junction_safe_route")
	_adjust_character_stat("endo", "sta", -6.0)
	_show_message("Endo threads the maintenance ledge without drawing the bloom.", 1.7)
	_complete_interactable(_safe_interactable)
	_complete_interactable(_direct_interactable)
	_start_field_operation("conduit")
	_update_visual_state()
	return true

func commit_direct_route() -> bool:
	if _danger_resolved:
		return _route_choice == "direct" and _party_min_hp() > 0.0
	if not _junction_read:
		_show_message("Endo needs to read the junction before anyone cuts the bloom.", 1.4)
		return false
	if not _forage_collected:
		_show_message("Collect the junction cache before spending health on the direct route.", 1.4)
		return false
	if not _require_station("", RISKY_BLOOM_POS, "the short bloom"):
		return false
	_route_choice = "direct"
	_danger_resolved = true
	_route_phase = "fieldwork"
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
	_start_field_operation("conduit")
	_update_visual_state()
	return _party_min_hp() > 0.0

func unlock_shortcut() -> bool:
	if not _danger_resolved:
		_show_message("Resolve the crossing before opening the return grate.", 1.2)
		return false
	if _field_operations_completed.size() < FIELD_OPERATIONS.size():
		_show_message("Finish the conduit, signal, and refuge-entry field loops first.", 1.4)
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
	if not _shortcut_unlocked:
		_show_message("Open the return grate before bedding the party down.", 1.2)
		return false
	if not _full_conscious_party_near(SHELTER_POS, SHELTER_RADIUS):
		_show_message("Bring Aster, Peris, and Endo into Shelter 1 conscious before resting.", 1.8)
		return false
	if not _party_can_pay_shelter_rest():
		_show_message("Everyone needs at least one ATP to survive the night.", 1.6)
		return false
	_apply_paid_shelter_rest()
	_shelter_reached = true
	_shelter_rested = true
	_route_phase = "complete"
	_last_outcome = "shelter_rested"
	_mark_segment("shelter")
	_set_preview_step("endo_junction_shelter_1")
	_fire_first_night_beat()
	_complete_interactable(_shelter_interactable)
	_update_visual_state()
	return true

func rest_shelter() -> bool:
	return reach_shelter()

func _build_shell() -> void:
	# The first-night palette still needs a readable physical surface when the compatibility
	# renderer (or the `fog off` diagnostic) bypasses the fullscreen perception pass. A low,
	# cool emission is applied by the final decoration material above so the textured deck remains.
	var route_floor := _add_floor(self, FLOOR_CENTER, FLOOR_SIZE, Color(0.12, 0.145, 0.165))
	route_floor.name = "EndoJunctionRouteFloor"
	_add_box(self, Vector3(17.0, 0.02, 0.0), Vector3(36.0, 0.035, 16.0),
		Color(0.105, 0.135, 0.15), Color(0.12, 0.28, 0.32), 0.48,
		"EndoJunctionEntryApron")
	var half_x := FLOOR_SIZE.x * 0.5
	var half_z := FLOOR_SIZE.z * 0.5
	_add_box(self, Vector3(FLOOR_CENTER.x, 2.2, -half_z - 0.1), Vector3(FLOOR_SIZE.x, 4.4, 0.3), Color(0.11, 0.13, 0.14))
	_add_box(self, Vector3(FLOOR_CENTER.x, 2.2, half_z + 0.1), Vector3(FLOOR_SIZE.x, 4.4, 0.3), Color(0.11, 0.13, 0.14))
	_add_box(self, Vector3(FLOOR_CENTER.x - half_x - 0.1, 2.2, 0.0), Vector3(0.3, 4.4, FLOOR_SIZE.z), Color(0.09, 0.11, 0.12))
	_add_box(self, Vector3(FLOOR_CENTER.x + half_x + 0.1, 2.2, 0.0), Vector3(0.3, 4.4, FLOOR_SIZE.z), Color(0.09, 0.11, 0.12))
	for i in range(16):
		var blend := float(i) / 15.0
		_add_light(self, Vector3(7.0 + float(i) * 17.2, 3.8, -1.0 + sin(float(i) * 1.7) * 1.4), Color(0.38 + blend * 0.2, 0.48 + blend * 0.1, 0.56 - blend * 0.08), 1.1 + blend * 0.65, 14.0)
	_add_label(self, "ENDO'S JUNCTION", JUNCTION_POS + Vector3(2.6, 2.7, -4.0), Color(0.68, 0.9, 0.74))
	_add_label(self, "SHELTER 1", SHELTER_POS + Vector3(0.0, 2.85, 0.0), Color(0.98, 0.82, 0.52))

func _build_junction() -> void:
	_junction_material = _make_material(Color(0.14, 0.16, 0.15), Color(0.52, 0.92, 0.66), 1.3)
	_add_box(self, JUNCTION_POS + Vector3(0.0, -0.02, 0.0), Vector3(9.0, 0.2, 8.0),
		Color(0.12, 0.16, 0.145), Color(0.24, 0.58, 0.36), 0.36,
		"EndoJunctionConsolePad")
	var station := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.45
	mesh.bottom_radius = 0.62
	mesh.height = 1.8
	station.mesh = mesh
	station.material_override = _junction_material
	station.position = JUNCTION_POS + Vector3(0.0, 0.9, 0.0)
	add_child(station)
	_build_entry_guide()
	_junction_interactable = _add_object_interactable(self, "EndoJunctionReadInteractable", "Endo's Junction Console", JUNCTION_POS, "ENDO: READ CONSOLE", [station], "endo", 0.0, false, INTERACT_RADIUS, Interactable.InteractableType.INSPECTION)
	_junction_interactable.interacted.connect(read_junction)

func _build_entry_guide() -> void:
	_entry_guide = Node3D.new()
	_entry_guide.name = "EndoJunctionEntryGuide"
	add_child(_entry_guide)
	var start: Vector3 = SPAWNS["endo"]
	var finish := Vector3(JUNCTION_POS.x, 0.04, JUNCTION_POS.z)
	start.y = 0.04
	for i in range(5):
		var t := float(i + 1) / 6.0
		var guide_pos := start.lerp(finish, t)
		_add_box(_entry_guide, guide_pos, Vector3(0.42, 0.04, 0.42),
			Color(0.08, 0.18, 0.12), Color(0.38, 1.0, 0.62), 1.45,
			"EndoJunctionEntryGuideDot%d" % i)
	for offset in [Vector3(1.05, 0.04, 0.0), Vector3(-1.05, 0.04, 0.0),
			Vector3(0.0, 0.04, 1.05), Vector3(0.0, 0.04, -1.05)]:
		_add_box(_entry_guide, JUNCTION_POS + offset, Vector3(0.5, 0.05, 0.5),
			Color(0.08, 0.18, 0.12), Color(0.38, 1.0, 0.62), 1.6)
	var guide_label := _add_label(_entry_guide, "ENDO: READ\nJUNCTION CONSOLE",
		JUNCTION_POS + Vector3(0.0, 2.45, 1.3), Color(0.7, 1.0, 0.78))
	guide_label.no_depth_test = true
	guide_label.render_priority = 2

func _build_route_marks() -> void:
	_add_box(self, WALL_MARKS_POS + Vector3(0.0, 0.5, -0.4), Vector3(8.5, 1.0, 0.18), Color(0.14, 0.16, 0.16), Color(0.44, 0.68, 0.58), 0.12)
	_add_label(self, "WALL MARKS", WALL_MARKS_POS + Vector3(0.0, 1.65, -0.4), Color(0.66, 0.9, 0.75))
	_route_interactable = _add_interactable(self, "EndoJunctionRouteMarkInteractable", "Translated Route Mark", GUIDE_MARK_POS, "MARK ROUTE", "aster", 3.4, false, INTERACT_RADIUS, Interactable.InteractableType.TIMED_ACTION, false)
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
	_cache_interactable = _add_object_interactable(self, "EndoJunctionCacheInteractable", "Wall Cache", FORAGE_CACHE_POS, "RECOVER CACHE", [cache], "endo", 4.0, false, INTERACT_RADIUS, Interactable.InteractableType.TIMED_ACTION)
	_cache_interactable.interacted.connect(collect_forage)

func _build_crossing() -> void:
	_safe_material = _make_material(Color(0.1, 0.16, 0.18), Color(0.52, 0.78, 0.86), 0.18)
	_direct_material = _make_material(Color(0.22, 0.1, 0.07), Color(0.86, 0.28, 0.12), 0.28)
	_add_box(self, SAFE_LEDGE_POS + Vector3(0.0, -0.02, 0.0), Vector3(17.0, 0.16, 3.0), Color(0.09, 0.14, 0.16), Color(0.38, 0.64, 0.72), 0.16)
	_add_label(self, "SAFE LEDGE", SAFE_LEDGE_POS + Vector3(0.0, 1.65, 0.0), Color(0.64, 0.88, 0.96))
	var safe_beacon := _add_box(self, SAFE_LEDGE_POS + Vector3(0.0, 0.55, 0.0), Vector3(0.55, 1.1, 0.55), Color(0.12, 0.25, 0.27), Color(0.52, 0.78, 0.86), 0.35)
	_safe_interactable = _add_object_interactable(self, "EndoJunctionSafeRouteInteractable", "Safe Ledge", SAFE_LEDGE_POS, "THREAD LEDGE", [safe_beacon], "endo", 4.2, false, INTERACT_RADIUS, Interactable.InteractableType.TIMED_ACTION)
	_safe_interactable.interacted.connect(commit_safe_route)
	_add_box(self, RISKY_BLOOM_POS + Vector3(0.0, -0.02, 0.0), Vector3(16.0, 0.16, 3.5), Color(0.18, 0.08, 0.055), Color(0.82, 0.22, 0.08), 0.24)
	_add_label(self, "SHORT BLOOM", RISKY_BLOOM_POS + Vector3(0.0, 1.65, 0.0), Color(0.98, 0.56, 0.32))
	var bloom_beacon := _add_box(self, RISKY_BLOOM_POS + Vector3(0.0, 0.55, 0.0), Vector3(0.55, 1.1, 0.55), Color(0.3, 0.1, 0.06), Color(0.92, 0.28, 0.1), 0.5)
	_direct_interactable = _add_object_interactable(self, "EndoJunctionDirectRouteInteractable", "Short Bloom", RISKY_BLOOM_POS, "CUT BLOOM", [bloom_beacon], "", 4.2, false, INTERACT_RADIUS, Interactable.InteractableType.TIMED_ACTION)
	_direct_interactable.interacted.connect(commit_direct_route)

func _build_fieldwork() -> void:
	var root := Node3D.new()
	root.name = "EndoJunctionFieldwork"
	add_child(root)
	var operation_index := 0
	for operation_id_variant in FIELD_OPERATIONS.keys():
		var operation_id := str(operation_id_variant)
		_build_field_operation_frame(root, operation_id, operation_index)
		var operation: Dictionary = FIELD_OPERATIONS[operation_id]
		var route_root := Node3D.new()
		route_root.name = "EndoJunctionRoute_%s" % operation_id
		root.add_child(route_root)
		_field_route_visuals[operation_id] = route_root
		var ordered_points: Array = [operation.get("start", Vector3.ZERO)]
		for evidence_id in operation.get("evidence", []):
			ordered_points.append(FIELD_SITES[str(evidence_id)].get("pos", Vector3.ZERO))
		for point_i in range(ordered_points.size() - 1):
			_add_field_datum(route_root, ordered_points[point_i], ordered_points[point_i + 1], operation.get("tint", Color.WHITE), "%s_evidence_%02d" % [operation_id, point_i])
		var last_evidence: Vector3 = ordered_points[-1]
		for choice_id_variant in operation.get("choices", []):
			var choice_id := str(choice_id_variant)
			var choice_pos: Vector3 = FIELD_SITES[choice_id].get("pos", Vector3.ZERO)
			var resolution_id := str((operation.get("resolution_sites", {}) as Dictionary).get(choice_id, ""))
			var resolution_pos: Vector3 = FIELD_SITES[resolution_id].get("pos", Vector3.ZERO)
			_add_field_datum(route_root, last_evidence, choice_pos, operation.get("tint", Color.WHITE), "%s_%s_choice" % [operation_id, choice_id])
			_add_field_datum(route_root, choice_pos, resolution_pos, operation.get("tint", Color.WHITE), "%s_%s_execute" % [operation_id, choice_id])
			_add_field_datum(route_root, resolution_pos, operation.get("end", Vector3.ZERO), operation.get("tint", Color.WHITE), "%s_%s_exit" % [operation_id, choice_id])
		operation_index += 1

	for site_id_variant in FIELD_SITES.keys():
		var site_id := str(site_id_variant)
		_build_field_site(root, site_id)

func _build_field_operation_frame(parent: Node3D, operation_id: String, operation_index: int) -> void:
	var operation: Dictionary = FIELD_OPERATIONS[operation_id]
	var start: Vector3 = operation.get("start", Vector3.ZERO)
	var end: Vector3 = operation.get("end", Vector3.ZERO)
	var center_x := (start.x + end.x) * 0.5
	var length := end.x - start.x
	var tint: Color = operation.get("tint", Color(0.4, 0.7, 0.6))
	var frame := Node3D.new()
	frame.name = "EndoJunctionFieldFrame_%s" % operation_id
	parent.add_child(frame)
	# Each operation reads as a constructed maintenance hall: recessed floor field, continuous
	# side races, repeated portal frames, a high service spine, and a numbered datum sign.
	_add_box(frame, Vector3(center_x, 0.012, 0.0), Vector3(length - 1.2, 0.024, 33.0), Color(0.045, 0.06, 0.062))
	_add_box(frame, Vector3(center_x, 0.032, -15.3), Vector3(length - 0.8, 0.035, 0.72), Color(0.055, 0.10, 0.105), tint, 0.12)
	_add_box(frame, Vector3(center_x, 0.032, 15.3), Vector3(length - 0.8, 0.035, 0.72), Color(0.055, 0.10, 0.105), tint, 0.12)
	_add_box(frame, Vector3(center_x, 3.95, 0.0), Vector3(length - 2.0, 0.18, 0.34), Color(0.18, 0.22, 0.21), tint, 0.08)
	var portal_x := start.x + 3.0
	var portal_index := 0
	while portal_x < end.x - 1.0:
		_add_box(frame, Vector3(portal_x, 2.0, -16.0), Vector3(0.28, 4.0, 0.38), Color(0.25, 0.29, 0.27))
		_add_box(frame, Vector3(portal_x, 2.0, 16.0), Vector3(0.28, 4.0, 0.38), Color(0.25, 0.29, 0.27))
		_add_box(frame, Vector3(portal_x, 3.92, 0.0), Vector3(0.28, 0.22, 32.3), Color(0.25, 0.29, 0.27))
		if portal_index % 2 == 0:
			_add_box(frame, Vector3(portal_x, 0.035, 0.0), Vector3(0.07, 0.03, 28.0), Color(0.12, 0.16, 0.16), tint, 0.16)
		portal_x += 12.0
		portal_index += 1
	_add_box(frame, Vector3(start.x + 4.5, 2.0, -20.9), Vector3(8.0, 2.4, 0.16), Color(0.055, 0.075, 0.075), tint, 0.18)
	_add_label(frame, "%02d // %s" % [operation_index + 1, str(operation.get("label", operation_id))], Vector3(start.x + 4.5, 2.0, -20.65), tint.lightened(0.22))
	var landmark := _add_light(frame, Vector3(center_x, 3.3, 0.0), tint, 1.15, 15.0)
	landmark.name = "EndoJunctionFieldLight_%s" % operation_id

func _build_field_site(parent: Node3D, site_id: String) -> void:
	var spec: Dictionary = FIELD_SITES[site_id]
	var position: Vector3 = spec.get("pos", Vector3.ZERO)
	var role := str(spec.get("role", ""))
	var kind := str(spec.get("kind", "evidence"))
	var role_color := _field_role_color(role)
	var operation: Dictionary = FIELD_OPERATIONS[str(spec.get("operation", ""))]
	var tint: Color = operation.get("tint", role_color)
	var base_color := role_color.darkened(0.52)
	var base := _add_box(parent, position + Vector3(0.0, 0.18, 0.0), Vector3(1.75, 0.36, 1.75), base_color, tint, 0.1)
	var post_height := 1.15 if kind == "evidence" else 1.45
	var post := _add_box(parent, position + Vector3(0.0, 0.36 + post_height * 0.5, 0.0), Vector3(0.42, post_height, 0.42), role_color.darkened(0.38), role_color, 0.24)
	var lens := MeshInstance3D.new()
	var lens_mesh := SphereMesh.new()
	lens_mesh.radius = 0.26 if kind == "evidence" else 0.34
	lens_mesh.height = lens_mesh.radius * 2.0
	lens.mesh = lens_mesh
	lens.material_override = _make_material(tint.darkened(0.3), tint, 0.48 if kind == "resolution" else 0.28)
	lens.position = position + Vector3(0.0, 0.5 + post_height, 0.0)
	parent.add_child(lens)
	var node_name := "EndoJunctionField_%s" % site_id
	var interactable := _add_object_interactable(parent, node_name, str(spec.get("display", site_id)), position, str(spec.get("verb", "WORK")), [base, post, lens], role, float(spec.get("dwell", 3.5)), false, INTERACT_RADIUS, Interactable.InteractableType.TIMED_ACTION)
	interactable.interacted.connect(_on_field_site_interacted.bind(site_id))
	_field_sites[site_id] = interactable
	_add_label(parent, "%s // %s" % [_display_name(role).to_upper(), str(spec.get("display", site_id))], position + Vector3(0.0, 2.25, 0.0), role_color.lightened(0.22))

func _add_field_datum(parent: Node3D, from: Vector3, to: Vector3, tint: Color, suffix: String) -> MeshInstance3D:
	var flat_from := Vector3(from.x, 0.045, from.z)
	var flat_to := Vector3(to.x, 0.045, to.z)
	var delta := flat_to - flat_from
	var datum := _add_box(parent, (flat_from + flat_to) * 0.5, Vector3(delta.length(), 0.025, 0.075), tint.darkened(0.48), tint, 0.24, "EndoJunctionDatum_%s" % suffix)
	datum.rotation.y = -atan2(delta.z, delta.x)
	return datum

func _field_role_color(role: String) -> Color:
	match role:
		"aster": return Color(0.42, 0.72, 0.95)
		"peris": return Color(0.42, 0.88, 0.58)
		"endo": return Color(0.96, 0.67, 0.30)
		_: return Color(0.82, 0.86, 0.9)

func complete_field_site(site_id: String) -> bool:
	# Headless/shared drivers use the same public gate after selecting and positioning the required
	# specialist. Real input reaches this state through the click-gated TIMED_ACTION signal above.
	if not FIELD_SITES.has(site_id) or not _field_sites.has(site_id):
		return false
	var spec: Dictionary = FIELD_SITES[site_id]
	var site: Node = _field_sites[site_id]
	if not site.is_interaction_enabled():
		return false
	if not _require_station(str(spec.get("role", "")), spec.get("pos", Vector3.ZERO), str(spec.get("display", site_id))):
		return false
	return _resolve_field_site_state(site_id)

func _on_field_site_interacted(site_id: String) -> void:
	_resolve_field_site_state(site_id)

func _resolve_field_site_state(site_id: String) -> bool:
	if not FIELD_SITES.has(site_id):
		return false
	var spec: Dictionary = FIELD_SITES[site_id]
	var operation_id := str(spec.get("operation", ""))
	if operation_id != _field_phase or not FIELD_OPERATIONS.has(operation_id):
		return false
	var site: Node = _field_sites.get(site_id)
	if site == null or not site.is_interaction_enabled():
		return false
	var kind := str(spec.get("kind", "evidence"))
	var finding := str(spec.get("finding", ""))
	if finding != "":
		_field_findings.append(finding)
		_show_message(finding, 2.0)
	match kind:
		"evidence":
			var completed: Dictionary = _field_evidence.get(operation_id, {})
			if bool(completed.get(site_id, false)):
				return true
			completed[site_id] = true
			_field_evidence[operation_id] = completed
			_mark_segment(site_id)
			_set_field_site_enabled(site_id, false)
			if _field_operation_evidence_complete(operation_id):
				for choice_id in FIELD_OPERATIONS[operation_id].get("choices", []):
					_set_field_site_enabled(str(choice_id), true)
			return true
		"choice":
			if not _field_operation_evidence_complete(operation_id):
				return false
			_field_choices[operation_id] = site_id
			for choice_id in FIELD_OPERATIONS[operation_id].get("choices", []):
				_set_field_site_enabled(str(choice_id), false)
			var resolution_sites: Dictionary = FIELD_OPERATIONS[operation_id].get("resolution_sites", {})
			var resolution_id := str(resolution_sites.get(site_id, ""))
			if resolution_id == "":
				return false
			_set_field_site_enabled(resolution_id, true)
			_route_phase = "%s_execution" % operation_id
			return true
		"resolution":
			var committed_choice := str(_field_choices.get(operation_id, ""))
			var expected_resolution := str((FIELD_OPERATIONS[operation_id].get("resolution_sites", {}) as Dictionary).get(committed_choice, ""))
			if site_id != expected_resolution:
				return false
			_set_field_site_enabled(site_id, false)
			_field_operations_completed[operation_id] = true
			_mark_segment("%s_complete" % operation_id)
			_apply_field_choice(operation_id, committed_choice)
			var next_id := str(FIELD_OPERATIONS[operation_id].get("next", ""))
			if next_id == "":
				_field_phase = "complete"
				_route_phase = "fieldwork_complete"
				_set_preview_step("endo_junction_fieldwork_complete")
				_show_note("The conduit, signal, and refuge entry are secured. Open Endo's return grate.", 3.0)
			else:
				_start_field_operation(next_id)
			return true
	return false

func _start_field_operation(operation_id: String) -> void:
	if not FIELD_OPERATIONS.has(operation_id):
		return
	_field_phase = operation_id
	_route_phase = "%s_survey" % operation_id
	if not _field_evidence.has(operation_id):
		_field_evidence[operation_id] = {}
	for site_id_variant in FIELD_SITES.keys():
		var site_id := str(site_id_variant)
		var spec: Dictionary = FIELD_SITES[site_id]
		_set_field_site_enabled(site_id, str(spec.get("operation", "")) == operation_id and str(spec.get("kind", "")) == "evidence" and not bool((_field_evidence.get(operation_id, {}) as Dictionary).get(site_id, false)))
	_set_preview_step("endo_junction_%s_survey" % operation_id)
	_show_note("%s: gather all five specialist reads, choose a plan, then execute it in the corridor." % str(FIELD_OPERATIONS[operation_id].get("label", operation_id)), 3.0)
	_update_visual_state()

func _field_operation_evidence_complete(operation_id: String) -> bool:
	if not FIELD_OPERATIONS.has(operation_id):
		return false
	var completed: Dictionary = _field_evidence.get(operation_id, {})
	for site_id in FIELD_OPERATIONS[operation_id].get("evidence", []):
		if not bool(completed.get(str(site_id), false)):
			return false
	return true

func _apply_field_choice(operation_id: String, choice_id: String) -> void:
	match choice_id:
		"conduit_brace":
			_field_effects["conduit_mode"] = "dry_service_brace"
			_adjust_character_stat("endo", "sta", -4.0)
		"conduit_buffer":
			_field_effects["conduit_mode"] = "living_root_buffer"
			for char_id in ["aster", "peris", "endo"]:
				_adjust_character_stat(char_id, "sta", 4.0)
		"signal_memory_beacon":
			_field_effects["signal_mode"] = "living_memory"
		"signal_data_beacon":
			_field_effects["signal_mode"] = "measured_echo"
		"approach_warm":
			_field_effects["entry_mode"] = "warm_recovery"
			for char_id in ["aster", "peris", "endo"]:
				_adjust_character_stat(char_id, "hp", 3.0)
		"approach_sealed":
			_field_effects["entry_mode"] = "hard_boundary"
			_adjust_character_stat("endo", "sta", -4.0)
	_field_effects["last_operation"] = operation_id

func _set_field_site_enabled(site_id: String, enabled: bool) -> void:
	var site: Node = _field_sites.get(site_id)
	if site != null and site.has_method("set_interaction_enabled"):
		site.call("set_interaction_enabled", enabled)

func _reset_field_interactables() -> void:
	for site_id in _field_sites.keys():
		var site: Node = _field_sites[site_id]
		if site.has_method("reset"):
			site.call("reset")
		_set_field_site_enabled(str(site_id), false)

func _build_hide_and_shortcut() -> void:
	_add_box(self, HIDE_SLOT_POS + Vector3(0.0, -0.03, 0.0), Vector3(7.0, 0.18, 3.2), Color(0.07, 0.11, 0.1))
	_add_box(self, HIDE_SLOT_POS + Vector3(-3.3, 1.2, 0.0), Vector3(0.25, 2.4, 3.2), Color(0.1, 0.14, 0.12))
	_add_label(self, "HIDE SLOT", HIDE_SLOT_POS + Vector3(0.0, 1.8, 0.0), Color(0.62, 0.88, 0.68))
	_shortcut_material = _make_material(Color(0.15, 0.15, 0.14), Color(0.9, 0.76, 0.42), 0.14)
	var grate := _add_box(self, SHORTCUT_LOCK_POS + Vector3(0.0, 0.45, 0.0), Vector3(2.2, 0.9, 2.2), Color(0.16, 0.14, 0.12), Color(0.82, 0.62, 0.28), 0.16)
	grate.material_override = _shortcut_material
	_add_label(self, "RETURN GRATE", SHORTCUT_LOCK_POS + Vector3(0.0, 1.7, 0.0), Color(0.94, 0.78, 0.46))
	_shortcut_interactable = _add_object_interactable(self, "EndoJunctionShortcutInteractable", "Return Grate", SHORTCUT_LOCK_POS, "OPEN GRATE", [grate], "endo", 4.0, false, INTERACT_RADIUS, Interactable.InteractableType.TIMED_ACTION)
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
	# A real refuge composition: warm central hearth, two bed platforms, dry stores, a threshold
	# canopy, and wall ribs. These stay clear of the hearth interaction radius.
	_add_box(self, SHELTER_POS + Vector3(-2.8, 0.28, -2.55), Vector3(3.2, 0.5, 1.35), Color(0.24, 0.19, 0.12), Color(0.75, 0.48, 0.2), 0.08)
	_add_box(self, SHELTER_POS + Vector3(-2.8, 0.28, 2.55), Vector3(3.2, 0.5, 1.35), Color(0.24, 0.19, 0.12), Color(0.75, 0.48, 0.2), 0.08)
	_add_box(self, SHELTER_POS + Vector3(2.9, 0.65, -2.6), Vector3(1.45, 1.3, 1.5), Color(0.18, 0.16, 0.12))
	_add_box(self, SHELTER_POS + Vector3(2.9, 1.55, -2.6), Vector3(1.65, 0.18, 1.7), Color(0.34, 0.28, 0.18))
	for rib_z in [-3.55, 3.55]:
		_add_box(self, SHELTER_POS + Vector3(0.0, 2.15, float(rib_z)), Vector3(9.2, 0.18, 0.22), Color(0.42, 0.34, 0.22))
	_add_label(self, "HEARTH // REST", SHELTER_POS + Vector3(0.0, 2.15, 0.0), Color(1.0, 0.82, 0.5))
	_add_light(self, SHELTER_POS + Vector3(0.0, 2.1, 0.0), Color(1.0, 0.74, 0.38), 2.0, 11.5)
	_shelter_interactable = _add_object_interactable(self, "EndoJunctionShelterInteractable", "Shelter 1 Hearth", SHELTER_POS, "REST PARTY", [hearth], "", 3.0, false, SHELTER_RADIUS, Interactable.InteractableType.TIMED_ACTION)
	_shelter_interactable.interacted.connect(reach_shelter)
	# The hearth room is a SHELTER: register the sanctuary region the detection/strike gates and
	# the revive watch read (a shelter that is only a room lets enemies attack you inside it —
	# the 2026-07-12 report). Sized to the built room slab (10 x 8 around SHELTER_POS).
	var gs = _get_game_state()
	if gs != null and gs.has_method("add_shelter_region"):
		gs.add_shelter_region(Vector2(SHELTER_POS.x - 5.0, SHELTER_POS.z - 4.0),
			Vector2(SHELTER_POS.x + 5.0, SHELTER_POS.z + 4.0))

func _update_stretch(_delta: float) -> void:
	# Shelter completion is intentionally interaction-gated. Merely crossing the
	# hearth radius must never skip the food check or rest the party for free.
	pass

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

func _full_conscious_party_near(position: Vector3, radius: float) -> bool:
	var gs = _get_game_state()
	if gs == null:
		return false
	for char_id in ["aster", "peris", "endo"]:
		if not gs.characters.has(char_id) or gs.is_downed(char_id):
			return false
		if _get_character_position(char_id).distance_to(position) > radius:
			return false
	return true

func _party_can_pay_shelter_rest() -> bool:
	var gs = _get_game_state()
	if gs == null:
		return false
	for char_id in ["aster", "peris", "endo"]:
		if not gs.characters.has(char_id) or gs.get_stat(char_id, "atp") < SHELTER_ATP_COST:
			return false
	return true

func _party_min_hp() -> float:
	var min_hp := 999.0
	for char_id in ["aster", "peris", "endo"]:
		min_hp = minf(min_hp, _get_character_stat(char_id, "hp"))
	return min_hp

func _apply_paid_shelter_rest() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for char_id in ["aster", "peris", "endo"]:
		gs.adjust_stat(char_id, "atp", -SHELTER_ATP_COST)
		gs.set_stat(char_id, "hp", gs.get_stat_cap(char_id, "hp"))
		gs.set_stat(char_id, "stamina", gs.get_stat_cap(char_id, "stamina"))
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
	_show_note("Shelter 1 reached. The full party spends one ATP each and beds down for the first night.", 4.0)

func _mark_segment(segment: String) -> void:
	if not _segments_completed.has(segment):
		_segments_completed.append(segment)

func _shortest_field_operation_route(operation_id: String) -> float:
	if not FIELD_OPERATIONS.has(operation_id):
		return 0.0
	var operation: Dictionary = FIELD_OPERATIONS[operation_id]
	var evidence_positions: Array[Vector3] = []
	for site_id in operation.get("evidence", []):
		evidence_positions.append(FIELD_SITES[str(site_id)].get("pos", Vector3.ZERO))
	var best := INF
	for choice_id_variant in operation.get("choices", []):
		var choice_id := str(choice_id_variant)
		var choice_pos: Vector3 = FIELD_SITES[choice_id].get("pos", Vector3.ZERO)
		var resolution_id := str((operation.get("resolution_sites", {}) as Dictionary).get(choice_id, ""))
		var resolution_pos: Vector3 = FIELD_SITES[resolution_id].get("pos", Vector3.ZERO)
		var branch_tail := choice_pos.distance_to(resolution_pos) + resolution_pos.distance_to(operation.get("end", Vector3.ZERO))
		var evidence_route := _shortest_path_through_points(operation.get("start", Vector3.ZERO), evidence_positions, (1 << evidence_positions.size()) - 1, choice_pos)
		best = minf(best, evidence_route + branch_tail)
	return 0.0 if is_inf(best) else best

func _shortest_path_through_points(current: Vector3, points: Array[Vector3], remaining_mask: int, tail: Vector3) -> float:
	if remaining_mask == 0:
		return current.distance_to(tail)
	var best := INF
	for point_i in range(points.size()):
		var bit := 1 << point_i
		if (remaining_mask & bit) == 0:
			continue
		best = minf(best, current.distance_to(points[point_i]) + _shortest_path_through_points(points[point_i], points, remaining_mask & ~bit, tail))
	return best

func _current_instruction() -> String:
	if FIELD_OPERATIONS.has(_field_phase):
		var operation: Dictionary = FIELD_OPERATIONS[_field_phase]
		if not _field_operation_evidence_complete(_field_phase):
			var completed: Dictionary = _field_evidence.get(_field_phase, {})
			return "%s reads %d/%d" % [str(operation.get("label", _field_phase)).to_lower(), completed.size(), operation.get("evidence", []).size()]
		var choice := str(_field_choices.get(_field_phase, ""))
		if choice == "":
			return "choose the %s plan" % str(operation.get("label", _field_phase)).to_lower()
		return "execute %s" % str(FIELD_SITES[choice].get("display", choice)).to_lower()
	match _route_phase:
		"junction":
			return "bring Endo to the glowing junction console and read it"
		"junction_read":
			return "have Aster mark the safe route"
		"safe_marked":
			return "collect the cache or commit the ledge"
		"foraged":
			return "choose ledge or short bloom"
		"fieldwork_complete":
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
		_junction_material.emission_energy_multiplier = 0.35 if _junction_read else 1.3
	if _entry_guide != null:
		_entry_guide.visible = not _junction_read
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
