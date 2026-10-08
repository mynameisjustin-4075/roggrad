class_name Bullet
extends Node2D
## A player or enemy projectile. Collision is checked by the game, not physics.
## Player kinds: "pellet", "lance" (ice), "missile", "charge", "ice_bomb".

const MISSILE_TOP_SPEED := 420.0
const MISSILE_ACCEL := 600.0

var kind := "pellet"
var vel := Vector2.ZERO
var radius := 2.0
var damage := 1.0
var owner_run: PlayerRun = null
var color := Color.WHITE
var enemy_bullet := false
var explode_radius := 0.0
var pierce_left := 0
var hit_list: Array = []
## Ice Blast bomb: seconds until it bursts on its own, and how long it freezes.
var fuse := 0.0
var fuse_done := false
var freeze_time := 0.0


func _physics_process(delta: float) -> void:
	if kind == "missile":
		vel = vel.move_toward(vel.normalized() * MISSILE_TOP_SPEED, MISSILE_ACCEL * delta)
	if fuse > 0.0:
		fuse -= delta
		if fuse <= 0.0:
			fuse_done = true
	position += vel * delta
	if kind == "ice_bomb":
		rotation += 8.0 * delta
	if position.x < -16 or position.x > 496 or position.y < -16 or position.y > 286:
		queue_free()
	if kind == "missile":
		queue_redraw()


func _draw() -> void:
	if enemy_bullet:
		draw_circle(Vector2.ZERO, radius, color)
		draw_circle(Vector2.ZERO, radius * 0.5, Color.WHITE)
		return
	match kind:
		"ice_bomb":
			draw_colored_polygon(PackedVector2Array([Vector2(5, 0), Vector2(0, -5), Vector2(-5, 0), Vector2(0, 5)]), Color(0.6, 0.9, 1.0))
			draw_rect(Rect2(-1.5, -1.5, 3, 3), Color.WHITE)
		"lance":
			draw_colored_polygon(PackedVector2Array([Vector2(6, 0), Vector2(0, -2.5), Vector2(-6, 0), Vector2(0, 2.5)]), Color(0.6, 0.9, 1.0))
			draw_line(Vector2(-4, 0), Vector2(5, 0), Color.WHITE, 1.0)
		"missile":
			draw_rect(Rect2(-4, -1.5, 8, 3), Color(1, 0.6, 0.2))
			draw_rect(Rect2(-6 - randf() * 2.0, -0.5, 2, 1), Color(1, 0.9, 0.4))
		"charge":
			draw_circle(Vector2.ZERO, radius, Color(1, 1, 1, 0.9))
			draw_circle(Vector2.ZERO, radius * 0.6, color)
		_:
			draw_rect(Rect2(-3, -1, 6, 2), color)
