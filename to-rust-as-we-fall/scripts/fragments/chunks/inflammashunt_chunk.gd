extends "res://scripts/fragments/chunks/data_fragment_chunk.gd"

## THE INFLAMMASHUNT (danger zone; canonical spec data/puzzles/inflammashunt_puzzle.md, shadow
## path inflammashunt_shadow_solution.md): the Resolution Catalyst retrieval — the Manage
## Conflict puzzle. Three character-coded INFORMATION routes feed a shared eight-interactable
## junction room; every route report is honest and confidently WRONG; the correct solve is
## "water, clean, clean, tend, open, physically retrieve". Route info is EFFICIENCY, not a gate (informed holds are
## short, uninformed holds are long); every wrong approach teaches exactly one rule and is
## recoverable without a reload (the hostile-root herding sub-puzzle is the largest recovery).
## The survival clock is OFF in here — danger is local state, not day/night attrition
## (GDD §10.2). Myke's value is information: scraping is general labor, so Aster+Peris can
## shadow-solve by reconstructing route C from routes A+B plus junction observation.

# --- Geometry (single floor; grid cs 1.5, origin z -16.5) ---
const APPROACH_X1 := 16.0
const HUB_X0 := 16.0
const HUB_X1 := 27.0
const HUB_HALF_Z := 6.0
const JCT_X0 := 30.0
const JCT_X1 := 55.5
const JCT_HALF_Z := 8.5
const ROUTE_X0 := 19.0
const ROUTE_X1 := 25.0
const POCKET := [29.5, 35.5, -14.5, -10.0]   # myke's crawl pocket [x0, x1, z0, z1]

const CHAR_A_POS := Vector3(34.0, 0.0, -2.0)
const CHAR_B_POS := Vector3(44.0, 0.0, 5.0)
const ROOT_BASE_POS := Vector3(45.2, 0.0, 5.8)
const VALVE_POS := Vector3(38.0, 0.6, -7.4)
const TERMINAL_POS := Vector3(42.0, 0.6, -7.4)
const RING_CENTER := Vector3(48.0, 0.0, 1.5)
const FLORA_POS := Vector3(32.5, 0.0, 6.8)
const HOUSING_POS := Vector3(51.5, 0.0, 5.5)
const GRATE_POS := Vector3(53.2, 0.0, 5.5)
const SAC_SOURCE_POS := FLORA_POS + Vector3(1.3, 0.3, 0.4)

# --- Tuning (spec values) ---
const SAC_DURATION := 22.0
const SAC_AURA := 3.0
const ROOT_CAPTURE_RADIUS := 1.5
const ROOT_RETRACT_DELAY := 1.0
const ROOT_REGROW_DELAY := 4.0
const RAGE_SECS := 16.0
const BUFFER_REFORM_SECS := 4.0
const POPCORN_DPS_TICK := 2.5
const HazardFieldScript := preload("res://scripts/game/objects/hazard_field.gd")
const WATER_FLOW_DURATION := 1.6
const ROOT_CONNECT_DURATION := 2.4
const HOUSING_OPEN_DURATION := 1.4
const INFLAMMASHUNT_AUTHORITY_VERSION := 5
const INFLAMMASHUNT_AUTHORITY_KEY := "chunk:inflammashunt:runtime"
const INTERACTION_POSITION_TOLERANCE := 0.2
const SHARED_POLL_INTERVAL := 0.5
const ROOT_POLL_INTERVAL := 0.35
const DEVICE_ITEM_TYPE := "cure_component"
const DEVICE_VISUAL_SCENE := "res://scenes/props/inflammashunt/resolution_catalyst.tscn"
const DEVICE_SOURCE_POS := HOUSING_POS + Vector3(0.0, 0.16, 0.0)
const DEVICE_PHASE_AVAILABLE := "available"
const DEVICE_PHASE_CLAIMING := "claiming"
const DEVICE_PHASE_CLAIMED := "claimed"

const ACTION_ASTER_LOG := "aster_log"
const ACTION_PIPE_DIAGRAM := "pipe_diagram"
const ACTION_DEAD_ROOTS := "dead_roots"
const ACTION_LIVING_JUNCTION := "living_junction"
const ACTION_GRATE_OBSERVATION := "grate_observation"
const ACTION_DEVICE_GAP := "device_gap"
const ACTION_VALVE := "valve"
const ACTION_CHAR_A := "char_a"
const ACTION_CHAR_B := "char_b"
const ACTION_TEND_ROOT := "tend_root"
const ACTION_EXAMINE_CLUSTER := "examine_cluster"
const ACTION_OBSERVE_FEEDING := "observe_feeding"
const ACTION_STRIKE_CLUSTER := "strike_cluster"
const ACTION_TEND_FLORA := "tend_flora"
const ACTION_TAKE_SAC := "take_sac"
const ACTION_HACK_TERMINAL := "hack_terminal"
const ACTION_THERMAL_RESET := "thermal_reset"
const ACTION_OPEN_HOUSING := "open_housing"
const ACTION_TAKE_DEVICE := "take_device"

## Hold-time table (spec "Route Information As Efficiency"): [with info, without info].
const HOLDS := {
	"valve": [2.5, 14.0],
	"char_a": [2.0, 10.0],
	"char_b": [2.5, 11.0],
	"root": [2.5, 12.0],
}

# --- Core state model (spec field names; exposed via headless_get_state) ---
var route_info := {
	"aster_log": false,
	"aster_pipe_diagram": false,
	"peris_dead_roots": false,
	"peris_living_junction": false,
	"myke_char_feed": false,
	"myke_buffer_ring": false,
}
var valve_open := false
var water_phase := "dry"        # dry, flowing, full
var water_deadline := -1.0
var char_a_state := "dry"        # dry, damp, cleared, burned
var char_b_state := "dry"
var root_state := "suppressed"   # suppressed, tame, hostile, recovering, connecting, connected
var root_connect_deadline := -1.0
var buffer_state := "stable"     # stable, shattered, reforming
var gas_sac_state := "idle"      # idle, tended, claiming, active, expired, ignited
var healing_zone := 0.0
var housing_unlocked := false
var housing_state := "sealed"    # sealed, opening, open
var housing_deadline := -1.0
# Compatibility/read-model cache. The source-tagged GameState item and transaction phase below are
# authoritative; opening the lid alone never changes this value.
var device_retrieved := false
var wrong_events: Array = []
var long_hold_count := 0

var _party: Array = ["aster", "peris", "myke"]
var _entry_played := false
var _reports := {}               # route -> true once the confident wrong answer played
var _reunion_played := false
var _popcorn := false
var _popcorn_field = null
var _sac_item_id := ""
# Presentation/cache only. Ownership lives in GameState.items and may change through ordinary
# drop/transfer commands without a bespoke chunk command.
var _sac_carrier := ""
var _sac_expires := -1.0
var _rage_until := -1.0
var _raged := {}                 # chelator id -> true while in the woken encounter
var _extra_chelators: Array = []
var _root_enemy: ChainEnemy
var _whip_ready := {}
var _polls_armed := false
var _shared_poll_deadline := -1.0
var _root_timer_mode := ""
var _root_deadline := -1.0
var _buffer_reform_deadline := -1.0
var _restoring_inflammashunt_authority := false
var _healing_glow: MeshInstance3D
var _char_a_mesh: MeshInstance3D
var _char_b_mesh: MeshInstance3D
var _husks: Array = []
var _water_route_segments: Array[MeshInstance3D] = []
var _root_filament_segments: Array[MeshInstance3D] = []
var _housing_lid_pivot: Node3D
var _housing_lid: MeshInstance3D
var _device_item_id := ""
var _device_phase := DEVICE_PHASE_AVAILABLE
var _device_claimed_by := ""
var _device_claim_serial := 0
var _sac_claim_serial := 0
var _terminal_hacked := false
## Per-action monotonic GameState trigger identities already incorporated into the saved semantic
## model. A GameState trigger whose count is newer than this map is an accepted-source-before-
## callback snapshot and owns no consequence; restore re-arms that exact source.
var _source_committed_counts := {}
var _interaction_sources := {}
var _active_source_receipt := {}

var _valve_it: Area3D
var _char_a_it: Area3D
var _char_b_it: Area3D
var _root_it: Area3D
var _flora_it: Area3D
var _take_sac_it: Area3D
var _terminal_it: Area3D
var _reset_it: Area3D
var _housing_it: Area3D
var _device_it: Area3D
var _examine_it: Area3D
var _strike_it: Area3D
var _observe_it: Area3D

func get_scene_title() -> String:
	return "The Inflammashunt (danger zone)"

func get_default_character() -> String:
	return "aster"

func configure_chunk(config: Dictionary) -> void:
	super.configure_chunk(config)
	if config.has("party"):
		_party = (config["party"] as Array).duplicate()

## The presence map drives the host's opt-in roster (myke exists only where a chunk asks).
func get_party_presence() -> Dictionary:
	return {
		"aster": _party.has("aster"),
		"peris": _party.has("peris"),
		"endo": _party.has("endo"),
		"myke": _party.has("myke"),
	}

func _build_chunk() -> void:
	fragment = _inflammashunt_fragment()
	super._build_chunk()
	_build_approach()
	_build_routes()
	_build_junction_room()
	_ensure_popcorn_field()
	_spawn_active_chelators()
	_refresh_hold_times()
	_apply_inflammashunt_presenters()
	_publish_inflammashunt_authority()

func _update(delta: float) -> void:
	super._update(delta)
	_ensure_polls()
	_sync_transition_presenters()

# --- The fragment (floors, walls, grid, spawns) ---

func _inflammashunt_fragment() -> Fragment:
	var frag := Fragment.new()
	frag.id = "inflammashunt"
	frag.title = "The Inflammashunt"
	frag.help = "Myke's old corridors. Salvageable working tech somewhere past the burn damage."
	frag.default_character = "aster"
	frag.party_ids = PackedStringArray(_party)
	var spawn_slots := {
		"aster": Vector3(4.0, 0.5, 0.0),
		"peris": Vector3(2.5, 0.5, 1.6),
		"myke": Vector3(2.5, 0.5, -1.6),
		"endo": Vector3(1.0, 0.5, 0.0),
	}
	frag.spawns = {}
	for cid in _party:
		if spawn_slots.has(cid):
			frag.spawns[cid] = spawn_slots[cid]
	var scorch := Color(0.09, 0.08, 0.075)
	frag.floors = [
		{"pos": Vector3(8.0, -0.05, 0.0), "size": Vector3(16.0, 0.1, 6.4), "color": scorch, "tile": "deck_metal"},
		{"pos": Vector3(21.5, -0.05, 0.0), "size": Vector3(11.0, 0.1, HUB_HALF_Z * 2.0), "color": scorch, "tile": "deck_metal"},
		{"pos": Vector3(22.0, -0.05, -9.75), "size": Vector3(6.5, 0.1, 7.9), "color": scorch, "tile": "deck_metal"},
		{"pos": Vector3(22.0, -0.05, 9.75), "size": Vector3(6.5, 0.1, 7.9), "color": Color(0.08, 0.09, 0.08), "tile": "deck_metal"},
		{"pos": Vector3(28.5, -0.05, 0.0), "size": Vector3(3.5, 0.1, 3.2), "color": scorch, "tile": "deck_metal"},
		{"pos": Vector3(42.75, -0.05, 0.0), "size": Vector3(25.5, 0.1, JCT_HALF_Z * 2.0), "color": Color(0.1, 0.095, 0.09), "tile": "deck_metal"},
		{"pos": Vector3(32.5, -0.05, -12.25), "size": Vector3(6.0, 0.1, 4.5), "color": Color(0.07, 0.065, 0.06), "tile": "deck_metal"},
	]
	var wallc := Color(0.06, 0.055, 0.05)
	frag.walls = [
		{"pos": Vector3(8.0, 1.5, 3.3), "size": Vector3(16.0, 3.0, 0.4), "color": wallc},
		{"pos": Vector3(8.0, 1.5, -3.3), "size": Vector3(16.0, 3.0, 0.4), "color": wallc},
		# hub shell (gaps: south+north route doors, east junction door)
		{"pos": Vector3(17.8, 1.5, -6.2), "size": Vector3(4.6, 3.0, 0.4), "color": wallc},
		{"pos": Vector3(25.6, 1.5, -6.2), "size": Vector3(3.6, 3.0, 0.4), "color": wallc},
		{"pos": Vector3(17.8, 1.5, 6.2), "size": Vector3(4.6, 3.0, 0.4), "color": wallc},
		{"pos": Vector3(25.6, 1.5, 6.2), "size": Vector3(3.6, 3.0, 0.4), "color": wallc},
		{"pos": Vector3(27.2, 1.5, -4.0), "size": Vector3(0.4, 3.0, 4.6), "color": wallc},
		{"pos": Vector3(27.2, 1.5, 4.0), "size": Vector3(0.4, 3.0, 4.6), "color": wallc},
		# route shells
		{"pos": Vector3(18.8, 1.5, -9.75), "size": Vector3(0.4, 3.0, 7.9), "color": wallc},
		{"pos": Vector3(25.2, 1.5, -9.75), "size": Vector3(0.4, 3.0, 7.9), "color": wallc},
		{"pos": Vector3(22.0, 1.5, -13.9), "size": Vector3(6.8, 3.0, 0.4), "color": wallc},
		{"pos": Vector3(18.8, 1.5, 9.75), "size": Vector3(0.4, 3.0, 7.9), "color": wallc},
		{"pos": Vector3(25.2, 1.5, 9.75), "size": Vector3(0.4, 3.0, 7.9), "color": wallc},
		{"pos": Vector3(22.0, 1.5, 13.9), "size": Vector3(6.8, 3.0, 0.4), "color": wallc},
		# junction shell
		{"pos": Vector3(42.75, 1.5, -8.9), "size": Vector3(25.5, 3.0, 0.4), "color": wallc},
		{"pos": Vector3(42.75, 1.5, 8.9), "size": Vector3(25.5, 3.0, 0.4), "color": wallc},
		{"pos": Vector3(55.9, 1.5, 0.0), "size": Vector3(0.4, 3.0, 18.2), "color": wallc},
		{"pos": Vector3(29.8, 1.5, -5.25), "size": Vector3(0.4, 3.0, 7.3), "color": wallc},
		{"pos": Vector3(29.8, 1.5, 5.25), "size": Vector3(0.4, 3.0, 7.3), "color": wallc},
		# the crawl pocket's sealed shell
		{"pos": Vector3(32.5, 1.2, -9.8), "size": Vector3(6.4, 2.4, 0.4), "color": wallc},
		{"pos": Vector3(32.5, 1.2, -14.7), "size": Vector3(6.4, 2.4, 0.4), "color": wallc},
		{"pos": Vector3(29.3, 1.2, -12.25), "size": Vector3(0.4, 2.4, 4.9), "color": wallc},
		{"pos": Vector3(35.7, 1.2, -12.25), "size": Vector3(0.4, 2.4, 4.9), "color": wallc},
	]
	frag.lights = [
		{"pos": Vector3(8.0, 3.6, 0.0), "color": Color(0.9, 0.68, 0.5), "energy": 1.2, "range": 16.0},
		{"pos": Vector3(21.5, 3.8, 0.0), "color": Color(0.85, 0.8, 0.7), "energy": 1.5, "range": 18.0},
		{"pos": Vector3(22.0, 3.4, 10.0), "color": Color(0.45, 0.85, 0.6), "energy": 1.1, "range": 14.0},
		{"pos": Vector3(22.0, 3.4, -10.0), "color": Color(0.6, 0.75, 0.95), "energy": 1.1, "range": 14.0},
		{"pos": Vector3(38.0, 3.8, 0.0), "color": Color(0.85, 0.78, 0.68), "energy": 1.6, "range": 22.0},
		{"pos": Vector3(50.0, 3.6, 4.0), "color": Color(0.5, 0.9, 0.62), "energy": 1.2, "range": 14.0},
	]
	frag.labels = [
		{"pos": Vector3(8.0, 3.0, 0.0), "text": "MAINTENANCE BRANCH 7 — DECOMMISSIONED", "color": Color(0.62, 0.58, 0.55)},
	]
	frag.objects = []
	frag.params = {"restart_on_wipe": false}
	frag.time_state = {"note_default": "Salvage run. The survival clock holds outside — in here the danger is local.",
		"routing_mode": "direct"}
	var cs := 1.5
	var w := 40
	var hgrid := 22
	var cells: Array = []
	for z in range(hgrid):
		for x in range(w):
			var wx := (float(x) + 0.5) * cs
			var wz := (float(z) + 0.5) * cs - 16.5
			var ok := false
			if wx < APPROACH_X1 and absf(wz) < 3.0 and wx > 0.5:
				ok = true
			elif wx >= HUB_X0 and wx < HUB_X1 and absf(wz) < HUB_HALF_Z:
				ok = true
			elif wx >= ROUTE_X0 and wx < ROUTE_X1 and wz > -13.5 and wz < -7.5:
				ok = true
			elif wx >= 20.5 and wx < 23.5 and wz >= -7.5 and wz < -6.0:
				ok = true
			elif wx >= ROUTE_X0 and wx < ROUTE_X1 and wz > 7.5 and wz < 13.5:
				ok = true
			elif wx >= 20.5 and wx < 23.5 and wz > 6.0 and wz <= 7.5:
				ok = true
			elif wx >= HUB_X1 and wx < JCT_X0 and absf(wz) < 1.6:
				ok = true
			elif wx >= JCT_X0 and wx < JCT_X1 and absf(wz) < JCT_HALF_Z:
				ok = true
			elif wx > POCKET[0] and wx < POCKET[1] and wz > POCKET[2] and wz < POCKET[3]:
				ok = true
			if ok:
				cells.append([x, z])
	frag.grid = {"contract_id": "unified_grid_v1", "cell_size": cs,
		"origin": [0.0, 0.0, -16.5], "width": w, "height": hgrid, "walkable_cells": cells}
	return frag

