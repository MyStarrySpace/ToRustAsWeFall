extends "res://scripts/fragments/chunks/data_fragment_chunk.gd"

## BOSS PIECES — the two mega-landmark boss encounters as a walkable look-dev gallery (GDD 11):
##   LOCA'S WATCHTOWER (Act 1/2 boundary) — the survey-built tower staged on a rock crag with the
##   switchback approach and the ACT I BELOW / ACT II AHEAD marker (boss plate: reference-images/
##   bosses/locas_watchtower.png). The mountain is the landmark; the tower is the punctuation.
##   THE PARANUCLEUS (Act 2/3 boundary) — the ophanim wheel aggregate over the engulfed NUTECH
##   facility (plate: reference-images/bosses/paranucleus.png). Every wheel TURNS in its own
##   plane, out of phase — cosmetic per-frame motion; the ring table guarantees no alignment
##   can make them touch. Hazy gray/purple light marks its region (the amyloid signature).
## N reseeds both pieces (seeded variants of the tower + a re-jittered wheel fan).

const Paranucleus := preload("res://scripts/generation/paranucleus_builder.gd")
const BaseShape := preload("res://scripts/generation/base_shape_builder.gd")

const TOWER_X := -17.0
const PARA_X := 13.0
const CRAG_H := 3.4
const CRAG_R := 7.6

const PARA_ORBIT_RADIUS := 14.0   # approach distance where the flat-image register takes over
const PARA_ORBIT_EXIT := 16.5     # hysteresis: leave a little further out than you entered

const CROSSING_TOL := 0.12        # rad — how generously a gap "straddles" the corridor line
const ALIGN_POLL := 0.25          # scheduler cadence for refreshing the crossing gate
const CRAWL_SPEED := 1.1
const SPIKER_ARC := 0.30          # rad — the Spiker lane's half-width around ring 0's rim
const SPIKER_DMG := 4.0           # hp/s while its lane bears on an exposed corridor-stander
const CLIMB_SPEED := 0.95         # the switchback climb pace (the crawl-tunnel pattern)
const SCRAMBLE_SECS := 18.0       # how long the winch leaves the trail head a scree scramble

var _seed := 0
var _finale := false             # roguelite FINALE: the prize waits beyond the crossing
var _prize_retrieved := false
var _wheels: Array = []   # [{node, spin, base(Basis), gaps, bottom}] — the ophanim pivots
var _para_center := Vector3.ZERO   # the shared wheel center (world) — the orbit pivot
var _orbit_on := false
var _ring0_parked := INF          # the braked ring's held phase (INF = turning)
var _ring_offsets: Array = []     # per-ring phase offsets (phase stays continuous across release)
var _render_phases: Array = []    # cosmetic eased copies of the tick-pure phases
var _align_mouths: Array = []     # the two crossing mouths (CrawlTunnels)
var _brake_ia: Area3D
var _causeway: MeshInstance3D
var _causeway_mat: StandardMaterial3D
var _align_poll_started := false
var _spiker_angle := 0.0          # the Spiker's rooted angle on ring 0 (pre-spin frame)
var _spiker_branch_mat: StandardMaterial3D
var _climb_tunnels: Array = []    # the switchback climb legs (CrawlTunnels, up + down)
var _flight_scramble := false     # the winch's after-state: the trail head is loose scree
var _watch_vantage_reached := false

func configure_chunk(config: Dictionary) -> void:
	if config.has("seed"):
		_seed = int(config["seed"])
	_finale = bool(config.get("finale", false))

func is_generation_preview() -> bool:
	return true

func get_generation_seed() -> int:
	return _seed

func get_scene_title() -> String:
	return "Boss Pieces — Watchtower + Paranucleus"

func _build_chunk() -> void:
	fragment = _boss_fragment()
	super._build_chunk()
	_wheels.clear()
	_climb_tunnels.clear()
	_prize_retrieved = false
	_watch_vantage_reached = false
	_flight_scramble = false
	_build_watchtower_staging()
	_build_paranucleus()
	_build_finale_prize()

## The reservoir cache beyond the far mouth — the piece's OBJECTIVE, so the mechanism is playable
## in every mode: hold the front vantage, park the wheel, wait the window, thread the crossing,
## take what's cached. In the roguelite finale taking it completes the run (the last sealed dose);
## in the showcase it's the same beat with a sample verb.
func _build_finale_prize() -> void:
	var prize_pos := Vector3(PARA_X, 0, -8.8)
	var prize := _add_interactable(self, "FinalePrize", "The last sealed dose from the reservoirs",
		prize_pos, "TAKE THE DOSE" if _finale else "TAKE THE SAMPLE", "", 0.8, true, 1.6,
		Interactable.InteractableType.INSPECTION, false)
	prize.interacted.connect(func() -> void: _prize_retrieved = true)
	var vial := _add_box(prize, Vector3(0, 0.55, 0), Vector3(0.16, 0.3, 0.16),
		Color(0.55, 0.42, 0.72), Color(0.80, 0.55, 1.0), 1.8)
	_add_box(prize, Vector3(0, 0.18, 0), Vector3(0.32, 0.18, 0.32), Color(0.48, 0.50, 0.52))
	_outline_interactable_child(prize, vial, "FinalePrize", 1.6)
	_add_boss_label(self, "THE RESERVOIR CACHE", prize_pos + Vector3(0, 1.6, 0), Color(0.82, 0.70, 0.95), 34)

