@tool
extends "res://scripts/tutorial/tutorial_sequence.gd"

const FloraMemorySystem = preload("res://scripts/system/simulation/flora_memory_system.gd")
const ENDO_JUNCTION_STRETCH_CHUNK_SCENE := preload("res://scenes/fragments/chunks/endo_junction_stretch_chunk.tscn")
const LOCKOUT_CHASE_CHUNK_SCENE := preload("res://scenes/fragments/chunks/lockout_chase_chunk.tscn")
const LevelDecoratorScript := preload("res://scripts/generation/level_decorator.gd")
const OPENING_FADE_DURATION := 2.5

## Act 1 chunk sequence: Channels, Stacks, Rings, Lockout.
## The Endo's-Junction-to-Shelter-1 SCENE chunk (a self-contained SceneChunk, unlike the four
## procedural chunks above) is reachable as its own leg via start_chunk == "endo_junction_stretch".

var _aster_node: CharacterBody3D
var _peris_node: CharacterBody3D
var _endo: CharacterBody3D
var _active_character := "aster"
var _channels_flure: MeshInstance3D
var _channels_flure_light: OmniLight3D
var _channels_flow_strips: Array[MeshInstance3D] = []
var _channels_flush_swarm_units: Array[Dictionary] = []
var _channels_run_lure_mesh: MeshInstance3D
var _channels_run_lure_light: OmniLight3D
var _channels_run_lure_interactable
var _channels_hide_spot: Node3D
var _channels_swarm_units: Array[Dictionary] = []
var _channels_window_lanes: Dictionary = {}
var _channels_active_window_lane := ""
var _channels_shortcut_gate_mesh: MeshInstance3D
var _channels_shortcut_gate_collision: CollisionShape3D
var _channels_shortcut_light: OmniLight3D
var _channels_run_lure_active := false
var _channels_run_lure_expire_tick := -1.0
var _channels_party_hidden := false
var _channels_encounter_resetting := false
var _channels_flow_power := 0.0
var _channels_flush_state := ""
var _channels_flush_timer := 0.0
var _channels_shortcut_unlocked := false
var _channels_party_recuperated := false
var _channels_shelter_reached := false
var _channels_field_sites: Dictionary = {}
var _channels_field_visuals: Dictionary = {}
var _channels_field_route_visuals: Dictionary = {}
var _channels_field_completed: Dictionary = {}
var _channels_field_operations_completed: Dictionary = {}
var _channels_field_phase := ""
var _channels_field_choices: Dictionary = {}
var _channels_field_attempts: Dictionary = {}
var _channels_optional_findings: Dictionary = {}
var _channels_field_decisions := 0

const STACKS_SUPPORT_LOG_KEY := "stacks_support_team_log"
var _stacks_signal_interactable
var _stacks_terminal_interactable
var _stacks_workspace_interactable
var _stacks_support_log_entry_id := -1
var _stacks_support_log_presented := false
var _stacks_signal_interacted := false
var _stacks_terminal_interacted := false
var _stacks_archive_interacted := false
var _stacks_audit_flags_found := false
var _stacks_bank_interactables: Dictionary = {}
var _stacks_bank_samples: Dictionary = {}
var _stacks_bank_resolved := false
var _stacks_bank_attempts := 0
const STACKS_GHOST_BANK := "bank_b"
var _stacks_field_sites: Dictionary = {}
var _stacks_field_visuals: Dictionary = {}
var _stacks_field_routes: Dictionary = {}
var _stacks_field_completed: Dictionary = {}
var _stacks_field_operations_completed: Dictionary = {}
var _stacks_field_phase := ""
var _stacks_field_choices: Dictionary = {}
var _stacks_field_effects: Dictionary = {}
var _stacks_field_decisions := 0

# Rings is a spatial visit, not an autoplay cutscene: the former client and three traces gate
# progress across the district so reading its story requires actually moving through the homes.
var _rings_client_interactable
var _rings_trace_interactables: Dictionary = {}
var _rings_trace_seen: Dictionary = {}
var _rings_client_seen := false
const RINGS_TRACE_ORDER := ["client_bloom", "forget_me_not", "doorvine"]
var _rings_field_sites: Dictionary = {}
var _rings_field_visuals: Dictionary = {}
var _rings_field_routes: Dictionary = {}
var _rings_field_completed: Dictionary = {}
var _rings_field_operations_completed: Dictionary = {}
var _rings_field_phase := ""
var _rings_field_choices: Dictionary = {}
var _rings_field_effects: Dictionary = {}
var _rings_field_decisions := 0

@export var start_chunk := ""

# Iron hazard zones
var _iron_patches: Array[Dictionary] = []
const IRON_DAMAGE_PER_SEC := 8.0

# HP
var _aster_hp := 100.0
var _peris_hp := 100.0

# Naturalizers (lockout chase)
var _naturalizers: Array[Node3D] = []

# Overlay + flora state
var _overlay_ui: CanvasLayer
var _overlay_buttons: Dictionary = {}
var _overlay_note_label: Label
var _overlay_status_label: Label
var _overlay_note_timer := 0.0
var _overlay_states := {
	"aster": true,
	"peris": true,
}
var _flora_overlay_root: Node3D
var _flora_marker_nodes: Dictionary = {}
var _flora_nodes: Dictionary = {}
var _flora_system := FloraMemorySystem.new()

const FLORA_SMELL_RADIUS := 2.25

# Linear progression along +X.
const CHANNELS_START := Vector3(0, 0, 0)
const CHANNELS_END := Vector3(228, 0, 0)
const CHANNELS_MEMORY_TRIGGER_X := 54.0
const CHANNELS_BODY_POS := Vector3(74.0, 0.5, -3.0)
const CHANNELS_WINDOW_ONE_STAGE_POS := Vector3(104.0, 0.5, -2.0)
const CHANNELS_WINDOW_ONE_LURE_POS := Vector3(110.0, 0.5, -13.0)
const CHANNELS_WINDOW_ONE_CURTAIN_POS := Vector3(122.0, 0.6, -1.0)
const CHANNELS_WINDOW_ONE_GOAL_POS := Vector3(132.0, 0.5, 0.0)
const CHANNELS_WINDOW_ONE_DURATION := 13.5
const CHANNELS_FLURE_TRIGGER_X := 146.0
const CHANNELS_FLURE_POS := Vector3(156.0, 0.5, 9.0)
const CHANNELS_FLUSH_SWARM_POS := Vector3(162.0, 0.6, 8.8)
const CHANNELS_FLUSH_SWARM_OFFSETS := [-1.6, -0.8, 0.0, 0.8, 1.6]
const CHANNELS_WINDOW_TWO_STAGE_POS := Vector3(166.0, 0.5, 2.0)
const CHANNELS_WINDOW_TWO_LURE_POS := Vector3(170.0, 0.5, 13.0)
const CHANNELS_WINDOW_TWO_CURTAIN_POS := Vector3(179.0, 0.6, 1.0)
const CHANNELS_WINDOW_TWO_GOAL_POS := Vector3(184.0, 0.5, 0.0)
const CHANNELS_WINDOW_TWO_DURATION := 9.5
const CHANNELS_ENCOUNTER_TRIGGER_X := 192.0
const CHANNELS_ENCOUNTER_ENTRY_POS := Vector3(194.0, 0.5, 3.0)
const CHANNELS_RUN_LURE_POS := Vector3(198.0, 0.5, 1.5)
const CHANNELS_HIDE_SPOT_POS := Vector3(204.0, 0.5, -10.0)
const CHANNELS_SWARM_CLUSTER_X := 211.0
const CHANNELS_SWARM_DETECT_RADIUS := 2.2
const CHANNELS_SWARM_SPEED := 1.7
const CHANNELS_RUN_LURE_DURATION := 20.0
const CHANNELS_SWARM_OFFSETS := [-2.4, -1.6, -0.8, 0.0, 0.8, 1.6, 2.4]
const CHANNELS_WINDOW_CURTAIN_OFFSETS := [-4.0, -2.0, 0.0, 2.0, 4.0]
const CHANNELS_WINDOW_DETECT_RADIUS := 3.0
const CHANNELS_WINDOW_PERIODIC_CHANNELS := 3
const CHANNELS_WINDOW_FLOW_PERIOD := 6.0
const CHANNELS_WINDOW_FLOOD_DURATION := 4.0
const CHANNELS_WINDOW_SWARM_SPEED := 3.6
const CHANNELS_WINDOW_SWARM_DELAY := 0.12
const CHANNELS_WINDOW_SWARM_WASH_SPEED := 8.6
const CHANNELS_WINDOW_CHANNEL_WASH_RADIUS := 1.9
const CHANNELS_WINDOW_CHANNEL_T_VALUES := [0.30, 0.48, 0.66]
const CHANNELS_WINDOW_SWARM_OFFSETS := [-1.4, -0.7, 0.0, 0.7, 1.4]
const CHANNELS_SHORTCUT_BRANCH_POS := Vector3(186.0, 0.5, 6.0)
const CHANNELS_SHORTCUT_GATE_POS := Vector3(186.0, 0.5, 10.4)
const CHANNELS_SHELTER_POS := Vector3(216.0, 0.5, 12.0)
const CHANNELS_REST_ATP := 8.0
const CHANNELS_MAX_HP := 100.0
const CHANNELS_FIELD_ACTION_EXTENSION_SECONDS := 1.25

# Channels is authored as a long first-zone lesson. These six field operations put active play
# between its six existing story/tactical beats: gather distinct evidence around the measured
# branch network, interpret it, then make one route/resource decision. Nothing below advances on
# a timer and no operation asks the player to repeat a switch. Required-character routing is
# handled by the party interaction controller, so the roles read as cooperation rather than UI tax.
const CHANNELS_FIELD_OPERATIONS := {
	"intake": {
		"step": "channels_intake_survey",
		"label": "INTAKE / FLOW ORIGIN",
		"frame_x": 8.0,
		"start": Vector3(5.0, 0.5, 0.0),
		"end": Vector3(55.0, 0.5, 0.0),
		"evidence": ["intake_aerosol", "intake_reed", "intake_grate", "intake_sluice", "intake_iron"],
		"choices": ["intake_flowing", "intake_stagnant"],
		"valid_choices": ["intake_flowing"],
		"decision_seconds": 24.0,
		"next": "to_memory",
		"tint": Color(0.26, 0.68, 0.76),
	},
	"memory": {
		"step": "channels_memory_reconstruction",
		"label": "MEMORY / BRIDGE TRACE",
		"frame_x": 62.0,
		"start": CHANNELS_BODY_POS,
		"end": CHANNELS_BODY_POS,
		"evidence": ["memory_posture", "memory_sleeve", "memory_hand", "memory_badge", "memory_boot"],
		"choices": ["memory_bridge", "memory_service"],
		"valid_choices": ["memory_bridge"],
		"decision_seconds": 30.0,
		"next": "corpse",
		"tint": Color(0.78, 0.58, 0.88),
	},
	"harvest": {
		"step": "channels_harvest_recovery",
		"label": "HARVEST / RECOVERY LOAD",
		"frame_x": 88.0,
		"start": CHANNELS_BODY_POS,
		"end": CHANNELS_WINDOW_ONE_STAGE_POS,
		"evidence": ["harvest_log", "harvest_water", "harvest_latch", "harvest_starch", "harvest_pack"],
		"choices": ["harvest_reserve", "harvest_guard"],
		"valid_choices": ["harvest_reserve", "harvest_guard"],
		"resolution_sites": {
			"harvest_reserve": "harvest_reserve_cache",
			"harvest_guard": "harvest_guard_station",
		},
		"decision_seconds": 28.0,
		"next": "window_one",
		"tint": Color(0.78, 0.56, 0.28),
	},
	"relay": {
		"step": "channels_relay_alignment",
		"label": "RELAY / PRESSURE ALIGNMENT",
		"frame_x": 126.0,
		"start": CHANNELS_WINDOW_ONE_GOAL_POS,
		"end": Vector3(CHANNELS_FLURE_TRIGGER_X + 1.0, 0.5, 0.0),
		"evidence": ["relay_head", "relay_scar", "relay_pin", "relay_overflow", "relay_root"],
		"choices": ["relay_pressure", "relay_recovery"],
		"valid_choices": ["relay_pressure", "relay_recovery"],
		"resolution_sites": {
			"relay_pressure": "relay_pressure_brace",
			"relay_recovery": "relay_recovery_roots",
		},
		"decision_seconds": 26.0,
		"next": "to_flure",
		"tint": Color(0.34, 0.72, 0.52),
	},
	"signal": {
		"step": "channels_signal_mapping",
		"label": "SIGNAL / RECEIVER MAP",
		"frame_x": 158.0,
		"start": CHANNELS_FLURE_POS,
		"end": CHANNELS_WINDOW_TWO_STAGE_POS,
		"evidence": ["signal_emission", "signal_shell", "signal_vine", "signal_cadence", "signal_return"],
		"choices": ["signal_tend", "signal_flush"],
		"valid_choices": ["signal_tend"],
		"decision_seconds": 30.0,
		"next": "window_two",
		"tint": Color(0.44, 0.82, 0.44),
	},
	"escape": {
		"step": "channels_escape_plan",
		"label": "ESCAPE / OCCLUSION PLAN",
		"frame_x": 188.0,
		"start": CHANNELS_WINDOW_TWO_GOAL_POS,
		"end": Vector3(CHANNELS_ENCOUNTER_TRIGGER_X + 1.0, 0.5, 3.0),
		"evidence": ["escape_lure", "escape_seam", "escape_draft", "escape_swarm", "escape_load"],
		"choices": ["escape_lure_hide", "escape_run_first"],
		"valid_choices": ["escape_lure_hide"],
		"decision_seconds": 32.0,
		"next": "to_encounter",
		"tint": Color(0.86, 0.48, 0.24),
	},
}

const CHANNELS_FIELD_SITES := {
	# Beat 1: establish the flow/spoil contrast by combining three characters' ways of reading it.
	"intake_aerosol": {"operation": "intake", "kind": "evidence", "role": "aster", "pos": Vector3(12, 0.5, -13), "dwell": 3.4, "verb": "CORRELATE MIST", "display": "AEROSOL", "finding": "Aster: airborne iron falls as this race accelerates."},
	"intake_reed": {"operation": "intake", "kind": "evidence", "role": "peris", "pos": Vector3(48, 0.5, 13), "dwell": 3.8, "verb": "READ REED MEMORY", "display": "REED", "finding": "Peris: the reeds remember a continuous current on the north edge."},
	"intake_grate": {"operation": "intake", "kind": "evidence", "role": "endo", "pos": Vector3(18, 0.5, 12), "dwell": 3.6, "verb": "TEST GRATE LOAD", "display": "LOAD", "finding": "Endo's brace finds the southern grate carrying dead weight."},
	"intake_sluice": {"operation": "intake", "kind": "evidence", "role": "aster", "pos": Vector3(50, 0.5, -12), "dwell": 3.4, "verb": "TRACE FLOW RATE", "display": "SLUICE", "finding": "The open sluice feeds the bright central race, not the pooled spur."},
	"intake_iron": {"operation": "intake", "kind": "evidence", "role": "peris", "pos": Vector3(30, 0.5, 0), "dwell": 3.8, "verb": "CHECK LIVING EDGE", "display": "EDGE", "finding": "Living growth stops exactly where the stagnant iron begins."},
	"intake_flowing": {"operation": "intake", "kind": "choice", "role": "endo", "pos": Vector3(52, 0.5, 8), "dwell": 2.2, "verb": "COMMIT FLOWING SPINE", "display": "FLOW", "finding": "The party commits to the moving-water spine."},
	"intake_stagnant": {"operation": "intake", "kind": "choice", "role": "aster", "pos": Vector3(52, 0.5, -8), "dwell": 2.2, "verb": "COMMIT POOLED SPUR", "display": "POOL", "finding": "That route contradicts every sample: the pooled spur is accumulating iron."},

	# Beat 2: Peris reconstructs the bodies she saw above. Details are intentionally concrete so
	# their later absence can register as memory loss.
	"memory_posture": {"operation": "memory", "kind": "evidence", "role": "peris", "pos": Vector3(32, 0.5, -13), "dwell": 3.8, "verb": "RECALL POSTURE", "display": "POSTURE", "finding": "One shoulder was caught under the bridge shadow."},
	"memory_sleeve": {"operation": "memory", "kind": "evidence", "role": "peris", "pos": Vector3(88, 0.5, 13), "dwell": 3.8, "verb": "RECALL SLEEVE", "display": "SLEEVE", "finding": "A blue cuff, torn twice, resolves in Peris's overlay."},
	"memory_hand": {"operation": "memory", "kind": "evidence", "role": "peris", "pos": Vector3(38, 0.5, 12), "dwell": 3.8, "verb": "RECALL HAND", "display": "HAND", "finding": "The left hand was turned palm-up beside the channel."},
	"memory_badge": {"operation": "memory", "kind": "evidence", "role": "peris", "pos": Vector3(92, 0.5, -12), "dwell": 3.8, "verb": "RECALL BADGE", "display": "BADGE", "finding": "A maintenance badge caught one bar of light from above."},
	"memory_boot": {"operation": "memory", "kind": "evidence", "role": "peris", "pos": Vector3(58, 0.5, 14), "dwell": 3.8, "verb": "RECALL FOOTING", "display": "BOOT", "finding": "One boot rested against the east drain, pointing back to the bridge."},
	"memory_bridge": {"operation": "memory", "kind": "choice", "role": "peris", "pos": Vector3(74, 0.5, -3), "dwell": 2.4, "verb": "MATCH BRIDGE SILHOUETTE", "display": "MATCH", "finding": "Every remembered detail converges on the figure in this channel."},
	"memory_service": {"operation": "memory", "kind": "choice", "role": "peris", "pos": Vector3(74, 0.5, 9), "dwell": 2.4, "verb": "MATCH SERVICE SHADOW", "display": "SHADOW", "finding": "The service shadow has the wrong sleeve and footing."},

	# Beat 3: turn the harvest into a material recovery problem, then let the player decide whether
	# the lysate protects immediate health or the party's later action reserve.
	"harvest_log": {"operation": "harvest", "kind": "evidence", "role": "aster", "pos": Vector3(98, 0.5, -13), "dwell": 3.6, "verb": "FILE CASUALTY TRACE", "display": "LOG", "finding": "Aster preserves a casualty trace before the channel erases it."},
	"harvest_water": {"operation": "harvest", "kind": "evidence", "role": "peris", "pos": Vector3(22, 0.5, 13), "dwell": 3.8, "verb": "FIND CLEAN RINSE", "display": "RINSE", "finding": "Peris finds a live reed marking water clean enough to rinse the pack."},
	"harvest_latch": {"operation": "harvest", "kind": "evidence", "role": "endo", "pos": Vector3(102, 0.5, 12), "dwell": 4.0, "verb": "OPEN SERVICE LATCH", "display": "LATCH", "finding": "Endo opens a dry service pocket without crossing the iron pool."},
	"harvest_starch": {"operation": "harvest", "kind": "evidence", "role": "endo", "pos": Vector3(35, 0.5, -12), "dwell": 4.0, "verb": "ASSESS STARCH", "display": "STARCH", "finding": "Endo separates usable starch from iron-soured material."},
	"harvest_pack": {"operation": "harvest", "kind": "evidence", "role": "aster", "pos": Vector3(85, 0.5, 14), "dwell": 3.6, "verb": "MODEL PACK LOAD", "display": "PACK", "finding": "The recovered amount supports one deliberate allocation."},
	"harvest_reserve": {"operation": "harvest", "kind": "choice", "role": "aster", "pos": Vector3(101, 0.5, -5), "dwell": 2.6, "verb": "BANK ACTION RESERVE", "display": "RESERVE", "finding": "The party banks the lysate as action reserve for the sluices ahead."},
	"harvest_guard": {"operation": "harvest", "kind": "choice", "role": "peris", "pos": Vector3(101, 0.5, 7), "dwell": 2.6, "verb": "STABILIZE EXPOSURE", "display": "GUARD", "finding": "Peris uses the lysate now, stabilizing the party against iron exposure."},
	"harvest_reserve_cache": {"operation": "harvest", "kind": "resolution", "role": "aster", "pos": Vector3(42, 0.5, -14), "dwell": 5.0, "verb": "SEAL DRY RESERVE", "display": "CACHE", "finding": "The dry service pocket seals the action reserve away from the iron race."},
	"harvest_guard_station": {"operation": "harvest", "kind": "resolution", "role": "peris", "pos": Vector3(44, 0.5, 13), "dwell": 5.0, "verb": "COMPLETE STABILIZATION", "display": "STABILIZE", "finding": "Clean rinse and measured lysate complete the exposure treatment."},

	# Between the first wash and the ferrolure: diagnose a relay as a system, not five switches.
	"relay_head": {"operation": "relay", "kind": "evidence", "role": "aster", "pos": Vector3(68, 0.5, -13), "dwell": 3.5, "verb": "COMPARE HEAD LOSS", "display": "HEAD", "finding": "Pressure loss begins upstream of the first corpse curtain."},
	"relay_scar": {"operation": "relay", "kind": "evidence", "role": "peris", "pos": Vector3(144, 0.5, 13), "dwell": 3.8, "verb": "READ WASH SCAR", "display": "SCAR", "finding": "Plant scars show the last surge climbed the northern bank."},
	"relay_pin": {"operation": "relay", "kind": "evidence", "role": "endo", "pos": Vector3(82, 0.5, 12), "dwell": 4.0, "verb": "TEST BRACE PIN", "display": "PIN", "finding": "The brace pin can hold one more pressure cycle, not two."},
	"relay_overflow": {"operation": "relay", "kind": "evidence", "role": "aster", "pos": Vector3(148, 0.5, -12), "dwell": 3.5, "verb": "TRACE OVERFLOW", "display": "OVERFLOW", "finding": "The overflow race trades a safer crossing for a weaker next window."},
	"relay_root": {"operation": "relay", "kind": "evidence", "role": "peris", "pos": Vector3(108, 0.5, 0), "dwell": 3.8, "verb": "CHECK ROOT TENSION", "display": "ROOT", "finding": "The roots can absorb one surge if the party needs recovery instead."},
	"relay_pressure": {"operation": "relay", "kind": "choice", "role": "endo", "pos": Vector3(144, 0.5, -6), "dwell": 2.6, "verb": "TUNE NEXT WINDOW", "display": "PRESSURE", "finding": "Endo keeps pressure in the relay, extending the next crossing window."},
	"relay_recovery": {"operation": "relay", "kind": "choice", "role": "peris", "pos": Vector3(144, 0.5, 6), "dwell": 2.6, "verb": "FEED ROOT BUFFER", "display": "RECOVER", "finding": "Peris spends the surge in the roots, restoring the party before the lure."},
	"relay_pressure_brace": {"operation": "relay", "kind": "resolution", "role": "endo", "pos": Vector3(78, 0.5, -13), "dwell": 5.0, "verb": "SET PRESSURE BRACE", "display": "BRACE", "finding": "Endo seats the upstream brace; the next timing window will hold longer."},
	"relay_recovery_roots": {"operation": "relay", "kind": "resolution", "role": "peris", "pos": Vector3(106, 0.5, 13), "dwell": 5.0, "verb": "FEED ROOT BUFFER", "display": "BUFFER", "finding": "The living root buffer takes the surge and returns it as recovery."},

	# Beat 3.5: the evidence makes Peris's practical/philosophical signal observation playable.
	"signal_emission": {"operation": "signal", "kind": "evidence", "role": "peris", "pos": Vector3(90, 0.5, -13), "dwell": 3.8, "verb": "TRACE EMISSION", "display": "EMIT", "finding": "The dormant lure is still emitting along a living root path."},
	"signal_shell": {"operation": "signal", "kind": "evidence", "role": "endo", "pos": Vector3(170, 0.5, 13), "dwell": 4.0, "verb": "READ EMPTY SHELL", "display": "SHELL", "finding": "No siderophore shell nearby carries a fresh response mark."},
	"signal_vine": {"operation": "signal", "kind": "evidence", "role": "peris", "pos": Vector3(104, 0.5, 12), "dwell": 3.8, "verb": "FOLLOW RECEIVER VINE", "display": "VINE", "finding": "The receiver vine ends in an empty service bay."},
	"signal_cadence": {"operation": "signal", "kind": "evidence", "role": "aster", "pos": Vector3(174, 0.5, -12), "dwell": 3.5, "verb": "MODEL SIGNAL CADENCE", "display": "CADENCE", "finding": "The cadence is steady: attention will not trigger a hidden swarm."},
	"signal_return": {"operation": "signal", "kind": "evidence", "role": "aster", "pos": Vector3(132, 0.5, 0), "dwell": 3.5, "verb": "CHECK RETURN PATH", "display": "RETURN", "finding": "No reflected signal returns from either channel curtain."},
	"signal_tend": {"operation": "signal", "kind": "choice", "role": "peris", "pos": Vector3(166, 0.5, 8), "dwell": 2.6, "verb": "TEND DORMANT LURE", "display": "TEND", "finding": "Nothing is receiving the signal. Peris can answer it safely."},
	"signal_flush": {"operation": "signal", "kind": "choice", "role": "aster", "pos": Vector3(166, 0.5, -6), "dwell": 2.6, "verb": "FORCE BLIND FLUSH", "display": "FLUSH", "finding": "A blind flush would destroy the evidence without making the lure safer."},

	# Beat 3.75: planning is spatial. Endo verifies lure, occlusion, stamina, swarm width, and
	# shelter draft before the player commits the authored lure -> hide -> run sequence.
	"escape_lure": {"operation": "escape", "kind": "evidence", "role": "endo", "pos": Vector3(72, 0.5, -13), "dwell": 4.0, "verb": "MEASURE LURE BURN", "display": "BURN", "finding": "The burn lasts long enough to reach the notch, not the shelter."},
	"escape_seam": {"operation": "escape", "kind": "evidence", "role": "endo", "pos": Vector3(192, 0.5, 13), "dwell": 4.0, "verb": "TEST OCCLUSION SEAM", "display": "HIDE", "finding": "The panel seam breaks line of sight across the whole notch."},
	"escape_draft": {"operation": "escape", "kind": "evidence", "role": "peris", "pos": Vector3(94, 0.5, 12), "dwell": 3.8, "verb": "FOLLOW SHELTER DRAFT", "display": "DRAFT", "finding": "The warm draft confirms the shelter door beyond the swarm."},
	"escape_swarm": {"operation": "escape", "kind": "evidence", "role": "aster", "pos": Vector3(196, 0.5, -12), "dwell": 3.5, "verb": "MAP SWARM WIDTH", "display": "SWARM", "finding": "The seven bodies overlap across the main race; there is no sneak line."},
	"escape_load": {"operation": "escape", "kind": "evidence", "role": "endo", "pos": Vector3(142, 0.5, -1), "dwell": 4.0, "verb": "PACE RETREAT LOAD", "display": "PACE", "finding": "Walking the first retreat leg preserves enough stamina for the final run."},
	"escape_lure_hide": {"operation": "escape", "kind": "choice", "role": "endo", "pos": Vector3(190, 0.5, 8), "dwell": 2.8, "verb": "COMMIT LURE / HIDE / RUN", "display": "PLAN", "finding": "Endo commits the three-stage route: lure, occlusion, shelter."},
	"escape_run_first": {"operation": "escape", "kind": "choice", "role": "aster", "pos": Vector3(190, 0.5, -8), "dwell": 2.8, "verb": "COMMIT DIRECT RUN", "display": "DIRECT", "finding": "The mapped detection fields overlap the direct run before the notch."},
}

const CHANNELS_OPTIONAL_SITES := {
	"optional_worker_names": {"role": "peris", "pos": Vector3(76, 0.5, -1), "dwell": 3.0, "verb": "REMEMBER NAMES", "display": "NAMES", "finding": "Peris preserves two names the casualty report could not recover."},
	"optional_sluice_manual": {"role": "aster", "pos": Vector3(118, 0.5, -14), "dwell": 3.0, "verb": "READ SLUICE MANUAL", "display": "MANUAL", "finding": "A maintenance note explains why the pressure relay was abandoned."},
	"optional_endo_marks": {"role": "endo", "pos": Vector3(188, 0.5, 13), "dwell": 3.0, "verb": "FOLLOW ENDO'S MARKS", "display": "MARKS", "finding": "Old hand marks connect this shelter to Endo's junction route."},
	"optional_seed_cache": {"role": "peris", "pos": Vector3(154, 0.5, 10), "dwell": 3.0, "verb": "RECOVER SEED CACHE", "display": "SEEDS", "finding": "A dry seed cache survives beside the ferrolure's roots."},
	"optional_report_stub": {"role": "aster", "pos": Vector3(48, 0.5, 13), "dwell": 3.0, "verb": "RECOVER REPORT STUB", "display": "STUB", "finding": "The final report stub logged flow failures, never the workers beside them."},
	"optional_shelter_bowl": {"role": "endo", "pos": Vector3(214, 0.5, 13), "dwell": 3.0, "verb": "CHECK SHARED BOWL", "display": "BOWL", "finding": "The bowl has been cleaned and left ready for whoever reaches the wall next."},
}
const STACKS_START := Vector3(240, 0, 0)
const STACKS_END := Vector3(460, 0, 0)
const RINGS_START := Vector3(480, 0, 0)
const RINGS_END := Vector3(680, 0, 0)
const LOCKOUT_START := Vector3(700, 0, 0)
const LOCKOUT_BOUNDARY := Vector3(780, 0, 0)

const DISTRICT_FIELD_ROUTE_SPEED := 2.5
const STACKS_LEGACY_START_POS := Vector3(245.0, 0.5, 0.0)
const STACKS_TERMINAL_POS := Vector3(328.0, 1.0, 0.0)
const STACKS_SIGNAL_POS := Vector3(336.0, 1.0, -16.9)
const STACKS_WORKSPACE_POS := Vector3(405.0, 1.0, -10.0)
const STACKS_BANK_POSITIONS := {
	"bank_a": Vector3(358.0, 0.5, -9.5),
	"bank_b": Vector3(378.0, 0.5, 9.0),
	"bank_c": Vector3(394.0, 0.5, -7.5),
}
const RINGS_LEGACY_START_POS := Vector3(486.5, 0.5, 2.0)
const RINGS_CLIENT_POS := Vector3(560.0, 0.5, -5.0)
const RINGS_TRACE_POSITIONS := {
	"client_bloom": Vector3(556.0, 0.5, -8.0),
	"forget_me_not": Vector3(596.0, 0.5, 13.8),
	"doorvine": Vector3(636.0, 0.5, 8.5),
}

# Both districts end with two compact field operations. They reuse the established corridor instead
# of inflating its footprint: distinct specialist reads make the existing architecture playable,
# then two valid plans expose persistent resource/information outcomes and a separate execution site.
const STACKS_FIELD_OPERATIONS := {
	"identity": {
		"step": "stacks_identity_reconstruction",
		"label": "IDENTITY RECONSTRUCTION",
		"frame_x": 418.0,
		"start": STACKS_WORKSPACE_POS,
		"end": Vector3(436.0, 0.5, 0.0),
		"tint": Color(0.42, 0.78, 0.92),
		"evidence": ["identity_header", "identity_patch", "identity_brace", "identity_shift", "identity_terminal", "identity_seam"],
		"choices": ["identity_people", "identity_route"],
		"resolution_sites": {
			"identity_people": "identity_people_execution",
			"identity_route": "identity_route_execution",
		},
		"next": "egress",
	},
	"egress": {
		"step": "stacks_egress_commit",
		"label": "SUPPORT EGRESS COMMIT",
		"frame_x": 447.0,
		"start": Vector3(436.0, 0.5, 0.0),
		"end": Vector3(458.0, 0.5, 0.0),
		"tint": Color(0.48, 0.88, 0.56),
		"evidence": ["egress_load", "egress_cadence", "egress_growth", "egress_latch", "egress_checksum", "egress_sightline"],
		"choices": ["egress_quiet", "egress_broadcast"],
		"resolution_sites": {
			"egress_quiet": "egress_quiet_execution",
			"egress_broadcast": "egress_broadcast_execution",
		},
		"next": "",
	},
}

const STACKS_FIELD_SITES := {
	"identity_header": {"operation": "identity", "kind": "evidence", "role": "aster", "pos": Vector3(408.0, 0.5, -6.0), "dwell": 5.4, "verb": "PARSE HEADER", "display": "UNSIGNED HEADER", "finding": "Aster separates a human identifier from the unsigned support route."},
	"identity_patch": {"operation": "identity", "kind": "evidence", "role": "peris", "pos": Vector3(412.0, 0.5, 5.0), "dwell": 5.4, "verb": "READ PATCH MEMORY", "display": "HAND PATCH", "finding": "Peris finds a maintenance patch written to preserve a person's context."},
	"identity_brace": {"operation": "identity", "kind": "evidence", "role": "endo", "pos": Vector3(416.0, 0.5, -5.0), "dwell": 5.4, "verb": "TEST RACK BRACE", "display": "RACK BRACE", "finding": "Endo proves this lane carried live support loads, not archival noise."},
	"identity_shift": {"operation": "identity", "kind": "evidence", "role": "aster", "pos": Vector3(420.0, 0.5, 5.0), "dwell": 5.4, "verb": "CORRELATE SHIFT", "display": "SHIFT GAP", "finding": "Aster aligns the ghost IDs with one unlogged maintenance shift."},
	"identity_terminal": {"operation": "identity", "kind": "evidence", "role": "peris", "pos": Vector3(424.0, 0.5, -4.0), "dwell": 5.4, "verb": "READ WARM TRACE", "display": "WARM TERMINAL", "finding": "The terminal remembers repeated hands at the same support station."},
	"identity_seam": {"operation": "identity", "kind": "evidence", "role": "endo", "pos": Vector3(428.0, 0.5, 4.0), "dwell": 5.4, "verb": "PACE SERVICE SEAM", "display": "SERVICE SEAM", "finding": "The seam opens toward both a personnel archive and an escape map."},
	"identity_people": {"operation": "identity", "kind": "choice", "role": "peris", "pos": Vector3(431.0, 0.5, 3.5), "dwell": 3.0, "verb": "PRESERVE PEOPLE", "display": "PEOPLE", "finding": "The party will preserve names and work context before route data."},
	"identity_route": {"operation": "identity", "kind": "choice", "role": "aster", "pos": Vector3(431.0, 0.5, -3.5), "dwell": 3.0, "verb": "PRESERVE ROUTE", "display": "ROUTE", "finding": "The party will preserve the hidden support route before annotations."},
	"identity_people_execution": {"operation": "identity", "kind": "resolution", "role": "peris", "pos": Vector3(434.0, 0.5, 6.0), "dwell": 5.2, "verb": "SEAL CONTEXT", "display": "CONTEXT", "finding": "Peris seals the worker context into the recovered archive."},
	"identity_route_execution": {"operation": "identity", "kind": "resolution", "role": "aster", "pos": Vector3(434.0, 0.5, -6.0), "dwell": 5.2, "verb": "COMMIT ROUTE MAP", "display": "ROUTE MAP", "finding": "Aster commits the unsigned support path to the party map."},
	"egress_load": {"operation": "egress", "kind": "evidence", "role": "endo", "pos": Vector3(438.0, 0.5, -6.0), "dwell": 5.4, "verb": "TEST EXIT LOAD", "display": "EXIT LOAD", "finding": "Endo finds the rack throat able to carry a quiet party crossing."},
	"egress_cadence": {"operation": "egress", "kind": "evidence", "role": "aster", "pos": Vector3(441.0, 0.5, 5.0), "dwell": 5.4, "verb": "MODEL CADENCE", "display": "CADENCE", "finding": "A broadcast pulse could expose the route while preserving its checksum."},
	"egress_growth": {"operation": "egress", "kind": "evidence", "role": "peris", "pos": Vector3(444.0, 0.5, -5.0), "dwell": 5.4, "verb": "READ STACK GROWTH", "display": "GROWTH", "finding": "Living growth marks the silent aisle as regularly used."},
	"egress_latch": {"operation": "egress", "kind": "evidence", "role": "endo", "pos": Vector3(447.0, 0.5, 5.0), "dwell": 5.4, "verb": "CHECK LATCH", "display": "LATCH", "finding": "The latch can be dogged quietly or held open for a data burst."},
	"egress_checksum": {"operation": "egress", "kind": "evidence", "role": "aster", "pos": Vector3(450.0, 0.5, -4.0), "dwell": 5.4, "verb": "VERIFY CHECKSUM", "display": "CHECKSUM", "finding": "The route checksum survives either execution if the party commits once."},
	"egress_sightline": {"operation": "egress", "kind": "evidence", "role": "peris", "pos": Vector3(452.0, 0.5, 4.0), "dwell": 5.4, "verb": "READ SIGHTLINE", "display": "SIGHTLINE", "finding": "Peris finds no watcher in the residential approach."},
	"egress_quiet": {"operation": "egress", "kind": "choice", "role": "endo", "pos": Vector3(454.0, 0.5, -3.0), "dwell": 3.0, "verb": "PLAN QUIET EGRESS", "display": "QUIET", "finding": "Endo will spend stamina bracing a silent exit."},
	"egress_broadcast": {"operation": "egress", "kind": "choice", "role": "aster", "pos": Vector3(454.0, 0.5, 3.0), "dwell": 3.0, "verb": "PLAN MAP BURST", "display": "MAP BURST", "finding": "Aster will spend ATP broadcasting the recovered route checksum."},
	"egress_quiet_execution": {"operation": "egress", "kind": "resolution", "role": "endo", "pos": Vector3(456.0, 0.5, -6.0), "dwell": 5.2, "verb": "BRACE EXIT", "display": "BRACE", "finding": "Endo braces the service throat and releases a silent exit."},
	"egress_broadcast_execution": {"operation": "egress", "kind": "resolution", "role": "aster", "pos": Vector3(456.0, 0.5, 6.0), "dwell": 5.2, "verb": "SEND MAP BURST", "display": "BROADCAST", "finding": "Aster sends one authenticated route burst toward the Rings."},
}

