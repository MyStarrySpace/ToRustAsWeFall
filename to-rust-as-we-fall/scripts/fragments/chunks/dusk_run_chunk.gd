extends "res://scripts/scene_chunks/scene_chunk.gd"

## Dusk Run — the GDD 422 lesson as a fragment: it is afternoon, the next shelter is far, and an
## IRON FIELD sits across the direct route. Safe routing (Tab) detours around the recoverable
## risk and costs time; direct routing eats the stamina drain and saves it. Reach the east
## shelter and REST before the day rolls over — sleep through the night skip and wake fresh;
## dawdle past dawn outside and wake REST-DEPRIVED (the stamina ceiling cut says so on the HUD).
## Time is the resource health competes with.

const DAY_LENGTH := 120.0
const START_TIME := 0.34          # afternoon: enough to make it, not enough to wander
const WEST_SHELTER := Vector3(3.5, 0.0, 4.0)
const EAST_SHELTER := Vector3(36.0, 0.0, 4.0)
const IRON_MIN := Vector2(16.0, 1.0)
const IRON_MAX := Vector2(24.0, 5.2)   # the direct lane crosses it; a clear lane runs south

# Spawns sit BESIDE the west shelter, not on its rest pad — standing on a pad starts the
# proximity dwell, and bedding down must be the player's choice, not the spawn point's.
const SPAWNS := {
	"aster": Vector3(7.5, 0.0, 3.2),
	"peris": Vector3(7.0, 0.0, 4.6),
	"endo": Vector3(8.0, 0.0, 5.8),
}

var _clock_label: Label3D
var _risk_applied := false

func _build_chunk() -> void:
	_add_floor(self, Vector3(20.0, -0.05, 4.5), Vector3(40.0, 0.1, 9.0), Color(0.1, 0.1, 0.11))
	# The iron field: visible rust, data-layer recoverable risk (safe routing detours it).
	_add_box(self, Vector3((IRON_MIN.x + IRON_MAX.x) * 0.5, 0.0, (IRON_MIN.y + IRON_MAX.y) * 0.5),
		Vector3(IRON_MAX.x - IRON_MIN.x, 0.08, IRON_MAX.y - IRON_MIN.y), Color(0.3, 0.12, 0.06), Color(0.6, 0.2, 0.08), 0.25)
	_add_label(self, "IRON FIELD", Vector3(20.0, 1.6, 3.0), Color(0.95, 0.5, 0.3))
	_add_label(self, "WEST SHELTER", WEST_SHELTER + Vector3(0, 2.2, 0), Color(0.95, 0.8, 0.5))
	_add_label(self, "EAST SHELTER — REST BEFORE DARK", EAST_SHELTER + Vector3(0, 2.2, 0), Color(0.95, 0.8, 0.5))
	_clock_label = _add_label(self, "", Vector3(20.0, 3.2, 4.5), Color(0.85, 0.8, 0.7))
	_add_rest_point(self, WEST_SHELTER, Vector2(4.0, 4.0))
	_add_rest_point(self, EAST_SHELTER, Vector2(5.0, 5.0))

func reset_preview_state() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	gs.set_game_clock(1, START_TIME)
	gs.set_day_length(DAY_LENGTH)
	_risk_applied = false

## The grid installs AFTER reset_preview_state in the chunk-load order — the iron risk applies
## lazily on the first frame that has one.
func _ensure_iron_risk() -> void:
	if _risk_applied:
		return
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return
	_risk_applied = true
	gs.grid.set_world_region_risk(IRON_MIN, IRON_MAX, 6.0, true)

func get_preview_character_state() -> Dictionary:
	return {
		"aster": {"hp": 80.0, "atp": 4.0},
		"peris": {"hp": 80.0, "atp": 4.0},
		"endo": {"hp": 80.0, "atp": 4.0},
	}

func get_preview_time_state() -> Dictionary:
	return {"day": 1, "time": START_TIME, "advance_time": false,
		"note_default": "Afternoon. The east shelter is far and the iron field is in the way: safe routing detours (slow), direct cuts through (drain). Be asleep before the day rolls over — or wake deprived."}

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
	_clock_label.text = "DAY %d // T %.2f (%s)%s" % [gs.get_game_day(), gs.get_time_of_day(), gs.get_day_phase(), ("  //  DEPRIVED: " + ", ".join(deprived)) if not deprived.is_empty() else ""]

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
	return "Cross to the east shelter before dark. Safe routing detours the iron field and costs time; direct routing eats the drain and saves it. Sleep through the skip and wake fresh — get caught out past dawn and wake rest-deprived."

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
		return {"contract_id": "dusk_run_v1"}
	var deprived := {}
	for cid in ["aster", "peris", "endo"]:
		deprived[cid] = gs.is_rest_deprived(str(cid))
	return {"contract_id": "dusk_run_v1", "day": gs.get_game_day(),
		"phase": gs.get_day_phase(), "deprived": deprived}
