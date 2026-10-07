class_name Bullet
extends Node2D
## A player or enemy projectile. Collision is checked by the game, not physics.

var vel := Vector2.ZERO
var radius := 2.0
var damage := 1.0
var owner_run: PlayerRun = null
var color := Color.WHITE
var enemy_bullet := false
var missile := false
var explode_radius := 0.0
var pierce_left := 0
var hit_list: Array = []


func _physics_process(delta: float) -> void:
	position += vel * delta
	if position.x < -16 or position.x > 496 or position.y < -16 or position.y > 286:
		queue_free()


func _draw() -> void:
	if enemy_bullet:
		draw_circle(Vector2.ZERO, radius, color)
		draw_circle(Vector2.ZERO, radius * 0.5, Color.WHITE)
	elif missile:
		draw_rect(Rect2(-4, -1.5, 8, 3), Color(1, 0.6, 0.2))
		draw_rect(Rect2(-6, -0.5, 2, 1), Color(1, 0.9, 0.4))
	elif radius > 2.5:
		draw_circle(Vector2.ZERO, radius, Color(1, 1, 1, 0.9))
		draw_circle(Vector2.ZERO, radius * 0.6, color)
	else:
		draw_rect(Rect2(-3, -1, 6, 2), color)
