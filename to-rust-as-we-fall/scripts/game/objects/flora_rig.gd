class_name FloraRig
extends Node3D

## The rigged BODY of a tendable plant, and the one place a flora object plays a
## state transition.
##
## THE LAW (director, 2026-08-10): a state change is an ANIMATION. The specs make
## the transition the readable thing — a Seefern's eye-markings "opening as she
## works" is what "tells the player when it's complete", a Hushbloom's leaflets
## fold "in a wave along each rachis" — so a plant that changes state plays a clip
## rather than swapping bodies or repainting.
##
## A clip is COSMETIC. The data layer owns the state and the scheduler owns when it
## commits; nothing here is ever waited on, and no gameplay truth is read back out
## of an animation (the fast-forward invariance law).
##
## The source gltf holds every species under one AnimationPlayer, so `setup()`
## keeps the requested species' armature and frees the rest — the clips are named
## per species precisely so one player can carry them all without collision.

const RIG_SCENE := "res://resources/models/flora/flora_rigged.gltf"

## species id -> the armature node that carries its skin in the shared gltf
const SPECIES_ARMATURES := {
	"capbage": "Capbage_Armature",
	"seefern": "Seefern_Armature",
	"hushbloom": "Hushbloom_Armature",
}

static var _packed: PackedScene = null

var species := ""
var _player: AnimationPlayer = null
var _armature: Node3D = null


static func _ensure_packed() -> PackedScene:
	if _packed != null:
		return _packed
	if not ResourceLoader.exists(RIG_SCENE):
		return null
	var res = load(RIG_SCENE)
	_packed = res if res is PackedScene else null
	return _packed


## True when `species_id` has a rigged body to play clips on.
static func has_rig(species_id: String) -> bool:
	return SPECIES_ARMATURES.has(species_id) and _ensure_packed() != null


## Build the body for `species_id`. Returns false when the rig is unavailable, so a
## caller can fall back to its static piece rather than standing there invisible.
func setup(species_id: String) -> bool:
	species = species_id
	var packed := _ensure_packed()
	if packed == null or not SPECIES_ARMATURES.has(species_id):
		return false
	var scene := packed.instantiate()
	var want := str(SPECIES_ARMATURES[species_id])
	_player = scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_armature = scene.find_child(want, true, false) as Node3D
	if _armature == null:
		scene.free()
		return false
	# Drop the other species: one gltf carries them all, and a Capbage has no
	# business paying for a fern it will never show.
	for other_id in SPECIES_ARMATURES.keys():
		if str(other_id) == species_id:
			continue
		var other := scene.find_child(str(SPECIES_ARMATURES[other_id]), true, false)
		if other != null:
			other.get_parent().remove_child(other)
			other.queue_free()
	add_child(scene)
	return true


## Play a named clip if this body has one. Missing clips are ignored rather than
## warned about: a species legitimately has only the transitions it has, and a
## caller asking for `tend` on a plant with no tend clip wants nothing to happen.
func play(clip: String, from_start := true) -> void:
	if _player == null or not _player.has_animation(clip):
		return
	if from_start:
		_player.stop()
	_player.play(clip)


## Hold a clip's FINAL pose without playing it — the state a plant is already in
## when it comes into view (a Capbage that was sealed before the player arrived).
func hold_end(clip: String) -> void:
	if _player == null or not _player.has_animation(clip):
		return
	var anim := _player.get_animation(clip)
	_player.play(clip)
	_player.seek(anim.length, true)
	_player.pause()


func is_playing(clip := "") -> bool:
	if _player == null:
		return false
	if clip.is_empty():
		return _player.is_playing()
	return _player.is_playing() and _player.current_animation == clip


## This body's own clips. The shared player carries every species' animations, so
## the list is filtered to this one — a caller enumerating clips is asking what
## THIS plant can do, and the fern's are not among them.
func clips() -> PackedStringArray:
	var out := PackedStringArray()
	if _player == null:
		return out
	for name in _player.get_animation_list():
		if str(name).begins_with(species + "_"):
			out.append(name)
	return out


## Every mesh in the body, for the outline grammar to wrap.
func meshes() -> Array:
	var out: Array = []
	var stack: Array = [self]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out
