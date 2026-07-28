extends SceneTree

## Production integration guard for the portable Scarpet and Hushbloom presenters.
## The catalog verifier owns portable-file/UV coverage; this guard proves that the
## reusable gameplay wrappers actually instance those assets without changing their
## concealment, collision, authority, or recharge behavior.

const Catalog := preload("res://scripts/game/objects/biota_placeholder_catalog.gd")
const ScarpetScript := preload("res://scripts/game/objects/scarpet.gd")
const HushbloomScript := preload("res://scripts/game/objects/hushbloom.gd")

const SCARPET_SOURCE := "res://scripts/game/objects/scarpet.gd"
const HUSHBLOOM_SOURCE := "res://scripts/game/objects/hushbloom.gd"
const GENERATED_STRETCH_SOURCE := "res://scripts/fragments/chunks/generated_stretch_chunk.gd"
const SCARPET_RADIUS := 1.65
const HUSH_ORIGIN := Vector3(7.0, 0.0, 3.0)

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_verify_production_source_boundary()
	await _verify_scarpet_presenter()
	await _verify_hushbloom_presenter_and_state()
	print("BIOTA GAMEPLAY PRESENTERS: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_production_source_boundary() -> void:
	var scarpet_source := FileAccess.get_file_as_string(SCARPET_SOURCE)
	var hushbloom_source := FileAccess.get_file_as_string(HUSHBLOOM_SOURCE)
	var generated_source := FileAccess.get_file_as_string(GENERATED_STRETCH_SOURCE)
	_check(scarpet_source.contains(
			"BiotaPlaceholderCatalogScript.instantiate(VISUAL_KEY)")
			and not scarpet_source.contains("BoxMesh.new()"),
		"production Scarpet wrapper instances its catalog visual instead of a unique box")
	_check(hushbloom_source.contains(
			"BiotaPlaceholderCatalogScript.instantiate(VISUAL_KEY)")
			and not hushbloom_source.contains("CylinderMesh.new()")
			and not hushbloom_source.contains("SphereMesh.new()"),
		"production Hushbloom wrapper instances its catalog visual instead of primitive stem/head")
	_check(generated_source.contains("var scarpet := Scarpet.new()")
			and generated_source.contains("var hushbloom := Hushbloom.new()"),
		"generated stretches reach the portable presenters through the reusable gameplay wrappers")
	_check(Catalog.has("flora/scarpet") and Catalog.has("flora/hushbloom"),
		"both production wrapper keys resolve through the bounded catalog")


func _verify_scarpet_presenter() -> void:
	var scarpet := ScarpetScript.new() as Scarpet
	scarpet.name = "VerifierScarpet"
	scarpet.configure(Vector3.ZERO, SCARPET_RADIUS, false)
	root.add_child(scarpet)
	var wide := ScarpetScript.new() as Scarpet
	wide.name = "VerifierWideScarpet"
	wide.configure(Vector3(10.0, 0.0, 0.0), SCARPET_RADIUS * 2.0, false)
	root.add_child(wide)
	await process_frame

	var presenter := scarpet.get_visual_presenter()
	var body := presenter.get_node_or_null("Body") as MeshInstance3D \
		if presenter != null else null
	var body_material := body.material_override as StandardMaterial3D \
		if body != null else null
	_check(presenter != null
			and str(presenter.get_meta("visual_identity", "")) == "placeholder_scarpet_v1"
			and str(presenter.get_meta("gameplay_visual_key", "")) == "flora/scarpet",
		"Scarpet exposes the catalog identity from inside its production gameplay wrapper")
	_check(body != null and body.mesh is ArrayMesh,
		"Scarpet production body is the imported portable mesh")
	_check(body_material != null and body_material.albedo_texture != null,
		"Scarpet production body retains its external paint texture")
	_check(presenter != null
			and is_equal_approx(presenter.scale.x, 1.0)
			and is_equal_approx(presenter.scale.y, 1.0)
			and is_equal_approx(presenter.scale.z, 1.0),
		"default Scarpet keeps the authored world-scale silhouette")
	var wide_presenter := wide.get_visual_presenter()
	_check(wide_presenter != null
			and is_equal_approx(wide_presenter.scale.x, 2.0)
			and is_equal_approx(wide_presenter.scale.y, 1.0)
			and is_equal_approx(wide_presenter.scale.z, 2.0),
		"Scarpet scales only its XZ footprint with the configured concealment radius")
	_check(scarpet.conceals(Vector3(SCARPET_RADIUS - 0.01, 50.0, 0.0))
			and not scarpet.conceals(Vector3(SCARPET_RADIUS + 0.01, 0.0, 0.0)),
		"portable presentation leaves the canonical planar concealment predicate unchanged")

	scarpet.queue_free()
	wide.queue_free()
	await process_frame


func _verify_hushbloom_presenter_and_state() -> void:
	var scheduler := EventScheduler.new()
	var state := GameState.new()
	state.scheduler = scheduler
	state.event_log = EventLog.new()
	var first := _make_hushbloom(state, "presenter_first", HUSH_ORIGIN)
	var second := _make_hushbloom(
		state, "presenter_second", HUSH_ORIGIN + Vector3(4.0, 0.0, 0.0))
	root.add_child(first)
	root.add_child(second)
	await process_frame

	var first_presenter := first.get_visual_presenter()
	var first_body := first_presenter.get_node_or_null("Body") as MeshInstance3D \
		if first_presenter != null else null
	var first_signal := first_presenter.get_node_or_null("Signal") as MeshInstance3D \
		if first_presenter != null else null
	var second_presenter := second.get_visual_presenter()
	var second_signal := second_presenter.get_node_or_null("Signal") as MeshInstance3D \
		if second_presenter != null else null
	var first_material := first_signal.material_override as StandardMaterial3D \
		if first_signal != null else null
	var second_material := second_signal.material_override as StandardMaterial3D \
		if second_signal != null else null
	_check(first_presenter != null
			and str(first_presenter.get_meta("visual_identity", ""))
				== "placeholder_hushbloom_v1"
			and str(first_presenter.get_meta("gameplay_visual_key", ""))
				== "flora/hushbloom",
		"Hushbloom exposes the catalog identity from inside its production gameplay wrapper")
	_check(first_body != null and first_body.mesh is ArrayMesh
			and first_signal != null and first_signal.mesh is ArrayMesh,
		"Hushbloom production body and signal are imported portable mesh families")
	_check(first_material != null
			and first_material.albedo_texture != null
			and first_material.emission_texture != null,
		"Hushbloom state material retains the external signal paint texture")
	_check(first_material != null and second_material != null
			and first_material != second_material,
		"each Hushbloom owns an isolated signal material instance")
	var collision := first.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var sphere := collision.shape as SphereShape3D if collision != null else null
	_check(sphere != null and is_equal_approx(sphere.radius, first.interaction_radius),
		"portable presentation preserves the production interaction collision")
	_check(first_signal != null and first_material != null
			and first.is_charged() and first_signal.visible
			and first_material.emission_energy_multiplier > 0.0,
		"authoritative CHARGED state shows the luminous signal family")

	_check(first.burst("presenter_fixture"),
		"production Hushbloom still accepts its canonical proximity-burst consequence")
	_check(first_body != null and first_signal != null and first_material != null
			and not first.is_charged()
			and first.visible
			and first_body.visible
			and not first_signal.visible
			and is_zero_approx(first_material.emission_energy_multiplier),
		"spent/recharging authority leaves the body present and removes the charged signal")
	_check(second_signal != null and second_material != null
			and second.is_charged()
			and second_signal.visible
			and second_material.emission_energy_multiplier > 0.0,
		"one spent bloom cannot mutate another bloom's signal presentation")

	scheduler.advance_ticks(1.0)
	_check(first_signal != null and first_material != null
			and first.is_charged()
			and str(first.get_effect_state().get("phase", "")) == "charged"
			and first_signal.visible
			and first_material.emission_energy_multiplier > 0.0,
		"absolute recharge authority restores the same external signal family")

	scheduler.clear()
	first.queue_free()
	second.queue_free()
	await process_frame


func _make_hushbloom(state: GameState, authority_id: String, origin: Vector3) -> Hushbloom:
	var bloom := HushbloomScript.new() as Hushbloom
	bloom.name = "VerifierHushbloom_%s" % authority_id
	bloom.authority_id = authority_id
	bloom.configure(state, origin, {
		"trigger_radius": 1.5,
		"stun_radius": 3.4,
		"stun_secs": 6.0,
		"regen_secs": 1.0,
		"pickable": false,
	})
	return bloom


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		push_error("  FAIL: %s" % message)
