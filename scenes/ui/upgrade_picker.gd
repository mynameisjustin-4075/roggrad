class_name UpgradePicker
extends Node2D
## "Pick 1 of 3" screen. Opened once per player after a room; only that
## player's controls drive it.

signal chosen(run: PlayerRun, upgrade: UpgradeData)

const FAMILY_COLORS := {
	"Volt": Color("ffe14d"), "Cryo": Color("7fd4ff"), "Nova": Color("ff8a3d"),
	"Swarm": Color("7dff7a"), "Aegis": Color("d0d8ff"), "Acid/Fire": Color("b6ff3b"),
}
const RARITY_NAMES := ["Common", "Rare", "Epic", "Legendary"]
const OPEN_DELAY := 0.35

var run: PlayerRun
var ctl: ControlState
var options: Array = []
var index := 0
var color := Color.WHITE
var _delay := 0.0


func open(p_run: PlayerRun, p_ctl: ControlState, p_options: Array, p_color: Color) -> void:
	run = p_run
	ctl = p_ctl
	options = p_options
	color = p_color
	index = 1 if options.size() > 1 else 0
	_delay = OPEN_DELAY
	ctl.sync()
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	var left := ctl.pressed("left")
	var right := ctl.pressed("right")
	var confirm := ctl.pressed("confirm")
	_delay -= delta
	if _delay > 0.0:
		return
	if left:
		index = (index - 1 + options.size()) % options.size()
	if right:
		index = (index + 1) % options.size()
	queue_redraw()
	if confirm:
		visible = false
		chosen.emit(run, options[index])


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(0, 0, 480, 270), Color(0, 0, 0, 0.75))
	draw_string(font, Vector2(0, 44), "P%d - CHOOSE AN UPGRADE" % (run.index + 1), HORIZONTAL_ALIGNMENT_CENTER, 480, 16, color)
	for i in options.size():
		var u: UpgradeData = options[i]
		var rect := Rect2(24 + i * 148, 64, 136, 150)
		var fc: Color = FAMILY_COLORS.get(u.family, Color.WHITE)
		var selected := i == index
		draw_rect(rect, Color(0.08, 0.09, 0.16))
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 4)), fc)
		draw_rect(rect, color if selected else Color(0.3, 0.3, 0.4), false, 2.0 if selected else 1.0)
		draw_string(font, rect.position + Vector2(8, 24), u.display_name, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, 12, Color.WHITE)
		draw_string(font, rect.position + Vector2(8, 38), "%s - %s" % [u.family, RARITY_NAMES[u.rarity]], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, 8, fc)
		var level := run.stacks(u.id)
		var note := ""
		if u.slot == "primary" and run.primary != u.id:
			note = "PRIMARY - replaces " + run.primary_name
		elif u.max_stacks > 1:
			note = "Level %d -> %d" % [level, level + 1]
		draw_string(font, rect.position + Vector2(8, 50), note, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, 8, Color(1, 0.85, 0.5) if u.slot == "primary" else Color(0.7, 0.7, 0.8))
		draw_multiline_string(font, rect.position + Vector2(8, 68), u.description, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, 10, -1, Color(0.85, 0.85, 0.9))
	draw_string(font, Vector2(0, 236), "Left / Right to choose    Fire / Enter to take it", HORIZONTAL_ALIGNMENT_CENTER, 480, 8, Color(0.6, 0.6, 0.7))
