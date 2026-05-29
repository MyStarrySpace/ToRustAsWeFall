class_name Zone
extends Resource

## Data: a zone of the game world. Has hubs (safe spaces that persist for
## the zone's duration), spokes (self-contained encounters), and gates
## (environmental obstacles that may demand specific party composition).
##
## Zones are data-driven, defined in .tres files and registered with the
## ZoneManager on scene load. The Zone does not carry runtime state;
## per-run progression lives on ZoneManager.
##
## The game is beatable with Aster and Peris alone; allies are optional.
## Gates that require specific characters declare them via Gate.required_members
## but no gate is authored to require any character other than Aster or Peris.

@export var id: StringName = &""
@export var display_name: String = ""
@export var hub_ids: Array[StringName] = []
@export var spoke_ids: Array[StringName] = []
@export var gate_ids: Array[StringName] = []
