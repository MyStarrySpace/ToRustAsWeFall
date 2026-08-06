class_name CharacterStatePresentationController
extends Node

## Scene-level, presentation-only projection of authoritative character state.
##
## GameState remains the only concealment authority. This controller reads that
## state and asks the lazily resolved shared HUD to render a portrait cue; it
## never writes gameplay state, moves a character, or chooses an action.

const CONCEALMENT_PRESENTATION_KEY := "character_concealment"
const STATUS_COVERED := "COVERED"
const STATUS_HIDDEN := "HIDDEN"
const PLAYER_BODY_PRESENTER_GROUP := &"player_observation_party_presenters"
const PLAYER_STATE_PRESENTER_GROUP := \
	&"player_observation_character_state_presenters"

var _game_state: GameState = null
var _hud_resolver := Callable()
var _presented_statuses: Dictionary = {} # character id -> exact rendered cue
var _presented_hud: Node = null
var _hidden_body_presenters: Dictionary = {} # character id -> live presenter Node
## A render-frame handoff, not gameplay state. When FULL concealment clears in
## `_process`, the body/HUD tree changes before the renderer presents that new
## frame. Until `frame_post_draw`, player observation must continue reporting
## the last completed HIDDEN frame instead of combining a cleared badge with a
## body that has not reached the framebuffer yet.
var _pending_reveal_handoffs: Dictionary = {} # character id -> exact prior cue


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(PLAYER_STATE_PRESENTER_GROUP)


func setup(game_state: GameState, hud_resolver: Callable) -> void:
	shutdown()
	_game_state = game_state
	_hud_resolver = hud_resolver
	set_process(_game_state != null and _hud_resolver.is_valid())
	sync_presentation()


func shutdown() -> void:
	clear_presentation()
	_disconnect_reveal_handoff_draw()
	set_process(false)
	_game_state = null
	_hud_resolver = Callable()


func _process(_delta: float) -> void:
	sync_presentation()


## Rebuild immediately after save/restore instead of waiting for an unrelated
## input or gameplay tick to make the HUD truthful again.
func on_game_state_snapshot_restored() -> void:
	sync_presentation(true)


func sync_presentation(force := false) -> void:
	if _game_state == null:
		clear_presentation()
		return
	var character_ids: Array[String] = []
	for character_id_v in _game_state.characters.keys():
		character_ids.append(str(character_id_v))
	character_ids.sort()
	_sync_body_presentation(character_ids)

	var hud := _resolve_hud()
	if hud == null:
		_clear_statuses_from_hud(_presented_hud)
		_presented_hud = null
		_presented_statuses.clear()
		return
	if hud != _presented_hud:
		_clear_statuses_from_hud(_presented_hud)
		_presented_hud = hud
		_presented_statuses.clear()
		force = true

	var current_ids := {}
	for character_id in character_ids:
		current_ids[character_id] = true
		var status := _concealment_status(
			_game_state.get_character_concealment(character_id))
		if not force and str(_presented_statuses.get(character_id, "")) == status:
			continue
		if status == "":
			if hud.has_method("clear_portrait_auxiliary_status"):
				hud.call(
					"clear_portrait_auxiliary_status",
					character_id,
					CONCEALMENT_PRESENTATION_KEY
				)
			_presented_statuses.erase(character_id)
		elif hud.has_method("set_portrait_auxiliary_status") and bool(hud.call(
				"set_portrait_auxiliary_status",
				character_id,
				CONCEALMENT_PRESENTATION_KEY,
				status
			)):
			_presented_statuses[character_id] = status

	for character_id_v in _presented_statuses.keys().duplicate():
		var character_id := str(character_id_v)
		if current_ids.has(character_id):
			continue
		if hud.has_method("clear_portrait_auxiliary_status"):
			hud.call(
				"clear_portrait_auxiliary_status",
				character_id,
				CONCEALMENT_PRESENTATION_KEY
			)
		_presented_statuses.erase(character_id)


func clear_presentation() -> void:
	_clear_statuses_from_hud(_presented_hud)
	_presented_statuses.clear()
	_presented_hud = null
	_restore_all_hidden_body_presenters()
	_pending_reveal_handoffs.clear()
	_disconnect_reveal_handoff_draw()


func _clear_statuses_from_hud(hud: Node) -> void:
	if not is_instance_valid(hud) \
			or not hud.has_method("clear_portrait_auxiliary_status"):
		return
	for character_id_v in _presented_statuses.keys():
		hud.call(
			"clear_portrait_auxiliary_status",
			str(character_id_v),
			CONCEALMENT_PRESENTATION_KEY
		)


func _exit_tree() -> void:
	shutdown()


func _resolve_hud() -> Node:
	if not _hud_resolver.is_valid():
		return null
	var hud_v: Variant = _hud_resolver.call()
	return hud_v as Node if hud_v is Node and is_instance_valid(hud_v) else null


