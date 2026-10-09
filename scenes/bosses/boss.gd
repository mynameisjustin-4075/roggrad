class_name Boss
extends Enemy
## World 1 boss, the Salvage Leviathan (placeholder art). Three phases by HP:
##   1 (above 2/3): aimed 3-way bursts while it sways.
##   2 (2/3 - 1/3): adds rotating rings and releases two beam drones, which it
##      directs through patterns: "lanes", "angled" and "x".
##   3 (below 1/3): adds grunt launches in patterns: "pair", "stream", "wall".
## Each phase speeds up its attacks by 25%. In co-op only HP scales.

const BASE_HP := 1200.0
const RADIUS := 58.0
const PARK_X := 560.0  # where it stops after entering
const SWAY := 100.0  # vertical sway around mid-screen
const PHASE_SPEEDUP := 1.25
const BURST_INTERVAL := 1.1
const RING_INTERVAL := 1.8
const MINION_INTERVAL := 4.0
## Drone pattern timing (move and telegraph scale with phase speed; firing is 2 s).
const DRONE_MOVE_TIME := 1.5
const DRONE_TELEGRAPH_TIME := 1.0
const DRONE_FIRE_TIME := 2.0
const DRONE_X := 470.0
## X pattern: how far the drones slide toward the crossing column while firing.
const X_SLIDE := 0.5
const DRONE_PATTERNS := ["lanes", "angled", "x"]
const MINION_PATTERNS := ["pair", "stream", "wall"]
## A destroyed drone is rebuilt on its dock and relaunched after this long.
const DRONE_REBUILD_TIME := 15.0
## Where the drones sit on the hull until released (top and bottom).
const DOCKS := [Vector2(-8, -RADIUS - 6), Vector2(-8, RADIUS + 6)]

var phase := 1
var hp_mult := 1.0
var ring_timer := 1.0
var minion_timer := 1.5
var drones_released := false
var drones: Array = [null, null]  # by lane: 0 = top, 1 = bottom
var rebuild_timers := [-1.0, -1.0]  # by lane; -1 = not rebuilding
var drone_state := "move"
var drone_time := 0.0
var drone_pattern := ""
var cross := Vector2.ZERO  # X pattern crossing point
var _launch_queue: Array = []  # [{t, offset}] grunts still to launch
var _last_drone_pattern := ""
var _minion_index := 0


func setup_boss(p_hp_mult: float) -> void:
	kind = "boss"
	hp_mult = p_hp_mult
	max_hp = BASE_HP * hp_mult
	hp = max_hp
	radius = RADIUS
	color = Color(0.75, 0.7, 0.6)
	scrap = 80
	fire_timer = 2.0
	freeze_resist = 0.5
	max_freezes = 3  # 1.5 s, 1.0 s, 0.5 s, then immune for the fight


func phase_speed() -> float:
	return pow(PHASE_SPEEDUP, phase - 1)


func _move(delta: float) -> void:
	if position.x > PARK_X:
		position.x -= 53.0 * delta
	else:
		position.y = 180.0 + sin(t * 0.7) * SWAY


func _update_fire(delta: float) -> void:
	if position.x > PARK_X + 14.0:
		return
	phase = 3 if hp < max_hp / 3.0 else (2 if hp < max_hp * 2.0 / 3.0 else 1)
	var sp := phase_speed()
	# Phase 1+: aimed 3-way bursts.
	fire_timer -= delta
	if fire_timer <= 0.0:
		fire_timer = BURST_INTERVAL / sp
		var p = game.aim_target(position)
		if p:
			var dir: Vector2 = (p.position - position).normalized()
			for a in [-0.25, 0.0, 0.25]:
				game.spawn_enemy_bullet(position + Vector2(-RADIUS, 0), dir.rotated(a) * 133.0, self)
	if phase >= 2:
		if not drones_released:
			_release_drones()
		_update_rebuilds(delta)
		ring_timer -= delta
		if ring_timer <= 0.0:
			ring_timer = RING_INTERVAL / sp
			for i in 14:
				game.spawn_enemy_bullet(position, Vector2.from_angle(TAU * i / 14.0 + t) * 93.0, self)
		_drone_cycle(delta, sp)
	if phase >= 3:
		minion_timer -= delta
		if minion_timer <= 0.0:
			minion_timer = MINION_INTERVAL / sp
			_queue_minions(MINION_PATTERNS[_minion_index % MINION_PATTERNS.size()])
			_minion_index += 1
	_launch_due_minions(delta)


