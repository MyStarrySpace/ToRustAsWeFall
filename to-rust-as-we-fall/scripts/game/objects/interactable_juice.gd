class_name InteractableJuice
extends RefCounted

## The COSMETIC squash/rustle grammar for interactables — the enemy system's
## scale-pulse language (kill-and-replace tweens per beat) brought to props and
## plants, plus handheld haptics on touch devices.
##
## Laws: purely visual — SceneTree tweens on mesh scale/rotation, never a
## scheduler tick, never game state, so fast-forward invariance and replay are
## untouched. The banned click PARTICLE bursts stay banned (play_selected_feedback
## is a legacy no-op); juice is the object itself acknowledging the hand.
## Every beat ends by restoring BOTH scale and rotation to the mesh's rest pose,
## so interrupted beats can never leave a prop deformed.

const META_TWEEN := "juice_tween"
const META_BASE_SCALE := "juice_base_scale"
const META_BASE_ROT := "juice_base_rot"


## Squash on impact, overshoot back to rest — the trigger beat.
static func punch(meshes: Array, strength := 0.14, dur := 0.34) -> void:
	for m in meshes:
		var n := _animatable(m)
		if n == null:
			continue
		var base: Vector3 = _base_scale(n)
		var base_rot: Vector3 = _base_rot(n)
		var tw := _fresh_tween(n)
		tw.tween_property(n, "scale", Vector3(
			base.x * (1.0 + strength), base.y * (1.0 - strength), base.z * (1.0 + strength)),
			dur * 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(n, "scale", base, dur * 0.78) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(n, "rotation", base_rot, dur * 0.78)


## Organic shiver: decaying rotation swings around the rest pose — the plant beat.
## Base-at-origin flora meshes tip around their root, which reads as a rustle.
static func rustle(meshes: Array, strength := 0.07, dur := 0.55) -> void:
	for m in meshes:
		var n := _animatable(m)
		if n == null:
			continue
		var base: Vector3 = _base_scale(n)
		var base_rot: Vector3 = _base_rot(n)
		var tw := _fresh_tween(n)
		var amp := strength
		for k in range(3):
			var sway := amp if k % 2 == 0 else -amp
			tw.tween_property(n, "rotation:z", base_rot.z + sway, dur / 6.0) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			amp *= 0.45
		tw.tween_property(n, "rotation", base_rot, dur / 6.0) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(n, "scale", base, dur / 6.0)


## A short physical tap on devices that can feel it. Desktop is a silent no-op.
static func tap(ms := 40) -> void:
	if DisplayServer.is_touchscreen_available():
		Input.vibrate_handheld(ms)


static func _animatable(m: Variant) -> Node3D:
	if m is Node3D and is_instance_valid(m) and (m as Node3D).is_inside_tree():
		return m as Node3D
	return null


static func _base_scale(n: Node3D) -> Vector3:
	if not n.has_meta(META_BASE_SCALE):
		n.set_meta(META_BASE_SCALE, n.scale)
	return n.get_meta(META_BASE_SCALE)


static func _base_rot(n: Node3D) -> Vector3:
	if not n.has_meta(META_BASE_ROT):
		n.set_meta(META_BASE_ROT, n.rotation)
	return n.get_meta(META_BASE_ROT)


## Kill-and-replace: one live juice tween per node, the new beat animates from
## wherever the old one left off (no snap).
static func _fresh_tween(n: Node3D) -> Tween:
	if n.has_meta(META_TWEEN):
		var old = n.get_meta(META_TWEEN)
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var tw := n.create_tween()
	n.set_meta(META_TWEEN, tw)
	return tw
