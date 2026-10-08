class_name PlayerRun
extends RefCounted
## One player's state for the current run. In co-op every player has their own;
## permanent (hangar) bonuses come from MetaProgress, the primary profile.

const DEFAULT_PRIMARY_NAME := "Twin Shot"
const DEFAULT_SECONDARY_NAME := "Charge Beam"
const DEFAULT_DODGE_NAME := "Dodge"
const SLOTS := ["primary", "secondary", "dodge"]

var index := 0
var devices: Array = []
var ship_id := "lancer"
var max_hull := 3
var hull := 3
var bombs := 2
var upgrades := {}  # upgrade id -> stacks (a slot upgrade's stacks = its level)
# Equipped slot upgrades by id; "" = the ship's own version.
var primary := ""
var primary_name := DEFAULT_PRIMARY_NAME
var secondary := ""
var secondary_name := DEFAULT_SECONDARY_NAME
var dodge := ""
var dodge_name := DEFAULT_DODGE_NAME
var credits := 0
var kills := 0
var alive := true


func stacks(id: String) -> int:
	return upgrades.get(id, 0)


func slot_id(slot: String) -> String:
	return get(slot)


func slot_name(slot: String) -> String:
	return get(slot + "_name")


func slot_level(slot: String) -> int:
	var id := slot_id(slot)
	return maxi(stacks(id), 1) if id != "" else 1


func primary_level() -> int:
	return slot_level("primary")


## Equip a primary, secondary or dodge upgrade: the same one levels up, a
## different one replaces whatever is in that slot (its levels are lost).
func equip(u: UpgradeData) -> void:
	var current := slot_id(u.slot)
	if current == u.id:
		upgrades[u.id] = stacks(u.id) + 1
		return
	if current != "":
		upgrades.erase(current)
	set(u.slot, u.id)
	set(u.slot + "_name", u.display_name)
	upgrades[u.id] = 1


## Back to the ship's own version for that slot.
func unequip(slot: String) -> void:
	upgrades.erase(slot_id(slot))
	set(slot, "")
	set(slot + "_name", {"primary": DEFAULT_PRIMARY_NAME, "secondary": DEFAULT_SECONDARY_NAME, "dodge": DEFAULT_DODGE_NAME}[slot])