const RINGS_FIELD_OPERATIONS := {
	"residence": {
		"step": "rings_residence_survey",
		"label": "OCCUPIED RESIDENCE SURVEY",
		"frame_x": 648.0,
		"start": RINGS_TRACE_POSITIONS["doorvine"],
		"end": Vector3(663.0, 0.5, 0.0),
		"tint": Color(0.92, 0.67, 0.36),
		"evidence": ["residence_heat", "residence_memory", "residence_seal", "residence_tending", "residence_pulse", "residence_garden"],
		"choices": ["residence_knock", "residence_marker"],
		"resolution_sites": {
			"residence_knock": "residence_knock_execution",
			"residence_marker": "residence_marker_execution",
		},
		"next": "boundary",
	},
	"boundary": {
		"step": "rings_boundary_commit",
		"label": "NEIGHBORHOOD HANDOFF",
		"frame_x": 671.0,
		"start": Vector3(663.0, 0.5, 0.0),
		"end": Vector3(679.0, 0.5, 0.0),
		"tint": Color(0.62, 0.78, 0.96),
		"evidence": ["boundary_watch", "boundary_names", "boundary_signal", "boundary_roots", "boundary_map", "boundary_quiet"],
		"choices": ["boundary_keep_watch", "boundary_share_map"],
		"resolution_sites": {
			"boundary_keep_watch": "boundary_watch_execution",
			"boundary_share_map": "boundary_map_execution",
		},
		"next": "",
	},
}

const RINGS_FIELD_SITES := {
	"residence_heat": {"operation": "residence", "kind": "evidence", "role": "aster", "pos": Vector3(640.0, 0.5, 6.0), "dwell": 5.4, "verb": "MAP HEAT", "display": "HEAT", "finding": "Aster confirms a stable occupied heat signature behind the seal."},
	"residence_memory": {"operation": "residence", "kind": "evidence", "role": "peris", "pos": Vector3(643.0, 0.5, -5.0), "dwell": 5.4, "verb": "READ CLIENT MEMORY", "display": "MEMORY", "finding": "Peris recognizes a care routine continuing after the client left."},
	"residence_seal": {"operation": "residence", "kind": "evidence", "role": "aster", "pos": Vector3(646.0, 0.5, 5.0), "dwell": 5.4, "verb": "TRACE SEAL LOG", "display": "SEAL LOG", "finding": "The seal log shows voluntary privacy, not emergency quarantine."},
	"residence_tending": {"operation": "residence", "kind": "evidence", "role": "peris", "pos": Vector3(649.0, 0.5, -5.0), "dwell": 5.4, "verb": "READ TENDING MARKS", "display": "TENDING", "finding": "Fresh tending marks prove someone still services the doorvine."},
	"residence_pulse": {"operation": "residence", "kind": "evidence", "role": "aster", "pos": Vector3(652.0, 0.5, 4.0), "dwell": 5.4, "verb": "CORRELATE PULSE", "display": "WINDOW PULSE", "finding": "One window pulse answers the district clock without opening the home."},
	"residence_garden": {"operation": "residence", "kind": "evidence", "role": "peris", "pos": Vector3(655.0, 0.5, -4.0), "dwell": 5.4, "verb": "READ GARDEN MEMORY", "display": "GARDEN", "finding": "The garden remembers a resident choosing quiet contact."},
	"residence_knock": {"operation": "residence", "kind": "choice", "role": "peris", "pos": Vector3(658.0, 0.5, 3.0), "dwell": 3.0, "verb": "PLAN GENTLE KNOCK", "display": "KNOCK", "finding": "Peris chooses one gentle contact and accepts the social risk."},
	"residence_marker": {"operation": "residence", "kind": "choice", "role": "aster", "pos": Vector3(658.0, 0.5, -3.0), "dwell": 3.0, "verb": "PLAN QUIET MARKER", "display": "MARKER", "finding": "Aster chooses a silent care marker that preserves privacy."},
	"residence_knock_execution": {"operation": "residence", "kind": "resolution", "role": "peris", "pos": Vector3(661.0, 0.5, 6.0), "dwell": 5.2, "verb": "MAKE CONTACT", "display": "CONTACT", "finding": "A quiet answer confirms the household is safe and wishes to remain private."},
	"residence_marker_execution": {"operation": "residence", "kind": "resolution", "role": "aster", "pos": Vector3(661.0, 0.5, -6.0), "dwell": 5.2, "verb": "SET CARE MARKER", "display": "CARE MARK", "finding": "Aster leaves a nonintrusive marker for the next support pass."},
	"boundary_watch": {"operation": "boundary", "kind": "evidence", "role": "peris", "pos": Vector3(665.0, 0.5, -6.0), "dwell": 5.4, "verb": "READ WATCH POST", "display": "WATCH", "finding": "Peris finds a resident watch line that covers the empty avenue."},
	"boundary_names": {"operation": "boundary", "kind": "evidence", "role": "aster", "pos": Vector3(667.0, 0.5, 5.0), "dwell": 5.4, "verb": "INDEX HOUSE NAMES", "display": "NAMES", "finding": "Aster recovers house names omitted from the public district map."},
	"boundary_signal": {"operation": "boundary", "kind": "evidence", "role": "peris", "pos": Vector3(669.0, 0.5, -5.0), "dwell": 5.4, "verb": "READ SIGNAL GARDEN", "display": "SIGNAL", "finding": "The garden signal offers help without exposing occupied doors."},
	"boundary_roots": {"operation": "boundary", "kind": "evidence", "role": "aster", "pos": Vector3(671.0, 0.5, 5.0), "dwell": 5.4, "verb": "TRACE ROOT MAP", "display": "ROOT MAP", "finding": "The roots carry a safe boundary route toward Lockout."},
	"boundary_map": {"operation": "boundary", "kind": "evidence", "role": "aster", "pos": Vector3(673.0, 0.5, -4.0), "dwell": 5.4, "verb": "COMPARE PUBLIC MAP", "display": "PUBLIC MAP", "finding": "The public map could accept one privacy-preserving update."},
	"boundary_quiet": {"operation": "boundary", "kind": "evidence", "role": "peris", "pos": Vector3(675.0, 0.5, 4.0), "dwell": 5.4, "verb": "READ QUIET ROUTE", "display": "QUIET ROUTE", "finding": "Peris can instead carry the route personally and keep every name local."},
	"boundary_keep_watch": {"operation": "boundary", "kind": "choice", "role": "peris", "pos": Vector3(677.0, 0.5, 2.8), "dwell": 3.0, "verb": "KEEP LOCAL WATCH", "display": "LOCAL", "finding": "Peris keeps the neighborhood map local and accepts the watch burden."},
	"boundary_share_map": {"operation": "boundary", "kind": "choice", "role": "aster", "pos": Vector3(677.0, 0.5, -2.8), "dwell": 3.0, "verb": "SHARE SAFE MAP", "display": "SHARE", "finding": "Aster shares only route geometry, withholding resident identities."},
	"boundary_watch_execution": {"operation": "boundary", "kind": "resolution", "role": "peris", "pos": Vector3(678.5, 0.5, 6.0), "dwell": 5.2, "verb": "TAKE WATCH", "display": "WATCH", "finding": "Peris carries the quiet route forward without publishing the homes."},
	"boundary_map_execution": {"operation": "boundary", "kind": "resolution", "role": "aster", "pos": Vector3(678.5, 0.5, -6.0), "dwell": 5.2, "verb": "PUBLISH SAFE LINE", "display": "SAFE LINE", "finding": "Aster publishes a safe line stripped of every household identifier."},
}

# --- Per-chunk grids ---
# act1 CUTS between chunks (each loads as the previous unloads), so only one chunk is live at a time.
# Each gets its own OPEN GridWorld over its corridor footprint (a generous bounding rect from its
# START..END span); the active grid swaps in when its chunk loads. Movement is then cell-based +
# cooperative per chunk, without a single impractical world-spanning grid.
const CHUNK_GRIDS := {
	"channels": {"origin": Vector3(-6, 0, -16), "size": Vector2i(242, 32)},   # X[-6,236]
	"stacks": {"origin": Vector3(234, 0, -16), "size": Vector2i(232, 32)},    # X[234,466]
	"rings": {"origin": Vector3(474, 0, -16), "size": Vector2i(212, 32)},     # X[474,686]
	"lockout": {"origin": Vector3(694, 0, -16), "size": Vector2i(92, 32)},    # X[694,786]
	# The Endo scene chunk authors its own long-form corridor and all specialist field stations.
	# Keep the cooperative grid aligned to the complete 284x44 authored footprint.
	"endo_junction_stretch": {"origin": Vector3(-2, 0, -22), "size": Vector2i(284, 44)},
}
var _grid: GridWorld
var _endo_junction_chunk: Node3D
## True while the Endo stretch leg is running. The chunk overwrites _current_step with its own per-beat
## step ids (via set_preview_step), so the completion poll keys off this flag, not _current_step.
var _endo_junction_active := false
var _lockout_chase_chunk: Node3D
var _lockout_chase_active := false
var _lockout_rejection_presented := false
var _lockout_dispatch_presented := false

## Build + activate the named chunk's OPEN grid, swapping it in as the live grid. The party re-derives
## its cells on the new grid (derived state); only one chunk grid is live at a time (act1 cuts between).
func _activate_chunk_grid(chunk_name: String) -> void:
	var spec = CHUNK_GRIDS.get(chunk_name)
	if spec == null or _game_state == null:
		return
	var size: Vector2i = spec["size"]
	_grid = GridWorld.new()
	_grid.origin = spec["origin"]
	_grid.create_room(size.x, size.y, false)
	_game_state.grid = _grid
	for node in [_aster_node, _peris_node, _endo]:
		if node != null and "grid_world" in node:
			node.grid_world = _grid
	for id in _game_state.characters.keys():
		_game_state.characters[id]["grid_cell"] = _grid.world_to_grid(_game_state.get_position(id))

## Scene chunks can author carved cells and dynamic obstacles rather than Act 1's open rectangles.
## Adopt that exact grid so the campaign version routes identically to the fragment preview/tests.
func _activate_hosted_chunk_grid(chunk: Node) -> void:
	if chunk == null or _game_state == null or not chunk.has_method("get_grid_data"):
		return
	var grid_data: Variant = chunk.call("get_grid_data")
	if not (grid_data is Dictionary) or (grid_data as Dictionary).is_empty():
		return
	_grid = GridWorld.from_data(grid_data as Dictionary)
	_game_state.grid = _grid
	for node in [_aster_node, _peris_node, _endo]:
		if node != null and "grid_world" in node:
			node.grid_world = _grid
	for id in _game_state.characters.keys():
		_game_state.characters[id]["grid_cell"] = _grid.world_to_grid(_game_state.get_position(id))

# --- Chunk dispatch ---

## Channels/Stacks/Rings/Lockout are PROCEDURAL (built by _build_chunk → null scene). The Endo
## stretch is a self-contained SCENE chunk: returning its PackedScene makes the base _load_chunk
## instantiate it and call attach_chunk_host(self, ...), wiring it to act1's GameState/scheduler/UI.
func _get_chunk_scene(chunk_name: String) -> PackedScene:
	if chunk_name == "endo_junction_stretch":
		return ENDO_JUNCTION_STRETCH_CHUNK_SCENE
	if chunk_name == "lockout_chase_campaign":
		return LOCKOUT_CHASE_CHUNK_SCENE
	return null

func _build_chunk(chunk_name: String, parent: Node3D) -> void:
	match chunk_name:
		"channels": _build_channels_chunk(parent)
		"stacks": _build_stacks_chunk(parent)
		"rings": _build_rings_chunk(parent)
		"lockout": _build_lockout_chunk(parent)
	LevelDecoratorScript.decorate_act1_chunk(parent, chunk_name)

# --- Virtual overrides ---

func _build_scene() -> void:
	var env := Node3D.new()
	env.name = "Environment"
	add_child(env)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.04, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.2, 0.2, 0.25)
	e.ambient_light_energy = 0.4
	e.glow_enabled = true
	e.glow_intensity = 0.2
	we.environment = e
	env.add_child(we)
	_load_chunk("channels")

func _build_characters() -> void:
	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)

	# Aster (player)
	_player = _create_player_character("Aster", Color(0.29, 0.62, 1.0))
	_player.position = CHANNELS_START + Vector3(1, 0.5, 0)
	chars.add_child(_player)
	_aster_node = _player

	# Peris
	_peris_node = _create_player_character("Peris", Color(1.0, 0.67, 0.27))
	_peris_node.position = CHANNELS_START + Vector3(0, 0.5, 1)
	chars.add_child(_peris_node)

	# Endo joins during the Channels encounter.
	_endo = _create_player_character("Endo", Color(0.4, 0.67, 0.53))
	_endo.position = CHANNELS_START + Vector3(-1, 0.5, 0)
	chars.add_child(_endo)

	if not Engine.is_editor_hint():
		_setup_game_camera(_player, Vector3(0, 10, 8), true)

func _register_characters() -> void:
	_activate_chunk_grid("channels")  # the live grid for the opening chunk
	_register_gs_character("aster", _aster_node, 3.0, {"hp": CHANNELS_MAX_HP, "atp": 6.0})
	_register_gs_character("peris", _peris_node, 2.5, {"hp": CHANNELS_MAX_HP, "atp": 6.0})
	_register_gs_character("endo", _endo, 2.5, {"hp": CHANNELS_MAX_HP, "atp": 6.0})
	_bind_channels_field_sites_to_game_state()

func _setup_ui() -> void:
	_build_overlay_ui()
	_flora_overlay_root = Node3D.new()
	_flora_overlay_root.name = "FloraOverlayRoot"
	add_child(_flora_overlay_root)
	_apply_overlay_visibility()
	_select_character("aster")

func _begin() -> void:
	_player.set_move_enabled(false)
	if start_chunk != "":
		if start_chunk == "endo_junction_stretch":
			# The scene chunk owns its own world; don't load the procedural opener around it.
			_start_endo_junction_stretch_enter()
			return
		_load_chunk(start_chunk)
		_player.set_move_enabled(true)
		match start_chunk:
			"channels":
				_player.global_position = CHANNELS_START + Vector3(5, 0.5, 0)
				_start_channels_enter()
			"stacks":
				_player.global_position = STACKS_START + Vector3(5, 0.5, 0)
				_start_stacks_enter()
			"rings":
				_player.global_position = RINGS_START + Vector3(5, 0.5, 0)
				_start_rings_enter()
			"lockout":
				_player.global_position = LOCKOUT_START + Vector3(5, 0.5, 0)
				_start_lockout_approach()
		return
	_current_step = "fade_in"
	_fade_from(Color(0.02, 0.02, 0.03, 1), OPENING_FADE_DURATION, _start_channels_enter, "channels_enter")

func _compute_speed() -> float:
	return 10.0 if Input.is_action_pressed("fast_forward") else 1.0

func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		match key_event.keycode:
			KEY_F1:
				_toggle_overlay("aster")
			KEY_F2:
				_toggle_overlay("peris")

func _on_process(delta: float, spd: float) -> void:
	if _current_step == "fade_in":
		_update_fade_in(OPENING_FADE_DURATION)

	var channels_script_locked := _current_step in [
		"channels_window_one_intro",
		"channels_window_one_activate",
		"channels_window_one_cross",
		"channels_window_one_reset",
		"channels_window_two_intro",
		"channels_window_two_activate",
		"channels_window_two_cross",
		"channels_window_two_reset",
		"channels_encounter_intro",
		"channels_encounter_activate",
		"channels_encounter_hide",
		"channels_encounter_run",
		"channels_encounter_reset",
		"channels_intake_survey",
		"channels_memory_reconstruction",
		"channels_harvest_recovery",
		"channels_relay_alignment",
		"channels_signal_mapping",
		"channels_escape_plan",
		"channels_memory",
		"channels_corpse",
		"channels_flure",
		"channels_shelter",
	]

	# Iron patch damage
	for pair in [["aster", _aster_node], ["peris", _peris_node]]:
		var cid: String = pair[0]
		var cnode: Node3D = pair[1]
		if not cnode:
			continue
		var hp: float = _aster_hp if cid == "aster" else _peris_hp
		if hp <= 0:
			continue
		var cpos := cnode.global_position
		for patch in _iron_patches:
			var ppos: Vector3 = patch.pos
			var psz: Vector3 = patch.size
			if absf(cpos.x - ppos.x) < psz.x / 2.0 and absf(cpos.z - ppos.z) < psz.z / 2.0:
				var dmg := IRON_DAMAGE_PER_SEC * delta * spd
				if cid == "aster":
					_aster_hp = maxf(0.0, _aster_hp - dmg)
				else:
					_peris_hp = maxf(0.0, _peris_hp - dmg)
				break

	_update_channels_encounter(delta, spd)
	_update_channels_flure_flush(delta, spd)
	_update_channels_window_puzzles(delta, spd)
	_update_overlay_note(delta)
	_update_flora_system()

	# Followers trail the leader outside cutscenes.
	if not channels_script_locked:
		var leader := _get_character_node(_active_character)
		for pair in [
			["aster", _aster_node, Vector3(-1.2, 0, 0.8)],
			["peris", _peris_node, Vector3(-1.2, 0, 1.2)],
			["endo", _endo, Vector3(-1.2, 0, -0.8)],
		]:
			var cid: String = pair[0]
			var cnode: CharacterBody3D = pair[1]
			var offset: Vector3 = pair[2]
			if cid == _active_character or cnode == null or not cnode.visible or not _game_state.characters.has(cid):
				continue
			var dist := cnode.global_position.distance_to(leader.global_position)
			if dist > 3.0 and not _game_state.is_moving(cid):
				_game_state.command_move_to_pos(cid, leader.global_position + offset)

	# Position gates
	if _current_step == "channels_to_memory":
		if _game_state.get_position("aster").x > CHANNELS_MEMORY_TRIGGER_X:
			_start_channels_memory()

	if _current_step == "channels_to_flure":
		if _game_state.get_position("aster").x > CHANNELS_FLURE_TRIGGER_X:
			_start_channels_flure()

	if _current_step == "channels_to_encounter":
		if _game_state.get_position("aster").x > CHANNELS_ENCOUNTER_TRIGGER_X:
			_start_channels_encounter_intro()

	if _current_step == "channels_explore":
		if _game_state.get_position("aster").x > CHANNELS_END.x - 5.0:
			_start_stacks_enter()

	# Endo stretch (its own leg): the chunk overwrites _current_step with per-beat ids, so poll on the
	# leg flag and the chunk's route_phase (set to "complete" by reach_shelter), not _current_step.
	if _endo_junction_active:
		if _endo_junction_chunk != null and is_instance_valid(_endo_junction_chunk) and _endo_junction_chunk.has_method("get_preview_state"):
			var stretch_state: Dictionary = _endo_junction_chunk.call("get_preview_state")
			if str(stretch_state.get("route_phase", "")) == "complete":
				_start_endo_junction_stretch_complete()

	# The authored chase owns its hazards, checkpoints, and wall rest. Act 1 only watches the
	# completion contract, then resumes the existing aftermath/handoff.
	if _lockout_chase_active:
		if _lockout_chase_chunk != null and is_instance_valid(_lockout_chase_chunk) \
				and _lockout_chase_chunk.has_method("get_preview_state"):
			var chase_state: Dictionary = _lockout_chase_chunk.call("get_preview_state")
			if bool(chase_state.get("complete", false)):
				_start_lockout_exile()

	if _current_step == "stacks_explore":
		if _game_state.get_position("aster").x > STACKS_END.x - 5.0:
			_start_rings_enter()

	if _current_step == "rings_explore":
		if _game_state.get_position("aster").x > RINGS_END.x - 5.0:
			_start_lockout_approach()

	# Lockout chase: Naturalizers walk toward party, stop at boundary
	if _current_step == "lockout_chase" and not _lockout_chase_active:
		for nk in _naturalizers:
			if is_instance_valid(nk):
				var nk_pos := nk.global_position
				var aster_pos := _aster_node.global_position
				# Stop at the unserviced boundary.
				if aster_pos.x < LOCKOUT_START.x - 10.0:
					_start_lockout_exile()
					break

# --- Step functions ---

func _get_character_node(id: String) -> CharacterBody3D:
	match id:
		"aster":
			return _aster_node
		"peris":
			return _peris_node
		"endo":
			return _endo
		_:
			return null

func _set_interactable_active_character(id: String) -> void:
	for node in find_children("*", "", true, false):
		if node.has_signal("interacted") and node.has_method("get_dwell_progress"):
			node.set("active_character", id)

func _select_character(id: String) -> void:
	var next := _get_character_node(id)
	if next == null:
		return
	for cid in ["aster", "peris", "endo"]:
		var node := _get_character_node(cid)
		if node:
			node.set_move_enabled(cid == id)
	_player = next
	_active_character = id
	_set_interactable_active_character(id)
	match id:
		"aster":
			_focus_aster_view()
		"peris":
			_focus_peris_view()
		"endo":
			_focus_endo_view()

func _focus_aster_view() -> void:
	if _camera:
		_camera.target = _aster_node
	_apply_overlay_visibility()

func _focus_peris_view() -> void:
	if _camera:
		_camera.target = _peris_node
	_apply_overlay_visibility()

func _focus_endo_view() -> void:
	if _camera:
		_camera.target = _endo
	_apply_overlay_visibility()

func _build_overlay_ui() -> void:
	_overlay_ui = preload("res://scenes/ui/perception_overlay.tscn").instantiate()
	_overlay_ui.name = "Act1OverlayUI"
	add_child(_overlay_ui)
	_overlay_note_label = _overlay_ui.get_node("Margin/Panel/Content/NoteLabel") as Label
	_overlay_status_label = _overlay_ui.get_node("Margin/Panel/Content/StatusLabel") as Label
	_bind_overlay_button(
		_overlay_ui.get_node("Margin/Panel/Content/Buttons/AsterOverlayButton") as Button,
		"aster", Color(0.29, 0.62, 1.0))
	_bind_overlay_button(
		_overlay_ui.get_node("Margin/Panel/Content/Buttons/PerisOverlayButton") as Button,
		"peris", Color(1.0, 0.67, 0.27))
	_update_overlay_status({})

func _bind_overlay_button(button: Button, overlay_id: String, color: Color) -> void:
	button.pressed.connect(_toggle_overlay.bind(overlay_id))
	_overlay_buttons[overlay_id] = {
		"button": button,
		"color": color,
	}
	_refresh_overlay_button(overlay_id)

func _toggle_overlay(overlay_id: String) -> void:
	if not _overlay_states.has(overlay_id):
		return
	_overlay_states[overlay_id] = not bool(_overlay_states[overlay_id])
	_refresh_overlay_button(overlay_id)
	_apply_overlay_visibility()
	_show_overlay_note("%s overlay %s" % [overlay_id.capitalize(), "ON" if bool(_overlay_states[overlay_id]) else "OFF"])

func _refresh_overlay_button(overlay_id: String) -> void:
	if not _overlay_buttons.has(overlay_id):
		return
	var info: Dictionary = _overlay_buttons[overlay_id]
	var button: Button = info.get("button")
	var color: Color = info.get("color", Color.WHITE)
	var enabled := bool(_overlay_states.get(overlay_id, false))
	var normal: StyleBoxFlat = button.get_theme_stylebox("normal")
	var hover: StyleBoxFlat = button.get_theme_stylebox("hover")
	var pressed: StyleBoxFlat = button.get_theme_stylebox("pressed")
	if enabled:
		normal.bg_color = Color(color, 0.18)
		normal.border_color = Color(color, 0.7)
		hover.bg_color = Color(color, 0.24)
		hover.border_color = Color(color, 0.85)
		pressed.bg_color = Color(color, 0.32)
		pressed.border_color = Color(color, 0.95)
		button.add_theme_color_override("font_color", Color(color, 0.95))
	else:
		normal.bg_color = Color(0.06, 0.06, 0.08, 0.9)
		normal.border_color = Color(color, 0.28)
		hover.bg_color = Color(0.08, 0.08, 0.1, 0.95)
		hover.border_color = Color(color, 0.45)
		pressed.bg_color = Color(0.11, 0.11, 0.13, 0.95)
		pressed.border_color = Color(color, 0.55)
		button.add_theme_color_override("font_color", Color(color, 0.6))

func _show_overlay_note(text: String, duration := 2.2) -> void:
	if _overlay_note_label == null:
		return
	_overlay_note_label.text = text
	_overlay_note_label.modulate.a = 0.95
	_overlay_note_timer = duration

func _update_overlay_note(delta: float) -> void:
	if _overlay_note_timer <= 0.0 or _overlay_note_label == null:
		return
	_overlay_note_timer = maxf(0.0, _overlay_note_timer - delta)
	if _overlay_note_timer <= 0.0:
		_overlay_note_label.modulate.a = 0.0

func _apply_overlay_visibility() -> void:
	if bool(_overlay_states.get("aster", false)):
		_setup_perception("data", _aster_node)
	else:
		if _perception_quad:
			_perception_quad.visible = false

func _update_overlay_status(snapshot: Dictionary) -> void:
	if _overlay_status_label == null:
		return
	var lines: Array[String] = [
		"Aster data: %s" % ("ON" if bool(_overlay_states.get("aster", false)) else "OFF"),
		"Peris flora: %s" % ("ON" if bool(_overlay_states.get("peris", false)) else "OFF"),
	]
	if bool(_overlay_states.get("peris", false)):
		if snapshot.is_empty():
			lines.append("")
			lines.append("Peris flora network is idle.")
		else:
			var relational: Dictionary = snapshot.get("relational", {})
			var words: Dictionary = snapshot.get("layer_words", {})
			lines.append("")
			lines.append("Network: %s" % ("bright" if bool(snapshot.get("window_active", false)) else "dormant"))
			if bool(snapshot.get("window_active", false)):
				lines.append("Read window: %.0fs" % float(snapshot.get("time_remaining", 0.0)))
			lines.append("Species: %s" % str(words.get("species", "clear")))
			lines.append("Health: %s" % str(words.get("health", "steady")))
			lines.append("Context: %s" % str(words.get("context", "readable")))
			lines.append("Direction: %s" % str(words.get("direction", "precise")))
			lines.append("Memory: %s" % str(words.get("memory", "anchored")))
			var scent := str(relational.get("scent", "none"))
			if scent == "none":
				lines.append("Forget-me-nots: scentless")
			elif scent == "flicker":
				lines.append("Forget-me-nots: flicker")
			else:
				lines.append("Forget-me-nots: %s" % scent)
	else:
		lines.append("")
		lines.append("Peris overlay hidden.")
	_overlay_status_label.text = "\n".join(lines)

func _update_flora_system() -> void:
	var current_tick := _scheduler.get_current_tick()
	var zone := _current_flora_zone()
	_flora_system.set_stage(_current_flora_stage())

	if zone != "":
		for node_id in _flora_nodes.keys():
			var info: Dictionary = _flora_nodes[node_id]
			if str(info.get("zone", "")) != zone:
				continue
			var pos: Vector3 = info.get("position", Vector3.ZERO)
			if _peris_node and _peris_node.visible and _peris_node.global_position.distance_to(pos) <= FLORA_SMELL_RADIUS:
				if _flora_system.can_activate_node(node_id, current_tick):
					var read := _flora_system.start_read(node_id, current_tick)
					if bool(read.get("started", false)):
						_show_overlay_note(str(read.get("message", "")))

	var snapshot := _flora_system.get_overlay_snapshot(current_tick, zone)
	_update_overlay_status(snapshot)
	_update_flora_markers(snapshot)

func _update_flora_markers(snapshot: Dictionary) -> void:
	for marker_id in _flora_marker_nodes.keys():
		var marker: Label3D = _flora_marker_nodes[marker_id]
		if marker:
			marker.visible = false

	if not bool(_overlay_states.get("peris", false)):
		return

	var clues: Array = snapshot.get("visible_clues", [])
	for clue_data in clues:
		var clue: Dictionary = clue_data
		var marker := _get_flora_marker(str(clue.get("id", "")))
		var signal_type := str(clue.get("signal_type", "memory"))
		var certainty := float(clue.get("certainty", 0.6))
		marker.position = clue.get("display_pos", Vector3.ZERO) + Vector3(0.0, 2.2, 0.0)
		marker.text = str(clue.get("signal_label", "")).to_upper()
		marker.modulate = Color(_flora_signal_color(signal_type), 0.2 + certainty * 0.75)
		marker.visible = true

func _get_flora_marker(id: String) -> Label3D:
	if _flora_marker_nodes.has(id):
		return _flora_marker_nodes[id]
	var marker := Label3D.new()
	marker.name = "FloraMarker_%s" % id
	marker.font_size = 28
	marker.pixel_size = 0.008
	marker.outline_modulate = Color(0.0, 0.0, 0.0, 0.45)
	marker.outline_size = 8
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.visible = false
	_flora_overlay_root.add_child(marker)
	_flora_marker_nodes[id] = marker
	return marker

func _flora_signal_color(signal_type: String) -> Color:
	match signal_type:
		"threat":
			return Color(0.92, 0.46, 0.32)
		"hazard", "iron":
			return Color(0.94, 0.64, 0.28)
		"resource", "cache":
			return Color(0.56, 0.84, 0.56)
		"relationship":
			return Color(0.6, 0.76, 0.95)
		_:
			return Color(1.0, 0.77, 0.42)

func _current_flora_zone() -> String:
	if _current_step.begins_with("channels"):
		return "channels"
	if _current_step.begins_with("stacks"):
		return "stacks"
	if _current_step.begins_with("rings"):
		return "rings"
	return ""

func _current_flora_stage() -> int:
	if _current_step.begins_with("channels"):
		return FloraMemorySystem.Stage.EARLY
	if _current_step.begins_with("stacks"):
		return FloraMemorySystem.Stage.MID
	if _current_step in ["rings_enter", "rings_client"]:
		return FloraMemorySystem.Stage.LATE_MID
	if _current_step.begins_with("rings") or _current_step.begins_with("lockout"):
		return FloraMemorySystem.Stage.LATE
	return FloraMemorySystem.Stage.EARLY

func get_capture_context() -> Dictionary:
	var zone_label := _capture_zone_label()
	var sub_location := _humanize_capture_token(_current_step)
	return {
		"scene_path": scene_file_path,
		"scene_name": "Act 1",
		"act": 1,
		"day": 1,
		"time_of_day": "",
		"timestamp_label": "Act 1 / Day 1",
		"location": zone_label,
		"sub_location": sub_location,
		"trigger_type": "manual",
		"trigger_context": _current_step if _current_step != "" else "manual_capture",
		"position": _player.global_position if _player != null else Vector3.ZERO,
		"caption": "%s, Day 1" % zone_label,
	}

func build_save_snapshot() -> Dictionary:
	var snapshot := super.build_save_snapshot()
	snapshot["act1"] = {
		"active_character": _active_character,
		"overlay_states": _overlay_states.duplicate(true),
		"channels_fieldwork": {
			"phase": _channels_field_phase,
			"completed": _channels_field_completed.duplicate(true),
			"operations_completed": _channels_field_operations_completed.duplicate(true),
			"choices": _channels_field_choices.duplicate(true),
			"attempts": _channels_field_attempts.duplicate(true),
			"optional_findings": _channels_optional_findings.duplicate(true),
			"decisions": _channels_field_decisions,
			"aster_hp": _aster_hp,
			"peris_hp": _peris_hp,
		},
		"stacks_state": {
			"support_log_entry_id": _stacks_support_log_entry_id,
			"support_log_presented": _stacks_support_log_presented,
			"signal_interacted": _stacks_signal_interacted,
			"terminal_interacted": _stacks_terminal_interacted,
			"archive_interacted": _stacks_archive_interacted,
			"audit_flags_found": _stacks_audit_flags_found,
			"bank_samples": _stacks_bank_samples.keys(),
			"bank_resolved": _stacks_bank_resolved,
			"bank_attempts": _stacks_bank_attempts,
			"field_phase": _stacks_field_phase,
			"field_completed": _stacks_field_completed.duplicate(true),
			"field_operations_completed": _stacks_field_operations_completed.duplicate(true),
			"field_choices": _stacks_field_choices.duplicate(true),
			"field_effects": _stacks_field_effects.duplicate(true),
			"field_decisions": _stacks_field_decisions,
		},
		"rings_state": {
			"client_seen": _rings_client_seen,
			"trace_seen": _rings_trace_seen.duplicate(true),
			"field_phase": _rings_field_phase,
			"field_completed": _rings_field_completed.duplicate(true),
			"field_operations_completed": _rings_field_operations_completed.duplicate(true),
			"field_choices": _rings_field_choices.duplicate(true),
			"field_effects": _rings_field_effects.duplicate(true),
			"field_decisions": _rings_field_decisions,
		},
	}
	return snapshot

func apply_save_snapshot(data: Dictionary) -> void:
	super.apply_save_snapshot(data)
	var act1_data: Dictionary = data.get("act1", {})
	if act1_data.has("overlay_states"):
		_overlay_states = act1_data.get("overlay_states", {}).duplicate(true)
		for overlay_id in _overlay_buttons.keys():
			_refresh_overlay_button(overlay_id)
		_apply_overlay_visibility()
	var active_character := str(act1_data.get("active_character", _active_character))
	if active_character != "":
		_select_character(active_character)
	var channels_fieldwork: Dictionary = act1_data.get("channels_fieldwork", {})
	_channels_field_phase = str(channels_fieldwork.get("phase", _channels_field_phase))
	_channels_field_completed = channels_fieldwork.get("completed", _channels_field_completed).duplicate(true)
	_channels_field_operations_completed = channels_fieldwork.get("operations_completed", _channels_field_operations_completed).duplicate(true)
	_channels_field_choices = channels_fieldwork.get("choices", _channels_field_choices).duplicate(true)
	_channels_field_attempts = channels_fieldwork.get("attempts", _channels_field_attempts).duplicate(true)
	_channels_optional_findings = channels_fieldwork.get("optional_findings", _channels_optional_findings).duplicate(true)
	_channels_field_decisions = int(channels_fieldwork.get("decisions", _channels_field_decisions))
	_aster_hp = float(channels_fieldwork.get("aster_hp", _aster_hp))
	_peris_hp = float(channels_fieldwork.get("peris_hp", _peris_hp))
	if str(_channels_field_choices.get("relay", "")) == "relay_pressure":
		_apply_channels_field_choice("relay", "relay_pressure")
	_restore_channels_fieldwork_interactables()
	var stacks_state: Dictionary = act1_data.get("stacks_state", {})
	_stacks_support_log_entry_id = int(stacks_state.get("support_log_entry_id", _stacks_support_log_entry_id))
	_stacks_support_log_presented = bool(stacks_state.get("support_log_presented", _stacks_support_log_presented))
	_stacks_signal_interacted = bool(stacks_state.get("signal_interacted", _stacks_signal_interacted))
	_stacks_terminal_interacted = bool(stacks_state.get("terminal_interacted", _stacks_terminal_interacted))
	_stacks_archive_interacted = bool(stacks_state.get("archive_interacted", _stacks_archive_interacted))
	_stacks_audit_flags_found = bool(stacks_state.get("audit_flags_found", _stacks_audit_flags_found))
	_stacks_bank_samples.clear()
	for bank_id in stacks_state.get("bank_samples", []):
		_stacks_bank_samples[str(bank_id)] = true
	_stacks_bank_resolved = bool(stacks_state.get("bank_resolved", _stacks_bank_resolved))
	_stacks_bank_attempts = int(stacks_state.get("bank_attempts", _stacks_bank_attempts))
	_stacks_field_phase = str(stacks_state.get("field_phase", _stacks_field_phase))
	_stacks_field_completed = stacks_state.get("field_completed", _stacks_field_completed).duplicate(true)
	_stacks_field_operations_completed = stacks_state.get("field_operations_completed", _stacks_field_operations_completed).duplicate(true)
	_stacks_field_choices = stacks_state.get("field_choices", _stacks_field_choices).duplicate(true)
	_stacks_field_effects = stacks_state.get("field_effects", _stacks_field_effects).duplicate(true)
	_stacks_field_decisions = int(stacks_state.get("field_decisions", _stacks_field_decisions))
	_restore_district_fieldwork_interactables("stacks")
	var rings_state: Dictionary = act1_data.get("rings_state", {})
	_rings_client_seen = bool(rings_state.get("client_seen", _rings_client_seen))
	_rings_trace_seen = rings_state.get("trace_seen", _rings_trace_seen).duplicate(true)
	_rings_field_phase = str(rings_state.get("field_phase", _rings_field_phase))
	_rings_field_completed = rings_state.get("field_completed", _rings_field_completed).duplicate(true)
	_rings_field_operations_completed = rings_state.get("field_operations_completed", _rings_field_operations_completed).duplicate(true)
	_rings_field_choices = rings_state.get("field_choices", _rings_field_choices).duplicate(true)
	_rings_field_effects = rings_state.get("field_effects", _rings_field_effects).duplicate(true)
	_rings_field_decisions = int(rings_state.get("field_decisions", _rings_field_decisions))
	_restore_district_fieldwork_interactables("rings")

