class_name Player
extends Node2D
## The Lancer. Its main shot is Twin Shot until a primary weapon upgrade
## replaces it. Secondary (default: Charge Beam) and Dodge each run on their
## own cooldown. Each co-op player gets one of these with their own controls
## and PlayerRun.

const SHIP_TEXTURE := preload("res://art/sprites/player/lancer.png")
## Where shots and beams leave the ship, relative to its centre.
const NOSE_X := 30.0
const HITBOX := 3.0
const BASE_SPEED := 160.0
const INVULN_TIME := 1.5
const DODGE_SPEED := 507.0
const DODGE_DASH_TIME := 0.15
const DODGE_IFRAMES := 0.35
const DODGE_COOLDOWN := 1.2
## An enemy bullet passing this close counts as a graze (Phase Shift).
const GRAZE_RADIUS := 16.0
## Barrier bubble: enemy bullets touching it are destroyed.
const BARRIER_RADIUS := 22.0
## Drones copy the main weapon's shot at this fraction of its damage.
const DRONE_DAMAGE_MULT := 0.5
## Drone slots: alternate above and below the ship, second pair further out.
const DRONE_OFFSETS := [Vector2(-4, -22), Vector2(-4, 22), Vector2(-14, -40), Vector2(-14, 40)]
## Swarm Strike: drones orbit the ship at this radius and spin speed (rad/s).
const STRIKE_ORBIT := 36.0
const STRIKE_SPIN := 3.0
const DRONE_BEAM_RANGE := 267.0
const BEAM_TICK := 0.1
const BEAM_HALF_WIDTH := 3.0

## Main-shot stats per primary weapon. Damage is per projectile (per second for the beam).
const WEAPONS := {
	"": {"interval": 0.12, "speed": 507.0, "damage": 0.75, "kind": "pellet"},
	"volt_lightning": {"interval": 1.0, "damage": 6.0, "kind": "zap", "range": 267.0},
	"cryo_lance": {"interval": 0.28, "speed": 320.0, "damage": 3.5, "kind": "lance"},
	"nova_missiles": {"interval": 0.75, "speed": 240.0, "damage": 9.0, "kind": "missile"},
	"acid_beam": {"damage": 8.0, "kind": "beam"},
}

## Secondary abilities by upgrade id; "" is the Lancer's own Charge Beam.
const SECONDARIES := {
	"": {"cooldown": 4.0},
	"volt_storm": {"cooldown": 5.0, "damage": 6.0, "targets": 6, "range": 200.0},
	"cryo_ice": {"cooldown": 6.0, "damage": 4.0, "radius": 69.0, "freeze": 3.0, "speed": 293.0, "fuse": 0.8},
	"nova_homing": {"cooldown": 6.0, "damage": 3.0, "count": 6, "radius": 16.0, "speed": 267.0, "fuse": 3.0},
	"swarm_strike": {"cooldown": 12.0, "duration": 6.0, "extra_drones": 2},
	"aegis_repulsor": {"cooldown": 6.0, "radius": 120.0, "bullet_damage": 2.0, "blast_damage": 2.0},
	# Defensive secondaries
	"volt_surge": {"cooldown": 24.0, "duration": 6.0, "boost": 0.25},
	"aegis_barrier": {"cooldown": 20.0, "duration": 5.0},
	"acid_napalm": {"cooldown": 7.0, "speed": 347.0, "fuse": 0.5, "width": 27.0, "duration": 3.0, "tick": 0.4, "power": 2},
}
## Dodge upgrades by upgrade id; "" is the plain dodge.
const DODGES := {
	"": {},
	"volt_static": {"damage": 5.0, "reach": 40.0},
	"cryo_frost_step": {"slow": 0.5, "duration": 2.0, "reach": 40.0},
	"nova_afterburner": {"damage": 6.0, "radius": 37.0},
	"swarm_decoy": {"duration": 2.0, "damage": 6.0, "radius": 43.0},
	"aegis_phase": {"extra_iframes": 0.2, "refund": 0.5},
	"acid_scorch": {"radius": 12.0, "duration": 1.5, "power": 1, "damage": 0.5, "spacing": 11.0},
}

