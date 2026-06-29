extends SceneTree

## One-off: capture the channels wash-intro's spawnables + map + logic knobs as DATA, so the chunk can become a
## thin behavior subclass over the DataFragmentChunk loader. Run:
##   ../Godot_v4.7-stable_win64_console.exe --headless --path "." --script res://tools/gen_channels_wash_intro_fragment.gd
## Regenerate data/fragments/channels_wash_intro.tres after a layout change.

const FLOOR_CENTER := Vector3(14.0, -0.05, 0.0)
const FLOOR_SIZE := Vector3(34.0, 0.1, 14.0)
const Z_HALF := 5.0
const FLURE_POS := Vector3(6.5, 0.5, 0.5)
const CAPBAGE_POS := [Vector3(2.5, 0.5, 3.5), Vector3(4.5, 0.5, -3.5), Vector3(7.5, 0.5, 3.5)]
const CAPBAGE_RADIUS := 1.4
const CHANNEL_X := [11.0, 13.5, 16.0]
const CHANNEL_HALF := 1.25
const CHANNEL_PERIOD := 3.0
const CHANNEL_DUR := 1.6
const CHANNEL_PHASE := [0.0, 1.0, 2.0]
const PORTAL_IN_POS := Vector3(8.5, 0.5, -1.5)
const PORTAL_OUT_POS := Vector3(21.5, 0.5, -1.5)
const PORTAL_RADIUS := 1.2
const WASH_BACK_POS := Vector3(2.5, 0.5, 0.5)
const EXIT_POS := Vector3(27.5, 0.5, 0.5)
const EXIT_RADIUS := 2.2
const ENEMY_SPECS := [
	{"id": "wash_intro_guard_0", "pos": Vector3(23.5, 0.5, 2.5)},
	{"id": "wash_intro_guard_1", "pos": Vector3(24.5, 0.5, -1.5)},
]
const ENEMY_SPEED := 2.4
const ENEMY_DETECT := 4.0
const FLURE_ATTRACT := 32.0

