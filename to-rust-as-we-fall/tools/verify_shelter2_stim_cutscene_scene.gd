extends SceneTree

const SCENE_PATH := "res://scenes/tutorial/shelter_2_aster_stim_cutscene.tscn"
const STAGING_CLIP := "shelter_2_staging"
const STIM_CLIP := "aster_stim_loop"
const STAGING_DURATION := 16.0
const STIM_LOOP_DURATION := 2.8

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect(packed != null, "authored Shelter 2 cutscene scene loads")
	if packed == null:
		_finish()
		return

	# A viewport promotes its first Camera3D automatically. Install the gameplay
	# baseline first so this assertion measures the scene's authored ownership
	# behavior instead of that engine fallback.
	var gameplay_camera := Camera3D.new()
	root.add_child(gameplay_camera)
	gameplay_camera.make_current()
	var instance := packed.instantiate()
	root.add_child(instance)
	_expect(instance is Node3D, "scene root is locally orientable Node3D")
	_expect(bool(instance.get_meta("presentation_only", false)),
		"scene is explicitly marked presentation-only")
	_expect(String(instance.get_meta("asset_status", "")) == "TEMPORARY_BLOCKOUT_PRESENTERS",
		"primitive cast presenters are explicitly marked temporary blockout work")

	var camera := instance.get_node_or_null("CinematicCamera") as Camera3D
	var staging_player := instance.get_node_or_null("StagingAnimationPlayer") as AnimationPlayer
	var stim_player := instance.get_node_or_null("StimAnimationPlayer") as AnimationPlayer
	var light := instance.get_node_or_null("ShelterLight") as OmniLight3D
	_expect(camera != null, "scene owns a dedicated cinematic Camera3D")
	_expect(camera != null and not camera.current,
		"cinematic camera never takes ownership merely by instantiating the scene")
	_expect(gameplay_camera.current,
		"instantiating the cutscene preserves the gameplay camera owner")
	_expect(staging_player != null, "scene owns a finite staging AnimationPlayer")
	_expect(stim_player != null, "scene owns an independent stim-loop AnimationPlayer")
	_expect(light != null and light.light_color.r > light.light_color.b,
		"scene owns a stable warm shelter practical")
	_expect(instance.get_node_or_null("Presenters/AsterPresenter") != null,
		"Aster presenter exists")
	_expect(instance.get_node_or_null("Presenters/PerisPresenter") != null,
		"Peris presenter exists")
	_expect(instance.get_node_or_null("Presenters/EndoPresenter") != null,
		"Endo presenter exists")
	_expect(instance.get_node_or_null("MaintainedBoundary") != null,
		"maintained-space threshold remains visible in the composition")

	if staging_player == null or stim_player == null:
		_finish()
		return
	_expect(staging_player.has_animation(STAGING_CLIP),
		"staging player exposes the canonical finite camera clip")
	_expect(stim_player.has_animation(STIM_CLIP),
		"stim player exposes the canonical independent loop")
	if not staging_player.has_animation(STAGING_CLIP) or not stim_player.has_animation(STIM_CLIP):
		_finish()
		return

	var staging := staging_player.get_animation(STAGING_CLIP)
	var stim := stim_player.get_animation(STIM_CLIP)
	_expect(is_equal_approx(staging.length, STAGING_DURATION),
		"staging clip has the documented sixteen-second timing contract")
	_expect(staging.loop_mode == Animation.LOOP_NONE, "staging clip is finite")
	_expect(is_equal_approx(stim.length, STIM_LOOP_DURATION),
		"stim loop has the documented 2.8-second cycle")
	_expect(stim.loop_mode == Animation.LOOP_LINEAR,
		"Aster's motion loops until the host completes both cutscene lanes")

	var camera_tracks := 0
	for track_index in staging.get_track_count():
		_expect(staging.track_get_type(track_index) == Animation.TYPE_VALUE,
			"staging track %d is property-only" % track_index)
		var path := String(staging.track_get_path(track_index))
		_expect(path.begins_with("CinematicCamera:"),
			"staging clip never mutates presenters or gameplay: %s" % path)
		camera_tracks += 1
	_expect(camera_tracks == 3,
		"staging camera motion is limited to position, rotation, and field of view")

	var aster_tracks := 0
	for track_index in stim.get_track_count():
		_expect(stim.track_get_type(track_index) == Animation.TYPE_VALUE,
			"stim track %d is property-only" % track_index)
		var path := String(stim.track_get_path(track_index))
		_expect(path.contains("Presenters/AsterPresenter"),
			"stim loop touches only Aster's presenter: %s" % path)
		_expect(not path.contains("PerisPresenter") and not path.contains("EndoPresenter"),
			"Peris and Endo remain static witnesses: %s" % path)
		_expect(not path.contains("ShelterLight"), "warm practical remains stable: %s" % path)
		aster_tracks += 1
	_expect(aster_tracks >= 7,
		"Aster has articulated torso, head, arm, forearm, and hand tracks")

	var left_forearm := instance.get_node(
		"Presenters/AsterPresenter/BodyRoot/LeftUpperArmPivot/LeftForearmPivot"
	) as Node3D
	stim_player.play(STIM_CLIP)
	stim_player.seek(0.0, true)
	var opening_pose := left_forearm.rotation
	stim_player.seek(0.7, true)
	var early_pose := left_forearm.rotation
	_expect(not opening_pose.is_equal_approx(early_pose),
		"close-to-body stimming begins before the dialogue-safe start")

	var threshold_z := (instance.get_node("Anchors/BoundaryPlane") as Marker3D).position.z
	staging_player.play(STAGING_CLIP)
	staging_player.seek(6.5, true)
	var before_crossing_z := camera.position.z
	staging_player.seek(8.5, true)
	var after_crossing_z := camera.position.z
	_expect(before_crossing_z > threshold_z and after_crossing_z < threshold_z,
		"camera visibly crosses the maintained-space threshold")

	_finish()


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] ", message)
	else:
		_failures.append(message)
		push_error("[FAIL] %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("Shelter 2 stim cutscene scene contract passed.")
		quit(0)
		return
	push_error("Shelter 2 stim cutscene scene contract failed (%d checks)." % _failures.size())
	quit(1)
