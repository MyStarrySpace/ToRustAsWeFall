# Browser performance trace

The gameplay timing trace is opt-in. Normal builds pay only the disabled guard;
they do not call the timer, retain samples, or print per-frame output.

Open a Web export with one of these query strings:

- `?perf=1` records every instrumented navigation, draw, and update stage, then
  prints the complete breakdown only for a slow frame.
- `?perf=all` prints every measured stage in every frame. Use this only for a
  short reproduction because the console traffic affects timing.
- `perf_step_ms` changes the individual-stage threshold (default `1.0`).
- `perf_frame_ms` changes the frame-interval/trace-span threshold (default
  `45.0`, high enough that an ordinary 30 FPS Web frame is not a hitch).

Example:

```text
http://127.0.0.1:8060/index.html?perf=1&perf_step_ms=0.75&perf_frame_ms=45
```

The console emits one `[PERF:FRAME]` line and the frame's complete set of
`[PERF:NAV]`, `[PERF:DRAW]`, and `[PERF:UPDATE]` lines. Measurements are nested,
so stage times should be read as inclusive durations rather than added together.
`interval` is the time between the first measured stage in adjacent process
frames; `trace` is the wall-time span covered by measured work in one frame.

Browser automation can read the same console stream, record the reproduction's
start timestamp, and aggregate later `[PERF:*]` messages by `label`. A hidden or
background-controlled browser may be frame-throttled; use a very high
`perf_frame_ms` (for example `5000`) there so only synchronous stage thresholds
trigger and the artificial frame interval is ignored.

Native/headless runs can opt in with `TRAWF_PERF_TRACE=slow` or
`TRAWF_PERF_TRACE=all`. Use `TRAWF_PERF_STEP_MS` and
`TRAWF_PERF_FRAME_MS` to override the same thresholds without changing code.
