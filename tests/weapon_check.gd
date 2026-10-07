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
	get_tree().quit()


func _equip(game: Game, run: PlayerRun, id: String) -> void:
	if id == "":
		return
	for u in game._upgrade_library:
		if u.id == id:
			run.take_primary(u)
