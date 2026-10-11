extends SceneTree
## Backs a belt up against a wall, checks the queue isn't squashed, then removes the wall
## and checks everything flows off. Exits 1 on failure.
## Usage: godot --headless --path . --script res://tests/belt_jam_test.gd

const MAX_OVERLAP := 1.5


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
	var worst := 0.0
	for a in sim.items:
		if a.carried_tick >= sim.tick - 2:
			carried += 1
		for b in sim.items:
			if a != b:
				var d := sqrt((a.x - b.x) ** 2 + (a.y - b.y) ** 2)
				worst = maxf(worst, a.radius + b.radius - d)
	print("Jammed: %d items, %d being carried, worst overlap %.2f px" % [sim.items.size(), carried, worst])

	# Same items, wall removed, spawners off: the whole queue should run off the end.
	machine.remove_at(Vector2i(14, 5))
	machine.remove_at(Vector2i(14, 6))
	var unjammed := PartGeometry.build(machine)
	unjammed.items = sim.items
	unjammed.tick = sim.tick
	unjammed.spawners.clear()
	for i in 900:
		unjammed.step()
	print("15s after removing the wall: %d items left" % unjammed.items.size())

	var ok := worst < MAX_OVERLAP and unjammed.items.is_empty()
	print("Belt jam: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
