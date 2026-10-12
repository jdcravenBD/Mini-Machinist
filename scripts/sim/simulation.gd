class_name Simulation
extends RefCounted
## Item physics for one running machine.
##
## The heavy lifting (items as rigid polygons, belts, spawners, crushers, sorters, bins, heat,
## and molten and hardened metal pixels) runs in native code: ItemWorld, built from native/src
## (see native/CMakeLists.txt). This class feeds it parts and item names, and turns its results
## back into names.
##
## Items are identified by a type id: one per material, size and outline shape, numbered
## the same way in every simulation (see type_id) so drawing can batch by it.

const TICK_RATE := 60
## Heat a coil adds to each cell of itself per tick, and how much each pumping bellows touching
## it multiplies that by (on top of 1).
const COIL_POWER := 6.5
const BELLOWS_BOOST := 1.0
## Bellows pump for the first half of every cycle (ticks).
const BELLOWS_CYCLE := 120
## What heat cells are made of (matches ItemWorld's materials).
enum HeatMaterial { AIR, METAL, INSULATION }

## Solid tile kinds, for pushing out items that a heavy pile squeezed into a solid.
## TOP_HALF fills only the top half of its tile (a conveyor).
enum Solid { NONE, BOX, RAMP_DOWN_RIGHT, RAMP_DOWN_LEFT, TOP_HALF }

var world := ItemWorld.new()

var tick: int:
	get:
		return world.get_tick()
## Items that fell out of the world.
var lost: int:
	get:
		return world.get_lost()
## Items caught by bins, by material name.
var delivered: Dictionary:
	get:
		var result := {}
		var raw: Dictionary = world.delivered_by_kind()
		for kind_index in raw:
			result[ItemDefs.ORDER[kind_index]] = raw[kind_index]
		return result

## Heating coils: [heater id in the world, number of bellows touching the coil].
var heaters: Array = []

var _bin_rects: Array[Rect2] = []
## Piston cell -> its id, for drawing its plate.
var pistons_by_cell := {}


func _init() -> void:
	# Registered in type_id order, so the native ids match it.
	for kind in ItemDefs.ORDER:
		for size in ItemDefs.SIZES:
			for shape in ItemDefs.SHAPES.size():
				world.register_type(ItemDefs.ORDER.find(kind), ItemDefs.size_rank(size), shape, ItemDefs.outline(kind, size, shape))
	for kind in ItemDefs.ORDER:
		world.set_melt_point(ItemDefs.ORDER.find(kind), ItemDefs.DEFS[kind]["melt"])


## How often a signal fires (ticks), by its variant (R): 1 s, 2 s, 4 s, half a second.
const SIGNAL_INTERVALS := [60, 120, 240, 30]
## How long a signal stays lit after firing (ticks), for drawing.
const SIGNAL_LIT_TICKS := 8


static func signal_interval(variant: int) -> int:
	return SIGNAL_INTERVALS[variant % SIGNAL_INTERVALS.size()]


## True while a signal with this variant shows that it just fired.
static func is_signal_lit(at_tick: int, variant: int) -> bool:
	return at_tick % signal_interval(variant) < SIGNAL_LIT_TICKS


## True while bellows are pumping.
static func is_pumping(at_tick: int) -> bool:
	return at_tick % BELLOWS_CYCLE < BELLOWS_CYCLE / 2


static func type_count() -> int:
	return ItemDefs.ORDER.size() * ItemDefs.SIZES.size() * ItemDefs.SHAPES.size()


static func type_id(kind: StringName, size: StringName, shape: int) -> int:
	return (ItemDefs.ORDER.find(kind) * ItemDefs.SIZES.size() + ItemDefs.size_rank(size)) * ItemDefs.SHAPES.size() + shape


## [kind, size, shape] for a type id.
static func type_info(id: int) -> Array:
	var shapes := ItemDefs.SHAPES.size()
	var sizes := ItemDefs.SIZES.size()
	return [ItemDefs.ORDER[id / (shapes * sizes)], ItemDefs.SIZES.keys()[(id / shapes) % sizes], id % shapes]


# --- Building --------------------------------------------------------------------------

