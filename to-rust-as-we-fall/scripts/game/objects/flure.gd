class_name Flure
extends Interactable

## A LURE flower (channels "flure"). Activating it emits a signal the hunters home in on: every lure target within
## attract_range drops the hunt, is marked DISTRACTED, and is sent to the flure — crossing the channels en route,
## where the Channel drowns them. attract_range is deliberately LARGER than the hunters' player-sense range, so they
## lock onto the flure rather than the party (they don't immediately come across at you).
##
## Self-contained + reusable: it owns its glow visual, its outline/hover wiring (so EVERY flure in EVERY fragment is
## highlighted identically — no per-chunk variance), and its lure logic. A fragment / level builder just places it
## and injects (game_state, the lure-target ids). This is the first of the modular gameplay objects: a fragment
## becomes a COMPOSITION of these, not a script that re-implements each mechanic.

signal flure_activated(pulled: int)
signal flure_targets_settled(activation_serial: int)

const STATE_CONTRACT := "flure/v2"
const LEGACY_STATE_CONTRACT := "flure/v1"
const PHASE_READY := "ready"
const PHASE_APPLYING := "applying"
const PHASE_ACTIVE := "active"
const PHASE_SPENT := "spent"
const SOURCE_POSITION_EPSILON := 0.25
const SOURCE_RECEIPT_POSITION_EPSILON := 0.05
const SOURCE_RECEIPT_TICK_EPSILON := 0.000001
const RESTORE_RESUME_EPSILON := 0.000001
const WINDOW_ANCHOR_ACTIVATION := "activation"
const WINDOW_ANCHOR_ALL_TARGETS_SETTLED := "all_targets_settled"

@export var attract_range := 32.0
@export var glow_color := Color(0.95, 0.78, 0.2)
@export var glow_radius := 0.45
## Stable authored identity used by save/load and deterministic replay. When omitted, the node
## name and authored origin form the identity, so a newly-instantiated presenter finds the same
## GameState record without depending on its transient instance id.
@export var authority_id := ""

## Optional park point for lured FSM enemies (INF = the flure itself) + how long the song holds.
var settle_pos := Vector3.INF
var lure_duration := 60.0
## An ordinary song expires from activation. A generated race may instead use lure_duration as
## an outbound failsafe, then start one shorter hold when every applied target physically settles.
var window_anchor_mode := WINDOW_ANCHOR_ACTIVATION
var settle_hold_duration := -1.0
## Relay compositions may light a second flower while the same targets are already lured. That
## physical song is authoritative but defers its target application until the current song ends.
var allow_deferred_targets := false

var _active := false
var _enemy_resolver: Callable = Callable()   # id -> Enemy node; the loader installs it
var _glow: MeshInstance3D
var _rig: FloraRig = null
## Which transition the body has already played. A phase refresh runs on every
## restore, and a clip restarted each time would keep resetting a plant that is
## simply still spent. It starts at READY because the body is MODELLED ready —
## a plant placed upright and open has not just been tended, and playing the
## tending on arrival would flash a completion nobody worked for.
var _played_phase := PHASE_READY
var _glow_mat: StandardMaterial3D
var _body: Node3D
var _lure_target_ids: Array = []
var _gs   # the GameState (Interactable keeps its own _game_state for data binding; we hold our own for the lure)
var _last_activation_report: Dictionary = {}
var _authored_origin := Vector3.ZERO
var _resolved_authority_id := ""
var _active_until_tick := -1.0
var _restoring_authority := false
var _configured := false
## An accepted interaction is a synchronous capability, not a public method call. The internal
## validator reserves its exact source/body/target receipt while this flag is open; `interacted`
## consumes it before the stack unwinds.
var _flure_trigger_open := false
var _trigger_dispatch_serial := 0
var _pending_source_receipt: Dictionary = {}
var _extra_pre_trigger_validator := Callable()
var _target_settle_overrides: Dictionary = {}

## Configure BEFORE adding to the tree (interaction_radius is read by Interactable._ready when it sizes the pick
## shape). game_state + the lure targets are the only injected dependencies.
func configure(gs, world_pos: Vector3, lure_target_ids: Array, attract := 32.0, radius := 1.6,
		color := Color(0.95, 0.78, 0.2)) -> void:
	_cancel_window_callback()
	_gs = gs
	position = world_pos
	_authored_origin = world_pos
	attract_range = attract
	interaction_radius = radius
	glow_color = color
	interactable_type = InteractableType.INSPECTION
	one_shot = true
	description = "Light the flure"
	tutorial_label = "FLURE"
	_lure_target_ids = lure_target_ids.duplicate()
	_resolved_authority_id = _resolve_authority_id(world_pos)
	_configured = true
	super.set_pre_trigger_validator(_validate_flure_trigger)
	_ensure_arrival_subscription()
	if is_inside_tree():
		_ensure_bound_source()
		_restore_authoritative_runtime()

func _ready() -> void:
	juice_profile = "plant"   # flora rustle on hover + trigger (InteractableJuice)
	# Exported authority_id may be assigned after configure() but before add_child(). Resolve it at
	# attachment time so authored IDs always win over the deterministic fallback.
	_resolved_authority_id = _resolve_authority_id(_authored_origin)
	# Interactable normally gets its pick shape from interactable.tscn; a code-spawned object self-builds it (and
	# the glow visual) BEFORE Interactable._ready reads the shape + sizes it to interaction_radius.
	if get_node_or_null("CollisionShape3D") == null:
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var sh := SphereShape3D.new()
		sh.radius = interaction_radius
		cs.shape = sh
		add_child(cs)
	_glow = _build_glow()
	_body = _build_body()
	_ensure_bound_source()
	super._ready()
	if _gs != null:
		set_movement_authority(_gs)
		if _gs.scheduler != null:
			set_scheduler(_gs.scheduler)
	_wire_outline()
	if not interacted.is_connected(_on_interacted):
		interacted.connect(_on_interacted)
	_ensure_arrival_subscription()
	_ensure_authority_record()
	_restore_authoritative_runtime()

func _build_glow() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Glow"
	var sph := SphereMesh.new()
	sph.radius = glow_radius
	sph.height = glow_radius * 2.0
	mi.mesh = sph
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = glow_color * 0.5
	_glow_mat.emission_enabled = true
	_glow_mat.emission = glow_color
	_glow_mat.emission_energy_multiplier = 0.5
	mi.material_override = _glow_mat
	mi.position = Vector3(0.0, 0.35, 0.0)
	add_child(mi)
	return mi

## The species BODY from the archetype piece library — the canonical radial-petal
## Flure (iron-bronze collar + filament core). A LOCAL child, so it rides chunk
## warps and the outline exactly like the glow. If the library is unavailable the
## glow sphere alone still works (the pulse/outline contracts don't change).
## The rigged body where one exists, the static piece otherwise.
##
## Spending a flure is a COLLAPSE, and the spec describes it as one: the plant
## "collapses from the core outward", the petals lose their sheen, the core dries
## and cracks. That is something the player watches happen, so it plays as a clip
## rather than reading as a change in how brightly the same shape glows.
func _build_body() -> Node3D:
	if FloraRig.has_rig("flure"):
		var rigged := FloraRig.new()
		rigged.name = "FlureBody"
		add_child(rigged)
		if rigged.setup("flure"):
			_rig = rigged
			# The halo belongs to the CORE, so it rides the core's bone: parked at
			# a fixed height it would hang in the air at the head's upright
			# position while the stem folds the head away beneath it.
			if _glow != null:
				_glow.scale = Vector3.ONE * 0.4
				if not rigged.attach_to_bone(_glow, "core_0"):
					_glow.position = Vector3(0.0, 0.88, 0.0)
			return rigged
		rigged.queue_free()
	var body := ArchetypePieceLibrary.instantiate("flure")
	if body == null:
		return null
	body.name = "FlureBody"
	add_child(body)
	# With a real plant body the glow sphere tucks into the filament core as its
	# halo instead of floating as a bare orb.
	if _glow != null:
		_glow.position = Vector3(0.0, 0.62, 0.0)
		_glow.scale = Vector3.ONE * 0.55
	return body

