class_name Player
extends Node2D
## The Lancer. Its main shot is Twin Shot until a primary weapon upgrade
## replaces it. Secondary (default: Charge Beam) and Dodge each run on their
## own cooldown. Each co-op player gets one of these with their own controls
## and PlayerRun.

const HITBOX := 2.0
const BASE_SPEED := 120.0
const INVULN_TIME := 1.5
const DODGE_SPEED := 380.0
const DODGE_DASH_TIME := 0.15
const DODGE_IFRAMES := 0.35
const DODGE_COOLDOWN := 1.2
const DRONE_INTERVAL := 0.18
const DRONE_DAMAGE := 0.5
## Drone slots: alternate above and below the ship, second pair further out.
const DRONE_OFFSETS := [Vector2(-2, -16), Vector2(-2, 16), Vector2(-10, -30), Vector2(-10, 30)]
const BEAM_TICK := 0.1
const BEAM_HALF_WIDTH := 2.0

## Main-shot stats per primary weapon. Damage is per projectile (per second for the beam).
const WEAPONS := {
	"": {"interval": 0.12, "speed": 380.0, "damage": 0.75, "kind": "pellet"},
	"volt_lightning": {"interval": 1.0, "damage": 6.0, "kind": "zap", "range": 200.0},
	"cryo_lance": {"interval": 0.28, "speed": 240.0, "damage": 3.5, "kind": "lance"},
	"nova_missiles": {"interval": 0.75, "speed": 180.0, "damage": 9.0, "kind": "missile"},
	"acid_beam": {"damage": 8.0, "kind": "beam"},
}

## Secondary abilities by upgrade id; "" is the Lancer's own Charge Beam.
const SECONDARIES := {
	"": {"cooldown": 4.0},
	"volt_storm": {"cooldown": 5.0, "damage": 6.0, "targets": 6, "range": 150.0},
	"cryo_ice": {"cooldown": 6.0, "damage": 4.0, "radius": 52.0, "freeze": 3.0, "speed": 220.0, "fuse": 0.8},
}
## Dodge upgrades by upgrade id; "" is the plain dodge.
const DODGES := {
	"": {},
	"volt_static": {"damage": 5.0, "reach": 30.0},
	"cryo_frost_step": {"slow": 0.5, "duration": 2.0, "reach": 30.0},
}

var run: PlayerRun
var game
var ctl: ControlState
var color := Color.WHITE
var fire_timer := 0.0
var drone_timer := 0.0
var invuln := 0.0
var shot_count := 0
var focused := false
var beam_on := false
var beam_end_x := 480.0
var beam_ticks := 0  # beam damage ticks; every 3rd one stacks acid
var _beam_timer := 0.0
var secondary_cooldown := 0.0
var dodge_cooldown := 0.0
var dodge_iframes := 0.0
var _dodge_dash := 0.0
var _dodge_dir := Vector2.ZERO
var _dodge_hits: Array = []  # enemies already zapped by this Static Dash


func setup(p_run: PlayerRun, p_game, p_color: Color) -> void:
	run = p_run
	game = p_game
	color = p_color
	ctl = ControlState.new(run.devices)


func can_be_hit() -> bool:
	return run.alive and invuln <= 0.0 and dodge_iframes <= 0.0 and not game.god_mode


func secondary() -> Dictionary:
	return SECONDARIES.get(run.secondary, SECONDARIES[""])


## Secondary and dodge upgrades: +25% effect and -10% cooldown per level above 1.
func slot_effect_mult(slot: String) -> float:
	return 1.0 + 0.25 * (run.slot_level(slot) - 1)


func secondary_cooldown_time() -> float:
	return secondary().cooldown * (1.0 - 0.1 * (run.slot_level("secondary") - 1))


func dodge_cooldown_time() -> float:
	return DODGE_COOLDOWN * (1.0 - 0.1 * (run.slot_level("dodge") - 1))


func weapon() -> Dictionary:
	return WEAPONS.get(run.primary, WEAPONS[""])


## +25% damage per weapon level above 1.
func level_mult() -> float:
	return 1.0 + 0.25 * (run.primary_level() - 1)


func fire_rate_mult() -> float:
	return 1.0 + 0.3 * run.stacks("volt_overclock")