func _capture_zone_label() -> String:
	if _current_step.begins_with("channels"):
		return "Plumbing Power Project"
	if _current_step.begins_with("stacks"):
		return "The Open Files Initiative"
	if _current_step.begins_with("rings"):
		return "Greenfields Collective"
	if _current_step.begins_with("lockout"):
		return "Lockout Corridor"
	return "Act 1"

func _add_flora_node(parent: Node3D, id: String, species: String, zone: String, pos: Vector3, signal_type: String, signal_label: String, signal_pos: Vector3, color: Color, relationship_strength := 0.55, extra: Dictionary = {}) -> void:
	var root := Node3D.new()
	root.name = "Flora_%s" % id
	root.position = pos
	parent.add_child(root)

	for i in range(3):
		var stem := MeshInstance3D.new()
		var stem_mesh := CylinderMesh.new()
		stem_mesh.top_radius = 0.03
		stem_mesh.bottom_radius = 0.05
		stem_mesh.height = 0.42 + float(i) * 0.08
		stem.mesh = stem_mesh
		var stem_mat := StandardMaterial3D.new()
		stem_mat.albedo_color = color.darkened(0.45)
		stem.material_override = stem_mat
		stem.position = Vector3(-0.18 + float(i) * 0.18, 0.2, -0.05 + sin(float(i)) * 0.08)
		root.add_child(stem)

		var bloom := MeshInstance3D.new()
		var bloom_mesh := SphereMesh.new()
		bloom_mesh.radius = 0.11 + float(i) * 0.015
		bloom_mesh.height = 0.22 + float(i) * 0.03
		bloom.mesh = bloom_mesh
		var bloom_mat := StandardMaterial3D.new()
		bloom_mat.albedo_color = color
		bloom_mat.emission_enabled = true
		bloom_mat.emission = color
		bloom_mat.emission_energy_multiplier = 0.25
		bloom.material_override = bloom_mat
		bloom.position = Vector3(-0.18 + float(i) * 0.18, 0.48 + float(i) * 0.09, -0.05 + sin(float(i)) * 0.08)
		root.add_child(bloom)

	_flora_nodes[id] = {
		"zone": zone,
		"position": pos,
		"node": root,
	}
	_flora_system.register_node(id, {
		"species": species,
		"zone": zone,
		"position": pos,
		"signal_type": signal_type,
		"signal_label": signal_label,
		"signal_pos": signal_pos,
		"relationship_strength": relationship_strength,
		"tended": bool(extra.get("tended", false)),
		"childhood_species": bool(extra.get("childhood_species", false)),
		"role": str(extra.get("role", "sensor")),
		"forget_me_not": bool(extra.get("forget_me_not", false)),
	})

func _wait_for_arrivals(ids: Array[String], next_func: Callable, tag: String) -> void:
	var poll: Callable
	poll = func() -> void:
		for id in ids:
			if _game_state.is_moving(id):
				_scheduler.schedule_after(0.1, poll, tag)
				return
		_scheduler.schedule_after(0.0, next_func, tag)
	_scheduler.schedule_after(0.0, poll, tag)

func _move_party_and_continue(destinations: Dictionary, next_func: Callable, tag: String) -> void:
	var ids: Array[String] = []
	for id in destinations.keys():
		ids.append(id)
		_game_state.command_move_to_pos(id, destinations[id])
	_wait_for_arrivals(ids, next_func, tag)

func _bind_channels_field_sites_to_game_state() -> void:
	# Procedural chunks are built before TutorialSequence creates GameState. Bind this layer at the
	# registration seam so required-character checks, one-shot state, save/replay events, and enabled
	# gates are data-authoritative just like scene-authored interactables.
	if _game_state == null:
		return
	for site_id_variant in _channels_field_sites.keys():
		var site_id := str(site_id_variant)
		var site = _channels_field_sites[site_id]
		if not is_instance_valid(site):
			continue
		var spec: Dictionary = CHANNELS_FIELD_SITES.get(site_id, CHANNELS_OPTIONAL_SITES.get(site_id, {}))
		var kind := str(spec.get("kind", "optional"))
		var data_id := "ChannelsField_%s" % site_id
		_game_state.register_interactable({
			"id": data_id,
			"position": spec.get("pos", Vector3.ZERO),
			"radius": 1.7,
			"hold_time": _channels_field_site_work_seconds(site_id),
			"one_shot": kind != "choice",
			"requires_hold": false,
			"required_character": str(spec.get("role", "")),
			"tutorial_label": str(spec.get("verb", "INSPECT")),
			"enabled": false,
		})
		site.bind_data(_game_state, data_id)
		site.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
		site.set("required_character", str(spec.get("role", "")))
		site.set_interaction_enabled(false)
		if site.has_method("set_movement_authority"):
			site.set_movement_authority(_game_state)

func _reset_channels_fieldwork_state() -> void:
	for character in [_aster_node, _peris_node, _endo]:
		if is_instance_valid(character) and character.has_method("cancel_interaction_target"):
			character.cancel_interaction_target()
	_channels_field_completed.clear()
	_channels_field_operations_completed.clear()
	_channels_field_phase = ""
	_channels_field_choices.clear()
	_channels_field_attempts.clear()
	_channels_optional_findings.clear()
	_channels_field_decisions = 0
	for route_visual in _channels_field_route_visuals.values():
		if is_instance_valid(route_visual):
			route_visual.visible = false
	for site in _channels_field_sites.values():
		if not is_instance_valid(site):
			continue
		site.reset()
		site.set_interaction_enabled(false)
		site.hide_tutorial_label()
	for visual in _channels_field_visuals.values():
		if is_instance_valid(visual):
			visual.visible = false

func _restore_channels_fieldwork_interactables() -> void:
	for route_visual in _channels_field_route_visuals.values():
		if is_instance_valid(route_visual):
			route_visual.visible = false
	for site in _channels_field_sites.values():
		if is_instance_valid(site):
			site.set_interaction_enabled(false)
			site.hide_tutorial_label()
	for visual in _channels_field_visuals.values():
		if is_instance_valid(visual):
			visual.visible = false
	if CHANNELS_FIELD_OPERATIONS.has(_channels_field_phase):
		var operation: Dictionary = CHANNELS_FIELD_OPERATIONS[_channels_field_phase]
		var route_visual = _channels_field_route_visuals.get(_channels_field_phase)
		if is_instance_valid(route_visual):
			route_visual.visible = true
		var completed: Dictionary = _channels_field_completed.get(_channels_field_phase, {})
		for site_id in operation.get("evidence", []):
			if not bool(completed.get(str(site_id), false)):
				_set_channels_field_site_enabled(str(site_id), true, true)
		var pending_choice := str(_channels_field_choices.get(_channels_field_phase, ""))
		var resolution_sites: Dictionary = operation.get("resolution_sites", {})
		if pending_choice != "" and resolution_sites.has(pending_choice):
			_set_channels_field_site_enabled(str(resolution_sites[pending_choice]), true, true)
		elif _channels_operation_evidence_complete(_channels_field_phase):
			for site_id in operation.get("choices", []):
				_set_channels_field_site_enabled(str(site_id), true, true)
	if _current_step == "channels_explore":
		_enable_channels_optional_exploration()

func _set_channels_field_site_enabled(site_id: String, enabled: bool, reset_first := false) -> void:
	var site = _channels_field_sites.get(site_id)
	if not is_instance_valid(site):
		return
	if reset_first:
		site.reset()
	if site.has_method("set_interaction_enabled"):
		site.set_interaction_enabled(enabled)
	var visual = _channels_field_visuals.get(site_id)
	if is_instance_valid(visual):
		visual.visible = enabled
	if enabled:
		site.show_tutorial_label()
	else:
		site.hide_tutorial_label()

func _channels_operation_evidence_complete(operation_id: String) -> bool:
	if not CHANNELS_FIELD_OPERATIONS.has(operation_id):
		return false
	var completed: Dictionary = _channels_field_completed.get(operation_id, {})
	var evidence: Array = CHANNELS_FIELD_OPERATIONS[operation_id].get("evidence", [])
	for site_id in evidence:
		if not bool(completed.get(str(site_id), false)):
			return false
	return not evidence.is_empty()

func _start_channels_field_operation(operation_id: String) -> void:
	if not CHANNELS_FIELD_OPERATIONS.has(operation_id):
		return
	var operation: Dictionary = CHANNELS_FIELD_OPERATIONS[operation_id]
	if not _enter_step(str(operation.get("step", "channels_fieldwork"))):
		return
	_channels_field_phase = operation_id
	_channels_field_completed[operation_id] = {}
	_channels_field_attempts[operation_id] = 0
	_channels_field_choices.erase(operation_id)
	_select_character("aster")
	_player.set_move_enabled(true)
	_clear_markers()
	var route_visual = _channels_field_route_visuals.get(operation_id)
	if is_instance_valid(route_visual):
		route_visual.visible = true
	for site_id in operation.get("evidence", []):
		_set_channels_field_site_enabled(str(site_id), true, true)
	for site_id in operation.get("choices", []):
		_set_channels_field_site_enabled(str(site_id), false, true)
	for site_id in (operation.get("resolution_sites", {}) as Dictionary).values():
		_set_channels_field_site_enabled(str(site_id), false, true)
	var evidence: Array = operation.get("evidence", [])
	_tutorial_prompt.show_prompt(
		"%s // gather distinct field reads (0/%d)" % [str(operation.get("label", "FIELDWORK")), evidence.size()]
	)
	_show_overlay_note("The party can service character-specific stations without manual switch padding.", 3.2)

func _on_channels_field_route_requested(_target: Node, world_position: Vector3, site_id: String) -> void:
	# A field read is party movement, even though one specialist performs the final work. Sending the
	# other two to the same measured bay makes the authored route real and leaves everyone together
	# for the next decision instead of yo-yoing followers across the corridor.
	if not CHANNELS_FIELD_SITES.has(site_id) and not CHANNELS_OPTIONAL_SITES.has(site_id):
		return
	var spec: Dictionary = CHANNELS_FIELD_SITES.get(site_id, CHANNELS_OPTIONAL_SITES.get(site_id, {}))
	var specialist := str(spec.get("role", ""))
	var offsets := {
		"aster": Vector3(-1.2, 0.0, -0.8),
		"peris": Vector3(-1.0, 0.0, 1.0),
		"endo": Vector3(1.1, 0.0, -0.6),
	}
	for char_id in ["aster", "peris", "endo"]:
		if char_id == specialist or _game_state == null or not _game_state.characters.has(char_id):
			continue
		_game_state.command_move_to_pos(char_id, world_position + offsets[char_id])

func _on_channels_field_site_interacted(site_id: String) -> void:
	if CHANNELS_OPTIONAL_SITES.has(site_id):
		if _current_step != "channels_explore" or bool(_channels_optional_findings.get(site_id, false)):
			return
		_channels_optional_findings[site_id] = true
		var optional_spec: Dictionary = CHANNELS_OPTIONAL_SITES[site_id]
		_show_overlay_note(str(optional_spec.get("finding", "The party records an optional field note.")), 4.2)
		_tutorial_prompt.show_prompt(
			"Optional Channels records %d/%d // continue to the Stacks when ready" % [
				_channels_optional_findings.size(), CHANNELS_OPTIONAL_SITES.size(),
			]
		)
		return
	if not CHANNELS_FIELD_SITES.has(site_id):
		return
	var spec: Dictionary = CHANNELS_FIELD_SITES[site_id]
	var operation_id := str(spec.get("operation", ""))
	if operation_id != _channels_field_phase or not CHANNELS_FIELD_OPERATIONS.has(operation_id):
		return
	var operation: Dictionary = CHANNELS_FIELD_OPERATIONS[operation_id]
	var kind := str(spec.get("kind", "evidence"))
	if kind == "evidence":
		var completed: Dictionary = _channels_field_completed.get(operation_id, {})
		if bool(completed.get(site_id, false)):
			return
		completed[site_id] = true
		_channels_field_completed[operation_id] = completed
		_show_overlay_note(str(spec.get("finding", "Field evidence recorded.")), 4.2)
		var evidence: Array = operation.get("evidence", [])
		if _channels_operation_evidence_complete(operation_id):
			for choice_id in operation.get("choices", []):
				_set_channels_field_site_enabled(str(choice_id), true, true)
				var choice_spec: Dictionary = CHANNELS_FIELD_SITES.get(str(choice_id), {})
				_show_marker(
					choice_spec.get("pos", Vector3.ZERO) + Vector3(0, 2.3, 0),
					str(choice_spec.get("display", "COMMIT")), operation.get("tint", Color.WHITE)
				)
			_tutorial_prompt.show_prompt("Evidence complete // compare it, then commit one marked response")
		else:
			_tutorial_prompt.show_prompt(
				"%s // distinct field reads (%d/%d)" % [
					str(operation.get("label", "FIELDWORK")), completed.size(), evidence.size(),
				]
			)
		return
	if kind == "resolution":
		var committed_choice := str(_channels_field_choices.get(operation_id, ""))
		var resolution_sites: Dictionary = operation.get("resolution_sites", {})
		if committed_choice == "" or str(resolution_sites.get(committed_choice, "")) != site_id:
			var unresolved_resolution = _channels_field_sites.get(site_id)
			if is_instance_valid(unresolved_resolution):
				unresolved_resolution.reset()
			return
		_channels_field_operations_completed[operation_id] = true
		_show_overlay_note(str(spec.get("finding", "The chosen field response is complete.")), 4.5)
		_apply_channels_field_choice(operation_id, committed_choice)
		_set_channels_field_site_enabled(site_id, false)
		_clear_markers()
		_complete_channels_field_operation(operation_id)
		return

	if kind != "choice" or not _channels_operation_evidence_complete(operation_id):
		var unresolved = _channels_field_sites.get(site_id)
		if is_instance_valid(unresolved):
			unresolved.reset()
		return
	_channels_field_attempts[operation_id] = int(_channels_field_attempts.get(operation_id, 0)) + 1
	var valid_choices: Array = operation.get("valid_choices", [])
	if not valid_choices.has(site_id):
		_show_overlay_note(str(spec.get("finding", "That conclusion conflicts with the field evidence.")), 4.5)
		_tutorial_prompt.show_prompt("The reads do not support that response // compare the marked alternative")
		var rejected = _channels_field_sites.get(site_id)
		if is_instance_valid(rejected):
			rejected.reset()
			rejected.set_interaction_enabled(true)
		return

	_channels_field_choices[operation_id] = site_id
	_channels_field_decisions += 1
	_show_overlay_note(str(spec.get("finding", "Field response committed.")), 4.5)
	for operation_site_id in operation.get("evidence", []):
		_set_channels_field_site_enabled(str(operation_site_id), false)
	for operation_site_id in operation.get("choices", []):
		_set_channels_field_site_enabled(str(operation_site_id), false)
	var resolution_sites: Dictionary = operation.get("resolution_sites", {})
	if resolution_sites.has(site_id):
		var resolution_id := str(resolution_sites[site_id])
		_set_channels_field_site_enabled(resolution_id, true, true)
		var resolution_spec: Dictionary = CHANNELS_FIELD_SITES[resolution_id]
		_show_marker(
			resolution_spec.get("pos", Vector3.ZERO) + Vector3(0, 2.3, 0),
			str(resolution_spec.get("display", "APPLY")), operation.get("tint", Color.WHITE)
		)
		_tutorial_prompt.show_prompt("Decision committed // execute it at the marked field station")
		return
	_channels_field_operations_completed[operation_id] = true
	_apply_channels_field_choice(operation_id, site_id)
	_clear_markers()
	_complete_channels_field_operation(operation_id)

func _apply_channels_field_choice(operation_id: String, site_id: String) -> void:
	match operation_id:
		"harvest":
			if site_id == "harvest_reserve":
				for char_id in ["aster", "peris", "endo"]:
					if _game_state != null and _game_state.characters.has(char_id):
						var stats: Dictionary = _game_state.characters[char_id].stats
						stats["atp"] = minf(10.0, float(stats.get("atp", 0.0)) + 2.0)
			else:
				_aster_hp = minf(CHANNELS_MAX_HP, _aster_hp + 25.0)
				_peris_hp = minf(CHANNELS_MAX_HP, _peris_hp + 25.0)
		"relay":
			if site_id == "relay_pressure" and _channels_window_lanes.has("window_two"):
				var lane: Dictionary = _channels_window_lanes["window_two"]
				lane["safe_duration"] = maxf(
					float(lane.get("safe_duration", CHANNELS_WINDOW_TWO_DURATION)),
					CHANNELS_WINDOW_TWO_DURATION + 3.0
				)
				_channels_window_lanes["window_two"] = lane
			elif site_id == "relay_recovery":
				_aster_hp = minf(CHANNELS_MAX_HP, _aster_hp + 18.0)
				_peris_hp = minf(CHANNELS_MAX_HP, _peris_hp + 18.0)

func _complete_channels_field_operation(operation_id: String) -> void:
	var route_visual = _channels_field_route_visuals.get(operation_id)
	if is_instance_valid(route_visual):
		route_visual.visible = false
	_channels_field_phase = ""
	var next := str(CHANNELS_FIELD_OPERATIONS[operation_id].get("next", ""))
	match next:
		"to_memory":
			_start_channels_to_memory()
		"corpse":
			_start_channels_corpse()
		"window_one":
			_start_channels_window_intro("window_one")
		"to_flure":
			_start_channels_to_flure()
		"window_two":
			_start_channels_window_intro("window_two")
		"to_encounter":
			_start_channels_to_encounter()

func _enable_channels_optional_exploration() -> void:
	for site_id in CHANNELS_OPTIONAL_SITES.keys():
		if bool(_channels_optional_findings.get(site_id, false)):
			continue
		_set_channels_field_site_enabled(str(site_id), true, true)

func _channels_field_site_position(site_id: String) -> Vector3:
	if CHANNELS_FIELD_SITES.has(site_id):
		return CHANNELS_FIELD_SITES[site_id].get("pos", Vector3.ZERO)
	if CHANNELS_OPTIONAL_SITES.has(site_id):
		return CHANNELS_OPTIONAL_SITES[site_id].get("pos", Vector3.ZERO)
	return Vector3.ZERO

func _channels_field_site_work_seconds(site_id: String) -> float:
	if CHANNELS_FIELD_SITES.has(site_id):
		return float(CHANNELS_FIELD_SITES[site_id].get("dwell", 0.0)) + CHANNELS_FIELD_ACTION_EXTENSION_SECONDS
	if CHANNELS_OPTIONAL_SITES.has(site_id):
		return float(CHANNELS_OPTIONAL_SITES[site_id].get("dwell", 0.0))
	return 0.0

func _channels_search_route_distance(
	current: Vector3,
	remaining: Array,
	choice_positions: Array,
	end: Vector3,
	distance_so_far: float,
	best: Array
) -> void:
	if distance_so_far >= float(best[0]):
		return
	if remaining.is_empty():
		for tail_variant in choice_positions:
			var tail: Dictionary = tail_variant
			var choice_pos: Vector3 = tail.get("choice", Vector3.ZERO)
			var tail_distance := current.distance_to(choice_pos)
			if tail.has("resolution"):
				var resolution_pos: Vector3 = tail.get("resolution", choice_pos)
				tail_distance += choice_pos.distance_to(resolution_pos) + resolution_pos.distance_to(end)
			else:
				tail_distance += choice_pos.distance_to(end)
			best[0] = minf(float(best[0]), distance_so_far + tail_distance)
		return
	for i in range(remaining.size()):
		var next_pos: Vector3 = remaining[i]
		var next_remaining := remaining.duplicate()
		next_remaining.remove_at(i)
		_channels_search_route_distance(
			next_pos, next_remaining, choice_positions, end,
			distance_so_far + current.distance_to(next_pos), best
		)

func _channels_shortest_operation_route(operation_id: String) -> float:
	if not CHANNELS_FIELD_OPERATIONS.has(operation_id):
		return 0.0
	var operation: Dictionary = CHANNELS_FIELD_OPERATIONS[operation_id]
	var evidence_positions: Array = []
	for site_id in operation.get("evidence", []):
		evidence_positions.append(_channels_field_site_position(str(site_id)))
	var choice_positions: Array = []
	var resolution_sites: Dictionary = operation.get("resolution_sites", {})
	for site_id in operation.get("valid_choices", []):
		var tail := {"choice": _channels_field_site_position(str(site_id))}
		if resolution_sites.has(str(site_id)):
			tail["resolution"] = _channels_field_site_position(str(resolution_sites[str(site_id)]))
		choice_positions.append(tail)
	var best := [INF]
	_channels_search_route_distance(
		operation.get("start", Vector3.ZERO), evidence_positions, choice_positions,
		operation.get("end", Vector3.ZERO), 0.0, best
	)
	return float(best[0]) if is_finite(float(best[0])) else 0.0

func get_channels_playtime_contract() -> Dictionary:
	# The previous full first-clear measurement was 306 s. The field operations replace 42 s of
	# straight inter-beat walking, while preserving 112 s of window/hide execution and 152 s of
	# authored dialogue/staging. Field travel uses the party's slow reliable pace (2.5 m/s); dwell is
	# the actual click-gated work configured on each station. Evidence interpretation and decisions
	# are benchmark allowances for reading unique clues, never scheduler waits.
	var route_by_operation := {}
	var route_meters := 0.0
	var work_seconds := 0.0
	var evidence_count := 0
	var resolution_action_count := 0
	var decision_seconds := 0.0
	for operation_id in CHANNELS_FIELD_OPERATIONS.keys():
		var operation: Dictionary = CHANNELS_FIELD_OPERATIONS[operation_id]
		var operation_route := _channels_shortest_operation_route(str(operation_id))
		route_by_operation[operation_id] = operation_route
		route_meters += operation_route
		decision_seconds += float(operation.get("decision_seconds", 0.0))
		for site_id in operation.get("evidence", []):
			work_seconds += _channels_field_site_work_seconds(str(site_id))
			evidence_count += 1
		var valid_choices: Array = operation.get("valid_choices", [])
		var resolution_sites: Dictionary = operation.get("resolution_sites", {})
		var shortest_choice_work := INF
		for site_id in valid_choices:
			var choice_work := _channels_field_site_work_seconds(str(site_id))
			if resolution_sites.has(str(site_id)):
				choice_work += _channels_field_site_work_seconds(str(resolution_sites[str(site_id)]))
			shortest_choice_work = minf(shortest_choice_work, choice_work)
		if is_finite(shortest_choice_work):
			work_seconds += shortest_choice_work
		resolution_action_count += 1 if not resolution_sites.is_empty() else 0
	var travel_seconds := route_meters / 2.5
	var interpretation_seconds := float(evidence_count) * 6.5
	var preserved_active_seconds := 112.0
	var preserved_narrative_seconds := 152.0
	var active_seconds := preserved_active_seconds + travel_seconds + work_seconds + interpretation_seconds + decision_seconds
	var first_clear_seconds := active_seconds + preserved_narrative_seconds
	var optional_work_seconds := 0.0
	for site_id in CHANNELS_OPTIONAL_SITES.keys():
		optional_work_seconds += float(CHANNELS_OPTIONAL_SITES[site_id].get("dwell", 0.0)) + 6.5
	return {
		"contract_id": "channels_longform_fieldwork_v1",
		"target_min_seconds": 1200.0,
		"target_max_seconds": 1800.0,
		"legacy_measured_first_clear_seconds": 306.0,
		"replaced_direct_travel_seconds": 42.0,
		"preserved_active_seconds": preserved_active_seconds,
		"preserved_narrative_seconds": preserved_narrative_seconds,
		"shortest_field_route_meters": route_meters,
		"route_meters_by_operation": route_by_operation,
		"field_travel_seconds": travel_seconds,
		"field_work_seconds": work_seconds,
		"evidence_interpretation_seconds": interpretation_seconds,
		"decision_seconds": decision_seconds,
		"modeled_active_seconds": active_seconds,
		"meaningful_active_seconds": active_seconds,
		"modeled_first_clear_seconds": first_clear_seconds,
		"total_play_seconds": first_clear_seconds,
		"modeled_active_ratio": active_seconds / maxf(first_clear_seconds, 0.001),
		"mandatory_operation_count": CHANNELS_FIELD_OPERATIONS.size(),
		"mandatory_evidence_count": evidence_count,
		"mandatory_resolution_action_count": resolution_action_count,
		"decision_count": CHANNELS_FIELD_OPERATIONS.size() + 3,
		"branch_count": 4,
		"optional_site_count": CHANNELS_OPTIONAL_SITES.size(),
		"optional_interpretation_and_work_seconds": optional_work_seconds,
		"estimation_basis": "exact shortest evidence-route search + configured dwell + measured legacy remainder + clue/decision benchmark",
	}

func _set_channels_flure_active(active: bool) -> void:
	if _channels_flure:
		var mat := _channels_flure.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 1.4 if active else 0.25
	if _channels_flure_light:
		_channels_flure_light.light_energy = 2.0 if active else 0.45

func _set_channels_flow_power(power: float) -> void:
	_channels_flow_power = clampf(power, 0.0, 1.0)
	for strip in _channels_flow_strips:
		if strip == null:
			continue
		var mat := strip.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.1, 0.15, 0.2).lerp(Color(0.16, 0.24, 0.34), _channels_flow_power)
			mat.emission_energy_multiplier = lerpf(0.3, 1.35, _channels_flow_power)

func _channels_window_branch_direction(stage_pos: Vector3, lure_pos: Vector3) -> Vector3:
	var branch := lure_pos - stage_pos
	branch.y = 0.0
	if branch.length() <= 0.001:
		return Vector3.FORWARD
	return branch.normalized()

func _channels_window_cross_direction(branch_dir: Vector3) -> Vector3:
	return Vector3(-branch_dir.z, 0.0, branch_dir.x).normalized()

func _channels_window_add_wrapped_interval(intervals: Array, start: float, duration: float, period: float) -> void:
	var wrapped_start := fposmod(start, period)
	var end := wrapped_start + duration
	if end <= period:
		intervals.append({"start": wrapped_start, "end": end})
		return
	intervals.append({"start": wrapped_start, "end": period})
	intervals.append({"start": 0.0, "end": end - period})

func _channels_window_offset_washes(lane: Dictionary, flow_offset: float) -> bool:
	var period := float(lane.get("flow_period", CHANNELS_WINDOW_FLOW_PERIOD))
	var flood_duration := float(lane.get("flood_duration", CHANNELS_WINDOW_FLOOD_DURATION))
	var channels: Array = lane.get("periodic_channels", [])
	for channel_variant in channels:
		var channel: Dictionary = channel_variant
		var local_phase := fposmod(
			flow_offset
			+ float(channel.get("contact_time", 0.0))
			+ float(channel.get("phase_offset", 0.0)),
			period
		)
		if local_phase < flood_duration:
			return true
	return false

func _channels_window_wash_analysis(lane: Dictionary, sample_count := 72) -> Dictionary:
	var period := float(lane.get("flow_period", CHANNELS_WINDOW_FLOW_PERIOD))
	var flood_duration := float(lane.get("flood_duration", CHANNELS_WINDOW_FLOOD_DURATION))
	var channels: Array = lane.get("periodic_channels", [])
	var intervals: Array = []
	for channel_variant in channels:
		var channel: Dictionary = channel_variant
		var start := -float(channel.get("contact_time", 0.0)) - float(channel.get("phase_offset", 0.0))
		_channels_window_add_wrapped_interval(intervals, start, flood_duration, period)
	intervals.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("start", 0.0)) < float(b.get("start", 0.0)))
	var merged: Array = []
	for interval_variant in intervals:
		var interval: Dictionary = interval_variant
		if merged.is_empty():
			merged.append(interval.duplicate(true))
			continue
		var current: Dictionary = merged[merged.size() - 1]
		if float(interval.get("start", 0.0)) <= float(current.get("end", 0.0)) + 0.0001:
			current["end"] = maxf(float(current.get("end", 0.0)), float(interval.get("end", 0.0)))
			merged[merged.size() - 1] = current
			continue
		merged.append(interval.duplicate(true))
	var largest_gap := period
	if not merged.is_empty():
		largest_gap = 0.0
		for i in range(merged.size()):
			var current: Dictionary = merged[i]
			var next: Dictionary = merged[(i + 1) % merged.size()]
			var gap := float(next.get("start", 0.0)) - float(current.get("end", 0.0))
			if i == merged.size() - 1:
				gap = float(next.get("start", 0.0)) + period - float(current.get("end", 0.0))
			largest_gap = maxf(largest_gap, gap)
	var failed_offsets: Array = []
	for i in range(maxi(1, sample_count)):
		var offset := period * float(i) / float(maxi(1, sample_count))
		if not _channels_window_offset_washes(lane, offset):
			failed_offsets.append(offset)
	return {
		"guaranteed": largest_gap <= 0.0001 and failed_offsets.is_empty(),
		"coverage_gap": maxf(0.0, largest_gap),
		"sample_count": maxi(1, sample_count),
		"failed_offsets": failed_offsets,
	}

func _channels_window_local_phase(current_tick: float, lane: Dictionary, channel: Dictionary) -> float:
	var period := float(lane.get("flow_period", CHANNELS_WINDOW_FLOW_PERIOD))
	return fposmod(
		current_tick
		+ float(lane.get("flow_offset", 0.0))
		+ float(channel.get("phase_offset", 0.0)),
		period
	)

func _channels_window_channel_level(local_phase: float, flood_duration: float, period: float) -> float:
	if local_phase < flood_duration:
		var flood_t := clampf(local_phase / maxf(flood_duration, 0.001), 0.0, 1.0)
		return 0.68 + 0.32 * sin(PI * flood_t)
	var cooldown_t := clampf((local_phase - flood_duration) / maxf(period - flood_duration, 0.001), 0.0, 1.0)
	return lerpf(0.28, 0.08, cooldown_t)

func _add_channels_window_bridge_segment(parent: Node3D, name: String, from_pos: Vector3, to_pos: Vector3) -> MeshInstance3D:
	var segment := MeshInstance3D.new()
	segment.name = name
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.45, 0.18, maxf(0.8, from_pos.distance_to(to_pos) + 0.35))
	segment.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.16, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(0.48, 0.3, 0.12)
	mat.emission_energy_multiplier = 0.15
	segment.material_override = mat
	segment.position = (from_pos + to_pos) * 0.5 + Vector3(0.0, 0.72, 0.0)
	segment.look_at_from_position(segment.position, to_pos + Vector3(0.0, 0.72, 0.0), Vector3.UP, true)
	parent.add_child(segment)
	return segment

func _reset_channels_window_swarm(lane: Dictionary) -> Dictionary:
	lane["swarm_state"] = "idle"
	lane["washed_channel_index"] = -1
	lane["swarm_start_tick"] = -1.0
	var swarm_units: Array = lane.get("swarm_units", [])
	for i in range(swarm_units.size()):
		var unit: Dictionary = swarm_units[i]
		unit["state"] = "idle"
		unit["path_index"] = 0
		unit["wash_vector"] = Vector3.ZERO
		var node: MeshInstance3D = unit.get("node")
		if is_instance_valid(node):
			node.visible = true
			node.scale = Vector3.ONE
			node.position = unit.get("base_pos", node.position)
		swarm_units[i] = unit
	lane["swarm_units"] = swarm_units
	return lane

func _trigger_channels_window_swarm_wash(window_id: String, lane: Dictionary, channel_index: int, current_tick: float) -> Dictionary:
	var branch_dir: Vector3 = lane.get("branch_dir", Vector3.FORWARD)
	var cross_dir: Vector3 = lane.get("cross_dir", Vector3.RIGHT)
	lane["swarm_state"] = "washing"
	lane["washed_channel_index"] = channel_index
	lane["swarm_start_tick"] = current_tick
	var swarm_units: Array = lane.get("swarm_units", [])
	for i in range(swarm_units.size()):
		var unit: Dictionary = swarm_units[i]
		unit["state"] = "wash"
		unit["wash_vector"] = branch_dir * CHANNELS_WINDOW_SWARM_WASH_SPEED + cross_dir * (CHANNELS_WINDOW_SWARM_OFFSETS[i] * 0.65)
		swarm_units[i] = unit
	lane["swarm_units"] = swarm_units
	_channels_window_lanes[window_id] = lane
	return lane

func _set_channels_shortcut_unlocked(unlocked: bool) -> void:
	_channels_shortcut_unlocked = unlocked
	if _channels_shortcut_gate_collision:
		_channels_shortcut_gate_collision.disabled = unlocked
	if _channels_shortcut_gate_mesh:
		_channels_shortcut_gate_mesh.visible = not unlocked
	if _channels_shortcut_light:
		_channels_shortcut_light.light_color = Color(0.88, 0.72, 0.44) if unlocked else Color(0.34, 0.42, 0.54)
		_channels_shortcut_light.light_energy = 2.0 if unlocked else 0.8

func _recuperate_channels_party() -> void:
	_channels_party_recuperated = true
	_aster_hp = CHANNELS_MAX_HP
	_peris_hp = CHANNELS_MAX_HP
	for char_id in ["aster", "peris", "endo"]:
		if _game_state == null or not _game_state.characters.has(char_id):
			continue
		var stats: Dictionary = _game_state.characters[char_id].stats
		stats["hp"] = CHANNELS_MAX_HP
		stats["atp"] = CHANNELS_REST_ATP

func _start_channels_flure_flush() -> void:
	_channels_flush_state = "pull"
	_channels_flush_timer = 0.0
	_set_channels_flow_power(0.55)
	for i in range(_channels_flush_swarm_units.size()):
		var unit := _channels_flush_swarm_units[i]
		unit["state"] = "pull"
		unit["active"] = true
		if unit.get("node") != null:
			unit["node"].visible = true
		_channels_flush_swarm_units[i] = unit

func _update_channels_flure_flush(delta: float, spd: float) -> void:
	if _channels_flush_state == "":
		if _channels_flow_power > 0.001:
			_set_channels_flow_power(maxf(0.0, _channels_flow_power - delta * spd * 0.5))
		return

	_channels_flush_timer += delta * spd
	match _channels_flush_state:
		"pull":
			_set_channels_flow_power(0.7 + 0.25 * absf(sin(_channels_flush_timer * 3.2)))
			for i in range(_channels_flush_swarm_units.size()):
				var unit := _channels_flush_swarm_units[i]
				if not bool(unit.get("active", false)):
					continue
				var node: MeshInstance3D = unit.get("node")
				if node == null:
					continue
				var target := CHANNELS_FLURE_POS + Vector3(0.45 * CHANNELS_FLUSH_SWARM_OFFSETS[i], 0.15, -0.4)
				node.position = node.position.move_toward(target, delta * spd * 3.2)
			if _channels_flush_timer >= 1.1:
				_channels_flush_state = "wash"
				_channels_flush_timer = 0.0
		"wash":
			_set_channels_flow_power(1.0)
			for i in range(_channels_flush_swarm_units.size()):
				var unit := _channels_flush_swarm_units[i]
				if not bool(unit.get("active", false)):
					continue
				var node: MeshInstance3D = unit.get("node")
				if node == null:
					continue
				node.position.x += delta * spd * 7.5
				node.position.y = maxf(0.18, node.position.y - delta * spd * 0.35)
				node.scale = node.scale.lerp(Vector3.ONE * 0.4, clampf(delta * spd * 2.5, 0.0, 1.0))
			if _channels_flush_timer >= 1.1:
				_channels_flush_state = "cooldown"
				_channels_flush_timer = 0.0
		"cooldown":
			_set_channels_flow_power(maxf(0.0, 0.9 - _channels_flush_timer * 1.5))
			if _channels_flush_timer >= 0.6:
				for i in range(_channels_flush_swarm_units.size()):
					var unit := _channels_flush_swarm_units[i]
					var node: MeshInstance3D = unit.get("node")
					if node:
						node.visible = false
						node.scale = Vector3.ONE
						node.position = unit.get("base_pos", node.position)
					unit["active"] = false
					unit["state"] = ""
					_channels_flush_swarm_units[i] = unit
				_channels_flush_state = ""
				_channels_flush_timer = 0.0
				_set_channels_flow_power(0.25)

func _set_channels_run_lure_active(active: bool) -> void:
	_channels_run_lure_active = active
	if _channels_run_lure_mesh:
		var mat := _channels_run_lure_mesh.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 2.0 if active else 0.35
	if _channels_run_lure_light:
		_channels_run_lure_light.light_energy = 2.4 if active else 0.5

func _show_marker(pos: Vector3, text: String, tint := Color(0.4, 0.7, 0.5, 0.75)) -> void:
	var lbl := Label3D.new()
	lbl.name = "Marker_" + text
	lbl.text = text
	lbl.font_size = 28
	lbl.pixel_size = 0.008
	lbl.modulate = tint
	lbl.outline_modulate = Color(0, 0, 0, 0.5)
	lbl.outline_size = 8
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = pos
	var env: Node = find_child("Environment", false, false)
	if env:
		env.add_child(lbl)

