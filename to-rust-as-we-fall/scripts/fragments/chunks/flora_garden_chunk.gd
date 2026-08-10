extends "res://scripts/scene_chunks/scene_chunk.gd"

## Flora Garden — the floral network's teaching ground (GDD: Peris's flora tending). Fast days
## (~75s) drive the loop: pick a seed from the crate, PLANT it on a soil pad, TEND it each day
## and watch it grow a stage at every dawn; flourishing growths light the dark east end of the
## room; the two near pads grow into ONE
## mycelial network while the far pad stays its own. Untended growths hold — the daily
## commitment is the lesson.

const DAY_LENGTH := 75.0
const SEED_CRATE_POS := Vector3(3.0, 0.0, 6.0)
const PAD_POSITIONS := [Vector3(8.0, 0.0, 4.5), Vector3(10.5, 0.0, 5.5), Vector3(16.5, 0.0, 8.5)]
const GARDEN_AUTHORITY_VERSION := 3
const INITIAL_SEED_STOCK := 3
const GARDEN_AUTHORITY_PREFIX := "runtime:flora_garden:"
const GARDEN_INTERACTION_POSITION_TOLERANCE := 0.15
const GARDEN_INTERACTION_HEIGHT_TOLERANCE := 1.25
const ACTION_SEED_CRATE := "seed_crate"
const ACTION_PLANT_PREFIX := "plant:"
const ACTION_TEND_PREFIX := "tend:"
const SEED_CLAIM_IDLE := "idle"
const SEED_CLAIMING := "claiming"
const PLANT_IDLE := "idle"
const PLANTING := "planting"
const SEED_SOURCE_OFFSETS := [
	Vector3(-0.24, 0.38, -0.20),
	Vector3(0.02, 0.38, 0.18),
	Vector3(0.27, 0.38, -0.08),
]

const SPAWNS := {
	"peris": Vector3(4.0, 0.0, 5.0),
	"aster": Vector3(2.5, 0.0, 4.0),
	"endo": Vector3(2.5, 0.0, 7.5),
}

var _clock_label: Label3D
var _seed_crate_label: Label3D
var _seed_crate_interactable
var _pad_interactables: Array = []
var _tend_interactables: Array = []
var _pad_visuals: Array = []
var _flora_visuals := {}        # active flora_id -> its stable per-pad FloraLight presenter
var _flora_interactables := {}  # active flora_id -> its stable per-pad TEND presenter

# The garden record owns finite crate stock and the relationship between each authored soil pad and
# its GameState growth. Growth stage/tended_today remain authoritative in GameState.flora; copying
# them here would recreate the same two-truth bug this record removes.
var _seed_stock := INITIAL_SEED_STOCK
var _source_seed_ids: Array[String] = []
var _issued_seed_ids: Array[String] = []
var _pad_flora_ids: Array[String] = ["", "", ""]
var _pad_seed_ids: Array[String] = ["", "", ""]
var _seed_claim_phase := SEED_CLAIM_IDLE
var _seed_claim_item_id := ""
var _seed_claimed_by := ""
var _seed_claim_serial := 0
var _plant_phase := PLANT_IDLE
var _plant_seed_id := ""
var _plant_actor := ""
var _plant_pad_index := -1
var _plant_serial := 0
## The Interactable registry records every physical acceptance monotonically. This map records the
## last receipt whose semantic consequence the garden owner consumed. A newer registry count with
## an older owner count is the save seam after source acceptance but before the bound callback.
var _source_committed_counts := {}
var _garden_sources := {}
var _garden_authority_initialized := false
var _restoring_garden_authority := false
var _garden_authority_baseline: Dictionary = {}

func _build_chunk() -> void:
	_add_floor(self, Vector3(10.0, -0.05, 6.0), Vector3(20.0, 0.1, 12.0), Color(0.09, 0.1, 0.08))
	# The east end reads DARK — flourishing flora becomes its light.
	_add_floor(self, Vector3(16.5, -0.02, 6.0), Vector3(7.0, 0.1, 12.0), Color(0.045, 0.05, 0.045))
	_seed_crate_label = _add_label(self, "SEED CRATE", SEED_CRATE_POS + Vector3(0, 1.8, 0), Color(0.8, 0.9, 0.7))
	_add_box(self, SEED_CRATE_POS + Vector3(0, 0.3, 0), Vector3(0.8, 0.6, 0.8), Color(0.3, 0.26, 0.16))
	_clock_label = _add_label(self, "", Vector3(10.0, 3.0, 6.0), Color(0.7, 0.9, 0.7))

	_seed_crate_interactable = _add_interactable(self, "SeedCrate", "Take a flora seed",
		SEED_CRATE_POS + Vector3(0.9, 0.0, 0.0), "TAKE SEED", "peris", 0.7, true, 1.6)
	_configure_garden_source(_seed_crate_interactable, ACTION_SEED_CRATE)

	for i in range(PAD_POSITIONS.size()):
		var pad_pos: Vector3 = PAD_POSITIONS[i]
		_add_floor(self, pad_pos + Vector3(0, 0.02, 0), Vector3(1.4, 0.06, 1.4), Color(0.16, 0.12, 0.08))
		var pad = _add_interactable(self, "SoilPad%d" % (i + 1), "Plant a seed here",
			pad_pos, "PLANT", "peris", 0.9, true, 1.5,
			Interactable.InteractableType.TIMED_ACTION)
		pad.set_meta("pad_pos", pad_pos)
		pad.set_meta("pad_index", i)
		_pad_interactables.append(pad)
		_configure_garden_source(pad, _plant_action_id(i))

		# One stable presentation slot per authored pad prevents rollback/reconstruction from appending
		# duplicate growth nodes or duplicate Flora_<id> interactions.
		var bloom := FloraLight.new()
		bloom.name = "FloraVisualPad%d" % (i + 1)
		bloom.position = pad_pos
		bloom.visible = false
		add_child(bloom)
		_pad_visuals.append(bloom)

		var tend = _add_interactable(self, "FloraPad%d" % (i + 1), "Tend the growth",
			pad_pos + Vector3(0.0, 0.0, 0.8), "TEND", "peris", 0.9, true, 1.5,
			Interactable.InteractableType.TIMED_ACTION)
		tend.set_meta("pad_index", i)
		_tend_interactables.append(tend)
		_configure_garden_source(tend, _tend_action_id(i))

	_initialize_garden_authority()
	_apply_garden_presenters()

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
		"note_default": "Take a seed, plant a pad, and tend it each day. Growth comes at dawn; flourishing growths light the dark end."}