## Wire the SHARED outline/hover system onto the flure's meshes (hover = white hull, SHIFT = reveal, click = the
## queued glow), the same path every interactable uses — so the object carries its own consistent feedback.
func _wire_outline() -> void:
	var mgr := OutlineFeedbackManager.ensure(self)
	if mgr == null or _glow == null:
		return
	var meshes: Array = [_glow]
	if _body != null:
		if _body is MeshInstance3D:
			meshes.append(_body)
		for c in _body.find_children("*", "MeshInstance3D", true, false):
			meshes.append(c)
	var target := mgr.outline_meshes(self, str(name) + "Outline", meshes, "flure", maxf(1.0, interaction_radius))
	if target == null:
		return
	if target.has_method("set_interaction_delegate"):
		target.call("set_interaction_delegate", self)
	set_outline_target(target)

## Always refuses: a Flure effect can only follow its exact bound Interactable trigger.
func activate() -> bool:
	return false


func _trigger(play_feedback := true) -> bool:
	if _flure_trigger_open:
		return false
	_trigger_dispatch_serial += 1
	_flure_trigger_open = true
	_pending_source_receipt.clear()
	var accepted := super._trigger(play_feedback)
	# `interacted` is synchronous. Anything still pending belongs to a rejected or stale attempt,
	# never to a capability a later callback may reuse.
	if not _pending_source_receipt.is_empty():
		_pending_source_receipt.clear()
		_clear_pending_source_authority()
	_flure_trigger_open = false
	if accepted:
		_settle_retries = 0
		if _gs != null and _gs.scheduler != null:
			_gs.scheduler.cancel_tag(_settle_retry_tag())
	else:
		_maybe_schedule_settle_retry()
	return accepted

## A real right-click walks the actor to the source and fires ON ARRIVAL —
## often a tick before the cooperative settle finishes, while is_moving still
## reads true, so the physical validation truthfully refuses. That refusal is
## a TIMING artifact, not a plan failure (the player did everything right):
## when the actor stands within reach and only MOTION blocked the fire, retry
## on the scheduler until the settle ends, bounded. Without the retry a
## clicked flure walks, refuses once, and never sings — a committed plan
## whose effect silently never fires.
const SOURCE_ARRIVAL_SLACK := 0.85
const _SETTLE_RETRY_STEP := 0.25
const _SETTLE_RETRY_MAX := 6
var _settle_retries := 0

func _settle_retry_tag() -> String:
	return "flure_settle_retry_%d" % get_instance_id()

func _maybe_schedule_settle_retry() -> void:
	if _gs == null or _gs.scheduler == null:
		return
	var actor := str(active_character)
	if actor.is_empty() or not _gs.characters.has(actor):
		return
	var actor_pos: Vector3 = _gs.get_position(actor)
	var source_pos: Vector3 = _source_data_position()
	var planar := Vector2(actor_pos.x, actor_pos.z).distance_to(
		Vector2(source_pos.x, source_pos.z))
	if planar > interaction_radius + SOURCE_ARRIVAL_SLACK + 0.4:
		return
	if not _actor_busy(actor):
		return
	if _settle_retries >= _SETTLE_RETRY_MAX:
		_settle_retries = 0
		return
	_settle_retries += 1
	_gs.scheduler.cancel_tag(_settle_retry_tag())
	_gs.scheduler.schedule_after(_SETTLE_RETRY_STEP, _settle_retry_fire,
		_settle_retry_tag())

func _settle_retry_fire() -> void:
	if _trigger(false):
		_settle_retries = 0


## Scenario policy may narrow eligibility, but it can never replace this reusable object's physical
## source/body/target proof.
func set_pre_trigger_validator(validator: Callable) -> void:
	_extra_pre_trigger_validator = validator
	super.set_pre_trigger_validator(_validate_flure_trigger)


func _validate_flure_trigger(source: Node, actor_value: String) -> bool:
	_pending_source_receipt.clear()
	if not _flure_trigger_open or source != self or not _configured \
			or _gs == null or _gs.scheduler == null:
		return false
	_ensure_bound_source()
	_ensure_authority_record()
	var saved := _authority_or_default()
	if str(saved.get("phase", PHASE_READY)) != PHASE_READY \
			or not _source_registry_enabled():
		return false
	var actor := str(actor_value)
	if not _actor_ready_at_source(actor):
		return false
	if required_character != "" and actor != required_character:
		return false
	if _extra_pre_trigger_validator.is_valid() \
			and not bool(_extra_pre_trigger_validator.call(source, actor)):
		return false
	var target_plan := _build_target_plan()
	# A rejected physical attempt still exposes a truthful immediate diagnostic, but it does not
	# publish an activation receipt, increment the source nonce, or consume the registry edge.
	_last_activation_report = _report_from_target_plan(target_plan)
	var eligible_count := 0
	var deferred_count := 0
	for entry_v in target_plan:
		var entry := entry_v as Dictionary
		if bool(entry.get("eligible", false)):
			eligible_count += 1
		elif bool(entry.get("deferable", false)):
			deferred_count += 1
	if eligible_count <= 0 and deferred_count <= 0:
		return false

	var receipt_nonce := int(saved.get("next_receipt_nonce", 0)) + 1
	_pending_source_receipt = {
		"version": 1,
		"source_id": _source_interactable_id(),
		"source_key": authority_state_key(),
		"actor": actor,
		"actor_position": _v3_to_value(_gs.get_position(actor)),
		"source_position": _v3_to_value(_source_data_position()),
		"accepted_tick": _scheduler_tick(),
		"dispatch_serial": _trigger_dispatch_serial,
		"nonce": receipt_nonce,
		"expected_trigger_count": _source_trigger_count() + 1,
		"target_plan": target_plan.duplicate(true),
		"phase": "source_reserved",
	}
	saved["next_receipt_nonce"] = receipt_nonce
	saved["pending_source_receipt"] = _pending_source_receipt.duplicate(true)
	_publish_authority(saved)
	return true


func _ensure_bound_source() -> void:
	if _gs == null or not _configured or not _gs.has_method("register_interactable"):
		return
	var source_id := _source_interactable_id()
	if source_id.is_empty():
		return
	if not _gs.has_interactable(source_id):
		_gs.register_interactable({
			"id": source_id,
			"position": _source_data_position(),
			"requires_hold": interactable_type == InteractableType.HOLD_ACTION,
			"interactable_type": interactable_type,
			"hold_time": dwell_time,
			"one_shot": one_shot,
			"required_character": required_character,
			"radius": interaction_radius,
			"tutorial_label": tutorial_label,
			"enabled": interaction_enabled,
		})
	if data_id != source_id or _game_state != _gs:
		bind_data(_gs, source_id)
	super.set_pre_trigger_validator(_validate_flure_trigger)


func _on_interacted() -> void:
	if not _flure_trigger_open or _pending_source_receipt.is_empty():
		return
	var receipt := _pending_source_receipt.duplicate(true)
	_pending_source_receipt.clear()
	if not _receipt_matches_accepted_source(receipt):
		_clear_pending_source_authority()
		return
	_commit_activation_receipt(receipt)

