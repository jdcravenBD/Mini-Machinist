class_name ItemDefs
## Catalog of every item kind. An item's drawn outline IS its collision shape, so what
## you see is exactly how it tips, stacks and settles.
##
## `size` scales the unit outline into pixels (a tile is 32).

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


static func size_of(kind: StringName) -> float:
	return DEFS[kind]["size"]


## The outline for `kind` in pixels, centered on its center of mass. Flat x, y pairs.
static func outline(kind: StringName, shape: int) -> PackedFloat64Array:
	var unit: Array = SHAPES[shape]
	var size := size_of(kind)
	var points := PackedFloat64Array()
	for v in unit:
		points.append(v * size)
	return Shape.recentered(points)
