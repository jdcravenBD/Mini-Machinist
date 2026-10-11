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
## Drawn outlines stick out a little past the collision circle so piles look packed.
const ITEM_DRAW_SCALE := 1.1

var machine: Machine
var sim: Simulation
## Placement preview; ghost_type is empty when there's nothing to preview.
var ghost_type: StringName = &""
var ghost_cell := Vector2i.ZERO
var ghost_flipped := false
var ghost_valid := true
## [kind, shape] -> drawing polygons ("body", "fleck", "outline") sized for that kind.
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
			_draw_part(p.type, p.cell, p.flipped, Color.WHITE)

	if sim:
		for it in sim.items:
			_draw_item(it)
		draw_set_transform_matrix(Transform2D.IDENTITY)
	elif ghost_type != &"":
		var tint := Color(1, 1, 1, 0.55) if ghost_valid else Color(1, 0.35, 0.35, 0.55)
		_draw_part(ghost_type, ghost_cell, ghost_flipped, tint)


## A lumpy chunk with a lighter fleck, so you can see it tumble and spin.
func _draw_item(it: Item) -> void:
	var key := [it.kind, it.shape]
	if not _item_polys.has(key):
		_item_polys[key] = _build_item_polys(it.kind, it.shape)
	var polys: Dictionary = _item_polys[key]
	var def: Dictionary = ItemDefs.DEFS[it.kind]
	draw_set_transform(Vector2(it.x, it.y), it.angle)
	draw_colored_polygon(polys["body"], def["color"])
	draw_colored_polygon(polys["fleck"], def["fleck"])
	draw_polyline(polys["outline"], ITEM_OUTLINE, 1.0, true)


func _build_item_polys(kind: StringName, shape: int) -> Dictionary:
	var r := ItemDefs.radius_of(kind) * ITEM_DRAW_SCALE
	var mults: Array = ItemDefs.SHAPES[shape]
	var body := PackedVector2Array()
	for i in mults.size():
		body.append(Vector2.from_angle(TAU * i / mults.size()) * r * mults[i])
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


func _draw_part(type: StringName, cell: Vector2i, flipped: bool, tint: Color) -> void:
	var def: Dictionary = PartDefs.DEFS[type]
	var rect := Rect2(Vector2(cell * T), Vector2(def["size"] * T))
	var color: Color = def["color"] * tint
	match type:
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


func _draw_box(rect: Rect2, color: Color, tint: Color) -> void:
	draw_rect(rect, color)
	draw_rect(rect.grow(-1.0), OUTLINE * tint, false, 2.0)


func _draw_conveyor(rect: Rect2, color: Color, flipped: bool, tint: Color) -> void:
	draw_rect(rect, color)
	# Belt along the top, with marks that scroll in the travel direction while running.
	var belt := Rect2(rect.position, Vector2(rect.size.x, 8))
	draw_rect(belt, BELT * tint)
	var dir := -1.0 if flipped else 1.0
	var offset := 0.0
	if sim:
		offset = fposmod(sim.tick * PartGeometry.BELT_SPEED / Simulation.TICK_RATE * dir, 16.0)
	for i in range(-1, 2):
		var mx := rect.position.x + offset + i * 16.0 + 4.0
		if mx >= rect.position.x and mx + 4.0 <= rect.end.x:
			draw_rect(Rect2(Vector2(mx, rect.position.y + 3), Vector2(4, 2)), BELT_MARK * tint)
	# Rollers and a direction arrow on the housing.
	draw_circle(rect.position + Vector2(8, 22), 4.0, BELT * tint)
	draw_circle(rect.position + Vector2(24, 22), 4.0, BELT * tint)
	var c := rect.position + Vector2(16, 22)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-3 * dir, -4), c + Vector2(3 * dir, 0), c + Vector2(-3 * dir, 4),
	]), BELT_MARK * tint)
	draw_rect(rect.grow(-1.0), OUTLINE * tint, false, 2.0)