## Commit an accepted source receipt before applying any target consequence.
func _commit_activation_receipt(receipt: Dictionary) -> bool:
	var saved := _authority_or_default()
	if str(saved.get("phase", PHASE_READY)) != PHASE_READY:
		return false
	var target_plan_v: Variant = receipt.get("target_plan", [])
	if not (target_plan_v is Array):
		return false
	var target_plan := (target_plan_v as Array).duplicate(true)
	var receipts := {}
	var eligible_count := 0
	var deferred_count := 0
	for entry_v in target_plan:
		var entry := entry_v as Dictionary
		var target_id := str(entry.get("target_id", ""))
		if target_id.is_empty():
			continue
		if bool(entry.get("eligible", false)):
			eligible_count += 1
			receipts[target_id] = {
				"status": "reserved",
				"mode": str(entry.get("mode", "fallback")),
				"applied_tick": -1.0,
				"settled": false,
				"settled_tick": -1.0,
			}
		elif bool(entry.get("deferable", false)):
			deferred_count += 1
			receipts[target_id] = {
				"status": "deferred",
				"mode": str(entry.get("mode", "enemy")),
				"reason": str(entry.get("reason", "already_lured")),
				"applied_tick": -1.0,
				"settled": false,
				"settled_tick": -1.0,
			}
		else:
			receipts[target_id] = {
				"status": "skipped",
				"mode": str(entry.get("mode", "none")),
				"reason": str(entry.get("reason", "unavailable")),
				"applied_tick": -1.0,
			}
	if eligible_count <= 0 and deferred_count <= 0:
		return false

	var now := _scheduler_tick()
	var deadline := now + maxf(0.0, lure_duration) if lure_duration > 0.0 else -1.0
	saved["phase"] = PHASE_APPLYING
	saved["start_tick"] = now
	saved["end_tick"] = deadline
	saved["window_anchor"] = "transit" \
		if window_anchor_mode == WINDOW_ANCHOR_ALL_TARGETS_SETTLED else "activation"
	saved["settled_tick"] = -1.0
	saved["settle_retime_receipts"] = {}
	saved["rearms"] = not one_shot
	saved["effect_origin"] = _v3_to_value(_source_data_position())
	saved["settle_position"] = _v3_to_value(_settle_data_position())
	saved["linked_target_ids"] = _lure_target_ids.duplicate()
	saved["pending_source_receipt"] = {}
	saved["activation_receipt"] = receipt.duplicate(true)
	saved["activation_serial"] = int(saved.get("activation_serial", 0)) + 1
	saved["last_consumed_trigger_count"] = int(receipt.get(
		"expected_trigger_count", _source_trigger_count()))
	saved["last_trigger_character"] = str(receipt.get("actor", ""))
	saved["target_plan"] = target_plan
	saved["target_receipts"] = receipts
	saved["last_activation_report"] = _report_from_target_plan(target_plan)
	saved["last_effect"] = {
		"activation_serial": int(saved["activation_serial"]),
		"source_receipt_nonce": int(receipt.get("nonce", 0)),
		"source_actor": str(receipt.get("actor", "")),
		"source_trigger_count": int(saved["last_consumed_trigger_count"]),
		"start_tick": now,
		"end_tick": deadline,
		"origin": _v3_to_value(_source_data_position()),
		"settle_position": _v3_to_value(_settle_data_position()),
		"linked_target_ids": _lure_target_ids.duplicate(),
		"pulled_ids": [],
		"fallback_ids": [],
		"target_receipts": receipts.duplicate(true),
	}
	_publish_authority(saved)
	_resume_target_plan(true)
	return true


## Apply only unpaid target receipts. Each target is published as APPLYING before its Enemy/GameState
## consequence. A save from that consequence's signal can reconcile the exact target and resume only
## the untouched suffix on a same-node or fresh-node load.
func _resume_target_plan(emit_completion_signal: bool) -> void:
	var saved := get_authority_state()
	if str(saved.get("phase", "")) != PHASE_APPLYING:
		return
	var plan: Array = saved.get("target_plan", [])
	var receipts: Dictionary = (
		saved.get("target_receipts", {}) as Dictionary
	).duplicate(true)
	for entry_v in plan:
		var entry := entry_v as Dictionary
		if not bool(entry.get("eligible", false)):
			continue
		var target_id := str(entry.get("target_id", ""))
		var target_receipt: Dictionary = (
			receipts.get(target_id, {}) as Dictionary
		).duplicate(true)
		var status := str(target_receipt.get("status", "reserved"))
		if status == "applied":
			continue
		if status == "applying" and _target_effect_matches_plan(entry):
			target_receipt["status"] = "applied"
			target_receipt["applied_tick"] = _scheduler_tick()
			receipts[target_id] = target_receipt
			saved["target_receipts"] = receipts.duplicate(true)
			_sync_effect_receipts(saved)
			_publish_authority(saved)
			continue
		target_receipt["status"] = "applying"
		target_receipt["apply_attempts"] = int(target_receipt.get("apply_attempts", 0)) + 1
		receipts[target_id] = target_receipt
		saved["target_receipts"] = receipts.duplicate(true)
		_sync_effect_receipts(saved)
		_publish_authority(saved)

		var accepted := _apply_target_plan_entry(entry)
		saved = get_authority_state()
		receipts = (saved.get("target_receipts", {}) as Dictionary).duplicate(true)
		target_receipt = (receipts.get(target_id, {}) as Dictionary).duplicate(true)
		if accepted or _target_effect_matches_plan(entry):
			target_receipt["status"] = "applied"
			target_receipt["applied_tick"] = _scheduler_tick()
		else:
			target_receipt["status"] = "failed"
			target_receipt["reason"] = _target_unavailable_reason(entry)
		receipts[target_id] = target_receipt
		saved["target_receipts"] = receipts.duplicate(true)
		_sync_effect_receipts(saved)
		_publish_authority(saved)
	_finalize_activation_transaction(emit_completion_signal)


func _finalize_activation_transaction(emit_completion_signal: bool) -> void:
	var saved := get_authority_state()
	if str(saved.get("phase", "")) != PHASE_APPLYING:
		return
	var deadline := float(saved.get("end_tick", -1.0))
	saved["phase"] = PHASE_ACTIVE if deadline >= 0.0 \
		else (PHASE_SPENT if one_shot else PHASE_READY)
	saved["activation_receipt"] = {}
	_sync_effect_receipts(saved)
	_publish_authority(saved)
	_arm_window_callback(saved)
	if window_anchor_mode == WINDOW_ANCHOR_ALL_TARGETS_SETTLED:
		_reconcile_target_settlements(true)
		saved = _authority_or_default()
	var report: Dictionary = saved.get("last_activation_report", {})
	if emit_completion_signal:
		flure_activated.emit(int(report.get("pulled", 0)))


## Apply targets that were truthfully deferred because another Flure already owned them. This is
## not a second activation: it can run only while the exact physically triggered song is still
## active, and it preserves that activation's serial, deadline, and source receipt.
func claim_deferred_targets() -> bool:
	var saved := _authority_or_default()
	if not allow_deferred_targets \
			or str(saved.get("phase", "")) != PHASE_ACTIVE \
			or float(saved.get("end_tick", -1.0)) <= _scheduler_tick() \
			or not _active_source_receipt_still_valid(saved):
		return false
	var current_plan: Array = (saved.get("target_plan", []) as Array).duplicate(true)
	var current_receipts: Dictionary = (
		saved.get("target_receipts", {}) as Dictionary
	).duplicate(true)
	var fresh_by_id := {}
	for entry_v in _build_target_plan():
		var entry := entry_v as Dictionary
		fresh_by_id[str(entry.get("target_id", ""))] = entry
	var claimed := 0
	for index in range(current_plan.size()):
		var old_entry := current_plan[index] as Dictionary
		var target_id := str(old_entry.get("target_id", ""))
		var receipt: Dictionary = current_receipts.get(target_id, {})
		if str(receipt.get("status", "")) != "deferred" or not fresh_by_id.has(target_id):
			continue
		var fresh := fresh_by_id[target_id] as Dictionary
		if not bool(fresh.get("eligible", false)):
			continue
		# A deferred claim spends only the remainder of this already-singing physical source.
		# Reusing the configured full duration here would let the target remain lured after its
		# flower had visibly gone quiet.
		fresh["duration"] = maxf(
			0.5, float(saved.get("end_tick", -1.0)) - _scheduler_tick())
		current_plan[index] = fresh.duplicate(true)
		current_receipts[target_id] = {
			"status": "reserved",
			"mode": str(fresh.get("mode", "enemy")),
			"applied_tick": -1.0,
			"settled": false,
			"settled_tick": -1.0,
			"deferred_from_activation": true,
		}
		claimed += 1
	if claimed <= 0:
		return false
	saved["phase"] = PHASE_APPLYING
	saved["target_plan"] = current_plan
	saved["target_receipts"] = current_receipts
	saved["deferred_claim_serial"] = int(saved.get("deferred_claim_serial", 0)) + 1
	_publish_authority(saved)
	_resume_target_plan(false)
	var applied := 0
	for target_id_v in current_receipts:
		var target_id := str(target_id_v)
		var receipt: Dictionary = (
			_authority_or_default().get("target_receipts", {}) as Dictionary
		).get(target_id, {})
		if bool(receipt.get("deferred_from_activation", false)) \
				and str(receipt.get("status", "")) == "applied":
			applied += 1
	return applied > 0


