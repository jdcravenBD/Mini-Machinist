class_name PartGeometry
## Turns a Machine's parts into a ready-to-run Simulation: collision segments, spawners
## and bins. Shapes are in pixels, measured from each part's top-left corner.

const T := PartDefs.TILE
const BELT_SPEED := 64.0
## Friction coefficients: belts grip hard so they drag items up to speed quickly.
const BELT_FRICTION := 0.9
const SURFACE_FRICTION := 0.6
## Ticks between spawns (60 ticks = 1 second).
const SPAWN_INTERVAL := 30
const HOPPER_GAP := 18.0
const PANEL_THICKNESS := 6.0

## Crushers. The gap between a pair of rollers decides what falls straight through:
## a large crusher's 10 px gap passes bits (9 px at most) but stops chunks (11 px at least);
## a small crusher's 5.2 px gap passes gravel (under 5 px) but stops bits (6 px at least).
const LARGE_ROLLER := 11.0
const SMALL_ROLLER := 5.4
## How fast the roller surfaces move, pulling what sits on them in toward the gap.
const ROLLER_SPEED := 40.0
const ROLLER_FRICTION := 0.9
## Ticks to crush one item (60 ticks = 1 second). A small crusher makes 3 gravel per bit at
## a third of the time, so one large crusher feeds one small crusher evenly.
const LARGE_CRUSH_TICKS := 24
const SMALL_CRUSH_TICKS := 8
const CRUSH_PIECES := 3
## Points of a unit circle every 30°, clockwise on screen, as exact numbers so rollers are
## bit-identical everywhere. Starting at 0° puts a corner right at the gap.
const CIRCLE_12 := [
	1.0, 0.0, 0.8660254037844386, 0.5, 0.5, 0.8660254037844386, 0.0, 1.0,
	-0.5, 0.8660254037844386, -0.8660254037844386, 0.5, -1.0, 0.0, -0.8660254037844386, -0.5,
	-0.5, -0.8660254037844386, 0.0, -1.0, 0.5, -0.8660254037844386, 0.8660254037844386, -0.5,
]
## Which tile edge a panel lies along, by variant (clockwise from the top), and the side
## that edge faces.
const PANEL_SIDES: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const BIN_INSET := 2.0
## How far below the bin's rim an item must fall before it counts as collected.
const BIN_CATCH_DEPTH := 10.0


static func build(machine: Machine) -> Simulation:
	var sim := Simulation.new()
	sim.set_bounds(Machine.WIDTH, Machine.HEIGHT)
	for p in machine.sorted_parts():
		var x0 := float(p.cell.x * T)
		var y0 := float(p.cell.y * T)
		var size := PartDefs.size_of(p.type)
		var x1 := x0 + size.x * T
		var y1 := y0 + size.y * T
		match p.type:
			&"block":
				_add_box(sim, machine, p, 0.0)
			&"spawner":
				_add_box(sim, machine, p, 0.0)
				sim.add_spawner(x0 + T * 0.5, y1, SPAWN_INTERVAL)
			&"conveyor":
				_add_box(sim, machine, p, belt_speed(p))
			&"sorter":
				# A belt top that the filtered kind falls straight through, over an open chute.
				_solid(sim, x0, y0, x1, y0, belt_speed(p), BELT_FRICTION, p.filter)
				_solid(sim, x0, y1, x0, y0)
				_solid(sim, x1, y0, x1, y1)
			&"panel":
				_add_panel(sim, machine, p)
			&"large_crusher":
				# Two big rollers side by side, turning in toward each other at the top.
				var mid := x0 + T
				_add_roller(sim, x0 + T * 0.5, y0 + T * 0.5, LARGE_ROLLER, ROLLER_SPEED)
				_add_roller(sim, x1 - T * 0.5, y0 + T * 0.5, LARGE_ROLLER, -ROLLER_SPEED)
				_add_crusher_housing(sim, x0, y0, x1, y0 + T * 0.5, T * 0.5 - LARGE_ROLLER)
				sim.add_crusher(&"chunk", &"bit", CRUSH_PIECES, LARGE_CRUSH_TICKS,
						Rect2(mid - 7.0, y0 - 4.0, 14.0, T * 0.5 + 4.0), mid, y1)
			&"small_crusher":
				# Four small rollers in the corners: the top pair crushes, the bottom pair
				# guides the gravel out. Each pair turns in toward its own gap.
				var mid := x0 + T * 0.5
				for row in 2:
					var cy := y0 + T * (0.25 + row * 0.5)
					_add_roller(sim, x0 + T * 0.25, cy, SMALL_ROLLER, ROLLER_SPEED)
					_add_roller(sim, x0 + T * 0.75, cy, SMALL_ROLLER, -ROLLER_SPEED)
				_add_crusher_housing(sim, x0, y0, x1, y0 + T * 0.25, T * 0.25 - SMALL_ROLLER)
				sim.add_crusher(&"bit", &"gravel", CRUSH_PIECES, SMALL_CRUSH_TICKS,
						Rect2(mid - 5.0, y0 - 6.0, 10.0, T * 0.25 + 6.0), mid, y1)
			&"ramp":
				_add_ramp(sim, machine, p, x0, y0, x1, y1)
			&"hopper":
				var mid := (x0 + x1) * 0.5
				sim.add_segment(Segment.new(x0, y0, mid - HOPPER_GAP * 0.5, y1))
				sim.add_segment(Segment.new(x1, y0, mid + HOPPER_GAP * 0.5, y1))
			&"bin":
				var l := x0 + BIN_INSET
				var r := x1 - BIN_INSET
				sim.add_segment(Segment.new(l, y0, l, y1))
				sim.add_segment(Segment.new(l, y1, r, y1))
				sim.add_segment(Segment.new(r, y1, r, y0))
				sim.add_bin(l, y0 + BIN_CATCH_DEPTH, r, y1)
	sim.finish_build()
	return sim


