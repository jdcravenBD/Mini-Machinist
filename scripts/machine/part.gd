class_name Part
extends RefCounted
## One placed part. `cell` is its top-left grid cell; `flipped` mirrors it left-right.

var type: StringName
var cell: Vector2i
var flipped: bool


func _init(p_type: StringName, p_cell: Vector2i, p_flipped := false) -> void:
	type = p_type
	cell = p_cell
	flipped = p_flipped


func cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var size := PartDefs.size_of(type)
	for y in size.y:
		for x in size.x:
			result.append(cell + Vector2i(x, y))
	return result