## Reconcile an Enemy that physically broke the song by acquiring a target. Calling this while
## every applied target is still lured is inert; the world state, not the caller, decides.
func reconcile_interrupted_targets() -> bool:
	var saved := _authority_or_default()
	if str(saved.get("phase", "")) != PHASE_ACTIVE:
		return false
	var receipts: Dictionary = (
		saved.get("target_receipts", {}) as Dictionary
	).duplicate(true)
	var changed := false
	var still_bound := 0
	for entry_v in (saved.get("target_plan", []) as Array):
		var entry := entry_v as Dictionary
		var target_id := str(entry.get("target_id", ""))
		var receipt: Dictionary = (
			receipts.get(target_id, {}) as Dictionary
		).duplicate(true)
		if str(receipt.get("status", "")) != "applied":
			continue
		var enemy_node = _resolved_enemy(target_id)
		var still_lured: bool = enemy_node != null \
			and enemy_node.has_method("get_lure_availability") \
			and str(enemy_node.call("get_lure_availability")) == "already_lured"
		if still_lured:
			still_bound += 1
			continue
		receipt["status"] = "interrupted"
		receipt["interrupted_tick"] = _scheduler_tick()
		receipts[target_id] = receipt
		changed = true
	if not changed:
		return false
	saved["target_receipts"] = receipts
	_sync_effect_receipts(saved)
	if still_bound <= 0:
		saved["phase"] = PHASE_READY if bool(saved.get("rearms", false)) else PHASE_SPENT
		saved["end_tick"] = -1.0
	_publish_authority(saved)
	if still_bound <= 0:
		_cancel_window_callback()
		if bool(saved.get("rearms", false)):
			_rearm_source_registry()
	return true


func _active_source_receipt_still_valid(saved: Dictionary) -> bool:
	if _gs == null or not _gs.has_interactable(_source_interactable_id()):
		return false
	var effect: Dictionary = saved.get("last_effect", {})
	var trigger_count := int(effect.get(
		"source_trigger_count", saved.get("last_consumed_trigger_count", 0)))
	var actor := str(effect.get(
		"source_actor", saved.get("last_trigger_character", "")))
	var spec: Dictionary = _gs.get_interactable(_source_interactable_id())
	return trigger_count > 0 \
		and int(spec.get("trigger_count", 0)) == trigger_count \
		and str(spec.get("last_trigger_character", "")) == actor


func _ensure_arrival_subscription() -> void:
	if _gs == null or not _gs.has_signal("character_arrived"):
		return
	if not _gs.character_arrived.is_connected(_on_lure_target_arrived):
		_gs.character_arrived.connect(_on_lure_target_arrived)


func _on_lure_target_arrived(target_id: String) -> void:
	if target_id in _lure_target_ids:
		_reconcile_target_settlements(true)


## A settle-anchored song replaces its outbound failsafe only after the exact applied bodies have
## physically arrived. Enemy owns the retimed LURED->RETURN deadline; Flure owns the source receipt.
func _reconcile_target_settlements(emit_signal: bool) -> void:
	var saved := _authority_or_default()
	if window_anchor_mode != WINDOW_ANCHOR_ALL_TARGETS_SETTLED \
			or str(saved.get("phase", "")) not in [PHASE_APPLYING, PHASE_ACTIVE] \
			or str(saved.get("window_anchor", "")) in ["settling", "settled"]:
		return
	var plan: Array = saved.get("target_plan", [])
	var receipts: Dictionary = (
		saved.get("target_receipts", {}) as Dictionary
	).duplicate(true)
	var applied_count := 0
	var settled_count := 0
	var changed := false
	for entry_v in plan:
		var entry := entry_v as Dictionary
		var target_id := str(entry.get("target_id", ""))
		var receipt: Dictionary = (
			receipts.get(target_id, {}) as Dictionary
		).duplicate(true)
		if str(receipt.get("status", "")) != "applied":
			continue
		applied_count += 1
		if not bool(receipt.get("settled", false)) and _target_physically_settled(entry):
			receipt["settled"] = true
			receipt["settled_tick"] = _scheduler_tick()
			receipts[target_id] = receipt
			changed = true
		if bool(receipt.get("settled", false)):
			settled_count += 1
	if changed:
		saved["target_receipts"] = receipts
		_sync_effect_receipts(saved)
		_publish_authority(saved)
	if applied_count <= 0 or settled_count != applied_count \
			or str(saved.get("phase", "")) != PHASE_ACTIVE:
		return
	var now := _scheduler_tick()
	var hold := maxf(0.5, settle_hold_duration)
	saved = _authority_or_default()
	saved["transit_deadline"] = float(saved.get("end_tick", -1.0))
	saved["end_tick"] = now + hold
	saved["settled_tick"] = now
	saved["window_anchor"] = "settling"
	var retime_receipts := {}
	for entry_v in plan:
		var entry := entry_v as Dictionary
		var target_id := str(entry.get("target_id", ""))
		var receipt: Dictionary = receipts.get(target_id, {})
		if str(receipt.get("status", "")) != "applied":
			continue
		retime_receipts[target_id] = {
			"status": "reserved" if str(entry.get("mode", "")) == "enemy" else "applied",
			"deadline": float(saved["end_tick"]),
		}
	saved["settle_retime_receipts"] = retime_receipts
	_publish_authority(saved)
	_resume_settle_retime(emit_signal)


func _resume_settle_retime(emit_signal: bool) -> void:
	var saved := _authority_or_default()
	if str(saved.get("phase", "")) != PHASE_ACTIVE \
			or str(saved.get("window_anchor", "")) != "settling":
		return
	var deadline := float(saved.get("end_tick", -1.0))
	var serial := int(saved.get("activation_serial", 0))
	var plan: Array = saved.get("target_plan", [])
	var retime_receipts: Dictionary = (
		saved.get("settle_retime_receipts", {}) as Dictionary
	).duplicate(true)
	var all_applied := true
	for entry_v in plan:
		var entry := entry_v as Dictionary
		if str(entry.get("mode", "")) != "enemy":
			continue
		var target_id := str(entry.get("target_id", ""))
		if not retime_receipts.has(target_id):
			continue
		var receipt: Dictionary = (
			retime_receipts.get(target_id, {}) as Dictionary
		).duplicate(true)
		if str(receipt.get("status", "")) == "applied":
			continue
		if _enemy_lure_deadline_matches(target_id, serial, deadline):
			receipt["status"] = "applied"
			retime_receipts[target_id] = receipt
			continue
		receipt["status"] = "applying"
		retime_receipts[target_id] = receipt
		saved["settle_retime_receipts"] = retime_receipts.duplicate(true)
		_publish_authority(saved)
		var enemy_node = _resolved_enemy(target_id)
		var accepted: bool = enemy_node != null \
			and enemy_node.has_method("retime_lure_from_source") \
			and bool(enemy_node.call(
				"retime_lure_from_source",
				authority_state_key(),
				serial,
				_v3_from_value(entry.get("settle_position", [])),
				maxf(0.0, deadline - _scheduler_tick())))
		receipt["status"] = "applied" if accepted else "failed"
		retime_receipts[target_id] = receipt
		if not accepted:
			all_applied = false
	for target_id_v in retime_receipts:
		if str((retime_receipts[target_id_v] as Dictionary).get("status", "")) != "applied":
			all_applied = false
	saved = _authority_or_default()
	saved["settle_retime_receipts"] = retime_receipts
	if not all_applied:
		saved["end_tick"] = float(saved.get("transit_deadline", saved.get("end_tick", -1.0)))
		saved["window_anchor"] = "transit"
		_publish_authority(saved)
		_arm_window_callback(saved)
		return
	saved["window_anchor"] = "settled"
	_publish_authority(saved)
	_arm_window_callback(saved)
	if emit_signal:
		flure_targets_settled.emit(serial)


