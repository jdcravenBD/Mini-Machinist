class_name Simulation
extends RefCounted
## Deterministic rigid-body physics for items: convex polygons that slide, tip, stack and
## settle, plus static segments, belts, spawners and bins.
##
## Position-based (XPBD style): each substep predicts where items go, finds contact points
## where outlines overlap, pushes them apart at those points (which also turns them), then
## derives velocity from how far they actually moved. Pushing at the real contact point is
## what makes a chunk resting on a corner tip over onto a flat side.
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
## Radians per second; also keeps a corner from swinging through a wall in one substep.
const MAX_SPIN := 30.0
const ANGULAR_DAMPING := 0.998
## Most an item may move in one substep, pushes included. Kept well below the thinnest
## item's half-width so nothing tunnels through a wall or squeezes past where solids meet.
const MAX_STEP := 2.5
## Friction coefficient between two items.
const ITEM_FRICTION := 0.6
const MAX_ITEMS := 600
## Largest item bounding radius; static segments are registered with this much margin.
const MAX_RADIUS := 9.0
const SEG_CELL := 32.0
## At least the largest item diameter, so touching items are always in neighbouring cells.
const ITEM_CELL := 18.0
## Solid tile kinds, for pushing out items that a heavy pile squeezed into a solid.
enum Solid { NONE, BOX, RAMP_DOWN_RIGHT, RAMP_DOWN_LEFT }
const INV_SQRT2 := 0.7071067811865476
## An item that stays within SLEEP_MOVE pixels and SLEEP_TURN radians of one pose for
## SLEEP_TICKS ticks goes to sleep. Measured over the whole stretch, not per tick, so a
## chunk rocking slightly on its resting spot still settles while a slow creep doesn't.
const SLEEP_MOVE := 0.5
const SLEEP_TURN := 0.03
const SLEEP_TICKS := 30
## An item hitting a sleeper faster than this wakes it. Gentle contact (an item settling
## onto a pile) doesn't, or every pile would keep re-waking itself.
const WAKE_SPEED := 60.0
## How close (pixels) something must be, and how upward its push (fraction of the contact
## direction), to count as holding an item up.
const SUPPORT_GAP := 1.0
const SUPPORT_SLOPE := 0.3
## Ticks a crusher takes to pull an item smaller than it crushes through unchanged.
const PASS_TICKS := 6
## Share of its grip a belt keeps on an item that's being held back, so a backed-up queue
## still presses forward (into a crusher, against a wall) without squashing together.
const BELT_PRESS := 0.15
## Starting rotations for spawned items, as exact unit vectors (cos, sin).
const SPAWN_ROTATIONS := [1.0, 0.0, 0.6, 0.8, -0.8, 0.6, 0.0, -1.0, 0.8, -0.6]


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
	## Items caught, by "kind size" (e.g. &"rock gravel").
	var by_kind := {}

	func _init(p_min_x: float, p_min_y: float, p_max_x: float, p_max_y: float) -> void:
		min_x = p_min_x
		min_y = p_min_y
		max_x = p_max_x
		max_y = p_max_y

	func contains(px: float, py: float) -> bool:
		return px > min_x and px < max_x and py > min_y and py < max_y


## Crushes one item at a time. An item that settles into its intake (the dip between its
## rollers) is pulled in. The size it `takes` is held for `duration` ticks while it's
## crushed, then comes out the bottom as `pieces` items of the next size down. Anything
## smaller is pulled straight through unchanged; anything bigger just sits there, clogging it.
class Crusher:
	var takes: StringName
	var makes: StringName
	var pieces: int
	var duration: int
	var min_x: float
	var min_y: float
	var max_x: float
	var max_y: float
	var exit_x: float
	var exit_y: float
	## The item being crushed (out of the physics while inside), and where it was caught.
	var held: Item = null
	var held_x := 0.0
	var held_y := 0.0
	## True if the held item is smaller than what it crushes and will come out unchanged.
	var passing := false
	var timer := 0

	func _init(p_takes: StringName, p_makes: StringName, p_pieces: int, p_duration: int) -> void:
		takes = p_takes
		makes = p_makes
		pieces = p_pieces
		duration = p_duration

	## 0 when it starts crushing (or passing an item through), 1 when done.
	func progress() -> float:
		return 1.0 - float(timer) / (PASS_TICKS if passing else duration)


