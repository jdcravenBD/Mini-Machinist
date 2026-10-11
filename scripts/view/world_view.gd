class_name WorldView
extends Node2D
## Draws the grid, parts, items and the placement preview.
##
## Parts use a simple development look until real art arrives: each is its color with a
## darker stroke just inside its edge and its letter in the middle (see PartDefs). Shapes are
## the parts' real sizes, so art can be swapped in per part in _draw_part.

const T := PartDefs.TILE
const BACKGROUND := Color(0.16, 0.155, 0.15)
const GRID_LINE := Color(1, 1, 1, 0.05)
const BORDER := Color(1, 1, 1, 0.18)
## How much darker a part's inner stroke is than its color, and how thick it is.
const STROKE_SHADE := 0.35
const STROKE_WIDTH := 2.0
const LETTER_SIZE := 14
## Inside a crucible: unmelted pieces, molten iron and slag.
const CRUCIBLE_SOLIDS := Color(0.50, 0.33, 0.24)
const MOLTEN_IRON := Color(1.0, 0.62, 0.18)
const MOLTEN_SLAG := Color(0.42, 0.26, 0.16)
## How dark an item's outline is, and how thick (it's thinner on tiny items).
const ITEM_OUTLINE_SHADE := 0.45
const ITEM_OUTLINE_WIDTH := 0.8

var machine: Machine
var sim: Simulation
## Placement preview, or null when there's nothing to preview.
var ghost: Part = null
var ghost_valid := true
## Item meshes by type id (see Simulation.type_id). Every item of a type is drawn in one
## call from a buffer of transforms the physics fills in directly; drawing each item
## separately costs a frame dozens of milliseconds once a few hundred are on screen.
var _meshes := {}
var _multimeshes := {}


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var size := Vector2(Machine.WIDTH * T, Machine.HEIGHT * T)
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	if sim == null:
		_draw_grid(size)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER, false, 2.0)

	# Items being crushed go behind the parts, so they look pushed down between the rollers.
	if sim:
		for i in sim.crusher_count():
			_draw_crushing(sim.crusher_state(i))

	if machine:
		for p in machine.parts:
			_draw_part(p, Color.WHITE)

	if sim:
		_draw_items()
	elif ghost != null:
		var tint := Color(1, 1, 1, 0.55) if ghost_valid else Color(1, 0.35, 0.35, 0.55)
		_draw_part(ghost, tint)


## Every item's real collision outline, with a lighter fleck so you can see it turn.
func _draw_items() -> void:
	var buffers := sim.draw_buffers()
	for type in buffers.size():
		var buffer: PackedFloat32Array = buffers[type]
		if buffer.is_empty():
			continue
		var multimesh: MultiMesh = _multimeshes.get(type)
		if multimesh == null:
			multimesh = MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_2D
			multimesh.mesh = _mesh_for(type)
			_multimeshes[type] = multimesh
		multimesh.instance_count = buffer.size() / 8
		multimesh.buffer = buffer
		draw_multimesh(multimesh, null)


## The item being crushed is pushed straight down between the rollers, at full size, until
## it breaks into pieces that drop out the bottom as real items.
func _draw_crushing(state: Dictionary) -> void:
	if not state["held"]:
		return
	var t: float = state["progress"]
	var pos := Vector2(lerpf(state["held_x"], state["exit_x"], t), lerpf(state["held_y"], state["press_y"], t))
	var c: float = state["c"]
	var s: float = state["s"]
	draw_mesh(_mesh_for(state["type"]), null, Transform2D(Vector2(c, s), Vector2(-s, c), pos))


func _mesh_for(type: int) -> ArrayMesh:
	if not _meshes.has(type):
		var info := Simulation.type_info(type)
		_meshes[type] = _build_item_mesh(info[0], info[1], info[2])
	return _meshes[type]


## One item's look as a mesh with baked colors: the body, a dark outline ring just inside
## its edge, and a lighter fleck.
func _build_item_mesh(kind: StringName, size: StringName, shape: int) -> ArrayMesh:
	var def: Dictionary = ItemDefs.DEFS[kind]
	var body_color: Color = def["color"]
	var outline_color := body_color.lerp(Color.BLACK, ITEM_OUTLINE_SHADE)
	var outline := ItemDefs.outline(kind, size, shape)
	var corners: Array[Vector2] = []
	for i in outline.size() / 2:
		corners.append(Vector2(outline[i * 2], outline[i * 2 + 1]))
	var width := minf(ITEM_OUTLINE_WIDTH, Shape.bounding_radius(outline) * 0.15)
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	for i in corners.size():
		var a := corners[i]
		var b := corners[(i + 1) % corners.size()]
		var a_in := a * (1.0 - width / a.length())
		var b_in := b * (1.0 - width / b.length())
		verts.append_array([Vector2.ZERO, a_in, b_in, a, b, b_in, a, b_in, a_in])
		colors.append_array([body_color, body_color, body_color, outline_color, outline_color, outline_color, outline_color, outline_color, outline_color])
	# Fleck: a small facet between the first two corners, pulled toward the center.
	verts.append_array([corners[0] * 0.75, corners[1] * 0.75, (corners[0] + corners[1]) * 0.2])
	var fleck: Color = def["fleck"]
	colors.append_array([fleck, fleck, fleck])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _draw_grid(size: Vector2) -> void:
	for x in range(1, Machine.WIDTH):
		draw_line(Vector2(x * T, 0), Vector2(x * T, size.y), GRID_LINE)
	for y in range(1, Machine.HEIGHT):
		draw_line(Vector2(0, y * T), Vector2(size.x, y * T), GRID_LINE)


