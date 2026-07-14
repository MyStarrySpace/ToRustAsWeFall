extends "res://scripts/fragments/chunks/data_fragment_chunk.gd"

## THE INFLAMMASHUNT (danger zone; canonical spec data/puzzles/inflammashunt_puzzle.md, shadow
## path inflammashunt_shadow_solution.md): the Resolution Catalyst retrieval — the Manage
## Conflict puzzle. Three character-coded INFORMATION routes feed a shared eight-interactable
## junction room; every route report is honest and confidently WRONG; the correct solve is
## "water, clean, clean, tend, open". Route info is EFFICIENCY, not a gate (informed holds are
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
var char_a_state := "dry"        # dry, damp, cleared, burned
var char_b_state := "dry"
var root_state := "suppressed"   # suppressed, tame, hostile, recovering, connected
var buffer_state := "stable"     # stable, shattered, reforming
var gas_sac_state := "idle"      # idle, tended, carried, expired, ignited
var healing_zone := 0.0
var housing_unlocked := false
var device_retrieved := false
var wrong_events: Array = []
var long_hold_count := 0

var _party: Array = ["aster", "peris", "myke"]
var _entry_played := false
var _reports := {}               # route -> true once the confident wrong answer played
var _reunion_played := false
var _popcorn := false
var _popcorn_field = null
var _sac_carrier := ""
var _sac_expires := -1.0
var _sac_visual: MeshInstance3D
var _rage_until := -1.0
var _raged := {}                 # chelator id -> true while in the woken encounter
var _extra_chelators: Array = []
var _root_enemy: ChainEnemy
var _whip_ready := {}
var _polls_armed := false
var _healing_glow: MeshInstance3D
var _char_a_mesh: MeshInstance3D
var _char_b_mesh: MeshInstance3D
var _husks: Array = []

var _valve_it: Area3D
var _char_a_it: Area3D
var _char_b_it: Area3D
var _root_it: Area3D
var _flora_it: Area3D
var _take_sac_it: Area3D
var _terminal_it: Area3D
var _reset_it: Area3D
var _housing_it: Area3D
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
	_spawn_active_chelators()
	_refresh_hold_times()

func _update(delta: float) -> void:
	super._update(delta)
	_ensure_polls()

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
		Vector3(20.0, 0.6, -11.5), "READ LOG", "aster", 1.0, false, 1.6)
	_outline_interactable_child(a1, _add_box(a1, Vector3(0, 0.55, 0), Vector3(0.7, 1.1, 0.4),
		Color(0.14, 0.16, 0.2), Color(0.36, 0.91, 0.5), 0.5), "AsterLogTerminal", 1.6)
	a1.interacted.connect(_on_aster_log)
	var a2 := _add_interactable(self, "PipeDiagram", "Scan the pipe junction diagram",
		Vector3(24.0, 0.6, -11.5), "SCAN DIAGRAM", "aster", 1.0, false, 1.6)
	_outline_interactable_child(a2, _add_box(a2, Vector3(0, 0.9, -0.4), Vector3(1.6, 1.2, 0.12),
		Color(0.16, 0.18, 0.22), Color(0.5, 0.7, 0.95), 0.4), "PipeDiagram", 1.6)
	a2.interacted.connect(_on_pipe_diagram)
	# Route B (Peris): dead roots + the living root-Chelator junction
	_add_label(self, "B — UNDERGROWTH", Vector3(22.0, 2.9, 8.0), Color(0.45, 0.85, 0.6))
	var p1 := _add_interactable(self, "DeadRootNetwork", "Examine the dead root network",
		Vector3(20.0, 0.4, 11.5), "EXAMINE ROOTS", "peris", 1.0, false, 1.6)
	_outline_interactable_child(p1, _add_box(p1, Vector3(0, 0.2, 0), Vector3(1.7, 0.4, 1.0),
		Color(0.16, 0.13, 0.1)), "DeadRootNetwork", 1.7)
	p1.interacted.connect(_on_dead_roots)
	var p2 := _add_interactable(self, "LivingJunction", "Examine the living root-Chelator junction",
		Vector3(24.0, 0.4, 11.5), "EXAMINE JUNCTION", "peris", 1.0, false, 1.6)
	_outline_interactable_child(p2, _add_box(p2, Vector3(0, 0.25, 0), Vector3(1.4, 0.5, 1.0),
		Color(0.14, 0.2, 0.15), Color(0.4, 0.9, 0.55), 0.6), "LivingJunction", 1.7)
	p2.interacted.connect(_on_living_junction)
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
		Vector3(31.8, 0.4, -13.2), "WATCH FEEDERS", "myke", 1.0, false, 1.6)
	_outline_interactable_child(m1, _add_box(m1, Vector3(0, 0.3, 0.5), Vector3(1.2, 0.6, 0.14),
		Color(0.14, 0.14, 0.15)), "GrateObservation", 1.6)
	m1.interacted.connect(_on_grate_observation)
	var m2 := _add_interactable(self, "DeviceGap", "Sight the device through the gap",
		Vector3(34.2, 0.4, -13.2), "SIGHT DEVICE", "myke", 1.0, false, 1.6)
	_outline_interactable_child(m2, _add_box(m2, Vector3(0, 0.3, 0.5), Vector3(1.2, 0.6, 0.14),
		Color(0.14, 0.14, 0.15), Color(0.5, 0.9, 0.62), 0.3), "DeviceGap", 1.6)
	m2.interacted.connect(_on_device_gap)

