class_name PartShapes
## The solid shape each part fills, in pixels from its cell's top-left corner. The pixel art
## draws these shapes and the heat map fills them with the part's material, so what you see
## glowing is exactly what conducts the heat.
##
## Returns {"rects": Array[Rect2], "polygons": Array[PackedVector2Array], "circles": Array}
## where each circle is [center: Vector2, radius: float]. Shapes may reach outside the cell
## (a sorter's roof is in the cell above).

const T := PartDefs.TILE


static func of(p: Part) -> Dictionary:
	var rects: Array[Rect2] = []
	var polygons: Array[PackedVector2Array] = []
	var circles: Array = []
	var size := Vector2(PartDefs.size_of(p.type) * T)
	match p.type:
		&"conveyor":
			rects.append(Rect2(0, 0, T, PartGeometry.CONVEYOR_HEIGHT))
		&"sorter":
			# The conveyor, and the roof over the passage.
			var hood := PartGeometry.SORTER_HOOD
			rects.append(Rect2(0, 0, T, PartGeometry.CONVEYOR_HEIGHT))
			rects.append(Rect2(0, -hood, T, hood - PartGeometry.SORTER_PASSAGE))
		&"ramp":
			if p.variant == 1:
				polygons.append(PackedVector2Array([Vector2(T, 0), Vector2(T, T), Vector2(0, T)]))
			else:
				polygons.append(PackedVector2Array([Vector2(0, 0), Vector2(0, T), Vector2(T, T)]))
		&"hopper":
			var mid := size.x * 0.5
			var gap := PartGeometry.HOPPER_GAP * 0.5
			var wall := 5.0
			polygons.append(PackedVector2Array([Vector2(0, 0), Vector2(wall, 0), Vector2(mid - gap, T), Vector2(mid - gap - wall, T)]))
			polygons.append(PackedVector2Array([Vector2(size.x - wall, 0), Vector2(size.x, 0), Vector2(mid + gap + wall, T), Vector2(mid + gap, T)]))
		&"panel":
			var slab := PartGeometry.panel_rect(p)
			rects.append(Rect2(slab.position - Vector2(p.cell * T), slab.size))
		&"bin":
			var inset := PartGeometry.BIN_INSET
			var wall := 4.0
			rects.append(Rect2(inset - wall * 0.5, 0, wall, T))
			rects.append(Rect2(size.x - inset - wall * 0.5, 0, wall, T))
			rects.append(Rect2(inset - wall * 0.5, T - wall, size.x - inset * 2.0 + wall, wall))
		&"large_crusher":
			circles.append([Vector2(T * 0.5, T * 0.5), PartGeometry.LARGE_ROLLER])
			circles.append([Vector2(T * 1.5, T * 0.5), PartGeometry.LARGE_ROLLER])
		&"small_crusher":
			for row in 2:
				for column in 2:
					circles.append([Vector2(T * (0.25 + column * 0.5), T * (0.25 + row * 0.5)), PartGeometry.SMALL_ROLLER])
		_:
			rects.append(Rect2(Vector2.ZERO, size))
	return {"rects": rects, "polygons": polygons, "circles": circles}
