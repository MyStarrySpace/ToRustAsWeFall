@tool
class_name TutorialSequence
extends Node3D

## Shared scheduler, GameState, UI, camera, and scene helpers for tutorials.

const INTERACTABLE_SCENE := preload("res://scenes/game/interactable.tscn")
const ItemData = preload("res://scripts/game/objects/item_data.gd")
const EXPLORATION_RADIUS_SCALE := 1.35
const EXPLORATION_MIN_RADIUS := 1.6
const EXPLORATION_FOCUS_OFFSET := Vector3(0, 4.2, 3.2)
const EXPLORATION_FOCUS_HEIGHT := 0.9
const OUTLINE_POST_PROCESS_ENABLED := false
const CHROMATIC_ABERRATION_SHADER := preload("res://resources/chromatic_aberration.gdshader")
const SCREEN_EFFECT_SCENE := preload("res://scenes/ui/screen_effect.tscn")
const SEQUENCE_ANIMATION_PLAYER_SCENE := preload("res://scenes/ui/sequence_animation_player.tscn")
const TOUCH_MODE_CONTROLLER_SCENE := preload("res://scenes/ui/touch_mode_controller.tscn")

@export_group("Post Processing")
@export var chromatic_aberration_enabled := false:
	set(value):
		chromatic_aberration_enabled = value
		_sync_chromatic_aberration_effect()
@export_range(0.0, 8.0, 0.1, "suffix:px") var chromatic_aberration_strength := 2.0:
	set(value):
		chromatic_aberration_strength = value
		_sync_chromatic_aberration_effect()
@export_range(0.0, 1.0, 0.01) var chromatic_aberration_intensity := 1.0:
	set(value):
		chromatic_aberration_intensity = value
		_sync_chromatic_aberration_effect()

# Core infrastructure
var _scheduler: EventScheduler          # gameplay lane (pausable, replay)
var _ui_scheduler: EventScheduler       # dialogue / thought-fade / UI lane
var _game_state: GameState
var _path_render_manager                # PathRenderManager: movement paths for all characters
var _downed_body_manager                # DownedBodyManager: fallen members become clickable carry targets
var _outline_mask_manager               # OutlineMaskManager: screen-space object outlines for all targets
var _selection_controller               # SelectionController: RTS left-click / marquee character select
var _playthrough_recorder               # normal-play deterministic tape / movie replay autoload
var _story_beat_runner := StoryBeatRunner.new()
var _current_step := ""
var _fade_start_tick := 0.0

# UI references (populated by _init_ui)
var _dialogue       # CanvasLayer + dialogue_box.gd
var _tutorial_prompt # TutorialUI prompt facade
var _fade_rect: ColorRect
var _thought_label: Label
var _engram_overlay
var _pause_menu
var _dev_console    # DevConsole (backtick) — the only in-game door to dev switches
var _touch_modes    # TouchModeController — the mobile camera/select/action mode cluster
var _chromatic_aberration_layer: CanvasLayer
var _chromatic_aberration_rect: ColorRect
var _chromatic_aberration_material: ShaderMaterial

# Fog of war is a standing GAMEPLAY layer, independent of the Aster/Peris perception views —
# turning those views off must never reveal the map. Only the dev console (`fog off`) or a dev
# surface flips this; scenes that render fog read it every overlay sync.
var fog_of_war_enabled := true

# Player and camera (populated by subclass via helpers)
var _player         # CharacterBody3D + player.gd
var _camera         # Camera3D + game_camera.gd

# Perception system
var _perception_quad: MeshInstance3D
var _perception_material: ShaderMaterial
var _perception_mode := ""  # "", "data", "fog", "outline"
var _perception_target: Node3D  # Character whose position drives the shader
var _data_identify_active := false  # Aster's data overlay on → hovering an object reveals its name
var _outline_hover_source: Node3D = null
var _outline_selected_source: Node3D = null
var _outline_hover_color := Color.WHITE
var _outline_selected_color := Color(1.0, 0.62, 0.12, 1.0)
var _outline_hover_radius := 2.0
var _outline_selected_radius := 2.0
var _outline_hover_extents := Vector3.ZERO
var _outline_selected_extents := Vector3.ZERO
var _outline_selection_token := 0
var _outline_feedback_manager: Node = null

# Dialogue chain state (used by _dialogue_chain helper)
var _dlg_chain_keys: Array = []
var _dlg_chain_index := 0
var _dlg_chain_next: Callable
var _dlg_chain_delay := 0.0
var _did_teardown := false
var suppress_scene_change := false
var requested_scene_change := ""
var _capture_pause_depth := 0
var _capture_pause_was_paused := false
var _thought_fade_active := false
var _thought_fade_start_tick := 0.0
var _thought_fade_duration := 0.0
var _thought_fade_from_alpha := 0.0
var _thought_fade_to_alpha := 0.0
var _exploration_focus_active := false
var _exploration_focus_prev_camera_offset := Vector3.ZERO
var _exploration_focus_prev_camera_target: Node3D = null
var _exploration_focus_prev_camera_state := {}
var _exploration_focus_prev_scheduler_paused := false
var _exploration_focus_prev_move_enabled := true

func _ready() -> void:
	if Engine.is_editor_hint():
		_clear_editor_generated_preview_children()
	else:
		_outline_feedback_manager = OutlineFeedbackManager.ensure(self)
	_build_scene()
	_build_characters()
	if Engine.is_editor_hint():
		return
	# Object hover + RTS right-click-to-interact ride the engine's physics picking (Area3D
	# mouse_entered / input_event). It's off by default, so enable it here — without it the white hover
	# outline never lit and the interactable's own click path was dead.
	get_viewport().physics_object_picking = true
	_scheduler = EventScheduler.new()
	# Second lane: dialogue / thought-fades / UI timers. F-scaled but never frozen
	# by gameplay pause — "pause gameplay, keep dialogue" is structural, not a hack.
	_ui_scheduler = EventScheduler.new()
	_game_state = GameState.new()
	_game_state.scheduler = _scheduler
	# A normal-play recording attaches here, before character/object registration, so its
	# authoritative EventLog covers the complete scene segment. Playback uses the same seam.
	_playthrough_recorder = get_node_or_null("/root/PlaythroughRecorder")
	if _playthrough_recorder != null and _playthrough_recorder.has_method("attach_game_state"):
		_playthrough_recorder.attach_game_state(_game_state, scene_file_path)
	_register_characters()
	# One scene-level path renderer for EVERY moving character (player, party, NPC, escort) — the
	# reusable home for movement-path visuals, not a per-controller one-off.
	_path_render_manager = PathRenderManager.new()
	_path_render_manager.name = "PathRenderManager"
	add_child(_path_render_manager)
	_path_render_manager.setup(_game_state, self)
	# One scene-level screen-space outline manager: OutlineSurfaceTargets register their meshes with it to show
	# the crisp object outline (clean on flat-shaded meshes, constant width at any distance). Same once-per-scene
	# pattern as the path renderer — every OutlineSurfaceTarget in the scene finds it via OutlineMaskManager.find_for.
	_outline_mask_manager = OutlineMaskManager.new()
	_outline_mask_manager.name = "OutlineMaskManager"
	add_child(_outline_mask_manager)
	_inject_scheduler_into_interactables(self)
	_init_ui()
	# One scene-level RTS selection controller (left-click / marquee character select), feeding the HUD
	# selection set — same once-per-scene pattern as the PathRenderManager. It resolves the HUD + active
	# player lazily from the sequence (both are created by the subclass _ready, after this base _ready).
	_selection_controller = SelectionController.new()
	_selection_controller.name = "SelectionController"
	add_child(_selection_controller)
	_selection_controller.setup(_game_state, self)
	# One scene-level downed-body manager: a fallen party member becomes a clickable body (click to
	# CARRY through the shared drag system, click again to set down) — same once-per-scene pattern.
	_downed_body_manager = DownedBodyManager.new()
	_downed_body_manager.name = "DownedBodyManager"
	add_child(_downed_body_manager)
	_downed_body_manager.setup(_game_state, self)
	_story_beat_runner.setup(StoryBeatContext.new(
		self, _game_state, _scheduler, _ui_scheduler, _story_beat_services()
	))
	_configure_story_beats()
	_begin()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# Scene changes can dispatch one final _process after teardown.
	if _scheduler == null or _game_state == null:
		return
	# Cosmetic: keep background chunk streams building a slice per frame (independent of the gameplay clock).
	_advance_chunk_streams()
	# Gameplay lane.
	var spd := _compute_speed()
	_scheduler.set_speed(spd)
	var gameplay_scheduler: EventScheduler = _scheduler
	var gameplay_tick_before := gameplay_scheduler.get_current_tick()
	for node in _get_speed_recipients():
		# A chunk reload (the roguelike loader) queue_frees the old chunk's recipients; skip any that a
		# subclass list hasn't pruned yet rather than writing to a freed node.
		if is_instance_valid(node):
			node.speed_multiplier = spd
	# A rendered deterministic playthrough may have input boundaries between fixed movie
	# frames. Stop exactly on those ticks; the recorder injects the inputs next frame and
	# ordinary gameplay continues. Live play keeps the scheduler's normal real-delta path.
	if _playthrough_recorder != null and _playthrough_recorder.has_method("constrain_playback_advance") \
			and bool(_playthrough_recorder.call("is_playing_back")):
		var requested_ticks := delta * spd
		var allowed_ticks := float(_playthrough_recorder.call(
			"constrain_playback_advance", gameplay_scheduler, requested_ticks))
		gameplay_scheduler.advance_ticks(allowed_ticks)
	else:
		gameplay_scheduler.advance(delta)
	var gameplay_ticks_advanced := gameplay_scheduler.get_current_tick() - gameplay_tick_before
	# advance() can fire a scheduled callback — e.g. a scene transition's _complete →
	# change_scene_to_file → _teardown_sequence — that tears this sequence down synchronously,
	# nulling both schedulers. The guard above only ran BEFORE advance, so re-check here before
	# touching the (possibly torn-down) UI lane, or _ui_scheduler.get_current_tick() hits null.
	if _scheduler == null or _ui_scheduler == null or _game_state == null:
		return
	# UI lane: dialogue + thought-fades advance here. F-scaled, but independent of
	# gameplay pause, so pausing gameplay keeps narrative flowing.
	var ui_before := _ui_scheduler.get_current_tick()
	_ui_scheduler.set_speed(_compute_dialogue_speed())
	_ui_scheduler.advance(delta)
	var ui_delta := _ui_scheduler.get_current_tick() - ui_before
	if _dialogue:
		_dialogue.advance_ui_time(ui_delta)
	_sync_scheduler_animations()
	_update_thought_fade()
	_sync_perception_shader()
	_update_data_identify()
	# Subclass gameplay integration must consume SIMULATION time, not render time. This
	# keeps planning pause free and makes fixed-FPS movie replay preserve live outcomes.
	var gameplay_delta := gameplay_ticks_advanced / spd if spd > 0.000001 else 0.0
	_story_beat_runner.update(gameplay_delta)
	_on_process(gameplay_delta, spd)

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	_teardown_sequence()

