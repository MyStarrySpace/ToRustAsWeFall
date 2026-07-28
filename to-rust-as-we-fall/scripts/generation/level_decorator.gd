class_name LevelDecorator
extends RefCounted
# @rendering_only_file: deterministic, collision-free environment dressing only.

## A measured decoration pass for authored corridor levels.
##
## The building grammar establishes the quality bar: coherent material fields, structural
## datums, a program-specific facade, sparse emissive landmarks, and decay that follows the
## construction instead of random prop scatter. This kit applies that same hierarchy to long
## playable interiors. All added geometry is wall-attached or a paper-thin floor marking and is
## rendered in a handful of MultiMeshes. It deliberately creates no physics bodies, areas, or
## navigation data, so dressing cannot change a route or swallow an interaction point.

const GRIME_SHADER := preload("res://resources/tile_grime.gdshader")
const TILE_DIR := "res://resources/models/elevator/tiles/"

const TERMINAL_GREEN := Color(0.36, 0.91, 0.50)
const SCANNER_CYAN := Color(0.42, 0.72, 0.95)
const WINDOW_AMBER := Color(0.95, 0.64, 0.32)
const QUALITY_CONTRACT_ID := "authored_level_decoration_v2"
const MAX_WAYFINDING_GAP_M := 48.0
const MAX_LIGHT_GAP_M := 58.0

