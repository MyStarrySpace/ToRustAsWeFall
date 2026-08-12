class_name StretchSpecCatalog

## THE one place a generated-stretch spec is resolved. Consumers hold a spec ID (or a named role),
## never a path: the directory, the extension, and the id->file mapping live HERE and nowhere else.
## Hard-coding a spec path at a use site is the defect this class exists to end -- a dozen scattered
## copies of one string is how deleting a single level broke ten consumers at use time, each failure
## far from the deletion. With resolution centralized, retargeting a role is one line, and
## `--test-level-reference-integrity` polices the stragglers.
##
## Standalone tools run under `--script`, where a fresh class_name is not always in the global cache:
## preload this file by PATH there (`const Catalog := preload("res://scripts/generation/stretch_spec_catalog.gd")`).

const SPEC_DIR := "res://data/generated_stretches"

## Named ROLES -- the semantic slots the game asks for, so a consumer can say "the teaching spec"
## without knowing which file currently plays that part. Retarget a role by editing its one line.
const TEACHING_SPEC := "generated_sample_teaching_first_fork"

static func path(spec_id: String) -> String:
	return SPEC_DIR.path_join(spec_id + ".json")

static func teaching_path() -> String:
	return path(TEACHING_SPEC)

static func exists(spec_id: String) -> bool:
	return FileAccess.file_exists(path(spec_id))

## Parse a spec by id. Missing or malformed specs return {} and push one error naming the id --
## the caller decides whether absence is fatal, but it can never be silent.
static func load_spec(spec_id: String) -> Dictionary:
	var spec_path := path(spec_id)
	if not FileAccess.file_exists(spec_path):
		push_error("StretchSpecCatalog: no spec '%s' (%s)" % [spec_id, spec_path])
		return {}
	var f := FileAccess.open(spec_path, FileAccess.READ)
	if f == null:
		push_error("StretchSpecCatalog: cannot read spec '%s' (%s)" % [spec_id, spec_path])
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_error("StretchSpecCatalog: spec '%s' is not a JSON object" % spec_id)
		return {}
	return parsed

## Every spec id present on disk (top level only; subdirectories hold derived artifacts).
static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	var dir := DirAccess.open(SPEC_DIR)
	if dir == null:
		return ids
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json"):
			ids.append(name.get_basename())
		name = dir.get_next()
	dir.list_dir_end()
	ids.sort()
	return ids
