# The Pass — throwing as supply logistics (director, 2026-08-06)

## Director's words (VERBATIM — the design authority for this doc)

> I want to avoid "carry swaping". You know how in Subnautica when you have two vehicles but one
> person, you have to drive a vehicle, then hop out, drive the other, etc.? It gets frustrating and
> boring. So let's have it so that if characters are in LOS range of each other, they can throw
> things to each other by dragging them in the GUI, causing them to throw them in the game once
> unpaused. Dragging things onto enemies throws things at them (predicting their arrival location to
> ensure a hit).

And, overruling this document's own opt-in allowlist (2026-08-06, after the spec was drafted):

> Actually why not make the fire fruit and the gas pod from the gasafoetida and everything theowable?
> Everything should be or it's unintuitive and increases mental load

The economy consequence is already ruled in `FRAGMENT_COMPOSITION_MODEL.md` §1j.

## AMENDMENT — everything is throwable (supersedes the allowlist below)

The drafted spec made `throwable` an opt-in allowlist and singled out `fire_fruit` as permanently
refused. **That is overruled.** Every item flies, with no allowlist and no per-item opt-out. Wherever
the sections below say otherwise — §1's "opt-in `throwable` allowlist", §8's "`fire_fruit` must be
`throwable: false` permanently", §9's rule 3 and its per-item table, §10 stage 1's `item_data.gd`
opt-in — read them as superseded by this amendment. They are left in place because their *reasoning*
about payloads is still correct; only the gating mechanism changed.

**Why the ruling is right.** A verb that works on some items and not others is a rule the player must
memorise, and the mental load costs more than the restriction saves. It is also the law this game
already follows elsewhere: the Capbage cache is documented as obeying "the same one-rule-no-exceptions
principle as endocytosis — the cavity holds whatever the player puts in it, and the player learns
through results what stores well and what doesn't." Throwing now reads the same way.

**Where the safety actually lives.** The allowlist was standing in for a guard that belongs one layer
down, and putting it there makes it stronger rather than weaker: **there must never be a generic "run
the item's effect where it lands" rule.** What arrives is an item on the floor. A fire fruit's damage
is an *endocytosis* effect — it hurts the character who eats it — so throwing one delivers a fire
fruit, not an explosion. One rule in one place beats a per-item affordance the player has to learn,
and it holds for every item that will ever be added rather than only the ones someone remembered to
mark.

This is now enforced positively rather than by refusal: `--test-throw-item-analytic` throws a fire
fruit at a party member and asserts it flies, arrives, and leaves the catcher's HP at 100 — a test
that would go red the moment a landing payload started running item effects.

**Consequence for the Gasafoetida pod.** The director names it, and it is a better first payload than
the `flure_seed` scent recommended in §8. Canon already has the pod emitting on contact with the
carrier's body heat, and the effect is *repel*, not damage — so a thrown pod that lands and emits is
area denial that routes enemies rather than striking them, which is exactly the tool-delivery register
this whole spec is defending. It is still a payload and still gated on Q2; it is simply the one I would
now bring first.

## The one-paragraph settlement

A throw moves an ITEM to a POINT. It never moves it into a hand, never resolves against a body, and in v1 never does anything on arrival except be an item lying on the floor. You drag a chip out of the party-hands strip and drop it on a teammate, an enemy, or bare ground; the solve happens once, at the release tick, in closed form; the solved landing point is what gets logged, and that point is what the item flies to no matter what anybody does afterwards. Landing on the ground is the only outcome — a teammate standing there picks it up automatically, but that is a convenience layered on the ground landing, not a second outcome with its own failure tree. This is the entire Subnautica fix, and it is deliberately smaller than what was asked, because the two things I cut are the two things that turn the verb into the attack verb the game does not have.

---

## 1. What I took, and what I dropped

| From | Taken | Why |
| --- | --- | --- |
| Spec 1 | The closed-form intercept quadratic; the airborne-item lane that stays off the physics registry; emit-then-validate; `throwinfo` as a pure read | The quadratic is exact and iteration-free; staying off `physics_objects` dodges three verified engine defects at once |
| Spec 1 critique | Delete the catch; price by distance; one custom pointer drag, no Godot DnD; split preview from commit-time solve | Each is load-bearing and each is right |
| Spec 2 | The refusal vocabulary riding the cursor; `PathRenderManager` reuse for the ribbon and ring; the launch-time re-validation discipline | Refusals before commit are the "click keeps its promise" law |
| Spec 2 critique | The intercept consistency check; `slows_carrier` items unthrowable; the stun-economy alarm | The math bug is real; `fragment` is the archetype §1j protects |
| Spec 3 | Geometry baked into the logged payload so replay never re-solves; the opt-in `throwable` allowlist; the fire-fruit refusal | A payload carrying the solved point has zero divergence surface |
| Spec 3 critique | The 3-of-33 occlusion measurement; `reachable()` is symmetric; the portrait-pip selection regression; `not seen` has no data layer | All four verified independently below; the first one changes the design |

