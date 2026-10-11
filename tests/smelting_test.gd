extends SceneTree
## Checks the smelting parts. Exits 1 on failure.
## Usage: godot --headless --path . --script res://tests/smelting_test.gd


func _init() -> void:
	var ok := _heat_setups()
	ok = _smelt_and_pour() and ok
	print("Smelting: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


## One coil alone can't reach the melting point; a coil plus bellows, plus insulation, or a
## second coil can.
func _heat_setups() -> bool:
	var setups := {
		"one coil": [[&"heating_coil", Vector2i(10, 7)]],
		"coil + bellows": [[&"heating_coil", Vector2i(10, 7)], [&"bellows", Vector2i(9, 7)]],
		"coil + insulation x2": [[&"heating_coil", Vector2i(10, 7)], [&"insulation", Vector2i(9, 6)], [&"insulation", Vector2i(12, 6)]],
		"two coils": [[&"heating_coil", Vector2i(10, 7)], [&"heating_coil", Vector2i(11, 7)]],
	}
	var ok := true
	for name in setups:
		var machine := Machine.new()
		machine.place(&"crucible", Vector2i(10, 6))
		for entry in setups[name]:
			machine.place(entry[0], entry[1])
		var sim := PartGeometry.build(machine)
		var hottest := 0.0
		for i in 3600:
			sim.step()
			hottest = maxf(hottest, sim.smelters[0].temperature)
		var melts := hottest >= Smelter.MELT_POINT
		print("Heat, %s: reaches %d°%s" % [name, roundi(hottest), " (melts iron)" if melts else ""])
		ok = ok and melts == (name != "one coil")
	return ok


## Ore chunks into a crucible heated by a coil and bellows, a skimmer over half its mouth and
## a tilter beside it: the slag is skimmed off and the iron pours out as scrap iron lumps.
func _smelt_and_pour() -> bool:
	var machine := Machine.new()
	machine.place(&"crucible", Vector2i(10, 6))
	machine.place(&"heating_coil", Vector2i(10, 7))
	machine.place(&"bellows", Vector2i(9, 7))
	machine.place(&"insulation", Vector2i(11, 7))
	machine.place(&"tilter", Vector2i(9, 6))
	machine.place(&"skimmer", Vector2i(10, 5))
	for x in range(4, 18):
		machine.place(&"panel", Vector2i(x, 10), 0)
	var sim := PartGeometry.build(machine)
	var smelter: Smelter = sim.smelters[0]
	var poured := false
	for i in 3600:
		# Six chunks of iron ore, dropped into the open half of the mouth two seconds apart.
		if i % 120 == 0 and i < 720:
			sim.add_item(&"iron_ore", &"chunk", (i / 120) % 4, 368.0, 150.0)
		sim.step()
		poured = poured or smelter.stream_on
	var counts := {}
	for i in sim.item_count():
		var item := sim.item(i)
		var key := "%s %s" % [item["kind"], item["size"]]
		counts[key] = counts.get(key, 0) + 1
	var iron: int = counts.get("scrap_iron bit", 0)
	var slag: int = counts.get("slag bit", 0)
	print("Smelt: poured %s, left in crucible %.2f iron %.2f slag, items %s" % [poured, smelter.iron, smelter.slag, counts])
	# 6 chunks of ore hold 4.2 iron and 1.8 slag. The tilter only tips once it has a full unit
	# to pour, so the last bit of iron can still be sitting in the crucible, and a chunk that
	# was in the mouth when it tipped gets thrown out unmelted.
	var thrown_out: int = counts.get("iron_ore chunk", 0)
	var iron_total := iron * ItemDefs.amount_of(&"bit") + smelter.iron + thrown_out * Smelter.ORE_IRON
	print("Iron accounted for: %.2f of 4.2" % iron_total)
	return poured and slag >= 4 and smelter.slag < 0.1 and absf(iron_total - 4.2) < 0.4 and smelter.solids.is_empty()
