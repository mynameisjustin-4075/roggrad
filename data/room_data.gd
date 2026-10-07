class_name RoomData
extends Resource
## One room: a timed list of enemy waves.
## Each wave: {"time": s, "enemy": "grunt"|"gunner"|"diver", "count": n,
##             "interval": s between spawns, "y": px, "dy": px added per spawn}

@export var display_name: String
@export var scroll_speed: float = 40.0
@export var is_boss: bool = false
@export var waves: Array = []
