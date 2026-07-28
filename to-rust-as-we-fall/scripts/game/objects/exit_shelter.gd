class_name ExitShelter
extends Interactable
## THE WIN OBJECT (P-KIT extraction): the one way a fragment/slice completes.
## Click-gated (INSPECTION — click, walk, fire on arrival), retryable, and it
## refuses until the win is REAL: every configured party member standing inside
## the shelter region and nobody downed. Acceptance is ONE atomic replay-safe
## `command_party_rest`; the region registers as a GameState sanctuary so the
## detection gate, strike gate, and revive watch honor it ("a pad the game
## CALLS a shelter must BE one").
##
## The chunk supplies placement + party + completion handling (connect
## `rest_completed`); the kit owns the gate, the guard, and the rest.
## data_fragment_chunk's loader-local `_spawn_exit_shelter` predates this class
## and additionally owns replay receipt bookkeeping tied to its own save
## contract — migrate it onto this class when that file is next opened
## (docs/GAMEPLAY_OBJECTS.md tracks the ledger item).

signal rest_completed(members: Array)
signal rest_refused(reason: String, missing: Array)

var _shelter_gs = null
var _party: Array = []
var _center := Vector3.ZERO
var _half_size := Vector2(1.5, 1.5)
var _committing := false
var _completed := false

## Configure BEFORE add_child (Interactable._ready reads the radius). `center` and
## `half_size` are DATA-frame coords — on a warped scene the base interactable warp
## moves the click zone while the region math stays flat with the data layer.
func configure_shelter(gs, center: Vector3, half_size: Vector2, party_ids: Array,
		label := "REST PARTY", radius := 1.4) -> void:
	_shelter_gs = gs
	_center = center
	_half_size = half_size
	_party = party_ids.duplicate()
	interactable_type = InteractableType.INSPECTION
	one_shot = false
	description = "Shelter"
	tutorial_label = label
	interaction_radius = radius
	position = center
	if gs != null and gs.has_method("add_shelter_region"):
		gs.add_shelter_region(
			Vector2(center.x - half_size.x, center.z - half_size.y),
			Vector2(center.x + half_size.x, center.z + half_size.y))
	interacted.connect(_on_rest_requested)

func is_inside(p: Vector3) -> bool:
	return absf(p.x - _center.x) <= _half_size.x and absf(p.z - _center.z) <= _half_size.y

func is_completed() -> bool:
	return _completed

## Re-arm after a scenario reset (the completion latch is scenario state).
func reset_shelter() -> void:
	_committing = false
	_completed = false

func _on_rest_requested() -> void:
	if _committing or _completed or _shelter_gs == null:
		return
	var missing: Array = []
	var downed: Array = []
	var present: Array = []
	for id_v in _party:
		var id := str(id_v)
		if not _shelter_gs.characters.has(id):
			continue
		if _shelter_gs.has_method("is_downed") and bool(_shelter_gs.is_downed(id)):
			downed.append(id)
		elif not is_inside(_shelter_gs.get_position(id)):
			missing.append(id)
		else:
			present.append(id)
	if not downed.is_empty():
		rest_refused.emit("downed", downed)
		return
	if not missing.is_empty():
		rest_refused.emit("waiting", missing)
		return
	if present.is_empty():
		rest_refused.emit("nobody", [])
		return
	# The rest is recovery, not a toll: only members who NEED it are committed
	# (a full member fails the engine's restability guard by design), and when
	# nobody needs it the win completes immediately — the same flow the
	# canonical loader preflights.
	var needs_rest: Array = []
	for id_v in present:
		var id := str(id_v)
		if _shelter_gs.has_method("get_stat") and _shelter_gs.has_method("get_stat_cap"):
			if float(_shelter_gs.get_stat(id, "hp")) < float(_shelter_gs.get_stat_cap(id, "hp")) \
					or float(_shelter_gs.get_stat(id, "stamina")) < float(_shelter_gs.get_stat_cap(id, "stamina")):
				needs_rest.append(id)
		else:
			needs_rest.append(id)
	if not needs_rest.is_empty():
		_committing = true
		if _shelter_gs.has_method("command_party_rest") \
				and not bool(_shelter_gs.command_party_rest(needs_rest)):
			_committing = false
			rest_refused.emit("rest_failed", needs_rest)
			return
		_committing = false
	_completed = true
	rest_completed.emit(present)