static func belt_speed(p: Part) -> float:
	return -BELT_SPEED if p.variant == 1 else BELT_SPEED


## True if the part at `cell` has a solid edge covering its whole `side`.
## Two parts touching along full edges skip that shared edge, so items glide across seams.
static func has_full_edge(machine: Machine, cell: Vector2i, side: Vector2i) -> bool:
	var part := machine.part_at(cell)
	if part == null:
		return false
	match part.type:
		&"block", &"spawner", &"conveyor":
			return true
		&"sorter":
			# Its belt and chute walls cover every side but the open bottom.
			return side != Vector2i.DOWN
		&"panel":
			return side == PANEL_SIDES[part.variant]
		&"ramp":
			if side == Vector2i.DOWN:
				return true
			# Unflipped ramps slope down to the right, so their solid side is on the left.
			return side == (Vector2i.RIGHT if part.variant == 1 else Vector2i.LEFT)
	return false


## The rectangle a panel fills inside its tile.
static func panel_rect(p: Part) -> Rect2:
	var origin := Vector2(p.cell * T)
	match PANEL_SIDES[p.variant]:
		Vector2i.UP:
			return Rect2(origin, Vector2(T, PANEL_THICKNESS))
		Vector2i.RIGHT:
			return Rect2(origin + Vector2(T - PANEL_THICKNESS, 0), Vector2(PANEL_THICKNESS, T))
		Vector2i.DOWN:
			return Rect2(origin + Vector2(0, T - PANEL_THICKNESS), Vector2(T, PANEL_THICKNESS))
	return Rect2(origin, Vector2(PANEL_THICKNESS, T))


## A thin slab. Its short ends are left off where it continues into a matching panel or a
## solid, so a row of panels makes one smooth floor and a wall meets a floor without a lip.
static func _add_panel(sim: Simulation, machine: Machine, p: Part) -> void:
	var r := panel_rect(p)
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	var side := PANEL_SIDES[p.variant]
	if side == Vector2i.UP or side == Vector2i.DOWN:
		_solid(sim, x0, y0, x1, y0)
		_solid(sim, x1, y1, x0, y1)
		if not _panel_continues(machine, p, Vector2i.LEFT):
			_solid(sim, x0, y1, x0, y0)
		if not _panel_continues(machine, p, Vector2i.RIGHT):
			_solid(sim, x1, y0, x1, y1)
	else:
		_solid(sim, x1, y0, x1, y1)
		_solid(sim, x0, y1, x0, y0)
		if not _panel_continues(machine, p, Vector2i.UP):
			_solid(sim, x0, y0, x1, y0)
		if not _panel_continues(machine, p, Vector2i.DOWN):
			_solid(sim, x1, y1, x0, y1)