# --- Approach corridor: the burn-damage read ---

func _build_approach() -> void:
	# scorch streaks + fused conduit — elegant routing beneath the burn (the key read)
	for i in range(5):
		var sx := 3.0 + float(i) * 2.6
		_add_box(self, Vector3(sx, 0.02, -1.0 + float(i % 3)), Vector3(1.8, 0.04, 1.2), Color(0.05, 0.045, 0.04))
	_add_box(self, Vector3(8.0, 2.4, -3.0), Vector3(14.0, 0.18, 0.18), Color(0.2, 0.16, 0.12),
		Color(0.9, 0.5, 0.2), 0.12)
	_add_box(self, Vector3(8.0, 2.1, -3.0), Vector3(14.0, 0.12, 0.12), Color(0.18, 0.15, 0.12))
	# Crust organisms on accumulated char (fauna roster: ambient char growth)
	for i in range(4):
		var c := _add_box(self, Vector3(4.5 + float(i) * 3.1, 0.28, 2.4 - float(i % 2) * 0.8),
			Vector3(0.55, 0.5, 0.5), Color(0.28, 0.2, 0.12), Color(0.75, 0.45, 0.15), 0.35)
		c.name = "Crust%d" % i
	_add_label(self, "OLD CHELATOR DAMAGE // REPEAT BURN RESIDUE", Vector3(11.0, 2.6, 0.0), Color(0.62, 0.5, 0.42))

# --- The three information routes ---

func _build_routes() -> void:
	# Route A (Aster): engineering log + pipe diagram
	_add_label(self, "A — RECORDS", Vector3(22.0, 2.9, -8.0), Color(0.6, 0.75, 0.95))
	var a1 := _add_interactable(self, "AsterLogTerminal", "Read the final engineering log",
		Vector3(20.0, 0.6, -11.5), "READ LOG", "aster", 1.0, true, 1.6)
	_outline_interactable_child(a1, _add_box(a1, Vector3(0, 0.55, 0), Vector3(0.7, 1.1, 0.4),
		Color(0.14, 0.16, 0.2), Color(0.36, 0.91, 0.5), 0.5), "AsterLogTerminal", 1.6)
	_configure_inflammashunt_source(a1, ACTION_ASTER_LOG)
	var a2 := _add_interactable(self, "PipeDiagram", "Scan the pipe junction diagram",
		Vector3(24.0, 0.6, -11.5), "SCAN DIAGRAM", "aster", 1.0, true, 1.6)
	_outline_interactable_child(a2, _add_box(a2, Vector3(0, 0.9, -0.4), Vector3(1.6, 1.2, 0.12),
		Color(0.16, 0.18, 0.22), Color(0.5, 0.7, 0.95), 0.4), "PipeDiagram", 1.6)
	_configure_inflammashunt_source(a2, ACTION_PIPE_DIAGRAM)
	# Route B (Peris): dead roots + the living root-Chelator junction
	_add_label(self, "B — UNDERGROWTH", Vector3(22.0, 2.9, 8.0), Color(0.45, 0.85, 0.6))
	var p1 := _add_interactable(self, "DeadRootNetwork", "Examine the dead root network",
		Vector3(20.0, 0.4, 11.5), "EXAMINE ROOTS", "peris", 1.0, true, 1.6)
	_outline_interactable_child(p1, _add_box(p1, Vector3(0, 0.2, 0), Vector3(1.7, 0.4, 1.0),
		Color(0.16, 0.13, 0.1)), "DeadRootNetwork", 1.7)
	_configure_inflammashunt_source(p1, ACTION_DEAD_ROOTS)
	var p2 := _add_interactable(self, "LivingJunction", "Examine the living root-Chelator junction",
		Vector3(24.0, 0.4, 11.5), "EXAMINE JUNCTION", "peris", 1.0, true, 1.6)
	_outline_interactable_child(p2, _add_box(p2, Vector3(0, 0.25, 0), Vector3(1.4, 0.5, 1.0),
		Color(0.14, 0.2, 0.15), Color(0.4, 0.9, 0.55), 0.6), "LivingJunction", 1.7)
	_configure_inflammashunt_source(p2, ACTION_LIVING_JUNCTION)
	# Route C (Myke): the crawlspace — physically character-coded
	var crawl_in := CrawlTunnel.new()
	crawl_in.name = "MykeCrawlIn"
	crawl_in.description = "A crawlspace only Myke fits through"
	crawl_in.tutorial_label = "CRAWL"
	crawl_in.configure(_get_game_state(), Vector3(26.2, 0.0, -4.5),
		[Vector3(28.2, 0.7, -8.0), Vector3(31.0, 0.0, -12.0)], 1.3, 1.1)
	_wire_myke_crawl(crawl_in)
	var crawl_out := CrawlTunnel.new()
	crawl_out.name = "MykeCrawlOut"
	crawl_out.description = "Back through the crawlspace"
	crawl_out.tutorial_label = "CRAWL BACK"
	crawl_out.configure(_get_game_state(), Vector3(30.4, 0.0, -11.0),
		[Vector3(28.2, 0.7, -8.0), Vector3(25.4, 0.0, -4.0)], 1.3, 1.1)
	_wire_myke_crawl(crawl_out)
	var m1 := _add_interactable(self, "GrateObservation", "Watch the corridor floor through the grate",
		Vector3(31.8, 0.4, -13.2), "WATCH FEEDERS", "myke", 1.0, true, 1.6)
	_outline_interactable_child(m1, _add_box(m1, Vector3(0, 0.3, 0.5), Vector3(1.2, 0.6, 0.14),
		Color(0.14, 0.14, 0.15)), "GrateObservation", 1.6)
	_configure_inflammashunt_source(m1, ACTION_GRATE_OBSERVATION)
	var m2 := _add_interactable(self, "DeviceGap", "Sight the device through the gap",
		Vector3(34.2, 0.4, -13.2), "SIGHT DEVICE", "myke", 1.0, true, 1.6)
	_outline_interactable_child(m2, _add_box(m2, Vector3(0, 0.3, 0.5), Vector3(1.2, 0.6, 0.14),
		Color(0.14, 0.14, 0.15), Color(0.5, 0.9, 0.62), 0.3), "DeviceGap", 1.6)
	_configure_inflammashunt_source(m2, ACTION_DEVICE_GAP)

func _wire_myke_crawl(crawl: CrawlTunnel) -> void:
	crawl.required_character = "myke"
	crawl.requirement = func() -> bool: return str(crawl.active_character) == "myke"
	crawl.refused.connect(func() -> void:
		_show_note("The gap is a hand-span wide. Only Myke could fit through there.", 2.4))
	add_child(crawl)
	# CrawlTunnel owns its saved traversal transaction, but this bespoke mouth is not created
	# through SceneChunk._add_interactable(). Bind an exact GameState source explicitly so its
	# accepted receipt has stable identity, canonical data-space position, and Myke authority.
	var gs = _get_game_state()
	if gs != null:
		var source_id := _interactable_data_id(str(crawl.name))
		gs.register_interactable({
			"id": source_id,
			"position": crawl.get_data_mouth(),
			"requires_hold": false,
			"interactable_type": Interactable.InteractableType.INSPECTION,
			"hold_time": 1.0,
			"one_shot": false,
			"required_character": "myke",
			"radius": crawl.interaction_radius,
			"tutorial_label": crawl.tutorial_label,
			"enabled": true,
		})
		crawl.bind_data(gs, source_id)
	_register_interactable(crawl)
	var stub := _add_box(crawl, Vector3(0.0, 0.35, 0.0), Vector3(0.5, 0.7, 0.5), Color(0.1, 0.1, 0.11))
	_outline_interactable_child(crawl, stub, crawl.name, 1.4)

# --- The junction room: eight interactables in one shared space ---

func _build_junction_room() -> void:
	var gs = _get_game_state()
	# 1. drainage valve (wall-mounted, near the terminal but visually distinct)
	_valve_it = _add_interactable(self, "DrainageValve", "Open the drainage valve",
		VALVE_POS, "OPEN VALVE", "", HOLDS["valve"][1], true, 1.7,
		Interactable.InteractableType.TIMED_ACTION)
	_outline_interactable_child(_valve_it, _add_box(_valve_it, Vector3(0, 0.4, -0.5), Vector3(0.9, 0.9, 0.35),
		Color(0.2, 0.28, 0.34), Color(0.4, 0.7, 0.9), 0.4), "DrainageValve", 1.7)
	_configure_inflammashunt_source(_valve_it, ACTION_VALVE)
	# 2 + 3. char deposits
	_char_a_mesh = _add_box(self, CHAR_A_POS + Vector3(0, 0.12, 0), Vector3(2.2, 0.24, 1.8), Color(0.05, 0.045, 0.04))
	_char_a_it = _add_interactable(self, "CharDepositA", "Clear the char deposit",
		CHAR_A_POS, "CLEAR CHAR", "", HOLDS["char_a"][1], true, 1.7,
		Interactable.InteractableType.TIMED_ACTION)
	_outline_interactable_child(_char_a_it, _add_box(_char_a_it, Vector3(0, 0.1, 0), Vector3(1.6, 0.2, 1.3),
		Color(0.06, 0.055, 0.05)), "CharDepositA", 1.8)
	_configure_inflammashunt_source(_char_a_it, ACTION_CHAR_A)
	_char_b_mesh = _add_box(self, CHAR_B_POS + Vector3(0, 0.12, 0), Vector3(1.8, 0.24, 1.5), Color(0.05, 0.045, 0.04))
	_char_b_it = _add_interactable(self, "CharDepositB", "Clear the char deposit by the root crack",
		CHAR_B_POS, "CLEAR CHAR", "", HOLDS["char_b"][1], true, 1.6,
		Interactable.InteractableType.TIMED_ACTION)
	_outline_interactable_child(_char_b_it, _add_box(_char_b_it, Vector3(0, 0.1, 0), Vector3(1.3, 0.2, 1.1),
		Color(0.06, 0.055, 0.05)), "CharDepositB", 1.7)
	_configure_inflammashunt_source(_char_b_it, ACTION_CHAR_B)
	# 4. the root tendril in the floor crack near char B
	var crack := _add_box(self, ROOT_BASE_POS + Vector3(0, 0.03, 0), Vector3(1.2, 0.06, 0.5), Color(0.03, 0.03, 0.03))
	crack.name = "RootCrack"
	_root_it = _add_interactable(self, "RootTendril", "Tend the suppressed root tendril",
		ROOT_BASE_POS, "TEND ROOT", "peris", HOLDS["root"][1], true, 1.5,
		Interactable.InteractableType.TIMED_ACTION)
	_outline_interactable_child(_root_it, _add_box(_root_it, Vector3(0, 0.18, 0), Vector3(0.35, 0.36, 0.35),
		Color(0.16, 0.24, 0.17), Color(0.4, 0.9, 0.55), 0.25), "RootTendril", 1.5)
	_configure_inflammashunt_source(_root_it, ACTION_TEND_ROOT)
	# 5. the dormant Chelator ring: examine is the read, strike is the mistake
	for i in range(5):
		var ang := TAU * float(i) / 5.0
		var husk := _add_box(self, RING_CENTER + Vector3(cos(ang) * 2.1, 0.3, sin(ang) * 2.1),
			Vector3(0.6, 0.6, 0.6), Color(0.22, 0.16, 0.12), Color(0.7, 0.45, 0.25), 0.18)
		husk.name = "DormantHusk%d" % i
		_husks.append(husk)
	_examine_it = _add_interactable(self, "ExamineCluster", "Examine the dormant Chelator ring",
		RING_CENTER + Vector3(-2.0, 0.4, -0.9), "EXAMINE", "", 1.0, true, 1.6)
	_outline_interactable_child(_examine_it, _add_box(_examine_it, Vector3(0, 0.25, 0), Vector3(0.3, 0.5, 0.3),
		Color(0.2, 0.2, 0.22), Color(0.55, 0.75, 1.0), 0.3), "ExamineCluster", 1.6)
	_configure_inflammashunt_source(_examine_it, ACTION_EXAMINE_CLUSTER)
	_strike_it = _add_interactable(self, "StrikeCluster", "Strike the dormant Chelators",
		RING_CENTER + Vector3(1.6, 0.4, -1.1), "STRIKE", "", 1.0, true, 1.6)
	_outline_interactable_child(_strike_it, _add_box(_strike_it, Vector3(0, 0.2, 0), Vector3(0.4, 0.4, 0.4),
		Color(0.24, 0.14, 0.12), Color(0.9, 0.4, 0.25), 0.3), "StrikeCluster", 1.6)
	_configure_inflammashunt_source(_strike_it, ACTION_STRIKE_CLUSTER)
	# 6. gas sac flora in the damp corner (Gasafoetida — flora_taxonomy: Peris-only tend,
	# carryable repellent pod)
	_flora_it = _add_interactable(self, "GasSacFlora", "Tend the gas sac flora",
		FLORA_POS, "TEND FLORA", "peris", 2.0, true, 1.7,
		Interactable.InteractableType.TIMED_ACTION)
	_outline_interactable_child(_flora_it, _add_box(_flora_it, Vector3(0, 0.35, 0), Vector3(0.8, 0.7, 0.8),
		Color(0.2, 0.26, 0.16), Color(0.6, 0.8, 0.3), 0.4), "GasSacFlora", 1.7)
	_configure_inflammashunt_source(_flora_it, ACTION_TEND_FLORA)
	_take_sac_it = _add_interactable(self, "TakeSac", "Take the swollen gas sac",
		SAC_SOURCE_POS, "TAKE SAC", "", 0.8, true, 1.4,
		Interactable.InteractableType.INSPECTION, false)
	_configure_inflammashunt_source(_take_sac_it, ACTION_TAKE_SAC)
	# 7. the terminal (hack = read-only diagnostics; the reset command is the trap)
	_terminal_it = _add_interactable(self, "JunctionTerminal", "Hack the maintenance terminal",
		TERMINAL_POS, "HACK", "aster", 1.0, true, 1.7)
	_outline_interactable_child(_terminal_it, _add_box(_terminal_it, Vector3(0, 0.5, -0.5), Vector3(0.9, 1.0, 0.3),
		Color(0.13, 0.15, 0.19), Color(0.36, 0.91, 0.5), 0.6), "JunctionTerminal", 1.7)
	_configure_inflammashunt_source(_terminal_it, ACTION_HACK_TERMINAL)
	_reset_it = _add_interactable(self, "ThermalResetConfirm", "Initiate the logged thermal reset",
		TERMINAL_POS + Vector3(1.5, 0.5, 0.6), "THERMAL RESET", "aster", 1.2, true, 1.4)
	_outline_interactable_child(_reset_it, _add_box(_reset_it, Vector3(0, 0.3, 0), Vector3(0.32, 0.6, 0.32),
		Color(0.3, 0.12, 0.1), Color(0.95, 0.3, 0.15), 0.7), "ThermalResetConfirm", 1.4)
	_configure_inflammashunt_source(_reset_it, ACTION_THERMAL_RESET)
	# 8. the device housing + the healing zone under the grate
	_housing_it = _add_interactable(self, "DeviceHousing", "Open the device housing",
		HOUSING_POS, "OPEN HOUSING", "", 1.2, true, 1.6,
		Interactable.InteractableType.TIMED_ACTION)
	_add_box(_housing_it, Vector3(0, 0.14, 0), Vector3(1.18, 0.28, 1.18),
		Color(0.12, 0.14, 0.16), Color(0.3, 0.55, 0.42), 0.12, "HousingShell")
	_housing_lid_pivot = Node3D.new()
	_housing_lid_pivot.name = "HousingLidHinge"
	_housing_lid_pivot.position = Vector3(0.0, 0.32, -0.55)
	_housing_it.add_child(_housing_lid_pivot)
	_housing_lid = _add_box(_housing_lid_pivot, Vector3(0, 0, 0.55), Vector3(1.1, 0.12, 1.1),
		Color(0.18, 0.2, 0.22), Color(0.5, 0.9, 0.62), 0.3, "HousingLid")
	_outline_interactable_child(_housing_it, _housing_lid, "DeviceHousing", 1.7)
	_configure_inflammashunt_source(_housing_it, ACTION_OPEN_HOUSING)
	# The housing and its contents are separate actions. The item exists at this exact source from
	# construction onward, but the lid physically conceals it and this pickup seam stays disabled until
	# the opening process commits. No completion flag is awarded by the lid animation.
	_device_it = _add_interactable(self, "InflammashuntDevice",
		"Lift the warm Resolution Catalyst from its housing",
		DEVICE_SOURCE_POS, "TAKE DEVICE", "", 0.8, true, 1.35,
		Interactable.InteractableType.INSPECTION, false)
	_configure_inflammashunt_source(_device_it, ACTION_TAKE_DEVICE)
	_ensure_device_source_item()
	var grate := _add_box(self, GRATE_POS + Vector3(0, 0.02, 0), Vector3(2.2, 0.05, 2.2), Color(0.12, 0.13, 0.14))
	grate.name = "HealingGrate"
	_healing_glow = _add_box(self, GRATE_POS + Vector3(0, -0.35, 0), Vector3(0.8, 0.15, 0.8),
		Color(0.1, 0.2, 0.12), Color(0.45, 0.95, 0.55), 1.4)
	_healing_glow.name = "HealingZoneGlow"
	# the shadow observation point: watching the feeders from inside the room
	_observe_it = _add_interactable(self, "ObserveFeeding", "Watch the active Chelators around the char",
		CHAR_A_POS + Vector3(1.8, 0.4, 1.4), "OBSERVE", "", 1.0, true, 1.6)
	_outline_interactable_child(_observe_it, _add_box(_observe_it, Vector3(0, 0.06, 0), Vector3(0.9, 0.12, 0.9),
		Color(0.13, 0.14, 0.15), Color(0.55, 0.75, 1.0), 0.2), "ObserveFeeding", 1.6)
	_configure_inflammashunt_source(_observe_it, ACTION_OBSERVE_FEEDING)
	_build_process_presenters()
	# the thermal-reset command is not offered until the terminal has been hacked
	if gs != null:
		gs.set_interactable_enabled(_interactable_data_id("ThermalResetConfirm"), false)


