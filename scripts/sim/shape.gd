class_name Shape
## Geometry helpers for convex outlines stored as flat x, y pairs going clockwise on screen
## (y points down). Edge i runs from vertex i to i + 1; its outward normal is (ey, -ex).
## Only + - * / and sqrt, so results are identical on every machine.


## Area of the outline.
static func area(p: PackedFloat64Array) -> float:
	var total := 0.0
	var n := p.size() / 2
	for i in n:
		var j := (i + 1) % n
		total += p[i * 2] * p[j * 2 + 1] - p[i * 2 + 1] * p[j * 2]
	return total * 0.5


## The outline shifted so its center of mass sits at (0, 0).
static func recentered(p: PackedFloat64Array) -> PackedFloat64Array:
	var n := p.size() / 2
	var cx := 0.0
	var cy := 0.0
	var a := 0.0
	for i in n:
		var j := (i + 1) % n
		var cross := p[i * 2] * p[j * 2 + 1] - p[i * 2 + 1] * p[j * 2]
		a += cross
		cx += (p[i * 2] + p[j * 2]) * cross
		cy += (p[i * 2 + 1] + p[j * 2 + 1]) * cross
	cx /= 3.0 * a
	cy /= 3.0 * a
	var out := PackedFloat64Array()
	for i in n:
		out.append(p[i * 2] - cx)
		out.append(p[i * 2 + 1] - cy)
	return out


## Rotational inertia about (0, 0) for a density of 1. Expects a recentered outline.
static func inertia(p: PackedFloat64Array) -> float:
	var total := 0.0
	var n := p.size() / 2
	for i in n:
		var j := (i + 1) % n
		var ax := p[i * 2]
		var ay := p[i * 2 + 1]
		var bx := p[j * 2]
		var by := p[j * 2 + 1]
		var cross := ax * by - ay * bx
		total += cross * (ax * ax + ax * bx + bx * bx + ay * ay + ay * by + by * by)
	return total / 12.0


## Distance from (0, 0) to the farthest vertex.
static func bounding_radius(p: PackedFloat64Array) -> float:
	var best := 0.0
	for i in p.size() / 2:
		best = maxf(best, p[i * 2] * p[i * 2] + p[i * 2 + 1] * p[i * 2 + 1])
	return sqrt(best)


## Outward unit normal of every edge, as flat x, y pairs.
static func normals(p: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var n := p.size() / 2
	for i in n:
		var j := (i + 1) % n
		var ex := p[j * 2] - p[i * 2]
		var ey := p[j * 2 + 1] - p[i * 2 + 1]
		var length := sqrt(ex * ex + ey * ey)
		out.append(ey / length)
		out.append(-ex / length)
	return out
