class_name Hud
extends CanvasLayer
## Bottom toolbar (parts, Play/Stop, Clear, part hint), controls help top-left, stats top-right.

signal part_selected(type: StringName)
signal play_pressed
signal clear_pressed
signal demo_pressed

## Screen space the HUD covers above and below the world, for framing the camera.
const TOP_MARGIN := 56.0
const BOTTOM_MARGIN := 48.0
const HELP := "Left click: place   Right click: remove   R: flip   1-6: pick part\nSpace: play/stop   Middle drag or WASD: pan   Wheel: zoom   Home: re-center"

var _part_buttons := {}  # StringName -> Button
var _play_button: Button
var _clear_button: Button
var _demo_button: Button
var _stats: Label
var _hint: Label


func _ready() -> void:
	var top := PanelContainer.new()
	top.anchor_right = 1.0
	top.offset_bottom = TOP_MARGIN
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(top)
	var top_pad := MarginContainer.new()
	top_pad.add_theme_constant_override("margin_left", 12)
	top_pad.add_theme_constant_override("margin_right", 12)
	top.add_child(top_pad)
	var top_row := HBoxContainer.new()
	top_pad.add_child(top_row)

	var help := Label.new()
	help.text = HELP
	help.modulate = Color(1, 1, 1, 0.6)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help.add_theme_font_size_override("font_size", 14)
	top_row.add_child(help)

	_stats = Label.new()
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stats.size_flags_vertical = Control.SIZE_FILL
	top_row.add_child(_stats)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_top = -BOTTOM_MARGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	var group := ButtonGroup.new()
	for i in PartDefs.ORDER.size():
		var type: StringName = PartDefs.ORDER[i]
		var button := _make_button("%d  %s" % [i + 1, PartDefs.DEFS[type]["name"]])
		button.toggle_mode = true
		button.button_group = group
		button.tooltip_text = PartDefs.DEFS[type]["hint"]
		button.pressed.connect(func() -> void: part_selected.emit(type))
		row.add_child(button)
		_part_buttons[type] = button

	row.add_child(VSeparator.new())
	_play_button = _make_button("Play")
	_play_button.custom_minimum_size.x = 72
	_play_button.pressed.connect(func() -> void: play_pressed.emit())
	row.add_child(_play_button)
	_clear_button = _make_button("Clear")
	_clear_button.pressed.connect(func() -> void: clear_pressed.emit())
	row.add_child(_clear_button)
	_demo_button = _make_button("Load Demo")
	_demo_button.pressed.connect(func() -> void: demo_pressed.emit())
	row.add_child(_demo_button)

	row.add_child(VSeparator.new())
	_hint = Label.new()
	_hint.modulate = Color(1, 1, 1, 0.6)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_hint)


func set_selected(type: StringName) -> void:
	if _part_buttons.has(type):
		_part_buttons[type].button_pressed = true
		_hint.text = PartDefs.DEFS[type]["hint"]


func set_running(running: bool) -> void:
	_play_button.text = "Stop" if running else "Play"
	_clear_button.disabled = running
	_demo_button.disabled = running
	for button in _part_buttons.values():
		button.disabled = running


func set_stats(text: String) -> void:
	_stats.text = text


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	# Keep Space free for Play/Stop instead of re-pressing the focused button.
	button.focus_mode = Control.FOCUS_NONE
	return button