## The solve describes three physical processes, so the room shows those processes instead of
## asking prose and booleans to stand in for them. These strips are generic gameplay feedback,
## not authored landmark assets: water advances out of the valve, Peris's filaments grow from
## the exposed root, and the actual housing lid hinges open over its saved interval.
func _build_process_presenters() -> void:
	_water_route_segments.clear()
	_root_filament_segments.clear()
	_append_process_route(_water_route_segments, [
		VALVE_POS + Vector3(0.0, -0.5, 0.0),
		Vector3(38.0, 0.06, -4.8),
		Vector3(34.0, 0.06, -4.8),
		CHAR_A_POS + Vector3(0.0, 0.06, 0.0),
		Vector3(40.0, 0.06, -2.0),
		Vector3(44.0, 0.06, -2.0),
		CHAR_B_POS + Vector3(0.0, 0.06, 0.0),
		ROOT_BASE_POS + Vector3(0.0, 0.06, 0.0),
		HOUSING_POS + Vector3(0.0, 0.06, 0.0),
	], 0.16, Color(0.06, 0.26, 0.38), Color(0.22, 0.72, 1.0), "WaterRoute")
	var filament_targets: Array[Vector3] = [
		RING_CENTER + Vector3(-2.1, 0.18, 0.0),
		RING_CENTER + Vector3(0.0, 0.18, -2.1),
		RING_CENTER + Vector3(1.7, 0.18, 1.2),
		HOUSING_POS + Vector3(0.0, 0.18, 0.0),
	]
	for target in filament_targets:
		_append_process_route(_root_filament_segments, [
			ROOT_BASE_POS + Vector3(0.0, 0.18, 0.0), target,
		], 0.07, Color(0.11, 0.25, 0.13), Color(0.42, 0.95, 0.48), "RootFilament")

	for target in [_char_a_mesh, _char_b_mesh, _root_it]:
		_add_causal_feedback_link(_valve_it, target, Color(0.22, 0.72, 1.0), {
			"name": "ValveWaterLink", "interaction_source": _valve_it,
			"show_label": false, "path_style": "movement_chevrons",
			"owner_character": "aster", "visibility_policy": "contextual",
			"feedback_mode": "predicted", "flow_speed": 0.34, "dash_count": 8,
			"source_offset": Vector3(0.0, 0.35, 0.0), "target_offset": Vector3(0.0, 0.25, 0.0),
		})
	_add_causal_feedback_link(_root_it, _housing_lid, Color(0.42, 0.95, 0.48), {
		"name": "RootHousingLink", "interaction_source": _root_it,
		"show_label": false, "path_style": "movement_chevrons",
		"owner_character": "peris", "visibility_policy": "contextual",
		"feedback_mode": "predicted", "flow_speed": 0.24, "dash_count": 9,
		"source_offset": Vector3(0.0, 0.35, 0.0), "target_offset": Vector3(0.0, 0.35, 0.0),
	})
	_sync_transition_presenters()


func _append_process_route(
		storage: Array[MeshInstance3D], points: Array[Vector3], width: float,
		base_color: Color, emission: Color, prefix: String
	) -> void:
	for index in range(points.size() - 1):
		var start := points[index]
		var finish := points[index + 1]
		var delta := finish - start
		var flat_length := Vector2(delta.x, delta.z).length()
		if flat_length <= 0.01:
			continue
		var strip := _add_box(self, (start + finish) * 0.5,
			Vector3(width, 0.035, flat_length), base_color, emission, 0.85,
			"%s_%02d" % [prefix, storage.size()])
		strip.rotation.y = atan2(delta.x, delta.z)
		strip.visible = false
		strip.set_meta("camera_occlusion_exempt", true)
		storage.append(strip)


func _sync_transition_presenters() -> void:
	var now := _now()
	var water_progress := 1.0 if water_phase == "full" else 0.0
	if water_phase == "flowing":
		water_progress = clampf(1.0 - (water_deadline - now) / WATER_FLOW_DURATION, 0.0, 1.0)
	_reveal_process_segments(_water_route_segments, water_progress)

	var root_progress := 1.0 if root_state == "connected" else 0.0
	if root_state == "connecting":
		root_progress = clampf(1.0 - (root_connect_deadline - now) / ROOT_CONNECT_DURATION, 0.0, 1.0)
	_reveal_process_segments(_root_filament_segments, root_progress)

	var housing_progress := 1.0 if housing_state == "open" else 0.0
	if housing_state == "opening":
		housing_progress = clampf(1.0 - (housing_deadline - now) / HOUSING_OPEN_DURATION, 0.0, 1.0)
	if _housing_lid_pivot != null and is_instance_valid(_housing_lid_pivot):
		_housing_lid_pivot.rotation.x = lerpf(0.0, -1.32, smoothstep(0.0, 1.0, housing_progress))
	if _housing_lid != null and is_instance_valid(_housing_lid):
		_housing_lid.visible = true


func _reveal_process_segments(segments: Array[MeshInstance3D], progress: float) -> void:
	if segments.is_empty():
		return
	var revealed := progress * float(segments.size())
	for index in range(segments.size()):
		var segment := segments[index]
		if segment != null and is_instance_valid(segment):
			segment.visible = revealed > float(index) + 0.01

func _spawn_active_chelators() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for i in range(3):
		var eid := "chelator_%d" % i
		var ang := TAU * float(i) / 3.0
		var enemy := Enemy.new()
		enemy.name = "Enemy_%s" % eid
		enemy.position = CHAR_A_POS + Vector3(cos(ang) * 1.8, 0.4, sin(ang) * 1.8)
		enemy.scale = Vector3.ONE * 0.62
		enemy.color = Color(0.45, 0.18, 0.1)
		enemy.move_speed = 2.0
		enemy.detection_range = 0.0
		enemy.windup_duration = 0.4
		enemy.recover_duration = 0.8
		enemy.charge_speed = 6.0
		enemy.attack_range = 1.5
		enemy.charge_damage = 6.0
		enemy._detection_targets.assign(_party)
		add_child(enemy)
		enemy.char_id = eid
		enemy.game_state = gs
		gs.register_character(eid, enemy.position, enemy.move_speed, {})
		if gs.has_method("set_coop_exempt"):
			gs.set_coop_exempt(eid)
		enemy.activate()
		enemy.set_roam(CHAR_A_POS, 2.4)
		_enemy_posts[eid] = enemy.position
		_enemies.append(enemy)

# --- Exact physical interaction authority ---

## Every consequential room action uses a one-shot Interactable as a short-lived receipt, including
## mechanisms that can later be retried. GameState's monotonic trigger_count distinguishes a new
## physical use from a direct callback, a manual signal emission, or an old receipt in the same tick.
func _configure_inflammashunt_source(source: Node, action_id: String) -> void:
	if not is_instance_valid(source):
		return
	_interaction_sources[action_id] = source
	source.set_pre_trigger_validator(
		_validate_inflammashunt_source_trigger.bind(action_id, source))
	source.interacted.connect(
		_on_inflammashunt_source_interacted.bind(action_id, source))


func _validate_inflammashunt_source_trigger(
		source: Node, actor: String, action_id: String, expected_source: Node
	) -> bool:
	return is_instance_valid(source) and source == expected_source \
		and _interaction_sources.get(action_id) == source \
		and _inflammashunt_actor_ready_at(source, actor) \
		and _inflammashunt_action_ready(action_id, actor)


func _inflammashunt_actor_ready_at(source: Node, actor: String) -> bool:
	var gs = _get_game_state()
	if gs == null or not is_instance_valid(source) or not (source is Node3D) \
			or actor == "" or not _party.has(actor) or not gs.characters.has(actor) \
			or not gs.is_narratively_available(actor) or gs.is_downed(actor) \
			or gs.is_knocked_down(actor) or gs.is_moving(actor) \
			or gs.is_resting(actor) or gs.is_dodging(actor) \
			or gs.is_endocytosing(actor) or gs.is_external_traversal_active(actor) \
			or gs.is_dragging(actor) or gs.is_field_restoring(actor) \
			or gs.is_pushing(actor):
		return false
	var required_actor := str(source.get("required_character"))
	if required_actor != "" and actor != required_actor:
		return false
	var source_position := _inflammashunt_source_data_position(source)
	var actor_position: Vector3 = gs.get_position(actor)
	var radius := float(source.get("interaction_radius")) + INTERACTION_POSITION_TOLERANCE
	return Vector2(actor_position.x, actor_position.z).distance_to(
		Vector2(source_position.x, source_position.z)) <= radius \
		and absf(actor_position.y - source_position.y) <= maxf(1.5, radius)


func _inflammashunt_source_data_position(source: Node) -> Vector3:
	var gs = _get_game_state()
	var data_id := str(source.get("data_id")) if is_instance_valid(source) else ""
	if gs != null and data_id != "" and gs.has_interactable(data_id):
		return gs.get_interactable(data_id).get("position", Vector3.ZERO)
	if source is Node3D:
		var source_position := (source as Node3D).global_position
		if gs != null and gs.coord_map != null and gs.coord_map.has_method("to_data"):
			source_position = gs.coord_map.to_data(source_position)
		return source_position
	return Vector3.INF


func _inflammashunt_action_ready(action_id: String, actor: String) -> bool:
	match action_id:
		ACTION_ASTER_LOG:
			return not bool(route_info["aster_log"])
		ACTION_PIPE_DIAGRAM:
			return not bool(route_info["aster_pipe_diagram"])
		ACTION_DEAD_ROOTS:
			return not bool(route_info["peris_dead_roots"])
		ACTION_LIVING_JUNCTION:
			return not bool(route_info["peris_living_junction"])
		ACTION_GRATE_OBSERVATION:
			return not bool(route_info["myke_char_feed"])
		ACTION_DEVICE_GAP:
			return not bool(route_info["myke_buffer_ring"])
		ACTION_VALVE:
			return water_phase == "dry"
		ACTION_CHAR_A:
			return char_a_state != "cleared"
		ACTION_CHAR_B:
			return char_b_state != "cleared"
		ACTION_TEND_ROOT:
			return root_state in ["suppressed", "tame"]
		ACTION_EXAMINE_CLUSTER:
			return buffer_state == "stable" and not bool(route_info["myke_buffer_ring"])
		ACTION_OBSERVE_FEEDING:
			return not bool(route_info["myke_char_feed"])
		ACTION_STRIKE_CLUSTER:
			return buffer_state == "stable"
		ACTION_TEND_FLORA:
			return gas_sac_state in ["idle", "expired"] \
				and _live_sac_item_state().is_empty()
		ACTION_TAKE_SAC:
			return gas_sac_state == "tended" and _sac_item_at_source() \
				and _actor_has_free_hand(actor)
		ACTION_HACK_TERMINAL:
			return not _terminal_hacked
		ACTION_THERMAL_RESET:
			return _terminal_hacked and not wrong_events.has("thermal_reset")
		ACTION_OPEN_HOUSING:
			return not device_retrieved and housing_state == "sealed"
		ACTION_TAKE_DEVICE:
			return housing_state == "open" \
				and _device_phase == DEVICE_PHASE_AVAILABLE \
				and _device_item_at_source() and _actor_has_free_hand(actor)
	return false


func _actor_has_free_hand(actor: String) -> bool:
	var gs = _get_game_state()
	return gs != null and gs.characters.has(actor) and gs.has_free_hands(actor, 1)


