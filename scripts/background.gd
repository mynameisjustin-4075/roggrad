class_name Background
extends Node2D
## World 1 (Debris Belt) parallax background, back to front:
##   1. seamless nebula backdrop, very slow
##   2. a few twinkling stars
##   3. giant derelict wrecks hugging the top and bottom edges, slow
##   4. small drifting debris across the middle, faster
## `speed` is the room's scroll speed; each layer moves at a fraction of it.
## Art comes from SpriteCook via tools/art/background.py.

const W := 640.0
const H := 360.0
const BACKDROP := preload("res://art/sprites/background/debris_belt_backdrop.png")
const WRECKS := [
	preload("res://art/sprites/background/wreck_a.png"),
	preload("res://art/sprites/background/wreck_b.png"),
	preload("res://art/sprites/background/wreck_c.png"),
	preload("res://art/sprites/background/wreck_d.png"),
]
const DEBRIS_COUNT := 12  # pieces, each baked in a small (_s) and medium (_m) size
const BACKDROP_FACTOR := 0.15
const STAR_FACTORS := [0.25, 0.35, 0.45]
const WRECK_FACTOR := 0.35
const STAR_COLORS := [Color(0.35, 0.4, 0.55), Color(0.55, 0.6, 0.75), Color(0.85, 0.9, 1.0)]

var speed := 40.0
var _backdrop_x := 0.0
var _stars: Array = []
var _wrecks: Array = []  # {tex, pos, flip}
var _debris: Array = []  # {tex, pos, factor, flip}
var _debris_textures: Array = []
var _next_wreck_x := 0.0


func _ready() -> void:
	for i in DEBRIS_COUNT:
		for size in ["s", "m"]:
			_debris_textures.append(load("res://art/sprites/background/debris_%02d_%s.png" % [i, size]))
	for i in 70:
		_stars.append({"p": Vector2(randf() * W, randf() * H), "l": randi() % 3, "phase": randf() * TAU})
	# Start with wrecks already on screen so the first room isn't empty.
	_next_wreck_x = randf_range(-60.0, 80.0)
	while _next_wreck_x < W + 200.0:
		_spawn_wreck(_next_wreck_x)
	for i in 7:
		_spawn_debris(randf() * W)


func _spawn_wreck(x: float) -> void:
	var tex: Texture2D = WRECKS.pick_random()
	var size := tex.get_size()
	# Alternate-ish between top and bottom edges, mostly off-screen.
	var top := randf() < 0.5
	var y := randf_range(-size.y * 0.45, -size.y * 0.2) if top else randf_range(H - size.y * 0.8, H - size.y * 0.55)
	_wrecks.append({"tex": tex, "pos": Vector2(x, y), "flip": randf() < 0.5})
	_next_wreck_x = x + size.x + randf_range(40.0, 220.0)


func _spawn_debris(x: float) -> void:
	_debris.append({
		"tex": _debris_textures.pick_random(),
		"pos": Vector2(x, randf_range(20.0, H - 20.0)),
		"factor": randf_range(0.7, 1.3),
		"flip": randf() < 0.5,
	})


func _process(delta: float) -> void:
	_backdrop_x = fposmod(_backdrop_x - speed * BACKDROP_FACTOR * delta, BACKDROP.get_width())
	for s in _stars:
		var p: Vector2 = s.p
		p.x -= speed * STAR_FACTORS[s.l] * delta
		if p.x < 0.0:
			p = Vector2(p.x + W, randf() * H)
		s.p = p
	var wreck_move := speed * WRECK_FACTOR * delta
	for w in _wrecks:
		w.pos.x -= wreck_move
	_next_wreck_x -= wreck_move
	_wrecks = _wrecks.filter(func(w): return w.pos.x + w.tex.get_width() > -10.0)
	if _next_wreck_x < W + 40.0:
		_spawn_wreck(maxf(_next_wreck_x, W + 10.0))
	for d in _debris:
		d.pos.x -= speed * d.factor * delta
	_debris = _debris.filter(func(d): return d.pos.x + d.tex.get_width() > -10.0)
	if _debris.size() < 7 and randf() < delta * 1.5:
		_spawn_debris(W + 10.0)
	queue_redraw()


func _draw() -> void:
	var bw := float(BACKDROP.get_width())
	var x := -_backdrop_x
	while x < W:
		draw_texture(BACKDROP, Vector2(roundf(x), 0))
		x += bw
	var t := Time.get_ticks_msec() * 0.002
	for s in _stars:
		var twinkle := 0.6 + 0.4 * sin(t + s.phase)
		draw_rect(Rect2(s.p.floor(), Vector2.ONE), Color(STAR_COLORS[s.l], twinkle))
	for w in _wrecks:
		_draw_piece(w.tex, w.pos, w.flip)
	for d in _debris:
		_draw_piece(d.tex, d.pos, d.flip)


func _draw_piece(tex: Texture2D, pos: Vector2, flip: bool) -> void:
	if flip:
		draw_set_transform(pos.round() + Vector2(tex.get_width(), 0), 0.0, Vector2(-1, 1))
		draw_texture(tex, Vector2.ZERO)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_texture(tex, pos.round())
