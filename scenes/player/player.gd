class_name Player
extends Node2D
## The Lancer: twin forward shot, hold Special to charge a piercing beam.
## Each co-op player gets one of these with their own controls and PlayerRun.

const HITBOX := 2.0
const BASE_SPEED := 120.0
const BASE_FIRE_INTERVAL := 0.12
const SHOT_DAMAGE := 0.75
const BULLET_SPEED := 380.0
const INVULN_TIME := 1.5
const OPTION_SPACING := 12

var run: PlayerRun
var game
var ctl: ControlState
var color := Color.WHITE
var fire_timer := 0.0
var invuln := 0.0
var shot_count := 0
var charge := 0.0
var focused := false
var trail: Array[Vector2] = []


func setup(p_run: PlayerRun, p_game, p_color: Color) -> void:
	run = p_run
	game = p_game
	color = p_color
	ctl = ControlState.new(run.devices)


func can_be_hit() -> bool:
	return run.alive and invuln <= 0.0 and not game.god_mode


func _physics_process(delta: float) -> void:
	var bomb_pressed := ctl.pressed("bomb")
	if not run.alive:
		return
	focused = ctl.down("focus")
	position += ctl.move() * BASE_SPEED * (0.5 if focused else 1.0) * delta
	position = position.clamp(Vector2(8, 8), Vector2(472, 262))
	trail.push_front(position)
	if trail.size() > OPTION_SPACING * 5:
		trail.pop_back()
	invuln = maxf(invuln - delta, 0.0)
	fire_timer -= delta
	if game.state == Game.State.PLAYING:
		if ctl.down("fire") and fire_timer <= 0.0:
			_fire()
		_update_charge(delta)
		if bomb_pressed and run.bombs > 0:
			run.bombs -= 1
			game.bomb(self)
	queue_redraw()


func _fire() -> void:
	fire_timer = BASE_FIRE_INTERVAL / (1.0 + 0.3 * run.stacks("volt_overclock"))
	shot_count += 1
	var forward := Vector2(BULLET_SPEED, 0)
	game.spawn_player_bullet(position + Vector2(10, -2), forward, SHOT_DAMAGE, run)
	game.spawn_player_bullet(position + Vector2(10, 2), forward, SHOT_DAMAGE, run)
	for i in range(1, run.stacks("nova_spread") + 1):
		for side in [-1.0, 1.0]:
			var dir := Vector2.from_angle(deg_to_rad(10.0 * i * side))
			game.spawn_player_bullet(position + Vector2(8, 0), dir * BULLET_SPEED, SHOT_DAMAGE * 0.6, run)
	if run.stacks("nova_payload") > 0 and shot_count % 5 == 0:
		game.spawn_player_bullet(position, Vector2(220, 0), SHOT_DAMAGE * 4.0, run, {"missile": true, "explode": 20.0, "radius": 3.0})
	for i in run.stacks("swarm_option"):
		game.spawn_player_bullet(option_position(i) + Vector2(6, 0), forward, SHOT_DAMAGE * 0.6, run)


func _update_charge(delta: float) -> void:
	if ctl.down("special"):
		charge = minf(charge + delta, 1.0)
	elif charge > 0.0:
		if charge >= 0.3:
			game.spawn_player_bullet(position + Vector2(12, 0), Vector2(300, 0), 10.0 * charge, run, {"radius": 3.0 + 4.0 * charge, "pierce": 99})
		charge = 0.0


func option_position(i: int) -> Vector2:
	var idx := mini((i + 1) * OPTION_SPACING, trail.size() - 1)
	return trail[idx] if idx >= 0 else position


func take_hit() -> void:
	if not can_be_hit():
		return
	run.hull -= 1
	invuln = INVULN_TIME
	game.shake = maxf(game.shake, 0.6)
	if run.hull <= 0:
		run.hull = 0
		run.alive = false
		visible = false
		game.on_player_down(self)


func revive() -> void:
	run.alive = true
	run.hull = maxi(run.hull, 1)
	visible = true
	invuln = 2.0
	trail.clear()
	position = Vector2(60, 135)


func _draw() -> void:
	if not run.alive:
		return
	for i in run.stacks("swarm_option"):
		var op := option_position(i) - position
		draw_circle(op, 3.0, color.darkened(0.25))
		draw_circle(op, 1.5, Color.WHITE)
	if invuln > 0.0 and int(invuln * 20.0) % 2 == 0:
		return
	draw_colored_polygon(PackedVector2Array([Vector2(10, 0), Vector2(-7, -6), Vector2(-3, 0), Vector2(-7, 6)]), color)
	draw_rect(Rect2(-10, -1, 3, 2), Color(1, 0.6, 0.2) if Engine.get_physics_frames() % 4 < 2 else Color(1, 0.9, 0.4))
	if charge >= 0.3:
		draw_circle(Vector2(12, 0), 2.0 + 3.0 * charge, Color(1, 1, 1, 0.7))
	if focused:
		draw_circle(Vector2.ZERO, HITBOX + 1.0, Color.WHITE)
		draw_circle(Vector2.ZERO, HITBOX, Color.RED)
	if game.players.size() > 1:
		draw_string(ThemeDB.fallback_font, Vector2(-6, -9), "P%d" % (run.index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color)
