extends SceneTree
## Checks the crushers. Exits 1 on failure.
## Usage: godot --headless --path . --script res://tests/crusher_test.gd


func _init() -> void:
	var ok := _chain_makes_gravel()
	ok = _bits_fall_through_large() and ok
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
	var caught: Dictionary = sim.bins[0].by_kind
	var gravel := 0
	var other := 0
	for key in caught:
		if String(key).ends_with("gravel"):
			gravel += caught[key]
		else:
			other += caught[key]
	var chunks: int = sim.spawners[0].count
	print("Chain: %d chunks mined -> %d gravel in the bin, %d other, lost %d, %d still in the machine" % [chunks, gravel, other, sim.lost, sim.items.size()])
	# Everything mined is either gravel in the bin or still on its way.
	return other == 0 and sim.lost == 0 and gravel > chunks * 9 * 0.6


## Bits dropped into a large crusher are pushed through it unchanged.
func _bits_fall_through_large() -> bool:
	var machine := Machine.new()
	machine.place(&"large_crusher", Vector2i(10, 5))
	machine.place(&"bin", Vector2i(10, 7))
	var sim := PartGeometry.build(machine)
	# Dropped one at a time, the way a belt or hopper would feed them.
	for i in 600:
		if i % 20 == 0 and i < 120:
			var k := i / 20
			sim.items.append(Item.new(&"rock" if k % 2 else &"iron_ore", 346.0 + k * 2.0, 120.0, k % 4, 1.0, 0.0, &"bit"))
		sim.step()
	var caught: Dictionary = sim.bins[0].by_kind
	var bits: int = caught.get(&"rock bit", 0) + caught.get(&"iron_ore bit", 0)
	print("Bits through large crusher: %s, crushed %d times" % [caught, 0 if sim.crushers[0].held == null else 1])
	return bits == 6


## A chunk is too big for a small crusher: it sits on the rollers and isn't crushed.
func _chunk_clogs_small() -> bool:
	var machine := Machine.new()
	machine.place(&"small_crusher", Vector2i(10, 5))
	var sim := PartGeometry.build(machine)
	var chunk := Item.new(&"iron_ore", 336.0, 140.0)
	sim.items.append(chunk)
	for i in 600:
		sim.step()
	var stuck := sim.items.has(chunk) and chunk.y < 5 * PartDefs.TILE + 4 and sim.crushers[0].held == null
	print("Chunk on small crusher: still on top %s (y %.1f)" % [stuck, chunk.y])
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
		sim.items.append(Item.new(&"rock" if k % 3 == 2 else &"iron_ore", 110.0 + k * 9.0, 440.0, k % 4, 1.0, 0.0, &"bit"))
	for i in 2400:
		sim.step()
	var bits := 0
	var gravel := 0
	var on_belts := 0
	for b in sim.bins:
		for key in b.by_kind:
			if String(key).ends_with(" bit"):
				bits += b.by_kind[key]
			elif String(key).ends_with(" gravel"):
				gravel += b.by_kind[key]
	for it in sim.items:
		if it.size != &"chunk" or it.x > 300:
			on_belts += 1
	var mined: int = sim.spawners[0].count
	print("Direct feed: %d chunks mined -> %d bits; 20 bits -> %d gravel; lost %d; %d pieces left past the belts" % [mined, bits, gravel, sim.lost, on_belts])
	# The last few chunks mined are still riding the belt when the test ends.
	return sim.lost == 0 and gravel == 60 and bits >= (mined - 10) * 3
