extends Node
## Input for up to 4 local players. Each player owns a list of devices:
## KEYBOARD (-1) and/or joypad ids. Keyboard actions are registered here at
## startup so they don't depend on editor input-map settings.

const KEYBOARD := -1
const DEADZONE := 0.3

const KEYS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"fire": [KEY_J, KEY_SPACE],
	"secondary": [KEY_K],
	"dodge": [KEY_I],
	"focus": [KEY_SHIFT],
	"bomb": [KEY_L],
	"confirm": [KEY_ENTER, KEY_SPACE, KEY_J],
	"start": [KEY_ENTER, KEY_ESCAPE],
}

const JOY_BUTTONS := {
	"fire": [JOY_BUTTON_A],
	"secondary": [JOY_BUTTON_X],
	"dodge": [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_Y],
	"bomb": [JOY_BUTTON_B],
	"focus": [JOY_BUTTON_RIGHT_SHOULDER],
	"confirm": [JOY_BUTTON_A],
	"start": [JOY_BUTTON_START],
}


func _ready() -> void:
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


func get_move(devices: Array) -> Vector2:
	var v := Vector2.ZERO
	for d in devices:
		if d == KEYBOARD:
			v += Vector2(
				Input.get_axis("move_left", "move_right"),
				Input.get_axis("move_up", "move_down"))
		else:
			var stick := Vector2(
				Input.get_joy_axis(d, JOY_AXIS_LEFT_X),
				Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
			if stick.length() < DEADZONE:
				stick = Vector2.ZERO
			var dpad := Vector2(
				float(Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT)) - float(Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT)),
				float(Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_DOWN)) - float(Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_UP)))
			v += stick + dpad
	return v.limit_length(1.0)


func is_down(devices: Array, action: String) -> bool:
	match action:
		"left":
			return get_move(devices).x < -0.5
		"right":
			return get_move(devices).x > 0.5
	for d in devices:
		if d == KEYBOARD:
			if InputMap.has_action(action) and Input.is_action_pressed(action):
				return true
		else:
			for button in JOY_BUTTONS.get(action, []):
				if Input.is_joy_button_pressed(d, button):
					return true
			if action == "fire" and Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) > 0.5:
				return true
			if action == "focus" and Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT) > 0.5:
				return true
	return false
