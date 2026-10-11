extends SceneTree
## Four spawners filling a walled pit, to measure cost per tick with a few hundred items.
## Usage: godot --headless --path . --script res://tests/stress_test.gd

const TICKS := 3600  # 60 seconds of game time


func _init() -> void:
	var machine := Machine.new()
	for x in range(10, 30):
		machine.place(&"block", Vector2i(x, 20))
	for y in range(8, 20):
		machine.place(&"block", Vector2i(9, y))
		machine.place(&"block", Vector2i(30, y))
	for x in [12, 17, 22, 27]:
		machine.place(&"spawner", Vector2i(x, 2))

	var sim := PartGeometry.build(machine)
	var worst := 0
	var start := Time.get_ticks_usec()
	for i in TICKS:
		var t := Time.get_ticks_usec()
		sim.step()
		worst = maxi(worst, Time.get_ticks_usec() - t)
	var total := Time.get_ticks_usec() - start

	# Stop the rain and let the pile settle.
	sim.spawners.clear()
	for i in 600:
		sim.step()
	var settled_start := Time.get_ticks_usec()
	for i in 60:
		sim.step()
	var settled := (Time.get_ticks_usec() - settled_start) / 1000.0 / 60

	print("Items: %d   Sleeping: %d   Lost: %d" % [sim.items.size(), sim.sleeping_count(), sim.lost])
	print("Average %.2f ms/tick, worst %.2f ms/tick (budget 16.6 ms per frame)" % [total / 1000.0 / TICKS, worst / 1000.0])
	print("After settling 10s: %d of %d asleep, %.2f ms/tick" % [sim.sleeping_count(), sim.items.size(), settled])
	var max_y := 0.0
	for it in sim.items:
		max_y = maxf(max_y, it.y)
	print("Lowest item y: %.1f (pit floor at %d)" % [max_y, 20 * PartDefs.TILE])
	quit()
