class_name WorldView
extends Node2D
## Draws the grid, parts, items and the placement preview.
##
## Everything here is placeholder shapes at final sizes. When real art arrives, each
## part's _draw_* function is the single place to swap in a sprite.

const T := PartDefs.TILE
const BACKGROUND := Color(0.16, 0.155, 0.15)
const GRID_LINE := Color(1, 1, 1, 0.05)
const BORDER := Color(1, 1, 1, 0.18)
const OUTLINE := Color(0, 0, 0, 0.35)
const BELT := Color(0.15, 0.15, 0.16)
const BELT_MARK := Color(0.80, 0.68, 0.30)
const ITEM_OUTLINE := Color(0, 0, 0, 0.45)
const ROLLER := Color(0.24, 0.24, 0.25)
const ROLLER_TOOTH := Color(0.55, 0.55, 0.57)

var machine: Machine
var sim: Simulation
## Placement preview, or null when there's nothing to preview.
var ghost: Part = null
var ghost_valid := true
## [kind, size, shape] -> drawing polygons ("body", "fleck", "outline") sized for that kind.
var _item_polys := {}


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var size := Vector2(Machine.WIDTH * T, Machine.HEIGHT * T)
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	if sim == null:
		_draw_grid(size)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER, false, 2.0)

	if machine:
		for p in machine.parts:
			_draw_part(p, Color.WHITE)

	if sim:
		for it in sim.items:
			_draw_item(it)
		for cr in sim.crushers:
			if cr.held != null:
				_draw_crushing(cr)
		draw_set_transform_matrix(Transform2D.IDENTITY)
	elif ghost != null:
		var tint := Color(1, 1, 1, 0.55) if ghost_valid else Color(1, 0.35, 0.35, 0.55)
		_draw_part(ghost, tint)


## The item's real collision outline, with a lighter fleck so you can see it turn.
func _draw_item(it: Item) -> void:
	var key := [it.kind, it.size, it.shape]
	if not _item_polys.has(key):
		_item_polys[key] = _build_item_polys(it)
	var polys: Dictionary = _item_polys[key]
	var def: Dictionary = ItemDefs.DEFS[it.kind]
	draw_set_transform_matrix(Transform2D(Vector2(it.c, it.s), Vector2(-it.s, it.c), Vector2(it.x, it.y)))
	draw_colored_polygon(polys["body"], def["color"])
	draw_colored_polygon(polys["fleck"], def["fleck"])
	draw_polyline(polys["outline"], ITEM_OUTLINE, 1.0, true)


## The item being crushed sinks into the gap, shrinking and shaking, until its pieces
## drop out the bottom as real items.
func _draw_crushing(cr: Simulation.Crusher) -> void:
	var t := cr.progress()
	var it := cr.held
	var key := [it.kind, it.size, it.shape]
	if not _item_polys.has(key):
		_item_polys[key] = _build_item_polys(it)
	var gap_y := cr.max_y
	var pos := Vector2(lerpf(cr.held_x, cr.exit_x, t), lerpf(cr.held_y, gap_y, t))
	pos += Vector2(sin(sim.tick * 2.3), cos(sim.tick * 1.7)) * 0.8
	var scale := 1.0 if cr.passing else lerpf(1.0, 0.45, t)
	var def: Dictionary = ItemDefs.DEFS[it.kind]
	draw_set_transform_matrix(Transform2D(Vector2(it.c, it.s) * scale, Vector2(-it.s, it.c) * scale, pos))
	draw_colored_polygon(_item_polys[key]["body"], def["color"])
	draw_polyline(_item_polys[key]["outline"], ITEM_OUTLINE, 1.0, true)


func _build_item_polys(it: Item) -> Dictionary:
	var body := PackedVector2Array()
	for i in it.count:
		body.append(Vector2(it.local[i * 2], it.local[i * 2 + 1]))
	var outline := body.duplicate()
	outline.append(body[0])
	# Fleck: a small facet between the first two corners, pulled toward the center.
	var fleck := PackedVector2Array([body[0] * 0.75, body[1] * 0.75, (body[0] + body[1]) * 0.2])
	return {"body": body, "fleck": fleck, "outline": outline}


