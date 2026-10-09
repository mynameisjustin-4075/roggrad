class_name Game
extends Node2D
## Runs one world: rooms in order, an upgrade pick per player after each room,
## then the boss. Builds its child nodes in code; collision is simple distance
## checks, which is plenty for a 640x360 shmup.

enum State { PLAYING, PICKING, VICTORY, GAME_OVER }

const UPGRADE_DIR := "res://data/upgrades/"
const PLAYER_COLORS := [Color("4fd8ff"), Color("8cff5a"), Color("ffa040"), Color("ff5ad8")]
const MAX_PLAYERS := 4
const HP_PER_EXTRA_PLAYER := 0.6
const SPAWNS_PER_EXTRA_PLAYER := 0.25
## Speed multipliers while slowed; the strongest active slow wins.
const FROST_LANCE_SLOW := 0.8
const FROST_WAKE_SLOW := 0.6
const SLOW_DURATION := 2.0
const LIGHTNING_COLOR := Color(0.75, 0.9, 1.0)
const ICE_COLOR := Color(0.55, 0.85, 1.0)
const AEGIS_COLOR := Color(0.85, 0.9, 1.0)

@export var world: WorldData

var state := State.PLAYING
var room: RoomData
var room_time := 0.0
var boss: Boss = null
var players: Array[Player] = []
var banner_text := ""
var banner_time := 0.0
var shake := 0.0
var god_mode := false

var _spawn_queue: Array = []
var _upgrade_library: Array[UpgradeData] = []
var _pick_queue: Array[PlayerRun] = []

var starfield: Starfield
var world_root: Node2D
var enemies: Node2D
var decoys: Node2D
var hazards: Node2D
var player_bullets: Node2D
var enemy_bullets: Node2D
var players_node: Node2D
var effects: Node2D
var hud: Hud
var picker: UpgradePicker


func _ready() -> void:
	randomize()
	_build_nodes()
	_load_upgrades()
	RunState.new_run()
	_add_player([Controls.KEYBOARD, 0])
	_start_room(0)


func _build_nodes() -> void:
	starfield = Starfield.new()
	add_child(starfield)
	world_root = Node2D.new()
	add_child(world_root)
	hazards = _add_layer("Hazards")
	decoys = _add_layer("Decoys")
	enemies = _add_layer("Enemies")
	players_node = _add_layer("Players")
	player_bullets = _add_layer("PlayerBullets")
	enemy_bullets = _add_layer("EnemyBullets")
	effects = _add_layer("Effects")
	var ui := CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	hud.game = self
	ui.add_child(hud)
	picker = UpgradePicker.new()
	picker.visible = false
	picker.chosen.connect(_on_upgrade_chosen)
	ui.add_child(picker)


func _add_layer(layer_name: String) -> Node2D:
	var n := Node2D.new()
	n.name = layer_name
	world_root.add_child(n)
	return n


func _load_upgrades() -> void:
	var dir := DirAccess.open(UPGRADE_DIR)
	if dir == null:
		push_error("Missing upgrade folder: " + UPGRADE_DIR)
		return
	for f in dir.get_files():
		var file := f.trim_suffix(".remap")
		if file.ends_with(".tres"):
			var u := load(UPGRADE_DIR + file) as UpgradeData
			if u:
				_upgrade_library.append(u)


# --- Players -----------------------------------------------------------------

func _add_player(devices: Array) -> void:
	var run := RunState.add_player(devices)
	var p := Player.new()
	p.setup(run, self, PLAYER_COLORS[run.index])
	p.position = Vector2(80, 120 + run.index * 40)
	players_node.add_child(p)
	players.append(p)


func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo:
		_debug_key(event.keycode)
	if state != State.PLAYING or players.size() >= MAX_PLAYERS:
		return
	if event is InputEventJoypadButton and event.pressed \
			and event.button_index in [JOY_BUTTON_START, JOY_BUTTON_A] \
			and not RunState.has_device(event.device):
		_add_player([event.device])
		_banner("P%d joined" % players.size())


