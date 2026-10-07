class_name Starfield
extends Node2D
## Placeholder 3-layer scrolling star background.

const LAYER_COLORS := [Color(0.3, 0.3, 0.45), Color(0.55, 0.55, 0.7), Color(0.9, 0.9, 1.0)]

var speed := 40.0
var _stars: Array = []


func _ready() -> void:
	for i in 90:
		_stars.append({"p": Vector2(randf() * 480.0, randf() * 270.0), "l": randi() % 3})


func _process(delta: float) -> void:
	for s in _stars:
		var p: Vector2 = s.p
		p.x -= speed * (0.3 + 0.5 * s.l) * delta
		if p.x < 0.0:
			p.x += 480.0
			p.y = randf() * 270.0
		s.p = p
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 480, 270), Color(0.04, 0.05, 0.1))
	for s in _stars:
		draw_rect(Rect2(s.p.floor(), Vector2.ONE), LAYER_COLORS[s.l])