func _draw_grid(size: Vector2) -> void:
	for x in range(1, Machine.WIDTH):
		draw_line(Vector2(x * T, 0), Vector2(x * T, size.y), GRID_LINE)
	for y in range(1, Machine.HEIGHT):
		draw_line(Vector2(0, y * T), Vector2(size.x, y * T), GRID_LINE)


func _draw_part(p: Part, tint: Color) -> void:
	var def: Dictionary = PartDefs.DEFS[p.type]
	var rect := Rect2(Vector2(p.cell * T), Vector2(def["size"] * T))
	var color: Color = def["color"] * tint
	var flipped := p.variant == 1
	match p.type:
		&"block":
			_draw_box(rect, color, tint)
		&"spawner":
			_draw_box(rect, color, tint)
			# Output slot at the bottom.
			var slot := Rect2(rect.position + Vector2(10, T - 6), Vector2(12, 6))
			draw_rect(slot, BELT * tint)
			draw_colored_polygon(PackedVector2Array([
				rect.position + Vector2(10, 9), rect.position + Vector2(22, 9), rect.position + Vector2(16, 18),
			]), BELT_MARK * tint)
		&"conveyor":
			_draw_conveyor(rect, color, flipped, tint)
		&"sorter":
			_draw_sorter(rect, color, flipped, p.filter, tint)
		&"large_crusher":
			var r := PartGeometry.LARGE_ROLLER
			_draw_roller(rect.position + Vector2(T * 0.5, T * 0.5), r, 1.0, tint)
			_draw_roller(rect.position + Vector2(T * 1.5, T * 0.5), r, -1.0, tint)
		&"small_crusher":
			var r := PartGeometry.SMALL_ROLLER
			for row in 2:
				var cy := T * (0.25 + row * 0.5)
				_draw_roller(rect.position + Vector2(T * 0.25, cy), r, 1.0, tint)
				_draw_roller(rect.position + Vector2(T * 0.75, cy), r, -1.0, tint)
		&"panel":
			var slab := PartGeometry.panel_rect(p)
			draw_rect(slab, color)
			draw_rect(slab, OUTLINE * tint, false, 1.0)
		&"ramp":
			var pts := PackedVector2Array([rect.position, rect.position + Vector2(0, T), rect.end])
			if flipped:
				pts = PackedVector2Array([rect.position + Vector2(T, 0), rect.end, rect.position + Vector2(0, T)])
			draw_colored_polygon(pts, color)
			pts.append(pts[0])
			draw_polyline(pts, OUTLINE * tint, 2.0)
		&"hopper":
			var mid := rect.position.x + rect.size.x * 0.5
			var gap := PartGeometry.HOPPER_GAP * 0.5
			var wall := 5.0
			draw_colored_polygon(PackedVector2Array([
				rect.position, rect.position + Vector2(wall, 0),
				Vector2(mid - gap, rect.end.y), Vector2(mid - gap - wall, rect.end.y),
			]), color)
			draw_colored_polygon(PackedVector2Array([
				Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x - wall, rect.position.y),
				Vector2(mid + gap, rect.end.y), Vector2(mid + gap + wall, rect.end.y),
			]), color)
		&"bin":
			var inset := PartGeometry.BIN_INSET
			var l := rect.position.x + inset
			var r := rect.end.x - inset
			draw_rect(Rect2(Vector2(l, rect.position.y + 6), Vector2(r - l, rect.size.y - 6)), color * Color(1, 1, 1, 0.35))
			draw_polyline(PackedVector2Array([
				Vector2(l, rect.position.y), Vector2(l, rect.end.y), Vector2(r, rect.end.y), Vector2(r, rect.position.y),
			]), color, 4.0)