func _process(delta: float) -> void:
	# The wheels render from the TICK-PURE phase (never per-frame accumulation): the data layer
	# owns ring_phase(i, tick) — fast-forward invariant, replay-identical — and the render merely
	# EASES toward it (imperceptible while turning; smooths the brake's detent snap).
	var t := _tick()
	for i in range(_wheels.size()):
		var wd := _wheels[i] as Dictionary
		var nd := wd["node"] as Node3D
		if not is_instance_valid(nd):
			continue
		_render_phases[i] = lerp_angle(float(_render_phases[i]), ring_phase(i, t), minf(1.0, 10.0 * delta))
		nd.basis = (wd["base"] as Basis) * Basis(Vector3(0, 0, 1), float(_render_phases[i]))
	_ensure_align_poll()
	_update_causeway_visual(t)
	_update_paranucleus_register()

## The Paranucleus camera REGISTER (director, 2026-07-11 — the Monument Valley aspect): inside the
## approach radius the level reads as a FLAT IMAGE — the camera flips to an orthographic ORBIT
## between four authored snap vantages (Q/E steps between them), zoom scales the picture, and
## panning is just looking closer at it (no parallax). Leaving restores the gameplay follow
## camera. Rendering-only: the flip reads the follow target's render position and mutates no game
## state — 1x and 10x play identically underneath it.
func _update_paranucleus_register() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not cam.has_method("enter_ortho_orbit"):
		return
	var t: Node3D = cam.get("target")
	if t == null or not is_instance_valid(t):
		return
	var d := Vector2(t.global_position.x - PARA_X, t.global_position.z).length()
	if not _orbit_on and d < PARA_ORBIT_RADIUS:
		_orbit_on = true
		# the camera is the VIEW of the committed vantage: Q/E steps commit through the data layer
		if cam.has_method("set_orbit_authority"):
			cam.call("set_orbit_authority", Callable(self, "_vantage_idx"), Callable(self, "_commit_vantage_step"))
		cam.call("enter_ortho_orbit", _para_center, [0.0, PI * 0.5, PI, PI * 1.5],
			{"dist": 40.0, "base_size": 24.0, "elev": 0.5})
	elif _orbit_on and d > PARA_ORBIT_EXIT:
		_orbit_on = false
		cam.call("exit_ortho_orbit")

## The crag + switchback approach + the act marker, with the survey-built tower on the summit.
func _build_watchtower_staging() -> void:
	var rock := SurfaceTool.new()
	rock.begin(Mesh.PRIMITIVE_TRIANGLES)
	# the crag: a stepped lathe (radii as fractions of CRAG_H), boulders scattered at its foot
	var rows := [[0.0, CRAG_R / CRAG_H], [0.30, CRAG_R * 0.93 / CRAG_H], [0.58, CRAG_R * 0.82 / CRAG_H],
		[0.84, CRAG_R * 0.72 / CRAG_H], [1.0, CRAG_R * 0.68 / CRAG_H]]
	BaseShape._rings_loft(rock, Vector3.ZERO, CRAG_H, rows, 14)
	for b in range(6):
		var ba := TAU * (0.13 + float(b) / 6.0)
		var br := CRAG_R * (1.02 + 0.10 * BaseShape._h01(float(_seed * 31 + b) + 3.0))
		var bs := 0.5 + 0.7 * BaseShape._h01(float(_seed * 31 + b) + 9.0)
		BaseShape._emit_box_st(rock, Vector3(cos(ba) * br, bs * 0.45, sin(ba) * br), Vector3(bs, bs * 0.5, bs * 0.8))
	# the switchback approach: two flights + a turn landing on the crag's front face
	var f1_a := Vector3(-5.4, 0.10, CRAG_R * 0.94)
	var f1_b := Vector3(3.6, 1.75, CRAG_R * 0.82)
	var f2_a := Vector3(3.6, 1.75, CRAG_R * 0.70)
	var f2_b := Vector3(-2.6, CRAG_H, CRAG_R * 0.56)
	for fl in [[f1_a, f1_b], [f2_a, f2_b]]:
		var a := (fl as Array)[0] as Vector3
		var c := (fl as Array)[1] as Vector3
		var mid := (a + c) * 0.5
		var run := c - a
		var u := run.normalized()
		var n := Vector3(0, 0, 1)
		var v := u.cross(n).normalized() * -1.0
		BaseShape._emit_oriented_box_st(rock, mid, u, v, n, Vector3(run.length() * 0.5 + 0.3, 0.09, 0.55))
	BaseShape._emit_box_st(rock, Vector3(3.6, 1.66, CRAG_R * 0.76), Vector3(0.9, 0.09, 0.9))
	rock.generate_normals()
	var rock_root := Node3D.new()
	rock_root.name = "WatchtowerCrag"
	rock_root.position = Vector3(TOWER_X, 0, 0)
	add_child(rock_root)
	_add_lattice_mesh(rock_root, "Crag", rock.commit(),
		_tinted_tile_material("facility_metal", Color(0.24, 0.25, 0.28)))
	# blue trail posts up the flights (the plate's cold checkpoint lights)
	var posts := SurfaceTool.new()
	posts.begin(Mesh.PRIMITIVE_TRIANGLES)
	for fl2 in [[f1_a, f1_b], [f2_a, f2_b]]:
		var a2 := (fl2 as Array)[0] as Vector3
		var c2 := (fl2 as Array)[1] as Vector3
		for t in range(4):
			var p := a2.lerp(c2, (float(t) + 0.5) / 4.0) + Vector3(0, 0.42, 0.62)
			BaseShape._emit_box_st(posts, p, Vector3(0.05, 0.42, 0.05))
			BaseShape._emit_box_st(posts, p + Vector3(0, 0.48, 0), Vector3(0.08, 0.08, 0.08))
	posts.generate_normals()
	var postm := StandardMaterial3D.new()
	postm.albedo_color = Color(0.10, 0.18, 0.26)
	postm.emission_enabled = true
	postm.emission = Color(0.45, 0.80, 1.0)
	postm.emission_energy_multiplier = 2.0
	_add_lattice_mesh(rock_root, "TrailPosts", posts.commit(), postm)
	# the act marker at the trail base (the plate's ACT I BELOW / ACT II AHEAD pylon)
	var marker := SurfaceTool.new()
	marker.begin(Mesh.PRIMITIVE_TRIANGLES)
	BaseShape._emit_box_st(marker, Vector3(0, 1.1, 0), Vector3(0.16, 1.1, 0.16))
	BaseShape._emit_box_st(marker, Vector3(0, 1.62, 0.02), Vector3(0.62, 0.30, 0.06))
	BaseShape._emit_box_st(marker, Vector3(0, 0.92, 0.02), Vector3(0.62, 0.30, 0.06))
	BaseShape._emit_box_st(marker, Vector3(0, 2.32, 0), Vector3(0.10, 0.24, 0.10))
	marker.generate_normals()
	var marker_root := Node3D.new()
	marker_root.name = "ActMarker"
	marker_root.position = Vector3(TOWER_X - 6.6, 0, CRAG_R + 1.6)
	add_child(marker_root)
	_add_lattice_mesh(marker_root, "MarkerBody", marker.commit(),
		_tinted_tile_material("facility_metal", Color(0.30, 0.33, 0.38)))
	_add_boss_label(marker_root, "ACT I BELOW", Vector3(0, 1.62, 0.14), Color(0.55, 0.80, 1.0), 30)
	_add_boss_label(marker_root, "ACT II AHEAD", Vector3(0, 0.92, 0.14), Color(0.55, 0.80, 1.0), 30)
	# the tower itself: the survey-built landmark on the summit
	_spawn_landmark_building({"kind": "locas_watchtower", "pos": Vector3(TOWER_X, CRAG_H, 0),
		"spec_seed": _seed})
	_add_boss_label(self, "LOCA'S WATCHTOWER — ACT 1 BOSS", Vector3(TOWER_X, CRAG_H + 15.6, 0),
		Color(0.62, 0.82, 1.0), 52)
	_build_watchtower_ascent(f1_a, f1_b, f2_a, f2_b)

