class_name MultiActorSurvey
extends RefCounted

## Scene-agnostic progress model for surveys that require both distinct observations
## and participation from specific actors.
##
## An observation is only counted once, while every valid actor who revisits it is
## still recorded. This lets a scene require multiple perspectives without forcing
## authors to duplicate interactables or hand-roll parallel dictionaries.

signal progress_changed
signal completed

var _required_observation_count := 1
var _required_actor_ids: Array[String] = []
var _observed_by: Dictionary = {}
var _actors_seen: Dictionary = {}
var _was_complete := false


func _init(required_observation_count := 1, required_actor_ids: Array = []) -> void:
	configure(required_observation_count, required_actor_ids)


func configure(required_observation_count: int, required_actor_ids: Array = []) -> void:
	_required_observation_count = maxi(0, required_observation_count)
	_required_actor_ids.clear()
	for actor_id_variant in required_actor_ids:
		var actor_id := str(actor_id_variant)
		if actor_id != "" and not _required_actor_ids.has(actor_id):
			_required_actor_ids.append(actor_id)
	reset()


func reset() -> void:
	_observed_by.clear()
	_actors_seen.clear()
	for actor_id in _required_actor_ids:
		_actors_seen[actor_id] = false
	_was_complete = false


## Records an interaction. Returns true when it adds either a new observation or
## a newly participating actor. Empty identifiers are rejected.
func record(observation_id: String, actor_id: String) -> bool:
	if observation_id == "" or actor_id == "":
		return false
	var changed := false
	if not _observed_by.has(observation_id):
		_observed_by[observation_id] = actor_id
		changed = true
	if not bool(_actors_seen.get(actor_id, false)):
		_actors_seen[actor_id] = true
		changed = true
	if not changed:
		return false
	progress_changed.emit()
	var complete_now := is_complete()
	if complete_now and not _was_complete:
		completed.emit()
	_was_complete = complete_now
	return true


func is_complete() -> bool:
	if _observed_by.size() < _required_observation_count:
		return false
	for actor_id in _required_actor_ids:
		if not bool(_actors_seen.get(actor_id, false)):
			return false
	return true


func observation_count() -> int:
	return _observed_by.size()


func required_observation_count() -> int:
	return _required_observation_count


func observation_ids() -> Array:
	return _observed_by.keys()


func observations() -> Dictionary:
	return _observed_by.duplicate()


## Includes every required actor with an explicit false value, plus any additional
## actors who participated. This is convenient for UI and save/debug snapshots.
func actor_presence() -> Dictionary:
	return _actors_seen.duplicate()


func has_actor_participated(actor_id: String) -> bool:
	return bool(_actors_seen.get(actor_id, false))


func snapshot() -> Dictionary:
	return {
		"observation_ids": observation_ids(),
		"observation_count": observation_count(),
		"observed_by": observations(),
		"actor_presence": actor_presence(),
		"required_observation_count": _required_observation_count,
		"required_actor_ids": _required_actor_ids.duplicate(),
		"complete": is_complete(),
	}


func restore(snapshot_data: Dictionary) -> void:
	_required_observation_count = maxi(0, int(snapshot_data.get(
		"required_observation_count", _required_observation_count
	)))
	_required_actor_ids.clear()
	for actor_id_variant in snapshot_data.get("required_actor_ids", []):
		var actor_id := str(actor_id_variant)
		if actor_id != "" and not _required_actor_ids.has(actor_id):
			_required_actor_ids.append(actor_id)
	_observed_by = (snapshot_data.get("observed_by", {}) as Dictionary).duplicate()
	_actors_seen = (snapshot_data.get("actor_presence", {}) as Dictionary).duplicate()
	for actor_id in _required_actor_ids:
		if not _actors_seen.has(actor_id):
			_actors_seen[actor_id] = false
	_was_complete = is_complete()
