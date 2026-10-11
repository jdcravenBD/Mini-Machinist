class_name Hud
extends CanvasLayer
## Bottom toolbar (part categories, the open category's parts, Play/Stop, Clear), the
## selected part's description above it, controls help top-left, stats top-right.

signal part_selected(type: StringName)
signal play_pressed
signal clear_pressed
signal demo_pressed

## Screen space the HUD covers above and below the world, for framing the camera.
const TOP_MARGIN := 56.0
const BOTTOM_MARGIN := 72.0
const TOOLBAR_HEIGHT := 44.0
const HELP := "Left click: place   Right click: remove   R: turn   F: sorter filter   1-9: pick part   Tab: next category\nSpace: play/stop   Middle drag or WASD: pan   Wheel: zoom   Home: re-center"

## Index into PartDefs.CATEGORIES of the category whose parts are showing.
var category := 0

var _category_buttons: Array[Button] = []
var _parts_row: HBoxContainer
var _part_buttons := {}  # StringName -> Button, for the open category
var _selected: StringName = &""
var _running := false
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
	panel.offset_top = -TOOLBAR_HEIGHT
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	var categories := ButtonGroup.new()
	for i in PartDefs.CATEGORIES.size():
		var button := _make_button(PartDefs.CATEGORIES[i]["name"])
		button.add_theme_font_size_override("font_size", 14)
		button.toggle_mode = true
		button.button_group = categories
		button.pressed.connect(func() -> void: show_category(i))
		row.add_child(button)
		_category_buttons.append(button)
	row.add_child(VSeparator.new())
	_parts_row = HBoxContainer.new()
	_parts_row.add_theme_constant_override("separation", 6)
	row.add_child(_parts_row)

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

	# The selected part's description, in a strip just above the toolbar.
	var hint_bar := PanelContainer.new()
	hint_bar.anchor_right = 1.0
	hint_bar.anchor_top = 1.0
	hint_bar.anchor_bottom = 1.0
	hint_bar.offset_top = -BOTTOM_MARGIN
	hint_bar.offset_bottom = -TOOLBAR_HEIGHT
	hint_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	hint_bar.self_modulate = Color(1, 1, 1, 0.7)
	add_child(hint_bar)
	var hint_pad := MarginContainer.new()
	hint_pad.add_theme_constant_override("margin_left", 12)
	hint_bar.add_child(hint_pad)
	_hint = Label.new()
	_hint.modulate = Color(1, 1, 1, 0.75)
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint_pad.add_child(_hint)

	show_category(0)


## The parts in the open category, in toolbar order.
func category_parts() -> Array:
	return PartDefs.CATEGORIES[category]["parts"]


func show_category(index: int) -> void:
	category = index
	_category_buttons[index].button_pressed = true
	for child in _parts_row.get_children():
		child.queue_free()
	_part_buttons.clear()
	var group := ButtonGroup.new()
	var parts := category_parts()
	for i in parts.size():
		var type: StringName = parts[i]
		var button := _make_button("%d %s" % [i + 1, PartDefs.DEFS[type]["name"]])
		button.add_theme_font_size_override("font_size", 14)
		button.toggle_mode = true
		button.button_group = group
		button.tooltip_text = PartDefs.DEFS[type]["hint"]
		button.disabled = _running
		button.button_pressed = type == _selected
		button.pressed.connect(func() -> void: part_selected.emit(type))
		_parts_row.add_child(button)
		_part_buttons[type] = button


func next_category() -> void:
	show_category((category + 1) % PartDefs.CATEGORIES.size())


## Marks `type` as the selected part, opening its category if needed.
func set_selected(type: StringName) -> void:
	_selected = type
	if not category_parts().has(type):
		for i in PartDefs.CATEGORIES.size():
			if PartDefs.CATEGORIES[i]["parts"].has(type):
				show_category(i)
	if _part_buttons.has(type):
		_part_buttons[type].button_pressed = true


func set_hint(text: String) -> void:
	_hint.text = text
	_hint.tooltip_text = text


func set_running(running: bool) -> void:
	_running = running
	_play_button.text = "Stop" if running else "Play"
	_clear_button.disabled = running
	_demo_button.disabled = running
	for button in _part_buttons.values():
		button.disabled = running
	for button in _category_buttons:
		button.disabled = running


func set_stats(text: String) -> void:
	_stats.text = text


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	# Keep Space free for Play/Stop instead of re-pressing the focused button.
	button.focus_mode = Control.FOCUS_NONE
	return button
