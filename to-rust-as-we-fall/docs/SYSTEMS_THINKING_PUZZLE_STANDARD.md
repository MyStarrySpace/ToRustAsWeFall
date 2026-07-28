# Systems-Thinking Puzzle Design Standard

Status: canonical design standard for puzzle, level, encounter, tutorial, and playtest work.

Read this alongside [DESIGN_PRINCIPLES.md](DESIGN_PRINCIPLES.md) and the
[level design review rubric](../data/puzzles/level_design_review_rubric.md).

## The Core Standard

A systems puzzle asks the player to build and revise a causal model:

```text
observe -> infer relationships -> predict -> intervene
        -> inspect consequences -> revise -> transfer
```

Systems thinking is not merely noticing many objects. It is understanding how a system's
elements, interconnections, boundaries, and purpose produce behavior over time; predicting an
intervention; and changing the system to produce a desired effect.

The player does not need perfect information, but the world must provide enough truthful evidence
to form, test, and correct a plausible model. Intentional perception loss may make evidence scarce;
accidental obscurity, broken visibility, ambiguous controls, and unreadable feedback do not.

## The Puzzle Contract

Every puzzle must have explicit answers to these questions before tuning:

1. What system boundary and goal should the player perceive?
2. Which elements and causal relationships are load-bearing?
3. Which stocks, flows, delays, feedback loops, thresholds, or scales matter?
4. What first mental model is the player likely to form?
5. What prediction should that model lead them to make?
6. What intervention is the meaningful leverage point?
7. What likely misconception will failure expose?
8. What visible evidence lets the player revise that misconception?
9. What later situation tests transfer of the same causal structure?
10. When does the reasoning end and repetitive execution begin?

Use `none` when a category genuinely does not apply. Do not silently omit it.

## Systems-Thinking Competencies

Use these as distinct design dimensions rather than a single vague measure of complexity.

| Competency | Player question | Possible puzzle expression |
| --- | --- | --- |
| Boundary and goal | What is part of this problem, and what outcome am I controlling? | One upstream machine controls several rooms; a local objective conflicts with the party goal |
| Interconnection | What affects what? | Highlightable causal links, shared power, gates, channels, flora, enemy responses |
| Direction and polarity | Does this increase, reduce, enable, or inhibit something? | Opening one route lowers pressure elsewhere; feeding one stock starves another |
| Stocks and flows | What accumulates, depletes, enters, and leaves? | Water, pressure, hunger, ATP, health, trust, enemy attention |
| Delay | When will the consequence arrive? | Surge travel, germination, enemy investigation, delayed drain or recovery |
| Feedback | Does the result amplify or counteract its cause? | Escalating pursuit, stabilizing relief valve, recoverable or runaway hunger loops |
| Nonlinearity | Where are the capacity limits and thresholds? | Overflow, detection threshold, bridge load, channel capacity, critical food state |
| Dynamic behavior | How does the whole system change over time? | Oscillation, phase alignment, emergent enemy-channel interaction |
| Scale and perspective | Is the locally sensible action globally useful? | One character's safe move strands the party; separate perception registers reveal different truths |
| Abstraction and transfer | Have I seen this relationship in another form? | The same balancing loop reappears as water, enemies, flora, or party positioning |
| Leverage | Which small intervention changes the most downstream behavior? | Reroute information or flow, change topology, alter a rule, expose a hidden connection |

## Difficulty Is Multidimensional

Systems-reasoning difficulty can rise through:

- more meaningful relationships, not more decorative objects;
- longer causal paths;
- additional or competing feedback loops;
- delayed or partially observed consequences;
- thresholds and nonlinear responses;
- multiple spatial or temporal scales;
- competing local and party-wide goals;
- higher experiment cost, provided recovery remains fair;
- transfer into a new context without repeating the original teaching.

Track these separately from execution and interface load:

- control complexity;
- camera management;
- selection burden;
- reaction precision;
- working-memory burden;
- visual clutter or shader failure;
- reset and traversal time;
- repeated performance after the solution is known.

If a player understands the correct model but cannot express it through the controls, the puzzle is
not measuring systems thinking. Fix or intentionally classify the execution challenge rather than
calling it puzzle difficulty.

## Player-State Diagnostic

During live play and deterministic replay, classify the player's state:

| Player reaction | Meaning | Design response |
| --- | --- | --- |
| "What am I even trying to affect?" | Boundary, goal, or important variables are unreadable | Clarify framing, landmark, state, or causal entry point |
| "Let me think this through." | The model is legible and alternatives need evaluation | Desired deliberation; protect the pause and inspection space |
| "Oh, that also changes this." | A prediction was falsified by understandable evidence | Productive surprise; preserve or strengthen the causal feedback |
| "Whew, that was close." | The model supported anticipation under pressure | Desired tension; verify that success was not luck or input ambiguity |
| "I know what to do; why am I still doing it?" | Reasoning is over and execution is repeating | Compress, automate, vary, or cash out mastery |
| "That was random/unfair." | Consequence cannot be traced to a readable state or action | Repair truthfulness, telegraphy, provenance, or replay explanation |
| "This is like the earlier pressure loop." | The player recognizes structure across content | Successful transfer and growing systems mastery |

Confusion is not automatically challenge. Deliberation, productive surprise, anticipation, and
transfer are the target states.

## Failure Pedagogy

A good failure is an experiment with a readable result.

It must answer:

- What player prediction was wrong?
- Which state or relationship disproved it?
- Can the relevant before/after state be inspected?
- Is the correction available before the next attempt?
- Does the next attempt test a revised model rather than demand the same blind action?

Feedback should distinguish at least these cases where relevant:

- incorrect causal model;
- incomplete information or lost perception register;
- correct plan with bad timing;
- correct plan with failed control execution;
- deliberate risk that produced an understood consequence.