func _physics_process(delta: float) -> void:
	var bomb_pressed := ctl.pressed("bomb")
	var dodge_pressed := ctl.pressed("dodge")
	var secondary_pressed := ctl.pressed("secondary")
	beam_on = false
	if not run.alive:
		return
	focused = ctl.down("focus")
	if _dodge_dash > 0.0:
		_dodge_dash -= delta
		position += _dodge_dir * DODGE_SPEED * delta
	else:
		position += ctl.move() * BASE_SPEED * (0.5 if focused else 1.0) * delta
	position = position.clamp(Vector2(8, 8), Vector2(472, 262))
	invuln = maxf(invuln - delta, 0.0)
	dodge_iframes = maxf(dodge_iframes - delta, 0.0)
	dodge_cooldown = maxf(dodge_cooldown - delta, 0.0)
	secondary_cooldown = maxf(secondary_cooldown - delta, 0.0)
	fire_timer -= delta
	drone_timer -= delta
	if game.state == Game.State.PLAYING:
		if dodge_pressed and dodge_cooldown <= 0.0:
			_dodge()
		_update_dodge_effect()
		var firing := ctl.down("fire")
		if weapon().kind == "beam":
			beam_on = firing
			_update_beam(delta)
		elif firing and fire_timer <= 0.0:
			_fire()
		if firing and drone_timer <= 0.0:
			_fire_drones()
		_update_secondary(secondary_pressed)
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


## Dash in the held direction with brief invulnerability. With no direction
## held it's a barrel roll in place: invulnerable, but no movement.
func _dodge() -> void:
	_dodge_dir = ctl.move().normalized()
	_dodge_dash = DODGE_DASH_TIME if _dodge_dir != Vector2.ZERO else 0.0
	dodge_iframes = DODGE_IFRAMES
	dodge_cooldown = dodge_cooldown_time()
	_dodge_hits.clear()


## Per-frame dodge-upgrade effects while the dodge's invulnerability lasts.
func _update_dodge_effect() -> void:
	if dodge_iframes <= 0.0:
		return
	match run.dodge:
		"volt_static":
			var d: Dictionary = DODGES[run.dodge]
			game.static_dash(self, d.damage * slot_effect_mult("dodge"), d.reach, _dodge_hits)
		"cryo_frost_step":
			var d: Dictionary = DODGES[run.dodge]
			game.frost_step(self, d.slow, d.duration * slot_effect_mult("dodge"), d.reach)


func _update_secondary(secondary_pressed: bool) -> void:
	if not secondary_pressed or secondary_cooldown > 0.0:
		return
	var s := secondary()
	match run.secondary:
		"volt_storm":
			game.storm_burst(self, s.damage * slot_effect_mult("secondary"), s.targets, s.range)
		"cryo_ice":
			# Bomb: bursts on the first enemy it touches, or after its fuse.
			var m := slot_effect_mult("secondary")
			_shoot(Vector2(10, 0), 0.0, s.speed, s.damage * m, {
				"kind": "ice_bomb", "radius": 5.0, "explode": s.radius * m,
				"freeze": s.freeze, "fuse": s.fuse})
		_:
			# Charge Beam: a tap fires the full-power piercing shot.
			_shoot(Vector2(12, 0), 0.0, 300.0, 10.0, {"kind": "charge", "radius": 7.0, "pierce": 99})
	secondary_cooldown = secondary_cooldown_time()


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
	var roll := 1.0
	if dodge_iframes > 0.0:
		# Barrel roll: squash the ship vertically and leave afterimages.
		var progress := 1.0 - dodge_iframes / DODGE_IFRAMES
		roll = maxf(absf(cos(progress * TAU)), 0.2)
		for i in [1, 2]:
			var ghost: Vector2 = -_dodge_dir * 7.0 * i
			draw_colored_polygon(_ship_shape(ghost, roll), Color(color, 0.35 / i))
	draw_colored_polygon(_ship_shape(Vector2.ZERO, roll), color)
	draw_rect(Rect2(-10, -1, 3, 2), Color(1, 0.6, 0.2) if Engine.get_physics_frames() % 4 < 2 else Color(1, 0.9, 0.4))
	if focused:
		draw_circle(Vector2.ZERO, HITBOX + 1.0, Color.WHITE)
		draw_circle(Vector2.ZERO, HITBOX, Color.RED)
	if game.players.size() > 1:
		draw_string(ThemeDB.fallback_font, Vector2(-6, -9), "P%d" % (run.index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color)


func _ship_shape(offset: Vector2, y_scale: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in [Vector2(10, 0), Vector2(-7, -6), Vector2(-3, 0), Vector2(-7, 6)]:
		pts.append(offset + Vector2(p.x, p.y * y_scale))
	return pts
