class_name ChunkGenerator
extends RefCounted

## THE ATOMIC UNIT — a CHUNK. Not a space you wander; a gated puzzle. Every chunk has:
##   1. a START point,
##   2. an END point,
##   3. a PUZZLE (a composition of nested archetypes, per reference-docs/design_archetypes.md) that must be solved,
##   4. and the hard invariant: you CANNOT walk start->end without solving it.
## The invariant is real, not decorative: a chunk owns a GATE (cells that are impassable until the puzzle is
## solved). `verify_gated` flood-fills and asserts start->end is BLOCKED while locked and OPEN once solved — so a
## generated chunk that could be walked straight through is a hard error, not a slip. Each chunk also carries its
## PRESENTED solve (a hook member) and its SHADOW solve (Aster+Peris alone), because a section without both is,
## per the design docs, unfinished.

const SYM_WALL := "#"
const SYM_FLOOR := "."
const SYM_START := "S"
const SYM_END := "E"

const ARCHETYPES := ["holdfast", "redirect", "vinebridge", "split"]

static func generate(archetype_id: String, seed: int) -> Dictionary:
	var rng := SeededRng.new(seed ^ 0x0c00c11c)
	match archetype_id:
		"holdfast": return _build_holdfast(rng)
		"redirect": return _build_redirect(rng)
		"vinebridge": return _build_vinebridge(rng)
		"split": return _build_split(rng)
	return _build_holdfast(rng)

# --- shared layout helpers ------------------------------------------------------------------------------------

static func _ri(rng: SeededRng, a: int, b: int) -> int:
	return int(rng.call("randi_range", a, b))

## A rectangular room: border walls, floor interior.
static func _room(w: int, h: int) -> Dictionary:
	var g := {}
	for y in range(h):
		for x in range(w):
			g[Vector2i(x, y)] = SYM_WALL if (x == 0 or y == 0 or x == w - 1 or y == h - 1) else SYM_FLOOR
	return g

## A full-height vertical band of `sym` at column `col` (the gate that splits the room in two). Returns the cells.
static func _vgate(g: Dictionary, col: int, h: int, sym: String) -> Array:
	var cells: Array = []
	for y in range(1, h - 1):
		g[Vector2i(col, y)] = sym
		cells.append(Vector2i(col, y))
	return cells

# --- the archetypes -------------------------------------------------------------------------------------------

## HOLDFAST CROSSING — a wash you cannot walk. Main archetype: the channels HELD-override crossing. NESTS
## Archetype 7 (stealth-and-time): the override sits past a guard, so you must sneak to it. Hold it -> the wash
## stops -> the party crosses.
static func _build_holdfast(rng: SeededRng) -> Dictionary:
	var w := _ri(rng, 12, 14)
	var h := _ri(rng, 8, 10)
	var g := _room(w, h)
	var start := Vector2i(1, h / 2)
	var end := Vector2i(w - 2, h / 2)
	g[start] = SYM_START
	g[end] = SYM_END
	var col := _ri(rng, w / 2 - 1, w / 2 + 1)   # wash band roughly centred
	var gate := _vgate(g, col, h, "~")
	# Override + guard on the START side (you reach them without crossing the wash; the guard is the nested stealth).
	var ov := Vector2i(_ri(rng, 2, col - 2), 1)
	g[ov] = "O"
	var guard := Vector2i(_ri(rng, 2, col - 2), _ri(rng, 2, h - 3))
	if guard == ov or guard == start:
		guard = Vector2i(2, 2)
	g[guard] = "g"
	return {
		"id": "holdfast", "title": "Holdfast Crossing",
		"archetype": "held-override wash crossing (channels) — NESTS A7 stealth-and-time",
		"w": w, "h": h, "start": start, "end": end, "grid": g, "gate": gate,
		"nests": ["A7 stealth-and-time: reach the override past the guard"],
		"solve": "Sneak past the guard (g) to the flow-override (O); a member HOLDS it and the wash stops; the rest cross the dry channel to the end. Lose the holder and the crossers are exposed — the role is inheritable.",
		"shadow": "Aster+Peris, no holder: Aster TRACE names the wash's dark window; Peris BLOOM raises a flora causeway across one lane — cross in timed dashes, unheld.",
		"legend": {"~": "wash (lethal; blocks; calm only while O is HELD)", "O": "held flow-override", "g": "guard (nested stealth)"},
	}

