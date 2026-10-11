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
	var result: Array[Vector2i] = []
	var size := PartDefs.size_of(type)
	for y in size.y:
		for x in size.x:
			result.append(cell + Vector2i(x, y))
	return result