# --- Virtual methods (override in subclasses) ---

func _build_scene() -> void:
	pass

func _build_characters() -> void:
	pass

func _register_characters() -> void:
	pass

func _setup_ui() -> void:
	pass

func _begin() -> void:
	pass

func _on_process(_delta: float, _spd: float) -> void:
	pass

## Register reusable StoryBeat instances here. The base runner synchronizes their
## lifecycle with `_enter_step`; legacy steps continue to work unchanged.
func _configure_story_beats() -> void:
	pass

## Optional typed capabilities made available to beats through StoryBeatContext.
## Subclasses can merge additional services without exposing their whole controller.
func _story_beat_services() -> Dictionary:
	return {
		&"dialogue": _dialogue,
		&"tutorial_prompt": _tutorial_prompt,
	}

func _compute_speed() -> float:
	return 10.0 if Input.is_action_pressed("fast_forward") else 1.0

## Dialogue clock speed. Intentionally independent of _compute_speed(): holding
## F fast-forwards dialogue even while gameplay is paused (Peris protect prompt,
## exploration focus), and a paused scheduler never freezes dialogue.
func _compute_dialogue_speed() -> float:
	return 10.0 if Input.is_action_pressed("fast_forward") else 1.0

func _get_speed_recipients() -> Array:
	return []

func headless_advance(duration: float, step := 0.05) -> void:
	if Engine.is_editor_hint() or _scheduler == null:
		return
	var remaining: float = duration
	while remaining > 0.0001:
		var dt: float = minf(step, remaining)
		_scheduler.advance_ticks(dt)
		# Same hazard as _process: a scheduled callback (a scene transition's _complete) can
		# tear the sequence down mid-advance, nulling _scheduler. Bail before re-using it.
		if _scheduler == null:
			return
		if _ui_scheduler:
			_ui_scheduler.advance_ticks(dt)
		if _dialogue:
			# Same UI lane as real play; dt is already in ticks (1x headless).
			_dialogue.advance_ui_time(dt)
		_sync_scheduler_animations()
		_update_thought_fade()
		_sync_perception_shader()
		_update_data_identify()
		_story_beat_runner.update(dt)
		_on_process(dt, 1.0)
		_headless_sync_scheduler_visuals()
		_headless_sync_runtime(dt)
		remaining -= dt

func headless_get_anchor_positions() -> Dictionary:
	return {}

func headless_get_state() -> Dictionary:
	return {
		"current_step": _current_step,
		"requested_scene_change": requested_scene_change,
		"scheduler_tick": _scheduler.get_current_tick() if _scheduler else 0.0,
	}

func _headless_sync_runtime(_delta: float) -> void:
	pass

func _headless_sync_scheduler_visuals() -> void:
	for node in find_children("*", "", true, false):
		if node.has_method("sync_scheduler_visuals"):
			node.call("sync_scheduler_visuals")

func _get_chunk_scene(_chunk_name: String) -> PackedScene:
	return null

func _clear_editor_generated_preview_children() -> void:
	for child in get_children().duplicate():
		if child.owner == null:
			child.free()

# --- Perception system ---

## Enable a perception overlay: data, fog, or outline.
func _setup_perception(mode: String, tracking_node: Node3D) -> void:
	if not _perception_quad:
		_perception_quad = MeshInstance3D.new()
		_perception_quad.name = "PerceptionQuad"
		var qm := QuadMesh.new()
		qm.size = Vector2(2, 2)
		_perception_quad.mesh = qm
		_perception_quad.extra_cull_margin = 10000.0
		_perception_material = ShaderMaterial.new()
		# Leave the final priority slot to world-space planning feedback. Path ribbons,
		# destination ghosts/rings, causal links, and object outlines all render at 127
		# so they remain legible after this full-screen rewrite (the shared managers
		# already document and test that composition contract).
		_perception_material.render_priority = 126
		_perception_quad.material_override = _perception_material
		add_child(_perception_quad)
	_set_perception_mode(mode)
	_perception_target = tracking_node
	_sync_perception_shader()

## Switch the perception shader without recreating the quad.
func _set_perception_mode(mode: String) -> void:
	_perception_mode = mode
	if not _perception_material:
		return
	match mode:
		"data":
			_perception_material.shader = preload("res://resources/data_view.gdshader")
		"fog":
			_perception_material.shader = preload("res://resources/peris_fog.gdshader")
		"outline":
			if not OUTLINE_POST_PROCESS_ENABLED:
				_perception_material.shader = null
				_perception_quad.visible = false
				return
			_perception_material.shader = preload("res://resources/black_outline.gdshader")
		_:
			_perception_quad.visible = false
			return
	_perception_quad.visible = true

## Change which character the perception shader tracks.
func _set_perception_target(node: Node3D) -> void:
	_perception_target = node
	_sync_perception_shader()

func _sync_perception_shader() -> void:
	if _perception_mode == "outline":
		_sync_outline_highlights()
		return
	if _perception_material == null or _perception_target == null:
		return
	_perception_material.set_shader_parameter("character_pos",
		_get_perception_target_position() + Vector3(0, 1.0, 0))

func _sync_outline_highlights() -> void:
	# Object materials own hover/selection feedback to avoid screen-edge bleed.
	pass

func _get_outline_shader_material() -> ShaderMaterial:
	if _perception_mode != "outline":
		return null
	if _perception_material != null and _perception_material.shader != null:
		return _perception_material
	var imported_outline := find_child("AsterSimRoomOutlinePreview", true, false) as MeshInstance3D
	if imported_outline != null:
		return imported_outline.material_override as ShaderMaterial
	var fallback_outline := find_child("PerceptionQuad", true, false) as MeshInstance3D
	if fallback_outline != null:
		return fallback_outline.material_override as ShaderMaterial
	return null

func _get_perception_target_position() -> Vector3:
	var pos := _perception_target.global_position
	var target_game_state = _perception_target.get("game_state")
	var target_char_id := str(_perception_target.get("char_id"))
	if target_game_state != null and target_char_id != "" and target_game_state.characters.has(target_char_id):
		pos = target_game_state.get_position(target_char_id)
	return pos

# --- UI setup ---

func _init_ui() -> void:
	var ui := preload("res://scenes/game/tutorial_ui.tscn").instantiate()
	add_child(ui)
	_dialogue = ui.get_node("DialogueBox")
	_tutorial_prompt = ui
	_fade_rect = ui.get_node("FadeOverlay/FadeRect")
	_thought_label = ui.get_node("ThoughtOverlay/ThoughtLabel")
	_fade_rect.color.a = 0.0

	_engram_overlay = preload("res://scenes/ui/engram_overlay.tscn").instantiate()
	add_child(_engram_overlay)

	# Esc-toggled pause menu (Resume / Settings → accessibility). Self-contained:
	# it handles its own input and pauses gameplay while open.
	_pause_menu = preload("res://scenes/ui/pause_menu.tscn").instantiate()
	_pause_menu.name = "PauseMenu"
	add_child(_pause_menu)

	# Backtick-toggled developer console — the one sanctioned door to dev switches in normal play
	# (fog of war stays ON in the game proper; only this console or a dev surface may turn it off).
	_dev_console = preload("res://scenes/ui/dev_console.tscn").instantiate()
	add_child(_dev_console)
	_dev_console.register_command("fog", _cmd_fog, "fog on|off — the fog of war (default on)")
	_dev_console.register_command("fxdebug", _cmd_fxdebug, "fxdebug on|off — path/outline FX traces")
	_dev_console.register_command("chroma", _cmd_chroma, "chroma on|off — testing-mode ID-color overlay on every interactable")
	_dev_console.register_command("photo", _cmd_photo, "photo on|off — screenshot mode: fog of war + UI hidden, restored on off")
	_dev_console.register_command("events", _cmd_events, "events on|off — print every game event + note to the console (default on in play)")
	# THE EVENT TRACE defaults ON for interactive play and OFF under the test runner/headless —
	# a play session console always carries the WHY (catches, sweeps, teleports, damage), and
	# ten thousand headless tests do not drown in it.
	if DisplayServer.get_name() != "headless" and not _running_under_test_flags() \
			and not (_playthrough_recorder != null \
				and bool(_playthrough_recorder.call("is_playing_back"))):
		EventLog.print_events = true

	# Mobile control modes: on touch, ONE finger carries three meanings — CAMERA drag-pan / SELECT
	# (tap-pick + marquee, with the interactable reveal on) / ACTION (tap = the command click).
	# The cluster appears on touchscreen devices; `touch on` forces it for desktop testing.
	_touch_modes = TOUCH_MODE_CONTROLLER_SCENE.instantiate()
	add_child(_touch_modes)
	_touch_modes.setup(self)
	# SELECT mode is the LOOK mode: the reveal-all outline (the hold-SHIFT treatment) stays on
	# while it's active, so every interactable advertises itself.
	_touch_modes.mode_changed.connect(func(m: String): _on_highlight_held(m == "select"))
	_dev_console.register_command("touch", _cmd_touch, "touch on|off — force the mobile control-mode cluster")

	_init_chromatic_aberration_effect()
	_setup_ui()
	# Wire the shared hold-SHIFT reveal-all HERE, once, after the subclass built its HUD — so no scene
	# has to remember the connection individually (it drifted: the fragment preview, showcase, and others
	# were missing it). Scenes that build no HUD no-op.
	_wire_shared_hud_signals()

func _cmd_touch(args: Array) -> String:
	if _touch_modes == null:
		return "no touch-mode controller in this scene"
	if not args.is_empty():
		_touch_modes.set_forced(str(args[0]).to_lower() in ["on", "true", "1"])
	return "touch cluster %s (mode: %s)" % ["shown" if _touch_modes.visible else "hidden", _touch_modes.mode]

