class_name Decoy
extends Node2D
## Swarm's Decoy dodge: a flickering ghost of the ship that enemies aim at
## until it expires, then `on_expire` runs (the explosion).

var life := 2.0
var color := Color.WHITE
var on_expire: Callable


func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		if on_expire.is_valid():
			on_expire.call()
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	# Blinks faster as it is about to go off.
	var blink := 0.35 + 0.35 * sin(Time.get_ticks_msec() * 0.001 * (8.0 if life > 0.6 else 24.0))
	var c := Color(color, blink)
	draw_polyline(PackedVector2Array([Vector2(10, 0), Vector2(-7, -6), Vector2(-3, 0), Vector2(-7, 6), Vector2(10, 0)]), c, 1.0)
	draw_circle(Vector2.ZERO, 2.0, Color(1, 1, 1, blink))
