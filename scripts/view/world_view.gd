class_name WorldView
extends Node2D
## Draws the grid, parts, items and the placement preview.
##
## Everything is pixel art at 32 x 32 pixels per tile (see PixelArt), drawn without smoothing
## so pixels stay square. Items are pixel clumps that rotate as a picture with the rock.

const T := PartDefs.TILE
const BACKGROUND := Color(0.16, 0.155, 0.15)
const GRID_LINE := Color(1, 1, 1, 0.05)
const BORDER := Color(1, 1, 1, 0.18)
## Inside a crucible: unmelted pieces, molten iron and slag.
const CRUCIBLE_SOLIDS := Color(0.50, 0.33, 0.24)
const MOLTEN_IRON := Color(1.0, 0.62, 0.18)
const MOLTEN_SLAG := Color(0.42, 0.26, 0.16)

var machine: Machine
var sim: Simulation
## Placement preview, or null when there's nothing to preview.
var ghost: Part = null
var ghost_valid := true
## Items are drawn in one call per item type (see Simulation.type_id): a textured square
## per item, placed and turned by a buffer of transforms the physics fills in directly.
## Drawing each item separately costs a frame dozens of milliseconds with a few hundred.
var _multimeshes := {}
## The glow of hot solids, one pixel per heat cell, stretched over the world.
var _heat_image: Image
var _heat_texture: ImageTexture


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


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
		_draw_heat()
		_draw_items()
	elif ghost != null:
		var tint := Color(1, 1, 1, 0.55) if ghost_valid else Color(1, 0.35, 0.35, 0.55)
		_draw_part(ghost, tint)


## Hot solids glow, from dark red through orange and yellow to near white.
func _draw_heat() -> void:
	var columns: int = sim.world.heat_columns()
	var rows: int = sim.world.heat_rows_count()
	var data: PackedByteArray = sim.world.heat_image()
	if _heat_image == null or _heat_image.get_width() != columns or _heat_image.get_height() != rows:
		_heat_image = Image.create_from_data(columns, rows, false, Image.FORMAT_RGBA8, data)
		_heat_texture = ImageTexture.create_from_image(_heat_image)
	else:
		_heat_image.set_data(columns, rows, false, Image.FORMAT_RGBA8, data)
		_heat_texture.update(_heat_image)
	draw_texture_rect(_heat_texture, Rect2(Vector2.ZERO, Vector2(Machine.WIDTH * T, Machine.HEIGHT * T)), false)


func _draw_items() -> void:
	var buffers := sim.draw_buffers()
	for type in buffers.size():
		var buffer: PackedFloat32Array = buffers[type]
		if buffer.is_empty():
			continue
		var art := _item_art(type)
		var multimesh: MultiMesh = _multimeshes.get(type)
		if multimesh == null:
			multimesh = MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_2D
			multimesh.use_colors = true
			multimesh.mesh = _quad(art["rect"])
			_multimeshes[type] = multimesh
		multimesh.instance_count = buffer.size() / 12
		multimesh.buffer = buffer
		draw_multimesh(multimesh, art["texture"])


## The item being crushed is pushed straight down between the rollers, at full size, until
## it breaks into pieces that drop out the bottom as real items.
func _draw_crushing(state: Dictionary) -> void:
	if not state["held"]:
		return
	var t: float = state["progress"]
	var pos := Vector2(lerpf(state["held_x"], state["exit_x"], t), lerpf(state["held_y"], state["press_y"], t))
	var c: float = state["c"]
	var s: float = state["s"]
	var art := _item_art(state["type"])
	draw_set_transform_matrix(Transform2D(Vector2(c, s), Vector2(-s, c), pos))
	draw_texture_rect(art["texture"], art["rect"], false)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _item_art(type: int) -> Dictionary:
	var info := Simulation.type_info(type)
	return PixelArt.item(info[0], info[1], info[2])


