class_name Item
extends RefCounted
## A loose physical object moving through machines (ore bits, rock, later ingots and plates).
##
## Position and velocity are plain 64-bit floats rather than Vector2 (which is 32-bit and
## may be computed differently per platform). The simulation only ever uses + - * / and
## sqrt on them, which keeps every run bit-for-bit identical.

var kind: StringName
var radius: float
var x: float
var y: float
var vx := 0.0
var vy := 0.0
## Settled items sleep: they stop moving and act as solid obstacles until disturbed.
var sleeping := false
var still_ticks := 0
## Last tick this item touched a moving belt. Items on belts never sleep, so a jammed
## belt always starts moving again once the jam clears.
var belt_tick := -1
## Position at the start of the current substep, used to cap how far one substep can move it.
var step_x := 0.0
var step_y := 0.0
## Position at the start of the current tick, used to tell whether the item has settled.
var prev_x := 0.0
var prev_y := 0.0


func _init(p_kind: StringName, p_radius: float, p_x: float, p_y: float) -> void:
	kind = p_kind
	radius = p_radius
	x = p_x
	y = p_y
	prev_x = p_x
	prev_y = p_y