func _wire_myke_crawl(crawl: CrawlTunnel) -> void:
	crawl.requirement = func() -> bool: return str(crawl.active_character) == "myke"
	crawl.refused.connect(func() -> void:
		_show_note("The gap is a hand-span wide. Only Myke could fit through there.", 2.4))
	add_child(crawl)
	_register_interactable(crawl)
	var stub := _add_box(crawl, Vector3(0.0, 0.35, 0.0), Vector3(0.5, 0.7, 0.5), Color(0.1, 0.1, 0.11))
	_outline_interactable_child(crawl, stub, crawl.name, 1.4)

# --- The junction room: eight interactables in one shared space ---

func _build_junction_room() -> void:
	var gs = _get_game_state()
	# 1. drainage valve (wall-mounted, near the terminal but visually distinct)
	_valve_it = _add_interactable(self, "DrainageValve", "Open the drainage valve",
		VALVE_POS, "OPEN VALVE", "", HOLDS["valve"][1], false, 1.7,
		Interactable.InteractableType.TIMED_ACTION)
	_outline_interactable_child(_valve_it, _add_box(_valve_it, Vector3(0, 0.4, -0.5), Vector3(0.9, 0.9, 0.35),
		Color(0.2, 0.28, 0.34), Color(0.4, 0.7, 0.9), 0.4), "DrainageValve", 1.7)
	_valve_it.interacted.connect(_on_valve)
	# 2 + 3. char deposits
	_char_a_mesh = _add_box(self, CHAR_A_POS + Vector3(0, 0.12, 0), Vector3(2.2, 0.24, 1.8), Color(0.05, 0.045, 0.04))
	_char_a_it = _add_interactable(self, "CharDepositA", "Clear the char deposit",
		CHAR_A_POS, "CLEAR CHAR", "", HOLDS["char_a"][1], false, 1.7,
		Interactable.InteractableType.TIMED_ACTION)
	_outline_interactable_child(_char_a_it, _add_box(_char_a_it, Vector3(0, 0.1, 0), Vector3(1.6, 0.2, 1.3),
		Color(0.06, 0.055, 0.05)), "CharDepositA", 1.8)
	_char_a_it.interacted.connect(func() -> void: _on_char_deposit("a"))
	_char_b_mesh = _add_box(self, CHAR_B_POS + Vector3(0, 0.12, 0), Vector3(1.8, 0.24, 1.5), Color(0.05, 0.045, 0.04))
	_char_b_it = _add_interactable(self, "CharDepositB", "Clear the char deposit by the root crack",
		CHAR_B_POS, "CLEAR CHAR", "", HOLDS["char_b"][1], false, 1.6,
		Interactable.InteractableType.TIMED_ACTION)
	_outline_interactable_child(_char_b_it, _add_box(_char_b_it, Vector3(0, 0.1, 0), Vector3(1.3, 0.2, 1.1),
		Color(0.06, 0.055, 0.05)), "CharDepositB", 1.7)
	_char_b_it.interacted.connect(func() -> void: _on_char_deposit("b"))
	# 4. the root tendril in the floor crack near char B
	var crack := _add_box(self, ROOT_BASE_POS + Vector3(0, 0.03, 0), Vector3(1.2, 0.06, 0.5), Color(0.03, 0.03, 0.03))
	crack.name = "RootCrack"
	_root_it = _add_interactable(self, "RootTendril", "Tend the suppressed root tendril",
		ROOT_BASE_POS, "TEND ROOT", "peris", HOLDS["root"][1], false, 1.5,
		Interactable.InteractableType.TIMED_ACTION)
	_outline_interactable_child(_root_it, _add_box(_root_it, Vector3(0, 0.18, 0), Vector3(0.35, 0.36, 0.35),
		Color(0.16, 0.24, 0.17), Color(0.4, 0.9, 0.55), 0.25), "RootTendril", 1.5)
	_root_it.interacted.connect(_on_tend_root)
	# 5. the dormant Chelator ring: examine is the read, strike is the mistake
	for i in range(5):
		var ang := TAU * float(i) / 5.0
		var husk := _add_box(self, RING_CENTER + Vector3(cos(ang) * 2.1, 0.3, sin(ang) * 2.1),
			Vector3(0.6, 0.6, 0.6), Color(0.22, 0.16, 0.12), Color(0.7, 0.45, 0.25), 0.18)
		husk.name = "DormantHusk%d" % i
		_husks.append(husk)
	_examine_it = _add_interactable(self, "ExamineCluster", "Examine the dormant Chelator ring",
		RING_CENTER + Vector3(-2.0, 0.4, -0.9), "EXAMINE", "", 1.0, false, 1.6)
	_outline_interactable_child(_examine_it, _add_box(_examine_it, Vector3(0, 0.25, 0), Vector3(0.3, 0.5, 0.3),
		Color(0.2, 0.2, 0.22), Color(0.55, 0.75, 1.0), 0.3), "ExamineCluster", 1.6)
	_examine_it.interacted.connect(_on_examine_cluster)
	_strike_it = _add_interactable(self, "StrikeCluster", "Strike the dormant Chelators",
		RING_CENTER + Vector3(1.6, 0.4, -1.1), "STRIKE", "", 1.0, false, 1.6)
	_outline_interactable_child(_strike_it, _add_box(_strike_it, Vector3(0, 0.2, 0), Vector3(0.4, 0.4, 0.4),
		Color(0.24, 0.14, 0.12), Color(0.9, 0.4, 0.25), 0.3), "StrikeCluster", 1.6)
	_strike_it.interacted.connect(_on_strike_cluster)
	# 6. gas sac flora in the damp corner (Gasafoetida — flora_taxonomy: Peris-only tend,
	# carryable repellent pod)
	_flora_it = _add_interactable(self, "GasSacFlora", "Tend the gas sac flora",
		FLORA_POS, "TEND FLORA", "peris", 2.0, false, 1.7,
		Interactable.InteractableType.TIMED_ACTION)
	_outline_interactable_child(_flora_it, _add_box(_flora_it, Vector3(0, 0.35, 0), Vector3(0.8, 0.7, 0.8),
		Color(0.2, 0.26, 0.16), Color(0.6, 0.8, 0.3), 0.4), "GasSacFlora", 1.7)
	_flora_it.interacted.connect(_on_tend_flora)
	_take_sac_it = _add_interactable(self, "TakeSac", "Take the swollen gas sac",
		FLORA_POS + Vector3(1.3, 0.3, 0.4), "TAKE SAC", "", 0.8, false, 1.4)
	_outline_interactable_child(_take_sac_it, _add_box(_take_sac_it, Vector3(0, 0.18, 0), Vector3(0.35, 0.35, 0.35),
		Color(0.35, 0.5, 0.2), Color(0.7, 0.9, 0.3), 0.5), "TakeSac", 1.4)
	_take_sac_it.interacted.connect(_on_take_sac)
	# 7. the terminal (hack = read-only diagnostics; the reset command is the trap)
	_terminal_it = _add_interactable(self, "JunctionTerminal", "Hack the maintenance terminal",
		TERMINAL_POS, "HACK", "aster", 1.0, false, 1.7)
	_outline_interactable_child(_terminal_it, _add_box(_terminal_it, Vector3(0, 0.5, -0.5), Vector3(0.9, 1.0, 0.3),
		Color(0.13, 0.15, 0.19), Color(0.36, 0.91, 0.5), 0.6), "JunctionTerminal", 1.7)
	_terminal_it.interacted.connect(_on_hack_terminal)
	_reset_it = _add_interactable(self, "ThermalResetConfirm", "Initiate the logged thermal reset",
		TERMINAL_POS + Vector3(1.5, 0.5, 0.6), "THERMAL RESET", "aster", 1.2, false, 1.4)
	_outline_interactable_child(_reset_it, _add_box(_reset_it, Vector3(0, 0.3, 0), Vector3(0.32, 0.6, 0.32),
		Color(0.3, 0.12, 0.1), Color(0.95, 0.3, 0.15), 0.7), "ThermalResetConfirm", 1.4)
	_reset_it.interacted.connect(_on_thermal_reset)
	# 8. the device housing + the healing zone under the grate
	_housing_it = _add_interactable(self, "DeviceHousing", "Open the device housing",
		HOUSING_POS, "OPEN HOUSING", "", 1.2, false, 1.6,
		Interactable.InteractableType.TIMED_ACTION)
	_outline_interactable_child(_housing_it, _add_box(_housing_it, Vector3(0, 0.3, 0), Vector3(1.1, 0.6, 1.1),
		Color(0.18, 0.2, 0.22), Color(0.5, 0.9, 0.62), 0.3), "DeviceHousing", 1.7)
	_housing_it.interacted.connect(_on_open_housing)
	var grate := _add_box(self, GRATE_POS + Vector3(0, 0.02, 0), Vector3(2.2, 0.05, 2.2), Color(0.12, 0.13, 0.14))
	grate.name = "HealingGrate"
	_healing_glow = _add_box(self, GRATE_POS + Vector3(0, -0.35, 0), Vector3(0.8, 0.15, 0.8),
		Color(0.1, 0.2, 0.12), Color(0.45, 0.95, 0.55), 1.4)
	_healing_glow.name = "HealingZoneGlow"
	# the shadow observation point: watching the feeders from inside the room
	_observe_it = _add_interactable(self, "ObserveFeeding", "Watch the active Chelators around the char",
		CHAR_A_POS + Vector3(1.8, 0.4, 1.4), "OBSERVE", "", 1.0, false, 1.6)
	_outline_interactable_child(_observe_it, _add_box(_observe_it, Vector3(0, 0.06, 0), Vector3(0.9, 0.12, 0.9),
		Color(0.13, 0.14, 0.15), Color(0.55, 0.75, 1.0), 0.2), "ObserveFeeding", 1.6)
	_observe_it.interacted.connect(_on_observe_feeding)
	# the thermal-reset command is not offered until the terminal has been hacked
	if gs != null:
		gs.set_interactable_enabled(_interactable_data_id("ThermalResetConfirm"), false)

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

