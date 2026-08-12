# The Level Data Contract — one declaration, loud absence

## Why this document exists

Deleting one level spec (`generated_teaching_channels_shelter_1_to_2.json`) broke **ten consumers**:
the preview picker, puzzle fixtures, the replay census, the level editor's plan browser, campaign
indexes, generation vocabulary, a cutscene controller, and a family of standalone tools. Every one
held a private copy of the level's identity — a path or id string — with no existence check, so the
deletion surfaced as scattered use-time failures far from the cause. A follow-up census found the
same disease in at least seven other identity classes (see `fragmentation_census` in the working
notes; character ids alone: 7,000+ scattered literals).

The JSON-spec system was itself the *previous* attempt at this fix — one data representation instead
of three per level scattered across scripts. It failed because **the data file standardized layout
while behavior leaked around it**: mechanics keyed to a spec ID were baked into the renderer
(`HYDRAULIC_SPEC_ID` gated ~3,600 lines of chunk code), so the level's identity ended up split
between a data file and code that only fired for that ID. Standardization must bind at the
**contract** level, not the file-format level.

## The law

1. **A level identity is DECLARED once and RESOLVED centrally.** Consumers hold an id (or a named
   role), never a path. The id→file mapping lives in exactly one class.
2. **Absence fails at the registry, loudly, naming the entry** — never at a use site. A registry
   test proves every declared reference resolves *before* anything tries to load it.
3. **One authority per CONCERN, not one file format per level:**
   - *Placements*: scene nodes (props `.tscn` / spec nodes) — the existing placement law.
   - *Mechanics*: canon system classes only (`CrawlTunnel`, `RiskLane`, wash sections, …), composed
     by levels, never chunk-private state machines keyed to a level id. `--test-canon-mechanics`
     lints the enforceable slice; the hydraulic retirement is the cautionary tale.
   - *Tuning and copy*: data files with loaders (`DialogueData`, `AbilityData` are the pattern).
   - *Wiring*: a thin chunk script.
4. **Derived artifacts belong to their source.** A replay baseline, sketch, or sample carries its
   parent's id and dies with it; an orphan is a test failure, not an archaeology project.
5. **Guards must be unable to pass vacuously.** Every sweep asserts liveness (counts with floors)
   and is red-proven against a planted fixture. A scanner that finds nothing agrees with every
   claim — this repo's most common test defect.

## The shipped instruments

- **`scripts/generation/stretch_spec_catalog.gd`** (`StretchSpecCatalog`) — spec resolution. Ids and
  named roles (`TEACHING_SPEC`) in; paths out via `path()` / `teaching_path()`; `load_spec()` can
  never fail silently; `all_ids()` enumerates disk. The directory string exists on one line of the
  codebase. Standalone tools preload it **by path** (`--script` runs may not have fresh
  `class_name`s in the global cache).
- **`scripts/testing/level_reference_integrity.gd`** + `--test-level-reference-integrity` (in
  `--test-all`) — the fragmentation guard. Sweeps scripts/, data/, scenes/, tools/ for every spec
  reference (path form everywhere; bare-id form in JSON); fails on dangling references, orphaned
  artifacts, and unconsumed specs, naming file and id. Hermetic red-proof runs against a `user://`
  fixture via injectable roots. `NON_SPEC_IDENTIFIERS` is the audited allowlist for vocabulary that
  wears the spec naming shape — keep it short; every entry is a hole.
- **The preview registry test** additionally proves every `PREVIEW_ENTRIES` `spec_path` exists on
  disk, failing with the entry id.
- **`RoomModelBinder`** predates all of this and is the in-repo proof the pattern works: modeled
  scenes declare one descriptor, a shared binder owns the rules, and `validate()` turns silent
  failures into loud strings. The catalog + sweep generalize that shape to level identity.

## How to ADD a generated level

1. Drop the spec in `data/generated_stretches/<id>.json`.
2. Reference it BY ID through `StretchSpecCatalog` (add a role const if it plays a named part).
3. Add its picker entry / campaign row as needed — the registry and integrity tests confirm the
   wiring resolves both ways (a spec nothing consumes is also a failure).

## How to REMOVE a level

1. Delete the spec file.
2. Run `--test-level-reference-integrity`. Every consumer that still names it is listed by file and
   id. Fix those sites (usually: retarget a role in the catalog, drop a fixture entry, delete
   derived replays).
3. If a mechanic exists only for that level, it violates law 3 and goes with it — budget for that,
   and expect the sweep plus the suite to find the blast radius *for* you this time.

## Authored fragments (the wash_ascent model)

Authored chunks follow the same contract with scene-node placements as their declaration. The
reference case: `wash_ascent` audits as exactly reproducible — all inputs committed, build a pure
function of committed bytes, zero RNG/wall-clock — with two hardening rules that generalize:
the build **claims its own district** (`ArchetypePieceLibrary.set_district`) rather than trusting
boot order, and variation uses project-owned position arithmetic, never engine `hash()`. A
build-twice signature guard is the planned enforcement (see the reproducibility audit notes).

## Roadmap (census-ranked, highest blast-radius first)

1. **Character roster** → `CHARACTER_REGISTRY` as the one authority (identity separate from
   capabilities; party-path validation; attribute tables absorbed — the scattered copies already
   diverged in production).
2. **Generalize the integrity sweep** to every `res://` literal (existence per path, small
   allowlist) — retires the use-time-null class for ~800 references at once.
3. **Guard the guards** — the test manifest asserts every headless flag is seated in
   `_run_all_tests` or on a named allowlist, and every documented flag still dispatches.
4. Species-id canonicalizer (plural/singular regimes), world-state key consts (renames silently
   desync saves), scene-flow table, cross-file meta-key consts — each on the same two patterns:
   a resolver where consumers should hold ids, a sweep where they can't.
