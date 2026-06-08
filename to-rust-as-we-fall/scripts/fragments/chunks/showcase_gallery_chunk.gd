extends "res://scripts/scene_chunks/scene_chunk.gd"

## Showcase Gallery — a guided exhibit hall that shows off, in order, the three HIDING
## types, both ENEMY types, and the FLORA types. A safe central corridor runs west→east;
## each exhibit sits in a side alcove off it, so the player can walk the gallery and step
## into each bay to try it, then reach the exit.
##   1. Hiding bay (south): three pads, one per concealment tier — EXPOSED (none), low
##      cover (medium), safehold (full). A demo sentry paces in front so each tier visibly
##      differs: exposed -> spotted, medium -> hidden unless it closes in, full -> never seen.
##   2. Enemy bay: a STANDARD sentry roaming + charging in a south pen, and a CHAIN seam
##      (segmented, anchored to a wall) working a north pen. The corridor stays out of their
##      reach, so you observe safely and step in to wake them.
##   3. Flora bay: a row of the canonical flora species (FloraSpecies), each labelled with
##      its name and hiding tier.

const EnemyScript := preload("res://scripts/game/ai/enemy.gd")
const ChainEnemyScript := preload("res://scripts/game/ai/chain_enemy.gd")

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
# range (6m), so EXPOSED is caught while MEDIUM holds. FULL is never seen. ---
const SENTRY_PACE_Z := -10.0
const PAD_Z := -6.0
const PAD_RADIUS := 1.6
const DEMO_SENTRY_RANGE := 6.0
const HIDE_PADS := [
	{"pos": Vector3(12.0, 0.45, PAD_Z), "tier": 0, "name": "EXPOSED", "sub": "no cover  —  NONE"},
	{"pos": Vector3(16.0, 0.45, PAD_Z), "tier": 1, "name": "SCARPET", "sub": "low cover  —  MEDIUM"},
	{"pos": Vector3(20.0, 0.45, PAD_Z), "tier": 2, "name": "DOMA", "sub": "safehold  —  FULL"},
]
const PAD_TINTS := [Color(0.4, 0.16, 0.14), Color(0.7, 0.6, 0.3), Color(0.35, 0.7, 0.5)]

# --- Bay 2: enemies, penned in alcoves 10m off the corridor (beyond their 5m reach). ---
const STANDARD_ANCHOR := Vector3(33.0, 0.5, -10.0)
const STANDARD_RANGE := 5.0
const CHAIN_ANCHOR := Vector3(44.0, 0.5, 10.0)
const CHAIN_RANGE := 5.0

# --- Bay 3: flora row, just south of the corridor. ---
const FLORA_Z := -3.4
const FLORA_START_X := 54.0
const FLORA_STEP_X := 4.0
const FLORA_ORDER := ["seefern", "scarpet", "flure", "hushbloom", "doma", "snapbloom"]
const FLORA_TINTS := {
	"seefern": Color(0.4, 0.85, 0.6),
	"scarpet": Color(0.78, 0.66, 0.32),
	"flure": Color(0.9, 0.55, 0.28),
	"hushbloom": Color(0.45, 0.62, 0.95),
	"doma": Color(0.93, 0.76, 0.42),
	"snapbloom": Color(0.95, 0.42, 0.3),
}

var _phase := "touring"
var _active_tier := 0
var _on_pad := ""
var _standard_enemy
var _chain_enemy
var _pad_materials: Array[StandardMaterial3D] = []

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
	_add_marker(EXIT_POS, Vector3(2.2, 0.5, 2.2), Color(0.3, 0.7, 0.45), 1.5, "EXIT")
	_add_label(self, "SHOWCASE GALLERY", Vector3(8.0, 3.6, 0.0), Color(0.85, 0.88, 0.95))

	_build_hiding_bay()
	_build_enemy_bay()
	_build_flora_bay()

	_spawn_enemies()
	_set_preview_step("showcase_touring")
	_show_message("A field gallery: three hiding types, both sentries, and the flora.", 2.4)

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

