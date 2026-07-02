class_name ChunkGenerator
extends RefCounted

## THE ATOMIC UNIT — a CHUNK. Not a space you wander; a gated puzzle. Every chunk has:
##   1. a START point,
##   2. an END point,
##   3. a PUZZLE (a composition of nested archetypes, per reference-docs/design_archetypes.md) that must be solved,
##   4. and the hard invariant: you CANNOT walk start->end without solving it.
## A chunk owns a list of GATES (in solve order). Each gate is cells that are impassable until its mechanism is
## activated. Gates can NEST: gate N's mechanism sits past gate N-1, so you must solve N-1 to even attempt N — a
## puzzle to reach the puzzle. `verify` flood-fills (the game's 8-dir, no diagonal-squeeze rule) and asserts:
## start->end is BLOCKED while any gate is shut, OPEN once all are solved, AND each gate's mechanism is reachable
## only after the previous gate is open (the nesting order). Each chunk carries a Presented solve + a Shadow
## (Aster+Peris) solve, because a section without both is, per the docs, unfinished.

const SYM_WALL := "#"
const SYM_FLOOR := "."
const SYM_START := "S"
const SYM_END := "E"

const ARCHETYPES := ["holdfast", "redirect", "vinebridge", "split", "distract"]

# --- entry points ---------------------------------------------------------------------------------------------

## An ATOMIC chunk (one gate) for `archetype_id`.
static func generate(archetype_id: String, seed: int) -> Dictionary:
	var rng := SeededRng.new(seed ^ 0x0c00c11c)
	var w := _ri(rng, 12, 14)
	var h := _ri(rng, 8, 10)
	var g := _room(w, h)
	var start := Vector2i(1, h / 2)
	g[start] = SYM_START
	var gate_col := _ri(rng, w / 2 - 1, w / 2 + 1)
	var gate := _stage(g, 1, gate_col, gate_col, h, archetype_id, rng)
	var end := Vector2i(w - 2, h / 2)
	g[end] = SYM_END
	return _finish({
		"id": archetype_id, "w": w, "h": h, "start": start, "end": end, "grid": g, "gates": [gate],
	})

## A NESTED chunk: a chain of gated chambers (`stages` = archetype ids, in solve order). end sits behind ALL of
## them; each gate's mechanism is in its own chamber, reachable only after the previous gate opens.
static func compose(stages: Array, seed: int) -> Dictionary:
	var rng := SeededRng.new(seed ^ 0x0c00c11c)
	var cw := 4                                   # chamber interior width
	var n := stages.size()
	var w := 1 + cw + n * (1 + cw) + 1            # borders + chamber0 + n*(gate + chamber)
	var h := 9
	var g := _room(w, h)
	var start := Vector2i(1, h / 2)
	g[start] = SYM_START
	var gates: Array = []
	var cx := 1                                   # interior x of the current chamber
	for i in range(n):
		var chamber_x0 := cx
		var gate_col := chamber_x0 + cw           # the gate sits right after this chamber
		gates.append(_stage(g, chamber_x0, gate_col, gate_col, h, str(stages[i]), rng))
		cx = gate_col + 1
	var end := Vector2i(w - 2, h / 2)
	g[end] = SYM_END
	return _finish({
		"id": "nested", "w": w, "h": h, "start": start, "end": end, "grid": g, "gates": gates,
	})

# --- one gate + its mechanism (an archetype), placed in [chamber_x0, gate_col) with the gate band at gate_col ---