## Contacts found this substep. Item A is always awake and is pushed along the normal;
## B is another item (index >= 0) or a static segment (-1 - segment index). Points are
## stored in each body's own frame (a segment's in world space) so they can be re-placed
## after earlier pushes in the same substep.
class Contacts:
	var a := PackedInt32Array()
	var b := PackedInt32Array()
	## Per contact: A-local x, y, B-local x, y, normal x, y.
	var f := PackedFloat64Array()
	## Contacts that actually pushed this substep, for the velocity pass.
	var touching := PackedInt32Array()

	func clear() -> void:
		a.clear()
		b.clear()
		f.clear()
		touching.clear()

	func size() -> int:
		return a.size()


var items: Array[Item] = []
var segments: Array[Segment] = []
var spawners: Array[Spawner] = []
var bins: Array[Bin] = []
var crushers: Array[Crusher] = []
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
var _item_contacts := Contacts.new()
var _wall_contacts := Contacts.new()
## Penetration depth found by the last _deepest_face call.
var _hit_depth := 0.0


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


## Collected until finish_build(), which merges and indexes them.
func add_segment(seg: Segment) -> void:
	segments.append(seg)


func add_spawner(x: float, y: float, interval: int) -> void:
	spawners.append(Spawner.new(x, y, interval))


func add_bin(min_x: float, min_y: float, max_x: float, max_y: float) -> void:
	bins.append(Bin.new(min_x, min_y, max_x, max_y))


## `intake` is where a waiting item gets pulled in; pieces come out at `exit`, falling.
func add_crusher(takes: StringName, makes: StringName, pieces: int, duration: int, intake: Rect2, exit_x: float, exit_y: float) -> Crusher:
	var crusher := Crusher.new(takes, makes, pieces, duration)
	crusher.min_x = intake.position.x
	crusher.min_y = intake.position.y
	crusher.max_x = intake.end.x
	crusher.max_y = intake.end.y
	crusher.exit_x = exit_x
	crusher.exit_y = exit_y
	crushers.append(crusher)
	return crusher


## Call once after adding all segments. Joins straight runs (a row of conveyors becomes one
## long belt) so items glide across seams instead of catching on the joints.
func finish_build() -> void:
	segments = _merge_runs(segments)
	_seg_grid.clear()
	for index in segments.size():
		var seg := segments[index]
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


func step() -> void:
	_run_spawners()
	_run_crushers()
	for it in items:
		it.prev_x = it.x
		it.prev_y = it.y
		it.prev_c = it.c
		it.prev_s = it.s
	for i in SUBSTEPS:
		_predict()
		_detect()
		# Items push each other first, then walls get the last word so nothing ends inside one.
		_solve(_item_contacts)
		_solve(_wall_contacts)
		_finish_substep()
		_settle_velocities(_item_contacts)
		_settle_velocities(_wall_contacts)
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
		data.append_array([it.x, it.y, it.c, it.s, it.vx, it.vy, it.w])
	return data


func _run_spawners() -> void:
	for sp in spawners:
		sp.timer -= 1
		if sp.timer > 0:
			continue
		sp.timer = sp.interval
		if items.size() >= MAX_ITEMS or _is_blocked(sp.x, sp.y):
			continue
		# Every third chunk is rock (the impurity). Shape, rotation and a small sideways
		# offset follow fixed patterns so piles look natural while staying repeatable.
		var kind := &"rock" if sp.count % 3 == 2 else &"iron_ore"
		var shape := sp.count % ItemDefs.SHAPES.size()
		var rot := (sp.count % (SPAWN_ROTATIONS.size() / 2)) * 2
		var jitter := float((sp.count * 7) % 5 - 2)
		var item := Item.new(kind, sp.x + jitter, sp.y, shape, SPAWN_ROTATIONS[rot], SPAWN_ROTATIONS[rot + 1])
		item.y += item.radius + 0.5
		item.prev_y = item.y
		item.update_world()
		items.append(item)
		sp.count += 1