const ACT1_PROFILES := {
	"channels": {
		"x0": 0.0, "x1": 228.0, "width": 50.0, "wall_height": 3.0,
		"seed": 0x1C4A11, "program": "hydraulic", "spacing": 13.5,
		"floor_tile": "deck_metal", "wall_tile": "rust_iron",
		"floor_tint": Color(0.16, 0.23, 0.25), "wall_tint": Color(0.18, 0.27, 0.27),
		"trim": Color(0.38, 0.43, 0.39), "inset": Color(0.055, 0.075, 0.08),
		"service": Color(0.20, 0.25, 0.23), "rust": Color(0.34, 0.16, 0.075),
		"glow": TERMINAL_GREEN, "light": Color(0.22, 0.48, 0.45),
		"signs": ["CHANNEL 01 / OUTFLOW", "RECIRCULATION SPINE", "SHELTER FLOW  >"],
	},
	"endo_stretch": {
		"x0": -2.0, "x1": 96.0, "width": 36.0, "wall_height": 4.4, "ground_y": 0.0,
		"seed": 0xE0D057, "program": "hydraulic", "spacing": 12.0,
		"floor_tile": "deck_metal", "wall_tile": "facility_metal",
		"floor_tint": Color(0.14, 0.19, 0.19), "wall_tint": Color(0.16, 0.22, 0.21),
		"trim": Color(0.36, 0.43, 0.39), "inset": Color(0.045, 0.065, 0.065),
		"service": Color(0.18, 0.25, 0.22), "rust": Color(0.32, 0.15, 0.07),
		"glow": TERMINAL_GREEN, "light": Color(0.26, 0.46, 0.39),
		"signs": ["ENDO'S JUNCTION", "MAINTENANCE LEDGE", "SHELTER 1  >"],
	},
	"leaving_facility": {
		"x0": -3.0, "x1": 47.0, "width": 16.0, "wall_height": 3.0, "ground_y": 0.0,
		"seed": 0x1EA71F, "program": "hydraulic", "spacing": 8.5,
		"floor_tile": "deck_metal", "wall_tile": "rust_iron",
		"floor_tint": Color(0.13, 0.14, 0.16), "wall_tint": Color(0.20, 0.17, 0.16),
		"trim": Color(0.42, 0.38, 0.34), "inset": Color(0.055, 0.05, 0.055),
		"service": Color(0.22, 0.20, 0.19), "rust": Color(0.42, 0.18, 0.065),
		"glow": Color(0.95, 0.38, 0.10), "light": Color(0.62, 0.33, 0.17),
		# The authored scene already owns its warnings and route beacons; do not duplicate them.
		"signs": [], "landmark_lights": false, "external_wayfinding": true,
	},
	"tag_checkpoint": {
		"x0": -4.0, "x1": 28.0, "width": 14.0, "wall_height": 3.0, "ground_y": 0.0,
		"seed": 0x7A6DA7, "program": "boundary", "spacing": 5.4,
		"floor_tile": "facility_metal", "wall_tile": "wall_panel",
		"floor_tint": Color(0.15, 0.17, 0.21), "wall_tint": Color(0.18, 0.21, 0.27),
		"trim": Color(0.38, 0.46, 0.56), "inset": Color(0.045, 0.055, 0.08),
		"service": Color(0.15, 0.20, 0.29), "rust": Color(0.23, 0.10, 0.06),
		"glow": SCANNER_CYAN, "light": Color(0.42, 0.60, 0.82),
		"signs": ["CHECKPOINT 7-B", "PSY-KNAPSE ARRAY", "WELLNESS WING"],
	},
	# The Elevator sequence supplies these values directly while it streams each room. Keeping the
	# measured production profiles here as well gives the shared kit one canonical audit surface and
	# lets future callers use decorate_profile() without copying the palette contract again.
	"elevator_below_routes": {
		"x0": -3.5, "x1": 136.34, "width": 16.0, "wall_height": 3.0, "ground_y": -4.0,
		"seed": 0xBE10A5, "program": "hydraulic", "spacing": 11.5,
		"floor_tile": "deck_metal", "wall_tile": "facility_metal",
		"floor_tint": Color(0.10, 0.15, 0.16), "wall_tint": Color(0.13, 0.19, 0.19),
		"trim": Color(0.31, 0.41, 0.38), "inset": Color(0.035, 0.055, 0.06),
		"service": Color(0.15, 0.23, 0.21), "rust": Color(0.37, 0.16, 0.06),
		"glow": TERMINAL_GREEN, "light": Color(0.24, 0.48, 0.40),
		"signs": ["LOWER DECK / ROUTE READ", "FLURE LANE  <", "IRON FIELD  >"],
	},
	"elevator_flure_relay": {
		"x0": 150.34, "x1": 226.34, "width": 14.0, "wall_height": 3.0, "ground_y": -4.0,
		"seed": 0xF1A2E2, "program": "boundary", "spacing": 9.0,
		"floor_tile": "deck_metal", "wall_tile": "rust_iron",
		"floor_tint": Color(0.10, 0.11, 0.14), "wall_tint": Color(0.16, 0.13, 0.12),
		"trim": Color(0.38, 0.34, 0.31), "inset": Color(0.045, 0.04, 0.05),
		"service": Color(0.22, 0.19, 0.18), "rust": Color(0.43, 0.17, 0.055),
		"glow": Color(0.95, 0.46, 0.12), "light": Color(0.58, 0.31, 0.18),
		"signs": ["FLURE RELAY / STAGE 1", "MIDPOINT REFUGE", "STAGE 2 / EXIT  >"],
	},
	"stacks": {
		"x0": 240.0, "x1": 460.0, "width": 40.0, "wall_height": 5.0,
		"seed": 0x57AC15, "program": "archive", "spacing": 11.5,
		"floor_tile": "deck_metal", "wall_tile": "wall_panel",
		"floor_tint": Color(0.13, 0.15, 0.17), "wall_tint": Color(0.16, 0.20, 0.21),
		"trim": Color(0.34, 0.40, 0.40), "inset": Color(0.045, 0.055, 0.065),
		"service": Color(0.18, 0.22, 0.23), "rust": Color(0.28, 0.14, 0.075),
		"glow": TERMINAL_GREEN, "light": Color(0.28, 0.42, 0.46),
		"signs": ["STACK INDEX 04", "PRESERVATION BUS", "ARCHIVE SUPPORT"],
	},
	"rings": {
		"x0": 480.0, "x1": 680.0, "width": 50.0, "wall_height": 4.0,
		"seed": 0x71A65, "program": "habitat", "spacing": 15.5,
		"floor_tile": "deck_metal", "wall_tile": "facility_metal",
		"floor_tint": Color(0.24, 0.22, 0.18), "wall_tint": Color(0.27, 0.26, 0.21),
		"trim": Color(0.56, 0.51, 0.39), "inset": Color(0.10, 0.095, 0.075),
		"service": Color(0.24, 0.28, 0.22), "rust": Color(0.35, 0.17, 0.08),
		"glow": WINDOW_AMBER, "light": Color(0.72, 0.50, 0.28),
		"signs": ["RING HABITAT 12", "COMMON GALLERY", "SIMULATION RESIDENCES"],
	},
	"lockout": {
		"x0": 700.0, "x1": 780.0, "width": 20.0, "wall_height": 5.0,
		"seed": 0x10C0A7, "program": "boundary", "spacing": 8.0,
		"floor_tile": "deck_metal", "wall_tile": "wall_panel",
		"floor_tint": Color(0.17, 0.19, 0.22), "wall_tint": Color(0.18, 0.21, 0.25),
		"trim": Color(0.42, 0.47, 0.52), "inset": Color(0.055, 0.065, 0.085),
		"service": Color(0.20, 0.24, 0.29), "rust": Color(0.30, 0.14, 0.07),
		"glow": SCANNER_CYAN, "light": Color(0.38, 0.55, 0.72),
		"signs": ["CIVIC LIMIT", "CREDENTIAL CORRIDOR", "CLASS GATE / NO EGRESS"],
	},
}

static var _material_cache: Dictionary = {}


static func decorate_act1_chunk(parent: Node3D, chunk_id: String, overrides: Dictionary = {}) -> Dictionary:
	return decorate_profile(parent, chunk_id, overrides)


