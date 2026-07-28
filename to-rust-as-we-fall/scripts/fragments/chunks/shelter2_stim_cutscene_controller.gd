class_name Shelter2StimCutsceneController
extends RefCounted

## Deterministic presentation controller for the authored Shelter 2 Aster-stimming
## beat. The generated chunk owns the saved phase; this object owns only derived
## camera, input, dialogue, and AnimationPlayer presentation.

const CUTSCENE_SCENE := preload(
	"res://scenes/tutorial/shelter_2_aster_stim_cutscene.tscn"
)
const AUTHORITY_VERSION := 1
const PHASE_NOT_STARTED := "not_started"
const PHASE_PLAYING := "playing"
const PHASE_COMPLETE := "complete"
const STAGING_ANIMATION := "shelter_2_staging"
const STIM_ANIMATION := "aster_stim_loop"
const DIALOGUE_DELAY := 2.0
const STAGING_DURATION := 16.0
const DEADLINE_EPSILON := 0.000001
const PARTY_IDS: Array[String] = ["aster", "peris", "endo"]
const DIALOGUE_KEYS: Array[String] = [
	"channels.narration.shelter",
	"channels.endo.door",
	"channels.narration.recuperate",
]
const STATE_KEYS: Array[String] = [
	"version",
	"phase",
	"start_tick",
	"dialogue_start_tick",
	"animation_deadline",
	"dialogue_started",
	"dialogue_complete",
	"animation_complete",
	"completion_count",
	"completed_tick",
	"return_camera_state",
	"presenter_visibility_state",
]

var _chunk: Node3D
var _host: Node
var _authority_id := ""
var _completion_callback := Callable()
var _publish_callback := Callable()
var _state: Dictionary = _default_state()
var _placement_transform := Transform3D.IDENTITY

var _presentation: Node3D
var _camera: Camera3D
var _staging_player: AnimationPlayer
var _stim_player: AnimationPlayer
var _presentation_active := false
var _dialogue_presenter_ready := true


func configure(
	chunk: Node3D,
	host: Node,
	authority_id: String,
	completion_callback: Callable,
	publish_callback: Callable,
) -> void:
	_chunk = chunk
	_host = host
	_authority_id = authority_id
	_completion_callback = completion_callback
	_publish_callback = publish_callback


func set_host(host: Node) -> void:
	_host = host


func get_state() -> Dictionary:
	return _state.duplicate(true)


func get_phase() -> String:
	return str(_state.get("phase", PHASE_NOT_STARTED))


func is_complete() -> bool:
	return get_phase() == PHASE_COMPLETE


func is_playing() -> bool:
	return get_phase() == PHASE_PLAYING


func get_dialogue_keys() -> Array[String]:
	return DIALOGUE_KEYS.duplicate()


func get_presentation_scene() -> Node3D:
	return _presentation if is_instance_valid(_presentation) else null


func can_present() -> bool:
	if _chunk == null or not is_instance_valid(_chunk) or not _chunk.is_inside_tree() \
			or _host == null or not is_instance_valid(_host):
		return false
	for method_name in [
		"get_preview_scheduler",
		"get_preview_scheduler_tick",
		"get_preview_dialogue_box",
		"capture_preview_camera_state",
		"valid_preview_camera_state",
		"begin_preview_cutscene_ownership",
		"end_preview_cutscene_ownership",
		"capture_preview_character_visual_visibility",
		"set_preview_character_visual_visibility",
		"restore_preview_character_visual_visibility",
		"play_preview_scheduler_animation_at",
		"stop_preview_scheduler_animation",
	]:
		if not _host.has_method(method_name):
			return false
	var scheduler = _scheduler()
	var dialogue := _dialogue_box()
	if scheduler == null or dialogue == null \
			or not scheduler.has_method("schedule_at") \
			or not scheduler.has_method("cancel_tag") \
			or not dialogue.has_method("say") \
			or not dialogue.has_method("set_cutscene_mode") \
			or not dialogue.has_method("is_active"):
		return false
	for key in DIALOGUE_KEYS:
		if not DialogueData.has_key(key):
			return false
	return true