## Debug builds only. F1: toggle invincibility. F2: clear the current room.
## F3 / F5 / F6: cycle P1's primary / secondary / dodge. F4: give P1 a drone.
## F7: jump straight to the world's boss room. N: drop the boss to its next phase
## (not F8: that is the Godot editor's "stop game" shortcut).
func _debug_key(keycode: Key) -> void:
	var p1 := RunState.players[0]
	match keycode:
		KEY_N:
			if boss and is_instance_valid(boss) and not boss.dead:
				var next_threshold := boss.max_hp * (2.0 / 3.0 if boss.hp >= boss.max_hp * 2.0 / 3.0 else 1.0 / 3.0)
				boss.hp = minf(boss.hp, next_threshold - 1.0)
				_banner("Boss phase skip")
		KEY_F7:
			if state == State.PLAYING:
				for e in enemies.get_children():
					e.dead = true
					e.queue_free()
				_clear_enemy_bullets()
				_start_room(world.rooms.size() - 1)
		KEY_F3:
			_debug_cycle(p1, "primary")
		KEY_F5:
			_debug_cycle(p1, "secondary")
		KEY_F6:
			_debug_cycle(p1, "dodge")
		KEY_F4:
			p1.upgrades["swarm_option"] = mini(p1.stacks("swarm_option") + 1, 4)
		KEY_F1:
			god_mode = not god_mode
			_banner("God mode " + ("on" if god_mode else "off"))
		KEY_F2:
			if state == State.PLAYING:
				_spawn_queue.clear()
				for e in enemies.get_children():
					e.dead = true
					e.queue_free()
				boss = null


func _debug_cycle(run: PlayerRun, slot: String) -> void:
	var options := _upgrade_library.filter(func(u): return u.slot == slot)
	options.sort_custom(func(a, b): return a.id < b.id)
	var next := options.map(func(u): return u.id).find(run.slot_id(slot)) + 1
	if next >= options.size():
		run.unequip(slot)
	else:
		run.equip(options[next])
	_banner(run.slot_name(slot))


