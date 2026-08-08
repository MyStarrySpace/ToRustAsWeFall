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
const HazardFieldScript := preload("res://scripts/game/objects/hazard_field.gd")

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
const SCREE_SWEEP_DURATION := 0.85 # visible forced travel off the apron; never an endpoint snap
const PRIZE_POS := Vector3(PARA_X, 0.0, -8.8)
const PRIZE_ITEM_TYPE := "sealed_reservoir_dose"
const PRIZE_PHASE_AVAILABLE := "available"
const PRIZE_PHASE_CLAIMING := "claiming"
const PRIZE_PHASE_CLAIMED := "claimed"
const PRIZE_INTERACTION_POSITION_TOLERANCE := 0.15
const BOSS_INTERACTION_POSITION_TOLERANCE := 0.15
const WINCH_IMPACT_DAMAGE := 2.0
const WINCH_BATCH_IDLE := "idle"
const WINCH_BATCH_RESERVED := "reserved"
const WINCH_BATCH_SWEEPING := "sweeping"
const WINCH_BATCH_COMPLETE := "complete"
const BRAKE_TRANSACTION_IDLE := "idle"
const BRAKE_TRANSACTION_RESERVED := "reserved"
const BRAKE_TRANSACTION_COMMITTED := "committed"
const POSITION_RECEIPT_TOLERANCE := 0.05

# The loader/base fragment owns its own cadence record. This second, seed-keyed record owns only
# the boss mechanisms added by this subclass: brake, scree span, objectives, and Spiker poll epoch.
const BOSS_AUTHORITY_VERSION := 3
const BOSS_AUTHORITY_PREFIX := "runtime:boss_showcase:"

var _seed := 0
var _finale := false             # roguelite FINALE: the prize waits beyond the crossing
var _prize_phase := PRIZE_PHASE_AVAILABLE
var _prize_item_id := ""
var _prize_claimed_by := ""
var _prize_claim_serial := 0
var _prize_interactable: Interactable
var _survey_interactable: Interactable
var _winch_interactable: Interactable
var _survey_trigger_consumed := 0
var _survey_actor := ""
var _winch_trigger_consumed := 0
var _winch_batch_serial := 0
var _winch_batch: Dictionary = {}
var _brake_trigger_consumed := 0
var _brake_transaction: Dictionary = {}
var _wheels: Array = []   # [{node, spin, base(Basis), gaps, bottom}] — the ophanim pivots
var _para_center := Vector3.ZERO   # the shared wheel center (world) — the orbit pivot
var _orbit_on := false
var _ring0_parked := INF          # the braked ring's held phase (INF = turning)
var _ring_offsets: Array = []     # per-ring phase offsets (phase stays continuous across release)
var _render_phases: Array = []    # cosmetic eased copies of the tick-pure phases
var _align_mouths: Array = []     # the two crossing mouths (CrawlTunnels)
var _brake_ia: Interactable
var _causeway: MeshInstance3D
var _causeway_mat: StandardMaterial3D
var _align_poll_started := false
var _align_poll_epoch := -1.0
var _align_next_tick := -1.0
var _spiker_angle := 0.0          # the Spiker's rooted angle on ring 0 (pre-spin frame)
var _spiker_branch_mat: StandardMaterial3D
var _spiker_field
var _climb_tunnels: Array = []    # the switchback climb legs (CrawlTunnels, up + down)
var _flight_scramble := false     # the winch's after-state: the trail head is loose scree
var _scramble_deadline := -1.0
var _watch_vantage_reached := false
var _boss_authority_initialized := false
var _restoring_boss_authority := false
var _boss_signal_game_state = null
var _winch_batch_resume_armed := false

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
	_ring_offsets.clear()
	_render_phases.clear()
	_align_mouths.clear()
	_climb_tunnels.clear()
	_prize_phase = PRIZE_PHASE_AVAILABLE
	_prize_item_id = ""
	_prize_claimed_by = ""
	_prize_claim_serial = 0
	_prize_interactable = null
	_survey_interactable = null
	_winch_interactable = null
	_survey_trigger_consumed = 0
	_survey_actor = ""
	_winch_trigger_consumed = 0
	_winch_batch_serial = 0
	_winch_batch.clear()
	_brake_trigger_consumed = 0
	_brake_transaction.clear()
	_watch_vantage_reached = false
	_flight_scramble = false
	_scramble_deadline = -1.0
	_ring0_parked = INF
	_align_poll_started = false
	_align_poll_epoch = -1.0
	_align_next_tick = -1.0
	_boss_authority_initialized = false
	_build_watchtower_staging()
	_build_paranucleus()
	_build_finale_prize()
	_bind_boss_external_traversal_signals()

## The reservoir cache beyond the far mouth — the piece's OBJECTIVE, so the mechanism is playable
## in every mode: hold the front vantage, park the wheel, wait the window, thread the crossing,
## take what's cached. In the roguelite finale taking it completes the run (the last sealed dose);
## in the showcase it's the same beat with a sample verb.
func _build_finale_prize() -> void:
	_prize_interactable = _add_interactable(self, "FinalePrize", "The last sealed dose from the reservoirs",
		PRIZE_POS, "TAKE THE DOSE" if _finale else "TAKE THE SAMPLE", "", 0.8, true, 1.6,
		Interactable.InteractableType.INSPECTION, false)
	_prize_interactable.set_pre_trigger_validator(_validate_prize_trigger)
	_prize_interactable.interacted.connect(
		_on_prize_retrieved.bind(_prize_interactable))
	var vial := _add_box(_prize_interactable, Vector3(0, 0.55, 0), Vector3(0.16, 0.3, 0.16),
		Color(0.55, 0.42, 0.72), Color(0.80, 0.55, 1.0), 1.8)
	_add_box(_prize_interactable, Vector3(0, 0.18, 0), Vector3(0.32, 0.18, 0.32), Color(0.48, 0.50, 0.52))
	_outline_interactable_child(_prize_interactable, vial, "FinalePrize", 1.6)
	_add_boss_label(self, "THE RESERVOIR CACHE", PRIZE_POS + Vector3(0, 1.6, 0), Color(0.82, 0.70, 0.95), 34)
	_apply_prize_presenter()

## The cache owns a real GameState item from construction onward. Claiming first reserves the exact
## item and actor in portable authority; only GameState's distance/hand-slot-checked pickup can turn
## that reservation into the solved objective.
func _validate_prize_trigger(source: Node, actor: String) -> bool:
	_initialize_or_restore_boss_authority()
	return source != null and source == _prize_interactable \
		and _prize_phase == PRIZE_PHASE_AVAILABLE and _prize_item_at_source() \
		and _prize_actor_ready_at_source(source, actor) \
		and _prize_actor_has_free_hand(actor)


func _prize_actor_has_free_hand(actor: String) -> bool:
	var gs = _get_game_state()
	return gs != null and gs.has_method("has_free_hand") \
		and bool(gs.call("has_free_hand", actor))


