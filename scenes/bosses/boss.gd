class_name Boss
extends Enemy
## World 1 boss, the Salvage Leviathan (placeholder art). Fires aimed 3-way
## bursts and launches grunts from its hull. Below half HP it adds rotating
## rings, launches grunts faster and releases two beam drones. In co-op only
## its HP (and its drones' HP) scale.

const BASE_HP := 600.0
const RADIUS := 58.0
const PARK_X := 560.0  # where it stops after entering
const SWAY := 100.0  # vertical sway around mid-screen
const MINION_INTERVAL := 5.0
const MINION_INTERVAL_PHASE2 := 4.0
## Where the drones sit on the hull until released (top and bottom).
const DOCKS := [Vector2(-8, -RADIUS - 6), Vector2(-8, RADIUS + 6)]

var phase := 1
var ring_timer := 2.0
var minion_timer := 3.0
var drones_released := false
var hp_mult := 1.0


func setup_boss(p_hp_mult: float) -> void:
	kind = "boss"
	hp_mult = p_hp_mult
	max_hp = BASE_HP * hp_mult
	hp = max_hp
	radius = RADIUS
	color = Color(0.75, 0.7, 0.6)
	scrap = 50
	fire_interval = 1.1
	fire_timer = 2.0
	freeze_resist = 0.5
	max_freezes = 3  # 1.5 s, 1.0 s, 0.5 s, then immune for the fight


func _move(delta: float) -> void:
	if position.x > PARK_X:
		position.x -= 53.0 * delta
	else:
		position.y = 180.0 + sin(t * 0.7) * SWAY


func _update_fire(delta: float) -> void:
	if position.x > PARK_X + 14.0:
		return
	phase = 2 if hp < max_hp * 0.5 else 1
	if phase == 2 and not drones_released:
		_release_drones()
	fire_timer -= delta
	if fire_timer <= 0.0:
		fire_timer = fire_interval * (0.8 if phase == 2 else 1.0)
		var p = game.aim_target(position)
		if p:
			var dir: Vector2 = (p.position - position).normalized()
			for a in [-0.25, 0.0, 0.25]:
				game.spawn_enemy_bullet(position + Vector2(-RADIUS, 0), dir.rotated(a) * 133.0, self)
	if phase == 2:
		ring_timer -= delta
		if ring_timer <= 0.0:
			ring_timer = 1.8
			for i in 14:
				game.spawn_enemy_bullet(position, Vector2.from_angle(TAU * i / 14.0 + t) * 93.0, self)
	minion_timer -= delta
	if minion_timer <= 0.0:
		minion_timer = MINION_INTERVAL_PHASE2 if phase == 2 else MINION_INTERVAL
		# A pair of grunts launched from the hull's front, one high, one low.
		for side in [-1.0, 1.0]:
			game.spawn_minion("grunt", position + Vector2(-RADIUS * 0.6, side * RADIUS * 0.45), self)


func _release_drones() -> void:
	drones_released = true
	for i in DOCKS.size():
		var d := BossDrone.new()
		d.game = game
		d.setup_drone(i, hp_mult, self)
		d.position = position + DOCKS[i]
		game.enemies.add_child(d)
	game.shake = maxf(game.shake, 0.8)


func _draw() -> void:
	var c := Color.WHITE if flash > 0.0 else color
	var hull := PackedVector2Array()
	for i in 6:
		hull.append(Vector2.from_angle(TAU * i / 6.0) * radius)
	draw_colored_polygon(hull, c)
	draw_rect(Rect2(-RADIUS - 22, -9, 26, 18), c.darkened(0.3))
	# Launch bay on the front, where grunts come out.
	draw_rect(Rect2(-RADIUS * 0.75, -RADIUS * 0.55, 14, RADIUS * 1.1), c.darkened(0.45))
	if not drones_released:
		for dock in DOCKS:
			BossDrone.draw_body(self, dock, Color(0.55, 0.6, 0.7))
	var pulse := 0.5 + 0.5 * sin(t * (6.0 if phase == 2 else 3.0))
	draw_circle(Vector2.ZERO, 18.0, Color(1.0, 0.2 + 0.3 * pulse, 0.2))
	_draw_status()