func _run_crushers() -> void:
	for cr in crushers:
		if cr.held == null:
			var takes := ItemDefs.size_rank(cr.takes)
			for it in items:
				var rank := ItemDefs.size_rank(it.size)
				if rank >= takes and it.x > cr.min_x and it.x < cr.max_x and it.y > cr.min_y and it.y < cr.max_y:
					cr.held = it
					cr.held_x = it.x
					cr.held_y = it.y
					cr.passing = rank > takes
					cr.timer = PASS_TICKS if cr.passing else cr.duration
					items.erase(it)
					_wake_near(it.x, it.y)
					break
		elif cr.timer > 0:
			cr.timer -= 1
		else:
			var out_size := cr.held.size if cr.passing else cr.makes
			var piece_size := ItemDefs.size_of(cr.held.kind, out_size)
			if not _is_blocked_near(cr.exit_x, cr.exit_y + piece_size * 2.0, piece_size * 3.0):
				_release_pieces(cr)


## The crushed item comes out as several smaller pieces in a fixed little spread (or, if it
## was only passing through, as itself).
func _release_pieces(cr: Crusher) -> void:
	var held := cr.held
	if cr.passing:
		var out := Item.new(held.kind, cr.exit_x, cr.exit_y + held.radius + 0.5, held.shape, held.c, held.s, held.size)
		out.vy = 40.0
		items.append(out)
		cr.held = null
		return
	var piece_size := ItemDefs.size_of(held.kind, cr.makes)
	var rotations := SPAWN_ROTATIONS.size() / 2
	for k in cr.pieces:
		var side := k - (cr.pieces - 1) * 0.5
		var rot := ((held.shape + k) % rotations) * 2
		var piece := Item.new(held.kind, cr.exit_x + side * piece_size * 1.3, cr.exit_y + piece_size * (1.2 + (k % 2)),
				(held.shape + k + 1) % ItemDefs.SHAPES.size(), SPAWN_ROTATIONS[rot], SPAWN_ROTATIONS[rot + 1], cr.makes)
		piece.vx = side * 15.0
		piece.vy = 40.0
		items.append(piece)
	cr.held = null


## True if any item's center is within `reach` of (x, y).
func _is_blocked_near(x: float, y: float, reach: float) -> bool:
	for it in items:
		var dx := it.x - x
		var dy := it.y - y
		if dx * dx + dy * dy < reach * reach:
			return true
	return false


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
		it.step_c = it.c
		it.step_s = it.s
		it.push_right = 0.0
		it.push_left = 0.0
		it.push_down = 0.0
		it.push_up = 0.0
		it.vy += GRAVITY * H
		var speed_sq := it.vx * it.vx + it.vy * it.vy
		if speed_sq > MAX_SPEED * MAX_SPEED:
			var k := MAX_SPEED / sqrt(speed_sq)
			it.vx *= k
			it.vy *= k
		it.w = clampf(it.w * ANGULAR_DAMPING, -MAX_SPIN, MAX_SPIN)
		it.x += it.vx * H
		it.y += it.vy * H
		it.turn(it.w * H)
		it.update_world()


## Caps movement, rescues anything squeezed into a solid, and derives velocity from
## whatever movement survived the pushes.
func _finish_substep() -> void:
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
		_push_out_of_solid(it)
		it.vx = (it.x - it.step_x) / H
		it.vy = (it.y - it.step_y) / H
		# sin of the angle turned this substep, which is the angle itself at these sizes.
		it.w = (it.step_c * it.s - it.step_s * it.c) / H


# --- Contact detection -------------------------------------------------------------

