class_name CombatFeedbackManager
extends Node
## THE HIT & SPOTTING FEEDBACK LAYER (director's spec) — presentation ONLY, a
## consumer of data-layer truth (gs.character_struck + gs positions); it never
## mutates gameplay state. One per scene, created by tutorial_sequence beside
## PathRenderManager / OutlineMaskManager.
##
## ON A STRIKE (gs.character_struck, emitted by the shared Enemy._resolve_strike
## after the damage + knockback commit): the screen SHAKES and FLASHES red —
## each individually disableable in accessibility Settings — and the struck
## body's opacity BLINKS. When the struck character is OFFSCREEN, a red "!"
## bubble additionally pulses above their HUD portrait; the shake and flash
## still fire (the information must land even when the body can't be seen).
##
## ON SPOTTING — a live enemy inside any party member's VISUAL RANGE (the fog
## of war's fully-clear radius, so "visible" and "unfogged" are one truth):
## the enemy wears a persistent RED OUTLINE through the scene's
## OutlineMaskManager until it leaves every visual range or dies (trackable),
## and on the FIRST spot (none were spotted before) the spotting character
## raises a yellow "!" bubble overhead — above their portrait instead when
## they are offscreen.
##
## Determinism: the spotting poll rides the gameplay scheduler (tagged), so
## replay and fast-forward observe identical spot timing; every visual is a
## node-bound tween (dies with its node) and none of it writes the EventLog.
## Headless: no camera / mask manager / HUD just skips that visual — the
## logical counters below still advance, which is what the tests assert.

const VISION_RADIUS := 14.0          # matches perception_stack's fully-clear fog radius
## The red outline LINGERS through brief LOS breaks (director): it drops only
## after the enemy has been outside every visual range for this long. Measured
## on the gameplay scheduler tick, so replay/FF see identical drop timing.
const SPOT_LINGER_SECONDS := 2.0
const SPOT_POLL_INTERVAL := 0.25
const SPOT_POLL_TAG := "combat_feedback_spot"
const SPOT_OUTLINE_COLOR := Color(0.92, 0.16, 0.10)
const ALERT_YELLOW := Color(0.98, 0.84, 0.20)
const ALERT_RED := Color(0.95, 0.22, 0.14)
const FLASH_COLOR := Color(0.85, 0.08, 0.05)
const PARTY_IDS := ["aster", "peris", "endo", "myke"]
const NODE_RESCAN_INTERVAL_FRAMES := 30

var game_state = null
var search_root: Node = null

var _flash_layer: CanvasLayer = null
var _flash_rect: ColorRect = null
var _flash_tween: Tween = null
var _spotted: Dictionary = {}        # enemy instance id -> {node, last_seen_tick}
var _char_nodes: Dictionary = {}     # char_id -> Node3D (cached tree scan)
var _cache_frame := -1000

# Logical counters — the headless-assertable truth of what fired.
var shakes_fired := 0
var flashes_fired := 0
var blinks_fired := 0
var portrait_bubbles_fired := 0
var head_bubbles_fired := 0


func setup(state, root: Node) -> void:
	game_state = state
	search_root = root if root != null else get_parent()
	if game_state != null and game_state.has_signal("character_struck") \
			and not game_state.character_struck.is_connected(_on_character_struck):
		game_state.character_struck.connect(_on_character_struck)
	_schedule_spot_poll()


func _exit_tree() -> void:
	if game_state != null and game_state.scheduler != null:
		game_state.scheduler.cancel_tag(SPOT_POLL_TAG)
	for eid in _spotted.keys():
		_unspot(int(eid))


func spotted_count() -> int:
	return _spotted.size()


func spotted_enemy_ids() -> Array:
	var out: Array = []
	for eid in _spotted:
		var e = (_spotted[eid] as Dictionary).get("node")
		if is_instance_valid(e) and "char_id" in e:
			out.append(str(e.char_id))
	return out


# --- The strike feedback ---

