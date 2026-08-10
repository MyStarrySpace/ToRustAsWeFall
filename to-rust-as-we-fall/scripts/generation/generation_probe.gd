class_name GenerationProbe
extends RefCounted

## The probe a generated stretch carries with it. Generation emits the level and, in the same breath,
## the verdict on whether anyone can actually play it — so a stretch that cannot be finished, or that
## can only be finished by bleeding, never reaches a player in the first place.
##
## THE THREE QUESTIONS (director, 2026-08-10), in the order they matter:
##   1. PASSABLE — can the party get through at all? Answered by the solution solver, which walks the
##      node spine per loadout and reports the shadow pair's verdict; the design law is that the
##      minimum pair finishes every puzzle.
##   2. LOSSLESS — does a line exist that PERFECT play pays nothing for? A stretch whose every route
##      charges HP is a toll booth, and the safe way through is a property the run is owed.
##   3. SURVIVABLE — if the party does take the priced line, does anyone come out wiped?
##
## WHAT THIS DELIBERATELY DOES NOT DO: it does not assume a node is free because nothing said it was
## expensive. A node the probe cannot price is reported as UNPRICED and counted, so the gap between
## "proven lossless" and "nothing declared a cost" stays visible instead of being quietly rounded into
## a pass. `strict` turns unpriced nodes into a refusal for callers that want the stronger claim.

const SolverScript := preload("res://scripts/generation/stretch_solution_solver.gd")
const RiskLaneScript := preload("res://scripts/generation/risk_lane.gd")

const CONTRACT := "generation_probe/v1"

## Node fields that state a GUARANTEED cost in HP — a toll the node charges whatever the player does.
## Exposure fields (`pressure`, `pressure_cost`) are deliberately NOT here: exposure is what sloppy
## play pays for, and the probe asks what PERFECT play pays.
const GUARANTEED_HP_FIELDS := ["guaranteed_hp_cost", "hp_toll", "forced_damage"]

## Fields that mark a node as offering a way past that costs nothing. A node carrying one is priced at
## zero for perfect play even when it also advertises a toll: the toll is then a CHOICE.
const BYPASS_FIELDS := ["safe_approach", "bypass", "clean_line"]

## The authored risk vocabulary on an approach (data/generation/archetype_catalog.json), read the way
## the labels actually use it:
##   safe   — straightforward cooperative work ("Peris tends the plant tool; Aster confirms the target")
##   risky  — SKILLED work by the shadow pair ("Aster times the enemy charge while Peris holds scarpet
##            cover"). Demanding, and clean when executed: this is the director's safe route that MAY
##            BE CHALLENGING, not a line that charges.
##   direct — confrontation ("bait a charge", "force it open with raw impact"). This is what costs.
##
## So a node has a clean line through it when it authors ANY approach that is not `direct`.
const CLEAN_RISKS := ["safe", "risky"]


