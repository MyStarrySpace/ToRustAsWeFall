extends RefCounted

## Pure fixed-cadence boundary math shared by scheduler-backed gameplay owners.
##
## Decimal epochs and intervals are not generally exact binary floats. At a mathematical boundary,
## `(now - epoch) / interval` can therefore be infinitesimally below an integer; a bare
## `floor(...) + 1` then reconstructs `now` instead of the following boundary. A callback which
## rearms itself at that result can dispatch forever inside one EventScheduler advance.
##
## This helper preserves the original epoch-aligned cadence while guaranteeing that every returned
## boundary is meaningfully later than `now`. The tolerance is capped at one tenth of a microsecond
## and also kept to one millionth of the cadence, so it absorbs representation noise without
## granting a visible timing window.

const MAX_BOUNDARY_EPSILON := 0.0000001
const BOUNDARY_EPSILON_FRACTION := 0.000001


static func next_strict_tick(epoch: float, interval: float, now: float) -> float:
	if interval <= 0.0:
		return -1.0
	var epsilon := minf(MAX_BOUNDARY_EPSILON, interval * BOUNDARY_EPSILON_FRACTION)
	if now < epoch - epsilon:
		return epoch
	var completed := floori((now - epoch) / interval) + 1
	var deadline := epoch + float(maxi(1, completed)) * interval
	if deadline <= now + epsilon:
		deadline += interval
	return deadline