static func _stage(g: Dictionary, chamber_x0: int, chamber_x1: int, gate_col: int, h: int, arch: String, rng: SeededRng) -> Dictionary:
	var cells := _vgate(g, gate_col, h, _gate_sym(arch))
	var row := _ri(rng, 2, h - 3)
	var mech := Vector2i(gate_col - 1, row)       # mechanism against the gate, inside the chamber
	var elements: Array = []
	match arch:
		"holdfast":
			mech = Vector2i(clampi(chamber_x0 + 1, chamber_x0, gate_col - 1), 1)
			g[mech] = "O"
			var guard := Vector2i(clampi(chamber_x0 + 1, chamber_x0, gate_col - 1), _ri(rng, 3, h - 3))
			if guard != mech:
				g[guard] = "g"
				elements.append({"sym": "g", "cell": guard})
			return {"cells": cells, "open_row": -1, "mechanism": mech, "sym": "~", "arch": arch,
				"elements": [{"sym": "O", "cell": mech}] + elements,
				"role": "held flow-override — hold it and the wash stops"}
		"redirect":
			g[mech] = "B"
			var enemy := Vector2i(clampi(chamber_x0, chamber_x0, gate_col - 2), row)
			if enemy == mech:
				enemy = Vector2i(chamber_x0, row)
			g[enemy] = "g"
			return {"cells": cells, "open_row": row, "mechanism": mech, "sym": "X", "arch": arch,
				"elements": [{"sym": "B", "cell": mech}, {"sym": "g", "cell": enemy}],
				"role": "bait tile — stand, then dodge as the enemy charges the wall"}
		"vinebridge":
			g[mech] = "V"
			var flure := Vector2i(clampi(chamber_x0, chamber_x0, gate_col - 2), clampi(row + 1, 1, h - 2))
			if g.get(flure) == SYM_FLOOR:
				g[flure] = "F"
			return {"cells": cells, "open_row": row, "mechanism": mech, "sym": ":", "arch": arch,
				"elements": [{"sym": "V", "cell": mech}, {"sym": "F", "cell": flure}],
				"role": "fertile lip — plant a climbvine; it bridges the chasm"}
		"split":
			var p1 := Vector2i(clampi(chamber_x0 + 1, chamber_x0, gate_col - 1), 1)
			var p2 := Vector2i(clampi(chamber_x0 + 1, chamber_x0, gate_col - 1), h - 2)
			g[p1] = "P"
			g[p2] = "P"
			return {"cells": cells, "open_row": -1, "mechanism": p1, "sym": "=", "arch": arch,
				"elements": [{"sym": "P", "cell": p1}, {"sym": "P", "cell": p2}],
				"role": "held plates — both must be held at once (split the party)"}
		"distract":
			# The Watched Gap kit, generated: the gate is a watched LANE (!) — topologically crossable in the
			# real game but enforcement is DETECTION (spotted = swept to start), so the model treats it as
			# blocked until the sentry commits away. Sentry (s) watches from the far mouth; the flure (F) sits
			# in a pocket reachable WITHOUT entering the lane; the conceal pocket (c) is the Shadow's stage.
			mech = Vector2i(clampi(chamber_x0 + 1, chamber_x0, gate_col - 1), 1)
			g[mech] = "F"
			var sentry := Vector2i(gate_col + 1, row)
			if g.get(sentry) == SYM_FLOOR:
				g[sentry] = "s"
			var conceal := Vector2i(clampi(chamber_x0 + 1, chamber_x0, gate_col - 1), h - 2)
			var elems: Array = [{"sym": "F", "cell": mech}, {"sym": "s", "cell": sentry}]
			if g.get(conceal) == SYM_FLOOR:
				g[conceal] = "c"
				elems.append({"sym": "c", "cell": conceal})
			return {"cells": cells, "open_row": -1, "mechanism": mech, "sym": "!", "arch": arch,
				"elements": elems,
				"role": "watched lane — tend the flure so the sentry commits off its watch, then cross"}
	# default: a plain wall + a lever
	g[mech] = "L"
	return {"cells": cells, "open_row": -1, "mechanism": mech, "sym": "=", "arch": "lever",
		"elements": [{"sym": "L", "cell": mech}], "role": "lever"}

static func _gate_sym(arch: String) -> String:
	match arch:
		"holdfast": return "~"
		"redirect": return "X"
		"vinebridge": return ":"
		"split": return "="
		"distract": return "!"
	return "="

## Track D: the gate MECHANISM is a TYPED object from a section-keyed family (BUILD_STRATEGY.md), never an
## opaque callback — so the verifier (and later the stretch assembler) can check "this section's mechanisms
## are drawn from its district's native family" the same way it checks topology. `register` names which
## perception register (P2) reads the mechanism best — the raw material of a PERCEPTION_LOCK.
static func mechanism_type(arch: String) -> Dictionary:
	match arch:
		"holdfast": return {"family": "terminal", "subtype": "flow", "register": "survival/held (Endo)"}
		"distract": return {"family": "flora", "subtype": "flure", "register": "WHERE (Peris)"}
		"vinebridge": return {"family": "flora", "subtype": "climbvine", "register": "WHERE (Peris)"}
		"split": return {"family": "plate", "subtype": "held_pair", "register": "co-op (two bodies)"}
		"redirect": return {"family": "bait", "subtype": "charge_line", "register": "dodge (mechanic unbuilt)"}
	return {"family": "lever", "subtype": "plain", "register": "any"}

