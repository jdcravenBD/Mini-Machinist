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
## Unit direction from a to b.
var tx: float
var ty: float
var surface_speed: float
## Fraction of sliding speed (relative to the surface) removed per contact substep.
var friction: float


func _init(p_ax: float, p_ay: float, p_bx: float, p_by: float, p_surface_speed := 0.0, p_friction := 0.02) -> void:
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
	surface_speed = p_surface_speed
	friction = p_friction
