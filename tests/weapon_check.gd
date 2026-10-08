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
	await _check_nova(game, p)
	await _check_swarm(game, p)
	await _check_aegis(game, p)
	await _check_acid(game, p)


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
	var durations: Array = []
	for i in 5:
		boss.frozen_timer = 0.0
		boss.freeze(3.0)
		durations.append(snappedf(boss.frozen_timer, 0.01))
	print("Boss freeze, 5 bombs in a row: %s s" % str(durations))
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


func _check_nova(game: Game, p: Player) -> void:
	_equip(game, p.run, "nova_homing")
	_equip(game, p.run, "nova_afterburner")
	_clear_enemies(game)
	await _frames(400, game)
	# Homing Cluster: a fragile dummy ahead dies to the first hits; the rest
	# of the swarm must retarget onto a tough dummy behind the ship.
	p.position = Vector2(200, 135)
	var fragile := _spawn_dummy(game, Vector2(300, 135))
	fragile.hp = 2.0
	var behind := _spawn_dummy(game, Vector2(80, 60))
	Input.action_press("secondary")
	await _frames(2, game)
	Input.action_release("secondary")
	var fired := game.player_bullets.get_children().filter(func(b): return b.kind == "homing").size()
	await _frames(240, game)
	print("Homing Cluster: fired %d, fragile destroyed %s, retargeted onto enemy behind (damage %.1f), cooldown %.1f s" % [
		fired, not is_instance_valid(fragile) or fragile.dead, behind.max_hp - behind.hp, p.secondary_cooldown])
	# Afterburner: dash away from a dummy sitting at the start point.
	_clear_enemies(game)
	await _frames(100, game)
	p.position = Vector2(150, 135)
	var at_start := _spawn_dummy(game, Vector2(165, 145))
	var far := _spawn_dummy(game, Vector2(400, 40))
	Input.action_press("move_left")
	Input.action_press("dodge")
	await _frames(2, game)
	Input.action_release("dodge")
	Input.action_release("move_left")
	print("Afterburner: start-point damage %.1f, far untouched %s" % [at_start.max_hp - at_start.hp, far.hp == far.max_hp])


func _check_swarm(game: Game, p: Player) -> void:
	p.run.upgrades["swarm_option"] = 2
	_clear_enemies(game)
	await _frames(30, game)
	# Drones copy the main weapon: one main volley + 2 drone shots of the same kind.
	var copies := []
	for id in ["", "cryo_lance", "nova_missiles"]:
		if id == "":
			p.run.unequip("primary")
		else:
			_equip(game, p.run, id)
		for b in game.player_bullets.get_children():
			b.queue_free()
		await _frames(1, game)
		p.fire_timer = 0.0
		p._fire()
		var kind: String = p.weapon().kind
		copies.append("%s x%d" % [kind, game.player_bullets.get_children().filter(func(b): return b.kind == kind and not b.is_queued_for_deletion()).size()])
	print("Drone copies (main + 2 drones): %s" % ", ".join(copies))
	p.run.unequip("primary")
	# Swarm Strike: 4 drones orbit and shoot an enemy directly behind the ship.
	_equip(game, p.run, "swarm_strike")
	_equip(game, p.run, "swarm_decoy")
	await _frames(400, game)
	p.position = Vector2(250, 135)
	var behind := _spawn_dummy(game, Vector2(120, 135))
	Input.action_press("secondary")
	await _frames(2, game)
	Input.action_release("secondary")
	var orbiting := p.drone_offsets().size()
	Input.action_press("fire")
	await _frames(60, game)
	Input.action_release("fire")
	var behind_dmg: float = behind.max_hp - behind.hp
	await _frames(330, game)
	print("Swarm Strike: %d drones orbiting, enemy behind took %.1f, after 6.5 s drones back to %d" % [orbiting, behind_dmg, p.drone_offsets().size()])
	# Decoy: a gunner aims at the decoy, which then explodes on a nearby dummy.
	_clear_enemies(game)
	await _frames(100, game)
	p.position = Vector2(100, 135)
	var gunner := _spawn_dummy(game, Vector2(350, 60))
	var beside := _spawn_dummy(game, Vector2(115, 150))
	Input.action_press("move_up")
	Input.action_press("dodge")
	await _frames(2, game)
	Input.action_release("dodge")
	await _frames(10, game)
	Input.action_release("move_up")
	var aimed_at = game.aim_target(gunner.position)
	var aims_decoy: bool = aimed_at is Decoy
	await _frames(130, game)
	print("Decoy: enemies aim at decoy %s, decoy exploded on the dummy beside it (damage %.1f), aim back on player %s" % [
		aims_decoy, beside.max_hp - beside.hp, game.aim_target(gunner.position) == p])