func _inflammashunt_source_receipt_count(source: Node, action_id: String) -> int:
	if not is_instance_valid(source) or _interaction_sources.get(action_id) != source:
		return -1
	var actor := str(source.get("active_character"))
	if not _validate_inflammashunt_source_trigger(source, actor, action_id, source) \
			or not bool(source.get("one_shot")) or not bool(source.get("_used")) \
			or bool(source.get("interaction_enabled")):
		return -1
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return -1
	var spec: Dictionary = gs.get_interactable(data_id)
	var trigger_count := int(spec.get("trigger_count", 0))
	if not bool(spec.get("one_shot", false)) \
			or not bool(spec.get("triggered", false)) \
			or bool(spec.get("enabled", true)) \
			or str(spec.get("last_trigger_character", "")) != actor \
			or trigger_count <= int(_source_committed_counts.get(action_id, 0)):
		return -1
	return trigger_count


func _on_inflammashunt_source_interacted(action_id: String, source: Node) -> void:
	var trigger_count := _inflammashunt_source_receipt_count(source, action_id)
	if trigger_count < 0:
		return
	var actor := str(source.get("active_character"))
	# Set the local receipt identity before the first action publication. Thus every semantic phase
	# snapshot contains its source count, while a snapshot captured from GameState's trigger signal
	# (before this callback) contains neither and is safely re-armed on restore.
	_source_committed_counts[action_id] = trigger_count
	_active_source_receipt = {
		"action": action_id,
		"actor": actor,
		"trigger_count": trigger_count,
	}
	var committed := _commit_inflammashunt_action(action_id, actor)
	_active_source_receipt.clear()
	if not committed:
		_rearm_inflammashunt_source(source)
		_publish_inflammashunt_authority()
		return
	_sync_inflammashunt_source_presenters()


func _commit_inflammashunt_action(action_id: String, actor: String) -> bool:
	if not _source_commit_is_active(action_id, actor):
		return false
	match action_id:
		ACTION_ASTER_LOG:
			return _read_aster_log_from_receipt()
		ACTION_PIPE_DIAGRAM:
			return _read_pipe_diagram_from_receipt()
		ACTION_DEAD_ROOTS:
			return _read_dead_roots_from_receipt()
		ACTION_LIVING_JUNCTION:
			return _read_living_junction_from_receipt()
		ACTION_GRATE_OBSERVATION:
			return _read_grate_observation_from_receipt()
		ACTION_DEVICE_GAP:
			return _read_device_gap_from_receipt()
		ACTION_VALVE:
			return _open_valve_from_receipt(actor)
		ACTION_CHAR_A:
			return _service_char_deposit_from_receipt("a", actor)
		ACTION_CHAR_B:
			return _service_char_deposit_from_receipt("b", actor)
		ACTION_TEND_ROOT:
			return _tend_root_from_receipt(actor)
		ACTION_EXAMINE_CLUSTER:
			return _examine_cluster_from_receipt()
		ACTION_OBSERVE_FEEDING:
			return _observe_feeding_from_receipt()
		ACTION_STRIKE_CLUSTER:
			return _strike_cluster_from_receipt()
		ACTION_TEND_FLORA:
			return _tend_flora_from_receipt()
		ACTION_TAKE_SAC:
			return _take_sac_from_receipt(actor)
		ACTION_HACK_TERMINAL:
			return _hack_terminal_from_receipt()
		ACTION_THERMAL_RESET:
			return _thermal_reset_from_receipt()
		ACTION_OPEN_HOUSING:
			return _open_housing_from_receipt()
		ACTION_TAKE_DEVICE:
			return _take_device_from_receipt(actor)
	return false


func _source_commit_is_active(action_id: String, actor := "") -> bool:
	return str(_active_source_receipt.get("action", "")) == action_id \
		and (actor == "" or str(_active_source_receipt.get("actor", "")) == actor) \
		and int(_active_source_receipt.get("trigger_count", 0)) > 0 \
		and int(_source_committed_counts.get(action_id, 0)) \
			== int(_active_source_receipt.get("trigger_count", -1))


func _rearm_inflammashunt_source(source: Node) -> void:
	if not is_instance_valid(source):
		return
	if source.is_node_ready():
		source.reset()
		return
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs != null and data_id != "" and gs.has_interactable(data_id):
		gs.reset_interactable(data_id)
	source.set("_used", false)
	source.set("interaction_enabled", true)


func _sync_inflammashunt_source_presenters() -> void:
	for action_id_v in _interaction_sources.keys():
		_project_inflammashunt_source(str(action_id_v))


func _project_inflammashunt_source(action_id: String) -> void:
	var source: Node = _interaction_sources.get(action_id)
	if not is_instance_valid(source):
		return
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return
	var should_enable := _inflammashunt_source_should_enable(action_id)
	var spec: Dictionary = gs.get_interactable(data_id)
	var triggered := bool(spec.get("triggered", false))
	if should_enable and triggered:
		_rearm_inflammashunt_source(source)
		return
	gs.set_interactable_enabled(data_id, should_enable)
	if source.has_method("restore_one_shot_presenter"):
		source.restore_one_shot_presenter(triggered, should_enable)


func _inflammashunt_source_should_enable(action_id: String) -> bool:
	match action_id:
		ACTION_ASTER_LOG:
			return not bool(route_info["aster_log"])
		ACTION_PIPE_DIAGRAM:
			return not bool(route_info["aster_pipe_diagram"])
		ACTION_DEAD_ROOTS:
			return not bool(route_info["peris_dead_roots"])
		ACTION_LIVING_JUNCTION:
			return not bool(route_info["peris_living_junction"])
		ACTION_GRATE_OBSERVATION:
			return not bool(route_info["myke_char_feed"])
		ACTION_DEVICE_GAP:
			return not bool(route_info["myke_buffer_ring"])
		ACTION_VALVE:
			return water_phase == "dry"
		ACTION_CHAR_A:
			return char_a_state != "cleared"
		ACTION_CHAR_B:
			return char_b_state != "cleared"
		ACTION_TEND_ROOT:
			return root_state in ["suppressed", "tame"]
		ACTION_EXAMINE_CLUSTER:
			return buffer_state == "stable" and not bool(route_info["myke_buffer_ring"])
		ACTION_OBSERVE_FEEDING:
			return not bool(route_info["myke_char_feed"])
		ACTION_STRIKE_CLUSTER:
			return buffer_state == "stable"
		ACTION_TEND_FLORA:
			return gas_sac_state in ["idle", "expired"] \
				and _live_sac_item_state().is_empty()
		ACTION_TAKE_SAC:
			return gas_sac_state == "tended" and _sac_item_at_source()
		ACTION_HACK_TERMINAL:
			return not _terminal_hacked
		ACTION_THERMAL_RESET:
			return _terminal_hacked and not wrong_events.has("thermal_reset")
		ACTION_OPEN_HOUSING:
			return not device_retrieved and housing_state == "sealed"
		ACTION_TAKE_DEVICE:
			return housing_state == "open" \
				and _device_phase == DEVICE_PHASE_AVAILABLE \
				and _device_item_at_source()
	return false


## Legacy test/automation handlers are deliberately inert. Consequences can only be reached through
## _commit_inflammashunt_action after the exact source's accepted trigger receipt.
func _on_aster_log() -> void:
	pass

func _on_pipe_diagram() -> void:
	pass

func _on_dead_roots() -> void:
	pass

func _on_living_junction() -> void:
	pass

func _on_grate_observation() -> void:
	pass

func _on_device_gap() -> void:
	pass

func _on_valve() -> void:
	pass

func _on_char_deposit(_which: String) -> void:
	pass

func _on_tend_root() -> void:
	pass

func _on_examine_cluster() -> void:
	pass

func _on_observe_feeding() -> void:
	pass

func _on_strike_cluster() -> void:
	pass

func _on_tend_flora() -> void:
	pass

func _on_take_sac() -> void:
	pass

func _on_hack_terminal() -> void:
	pass

func _on_thermal_reset() -> void:
	pass

func _on_open_housing() -> void:
	pass

func _on_take_device() -> bool:
	return false


# --- Route handlers: every report is honest and confidently wrong ---

func _read_aster_log_from_receipt() -> bool:
	if not _source_commit_is_active(ACTION_ASTER_LOG):
		return false
	route_info["aster_log"] = true
	_show_note("FINAL ENTRY // Resolution capacity exceeded. Recommend thermal reset. // Filed: same day as section removal from registry.", 4.2)
	_maybe_report("aster")
	_refresh_hold_times()
	_publish_inflammashunt_authority()
	return true

func _read_pipe_diagram_from_receipt() -> bool:
	if not _source_commit_is_active(ACTION_PIPE_DIAGRAM):
		return false
	route_info["aster_pipe_diagram"] = true
	_show_note("Drainage routing — the valve feeds from the Plumbing Power Project. Flow and pressure ratings. Water infrastructure, not heat.", 3.8)
	_maybe_report("aster")
	_refresh_hold_times()
	_publish_inflammashunt_authority()
	return true

func _read_dead_roots_from_receipt() -> bool:
	if not _source_commit_is_active(ACTION_DEAD_ROOTS):
		return false
	route_info["peris_dead_roots"] = true
	_show_note("The old network is hollow — tunneled from inside, then coated by char. It was eaten before it burned.", 3.6)
	_maybe_report("peris")
	_refresh_hold_times()
	_publish_inflammashunt_authority()
	return true

func _read_living_junction_from_receipt() -> bool:
	if not _source_commit_is_active(ACTION_LIVING_JUNCTION):
		return false
	route_info["peris_living_junction"] = true
	_show_note("Living filaments feed the dormant husks — and the husks feed the roots back. A cycle, still running.", 3.6)
	_maybe_report("peris")
	_refresh_hold_times()
	_publish_inflammashunt_authority()
	return true

func _read_grate_observation_from_receipt() -> bool:
	if not _source_commit_is_active(ACTION_GRATE_OBSERVATION):
		return false
	route_info["myke_char_feed"] = true
	_show_note("The active crawlers aren't roaming. They're feeding — clustered on the char.", 3.2)
	_maybe_report("myke")
	_refresh_hold_times()
	_publish_inflammashunt_authority()
	return true

func _read_device_gap_from_receipt() -> bool:
	if not _source_commit_is_active(ACTION_DEVICE_GAP):
		return false
	route_info["myke_buffer_ring"] = true
	_show_note("Dormant crawlers ring the device — calm, inside. The active ones press from outside the ring.", 3.2)
	_maybe_report("myke")
	_refresh_hold_times()
	_publish_inflammashunt_authority()
	return true

## The confident wrong answer, played once when a route's pair of reads is complete.
func _maybe_report(route: String) -> void:
	if _reports.has(route):
		return
	match route:
		"aster":
			if route_info["aster_log"] and route_info["aster_pipe_diagram"]:
				_reports["aster"] = true
				_show_note("Aster: \"The engineers left instructions. The device needs a thermal reset.\"", 3.4)
		"peris":
			if route_info["peris_dead_roots"] and route_info["peris_living_junction"]:
				_reports["peris"] = true
				_show_note("Peris: \"The old roots were burned. Fire killed the previous resolution system. We can't use fire near the device.\"", 3.8)
		"myke":
			if route_info["myke_char_feed"] and route_info["myke_buffer_ring"] and _party.has("myke"):
				_reports["myke"] = true
				_show_note("Myke: \"Too many crawlers. We burn the corridor clean, give the thing room to breathe.\"", 3.6)

## The reunion triangle: back at the hub with the reports in hand, the contradictions land.
func _check_reunion() -> void:
	if _reunion_played or _reports.size() < 2:
		return
	var gs = _get_game_state()
	if gs == null:
		return
	for cid in _party:
		if not gs.characters.has(cid):
			continue
		var p: Vector3 = gs.get_position(cid)
		if p.x < HUB_X0 or p.x > HUB_X1 or absf(p.z) > HUB_HALF_Z:
			return
	_reunion_played = true
	_publish_inflammashunt_authority()
	var sched = _get_scheduler()
	if sched == null:
		return
	if _reports.size() >= 3:
		sched.schedule_after(0.5, func() -> void:
			_show_note("Aster: \"Thermal reset.\"  Peris: \"Heat killed the old system.\"", 3.4), "inflam_reunion")
		sched.schedule_after(4.0, func() -> void:
			_show_note("Myke: \"Burn it clean.\"  Aster: \"The only live infrastructure is water.\"", 3.4), "inflam_reunion")
		sched.schedule_after(7.5, func() -> void:
			_show_note("Three confident answers. They can't all be right.", 3.0), "inflam_reunion")
	else:
		sched.schedule_after(0.5, func() -> void:
			_show_note("Two confident answers that can't both be right. Something out there settles it.", 3.4), "inflam_reunion")

# --- Junction handlers ---

func _open_valve_from_receipt(actor: String) -> bool:
	if not _source_commit_is_active(ACTION_VALVE, actor):
		return false
	if water_phase != "dry":
		_show_note("The valve is already open. The channel is still filling." if water_phase == "flowing"
			else "The flush line is already full.", 2.0)
		return false
	if not route_info["aster_pipe_diagram"]:
		_long_hold(actor)
	valve_open = true
	water_phase = "flowing"
	water_deadline = _now() + WATER_FLOW_DURATION
	_set_interactable_runtime_enabled(_valve_it, false)
	_set_causal_feedback_mode(_valve_it, "active")
	_set_causal_feedback_latched(_valve_it, true)
	_flash_causal_feedback(_valve_it, WATER_FLOW_DURATION, 1.1)
	_sync_transition_presenters()
	_publish_inflammashunt_authority()
	_show_note("The valve opens. Water races visibly through the floor channels toward both deposits.", 3.0)
	_arm_water_flow(water_deadline)
	return true


func _arm_water_flow(deadline: float) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag("inflam_water_flow")
	water_deadline = deadline
	sched.schedule_after(maxf(0.0, deadline - _now()),
		_finish_water_flow_from_timer.bind(deadline), "inflam_water_flow")


func _finish_water_flow_from_timer(expected_deadline: float) -> void:
	if water_phase != "flowing" \
			or not is_equal_approx(expected_deadline, water_deadline) \
			or _now() + 0.000001 < expected_deadline:
		return
	water_phase = "full"
	water_deadline = -1.0
	if char_a_state == "dry" or char_a_state == "burned":
		char_a_state = "damp"
	if char_b_state == "dry" or char_b_state == "burned":
		char_b_state = "damp"
	_sync_char_visuals()
	_sync_transition_presenters()
	_set_causal_feedback_mode(_valve_it, "complete")
	_set_causal_feedback_latched(_valve_it, false)
	if _popcorn:
		_end_popcorn("The flood reaches the fire and takes it. Scorched sacs drift in the runoff.")
	else:
		_show_note("The water reaches both deposits. The char darkens and steams; the crawlers recoil.", 3.4)
	_refresh_hold_times()
	_publish_inflammashunt_authority()

func _service_char_deposit_from_receipt(which: String, actor: String) -> bool:
	var action_id := ACTION_CHAR_A if which == "a" else ACTION_CHAR_B
	if not _source_commit_is_active(action_id, actor):
		return false
	var state := char_a_state if which == "a" else char_b_state
	match state:
		"dry", "burned":
			if actor == "myke":
				_burn_char(which)
			else:
				_show_note("The residue is baked on — it won't come loose dry. Water would soften it.", 2.8)
		"damp":
			if not route_info["myke_char_feed"]:
				_long_hold(actor)
			if which == "a":
				char_a_state = "cleared"
				_show_note("The damp char comes away clean. The feeders lose their food source and thin out.", 3.2)
				_thin_out_chelators()
			else:
				char_b_state = "cleared"
				_show_note("Careful strokes around the crack — the char lifts without touching the root.", 3.0)
			_sync_char_visuals()
		"cleared":
			_show_note("Bare floor. Nothing left to clear.", 2.0)
	_publish_inflammashunt_authority()
	return true

