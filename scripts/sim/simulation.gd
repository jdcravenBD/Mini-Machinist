class_name Simulation
extends RefCounted
## Item physics for one running machine.
##
## The heavy lifting (items as rigid polygons, contacts, belts, sleeping, spawners, crushers
## and bins) runs in native code: ItemWorld, built from native/src (see native/CMakeLists.txt).
## This class feeds it parts and item names, and turns its results back into names.
##
## Items are identified by a type id: one per material, size and outline shape, numbered
## the same way in every simulation (see type_id) so drawing can batch by it.

const TICK_RATE := 60

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

## Crucibles and the smelting parts touching them, run after the physics each tick.
var smelters: Array[Smelter] = []
## Crucible cell -> its Smelter, for drawing.
var smelters_by_cell := {}

var _bin_rects: Array[Rect2] = []
var _wall_groups := 0


func _init() -> void:
	# Registered in type_id order, so the native ids match it.
	for kind in ItemDefs.ORDER:
		for size in ItemDefs.SIZES:
			for shape in ItemDefs.SHAPES.size():
				world.register_type(ItemDefs.ORDER.find(kind), ItemDefs.size_rank(size), shape, ItemDefs.outline(kind, size, shape))


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
	world.add_segment(seg.ax, seg.ay, seg.bx, seg.by, seg.surface_speed, seg.friction, ItemDefs.ORDER.find(seg.passes), seg.belt, seg.group)


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


## A new id for a group of walls that can be switched off together.
func new_wall_group() -> int:
	_wall_groups += 1
	return _wall_groups - 1


## A sorter box: items whose centers enter `intake` go inside, then drop out at `drop` (the
## box's bottom middle) if their material is `filter`, or come out past `out_x` on the belt
## line `out_y` moving at `out_vx`.
func add_sorter(intake: Rect2, filter: StringName, out_x: float, out_y: float, out_vx: float, drop_x: float, drop_y: float) -> void:
	world.add_sorter(intake.position.x, intake.position.y, intake.end.x, intake.end.y,
			ItemDefs.ORDER.find(filter), out_x, out_y, out_vx, drop_x, drop_y)


## An area that swallows items while open; returns its id for Smelter.
func add_intake(area: Rect2) -> int:
	return world.add_intake(area.position.x, area.position.y, area.end.x, area.end.y)


func add_smelter(cell: Vector2i, smelter: Smelter) -> void:
	smelters.append(smelter)
	smelters_by_cell[cell] = smelter


func finish_build() -> void:
	world.finish_build()


# --- Running and reading ---------------------------------------------------------------

func step() -> void:
	world.step()
	for smelter in smelters:
		smelter.step(self)


## Drops an item into the world (tests and future player actions). Returns its index.
func add_item(kind: StringName, size: StringName, shape: int, x: float, y: float, c := 1.0, s := 0.0, vx := 0.0, vy := 0.0) -> int:
	return world.add_item(type_id(kind, size, shape), x, y, c, s, vx, vy)


func item_count() -> int:
	return world.item_count()


func sleeping_count() -> int:
	return world.sleeping_count()


## One item's state: kind, size (names), shape, x, y, c, s, vx, vy, w, radius, sleeping,
## carried, and world (its outline in world space as flat x, y pairs).
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


## Per item type id, the transforms of every item of that type, ready for a MultiMesh.
func draw_buffers() -> Array:
	return world.draw_buffers(type_count())
