class_name Part
extends RefCounted
## One placed part. `cell` is its top-left grid cell.

var type: StringName
var cell: Vector2i
## Which way it faces: belt direction, ramp slope, panel edge. See PartDefs "variants".
var variant: int
## What a sorter drops through (an item kind), empty for parts without a filter.
var filter: StringName


func _init(p_type: StringName, p_cell: Vector2i, p_variant := 0, p_filter: StringName = &"") -> void:
	type = p_type
	cell = p_cell
	variant = p_variant
	filter = p_filter


func cells() -> Array[Vector2i]:
	return PartDefs.footprint(type, cell)
