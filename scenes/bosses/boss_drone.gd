class_name BossDrone
extends Enemy
## Released by the Salvage Leviathan at half HP: one drone takes the top half of
## the screen, the other the bottom. Each repeats: glide to a new height,
## telegraph with a thin flickering line, then fire a thick horizontal beam
## across the screen. The two beams are parallel; the gaps are where to dodge.

const BASE_HP := 60.0
const HOVER_X := 470.0
const LANES := [Vector2(40, 160), Vector2(200, 320)]  # y range: top, bottom
const MOVE_TIME := 1.5
const TELEGRAPH_TIME := 1.0
const FIRE_TIME := 1.0
const BEAM_HALF := 6.0

var lane := 0
var boss: Node2D
var state := "move"
var state_time := 0.0
var target_y := 0.0


func setup_drone(p_lane: int, hp_mult: float, p_boss: Node2D) -> void:
	kind = "boss_drone"
	lane = p_lane
	boss = p_boss
	summoned_by = p_boss
	max_hp = BASE_HP * hp_mult
	hp = max_hp
	radius = 12.0
	color = Color(0.55, 0.6, 0.7)
	scrap = 10
	_pick_target()


func _pick_target() -> void:
	var r: Vector2 = LANES[lane]
	target_y = randf_range(r.x, r.y)


func is_beam_firing() -> bool:
	return state == "fire"


func _move(delta: float) -> void:
	state_time += delta
	match state:
		"move":
			position.x = move_toward(position.x, HOVER_X, 160.0 * delta)
			position.y = move_toward(position.y, target_y, 140.0 * delta)
			if state_time >= MOVE_TIME:
				_set_state("telegraph")
		"telegraph":
			if state_time >= TELEGRAPH_TIME:
				_set_state("fire")
				game.shake = maxf(game.shake, 0.3)
		"fire":
			if state_time >= FIRE_TIME:
				_pick_target()
				_set_state("move")


func _set_state(s: String) -> void:
	state = s
	state_time = 0.0


func _update_fire(_delta: float) -> void:
	if state != "fire":
		return
	for p in game.players:
		if p.can_be_hit() and p.position.x < position.x and absf(p.position.y - position.y) < BEAM_HALF + Player.HITBOX:
			p.take_hit()


func _draw() -> void:
	if frozen_timer > 0.0:
		pass  # a frozen drone's beam is held, so don't draw it
	elif state == "telegraph" and int(state_time * 16.0) % 2 == 0:
		draw_line(Vector2(-radius, 0), Vector2(-position.x, 0), Color(1.0, 0.3, 0.4, 0.7), 1.0)
	elif state == "fire":
		var w := BEAM_HALF * (1.0 - 0.25 * sin(state_time * 40.0))
		draw_rect(Rect2(-position.x, -w - 2, position.x - radius, w * 2 + 4), Color(1.0, 0.2, 0.35, 0.45))
		draw_rect(Rect2(-position.x, -w, position.x - radius, w * 2), Color(1.0, 0.45, 0.55, 0.85))
		draw_rect(Rect2(-position.x, -1.5, position.x - radius, 3), Color(1, 0.95, 0.95))
	draw_body(self, Vector2.ZERO, Color.WHITE if flash > 0.0 else color)
	_draw_status()


## Shared with the boss, which draws the drones docked on its hull.
static func draw_body(canvas: CanvasItem, at: Vector2, c: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(-12, 0), at + Vector2(0, -10), at + Vector2(12, 0), at + Vector2(0, 10)]), c)
	canvas.draw_rect(Rect2(at + Vector2(-16, -2), Vector2(6, 4)), c.darkened(0.4))
	canvas.draw_circle(at, 3.0, Color(1.0, 0.3, 0.4))