## THE ASCENT (SET_PIECES 12 lite — the tower becomes PLAYABLE): the switchback is a real climb
## (a CrawlTunnel authored path, the established way to traverse grid-forbidden vertical ground),
## the trail-head WINCH sweeps the scree chute over the base apron (locusts pushed off the trail
## head, and the climb itself turns to slow scramble for a span — spending the winch always costs
## your own line), and the summit holds the ACT II SURVEY beat. The two dwell points up top are
## HOLD_ACTION on purpose: the summit is unreachable by click-walk (the crag blocks the grid), so
## proximity is the only honest trigger there — the climb deposits you inside their radius.
func _build_watchtower_ascent(f1_a: Vector3, f1_b: Vector3, f2_a: Vector3, f2_b: Vector3) -> void:
	var off := Vector3(TOWER_X, 0, 0)
	var up := Vector3(0, 0.15, 0)
	var summit := Vector3(TOWER_X - 2.6, CRAG_H, 3.6)
	var base_mouth := Vector3(TOWER_X - 5.4, 0, CRAG_R + 1.0)
	var path_up: Array = [f1_a + off + up, f1_b + off + up, f2_a + off + up, f2_b + off + up, summit]
	var climb_up := CrawlTunnel.new()
	climb_up.name = "ClimbSwitchback"
	climb_up.description = "Climb the switchback trail"
	climb_up.tutorial_label = "CLIMB"
	climb_up.configure(_get_game_state(), base_mouth, path_up, 1.3, CLIMB_SPEED)
	climb_up.set_group_provider(_selected_party_ids)
	add_child(climb_up)
	_register_interactable(climb_up)
	var stub := _add_box(climb_up, Vector3(-0.7, 0.3, 0), Vector3(0.26, 0.6, 0.26), Color(0.32, 0.36, 0.42))
	_outline_interactable_child(climb_up, stub, "ClimbSwitchback", 1.3)
	_climb_tunnels.append(climb_up)
	# the way back down: a HOLD point at the summit exit (stand and it carries you down)
	var path_down := path_up.duplicate()
	path_down.reverse()
	path_down.append(base_mouth)
	var climb_down := CrawlTunnel.new()
	climb_down.name = "DescendSwitchback"
	climb_down.description = "Take the trail back down"
	climb_down.tutorial_label = "DESCEND"
	climb_down.configure(_get_game_state(), summit, path_down, 1.4, CLIMB_SPEED)
	# the descend stays CLICK-gated (the project default): the climb deposits you inside its
	# radius, so the commit walk is zero-length — click DESCEND and it carries you down. No
	# auto-dwell yanking the player off the summit mid-look.
	climb_down.set_group_provider(_selected_party_ids)
	add_child(climb_down)
	_register_interactable(climb_down)
	_climb_tunnels.append(climb_down)
	var down_stub := _add_box(climb_down, Vector3(0.7, 0.3, 0), Vector3(0.26, 0.6, 0.26), Color(0.32, 0.36, 0.42))
	_outline_interactable_child(climb_down, down_stub, "DescendSwitchback", 1.4)
	# hand-built tunnels miss the host's scheduler tree-walk (it ran before the chunk loaded) —
	# inject explicitly so any dwell rides the SCHEDULER, never the wall-clock fallback
	var sched = _get_scheduler()
	if sched != null:
		climb_up.set_scheduler(sched)
		climb_down.set_scheduler(sched)
	# the ACT II survey beat: reaching the summit IS the objective — a stand-and-work dwell placed
	# INSIDE the climb's deposit radius (the summit can't be click-walked; proximity is the beat).
	# It fires at 1.2 s of standing; the descend dwell under the same feet needs 3.0 s — survey
	# first, then the way back, sequenced by dwell time alone.
	var survey := _add_interactable(self, "SummitSurvey", "Survey the Act II country ahead",
		summit + Vector3(0.0, 0.0, -0.6), "SURVEY", "", 1.2, true, 1.7,
		Interactable.InteractableType.HOLD_ACTION, false)
	survey.interacted.connect(func() -> void:
		_watch_vantage_reached = true
		_set_preview_step("watchtower_vantage")
		_show_note("Act II, laid out below. The tower watches it all.", 3.0))
	var scope := _add_box(survey, Vector3(0, 0.5, 0), Vector3(0.1, 0.5, 0.1), Color(0.30, 0.34, 0.40),
		Color(0.45, 0.80, 1.0), 1.2)
	_outline_interactable_child(survey, scope, "SummitSurvey", 1.7)
	# the trail-head winch: the scree chute gate (CONTROL at the base, EFFECT on the apron)
	var winch := _add_interactable(self, "ScreeWinch", "The scree chute winch above the trail head",
		Vector3(TOWER_X - 7.0, 0, CRAG_R + 2.2), "WINCH", "", 0.8, false, 1.6,
		Interactable.InteractableType.INSPECTION, false)
	winch.interacted.connect(_on_winch_used)
	var drum := _add_box(winch, Vector3(0, 0.5, 0), Vector3(0.45, 0.5, 0.4), Color(0.36, 0.34, 0.30))
	_add_box(winch, Vector3(0, 1.06, 0), Vector3(0.3, 0.1, 0.1), Color(0.62, 0.5, 0.3))
	_outline_interactable_child(winch, drum, "ScreeWinch", 1.6)