func _plant_action_id(pad_index: int) -> String:
	return ACTION_PLANT_PREFIX + str(pad_index)


func _tend_action_id(pad_index: int) -> String:
	return ACTION_TEND_PREFIX + str(pad_index)


func _garden_action_pad_index(action_id: String, prefix: String) -> int:
	if not action_id.begins_with(prefix):
		return -1
	var suffix := action_id.substr(prefix.length())
	return int(suffix) if suffix.is_valid_int() else -1


func _garden_action_ids() -> Array[String]:
	var action_ids: Array[String] = [ACTION_SEED_CRATE]
	for pad_index in range(PAD_POSITIONS.size()):
		action_ids.append(_plant_action_id(pad_index))
		action_ids.append(_tend_action_id(pad_index))
	return action_ids


## Every garden verb consumes the exact one-shot presenter edge minted by its own nearby Peris
## body. The semantic owner rearms repeatable work only when the crate/pad/growth becomes ready
## again, while GameState's trigger_count remains monotonic across every rearm.
func _configure_garden_source(source: Node, action_id: String) -> void:
	if not is_instance_valid(source):
		return
	_garden_sources[action_id] = source
	source.set_meta("garden_action_id", action_id)
	source.set_pre_trigger_validator(
		_validate_garden_source_trigger.bind(action_id, source))
	source.interacted.connect(
		_on_garden_source_interacted.bind(action_id, source))


func _on_garden_source_interacted(action_id: String, source: Node) -> void:
	if action_id == ACTION_SEED_CRATE:
		_on_seed_taken(source)
	elif action_id.begins_with(ACTION_PLANT_PREFIX):
		_on_pad_planted(source)
	elif action_id.begins_with(ACTION_TEND_PREFIX):
		_on_pad_tended(
			_garden_action_pad_index(action_id, ACTION_TEND_PREFIX), source)


func _validate_garden_source_trigger(
		source: Node, actor: String, action_id: String, expected_source: Node) -> bool:
	return is_instance_valid(source) and source == expected_source \
		and _garden_sources.get(action_id) == source \
		and _garden_actor_ready_at_source(source, actor) \
		and _garden_action_ready(action_id)


func _garden_actor_ready_at_source(source: Node, actor: String) -> bool:
	var gs = _get_game_state()
	if gs == null or not is_instance_valid(source) or not (source is Node3D) \
			or actor != "peris" or not gs.characters.has(actor) \
			or not gs.get_party().has(actor) or not gs.is_narratively_available(actor) \
			or gs.is_downed(actor) or gs.is_knocked_down(actor) or gs.is_moving(actor) \
			or gs.is_resting(actor) or gs.is_dodging(actor) or gs.is_endocytosing(actor) \
			or gs.is_external_traversal_active(actor) or gs.is_dragging(actor) \
			or gs.is_field_restoring(actor) or gs.is_pushing(actor):
		return false
	var source_position := _garden_source_data_position(source)
	if not source_position.is_finite():
		return false
	if gs.grid != null and gs.grid.level_count > 1 \
			and int(gs.get_character_level(actor)) != int(
				gs.grid.level_for_y(source_position.y)):
		return false
	var actor_position: Vector3 = gs.get_position(actor)
	var radius := float(source.get("interaction_radius")) \
		+ GARDEN_INTERACTION_POSITION_TOLERANCE
	return Vector2(actor_position.x, actor_position.z).distance_to(
		Vector2(source_position.x, source_position.z)) <= radius \
		and absf(actor_position.y - source_position.y) \
			<= GARDEN_INTERACTION_HEIGHT_TOLERANCE


func _garden_source_data_position(source: Node) -> Vector3:
	var gs = _get_game_state()
	var data_id := str(source.get("data_id")) if is_instance_valid(source) else ""
	if gs != null and data_id != "" and gs.has_interactable(data_id):
		var saved_position: Variant = gs.get_interactable(data_id).get(
			"position", Vector3.INF)
		if saved_position is Vector3:
			return saved_position
	if source is Node3D:
		var world_position := (source as Node3D).global_position
		if gs != null and gs.coord_map != null and gs.coord_map.has_method("to_data"):
			return gs.coord_map.to_data(world_position)
		return world_position
	return Vector3.INF


func _garden_action_ready(action_id: String) -> bool:
	var gs = _get_game_state()
	if gs == null:
		return false
	if action_id == ACTION_SEED_CRATE:
		return _seed_stock > 0 and _seed_claim_phase == SEED_CLAIM_IDLE \
			and _plant_phase == PLANT_IDLE \
			and _find_carried_garden_seed("peris") == "" \
			and gs.has_free_hands("peris", 1) \
			and _next_available_source_seed_id() != ""
	var plant_index := _garden_action_pad_index(action_id, ACTION_PLANT_PREFIX)
	if plant_index >= 0:
		return plant_index < PAD_POSITIONS.size() \
			and _seed_claim_phase == SEED_CLAIM_IDLE \
			and _plant_phase == PLANT_IDLE \
			and _pad_flora_ids[plant_index] == "" \
			and not _pad_has_unowned_growth(gs, plant_index) \
			and _find_carried_garden_seed("peris") != ""
	var tend_index := _garden_action_pad_index(action_id, ACTION_TEND_PREFIX)
	if tend_index < 0 or tend_index >= PAD_POSITIONS.size():
		return false
	var flora_id := _pad_flora_ids[tend_index]
	if flora_id == "" or not gs.flora.has(flora_id):
		return false
	var growth: Dictionary = gs.flora[flora_id]
	return gs.get_flora_stage(flora_id) < GameState.FLORA_STAGES.size() - 1 \
		and not bool(growth.get("tended_today", false))


func _garden_source_trigger_count(source: Node) -> int:
	var gs = _get_game_state()
	var data_id := str(source.get("data_id")) if is_instance_valid(source) else ""
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return -1
	return int(gs.get_interactable(data_id).get("trigger_count", -1))