func begin(placement_transform: Transform3D) -> bool:
	_placement_transform = placement_transform
	if is_complete():
		return true
	if is_playing():
		return _presentation_active or _rebuild_presentation()
	if not can_present():
		return false
	var camera_state_v: Variant = _host.call("capture_preview_camera_state")
	var visibility_state_v: Variant = _host.call(
		"capture_preview_character_visual_visibility", PARTY_IDS
	)
	if not (camera_state_v is Dictionary) \
			or not bool(_host.call("valid_preview_camera_state", camera_state_v)) \
			or not (visibility_state_v is Dictionary) \
			or (visibility_state_v as Dictionary).size() != PARTY_IDS.size() \
			or not _is_json_safe(visibility_state_v):
		return false
	var start_tick := _now()
	_state = {
		"version": AUTHORITY_VERSION,
		"phase": PHASE_PLAYING,
		"start_tick": start_tick,
		"dialogue_start_tick": start_tick + DIALOGUE_DELAY,
		"animation_deadline": start_tick + STAGING_DURATION,
		"dialogue_started": false,
		"dialogue_complete": false,
		"animation_complete": false,
		"completion_count": 0,
		"completed_tick": -1.0,
		"return_camera_state": (camera_state_v as Dictionary).duplicate(true),
		"presenter_visibility_state": (
			(visibility_state_v as Dictionary).duplicate(true)
		),
	}
	_dialogue_presenter_ready = true
	_publish()
	if not _rebuild_presentation():
		return false
	_rearm_callbacks()
	return true


func restore_state(
	raw_state: Variant,
	legacy_completed: bool,
	legacy_completed_tick := -1.0,
	placement_transform := Transform3D.IDENTITY,
) -> bool:
	_cancel_callbacks()
	_cleanup_derived(false)
	_placement_transform = placement_transform
	_dialogue_presenter_ready = false
	if not (raw_state is Dictionary) or (raw_state as Dictionary).is_empty():
		_state = (
			_complete_state(legacy_completed_tick)
			if legacy_completed
			else _default_state()
		)
	elif not valid_state(raw_state):
		push_warning(
			"Shelter2StimCutsceneController: rejected malformed nested authority for %s"
			% _authority_id
		)
		_state = (
			_complete_state(legacy_completed_tick)
			if legacy_completed
			else _default_state()
		)
	else:
		_state = (raw_state as Dictionary).duplicate(true)
	if is_complete() or get_phase() == PHASE_NOT_STARTED:
		return true
	if not can_present() or not _rebuild_presentation():
		complete_without_playback(maxf(_now(), legacy_completed_tick))
		return false
	_rearm_callbacks()
	process_authority()
	return true


func valid_state(raw_state: Variant) -> bool:
	if not (raw_state is Dictionary) or not _exact_string_keys(
		raw_state as Dictionary, STATE_KEYS
	):
		return false
	var state := raw_state as Dictionary
	if int(state.get("version", 0)) != AUTHORITY_VERSION \
			or not (state.get("phase", null) is String) \
			or not (state.get("dialogue_started", null) is bool) \
			or not (state.get("dialogue_complete", null) is bool) \
			or not (state.get("animation_complete", null) is bool) \
			or not _finite_number(state.get("start_tick", null)) \
			or not _finite_number(state.get("dialogue_start_tick", null)) \
			or not _finite_number(state.get("animation_deadline", null)) \
			or not _finite_number(state.get("completed_tick", null)) \
			or not _finite_number(state.get("completion_count", null)) \
			or not (state.get("return_camera_state", null) is Dictionary) \
			or not (state.get("presenter_visibility_state", null) is Dictionary) \
			or not _is_json_safe(state):
		return false
	var phase := str(state.get("phase", ""))
	var start_tick := float(state.get("start_tick", -1.0))
	var dialogue_tick := float(state.get("dialogue_start_tick", -1.0))
	var animation_tick := float(state.get("animation_deadline", -1.0))
	var completed_tick := float(state.get("completed_tick", -1.0))
	var dialogue_started := bool(state.get("dialogue_started", false))
	var dialogue_complete := bool(state.get("dialogue_complete", false))
	var animation_complete := bool(state.get("animation_complete", false))
	var completion_count_raw := float(state.get("completion_count", -1))
	var completion_count := int(completion_count_raw)
	if not is_equal_approx(completion_count_raw, float(completion_count)):
		return false
	if dialogue_complete and not dialogue_started:
		return false
	return _valid_phase_state(
		state,
		phase,
		start_tick,
		dialogue_tick,
		animation_tick,
		completed_tick,
		dialogue_started,
		dialogue_complete,
		animation_complete,
		completion_count
	)