## The winch fires the chute: everything on the base apron is SWEPT off the trail head (pushed
## outward — fail-forward, never a kill), and the head becomes loose scree for a span: the climb
## runs at half pace for everyone, including you. Logged moves + scheduler restore — replay-safe.
func _on_winch_used() -> void:
	var gs = _get_game_state()
	if gs == null or fragment == null:
		return
	var apron := Vector3(TOWER_X - 5.4, 0, CRAG_R + 1.0)
	var swept := 0
	for id_v in gs.characters.keys():
		var id := str(id_v)
		var pos: Vector3 = gs.get_position(id)
		if Vector2(pos.x - apron.x, pos.z - apron.z).length() > 3.2 or pos.y > 1.2:
			continue
		var away := Vector3(pos.x - TOWER_X, 0, pos.z).normalized()
		gs.snap_character_to(id, pos + away * 4.2)
		swept += 1
		for enemy in _enemies:
			if is_instance_valid(enemy) and str(enemy.char_id) == id and enemy.has_method("take_damage"):
				enemy.take_damage(2.0)
	_flight_scramble = true
	for ct in _climb_tunnels:
		if is_instance_valid(ct):
			ct.crawl_speed = CLIMB_SPEED * 0.5
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag("watch_scramble")
		sched.schedule_after(SCRAMBLE_SECS, _end_scramble, "watch_scramble")
	_show_note("The chute lets go. The trail head is scree — %d swept off it." % swept, 2.8)

func _end_scramble() -> void:
	_flight_scramble = false
	for ct in _climb_tunnels:
		if is_instance_valid(ct):
			ct.crawl_speed = CLIMB_SPEED

