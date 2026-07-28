class_name PerformanceTrace
extends RefCounted

## Opt-in, browser-readable timings for the synchronous gameplay stages that can
## make a rendered frame hitch. Every measured stage is retained for its frame;
## ordinary `?perf=1` logging prints all stages in a slow frame, while
## `?perf=all` prints every measured frame. The collector is a cheap no-op in
## normal builds so profiling does not become the performance problem.

const DEFAULT_STEP_THRESHOLD_MS := 1.0
const DEFAULT_FRAME_THRESHOLD_MS := 45.0

static var _configured := false
static var _enabled := false
static var _print_all := false
static var _step_threshold_ms := DEFAULT_STEP_THRESHOLD_MS
static var _frame_threshold_ms := DEFAULT_FRAME_THRESHOLD_MS

static var _frame := -1
static var _frame_first_usec := 0
static var _frame_last_usec := 0
static var _steps: Array[Dictionary] = []
static var _max_step_ms := 0.0
static var _last_flush: Dictionary = {}


static func is_enabled() -> bool:
	_ensure_configured()
	return _enabled


static func step_threshold_ms() -> float:
	_ensure_configured()
	return _step_threshold_ms


static func begin() -> int:
	_ensure_configured()
	if not _enabled:
		return 0
	var process_frame := Engine.get_process_frames()
	if process_frame != _frame:
		# Flush before taking the caller's timestamp. A slow-frame report can be
		# surprisingly expensive in Web builds; doing that work from the first
		# nested end() made its enclosing scheduler/process sample measure the
		# profiler's console output as gameplay work.
		_roll_over_to_frame(process_frame, Time.get_ticks_usec())
	return Time.get_ticks_usec()


## Complete one synchronous timing sample. `subject` identifies the affected
## character/result without forcing callers to allocate a Dictionary every
## frame; `work_units` is nodes, points, entries, or another useful count.
static func end(
	category: StringName,
	label: StringName,
	started_usec: int,
	subject := "",
	work_units := -1
) -> float:
	if started_usec <= 0 or not _enabled:
		return 0.0
	var ended_usec := Time.get_ticks_usec()
	var process_frame := Engine.get_process_frames()
	if process_frame != _frame:
		# Safe fallback for callers that hand end() a timestamp without using
		# begin(), or for the unlikely case that a sample spans a process-frame
		# boundary. ended_usec was captured before the flush, so observer output
		# still cannot inflate this sample.
		_roll_over_to_frame(process_frame, started_usec)
	if _frame_first_usec <= 0:
		_frame_first_usec = started_usec
		_frame_last_usec = ended_usec
	var elapsed_ms := float(ended_usec - started_usec) / 1000.0
	_frame_first_usec = mini(_frame_first_usec, started_usec)
	_frame_last_usec = maxi(_frame_last_usec, ended_usec)
	_max_step_ms = maxf(_max_step_ms, elapsed_ms)
	_steps.append({
		"category": str(category),
		"label": str(label),
		"ms": elapsed_ms,
		"subject": subject,
		"units": work_units,
	})
	return elapsed_ms


static func _roll_over_to_frame(process_frame: int, next_frame_started_usec: int) -> void:
	_flush_frame(next_frame_started_usec)
	_frame = process_frame


## Explicit configuration is useful to native profiling/tests. Browser builds
## normally configure themselves from `?perf=1`, `?perf=all`,
## `?perf_step_ms=...`, and `?perf_frame_ms=...`.
static func configure(
	enabled: bool,
	print_all := false,
	step_threshold_ms := DEFAULT_STEP_THRESHOLD_MS,
	frame_threshold_ms := DEFAULT_FRAME_THRESHOLD_MS
) -> void:
	if _enabled:
		_flush_frame(Time.get_ticks_usec())
	_configured = true
	_enabled = enabled
	_print_all = print_all
	_step_threshold_ms = maxf(step_threshold_ms, 0.0)
	_frame_threshold_ms = maxf(frame_threshold_ms, 0.0)
	_clear_frame()
	if _enabled:
		print("[PERF:CONFIG] mode=%s step>=%.3fms frame>=%.3fms" % [
			"all" if _print_all else "slow", _step_threshold_ms, _frame_threshold_ms])


