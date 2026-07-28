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

## An ATOMIC chunk (one gate) for `archetype_id` (accepts "arch:variant", e.g. "distract:patrol").
static func generate(archetype_id: String, seed: int) -> Dictionary:
	return compose([archetype_id], seed)

## A NESTED chunk: a chain of gated chambers (`stages` = archetype ids, in solve order; a distract stage may
## pin its variant as "distract:lure|patrol|twin", otherwise the seed picks). end sits behind ALL of them;
## each gate's mechanism is in its own chamber, reachable only after the previous gate opens. VARIETY is
## seeded: chamber widths vary, watched-gap rows drift off-center, and chambers grow cover PILLARS — pillars
## are reverted wholesale if they break the gated invariant (verified, never hoped).
static func compose(stages: Array, seed: int) -> Dictionary:
	# Attempt loop: a layout must pass gated + lock-before-key + SAFE-PASSAGE (fans must leave regroup
	# ground between gates). A failing roll re-rolls with a derived seed — deterministic remediation, and
	# the last attempt is returned regardless so the report card shows the failure honestly.
	var chunk: Dictionary = {}
	for attempt in range(4):
		chunk = _compose_attempt(stages, seed ^ (attempt * 0x9e3779b9))
		var sp := safe_passage(chunk)
		if bool(verify(chunk)["ok"]) and bool(lock_before_key(chunk)["ok"]) and bool(sp["ok"]):
			break
	return chunk

static func _compose_attempt(stages: Array, seed: int) -> Dictionary:
	var rng := SeededRng.new(seed ^ 0x0c00c11c)
	var n := stages.size()
	var h := 11
	var widths: Array = []
	var w := 2                                    # borders
	for i in range(n + 1):
		var stage_arch := str(stages[i]).split(":")[0] if i < n else ""
		# Watched races need a real three-body staging footprint plus approach space.
		# Six or seven cells keeps every possible lateral slot at least four cells
		# from the post while retaining seeded length variety.
		var cw := _ri(rng, 6, 7) if stage_arch == "distract" else _ri(rng, 4, 6)
		widths.append(cw)
		w += cw + (1 if i < n else 0)             # chamber + its gate column
	var g := _room(w, h)
	var start := Vector2i(1, h / 2)
	g[start] = SYM_START
	var gates: Array = []
	var chamber_spans: Array = []                 # [{x0, x1, path_blockers}] interiors, for pillar seeding
	var cx := 1
	for i in range(n):
		var chamber_x0 := cx
		var gate_col := chamber_x0 + int(widths[i])
		var parts := str(stages[i]).split(":")
		var arch := parts[0]
		var variant := parts[1] if parts.size() > 1 else ""
		# A distract chamber is a formation-and-timing test. Random blocking pillars turn
		# that into an unpreviewed navigation test: a side member can be braided through
		# the watch fan even though the generated launch and centre route are safe. Keep
		# portable decoration there, but reserve the whole executable chamber topology.
		chamber_spans.append({
			"x0": chamber_x0,
			"x1": gate_col - 1,
			"path_blockers": arch != "distract",
		})
		gates.append(_stage(g, chamber_x0, gate_col, gate_col, h, arch, rng, variant))
		cx = gate_col + 1
	chamber_spans.append({"x0": cx, "x1": w - 2, "path_blockers": true})
	var end := Vector2i(w - 2, h / 2)
	g[end] = SYM_END
	var chunk := {
		"id": "nested" if n > 1 else str(stages[0]), "w": w, "h": h,
		"start": start, "end": end, "grid": g, "gates": gates,
	}
	_seed_pillars(chunk, chamber_spans, rng)
	return _finish(chunk)

