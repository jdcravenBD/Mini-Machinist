extends SceneTree
## Runs each test machine twice and checks both runs end in exactly the same state.
## Usage: godot --headless --path . --script res://tests/determinism_test.gd

const TICKS := 1800  # 30 seconds of game time


func _init() -> void:
	var demo := Machine.new()
	DemoMachine.build(demo)
	var crushing := Machine.new()
	crushing.place(&"spawner", Vector2i(5, 0))
	for x in range(3, 10):
		crushing.place(&"conveyor", Vector2i(x, 3))
	crushing.place(&"hopper", Vector2i(10, 4))
	crushing.place(&"large_crusher", Vector2i(10, 5))
	crushing.place(&"ramp", Vector2i(11, 6), 1)
	crushing.place(&"small_crusher", Vector2i(10, 7))
	crushing.place(&"bin", Vector2i(10, 9))

	var same := true
	for entry in [["Demo", demo], ["Crushing line", crushing]]:
		var start := Time.get_ticks_msec()
		var first := _run(entry[1])
		var elapsed := Time.get_ticks_msec() - start
		var second := _run(entry[1])
		var match_: bool = first.snapshot == second.snapshot and first.delivered == second.delivered
		print("%s: %d ticks in %d ms (%.2f ms/tick), %d items on screen, delivered %s, lost %d, same both runs: %s" % [
			entry[0], TICKS, elapsed, elapsed / float(TICKS), first.items, first.delivered, first.lost, match_])
		same = same and match_
	print("Deterministic: %s" % ("YES" if same else "NO"))
	quit(0 if same else 1)


func _run(machine: Machine) -> Dictionary:
	var sim := PartGeometry.build(machine)
	for i in TICKS:
		sim.step()
	return {"snapshot": sim.snapshot(), "delivered": sim.delivered, "items": sim.items.size(), "lost": sim.lost}