## Dev-console commands shared by every scene. Fog of war is a GAMEPLAY layer (independent of the
## Aster/Peris perception views); scenes that render it read fog_of_war_enabled each sync.
func _cmd_fog(args: Array) -> String:
	if not args.is_empty():
		fog_of_war_enabled = str(args[0]).to_lower() in ["on", "true", "1"]
	return "fog of war: %s" % ("ON" if fog_of_war_enabled else "off (dev)")

var _photo_mode := false
var _photo_fog_prev := true

## SCREENSHOT MODE (dev): hides the fog of war AND the UI canvases for clean captures. It rides
## the console because fog is a gameplay layer — photo mode is a sanctioned dev exception like
## `fog off`, and `photo off` restores exactly the fog state it found.
func _cmd_photo(args: Array) -> String:
	if not args.is_empty():
		var want := str(args[0]).to_lower() in ["on", "true", "1"]
		if want != _photo_mode:
			_photo_mode = want
			if want:
				_photo_fog_prev = fog_of_war_enabled
				fog_of_war_enabled = false
			else:
				fog_of_war_enabled = _photo_fog_prev
			_apply_photo_mode(_photo_mode)
	return "photo mode: %s" % ("ON — fog + UI hidden (`photo off` restores)" if _photo_mode else "off")

## Scene hook for photo mode: the base hides nothing (scenes own their canvases); the fragment
## preview overrides this to hide its HUD and preview UI layer.
func _apply_photo_mode(_active: bool) -> void:
	pass

func _cmd_events(args: Array) -> String:
	if not args.is_empty():
		EventLog.print_events = str(args[0]).to_lower() in ["on", "true", "1"]
	return "event trace: %s" % ("ON" if EventLog.print_events else "off")

static func _running_under_test_flags() -> bool:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--test-"):
			return true
	return false

func _cmd_fxdebug(args: Array) -> String:
	if not args.is_empty():
		GridWorld._fx_debug = str(args[0]).to_lower() in ["on", "true", "1"]
	return "fx debug traces: %s" % ("ON (see console output)" if GridWorld._fx_debug else "off")

## Testing-mode chroma overlay: every interactable wears its ID color as a translucent proxy — the
## human-visible face of the same ChromaProbe machinery the player-contract tests read as pixels.
func _cmd_chroma(args: Array) -> String:
	var on := not args.is_empty() and str(args[0]).to_lower() in ["on", "true", "1"]
	var probe := ChromaProbe.ensure(self)
	if probe == null:
		return "chroma: no probe (null context)"
	if on:
		probe.clear()
		var idx := 0
		var stack: Array = [self as Node]
		while not stack.is_empty():
			var n := stack.pop_back() as Node
			for child in n.get_children():
				stack.append(child)
			if n is Node3D and n.has_signal("interacted") and "interaction_radius" in n:
				probe.register(n as Node3D, ChromaProbe.KIND_INTERACTABLE, idx,
					maxf(0.5, float(n.get("interaction_radius"))) * 0.7, 1.4)
				idx += 1
		probe.set_overlay_visible(true)
		return "chroma overlay: ON (%d interactables)" % idx
	probe.set_overlay_visible(false)
	return "chroma overlay: off"

## Connect the universal HUD signals every scene shares (currently: hold-SHIFT reveal-all). The HUD is
## resolved by NODE — every scene names it "GameHUD" and runs game_hud.gd (which owns highlight_held) —
## because _hud is a per-subclass var, not a base member. Guarded so a stray per-scene connect can't
## double-bind, and a HUD-less scene (tag_day) simply finds nothing.
func _wire_shared_hud_signals() -> void:
	var hud := get_node_or_null("GameHUD")
	if hud != null and hud.has_signal("highlight_held") and not hud.highlight_held.is_connected(_on_highlight_held):
		hud.highlight_held.connect(_on_highlight_held)

func _init_chromatic_aberration_effect() -> void:
	if _chromatic_aberration_layer != null:
		_sync_chromatic_aberration_effect()
		return

	_chromatic_aberration_layer = SCREEN_EFFECT_SCENE.instantiate() as CanvasLayer
	_chromatic_aberration_layer.name = "ChromaticAberrationLayer"
	_chromatic_aberration_layer.layer = 0
	add_child(_chromatic_aberration_layer)

	_chromatic_aberration_rect = _chromatic_aberration_layer.get_node("ScreenEffect") as ColorRect
	_chromatic_aberration_rect.name = "ChromaticAberrationRect"

	_chromatic_aberration_material = ShaderMaterial.new()
	_chromatic_aberration_material.shader = CHROMATIC_ABERRATION_SHADER
	_chromatic_aberration_rect.material = _chromatic_aberration_material
	_sync_chromatic_aberration_effect()

func _sync_chromatic_aberration_effect() -> void:
	if _chromatic_aberration_layer == null or _chromatic_aberration_material == null:
		return
	var active := (
		chromatic_aberration_enabled
		and chromatic_aberration_strength > 0.0
		and chromatic_aberration_intensity > 0.0
	)
	_chromatic_aberration_layer.visible = active
	_chromatic_aberration_material.set_shader_parameter("strength_px", chromatic_aberration_strength)
	_chromatic_aberration_material.set_shader_parameter("intensity", chromatic_aberration_intensity)

func set_chromatic_aberration_enabled(enabled: bool) -> void:
	chromatic_aberration_enabled = enabled
	_sync_chromatic_aberration_effect()

func _teardown_sequence() -> void:
	if _did_teardown:
		return
	_did_teardown = true
	_story_beat_runner.deactivate(&"scene_teardown")

	# Prevent one last _process from touching torn-down state.
	set_process(false)
	set_physics_process(false)

	if _dialogue:
		for conn in _dialogue.dialogue_finished.get_connections():
			_dialogue.dialogue_finished.disconnect(conn.callable)
		if _dialogue.has_method("clear"):
			_dialogue.clear()

	_dlg_chain_keys.clear()
	_dlg_chain_index = 0
	_dlg_chain_next = Callable()
	_dlg_chain_delay = 0.0
	_scheduler_animation_states.clear()
	_thought_fade_active = false
	_perception_target = null
	_outline_feedback_manager = null

	if _camera:
		_camera.target = null

	for node in find_children("*", "", true, false):
		for prop in node.get_property_list():
			if prop.name == "game_state":
				node.set("game_state", null)
				break

	if _scheduler:
		_scheduler.clear()
	if _ui_scheduler:
		_ui_scheduler.clear()
	if _game_state:
		_game_state.scheduler = null

	_game_state = null
	_scheduler = null
	_ui_scheduler = null
	_path_render_manager = null
	_outline_mask_manager = null
	_selection_controller = null
	_playthrough_recorder = null
	_dialogue = null
	_tutorial_prompt = null
	_fade_rect = null
	_thought_label = null
	_engram_overlay = null
	_pause_menu = null
	_chromatic_aberration_layer = null
	_chromatic_aberration_rect = null
	_chromatic_aberration_material = null

func _change_scene_or_record(scene_path: String) -> void:
	requested_scene_change = scene_path
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null:
		save_manager.save_current("scene_change")
	if suppress_scene_change:
		return
	get_tree().change_scene_to_file(scene_path)

func build_save_snapshot() -> Dictionary:
	return {
		"scene_kind": "tutorial_sequence",
		"current_step": _current_step,
		"requested_scene_change": requested_scene_change,
		"scheduler": _scheduler.serialize() if _scheduler != null else {},
		"game_state": _game_state.serialize() if _game_state != null else {},
		"capture_context": get_capture_context(),
	}

func apply_save_snapshot(data: Dictionary) -> void:
	if _scheduler != null and data.has("scheduler"):
		_scheduler.deserialize(data.scheduler)
	if data.has("game_state"):
		_apply_saved_game_state(data.game_state)
	_current_step = str(data.get("current_step", _current_step))
	requested_scene_change = str(data.get("requested_scene_change", requested_scene_change))

func _apply_saved_game_state(snapshot: Dictionary) -> void:
	if _game_state == null:
		return
	var characters_snapshot: Dictionary = snapshot.get("characters", {})
	for char_id in characters_snapshot.keys():
		if not _game_state.characters.has(char_id):
			continue
		var saved_char: Dictionary = characters_snapshot[char_id]
		var position_arr: Array = saved_char.get("position", [0.0, 0.0, 0.0])
		var position := Vector3(
			float(position_arr[0]),
			float(position_arr[1]),
			float(position_arr[2])
		)
		var runtime_char: Dictionary = _game_state.characters[char_id]
		runtime_char["position"] = position
		runtime_char["move_speed"] = float(saved_char.get("move_speed", runtime_char.get("move_speed", 3.0)))
		runtime_char["stats"] = saved_char.get("stats", {}).duplicate(true)
		runtime_char["movement"] = null
		if _game_state.grid != null:
			runtime_char["grid_cell"] = _game_state.grid.world_to_grid(position)
		var node := _find_character_node(char_id)
		if node != null:
			node.global_position = Vector3(position.x, node.global_position.y, position.z)
	if snapshot.has("explored"):
		_game_state._deserialize_explored(snapshot.explored)

func _find_character_node(char_id: String) -> Node3D:
	for node in find_children("*", "", true, false):
		if not (node is Node3D):
			continue
		if "char_id" in node and str(node.char_id) == char_id:
			return node
	return null

func set_capture_pause(active: bool) -> void:
	if _scheduler == null:
		return
	if active:
		if _capture_pause_depth == 0:
			_capture_pause_was_paused = _scheduler.is_paused()
			if not _capture_pause_was_paused:
				_scheduler.pause()
		_capture_pause_depth += 1
		return
	if _capture_pause_depth > 0:
		_capture_pause_depth -= 1
	if _capture_pause_depth == 0 and not _capture_pause_was_paused:
		_scheduler.resume()

func show_capture_message(text: String) -> void:
	if _tutorial_prompt != null:
		_tutorial_prompt.show_prompt(text, 1.6)

