class_name Zone
extends Resource

## Data: a zone of the game world. Has hubs (safe spaces that persist for
## the zone's duration), spokes (self-contained encounters), and gates
## (environmental obstacles that demand specific party composition).
##
## Zones are data-driven — defined in .tres files and registered with the
## ZoneManager on scene load. The Zone does not carry runtime state;
## per-run progression lives on ZoneManager.
##
## The essential_third is the character whose abilities are load-bearing
## for this zone's gates. Gates also default to requiring Aster and Peris;
## they are the spine of the game.

@export var id: StringName = &""
@export var display_name: String = ""
@export var hub_ids: Array[StringName] = []
@export var spoke_ids: Array[StringName] = []
@export var gate_ids: Array[StringName] = []
@export var essential_third: StringName = &""