## The ophanim aggregate: per-wheel pivots (basis from the ring table) so each wheel turns in its
## own plane; the pink-red core; the engulfed NUTECH fragments with their legible boards.
func _build_paranucleus() -> void:
	var spec: Dictionary = Paranucleus.generate(_seed)
	var problems: Array = Paranucleus.validate(spec)
	for p in problems:
		push_warning("BossShowcase: %s" % str(p))
	var built: Dictionary = Paranucleus.build(spec)
	var root := Node3D.new()
	root.name = "Paranucleus"
	root.position = Vector3(PARA_X, 0, 0)
	add_child(root)
	var bonem := StandardMaterial3D.new()
	bonem.albedo_color = Color(0.87, 0.84, 0.79)   # bone-white, catching the purple light
	bonem.roughness = 0.86
	var lavm := StandardMaterial3D.new()
	lavm.albedo_color = Color(0.70, 0.63, 0.80)    # the pale-lavender understrands
	lavm.roughness = 0.9
	var origin := built["origin"] as Vector3
	_para_center = root.position + origin   # the orbit pivot: the shared wheel center, world frame
	for r_v in (built["rings"] as Array):
		var rd := r_v as Dictionary
		var pivot := Node3D.new()
		pivot.name = "Wheel%d" % _wheels.size()
		pivot.position = origin
		var b := rd["basis"] as Basis
		pivot.basis = b
		root.add_child(pivot)
		_add_lattice_mesh(pivot, "Bone", rd["bone"], bonem)
		_add_lattice_mesh(pivot, "Lav", rd["lav"], lavm)
		# "bottom" = the ring-local angle whose direction maps to world-DOWN: where the ground
		# corridor crosses this wheel's circle (pure geometry from the same basis the mesh uses)
		_wheels.append({"node": pivot, "spin": float(rd["spin"]), "base": b,
			"gaps": (rd.get("gaps", []) as Array).duplicate(true),
			"bottom": atan2(-b.y.y, -b.x.y)})
		_ring_offsets.append(0.0)
		_render_phases.append(0.0)
	_build_ring_spiker()
	var corem := StandardMaterial3D.new()
	corem.albedo_color = Color(0.42, 0.10, 0.16)
	corem.emission_enabled = true
	corem.emission = Color(1.0, 0.42, 0.50)   # the map's ONLY pink-red saturation (GDD 4.5)
	corem.emission_energy_multiplier = 3.0
	var core_holder := Node3D.new()
	core_holder.name = "CoreHolder"
	core_holder.position = origin
	root.add_child(core_holder)
	_add_lattice_mesh(core_holder, "Core", built["core"], corem)
	_add_lattice_mesh(root, "Nutech", built["nutech"],
		_tinted_tile_material("facility_metal", Color(0.46, 0.48, 0.50)))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.09, 0.10)
	dark.roughness = 0.92
	_add_lattice_mesh(root, "NutechDark", built["dark"], dark)
	var signm := StandardMaterial3D.new()
	signm.albedo_color = Color(0.78, 0.80, 0.78)
	signm.emission_enabled = true
	signm.emission = Color(0.95, 0.97, 0.94)   # the gate board — still powered
	signm.emission_energy_multiplier = 1.2
	_add_lattice_mesh(root, "NutechSigns", built["signs"], signm)
	# the legible offices: REAL surveyed nutech_facility instances scaled into their envelopes
	for slot_v in (built["building_slots"] as Array):
		var slot := (slot_v as Dictionary).duplicate()
		slot["pos"] = root.position + (slot["pos"] as Vector3)
		_spawn_landmark_building(slot)
	for sp_v in (built["sign_positions"] as Array):
		var sp := sp_v as Dictionary
		_add_boss_label(root, "NUTECH", (sp["pos"] as Vector3), Color(0.16, 0.18, 0.20), 34)
	_add_boss_label(self, "THE PARANUCLEUS — ACT 2 BOSS",
		Vector3(PARA_X, (built["origin"] as Vector3).y * 2.1, 0), Color(0.82, 0.72, 0.92), 52)
	_build_alignment_crossing()

# --- The projection-alignment crossing (the Monument Valley payoff, director 2026-07-11) --------
#
# A ground corridor threads UNDER the wheels, mouth to mouth. Ring 0's bottom tube physically
# blocks it; ring 1 never does — but the crossing exists ONLY while the flat image shows it whole:
# the front snap vantage held AND both wheels' gap arcs on the corridor line. The picture is the
# path. Mechanics: ring phase is a PURE function of the scheduler tick; the NUTECH brake parks
# ring 0 at its nearest gap-on-corridor detent (a logged interaction); the crossing itself is a
# CrawlTunnel (authored path through grid-forbidden space, portal-rule group entry); the gate is
# refreshed on a scheduler cadence (deterministic at any speed — the puzzle-fast-forward law).

func _tick() -> float:
	var sched = _get_scheduler()
	return float(sched.get_current_tick()) if sched != null else 0.0

## Ring i's rotation phase — a PURE function of the scheduler tick (fast-forward invariant,
## replay-identical). The braked ring holds its parked detent.
func ring_phase(i: int, tick: float) -> float:
	if i == 0 and _ring0_parked != INF:
		return _ring0_parked
	var w := _wheels[i] as Dictionary
	return wrapf(float(w["spin"]) * tick + float(_ring_offsets[i]), 0.0, TAU)

## Whether one of ring i's gap arcs straddles the wheel's BOTTOM (the corridor's crossing line).
func ring_gap_at_bottom(i: int, tick: float) -> bool:
	var w := _wheels[i] as Dictionary
	for g_v in (w["gaps"] as Array):
		var g := g_v as Array
		var center := (float(g[0]) + float(g[1])) * 0.5
		var half := (float(g[1]) - float(g[0])) * 0.5
		if absf(wrapf(center + ring_phase(i, tick) - float(w["bottom"]), -PI, PI)) <= half + CROSSING_TOL:
			return true
	return false

## THE SPIKER SIGHTLINE (SET_PIECES 18 — the plaque is a siege site): a Spiker rooted to ring 0's
## rim, so its firing lane is a pure function of the SAME phase the gaps ride. When the bright
## branch sweeps onto the corridor line, the lane rakes the ground crossing: the thread window now
## has TWO phases to satisfy at once, and standing exposed on the corridor while it bears costs hp.
func spiker_at_bottom(tick: float) -> bool:
	if _wheels.is_empty():
		return false
	var w := _wheels[0] as Dictionary
	return absf(wrapf(_spiker_angle + ring_phase(0, tick) - float(w["bottom"]), -PI, PI)) <= SPIKER_ARC

## The PHYSICAL thread window: both outer wheels' gaps on the corridor line AND the Spiker's lane
## swept off it — one pure predicate shared by the crossing rule, the mouth gates, and the
## analytic window scan (they can never disagree).
func thread_window(tick: float) -> bool:
	return ring_gap_at_bottom(0, tick) and ring_gap_at_bottom(1, tick) and not spiker_at_bottom(tick)

## THE RULE: the crossing exists only while the IMAGE shows it whole — front vantage held AND the
## physical window (gaps on the line, Spiker away). Ring 1 never physically blocks the ground
## lane; if the picture is broken, the path is not there.
func crossing_open(tick: float) -> bool:
	return _vantage_is_front() and thread_window(tick)

