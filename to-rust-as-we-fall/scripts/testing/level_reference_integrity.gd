class_name LevelReferenceIntegrity

## Referential integrity for LEVEL IDENTITY across the whole project.
##
## A level exists in exactly one place (its spec file, or its registered chunk), but it is NAMED in
## many: the preview picker, campaign indexes, puzzle fixtures, replay baselines, editor plans, and
## tests. Each of those references is a private string, and a string cannot know its target is gone.
## Deleting one spec file therefore breaks consumers at USE time, scattered across the project, far
## from the deletion -- the measured blast radius of one such deletion was ten consumers.
##
## This sweep makes the coupling loud and central instead of silent and scattered: every reference
## to a spec, anywhere, must resolve to a spec that exists; every derived artifact (replay baseline,
## sample) must have its parent; and the scan itself must prove it saw a real project (a scanner
## that finds nothing passes every claim -- the empty-collection trap this codebase keeps meeting).
##
## Pure static sweep, no scene tree needed. The test runner asserts on the report; tools may print it.

const SPEC_DIR := "res://data/generated_stretches"

## Where level identities get NAMED. docs/ is deliberately excluded: prose may cite levels that are
## gone, as history, without holding the loader hostage. tools/ IS included -- a capture or verify
## tool pointed at a missing spec hard-errors on its next run, which is the same defect one step
## deferred.
const SCAN_ROOTS := ["res://scripts", "res://data", "res://scenes", "res://tools"]
const SCAN_EXTENSIONS := ["gd", "json", "tscn", "tres", "cfg"]

## Identifiers that match the spec naming shape but are vocabulary, not levels. Keep this list SHORT
## and audited -- every entry here is a hole in the guard.
const NON_SPEC_IDENTIFIERS := {
	"generated_stretch": true,          # the renderer chunk's id, not a spec
	"generated_stretches": true,        # the directory itself
	"generated_stretch_complete": true, # a completion STEP name asserted by fixtures
	"generated_teaching_stretch": true, # a puzzle-fixture ENTRY id, not the spec it targets
}

## Every spec id that exists on disk right now (filename minus .json, top level of SPEC_DIR only --
## subdirectories hold derived artifacts, not specs).
static func existing_spec_ids(spec_dir: String = SPEC_DIR) -> Dictionary:
	var ids := {}
	var dir := DirAccess.open(spec_dir)
	if dir == null:
		return ids
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json"):
			ids[name.get_basename()] = true
		name = dir.get_next()
	dir.list_dir_end()
	return ids

## The full sweep. Returns:
##   specs: int                      -- how many specs exist (liveness)
##   references: Array[Dictionary]   -- every {file, id} naming a spec outside SPEC_DIR
##   dangling: Array[Dictionary]     -- references whose spec does not exist
##   orphans: Array[String]          -- derived artifacts under SPEC_DIR whose parent spec is gone
##   unreferenced: Array[String]     -- specs no consumer names (drift the other direction)
##   files_scanned: int              -- liveness for the scan itself
## Roots and spec dir are injectable so the guard can be red-proven against a hermetic fixture
## instead of a temporary mutation of the live tree.
static func sweep(spec_dir: String = SPEC_DIR, roots: Array = SCAN_ROOTS) -> Dictionary:
	var existing := existing_spec_ids(spec_dir)
	var path_pattern := RegEx.new()
	path_pattern.compile("generated_stretches/([A-Za-z0-9_\\-]+)\\.json")
	var id_pattern := RegEx.new()
	id_pattern.compile("\"(generated_[a-z0-9_]+)\"")

	var references: Array[Dictionary] = []
	var files_scanned := 0
	for root in roots:
		files_scanned += _scan_dir(root, spec_dir, existing, path_pattern, id_pattern, references)

	var dangling: Array[Dictionary] = []
	var referenced := {}
	for ref in references:
		referenced[ref["id"]] = true
		if not existing.has(ref["id"]):
			dangling.append(ref)

	var unreferenced: Array[String] = []
	for spec_id in existing:
		if not referenced.has(spec_id):
			unreferenced.append(spec_id)
	unreferenced.sort()

	return {
		"specs": existing.size(),
		"references": references,
		"dangling": dangling,
		"orphans": _orphaned_artifacts(existing, spec_dir),
		"unreferenced": unreferenced,
		"files_scanned": files_scanned,
	}

## Recursive scan of one root. Returns the number of files read.
static func _scan_dir(
	path: String, spec_dir: String, existing: Dictionary,
	path_pattern: RegEx, id_pattern: RegEx,
	out_references: Array[Dictionary]
) -> int:
	# Derived artifacts under the spec dir name their parent by construction; scanning them as
	# consumers would let a spec count as "referenced" by its own replay.
	if path == spec_dir:
		return 0
	var dir := DirAccess.open(path)
	if dir == null:
		return 0
	var scanned := 0
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var child := path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				scanned += _scan_dir(child, spec_dir, existing, path_pattern, id_pattern, out_references)
		elif name.get_extension() in SCAN_EXTENSIONS:
			scanned += 1
			_scan_file(child, path_pattern, id_pattern, out_references)
		name = dir.get_next()
	dir.list_dir_end()
	return scanned

static func _scan_file(
	file_path: String, path_pattern: RegEx, id_pattern: RegEx,
	out_references: Array[Dictionary]
) -> void:
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var seen := {}
	for m in path_pattern.search_all(text):
		var id := m.get_string(1)
		if not seen.has(id):
			seen[id] = true
			out_references.append({"file": file_path, "id": id, "kind": "path"})
	# Quoted bare ids catch the consumers that name a spec without its path -- campaign indexes,
	# fixture spec_id fields, editor plans. Data files only: in .gd source a quoted generated_*
	# string is usually vocabulary (node kinds, handler names), and the path form above already
	# catches code that loads a spec.
	if file_path.get_extension() != "json":
		return
	for m in id_pattern.search_all(text):
		var id := m.get_string(1)
		if NON_SPEC_IDENTIFIERS.has(id) or seen.has(id):
			continue
		# Only the spec NAMESPACE: ids shaped like specs that are not any known vocabulary word.
		# An id that exists is a reference; an id that does not exist is exactly the dangling
		# reference this sweep hunts -- both get recorded.
		seen[id] = true
		out_references.append({"file": file_path, "id": id, "kind": "id"})

## Derived artifacts (replays, sketches, samples) live in subdirectories of SPEC_DIR and carry
## their parent spec's id as a filename prefix. A derived file whose parent is gone is an orphan.
static func _orphaned_artifacts(existing: Dictionary, spec_dir: String = SPEC_DIR) -> Array[String]:
	var orphans: Array[String] = []
	_walk_artifacts(spec_dir, existing, orphans, true)
	orphans.sort()
	return orphans

static func _walk_artifacts(
	path: String, existing: Dictionary, out_orphans: Array[String], top_level: bool
) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var child := path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_walk_artifacts(child, existing, out_orphans, false)
		elif not top_level:
			var matched := false
			for spec_id in existing:
				if name.begins_with(spec_id):
					matched = true
					break
			if not matched:
				out_orphans.append(child)
		name = dir.get_next()
	dir.list_dir_end()
