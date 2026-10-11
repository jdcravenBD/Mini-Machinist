extends SceneTree
## Drops every chunk shape at several rotations onto a flat floor and checks each one ends
## up asleep, lying on a flat side (its two lowest corners level), not balanced on a point.
## Usage: godot --headless --path . --script res://tests/settle_test.gd

const ROTATIONS := [1.0, 0.0, 0.6, 0.8, 0.0, 1.0, -0.8, 0.6, -1.0, 0.0, 0.8, -0.6]
const MAX_TILT := 0.5  # pixels between the two lowest corners


func _init() -> void:
	var machine := Machine.new()
	for x in range(2, 30):
		machine.place(&"block", Vector2i(x, 10))
	var failures := 0
	var total := 0
	for kind in [&"iron_ore", &"rock"]:
		for shape in ItemDefs.SHAPES.size():
			for r in ROTATIONS.size() / 2:
				var sim := PartGeometry.build(machine)
				sim.add_item(kind, &"chunk", shape, 300.0, 280.0, ROTATIONS[r * 2], ROTATIONS[r * 2 + 1])
				for i in 300:
					sim.step()
				var item := sim.item(0)
				var world: PackedFloat64Array = item["world"]
				# The two lowest corners.
				var low1 := -INF
				var low2 := -INF
				for k in world.size() / 2:
					var y: float = world[k * 2 + 1]
					if y > low1:
						low2 = low1
						low1 = y
					elif y > low2:
						low2 = y
				total += 1
				if not item["sleeping"] or low1 - low2 > MAX_TILT:
					failures += 1
					print("%s shape %d rotation %d: asleep %s, lowest corners %.2f px apart" % [kind, shape, r, item["sleeping"], low1 - low2])
	print("Settle: %d of %d lying flat" % [total - failures, total])
	print("Settle: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