func _on_character_struck(char_id: String, _attacker_id: String) -> void:
	var settings = get_node_or_null("/root/Settings")
	var body := _char_node(char_id)
	if body != null:
		_blink(body)
	if settings == null or bool(settings.get("screen_shake_enabled")):
		_shake()
	if settings == null or bool(settings.get("damage_flash_enabled")):
		_flash()
	if body == null or not _on_screen(body.global_position):
		_portrait_bubble(char_id, ALERT_RED)


## A short decaying camera judder on the view offsets — the follow camera owns
## position/rotation, so offsets never fight it. Bound to the camera node.
func _shake() -> void:
	shakes_fired += 1
	var cam := _camera()
	if cam == null:
		return
	var tw := cam.create_tween()
	for step in [Vector2(0.05, 0.035), Vector2(-0.04, -0.03), Vector2(0.025, 0.02),
			Vector2(-0.012, -0.01), Vector2.ZERO]:
		tw.tween_property(cam, "h_offset", step.x, 0.05)
		tw.parallel().tween_property(cam, "v_offset", step.y, 0.05)


const FLASH_SCENE := preload("res://scenes/ui/damage_flash.tscn")

## One full-screen red pulse (the .tscn owns the structure; this only animates
## alpha). Built lazily; input-transparent.
func _flash() -> void:
	flashes_fired += 1
	if _flash_rect == null:
		_flash_layer = FLASH_SCENE.instantiate()
		add_child(_flash_layer)
		_flash_rect = _flash_layer.get_node("DamageFlash") as ColorRect
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_rect.color = Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, 0.26)
	_flash_tween = _flash_rect.create_tween()
	_flash_tween.tween_property(_flash_rect, "color:a", 0.0, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## The struck body's opacity blinks twice. GeometryInstance3D.transparency is
## per-mesh; one tween_method drives every mesh under the body together.
func _blink(body: Node3D) -> void:
	blinks_fired += 1
	var meshes: Array = []
	var stack: Array = [body]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			meshes.append(n)
		for c in n.get_children():
			stack.append(c)
	if meshes.is_empty():
		return
	var tw := body.create_tween()
	for _cycle in range(2):
		tw.tween_method(_set_meshes_transparency.bind(meshes), 0.0, 0.6, 0.09)
		tw.tween_method(_set_meshes_transparency.bind(meshes), 0.6, 0.0, 0.11)


func _set_meshes_transparency(value: float, meshes: Array) -> void:
	for m in meshes:
		if is_instance_valid(m):
			(m as GeometryInstance3D).transparency = value


# --- The spotting feedback ---

func _schedule_spot_poll() -> void:
	if game_state == null or game_state.scheduler == null:
		return
	game_state.scheduler.cancel_tag(SPOT_POLL_TAG)
	game_state.scheduler.schedule_after(SPOT_POLL_INTERVAL, _spot_poll, SPOT_POLL_TAG)


func _spot_poll() -> void:
	if game_state == null:
		return
	var now := 0.0
	if game_state.scheduler != null:
		now = float(game_state.scheduler.get_current_tick())
	var alive: Dictionary = {}
	var newly: Array = []
	for e in _live_enemies():
		var eid: int = e.get_instance_id()
		alive[eid] = true
		var spotter := _spotter_for(e)
		if spotter != "":
			if _spotted.has(eid):
				(_spotted[eid] as Dictionary)["last_seen_tick"] = now
			else:
				newly.append([e, spotter])
	# out-of-sight entries LINGER for the grace window, then drop; dead or
	# freed enemies drop immediately
	for eid in _spotted.keys():
		var entry: Dictionary = _spotted[eid]
		if not alive.has(int(eid)):
			_unspot(int(eid))
		elif now - float(entry.get("last_seen_tick", now)) >= SPOT_LINGER_SECONDS:
			_unspot(int(eid))
	var was_empty := _spotted.is_empty()
	for pair in newly:
		_spot(pair[0], now)
	if was_empty and not newly.is_empty():
		var spotter_id: String = str(newly[0][1])
		var node := _char_node(spotter_id)
		if node != null and _on_screen(node.global_position):
			_head_bubble(node, ALERT_YELLOW)
		else:
			_portrait_bubble(spotter_id, ALERT_YELLOW)
	_schedule_spot_poll()


func _spot(enemy: Node, seen_tick: float) -> void:
	var meshes: Array = []
	var stack: Array = [enemy]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).visible:
			meshes.append(n)
		for c in n.get_children():
			stack.append(c)
	_spotted[enemy.get_instance_id()] = {"node": enemy, "last_seen_tick": seen_tick}
	var mask := OutlineMaskManager.find_for(self)
	if mask != null and not meshes.is_empty():
		mask.register(enemy.get_instance_id(), meshes, SPOT_OUTLINE_COLOR, false)


