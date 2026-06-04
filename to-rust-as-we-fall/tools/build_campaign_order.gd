extends SceneTree

## Builds the default campaign order (Act > Region > stretch) from every generated spec
## and writes the manifest + a stretches index. The manifest is what the game loads and
## the Android campaign manager edits; the index is the "Add Stretch" palette source.
##
## Run: ../Godot_v4.6.1-stable_win64_console.exe --headless --path "." \
##        --script res://tools/build_campaign_order.gd

const CampaignOrderScript := preload("res://scripts/system/campaign/campaign_order.gd")

const SPEC_DIR := "res://data/generated_stretches"
const OUT_DIR := "res://data/campaign"
const MANIFEST := "res://data/campaign/act1_order.json"
const INDEX := "res://data/campaign/stretches_index.json"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var order = CampaignOrderScript.build_default_from_dir(SPEC_DIR)
	var summaries = CampaignOrderScript.spec_summaries(SPEC_DIR)
	var known_ids := []
	for s in summaries:
		known_ids.append(str(s.get("spec_id", "")))

	var report := order.validate(known_ids)
	if not _write(MANIFEST, order.to_json()):
		push_error("Failed to write %s" % MANIFEST)
		quit(1)
		return
	if not _write(INDEX, JSON.stringify({"schema": "trawf_stretches_index_v1", "stretches": summaries}, "\t")):
		push_error("Failed to write %s" % INDEX)
		quit(1)
		return

	print("=== Campaign order built ===")
	print("  stretches placed: %d   acts: %d" % [report.get("stretch_count", 0), (order.root().get("children", []) as Array).size()])
	print("  validation: %d errors, %d warnings" % [report.get("error_count", 0), report.get("warning_count", 0)])
	for it in report.get("issues", []):
		print("    [%s] %s" % [str(it.get("severity", "")), str(it.get("message", ""))])
	print("  -> %s" % MANIFEST)
	print("  -> %s" % INDEX)
	quit(0)

func _write(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	return true
