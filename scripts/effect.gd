class_name Effect
extends Node2D
## Short-lived visual: an expanding ring (explosion) or a lightning line (arc).

var kind := "explosion"
var life := 0.3
var max_life := 0.3
var radius := 10.0
var color := Color.WHITE
var target := Vector2.ZERO


func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var k := clampf(life / max_life, 0.0, 1.0)
	var c := Color(color, k)
	match kind:
		"explosion":
			draw_arc(Vector2.ZERO, radius * (1.0 - k * 0.7), 0.0, TAU, 16, c, 1.0)
			if k > 0.6:
				draw_circle(Vector2.ZERO, radius * 0.4 * k, Color(1, 1, 0.8, k))
		"arc":
			var to := target - position
			var mid := to * 0.5 + to.orthogonal().normalized() * randf_range(-4.0, 4.0)
			draw_line(Vector2.ZERO, mid, c, 1.0)
			draw_line(mid, to, c, 1.0)