func _target_physically_settled(entry: Dictionary) -> bool:
	if _gs == null:
		return false
	var target_id := str(entry.get("target_id", ""))
	if not _gs.characters.has(target_id):
		return false
	var settle := _v3_from_value(entry.get("settle_position", []))
	return _gs.get_position(target_id).distance_to(settle) <= SOURCE_POSITION_EPSILON \
		and (not _gs.has_method("is_moving") or not bool(_gs.is_moving(target_id)))


func _enemy_lure_deadline_matches(
	target_id: String,
	activation_serial: int,
	deadline: float
) -> bool:
	if _gs == null:
		return false
	var raw: Variant = _gs.get_world_state("runtime:enemy:%s" % target_id, {})
	if not (raw is Dictionary):
		return false
	var enemy_state := raw as Dictionary
	var deadlines: Dictionary = enemy_state.get("deadlines", {})
	return str(enemy_state.get("state", "")) == "lured" \
		and str(enemy_state.get("lure_source_key", "")) == authority_state_key() \
		and int(enemy_state.get("lure_source_activation_serial", 0)) == activation_serial \
		and deadlines.has("lure_end") \
		and is_equal_approx(float(deadlines.get("lure_end", -1.0)), deadline)


func _build_target_plan() -> Array:
	var out: Array = []
	var seen := {}
	var source := _source_data_position()
	for index in range(_lure_target_ids.size()):
		var target_id := str(_lure_target_ids[index])
		var settle := _target_settle_position(target_id)
		var entry := {
			"target_id": target_id,
			"order": index,
			"mode": "none",
			"eligible": false,
			"deferable": false,
			"reason": "",
			"source_position": _v3_to_value(source),
			"settle_position": _v3_to_value(settle),
			"duration": lure_duration,
		}
		if target_id.is_empty() or seen.has(target_id):
			entry["reason"] = "duplicate"
			out.append(entry)
			continue
		seen[target_id] = true
		if _gs == null or not _gs.characters.has(target_id):
			entry["reason"] = "missing"
			out.append(entry)
			continue
		if _gs.get_position(target_id).distance_to(source) > attract_range:
			entry["reason"] = "out_of_range"
			out.append(entry)
			continue
		var enemy_node = _resolved_enemy(target_id)
		if enemy_node != null:
			entry["mode"] = "enemy"
			if not enemy_node.has_method("lure_to"):
				entry["reason"] = "missing_lure_contract"
			else:
				var availability := "available"
				if enemy_node.has_method("get_lure_availability"):
					availability = str(enemy_node.call("get_lure_availability"))
				entry["reason"] = availability
				entry["eligible"] = availability == "available"
				entry["deferable"] = allow_deferred_targets and availability == "already_lured"
		else:
			entry["mode"] = "fallback"
			entry["reason"] = _fallback_target_availability(target_id)
			entry["eligible"] = str(entry["reason"]) == "available"
		out.append(entry)
	return out


func _report_from_target_plan(plan: Array) -> Dictionary:
	var report := {
		"linked_count": _lure_target_ids.size(),
		"pulled": 0,
		"pulled_ids": [],
		"out_of_range_ids": [],
		"committed_ids": [],
		"deferred_ids": [],
		"unavailable_ids": [],
		"missing_ids": [],
	}
	for entry_v in plan:
		var entry := entry_v as Dictionary
		var target_id := str(entry.get("target_id", ""))
		if bool(entry.get("eligible", false)):
			continue
		if bool(entry.get("deferable", false)):
			(report["deferred_ids"] as Array).append(target_id)
			continue
		match str(entry.get("reason", "unavailable")):
			"missing":
				(report["missing_ids"] as Array).append(target_id)
			"out_of_range":
				(report["out_of_range_ids"] as Array).append(target_id)
			"committed":
				(report["committed_ids"] as Array).append(target_id)
			_:
				(report["unavailable_ids"] as Array).append(target_id)
	return report


func _sync_effect_receipts(saved: Dictionary) -> void:
	var receipts: Dictionary = saved.get("target_receipts", {})
	var plan: Array = saved.get("target_plan", [])
	var report: Dictionary = saved.get(
		"last_activation_report", _report_from_target_plan(plan))
	var pulled_ids: Array = []
	var fallback_ids: Array = []
	for entry_v in plan:
		var entry := entry_v as Dictionary
		var target_id := str(entry.get("target_id", ""))
		var receipt: Dictionary = receipts.get(target_id, {})
		if str(receipt.get("status", "")) == "applied":
			pulled_ids.append(target_id)
			if report.has("deferred_ids"):
				(report["deferred_ids"] as Array).erase(target_id)
			if str(entry.get("mode", "")) == "fallback":
				fallback_ids.append(target_id)
		elif str(receipt.get("status", "")) == "failed" \
				and not (report["unavailable_ids"] as Array).has(target_id):
			(report["unavailable_ids"] as Array).append(target_id)
	report["pulled_ids"] = pulled_ids
	report["pulled"] = pulled_ids.size()
	saved["last_activation_report"] = report
	var effect: Dictionary = (saved.get("last_effect", {}) as Dictionary).duplicate(true)
	effect["pulled_ids"] = pulled_ids.duplicate()
	effect["fallback_ids"] = fallback_ids.duplicate()
	effect["target_receipts"] = receipts.duplicate(true)
	saved["last_effect"] = effect


func _apply_target_plan_entry(entry: Dictionary) -> bool:
	if _gs == null:
		return false
	var target_id := str(entry.get("target_id", ""))
	if not _gs.characters.has(target_id):
		return false
	var settle := _v3_from_value(entry.get("settle_position", []))
	if str(entry.get("mode", "")) == "enemy":
		var enemy_node = _resolved_enemy(target_id)
		if enemy_node == null or not enemy_node.has_method("lure_to"):
			return false
		var saved := _authority_or_default()
		return bool(enemy_node.call("lure_to", settle, float(entry.get(
			"duration", lure_duration)), {
				"source_key": authority_state_key(),
				"activation_serial": int(saved.get("activation_serial", 0)),
			}))
	if str(entry.get("mode", "")) != "fallback":
		return false
	_gs.set_character_distracted(target_id, true)
	return bool(_gs.command_move_to_pos(target_id, settle))


func _target_effect_matches_plan(entry: Dictionary) -> bool:
	if _gs == null:
		return false
	var target_id := str(entry.get("target_id", ""))
	if not _gs.characters.has(target_id) or not _gs.is_character_distracted(target_id):
		return false
	var settle := _v3_from_value(entry.get("settle_position", []))
	var destination: Vector3 = _gs.get_destination(target_id) \
		if _gs.has_method("get_destination") else Vector3.INF
	if destination.is_finite() and destination.distance_to(settle) <= SOURCE_POSITION_EPSILON:
		return true
	if _gs.get_position(target_id).distance_to(settle) <= SOURCE_POSITION_EPSILON:
		return true
	# Enemy publishes portable state after its entry hook. This is the stronger fresh-presenter
	# receipt once that publication has occurred; the movement/distraction check above closes the
	# earlier movement_started signal seam inside the same hook.
	var enemy_state_v: Variant = _gs.get_world_state("runtime:enemy:%s" % target_id, {})
	if enemy_state_v is Dictionary:
		var enemy_state := enemy_state_v as Dictionary
		return str(enemy_state.get("state", "")) == "lured" \
			and _v3_from_value(enemy_state.get("lure_settle", [])).distance_to(settle) \
				<= SOURCE_POSITION_EPSILON
	return false


func _target_unavailable_reason(entry: Dictionary) -> String:
	var target_id := str(entry.get("target_id", ""))
	var enemy_node = _resolved_enemy(target_id)
	if enemy_node != null and enemy_node.has_method("get_lure_availability"):
		return str(enemy_node.call("get_lure_availability"))
	return _fallback_target_availability(target_id)


