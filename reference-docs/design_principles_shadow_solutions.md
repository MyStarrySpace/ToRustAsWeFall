# Design Principles: Shadow-Solution Layer

Meta-design doc for the game-wide commitment that every major puzzle can be solved by Aster and Peris alone, even when the presented solution involves other party members.

This doc captures the principle, its rationale, its design commitments across the game, and the taxonomy of solution layers.

## The principle

**Every major puzzle in the game has a hidden solution path that can be executed by Aster and Peris alone.**

The hidden solution is not presented to the first-play player, is not required for standard progression, and is not surfaced through tutorial or UI. It exists as a structural option for players who have learned enough of the game's mechanical vocabulary to recognize it. The presented solutions use other party members (Endo carrying, Myke burning, Oli shielding, Tyreg shooting); the hidden solutions substitute Aster and Peris's combined toolkit (overlay-reading, terminal hacking, flora planting, sensory perception).

## Rationale

**Thematic.** Aster and Peris are the base pair. The game opens with them, the endings land on them, their relationship is the load-bearing structure across the entire arc. Every other party member is someone who joined *them*. Mechanically making them the puzzle-completion minimum operationalizes the thematic claim that their relationship is what the game is built on.

**Gameplay.** The shadow-solution layer rewards player mastery. Players who learn the game's mechanical vocabulary deeply find that the game is more open than it appears. Puzzles that seemed to require Endo or Myke turn out to be soluble without them. This gives replays genuine variance and turns the game into something the skilled player can dismantle differently than the first-play player.

**Narrative.** The shadow layer is the mechanical expression of a thematic principle the game argues at every level: that care-work is sufficient. Endo's wall is made of tended bonds. Peris's flora are tended infrastructure. The cure itself is made of care-work rendered as biochemistry. If the game's thesis is that care is sufficient, then the game's mechanics must make care sufficient — at least for Aster and Peris, who are the game's protagonists and whose care for each other is the game's emotional center.

**Meta-narrative.** The game is about a civilization that forgot its own workers. The players who find the shadow-solution layer are doing what the civilization's best practitioners did in-world: they are seeing through the institutional presentation to the actual capabilities underneath. The mechanical structure of the game models the epistemic stance the game is recommending.

## Commitments this imposes on the design

**Every major puzzle must have a designed Aster-Peris solution.** This is not optional. If a puzzle cannot be solved by Aster and Peris alone, the puzzle must be redesigned until it can. The design-time cost is significant but absorbed by the fact that Aster and Peris are always in the party, so the coordinate mechanical affordances (Peris's flora kit, Aster's overlay and hacking) are always available.

**The hidden solution must not be surfaced as a first-play option.** The presented solution uses the additional party member whose contribution the puzzle is built around. The hidden solution exists but is not advertised. Environmental design, UI prompts, and dialogue all assume the presented solution. A player who sees the hidden solution on first play has earned it through observation.

**The hidden solution must be achievable with mechanics the game teaches.** It cannot rely on undocumented edge cases or exploits. The teaching happens organically — via NPC demonstrations (Marco), terminal logs, environmental storytelling, shelter conversations — without being framed as tutorial. The player encounters the information and has to connect it to the puzzles where it applies.

**The hidden solution is typically harder than the presented solution.** It takes more moves, more setup, more resources, or more tactical care. The reward for finding it is not efficiency; it is agency. The player who knows the hidden solution can complete the puzzle without the ally whose contribution was presented as required.

## The three solution layers

**Layer 1: Presented solution.** What the first-play player does. Involves the party member whose contribution is the puzzle's hook. Mother Flure uses Endo carrying the gear. Maintenance Warrens puzzles will use Oli's insulation. Archive Depths puzzles will use Tyreg's enforcement-class authority. Etc. These are the canonical solutions the game teaches through level design and character moments.

**Layer 2: Optimized presented solution.** Players who have internalized the mechanics can execute the presented solution more efficiently — fewer moves, less combat, faster completion. This is standard mastery and requires no special knowledge beyond what the game teaches.

**Layer 3: Shadow solution.** Aster-Peris alone. Requires game-wide mechanical knowledge. Usually harder than Layer 1 but possible. Sequence-break-adjacent. Not a speedrun category per se; a mastery expression.

## Examples and commitments

**Mother Flure chamber (Act 1 end).** 
- Presented: Endo carries the gear; siderophores controlled by party combat tools.
- Shadow: Aster and Peris drag the gear over a pre-planted Scarpet bed. Scarpet reduces friction (enabling the drag) and masks iron signal (preventing siderophore swarm). Requires rapid-germination technique learned from Marco's drag demonstration (separate scene). See `marco_drag_scene.md`.

