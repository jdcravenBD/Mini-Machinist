extends Node2D
## Mini Machinist prototype: build on the grid, then press Play to watch it run.
## Editing is only allowed while stopped; Stop throws away all items.

const SAVE_PATH := "user://machine.json"
const T := PartDefs.TILE
const PAN_SPEED := 600.0
const ZOOM_MIN := 0.5
const ZOOM_MAX := 3.0
## Most simulation ticks to run in one frame, so a slow frame can't snowball.
const MAX_TICKS_PER_FRAME := 4

@onready var view: WorldView = $WorldView
@onready var camera: Camera2D = $Camera
@onready var hud: Hud = $Hud

var machine := Machine.new()
var sim: Simulation = null
var selected: StringName = &"conveyor"
var flipped := false
var _accum := 0.0
var _panning := false
## Mouse button being dragged to paint (place) or erase, or MOUSE_BUTTON_NONE.
var _paint_button := MOUSE_BUTTON_NONE
var _last_paint_cell := Vector2i(-1, -1)


func _ready() -> void:
	if not _load():
		DemoMachine.build(machine)
	machine.changed.connect(_save)
	view.machine = machine
	hud.part_selected.connect(_select)
	hud.play_pressed.connect(_toggle_play)
	hud.clear_pressed.connect(machine.clear)
	hud.demo_pressed.connect(func() -> void: DemoMachine.build(machine))
	_select(selected)
	_frame_camera()


func _process(delta: float) -> void:
	if sim:
		var tick_time := 1.0 / Simulation.TICK_RATE
		_accum += delta
		var ticks := 0
		while _accum >= tick_time and ticks < MAX_TICKS_PER_FRAME:
			sim.step()
			_accum -= tick_time
			ticks += 1
		if ticks == MAX_TICKS_PER_FRAME:
			_accum = 0.0
		hud.set_stats("Running %.1fs    Items: %d    Bin: %d iron ore, %d rock    Lost: %d" % [
			sim.tick / float(Simulation.TICK_RATE), sim.items.size(),
			sim.delivered.get(&"iron_ore", 0), sim.delivered.get(&"rock", 0), sim.lost,
		])
	else:
		hud.set_stats("Building   Parts: %d" % machine.parts.size())

	_pan_with_keys(delta)
	_update_ghost()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event.keycode)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		if _panning:
			camera.position -= event.relative / camera.zoom
		elif _paint_button != MOUSE_BUTTON_NONE:
			_paint(_hover_cell())


func _handle_key(keycode: Key) -> void:
	if keycode == KEY_SPACE:
		_toggle_play()
	elif keycode == KEY_R:
		flipped = not flipped
	elif keycode >= KEY_1 and keycode < KEY_1 + PartDefs.ORDER.size():
		_select(PartDefs.ORDER[keycode - KEY_1])


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_zoom_at(event.position, 1.1)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_zoom_at(event.position, 1.0 / 1.1)
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
			if not event.pressed:
				_paint_button = MOUSE_BUTTON_NONE
			elif sim == null:
				_paint_button = event.button_index
				_last_paint_cell = Vector2i(-1, -1)
				_paint(_hover_cell())


func _paint(cell: Vector2i) -> void:
	if sim or cell == _last_paint_cell:
		return
	_last_paint_cell = cell
	if _paint_button == MOUSE_BUTTON_LEFT:
		machine.place(selected, cell, flipped)
	elif _paint_button == MOUSE_BUTTON_RIGHT:
		machine.remove_at(cell)


func _select(type: StringName) -> void:
	selected = type
	hud.set_selected(type)


func _toggle_play() -> void:
	if sim:
		sim = null
	else:
		sim = PartGeometry.build(machine)
		_accum = 0.0
	_paint_button = MOUSE_BUTTON_NONE
	view.sim = sim
	hud.set_running(sim != null)


func _update_ghost() -> void:
	if sim or _panning:
		view.ghost_type = &""
		return
	var cell := _hover_cell()
	view.ghost_type = selected
	view.ghost_cell = cell
	view.ghost_flipped = flipped and PartDefs.is_flippable(selected)
	view.ghost_valid = machine.can_place(selected, cell)


func _hover_cell() -> Vector2i:
	var p := get_global_mouse_position()
	return Vector2i(floori(p.x / T), floori(p.y / T))


func _pan_with_keys(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	camera.position += dir * PAN_SPEED * delta / camera.zoom.x


## Zooms while keeping the world point under the mouse in place.
func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var half := get_viewport_rect().size * 0.5
	var world := camera.position + (screen_pos - half) / camera.zoom
	var z := clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)
	camera.position = world - (screen_pos - half) / camera.zoom


## Fits the whole grid in the space between the top and bottom HUD bars.
func _frame_camera() -> void:
	var world_size := Vector2(Machine.WIDTH * T, Machine.HEIGHT * T)
	var screen := get_viewport_rect().size
	var space := screen - Vector2(24, Hud.TOP_MARGIN + Hud.BOTTOM_MARGIN + 16)
	var z := clampf(minf(space.x / world_size.x, space.y / world_size.y), ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)
	# Shift so the grid centers in the free space rather than the whole screen.
	var offset_y := (Hud.TOP_MARGIN - Hud.BOTTOM_MARGIN) * 0.5
	camera.position = world_size * 0.5 - Vector2(0, offset_y) / z


func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(machine.to_dict(), "\t"))


func _load() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data is Dictionary:
		machine.load_dict(data)
		return true
	return false