func _fallback_target_availability(target_id: String) -> String:
	if _gs == null or not _gs.characters.has(target_id):
		return "missing"
	var target_stats: Dictionary = (_gs.characters[target_id] as Dictionary).get("stats", {})
	if _gs.is_downed(target_id) or bool(target_stats.get("dead", false)):
		return "dead"
	if _gs.has_method("is_narratively_available") \
			and not bool(_gs.is_narratively_available(target_id)):
		return "unavailable"
	return "available"


func _resolved_enemy(target_id: String):
	if not _enemy_resolver.is_valid():
		return null
	var enemy_node = _enemy_resolver.call(target_id)
	return enemy_node if enemy_node != null and is_instance_valid(enemy_node) else null


func _receipt_matches_accepted_source(receipt: Dictionary) -> bool:
	if _gs == null or _gs.scheduler == null \
			or int(receipt.get("version", 0)) != 1 \
			or int(receipt.get("dispatch_serial", -1)) != _trigger_dispatch_serial \
			or int(receipt.get("nonce", 0)) <= 0 \
			or str(receipt.get("source_id", "")) != _source_interactable_id() \
			or str(receipt.get("source_key", "")) != authority_state_key() \
			or str(receipt.get("phase", "")) != "source_reserved":
		return false
	var actor := str(receipt.get("actor", ""))
	if not _actor_ready_at_source(actor):
		return false
	if absf(float(receipt.get("accepted_tick", -INF)) - _scheduler_tick()) \
			> SOURCE_RECEIPT_TICK_EPSILON:
		return false
	if _gs.get_position(actor).distance_to(
			_v3_from_value(receipt.get("actor_position", []))
		) > SOURCE_RECEIPT_POSITION_EPSILON:
		return false
	return _source_receipt_was_accepted(receipt)


func _source_receipt_was_accepted(receipt: Dictionary) -> bool:
	if _gs == null or not _gs.has_interactable(_source_interactable_id()):
		return false
	var spec: Dictionary = _gs.get_interactable(_source_interactable_id())
	return int(spec.get("trigger_count", 0)) \
			== int(receipt.get("expected_trigger_count", -1)) \
		and str(spec.get("last_trigger_character", "")) \
			== str(receipt.get("actor", ""))


func _actor_ready_at_source(actor: String) -> bool:
	if actor.is_empty() or _gs == null or not _gs.characters.has(actor):
		return false
	if _gs.has_method("is_narratively_available") \
			and not bool(_gs.is_narratively_available(actor)):
		return false
	if _gs.is_downed(actor) or _actor_busy(actor):
		return false
	var actor_stats: Dictionary = (_gs.characters[actor] as Dictionary).get("stats", {})
	if bool(actor_stats.get("dead", false)) or float(actor_stats.get("hp", 1.0)) <= 0.0:
		return false
	var actor_position: Vector3 = _gs.get_position(actor)
	var source_position: Vector3 = _source_data_position()
	var planar: float = Vector2(actor_position.x, actor_position.z).distance_to(
		Vector2(source_position.x, source_position.z))
	# The interaction walk stops at the target's RING EDGE and parks on a grid
	# cell, so a legitimate click-arrival lands up to ~a cell diagonal beyond
	# interaction_radius. The anti-remote-firing law survives (the actor still
	# stands AT the flure); demanding the radius exactly refused every real
	# click-walk arrival (the wash_ascent player-contract catch).
	return planar <= interaction_radius + SOURCE_ARRIVAL_SLACK + SOURCE_POSITION_EPSILON \
		and absf(actor_position.y - source_position.y) \
			<= maxf(1.5, interaction_radius + SOURCE_POSITION_EPSILON)


func _actor_busy(actor: String) -> bool:
	for method_name in [
		"is_moving", "is_resting", "is_dodging", "is_endocytosing",
		"is_external_traversal_active", "is_dragging", "is_field_restoring",
		"is_knocked_down",
	]:
		if _gs.has_method(method_name) and bool(_gs.call(method_name, actor)):
			return true
	return false


func _source_data_position() -> Vector3:
	return _authored_origin


func _settle_data_position() -> Vector3:
	return settle_pos if settle_pos != Vector3.INF else _source_data_position()


func _target_settle_position(target_id: String) -> Vector3:
	var override_v: Variant = _target_settle_overrides.get(target_id, null)
	return override_v as Vector3 if override_v is Vector3 else _settle_data_position()


func _settle_override_data() -> Dictionary:
	var out := {}
	for target_id_v in _target_settle_overrides:
		var target_id := str(target_id_v)
		var position_v: Variant = _target_settle_overrides[target_id_v]
		if position_v is Vector3:
			out[target_id] = _v3_to_value(position_v)
	return out


func _restore_settle_overrides(value: Variant) -> void:
	if not (value is Dictionary):
		return
	_target_settle_overrides.clear()
	for target_id_v in (value as Dictionary):
		var target_id := str(target_id_v)
		var position := _v3_from_value((value as Dictionary)[target_id_v])
		if not target_id.is_empty() and position.is_finite():
			_target_settle_overrides[target_id] = position


func _source_interactable_id() -> String:
	var resolved := _resolved_authority_id
	if resolved.is_empty():
		resolved = _resolve_authority_id(_authored_origin)
	return "flure:%s" % resolved if not resolved.is_empty() else ""


func get_source_interactable_id() -> String:
	return _source_interactable_id()


func get_source_data_position() -> Vector3:
	return _source_data_position()


func _source_registry_enabled() -> bool:
	return _gs != null and _gs.has_interactable(_source_interactable_id()) \
		and _gs.is_interactable_enabled(_source_interactable_id())


func _source_trigger_count() -> int:
	if _gs == null or not _gs.has_interactable(_source_interactable_id()):
		return 0
	return int(_gs.get_interactable(_source_interactable_id()).get("trigger_count", 0))


func _clear_pending_source_authority() -> void:
	var saved := get_authority_state()
	if saved.is_empty() or (saved.get("pending_source_receipt", {}) as Dictionary).is_empty():
		return
	saved["pending_source_receipt"] = {}
	_publish_authority(saved)

## Structured evidence for the most recent signal. Callers can distinguish range/model errors from
## timing errors without coupling themselves to Enemy's internal state names.
func get_last_activation_report() -> Dictionary:
	return _last_activation_report.duplicate(true)

## The loader hands the flure a way to find the Enemy NODE behind a lure-target id, so an FSM enemy
## is lured through its own `lured` state (walk to settle, park distracted, walk home) instead of a
## raw data-layer move its state machine would fight.
func set_enemy_resolver(resolver: Callable) -> void:
	_enemy_resolver = resolver


## Optional stable per-target park points. This preserves a relay's visible fan formation without
## reimplementing the lure consequence in its chunk script.
func set_target_settle_positions(overrides: Dictionary) -> void:
	if _configured and str(_authority_or_default().get("phase", PHASE_READY)) != PHASE_READY:
		return
	_target_settle_overrides.clear()
	for target_v in overrides:
		var target_id := str(target_v)
		var position_v: Variant = overrides[target_v]
		if not target_id.is_empty() and position_v is Vector3:
			_target_settle_overrides[target_id] = position_v
	if _configured:
		var saved := _authority_or_default()
		saved["target_settle_positions"] = _settle_override_data()
		_publish_authority(saved)


func is_active() -> bool:
	return _active

func reset_flure() -> void:
	_ensure_authority_record()
	var previous := _authority_or_default()
	_release_fallback_targets(previous)
	_rearm_source_registry()
	var reset_record := _configured_record()
	# Reset clears the window, not its history. Repeated sources require a monotonic nonce/serial so
	# two retries at the same scheduler tick can never alias in observers or save reconciliation.
	reset_record["next_receipt_nonce"] = int(previous.get("next_receipt_nonce", 0))
	reset_record["activation_serial"] = int(previous.get("activation_serial", 0))
	reset_record["last_consumed_trigger_count"] = maxi(
		int(previous.get("last_consumed_trigger_count", 0)),
		_source_trigger_count())
	reset_record["last_trigger_character"] = str(
		previous.get("last_trigger_character", ""))
	_publish_authority(reset_record)
	_cancel_window_callback()