Use persistent state, path/link visualization, camera emphasis, trends, pause inspection, and
deterministic replay to show causality. Do not show the complete solution by default. Reveal the
specific relationship needed to make the player's experiment interpretable.

## Progression Ladder

A strong curriculum usually progresses through these stages:

1. Isolate one relationship and show a harmless consequence.
2. Ask the player to predict and use a short causal chain.
3. Add a visible delay or accumulation.
4. Close a reinforcing or balancing feedback loop.
5. Combine loops or add a locally sensible action with a global cost.
6. Ask for a higher-leverage intervention instead of a parameter tweak.
7. Re-skin the structure and test transfer without re-explaining it.
8. Degrade a previously reliable perception or capability while keeping world truth consistent.

Teach the baseline before degrading it. Introduce only enough structure for the current inference;
complexity should be composed, not dumped on the player.

## Reusable System Archetypes

These are starting hypotheses for puzzle structures, not recipes or guaranteed truths.

| Archetype | Puzzle form |
| --- | --- |
| Limits to growth | An effective strategy reaches a capacity constraint; the player must identify the limiter |
| Fixes that fail | A quick solution works now but creates a delayed consequence |
| Shifting the burden | A convenient workaround weakens or postpones the fundamental solution |
| Success to the successful | Investing in one route reinforces it while starving another possibility |
| Escalation | Two agents react to each other in a reinforcing contest |
| Tragedy of the commons | Locally useful actions deplete a shared party or environmental resource |
| Balancing loop with delay | Delayed correction causes overshoot or oscillation |
| Common cause | Several apparent problems trace back to one upstream state |
| Common effect | Several independent actions converge on one limited capacity or outcome |
| Causal chain | The player must reason across a sequence rather than adjacent objects |

## Application To TRAWF

### Channels

- Water and pressure are stocks; gates, pumps, surges, drains, and leaks are flows.
- Surge travel, germination, investigation, and recovery create delays.
- Portals, tunnels, bridges, and dropped objects change network topology.
- Character-bound causal links should expose only the relationships the living, conscious party can
  currently perceive.
- Enemy routing through channels can create feedback and leverage: the player manipulates a system
  rather than merely outrunning a threat.

### Party

- Each character is a local perspective and capability inside the larger party system.
- Selection, rally, pause, and assignment controls should reduce coordination friction without
  solving the strategic choice.
- A locally safe move may create a party-wide cost; the consequence must be inspectable.
- Carrying, holding, locking, and role inheritance are persistent states that should remain visible
  in portraits and the world.

### Food

- Food is a stock, drain is an outflow, and pickups are inflows.
- Riskier branches can offer larger inflows while sparse food guides movement.
- Early hunger should create route evaluation, not a runaway failure spiral.
- If low food reduces the ability to obtain food, provide a legible recovery path or intentionally
  identify the reinforcing trap before using it.
- More granular bars are valuable when they help predict time-to-threshold; granularity that does
  not change a decision is noise.

### Deterministic Replay

- Record the state and player intervention needed to reconstruct consequences.
- Every gameplay-relevant state-machine phase is authoritative GameState from the moment of
  commitment, not view-local animation state. Active traversals, carries, interactions, hazards,
  and interruptions must survive save/load and replay with their origin, destination or target,
  start/end tick, progress rule, and interruption policy intact.
- Presentation derives from authoritative state. Never leave a character logically at an origin
  while animating them elsewhere and commit only on arrival; queries, saves, collision, targeting,
  or reloads would then expose an exploitable second reality.
- Replays should let us compare intended prediction with actual outcome at normal pace.
- Mark moments of model revision, confusion, tension, and solved-state repetition.
- A deterministic result is not automatically legible; the replay must expose the relevant causal
  path and state transition.

## Playtest Questions

For each failure, pause, surprise, and success, record:

1. What did the player believe would happen?
2. What actually happened?
3. Which evidence was available before commitment?
4. Which evidence became available afterward?
5. Did the player revise the correct relationship?
6. Was the next attempt a new hypothesis or repeated guessing?
7. Was pressure creating meaningful prioritization or hiding information?
8. Did party controls express the plan cleanly?
9. At what moment was the system mentally solved?
10. How much play remained after that moment, and did it add a new decision?

## Acceptance Standard

A puzzle is systems-ready when:

- its intended causal model can be stated succinctly;
- its load-bearing relationships are consistently represented;
- a plausible novice model exists;
- representative failure visibly corrects a misconception;
- model error and execution error can be distinguished;
- the leverage point produces a meaningful downstream change;
- recovery permits a revised hypothesis at a proportional cost;
- the solution remains truthful under replay and fast-forward;
- the solved-state execution tail is short or contains a new decision;
- a later encounter can test transfer of the learned structure.

## Research Basis

- Ross D. Arnold and Jon P. Wade, [A Definition of Systems Thinking: A Systems Approach](https://doi.org/10.1016/j.procs.2015.03.050)
- Donella Meadows, [Leverage Points: Places to Intervene in a System](https://donellameadows.org/archives/leverage-points-places-to-intervene-in-a-system/)
- Donella Meadows, [Dancing With Systems](https://donellameadows.org/archives/dancing-with-systems/)
- Benjamin M. Rottman, Dedre Gentner, and Micah B. Goldwater, [Causal Systems Categories](https://doi.org/10.1111/j.1551-6709.2012.01253.x)
- Michael Engelhart, Joachim Funke, and Sebastian Sager, [A Web-Based Feedback Study](https://doi.org/10.11588/jddm.2017.1.34608)
- MIT Sloan, [Beer Distribution Game](https://mitsloan.mit.edu/teaching-resources-library/mit-sloan-beer-game-online)
