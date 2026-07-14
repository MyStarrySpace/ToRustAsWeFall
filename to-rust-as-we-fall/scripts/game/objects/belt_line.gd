class_name BeltLine
extends CrawlTunnel

## A DERELICT RESOURCE BELT (SET_PIECES.md #25; canon: the powered resource belt element —
## "carries a standing character along its length at belt speed"). The between-zone supply
## infrastructure as a set piece: the EFFECT is a fast, EXPOSED ride down the old line (an
## authored transit like a crawl, but nobody is hidden on an open belt); the CONTROL is the
## substation breaker that powers it, placed apart per the set-piece grammar. Dead lines refuse
## the ride through the shared `requirement` gate, so the refusal grammar (note + no consume)
## matches every other gated activation.

var powered := false

func _init() -> void:
	conceal_riders = false
	one_shot = false
	requirement = func() -> bool: return powered

func set_powered(on: bool) -> void:
	powered = on
