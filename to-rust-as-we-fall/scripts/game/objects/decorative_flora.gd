class_name DecorativeFlora
extends Interactable

## ORNAMENTAL INVASIVE flora (docs/DECORATIVE_FLORA.md): decoration with NO gameplay value that
## reads as scenery — no hover outline, no SHIFT reveal, not pickable. Peris's HARVEST ability is
## the only thing that lights it: the reveal window registers a YELLOW outline ("just pretty") and
## makes it clickable exactly long enough to CLEAR it (harvesting yields nothing and removes the
## instance). Canon: every decorative species is a feral cultivar of an engineered commercial
## product (GDD L1469) — the brand name survives as the species name.
##
## Species (per-species death/runback behaviour lives in the LOADER's runback pass; this class
## carries the state hooks):
##   verdanta  — corporate groundcover pile; spreads on runbacks (loader spawns the new patches)
##   curbelia  — median bedding rows; indifferent, never changes
##   lilypall  — floating pond rosettes; re-rolled per attempt (reroll(seed))
##   festoona  — celebration garland; droops after a wipe (set_drooped(true))

signal cleared()

const SPECIES := ["verdanta", "curbelia", "lilypall", "festoona"]
## The reveal tint: yellow, deliberately NOT the white hover or a character color — the outline
## grammar's third lane (white = interactive, char tint = queued, yellow = decorative).
const REVEAL_COLOR := Color(1.0, 0.84, 0.25)

var species := "curbelia"
var _opts: Dictionary = {}
var _species_meshes: Array = []
var _revealed := false
var _known := false
var _is_cleared := false
var _drooped := false

## Configure BEFORE adding to the tree (Interactable._ready sizes the pick shape from
## interaction_radius). No game-state dependency — decoration binds to nothing.
func configure(flora_species: String, world_pos: Vector3, opts: Dictionary = {}) -> void:
	species = flora_species if flora_species in SPECIES else "curbelia"
	position = world_pos
	_opts = opts.duplicate(true)
	interaction_radius = float(_opts.get("radius", 1.2))
	interactable_type = InteractableType.INSPECTION
	one_shot = true
	description = "Clear the ornamental growth"
	tutorial_label = "CLEAR"
	# Dormant scenery: not interactive and not pickable until a harvest reveal opens the window.
	interaction_enabled = false

func _ready() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var sh := SphereShape3D.new()
		sh.radius = interaction_radius
		cs.shape = sh
		add_child(cs)
	_build_species_visual()
	super._ready()
	# Dormant scenery: fully non-interactive AND un-pickable (the hover ray must sail through).
	set_interaction_enabled(false)
	# Deliberately NO outline target wiring: hover and SHIFT must show NOTHING (the whole point).
	if not interacted.is_connected(_on_cleared_interaction):
		interacted.connect(_on_cleared_interaction)

## --- The harvest reveal window (Peris's read) ---

## Lights/extinguishes the yellow outline. The mask registration goes STRAIGHT to the
## OutlineMaskManager — bypassing the OutlineSurfaceTarget hover pipeline on purpose, so the
## white grammar can never claim these meshes. The FIRST reveal makes the decorative KNOWN:
## it stays clickable (CLEAR) after the yellow fades — a committed clear order walking in as
## the window closes must not be silently refused (the disabled-trigger lesson).
func set_harvest_reveal(active: bool) -> void:
	if _is_cleared or active == _revealed:
		return
	_revealed = active
	if active and not _known:
		_known = true
		set_interaction_enabled(true)
	var manager = OutlineMaskManager.find_for(self)
	if manager != null:
		if active:
			manager.register(get_instance_id(), _species_meshes, REVEAL_COLOR, false)
		else:
			manager.unregister(get_instance_id())

func is_revealed() -> bool:
	return _revealed

## Harvest-clear: nothing yielded, the instance goes away. The only verb decoration answers to.
func clear_decoration() -> void:
	if _is_cleared:
		return
	set_harvest_reveal(false)
	_is_cleared = true
	set_interaction_enabled(false)
	visible = false
	cleared.emit()

func is_cleared() -> bool:
	return _is_cleared

func _on_cleared_interaction() -> void:
	clear_decoration()

## Host reset: back to the authored state (a fresh run) — present, unknown, un-drooped, dormant.
func reset_decoration() -> void:
	set_harvest_reveal(false)
	_is_cleared = false
	_known = false
	visible = true
	reset()                        # re-arm the one-shot
	set_interaction_enabled(false) # ...but back to dormant scenery
	if _drooped:
		_drooped = false
		_rebuild_species_visual()

## --- Per-species runback state hooks (the loader's runback pass drives these) ---

## Festoona: the celebration is over — the garland stays but wilts for the rest of the run.
func set_drooped(active: bool) -> void:
	if species != "festoona" or _drooped == active:
		return
	_drooped = active
	_rebuild_species_visual()

func is_drooped() -> bool:
	return _drooped