var run: PlayerRun
var game
var ctl: ControlState
var color := Color.WHITE
var fire_timer := 0.0
var invuln := 0.0
var strike_timer := 0.0  # Swarm Strike time left
var surge_timer := 0.0  # Volt Power Surge time left
var barrier_timer := 0.0  # Aegis Barrier time left
var _strike_angle := 0.0
var _drone_beams: Array = []  # [drone offset, beam end] pairs, local, for drawing
var shot_count := 0
var focused := false
var beam_on := false
var beam_end_x := 640.0
var beam_ticks := 0  # beam damage ticks; every 3rd one stacks acid
var _beam_timer := 0.0
var secondary_cooldown := 0.0
var dodge_cooldown := 0.0
var dodge_iframes := 0.0
var _dodge_dash := 0.0
var _dodge_dir := Vector2.ZERO
var _dodge_hits: Array = []  # enemies already zapped by this Static Dash
var _dodge_iframes_total := DODGE_IFRAMES
var _grazed := false  # Phase Shift refund already used this dodge
var _last_scorch := Vector2.INF  # where Scorch Trail last dropped a patch


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
	return (1.0 + 0.3 * run.stacks("volt_overclock")) * surge_mult()


## Volt Power Surge: speed and fire rate boost while active.
func surge_mult() -> float:
	return 1.0 + SECONDARIES["volt_surge"].boost if surge_timer > 0.0 else 1.0


func has_barrier() -> bool:
	return barrier_timer > 0.0


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
		position += ctl.move() * BASE_SPEED * surge_mult() * (0.5 if focused else 1.0) * delta
	position = position.clamp(Vector2(24, 12), Vector2(616, 348))
	invuln = maxf(invuln - delta, 0.0)
	dodge_iframes = maxf(dodge_iframes - delta, 0.0)
	dodge_cooldown = maxf(dodge_cooldown - delta, 0.0)
	secondary_cooldown = maxf(secondary_cooldown - delta, 0.0)
	fire_timer -= delta
	strike_timer = maxf(strike_timer - delta, 0.0)
	surge_timer = maxf(surge_timer - delta, 0.0)
	barrier_timer = maxf(barrier_timer - delta, 0.0)
	_strike_angle += STRIKE_SPIN * delta
	_drone_beams.clear()
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
		opts["explode"] = 32.0 + 5.0 * (run.primary_level() - 1)
		_shoot(Vector2(16, -4 if shot_count % 2 == 0 else 4), 0.0, w.speed, dmg, opts)
	elif w.kind == "pellet":
		_shoot(Vector2(30, -3), 0.0, w.speed, dmg, opts)
		_shoot(Vector2(30, 3), 0.0, w.speed, dmg, opts)
	else:
		_shoot(Vector2(30, 0), 0.0, w.speed, dmg, opts)
	for i in range(1, run.stacks("nova_spread") + 1):
		for side in [-1.0, 1.0]:
			_shoot(Vector2(24, 0), 10.0 * i * side, w.speed, dmg * 0.6, opts)
	if run.stacks("nova_payload") > 0 and shot_count % 5 == 0:
		_shoot(Vector2.ZERO, 0.0, 293.0, 3.0, {"kind": "missile", "explode": 27.0})
	_fire_drones(w, dmg)


## Tesla-coil Lightning: arc from the ship to the nearest enemy in range, in any
## direction. With nothing in range it stays charged and zaps as soon as one is.
## Each drone adds its own weaker, non-chaining zap from where it sits.
func _zap(w: Dictionary) -> void:
	var target = game.nearest_enemy(position, w.range)
	if target == null:
		return
	fire_timer = w.interval / fire_rate_mult()
	shot_count += 1
	var dmg: float = w.damage * level_mult()
	game.lightning_zap(self, target, dmg)
	for off in drone_offsets():
		var drone_target = game.nearest_enemy(position + off, w.range)
		if drone_target:
			game.lightning_zap(self, drone_target, dmg * DRONE_DAMAGE_MULT, position + off, 0)


func _shoot(offset: Vector2, angle_deg: float, speed: float, dmg: float, opts: Dictionary) -> void:
	var vel := Vector2.from_angle(deg_to_rad(angle_deg)) * speed
	game.spawn_player_bullet(position + offset, vel, dmg, run, opts)


## Drone positions relative to the ship: locked formation normally; during
## Swarm Strike every drone (plus the temporary ones) orbits the ship.
func drone_offsets() -> Array:
	var count := run.stacks("swarm_option")
	var out: Array = []
	if strike_timer > 0.0:
		count += SECONDARIES["swarm_strike"].extra_drones
		for i in count:
			out.append(Vector2.from_angle(_strike_angle + TAU * i / count) * STRIKE_ORBIT)
	else:
		for i in count:
			out.append(DRONE_OFFSETS[i])
	return out


## Straight ahead normally; at the nearest enemy during Swarm Strike.
func _drone_aim(from: Vector2) -> Vector2:
	if strike_timer > 0.0:
		var e = game.nearest_enemy(from, INF)
		if e:
			return (e.position - from).normalized()
	return Vector2.RIGHT


