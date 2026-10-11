class_name Simulation
extends RefCounted
## Deterministic item physics: gravity, static segments, belts, and item-vs-item pushing.
##
## Position-based: each substep predicts where items go, pushes them apart and out of
## walls, then derives velocity from how far they actually moved. That way a push that
## stops an item also stops its speed, so piles settle instead of jittering.
##
## The same machine always produces the same result. To keep it that way:
## - advance only through step() (fixed timestep, fixed substeps)
## - iterate items and segments in a fixed order (never Dictionary key order for physics)
## - use only + - * / and sqrt on item floats (no trig, no randomness)

const TICK_RATE := 60
const SUBSTEPS := 2
const H := 1.0 / (TICK_RATE * SUBSTEPS)
const GRAVITY := 900.0
const MAX_SPEED := 400.0
## Most an item may move in one substep, pushes included. Kept below the smallest radius so
## nothing can tunnel through a wall or squeeze past the point where two solids meet.
const MAX_STEP := 3.5
## Fraction of sliding between two touching items removed per substep.
const ITEM_FRICTION := 0.1
const MAX_ITEMS := 600
## Largest item radius; static segments are registered with this much margin.
const MAX_RADIUS := 6.0
const SEG_CELL := 32.0
const ITEM_CELL := 12.0
## Solid tile kinds, for pushing out items that a heavy pile squeezed into a solid.
enum Solid { NONE, BOX, RAMP_DOWN_RIGHT, RAMP_DOWN_LEFT }
const INV_SQRT2 := 0.7071067811865476
## An item that moves less than this (pixels per tick) for SLEEP_TICKS in a row goes to sleep.
const SLEEP_MOVE := 0.2
const SLEEP_TICKS := 30
## An item hitting a sleeper faster than this wakes it. Gentle contact (an item settling
## onto a pile) doesn't, or every pile would keep re-waking itself.
const WAKE_SPEED := 60.0
const WAKE_MARGIN := 1.0
## Each sleeper checks it is still held up from below once every this many ticks.
const SUPPORT_CHECK_TICKS := 4
## How close (pixels) and how far below (fraction of the contact direction) something must
## be to count as holding a sleeper up.
const SUPPORT_GAP := 0.5
const SUPPORT_SLOPE := 0.3


## Emits a repeating ore/rock pattern from a point, pausing while the output is blocked.
class Spawner:
	var x: float
	var y: float
	var interval: int
	var timer := 1
	var count := 0

	func _init(p_x: float, p_y: float, p_interval: int) -> void:
		x = p_x
		y = p_y
		interval = p_interval


## Consumes items whose centers enter its catch area.
class Bin:
	var min_x: float
	var min_y: float
	var max_x: float
	var max_y: float
	var caught := 0

	func _init(p_min_x: float, p_min_y: float, p_max_x: float, p_max_y: float) -> void:
		min_x = p_min_x
		min_y = p_min_y
		max_x = p_max_x
		max_y = p_max_y

	func contains(px: float, py: float) -> bool:
		return px > min_x and px < max_x and py > min_y and py < max_y


var items: Array[Item] = []
var segments: Array[Segment] = []
var spawners: Array[Spawner] = []
var bins: Array[Bin] = []
var tick := 0
var lost := 0
## Items consumed by bins, by kind.
var delivered := {}

var _kill_min_x := -64.0
var _kill_max_x := 64.0
var _kill_max_y := 64.0
## Cell key -> Array of segment indices, in the order segments were added.
var _seg_grid := {}
var _solid := PackedByteArray()
var _cols := 0
var _rows := 0
## Item grid from the latest substep (cell key -> item indices).
var _item_grid := {}


func set_bounds(cols: int, rows: int) -> void:
	_cols = cols
	_rows = rows
	_solid.resize(cols * rows)
	_solid.fill(Solid.NONE)
	_kill_min_x = -64.0
	_kill_max_x = cols * SEG_CELL + 64.0
	_kill_max_y = rows * SEG_CELL + 64.0


func set_solid(cell: Vector2i, kind: Solid) -> void:
	_solid[cell.y * _cols + cell.x] = kind


func add_segment(seg: Segment) -> void:
	var index := segments.size()
	segments.append(seg)
	var x0 := floori((minf(seg.ax, seg.bx) - MAX_RADIUS - 1.0) / SEG_CELL)
	var x1 := floori((maxf(seg.ax, seg.bx) + MAX_RADIUS + 1.0) / SEG_CELL)
	var y0 := floori((minf(seg.ay, seg.by) - MAX_RADIUS - 1.0) / SEG_CELL)
	var y1 := floori((maxf(seg.ay, seg.by) + MAX_RADIUS + 1.0) / SEG_CELL)
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var key := _cell_key(cx, cy)
			if _seg_grid.has(key):
				_seg_grid[key].append(index)
			else:
				_seg_grid[key] = [index]


