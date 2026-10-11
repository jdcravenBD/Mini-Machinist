class_name Machine
extends RefCounted
## The player's build: which parts sit on which grid cells.

signal changed

const WIDTH := 40
const HEIGHT := 24

var parts: Array[Part] = []
var _occupied := {}  # Vector2i -> Part


func can_place(type: StringName, cell: Vector2i) -> bool:
	var size := PartDefs.size_of(type)
	for y in size.y:
		for x in size.x:
			var c := cell + Vector2i(x, y)
			if c.x < 0 or c.y < 0 or c.x >= WIDTH or c.y >= HEIGHT or _occupied.has(c):
				return false
	return true


func place(type: StringName, cell: Vector2i, flipped := false) -> Part:
	if not can_place(type, cell):
		return null
	var part := Part.new(type, cell, flipped and PartDefs.is_flippable(type))
	parts.append(part)
	for c in part.cells():
		_occupied[c] = part
	changed.emit()
	return part


func part_at(cell: Vector2i) -> Part:
	return _occupied.get(cell)


func remove_at(cell: Vector2i) -> bool:
	var part := part_at(cell)
	if part == null:
		return false
	for c in part.cells():
		_occupied.erase(c)
	parts.erase(part)
	changed.emit()
	return true


func clear() -> void:
	parts.clear()
	_occupied.clear()
	changed.emit()


## Parts sorted top-to-bottom, left-to-right, so building the simulation never depends
## on the order the player happened to place things.
func sorted_parts() -> Array[Part]:
	var result: Array[Part] = []
	result.assign(parts)
	result.sort_custom(func(a: Part, b: Part) -> bool:
		return a.cell.y < b.cell.y or (a.cell.y == b.cell.y and a.cell.x < b.cell.x))
	return result


func to_dict() -> Dictionary:
	var list := []
	for p in sorted_parts():
		list.append({"type": String(p.type), "x": p.cell.x, "y": p.cell.y, "flipped": p.flipped})
	return {"version": 1, "parts": list}


func load_dict(data: Dictionary) -> void:
	parts.clear()
	_occupied.clear()
	for entry in data.get("parts", []):
		var type := StringName(entry.get("type", ""))
		if PartDefs.DEFS.has(type):
			var cell := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
			if can_place(type, cell):
				var part := Part.new(type, cell, bool(entry.get("flipped", false)))
				parts.append(part)
				for c in part.cells():
					_occupied[c] = part
	changed.emit()
