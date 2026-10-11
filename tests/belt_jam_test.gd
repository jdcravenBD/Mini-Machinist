extends SceneTree
## Backs a belt up against a wall, checks the queue isn't squashed, then removes the wall
## and checks everything flows off. Exits 1 on failure.
## Usage: godot --headless --path . --script res://tests/belt_jam_test.gd

## A squashed queue used to reach ~6 px. Items in a pile momentarily press up to ~1.6 px
## into the one on top of them, which is normal.
const MAX_OVERLAP := 2.0


func _init() -> void:
	var machine := Machine.new()
	machine.place(&"spawner", Vector2i(5, 3))
	machine.place(&"spawner", Vector2i(9, 3))
	for x in range(4, 14):
		machine.place(&"conveyor", Vector2i(x, 6))
	machine.place(&"block", Vector2i(14, 5))
	machine.place(&"block", Vector2i(14, 6))

	var sim := PartGeometry.build(machine)
	for i in 1200:
		sim.step()
	var carried := 0
	for i in sim.item_count():
		if sim.item(i)["carried"]:
			carried += 1
	var worst := sim.max_overlap()
	print("Jammed: %d items, %d being carried, worst overlap %.2f px" % [sim.item_count(), carried, worst])

	# Same items, wall removed, spawners off: the whole queue should run off the end.
	machine.remove_at(Vector2i(14, 5))
	machine.remove_at(Vector2i(14, 6))
	var unjammed := PartGeometry.build(machine)
	unjammed.copy_items_from(sim)
	unjammed.clear_spawners()
	for i in 900:
		unjammed.step()
	print("15s after removing the wall: %d items left" % unjammed.item_count())

	var ok := worst < MAX_OVERLAP and unjammed.item_count() == 0
	print("Belt jam: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
