extends "res://scripts/scene_chunks/scene_chunk.gd"

## Flora Garden — the floral network's teaching ground (GDD: Peris's flora tending). Fast days
## (~75s) drive the loop: pick a seed from the crate, PLANT it on a soil pad, TEND it each day
## and watch it grow a stage at every dawn; established growths HARVEST a tonic once a day;
## flourishing growths light the dark east end of the room; the two near pads grow into ONE
## mycelial network while the far pad stays its own. Untended growths hold — the daily
## commitment is the lesson.

const DAY_LENGTH := 75.0
const SEED_CRATE_POS := Vector3(3.0, 0.0, 6.0)
const PAD_POSITIONS := [Vector3(8.0, 0.0, 4.5), Vector3(10.5, 0.0, 5.5), Vector3(16.5, 0.0, 8.5)]

const SPAWNS := {
	"peris": Vector3(4.0, 0.0, 5.0),
	"aster": Vector3(2.5, 0.0, 4.0),
	"endo": Vector3(2.5, 0.0, 7.5),
}

var _clock_label: Label3D
var _pad_interactables: Array = []
var _flora_visuals := {}      # flora_id -> FloraLight (glowing bloom; scale + light range track the stage)
var _flora_interactables := {}  # flora_id -> Interactable (tend/harvest)

func _build_chunk() -> void:
	_add_floor(self, Vector3(10.0, -0.05, 6.0), Vector3(20.0, 0.1, 12.0), Color(0.09, 0.1, 0.08))
	# The east end reads DARK — flourishing flora becomes its light.
	_add_floor(self, Vector3(16.5, -0.02, 6.0), Vector3(7.0, 0.1, 12.0), Color(0.045, 0.05, 0.045))
	_add_label(self, "SEED CRATE", SEED_CRATE_POS + Vector3(0, 1.8, 0), Color(0.8, 0.9, 0.7))
	_add_box(self, SEED_CRATE_POS + Vector3(0, 0.3, 0), Vector3(0.8, 0.6, 0.8), Color(0.3, 0.26, 0.16))
	_clock_label = _add_label(self, "", Vector3(10.0, 3.0, 6.0), Color(0.7, 0.9, 0.7))

	var crate = _add_interactable(self, "SeedCrate", "Take a flora seed",
		SEED_CRATE_POS + Vector3(0.9, 0.0, 0.0), "TAKE SEED", "peris", 0.7, false, 1.6)
	crate.interacted.connect(_on_seed_taken)

	for i in range(PAD_POSITIONS.size()):
		var pad_pos: Vector3 = PAD_POSITIONS[i]
		_add_floor(self, pad_pos + Vector3(0, 0.02, 0), Vector3(1.4, 0.06, 1.4), Color(0.16, 0.12, 0.08))
		var pad = _add_interactable(self, "SoilPad%d" % (i + 1), "Plant a seed here",
			pad_pos, "PLANT", "peris", 0.9, false, 1.5)
		pad.set_meta("pad_pos", pad_pos)
		pad.interacted.connect(_on_pad_planted.bind(pad))
		_pad_interactables.append(pad)

func reset_preview_state() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	gs.set_game_clock(1, 0.2)
	gs.set_day_length(DAY_LENGTH)

func get_preview_character_state() -> Dictionary:
	return {"peris": {"hp": 90.0, "atp": 6.0}}

func get_preview_time_state() -> Dictionary:
	return {"day": 1, "time": 0.2, "advance_time": false,
		"note_default": "Take a seed, plant a pad, tend it EVERY day. Growth comes at dawn; established growths yield; flourishing growths light the dark end."}

func _on_seed_taken() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	if gs._find_carried_item("peris", "flora_seed") != "":
		return  # one at a time — hands are the inventory
	var seed_id: String = gs.spawn_item("flora_seed", gs.get_position("peris"))
	gs.pick_up_item("peris", seed_id)

func _on_pad_planted(pad) -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var pad_pos: Vector3 = pad.get_meta("pad_pos")
	var flora_id: String = gs.command_plant_flora("peris", pad_pos)
	if flora_id == "":
		return
	pad.set_interaction_enabled(false)
	_ensure_flora_nodes(flora_id, pad_pos)

## Each growth gets a TEND/HARVEST interactable + a glowing FloraLight that scales with its stage.
func _ensure_flora_nodes(flora_id: String, pos: Vector3) -> void:
	var bloom := FloraLight.new()
	bloom.name = "FloraVisual_" + flora_id
	bloom.position = pos
	add_child(bloom)
	_flora_visuals[flora_id] = bloom

	var it = _add_interactable(self, "Flora_" + flora_id, "Tend or harvest the growth",
		pos + Vector3(0.0, 0.0, 0.8), "TEND", "peris", 0.9, false, 1.5)
	it.interacted.connect(_on_flora_tended.bind(flora_id))
	_flora_interactables[flora_id] = it

## One interaction covers the loop: harvest when there is a yield, otherwise tend.
func _on_flora_tended(flora_id: String) -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	if gs.get_flora_stage(flora_id) >= GameState.FLORA_HARVEST_STAGE \
			and int(gs.flora[flora_id].harvested_day) < gs.get_game_day():
		gs.command_harvest_flora("peris", flora_id)
	else:
		gs.command_tend_flora("peris", flora_id)

func headless_process(_delta: float) -> void:
	_sync_flora()

func _process(_delta: float) -> void:
	_sync_flora()

func _sync_flora() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for flora_id in gs.flora.keys():
		var fid := str(flora_id)
		if not _flora_visuals.has(fid):
			_ensure_flora_nodes(fid, gs.flora[fid].position)
		var stage: int = gs.get_flora_stage(fid)
		var bloom: FloraLight = _flora_visuals[fid]
		bloom.set_growth_scale(1.0 + stage * 0.8)
		bloom.set_light_range(gs.get_flora_light_radius(fid))
	if _clock_label != null:
		var grown := []
		for fid in gs.flora.keys():
			grown.append("%s:%s" % [fid, GameState.FLORA_STAGES[gs.get_flora_stage(str(fid))]])
		_clock_label.text = "DAY %d // T %.2f (%s) // %s" % [gs.get_game_day(), gs.get_time_of_day(), gs.get_day_phase(), ", ".join(grown) if not grown.is_empty() else "no growths yet"]

func get_grid_data() -> Dictionary:
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [0.0, 0.0, 0.0],
		"cell_size": 1.0,
		"width": 21,
		"height": 13,
		"walkable_regions": [{"min": [1.0, 1.0], "max": [19.9, 11.9]}],
	}

func get_scene_title() -> String:
	return "Flora Garden"

func get_scene_help() -> String:
	return "Peris's tending loop on fast days: take a seed, plant a pad, tend the growth every day — it advances each dawn. Established growths yield a tonic daily; flourishing growths light the dark end. The two near pads grow into one mycelial network."

func get_default_character() -> String:
	return "peris"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate()

func get_preview_anchors() -> Dictionary:
	return {
		"seed_crate": SEED_CRATE_POS,
		"pad_1": PAD_POSITIONS[0], "pad_2": PAD_POSITIONS[1], "pad_3": PAD_POSITIONS[2],
	}

func get_preview_state() -> Dictionary:
	var gs = _get_game_state()
	if gs == null:
		return {"contract_id": "flora_garden_v1"}
	var stages := {}
	for fid in gs.flora.keys():
		stages[str(fid)] = gs.get_flora_stage(str(fid))
	return {"contract_id": "flora_garden_v1", "day": gs.get_game_day(), "stages": stages}
