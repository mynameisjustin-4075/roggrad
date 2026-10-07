class_name Hud
extends Node2D
## Per-player hull, bombs and credits, room name, banners, boss bar and end screens.

var game
var flash := 0.0


func _process(delta: float) -> void:
	flash = maxf(flash - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for p in game.players:
		var run: PlayerRun = p.run
		var x := 6.0 + run.index * 118.0
		draw_string(font, Vector2(x, 12), "P%d" % (run.index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, p.color)
		for h in run.max_hull:
			draw_rect(Rect2(x + 18 + h * 7, 4, 5, 7), p.color if h < run.hull else Color(0.25, 0.25, 0.3))
		for b in run.bombs:
			draw_circle(Vector2(x + 21 + b * 6, 17), 2.0, Color(1, 0.5, 0.3))
		if run.alive:
			_cooldown_bar(Vector2(x + 18, 25), 1.0 - p.dodge_cooldown / Player.DODGE_COOLDOWN, p.color)
			_cooldown_bar(Vector2(x + 38, 25), 1.0 - p.secondary_cooldown / p.secondary().cooldown, Color(1, 0.85, 0.5))
		draw_string(font, Vector2(x + 18 + run.max_hull * 7 + 4, 12), "%dc" % run.credits, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.8, 0.8, 0.5))
		if run.alive:
			var weapon_name := run.primary_name + (" %d" % run.primary_level() if run.primary != "" else "")
			draw_string(font, Vector2(x + 34, 21), weapon_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.7, 0.7, 0.8))
		else:
			draw_string(font, Vector2(x + 34, 21), "DOWN", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.3, 0.3))
	if game.room:
		draw_string(font, Vector2(0, 264), game.room.display_name, HORIZONTAL_ALIGNMENT_RIGHT, 474, 8, Color(0.6, 0.6, 0.7))
	if game.state == Game.State.PLAYING and RunState.room_index == 0 and game.players.size() < 4:
		draw_string(font, Vector2(6, 264), "Press Start on another controller to join", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.6, 0.6, 0.7))
	if game.banner_time > 0.0:
		draw_string(font, Vector2(0, 110), game.banner_text, HORIZONTAL_ALIGNMENT_CENTER, 480, 16, Color(1, 1, 1, clampf(game.banner_time, 0.0, 1.0)))
	_draw_boss_bar(font)
	if flash > 0.0:
		draw_rect(Rect2(0, 0, 480, 270), Color(1, 1, 1, flash))
	if game.state == Game.State.VICTORY or game.state == Game.State.GAME_OVER:
		_draw_end_screen(font)


## A 16x2 bar: full and bright when ready, dim while recharging.
func _cooldown_bar(pos: Vector2, ready: float, color: Color) -> void:
	ready = clampf(ready, 0.0, 1.0)
	draw_rect(Rect2(pos, Vector2(16, 2)), Color(0.2, 0.2, 0.25))
	draw_rect(Rect2(pos, Vector2(16 * ready, 2)), color if ready >= 1.0 else Color(color, 0.45))


func _draw_boss_bar(font: Font) -> void:
	var boss = game.boss
	if boss == null or not is_instance_valid(boss) or boss.dead:
		return
	draw_string(font, Vector2(90, 248), game.world.boss_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.8, 0.8))
	draw_rect(Rect2(90, 251, 300, 5), Color(0.2, 0.1, 0.1))
	draw_rect(Rect2(90, 251, 300.0 * maxf(boss.hp, 0.0) / boss.max_hp, 5), Color(0.9, 0.2, 0.2))


func _draw_end_screen(font: Font) -> void:
	draw_rect(Rect2(0, 0, 480, 270), Color(0, 0, 0, 0.65))
	var won: bool = game.state == Game.State.VICTORY
	draw_string(font, Vector2(0, 100), "WORLD CLEAR" if won else "ALL SHIPS DESTROYED", HORIZONTAL_ALIGNMENT_CENTER, 480, 20, Color(0.6, 1, 0.6) if won else Color(1, 0.4, 0.4))
	draw_string(font, Vector2(0, 130), "Scrap earned: %d     Total Scrap: %d" % [RunState.scrap_earned, MetaProgress.scrap], HORIZONTAL_ALIGNMENT_CENTER, 480, 10, Color.WHITE)
	draw_string(font, Vector2(0, 160), "Press Start / Enter to fly again", HORIZONTAL_ALIGNMENT_CENTER, 480, 10, Color(0.7, 0.7, 0.8))