func _detect() -> void:
	_item_contacts.clear()
	_wall_contacts.clear()
	var grid := {}
	_item_grid = grid
	for i in items.size():
		var it := items[i]
		var key := _cell_key(floori(it.x / ITEM_CELL), floori(it.y / ITEM_CELL))
		if grid.has(key):
			grid[key].append(i)
		else:
			grid[key] = [i]

	# Only awake items look for contacts; two sleepers never need resolving.
	for i in items.size():
		var a := items[i]
		if a.sleeping:
			continue
		var walls = _seg_grid.get(_cell_key(floori(a.x / SEG_CELL), floori(a.y / SEG_CELL)))
		if walls != null:
			for si in walls:
				_detect_wall(i, a, si)

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
					var dx := b.x - a.x
					var dy := b.y - a.y
					var reach := a.radius + b.radius + SUPPORT_GAP
					if dx * dx + dy * dy < reach * reach:
						if b.sleeping:
							b.near_tick = tick
						_detect_pair(i, a, j, b)


## Contacts where a corner of one item pokes into the other.
func _detect_pair(ia: int, a: Item, ib: int, b: Item) -> void:
	var first := _item_contacts.size()
	# A corner outside the other item's bounding circle can't be inside it; skipping those
	# saves most of the work.
	var rb := b.radius * b.radius
	var ra := a.radius * a.radius
	for k in a.count:
		var px := a.world[k * 2]
		var py := a.world[k * 2 + 1]
		if (px - b.x) * (px - b.x) + (py - b.y) * (py - b.y) >= rb:
			continue
		var face := _deepest_face(px, py, b, 0.0)
		if face >= 0:
			var nx := b.world_normals[face * 2]
			var ny := b.world_normals[face * 2 + 1]
			_add_contact(_item_contacts, ia, a, ib, b, px, py, px + nx * _hit_depth, py + ny * _hit_depth, nx, ny)
	for k in b.count:
		var px := b.world[k * 2]
		var py := b.world[k * 2 + 1]
		if (px - a.x) * (px - a.x) + (py - a.y) * (py - a.y) >= ra:
			continue
		var face := _deepest_face(px, py, a, 0.0)
		if face >= 0:
			var nx := a.world_normals[face * 2]
			var ny := a.world_normals[face * 2 + 1]
			_add_contact(_item_contacts, ia, a, ib, b, px + nx * _hit_depth, py + ny * _hit_depth, px, py, -nx, -ny)

	if b.sleeping:
		# Wake a sleeper on a real impact, or when it sits on something being carried.
		var carried := _is_carried(a)
		for k in range(first, _item_contacts.size()):
			var nx := _item_contacts.f[k * 6 + 4]
			var ny := _item_contacts.f[k * 6 + 5]
			if -(a.vx * nx + a.vy * ny) > WAKE_SPEED or (carried and ny > SUPPORT_SLOPE):
				_wake(b)
				break


## Contacts between an item and a static line: item corners past the line, and line ends
## poking into the item. The line pushes toward whichever side the item's center is on.
func _detect_wall(ia: int, a: Item, si: int) -> void:
	var sg := segments[si]
	if sg.passes == a.kind:
		return
	var along := (a.x - sg.ax) * sg.tx + (a.y - sg.ay) * sg.ty
	if along < -a.radius or along * along > (sqrt(sg.len_sq) + a.radius) ** 2:
		return
	# Push back toward the side the center was on at the start of the substep, so a small
	# fast item that got all the way across a thin wall still goes back where it came from.
	var side := (a.x - sg.ax) * sg.nx + (a.y - sg.ay) * sg.ny
	var was := (a.step_x - sg.ax) * sg.nx + (a.step_y - sg.ay) * sg.ny
	if absf(side) >= a.radius and (side >= 0.0) == (was >= 0.0):
		return
	var nx := sg.nx if was >= 0.0 else -sg.nx
	var ny := sg.ny if was >= 0.0 else -sg.ny
	for k in a.count:
		var px := a.world[k * 2]
		var py := a.world[k * 2 + 1]
		var u := ((px - sg.ax) * sg.dx + (py - sg.ay) * sg.dy) / sg.len_sq
		if u < 0.0 or u > 1.0:
			continue
		var d := (px - sg.ax) * nx + (py - sg.ay) * ny
		if d < 0.0:
			_add_contact(_wall_contacts, ia, a, -1 - si, null, px, py, px - nx * d, py - ny * d, nx, ny)
	for e in 2:
		var ex := sg.ax if e == 0 else sg.bx
		var ey := sg.ay if e == 0 else sg.by
		if (ex - a.x) ** 2 + (ey - a.y) ** 2 >= a.radius * a.radius:
			continue
		var face := _deepest_face(ex, ey, a, 0.0)
		if face >= 0:
			var fx := a.world_normals[face * 2]
			var fy := a.world_normals[face * 2 + 1]
			_add_contact(_wall_contacts, ia, a, -1 - si, null, ex + fx * _hit_depth, ey + fy * _hit_depth, ex, ey, -fx, -fy)