const VANTAGE_KEY := "paranucleus_vantage"

## The committed survey-lens vantage — pure DATA (a logged world state), never a camera read:
## walkability gates stay replay-identical and the mechanism is playable headless through the
## data layer. The camera is bound to this as its VIEW (set_orbit_authority).
func _vantage_idx() -> int:
	var gs = _get_game_state()
	return int(gs.get_world_state(VANTAGE_KEY, 0)) if gs != null else 0

func _commit_vantage_step(dir: int) -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	gs.set_world_state(VANTAGE_KEY, posmod(_vantage_idx() + dir, 4))
	_refresh_crossing_gate()

func _vantage_is_front() -> bool:
	return _vantage_idx() == 0

func _build_alignment_crossing() -> void:
	# the NUTECH ring brake: parks ring 0 at its nearest gap-on-corridor detent; used again, releases
	_brake_ia = _add_interactable(self, "RingBrake", "The surviving NUTECH maintenance brake",
		Vector3(PARA_X - 5.2, 0, 6.4), "BRAKE RING", "", 0.8, false, 1.6,
		Interactable.InteractableType.INSPECTION, false)
	_brake_ia.interacted.connect(_on_brake_used)
	# the brake's visible body: a grey NUTECH console pedestal with a caliper lever
	var pedestal := _add_box(_brake_ia, Vector3(0, 0.45, 0), Vector3(0.5, 0.9, 0.42),
		Color(0.48, 0.50, 0.52))
	_add_box(_brake_ia, Vector3(0.16, 0.98, 0), Vector3(0.08, 0.34, 0.08), Color(0.75, 0.30, 0.22))
	_outline_interactable_child(_brake_ia, pedestal, "RingBrake", 1.6)
	var near_mouth := Vector3(PARA_X, 0, 6.3)
	var far_mouth := Vector3(PARA_X, 0, -6.3)
	var thread: Array = [Vector3(PARA_X, 0.15, 4.2), Vector3(PARA_X, 0.15, 0.0), Vector3(PARA_X, 0.15, -4.2)]
	_align_mouths.append(_add_align_mouth("AlignCrossingIn", near_mouth, thread + [far_mouth]))
	var back := thread.duplicate()
	back.reverse()
	_align_mouths.append(_add_align_mouth("AlignCrossingOut", far_mouth, back + [near_mouth]))
	_refresh_crossing_gate()
	# the ghost causeway: the corridor's read — bright while the picture is whole
	_causeway = MeshInstance3D.new()
	_causeway.name = "AlignCauseway"
	var bm := BoxMesh.new()
	bm.size = Vector3(1.15, 0.04, 12.4)
	_causeway.mesh = bm
	_causeway_mat = StandardMaterial3D.new()
	_causeway_mat.albedo_color = Color(0.55, 0.48, 0.68)
	_causeway_mat.emission_enabled = true
	_causeway_mat.emission = Color(0.85, 0.78, 1.0)   # pale lavender — the aggregate's own light
	_causeway_mat.emission_energy_multiplier = 0.1
	_causeway.material_override = _causeway_mat
	_causeway.position = Vector3(PARA_X, 0.05, 0)
	add_child(_causeway)

func _add_align_mouth(mouth_name: String, mouth: Vector3, waypoints: Array) -> CrawlTunnel:
	var ct := AlignmentCrossing.new()
	ct.name = mouth_name
	ct.description = "Thread the wheels when the gaps align"
	ct.tutorial_label = "THREAD"
	ct.configure(_get_game_state(), mouth, waypoints, 1.3, CRAWL_SPEED)
	ct.set_group_provider(_selected_party_ids)
	# the PHYSICAL gate: the shared thread window (gaps on the corridor line + Spiker away) — pure
	# functions of the tick, so the queued launch tick is predicted, never sampled
	ct.set_window_gate(thread_window, _next_window_tick)
	add_child(ct)
	_register_interactable(ct)
	# the mouth's visible body: a pair of bone kerb stubs flanking the corridor entry (the outline
	# hull wraps them — every visible interactable shares the outline/glow shaders)
	var stub_l := _add_box(ct, Vector3(-0.72, 0.28, 0), Vector3(0.3, 0.56, 0.34),
		Color(0.85, 0.82, 0.77))
	_add_box(ct, Vector3(0.72, 0.28, 0), Vector3(0.3, 0.56, 0.34), Color(0.85, 0.82, 0.77))
	_outline_interactable_child(ct, stub_l, mouth_name, 1.3)
	return ct

## Park ring 0 at the detent nearest its current phase (a gap CENTER on the corridor line);
## a second use releases it, phase continuous from the parked value.
func _on_brake_used() -> void:
	if _crossing_occupied():
		return   # the caliper refuses while something is inside the wheel
	var t := _tick()
	var w := _wheels[0] as Dictionary
	if _ring0_parked != INF:
		_ring_offsets[0] = wrapf(_ring0_parked - float(w["spin"]) * t, 0.0, TAU)
		_ring0_parked = INF
	else:
		var cur := ring_phase(0, t)
		var best := cur
		var best_d := INF
		for spiker_aware in [true, false]:
			for g_v in (w["gaps"] as Array):
				var g := g_v as Array
				var center := (float(g[0]) + float(g[1])) * 0.5
				var p := wrapf(float(w["bottom"]) - center, 0.0, TAU)
				# the brake is CONTESTED (piece 18): a detent that would freeze the Spiker's lane
				# ON the corridor is refused — parking must never soft-lock the window shut. If
				# every detent were blocked (a degenerate gap layout), fall back to the nearest
				# plain detent rather than parking off-gap.
				if spiker_aware and absf(wrapf(_spiker_angle + p - float(w["bottom"]), -PI, PI)) <= SPIKER_ARC + 0.10:
					continue
				var d := absf(wrapf(p - cur, -PI, PI))
				if d < best_d:
					best_d = d
					best = p
			if best_d < INF:
				break
		_ring0_parked = best
	_refresh_crossing_gate()

