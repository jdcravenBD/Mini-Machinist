extends SceneTree
## Checks the crushers. Exits 1 on failure.
## Usage: godot --headless --path . --script res://tests/crusher_test.gd


func _init() -> void:
	var ok := _chain_makes_gravel()
	ok = _bits_fall_through_large() and ok
	ok = _chunk_clogs_small() and ok
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


## Bits dropped into a large crusher fall through its gap untouched.
func _bits_fall_through_large() -> bool:
	var machine := Machine.new()
	machine.place(&"large_crusher", Vector2i(10, 5))
	machine.place(&"bin", Vector2i(10, 7))
	var sim := PartGeometry.build(machine)
	for k in 6:
		sim.items.append(Item.new(&"rock" if k % 2 else &"iron_ore", 340.0 + k * 5.0, 120.0 - k * 12.0, k % 4, 1.0, 0.0, &"bit"))
	for i in 600:
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