## Index of the face of `b` that point (px, py) is least deep behind, or -1 if the point
## is more than `margin` outside. Sets _hit_depth to how deep it is (negative if outside).
func _deepest_face(px: float, py: float, b: Item, margin: float) -> int:
	var best := -INF
	var best_face := -1
	for f in b.count:
		var d := (px - b.world[f * 2]) * b.world_normals[f * 2] + (py - b.world[f * 2 + 1]) * b.world_normals[f * 2 + 1]
		if d > margin:
			return -1
		if d > best:
			best = d
			best_face = f
	_hit_depth = -best
	return best_face


func _add_contact(list: Contacts, ia: int, a: Item, ib: int, b: Item, pax: float, pay: float, pbx: float, pby: float, nx: float, ny: float) -> void:
	list.a.append(ia)
	list.b.append(ib)
	var dx := pax - a.x
	var dy := pay - a.y
	list.f.append(a.c * dx + a.s * dy)
	list.f.append(-a.s * dx + a.c * dy)
	if b == null:
		list.f.append(pbx)
		list.f.append(pby)
	else:
		dx = pbx - b.x
		dy = pby - b.y
		list.f.append(b.c * dx + b.s * dy)
		list.f.append(-b.s * dx + b.c * dy)
	list.f.append(nx)
	list.f.append(ny)


# --- Contact solving ---------------------------------------------------------------

func _solve(list: Contacts) -> void:
	for k in list.size():
		var a := items[list.a[k]]
		var ib := list.b[k]
		var o := k * 6
		var lax := list.f[o]
		var lay := list.f[o + 1]
		var lbx := list.f[o + 2]
		var lby := list.f[o + 3]
		var nx := list.f[o + 4]
		var ny := list.f[o + 5]

		var b: Item = null
		var seg: Segment = null
		var pbx := lbx
		var pby := lby
		if ib < 0:
			seg = segments[-1 - ib]
		else:
			b = items[ib]
			pbx = b.x + b.c * lbx - b.s * lby
			pby = b.y + b.s * lbx + b.c * lby
		var pax := a.x + a.c * lax - a.s * lay
		var pay := a.y + a.s * lax + a.c * lay
		var depth := (pbx - pax) * nx + (pby - pay) * ny
		if depth <= 0.0:
			continue
		list.touching.append(k)

		# Push apart at the contact point. Off-center pushes also turn the item, which is
		# what tips a chunk off its corner.
		var b_moves := b != null and not b.sleeping
		var rax := pax - a.x
		var ray := pay - a.y
		var cra := rax * ny - ray * nx
		var weight := a.inv_mass + a.inv_inertia * cra * cra
		var rbx := 0.0
		var rby := 0.0
		if b_moves:
			rbx = pbx - b.x
			rby = pby - b.y
			var crb := rbx * ny - rby * nx
			weight += b.inv_mass + b.inv_inertia * crb * crb
		var lam := depth / weight
		_move(a, nx * lam, ny * lam, rax, ray)
		if b_moves:
			_move(b, -nx * lam, -ny * lam, rbx, rby)

		# Whatever rests on a carried item is carried too (ny < 0: A is pushed up, so on top).
		if seg != null:
			if seg.surface_speed != 0.0:
				a.carried_tick = tick
		elif ny < -SUPPORT_SLOPE and _is_carried(b):
			a.carried_tick = tick
		elif ny > SUPPORT_SLOPE and b_moves and _is_carried(a):
			b.carried_tick = tick

		_apply_friction(a, b if b_moves else null, seg, lax, lay, lbx, lby, nx, ny, lam)