## The gate refresh rides the SCHEDULER (never the frame clock): same cadence at 1x and 10x, so
## the mouths enable/disable at the same ticks in every run and in replay.
func _ensure_align_poll() -> void:
	if _align_poll_started or _align_mouths.is_empty():
		return
	var sched = _get_scheduler()
	if sched == null:
		return
	_align_poll_started = true
	_align_poll()

func _align_poll() -> void:
	_refresh_crossing_gate()
	_apply_spiker_fire()
	var sched = _get_scheduler()
	if sched != null:
		sched.schedule_after(ALIGN_POLL, _align_poll, "align_poll")

## The Spiker's rake, applied on the same scheduler cadence as the gate (never frame-sampled):
## while its lane bears on the corridor, an EXPOSED party member standing in the strip drains hp.
## Concealment is the canon cover verb (Capbage/Scarpet break its LOS).
func _apply_spiker_fire() -> void:
	var gs = _get_game_state()
	if gs == null or fragment == null or not spiker_at_bottom(_tick()):
		return
	for cid_v in fragment.party_ids:
		var cid := str(cid_v)
		if not gs.characters.has(cid) or gs.is_character_hidden(cid):
			continue
		var pos: Vector3 = gs.get_position(cid)
		if absf(pos.x - PARA_X) <= 1.3 and absf(pos.z) <= 6.3:
			gs.adjust_stat(cid, "hp", -SPIKER_DMG * ALIGN_POLL)

func _refresh_crossing_gate() -> void:
	# The mouth is COMMITTABLE whenever the front vantage is held (the view rule); the physical
	# window is the AlignmentCrossing's own gate — an order outside the window queues at the
	# mouth and launches on the next window's predicted tick.
	var committable := _vantage_is_front()
	for m in _align_mouths:
		if m != null and is_instance_valid(m) and m.has_method("set_interaction_enabled"):
			m.set_interaction_enabled(committable)

## The first tick >= `from_tick` at which the full thread window holds (gaps on the corridor
## line, Spiker away; < 0 = none within the horizon). A pure scan of the tick-pure functions.
func _next_window_tick(from_tick: float) -> float:
	var dt := 0.0
	while dt < 600.0:
		var t := from_tick + dt
		if thread_window(t):
			return t
		dt += 0.05
	return -1.0