func _build_enemy_bay() -> void:
	_add_label(self, "2 — ENEMIES", Vector3(38.0, 3.0, -2.0), Color(0.9, 0.6, 0.55))
	# South pen (standard) + north pen (chain), drawn as darker floor patches.
	_add_box(self, Vector3(33.0, -0.04, -10.0), Vector3(12.0, 0.06, 8.0), Color(0.13, 0.1, 0.1))
	_add_box(self, Vector3(44.0, -0.04, 10.0), Vector3(12.0, 0.06, 8.0), Color(0.1, 0.1, 0.13))
	_add_label(self, "STANDARD SENTRY", Vector3(33.0, 2.2, -10.0), Color(0.95, 0.5, 0.4))
	_add_label(self, "roams · charges", Vector3(33.0, 1.6, -10.0), Color(0.7, 0.6, 0.6))
	_add_label(self, "CHAIN SEAM", Vector3(44.0, 2.2, 10.0), Color(0.6, 0.65, 0.95))
	_add_label(self, "segmented · wall-anchored", Vector3(44.0, 1.6, 10.0), Color(0.6, 0.62, 0.74))
	_add_label(self, "step into a pen to wake it", Vector3(38.5, 0.9, -2.6), Color(0.66, 0.7, 0.76))

func _build_flora_bay() -> void:
	_add_label(self, "3 — FLORA", Vector3(62.0, 3.0, -2.0), Color(0.7, 0.85, 0.6))
	for i in range(FLORA_ORDER.size()):
		var key: String = FLORA_ORDER[i]
		var x := FLORA_START_X + float(i) * FLORA_STEP_X
		var tint: Color = FLORA_TINTS.get(key, Color(0.5, 0.7, 0.5))
		var bloom_mat := _make_material(tint * 0.45, tint, 0.5)
		_add_flora(Vector3(x, 0.45, FLORA_Z), bloom_mat, 0.7)
		_add_label(self, FloraSpecies.display_name(key).to_upper(), Vector3(x, 1.6, FLORA_Z), tint.lightened(0.3))
		_add_label(self, _flora_caption(key), Vector3(x, 1.05, FLORA_Z), Color(0.7, 0.74, 0.8))

func _process(delta: float) -> void:
	_update(delta)

func headless_process(delta: float) -> void:
	_update(delta)

func _update(_delta: float) -> void:
	if _phase == "complete":
		return
	_apply_concealment()
	if _get_character_position(_get_active_character()).x >= EXIT_X:
		_phase = "complete"
		_set_preview_step("showcase_complete")
		_show_message("Gallery cleared — hiding, enemies, and flora all surveyed.", 2.0)

## Each frame: the ACTIVE member takes the concealment tier of the pad it stands on (none when
## off a pad); every other member is held FULLY concealed so they're inert observers and never
## trip the demo sentries. Derived state (never logged) — rebuilt from positions on replay.
func _apply_concealment() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var active := _get_active_character()
	var tier := GameState.CONCEAL_NONE
	_on_pad = ""
	for pad in HIDE_PADS:
		if _char_in_radius(active, pad["pos"], PAD_RADIUS):
			tier = int(pad["tier"])
			_on_pad = String(pad["name"])
			break
	_active_tier = tier
	for cid in PARTY_IDS:
		if not gs.characters.has(cid):
			continue
		gs.set_character_concealment(cid, tier if cid == active else GameState.CONCEAL_FULL)

func _spawn_enemies() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	# Bay 1 demo sentry: paces a short line in front of the pads so each tier reads.
	var demo := EnemyScript.new()
	demo.name = "GalleryDemoSentry"
	demo.position = Vector3(16.0, 0.5, SENTRY_PACE_Z)
	demo.move_speed = 1.4
	demo.detection_range = DEMO_SENTRY_RANGE
	demo._detection_targets.assign(PARTY_IDS)
	add_child(demo)
	_register_enemy(demo, "gallery_demo", demo.move_speed)
	if demo.has_method("set_patrol"):
		var pace: Array[Vector3] = [Vector3(12.0, 0.0, SENTRY_PACE_Z), Vector3(20.0, 0.0, SENTRY_PACE_Z)]
		demo.set_patrol(pace)

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

# --- Scene metadata ---