static func _valid_phase_state(
	state: Dictionary,
	phase: String,
	start_tick: float,
	dialogue_tick: float,
	animation_tick: float,
	completed_tick: float,
	dialogue_started: bool,
	dialogue_complete: bool,
	animation_complete: bool,
	completion_count: int,
) -> bool:
	match phase:
		PHASE_NOT_STARTED:
			return start_tick < 0.0 and dialogue_tick < 0.0 and animation_tick < 0.0 \
				and completed_tick < 0.0 and not dialogue_started \
				and not dialogue_complete and not animation_complete \
				and completion_count == 0 \
				and (state.return_camera_state as Dictionary).is_empty() \
				and (state.presenter_visibility_state as Dictionary).is_empty()
		PHASE_PLAYING:
			return start_tick >= 0.0 \
				and dialogue_tick >= start_tick \
				and animation_tick >= dialogue_tick \
				and completed_tick < 0.0 \
				and completion_count == 0 \
				and not (state.return_camera_state as Dictionary).is_empty() \
				and not (state.presenter_visibility_state as Dictionary).is_empty()
		PHASE_COMPLETE:
			return start_tick >= 0.0 \
				and dialogue_tick >= start_tick \
				and animation_tick >= dialogue_tick \
				and completed_tick >= start_tick \
				and dialogue_started and dialogue_complete and animation_complete \
				and completion_count == 1
		_:
			return false


func complete_without_playback(completed_tick := -1.0) -> void:
	if is_complete():
		return
	_cancel_callbacks()
	_cleanup_derived(true)
	_state = _complete_state(completed_tick)
	_commit_completion()


func reset() -> void:
	_cancel_callbacks()
	_cleanup_derived(true)
	_state = _default_state()
	_dialogue_presenter_ready = true


func detach() -> void:
	_cancel_callbacks()
	_cleanup_derived(true)
	_host = null


func process_authority() -> void:
	if not is_playing():
		return
	var now := _now()
	if not bool(_state.get("dialogue_started", false)) \
			and now + DEADLINE_EPSILON >= float(_state.get("dialogue_start_tick", INF)):
		_commit_dialogue_started()
	if not bool(_state.get("animation_complete", false)) \
			and now + DEADLINE_EPSILON >= float(_state.get("animation_deadline", INF)):
		_commit_animation_complete()
	_try_complete()


## TutorialSequence restores GameState presenters before DialogueBox. The chunk
## forwards this later seam so we reconnect to the restored queue rather than
## queueing duplicate lines during GameState.deserialize().
func on_dialogue_presenter_snapshot_restored() -> void:
	_dialogue_presenter_ready = true
	if not is_playing():
		_set_dialogue_cutscene_mode(false)
		_disconnect_dialogue_callback()
		return
	process_authority()
	_ensure_dialogue_presentation()


func _on_dialogue_start_due() -> void:
	if not is_playing() or bool(_state.get("dialogue_started", false)) \
			or _now() + DEADLINE_EPSILON < float(
				_state.get("dialogue_start_tick", INF)
			):
		return
	_commit_dialogue_started()


func _on_animation_deadline_due() -> void:
	if not is_playing() or bool(_state.get("animation_complete", false)) \
			or _now() + DEADLINE_EPSILON < float(
				_state.get("animation_deadline", INF)
			):
		return
	_commit_animation_complete()


func _commit_dialogue_started() -> void:
	if not is_playing() or bool(_state.get("dialogue_started", false)):
		return
	_state["dialogue_started"] = true
	_publish()
	_ensure_dialogue_presentation()


func _commit_animation_complete() -> void:
	if not is_playing() or bool(_state.get("animation_complete", false)):
		return
	_state["animation_complete"] = true
	_publish()
	_try_complete()


func _on_dialogue_finished() -> void:
	if not is_playing() or not bool(_state.get("dialogue_started", false)) \
			or bool(_state.get("dialogue_complete", false)):
		return
	_state["dialogue_complete"] = true
	_publish()
	_try_complete()


func _try_complete() -> void:
	if not is_playing() \
			or not bool(_state.get("dialogue_complete", false)) \
			or not bool(_state.get("animation_complete", false)):
		return
	_cancel_callbacks()
	_state["phase"] = PHASE_COMPLETE
	_state["completion_count"] = 1
	_state["completed_tick"] = maxf(_now(), float(_state.get("start_tick", 0.0)))
	_commit_completion()
	_cleanup_derived(false)


func _commit_completion() -> void:
	if _completion_callback.is_valid():
		_completion_callback.call()
	else:
		_publish()


func _publish() -> void:
	if _publish_callback.is_valid():
		_publish_callback.call()


