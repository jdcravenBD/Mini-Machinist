extends SceneTree
## Checks heat: a coil heats the panel floor of a box built over it, the ore resting on that
## floor warms up with it (and melts once hot enough), one coil alone stays below iron's melting point, and a second
## coil, bellows or insulation around the coil push it past. Exits 1 on failure.
## Usage: godot --headless --path . --script res://tests/heat_test.gd

const MELT := 1500.0


func _init() -> void:
	var setups := {
		"one coil": [],
		"two coils": [[&"heating_coil", Vector2i(9, 9)]],
		"coil + bellows": [[&"bellows", Vector2i(9, 9)]],
		"coil + insulation": [[&"insulation", Vector2i(9, 9)], [&"insulation", Vector2i(11, 9)], [&"insulation", Vector2i(10, 10)]],
	}
	var ok := true
	for name in setups:
		var machine := _box()
		for extra in setups[name]:
			machine.place(extra[0], extra[1])
		var sim := PartGeometry.build(machine)
		sim.add_item(&"iron_ore", &"chunk", 0, 336.0, 270.0)
		var hottest_floor := 0.0
		var ore := 0.0
		for i in 3600:
			sim.step()
			hottest_floor = maxf(hottest_floor, sim.heat_at(Vector2(336, 285)))
			# Hot enough, the ore melts away into molten metal.
			if sim.item_count() > 0:
				ore = sim.item(0)["temp"]
		var air := sim.heat_at(Vector2(336, 266))
		var melts := hottest_floor >= MELT
		print("%-18s floor reaches %4d°, ore %4d°, air in the box %4d°%s" % [name, roundi(hottest_floor), roundi(ore), roundi(air), "  (hot enough to melt iron)" if melts else ""])
		if sim.item_count() == 0:
			print("%-18s the ore melted" % "")
		var melted := sim.item_count() == 0
		ok = ok and melts == (name != "one coil") and melted == melts and (melted or ore > hottest_floor * 0.8)
	print("Heat: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


## A box of blocks with a three-panel floor along the bottom of its row, and a heating coil
## right under the middle panel.
func _box() -> Machine:
	var machine := Machine.new()
	for x in range(9, 12):
		machine.place(&"panel", Vector2i(x, 8), 2)
	for y in range(7, 9):
		machine.place(&"block", Vector2i(8, y))
		machine.place(&"block", Vector2i(12, y))
	machine.place(&"heating_coil", Vector2i(10, 9))
	return machine