# --- metadata + solve/shadow text -----------------------------------------------------------------------------

static func _finish(chunk: Dictionary) -> Dictionary:
	var gates: Array = chunk["gates"]
	var titles := {"holdfast": "Holdfast Crossing", "redirect": "The Charger's Breach", "vinebridge": "The Lured Causeway", "split": "The Two-Hand Door", "distract": "The Watched Gap (atom)"}
	if gates.size() == 1:
		var a := str(gates[0]["arch"])
		chunk["title"] = titles.get(a, "Chunk")
		chunk["archetype"] = _arch_label(a)
	else:
		var labels: Array = []
		for gt in gates:
			labels.append(str(gt["arch"]))
		chunk["title"] = "Nested: " + " -> ".join(labels)
		chunk["archetype"] = "%d gates, each behind the last (nested)" % gates.size()
	chunk["solve"] = _solve_text(gates)
	chunk["shadow"] = _shadow_text(gates)
	chunk["legend"] = _legend(gates)
	return chunk

static func _arch_label(a: String) -> String:
	match a:
		"holdfast": return "held-override wash crossing (channels) — NESTS A7 stealth-and-time"
		"redirect": return "Archetype 1 redirected aggression (break the barrier) — NESTS a dodge beat"
		"vinebridge": return "Archetype 2-C plant-as-tool (climbvine bridge) — NESTS Archetype 4 distract-the-patrol"
		"split": return "Archetype 5 two-character split (a door that needs two held plates)"
		"distract": return "Archetype 4 distract-the-patrol — PROVEN in-engine (--test-distract-gate)"
	return a

## Whether this archetype can be built from mechanics that EXIST TODAY, and which real mechanic backs it. The
## flood-fill invariant proves a chunk's TOPOLOGY (you can't walk it unsolved); it does NOT prove the solve is
## mechanically possible — that only a real in-engine playtest can. This keeps the generator honest about which
## archetypes have a real mechanic vs. which are design placeholders waiting on one.
static func mechanic(a: String) -> Dictionary:
	match a:
		"holdfast": return {"buildable": true, "mechanic": "wash + HELD override + sweep (wash_relay_chunk) — real, tested"}
		"vinebridge": return {"buildable": false, "mechanic": "a climbvine that BRIDGES a chasm — flora-causeway exists in wash_relay, standalone bridge NOT verified"}
		"split": return {"buildable": true, "mechanic": "two HELD plates + a dynamic_blocker gate — real (hold interactable + grid)"}
		"distract": return {"buildable": true, "mechanic": "real enemy detection (LOS-blocked) + Flure lure (lure_relay_chunk) — real, tested"}
		"redirect": return {"buildable": false, "mechanic": "an enemy that BREAKS a structure on charge impact — NO such mechanic exists (charges don't collide with structures)"}
	return {"buildable": false, "mechanic": "unknown"}

static func _solve_step(a: String) -> String:
	match a:
		"holdfast": return "sneak past the guard to the override (O) and HOLD it so the wash (~) calms, then cross"
		"redirect": return "bait the enemy (g) at (B) and dodge so it breaches the wall (X)"
		"vinebridge": return "flure (F) the guard off the lip, plant a climbvine at (V) to bridge the chasm (:)"
		"split": return "split the party to hold BOTH plates (P) at once so the door (=) opens"
		"distract": return "tend the flure (F) so the sentry (s) commits off its watch, fall back, cross the lane (!)"
	return "activate the mechanism"

static func _solve_text(gates: Array) -> String:
	if gates.size() == 1:
		return _solve_step(str(gates[0]["arch"])).capitalize() + "."
	var parts: Array = []
	for i in range(gates.size()):
		parts.append("(%d) %s" % [i + 1, _solve_step(str(gates[i]["arch"]))])
	return "In order, each behind the last: " + "; then ".join(parts) + " — only then is the end reachable."