## Cover pillars: 0-2 single-cell wall blobs per chamber, seeded. They break sightlines (the walls are
## opaque in the built room) and give crossings texture. Placed only on bare floor, then the WHOLE set is
## reverted if verify() reports the chunk broken — variety never buys a broken invariant.
static func _seed_pillars(chunk: Dictionary, spans: Array, rng: SeededRng) -> void:
	var g: Dictionary = chunk["grid"]
	var h := int(chunk["h"])
	var placed: Array = []
	# A distract gate's east-side comprehension landing is part of its executable
	# three-body route. Final/next-chamber decoration used to place a pillar on one
	# of those slots; the generic rally resolver silently shifted that character,
	# while the authored pad and strategy proof described a different solution.
	var reserved := {}
	for gate_v in (chunk.get("gates", []) as Array):
		var gate := gate_v as Dictionary
		if str(gate.get("arch", "")) != "distract":
			continue
		for gate_cell_v in (gate.get("cells", []) as Array):
			var gate_cell := gate_cell_v as Vector2i
			for east_steps in range(1, 3):
				reserved[gate_cell + Vector2i(east_steps, 0)] = true
	for span in spans:
		if not bool(span.get("path_blockers", true)):
			continue
		var x0 := int(span["x0"])
		var x1 := int(span["x1"])
		if x1 - x0 < 3:
			continue
		for _p in range(_ri(rng, 0, 2)):
			var cell := Vector2i(_ri(rng, x0 + 1, x1 - 1), _ri(rng, 2, h - 3))
			if not reserved.has(cell) and str(g.get(cell, "")) == SYM_FLOOR \
					and absi(cell.y - h / 2) >= 1:
				g[cell] = SYM_WALL
				placed.append(cell)
	if placed.is_empty():
		return
	var v := verify(chunk)
	var lbk := lock_before_key(chunk)
	var sp := safe_passage(chunk)
	if not (bool(v["ok"]) and bool(lbk["ok"]) and bool(sp["ok"])):
		for cell in placed:
			g[cell] = SYM_FLOOR

# --- one gate + its mechanism (an archetype), placed in [chamber_x0, gate_col) with the gate band at gate_col ---

