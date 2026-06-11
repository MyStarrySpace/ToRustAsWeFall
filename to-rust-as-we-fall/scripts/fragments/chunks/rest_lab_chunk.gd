extends "res://scripts/scene_chunks/scene_chunk.gd"

## Shelter Rest Lab — the GDD 3.3 survival sink in one room, for eyeballing and headless drives:
## a battered party at dusk, a shelter pad, and a downed member lying beside it. Stand on the pad
## and hold REST to bed the active character down (1 HP/sec, one ATP pip per 25s). Stand near the
## downed member at the shelter and presence alone revives them in 10s. Once every conscious
## character is resting after nightfall, the night skips to dawn — restful bonus if nobody downed.

const SHELTER_MIN := Vector2(10.0, 3.0)
const SHELTER_MAX := Vector2(16.0, 9.0)

const SPAWNS := {
	"aster": Vector3(3.5, 0.0, 5.5),
	"peris": Vector3(2.5, 0.0, 6.5),
	"endo": Vector3(12.5, 0.0, 7.5),  # downed at the shelter — revive teaches presence
}

var _rest_interactable
var _clock_label: Label3D

func _build_chunk() -> void:
	_add_floor(self, Vector3(9.0, -0.05, 6.0), Vector3(18.0, 0.1, 12.0), Color(0.1, 0.11, 0.13))
	_add_box(self, Vector3(13.0, 0.6, 3.4), Vector3(5.6, 1.2, 0.3), Color(0.2, 0.17, 0.12))
	_add_label(self, "SHELTER", Vector3(13.0, 2.0, 4.0), Color(0.95, 0.8, 0.5))
	_clock_label = _add_label(self, "", Vector3(9.0, 3.2, 6.0), Color(0.7, 0.8, 0.95))
	# The shared rest point also registers the shelter region — reset_preview_state re-clamps it.
	_rest_interactable = _add_rest_point(self, Vector3(13.0, 0.0, 6.0), Vector2(6.0, 6.0))

func configure_chunk(_config: Dictionary) -> void:
	pass

## The preview applies this at chunk load — the supported way to open with a battered party.
func get_preview_character_state() -> Dictionary:
	return {
		"aster": {"hp": 45.0, "atp": 5.0},
		"peris": {"hp": 45.0, "atp": 5.0},
		"endo": {"hp": 0.0, "atp": 4.0, "status": "downed"},
	}

func get_preview_time_state() -> Dictionary:
	return {"day": 1, "time": 0.55, "advance_time": false,
		"note_default": "Dusk. Bed everyone down at the shelter to skip to dawn; the downed member revives from presence alone."}

## The preview calls this synchronously at chunk load, right after applying the character preset
## (which set the HP/ATP numbers) — the data-layer half of the scenario goes here.
func reset_preview_state() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	gs.clear_shelter_regions()
	gs.add_shelter_region(SHELTER_MIN, SHELTER_MAX)
	gs.set_game_clock(1, 0.55)
	if gs.characters.has("endo") and not gs.is_downed("endo"):
		gs.set_stat("endo", "atp", 4.0)
		gs.down_character("endo")

func headless_process(_delta: float) -> void:
	_update_clock_label()

func _process(_delta: float) -> void:
	_update_clock_label()

func _update_clock_label() -> void:
	var gs = _get_game_state()
	if gs == null or _clock_label == null:
		return
	var resting := []
	for cid in ["aster", "peris", "endo"]:
		if gs.is_resting(str(cid)):
			resting.append(cid)
	_clock_label.text = "DAY %d  //  T %.2f  //  RESTING: %s" % [gs.game_day, gs.game_time, ", ".join(resting) if not resting.is_empty() else "—"]

func get_grid_data() -> Dictionary:
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [0.0, 0.0, 0.0],
		"cell_size": 1.0,
		"width": 19,
		"height": 13,
		"walkable_regions": [
			{"min": [1.0, 1.0], "max": [17.9, 11.9]},
		],
	}

func get_scene_title() -> String:
	return "Shelter Rest Lab"

func get_scene_help() -> String:
	return "Dusk, a hurt party, and one member down at the shelter. Hold REST on the pad to sleep (heals 1 HP/sec, costs ATP). Stand by the downed member to revive them. When everyone conscious is resting, the night skips to dawn."

func get_default_character() -> String:
	return "aster"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate()

func get_preview_anchors() -> Dictionary:
	return {
		"shelter_pad": Vector3(13.0, 0.0, 6.0),
		"downed_endo": SPAWNS["endo"],
	}

func get_preview_state() -> Dictionary:
	var gs = _get_game_state()
	var resting := {}
	var downed := {}
	if gs != null:
		for cid in ["aster", "peris", "endo"]:
			resting[cid] = gs.is_resting(str(cid))
			downed[cid] = gs.is_downed(str(cid))
		return {"contract_id": "rest_lab_v1", "day": gs.game_day, "time": gs.game_time,
			"resting": resting, "downed": downed}
	return {"contract_id": "rest_lab_v1"}