func _sync_body_presentation(character_ids: Array[String]) -> void:
	var current_ids := {}
	for character_id in character_ids:
		current_ids[character_id] = true
		var hidden := _game_state.get_character_concealment(character_id) \
			>= GameState.CONCEAL_FULL
		var tracked := _hidden_body_presenter(character_id)
		if tracked == null and _hidden_body_presenters.has(character_id):
			_hidden_body_presenters.erase(character_id)
		if not hidden:
			# The previous framebuffer still contains the exact HIDDEN portrait
			# and no body. Preserve that completed presentation as one atomic
			# observation mode until the restored body/cleared HUD frame draws.
			if tracked != null \
					and str(_presented_statuses.get(character_id, "")) \
						== STATUS_HIDDEN:
				_begin_reveal_handoff(character_id)
			_restore_hidden_body_presenter(character_id)
			continue
		_pending_reveal_handoffs.erase(character_id)
		var presenter := _resolve_unique_body_presenter(character_id)
		if tracked != null and tracked != presenter:
			_restore_hidden_body_presenter(character_id)
		if presenter == null \
				or not presenter.has_method("set_concealment_presentation_hidden"):
			continue
		presenter.call("set_concealment_presentation_hidden", true)
		_hidden_body_presenters[character_id] = presenter
	for character_id_v in _hidden_body_presenters.keys().duplicate():
		var character_id := str(character_id_v)
		if not current_ids.has(character_id):
			_restore_hidden_body_presenter(character_id)
	for character_id_v in _pending_reveal_handoffs.keys().duplicate():
		if not current_ids.has(str(character_id_v)):
			_pending_reveal_handoffs.erase(character_id_v)
	if _pending_reveal_handoffs.is_empty():
		_disconnect_reveal_handoff_draw()


## Presentation-only receipt consumed by PlayerObservationController. Raw IDs
## remain inside the adapter and are converted to its session-local portrait
## tokens before policy sees the exact HIDDEN word.
func get_player_observation_concealment_reveal_handoffs() -> Dictionary:
	return _pending_reveal_handoffs.duplicate(true)


func _begin_reveal_handoff(character_id: String) -> void:
	_pending_reveal_handoffs[character_id] = STATUS_HIDDEN
	var callback := Callable(self, "_on_reveal_handoff_frame_drawn")
	if not RenderingServer.frame_post_draw.is_connected(callback):
		RenderingServer.frame_post_draw.connect(callback)


func _disconnect_reveal_handoff_draw() -> void:
	var callback := Callable(self, "_on_reveal_handoff_frame_drawn")
	if RenderingServer.frame_post_draw.is_connected(callback):
		RenderingServer.frame_post_draw.disconnect(callback)


func _on_reveal_handoff_frame_drawn() -> void:
	# The body restore and portrait-status clear have now reached one completed
	# framebuffer together. Subsequent observations may bind the real body and
	# must no longer inherit the prior HIDDEN presentation.
	_pending_reveal_handoffs.clear()
	_disconnect_reveal_handoff_draw()


func _resolve_unique_body_presenter(character_id: String) -> Node:
	if get_tree() == null or get_parent() == null:
		return null
	var scope := get_parent()
	var matched_presenter: Node = null
	for presenter_v in get_tree().get_nodes_in_group(
			PLAYER_BODY_PRESENTER_GROUP):
		if not (presenter_v is Node) or not is_instance_valid(presenter_v):
			continue
		var presenter := presenter_v as Node
		if presenter != scope and not scope.is_ancestor_of(presenter):
			continue
		if not presenter.has_method("get_player_observation_portrait_key") \
				or str(presenter.call(
					"get_player_observation_portrait_key")) != character_id:
			continue
		# Ambiguous identity fails closed: never hide an arbitrary duplicate body.
		if matched_presenter != null:
			return null
		matched_presenter = presenter
	return matched_presenter


func _hidden_body_presenter(character_id: String) -> Node:
	var value: Variant = _hidden_body_presenters.get(character_id, null)
	return value as Node if value is Node and is_instance_valid(value) else null


func _restore_hidden_body_presenter(character_id: String) -> void:
	var presenter := _hidden_body_presenter(character_id)
	if presenter != null \
			and presenter.has_method("set_concealment_presentation_hidden"):
		presenter.call("set_concealment_presentation_hidden", false)
	_hidden_body_presenters.erase(character_id)


func _restore_all_hidden_body_presenters() -> void:
	for character_id_v in _hidden_body_presenters.keys().duplicate():
		_restore_hidden_body_presenter(str(character_id_v))


func _concealment_status(tier: int) -> String:
	if tier >= GameState.CONCEAL_FULL:
		return STATUS_HIDDEN
	if tier == GameState.CONCEAL_MEDIUM:
		return STATUS_COVERED
	return ""