## REDIRECTED AGGRESSION (Archetype 1) — a solid wall you cannot pass. Bait an enemy into charging the wall so it
## breaches. NESTS a dodge beat (step off the bait line as it commits).
static func _build_redirect(rng: SeededRng) -> Dictionary:
	var w := _ri(rng, 12, 14)
	var h := _ri(rng, 8, 10)
	var g := _room(w, h)
	var start := Vector2i(1, h / 2)
	var end := Vector2i(w - 2, h / 2)
	g[start] = SYM_START
	g[end] = SYM_END
	var col := _ri(rng, w / 2 - 1, w / 2 + 1)
	var gate := _vgate(g, col, h, "X")
	# Bait sits against the wall on the line to the end; the enemy charges through it into the wall.
	var brow := _ri(rng, 2, h - 3)
	var bait := Vector2i(col - 1, brow)
	var enemy := Vector2i(_ri(rng, 2, col - 2), brow)
	if enemy == start:
		enemy = Vector2i(2, brow)
	g[bait] = "B"
	g[enemy] = "g"
	return {
		"id": "redirect", "title": "The Charger's Breach",
		"archetype": "Archetype 1 redirected aggression (break the barrier) — NESTS a dodge beat",
		"w": w, "h": h, "start": start, "end": end, "grid": g, "gate": gate,
		"gate_open_row": brow,   # only the impacted segment breaches
		"nests": ["dodge: step off the bait line at the enemy's commit"],
		"solve": "Stand on the bait (B) in the enemy's charge lane; DODGE as it commits; the enemy (g) slams the wall (X) and breaches it — cross through the hole to the end.",
		"shadow": "Aster+Peris: Peris plants a Hushbloom to stun g at the commit (no dodge window needed), or a Flure iron-decoy sets the charge line; same breach.",
		"legend": {"X": "breakable wall (blocks until an enemy charges it)", "g": "enemy (charges when baited)", "B": "bait tile (stand, then dodge)"},
	}

## PLANT AS TOOL (Archetype 2-C, climbvine) — a chasm you cannot cross. Grow a bridge. NESTS Archetype 4 (distract
## the patrol): a guard holds the fertile lip, so you lure it off with a flure before you can plant.
static func _build_vinebridge(rng: SeededRng) -> Dictionary:
	var w := _ri(rng, 12, 14)
	var h := _ri(rng, 8, 10)
	var g := _room(w, h)
	var start := Vector2i(1, h / 2)
	var end := Vector2i(w - 2, h / 2)
	g[start] = SYM_START
	g[end] = SYM_END
	var col := _ri(rng, w / 2 - 1, w / 2 + 1)
	var gate := _vgate(g, col, h, ":")
	var vrow := _ri(rng, 2, h - 3)
	var vine := Vector2i(col - 1, vrow)         # fertile lip against the chasm
	g[vine] = "V"
	var flure := Vector2i(_ri(rng, 2, col - 2), _ri(rng, 2, h - 3))
	var guard := Vector2i(col - 1, vrow + 1 if vrow + 1 < h - 1 else vrow - 1)
	if flure == start:
		flure = Vector2i(2, 2)
	g[flure] = "F"
	g[guard] = "g"
	return {
		"id": "vinebridge", "title": "The Lured Causeway",
		"archetype": "Archetype 2-C plant-as-tool (climbvine bridge) — NESTS Archetype 4 distract-the-patrol",
		"w": w, "h": h, "start": start, "end": end, "grid": g, "gate": gate,
		"gate_open_row": vrow,   # the vine bridges one lane
		"nests": ["A4 distract-the-patrol: pull the guard off the fertile lip"],
		"solve": "Fire the flure (F) to pull the guard (g) off the fertile lip; plant a climbvine at (V); it matures into a bridge over the chasm (:) — cross to the end.",
		"shadow": "Aster+Peris: Peris plants + BLOOMs the vine herself (Endo's home read not needed); Aster EMPs / times the guard's sweep instead of the flure.",
		"legend": {":": "chasm (blocks until bridged)", "V": "fertile lip (plant a climbvine -> bridge)", "F": "flure (lure the guard away)", "g": "patrol guard"},
	}

