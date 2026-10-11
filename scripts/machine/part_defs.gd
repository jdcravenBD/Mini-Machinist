class_name PartDefs
## Catalog of every placeable part.
##
## Sizes are the real in-game sizes. Until final art arrives every part is drawn the same
## simple way: its color, a darker stroke just inside its edge, and its letter in the middle.
## "variants" is how many ways R can turn it.

const TILE := 32

## Toolbar categories, in order. Number keys pick a part within the open category.
const CATEGORIES := [
	{"name": "Moving", "parts": [&"conveyor", &"sorter", &"ramp", &"hopper"]},
	{"name": "Crushing", "parts": [&"large_crusher", &"small_crusher"]},
	{"name": "Smelting", "parts": [&"crucible", &"heating_coil", &"bellows", &"insulation", &"skimmer", &"tilter"]},
	{"name": "Building", "parts": [&"block", &"panel"]},
	{"name": "Testing", "parts": [&"spawner", &"bin"]},
]

const DEFS := {
	&"spawner": {
		"name": "Ore Spawner",
		"letter": "O",
		"size": Vector2i(1, 1),
		"variants": 1,
		"color": Color(0.45, 0.36, 0.28),
		"hint": "Drops iron ore (and some rock) out of its bottom.",
	},
	&"conveyor": {
		"name": "Conveyor",
		"letter": ">",
		"size": Vector2i(1, 1),
		"variants": 2,
		"color": Color(0.40, 0.43, 0.47),
		"hint": "A half-tile belt that carries items along its top. R flips direction.",
	},
	&"sorter": {
		"name": "Sorter",
		"letter": "S",
		"size": Vector2i(1, 1),
		"variants": 2,
		"color": Color(0.33, 0.45, 0.58),
		"hint": "A closed box in a belt line: everything goes in its mouth, the material it's set to drop falls out the bottom, the rest comes out the far side. R flips, F changes what it drops.",
	},
	&"ramp": {
		"name": "Ramp",
		"letter": "R",
		"size": Vector2i(1, 1),
		"variants": 2,
		"color": Color(0.60, 0.55, 0.45),
		"hint": "Items slide down it. R flips the slope.",
	},
	&"hopper": {
		"name": "Hopper",
		"letter": "F",
		"size": Vector2i(2, 1),
		"variants": 1,
		"color": Color(0.66, 0.52, 0.30),
		"hint": "Funnels items through a narrow gap at the bottom.",
	},
	&"large_crusher": {
		"name": "Large Crusher",
		"letter": "X",
		"size": Vector2i(2, 1),
		"variants": 1,
		"color": Color(0.45, 0.45, 0.50),
		"hint": "Two big rollers carry chunks into the middle and crush each into 3 bits, one at a time. Anything smaller passes through.",
	},
	&"small_crusher": {
		"name": "Small Crusher",
		"letter": "x",
		"size": Vector2i(1, 1),
		"variants": 1,
		"color": Color(0.55, 0.53, 0.58),
		"hint": "Four small rollers crush each bit into 3 gravel. Gravel passes through; a chunk is too big and clogs it.",
	},
	&"crucible": {
		"name": "Crucible",
		"letter": "C",
		"size": Vector2i(2, 1),
		"variants": 1,
		"color": Color(0.36, 0.33, 0.36),
		"hint": "Swallows ore dropped in and melts it once it's hot enough (1500°): ore into iron and slag, rock into slag. Smaller pieces melt faster. Cools below that and the iron hardens again.",
	},
	&"heating_coil": {
		"name": "Heating Coil",
		"letter": "H",
		"size": Vector2i(1, 1),
		"variants": 1,
		"color": Color(0.93, 0.50, 0.15),
		"hint": "Heats every crucible it touches. One coil alone can't reach 1500°: add bellows, insulation or a second coil.",
	},
	&"bellows": {
		"name": "Bellows",
		"letter": "W",
		"size": Vector2i(1, 1),
		"variants": 1,
		"color": Color(0.55, 0.38, 0.24),
		"hint": "Doubles the heat of a coil it touches, but only while it's pumping, so the heat rises and falls.",
	},
	&"insulation": {
		"name": "Insulation",
		"letter": "I",
		"size": Vector2i(1, 1),
		"variants": 1,
		"color": Color(0.85, 0.82, 0.72),
		"hint": "Each piece touching a crucible cuts the heat it loses.",
	},
	&"skimmer": {
		"name": "Skimmer",
		"letter": "K",
		"size": Vector2i(1, 1),
		"variants": 1,
		"color": Color(0.25, 0.55, 0.55),
		"hint": "Scrapes the slag off a crucible it touches (it can sit over half the crucible's mouth) and drops it out its far side.",
	},
	&"tilter": {
		"name": "Tilter",
		"letter": "T",
		"size": Vector2i(1, 1),
		"variants": 1,
		"color": Color(0.50, 0.40, 0.62),
		"hint": "Next to a crucible, tips it to pour out the far side once everything inside has melted. Slag floats, so it pours out first.",
	},
	&"block": {
		"name": "Block",
		"letter": "B",
		"size": Vector2i(1, 1),
		"variants": 1,
		"color": Color(0.32, 0.31, 0.30),
		"hint": "A plain solid support.",
	},
	&"panel": {
		"name": "Panel",
		"letter": "",
		"size": Vector2i(1, 1),
		"variants": 4,
		"color": Color(0.52, 0.50, 0.46),
		"hint": "A thin floor or wall along one edge of its tile, for building basins and chutes. R turns it.",
	},
	&"bin": {
		"name": "Collection Bin",
		"letter": "#",
		"size": Vector2i(2, 1),
		"variants": 1,
		"color": Color(0.30, 0.50, 0.36),
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