func _rearm_callbacks() -> void:
	_cancel_callbacks()
	if not is_playing():
		return
	var scheduler = _scheduler()
	if scheduler == null:
		return
	var now := _now()
	if not bool(_state.get("dialogue_started", false)):
		var dialogue_tick := float(_state.get("dialogue_start_tick", now))
		if now + DEADLINE_EPSILON >= dialogue_tick:
			_commit_dialogue_started()
		else:
			scheduler.call(
				"schedule_at",
				dialogue_tick,
				Callable(self, "_on_dialogue_start_due"),
				_dialogue_tag()
			)
	if not is_playing():
		return
	if not bool(_state.get("animation_complete", false)):
		var animation_tick := float(_state.get("animation_deadline", now))
		if now + DEADLINE_EPSILON >= animation_tick:
			_commit_animation_complete()
		else:
			scheduler.call(
				"schedule_at",
				animation_tick,
				Callable(self, "_on_animation_deadline_due"),
				_animation_tag()
			)


func _cancel_callbacks() -> void:
	var scheduler = _scheduler()
	if scheduler == null:
		return
	scheduler.call("cancel_tag", _dialogue_tag())
	scheduler.call("cancel_tag", _animation_tag())


func _ensure_dialogue_presentation() -> void:
	if not _dialogue_presenter_ready or not is_playing() \
			or not bool(_state.get("dialogue_started", false)):
		return
	var dialogue := _dialogue_box()
	if dialogue == null:
		return
	if bool(_state.get("dialogue_complete", false)):
		_set_dialogue_cutscene_mode(false)
		_disconnect_dialogue_callback()
		return
	_set_dialogue_cutscene_mode(true)
	_connect_dialogue_callback()
	if bool(dialogue.call("is_active")):
		return
	# Queue the complete authored conversation at once. DialogueBox's portable
	# snapshot then owns the current line and the two remaining lines.
	for key in DIALOGUE_KEYS:
		DialogueData.say_to(dialogue, key)


func _connect_dialogue_callback() -> void:
	var dialogue := _dialogue_box()
	if dialogue == null:
		return
	var callback := Callable(self, "_on_dialogue_finished")
	if not dialogue.is_connected("dialogue_finished", callback):
		dialogue.connect("dialogue_finished", callback, CONNECT_ONE_SHOT)


func _disconnect_dialogue_callback() -> void:
	var dialogue := _dialogue_box()
	if dialogue == null:
		return
	var callback := Callable(self, "_on_dialogue_finished")
	if dialogue.is_connected("dialogue_finished", callback):
		dialogue.disconnect("dialogue_finished", callback)


func _set_dialogue_cutscene_mode(enabled: bool) -> void:
	var dialogue := _dialogue_box()
	if dialogue != null and dialogue.has_method("set_cutscene_mode"):
		dialogue.call("set_cutscene_mode", enabled)


func _rebuild_presentation() -> bool:
	if not can_present():
		return false
	var camera_state := _state.get("return_camera_state", {}) as Dictionary
	var visibility_state := (
		_state.get("presenter_visibility_state", {}) as Dictionary
	)
	if not bool(_host.call("valid_preview_camera_state", camera_state)) \
			or visibility_state.size() != PARTY_IDS.size():
		return false
	_presentation = CUTSCENE_SCENE.instantiate() as Node3D
	if _presentation == null:
		return false
	_presentation.transform = _placement_transform
	_chunk.add_child(_presentation)
	_camera = _presentation.get_node_or_null("CinematicCamera") as Camera3D
	_staging_player = (
		_presentation.get_node_or_null("StagingAnimationPlayer") as AnimationPlayer
	)
	_stim_player = _presentation.get_node_or_null("StimAnimationPlayer") as AnimationPlayer
	if _camera == null or _staging_player == null or _stim_player == null \
			or not bool(_host.call(
				"begin_preview_cutscene_ownership",
				_authority_id,
				_camera,
				camera_state
			)):
		_free_presentation()
		return false
	if not bool(_host.call(
		"set_preview_character_visual_visibility", PARTY_IDS, false
	)):
		_host.call("end_preview_cutscene_ownership", _authority_id)
		_free_presentation()
		return false
	_presentation_active = true
	var start_tick := float(_state.get("start_tick", _now()))
	var staging_ok := bool(_host.call(
		"play_preview_scheduler_animation_at",
		_staging_player,
		STAGING_ANIMATION,
		start_tick
	))
	var stim_ok := bool(_host.call(
		"play_preview_scheduler_animation_at",
		_stim_player,
		STIM_ANIMATION,
		start_tick
	))
	if not staging_ok or not stim_ok:
		_cleanup_derived(false)
	return staging_ok and stim_ok