func _garden_source_receipt_count(source: Node, action_id: String) -> int:
	if not is_instance_valid(source) or _garden_sources.get(action_id) != source:
		return -1
	var actor := str(source.get("active_character"))
	if not _validate_garden_source_trigger(source, actor, action_id, source) \
			or not bool(source.get("one_shot")) or not bool(source.get("_used")) \
			or bool(source.get("interaction_enabled")):
		return -1
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return -1
	var receipt: Dictionary = gs.get_interactable(data_id)
	var trigger_count := int(receipt.get("trigger_count", -1))
	if not bool(receipt.get("one_shot", false)) \
			or not bool(receipt.get("triggered", false)) \
			or bool(receipt.get("enabled", true)) \
			or str(receipt.get("last_trigger_character", "")) != actor \
			or trigger_count <= int(_source_committed_counts.get(action_id, 0)):
		return -1
	return trigger_count


func _consume_garden_source_receipt(source: Node, action_id: String) -> Dictionary:
	var trigger_count := _garden_source_receipt_count(source, action_id)
	if trigger_count < 0:
		return {}
	var actor := str(source.get("active_character"))
	_source_committed_counts[action_id] = trigger_count
	return {
		"action": action_id,
		"actor": actor,
		"trigger_count": trigger_count,
	}


func _on_seed_taken(source: Node = null) -> bool:
	var gs = _get_game_state()
	if gs == null:
		return false
	_initialize_garden_authority()
	var source_receipt := _consume_garden_source_receipt(
		source, ACTION_SEED_CRATE)
	if source_receipt.is_empty():
		return false
	var actor := str(source_receipt.get("actor", ""))
	if actor == "" or not gs.characters.has(actor) or _find_carried_garden_seed(actor) != "":
		return false  # one at a time — hands are the inventory
	var seed_id := _next_available_source_seed_id()
	if seed_id == "" or not _seed_at_source(seed_id):
		_publish_garden_authority()
		_apply_garden_presenters()
		return false
	_seed_claim_phase = SEED_CLAIMING
	_seed_claim_item_id = seed_id
	_seed_claimed_by = actor
	_seed_claim_serial += 1
	_seed_stock -= 1
	_issued_seed_ids.append(seed_id)
	_publish_garden_authority()
	_apply_garden_presenters()
	if not _pick_up_item(actor, seed_id):
		_issued_seed_ids.erase(seed_id)
		_seed_stock += 1
		_clear_seed_claim()
		_publish_garden_authority()
		_apply_garden_presenters()
		return false
	_clear_seed_claim()
	_publish_garden_authority()
	_apply_garden_presenters()
	return true

func _on_pad_planted(pad: Node = null) -> bool:
	var gs = _get_game_state()
	if gs == null or not is_instance_valid(pad):
		return false
	_initialize_garden_authority()
	var pad_index := int(pad.get_meta("pad_index", -1))
	var action_id := _plant_action_id(pad_index)
	var source_receipt := _consume_garden_source_receipt(pad, action_id)
	if source_receipt.is_empty():
		return false
	if pad_index < 0 or pad_index >= PAD_POSITIONS.size() or _pad_flora_ids[pad_index] != "":
		_publish_garden_authority()
		_apply_garden_presenters()
		return false
	if _pad_has_unowned_growth(gs, pad_index):
		_publish_garden_authority()
		_apply_garden_presenters()
		return false
	var pad_pos: Vector3 = pad.get_meta("pad_pos")
	var actor := str(source_receipt.get("actor", ""))
	var seed_id := _find_carried_garden_seed(actor)
	if actor == "" or seed_id == "" or _plant_phase != PLANT_IDLE:
		_publish_garden_authority()
		_apply_garden_presenters()
		return false
	_plant_phase = PLANTING
	_plant_seed_id = seed_id
	_plant_actor = actor
	_plant_pad_index = pad_index
	_plant_serial += 1
	_publish_garden_authority()
	_apply_garden_presenters()
	var flora_id: String = gs.command_plant_flora(actor, pad_pos)
	if flora_id == "":
		_clear_plant_transaction()
		_publish_garden_authority()
		_apply_garden_presenters()
		return false
	var growth: Dictionary = gs.flora.get(flora_id, {})
	if str(growth.get("source_seed_id", "")) != seed_id:
		_clear_plant_transaction()
		_publish_garden_authority()
		_apply_garden_presenters()
		return false
	_pad_flora_ids[pad_index] = flora_id
	_pad_seed_ids[pad_index] = seed_id
	_clear_plant_transaction()
	_publish_garden_authority()
	_apply_garden_presenters()
	return true

func _on_pad_tended(pad_index: int, source: Node = null) -> bool:
	if pad_index < 0 or pad_index >= _pad_flora_ids.size():
		return false
	var gs = _get_game_state()
	if gs == null:
		return false
	_initialize_garden_authority()
	var action_id := _tend_action_id(pad_index)
	var source_receipt := _consume_garden_source_receipt(source, action_id)
	if source_receipt.is_empty():
		return false
	var flora_id := _pad_flora_ids[pad_index]
	var actor := str(source_receipt.get("actor", ""))
	# Publish the source identity before GameState emits its flora mutation. A save on this exact
	# boundary still has an untended growth, so source projection safely rearms it after restore.
	_publish_garden_authority()
	var tended: bool = flora_id != "" and gs.flora.has(flora_id) \
		and gs.command_tend_flora(actor, flora_id)
	_apply_garden_presenters()
	return tended


## Deliberately inert bypass: the garden's authored tending must originate at FloraPadN.
func _on_flora_tended(_flora_id: String, _actor := "peris") -> bool:
	return false

func headless_process(_delta: float) -> void:
	_sync_flora()

func _process(_delta: float) -> void:
	_sync_flora()

func _sync_flora() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	_initialize_garden_authority()
	_apply_garden_presenters()
	if _clock_label != null:
		var grown := []
		for fid in _pad_flora_ids:
			if fid != "" and gs.flora.has(fid):
				grown.append("%s:%s" % [fid, GameState.FLORA_STAGES[gs.get_flora_stage(fid)]])
		_clock_label.text = "DAY %d // T %.2f (%s) // %s" % [gs.get_game_day(), gs.get_time_of_day(), gs.get_day_phase(), ", ".join(grown) if not grown.is_empty() else "no growths yet"]