func add_spawner(x: float, y: float, interval: int) -> void:
	spawners.append(Spawner.new(x, y, interval))


func add_bin(min_x: float, min_y: float, max_x: float, max_y: float) -> void:
	bins.append(Bin.new(min_x, min_y, max_x, max_y))


func step() -> void:
	_run_spawners()
	for it in items:
		it.prev_x = it.x
		it.prev_y = it.y
	for i in SUBSTEPS:
		_predict()
		_collide_items()
		_limit_moves()
		_collide_segments()
		_update_velocities()
	_update_sleep()
	_check_support()
	_collect()
	tick += 1


func delivered_total() -> int:
	var total := 0
	for kind in delivered:
		total += delivered[kind]
	return total


func sleeping_count() -> int:
	var count := 0
	for it in items:
		if it.sleeping:
			count += 1
	return count


## Snapshot of every item's state, for checking two runs are identical.
func snapshot() -> PackedFloat64Array:
	var data := PackedFloat64Array()
	for it in items:
		data.append_array([it.x, it.y, it.vx, it.vy])
	return data


func _run_spawners() -> void:
	for sp in spawners:
		sp.timer -= 1
		if sp.timer > 0:
			continue
		sp.timer = sp.interval
		if items.size() >= MAX_ITEMS or _is_blocked(sp.x, sp.y):
			continue
		# Every third bit is rock (the impurity). The small sideways offset follows a fixed
		# pattern so piles look natural while staying repeatable.
		var is_rock := sp.count % 3 == 2
		var radius := 6.0 if is_rock else 5.0
		var jitter := float((sp.count * 7) % 5 - 2)
		var kind := &"rock" if is_rock else &"iron_ore"
		items.append(Item.new(kind, radius, sp.x + jitter, sp.y + radius))
		sp.count += 1


func _is_blocked(x: float, y: float) -> bool:
	var reach := MAX_RADIUS * 2.0
	for it in items:
		var dx := it.x - x
		var dy := it.y - (y + MAX_RADIUS)
		if dx * dx + dy * dy < reach * reach:
			return true
	return false


## Moves every awake item by its velocity plus gravity, remembering where it started.
func _predict() -> void:
	for it in items:
		if it.sleeping:
			continue
		it.step_x = it.x
		it.step_y = it.y
		it.vy += GRAVITY * H
		var speed_sq := it.vx * it.vx + it.vy * it.vy
		if speed_sq > MAX_SPEED * MAX_SPEED:
			var k := MAX_SPEED / sqrt(speed_sq)
			it.vx *= k
			it.vy *= k
		it.x += it.vx * H
		it.y += it.vy * H


## Velocity is whatever movement survived the pushes this substep.
func _update_velocities() -> void:
	for it in items:
		if it.sleeping:
			continue
		it.vx = (it.x - it.step_x) / H
		it.vy = (it.y - it.step_y) / H


func _limit_moves() -> void:
	for it in items:
		if it.sleeping:
			continue
		var dx := it.x - it.step_x
		var dy := it.y - it.step_y
		var d2 := dx * dx + dy * dy
		if d2 > MAX_STEP * MAX_STEP:
			var k := MAX_STEP / sqrt(d2)
			it.x = it.step_x + dx * k
			it.y = it.step_y + dy * k


func _collide_segments() -> void:
	for it in items:
		if it.sleeping:
			continue
		_push_out_of_solid(it)
		var list = _seg_grid.get(_cell_key(floori(it.x / SEG_CELL), floori(it.y / SEG_CELL)))
		if list == null:
			continue
		for si in list:
			_resolve_segment(it, segments[si])


func _resolve_segment(it: Item, s: Segment) -> void:
	var t := ((it.x - s.ax) * s.dx + (it.y - s.ay) * s.dy) / s.len_sq
	t = clampf(t, 0.0, 1.0)
	var nx := it.x - (s.ax + s.dx * t)
	var ny := it.y - (s.ay + s.dy * t)
	var dist_sq := nx * nx + ny * ny
	if dist_sq >= it.radius * it.radius or dist_sq == 0.0:
		return
	var dist := sqrt(dist_sq)
	nx /= dist
	ny /= dist
	var pen := it.radius - dist
	it.x += nx * pen
	it.y += ny * pen
	if s.surface_speed != 0.0:
		it.belt_tick = tick

	# Friction pulls the item's sliding toward the surface's own movement (none unless a belt).
	var tnx := -ny
	var tny := nx
	var surface_step := s.surface_speed * H
	var slide := (it.x - it.step_x - s.tx * surface_step) * tnx + (it.y - it.step_y - s.ty * surface_step) * tny
	it.x -= tnx * slide * s.friction
	it.y -= tny * slide * s.friction


