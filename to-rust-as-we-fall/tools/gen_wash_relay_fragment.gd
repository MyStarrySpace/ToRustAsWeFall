extends SceneTree

## One-off: capture wash_relay's LAYOUT + environment model + level tunables as DATA, so the chunk becomes a
## thin behavior subclass over DataFragmentChunk. The warp/flood/branch/drain MECHANICS stay in the subclass
## (they read these knobs from fragment.params). Run:
##   ../Godot_v4.7-stable_win64_console.exe --headless --path "." --script res://tools/gen_wash_relay_fragment.gd

func _init() -> void:
	var frag := Fragment.new()
	frag.id = "wash_relay"
	frag.title = "Wash Relay"
	frag.help = "Read the shared surge, but expect the coil to break. At the first break, take the violet portal into the pressure room, vent the jet manifold, then leave through cyan. At the sluice, choose the fast exposed crossing or the slow concealed outer pipe; both rejoin at the collector. Held overrides and plates still need party coordination. Later, hide, lure guards into the wash, and explore only the salvage lobes that look worth the risk. Water or a guard hit sends a crew member to start; the terminal and sloperope recover them."
	frag.default_character = "endo"
	frag.party_ids = PackedStringArray(["aster", "peris", "endo"])
	frag.spawns = {
		"aster": Vector3(3.0, 0.5, 0.0), "peris": Vector3(2.0, 0.5, 1.2), "endo": Vector3(2.0, 0.5, -1.2),
	}
	frag.environment_model = "res://resources/models/channels/channels.glb"
	# The chunk builds all its own warped geometry, so the procedural arrays stay empty (no double-build).
	frag.floors = []
	frag.walls = []
	frag.lights = []
	frag.labels = []
	frag.objects = []
	frag.grid = {}   # derived in get_grid_data() from the sections + drain consts — stays a method
	frag.time_state = {"day": 2, "time": 0.5, "routing_mode": "safe",
		"note_default": "Read the flood beat. Cross the broken coil through pressure transit; choose fast sluice or slow outer pipe."}

	# The authored LAYOUT + level tunables (what a level designer edits). The mechanic-tuning consts
	# (branch/drain/splash/ability/colors) stay in the subclass as the "thin logic" half of the hybrid.
	frag.params = {
		"sections": [
			{"type": "flush",        "x0": 6.0,  "x1": 11.0, "phase": 0.0, "disable": "override"},
			{"type": "current",      "x0": 14.0, "x1": 19.0, "phase": 2.5, "disable": "timing", "period": 4.0},
			{"type": "jet",          "x0": 22.0, "x1": 27.0, "phase": 1.2, "disable": "override"},
			{"type": "plate",        "x0": 30.0, "x1": 35.0, "phase": 3.6, "disable": "plate"},
			{"type": "sluice",       "x0": 38.0, "x1": 41.0, "phase": 0.8, "disable": "timing"},
			{"type": "patrol",       "x0": 46.0, "x1": 53.0, "phase": 4.0, "disable": "timing"},
			{"type": "lure",         "x0": 56.0, "x1": 61.0, "phase": 1.6, "disable": "timing"},
			{"type": "basin",        "x0": 64.0, "x1": 71.0, "phase": 0.0, "disable": "override", "period": 8.0, "dur": 2.6},
			{"type": "double_plate", "x0": 74.0, "x1": 79.0, "phase": 2.0, "disable": "double_plate"},
		],
		"start_pos": Vector3(3.0, 0.5, 0.0),
		"floor_z_half": 4.0, "floor_min_x": -1.0, "floor_max_x": 87.0, "chunk_end_x": 84.0,
		"terminal_pos": Vector3(84.0, 0.5, 2.5), "sloperope_pos": Vector3(84.0, 0.5, -2.5),
		"climb_pos": Vector3(5.0, 0.5, 2.5), "return_landing": Vector3(83.0, 0.5, 0.0),
		"flow_period": 6.0, "flood_duration": 1.4, "first_flood": 2.5,
		"hide_alcoves": [
			{"pos": Vector3(49.5, 0.5, 3.3), "radius": 1.9},
			{"pos": Vector3(67.5, 0.5, 3.3), "radius": 1.9},
		],
		"enemy_specs": [
			{"id": "ch_roamer", "spawn": Vector3(49.5, 0.5, 0.0), "kind": "roam",  "radius": 2.6, "speed": 3.0, "range": 5.5},
			{"id": "ch_sentry", "spawn": Vector3(58.5, 0.5, 0.0), "kind": "guard", "radius": 0.0, "speed": 4.0, "range": 6.0},
			{"id": "ch_basin",  "spawn": Vector3(67.5, 0.5, 0.0), "kind": "roam",  "radius": 3.0, "speed": 3.2, "range": 5.5},
			{"id": "ch_drain",  "spawn": Vector3(81.25, 0.5, 9.3), "kind": "guard", "radius": 0.0, "speed": 4.2, "range": 5.0},
		],
		"lure_specs": [{"pos": Vector3(54.0, 0.5, 2.8), "target": "ch_sentry"}],
		"lure_duration": 9.0,
	}

	var path := "res://data/fragments/wash_relay.tres"
	var err := ResourceSaver.save(frag, path)
	print("[gen-wash-relay] %s %s (%d sections)" % ["saved" if err == OK else "FAILED(%d)" % err, path, (frag.params["sections"] as Array).size()])
	quit()
