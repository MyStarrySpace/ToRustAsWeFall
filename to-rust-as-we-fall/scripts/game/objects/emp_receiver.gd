class_name EmpReceiver
extends Node3D
## An ELECTRONIC opt-in point for Aster's canonical EMP: the pulse service scans
## world nodes for `apply_emp(duration)` — this node forwards the hit to whatever
## mechanism hosts it (a valve, a console, a lock) through one Callable, so any
## chunk can make a fixture EMP-able without subclassing the ability service or
## the interactable. Parent it under the fixture's node: it rides that node's
## transform (including a coord-map warp), and the pulse's world-space radius
## check reads its live global position. Canon: EMP is ANTI-TECH — fauna never
## opt in; mechanisms do, through exactly this.

## Called with the pulse duration; return true if the mechanism accepted the hit
## (the ability reports it as affected).
var on_pulse: Callable = Callable()


func apply_emp(duration: float) -> bool:
	if on_pulse.is_valid():
		return bool(on_pulse.call(duration))
	return false
