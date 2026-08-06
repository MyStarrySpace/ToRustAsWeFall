# Level Design Review Rubric

Use this rubric when reviewing a new fragment, chunk-backed preview, or full level pass.

It is meant to be compact enough to use during iteration, not just at the end.

This complements:

- [Systems-Thinking Puzzle Design Standard](../../docs/SYSTEMS_THINKING_PUZZLE_STANDARD.md)
- [Puzzle Fragment Workflow](/C:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/data/puzzles/README.md)
- [Puzzle Fragment Generation Methodology](/C:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/data/puzzles/puzzle_fragment_generation_methodology.md)
- [Puzzle Fragment Design Template](/C:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/data/puzzles/puzzle_fragment_design_template.md)

## How To Use It

1. Identify the unit under review: `fragment`, `scene chunk`, or `level slice`.
2. State its intended job in one sentence.
3. Check the hard gates first. If any hard gate fails, do not trust a high score.
4. Score each dimension from `0` to `3`.
5. Record the two lowest categories and change those first.

Suggested scale:

- `0`: absent, misleading, or actively harmful
- `1`: present but weak, noisy, or inconsistent
- `2`: solid and shippable
- `3`: strong, memorable, and clearly intentional

## Hard Gates

If the answer to any of these is `no`, the design needs revision even if the total score is high.

- Can the player form a plausible first read within a few seconds?
- Is there one primary insight or decision the beat is about?
- Can the intended causal model and meaningful leverage point be stated clearly?
- Does failure teach something visible or actionable?
- Does every player-facing state change or forced movement visibly identify its cause, active
  effect, and resulting destination/state?
- Can a model error be distinguished from a control, timing, camera, or visibility error?
- Is the critical path readable without relying on tooltips or outside explanation?
- Does the beat support the campaign fantasy of guiding a vulnerable, specialized party through a dangerous expedition?
- For generated content, does the identical spec remain completable by ideal, resource-aware play under Scarcity, with every easier setting acting only as a monotone pressure relaxation?

## Systems-Thinking Diagnostic

Before scoring, record:

- the model the player is expected to form;
- the player's most likely first model and misconception;
- the prediction made before the representative intervention;
- the evidence that confirms or falsifies that prediction;
- the stock, flow, delay, feedback loop, threshold, scale shift, or network change under test;
- the encounter's meaningful leverage point;
- the moment the reasoning is solved;
- how much execution remains after that moment and what new decision it adds.

If these cannot be stated, the design is not ready for numerical tuning.

## Scorecard

### 1. First Read And Readability

- Can the player quickly notice the important objects, route, danger, and goal?
- Do landmarks, lighting, framing, geometry, and overlays point toward the right question?
- Is there a dominant read, or are several candidate reads competing too early?

Score notes:

- `0`: the player does not know what matters
- `1`: the right read exists but is buried
- `2`: the beat reads cleanly
- `3`: the beat reads cleanly and memorably

### 2. Affordance And Feedback

- Do interactables look usable before interaction?
- Does the world answer actions with clear feedback?
- Can the player tell whether something changed, failed, opened, closed, armed, or became unsafe?
- Can the player trace an important consequence back to its action or prior state?
- For forced movement, is there a warning before commitment, a directional cue and involuntary
  motion read during transit, and an arrival/aftermath cue at the named destination?

Score notes:

- `0`: actions feel arbitrary
- `1`: some feedback exists, but cause and effect are muddy
- `2`: consequences are clear
- `3`: consequences are clear and teach the system

### 3. Primary Insight

- Can the core lesson be stated in one sentence?
- Is the fragment teaching one main idea instead of several half-ideas?
- Are secondary textures supporting the main idea instead of crowding it?

Score notes:

- `0`: no stable idea emerges
- `1`: multiple ideas compete
- `2`: one main idea lands
- `3`: one main idea lands and will likely be remembered later

### 4. Failure Pedagogy

- Do common mistakes produce legible consequences?
- After failure, can the player say what they missed?
- Does the design produce "I know what to try next" instead of "I do not know what happened"?
- Does feedback identify a wrong model separately from failed execution?

Score notes:

- `0`: failure is opaque
- `1`: failure punishes more than it teaches
- `2`: failure teaches the next attempt
- `3`: different failures teach different layers of the system

### 5. Pressure Quality

- Does survival pressure sharpen the decision instead of hiding it?
- Are time, ATP, health, night length, or enemy pressure doing useful work?
- Is the player under tension for a reason, or simply under noise?
- Does pressure force prioritization within the system without preventing the player from reading it?

Score notes:

- `0`: pressure obscures the design
- `1`: pressure exists but is not doing focused work
- `2`: pressure reinforces the intended choice
- `3`: pressure creates drama without reducing legibility

### 6. Spatial Composition

- Are safe space, hazard space, commit points, regroup points, and release points legible?
- Does the layout make use of prospect and refuge?
- Is the player given the right amount of overview before commitment?

Score notes:

- `0`: space does not support the mechanics
- `1`: useful space exists but is poorly staged
- `2`: space supports the beat well
- `3`: space itself is part of the lesson and emotion

### 7. Pacing Role

- Is the beat clearly `teach`, `test`, `twist`, `recovery`, `reveal`, or `set-piece`?
- Does it fit well next to the beats before and after it?
- Does it give enough contrast from adjacent beats?
- Once the causal model is solved, does the remaining play introduce a new decision or transfer test?

Score notes:

- `0`: role is unclear
- `1`: role exists but clashes with surrounding pacing
- `2`: role is clear and sequence fit is good
- `3`: role is clear and the beat improves the whole sequence rhythm

### 8. Party Identity And Layering

- Does at least one character feel like the expert here?
- Do overlays add signal instead of replacing spatial design?
- When multiple layers are active, do they combine into understanding instead of clutter?

