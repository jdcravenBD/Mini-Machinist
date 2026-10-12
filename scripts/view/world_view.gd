class_name WorldView
extends Node2D
## Draws the grid, parts, items and the placement preview.
##
## Everything is pixel art at 32 x 32 pixels per tile (see PixelArt), drawn without smoothing
## so pixels stay square. Items are pixel clumps that rotate as a picture with the rock.
##
## Layers, back to front: the grid and parts (this node), the glow of hot parts (a child,
## masked to the parts' own pixels so empty space never glows), then molten metal, items,
## sorter boxes (over the items riding through them) and the placement preview (a child).

const T := PartDefs.TILE
## A piston plate's thickness (as in the physics).
const PISTON_PLATE := 6.0
const BACKGROUND := Color(0.16, 0.155, 0.15)
const GRID_LINE := Color(1, 1, 1, 0.05)
const BORDER := Color(1, 1, 1, 0.18)
## How strongly hot parts glow over their own look (1 hides their letters at full heat).
const GLOW_STRENGTH := 0.6
const GLOW_SHADER := """
shader_type canvas_item;
uniform sampler2D mask : filter_nearest;
uniform float strength;
void fragment() {
	vec4 glow = texture(TEXTURE, UV);
	COLOR = vec4(glow.rgb, glow.a * texture(mask, UV).r * strength);
}
"""

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
var _glow_layer := Node2D.new()
var _glow_material := ShaderMaterial.new()
var _glow_sim: Simulation
var _front_layer := Node2D.new()
## Molten and hardened metal, one texture per block of the pixel layer that has any in it
## (chunk index -> ImageTexture), refreshed only where the metal changed.
var _chunks := {}
var _chunks_sim: Simulation


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shader := Shader.new()
	shader.code = GLOW_SHADER
	_glow_material.shader = shader
	_glow_material.set_shader_parameter("strength", GLOW_STRENGTH)
	_glow_layer.material = _glow_material
	_glow_layer.draw.connect(_draw_glow)
	add_child(_glow_layer)
	_front_layer.draw.connect(_draw_front)
	add_child(_front_layer)


func _process(_delta: float) -> void:
	queue_redraw()
	_glow_layer.queue_redraw()
	_front_layer.queue_redraw()


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
			if p.type != &"sorter":
				_draw_part(p, Color.WHITE)


## Molten metal, items, then sorter boxes over the items riding through them, then the
## placement preview.
func _draw_front() -> void:
	if sim:
		_draw_metal()
		_draw_items()
	if machine:
		for p in machine.parts:
			if p.type == &"sorter":
				_draw_part(p, Color.WHITE, _front_layer)
	if sim == null and ghost != null:
		var tint := Color(1, 1, 1, 0.55) if ghost_valid else Color(1, 0.35, 0.35, 0.55)
		_draw_part(ghost, tint, _front_layer)


## Hot parts glow, from dark red through orange and yellow to near white, only on their own
## pixels (the shader masks the glow with the parts' outline).
func _draw_glow() -> void:
	if sim == null:
		return
	if _glow_sim != sim:
		_glow_sim = sim
		var mask := Image.create_from_data(Machine.WIDTH * T, Machine.HEIGHT * T, false, Image.FORMAT_L8, sim.world.wall_mask())
		_glow_material.set_shader_parameter("mask", ImageTexture.create_from_image(mask))
	var columns: int = sim.world.heat_columns()
	var rows: int = sim.world.heat_rows_count()
	var data: PackedByteArray = sim.world.heat_image()
	if _heat_image == null or _heat_image.get_width() != columns or _heat_image.get_height() != rows:
		_heat_image = Image.create_from_data(columns, rows, false, Image.FORMAT_RGBA8, data)
		_heat_texture = ImageTexture.create_from_image(_heat_image)
	else:
		_heat_image.set_data(columns, rows, false, Image.FORMAT_RGBA8, data)
		_heat_texture.update(_heat_image)
	_glow_layer.draw_texture_rect(_heat_texture, Rect2(Vector2.ZERO, Vector2(Machine.WIDTH * T, Machine.HEIGHT * T)), false)