## A toothed roller, turning clockwise for `direction` 1 and counterclockwise for -1.
func _draw_roller(center: Vector2, radius: float, direction: float, tint: Color) -> void:
	var turn := 0.0
	if sim:
		turn = sim.tick / float(Simulation.TICK_RATE) * PartGeometry.ROLLER_SPEED / radius * direction
	var teeth := 12 if radius > 10.0 else 8
	var tooth := radius * 0.22
	var body := PackedVector2Array()
	for i in teeth * 2:
		var a := turn + TAU * i / (teeth * 2)
		body.append(center + Vector2.from_angle(a) * (radius if i % 2 == 0 else radius - tooth))
	draw_colored_polygon(body, ROLLER_TOOTH * tint)
	draw_circle(center, radius - tooth, ROLLER * tint)
	draw_circle(center, radius * 0.25, ROLLER_TOOTH * tint)


func _draw_box(rect: Rect2, color: Color, tint: Color) -> void:
	draw_rect(rect, color)
	draw_rect(rect.grow(-1.0), OUTLINE * tint, false, 2.0)


func _draw_conveyor(rect: Rect2, color: Color, flipped: bool, tint: Color) -> void:
	draw_rect(rect, color)
	_draw_belt(rect, flipped, tint)
	var dir := -1.0 if flipped else 1.0
	# Rollers and a direction arrow on the housing.
	draw_circle(rect.position + Vector2(8, 22), 4.0, BELT * tint)
	draw_circle(rect.position + Vector2(24, 22), 4.0, BELT * tint)
	var c := rect.position + Vector2(16, 22)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-3 * dir, -4), c + Vector2(3 * dir, 0), c + Vector2(-3 * dir, 4),
	]), BELT_MARK * tint)
	draw_rect(rect.grow(-1.0), OUTLINE * tint, false, 2.0)


## Belt band along the top, with marks that scroll in the travel direction while running.
func _draw_belt(rect: Rect2, flipped: bool, tint: Color) -> void:
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 8)), BELT * tint)
	var dir := -1.0 if flipped else 1.0
	var offset := 0.0
	if sim:
		offset = fposmod(sim.tick * PartGeometry.BELT_SPEED / Simulation.TICK_RATE * dir, 16.0)
	for i in range(-1, 2):
		var mx := rect.position.x + offset + i * 16.0 + 4.0
		if mx >= rect.position.x and mx + 4.0 <= rect.end.x:
			draw_rect(Rect2(Vector2(mx, rect.position.y + 3), Vector2(4, 2)), BELT_MARK * tint)


## A belt with a grate over an open chute, showing the item it drops.
func _draw_sorter(rect: Rect2, color: Color, flipped: bool, filter: StringName, tint: Color) -> void:
	var post := 5.0
	draw_rect(Rect2(rect.position + Vector2(0, 8), Vector2(rect.size.x, rect.size.y - 8)), BELT * Color(1, 1, 1, 0.5) * tint)
	draw_rect(Rect2(rect.position, Vector2(post, rect.size.y)), color)
	draw_rect(Rect2(Vector2(rect.end.x - post, rect.position.y), Vector2(post, rect.size.y)), color)
	_draw_belt(rect, flipped, tint)
	# Grate slots across the belt.
	for i in 4:
		draw_rect(Rect2(rect.position + Vector2(5 + i * 6, 1), Vector2(3, 6)), Color(0, 0, 0, 0.55) * tint)
	# What it drops, with an arrow pointing down through the chute.
	if ItemDefs.DEFS.has(filter):
		var icon := PackedVector2Array()
		var outline := ItemDefs.outline(filter, &"chunk", 0)
		var center := rect.position + Vector2(16, 17)
		for i in outline.size() / 2:
			icon.append(center + Vector2(outline[i * 2], outline[i * 2 + 1]) * 0.8)
		draw_colored_polygon(icon, ItemDefs.DEFS[filter]["color"] * tint)
		var arrow := rect.position + Vector2(16, 26)
		draw_colored_polygon(PackedVector2Array([
			arrow + Vector2(-4, -2), arrow + Vector2(4, -2), arrow + Vector2(0, 3),
		]), BELT_MARK * tint)
