class_name ItemDefs
## Catalog of item materials and sizes. An item is a material (iron ore, rock, scrap iron…)
## at a size: a chunk as mined, bits from a large crusher, gravel from a small crusher.
## An item's drawn outline IS its collision shape, so what you see is exactly how it tips,
## stacks and settles, and whether it fits through a gap.

## Every material, in the order a sorter's filter cycles through them.
const ORDER: Array[StringName] = [&"iron_ore", &"rock", &"scrap_iron", &"slag"]

## "size" is a chunk's scale in pixels (a tile is 32); smaller sizes scale down from it.
const DEFS := {
	&"iron_ore": {
		"name": "Iron Ore",
		"size": 6.5,
		"color": Color(0.62, 0.36, 0.25),
		"fleck": Color(0.80, 0.52, 0.36),
	},
	&"rock": {
		"name": "Rock",
		"size": 7.5,
		"color": Color(0.50, 0.50, 0.48),
		"fleck": Color(0.64, 0.64, 0.61),
	},
	# Molten iron that hardened outside a mold (poured onto the floor, or cooled in the
	# crucible). Melts back down.
	&"scrap_iron": {
		"name": "Scrap Iron",
		"size": 6.5,
		"color": Color(0.58, 0.60, 0.64),
		"fleck": Color(0.78, 0.80, 0.84),
	},
	# The glassy waste from smelting: everything in ore that isn't iron, and all of rock.
	&"slag": {
		"name": "Slag",
		"size": 7.0,
		"color": Color(0.24, 0.27, 0.25),
		"fleck": Color(0.38, 0.44, 0.40),
	},
}

## Sizes from largest to smallest. Three pieces of the next size down hold about the same
## amount of material as one piece of the size above (0.55² × 3 ≈ 0.9).
const SIZES := {
	&"chunk": {"name": "Chunk", "scale": 1.0, "amount": 1.0},
	&"bit": {"name": "Bits", "scale": 0.55, "amount": 1.0 / 3.0},
	&"gravel": {"name": "Gravel", "scale": 0.3, "amount": 1.0 / 9.0},
}

## Lumpy convex outlines of radius ~1, as flat x, y pairs going clockwise on screen.
## Written out as exact numbers (not computed with sin/cos) so every machine builds
## bit-identical shapes. Each item picks one, so piles aren't copies of one pebble.
const SHAPES := [
	[-0.819, -0.574, 0.0, -0.85, 0.766, -0.643, 1.05, 0.0, 0.516, 0.737, -0.376, 1.034, -0.936, 0.165],
	[-0.45, -0.779, 0.5, -0.866, 1.083, 0.191, 0.325, 0.893, -0.574, 0.819, -1.1, 0.0],
	[-0.893, -0.325, -0.285, -1.063, 0.579, -0.689, 0.95, 0.0, 0.778, 0.778, -0.156, 0.886, -0.909, 0.525],
	[-0.987, -0.359, -0.174, -0.985, 0.728, -0.611, 0.94, 0.342, 0.096, 1.096, -0.689, 0.579],
]


## 0 for the biggest size, counting up as pieces get smaller.
static func size_rank(size: StringName) -> int:
	return SIZES.keys().find(size)


## How much material one piece of `size` holds, counting a chunk as 1.
static func amount_of(size: StringName) -> float:
	return SIZES[size]["amount"]


## Scale in pixels of `kind` at `size`.
static func size_of(kind: StringName, size: StringName) -> float:
	return DEFS[kind]["size"] * SIZES[size]["scale"]


## "Iron Ore Chunk", "Rock Gravel", …
static func display_name(kind: StringName, size: StringName) -> String:
	return "%s %s" % [DEFS[kind]["name"], SIZES[size]["name"]]


## The outline in pixels, centered on its center of mass. Flat x, y pairs.
static func outline(kind: StringName, size: StringName, shape: int) -> PackedFloat64Array:
	var unit: Array = SHAPES[shape]
	var scale := size_of(kind, size)
	var points := PackedFloat64Array()
	for v in unit:
		points.append(v * scale)
	return Shape.recentered(points)
