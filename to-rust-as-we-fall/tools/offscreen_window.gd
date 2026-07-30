class_name OffscreenWindow
## Parks a window FULLY outside the virtual desktop for capture/recording
## runs. `--position 20000,20000` is clamped against the virtual desktop at
## window creation, and on a wide (or multi-monitor) desktop the clamp leaves
## a sliver of the game visible on screen. Runtime repositioning is not
## clamped, and the desktop's VERTICAL extent is small on any monitor
## arrangement — so the reliable spot is just below the bottom edge.
## The move goes through DisplayServer directly: the Window.position setter
## clamps back onto the visible desktop (measured — a request for y 1680 on a
## 1440-tall desktop read back as re-centred), while the raw DisplayServer
## call places the window truly off-screen and sticks.
static func park(window: Window) -> void:
	var union := Rect2i(DisplayServer.screen_get_position(0),
		DisplayServer.screen_get_size(0))
	for i in range(1, DisplayServer.get_screen_count()):
		union = union.merge(Rect2i(DisplayServer.screen_get_position(i),
			DisplayServer.screen_get_size(i)))
	DisplayServer.window_set_position(
		Vector2i(union.position.x, union.end.y + 240), window.get_window_id())