## TWO-CHARACTER SPLIT (Archetype 5) — a sealed door you cannot open alone. Two override plates in separate alcoves
## must be HELD at once, so the party must split across both stations — one body can't hold both.
static func _build_split(rng: SeededRng) -> Dictionary:
	var w := _ri(rng, 12, 14)
	var h := 10
	var g := _room(w, h)
	var start := Vector2i(1, h / 2)
	var end := Vector2i(w - 2, h / 2)
	g[start] = SYM_START
	g[end] = SYM_END
	var col := _ri(rng, w / 2, w / 2 + 1)
	var gate := _vgate(g, col, h, "=")
	# Two plates in the START region, far apart (top + bottom alcoves) — no single member reaches both.
	var p1 := Vector2i(_ri(rng, 2, col - 2), 1)
	var p2 := Vector2i(_ri(rng, 2, col - 2), h - 2)
	g[p1] = "P"
	g[p2] = "P"
	return {
		"id": "split", "title": "The Two-Hand Door",
		"archetype": "Archetype 5 two-character split (a door that needs two held plates)",
		"w": w, "h": h, "start": start, "end": end, "grid": g, "gate": gate,
		"nests": ["simultaneity: both plates held at once — the party must divide"],
		"solve": "Split the party: one member holds the top plate (P), another the bottom plate (P) at the same time; the sealed door (=) opens while both are held — the third crosses to the end, then the holders follow before it re-seals.",
		"shadow": "Aster+Peris (only two bodies): both must hold, leaving none to cross — so Aster hacks one plate to a TIMED latch (a short hold-open) while Peris holds the other, then dashes across in the window.",
		"legend": {"=": "sealed door (opens only while BOTH plates are held)", "P": "held override plate"},
	}

# --- the invariant: prove you cannot walk start->end without solving ------------------------------------------

## Flood-fill start->end under LOCKED passability (gate impassable) and SOLVED passability (gate passable). A valid
## chunk BLOCKS while locked and CONNECTS once solved. Uses the game's move rule (8-dir, a diagonal only when both
## orthogonals are open) so a 1-wide gate can't be diagonally squeezed. Returns {ok, locked_blocks, solved_connects}.
static func verify_gated(chunk: Dictionary) -> Dictionary:
	var gate_set := {}
	for c in chunk.get("gate", []):
		gate_set[c] = true
	var locked_reach := _reaches(chunk, gate_set, false, {})
	# On solve the gate opens. Default: the whole band opens (nothing left blocked). For a breach/bridge only the
	# IMPACTED row opens, so every OTHER gate cell stays blocked.
	var still_blocked := {}
	if chunk.has("gate_open_row"):
		var row := int(chunk["gate_open_row"])
		for c in chunk.get("gate", []):
			if (c as Vector2i).y != row:
				still_blocked[c] = true
	var solved_reach := _reaches(chunk, still_blocked, false, {})
	var locked_blocks := not locked_reach
	var solved_connects := solved_reach
	return {"ok": locked_blocks and solved_connects, "locked_blocks": locked_blocks, "solved_connects": solved_connects}

## Can start reach end? `blocked` = cells that are impassable on top of walls (the still-closed gate cells).
static func _reaches(chunk: Dictionary, blocked: Dictionary, _unused: bool, _u2: Dictionary) -> bool:
	var start: Vector2i = chunk["start"]
	var end: Vector2i = chunk["end"]
	var grid: Dictionary = chunk["grid"]
	var passable := func(c: Vector2i) -> bool:
		if not grid.has(c):
			return false
		return str(grid[c]) != SYM_WALL and not blocked.has(c)
	var seen := {start: true}
	var stack := [start]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		if c == end:
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var n: Vector2i = c + d
			if seen.has(n) or not passable.call(n):
				continue
			# Diagonal only if both orthogonal neighbours are open (no squeezing past a 1-wide gate).
			if d.x != 0 and d.y != 0:
				if not passable.call(Vector2i(c.x + d.x, c.y)) or not passable.call(Vector2i(c.x, c.y + d.y)):
					continue
			seen[n] = true
			stack.append(n)
	return false

# --- ASCII render ---------------------------------------------------------------------------------------------

static func render_ascii(chunk: Dictionary, verify := true) -> String:
	var w := int(chunk["w"])
	var h := int(chunk["h"])
	var grid: Dictionary = chunk["grid"]
	var out := "%s  [%s]\n" % [str(chunk.get("title", "Chunk")), str(chunk.get("archetype", ""))]
	for y in range(h):
		var row := ""
		for x in range(w):
			row += str(grid.get(Vector2i(x, y), " "))
		out += "  " + row + "\n"
	# Legend
	out += "  legend: S=start  E=end  #=wall  .=floor"
	for k in chunk.get("legend", {}).keys():
		out += "  %s=%s" % [k, str(chunk["legend"][k])]
	out += "\n"
	out += "  NESTS: %s\n" % ", ".join(chunk.get("nests", []))
	out += "  SOLVE:  %s\n" % str(chunk.get("solve", ""))
	out += "  SHADOW: %s\n" % str(chunk.get("shadow", ""))
	if verify:
		var v := verify_gated(chunk)
		out += "  GATED?  locked blocks start->end: %s | solving opens it: %s | %s\n" % [
			str(v["locked_blocks"]), str(v["solved_connects"]),
			"OK — you cannot walk through without solving" if v["ok"] else "BROKEN"]
	return out
