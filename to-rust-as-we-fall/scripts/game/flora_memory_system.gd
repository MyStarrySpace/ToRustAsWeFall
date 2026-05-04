class_name FloraMemorySystem
extends RefCounted

enum Stage {
	EARLY,
	MID,
	LATE_MID,
	LATE,
	ENDGAME,
}

const STAGE_READ_DURATION := {
	Stage.EARLY: 60.0,
	Stage.MID: 30.0,
	Stage.LATE_MID: 18.0,
	Stage.LATE: 10.0,
	Stage.ENDGAME: 3.0,
}

const STAGE_LAYERS := {
	Stage.EARLY: {"species": 1.0, "health": 1.0, "context": 1.0, "direction": 1.0, "memory": 1.0},
	Stage.MID: {"species": 1.0, "health": 0.88, "context": 0.72, "direction": 0.45, "memory": 0.98},
	Stage.LATE_MID: {"species": 0.9, "health": 0.72, "context": 0.42, "direction": 0.2, "memory": 0.92},
	Stage.LATE: {"species": 0.58, "health": 0.42, "context": 0.18, "direction": 0.05, "memory": 0.74},
	Stage.ENDGAME: {"species": 0.26, "health": 0.16, "context": 0.0, "direction": 0.0, "memory": 0.36},
}

const SIGNAL_GENERIC := {
	"threat": ["movement", "something moving", "something here"],
	"hazard": ["stress pattern", "rough signal", "wrongness"],
	"iron": ["iron trace", "metal stress", "something metallic"],
	"resource": ["resource trace", "useful warmth", "something useful"],
	"cache": ["cache trace", "stored shape", "something stored"],
	"memory": ["memory trace", "familiar pull", "something familiar"],
	"relationship": ["anchor", "someone close", "someone"],
}

var stage: int = Stage.EARLY
var nodes: Dictionary = {}
var cures := {
	"relational": 0.0,
	"duration": 0.0,
	"context": 0.0,
	"direction": 0.0,
	"species": 0.0,
	"health": 0.0,
	"memory": 0.0,
}

var active_sensor_read: Dictionary = {}
var active_relational_refresh: Dictionary = {}

func register_node(id: String, data: Dictionary) -> void:
	var node := {
		"id": id,
		"species": str(data.get("species", "flora")),
		"zone": str(data.get("zone", "")),
		"position": data.get("position", Vector3.ZERO),
		"signal_pos": data.get("signal_pos", data.get("position", Vector3.ZERO)),
		"signal_type": str(data.get("signal_type", "memory")),
		"signal_label": str(data.get("signal_label", "memory trace")),
		"role": str(data.get("role", "sensor")),
		"encountered": bool(data.get("encountered", false)),
		"tended": bool(data.get("tended", false)),
		"childhood_species": bool(data.get("childhood_species", false)),
		"forget_me_not": bool(data.get("forget_me_not", false)),
		"relationship_strength": clampf(float(data.get("relationship_strength", 0.5)), 0.1, 1.0),
		"last_activation_tick": -1000.0,
	}
	nodes[id] = node

func has_node(id: String) -> bool:
	return nodes.has(id)

func set_stage(next_stage: int) -> void:
	stage = clampi(next_stage, Stage.EARLY, Stage.ENDGAME)

func can_activate_node(id: String, current_tick: float) -> bool:
	if not nodes.has(id):
		return false
	var node: Dictionary = nodes[id]
	var base_cooldown := maxf(4.0, _base_read_duration() * 0.2)
	return current_tick - float(node.get("last_activation_tick", -1000.0)) >= base_cooldown

func encounter_node(id: String, tended_override := false) -> void:
	if not nodes.has(id):
		return
	var node: Dictionary = nodes[id]
	node["encountered"] = true
	if tended_override:
		node["tended"] = true
	nodes[id] = node