func _burn_char(which: String) -> void:
	var action_id := ACTION_CHAR_A if which == "a" else ACTION_CHAR_B
	if not _source_commit_is_active(action_id, "myke"):
		return
	if which == "a":
		char_a_state = "burned"
		_wrong("burned_char_a")
		_show_note("Myke's fire takes the char — and the heat wakes what was sleeping. They're up.", 3.2)
		_wake_chelators(0)
	else:
		char_b_state = "burned"
		root_state = "hostile"
		_wrong("burned_char_b")
		_show_note("The char flashes off — and the root beside it whips out of the crack, thrashing.", 3.2)
		_spawn_hostile_root()
	_sync_char_visuals()
	_publish_inflammashunt_authority()

func _tend_root_from_receipt(actor: String) -> bool:
	if not _source_commit_is_active(ACTION_TEND_ROOT, actor):
		return false
	if root_state == "hostile" or root_state == "recovering":
		_show_note("The root is in no state to be tended.", 2.2)
		return false
	if root_state == "connecting":
		_show_note("The new filaments are still growing toward the ring.", 2.0)
		return false
	if root_state == "connected":
		_show_note("The living circuit is already connected.", 2.0)
		return false
	if char_a_state != "cleared" or char_b_state != "cleared":
		_show_note("The pulse flickers under Peris's hands and dies down. The residue is still smothering it.", 3.2)
		if not route_info["peris_living_junction"]:
			_long_hold(actor)
		_publish_inflammashunt_authority()
		return true
	if not route_info["peris_living_junction"]:
		_long_hold(actor)
	root_state = "connecting"
	root_connect_deadline = _now() + ROOT_CONNECT_DURATION
	_set_interactable_runtime_enabled(_root_it, false)
	_set_causal_feedback_mode(_root_it, "active")
	_set_causal_feedback_latched(_root_it, true)
	_flash_causal_feedback(_root_it, ROOT_CONNECT_DURATION, 1.1)
	_sync_transition_presenters()
	_publish_inflammashunt_authority()
	_show_note("The root brightens. Watch the filaments thread toward the dormant ring and housing.", 3.2)
	_arm_root_connection(root_connect_deadline)
	return true


func _arm_root_connection(deadline: float) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag("inflam_root_connect")
	root_connect_deadline = deadline
	sched.schedule_after(maxf(0.0, deadline - _now()),
		_finish_root_connection_from_timer.bind(deadline), "inflam_root_connect")


func _finish_root_connection_from_timer(expected_deadline: float) -> void:
	if root_state != "connecting" \
			or not is_equal_approx(expected_deadline, root_connect_deadline) \
			or _now() + 0.000001 < expected_deadline:
		return
	root_state = "connected"
	root_connect_deadline = -1.0
	healing_zone = 1.0
	housing_unlocked = true
	_sync_healing_visual()
	_sync_transition_presenters()
	_set_causal_feedback_mode(_root_it, "complete")
	_set_causal_feedback_latched(_root_it, false)
	_publish_inflammashunt_authority()
	_show_note("The last filament seats. The grate glow reaches the housing and its lock releases.", 3.4)

func _examine_cluster_from_receipt() -> bool:
	if not _source_commit_is_active(ACTION_EXAMINE_CLUSTER):
		return false
	_show_note("Warm. Connected by thin filaments. Not feeding, not moving — a perimeter.", 3.2)
	if route_info["peris_living_junction"] and not route_info["myke_buffer_ring"]:
		route_info["myke_buffer_ring"] = true
		_show_note("Peris: \"They're in the same state as the junction underground. It's a buffer — not a siege.\"", 3.6)
		_refresh_hold_times()
	_publish_inflammashunt_authority()
	return true

func _observe_feeding_from_receipt() -> bool:
	if not _source_commit_is_active(ACTION_OBSERVE_FEEDING):
		return false
	_show_note("The active crawlers cluster on the char deposits. They don't wander off them.", 3.0)
	if route_info["aster_pipe_diagram"] and route_info["peris_living_junction"] \
			and not route_info["myke_char_feed"]:
		route_info["myke_char_feed"] = true
		_show_note("Aster: \"The system was built to flush something. They're eating it. The char is the food.\"", 3.6)
		_refresh_hold_times()
	_publish_inflammashunt_authority()
	return true

func _strike_cluster_from_receipt() -> bool:
	if not _source_commit_is_active(ACTION_STRIKE_CLUSTER):
		return false
	if buffer_state != "stable":
		_show_note("The scattered husks don't react.", 2.0)
		return false
	buffer_state = "shattered"
	_wrong("attacked_buffer")
	if root_state in ["connecting", "connected"] and not device_retrieved:
		_cancel_process_transition("inflam_root_connect")
		root_connect_deadline = -1.0
		root_state = "suppressed"
		healing_zone = 0.0
		housing_unlocked = false
		_set_interactable_runtime_enabled(_root_it, true)
		_set_causal_feedback_mode(_root_it, "failed")
		_set_causal_feedback_latched(_root_it, false)
		if housing_state == "opening":
			_cancel_process_transition("inflam_housing_open")
			housing_state = "sealed"
			housing_deadline = -1.0
			_set_interactable_runtime_enabled(_housing_it, true)
		_sync_healing_visual()
		_sync_transition_presenters()
	_show_note("The ring shatters — and everything that was calm isn't. The root snaps back into its crack.", 3.4)
	for husk in _husks:
		if is_instance_valid(husk):
			husk.visible = false
	_wake_chelators(2)
	_publish_inflammashunt_authority()
	return true

func _tend_flora_from_receipt() -> bool:
	if not _source_commit_is_active(ACTION_TEND_FLORA):
		return false
	if gas_sac_state == "ignited":
		_show_note("The flora is still burning. Nothing to tend yet.", 2.2)
		return false
	if not _live_sac_item_state().is_empty():
		_show_note("A ripe sac is already out in the room.", 2.0)
		return false
	_sac_item_id = _spawn_sac_source_item()
	if _sac_item_id == "":
		_show_note("The tended pod has not separated from the plant yet.", 2.0)
		return false
	gas_sac_state = "tended"
	_apply_sac_interactable_state()
	_publish_inflammashunt_authority()
	_show_note("The flora swells under Peris's hands. A sac ripens, ready to carry.", 3.0)
	return true


func _spawn_sac_source_item(properties: Dictionary = {}) -> String:
	var item_properties := {
		"display_name": "Repellent Gas Sac",
		"hand_slots": 1,
		"visual_kind": "gas_sac",
		"visual_color": Color(0.5, 0.7, 0.25),
		"inflammashunt_authority": INFLAMMASHUNT_AUTHORITY_KEY,
		"source_fixture": "GasSacFlora",
		"endocytosis_allowed": false,
	}
	item_properties.merge(properties, true)
	return _spawn_item("gas_sac", SAC_SOURCE_POS, item_properties)

func _take_sac_from_receipt(actor: String) -> bool:
	if not _source_commit_is_active(ACTION_TAKE_SAC, actor):
		return false
	if gas_sac_state != "tended":
		_show_note("No ripe sac. The flora needs tending first.", 2.2)
		return false
	if actor == "":
		return false
	var gs = _get_game_state()
	if gs == null or not gs.characters.has(actor):
		return false
	if not gs.has_free_hands(actor, 1):
		_show_note("%s needs a free hand for the gas sac." % actor.capitalize(), 2.2)
		return false
	if not _sac_item_at_source():
		_show_note("The ripe pod is no longer seated on this plant.", 2.2)
		return false
	gas_sac_state = "claiming"
	_sac_carrier = actor
	_sac_expires = _now() + SAC_DURATION
	_sac_claim_serial += 1
	_apply_sac_interactable_state()
	_publish_inflammashunt_authority()
	if not _pick_up_item(actor, _sac_item_id):
		gas_sac_state = "tended"
		_sac_carrier = ""
		_sac_expires = -1.0
		_apply_sac_interactable_state()
		_publish_inflammashunt_authority()
		_show_note("The sac stays on the plant; the carrier needs a free hand.", 2.2)
		return false
	gas_sac_state = "active"
	_apply_sac_interactable_state()
	_publish_inflammashunt_authority()
	_show_note("%s carries the sac at arm's length. The smell peels paint — nothing rooted will come near it." % actor.capitalize(), 3.2)

	return true

func _hack_terminal_from_receipt() -> bool:
	if not _source_commit_is_active(ACTION_HACK_TERMINAL):
		return false
	var gs = _get_game_state()
	_terminal_hacked = true
	_show_note("Read-only diagnostics: resolution loop INCOMPLETE // residue accumulating // flush line INTACT. One logged command is still queued: THERMAL RESET.", 4.2)
	if gs != null:
		gs.set_interactable_enabled(_interactable_data_id("ThermalResetConfirm"), true)
	_publish_inflammashunt_authority()
	return true

func _thermal_reset_from_receipt() -> bool:
	if not _source_commit_is_active(ACTION_THERMAL_RESET):
		return false
	if _popcorn:
		return false
	_wrong("thermal_reset")
	_remove_live_sac_item()
	gas_sac_state = "ignited"
	_sac_expires = -1.0
	_apply_sac_interactable_state()
	_popcorn = true
	_arm_popcorn_poll()
	_publish_inflammashunt_authority()
	_show_note("Heaters cough alive — and the gas sacs go up. Flaming sacs skip off the walls. The VALVE. Flood the room.", 3.8)

	return true

func _open_housing_from_receipt() -> bool:
	if not _source_commit_is_active(ACTION_OPEN_HOUSING):
		return false
	if device_retrieved:
		return false
	if housing_state == "opening":
		_show_note("The housing latches are still withdrawing.", 1.8)
		return false
	if not housing_unlocked:
		_show_note("It does not budge. The lock is warm, but the warmth is coming from below, not from the panel.", 3.4)
		_publish_inflammashunt_authority()
		return true
	housing_state = "opening"
	housing_deadline = _now() + HOUSING_OPEN_DURATION
	_set_interactable_runtime_enabled(_housing_it, false)
	_sync_transition_presenters()
	_publish_inflammashunt_authority()
	_show_note("The living lock withdraws in sequence. The lid begins to hinge open.", 2.6)
	_arm_housing_open(housing_deadline)


	return true

func _arm_housing_open(deadline: float) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag("inflam_housing_open")
	housing_deadline = deadline
	sched.schedule_after(maxf(0.0, deadline - _now()),
		_finish_housing_open_from_timer.bind(deadline), "inflam_housing_open")


func _finish_housing_open_from_timer(expected_deadline: float) -> void:
	if housing_state != "opening" or not housing_unlocked \
			or not is_equal_approx(expected_deadline, housing_deadline) \
			or _now() + 0.000001 < expected_deadline:
		return
	housing_state = "open"
	housing_deadline = -1.0
	_sync_transition_presenters()
	_apply_device_interactable_state()
	_publish_inflammashunt_authority()
	_sync_healing_visual()
	_show_note("The housing opens. The Inflammashunt is still running inside — warm, loose, and ready to lift.", 3.6)


## Opening exposes the prize; this exact-source pickup is the retrieval. The transient claiming
## phase makes a snapshot taken from GameState.item_picked_up unambiguous on restore without ever
## substituting another character, item, or free hand.
func _take_device_from_receipt(actor: String) -> bool:
	if not _source_commit_is_active(ACTION_TAKE_DEVICE, actor):
		return false
	if housing_state != "open" or _device_phase != DEVICE_PHASE_AVAILABLE \
			or not _device_item_at_source():
		return false
	var gs = _get_game_state()
	if actor == "" or gs == null or not gs.characters.has(actor):
		return false
	if not gs.has_free_hands(actor, 1):
		_show_note("%s needs a free hand to lift the Inflammashunt." % actor.capitalize(), 2.2)
		return false

	_device_phase = DEVICE_PHASE_CLAIMING
	_device_claimed_by = actor
	_device_claim_serial += 1
	_apply_device_interactable_state()
	_publish_inflammashunt_authority()
	if not _pick_up_item(actor, _device_item_id):
		_device_phase = DEVICE_PHASE_AVAILABLE
		_device_claimed_by = ""
		_apply_device_interactable_state()
		_publish_inflammashunt_authority()
		_show_note("The device stays seated; stand at the open housing with one hand free.", 2.2)
		return false

	_device_phase = DEVICE_PHASE_CLAIMED
	device_retrieved = true
	_phase = "complete"
	_apply_device_interactable_state()
	_publish_inflammashunt_authority()
	_set_preview_step("inflammashunt_complete")
	_sync_healing_visual()
	_show_note("%s lifts the Inflammashunt free — a warm Resolution Catalyst, now real salvage in hand." \
		% actor.capitalize(), 3.6)
	var sched = _get_scheduler()
	if sched != null and _party.has("myke"):
		sched.schedule_after(4.0, func() -> void:
			_show_note("Myke: \"...Huh. So that's what it looks like when somebody finishes the job.\"", 3.8), "inflam_after")
	return true


func _spawn_device_item(properties: Dictionary = {}) -> String:
	var item_properties := {
		"display_name": "Inflammashunt Resolution Catalyst",
		"hand_slots": 1,
		"source_inflammashunt": INFLAMMASHUNT_AUTHORITY_KEY,
		"visual_kind": "inflammashunt_resolution_catalyst",
		"visual_scene": DEVICE_VISUAL_SCENE,
		"visual_identity": "inflammashunt_resolution_catalyst_v1",
		"visual_color": Color(0.46, 0.88, 0.68),
		"ground_visual_y": 0.17,
		"endocytosis_allowed": true,
		"adds_to_collection": true,
	}
	item_properties.merge(properties, true)
	return _spawn_item(DEVICE_ITEM_TYPE, DEVICE_SOURCE_POS, item_properties)


func _is_device_item(item_id: String) -> bool:
	var item := _get_item_state(item_id)
	if item.is_empty() or str(item.get("type", "")) != DEVICE_ITEM_TYPE:
		return false
	var properties: Dictionary = item.get("properties", {})
	return str(properties.get("source_inflammashunt", "")) == INFLAMMASHUNT_AUTHORITY_KEY


func _find_device_item_id() -> String:
	var gs = _get_game_state()
	if gs == null or not "items" in gs:
		return ""
	var candidates: Array[String] = []
	for item_id_v in gs.items.keys():
		var item_id := str(item_id_v)
		if _is_device_item(item_id):
			candidates.append(item_id)
	candidates.sort()
	return candidates[0] if not candidates.is_empty() else ""


func _remove_device_items() -> void:
	var gs = _get_game_state()
	if gs == null or not "items" in gs:
		return
	var remove_ids: Array[String] = []
	for item_id_v in gs.items.keys():
		var item_id := str(item_id_v)
		if _is_device_item(item_id):
			remove_ids.append(item_id)
	for item_id in remove_ids:
		_remove_item(item_id)


func _ensure_device_source_item() -> void:
	if _is_device_item(_device_item_id):
		return
	_device_item_id = _find_device_item_id()
	if _device_item_id == "":
		_device_item_id = _spawn_device_item()


func _device_item_at_source() -> bool:
	if not _is_device_item(_device_item_id):
		return false
	var item := _get_item_state(_device_item_id)
	return str(item.get("location", "")) == "ground" \
		and (item.get("position", DEVICE_SOURCE_POS) as Vector3).distance_to(DEVICE_SOURCE_POS) <= 0.05


func _device_item_holder() -> String:
	var item := _get_item_state(_device_item_id)
	return str(item.get("holder", "")) if not item.is_empty() else ""


func _apply_device_interactable_state() -> void:
	_project_inflammashunt_source(ACTION_TAKE_DEVICE)


func _cancel_process_transition(tag: String) -> void:
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(tag)


func _set_interactable_runtime_enabled(interactable: Area3D, enabled: bool) -> void:
	if interactable == null:
		return
	var gs = _get_game_state()
	if gs != null:
		gs.set_interactable_enabled(_interactable_data_id(str(interactable.name)), enabled)

# --- Wrong-approach machinery ---