## Flush the current frame on demand (mainly for deterministic CLI coverage).
static func flush() -> Dictionary:
	if _enabled:
		_flush_frame(Time.get_ticks_usec(), true)
	return _last_flush.duplicate(true)


static func get_last_flush() -> Dictionary:
	return _last_flush.duplicate(true)


static func _ensure_configured() -> void:
	if _configured:
		return
	var mode := OS.get_environment("TRAWF_PERF_TRACE").strip_edges().to_lower()
	var step_ms := _positive_float(
		OS.get_environment("TRAWF_PERF_STEP_MS"), DEFAULT_STEP_THRESHOLD_MS)
	var frame_ms := _positive_float(
		OS.get_environment("TRAWF_PERF_FRAME_MS"), DEFAULT_FRAME_THRESHOLD_MS)
	if OS.has_feature("web"):
		var search = JavaScriptBridge.eval("window.location.search", true)
		if search != null:
			var params := _query_params(str(search))
			mode = str(params.get("perf", mode)).strip_edges().to_lower()
			step_ms = _positive_float(params.get("perf_step_ms", step_ms), step_ms)
			frame_ms = _positive_float(params.get("perf_frame_ms", frame_ms), frame_ms)
	configure(mode in ["1", "true", "slow", "all"], mode == "all", step_ms, frame_ms)


static func _query_params(search: String) -> Dictionary:
	var out := {}
	for raw_pair in search.trim_prefix("?").split("&", false):
		var split_at := raw_pair.find("=")
		if split_at < 0:
			out[raw_pair.uri_decode()] = "1"
		else:
			out[raw_pair.substr(0, split_at).uri_decode()] = raw_pair.substr(split_at + 1).uri_decode()
	return out


static func _positive_float(value, fallback: float) -> float:
	if not str(value).is_valid_float():
		return fallback
	return maxf(float(value), 0.0)


static func _flush_frame(next_frame_started_usec: int, force := false) -> void:
	if _frame < 0 or _steps.is_empty():
		_clear_frame()
		return
	var trace_span_ms := float(_frame_last_usec - _frame_first_usec) / 1000.0
	var frame_interval_ms := float(maxi(next_frame_started_usec - _frame_first_usec, 0)) / 1000.0
	var interval_slow := frame_interval_ms >= _frame_threshold_ms
	var slow := (
		_print_all
		or _max_step_ms >= _step_threshold_ms
		or trace_span_ms >= _frame_threshold_ms
		or interval_slow
	)
	var payload := {
		"frame": _frame,
		"interval_ms": frame_interval_ms,
		"trace_span_ms": trace_span_ms,
		"max_step_ms": _max_step_ms,
		"step_count": _steps.size(),
		"slow": slow,
		"forced": force,
		"steps": _steps.duplicate(true),
	}
	_last_flush = payload
	if slow or force:
		print("[PERF:FRAME] frame=%d interval=%.3fms trace=%.3fms max=%.3fms steps=%d" % [
			_frame, frame_interval_ms, trace_span_ms, _max_step_ms, _steps.size()])
		for step in _steps:
			var suffix := ""
			if str(step.subject) != "":
				suffix += " subject=%s" % str(step.subject)
			if int(step.units) >= 0:
				suffix += " units=%d" % int(step.units)
			print("[PERF:%s] frame=%d %s %.3fms%s" % [
				str(step.category).to_upper(), _frame, str(step.label), float(step.ms), suffix])
	_clear_frame()
static func _clear_frame() -> void:
	_frame = -1
	_frame_first_usec = 0
	_frame_last_usec = 0
	_steps.clear()
	_max_step_ms = 0.0
