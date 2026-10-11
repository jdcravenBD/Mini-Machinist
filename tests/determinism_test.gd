extends SceneTree
## Runs the demo machine twice and checks both runs end in exactly the same state.
## Usage: godot --headless --path . --script res://tests/determinism_test.gd

const TICKS := 1800  # 30 seconds of game time


func _init() -> void:
	var machine := Machine.new()
	DemoMachine.build(machine)

	var start := Time.get_ticks_msec()
	var first := _run(machine)
	var elapsed := Time.get_ticks_msec() - start
	var second := _run(machine)

	var same: bool = first.snapshot == second.snapshot and first.delivered == second.delivered
	print("Simulated %d ticks in %d ms (%.2f ms/tick)" % [TICKS, elapsed, elapsed / float(TICKS)])
	print("Items on screen: %d   Collected: %s   Lost: %d" % [first.items, first.delivered, first.lost])
	print("Deterministic: %s" % ("YES" if same else "NO"))
	quit(0 if same else 1)


func _run(machine: Machine) -> Dictionary:
	var sim := PartGeometry.build(machine)
	for i in TICKS:
		sim.step()
	return {"snapshot": sim.snapshot(), "delivered": sim.delivered, "items": sim.items.size(), "lost": sim.lost}
