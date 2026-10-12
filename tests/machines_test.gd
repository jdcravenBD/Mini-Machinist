extends SceneTree
## Checks the piston: it needs a motor, without a signal it slams down and stays down, with
## one it fires on the timer and crushes ore on the belt under it, more motors (also chained
## through each other) pull it back up faster, every piece it lands on is crushed wherever it
## sits under the plate, and nothing ever ends up inside or above the head.
## Exits 1 on failure.
## Usage: godot --headless --path . --script res://tests/machines_test.gd

const PISTON := Vector2i(7, 4)


func _init() -> void:
	var ok := true
	var one := _run(1, true)
	var two := _run(2, true)
	var held := _run(1, false)
	var unpowered := _run(0, true)
	var chained := _run(1, true, true)
	print("Motor + signal: crushed %d, back up in %d ticks" % [one.crushed, one.retract])
	print("Two motors + signal: crushed %d, back up in %d ticks" % [two.crushed, two.retract])
	print("Motor, no signal: plate at %.1f at the end (stays down), crushed %d" % [held.end_ext, held.crushed])
	print("No motor: plate went %.1f down, crushed %d" % [unpowered.max_ext, unpowered.crushed])
	print("Three chained motors, one touching: back up in %d ticks" % chained.retract)
	print("Something inside the head: %d ticks (two motors), %d (one)" % [two.inside, one.inside])
	ok = ok and one.crushed > 0 and two.crushed > one.crushed and two.retract < one.retract
	ok = ok and held.end_ext > 0.0 and unpowered.max_ext == 0.0 and unpowered.crushed == 0
	ok = ok and chained.retract < two.retract and one.inside == 0 and two.inside == 0
	ok = _every_slam_crushes() and ok
	print("Machines: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


## The demo build: a signal beside the piston, motors touching it, a belt two rows down
## carrying ore under it. Returns how much got crushed (smaller pieces made), how long the
## first return took, and where the plate ended.
func _run(motors: int, with_signal: bool, chained := false) -> Dictionary:
	var m := Machine.new()
	m.place(&"spawner", Vector2i(4, 2))
	for x in range(3, 12):
		m.place(&"conveyor", Vector2i(x, 6))
	m.place(&"piston", PISTON)
	for cell in [Vector2i(7, 3), Vector2i(6, 4)].slice(0, motors):
		m.place(&"small_motor", cell)
	if chained:
		# Two more motors joined to the one on top, touching only it.
		m.place(&"small_motor", Vector2i(7, 2))
		m.place(&"small_motor", Vector2i(8, 2))
	if with_signal:
		m.place(&"signal", Vector2i(8, 4))
	m.place(&"bin", Vector2i(12, 7))
	var sim := PartGeometry.build(m)
	var max_ext := 0.0
	var retract := 0
	var started := -1
	var inside := 0
	for i in 1800:
		sim.step()
		if _inside_head(sim):
			inside += 1
		var ext := sim.piston_extension(PISTON)
		max_ext = maxf(max_ext, ext)
		if started < 0 and ext >= float(PartDefs.TILE) - 0.01:
			started = i
		elif started >= 0 and retract == 0 and ext == 0.0:
			retract = i - started
	var crushed := 0
	var counts := sim.bin_counts(0)
	for key in counts:
		if not String(key).ends_with("chunk"):
			crushed += counts[key]
	for i in sim.item_count():
		if sim.item(i)["size"] != &"chunk":
			crushed += 1
	return {"crushed": crushed, "retract": retract, "max_ext": max_ext, "end_ext": sim.piston_extension(PISTON), "inside": inside}


## A chunk or bit of every shape, resting at offsets right across the plate on a thin panel
## floor: one slam always crushes it (nothing of its size is left under the plate), never
## pushes it through the floor, and never lets anything inside the head.
func _every_slam_crushes() -> bool:
	var fails := 0
	var runs := 0
	for size in [&"chunk", &"bit"]:
		for shape in ItemDefs.SHAPES.size():
			for offset in range(-16, 17, 4):
				var m := Machine.new()
				m.place(&"piston", PISTON)
				m.place(&"small_motor", Vector2i(7, 3))
				for x in range(5, 10):
					m.place(&"panel", Vector2i(x, 6), 0)
				var sim := PartGeometry.build(m)
				sim.add_item(&"iron_ore", size, shape, 240.0 + offset, 180.0)
				var inside := false
				for i in 120:
					sim.step()
					inside = inside or _inside_head(sim)
				var left := 0
				var fell_through := 0
				for k in sim.item_count():
					var it := sim.item(k)
					if it["size"] == size and absf(it["x"] - 240.0) < 14.0:
						left += 1
					if it["y"] > 200.0:
						fell_through += 1
				runs += 1
				if left > 0 or inside or fell_through > 0:
					fails += 1
					print("  %s shape %d offset %d: %d left, %d through the floor, inside head %s" % [size, shape, offset, left, fell_through, inside])
	print("Single slams: %d of %d failed" % [fails, runs])
	return fails == 0


## True if any item's center is inside the piston's head (from inside its body down to the
## plate's bottom).
func _inside_head(sim: Simulation) -> bool:
	var T := PartDefs.TILE
	var x0 := PISTON.x * T + PartGeometry.PISTON_INSET
	var x1 := PISTON.x * T + T - PartGeometry.PISTON_INSET
	var top := (PISTON.y + 1) * T - 6.0
	var plate := (PISTON.y + 1) * T + sim.piston_extension(PISTON)
	for k in sim.item_count():
		var it := sim.item(k)
		if it["x"] > x0 and it["x"] < x1 and it["y"] > top and it["y"] < plate - 0.5:
			return true
	return false
