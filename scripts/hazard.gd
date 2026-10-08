class_name Hazard
extends Node2D
## A lingering area that affects enemies inside it every `tick` seconds:
## a rectangle (`rect`, local) or a circle (`radius`). `on_tick` receives the
## enemies inside. Used by Napalm Line (fire strip) and Scorch Trail (patches).

var life := 4.0
var max_life := 4.0
var tick := 0.4
var rect := Rect2()
var radius := 0.0
var look := "napalm"  # "napalm" strip or "scorch" patch
var on_tick: Callable
var enemies_node: Node
var _tick_timer := 0.0


func contains(e: Node2D) -> bool:
	if radius > 0.0:
		return position.distance_to(e.position) <= radius + e.radius
	var r := Rect2(position + rect.position, rect.size).grow(e.radius)
	return r.has_point(e.position)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = tick
		var inside := enemies_node.get_children().filter(func(e): return not e.dead and contains(e))
		if not inside.is_empty() and on_tick.is_valid():
			on_tick.call(inside)
	queue_redraw()


func _draw() -> void:
	var fade := clampf(life / 0.5, 0.0, 1.0)  # fade out over the last half second
	if look == "napalm":
		# Flickering column of flame, acid-green at its core.
		draw_rect(rect, Color(1.0, 0.45, 0.1, 0.35 * fade))
		var step := 6.0
		var y := rect.position.y
		while y < rect.end.y:
			var w := rect.size.x * randf_range(0.3, 0.8)
			draw_rect(Rect2(-w / 2.0, y, w, step - 1.0), Color(1.0, randf_range(0.5, 0.8), 0.15, 0.6 * fade))
			y += step
		draw_rect(Rect2(-1.5, rect.position.y, 3.0, rect.size.y), Color(0.7, 1.0, 0.3, 0.5 * fade))
	else:
		var k := life / max_life
		draw_circle(Vector2.ZERO, radius * (0.6 + 0.4 * randf()), Color(1.0, 0.5, 0.1, 0.45 * fade))
		draw_circle(Vector2.ZERO, radius * 0.4, Color(0.7, 1.0, 0.3, 0.5 * k))