**Inflammashunt DZ (Act 1 transition / Act 2 early).**
- Presented: Three-route information gathering uses Myke's crawlspace access, Peris's underground flora route, and Aster's terminal route. Each party member contributes a route's information.
- Shadow: Aster can technically access all three routes alone via overlay-scanning with specific environmental conditions; Peris can read the flora without needing Myke's physical access if the flora are mature enough. The shadow solution requires multiple visits and patient information-gathering.
- Status: needs design pass to confirm Aster-Peris feasibility

**Maintenance Warrens puzzles (Act 2 early).**
- Presented: Oli's insulation-reading layer identifies safe vs. hostile conduits; his barrier provides cover in tight corridors.
- Shadow: Aster's overlay can read the conduits through signal-analysis (slower, imperfect, requires active scanning). Peris's Doma can provide pursuit-break cover where Oli's barrier would. The shadow path is slower and requires more resource management.
- Status: needs design pass to confirm

**Archive Depths (Act 2 mid).**
- Presented: Tyreg's institutional-enforcement authority allows bypassing certain checkpoint-protocol interactions. She is Act 2's new face and her recruitment happens here.
- Shadow: Aster's device can emulate enforcement-class credentials via a hack learned at a specific earlier terminal. This is fragile and requires specific conditions. Without Tyreg, the puzzle becomes a stealth-and-timing problem rather than an authority-override problem.
- Status: needs design pass to confirm

**Filtration Membranes (Act 2 late).**
- Presented: Barrier-crossing mechanics use the full party's tools in combination.
- Shadow: Needs design pass.

**Iron Marshes, Resonance Chambers, Dead Zones, Root Archive (Act 3).**
- Presented: Act 3 uses the full party with escalating coordination demands.
- Shadow: Needs design pass across all four sub-areas. Act 3 is the hardest place to maintain this principle because the late-game puzzles are designed to stress full-party coordination. The shadow solutions in Act 3 will be the hardest to design and will require the most player mastery to execute.

## How players learn the shadow solutions

**NPC demonstrations.** Marco is the game's primary shadow-solution teacher. He demonstrates mechanics (Scarpet-drag, rapid germination, applied chemistry) that the player then applies in unexpected places. Marco is positioned across the game specifically to surface mechanics the official party members would not.

**Terminal logs and environmental storytelling.** Construction-era logs reference techniques the workers used that the official party does not. A terminal log describing how construction crews moved heavy materials over Scarpet beds, discovered late-game after the chamber is done, retroactively teaches the Mother Flure shadow solution.

**Shelter conversations.** Late-game shelter conversations where party members mention offhand observations that connect to earlier puzzles. Oli's "Scarpet is what you use to move heavy things" line during a Warrens shelter rest plants the Mother Flure shadow solution alongside its more direct Warrens application.

**Peris's own discovery.** As Peris's relationship with flora deepens, her own practice surfaces capabilities the first-play player did not expect. Rapid germination. Network communication between tended flora. Long-range sensing. These are mechanical surfacing of narrative character growth.

## Anti-principles (what this is not)

**This is not a speedrun system.** Shadow solutions are not about minimizing time. They are about minimizing party-member dependencies. A shadow solution can be slower than the presented solution.

**This is not a difficulty toggle.** The shadow solutions are harder; they are not the "hard mode" of the presented solutions. The shadow layer exists alongside the presented layer; players choose which to use based on knowledge and intent.

**This is not punishment for missing party members.** The game does not force shadow solutions in any situation. If a party member is available, their contribution is always welcome. The shadow solutions matter for expert players and replay players, not for the first-play player who should never realize they are missing anything.

**This is not a secret ending path.** Shadow solutions do not lock or unlock endings. The endings depend on cure-component collection, not on how puzzles were solved. Shadow solutions are mastery expression, not narrative variance.

## Open design questions

- Which puzzles in Acts 2 and 3 have designed shadow solutions vs. need them designed. Systematic pass required.
- Whether any puzzles should resist shadow-solving (e.g., late-game boss mechanics that require specific party abilities by their nature). The commitment is to the principle; some local exceptions may be acceptable if the exception is narratively motivated and not too numerous.
- How the learning of shadow solutions surfaces to the player across the game. Marco's teaching is the first beat; subsequent beats should space out across the acts.
- Whether shadow solutions should unlock achievements or player stat tracking. Default: yes, but invisibly. Completing a puzzle via the shadow path logs something the player can review on replay.

## Related docs

- `mother_flure_spec.md` — first instance of the shadow-solution layer (Scarpet-drag)
- `marco_drag_scene.md` — Marco's demonstration of the Scarpet-drag technique (to be drafted)
- `flora_taxonomy.md` — Scarpet's mechanical properties
- Individual puzzle specs for Acts 2 and 3, as they get drafted, must consider the shadow-solution layer