func get_capture_context() -> Dictionary:
	var scene_label: String = _humanize_capture_token(name if name != "" else _scene_label_from_path())
	var sub_location: String = _humanize_capture_token(_current_step)
	var position: Vector3 = _player.global_position if _player != null else Vector3.ZERO
	return {
		"scene_path": scene_file_path,
		"scene_name": scene_label,
		"act": 0,
		"day": 0,
		"time_of_day": "",
		"timestamp_label": scene_label,
		"location": scene_label,
		"sub_location": sub_location,
		"trigger_type": "manual",
		"trigger_context": _current_step if _current_step != "" else "manual_capture",
		"position": position,
		"caption": "%s%s" % [scene_label, (", " + sub_location) if sub_location != "" else ""],
	}

func _scene_label_from_path() -> String:
	var path: String = scene_file_path
	if path == "":
		return "engram"
	return path.get_file().get_basename()

func _humanize_capture_token(value: String) -> String:
	if value == "":
		return ""
	var words := value.replace("_", " ").replace("-", " ").split(" ", false)
	for i in range(words.size()):
		words[i] = str(words[i]).capitalize()
	return " ".join(words)

# --- Character helpers ---

func _create_player_character(char_name: String, char_color: Color) -> CharacterBody3D:
	var p := preload("res://scenes/game/player_character.tscn").instantiate()
	p.name = char_name
	p.color = char_color
	p.get_node("Label3D").text = char_name.to_upper()
	p.get_node("Label3D").modulate = Color(char_color, 0.8)
	return p

func _create_npc(npc_name: String, npc_color: Color) -> Node3D:
	var npc := Node3D.new()
	npc.name = npc_name.replace("-", "_")
	npc.set_script(preload("res://scripts/game/ai/npc.gd"))
	npc.display_name = npc_name
	npc.color = npc_color
	return npc

## Build the shared follow camera. Pass free_look = true to start with the full "move the camera around"
## control set (WASD + right-drag + edge-scroll, click recenters) — what you want when testing/exploring a
## scene or chunk. Scripted scenes (tag_day, elevator) leave it false and drive the camera per-beat.
func _setup_game_camera(target_node: Node3D, offset := Vector3(0, 10, 7), free_look := false) -> void:
	var cam := Camera3D.new()
	cam.name = "GameCamera"
	cam.set_script(preload("res://scripts/ui/game_camera.gd"))
	add_child(cam)
	_camera = cam
	_camera.target = target_node
	_camera.follow_offset = offset
	if free_look:
		_camera.enable_free_look()
	else:
		_camera.set_pan_enabled(false)

## Clamp the camera's look-at to the LEVEL's world bounds (derived from the grid extent), so pan / edge-scroll /
## look-around can never drift the view off the level and "lose the room". Reusable: any scene passes its grid
## (the base doesn't own one — subclasses do) once it + the camera exist (no-ops without them). `inset` pulls the
## bound IN from the edge so the view stays over the interior instead of centring on a wall; `extra` grows it.
func _bind_camera_to_level_bounds(grid, inset := 0.0, extra := 0.0) -> void:
	if _camera == null or grid == null or grid.width <= 0 or grid.height <= 0:
		return
	var c0: Vector3 = grid.grid_to_world(Vector2i(0, 0))
	var c1: Vector3 = grid.grid_to_world(Vector2i(grid.width - 1, grid.height - 1))
	var pad := inset - extra
	var mn := Vector3(minf(c0.x, c1.x) + pad, 0.0, minf(c0.z, c1.z) + pad)
	var mx := Vector3(maxf(c0.x, c1.x) - pad, 0.0, maxf(c0.z, c1.z) - pad)
	if mn.x > mx.x or mn.z > mx.z:   # inset too large for a tiny level — fall back to the raw extent
		mn = Vector3(minf(c0.x, c1.x), 0.0, minf(c0.z, c1.z))
		mx = Vector3(maxf(c0.x, c1.x), 0.0, maxf(c0.z, c1.z))
	if _camera.has_method("set_look_bounds"):
		_camera.set_look_bounds(mn, mx)

func _register_gs_character(id: String, node: Node3D, speed: float = 3.0, stats: Dictionary = {}) -> void:
	_game_state.register_character(id, node.position, speed, stats)
	node.game_state = _game_state
	node.char_id = id
	if node.has_method("set_scheduler"):
		node.call("set_scheduler", _scheduler)
	if node == _player and node.has_method("bind_interaction_root"):
		node.call("bind_interaction_root", self)

## Resolve a character SPAWN from an authored marker, snapped onto a valid grounded cell. The marker
## is found anywhere in the scene tree (so markers parented under the room model work, not just under
## ScenePlacement); its position is then routed through grid.nearest_walkable_world so an authored spot
## that grazes a wall / sits off the floor still lands on a stand-able, path-able cell. `fallback` is
## the desired position when the marker isn't found (also snapped). Use this for EVERY character spawn.
func _spawn_at_marker(grid: GridWorld, marker_name: String, fallback: Vector3) -> Vector3:
	var marker := find_child(marker_name, true, false) as Node3D
	var desired: Vector3 = marker.global_position if marker != null else fallback
	if grid != null:
		return grid.nearest_walkable_world(desired)
	return desired

# --- Multi-level scene authoring (stacked floors + ladders/ramps) ---
#
# A scene that stacks floors declares them on the shared grid, then moves characters
# across floors with the cooperative cross-level pathfinder. These thin helpers wrap the
# GridWorld/GameState API so a sequence never reaches into the grid internals directly —
# keep new floor-based scenes on these, not on bespoke per-scene position math.

## A fullscreen SCREEN EFFECT (canvas_item shader) for a scene's look — e.g. the chromatic
## aberration both sim rooms use. Mounted on its own CanvasLayer UNDER the HUD; purely cosmetic.
func _add_screen_effect(effect_name: String, shader: Shader, params: Dictionary = {}) -> ColorRect:
	var layer := SCREEN_EFFECT_SCENE.instantiate() as CanvasLayer
	layer.name = effect_name + "Layer"
	layer.layer = 0
	add_child(layer)
	var rect := layer.get_node("ScreenEffect") as ColorRect
	rect.name = effect_name
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for key in params:
		mat.set_shader_parameter(key, params[key])
	rect.material = mat
	return rect

## ONE KNOB for modeled scenes (Blockbench/Crocotile/Blender): the visible floor's top surface
## sits above world y=0 by the model's floor thickness. Setting it lifts the whole DATA PLANE —
## grid origin (so grid_to_world / data positions ride the visible floor), the click-raycast
## floor body (GridRenderer positions from grid.origin), the hover grid, path ribbons, and
## spawn heights all follow. Call right after the grid is built, before the renderer.
func _set_floor_surface(grid: GridWorld, height: float) -> void:
	if grid != null:
		grid.origin.y = height

## Declare how many stacked floors the grid has (and the world Y between them). Level 0 sits at
## the grid origin Y; each higher floor is `height` above the last. Call once during scene build.
func _configure_levels(count: int, height: float = 4.0) -> void:
	if _game_state == null or _game_state.grid == null:
		return
	_game_state.grid.set_level_count(count)
	_game_state.grid.level_height = height

## Place a ladder at a cell linking two adjacent floors (climb — costs more than a flat step).
func _add_ladder(cell: Vector2i, from_level: int, to_level: int) -> void:
	if _game_state and _game_state.grid:
		_game_state.grid.add_inter_level_link(cell, from_level, to_level, "ladder")

## Place a ramp at a cell linking two adjacent floors (walk — cheaper than a ladder).
func _add_ramp(cell: Vector2i, from_level: int, to_level: int) -> void:
	if _game_state and _game_state.grid:
		_game_state.grid.add_inter_level_link(cell, from_level, to_level, "ramp")

## Move a character to a cell on a (possibly different) floor, routing over ladders/ramps. Returns
## false if no route exists between the floors. Same floor → an ordinary cooperative move.
func _move_to_cell_on_level(id: String, cell: Vector2i, level: int) -> bool:
	if _game_state == null:
		return false
	return _game_state.command_move_cross_level(id, cell, level)

## Declare a level's walkable FOOTPRINT as a world-space XZ rectangle. Stacked floors usually have
## different shapes (one deck's floor is another deck's void), so a level is walkable only inside the
## regions you declare. Additive — call once per region. A level with NO declared region stays fully
## walkable (the single-floor default). Pass world min/max corners on the X and Z axes.
func _add_level_walkable_region(level: int, min_xz: Vector2, max_xz: Vector2) -> void:
	if _game_state and _game_state.grid:
		_game_state.grid.allow_world_region_on_level(min_xz, max_xz, level)

## Hand the gameplay scheduler to every interactable built before the scheduler
## existed (the scene tree is assembled in _build_scene, _scheduler after). Their
## dwell timers then ride the scheduler and pause with gameplay.
func _inject_scheduler_into_interactables(node: Node) -> void:
	if node is Interactable and node.has_method("set_scheduler"):
		node.call("set_scheduler", _scheduler)
		if node.has_method("set_movement_authority"):
			node.call("set_movement_authority", _game_state)
	# Pushables: a PushTarget's queue request routes to the player's queued-push mode (signal
	# plumbing only — the target consumes its own click).
	if node.has_signal("push_queue_requested") and not node.push_queue_requested.is_connected(_on_push_queue_requested):
		node.push_queue_requested.connect(_on_push_queue_requested)
	for child in node.get_children():
		_inject_scheduler_into_interactables(child)

func _on_push_queue_requested(obj_id: String) -> void:
	if _player != null and _player.has_method("queue_push"):
		_player.call("queue_push", obj_id)

## The ONE party-control invariant, shared by every scene that lets the player select characters:
## the current selection is always the GameState party, while the ACTIVE character's node is the
## only move-enabled one and (in group control) the only group_move driver. Sequences pass their
## node map — the lookup is scene-specific, the wiring must not be.
func _apply_party_control(nodes: Dictionary, selected_ids: Array, active_id: String, group_control: bool) -> void:
	if _game_state != null:
		var synchronized_party: Array = selected_ids.duplicate()
		# Selection handlers normally keep one active member selected. Keep the
		# authoritative party usable during transient empty-selection handoffs too.
		if synchronized_party.is_empty() and active_id != "":
			synchronized_party.append(active_id)
		if _game_state.get_party() != synchronized_party:
			_game_state.set_party(synchronized_party)
	for cid in nodes.keys():
		var node = nodes[cid]
		if node == null:
			continue
		var is_active: bool = str(cid) == active_id
		if node.has_method("set_move_enabled"):
			node.call("set_move_enabled", is_active)
		if "group_move" in node:
			node.set("group_move", group_control and is_active)