func _wrong(event: String) -> void:
	wrong_events.append(event)
	_publish_inflammashunt_authority()
	var missing: Array = []
	for k in route_info:
		if not bool(route_info[k]):
			missing.append(str(k))
	if missing.is_empty():
		return
	# explicit recon push (spec: after a wrong consequence with missing route info)
	var sched = _get_scheduler()
	if sched == null:
		return
	if not route_info["aster_log"] or not route_info["aster_pipe_diagram"]:
		sched.schedule_after(3.5, func() -> void:
			_show_note("Aster: \"We're missing something. Let me check that terminal back at the junction.\"", 3.2), "inflam_hint")
	elif _party.has("myke") and (not route_info["myke_char_feed"] or not route_info["myke_buffer_ring"]):
		sched.schedule_after(3.5, func() -> void:
			_show_note("Myke: \"We're doing this blind. Let me crawl in and see what we're actually dealing with.\"", 3.2), "inflam_hint")
	elif not route_info["peris_dead_roots"] or not route_info["peris_living_junction"]:
		sched.schedule_after(3.5, func() -> void:
			_show_note("Peris: \"There's something growing underground near the junction. I need to see it before we try anything else.\"", 3.2), "inflam_hint")

## Hold-without-info: counted, and the hint ladder pushes RECONNAISSANCE, never solutions.
func _long_hold(actor: String) -> void:
	long_hold_count += 1
	_publish_inflammashunt_authority()
	match mini(long_hold_count, 3):
		1:
			match actor:
				"aster": _show_note("Aster: \"This interface is fighting me.\"", 2.6)
				"peris": _show_note("Peris: \"It is not answering yet.\"", 2.6)
				"myke": _show_note("Myke: \"I don't like guessing at crawler sign.\"", 2.6)
				_: _show_note("Slow, blind work.", 2.2)
		2:
			if _party.has("myke") and actor != "myke":
				_show_note("Myke: \"You look like you're guessing.\"", 2.6)
			else:
				_show_note("Peris: \"Maybe we should look around first.\"", 2.6)
		3:
			var sched = _get_scheduler()
			if sched != null:
				if _party.has("myke"):
					sched.schedule_after(0.4, func() -> void:
						_show_note("Myke: \"There's a crawlspace back there I could fit through. Might see something useful.\"", 3.2), "inflam_hint")
				sched.schedule_after(3.6, func() -> void:
					_show_note("Peris: \"I noticed a growth at that junction. I could follow it underground.\"", 3.2), "inflam_hint")
				sched.schedule_after(6.8, func() -> void:
					_show_note("Aster: \"That terminal at the junction had a hack lock. I should take a look.\"", 3.2), "inflam_hint")

## Waking the dormant systems: the roamers turn on the party, plus `extra` fresh bodies out of
## the shattered ring. The encounter cools on its own once nothing keeps provoking it.
func _wake_chelators(extra: int) -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for i in range(extra):
		var eid := "chelator_x%d" % _extra_chelators.size()
		var enemy := Enemy.new()
		enemy.name = "Enemy_%s" % eid
		enemy.position = RING_CENTER + Vector3(-1.2 + 1.2 * float(i), 0.4, 0.8 - 1.6 * float(i % 2))
		enemy.scale = Vector3.ONE * 0.62
		enemy.color = Color(0.5, 0.16, 0.08)
		enemy.move_speed = 2.2
		enemy.detection_range = 0.0
		enemy.windup_duration = 0.4
		enemy.recover_duration = 0.8
		enemy.charge_speed = 6.0
		enemy.attack_range = 1.5
		enemy.charge_damage = 6.0
		enemy._detection_targets.assign(_party)
		add_child(enemy)
		enemy.char_id = eid
		enemy.game_state = gs
		gs.register_character(eid, enemy.position, enemy.move_speed, {})
		if gs.has_method("set_coop_exempt"):
			gs.set_coop_exempt(eid)
		enemy.activate()
		_extra_chelators.append(enemy)
		_enemies.append(enemy)
	_rage_until = _now() + RAGE_SECS
	for enemy in _enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive() or enemy == _root_enemy:
			continue
		_raged[enemy.char_id] = true
		var target := _nearest_party_to(gs.get_position(enemy.char_id))
		if target != "" and enemy.has_method("engage_target"):
			enemy.engage_target(target)
	_publish_inflammashunt_authority()

func _thin_out_chelators() -> void:
	# the food source is gone: the feeders disperse (roam wide, away from the cleared deposit)
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy != _root_enemy and enemy.has_method("set_roam") \
				and not _raged.get(enemy.char_id, false):
			enemy.set_roam(Vector3(33.0, 0.0, -6.0), 1.6)

## The rage cooling + buffer reform pass, on the shared poll.
func _cool_encounters(now: float) -> void:
	if _rage_until > 0.0 and now >= _rage_until:
		_rage_until = -1.0
		var gs = _get_game_state()
		for enemy in _enemies:
			if not is_instance_valid(enemy) or enemy == _root_enemy or not enemy.is_alive():
				continue
			if _raged.get(enemy.char_id, false) and enemy.has_method("re_post"):
				enemy.re_post(_enemy_posts.get(enemy.char_id, enemy.position))
				if enemy.has_method("set_roam"):
					enemy.set_roam(CHAR_A_POS, 2.4)
		_raged.clear()
		_show_note("The crawlers settle. Whatever woke them, it's over.", 2.6)
		if buffer_state == "shattered":
			buffer_state = "reforming"
			_arm_buffer_reform(now + BUFFER_REFORM_SECS)
		_publish_inflammashunt_authority()


func _arm_buffer_reform(deadline: float) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag("inflam_reform")
	_buffer_reform_deadline = deadline
	sched.schedule_after(maxf(0.0, deadline - _now()),
		_reform_buffer_from_timer.bind(deadline), "inflam_reform")

func _reform_buffer_from_timer(expected_deadline: float) -> void:
	if buffer_state != "reforming" \
			or not is_equal_approx(expected_deadline, _buffer_reform_deadline) \
			or _now() + 0.000001 < expected_deadline:
		return
	_buffer_reform_deadline = -1.0
	buffer_state = "stable"
	for husk in _husks:
		if is_instance_valid(husk):
			husk.visible = true
	_project_inflammashunt_source(ACTION_STRIKE_CLUSTER)
	_publish_inflammashunt_authority()
	_show_note("One by one the husks drift back into their ring around the housing.", 3.0)

# --- The hostile-root recovery sub-puzzle (Chain AI, herd it home with a sac) ---

func _spawn_hostile_root() -> void:
	if _root_enemy != null and is_instance_valid(_root_enemy):
		return
	var gs = _get_game_state()
	if gs == null:
		return
	var root := ChainEnemy.new()
	root.name = "Enemy_hostile_root"
	root.position = ROOT_BASE_POS + Vector3(-1.2, 0.3, -0.8)
	root.segment_count = 7
	add_child(root)
	root.char_id = "hostile_root"
	root.game_state = gs
	gs.register_character("hostile_root", root.position, 2.8, {})
	if gs.has_method("set_coop_exempt"):
		gs.set_coop_exempt("hostile_root")
	# no activate(): the chunk drives the whole behavior deterministically (flee/whip/capture),
	# so the herding reads the same at 1x and 10x
	_root_enemy = root
	_whip_ready.clear()
	_arm_root_poll()
	_publish_inflammashunt_authority()

func _arm_root_poll() -> void:
	_arm_root_timer("poll", _now() + ROOT_POLL_INTERVAL)


func _arm_root_timer(mode: String, deadline: float) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag("inflam_root")
	_root_timer_mode = mode
	_root_deadline = deadline
	if mode in ["poll", "retract", "regrow"]:
		sched.schedule_after(maxf(0.0, deadline - _now()),
			_run_inflammashunt_root_timer.bind(mode, deadline), "inflam_root")


func _run_inflammashunt_root_timer(mode: String, expected_deadline: float) -> void:
	if mode != _root_timer_mode \
			or not is_equal_approx(expected_deadline, _root_deadline) \
			or _now() + 0.000001 < expected_deadline:
		return
	match mode:
		"poll":
			_root_poll_from_timer()
		"retract":
			_retract_root_from_timer()
		"regrow":
			_finish_root_regrow_from_timer()


func _root_poll_from_timer() -> void:
	_root_timer_mode = ""
	_root_deadline = -1.0
	if not is_inside_tree() or _root_enemy == null or not is_instance_valid(_root_enemy):
		_publish_inflammashunt_authority()
		return
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if gs == null or sched == null:
		return
	var now := _now()
	var rp: Vector3 = gs.get_position("hostile_root")
	# Only a completed ACTIVE pickup creates the repellent field. During CLAIMING,
	# _sac_carrier is the immutable reservation actor; deriving it from a wrong/forged
	# physical holder here would silently retarget the saved transaction.
	if gas_sac_state == "active":
		_sac_carrier = _sac_holder()
	var carrier_live: bool = gas_sac_state == "active" \
		and _sac_carrier != "" and now < _sac_expires
	if carrier_live:
		var cp: Vector3 = gs.get_position(_sac_carrier)
		var d := Vector2(rp.x - cp.x, rp.z - cp.z)
		if d.length() < SAC_AURA:
			# recoil from the sac: straight flee, clamped inside the junction room
			var dir := d.normalized() if d.length() > 0.05 else Vector2(1, 0)
			var tx := clampf(rp.x + dir.x * 2.4, JCT_X0 + 1.0, JCT_X1 - 1.0)
			var tz := clampf(rp.z + dir.y * 2.4, -JCT_HALF_Z + 1.0, JCT_HALF_Z - 1.0)
			gs.command_move_to_pos("hostile_root", Vector3(tx, 0.0, tz))
			# boxed in at its base: it goes home
			if Vector2(rp.x - ROOT_BASE_POS.x, rp.z - ROOT_BASE_POS.z).length() < ROOT_CAPTURE_RADIUS:
				gs.command_stop("hostile_root")
				_arm_root_timer("retract", now + ROOT_RETRACT_DELAY)
				_publish_inflammashunt_authority()
				return
	else:
		# aggressive: threads toward the nearest character and whips at close range
		var target := _nearest_party_to(rp)
		if target != "":
			var tp: Vector3 = gs.get_position(target)
			if Vector2(rp.x - tp.x, rp.z - tp.z).length() > 1.4:
				gs.command_move_to_pos("hostile_root", tp)
			elif now >= float(_whip_ready.get(target, -100.0)):
				_whip_ready[target] = now + 2.2
				# the whip rides the kit's ONE strike path -- dodge windows, sanctuary,
				# concealment, and corpse-skip all come from Enemy._resolve_strike
				_root_enemy.charge_damage = 5.0
				_root_enemy._charge_hit = false
				if _root_enemy._resolve_strike(target):
					_show_note("The root whips %s across the deck." % target.capitalize(), 2.0)
	_arm_root_timer("poll", now + ROOT_POLL_INTERVAL)
	_publish_inflammashunt_authority()


## The sac is an ordinary GameState item. These helpers derive the chunk's read model from that
## canonical ownership so inventory drop/transfer commands immediately change the herding system.
func _is_live_sac_item_id(item_id: String) -> bool:
	var gs = _get_game_state()
	if gs == null or item_id == "" or not gs.items.has(item_id):
		return false
	var item: Dictionary = gs.items[item_id]
	if str(item.get("type", "")) != "gas_sac":
		return false
	var properties: Dictionary = item.get("properties", {})
	return str(properties.get("inflammashunt_authority", "")) == INFLAMMASHUNT_AUTHORITY_KEY


func _live_sac_item_state() -> Dictionary:
	var gs = _get_game_state()
	if gs == null or not _is_live_sac_item_id(_sac_item_id):
		return {}
	var item: Dictionary = gs.items[_sac_item_id]
	return item


func _find_sac_item_id() -> String:
	var gs = _get_game_state()
	if gs == null or not "items" in gs:
		return ""
	var candidates: Array[String] = []
	for item_id_v in gs.items.keys():
		var item_id := str(item_id_v)
		var item: Dictionary = gs.items.get(item_id, {})
		if str(item.get("type", "")) != "gas_sac":
			continue
		var properties: Dictionary = item.get("properties", {})
		if str(properties.get("inflammashunt_authority", "")) == INFLAMMASHUNT_AUTHORITY_KEY:
			candidates.append(item_id)
	candidates.sort()
	return candidates[0] if not candidates.is_empty() else ""


func _sac_item_at_source() -> bool:
	var item := _live_sac_item_state()
	return not item.is_empty() \
		and str(item.get("location", "")) == "ground" \
		and (item.get("position", SAC_SOURCE_POS) as Vector3).distance_to(SAC_SOURCE_POS) <= 0.05


func _sac_holder() -> String:
	var item := _live_sac_item_state()
	if item.is_empty() or str(item.get("location", "")) != "hand":
		return ""
	var holder := str(item.get("holder", ""))
	var gs = _get_game_state()
	return holder if gs != null and gs.characters.has(holder) else ""


func _remove_live_sac_item() -> void:
	var gs = _get_game_state()
	if gs != null:
		# Authority absence and old-save migration must also retract an item whose cached id was lost.
		for item_id_v in gs.items.keys().duplicate():
			var item_id := str(item_id_v)
			var item: Dictionary = gs.items.get(item_id, {})
			var properties: Dictionary = item.get("properties", {})
			if str(properties.get("inflammashunt_authority", "")) == INFLAMMASHUNT_AUTHORITY_KEY:
				_remove_item(item_id)
	_sac_item_id = ""
	_sac_carrier = ""


func _expire_sac() -> void:
	_remove_live_sac_item()
	gas_sac_state = "expired"
	_sac_expires = -1.0
	_apply_sac_interactable_state()


func _apply_sac_interactable_state() -> void:
	_project_inflammashunt_source(ACTION_TEND_FLORA)
	_project_inflammashunt_source(ACTION_TAKE_SAC)

func _retract_root_from_timer() -> void:
	_root_timer_mode = ""
	_root_deadline = -1.0
	var pending_sched = _get_scheduler()
	if pending_sched != null:
		pending_sched.cancel_tag("inflam_root")
	if _root_enemy == null or not is_instance_valid(_root_enemy):
		_publish_inflammashunt_authority()
		return
	var gs = _get_game_state()
	if gs != null and gs.characters.has("hostile_root"):
		gs.unregister_character("hostile_root")
	_enemies.erase(_root_enemy)
	_root_enemy.queue_free()
	_root_enemy = null
	root_state = "recovering"
	_root_timer_mode = "regrow"
	_root_deadline = _now() + ROOT_REGROW_DELAY
	_publish_inflammashunt_authority()
	_show_note("The root pours itself back into the crack and stills.", 3.0)
	_arm_root_timer("regrow", _root_deadline)


func _finish_root_regrow_from_timer() -> void:
	_root_timer_mode = ""
	_root_deadline = -1.0
	root_state = "suppressed"
	_project_inflammashunt_source(ACTION_TEND_ROOT)
	_publish_inflammashunt_authority()
	_show_note("A smaller tendril noses back out of the crack. Tame — and still smothered.", 3.0)


## Retired process shortcuts. Root phase transitions are consumed only by their saved scheduler
## mode/deadline receipt, never by a direct callback from a test or automation driver.
func _finish_water_flow() -> void:
	pass


func _finish_root_connection() -> void:
	pass


func _finish_housing_open() -> void:
	pass


func _reform_buffer() -> void:
	pass


func _root_poll() -> void:
	pass


func _retract_root() -> void:
	pass


func _finish_root_regrow() -> void:
	pass


# --- The popcorn hazard (thermal reset trap): a kit HazardField owns the burn; the chunk only
# --- places it over the junction and toggles it from its own mechanisms (reset lever / valve) ---

func _arm_popcorn_poll() -> void:
	_ensure_popcorn_field()
	if _popcorn_field != null and is_instance_valid(_popcorn_field):
		_popcorn_field.set_active(true)


