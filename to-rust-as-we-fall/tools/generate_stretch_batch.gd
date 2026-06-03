extends SceneTree

## Generates a curated batch of sample stretches across tiers and composition
## strategies, validates each through the solution solver (must be multi-solution,
## shadow-solvable, with no shadow-broken errors), and only then writes it to
## data/generated_stretches/. A spec that fails validation is reported and skipped —
## the batch never ships an unsolvable or single-solution puzzle stretch.
##
## Run: ../Godot_v4.6.1-stable_win64_console.exe --headless --path "." \
##        --script res://tools/generate_stretch_batch.gd

const StretchGeneratorScript := preload("res://scripts/generation/stretch_generator.gd")
const StretchSolutionSolverScript := preload("res://scripts/generation/stretch_solution_solver.gd")

const PUZZLE_ARCHETYPES := ["1", "2", "3", "4", "5", "6", "7", "8", "10", "11"]
const IMPLEMENTED_FLORA := ["seefern", "scarpet", "flure", "mother_flure", "hushbloom", "doma", "snapbloom", "gasafoetida"]
const IMPLEMENTED_ENEMIES := ["techos", "naturalizers"]

func _batch() -> Array:
	return [
		{
			"id": "generated_sample_teaching_first_fork",
			"title": "Sample — First Fork (Teaching)",
			"seed": 2207,
			"complexity_tier": "teaching",
			"progression_stage": 2,
			"limitations": {
				"allowed": {"archetypes": PUZZLE_ARCHETYPES, "flora": IMPLEMENTED_FLORA, "enemies": IMPLEMENTED_ENEMIES},
				"required": {"archetypes": ["2", "3"], "structures": ["shelter"]},
			},
			"world_slot": {"region": "Tutorial Outflow", "entry_shelter_id": "shelter_1", "exit_shelter_id": "shelter_2"},
		},
		{
			"id": "generated_sample_standard_garden_patrol",
			"title": "Sample — Garden Patrol (Standard)",
			"seed": 5519,
			"complexity_tier": "standard",
			"progression_stage": 3,
			"limitations": {
				"allowed": {"archetypes": PUZZLE_ARCHETYPES, "flora": IMPLEMENTED_FLORA, "enemies": IMPLEMENTED_ENEMIES},
				"required": {"archetypes": ["1", "2", "4"], "structures": ["shelter"]},
			},
			"composition": {
				"mode": "archetype_random_walk",
				"random_walk": {"start_archetype": "4", "step_count": 6, "transition_chance": 0.4, "prefer_tags": ["patrol", "flora", "timing"]},
			},
			"world_slot": {"region": "Garden Causeway", "entry_shelter_id": "shelter_2", "exit_shelter_id": "shelter_3"},
		},
		{
			"id": "generated_sample_hard_carry_run",
			"title": "Sample — Ferric Carry Run (Hard)",
			"seed": 7331,
			"complexity_tier": "hard",
			"progression_stage": 4,
			"limitations": {
				"allowed": {"archetypes": PUZZLE_ARCHETYPES, "flora": IMPLEMENTED_FLORA, "enemies": IMPLEMENTED_ENEMIES},
				"required": {"archetypes": ["1", "3", "4", "6"], "structures": ["shelter", "carry_gear"]},
			},
			"composition": {
				"mode": "chain_nested_poc",
				"chain": [
					{"id": "1", "output": "cleared_lane"},
					{"id": "3", "input": "cleared_lane", "output": "carried_component"},
					{"id": "4"},
					{"id": "6", "input": "carried_component"},
				],
				"nested": [{"id": "2", "host_id": "3", "host_step": 2}],
			},
			"world_slot": {"region": "Ferric Spiral", "entry_shelter_id": "shelter_3", "exit_shelter_id": "shelter_4"},
		},
		{
			"id": "generated_sample_setpiece_containment",
			"title": "Sample — Containment Vault (Setpiece)",
			"seed": 9043,
			"complexity_tier": "setpiece",
			"progression_stage": 5,
			"limitations": {
				"allowed": {"archetypes": PUZZLE_ARCHETYPES, "flora": IMPLEMENTED_FLORA, "enemies": IMPLEMENTED_ENEMIES},
				"required": {"archetypes": ["10", "1", "3", "4", "6"], "structures": ["shelter"]},
			},
			"composition": {
				"mode": "archetype_random_walk",
				"random_walk": {"start_archetype": "10", "step_count": 9, "transition_chance": 0.5, "prefer_tags": ["danger_zone", "carry", "patrol", "fragments"]},
			},
			"world_slot": {"region": "Containment Vault", "entry_shelter_id": "shelter_4", "exit_shelter_id": "shelter_5"},
		},
	]

func _init() -> void:
	var saved := 0
	var skipped := 0
	print("=== Generating stretch batch ===")
	for settings in _batch():
		var spec: Dictionary = StretchGeneratorScript.generate(settings)
		var spec_id := str(settings.get("id", "?"))
		if not bool(spec.get("success", false)):
			push_error("%s: generation failed: %s" % [spec_id, str(spec.get("validation", spec.get("error", "")))])
			skipped += 1
			continue
		var analysis: Dictionary = StretchSolutionSolverScript.analyze_spec(spec)
		var problems := _validation_problems(spec, analysis)
		if not problems.is_empty():
			push_error("%s: rejected — %s" % [spec_id, ", ".join(problems)])
			skipped += 1
			continue
		var path := "res://data/generated_stretches/%s.json" % spec_id
		if not StretchGeneratorScript.save_spec(spec, path):
			push_error("%s: failed to save to %s" % [spec_id, path])
			skipped += 1
			continue
		saved += 1
		print("  OK  %-44s tier=%-9s stage=%d nodes=%2d choice=%d shadow=%s future=%s -> %s" % [
			spec_id,
			str(spec.get("source", {}).get("complexity_tier", "")),
			int(spec.get("source", {}).get("progression_stage", 0)),
			(spec.get("nodes", []) as Array).size(),
			int(analysis.get("choice_node_count", 0)),
			str(bool(analysis.get("shadow_solvable", false))),
			str(bool(analysis.get("shadow_uses_future_technique", false))),
			path,
		])
	print("=== Batch complete: %d saved, %d skipped ===" % [saved, skipped])
	quit(1 if skipped > 0 else 0)

## Returns a list of human-readable reasons a generated spec is not ship-worthy.
func _validation_problems(spec: Dictionary, analysis: Dictionary) -> Array:
	var problems := []
	if int(analysis.get("choice_node_count", 0)) < 1:
		problems.append("no multi-solution puzzle nodes")
	if not bool(analysis.get("multi_solution", false)):
		problems.append("only one solution path")
	if not bool(analysis.get("shadow_solvable", false)):
		problems.append("Aster+Peris cannot finish (shadow-broken)")
	if not bool(analysis.get("bare_pair_solvable", false)):
		problems.append("bare pair cannot finish without a placed tool")
	if not bool(analysis.get("spotlight_within_stage", true)):
		problems.append("full party exceeds the progression stage")
	for warning in analysis.get("warnings", []):
		if warning is Dictionary and str((warning as Dictionary).get("severity", "")) == "error":
			problems.append(str((warning as Dictionary).get("code", "error")))
	return problems
