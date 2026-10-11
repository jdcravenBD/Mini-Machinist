extends SceneTree
## Checks the crushers. Exits 1 on failure.
## Usage: godot --headless --path . --script res://tests/crusher_test.gd


func _init() -> void:
	var ok := _chain_makes_gravel()
	ok = _bits_pass_through_large() and ok
	ok = _chunk_clogs_small() and ok
	ok = _belts_feed_directly() and ok
	print("Crushers: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


## Spawner -> belt -> hopper -> large crusher -> ramp -> small crusher -> bin: only gravel
## arrives. The hopper meters chunks into the crusher's gap so they don't spill over its sides.
func _chain_makes_gravel() -> bool:
	var machine := Machine.new()
	machine.place(&"spawner", Vector2i(5, 0))
	for x in range(3, 10):
		machine.place(&"conveyor", Vector2i(x, 3))
	machine.place(&"hopper", Vector2i(10, 4))
	machine.place(&"large_crusher", Vector2i(10, 5))
	machine.place(&"ramp", Vector2i(11, 6), 1)
	machine.place(&"small_crusher", Vector2i(10, 7))
	# Walls beside the small crusher keep bits from rolling off its outer rollers.
	machine.place(&"panel", Vector2i(11, 7), 3)
	machine.place(&"panel", Vector2i(9, 6), 1)
	machine.place(&"panel", Vector2i(9, 7), 1)
	machine.place(&"bin", Vector2i(10, 9))
	var sim := PartGeometry.build(machine)
	for i in 3600:
		sim.step()
	var caught := sim.bin_counts(0)
	var gravel := 0
	var other := 0
	for key in caught:
		if String(key).ends_with("gravel"):
			gravel += caught[key]
		else:
			other += caught[key]
	var chunks := sim.spawned(0)
	print("Chain: %d chunks mined -> %d gravel in the bin, %d other, lost %d, %d still in the machine" % [chunks, gravel, other, sim.lost, sim.item_count()])
	# Everything mined is either gravel in the bin or still on its way.
	return other == 0 and sim.lost == 0 and gravel > chunks * 9 * 0.6


## Bits dropped into a large crusher are pushed through it unchanged.
func _bits_pass_through_large() -> bool:
	var machine := Machine.new()
	machine.place(&"large_crusher", Vector2i(10, 5))
	machine.place(&"bin", Vector2i(10, 7))
	var sim := PartGeometry.build(machine)
	# Dropped one at a time, the way a belt or hopper would feed them.
	for i in 600:
		if i % 20 == 0 and i < 120:
			var k := i / 20
			sim.add_item(&"rock" if k % 2 else &"iron_ore", &"bit", k % 4, 346.0 + k * 2.0, 120.0)
		sim.step()
	var caught := sim.bin_counts(0)
	var bits: int = caught.get(&"rock bit", 0) + caught.get(&"iron_ore bit", 0)
	print("Bits through large crusher: %s" % caught)
	return bits == 6


## A chunk is too big for a small crusher: it sits on the rollers and isn't crushed.
func _chunk_clogs_small() -> bool:
	var machine := Machine.new()
	machine.place(&"small_crusher", Vector2i(10, 5))
	var sim := PartGeometry.build(machine)
	sim.add_item(&"iron_ore", &"chunk", 0, 336.0, 140.0)
	for i in 600:
		sim.step()
	var stuck: bool = sim.item_count() == 1 and sim.item(0)["size"] == &"chunk" \
			and sim.item(0)["y"] < 5 * PartDefs.TILE + 4 and not sim.crusher_state(0)["held"]
	print("Chunk on small crusher: still on top %s" % stuck)
	return stuck


## A belt in the same row feeding straight into each crusher, no hopper: nothing gets stuck
## at the edge, and everything comes out crushed.
func _belts_feed_directly() -> bool:
	var machine := Machine.new()
	machine.place(&"spawner", Vector2i(5, 3))
	for x in range(3, 10):
		machine.place(&"conveyor", Vector2i(x, 6))
	machine.place(&"large_crusher", Vector2i(10, 6))
	machine.place(&"bin", Vector2i(10, 8))
	for x in range(3, 10):
		machine.place(&"conveyor", Vector2i(x, 14))
	machine.place(&"small_crusher", Vector2i(10, 14))
	machine.place(&"bin", Vector2i(9, 16))
	machine.place(&"panel", Vector2i(11, 16), 3)
	var sim := PartGeometry.build(machine)
	for k in 20:
		sim.add_item(&"rock" if k % 3 == 2 else &"iron_ore", &"bit", k % 4, 110.0 + k * 9.0, 440.0)
	for i in 2400:
		sim.step()
	var bits := 0
	var gravel := 0
	for b in sim.bin_count():
		var caught := sim.bin_counts(b)
		for key in caught:
			if String(key).ends_with(" bit"):
				bits += caught[key]
			elif String(key).ends_with(" gravel"):
				gravel += caught[key]
	var mined := sim.spawned(0)
	print("Direct feed: %d chunks mined -> %d bits; 20 bits -> %d gravel; lost %d" % [mined, bits, gravel, sim.lost])
	# The last few chunks mined are still riding the belt when the test ends.
	return sim.lost == 0 and gravel == 60 and bits >= (mined - 10) * 3
