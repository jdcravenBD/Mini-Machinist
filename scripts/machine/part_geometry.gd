class_name PartGeometry
## Turns a Machine's parts into a ready-to-run Simulation: collision segments, spawners
## and bins. Shapes are in pixels, measured from each part's top-left corner.

const T := PartDefs.TILE
## Crucible cell -> its wall group, while building.
static var _crucible_groups := {}
const BELT_SPEED := 64.0
## Friction coefficients: belts grip hard so they drag items up to speed quickly.
const BELT_FRICTION := 0.9
const SURFACE_FRICTION := 0.6
## Ticks between spawns (60 ticks = 1 second).
const SPAWN_INTERVAL := 30
const HOPPER_GAP := 18.0
const PANEL_THICKNESS := 6.0
## Conveyors are half a tile tall, with the belt on top.
const CONVEYOR_HEIGHT := 16.0
## A sorter is a conveyor-sized box with a hood rising this far above the belt line.
const SORTER_HOOD := 6.0
## How far in front of its mouth, and above its hood, a sorter takes items in.
const SORTER_REACH := 10.0
const SORTER_TOP_REACH := 18.0
## How far a crucible's walls sit inside its tile, and how far below the rim an item must
## fall before the crucible takes it.
const CRUCIBLE_WALL := 2.0
const CRUCIBLE_MOUTH := 6.0

## Crushers are nothing but toothed rollers: a large crusher's two each fill a tile, a small
## crusher's four each fill a quarter of its tile. They nearly touch, so nothing falls
## between them; the crusher itself decides what goes through (see Simulation.Crusher).
const LARGE_ROLLER := 15.0
const SMALL_ROLLER := 7.5
## How fast the roller surfaces move, carrying what sits on them in toward the middle.
## Their teeth bite, so they grip far harder than a smooth surface.
const ROLLER_SPEED := 40.0
const ROLLER_GRIP := 3.0
## Ticks to crush one item (60 ticks = 1 second). Each crusher runs a little faster than the
## one before it can feed it (spawner 2 chunks/s, large 2.5 chunks/s = 7.5 bits/s, small 10
## bits/s), so a simple line never backs up.
const LARGE_CRUSH_TICKS := 24
const SMALL_CRUSH_TICKS := 6
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
	_crucible_groups.clear()
	sim.set_bounds(Machine.WIDTH, Machine.HEIGHT)
	for p in machine.sorted_parts():
		var x0 := float(p.cell.x * T)
		var y0 := float(p.cell.y * T)
		var size := PartDefs.size_of(p.type)
		var x1 := x0 + size.x * T
		var y1 := y0 + size.y * T
		match p.type:
			&"block":
				_add_box(sim, machine, p)
			&"spawner":
				_add_box(sim, machine, p)
				sim.add_spawner(x0 + T * 0.5, y1, SPAWN_INTERVAL)
			&"conveyor":
				_add_conveyor(sim, machine, p)
			&"sorter":
				_add_sorter(sim, p, x0, y0, x1)
			&"panel":
				_add_panel(sim, machine, p)
			&"heating_coil", &"bellows", &"insulation", &"skimmer", &"tilter":
				_add_box(sim, machine, p)
			&"crucible":
				# A cup: thin walls and a floor. What falls in is swallowed into the melt. The
				# walls switch off while it's tipped (see Smelter).
				var l := x0 + CRUCIBLE_WALL
				var r := x1 - CRUCIBLE_WALL
				var b := y1 - CRUCIBLE_WALL
				var group := sim.new_wall_group()
				for wall in [Segment.new(l, y0, l, b), Segment.new(l, b, r, b), Segment.new(r, b, r, y0)]:
					wall.group = group
					sim.add_segment(wall)
				_crucible_groups[p.cell] = group
			&"large_crusher":
				# Two big rollers side by side, turning in toward each other at the top, so what
				# lands on them rolls into the dip in the middle. The intake reaches high enough
				# to take the lower of two chunks wedged in a hopper's outlet just above.
				var mid := x0 + T
				_add_roller(sim, x0 + T * 0.5, y0 + T * 0.5, LARGE_ROLLER, ROLLER_SPEED)
				_add_roller(sim, x1 - T * 0.5, y0 + T * 0.5, LARGE_ROLLER, -ROLLER_SPEED)
				sim.add_crusher(&"chunk", &"bit", CRUSH_PIECES, LARGE_CRUSH_TICKS,
						Rect2(mid - 7.0, y0 - 10.0, 14.0, T * 0.5 + 10.0), y0 + T * 0.5, mid, y1)
			&"small_crusher":
				# Four small rollers, one per quarter of the tile. Each pair turns in toward the
				# middle, so what lands on top rolls into the dip between the top pair.
				var mid := x0 + T * 0.5
				for row in 2:
					var cy := y0 + T * (0.25 + row * 0.5)
					_add_roller(sim, x0 + T * 0.25, cy, SMALL_ROLLER, ROLLER_SPEED)
					_add_roller(sim, x0 + T * 0.75, cy, SMALL_ROLLER, -ROLLER_SPEED)
				sim.add_crusher(&"bit", &"gravel", CRUSH_PIECES, SMALL_CRUSH_TICKS,
						Rect2(mid - 4.0, y0 - 6.0, 8.0, T * 0.25 + 6.0), y0 + T * 0.5, mid, y1)
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
	for p in machine.sorted_parts():
		if p.type == &"crucible":
			_add_smelter(sim, machine, p, _crucible_groups[p.cell])
	_add_heat(sim, machine)
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
		&"block", &"spawner", &"heating_coil", &"bellows", &"insulation", &"skimmer", &"tilter":
			return true
		&"conveyor":
			# Only its top: the belt runs the full width, but the body is half a tile tall.
			return side == Vector2i.UP
		&"sorter":
			# Its hood covers its top; its sides only reach halfway down.
			return side == Vector2i.UP
		&"panel":
			return side == PANEL_SIDES[part.variant]
		&"ramp":
			if side == Vector2i.DOWN:
				return true
			# Unflipped ramps slope down to the right, so their solid side is on the left.
			return side == (Vector2i.RIGHT if part.variant == 1 else Vector2i.LEFT)
	return false


