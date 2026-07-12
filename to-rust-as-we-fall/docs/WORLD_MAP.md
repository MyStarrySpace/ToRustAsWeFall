# World Map Audit — every asset on the spine, and the gaps (2026-07-12)

**Owner: the director.** The Act 1 descent spine is canonical (act1_timeline.md, GDD 4.4); Act 2/3
placements follow the GDD's transitions. Each zone lists what EXISTS (playable chunks, survey
building kinds, scenes, mechanics) against what the registers DESIGNED for it — the deltas are
the gap list at the bottom. Companion scene design: docs/LOCKOUT_CHASE.md (the user-flagged gap).

Legend: ✅ built+tested · 🟡 partial/staged · ❌ nothing yet · 📋 designed in a register (unbuilt)

## The spine

### Shelters 1–2 — Section 3B (the facility)  ← the director flags this needs work
- ✅ Scenes: peris_sim + aster_sim (modeled rooms, RoomModelBinder), tag_day, elevator,
  leaving_facility; the full intro chain is playable + real-input tested.
- ✅ endo_junction_stretch (junction → shelter 1, modeled backdrop); lockout/rings/stacks labs
  (elevator-era mechanics live here as labs).
- ❌ **The facility as a PLACE**: there is no central-facility exterior, no approach, no
  simulation-boundary checkpoint geometry — the institution the whole Act 1 revolves around
  exists only as interior sim rooms and corridor beats. The FAILED RE-ENTRY (GDD L763 — the
  antecedent the chase elaborates) has no scene. No "facility" survey building kind (nutech is
  the Act 2/3 ruin, not the living institution).
- ❌ Peris's care facility (her workplace, GDD L586) — referenced by her whole arc, zero geometry.
- GAP RANK: **A** (see gap list).

### Shelters 2–3 — Plumbing Power Project
- ✅ The channels: wash_relay (+ trace/checkpoint/playthrough tests), channels_wash_intro,
  pump_hall (pure-data tactical stealth), set-piece water basin; Channel/Flure/Capbage/Scarpet/
  CrawlTunnel all live here; Climbvine return-points exist in generated stretches.
- 📋 Elements 1–4 (valve-rotation terminal, flow-strip beat reader, sloperope re-anchor,
  portal-pad co-op) — beat reader is COMPOSABLE-NOW.
- 🟡 plumbing_power building kind ✅, but the channels stretch uses its own helix world — the
  district's street-level face (STAGE_ELEMENTS stage-1 ambients) is unplaced.

### Shelters 4–5 — Greenfields Collective
- ✅ greenfields building kind (balcony slab stack). flora_garden lab (tend/harvest loop) fits
  here thematically.
- 📋 STAGE_ELEMENTS stage-2 (allotments, clotheslines, notice pylons); DECORATIVE_FLORA density.
- ❌ **No Greenfields playable chunk** — the residential zone between the channels and the
  terminal zone has no level of its own.

### Shelters 6–7 — The Open Files Initiative (+ the simulation boundary)
- ✅ stacks fragment lab (data terminals); open_files building kind (fin-cluster composite).
- ❌ **THE LOCKOUT CHASE (GDD §12.1)** — the Act 1 climax happens HERE and is entirely unbuilt:
  checkpoint, tag rejection, Naturalizer waves, Tyreg, the portal-offshoot beat. Now designed:
  docs/LOCKOUT_CHASE.md.
- 📋 Data-conduit troughs + card drifts (STAGE_ELEMENTS stage 2); Open Files elements in the
  register.

### Shelters 8–9 — The Hypelines
- ✅ hypelines building kind (mound + pipe arms). Tension chunks (dusk_run, refuge_run,
  distract_gate, sprint_gap) are zone-agnostic but read Hypelines-ish.
- 📋 Conveyor lines / sorting chutes / pallet mazes (STAGE_ELEMENTS stage 3).
- ❌ No Hypelines-specific chunk; the conveyor element (its signature) unbuilt.

### Shelter 10 — Ancourage (Act 1/2 transition)
- ✅ ancourage building kind; **Loca's Watchtower** boss piece PLAYABLE (climb + winch + survey,
  boss_showcase) — the Act 1 boss sits at this boundary. ✅
- 📋 Chain runs, shunt vents (stage 3); the tangle/containment vocabulary exists on the tower.

### Shelters 11–12 — The Honeycomb Cooperative
- ✅ honeycomb building kind (honeyframe lattice + laned drapes). ❌ no chunk, no elements built.

### Shelters 13–14 — The Cleanstreets Initiative
- ✅ cleanstreets building kind; **hostile_streets** chunk (decorative invasives + anti-loiter
  studs — the canon anti-homeless register, SET_PIECES 21–24, 21 built).