func flora_garden_authority_key() -> String:
	var owner := chunk_name if chunk_name != "" else "flora_garden"
	return GARDEN_AUTHORITY_PREFIX + owner


func _seed_source_position(ordinal: int) -> Vector3:
	var index := clampi(ordinal - 1, 0, SEED_SOURCE_OFFSETS.size() - 1)
	return SEED_CRATE_POS + (SEED_SOURCE_OFFSETS[index] as Vector3)


func _spawn_source_seed(ordinal: int, legacy_recovery := false) -> String:
	return _spawn_item("flora_seed", _seed_source_position(ordinal), {
		"display_name": "Garden Flora Seed %d" % ordinal,
		"garden_authority": flora_garden_authority_key(),
		"garden_seed_ordinal": ordinal,
		"source_fixture": "SeedCrate",
		"visual_kind": "flora_seed",
		"visual_color": Color(0.58, 0.82, 0.36),
		"legacy_source_recovery": legacy_recovery,
	})


func _is_garden_seed(item_id: String) -> bool:
	var item := _get_item_state(item_id)
	if item.is_empty() or str(item.get("type", "")) != "flora_seed":
		return false
	var properties: Dictionary = item.get("properties", {})
	var ordinal := int(properties.get("garden_seed_ordinal", 0))
	return str(properties.get("garden_authority", "")) == flora_garden_authority_key() \
		and ordinal >= 1 and ordinal <= INITIAL_SEED_STOCK


func _seed_at_source(item_id: String) -> bool:
	if not _is_garden_seed(item_id):
		return false
	var item := _get_item_state(item_id)
	var ordinal := int((item.get("properties", {}) as Dictionary).get("garden_seed_ordinal", 0))
	return str(item.get("location", "")) == "ground" \
		and (item.get("position", Vector3.INF) as Vector3).distance_to(
			_seed_source_position(ordinal)) <= 0.05


func _seed_holder(item_id: String) -> String:
	var item := _get_item_state(item_id)
	return str(item.get("holder", "")) if not item.is_empty() else ""


func _find_carried_garden_seed(actor: String) -> String:
	var gs = _get_game_state()
	if gs == null or actor == "" or not gs.characters.has(actor):
		return ""
	for item_id_v in gs.get_hand_items(actor) + gs.get_internal_items(actor):
		var item_id := str(item_id_v)
		if _is_garden_seed(item_id):
			return item_id
	return ""


func _next_available_source_seed_id() -> String:
	for item_id in _source_seed_ids:
		if not _issued_seed_ids.has(item_id) and _seed_at_source(item_id):
			return item_id
	return ""


func _available_source_seed_count() -> int:
	var count := 0
	for item_id in _source_seed_ids:
		if not _issued_seed_ids.has(item_id) and _seed_at_source(item_id):
			count += 1
	return count


func _clear_seed_claim() -> void:
	_seed_claim_phase = SEED_CLAIM_IDLE
	_seed_claim_item_id = ""
	_seed_claimed_by = ""


func _clear_plant_transaction() -> void:
	_plant_phase = PLANT_IDLE
	_plant_seed_id = ""
	_plant_actor = ""
	_plant_pad_index = -1


func _reset_source_committed_counts_to_registry() -> void:
	_source_committed_counts.clear()
	for action_id in _garden_action_ids():
		var source: Node = _garden_sources.get(action_id)
		_source_committed_counts[action_id] = maxi(
			0, _garden_source_trigger_count(source))


## A one-shot registry receipt newer than the owner's saved count is the synchronous seam after
## Interactable accepted Peris but before this chunk's bound callback began. The semantic record is
## still pre-action, so consume that stale count without granting anything; presenter projection
## then rearms the exact source if its physical prerequisites remain true.
func _reconcile_accepted_garden_source_receipts() -> void:
	for action_id in _garden_action_ids():
		var source: Node = _garden_sources.get(action_id)
		var source_count := maxi(0, _garden_source_trigger_count(source))
		var committed_count := maxi(
			0, int(_source_committed_counts.get(action_id, 0)))
		if source_count > committed_count:
			_source_committed_counts[action_id] = source_count


func _remove_all_garden_seeds() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var remove_ids: Array[String] = []
	for item_id_v in gs.items.keys():
		var item_id := str(item_id_v)
		if _is_garden_seed(item_id):
			remove_ids.append(item_id)
	for item_id in remove_ids:
		_remove_item(item_id)


func _retract_garden_to_physical_baseline(publish_state := false) -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	_remove_all_garden_seeds()
	# An absent/malformed garden record cannot own a growth at one of its exact authored pads.
	# Retract those unmatched future outcomes before making the three source seeds visible again.
	var remove_flora: Array[String] = []
	for flora_id_v in gs.flora.keys():
		var flora_id := str(flora_id_v)
		var growth_pos: Vector3 = (gs.flora[flora_id] as Dictionary).get("position", Vector3.INF)
		for pad_pos in PAD_POSITIONS:
			if growth_pos.distance_to(pad_pos) <= 0.01:
				remove_flora.append(flora_id)
				break
	for flora_id in remove_flora:
		gs.flora.erase(flora_id)
	_source_seed_ids.clear()
	for ordinal in range(1, INITIAL_SEED_STOCK + 1):
		_source_seed_ids.append(_spawn_source_seed(ordinal, true))
	_seed_stock = INITIAL_SEED_STOCK
	_issued_seed_ids.clear()
	_pad_flora_ids = ["", "", ""]
	_pad_seed_ids = ["", "", ""]
	_clear_seed_claim()
	_clear_plant_transaction()
	_reset_source_committed_counts_to_registry()
	_garden_authority_baseline = _garden_authority_state()
	_apply_garden_presenters()
	if publish_state:
		_publish_garden_authority()


