class_name RoomPieceCatalog
extends RefCounted

## Loads the tileable ROOM-PIECE catalog (data/generation/roompiece_catalog.json) — the WFC "tiles" the
## two-tier generator drops into each archetype-node slot. Mirrors StretchArchetypeCatalog's load/validate
## style. A piece declares: size:[w,h] (tile cells), walkable rows ("."=floor "#"=wall), per-side edge SOCKETS
## (one kind per edge cell: wall|open|door), connection_points (where a corridor attaches), tags (eligibility),
## and a pick weight. Rotation + socket-compatibility helpers are static so the WFC + the stitcher share them.

const DEFAULT_PATH := "res://data/generation/roompiece_catalog.json"

var path := DEFAULT_PATH
var data: Dictionary = {}
var errors: Array[String] = []

func _init(load_default := true) -> void:
	if load_default:
		load_from_file()

func load_from_file(next_path := DEFAULT_PATH) -> bool:
	path = next_path
	errors.clear()
	data = _load_json_dict(path)
	if data.is_empty():
		errors.append("Missing or invalid room-piece catalog: %s" % path)
	return bool(validate().get("valid", false))

func tile_size() -> int:
	return int(data.get("tile_size", 1))

func socket_kinds() -> Array:
	return data.get("socket_kinds", ["wall", "open", "door"])

func piece_ids() -> Array[String]:
	var ids: Array[String] = []
	var pieces: Dictionary = data.get("pieces", {})
	for key in pieces.keys():
		ids.append(str(key))
	ids.sort()
	return ids

func get_piece(id: Variant) -> Dictionary:
	var pieces: Dictionary = data.get("pieces", {})
	var key := str(id)
	if pieces.has(key) and pieces[key] is Dictionary:
		var p: Dictionary = (pieces[key] as Dictionary).duplicate(true)
		p["id"] = key
		return p
	return {}

func has_piece(id: Variant) -> bool:
	return not get_piece(id).is_empty()

## Pieces whose tags INTERSECT `tags` (the slot's archetype role/tags). The eligibility gate before WFC.
func pieces_for_tags(tags: Array) -> Array[String]:
	var want := {}
	for t in tags:
		want[str(t)] = true
	var out: Array[String] = []
	for id in piece_ids():
		for t in get_piece(id).get("tags", []):
			if want.has(str(t)):
				out.append(id)
				break
	return out

func validate() -> Dictionary:
	var errs: Array[String] = []
	var pieces: Dictionary = data.get("pieces", {})
	var spatial_feature_count := 0
	if pieces.is_empty():
		errs.append("Room-piece catalog has no pieces")
	var kinds := {}
	for k in socket_kinds():
		kinds[str(k)] = true
	for id in pieces.keys():
		var p: Variant = pieces[id]
		if not (p is Dictionary):
			errs.append("%s is not a dict" % id)
			continue
		var size: Array = (p as Dictionary).get("size", [])
		if size.size() != 2:
			errs.append("%s: size must be [w,h]" % id)
			continue
		var w := int(size[0])
		var h := int(size[1])
		var walkable: Array = (p as Dictionary).get("walkable", [])
		if walkable.size() != h:
			errs.append("%s: walkable has %d rows, expected h=%d" % [id, walkable.size(), h])
		else:
			for r in walkable:
				if str(r).length() != w:
					errs.append("%s: walkable row '%s' width != w=%d" % [id, str(r), w])
					break
		var sockets: Dictionary = (p as Dictionary).get("sockets", {})
		for side in ["n", "s"]:
			if (sockets.get(side, []) as Array).size() != w:
				errs.append("%s: socket %s length != w=%d" % [id, side, w])
		for side in ["e", "w"]:
			if (sockets.get(side, []) as Array).size() != h:
				errs.append("%s: socket %s length != h=%d" % [id, side, h])
		for side in sockets.keys():
			for kind in sockets[side]:
				if not kinds.has(str(kind)):
					errs.append("%s: unknown socket kind '%s' on %s" % [id, str(kind), side])
		var feature: Dictionary = (p as Dictionary).get("spatial_feature", {})
		if not feature.is_empty():
			spatial_feature_count += 1
			if str(feature.get("kind", "")) == "":
				errs.append("%s: spatial_feature requires a kind" % id)
			var scene_path := str(feature.get("scene", ""))
			if scene_path == "" or not ResourceLoader.exists(scene_path):
				errs.append("%s: spatial_feature scene does not exist: %s" % [id, scene_path])
			var content_sockets: Variant = feature.get("content_sockets", {})
			if not (content_sockets is Dictionary) or (content_sockets as Dictionary).is_empty():
				errs.append("%s: spatial_feature requires content_sockets" % id)
			else:
				for category in (content_sockets as Dictionary).keys():
					for socket in (content_sockets as Dictionary).get(category, []):
						if not (socket is Array) or (socket as Array).size() != 3:
							errs.append("%s: %s content socket must be [x,y,z]" % [id, str(category)])
	errors.append_array(errs)
	return {
		"valid": errs.is_empty(),
		"errors": errs,
		"piece_count": pieces.size(),
		"spatial_feature_count": spatial_feature_count,
	}