## Removes motion along the normal at every contact that pushed this substep. Pushing
## overlapping items apart turns into speed in this kind of solver; without this pass a
## chunk landing on a corner would spring off and spin far more than a real rock does.
func _settle_velocities(list: Contacts) -> void:
	for k in list.touching:
		var a := items[list.a[k]]
		var ib := list.b[k]
		var o := k * 6
		var lax := list.f[o]
		var lay := list.f[o + 1]
		var nx := list.f[o + 4]
		var ny := list.f[o + 5]
		var rax := a.c * lax - a.s * lay
		var ray := a.s * lax + a.c * lay
		var vn := (a.vx - a.w * ray) * nx + (a.vy + a.w * rax) * ny
		var cra := rax * ny - ray * nx
		var weight := a.inv_mass + a.inv_inertia * cra * cra
		var b: Item = null
		var rbx := 0.0
		var rby := 0.0
		var crb := 0.0
		if ib >= 0 and not items[ib].sleeping:
			b = items[ib]
			var lbx := list.f[o + 2]
			var lby := list.f[o + 3]
			rbx = b.c * lbx - b.s * lby
			rby = b.s * lbx + b.c * lby
			vn -= (b.vx - b.w * rby) * nx + (b.vy + b.w * rbx) * ny
			crb = rbx * ny - rby * nx
			weight += b.inv_mass + b.inv_inertia * crb * crb
		var j := -vn / weight
		a.vx += nx * j * a.inv_mass
		a.vy += ny * j * a.inv_mass
		a.w += cra * j * a.inv_inertia
		if b != null:
			b.vx -= nx * j * b.inv_mass
			b.vy -= ny * j * b.inv_mass
			b.w -= crb * j * b.inv_inertia


## Moves an item by impulse (px, py) applied at offset (rx, ry) from its center.
func _move(it: Item, px: float, py: float, rx: float, ry: float) -> void:
	var mx := px * it.inv_mass
	var my := py * it.inv_mass
	it.x += mx
	it.y += my
	_add_push(it, mx, my)
	it.turn(it.inv_inertia * (rx * py - ry * px))


## Static friction: cancels sliding at the contact this substep, up to what the contact's
## push allows (Coulomb). On a belt the "not sliding" target is the belt's own movement.
func _apply_friction(a: Item, b: Item, seg: Segment, lax: float, lay: float, lbx: float, lby: float, nx: float, ny: float, lam: float) -> void:
	var pax := a.x + a.c * lax - a.s * lay
	var pay := a.y + a.s * lax + a.c * lay
	var mx := pax - (a.step_x + a.step_c * lax - a.step_s * lay)
	var my := pay - (a.step_y + a.step_s * lax + a.step_c * lay)
	var mu := ITEM_FRICTION
	var rbx := 0.0
	var rby := 0.0
	if seg != null:
		mu = seg.friction
		mx -= seg.tx * seg.surface_speed * H
		my -= seg.ty * seg.surface_speed * H
	elif b != null:
		var pbx := b.x + b.c * lbx - b.s * lby
		var pby := b.y + b.s * lbx + b.c * lby
		rbx = pbx - b.x
		rby = pby - b.y
		mx -= pbx - (b.step_x + b.step_c * lbx - b.step_s * lby)
		my -= pby - (b.step_y + b.step_s * lbx + b.step_c * lby)

	var mn := mx * nx + my * ny
	var tx := mx - nx * mn
	var ty := my - ny * mn
	var slide := sqrt(tx * tx + ty * ty)
	if slide < 1e-9:
		return
	tx /= slide
	ty /= slide

	var rax := pax - a.x
	var ray := pay - a.y
	var cra := rax * ty - ray * tx
	var weight := a.inv_mass + a.inv_inertia * cra * cra
	if b != null:
		var crb := rbx * ty - rby * tx
		weight += b.inv_mass + b.inv_inertia * crb * crb
	var lam_t := minf(slide / weight, mu * lam)

	if seg != null and seg.surface_speed != 0.0:
		# A belt mostly slips under an item that something is holding back (a wall, the item
		# ahead in a queue), keeping only BELT_PRESS of its grip. Full grip would squash a
		# long queue together; none would leave a backed-up queue limp.
		var held := (a.push_left if -tx > 0.0 else a.push_right) * absf(tx)
		held += (a.push_up if -ty > 0.0 else a.push_down) * absf(ty)
		lam_t = maxf(lam_t * BELT_PRESS, lam_t - held / a.inv_mass)

	_move(a, -tx * lam_t, -ty * lam_t, rax, ray)
	if b != null:
		_move(b, tx * lam_t, ty * lam_t, rbx, rby)