static func _stage(g: Dictionary, chamber_x0: int, chamber_x1: int, gate_col: int, h: int, arch: String, rng: SeededRng, variant := "") -> Dictionary:
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
			# The Watched Gap kit, generated, in three VARIANTS (all backed by the same proven mechanics).
			# Geometry rule for all: the gate is a GAP in a WALL band — the watched lane (!) is only a few
			# rows; the rest of the column is wall. The wall makes the sentry's sight honest (it watches
			# THROUGH its gap; the chambers are blind to it) and the sentry POSTS IN the gap it guards.
			var v: String = variant if variant != "" else str(["lure", "patrol", "twin"][_ri(rng, 0, 2)])
			match v:
				"patrol":
					# WHEN-register gate: no flure. A TALLER watched gap (6 rows) with the sentry pacing
					# inside it — the window is crossing the far rows while it walks the other end. A
					# carved side-alcove was tried first and verify() caught it as a hole straight
					# through the 1-cell band; the tall-gap form keeps the invariant by construction.
					# Mechanism = the conceal pocket (the STAGING spot — you solve this gate by being in
					# position when the beat opens).
					var g_mid := _ri(rng, 3, 5)
					var lane_p: Array = []
					for c0 in cells:
						var cyp := (c0 as Vector2i).y
						if cyp >= g_mid - 2 and cyp <= g_mid + 4:
							lane_p.append(c0)
						else:
							g[c0] = SYM_WALL
					for lc in lane_p:
						g[lc] = "!"
					var sentry_p := Vector2i(gate_col, g_mid)
					g[sentry_p] = "s"
					var far := Vector2i(gate_col, g_mid + 4)
					# The green cell is the actual launch position for the readable beat: safely
					# west of the post and on the row opposite its far endpoint.  An arbitrary
					# bottom-corner pocket made the sign and the executable solution disagree.
					# Keep the three-body launch on the far side of the patrol beat.
					# The opening extends one extra row north so every formation slot
					# has its own lane instead of serializing at the wall.
					var conceal_p := Vector2i(chamber_x0 + 1, g_mid - 1)
					g[conceal_p] = "c"
					return {"cells": lane_p, "open_row": -1, "mechanism": conceal_p, "sym": "!", "arch": arch,
						"variant": "patrol", "patrol_far": far,
						"elements": [{"sym": "s", "cell": sentry_p}, {"sym": "c", "cell": conceal_p}],
						"role": "patrolled gap — prepare on the launch, read the far beat, cross the opposite rows"}
				"twin":
					# Two gaps, two watchers, ONE flure: luring pulls the NORTH sentry only — its gap
					# clears while the south watcher keeps its own. Crossing the wrong gap still bites.
					var lane_n: Array = []
					var lane_s: Array = []
					for c0 in cells:
						var cy := (c0 as Vector2i).y
						if cy >= 3 and cy <= 5:
							lane_n.append(c0)
						elif cy >= h - 4 and cy <= h - 2:
							lane_s.append(c0)
						else:
							g[c0] = SYM_WALL
					for lc in lane_n + lane_s:
						g[lc] = "!"
					var s_n := Vector2i(gate_col, 3)
					var s_s := Vector2i(gate_col, h - 3)
					g[s_n] = "s"
					g[s_s] = "s"
					mech = Vector2i(clampi(chamber_x0 + 1, chamber_x0, gate_col - 1), 1)
					g[mech] = "F"
					# Launch beside the linked NORTH lane, far enough west that a three-body
					# formation remains outside both posted watch fans.  The south lane stays
					# visibly red and has no equivalent launch affordance.
					# The gold formation is one row away from its flure and three
					# rows from the unlinked red watcher. Its three slots line up
					# exactly with rows 3..5 of the north opening.
					var conceal_t := Vector2i(chamber_x0 + 1, s_n.y + 1)
					var elems_t: Array = [{"sym": "F", "cell": mech}, {"sym": "s", "cell": s_n},
						{"sym": "s", "cell": s_s}, {"sym": "c", "cell": conceal_t}]
					if g.get(conceal_t) == SYM_FLOOR:
						g[conceal_t] = "c"
					return {"cells": lane_n + lane_s, "open_row": -1, "mechanism": mech, "sym": "!", "arch": arch,
						"variant": "twin", "lured_sentry": s_n, "other_sentry": s_s,
						"elements": elems_t,
						"role": "twin watch — rally gold, Peris tends and returns; cross NORTH while south stays hot"}
				_:
					# The classic: flure pocket, conceal pocket, static in-gap sentry. Gap row drifts.
					var flip := _ri(rng, 0, 1) == 1     # seeded N/S flip of flure vs conceal pockets
					var fy := 1 if not flip else h - 2
					# Bound the causal path itself. If a watcher can spawn at the far
					# opposite edge from its flure, no legal gear that is faster than
					# walk and slower than RUN can make the return race meaningful.
					# Keeping the post 2..4 rows from the endpoint preserves seeded
					# variation while guaranteeing the taught speed choice can exist.
					var g_mid_l := _ri(rng, fy + 2, mini(fy + 4, h - 4)) \
						if fy < h / 2 else _ri(rng, maxi(3, fy - 4), fy - 2)
					var launch_row := g_mid_l + (1 if fy < g_mid_l else -1)
					# Centre the executable opening on the formation, not the watcher.
					# The watcher still posts in its edge cell while all three party
					# lanes remain open and at least two cells from the flure endpoint.
					var lane_l := _carve_gap(g, cells, gate_col, launch_row)
					var sentry_l := Vector2i(gate_col, g_mid_l)
					g[sentry_l] = "s"
					# Put the flure in the chamber's rear side pocket.  The watcher then
					# traverses a visible side route instead of parking on the party's gap
					# approach, and Peris's launch-to-flure trip stays short and readable.
					mech = Vector2i(clampi(chamber_x0 + 1, chamber_x0, gate_col - 1), fy)
					g[mech] = "F"
					# This is not decorative concealment: it is the launch/regroup state that
					# makes the causal loop executable. It is centered on the same three-row
					# opening and displaced away from the flure's distracted detection bubble.
					var conceal_l := Vector2i(chamber_x0 + 1, launch_row)
					var elems_l: Array = [{"sym": "F", "cell": mech}, {"sym": "s", "cell": sentry_l},
						{"sym": "c", "cell": conceal_l}]
					if g.get(conceal_l) == SYM_FLOOR:
						g[conceal_l] = "c"
					return {"cells": lane_l, "open_row": -1, "mechanism": mech, "sym": "!", "arch": arch,
						"variant": "lure",
						"elements": elems_l,
						"role": "watched gap — rally green; Peris tends and returns; sprint as the watcher races home"}
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
static func mechanism_type(arch: String, variant := "") -> Dictionary:
	match arch:
		"holdfast": return {"family": "terminal", "subtype": "flow", "register": "survival/held (Endo)"}
		"distract":
			if variant == "patrol":
				# No object at all: the mechanism is the BEAT — pure WHEN register (Archetype 7 shading).
				return {"family": "timing", "subtype": "patrol_window", "register": "WHEN (Aster)"}
			return {"family": "flora", "subtype": "flure", "register": "WHERE (Peris)"}
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
			var lbl := str(gt["arch"])
			if str(gt.get("variant", "")) != "":
				lbl += ":" + str(gt["variant"])
			labels.append(lbl)
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

