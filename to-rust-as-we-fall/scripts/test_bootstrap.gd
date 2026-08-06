extends Node

const WINDOWED_OFFSCREEN_ENV := "TRAWF_TEST_WINDOWED_OFFSCREEN"
const POINTER_INPUT_MODE_ENV := "TRAWF_TEST_POINTER_INPUT_MODE"
const WINDOW_HOST_MODE_ENV := "TRAWF_TEST_WINDOW_HOST_MODE"
const WINDOW_PARENT_ID_ENV := "TRAWF_TEST_WINDOW_PARENT_ID"
const APP_LOCAL_POINTER_INPUT_MODE := "app_local_events_v1"
const WINDOWS_HIDDEN_PARENT_MODE := "hidden_parent_v1"
const OFFSCREEN_GEOMETRY_MODE := "offscreen_geometry_v1"
const WINDOWED_CONTRACT_EXIT_CODE := 66

var _windowed_test_contract_active := false
var _windowed_contract_failed := false
var _root_window: Window
var _lifetime_repark_count := 0
var _window_host_mode := ""


func _enter_tree() -> void:
	# Detect testing from user arguments, never from an optional environment value.
	# On Windows the tracked launcher gives Godot a never-shown native owner using
	# --wid; this preserves a logically visible render surface and a real
	# swapchain without exposing it on the desktop. Other hosts use geometric
	# parking. A broken/direct Windows launch is immediately hidden, parked, and
	# terminated from this tree-entry hook before any test gameplay can begin.
	_windowed_test_contract_active = _is_test_invocation() \
		and DisplayServer.get_name() != "headless"
	if not _windowed_test_contract_active:
		return
	_root_window = get_tree().root
	_window_host_mode = OS.get_environment(WINDOW_HOST_MODE_ENV)
	_root_window.unfocusable = true
	# Validate every launch-time isolation/input token before allowing a logically
	# visible root. The native launcher is the pre-script exposure boundary; this
	# early guard ensures a malformed contract fails dark and requests exit here,
	# before _ready() can dispatch any test gameplay.
	var launch_failure := _windowed_launch_token_failure()
	if launch_failure != "":
		_root_window.visible = false
		OffscreenWindow.park(_root_window)
		push_error("Windowed test enter-tree launch contract failed: " + launch_failure)
		_fail_windowed_contract()
		return
	if _window_host_mode == OFFSCREEN_GEOMETRY_MODE:
		OffscreenWindow.park(_root_window)
	var surface_failure := _windowed_surface_contract_failure()
	if surface_failure != "":
		_root_window.visible = false
		OffscreenWindow.park(_root_window)
		push_error("Windowed test enter-tree surface contract failed: " + surface_failure)
		_fail_windowed_contract()
		return
	_root_window.visibility_changed.connect(_on_root_window_visibility_changed)
	_root_window.size_changed.connect(_on_root_window_size_changed)
	# Run after ordinary scene/autoload processing so a test cannot reposition or
	# fullscreen the window and quit successfully in the same rendered frame.
	process_priority = 1000000
	set_process(true)


## Explicit scene used by native test invocations. TestRunner is an autoload so
## a parser failure in test_runner_cli.gd prevents that node from being created.
## Without this independent scene Godot falls back to an idle main menu and the
## gate reports only a late timeout instead of the real compiler failure.
func _ready() -> void:
	if not _is_test_invocation():
		push_error("TestBootstrap may only be launched with a --test-* user argument.")
		get_tree().quit(64)
		return
	if not _validate_windowed_launch_contract():
		_fail_windowed_contract()
		return

	# Autoload construction happens before the main scene. Give TestRunner a few
	# frames to resume its awaited _ready, recognize the requested entry point,
	# and publish the claim before this independent watchdog decides startup failed.
	var runner: Node = null
	for _frame in range(3):
		await get_tree().process_frame
		runner = get_node_or_null("/root/TestRunner")
		if runner != null and runner.has_meta("test_invocation_claimed"):
			return
	if runner == null:
		push_error(
			"TestRunner autoload is unavailable. A script load/parse error occurred "
			+ "before the requested test could start."
		)
		get_tree().quit(2)
	else:
		push_error(
			"TestRunner exists but did not claim the requested test entry point. "
			+ "Its startup failed before dispatch."
		)
		get_tree().quit(65)