## The rooted Spiker itself (piece 18): a bright branch bolted to ring 0's rim — parented to the
## wheel pivot, so the render sweeps with the same eased phase the mesh turns by. The lane read is
## the emissive branch; the mechanics live in spiker_at_bottom()/_apply_spiker_fire().
func _build_ring_spiker() -> void:
	if _wheels.is_empty():
		return
	var w := _wheels[0] as Dictionary
	_spiker_angle = wrapf(float(w["bottom"]) + 1.9 + 1.3 * BaseShape._h01(float(_seed) * 13.7 + 4.0), 0.0, TAU)
	var pivot := w["node"] as Node3D
	var rim := 0.0
	for child in pivot.get_children():
		if child is MeshInstance3D:
			rim = maxf(rim, (child as MeshInstance3D).get_aabb().size.x * 0.42)
	if rim <= 0.0:
		rim = 6.0
	var holder := Node3D.new()
	holder.name = "RingSpiker"
	pivot.add_child(holder)
	var radial := Vector3(cos(_spiker_angle), sin(_spiker_angle), 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# the body knuckle on the rim + the bright branch aiming INWARD across the wheel
	BaseShape._emit_box_st(st, radial * rim, Vector3(0.34, 0.34, 0.34))
	BaseShape._emit_oriented_box_st(st, radial * (rim - 1.05), -radial,
		Vector3(0, 0, 1).cross(-radial).normalized(), Vector3(0, 0, 1), Vector3(1.0, 0.09, 0.09))
	st.generate_normals()
	_spiker_branch_mat = StandardMaterial3D.new()
	_spiker_branch_mat.albedo_color = Color(0.30, 0.10, 0.08)
	_spiker_branch_mat.emission_enabled = true
	_spiker_branch_mat.emission = Color(1.0, 0.52, 0.28)   # the fauna_roster bright branch
	_spiker_branch_mat.emission_energy_multiplier = 1.4
	var mi := MeshInstance3D.new()
	mi.name = "SpikerBranch"
	mi.mesh = st.commit()
	mi.material_override = _spiker_branch_mat
	holder.add_child(mi)

## Anyone inside (or committed into) the wheel: the brake must not move it under them.
func _crossing_occupied() -> bool:
	for m in _align_mouths:
		if m != null and is_instance_valid(m) and m.has_method("has_occupants") and bool(m.call("has_occupants")):
			return true
	return false

## Cosmetic: the causeway brightens as the picture completes (reads the same pure functions).
func _update_causeway_visual(t: float) -> void:
	if _causeway_mat == null:
		return
	var open := crossing_open(t)
	var near_open := ring_gap_at_bottom(0, t) or ring_gap_at_bottom(1, t)
	var target := 2.2 if open else (0.45 if near_open else 0.1)
	_causeway_mat.emission_energy_multiplier = lerpf(_causeway_mat.emission_energy_multiplier, target, 0.15)
	# the Spiker's bright branch runs HOT while its lane bears on the corridor — the danger read
	if _spiker_branch_mat != null:
		var hot := 3.4 if spiker_at_bottom(t) else 1.4
		_spiker_branch_mat.emission_energy_multiplier = lerpf(
			_spiker_branch_mat.emission_energy_multiplier, hot, 0.2)

## A sized label riding the shared _add_label (the base already owns the Label3D idiom).
func _add_boss_label(parent: Node3D, text: String, pos: Vector3, col: Color, size: int) -> void:
	var lbl := _add_label(parent, text, pos, col)
	lbl.font_size = size
	lbl.pixel_size = 0.006
	lbl.outline_size = 8
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y

func get_preview_state() -> Dictionary:
	var st: Dictionary = super.get_preview_state()
	st["seed"] = _seed
	st["wheels"] = _wheels.size()
	st["crossing_open"] = crossing_open(_tick()) if not _wheels.is_empty() else false
	st["ring0_parked"] = _ring0_parked != INF
	st["prize_retrieved"] = _prize_retrieved
	st["spiker_clear"] = not spiker_at_bottom(_tick())
	st["watch_vantage"] = _watch_vantage_reached
	st["scramble"] = _flight_scramble
	return st

func _boss_fragment() -> Fragment:
	var frag := Fragment.new()
	frag.id = "boss_showcase_%d" % _seed
	frag.title = "Boss Pieces — Watchtower + Paranucleus"
	frag.help = "The two mega-landmark boss encounters. Walk the ground; compare to the boss plates."
	frag.default_character = "aster"
	frag.party_ids = PackedStringArray(["aster", "peris", "endo"])
	var cs := 1.5
	var w := 38
	var h := 20
	frag.floors = [{
		"pos": Vector3(-2.0, -0.05, 0), "size": Vector3(w * cs, 0.1, h * cs),
		"color": Color(0.11, 0.10, 0.13), "tile": "deck_metal",
	}]
	var origin_x := -2.0 - w * cs * 0.5
	var origin_z := -h * cs * 0.5
	var blocked := {}
	for z in range(h):
		for x in range(w):
			var wx := origin_x + (float(x) + 0.5) * cs
			var wz := origin_z + (float(z) + 0.5) * cs
			# the crag disc + the paranucleus facility apron are staging, not floor
			if Vector2(wx - TOWER_X, wz).length() < CRAG_R + 1.2:
				blocked[Vector2i(x, z)] = true
			if absf(wx - PARA_X) < 7.2 and absf(wz) < 5.4:
				blocked[Vector2i(x, z)] = true
	var cells: Array = []
	for z2 in range(h):
		for x2 in range(w):
			if not blocked.has(Vector2i(x2, z2)):
				cells.append([x2, z2])
	frag.grid = {
		"contract_id": "unified_grid_v1", "cell_size": cs,
		"origin": [origin_x, 0.0, origin_z], "width": w, "height": h,
		"walkable_cells": cells,
	}
	frag.spawns = {
		"aster": Vector3(-3.5, 0.5, 11.5), "peris": Vector3(-2.0, 0.5, 12.4), "endo": Vector3(-5.0, 0.5, 12.4),
	}
	frag.shelters = [{"min": Vector2(-6.5, 10.4), "max": Vector2(-0.5, 13.4)}]
	frag.lights = [
		# the watchtower region: the cold institutional blue against the dark
		{"pos": Vector3(TOWER_X - 6.0, 16.0, 10.0), "color": Color(0.62, 0.74, 0.92), "energy": 3.6, "range": 34.0},
		{"pos": Vector3(TOWER_X + 6.0, 5.0, 8.0), "color": Color(0.45, 0.58, 0.80), "energy": 1.8, "range": 20.0},
		# the paranucleus region: the hazy gray/purple amyloid signature (GDD 4.5)
		{"pos": Vector3(PARA_X - 5.0, 15.0, 9.0), "color": Color(0.72, 0.64, 0.82), "energy": 3.4, "range": 36.0},
		{"pos": Vector3(PARA_X + 6.0, 6.0, -7.0), "color": Color(0.55, 0.46, 0.66), "energy": 2.0, "range": 24.0},
		# the core's own pink-red spill
		{"pos": Vector3(PARA_X, 8.4, 0.0), "color": Color(1.0, 0.45, 0.52), "energy": 1.6, "range": 10.0},
	]
	frag.labels = []
	# the trail-head locusts (piece 12's tide, lite): roamers holding the watchtower approach —
	# the winch's scree chute is the answer that clears them off the apron
	frag.objects = [
		{"type": "enemy", "id": "trail_gnawer_0", "pos": Vector3(TOWER_X - 6.0, 0.5, CRAG_R + 2.9),
			"speed": 2.2, "detect": 3.5, "targets": ["aster", "peris", "endo"], "roam": {"radius": 2.4}},
		{"type": "enemy", "id": "trail_gnawer_1", "pos": Vector3(TOWER_X - 4.0, 0.5, CRAG_R + 3.9),
			"speed": 2.2, "detect": 3.5, "targets": ["aster", "peris", "endo"], "roam": {"radius": 2.4}},
	]
	frag.params = {"stamina_field_regen": true, "showcase_seed": _seed}
	frag.time_state = {"note_default": "The two boss mega-landmarks — climb the tower trail; thread the wheels.",
		"routing_mode": "safe"}
	return frag
