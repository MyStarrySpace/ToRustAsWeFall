extends "res://scripts/scene_chunks/scene_chunk.gd"

## Minimal production-shaped owner for SceneChunk's reusable sump, silo, and belt machinery. The focused
## save-authority verifier uses this instead of depending on a particular generated seed/layout.

var silo_victim: Enemy = null


func _build_chunk() -> void:
	_spawn_sump({
		"pos": Vector3(3.0, 0.0, 3.0),
		"pump_pos": Vector3(6.0, 0.0, 3.0),
		"pit_min": Vector3(2.0, 0.0, 2.0),
		"pit_max": Vector3(4.0, 0.0, 4.0),
		"pit_cells": [[2, 2], [3, 2]],
		"ledge_cell": [4, 2],
		"ledge_level": 1,
		"pit_enemy": true,
	})
	_spawn_silo({
		"pos": Vector3(10.0, 0.0, 3.0),
		"lever_pos": Vector3(13.0, 0.0, 3.0),
		"spill_min": Vector3(9.0, -0.5, 5.0),
		"spill_max": Vector3(11.0, 1.5, 7.0),
		"ramp_cell": [10, 6],
		"ramp_to_level": 1,
		"ramp_top": Vector3(10.0, 2.0, 8.0),
	})
	_spawn_belt({
		"name": "FixtureBelt",
		"pos": Vector3(2.0, 0.0, 12.0),
		"waypoints": [Vector3(8.0, 0.0, 12.0)],
		"breaker_pos": Vector3(2.0, 0.0, 10.0),
		"speed": 4.2,
		"powered": false,
	})
	_spawn_silo_victim()


func _spawn_silo_victim() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	silo_victim = Enemy.new()
	silo_victim.name = "SiloVictim"
	silo_victim.char_id = "silo_victim"
	silo_victim.position = Vector3(10.0, 0.0, 6.0)
	silo_victim.game_state = gs
	silo_victim.detection_range = 0.0
	add_child(silo_victim)
	gs.register_character(silo_victim.char_id, silo_victim.position, silo_victim.move_speed, {})
	gs.set_coop_exempt(silo_victim.char_id)
	silo_victim.activate()


func _enemy_by_id(char_id: String):
	if silo_victim != null and is_instance_valid(silo_victim) \
			and silo_victim.char_id == char_id:
		return silo_victim
	var pen = (_sumps[0] as Dictionary).get("pen", null) if not _sumps.is_empty() else null
	if pen != null and is_instance_valid(pen) and str(pen.char_id) == char_id:
		return pen
	return null