func set_bounds(cols: int, rows: int) -> void:
	world.set_bounds(cols, rows)


func set_solid(cell: Vector2i, kind: Solid) -> void:
	world.set_solid(cell.x, cell.y, kind)


## Collected until finish_build(), which joins straight runs and indexes them.
func add_segment(seg: Segment) -> void:
	world.add_segment(seg.ax, seg.ay, seg.bx, seg.by, seg.surface_speed, seg.friction, ItemDefs.ORDER.find(seg.passes), seg.belt)


## Emits a repeating ore/rock chunk pattern from a point, pausing while the output is blocked.
func add_spawner(x: float, y: float, interval: int) -> void:
	var ore := PackedInt32Array()
	var rock := PackedInt32Array()
	for shape in ItemDefs.SHAPES.size():
		ore.append(type_id(&"iron_ore", &"chunk", shape))
		rock.append(type_id(&"rock", &"chunk", shape))
	world.add_spawner(x, y, interval, ore, rock)


## Consumes items whose centers enter the area.
func add_bin(min_x: float, min_y: float, max_x: float, max_y: float) -> void:
	_bin_rects.append(Rect2(min_x, min_y, max_x - min_x, max_y - min_y))
	world.add_bin(min_x, min_y, max_x, max_y)


## A crusher takes items that reach `intake`, pushes them down to `press_y`, and drops
## pieces out at `exit`. See ItemWorld::Crusher for the rules.
func add_crusher(takes: StringName, makes: StringName, pieces: int, duration: int, intake: Rect2, press_y: float, exit_x: float, exit_y: float) -> void:
	world.add_crusher(ItemDefs.size_rank(takes), ItemDefs.size_rank(makes), pieces, duration,
			intake.position.x, intake.position.y, intake.end.x, intake.end.y, press_y, exit_x, exit_y)


## Fills in what a part covers: its material in the heat map, and wall in the pixel layer
## (molten metal can't flow into it).
func fill_part(origin: Vector2, shapes: Dictionary, material: HeatMaterial) -> void:
	for r in shapes["rects"]:
		var rect: Rect2 = r
		world.heat_fill_rect(origin.x + rect.position.x, origin.y + rect.position.y, origin.x + rect.end.x, origin.y + rect.end.y, material)
		world.pixel_fill_rect(origin.x + rect.position.x, origin.y + rect.position.y, origin.x + rect.end.x, origin.y + rect.end.y)
	var outlines: Array[PackedVector2Array] = []
	outlines.assign(shapes["polygons"])
	for circle in shapes["circles"]:
		var ring := PackedVector2Array()
		for i in 12:
			ring.append(circle[0] + Vector2(PartGeometry.CIRCLE_12[i * 2], PartGeometry.CIRCLE_12[i * 2 + 1]) * circle[1])
		outlines.append(ring)
	for outline in outlines:
		world.heat_fill_polygon(_flat(outline, origin), material)
		world.pixel_fill_polygon(_flat(outline, origin))


func add_signal(interval: int) -> int:
	return world.add_signal(interval)


## A piston at `cell` whose plate spans x0..x1 and sits with its bottom at `top` when in.
func add_piston(cell: Vector2i, x0: float, x1: float, top: float, travel: float, power: int, signals: PackedInt32Array) -> void:
	pistons_by_cell[cell] = world.add_piston(x0, x1, top, travel, power, signals)


## How far down a piston's plate is.
func piston_extension(cell: Vector2i) -> float:
	return world.piston_extension(pistons_by_cell[cell]) if pistons_by_cell.has(cell) else 0.0


## A skimmer's box: molten slag touching it is taken off and dropped out its far side.
func add_skimmer(area: Rect2) -> void:
	var lumps := PackedInt32Array()
	for shape in ItemDefs.SHAPES.size():
		lumps.append(type_id(&"slag", &"bit", shape))
	world.add_skimmer(area.position.x, area.position.y, area.end.x, area.end.y, lumps)


## Pours molten iron (or slag) at `temp` into the empty pixels of `area`.
func add_liquid(area: Rect2, iron: bool, temp: float) -> void:
	world.add_liquid(area.position.x, area.position.y, area.end.x, area.end.y, iron, temp)


