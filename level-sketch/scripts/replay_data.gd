class_name ReplayData
extends RefCounted

## Loads a generated-stretch replay (exported from the game project into res://samples/)
## and interpolates the party's positions over time. Pure data — the view just asks for
## "where is everyone at time t" and "what's the caption now". A replay carries a flat
## level projection plus one solution path per loadout (spotlight trio / Aster+Peris
## shadow), so the viewer can show the same stretch solved two different ways.

const SAMPLES_DIR := "res://samples"

var data: Dictionary = {}


## [{path, id, title, region, tier, multi}] for every replay bundled with the app.
static func list_samples() -> Array:
	var out := []
	var dir := DirAccess.open(SAMPLES_DIR)
	if dir == null:
		return out
	var names := []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".json"):
			names.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for n in names:
		var d := _load_json("%s/%s" % [SAMPLES_DIR, n])
		if d.is_empty():
			continue
		out.append({
			"path": "%s/%s" % [SAMPLES_DIR, n],
			"id": str(d.get("spec_id", n.get_basename())),
			"title": str(d.get("title", n.get_basename())),
			"region": str(d.get("region", "")),
			"tier": str(d.get("complexity_tier", "")),
			"multi": bool(d.get("multi_solution", false)),
		})
	return out


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func load_path(path: String) -> bool:
	data = _load_json(path)
	return not data.is_empty()


func title() -> String:
	return str(data.get("title", "Replay"))


func region() -> String:
	return str(data.get("region", ""))


func level() -> Dictionary:
	return data.get("level", {})


func solutions() -> Array:
	return data.get("solutions", [])


func solution(index: int) -> Dictionary:
	var s := solutions()
	return s[index] if index >= 0 and index < s.size() else {}


func duration(index: int) -> float:
	return float(solution(index).get("duration", 0.0))


## Cell-space positions of each party member at time t (interpolated between keyframes).
func characters_at(index: int, t: float) -> Dictionary:
	var frames: Array = solution(index).get("frames", [])
	if frames.is_empty():
		return {}
	if t <= float((frames[0] as Dictionary).get("t", 0.0)):
		return _chars(frames[0])
	for k in range(frames.size() - 1):
		var a: Dictionary = frames[k]
		var b: Dictionary = frames[k + 1]
		var ta := float(a.get("t", 0.0))
		var tb := float(b.get("t", 0.0))
		if t >= ta and t <= tb:
			var u := 0.0 if tb <= ta else clampf((t - ta) / (tb - ta), 0.0, 1.0)
			return _lerp_chars(a, b, u)
	return _chars(frames[frames.size() - 1])


## The most recent keyframe at time t (for the caption + which node is being solved).
func frame_at(index: int, t: float) -> Dictionary:
	var frames: Array = solution(index).get("frames", [])
	var current := {}
	for f in frames:
		if f is Dictionary and t + 0.0001 >= float((f as Dictionary).get("t", 0.0)):
			current = f
	if current.is_empty() and not frames.is_empty():
		current = frames[0]
	return current


## Node ids cleared up to (and including) time t — used to draw the solved trail.
func visited_nodes(index: int, t: float) -> Array:
	var out := []
	for f in solution(index).get("frames", []):
		if f is Dictionary and t + 0.0001 >= float((f as Dictionary).get("t", 0.0)):
			out.append(str((f as Dictionary).get("node", "")))
	return out


func _chars(frame: Dictionary) -> Dictionary:
	var out := {}
	for id in frame.get("characters", {}).keys():
		out[str(id)] = _to_vec(frame["characters"][id])
	return out


func _lerp_chars(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	var ca: Dictionary = a.get("characters", {})
	var cb: Dictionary = b.get("characters", {})
	var out := {}
	for id in ca.keys():
		var pa := _to_vec(ca[id])
		var pb := _to_vec(cb.get(id, ca[id]))
		out[str(id)] = pa.lerp(pb, u)
	return out


func _to_vec(raw: Variant) -> Vector2:
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float((raw as Array)[0]), float((raw as Array)[1]))
	return Vector2.ZERO
