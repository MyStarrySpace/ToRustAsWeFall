extends "res://scripts/scene_chunks/scene_chunk.gd"

## Showcase Gallery — a guided exhibit hall that shows off, in order, the three HIDING
## types, both ENEMY types, and the FLORA types. A safe central corridor runs west→east;
## each exhibit sits in a side alcove off it, so the player can walk the gallery and cause
## every response, then regroup the whole required party at the exit.
##   1. Hiding bay (south): three pads, one per concealment tier — EXPOSED (none), low
##      cover (medium), safehold (full). A demo sentry paces in front so each tier visibly
##      differs: exposed -> spotted, medium -> hidden unless it closes in, full -> never seen.
##   2. Enemy bay: a STANDARD sentry roaming + charging in a south wake zone, and a CHAIN
##      seam (segmented, wall-anchored) working a north zone. The corridor starts beyond their
##      reach; entering a marked zone wakes a live pursuit rather than pretending a floor patch is a pen.
##   3. Flora bay: the shipped field-ready flora objects, each exposing its real verb. Species
##      without a gameplay object are omitted; this room never substitutes a labelled prop.

const EnemyScript := preload("res://scripts/game/ai/enemy.gd")
const ChainEnemyScript := preload("res://scripts/game/ai/chain_enemy.gd")
const ScarpetScript := preload("res://scripts/game/objects/scarpet.gd")
const CapbageScript := preload("res://scripts/game/objects/capbage.gd")
const FlureScript := preload("res://scripts/game/objects/flure.gd")
const HushbloomScript := preload("res://scripts/game/objects/hushbloom.gd")
const GALLERY_AUTHORITY_VERSION := 2
const GALLERY_AUTHORITY_KEY := "runtime:showcase_gallery:tour"
const GALLERY_PHASE_TOURING := "touring"
const GALLERY_PHASE_COMPLETE := "complete"
const GALLERY_EVIDENCE_CONTRACT := "showcase_gallery_evidence/v1"
const GALLERY_COMPLETION_CONTRACT := "showcase_gallery_completion/v1"

const PARTY_IDS := ["aster", "peris", "endo"]

const FLOOR_CENTER := Vector3(41.0, -0.05, -2.0)
const FLOOR_SIZE := Vector3(88.0, 0.1, 32.0)

const ENTRY_POS := Vector3(3.0, 0.45, 0.0)
const EXIT_POS := Vector3(80.0, 0.45, 0.0)
const EXIT_X := 78.0

const SPAWNS := {
	"peris": Vector3(3.0, 0.5, 0.0),
	"aster": Vector3(2.0, 0.5, 1.4),
	"endo": Vector3(2.0, 0.5, -1.4),
}

# --- Bay 1: hiding. Pads sit north of the demo sentry's pace line; at the closest pass the
# pads are PAD_GAP (4m) away — beyond the medium inner band (~2.7m) but inside the outer
# range (5.5m), so EXPOSED is caught while MEDIUM holds. FULL is never seen. ---
const SENTRY_PACE_Z := -10.0
const PAD_Z := -6.0
const PAD_RADIUS := 1.6
const DEMO_SENTRY_RANGE := 5.5
const HIDE_PADS := [
	{"pos": Vector3(12.0, 0.45, PAD_Z), "tier": 0, "name": "EXPOSED", "sub": "no cover  —  NONE"},
	{"pos": Vector3(16.0, 0.45, PAD_Z), "tier": 1, "name": "SCARPET", "sub": "low cover  —  MEDIUM"},
	{"pos": Vector3(20.0, 0.45, PAD_Z), "tier": 2, "name": "CAPBAGE", "sub": "safehold  —  FULL"},
]
const PAD_TINTS := [Color(0.4, 0.16, 0.14), Color(0.7, 0.6, 0.3), Color(0.35, 0.7, 0.5)]

# --- Bay 2: enemies staged in alcoves 10m off the corridor (beyond their initial 5m reach). ---
const STANDARD_ANCHOR := Vector3(33.0, 0.5, -10.0)
const STANDARD_RANGE := 5.0
const CHAIN_ANCHOR := Vector3(44.0, 0.5, 10.0)
const CHAIN_RANGE := 5.0

# --- Bay 3: only flora with shipped gameplay objects. Unsupported species are omitted instead of
# being represented by a differently coloured copy of the same fake plant. The response sentry is
# placed between the Flure's settle point and the Hushbloom's burst, so both causal verbs are visible.
const FLORA_ORDER := ["scarpet", "capbage", "flure", "hushbloom"]
const FLORA_POSITIONS := {
	"scarpet": Vector3(54.0, 0.45, -5.0),
	"capbage": Vector3(58.0, 0.45, -5.0),
	"flure": Vector3(64.0, 0.45, -5.0),
	"hushbloom": Vector3(70.0, 0.45, -5.0),
}
const FLORA_TARGET_ANCHOR := Vector3(70.0, 0.5, -9.0)
const FLORA_TARGET_SETTLE := Vector3(67.0, 0.5, -7.0)
const FLORA_TARGET_ID := "gallery_flora_target"
const FLORA_TINTS := {
	"scarpet": Color(0.78, 0.66, 0.32),
	"flure": Color(0.9, 0.55, 0.28),
	"hushbloom": Color(0.45, 0.62, 0.95),
	"capbage": Color(0.93, 0.76, 0.42),
}

