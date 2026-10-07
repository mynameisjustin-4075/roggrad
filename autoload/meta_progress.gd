extends Node
## Permanent progress for the primary player's profile. In co-op these bonuses
## apply to every player; only the primary profile earns and spends Scrap.

const SAVE_PATH := "user://meta.json"

var scrap := 0
var bonus_hull := 0
var runs := 0


func _ready() -> void:
	load_save()


func add_run_result(earned: int) -> void:
	scrap += earned
	runs += 1
	save()


func save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"scrap": scrap, "bonus_hull": bonus_hull, "runs": runs}))


func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data is Dictionary:
		scrap = int(data.get("scrap", 0))
		bonus_hull = int(data.get("bonus_hull", 0))
		runs = int(data.get("runs", 0))
