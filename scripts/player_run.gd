class_name PlayerRun
extends RefCounted
## One player's state for the current run. In co-op every player has their own;
## permanent (hangar) bonuses come from MetaProgress, the primary profile.

const DEFAULT_PRIMARY_NAME := "Twin Shot"

var index := 0
var devices: Array = []
var ship_id := "lancer"
var max_hull := 3
var hull := 3
var bombs := 2
var upgrades := {}  # upgrade id -> stacks (the primary weapon's stacks = its level)
var primary := ""  # upgrade id of the primary weapon; "" = the ship's own shot
var primary_name := DEFAULT_PRIMARY_NAME
var secondary := ""  # upgrade id of the secondary ability; "" = the ship's own
var credits := 0
var kills := 0
var alive := true


func stacks(id: String) -> int:
	return upgrades.get(id, 0)


func primary_level() -> int:
	return maxi(stacks(primary), 1) if primary != "" else 1


## Equip a primary weapon upgrade: the same one levels up, a new one replaces the old.
func take_primary(u: UpgradeData) -> void:
	if primary == u.id:
		upgrades[u.id] = stacks(u.id) + 1
		return
	if primary != "":
		upgrades.erase(primary)
	primary = u.id
	primary_name = u.display_name
	upgrades[u.id] = 1