func _ensure_popcorn_field() -> void:
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if gs == null or sched == null:
		return
	if _popcorn_field == null or not is_instance_valid(_popcorn_field):
		_popcorn_field = HazardFieldScript.new()
		_popcorn_field.name = "PopcornHazard"
		_popcorn_field.position = Vector3((JCT_X0 + JCT_X1) * 0.5, 0.0, 0.0)
		add_child(_popcorn_field)
	_popcorn_field.setup(gs, sched, Vector2(JCT_X0, -JCT_HALF_Z), Vector2(JCT_X1, JCT_HALF_Z),
		_party, {"dps_tick": POPCORN_DPS_TICK, "interval": 1.0, "tag": "inflam_popcorn"})

func _end_popcorn(msg: String) -> void:
	_popcorn = false
	_remove_live_sac_item()
	gas_sac_state = "idle"
	_sac_expires = -1.0
	_apply_sac_interactable_state()
	if _popcorn_field != null and is_instance_valid(_popcorn_field):
		_popcorn_field.set_active(false)
	_publish_inflammashunt_authority()
	_show_note(msg, 3.4)

# --- The shared cadence poll ---

func _ensure_polls() -> void:
	if _polls_armed:
		return
	_arm_shared_poll(_now() + SHARED_POLL_INTERVAL)


func _arm_shared_poll(deadline: float) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag("inflam_shared")
	_polls_armed = true
	_shared_poll_deadline = deadline
	sched.schedule_after(maxf(0.0, deadline - _now()), _shared_poll, "inflam_shared")

func _shared_poll() -> void:
	_polls_armed = false
	_shared_poll_deadline = -1.0
	if not is_inside_tree():
		return
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if gs == null or sched == null:
		return
	var now := _now()
	if not _entry_played:
		for cid in _party:
			if gs.characters.has(cid) and gs.get_position(cid).x > 10.0:
				_play_entry_beat()
				break
	if gas_sac_state == "active":
		_sac_carrier = _sac_holder()
		if _live_sac_item_state().is_empty() or now >= _sac_expires:
			_expire_sac()
			_show_note("The sac wilts and goes quiet. Peris can tend another.", 2.8)
	_cool_encounters(now)
	_check_reunion()
	_arm_shared_poll(now + SHARED_POLL_INTERVAL)
	_publish_inflammashunt_authority()

func _play_entry_beat() -> void:
	_entry_played = true
	_publish_inflammashunt_authority()
	var sched = _get_scheduler()
	if sched == null:
		return
	if _party.has("myke"):
		_show_note("Myke: \"...I cleared this section. Twice, maybe. The crawlers kept coming back.\"", 3.2)
		sched.schedule_after(3.6, func() -> void:
			_show_note("Aster: \"The fire worked. The crawlers are gone.\"", 2.6), "inflam_entry")
		sched.schedule_after(6.6, func() -> void:
			_show_note("Myke: \"Yeah.\"", 1.8), "inflam_entry")
	else:
		_show_note("Scorched walls, fused conduit — elegant routing under all that burn. Somebody fought here for a long time, and nobody cleaned up.", 4.0)

# --- Save/load authority ---

func _inflammashunt_authority_state() -> Dictionary:
	var extra_ids: Array[String] = []
	for enemy in _extra_chelators:
		if is_instance_valid(enemy) and str(enemy.char_id) != "":
			extra_ids.append(str(enemy.char_id))
	return {
		"version": INFLAMMASHUNT_AUTHORITY_VERSION,
		"phase": _phase,
		"route_info": route_info.duplicate(true),
		"valve_open": valve_open,
		"water_phase": water_phase,
		"water_deadline": water_deadline,
		"char_a_state": char_a_state,
		"char_b_state": char_b_state,
		"root_state": root_state,
		"root_connect_deadline": root_connect_deadline,
		"buffer_state": buffer_state,
		"gas_sac_state": gas_sac_state,
		"healing_zone": healing_zone,
		"housing_unlocked": housing_unlocked,
		"housing_state": housing_state,
		"housing_deadline": housing_deadline,
		"device_retrieved": device_retrieved,
		"device_phase": _device_phase,
		"device_item_id": _device_item_id,
		"device_claimed_by": _device_claimed_by,
		"device_claim_serial": _device_claim_serial,
		"sac_claim_serial": _sac_claim_serial,
		"terminal_hacked": _terminal_hacked,
		"source_committed_counts": _source_committed_counts.duplicate(true),
		"wrong_events": wrong_events.duplicate(true),
		"long_hold_count": long_hold_count,
		"entry_played": _entry_played,
		"reports": _reports.duplicate(true),
		"reunion_played": _reunion_played,
		"popcorn": _popcorn,
		"sac_item_id": _sac_item_id,
		"sac_carrier": _sac_carrier if gas_sac_state == "claiming" else _sac_holder(),
		"sac_expires": _sac_expires,
		"rage_until": _rage_until,
		"raged_ids": _raged.keys(),
		"whip_ready": _whip_ready.duplicate(true),
		"polls_armed": _polls_armed,
		"shared_poll_deadline": _shared_poll_deadline,
		"root_timer_mode": _root_timer_mode,
		"root_deadline": _root_deadline,
		"buffer_reform_deadline": _buffer_reform_deadline,
		"extra_chelator_ids": extra_ids,
		"hostile_root_present": _root_enemy != null and is_instance_valid(_root_enemy),
	}


func _publish_inflammashunt_authority() -> void:
	if _restoring_inflammashunt_authority:
		return
	var gs = _get_game_state()
	if gs != null and gs.has_method("set_world_state"):
		gs.set_world_state(INFLAMMASHUNT_AUTHORITY_KEY, _inflammashunt_authority_state())


## The production loader clears every opaque scheduler Callable. This restores the puzzle's stocks,
## dynamic bodies, and exact absolute deadlines before reattaching one callback for each active phase.
func on_game_state_snapshot_restored() -> void:
	super.on_game_state_snapshot_restored()
	_cancel_inflammashunt_callbacks()
	var gs = _get_game_state()
	var raw: Variant = gs.get_world_state(INFLAMMASHUNT_AUTHORITY_KEY, null) \
			if gs != null and gs.has_method("get_world_state") else null
	if not raw is Dictionary or int(raw.get("version", 0)) \
			not in [1, 2, 3, 4, INFLAMMASHUNT_AUTHORITY_VERSION]:
		_retract_inflammashunt_presenter_to_defaults()
		return

	var saved: Dictionary = raw
	var saved_version := int(saved.get("version", 1))
	_restoring_inflammashunt_authority = true
	_phase = str(saved.get("phase", "ready"))
	if _phase not in ["ready", "active", "failed", "complete"]:
		_phase = "ready"
	var saved_route: Variant = saved.get("route_info", {})
	for key_v in route_info.keys():
		var key := str(key_v)
		route_info[key] = bool((saved_route as Dictionary).get(key, false)) \
				if saved_route is Dictionary else false
	valve_open = bool(saved.get("valve_open", false))
	water_phase = _valid_string(saved.get("water_phase", "full" if valve_open else "dry"),
		["dry", "flowing", "full"], "dry") if saved_version >= 2 else ("full" if valve_open else "dry")
	water_deadline = float(saved.get("water_deadline", -1.0)) if saved_version >= 2 else -1.0
	char_a_state = _valid_string(saved.get("char_a_state", "dry"),
		["dry", "damp", "cleared", "burned"], "dry")
	char_b_state = _valid_string(saved.get("char_b_state", "dry"),
		["dry", "damp", "cleared", "burned"], "dry")
	root_state = _valid_string(saved.get("root_state", "suppressed"),
		["suppressed", "tame", "hostile", "recovering", "connecting", "connected"], "suppressed")
	root_connect_deadline = float(saved.get("root_connect_deadline", -1.0)) if saved_version >= 2 else -1.0
	buffer_state = _valid_string(saved.get("buffer_state", "stable"),
		["stable", "shattered", "reforming"], "stable")
	gas_sac_state = _valid_string(saved.get("gas_sac_state", "idle"),
		["idle", "tended", "claiming", "active", "carried", "expired", "ignited"], "idle")
	healing_zone = clampf(float(saved.get("healing_zone", 0.0)), 0.0, 1.0)
	housing_unlocked = bool(saved.get("housing_unlocked", false))
	housing_state = _valid_string(saved.get("housing_state", "open" if bool(saved.get("device_retrieved", false)) else "sealed"),
		["sealed", "opening", "open"], "sealed") if saved_version >= 2 \
		else ("open" if bool(saved.get("device_retrieved", false)) else "sealed")
	housing_deadline = float(saved.get("housing_deadline", -1.0)) if saved_version >= 2 else -1.0
	var legacy_device_retrieved := bool(saved.get("device_retrieved", false))
	device_retrieved = legacy_device_retrieved
	_device_phase = _valid_string(saved.get("device_phase", DEVICE_PHASE_AVAILABLE),
		[DEVICE_PHASE_AVAILABLE, DEVICE_PHASE_CLAIMING, DEVICE_PHASE_CLAIMED],
		DEVICE_PHASE_AVAILABLE) if saved_version >= 4 else DEVICE_PHASE_AVAILABLE
	_device_item_id = str(saved.get("device_item_id", "")) if saved_version >= 4 else ""
	_device_claimed_by = str(saved.get("device_claimed_by", "")) if saved_version >= 4 else ""
	_device_claim_serial = maxi(0, int(saved.get("device_claim_serial", 0))) if saved_version >= 4 else 0
	_sac_claim_serial = maxi(0, int(saved.get("sac_claim_serial", 0))) \
		if saved_version >= 5 else 0
	_source_committed_counts.clear()
	if saved_version >= 5 and saved.get("source_committed_counts", null) is Dictionary:
		for action_id_v in (saved.get("source_committed_counts", {}) as Dictionary).keys():
			var action_id := str(action_id_v)
			if _interaction_sources.has(action_id):
				_source_committed_counts[action_id] = maxi(
					0, int((saved.get("source_committed_counts", {}) as Dictionary)[action_id_v]))
	_normalize_process_authority()
	wrong_events = (saved.get("wrong_events", []) as Array).duplicate(true) \
			if saved.get("wrong_events", null) is Array else []
	_terminal_hacked = bool(saved.get("terminal_hacked", false)) \
		if saved_version >= 5 else wrong_events.has("thermal_reset")
	long_hold_count = maxi(0, int(saved.get("long_hold_count", 0)))
	_entry_played = bool(saved.get("entry_played", false))
	_reports = (saved.get("reports", {}) as Dictionary).duplicate(true) \
			if saved.get("reports", null) is Dictionary else {}
	_reunion_played = bool(saved.get("reunion_played", false))
	_popcorn = bool(saved.get("popcorn", false))
	_sac_item_id = str(saved.get("sac_item_id", "")) if saved_version >= 3 else ""
	_sac_carrier = str(saved.get("sac_carrier", "")) if saved_version >= 4 else ""
	_sac_expires = float(saved.get("sac_expires", -1.0))
	_normalize_sac_authority(saved_version)
	_rage_until = float(saved.get("rage_until", -1.0))
	_raged.clear()
	for id_v in (saved.get("raged_ids", []) as Array):
		_raged[str(id_v)] = true
	_whip_ready.clear()
	var saved_whips: Variant = saved.get("whip_ready", {})
	if saved_whips is Dictionary:
		for id_v in (saved_whips as Dictionary).keys():
			_whip_ready[str(id_v)] = float((saved_whips as Dictionary)[id_v])
	_polls_armed = bool(saved.get("polls_armed", false))
	_shared_poll_deadline = float(saved.get("shared_poll_deadline", -1.0))
	_root_timer_mode = _valid_string(saved.get("root_timer_mode", ""),
		["", "poll", "retract", "regrow"], "")
	_root_deadline = float(saved.get("root_deadline", -1.0))
	_buffer_reform_deadline = float(saved.get("buffer_reform_deadline", -1.0))
	_restore_dynamic_enemy_presenters(
		saved.get("extra_chelator_ids", []) as Array,
		bool(saved.get("hostile_root_present", false)))
	_reconcile_restored_device_transaction(saved_version, legacy_device_retrieved)
	_apply_inflammashunt_presenters()
	_restoring_inflammashunt_authority = false

	if _polls_armed and _shared_poll_deadline >= 0.0:
		_arm_shared_poll(_shared_poll_deadline)
	if _root_timer_mode != "" and _root_deadline >= 0.0:
		_arm_root_timer(_root_timer_mode, _root_deadline)
	if buffer_state == "reforming" and _buffer_reform_deadline >= 0.0:
		_arm_buffer_reform(_buffer_reform_deadline)
	if water_phase == "flowing" and water_deadline >= 0.0:
		_arm_water_flow(water_deadline)
	if root_state == "connecting" and root_connect_deadline >= 0.0:
		_arm_root_connection(root_connect_deadline)
	if housing_state == "opening" and housing_deadline >= 0.0:
		_arm_housing_open(housing_deadline)
	# Reconciliation may complete a transaction whose save landed synchronously inside
	# GameState.item_picked_up (CLAIMING + the exact item already in the reserved hand), or retract
	# an orphan accepted-source receipt. Publish that normalized truth now so an immediate second
	# save cannot regress to the stale pre-callback phase and mint/re-arm its reward.
	_publish_inflammashunt_authority()


func _normalize_process_authority() -> void:
	if water_phase == "dry":
		valve_open = false
		water_deadline = -1.0
	elif water_phase == "full":
		valve_open = true
		water_deadline = -1.0
	elif water_deadline < 0.0:
		water_phase = "dry"
		valve_open = false

	if root_state == "connecting" and root_connect_deadline < 0.0:
		root_state = "suppressed"
	if root_state != "connecting":
		root_connect_deadline = -1.0
	if root_state == "connected":
		housing_unlocked = true
	elif not device_retrieved:
		housing_unlocked = false
		healing_zone = 0.0

	# An open housing is a durable physical state, not shorthand for owning its contents.
	# Only the source-tagged item transaction below may derive retrieval/completion.
	if housing_state == "opening" and (not housing_unlocked or housing_deadline < 0.0):
		housing_state = "sealed"
		housing_deadline = -1.0
	if housing_state != "opening":
		housing_deadline = -1.0


## Reconcile the serializable transaction against the item authority restored by GameState. A
## snapshot may land immediately before or inside item_picked_up; source-ground means no pickup
## committed, while any other location means it did. Older boolean-only saves intentionally return
## the device to the open housing rather than minting ownership to an unknown character.
func _reconcile_restored_device_transaction(saved_version: int, legacy_retrieved: bool) -> void:
	# Version 4+ binds this transaction to the saved item id. Do not let a different tagged item
	# replace that identity if the exact source was deleted, moved through a forged save, or consumed
	# after a completed claim. Older boolean-only saves may recover their one surviving tagged item.
	var strict_saved_identity := saved_version >= 4
	if not _is_device_item(_device_item_id) \
			and not strict_saved_identity and _device_phase != DEVICE_PHASE_CLAIMED:
		var recovered_item_id := _find_device_item_id()
		if recovered_item_id != "":
			_device_item_id = recovered_item_id
		else:
			_device_item_id = ""

	# Exactly one source identity may exist for this encounter. A duplicated item is a save exploit,
	# not a second reward; discard deterministic extras without touching unrelated cure components.
	var gs = _get_game_state()
	if gs != null and "items" in gs:
		var duplicate_ids: Array[String] = []
		for item_id_v in gs.items.keys():
			var item_id := str(item_id_v)
			if item_id != _device_item_id and _is_device_item(item_id):
				duplicate_ids.append(item_id)
		for item_id in duplicate_ids:
			_remove_item(item_id)

	# An unclaimed missing source retracts to one newly visible item after every possible substitute
	# has been removed. A completed claim instead retains its saved id as an exact-once tombstone.
	if not _is_device_item(_device_item_id) and _device_phase != DEVICE_PHASE_CLAIMED:
		_device_item_id = _spawn_device_item({"legacy_source_recovery": saved_version < 4})

	if saved_version < 4:
		# The old save only knew that a lid animation had ended. Preserve the solved housing/root,
		# but require one honest pickup from the visible source before granting completion.
		_device_phase = DEVICE_PHASE_AVAILABLE
		_device_claimed_by = ""
		_device_claim_serial = 0
		device_retrieved = false
		if legacy_retrieved:
			housing_state = "open"
			housing_deadline = -1.0
			_phase = "active"
		return

	var at_source := _device_item_at_source()
	match _device_phase:
		DEVICE_PHASE_AVAILABLE:
			# A moved item without our published reservation is not proof of this interaction.
			pass
		DEVICE_PHASE_CLAIMING:
			if at_source:
				_device_phase = DEVICE_PHASE_AVAILABLE
				_device_claimed_by = ""
			elif _device_claimed_by != "" and _device_item_holder() == _device_claimed_by:
				_device_phase = DEVICE_PHASE_CLAIMED
		DEVICE_PHASE_CLAIMED:
			pass

	device_retrieved = _device_phase == DEVICE_PHASE_CLAIMED
	if device_retrieved:
		housing_state = "open"
		housing_deadline = -1.0
		_phase = "complete"
		var actual_holder := _device_item_holder()
		if actual_holder != "":
			_device_claimed_by = actual_holder
		elif _device_claimed_by == "":
			_device_claimed_by = "stored"
		_device_claim_serial = maxi(1, _device_claim_serial)
	elif _phase == "complete":
		_phase = "active"


