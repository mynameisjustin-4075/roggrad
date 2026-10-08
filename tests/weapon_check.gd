extends Node
## Headless smoke test for primary weapons. Run:
##   godot --headless --path . res://tests/weapon_check.tscn
## Fires each weapon for 4 s at 3 tough, stationary gunners and prints what
## happened to them.

const PRIMARIES := ["", "volt_lightning", "cryo_lance", "nova_missiles", "acid_beam"]


func _ready() -> void:
	var game: Game = load("res://scenes/main/main.tscn").instantiate()
	add_child(game)
	await get_tree().physics_frame
	game.god_mode = true
	game._spawn_queue.clear()
	var p: Player = game.players[0]
	p.run.upgrades["swarm_option"] = 2
	Input.action_press("fire")
	for id in PRIMARIES:
		for e in game.enemies.get_children():
			e.dead = true
			e.queue_free()
		for b in game.player_bullets.get_children():
			b.queue_free()
		_equip(game, p.run, id)
		p.position = Vector2(60, 135)
		var targets: Array = []
		for i in 3:
			var e := Enemy.new()
			e.game = game
			e.setup("gunner", 20.0)
			e.speed = 0.0
			e.fire_mode = ""
			e.position = Vector2(200 + i * 30, 135 + i * 12)
			e.base_y = e.position.y
			game.enemies.add_child(e)
			targets.append(e)
		var slowed := 0
		var max_acid := 0
		var fx := 0
		for f in 240:
			game.state = Game.State.PLAYING
			game.room_time = -100.0
			await get_tree().physics_frame
			for e in targets:
				if e.slow_timer > 0.0:
					slowed += 1
				max_acid = maxi(max_acid, e.acid_stacks)
			fx = maxi(fx, game.effects.get_child_count())
		var dmg := targets.map(func(e): return snappedf(e.max_hp - e.hp, 0.1))
		print("%-15s damage per target %s  slowed-frames %d  max acid %d  peak effects %d" % [p.run.primary_name, str(dmg), slowed, max_acid, fx])
	Input.action_release("fire")
	await _check_abilities(game, p)
	get_tree().quit()


func _frames(n: int, game: Game) -> void:
	for f in n:
		game.state = Game.State.PLAYING
		game.room_time = -100.0
		await get_tree().physics_frame


func _check_abilities(game: Game, p: Player) -> void:
	game.god_mode = false
	for e in game.enemies.get_children():
		e.dead = true
		e.queue_free()
	await _frames(70, game)  # let any old cooldowns expire
	# Dodge down: should dash ~57 px, be unhittable, then refuse a second dodge.
	p.position = Vector2(100, 100)
	Input.action_press("move_down")
	Input.action_press("dodge")
	await _frames(2, game)
	var hittable_during := p.can_be_hit()
	Input.action_release("dodge")
	await _frames(12, game)
	Input.action_release("move_down")
	var moved := p.position.y - 100.0
	await _frames(12, game)  # i-frames (21 frames) over, cooldown (72 frames) not
	Input.action_press("dodge")
	await _frames(2, game)
	Input.action_release("dodge")
	print("Dodge: moved %.0f px, hittable during dodge: %s, second dodge blocked: %s, hittable after: %s" % [
		moved, hittable_during, p.dodge_cooldown > 0.0 and p.dodge_iframes == 0.0, p.can_be_hit()])
	# Secondary: a tap fires one shot and starts a 4 s cooldown; a retry is blocked.
	var before := game.player_bullets.get_child_count()
	Input.action_press("secondary")
	await _frames(30, game)
	Input.action_release("secondary")
	await _frames(1, game)
	var shots := 0
	for b in game.player_bullets.get_children():
		if b.kind == "charge":
			shots += 1
	var cd := p.secondary_cooldown
	Input.action_press("secondary")
	await _frames(30, game)
	Input.action_release("secondary")
	await _frames(1, game)
	var shots_after := 0
	for b in game.player_bullets.get_children():
		if b.kind == "charge":
			shots_after += 1
	print("Secondary: charge shots fired %d, cooldown %.1f s, extra shots during cooldown %d" % [shots, cd, shots_after - shots])
	await _check_volt(game, p)


func _spawn_dummy(game: Game, pos: Vector2) -> Enemy:
	var e := Enemy.new()
	e.game = game
	e.setup("gunner", 20.0)
	e.speed = 0.0
	e.fire_mode = ""
	e.position = pos
	e.base_y = pos.y
	game.enemies.add_child(e)
	return e


func _clear_enemies(game: Game) -> void:
	for e in game.enemies.get_children():
		e.dead = true
		e.queue_free()


