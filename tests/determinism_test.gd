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
	# Walls beside the small crusher keep bits from rolling off its outer rollers.
	crushing.place(&"panel", Vector2i(11, 7), 3)
	crushing.place(&"panel", Vector2i(9, 6), 1)
	crushing.place(&"panel", Vector2i(9, 7), 1)
	crushing.place(&"bin", Vector2i(10, 9))
	# Ore dropping into a box of panels over coils: it melts, the slag goes out a skimmer, and
	# what spills over the sides hardens.
	var melting := Machine.new()
	melting.place(&"spawner", Vector2i(10, 4))
	for x in range(9, 12):
		melting.place(&"panel", Vector2i(x, 8), 2)
		melting.place(&"heating_coil", Vector2i(x, 9))
	melting.place(&"bellows", Vector2i(8, 9))
	melting.place(&"block", Vector2i(8, 7))
	melting.place(&"block", Vector2i(8, 8))
	melting.place(&"block", Vector2i(12, 7))
	melting.place(&"skimmer", Vector2i(12, 8))
	for x in range(4, 18):
		melting.place(&"panel", Vector2i(x, 11), 2)

	var same := true
	for entry in [["Demo", demo], ["Crushing line", crushing], ["Melting", melting]]:
		var start := Time.get_ticks_msec()
		var first := _run(entry[1])
		var elapsed := Time.get_ticks_msec() - start
		var second := _run(entry[1])
		var match_: bool = first.snapshot == second.snapshot and first.delivered == second.delivered and first.pixels == second.pixels
		print("%s: %d ticks in %d ms (%.2f ms/tick), %d items on screen, delivered %s, lost %d, metal %s, same both runs: %s" % [
			entry[0], TICKS, elapsed, elapsed / float(TICKS), first.items, first.delivered, first.lost, first.counts, match_])
		same = same and match_
	print("Deterministic: %s" % ("YES" if same else "NO"))
	quit(0 if same else 1)


func _run(machine: Machine) -> Dictionary:
	var sim := PartGeometry.build(machine)
	for i in TICKS:
		sim.step()
	# Every chunk of the pixel layer, so any metal pixel in a different place or at a different
	# temperature shows up.
	var pixels := PackedByteArray()
	var size: int = sim.world.chunk_size()
	var chunks: int = sim.world.chunk_columns() * ceili(Machine.HEIGHT * PartDefs.TILE / float(size))
	for chunk in chunks:
		pixels.append_array(sim.world.chunk_image(chunk))
	var px := sim.pixel_counts()
	var counts := "%d iron, %d slag, %d hardened" % [px["iron"], px["slag"], px["solid_iron"] + px["solid_slag"]]
	return {"snapshot": sim.snapshot(), "delivered": sim.delivered, "items": sim.item_count(), "lost": sim.lost, "pixels": pixels, "counts": counts}