## Stable GameState namespace for the flower's commitment window.
func authority_state_key() -> String:
	var resolved := _resolved_authority_id
	if resolved.is_empty():
		resolved = authority_id.strip_edges()
	if resolved.is_empty():
		resolved = str(name).strip_edges()
	if resolved.is_empty():
		resolved = "unconfigured"
	return "gameplay:flure:%s" % resolved


func get_authority_state() -> Dictionary:
	if _gs == null or not _gs.has_method("get_world_state"):
		return {}
	var value: Variant = _gs.get_world_state(authority_state_key(), {})
	if not (value is Dictionary):
		return {}
	var saved := (value as Dictionary).duplicate(true)
	if str(saved.get("authority_id", "")) != _resolved_authority_id:
		return {}
	var contract := str(saved.get("contract", ""))
	if contract == STATE_CONTRACT:
		return _normalize_v2_record(saved)
	if contract == LEGACY_STATE_CONTRACT:
		return _migrate_v1_record(saved)
	return {}


## Readable state for tests, replay explanation, and hover feedback. The record names the exact
## effect targets rather than forcing a presenter to infer them from where actors happen to be now.
func get_effect_state() -> Dictionary:
	var saved := _authority_or_default()
	var now := _scheduler_tick()
	saved["remaining"] = maxf(0.0, float(saved.get("end_tick", -1.0)) - now) \
		if str(saved.get("phase", PHASE_READY)) in [PHASE_APPLYING, PHASE_ACTIVE] else 0.0
	return saved


## TutorialSequence invokes this after clearing opaque scheduler Callables and restoring GameState.
## The base interactable reattaches any in-flight dwell first; the flower then derives its visible
## charge and its one remaining deadline from world truth.
func on_game_state_snapshot_restored() -> void:
	# restore_one_shot_presenter() leaves an owner projection cached in Interactable. That projection
	# belongs to the discarded timeline: if a spent future is rolled back to READY, the base restore
	# must first mirror the restored registry instead of writing the stale "disabled" override back
	# over it. This Flure re-establishes its current projection from its own authority immediately
	# after the generic restore.
	_owner_used_override = null
	_owner_enabled_override = null
	super.on_game_state_snapshot_restored()
	_restore_authoritative_runtime()


func _configured_record() -> Dictionary:
	var settle := settle_pos if settle_pos != Vector3.INF else _authored_origin
	return {
		"contract": STATE_CONTRACT,
		"authority_id": _resolved_authority_id,
		"phase": PHASE_READY,
		"start_tick": -1.0,
		"end_tick": -1.0,
		"rearms": not one_shot,
		"one_shot": one_shot,
		"lure_duration": lure_duration,
		"attract_range": attract_range,
		"window_anchor_mode": window_anchor_mode,
		"settle_hold_duration": settle_hold_duration,
		"window_anchor": "activation",
		"settled_tick": -1.0,
		"settle_retime_receipts": {},
		"deferred_claim_serial": 0,
		"allow_deferred_targets": allow_deferred_targets,
		"target_settle_positions": _settle_override_data(),
		"effect_origin": _v3_to_value(_authored_origin),
		"settle_position": _v3_to_value(settle),
		"linked_target_ids": _lure_target_ids.duplicate(),
		"next_receipt_nonce": 0,
		"pending_source_receipt": {},
		"activation_receipt": {},
		"activation_serial": 0,
		"last_consumed_trigger_count": 0,
		"last_trigger_character": "",
		"target_plan": [],
		"target_receipts": {},
		"last_activation_report": {},
		"last_effect": {},
	}


func _normalize_v2_record(saved: Dictionary) -> Dictionary:
	var normalized := _configured_record()
	for key in saved:
		normalized[key] = saved[key]
	normalized["contract"] = STATE_CONTRACT
	normalized["authority_id"] = _resolved_authority_id
	return normalized


func _migrate_v1_record(saved: Dictionary) -> Dictionary:
	var migrated := _configured_record()
	for key in [
		"phase", "start_tick", "end_tick", "rearms", "one_shot", "lure_duration",
		"attract_range", "effect_origin", "settle_position", "linked_target_ids",
		"last_activation_report", "last_effect",
	]:
		if saved.has(key):
			migrated[key] = saved[key]
	var effect: Dictionary = migrated.get("last_effect", {})
	var pulled_ids: Array = effect.get("pulled_ids", [])
	var plan: Array = []
	var receipts := {}
	for index in range((migrated.get("linked_target_ids", []) as Array).size()):
		var target_id := str((migrated.get("linked_target_ids", []) as Array)[index])
		var applied := pulled_ids.has(target_id)
		plan.append({
			"target_id": target_id,
			"order": index,
			"mode": "fallback" if (effect.get("fallback_ids", []) as Array).has(target_id) \
				else "enemy",
			"eligible": applied,
			"reason": "" if applied else "legacy_unavailable",
			"source_position": migrated.get("effect_origin", _v3_to_value(_authored_origin)),
			"settle_position": migrated.get("settle_position", _v3_to_value(_authored_origin)),
			"duration": float(migrated.get("lure_duration", lure_duration)),
		})
		receipts[target_id] = {
			"status": "applied" if applied else "skipped",
			"mode": str((plan[plan.size() - 1] as Dictionary).get("mode", "enemy")),
			"applied_tick": float(migrated.get("start_tick", -1.0)) if applied else -1.0,
		}
	migrated["target_plan"] = plan
	migrated["target_receipts"] = receipts
	return migrated


func _authority_or_default() -> Dictionary:
	var saved := get_authority_state()
	return _configured_record() if saved.is_empty() else saved


func _ensure_authority_record() -> void:
	if not _configured or _gs == null or not get_authority_state().is_empty():
		return
	_publish_authority(_configured_record())


func _publish_authority(saved: Dictionary) -> void:
	if _restoring_authority or _gs == null or not _gs.has_method("set_world_state"):
		return
	var normalized := _normalize_v2_record(saved)
	_gs.set_world_state(authority_state_key(), normalized.duplicate(true))
	_mirror_runtime_state(normalized)


func _restore_authoritative_runtime(allow_due_transition := true) -> void:
	if not _configured:
		return
	_cancel_window_callback()
	_ensure_bound_source()
	_ensure_authority_record()
	var saved := _authority_or_default()
	saved = _reconcile_source_receipt_on_restore(saved)
	var phase := str(saved.get("phase", PHASE_READY))
	var deadline := float(saved.get("end_tick", -1.0))
	if allow_due_transition and phase == PHASE_ACTIVE and deadline >= 0.0 \
			and deadline <= _scheduler_tick() + 0.000001:
		_finish_window(deadline)
		return

	_restoring_authority = true
	lure_duration = float(saved.get("lure_duration", lure_duration))
	attract_range = float(saved.get("attract_range", attract_range))
	window_anchor_mode = str(saved.get("window_anchor_mode", window_anchor_mode))
	if window_anchor_mode not in [
		WINDOW_ANCHOR_ACTIVATION, WINDOW_ANCHOR_ALL_TARGETS_SETTLED,
	]:
		window_anchor_mode = WINDOW_ANCHOR_ACTIVATION
	settle_hold_duration = float(saved.get("settle_hold_duration", settle_hold_duration))
	allow_deferred_targets = bool(saved.get("allow_deferred_targets", allow_deferred_targets))
	_restore_settle_overrides(saved.get("target_settle_positions", {}))
	_lure_target_ids = (saved.get("linked_target_ids", _lure_target_ids) as Array).duplicate()
	settle_pos = _v3_from_value(saved.get("settle_position", settle_pos))
	_mirror_runtime_state(saved)
	_restoring_authority = false
	if phase == PHASE_APPLYING:
		_reconcile_applying_receipts_without_effects()
		saved = _authority_or_default()
		if str(saved.get("phase", "")) == PHASE_APPLYING:
			_arm_apply_resume()
	else:
		if phase == PHASE_ACTIVE \
				and str(saved.get("window_anchor", "")) == "settling":
			_resume_settle_retime(false)
			saved = _authority_or_default()
		elif phase == PHASE_ACTIVE \
				and str(saved.get("window_anchor", "")) == "transit":
			_reconcile_target_settlements(false)
			saved = _authority_or_default()
		_arm_window_callback(saved)


