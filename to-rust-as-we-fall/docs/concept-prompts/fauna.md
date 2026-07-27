# Fauna — concept references and prompts

Like flora, fauna is a category where **canon already exists — never regenerate what
it covers.** The canonical prompt document is `reference-docs/fauna_image_prompts.md`
(~41 KB, all thirteen threats), and the ecology that pairs with it is
`reference-docs/enemy_ecosystem.md`. Both are now mirrored into `reference-docs/`
(they were missing from the mirror until 2026-07-27, which is how a redundant
hand-written prompt set got made here — the mistake this file now exists to prevent).

Each canonical entry carries: **Tier · Silhouette priority · Form · Locomotion ·
Attack telegraph · Hurt/death · Biological inspiration.** The attack telegraph is the
fauna equivalent of a flora affordance — it is the thing the art must encode, because
the player reads the tell before the strike.

## The naming (director's ruling, 2026-07-27 — FINAL)

Four species were renamed onto the harm-naming scheme; the rename is now propagated
through the whole corpus (code, data, docs, and the canon mirror):

| Current (canonical) | Retired | Why |
|---|---|---|
| **Sapscraps** | Techos | *sap* (drains iron, saps infrastructure) + *scraps* (picked-clean detritus, scrap-sized swarm bodies) |
| **Aembers** | Verdings | *amber* + *ember* — the resin-seep at a wound, and the glowing core you see coming |
| **Flares** | Neutros | the area burst is a flare; doubles as an inflammatory flare-up (neutrophil) |
| **Redactors** | Nosomas | *redact* = erase-from-record — the information-suppression motif as a name |

The other nine keep their names: Hidras, Crusts, Candids, Meebs, Gnawers, Spikers,
Tanglers, Toxos, Naturalizers.

`reference-docs/fauna_roster.md` deliberately **keeps** the retired names — it *is* the
rename record. So do the project instruction files that teach the mapping. Everywhere
else a retired name is a bug: `--test-canon-fauna-names` fails on one.

Note for anyone reading older art or docs: `fauna_image_prompts.md` and
`enemy_ecosystem.md` were authored before the rename and have been migrated in place,
so their species headings now read Sapscraps / Aembers / Flares / Redactors. The
numbered duplicate copies in the director's Downloads folder (`… (1).md`) were left
untouched as pre-rename history.

## Where each species' art comes from

Use the canonical prompt for the species (`reference-docs/fauna_image_prompts.md`
§ *species*), prepending the shared style preamble that file defines. Generated art
belongs in `reference-images/concept/fauna/`.

**Priority order for the build queue** — the wash relay's branch guards are
**Sapscraps** (canon: only Sapscraps / Aembers / Hidras answer a Flure iron decoy), and
the in-game guard body is still a placeholder capsule, so Sapscraps art unblocks the
creature-grammar hookup first. Aembers and Hidras follow (both appear in the Plumbing
Power Project); the enforcement classes (Naturalizers, Redactors) matter for Tag Day
and the lockout chase.

The three prompts previously hand-written here were redundant with canon and have been
removed. If a species ever needs a *new* prompt — a state the canonical file does not
cover (a swarm-mass composition, a district-specific dressing) — add it below as an
explicit supplement and cite which canonical entry it extends.

## Supplements (none yet)
