extends SceneTree
## Checks melting: ore in a heated box of panels melts into molten iron with slag floating
## on it like oil on water, molten metal never hardens, and a skimmer takes the slag off.
## Exits 1 on failure.
## Usage: godot --headless --path . --script res://tests/smelting_test.gd

const T := PartDefs.TILE


func _init() -> void:
	var ok := _melt()
	ok = _no_hardening() and ok
	ok = _layers() and ok
	ok = _skim() and ok
	print("Smelting: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


## A box of blocks with a three-panel floor along the bottom of row 8 (inside: x 288..384,
## floor at y 282), and whatever goes on the right at (12, 8).
func _box(right_wall: StringName) -> Machine:
	var machine := Machine.new()
	for x in range(9, 12):
		machine.place(&"panel", Vector2i(x, 8), 2)
	machine.place(&"block", Vector2i(8, 7))
	machine.place(&"block", Vector2i(8, 8))
	machine.place(&"block", Vector2i(12, 7))
	machine.place(right_wall, Vector2i(12, 8))
	return machine


## A coil under each of the box's floor panels (heat doesn't travel far along a thin panel).
func _heat(machine: Machine) -> void:
	for x in range(9, 12):
		machine.place(&"heating_coil", Vector2i(x, 9))


## Iron ore dropped into the heated box melts down: no ore left, molten iron at the bottom
## and the lighter slag above it.
func _melt() -> bool:
	var machine := _box(&"block")
	_heat(machine)
	var sim := PartGeometry.build(machine)
	for i in 4:
		sim.add_item(&"iron_ore", &"chunk", i, 310.0 + i * 22.0, 250.0)
	for i in 3600:
		sim.step()
	var px := sim.pixel_counts()
	var ore := sim.item_count()
	print("Melt: %d ore left, iron %d px (avg y %.1f), slag %d px (avg y %.1f)" % [
		ore, px["iron"], px["iron_y"], px["slag"], px["slag_y"]])
	return ore == 0 and px["iron"] > 0 and px["slag"] > 0 and px["slag_y"] < px["iron_y"] and px["iron"] > px["slag"]


## Molten metal left to cool never hardens: poured into a cold box, it still lies flat in a
## pool, and a rock dropped on it floats partly sunk in it instead of resting on a crust.
func _no_hardening() -> bool:
	var sim := PartGeometry.build(_box(&"block"))
	sim.add_liquid(Rect2(288, 266, 96, 16), true, 1600.0)
	for i in 1200:
		sim.step()
	var px := sim.pixel_counts()
	sim.add_item(&"rock", &"chunk", 0, 336.0, 220.0)
	for i in 300:
		sim.step()
	var rock := sim.item(0)
	print("Cooling: %d of 1536 iron still molten after 20 s; a rock dropped on it ends at y %.1f (pool top 266)" % [px["iron"], rock["y"]])
	return px["iron"] == 1536 and rock["y"] > 266.0


## Ore melting in a mix of iron and slag separates like water and oil: in every column of the
## pool, all the slag sits above all the iron.
func _layers() -> bool:
	var machine := _box(&"block")
	_heat(machine)
	var sim := PartGeometry.build(machine)
	for i in 1200:
		sim.step()
	for i in 6:
		sim.add_item(&"iron_ore", &"chunk", i % 4, 300.0 + i * 15.0, 240.0 - (i % 2) * 20.0)
	for i in 1800:
		sim.step()
	var mixed := 0
	var columns := 0
	for x in range(288, 384):
		var seen_iron := false
		var counted := false
		for y in range(240, 282):
			var m: int = sim.world.pixel_at(x, y)
			if m == 2:
				seen_iron = true
			elif m == 3 and seen_iron and not counted:
				mixed += 1
				counted = true
		columns += 1
	var px := sim.pixel_counts()
	print("Layers: %d iron px, %d slag px, %d of %d columns with slag under iron" % [px["iron"], px["slag"], mixed, columns])
	return px["iron"] > 0 and px["slag"] > 0 and mixed == 0


## Hot iron with slag on top, in the heated box whose right wall at the slag's height is a
## skimmer: the slag comes off as lumps out the far side and the iron stays.
func _skim() -> bool:
	var machine := _box(&"skimmer")
	_heat(machine)
	for x in range(13, 16):
		machine.place(&"panel", Vector2i(x, 8), 2)
	var sim := PartGeometry.build(machine)
	# Let the coils heat the box first.
	for i in 1200:
		sim.step()
	sim.add_liquid(Rect2(288, 270, 96, 12), true, 2000.0)
	sim.add_liquid(Rect2(288, 262, 96, 8), false, 2000.0)
	var before := sim.pixel_counts()
	for i in 600:
		sim.step()
	var px := sim.pixel_counts()
	var lumps := 0
	var outside := 0
	for i in sim.item_count():
		var item := sim.item(i)
		if item["kind"] == &"slag":
			lumps += 1
			if item["x"] > 384.0 + T:
				outside += 1
	var iron_kept: int = px["iron"]
	print("Skim: slag %d -> %d px, %d lumps (%d out the far side), iron %d -> %d px" % [
		before["slag"], px["slag"], lumps, outside, before["iron"], iron_kept])
	return px["slag"] < before["slag"] / 10 and lumps >= 15 and outside == lumps and iron_kept == before["iron"]
