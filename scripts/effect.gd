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
			# Jagged bolt, re-rolled every frame so it crackles.
			var to := target - position
			var side := to.orthogonal().normalized()
			var segments := clampi(int(to.length() / 12.0), 3, 12)
			var points := PackedVector2Array([Vector2.ZERO])
			for i in range(1, segments):
				points.append(to * (float(i) / segments) + side * randf_range(-5.0, 5.0))
			points.append(to)
			draw_polyline(points, Color(c, k * 0.35), 3.0)
			draw_polyline(points, c, 1.0)
			draw_circle(to, 2.5 * k, Color(1, 1, 1, k))
