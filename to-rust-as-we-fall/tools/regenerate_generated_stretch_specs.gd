extends SceneTree

const StretchGeneratorScript := preload("res://scripts/generation/stretch_generator.gd")

const SPEC_PATHS := [
	"res://data/generated_stretches/generated_teaching_channels_shelter_1_to_2.json",
	"res://data/generated_stretches/generated_chain_nested_poc_shelter_2_to_3.json",
	"res://data/generated_stretches/generated_random_walk_poc_shelter_3_to_4.json",
	"res://data/generated_stretches/generated_event_walk_shelter_4_to_5.json",
]

func _init() -> void:
	for path in SPEC_PATHS:
		var existing: Dictionary = StretchGeneratorScript.load_spec(path)
		if existing.is_empty():
			push_error("Missing generated stretch spec: %s" % path)
			quit(1)
			return
		var settings: Dictionary = existing.get("settings", {})
		if settings.is_empty():
			push_error("Generated stretch spec has no settings block: %s" % path)
			quit(1)
			return
		var regenerated: Dictionary = StretchGeneratorScript.generate(settings)
		if not bool(regenerated.get("success", false)):
			push_error("Failed to regenerate %s: %s" % [path, str(regenerated.get("error", ""))])
			quit(1)
			return
		if not StretchGeneratorScript.save_spec(regenerated, path):
			push_error("Failed to save regenerated stretch spec: %s" % path)
			quit(1)
			return
		print("Regenerated ", path)
	quit()
