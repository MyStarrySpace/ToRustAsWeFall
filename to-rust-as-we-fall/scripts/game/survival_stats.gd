class_name SurvivalStats
extends RefCounted

const ATP_MAX_PIPS := 8.0

static func normalize_atp(value: float) -> float:
	if value > ATP_MAX_PIPS + 0.001:
		return clampf(roundf((value / 100.0) * ATP_MAX_PIPS), 0.0, ATP_MAX_PIPS)
	return clampf(roundf(value), 0.0, ATP_MAX_PIPS)

static func clamp_atp(value: float) -> float:
	return clampf(roundf(value), 0.0, ATP_MAX_PIPS)

static func atp_text(value: float) -> String:
	return "%d/%d" % [int(normalize_atp(value)), int(ATP_MAX_PIPS)]
