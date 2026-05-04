class_name DayNightCycle
extends RefCounted

const DAY_START := 0.0
const NIGHT_START := 0.5
const CYCLE_END := 1.0
const SEGMENT_SPAN := NIGHT_START

const DEFAULT_DAY_DURATION_SECONDS := 15.0 * 60.0
const DEFAULT_NIGHT_DURATION_SECONDS := 5.0 * 60.0

var day_duration_seconds := DEFAULT_DAY_DURATION_SECONDS
var night_duration_seconds := DEFAULT_NIGHT_DURATION_SECONDS

func configure(
	next_day_duration := DEFAULT_DAY_DURATION_SECONDS,
	next_night_duration := DEFAULT_NIGHT_DURATION_SECONDS
) -> void:
	day_duration_seconds = maxf(float(next_day_duration), 1.0)
	night_duration_seconds = maxf(float(next_night_duration), 1.0)

func duplicate_config() -> Dictionary:
	return {
		"day_duration_seconds": day_duration_seconds,
		"night_duration_seconds": night_duration_seconds,
	}

func is_night(time_of_day: float) -> bool:
	return _normalize_time(time_of_day) >= NIGHT_START

func get_cycle_duration_seconds() -> float:
	return day_duration_seconds + night_duration_seconds

func get_phase_name(time_of_day: float) -> String:
	var normalized := _normalize_time(time_of_day)
	if normalized < 0.15:
		return "Morning"
	if normalized < 0.3:
		return "Afternoon"
	if normalized < 0.4:
		return "Evening"
	if normalized < 0.5:
		return "Dusk"
	return "Night"

func get_phase_duration_seconds(time_of_day: float) -> float:
	return day_duration_seconds if _normalize_time(time_of_day) < NIGHT_START else night_duration_seconds

func get_phase_progress(time_of_day: float) -> float:
	var normalized := _normalize_time(time_of_day)
	if normalized < NIGHT_START:
		return clampf((normalized - DAY_START) / SEGMENT_SPAN, 0.0, 1.0)
	return clampf((normalized - NIGHT_START) / SEGMENT_SPAN, 0.0, 1.0)

func get_phase_elapsed_seconds(time_of_day: float) -> float:
	return get_phase_progress(time_of_day) * get_phase_duration_seconds(time_of_day)

func get_seconds_until_next_phase(time_of_day: float) -> float:
	var normalized := _normalize_time(time_of_day)
	var boundary := NIGHT_START if normalized < NIGHT_START else CYCLE_END
	return _segment_seconds(normalized, boundary, get_phase_duration_seconds(normalized))

func get_cycle_elapsed_seconds(time_of_day: float) -> float:
	var normalized := _normalize_time(time_of_day)
	if normalized < NIGHT_START:
		return get_phase_elapsed_seconds(normalized)
	return day_duration_seconds + get_phase_elapsed_seconds(normalized)

func advance(day: int, time_of_day: float, delta_seconds: float) -> Dictionary:
	var current_day := maxi(day, 1)
	var current_time := _normalize_time(time_of_day)
	var remaining := maxf(float(delta_seconds), 0.0)

	while remaining > 0.0001:
		var phase_duration := get_phase_duration_seconds(current_time)
		var boundary := NIGHT_START if current_time < NIGHT_START else CYCLE_END
		var seconds_to_boundary := _segment_seconds(current_time, boundary, phase_duration)
		if remaining + 0.0001 < seconds_to_boundary:
			current_time += (remaining / phase_duration) * SEGMENT_SPAN
			remaining = 0.0
			break

		remaining = maxf(0.0, remaining - seconds_to_boundary)
		if boundary >= CYCLE_END - 0.0001:
			current_day += 1
			current_time = DAY_START
		else:
			current_time = boundary

	return {
		"day": current_day,
		"time": _normalize_time(current_time),
		"phase": get_phase_name(current_time),
	}

func _segment_seconds(start_time: float, end_time: float, duration_seconds: float) -> float:
	return maxf(0.0, end_time - start_time) / SEGMENT_SPAN * duration_seconds

func _normalize_time(time_of_day: float) -> float:
	var normalized := float(time_of_day)
	while normalized >= CYCLE_END:
		normalized -= CYCLE_END
	while normalized < DAY_START:
		normalized += CYCLE_END
	return clampf(normalized, DAY_START, CYCLE_END)