func _clear_markers() -> void:
	var env: Node = find_child("Environment", false, false)
	if env == null:
		return
	for child in env.get_children():
		if child is Label3D and child.name.begins_with("Marker_"):
			child.queue_free()

func _get_channels_window_party_positions(window_id: String) -> Dictionary:
	match window_id:
		"window_one":
			return {
				"aster": CHANNELS_WINDOW_ONE_STAGE_POS,
				"peris": CHANNELS_WINDOW_ONE_STAGE_POS + Vector3(-1.6, 0.0, 1.2),
				"endo": CHANNELS_WINDOW_ONE_STAGE_POS + Vector3(-2.8, 0.0, -1.0),
			}
		"window_two":
			return {
				"aster": CHANNELS_WINDOW_TWO_STAGE_POS,
				"peris": CHANNELS_WINDOW_TWO_STAGE_POS + Vector3(-1.6, 0.0, 1.2),
				"endo": CHANNELS_WINDOW_TWO_STAGE_POS + Vector3(-2.8, 0.0, -1.0),
			}
		_:
			return {}

func _channels_window_step_name(window_id: String, suffix: String) -> String:
	return "channels_%s_%s" % [window_id, suffix]

func _set_channels_window_lane_active(window_id: String, active: bool) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	var lane: Dictionary = _channels_window_lanes[window_id]
	lane["lure_active"] = active
	var lure_mesh = lane.get("lure_mesh")
	if is_instance_valid(lure_mesh):
		var mat := lure_mesh.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 1.9 if active else 0.35
	var lure_light = lane.get("lure_light")
	if is_instance_valid(lure_light):
		lure_light.light_energy = 2.1 if active else 0.45
	_channels_window_lanes[window_id] = lane

func _reset_channels_window_lane(window_id: String) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	if _scheduler:
		_scheduler.cancel_tag("channels_%s_expire" % window_id)
		_scheduler.cancel_tag("channels_%s_retry" % window_id)
	_set_channels_window_lane_active(window_id, false)
	var lane: Dictionary = _channels_window_lanes[window_id]
	lane["phase"] = "idle"
	lane["safe_until_tick"] = -1.0
	lane["last_outcome"] = ""
	lane["flow_offset"] = 0.0
	var curtain_nodes: Array = lane.get("curtain_nodes", [])
	var curtain_pos: Vector3 = lane.get("curtain_pos", Vector3.ZERO)
	for i in range(curtain_nodes.size()):
		var node = curtain_nodes[i]
		if is_instance_valid(node):
			node.position = curtain_pos + Vector3(0, 0, CHANNELS_WINDOW_CURTAIN_OFFSETS[i])
	if lane.has("interactable"):
		var interactable = lane["interactable"]
		if is_instance_valid(interactable):
			interactable.reset()
			interactable.show_tutorial_label()
	lane = _reset_channels_window_swarm(lane)
	_channels_window_lanes[window_id] = lane

func _begin_channels_window_lane(window_id: String) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	if not _enter_step(_channels_window_step_name(window_id, "activate")):
		return
	_channels_active_window_lane = window_id
	_select_character("aster")
	_player.set_move_enabled(true)
	_reset_channels_window_lane(window_id)
	var lane: Dictionary = _channels_window_lanes[window_id]
	lane["phase"] = "activate"
	_channels_window_lanes[window_id] = lane
	_clear_markers()
	_show_marker(lane["lure_pos"] + Vector3(0, 2.0, 0), "LURE", Color(0.76, 0.46, 0.2, 0.85))
	_show_marker(lane["goal_pos"] + Vector3(0, 2.0, 0), "CROSS", Color(0.36, 0.74, 0.88, 0.85))
	_tutorial_prompt.show_prompt("Hold at the lure, then cross before the channel fills again")

func _on_channels_window_lure_activated(window_id: String) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	if _channels_active_window_lane != window_id:
		return
	if _current_step not in [
		_channels_window_step_name(window_id, "activate"),
		_channels_window_step_name(window_id, "cross"),
	]:
		return
	var lane: Dictionary = _channels_window_lanes[window_id]
	if bool(lane.get("lure_active", false)):
		return
	_set_channels_window_lane_active(window_id, true)
	lane = _channels_window_lanes[window_id]
	lane["phase"] = "cross"
	var current_tick := _scheduler.get_current_tick() if _scheduler else 0.0
	lane["safe_until_tick"] = current_tick + float(lane.get("safe_duration", 0.0))
	lane["swarm_state"] = "advancing"
	lane["swarm_start_tick"] = current_tick
	lane["washed_channel_index"] = -1
	var swarm_units: Array = lane.get("swarm_units", [])
	for i in range(swarm_units.size()):
		var unit: Dictionary = swarm_units[i]
		unit["state"] = "advance"
		unit["path_index"] = 1
		unit["wash_vector"] = Vector3.ZERO
		swarm_units[i] = unit
	lane["swarm_units"] = swarm_units
	_channels_window_lanes[window_id] = lane
	_enter_step(_channels_window_step_name(window_id, "cross"))
	if lane.has("interactable"):
		var interactable = lane["interactable"]
		if is_instance_valid(interactable):
			interactable.hide_tutorial_label()
	_tutorial_prompt.show_prompt("Move. The corridor stays clear only while the lure holds")
	_scheduler.cancel_tag("channels_%s_expire" % window_id)
	_scheduler.schedule_after(float(lane.get("safe_duration", 0.0)), func():
		_on_channels_window_lure_expired(window_id)
	, "channels_%s_expire" % window_id)

func _on_channels_window_lure_expired(window_id: String) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	if _channels_active_window_lane != window_id:
		return
	if _current_step != _channels_window_step_name(window_id, "cross"):
		return
	_set_channels_window_lane_active(window_id, false)
	var lane: Dictionary = _channels_window_lanes[window_id]
	lane["safe_until_tick"] = -1.0
	_channels_window_lanes[window_id] = lane
	_fail_channels_window_lane(window_id, "window_closed")

func _fail_channels_window_lane(window_id: String, reason: String) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	if _current_step not in [
		_channels_window_step_name(window_id, "activate"),
		_channels_window_step_name(window_id, "cross"),
	]:
		return
	var lane: Dictionary = _channels_window_lanes[window_id]
	if str(lane.get("phase", "")) == "failed":
		return
	_player.set_move_enabled(false)
	for cid in ["aster", "peris", "endo"]:
		if _game_state.characters.has(cid):
			_game_state.command_stop(cid)
	lane["phase"] = "failed"
	lane["last_outcome"] = reason
	_channels_window_lanes[window_id] = lane
	_tutorial_prompt.show_prompt("Too slow. The Techos spill back into the lane.")
	_clear_markers()
	_show_marker(lane["curtain_pos"] + Vector3(0, 2.0, 0), "BLOCKED", Color(0.86, 0.28, 0.22, 0.88))
	_scheduler.schedule_after(1.0, func():
		_restart_channels_window_lane(window_id)
	, "channels_%s_retry" % window_id)

func _restart_channels_window_lane(window_id: String) -> void:
	if not _enter_step(_channels_window_step_name(window_id, "reset")):
		return
	var party_positions := _get_channels_window_party_positions(window_id)
	_move_party_and_continue(party_positions, func():
		_begin_channels_window_lane(window_id)
	, "channels_%s_reset_move" % window_id)

func _complete_channels_window_lane(window_id: String) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	var lane: Dictionary = _channels_window_lanes[window_id]
	lane["phase"] = "safe"
	lane["last_outcome"] = "success"
	lane["safe_until_tick"] = -1.0
	_channels_window_lanes[window_id] = lane
	_channels_active_window_lane = ""
	_set_channels_window_lane_active(window_id, false)
	_scheduler.cancel_tag("channels_%s_expire" % window_id)
	_clear_markers()
	_tutorial_prompt.hide_prompt()
	match window_id:
		"window_one":
			_start_channels_field_operation("relay")
		"window_two":
			_start_channels_field_operation("escape")

func _update_channels_window_puzzles(delta: float, spd: float) -> void:
	for window_id in _channels_window_lanes.keys():
		var lane: Dictionary = _channels_window_lanes[window_id]
		var current_tick := _scheduler.get_current_tick() if _scheduler else 0.0
		var flow_period := float(lane.get("flow_period", CHANNELS_WINDOW_FLOW_PERIOD))
		var flood_duration := float(lane.get("flood_duration", CHANNELS_WINDOW_FLOOD_DURATION))
		var periodic_channels: Array = lane.get("periodic_channels", [])
		for i in range(periodic_channels.size()):
			var channel: Dictionary = periodic_channels[i]
			var local_phase := _channels_window_local_phase(current_tick, lane, channel)
			var level := _channels_window_channel_level(local_phase, flood_duration, flow_period)
			channel["local_phase"] = local_phase
			channel["level"] = level
			channel["flooded"] = local_phase < flood_duration
			var water = channel.get("water")
			var water_height := -0.22
			var water_scale := maxf(0.08, level)
			if is_instance_valid(water):
				water.scale = Vector3(1.0, water_scale, 1.0)
				water.position.y = -0.42 + water.scale.y * 0.46
				water_height = water.position.y
				var water_mat := water.material_override as StandardMaterial3D
				if water_mat:
					water_mat.emission_energy_multiplier = lerpf(0.2, 1.3, level)
			var foam = channel.get("foam")
			if is_instance_valid(foam):
				foam.position.y = water_height + 0.42 * water_scale
				foam.visible = bool(channel.get("flooded", false))
				var foam_mat := foam.material_override as StandardMaterial3D
				if foam_mat:
					foam_mat.albedo_color.a = 0.35 + 0.45 * level
					foam_mat.emission_energy_multiplier = lerpf(0.08, 0.48, level)
			var light = channel.get("light")
			if is_instance_valid(light):
				light.light_energy = lerpf(0.2, 1.15, level)
			periodic_channels[i] = channel
		lane["periodic_channels"] = periodic_channels

		var swarm_state := str(lane.get("swarm_state", "idle"))
		var swarm_path: Array = lane.get("swarm_path", [])
		var channel_contact_map: Dictionary = lane.get("channel_contact_map", {})
		var swarm_units: Array = lane.get("swarm_units", [])
		if swarm_state == "advancing":
			var wash_triggered := false
			var wash_channel_index := -1
			var all_lured := not swarm_units.is_empty()
			for i in range(swarm_units.size()):
				var unit: Dictionary = swarm_units[i]
				var node = unit.get("node")
				if not is_instance_valid(node):
					swarm_units[i] = unit
					continue
				if current_tick < float(lane.get("swarm_start_tick", -1.0)) + float(unit.get("delay", 0.0)):
					all_lured = false
					swarm_units[i] = unit
					continue
				if str(unit.get("state", "")) == "washed":
					swarm_units[i] = unit
					continue
				var path_index := int(unit.get("path_index", 0))
				if path_index >= swarm_path.size():
					unit["state"] = "lured"
					swarm_units[i] = unit
					continue
				all_lured = false
				var target: Vector3 = swarm_path[path_index]
				node.position = node.position.move_toward(target, delta * spd * CHANNELS_WINDOW_SWARM_SPEED)
				if node.position.distance_to(target) <= 0.08:
					if channel_contact_map.has(path_index):
						var candidate_channel_index := int(channel_contact_map[path_index])
						if candidate_channel_index >= 0 and candidate_channel_index < periodic_channels.size():
							var contact_channel: Dictionary = periodic_channels[candidate_channel_index]
							if bool(contact_channel.get("flooded", false)):
								wash_triggered = true
								wash_channel_index = candidate_channel_index
					unit["path_index"] = path_index + 1
					if int(unit.get("path_index", 0)) >= swarm_path.size():
						unit["state"] = "lured"
				swarm_units[i] = unit
				if wash_triggered:
					break
			lane["swarm_units"] = swarm_units
			if wash_triggered:
				lane = _trigger_channels_window_swarm_wash(window_id, lane, wash_channel_index, current_tick)
				periodic_channels = lane.get("periodic_channels", periodic_channels)
				swarm_units = lane.get("swarm_units", swarm_units)
			elif all_lured:
				lane["swarm_state"] = "escaped"
		elif swarm_state == "washing":
			var washed_count := 0
			for i in range(swarm_units.size()):
				var unit: Dictionary = swarm_units[i]
				var node = unit.get("node")
				if not is_instance_valid(node):
					swarm_units[i] = unit
					continue
				if str(unit.get("state", "")) == "washed":
					washed_count += 1
					swarm_units[i] = unit
					continue
				var wash_vector: Vector3 = unit.get("wash_vector", Vector3.ZERO)
				node.position += wash_vector * delta * spd
				node.position.y -= delta * spd * 1.6
				node.scale = node.scale.move_toward(Vector3.ONE * 0.28, delta * spd * 1.2)
				if current_tick - float(lane.get("swarm_start_tick", current_tick)) >= 1.1 + float(unit.get("delay", 0.0)) * 0.5:
					node.visible = false
					unit["state"] = "washed"
					washed_count += 1
				swarm_units[i] = unit
			lane["swarm_units"] = swarm_units
			if washed_count >= swarm_units.size() and not swarm_units.is_empty():
				lane["swarm_state"] = "washed"

		var curtain_nodes: Array = lane.get("curtain_nodes", [])
		var curtain_pos: Vector3 = lane.get("curtain_pos", Vector3.ZERO)
		var attract_pos: Vector3 = lane.get("attract_pos", curtain_pos)
		var lure_active: bool = bool(lane.get("lure_active", false))
		for i in range(curtain_nodes.size()):
			var node = curtain_nodes[i]
			if not is_instance_valid(node):
				continue
			var base_target := curtain_pos + Vector3(0, 0, CHANNELS_WINDOW_CURTAIN_OFFSETS[i])
			var active_target := attract_pos + Vector3(0.35 * CHANNELS_WINDOW_CURTAIN_OFFSETS[i], 0.0, 0.7 * CHANNELS_WINDOW_CURTAIN_OFFSETS[i])
			var target: Vector3 = active_target if lure_active else base_target
			node.position = node.position.move_toward(target, delta * spd * 6.0)

		if _channels_active_window_lane != window_id:
			_channels_window_lanes[window_id] = lane
			continue
		if _current_step != _channels_window_step_name(window_id, "cross"):
			_channels_window_lanes[window_id] = lane
			continue

		var goal_pos: Vector3 = lane.get("goal_pos", Vector3.ZERO)
		var curtain_anchor: Vector3 = lane.get("curtain_pos", Vector3.ZERO)
		if _player.global_position.distance_to(goal_pos) <= 2.6:
			_complete_channels_window_lane(window_id)
			return
		if float(lane.get("safe_until_tick", -1.0)) >= 0.0 and _scheduler.get_current_tick() >= float(lane.get("safe_until_tick", -1.0)):
			_fail_channels_window_lane(window_id, "window_closed")
			return
		if not bool(lane.get("lure_active", false)) and _player.global_position.distance_to(curtain_anchor) <= CHANNELS_WINDOW_DETECT_RADIUS:
			_fail_channels_window_lane(window_id, "blocked_lane")
			return
		_channels_window_lanes[window_id] = lane

func _reset_channels_encounter_nodes() -> void:
	_clear_markers()
	_set_channels_run_lure_active(false)
	_channels_run_lure_expire_tick = -1.0
	_channels_party_hidden = false
	_channels_encounter_resetting = false
	if is_instance_valid(_channels_run_lure_interactable):
		_channels_run_lure_interactable.reset()
		_channels_run_lure_interactable.show_tutorial_label()
	for i in range(_channels_swarm_units.size()):
		var unit := _channels_swarm_units[i]
		unit["x"] = CHANNELS_SWARM_CLUSTER_X + CHANNELS_SWARM_OFFSETS[i]
		unit["target_x"] = unit["x"]
		if unit["node"]:
			unit["node"].position.x = unit["x"]
		_channels_swarm_units[i] = unit

func _begin_channels_encounter() -> void:
	if not _enter_step("channels_encounter_activate"):
		return
	_select_character("endo")
	_reset_channels_encounter_nodes()
	_show_marker(CHANNELS_RUN_LURE_POS + Vector3(0, 2.0, 0), "LURE", Color(0.75, 0.45, 0.2, 0.8))
	_show_marker(CHANNELS_HIDE_SPOT_POS + Vector3(0, 2.0, 0), "HIDE", Color(0.35, 0.75, 0.55, 0.8))
	_show_marker(CHANNELS_SHELTER_POS + Vector3(0, 2.0, 0), "SHELTER", Color(0.8, 0.72, 0.45, 0.85))
	_tutorial_prompt.show_prompt("Move Endo to the lure and hold position")
	_player.set_move_enabled(true)

func _on_channels_run_lure_activated() -> void:
	if _channels_run_lure_active or _current_step not in ["channels_encounter_activate", "channels_encounter_hide"]:
		return
	_set_channels_run_lure_active(true)
	_channels_run_lure_expire_tick = _scheduler.get_current_tick() + CHANNELS_RUN_LURE_DURATION
	_enter_step("channels_encounter_hide")
	if _channels_run_lure_interactable:
		_channels_run_lure_interactable.hide_tutorial_label()
	_tutorial_prompt.show_prompt("Hide until the swarm commits")
	_scheduler.cancel_tag("channels_run_lure_expire")
	_scheduler.schedule_after(CHANNELS_RUN_LURE_DURATION, _on_channels_run_lure_expired, "channels_run_lure_expire")

func _on_channels_run_lure_expired() -> void:
	if _current_step not in ["channels_encounter_hide", "channels_encounter_run"]:
		return
	_set_channels_run_lure_active(false)
	_channels_run_lure_expire_tick = -1.0
	if _channels_party_hidden:
		_enter_step("channels_encounter_run")
		_tutorial_prompt.show_prompt("Run for shelter")
	else:
		_fail_channels_encounter("lure_expired_exposed")

func _fail_channels_encounter(reason: String) -> void:
	if _channels_encounter_resetting or _current_step not in ["channels_encounter_activate", "channels_encounter_hide", "channels_encounter_run"]:
		return
	_channels_encounter_resetting = true
	_player.set_move_enabled(false)
	for cid in ["aster", "peris", "endo"]:
		if _game_state.characters.has(cid):
			_game_state.command_stop(cid)
	_tutorial_prompt.show_prompt("The swarm catches the movement. Try again.")
	_clear_markers()
	_show_marker(CHANNELS_HIDE_SPOT_POS + Vector3(0, 2.0, 0), "CAUGHT", Color(0.85, 0.28, 0.22, 0.85))
	_scheduler.schedule_after(1.0, func():
		_restart_channels_encounter(reason)
	, "channels_encounter_retry")

func _restart_channels_encounter(_reason: String) -> void:
	if not _enter_step("channels_encounter_reset"):
		return
	_move_party_and_continue({
		"aster": CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(-2.4, 0.0, 0.4),
		"peris": CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(-1.4, 0.0, 1.2),
		"endo": CHANNELS_ENCOUNTER_ENTRY_POS,
	}, func():
		_begin_channels_encounter()
	, "channels_encounter_reset_move")

func _complete_channels_encounter() -> void:
	if _current_step == "channels_shelter":
		return
	_player.set_move_enabled(false)
	for cid in ["aster", "peris", "endo"]:
		if _game_state.characters.has(cid):
			_game_state.command_stop(cid)
	_clear_markers()
	_tutorial_prompt.hide_prompt()
	_scheduler.cancel_tag("channels_run_lure_expire")
	_start_channels_shelter()

func _update_channels_encounter(delta: float, spd: float) -> void:
	if _current_step not in ["channels_encounter_activate", "channels_encounter_hide", "channels_encounter_run"]:
		return
	var target_x := CHANNELS_SWARM_CLUSTER_X
	if _channels_run_lure_active:
		target_x = CHANNELS_RUN_LURE_POS.x
	for i in range(_channels_swarm_units.size()):
		var unit := _channels_swarm_units[i]
		unit["target_x"] = target_x + CHANNELS_SWARM_OFFSETS[i]
		var dx: float = unit["target_x"] - unit["x"]
		unit["x"] += signf(dx) * minf(absf(dx), CHANNELS_SWARM_SPEED * delta * spd)
		if unit["node"]:
			unit["node"].position.x = unit["x"]
		_channels_swarm_units[i] = unit

	var hide_reached: bool = _player.global_position.distance_to(CHANNELS_HIDE_SPOT_POS) <= 2.3
	if hide_reached != _channels_party_hidden:
		_channels_party_hidden = hide_reached
		if _channels_party_hidden and _current_step == "channels_encounter_hide":
			_tutorial_prompt.show_prompt("Wait for the lure to burn out")

	if _current_step == "channels_encounter_run" and _player.global_position.distance_to(CHANNELS_SHELTER_POS) <= 3.0:
		_complete_channels_encounter()
		return

	if _channels_party_hidden:
		return

	var visible_x: float = _player.global_position.x
	for unit in _channels_swarm_units:
		if absf(unit["x"] - visible_x) <= CHANNELS_SWARM_DETECT_RADIUS:
			_fail_channels_encounter("detected")
			return

func _start_channels_enter() -> void:
	if _fade_rect != null:
		_fade_rect.color.a = 0.0
	if not _enter_step("channels_enter"):
		return
	_focus_aster_view()
	_player.set_move_enabled(true)
	_dialogue_chain([
		"channels.narration.enter",
		"channels.aster.fluid",
		"channels.peris.sound",
	], func(): _scheduler.schedule_after(0.5, func():
		_start_channels_field_operation("intake")
	, "channels_intake_survey"))

func _start_channels_to_memory() -> void:
	if not _enter_step("channels_to_memory"):
		return
	_focus_aster_view()
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

func _start_channels_memory() -> void:
	if not _enter_step("channels_memory"):
		return
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	_game_state.command_stop("aster")
	_focus_peris_view()
	_move_party_and_continue({
		"peris": CHANNELS_BODY_POS + Vector3(-1.0, 0.0, 1.1),
		"aster": CHANNELS_BODY_POS + Vector3(-3.0, 0.0, 0.4),
		"endo": CHANNELS_BODY_POS + Vector3(-4.2, 0.0, -0.8),
	}, func():
		_dialogue_chain([
			"channels.narration.memory",
			"channels.peris.know_place",
			"channels.aster.not_here",
			"channels.peris.saw_it",
			"channels.narration.leads",
		], func(): _scheduler.schedule_after(0.5, func():
			_start_channels_field_operation("memory")
		, "channels_memory_reconstruction"))
	, "channels_memory_move")

func _start_channels_to_flure() -> void:
	if not _enter_step("channels_to_flure"):
		return
	_focus_aster_view()
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

func _start_channels_window_intro(window_id: String) -> void:
	var intro_step := _channels_window_step_name(window_id, "intro")
	if not _enter_step(intro_step):
		return
	_select_character("aster")
	_focus_aster_view()
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	for cid in ["aster", "peris", "endo"]:
		if _game_state.characters.has(cid):
			_game_state.command_stop(cid)

	var dialogue_keys: Array = []
	match window_id:
		"window_one":
			dialogue_keys = [
				"channels.narration.window_one",
				"channels.endo.window_one",
			]
		"window_two":
			dialogue_keys = [
				"channels.narration.window_two",
				"channels.peris.window_two",
			]
		_:
			return

	_move_party_and_continue(_get_channels_window_party_positions(window_id), func():
		_dialogue_chain(dialogue_keys, func():
			_scheduler.schedule_after(0.35, func():
				_begin_channels_window_lane(window_id)
			, "channels_%s_begin" % window_id)
		)
	, "channels_%s_intro_move" % window_id)

func _start_channels_corpse() -> void:
	if not _enter_step("channels_corpse"):
		return
	_focus_aster_view()
	_dialogue_chain([
		"channels.narration.body",
		"channels.endo.kneel",
		"channels.aster.report",
		"channels.peris.smell",
		"channels.peris.clients",
		"channels.aster.lysate",
		"channels.peris.people",
		"channels.aster.hungry",
		"channels.aster.downgrade",
	], func():
		_scheduler.schedule_after(0.5, func():
			_start_channels_field_operation("harvest")
		, "channels_harvest_recovery")
	)

func _start_channels_flure() -> void:
	if not _enter_step("channels_flure"):
		return
	_select_character("aster")
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	_game_state.command_stop("aster")
	_set_channels_flure_active(false)
	_move_party_and_continue({
		"peris": CHANNELS_FLURE_POS + Vector3(-0.8, 0.0, 0.6),
		"aster": CHANNELS_FLURE_POS + Vector3(-2.5, 0.0, -0.3),
		"endo": CHANNELS_FLURE_POS + Vector3(-3.6, 0.0, 1.2),
	}, func():
		_dialogue_chain([
			"channels.narration.flora",
			"channels.aster.lure",
			"channels.peris.signals",
			"channels.peris.pause",
		], func():
			_set_channels_flure_active(true)
			_start_channels_flure_flush()
			_dialogue_chain([
				"channels.peris.touch",
				"channels.peris.always",
			], func():
				_scheduler.schedule_after(2.0, func():
					_set_channels_flure_active(false)
					_start_channels_field_operation("signal")
				, "channels_signal_mapping")
			)
		)
	, "channels_flure_move")

func _start_channels_to_encounter() -> void:
	if not _enter_step("channels_to_encounter"):
		return
	_select_character("aster")
	_focus_aster_view()
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

func _start_channels_encounter_intro() -> void:
	if not _enter_step("channels_encounter_intro"):
		return
	_select_character("endo")
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	_move_party_and_continue({
		"aster": CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(-2.4, 0.0, 0.4),
		"peris": CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(-1.4, 0.0, 1.2),
		"endo": CHANNELS_ENCOUNTER_ENTRY_POS,
	}, func():
		_begin_channels_encounter()
	, "channels_encounter_intro_move")

func _start_channels_shelter() -> void:
	if not _enter_step("channels_shelter"):
		return
	_channels_shelter_reached = true
	_recuperate_channels_party()
	_set_channels_shortcut_unlocked(true)
	_select_character("endo")
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	_game_state.command_stop("aster")
	_game_state.command_stop("peris")
	_game_state.command_stop("endo")
	_move_party_and_continue({
		"aster": CHANNELS_SHELTER_POS + Vector3(-1.8, 0.0, -1.2),
		"peris": CHANNELS_SHELTER_POS + Vector3(-0.8, 0.0, 0.9),
		"endo": CHANNELS_SHELTER_POS + Vector3(-0.3, 0.0, -0.2),
	}, func():
		_dialogue_chain([
			"channels.narration.shelter",
			"channels.endo.door",
			"channels.narration.recuperate",
			"channels.narration.shortcut",
		], func(): _scheduler.schedule_after(0.5, _start_channels_explore, "channels_explore"))
	, "channels_shelter_move")

func _start_channels_explore() -> void:
	if not _enter_step("channels_explore"):
		return
	_select_character("aster")
	_player.set_move_enabled(true)
	_enable_channels_optional_exploration()
	_tutorial_prompt.show_prompt("Optional records remain in the branches // continue to the Stacks when ready")

# --- Stacks ---

func _clear_channels_runtime_state() -> void:
	_channels_flow_strips.clear()
	_channels_flush_swarm_units.clear()
	_channels_window_lanes.clear()
	_channels_field_sites.clear()
	_channels_field_visuals.clear()
	_channels_field_route_visuals.clear()
	_channels_field_completed.clear()
	_channels_field_operations_completed.clear()
	_channels_field_phase = ""
	_channels_field_choices.clear()
	_channels_field_attempts.clear()
	_channels_optional_findings.clear()
	_channels_field_decisions = 0
	_channels_active_window_lane = ""
	_channels_flow_power = 0.0
	_channels_flush_state = ""
	_iron_patches.clear()

func _district_operations(district: String) -> Dictionary:
	return STACKS_FIELD_OPERATIONS if district == "stacks" else RINGS_FIELD_OPERATIONS

func _district_site_specs(district: String) -> Dictionary:
	return STACKS_FIELD_SITES if district == "stacks" else RINGS_FIELD_SITES

func _district_site_nodes(district: String) -> Dictionary:
	return _stacks_field_sites if district == "stacks" else _rings_field_sites

func _district_site_visuals(district: String) -> Dictionary:
	return _stacks_field_visuals if district == "stacks" else _rings_field_visuals

func _district_route_visuals(district: String) -> Dictionary:
	return _stacks_field_routes if district == "stacks" else _rings_field_routes

func _district_completed_evidence(district: String) -> Dictionary:
	return _stacks_field_completed if district == "stacks" else _rings_field_completed

func _district_completed_operations(district: String) -> Dictionary:
	return _stacks_field_operations_completed if district == "stacks" else _rings_field_operations_completed

func _district_choices(district: String) -> Dictionary:
	return _stacks_field_choices if district == "stacks" else _rings_field_choices

func _district_effects(district: String) -> Dictionary:
	return _stacks_field_effects if district == "stacks" else _rings_field_effects

func _district_phase(district: String) -> String:
	return _stacks_field_phase if district == "stacks" else _rings_field_phase

func _set_district_phase(district: String, phase: String) -> void:
	if district == "stacks":
		_stacks_field_phase = phase
	else:
		_rings_field_phase = phase

func _increment_district_decisions(district: String) -> void:
	if district == "stacks":
		_stacks_field_decisions += 1
	else:
		_rings_field_decisions += 1

func _reset_district_fieldwork(district: String) -> void:
	_set_district_phase(district, "")
	_district_completed_evidence(district).clear()
	_district_completed_operations(district).clear()
	_district_choices(district).clear()
	_district_effects(district).clear()
	if district == "stacks":
		_stacks_field_decisions = 0
	else:
		_rings_field_decisions = 0
	for route_visual in _district_route_visuals(district).values():
		if is_instance_valid(route_visual):
			route_visual.visible = false
	for site_id_variant in _district_site_nodes(district).keys():
		var site_id := str(site_id_variant)
		var site = _district_site_nodes(district)[site_id]
		if not is_instance_valid(site):
			continue
		site.reset()
		site.set_interaction_enabled(false)
		site.hide_tutorial_label()
		var visual = _district_site_visuals(district).get(site_id)
		if is_instance_valid(visual):
			visual.visible = true

func _restore_district_fieldwork_interactables(district: String) -> void:
	for route_visual in _district_route_visuals(district).values():
		if is_instance_valid(route_visual):
			route_visual.visible = false
	for site_id in _district_site_nodes(district).keys():
		_set_district_field_site_enabled(district, str(site_id), false, true)
	var phase := _district_phase(district)
	var operations := _district_operations(district)
	if not operations.has(phase):
		return
	var route_visual = _district_route_visuals(district).get(phase)
	if is_instance_valid(route_visual):
		route_visual.visible = true
	var operation: Dictionary = operations[phase]
	var completed: Dictionary = _district_completed_evidence(district).get(phase, {})
	for evidence_id in operation.get("evidence", []):
		if not bool(completed.get(str(evidence_id), false)):
			_set_district_field_site_enabled(district, str(evidence_id), true, true)
	if _district_operation_evidence_complete(district, phase):
		var choice := str(_district_choices(district).get(phase, ""))
		var resolutions: Dictionary = operation.get("resolution_sites", {})
		if choice != "" and resolutions.has(choice):
			_set_district_field_site_enabled(district, str(resolutions[choice]), true, true)
		else:
			for choice_id in operation.get("choices", []):
				_set_district_field_site_enabled(district, str(choice_id), true, true)

func _set_district_field_site_enabled(district: String, site_id: String, enabled: bool, reset_first := false) -> void:
	var site = _district_site_nodes(district).get(site_id)
	if not is_instance_valid(site):
		return
	if reset_first:
		site.reset()
	if site.has_method("set_interaction_enabled"):
		site.set_interaction_enabled(enabled)
	if enabled:
		site.show_tutorial_label()
	else:
		site.hide_tutorial_label()

func _district_operation_evidence_complete(district: String, operation_id: String) -> bool:
	var operations := _district_operations(district)
	if not operations.has(operation_id):
		return false
	var completed: Dictionary = _district_completed_evidence(district).get(operation_id, {})
	for site_id in operations[operation_id].get("evidence", []):
		if not bool(completed.get(str(site_id), false)):
			return false
	return true

func _start_district_field_operation(district: String, operation_id: String) -> void:
	var operations := _district_operations(district)
	if not operations.has(operation_id):
		return
	var operation: Dictionary = operations[operation_id]
	if not _enter_step(str(operation.get("step", "%s_fieldwork" % district))):
		return
	_set_district_phase(district, operation_id)
	if not _district_completed_evidence(district).has(operation_id):
		_district_completed_evidence(district)[operation_id] = {}
	_district_choices(district).erase(operation_id)
	_clear_markers()
	for route_id in _district_route_visuals(district).keys():
		var route_visual = _district_route_visuals(district)[route_id]
		if is_instance_valid(route_visual):
			route_visual.visible = str(route_id) == operation_id
	for site_id_variant in _district_site_nodes(district).keys():
		var site_id := str(site_id_variant)
		var spec: Dictionary = _district_site_specs(district)[site_id]
		var enabled := str(spec.get("operation", "")) == operation_id and str(spec.get("kind", "")) == "evidence" \
			and not bool((_district_completed_evidence(district).get(operation_id, {}) as Dictionary).get(site_id, false))
		_set_district_field_site_enabled(district, site_id, enabled, true)
	var evidence: Array = operation.get("evidence", [])
	_select_character(str(_district_site_specs(district)[str(evidence[0])].get("role", "aster")))
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("%s // gather distinct specialist reads (0/%d)" % [
		str(operation.get("label", "FIELDWORK")), evidence.size(),
	])

func _on_district_field_route_requested(_target: Node, world_position: Vector3, district: String, site_id: String) -> void:
	if not _district_site_specs(district).has(site_id) or _game_state == null:
		return
	var specialist := str(_district_site_specs(district)[site_id].get("role", ""))
	var party := ["aster", "peris", "endo"] if district == "stacks" else ["aster", "peris"]
	var offsets := {
		"aster": Vector3(-1.1, 0.0, -0.8),
		"peris": Vector3(-0.9, 0.0, 0.9),
		"endo": Vector3(1.0, 0.0, -0.6),
	}
	for char_id in party:
		if char_id == specialist or not _game_state.characters.has(char_id):
			continue
		_game_state.command_move_to_pos(char_id, world_position + offsets[char_id])

func _on_district_field_site_interacted(district: String, site_id: String) -> void:
	var operations := _district_operations(district)
	var specs := _district_site_specs(district)
	if not specs.has(site_id):
		return
	var spec: Dictionary = specs[site_id]
	var operation_id := str(spec.get("operation", ""))
	if operation_id != _district_phase(district) or not operations.has(operation_id):
		return
	var site = _district_site_nodes(district).get(site_id)
	if not is_instance_valid(site) or not site.is_interaction_enabled():
		return
	var operation: Dictionary = operations[operation_id]
	var kind := str(spec.get("kind", "evidence"))
	if kind == "evidence":
		var completed: Dictionary = _district_completed_evidence(district).get(operation_id, {})
		if bool(completed.get(site_id, false)):
			return
		completed[site_id] = true
		_district_completed_evidence(district)[operation_id] = completed
		_set_district_field_site_enabled(district, site_id, false)
		_show_overlay_note(str(spec.get("finding", "Evidence recorded.")), 4.2)
		if _district_operation_evidence_complete(district, operation_id):
			for choice_id_variant in operation.get("choices", []):
				var choice_id := str(choice_id_variant)
				_set_district_field_site_enabled(district, choice_id, true, true)
				var choice_spec: Dictionary = specs[choice_id]
				_show_marker(choice_spec.get("pos", Vector3.ZERO) + Vector3(0, 2.2, 0), str(choice_spec.get("display", "PLAN")), operation.get("tint", Color.WHITE))
			_tutorial_prompt.show_prompt("Evidence complete // commit one marked plan")
		else:
			_tutorial_prompt.show_prompt("%s // reads %d/%d" % [
				str(operation.get("label", "FIELDWORK")), completed.size(), operation.get("evidence", []).size(),
			])
		return
	if kind == "choice":
		if not _district_operation_evidence_complete(district, operation_id):
			site.reset()
			return
		_district_choices(district)[operation_id] = site_id
		_increment_district_decisions(district)
		_show_overlay_note(str(spec.get("finding", "Plan committed.")), 4.5)
		for operation_site_id in operation.get("evidence", []):
			_set_district_field_site_enabled(district, str(operation_site_id), false)
		for operation_site_id in operation.get("choices", []):
			_set_district_field_site_enabled(district, str(operation_site_id), false)
		var resolution_id := str((operation.get("resolution_sites", {}) as Dictionary).get(site_id, ""))
		if resolution_id != "":
			_set_district_field_site_enabled(district, resolution_id, true, true)
			var resolution_spec: Dictionary = specs[resolution_id]
			_clear_markers()
			_show_marker(resolution_spec.get("pos", Vector3.ZERO) + Vector3(0, 2.2, 0), str(resolution_spec.get("display", "EXECUTE")), operation.get("tint", Color.WHITE))
			_tutorial_prompt.show_prompt("Plan committed // execute it at the marked station")
		return
	if kind != "resolution":
		return
	var committed_choice := str(_district_choices(district).get(operation_id, ""))
	var expected_resolution := str((operation.get("resolution_sites", {}) as Dictionary).get(committed_choice, ""))
	if site_id != expected_resolution:
		site.reset()
		return
	_set_district_field_site_enabled(district, site_id, false)
	_district_completed_operations(district)[operation_id] = true
	_apply_district_field_choice(district, operation_id, committed_choice)
	_show_overlay_note(str(spec.get("finding", "Plan executed.")), 4.5)
	_clear_markers()
	var next_operation := str(operation.get("next", ""))
	if next_operation != "":
		_start_district_field_operation(district, next_operation)
		return
	_set_district_phase(district, "complete")
	for route_visual in _district_route_visuals(district).values():
		if is_instance_valid(route_visual):
			route_visual.visible = false
	if district == "stacks":
		_start_stacks_explore()
	else:
		_start_rings_explore()