## How many pixels of molten iron and slag there are, and their average heights:
## {"iron", "slag", "iron_y", "slag_y"}.
func pixel_counts() -> Dictionary:
	return world.pixel_counts()


## A heating coil over `area`, with `bellows` bellows touching it.
func add_heater(area: Rect2, bellows: int) -> void:
	heaters.append([world.add_heater(area.position.x, area.position.y, area.end.x, area.end.y), bellows])


## The temperature at a point in the world.
func heat_at(point: Vector2) -> float:
	return world.heat_at(point.x, point.y)


static func _flat(points: PackedVector2Array, origin: Vector2) -> PackedFloat64Array:
	var flat := PackedFloat64Array()
	for point in points:
		flat.append(origin.x + point.x)
		flat.append(origin.y + point.y)
	return flat


## A sorter: `box` with a passage through it from `pass_top` down to the belt at `belt_y`,
## running at `belt_vx` (its grate is plain segments that let `filter` through). Items landing
## within `top_reach` above its roof are taken in and set down on that belt inside.
func add_sorter(box: Rect2, pass_top: float, belt_y: float, top_reach: float, filter: StringName, belt_vx: float) -> void:
	world.add_sorter(box.position.x, box.position.y, box.end.x, box.end.y, pass_top, belt_y, top_reach,
			ItemDefs.ORDER.find(filter), belt_vx)


func finish_build() -> void:
	world.finish_build()


# --- Running and reading ---------------------------------------------------------------

func step() -> void:
	var pumping := is_pumping(tick)
	for heater in heaters:
		var boost: float = 1.0 + (BELLOWS_BOOST * heater[1] if pumping else 0.0)
		world.set_heater_power(heater[0], COIL_POWER * boost)
	world.step()


## Drops an item into the world (tests and future player actions). Returns its index.
func add_item(kind: StringName, size: StringName, shape: int, x: float, y: float, c := 1.0, s := 0.0, vx := 0.0, vy := 0.0) -> int:
	return world.add_item(type_id(kind, size, shape), x, y, c, s, vx, vy)


func item_count() -> int:
	return world.item_count()


func sleeping_count() -> int:
	return world.sleeping_count()


## One item's state: kind, size (names), shape, x, y, c, s, vx, vy, w, radius, sleeping,
## carried, temp, and world (its outline in world space as flat x, y pairs).
func item(index: int) -> Dictionary:
	var data: Dictionary = world.get_item(index)
	data["kind"] = ItemDefs.ORDER[data["kind"]]
	data["size"] = ItemDefs.SIZES.keys()[data["size"]]
	return data


## Every item's state, for checking two runs are identical.
func snapshot() -> PackedFloat64Array:
	return world.snapshot()


func bin_count() -> int:
	return _bin_rects.size()


func bin_rect(index: int) -> Rect2:
	return _bin_rects[index]


## Items a bin caught, keyed like &"rock gravel".
func bin_counts(index: int) -> Dictionary:
	var result := {}
	var raw: Dictionary = world.bin_counts(index)
	for key in raw:
		var name := "%s %s" % [ItemDefs.ORDER[key / 16], ItemDefs.SIZES.keys()[key % 16]]
		result[StringName(name)] = raw[key]
	return result


func crusher_count() -> int:
	return world.crusher_count()


## What a crusher is doing: "held" is false when it's empty; otherwise "type" (an item type
## id), "c", "s", "held_x", "held_y", "press_y", "exit_x", "passing" and "progress" (0 to 1).
func crusher_state(index: int) -> Dictionary:
	return world.crusher_state(index)


## How many items a spawner has made.
func spawned(index: int) -> int:
	return world.spawned_count(index)


func clear_spawners() -> void:
	world.clear_spawners()


## How deep the deepest corner of any item sits inside another (for tests).
func max_overlap() -> float:
	return world.max_overlap()


## Takes another simulation's items and clock (for tests that rebuild a machine mid-run).
func copy_items_from(other: Simulation) -> void:
	world.copy_items_from(other.world)


## Per item type id, the transform and color of every item of that type, ready for a
## MultiMesh (12 floats each).
func draw_buffers() -> Array:
	return world.draw_buffers(type_count())
