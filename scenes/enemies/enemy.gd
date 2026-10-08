class_name Enemy
extends Node2D
## A placeholder enemy drawn as a shape. Types are defined in TYPES for now;
## they move to EnemyData resources once art arrives.

const TYPES := {
	"grunt": {"hp": 3.0, "radius": 6.0, "speed": 70.0, "pattern": "sine", "color": Color(0.9, 0.4, 0.3), "scrap": 1},
	"gunner": {"hp": 10.0, "radius": 8.0, "speed": 35.0, "pattern": "stop", "fire": "aimed", "fire_interval": 1.4, "color": Color(0.85, 0.65, 0.2), "scrap": 3},
	"diver": {"hp": 4.0, "radius": 6.0, "speed": 120.0, "pattern": "dive", "color": Color(0.75, 0.35, 0.9), "scrap": 2},
}
const ACID_DPS := 1.5

var game
var kind := "grunt"
var hp := 1.0
var max_hp := 1.0
var radius := 6.0
var speed := 60.0
var pattern := "straight"
var fire_mode := ""
var fire_interval := 1.5
var color := Color.RED
var scrap := 1
var dead := false
var base_y := 135.0
var t := 0.0
var fire_timer := 0.0
var flash := 0.0
var slow_timer := 0.0
var slow_mult := 1.0
var vel := Vector2.ZERO
var acid_stacks := 0
var acid_power := 0
var acid_timer := 0.0
var acid_owner: PlayerRun = null
var frozen_timer := 0.0
## Freeze durations are multiplied by this. Bosses start lower and halve it on
## every freeze (diminishing returns), recovering slowly back to the max.
var freeze_resist := 1.0
var freeze_resist_max := 1.0
var freeze_diminishes := false


func setup(p_kind: String, hp_mult: float) -> void:
	kind = p_kind
	var d: Dictionary = TYPES[kind]
	max_hp = d.hp * hp_mult
	hp = max_hp
	radius = d.radius
	speed = d.speed
	pattern = d.pattern
	fire_mode = d.get("fire", "")
	fire_interval = d.get("fire_interval", 1.5)
	color = d.color
	scrap = d.scrap
	fire_timer = randf_range(0.5, fire_interval)


func _physics_process(delta: float) -> void:
	if dead:
		return
	freeze_resist = minf(freeze_resist + 0.05 * delta, freeze_resist_max)
	if frozen_timer > 0.0:
		frozen_timer -= delta
	else:
		t += delta
		var slow := 1.0
		if slow_timer > 0.0:
			slow_timer -= delta
			slow = slow_mult
		_move(delta * slow)
		_update_fire(delta * slow)
	if acid_stacks > 0:
		_tick_acid(delta)
	flash = maxf(flash - delta, 0.0)
	if position.x < -40.0 or position.y < -60.0 or position.y > 330.0:
		dead = true
		queue_free()
	queue_redraw()


func _move(delta: float) -> void:
	match pattern:
		"sine":
			position.x -= speed * delta
			position.y = base_y + sin(t * 3.0) * 22.0
		"stop":
			if position.x > 400.0:
				position.x -= speed * 2.0 * delta
			else:
				position.x -= speed * 0.2 * delta
			position.y = base_y + sin(t * 1.2) * 10.0
		"dive":
			if t < 0.7:
				position.x -= speed * 0.4 * delta
			else:
				if vel == Vector2.ZERO:
					var p = game.nearest_player(position)
					vel = (p.position - position).normalized() * speed if p else Vector2(-speed, 0)
				position += vel * delta
		_:
			position.x -= speed * delta


func _update_fire(delta: float) -> void:
	if fire_mode == "" or position.x > 470.0:
		return
	fire_timer -= delta
	if fire_timer <= 0.0:
		fire_timer = fire_interval
		var p = game.nearest_player(position)
		if p:
			game.spawn_enemy_bullet(position, (p.position - position).normalized() * 90.0)


func add_acid(power: int, source: PlayerRun) -> void:
	acid_stacks = mini(acid_stacks + 1, 5)
	acid_power = power
	acid_owner = source
	acid_timer = 3.0


## Slow movement and firing to `mult` speed for `duration` seconds. Each hit
## restarts the timer; while slowed, the strongest slow applied so far is kept.
func apply_slow(mult: float, duration: float) -> void:
	slow_mult = minf(slow_mult, mult) if slow_timer > 0.0 else mult
	slow_timer = duration


## Stop moving and firing for `duration` seconds (scaled by freeze_resist).
func freeze(duration: float) -> void:
	frozen_timer = maxf(frozen_timer, duration * freeze_resist)
	if freeze_diminishes:
		freeze_resist *= 0.5


func _tick_acid(delta: float) -> void:
	acid_timer -= delta
	if acid_timer <= 0.0:
		acid_stacks = 0
		return
	take_damage(acid_stacks * ACID_DPS * acid_power * delta, acid_owner, false)


func take_damage(amount: float, source: PlayerRun = null, show_flash := true) -> void:
	if dead:
		return
	hp -= amount
	if show_flash:
		flash = 0.06
	if hp <= 0.0:
		dead = true
		game.on_enemy_killed(self, source)
		queue_free()


func _draw() -> void:
	var c := Color.WHITE if flash > 0.0 else color
	match kind:
		"grunt":
			draw_colored_polygon(PackedVector2Array([Vector2(-6, 0), Vector2(0, -5), Vector2(6, 0), Vector2(0, 5)]), c)
		"gunner":
			draw_rect(Rect2(-8, -6, 16, 12), c)
			draw_rect(Rect2(-12, -1, 4, 2), c.darkened(0.3))
		"diver":
			draw_colored_polygon(PackedVector2Array([Vector2(-7, 0), Vector2(6, -5), Vector2(3, 0), Vector2(6, 5)]), c)
	_draw_status()


func _draw_status() -> void:
	if acid_stacks > 0:
		draw_arc(Vector2.ZERO, radius + 2.0, 0.0, TAU, 12, Color(0.6, 1.0, 0.2, 0.8), 1.0)
	if slow_timer > 0.0:
		draw_arc(Vector2.ZERO, radius + 3.5, 0.0, TAU, 12, Color(0.6, 0.85, 1.0, 0.7), 1.0)
	if frozen_timer > 0.0:
		draw_circle(Vector2.ZERO, radius + 1.0, Color(0.7, 0.9, 1.0, 0.55))
		draw_arc(Vector2.ZERO, radius + 1.5, 0.0, TAU, 6, Color.WHITE, 1.0)