func _apply_district_field_choice(district: String, operation_id: String, choice_id: String) -> void:
	var effects := _district_effects(district)
	match choice_id:
		"identity_people":
			effects["archive_mode"] = "worker_context"
			_game_state.adjust_stat("peris", "stamina", 6.0)
		"identity_route":
			effects["archive_mode"] = "ghost_route"
			_game_state.adjust_stat("aster", "atp", 1.0)
		"egress_quiet":
			effects["egress_mode"] = "quiet_brace"
			_game_state.adjust_stat("endo", "stamina", -5.0)
		"egress_broadcast":
			effects["egress_mode"] = "authenticated_burst"
			_game_state.adjust_stat("aster", "atp", -1.0)
		"residence_knock":
			effects["contact_mode"] = "consensual_contact"
			_game_state.adjust_stat("peris", "stamina", 5.0)
		"residence_marker":
			effects["contact_mode"] = "privacy_marker"
			_game_state.adjust_stat("aster", "atp", 1.0)
		"boundary_keep_watch":
			effects["handoff_mode"] = "local_watch"
			_game_state.adjust_stat("peris", "stamina", -4.0)
		"boundary_share_map":
			effects["handoff_mode"] = "anonymized_map"
			_game_state.adjust_stat("aster", "atp", -1.0)
	effects["last_operation"] = operation_id

func _district_shortest_operation_route(district: String, operation_id: String) -> float:
	var operations := _district_operations(district)
	var specs := _district_site_specs(district)
	if not operations.has(operation_id):
		return 0.0
	var operation: Dictionary = operations[operation_id]
	var evidence_positions: Array[Vector3] = []
	for site_id in operation.get("evidence", []):
		evidence_positions.append(specs[str(site_id)].get("pos", Vector3.ZERO))
	var best := INF
	for choice_id_variant in operation.get("choices", []):
		var choice_id := str(choice_id_variant)
		var choice_pos: Vector3 = specs[choice_id].get("pos", Vector3.ZERO)
		var resolution_id := str((operation.get("resolution_sites", {}) as Dictionary).get(choice_id, ""))
		var resolution_pos: Vector3 = specs[resolution_id].get("pos", Vector3.ZERO)
		var evidence_route := _district_shortest_path_through(
			operation.get("start", Vector3.ZERO), evidence_positions,
			(1 << evidence_positions.size()) - 1, choice_pos
		)
		var branch_tail := choice_pos.distance_to(resolution_pos) + resolution_pos.distance_to(operation.get("end", Vector3.ZERO))
		best = minf(best, evidence_route + branch_tail)
	return 0.0 if is_inf(best) else best

func _district_shortest_path_through(current: Vector3, points: Array[Vector3], remaining_mask: int, tail: Vector3) -> float:
	if remaining_mask == 0:
		return current.distance_to(tail)
	var best := INF
	for point_i in range(points.size()):
		var bit := 1 << point_i
		if (remaining_mask & bit) == 0:
			continue
		best = minf(best, current.distance_to(points[point_i]) + _district_shortest_path_through(
			points[point_i], points, remaining_mask & ~bit, tail
		))
	return best

func _district_field_route_and_work(district: String) -> Dictionary:
	var route_by_operation := {}
	var route_meters := 0.0
	var work_seconds := 0.0
	var operations := _district_operations(district)
	var specs := _district_site_specs(district)
	for operation_id_variant in operations.keys():
		var operation_id := str(operation_id_variant)
		var operation: Dictionary = operations[operation_id]
		var route := _district_shortest_operation_route(district, operation_id)
		route_by_operation[operation_id] = route
		route_meters += route
		for evidence_id in operation.get("evidence", []):
			work_seconds += float(specs[str(evidence_id)].get("dwell", 0.0))
		var shortest_branch_work := INF
		for choice_id_variant in operation.get("choices", []):
			var choice_id := str(choice_id_variant)
			var resolution_id := str((operation.get("resolution_sites", {}) as Dictionary).get(choice_id, ""))
			shortest_branch_work = minf(shortest_branch_work,
				float(specs[choice_id].get("dwell", 0.0)) + float(specs[resolution_id].get("dwell", 0.0)))
		work_seconds += 0.0 if is_inf(shortest_branch_work) else shortest_branch_work
	return {
		"route_meters": route_meters,
		"route_by_operation": route_by_operation,
		"work_seconds": work_seconds,
	}

func get_stacks_playtime_contract() -> Dictionary:
	var field := _district_field_route_and_work("stacks")
	var banks: Array[Vector3] = [
		STACKS_BANK_POSITIONS["bank_a"], STACKS_BANK_POSITIONS["bank_b"], STACKS_BANK_POSITIONS["bank_c"],
	]
	var bank_route := _district_shortest_path_through(
		STACKS_SIGNAL_POS, banks, (1 << banks.size()) - 1, STACKS_BANK_POSITIONS[STACKS_GHOST_BANK]
	)
	var legacy_route_meters := STACKS_LEGACY_START_POS.distance_to(STACKS_TERMINAL_POS) \
		+ STACKS_TERMINAL_POS.distance_to(STACKS_SIGNAL_POS) \
		+ bank_route + STACKS_BANK_POSITIONS[STACKS_GHOST_BANK].distance_to(STACKS_WORKSPACE_POS)
	var traversal_seconds := legacy_route_meters / 3.0 + float(field.get("route_meters", 0.0)) / DISTRICT_FIELD_ROUTE_SPEED
	var interaction_seconds := 1.3 + 1.3 + 3.0 * 1.2 + 1.3 + float(field.get("work_seconds", 0.0))
	var planning_seconds := 48.0
	var active_seconds := traversal_seconds + interaction_seconds + planning_seconds
	var presentation_seconds := 54.0
	var total_seconds := active_seconds + presentation_seconds
	var mode_segments := {
		"entry_to_terminal_traversal": STACKS_LEGACY_START_POS.distance_to(STACKS_TERMINAL_POS) / 3.0,
		"longest_dialogue_exchange": 42.0,
		"field_evidence_work": 5.4,
		"operation_synthesis": 20.0,
	}
	return {
		"target_id": "stacks",
		"meaningful_active_seconds": active_seconds,
		"total_play_seconds": total_seconds,
		"max_dead_gap_seconds": 4.6,
		"max_single_mode_seconds": 42.0,
		"decision_count": 3,
		"branch_count": 4,
		"category_seconds": {
			"exploration_and_traversal": traversal_seconds,
			"planning_and_decisions": planning_seconds,
			"interaction_and_execution": interaction_seconds,
		},
		"legacy_route_meters": legacy_route_meters,
		"field_route_meters": field.get("route_meters", 0.0),
		"route_meters_by_operation": field.get("route_by_operation", {}),
		"field_work_seconds": field.get("work_seconds", 0.0),
		"presentation_seconds": presentation_seconds,
		"mandatory_field_evidence_count": 12,
		"mandatory_field_action_count": 16,
		"operation_count": 2,
		"mode_segments": mode_segments,
		"timing_basis": "exact shortest geometry through the terminal, signal, all audit banks, workspace, two field operations, and shortest valid executions; authored dwell plus explicit evidence-synthesis time; dialogue presentation is inactive and cannot satisfy the active floor",
	}

func get_rings_playtime_contract() -> Dictionary:
	var field := _district_field_route_and_work("rings")
	var legacy_route_meters := RINGS_LEGACY_START_POS.distance_to(RINGS_CLIENT_POS) \
		+ RINGS_CLIENT_POS.distance_to(RINGS_TRACE_POSITIONS["client_bloom"]) \
		+ RINGS_TRACE_POSITIONS["client_bloom"].distance_to(RINGS_TRACE_POSITIONS["forget_me_not"]) \
		+ RINGS_TRACE_POSITIONS["forget_me_not"].distance_to(RINGS_TRACE_POSITIONS["doorvine"])
	var traversal_seconds := legacy_route_meters / 2.5 + float(field.get("route_meters", 0.0)) / DISTRICT_FIELD_ROUTE_SPEED
	var interaction_seconds := 1.0 + 3.0 * 1.4 + float(field.get("work_seconds", 0.0))
	var planning_seconds := 48.0
	var active_seconds := traversal_seconds + interaction_seconds + planning_seconds
	var presentation_seconds := 62.0
	var total_seconds := active_seconds + presentation_seconds
	var mode_segments := {
		"entry_to_client_traversal": RINGS_LEGACY_START_POS.distance_to(RINGS_CLIENT_POS) / 2.5,
		"longest_dialogue_exchange": 44.0,
		"field_evidence_work": 5.4,
		"operation_synthesis": 22.0,
	}
	return {
		"target_id": "rings",
		"meaningful_active_seconds": active_seconds,
		"total_play_seconds": total_seconds,
		"max_dead_gap_seconds": 4.8,
		"max_single_mode_seconds": 44.0,
		"decision_count": 2,
		"branch_count": 4,
		"category_seconds": {
			"exploration_and_traversal": traversal_seconds,
			"planning_and_decisions": planning_seconds,
			"interaction_and_execution": interaction_seconds,
		},
		"legacy_route_meters": legacy_route_meters,
		"field_route_meters": field.get("route_meters", 0.0),
		"route_meters_by_operation": field.get("route_by_operation", {}),
		"field_work_seconds": field.get("work_seconds", 0.0),
		"presentation_seconds": presentation_seconds,
		"mandatory_field_evidence_count": 12,
		"mandatory_field_action_count": 16,
		"operation_count": 2,
		"mode_segments": mode_segments,
		"timing_basis": "exact shortest geometry through the former client, three ordered residential traces, two field operations, and shortest valid executions; authored dwell plus explicit evidence-synthesis time; dialogue presentation is inactive and cannot satisfy the active floor",
	}

func _reset_stacks_runtime_state() -> void:
	_stacks_support_log_entry_id = -1
	_stacks_support_log_presented = false
	_stacks_signal_interacted = false
	_stacks_terminal_interacted = false
	_stacks_archive_interacted = false
	_stacks_audit_flags_found = false
	_stacks_bank_samples.clear()
	_stacks_bank_resolved = false
	_stacks_bank_attempts = 0
	if is_instance_valid(_stacks_signal_interactable):
		_stacks_signal_interactable.reset()
		_stacks_signal_interactable.hide_tutorial_label()
	if is_instance_valid(_stacks_terminal_interactable):
		_stacks_terminal_interactable.reset()
		_stacks_terminal_interactable.hide_tutorial_label()
	if is_instance_valid(_stacks_workspace_interactable):
		_stacks_workspace_interactable.reset()
		_stacks_workspace_interactable.hide_tutorial_label()
	for interactable in _stacks_bank_interactables.values():
		if is_instance_valid(interactable):
			interactable.reset()
			interactable.set_interaction_enabled(true)
			interactable.hide_tutorial_label()
	_reset_district_fieldwork("stacks")

func _ensure_stacks_support_log_entry() -> Dictionary:
	var journal: Node = get_node_or_null("/root/EngramJournal")
	if journal == null:
		return {}
	var context := {
		"scene_path": scene_file_path,
		"scene_name": "Act 1",
		"act": 1,
		"day": 1,
		"time_of_day": "maintenance_shift",
		"timestamp_label": "147 cycles ago",
		"location": "The Open Files Initiative",
		"sub_location": "Support Team Thread",
		"trigger_type": "story",
		"trigger_context": "support_team_log",
		"position": Vector3(STACKS_START.x + 88.0, 0.5, 0.0),
		"caption": "Maintenance thread surfaced from the old support logs",
	}
	var title := DialogueData.text("stacks.engram.support_log.title")
	var body := DialogueData.text("stacks.engram.support_log.body")
	return journal.ensure_story_log_entry(
		STACKS_SUPPORT_LOG_KEY,
		title,
		body,
		context,
		{
			"caption": "Support team maintenance log",
			"trigger_context": "support_team_log",
			"attached_data": {
				"channel": "#ependyma-core",
			},
		}
	)

func trigger_stacks_support_log() -> void:
	_present_stacks_support_log()

func close_stacks_engram_overlay() -> void:
	if _engram_overlay != null and _engram_overlay.visible:
		_engram_overlay.close_overlay()

func _present_stacks_support_log() -> void:
	var entry := _ensure_stacks_support_log_entry()
	_stacks_support_log_presented = not entry.is_empty()
	_stacks_support_log_entry_id = int(entry.get("id", -1))
	if _engram_overlay == null:
		_scheduler.schedule_after(0.1, _start_stacks_terminal, "terminal")
		return
	if not _engram_overlay.overlay_closed.is_connected(_on_stacks_support_log_closed):
		_engram_overlay.overlay_closed.connect(_on_stacks_support_log_closed, CONNECT_ONE_SHOT)
	_engram_overlay.open_overlay_for_entry(_stacks_support_log_entry_id)
	show_capture_message("Engram surfaced a maintenance log. J or Esc closes it.")

func _on_stacks_support_log_closed() -> void:
	if _current_step == "stacks_enter":
		_scheduler.schedule_after(0.1, _start_stacks_terminal, "terminal")

func _start_stacks_enter() -> void:
	_enter_step("stacks_enter")
	_tutorial_prompt.hide_prompt()
	_load_chunk("stacks")
	_unload_chunk("channels")
	_activate_chunk_grid("stacks")  # swap the live grid to the stacks footprint
	_clear_channels_runtime_state()
	_reset_stacks_runtime_state()
	_select_character("aster")
	_player.set_move_enabled(false)
	_dialogue_chain([
		"stacks.narration.enter",
		"stacks.aster.cores",
		"stacks.peris.noisy",
		"stacks.narration.network_address",
		"stacks.aster.know_number",
	], func(): _present_stacks_support_log())

func _start_stacks_terminal() -> void:
	if not _enter_step("stacks_terminal"):
		return
	_select_character("aster")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Move Aster to the terminal")
	if is_instance_valid(_stacks_terminal_interactable):
		_stacks_terminal_interactable.reset()
		_stacks_terminal_interactable.show_tutorial_label()

func _start_stacks_signal() -> void:
	if not _enter_step("stacks_signal"):
		return
	_select_character("aster")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Move Aster to the custom sensor wall")
	if is_instance_valid(_stacks_signal_interactable):
		_stacks_signal_interactable.reset()
		_stacks_signal_interactable.show_tutorial_label()

func trigger_stacks_terminal(play_dialogue := false) -> void:
	if _current_step != "stacks_terminal" or _stacks_terminal_interacted:
		return
	_stacks_terminal_interacted = true
	_tutorial_prompt.hide_prompt()
	if is_instance_valid(_stacks_terminal_interactable):
		_stacks_terminal_interactable.hide_tutorial_label()
	if not play_dialogue:
		_start_stacks_signal()
		return
	_player.set_move_enabled(false)
	_dialogue_chain([
		"stacks.aster.support_team",
		"stacks.aster.drink_machine",
		"stacks.peris.priorities",
		"stacks.narration.cleaned_terminal",
		"stacks.aster.cleaner_than_place",
		"stacks.aster.simplodrink",
		"stacks.peris.miss_machine",
		"stacks.aster.expectation",
	], func(): _scheduler.schedule_after(0.2, _start_stacks_signal, "signal"))

func trigger_stacks_signal(play_dialogue := false) -> void:
	if _current_step != "stacks_signal" or _stacks_signal_interacted:
		return
	_stacks_signal_interacted = true
	_tutorial_prompt.hide_prompt()
	if is_instance_valid(_stacks_signal_interactable):
		_stacks_signal_interactable.hide_tutorial_label()
	if not play_dialogue:
		_start_stacks_archive()
		return
	_player.set_move_enabled(false)
	_dialogue_chain([
		"stacks.narration.instrumented_lane",
		"stacks.aster.nonstandard",
		"stacks.aster.metrics",
		"stacks.peris.damn_cooler",
		"stacks.aster.cooling_part",
		"stacks.peris.meaning",
		"stacks.aster.standardization",
	], func(): _scheduler.schedule_after(0.2, _start_stacks_bank_audit, "bank_audit"))

func _start_stacks_bank_audit() -> void:
	if not _enter_step("stacks_bank_audit"):
		return
	_select_character("aster")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Use Aster's data view to sample all three banks, then commit the ghost-ID rack")
	for interactable in _stacks_bank_interactables.values():
		if is_instance_valid(interactable):
			interactable.reset()
			interactable.set_interaction_enabled(true)
			interactable.show_tutorial_label()

func trigger_stacks_bank(bank_id: String) -> void:
	if _current_step != "stacks_bank_audit" or _stacks_bank_resolved:
		return
	_stacks_bank_attempts += 1
	var interactable = _stacks_bank_interactables.get(bank_id)
	_stacks_bank_samples[bank_id] = true
	if _stacks_bank_samples.size() < _stacks_bank_interactables.size():
		show_preview_note(
			"Bank sample captured (%d/%d). A comparison needs the remaining feed%s." % [
				_stacks_bank_samples.size(),
				_stacks_bank_interactables.size(),
				"s" if _stacks_bank_interactables.size() - _stacks_bank_samples.size() != 1 else "",
			],
			3.0
		)
		_tutorial_prompt.show_prompt(
			"Compare data banks (%d/%d sampled)" % [
				_stacks_bank_samples.size(),
				_stacks_bank_interactables.size(),
			]
		)
		if is_instance_valid(interactable):
			interactable.reset()
		return
	if bank_id != STACKS_GHOST_BANK:
		show_preview_note(
			"Comparison complete: the ghost IDs ride BANK B's unsigned lane. Return there to commit it.",
			3.2
		)
		_tutorial_prompt.show_prompt("Return to BANK B // UNSIGNED and commit the ghost-ID trace")
		if is_instance_valid(interactable):
			interactable.reset()
		return
	_stacks_bank_resolved = true
	_tutorial_prompt.hide_prompt()
	show_preview_note("Ghost-ID cadence matched. The hidden route resolves toward the support workspace.", 3.4)
	for candidate in _stacks_bank_interactables.values():
		if is_instance_valid(candidate):
			candidate.hide_tutorial_label()
			candidate.set_interaction_enabled(false)
	_scheduler.schedule_after(0.2, _start_stacks_archive, "archive")

func _start_stacks_archive() -> void:
	if not _enter_step("stacks_archive"):
		return
	_select_character("aster")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Move Aster to the tuned workspace")
	if is_instance_valid(_stacks_workspace_interactable):
		_stacks_workspace_interactable.reset()
		_stacks_workspace_interactable.show_tutorial_label()

func trigger_stacks_archive(play_dialogue := false) -> void:
	if _current_step != "stacks_archive" or _stacks_archive_interacted:
		return
	_stacks_archive_interacted = true
	_stacks_audit_flags_found = true
	_tutorial_prompt.hide_prompt()
	if is_instance_valid(_stacks_workspace_interactable):
		_stacks_workspace_interactable.hide_tutorial_label()
	if not play_dialogue:
		_start_district_field_operation("stacks", "identity")
		return
	_player.set_move_enabled(false)
	_dialogue_chain([
		"stacks.narration.workspace",
		"stacks.aster.pull_archive",
		"stacks.aster.ghost_ids",
		"stacks.peris.fake_permissions",
		"stacks.aster.security_patch",
		"stacks.aster.not_the_type",
		"stacks.aster.right",
	], func(): _scheduler.schedule_after(0.2, _start_district_field_operation.bind("stacks", "identity"), "stacks_fieldwork"))

func _start_stacks_explore() -> void:
	_enter_step("stacks_explore")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

# --- Rings ---

func _reset_rings_runtime_state() -> void:
	_rings_client_seen = false
	_rings_trace_seen.clear()
	if is_instance_valid(_rings_client_interactable):
		_rings_client_interactable.reset()
		_rings_client_interactable.hide_tutorial_label()
	for interactable in _rings_trace_interactables.values():
		if is_instance_valid(interactable):
			interactable.reset()
			interactable.hide_tutorial_label()
	_reset_district_fieldwork("rings")

func _start_rings_enter() -> void:
	_enter_step("rings_enter")
	_tutorial_prompt.hide_prompt()
	_load_chunk("rings")
	_unload_chunk("stacks")
	_activate_chunk_grid("rings")  # swap the live grid to the rings footprint
	_reset_rings_runtime_state()
	_select_character("peris")
	_player.set_move_enabled(false)
	_dialogue_chain([
		"ring.entry.narration",
		"ring.entry.aster.home",
		"ring.entry.aster.machine",
		"ring.entry.peris.quiet",
		"ring.entry.endo.wall_touch",
		"ring.scatter.peris.notice",
		"ring.scatter.aster.continue",
	], func(): _scheduler.schedule_after(0.2, _start_rings_client, "client"))

func _start_rings_client() -> void:
	_enter_step("rings_client")
	_select_character("peris")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Take Peris to the former client")
	if is_instance_valid(_rings_client_interactable):
		_rings_client_interactable.reset()
		_rings_client_interactable.show_tutorial_label()

func trigger_rings_client(play_dialogue := true) -> void:
	if _current_step != "rings_client" or _rings_client_seen:
		return
	_rings_client_seen = true
	_tutorial_prompt.hide_prompt()
	if is_instance_valid(_rings_client_interactable):
		_rings_client_interactable.hide_tutorial_label()
	if not play_dialogue:
		_start_endo_departs()
		return
	_player.set_move_enabled(false)
	_dialogue_chain([
		"ring.marco.entry.narration",
		"ring.marco.entry.marco.warn",
		"ring.marco.entry.peris.name",
		"ring.marco.entry.marco.correct",
		"ring.marco.warn.jeopardize",
		"ring.marco.warn.c_suite",
		"ring.marco.peris.wellness_start",
		"ring.marco.peris.silence",
		"ring.marco.peris.apology",
		"ring.marco.exit.marco.brief",
		"ring.marco.exit.narration",
		"ring.after_marco.aster.weird",
		"ring.after_marco.peris.quiet",
		"ring.after_marco.aster.move_on",
		"ring.after_marco.endo.watch",
	], func(): _scheduler.schedule_after(0.2, _start_endo_departs, "endo_departs"))

func _start_endo_departs() -> void:
	_enter_step("endo_departs")
	_dialogue_chain([
		"ring.departure.narration",
		"ring.departure.aster.question",
		"ring.departure.peris.read",
		"ring.departure.endo.turn",
		"ring.departure.aster.delayed",
		"ring.departure.peris.explain",
		"ring.departure.aster.but",
		"ring.departure.peris.look",
		"ring.departure.aster.settle",
		"ring.departure.narration.closing",
	], func():
		# Endo walks back and fades out
		_endo.visible = false
		if _game_state.characters.has("endo"):
			_game_state.command_stop("endo")
		_scheduler.schedule_after(0.2, _start_rings_trace.bind(RINGS_TRACE_ORDER[0]), "rings_trace")
	)

func _start_rings_trace(trace_id: String) -> void:
	if not RINGS_TRACE_ORDER.has(trace_id):
		_start_rings_explore()
		return
	_enter_step("rings_trace_%s" % trace_id)
	_select_character("peris")
	_player.set_move_enabled(true)
	var labels := {
		"client_bloom": "Read the client bloom",
		"forget_me_not": "Follow the trace to the forget-me-not bed",
		"doorvine": "Check the occupied doorvine",
	}
	_tutorial_prompt.show_prompt(str(labels.get(trace_id, "Follow the residential trace")))
	var interactable = _rings_trace_interactables.get(trace_id)
	if is_instance_valid(interactable):
		interactable.reset()
		interactable.show_tutorial_label()

func trigger_rings_trace(trace_id: String) -> void:
	if _current_step != "rings_trace_%s" % trace_id or bool(_rings_trace_seen.get(trace_id, false)):
		return
	_rings_trace_seen[trace_id] = true
	var interactable = _rings_trace_interactables.get(trace_id)
	if is_instance_valid(interactable):
		interactable.hide_tutorial_label()
	var notes := {
		"client_bloom": "The bloom kept listening after the client stopped answering.",
		"forget_me_not": "The domestic trace turns inward: a familiar species, deliberately tended.",
		"doorvine": "Warmth remains behind this seal. Empty streets do not mean empty homes.",
	}
	show_preview_note(str(notes.get(trace_id, "The trace resolves.")), 3.2)
	var index := RINGS_TRACE_ORDER.find(trace_id)
	if index >= 0 and index + 1 < RINGS_TRACE_ORDER.size():
		_scheduler.schedule_after(0.2, _start_rings_trace.bind(RINGS_TRACE_ORDER[index + 1]), "rings_trace")
	else:
		_scheduler.schedule_after(0.2, _start_district_field_operation.bind("rings", "residence"), "rings_fieldwork")

func _start_rings_explore() -> void:
	_enter_step("rings_explore")
	_player.set_move_enabled(true)
	_tutorial_prompt.show_prompt("Click to move")

# --- Lockout ---

func _start_lockout_approach() -> void:
	_enter_step("lockout_approach")
	_tutorial_prompt.hide_prompt()
	_clear_lockout_runtime_state()
	_lockout_chase_active = true
	_lockout_rejection_presented = false
	_lockout_dispatch_presented = false
	_lockout_chase_chunk = _load_chunk("lockout_chase_campaign")
	_unload_chunk("rings")
	_unload_chunk("stacks")
	_unload_chunk("channels")
	_activate_hosted_chunk_grid(_lockout_chase_chunk)
	if _lockout_chase_chunk != null:
		if _lockout_chase_chunk.has_method("set_pursuit_start_deferred"):
			_lockout_chase_chunk.call("set_pursuit_start_deferred", true)
		var rejection_callback := Callable(self, "_on_campaign_lockout_tags_rejected")
		if _lockout_chase_chunk.has_signal("tags_rejected") \
				and not _lockout_chase_chunk.is_connected("tags_rejected", rejection_callback):
			_lockout_chase_chunk.connect("tags_rejected", rejection_callback)
		var spawns := {}
		if _lockout_chase_chunk.has_method("get_spawn_positions"):
			spawns = _lockout_chase_chunk.call("get_spawn_positions")
		for char_id in ["aster", "peris"]:
			if spawns.has(char_id):
				set_preview_character_visible(char_id, true)
				set_preview_character_position(char_id, spawns[char_id])
	# Loading the data chunk publishes its own preview start step; restore the campaign step after
	# the host/grid/spawn hand-off, as the Endo stretch integration does.
	_current_step = "lockout_approach"
	_endo.visible = false
	_select_character("aster")
	_player.set_move_enabled(false)
	_dialogue_chain([
		"lockout.approach.narration",
		"lockout.approach.aster.confident",
	], func():
		_player.set_move_enabled(true)
		_tutorial_prompt.show_prompt("Present Aster and Peris's tags at the boundary scanner")
	)

func _on_campaign_lockout_tags_rejected() -> void:
	if not _lockout_chase_active:
		return
	_tutorial_prompt.hide_prompt()
	if _lockout_rejection_presented:
		_start_lockout_chase()
	else:
		_start_lockout_rejected()

func _start_lockout_rejected() -> void:
	_enter_step("lockout_rejected")
	_player.set_move_enabled(false)
	_lockout_rejection_presented = true
	_dialogue_chain([
		"lockout.approach.panel_reject",
		"lockout.approach.aster.glitch",
		"lockout.approach.aster.retry",
		"lockout.approach.aster.confused",
		"lockout.escalate.aster.hack",
		"lockout.escalate.hack_block",
		"lockout.escalate.aster.recog",
		"lockout.escalate.aster.try_again",
		"lockout.escalate.peris.quiet",
		"lockout.escalate.peris_approaches",
		"lockout.escalate.aster.notices",
		"lockout.escalate.peris.dont",
	], func(): _scheduler.schedule_after(0.2, _start_lockout_chase, "chase"))

func _start_lockout_chase() -> void:
	_enter_step("lockout_chase")
	if _lockout_chase_active:
		if _lockout_chase_chunk != null and _lockout_chase_chunk.has_method("begin_deferred_pursuit"):
			_lockout_chase_chunk.call("begin_deferred_pursuit")
		_player.set_move_enabled(true)
		_tutorial_prompt.show_prompt("Run east to Endo's maintained wall")
		if _lockout_dispatch_presented:
			return
		_lockout_dispatch_presented = true
		# These urgent lines ride over player-controlled movement; the pursuit scene remains sparse
		# and the story no longer turns its opening seconds into another stationary cutscene.
		_dialogue_chain([
			"lockout.dispatch.narration",
			"lockout.dispatch.aster.frozen",
			"lockout.dispatch.peris.hears",
			"lockout.dispatch.aster.pulled",
			"lockout.dispatch.peris.no",
			"lockout.dispatch.narration.start_chase",
			"lockout.chase.aster.lost",
			"lockout.chase.peris.listen",
		], func(): pass)
		return
	_dialogue_chain([
		"lockout.dispatch.narration",
		"lockout.dispatch.aster.frozen",
		"lockout.dispatch.peris.hears",
		"lockout.dispatch.aster.pulled",
		"lockout.dispatch.peris.no",
		"lockout.dispatch.narration.start_chase",
		"lockout.chase.aster.lost",
		"lockout.chase.peris.listen",
	], func():
		_player.set_move_enabled(true)
		_tutorial_prompt.show_prompt("Run!")
	)
	_spawn_lockout_naturalizers()

func _start_lockout_exile() -> void:
	if not _enter_step("lockout_exile"):
		return
	_lockout_chase_active = false
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	# Stop Naturalizers
	for i in range(_naturalizers.size()):
		if _game_state.characters.has("nk_%d" % i):
			_game_state.command_stop("nk_%d" % i)
	_dialogue_chain([
		"lockout.chase.narration.boundary",
		"lockout.standoff.narration",
		"lockout.standoff.aster.try",
		"lockout.standoff.peris.back",
		"lockout.standoff.aster.cant_answer",
		"lockout.standoff.narration.silence",
		"lockout.aftermath.aster.watch",
		"lockout.aftermath.peris.answer",
		"lockout.aftermath.aster.sit",
		"lockout.aftermath.peris.sit",
		"lockout.aftermath.peris.ask_word",
		"lockout.aftermath.aster.fugacity",
		"lockout.aftermath.aster.clarify",
		"lockout.aftermath.peris.pressure",
		"lockout.aftermath.aster.laugh",
		"lockout.aftermath.peris.soft",
		"lockout.aftermath.narration.close",
	], func(): _scheduler.schedule_after(2.0, _complete, "complete"))

func _spawn_lockout_naturalizers() -> void:
	_clear_lockout_runtime_state()
	var chars := find_child("Characters", false, false)
	if chars == null:
		return
	for i in range(3):
		var nk := _create_npc("NK-%d" % (i + 1), Color(0.7, 0.7, 0.75))
		nk.position = LOCKOUT_BOUNDARY + Vector3(-2 + i * 2, 0.5, 0)
		chars.add_child(nk)
		_register_gs_character("nk_%d" % i, nk, 1.5)
		_game_state.command_move_to_pos("nk_%d" % i, _aster_node.global_position)
		_naturalizers.append(nk)

func _clear_lockout_runtime_state() -> void:
	if _lockout_chase_chunk != null and is_instance_valid(_lockout_chase_chunk):
		_unload_chunk("lockout_chase_campaign")
	_lockout_chase_chunk = null
	_lockout_chase_active = false
	for i in range(_naturalizers.size()):
		var nk := _naturalizers[i]
		if is_instance_valid(nk):
			nk.queue_free()
		if _game_state != null:
			var nk_id := "nk_%d" % i
			if _game_state.characters.has(nk_id):
				_game_state.unregister_character(nk_id)
	_naturalizers.clear()

# --- Endo's Junction to Shelter 1 (scene chunk, its own leg) ---

## Boot the Endo stretch as its own reachable leg: load the self-contained scene chunk (its
## attach_chunk_host wires it to act1), swap to its grid, teleport the full party onto the chunk's
## own spawn anchors (so its LOCAL station-distance checks line up), play a short intro, then hand
## control to the player. The chunk's interactables fire through act1 because the host interface is
## now inherited from tutorial_sequence; reach_shelter sets route_phase == "complete".

func _start_endo_junction_stretch_enter() -> void:
	if not _enter_step("endo_junction_stretch"):
		return
	_endo_junction_active = true
	_endo_junction_chunk = _load_chunk("endo_junction_stretch")
	_unload_chunk("channels")
	_clear_channels_runtime_state()
	_activate_chunk_grid("endo_junction_stretch")

	var spawns := {}
	if _endo_junction_chunk != null and _endo_junction_chunk.has_method("get_spawn_positions"):
		spawns = _endo_junction_chunk.call("get_spawn_positions")
	for char_id in ["aster", "peris", "endo"]:
		if spawns.has(char_id):
			var node := _get_character_node(char_id)
			if node != null:
				node.visible = true
			set_preview_character_position(char_id, spawns[char_id])

	# The chunk already reset its story state in _build_chunk (on load). Re-set the step AFTER, because
	# the chunk's reset writes its own "..._start" step through set_preview_step (it shares _current_step).
	_current_step = "endo_junction_stretch"
	_select_character("endo")
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	_dialogue_chain([
		"endo_stretch.entry.aster_space",
		"endo_stretch.entry.peris_home",
		"endo_stretch.route.endo_gesture",
	], func():
		_player.set_move_enabled(true)
		_tutorial_prompt.show_prompt("Read Endo's junction, then combine all three views at the pulse crossing"))

## The stretch resolved (party rested at Shelter 1). Hand off to the existing flow.
func _start_endo_junction_stretch_complete() -> void:
	if not _endo_junction_active:
		return
	_endo_junction_active = false
	_current_step = "endo_junction_stretch_complete"
	_player.set_move_enabled(false)
	_tutorial_prompt.hide_prompt()
	_unload_chunk("endo_junction_stretch")
	_scheduler.schedule_after(1.0, _start_stacks_enter, "endo_to_stacks")

func _complete() -> void:
	_enter_step("complete")
	_player.set_move_enabled(false)
	# Cosmetic fade; the scene hand-off rides the scheduler so fast-forward (and the
	# headless playthrough, which never advances tweens) reaches it at the same tick.
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color", Color(0.02, 0.02, 0.03, 1.0), 2.0)
	_scheduler.schedule_after(2.0, func():
		_change_scene_or_record("res://scenes/tutorial/leaving_facility.tscn")
	, "complete_handoff")

# --- Chunk builders ---

