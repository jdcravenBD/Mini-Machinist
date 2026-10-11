class_name ItemDefs
## Catalog of every item kind. Radius is the collision size in pixels (a tile is 32);
## the drawn shape is a lumpy outline around that circle.

const DEFS := {
	&"iron_ore": {
		"name": "Iron Ore",
		"radius": 5.0,
		"color": Color(0.62, 0.36, 0.25),
		"fleck": Color(0.80, 0.52, 0.36),
	},
	&"rock": {
		"name": "Rock",
		"radius": 6.0,
		"color": Color(0.50, 0.50, 0.48),
		"fleck": Color(0.64, 0.64, 0.61),
	},
}

## Lumpy outlines, as radius multipliers at evenly spaced angles. Each item picks one,
## so a pile doesn't look like copies of the same pebble.
const SHAPES := [
	[1.05, 0.85, 1.10, 0.92, 1.02, 0.82, 0.97],
	[0.92, 1.08, 0.86, 1.04, 0.96, 1.10, 0.84],
	[1.10, 0.90, 1.00, 0.82, 1.08, 0.92, 1.00],
	[0.86, 1.02, 0.96, 1.10, 0.82, 1.04, 0.92],
]


static func radius_of(kind: StringName) -> float:
	return DEFS[kind]["radius"]