func get_scene_title() -> String:
	return "Showcase Gallery"

func get_scene_help() -> String:
	return "Walk the gallery west to east. South in bay 1: stand on each pad to feel the three hiding tiers against the pacing sentry (exposed gets seen, low cover holds at range, the safehold never shows). Bay 2: watch the standard roamer and the chain seam from the corridor, or step into a pen to wake one. Bay 3: the flora line-up. Reach the EXIT to finish."

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
		"flora_row": Vector3(FLORA_START_X + 8.0, 0.45, FLORA_Z),
		"exit": EXIT_POS,
	}, true)
	return anchors

func get_preview_time_state() -> Dictionary:
	return {
		"day": 3,
		"time": 0.5,
		"routing_mode": "safe",
		"note_default": "A guided field gallery: the three hiding tiers, both sentry types, and the canonical flora, each in its own bay off a safe corridor.",
	}

func get_preview_state() -> Dictionary:
	return {
		"phase": _phase,
		"active_tier": _active_tier,
		"on_pad": _on_pad,
		"complete": _phase == "complete",
		"hiding_type_count": HIDE_PADS.size(),
		"enemy_count": _enemy_count(),
		"flora_count": FLORA_ORDER.size(),
		"enemy_types": ["standard", "chain"],
		"enemy": {
			"standard": _enemy_report(_standard_enemy),
			"chain": _enemy_report(_chain_enemy),
		},
	}

func get_preview_overlay_status(overlay_id: String, _current_tick: float) -> Array:
	match overlay_id:
		"aster":
			return ["DATA: three hiding tiers on display.", "On pad: %s" % (_on_pad if _on_pad != "" else "none")]
		"peris":
			return ["FOG: the flures and blooms read clean down the east wall.", "Hiding tier active: %d" % _active_tier]
		"endo":
			return ["Seam: the chain works the north pen; the roamer holds the south.", "Step in to wake one."]
	return []

func reset_preview_state() -> void:
	_phase = "touring"
	_active_tier = 0
	_on_pad = ""
	var gs = _get_game_state()
	if gs != null:
		for cid in PARTY_IDS:
			if gs.characters.has(cid):
				gs.set_character_concealment(cid, GameState.CONCEAL_NONE)
	_set_preview_step("showcase_touring")

# --- Helpers ---

func _char_in_radius(cid: String, center: Vector3, radius: float) -> bool:
	var pos := _get_character_position(cid)
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
	var tier_name := ""
	match FloraSpecies.tier(key):
		FloraSpecies.Tier.NONE:
			tier_name = "no cover"
		FloraSpecies.Tier.LOOSEST:
			tier_name = "loose cover"
		FloraSpecies.Tier.MEDIUM:
			tier_name = "medium cover"
		FloraSpecies.Tier.TIGHT:
			tier_name = "tight cover"
	return tier_name

# --- Local marker + flora visual helpers (same shapes the other chunks use) ---

func _add_marker(pos: Vector3, size: Vector3, color: Color, energy: float, label: String) -> StandardMaterial3D:
	var mat := _make_material(color * 0.4, color, energy)
	var mesh := _add_box(self, pos - Vector3(0, 0.2, 0), size, color * 0.4)
	mesh.material_override = mat
	_add_label(self, label, pos + Vector3(0, 1.7, 0), color)
	return mat

func _add_flora(pos: Vector3, bloom_mat: StandardMaterial3D, flora_scale: float) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var stem_mat := _make_material(Color(0.12, 0.16, 0.12))
	for i in range(3):
		var angle := float(i) * TAU / 3.0
		var stem := _add_box(root, Vector3(cos(angle) * 0.12, 0.28 * flora_scale, sin(angle) * 0.12),
			Vector3(0.05, 0.56 * flora_scale, 0.05), Color(0.12, 0.16, 0.12))
		stem.material_override = stem_mat
		var bloom := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.13 * flora_scale
		sphere.height = 0.26 * flora_scale
		bloom.mesh = sphere
		bloom.material_override = bloom_mat
		bloom.position = Vector3(cos(angle) * 0.12, 0.56 * flora_scale, sin(angle) * 0.12)
		root.add_child(bloom)
