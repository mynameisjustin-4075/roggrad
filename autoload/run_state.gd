extends Node
## State of the current run, shared by every scene during that run.

var players: Array[PlayerRun] = []
var room_index := 0
var scrap_earned := 0


func new_run() -> void:
	players.clear()
	room_index = 0
	scrap_earned = 0


func add_player(devices: Array) -> PlayerRun:
	var run := PlayerRun.new()
	run.index = players.size()
	run.devices = devices
	run.max_hull = 3 + MetaProgress.bonus_hull
	run.hull = run.max_hull
	players.append(run)
	return run


func has_device(device: int) -> bool:
	for run in players:
		if device in run.devices:
			return true
	return false


func alive_count() -> int:
	var n := 0
	for run in players:
		if run.alive:
			n += 1
	return n