func _prize_actor_ready_at_source(source: Node, actor: String) -> bool:
	var gs = _get_game_state()
	if gs == null or source == null or not (source is Node3D) or actor == "" \
			or not gs.characters.has(actor) or gs.is_downed(actor) \
			or gs.is_knocked_down(actor) or gs.is_moving(actor) \
			or gs.is_resting(actor) or gs.is_dodging(actor) \
			or gs.is_endocytosing(actor) or gs.is_external_traversal_active(actor) \
			or gs.is_dragging(actor) or gs.is_field_restoring(actor):
		return false
	if gs.has_method("is_narratively_available") \
			and not bool(gs.call("is_narratively_available", actor)):
		return false
	var source_pos := (source as Node3D).global_position
	if gs.coord_map != null and gs.coord_map.has_method("to_data"):
		source_pos = gs.coord_map.to_data(source_pos)
	var actor_pos: Vector3 = gs.get_position(actor)
	return Vector2(actor_pos.x, actor_pos.z).distance_to(
		Vector2(source_pos.x, source_pos.z)
	) <= float(source.get("interaction_radius")) + PRIZE_INTERACTION_POSITION_TOLERANCE


func _prize_source_receipt_pending(source: Node) -> bool:
	if source == null or source != _prize_interactable \
			or not bool(source.get("one_shot")) or not bool(source.get("_used")) \
			or bool(source.get("interaction_enabled")):
		return false
	var actor := str(source.get("active_character"))
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return false
	var receipt: Dictionary = gs.get_interactable(data_id)
	return bool(receipt.get("one_shot", false)) \
		and bool(receipt.get("triggered", false)) \
		and not bool(receipt.get("enabled", true)) \
		and _validate_prize_trigger(source, actor)


## Consequence-grade prize collection accepts only the exact one-shot that the servicing body
## physically reached. The selected portrait is presentation and cannot substitute for that body.
## Direct compatibility calls have no consumed receipt and are therefore inert.
func _on_prize_retrieved(source: Node = null) -> bool:
	_initialize_or_restore_boss_authority()
	if not _prize_source_receipt_pending(source):
		return false
	var actor := str(source.get("active_character"))
	var gs = _get_game_state()
	_prize_phase = PRIZE_PHASE_CLAIMING
	_prize_claimed_by = actor
	_prize_claim_serial += 1
	_publish_boss_authority()
	_apply_prize_presenter()
	if not _pick_up_item(actor, _prize_item_id):
		_prize_phase = PRIZE_PHASE_AVAILABLE
		_prize_claimed_by = ""
		if source.has_method("reset"):
			source.reset()
		_publish_boss_authority()
		_apply_prize_presenter()
		return false
	_prize_phase = PRIZE_PHASE_CLAIMED
	_publish_boss_authority()
	_apply_prize_presenter()
	return true


func _spawn_prize_item(properties: Dictionary = {}) -> String:
	var item_properties := {
		"display_name": "Last Sealed Dose" if _finale else "Reservoir Sample",
		"description": "A sealed reservoir vial recovered beyond the Paranucleus crossing.",
		"hand_slots": 1,
		"endocytosis_allowed": false,
		"source_boss_prize": boss_authority_key(),
		"boss_seed": _seed,
		"boss_finale": _finale,
	}
	item_properties.merge(properties, true)
	return _spawn_item(PRIZE_ITEM_TYPE, PRIZE_POS, item_properties)


func _is_boss_prize_item(item_id: String) -> bool:
	var item := _get_item_state(item_id)
	if item.is_empty() or str(item.get("type", "")) != PRIZE_ITEM_TYPE:
		return false
	var properties: Dictionary = item.get("properties", {})
	return str(properties.get("source_boss_prize", "")) == boss_authority_key()


func _find_boss_prize_item_id() -> String:
	var gs = _get_game_state()
	if gs == null or not "items" in gs:
		return ""
	var candidates: Array[String] = []
	for item_id_v in gs.items.keys():
		var item_id := str(item_id_v)
		if _is_boss_prize_item(item_id):
			candidates.append(item_id)
	candidates.sort()
	return candidates[0] if not candidates.is_empty() else ""


func _remove_boss_prize_items() -> void:
	var gs = _get_game_state()
	if gs == null or not "items" in gs:
		return
	var remove_ids: Array[String] = []
	for item_id_v in gs.items.keys():
		var item_id := str(item_id_v)
		if _is_boss_prize_item(item_id):
			remove_ids.append(item_id)
	for item_id in remove_ids:
		_remove_item(item_id)


func _reset_prize_to_available() -> void:
	_remove_boss_prize_items()
	_prize_phase = PRIZE_PHASE_AVAILABLE
	_prize_claimed_by = ""
	_prize_claim_serial = 0
	_prize_item_id = _spawn_prize_item()
	_apply_prize_presenter()


func _prize_item_at_source() -> bool:
	if not _is_boss_prize_item(_prize_item_id):
		return false
	var item := _get_item_state(_prize_item_id)
	return str(item.get("location", "")) == "ground" \
		and (item.get("position", PRIZE_POS) as Vector3).distance_to(PRIZE_POS) <= 0.05


func _prize_item_holder() -> String:
	var item := _get_item_state(_prize_item_id)
	return str(item.get("holder", "")) if not item.is_empty() else ""


func _apply_prize_presenter() -> void:
	if not is_instance_valid(_prize_interactable):
		return
	var available := _prize_phase == PRIZE_PHASE_AVAILABLE and _prize_item_at_source()
	_prize_interactable.visible = available
	_prize_interactable.set_interaction_enabled(available)

func _process(delta: float) -> void:
	super._process(delta)
	_initialize_or_restore_boss_authority()
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

func headless_process(delta: float) -> void:
	super.headless_process(delta)
	_initialize_or_restore_boss_authority()
	_ensure_align_poll()

## The Paranucleus camera REGISTER (the Monument Valley aspect): inside the
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
	_survey_interactable = _add_interactable(self, "SummitSurvey", "Survey the Act II country ahead",
		summit + Vector3(0.0, 0.0, -0.6), "SURVEY", "", 1.2, true, 1.7,
		Interactable.InteractableType.HOLD_ACTION, false)
	_survey_interactable.set_pre_trigger_validator(
		_validate_survey_trigger.bind(_survey_interactable))
	_survey_interactable.interacted.connect(
		_on_watch_vantage_reached.bind(_survey_interactable))
	var scope := _add_box(_survey_interactable, Vector3(0, 0.5, 0),
		Vector3(0.1, 0.5, 0.1), Color(0.30, 0.34, 0.40),
		Color(0.45, 0.80, 1.0), 1.2)
	_outline_interactable_child(_survey_interactable, scope, "SummitSurvey", 1.7)
	# the trail-head winch: the scree chute gate (CONTROL at the base, EFFECT on the apron)
	_winch_interactable = _add_interactable(self, "ScreeWinch", "The scree chute winch above the trail head",
		Vector3(TOWER_X - 7.0, 0, CRAG_R + 2.2), "WINCH", "", 0.8, false, 1.6,
		Interactable.InteractableType.INSPECTION, false)
	_winch_interactable.set_pre_trigger_validator(
		_validate_winch_trigger.bind(_winch_interactable))
	_winch_interactable.interacted.connect(_on_winch_used.bind(_winch_interactable))
	var drum := _add_box(_winch_interactable, Vector3(0, 0.5, 0),
		Vector3(0.45, 0.5, 0.4), Color(0.36, 0.34, 0.30))
	_add_box(_winch_interactable, Vector3(0, 1.06, 0),
		Vector3(0.3, 0.1, 0.1), Color(0.62, 0.5, 0.3))
	_outline_interactable_child(_winch_interactable, drum, "ScreeWinch", 1.6)

func _validate_survey_trigger(source: Node, actor: String, expected_source: Node) -> bool:
	_initialize_or_restore_boss_authority()
	return source == expected_source and source == _survey_interactable \
		and not _watch_vantage_reached \
		and _boss_interaction_actor_ready_at(source, actor)


