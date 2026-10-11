class_name Machine
extends RefCounted
## The player's build: which parts sit on which grid cells.

signal changed

const WIDTH := 40
const HEIGHT := 24

var parts: Array[Part] = []
var _occupied := {}  # Vector2i -> Part


func can_place(type: StringName, cell: Vector2i) -> bool:
	for c in PartDefs.footprint(type, cell):
		if c.x < 0 or c.y < 0 or c.x >= WIDTH or c.y >= HEIGHT or _occupied.has(c):
			return false
	return true


## `variant` wraps around the part's variant count, so one "turn" setting works for all.
func place(type: StringName, cell: Vector2i, variant := 0, filter: StringName = &"") -> Part:
	if not can_place(type, cell):
		return null
	if PartDefs.has_filter(type) and filter == &"":
		filter = PartDefs.DEFAULT_FILTER
	var part := Part.new(type, cell, variant % PartDefs.variant_count(type), filter if PartDefs.has_filter(type) else &"")
	parts.append(part)
	for c in part.cells():
		_occupied[c] = part
	changed.emit()
	return part


func set_filter(part: Part, filter: StringName) -> void:
	part.filter = filter
	changed.emit()


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
		var entry := {"type": String(p.type), "x": p.cell.x, "y": p.cell.y, "variant": p.variant}
		if p.filter != &"":
			entry["filter"] = String(p.filter)
		list.append(entry)
	return {"version": 2, "parts": list}


func load_dict(data: Dictionary) -> void:
	parts.clear()
	_occupied.clear()
	for entry in data.get("parts", []):
		var type := StringName(entry.get("type", ""))
		if PartDefs.DEFS.has(type):
			var cell := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
			if can_place(type, cell):
				# Version 1 saves stored a "flipped" flag instead of a variant number.
				var variant := int(entry.get("variant", 1 if entry.get("flipped", false) else 0))
				var filter := StringName(entry.get("filter", ""))
				if PartDefs.has_filter(type) and not ItemDefs.DEFS.has(filter):
					filter = PartDefs.DEFAULT_FILTER
				var part := Part.new(type, cell, variant % PartDefs.variant_count(type), filter)
				parts.append(part)
				for c in part.cells():
					_occupied[c] = part
	changed.emit()
