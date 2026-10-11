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
				_add_box(sim, machine, p, -BELT_SPEED if p.flipped else BELT_SPEED)
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


## True if the part at `cell` has a solid edge covering its whole `side`.
## Two parts touching along full edges skip that shared edge, so items glide across seams.
static func has_full_edge(machine: Machine, cell: Vector2i, side: Vector2i) -> bool:
	var part := machine.part_at(cell)
	if part == null:
		return false
	match part.type:
		&"block", &"spawner", &"conveyor":
			return true
		&"ramp":
			if side == Vector2i.DOWN:
				return true
			# Unflipped ramps slope down to the right, so their solid side is on the left.
			return side == (Vector2i.RIGHT if part.flipped else Vector2i.LEFT)
	return false


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
	sim.set_solid(p.cell, Simulation.Solid.RAMP_DOWN_LEFT if p.flipped else Simulation.Solid.RAMP_DOWN_RIGHT)
	if p.flipped:
		_solid(sim, x0, y1, x1, y0)
		if not has_full_edge(machine, p.cell + Vector2i.RIGHT, Vector2i.LEFT):
			_solid(sim, x1, y0, x1, y1)
	else:
		_solid(sim, x0, y0, x1, y1)
		if not has_full_edge(machine, p.cell + Vector2i.LEFT, Vector2i.RIGHT):
			_solid(sim, x0, y1, x0, y0)
	if not has_full_edge(machine, p.cell + Vector2i.DOWN, Vector2i.UP):
		_solid(sim, x1, y1, x0, y1)


static func _solid(sim: Simulation, ax: float, ay: float, bx: float, by: float, speed := 0.0, friction := SURFACE_FRICTION) -> void:
	sim.add_segment(Segment.new(ax, ay, bx, by, speed, friction))
