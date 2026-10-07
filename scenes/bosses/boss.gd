class_name Boss
extends Enemy
## Placeholder World 1 boss. Phase 1: aimed 3-way bursts. Below half HP it adds
## rotating rings. In co-op only its HP scales.

const BASE_HP := 300.0

var phase := 1
var ring_timer := 2.0


func setup_boss(hp_mult: float) -> void:
	kind = "boss"
	max_hp = BASE_HP * hp_mult
	hp = max_hp
	radius = 22.0
	color = Color(0.75, 0.7, 0.6)
	scrap = 50
	fire_interval = 1.1
	fire_timer = 2.0


func _move(delta: float) -> void:
	if position.x > 400.0:
		position.x -= 40.0 * delta
	else:
		position.y = 135.0 + sin(t * 0.7) * 80.0


func _update_fire(delta: float) -> void:
	if position.x > 410.0:
		return
	phase = 2 if hp < max_hp * 0.5 else 1
	fire_timer -= delta
	if fire_timer <= 0.0:
		fire_timer = fire_interval * (0.8 if phase == 2 else 1.0)
		var p = game.nearest_player(position)
		if p:
			var dir: Vector2 = (p.position - position).normalized()
			for a in [-0.25, 0.0, 0.25]:
				game.spawn_enemy_bullet(position + Vector2(-20, 0), dir.rotated(a) * 100.0)
	if phase == 2:
		ring_timer -= delta
		if ring_timer <= 0.0:
			ring_timer = 1.8
			for i in 14:
				game.spawn_enemy_bullet(position, Vector2.from_angle(TAU * i / 14.0 + t) * 70.0)


func _draw() -> void:
	var c := Color.WHITE if flash > 0.0 else color
	var hull := PackedVector2Array()
	for i in 6:
		hull.append(Vector2.from_angle(TAU * i / 6.0) * radius)
	draw_colored_polygon(hull, c)
	draw_rect(Rect2(-30, -4, 10, 8), c.darkened(0.3))
	var pulse := 0.5 + 0.5 * sin(t * (6.0 if phase == 2 else 3.0))
	draw_circle(Vector2.ZERO, 7.0, Color(1.0, 0.2 + 0.3 * pulse, 0.2))
	_draw_status()