static func _solve_step(gt: Dictionary) -> String:
	var a := str(gt["arch"])
	match a:
		"holdfast": return "sneak past the guard to the override (O) and HOLD it so the wash (~) calms, then cross"
		"redirect": return "bait the enemy (g) at (B) and dodge so it breaches the wall (X)"
		"vinebridge": return "flure (F) the guard off the lip, plant a climbvine at (V) to bridge the chasm (:)"
		"split": return "split the party to hold BOTH plates (P) at once so the door (=) opens"
		"distract":
			match str(gt.get("variant", "lure")):
				"patrol": return "stage in the pocket (c), read the sentry's patrol beat, cross the lane (!) in its look-away"
				"twin": return "tend the flure (F) — it pulls ONLY the north watcher; cross the NORTH gap while the south one keeps its own"
				_: return "tend the flure (F) so the sentry (s) commits off its watch, fall back, cross the lane (!)"
	return "activate the mechanism"

static func _solve_text(gates: Array) -> String:
	if gates.size() == 1:
		return _solve_step(gates[0]).capitalize() + "."
	var parts: Array = []
	for i in range(gates.size()):
		parts.append("(%d) %s" % [i + 1, _solve_step(gates[i])])
	return "In order, each behind the last: " + "; then ".join(parts) + " — only then is the end reachable."

static func _shadow_text(gates: Array) -> String:
	var a := str(gates[0]["arch"])
	match a:
		"holdfast": return "Aster+Peris: Aster scans the wash gauge for the dark window; Peris tends a causeway on one fertile lane — cross unheld."
		"redirect": return "Aster+Peris: Peris Hushbloom-stuns the charger at the commit (no dodge window)."
		"vinebridge": return "Aster+Peris: Peris plants and tends the vine herself; Aster reads the guard's timing or uses EMP instead of the flure."
		"split": return "Aster+Peris (two bodies): Aster hacks one plate to a timed latch while Peris holds the other, then dashes."
		"distract":
			match str(gates[0].get("variant", "lure")):
				"patrol": return "Aster+Peris: Peris reads the flora-lit safe row; Aster reads the patrol beat — cross split, one per window."
				"twin": return "Aster+Peris: no flure spent — inspect both watchers' idle drift, stage in the pocket, thread the north gap in the overlap of their look-aways."
				_: return "Aster+Peris: Aster reads the sentry's beat from its world tell; stage in the conceal pocket (c) and slip the look-away window — no flure spent."
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

## Carve a 3-row watched gap centered on `g_mid` out of a full-column band: lane rows become "!", the rest
## of the column becomes wall. Returns the lane cells.
static func _carve_gap(g: Dictionary, cells: Array, _col: int, g_mid: int) -> Array:
	var lane: Array = []
	for c0 in cells:
		var cy := (c0 as Vector2i).y
		if cy >= g_mid - 1 and cy <= g_mid + 1:
			lane.append(c0)
		else:
			g[c0] = SYM_WALL
	for lc in lane:
		g[lc] = "!"
	return lane

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

# --- safe passage between watch fans (learned by PLAYING a generated chain) -------------------------------------

## Watch-fan radius in CELLS (mirrors the bridge: SENTRY_RANGE 4.0 / CELL 1.5).
const WATCH_RANGE_CELLS := 2.7

## THE FAIRNESS INVARIANT for chained stealth gates: between consecutive gates there must be SAFE GROUND —
## a route from the previous gate's exit to the next stage's mechanism (and conceal pocket) that avoids
## EVERY posted sentry's watch fan except the just-crossed gate's own (you land in that one and walk out
## while its sentry is still away). Without this, aligned gap rows let two gates' fans jointly cover the
## connecting chamber and a correctly-playing runner gets caught on open floor — the bridge playtest found
## exactly that (seed 11: patrol row == twin north row). Machine-checked here; compose() re-rolls a failing
## layout. Fans are radial + wall-LOS, same truth the real detection uses.
static func safe_passage(chunk: Dictionary) -> Dictionary:
	var gates: Array = chunk["gates"]
	var grid: Dictionary = chunk["grid"]
	var gate_sentries: Array = []
	for gt in gates:
		var s: Array = []
		for e in gt.get("elements", []):
			if str(e["sym"]) == "s":
				s.append(e["cell"])
		gate_sentries.append(s)
	var segments: Array = []
	var all_ok := true
	for i in range(-1, gates.size()):
		var fan := {}
		for gi in range(gates.size()):
			if gi == i:
				continue   # the just-crossed gate's own fan is excused for its own aftermath
			for sc in gate_sentries[gi]:
				_add_fan(grid, sc, fan)
		var entries: Array = []
		if i == -1:
			entries = [chunk["start"]]
		else:
			for lc in gates[i]["cells"]:
				var e2: Vector2i = (lc as Vector2i) + Vector2i(1, 0)
				if grid.has(e2) and str(grid[e2]) != SYM_WALL:
					entries.append(e2)
		var targets: Array = []
		if i + 1 < gates.size():
			targets.append(gates[i + 1]["mechanism"])
			for e3 in gates[i + 1].get("elements", []):
				if str(e3["sym"]) == "c":
					var launch := e3["cell"] as Vector2i
					# The live party resolver can orient its three-body formation on either
					# axis according to the approach. Prove the entire plus-shaped staging
					# footprint, not just the clicked centre cell.
					for offset in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT,
							Vector2i.UP, Vector2i.DOWN]:
						targets.append(launch + offset)
		else:
			targets.append(chunk["end"])
		var ok := _safe_flood(grid, entries, targets, fan)
		segments.append({"segment": i, "ok": ok})
		all_ok = all_ok and ok
	return {"ok": all_ok, "segments": segments}

