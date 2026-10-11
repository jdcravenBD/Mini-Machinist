class_name Item
extends RefCounted
## A loose physical object moving through machines (ore chunks, rock, later ingots and plates).
## It's a rigid convex polygon: it slides, tips over, rolls off edges and settles on a side.
##
## Everything is plain 64-bit floats rather than Vector2 (32-bit, and possibly computed
## differently per platform). The simulation only uses + - * / and sqrt on them, which
## keeps every run bit-for-bit identical. Rotation is kept as a unit vector (c, s) = the
## cosine and sine of the angle, so turning never needs trig either.

const DENSITY := 1.0

## Material (ItemDefs.DEFS key) and size (ItemDefs.SIZES key).
var kind: StringName
var size: StringName
## Which outline from ItemDefs.SHAPES this item uses.
var shape: int
## Outline around the center of mass, flat x, y pairs, and its edge normals.
var local: PackedFloat64Array
var local_normals: PackedFloat64Array
var count: int
## Distance from the center to the farthest corner.
var radius: float
var inv_mass: float
var inv_inertia: float

var x: float
var y: float
var c := 1.0
var s := 0.0
var vx := 0.0
var vy := 0.0
## Angular velocity in radians per second (positive turns clockwise on screen).
var w := 0.0

## Outline and normals in world space, refreshed each substep before collision checks.
var world := PackedFloat64Array()
var world_normals := PackedFloat64Array()

## Settled items sleep: they stop moving and act as solid obstacles until disturbed.
var sleeping := false
var still_ticks := 0
## Pose when the item last started holding still. It sleeps once it has stayed close to
## this pose long enough, so rocking back and forth in place still counts as settled.
var still_x := 0.0
var still_y := 0.0
var still_c := 1.0
var still_s := 0.0
## Last tick a moving item came within reach of this one while it slept. Only those
## sleepers need to re-check that something still holds them up.
var near_tick := -10
## Last tick this item was carried: touching a moving belt, or resting on something carried.
## Carried items never sleep, so a backed-up belt keeps working on everything piled on it.
var carried_tick := -10
## Pose at the start of the current substep (to cap movement and derive velocity) and at
## the start of the current tick (to tell whether it has settled).
var step_x := 0.0
var step_y := 0.0
var step_c := 1.0
var step_s := 0.0
var prev_x := 0.0
var prev_y := 0.0
var prev_c := 1.0
var prev_s := 0.0
## Pushes this item got from neighbours and walls this substep, summed per direction
## (all >= 0). A belt won't shove an item against a push holding it back; it slips instead.
## Kept per direction so a push from behind can't cancel out the one holding it back.
var push_right := 0.0
var push_left := 0.0
var push_down := 0.0
var push_up := 0.0


## `p_c`/`p_s` give the starting rotation; they must form a unit vector.
func _init(p_kind: StringName, p_x: float, p_y: float, p_shape := 0, p_c := 1.0, p_s := 0.0, p_size: StringName = &"chunk") -> void:
	kind = p_kind
	size = p_size
	shape = p_shape
	local = ItemDefs.outline(p_kind, p_size, p_shape)
	local_normals = Shape.normals(local)
	count = local.size() / 2
	radius = Shape.bounding_radius(local)
	inv_mass = 1.0 / (Shape.area(local) * DENSITY)
	inv_inertia = 1.0 / (Shape.inertia(local) * DENSITY)
	world.resize(local.size())
	world_normals.resize(local.size())
	x = p_x
	y = p_y
	c = p_c
	s = p_s
	step_x = x
	step_y = y
	step_c = c
	step_s = s
	prev_x = x
	prev_y = y
	prev_c = c
	prev_s = s
	update_world()


func update_world() -> void:
	for i in count:
		var lx := local[i * 2]
		var ly := local[i * 2 + 1]
		world[i * 2] = x + c * lx - s * ly
		world[i * 2 + 1] = y + s * lx + c * ly
		var nx := local_normals[i * 2]
		var ny := local_normals[i * 2 + 1]
		world_normals[i * 2] = c * nx - s * ny
		world_normals[i * 2 + 1] = s * nx + c * ny


## Turns by a small angle (radians), staying a unit vector without using trig.
func turn(angle: float) -> void:
	var nc := c - s * angle
	var ns := s + c * angle
	var length := sqrt(nc * nc + ns * ns)
	c = nc / length
	s = ns / length