func _add_push(it: Item, dx: float, dy: float) -> void:
	if dx > 0.0:
		it.push_right += dx
	else:
		it.push_left -= dx
	if dy > 0.0:
		it.push_down += dy
	else:
		it.push_up -= dy


# --- Solids --------------------------------------------------------------------------

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


# --- Sleeping ------------------------------------------------------------------------

## Carried this tick or the one before (substeps of a new tick haven't re-marked it yet).
func _is_carried(it: Item) -> bool:
	return it.carried_tick >= tick - 1


func _wake(it: Item) -> void:
	it.sleeping = false
	it.still_ticks = 0
	it.step_x = it.x
	it.step_y = it.y
	it.step_c = it.c
	it.step_s = it.s


func _update_sleep() -> void:
	for it in items:
		if it.sleeping:
			continue
		if _is_carried(it):
			it.still_ticks = 0
			continue
		if it.vx * it.vx + it.vy * it.vy > WAKE_SPEED * WAKE_SPEED:
			it.still_ticks = 0
			continue
		var mx := it.x - it.still_x
		var my := it.y - it.still_y
		var turned := absf(it.still_c * it.s - it.still_s * it.c)
		if it.still_ticks > 0 and mx * mx + my * my < SLEEP_MOVE * SLEEP_MOVE and turned < SLEEP_TURN:
			it.still_ticks += 1
			if it.still_ticks >= SLEEP_TICKS:
				it.sleeping = true
				it.vx = 0.0
				it.vy = 0.0
				it.w = 0.0
				it.update_world()
		else:
			# Start a new stretch from here.
			it.still_ticks = 1
			it.still_x = it.x
			it.still_y = it.y
			it.still_c = it.c
			it.still_s = it.s


## Wakes sleepers whose support has moved away. A sleeper's support can only go if
## something next to it moves (removed items are handled in _collect), so only sleepers
## a moving item came near this tick are checked.
func _check_support() -> void:
	for i in items.size():
		var it := items[i]
		if it.sleeping and it.near_tick == tick and not _is_supported(i):
			_wake(it)


## True if a wall or another item touches this one in a way that pushes it upward.
func _is_supported(index: int) -> bool:
	var it := items[index]
	var walls = _seg_grid.get(_cell_key(floori(it.x / SEG_CELL), floori(it.y / SEG_CELL)))
	if walls != null:
		for si in walls:
			var sg := segments[si]
			if sg.passes == it.kind:
				continue
			var side := (it.x - sg.ax) * sg.nx + (it.y - sg.ay) * sg.ny
			if absf(side) >= it.radius + SUPPORT_GAP:
				continue
			var nx := sg.nx if side >= 0.0 else -sg.nx
			var ny := sg.ny if side >= 0.0 else -sg.ny
			if ny < -SUPPORT_SLOPE:
				for k in it.count:
					var px := it.world[k * 2]
					var py := it.world[k * 2 + 1]
					var u := ((px - sg.ax) * sg.dx + (py - sg.ay) * sg.dy) / sg.len_sq
					if u >= 0.0 and u <= 1.0 and (px - sg.ax) * nx + (py - sg.ay) * ny <= SUPPORT_GAP:
						return true
			for e in 2:
				var face := _deepest_face(sg.ax if e == 0 else sg.bx, sg.ay if e == 0 else sg.by, it, SUPPORT_GAP)
				if face >= 0 and it.world_normals[face * 2 + 1] > SUPPORT_SLOPE:
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
				if dx * dx + dy * dy >= reach * reach:
					continue
				for k in it.count:
					var face := _deepest_face(it.world[k * 2], it.world[k * 2 + 1], o, SUPPORT_GAP)
					if face >= 0 and o.world_normals[face * 2 + 1] < -SUPPORT_SLOPE:
						return true
				for k in o.count:
					var face := _deepest_face(o.world[k * 2], o.world[k * 2 + 1], it, SUPPORT_GAP)
					if face >= 0 and it.world_normals[face * 2 + 1] > SUPPORT_SLOPE:
						return true
	return false