# --- Grunts -------------------------------------------------------------------

func _queue_minions(pattern: String) -> void:
	match pattern:
		"pair":  # one high, one low
			for side in [-1.0, 1.0]:
				_launch_queue.append({"t": 0.0, "offset": side * 0.45})
		"stream":  # five in a snaking line from the bay's centre
			for i in 5:
				_launch_queue.append({"t": i * 0.22, "offset": 0.0})
		"wall":  # four at spread heights at once
			for off in [-0.9, -0.3, 0.3, 0.9]:
				_launch_queue.append({"t": 0.0, "offset": off})


func _launch_due_minions(delta: float) -> void:
	for entry in _launch_queue:
		entry.t -= delta
	for entry in _launch_queue.filter(func(q): return q.t <= 0.0):
		var y := clampf(position.y + entry.offset * RADIUS * 1.6, 24.0, 336.0)
		game.spawn_minion("grunt", Vector2(position.x - RADIUS * 0.6, y), self)
	_launch_queue = _launch_queue.filter(func(q): return q.t > 0.0)


# --- Drones -------------------------------------------------------------------

func _release_drones() -> void:
	drones_released = true
	for lane in DOCKS.size():
		_launch_drone(lane)
	game.shake = maxf(game.shake, 0.8)
	_start_drone_pattern()


func _launch_drone(lane: int) -> void:
	var d := BossDrone.new()
	d.game = game
	d.setup_drone(lane, hp_mult, self)
	d.position = position + DOCKS[lane]
	# Hover in its lane until the next pattern starts.
	d.target = Vector2(DRONE_X, 90.0 if lane == 0 else 270.0)
	game.enemies.add_child(d)
	drones[lane] = d


func _drone_lost(lane: int) -> bool:
	var d = drones[lane]
	return d == null or not is_instance_valid(d) or d.dead


## A destroyed drone starts rebuilding on its dock; after DRONE_REBUILD_TIME it
## launches again and joins the next pattern.
func _update_rebuilds(delta: float) -> void:
	for lane in DOCKS.size():
		if not _drone_lost(lane):
			continue
		if rebuild_timers[lane] < 0.0:
			rebuild_timers[lane] = DRONE_REBUILD_TIME
		rebuild_timers[lane] -= delta
		if rebuild_timers[lane] <= 0.0:
			rebuild_timers[lane] = -1.0
			_launch_drone(lane)


func _alive_drones() -> Array:
	return range(DOCKS.size()).filter(func(lane): return not _drone_lost(lane)).map(func(lane): return drones[lane])


## `force` picks a specific pattern (tests); otherwise random, never the same twice.
func _start_drone_pattern(force := "") -> void:
	var options := DRONE_PATTERNS.filter(func(n): return n != _last_drone_pattern)
	drone_pattern = force if force != "" else options.pick_random()
	_last_drone_pattern = drone_pattern
	drone_state = "move"
	drone_time = 0.0
	for d in _alive_drones():
		d.mode = "idle"
		d.move_speed = 200.0
		d.aim = PI
		match drone_pattern:
			"lanes":
				# Start far enough apart that the squeeze always leaves a gap
				# (worst case: beams at y 160 and 200, ~28 px of clear space).
				d.target = Vector2(DRONE_X, randf_range(50, 110) if d.lane == 0 else randf_range(250, 310))
			"angled":
				d.target = Vector2(DRONE_X, 70.0 if d.lane == 0 else 290.0)
			"x":
				d.target = Vector2(DRONE_X, 24.0 if d.lane == 0 else 336.0)