## Probe a finished spec. Returns the verdict the spec then carries.
static func probe(spec: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var strict := bool(opts.get("strict", false))
	var party_hp: Dictionary = opts.get("party_hp", {"aster": 100.0, "peris": 100.0})
	var reasons: Array[String] = []

	if not bool(spec.get("success", false)):
		return _verdict(false, false, false, false, [], ["generation_failed"], {})

	# 1. PASSABLE. Generation has already walked the spine once to build the level; re-walking it here
	# would be a second answer to a question already answered, and the solver is the most expensive
	# thing either of us does. A caller that has the analysis hands it over.
	var analysis: Dictionary = opts.get("analysis", {}) as Dictionary
	if analysis.is_empty():
		analysis = SolverScript.analyze_spec(spec)
	var passable := bool(analysis.get("shadow_solvable", false)) \
		and int(analysis.get("solvable_loadout_count", 0)) > 0
	if not passable:
		reasons.append("no_loadout_reaches_the_exit")

	# 2. LOSSLESS under perfect play, and 3. SURVIVABLE if the priced line is taken instead.
	var nodes: Array = spec.get("nodes", [])
	var forced: Array[String] = []
	var unpriced: Array[String] = []
	var priced_total := 0.0
	for node_value in nodes:
		if not (node_value is Dictionary):
			continue
		var node: Dictionary = node_value
		var role := str(node.get("role", ""))
		if role in ["boundary", "shelter_arrival"]:
			continue
		var toll := _declared_toll(node)
		# An OPTIONAL detour is a choice, not a way through: the golden path walks the non-optional
		# spine, so a risky side room is exactly the priced content the law permits. Its toll still
		# counts toward what the priced line costs -- taking it is how you pay it.
		if bool(node.get("optional", false)):
			priced_total += toll
			continue
		var has_bypass := _has_bypass(node) or _offers_a_safe_approach(node)
		if toll > 0.0:
			priced_total += toll
			# A toll with no way past it is what makes a stretch unplayable clean.
			if not has_bypass:
				forced.append(str(node.get("id", node.get("role", "?"))))
		elif not has_bypass:
			# The node authored approaches and NONE of them is the safe one, so every line through it
			# is a line that can cost. That is a forced toll whether or not anyone wrote a number on
			# it, and it is exactly what the clean-line law forbids on a safe route.
			forced.append(str(node.get("id", node.get("role", "?"))))
		elif not (node.get("approaches", []) as Array).is_empty() and not _states_a_price(node):
			# A clean line exists, but what its RISKY siblings would cost was never written down. The
			# stretch is lossless; what the priced line costs is still unknown, and saying so is the
			# difference between a probe and a rubber stamp.
			unpriced.append(str(node.get("id", node.get("role", "?"))))

	var lossless := forced.is_empty()
	if not lossless:
		reasons.append("nodes_charge_a_toll_with_no_way_past:%d" % forced.size())
	if strict and not unpriced.is_empty():
		lossless = false
		reasons.append("unpriced_nodes_cannot_be_proven_lossless:%d" % unpriced.size())

	# Survivability is asked of the PRICED line: the clean line costs nothing by construction, so the
	# question is only whether a party that pays every toll is still standing at the end.
	var affordability: Dictionary = RiskLaneScript.route_affordability(
		[{"hp_cost": priced_total}], party_hp)
	var survivable := bool(affordability.get("affordable", false))
	if not survivable:
		reasons.append("the priced line would wipe: %s" % str(
			affordability.get("casualties", [])))

	return _verdict(passable and lossless and survivable, passable, lossless, survivable,
		unpriced, reasons, {
			"forced_toll_nodes": forced,
			"priced_line_hp": priced_total,
			"shadow_solvable": bool(analysis.get("shadow_solvable", false)),
			"solvable_loadout_count": int(analysis.get("solvable_loadout_count", 0)),
			"choice_node_count": int(analysis.get("choice_node_count", 0)),
		})


## What a node charges no matter how well it is played. Exposure is not a toll.
static func _declared_toll(node: Dictionary) -> float:
	var toll := 0.0
	for field in GUARANTEED_HP_FIELDS:
		toll = maxf(toll, float(node.get(field, 0.0)))
	return toll


## Whether the node authors a line through it that perfect play pays nothing for -- allowing that the
## line may be hard to walk. A node with NO approaches at all is a plain traversal beat — entry, shelter, an unscripted room — which the
## solution solver itself treats as always passable and safe; there is nothing there to charge.
static func _offers_a_safe_approach(node: Dictionary) -> bool:
	var approaches: Array = node.get("approaches", []) as Array
	if approaches.is_empty():
		return true
	for approach_value in approaches:
		if not (approach_value is Dictionary):
			continue
		if str((approach_value as Dictionary).get("risk", "")) in CLEAN_RISKS:
			return true
	return false


static func _has_bypass(node: Dictionary) -> bool:
	for field in BYPASS_FIELDS:
		var value: Variant = node.get(field, null)
		if value is bool and bool(value):
			return true
		if value is String and str(value) != "":
			return true
		if value is Dictionary and not (value as Dictionary).is_empty():
			return true
		if value is Array and not (value as Array).is_empty():
			return true
	return false


## Whether the node said ANYTHING about what it costs. A node that declares a zero toll has been
## priced; a node that mentions no cost at all has not.
static func _states_a_price(node: Dictionary) -> bool:
	for field in GUARANTEED_HP_FIELDS:
		if node.has(field):
			return true
	return false


static func _verdict(ok: bool, passable: bool, lossless: bool, survivable: bool,
		unpriced: Array, reasons: Array, detail: Dictionary) -> Dictionary:
	var report := {
		"contract": CONTRACT,
		"ok": ok,
		"passable": passable,
		"lossless": lossless,
		"survivable": survivable,
		"unpriced_nodes": unpriced,
		"unpriced_node_count": unpriced.size(),
		"reasons": reasons,
	}
	for key in detail.keys():
		report[str(key)] = detail[key]
	return report