## Reveal-all overlay handler: while the player holds the highlight action (SHIFT), every
## interactable in the scene shows its label so the player can see what's interactable. A scene
## that builds a HUD wires it with `_hud.highlight_held.connect(_on_highlight_held)`. Input flows
## key → HUD signal → here (no raw key polling in the sequence — keeps input discipline green).
func _on_highlight_held(active: bool) -> void:
	_set_all_interactables_highlighted(self, active)

func _set_all_interactables_highlighted(node: Node, active: bool) -> void:
	# Both Interactable (footprint-particle highlight) and OutlineSurfaceTarget (mesh outline
	# shader + surface particles) expose set_highlight — reveal whichever the node is.
	if node.has_method("set_highlight"):
		node.call("set_highlight", active)
	for child in node.get_children():
		_set_all_interactables_highlighted(child, active)

# --- Hover-to-identify (Aster's data overlay) ---
#
# While the data overlay is active, hovering an interactable surfaces the object's NAME (a cyan
# scan readout). The overlay turning on/off flips a flag on every interactable; the per-interactable
# hover then shows/hides the readout. Reusable: any sequence running "data" perception gets it free.

## True when Aster's data overlay is live (mode == "data" and, where gated like the elevator, the
## perception quad is actually visible).
func _data_overlay_active() -> bool:
	return _perception_mode == "data" and (_perception_quad == null or _perception_quad.visible)

## Flip hover-to-identify on every interactable when the overlay state changes (cheap: only on edge).
func _update_data_identify() -> void:
	var active := _data_overlay_active()
	if active == _data_identify_active:
		return
	_data_identify_active = active
	_set_all_data_identify(self, active)

func _set_all_data_identify(node: Node, active: bool) -> void:
	if node.has_method("set_data_identify"):
		node.call("set_data_identify", active)
	for child in node.get_children():
		_set_all_data_identify(child, active)

# --- Exploration helpers ---

func _create_interactable(
		parent: Node3D,
		pos: Vector3,
		interactable_name: String,
		radius: float = 1.5,
		dwell: float = 1.0,
		label: String = "",
		one_shot: bool = true,
		interactable_type: int = Interactable.InteractableType.HOLD_ACTION,
		interactable_id: String = ""
	) -> Area3D:
	# Register the interactable in the data layer and spawn a view bound to it.
	var spec := {
		"position": pos,
		"radius": radius,
		"hold_time": dwell,
		"one_shot": one_shot,
		"requires_hold": interactable_type == Interactable.InteractableType.HOLD_ACTION,
		"tutorial_label": label,
	}
	if interactable_id != "":
		spec["catalog_id"] = interactable_id
	var area := InteractableFactory.spawn(
		_game_state, parent, interactable_name, spec,
		_scheduler, _dialogue, _current_interaction_character()) as Area3D
	area.set("outline_highlight_radius", radius)
	_connect_interactable_outline_feedback(area)
	# Inherit the current data-overlay identify state (interactables spawned after it turned on).
	if _data_identify_active and area.has_method("set_data_identify"):
		area.call("set_data_identify", true)
	return area

func _connect_interactable_outline_feedback(source: Node) -> void:
	_connect_outline_feedback_source(source)

func _connect_outline_feedback_sources(root: Node) -> void:
	_connect_outline_feedback_source(root)
	for child in root.get_children():
		_connect_outline_feedback_sources(child)

func _connect_outline_feedback_source(source: Node) -> void:
	if source == null:
		return
	if source.has_signal("interaction_rejected") and not source.is_connected("interaction_rejected", _on_interaction_rejected):
		source.connect("interaction_rejected", _on_interaction_rejected)
	if _outline_feedback_manager != null:
		_outline_feedback_manager.call("bind_target", source)
		_outline_feedback_manager.call("bind_interaction_controller", source)
		return
	if source.has_signal("outline_hovered") and not source.is_connected("outline_hovered", _on_interactable_outline_hovered):
		source.connect("outline_hovered", _on_interactable_outline_hovered)
	if source.has_signal("outline_unhovered") and not source.is_connected("outline_unhovered", _on_interactable_outline_unhovered):
		source.connect("outline_unhovered", _on_interactable_outline_unhovered)
	if source.has_signal("outline_selected") and not source.is_connected("outline_selected", _on_interactable_outline_selected):
		source.connect("outline_selected", _on_interactable_outline_selected)

func _on_interactable_outline_hovered(interactable: Node) -> void:
	if not (interactable is Node3D):
		return
	_outline_hover_source = interactable as Node3D
	_outline_hover_color = _read_interactable_color(interactable, "hover_outline_color", Color.WHITE)
	_outline_hover_radius = _read_interactable_outline_radius(interactable)
	_outline_hover_extents = _read_interactable_outline_extents(interactable)
	_sync_outline_highlights()

func _on_interactable_outline_unhovered(interactable: Node) -> void:
	if _outline_hover_source == interactable:
		_outline_hover_source = null
		_sync_outline_highlights()

func _on_interactable_outline_selected(interactable: Node) -> void:
	if not (interactable is Node3D):
		return
	_outline_selected_source = interactable as Node3D
	_outline_selected_color = _read_interactable_color(interactable, "selected_feedback_color", Color(1.0, 0.62, 0.12, 1.0))
	_outline_selected_radius = _read_interactable_outline_radius(interactable)
	_outline_selected_extents = _read_interactable_outline_extents(interactable)
	_sync_outline_highlights()
	_outline_selection_token += 1
	var token := _outline_selection_token
	var duration := _read_interactable_float(interactable, "selected_feedback_duration", 0.7)
	# node-bound tween, not a SceneTree timer: dies with the sequence instead of firing a
	# freed-capture lambda after scene teardown
	var expire := create_tween()
	expire.tween_interval(maxf(0.05, duration))
	expire.tween_callback(func():
		if token == _outline_selection_token:
			_outline_selected_source = null
			_sync_outline_highlights())

func _read_interactable_color(interactable: Node, property_name: String, fallback: Color) -> Color:
	var value = interactable.get(property_name)
	if value is Color:
		return value
	return fallback

func _read_interactable_float(interactable: Node, property_name: String, fallback: float) -> float:
	var value = interactable.get(property_name)
	if value == null:
		return fallback
	return float(value)

func _read_interactable_outline_radius(interactable: Node) -> float:
	if interactable.has_method("get_outline_highlight_radius"):
		return float(interactable.call("get_outline_highlight_radius"))
	var radius := _read_interactable_float(interactable, "outline_highlight_radius", 0.0)
	if radius <= 0.0:
		radius = _read_interactable_float(interactable, "interaction_radius", 2.0)
	return maxf(0.25, radius)

func _read_interactable_outline_extents(interactable: Node) -> Vector3:
	if interactable.has_method("get_outline_highlight_extents"):
		var method_value = interactable.call("get_outline_highlight_extents")
		if method_value is Vector3:
			return method_value
	var value = interactable.get("outline_highlight_extents")
	if value is Vector3:
		return value
	return Vector3.ZERO

func _current_interaction_character() -> String:
	if _player == null:
		return ""
	var char_id = _player.get("char_id")
	return str(char_id) if char_id != null else ""

# --- Object outlines (hover/selected edge outline + surface-emitted particles) ---
# The building lives in the shared OutlineFeedbackManager so chunks and gameplay get
# the same path; these stay as thin scene-facing wrappers over that system.

## The outline system for this scene's branch (find-or-create), cached.
func _outline_system() -> OutlineFeedbackManager:
	if (_outline_feedback_manager == null or not is_instance_valid(_outline_feedback_manager)) and not Engine.is_editor_hint():
		_outline_feedback_manager = OutlineFeedbackManager.ensure(self)
	return _outline_feedback_manager

## Wrap a set of visual meshes in an OutlineSurfaceTarget so the object gets a
## hover/selected edge outline + surface-emitted particles, bound to the outline
## feedback system. Returns the target, or null in the editor / with no meshes.
func _create_outline_target(
		parent: Node3D,
		target_name: String,
		center: Vector3,
		size: Vector3,
		meshes: Array,
		element_id: String,
		radius: float = 1.0
	) -> Node3D:
	var system := _outline_system()
	if system == null:
		return null
	return system.create_outline_target(parent, target_name, center, size, meshes, element_id, radius)

## Like _create_outline_target but derives the enclosing box from the meshes' own
## world bounds, so callers don't hand-tune a size. Returns null if no usable mesh.
func _outline_object_meshes(
		parent: Node3D,
		target_name: String,
		meshes: Array,
		element_id: String,
		radius: float = 1.0,
		padding: float = 0.12
	) -> Node3D:
	var system := _outline_system()
	if system == null:
		return null
	return system.outline_meshes(parent, target_name, meshes, element_id, radius, {}, padding)

## World-space AABB enclosing every MeshInstance3D in `meshes` (empty if none).
func _combined_world_bounds(meshes: Array) -> AABB:
	return OutlineFeedbackManager.combined_world_bounds(meshes)

## Gather every MeshInstance3D at or under `node` (objects often nest their meshes).
func _collect_mesh_instances(node: Node) -> Array:
	return OutlineFeedbackManager.collect_mesh_instances(node)

## Route an outline target's interaction to a paired zone/interactable, so clicking
## the outlined object runs the same inspection as walking up to it.
func _set_room_target_interaction_delegate(target: Node, delegate: Node) -> void:
	if target != null and delegate != null and target.has_method("set_interaction_delegate"):
		target.call("set_interaction_delegate", delegate)
	# Reverse link: the interactable intercepts the hover ray (it's pickable for clicks), so on
	# hover / SHIFT it lights up ITS object's outline+particle target rather than a stray ring.
	if target != null and delegate != null and delegate.has_method("set_outline_target"):
		delegate.call("set_outline_target", target)

## Create a click-to-inspect zone for spoken/object text.
func _make_exploration_zone(
		parent: Node3D,
		pos: Vector3,
		zone_name: String,
		line_key: String,
		radius: float = 1.5,
		dwell: float = 0.6,
		label: String = "",
		re_interactable: bool = true
	) -> Area3D:
	# Exploration inspectables are RE-INTERACTABLE by default: re-inspecting replays the line instead of
	# going silent (the same re-read affordance as Aster's monitor). Pass re_interactable=false for a
	# one-time-only beat. The tutorial.inspection catalog forces one_shot=true, so (like the sequence zone)
	# override it on the node after spawn.
	var scaled_radius := maxf(radius * EXPLORATION_RADIUS_SCALE, EXPLORATION_MIN_RADIUS)
	var area := _create_interactable(parent, pos, zone_name, scaled_radius, dwell, label, true,
		Interactable.InteractableType.INSPECTION, "tutorial.inspection")
	if re_interactable:
		area.set("one_shot", false)
	if line_key != "":
		area.connect("interacted", func(): _play_exploration_beat(line_key, area))
	if label != "":
		area.call_deferred("show_tutorial_label")
	return area