# --- Static geometry helpers (shared by WFC + stitcher) ---

## The seam rule: two FACING socket arrays are compatible iff equal length and every cell-pair matches —
## wall|wall, open|open/door, door|open/door. Used for adjacency propagation + corridor-mouth validation.
static func sockets_compatible(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if not _kinds_ok(str(a[i]), str(b[i])):
			return false
	return true

static func _kinds_ok(x: String, y: String) -> bool:
	if x == "wall":
		return y == "wall"
	if x == "open" or x == "door":
		return y == "open" or y == "door"
	return false

## Which sides {n,s,e,w} carry at least one OPEN/door socket (a corridor can attach there). Used to gate a
## piece against a slot's required-open sides.
static func open_sides(piece: Dictionary) -> Dictionary:
	var out := {"n": false, "s": false, "e": false, "w": false}
	var sockets: Dictionary = piece.get("sockets", {})
	for side in ["n", "s", "e", "w"]:
		for k in sockets.get(side, []):
			if str(k) == "open" or str(k) == "door":
				out[side] = true
				break
	return out

## A copy of `piece` rotated CW by `deg` (0/90/180/270): size, walkable, sockets, connection_points all
## transform together. Pure + deterministic (no RNG), so WFC stays seed-reproducible.
static func rotate_piece(piece: Dictionary, deg: int) -> Dictionary:
	var p := piece.duplicate(true)
	var times := (int(deg) / 90) % 4
	for _i in range(times):
		p = _rotate_cw(p)
	p["rotation"] = int(deg) % 360
	return p

static func _rotate_cw(p: Dictionary) -> Dictionary:
	var size: Array = p.get("size", [1, 1])
	var w := int(size[0])
	var h := int(size[1])
	var new_w := h
	var new_h := w
	var old_walk: Array = p.get("walkable", [])
	# new (nx,ny) <- old (ox,oy) where ox=ny, oy=h-1-nx
	var new_walk: Array = []
	for ny in range(new_h):
		var row := ""
		for nx in range(new_w):
			var ox := ny
			var oy := h - 1 - nx
			var src_row := str(old_walk[oy]) if oy < old_walk.size() else ""
			row += src_row.substr(ox, 1) if ox < src_row.length() else "."
		new_walk.append(row)
	var s: Dictionary = p.get("sockets", {})
	var new_sockets := {
		"n": _rev(s.get("w", [])),
		"e": s.get("n", []).duplicate(),
		"s": _rev(s.get("e", [])),
		"w": s.get("s", []).duplicate(),
	}
	var side_map := {"n": "e", "e": "s", "s": "w", "w": "n"}
	var new_cp := {}
	for side in p.get("connection_points", {}).keys():
		var pt: Array = p["connection_points"][side]
		var ox := int(pt[0])
		var oy := int(pt[1])
		new_cp[side_map[side]] = [h - 1 - oy, ox]
	var out := p.duplicate(true)
	out["size"] = [new_w, new_h]
	out["walkable"] = new_walk
	out["sockets"] = new_sockets
	out["connection_points"] = new_cp
	return out

static func _rev(arr: Array) -> Array:
	var out := arr.duplicate()
	out.reverse()
	return out

static func _load_json_dict(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var file := FileAccess.open(p, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
