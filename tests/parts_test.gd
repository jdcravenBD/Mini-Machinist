extends SceneTree
## Checks the sorter and panels do their jobs. Exits 1 on failure.
## Usage: godot --headless --path . --script res://tests/parts_test.gd


func _init() -> void:
	var ok := _sorter_splits()
	ok = _sorters_in_a_row() and ok
	ok = _panel_basin_holds() and ok
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
	for b in sim.bin_count():
		if sim.bin_rect(b).position.x < 11 * PartDefs.TILE:
			under = sim.bin_counts(b)
		else:
			end = sim.bin_counts(b)
	print("Sorter: under it %s, at the end %s, lost %d" % [under, end, sim.lost])
	return under.get(&"iron_ore chunk", 0) == 0 and end.get(&"rock chunk", 0) == 0 \
		and under.get(&"rock chunk", 0) > 5 and end.get(&"iron_ore chunk", 0) > 10 and sim.lost == 0


## Three sorters back to back (rock, iron ore, slag): rock and ore drop out of the first two,
## nothing snags at the seams, and nothing is left on the line once the spawner stops.
func _sorters_in_a_row() -> bool:
	var machine := Machine.new()
	machine.place(&"spawner", Vector2i(5, 3))
	for x in range(3, 10):
		machine.place(&"conveyor", Vector2i(x, 6))
	machine.place(&"sorter", Vector2i(10, 6), 0, &"rock")
	machine.place(&"sorter", Vector2i(11, 6), 0, &"iron_ore")
	machine.place(&"sorter", Vector2i(12, 6), 0, &"slag")
	for x in range(13, 16):
		machine.place(&"conveyor", Vector2i(x, 6))
	machine.place(&"bin", Vector2i(10, 8))
	machine.place(&"bin", Vector2i(12, 8))
	machine.place(&"bin", Vector2i(16, 7))
	var sim := PartGeometry.build(machine)
	for i in 1800:
		sim.step()
	var mined := sim.spawned(0)
	sim.clear_spawners()
	for i in 600:
		sim.step()
	var dropped := {}
	var past_the_end := {}
	for b in sim.bin_count():
		var counts := sim.bin_counts(b)
		var into := past_the_end if sim.bin_rect(b).position.x > 15 * PartDefs.TILE else dropped
		for key in counts:
			into[key] = into.get(key, 0) + counts[key]
	print("Sorters in a row: %d mined, dropped %s, past the end %s, %d still on the line, lost %d" % [mined, dropped, past_the_end, sim.item_count(), sim.lost])
	return past_the_end.is_empty() and sim.item_count() == 0 and sim.lost == 0 		and dropped.get(&"rock chunk", 0) + dropped.get(&"iron_ore chunk", 0) == mined


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
	for i in sim.item_count():
		lowest = maxf(lowest, sim.item(i)["y"])
	print("Panel basin: %d items held, lost %d, lowest at y %.1f (floor top at %d)" % [sim.item_count(), sim.lost, lowest, 12 * PartDefs.TILE])
	return sim.lost == 0 and sim.item_count() > 30 and lowest < 12 * PartDefs.TILE
