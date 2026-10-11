class_name Item
extends RefCounted
## A loose physical object moving through machines (ore bits, rock, later ingots and plates).
##
## Position and velocity are plain 64-bit floats rather than Vector2 (which is 32-bit and
## may be computed differently per platform). The simulation only ever uses + - * / and
## sqrt on them, which keeps every run bit-for-bit identical.

var kind: StringName
var radius: float
## Which outline from ItemDefs.SHAPES to draw.
var shape: int
var x: float
var y: float
var vx := 0.0
var vy := 0.0
## Rotation, for drawing only: the physics treats items as round, so turning never
## changes where anything goes. Spin comes from rolling and from belts dragging the item.
var angle := 0.0
var spin := 0.0
## Settled items sleep: they stop moving and act as solid obstacles until disturbed.
var sleeping := false
var still_ticks := 0
## Last tick this item was carried: touching a moving belt, or resting on something carried.
## Carried items never sleep, so a backed-up belt keeps working on everything piled on it.
var carried_tick := -10
## Position at the start of the current substep, used to cap how far one substep can move it.
var step_x := 0.0
var step_y := 0.0
## Pushes this item got from neighbours and walls this substep, summed per direction
## (all >= 0). A belt won't shove an item against a push holding it back; it slips instead.
## Kept per direction so a push from behind can't cancel out the one holding it back.
var push_right := 0.0
var push_left := 0.0
var push_down := 0.0
var push_up := 0.0
## Position at the start of the current tick, used to tell whether the item has settled.
var prev_x := 0.0
var prev_y := 0.0


func _init(p_kind: StringName, p_x: float, p_y: float, p_shape := 0) -> void:
	kind = p_kind
	radius = ItemDefs.radius_of(p_kind)
	shape = p_shape
	x = p_x
	y = p_y
	prev_x = p_x
	prev_y = p_y
