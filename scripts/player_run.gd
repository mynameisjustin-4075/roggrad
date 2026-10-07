class_name PlayerRun
extends RefCounted
## One player's state for the current run. In co-op every player has their own;
## permanent (hangar) bonuses come from MetaProgress, the primary profile.

var index := 0
var devices: Array = []
var ship_id := "lancer"
var max_hull := 3
var hull := 3
var bombs := 2
var upgrades := {}  # upgrade id -> stacks
var credits := 0
var kills := 0
var alive := true


func stacks(id: String) -> int:
	return upgrades.get(id, 0)