const REQUIRED_EVIDENCE := {
	"hide_exposed_spotted": {
		"source_id": "gallery_demo",
		"verb": "spotted_on_exposed_pad",
		"label": "let the hiding sentry spot an exposed body",
	},
	"hide_scarpet_occupied": {
		"source_id": "gallery_hide_scarpet",
		"verb": "occupied_medium_cover",
		"label": "stand a body in the hiding-bay Scarpet",
	},
	"hide_capbage_tucked": {
		"source_id": "gallery_hide_capbage",
		"verb": "tucked_into_full_cover",
		"label": "tuck a body into the hiding-bay Capbage",
	},
	"enemy_standard_engaged": {
		"source_id": "gallery_standard",
		"verb": "target_spotted",
		"label": "wake the standard sentry in its marked zone",
	},
	"enemy_chain_engaged": {
		"source_id": "gallery_chain",
		"verb": "target_spotted",
		"label": "wake the chain seam in its marked zone",
	},
	"flora_scarpet_occupied": {
		"source_id": "gallery_flora_scarpet",
		"verb": "occupied_medium_cover",
		"label": "stand in the field Scarpet",
	},
	"flora_capbage_tucked": {
		"source_id": "gallery_flora_capbage",
		"verb": "tucked_into_full_cover",
		"label": "tuck into the field Capbage",
	},
	"flora_flure_lured": {
		"source_id": "gameplay:flure:showcase_gallery_flure",
		"verb": "lured_response_sentry",
		"label": "light the Flure and move its response sentry",
	},
	"flora_hushbloom_stunned": {
		"source_id": "gameplay:hushbloom:showcase_gallery_hushbloom",
		"verb": "stunned_response_sentry",
		"label": "trip the Hushbloom and stun its response sentry",
	},
}

var _phase := GALLERY_PHASE_TOURING
var _evidence: Dictionary = {}
var _completion: Dictionary = {}
var _active_tier := 0
var _on_pad := ""
var _demo_enemy
var _standard_enemy
var _chain_enemy
var _flora_target_enemy
var _medium_scarpet
var _full_capbage
var _flora_scarpet
var _flora_capbage
var _flora_flure
var _flora_hushbloom
var _pad_materials: Array[StandardMaterial3D] = []
var _gallery_authority_baseline: Dictionary = {}
var _gallery_authority_initialized := false
var _restoring_gallery_authority := false
var _exit_signal_game_state

func _build_chunk() -> void:
	_add_floor(self, FLOOR_CENTER, FLOOR_SIZE, Color(0.085, 0.09, 0.11))
	# Corridor strip (visually lighter), and the boundary walls.
	_add_box(self, Vector3(41.0, -0.04, 0.0), Vector3(84.0, 0.06, 4.4), Color(0.12, 0.13, 0.16))
	_add_box(self, Vector3(41.0, 2.4, -17.9), Vector3(88.0, 4.8, 0.3), Color(0.13, 0.14, 0.16))
	_add_box(self, Vector3(41.0, 2.4, 13.9), Vector3(88.0, 4.8, 0.3), Color(0.13, 0.14, 0.16))
	for i in range(9):
		var blend := float(i) / 8.0
		_add_light(self, Vector3(4.0 + float(i) * 9.5, 3.8, 0.0),
			Color(0.5 + blend * 0.18, 0.54 + blend * 0.12, 0.62 - blend * 0.06), 2.4, 18.0)
	# Brighter fill over each exhibit so the showcase reads clearly.
	_add_light(self, Vector3(16.0, 3.2, -7.0), Color(0.7, 0.9, 0.75), 2.6, 16.0)   # hiding bay
	_add_light(self, Vector3(33.0, 3.2, -9.0), Color(0.95, 0.7, 0.62), 2.4, 15.0)  # standard pen
	_add_light(self, Vector3(44.0, 3.2, 9.0), Color(0.66, 0.7, 0.95), 2.4, 15.0)   # chain pen
	_add_light(self, Vector3(64.0, 3.2, -3.4), Color(0.85, 0.92, 0.8), 2.6, 18.0)  # flora row

	_add_marker(ENTRY_POS, Vector3(2.2, 0.5, 2.2), Color(0.2, 0.5, 0.7), 1.5, "ENTRY")
	_add_marker(EXIT_POS, Vector3(2.2, 0.5, 2.2), Color(0.3, 0.7, 0.45), 1.5, "REGROUP EXIT")
	_add_label(self, "SHOWCASE GALLERY", Vector3(8.0, 3.6, 0.0), Color(0.85, 0.88, 0.95))

	_build_hiding_bay()
	_build_enemy_bay()
	_build_flora_bay()

	_spawn_enemies()
	_connect_gallery_signals()
	_initialize_gallery_authority()
	_show_message("Try each live response, then regroup all three bodies at the exit.", 3.0)

func _build_hiding_bay() -> void:
	_add_label(self, "1 — HIDING", Vector3(16.0, 3.0, -2.0), Color(0.6, 0.85, 0.7))
	_add_box(self, Vector3(16.0, -0.04, -8.0), Vector3(16.0, 0.06, 9.0), Color(0.1, 0.12, 0.11))
	_pad_materials.clear()
	for i in range(HIDE_PADS.size()):
		var pad: Dictionary = HIDE_PADS[i]
		var tint: Color = PAD_TINTS[i]
		var mat := _make_material(tint * 0.5, tint, 0.45)
		var quad := _add_box(self, (pad["pos"] as Vector3) - Vector3(0, 0.42, 0),
			Vector3(PAD_RADIUS * 2.0, 0.08, PAD_RADIUS * 2.0), tint * 0.5)
		quad.material_override = mat
		_pad_materials.append(mat)
		_add_label(self, String(pad["name"]), (pad["pos"] as Vector3) + Vector3(0, 1.7, 0), tint.lightened(0.4))
		_add_label(self, String(pad["sub"]), (pad["pos"] as Vector3) + Vector3(0, 1.1, 0), Color(0.7, 0.74, 0.8))
	# The named cover exhibits are the reusable gameplay objects, not painted rectangles that merely
	# impersonate their effects. Their spatial predicates below are the same predicates production
	# fragments use; the broad plinths remain only as readable exhibit boundaries.
	_medium_scarpet = ScarpetScript.new()
	_medium_scarpet.name = "GalleryScarpet"
	_medium_scarpet.configure(HIDE_PADS[1]["pos"], PAD_RADIUS, false)
	_medium_scarpet.set_meta("gallery_mechanic_id", "hide_scarpet_occupied")
	add_child(_medium_scarpet)
	_full_capbage = CapbageScript.new()
	_full_capbage.name = "GalleryCapbage"
	_full_capbage.configure(_get_game_state(), HIDE_PADS[2]["pos"], PAD_RADIUS)
	_full_capbage.description = "Tuck into the hiding-bay Capbage"
	_full_capbage.set_meta("gallery_mechanic_id", "hide_capbage_tucked")
	add_child(_full_capbage)
	_register_interactable(_full_capbage)