## If a heavy pile squeezed an item's center into a solid tile, move it out through the
## nearest open face. Faces shared with another solid never count as a way out.
func _push_out_of_solid(it: Item) -> void:
	var cx := floori(it.x / SEG_CELL)
	var cy := floori(it.y / SEG_CELL)
	var kind := _solid_at(cx, cy)
	if kind == Solid.NONE:
		return
	var lx := it.x - cx * SEG_CELL
	var ly := it.y - cy * SEG_CELL

	if kind == Solid.RAMP_DOWN_RIGHT or kind == Solid.RAMP_DOWN_LEFT:
		var down_right := kind == Solid.RAMP_DOWN_RIGHT
		var depth := (ly - lx) if down_right else (lx + ly - SEG_CELL)
		if depth > 0.0:
			_push_out_along(it, depth * INV_SQRT2, INV_SQRT2 if down_right else -INV_SQRT2, -INV_SQRT2)
		return

	# Prefer the faces on the side the item came from this tick, so an item squeezed into
	# the corner where two solids touch diagonally goes back where it was, not through.
	var from_x := signi(floori(it.prev_x / SEG_CELL) - cx)
	var from_y := signi(floori(it.prev_y / SEG_CELL) - cy)
	var best := INF
	var nx := 0.0
	var ny := 0.0
	for pass_index in 2:
		var any_side := pass_index == 1
		if (any_side or from_y < 0) and _is_open(cx, cy - 1, Vector2i.DOWN) and ly < best:
			best = ly
			nx = 0.0
			ny = -1.0
		if (any_side or from_x < 0) and _is_open(cx - 1, cy, Vector2i.RIGHT) and lx < best:
			best = lx
			nx = -1.0
			ny = 0.0
		if (any_side or from_x > 0) and _is_open(cx + 1, cy, Vector2i.LEFT) and SEG_CELL - lx < best:
			best = SEG_CELL - lx
			nx = 1.0
			ny = 0.0
		if (any_side or from_y > 0) and _is_open(cx, cy + 1, Vector2i.UP) and SEG_CELL - ly < best:
			best = SEG_CELL - ly
			nx = 0.0
			ny = 1.0
		if best != INF:
			_push_out_along(it, best, nx, ny)
			return


func _push_out_along(it: Item, depth: float, nx: float, ny: float) -> void:
	it.x += nx * (depth + it.radius)
	it.y += ny * (depth + it.radius)


func _solid_at(cx: int, cy: int) -> Solid:
	if cx < 0 or cy < 0 or cx >= _cols or cy >= _rows:
		return Solid.NONE
	return _solid[cy * _cols + cx] as Solid


## True if the cell can be exited into from its `side` (not blocked by a full solid face).
func _is_open(cx: int, cy: int, side: Vector2i) -> bool:
	match _solid_at(cx, cy):
		Solid.NONE:
			return true
		Solid.RAMP_DOWN_RIGHT:
			return side != Vector2i.DOWN and side != Vector2i.LEFT
		Solid.RAMP_DOWN_LEFT:
			return side != Vector2i.DOWN and side != Vector2i.RIGHT
	return false


func _collide_items() -> void:
	var grid := {}
	_item_grid = grid
	for i in items.size():
		var it := items[i]
		var key := _cell_key(floori(it.x / ITEM_CELL), floori(it.y / ITEM_CELL))
		if grid.has(key):
			grid[key].append(i)
		else:
			grid[key] = [i]

	# Only awake items look for neighbours; two sleepers never need resolving.
	for i in items.size():
		var a := items[i]
		if a.sleeping:
			continue
		var cx := floori(a.x / ITEM_CELL)
		var cy := floori(a.y / ITEM_CELL)
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var list = grid.get(_cell_key(cx + ox, cy + oy))
				if list == null:
					continue
				for j in list:
					var b := items[j]
					if not b.sleeping and j <= i:
						continue
					# Cheap distance test first, so misses don't pay for a function call.
					var dx := b.x - a.x
					var dy := b.y - a.y
					var reach := a.radius + b.radius + WAKE_MARGIN
					if dx * dx + dy * dy >= reach * reach:
						continue
					if b.sleeping:
						_resolve_against_sleeper(a, b)
					else:
						_resolve_pair(a, b)


func _resolve_pair(a: Item, b: Item) -> void:
	var dx := b.x - a.x
	var dy := b.y - a.y
	var rsum := a.radius + b.radius
	var d2 := dx * dx + dy * dy
	if d2 >= rsum * rsum:
		return
	var nx := 0.0
	var ny := 1.0
	var dist := 0.0
	if d2 > 0.0:
		dist = sqrt(d2)
		nx = dx / dist
		ny = dy / dist

	var push := (rsum - dist) * 0.5
	a.x -= nx * push
	a.y -= ny * push
	b.x += nx * push
	b.y += ny * push

	# Friction lets a belt carry a small pile, not just the bottom layer, and lets piles heap.
	var tnx := -ny
	var tny := nx
	var slide := ((b.x - b.step_x) - (a.x - a.step_x)) * tnx + ((b.y - b.step_y) - (a.y - a.step_y)) * tny
	var f := slide * ITEM_FRICTION * 0.5
	a.x += tnx * f
	a.y += tny * f
	b.x -= tnx * f
	b.y -= tny * f