## Create a reusable inspection zone that advances through lines on repeated clicks.
func _make_exploration_sequence_zone(
		parent: Node3D,
		pos: Vector3,
		zone_name: String,
		line_keys: Array,
		radius: float = 1.5,
		dwell: float = 0.6,
		label: String = ""
	) -> Area3D:
	var scaled_radius := maxf(radius * EXPLORATION_RADIUS_SCALE, EXPLORATION_MIN_RADIUS)
	var area := _create_interactable(parent, pos, zone_name, scaled_radius, dwell, label, false,
		Interactable.InteractableType.INSPECTION, "tutorial.inspection")
	area.set("one_shot", false)
	area.set("interactable_type", Interactable.InteractableType.INSPECTION)
	var cleaned_keys := []
	for key in line_keys:
		var key_string := str(key)
		if key_string != "":
			cleaned_keys.append(key_string)
	area.set_meta("exploration_dialogue_keys", cleaned_keys)
	area.set_meta("exploration_dialogue_index", 0)
	if not cleaned_keys.is_empty():
		area.connect("interacted", func(): _play_next_exploration_sequence_beat(area))
	if label != "":
		area.call_deferred("show_tutorial_label")
	return area

func _play_next_exploration_sequence_beat(area: Node3D) -> void:
	if area == null:
		return
	var raw_keys = area.get_meta("exploration_dialogue_keys", [])
	if not (raw_keys is Array):
		return
	var keys: Array = raw_keys
	if keys.is_empty():
		return
	var index := int(area.get_meta("exploration_dialogue_index", 0))
	var clamped_index := mini(maxi(index, 0), keys.size() - 1)
	var line_key := str(keys[clamped_index])
	area.set_meta("exploration_dialogue_index", mini(clamped_index + 1, keys.size() - 1))
	_play_exploration_beat(line_key, area)

func _play_exploration_beat(line_key: String, focus_node: Node3D = null) -> void:
	var keys := []
	if line_key != "":
		keys.append(line_key)
	_play_focused_dialogue_keys(keys, focus_node)

func _play_focused_dialogue_keys(keys: Array, focus_node: Node3D = null) -> void:
	if _dialogue == null:
		return
	if focus_node != null:
		_begin_exploration_focus(focus_node)
	var queued_dialogue := false
	for key in keys:
		var key_string := str(key)
		if key_string == "":
			continue
		DialogueData.say_to(_dialogue, key_string)
		queued_dialogue = true
	if focus_node != null:
		if queued_dialogue:
			_dialogue.dialogue_finished.connect(_finish_exploration_focus, CONNECT_ONE_SHOT)
		else:
			_finish_exploration_focus()

func _begin_exploration_focus(focus_node: Node3D) -> void:
	if _exploration_focus_active:
		return
	_exploration_focus_active = true
	_exploration_focus_prev_scheduler_paused = _scheduler != null and _scheduler.is_paused()
	if _scheduler != null and not _exploration_focus_prev_scheduler_paused:
		_scheduler.pause()
	if _player != null and _player.has_method("set_move_enabled"):
		_exploration_focus_prev_move_enabled = bool(_player.get("_move_enabled")) if "_move_enabled" in _player else true
		_player.set_move_enabled(false)
	if _camera != null:
		_exploration_focus_prev_camera_offset = _camera.follow_offset
		_exploration_focus_prev_camera_target = _camera.target
		_exploration_focus_prev_camera_state = _camera.capture_view_state() \
			if _camera.has_method("capture_view_state") else {}
		_camera.follow_offset = EXPLORATION_FOCUS_OFFSET
		_camera.lock_to(_exploration_focus_point(focus_node))

func _finish_exploration_focus() -> void:
	if not _exploration_focus_active:
		return
	if _camera != null:
		if not _exploration_focus_prev_camera_state.is_empty() and _camera.has_method("restore_view_state"):
			_camera.restore_view_state(_exploration_focus_prev_camera_state)
		else:
			_camera.follow_offset = _exploration_focus_prev_camera_offset
			_camera.target = _exploration_focus_prev_camera_target
			_camera.unlock()
	_exploration_focus_prev_camera_state.clear()
	if _player != null and _player.has_method("set_move_enabled"):
		_player.set_move_enabled(_exploration_focus_prev_move_enabled)
	if _scheduler != null and not _exploration_focus_prev_scheduler_paused:
		_scheduler.resume()
	_exploration_focus_active = false

func _exploration_focus_point(focus_node: Node3D) -> Vector3:
	return focus_node.global_position + Vector3(0, EXPLORATION_FOCUS_HEIGHT, 0)

# --- Fade helpers ---

func _fade_from(color: Color, duration: float, next_func: Callable, next_tag: String) -> void:
	_fade_rect.color = color
	_fade_start_tick = _scheduler.get_current_tick()
	_scheduler.schedule_after(duration, next_func, next_tag)

func _update_fade_in(duration: float = 2.0) -> void:
	var elapsed := _scheduler.get_current_tick() - _fade_start_tick
	_fade_rect.color.a = 1.0 - clampf(elapsed / duration, 0.0, 1.0)

func _update_fade_out(target_color: Color, duration: float = 2.0) -> void:
	var elapsed := _scheduler.get_current_tick() - _fade_start_tick
	var alpha := clampf(elapsed / duration, 0.0, 1.0)
	_fade_rect.color = Color(target_color.r, target_color.g, target_color.b, alpha)

# --- Thought helpers ---

## Walking the wrong character onto a required-character interactable says who is needed.
## The feedback line is optional content: when the dialogue table has no entry for it,
## the rejection stays silent rather than surfacing a placeholder thought.
func _on_interaction_rejected(_interactable: Node, required_character: String) -> void:
	if not DialogueData.has_key("system.interact.wrong_character"):
		return
	var line := DialogueData.text("system.interact.wrong_character")
	if line == "":
		return
	_show_thought(line.replace("{name}", required_character.capitalize()))

func _show_thought(text: String) -> void:
	# Dialogue takes priority: don't stack an ambient thought over a live line.
	if _dialogue != null and _dialogue.has_method("is_active") and _dialogue.is_active():
		return
	_thought_label.text = text
	_start_thought_fade(0.7, 0.5)

func _hide_thought() -> void:
	_start_thought_fade(0.0, 0.5)

func _start_thought_fade(target_alpha: float, duration: float) -> void:
	if _thought_label == null:
		return
	# Thoughts ride the UI lane, so they fade smoothly even while gameplay is paused.
	if _ui_scheduler == null or duration <= 0.0 or _ui_scheduler.get_speed() <= 0.0:
		_thought_label.modulate.a = target_alpha
		_thought_fade_active = false
		return
	_thought_fade_from_alpha = _thought_label.modulate.a
	_thought_fade_to_alpha = target_alpha
	_thought_fade_duration = duration
	_thought_fade_start_tick = _ui_scheduler.get_current_tick()
	_thought_fade_active = true
	_update_thought_fade()

func _update_thought_fade() -> void:
	if not _thought_fade_active or _thought_label == null or _ui_scheduler == null:
		return
	var elapsed := _ui_scheduler.get_current_tick() - _thought_fade_start_tick
	var t := clampf(elapsed / maxf(_thought_fade_duration, 0.001), 0.0, 1.0)
	_thought_label.modulate.a = lerpf(_thought_fade_from_alpha, _thought_fade_to_alpha, t)
	if t >= 1.0:
		_thought_fade_active = false

# --- Step transition ---

## Enter a step once and clear stale dialogue callbacks.
func _enter_step(step_name: String) -> bool:
	if _current_step == step_name:
		return false
	var previous_step := _current_step
	_current_step = step_name
	var beat_id := StringName(step_name)
	if _story_beat_runner.has_beat(beat_id):
		if not _story_beat_runner.transition_to(beat_id):
			push_error("Story beat '%s' rejected its context." % step_name)
			_current_step = previous_step
			return false
	else:
		_story_beat_runner.deactivate(&"step_changed")
	if _dialogue:
		for conn in _dialogue.dialogue_finished.get_connections():
			_dialogue.dialogue_finished.disconnect(conn.callable)
	return true

# --- Dialogue chain ---

## Play dialogue keys in order, then call next_func.
func _dialogue_chain(keys: Array, next_func: Callable, delay_between := 0.0) -> void:
	_dlg_chain_keys = keys
	_dlg_chain_index = 0
	_dlg_chain_next = next_func
	_dlg_chain_delay = delay_between
	_dlg_chain_play_next()

func _dlg_chain_play_next() -> void:
	if _dlg_chain_index >= _dlg_chain_keys.size():
		if _dlg_chain_next.is_valid():
			_scheduler.schedule_after(0.0, _dlg_chain_next, "dlg_chain_complete")
		return
	var key: String = _dlg_chain_keys[_dlg_chain_index]
	_dlg_chain_index += 1
	DialogueData.say_to(_dialogue, key)
	# The dialogue box owns UI timing; only stateful follow-ups enter the scheduler.
	_dialogue.dialogue_finished.connect(func():
		if _dlg_chain_delay > 0.0 and _dlg_chain_index < _dlg_chain_keys.size():
			_scheduler.schedule_after(_dlg_chain_delay, _dlg_chain_play_next, "dlg_chain")
		else:
			_dlg_chain_play_next()
	, CONNECT_ONE_SHOT)

# --- Chunk Management ---

var _chunks: Dictionary = {}

## Exposed to hosted chunks so their interactables register with the same data
## layer the rest of the game uses (SceneChunk reads these through `host`).
func get_preview_game_state() -> GameState:
	return _game_state

func get_preview_scheduler() -> EventScheduler:
	return _scheduler