func _process(_delta: float) -> void:
	if not _windowed_test_contract_active or _windowed_contract_failed:
		return
	_enforce_window_isolation("process_frame")


func _on_root_window_visibility_changed() -> void:
	if not _windowed_test_contract_active or _windowed_contract_failed:
		return
	_enforce_window_isolation("visibility_changed")


func _on_root_window_size_changed() -> void:
	if not _windowed_test_contract_active or _windowed_contract_failed:
		return
	_enforce_window_isolation("size_changed")


func _enforce_window_isolation(source: String) -> void:
	if _root_window == null:
		push_error("Windowed test lost its root Window while enforcing desktop isolation.")
		_fail_windowed_contract()
		return
	if OS.get_name() == "Windows" and _window_host_mode == WINDOWS_HIDDEN_PARENT_MODE:
		# The launcher continuously proves native parentage, effective invisibility,
		# offscreen rectangles, top-level style, and foreground ownership. Keep the
		# Godot render surface logically visible so rendering and physics picking stay real.
		var surface_failure := _windowed_surface_contract_failure()
		if surface_failure != "":
			push_error(
				"Embedded Windowed test lost its native surface contract. "
				+ "source=%s reason=%s" % [source, surface_failure])
			_fail_windowed_contract()
			return
		# The native launcher owns the Windows topology/desktop checks. A valid
		# hidden-owner surface must not fall through into the geometric fallback.
		return
	if _window_host_mode == OFFSCREEN_GEOMETRY_MODE \
			and not _window_is_fully_offscreen():
		_lifetime_repark_count += 1
		OffscreenWindow.park(_root_window)
	if _window_host_mode != OFFSCREEN_GEOMETRY_MODE \
			or not _window_is_fully_offscreen():
		var virtual_desktop := _virtual_desktop_rect()
		var window_rect := _window_rect()
		push_error(
			"Windowed test could not preserve its desktop-isolation boundary. "
			+ "source=%s host_mode=%s visible=%s reparks=%d desktop=%s window=%s" % [
				source,
				_window_host_mode if _window_host_mode != "" else "<missing>",
				str(_root_window.visible),
				_lifetime_repark_count,
				str(virtual_desktop),
				str(window_rect),
			]
		)
		_fail_windowed_contract()


func _validate_windowed_launch_contract() -> bool:
	if not _windowed_test_contract_active:
		return true
	var launch_failure := _windowed_launch_token_failure()
	if launch_failure != "":
		push_error("Windowed test launch contract failed: " + launch_failure)
		return false
	var surface_failure := _windowed_surface_contract_failure()
	if surface_failure != "":
		push_error("Windowed test surface contract failed: " + surface_failure)
		return false
	_enforce_window_isolation("pre_first_frame")
	if _windowed_contract_failed:
		return false
	return true