func _validate_winch_trigger(source: Node, actor: String, expected_source: Node) -> bool:
	_initialize_or_restore_boss_authority()
	return source == expected_source and source == _winch_interactable \
		and not _winch_batch_active() \
		and _boss_interaction_actor_ready_at(source, actor)


func _validate_brake_trigger(source: Node, actor: String, expected_source: Node) -> bool:
	_initialize_or_restore_boss_authority()
	return source == expected_source and source == _brake_ia \
		and not _crossing_occupied() \
		and str(_brake_transaction.get("phase", BRAKE_TRANSACTION_IDLE)) \
			!= BRAKE_TRANSACTION_RESERVED \
		and _boss_interaction_actor_ready_at(source, actor)


func _boss_interaction_actor_ready_at(source: Node, actor: String) -> bool:
	var gs = _get_game_state()
	if gs == null or not is_instance_valid(source) or not (source is Node3D) \
			or actor == "" or not gs.characters.has(actor) \
			or not gs.is_narratively_available(actor) \
			or gs.is_downed(actor) or gs.is_knocked_down(actor) \
			or gs.is_moving(actor) or gs.is_resting(actor) or gs.is_dodging(actor) \
			or gs.is_endocytosing(actor) or gs.is_external_traversal_active(actor) \
			or gs.is_dragging(actor) or gs.is_field_restoring(actor):
		return false
	var required_actor := str(source.get("required_character"))
	if required_actor != "" and actor != required_actor:
		return false
	var source_pos := _boss_control_data_position(source)
	var actor_pos: Vector3 = gs.get_position(actor)
	return Vector2(actor_pos.x, actor_pos.z).distance_to(
		Vector2(source_pos.x, source_pos.z)
	) <= float(source.get("interaction_radius")) + BOSS_INTERACTION_POSITION_TOLERANCE


func _boss_control_data_position(source: Node) -> Vector3:
	var gs = _get_game_state()
	var data_id := str(source.get("data_id")) if source != null else ""
	if gs != null and data_id != "" and gs.has_interactable(data_id):
		var saved_position: Variant = gs.get_interactable(data_id).get("position", Vector3.ZERO)
		if saved_position is Vector3:
			return saved_position
	var source_pos := (source as Node3D).global_position \
		if source is Node3D else Vector3.ZERO
	if gs != null and gs.coord_map != null and gs.coord_map.has_method("to_data"):
		return gs.coord_map.to_data(source_pos)
	return source_pos


func _boss_source_trigger_count(source: Node) -> int:
	var gs = _get_game_state()
	var data_id := str(source.get("data_id")) if source != null else ""
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return -1
	return int(gs.get_interactable(data_id).get("trigger_count", -1))


func _boss_consumed_source_receipt(
	source: Node,
	expected_source: Node,
	consumed_count: int,
	require_one_shot: bool
) -> bool:
	if not is_instance_valid(source) or source != expected_source:
		return false
	var actor := str(source.get("active_character"))
	if not _boss_interaction_actor_ready_at(source, actor):
		return false
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return false
	var receipt: Dictionary = gs.get_interactable(data_id)
	var trigger_count := int(receipt.get("trigger_count", -1))
	if trigger_count != consumed_count + 1 \
			or str(receipt.get("last_trigger_character", "")) != actor \
			or not bool(receipt.get("triggered", false)):
		return false
	if require_one_shot:
		return bool(source.get("one_shot")) and bool(source.get("_used")) \
			and not bool(source.get("interaction_enabled")) \
			and bool(receipt.get("one_shot", false)) \
			and not bool(receipt.get("enabled", true))
	return not bool(source.get("one_shot")) and not bool(receipt.get("one_shot", false))


func _on_watch_vantage_reached(source: Node = null) -> bool:
	_initialize_or_restore_boss_authority()
	if source != _survey_interactable \
			or not _boss_consumed_source_receipt(
				source, _survey_interactable, _survey_trigger_consumed, true
			) \
			or _watch_vantage_reached:
		return false
	_survey_trigger_consumed = _boss_source_trigger_count(source)
	_survey_actor = str(source.get("active_character"))
	_watch_vantage_reached = true
	_publish_boss_authority()
	_set_preview_step("watchtower_vantage")
	_show_note("Act II, laid out below. The tower watches it all.", 3.0)
	return true

## The winch fires the chute: everything on the base apron is SWEPT off the trail head (pushed
## outward — fail-forward, never a kill), and the head becomes loose scree for a span: the climb
## runs at half pace for everyone, including you. Logged moves + scheduler restore — replay-safe.
func _on_winch_used(source: Node = null) -> bool:
	_initialize_or_restore_boss_authority()
	if source != _winch_interactable or _winch_batch_active() \
			or not _boss_consumed_source_receipt(
				source, _winch_interactable, _winch_trigger_consumed, false
			):
		return false
	var gs = _get_game_state()
	if gs == null or fragment == null:
		return false
	var apron := Vector3(TOWER_X - 5.4, 0, CRAG_R + 1.0)
	_winch_trigger_consumed = _boss_source_trigger_count(source)
	_winch_batch_serial += 1
	var targets := _build_winch_batch_targets(apron, _winch_batch_serial)
	_flight_scramble = true
	var sched = _get_scheduler()
	if sched != null:
		_scramble_deadline = float(sched.get_current_tick()) + SCRAMBLE_SECS
	_winch_batch = {
		"version": 1,
		"phase": WINCH_BATCH_RESERVED,
		"serial": _winch_batch_serial,
		"receipt_count": _winch_trigger_consumed,
		"actor": str(source.get("active_character")),
		"source_id": str(source.get("data_id")),
		"started_tick": _tick(),
		"scramble_deadline": _scramble_deadline,
		"targets": targets,
	}
	# Commit the complete cohort and every endpoint before the first movement signal can expose a
	# partial batch to save/replay.
	_publish_boss_authority()
	_apply_scramble_presenter()
	if _scramble_deadline >= 0.0:
		_schedule_scramble_end(_scramble_deadline)
	_drain_winch_batch()
	_show_note(
		"The chute lets go. The trail head is scree — %d swept off it." % targets.size(),
		2.8)
	return true


func _scree_traversal_id(char_id: String, serial: int = _winch_batch_serial) -> StringName:
	return StringName("boss_scree:%s:%d:%s" % [boss_authority_key(), serial, char_id])


func _build_winch_batch_targets(apron: Vector3, serial: int) -> Array:
	var gs = _get_game_state()
	var targets: Array = []
	if gs == null:
		return targets
	var ids: Array[String] = []
	for id_v in gs.characters.keys():
		ids.append(str(id_v))
	ids.sort()
	for id in ids:
		var origin: Vector3 = gs.get_position(id)
		if Vector2(origin.x - apron.x, origin.z - apron.z).length() > 3.2 \
				or origin.y > 1.2 or not _winch_sweep_target_available(id):
			continue
		var away := Vector3(origin.x - TOWER_X, 0.0, origin.z).normalized()
		if away.length_squared() <= 0.000001:
			away = Vector3(-1.0, 0.0, 0.0)
		var destination := origin + away * 4.2
		var render_origin: Vector3 = gs.get_render_position(id)
		var render_destination := destination
		if gs.coord_map != null and gs.coord_map.has_method("to_world"):
			render_destination = gs.coord_map.to_world(destination)
		var enemy = _boss_enemy_for_id(id)
		var damage := WINCH_IMPACT_DAMAGE if enemy != null else 0.0
		var hp_before := float(enemy.get_hp()) \
			if enemy != null and enemy.has_method("get_hp") else 0.0
		targets.append({
			"id": id,
			"origin": _boss_vec3_to_data(origin),
			"destination": _boss_vec3_to_data(destination),
			"render_origin": _boss_vec3_to_data(render_origin),
			"render_destination": _boss_vec3_to_data(render_destination),
			"traversal_id": str(_scree_traversal_id(id, serial)),
			"planned_start_tick": _tick(),
			"planned_end_tick": _tick() + SCREE_SWEEP_DURATION,
			"enemy": enemy != null,
			"damage": damage,
			"hp_before": hp_before,
			"hp_after": maxf(0.0, hp_before - damage),
			"start_committed": false,
			"traversal_started": false,
			"arrived": false,
			"impact_committed": false,
			"impact_applied": false,
			"cancelled": false,
		})
	return targets