static func _shadow_text(gates: Array) -> String:
	var a := str(gates[0]["arch"])
	match a:
		"holdfast": return "Aster+Peris: Aster TRACE times the wash's dark window; Peris BLOOM causeways one lane — cross unheld."
		"redirect": return "Aster+Peris: Peris Hushbloom-stuns the charger at the commit (no dodge window)."
		"vinebridge": return "Aster+Peris: Peris plants+BLOOMs the vine herself; Aster times/EMPs the guard instead of the flure."
		"split": return "Aster+Peris (two bodies): Aster hacks one plate to a timed latch while Peris holds the other, then dashes."
		"distract": return "Aster+Peris: Aster TRACE reads the sentry's beat; stage in the conceal pocket (c) and slip the look-away window — no flure spent."
	return "Aster+Peris compose the same skeleton with substitute variants."

static func _legend(gates: Array) -> Dictionary:
	var syms := {
		"~": "wash (blocks; calm only while O is HELD)", "O": "held flow-override", "g": "enemy / guard",
		"X": "breakable wall (an enemy must charge it)", "B": "bait tile (stand, then dodge)",
		":": "chasm (blocks until bridged)", "V": "fertile lip (plant a climbvine)", "F": "flure (lure the guard)",
		"=": "sealed door (both plates held)", "P": "held plate",
		"!": "watched lane (cross unsolved = spotted, swept to start)", "s": "sentry (LOS-gated watcher)",
		"c": "conceal pocket (CONCEAL_MEDIUM — the Shadow's stage)",
	}
	var out := {}
	for gt in gates:
		out[str(gt["sym"])] = syms.get(str(gt["sym"]), "gate")
		for e in gt.get("elements", []):
			out[str(e["sym"])] = syms.get(str(e["sym"]), "element")
	return out

# --- layout primitives ----------------------------------------------------------------------------------------

static func _ri(rng: SeededRng, a: int, b: int) -> int:
	return int(rng.call("randi_range", a, b))

static func _room(w: int, h: int) -> Dictionary:
	var g := {}
	for y in range(h):
		for x in range(w):
			g[Vector2i(x, y)] = SYM_WALL if (x == 0 or y == 0 or x == w - 1 or y == h - 1) else SYM_FLOOR
	return g

static func _vgate(g: Dictionary, col: int, h: int, sym: String) -> Array:
	var cells: Array = []
	for y in range(1, h - 1):
		g[Vector2i(col, y)] = sym
		cells.append(Vector2i(col, y))
	return cells

# --- the invariant: prove you cannot walk start->end without solving, in order --------------------------------

## Returns {ok, locked_blocks, solved_connects, ordering_ok}. locked_blocks: end unreachable with any gate shut.
## solved_connects: end reachable with all open. ordering_ok: gate i's mechanism is reachable only after gate i-1
## opens (a puzzle to reach the puzzle) — the nesting property.
static func verify(chunk: Dictionary) -> Dictionary:
	var gates: Array = chunk["gates"]
	var n := gates.size()
	var all_closed := _flags(n, -1)            # nothing open
	var all_open := _flags(n, n)               # everything open
	var locked_blocks := not _reach(chunk, chunk["end"], all_closed)
	var solved_connects := _reach(chunk, chunk["end"], all_open)
	var ordering_ok := true
	for i in range(n):
		var mech: Vector2i = gates[i]["mechanism"]
		# gates 0..i-1 open -> mechanism i reachable.
		if not _reach(chunk, mech, _flags(n, i)):
			ordering_ok = false
		# gate i-1 NOT open (only 0..i-2 open) -> mechanism i must be UNreachable (else it isn't gated by i-1).
		if i > 0 and _reach(chunk, mech, _flags(n, i - 1)):
			ordering_ok = false
	return {"ok": locked_blocks and solved_connects and ordering_ok,
		"locked_blocks": locked_blocks, "solved_connects": solved_connects, "ordering_ok": ordering_ok}

## Open flags: gates with index < open_upto are OPEN.
static func _flags(n: int, open_upto: int) -> Array:
	var f: Array = []
	for i in range(n):
		f.append(i < open_upto)
	return f

