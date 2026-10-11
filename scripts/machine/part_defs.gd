class_name PartDefs
## Catalog of every placeable part.
##
## Sizes are the real in-game sizes; colors are placeholders until final art replaces
## the shapes drawn in WorldView. "variants" is how many ways R can turn it.

const TILE := 32

## Toolbar order (also the number-key hotkeys 1-9, then 0).
const ORDER: Array[StringName] = [
	&"spawner", &"conveyor", &"sorter", &"ramp", &"hopper",
	&"large_crusher", &"small_crusher", &"block", &"panel", &"bin",
]

const DEFS := {
	&"spawner": {
		"name": "Ore Spawner",
		"size": Vector2i(1, 1),
		"variants": 1,
		"color": Color(0.42, 0.36, 0.30),
		"hint": "Drops iron ore (and some rock) out of its bottom.",
	},
	&"conveyor": {
		"name": "Conveyor",
		"size": Vector2i(1, 1),
		"variants": 2,
		"color": Color(0.36, 0.38, 0.40),
		"hint": "Carries items along its top. R flips direction.",
	},
	&"sorter": {
		"name": "Sorter",
		"size": Vector2i(1, 1),
		"variants": 2,
		"color": Color(0.33, 0.40, 0.46),
		"hint": "A belt with a grate: items it's set to drop fall through, the rest ride across. R flips, F changes what it drops.",
	},
	&"ramp": {
		"name": "Ramp",
		"size": Vector2i(1, 1),
		"variants": 2,
		"color": Color(0.50, 0.47, 0.42),
		"hint": "Items slide down it. R flips the slope.",
	},
	&"hopper": {
		"name": "Hopper",
		"size": Vector2i(2, 1),
		"variants": 1,
		"color": Color(0.55, 0.45, 0.30),
		"hint": "Funnels items through a narrow gap at the bottom.",
	},
	&"large_crusher": {
		"name": "Large Crusher",
		"size": Vector2i(2, 1),
		"variants": 1,
		"color": Color(0.40, 0.36, 0.33),
		"hint": "Two big toothed rollers crush each chunk into 3 bits, one at a time. Bits and gravel fall straight through.",
	},
	&"small_crusher": {
		"name": "Small Crusher",
		"size": Vector2i(1, 1),
		"variants": 1,
		"color": Color(0.40, 0.36, 0.33),
		"hint": "Four small rollers crush each bit into 3 gravel. Gravel falls through; a chunk is too big and clogs it.",
	},
	&"block": {
		"name": "Block",
		"size": Vector2i(1, 1),
		"variants": 1,
		"color": Color(0.30, 0.29, 0.27),
		"hint": "A plain solid support.",
	},
	&"panel": {
		"name": "Panel",
		"size": Vector2i(1, 1),
		"variants": 4,
		"color": Color(0.46, 0.44, 0.40),
		"hint": "A thin floor or wall along one edge of its tile, for building basins and chutes. R turns it.",
	},
	&"bin": {
		"name": "Collection Bin",
		"size": Vector2i(2, 1),
		"variants": 1,
		"color": Color(0.30, 0.42, 0.33),
		"hint": "Collects and counts whatever falls in.",
	},
}

## What a newly placed sorter drops.
const DEFAULT_FILTER := &"rock"


static func size_of(type: StringName) -> Vector2i:
	return DEFS[type]["size"]


static func variant_count(type: StringName) -> int:
	return DEFS[type]["variants"]


static func has_filter(type: StringName) -> bool:
	return type == &"sorter"