# --- Route handlers: every report is honest and confidently wrong ---

func _on_aster_log() -> void:
	route_info["aster_log"] = true
	_show_note("FINAL ENTRY // Resolution capacity exceeded. Recommend thermal reset. // Filed: same day as section removal from registry.", 4.2)
	_maybe_report("aster")
	_refresh_hold_times()

func _on_pipe_diagram() -> void:
	route_info["aster_pipe_diagram"] = true
	_show_note("Drainage routing — the valve feeds from the Plumbing Power Project. Flow and pressure ratings. Water infrastructure, not heat.", 3.8)
	_maybe_report("aster")
	_refresh_hold_times()

func _on_dead_roots() -> void:
	route_info["peris_dead_roots"] = true
	_show_note("The old network is hollow — tunneled from inside, then coated by char. It was eaten before it burned.", 3.6)
	_maybe_report("peris")
	_refresh_hold_times()

func _on_living_junction() -> void:
	route_info["peris_living_junction"] = true
	_show_note("Living filaments feed the dormant husks — and the husks feed the roots back. A cycle, still running.", 3.6)
	_maybe_report("peris")
	_refresh_hold_times()

func _on_grate_observation() -> void:
	route_info["myke_char_feed"] = true
	_show_note("The active crawlers aren't roaming. They're feeding — clustered on the char.", 3.2)
	_maybe_report("myke")
	_refresh_hold_times()