func _winch_sweep_target_available(char_id: String) -> bool:
	var gs = _get_game_state()
	return gs != null and gs.characters.has(char_id) \
		and not gs.is_downed(char_id) and not gs.is_knocked_down(char_id) \
		and not gs.is_dodging(char_id) and not gs.is_endocytosing(char_id) \
		and not gs.is_external_traversal_active(char_id) and not gs.is_dragging(char_id)


func _boss_enemy_for_id(char_id: String):
	for enemy in _enemies:
		if is_instance_valid(enemy) and str(enemy.char_id) == char_id:
			return enemy
	return null


func _winch_batch_active() -> bool:
	return str(_winch_batch.get("phase", WINCH_BATCH_IDLE)) \
		in [WINCH_BATCH_RESERVED, WINCH_BATCH_SWEEPING]


func _winch_target_at_position(target: Dictionary, key: String) -> bool:
	var gs = _get_game_state()
	var char_id := str(target.get("id", ""))
	if gs == null or char_id == "" or not gs.characters.has(char_id):
		return false
	return gs.get_position(char_id).distance_to(
		_boss_vec3_from_data(target.get(key, null), Vector3.INF)
	) <= POSITION_RECEIPT_TOLERANCE


func _boss_vec3_to_data(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _boss_vec3_from_data(value: Variant, fallback := Vector3.ZERO) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and (value as Array).size() >= 3:
		return Vector3(
			float((value as Array)[0]),
			float((value as Array)[1]),
			float((value as Array)[2])
		)
	return fallback


func _set_winch_batch_target(index: int, target: Dictionary) -> void:
	var targets: Array = _winch_batch.get("targets", [])
	if index < 0 or index >= targets.size():
		return
	targets[index] = target
	_winch_batch["targets"] = targets


func _drain_winch_batch() -> void:
	if not _winch_batch_active():
		return
	var gs = _get_game_state()
	if gs == null:
		return
	if str(_winch_batch.get("phase", "")) == WINCH_BATCH_RESERVED:
		_winch_batch["phase"] = WINCH_BATCH_SWEEPING
		_publish_boss_authority()
	var targets: Array = _winch_batch.get("targets", [])
	for index in range(targets.size()):
		var target := (targets[index] as Dictionary).duplicate(true)
		if bool(target.get("impact_applied", false)):
			continue
		var char_id := str(target.get("id", ""))
		var traversal_id := StringName(str(target.get("traversal_id", "")))
		var active: Dictionary = gs.get_external_traversal_state(char_id)
		if not active.is_empty() \
				and StringName(str(active.get("traversal_id", ""))) == traversal_id:
			if not bool(target.get("start_committed", false)) \
					or not bool(target.get("traversal_started", false)):
				target["start_committed"] = true
				target["traversal_started"] = true
				_set_winch_batch_target(index, target)
				_publish_boss_authority()
			continue
		if bool(target.get("start_committed", false)) \
				and _winch_target_at_position(target, "destination"):
			_commit_winch_target_arrival(index)
			continue
		if not bool(target.get("start_committed", false)):
			target["start_committed"] = true
			_set_winch_batch_target(index, target)
			# This edge is the per-body movement reservation. A signal-time save before
			# GameState accepts the command can resume it from the exact stored origin.
			_publish_boss_authority()
		if not _winch_target_at_position(target, "origin"):
			continue
		var now := _tick()
		var duration := maxf(
			0.000001, float(target.get("planned_end_tick", now)) - now)
		if gs.command_external_traversal(
				char_id,
				traversal_id,
				_boss_vec3_from_data(target.get("destination", null)),
				_boss_vec3_from_data(target.get("render_origin", null)),
				_boss_vec3_from_data(target.get("render_destination", null)),
				duration,
				&"locked"):
			target["traversal_started"] = true
			_set_winch_batch_target(index, target)
			_publish_boss_authority()
	_finish_winch_batch_if_complete()


func _commit_winch_target_arrival(index: int) -> void:
	var targets: Array = _winch_batch.get("targets", [])
	if index < 0 or index >= targets.size():
		return
	var target := (targets[index] as Dictionary).duplicate(true)
	if bool(target.get("impact_applied", false)) \
			or not _winch_target_at_position(target, "destination"):
		return
	if not bool(target.get("impact_committed", false)):
		target["arrived"] = true
		target["impact_committed"] = true
		target["impact_tick"] = _tick()
		_set_winch_batch_target(index, target)
		# Arrival is already physical GameState truth. Commit the exact damage receipt before
		# Enemy's synchronous damaged/state signals can expose the middle of the impact.
		_publish_boss_authority()
	if not _reconcile_winch_target_damage(target):
		return
	target["impact_applied"] = true
	_set_winch_batch_target(index, target)
	_publish_boss_authority()
	_finish_winch_batch_if_complete()


func _reconcile_winch_target_damage(target: Dictionary) -> bool:
	if not bool(target.get("enemy", false)) \
			or float(target.get("damage", 0.0)) <= 0.0:
		return true
	var enemy = _boss_enemy_for_id(str(target.get("id", "")))
	if enemy == null or not enemy.has_method("get_hp"):
		return true
	var hp_before := float(target.get("hp_before", enemy.get_hp()))
	var hp_after := float(target.get("hp_after", hp_before))
	var current_hp := float(enemy.get_hp())
	if current_hp <= hp_after + 0.0001:
		return true
	if is_equal_approx(current_hp, hp_before):
		enemy.take_damage(float(target.get("damage", 0.0)))
		return true
	return false


func _finish_winch_batch_if_complete() -> void:
	if not _winch_batch_active():
		return
	for target_v in (_winch_batch.get("targets", []) as Array):
		if not bool((target_v as Dictionary).get("impact_applied", false)):
			return
	_winch_batch["phase"] = WINCH_BATCH_COMPLETE
	_winch_batch["completed_tick"] = _tick()
	_publish_boss_authority()


func _on_boss_external_traversal_finished(
	char_id: String, traversal_id: StringName
) -> void:
	if not _winch_batch_active():
		return
	var targets: Array = _winch_batch.get("targets", [])
	for index in range(targets.size()):
		var target := targets[index] as Dictionary
		if str(target.get("id", "")) == char_id \
				and StringName(str(target.get("traversal_id", ""))) == traversal_id:
			_commit_winch_target_arrival(index)
			return


func _on_boss_external_traversal_cancelled(
	char_id: String, traversal_id: StringName, reason: StringName
) -> void:
	if not _winch_batch_active():
		return
	var targets: Array = _winch_batch.get("targets", [])
	for index in range(targets.size()):
		var target := (targets[index] as Dictionary).duplicate(true)
		if str(target.get("id", "")) != char_id \
				or StringName(str(target.get("traversal_id", ""))) != traversal_id:
			continue
		target["cancelled"] = true
		target["cancel_reason"] = str(reason)
		target["impact_committed"] = true
		target["impact_applied"] = true
		_set_winch_batch_target(index, target)
		_publish_boss_authority()
		_finish_winch_batch_if_complete()
		return


func _bind_boss_external_traversal_signals() -> void:
	var gs = _get_game_state()
	if gs == _boss_signal_game_state:
		return
	_unbind_boss_external_traversal_signals()
	_boss_signal_game_state = gs
	if gs == null:
		return
	var finished := Callable(self, "_on_boss_external_traversal_finished")
	var cancelled := Callable(self, "_on_boss_external_traversal_cancelled")
	if not gs.external_traversal_finished.is_connected(finished):
		gs.external_traversal_finished.connect(finished)
	if not gs.external_traversal_cancelled.is_connected(cancelled):
		gs.external_traversal_cancelled.connect(cancelled)


func _unbind_boss_external_traversal_signals() -> void:
	if _boss_signal_game_state == null or not is_instance_valid(_boss_signal_game_state):
		_boss_signal_game_state = null
		return
	var finished := Callable(self, "_on_boss_external_traversal_finished")
	var cancelled := Callable(self, "_on_boss_external_traversal_cancelled")
	if _boss_signal_game_state.external_traversal_finished.is_connected(finished):
		_boss_signal_game_state.external_traversal_finished.disconnect(finished)
	if _boss_signal_game_state.external_traversal_cancelled.is_connected(cancelled):
		_boss_signal_game_state.external_traversal_cancelled.disconnect(cancelled)
	_boss_signal_game_state = null


func _apply_scramble_presenter() -> void:
	for ct in _climb_tunnels:
		if is_instance_valid(ct):
			ct.crawl_speed = CLIMB_SPEED * 0.5 if _flight_scramble else CLIMB_SPEED


func _arm_winch_batch_resume() -> void:
	var sched = _get_scheduler()
	if sched == null or not _winch_batch_active():
		return
	sched.cancel_tag(_boss_tag("winch_batch_resume"))
	sched.schedule_after(0.0, _resume_winch_batch, _boss_tag("winch_batch_resume"))
	_winch_batch_resume_armed = true


func _resume_winch_batch() -> void:
	_winch_batch_resume_armed = false
	_drain_winch_batch()


func _reconcile_winch_batch_on_restore() -> bool:
	if not _winch_batch_active():
		return false
	var gs = _get_game_state()
	if gs == null:
		return false
	var changed := false
	var targets: Array = _winch_batch.get("targets", [])
	for index in range(targets.size()):
		var target := (targets[index] as Dictionary).duplicate(true)
		var target_changed := false
		var char_id := str(target.get("id", ""))
		var traversal_id := StringName(str(target.get("traversal_id", "")))
		var active: Dictionary = gs.get_external_traversal_state(char_id)
		if not active.is_empty() \
				and StringName(str(active.get("traversal_id", ""))) == traversal_id:
			if not bool(target.get("start_committed", false)) \
					or not bool(target.get("traversal_started", false)):
				target["start_committed"] = true
				target["traversal_started"] = true
				target_changed = true
		elif bool(target.get("start_committed", false)) \
				and _winch_target_at_position(target, "destination") \
				and not bool(target.get("impact_committed", false)):
			target["arrived"] = true
			target["impact_committed"] = true
			target["impact_tick"] = _tick()
			target_changed = true
		if target_changed:
			targets[index] = target
			changed = true
	_winch_batch["targets"] = targets
	return changed

func _schedule_scramble_end(deadline: float) -> void:
	var sched = _get_scheduler()
	if sched == null or deadline < 0.0:
		return
	sched.cancel_tag(_boss_tag("watch_scramble"))
	var now := float(sched.get_current_tick())
	sched.schedule_at(
		maxf(now, deadline), _end_scramble.bind(deadline), _boss_tag("watch_scramble")
	)

func _end_scramble(expected_deadline := -1.0) -> void:
	if expected_deadline >= 0.0 and not is_equal_approx(_scramble_deadline, expected_deadline):
		return
	_flight_scramble = false
	_scramble_deadline = -1.0
	for ct in _climb_tunnels:
		if is_instance_valid(ct):
			ct.crawl_speed = CLIMB_SPEED
	_publish_boss_authority()

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

# --- The projection-alignment crossing (the Monument Valley payoff) --------
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
	_brake_ia.set_pre_trigger_validator(_validate_brake_trigger.bind(_brake_ia))
	_brake_ia.interacted.connect(_on_brake_used.bind(_brake_ia))
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
	_build_spiker_hazard_field()


func _build_spiker_hazard_field() -> void:
	var gs = _get_game_state()
	var scheduler = _get_scheduler()
	if gs == null or scheduler == null or fragment == null:
		return
	_spiker_field = HazardFieldScript.new()
	_spiker_field.name = "RingSpikerHazardField"
	add_child(_spiker_field)
	_spiker_field.setup(
		gs,
		scheduler,
		Vector2(PARA_X - 1.3, -6.3),
		Vector2(PARA_X + 1.3, 6.3),
		Array(fragment.party_ids),
		{
			"dps_tick": SPIKER_DMG * ALIGN_POLL,
			"interval": ALIGN_POLL,
			"tag": "boss_ring_spiker_%d" % _seed,
			"target_filter": Callable(self, "_spiker_target_exposed"),
		}
	)
	_spiker_field.set_active(false)


func _spiker_target_exposed(char_id: String, _position: Vector3) -> bool:
	var gs = _get_game_state()
	return gs != null and gs.characters.has(char_id) and not gs.is_character_hidden(char_id)

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
func _on_brake_used(source: Node = null) -> bool:
	_initialize_or_restore_boss_authority()
	if source != _brake_ia or _crossing_occupied() \
			or not _boss_consumed_source_receipt(
				source, _brake_ia, _brake_trigger_consumed, false
			):
		return false
	_brake_trigger_consumed = _boss_source_trigger_count(source)
	_brake_transaction = _make_brake_transaction(
		_brake_trigger_consumed, str(source.get("active_character")))
	# The chosen detent/release offset is portable before the wheel moves. A save observer on this
	# world-state edge therefore restores the same target rather than recomputing from a later tick.
	_publish_boss_authority()
	_apply_brake_transaction(_brake_transaction)
	_brake_transaction["phase"] = BRAKE_TRANSACTION_COMMITTED
	_publish_boss_authority()
	return true


func _make_brake_transaction(receipt_count: int, actor: String) -> Dictionary:
	var t := _tick()
	var w := _wheels[0] as Dictionary
	var target_is_parked := _ring0_parked == INF
	var target_phase := 0.0
	var target_offset := float(_ring_offsets[0])
	if _ring0_parked != INF:
		target_offset = wrapf(_ring0_parked - float(w["spin"]) * t, 0.0, TAU)
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
		target_phase = best
	return {
		"version": 1,
		"phase": BRAKE_TRANSACTION_RESERVED,
		"receipt_count": receipt_count,
		"actor": actor,
		"committed_tick": t,
		"from_is_parked": _ring0_parked != INF,
		"from_parked_phase": _ring0_parked if _ring0_parked != INF else 0.0,
		"from_offset": float(_ring_offsets[0]),
		"target_is_parked": target_is_parked,
		"target_parked_phase": target_phase,
		"target_offset": target_offset,
	}


func _apply_brake_transaction(transaction: Dictionary) -> void:
	if _ring_offsets.is_empty():
		return
	_ring_offsets[0] = wrapf(
		float(transaction.get("target_offset", _ring_offsets[0])), 0.0, TAU)
	_ring0_parked = wrapf(
		float(transaction.get("target_parked_phase", 0.0)), 0.0, TAU
	) if bool(transaction.get("target_is_parked", false)) else INF
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
	_align_poll_epoch = float(sched.get_current_tick())
	# Initialization may be discovered by a render frame, but that frame must not deal damage.
	# Project the gate immediately, then let the first authoritative Spiker consequence arrive on
	# the same fixed cadence as every later one.
	_refresh_crossing_gate()
	_schedule_align_poll_at(_align_poll_epoch + ALIGN_POLL)
	_publish_boss_authority()

func _run_align_poll(expected_tick: float) -> void:
	if not _align_poll_started:
		return
	if _align_next_tick >= 0.0 and not is_equal_approx(_align_next_tick, expected_tick):
		return
	_align_next_tick = -1.0
	_refresh_crossing_gate()
	_apply_spiker_fire()
	_schedule_align_poll_at(expected_tick + ALIGN_POLL)

func _schedule_align_poll_at(deadline: float) -> void:
	var sched = _get_scheduler()
	if sched == null or not _align_poll_started:
		return
	sched.cancel_tag(_boss_tag("align_poll"))
	_align_next_tick = deadline
	sched.schedule_at(deadline, _run_align_poll.bind(deadline), _boss_tag("align_poll"))

func _next_align_poll_after(tick: float) -> float:
	if _align_poll_epoch < 0.0:
		return -1.0
	return FixedCadenceScript.next_strict_tick(_align_poll_epoch, ALIGN_POLL, tick)

## Alignment cadence toggles the reusable HazardField bound to the rotating branch.
## The visible branch is the telegraph; the field owns each later impact and its
## save/load deadline. Concealment is injected as the field's target filter.
func _apply_spiker_fire() -> void:
	if _spiker_field != null:
		_spiker_field.set_active(spiker_at_bottom(_tick()))

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
## the emissive branch; spiker_at_bottom() drives the reusable saved HazardField.
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

# --- portable boss-mechanism authority ----------------------------------------------------------

func boss_authority_key() -> String:
	return "%s%d:%s" % [BOSS_AUTHORITY_PREFIX, _seed, "finale" if _finale else "showcase"]

func _boss_authority_state() -> Dictionary:
	var offsets: Array = []
	for offset in _ring_offsets:
		offsets.append(float(offset))
	return {
		"version": BOSS_AUTHORITY_VERSION,
		"seed": _seed,
		"finale": _finale,
		"prize_retrieved": _prize_phase == PRIZE_PHASE_CLAIMED,
		"prize_phase": _prize_phase,
		"prize_item_id": _prize_item_id,
		"prize_claimed_by": _prize_claimed_by,
		"prize_claim_serial": _prize_claim_serial,
		"watch_vantage_reached": _watch_vantage_reached,
		"survey_trigger_consumed": _survey_trigger_consumed,
		"survey_actor": _survey_actor,
		"winch_trigger_consumed": _winch_trigger_consumed,
		"winch_batch_serial": _winch_batch_serial,
		"winch_batch": _winch_batch.duplicate(true),
		"brake_trigger_consumed": _brake_trigger_consumed,
		"brake_transaction": _brake_transaction.duplicate(true),
		"flight_scramble": _flight_scramble,
		"scramble_deadline": _scramble_deadline,
		"ring0_is_parked": _ring0_parked != INF,
		"ring0_parked_phase": _ring0_parked if _ring0_parked != INF else 0.0,
		"ring_offsets": offsets,
		"align_poll_started": _align_poll_started,
		# One absolute cadence epoch reconstructs every later poll without writing world-state four
		# times a second. It is the deadline provenance, not a scene-local "armed" boolean.
		"align_poll_epoch": _align_poll_epoch,
	}

func _publish_boss_authority() -> void:
	if _restoring_boss_authority:
		return
	var gs = _get_game_state()
	if gs != null and gs.has_method("set_world_state"):
		gs.set_world_state(boss_authority_key(), _boss_authority_state())


func _valid_boss_authority(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var saved := raw as Dictionary
	var version := int(saved.get("version", 0))
	if version not in [1, 2, BOSS_AUTHORITY_VERSION]:
		return false
	if version < 2:
		return true
	var phase := str(saved.get("prize_phase", ""))
	if phase not in [PRIZE_PHASE_AVAILABLE, PRIZE_PHASE_CLAIMING, PRIZE_PHASE_CLAIMED] \
			or str(saved.get("prize_item_id", "")) == "" \
			or int(saved.get("prize_claim_serial", -1)) < 0:
		return false
	var actor := str(saved.get("prize_claimed_by", ""))
	if phase == PRIZE_PHASE_AVAILABLE:
		if actor != "":
			return false
	elif actor == "":
		return false
	if version < 3:
		return true
	if int(saved.get("survey_trigger_consumed", -1)) < 0 \
			or int(saved.get("winch_trigger_consumed", -1)) < 0 \
			or int(saved.get("winch_batch_serial", -1)) < 0 \
			or int(saved.get("brake_trigger_consumed", -1)) < 0:
		return false
	var batch: Variant = saved.get("winch_batch", {})
	var brake: Variant = saved.get("brake_transaction", {})
	if not batch is Dictionary or not brake is Dictionary:
		return false
	if not (batch as Dictionary).is_empty() \
			and str((batch as Dictionary).get("phase", "")) not in [
				WINCH_BATCH_RESERVED, WINCH_BATCH_SWEEPING, WINCH_BATCH_COMPLETE
			]:
		return false
	if not (brake as Dictionary).is_empty() \
			and str((brake as Dictionary).get("phase", "")) not in [
				BRAKE_TRANSACTION_RESERVED, BRAKE_TRANSACTION_COMMITTED
			]:
		return false
	return true


## A save observer can capture either side of GameState's synchronous item_picked_up signal. The
## physical item resolves that ambiguity: source-ground means the command never committed; any
## non-source location means it did. Neither branch spawns or moves another item.
func _reconcile_restored_prize_transaction() -> bool:
	var changed := false
	if not _is_boss_prize_item(_prize_item_id):
		var found := _find_boss_prize_item_id()
		if found != "" and _prize_phase != PRIZE_PHASE_CLAIMED:
			_prize_item_id = found
			changed = true
	var item := _get_item_state(_prize_item_id)
	if item.is_empty():
		if _prize_phase == PRIZE_PHASE_CLAIMING:
			_prize_phase = PRIZE_PHASE_AVAILABLE
			_prize_claimed_by = ""
			changed = true
		return changed
	var at_source := _prize_item_at_source()
	match _prize_phase:
		PRIZE_PHASE_AVAILABLE:
			if not at_source:
				_prize_phase = PRIZE_PHASE_CLAIMED
				_prize_claimed_by = str(item.get("holder", ""))
				if _prize_claimed_by == "":
					_prize_claimed_by = "unknown_physical_claim"
				_prize_claim_serial = maxi(_prize_claim_serial, 1)
				changed = true
		PRIZE_PHASE_CLAIMING:
			if at_source:
				_prize_phase = PRIZE_PHASE_AVAILABLE
				_prize_claimed_by = ""
				changed = true
			else:
				_prize_phase = PRIZE_PHASE_CLAIMED
				if str(item.get("holder", "")) != "":
					_prize_claimed_by = str(item.get("holder", ""))
				changed = true
	return changed


## Boss authority owns the durable prize phase; the Interactable registry owns only the tiny
## accepted-source edge. A signal-time save can contain a consumed one-shot while the item and boss
## record are still AVAILABLE. Re-arm that uncommitted edge instead of granting a remote pickup or
## leaving the visible vial permanently unusable. This also upgrades older repeatable prize specs.
func _normalize_prize_source_receipt_registry() -> void:
	if not is_instance_valid(_prize_interactable):
		return
	_prize_interactable.one_shot = true
	var gs = _get_game_state()
	var data_id := str(_prize_interactable.data_id)
	if gs != null and data_id != "" and gs.has_interactable(data_id):
		var spec: Dictionary = gs.get_interactable(data_id)
		if not bool(spec.get("one_shot", false)):
			spec["id"] = data_id
			spec["one_shot"] = true
			spec["triggered"] = false
			spec["enabled"] = true
			gs.register_interactable(spec)
	if _prize_phase == PRIZE_PHASE_AVAILABLE and _prize_item_at_source() \
			and _prize_interactable.has_method("reset"):
		_prize_interactable.reset()


## A save can observe GameState's accepted trigger before this owner receives the source signal.
## Such a receipt has no owner reservation and therefore grants nothing after load. Consume its
## monotonic identity (so a stale callback is inert), and re-arm the one-shot survey for a retry.
func _normalize_boss_control_source_receipts() -> bool:
	var changed := false
	if is_instance_valid(_survey_interactable):
		var survey_count := _boss_source_trigger_count(_survey_interactable)
		if survey_count > _survey_trigger_consumed:
			_survey_trigger_consumed = survey_count
			changed = true
		if not _watch_vantage_reached:
			var gs = _get_game_state()
			var data_id := str(_survey_interactable.get("data_id"))
			var receipt: Dictionary = gs.get_interactable(data_id) \
				if gs != null and data_id != "" and gs.has_interactable(data_id) else {}
			if bool(receipt.get("triggered", false)) \
					and _survey_interactable.has_method("reset"):
				_survey_interactable.reset()
				_survey_actor = ""
				changed = true
	if is_instance_valid(_winch_interactable):
		var winch_count := _boss_source_trigger_count(_winch_interactable)
		var owned_winch_receipt := int(_winch_batch.get("receipt_count", -1))
		if winch_count > _winch_trigger_consumed \
				and owned_winch_receipt != winch_count:
			_winch_trigger_consumed = winch_count
			changed = true
	if is_instance_valid(_brake_ia):
		var brake_count := _boss_source_trigger_count(_brake_ia)
		var owned_brake_receipt := int(_brake_transaction.get("receipt_count", -1))
		if brake_count > _brake_trigger_consumed \
				and owned_brake_receipt != brake_count:
			_brake_trigger_consumed = brake_count
			changed = true
	return changed


func _initialize_or_restore_boss_authority() -> void:
	if _boss_authority_initialized or _wheels.is_empty():
		return
	_bind_boss_external_traversal_signals()
	_boss_authority_initialized = true
	var gs = _get_game_state()
	var raw: Variant = gs.get_world_state(boss_authority_key(), null) \
		if gs != null and gs.has_method("get_world_state") else null
	if _valid_boss_authority(raw) \
			and int(raw.get("seed", _seed)) == _seed \
			and bool(raw.get("finale", _finale)) == _finale:
		_restore_boss_authority(raw)
	else:
		_reset_prize_to_available()
		_survey_trigger_consumed = maxi(
			0, _boss_source_trigger_count(_survey_interactable))
		_survey_actor = ""
		_winch_trigger_consumed = maxi(
			0, _boss_source_trigger_count(_winch_interactable))
		_winch_batch_serial = 0
		_winch_batch.clear()
		_brake_trigger_consumed = maxi(0, _boss_source_trigger_count(_brake_ia))
		_brake_transaction.clear()
		_publish_boss_authority()

func on_game_state_snapshot_restored() -> void:
	super.on_game_state_snapshot_restored()
	_cancel_boss_callbacks()
	_bind_boss_external_traversal_signals()
	_boss_authority_initialized = true
	var gs = _get_game_state()
	var raw: Variant = gs.get_world_state(boss_authority_key(), null) \
		if gs != null and gs.has_method("get_world_state") else null
	if not _valid_boss_authority(raw) \
			or int(raw.get("seed", _seed)) != _seed \
			or bool(raw.get("finale", _finale)) != _finale:
		_retract_boss_to_defaults()
		_publish_boss_authority()
		return
	_restore_boss_authority(raw)

func _restore_boss_authority(saved: Dictionary) -> void:
	_restoring_boss_authority = true
	_cancel_boss_callbacks()
	var saved_version := int(saved.get("version", 1))
	var normalized := saved_version < BOSS_AUTHORITY_VERSION
	if saved_version >= 2:
		_prize_phase = str(saved.get("prize_phase", PRIZE_PHASE_AVAILABLE))
		_prize_item_id = str(saved.get("prize_item_id", ""))
		_prize_claimed_by = str(saved.get("prize_claimed_by", ""))
		_prize_claim_serial = maxi(0, int(saved.get("prize_claim_serial", 0)))
	else:
		# Version 1 had only a solved boolean and no physical reward. Create exactly one tagged
		# migration item, preserving whether the old objective had already fired without guessing a
		# historical holder.
		_prize_phase = PRIZE_PHASE_CLAIMED \
			if bool(saved.get("prize_retrieved", false)) else PRIZE_PHASE_AVAILABLE
		_prize_claimed_by = "unknown_legacy" \
			if _prize_phase == PRIZE_PHASE_CLAIMED else ""
		_prize_claim_serial = 1 if _prize_phase == PRIZE_PHASE_CLAIMED else 0
		_prize_item_id = _find_boss_prize_item_id()
		if _prize_item_id == "":
			_prize_item_id = _spawn_prize_item({"legacy_v1_migration": true})
	if _reconcile_restored_prize_transaction():
		normalized = true
	_normalize_prize_source_receipt_registry()
	_watch_vantage_reached = bool(saved.get("watch_vantage_reached", false))
	if saved_version >= 3:
		_survey_trigger_consumed = maxi(
			0, int(saved.get("survey_trigger_consumed", 0)))
		_survey_actor = str(saved.get("survey_actor", ""))
		_winch_trigger_consumed = maxi(
			0, int(saved.get("winch_trigger_consumed", 0)))
		_winch_batch_serial = maxi(0, int(saved.get("winch_batch_serial", 0)))
		_winch_batch = (saved.get("winch_batch", {}) as Dictionary).duplicate(true)
		_brake_trigger_consumed = maxi(
			0, int(saved.get("brake_trigger_consumed", 0)))
		_brake_transaction = (
			saved.get("brake_transaction", {}) as Dictionary
		).duplicate(true)
	else:
		_survey_trigger_consumed = maxi(
			0, _boss_source_trigger_count(_survey_interactable))
		_survey_actor = ""
		_winch_trigger_consumed = maxi(
			0, _boss_source_trigger_count(_winch_interactable))
		_winch_batch_serial = 0
		_winch_batch.clear()
		_brake_trigger_consumed = maxi(0, _boss_source_trigger_count(_brake_ia))
		_brake_transaction.clear()
	_flight_scramble = bool(saved.get("flight_scramble", false))
	_scramble_deadline = float(saved.get("scramble_deadline", -1.0)) \
		if _flight_scramble else -1.0
	var saved_offsets: Array = saved.get("ring_offsets", []) as Array
	for i in range(_ring_offsets.size()):
		_ring_offsets[i] = float(saved_offsets[i]) if i < saved_offsets.size() else 0.0
	_ring0_parked = wrapf(float(saved.get("ring0_parked_phase", 0.0)), 0.0, TAU) \
		if bool(saved.get("ring0_is_parked", false)) else INF
	if not _brake_transaction.is_empty():
		_apply_brake_transaction(_brake_transaction)
		if str(_brake_transaction.get("phase", "")) == BRAKE_TRANSACTION_RESERVED:
			_brake_transaction["phase"] = BRAKE_TRANSACTION_COMMITTED
			normalized = true
	_align_poll_started = bool(saved.get("align_poll_started", false))
	_align_poll_epoch = float(saved.get("align_poll_epoch", -1.0)) \
		if _align_poll_started else -1.0
	_align_next_tick = -1.0
	if _reconcile_winch_batch_on_restore():
		normalized = true
	if _normalize_boss_control_source_receipts():
		normalized = true
	_apply_boss_presenters()
	_restoring_boss_authority = false
	if normalized:
		_publish_boss_authority()

	if _flight_scramble and _scramble_deadline >= 0.0:
		_schedule_scramble_end(_scramble_deadline)
	if _winch_batch_active():
		_arm_winch_batch_resume()
	if _align_poll_started and _align_poll_epoch >= 0.0:
		var next_tick := _next_align_poll_after(_tick())
		if next_tick >= 0.0:
			_schedule_align_poll_at(next_tick)

func _retract_boss_to_defaults() -> void:
	_restoring_boss_authority = true
	_reset_prize_to_available()
	_watch_vantage_reached = false
	_survey_actor = ""
	if is_instance_valid(_survey_interactable) \
			and _survey_interactable.has_method("reset"):
		_survey_interactable.reset()
	_survey_trigger_consumed = maxi(
		0, _boss_source_trigger_count(_survey_interactable))
	_winch_trigger_consumed = maxi(
		0, _boss_source_trigger_count(_winch_interactable))
	_winch_batch_serial = 0
	_winch_batch.clear()
	_brake_trigger_consumed = maxi(0, _boss_source_trigger_count(_brake_ia))
	_brake_transaction.clear()
	_flight_scramble = false
	_scramble_deadline = -1.0
	_ring0_parked = INF
	for i in range(_ring_offsets.size()):
		_ring_offsets[i] = 0.0
	_align_poll_started = false
	_align_poll_epoch = -1.0
	_align_next_tick = -1.0
	_apply_boss_presenters()
	_restoring_boss_authority = false

func _apply_boss_presenters() -> void:
	_apply_prize_presenter()
	if is_instance_valid(_survey_interactable) \
			and _survey_interactable.has_method("restore_one_shot_presenter"):
		_survey_interactable.restore_one_shot_presenter(
			_watch_vantage_reached, not _watch_vantage_reached)
	_apply_scramble_presenter()
	var t := _tick()
	for i in range(_wheels.size()):
		var phase := ring_phase(i, t)
		if i < _render_phases.size():
			_render_phases[i] = phase
		var wheel := _wheels[i] as Dictionary
		var node := wheel.get("node") as Node3D
		if node != null and is_instance_valid(node):
			node.basis = (wheel["base"] as Basis) * Basis(Vector3(0, 0, 1), phase)
	_refresh_crossing_gate()
	_update_causeway_visual(t)

func reset_preview_state() -> void:
	_cancel_boss_callbacks()
	super.reset_preview_state()
	_retract_boss_to_defaults()
	if _spiker_field != null:
		_spiker_field.set_active(false)
	var gs = _get_game_state()
	if gs != null:
		gs.set_world_state(VANTAGE_KEY, 0)
	_boss_authority_initialized = true
	_publish_boss_authority()

func _cancel_boss_callbacks() -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	# Cancel the un-prefixed fixed tags too, so an in-place reload cannot leave a stale callback
	# beside the seed-keyed one.
	sched.cancel_tag("watch_scramble")
	sched.cancel_tag("align_poll")
	sched.cancel_tag(_boss_tag("watch_scramble"))
	sched.cancel_tag(_boss_tag("align_poll"))
	sched.cancel_tag(_boss_tag("winch_batch_resume"))
	_align_next_tick = -1.0
	_winch_batch_resume_armed = false

func _boss_tag(suffix: String) -> String:
	return "boss_%s_%s" % [absi(boss_authority_key().hash()), suffix]

func _exit_tree() -> void:
	_cancel_boss_callbacks()
	_unbind_boss_external_traversal_signals()
	super._exit_tree()

## A sized label riding the shared _add_label (the base already owns the Label3D idiom).
func _add_boss_label(parent: Node3D, text: String, pos: Vector3, col: Color, size: int) -> void:
	var lbl := _add_label(parent, text, pos, col)
	lbl.font_size = size
	lbl.pixel_size = 0.006
	lbl.outline_size = 8
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y

func get_preview_state() -> Dictionary:
	var st: Dictionary = super.get_preview_state()
	var scree_traversals: Dictionary = {}
	var gs = _get_game_state()
	if gs != null:
		for char_id_v in gs.characters.keys():
			var char_id := str(char_id_v)
			var traversal: Dictionary = gs.get_external_traversal_state(char_id)
			if not traversal.is_empty() \
					and StringName(str(traversal.get("traversal_id", ""))) == _scree_traversal_id(char_id):
				scree_traversals[char_id] = traversal
	st["seed"] = _seed
	st["wheels"] = _wheels.size()
	st["crossing_open"] = crossing_open(_tick()) if not _wheels.is_empty() else false
	st["ring0_parked"] = _ring0_parked != INF
	var prize_item := _get_item_state(_prize_item_id)
	st["prize_retrieved"] = _prize_phase == PRIZE_PHASE_CLAIMED
	st["prize_phase"] = _prize_phase
	st["prize_item_id"] = _prize_item_id
	st["prize_item_exists"] = not prize_item.is_empty()
	st["prize_item_location"] = str(prize_item.get("location", "missing"))
	st["prize_item_holder"] = str(prize_item.get("holder", ""))
	st["prize_claimed_by"] = _prize_claimed_by
	st["prize_claim_serial"] = _prize_claim_serial
	st["spiker_clear"] = not spiker_at_bottom(_tick())
	st["spiker_hazard"] = _spiker_field.get_state() if _spiker_field != null else {}
	st["watch_vantage"] = _watch_vantage_reached
	st["survey_actor"] = _survey_actor
	st["survey_trigger_consumed"] = _survey_trigger_consumed
	st["winch_trigger_consumed"] = _winch_trigger_consumed
	st["winch_batch_serial"] = _winch_batch_serial
	st["winch_batch"] = _winch_batch.duplicate(true)
	st["brake_trigger_consumed"] = _brake_trigger_consumed
	st["brake_transaction"] = _brake_transaction.duplicate(true)
	st["scramble"] = _flight_scramble
	st["scramble_deadline"] = _scramble_deadline
	st["scree_traversals"] = scree_traversals
	st["align_poll_epoch"] = _align_poll_epoch
	st["align_next_tick"] = _align_next_tick
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
