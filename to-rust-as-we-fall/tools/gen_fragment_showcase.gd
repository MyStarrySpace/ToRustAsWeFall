extends SceneTree

## One-off: build a demo Fragment exercising EVERY modular object type and save it as data so the data-driven
## loader (DataFragmentChunk) has a real .tres to consume. Run:
##   ../Godot_v4.7-stable_win64_console.exe --headless --path "." --script res://tools/gen_fragment_showcase.gd
## Re-run after changing the schema to regenerate data/fragments/object_showcase.tres.

func _init() -> void:
	var frag := Fragment.new()
	frag.id = "object_showcase"
	frag.title = "Object Showcase (data)"
	frag.help = "A data-driven fragment: floor, flure, portals, capbages, channels, flora light, and roamers — all from a .tres."
	frag.default_character = "peris"
	frag.party_ids = PackedStringArray(["aster", "peris", "endo"])
	frag.spawns = {
		"aster": Vector3(3.5, 0.5, 1.5),
		"peris": Vector3(2.5, 0.5, 0.5),
		"endo": Vector3(2.5, 0.5, -1.5),
	}
	frag.floors = [
		{"pos": Vector3(14.0, -0.05, 0.0), "size": Vector3(34.0, 0.1, 14.0), "color": Color(0.09, 0.1, 0.12)},
	]
	frag.walls = [
		{"pos": Vector3(14.0, 1.4, 7.2), "size": Vector3(34.0, 2.8, 0.3), "color": Color(0.06, 0.06, 0.08)},
		{"pos": Vector3(14.0, 1.4, -7.2), "size": Vector3(34.0, 2.8, 0.3), "color": Color(0.06, 0.06, 0.08)},
	]
	frag.lights = [
		{"pos": Vector3(8.0, 2.0, 0.0), "color": Color(0.5, 0.8, 1.0), "energy": 1.0, "range": 12.0},
	]
	frag.labels = [
		{"text": "OBJECT SHOWCASE", "pos": Vector3(8.0, 2.6, 0.0), "color": Color(0.7, 0.85, 0.95)},
	]
	frag.objects = [
		# The lure flower, pulling the two roamers.
		{"type": "flure", "name": "Flure", "pos": Vector3(6.5, 0.5, 0.5),
			"targets": ["show_guard_0", "show_guard_1"], "attract": 32.0, "radius": 1.6, "color": Color(0.95, 0.78, 0.2)},
		# A bidirectional portal pair across the channels.
		{"type": "portal_pad", "name": "PortalNear", "pos": Vector3(8.5, 0.5, -1.5), "dest": Vector3(21.5, 0.5, -1.5)},
		{"type": "portal_pad", "name": "PortalFar", "pos": Vector3(21.5, 0.5, -1.5), "dest": Vector3(8.5, 0.5, -1.5)},
		# Three tight-hide capbages on the near bank.
		{"type": "capbage", "name": "Capbage0", "pos": Vector3(2.5, 0.5, 3.5), "radius": 1.4},
		{"type": "capbage", "name": "Capbage1", "pos": Vector3(4.5, 0.5, -3.5), "radius": 1.4},
		{"type": "capbage", "name": "Capbage2", "pos": Vector3(7.5, 0.5, 3.5), "radius": 1.4},
		# Three phased flood channels (at least one always flooding).
		{"type": "channel", "name": "Channel0", "x": 11.0, "half": 1.25, "z_half": 5.0, "period": 3.0, "dur": 1.6, "phase": 0.0, "tag": "sc_ch0"},
		{"type": "channel", "name": "Channel1", "x": 13.5, "half": 1.25, "z_half": 5.0, "period": 3.0, "dur": 1.6, "phase": 1.0, "tag": "sc_ch1"},
		{"type": "channel", "name": "Channel2", "x": 16.0, "half": 1.25, "z_half": 5.0, "period": 3.0, "dur": 1.6, "phase": 2.0, "tag": "sc_ch2"},
		# A grown flora light (Peris's bloom).
		{"type": "flora_light", "name": "Bloom", "pos": Vector3(5.0, 0.0, -3.0),
			"opts": {"light_range": 4.0, "emission": Color(0.4, 1.0, 0.7)}},
		# Two roaming guards by the far exit.
		{"type": "enemy", "id": "show_guard_0", "pos": Vector3(23.5, 0.5, 2.5), "speed": 2.4, "detect": 4.0,
			"targets": ["aster", "peris", "endo"], "roam": {"radius": 3.0}},
		{"type": "enemy", "id": "show_guard_1", "pos": Vector3(24.5, 0.5, -1.5), "speed": 2.4, "detect": 4.0,
			"targets": ["aster", "peris", "endo"], "roam": {"radius": 3.0}},
		# The exit marker.
		{"type": "marker", "pos": Vector3(28.0, 0.5, 0.0), "size": Vector3(2.0, 0.4, 2.0), "color": Color(0.3, 0.7, 0.55), "label": "EXIT"},
	]
	frag.time_state = {"day": 2, "time": 0.6, "routing_mode": "safe", "note_default": "A data-driven fragment loaded from a .tres."}

	var path := "res://data/fragments/object_showcase.tres"
	var err := ResourceSaver.save(frag, path)
	if err == OK:
		print("[gen-fragment] saved %s (%d objects)" % [path, frag.objects.size()])
	else:
		print("[gen-fragment] FAILED to save %s (err %d)" % [path, err])
	quit()