func _on_device_gap() -> void:
	route_info["myke_buffer_ring"] = true
	_show_note("Dormant crawlers ring the device — calm, inside. The active ones press from outside the ring.", 3.2)
	_maybe_report("myke")
	_refresh_hold_times()

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

func _on_valve() -> void:
	if not valve_open:
		if not route_info["aster_pipe_diagram"]:
			_long_hold(str(_valve_it.active_character))
		valve_open = true
		if char_a_state == "dry" or char_a_state == "burned":
			char_a_state = "damp"
		if char_b_state == "dry" or char_b_state == "burned":
			char_b_state = "damp"
		_sync_char_visuals()
		if _popcorn:
			_end_popcorn("The flood takes the fire. Scorched sacs drift in the runoff.")
		else:
			_show_note("The pipes rumble. The floor channels fill — the char darkens and steams. The crawlers recoil.", 3.6)
		_refresh_hold_times()

func _on_char_deposit(which: String) -> void:
	var it := _char_a_it if which == "a" else _char_b_it
	var actor := str(it.active_character)
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

func _burn_char(which: String) -> void:
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

func _on_tend_root() -> void:
	if root_state == "hostile" or root_state == "recovering":
		_show_note("The root is in no state to be tended.", 2.2)
		return
	if char_a_state != "cleared" or char_b_state != "cleared":
		_show_note("The pulse flickers under Peris's hands and dies down. The residue is still smothering it.", 3.2)
		if not route_info["peris_living_junction"]:
			_long_hold("peris")
		return
	if not route_info["peris_living_junction"]:
		_long_hold("peris")
	root_state = "connected"
	healing_zone = 1.0
	housing_unlocked = true
	_sync_healing_visual()
	_show_note("The root brightens. Filaments thread toward the dormant ring — and the glow under the grate spreads to the housing.", 4.0)