# --- Bookkeeping ---------------------------------------------------------------------

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
				var key := StringName("%s %s" % [it.kind, it.size])
				b.by_kind[key] = b.by_kind.get(key, 0) + 1
				delivered[it.kind] = delivered.get(it.kind, 0) + 1
				caught = true
				break
		if caught:
			removed.append(it)
		else:
			kept.append(it)
	items = kept

	for r in removed:
		_wake_near(r.x, r.y)


## Wakes sleepers that could have been resting on something at (x, y) that just left.
func _wake_near(x: float, y: float) -> void:
	var reach := MAX_RADIUS * 2.0 + SUPPORT_GAP
	for it in items:
		if it.sleeping:
			var dx := it.x - x
			var dy := it.y - y
			if dx * dx + dy * dy < reach * reach:
				_wake(it)


## Joins touching horizontal or vertical segments that lie on the same line and behave the
## same (speed, friction, what passes through). Slanted ones are left alone. Output order is fixed by sorting.
static func _merge_runs(input: Array[Segment]) -> Array[Segment]:
	var straight: Array[Segment] = []
	var result: Array[Segment] = []
	for sg in input:
		# Point each straight segment toward +x or +y (flipping a belt flips its speed too).
		if (sg.ay == sg.by and sg.ax > sg.bx) or (sg.ax == sg.bx and sg.ay > sg.by):
			sg = Segment.new(sg.bx, sg.by, sg.ax, sg.ay, -sg.surface_speed, sg.friction, sg.passes)
		if sg.ay == sg.by or sg.ax == sg.bx:
			straight.append(sg)
		else:
			result.append(sg)

	straight.sort_custom(func(p: Segment, q: Segment) -> bool:
		var p_flat := p.ay == p.by
		var q_flat := q.ay == q.by
		if p_flat != q_flat:
			return p_flat
		var p_line := p.ay if p_flat else p.ax
		var q_line := q.ay if q_flat else q.ax
		if p_line != q_line:
			return p_line < q_line
		if p.surface_speed != q.surface_speed:
			return p.surface_speed < q.surface_speed
		if p.friction != q.friction:
			return p.friction < q.friction
		var p_start := p.ax if p_flat else p.ay
		var q_start := q.ax if q_flat else q.ay
		if p_start != q_start:
			return p_start < q_start
		return (p.bx if p_flat else p.by) < (q.bx if q_flat else q.by))

	var run: Segment = null
	for sg in straight:
		if run != null and _continues(run, sg):
			if sg.ay == sg.by:
				if sg.bx > run.bx:
					run = Segment.new(run.ax, run.ay, sg.bx, sg.by, run.surface_speed, run.friction, run.passes)
			elif sg.by > run.by:
				run = Segment.new(run.ax, run.ay, sg.bx, sg.by, run.surface_speed, run.friction, run.passes)
			continue
		if run != null:
			result.append(run)
		run = sg
	if run != null:
		result.append(run)
	return result


## True if `next` lies on the same line as `run`, behaves the same, and starts where `run`
## ends (or before).
static func _continues(run: Segment, next: Segment) -> bool:
	if run.surface_speed != next.surface_speed or run.friction != next.friction or run.passes != next.passes:
		return false
	if run.ay == run.by:
		return next.ay == next.by and next.ay == run.ay and next.ax <= run.bx
	return next.ax == next.bx and next.ax == run.ax and run.ax == run.bx and next.ay <= run.by


static func _cell_key(cx: int, cy: int) -> int:
	return (cx + 4096) * 65536 + (cy + 4096)
