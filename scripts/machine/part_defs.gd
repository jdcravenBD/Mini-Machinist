class_name PartDefs
## Catalog of every placeable part.
##
## Sizes are the real in-game sizes; colors are placeholders until final art replaces
## the shapes drawn in WorldView.

const TILE := 32

## Toolbar order (also the 1-6 hotkeys).
const ORDER: Array[StringName] = [&"spawner", &"conveyor", &"ramp", &"hopper", &"block", &"bin"]

const DEFS := {
	&"spawner": {
		"name": "Ore Spawner",
		"size": Vector2i(1, 1),
		"flippable": false,
		"color": Color(0.42, 0.36, 0.30),
		"hint": "Drops iron ore (and some rock) out of its bottom.",
	},
	&"conveyor": {
		"name": "Conveyor",
		"size": Vector2i(1, 1),
		"flippable": true,
		"color": Color(0.36, 0.38, 0.40),
		"hint": "Carries items along its top. R flips direction.",
	},
	&"ramp": {
		"name": "Ramp",
		"size": Vector2i(1, 1),
		"flippable": true,
		"color": Color(0.50, 0.47, 0.42),
		"hint": "Items slide down it. R flips the slope.",
	},
	&"hopper": {
		"name": "Hopper",
		"size": Vector2i(2, 1),
		"flippable": false,
		"color": Color(0.55, 0.45, 0.30),
		"hint": "Funnels items through a narrow gap at the bottom.",
	},
	&"block": {
		"name": "Block",
		"size": Vector2i(1, 1),
		"flippable": false,
		"color": Color(0.30, 0.29, 0.27),
		"hint": "A plain solid support.",
	},
	&"bin": {
		"name": "Collection Bin",
		"size": Vector2i(2, 1),
		"flippable": false,
		"color": Color(0.30, 0.42, 0.33),
		"hint": "Collects and counts whatever falls in.",
	},
}


static func size_of(type: StringName) -> Vector2i:
	return DEFS[type]["size"]


static func is_flippable(type: StringName) -> bool:
	return DEFS[type]["flippable"]
