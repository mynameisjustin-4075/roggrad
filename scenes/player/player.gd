class_name Player
extends Node2D
## The Lancer. Its main shot is Twin Shot until a primary weapon upgrade
## replaces it; hold Special to charge a piercing beam. Each co-op player gets
## one of these with their own controls and PlayerRun.

const HITBOX := 2.0
const BASE_SPEED := 120.0
const INVULN_TIME := 1.5
const DRONE_INTERVAL := 0.18
const DRONE_DAMAGE := 0.5
## Drone slots: alternate above and below the ship, second pair further out.
const DRONE_OFFSETS := [Vector2(-2, -16), Vector2(-2, 16), Vector2(-10, -30), Vector2(-10, 30)]
const BEAM_TICK := 0.1
const BEAM_HALF_WIDTH := 2.0

## Main-shot stats per primary weapon. Damage is per projectile (per second for the beam).
const WEAPONS := {
	"": {"interval": 0.12, "speed": 380.0, "damage": 0.75, "kind": "pellet"},
	"volt_lightning": {"interval": 1.0, "damage": 8.0, "kind": "zap", "range": 200.0},
	"cryo_lance": {"interval": 0.28, "speed": 240.0, "damage": 3.5, "kind": "lance"},
	"nova_missiles": {"interval": 0.75, "speed": 180.0, "damage": 9.0, "kind": "missile"},
	"acid_beam": {"damage": 8.0, "kind": "beam"},
}

var run: PlayerRun
var game
var ctl: ControlState
var color := Color.WHITE
var fire_timer := 0.0
var drone_timer := 0.0
var invuln := 0.0
var shot_count := 0
var charge := 0.0
var focused := false
var beam_on := false
var beam_end_x := 480.0
var beam_ticks := 0  # beam damage ticks; every 3rd one stacks acid
var _beam_timer := 0.0


func setup(p_run: PlayerRun, p_game, p_color: Color) -> void:
	run = p_run
	game = p_game
	color = p_color
	ctl = ControlState.new(run.devices)


func can_be_hit() -> bool:
	return run.alive and invuln <= 0.0 and not game.god_mode


func weapon() -> Dictionary:
	return WEAPONS.get(run.primary, WEAPONS[""])


## +25% damage per weapon level above 1.
func level_mult() -> float:
	return 1.0 + 0.25 * (run.primary_level() - 1)


func fire_rate_mult() -> float:
	return 1.0 + 0.3 * run.stacks("volt_overclock")


func _physics_process(delta: float) -> void:
	var bomb_pressed := ctl.pressed("bomb")
	beam_on = false
	if not run.alive:
		return
	focused = ctl.down("focus")
	position += ctl.move() * BASE_SPEED * (0.5 if focused else 1.0) * delta
	position = position.clamp(Vector2(8, 8), Vector2(472, 262))
	invuln = maxf(invuln - delta, 0.0)
	fire_timer -= delta
	drone_timer -= delta
	if game.state == Game.State.PLAYING:
		var firing := ctl.down("fire")
		if weapon().kind == "beam":
			beam_on = firing
			_update_beam(delta)
		elif firing and fire_timer <= 0.0:
			_fire()
		if firing and drone_timer <= 0.0:
			_fire_drones()
		_update_charge(delta)
		if bomb_pressed and run.bombs > 0:
			run.bombs -= 1
			game.bomb(self)
	queue_redraw()


func _fire() -> void:
	var w := weapon()
	if w.kind == "zap":
		_zap(w)
		return
	fire_timer = w.interval / fire_rate_mult()
	shot_count += 1
	var dmg: float = w.damage * level_mult()
	var opts := {"kind": w.kind}
	if w.kind == "missile":
		opts["explode"] = 24.0 + 4.0 * (run.primary_level() - 1)
		_shoot(Vector2(8, -3 if shot_count % 2 == 0 else 3), 0.0, w.speed, dmg, opts)
	elif w.kind == "pellet":
		_shoot(Vector2(10, -2), 0.0, w.speed, dmg, opts)
		_shoot(Vector2(10, 2), 0.0, w.speed, dmg, opts)
	else:
		_shoot(Vector2(10, 0), 0.0, w.speed, dmg, opts)
	for i in range(1, run.stacks("nova_spread") + 1):
		for side in [-1.0, 1.0]:
			_shoot(Vector2(8, 0), 10.0 * i * side, w.speed, dmg * 0.6, opts)
	if run.stacks("nova_payload") > 0 and shot_count % 5 == 0:
		_shoot(Vector2.ZERO, 0.0, 220.0, 3.0, {"kind": "missile", "explode": 20.0})


## Tesla-coil Lightning: arc from the ship to the nearest enemy in range, in any
## direction. With nothing in range it stays charged and zaps as soon as one is.
func _zap(w: Dictionary) -> void:
	var target = game.nearest_enemy(position, w.range)
	if target == null:
		return
	fire_timer = w.interval / fire_rate_mult()
	shot_count += 1
	game.lightning_zap(self, target, w.damage * level_mult())


func _shoot(offset: Vector2, angle_deg: float, speed: float, dmg: float, opts: Dictionary) -> void:
	var vel := Vector2.from_angle(deg_to_rad(angle_deg)) * speed
	game.spawn_player_bullet(position + offset, vel, dmg, run, opts)


func _fire_drones() -> void:
	var count := run.stacks("swarm_option")
	if count == 0:
		return
	drone_timer = DRONE_INTERVAL / fire_rate_mult()
	for i in count:
		game.spawn_player_bullet(position + DRONE_OFFSETS[i] + Vector2(6, 0), Vector2(380, 0), DRONE_DAMAGE, run)


func _update_beam(delta: float) -> void:
	if not beam_on:
		_beam_timer = 0.0
		return
	var target = game.beam_target(position, BEAM_HALF_WIDTH)
	beam_end_x = target.position.x - target.radius if target else 480.0
	_beam_timer -= delta
	if _beam_timer <= 0.0:
		_beam_timer = BEAM_TICK
		if target:
			var dps: float = weapon().damage * level_mult() * fire_rate_mult()
			game.beam_hit(self, target, dps * BEAM_TICK)


func _update_charge(delta: float) -> void:
	if ctl.down("special"):
		charge = minf(charge + delta, 1.0)
	elif charge > 0.0:
		if charge >= 0.3:
			_shoot(Vector2(12, 0), 0.0, 300.0, 10.0 * charge, {"kind": "charge", "radius": 3.0 + 4.0 * charge, "pierce": 99})
		charge = 0.0


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
	position = Vector2(60, 135)


func _draw() -> void:
	if not run.alive:
		return
	if beam_on:
		var length := beam_end_x - position.x - 10.0
		var flicker := 0.5 + 0.2 * sin(Engine.get_physics_frames() * 0.8)
		draw_rect(Rect2(10, -BEAM_HALF_WIDTH - 1, length, BEAM_HALF_WIDTH * 2 + 2), Color(0.6, 1.0, 0.2, flicker))
		draw_rect(Rect2(10, -1, length, 2), Color(0.95, 1.0, 0.75))
		draw_circle(Vector2(10 + length, 0), 3.0, Color(1.0, 0.8, 0.3, 0.8))
	for i in run.stacks("swarm_option"):
		var d: Vector2 = DRONE_OFFSETS[i]
		draw_colored_polygon(PackedVector2Array([d + Vector2(5, 0), d + Vector2(-3, -3), d + Vector2(-3, 3)]), color.darkened(0.25))
		draw_rect(Rect2(d + Vector2(-1, -0.5), Vector2(2, 1)), Color.WHITE)
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
