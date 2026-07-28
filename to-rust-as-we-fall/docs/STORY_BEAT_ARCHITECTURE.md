# Story Beat Architecture

Story progression is split into five layers. A scene controller coordinates them; it does not become them.

1. **Authored scene assets** own geometry, collision, markers, animation, and editor-tunable presentation.
2. **Pure mechanics** own deterministic rules such as multi-actor survey progress, gates, and evidence/decision state.
3. **Story beats** compose mechanics into one narrative objective and expose a stable lifecycle.
4. **The beat runner** owns enter, exit, update, event dispatch, completion, and transition ordering.
5. **The scene adapter** binds beat signals/state to nodes, dialogue, cameras, audio, and scene-specific consequences.

## Contract

`StoryBeat` is an abstract `RefCounted` base. Subclasses implement `_on_entered()` and may override the other protected hooks. External code calls only the public lifecycle:

- `enter(context, payload)`
- `exit(reason)`
- `update(delta)`
- `handle_event(event_id, payload)`
- `complete(outcome)`
- `request_transition(next_beat_id, payload)`
- `snapshot()` / `restore(snapshot)`

`StoryBeatContext` supplies typed core dependencies (`GameState` and the gameplay/UI schedulers) plus an explicit service map. A beat must validate required services before entry. It must not search a scene tree for hidden dependencies.

`StoryBeatRunner` is created once by `TutorialSequence`. Subclasses register beats in `_configure_story_beats()`. Calls to `_enter_step()` activate a registered beat with the same id and deactivate the previous beat. Existing non-beat steps remain valid during incremental migration.

Use `CallbackStoryBeat` for a small, stateless beat whose hooks fit cleanly into injected callables. Use a dedicated subclass when the beat has state, invariants, serialization, or reusable mechanics.

## Ownership rules

A story beat may own:

- objective phase and completion state;
- composition of reusable mechanics;
- validation of causal/action prerequisites;
- deterministic reactions to semantic events;
- a serializable snapshot of its own state.

A story beat must not own:

- generated `MeshInstance3D`, UI controls, collision shapes, or level shell geometry;
- direct camera, shader, dialogue-box, or animation-player manipulation;
- per-frame polling that can be expressed as a semantic event;
- a second copy of state already authoritative in `GameState` or another mechanic.

The scene adapter may own presentation and the authored consequence of a beat. For example, the reusable Junction beat records completion of Peris's contextual `tend_plant` action; the Elevator adapter then owns the dusk transition and begins streaming the following gauntlet. Optional shelter inspections remain world-building interactions rather than cast abilities or preparation currencies.

## Causal puzzle mechanics

`MultiActorSurvey` counts distinct observations separately from participating actors. Re-reading one station can add a missing perspective without falsely adding another station.

`EvidenceDecisionSequence` implements evidence → decision → physical resolution. It validates authored graph references before play, rejects unavailable/wrong-actor actions without mutation, and derives protocol advancement from one ordered source of truth.

`SurveyProtocolStoryBeat` composes both mechanics with an optional preparation decision. Endo's Junction is the first migrated use. Its scene script now binds interactables and consequences while the generic beat owns all progress rules.

## Native-code seam

GDScript classes cannot serve as a native ABI interface. If profiling identifies a genuinely hot mechanic, keep the `StoryBeat` shell and delegate pure computation to a GDExtension `RefCounted` service exposed through the context or a composed mechanic. `CallbackStoryBeat` can also bind native methods as callables. If the whole lifecycle eventually moves native, promote the base contract itself to a registered GDExtension class so GDScript beats can extend that native base.

Do not move a beat to C++ merely for stronger static typing: most beats are event-driven and cold. Native code is appropriate for measured hotspots such as search, spatial queries, simulation sweeps, or bulk generation; the GDScript adapter remains useful for authored presentation.
