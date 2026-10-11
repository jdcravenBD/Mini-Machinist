class_name DemoMachine
## A small starter layout so there's something to watch on first launch:
## spawner -> hopper -> belt -> ramp -> belt -> bin.


static func build(machine: Machine) -> void:
	machine.clear()
	machine.place(&"spawner", Vector2i(6, 3))
	machine.place(&"hopper", Vector2i(5, 5))
	for x in range(4, 15):
		machine.place(&"conveyor", Vector2i(x, 8))
	machine.place(&"ramp", Vector2i(15, 9))
	for x in range(16, 25):
		machine.place(&"conveyor", Vector2i(x, 10))
	machine.place(&"bin", Vector2i(25, 11))