func _build_channels_window_lane(
	parent: Node3D,
	window_id: String,
	stage_pos: Vector3,
	lure_pos: Vector3,
	curtain_pos: Vector3,
	goal_pos: Vector3,
	safe_duration: float
) -> void:
	var lane_root := Node3D.new()
	lane_root.name = "ChannelsWindowLane_%s" % window_id
	parent.add_child(lane_root)

	var side_sign := signf(lure_pos.z - stage_pos.z)
	var branch_dir := _channels_window_branch_direction(stage_pos, lure_pos)
	var cross_dir := _channels_window_cross_direction(branch_dir)
	var lane_floor_center := Vector3((stage_pos.x + goal_pos.x) * 0.5, -0.04, stage_pos.z)
	var lane_floor_size := Vector3(absf(goal_pos.x - stage_pos.x) + 8.0, 0.08, 7.0)
	_add_corridor_section(parent, lane_floor_center, lane_floor_size, Color(0.07, 0.085, 0.1))

	var lure_branch_center := Vector3((stage_pos.x + lure_pos.x) * 0.5, -0.04, (stage_pos.z + lure_pos.z) * 0.5)
	var lure_branch_size := Vector3(absf(lure_pos.x - stage_pos.x) + 5.0, 0.08, absf(lure_pos.z - stage_pos.z) + 4.0)
	_add_corridor_section(parent, lure_branch_center, lure_branch_size, Color(0.06, 0.075, 0.09))

	var stage_ring := MeshInstance3D.new()
	stage_ring.name = "ChannelsWindowStage_%s" % window_id
	var stage_ring_mesh := CylinderMesh.new()
	stage_ring_mesh.top_radius = 1.35
	stage_ring_mesh.bottom_radius = 1.35
	stage_ring_mesh.height = 0.04
	stage_ring.mesh = stage_ring_mesh
	var stage_ring_mat := StandardMaterial3D.new()
	stage_ring_mat.albedo_color = Color(0.18, 0.24, 0.3)
	stage_ring_mat.emission_enabled = true
	stage_ring_mat.emission = Color(0.18, 0.32, 0.46)
	stage_ring_mat.emission_energy_multiplier = 0.45
	stage_ring.material_override = stage_ring_mat
	stage_ring.position = stage_pos + Vector3(0.0, 0.03, 0.0)
	lane_root.add_child(stage_ring)

	var goal_beacon := MeshInstance3D.new()
	goal_beacon.name = "ChannelsWindowGoal_%s" % window_id
	var goal_beacon_mesh := CylinderMesh.new()
	goal_beacon_mesh.top_radius = 0.65
	goal_beacon_mesh.bottom_radius = 0.65
	goal_beacon_mesh.height = 0.12
	goal_beacon.mesh = goal_beacon_mesh
	var goal_beacon_mat := StandardMaterial3D.new()
	goal_beacon_mat.albedo_color = Color(0.3, 0.48, 0.56)
	goal_beacon_mat.emission_enabled = true
	goal_beacon_mat.emission = Color(0.32, 0.64, 0.76)
	goal_beacon_mat.emission_energy_multiplier = 0.5
	goal_beacon.material_override = goal_beacon_mat
	goal_beacon.position = goal_pos + Vector3(0.0, 0.06, 0.0)
	lane_root.add_child(goal_beacon)

	var goal_light := OmniLight3D.new()
	goal_light.position = goal_pos + Vector3(0.0, 1.6, 0.0)
	goal_light.light_color = Color(0.36, 0.78, 0.92)
	goal_light.light_energy = 1.4
	goal_light.omni_range = 8.0
	lane_root.add_child(goal_light)

	var lure_root := Node3D.new()
	lure_root.name = "ChannelsWindowLure_%s" % window_id
	lure_root.position = lure_pos
	lane_root.add_child(lure_root)

	var lure_stem := MeshInstance3D.new()
	var lure_stem_mesh := CylinderMesh.new()
	lure_stem_mesh.top_radius = 0.08
	lure_stem_mesh.bottom_radius = 0.12
	lure_stem_mesh.height = 0.95
	lure_stem.mesh = lure_stem_mesh
	var lure_stem_mat := StandardMaterial3D.new()
	lure_stem_mat.albedo_color = Color(0.24, 0.28, 0.18)
	lure_stem.material_override = lure_stem_mat
	lure_stem.position = Vector3(0.0, 0.48, 0.0)
	lure_root.add_child(lure_stem)

	var lure_mesh := MeshInstance3D.new()
	var lure_bulb_mesh := SphereMesh.new()
	lure_bulb_mesh.radius = 0.34
	lure_bulb_mesh.height = 0.68
	lure_mesh.mesh = lure_bulb_mesh
	var lure_mat := StandardMaterial3D.new()
	lure_mat.albedo_color = Color(0.56, 0.34, 0.16)
	lure_mat.emission_enabled = true
	lure_mat.emission = Color(0.82, 0.46, 0.18)
	lure_mat.emission_energy_multiplier = 0.35
	lure_mesh.material_override = lure_mat
	lure_mesh.position = Vector3(0.0, 1.0, 0.0)
	lure_root.add_child(lure_mesh)

	var lure_light := OmniLight3D.new()
	lure_light.position = Vector3(0.0, 1.1, 0.0)
	lure_light.light_color = Color(0.92, 0.5, 0.2)
	lure_light.light_energy = 0.45
	lure_light.omni_range = 7.5
	lure_root.add_child(lure_light)

	var lure_interactable = preload("res://scenes/game/interactable.tscn").instantiate()
	lure_interactable.name = "ChannelsWindowInteract_%s" % window_id
	lure_interactable.description = "Flure"
	lure_interactable.required_character = "aster"
	lure_interactable.one_shot = false
	lure_interactable.dwell_time = 1.6
	lure_interactable.tutorial_label = "HOLD"
	lure_interactable.position = lure_pos
	lure_interactable.interacted.connect(_on_channels_window_lure_activated.bind(window_id))
	parent.add_child(lure_interactable)

	var curtain_nodes: Array = []
	for i in range(CHANNELS_WINDOW_CURTAIN_OFFSETS.size()):
		var curtain := MeshInstance3D.new()
		curtain.name = "ChannelsWindowCurtain_%s_%d" % [window_id, i]
		var curtain_mesh := SphereMesh.new()
		curtain_mesh.radius = 0.36
		curtain_mesh.height = 0.72
		curtain.mesh = curtain_mesh
		var curtain_mat := StandardMaterial3D.new()
		curtain_mat.albedo_color = Color(0.2, 0.14, 0.08)
		curtain_mat.emission_enabled = true
		curtain_mat.emission = Color(0.7, 0.24, 0.08)
		curtain_mat.emission_energy_multiplier = 0.55
		curtain.material_override = curtain_mat
		curtain.position = curtain_pos + Vector3(0.0, 0.0, CHANNELS_WINDOW_CURTAIN_OFFSETS[i])
		parent.add_child(curtain)
		curtain_nodes.append(curtain)

	var corpse_nodes: Array = []
	var corpse_center := stage_pos - branch_dir * 5.8 - cross_dir * 1.6
	var corpse_offsets := [
		Vector3.ZERO,
		cross_dir * 1.55 - branch_dir * 0.85,
		cross_dir * -1.35 + branch_dir * 0.75,
	]
	for i in range(corpse_offsets.size()):
		var corpse := MeshInstance3D.new()
		corpse.name = "ChannelsWindowCorpse_%s_%d" % [window_id, i]
		var corpse_mesh := CapsuleMesh.new()
		corpse_mesh.radius = 0.22 + 0.03 * float(i)
		corpse_mesh.height = 1.0 + 0.1 * float(i)
		corpse.mesh = corpse_mesh
		var corpse_mat := StandardMaterial3D.new()
		corpse_mat.albedo_color = Color(0.18, 0.16, 0.15).lerp(Color(0.24, 0.18, 0.16), float(i) * 0.2)
		corpse_mat.roughness = 0.95
		corpse.material_override = corpse_mat
		corpse.position = corpse_center + corpse_offsets[i] + Vector3(0.0, 0.28, 0.0)
		corpse.rotation_degrees = Vector3(88.0, 24.0 * float(i), 80.0 - 8.0 * float(i))
		lane_root.add_child(corpse)
		corpse_nodes.append(corpse)

	var bridge_points: Array = []
	var channel_specs: Array = []
	var channel_lateral_offsets := [-1.25, 1.3, -0.95]
	var swarm_start_pos := corpse_center + branch_dir * 0.95 + cross_dir * 0.15
	bridge_points.append(swarm_start_pos)
	bridge_points.append(stage_pos - branch_dir * 1.4 - cross_dir * 1.1)
	for i in range(CHANNELS_WINDOW_PERIODIC_CHANNELS):
		var t := float(CHANNELS_WINDOW_CHANNEL_T_VALUES[i])
		var lateral := float(channel_lateral_offsets[i % channel_lateral_offsets.size()])
		var approach := stage_pos.lerp(lure_pos, maxf(0.08, t - 0.055)) + cross_dir * (lateral * 0.72)
		var channel_pos := stage_pos.lerp(lure_pos, t) + cross_dir * lateral
		var exit := stage_pos.lerp(lure_pos, minf(0.9, t + 0.055)) + cross_dir * (-lateral * 0.42)
		if bridge_points[bridge_points.size() - 1].distance_to(approach) > 0.3:
			bridge_points.append(approach)
		bridge_points.append(channel_pos)
		channel_specs.append({
			"position": channel_pos,
			"path_index": bridge_points.size() - 1,
		})
		bridge_points.append(exit)
	bridge_points.append(lure_pos + branch_dir * 0.35 + cross_dir * 0.45)

	var bridge_segments: Array = []
	for i in range(bridge_points.size() - 1):
		bridge_segments.append(_add_channels_window_bridge_segment(
			lane_root,
			"ChannelsWindowBridge_%s_%d" % [window_id, i],
			bridge_points[i],
			bridge_points[i + 1]
		))

	var path_distances: Array = []
	var path_distance := 0.0
	for i in range(bridge_points.size()):
		if i == 0:
			path_distances.append(0.0)
			continue
		path_distance += bridge_points[i - 1].distance_to(bridge_points[i])
		path_distances.append(path_distance)

	var periodic_channels: Array = []
	var channel_contact_map := {}
	var flow_period := CHANNELS_WINDOW_FLOW_PERIOD
	var desired_spacing := flow_period / float(CHANNELS_WINDOW_PERIODIC_CHANNELS)
	for i in range(channel_specs.size()):
		var spec: Dictionary = channel_specs[i]
		var channel_root := Node3D.new()
		channel_root.name = "ChannelsWindowChannel_%s_%d" % [window_id, i]
		channel_root.position = spec.get("position", Vector3.ZERO)
		channel_root.look_at_from_position(channel_root.position, channel_root.position + cross_dir, Vector3.UP, true)
		lane_root.add_child(channel_root)

		var trench := MeshInstance3D.new()
		var trench_mesh := BoxMesh.new()
		trench_mesh.size = Vector3(2.6, 0.32, 5.8)
		trench.mesh = trench_mesh
		var trench_mat := StandardMaterial3D.new()
		trench_mat.albedo_color = Color(0.07, 0.1, 0.12)
		trench_mat.roughness = 0.92
		trench.material_override = trench_mat
		trench.position = Vector3(0.0, 0.12, 0.0)
		channel_root.add_child(trench)

		var water := MeshInstance3D.new()
		var water_mesh := BoxMesh.new()
		water_mesh.size = Vector3(1.65, 1.0, 5.1)
		water.mesh = water_mesh
		var water_mat := StandardMaterial3D.new()
		water_mat.albedo_color = Color(0.08, 0.16, 0.24)
		water_mat.emission_enabled = true
		water_mat.emission = Color(0.14, 0.42, 0.65)
		water_mat.emission_energy_multiplier = 0.3
		water.material_override = water_mat
		water.position = Vector3(0.0, -0.22, 0.0)
		water.scale = Vector3.ONE
		channel_root.add_child(water)

		var foam := MeshInstance3D.new()
		var foam_mesh := BoxMesh.new()
		foam_mesh.size = Vector3(1.7, 0.08, 5.2)
		foam.mesh = foam_mesh
		var foam_mat := StandardMaterial3D.new()
		foam_mat.albedo_color = Color(0.54, 0.7, 0.78, 0.8)
		foam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		foam_mat.emission_enabled = true
		foam_mat.emission = Color(0.42, 0.78, 0.9)
		foam_mat.emission_energy_multiplier = 0.18
		foam.material_override = foam_mat
		foam.position = Vector3(0.0, 0.1, 0.0)
		channel_root.add_child(foam)

		var channel_light := OmniLight3D.new()
		channel_light.position = Vector3(0.0, 1.0, 0.0)
		channel_light.light_color = Color(0.24, 0.58, 0.8)
		channel_light.light_energy = 0.35
		channel_light.omni_range = 5.0
		channel_root.add_child(channel_light)

		var contact_path_index := int(spec.get("path_index", 0))
		var contact_time := float(path_distances[contact_path_index]) / CHANNELS_WINDOW_SWARM_SPEED
		var desired_start := fposmod(float(i) * desired_spacing, flow_period)
		var phase_offset := fposmod(-contact_time - desired_start, flow_period)
		periodic_channels.append({
			"index": i,
			"position": spec.get("position", Vector3.ZERO),
			"path_index": contact_path_index,
			"contact_time": contact_time,
			"phase_offset": phase_offset,
			"root": channel_root,
			"water": water,
			"foam": foam,
			"light": channel_light,
			"level": 0.0,
			"flooded": false,
			"local_phase": 0.0,
		})
		channel_contact_map[contact_path_index] = i

	var swarm_units: Array = []
	for i in range(CHANNELS_WINDOW_SWARM_OFFSETS.size()):
		var swarm := MeshInstance3D.new()
		swarm.name = "ChannelsWindowSwarm_%s_%d" % [window_id, i]
		var swarm_mesh := SphereMesh.new()
		swarm_mesh.radius = 0.28
		swarm_mesh.height = 0.56
		swarm.mesh = swarm_mesh
		var swarm_mat := StandardMaterial3D.new()
		swarm_mat.albedo_color = Color(0.32, 0.19, 0.08)
		swarm_mat.emission_enabled = true
		swarm_mat.emission = Color(0.86, 0.3, 0.08)
		swarm_mat.emission_energy_multiplier = 0.4
		swarm.material_override = swarm_mat
		var base_pos: Vector3 = (
			swarm_start_pos
			+ cross_dir * (CHANNELS_WINDOW_SWARM_OFFSETS[i] * 0.65)
			+ branch_dir * (0.22 * float(i % 2) - 0.28)
		)
		swarm.position = base_pos
		lane_root.add_child(swarm)
		swarm_units.append({
			"node": swarm,
			"base_pos": base_pos,
			"delay": float(i) * CHANNELS_WINDOW_SWARM_DELAY,
			"path_index": 1,
			"state": "idle",
			"wash_vector": Vector3.ZERO,
		})

	var attract_pos := curtain_pos + Vector3(0.0, 0.0, side_sign * 9.0)
	var lane := {
		"stage_pos": stage_pos,
		"lure_pos": lure_pos,
		"goal_pos": goal_pos,
		"curtain_pos": curtain_pos,
		"attract_pos": attract_pos,
		"safe_duration": safe_duration,
		"curtain_nodes": curtain_nodes,
		"lure_mesh": lure_mesh,
		"lure_light": lure_light,
		"interactable": lure_interactable,
		"phase": "idle",
		"safe_until_tick": -1.0,
		"last_outcome": "",
		"lure_active": false,
		"branch_dir": branch_dir,
		"cross_dir": cross_dir,
		"swarm_start_pos": swarm_start_pos,
		"swarm_path": bridge_points,
		"channel_contact_map": channel_contact_map,
		"flow_period": flow_period,
		"flood_duration": CHANNELS_WINDOW_FLOOD_DURATION,
		"flow_offset": 0.0,
		"periodic_channels": periodic_channels,
		"bridge_segments": bridge_segments,
		"corpse_nodes": corpse_nodes,
		"swarm_units": swarm_units,
		"swarm_state": "idle",
		"swarm_start_tick": -1.0,
		"washed_channel_index": -1,
		"wash_analysis": {},
	}
	lane["wash_analysis"] = _channels_window_wash_analysis(lane)
	lane = _reset_channels_window_swarm(lane)
	_channels_window_lanes[window_id] = lane

func _channels_field_role_color(role: String) -> Color:
	match role:
		"aster":
			return Color(0.30, 0.68, 1.0)
		"peris":
			return Color(0.95, 0.68, 0.30)
		"endo":
			return Color(0.38, 0.76, 0.55)
		_:
			return Color(0.72, 0.74, 0.76)

func _add_channels_field_station_visual(site: Node3D, site_id: String, spec: Dictionary) -> Node3D:
	var assembly := Node3D.new()
	assembly.name = "ChannelsFieldAssembly_%s" % site_id
	site.add_child(assembly)
	var role := str(spec.get("role", ""))
	var role_color := _channels_field_role_color(role)
	var kind := str(spec.get("kind", "optional"))
	var operation_tint := role_color
	var operation_id := str(spec.get("operation", ""))
	if CHANNELS_FIELD_OPERATIONS.has(operation_id):
		operation_tint = CHANNELS_FIELD_OPERATIONS[operation_id].get("tint", role_color)
	var base_material := StandardMaterial3D.new()
	base_material.albedo_color = Color(0.075, 0.09, 0.095).lerp(role_color.darkened(0.4), 0.32)
	base_material.metallic = 0.42
	base_material.roughness = 0.58
	var glow_material := StandardMaterial3D.new()
	glow_material.albedo_color = operation_tint.darkened(0.24)
	glow_material.emission_enabled = true
	glow_material.emission = operation_tint
	glow_material.emission_energy_multiplier = 1.15 if kind == "choice" else 0.58
	glow_material.metallic = 0.18
	glow_material.roughness = 0.42

	var footing := MeshInstance3D.new()
	footing.name = "MeasuredFooting"
	var footing_mesh := CylinderMesh.new()
	footing_mesh.top_radius = 0.54 if kind == "choice" else 0.42
	footing_mesh.bottom_radius = 0.68 if kind == "choice" else 0.56
	footing_mesh.height = 0.22
	footing.mesh = footing_mesh
	footing.material_override = base_material
	footing.position.y = 0.11
	assembly.add_child(footing)

	var body := MeshInstance3D.new()
	body.name = "InstrumentBody"
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.72 if kind == "choice" else 0.54, 1.05, 0.52)
	body.mesh = body_mesh
	body.material_override = base_material
	body.position.y = 0.73
	assembly.add_child(body)

	var face := MeshInstance3D.new()
	face.name = "InstrumentReadout"
	var face_mesh := BoxMesh.new()
	face_mesh.size = Vector3(0.58 if kind == "choice" else 0.42, 0.26, 0.055)
	face.mesh = face_mesh
	face.material_override = glow_material
	face.position = Vector3(0, 0.92, -0.29)
	assembly.add_child(face)
	for band_i in range(3):
		var band := MeshInstance3D.new()
		band.name = "MeasuredBand%d" % band_i
		var band_mesh := BoxMesh.new()
		band_mesh.size = Vector3(0.12, 0.05, 0.06)
		band.mesh = band_mesh
		band.material_override = glow_material
		band.position = Vector3(-0.18 + float(band_i) * 0.18, 0.50, -0.30)
		assembly.add_child(band)

	# The top silhouette carries role, not arbitrary prop scatter: Aster gets a data vane, Peris a
	# living fork, Endo a brace bar. Players can read who will service a site from across a bay.
	match role:
		"aster":
			var vane := MeshInstance3D.new()
			vane.name = "DataVane"
			var vane_mesh := BoxMesh.new()
			vane_mesh.size = Vector3(0.08, 0.62, 0.42)
			vane.mesh = vane_mesh
			vane.material_override = glow_material
			vane.position = Vector3(0, 1.54, 0)
			vane.rotation_degrees.z = 24.0
			assembly.add_child(vane)
		"peris":
			for fork_x in [-0.16, 0.16]:
				var fork := MeshInstance3D.new()
				fork.name = "LivingFork"
				var fork_mesh := CylinderMesh.new()
				fork_mesh.top_radius = 0.045
				fork_mesh.bottom_radius = 0.065
				fork_mesh.height = 0.68
				fork.mesh = fork_mesh
				fork.material_override = glow_material
				fork.position = Vector3(float(fork_x), 1.54, 0)
				fork.rotation_degrees.z = -16.0 if float(fork_x) < 0.0 else 16.0
				assembly.add_child(fork)
		"endo":
			var brace := MeshInstance3D.new()
			brace.name = "BraceBar"
			var brace_mesh := BoxMesh.new()
			brace_mesh.size = Vector3(0.92, 0.12, 0.14)
			brace.mesh = brace_mesh
			brace.material_override = glow_material
			brace.position = Vector3(0, 1.48, 0)
			brace.rotation_degrees.z = -12.0
			assembly.add_child(brace)

	var label := Label3D.new()
	label.name = "MeasuredLabel"
	label.text = "%s // %s" % [role.to_upper(), str(spec.get("display", site_id)).to_upper()]
	label.font_size = 34
	label.pixel_size = 0.0075
	label.modulate = operation_tint.lightened(0.24)
	label.outline_modulate = Color(0.01, 0.015, 0.018, 0.96)
	label.outline_size = 10
	label.position = Vector3(0, 2.10, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	assembly.add_child(label)
	return assembly

func _bind_channels_field_site_outline(site: Node3D, assembly: Node3D, site_id: String) -> void:
	if not is_instance_valid(site) or not is_instance_valid(assembly):
		return
	var target := _outline_object_meshes(
		site, "ChannelsFieldOutline_%s" % site_id, _collect_mesh_instances(assembly),
		"channels.field.%s" % site_id, 0.85
	)
	_set_room_target_interaction_delegate(target, site)

func _spawn_channels_field_site(parent: Node3D, site_id: String, spec: Dictionary, optional := false) -> void:
	var role := str(spec.get("role", ""))
	var site = InteractableFactory.spawn(
		_game_state, parent, "ChannelsField_%s" % site_id,
		{
			"position": spec.get("pos", Vector3.ZERO),
			"radius": 1.7,
			"hold_time": _channels_field_site_work_seconds(site_id),
			"one_shot": str(spec.get("kind", "optional")) != "choice",
			"requires_hold": false,
			"required_character": role,
			"tutorial_label": str(spec.get("verb", "INSPECT")),
			"description": str(spec.get("display", site_id)),
			"enabled": false,
		},
		_scheduler, _dialogue, _active_character
	)
	site.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
	site.set("required_character", role)
	site.set_interaction_enabled(false)
	site.set("selected_feedback_color", _channels_field_role_color(role))
	site.set("outline_highlight_radius", 1.4)
	site.interacted.connect(Callable(self, "_on_channels_field_site_interacted").bind(site_id))
	site.interaction_requested.connect(Callable(self, "_on_channels_field_route_requested").bind(site_id))
	var visual_spec := spec.duplicate(true)
	if optional:
		visual_spec["kind"] = "optional"
	var assembly := _add_channels_field_station_visual(site, site_id, visual_spec)
	_channels_field_sites[site_id] = site
	_channels_field_visuals[site_id] = assembly
	assembly.visible = false
	call_deferred("_bind_channels_field_site_outline", site, assembly, site_id)

func _add_channels_field_datum(parent: Node3D, datum_name: String, from_pos: Vector3, to_pos: Vector3, color: Color) -> void:
	var flat_from := Vector3(from_pos.x, 0.032, from_pos.z)
	var flat_to := Vector3(to_pos.x, 0.032, to_pos.z)
	var length := flat_from.distance_to(flat_to)
	if length <= 0.1:
		return
	var datum := MeshInstance3D.new()
	datum.name = datum_name
	var datum_mesh := BoxMesh.new()
	datum_mesh.size = Vector3(0.075, 0.018, length)
	datum.mesh = datum_mesh
	var datum_material := StandardMaterial3D.new()
	datum_material.albedo_color = Color(color, 0.72)
	datum_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	datum_material.emission_enabled = true
	datum_material.emission = color
	datum_material.emission_energy_multiplier = 0.45
	datum_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	datum.material_override = datum_material
	datum.position = (flat_from + flat_to) * 0.5
	datum.look_at_from_position(datum.position, flat_to, Vector3.UP, true)
	parent.add_child(datum)

func _add_channels_field_frame(parent: Node3D, operation_id: String, operation_index: int) -> void:
	var operation: Dictionary = CHANNELS_FIELD_OPERATIONS[operation_id]
	var anchor := Vector3(float(operation.get("frame_x", 0.0)), 0.0, 0.0)
	var tint: Color = operation.get("tint", Color(0.4, 0.7, 0.6))
	var frame_root := Node3D.new()
	frame_root.name = "ChannelsFieldFrame_%s" % operation_id
	parent.add_child(frame_root)
	var frame_material := StandardMaterial3D.new()
	frame_material.albedo_color = Color(0.18, 0.23, 0.22)
	frame_material.metallic = 0.38
	frame_material.roughness = 0.68
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.name = "MeasuredPost"
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.34, 3.1, 0.42)
		post.mesh = post_mesh
		post.material_override = frame_material
		post.position = Vector3(anchor.x, 1.55, float(side) * 23.6)
		frame_root.add_child(post)
	var beam := MeshInstance3D.new()
	beam.name = "MeasuredHeader"
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(0.42, 0.26, 47.2)
	beam.mesh = beam_mesh
	beam.material_override = frame_material
	beam.position = Vector3(anchor.x, 3.05, 0)
	frame_root.add_child(beam)
	var sign := Label3D.new()
	sign.name = "OperationSign"
	sign.text = "%02d // %s" % [operation_index + 1, str(operation.get("label", operation_id)).to_upper()]
	sign.font_size = 44
	sign.pixel_size = 0.008
	sign.modulate = tint.lightened(0.22)
	sign.outline_modulate = Color(0.01, 0.015, 0.018, 0.95)
	sign.outline_size = 10
	sign.position = Vector3(anchor.x + 0.28, 2.58, -22.9)
	sign.rotation_degrees.y = 0.0
	frame_root.add_child(sign)
	var light := OmniLight3D.new()
	light.name = "ChannelsFieldLight_%s" % operation_id
	light.position = Vector3(anchor.x + 1.4, 2.7, 0)
	light.light_color = tint
	light.light_energy = 0.86
	light.omni_range = 12.0
	light.shadow_enabled = false
	frame_root.add_child(light)

func _channels_landmark_material(
		color: Color, emission_energy: float = 0.0, alpha: float = 1.0
	) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.metallic = 0.34
	material.roughness = 0.48 if emission_energy > 0.0 else 0.68
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	return material

func _channels_landmark_box(
		parent: Node3D, node_name: String, local_position: Vector3, size: Vector3,
		material: Material, local_rotation := Vector3.ZERO
	) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = material
	mesh_instance.position = local_position
	mesh_instance.rotation_degrees = local_rotation
	parent.add_child(mesh_instance)
	return mesh_instance

func _channels_landmark_cylinder(
		parent: Node3D, node_name: String, local_position: Vector3,
		top_radius: float, bottom_radius: float, height: float, material: Material,
		local_rotation := Vector3.ZERO
	) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top_radius
	cylinder.bottom_radius = bottom_radius
	cylinder.height = height
	cylinder.radial_segments = 16
	cylinder.rings = 4
	mesh_instance.mesh = cylinder
	mesh_instance.material_override = material
	mesh_instance.position = local_position
	mesh_instance.rotation_degrees = local_rotation
	parent.add_child(mesh_instance)
	return mesh_instance

func _add_channels_landmark_basin(
		room: Node3D, operation_id: String, side: float, structure_material: Material,
		water_material: Material
	) -> void:
	var basin_z := side * 16.8
	var trunk_z := side * 6.1
	_channels_landmark_box(
		room, "ChannelsLandmarkWater_%s_trunk" % operation_id,
		Vector3(0.0, 0.035, trunk_z), Vector3(4.6, 0.07, 12.2), water_material
	)
	_channels_landmark_box(
		room, "ChannelsLandmarkWater_%s_basin" % operation_id,
		Vector3(0.0, 0.045, basin_z), Vector3(13.2, 0.09, 8.8), water_material
	)
	_channels_landmark_box(
		room, "ChannelsLandmarkSilhouette_%s_rim_left" % operation_id,
		Vector3(-6.75, 0.28, basin_z), Vector3(0.34, 0.56, 9.2), structure_material
	)
	_channels_landmark_box(
		room, "ChannelsLandmarkSilhouette_%s_rim_right" % operation_id,
		Vector3(6.75, 0.28, basin_z), Vector3(0.34, 0.56, 9.2), structure_material
	)
	_channels_landmark_box(
		room, "ChannelsLandmarkSilhouette_%s_rim_inner" % operation_id,
		Vector3(0.0, 0.28, basin_z - side * 4.55), Vector3(13.8, 0.56, 0.34), structure_material
	)
	_channels_landmark_box(
		room, "ChannelsLandmarkSilhouette_%s_rim_outer" % operation_id,
		Vector3(0.0, 0.28, basin_z + side * 4.55), Vector3(13.8, 0.56, 0.34), structure_material
	)

func _add_channels_landmark_silhouette(
		room: Node3D, operation_id: String, side: float, structure_material: Material,
		glow_material: Material
	) -> void:
	var outer_z := side * 20.2
	match operation_id:
		"intake":
			for pipe_index in range(3):
				var pipe_x := -3.4 + float(pipe_index) * 3.4
				_channels_landmark_cylinder(
					room, "ChannelsLandmarkSilhouette_intake_pipe_%02d" % pipe_index,
					Vector3(pipe_x, 3.8, outer_z), 1.15, 1.15, 4.8,
					structure_material, Vector3(90.0, 0.0, 0.0)
				)
				_channels_landmark_cylinder(
					room, "ChannelsLandmarkSilhouette_intake_mouth_%02d" % pipe_index,
					Vector3(pipe_x, 3.8, outer_z - side * 2.5), 1.30, 1.30, 0.18,
					glow_material, Vector3(90.0, 0.0, 0.0)
				)
			_channels_landmark_box(
				room, "ChannelsLandmarkSilhouette_intake_header", Vector3(0.0, 6.0, outer_z),
				Vector3(10.8, 0.55, 1.2), structure_material
			)
		"memory":
			for post_x in [-5.2, 5.2]:
				_channels_landmark_box(
					room, "ChannelsLandmarkSilhouette_memory_post_%s" % str(post_x),
					Vector3(float(post_x), 3.0, outer_z), Vector3(0.65, 6.0, 0.75), structure_material
				)
			_channels_landmark_box(
				room, "ChannelsLandmarkSilhouette_memory_bridge", Vector3(0.0, 5.8, outer_z),
				Vector3(11.0, 0.62, 1.3), structure_material
			)
			_channels_landmark_cylinder(
				room, "ChannelsLandmarkSilhouette_memory_lantern", Vector3(0.0, 3.65, outer_z),
				0.72, 0.42, 1.55, glow_material
			)
			_channels_landmark_box(
				room, "ChannelsLandmarkSilhouette_memory_drop", Vector3(0.0, 4.85, outer_z),
				Vector3(0.12, 1.9, 0.12), glow_material
			)
		"harvest":
			for hopper_index in range(3):
				var hopper_x := -3.8 + float(hopper_index) * 3.8
				_channels_landmark_cylinder(
					room, "ChannelsLandmarkSilhouette_harvest_hopper_%02d" % hopper_index,
					Vector3(hopper_x, 4.4, outer_z), 1.35, 0.34, 2.9, structure_material
				)
				_channels_landmark_box(
					room, "ChannelsLandmarkSilhouette_harvest_catch_%02d" % hopper_index,
					Vector3(hopper_x, 2.55, outer_z), Vector3(2.4, 0.35, 2.0), glow_material
				)
			_channels_landmark_box(
				room, "ChannelsLandmarkSilhouette_harvest_rail", Vector3(0.0, 6.2, outer_z),
				Vector3(12.4, 0.36, 0.5), structure_material
			)
		"relay":
			_channels_landmark_cylinder(
				room, "ChannelsLandmarkSilhouette_relay_tower", Vector3(0.0, 4.25, outer_z),
				2.25, 2.55, 8.5, structure_material
			)
			for band_index in range(3):
				_channels_landmark_cylinder(
					room, "ChannelsLandmarkSilhouette_relay_band_%02d" % band_index,
					Vector3(0.0, 2.2 + float(band_index) * 2.0, outer_z),
					2.62, 2.62, 0.18, glow_material
				)
			for pipe_side in [-1.0, 1.0]:
				_channels_landmark_cylinder(
					room, "ChannelsLandmarkSilhouette_relay_feed_%s" % str(pipe_side),
					Vector3(float(pipe_side) * 4.0, 2.0, outer_z), 0.46, 0.46, 6.0,
					structure_material, Vector3(0.0, 0.0, 90.0)
				)
		"signal":
			_channels_landmark_cylinder(
				room, "ChannelsLandmarkSilhouette_signal_mast", Vector3(0.0, 4.4, outer_z),
				0.34, 0.58, 8.8, structure_material
			)
			for arm_index in range(3):
				var arm_side := -1.0 if arm_index % 2 == 0 else 1.0
				_channels_landmark_box(
					room, "ChannelsLandmarkSilhouette_signal_arm_%02d" % arm_index,
					Vector3(arm_side * (1.6 + float(arm_index) * 0.65), 4.2 + float(arm_index) * 1.25, outer_z),
					Vector3(0.28, 4.6, 0.30), glow_material,
					Vector3(0.0, 0.0, arm_side * (38.0 + float(arm_index) * 5.0))
				)
			_channels_landmark_cylinder(
				room, "ChannelsLandmarkSilhouette_signal_crown", Vector3(0.0, 8.8, outer_z),
				1.65, 1.65, 0.20, glow_material
			)
		"escape":
			for baffle_index in range(4):
				var baffle_x := -4.8 + float(baffle_index) * 3.2
				_channels_landmark_box(
					room, "ChannelsLandmarkSilhouette_escape_baffle_%02d" % baffle_index,
					Vector3(baffle_x, 2.4, outer_z - side * float(baffle_index % 2) * 1.2),
					Vector3(0.42, 4.8, 4.6), structure_material,
					Vector3(0.0, float(baffle_index - 1) * 8.0, 0.0)
				)
			_channels_landmark_cylinder(
				room, "ChannelsLandmarkSilhouette_escape_beacon", Vector3(0.0, 5.9, outer_z),
				0.72, 1.15, 6.2, glow_material
			)

func _build_channels_operation_landmarks(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "ChannelsOperationLandmarks"
	parent.add_child(root)
	var operation_order := ["intake", "memory", "harvest", "relay", "signal", "escape"]
	for operation_index in range(operation_order.size()):
		var operation_id := str(operation_order[operation_index])
		var operation: Dictionary = CHANNELS_FIELD_OPERATIONS[operation_id]
		var side := -1.0 if operation_index % 2 == 0 else 1.0
		var tint: Color = operation.get("tint", Color(0.36, 0.76, 0.62))
		var room := Node3D.new()
		room.name = "ChannelsLandmarkRoom_%s" % operation_id
		room.position = Vector3(float(operation.get("frame_x", 0.0)), 0.0, 0.0)
		room.set_meta("operation_id", operation_id)
		room.set_meta("visual_verb", str(operation.get("label", operation_id)))
		root.add_child(room)
		var structure_material := _channels_landmark_material(
			Color(0.11, 0.15, 0.16).lerp(tint.darkened(0.48), 0.38)
		)
		var glow_material := _channels_landmark_material(tint, 1.5)
		var water_material := _channels_landmark_material(
			Color(0.10, 0.48, 0.58).lerp(tint, 0.28), 1.15, 0.82
		)
		_add_channels_landmark_basin(
			room, operation_id, side, structure_material, water_material
		)
		_add_channels_landmark_silhouette(
			room, operation_id, side, structure_material, glow_material
		)
		var label := Label3D.new()
		label.name = "ChannelsLandmarkLabel_%s" % operation_id
		label.text = "%02d // %s" % [operation_index + 1, str(operation.get("label", operation_id)).to_upper()]
		label.font_size = 52
		label.pixel_size = 0.009
		label.modulate = tint.lightened(0.26)
		label.outline_modulate = Color(0.005, 0.01, 0.012, 0.98)
		label.outline_size = 12
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0.0, 7.4, side * 21.8)
		room.add_child(label)
		var light := OmniLight3D.new()
		light.name = "ChannelsLandmarkLight_%s" % operation_id
		light.position = Vector3(0.0, 4.6, side * 16.8)
		light.light_color = tint.lightened(0.12)
		light.light_energy = 1.35
		light.omni_range = 15.0
		light.shadow_enabled = false
		room.add_child(light)

func _build_channels_fieldwork(parent: Node3D) -> void:
	_channels_field_sites.clear()
	_channels_field_visuals.clear()
	_channels_field_route_visuals.clear()
	_channels_field_completed.clear()
	_channels_field_operations_completed.clear()
	_channels_field_phase = ""
	_channels_field_choices.clear()
	_channels_field_attempts.clear()
	_channels_optional_findings.clear()
	_channels_field_decisions = 0
	var root := Node3D.new()
	root.name = "ChannelsFieldwork"
	parent.add_child(root)
	var operation_index := 0
	for operation_id_variant in CHANNELS_FIELD_OPERATIONS.keys():
		var operation_id := str(operation_id_variant)
		var operation: Dictionary = CHANNELS_FIELD_OPERATIONS[operation_id]
		_add_channels_field_frame(root, operation_id, operation_index)
		var route_root := Node3D.new()
		route_root.name = "ChannelsFieldRoute_%s" % operation_id
		route_root.visible = false
		root.add_child(route_root)
		_channels_field_route_visuals[operation_id] = route_root
		var route_points: Array = [operation.get("start", Vector3.ZERO)]
		for site_id in operation.get("evidence", []):
			var spec: Dictionary = CHANNELS_FIELD_SITES[str(site_id)]
			_spawn_channels_field_site(root, str(site_id), spec)
			route_points.append(spec.get("pos", Vector3.ZERO))
		for choice_id in operation.get("choices", []):
			_spawn_channels_field_site(root, str(choice_id), CHANNELS_FIELD_SITES[str(choice_id)])
		for resolution_id in (operation.get("resolution_sites", {}) as Dictionary).values():
			_spawn_channels_field_site(root, str(resolution_id), CHANNELS_FIELD_SITES[str(resolution_id)])
		for point_i in range(route_points.size() - 1):
			_add_channels_field_datum(
				route_root, "ChannelsFieldDatum_%s_%02d" % [operation_id, point_i],
				route_points[point_i], route_points[point_i + 1], operation.get("tint", Color.WHITE)
			)
		var last_point: Vector3 = route_points[route_points.size() - 1]
		for choice_index in range(operation.get("choices", []).size()):
			var choice_id := str(operation.get("choices", [])[choice_index])
			_add_channels_field_datum(
				route_root, "ChannelsFieldDatum_%s_choice_%02d" % [operation_id, choice_index],
				last_point, _channels_field_site_position(choice_id), operation.get("tint", Color.WHITE)
			)
			var resolution_sites: Dictionary = operation.get("resolution_sites", {})
			if resolution_sites.has(choice_id):
				_add_channels_field_datum(
					route_root, "ChannelsFieldDatum_%s_resolution_%02d" % [operation_id, choice_index],
					_channels_field_site_position(choice_id),
					_channels_field_site_position(str(resolution_sites[choice_id])),
					operation.get("tint", Color.WHITE)
				)
		operation_index += 1
	for site_id_variant in CHANNELS_OPTIONAL_SITES.keys():
		var site_id := str(site_id_variant)
		_spawn_channels_field_site(root, site_id, CHANNELS_OPTIONAL_SITES[site_id], true)