func _on_examine_cluster() -> void:
	_show_note("Warm. Connected by thin filaments. Not feeding, not moving — a perimeter.", 3.2)
	if route_info["peris_living_junction"] and not route_info["myke_buffer_ring"]:
		route_info["myke_buffer_ring"] = true
		_show_note("Peris: \"They're in the same state as the junction underground. It's a buffer — not a siege.\"", 3.6)
		_refresh_hold_times()

func _on_observe_feeding() -> void:
	_show_note("The active crawlers cluster on the char deposits. They don't wander off them.", 3.0)
	if route_info["aster_pipe_diagram"] and route_info["peris_living_junction"] \
			and not route_info["myke_char_feed"]:
		route_info["myke_char_feed"] = true
		_show_note("Aster: \"The system was built to flush something. They're eating it. The char is the food.\"", 3.6)
		_refresh_hold_times()

func _on_strike_cluster() -> void:
	if buffer_state != "stable":
		_show_note("The scattered husks don't react.", 2.0)
		return
	buffer_state = "shattered"
	_wrong("attacked_buffer")
	if root_state == "connected" and not device_retrieved:
		root_state = "suppressed"
		healing_zone = 0.0
		housing_unlocked = false
		_sync_healing_visual()
	_show_note("The ring shatters — and everything that was calm isn't. The root snaps back into its crack.", 3.4)
	for husk in _husks:
		if is_instance_valid(husk):
			husk.visible = false
	_wake_chelators(2)