func _windowed_launch_token_failure() -> String:
	var expected_position := OS.get_environment(WINDOWED_OFFSCREEN_ENV)
	if not _is_canonical_position_token(expected_position):
		return "missing or non-canonical process-start position token: %s" % (
			expected_position if expected_position != "" else "<missing>")
	var pointer_mode := OS.get_environment(POINTER_INPUT_MODE_ENV)
	if pointer_mode != APP_LOCAL_POINTER_INPUT_MODE:
		return "pointer mode must be %s, observed %s" % [
			APP_LOCAL_POINTER_INPUT_MODE,
			pointer_mode if pointer_mode != "" else "<missing>",
		]
	if OS.get_name() == "Windows":
		var parent_id := OS.get_environment(WINDOW_PARENT_ID_ENV)
		if _window_host_mode != WINDOWS_HIDDEN_PARENT_MODE:
			return "Windows host mode must be %s, observed %s" % [
				WINDOWS_HIDDEN_PARENT_MODE,
				_window_host_mode if _window_host_mode != "" else "<missing>",
			]
		if not _is_positive_decimal_handle(parent_id):
			return "Windows hidden-parent HWND token is missing or invalid: %s" % (
				parent_id if parent_id != "" else "<missing>")
		return ""
	if _window_host_mode != OFFSCREEN_GEOMETRY_MODE:
		return "non-Windows host mode must be %s, observed %s" % [
			OFFSCREEN_GEOMETRY_MODE,
			_window_host_mode if _window_host_mode != "" else "<missing>",
		]
	return ""


func _windowed_surface_contract_failure() -> String:
	if _root_window == null:
		return "root Window is unavailable"
	if not _root_window.visible:
		return "root Window is not logically visible"
	if not _window_is_fully_offscreen():
		return "window intersects the virtual desktop: desktop=%s window=%s" % [
			str(_virtual_desktop_rect()), str(_window_rect())]
	if OS.get_name() != "Windows":
		return ""
	var expected_position := _position_from_token(
		OS.get_environment(WINDOWED_OFFSCREEN_ENV))
	var actual_position := DisplayServer.window_get_position()
	if actual_position != expected_position:
		return "embedded startup position differs from launcher request: expected=%s actual=%s" % [
			str(expected_position), str(actual_position)]
	if DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE) == 0:
		return "embedded render HWND is unavailable"
	return ""


func _is_canonical_position_token(value: String) -> bool:
	var coordinates := value.split(",", false)
	return coordinates.size() == 2 \
		and coordinates[0] == coordinates[0].strip_edges() \
		and coordinates[1] == coordinates[1].strip_edges() \
		and coordinates[0].is_valid_int() \
		and coordinates[1].is_valid_int()


func _position_from_token(value: String) -> Vector2i:
	var coordinates := value.split(",", false)
	if coordinates.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(coordinates[0]), int(coordinates[1]))


func _is_positive_decimal_handle(value: String) -> bool:
	# HWND is pointer-sized. Validate the launcher's canonical decimal string
	# without converting it through GDScript's signed integer representation.
	if value == "" or value == "0":
		return false
	for index in range(value.length()):
		var codepoint := value.unicode_at(index)
		if codepoint < 48 or codepoint > 57:
			return false
	return true


func _is_test_invocation() -> bool:
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--test"):
			return true
	return false


func _window_rect() -> Rect2i:
	return Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())


func _window_is_fully_offscreen() -> bool:
	return not _rects_have_positive_area_intersection(
		_virtual_desktop_rect(), _window_rect())


func _rects_have_positive_area_intersection(first: Rect2i, second: Rect2i) -> bool:
	# Strict inequalities make even one pixel of positive overlap a violation;
	# rectangles that only touch at an edge remain non-intersecting.
	var first_end := first.position + first.size
	var second_end := second.position + second.size
	return first.position.x < second_end.x \
		and first_end.x > second.position.x \
		and first.position.y < second_end.y \
		and first_end.y > second.position.y


func _fail_windowed_contract() -> void:
	if _windowed_contract_failed:
		return
	_windowed_contract_failed = true
	get_tree().quit(WINDOWED_CONTRACT_EXIT_CODE)


func _virtual_desktop_rect() -> Rect2i:
	var desktop := Rect2i(
		DisplayServer.screen_get_position(0), DisplayServer.screen_get_size(0))
	for screen_index in range(1, DisplayServer.get_screen_count()):
		desktop = desktop.merge(Rect2i(
			DisplayServer.screen_get_position(screen_index),
			DisplayServer.screen_get_size(screen_index)))
	return desktop
