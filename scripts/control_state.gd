class_name ControlState
extends RefCounted
## One player's controls, with just-pressed detection per action.

var devices: Array
var _prev := {}


func _init(p_devices: Array) -> void:
	devices = p_devices


func move() -> Vector2:
	return Controls.get_move(devices)


func down(action: String) -> bool:
	return Controls.is_down(devices, action)


## True only on the frame the action goes from up to down. An action seen for
## the first time counts as already held, so a held button never fires early.
func pressed(action: String) -> bool:
	var now := down(action)
	var was: bool = _prev.get(action, true)
	_prev[action] = now
	return now and not was


## Forget edges so buttons held right now don't count as fresh presses.
func sync() -> void:
	for action in _prev.keys():
		_prev[action] = down(action)
