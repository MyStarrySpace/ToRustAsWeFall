extends Control

## Cosmetic RTS selection rectangle. The SelectionController feeds it a screen-space rect while the
## player drags; we just draw it. Purely visual — never gates any game state, so it's display-only
## (headless tests drive the SelectionController math directly and never need this).

var _rect := Rect2()

func set_rect(r: Rect2) -> void:
	_rect = r
	queue_redraw()

func clear_rect() -> void:
	_rect = Rect2()
	queue_redraw()

func _draw() -> void:
	var r := _rect.abs()
	if r.size.x < 1.0 and r.size.y < 1.0:
		return
	draw_rect(r, Color(0.4, 0.85, 0.55, 0.12), true)
	draw_rect(r, Color(0.5, 0.95, 0.7, 0.9), false, 1.5)