## Each drone fires a weaker copy of the main weapon's projectile.
func _fire_drones(w: Dictionary, dmg: float) -> void:
	for off in drone_offsets():
		var pos: Vector2 = position + off
		var dir := _drone_aim(pos)
		var opts := {"kind": w.kind}
		if w.kind == "missile":
			opts["explode"] = 19.0
		game.spawn_player_bullet(pos + dir * 8.0, dir * w.speed, dmg * DRONE_DAMAGE_MULT, run, opts)


func _update_beam(delta: float) -> void:
	if not beam_on:
		_beam_timer = 0.0
		return
	var target = game.beam_target(position, BEAM_HALF_WIDTH)
	beam_end_x = target.position.x - target.radius if target else 640.0
	# Drone beams: straight ahead, or locked onto the nearest enemy in a Strike.
	var drone_targets: Array = []
	for off in drone_offsets():
		var pos: Vector2 = position + off
		var t = game.nearest_enemy(pos, DRONE_BEAM_RANGE) if strike_timer > 0.0 else game.beam_target(pos, 2.0)
		drone_targets.append(t)
		var end: Vector2 = t.position - position if t else Vector2(640.0 - position.x, off.y)
		_drone_beams.append([off, end])
	_beam_timer -= delta
	if _beam_timer <= 0.0:
		_beam_timer = BEAM_TICK
		var dps: float = weapon().damage * level_mult() * fire_rate_mult()
		if target:
			game.beam_hit(self, target, dps * BEAM_TICK)
		for t in drone_targets:
			if t:
				game.beam_hit(self, t, dps * BEAM_TICK * DRONE_DAMAGE_MULT)


## Dash in the held direction with brief invulnerability. With no direction
## held it's a barrel roll in place: invulnerable, but no movement.
func _dodge() -> void:
	_dodge_dir = ctl.move().normalized()
	_dodge_dash = DODGE_DASH_TIME if _dodge_dir != Vector2.ZERO else 0.0
	_dodge_iframes_total = DODGE_IFRAMES
	if run.dodge == "aegis_phase":
		_dodge_iframes_total += DODGES[run.dodge].extra_iframes * slot_effect_mult("dodge")
	dodge_iframes = _dodge_iframes_total
	dodge_cooldown = dodge_cooldown_time()
	_dodge_hits.clear()
	_grazed = false
	_last_scorch = Vector2.INF
	match run.dodge:
		"nova_afterburner":
			var d: Dictionary = DODGES[run.dodge]
			game.afterburner(self, position, d.damage * slot_effect_mult("dodge"), d.radius)
		"swarm_decoy":
			var d: Dictionary = DODGES[run.dodge]
			game.spawn_decoy(self, position, d.duration, d.damage * slot_effect_mult("dodge"), d.radius)


## An enemy bullet passed close by. With Phase Shift, the first graze during a
## dodge refunds half the dodge cooldown.
func on_graze(at: Vector2) -> void:
	if run.dodge != "aegis_phase" or dodge_iframes <= 0.0 or _grazed:
		return
	_grazed = true
	dodge_cooldown = maxf(dodge_cooldown - dodge_cooldown_time() * DODGES[run.dodge].refund, 0.0)
	game.graze_spark(at)


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
		"acid_scorch":
			# Drop a fire patch every few pixels along the dash path.
			var d: Dictionary = DODGES[run.dodge]
			if _last_scorch == Vector2.INF or position.distance_to(_last_scorch) >= d.spacing:
				_last_scorch = position
				game.scorch_patch(self, position, d.radius, d.duration * slot_effect_mult("dodge"),
					d.power * run.slot_level("dodge"), d.damage)


func _update_secondary(secondary_pressed: bool) -> void:
	if not secondary_pressed or secondary_cooldown > 0.0:
		return
	var s := secondary()
	match run.secondary:
		"volt_storm":
			game.storm_burst(self, s.damage * slot_effect_mult("secondary"), s.targets, s.range)
		"volt_surge":
			surge_timer = s.duration * slot_effect_mult("secondary")
		"aegis_barrier":
			barrier_timer = s.duration * slot_effect_mult("secondary")
		"acid_napalm":
			_shoot(Vector2(30, 0), 0.0, s.speed, 0.0, {"kind": "canister", "radius": 5.0, "fuse": s.fuse,
				"extra": {"width": s.width, "duration": s.duration * slot_effect_mult("secondary"),
					"tick": s.tick, "power": s.power}})
		"aegis_repulsor":
			var m := slot_effect_mult("secondary")
			game.repulsor(self, s.radius, s.bullet_damage * m, s.blast_damage * m)
		"swarm_strike":
			strike_timer = s.duration * slot_effect_mult("secondary")
		"nova_homing":
			# Fan the missiles out from the ship; they then curve onto targets.
			var m := slot_effect_mult("secondary")
			for i in s.count:
				var angle := lerpf(-60.0, 60.0, float(i) / maxi(s.count - 1, 1))
				_shoot(Vector2(8, 0), angle, s.speed, s.damage * m, {
					"kind": "homing", "explode": s.radius, "fuse": s.fuse})
		"cryo_ice":
			# Bomb: bursts on the first enemy it touches, or after its fuse.
			var m := slot_effect_mult("secondary")
			_shoot(Vector2(30, 0), 0.0, s.speed, s.damage * m, {
				"kind": "ice_bomb", "radius": 7.0, "explode": s.radius * m,
				"freeze": s.freeze, "fuse": s.fuse})
		_:
			# Charge Beam: a tap fires the full-power piercing shot.
			_shoot(Vector2(30, 0), 0.0, 400.0, 10.0, {"kind": "charge", "radius": 9.0, "pierce": 99})
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
	position = Vector2(80, 180)