## Molten metal, in blocks of pixels redrawn only where it changed.
func _draw_metal() -> void:
	if _chunks_sim != sim:
		_chunks.clear()
		_chunks_sim = sim
	var size: int = sim.world.chunk_size()
	for chunk in sim.world.dirty_chunks():
		var data: PackedByteArray = sim.world.chunk_image(chunk)
		if data.is_empty():
			_chunks.erase(chunk)
			continue
		var image := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
		var texture: ImageTexture = _chunks.get(chunk)
		if texture == null:
			_chunks[chunk] = ImageTexture.create_from_image(image)
		else:
			texture.update(image)
	var columns: int = sim.world.chunk_columns()
	for chunk in _chunks:
		_front_layer.draw_texture(_chunks[chunk], Vector2(chunk % columns, chunk / columns) * size)


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
		_front_layer.draw_multimesh(multimesh, art["texture"])


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


## Draws onto `canvas` (this node, or one of its layers).
func _draw_part(p: Part, tint: Color, canvas: CanvasItem = self) -> void:
	var def: Dictionary = PartDefs.DEFS[p.type]
	var origin := Vector2(p.cell * T)
	match p.type:
		&"large_crusher":
			var r := PartGeometry.LARGE_ROLLER
			_draw_roller(origin + Vector2(T * 0.5, T * 0.5), r, 1.0, def, tint, canvas)
			_draw_roller(origin + Vector2(T * 1.5, T * 0.5), r, -1.0, def, tint, canvas)
		&"small_crusher":
			var r := PartGeometry.SMALL_ROLLER
			for row in 2:
				var cy := T * (0.25 + row * 0.5)
				_draw_roller(origin + Vector2(T * 0.25, cy), r, 1.0, def, tint, canvas)
				_draw_roller(origin + Vector2(T * 0.75, cy), r, -1.0, def, tint, canvas)
		&"piston":
			var art := PixelArt.part(p)
			canvas.draw_texture(art["texture"], origin, tint)
			_draw_piston_plate(p, def, tint, canvas)
		&"signal":
			var art := PixelArt.part(p)
			var lit := sim != null and Simulation.is_signal_lit(sim.tick, p.variant)
			canvas.draw_texture(art["texture"], origin, tint * (Color(1.6, 1.6, 1.6) if lit else Color.WHITE))
		&"bellows":
			# Squashed from the top while it's pumping.
			var art := PixelArt.part(p)
			var texture: Texture2D = art["texture"]
			var squash := 6.0 if sim and Simulation.is_pumping(sim.tick) else 0.0
			canvas.draw_texture_rect(texture, Rect2(origin + Vector2(0, squash), Vector2(T, T - squash)), false, tint)
		_:
			var art := PixelArt.part(p)
			canvas.draw_texture(art["texture"], origin + art["offset"], tint)


## A piston's rod and plate, as far down as the plate is.
func _draw_piston_plate(p: Part, def: Dictionary, tint: Color, canvas: CanvasItem) -> void:
	var ext := sim.piston_extension(p.cell) if sim else 0.0
	var origin := Vector2(p.cell * T)
	var inset := PartGeometry.PISTON_INSET
	var bottom := T + ext
	var plate := Rect2(origin + Vector2(inset, bottom - PISTON_PLATE), Vector2(T - inset * 2.0, PISTON_PLATE))
	var color: Color = def["color"]
	var dark := color.darkened(PixelArt.STROKE_SHADE)
	if ext > 0.0:
		canvas.draw_rect(Rect2(origin + Vector2(T * 0.5 - 4.0, T - 2.0), Vector2(8.0, ext - PISTON_PLATE + 2.0)), Color(0.55, 0.55, 0.58) * tint)
	canvas.draw_rect(plate, dark * tint)
	canvas.draw_rect(plate.grow(-1.0), color.lightened(0.15) * tint)


## A crusher roller, turned as it spins so its letter shows the turning.
func _draw_roller(center: Vector2, radius: float, direction: float, def: Dictionary, tint: Color, canvas: CanvasItem) -> void:
	var turn := 0.0
	if sim:
		turn = sim.tick / float(Simulation.TICK_RATE) * PartGeometry.ROLLER_SPEED / radius * direction
	var art := PixelArt.roller(radius, def["color"], def["letter"])
	canvas.draw_set_transform(center, turn)
	canvas.draw_texture(art["texture"], art["offset"], tint)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