Score notes:

- `0`: party systems feel interchangeable or noisy
- `1`: identity exists but is underused or confusing
- `2`: role spotlight is clear
- `3`: party asymmetry creates a distinct and satisfying read

### 9. Agency, Recovery, And Alternate Solutions

- Are commits legible before the player takes them?
- Can the player recover from a mistake at an appropriate cost?
- If alternate solutions exist, do they feel smart instead of broken?

Score notes:

- `0`: the beat feels brittle or unfair
- `1`: recovery exists but feels awkward
- `2`: recovery and commitment cost feel fair
- `3`: recovery paths and alternates deepen the design

### 10. Instrumentation And Composability

- Can the beat be tested headlessly?
- Are anchors, state reads, and helper methods exposed cleanly?
- Will this beat still compose well once chained into a larger level?
- Is generation independent of difficulty settings?
- Do replay artifacts record both a stable content fingerprint and the applied pressure projection?
- Does every active gameplay state-machine phase become authoritative at commitment and survive
  save/load/replay, rather than existing only in a scene animation until completion?
- Do player-facing consequences carry portable presentation receipts, while intentionally silent
  bookkeeping declares a specific reason?
- Does live presenter coverage sample warning, active, and arrival phases rather than only endpoints?

Score notes:

- `0`: hard to test and hard to reuse
- `1`: testable only through fragile setup
- `2`: deterministic and reusable
- `3`: deterministic, reusable, and easy to tune

## Interpreting The Score

Max score: `30`

- `26-30`: strong, likely ready for broader sequencing and content polish
- `21-25`: solid core, but there is still one obvious improvement pass left
- `16-20`: promising, but one or two structural issues are still dragging the beat down
- `10-15`: redesign one or more fundamentals before tuning
- `0-9`: do not tune yet; restate the beat's purpose and rebuild

Do not average away a weak `First Read`, `Primary Insight`, or `Failure Pedagogy` score. Those are structural.

## Fragment Expectations

Fragments should usually score well on:

- `First Read And Readability`
- `Primary Insight`
- `Failure Pedagogy`
- `Instrumentation And Composability`

Fragments should usually be rejected if:

- they try to teach more than one main idea
- they rely on lore text to explain the mechanic
- they have no representative failure case
- they are hard to summarize after one attempt

## Scene Chunk Expectations

Chunk-backed previews should usually score well on:

- `Spatial Composition`
- `Party Identity And Layering`
- `Agency, Recovery, And Alternate Solutions`
- `Instrumentation And Composability`

Chunk previews should usually be rejected if:

- the full UI hides the actual geometry instead of clarifying it
- overlays become mandatory because the base scene is unreadable
- the chunk cannot be lifted into a larger level without bespoke rewrites

## Level Slice Expectations

A full level slice should usually score well on:

- `Pacing Role`
- `Pressure Quality`
- `Spatial Composition`
- `Party Identity And Layering`

Level slices should usually be rejected if:

- every room asks for the same kind of thinking
- there is no regroup beat
- danger ramps without new understanding
- the player cannot tell what the expedition accomplished

## Playtest Questions

Ask these after a run:

- What did you think the room was about when you first saw it?
- What changed your plan?
- What killed you or stopped you?
- What did you learn from the failed attempt?
- Which character felt most important here?
- What detail made the room finally click?
- What felt noisy rather than tense?

## Fast Review Template

Copy this into a design note or PR comment:

```md
## Review Target

- `unit`:
- `intended_job`:
- `campaign_role`:

## Hard Gates

- `first_read`: pass / fail
- `one_primary_insight`: pass / fail
- `failure_teaches`: pass / fail
- `consequence_provenance_legible`: pass / fail
- `critical_path_legible`: pass / fail
- `campaign_fantasy_supported`: pass / fail

## Scores

- `first_read_and_readability`:
- `affordance_and_feedback`:
- `primary_insight`:
- `failure_pedagogy`:
- `pressure_quality`:
- `spatial_composition`:
- `pacing_role`:
- `party_identity_and_layering`:
- `agency_recovery_and_alternates`:
- `instrumentation_and_composability`:

- `total`:

## Lowest Two Categories

- `1`:
- `2`:

## Recommended Changes

- `change_1`:
- `change_2`:
- `change_3`:
```

## Source Notes

This rubric is informed by a few repeated ideas from external design sources:

- Portal 2's chamber design emphasis on teaching cleanly, recombining mechanics, and re-testing after art
- Randy Smith's framing of puzzles as an interface problem: visibility, affordance, mapping, feedback, and conceptual model
- Valve's pacing categories of puzzle, exploration, choreography, vista, and combat
- spatial-emotion framing through prospect, refuge, exposure, and denied safety
- difficulty evaluation through player behavior, not just success rate

Reference links:

- [Thinking With Portals: Making A Test Chamber](https://www.gameinformer.com/b/features/archive/2010/03/17/thinking-with-portals-making-a-test-chamber.aspx)
- [Randy Smith GDC notes summary](https://malvasiabianca.org/archives/2009/03/gdc-2009-thursday/)
- [Level Design In A Day Workshop PDF](https://media.gdcvault.com/gdcchina14/presentations/833762_JoelBurgess_MattScott_LeePerry_3_Pacing_EN.pdf)
- [Applying Architecture And Level Design To Game Worlds PDF](https://media.gdcvault.com/gdc2017/Presentations/Brown_Lisa_Applying_3D_Level.pdf)
- [Statistical Modelling of Level Difficulty in Puzzle Games](https://arxiv.org/abs/2107.03305)
- [A Case Study of Expressively Constrainable Level Design](https://grail.cs.washington.edu/wp-content/uploads/2015/08/smith2012acs.pdf)