func _draw() -> void:
	if not run.alive:
		return
	if beam_on:
		var length := beam_end_x - position.x - NOSE_X
		var flicker := 0.5 + 0.2 * sin(Engine.get_physics_frames() * 0.8)
		draw_rect(Rect2(NOSE_X, -BEAM_HALF_WIDTH - 1, length, BEAM_HALF_WIDTH * 2 + 2), Color(0.6, 1.0, 0.2, flicker))
		draw_rect(Rect2(NOSE_X, -1, length, 2), Color(0.95, 1.0, 0.75))
		draw_circle(Vector2(NOSE_X + length, 0), 4.0, Color(1.0, 0.8, 0.3, 0.8))
	for pair in _drone_beams:
		draw_line(pair[0], pair[1], Color(0.7, 1.0, 0.3, 0.7), 1.0)
	for off in drone_offsets():
		var d: Vector2 = off
		var aim := _drone_aim(position + d)
		var side := aim.orthogonal()
		draw_colored_polygon(PackedVector2Array([d + aim * 7.0, d - aim * 4.0 + side * 4.0, d - aim * 4.0 - side * 4.0]), color.darkened(0.25))
		draw_rect(Rect2(d + Vector2(-1, -1), Vector2(3, 2)), Color.WHITE)
	if barrier_timer > 0.0:
		# Bubble; flickers in its last half second.
		var a := 0.35 if barrier_timer > 0.5 or int(barrier_timer * 20.0) % 2 == 0 else 0.1
		draw_circle(Vector2.ZERO, BARRIER_RADIUS, Color(0.8, 0.9, 1.0, a * 0.4))
		draw_arc(Vector2.ZERO, BARRIER_RADIUS, 0.0, TAU, 24, Color(0.85, 0.92, 1.0, a + 0.3), 1.0)
	if surge_timer > 0.0 and Engine.get_physics_frames() % 6 < 3:
		# Crackle along the hull while Power Surge is active.
		var j := Vector2(randf_range(-24, 24), randf_range(-9, 9))
		draw_line(j, j + Vector2(randf_range(-5, 5), randf_range(-5, 5)), Color(0.75, 0.9, 1.0), 1.0)
	if invuln > 0.0 and int(invuln * 20.0) % 2 == 0:
		return
	var roll := 1.0
	if dodge_iframes > 0.0:
		# Barrel roll: squash the ship vertically and leave afterimages.
		var progress := 1.0 - dodge_iframes / _dodge_iframes_total
		roll = maxf(absf(cos(progress * TAU)), 0.2)
		for i in [1, 2]:
			_draw_ship(-_dodge_dir * 10.0 * i, roll, Color(_tint(), 0.35 / i))
	_draw_ship(Vector2.ZERO, roll, _tint())
	if focused:
		draw_circle(Vector2.ZERO, HITBOX + 1.0, Color.WHITE)
		draw_circle(Vector2.ZERO, HITBOX, Color.RED)
	if game.players.size() > 1:
		draw_string(ThemeDB.fallback_font, Vector2(-8, -16), "P%d" % (run.index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)


## P1 flies the ship in its own colors; other co-op players get a tint of
## their player color so ships stay easy to tell apart.
func _tint() -> Color:
	return Color.WHITE if run.index == 0 else Color.WHITE.lerp(color, 0.45)


func _draw_ship(offset: Vector2, y_scale: float, modulate_color: Color) -> void:
	draw_set_transform(offset, 0.0, Vector2(1.0, y_scale))
	draw_texture(SHIP_TEXTURE, -SHIP_TEXTURE.get_size() / 2.0, modulate_color)
	draw_set_transform(Vector2.ZERO)
