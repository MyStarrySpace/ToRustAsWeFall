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
var _concealment_origin := Vector3.INF

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

## The modelled leaf head — concentric leaf tiers around the dark apex cavity that
## is the plant's whole affordance ("the cavity reads as doorway"). The library has
## carried this body all along while the runtime drew a box; the box survives only
## as the degrade path, so a missing model still leaves a clickable, hideable plant
## rather than an invisible one.
func _build_head() -> Node3D:
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
## only whichever mesh happened to be the root.
func _head_meshes() -> Array:
	var out: Array = []
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
func conceals(world_pos: Vector3) -> bool:
	var origin := global_position if _concealment_origin == Vector3.INF else _concealment_origin
	return Vector2(world_pos.x - origin.x, world_pos.z - origin.z).length() <= conceal_radius


func get_concealment_origin() -> Vector3:
	return global_position if _concealment_origin == Vector3.INF else _concealment_origin


## Coordinate-map presenters call this before moving the visible root. Ordinary
## authored scenes retain the original global-position behavior.
func set_concealment_origin(origin: Vector3) -> void:
	_concealment_origin = origin
