class_name Capbage
extends Interactable

## CAPBAGE (GDD 7.9, tight-hide flora): a self-sealing leaf head a member tucks into — fully undetectable inside.
## Concealment is POSITIONAL: this object knows its own hide radius (conceals(pos)); a fragment's per-frame pass
## asks each Capbage whether a member is inside and sets CONCEAL_FULL accordingly.
##
## Self-contained + reusable like Flure/Portal: owns its leaf-head visual, its outline/hover wiring (consistent
## highlight), and its hide-radius. A fragment composes it; a level builder places it.

signal tucked_in()

@export var leaf_color := Color(0.16, 0.34, 0.18)
@export var leaf_emission := Color(0.3, 0.7, 0.35)
@export var conceal_radius := 1.4

var _gs   # GameState (Interactable keeps its own _game_state for data binding)
var _head: Node3D
var _rig: FloraRig = null
var _concealment_origin := Vector3.INF
## Sealing is DERIVED from occupancy and purely cosmetic: the chunk's concealment
## pass asks conceals() on its own cadence, so the plant notices it is being used
## and closes. Nothing gameplay-facing reads these back — the hide works whether or
## not the leaves have finished moving.
var _sealed := false
var _last_occupied_ms := -1_000_000

## Configure BEFORE adding to the tree (interaction_radius is read in _ready).
##
## Authored Capbages traditionally use one radius for both clicking and bodily
## concealment. Generated content may pass a fourth, tighter radius because its
## broad leaf-head click hull is not evidence that a neighboring graph cell is
## physically inside the plant.
func configure(
		gs, world_pos: Vector3, radius := 1.4, body_conceal_radius := -1.0
	) -> void:
	_gs = gs
	position = world_pos
	interaction_radius = radius
	conceal_radius = radius if body_conceal_radius <= 0.0 else body_conceal_radius
	interactable_type = InteractableType.INSPECTION
	one_shot = false
	description = "Tuck into the Capbage"
	tutorial_label = "HIDE"

func _ready() -> void:
	add_to_group(&"capbage_hide_sources")
	juice_profile = "plant"   # flora rustle on hover + trigger (InteractableJuice)
	if get_node_or_null("CollisionShape3D") == null:
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var sh := SphereShape3D.new()
		sh.radius = interaction_radius
		cs.shape = sh
		add_child(cs)
	_head = _build_head()
	super._ready()
	_wire_outline()
	if not interacted.is_connected(_on_interacted):
		interacted.connect(_on_interacted)

## The leaf head — concentric leaf tiers around the dark apex cavity that is the
## plant's whole affordance ("the cavity reads as doorway").
##
## Preference order is RIGGED, then the static modelled piece, then the block. The
## rigged body is what lets the plant SEAL: the spec's states are a fold, not two
## shapes, and the fold is what a player watches when they tuck in.
func _build_head() -> Node3D:
	if FloraRig.has_rig("capbage"):
		var rigged := FloraRig.new()
		rigged.name = "Head"
		add_child(rigged)
		if rigged.setup("capbage"):
			_rig = rigged
			return rigged
		rigged.queue_free()
	var body := ArchetypePieceLibrary.instantiate("capbage")
	if body != null:
		body.name = "Head"
		add_child(body)
		return body
	push_warning("Capbage: no modelled body; falling back to the block head")
	var mi := MeshInstance3D.new()
	mi.name = "Head"
	var bm := BoxMesh.new()
	bm.size = Vector3(1.5, 1.0, 1.5)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = leaf_color
	m.emission_enabled = true
	m.emission = leaf_emission
	m.emission_energy_multiplier = 0.25
	mi.material_override = m
	mi.position = Vector3(0.0, 0.2, 0.0)
	add_child(mi)
	return mi


## Every mesh in the head, so the outline traces the modelled silhouette instead of
## only whichever mesh happened to be the root. A rigged head keeps its meshes under
## a Skeleton3D, so this walks rather than reaching for a known child.
func _head_meshes() -> Array:
	var out: Array = []
	if _head == null:
		return out
	var stack: Array = [_head]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out

func _wire_outline() -> void:
	var mgr := OutlineFeedbackManager.ensure(self)
	if mgr == null or _head == null:
		return
	var meshes := _head_meshes()
	if meshes.is_empty():
		return
	var target := mgr.outline_meshes(self, str(name) + "Outline", meshes, "capbage", maxf(1.0, interaction_radius))
	if target == null:
		return
	if target.has_method("set_interaction_delegate"):
		target.call("set_interaction_delegate", self)
	set_outline_target(target)

func _on_interacted() -> void:
	tucked_in.emit()

## True if `world_pos` is inside this Capbage's tight-hide radius (a member there is CONCEAL_FULL).
##
## The chunk's concealment pass calls this for every member on its own cadence, so
## it is also where the plant learns it is being USED. Noting that is what lets the
## head seal without any chunk having to tell it to — the four separate concealment
## passes in the codebase all break on the first match and discard which plant it
## was, so there is nothing upstream to ask.
func conceals(world_pos: Vector3) -> bool:
	var origin := global_position if _concealment_origin == Vector3.INF else _concealment_origin
	var inside := Vector2(world_pos.x - origin.x, world_pos.z - origin.z).length() <= conceal_radius
	if inside:
		_last_occupied_ms = Time.get_ticks_msec()
	_refresh_seal()
	return inside


## Seal while someone is inside, open once they have gone.
##
## This rides the concealment call rather than _process because Interactable turns
## per-frame processing OFF whenever it has no label or dwell work to do — a
## _process override here simply never runs. The pass asks every plant about every
## member on its own cadence, so it is a reliable heartbeat, and the hold window
## covers the gap between ticks so the head cannot flap. Cosmetic and derived: the
## hide works whether or not the leaves have finished moving.
const _OCCUPANCY_HOLD_MS := 700

func _refresh_seal() -> void:
	if _rig == null or not is_instance_valid(_rig):
		return
	var occupied := (Time.get_ticks_msec() - _last_occupied_ms) < _OCCUPANCY_HOLD_MS
	if occupied == _sealed:
		return
	_sealed = occupied
	_rig.play("capbage_seal" if occupied else "capbage_open")


func get_concealment_origin() -> Vector3:
	return global_position if _concealment_origin == Vector3.INF else _concealment_origin


## Coordinate-map presenters call this before moving the visible root. Ordinary
## authored scenes retain the original global-position behavior.
func set_concealment_origin(origin: Vector3) -> void:
	_concealment_origin = origin