## A sleeper is a solid obstacle until something moving fast enough touches it.
func _resolve_against_sleeper(a: Item, s: Item) -> void:
	var dx := a.x - s.x
	var dy := a.y - s.y
	var rsum := a.radius + s.radius
	var d2 := dx * dx + dy * dy
	if d2 == 0.0:
		return
	var dist := sqrt(d2)
	var nx := dx / dist
	var ny := dy / dist
	if -(a.vx * nx + a.vy * ny) > WAKE_SPEED:
		_wake(s)
		_resolve_pair(s, a)
		return
	if dist >= rsum:
		return
	a.x += nx * (rsum - dist)
	a.y += ny * (rsum - dist)
	var tnx := -ny
	var tny := nx
	var slide := (a.x - a.step_x) * tnx + (a.y - a.step_y) * tny
	a.x -= tnx * slide * ITEM_FRICTION
	a.y -= tny * slide * ITEM_FRICTION


func _wake(it: Item) -> void:
	it.sleeping = false
	it.still_ticks = 0
	it.step_x = it.x
	it.step_y = it.y


func _update_sleep() -> void:
	for it in items:
		if it.sleeping:
			continue
		if it.belt_tick == tick:
			it.still_ticks = 0
			continue
		var mx := it.x - it.prev_x
		var my := it.y - it.prev_y
		if mx * mx + my * my < SLEEP_MOVE * SLEEP_MOVE:
			it.still_ticks += 1
			if it.still_ticks >= SLEEP_TICKS:
				it.sleeping = true
				it.vx = 0.0
				it.vy = 0.0
		else:
			it.still_ticks = 0


## Wakes sleepers whose support has moved away. Checks are spread across ticks
## (each sleeper is checked every SUPPORT_CHECK_TICKS) to keep the cost low.
func _check_support() -> void:
	for i in items.size():
		var it := items[i]
		if it.sleeping and (i + tick) % SUPPORT_CHECK_TICKS == 0 and not _is_supported(i):
			_wake(it)


func _is_supported(index: int) -> bool:
	var it := items[index]
	var list = _seg_grid.get(_cell_key(floori(it.x / SEG_CELL), floori(it.y / SEG_CELL)))
	if list != null:
		var reach := it.radius + SUPPORT_GAP
		for si in list:
			var s := segments[si]
			var t := clampf(((it.x - s.ax) * s.dx + (it.y - s.ay) * s.dy) / s.len_sq, 0.0, 1.0)
			var dx := s.ax + s.dx * t - it.x
			var dy := s.ay + s.dy * t - it.y
			var d2 := dx * dx + dy * dy
			if d2 < reach * reach and dy > SUPPORT_SLOPE * sqrt(d2):
				return true

	var cx := floori(it.x / ITEM_CELL)
	var cy := floori(it.y / ITEM_CELL)
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var cell = _item_grid.get(_cell_key(cx + ox, cy + oy))
			if cell == null:
				continue
			for j in cell:
				if j == index:
					continue
				var o := items[j]
				var dx := o.x - it.x
				var dy := o.y - it.y
				var reach := it.radius + o.radius + SUPPORT_GAP
				var d2 := dx * dx + dy * dy
				if d2 < reach * reach and dy > SUPPORT_SLOPE * sqrt(d2):
					return true
	return false


## Removes items that fell out of the world or landed in a bin, keeping the rest in order.
## Sleepers that were resting on a removed item are woken so they don't hang in mid-air.
func _collect() -> void:
	var kept: Array[Item] = []
	var removed: Array[Item] = []
	for it in items:
		if it.y > _kill_max_y or it.x < _kill_min_x or it.x > _kill_max_x:
			lost += 1
			removed.append(it)
			continue
		var caught := false
		for b in bins:
			if b.contains(it.x, it.y):
				b.caught += 1
				delivered[it.kind] = delivered.get(it.kind, 0) + 1
				caught = true
				break
		if caught:
			removed.append(it)
		else:
			kept.append(it)
	items = kept

	var reach := MAX_RADIUS * 2.0 + WAKE_MARGIN
	for r in removed:
		for it in items:
			if it.sleeping:
				var dx := it.x - r.x
				var dy := it.y - r.y
				if dx * dx + dy * dy < reach * reach:
					_wake(it)


static func _cell_key(cx: int, cy: int) -> int:
	return (cx + 4096) * 65536 + (cy + 4096)
