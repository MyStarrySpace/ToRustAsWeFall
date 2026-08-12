# Concept Art Status Index

## Mandatory creature design workflow

All new or reopened fauna designs begin with an orthographic top-down silhouette
exploration. The director must select or explicitly approve a flat silhouette
before anatomy, materials, color, state transformations, turnarounds, or action
sheets are produced. Judge the silhouette at distant gameplay scale. Construct
complexity through a few large exaggerated forms and meaningful negative space;
do not rely on internal color, texture, fine teeth, small spikes, or surface detail
to identify the creature. For transforming creatures, approve the silhouette of
each state and map a one-to-one physical path between them before rendering.

Every silhouette sheet must visibly include the exact biological, chemical, and
approved world-style references used. Candidate families must differ by structural
abstraction, not merely by pose or proportion. A candidate advances only if it
passes all three gates:

1. **Source fidelity:** its large geometry still carries the organism, molecule,
   or pathology that inspired it.
2. **Gameplay affordance:** its role, facing, movement, attack lane, or state is
   legible from the gameplay camera.
3. **World-family fit:** it belongs beside the approved Sapscrap and Meeb through
   organic-horror massing—diseased asymmetry, awkward weight, soft tissue compressed
   beneath irregular hard growths, uncomfortable negative space, and a few large
   dental or hooking forms. Avoid clean logo geometry, smooth icons, vehicles,
   heraldic symmetry, and decorative spike fields.

Biological mapping annotations are governed by
`docs/BIOLOGICAL_DESIGN_ANNOTATION_MAP.md`. Every concept sheet must show where
its source appears in anatomy/silhouette, material, behavior/affordance, or
transformation. Locked designs receive annotation companion sheets only; adding
annotations does not authorize redesign.

This is the authority for deciding which concept images may be used as design
references. It exists because the concept folders contain final designs,
explorations, superseded branches, prompt outputs, action studies, and modeling
clarifications under similarly authoritative-looking filenames.

## Status precedence

1. **FINAL — LOCKED**: the design is approved. Do not redesign it or generate a
   replacement. New production views may be made only when explicitly requested,
   and must use the locked image as the sole anatomy authority.
2. **FINAL DESIGN — FILE NEEDS IDENTIFICATION**: the director has described the
   approved design, but this index cannot safely identify its exact source file.
   Do not generate from a guessed candidate. Ask the director to identify it.
3. **APPROVED DIRECTION — NOT FINAL**: preserve the stated construction and
   affordances, but further review is expected.
4. **REVIEW REQUIRED**: preliminary work only. Do not treat it as canon or use it
   to seed a production asset without approval.
5. **SUPERSEDED / DO NOT USE**: may remain as process history, but must never seed
   new art, models, prompts, or runtime visuals.
6. **CANON CONFLICT — BLOCKED**: do not continue visual development until the
   underlying lore/design contradiction is resolved.

The explicit entry in this file overrides filenames containing words such as
`final`, `clean`, `turnaround`, `affordance`, or a higher version number.

## Fauna and institutional actors