**Dropped outright:** the catch as a distinct outcome (Spec 1/2/3 all had it — it produces six failure branches, enables the bucket brigade, and is the reason stale aim stings). The windup and the queued-throw state (Spec 2 — with no catch, commit-at-release is safe and needs no new state machine). The mid-flight LOS re-check (Spec 1 — its only trigger is runtime `LOCKED_DOOR` mutation, which exists nowhere in shipped code, and it snaps the item backward along an arc the player already watched). The `not seen` fog refusal (Spec 3 — no per-cell fog state exists; it is producible in the GUI and not in the CLI, a straight law-4 break). "Round-trip `reachable()`" (Spec 2/3 — proven a tautology below). Portrait-mounted hand pips (Spec 3 — they eat `_on_portrait_input`'s select press). Payload effects in v1 (all three — see §7).

---

## 2. The finding that changes the design

§1j rules that sightline is the lever, and gives a good reason: *"a range number would be a fourth invisible rule, while an occluder is a thing the level already wanted."* That reasoning is sound. The problem is that the lever does not exist in the content.

Measured on the tree, not inferred:

| Fact | Measurement |
| --- | --- |
| Chunk scripts under `scripts/fragments/chunks/` | 33 |
| Chunks calling `add_sight_blocker` | **3** (lockout_chase, set_piece_showcase, wash_ascent) |
| Chunks referencing `Tile.WALL` | **0** |
| Chunks calling `set_tile` | **0** |
| What chunks actually use for walls | `add_dynamic_blocker` + model geometry |

And `is_opaque_cell` (`grid_world.gd:835`) checks exactly four things: an explicit `sight_blocker`, `sight_transparent` (which *clears*), `Tile.WALL`, `Tile.LOCKED_DOOR`. **A dynamic blocker is invisible to it.** So the mechanism 30 of 33 chunks use to build walls does not block sight. Ship an LOS-gated throw as specified and it is an unconditional ~15 m free teleport of any item to any teammate through every wall in the level, in ~91% of shipped fragment content, on day one. That voids every carry-cost puzzle already authored, and it does so silently.

The three specs all defended the wrong case. Each hardened `grid == null` (refuse-by-default when there is no grid). The real failure is `grid != null` with an empty `sight_blockers` dict, which is the normal state of the game.

**Ruling: throwing is OFF unless a fragment turns it on, and turning it on requires declaring an occlusion set.** `SceneChunk` gets `throw_enabled := false`. A chunk opts in, and `--test-throw-occlusion-coverage` goes red by name for any opted-in fragment whose grid fails an occlusion probe (below). This keeps §1j's lever exactly as the director ruled it, and makes the authoring debt visible instead of shipping a hole. Throwing arrives in three fragments and spreads as levels earn their occluders.

That is also why the second price in §4 is not optional. Sightline is the *design* lever; it cannot be the *only* lever while it is unbuilt in 30 levels.

### 2a. Verification pass — the finding holds, but it is narrower than stated above

Re-measured independently before adopting this ruling, because it contradicts a director ruling and
the fix is expensive. **The core is confirmed. The severity claim is overstated and the real hazard is
a different, sharper one.**

Confirmed exactly as written: `is_opaque_cell` (`scripts/game/world/grid_world.gd`) returns true only
for an explicit `sight_blockers` entry, `Tile.WALL`, or `Tile.LOCKED_DOOR`, with `sight_transparent`
clearing. 33 chunk scripts; **3** call `add_sight_blocker`; **0** reference `Tile.WALL`; **0** call
`set_tile`. A dynamic blocker is indeed invisible to sight.

**But grids built from DATA do get real wall tiles.** `GridWorld.from_data` fills `Tile.WALL` both
from `default_walkable: false` and from an explicit `wall_cells` list. So every grid that arrives
through the grid-data contract — the generated stretches, and any fragment whose `.tres` declares
`grid.wall_cells` — is sight-opaque exactly as intended. "~91% of shipped content is a free teleport"
does not survive contact with that path.

**The sharper hazard, which the panel missed and which is worse because it is silent:** a data
fragment declares its walls **twice, independently**. `Fragment.walls` (`scenes/fragments/fragment.gd`)
is a list of visual boxes with collision, built by `data_fragment_chunk.gd:145` as geometry. The
`Fragment.grid` dictionary is a *separate optional export* fed to `GridWorld.from_data`. **Nothing
checks the two agree.** A fragment can therefore draw a wall you cannot walk through and cannot see
past visually, while its grid never marks that cell opaque — so detection, and now a throw, pass
straight through a wall the player is looking at. That divergence already affects enemy sight today;
the throw just makes it exploitable and obvious.

**Adopt the opt-in ruling, and add one check.** `throw_enabled := false` per chunk stands — it is
correct for the authoring-debt reason given. But the coverage test should not merely probe for *some*
occlusion; it should assert **`Fragment.walls` and grid opacity agree**, so the two declarations
cannot silently drift. That check is worth having whether or not throwing ships.

---

## 3. The gesture

**Source — the party-hands strip.** Not the portrait cards. `game_hud.gd:330-331` wires `card.gui_input` on a `MOUSE_FILTER_STOP` card and `_on_portrait_input` (`:934`) consumes LMB-pressed to select; a STOP child pip inside that card receives `gui_input` first in its own rect and kills tap-to-select, which on touch is the primary selection affordance. Instead, `_hands_section` is generalised from one bound character to the whole party: one chip per held item, each labelled with its owner, each carrying `item_id` and `owner_id` as metadata. The data is already computed — `fragment_preview_sequence.gd:2912-2930` builds exactly this table for its CARRY label. In practice the strip is short: six characters, two slots each, but rarely more than three or four items in hand at once.

Each chip is `MOUSE_FILTER_STOP` with `set_meta("blocks_world_commands", true)`. That single fact closes both input hazards for free: `selection_controller._command_belongs_to_gui()` (`:524-528`) reads exactly that meta and suppresses the RIGHT-button world command, and `touch_mode_controller` (`:166`) yields the pointer to a hovered STOP control before it can start a camera pan, a marquee, or a rally.

**Owner — `scripts/game/characters/throw_drag_controller.gd`**, sibling of `selection_controller.gd`, whose header (`:12-14`) documents this exact placement law: input handling lives in `scripts/game/`, never in a sequence, so `--test-sequence-input-discipline` (which scans only `res://scripts/tutorial/*_sequence.gd`) is satisfied structurally rather than by luck. `process_mode = PROCESS_MODE_ALWAYS` so it lives during scheduler pause — the mode the feature exists for — plus an explicit `get_tree().paused` guard so it is dead over the pause menu. Those are two different pauses and getting them backwards makes the gesture either dead when it matters or live over the menu.

**No Godot DnD.** `_get_drag_data`/`_drop_data` resolve only Control-to-Control and cannot deliver a drop onto a 3D body; using them for portraits and a hand-rolled tracker for the world means two claimants that must agree on threshold, cancel and touch, with `TouchModeController` as a third. One custom pointer drag: press on a chip arms it, motion past `DRAG_THRESHOLD` (10.0, the number `selection_controller.gd:23` and `touch_mode_controller.gd:27` already share) starts it, release resolves it.

**Target resolution — one function, three shapes, in order.** `resolve_throw_target(screen_pos)` returns `{kind, id, point}`: a hovered Control walked up to a portrait card gives `{kind="char", id}`; otherwise an unproject-pick over party then enemy render positions within `PICK_SCREEN_RADIUS` 56 px, using `camera.unproject_position(game_state.get_render_position(id))` — the exact math `selection_controller.gd:1114-1130` already uses, so warped scenes work for free — gives `{kind="char"|"enemy", id}`; otherwise a ground point from `player.gd`, the only owner of the ground raycast (`:800`), exposed as a thin `project_ground_point(screen_pos)`, giving `{kind="cell", point}`.

**Frame conversion happens here, once.** A ground point arrives in RENDER space; every GameState API expects DATA space. If `coord_map != null` it goes through `coord_map.to_data()` at this boundary — the pattern `fragment_preview_sequence.gd:2794-2801` already uses. `_warn_if_off_frame` (`game_state.gd:1486`) is the permanent net, and it exists because a render-frame point once teleported a party member and the cause outran four instrumentation passes.

**What the player sees.** Armed: the chip dims and a swatch rides the cursor. Over a legal target: `PathRenderManager` draws a ground ribbon from thrower to the solved landing point, its existing destination RING at the landing cell, and the refusal-free tint. Over an illegal target: the ribbon takes the refused tint and one line rides the cursor with the reason — `no line` / `out of arc` / `not throwable` / `no floor there` / `throwing off here`. The reason is visible before release, so a doomed throw is never committed.

The ribbon and ring are genuine reuse. The item ghost is not — `PathRenderManager._build_dest_ghost` duplicates a *character* node and there is no item-ghost path. Spec 3 over-claimed this. Budget it as new geometry in the manager, small, and it must satisfy `--test-overlay-materials` itself (the preview scene drops the alpha-BLEND pass; a blended floor overlay is invisible there).

**Paused reading.** SPACE pauses the gameplay lane only (`tutorial_sequence.gd:1310-1322` calls `_scheduler.pause()`, not the tree). The throw commits and logs at the frozen tick; the item leaves the hand immediately and hangs in the air at flight fraction zero, because its position is a pure function of the scheduler tick. On resume it flies. There is no queued-throw state, no windup, and no separate deferral system to maintain — this is exactly how a queued MOVE already behaves, and it is free.

**Cancel.** ESC, or release over nothing legal, or drag back onto the source chip. Nothing is logged in any of those cases; a refused gesture is not a command. **Right-click is explicitly not a cancel** — `selection_controller._input` (`:126-173`) captures RIGHT before GUI dispatch and steps aside only via `gui_get_hovered_control()`, which is null mid-drag over the viewport, so a right-click cancel would also fire a party move command. Two sibling nodes both implementing `_input` have no guaranteed ordering; do not rely on one.

**Touch.** The drag can only begin on a STOP HUD chip, which `touch_mode_controller.gd:166` already yields to, so it is unambiguous in all three touch modes and cannot collide with two-finger pan or pinch. A second finger arriving mid-drag drops the drag and returns the item, logging nothing. While dragging on touch the cursor-line offset flips above the finger and the world pick radius widens to 72 px, because the finger occludes the target.

---

## 4. The command

One logged KIND. The geometry is SOLVED before the emit and baked into the payload, so replay re-runs the landing with the recorded point and never re-solves — there is no divergence surface in the solver at all.

```
KIND_THROW_ITEM  = "throw_item"

{
  "item_id":  String,
  "from":     String,          # thrower char_id
  "landing":  [x, y, z],       # DATA frame, y from grid_to_world(cell, level)
  "level":    int,             # destination level
  "flight":   float,           # ticks, from the analytic solve
  "aim":      String,          # id the player dropped on; "" for a bare cell
}
```

`aim` is a hint used only for the auto-pickup convenience at landing. It is never a target the throw resolves against, carries no velocity, no force, no damage, and cannot express "hit that thing."

Adding the KIND is a **three-place change** — the const block in `game_event.gd:41-48`, the `ALL_KINDS` array at `:121-184` (because `make()` asserts membership at `:186`), and a `_dispatch` arm at `game_state.gd:6833`. Miss the dispatch arm and the event serialises fine, replays as nothing, and `state_hash()` diverges only under the replay tests.

**Two public functions, one solver.**

`command_throw_item(from_id, item_id, target_kind, target_id_or_point) -> Dictionary` solves and, on success only, delegates. It does not emit; it goes on the mutation-audit allowlist with the `throw_physics_object_to` justification shape (`test_runner_cli.gd:51865-51867`): *"solves the lead and delegates to `throw_item`, which emits."* On refusal it returns `{ok=false, reason=…}` and nothing enters the log.

`throw_item(from_id, item_id, landing, flight, aim) -> void` **emits first, then validates** — the house pattern at `throw_physics_object:6439`, `transfer_item:4852`, `pick_up_item:4810`. Validating first and emitting only on success makes live play and replay diverge whenever a refusal is timing-dependent, which for this mechanic is the normal case.

Plus two pure reads, both allowlisted: `solve_throw(...)` (the preview, returning `{ok, reason, landing, flight}`) and `get_item_position(item_id)` (held → hand offset; ground → stored position; airborne → the parabola at `scheduler.get_current_tick()`, mirroring `get_physics_position`'s branch at `:5147-5153`).

**What stays derived, never logged:** the drag, the hovered target, the refusal string, the ribbon, the ring, the ghost, the outline registration. And critically **the landing itself** — a scheduled callback under tag `throw_item_<id>`, exactly like `_on_throw_landing:6558`, never a second logged event. `event_log.append` asserts monotonically non-decreasing ticks (`event_log.gd:44-47`); a second event at the landing tick would either trip that assert on reorder or create a second source of truth. The auto-pickup is likewise derived: a pure function of the logged throw plus the logged movements plus the tick.

**One new piece of derived state GameState genuinely needs.** `register_character` (`game_state.gd:298-307`) gives **every** registered character `hands: [null, null]` — enemies included. So an auto-pickup gated on free hands would let an enemy catch a thrown item. GameState has no roster concept at all (no `is_enemy`, no faction, flat `characters`). Add `party_ids: Dictionary`, set by the sequence at registration, derived and never logged, allowlisted with the concealment/distraction justification (`test_runner_cli.gd:51855-51859`). It is small, it is honest, and more than this feature wants it.

**Serialisation.** `_serialize_items` (`:2505-2517`) writes exactly type/holder/location/position/properties and drops unknown keys, so an airborne item would silently teleport home across a save. It needs the `flight` record with a remaining-tick count — the shape `_serialize_physics_objects` already uses for an in-flight throw at `:2636-2647` — plus the matching restore and re-schedule, plus an `"airborne"` branch in every existing `items` consumer that today assumes ground|hand|internal. That is three edits and a sweep, not a one-liner.

**Data-layer parity.** `SimCommand.throw_item(item_id, target_kind, target_id)` and `throw_item_to(item_id, x, z)` beside `throw_object` (`sim_command.gd:133`); `_throw_item`/`_throw_item_to` in `sim_runner.gd` beside `_give_item` (`:283`); CLI verbs `pass <item> <char>`, `lob <item> <enemy>`, `toss <item> <x> <z>`, and `throwinfo <item> <target>` as a pure read that prints the solve without mutating. `throw` keeps its existing physics-object meaning so nothing shifts. Both paths converge on `command_throw_item`, so a CLI refusal and a GUI refusal are the same code returning the same reason string.

One gap the specs missed: the fixture form `assert endo_hands has hushbloom_1` does not parse. `cli_game.gd:242-247` implements `assert <stat> <op> <float>` only. The assertion vocabulary needs a set-membership form before a headless fixture can prove a hand-off, and that is part of the stage-1 budget.

---

## 5. The intercept solve

Everything is solved once, in closed form, at the release tick. Nothing about the outcome is discovered by sampling — the discipline `_solve_quadratic_detection` (`game_state.gd:8618`) already sets, and the one the channels hide-window surge taught the hard way when a per-frame flood-coincidence sample diverged at 1× versus 10×.

**Constants are promoted, not invented.** `throw_physics_object_to` already hardcodes `t = clampf(horizontal / 6.0, 0.45, 2.5)` (`:6552`) — a 6 m/s arm and a 2.5 s ceiling. Name them `THROW_XZ_SPEED := 6.0` and `THROW_MAX_ARC := 2.5`, giving a ~15 m envelope that falls off with height difference. It is a consequence of the existing solver, visible to the player as the preview ribbon falling short, not a new tuning dial.

**The lead.** Take the target's piecewise-linear future from `_get_movement_segments(target_id)` (`:4203`) — `{start_tick, end_tick, start_pos, velocity}`, including the trailing parked segment out to tick `1e12` (`:4253-4264`) so a stationary target is still solvable. For each segment clipped to its window, advance its start to `t0` giving target position `q` and constant XZ velocity `u`, let `d = (q − p)` in XZ with `p` the thrower's launch point, and solve

> **`(|u|² − v²)·t² + 2(d·u)·t + |d|² = 0`,  `v = THROW_XZ_SPEED`**

for the smallest positive root inside that segment's window. Degenerate `|u|² ≈ v²` collapses to `t = −|d|² / (2 d·u)`, valid only when `d·u < 0`, handled exactly as `_solve_quadratic_detection` handles its degenerate `a`. Negative discriminant or no root in the window → next segment. First hit wins. A static target is not a special case: `u = 0` reduces it to `t = |d| / v`, one code path.

This is exact and iteration-free, which is why it beats the two-pass fixed point `enemy.gd:1071-1074` uses for the charge lunge. That fixed point is right when the mover's own speed is unknown; here the projectile speed is fixed and the segment is linear, so there is no convergence tolerance that could drift between 1× and 10×.

**The consistency check — this is the bug all three specs shipped.** After the root, assert `|p − landing| / t` is within tolerance of `THROW_XZ_SPEED` and that `t <= THROW_MAX_ARC`. Without it, a clamped flight time and an unclamped landing point disagree and the item's implied speed is unbounded — a receiver running at `run_speed` 6.0 from 12 m needs 4.0 s, which the 2.5 s ceiling silently truncates, and the projectile teleports. Failing the check refuses with `out of arc`, which is a legible refusal, never a silent miss.

**The vertical, which the segments cannot give you.** `_get_movement_segments` zeroes Y in **every** branch — verified at all seven `Vector3(` constructions in the function. So the solved landing has `y = 0` structurally. Derive it instead: `landing.y = grid_to_world(world_to_grid(landing_xz), level).y`. Spec 1 and 3 both fed the segment straight through and would have landed every above-ground throw on level 0's plane, and every throw in a modeled room inside the floor slab (the RoomModelBinder `floor_surface_y` pattern — the aster room's is 0.15). Then invert the parabola exactly as `throw_physics_object_to:6552`: `vy = (landing.y − p.y + 0.5·PENDULUM_GRAVITY·t²) / t`, with `PENDULUM_GRAVITY := 9.8` (`:6628`). Apex is cosmetic.

**Riding the tick.** Commit stores `land_tick = commit_tick + t` and schedules exactly one callback under tag `"throw_item_" + item_id` — the discipline of `"throw_" + obj_id` at `:6520`. In-flight position is `get_item_position`, interpolating XZ and evaluating the parabola in Y from `scheduler.get_current_tick()`. The visual **reads that function and never integrates `delta`**, which is what makes it correct while paused, correct under hold-F (speed multiplies, `land_tick` does not move), and correct after a save.

**The item is not registered as a physics object.** This is a safety decision as much as a performance one, and it dodges three verified defects: `_recompute_physics_predictions` (`:5203`) is O(chars×objects + objects²) and re-runs on every registration, throw, landing and slide; its collision prediction is planar because `_get_physics_segments` zeroes Y (`:5170`, `:5183`), so a pod arcing three metres over someone's head registers as a hit on whoever is underneath; and `_on_physics_collision_event` (`:5274`) emits `physics_collision(obj_id, collider_id, velocity)` — the impact-velocity signature that is one handler away from being the attack verb. The airborne-item lane has no collision prediction at all. It flies from `p` to `landing` and lands. Bodies in between are irrelevant, which is both correct for a lob and cheap. It also skips `_trace_slide_against_walls` (`:5347`), which traces against `is_walkable` and would truncate a lob over a chasm and drop it *into* the chasm.

---

## 6. The LOS rule

A throw from `A` to point `P` is legal iff all of:

| # | Gate | Source |
| --- | --- | --- |
| 1 | Frame converted to DATA space first | `coord_map.to_data()`, the `fragment_preview_sequence.gd:2794` pattern |
| 2 | `grid.has_line_of_sight(a_xz, p_xz)` | `grid_world.gd:846` — ≥2 samples per cell, endpoint cells skipped, first `is_opaque_cell` fails it |
| 3 | Ballistic envelope satisfied | §5's consistency check |
| 4 | Landing cell walkable on the destination level | `is_walkable(x, z, {}, locked_doors, level)` with the **live** locked-door set |
| 5 | `abs(from_level − to_level) <= 1` | see below |
| 6 | Fragment has `throw_enabled` | §2 |

Gate 2 is the deterministic grid walk, not a physics raycast — its own comment says so, and it is the same predicate enemy detection gates on (`_has_detection_los:4134`), so the player's throw and the enemy's sight obey one authority. §1j's "one occluder, three readings" holds exactly.

**Cross-floor is allowed for adjacent levels, and this is a reversal of all three specs.** They all refused it, on the implementation ground that `has_line_of_sight` is XZ-only and level-blind. But the ladder shuttle — walk to the ladder, climb, walk back — is the single worst instance of the chore the director named, and "toss it up to Endo on the gantry" is the most legible use of the entire verb. Refusing it does not keep the promise. The honest v1 rule is gate 5 plus gate 4: the landing cell must be walkable on the destination level (`level_allowed` already enforces per-level footprints), and LOS is evaluated on the shared XZ opacity set. **Flag: `is_opaque_cell` has one dict for all levels, so a wall on floor 0 blocks a throw between two points on floor 1 above it.** That is a conservative error — it refuses throws it should allow, never allows one it should refuse — so it is safe to ship, but per-level opacity is real future work and should be written down as owed.

**`sight_transparent` does not grant throw-over.** `add_sight_transparent` (`:829`) marks a WALL-tiled cell that blocks movement but not sight — water basins, canals, pits, low kerbs. Inheriting it into the throw predicate would retroactively turn every see-through-impassable cell in every already-authored level into a key-delivery chute, with no audit and no author intent, and every future registration would silently inherit the new meaning. Spec 3 went further and used it as a cross-floor licence, which it cannot support — it is a same-plane marker with no vertical semantics at all, so standing near a canal would license a throw to another floor. **Throw traversal gets its own predicate, `is_throw_blocking_cell`, seeded from `is_opaque_cell` but with `sight_transparent` NOT clearing it.** An author who wants a see-over-and-throw-over gap clears it explicitly. This is one small function and it protects every timed-current and hazard-band puzzle in the game.

**What happens when LOS breaks between commit and resolution: nothing.** The gate is commit-time only, and it is never re-checked. Two reasons. First, the lever must be legible geometry read at the moment the player commits; a throw invalidated by something that wandered into the line afterwards is unreadable, and a body does not block a lob anyway. Second, re-checking means sampling during flight, which is exactly the per-frame discovery that broke fast-forward invariance in the channels. Spec 1's mid-flight re-check was justified solely by runtime `LOCKED_DOOR` mutation — which is written at runtime in exactly one place repo-wide (a test), by no chunk, with no `KIND_SET_TILE` to replay it, so the clipped landing would be persistent state replay could not reproduce. It also snaps the item backward along an arc the player already watched to 90%. Deleted.

One commit, one solve, one landing tick.

---

## 7. Failure modes

Deleting the catch collapses what were six branches into one, and that is the single biggest simplification in this spec.

| Case | Outcome |
| --- | --- |
| **Refused at commit** (no line, out of arc, not throwable, unwalkable landing, throwing off) | Nothing logged, nothing consumed, nothing moved. The reason was on the cursor before release. A refused gesture is not a command, and replay sees nothing because nothing was emitted. |
| **Target re-pathed; the throw "misses"** | The item lands at the solved point, on the ground, retrievable. The ring showed exactly where it would land before the player committed. No re-homing — that would break both the fiction and fast-forward invariance. |
| **Intended receiver moved away** | Same: it is on the ground where you aimed it. Because there is no catch, a stale aim costs a short walk, not a lost item. This is precisely why deleting the catch is load-bearing: it makes the commit-time solve safe. |
| **Receiver's hands full at landing** | The auto-pickup convenience declines; the item is on the ground. Checked at the landing tick against `has_free_hands` and `party_ids`, never at commit, because the receiver's hands can change during flight. |
| **Receiver downed, endocytosing, or mid external traversal at landing** | Auto-pickup declines; item on the ground. Same block list `transfer_item:4855` already uses. |
| **Target enemy dies mid-flight** | Structurally a non-event. The throw resolves against a point, not a body; there is no hit and therefore no corpse case. Contrast `Enemy._resolve_strike`, which needed an explicit `hp > 0` re-check. |
| **Thrower downed mid-flight** | Irrelevant. The item left the hand at the commit tick — `slows_carrier` stops applying immediately — and the flight is owned by the scheduler, not the body. |
| **Scene teardown mid-flight** | The landing rides `scheduler.schedule_at` under a tag, cleared when `tutorial_sequence` clears both lanes. There is no `get_tree().create_timer()` anywhere in this feature, so no `Lambda capture … was freed` — the law `--test-elevator-teardown-clean` guards. |
| **Save mid-flight** | The `flight` record serialises with a remaining-tick count and re-schedules on load. Requires the three edits in §4. |
| **Landing cell becomes unwalkable later** (rising water, a pushed crate, a closed gate) | The item migrates to the nearest walkable cell at that moment. No spec handled this and the no-softlock invariant genuinely needs it — commit-time validation cannot cover a world that changes. Stage 4. |

**The item is never destroyed in any branch.** That is the invariant to test.

---

## 8. Tool delivery, not the attack verb — and the honest answer

The director asked for "dragging things onto enemies … to ensure a hit." Here is the part that needs saying out loud rather than being buried in a failure-mode bullet.

**In v1, nothing a throw delivers does anything on arrival.** The payload table is empty. `throwable` is opt-in per item type; `on_land` does not exist yet. What lands is an item lying on a floor. Enemy-targeting is fully built — the drag resolves an enemy, the intercept solve leads its committed plan, the ring shows the predicted point — but the thing that arrives is inert. This is 100% of the Subnautica fix, and it is the only version of the feature I can defend against law 1 today.

**The three structural guarantees, which hold regardless of what ships later.** The command has no target body — the only spatial argument is a point, and `aim` can only trigger a hand transfer. Impact velocity is never computed, stored, or exposed; there is no expression anywhere in the feature that multiplies a speed by a mass. And because a thrown item is never a physics object, `_on_physics_collision_event`'s `(obj_id, collider_id, velocity)` signature is never reached by one — there is nothing to accidentally wire.

**Why the payloads are held back, specifically.** All three specs proposed `hushbloom → stun_burst` as the flagship, citing `Hushbloom.burst_at` (`hushbloom.gd:231`) whose docstring already reads *"also the THROWN use"* and which has zero callers. It is genuinely pre-wired. It is also, verified:

- **`Enemy.stun()` is not gated.** `apply_emp` refuses when `not emp_compatible` (`enemy.gd:405-409`, asserted at `test_runner_cli.gd:55770` — "a biological/default enemy rejects EMP"). `stun()` (`:391-403`) has no such gate and stuns anything. A thrown bloom would be the **first universal ranged disable in the game**, effective against creatures the canon ability deliberately cannot touch.
- **It refreshes on re-stun.** `:398-402` explicitly replaces the deadline rather than ignoring the second stun. N banked blooms is 4N seconds of a hard hold that cancels movement and scanning.
- **It out-ranges perception.** ~15 m envelope against `detection_range := 6.0` (`enemy.gd:21`). You disable from outside the thing's detection envelope, with a lead advertised as ensuring a hit.

Zero HP changes and combat is solved by throwing. A `--test-throw-is-not-a-weapon` asserting HP unchanged would sit green while the law is broken, because the law is about the verb, not the stat.

**There is a second reason payloads cannot ship in v1 even if the balance were fine: they have no owner.** `burst_at` takes arrays of scene NODES and calls `e.stun()` on an Enemy node. GameState holds no node references and must not. So the effect either moves into GameState — which has no stun concept at all — or it becomes a scene-side signal handler, which makes it per-scene, invisible to `serialize()`, and therefore invisible to `state_hash()`. Either way the replay test proves the item replayed and says nothing about the effect. That is a real architectural question, not a wiring detail, and it deserves its own decision rather than being smuggled in under a logistics feature.

**What I recommend when payloads do ship (§10, Q2).** Not stun first. `flure_seed → scent_broadcast` — re-siting a lure is the canonical ROUTING verb, it composes with the lure relay instead of skipping it, and it cannot read as a strike. Then reassess. And `fire_fruit` must be `throwable: false` permanently: it is the only item in `item_data.gd` carrying a `damage` field (20.0, `:50-57`, today self-inflicted via `endocytosis_effect: "self_damage"`), and any generic "run the item's effect where it lands" rule hands the player a grenade in one line of shared code.

**The honest concession.** Even inert, a throw into an enemy's lane is an *aimed* action against a creature, and it will read as an attack to some players the first time they do it. The mitigation is language and consequence, not mechanics: the cursor verb is `Pass` and `Place`, never `Throw at`; the HUD never says missed; and the curriculum introduces the pass as supply across a gap long before anything is ever aimed at a body. If the director wants the aimed-at-enemy gesture to feel like *doing something*, that is exactly the payload question in §10 and it should be answered deliberately, once.

---

## 9. Degenerate play

**The bucket brigade.** Six characters spaced along the envelope relay an item across a level with no walking. Deleting the catch does not kill it — auto-pickup plus re-throw chains just as well. Three prices, all needed:

1. **Distance-priced stamina.** `throw_stamina = base + k·distance`, tuned so a hop costs roughly what walking it costs. A flat cost cannot work: against `STAMINA_MAX 100`, run drain 15/sec, `DODGE_STAMINA_COST 15`, `FIELD_RESTORE_STAMINA_COST 60`, a flat 6.0 is 0.4 seconds of sprinting — 16 throws per bar. Deduct via the private path `dodge_roll` uses (`ch.stats["stamina"] = …`, `:4495`) rather than `adjust_stat`, which would `_emit` a second `KIND_SET_STAT` per throw and make the throw command's replay depend on `set_stat` being absolute rather than a delta.
2. **A per-character throw cooldown on the gameplay lane**, so one pause cannot issue a whole brigade.
3. **`throwable` is opt-in.** Not opt-out. This is the inversion that makes every other guard cheap.

**The opt-in allowlist, v1.**

| Item | Throwable | Why |
| --- | --- | --- |
| `lysate`, `seed` | yes | Supply movement, no puzzle role |
| `fragment` | **no** | `slows_carrier: true, speed_multiplier: 0.5` — it IS the slow-carry price, the archetype §1j names by name. Spec 3 marked it throwable, which voids the one carry-cost mechanic that exists in data. |
| `mother_gear` | **no** | `hand_slots: 2`; `mother_flure_chunk.gd:1320/1380` gates an authored beat on Endo walking a specific carry lane. A body that needs both arms cannot throw — a fiction-grounded class rule, not an invented stat. |
| `cure_component` | **no** | `adds_to_collection: true` — an objective item. An unrecoverable loss must not be possible by omission. |
| `fire_fruit`, `gas_sac`, `curecumin` | **no** | §8 / sealed / permanent upgrade |
| `hushbloom`, `flure_seed` | **no in v1** | Payload items; see §8 and §10 Q2 |

**The retrievability guard, corrected.** All three specs proposed a "round-trip `grid.reachable()`" check citing §1j's directedness caveat. **`reachable()` is provably symmetric.** `_reach_walkable` is a pure per-cell predicate, and the diagonal corner-cut test from `c` toward `n` checks `(c.x+dir.x, c.y)` and `(c.x, c.y+dir.y)` — traversed from `n` with `−dir` it evaluates the identical pair. So `reachable(A,B) == reachable(B,A)` always, the round trip is one call's worth of information, and the `[throw/one-way-target]` report line §1j specifies can never fire from it. Worse, it *refuses the mechanic's headline case*: one-way-ness lives in inter-level links and external traversals, never in cell walkability, so a teammate stranded past a one-way drop is a disconnected walkable region and the throw to them gets refused — the exact thing the feature exists for.

So: **the real guard is gate 4 — the landing cell must be walkable on the destination level, with the live locked-door set passed in.** (`_reach_walkable` calls `is_walkable(x, z, {}, {}, level)` with an *empty* locked-doors dict, so any BFS built on it walks straight through every locked door — which is how Spec 1's softlock guard would have permitted throwing into locked rooms.) Combined with objective items being unthrowable and payloads being absent, the softlock surface in v1 is a walk, not a run-ender. The genuinely directed §1j check belongs to the economy layer's directed model and should be cited there, not faked with this predicate.

**Puzzle skips still open, and their answers.** A key past an Interactable gate: gates built as objects on walkable cells are neither `WALL` tiles nor sight blockers, so the line passes through them — a fragment that gates with an object and opts into throwing must register a sight blocker on the gate cell, and `--test-throw-occlusion-coverage` is where that gets caught. Throwing from `CONCEAL_FULL`: harmless in v1 because nothing lands with an effect, but **the day a payload ships, a throw must break the thrower's concealment for a beat**, or a hidden character delivers from a shelter at zero risk. Write that into the payload stage, not v1.

**Transitivity.** §1j widens `carried` reachability to party-walk plus an LOS hop. It is a *closure*, not a single edge: with six members the hop chains A→B→C→D in one paused turn. Any solvability proof modelling one hop under-counts. The generator's predicate is **not** widened in v1 (`allow_throw_hop` defaults false) precisely because throwing is opt-in per fragment and the proof would otherwise change meaning silently for 30 levels that never turned it on.

---

## 10. Implementation plan

Smallest shippable slice first. Each stage is committable and green on its own.

**Stage 1 — the data layer, no GUI.** `game_event.gd` (const + `ALL_KINDS`), `game_state.gd` (`_dispatch` arm, `command_throw_item`, `throw_item`, `solve_throw`, `get_item_position`, `_on_item_landing`, `party_ids`, the `_solve_quadratic_intercept` static beside `_solve_quadratic_detection`), `grid_world.gd` (`is_throw_blocking_cell`), `item_data.gd` (`throwable` opt-in + `throw_stamina`), `scene_chunk` (`throw_enabled := false`). No UI, no presenter. Guards: `--test-throw-item-analytic` (the quadratic against a brute-force sample for a straight mover, a corner-turner, and a parked target; the degenerate and no-root cases refuse), `--test-throw-los-gate` (blocker refuses, cleared permits, `sight_transparent` does **not** permit, adjacent-level permits, two-levels refuses), `--test-throw-fast-forward-invariance` (same landing tick, point and verdict at ~0.0166 and ~0.166 steps), `--test-event-log-mutation-audit` stays green with three new allowlist entries.

**Stage 2 — CLI and replay.** `sim_command.gd`, `sim_runner.gd`, `cli_game.gd` (`pass`/`lob`/`toss`/`throwinfo` + the `assert … has …` set-membership form), `_serialize_items`/`_restore_items` + the `"airborne"` branch sweep, a fixture in `data/playthroughs/`. Guards: `--test-throw-replay-determinism` (three throws — clean auto-pickup, stale-aim ground landing, hands-full ground landing — identical `state_hash()`, and exactly three `KIND_THROW_ITEM` events with zero landing/pickup events, proving both stayed derived), `--test-throw-serialize-midflight`, `--test-sim-command-api` extended.

**Stage 3 — the presenter and the gesture.** `party_item_controller.gd` (the airborne arm reading `get_item_position` through the existing `_to_render_position:630`, which `physics_object_3d.gd:10-17` notably fails to do), `path_render_manager.gd` (arc ribbon + landing ring + item ghost, with its `--test-overlay-materials` entry), `game_hud.gd` (`_hands_section` generalised to the party strip; state the `get_hud_contract()` change explicitly rather than slipping it in), `scenes/ui/hud_hand_chip.tscn` (STOP + meta + 44 px minimum), `throw_drag_controller.gd`. Guards: `--test-throw-drag-gesture` (a sub-threshold press is a tap not a throw; the press leaks no world command and arms no marquee; ESC logs nothing; a release over an illegal target logs nothing and surfaces the reason), `--test-throw-preview-matches-committed` (`solve_throw` returns exactly what `command_throw_item` executes), `--test-throw-warped-frame`, `--test-input-playthrough` extended with a real-input leg asserting the emitted payload is identical to `SimCommand.throw_item`'s.

**Stage 4 — content opt-in and the guards that make it honest.** Turn `throw_enabled` on in the three fragments that already register occluders; author occluders where a fourth is wanted. Guards: `--test-throw-occlusion-coverage` — for every `PREVIEW_ENTRIES` fragment with `throw_enabled`, sample N random walkable pairs within the envelope and require a minimum blocked fraction. **Not** "zero opaque cells," which passes on any grid with a wall border and would have shipped the hole. Plus the unwalkable-migration rule from §7 and `--test-throw-no-softlock`.

**Stage 5 — payloads, director-gated.** Blocked on §11 Q2. Whatever ships needs `ItemLandingDispatcher` in one scannable file, a closed `on_land` allowlist, the concealment break, `--test-canon-mechanics` extended to lint `on_land` values and `adjust_stat(` with `"hp"` in the landing path, and a `--test-throw-is-not-a-weapon` that runs in a **live fragment** asserting positively that the intended effect fired alongside HP unchanged — because a pure-GameState version of that test is green when nothing is wired at all.

---

## 11. What needs the director

**Q1 — Is inert-v1 acceptable?** The request says dragging onto an enemy throws things *at* them. I am shipping the gesture and the intercept and delivering an inert object, because the obvious payload (Hushbloom stun) is the first universal ranged disable in the game, refreshes on re-stun into an indefinite lock, and works from outside the enemy's detection range. If the felt experience of "I did something to that thing" is required in v1, that is a different feature and it needs the ruling below first.

**Q2 — Which payload, and does it get the StrikeableCluster treatment?** `ENVIRONMENT_ELEMENTS.md:324` records that adding a player strike needs an explicit director-approved class. A delivered stun is not damage but it *is* an encounter answer, so it sits on that boundary. My recommendation: `flure_seed` scent first (routing, composes with the lure relay rather than skipping it), stun deferred and, if approved, gated to `emp_compatible` so it inherits the existing biological-immunity rule, capped against refresh-chaining, and given an envelope *shorter* than `detection_range 6.0` so delivering costs exposure.

**Q3 — "Ensure a hit" is not what the math can promise.** Enemies re-path constantly — roam issues one short hop at a time, pursuit re-plans on each rescan — and commit happens during pause, when the plan is a frozen snapshot the FSM will revise the instant you unpause. The lead is exact against the *committed* plan and frequently stale against what actually happens. What would make a delivery connect is a payload *radius*, not the prediction. If that framing is right — "aim at the lane, the effect radius does the connecting" — it is on-message for tool delivery and I will write it that way. If you want the projectile to actually track, that is a homing projectile and it breaks both the fiction and fast-forward invariance; say so and I will bring options.

**Q4 — Cross-floor.** I reversed all three specs and allowed adjacent-level throws, because the ladder shuttle is the worst instance of the chore you named. The cost is that `is_opaque_cell` has one opacity dict for all levels, so a wall on floor 0 can refuse a throw between two points on floor 1. It errs toward refusing, never toward allowing, so it is safe — but confirm you want the vertical toss at all before I spend the per-level-opacity work.

**Q5 — The occlusion debt.** Throwing ships OFF everywhere and turns on per fragment, because 30 of 33 chunks build walls with `add_dynamic_blocker`, which the sight predicate cannot see. The alternative is a global second price (a flat range stat) — which §1j explicitly rejects as "a fourth invisible rule." I have followed §1j and made the debt visible instead. Confirm that opt-in rollout is acceptable, or rule that the range stat is worth its invisibility after all.

**Q6 — Two-handed items and the mother gear.** `mother_gear` stays unthrowable, which preserves the authored Endo carry lane. That is my call on a fiction ground (both arms occupied), not a balance one. If you ever want a two-body carry or a thrown gear, it changes the hand model, not this spec.
