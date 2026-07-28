extends "res://scripts/scene_chunks/scene_chunk.gd"

## Dusk Run — the GDD 422 lesson as a fragment: it is afternoon, the next shelter is far, and an
## IRON FIELD sits across the direct route. Safe routing (Tab) detours around the recoverable
## risk and costs time; direct routing accepts visible iron damage and saves it. Reach the east
## shelter and REST before the day rolls over — sleep through the night skip and wake fresh;
## dawdle past dawn outside and wake REST-DEPRIVED (the stamina ceiling cut says so on the HUD).
## Time is the resource health competes with.

const DAY_LENGTH := 120.0
const START_TIME := 0.34          # afternoon: enough to make it, not enough to wander
const WEST_SHELTER := Vector3(3.5, 0.0, 4.0)
const EAST_SHELTER := Vector3(36.0, 0.0, 4.0)
const IRON_MIN := Vector2(16.0, 1.0)
const IRON_MAX := Vector2(24.0, 5.2)   # the direct lane crosses it; a clear lane runs south
const IRON_ROUTE_PENALTY := 6.0
const IRON_DAMAGE_INTERVAL := 0.5
const IRON_DAMAGE_RATE_SCALE := 1.0
const IRON_FIELD_TAG := "dusk_run_iron_field"
const GridRiskFieldScript := preload("res://scripts/game/objects/grid_risk_field.gd")

# Spawns sit BESIDE the west shelter, not on its rest pad — standing on a pad starts the
# proximity dwell, and bedding down must be the player's choice, not the spawn point's.
const SPAWNS := {
	"aster": Vector3(7.5, 0.0, 3.2),
	"peris": Vector3(7.0, 0.0, 4.6),
	"endo": Vector3(8.0, 0.0, 5.8),
}

var _clock_label: Label3D
var _risk_applied := false
var _iron_risk_field: Node = null
var _iron_contacts: Dictionary = {}

func _build_chunk() -> void:
	_add_floor(self, Vector3(20.0, -0.05, 4.5), Vector3(40.0, 0.1, 9.0), Color(0.1, 0.1, 0.11))
	# The iron field: visible rust, data-layer recoverable risk (safe routing detours it).
	_add_box(
		self,
		Vector3((IRON_MIN.x + IRON_MAX.x) * 0.5, 0.0,
			(IRON_MIN.y + IRON_MAX.y) * 0.5),
		Vector3(IRON_MAX.x - IRON_MIN.x, 0.08, IRON_MAX.y - IRON_MIN.y),
		Color(0.3, 0.12, 0.06), Color(0.6, 0.2, 0.08), 0.25
	)
	_add_label(self, "IRON FIELD", Vector3(20.0, 1.6, 3.0), Color(0.95, 0.5, 0.3))
	_add_label(self, "WEST SHELTER", WEST_SHELTER + Vector3(0, 2.2, 0), Color(0.95, 0.8, 0.5))
	_add_label(
		self, "EAST SHELTER — REST BEFORE DARK",
		EAST_SHELTER + Vector3(0, 2.2, 0), Color(0.95, 0.8, 0.5)
	)
	_clock_label = _add_label(self, "", Vector3(20.0, 3.2, 4.5), Color(0.85, 0.8, 0.7))
	_add_rest_point(self, WEST_SHELTER, Vector2(4.0, 4.0), ["aster", "peris", "endo"])
	_add_rest_point(self, EAST_SHELTER, Vector2(5.0, 5.0), ["aster", "peris", "endo"])

func reset_preview_state() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	gs.set_game_clock(1, START_TIME)
	gs.set_day_length(DAY_LENGTH)
	_risk_applied = false
	_iron_contacts.clear()
	if _iron_risk_field != null and is_instance_valid(_iron_risk_field) \
			and _iron_risk_field.has_method("reset"):
		_iron_risk_field.call("reset", true)

## The grid installs AFTER reset_preview_state in the chunk-load order — the iron risk applies
## lazily on the first frame that has one.
func _ensure_iron_risk() -> void:
	if _risk_applied:
		return
	var gs = _get_game_state()
	var scheduler = _get_scheduler()
	if gs == null or gs.grid == null or scheduler == null:
		return
	gs.grid.set_world_region_risk(IRON_MIN, IRON_MAX, IRON_ROUTE_PENALTY, true)
	var entries: Array = []
	var min_cell: Vector2i = gs.grid.world_to_grid(Vector3(IRON_MIN.x, 0.0, IRON_MIN.y))
	var max_cell: Vector2i = gs.grid.world_to_grid(Vector3(IRON_MAX.x, 0.0, IRON_MAX.y))
	for z in range(mini(min_cell.y, max_cell.y), maxi(min_cell.y, max_cell.y) + 1):
		for x in range(mini(min_cell.x, max_cell.x), maxi(min_cell.x, max_cell.x) + 1):
			entries.append({"cell": [x, z], "penalty": IRON_ROUTE_PENALTY})
	if _iron_risk_field == null or not is_instance_valid(_iron_risk_field):
		_iron_risk_field = GridRiskFieldScript.new()
		_iron_risk_field.name = "DuskRunIronRiskField"
		add_child(_iron_risk_field)
	_iron_risk_field.call("setup", gs, scheduler, gs.grid, entries,
		["aster", "peris", "endo"], {
			"tag": IRON_FIELD_TAG,
			"interval": IRON_DAMAGE_INTERVAL,
			"damage_rate_scale": IRON_DAMAGE_RATE_SCALE,
			"active": true,
			"restore_existing_authority": true,
			"on_bite": Callable(self, "_on_iron_bite"),
		})
	_risk_applied = true