func _build_enemy_bay() -> void:
	_add_label(self, "2 — ENEMIES", Vector3(38.0, 3.0, -2.0), Color(0.9, 0.6, 0.55))
	# South and north wake zones, drawn as darker floor patches. These are tells, not blockers.
	_add_box(self, Vector3(33.0, -0.04, -10.0), Vector3(12.0, 0.06, 8.0), Color(0.13, 0.1, 0.1))
	_add_box(self, Vector3(44.0, -0.04, 10.0), Vector3(12.0, 0.06, 8.0), Color(0.1, 0.1, 0.13))
	_add_label(self, "STANDARD SENTRY", Vector3(33.0, 2.2, -10.0), Color(0.95, 0.5, 0.4))
	_add_label(self, "roams · charges", Vector3(33.0, 1.6, -10.0), Color(0.7, 0.6, 0.6))
	_add_label(self, "CHAIN SEAM", Vector3(44.0, 2.2, 10.0), Color(0.6, 0.65, 0.95))
	_add_label(self, "segmented · wall-anchored", Vector3(44.0, 1.6, 10.0), Color(0.6, 0.62, 0.74))
	_add_label(self, "step into a marked zone to wake it", Vector3(38.5, 0.9, -2.6), Color(0.66, 0.7, 0.76))

func _build_flora_bay() -> void:
	var gs = _get_game_state()
	_add_label(self, "3 — FIELD-READY FLORA", Vector3(63.0, 3.0, -2.0), Color(0.7, 0.85, 0.6))
	_add_label(self, "only specimens with a live field response are exhibited",
		Vector3(63.0, 2.35, -2.0), Color(0.62, 0.7, 0.66))
	_add_box(self, Vector3(63.0, -0.04, -6.5), Vector3(23.0, 0.06, 8.0), Color(0.09, 0.12, 0.1))

	_flora_scarpet = ScarpetScript.new()
	_flora_scarpet.name = "GalleryFloraScarpet"
	_flora_scarpet.configure(FLORA_POSITIONS["scarpet"], 1.55, false)
	_flora_scarpet.set_meta("gallery_mechanic_id", "flora_scarpet_occupied")
	add_child(_flora_scarpet)

	_flora_capbage = CapbageScript.new()
	_flora_capbage.name = "GalleryFloraCapbage"
	_flora_capbage.configure(gs, FLORA_POSITIONS["capbage"], 1.35)
	_flora_capbage.description = "Tuck into the field Capbage"
	_flora_capbage.set_meta("gallery_mechanic_id", "flora_capbage_tucked")
	add_child(_flora_capbage)
	_register_interactable(_flora_capbage)

	_flora_flure = FlureScript.new()
	_flora_flure.name = "GalleryFloraFlure"
	_flora_flure.authority_id = "showcase_gallery_flure"
	_flora_flure.configure(gs, FLORA_POSITIONS["flure"], [FLORA_TARGET_ID],
		18.0, 1.5, FLORA_TINTS["flure"])
	_flora_flure.required_character = "peris"
	_flora_flure.settle_pos = FLORA_TARGET_SETTLE
	_flora_flure.lure_duration = 20.0
	_flora_flure.one_shot = false
	_flora_flure.consequence_preview = "Pull the response sentry into the marked settle pocket"
	_flora_flure.set_enemy_resolver(Callable(self, "_gallery_enemy_by_id"))
	_flora_flure.set_meta("gallery_mechanic_id", "flora_flure_lured")
	add_child(_flora_flure)
	_register_interactable(_flora_flure)

	_flora_hushbloom = HushbloomScript.new()
	_flora_hushbloom.name = "GalleryFloraHushbloom"
	_flora_hushbloom.authority_id = "showcase_gallery_hushbloom"
	_flora_hushbloom.configure(gs, FLORA_POSITIONS["hushbloom"], {
		"trigger_radius": 1.4,
		"stun_radius": 5.0,
		"stun_secs": 7.0,
		# A field-demo recharge keeps an accidental ANY-body trip recoverable in this teaching room.
		"regen_secs": 12.0,
		"pickable": false,
	})
	_flora_hushbloom.set_enemy_provider(Callable(self, "_gallery_flora_enemies"))
	_flora_hushbloom.set_meta("gallery_mechanic_id", "flora_hushbloom_stunned")
	add_child(_flora_hushbloom)

	for key in FLORA_ORDER:
		var pos: Vector3 = FLORA_POSITIONS[key]
		var tint: Color = FLORA_TINTS.get(key, Color(0.5, 0.7, 0.5))
		_add_label(self, FloraSpecies.display_name(key).to_upper(),
			pos + Vector3(0.0, 1.65, 0.0), tint.lightened(0.3))
		_add_label(self, _flora_caption(key), pos + Vector3(0.0, 1.08, 0.0),
			Color(0.7, 0.74, 0.8))
	_add_marker(FLORA_TARGET_SETTLE, Vector3(1.5, 0.12, 1.5),
		Color(0.9, 0.55, 0.28), 0.55, "LURE POCKET")
	_add_label(self, "response sentry", FLORA_TARGET_ANCHOR + Vector3(0.0, 1.5, 0.0),
		Color(0.75, 0.62, 0.55))

func _process(delta: float) -> void:
	_update(delta, false)

func headless_process(delta: float) -> void:
	_update(delta, true)

func _update(_delta: float, simulation_step := false) -> void:
	_apply_concealment()
	# Render frames are presentation. Ordinary play commits at GameState.character_arrived; an explicit
	# headless simulation step also checks the saved body positions so deterministic teleport fixtures
	# exercise the same exit predicate without turning `_process` into gameplay authority.
	if simulation_step:
		for char_id in PARTY_IDS:
			_observe_spatial_evidence(char_id)
		_check_exit_progression()