func mark_tended(id: String) -> void:
	if not nodes.has(id):
		return
	var node: Dictionary = nodes[id]
	node["tended"] = true
	node["encountered"] = true
	node["relationship_strength"] = clampf(maxf(float(node.get("relationship_strength", 0.5)), 0.85), 0.1, 1.0)
	nodes[id] = node

func apply_cure_component(name: String) -> void:
	var lower := name.to_lower()
	if lower.find("chaperone lattice") != -1:
		cures["relational"] = minf(1.0, float(cures["relational"]) + 0.45)
		cures["duration"] = minf(1.0, float(cures["duration"]) + 0.15)
		cures["memory"] = minf(1.0, float(cures["memory"]) + 0.1)
	elif lower.find("context") != -1:
		cures["context"] = minf(1.0, float(cures["context"]) + 0.28)
	elif lower.find("direction") != -1:
		cures["direction"] = minf(1.0, float(cures["direction"]) + 0.32)
	elif lower.find("species") != -1:
		cures["species"] = minf(1.0, float(cures["species"]) + 0.24)
	elif lower.find("health") != -1:
		cures["health"] = minf(1.0, float(cures["health"]) + 0.24)
	else:
		cures["duration"] = minf(1.0, float(cures["duration"]) + 0.08)
		cures["memory"] = minf(1.0, float(cures["memory"]) + 0.08)

func start_read(id: String, current_tick: float) -> Dictionary:
	if not nodes.has(id):
		return {"started": false, "kind": "missing", "message": ""}

	var node: Dictionary = nodes[id]
	node["encountered"] = true
	node["last_activation_tick"] = current_tick
	nodes[id] = node

	if bool(node.get("forget_me_not", false)) or str(node.get("role", "sensor")) == "relationship":
		var scent := _forget_me_not_scent_state()
		if scent == "none":
			active_relational_refresh = {
				"source_id": id,
				"start_tick": current_tick,
				"end_tick": current_tick,
				"scent": scent,
			}
			return {
				"started": true,
				"kind": "relationship",
				"message": "Peris leans in. Nothing comes.",
				"scent": scent,
				"duration": 0.0,
			}
		var duration := 24.0 + 14.0 * _node_relationship(node) + float(cures["relational"]) * 14.0
		active_relational_refresh = {
			"source_id": id,
			"start_tick": current_tick,
			"end_tick": current_tick + duration,
			"scent": scent,
		}
		return {
			"started": true,
			"kind": "relationship",
			"message": "Peris catches the rust going away.",
			"scent": scent,
			"duration": duration,
		}

	var duration := _base_read_duration()
	duration *= lerpf(0.78, 1.22, _node_relationship(node))
	duration *= 1.0 + float(cures["duration"]) * 0.35
	active_sensor_read = {
		"source_id": id,
		"zone": str(node.get("zone", "")),
		"start_tick": current_tick,
		"end_tick": current_tick + duration,
		"duration": duration,
	}
	return {
		"started": true,
		"kind": "sensor",
		"message": "The flora network wakes around Peris.",
		"duration": duration,
	}