func _normalize_sac_authority(saved_version: int) -> void:
	# Recover the exact tagged item when the cached id was lost. Older carrier-string saves and the
	# old spawn-at-actor pickup seam have no durable reservation, so they retract to one visible pod
	# at the plant rather than minting or guessing inventory ownership.
	if not _is_live_sac_item_id(_sac_item_id):
		# Version 5 binds the transaction to one exact item. If that item is absent, a different
		# tagged sac is a forged duplicate rather than a substitute for a carried/claiming reward.
		# Older saves did not have that identity guarantee, so they may still recover their one
		# surviving tagged item before the legacy migration below.
		if saved_version < 5:
			_sac_item_id = _find_sac_item_id()
	_remove_duplicate_sac_items()
	if gas_sac_state == "carried":
		gas_sac_state = "tended" if saved_version < 4 else "active"

	if saved_version < 4 and gas_sac_state != "active":
		_remove_live_sac_item()
		_sac_item_id = _spawn_sac_source_item({"legacy_source_recovery": true}) \
			if gas_sac_state == "tended" else ""
		_sac_carrier = ""
		_sac_expires = -1.0
		return

	match gas_sac_state:
		"idle", "expired", "ignited":
			_remove_live_sac_item()
			_sac_expires = -1.0
			return
		"tended":
			if not _sac_item_at_source():
				_remove_live_sac_item()
				_sac_item_id = _spawn_sac_source_item()
			_sac_carrier = ""
			_sac_expires = -1.0
			return
		"claiming":
			if _sac_item_at_source():
				gas_sac_state = "tended"
				_sac_carrier = ""
				_sac_expires = -1.0
				return
			if _sac_carrier != "" and _sac_holder() == _sac_carrier and _sac_expires >= 0.0:
				gas_sac_state = "active"
				_sac_claim_serial = maxi(1, _sac_claim_serial)
				return
			if _live_sac_item_state().is_empty():
				# The reserved exact item never committed to a hand. Retract the interrupted claim
				# to one new visible source pod instead of leaving a permanent soft lock.
				_remove_live_sac_item()
				_sac_item_id = _spawn_sac_source_item()
				gas_sac_state = "tended"
				_sac_carrier = ""
				_sac_expires = -1.0
				return
			# Wrong-holder injection remains unresolved and is never silently retargeted.
			return

	if gas_sac_state == "active" and not _live_sac_item_state().is_empty() and _sac_expires >= 0.0:
		_sac_carrier = _sac_holder()
		_sac_claim_serial = maxi(1, _sac_claim_serial)
		return
	if gas_sac_state == "active":
		gas_sac_state = "expired"
	_remove_live_sac_item()
	_sac_carrier = ""
	_sac_expires = -1.0


func _remove_duplicate_sac_items() -> void:
	var gs = _get_game_state()
	if gs == null or not "items" in gs:
		return
	var duplicate_ids: Array[String] = []
	for item_id_v in gs.items.keys():
		var item_id := str(item_id_v)
		if item_id != _sac_item_id and _is_live_sac_item_id(item_id):
			duplicate_ids.append(item_id)
	duplicate_ids.sort()
	for item_id in duplicate_ids:
		_remove_item(item_id)


func _cancel_inflammashunt_callbacks() -> void:
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("inflam_shared")
		sched.cancel_tag("inflam_root")
		sched.cancel_tag("inflam_reform")
		sched.cancel_tag("inflam_water_flow")
		sched.cancel_tag("inflam_root_connect")
		sched.cancel_tag("inflam_housing_open")
	_polls_armed = false


func _retract_inflammashunt_presenter_to_defaults() -> void:
	_remove_live_sac_item()
	_remove_device_items()
	_restoring_inflammashunt_authority = true
	_phase = "ready"
	for key_v in route_info.keys():
		route_info[str(key_v)] = false
	valve_open = false
	water_phase = "dry"
	water_deadline = -1.0
	char_a_state = "dry"
	char_b_state = "dry"
	root_state = "suppressed"
	root_connect_deadline = -1.0
	buffer_state = "stable"
	gas_sac_state = "idle"
	healing_zone = 0.0
	housing_unlocked = false
	housing_state = "sealed"
	housing_deadline = -1.0
	device_retrieved = false
	_device_phase = DEVICE_PHASE_AVAILABLE
	_device_item_id = ""
	_device_claimed_by = ""
	_device_claim_serial = 0
	_sac_claim_serial = 0
	_terminal_hacked = false
	_source_committed_counts.clear()
	_active_source_receipt.clear()
	wrong_events.clear()
	long_hold_count = 0
	_entry_played = false
	_reports.clear()
	_reunion_played = false
	_popcorn = false
	_sac_item_id = ""
	_sac_carrier = ""
	_sac_expires = -1.0
	_rage_until = -1.0
	_raged.clear()
	_whip_ready.clear()
	_polls_armed = false
	_shared_poll_deadline = -1.0
	_root_timer_mode = ""
	_root_deadline = -1.0
	_buffer_reform_deadline = -1.0
	_restore_dynamic_enemy_presenters([], false)
	_ensure_device_source_item()
	_apply_inflammashunt_presenters()
	_restoring_inflammashunt_authority = false


func _apply_inflammashunt_presenters() -> void:
	_sync_char_visuals()
	_sync_healing_visual()
	_sync_transition_presenters()
	_sync_inflammashunt_source_presenters()
	_set_causal_feedback_latched(_valve_it, water_phase == "flowing")
	_set_causal_feedback_mode(_valve_it,
		"active" if water_phase == "flowing" else ("complete" if water_phase == "full" else "predicted"))
	_set_causal_feedback_latched(_root_it, root_state == "connecting")
	_set_causal_feedback_mode(_root_it,
		"active" if root_state == "connecting" else ("complete" if root_state == "connected" else "predicted"))
	_sync_healing_visual()
	for husk in _husks:
		if is_instance_valid(husk):
			husk.visible = buffer_state == "stable"
	if gas_sac_state == "active":
		_sac_carrier = _sac_holder()
	elif gas_sac_state != "claiming":
		_sac_carrier = ""
	_refresh_hold_times()


func _restore_dynamic_enemy_presenters(extra_ids_raw: Array, root_present: bool) -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var wanted: Dictionary = {}
	for id_v in extra_ids_raw:
		var id := str(id_v)
		if id.begins_with("chelator_x"):
			wanted[id] = true
	for enemy in _extra_chelators.duplicate():
		if not is_instance_valid(enemy):
			_extra_chelators.erase(enemy)
			_enemies.erase(enemy)
			continue
		var id := str(enemy.char_id)
		if wanted.has(id) and gs.characters.has(id):
			continue
		_extra_chelators.erase(enemy)
		_enemies.erase(enemy)
		if gs.characters.has(id):
			gs.unregister_character(id)
		enemy.set_process(false)
		enemy.call_deferred("queue_free")
	for id_v in wanted.keys():
		var id := str(id_v)
		if not gs.characters.has(id) or _find_extra_chelator(id) != null:
			continue
		_create_restored_extra_chelator(id)

	var want_root: bool = root_present and gs.characters.has("hostile_root")
	if _root_enemy != null and is_instance_valid(_root_enemy) and not want_root:
		_enemies.erase(_root_enemy)
		if gs.characters.has("hostile_root"):
			gs.unregister_character("hostile_root")
		_root_enemy.set_process(false)
		_root_enemy.call_deferred("queue_free")
		_root_enemy = null
	if want_root and (_root_enemy == null or not is_instance_valid(_root_enemy)):
		_create_restored_hostile_root()


func _find_extra_chelator(char_id: String):
	for enemy in _extra_chelators:
		if is_instance_valid(enemy) and str(enemy.char_id) == char_id:
			return enemy
	return null


func _create_restored_extra_chelator(char_id: String) -> void:
	var gs = _get_game_state()
	if gs == null or not gs.characters.has(char_id):
		return
	var enemy := Enemy.new()
	enemy.name = "Enemy_%s" % char_id
	enemy.scale = Vector3.ONE * 0.62
	enemy.color = Color(0.5, 0.16, 0.08)
	enemy.move_speed = 2.2
	enemy.detection_range = 0.0
	enemy.windup_duration = 0.4
	enemy.recover_duration = 0.8
	enemy.charge_speed = 6.0
	enemy.attack_range = 1.5
	enemy.charge_damage = 6.0
	enemy._detection_targets.assign(_party)
	enemy.char_id = char_id
	enemy.game_state = gs
	add_child(enemy)
	enemy.global_position = gs.get_render_position(char_id)
	enemy.activate()
	_extra_chelators.append(enemy)
	_enemies.append(enemy)


func _create_restored_hostile_root() -> void:
	var gs = _get_game_state()
	if gs == null or not gs.characters.has("hostile_root"):
		return
	var root := ChainEnemy.new()
	root.name = "Enemy_hostile_root"
	root.segment_count = 7
	root.char_id = "hostile_root"
	root.game_state = gs
	add_child(root)
	root.global_position = gs.get_render_position("hostile_root")
	_root_enemy = root
	_enemies.append(root)


func _valid_string(raw: Variant, allowed: Array, fallback: String) -> String:
	var value := str(raw)
	return value if value in allowed else fallback


# --- Helpers ---

func _now() -> float:
	var sched = _get_scheduler()
	return float(sched.get_current_tick()) if sched != null else 0.0

func _nearest_party_to(pos: Vector3) -> String:
	var gs = _get_game_state()
	if gs == null:
		return ""
	var best := ""
	var best_d := INF
	for cid in _party:
		if not gs.characters.has(cid) or gs.is_downed(cid):
			continue
		var d: float = pos.distance_to(gs.get_position(cid))
		if d < best_d:
			best_d = d
			best = str(cid)
	return best

## Route info is EFFICIENCY: informed holds are short, uninformed holds are long.
func _refresh_hold_times() -> void:
	if _valve_it != null:
		_valve_it.dwell_time = HOLDS["valve"][0] if route_info["aster_pipe_diagram"] else HOLDS["valve"][1]
	if _char_a_it != null:
		_char_a_it.dwell_time = (1.0 if char_a_state in ["dry", "burned"]
			else (HOLDS["char_a"][0] if route_info["myke_char_feed"] else HOLDS["char_a"][1]))
	if _char_b_it != null:
		_char_b_it.dwell_time = (1.0 if char_b_state in ["dry", "burned"]
			else (HOLDS["char_b"][0] if route_info["myke_char_feed"] else HOLDS["char_b"][1]))
	if _root_it != null:
		_root_it.dwell_time = HOLDS["root"][0] if route_info["peris_living_junction"] else HOLDS["root"][1]

func _sync_char_visuals() -> void:
	var colors := {
		"dry": Color(0.05, 0.045, 0.04),
		"damp": Color(0.03, 0.032, 0.04),
		"burned": Color(0.12, 0.05, 0.02),
		"cleared": Color(0.14, 0.14, 0.15),
	}
	if _char_a_mesh != null and is_instance_valid(_char_a_mesh):
		_char_a_mesh.material_override = _make_material(colors.get(char_a_state, colors["dry"]))
		_char_a_mesh.visible = char_a_state != "cleared"
	if _char_b_mesh != null and is_instance_valid(_char_b_mesh):
		_char_b_mesh.material_override = _make_material(colors.get(char_b_state, colors["dry"]))
		_char_b_mesh.visible = char_b_state != "cleared"
	_refresh_hold_times()

func _sync_healing_visual() -> void:
	if _healing_glow == null or not is_instance_valid(_healing_glow):
		return
	# The visible expansion is caused by opening the resolution cycle to the grate, not by the
	# inventory flag that follows. Picking the device up therefore cannot be the hidden VFX switch.
	var spread := 0.8 + healing_zone * (3.4 if housing_state == "open" else 2.2)
	_healing_glow.scale = Vector3(spread, 1.0, spread)

# --- State surfaces (spec: headless_get_state) ---

func reset_preview_state() -> void:
	super.reset_preview_state()
	_cancel_inflammashunt_callbacks()
	_retract_inflammashunt_presenter_to_defaults()
	if _popcorn_field != null and is_instance_valid(_popcorn_field):
		_popcorn_field.set_active(false)
	var gs = _get_game_state()
	if gs != null:
		gs.set_interactable_enabled(_interactable_data_id("ThermalResetConfirm"), false)
	_ensure_polls()
	_publish_inflammashunt_authority()


func headless_get_state() -> Dictionary:
	return {
		"current_step": "complete" if device_retrieved else "ready",
		"route_info": route_info.duplicate(),
		"valve_open": valve_open,
		"water_phase": water_phase,
		"water_deadline": water_deadline,
		"char_a_state": char_a_state,
		"char_b_state": char_b_state,
		"root_state": root_state,
		"root_connect_deadline": root_connect_deadline,
		"buffer_state": buffer_state,
		"gas_sac_state": gas_sac_state,
		"healing_zone": healing_zone,
		"housing_unlocked": housing_unlocked,
		"housing_state": housing_state,
		"housing_deadline": housing_deadline,
		"device_retrieved": device_retrieved,
		"device_phase": _device_phase,
		"device_item_id": _device_item_id,
		"device_item_at_source": _device_item_at_source(),
		"device_item_holder": _device_item_holder(),
		"device_claimed_by": _device_claimed_by,
		"device_claim_serial": _device_claim_serial,
		"sac_claim_serial": _sac_claim_serial,
		"terminal_hacked": _terminal_hacked,
		"source_committed_counts": _source_committed_counts.duplicate(true),
		"process_presenters": {
			"water_visible": _visible_process_segment_count(_water_route_segments),
			"water_total": _water_route_segments.size(),
			"filaments_visible": _visible_process_segment_count(_root_filament_segments),
			"filaments_total": _root_filament_segments.size(),
			"lid_angle": _housing_lid_pivot.rotation.x if _housing_lid_pivot != null else 0.0,
		},
		"wrong_events": wrong_events.duplicate(),
		"active_hazards": {"popcorn": _popcorn, "hostile_root": _root_enemy != null and is_instance_valid(_root_enemy), "rage": _rage_until > 0.0},
		"long_hold_count": long_hold_count,
		"sac_item_id": _sac_item_id,
		"sac_carrier": _sac_holder(),
		"sac_reserved_carrier": _sac_carrier if gas_sac_state == "claiming" else "",
		"sac_item_at_source": _sac_item_at_source(),
		"reports": _reports.duplicate(),
	}

func get_preview_state() -> Dictionary:
	var st: Dictionary = super.get_preview_state()
	st.merge(headless_get_state(), true)
	return st


func _visible_process_segment_count(segments: Array[MeshInstance3D]) -> int:
	var visible := 0
	for segment in segments:
		if segment != null and is_instance_valid(segment) and segment.visible:
			visible += 1
	return visible
