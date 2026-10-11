extends SceneTree
## Checks the sorter and panels do their jobs. Exits 1 on failure.
## Usage: godot --headless --path . --script res://tests/parts_test.gd


func _init() -> void:
	var ok := _sorter_splits() and _panel_basin_holds()
	print("Parts: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


## Spawner -> belt -> rock sorter -> belt -> bin. Rock should drop into the bin under the
## sorter; ore should ride on to the bin at the end.
func _sorter_splits() -> bool:
	var machine := Machine.new()
	machine.place(&"spawner", Vector2i(5, 3))
	for x in range(3, 10):
		machine.place(&"conveyor", Vector2i(x, 6))
	machine.place(&"sorter", Vector2i(10, 6), 0, &"rock")
	for x in range(11, 16):
		machine.place(&"conveyor", Vector2i(x, 6))
	machine.place(&"bin", Vector2i(10, 8))
	machine.place(&"bin", Vector2i(16, 7))
	var sim := PartGeometry.build(machine)
	for i in 2400:
		sim.step()
	# Bins are listed top to bottom, so tell them apart by where they sit.
	var under: Dictionary = {}
	var end: Dictionary = {}
	for b in sim.bins:
		if b.min_x < 11 * PartDefs.TILE:
			under = b.by_kind
		else:
			end = b.by_kind
	print("Sorter: under it %s, at the end %s, lost %d" % [under, end, sim.lost])
	return under.get(&"iron_ore chunk", 0) == 0 and end.get(&"rock chunk", 0) == 0 \
		and under.get(&"rock chunk", 0) > 5 and end.get(&"iron_ore chunk", 0) > 10 and sim.lost == 0


## A basin made only of panels (floor plus two walls) should hold everything poured in.
func _panel_basin_holds() -> bool:
	var machine := Machine.new()
	for x in range(20, 26):
		machine.place(&"panel", Vector2i(x, 12), 0)
	for y in range(9, 12):
		machine.place(&"panel", Vector2i(20, y), 3)
		machine.place(&"panel", Vector2i(25, y), 1)
	machine.place(&"spawner", Vector2i(22, 5))
	var sim := PartGeometry.build(machine)
	for i in 1800:
		sim.step()
	var lowest := 0.0
	for it in sim.items:
		lowest = maxf(lowest, it.y)
	print("Panel basin: %d items held, lost %d, lowest at y %.1f (floor top at %d)" % [sim.items.size(), sim.lost, lowest, 12 * PartDefs.TILE])
	return sim.lost == 0 and sim.items.size() > 30 and lowest < 12 * PartDefs.TILE