func get_overlay_snapshot(current_tick: float, zone := "") -> Dictionary:
	var layers := get_layer_strengths()
	var sensor_active := _sensor_read_active(current_tick)
	var relational := _relational_state(current_tick)
	var result := {
		"stage": stage,
		"window_active": sensor_active,
		"time_remaining": 0.0,
		"read_strength": 0.0,
		"source_id": "",
		"visible_clues": [],
		"layers": layers,
		"layer_words": {
			"species": _layer_word(float(layers["species"]), ["gone", "slipping", "steady", "clear"]),
			"health": _layer_word(float(layers["health"]), ["gone", "coarse", "steady", "nuanced"]),
			"context": _layer_word(float(layers["context"]), ["gone", "muddled", "partial", "readable"]),
			"direction": _layer_word(float(layers["direction"]), ["gone", "fuzzy", "partial", "precise"]),
			"memory": _layer_word(float(layers["memory"]), ["gone", "frayed", "held", "anchored"]),
		},
		"relational": relational,
	}

	if not sensor_active:
		return result

	var source_id := str(active_sensor_read.get("source_id", ""))
	var source_node: Dictionary = nodes.get(source_id, {})
	var duration := maxf(float(active_sensor_read.get("duration", 0.0)), 0.001)
	var remaining := maxf(0.0, float(active_sensor_read.get("end_tick", 0.0)) - current_tick)
	var age_ratio := clampf(remaining / duration, 0.0, 1.0)
	result["time_remaining"] = remaining
	result["read_strength"] = age_ratio
	result["source_id"] = source_id

	for node_id in nodes.keys():
		var node: Dictionary = nodes[node_id]
		if str(node.get("role", "sensor")) == "relationship" or bool(node.get("forget_me_not", false)):
			continue
		if zone != "" and str(node.get("zone", "")) != zone:
			continue
		if not bool(node.get("encountered", false)) and node_id != source_id:
			continue

		var delay := _propagation_delay(source_node, node, float(layers["memory"]))
		if current_tick < float(active_sensor_read.get("start_tick", 0.0)) + delay:
			continue

		result["visible_clues"].append(_build_clue(source_node, node, age_ratio, layers))

	return result

func get_debug_state(current_tick: float, zone := "") -> Dictionary:
	var snapshot := get_overlay_snapshot(current_tick, zone)
	snapshot["node_count"] = nodes.size()
	snapshot["encountered_count"] = _encountered_count(zone)
	return snapshot

func get_layer_strengths() -> Dictionary:
	var layers: Dictionary = STAGE_LAYERS.get(stage, STAGE_LAYERS[Stage.EARLY]).duplicate(true)
	layers["species"] = clampf(float(layers["species"]) + float(cures["species"]), 0.0, 1.0)
	layers["health"] = clampf(float(layers["health"]) + float(cures["health"]), 0.0, 1.0)
	layers["context"] = clampf(float(layers["context"]) + float(cures["context"]), 0.0, 1.0)
	layers["direction"] = clampf(float(layers["direction"]) + float(cures["direction"]), 0.0, 1.0)
	layers["memory"] = clampf(float(layers["memory"]) + float(cures["memory"]), 0.0, 1.0)
	return layers

func _sensor_read_active(current_tick: float) -> bool:
	return not active_sensor_read.is_empty() and current_tick < float(active_sensor_read.get("end_tick", -1.0))

func _relational_state(current_tick: float) -> Dictionary:
	var base_strength := clampf(1.0 - float(stage) * 0.24 + float(cures["relational"]) * 0.8, 0.0, 1.0)
	var refresh_strength := 0.0
	var scent := "none"
	if not active_relational_refresh.is_empty() and current_tick < float(active_relational_refresh.get("end_tick", -1.0)):
		scent = str(active_relational_refresh.get("scent", "none"))
		refresh_strength = 0.35
	var strength := clampf(base_strength + refresh_strength, 0.0, 1.0)
	return {
		"strength": strength,
		"status": _layer_word(strength, ["gone", "flicker", "held", "clear"]),
		"scent": scent,
		"refresh_active": scent != "none" and refresh_strength > 0.0,
	}

func _forget_me_not_scent_state() -> String:
	var relational_strength := clampf(1.0 - float(stage) * 0.3 + float(cures["relational"]) * 1.3, 0.0, 1.0)
	if relational_strength >= 0.62:
		return "rust going away"
	if relational_strength >= 0.36:
		return "flicker"
	return "none"