# --- Shared chunk-host interface ---
#
# A SceneChunk drives everything through the `*_preview_*` host methods (see
# scene_chunk.gd). These GENERIC implementations map each one to the systems every host
# already has — _game_state (positions / stats / movement / inventory), _dialogue, and
# _scheduler — so a chunk loaded into ANY tutorial scene (act1, the elevator, …) behaves
# like it does in the fragment preview, not silently no-op. The preview host overrides a
# subset (the ones with preview-only UI side effects: messages, notes, the overlay panel,
# the inventory mirror). Everything here null-guards the optional systems so a host without
# them (the editor, a HUD-less scene) stays safe. Status / visibility are HUD-presentation
# state (GameState has no status field), so they live on this small base mirror and push to
# the scene's "GameHUD" node when one exists.

## sta -> stamina: chunks speak the HUD's "sta"; GameState's stat is "stamina".
const _CHUNK_STAT_ALIASES := {"sta": "stamina", "health": "hp", "stamina": "stamina"}

var _chunk_char_status: Dictionary = {}

func _chunk_stat_key(stat_name: String) -> String:
	var key := stat_name.strip_edges().to_lower()
	return str(_CHUNK_STAT_ALIASES.get(key, key))

## The scene's HUD (every scene names it "GameHUD"); null for HUD-less scenes (tag_day).
func _chunk_host_hud() -> Node:
	return get_node_or_null("GameHUD")

func get_preview_dialogue_box() -> Node:
	return _dialogue

func get_preview_engram_overlay() -> Node:
	return _engram_overlay

func get_preview_scheduler_tick() -> float:
	return _scheduler.get_current_tick() if _scheduler != null else 0.0

func get_preview_active_character() -> String:
	# The move-enabled / camera-followed character is the one a chunk should service.
	if _player != null:
		var pid = _player.get("char_id")
		if pid != null and str(pid) != "":
			return str(pid)
	return ""

func get_preview_character_position(char_id: String) -> Vector3:
	if _game_state != null and _game_state.characters.has(char_id):
		return _game_state.get_position(char_id)
	var node := _find_character_node(char_id)
	return node.global_position if node != null else Vector3.ZERO

func set_preview_character_position(char_id: String, pos: Vector3) -> void:
	if _game_state != null and _game_state.characters.has(char_id):
		_game_state.command_stop(char_id)
		_game_state.characters[char_id]["position"] = pos
		if _game_state.grid != null:
			_game_state.characters[char_id]["grid_cell"] = _game_state.grid.world_to_grid(pos)
	var node := _find_character_node(char_id)
	if node != null:
		node.global_position = pos

func get_preview_character_move_speed(char_id: String, running := false) -> float:
	var node := _find_character_node(char_id)
	if running and node != null:
		var run_speed = node.get("run_speed")
		if run_speed != null:
			return float(run_speed)
	if _game_state != null and _game_state.characters.has(char_id):
		return float(_game_state.characters[char_id].get("move_speed", 3.0))
	return 3.0

func get_preview_character_stat(char_id: String, stat_name: String) -> float:
	if _game_state == null:
		return 0.0
	return _game_state.get_stat(char_id, _chunk_stat_key(stat_name))

func set_preview_character_stat(char_id: String, stat_name: String, value: float) -> void:
	if _game_state == null or not _game_state.characters.has(char_id):
		return
	_game_state.set_stat(char_id, _chunk_stat_key(stat_name), value)
	_sync_chunk_portrait(char_id)

func adjust_preview_character_stat(char_id: String, stat_name: String, delta: float) -> void:
	if _game_state == null or not _game_state.characters.has(char_id):
		return
	_game_state.adjust_stat(char_id, _chunk_stat_key(stat_name), delta)
	_sync_chunk_portrait(char_id)

func set_preview_character_status(char_id: String, status: String) -> void:
	_chunk_char_status[char_id] = status
	var hud := _chunk_host_hud()
	if hud != null and hud.has_method("set_portrait_status"):
		hud.call("set_portrait_status", char_id, status)

func set_preview_character_visible(char_id: String, visible: bool) -> void:
	var node := _find_character_node(char_id)
	if node != null:
		node.visible = visible
		if not visible and node.has_method("set_move_enabled"):
			node.call("set_move_enabled", false)

## Push a character's live GameState stats to its HUD portrait (no-op when HUD-less).
func _sync_chunk_portrait(char_id: String) -> void:
	var hud := _chunk_host_hud()
	if hud == null or _game_state == null or not _game_state.characters.has(char_id):
		return
	if hud.has_method("set_portrait_stat"):
		hud.call("set_portrait_stat", char_id, "hp", _game_state.get_stat(char_id, "hp"))
		hud.call("set_portrait_stat", char_id, "sta", _game_state.get_stat(char_id, "stamina"))
		hud.call("set_portrait_stat", char_id, "atp", _game_state.get_stat(char_id, "atp"))

func show_preview_message(text: String, duration := 2.0) -> void:
	var hud := _chunk_host_hud()
	if hud != null and hud.has_method("show_message"):
		hud.call("show_message", text, duration)

func show_preview_note(text: String, duration := 3.0) -> void:
	# No dedicated note band on the base HUD; surface it as a transient thought/message.
	if _tutorial_prompt != null and _tutorial_prompt.has_method("show_prompt"):
		_tutorial_prompt.show_prompt(text, duration)
	else:
		show_preview_message(text, duration)

func set_preview_step(step: String) -> void:
	_current_step = step

func set_preview_ability_state(_ability_id: String, _state: String, _remaining := 0.0) -> void:
	# Ability cooldown bookkeeping is preview-UI state; the base scene drives abilities itself.
	pass

func get_preview_routing_mode() -> String:
	if "_routing_mode" in self:
		return str(get("_routing_mode"))
	return "safe"

# --- Inventory / items (route through GameState; draw a minimal world view) ---

var _chunk_item_nodes: Dictionary = {}

func spawn_preview_item(item_type: String, position: Vector3, properties: Dictionary = {}) -> String:
	if _game_state == null:
		return ""
	var item_id := _game_state.spawn_item(item_type, position, properties)
	_ensure_chunk_item_node(item_id)
	return item_id

func remove_preview_item(item_id: String) -> void:
	if _game_state == null:
		return
	_game_state.remove_item(item_id)
	if _chunk_item_nodes.has(item_id):
		var node: Node3D = _chunk_item_nodes[item_id]
		if is_instance_valid(node):
			node.queue_free()
		_chunk_item_nodes.erase(item_id)

func pick_up_preview_item(char_id: String, item_id: String) -> bool:
	return _game_state != null and _game_state.pick_up_item(char_id, item_id)

func drop_preview_item(char_id: String, item_id: String) -> bool:
	return _game_state != null and _game_state.drop_item(char_id, item_id)

func transfer_preview_item(from_id: String, to_id: String, item_id: String) -> bool:
	return _game_state != null and _game_state.transfer_item(from_id, to_id, item_id)

func endocytose_preview_item(char_id: String, item_id: String) -> bool:
	return _game_state != null and _game_state.endocytose_item(char_id, item_id)

func exocytose_preview_item(char_id: String, item_id: String) -> bool:
	return _game_state != null and _game_state.exocytose_item(char_id, item_id)

func get_preview_hand_items(char_id: String) -> Array:
	return _game_state.get_hand_items(char_id) if _game_state != null else []

func get_preview_hand_slots(char_id: String) -> Array:
	return _game_state.get_hand_slots(char_id) if _game_state != null else []

func get_preview_internal_items(char_id: String) -> Array:
	return _game_state.get_internal_items(char_id) if _game_state != null else []

func get_preview_collection_items() -> Array:
	return _game_state.collection.duplicate() if _game_state != null else []

func get_preview_item_state(item_id: String) -> Dictionary:
	if _game_state == null or not _game_state.items.has(item_id):
		return {}
	return (_game_state.items[item_id] as Dictionary).duplicate(true)

func get_preview_item_display_name(item_id: String, char_id := "") -> String:
	if _game_state == null or not _game_state.items.has(item_id):
		return item_id
	var item: Dictionary = _game_state.items[item_id]
	var properties: Dictionary = item.get("properties", {})
	var display_names: Dictionary = properties.get("display_names_by_character", {})
	if char_id != "" and display_names.has(char_id):
		return str(display_names.get(char_id, item_id))
	if properties.has("display_name"):
		return str(properties.get("display_name", item_id))
	return ItemData.get_display_name(str(item.get("type", item_id)))

## A small ground/hand visual for a chunk-spawned item, so picking it up reads on screen.
func _ensure_chunk_item_node(item_id: String) -> void:
	if _chunk_item_nodes.has(item_id) or _game_state == null or not _game_state.items.has(item_id):
		return
	var item: Dictionary = _game_state.items[item_id]
	var properties: Dictionary = item.get("properties", {})
	var node := MeshInstance3D.new()
	node.name = "ChunkItem_%s" % item_id
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	node.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = properties.get("visual_color", Color(0.78, 0.78, 0.82))
	mat.emission_enabled = true
	mat.emission = (mat.albedo_color as Color).lightened(0.1)
	mat.emission_energy_multiplier = 0.24
	node.material_override = mat
	var pos: Vector3 = item.get("position", Vector3.ZERO)
	add_child(node)
	node.global_position = Vector3(pos.x, pos.y + 0.42, pos.z)
	_chunk_item_nodes[item_id] = node

## Register a chunk interactable with the scene's input/feedback wiring (the preview host's
## register_preview_interactable equivalent): give it the dialogue box + active character,
## inject the gameplay scheduler so dwell rides it, and bind hover/outline feedback so it
## highlights and fires exactly as the scene's own interactables do.
func register_preview_interactable(interactable: Node) -> void:
	if interactable == null:
		return
	if "dialogue_box" in interactable:
		interactable.dialogue_box = _dialogue
	if "active_character" in interactable:
		interactable.active_character = get_preview_active_character()
	if interactable.has_method("set_scheduler"):
		interactable.call("set_scheduler", _scheduler)
	if interactable.has_method("set_movement_authority"):
		interactable.call("set_movement_authority", _game_state)
	_connect_interactable_outline_feedback(interactable)
	if _player != null and _player.has_method("bind_interaction_target"):
		_player.call("bind_interaction_target", interactable)