- 📋 Toll chokepoint element (register), tactile guidance strips + rain sails (stage 4).

### Shelters 15–16 — Beacon Hill
- ✅ beacon_hill building kind. Canon: Tyreg's recruitment site (second meeting).
- 📋 Archive columns, preservation lamps (stage 5). ❌ no chunk.

### Shelters 17–18 — Bulwark Wharf (Act 2/3 transition)
- ✅ bulwark_wharf + nutech_facility kinds; **the Paranucleus** boss piece PLAYABLE (ortho
  register, alignment crossing, Spiker sightline, reservoir cache) at this boundary. ✅
- 📋 Gantry cranes, sluice gates, quarantine webs (stage 5).

### Off-spine — The Aghora (Act 2; exact spine slot = director's call)
- ✅ aghora_exchange + aghora_stack kinds; aghora_bazaar canyon chunk (stalls, banners —
  clearance-fixed). 📋 pieces 8–11 (tolerance lanterns, sync floor…), market-gate set piece
  queued. ❌ no gameplay in the bazaar yet (walk-only).

### Shelters 19+ — Act 3 (Welcombe Springs, Harmonia, Sunset Acres, Root Archive)
- ✅ zone3 building kind (dead-zone shopfront); mother_flure chamber chunk (the clonal reveal —
  Act 3 content, already playable); creature/shape grammar pipelines ready to populate.
- 📋 STAGE_ELEMENTS stage 6 (mineral terraces, entrainment poles, middens, root buttresses,
  the verge line) — all PROPOSAL, like the GDD says Act 3 is.
- ❌ Everything else.

### Cross-zone systems (not places)
- ✅ Roguelite Retrieval Descent (WFC + atom variants, finale, permadeath); generated stretches
  (helix meta-template, solver-gated); showcase/lab fragments; the full object vocabulary
  (Flure, PortalPad, Capbage, Scarpet, Channel, FloraLight, CandidZone, CrawlTunnel,
  AlignmentCrossing, SpikeStrip, DecorativeFlora, weak walls, push, shelters-as-sanctuary).

## The gap list (ranked)

- **A. THE FACILITY** (director-flagged). The institution has no body: build (1) the central
  facility EXTERIOR + simulation-boundary checkpoint as a survey building kind (the living
  institutional register the nutech ruin echoes — clean, lit, terminal-green, scan gates), (2)
  the FAILED RE-ENTRY beat (short scene at the checkpoint: tags rejected politely — the quiet
  antecedent), (3) the checkpoint plaza geometry that the lockout chase then re-uses under
  pursuit (one build, two scenes), (4) Peris's care facility facade for her arc beats.
- **B. THE LOCKOUT CHASE** (director-flagged) — designed in docs/LOCKOUT_CHASE.md; needs the
  Naturalizer enemy variant, Tyreg temp-member + Suppress, the ammo-cache portal loop, the
  portal-offshoot beat (with the anti-cheese laws), and the Hushbloom class (which also unlocks
  the decline-path expert solution).
- **C. Zone-specific playable chunks**: Greenfields, Hypelines, Honeycomb, Beacon, Bulwark have
  architecture but no levels. Cheapest wins: reuse the data-fragment loader + each zone's
  STAGE_ELEMENTS/register entries (the hostile_streets pattern — one .tres each).
- **D. Unbuilt canon flora classes**: Hushbloom (stun — blocks TWO designs above), Seefern
  (reveal light), Gasafoetida (repel). Climbvine is half-built (return points, not the plantable
  class).
- **E. Enemy roster depth**: base Enemy + chain + roam/patrol are solid; the canon roster
  (Naturalizers, Spikers-as-class, Tanglers, Crusts, Hidras, Meebs…) mostly lacks classes —
  Naturalizer first (chase + tag_day already fake them scripted).
- **F. The Aghora's gameplay** (market gate piece, lanterns) and the boss sites' ALTERNATE
  roguelite finales (Watchtower approach, Aghora gate).

## Reference-docs holes found during this audit

RESOLVED 2026-07-12: `chase_scene_framework.md`, `lockout_chase_aftermath.md`, and
`endo_wall_scene.md` are now mirrored from Downloads (newest versions), and
docs/LOCKOUT_CHASE.md has been rewritten against the real framework (the portal offshoot is the
DESIGNED decline-path expert solution — knowledge-gated, not a cheese to close). Also mirrored: `enemy_ecosystem.md`, `survival_gameplay_feel.md`. Still missing from
Downloads entirely: `world_aesthetic_reference.md`, `trawf_timing_and_pacing_spec.md` (the
reset-system spec the chase framework cites), and the `trawf-scene-spec-framework` skill dir.