func _draw_part(p: Part, tint: Color) -> void:
	var def: Dictionary = PartDefs.DEFS[p.type]
	var rect := Rect2(Vector2(p.cell * T), Vector2(def["size"] * T))
	var color: Color = def["color"]
	var letter: String = def["letter"]
	match p.type:
		&"conveyor":
			var belt := Rect2(rect.position, Vector2(T, PartGeometry.CONVEYOR_HEIGHT))
			_draw_styled(belt, color, "<" if p.variant == 1 else ">", tint, 12)
		&"sorter":
			# A box with a hood above the belt line, a dark mouth on the side the belt comes
			# from, and a dot showing what it drops.
			var hood := PartGeometry.SORTER_HOOD
			var box := Rect2(rect.position - Vector2(0, hood), Vector2(T, PartGeometry.CONVEYOR_HEIGHT + hood))
			_draw_styled(box, color, letter, tint, 12)
			var mouth_x := box.position.x + 2.0 if p.variant == 0 else box.end.x - 6.0
			draw_rect(Rect2(Vector2(mouth_x, box.position.y + 2.0), Vector2(4, box.size.y - 4.0)), color.darkened(0.7) * tint)
			if ItemDefs.DEFS.has(p.filter):
				var dot_x := box.end.x - 9.0 if p.variant == 0 else box.position.x + 3.0
				draw_rect(Rect2(Vector2(dot_x, box.position.y + 3.0), Vector2(6, 6)), ItemDefs.DEFS[p.filter]["color"] * tint)
		&"ramp":
			var pts := PackedVector2Array([rect.position, rect.position + Vector2(0, T), rect.end])
			if p.variant == 1:
				pts = PackedVector2Array([rect.position + Vector2(T, 0), rect.end, rect.position + Vector2(0, T)])
			_draw_styled_polygon(pts, color, letter, tint, 10)
		&"hopper":
			var mid := rect.position.x + rect.size.x * 0.5
			var gap := PartGeometry.HOPPER_GAP * 0.5
			var wall := 5.0
			_draw_styled_polygon(PackedVector2Array([
				rect.position, rect.position + Vector2(wall, 0),
				Vector2(mid - gap, rect.end.y), Vector2(mid - gap - wall, rect.end.y),
			]), color, "", tint)
			_draw_styled_polygon(PackedVector2Array([
				Vector2(rect.end.x - wall, rect.position.y), Vector2(rect.end.x, rect.position.y),
				Vector2(mid + gap + wall, rect.end.y), Vector2(mid + gap, rect.end.y),
			]), color, "", tint)
			_draw_letter(Vector2(mid, rect.position.y + 10), letter, color * tint, 12)
		&"large_crusher":
			var r := PartGeometry.LARGE_ROLLER
			_draw_roller(rect.position + Vector2(T * 0.5, T * 0.5), r, 1.0, color, letter, tint)
			_draw_roller(rect.position + Vector2(T * 1.5, T * 0.5), r, -1.0, color, letter, tint)
		&"small_crusher":
			var r := PartGeometry.SMALL_ROLLER
			for row in 2:
				var cy := T * (0.25 + row * 0.5)
				_draw_roller(rect.position + Vector2(T * 0.25, cy), r, 1.0, color, letter, tint)
				_draw_roller(rect.position + Vector2(T * 0.75, cy), r, -1.0, color, letter, tint)
		&"panel":
			_draw_styled(PartGeometry.panel_rect(p), color, "", tint, LETTER_SIZE, 1.5)
		&"bin":
			var inset := PartGeometry.BIN_INSET
			var wall := 4.0
			var l := rect.position.x + inset
			var r := rect.end.x - inset
			_draw_styled(Rect2(Vector2(l - wall * 0.5, rect.position.y), Vector2(wall, T)), color, "", tint, 0, 1.0)
			_draw_styled(Rect2(Vector2(r - wall * 0.5, rect.position.y), Vector2(wall, T)), color, "", tint, 0, 1.0)
			_draw_styled(Rect2(Vector2(l - wall * 0.5, rect.end.y - wall), Vector2(r - l + wall, wall)), color, "", tint, 0, 1.0)
			_draw_letter(rect.get_center(), letter, color * tint, LETTER_SIZE)
		&"crucible":
			_draw_crucible(p, rect, color, letter, tint)
		&"bellows":
			# Squashed while it's pumping.
			var body := rect
			if sim and Smelter.is_pumping(sim.tick):
				body = rect.grow_individual(0, -6, 0, 0)
			_draw_styled(body, color, letter, tint)
		_:
			_draw_styled(rect, color, letter, tint)