## Every member's concealment is derived independently from that member's physical location. Portrait
## selection changes only which readout the gallery displays; it cannot turn exposed bodies elsewhere
## in the room invisible. Derived state is rebuilt from authoritative positions on replay/load.
func _apply_concealment() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var active := _get_active_character()
	_active_tier = GameState.CONCEAL_NONE
	_on_pad = ""
	for cid in PARTY_IDS:
		if not gs.characters.has(cid):
			continue
		var cover := _spatial_cover_for(cid)
		var tier := int(cover.get("tier", GameState.CONCEAL_NONE))
		gs.set_character_concealment(cid, tier)
		if cid == active:
			_active_tier = tier
			_on_pad = str(cover.get("name", ""))


func _spatial_cover_for(char_id: String) -> Dictionary:
	var position := _get_character_position(char_id)
	if _full_capbage != null and is_instance_valid(_full_capbage) \
			and _full_capbage.conceals(position):
		return {"tier": GameState.CONCEAL_FULL, "name": "CAPBAGE"}
	if _flora_capbage != null and is_instance_valid(_flora_capbage) \
			and _flora_capbage.conceals(position):
		return {"tier": GameState.CONCEAL_FULL, "name": "CAPBAGE · FLORA BAY"}
	if _medium_scarpet != null and is_instance_valid(_medium_scarpet) \
			and _medium_scarpet.conceals(position):
		return {"tier": GameState.CONCEAL_MEDIUM, "name": "SCARPET"}
	if _flora_scarpet != null and is_instance_valid(_flora_scarpet) \
			and _flora_scarpet.conceals(position):
		return {"tier": GameState.CONCEAL_MEDIUM, "name": "SCARPET · FLORA BAY"}
	if _char_in_radius(char_id, HIDE_PADS[0]["pos"], PAD_RADIUS):
		return {"tier": GameState.CONCEAL_NONE, "name": "EXPOSED"}
	return {"tier": GameState.CONCEAL_NONE, "name": ""}


func on_game_state_snapshot_restored() -> void:
	super.on_game_state_snapshot_restored()
	_connect_gallery_signals()
	_gallery_authority_initialized = true
	if _gallery_authority_baseline.is_empty():
		_gallery_authority_baseline = _baseline_gallery_authority_state()
	var gs = _get_game_state()
	var raw: Variant = gs.get_world_state(gallery_authority_key(), null) \
			if gs != null and gs.has_method("get_world_state") else null
	if _valid_gallery_authority(raw):
		_restore_gallery_authority(raw as Dictionary)
	else:
		# Absence is construction-time touring truth. Do not publish a replacement event while loading.
		_restore_gallery_authority(_gallery_authority_baseline.duplicate(true))
	# Concealment is deliberately not a second save record. Saved body positions are authority, so a
	# stale serialized stat or a selection change cannot survive this presenter attachment seam.
	_apply_concealment()


func gallery_authority_key() -> String:
	return GALLERY_AUTHORITY_KEY


func _baseline_gallery_authority_state() -> Dictionary:
	return {
		"version": GALLERY_AUTHORITY_VERSION,
		"authority_id": gallery_authority_key(),
		"phase": GALLERY_PHASE_TOURING,
		"evidence": {},
		"completion": {},
	}


func _gallery_authority_state() -> Dictionary:
	return {
		"version": GALLERY_AUTHORITY_VERSION,
		"authority_id": gallery_authority_key(),
		"phase": _phase,
		"evidence": _evidence.duplicate(true),
		"completion": _completion.duplicate(true),
	}