## A square covering `rect` with the whole texture on it.
func _quad(rect: Rect2) -> ArrayMesh:
	var a := rect.position
	var b := Vector2(rect.end.x, rect.position.y)
	var c := rect.end
	var d := Vector2(rect.position.x, rect.end.y)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([a, b, c, a, c, d])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])
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
	var origin := Vector2(p.cell * T)
	match p.type:
		&"large_crusher":
			var r := PartGeometry.LARGE_ROLLER
			_draw_roller(origin + Vector2(T * 0.5, T * 0.5), r, 1.0, def, tint)
			_draw_roller(origin + Vector2(T * 1.5, T * 0.5), r, -1.0, def, tint)
		&"small_crusher":
			var r := PartGeometry.SMALL_ROLLER
			for row in 2:
				var cy := T * (0.25 + row * 0.5)
				_draw_roller(origin + Vector2(T * 0.25, cy), r, 1.0, def, tint)
				_draw_roller(origin + Vector2(T * 0.75, cy), r, -1.0, def, tint)
		&"crucible":
			_draw_crucible(p, tint)
		&"bellows":
			# Squashed from the top while it's pumping.
			var art := PixelArt.part(p)
			var texture: Texture2D = art["texture"]
			var squash := 6.0 if sim and Smelter.is_pumping(sim.tick) else 0.0
			draw_texture_rect(texture, Rect2(origin + Vector2(0, squash), Vector2(T, T - squash)), false, tint)
		_:
			var art := PixelArt.part(p)
			draw_texture(art["texture"], origin + art["offset"], tint)


## A crusher roller, turned as it spins so its letter shows the turning.
func _draw_roller(center: Vector2, radius: float, direction: float, def: Dictionary, tint: Color) -> void:
	var turn := 0.0
	if sim:
		turn = sim.tick / float(Simulation.TICK_RATE) * PartGeometry.ROLLER_SPEED / radius * direction
	var art := PixelArt.roller(radius, def["color"], def["letter"])
	draw_set_transform(center, turn)
	draw_texture(art["texture"], art["offset"], tint)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## A crucible: its body, what's inside (unmelted pieces, molten iron, slag floating on top),
## its temperature, and, while pouring, tipped over with a stream falling from its lip.
func _draw_crucible(p: Part, tint: Color) -> void:
	var rect := Rect2(Vector2(p.cell * T), Vector2(PartDefs.size_of(p.type) * T))
	var smelter: Smelter = sim.smelters_by_cell.get(p.cell) if sim else null
	# Tipping pivots on the bottom corner on the pouring side.
	var tilt := smelter.tilt * smelter.pour_dir if smelter else 0.0
	var pivot := Vector2(rect.end.x if tilt > 0.0 else rect.position.x, rect.end.y)
	draw_set_transform(pivot, tilt * Smelter.TILT_ANGLE)
	var local := Rect2(rect.position - pivot, rect.size)
	draw_texture(PixelArt.part(p)["texture"], local.position, tint)
	if smelter:
		# Fill levels, bottom up, as a share of what the crucible holds.
		var inside := local.grow(-4.0)
		var y := inside.end.y
		for layer in [[smelter.solid_amount(), CRUCIBLE_SOLIDS], [smelter.iron, MOLTEN_IRON], [smelter.slag, MOLTEN_SLAG]]:
			var height := floorf(minf(y - inside.position.y, inside.size.y * layer[0] / Smelter.CAPACITY))
			if height > 0.0:
				draw_rect(Rect2(Vector2(inside.position.x, y - height), Vector2(inside.size.x, height)), layer[1] * tint)
				y -= height
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if smelter:
		var hot := clampf((smelter.temperature - 300.0) / (Smelter.MELT_POINT - 300.0), 0.0, 1.0)
		var label := Color(0.8, 0.8, 0.8).lerp(MOLTEN_IRON, hot)
		var font := ThemeDB.fallback_font
		var text := "%d°" % roundi(smelter.temperature)
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		draw_string(font, Vector2(rect.get_center().x - width * 0.5, rect.position.y - 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, label)
		if smelter.stream_on:
			draw_line(Vector2(smelter.stream_x, smelter.stream_top), Vector2(smelter.stream_x, smelter.stream_y), MOLTEN_IRON, 3.0)