func _on_iron_bite(
	character_id: String, _damage: float, _cell: Vector2i, penalty: float
) -> void:
	if _iron_contacts.has(character_id):
		return
	_iron_contacts[character_id] = true
	_show_note(
		"IRON FIELD // %s is losing %.1f HP/s. Keep moving or route around the rust."
		% [character_id.capitalize(), penalty * IRON_DAMAGE_RATE_SCALE],
		2.8
	)


func on_game_state_grid_ready() -> void:
	_ensure_iron_risk()


func on_game_state_snapshot_restored() -> void:
	super.on_game_state_snapshot_restored()
	if _iron_risk_field != null and is_instance_valid(_iron_risk_field) \
			and _iron_risk_field.has_method("on_game_state_snapshot_restored"):
		_iron_risk_field.call("on_game_state_snapshot_restored")

func get_preview_character_state() -> Dictionary:
	return {
		"aster": {"hp": 80.0, "atp": 4.0},
		"peris": {"hp": 80.0, "atp": 4.0},
		"endo": {"hp": 80.0, "atp": 4.0},
	}

func get_preview_time_state() -> Dictionary:
	return {"day": 1, "time": START_TIME, "advance_time": false,
		"note_default": "Afternoon: safe routing detours the iron field but costs time; "
			+ "direct routing crosses it and takes HP damage. Sleep before dawn or wake deprived."}

func headless_process(_delta: float) -> void:
	_ensure_iron_risk()
	_update_clock_label()

func _process(_delta: float) -> void:
	_ensure_iron_risk()
	_update_clock_label()

func _update_clock_label() -> void:
	var gs = _get_game_state()
	if gs == null or _clock_label == null:
		return
	var deprived := []
	for cid in ["aster", "peris", "endo"]:
		if gs.is_rest_deprived(str(cid)):
			deprived.append(cid)
	var warning := ("  //  DEPRIVED: " + ", ".join(deprived)) \
		if not deprived.is_empty() else ""
	_clock_label.text = "DAY %d // T %.2f (%s)%s" % [
		gs.get_game_day(), gs.get_time_of_day(), gs.get_day_phase(), warning
	]

func get_grid_data() -> Dictionary:
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [0.0, 0.0, 0.0],
		"cell_size": 1.0,
		"width": 41,
		"height": 10,
		"walkable_regions": [{"min": [1.0, 1.0], "max": [39.9, 8.9]}],
	}

func get_scene_title() -> String:
	return "Dusk Run"

func get_scene_help() -> String:
	return "Cross to the east shelter before dark. Safe routing detours the iron field but costs " \
		+ "time; direct routing takes visible HP damage. Sleep there or wake rest-deprived."

func get_default_character() -> String:
	return "aster"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate()

func get_preview_anchors() -> Dictionary:
	return {
		"west_shelter": WEST_SHELTER,
		"east_shelter": EAST_SHELTER,
		"iron_center": Vector3((IRON_MIN.x + IRON_MAX.x) * 0.5, 0.0, (IRON_MIN.y + IRON_MAX.y) * 0.5),
	}

func get_preview_state() -> Dictionary:
	var gs = _get_game_state()
	if gs == null:
		return {"contract_id": "dusk_run_v2"}
	var deprived := {}
	for cid in ["aster", "peris", "endo"]:
		deprived[cid] = gs.is_rest_deprived(str(cid))
	var risk_state: Dictionary = {}
	if _iron_risk_field != null and is_instance_valid(_iron_risk_field) \
			and _iron_risk_field.has_method("get_state"):
		risk_state = (_iron_risk_field.call("get_state") as Dictionary).duplicate(true)
	return {"contract_id": "dusk_run_v2", "day": gs.get_game_day(),
		"phase": gs.get_day_phase(), "deprived": deprived,
		"iron_risk_field": risk_state, "iron_contacts": _iron_contacts.duplicate(true)}