| Design | Status | Authoritative reference or locked ruling | Notes |
| --- | --- | --- | --- |
| **Sapscrap** | **FINAL — LOCKED** | `reference-images/concept/fauna/turnarounds/sapscraps-idle-01-*.png`; source selection: bottom-right creature in `reference-images/concept/fauna/silhouettes/sapscraps-short-arm-mouth-exploration-01.png`; Blender master: `../blender/fauna/sapscrap/sapscrap.blend` | Compact, squat, subtly lopsided round body; enormous forward central ring mouth; exactly three extremely short thick hook appendages—two lower front arms and one rear-upper crown arm. This is the design implemented by the current Blender/GLTF asset. **Do not generate new Sapscrap images or redesign it unless the director explicitly reopens it.** |
| **Ferrule** | **REDESIGN IN PROGRESS — NOT FINAL** | Director ruling: rebuild from the supplied pyoverdine skeletal structure rather than any surviving old Ferrule image; its gameplay role is a concealed breach/chokepoint ambusher | Design the hidden state first. From the gameplay camera, roughly 90–95% of the Ferrule must be physically stored behind an opaque doorway wall/jamb; the open passage should look almost empty, with at most one ambiguous tooth-, barb-, or cracked-trim-sized sliver protruding. Preserve a bulky three-mass toothed head, exactly two unequal strong clamp arms, and one continuous asymmetric folded body/tail derived from pyoverdine topology. A tiny chartreuse seam provides the warning, then a large connected weapon mass must actually travel laterally or diagonally through the gap along a traceable one-to-one path. Separate explanatory full-body maps from the occluded player view. Simplify by compression—few oversized teeth, hooks, folds, and connected masses—not by making the form plain. Never use beads, repeated segments, loose pieces, a free-roaming slug silhouette, or a visibly waiting doorway sentry. Current mechanism exploration is awaiting approval and is not stored as project authority. |
| **Hidra** | **REVIEW REQUIRED** | `reference-images/concept/fauna/hidras.png` is the older concept; `hidra-clean-mesh-sheet-01.png` is a later clarification pass | No explicit final approval recorded in this audit. |
| **Crust** | **APPROVED DIRECTION — NOT FINAL** | Preserve the porous colony appearance from `crust-affordance-concept-01.png` as the active state | Must be a low floor colony. It also needs a closed camouflage state in which the same holes seal and the colony resembles ordinary flooring with only a shallow raised patch. The wall-mounted seven-pore cleanup is not final. |
| **Candid** | **REVIEW REQUIRED** | `candid-clean-module-sheet-01.png` | Three-layer construction is useful—carpet, pseudohyphal stalks, canopy—but has not been declared final. |
| **Meeb** | **FINAL — LOCKED** | `reference-images/concept/fauna/meeb-clean-mesh-sheet-01.png` | Sapscrap-adjacent feral material language with scattered irregular denticles around feeding pores. Do not redesign or regenerate unless the director explicitly reopens it. |
| **Gnawer** | **REVIEW REQUIRED** | `gnawer-clean-mesh-sheet-01.png` | Clean mesh study only; not explicitly approved as final. |
| **Spiker** | **APPROVED DIRECTION — NOT FINAL** | `spiker-clean-mesh-sheet-01.png` | Preserve the large, distance-readable asymmetric crown. Earlier dense branches and overly symmetrical versions are superseded. |
| **Tangler** | **REVIEW REQUIRED** | `tangler-clean-mesh-sheet-01.png` | Strand-continuity construction study; not explicitly approved as final. |
| **Flare** | **APPROVED DIRECTION — NOT FINAL** | `reference-images/concept/fauna/flare-transformation-construction-01.png` is the sole current construction/state authority | Containment pod with five persistent hinged scutes, three braces, fixed reservoirs, and a NET-like burst. Preserve reduced detail density and the sheet's explicit one-to-one hinge trajectories: every closed-state part must remain identifiable in the open state. `flare-clean-mesh-sheet-01.png` is not a transformation authority; its disconnected/exploded open tableau is superseded. The literal giant-cell Flare is also superseded. |
| **Toxo** | **SILHOUETTE EXPLORATION — NOT FINAL** | Select a top-down silhouette before returning to anatomy or materials | The deleted smooth comma/cell version is explicitly superseded. Target detail density lies between the dense first armored exploration and the overly plain seed-like simplification: retain menace through fewer but much larger crown teeth, silhouette spikes, armor divisions, and ventral scutes. Current candidates D, F, and G have useful directionality but none is approved. Its eventual distant top-down identity should remain a bold apical crown + exaggerated asymmetric wedge; paired red reservoirs return only after the outer silhouette is locked. Do not create production views until the silhouette and replacement direction are approved. |
| **Naturalizer** | **FINAL — LOCKED** | `reference-images/concept/characters/naturalizer-humanoid-final-01.png` | Not fauna. Humanoid institutional enforcer with sealed scanner helmet, technical enforcement uniform, and visible scan/strike affordances. Do not redesign or regenerate unless the director explicitly reopens it. Beetle images are superseded. |
| **Redactor** | **CANON CONFLICT — BLOCKED** | No current visual authority | Existing art derives it from the obsolete beetle Naturalizer. Reconcile its anatomy with the humanoid Naturalizer ruling before further art. |

## Explicitly superseded fauna files and branches

The following must not be used as design authorities:

- `reference-images/concept/fauna/sapscraps-feral-reclaimer-concept-01.png`
- `reference-images/concept/fauna/sapscrap-clean-mesh-sheet-01.png`
- The deleted flat-disc `reference-images/concept/fauna/sapscraps.png` branch.
- Sapscrap silhouette/action experiments that conflict with the locked round,
  three-short-appendage turnaround and Blender model.
- `reference-images/concept/fauna/naturalizers.png`
- `reference-images/concept/fauna/naturalizers-v2.png`
- `reference-images/concept/fauna/flare-affordance-concept-01.png`
- `reference-images/concept/fauna/flare-turnaround-concept-01.png`
- The disconnected/exploded open-state interpretation in
  `reference-images/concept/fauna/flare-clean-mesh-sheet-01.png`; use only
  `flare-transformation-construction-01.png` for current part continuity.
- The deleted smooth comma/cell Toxo branch formerly represented by
  `reference-images/concept/fauna/toxo-clean-mesh-sheet-01.png`
- The wall-mounted interpretation in
  `reference-images/concept/fauna/crust-clean-module-sheet-01.png`
- All surviving old Ferrule branches. The intended current artwork was lost, so
  none are safe authorities for the new pyoverdine-driven rebuild.

## Flora

The flora concept files have not yet received the same final-status audit. Their
affordance and turnaround filenames indicate production intent, not approval.
Until reviewed, treat all flora entries as **REVIEW REQUIRED**, with these locked
construction rulings from the director:

- Hushbloom leaves are card geometry, not modeled leaf meshes.
- Each Seefern frond/front is card geometry.

## Workflow gate for future image generation

Before generating or editing concept art:

1. Look up the design in this index.
2. If it is **FINAL — LOCKED**, do not generate unless the user explicitly asks
   for a new derivative view or edit of that final.
3. Use only the listed authority as the anatomy reference. Do not mix exploratory
   branches for style or construction.
4. If the exact final file is unidentified, ask for identification. Never choose
   by filename, recency, or apparent polish.
5. Save new work with a status-bearing filename or update this index immediately;
   a new image is preliminary by default and never silently becomes final.