static func _add_fan(grid: Dictionary, sc: Vector2i, fan: Dictionary) -> void:
	var r := int(ceil(WATCH_RANGE_CELLS))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := sc + Vector2i(dx, dy)
			if not grid.has(c) or Vector2(dx, dy).length() > WATCH_RANGE_CELLS:
				continue
			if _cell_los(grid, sc, c):
				fan[c] = true

## Cell-to-cell sightline: sampled line, blocked by wall cells (endpoints excluded) — the sketch mirror of
## grid_world.has_line_of_sight.
static func _cell_los(grid: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	if a == b:
		return true
	var dist := Vector2(b - a).length()
	var steps := maxi(2, int(ceil(dist / 0.4)))
	for s in range(1, steps):
		var f := float(s) / float(steps)
		var c := Vector2i(roundi(lerpf(a.x, b.x, f)), roundi(lerpf(a.y, b.y, f)))
		if c == a or c == b:
			continue
		if grid.has(c) and str(grid[c]) == SYM_WALL:
			return false
	return true

static func _safe_flood(grid: Dictionary, entries: Array, targets: Array, fan: Dictionary) -> bool:
	var target_set := {}
	for t in targets:
		target_set[t] = true
	var seen := {}
	var queue: Array = []
	for e in entries:
		if not fan.has(e) and not seen.has(e):
			seen[e] = true
			queue.append(e)
	var qi := 0
	while qi < queue.size():
		var c: Vector2i = queue[qi]
		qi += 1
		if target_set.has(c):
			target_set.erase(c)
			if target_set.is_empty():
				return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc: Vector2i = c + (d as Vector2i)
			if seen.has(nc) or not grid.has(nc) or str(grid[nc]) == SYM_WALL or fan.has(nc):
				continue
			seen[nc] = true
			queue.append(nc)
	return target_set.is_empty()

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
	var sp := safe_passage(chunk)
	var gates: Array = chunk["gates"]
	var blocked_archs: Array = []
	var registers := {}
	var mechanisms: Array = []
	for gt in gates:
		var a := str(gt["arch"])
		if not bool(mechanic(a)["buildable"]):
			blocked_archs.append(a)
		var mt := mechanism_type(a, str(gt.get("variant", "")))
		registers[str(mt["register"])] = true
		mechanisms.append("%s/%s" % [str(mt["family"]), str(mt["subtype"])])
	return {
		"gated": v,                                       # P8: cannot walk start->end unsolved (PROVEN)
		"lock_before_key": lbk,                           # research: encounter the lock first (PROVEN)
		"safe_passage": sp,                               # fairness: regroup ground exists between watch fans (PROVEN)
		"buildable": blocked_archs.is_empty(),            # P6: every gate backed by a real mechanic
		"blocked_archetypes": blocked_archs,
		"mechanisms": mechanisms,                         # Track D: typed, section-keyable
		"registers": registers.keys(),                    # P2 raw material (composite = >=2 registers)
		"two_registers": registers.size() >= 2,           # P2: a legit SECTION composes two (atoms may be 1)
		"shadow_verified": false,                         # P10: prose only until the ablation slot (Track B2)
		"ok": bool(v["ok"]) and bool(lbk["ok"]) and bool(sp["ok"]) and blocked_archs.is_empty(),
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