func _build_clue(source_node: Dictionary, node: Dictionary, age_ratio: float, layers: Dictionary) -> Dictionary:
	var relationship := _node_relationship(node)
	var species_strength := minf(float(layers["species"]), relationship)
	var context_strength := minf(float(layers["context"]), relationship)
	var direction_strength := minf(float(layers["direction"]), relationship)
	var display_pos: Vector3 = _display_position(node, direction_strength)
	var signal_type := str(node.get("signal_type", "memory"))
	return {
		"id": str(node.get("id", "")),
		"species_label": _species_text(str(node.get("species", "flora")), species_strength),
		"signal_type": signal_type,
		"signal_label": _signal_text(signal_type, str(node.get("signal_label", "")), context_strength),
		"display_pos": display_pos,
		"source_pos": node.get("position", Vector3.ZERO),
		"certainty": clampf(age_ratio * (0.45 + relationship * 0.55), 0.18, 1.0),
		"fuzzy": direction_strength < 0.55 or context_strength < 0.55,
		"distance_from_source": source_node.get("position", Vector3.ZERO).distance_to(node.get("position", Vector3.ZERO)),
	}

func _display_position(node: Dictionary, direction_strength: float) -> Vector3:
	var source_pos: Vector3 = node.get("position", Vector3.ZERO)
	var signal_pos: Vector3 = node.get("signal_pos", source_pos)
	if direction_strength >= 0.68:
		return signal_pos
	if direction_strength >= 0.3:
		return source_pos.lerp(signal_pos, 0.4) + _jitter_for_id(str(node.get("id", "")), 1.1)
	return source_pos + _jitter_for_id(str(node.get("id", "")), 1.8)

func _signal_text(signal_type: String, specific_label: String, strength: float) -> String:
	var fallback: Array = SIGNAL_GENERIC.get(signal_type, SIGNAL_GENERIC["memory"])
	if strength >= 0.72:
		return specific_label if specific_label != "" else str(fallback[0])
	if strength >= 0.36:
		return str(fallback[1])
	return str(fallback[2])

func _species_text(species: String, strength: float) -> String:
	if strength >= 0.72:
		return species
	if strength >= 0.36:
		return "familiar flora"
	return "unclear bloom"

func _propagation_delay(source_node: Dictionary, node: Dictionary, memory_strength: float) -> float:
	if source_node.is_empty():
		return 0.0
	if str(source_node.get("id", "")) == str(node.get("id", "")):
		return 0.0
	var source_pos: Vector3 = source_node.get("position", Vector3.ZERO)
	var node_pos: Vector3 = node.get("position", Vector3.ZERO)
	var distance: float = source_pos.distance_to(node_pos)
	var base_delay := 0.0
	if distance <= 10.0:
		base_delay = 0.6
	elif distance <= 32.0:
		base_delay = 3.2
	else:
		base_delay = 8.5
	return base_delay * lerpf(1.25, 0.8, memory_strength)

func _encountered_count(zone: String) -> int:
	var count := 0
	for node_id in nodes.keys():
		var node: Dictionary = nodes[node_id]
		if zone != "" and str(node.get("zone", "")) != zone:
			continue
		if bool(node.get("encountered", false)):
			count += 1
	return count

func _node_relationship(node: Dictionary) -> float:
	var strength := float(node.get("relationship_strength", 0.5))
	if bool(node.get("tended", false)):
		strength += 0.18
	if bool(node.get("childhood_species", false)):
		strength += 0.12
	return clampf(strength, 0.12, 1.0)

func _base_read_duration() -> float:
	return float(STAGE_READ_DURATION.get(stage, 10.0))

func _layer_word(strength: float, words: Array[String]) -> String:
	if strength >= 0.78:
		return words[3]
	if strength >= 0.48:
		return words[2]
	if strength >= 0.18:
		return words[1]
	return words[0]

func _jitter_for_id(id: String, radius: float) -> Vector3:
	var seed: int = abs(id.hash())
	var x := float(seed % 37) / 36.0 - 0.5
	var z := float((seed / 37) % 37) / 36.0 - 0.5
	return Vector3(x * radius, 0.0, z * radius)