func _check_volt(game: Game, p: Player) -> void:
	p.run.unequip("primary")
	p.run.upgrades.erase("swarm_option")
	_equip(game, p.run, "volt_storm")
	_equip(game, p.run, "volt_static")
	game.god_mode = true
	_clear_enemies(game)
	await _frames(400, game)  # let cooldowns expire
	# Storm Burst: 8 dummies, 6 inside 150 px plus 2 far away -> exactly 6 hit.
	p.position = Vector2(150, 135)
	var dummies: Array = []
	for i in 6:
		dummies.append(_spawn_dummy(game, p.position + Vector2.from_angle(TAU * i / 6.0) * (60 + i * 12)))
	dummies.append(_spawn_dummy(game, Vector2(420, 40)))
	dummies.append(_spawn_dummy(game, Vector2(420, 230)))
	Input.action_press("secondary")
	await _frames(2, game)
	Input.action_release("secondary")
	var hit := dummies.filter(func(e): return e.hp < e.max_hp).size()
	print("Storm Burst: hit %d of 8 (6 in range), cooldown %.1f s, HUD name '%s'" % [hit, p.secondary_cooldown, p.run.secondary_name])
	# Static Dash: dash right past 2 dummies 20 px off the path; 1 dummy far below.
	_clear_enemies(game)
	await _frames(2, game)
	p.position = Vector2(100, 100)
	var near_a := _spawn_dummy(game, Vector2(125, 120))
	var near_b := _spawn_dummy(game, Vector2(150, 80))
	var far := _spawn_dummy(game, Vector2(130, 200))
	Input.action_press("move_right")
	Input.action_press("dodge")
	await _frames(3, game)
	Input.action_release("dodge")
	await _frames(20, game)
	Input.action_release("move_right")
	print("Static Dash: near hits %d/2 (damage %.1f each), far untouched %s, dodge cooldown set %.2f s" % [
		[near_a, near_b].filter(func(e): return e.hp < e.max_hp).size(),
		near_a.max_hp - near_a.hp, far.hp == far.max_hp, p.dodge_cooldown_time()])
	await _check_cryo(game, p)


func _equip(game: Game, run: PlayerRun, id: String) -> void:
	if id == "":
		return
	for u in game._upgrade_library:
		if u.id == id:
			run.equip(u)


func _check_cryo(game: Game, p: Player) -> void:
	_equip(game, p.run, "cryo_ice")
	_equip(game, p.run, "cryo_frost_step")
	_clear_enemies(game)
	await _frames(400, game)
	# Ice Blast on impact: 3 dummies clustered ahead, 1 well outside the blast.
	p.position = Vector2(100, 135)
	var cluster := [_spawn_dummy(game, Vector2(200, 135)), _spawn_dummy(game, Vector2(215, 160)), _spawn_dummy(game, Vector2(220, 110))]
	var outside := _spawn_dummy(game, Vector2(200, 230))
	Input.action_press("secondary")
	await _frames(2, game)
	Input.action_release("secondary")
	await _frames(40, game)
	var frozen := cluster.filter(func(e): return e.frozen_timer > 0.0).size()
	print("Ice Blast impact: frozen %d/3 (%.1f s left), outside frozen: %s, cooldown %.1f s" % [
		frozen, cluster[0].frozen_timer, outside.frozen_timer > 0.0, p.secondary_cooldown])
	# Ice Blast fuse: nothing in the way; it should burst ~176 px out and freeze a dummy there.
	_clear_enemies(game)
	await _frames(400, game)
	p.position = Vector2(100, 60)
	var at_fuse := _spawn_dummy(game, Vector2(100 + 10 + 176, 60 + 28))
	Input.action_press("secondary")
	await _frames(2, game)
	Input.action_release("secondary")
	await _frames(60, game)
	print("Ice Blast fuse: burst on its own and froze the dummy: %s" % (at_fuse.frozen_timer > 0.0))
	# Boss diminishing returns: two 3 s freezes in a row.
	_clear_enemies(game)
	var boss := Boss.new()
	boss.game = game
	boss.setup_boss(1.0)
	boss.position = Vector2(380, 135)
	game.enemies.add_child(boss)
	boss.freeze(3.0)
	var first := boss.frozen_timer
	boss.frozen_timer = 0.0
	boss.freeze(3.0)
	print("Boss freeze: first %.2f s, second %.2f s" % [first, boss.frozen_timer])
	# Frost Step: dodge next to a dummy -> slowed to 0.5 for 2 s.
	_clear_enemies(game)
	await _frames(100, game)
	p.position = Vector2(100, 100)
	var near := _spawn_dummy(game, Vector2(120, 110))
	var far := _spawn_dummy(game, Vector2(300, 220))
	Input.action_press("dodge")
	await _frames(2, game)
	Input.action_release("dodge")
	print("Frost Step: near slowed to %.1f for %.1f s, far slowed: %s" % [near.slow_mult, near.slow_timer, far.slow_timer > 0.0])