func _build_channels_chunk(parent: Node3D) -> void:
	var sx := CHANNELS_START.x
	var length := CHANNELS_END.x - CHANNELS_START.x
	var width := 50.0
	var floor_color := Color(0.06, 0.08, 0.1)
	var wall_color := Color(0.08, 0.08, 0.1)
	_channels_flow_strips.clear()
	_channels_flush_swarm_units.clear()
	_channels_window_lanes.clear()
	_channels_active_window_lane = ""
	_channels_shortcut_unlocked = false
	_channels_party_recuperated = false
	_channels_shelter_reached = false
	_channels_flush_state = ""
	_channels_flush_timer = 0.0
	_channels_flow_power = 0.0

	# Main corridor ground + collision
	_add_corridor_section(parent, Vector3(sx + length / 2.0, -0.05, 0), Vector3(length, 0.1, width), floor_color)
	var gb := StaticBody3D.new()
	gb.position = Vector3(sx + length / 2.0, -0.01, 0)
	gb.collision_layer = 1
	gb.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(length, 0.02, width)
	gc.shape = gs
	gb.add_child(gc)
	parent.add_child(gb)

	# Outer walls
	_add_wall(parent, Vector3(sx + length / 2.0, 1.5, -width / 2.0), Vector3(length, 3, 0.3), wall_color)
	_add_wall(parent, Vector3(sx + length / 2.0, 1.5, width / 2.0), Vector3(length, 3, 0.3), wall_color)

	# Flowing water channels along the main path (blue-tinted strips)
	for i in range(6):
		var water := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(length * 0.8, 0.02, 2.0)
		water.mesh = wb
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.1, 0.15, 0.2)
		wm.emission_enabled = true
		wm.emission = Color(0.05, 0.08, 0.12)
		wm.emission_energy_multiplier = 0.3
		water.material_override = wm
		water.position = Vector3(sx + length / 2.0, 0.01, -15.0 + i * 6.0)
		parent.add_child(water)
		_channels_flow_strips.append(water)

	# Side branches (3 alcoves off the main path for exploration)
	for i in range(3):
		var branch_x: float = sx + 50.0 + i * 60.0
		var branch_z: float = -width / 2.0 + 5.0 if i % 2 == 0 else width / 2.0 - 5.0
		var branch_sign: float = 1.0 if branch_z > 0 else -1.0
		# Alcove floor
		_add_corridor_section(parent, Vector3(branch_x, -0.04, branch_z + branch_sign * 10.0), Vector3(15, 0.08, 12), Color(0.05, 0.06, 0.08))
		# Alcove walls
		_add_wall(parent, Vector3(branch_x - 8.0, 1.5, branch_z + branch_sign * 10.0), Vector3(0.3, 3, 12), wall_color)
		_add_wall(parent, Vector3(branch_x + 8.0, 1.5, branch_z + branch_sign * 10.0), Vector3(0.3, 3, 12), wall_color)

	# Stagnant pools with iron deposits (multiple, spread out)
	for i in range(4):
		var sp_x: float = sx + 40.0 + i * 50.0
		var sp_z: float = 8.0 + randf_range(-3, 3) if i % 2 == 0 else -8.0 + randf_range(-3, 3)  # @rendering_only — sandbox debris scatter
		var sp_pos := Vector3(sp_x, 0.02, sp_z)
		var sp_size := Vector3(8, 0.04, 6)
		var stagnant := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = sp_size
		stagnant.mesh = sb
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.2, 0.12, 0.06)
		sm.emission_enabled = true
		sm.emission = Color(0.15, 0.06, 0.02)
		sm.emission_energy_multiplier = 0.2
		stagnant.material_override = sm
		stagnant.position = sp_pos
		parent.add_child(stagnant)
		_iron_patches.append({"pos": sp_pos, "size": sp_size})

	# Body in the drainage path grounds both the memory beat and the harvest beat.
	var body := MeshInstance3D.new()
	body.name = "ChannelsBody"
	var corpse_mesh := CapsuleMesh.new()
	corpse_mesh.radius = 0.28
	corpse_mesh.height = 1.3
	body.mesh = corpse_mesh
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.2, 0.18, 0.16)
	body_mat.roughness = 0.9
	body.material_override = body_mat
	body.position = CHANNELS_BODY_POS
	body.rotation_degrees = Vector3(0, 0, 88)
	parent.add_child(body)

	for i in range(2):
		var memory_body := MeshInstance3D.new()
		var memory_mesh := CapsuleMesh.new()
		memory_mesh.radius = 0.22
		memory_mesh.height = 1.1
		memory_body.mesh = memory_mesh
		var memory_mat := StandardMaterial3D.new()
		memory_mat.albedo_color = Color(0.16, 0.18, 0.22)
		memory_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		memory_mat.albedo_color.a = 0.45
		memory_body.material_override = memory_mat
		memory_body.position = Vector3(sx + 48.0 + i * 14.0, 0.38, -10.0 + i * 6.0)
		memory_body.rotation_degrees = Vector3(0, 0, 90)
		parent.add_child(memory_body)

	# Second flure: dormant until Peris tends it in the coda beat.
	var flure_root := Node3D.new()
	flure_root.name = "SecondFlure"
	flure_root.position = CHANNELS_FLURE_POS
	parent.add_child(flure_root)

	var flure_stem := MeshInstance3D.new()
	var flure_stem_mesh := CylinderMesh.new()
	flure_stem_mesh.top_radius = 0.08
	flure_stem_mesh.bottom_radius = 0.12
	flure_stem_mesh.height = 1.0
	flure_stem.mesh = flure_stem_mesh
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.18, 0.24, 0.18)
	flure_stem.material_override = stem_mat
	flure_stem.position = Vector3(0, 0.5, 0)
	flure_root.add_child(flure_stem)

	_channels_flure = MeshInstance3D.new()
	var flure_bulb_mesh := SphereMesh.new()
	flure_bulb_mesh.radius = 0.35
	flure_bulb_mesh.height = 0.7
	_channels_flure.mesh = flure_bulb_mesh
	var flure_mat := StandardMaterial3D.new()
	flure_mat.albedo_color = Color(0.22, 0.35, 0.25)
	flure_mat.emission_enabled = true
	flure_mat.emission = Color(0.2, 0.55, 0.32)
	flure_mat.emission_energy_multiplier = 0.25
	_channels_flure.material_override = flure_mat
	_channels_flure.position = Vector3(0, 1.05, 0)
	flure_root.add_child(_channels_flure)

	_channels_flure_light = OmniLight3D.new()
	_channels_flure_light.position = Vector3(0, 1.0, 0)
	_channels_flure_light.light_color = Color(0.32, 0.7, 0.45)
	_channels_flure_light.light_energy = 0.45
	_channels_flure_light.omni_range = 8.0
	flure_root.add_child(_channels_flure_light)
	_set_channels_flure_active(false)
	_set_channels_flow_power(0.25)

	for i in range(CHANNELS_FLUSH_SWARM_OFFSETS.size()):
		var flush_swarm := MeshInstance3D.new()
		flush_swarm.name = "ChannelsFlushSwarm_%d" % i
		var flush_mesh := SphereMesh.new()
		flush_mesh.radius = 0.22
		flush_mesh.height = 0.45
		flush_swarm.mesh = flush_mesh
		var flush_mat := StandardMaterial3D.new()
		flush_mat.albedo_color = Color(0.22, 0.18, 0.12)
		flush_mat.emission_enabled = true
		flush_mat.emission = Color(0.72, 0.32, 0.1)
		flush_mat.emission_energy_multiplier = 0.55
		flush_swarm.material_override = flush_mat
		flush_swarm.position = CHANNELS_FLUSH_SWARM_POS + Vector3(CHANNELS_FLUSH_SWARM_OFFSETS[i], 0.0, sin(float(i) * 1.4) * 0.8)
		parent.add_child(flush_swarm)
		_channels_flush_swarm_units.append({
			"node": flush_swarm,
			"base_pos": flush_swarm.position,
			"active": true,
			"state": "",
		})

	_build_channels_window_lane(
		parent,
		"window_one",
		CHANNELS_WINDOW_ONE_STAGE_POS,
		CHANNELS_WINDOW_ONE_LURE_POS,
		CHANNELS_WINDOW_ONE_CURTAIN_POS,
		CHANNELS_WINDOW_ONE_GOAL_POS,
		CHANNELS_WINDOW_ONE_DURATION
	)
	_build_channels_window_lane(
		parent,
		"window_two",
		CHANNELS_WINDOW_TWO_STAGE_POS,
		CHANNELS_WINDOW_TWO_LURE_POS,
		CHANNELS_WINDOW_TWO_CURTAIN_POS,
		CHANNELS_WINDOW_TWO_GOAL_POS,
		CHANNELS_WINDOW_TWO_DURATION
	)

	# Encounter lure: Endo uses this to pull the swarm away from the shelter route.
	var run_lure_root := Node3D.new()
	run_lure_root.name = "EncounterFlure"
	run_lure_root.position = CHANNELS_RUN_LURE_POS
	parent.add_child(run_lure_root)

	var run_lure_stem := MeshInstance3D.new()
	var run_lure_stem_mesh := CylinderMesh.new()
	run_lure_stem_mesh.top_radius = 0.09
	run_lure_stem_mesh.bottom_radius = 0.13
	run_lure_stem_mesh.height = 1.1
	run_lure_stem.mesh = run_lure_stem_mesh
	var run_lure_stem_mat := StandardMaterial3D.new()
	run_lure_stem_mat.albedo_color = Color(0.25, 0.28, 0.18)
	run_lure_stem.material_override = run_lure_stem_mat
	run_lure_stem.position = Vector3(0, 0.55, 0)
	run_lure_root.add_child(run_lure_stem)

	_channels_run_lure_mesh = MeshInstance3D.new()
	var run_lure_bulb := SphereMesh.new()
	run_lure_bulb.radius = 0.4
	run_lure_bulb.height = 0.8
	_channels_run_lure_mesh.mesh = run_lure_bulb
	var run_lure_mat := StandardMaterial3D.new()
	run_lure_mat.albedo_color = Color(0.55, 0.34, 0.12)
	run_lure_mat.emission_enabled = true
	run_lure_mat.emission = Color(0.8, 0.4, 0.15)
	run_lure_mat.emission_energy_multiplier = 0.35
	run_lure_mat.metallic = 0.15
	_channels_run_lure_mesh.material_override = run_lure_mat
	_channels_run_lure_mesh.position = Vector3(0, 1.1, 0)
	run_lure_root.add_child(_channels_run_lure_mesh)

	_channels_run_lure_light = OmniLight3D.new()
	_channels_run_lure_light.position = Vector3(0, 1.2, 0)
	_channels_run_lure_light.light_color = Color(0.9, 0.45, 0.18)
	_channels_run_lure_light.light_energy = 0.5
	_channels_run_lure_light.omni_range = 8.0
	run_lure_root.add_child(_channels_run_lure_light)
	_set_channels_run_lure_active(false)

	_channels_run_lure_interactable = preload("res://scenes/game/interactable.tscn").instantiate()
	_channels_run_lure_interactable.name = "EncounterFlureInteract"
	_channels_run_lure_interactable.description = "Flure"
	_channels_run_lure_interactable.required_character = "endo"
	_channels_run_lure_interactable.one_shot = false
	_channels_run_lure_interactable.dwell_time = 2.0
	_channels_run_lure_interactable.tutorial_label = "HOLD"
	_channels_run_lure_interactable.position = CHANNELS_RUN_LURE_POS
	parent.add_child(_channels_run_lure_interactable)
	_channels_run_lure_interactable.interacted.connect(_on_channels_run_lure_activated)

	# Hide alcove near the shelter route.
	_channels_hide_spot = Node3D.new()
	_channels_hide_spot.name = "ChannelsHideSpot"
	_channels_hide_spot.position = CHANNELS_HIDE_SPOT_POS
	parent.add_child(_channels_hide_spot)
	_add_corridor_section(parent, Vector3(CHANNELS_HIDE_SPOT_POS.x, -0.04, CHANNELS_HIDE_SPOT_POS.z), Vector3(10, 0.08, 8), Color(0.05, 0.05, 0.07))
	_add_wall(parent, Vector3(CHANNELS_HIDE_SPOT_POS.x, 1.5, CHANNELS_HIDE_SPOT_POS.z + 4.0), Vector3(10, 3, 0.3), wall_color)
	_add_wall(parent, Vector3(CHANNELS_HIDE_SPOT_POS.x - 5.0, 1.5, CHANNELS_HIDE_SPOT_POS.z), Vector3(0.3, 3, 8), wall_color)
	_add_wall(parent, Vector3(CHANNELS_HIDE_SPOT_POS.x + 5.0, 1.5, CHANNELS_HIDE_SPOT_POS.z), Vector3(0.3, 3, 8), wall_color)

	# Swarm cluster guarding the stretch before the shelter.
	_channels_swarm_units.clear()
	for i in range(CHANNELS_SWARM_OFFSETS.size()):
		var swarm := MeshInstance3D.new()
		swarm.name = "ChannelsSwarm_%d" % i
		var swarm_mesh := SphereMesh.new()
		swarm_mesh.radius = 0.3
		swarm_mesh.height = 0.6
		swarm.mesh = swarm_mesh
		var swarm_mat := StandardMaterial3D.new()
		swarm_mat.albedo_color = Color(0.15, 0.12, 0.08)
		swarm_mat.emission_enabled = true
		swarm_mat.emission = Color(0.45, 0.2, 0.06)
		swarm_mat.emission_energy_multiplier = 0.6
		swarm.material_override = swarm_mat
		swarm.position = Vector3(CHANNELS_SWARM_CLUSTER_X + CHANNELS_SWARM_OFFSETS[i], 0.6, 0.5 + sin(float(i)) * 1.2)
		parent.add_child(swarm)
		_channels_swarm_units.append({
			"node": swarm,
			"x": swarm.position.x,
			"target_x": swarm.position.x,
		})

	# Shelter alcove at the far end of the zone.
	_add_corridor_section(parent, Vector3(CHANNELS_SHELTER_POS.x, -0.04, CHANNELS_SHELTER_POS.z), Vector3(16, 0.08, 10), Color(0.07, 0.07, 0.08))
	_add_wall(parent, Vector3(CHANNELS_SHELTER_POS.x, 1.5, CHANNELS_SHELTER_POS.z + 5.0), Vector3(16, 3, 0.3), wall_color)
	_add_wall(parent, Vector3(CHANNELS_SHELTER_POS.x - 8.0, 1.5, CHANNELS_SHELTER_POS.z), Vector3(0.3, 3, 10), wall_color)
	_add_wall(parent, Vector3(CHANNELS_SHELTER_POS.x + 8.0, 1.5, CHANNELS_SHELTER_POS.z), Vector3(0.3, 3, 10), wall_color)
	var shelter_door := MeshInstance3D.new()
	shelter_door.name = "ChannelsShelterDoor"
	var shelter_door_mesh := BoxMesh.new()
	shelter_door_mesh.size = Vector3(2.4, 2.6, 0.18)
	shelter_door.mesh = shelter_door_mesh
	var shelter_door_mat := StandardMaterial3D.new()
	shelter_door_mat.albedo_color = Color(0.22, 0.2, 0.18)
	shelter_door.material_override = shelter_door_mat
	shelter_door.position = CHANNELS_SHELTER_POS + Vector3(0, 1.25, -4.8)
	parent.add_child(shelter_door)
	var shelter_light := OmniLight3D.new()
	shelter_light.position = CHANNELS_SHELTER_POS + Vector3(0, 2.0, 0)
	shelter_light.light_color = Color(0.85, 0.68, 0.42)
	shelter_light.light_energy = 2.1
	shelter_light.omni_range = 12.0
	parent.add_child(shelter_light)

	var shelter_label := Label3D.new()
	shelter_label.name = "ChannelsShelterLabel"
	shelter_label.text = "SHELTER"
	shelter_label.font_size = 28
	shelter_label.pixel_size = 0.008
	shelter_label.modulate = Color(0.92, 0.78, 0.52, 0.85)
	shelter_label.outline_modulate = Color(0, 0, 0, 0.45)
	shelter_label.outline_size = 8
	shelter_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	shelter_label.position = CHANNELS_SHELTER_POS + Vector3(0, 2.6, 0)
	parent.add_child(shelter_label)

	_add_flora_node(
		parent,
		"channels_memory_reed",
		"Memory Reed",
		"channels",
		CHANNELS_BODY_POS + Vector3(-2.2, 0.0, 1.2),
		"memory",
		"client trace",
		CHANNELS_BODY_POS + Vector3(-0.6, 0.0, 0.2),
		Color(0.86, 0.68, 0.38),
		0.76,
		{"tended": true}
	)
	_add_flora_node(
		parent,
		"channels_lumivine",
		"Lumivine",
		"channels",
		CHANNELS_FLURE_POS + Vector3(1.8, 0.0, -1.1),
		"iron",
		"iron bloom",
		CHANNELS_ENCOUNTER_ENTRY_POS + Vector3(3.0, 0.0, -0.6),
		Color(0.48, 0.88, 0.58),
		0.84,
		{"tended": true, "childhood_species": true}
	)
	_add_flora_node(
		parent,
		"channels_shortcut_vine",
		"Shelter Vine",
		"channels",
		CHANNELS_SHORTCUT_BRANCH_POS + Vector3(1.2, 0.0, 2.6),
		"resource",
		"warm shelter trace",
		CHANNELS_SHELTER_POS + Vector3(0.8, 0.0, 0.4),
		Color(0.72, 0.88, 0.52),
		0.68,
		{"tended": true}
	)
	_add_flora_node(
		parent,
		"channels_forget_me_not",
		"Forget-Me-Not",
		"channels",
		CHANNELS_SHELTER_POS + Vector3(-2.6, 0.0, 1.7),
		"relationship",
		"Aster",
		CHANNELS_SHELTER_POS + Vector3(-0.8, 0.0, 0.9),
		Color(0.58, 0.72, 0.95),
		1.0,
		{"role": "relationship", "forget_me_not": true, "tended": true, "childhood_species": true}
	)

	# Shortcut branch: visible from the outer path, locked from this side until the shelter is reached.
	_add_corridor_section(parent, Vector3(CHANNELS_SHORTCUT_BRANCH_POS.x, -0.04, CHANNELS_SHORTCUT_BRANCH_POS.z), Vector3(6, 0.08, 12), Color(0.055, 0.06, 0.075))
	_add_wall(parent, Vector3(CHANNELS_SHORTCUT_BRANCH_POS.x - 3.0, 1.5, CHANNELS_SHORTCUT_BRANCH_POS.z), Vector3(0.3, 3, 12), wall_color)
	_add_wall(parent, Vector3(CHANNELS_SHORTCUT_BRANCH_POS.x + 3.0, 1.5, CHANNELS_SHORTCUT_BRANCH_POS.z), Vector3(0.3, 3, 12), wall_color)
	_add_corridor_section(parent, Vector3((CHANNELS_SHORTCUT_GATE_POS.x + CHANNELS_SHELTER_POS.x) * 0.5, -0.04, CHANNELS_SHELTER_POS.z), Vector3(CHANNELS_SHELTER_POS.x - CHANNELS_SHORTCUT_GATE_POS.x + 6.0, 0.08, 6), Color(0.06, 0.065, 0.08))
	_add_wall(parent, Vector3((CHANNELS_SHORTCUT_GATE_POS.x + CHANNELS_SHELTER_POS.x) * 0.5, 1.5, CHANNELS_SHELTER_POS.z - 3.0), Vector3(CHANNELS_SHELTER_POS.x - CHANNELS_SHORTCUT_GATE_POS.x + 6.0, 3, 0.3), wall_color)
	_add_wall(parent, Vector3((CHANNELS_SHORTCUT_GATE_POS.x + CHANNELS_SHELTER_POS.x) * 0.5, 1.5, CHANNELS_SHELTER_POS.z + 3.0), Vector3(CHANNELS_SHELTER_POS.x - CHANNELS_SHORTCUT_GATE_POS.x + 6.0, 3, 0.3), wall_color)

	_channels_shortcut_gate_mesh = MeshInstance3D.new()
	_channels_shortcut_gate_mesh.name = "ChannelsShortcutGate"
	var shortcut_gate_mesh := BoxMesh.new()
	shortcut_gate_mesh.size = Vector3(6.0, 2.6, 0.18)
	_channels_shortcut_gate_mesh.mesh = shortcut_gate_mesh
	var shortcut_gate_mat := StandardMaterial3D.new()
	shortcut_gate_mat.albedo_color = Color(0.22, 0.26, 0.3)
	shortcut_gate_mat.metallic = 0.2
	shortcut_gate_mat.roughness = 0.7
	_channels_shortcut_gate_mesh.material_override = shortcut_gate_mat
	_channels_shortcut_gate_mesh.position = CHANNELS_SHORTCUT_GATE_POS + Vector3(0, 1.25, 0)
	parent.add_child(_channels_shortcut_gate_mesh)

	var shortcut_gate_body := StaticBody3D.new()
	shortcut_gate_body.name = "ChannelsShortcutGateBody"
	shortcut_gate_body.position = CHANNELS_SHORTCUT_GATE_POS + Vector3(0, 1.25, 0)
	var shortcut_gate_shape := CollisionShape3D.new()
	var shortcut_gate_box := BoxShape3D.new()
	shortcut_gate_box.size = Vector3(6.0, 2.6, 0.2)
	shortcut_gate_shape.shape = shortcut_gate_box
	shortcut_gate_body.add_child(shortcut_gate_shape)
	parent.add_child(shortcut_gate_body)
	_channels_shortcut_gate_collision = shortcut_gate_shape

	_channels_shortcut_light = OmniLight3D.new()
	_channels_shortcut_light.position = CHANNELS_SHORTCUT_GATE_POS + Vector3(0, 2.0, 0.8)
	parent.add_child(_channels_shortcut_light)
	_set_channels_shortcut_unlocked(false)

	var shortcut_table := MeshInstance3D.new()
	var shortcut_table_mesh := BoxMesh.new()
	shortcut_table_mesh.size = Vector3(2.0, 0.18, 1.0)
	shortcut_table.mesh = shortcut_table_mesh
	var shortcut_table_mat := StandardMaterial3D.new()
	shortcut_table_mat.albedo_color = Color(0.28, 0.24, 0.2)
	shortcut_table.material_override = shortcut_table_mat
	shortcut_table.position = CHANNELS_SHELTER_POS + Vector3(-2.8, 0.85, 1.4)
	parent.add_child(shortcut_table)

	var shortcut_bowl := MeshInstance3D.new()
	var shortcut_bowl_mesh := SphereMesh.new()
	shortcut_bowl_mesh.radius = 0.22
	shortcut_bowl_mesh.height = 0.16
	shortcut_bowl.mesh = shortcut_bowl_mesh
	var shortcut_bowl_mat := StandardMaterial3D.new()
	shortcut_bowl_mat.albedo_color = Color(0.7, 0.58, 0.4)
	shortcut_bowl.material_override = shortcut_bowl_mat
	shortcut_bowl.position = CHANNELS_SHELTER_POS + Vector3(-2.5, 1.03, 1.35)
	parent.add_child(shortcut_bowl)

	var shelter_heater := MeshInstance3D.new()
	var shelter_heater_mesh := BoxMesh.new()
	shelter_heater_mesh.size = Vector3(0.8, 0.9, 0.5)
	shelter_heater.mesh = shelter_heater_mesh
	var shelter_heater_mat := StandardMaterial3D.new()
	shelter_heater_mat.albedo_color = Color(0.34, 0.22, 0.14)
	shelter_heater_mat.emission_enabled = true
	shelter_heater_mat.emission = Color(0.95, 0.46, 0.18)
	shelter_heater_mat.emission_energy_multiplier = 0.35
	shelter_heater.material_override = shelter_heater_mat
	shelter_heater.position = CHANNELS_SHELTER_POS + Vector3(3.4, 0.45, 2.0)
	parent.add_child(shelter_heater)

	# Lighting spans the corridor.
	for i in range(5):
		var light := OmniLight3D.new()
		light.position = Vector3(sx + 20.0 + i * 45.0, 2.5, 0)
		light.light_color = Color(0.2, 0.25, 0.4)
		light.light_energy = 1.5
		light.omni_range = 20.0
		parent.add_child(light)

	# Warm lights near stagnant zones
	for i in range(3):
		var sl := OmniLight3D.new()
		sl.position = Vector3(sx + 50.0 + i * 60.0, 2.0, 12.0 if i % 2 == 0 else -12.0)
		sl.light_color = Color(0.5, 0.25, 0.1)
		sl.light_energy = 1.0
		sl.omni_range = 8.0
		parent.add_child(sl)

	# Long-form play sits on the same measured hydraulic grammar as the shared decoration pass:
	# macro-scale operation rooms establish the six spatial reads; structural bay frames, thin floor
	# datums, and role-readable instruments carry the local evidence without collision clutter.
	_build_channels_operation_landmarks(parent)
	_build_channels_fieldwork(parent)

func headless_get_anchor_positions() -> Dictionary:
	var anchors := {
		"channels_body": CHANNELS_BODY_POS,
		"channels_window_one_stage": CHANNELS_WINDOW_ONE_STAGE_POS,
		"channels_window_one_lure": CHANNELS_WINDOW_ONE_LURE_POS,
		"channels_window_one_curtain": CHANNELS_WINDOW_ONE_CURTAIN_POS,
		"channels_window_one_goal": CHANNELS_WINDOW_ONE_GOAL_POS,
		"channels_flure": CHANNELS_FLURE_POS,
		"channels_window_two_stage": CHANNELS_WINDOW_TWO_STAGE_POS,
		"channels_window_two_lure": CHANNELS_WINDOW_TWO_LURE_POS,
		"channels_window_two_curtain": CHANNELS_WINDOW_TWO_CURTAIN_POS,
		"channels_window_two_goal": CHANNELS_WINDOW_TWO_GOAL_POS,
		"channels_run_lure": CHANNELS_RUN_LURE_POS,
		"channels_encounter_entry": CHANNELS_ENCOUNTER_ENTRY_POS,
		"channels_hide_spot": CHANNELS_HIDE_SPOT_POS,
		"channels_shelter": CHANNELS_SHELTER_POS,
		"channels_shortcut_gate": CHANNELS_SHORTCUT_GATE_POS,
		"channels_shortcut_branch": CHANNELS_SHORTCUT_BRANCH_POS,
		"stacks_signal_wall": _stacks_signal_interactable.global_position if is_instance_valid(_stacks_signal_interactable) else Vector3(STACKS_START.x + 96.0, 1.0, -16.9),
		"stacks_terminal": _stacks_terminal_interactable.global_position if is_instance_valid(_stacks_terminal_interactable) else Vector3(STACKS_START.x + 88.0, 1.0, 0.0),
		"stacks_workspace": _stacks_workspace_interactable.global_position if is_instance_valid(_stacks_workspace_interactable) else Vector3(STACKS_START.x + 165.0, 1.0, -10.0),
		"stacks_drink_machine": Vector3(STACKS_START.x + 132.0, 0.9, 14.0),
		"rings_client_bloom": _flora_nodes["rings_client_bloom"].get("position", Vector3(RINGS_START.x + 76.0, 0.0, -8.0)) if _flora_nodes.has("rings_client_bloom") else Vector3(RINGS_START.x + 76.0, 0.0, -8.0),
		"rings_forget_me_not": _flora_nodes["rings_forget_me_not"].get("position", Vector3(RINGS_START.x + 116.0, 0.0, 13.8)) if _flora_nodes.has("rings_forget_me_not") else Vector3(RINGS_START.x + 116.0, 0.0, 13.8),
		"rings_doorvine": _flora_nodes["rings_doorvine"].get("position", Vector3(RINGS_START.x + 156.0, 0.0, 8.5)) if _flora_nodes.has("rings_doorvine") else Vector3(RINGS_START.x + 156.0, 0.0, 8.5),
		"lockout_access_panel": LOCKOUT_BOUNDARY + Vector3(-1.5, 0.75, 0.0),
		"lockout_escape_trigger": Vector3(LOCKOUT_START.x - 11.0, 0.5, 0.0),
	}
	for window_id in _channels_window_lanes.keys():
		var lane: Dictionary = _channels_window_lanes[window_id]
		anchors["channels_%s_swarm_start" % window_id] = lane.get("swarm_start_pos", Vector3.ZERO)
	for site_id in CHANNELS_FIELD_SITES.keys():
		anchors["channels_field_%s" % site_id] = _channels_field_site_position(str(site_id))
	for site_id in CHANNELS_OPTIONAL_SITES.keys():
		anchors["channels_optional_%s" % site_id] = _channels_field_site_position(str(site_id))
	return anchors

func headless_get_state() -> Dictionary:
	var state := super.headless_get_state()
	var atp := {}
	var lane_state := {}
	var journal: Node = get_node_or_null("/root/EngramJournal")
	var support_log: Dictionary = {}
	var flora_state := _flora_system.get_debug_state(
		_scheduler.get_current_tick() if _scheduler else 0.0,
		_current_flora_zone()
	)
	flora_state["visible_clue_count"] = int(flora_state.get("visible_clues", []).size())
	if _game_state:
		for char_id in ["aster", "peris", "endo"]:
			if _game_state.characters.has(char_id):
				atp[char_id] = float(_game_state.characters[char_id].stats.get("atp", 0.0))
	for window_id in _channels_window_lanes.keys():
		var lane: Dictionary = _channels_window_lanes[window_id]
		var channel_states: Array = []
		var visible_swarm_units := 0
		var washed_swarm_units := 0
		var current_tick := _scheduler.get_current_tick() if _scheduler else 0.0
		for channel_variant in lane.get("periodic_channels", []):
			var channel: Dictionary = channel_variant
			channel_states.append({
				"position": channel.get("position", Vector3.ZERO),
				"contact_time": float(channel.get("contact_time", 0.0)),
				"phase_offset": float(channel.get("phase_offset", 0.0)),
				"local_phase": float(channel.get("local_phase", _channels_window_local_phase(current_tick, lane, channel))),
				"level": float(channel.get("level", 0.0)),
				"flooded": bool(channel.get("flooded", false)),
			})
		for unit_variant in lane.get("swarm_units", []):
			var unit: Dictionary = unit_variant
			var node = unit.get("node")
			if is_instance_valid(node) and node.visible:
				visible_swarm_units += 1
			if str(unit.get("state", "")) == "washed":
				washed_swarm_units += 1
		lane_state[window_id] = {
			"phase": str(lane.get("phase", "")),
			"last_outcome": str(lane.get("last_outcome", "")),
			"lure_active": bool(lane.get("lure_active", false)),
			"safe_until_tick": float(lane.get("safe_until_tick", -1.0)),
			"flow_offset": float(lane.get("flow_offset", 0.0)),
			"periodic_channel_count": int(lane.get("periodic_channels", []).size()),
			"bridge_segment_count": int(lane.get("bridge_segments", []).size()),
			"corpse_count": int(lane.get("corpse_nodes", []).size()),
			"swarm_unit_count": int(lane.get("swarm_units", []).size()),
			"visible_swarm_units": visible_swarm_units,
			"washed_swarm_units": washed_swarm_units,
			"swarm_state": str(lane.get("swarm_state", "")),
			"washed_channel_index": int(lane.get("washed_channel_index", -1)),
			"wash_analysis": lane.get("wash_analysis", {}),
			"channels": channel_states,
		}
	if journal != null:
		if _stacks_support_log_entry_id != -1:
			support_log = journal.get_entry(_stacks_support_log_entry_id)
		if support_log.is_empty():
			support_log = journal.get_entry_by_story_key(STACKS_SUPPORT_LOG_KEY)
	state["active_character"] = _active_character
	state["channels_active_window_lane"] = _channels_active_window_lane
	state["channels_shortcut_unlocked"] = _channels_shortcut_unlocked
	state["channels_party_recuperated"] = _channels_party_recuperated
	state["channels_shelter_reached"] = _channels_shelter_reached
	state["channels_flow_power"] = _channels_flow_power
	state["channels_flush_state"] = _channels_flush_state
	state["channels_window_lanes"] = lane_state
	state["channels_run_lure_active"] = _channels_run_lure_active
	state["channels_party_hidden"] = _channels_party_hidden
	state["channels_hp"] = {
		"aster": _aster_hp,
		"peris": _peris_hp,
	}
	state["channels_atp"] = atp
	state["channels_fieldwork"] = {
		"phase": _channels_field_phase,
		"completed_evidence": _channels_field_completed.duplicate(true),
		"operations_completed": _channels_field_operations_completed.duplicate(true),
		"operation_count": _channels_field_operations_completed.size(),
		"choices": _channels_field_choices.duplicate(true),
		"attempts": _channels_field_attempts.duplicate(true),
		"decision_count": _channels_field_decisions,
		"optional_findings": _channels_optional_findings.duplicate(true),
		"optional_count": _channels_optional_findings.size(),
		"playtime_contract": get_channels_playtime_contract(),
	}
	state["overlay_states"] = _overlay_states.duplicate(true)
	state["stacks"] = {
		"support_log_presented": _stacks_support_log_presented,
		"signal_interacted": _stacks_signal_interacted,
		"terminal_interacted": _stacks_terminal_interacted,
		"archive_interacted": _stacks_archive_interacted,
		"audit_flags_found": _stacks_audit_flags_found,
		"bank_samples": _stacks_bank_samples.keys(),
		"bank_resolved": _stacks_bank_resolved,
		"bank_attempts": _stacks_bank_attempts,
		"fieldwork": {
			"phase": _stacks_field_phase,
			"completed_evidence": _stacks_field_completed.duplicate(true),
			"operations_completed": _stacks_field_operations_completed.duplicate(true),
			"operation_count": _stacks_field_operations_completed.size(),
			"choices": _stacks_field_choices.duplicate(true),
			"effects": _stacks_field_effects.duplicate(true),
			"decision_count": _stacks_field_decisions,
			"playtime_contract": get_stacks_playtime_contract(),
		},
		"engram": {
			"entry_count": journal.get_entry_count() if journal != null else 0,
			"story_key": str(support_log.get("story_key", "")),
			"overlay_visible": _engram_overlay != null and _engram_overlay.visible,
		},
	}
	state["rings"] = {
		"endo_visible": _endo != null and _endo.visible,
		"peris_overlay_enabled": bool(_overlay_states.get("peris", false)),
		"client_seen": _rings_client_seen,
		"trace_seen": _rings_trace_seen.duplicate(true),
		"trace_count": _rings_trace_seen.size(),
		"fieldwork": {
			"phase": _rings_field_phase,
			"completed_evidence": _rings_field_completed.duplicate(true),
			"operations_completed": _rings_field_operations_completed.duplicate(true),
			"operation_count": _rings_field_operations_completed.size(),
			"choices": _rings_field_choices.duplicate(true),
			"effects": _rings_field_effects.duplicate(true),
			"decision_count": _rings_field_decisions,
			"playtime_contract": get_rings_playtime_contract(),
		},
	}
	var lockout_state := {
		"naturalizer_count": _naturalizers.size(),
		"boundary_crossed": _aster_node != null and _aster_node.global_position.x < LOCKOUT_START.x - 10.0,
		"campaign_chase_active": _lockout_chase_active,
	}
	if _lockout_chase_chunk != null and is_instance_valid(_lockout_chase_chunk) \
			and _lockout_chase_chunk.has_method("get_preview_state"):
		lockout_state.merge(_lockout_chase_chunk.call("get_preview_state"), true)
	state["lockout"] = lockout_state
	state["flora"] = flora_state
	return state

func headless_select_character(char_id: String) -> void:
	_select_character(char_id)

func headless_set_overlay_state(overlay_id: String, enabled: bool) -> void:
	if not _overlay_states.has(overlay_id):
		return
	_overlay_states[overlay_id] = enabled
	_refresh_overlay_button(overlay_id)
	_apply_overlay_visibility()

func headless_set_character_position(char_id: String, pos: Vector3) -> void:
	var node := _get_character_node(char_id)
	if node == null:
		return
	if _game_state and _game_state.characters.has(char_id):
		_game_state.command_stop(char_id)
		_game_state.characters[char_id].position = pos
	node.global_position = pos

# Shared front-half of every prepare_*_fragment entry point: wipe the transient UI/scheduler
# state and swap the named chunk in (load it, unload the others, activate its grid). Every
# fragment — channels included — initializes through this one path.
func _begin_fragment_prep(chunk_name: String) -> void:
	if _dialogue and _dialogue.has_method("clear"):
		_dialogue.clear()
	if _scheduler:
		_scheduler.clear()
	_clear_markers()
	_tutorial_prompt.hide_prompt()
	_swap_to_chunk(chunk_name)

# Load the named chunk, unload every other act1 chunk so only one is live (act1 cuts between
# chunks), and swap the live grid to this chunk's footprint. This is the SINGLE way a chunk is
# made current — the in-game enter beats and the prepare_*_fragment jump-ins both go through it,
# so a chunk is always initialized the same way. Unloading an already-unloaded chunk is a no-op,
# so it is safe from any starting state.
func _swap_to_chunk(chunk_name: String) -> void:
	_load_chunk(chunk_name)
	for other in CHUNK_GRIDS.keys():
		if other != chunk_name:
			_unload_chunk(other)
	_activate_chunk_grid(chunk_name)