func _check_aegis(game: Game, p: Player) -> void:
	p.run.upgrades.erase("swarm_option")
	_equip(game, p.run, "aegis_repulsor")
	_equip(game, p.run, "aegis_phase")
	_clear_enemies(game)
	game._clear_enemy_bullets()
	await _frames(400, game)
	# Repulsor: 3 bullets from a distant gunner near the ship, 1 stray far away.
	p.position = Vector2(100, 135)
	var gunner := _spawn_dummy(game, Vector2(380, 60))
	for off in [Vector2(30, 0), Vector2(20, -40), Vector2(-30, 30)]:
		game.spawn_enemy_bullet(p.position + off, Vector2.ZERO, gunner)
	game.spawn_enemy_bullet(Vector2(400, 250), Vector2.ZERO, gunner)
	await _frames(1, game)
	Input.action_press("secondary")
	await _frames(2, game)
	Input.action_release("secondary")
	var reflected := game.player_bullets.get_children().filter(func(b): return b.kind == "reflect").size()
	var enemy_left := game.enemy_bullets.get_children().filter(func(b): return not b.is_queued_for_deletion()).size()
	await _frames(150, game)
	print("Repulsor: reflected %d/3, stray bullet kept %s, shooter took %.1f damage" % [
		reflected, enemy_left == 1, gunner.max_hp - gunner.hp])
	# Phase Shift: longer i-frames; a bullet grazing the ship refunds half the cooldown.
	_clear_enemies(game)
	game._clear_enemy_bullets()
	await _frames(100, game)
	p.position = Vector2(200, 135)
	Input.action_press("dodge")
	await _frames(2, game)
	Input.action_release("dodge")
	var iframes := p._dodge_iframes_total
	var cd_before := p.dodge_cooldown
	game.spawn_enemy_bullet(p.position + Vector2(8, 0), Vector2.ZERO)
	await _frames(2, game)
	print("Phase Shift: i-frames %.2f s, cooldown %.2f -> %.2f s after graze, hull %d/%d" % [
		iframes, cd_before, p.dodge_cooldown, p.run.hull, p.run.max_hull])


func _check_acid(game: Game, p: Player) -> void:
	_equip(game, p.run, "acid_napalm")
	_equip(game, p.run, "acid_scorch")
	_clear_enemies(game)
	game._clear_enemy_bullets()
	await _frames(450, game)
	# Napalm Line: canister hits a dummy at x=200; the strip covers that column
	# from top to bottom, so dummies at the top and bottom burn too.
	p.position = Vector2(100, 135)
	var hit := _spawn_dummy(game, Vector2(200, 135))
	var top := _spawn_dummy(game, Vector2(204, 20))
	var bottom := _spawn_dummy(game, Vector2(196, 250))
	var aside := _spawn_dummy(game, Vector2(300, 40))
	Input.action_press("secondary")
	await _frames(2, game)
	Input.action_release("secondary")
	await _frames(60, game)
	var in_strip := [hit, top, bottom].filter(func(e): return e.acid_stacks > 0).size()
	await _frames(240, game)
	var strips_left := game.hazards.get_children().filter(func(h): return not h.is_queued_for_deletion()).size()
	print("Napalm Line: burning %d/3 in the strip, outside burning %s, strip gone after 5 s %s, cooldown %.1f s" % [
		in_strip, aside.acid_stacks > 0, strips_left == 0, secondary_cd(p)])
	# Scorch Trail: dash right past one dummy on the path; one dummy well away.
	_clear_enemies(game)
	await _frames(100, game)
	p.position = Vector2(100, 135)
	var on_path := _spawn_dummy(game, Vector2(130, 140))
	var off_path := _spawn_dummy(game, Vector2(130, 220))
	on_path.radius = 2.0  # small target: it only burns if it sits right on the trail
	Input.action_press("move_right")
	Input.action_press("dodge")
	await _frames(2, game)
	Input.action_release("dodge")
	await _frames(12, game)
	Input.action_release("move_right")
	await _frames(30, game)
	print("Scorch Trail: patches dropped %d, on-path acid %d (damage %.1f), off-path acid %d" % [
		game.hazards.get_child_count(), on_path.acid_stacks, on_path.max_hp - on_path.hp, off_path.acid_stacks])


func secondary_cd(p: Player) -> float:
	return p.secondary_cooldown