func _valid_gallery_authority(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var saved := raw as Dictionary
	if int(saved.get("version", 0)) != GALLERY_AUTHORITY_VERSION \
			or str(saved.get("authority_id", "")) != gallery_authority_key():
		return false
	var phase := str(saved.get("phase", ""))
	var evidence_raw: Variant = saved.get("evidence", null)
	var completion_raw: Variant = saved.get("completion", null)
	if not evidence_raw is Dictionary or not completion_raw is Dictionary:
		return false
	var evidence := evidence_raw as Dictionary
	for mechanic_id_v in evidence.keys():
		var mechanic_id := str(mechanic_id_v)
		if not REQUIRED_EVIDENCE.has(mechanic_id) \
				or not _valid_evidence_record(mechanic_id, evidence[mechanic_id_v]):
			return false
	if phase == GALLERY_PHASE_TOURING:
		return (completion_raw as Dictionary).is_empty()
	if phase == GALLERY_PHASE_COMPLETE:
		return _evidence_is_complete(evidence) and _valid_completion_record(completion_raw)
	return false


func _valid_evidence_record(mechanic_id: String, raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var record := raw as Dictionary
	var spec: Dictionary = REQUIRED_EVIDENCE.get(mechanic_id, {})
	var actor := str(record.get("actor_id", ""))
	var tick := float(record.get("observed_tick", -1.0))
	var position := _v3_from_value(record.get("actor_position", []))
	if str(record.get("contract", "")) != GALLERY_EVIDENCE_CONTRACT \
			or str(record.get("mechanic_id", "")) != mechanic_id \
			or str(record.get("source_id", "")) != str(spec.get("source_id", "")) \
			or str(record.get("verb", "")) != str(spec.get("verb", "")) \
			or actor not in PARTY_IDS or tick < 0.0 \
			or position == Vector3.INF or not _evidence_position_valid(mechanic_id, position):
		return false
	# Flora effects keep their own independent world-state contracts. A Gallery record cannot claim
	# that a labelled prop performed a verb when the target-owned object has no matching effect.
	if mechanic_id == "flora_flure_lured":
		if _flora_flure == null or not is_instance_valid(_flora_flure):
			return false
		var flure_state: Dictionary = _flora_flure.get_authority_state()
		var flure_effect: Dictionary = flure_state.get("last_effect", {})
		return (flure_effect.get("pulled_ids", []) as Array).has(FLORA_TARGET_ID)
	if mechanic_id == "flora_hushbloom_stunned":
		if _flora_hushbloom == null or not is_instance_valid(_flora_hushbloom):
			return false
		var hush_state: Dictionary = _flora_hushbloom.get_authority_state()
		var hush_effect: Dictionary = hush_state.get("last_effect", {})
		return (hush_effect.get("enemy_ids", []) as Array).has(FLORA_TARGET_ID)
	return true


func _valid_completion_record(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var record := raw as Dictionary
	if str(record.get("contract", "")) != GALLERY_COMPLETION_CONTRACT \
			or float(record.get("observed_tick", -1.0)) < 0.0:
		return false
	var party_raw: Variant = record.get("party_ids", null)
	var positions_raw: Variant = record.get("party_positions", null)
	if not party_raw is Array or not positions_raw is Dictionary:
		return false
	var party: Array = party_raw
	if party.size() != PARTY_IDS.size():
		return false
	for i in range(PARTY_IDS.size()):
		if str(party[i]) != PARTY_IDS[i]:
			return false
	var positions := positions_raw as Dictionary
	if positions.size() != PARTY_IDS.size():
		return false
	for char_id in PARTY_IDS:
		var position := _v3_from_value(positions.get(char_id, []))
		if position == Vector3.INF or position.x < EXIT_X:
			return false
	return true


func _evidence_position_valid(mechanic_id: String, position: Vector3) -> bool:
	match mechanic_id:
		"hide_exposed_spotted":
			# Detection resolves at the body's centre as it crosses the pad edge.
			return _point_in_radius(position, HIDE_PADS[0]["pos"], PAD_RADIUS + 0.5)
		"hide_scarpet_occupied":
			return _point_in_radius(position, HIDE_PADS[1]["pos"], PAD_RADIUS)
		"hide_capbage_tucked":
			return _point_in_radius(position, HIDE_PADS[2]["pos"], PAD_RADIUS)
		"enemy_standard_engaged":
			return _point_in_radius(position, STANDARD_ANCHOR, STANDARD_RANGE + 3.0)
		"enemy_chain_engaged":
			return _point_in_radius(position, CHAIN_ANCHOR, CHAIN_RANGE + 2.5)
		"flora_scarpet_occupied":
			return _point_in_radius(position, FLORA_POSITIONS["scarpet"], 1.55)
		"flora_capbage_tucked":
			return _point_in_radius(position, FLORA_POSITIONS["capbage"], 1.35)
		"flora_flure_lured":
			return _point_in_radius(position, FLORA_POSITIONS["flure"], 1.6)
		"flora_hushbloom_stunned":
			return _point_in_radius(position, FLORA_POSITIONS["hushbloom"], 1.4)
	return false


func _evidence_is_complete(evidence := _evidence) -> bool:
	for mechanic_id in REQUIRED_EVIDENCE.keys():
		if not evidence.has(mechanic_id):
			return false
	return true


func _initialize_gallery_authority() -> void:
	if _gallery_authority_initialized:
		return
	var gs = _get_game_state()
	if gs == null or not gs.has_method("get_world_state"):
		_apply_gallery_presenter()
		return
	_gallery_authority_initialized = true
	_gallery_authority_baseline = _baseline_gallery_authority_state()
	var raw: Variant = gs.get_world_state(gallery_authority_key(), null)
	if _valid_gallery_authority(raw):
		_restore_gallery_authority(raw as Dictionary)
	else:
		_apply_gallery_presenter()
		_publish_gallery_authority()


func _publish_gallery_authority() -> void:
	if _restoring_gallery_authority:
		return
	var gs = _get_game_state()
	if gs != null and gs.has_method("set_world_state"):
		gs.set_world_state(gallery_authority_key(), _gallery_authority_state())


func _restore_gallery_authority(saved: Dictionary) -> void:
	_restoring_gallery_authority = true
	_phase = str(saved.get("phase", GALLERY_PHASE_TOURING))
	_evidence = (saved.get("evidence", {}) as Dictionary).duplicate(true)
	_completion = (saved.get("completion", {}) as Dictionary).duplicate(true)
	_apply_gallery_presenter()
	_restoring_gallery_authority = false


func _apply_gallery_presenter() -> void:
	_set_preview_step("showcase_complete" if _phase == GALLERY_PHASE_COMPLETE \
			else "showcase_touring")


func _connect_gallery_signals() -> void:
	if _demo_enemy != null and is_instance_valid(_demo_enemy) \
			and not _demo_enemy.target_spotted.is_connected(_on_demo_target_spotted):
		_demo_enemy.target_spotted.connect(_on_demo_target_spotted)
	if _standard_enemy != null and is_instance_valid(_standard_enemy) \
			and not _standard_enemy.target_spotted.is_connected(_on_standard_target_spotted):
		_standard_enemy.target_spotted.connect(_on_standard_target_spotted)
	if _chain_enemy != null and is_instance_valid(_chain_enemy) \
			and not _chain_enemy.target_spotted.is_connected(_on_chain_target_spotted):
		_chain_enemy.target_spotted.connect(_on_chain_target_spotted)
	if _full_capbage != null and is_instance_valid(_full_capbage) \
			and not _full_capbage.tucked_in.is_connected(_on_hide_capbage_tucked):
		_full_capbage.tucked_in.connect(_on_hide_capbage_tucked)
	if _flora_capbage != null and is_instance_valid(_flora_capbage) \
			and not _flora_capbage.tucked_in.is_connected(_on_flora_capbage_tucked):
		_flora_capbage.tucked_in.connect(_on_flora_capbage_tucked)
	if _flora_flure != null and is_instance_valid(_flora_flure) \
			and not _flora_flure.flure_activated.is_connected(_on_gallery_flure_activated):
		_flora_flure.flure_activated.connect(_on_gallery_flure_activated)
	if _flora_hushbloom != null and is_instance_valid(_flora_hushbloom) \
			and not _flora_hushbloom.burst_fired.is_connected(_on_gallery_hushbloom_fired):
		_flora_hushbloom.burst_fired.connect(_on_gallery_hushbloom_fired)
	var gs = _get_game_state()
	if gs == _exit_signal_game_state:
		return
	if _exit_signal_game_state != null and is_instance_valid(_exit_signal_game_state) \
			and _exit_signal_game_state.character_arrived.is_connected(_on_gallery_character_arrived):
		_exit_signal_game_state.character_arrived.disconnect(_on_gallery_character_arrived)
	_exit_signal_game_state = gs
	if gs != null and not gs.character_arrived.is_connected(_on_gallery_character_arrived):
		gs.character_arrived.connect(_on_gallery_character_arrived)


func _disconnect_gallery_signals() -> void:
	if _exit_signal_game_state != null and is_instance_valid(_exit_signal_game_state) \
			and _exit_signal_game_state.character_arrived.is_connected(_on_gallery_character_arrived):
		_exit_signal_game_state.character_arrived.disconnect(_on_gallery_character_arrived)
	_exit_signal_game_state = null


func detach_chunk_host() -> void:
	_disconnect_gallery_signals()
	super.detach_chunk_host()


func _exit_tree() -> void:
	_disconnect_gallery_signals()


func _on_gallery_character_arrived(char_id: String) -> void:
	if char_id in PARTY_IDS:
		_observe_spatial_evidence(char_id)
		_check_exit_progression(char_id)
		if _phase == GALLERY_PHASE_TOURING and _character_has_reached_exit(char_id):
			var remaining := remaining_evidence_ids()
			if not remaining.is_empty():
				_show_message("REGROUP EXIT waits: %d live response%s remain." % [
					remaining.size(), "" if remaining.size() == 1 else "s"], 2.4)
			else:
				var missing_party: Array[String] = []
				for required_id in PARTY_IDS:
					if not _character_has_reached_exit(required_id):
						missing_party.append(required_id.capitalize())
				_show_message("REGROUP EXIT waits for %s." % ", ".join(missing_party), 2.4)


func _observe_spatial_evidence(char_id: String) -> void:
	if char_id not in PARTY_IDS:
		return
	var position := _get_character_position(char_id)
	if _point_in_radius(position, HIDE_PADS[1]["pos"], PAD_RADIUS):
		_record_evidence("hide_scarpet_occupied", char_id, position)
	if _point_in_radius(position, FLORA_POSITIONS["scarpet"], 1.55):
		_record_evidence("flora_scarpet_occupied", char_id, position)


func _on_demo_target_spotted(char_id: String) -> void:
	_record_evidence("hide_exposed_spotted", char_id, _get_character_position(char_id))


func _on_standard_target_spotted(char_id: String) -> void:
	_record_evidence("enemy_standard_engaged", char_id, _get_character_position(char_id))


func _on_chain_target_spotted(char_id: String) -> void:
	_record_evidence("enemy_chain_engaged", char_id, _get_character_position(char_id))


func _on_hide_capbage_tucked() -> void:
	var actor := str(_full_capbage.active_character) if _full_capbage != null else ""
	if actor in PARTY_IDS:
		_record_evidence("hide_capbage_tucked", actor, _get_character_position(actor))


func _on_flora_capbage_tucked() -> void:
	var actor := str(_flora_capbage.active_character) if _flora_capbage != null else ""
	if actor in PARTY_IDS:
		_record_evidence("flora_capbage_tucked", actor, _get_character_position(actor))


func _on_gallery_flure_activated(pulled: int) -> void:
	if pulled <= 0 or _flora_flure == null:
		return
	var report: Dictionary = _flora_flure.get_last_activation_report()
	if not (report.get("pulled_ids", []) as Array).has(FLORA_TARGET_ID):
		return
	var actor := str(_flora_flure.active_character)
	if actor in PARTY_IDS:
		_record_evidence("flora_flure_lured", actor, _get_character_position(actor))


func _on_gallery_hushbloom_fired(_at: Vector3) -> void:
	if _flora_hushbloom == null:
		return
	var state: Dictionary = _flora_hushbloom.get_authority_state()
	var effect: Dictionary = state.get("last_effect", {})
	if not (effect.get("enemy_ids", []) as Array).has(FLORA_TARGET_ID):
		return
	var actor := str(effect.get("trigger_body_id", ""))
	if actor in PARTY_IDS:
		_record_evidence("flora_hushbloom_stunned", actor, _get_character_position(actor))


func _record_evidence(mechanic_id: String, actor: String, position: Vector3) -> void:
	if _phase == GALLERY_PHASE_COMPLETE or actor not in PARTY_IDS \
			or not REQUIRED_EVIDENCE.has(mechanic_id) \
			or not _evidence_position_valid(mechanic_id, position):
		return
	if _evidence.has(mechanic_id) \
			and mechanic_id not in ["flora_flure_lured", "flora_hushbloom_stunned"]:
		return
	var spec: Dictionary = REQUIRED_EVIDENCE[mechanic_id]
	var record := {
		"contract": GALLERY_EVIDENCE_CONTRACT,
		"mechanic_id": mechanic_id,
		"source_id": str(spec.get("source_id", "")),
		"verb": str(spec.get("verb", "")),
		"actor_id": actor,
		"actor_position": _v3_to_value(position),
		"observed_tick": _get_scheduler_tick(),
	}
	if _evidence.get(mechanic_id, null) == record:
		return
	_evidence[mechanic_id] = record
	_publish_gallery_authority()
	var remaining := remaining_evidence_ids().size()
	_show_message("Survey response: %s. %d live response%s remain." % [
		str(spec.get("label", mechanic_id)), remaining, "" if remaining == 1 else "s"], 2.2)


func _check_exit_progression(_preferred_actor := "") -> void:
	if _phase == GALLERY_PHASE_COMPLETE:
		return
	if _evidence_is_complete() and _all_required_party_at_exit():
		_commit_gallery_completion()


func _character_has_reached_exit(char_id: String) -> bool:
	var gs = _get_game_state()
	return gs != null and gs.characters.has(char_id) \
			and _get_character_position(char_id).x >= EXIT_X


func _all_required_party_at_exit() -> bool:
	for char_id in PARTY_IDS:
		if not _character_has_reached_exit(char_id):
			return false
	return true


func _commit_gallery_completion() -> void:
	if _phase == GALLERY_PHASE_COMPLETE or not _evidence_is_complete() \
			or not _all_required_party_at_exit():
		return
	var positions := {}
	for char_id in PARTY_IDS:
		positions[char_id] = _v3_to_value(_get_character_position(char_id))
	_phase = GALLERY_PHASE_COMPLETE
	_completion = {
		"contract": GALLERY_COMPLETION_CONTRACT,
		"party_ids": PARTY_IDS.duplicate(),
		"party_positions": positions,
		"observed_tick": _get_scheduler_tick(),
	}
	_publish_gallery_authority()
	_apply_gallery_presenter()
	_show_message("Gallery cleared — every live response surveyed, all three regrouped.", 2.8)


func _spawn_enemies() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	# Bay 1 demo sentry: paces a short line in front of the pads so each tier reads.
	_demo_enemy = EnemyScript.new()
	_demo_enemy.name = "GalleryDemoSentry"
	_demo_enemy.position = Vector3(16.0, 0.5, SENTRY_PACE_Z)
	_demo_enemy.move_speed = 1.4
	_demo_enemy.detection_range = DEMO_SENTRY_RANGE
	_demo_enemy._detection_targets.assign(PARTY_IDS)
	add_child(_demo_enemy)
	_register_enemy(_demo_enemy, "gallery_demo", _demo_enemy.move_speed)
	if _demo_enemy.has_method("set_patrol"):
		var pace: Array[Vector3] = [Vector3(12.0, 0.0, SENTRY_PACE_Z), Vector3(20.0, 0.0, SENTRY_PACE_Z)]
		_demo_enemy.set_patrol(pace)

	# Bay 2 standard: roams its south pen (local wander, no pathfinding) and will charge if you enter.
	_standard_enemy = EnemyScript.new()
	_standard_enemy.name = "GalleryStandard"
	_standard_enemy.position = STANDARD_ANCHOR
	_standard_enemy.move_speed = 1.6
	_standard_enemy.detection_range = STANDARD_RANGE
	_standard_enemy._detection_targets.assign(PARTY_IDS)
	add_child(_standard_enemy)
	_register_enemy(_standard_enemy, "gallery_standard", _standard_enemy.move_speed)
	if _standard_enemy.has_method("set_roam"):
		_standard_enemy.set_roam(STANDARD_ANCHOR, 2.5)

	# Bay 2 chain: a segmented seam anchored to the north wall, pacing its pen.
	_chain_enemy = ChainEnemyScript.new()
	_chain_enemy.name = "GalleryChain"
	_chain_enemy.position = CHAIN_ANCHOR
	_chain_enemy.move_speed = 1.4
	_chain_enemy.detection_range = CHAIN_RANGE
	_chain_enemy._detection_targets.assign(PARTY_IDS)
	add_child(_chain_enemy)
	_register_enemy(_chain_enemy, "gallery_chain", _chain_enemy.move_speed)
	if _chain_enemy.has_method("set_wall_line"):
		_chain_enemy.set_wall_line(Vector3(44.0, 0.5, 13.5), Vector3(0, 0, -1))
	if _chain_enemy.has_method("set_patrol"):
		var seam: Array[Vector3] = [Vector3(41.0, 0.0, 10.0), Vector3(47.0, 0.0, 10.0)]
		_chain_enemy.set_patrol(seam)

	# The flora bay's inert response sentry is a real Enemy FSM with no acquisition range. Flure
	# moves it through Enemy.lure_to; Hushbloom freezes the same body through Enemy.stun.
	_flora_target_enemy = EnemyScript.new()
	_flora_target_enemy.name = "GalleryFloraResponseSentry"
	_flora_target_enemy.position = FLORA_TARGET_ANCHOR
	_flora_target_enemy.scale = Vector3.ONE * 0.72
	_flora_target_enemy.move_speed = 1.3
	_flora_target_enemy.detection_range = 0.0
	_flora_target_enemy._detection_targets.assign(PARTY_IDS)
	add_child(_flora_target_enemy)
	_register_enemy(_flora_target_enemy, FLORA_TARGET_ID, _flora_target_enemy.move_speed)

## Register an enemy in GameState + wire the node (it reads its scheduler from game_state).
func _register_enemy(enemy, id: String, speed: float) -> void:
	var gs = _get_game_state()
	if gs == null or enemy == null:
		return
	enemy.char_id = id
	enemy.game_state = gs
	gs.register_character(id, enemy.position, speed, {"detection_range": float(enemy.detection_range)})
	if enemy.has_method("activate"):
		enemy.activate()


func _gallery_enemy_by_id(enemy_id: String):
	if enemy_id == FLORA_TARGET_ID and _flora_target_enemy != null \
			and is_instance_valid(_flora_target_enemy):
		return _flora_target_enemy
	return null


func _gallery_flora_enemies() -> Array:
	return [_flora_target_enemy] if _flora_target_enemy != null \
		and is_instance_valid(_flora_target_enemy) else []


# --- Scene metadata ---

func get_scene_title() -> String:
	return "Showcase Gallery"

func get_scene_help() -> String:
	return "Build the field model before leaving. Bay 1: be spotted while EXPOSED, stand in the SCARPET, and interact to tuck into the CAPBAGE. Bay 2: physically enter both marked wake zones until each enemy acquires a target; once awake, these are live pursuits, not fenced props. Bay 3 contains only shipped flora mechanics: stand in Scarpet, tuck into Capbage, have Peris light the Flure so its response sentry moves, and cross the Hushbloom so that sentry is stunned. Once every response has occurred, move Aster, Peris, and Endo together across the REGROUP EXIT."

func get_default_character() -> String:
	return "peris"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors.merge({
		"entry": ENTRY_POS,
		"pad_exposed": HIDE_PADS[0]["pos"],
		"pad_medium": HIDE_PADS[1]["pos"],
		"pad_full": HIDE_PADS[2]["pos"],
		"standard_pen": STANDARD_ANCHOR,
		"chain_pen": CHAIN_ANCHOR,
		"standard_zone": STANDARD_ANCHOR,
		"chain_zone": CHAIN_ANCHOR,
		"flora_scarpet": FLORA_POSITIONS["scarpet"],
		"flora_capbage": FLORA_POSITIONS["capbage"],
		"flora_flure": FLORA_POSITIONS["flure"],
		"flora_hushbloom": FLORA_POSITIONS["hushbloom"],
		"flora_response_sentry": FLORA_TARGET_ANCHOR,
		"exit": EXIT_POS,
	}, true)
	return anchors


func get_playthrough_interaction_target(action_id: String) -> Node3D:
	match action_id:
		"hide_capbage":
			return _full_capbage as Node3D
		"flora_capbage":
			return _flora_capbage as Node3D
		"flora_flure":
			return _flora_flure as Node3D
	return null


func get_preview_time_state() -> Dictionary:
	return {
		"day": 3,
		"time": 0.5,
		"routing_mode": "safe",
		"note_default": "A systems survey: cause every live exhibit response, then regroup the whole required party. Static stand-ins for unbuilt flora are deliberately absent.",
	}


func remaining_evidence_ids() -> Array[String]:
	var remaining: Array[String] = []
	for mechanic_id_v in REQUIRED_EVIDENCE.keys():
		var mechanic_id := str(mechanic_id_v)
		if not _evidence.has(mechanic_id):
			remaining.append(mechanic_id)
	return remaining


func get_preview_state() -> Dictionary:
	var concealment_by_character := {}
	var gs = _get_game_state()
	if gs != null:
		for char_id in PARTY_IDS:
			if gs.characters.has(char_id):
				concealment_by_character[char_id] = gs.get_character_concealment(char_id)
	return {
		"phase": _phase,
		"evidence": _evidence.duplicate(true),
		"evidence_count": _evidence.size(),
		"required_evidence_count": REQUIRED_EVIDENCE.size(),
		"remaining_evidence": remaining_evidence_ids(),
		"completion": _completion.duplicate(true),
		"completion_party": (_completion.get("party_ids", []) as Array).duplicate(),
		"completion_tick": float(_completion.get("observed_tick", -1.0)),
		"whole_party_at_exit": _all_required_party_at_exit(),
		"active_tier": _active_tier,
		"on_pad": _on_pad,
		"complete": _phase == GALLERY_PHASE_COMPLETE,
		"hiding_type_count": HIDE_PADS.size(),
		"enemy_count": _enemy_count(),
		"flora_count": FLORA_ORDER.size(),
		"enemy_types": ["standard", "chain"],
		"concealment_by_character": concealment_by_character,
		"enemy": {
			"standard": _enemy_report(_standard_enemy),
			"chain": _enemy_report(_chain_enemy),
			"flora_response": _enemy_report(_flora_target_enemy),
		},
	}

func get_preview_overlay_status(overlay_id: String, _current_tick: float) -> Array:
	match overlay_id:
		"aster":
			return ["DATA: %d/%d physical responses surveyed." % [
				_evidence.size(), REQUIRED_EVIDENCE.size()],
				"On pad: %s" % (_on_pad if _on_pad != "" else "none")]
		"peris":
			return ["BLOOM: Scarpet, Capbage, Flure, and Hushbloom have live verbs.",
				"Hiding tier active: %d" % _active_tier]
		"endo":
			return ["Seam: wake both enemy types; the east sentry is the flora response target.",
				"Exit requires every response and all three bodies."]
	return []

func reset_preview_state() -> void:
	_restoring_gallery_authority = true
	_phase = GALLERY_PHASE_TOURING
	_evidence.clear()
	_completion.clear()
	_active_tier = 0
	_on_pad = ""
	var gs = _get_game_state()
	if gs != null:
		for cid in PARTY_IDS:
			if gs.characters.has(cid):
				gs.set_character_concealment(cid, GameState.CONCEAL_NONE)
	_restoring_gallery_authority = false
	_gallery_authority_baseline = _baseline_gallery_authority_state()
	_gallery_authority_initialized = true
	_connect_gallery_signals()
	_apply_gallery_presenter()
	_publish_gallery_authority()

# --- Helpers ---

func _char_in_radius(cid: String, center: Vector3, radius: float) -> bool:
	var pos := _get_character_position(cid)
	return _point_in_radius(pos, center, radius)


func _point_in_radius(pos: Vector3, center: Vector3, radius: float) -> bool:
	return Vector2(pos.x - center.x, pos.z - center.z).length() <= radius

func _enemy_report(enemy) -> Dictionary:
	if enemy == null or not is_instance_valid(enemy):
		return {"state": "", "target": ""}
	return {
		"state": str(enemy.get_state()) if enemy.has_method("get_state") else "",
		"target": str(enemy._current_target_id),
	}

func _enemy_count() -> int:
	var n := 0
	if _standard_enemy != null and is_instance_valid(_standard_enemy):
		n += 1
	if _chain_enemy != null and is_instance_valid(_chain_enemy):
		n += 1
	return n

func _flora_caption(key: String) -> String:
	match key:
		"scarpet":
			return "stand inside — medium cover"
		"capbage":
			return "interact — full hide"
		"flure":
			return "Peris lights — pulls sentry"
		"hushbloom":
			return "cross bloom — stuns sentry"
	return "not field-ready"

# --- Local marker + serialization helpers ---

func _add_marker(pos: Vector3, size: Vector3, color: Color, energy: float, label: String) -> StandardMaterial3D:
	var mat := _make_material(color * 0.4, color, energy)
	var mesh := _add_box(self, pos - Vector3(0, 0.2, 0), size, color * 0.4)
	mesh.material_override = mat
	_add_label(self, label, pos + Vector3(0, 1.7, 0), color)
	return mat


func _v3_to_value(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _v3_from_value(value: Variant) -> Vector3:
	if not value is Array or (value as Array).size() != 3:
		return Vector3.INF
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