func _reconcile_source_receipt_on_restore(saved: Dictionary) -> Dictionary:
	var pending_v: Variant = saved.get("pending_source_receipt", {})
	if not (pending_v is Dictionary) or (pending_v as Dictionary).is_empty():
		return saved
	var pending := pending_v as Dictionary
	var accepted := _source_receipt_was_accepted(pending)
	if accepted:
		saved["last_consumed_trigger_count"] = maxi(
			int(saved.get("last_consumed_trigger_count", 0)),
			int(pending.get("expected_trigger_count", 0)))
		saved["last_trigger_character"] = str(pending.get("actor", ""))
		# The snapshot caught GameState's accepted-trigger signal before this owner created any
		# target transaction. Consume that orphan receipt, rearm the physical source, and grant no
		# lure. Repeatable trigger_count remains monotonic; one-shots clear only their spent latch.
		_rearm_source_registry()
	saved["pending_source_receipt"] = {}
	_pending_source_receipt.clear()
	_publish_authority(saved)
	return _authority_or_default()


func _reconcile_applying_receipts_without_effects() -> void:
	var saved := _authority_or_default()
	if str(saved.get("phase", "")) != PHASE_APPLYING:
		return
	var plan: Array = saved.get("target_plan", [])
	var receipts: Dictionary = (
		saved.get("target_receipts", {}) as Dictionary
	).duplicate(true)
	var changed := false
	for entry_v in plan:
		var entry := entry_v as Dictionary
		var target_id := str(entry.get("target_id", ""))
		var receipt: Dictionary = (
			receipts.get(target_id, {}) as Dictionary
		).duplicate(true)
		if str(receipt.get("status", "")) == "applying" \
				and _target_effect_matches_plan(entry):
			receipt["status"] = "applied"
			receipt["applied_tick"] = _scheduler_tick()
			receipts[target_id] = receipt
			changed = true
	if changed:
		saved["target_receipts"] = receipts
		_sync_effect_receipts(saved)
		_publish_authority(saved)
	var all_paid := true
	for entry_v in plan:
		var entry := entry_v as Dictionary
		if not bool(entry.get("eligible", false)):
			continue
		var status := str((receipts.get(
			str(entry.get("target_id", "")), {}) as Dictionary).get("status", "reserved"))
		if status not in ["applied", "failed"]:
			all_paid = false
			break
	if all_paid:
		_finalize_activation_transaction(false)


func _arm_apply_resume() -> void:
	if _gs == null or _gs.scheduler == null:
		return
	_gs.scheduler.cancel_tag(_apply_resume_tag())
	_gs.scheduler.schedule_at(
		_scheduler_tick() + RESTORE_RESUME_EPSILON,
		_resume_target_plan.bind(true),
		_apply_resume_tag())


func _arm_window_callback(saved: Dictionary) -> void:
	if _gs == null or _gs.scheduler == null:
		return
	_gs.scheduler.cancel_tag(_window_tag())
	if str(saved.get("phase", "")) != PHASE_ACTIVE:
		return
	var deadline := float(saved.get("end_tick", -1.0))
	if deadline < 0.0:
		return
	_gs.scheduler.schedule_at(
		maxf(deadline, _scheduler_tick() + RESTORE_RESUME_EPSILON),
		_finish_window.bind(deadline),
		_window_tag())


func _mirror_runtime_state(saved: Dictionary) -> void:
	var phase := str(saved.get("phase", PHASE_READY))
	var deadline := float(saved.get("end_tick", -1.0))
	_active_until_tick = deadline if phase == PHASE_ACTIVE else -1.0
	_active = phase in [PHASE_APPLYING, PHASE_ACTIVE]
	_last_activation_report = (
		saved.get("last_activation_report", {}) as Dictionary
	).duplicate(true)
	_apply_runtime_surface(saved)


func _rearm_source_registry() -> void:
	if _gs != null and _gs.has_interactable(_source_interactable_id()):
		var spec: Dictionary = _gs.get_interactable(_source_interactable_id())
		if bool(spec.get("triggered", false)) \
				or not bool(spec.get("enabled", true)):
			_gs.reset_interactable(_source_interactable_id())
	if one_shot:
		restore_one_shot_presenter(false, true)


func _finish_window(expected_deadline: float) -> void:
	var saved := get_authority_state()
	if str(saved.get("phase", "")) != PHASE_ACTIVE \
			or not is_equal_approx(float(saved.get("end_tick", -1.0)), expected_deadline):
		return
	_release_fallback_targets(saved)
	saved["phase"] = PHASE_READY if bool(saved.get("rearms", false)) else PHASE_SPENT
	saved["end_tick"] = -1.0
	_publish_authority(saved)


func _release_fallback_targets(saved: Dictionary) -> void:
	if _gs == null:
		return
	var effect: Dictionary = saved.get("last_effect", {}) as Dictionary
	for id_variant in (effect.get("fallback_ids", []) as Array):
		var id := str(id_variant)
		if _gs.characters.has(id):
			_gs.set_character_distracted(id, false)


func _apply_runtime_surface(saved: Dictionary) -> void:
	var phase := str(saved.get("phase", PHASE_READY))
	if _glow_mat != null:
		match phase:
			PHASE_APPLYING, PHASE_ACTIVE:
				_glow_mat.emission_energy_multiplier = 3.0
			PHASE_SPENT:
				_glow_mat.emission_energy_multiplier = 0.12
			_:
				_glow_mat.emission_energy_multiplier = 0.5
	_play_phase_clip(phase)
	# Registry truth owns enablement. In particular, READY does not override a scenario that has
	# deliberately disabled a future-stage flower.
	if one_shot:
		var source_enabled := _source_registry_enabled() if _gs != null else interaction_enabled
		restore_one_shot_presenter(
			phase != PHASE_READY,
			source_enabled and phase == PHASE_READY)


func _cancel_window_callback() -> void:
	if _gs != null and _gs.scheduler != null:
		_gs.scheduler.cancel_tag(_window_tag())
		_gs.scheduler.cancel_tag(_apply_resume_tag())
	_active_until_tick = -1.0


func _window_tag() -> String:
	return "flure_window_%s" % str(absi(authority_state_key().hash()))


func _apply_resume_tag() -> String:
	return "flure_apply_resume_%s" % str(absi(authority_state_key().hash()))


func _scheduler_tick() -> float:
	return float(_gs.scheduler.get_current_tick()) \
		if _gs != null and _gs.scheduler != null else 0.0


func _resolve_authority_id(origin: Vector3) -> String:
	var explicit := authority_id.strip_edges()
	if not explicit.is_empty():
		return explicit
	var node_id := str(name).strip_edges()
	if node_id.is_empty():
		node_id = "flure"
	return "%s@%s" % [node_id, _vector_signature(origin)]


func _vector_signature(value: Vector3) -> String:
	return "%.3f,%.3f,%.3f" % [value.x, value.y, value.z]


func _v3_to_value(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _v3_from_value(value: Variant) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array and (value as Array).size() >= 3:
		return Vector3(
			float((value as Array)[0]),
			float((value as Array)[1]),
			float((value as Array)[2])
		)
	return Vector3.INF


func _exit_tree() -> void:
	_cancel_window_callback()
	if _gs != null and _gs.has_signal("character_arrived") \
			and _gs.character_arrived.is_connected(_on_lure_target_arrived):
		_gs.character_arrived.disconnect(_on_lure_target_arrived)


## Play the transition a phase names, once per arrival at that phase.
##
## Cosmetic only: the registry owns the phase and the scheduler owns when it
## commits, so nothing waits on the clip and the lure works whether or not the
## petals have finished folding.
func _play_phase_clip(phase: String) -> void:
	if _rig == null or not is_instance_valid(_rig) or phase == _played_phase:
		return
	_played_phase = phase
	match phase:
		PHASE_SPENT:
			_rig.play("flure_spend")
		PHASE_READY:
			# Re-arming is not tending. The body is modelled ready, so it goes
			# straight back to that without playing the tending — which would
			# otherwise fire the completion flare for work nobody did.
			_rig.rest()
