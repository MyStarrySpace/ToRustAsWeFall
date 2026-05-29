class_name Portal
extends RefCounted

## A directed edge between zones. Taking a portal exits the current zone
## and enters the destination zone at the declared re-entry hub.
##
## Portals are the designed affordance for backtracking. Walking back to
## a hub within the current zone is free; crossing zones is always via
## portal. This mirrors the architecture's "linear forward progression
## with local fallback" shape.
##
## Portals are data-only. Runtime behavior (state snapshots, revisit
## transforms) lives on ZoneManager.

var id: StringName = &""
var from_zone_id: StringName = &""
var to_zone_id: StringName = &""
var to_hub_id: StringName = &""