static func _panel_continues(machine: Machine, p: Part, direction: Vector2i) -> bool:
	var next := machine.part_at(p.cell + direction)
	if next != null and next.type == &"panel" and next.variant == p.variant:
		return true
	return has_full_edge(machine, p.cell + direction, -direction)


## A full-tile solid box. `top_speed` makes the top surface a belt.
static func _add_box(sim: Simulation, machine: Machine, p: Part, top_speed: float) -> void:
	sim.set_solid(p.cell, Simulation.Solid.BOX)
	var x0 := float(p.cell.x * T)
	var y0 := float(p.cell.y * T)
	var x1 := x0 + T
	var y1 := y0 + T
	if not has_full_edge(machine, p.cell + Vector2i.UP, Vector2i.DOWN):
		var friction := BELT_FRICTION if top_speed != 0.0 else SURFACE_FRICTION
		_solid(sim, x0, y0, x1, y0, top_speed, friction)
	if not has_full_edge(machine, p.cell + Vector2i.RIGHT, Vector2i.LEFT):
		_solid(sim, x1, y0, x1, y1)
	if not has_full_edge(machine, p.cell + Vector2i.DOWN, Vector2i.UP):
		_solid(sim, x1, y1, x0, y1)
	if not has_full_edge(machine, p.cell + Vector2i.LEFT, Vector2i.RIGHT):
		_solid(sim, x0, y1, x0, y0)


static func _add_ramp(sim: Simulation, machine: Machine, p: Part, x0: float, y0: float, x1: float, y1: float) -> void:
	var flipped := p.variant == 1
	sim.set_solid(p.cell, Simulation.Solid.RAMP_DOWN_LEFT if flipped else Simulation.Solid.RAMP_DOWN_RIGHT)
	if flipped:
		_solid(sim, x0, y1, x1, y0)
		if not has_full_edge(machine, p.cell + Vector2i.RIGHT, Vector2i.LEFT):
			_solid(sim, x1, y0, x1, y1)
	else:
		_solid(sim, x0, y0, x1, y1)
		if not has_full_edge(machine, p.cell + Vector2i.LEFT, Vector2i.RIGHT):
			_solid(sim, x0, y1, x0, y0)
	if not has_full_edge(machine, p.cell + Vector2i.DOWN, Vector2i.UP):
		_solid(sim, x1, y1, x0, y1)


## A roller as a 12-sided outline whose surface moves at `speed` (positive turns clockwise
## on screen, so the top of a left-hand roller moves right, toward the gap).
static func _add_roller(sim: Simulation, cx: float, cy: float, radius: float, speed: float) -> void:
	for i in 12:
		var j := (i + 1) % 12
		sim.add_segment(Segment.new(
				cx + CIRCLE_12[i * 2] * radius, cy + CIRCLE_12[i * 2 + 1] * radius,
				cx + CIRCLE_12[j * 2] * radius, cy + CIRCLE_12[j * 2 + 1] * radius,
				speed, ROLLER_FRICTION))


## Side walls down to the top rollers' middle (`roller_y`), then a short ledge in to each
## roller's outer corner, so nothing slips down the outside of the rollers.
static func _add_crusher_housing(sim: Simulation, x0: float, y0: float, x1: float, roller_y: float, ledge: float) -> void:
	_solid(sim, x0, y0, x0, roller_y)
	_solid(sim, x0, roller_y, x0 + ledge, roller_y)
	_solid(sim, x1, roller_y, x1, y0)
	_solid(sim, x1 - ledge, roller_y, x1, roller_y)


static func _solid(sim: Simulation, ax: float, ay: float, bx: float, by: float, speed := 0.0, friction := SURFACE_FRICTION, passes: StringName = &"") -> void:
	sim.add_segment(Segment.new(ax, ay, bx, by, speed, friction, passes))