func _baseline_garden_authority_state() -> Dictionary:
	return {
		"version": GARDEN_AUTHORITY_VERSION,
		"authority_id": flora_garden_authority_key(),
		"seed_stock": INITIAL_SEED_STOCK,
		"source_seed_ids": _source_seed_ids.duplicate(),
		"issued_seed_ids": [],
		"pad_flora_ids": ["", "", ""],
		"pad_seed_ids": ["", "", ""],
		"seed_claim_phase": SEED_CLAIM_IDLE,
		"seed_claim_item_id": "",
		"seed_claimed_by": "",
		"seed_claim_serial": 0,
		"plant_phase": PLANT_IDLE,
		"plant_seed_id": "",
		"plant_actor": "",
		"plant_pad_index": -1,
		"plant_serial": 0,
		"source_committed_counts": _source_committed_counts.duplicate(true),
	}


func _garden_authority_state() -> Dictionary:
	return {
		"version": GARDEN_AUTHORITY_VERSION,
		"authority_id": flora_garden_authority_key(),
		"seed_stock": _seed_stock,
		"source_seed_ids": _source_seed_ids.duplicate(),
		"issued_seed_ids": _issued_seed_ids.duplicate(),
		"pad_flora_ids": _pad_flora_ids.duplicate(),
		"pad_seed_ids": _pad_seed_ids.duplicate(),
		"seed_claim_phase": _seed_claim_phase,
		"seed_claim_item_id": _seed_claim_item_id,
		"seed_claimed_by": _seed_claimed_by,
		"seed_claim_serial": _seed_claim_serial,
		"plant_phase": _plant_phase,
		"plant_seed_id": _plant_seed_id,
		"plant_actor": _plant_actor,
		"plant_pad_index": _plant_pad_index,
		"plant_serial": _plant_serial,
		"source_committed_counts": _source_committed_counts.duplicate(true),
	}