func _on_tend_flora() -> void:
	if gas_sac_state == "ignited":
		_show_note("The flora is still burning. Nothing to tend yet.", 2.2)
		return
	gas_sac_state = "tended"
	_show_note("The flora swells under Peris's hands. A sac ripens, ready to carry.", 3.0)

func _on_take_sac() -> void:
	if gas_sac_state != "tended":
		_show_note("No ripe sac. The flora needs tending first.", 2.2)
		return
	var actor := str(_take_sac_it.active_character)
	if actor == "":
		return
	_sac_carrier = actor
	_sac_expires = _now() + SAC_DURATION
	gas_sac_state = "carried"
	_attach_sac_visual(actor)
	_show_note("%s carries the sac at arm's length. The smell peels paint — nothing rooted will come near it." % actor.capitalize(), 3.2)

func _on_hack_terminal() -> void:
	var gs = _get_game_state()
	_show_note("Read-only diagnostics: resolution loop INCOMPLETE // residue accumulating // flush line INTACT. One logged command is still queued: THERMAL RESET.", 4.2)
	if gs != null:
		gs.set_interactable_enabled(_interactable_data_id("ThermalResetConfirm"), true)

func _on_thermal_reset() -> void:
	if _popcorn:
		return
	_wrong("thermal_reset")
	gas_sac_state = "ignited"
	_popcorn = true
	_arm_popcorn_poll()
	_show_note("Heaters cough alive — and the gas sacs go up. Flaming sacs skip off the walls. The VALVE. Flood the room.", 3.8)

func _on_open_housing() -> void:
	if device_retrieved:
		return
	if not housing_unlocked:
		_show_note("It does not budge. The lock is warm, but the warmth is coming from below, not from the panel.", 3.4)
		return
	device_retrieved = true
	_phase = "complete"
	_set_preview_step("inflammashunt_complete")
	_sync_healing_visual()
	_show_note("The housing opens. The Inflammashunt — still running, still warm. Salvage worth the walk.", 3.6)
	var sched = _get_scheduler()
	if sched != null and _party.has("myke"):
		sched.schedule_after(4.0, func() -> void:
			_show_note("Myke: \"...Huh. So that's what it looks like when somebody finishes the job.\"", 3.8), "inflam_after")

# --- Wrong-approach machinery ---

func _wrong(event: String) -> void:
	wrong_events.append(event)
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
			var sched = _get_scheduler()
			if sched != null:
				sched.schedule_after(BUFFER_REFORM_SECS, _reform_buffer, "inflam_reform")

func _reform_buffer() -> void:
	buffer_state = "stable"
	for husk in _husks:
		if is_instance_valid(husk):
			husk.visible = true
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

func _arm_root_poll() -> void:
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("inflam_root")
		sched.schedule_after(0.35, _root_poll, "inflam_root")

func _root_poll() -> void:
	if not is_inside_tree() or _root_enemy == null or not is_instance_valid(_root_enemy):
		return
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if gs == null or sched == null:
		return
	var now := _now()
	var rp: Vector3 = gs.get_position("hostile_root")
	var carrier_live: bool = _sac_carrier != "" and now < _sac_expires and gs.characters.has(_sac_carrier)
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
				sched.schedule_after(ROOT_RETRACT_DELAY, _retract_root, "inflam_root")
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
	sched.schedule_after(0.35, _root_poll, "inflam_root")