func _drone_cycle(delta: float, sp: float) -> void:
	var alive := _alive_drones()
	if alive.is_empty():
		return
	drone_time += delta
	match drone_state:
		"move":
			if drone_time >= DRONE_MOVE_TIME / sp:
				_aim_drones(alive)
				_set_drone_state("telegraph", alive)
		"telegraph":
			if drone_time >= DRONE_TELEGRAPH_TIME / sp:
				_set_drone_state("fire", alive)
				game.shake = maxf(game.shake, 0.3)
		"fire":
			_sweep_drones(alive, delta)
			if drone_time >= DRONE_FIRE_TIME:
				_start_drone_pattern()


func _set_drone_state(s: String, alive: Array) -> void:
	drone_state = s
	drone_time = 0.0
	for d in alive:
		d.mode = s


## Lock in the aim when the warning lines appear.
func _aim_drones(alive: Array) -> void:
	var p = game.aim_target(position)
	var player_pos: Vector2 = p.position if p else Vector2(160, 180)
	match drone_pattern:
		"lanes":
			for d in alive:
				d.aim = PI
		"angled":
			# Both beams converge on where the player is right now.
			for d in alive:
				d.aim = (player_pos - d.position).angle()
		"x":
			# Beams cross on the player's column at mid-height.
			cross = Vector2(clampf(player_pos.x, 140.0, 380.0), 180.0)
			for d in alive:
				d.aim = (cross - d.position).angle()


## Movement while firing.
func _sweep_drones(alive: Array, delta: float) -> void:
	match drone_pattern:
		"lanes":
			# Squeeze the gap: the two beams drift toward each other.
			for d in alive:
				d.move_speed = 25.0
				d.target = Vector2(DRONE_X, d.position.y + (25.0 if d.lane == 0 else -25.0))
		"angled":
			# Sweep the beams toward the centre line.
			for d in alive:
				d.aim += (-0.13 if d.lane == 0 else 0.13) * delta
		"x":
			# Slide along the edges halfway toward the crossing column, swinging
			# both beams steeper so the player has to move off the cross. Only
			# halfway, so the wedges above and below the cross stay open.
			var stop_x := DRONE_X - (DRONE_X - cross.x) * X_SLIDE
			for d in alive:
				d.move_speed = (DRONE_X - stop_x) / DRONE_FIRE_TIME
				d.target = Vector2(stop_x, d.position.y)
				d.aim = (cross - d.position).angle()


func _draw() -> void:
	var c := Color.WHITE if flash > 0.0 else color
	var hull := PackedVector2Array()
	for i in 6:
		hull.append(Vector2.from_angle(TAU * i / 6.0) * radius)
	draw_colored_polygon(hull, c)
	draw_rect(Rect2(-RADIUS - 22, -9, 26, 18), c.darkened(0.3))
	# Launch bay on the front, where grunts come out.
	draw_rect(Rect2(-RADIUS * 0.75, -RADIUS * 0.55, 14, RADIUS * 1.1), c.darkened(0.45))
	for lane in DOCKS.size():
		if not drones_released:
			BossDrone.draw_body(self, DOCKS[lane], 0.0, Color(0.55, 0.6, 0.7))
		elif rebuild_timers[lane] >= 0.0:
			# Rebuilding: the drone fades in on its dock as the timer runs down.
			var built: float = 1.0 - rebuild_timers[lane] / DRONE_REBUILD_TIME
			BossDrone.draw_body(self, DOCKS[lane], 0.0, Color(0.55, 0.6, 0.7, 0.15 + 0.6 * built))
	var pulse := 0.5 + 0.5 * sin(t * 3.0 * phase_speed())
	draw_circle(Vector2.ZERO, 18.0, Color(1.0, 0.2 + 0.3 * pulse, 0.2))
	_draw_status()