# Halt the whole party so a fragment can reposition them cleanly.
func _stop_party() -> void:
	if _game_state == null:
		return
	for cid in ["aster", "peris", "endo"]:
		if _game_state.characters.has(cid):
			_game_state.command_stop(cid)

func prepare_channels_fragment() -> void:
	_begin_fragment_prep("channels")
	_reset_channels_fieldwork_state()
	_channels_active_window_lane = ""
	for window_id in _channels_window_lanes.keys():
		_reset_channels_window_lane(window_id)
	_reset_channels_encounter_nodes()
	_stop_party()
	_current_step = ""
	_select_character("aster")
	_player.set_move_enabled(true)

func prepare_stacks_fragment(mode: String = "engram") -> void:
	_begin_fragment_prep("stacks")
	_clear_channels_runtime_state()
	_reset_stacks_runtime_state()
	var journal: Node = get_node_or_null("/root/EngramJournal")
	if journal != null:
		journal.reset_state(false)
	_select_character("aster")
	_player.global_position = STACKS_START + Vector3(5.0, 0.5, 0.0)
	_player.set_move_enabled(true)
	match mode:
		"signal":
			_start_stacks_signal()
		"terminal":
			_start_stacks_terminal()
		"archive":
			_start_stacks_archive()
		"explore":
			_start_stacks_explore()
		_:
			_enter_step("stacks_enter")
			_player.set_move_enabled(false)

func prepare_rings_fragment(mode: String = "client") -> void:
	_begin_fragment_prep("rings")
	_clear_lockout_runtime_state()
	_endo.visible = true
	_stop_party()
	headless_set_character_position("aster", RINGS_START + Vector3(8.0, 0.5, 0.0))
	headless_set_character_position("peris", RINGS_START + Vector3(6.5, 0.5, 2.0))
	headless_set_character_position("endo", RINGS_START + Vector3(5.0, 0.5, -1.8))
	requested_scene_change = ""
	match mode:
		"explore":
			_endo.visible = false
			_select_character("aster")
			_start_rings_explore()
		_:
			_select_character("peris")
			_enter_step("rings_client")
			_player.set_move_enabled(true)

func prepare_lockout_fragment(mode: String = "chase") -> void:
	_begin_fragment_prep("lockout")
	_clear_lockout_runtime_state()
	_endo.visible = true
	_stop_party()
	headless_set_character_position("aster", LOCKOUT_BOUNDARY + Vector3(-7.5, 0.5, 0.0))
	headless_set_character_position("peris", LOCKOUT_BOUNDARY + Vector3(-9.0, 0.5, 1.4))
	headless_set_character_position("endo", LOCKOUT_BOUNDARY + Vector3(-10.5, 0.5, -1.4))
	requested_scene_change = ""
	_select_character("aster")
	match mode:
		"approach":
			_enter_step("lockout_approach")
			_player.set_move_enabled(false)
		"rejected":
			_enter_step("lockout_rejected")
			_player.set_move_enabled(false)
		_:
			_enter_step("lockout_chase")
			_player.set_move_enabled(true)
			_tutorial_prompt.show_prompt("Run!")
			_spawn_lockout_naturalizers()

func start_channels_window_puzzle(window_id: String) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	prepare_channels_fragment()
	var party_positions := _get_channels_window_party_positions(window_id)
	for char_id in party_positions.keys():
		headless_set_character_position(char_id, party_positions[char_id])
	_begin_channels_window_lane(window_id)

func activate_channels_window_lure(window_id: String) -> void:
	_on_channels_window_lure_activated(window_id)

func set_channels_window_flow_offset(window_id: String, offset: float) -> void:
	if not _channels_window_lanes.has(window_id):
		return
	var lane: Dictionary = _channels_window_lanes[window_id]
	lane["flow_offset"] = offset
	_channels_window_lanes[window_id] = lane

func get_channels_window_wash_analysis(window_id: String) -> Dictionary:
	if not _channels_window_lanes.has(window_id):
		return {}
	return _channels_window_lanes[window_id].get("wash_analysis", {})

func _district_field_role_color(role: String) -> Color:
	match role:
		"aster": return Color(0.38, 0.72, 1.0)
		"peris": return Color(0.50, 0.88, 0.58)
		"endo": return Color(0.96, 0.67, 0.30)
		_: return Color(0.78, 0.82, 0.86)

func _add_district_field_station_visual(site: Node3D, district: String, site_id: String, spec: Dictionary) -> Node3D:
	var assembly := Node3D.new()
	assembly.name = "%sFieldAssembly_%s" % [district.capitalize(), site_id]
	site.add_child(assembly)
	var role := str(spec.get("role", ""))
	var role_color := _district_field_role_color(role)
	var operation: Dictionary = _district_operations(district)[str(spec.get("operation", ""))]
	var tint: Color = operation.get("tint", role_color)
	var kind := str(spec.get("kind", "evidence"))
	var base_material := StandardMaterial3D.new()
	base_material.albedo_color = Color(0.07, 0.08, 0.09).lerp(role_color.darkened(0.42), 0.34)
	base_material.metallic = 0.42
	base_material.roughness = 0.58
	var glow_material := StandardMaterial3D.new()
	glow_material.albedo_color = tint.darkened(0.35)
	glow_material.emission_enabled = true
	glow_material.emission = tint
	glow_material.emission_energy_multiplier = 0.95 if kind != "evidence" else 0.55
	glow_material.roughness = 0.44

	var footing := MeshInstance3D.new()
	footing.name = "MeasuredFooting"
	var footing_mesh := CylinderMesh.new()
	footing_mesh.top_radius = 0.46 if kind == "evidence" else 0.58
	footing_mesh.bottom_radius = 0.60 if kind == "evidence" else 0.72
	footing_mesh.height = 0.22
	footing.mesh = footing_mesh
	footing.material_override = base_material
	footing.position.y = 0.11
	assembly.add_child(footing)

	var body := MeshInstance3D.new()
	body.name = "InstrumentBody"
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.54 if kind == "evidence" else 0.72, 1.05, 0.52)
	body.mesh = body_mesh
	body.material_override = base_material
	body.position.y = 0.74
	assembly.add_child(body)

	var face := MeshInstance3D.new()
	face.name = "InstrumentReadout"
	var face_mesh := BoxMesh.new()
	face_mesh.size = Vector3(0.42 if kind == "evidence" else 0.58, 0.28, 0.06)
	face.mesh = face_mesh
	face.material_override = glow_material
	face.position = Vector3(0.0, 0.94, -0.29)
	assembly.add_child(face)

	match role:
		"aster":
			var vane := MeshInstance3D.new()
			vane.name = "DataVane"
			var vane_mesh := BoxMesh.new()
			vane_mesh.size = Vector3(0.08, 0.62, 0.42)
			vane.mesh = vane_mesh
			vane.material_override = glow_material
			vane.position = Vector3(0, 1.48, 0)
			vane.rotation_degrees.z = 22.0
			assembly.add_child(vane)
		"peris":
			for fork_x in [-0.15, 0.15]:
				var fork := MeshInstance3D.new()
				fork.name = "LivingFork"
				var fork_mesh := CylinderMesh.new()
				fork_mesh.top_radius = 0.04
				fork_mesh.bottom_radius = 0.065
				fork_mesh.height = 0.68
				fork.mesh = fork_mesh
				fork.material_override = glow_material
				fork.position = Vector3(float(fork_x), 1.49, 0)
				fork.rotation_degrees.z = -15.0 if float(fork_x) < 0.0 else 15.0
				assembly.add_child(fork)
		"endo":
			var brace := MeshInstance3D.new()
			brace.name = "BraceBar"
			var brace_mesh := BoxMesh.new()
			brace_mesh.size = Vector3(0.88, 0.12, 0.14)
			brace.mesh = brace_mesh
			brace.material_override = glow_material
			brace.position = Vector3(0, 1.48, 0)
			brace.rotation_degrees.z = -12.0
			assembly.add_child(brace)

	var label := Label3D.new()
	label.name = "MeasuredLabel"
	label.text = "%s // %s" % [role.to_upper(), str(spec.get("display", site_id)).to_upper()]
	label.font_size = 30
	label.pixel_size = 0.0072
	label.modulate = tint.lightened(0.22)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	label.outline_size = 9
	label.position = Vector3(0, 2.05, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	assembly.add_child(label)
	return assembly

func _bind_district_field_site_outline(site: Node3D, assembly: Node3D, district: String, site_id: String) -> void:
	if not is_instance_valid(site) or not is_instance_valid(assembly):
		return
	var target := _outline_object_meshes(
		site, "%sFieldOutline_%s" % [district.capitalize(), site_id], _collect_mesh_instances(assembly),
		"%s.field.%s" % [district, site_id], 0.82
	)
	_set_room_target_interaction_delegate(target, site)

func _spawn_district_field_site(parent: Node3D, district: String, site_id: String, spec: Dictionary) -> void:
	var role := str(spec.get("role", ""))
	var data_id := "%sField_%s" % [district.capitalize(), site_id]
	var site = InteractableFactory.spawn(
		_game_state, parent, data_id,
		{
			"position": spec.get("pos", Vector3.ZERO),
			"radius": 1.45,
			"hold_time": float(spec.get("dwell", 5.4)),
			"one_shot": false,
			"requires_hold": false,
			"required_character": role,
			"tutorial_label": str(spec.get("verb", "INSPECT")),
			"description": str(spec.get("display", site_id)),
			"enabled": false,
		},
		_scheduler, _dialogue, _active_character
	)
	site.set("interactable_type", Interactable.InteractableType.TIMED_ACTION)
	site.set("required_character", role)
	site.set("selected_feedback_color", _district_field_role_color(role))
	site.set("outline_highlight_radius", 1.3)
	site.set_interaction_enabled(false)
	site.interacted.connect(Callable(self, "_on_district_field_site_interacted").bind(district, site_id))
	site.interaction_requested.connect(Callable(self, "_on_district_field_route_requested").bind(district, site_id))
	register_preview_interactable(site)
	var assembly := _add_district_field_station_visual(site, district, site_id, spec)
	_district_site_nodes(district)[site_id] = site
	_district_site_visuals(district)[site_id] = assembly
	call_deferred("_bind_district_field_site_outline", site, assembly, district, site_id)

func _add_district_field_datum(parent: Node3D, district: String, datum_name: String, from_pos: Vector3, to_pos: Vector3, color: Color) -> void:
	var flat_from := Vector3(from_pos.x, 0.034, from_pos.z)
	var flat_to := Vector3(to_pos.x, 0.034, to_pos.z)
	var length := flat_from.distance_to(flat_to)
	if length <= 0.1:
		return
	var datum := MeshInstance3D.new()
	datum.name = "%sFieldDatum_%s" % [district.capitalize(), datum_name]
	var datum_mesh := BoxMesh.new()
	datum_mesh.size = Vector3(0.07, 0.018, length)
	datum.mesh = datum_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color, 0.72)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.42
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	datum.material_override = material
	datum.position = (flat_from + flat_to) * 0.5
	datum.look_at_from_position(datum.position, flat_to, Vector3.UP, true)
	parent.add_child(datum)

func _add_district_field_frame(parent: Node3D, district: String, operation_id: String, operation_index: int) -> void:
	var operation: Dictionary = _district_operations(district)[operation_id]
	var frame_x := float(operation.get("frame_x", 0.0))
	var tint: Color = operation.get("tint", Color.WHITE)
	var half_width := 17.8 if district == "stacks" else 21.8
	var root := Node3D.new()
	root.name = "%sFieldFrame_%s" % [district.capitalize(), operation_id]
	parent.add_child(root)
	var frame_material := StandardMaterial3D.new()
	frame_material.albedo_color = Color(0.22, 0.24, 0.23)
	frame_material.metallic = 0.38
	frame_material.roughness = 0.66
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.name = "MeasuredPost"
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.28, 3.2, 0.36)
		post.mesh = post_mesh
		post.material_override = frame_material
		post.position = Vector3(frame_x, 1.6, float(side) * half_width)
		root.add_child(post)
	var header := MeshInstance3D.new()
	header.name = "MeasuredHeader"
	var header_mesh := BoxMesh.new()
	header_mesh.size = Vector3(0.34, 0.24, half_width * 2.0)
	header.mesh = header_mesh
	header.material_override = frame_material
	header.position = Vector3(frame_x, 3.12, 0.0)
	root.add_child(header)
	var sign := Label3D.new()
	sign.name = "OperationSign"
	sign.text = "%02d // %s" % [operation_index + 1, str(operation.get("label", operation_id))]
	sign.font_size = 34
	sign.pixel_size = 0.0075
	sign.modulate = tint.lightened(0.2)
	sign.outline_modulate = Color(0, 0, 0, 0.94)
	sign.outline_size = 9
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = Vector3(frame_x, 2.55, -half_width + 0.25)
	root.add_child(sign)
	var light := OmniLight3D.new()
	light.name = "%sFieldLight_%s" % [district.capitalize(), operation_id]
	light.position = Vector3(frame_x, 3.1, 0.0)
	light.light_color = tint
	light.light_energy = 0.9
	light.omni_range = 10.0
	light.shadow_enabled = false
	root.add_child(light)

func _build_district_fieldwork(parent: Node3D, district: String) -> void:
	_district_site_nodes(district).clear()
	_district_site_visuals(district).clear()
	_district_route_visuals(district).clear()
	var root := Node3D.new()
	root.name = "%sFieldwork" % district.capitalize()
	parent.add_child(root)
	var operation_index := 0
	for operation_id_variant in _district_operations(district).keys():
		var operation_id := str(operation_id_variant)
		var operation: Dictionary = _district_operations(district)[operation_id]
		_add_district_field_frame(root, district, operation_id, operation_index)
		var route_root := Node3D.new()
		route_root.name = "%sFieldRoute_%s" % [district.capitalize(), operation_id]
		route_root.visible = false
		root.add_child(route_root)
		_district_route_visuals(district)[operation_id] = route_root
		var points: Array = [operation.get("start", Vector3.ZERO)]
		for evidence_id in operation.get("evidence", []):
			points.append(_district_site_specs(district)[str(evidence_id)].get("pos", Vector3.ZERO))
		for point_i in range(points.size() - 1):
			_add_district_field_datum(route_root, district, "%s_read_%02d" % [operation_id, point_i], points[point_i], points[point_i + 1], operation.get("tint", Color.WHITE))
		var last_evidence: Vector3 = points[-1]
		for choice_id_variant in operation.get("choices", []):
			var choice_id := str(choice_id_variant)
			var choice_pos: Vector3 = _district_site_specs(district)[choice_id].get("pos", Vector3.ZERO)
			var resolution_id := str((operation.get("resolution_sites", {}) as Dictionary).get(choice_id, ""))
			var resolution_pos: Vector3 = _district_site_specs(district)[resolution_id].get("pos", Vector3.ZERO)
			_add_district_field_datum(route_root, district, "%s_%s_plan" % [operation_id, choice_id], last_evidence, choice_pos, operation.get("tint", Color.WHITE))
			_add_district_field_datum(route_root, district, "%s_%s_execute" % [operation_id, choice_id], choice_pos, resolution_pos, operation.get("tint", Color.WHITE))
			_add_district_field_datum(route_root, district, "%s_%s_exit" % [operation_id, choice_id], resolution_pos, operation.get("end", Vector3.ZERO), operation.get("tint", Color.WHITE))
		operation_index += 1
	for site_id_variant in _district_site_specs(district).keys():
		var site_id := str(site_id_variant)
		_spawn_district_field_site(root, district, site_id, _district_site_specs(district)[site_id])

func _add_stacks_audit_bank(
	parent: Node3D,
	bank_id: String,
	position: Vector3,
	status_text: String,
	status_color: Color
) -> void:
	var housing := MeshInstance3D.new()
	housing.name = "StacksAuditHousing_%s" % bank_id
	var housing_mesh := BoxMesh.new()
	housing_mesh.size = Vector3(2.6, 2.2, 1.2)
	housing.mesh = housing_mesh
	var housing_material := StandardMaterial3D.new()
	housing_material.albedo_color = Color(0.07, 0.08, 0.1)
	housing.material_override = housing_material
	housing.position = position + Vector3(0.0, 1.1, 0.0)
	parent.add_child(housing)

	var display := MeshInstance3D.new()
	var display_mesh := BoxMesh.new()
	display_mesh.size = Vector3(1.9, 0.55, 0.08)
	display.mesh = display_mesh
	var display_material := StandardMaterial3D.new()
	display_material.albedo_color = status_color.darkened(0.55)
	display_material.emission_enabled = true
	display_material.emission = status_color
	display_material.emission_energy_multiplier = 0.85 if bank_id == STACKS_GHOST_BANK else 0.35
	display.material_override = display_material
	display.position = position + Vector3(0.0, 1.35, 0.64)
	parent.add_child(display)

	var label := Label3D.new()
	label.text = status_text
	label.font_size = 24
	label.pixel_size = 0.008
	label.modulate = status_color
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.7)
	label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = position + Vector3(0.0, 2.65, 0.0)
	parent.add_child(label)

	var interactable = preload("res://scenes/game/interactable.tscn").instantiate()
	interactable.name = "StacksAudit_%s" % bank_id
	interactable.description = status_text
	interactable.dialogue_box = _dialogue
	interactable.active_character = "aster"
	interactable.required_character = "aster"
	interactable.one_shot = false
	interactable.dwell_time = 1.2
	interactable.position = position + Vector3(0.0, 0.5, 0.0)
	interactable.tutorial_label = "COMPARE"
	interactable.interacted.connect(trigger_stacks_bank.bind(bank_id))
	parent.add_child(interactable)
	register_preview_interactable(interactable)
	_stacks_bank_interactables[bank_id] = interactable

func _build_stacks_chunk(parent: Node3D) -> void:
	var sx := STACKS_START.x
	var length := 220.0
	var width := 40.0
	var floor_color := Color(0.05, 0.05, 0.06)
	var wall_color := Color(0.07, 0.07, 0.09)

	# Ground + collision
	_add_corridor_section(parent, Vector3(sx + length / 2.0, -0.05, 0), Vector3(length, 0.1, width), floor_color)
	var gb := StaticBody3D.new()
	gb.position = Vector3(sx + length / 2.0, -0.01, 0)
	gb.collision_layer = 1
	gb.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(length, 0.02, width)
	gc.shape = gs
	gb.add_child(gc)
	parent.add_child(gb)

	_add_wall(parent, Vector3(sx + length / 2.0, 2.5, -width / 2.0), Vector3(length, 5, 0.3), wall_color)
	_add_wall(parent, Vector3(sx + length / 2.0, 2.5, width / 2.0), Vector3(length, 5, 0.3), wall_color)

	# Dense rack grid creates corridors.
	for row in range(5):
		for col in range(12):
			var rack := MeshInstance3D.new()
			var rb := BoxMesh.new()
			rb.size = Vector3(1.0, 3.0, 5.0)
			rack.mesh = rb
			var rm := StandardMaterial3D.new()
			rm.albedo_color = Color(0.06, 0.06, 0.08)
			rm.metallic = 0.3
			rack.material_override = rm
			rack.position = Vector3(sx + 15 + col * 16.0, 1.5, -12.0 + row * 6.0)
			parent.add_child(rack)

	# Terminal interactable (midway through the stacks)
	var terminal = preload("res://scenes/game/interactable.tscn").instantiate()
	terminal.name = "DataTerminal"
	terminal.description = "Maintenance Terminal"
	terminal.dialogue_box = _dialogue
	terminal.active_character = "aster"
	terminal.one_shot = true
	terminal.dwell_time = 1.3
	terminal.position = Vector3(sx + length * 0.4, 1.0, 0)
	terminal.tutorial_label = "READ"
	terminal.interacted.connect(trigger_stacks_terminal.bind(true))
	parent.add_child(terminal)
	_stacks_terminal_interactable = terminal

	# Sensor panels and cable bundles - the space reads as maintained instead of abandoned.
	for x_offset in [72.0, 84.0, 108.0]:
		var panel := MeshInstance3D.new()
		var panel_mesh := BoxMesh.new()
		panel_mesh.size = Vector3(3.4, 2.2, 0.16)
		panel.mesh = panel_mesh
		var panel_mat := StandardMaterial3D.new()
		panel_mat.albedo_color = Color(0.08, 0.1, 0.12)
		panel_mat.emission_enabled = true
		panel_mat.emission = Color(0.18, 0.34, 0.42)
		panel_mat.emission_energy_multiplier = 0.35
		panel.material_override = panel_mat
		panel.position = Vector3(sx + x_offset, 1.8, -width / 2.0 + 1.4)
		parent.add_child(panel)

		var cable := MeshInstance3D.new()
		var cable_mesh := CylinderMesh.new()
		cable_mesh.top_radius = 0.08
		cable_mesh.bottom_radius = 0.08
		cable_mesh.height = 4.8
		cable.mesh = cable_mesh
		var cable_mat := StandardMaterial3D.new()
		cable_mat.albedo_color = Color(0.16, 0.18, 0.2)
		cable.material_override = cable_mat
		cable.rotation_degrees.z = 90.0
		cable.position = Vector3(sx + x_offset + 1.5, 2.8, -width / 2.0 + 2.4)
		parent.add_child(cable)

	# Tuned signal lane - one wall reads as custom instrumentation instead of stock hardware.
	var signal_strip := MeshInstance3D.new()
	var signal_strip_mesh := BoxMesh.new()
	signal_strip_mesh.size = Vector3(7.0, 0.03, 1.6)
	signal_strip.mesh = signal_strip_mesh
	var signal_strip_mat := StandardMaterial3D.new()
	signal_strip_mat.albedo_color = Color(0.16, 0.14, 0.08)
	signal_strip_mat.emission_enabled = true
	signal_strip_mat.emission = Color(0.42, 0.3, 0.14)
	signal_strip_mat.emission_energy_multiplier = 0.25
	signal_strip.material_override = signal_strip_mat
	signal_strip.position = Vector3(sx + 96.0, 0.03, -width / 2.0 + 3.7)
	parent.add_child(signal_strip)

	var signal_panel := MeshInstance3D.new()
	var signal_panel_mesh := BoxMesh.new()
	signal_panel_mesh.size = Vector3(6.2, 2.5, 0.18)
	signal_panel.mesh = signal_panel_mesh
	var signal_panel_mat := StandardMaterial3D.new()
	signal_panel_mat.albedo_color = Color(0.11, 0.11, 0.09)
	signal_panel_mat.emission_enabled = true
	signal_panel_mat.emission = Color(0.46, 0.34, 0.16)
	signal_panel_mat.emission_energy_multiplier = 0.55
	signal_panel.material_override = signal_panel_mat
	signal_panel.position = Vector3(sx + 96.0, 1.85, -width / 2.0 + 1.32)
	parent.add_child(signal_panel)

	for i in range(4):
		var meter := MeshInstance3D.new()
		var meter_mesh := BoxMesh.new()
		meter_mesh.size = Vector3(0.45, 1.4 + 0.18 * float(i % 2), 0.08)
		meter.mesh = meter_mesh
		var meter_mat := StandardMaterial3D.new()
		meter_mat.albedo_color = Color(0.12, 0.16, 0.14)
		meter_mat.emission_enabled = true
		meter_mat.emission = Color(0.52, 0.74, 0.28) if i < 2 else Color(0.8, 0.62, 0.24)
		meter_mat.emission_energy_multiplier = 0.6
		meter.material_override = meter_mat
		meter.position = signal_panel.position + Vector3(-1.8 + float(i) * 1.2, -0.15 + 0.08 * float(i % 2), 0.12)
		parent.add_child(meter)

	var signal_light := OmniLight3D.new()
	signal_light.position = Vector3(sx + 96.0, 2.2, -13.8)
	signal_light.light_color = Color(0.46, 0.34, 0.18)
	signal_light.light_energy = 1.1
	signal_light.omni_range = 7.0
	parent.add_child(signal_light)

	var signal_wall = preload("res://scenes/game/interactable.tscn").instantiate()
	signal_wall.name = "SignalWall"
	signal_wall.description = "Custom Sensor Wall"
	signal_wall.dialogue_box = _dialogue
	signal_wall.active_character = "aster"
	signal_wall.one_shot = true
	signal_wall.dwell_time = 1.3
	signal_wall.position = Vector3(sx + 96.0, 1.0, -16.9)
	signal_wall.tutorial_label = "PARSE"
	signal_wall.interacted.connect(trigger_stacks_signal.bind(true))
	parent.add_child(signal_wall)
	_stacks_signal_interactable = signal_wall

	# The support log gives the numbers; the custom wall establishes that the useful feed is
	# nonstandard. Three separated banks turn that information into a short spatial deduction.
	_add_stacks_audit_bank(
		parent,
		"bank_a",
		Vector3(sx + 118.0, 0.0, -9.5),
		"BANK A // NORMALIZED",
		Color(0.24, 0.58, 0.72)
	)
	_add_stacks_audit_bank(
		parent,
		"bank_b",
		Vector3(sx + 138.0, 0.0, 9.0),
		"BANK B // UNSIGNED",
		Color(0.38, 0.84, 0.48)
	)
	_add_stacks_audit_bank(
		parent,
		"bank_c",
		Vector3(sx + 154.0, 0.0, -7.5),
		"BANK C // COLD MIRROR",
		Color(0.34, 0.48, 0.66)
	)

	# Myke's elegant workspace - deeper in, off the main path
	var elegant_light := OmniLight3D.new()
	elegant_light.position = Vector3(sx + length * 0.75, 2.0, -10)
	elegant_light.light_color = Color(0.42, 0.3, 0.2)
	elegant_light.light_energy = 1.5
	elegant_light.omni_range = 9.0
	parent.add_child(elegant_light)

	var work_table := MeshInstance3D.new()
	var work_table_mesh := BoxMesh.new()
	work_table_mesh.size = Vector3(3.2, 0.18, 1.6)
	work_table.mesh = work_table_mesh
	var work_table_mat := StandardMaterial3D.new()
	work_table_mat.albedo_color = Color(0.24, 0.2, 0.16)
	work_table.material_override = work_table_mat
	work_table.position = Vector3(sx + length * 0.75, 0.95, -10.0)
	parent.add_child(work_table)

	var notebook := MeshInstance3D.new()
	var notebook_mesh := BoxMesh.new()
	notebook_mesh.size = Vector3(0.55, 0.04, 0.8)
	notebook.mesh = notebook_mesh
	var notebook_mat := StandardMaterial3D.new()
	notebook_mat.albedo_color = Color(0.82, 0.78, 0.66)
	notebook.material_override = notebook_mat
	notebook.rotation_degrees.y = 18.0
	notebook.position = work_table.position + Vector3(0.6, 0.13, -0.2)
	parent.add_child(notebook)

	var workspace = preload("res://scenes/game/interactable.tscn").instantiate()
	workspace.name = "SupportWorkspace"
	workspace.description = "Support Workspace"
	workspace.dialogue_box = _dialogue
	workspace.active_character = "aster"
	workspace.one_shot = true
	workspace.dwell_time = 1.3
	workspace.position = Vector3(sx + length * 0.75, 1.0, -10.0)
	workspace.tutorial_label = "TRACE"
	workspace.interacted.connect(trigger_stacks_archive.bind(true))
	parent.add_child(workspace)
	_stacks_workspace_interactable = workspace

	var drink := MeshInstance3D.new()
	var drink_mesh := BoxMesh.new()
	drink_mesh.size = Vector3(1.1, 1.9, 0.9)
	drink.mesh = drink_mesh
	var drink_mat := StandardMaterial3D.new()
	drink_mat.albedo_color = Color(0.14, 0.18, 0.2)
	drink_mat.emission_enabled = true
	drink_mat.emission = Color(0.1, 0.18, 0.24)
	drink_mat.emission_energy_multiplier = 0.42
	drink.material_override = drink_mat
	drink.position = Vector3(sx + length * 0.6, 0.95, width / 2.0 - 3.0)
	parent.add_child(drink)

	# Cold lighting spans the corridor.
	for i in range(6):
		var light := OmniLight3D.new()
		light.position = Vector3(sx + 20.0 + i * 35.0, 4.0, 0)
		light.light_color = Color(0.2, 0.2, 0.3)
		light.light_energy = 2.0
		light.omni_range = 20.0
		parent.add_child(light)

	_add_flora_node(
		parent,
		"stacks_terminal_bloom",
		"Duct Bloom",
		"stacks",
		Vector3(sx + length * 0.4, 0.0, 3.2),
		"cache",
		"terminal cache",
		Vector3(sx + length * 0.4, 0.0, 0.0),
		Color(0.72, 0.88, 0.54),
		0.58
	)
	_add_flora_node(
		parent,
		"stacks_archive_vine",
		"Archive Vine",
		"stacks",
		Vector3(sx + length * 0.75, 0.0, -8.2),
		"resource",
		"warm archive trace",
		Vector3(sx + length * 0.75, 0.0, -10.0),
		Color(0.88, 0.78, 0.46),
		0.7,
		{"tended": true}
	)
	_build_district_fieldwork(parent, "stacks")

func _add_rings_trace_interactable(
	parent: Node3D,
	trace_id: String,
	description: String,
	position: Vector3,
	label: String
) -> void:
	var interactable = preload("res://scenes/game/interactable.tscn").instantiate()
	interactable.name = "RingsTrace_%s" % trace_id
	interactable.description = description
	interactable.dialogue_box = _dialogue
	interactable.active_character = "peris"
	interactable.required_character = "peris"
	interactable.one_shot = true
	interactable.dwell_time = 1.4
	interactable.position = position
	interactable.tutorial_label = label
	interactable.interacted.connect(trigger_rings_trace.bind(trace_id))
	parent.add_child(interactable)
	register_preview_interactable(interactable)
	_rings_trace_interactables[trace_id] = interactable

func _build_rings_chunk(parent: Node3D) -> void:
	var sx := RINGS_START.x
	var length := 200.0
	var width := 50.0
	var floor_color := Color(0.12, 0.11, 0.1)
	var wall_color := Color(0.15, 0.14, 0.12)

	# Ground + collision
	_add_corridor_section(parent, Vector3(sx + length / 2.0, -0.05, 0), Vector3(length, 0.1, width), floor_color)
	var gb := StaticBody3D.new()
	gb.position = Vector3(sx + length / 2.0, -0.01, 0)
	gb.collision_layer = 1
	gb.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(length, 0.02, width)
	gc.shape = gs
	gb.add_child(gc)
	parent.add_child(gb)

	# Cleaner residential walls.
	_add_wall(parent, Vector3(sx + length / 2.0, 2.0, -width / 2.0), Vector3(length, 4, 0.3), wall_color)
	_add_wall(parent, Vector3(sx + length / 2.0, 2.0, width / 2.0), Vector3(length, 4, 0.3), wall_color)

	# Warm residential lighting.
	for i in range(8):
		var light := OmniLight3D.new()
		light.position = Vector3(sx + 15 + i * 25.0, 3.5, 0)
		light.light_color = Color(0.8, 0.6, 0.4)
		light.light_energy = 2.5
		light.omni_range = 18.0
		parent.add_child(light)

	# Simulation bay windows (glowing rectangles along the north wall)
	for i in range(10):
		var bay := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(5, 2.0, 0.1)
		bay.mesh = bb
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.15, 0.12, 0.1)
		bm.emission_enabled = true
		bm.emission = Color(0.3, 0.25, 0.15)
		bm.emission_energy_multiplier = 0.5
		bay.material_override = bm
		bay.position = Vector3(sx + 10 + i * 18.0, 1.8, -width / 2.0 + 0.2)
		parent.add_child(bay)

	# Apartment doors along the south wall (some sealed, one ajar)
	for i in range(8):
		var door := MeshInstance3D.new()
		var db := BoxMesh.new()
		db.size = Vector3(2.0, 2.5, 0.1)
		door.mesh = db
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.18, 0.16, 0.14)
		door.material_override = dm
		door.position = Vector3(sx + 20 + i * 22.0, 1.25, width / 2.0 - 0.2)
		parent.add_child(door)

	# Client interactable (Peris tries to talk)
	var client := preload("res://scenes/game/interactable.tscn").instantiate()
	client.name = "ClientNPC"
	client.description = "Former Client"
	client.dialogue_box = _dialogue
	client.active_character = "peris"
	client.required_character = "peris"
	client.one_shot = true
	client.dwell_time = 1.0
	client.position = Vector3(sx + length * 0.4, 0.5, -5)
	client.tutorial_label = "SPEAK"
	client.interacted.connect(trigger_rings_client.bind(true))
	parent.add_child(client)
	register_preview_interactable(client)
	_rings_client_interactable = client

	# Drink machine set dressing.
	var drink := MeshInstance3D.new()
	var drb := BoxMesh.new()
	drb.size = Vector3(1.0, 1.8, 0.8)
	drink.mesh = drb
	var drm := StandardMaterial3D.new()
	drm.albedo_color = Color(0.15, 0.18, 0.2)
	drm.emission_enabled = true
	drm.emission = Color(0.1, 0.15, 0.2)
	drm.emission_energy_multiplier = 0.3
	drink.material_override = drm
	drink.position = Vector3(sx + length * 0.6, 0.9, width / 2.0 - 2.0)
	parent.add_child(drink)

	_add_flora_node(
		parent,
		"rings_client_bloom",
		"Client Bloom",
		"rings",
		Vector3(sx + length * 0.38, 0.0, -8.0),
		"memory",
		"client trace",
		Vector3(sx + length * 0.4, 0.0, -5.0),
		Color(0.95, 0.74, 0.44),
		0.82,
		{"tended": true}
	)
	_add_flora_node(
		parent,
		"rings_forget_me_not",
		"Forget-Me-Not",
		"rings",
		Vector3(sx + length * 0.58, 0.0, 13.8),
		"relationship",
		"Aster",
		Vector3(sx + length * 0.58, 0.0, 13.8),
		Color(0.58, 0.72, 0.95),
		1.0,
		{"role": "relationship", "forget_me_not": true, "tended": true, "childhood_species": true}
	)
	_add_flora_node(
		parent,
		"rings_doorvine",
		"Doorvine",
		"rings",
		Vector3(sx + length * 0.78, 0.0, 8.5),
		"resource",
		"occupied warmth",
		Vector3(sx + length * 0.8, 0.0, 10.0),
		Color(0.72, 0.88, 0.58),
		0.52
	)

	_add_rings_trace_interactable(
		parent,
		"client_bloom",
		"Client Bloom",
		Vector3(sx + length * 0.38, 0.5, -8.0),
		"READ"
	)
	_add_rings_trace_interactable(
		parent,
		"forget_me_not",
		"Forget-Me-Not Bed",
		Vector3(sx + length * 0.58, 0.5, 13.8),
		"TEND"
	)
	_add_rings_trace_interactable(
		parent,
		"doorvine",
		"Occupied Doorvine",
		Vector3(sx + length * 0.78, 0.5, 8.5),
		"TRACE"
	)
	_build_district_fieldwork(parent, "rings")

func _build_lockout_chunk(parent: Node3D) -> void:
	var sx := LOCKOUT_START.x
	var length := 80.0  # Shorter — this is an event, not an exploration area
	var width := 20.0
	var floor_color := Color(0.1, 0.1, 0.12)
	var wall_color := Color(0.12, 0.12, 0.14)

	# Ground + collision
	_add_corridor_section(parent, Vector3(sx + length / 2.0, -0.05, 0), Vector3(length, 0.1, width), floor_color)
	var gb := StaticBody3D.new()
	gb.position = Vector3(sx + length / 2.0, -0.01, 0)
	gb.collision_layer = 1
	gb.collision_mask = 0
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(length, 0.02, width)
	gc.shape = gs
	gb.add_child(gc)
	parent.add_child(gb)

	# Cleaner boundary walls.
	_add_wall(parent, Vector3(sx + length / 2.0, 2.5, -width / 2.0), Vector3(length, 5, 0.3), wall_color)
	_add_wall(parent, Vector3(sx + length / 2.0, 2.5, width / 2.0), Vector3(length, 5, 0.3), wall_color)

	# Progressive lighting: dim at entry, bright at boundary (approaching civilization)
	for i in range(4):
		var light := OmniLight3D.new()
		var t: float = float(i) / 3.0
		light.position = Vector3(sx + 10.0 + i * 20.0, 3.0, 0)
		light.light_color = Color(0.3 + t * 0.3, 0.3 + t * 0.2, 0.35 + t * 0.25)
		light.light_energy = 1.0 + t * 2.0
		light.omni_range = 12.0 + t * 6.0
		parent.add_child(light)

	# Access panel visual (at the boundary)
	var panel := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.15, 1.5, 1.0)
	panel.mesh = pb
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.12, 0.14, 0.18)
	pm.emission_enabled = true
	pm.emission = Color(0.1, 0.15, 0.25)
	pm.emission_energy_multiplier = 0.8
	panel.material_override = pm
	panel.position = LOCKOUT_BOUNDARY + Vector3(-0.5, 0.75, 0)
	parent.add_child(panel)

	# Access panel interactable
	var access := preload("res://scenes/game/interactable.tscn").instantiate()
	access.name = "AccessPanel"
	access.description = "Access Panel"
	access.dialogue_key = "lockout.approach.panel_reject"
	access.dialogue_box = _dialogue
	access.active_character = "aster"
	access.one_shot = true
	access.dwell_time = 1.5
	access.position = LOCKOUT_BOUNDARY + Vector3(-1.5, 0.75, 0)
	add_child(access)
