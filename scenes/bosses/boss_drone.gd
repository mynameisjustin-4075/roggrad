class_name BossDrone
extends Enemy
## Beam drone released by the Salvage Leviathan in phase 2. The boss directs it:
## where to fly (`target`, `move_speed`), where to aim (`aim`, radians) and
## what to do (`mode`: "idle", "telegraph" = flickering warning line,
## "fire" = beam). The beam runs from the drone along `aim` off the screen.

const BASE_HP := 100.0
const BEAM_HALF := 6.0
const BEAM_LENGTH := 900.0

var lane := 0  # 0 = top half, 1 = bottom half
var boss: Node2D
var mode := "idle"
var target := Vector2.ZERO
var move_speed := 200.0
var aim := PI
var _mode_time := 0.0


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


func _move(delta: float) -> void:
	position = position.move_toward(target, move_speed * delta)
	_mode_time += delta


## Is `point` within the beam (plus `extra` px)? The beam only goes forward.
func beam_hits(point: Vector2, extra: float) -> bool:
	var dir := Vector2.from_angle(aim)
	var rel := point - position
	if rel.dot(dir) < 0.0:
		return false
	return absf(rel.cross(dir)) < BEAM_HALF + extra


func _update_fire(_delta: float) -> void:
	if mode != "fire":
		return
	for p in game.players:
		if p.can_be_hit() and beam_hits(p.position, Player.HITBOX):
			p.take_hit()


func _draw() -> void:
	if frozen_timer <= 0.0:
		draw_set_transform(Vector2.ZERO, aim)
		if mode == "telegraph" and int(Time.get_ticks_msec() / 60) % 2 == 0:
			draw_line(Vector2(radius, 0), Vector2(BEAM_LENGTH, 0), Color(1.0, 0.3, 0.4, 0.75), 1.0)
		elif mode == "fire":
			var w := BEAM_HALF * (1.0 - 0.25 * sin(Time.get_ticks_msec() * 0.04))
			draw_rect(Rect2(radius, -w - 2, BEAM_LENGTH, w * 2 + 4), Color(1.0, 0.2, 0.35, 0.45))
			draw_rect(Rect2(radius, -w, BEAM_LENGTH, w * 2), Color(1.0, 0.45, 0.55, 0.85))
			draw_rect(Rect2(radius, -1.5, BEAM_LENGTH, 3), Color(1, 0.95, 0.95))
		draw_set_transform(Vector2.ZERO)
	draw_body(self, Vector2.ZERO, aim - PI, Color.WHITE if flash > 0.0 else color)
	_draw_status()


## Diamond hull with the emitter facing along `turn` + left. Shared with the
## boss, which draws the drones docked on its hull.
static func draw_body(canvas: CanvasItem, at: Vector2, turn: float, c: Color) -> void:
	var pts := PackedVector2Array()
	for p in [Vector2(-12, 0), Vector2(0, -10), Vector2(12, 0), Vector2(0, 10)]:
		pts.append(at + p.rotated(turn))
	canvas.draw_colored_polygon(pts, c)
	canvas.draw_line(at + Vector2(-10, 0).rotated(turn), at + Vector2(-16, 0).rotated(turn), c.darkened(0.4), 4.0)
	canvas.draw_circle(at, 3.0, Color(1.0, 0.3, 0.4))
