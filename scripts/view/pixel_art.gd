class_name PixelArt
## Generates the game's pixel-art textures: 32 x 32 pixels per tile for parts, and pixel
## clumps for items. Everything is made from the parts' and items' real shapes, so it lines
## up exactly with what they collide with.
##
## Parts use the development look until real art arrives: the part's color, a darker stroke
## just inside its edge, and its letter in a small pixel font.

const T := PartDefs.TILE
## How much darker a part's inner stroke is, and how thick (in pixels).
const STROKE_SHADE := 0.35
const STROKE := 2.0
## Item clumps: darker edge pixels, and light and dark specks inside.
const ITEM_EDGE_SHADE := 0.4
const ITEM_DARK_SPECK := 0.18

## 5 x 7 pixel glyphs for part letters.
const FONT := {
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	">": ["#....", ".#...", "..#..", "...#.", "..#..", ".#...", "#...."],
	"<": ["....#", "...#.", "..#..", ".#...", "..#..", "...#.", "....#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"x": [".....", ".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
	"C": [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
	"I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"#": [".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#."],
}

static var _cache := {}


## A part's texture and where its top-left corner goes, relative to the part's cell.
## Returns {"texture": ImageTexture, "offset": Vector2}.
static func part(p: Part) -> Dictionary:
	var key := [p.type, p.variant, p.filter]
	if not _cache.has(key):
		_cache[key] = _make_part(p)
	return _cache[key]


## A crusher roller (round, with its letter), centered on (0, 0). Drawn rotated as it spins.
static func roller(radius: float, color: Color, letter: String) -> Dictionary:
	var key := ["roller", radius, color, letter]
	if not _cache.has(key):
		var size := int(ceil(radius * 2.0))
		var art := _Art.new(size, size, -Vector2(size, size) * 0.5)
		art.circles.append([Vector2.ZERO, radius])
		art.color = color
		art.letter = letter
		art.letter_scale = 2 if radius > 10.0 else 1
		art.stroke = STROKE if radius > 10.0 else 1.0
		_cache[key] = art.render()
	return _cache[key]


## An item's pixel clump: every pixel whose center lies inside its collision outline, with
## darker edge pixels and specks. Centered on its center of mass; drawn rotated with it.
## Returns {"texture": ImageTexture, "rect": Rect2 (where the texture goes, around the center)}.
static func item(kind: StringName, size: StringName, shape: int) -> Dictionary:
	var key := ["item", kind, size, shape]
	if _cache.has(key):
		return _cache[key]
	var outline := ItemDefs.outline(kind, size, shape)
	var points := PackedVector2Array()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for i in outline.size() / 2:
		var point := Vector2(outline[i * 2], outline[i * 2 + 1])
		points.append(point)
		low = low.min(point)
		high = high.max(point)
	var origin := low.floor()
	var w := int(ceil(high.x - origin.x))
	var h := int(ceil(high.y - origin.y))
	var filled := []
	for y in h:
		var row := []
		for x in w:
			row.append(Geometry2D.is_point_in_polygon(origin + Vector2(x + 0.5, y + 0.5), points))
		filled.append(row)

	var def: Dictionary = ItemDefs.DEFS[kind]
	var body: Color = def["color"]
	var edge := body.lerp(Color.BLACK, ITEM_EDGE_SHADE)
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			if not filled[y][x]:
				continue
			var color := body
			var on_edge: bool = x == 0 or y == 0 or x == w - 1 or y == h - 1 \
					or not filled[y][x - 1] or not filled[y][x + 1] or not filled[y - 1][x] or not filled[y + 1][x]
			if on_edge:
				color = edge
			else:
				var speck := (x * 7 + y * 13 + shape * 5) % 9
				if speck == 0:
					color = def["fleck"]
				elif speck == 4:
					color = body.lerp(Color.BLACK, ITEM_DARK_SPECK)
			image.set_pixel(x, y, color)
	var result := {"texture": ImageTexture.create_from_image(image), "rect": Rect2(origin, Vector2(w, h))}
	_cache[key] = result
	return result


static func _make_part(p: Part) -> Dictionary:
	var def: Dictionary = PartDefs.DEFS[p.type]
	var size := Vector2(def["size"] * T)
	var art := _Art.new(int(size.x), int(size.y), Vector2.ZERO)
	art.color = def["color"]
	art.letter = def["letter"]
	if p.type == &"large_crusher" or p.type == &"small_crusher":
		# Drawn as rotating rollers instead (see roller()).
		return {"texture": null, "offset": Vector2.ZERO}
	var shapes := PartShapes.of(p)
	art.rects = shapes["rects"]
	art.polygons = shapes["polygons"]
	art.circles = shapes["circles"]
	match p.type:
		&"conveyor":
			art.resize(T, int(PartGeometry.CONVEYOR_HEIGHT), Vector2.ZERO)
			art.letter = "<" if p.variant == 1 else ">"
			art.letter_scale = 1
		&"sorter":
			# A dark mouth on the side the belt comes from, and a dot showing what it drops.
			var hood := PartGeometry.SORTER_HOOD
			var height := PartGeometry.CONVEYOR_HEIGHT + hood
			art.resize(T, int(height), Vector2(0, -hood))
			art.letter_scale = 1
			var mouth_x := 3 if p.variant == 0 else T - 6
			art.patches.append([Rect2(mouth_x, 3 - hood, 3, height - 6), art.color.darkened(0.7)])
			if ItemDefs.DEFS.has(p.filter):
				var dot_x := T - 9 if p.variant == 0 else 5
				art.patches.append([Rect2(dot_x, 4 - hood, 4, 4), ItemDefs.DEFS[p.filter]["color"]])
		&"ramp":
			art.letter_at = Vector2(T * 0.68, T * 0.7) if p.variant == 1 else Vector2(T * 0.32, T * 0.7)
			art.letter_scale = 1
		&"hopper":
			art.stroke = 1.0
			art.letter_at = Vector2(size.x * 0.5, 9)
			art.letter_scale = 1
			art.letter_on_background = true
		&"panel":
			art.stroke = 1.0
			art.letter = ""
		&"bin":
			art.stroke = 1.0
			art.letter_at = Vector2(size.x * 0.5, T * 0.45)
			art.letter_on_background = true
	return art.render()


## A part drawing being put together: filled shapes with an inner stroke, solid color patches
## on top, and a letter.
class _Art:
	var width: int
	var height: int
	var offset: Vector2
	var rects: Array[Rect2] = []
	var polygons: Array[PackedVector2Array] = []
	## [center, radius]
	var circles: Array = []
	## [Rect2, Color] drawn over the shapes as-is.
	var patches: Array = []
	var color := Color.WHITE
	var stroke := PixelArt.STROKE
	var letter := ""
	## Where the letter's center goes; the middle of the drawing by default.
	var letter_at := Vector2(-1, -1)
	var letter_scale := 2
	## The letter sits on empty space (a hopper's or bin's middle) rather than on the part.
	var letter_on_background := false

	func _init(p_width: int, p_height: int, p_offset: Vector2) -> void:
		resize(p_width, p_height, p_offset)

	func resize(p_width: int, p_height: int, p_offset: Vector2) -> void:
		width = p_width
		height = p_height
		offset = p_offset

	func render() -> Dictionary:
		var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
		var dark := color.darkened(PixelArt.STROKE_SHADE)
		for y in height:
			for x in width:
				var depth := _depth(Vector2(x + 0.5, y + 0.5) + offset)
				if depth > 0.0:
					image.set_pixel(x, y, dark if depth <= stroke else color)
		for patch in patches:
			var r: Rect2 = patch[0]
			image.fill_rect(Rect2i(Vector2i(r.position - offset), Vector2i(r.size)), patch[1])
		if letter != "":
			var center := letter_at if letter_at.x >= 0.0 else Vector2(width, height) * 0.5 + offset
			var ink := color if letter_on_background else _letter_color(color)
			_draw_letter(image, center - offset, ink)
		var texture := ImageTexture.create_from_image(image)
		return {"texture": texture, "offset": offset}

	## How far inside the shapes a point is (0 if outside).
	func _depth(point: Vector2) -> float:
		var best := 0.0
		for r in rects:
			if r.has_point(point):
				best = maxf(best, minf(minf(point.x - r.position.x, r.end.x - point.x), minf(point.y - r.position.y, r.end.y - point.y)))
		for poly in polygons:
			if Geometry2D.is_point_in_polygon(point, poly):
				var nearest := INF
				for i in poly.size():
					var closest := Geometry2D.get_closest_point_to_segment(point, poly[i], poly[(i + 1) % poly.size()])
					nearest = minf(nearest, point.distance_to(closest))
				best = maxf(best, nearest)
		for circle in circles:
			best = maxf(best, circle[1] - point.distance_to(circle[0]))
		return best

	func _draw_letter(image: Image, center: Vector2, ink: Color) -> void:
		var glyph: Array = PixelArt.FONT.get(letter, [])
		if glyph.is_empty():
			return
		var s := letter_scale
		var left := int(round(center.x - 5 * s * 0.5))
		var top := int(round(center.y - 7 * s * 0.5))
		for gy in 7:
			for gx in 5:
				if glyph[gy][gx] == "#":
					image.fill_rect(Rect2i(left + gx * s, top + gy * s, s, s), ink)

	## Dark letters on light parts, light letters on dark ones.
	static func _letter_color(base: Color) -> Color:
		return base.darkened(0.6) if base.get_luminance() > 0.4 else base.lightened(0.6)