## A closed box in a belt line. Everything goes in through its mouth (the side the belt comes
## from) or the top of its hood, out of sight; matches drop out the bottom, the rest come out
## the far side onto the next belt. Being solid and seamless, a row of sorters can't snag.
static func _add_sorter(sim: Simulation, p: Part, x0: float, y0: float, x1: float) -> void:
	sim.set_solid(p.cell, Simulation.Solid.TOP_HALF)
	var top := y0 - SORTER_HOOD
	var bottom := y0 + CONVEYOR_HEIGHT
	_solid(sim, x0, top, x1, top)
	_solid(sim, x1, top, x1, bottom)
	_solid(sim, x1, bottom, x0, bottom)
	_solid(sim, x0, bottom, x0, top)
	var speed := belt_speed(p)
	var intake := Rect2(x0 - SORTER_REACH, top - SORTER_TOP_REACH, x1 - x0 + SORTER_REACH, bottom - top + SORTER_TOP_REACH)
	if speed < 0.0:
		intake.position.x = x0
	sim.add_sorter(intake, p.filter, x1 if speed > 0.0 else x0, y0, speed, (x0 + x1) * 0.5, bottom)


## A half-tile box along the top of its tile with a belt surface. Its ends are left off where
## it continues into another belt or a solid, so a row of conveyors is one smooth belt.
static func _add_conveyor(sim: Simulation, machine: Machine, p: Part) -> void:
	sim.set_solid(p.cell, Simulation.Solid.TOP_HALF)
	var x0 := float(p.cell.x * T)
	var y0 := float(p.cell.y * T)
	var x1 := x0 + T
	var y1 := y0 + CONVEYOR_HEIGHT
	if not has_full_edge(machine, p.cell + Vector2i.UP, Vector2i.DOWN):
		sim.add_segment(Segment.new(x0, y0, x1, y0, belt_speed(p), BELT_FRICTION, &"", true))
	_solid(sim, x1, y1, x0, y1)
	if not _belt_continues(machine, p.cell + Vector2i.RIGHT, Vector2i.LEFT):
		_solid(sim, x1, y0, x1, y1)
	if not _belt_continues(machine, p.cell + Vector2i.LEFT, Vector2i.RIGHT):
		_solid(sim, x0, y1, x0, y0)