func _init() -> void:
	var frag := Fragment.new()
	frag.id = "channels_wash_intro"
	frag.title = "Channels — Wash Intro"
	frag.help = "The hunters guard the way down. Light the flure to draw them into the channels — the wash takes them — then step through the portal across. Tuck into a Capbage if one gets close."
	frag.default_character = "endo"
	frag.party_ids = PackedStringArray(["aster", "peris", "endo"])
	frag.spawns = {
		"aster": Vector3(3.5, 0.5, 1.5),
		"peris": Vector3(2.5, 0.5, 0.5),
		"endo": Vector3(2.5, 0.5, -1.5),
	}
	frag.floors = [{"pos": FLOOR_CENTER, "size": FLOOR_SIZE, "color": Color(0.34, 0.36, 0.40)}]
	frag.walls = [
		{"pos": Vector3(FLOOR_CENTER.x, 2.0, -Z_HALF - 0.2), "size": Vector3(FLOOR_SIZE.x, 4.0, 0.4), "color": Color(0.24, 0.25, 0.28)},
		{"pos": Vector3(FLOOR_CENTER.x, 2.0, Z_HALF + 0.2), "size": Vector3(FLOOR_SIZE.x, 4.0, 0.4), "color": Color(0.24, 0.25, 0.28)},
	]
	frag.lights = []
	for lx in [3.0, 11.0, 19.0, 27.0]:
		frag.lights.append({"pos": Vector3(lx, 4.2, 0.0), "color": Color(0.62, 0.68, 0.78), "energy": 2.4, "range": 16.0})
	frag.labels = [{"text": "TO SPIRAL", "pos": EXIT_POS + Vector3(0.0, 2.0, 0.0), "color": Color(0.5, 0.8, 0.9)}]
	for i in range(CHANNEL_X.size()):
		frag.labels.append({"text": "Channel %d" % (i + 1), "pos": Vector3(CHANNEL_X[i], 1.4, 0.0), "color": Color(0.4, 0.75, 0.85)})
	for cp in CAPBAGE_POS:
		frag.labels.append({"text": "CAPBAGE", "pos": (cp as Vector3) + Vector3(0.0, 1.5, 0.0), "color": Color(0.5, 0.85, 0.55)})
	frag.labels.append({"text": "PORTAL", "pos": PORTAL_IN_POS + Vector3(0.0, 1.6, 0.0), "color": Color(0.6, 0.5, 1.0)})

	var objs: Array[Dictionary] = []
	# Channels (phased flood strips).
	for i in range(CHANNEL_X.size()):
		objs.append({"type": "channel", "name": "Channel%d" % i, "x": float(CHANNEL_X[i]), "half": CHANNEL_HALF,
			"z_half": Z_HALF, "period": CHANNEL_PERIOD, "dur": CHANNEL_DUR, "phase": float(CHANNEL_PHASE[i]), "tag": "wi_ch%d" % i})
	# Capbages (tight hides).
	for j in range(CAPBAGE_POS.size()):
		objs.append({"type": "capbage", "name": "Capbage%d" % j, "pos": CAPBAGE_POS[j], "radius": CAPBAGE_RADIUS})
	# The flure (lures the two guards).
	objs.append({"type": "flure", "name": "Flure", "pos": FLURE_POS,
		"targets": ["wash_intro_guard_0", "wash_intro_guard_1"], "attract": FLURE_ATTRACT, "radius": 1.6, "color": Color(0.95, 0.78, 0.2)})
	# Bidirectional portal pair.
	objs.append({"type": "portal_pad", "name": "PortalNear", "pos": PORTAL_IN_POS, "dest": PORTAL_OUT_POS, "radius": PORTAL_RADIUS, "color": Color(0.55, 0.42, 0.98)})
	objs.append({"type": "portal_pad", "name": "PortalFar", "pos": PORTAL_OUT_POS, "dest": PORTAL_IN_POS, "radius": PORTAL_RADIUS, "color": Color(0.55, 0.42, 0.98)})
	# Two guards by the exit (idle hold — no roam; they only pathfind to chase the player or the flure).
	for spec in ENEMY_SPECS:
		objs.append({"type": "enemy", "id": str(spec["id"]), "pos": spec["pos"], "speed": ENEMY_SPEED, "detect": ENEMY_DETECT,
			"targets": ["aster", "peris", "endo"]})
	# Exit marker (the green pad toward the spiral; its "TO SPIRAL" label is a separate label entry).
	objs.append({"type": "marker", "pos": EXIT_POS, "size": Vector3(EXIT_RADIUS * 1.6, 0.4, EXIT_RADIUS * 1.6),
		"color": Color(0.3, 0.7, 0.55), "energy": 1.4, "label": ""})
	frag.objects = objs

	frag.grid = {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [-3.0, 0.0, -7.0],
		"cell_size": 1.0,
		"width": 34,
		"height": 14,
		"walkable_regions": [{"min": [-2.0, -5.0], "max": [30.0, 5.0]}],
	}
	frag.time_state = {"day": 2, "time": 0.6, "routing_mode": "safe",
		"note_default": "Endo's junction. The hunters guard the drop to the spiral — read the channels, use the flure."}
	frag.params = {
		"exit_pos": EXIT_POS,
		"exit_radius": EXIT_RADIUS,
		"wash_back_pos": WASH_BACK_POS,
		"flure_attract": FLURE_ATTRACT,
		"enemy_detect": ENEMY_DETECT,
		"anchors": {
			"flure": FLURE_POS, "portal_in": PORTAL_IN_POS, "portal_out": PORTAL_OUT_POS, "exit": EXIT_POS,
			"capbage_0": CAPBAGE_POS[0], "capbage_1": CAPBAGE_POS[1], "capbage_2": CAPBAGE_POS[2],
		},
	}

	var path := "res://data/fragments/channels_wash_intro.tres"
	var err := ResourceSaver.save(frag, path)
	print("[gen-wash-intro] %s %s (%d objects)" % ["saved" if err == OK else "FAILED(%d)" % err, path, frag.objects.size()])
	quit()
