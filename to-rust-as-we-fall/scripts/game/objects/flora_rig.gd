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
## Each species ships its OWN gltf. A file holding several rigs gives every clip
## in it tracks for every armature, so a body built for one species arrives
## carrying the others' bones and warns for each track it cannot resolve.

## species id -> the armature node carrying its skin, in that species' own gltf
const SPECIES_ARMATURES := {
	"capbage": "Capbage_Armature",
	"seefern": "Seefern_Armature",
	"hushbloom": "Hushbloom_Armature",
	"scarpet": "Scarpet_Armature",
	"flure": "Flure_Armature",
	"gasafoetida": "Gasafoetida_Armature",
	# What a tended Gasafoetida hands you: a held item, not a plant, but the
	# same rigged body playing the same kind of clip.
	"gaspod": "GasPod_Armature",
	# The cut length a tended Climbvine gives up: carried it keeps its curve,
	# slung between anchors it hangs.
	"vinecut": "VineCut_Armature",
	# A cut rachis of the stun plant: jostled it folds and fires, the same wave
	# the growing plant uses, because it is the same leaf.
	"sample": "Sample_Armature",
	# Not flora. The rooted turret is rigged the same way and plays the same
	# kind of clip, so it rides the same bridge rather than growing a second.
	"spiker": "Spiker_Armature",
	"tangler": "Tangler_Armature",
	"flare": "Flare_Armature",
	"naturalizer": "Naturalizer_Armature",
	"redactor": "Redactor_Armature",
	"candid": "Candid_Armature",
	"hidra": "Hidra_Armature",
	"crust": "Crust_Armature",
	"meeb": "Meeb_Armature",
	"gnawer": "Gnawer_Armature",
	"toxo": "Toxo_Armature",
}

## Bodies that do not live under resources/models/flora.
const SPECIES_SCENE_OVERRIDE := {
	"spiker": "res://resources/models/fauna/spiker.gltf",
	"tangler": "res://resources/models/fauna/tangler.gltf",
	"flare": "res://resources/models/fauna/flare.gltf",
	"naturalizer": "res://resources/models/fauna/naturalizer.gltf",
	"redactor": "res://resources/models/fauna/redactor.gltf",
	"candid": "res://resources/models/fauna/candid.gltf",
	"hidra": "res://resources/models/fauna/hidra.gltf",
	"crust": "res://resources/models/fauna/crust.gltf",
	"meeb": "res://resources/models/fauna/meeb.gltf",
	"gnawer": "res://resources/models/fauna/gnawer.gltf",
	"toxo": "res://resources/models/fauna/toxo.gltf",
}

static var _packed := {}

var species := ""
var _player: AnimationPlayer = null
var _armature: Node3D = null


static func scene_path(species_id: String) -> String:
	if SPECIES_SCENE_OVERRIDE.has(species_id):
		return str(SPECIES_SCENE_OVERRIDE[species_id])
	return "res://resources/models/flora/flora_%s.gltf" % species_id


static func _ensure_packed(species_id: String) -> PackedScene:
	if _packed.has(species_id):
		return _packed[species_id]
	var path := scene_path(species_id)
	var packed: PackedScene = null
	if ResourceLoader.exists(path):
		var res = load(path)
		packed = res if res is PackedScene else null
	_packed[species_id] = packed
	return packed


## True when `species_id` has a rigged body to play clips on.
static func has_rig(species_id: String) -> bool:
	return SPECIES_ARMATURES.has(species_id) and _ensure_packed(species_id) != null


## Build the body for `species_id`. Returns false when the rig is unavailable, so a
## caller can fall back to its static piece rather than standing there invisible.
func setup(species_id: String) -> bool:
	species = species_id
	if not SPECIES_ARMATURES.has(species_id):
		return false
	var packed := _ensure_packed(species_id)
	if packed == null:
		return false
	var scene := packed.instantiate()
	var want := str(SPECIES_ARMATURES[species_id])
	_player = scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_armature = scene.find_child(want, true, false) as Node3D
	if _armature == null:
		scene.free()
		return false
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


## Play a clip and leave the plant in its FINAL pose — which is what a transition
## ends in anyway, since an AnimationPlayer keeps the last frame applied.
##
## This is deliberately not a "pose without playing": seek(), pause() and advance()
## are all no-ops issued straight after play() because playback has not been
## processed yet, and fighting that produced a plant parked at a random frame. The
## honest cost is that a plant which was ALREADY in a state when the scene loaded
## plays its transition once on arrival. Cheap, self-correcting, and the end state
## is right either way.
func play_to_end(clip: String) -> void:
	play(clip)


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


## Put the body back in the state it was modelled in, at once and without playing
## anything. A plant that re-arms has not just been tended, so replaying its tend
## would fire the completion flare for work nobody did; and the rest pose IS the
## ready state, so restoring it is the whole job.
func rest() -> void:
	if _player != null:
		_player.stop()
	for node in _skeletons():
		node.reset_bone_poses()


## Hang `node` off a named bone so it rides the animation. A child of the body
## alone keeps its own local transform, so it holds the bone's REST position while
## the bone itself moves away from it.
func attach_to_bone(node: Node3D, bone_name: String) -> bool:
	for sk in _skeletons():
		var idx := sk.find_bone(bone_name)
		if idx < 0:
			continue
		var hook := BoneAttachment3D.new()
		hook.name = "%sHook" % bone_name
		sk.add_child(hook)
		hook.bone_name = bone_name
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		hook.add_child(node)
		node.transform = Transform3D.IDENTITY
		return true
	return false


func _skeletons() -> Array[Skeleton3D]:
	var out: Array[Skeleton3D] = []
	var stack: Array = [self]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is Skeleton3D:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out
