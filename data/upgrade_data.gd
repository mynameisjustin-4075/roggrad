class_name UpgradeData
extends Resource
## One in-run upgrade. Its effect is looked up by `id` in the player and game code.
## A "primary" upgrade replaces the ship's main shot; taking it again levels it.
## "secondary" and "dodge" are reserved for upcoming secondary-ability and
## dodge upgrades.

@export var id: String
@export var display_name: String
@export_multiline var description: String
@export var family: String
@export_enum("Common", "Rare", "Epic", "Legendary") var rarity: int = 0
@export var max_stacks: int = 1
@export_enum("passive", "primary", "secondary", "dodge") var slot: String = "passive"
## Not offered while the player's primary weapon is one of these ids.
@export var incompatible_with: PackedStringArray = []