## What enemies aim and dive at: an active Decoy if there is one, else the
## nearest living player.
func aim_target(from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for d in decoys.get_children():
		if d.is_queued_for_deletion():
			continue
		var dist := from.distance_squared_to(d.position)
		if dist < best_d:
			best_d = dist
			best = d
	return best if best else nearest_player(from)


## Swarm dodge, Decoy: a ghost ship that draws fire, then explodes.
func spawn_decoy(p: Player, pos: Vector2, duration: float, damage: float, radius: float) -> void:
	var d := Decoy.new()
	d.position = pos
	d.life = duration
	d.color = p.color
	d.on_expire = func(): _explode(d.position, radius, damage, p.run, p.color)
	decoys.add_child(d)


func nearest_player(from: Vector2) -> Player:
	var best: Player = null
	var best_d := INF
	for p in players:
		if p.run.alive:
			var d := from.distance_squared_to(p.position)
			if d < best_d:
				best_d = d
				best = p
	return best


# --- Rooms -------------------------------------------------------------------

func _start_room(index: int) -> void:
	RunState.room_index = index
	room = world.rooms[index]
	room_time = 0.0
	_spawn_queue.clear()
	var extra := players.size() - 1
	for wave in room.waves:
		var count := int(round(wave.get("count", 1) * (1.0 + SPAWNS_PER_EXTRA_PLAYER * extra)))
		for k in count:
			var y: float = wave.get("y", 180.0) + k * wave.get("dy", 0.0)
			_spawn_queue.append({
				"t": wave.get("time", 0.0) + k * wave.get("interval", 0.3),
				"enemy": wave.get("enemy", "grunt"),
				"y": fposmod(y - 24.0, 312.0) + 24.0,
			})
	if room.is_boss:
		_spawn_queue.append({"t": 1.5, "enemy": "boss", "y": 180.0})
	_spawn_queue.sort_custom(func(a, b): return a.t < b.t)
	for p in players:
		if not p.run.alive:
			p.revive()
	starfield.speed = room.scroll_speed
	state = State.PLAYING
	_banner(world.boss_name + " APPROACHING" if room.is_boss else room.display_name)


func _spawn(entry: Dictionary) -> void:
	var hp_mult := 1.0 + HP_PER_EXTRA_PLAYER * (players.size() - 1)
	if entry.enemy == "boss":
		boss = Boss.new()
		boss.game = self
		boss.setup_boss(hp_mult)
		boss.position = Vector2(720, 180)
		enemies.add_child(boss)
		return
	var e := Enemy.new()
	e.game = self
	e.setup(entry.enemy, hp_mult)
	e.position = Vector2(670, entry.y)
	e.base_y = entry.y
	enemies.add_child(e)


func _physics_process(delta: float) -> void:
	banner_time -= delta
	shake = maxf(shake - delta * 4.0, 0.0)
	world_root.position = (Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * 3.0).round()
	match state:
		State.PLAYING:
			room_time += delta
			while not _spawn_queue.is_empty() and _spawn_queue[0].t <= room_time:
				_spawn(_spawn_queue.pop_front())
			_collide()
			if _spawn_queue.is_empty() and _live_enemy_count() == 0 and room_time > 1.0:
				_room_cleared()
		State.VICTORY, State.GAME_OVER:
			for p in players:
				if p.ctl.pressed("start") or p.ctl.pressed("confirm"):
					get_tree().reload_current_scene()
					return


## An enemy launched mid-fight by a boss (e.g. the Leviathan's grunts).
func spawn_minion(kind: String, pos: Vector2, summoner: Node2D) -> void:
	var e := Enemy.new()
	e.game = self
	e.setup(kind, 1.0 + HP_PER_EXTRA_PLAYER * (players.size() - 1))
	e.position = pos
	e.base_y = pos.y
	e.summoned_by = summoner
	enemies.add_child(e)


func _live_enemy_count() -> int:
	var n := 0
	for e in enemies.get_children():
		if not e.dead:
			n += 1
	return n


func _room_cleared() -> void:
	_clear_enemy_bullets()
	if room.is_boss:
		_end_run(State.VICTORY)
		return
	state = State.PICKING
	_pick_queue = RunState.players.duplicate()
	_next_pick()


func _next_pick() -> void:
	while not _pick_queue.is_empty():
		var run: PlayerRun = _pick_queue.pop_front()
		var options := _roll_options(run)
		if not options.is_empty():
			picker.open(run, players[run.index].ctl, options, PLAYER_COLORS[run.index])
			return
	_start_room(RunState.room_index + 1)


func _roll_options(run: PlayerRun) -> Array:
	var pool := _upgrade_library.filter(func(u): return _can_offer(run, u))
	pool.shuffle()
	return pool.slice(0, 3)


func _can_offer(run: PlayerRun, u: UpgradeData) -> bool:
	if run.primary in u.incompatible_with:
		return false
	return run.stacks(u.id) < u.max_stacks


func _on_upgrade_chosen(run: PlayerRun, u: UpgradeData) -> void:
	if u.slot != "passive":
		run.equip(u)
	else:
		run.upgrades[u.id] = run.stacks(u.id) + 1
	if u.id == "aegis_plating":
		run.max_hull += 1
		run.hull = mini(run.hull + 1, run.max_hull)
	_next_pick()


func _end_run(end_state: State) -> void:
	state = end_state
	MetaProgress.add_run_result(RunState.scrap_earned)
	for p in players:
		p.ctl.sync()


func _banner(text: String) -> void:
	banner_text = text
	banner_time = 2.0


# --- Combat ------------------------------------------------------------------

func spawn_player_bullet(pos: Vector2, vel: Vector2, damage: float, run: PlayerRun, opts := {}) -> void:
	var b := Bullet.new()
	b.position = pos
	b.vel = vel
	b.damage = damage
	b.owner_run = run
	b.color = PLAYER_COLORS[run.index].lightened(0.4)
	b.kind = opts.get("kind", "pellet")
	b.radius = opts.get("radius", 2.0)
	b.explode_radius = opts.get("explode", 0.0)
	b.pierce_left = opts.get("pierce", 0)
	b.fuse = opts.get("fuse", 0.0)
	b.freeze_time = opts.get("freeze", 0.0)
	b.extra = opts.get("extra", {})
	if b.kind == "homing" or b.kind == "reflect":
		b.game = self
		b.rotation = vel.angle()
		b.target = opts.get("target", null)
	player_bullets.add_child(b)


func spawn_enemy_bullet(pos: Vector2, vel: Vector2, shooter: Node2D = null) -> void:
	var b := Bullet.new()
	b.shooter = shooter
	b.position = pos
	b.vel = vel
	b.radius = 4.0
	b.color = Color(1.0, 0.35, 0.7)
	b.enemy_bullet = true
	enemy_bullets.add_child(b)


func _collide() -> void:
	for b in player_bullets.get_children():
		if b.is_queued_for_deletion():
			continue
		if b.fuse_done:
			if b.kind == "ice_bomb":
				_ice_blast(b)
			elif b.kind == "canister":
				_napalm(b)
			else:
				_explode(b.position, b.explode_radius, b.damage, b.owner_run)
				b.queue_free()
			continue
		for e in enemies.get_children():
			if e.dead or e in b.hit_list:
				continue
			if b.position.distance_to(e.position) < b.radius + e.radius:
				b.hit_list.append(e)
				_bullet_hit_enemy(b, e)
				if b.pierce_left <= 0:
					b.queue_free()
					break
				b.pierce_left -= 1
	for b in enemy_bullets.get_children():
		if b.is_queued_for_deletion():
			continue
		for p in players:
			var dist: float = b.position.distance_to(p.position)
			if p.run.alive and p.has_barrier() and dist < b.radius + Player.BARRIER_RADIUS:
				_effect("explosion", b.position, 0.15, 7.0, AEGIS_COLOR)
				b.queue_free()
				break
			if p.can_be_hit() and dist < b.radius + Player.HITBOX:
				p.take_hit()
				b.queue_free()
				break
			if dist < b.radius + Player.GRAZE_RADIUS:
				p.on_graze(b.position)
	for e in enemies.get_children():
		if e.dead:
			continue
		for p in players:
			if p.can_be_hit() and e.position.distance_to(p.position) < e.radius + Player.HITBOX + 3.0:
				p.take_hit()
				if not e is Boss:
					e.take_damage(5.0, p.run)


func _bullet_hit_enemy(b: Bullet, e: Enemy) -> void:
	var run := b.owner_run
	match b.kind:
		"lance":
			_frost_hit(e, b.damage, run)
		"ice_bomb":
			_ice_blast(b)
			return
		"canister":
			_napalm(b)
			return
		_:
			if b.explode_radius > 0.0:
				_explode(b.position, b.explode_radius, b.damage, run)
			else:
				e.take_damage(b.damage, run)
	_apply_on_hit(e, b.damage, run)


## Add-on effects shared by every weapon, including the beam.
func _apply_on_hit(e: Enemy, damage: float, run: PlayerRun) -> void:
	if run.stacks("acid_corrode") > 0:
		e.add_acid(run.stacks("acid_corrode"), run)
	if run.stacks("cryo_frost") > 0:
		e.apply_slow(FROST_WAKE_SLOW, SLOW_DURATION)
	var arc := run.stacks("volt_arc")
	if arc > 0 and randf() < 0.25 * arc:
		var target := _nearest_enemy(e.position, 93.0, [e])
		if target:
			target.take_damage(damage * 0.5, run)
			_effect("arc", e.position, 0.15, 0.0, LIGHTNING_COLOR, target.position)


func nearest_enemy(from: Vector2, max_dist: float) -> Enemy:
	return _nearest_enemy(from, max_dist, [])


## Lightning: arc from `origin` (default: the ship's nose) to the target, then
## chain onward. `chains` = -1 uses the weapon's normal 1 + level.
func lightning_zap(p: Player, target: Enemy, damage: float, origin := Vector2.INF, chains := -1) -> void:
	var run := p.run
	var from := p.position + Vector2(24, 0) if origin == Vector2.INF else origin
	_effect("arc", from, 0.2, 0.0, LIGHTNING_COLOR, target.position)
	target.take_damage(damage, run)
	_apply_on_hit(target, damage, run)
	_chain_lightning(target, damage * 0.7, 1 + run.primary_level() if chains < 0 else chains, run)


## Volt secondary, Storm Burst: arcs from the ship to the nearest enemies in range.
func storm_burst(p: Player, damage: float, max_targets: int, burst_range: float) -> void:
	_effect("ring", p.position, 0.3, burst_range, LIGHTNING_COLOR)
	var targets := enemies.get_children().filter(
		func(e): return not e.dead and e.position.distance_to(p.position) <= burst_range)
	targets.sort_custom(func(a, b): return a.position.distance_squared_to(p.position) < b.position.distance_squared_to(p.position))
	for e in targets.slice(0, max_targets):
		_effect("arc", p.position, 0.25, 0.0, LIGHTNING_COLOR, e.position)
		e.take_damage(damage, p.run)
		_apply_on_hit(e, damage, p.run)


## Cryo secondary, Ice Blast: the bomb bursts, damaging and freezing every
## enemy in its radius.
func _ice_blast(b: Bullet) -> void:
	_effect("ring", b.position, 0.35, b.explode_radius, ICE_COLOR)
	_effect("explosion", b.position, 0.25, b.explode_radius * 0.5, ICE_COLOR)
	for e in enemies.get_children():
		if not e.dead and e.position.distance_to(b.position) <= b.explode_radius + e.radius:
			e.freeze(b.freeze_time)
			e.take_damage(b.damage, b.owner_run)
	b.queue_free()


## Acid/Fire secondary, Napalm Line: the canister lands and leaves a strip of
## fire running the full height of the screen; enemies inside gain acid stacks.
func _napalm(b: Bullet) -> void:
	var run := b.owner_run
	var x: float = clampf(b.position.x, 14.0, 626.0)
	var h := Hazard.new()
	h.position = Vector2(x, 0)
	h.rect = Rect2(-b.extra.width / 2.0, 0, b.extra.width, 360)
	h.life = b.extra.duration
	h.max_life = h.life
	h.tick = b.extra.tick
	h.look = "napalm"
	h.enemies_node = enemies
	var power: int = b.extra.power
	h.on_tick = func(inside: Array):
		for e in inside:
			e.add_acid(power, run)
	hazards.add_child(h)
	_effect("explosion", b.position, 0.25, 19.0, Color(1, 0.55, 0.15))
	b.queue_free()


## Acid/Fire dodge, Scorch Trail: one burning patch on the dash path.
func scorch_patch(p: Player, pos: Vector2, radius: float, duration: float, power: int, damage: float) -> void:
	var run := p.run
	var h := Hazard.new()
	h.position = pos
	h.radius = radius
	h.life = duration
	h.max_life = duration
	h.tick = 0.3
	h.look = "scorch"
	h.enemies_node = enemies
	h.on_tick = func(inside: Array):
		for e in inside:
			e.add_acid(power, run)
			e.take_damage(damage, run, false)
	hazards.add_child(h)


## Phase Shift graze feedback: a small bright flash where the bullet passed.
func graze_spark(at: Vector2) -> void:
	_effect("explosion", at, 0.2, 11.0, AEGIS_COLOR)


## Aegis secondary, Repulsor: every enemy bullet within `radius` is sent back,
## steering toward the enemy that fired it; enemies in the blast take damage.
func repulsor(p: Player, radius: float, bullet_damage: float, blast_damage: float) -> int:
	_effect("ring", p.position, 0.3, radius, AEGIS_COLOR)
	var returned := 0
	for b in enemy_bullets.get_children():
		if b.is_queued_for_deletion() or b.position.distance_to(p.position) > radius:
			continue
		var target = b.shooter if is_instance_valid(b.shooter) and not b.shooter.dead else null
		var dir: Vector2 = (target.position - b.position).normalized() if target else -b.vel.normalized()
		spawn_player_bullet(b.position, dir * 293.0, bullet_damage, p.run, {
			"kind": "reflect", "radius": 4.0, "target": target, "fuse": 3.0})
		b.queue_free()
		returned += 1
	for e in enemies.get_children():
		if not e.dead and e.position.distance_to(p.position) <= radius + e.radius:
			e.take_damage(blast_damage, p.run)
	return returned


## Nova dodge, Afterburner: an explosion where the dash started.
func afterburner(p: Player, pos: Vector2, damage: float, radius: float) -> void:
	_explode(pos, radius, damage, p.run)


## Cryo dodge, Frost Step: enemies near the dodging ship are slowed.
func frost_step(p: Player, slow: float, duration: float, reach: float) -> void:
	for e in enemies.get_children():
		if not e.dead and e.position.distance_to(p.position) <= reach + e.radius:
			e.apply_slow(slow, duration)


## Volt dodge, Static Dash: zap enemies the dodging ship passes close to, once
## each per dodge. `already_hit` is the player's list for the current dodge.
func static_dash(p: Player, damage: float, reach: float, already_hit: Array) -> void:
	for e in enemies.get_children():
		if e.dead or e in already_hit:
			continue
		if e.position.distance_to(p.position) <= reach + e.radius:
			already_hit.append(e)
			_effect("arc", p.position, 0.2, 0.0, LIGHTNING_COLOR, e.position)
			e.take_damage(damage, p.run)
			_apply_on_hit(e, damage, p.run)


## Jump from enemy to enemy, never hitting the same one twice.
func _chain_lightning(from_e: Enemy, damage: float, jumps: int, run: PlayerRun) -> void:
	var hit: Array = [from_e]
	var cur := from_e
	for j in jumps:
		var target := _nearest_enemy(cur.position, 107.0, hit)
		if target == null:
			return
		_effect("arc", cur.position, 0.2, 0.0, LIGHTNING_COLOR, target.position)
		target.take_damage(damage, run)
		hit.append(target)
		cur = target


## Frost Lance: every hit slows the enemy and restarts the slow timer.
func _frost_hit(e: Enemy, damage: float, run: PlayerRun) -> void:
	e.take_damage(damage, run)
	e.apply_slow(FROST_LANCE_SLOW, SLOW_DURATION)


## Corrosive Beam: the first enemy in the beam's path, if any.
func beam_target(from: Vector2, half_width: float) -> Enemy:
	var best: Enemy = null
	for e in enemies.get_children():
		if e.dead or e.position.x < from.x:
			continue
		if absf(e.position.y - from.y) < e.radius + half_width:
			if best == null or e.position.x < best.position.x:
				best = e
	return best


func beam_hit(p: Player, e: Enemy, damage: float) -> void:
	var run := p.run
	e.take_damage(damage, run)
	p.beam_ticks += 1
	if p.beam_ticks % 3 == 0:
		e.add_acid(run.primary_level() + run.stacks("acid_corrode"), run)
	if run.stacks("cryo_frost") > 0:
		e.apply_slow(FROST_WAKE_SLOW, SLOW_DURATION)


func _nearest_enemy(from: Vector2, max_dist: float, exclude: Array) -> Enemy:
	var best: Enemy = null
	var best_d := max_dist
	for e in enemies.get_children():
		if e in exclude or e.dead:
			continue
		var d := from.distance_to(e.position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _explode(pos: Vector2, r: float, damage: float, run: PlayerRun, color := Color(1, 0.6, 0.2)) -> void:
	_effect("explosion", pos, 0.25, r, color)
	for e in enemies.get_children():
		if not e.dead and e.position.distance_to(pos) < r + e.radius:
			e.take_damage(damage, run)


func bomb(p: Player) -> void:
	_clear_enemy_bullets()
	hud.flash = 0.4
	shake = maxf(shake, 1.0)
	for e in enemies.get_children():
		if not e.dead:
			e.take_damage(6.0, p.run)


func _clear_enemy_bullets() -> void:
	for b in enemy_bullets.get_children():
		b.queue_free()


func on_enemy_killed(e: Enemy, run: PlayerRun) -> void:
	RunState.scrap_earned += e.scrap
	_effect("explosion", e.position, 0.35, e.radius * 2.0, e.color)
	if run:
		run.kills += 1
		run.credits += e.scrap
		if run.stacks("aegis_repair") > 0 and run.kills % 8 == 0:
			run.hull = mini(run.hull + 1, run.max_hull)
	if e == boss:
		boss = null
		shake = 1.5
		_clear_enemy_bullets()
		# Its drones and launched grunts go down with it (no extra Scrap).
		for m in enemies.get_children():
			if not m.dead and m.summoned_by == e:
				m.dead = true
				_effect("explosion", m.position, 0.35, m.radius * 2.0, m.color)
				m.queue_free()


func on_player_down(p: Player) -> void:
	_effect("explosion", p.position, 0.6, 32.0, p.color)
	if RunState.alive_count() == 0:
		_end_run(State.GAME_OVER)


func _effect(kind: String, pos: Vector2, life: float, radius: float, color: Color, target := Vector2.ZERO) -> void:
	var fx := Effect.new()
	fx.kind = kind
	fx.position = pos
	fx.life = life
	fx.max_life = life
	fx.radius = radius
	fx.color = color
	fx.target = target
	effects.add_child(fx)