static func _reach(chunk: Dictionary, target: Vector2i, open_flags: Array) -> bool:
	var grid: Dictionary = chunk["grid"]
	var gates: Array = chunk["gates"]
	var blocked := {}
	for i in range(gates.size()):
		var gt: Dictionary = gates[i]
		var is_open: bool = open_flags[i]
		var open_row := int(gt.get("open_row", -1))
		for c in gt["cells"]:
			if not is_open:
				blocked[c] = true
			elif open_row >= 0 and (c as Vector2i).y != open_row:
				blocked[c] = true   # a breach/bridge opens only its impacted row
	var start: Vector2i = chunk["start"]
	var passable := func(c: Vector2i) -> bool:
		return grid.has(c) and str(grid[c]) != SYM_WALL and not blocked.has(c)
	var seen := {start: true}
	var stack := [start]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		if c == target:
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var nc: Vector2i = c + d
			if seen.has(nc) or not passable.call(nc):
				continue
			if d.x != 0 and d.y != 0 and (not passable.call(Vector2i(c.x + d.x, c.y)) or not passable.call(Vector2i(c.x, c.y + d.y))):
				continue
			seen[nc] = true
			stack.append(nc)
	return false

# --- lock-before-key (Dormans; LEVEL_DESIGN_RESEARCH.md) --------------------------------------------------------

## The player must ENCOUNTER the lock before the key: for each gate i (with gates 0..i-1 open), the walk
## distance at which the gate first becomes VISIBLE must not exceed the distance to its mechanism. Key-first
## play degrades into indiscriminate collecting; a key found after its lock reads as an answer, not a chore.
## Visibility = a clear straight row/column ray to a gate cell over non-wall cells (the chambers are boxes,
## so axis rays are an honest sight model for the sketch layer).
static func lock_before_key(chunk: Dictionary) -> Dictionary:
	var gates: Array = chunk["gates"]
	var per_gate: Array = []
	var all_ok := true
	for i in range(gates.size()):
		var dists := _bfs_distances(chunk, _flags(gates.size(), i))
		var mech: Vector2i = gates[i]["mechanism"]
		var key_d := int(dists.get(mech, 1 << 30))
		var lock_d := 1 << 30
		for c in dists.keys():
			if int(dists[c]) < lock_d and _sees_any(chunk, c, gates[i]["cells"]):
				lock_d = int(dists[c])
		var ok := lock_d <= key_d and key_d < (1 << 30)
		per_gate.append({"gate": i, "arch": str(gates[i]["arch"]), "lock_dist": lock_d, "key_dist": key_d, "ok": ok})
		all_ok = all_ok and ok
	return {"ok": all_ok, "gates": per_gate}

static func _bfs_distances(chunk: Dictionary, open_flags: Array) -> Dictionary:
	var grid: Dictionary = chunk["grid"]
	var gates: Array = chunk["gates"]
	var blocked := {}
	for i in range(gates.size()):
		if not bool(open_flags[i]):
			for c in gates[i]["cells"]:
				blocked[c] = true
	var start: Vector2i = chunk["start"]
	var dists := {start: 0}
	var queue := [start]
	var qi := 0
	while qi < queue.size():
		var c: Vector2i = queue[qi]
		qi += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc: Vector2i = c + d
			if dists.has(nc) or not grid.has(nc) or str(grid[nc]) == SYM_WALL or blocked.has(nc):
				continue
			dists[nc] = int(dists[c]) + 1
			queue.append(nc)
	return dists

## Clear axis ray from `from` to any of `targets` (over non-wall cells; the target cell itself counts).
static func _sees_any(chunk: Dictionary, from: Vector2i, targets: Array) -> bool:
	var grid: Dictionary = chunk["grid"]
	var target_set := {}
	for t in targets:
		target_set[t] = true
	if target_set.has(from):
		return true
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = from + (d as Vector2i)
		while grid.has(c):
			if target_set.has(c):
				return true
			if str(grid[c]) == SYM_WALL:
				break
			c += d as Vector2i
	return false

# --- the principle report card ----------------------------------------------------------------------------------

