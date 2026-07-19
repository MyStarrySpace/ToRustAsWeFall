extends SceneTree

## Focused regression for the Cleanstreets roguelite district contract. It keeps the expensive all-biome seed
## sweep separate while proving one complete generated stretch, authored scene loading, risk-cell seating, and
## the flat-space damage coverage used after the visible world is wrapped onto a helix.

const Biomes := preload("res://scripts/generation/biomes.gd")
const Generator := preload("res://scripts/generation/stretch_generator.gd")
const GeneratedChunkScene := preload("res://scenes/fragments/chunks/generated_stretch_chunk.tscn")

var checks := 0
var failures := 0


func _init() -> void:
	var registry: Dictionary = Biomes.validate()
	check(bool(registry.get("valid", false)), "biome registry validates: %s" % str(registry.get("errors", [])))
	check(Biomes.biome_ids().has("cleanstreets"), "Cleanstreets participates in run-depth rotation")
	check(GeneratedChunkScene != null, "generated stretch presenter with theme-hazard runtime loads")

	var spec: Dictionary = Generator.generate({
		"id": "verify_cleanstreets",
		"title": "Verify Cleanstreets",
		"seed": 71926,
		"complexity_tier": "teaching",
		"biome": "cleanstreets",
	})
	check(bool(spec.get("success", false)), "Cleanstreets stretch generates: %s" % str(spec.get("validation", spec.get("error", ""))))
	if bool(spec.get("success", false)):
		var validation: Dictionary = Generator.validate_area_theme(spec)
		check(bool(validation.get("valid", false)), "Cleanstreets area theme validates: %s" % str(validation.get("errors", [])))
		check((spec.get("themed_landmarks", []) as Array).size() == 1, "one dominant toll pavilion is emitted")
		var setpieces: Array = spec.get("themed_setpieces", [])
		check(setpieces.size() >= 3, "several hostile-architecture cells create a repeated street system")
		var risk_cells := {}
		for risk_v in spec.get("navigation_grid", {}).get("risk_cell_list", []):
			if risk_v is Dictionary:
				var raw: Array = (risk_v as Dictionary).get("cell", [])
				if raw.size() >= 2:
					risk_cells["%d:%d" % [int(raw[0]), int(raw[1])]] = true
		for setpiece_v in setpieces:
			var setpiece := setpiece_v as Dictionary
			var cell: Array = setpiece.get("risk_cell", [])
			check(cell.size() >= 2 and risk_cells.has("%d:%d" % [int(cell[0]), int(cell[1])]),
				"%s sits on a route-preview risk cell" % str(setpiece.get("id", "setpiece")))
		if not setpieces.is_empty():
			var first := setpieces[0] as Dictionary
			var packed := load(str(first.get("scene", ""))) as PackedScene
			check(packed != null, "authored stud-lane scene loads")
			if packed != null:
				var lane := packed.instantiate() as Node3D
				check(lane != null and lane.find_child("HostileArchitecture", true, false) != null,
					"stud lane keeps its visible fixtures as scene nodes")
				if lane != null:
					lane.call("configure", first)
					var p := _vec3(first.get("position", []))
					check(bool(lane.call("covers_flat", p)), "stud lane covers its emitted risk-cell center")
					check(not bool(lane.call("covers_flat", p + Vector3(3.0, 0.0, 3.0))),
						"stud damage remains local to the visible fixture")
					lane.free()
	print("CLEANSTREETS GENERATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: %s" % message)
		return
	failures += 1
	push_error("FAIL: %s" % message)


func _vec3(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array and (raw as Array).size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3.ZERO