func _cleanup_derived(clear_owned_dialogue: bool) -> void:
	_disconnect_dialogue_callback()
	var dialogue := _dialogue_box()
	if clear_owned_dialogue and is_playing() \
			and bool(_state.get("dialogue_started", false)) \
			and not bool(_state.get("dialogue_complete", false)) \
			and dialogue != null and dialogue.has_method("clear"):
		dialogue.call("clear")
	_set_dialogue_cutscene_mode(false)
	if _host != null and is_instance_valid(_host):
		if _staging_player != null and is_instance_valid(_staging_player) \
				and _host.has_method("stop_preview_scheduler_animation"):
			_host.call("stop_preview_scheduler_animation", _staging_player)
		if _stim_player != null and is_instance_valid(_stim_player) \
				and _host.has_method("stop_preview_scheduler_animation"):
			_host.call("stop_preview_scheduler_animation", _stim_player)
		if _presentation_active:
			var visibility_state := (
				_state.get("presenter_visibility_state", {}) as Dictionary
			)
			if not visibility_state.is_empty() \
					and _host.has_method(
						"restore_preview_character_visual_visibility"
					):
				_host.call(
					"restore_preview_character_visual_visibility",
					visibility_state
				)
			if _host.has_method("end_preview_cutscene_ownership"):
				_host.call("end_preview_cutscene_ownership", _authority_id)
	_presentation_active = false
	_free_presentation()


func _free_presentation() -> void:
	if _presentation != null and is_instance_valid(_presentation):
		_presentation.queue_free()
	_presentation = null
	_camera = null
	_staging_player = null
	_stim_player = null


func _scheduler():
	if _host != null and is_instance_valid(_host) \
			and _host.has_method("get_preview_scheduler"):
		return _host.call("get_preview_scheduler")
	return null


func _dialogue_box() -> Node:
	if _host != null and is_instance_valid(_host) \
			and _host.has_method("get_preview_dialogue_box"):
		return _host.call("get_preview_dialogue_box") as Node
	return null


func _now() -> float:
	if _host != null and is_instance_valid(_host) \
			and _host.has_method("get_preview_scheduler_tick"):
		return float(_host.call("get_preview_scheduler_tick"))
	var scheduler = _scheduler()
	return (
		float(scheduler.call("get_current_tick"))
		if scheduler != null and scheduler.has_method("get_current_tick")
		else 0.0
	)


func _dialogue_tag() -> String:
	return "shelter2_stim_dialogue:%s" % _authority_id


func _animation_tag() -> String:
	return "shelter2_stim_animation:%s" % _authority_id


func _complete_state(completed_tick: float) -> Dictionary:
	var tick := completed_tick
	if not is_finite(tick) or tick < 0.0:
		tick = _now()
	return {
		"version": AUTHORITY_VERSION,
		"phase": PHASE_COMPLETE,
		"start_tick": tick,
		"dialogue_start_tick": tick,
		"animation_deadline": tick,
		"dialogue_started": true,
		"dialogue_complete": true,
		"animation_complete": true,
		"completion_count": 1,
		"completed_tick": tick,
		"return_camera_state": {},
		"presenter_visibility_state": {},
	}


static func _default_state() -> Dictionary:
	return {
		"version": AUTHORITY_VERSION,
		"phase": PHASE_NOT_STARTED,
		"start_tick": -1.0,
		"dialogue_start_tick": -1.0,
		"animation_deadline": -1.0,
		"dialogue_started": false,
		"dialogue_complete": false,
		"animation_complete": false,
		"completion_count": 0,
		"completed_tick": -1.0,
		"return_camera_state": {},
		"presenter_visibility_state": {},
	}


static func _exact_string_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.size() != expected.size():
		return false
	for raw_key in value:
		if not (raw_key is String) or not expected.has(str(raw_key)):
			return false
	return true


static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _is_json_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_ARRAY:
			for entry in value as Array:
				if not _is_json_safe(entry):
					return false
			return true
		TYPE_DICTIONARY:
			for raw_key in (value as Dictionary):
				if not (raw_key is String) \
						or not _is_json_safe((value as Dictionary)[raw_key]):
					return false
			return true
		_:
			return false