# Create + register a chunk's ROOT node (PackedScene instance or an empty Node3D for a procedural chunk) and
# parent it under Environment — WITHOUT building the procedural body. `_load_chunk` and `stream_chunk` share this
# so the tree wiring stays identical whether a chunk is built in one shot or streamed across frames.
func _create_chunk_root(chunk_name: String) -> Node3D:
	var chunk_scene: PackedScene = _get_chunk_scene(chunk_name)
	var chunk: Node3D
	if chunk_scene != null:
		var instance: Node = chunk_scene.instantiate()
		if instance is Node3D:
			chunk = instance as Node3D
			if chunk.has_method("attach_chunk_host"):
				chunk.call("attach_chunk_host", self, chunk_name)
			if has_method("_configure_loaded_chunk"):
				call("_configure_loaded_chunk", chunk, chunk_name)
		else:
			push_warning("Chunk scene for %s did not instantiate a Node3D" % chunk_name)
	if chunk == null:
		chunk = Node3D.new()
	chunk.name = "Chunk_" + chunk_name
	var env := find_child("Environment", false, false)
	if env:
		env.add_child(chunk)
	else:
		add_child(chunk)
	_chunks[chunk_name] = chunk
	return chunk

func _load_chunk(chunk_name: String) -> Node3D:
	# A background stream may have created the root but not finished building it — finish + reveal it now so a
	# _load_chunk caller always gets a COMPLETE, visible chunk (never a half-streamed hidden one).
	if _chunk_streams.has(chunk_name):
		return reveal_chunk(chunk_name)
	if _chunks.has(chunk_name):
		return _chunks[chunk_name]
	var chunk := _create_chunk_root(chunk_name)
	if _get_chunk_scene(chunk_name) == null:
		_build_chunk(chunk_name, chunk)
	return chunk

func _unload_chunk(chunk_name: String) -> void:
	_chunk_streams.erase(chunk_name)
	if not _chunks.has(chunk_name):
		return
	var chunk: Node3D = _chunks[chunk_name]
	if is_instance_valid(chunk) and chunk.has_method("detach_chunk_host"):
		chunk.call("detach_chunk_host")
	chunk.queue_free()
	_chunks.erase(chunk_name)

# --- Reusable chunk STREAMING (prewarm + incremental build) --------------------------------------------------
# A chunk built the instant it's needed hitches on that frame (a GLB instantiate + a level's worth of nodes). The
# streamer builds it AHEAD of time, spread across frames into a HIDDEN root, so revealing it later costs only a
# `visible = true`. A procedural chunk opts in by returning batched build Callables from `_chunk_build_steps`;
# without them it builds in one shot during the (quiet) prewarm. Correctness never depends on streaming timing —
# `reveal_chunk` finishes any remaining steps synchronously before the chunk is used, so it's purely cosmetic
# smoothing and stays replay/headless-safe (headless simply reveals, which block-finishes).
var _chunk_streams := {}   # chunk_name -> {chunk: Node3D, steps: Array[Callable], i: int}
const _CHUNK_STREAM_STEPS_PER_FRAME := 1

## Begin building a chunk across frames, hidden, so a later reveal has no hitch. Idempotent; safe if the chunk is
## already loaded or streaming. Call it during a quiet moment (stationary dialogue) ahead of when it's revealed.
func stream_chunk(chunk_name: String) -> void:
	if _chunks.has(chunk_name) or _chunk_streams.has(chunk_name):
		return
	var chunk := _create_chunk_root(chunk_name)
	chunk.visible = false
	var steps: Array = []
	if _get_chunk_scene(chunk_name) == null:
		steps = _chunk_build_steps(chunk_name, chunk)
		if steps.is_empty():
			_build_chunk(chunk_name, chunk)   # one-shot prewarm (no batches provided)
	if not steps.is_empty():
		_chunk_streams[chunk_name] = {"chunk": chunk, "steps": steps, "i": 0}

## Advance in-progress streams a few build-steps per frame (cosmetic; correctness comes from reveal_chunk).
func _advance_chunk_streams() -> void:
	if _chunk_streams.is_empty():
		return
	for chunk_name in _chunk_streams.keys():
		var st: Dictionary = _chunk_streams[chunk_name]
		var steps: Array = st["steps"]
		var ran := 0
		while int(st["i"]) < steps.size() and ran < _CHUNK_STREAM_STEPS_PER_FRAME:
			(steps[int(st["i"])] as Callable).call()
			st["i"] = int(st["i"]) + 1
			ran += 1
		if int(st["i"]) >= steps.size():
			_chunk_streams.erase(chunk_name)

## Reveal a (possibly streamed) chunk: finish any remaining build synchronously, make it visible, return it.
## Falls back to a full synchronous load if the chunk was never streamed (so callers can always use it).
func reveal_chunk(chunk_name: String) -> Node3D:
	if _chunk_streams.has(chunk_name):
		var st: Dictionary = _chunk_streams[chunk_name]
		var steps: Array = st["steps"]
		while int(st["i"]) < steps.size():
			(steps[int(st["i"])] as Callable).call()
			st["i"] = int(st["i"]) + 1
		_chunk_streams.erase(chunk_name)
	var chunk: Node3D = _chunks.get(chunk_name)
	if chunk == null:
		chunk = _load_chunk(chunk_name)
	if chunk != null:
		chunk.visible = true
		_on_chunk_revealed(chunk_name, chunk)
	return chunk

## True while a chunk is still being built in the background (nothing revealed it yet).
func is_chunk_streaming(chunk_name: String) -> bool:
	return _chunk_streams.has(chunk_name)

## Subclass hook: break a procedural chunk's build into batched Callables (each builds a slice into `parent`),
## so the streamer can spread it across frames. Return [] to build the chunk in one shot. Only consulted for
## procedural (non-PackedScene) chunks; the synchronous `_build_chunk` must produce the SAME result as running
## every step in order (keep them in sync — a scene can implement one in terms of the other).
func _chunk_build_steps(_chunk_name: String, _parent: Node3D) -> Array:
	return []

## Subclass hook for work that must wait until a prewarmed chunk becomes playable. Keep this cheap: the
## expensive construction belongs in `_chunk_build_steps`; this is for lifecycle activation (AI, audio, etc.).
func _on_chunk_revealed(_chunk_name: String, _chunk: Node3D) -> void:
	pass

func _build_chunk(_chunk_name: String, _parent: Node3D) -> void:
	pass

func _configure_loaded_chunk(_chunk: Node3D, _chunk_name: String) -> void:
	pass

# --- Animation System ---

var _anim_player: AnimationPlayer
var _anim_lib: AnimationLibrary
var _scheduler_animation_states: Dictionary = {}

## Scheduler-driven playback for editor-authored AnimationPlayer clips.
func _register_scheduler_animation_player(player: AnimationPlayer) -> void:
	if player == null:
		return
	player.speed_scale = 0.0

func _create_animation(anim_name: String, length: float) -> Animation:
	if not _anim_player:
		_anim_player = SEQUENCE_ANIMATION_PLAYER_SCENE.instantiate() as AnimationPlayer
		add_child(_anim_player)
		_anim_lib = AnimationLibrary.new()
		_anim_player.add_animation_library("", _anim_lib)
		_register_scheduler_animation_player(_anim_player)
	var anim := Animation.new()
	anim.length = length
	_anim_lib.add_animation(anim_name, anim)
	return anim

func _play_animation(anim_name: String, finished := Callable()) -> void:
	if _anim_player and _anim_lib.has_animation(anim_name):
		_play_scheduler_animation(_anim_player, anim_name, finished)

func _play_scheduler_animation(
		player: AnimationPlayer,
		anim_name: String,
		finished := Callable(),
		from_start := true
	) -> void:
	if player == null or _scheduler == null or not player.has_animation(anim_name):
		return
	_register_scheduler_animation_player(player)
	var anim: Animation = player.get_animation(anim_name)
	var length := maxf(anim.length, 0.0)
	var start_tick := _scheduler.get_current_tick()
	if not from_start and player.current_animation == anim_name:
		start_tick -= player.current_animation_position
	var state := {
		"player": player,
		"animation": anim_name,
		"start_tick": start_tick,
		"length": length,
		"loop": anim.loop_mode != Animation.LOOP_NONE,
		"finished": finished,
	}
	_scheduler_animation_states[player.get_instance_id()] = state
	player.play(anim_name)
	player.speed_scale = 0.0
	_seek_scheduler_animation(player, anim_name, 0.0 if from_start else player.current_animation_position)

func _stop_animation(anim_name: String) -> void:
	if _anim_player and _anim_player.current_animation == anim_name:
		_scheduler_animation_states.erase(_anim_player.get_instance_id())
		_anim_player.stop()

func _has_animation(anim_name: String) -> bool:
	return _anim_lib != null and _anim_lib.has_animation(anim_name)

func _stop_scheduler_animation(player: AnimationPlayer) -> void:
	if player == null:
		return
	_scheduler_animation_states.erase(player.get_instance_id())
	player.stop()

func _sync_scheduler_animations() -> void:
	if _scheduler == null or _scheduler_animation_states.is_empty():
		return
	var now := _scheduler.get_current_tick()
	for key in _scheduler_animation_states.keys():
		var state: Dictionary = _scheduler_animation_states.get(key, {})
		var player: AnimationPlayer = state.get("player", null)
		var anim_name := str(state.get("animation", ""))
		if player == null or not is_instance_valid(player) or anim_name == "" or not player.has_animation(anim_name):
			_scheduler_animation_states.erase(key)
			continue
		var length := float(state.get("length", 0.0))
		var elapsed := maxf(0.0, now - float(state.get("start_tick", now)))
		var position := elapsed
		var done := false
		if bool(state.get("loop", false)) and length > 0.0:
			position = fposmod(elapsed, length)
		elif elapsed >= length:
			position = length
			done = true
		_seek_scheduler_animation(player, anim_name, position)
		if done:
			_scheduler_animation_states.erase(key)
			var cb: Callable = state.get("finished", Callable())
			if cb.is_valid():
				cb.call()

func _seek_scheduler_animation(player: AnimationPlayer, anim_name: String, position: float) -> void:
	if player.current_animation != anim_name:
		player.play(anim_name)
	player.speed_scale = 0.0
	player.seek(position, true)

# --- Environment helpers ---

func _add_corridor_section(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var b2 := BoxMesh.new()
	b2.size = size
	mesh.mesh = b2
	var mat2 := StandardMaterial3D.new()
	mat2.albedo_color = color
	mesh.material_override = mat2
	mesh.position = pos
	parent.add_child(mesh)

func _add_wall(parent: Node3D, pos: Vector3, size: Vector3, color := Color(0.12, 0.12, 0.15)) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