static func decorate_profile(parent: Node3D, profile_id: String, overrides: Dictionary = {}) -> Dictionary:
	if not ACT1_PROFILES.has(profile_id):
		return {}
	var profile: Dictionary = (ACT1_PROFILES[profile_id] as Dictionary).duplicate(true)
	for key in overrides:
		profile[key] = overrides[key]
	profile["id"] = profile_id
	return decorate_corridor(parent, profile)


static func decorate_corridor(parent: Node3D, profile: Dictionary) -> Dictionary:
	var profile_id := str(profile.get("id", "corridor"))
	if ACT1_PROFILES.has(profile_id):
		var resolved_profile: Dictionary = (ACT1_PROFILES[profile_id] as Dictionary).duplicate(true)
		for key in profile:
			resolved_profile[key] = profile[key]
		profile = resolved_profile
	var existing := parent.get_node_or_null("LevelDecoration")
	if existing != null:
		return existing.get_meta("decoration_audit", {}) as Dictionary

	var x0 := float(profile.get("x0", 0.0))
	var x1 := float(profile.get("x1", 0.0))
	var width := float(profile.get("width", 12.0))
	var wall_h := float(profile.get("wall_height", 3.0))
	var ground_y := float(profile.get("ground_y", 0.0))
	if x1 <= x0 or width <= 2.0 or wall_h <= 1.0:
		return {}

	var root := Node3D.new()
	root.name = "LevelDecoration"
	parent.add_child(root)

	# Some streamed scenes already own carefully configured StandardMaterial3D shells which a later
	# post-build pass must inspect or wrap. They can keep those materials while still receiving every
	# collision-free facade, datum, sign, and light emitted below.
	var replace_shell_materials := bool(profile.get("replace_shell_materials", true))
	var shell_surfaces := _apply_shell_materials(parent, profile) if replace_shell_materials else 0

	var batches := {
		"mass": [],
		"trim": [],
		"inset": [],
		"service": [],
		"rust": [],
		"glow": [],
		"dark": [],
		"leaf": [],
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(profile.get("seed", 1))
	var spacing := float(profile.get("spacing", 12.0))
	var stations: Array[float] = []
	var x := x0 + minf(5.0, spacing * 0.4)
	while x < x1 - 2.0:
		stations.append(x)
		x += spacing * rng.randf_range(0.84, 1.17)
	if stations.size() < 2:
		stations = [x0 + (x1 - x0) * 0.25, x0 + (x1 - x0) * 0.75]

	var half_w := width * 0.5
	var program := str(profile.get("program", "utility"))
	var primary_datum_instances := 0
	var facade_field_instances := 0
	var program_signature_instances := 0
	var upper_mass_instances := 0
	var surface_datum_instances := 0
	for i in range(stations.size()):
		var sx := stations[i]
		var next_x := stations[i + 1] if i + 1 < stations.size() else minf(x1 - 1.0, sx + spacing)
		var bay_len: float = maxf(2.0, next_x - sx)
		var datum_jitter := rng.randf_range(-0.16, 0.16)
		for side_value in [-1.0, 1.0]:
			var side: float = float(side_value)
			var wall_z := side * half_w
			var face_z := wall_z - side * 0.20
			# Primary datum: a buttress, a low plinth, and an uneven eave/reveal.
			_add_box_xform(batches["trim"], Vector3(sx, ground_y + wall_h * 0.48, face_z),
				Vector3(0.34, wall_h * 0.96, 0.46))
			_add_box_xform(batches["trim"], Vector3(sx + bay_len * 0.5, ground_y + 0.18, face_z),
				Vector3(maxf(0.6, bay_len - 0.42), 0.28, 0.34))
			_add_box_xform(batches["trim"], Vector3(sx + bay_len * 0.5,
				ground_y + wall_h - 0.34 + datum_jitter, face_z),
				Vector3(maxf(0.6, bay_len - 0.58), 0.22, 0.30))
			primary_datum_instances += 3
			# Cantilever fins stop short of the central play lane and give the wall a branching silhouette.
			var fin_depth := 0.85 + 0.30 * float((i + (0 if side < 0.0 else 1)) % 3)
			_add_box_xform(batches["service"], Vector3(sx, ground_y + wall_h - 0.18,
				wall_z - side * fin_depth * 0.5), Vector3(0.28, 0.20, fin_depth))

			# Recessed facade field. Width and height drift together within a structural bay.
			var inset_w := bay_len * rng.randf_range(0.52, 0.72)
			var inset_h := wall_h * rng.randf_range(0.38, 0.58)
			var inset_y := ground_y + wall_h * 0.48 + rng.randf_range(-0.12, 0.12)
			_add_box_xform(batches["inset"], Vector3(sx + bay_len * 0.52, inset_y,
				wall_z - side * 0.365), Vector3(inset_w, inset_h, 0.055))
			facade_field_instances += 1

			# Wear hangs from real seams. It never floats randomly in the middle of a panel.
			if (i + (0 if side < 0.0 else 2)) % 3 != 0:
				var streak_h := rng.randf_range(0.55, minf(1.8, wall_h * 0.42))
				var streak_x := sx + bay_len * rng.randf_range(0.20, 0.82)
				_add_box_xform(batches["rust"], Vector3(streak_x,
					ground_y + wall_h - 0.48 - streak_h * 0.5, wall_z - side * 0.405),
					Vector3(rng.randf_range(0.07, 0.18), streak_h, 0.025))

			var program_before := _batch_instance_total(batches)
			_add_program_details(batches, program, i, side, sx, bay_len, face_z, wall_z,
				ground_y, wall_h, rng)
			program_signature_instances += _batch_instance_total(batches) - program_before
			# A staggered upper service mass gives the room an authored skyline instead of a cut-off
			# graybox wall. It sits OUTSIDE the boundary and steps down toward its facade datum.
			var side_phase := 0 if side < 0.0 else 2
			if (i + side_phase) % 4 == 0:
				var upper_h := rng.randf_range(1.7, 3.0)
				var upper_w := minf(bay_len * 0.56, rng.randf_range(3.4, 5.6))
				_add_box_xform(batches["mass"], Vector3(sx + bay_len * 0.48,
					ground_y + wall_h + upper_h * 0.5 - 0.08, wall_z + side * 0.62),
					Vector3(upper_w, upper_h, 1.20))
				_add_box_xform(batches["trim"], Vector3(sx + bay_len * 0.48,
					ground_y + wall_h + upper_h - 0.10, wall_z + side * 0.58),
					Vector3(upper_w + 0.36, 0.18, 1.34))
				upper_mass_instances += 2
				if program == "habitat":
					_add_box_xform(batches["glow"], Vector3(sx + bay_len * 0.48,
						ground_y + wall_h + upper_h * 0.52, wall_z - side * 0.015),
						Vector3(upper_w * 0.54, upper_h * 0.34, 0.035))

		# Program-specific floor composition, once per bay. These are surface markings, never obstacles.
		var surface_before := _batch_instance_total(batches)
		match program:
			"boundary":
				_add_box_xform(batches["dark"], Vector3(sx + bay_len * 0.5, ground_y + 0.018, 0.0),
					Vector3(maxf(0.8, bay_len - 0.42), 0.018, 6.2))
				for guide_z in [-3.18, 3.18]:
					_add_box_xform(batches["glow"], Vector3(sx + bay_len * 0.5, ground_y + 0.032,
						float(guide_z)), Vector3(maxf(0.8, bay_len - 0.76), 0.018, 0.055))
			"archive":
				if i % 3 == 1:
					for rail_z in [-6.4, 6.4]:
						_add_box_xform(batches["service"], Vector3(sx + bay_len * 0.5,
							ground_y + 0.028, float(rail_z)), Vector3(bay_len * 0.72, 0.025, 0.18))
			"habitat":
				# Alternating commons courts pull the residential composition in from the distant
				# facade without putting props in the route. They are only paving/moss inlays.
				var court_z := -8.0 if i % 2 == 0 else 8.0
				_add_box_xform(batches["dark"], Vector3(sx + bay_len * 0.5, ground_y + 0.017, court_z),
					Vector3(maxf(1.2, bay_len * 0.72), 0.016, 5.2))
				for curb_z in [court_z - 2.68, court_z + 2.68]:
					_add_box_xform(batches["trim"], Vector3(sx + bay_len * 0.5, ground_y + 0.029,
						float(curb_z)), Vector3(maxf(1.2, bay_len * 0.76), 0.022, 0.11))
				for moss_i in range(3):
					_add_box_xform(batches["leaf"], Vector3(sx + bay_len * (0.30 + 0.20 * float(moss_i)),
						ground_y + 0.031, court_z + (-1.35 if moss_i % 2 == 0 else 1.25)),
						Vector3(bay_len * 0.12, 0.024, 0.72))
				if i % 3 == 0:
					_add_box_xform(batches["trim"], Vector3(sx + bay_len * 0.5, ground_y + 0.027, 0.0),
						Vector3(bay_len * 0.52, 0.024, 0.30))
			"hydraulic":
				if i % 3 == 0:
					_add_box_xform(batches["service"], Vector3(sx + bay_len * 0.5, ground_y + 0.030, 0.0),
						Vector3(0.28, 0.025, width * 0.44))
		surface_datum_instances += _batch_instance_total(batches) - surface_before

	# A paper-thin construction seam at each major bay makes scale and distance readable.
	for i in range(stations.size()):
		if i % 2 != 0:
			continue
		_add_box_xform(batches["dark"], Vector3(stations[i], ground_y + 0.025, 0.0),
			Vector3(0.055, 0.025, maxf(2.0, width - 3.0)))
		surface_datum_instances += 1
	if program == "hydraulic":
		# Long drain races connect the transverse service seams into one legible hydraulic system.
		# Their placement hugs the boundary datum, keeping the playable center completely clear.
		var run_length := x1 - x0 - 1.0
		for drain_side in [-1.0, 1.0]:
			var drain_z := float(drain_side) * (half_w - 2.1)
			_add_box_xform(batches["dark"], Vector3((x0 + x1) * 0.5, ground_y + 0.018, drain_z),
				Vector3(run_length, 0.018, 0.82))
			for edge in [-0.46, 0.46]:
				_add_box_xform(batches["trim"], Vector3((x0 + x1) * 0.5, ground_y + 0.030,
					drain_z + float(edge)), Vector3(run_length, 0.022, 0.07))
			surface_datum_instances += 3

	# Major thresholds keep a 200 m route from reading as one repeated wallpaper strip. They use
	# wall-bound light bars and paper-thin floor brackets only: strong enough to divide the route into
	# memorable zones, with no new collision or false cover in the play lane.
	var wayfinding := _add_wayfinding_landmarks(batches, x0, x1, width, wall_h, ground_y)
	primary_datum_instances += int(wayfinding.get("wall_datums", 0))
	surface_datum_instances += int(wayfinding.get("surface_datums", 0))

	var material_map := {
		"mass": _standard_material(profile.get("wall_tint", Color(0.18, 0.22, 0.22)).darkened(0.18), 0.90, 0.10),
		"trim": _standard_material(profile.get("trim", Color(0.4, 0.42, 0.4)), 0.78, 0.18),
		"inset": _standard_material(profile.get("inset", Color(0.05, 0.06, 0.07)), 0.92, 0.05),
		"service": _standard_material(profile.get("service", Color(0.2, 0.22, 0.22)), 0.76, 0.32),
		"rust": _standard_material(profile.get("rust", Color(0.34, 0.16, 0.08)), 0.96, 0.08),
		"glow": _emissive_material(profile.get("glow", TERMINAL_GREEN), 1.75),
		"dark": _standard_material(Color(0.035, 0.04, 0.045), 0.94, 0.04),
		"leaf": _standard_material(Color(0.20, 0.32, 0.18), 0.94, 0.0),
	}
	var instance_total := 0
	var batch_count := 0
	var batch_instances := {}
	for batch_name in batches:
		var transforms: Array = batches[batch_name]
		if transforms.is_empty():
			continue
		_emit_box_batch(root, str(batch_name).capitalize(), transforms, material_map[batch_name])
		instance_total += transforms.size()
		batch_count += 1
		batch_instances[str(batch_name)] = transforms.size()

	var labels := _add_landmark_signs(root, profile, ground_y, half_w, wall_h)
	var lights := _add_landmark_lights(root, profile, ground_y, half_w, wall_h)
	var length_m := x1 - x0
	var landmark_count := int(wayfinding.get("count", 0))
	var wayfinding_gap_m := length_m / float(landmark_count + 1)
	var light_gap_m := (
		length_m / float(lights + 1)
		if lights > 0
		else (0.0 if bool(profile.get("external_wayfinding", false)) else length_m)
	)
	var route_obstacles := _count_potential_route_obstacles(batches, width, ground_y)
	var hierarchy_layers := 0
	hierarchy_layers += 1 if primary_datum_instances > 0 and upper_mass_instances > 0 else 0
	hierarchy_layers += 1 if facade_field_instances > 0 else 0
	hierarchy_layers += 1 if program_signature_instances > 0 else 0
	hierarchy_layers += 1 if landmark_count > 0 else 0
	hierarchy_layers += 1 if (batches["rust"] as Array).size() > 0 else 0
	var quality_issues: Array[String] = []
	if stations.size() < 2:
		quality_issues.append("fewer than two measured structural bays")
	if primary_datum_instances < stations.size() * 6:
		quality_issues.append("primary plinth/eave datum ladder is incomplete")
	if facade_field_instances < stations.size() * 2:
		quality_issues.append("both corridor faces do not carry a facade field")
	if program_signature_instances < stations.size() * 2:
		quality_issues.append("program signature is too sparse to differentiate the room")
	if surface_datum_instances < maxi(2, int(stations.size() / 2.0)):
		quality_issues.append("floor scale/route datums are too sparse")
	if batch_count < 7:
		quality_issues.append("fewer than seven coherent material roles are present")
	if hierarchy_layers < 5:
		quality_issues.append("massing/facade/program/landmark/decay hierarchy is incomplete")
	if landmark_count < 2 or wayfinding_gap_m > MAX_WAYFINDING_GAP_M + 0.01:
		quality_issues.append("macro wayfinding gap exceeds %.0f m" % MAX_WAYFINDING_GAP_M)
	if light_gap_m > MAX_LIGHT_GAP_M + 0.01:
		quality_issues.append("landmark lighting gap exceeds %.0f m" % MAX_LIGHT_GAP_M)
	if route_obstacles > 0:
		quality_issues.append("render dressing intrudes into standing-height play-lane clearance")
	var audit := {
		# Keep the original integration ID stable for hosted chunks; quality_contract_id versions the
		# richer measurable hierarchy without forcing gameplay callers to migrate in lockstep.
		"contract_id": "authored_level_decoration_v1",
		"quality_contract_id": QUALITY_CONTRACT_ID,
		"level_id": str(profile.get("id", "corridor")),
		"program": program,
		"seed": int(profile.get("seed", 1)),
		"length_m": length_m,
		"width_m": width,
		"wall_height_m": wall_h,
		"stations": stations.size(),
		"batches": batch_count,
		"instances": instance_total,
		"batch_instances": batch_instances,
		"hierarchy_layers": hierarchy_layers,
		"primary_datums": primary_datum_instances,
		"facade_fields": facade_field_instances,
		"program_signature_instances": program_signature_instances,
		"upper_mass_instances": upper_mass_instances,
		"surface_datums": surface_datum_instances,
		"decay_marks": (batches["rust"] as Array).size(),
		"emissive_instances": (batches["glow"] as Array).size(),
		"macro_landmarks": landmark_count,
		"max_wayfinding_gap_m": wayfinding_gap_m,
		"max_light_gap_m": light_gap_m,
		"labels": labels,
		"lights": lights,
		"shell_surfaces": shell_surfaces,
		"shell_materials_replaced": replace_shell_materials,
		"collision_shapes": 0,
		"route_clearance_intrusions": route_obstacles,
		"clearance": "surface_only_no_obstacles",
		"quality_passed": quality_issues.is_empty(),
		"quality_issues": quality_issues,
	}
	root.set_meta("decoration_audit", audit)
	return audit


static func _batch_instance_total(batches: Dictionary) -> int:
	var total := 0
	for batch_value in batches.values():
		total += (batch_value as Array).size()
	return total


static func _add_wayfinding_landmarks(batches: Dictionary, x0: float, x1: float, width: float,
		wall_h: float, ground_y: float) -> Dictionary:
	var length_m := x1 - x0
	var landmark_count := maxi(2, ceili(length_m / MAX_WAYFINDING_GAP_M) - 1)
	var half_w := width * 0.5
	var floor_tick_z := maxf(1.8, half_w - 1.20)
	for i in range(landmark_count):
		var fraction := float(i + 1) / float(landmark_count + 1)
		var lx := lerpf(x0, x1, fraction)
		_add_box_xform(batches["dark"], Vector3(lx, ground_y + 0.019, 0.0),
			Vector3(0.18, 0.018, maxf(2.0, width - 2.6)))
		for side_value in [-1.0, 1.0]:
			var side := float(side_value)
			_add_box_xform(batches["trim"], Vector3(lx, ground_y + wall_h * 0.54,
				side * half_w - side * 0.30), Vector3(0.20, wall_h * 0.68, 0.16))
			_add_box_xform(batches["glow"], Vector3(lx, ground_y + wall_h * 0.54,
				side * half_w - side * 0.40), Vector3(0.075, wall_h * 0.46, 0.026))
			_add_box_xform(batches["glow"], Vector3(lx, ground_y + 0.034,
				side * floor_tick_z), Vector3(1.45, 0.018, 0.075))
	return {
		"count": landmark_count,
		"wall_datums": landmark_count * 4,
		"surface_datums": landmark_count * 3,
	}


static func _count_potential_route_obstacles(batches: Dictionary, width: float,
		ground_y: float) -> int:
	var intrusion_count := 0
	var lane_half_width := minf(3.5, maxf(1.8, width * 0.18))
	for batch_value in batches.values():
		for raw_transform in batch_value as Array:
			var transform: Transform3D = raw_transform
			var size := transform.basis.get_scale().abs()
			var inner_z := absf(transform.origin.z) - size.z * 0.5
			var bottom_y := transform.origin.y - size.y * 0.5
			var top_y := transform.origin.y + size.y * 0.5
			var overlaps_lane := inner_z < lane_half_width
			var blocks_standing_height := top_y > ground_y + 0.12 and bottom_y < ground_y + 2.20
			if overlaps_lane and blocks_standing_height:
				intrusion_count += 1
	return intrusion_count


static func _add_program_details(batches: Dictionary, program: String, bay_i: int, side: float,
		sx: float, bay_len: float, face_z: float, wall_z: float, ground_y: float, wall_h: float,
		rng: RandomNumberGenerator) -> void:
	match program:
		"hydraulic":
			# Vessel/pipe read: three service lines with regular clamps and a sparse green readout.
			for line_i in range(3):
				var ly := ground_y + 0.82 + float(line_i) * 0.52
				_add_box_xform(batches["service"], Vector3(sx + bay_len * 0.5, ly, face_z - side * 0.12),
					Vector3(maxf(0.7, bay_len - 0.7), 0.10 + 0.025 * float(line_i), 0.11))
			for clamp_t in [0.25, 0.72]:
				_add_box_xform(batches["trim"], Vector3(sx + bay_len * float(clamp_t), ground_y + 1.34,
					face_z - side * 0.16), Vector3(0.10, 1.55, 0.18))
			if bay_i % 4 == (0 if side < 0.0 else 2):
				_add_box_xform(batches["glow"], Vector3(sx + bay_len * 0.70, ground_y + 2.15,
					wall_z - side * 0.43), Vector3(1.25, 0.18, 0.035))
		"archive":
			# Drawer strata and cable bus: preservation infrastructure reads dense, indexed, and maintained.
			for band_i in range(4):
				var by := ground_y + 1.05 + float(band_i) * minf(0.78, wall_h * 0.15)
				_add_box_xform(batches["service"], Vector3(sx + bay_len * 0.52, by,
					wall_z - side * 0.405), Vector3(bay_len * 0.56, 0.09, 0.035))
			for drawer_i in range(3):
				var dx := sx + bay_len * (0.30 + float(drawer_i) * 0.20)
				_add_box_xform(batches["trim"], Vector3(dx, ground_y + wall_h * 0.47,
					wall_z - side * 0.425), Vector3(0.055, wall_h * 0.42, 0.025))
			if bay_i % 3 == (1 if side < 0.0 else 0):
				for meter_i in range(3):
					_add_box_xform(batches["glow"], Vector3(sx + bay_len * (0.33 + meter_i * 0.13),
						ground_y + wall_h * 0.68, wall_z - side * 0.45),
						Vector3(0.34, 0.08, 0.025))
		"habitat":
			# Warm window field, small shade, and tended trough. Occupancy is uneven, not a perfect grid.
			if (bay_i + (0 if side < 0.0 else 1)) % 3 != 0:
				_add_box_xform(batches["glow"], Vector3(sx + bay_len * 0.52, ground_y + wall_h * 0.58,
					wall_z - side * 0.42), Vector3(bay_len * rng.randf_range(0.34, 0.50),
					wall_h * 0.28, 0.035))
				_add_box_xform(batches["trim"], Vector3(sx + bay_len * 0.52, ground_y + wall_h * 0.77,
					wall_z - side * 0.72), Vector3(bay_len * 0.50, 0.10, 0.62))
			if bay_i % 4 == (0 if side < 0.0 else 2):
				_add_box_xform(batches["service"], Vector3(sx + bay_len * 0.58, ground_y + 0.62,
					wall_z - side * 0.56), Vector3(bay_len * 0.34, 0.30, 0.65))
				for leaf_i in range(4):
					_add_box_xform(batches["leaf"], Vector3(sx + bay_len * (0.45 + leaf_i * 0.08),
						ground_y + 0.90 + 0.08 * float(leaf_i % 2), wall_z - side * 0.58),
						Vector3(0.14, 0.42, 0.12))
		"boundary":
			# Institutional fins tighten toward the class gate; scanner bars remain the only cyan field.
			for fin_i in range(3):
				var fx := sx + bay_len * (0.28 + 0.22 * float(fin_i))
				_add_box_xform(batches["trim"], Vector3(fx, ground_y + wall_h * 0.50,
					wall_z - side * 0.48), Vector3(0.12, wall_h * (0.48 + 0.08 * float(fin_i)), 0.26))
			if (bay_i + (0 if side < 0.0 else 1)) % 2 == 0:
				_add_box_xform(batches["glow"], Vector3(sx + bay_len * 0.52,
					ground_y + wall_h * (0.36 + 0.10 * float(bay_i % 3)), wall_z - side * 0.50),
					Vector3(bay_len * 0.42, 0.09, 0.035))
		_:
			if bay_i % 4 == 0:
				_add_box_xform(batches["glow"], Vector3(sx + bay_len * 0.5, ground_y + wall_h * 0.6,
					wall_z - side * 0.42), Vector3(1.0, 0.12, 0.035))


static func _apply_shell_materials(parent: Node3D, profile: Dictionary) -> int:
	var length := float(profile.get("x1", 0.0)) - float(profile.get("x0", 0.0))
	var width := float(profile.get("width", 12.0))
	var wall_h := float(profile.get("wall_height", 3.0))
	var ground_y := float(profile.get("ground_y", 0.0))
	var floor_mat := _grime_material(str(profile.get("floor_tile", "deck_metal")),
		profile.get("floor_tint", Color.WHITE), 0.35, 0.22,
		float(profile.get("floor_emission_energy", 0.0)))
	var wall_mat := _grime_material(str(profile.get("wall_tile", "facility_metal")),
		profile.get("wall_tint", Color.WHITE), 0.62, 0.40)
	var surfaces := 0
	for child in parent.get_children():
		if not (child is MeshInstance3D):
			continue
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var size := mi.mesh.get_aabb().size * mi.scale.abs()
		var is_shell_floor := size.y <= 0.16 and size.x >= length * 0.80 and size.z >= width * 0.80 \
			and absf(mi.position.y - ground_y) < 0.20
		var is_shell_wall := size.x >= length * 0.80 and size.y >= wall_h * 0.72 and size.z <= 0.75
		if is_shell_floor:
			mi.material_override = floor_mat
			surfaces += 1
		elif is_shell_wall:
			mi.material_override = wall_mat
			surfaces += 1
	return surfaces


static func _add_landmark_signs(root: Node3D, profile: Dictionary, ground_y: float,
		half_w: float, wall_h: float) -> int:
	var signs: Array = profile.get("signs", [])
	if signs.is_empty():
		return 0
	var x0 := float(profile.get("x0", 0.0))
	var x1 := float(profile.get("x1", 0.0))
	var trim: Color = profile.get("trim", Color(0.4, 0.42, 0.4))
	var glow: Color = profile.get("glow", TERMINAL_GREEN)
	var fractions := [0.12, 0.50, 0.86]
	for i in range(mini(3, signs.size())):
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos := Vector3(lerpf(x0, x1, float(fractions[i])), ground_y + minf(wall_h - 0.65, 2.6),
			side * half_w - side * 0.48)
		var board := MeshInstance3D.new()
		board.name = "DistrictSignBoard%d" % i
		var box := BoxMesh.new()
		box.size = Vector3(5.8, 0.78, 0.08)
		board.mesh = box
		board.material_override = _standard_material(trim.darkened(0.34), 0.86, 0.18)
		board.position = pos
		root.add_child(board)
		var label := Label3D.new()
		label.name = "DistrictSign%d" % i
		label.text = str(signs[i])
		label.font_size = 46
		label.pixel_size = 0.009
		label.modulate = glow.lerp(Color.WHITE, 0.22)
		label.outline_modulate = Color(0.01, 0.015, 0.02, 0.9)
		label.outline_size = 9
		label.position = pos - Vector3(0.0, 0.0, side * 0.065)
		label.rotation_degrees.y = 0.0 if side < 0.0 else 180.0
		root.add_child(label)
	return mini(3, signs.size())


static func _add_landmark_lights(root: Node3D, profile: Dictionary, ground_y: float,
		half_w: float, wall_h: float) -> int:
	if not bool(profile.get("landmark_lights", true)):
		return 0
	var x0 := float(profile.get("x0", 0.0))
	var x1 := float(profile.get("x1", 0.0))
	var light_color: Color = profile.get("light", Color(0.4, 0.5, 0.5))
	var light_count := maxi(3, ceili((x1 - x0) / MAX_LIGHT_GAP_M) - 1)
	light_count = mini(6, light_count)
	for i in range(light_count):
		var fraction := float(i + 1) / float(light_count + 1)
		var side := -1.0 if i % 2 == 0 else 1.0
		var light := OmniLight3D.new()
		light.name = "DecorationLight%d" % i
		light.position = Vector3(lerpf(x0, x1, fraction),
			ground_y + minf(wall_h - 0.4, 3.0), side * (half_w - 1.2))
		light.light_color = light_color
		light.light_energy = 0.72
		light.omni_range = 8.5
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 18.0
		light.distance_fade_length = 12.0
		root.add_child(light)
	return light_count


static func _add_box_xform(target: Array, position: Vector3, size: Vector3,
		rotation: Basis = Basis.IDENTITY) -> void:
	target.append(Transform3D(rotation.scaled(size), position))


static func _emit_box_batch(parent: Node3D, batch_name: String, transforms: Array, material: Material) -> void:
	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = unit_box
	multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		var instance_transform: Transform3D = transforms[i]
		multimesh.set_instance_transform(i, instance_transform)
	var batch := MultiMeshInstance3D.new()
	batch.name = batch_name
	batch.multimesh = multimesh
	batch.material_override = material
	batch.extra_cull_margin = 8.0
	parent.add_child(batch)


static func _grime_material(tile_name: String, tint: Color, grime: float, rust: float,
		emission_energy := 0.0) -> ShaderMaterial:
	var key := "grime:%s:%s:%.2f:%.2f:%.2f" % [
		tile_name, tint.to_html(false), grime, rust, emission_energy]
	if _material_cache.has(key):
		return _material_cache[key] as ShaderMaterial
	var material := ShaderMaterial.new()
	material.shader = GRIME_SHADER
	var texture = load(TILE_DIR + tile_name + ".png")
	if texture != null:
		material.set_shader_parameter("tile_tex", texture)
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("grime_amount", grime)
	material.set_shader_parameter("rust_amount", rust)
	material.set_shader_parameter("roughness_val", 0.88)
	material.set_shader_parameter("emission_energy", emission_energy)
	_material_cache[key] = material
	return material


static func _standard_material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var key := "std:%s:%.2f:%.2f" % [color.to_html(), roughness, metallic]
	if _material_cache.has(key):
		return _material_cache[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	_material_cache[key] = material
	return material


static func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var key := "emit:%s:%.2f" % [color.to_html(), energy]
	if _material_cache.has(key):
		return _material_cache[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.58)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.roughness = 0.48
	_material_cache[key] = material
	return material
