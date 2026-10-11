class_name Segment
extends RefCounted
## A static collision line that items bump into from either side.
##
## surface_speed drags touching items along the line's direction (a -> b);
## belts use it, everything else leaves it at 0.

var ax: float
var ay: float
var bx: float
var by: float
var dx: float
var dy: float
var len_sq: float
## Unit direction from a to b, and a unit normal (which side it faces doesn't matter).
var tx: float
var ty: float
var nx: float
var ny: float
var surface_speed: float
## Friction coefficient: how hard it grips what rests on it (about 0.6 slides on a 31° slope).
var friction: float
## An item kind that goes straight through this line (a sorter's grate), or empty.
var passes: StringName


func _init(p_ax: float, p_ay: float, p_bx: float, p_by: float, p_surface_speed := 0.0, p_friction := 0.6, p_passes: StringName = &"") -> void:
	ax = p_ax
	ay = p_ay
	bx = p_bx
	by = p_by
	dx = bx - ax
	dy = by - ay
	len_sq = dx * dx + dy * dy
	var length := sqrt(len_sq)
	tx = dx / length
	ty = dy / length
	nx = ty
	ny = -tx
	surface_speed = p_surface_speed
	friction = p_friction
	passes = p_passes