static func _belt_continues(machine: Machine, cell: Vector2i, side: Vector2i) -> bool:
	var next := machine.part_at(cell)
	if next != null and (next.type == &"conveyor" or next.type == &"sorter"):
		return true
	return has_full_edge(machine, cell, side)


## Finds the smelting parts touching a crucible and hands the lot to the simulation.
static func _add_smelter(sim: Simulation, machine: Machine, crucible: Part, walls: int) -> void:
	var x0 := float(crucible.cell.x * T)
	var y0 := float(crucible.cell.y * T)
	var width := float(PartDefs.size_of(crucible.type).x * T)
	var mouth := Rect2(x0 + CRUCIBLE_WALL, y0 + CRUCIBLE_MOUTH, width - CRUCIBLE_WALL * 2.0, T - CRUCIBLE_MOUTH - CRUCIBLE_WALL)
	var smelter := Smelter.new(x0, y0, width, sim.add_intake(mouth))
	smelter.walls = walls
	for touching in _touching_parts(machine, crucible):
		var neighbor: Part = touching[0]
		var side: Vector2i = touching[1]
		match neighbor.type:
			&"heating_coil":
				var bellows := 0
				for around in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
					var beside := machine.part_at(neighbor.cell + around)
					if beside != null and beside.type == &"bellows":
						bellows += 1
				smelter.coils.append(bellows)
			&"insulation":
				smelter.insulation += 1
			&"skimmer":
				# Slag drops out the skimmer's side facing away from the crucible's middle.
				smelter.has_skimmer = true
				var outward := 1.0 if neighbor.cell.x * T + T * 0.5 > x0 + width * 0.5 else -1.0
				smelter.skim_x = neighbor.cell.x * T + T * 0.5 + outward * T * 0.5
				smelter.skim_y = neighbor.cell.y * T + T * 0.5
				smelter.skim_dir = outward
			&"tilter":
				if side.x != 0:
					smelter.pour_dir = -side.x
	sim.add_smelter(crucible.cell, smelter)


## Fills the heat map with every part's material (insulation, or metal for everything else),
## then sets up the heating coils, each boosted by the bellows touching it.
static func _add_heat(sim: Simulation, machine: Machine) -> void:
	for p in machine.sorted_parts():
		var material := Simulation.HeatMaterial.INSULATION if p.type == &"insulation" else Simulation.HeatMaterial.METAL
		sim.fill_heat(Vector2(p.cell * T), PartShapes.of(p), material)
	for p in machine.sorted_parts():
		if p.type != &"heating_coil":
			continue
		var bellows := 0
		for touching in _touching_parts(machine, p):
			if touching[0].type == &"bellows":
				bellows += 1
		sim.add_heater(Rect2(Vector2(p.cell * T), Vector2(T, T)), bellows)


## Every part sharing an edge with `part`, each once, as [neighbor, side it's on].
static func _touching_parts(machine: Machine, part: Part) -> Array:
	var found: Array = []
	var seen := {}
	var own := part.cells()
	for cell in own:
		for side in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next := machine.part_at(cell + side)
			if next != null and next != part and not seen.has(next):
				seen[next] = true
				found.append([next, side])
	return found


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


## A full-tile solid box.
static func _add_box(sim: Simulation, machine: Machine, p: Part) -> void:
	sim.set_solid(p.cell, Simulation.Solid.BOX)
	var x0 := float(p.cell.x * T)
	var y0 := float(p.cell.y * T)
	var x1 := x0 + T
	var y1 := y0 + T
	if not has_full_edge(machine, p.cell + Vector2i.UP, Vector2i.DOWN):
		_solid(sim, x0, y0, x1, y0)
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
				speed, ROLLER_GRIP))


static func _solid(sim: Simulation, ax: float, ay: float, bx: float, by: float, speed := 0.0, friction := SURFACE_FRICTION, passes: StringName = &"") -> void:
	sim.add_segment(Segment.new(ax, ay, bx, by, speed, friction, passes))