func _unspot(eid: int) -> void:
	_spotted.erase(eid)
	var mask := OutlineMaskManager.find_for(self)
	if mask != null:
		mask.unregister(eid)


func _live_enemies() -> Array:
	if search_root == null or not is_instance_valid(search_root):
		return []
	var out: Array = []
	for e in search_root.find_children("*", "Enemy", true, false):
		if e.has_method("is_alive") and not bool(e.call("is_alive")):
			continue
		out.append(e)
	return out


## The nearest party member whose VISUAL RANGE contains the enemy (data-layer
## planar distance — the same truth the fog's clear radius renders).
func _spotter_for(enemy: Node) -> String:
	if game_state == null or not ("char_id" in enemy):
		return ""
	var eid := str(enemy.char_id)
	if not game_state.characters.has(eid):
		return ""
	var epos: Vector3 = game_state.get_position(eid)
	var best := ""
	var best_d := VISION_RADIUS
	for pid in PARTY_IDS:
		if not game_state.characters.has(pid):
			continue
		var p: Vector3 = game_state.get_position(pid)
		var d := Vector2(p.x, p.z).distance_to(Vector2(epos.x, epos.z))
		if d <= best_d:
			best_d = d
			best = pid
	return best


# --- Bubbles ---

func _head_bubble(body: Node3D, color: Color) -> void:
	head_bubbles_fired += 1
	var label := Label3D.new()
	label.text = "!"
	label.font_size = 96
	label.outline_size = 18
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 2.4, 0.0)
	label.scale = Vector3.ONE * 0.2
	body.add_child(label)
	var tw := label.create_tween()
	tw.tween_property(label, "scale", Vector3.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.5)
	tw.tween_property(label, "modulate:a", 0.0, 0.35)
	tw.tween_callback(label.queue_free)


func _portrait_bubble(char_id: String, color: Color) -> void:
	portrait_bubbles_fired += 1
	var hud := _hud()
	if hud != null and hud.has_method("show_portrait_alert_bubble"):
		hud.call("show_portrait_alert_bubble", char_id, color)


# --- Lookups ---

func _camera() -> Camera3D:
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null


func _on_screen(world_pos: Vector3) -> bool:
	var cam := _camera()
	if cam == null:
		return true
	return cam.is_position_in_frustum(world_pos)


func _hud() -> Node:
	if search_root == null or not is_instance_valid(search_root):
		return null
	return search_root.find_child("GameHUD", true, false)


func _char_node(char_id: String) -> Node3D:
	var frame := Engine.get_process_frames()
	if frame - _cache_frame > NODE_RESCAN_INTERVAL_FRAMES:
		_cache_frame = frame
		_char_nodes.clear()
		if search_root != null and is_instance_valid(search_root):
			for n in search_root.find_children("*", "", true, false):
				if n is Node3D and "char_id" in n and n is not Enemy \
						and not (n.get_parent() is SubViewport):
					var cid := str(n.get("char_id"))
					if cid != "" and not _char_nodes.has(cid):
						_char_nodes[cid] = n
	var hit = _char_nodes.get(char_id)
	return hit if hit != null and is_instance_valid(hit) else null