## Grade a generated chunk against the MACHINE-CHECKABLE principles (DESIGN_PRINCIPLES.md). Honest about what
## is verified vs merely authored: topology gating, nesting order, and lock-before-key are PROVEN here; the
## Shadow is prose until the ability-ablation verifier lands (Track B); buildability comes from the ledger.
static func report_card(chunk: Dictionary) -> Dictionary:
	var v := verify(chunk)
	var lbk := lock_before_key(chunk)
	var gates: Array = chunk["gates"]
	var blocked_archs: Array = []
	var registers := {}
	var mechanisms: Array = []
	for gt in gates:
		var a := str(gt["arch"])
		if not bool(mechanic(a)["buildable"]):
			blocked_archs.append(a)
		var mt := mechanism_type(a)
		registers[str(mt["register"])] = true
		mechanisms.append("%s/%s" % [str(mt["family"]), str(mt["subtype"])])
	return {
		"gated": v,                                       # P8: cannot walk start->end unsolved (PROVEN)
		"lock_before_key": lbk,                           # research: encounter the lock first (PROVEN)
		"buildable": blocked_archs.is_empty(),            # P6: every gate backed by a real mechanic
		"blocked_archetypes": blocked_archs,
		"mechanisms": mechanisms,                         # Track D: typed, section-keyable
		"registers": registers.keys(),                    # P2 raw material (composite = >=2 registers)
		"two_registers": registers.size() >= 2,           # P2: a legit SECTION composes two (atoms may be 1)
		"shadow_verified": false,                         # P10: prose only until the ablation slot (Track B2)
		"ok": bool(v["ok"]) and bool(lbk["ok"]) and blocked_archs.is_empty(),
	}

static func render_report(chunk: Dictionary) -> String:
	var r := report_card(chunk)
	var out := "  REPORT CARD (vs DESIGN_PRINCIPLES.md):\n"
	out += "    P8 gated (proven):        %s\n" % ("PASS" if bool(r["gated"]["ok"]) else "FAIL " + str(r["gated"]))
	var lbk: Dictionary = r["lock_before_key"]
	var lbk_bits: Array = []
	for gd in lbk["gates"]:
		lbk_bits.append("g%d:%s(lock@%d key@%d)" % [int(gd["gate"]), "ok" if bool(gd["ok"]) else "VIOLATED", int(gd["lock_dist"]), int(gd["key_dist"])])
	out += "    lock-before-key (proven): %s  [%s]\n" % ["PASS" if bool(lbk["ok"]) else "FAIL", ", ".join(lbk_bits)]
	out += "    P6 buildable today:       %s%s\n" % ["PASS" if bool(r["buildable"]) else "BLOCKED", "" if r["blocked_archetypes"].is_empty() else " — " + str(r["blocked_archetypes"])]
	out += "    Track D mechanisms:       %s\n" % ", ".join(r["mechanisms"])
	out += "    P2 registers touched:     %s%s\n" % [", ".join(r["registers"]), "  (composite: 2+ registers)" if bool(r["two_registers"]) else "  (single-register ATOM — a full section should compose two)"]
	out += "    P10 shadow:               authored prose only — machine ablation check pending (Track B2)\n"
	out += "    VERDICT:                  %s\n" % ("SHIPPABLE SKETCH" if bool(r["ok"]) else "HOLD — see failures above")
	return out

# --- ASCII render ---------------------------------------------------------------------------------------------

static func render_ascii(chunk: Dictionary, show_verify := true) -> String:
	var w := int(chunk["w"])
	var h := int(chunk["h"])
	var grid: Dictionary = chunk["grid"]
	var out := "%s  [%s]\n" % [str(chunk.get("title", "Chunk")), str(chunk.get("archetype", ""))]
	for y in range(h):
		var row := ""
		for x in range(w):
			row += str(grid.get(Vector2i(x, y), " "))
		out += "  " + row + "\n"
	out += "  legend: S=start  E=end  #=wall  .=floor"
	for k in chunk.get("legend", {}).keys():
		out += "  %s=%s" % [k, str(chunk["legend"][k])]
	out += "\n  SOLVE:  %s\n" % str(chunk.get("solve", ""))
	out += "  SHADOW: %s\n" % str(chunk.get("shadow", ""))
	# Honesty: does a real mechanic back each gate's solve? (topology gating != mechanically solvable)
	for gt in chunk.get("gates", []):
		var m := mechanic(str(gt.get("arch", "")))
		out += "  MECHANIC (%s): %s — %s\n" % [str(gt.get("arch", "")), "BUILDABLE TODAY" if m["buildable"] else "NOT BUILDABLE YET", str(m["mechanic"])]
	if show_verify:
		var v := verify(chunk)
		out += "  GATED?  locked blocks start->end: %s | all solved opens it: %s | nesting order enforced: %s | %s\n" % [
			str(v["locked_blocks"]), str(v["solved_connects"]), str(v["ordering_ok"]),
			"OK — no walkthrough without solving, in order" if v["ok"] else "BROKEN"]
	return out