## The development look: a solid color, a darker stroke just inside the edge, and a letter.
func _draw_styled(rect: Rect2, color: Color, letter: String, tint: Color, letter_size := LETTER_SIZE, stroke := STROKE_WIDTH) -> void:
	draw_rect(rect, color * tint)
	stroke = minf(stroke, minf(rect.size.x, rect.size.y) * 0.25)
	draw_rect(rect.grow(-stroke * 0.5), color.darkened(STROKE_SHADE) * tint, false, stroke)
	if letter != "":
		_draw_letter(rect.get_center(), letter, _letter_color(color) * tint, letter_size)


## The same look for a shape that isn't a rectangle (its stroke follows the edge inward).
func _draw_styled_polygon(points: PackedVector2Array, color: Color, letter: String, tint: Color, letter_size := LETTER_SIZE) -> void:
	draw_colored_polygon(points, color * tint)
	var center := Vector2.ZERO
	for point in points:
		center += point
	center /= points.size()
	var inner := PackedVector2Array()
	for point in points:
		var toward := center - point
		inner.append(point + toward.normalized() * minf(STROKE_WIDTH, toward.length() * 0.5))
	inner.append(inner[0])
	draw_polyline(inner, color.darkened(STROKE_SHADE) * tint, STROKE_WIDTH * 0.75)
	if letter != "":
		_draw_letter(center, letter, _letter_color(color) * tint, letter_size)


func _draw_letter(center: Vector2, letter: String, color: Color, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	var size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, center + Vector2(-size.x * 0.5, font_size * 0.35), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Dark letters on light parts, light letters on dark ones.
func _letter_color(color: Color) -> Color:
	return color.darkened(0.6) if color.get_luminance() > 0.4 else color.lightened(0.6)


## A roller in the development look. Its letter turns with it, so you can see it spin.
func _draw_roller(center: Vector2, radius: float, direction: float, color: Color, letter: String, tint: Color) -> void:
	var turn := 0.0
	if sim:
		turn = sim.tick / float(Simulation.TICK_RATE) * PartGeometry.ROLLER_SPEED / radius * direction
	draw_circle(center, radius, color * tint)
	draw_arc(center, radius - STROKE_WIDTH * 0.5, 0.0, TAU, 32, color.darkened(STROKE_SHADE) * tint, STROKE_WIDTH)
	draw_set_transform(center, turn)
	_draw_letter(Vector2.ZERO, letter, _letter_color(color) * tint, int(radius * 0.9))
	draw_set_transform_matrix(Transform2D.IDENTITY)


## A crucible: its body, what's inside (unmelted pieces, molten iron, slag floating on top),
## its temperature, and, while pouring, tipped over with a stream falling from its lip.
func _draw_crucible(p: Part, rect: Rect2, color: Color, letter: String, tint: Color) -> void:
	var smelter: Smelter = sim.smelters_by_cell.get(p.cell) if sim else null
	# Tipping pivots on the bottom corner on the pouring side.
	var tilt := smelter.tilt * smelter.pour_dir if smelter else 0.0
	var pivot := Vector2(rect.end.x if tilt > 0.0 else rect.position.x, rect.end.y)
	draw_set_transform(pivot, tilt * Smelter.TILT_ANGLE)
	var local := Rect2(rect.position - pivot, rect.size)
	_draw_styled(local, color, "", tint)
	if smelter:
		# Fill levels, bottom up, as a share of what the crucible holds.
		var inside := local.grow(-4.0)
		var y := inside.end.y
		for layer in [[smelter.solid_amount(), CRUCIBLE_SOLIDS], [smelter.iron, MOLTEN_IRON], [smelter.slag, MOLTEN_SLAG]]:
			var height := minf(y - inside.position.y, inside.size.y * layer[0] / Smelter.CAPACITY)
			if height > 0.0:
				draw_rect(Rect2(Vector2(inside.position.x, y - height), Vector2(inside.size.x, height)), layer[1] * tint)
				y -= height
	_draw_letter(local.get_center(), letter, _letter_color(color) * tint, LETTER_SIZE)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if smelter:
		var hot := clampf((smelter.temperature - 300.0) / (Smelter.MELT_POINT - 300.0), 0.0, 1.0)
		var label := Color(0.8, 0.8, 0.8).lerp(MOLTEN_IRON, hot)
		_draw_letter(Vector2(rect.get_center().x, rect.position.y - 5), "%d°" % roundi(smelter.temperature), label, 9)
		if smelter.stream_on:
			draw_line(Vector2(smelter.stream_x, smelter.stream_top), Vector2(smelter.stream_x, smelter.stream_y), MOLTEN_IRON, 3.0)