func _valid_garden_authority(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var saved := raw as Dictionary
	var saved_version := int(saved.get("version", 0))
	if saved_version not in [2, GARDEN_AUTHORITY_VERSION] \
			or str(saved.get("authority_id", "")) != flora_garden_authority_key():
		return false
	var stock := int(saved.get("seed_stock", -1))
	var source_v: Variant = saved.get("source_seed_ids", null)
	var issued_v: Variant = saved.get("issued_seed_ids", null)
	var flora_ids_v: Variant = saved.get("pad_flora_ids", null)
	var seed_ids_v: Variant = saved.get("pad_seed_ids", null)
	if stock < 0 or stock > INITIAL_SEED_STOCK \
			or not source_v is Array or not issued_v is Array \
			or not flora_ids_v is Array or not seed_ids_v is Array:
		return false
	var source_ids := source_v as Array
	var issued := issued_v as Array
	var flora_ids := flora_ids_v as Array
	var seed_ids := seed_ids_v as Array
	if source_ids.size() != INITIAL_SEED_STOCK or issued.size() + stock != INITIAL_SEED_STOCK \
			or flora_ids.size() != PAD_POSITIONS.size() or seed_ids.size() != PAD_POSITIONS.size():
		return false
	var gs = _get_game_state()
	if gs == null:
		return false
	if saved_version >= 3:
		var committed_v: Variant = saved.get("source_committed_counts", null)
		if not committed_v is Dictionary:
			return false
		var committed := committed_v as Dictionary
		for action_id in _garden_action_ids():
			if not committed.has(action_id):
				return false
			var saved_count := int(committed.get(action_id, -1))
			var source: Node = _garden_sources.get(action_id)
			var source_count := _garden_source_trigger_count(source)
			if saved_count < 0 or source_count < 0 or saved_count > source_count:
				return false
	var unique_sources := {}
	for source_index in range(source_ids.size()):
		var source_id := str(source_ids[source_index])
		if source_id == "" or unique_sources.has(source_id):
			return false
		unique_sources[source_id] = true
		if gs.items.has(source_id):
			var source_item: Dictionary = gs.items[source_id]
			var source_properties: Dictionary = source_item.get("properties", {})
			if str(source_item.get("type", "")) != "flora_seed" \
					or str(source_properties.get("garden_authority", "")) != flora_garden_authority_key() \
					or int(source_properties.get("garden_seed_ordinal", 0)) != source_index + 1:
				return false
	# No tagged fourth seed may sit outside the three finite identities.
	for item_id_v in gs.items.keys():
		var item_id := str(item_id_v)
		if _is_garden_seed(item_id) and not unique_sources.has(item_id):
			return false
	var unique_issued := {}
	for seed_id_v in issued:
		var seed_id := str(seed_id_v)
		if seed_id == "" or unique_issued.has(seed_id) or not unique_sources.has(seed_id):
			return false
		unique_issued[seed_id] = true
	var unique_flora := {}
	var consumed_seeds := {}
	for pad_index in range(PAD_POSITIONS.size()):
		var flora_id := str(flora_ids[pad_index])
		var source_seed_id := str(seed_ids[pad_index])
		if (flora_id == "") != (source_seed_id == ""):
			return false
		if flora_id == "":
			continue
		if unique_flora.has(flora_id) or consumed_seeds.has(source_seed_id) \
				or not unique_issued.has(source_seed_id) or not gs.flora.has(flora_id):
			return false
		var growth: Dictionary = gs.flora[flora_id]
		var growth_pos: Vector3 = growth.get("position", Vector3.INF)
		if growth_pos.distance_to(PAD_POSITIONS[pad_index]) > 0.01 \
				or str(growth.get("source_seed_id", "")) != source_seed_id:
			return false
		unique_flora[flora_id] = true
		consumed_seeds[source_seed_id] = true

	var claim_phase := str(saved.get("seed_claim_phase", ""))
	var claim_item_id := str(saved.get("seed_claim_item_id", ""))
	var claimed_by := str(saved.get("seed_claimed_by", ""))
	var claim_serial := int(saved.get("seed_claim_serial", -1))
	if claim_serial < 0 or claim_phase not in [SEED_CLAIM_IDLE, SEED_CLAIMING]:
		return false
	if claim_phase == SEED_CLAIM_IDLE:
		if claim_item_id != "" or claimed_by != "":
			return false
	elif claim_item_id == "" or claimed_by == "" or claim_serial < 1 \
			or not unique_issued.has(claim_item_id) or not gs.items.has(claim_item_id):
		return false

	var plant_phase := str(saved.get("plant_phase", ""))
	var plant_seed_id := str(saved.get("plant_seed_id", ""))
	var plant_actor := str(saved.get("plant_actor", ""))
	var plant_pad_index := int(saved.get("plant_pad_index", -1))
	var plant_serial := int(saved.get("plant_serial", -1))
	if plant_serial < 0 or plant_phase not in [PLANT_IDLE, PLANTING]:
		return false
	var pending_growth_id := ""
	if plant_phase == PLANT_IDLE:
		if plant_seed_id != "" or plant_actor != "" or plant_pad_index != -1:
			return false
	else:
		if plant_seed_id == "" or plant_actor == "" or plant_serial < 1 \
				or plant_pad_index < 0 or plant_pad_index >= PAD_POSITIONS.size() \
				or not unique_issued.has(plant_seed_id) \
				or str(flora_ids[plant_pad_index]) != "" or str(seed_ids[plant_pad_index]) != "":
			return false
		pending_growth_id = gs.find_flora_at_site(PAD_POSITIONS[plant_pad_index])
		if pending_growth_id != "":
			var pending_growth: Dictionary = gs.flora[pending_growth_id]
			if str(pending_growth.get("source_seed_id", "")) != plant_seed_id:
				return false
			consumed_seeds[plant_seed_id] = true
	# Each issued seed has one authoritative location: a still-live item or exactly one planted pad.
	# This closes the exploit where reconstructing the crate could issue the same finite stock twice.
	for source_id_v in source_ids:
		var source_id := str(source_id_v)
		var live_item: bool = gs.items.has(source_id)
		if not unique_issued.has(source_id):
			if not live_item or not _seed_at_source(source_id):
				return false
		elif int(live_item) + int(consumed_seeds.has(source_id)) != 1:
			return false
	return true


func _initialize_garden_authority() -> void:
	if _garden_authority_initialized:
		return
	var gs = _get_game_state()
	if gs == null or not gs.has_method("get_world_state"):
		return
	_garden_authority_initialized = true
	var raw: Variant = gs.get_world_state(flora_garden_authority_key(), null)
	if _valid_garden_authority(raw):
		_restore_garden_authority(raw as Dictionary)
	elif _migrate_legacy_garden_authority(raw):
		pass
	else:
		_retract_garden_to_physical_baseline(true)


func _publish_garden_authority() -> void:
	if _restoring_garden_authority or not _garden_authority_initialized:
		return
	var gs = _get_game_state()
	if gs != null and gs.has_method("set_world_state"):
		gs.set_world_state(flora_garden_authority_key(), _garden_authority_state())


func on_game_state_snapshot_restored() -> void:
	super.on_game_state_snapshot_restored()
	_garden_authority_initialized = true
	var gs = _get_game_state()
	var raw: Variant = gs.get_world_state(flora_garden_authority_key(), null) \
		if gs != null and gs.has_method("get_world_state") else null
	if _valid_garden_authority(raw):
		_restore_garden_authority(raw as Dictionary)
	elif _migrate_legacy_garden_authority(raw):
		pass
	else:
		# Absence is construction truth: the snapshot predates every crate/pad action. Retract the
		# presenter's later occupancy without writing a replacement event into the restored timeline.
		_retract_garden_to_physical_baseline(false)


func _restore_garden_authority(saved: Dictionary) -> void:
	_restoring_garden_authority = true
	_seed_stock = clampi(int(saved.get("seed_stock", INITIAL_SEED_STOCK)), 0, INITIAL_SEED_STOCK)
	_source_seed_ids.clear()
	for seed_id_v in saved.get("source_seed_ids", []):
		_source_seed_ids.append(str(seed_id_v))
	_issued_seed_ids.clear()
	for seed_id_v in saved.get("issued_seed_ids", []):
		_issued_seed_ids.append(str(seed_id_v))
	_pad_flora_ids.clear()
	for flora_id_v in saved.get("pad_flora_ids", ["", "", ""]):
		_pad_flora_ids.append(str(flora_id_v))
	_pad_seed_ids.clear()
	for seed_id_v in saved.get("pad_seed_ids", ["", "", ""]):
		_pad_seed_ids.append(str(seed_id_v))
	while _pad_flora_ids.size() < PAD_POSITIONS.size():
		_pad_flora_ids.append("")
	while _pad_seed_ids.size() < PAD_POSITIONS.size():
		_pad_seed_ids.append("")
	_seed_claim_phase = str(saved.get("seed_claim_phase", SEED_CLAIM_IDLE))
	_seed_claim_item_id = str(saved.get("seed_claim_item_id", ""))
	_seed_claimed_by = str(saved.get("seed_claimed_by", ""))
	_seed_claim_serial = maxi(0, int(saved.get("seed_claim_serial", 0)))
	_plant_phase = str(saved.get("plant_phase", PLANT_IDLE))
	_plant_seed_id = str(saved.get("plant_seed_id", ""))
	_plant_actor = str(saved.get("plant_actor", ""))
	_plant_pad_index = int(saved.get("plant_pad_index", -1))
	_plant_serial = maxi(0, int(saved.get("plant_serial", 0)))
	_source_committed_counts.clear()
	if int(saved.get("version", 0)) >= 3:
		var saved_counts: Dictionary = saved.get("source_committed_counts", {})
		for action_id in _garden_action_ids():
			_source_committed_counts[action_id] = maxi(
				0, int(saved_counts.get(action_id, 0)))
	else:
		# Version 2 predates owner-side receipt identities. Burn its already-recorded registry history
		# so no old trigger can masquerade as a newly accepted physical use after migration.
		_reset_source_committed_counts_to_registry()
	_reconcile_accepted_garden_source_receipts()
	_reconcile_garden_transactions()
	_restoring_garden_authority = false
	_apply_garden_presenters()
	_publish_garden_authority()


func _reconcile_garden_transactions() -> void:
	if _seed_claim_phase == SEED_CLAIMING:
		if _seed_at_source(_seed_claim_item_id):
			_issued_seed_ids.erase(_seed_claim_item_id)
			_seed_stock = mini(INITIAL_SEED_STOCK, _seed_stock + 1)
			_clear_seed_claim()
		elif _seed_holder(_seed_claim_item_id) == _seed_claimed_by:
			_clear_seed_claim()
		# A different holder is an unresolved malformed reservation. Do not retarget it.

	if _plant_phase != PLANTING:
		return
	var gs = _get_game_state()
	if gs == null or _plant_pad_index < 0 or _plant_pad_index >= PAD_POSITIONS.size():
		return
	var flora_id: String = gs.find_flora_at_site(PAD_POSITIONS[_plant_pad_index])
	if flora_id != "":
		var growth: Dictionary = gs.flora[flora_id]
		if str(growth.get("source_seed_id", "")) == _plant_seed_id:
			_pad_flora_ids[_plant_pad_index] = flora_id
			_pad_seed_ids[_plant_pad_index] = _plant_seed_id
			_clear_plant_transaction()
		return
	if _seed_holder(_plant_seed_id) == _plant_actor:
		# Snapshot landed after publishing PLANTING but before GameState consumed the seed.
		_clear_plant_transaction()


## Version 1 recorded already-issued exact seed IDs but represented the unopened crate as a counter.
## Preserve any honest carried/planted identities, attach provenance to their saved growths, and make
## the remaining stock visible at the crate. A malformed v1 record falls through to full retraction.
func _migrate_legacy_garden_authority(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var saved := raw as Dictionary
	if int(saved.get("version", 0)) != 1 \
			or str(saved.get("authority_id", "")) != flora_garden_authority_key():
		return false
	var issued_v: Variant = saved.get("issued_seed_ids", null)
	var flora_v: Variant = saved.get("pad_flora_ids", null)
	var pad_seed_v: Variant = saved.get("pad_seed_ids", null)
	var stock := int(saved.get("seed_stock", -1))
	if not issued_v is Array or not flora_v is Array or not pad_seed_v is Array \
			or (issued_v as Array).size() + stock != INITIAL_SEED_STOCK \
			or (flora_v as Array).size() != PAD_POSITIONS.size() \
			or (pad_seed_v as Array).size() != PAD_POSITIONS.size():
		return false
	var gs = _get_game_state()
	if gs == null:
		return false
	var issued: Array = issued_v as Array
	var unique := {}
	for seed_id_v in issued:
		var seed_id := str(seed_id_v)
		if seed_id == "" or unique.has(seed_id):
			return false
		unique[seed_id] = true
	# Validate/infer the old pad provenance before mutating anything.
	for pad_index in range(PAD_POSITIONS.size()):
		var flora_id := str((flora_v as Array)[pad_index])
		var seed_id := str((pad_seed_v as Array)[pad_index])
		if (flora_id == "") != (seed_id == ""):
			return false
		if flora_id != "" and (not unique.has(seed_id) or not gs.flora.has(flora_id)):
			return false

	_restoring_garden_authority = true
	_source_seed_ids.clear()
	_issued_seed_ids.clear()
	for issued_index in range(issued.size()):
		var seed_id := str(issued[issued_index])
		_source_seed_ids.append(seed_id)
		_issued_seed_ids.append(seed_id)
		if gs.items.has(seed_id):
			var item: Dictionary = gs.items[seed_id]
			var properties: Dictionary = item.get("properties", {})
			if str(item.get("type", "")) != "flora_seed" \
					or str(properties.get("garden_authority", "")) != flora_garden_authority_key():
				_restoring_garden_authority = false
				return false
			properties["garden_seed_ordinal"] = issued_index + 1
			properties["source_fixture"] = "SeedCrate"
			item["properties"] = properties
	_pad_flora_ids.clear()
	_pad_seed_ids.clear()
	for pad_index in range(PAD_POSITIONS.size()):
		var flora_id := str((flora_v as Array)[pad_index])
		var seed_id := str((pad_seed_v as Array)[pad_index])
		_pad_flora_ids.append(flora_id)
		_pad_seed_ids.append(seed_id)
		if flora_id != "":
			var growth: Dictionary = gs.flora[flora_id]
			growth["source_seed_id"] = seed_id
	for ordinal in range(issued.size() + 1, INITIAL_SEED_STOCK + 1):
		_source_seed_ids.append(_spawn_source_seed(ordinal, true))
	_seed_stock = stock
	_clear_seed_claim()
	_clear_plant_transaction()
	_reset_source_committed_counts_to_registry()
	_restoring_garden_authority = false
	_garden_authority_baseline = _garden_authority_state()
	_apply_garden_presenters()
	_publish_garden_authority()
	return _valid_garden_authority(_garden_authority_state())


func _apply_garden_presenters() -> void:
	if _pad_visuals.size() != PAD_POSITIONS.size() \
			or _pad_interactables.size() != PAD_POSITIONS.size() \
			or _tend_interactables.size() != PAD_POSITIONS.size():
		return
	var gs = _get_game_state()
	if gs == null:
		return
	_flora_visuals.clear()
	_flora_interactables.clear()
	_project_garden_source(ACTION_SEED_CRATE)
	if _seed_crate_label != null:
		_seed_crate_label.text = "SEED CRATE // %d REMAIN" % _seed_stock
	for pad_index in range(PAD_POSITIONS.size()):
		var flora_id: String = _pad_flora_ids[pad_index]
		var growth_exists: bool = flora_id != "" and gs.flora.has(flora_id)
		var bloom: FloraLight = _pad_visuals[pad_index]
		bloom.visible = growth_exists
		bloom.position = PAD_POSITIONS[pad_index]
		var tend = _tend_interactables[pad_index]
		if growth_exists:
			var stage: int = gs.get_flora_stage(flora_id)
			var growth: Dictionary = gs.flora[flora_id]
			bloom.set_growth_scale(1.0 + stage * 0.8)
			bloom.set_light_range(gs.get_flora_light_radius(flora_id))
			_flora_visuals[flora_id] = bloom
			_flora_interactables[flora_id] = tend
		_project_garden_source(_tend_action_id(pad_index))
		_project_garden_source(_plant_action_id(pad_index))


func _project_garden_source(action_id: String) -> void:
	var source: Node = _garden_sources.get(action_id)
	if not is_instance_valid(source):
		return
	_ensure_garden_source_registry_contract(source)
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return
	var should_enable := _garden_action_ready(action_id)
	var spec: Dictionary = gs.get_interactable(data_id)
	var triggered := bool(spec.get("triggered", false))
	var source_count := int(spec.get("trigger_count", 0))
	var committed_count := int(_source_committed_counts.get(action_id, 0))
	var accepted_before_owner := source_count > committed_count
	if should_enable and triggered and not accepted_before_owner:
		_rearm_garden_source(source)
		return
	if should_enable and not triggered:
		gs.set_interactable_enabled(data_id, true)
		if source.has_method("restore_one_shot_presenter"):
			source.restore_one_shot_presenter(false, true)
		return
	gs.set_interactable_enabled(data_id, false)
	if source.has_method("restore_one_shot_presenter"):
		source.restore_one_shot_presenter(triggered, false)


func _ensure_garden_source_registry_contract(source: Node) -> void:
	if not is_instance_valid(source):
		return
	source.set("one_shot", true)
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return
	var spec: Dictionary = gs.get_interactable(data_id)
	if bool(spec.get("one_shot", false)):
		return
	# Version-2 saves serialized these controls as repeatable. Re-register the same stable source,
	# position, trigger count, and actor history under the one-shot receipt grammar; no gameplay
	# consequence is emitted, and the owner-side migration burns the old count.
	spec["id"] = data_id
	spec["one_shot"] = true
	spec["enabled"] = bool(spec.get("enabled", true))
	gs.register_interactable(spec)


func _rearm_garden_source(source: Node) -> void:
	if not is_instance_valid(source):
		return
	if source.is_node_ready():
		source.reset()
		return
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs != null and data_id != "" and gs.has_interactable(data_id):
		gs.reset_interactable(data_id)
	source.set("_used", false)
	source.set("interaction_enabled", true)


func _pad_has_unowned_growth(gs, pad_index: int) -> bool:
	for flora_id_v in gs.flora.keys():
		var flora_id := str(flora_id_v)
		if flora_id == _pad_flora_ids[pad_index]:
			continue
		var growth: Dictionary = gs.flora[flora_id]
		var growth_pos: Vector3 = growth.get("position", Vector3.INF)
		if growth_pos.distance_to(PAD_POSITIONS[pad_index]) <= 0.01:
			return true
	return false


func _set_interactable_enabled(interactable: Node, enabled: bool) -> void:
	if interactable == null or not is_instance_valid(interactable):
		return
	if interactable.has_method("is_interaction_enabled") \
			and bool(interactable.call("is_interaction_enabled")) == enabled:
		return
	interactable.call("set_interaction_enabled", enabled)

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
	return "Peris's tending loop on fast days: take a seed, plant a pad, and tend the growth each day — it advances at dawn. Flourishing growths light the dark end, and the two near pads form one mycelial network."

func get_default_character() -> String:
	return "peris"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate()

func get_preview_anchors() -> Dictionary:
	return {
		"seed_crate": SEED_CRATE_POS,
		"pad_1": PAD_POSITIONS[0], "pad_2": PAD_POSITIONS[1], "pad_3": PAD_POSITIONS[2],
	}

## Declared from the design, before the body: a finite seed crate, near pads whose growths join one
## mycelial network while the far pad stays its own, a TEND station per pad, and one stable bloom
## presenter per authored pad. --test-fragment-manifest proves the built scene matches.
func get_fragment_manifest() -> Dictionary:
	return {
		# Nothing here charges a toll: a player who plays it perfectly finishes whole, so this
		# fragment may be socketed onto a SAFE arm of a branch point.
		"route_class": "clean",
		"safe_route_test": "--test-flora-garden",
		"components": [
			{"id": "seed_crate", "kind": "interactable", "node_name": "SeedCrate"},
			{"id": "near_pad", "kind": "interactable", "node_name": "SoilPad1"},
			{"id": "far_pad", "kind": "interactable", "node_name": "SoilPad3"},
			{"id": "tend_station", "kind": "interactable", "node_name": "FloraPad1"},
			{"id": "pad_blooms", "kind": "node", "node_class": "FloraLight", "count": 3},
		],
		"behaviours": [
			{
				"id": "daily_tending_flourishes",
				"claim": "a crate seed planted on a pad and tended each day advances a stage at dawn and reaches flourishing",
				"test": "--test-flora-garden",
			},
			{
				"id": "flourishing_sheds_light",
				"claim": "a flourishing growth sheds real light where it stands",
				"test": "--test-flora-garden",
			},
			{
				"id": "near_pads_one_network",
				"claim": "the two near pads grow into ONE mycelial network",
				"test": "--test-flora-garden",
			},
		],
	}

func get_preview_state() -> Dictionary:
	var gs = _get_game_state()
	if gs == null:
		return {"contract_id": "flora_garden_v1", "authority_version": GARDEN_AUTHORITY_VERSION}
	var stages := {}
	var visible_growth_count := 0
	var tendable_count := 0
	for pad_index in range(_pad_flora_ids.size()):
		var fid := _pad_flora_ids[pad_index]
		if fid == "" or not gs.flora.has(fid):
			continue
		stages[fid] = gs.get_flora_stage(fid)
		visible_growth_count += 1
		if pad_index < _tend_interactables.size() \
				and _tend_interactables[pad_index].is_interaction_enabled():
			tendable_count += 1
	return {
		"contract_id": "flora_garden_v1",
		"authority_version": GARDEN_AUTHORITY_VERSION,
		"day": gs.get_game_day(),
		"stages": stages,
		"seed_stock": _seed_stock,
		"source_seed_ids": _source_seed_ids.duplicate(),
		"source_seed_count": _source_seed_ids.size(),
		"available_source_seed_count": _available_source_seed_count(),
		"issued_seed_count": _issued_seed_ids.size(),
		"seed_claim_phase": _seed_claim_phase,
		"seed_claim_item_id": _seed_claim_item_id,
		"seed_claimed_by": _seed_claimed_by,
		"seed_claim_serial": _seed_claim_serial,
		"plant_phase": _plant_phase,
		"plant_seed_id": _plant_seed_id,
		"plant_actor": _plant_actor,
		"plant_pad_index": _plant_pad_index,
		"plant_serial": _plant_serial,
		"source_committed_counts": _source_committed_counts.duplicate(true),
		"pad_flora_ids": _pad_flora_ids.duplicate(),
		"visible_growth_count": visible_growth_count,
		"tendable_count": tendable_count,
	}