## Lilypall: the rafts drift between attempts — deal a fresh (deterministic) arrangement.
func reroll(attempt_seed: int) -> void:
	if species != "lilypall":
		return
	_opts["seed"] = attempt_seed
	_rebuild_species_visual()

## --- Visuals (simple procedural meshes; the loader never sees these) ---

func _rebuild_species_visual() -> void:
	var was_revealed := _revealed
	if was_revealed:
		set_harvest_reveal(false)
	for m in _species_meshes:
		if is_instance_valid(m):
			m.queue_free()
	_species_meshes.clear()
	_build_species_visual()
	if was_revealed:
		set_harvest_reveal(true)

func _build_species_visual() -> void:
	match species:
		"verdanta":
			_build_verdanta()
		"curbelia":
			_build_curbelia()
		"lilypall":
			_build_lilypall()
		"festoona":
			_build_festoona()

func _mesh(mesh: Mesh, local_pos: Vector3, color: Color, emission := Color.BLACK, energy := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = energy
	mi.material_override = mat
	mi.position = local_pos
	add_child(mi)
	_species_meshes.append(mi)
	return mi

## Verdanta: the impossibly even emerald pile — a floor patch plus a wall-climb tongue. Uniform
## color and a faint plastic sheen; nothing wild grows this flat.
func _build_verdanta() -> void:
	var green := Color(0.16, 0.52, 0.2)
	var patch := BoxMesh.new()
	patch.size = Vector3(interaction_radius * 1.8, 0.07, interaction_radius * 1.5)
	var floor_mi := _mesh(patch, Vector3(0.0, 0.035, 0.0), green)
	(floor_mi.material_override as StandardMaterial3D).roughness = 0.35
	if bool(_opts.get("wall", true)):
		var tongue := BoxMesh.new()
		tongue.size = Vector3(interaction_radius * 0.9, 1.4, 0.08)
		_mesh(tongue, Vector3(0.0, 0.7, -interaction_radius * 0.72), green * 0.92)

## Curbelia: one-color blossoms in a dead-straight row on a low bed — planted by the meter.
## The geometry (a line, never a drift) is the tell.
func _build_curbelia() -> void:
	var bed := BoxMesh.new()
	var count := int(_opts.get("count", 5))
	bed.size = Vector3(0.34 * count, 0.12, 0.4)
	_mesh(bed, Vector3(0.0, 0.06, 0.0), Color(0.24, 0.18, 0.14))
	var petal := Color(0.95, 0.62, 0.78) if int(_opts.get("tint", 0)) == 0 else Color(0.78, 0.68, 0.95)
	for i in count:
		var bloom := SphereMesh.new()
		bloom.radius = 0.09
		bloom.height = 0.18
		_mesh(bloom, Vector3((i - (count - 1) * 0.5) * 0.34, 0.2, 0.0), petal, petal, 0.12)

## Lilypall: flat pastel rosettes tiling a water surface. Deterministic per seed so the
## per-attempt re-roll replays.
func _build_lilypall() -> void:
	var count := int(_opts.get("count", 6))
	var spread := float(_opts.get("spread", interaction_radius))
	var seed_v := int(_opts.get("seed", 0))
	for i in count:
		var h := hash(str(seed_v) + "_pall_" + str(i))
		var ang := float(h % 628) * 0.01
		var dist := float((h / 628) % 100) * 0.01 * spread
		var pad := CylinderMesh.new()
		pad.top_radius = 0.22
		pad.bottom_radius = 0.22
		pad.height = 0.04
		_mesh(pad, Vector3(cos(ang) * dist, 0.02, sin(ang) * dist),
			Color(0.72, 0.85, 0.7), Color(0.9, 0.8, 0.85), 0.08)

## Festoona: a garland catenary strung between two posts. Drooped = the wilted after-state (gray,
## deeper sag) the wipe pass flips on.
func _build_festoona() -> void:
	var span: Vector3 = _opts.get("span", Vector3(2.4, 0.0, 0.0))
	var top := float(_opts.get("height", 1.9))
	var sag := (0.85 if _drooped else 0.45) * float(_opts.get("sag", 1.0))
	var bloom_color := Color(0.55, 0.5, 0.42) if _drooped else Color(0.9, 0.55, 0.7)
	for side in [-0.5, 0.5]:
		var post := CylinderMesh.new()
		post.top_radius = 0.05
		post.bottom_radius = 0.06
		post.height = top
		_mesh(post, span * side + Vector3(0.0, top * 0.5, 0.0), Color(0.3, 0.28, 0.26))
	var beads := 9
	for i in beads:
		var t := float(i) / float(beads - 1)
		var p: Vector3 = span * (t - 0.5) + Vector3(0.0, top - sag * 4.0 * t * (1.0 - t), 0.0)
		var bead := SphereMesh.new()
		bead.radius = 0.07
		bead.height = 0.14
		_mesh(bead, p, bloom_color, bloom_color, 0.0 if _drooped else 0.15)