func _retract_root() -> void:
	if _root_enemy == null or not is_instance_valid(_root_enemy):
		return
	var gs = _get_game_state()
	if gs != null and gs.characters.has("hostile_root"):
		gs.unregister_character("hostile_root")
	_enemies.erase(_root_enemy)
	_root_enemy.queue_free()
	_root_enemy = null
	root_state = "recovering"
	_show_note("The root pours itself back into the crack and stills.", 3.0)
	var sched = _get_scheduler()
	if sched != null:
		sched.schedule_after(ROOT_REGROW_DELAY, func() -> void:
			root_state = "suppressed"
			_show_note("A smaller tendril noses back out of the crack. Tame — and still smothered.", 3.0), "inflam_root")

# --- The popcorn hazard (thermal reset trap): a kit HazardField owns the burn; the chunk only
# --- places it over the junction and toggles it from its own mechanisms (reset lever / valve) ---

func _arm_popcorn_poll() -> void:
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
	_popcorn_field.set_active(true)

func _end_popcorn(msg: String) -> void:
	_popcorn = false
	gas_sac_state = "idle"
	if _popcorn_field != null and is_instance_valid(_popcorn_field):
		_popcorn_field.set_active(false)
	_show_note(msg, 3.4)

# --- The shared cadence poll ---

func _ensure_polls() -> void:
	if _polls_armed:
		return
	var sched = _get_scheduler()
	if sched == null:
		return
	_polls_armed = true
	sched.schedule_after(0.5, _shared_poll, "inflam_shared")

func _shared_poll() -> void:
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
	if _sac_carrier != "" and now >= _sac_expires:
		_sac_carrier = ""
		gas_sac_state = "expired"
		_detach_sac_visual()
		_show_note("The sac wilts and goes quiet. Peris can tend another.", 2.8)
	_cool_encounters(now)
	_check_reunion()
	sched.schedule_after(0.5, _shared_poll, "inflam_shared")

func _play_entry_beat() -> void:
	_entry_played = true
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
	var spread := 0.8 + healing_zone * (3.4 if device_retrieved else 2.2)
	_healing_glow.scale = Vector3(spread, 1.0, spread)

func _attach_sac_visual(actor: String) -> void:
	_detach_sac_visual()
	var node = _chunk_character_node(actor)
	if node == null:
		return
	_sac_visual = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	_sac_visual.mesh = sphere
	_sac_visual.material_override = _make_material(Color(0.5, 0.7, 0.25), Color(0.7, 0.9, 0.3), 0.8)
	_sac_visual.position = Vector3(0.5, 1.0, 0.0)
	node.add_child(_sac_visual)

func _detach_sac_visual() -> void:
	if _sac_visual != null and is_instance_valid(_sac_visual):
		_sac_visual.queue_free()
	_sac_visual = null

func _chunk_character_node(cid: String) -> Node3D:
	var host := get_parent()
	while host != null and not host.has_method("get_preview_state"):
		host = host.get_parent()
	if host != null and "_characters" in host:
		var chars: Dictionary = host.get("_characters")
		if chars.has(cid):
			return chars[cid]
	return null

# --- State surfaces (spec: headless_get_state) ---

func headless_get_state() -> Dictionary:
	return {
		"current_step": "complete" if device_retrieved else "ready",
		"route_info": route_info.duplicate(),
		"valve_open": valve_open,
		"char_a_state": char_a_state,
		"char_b_state": char_b_state,
		"root_state": root_state,
		"buffer_state": buffer_state,
		"gas_sac_state": gas_sac_state,
		"healing_zone": healing_zone,
		"housing_unlocked": housing_unlocked,
		"device_retrieved": device_retrieved,
		"wrong_events": wrong_events.duplicate(),
		"active_hazards": {"popcorn": _popcorn, "hostile_root": _root_enemy != null and is_instance_valid(_root_enemy), "rage": _rage_until > 0.0},
		"long_hold_count": long_hold_count,
		"sac_carrier": _sac_carrier,
		"reports": _reports.duplicate(),
	}

func get_preview_state() -> Dictionary:
	var st: Dictionary = super.get_preview_state()
	st.merge(headless_get_state(), true)
	return st
