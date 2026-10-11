class_name Smelter
extends RefCounted
## A crucible and the smelting parts touching it: heating coils (each with the bellows
## touching it), insulation, a skimmer and a tilter.
##
## Liquids aren't simulated as particles: the crucible keeps amounts (a chunk of material
## counts as 1), and a pour is a straight falling stream that hardens into lumps where it
## lands. Runs once per tick after the physics; plain + - * / only, so it's deterministic.

const AMBIENT := 20.0
## Iron ore melts at this temperature; below FREEZE_POINT molten iron hardens again.
const MELT_POINT := 1500.0
const FREEZE_POINT := 1400.0
## Where a crucible's temperature settles per unit of heat (one coil) with no insulation:
## one coil alone stops short of the melting point.
const DEGREES_PER_HEAT := 1080.0
## Ticks for the temperature to close most of the gap to where it's heading.
const HEAT_TICKS := 360.0
## Each insulation piece cuts heat loss by this share, so the same heat climbs higher.
const INSULATION_CUT := 0.25
## A pumping bellows adds this much heat to the coil it touches. Bellows pump for the first
## half of every cycle.
const BELLOWS_HEAT := 1.0
const BELLOWS_CYCLE := 120
## Most material a crucible holds (a chunk counts as 1).
const CAPACITY := 3.0
## Seconds for one piece to melt right at the melting point; hotter melts faster.
const MELT_SECONDS := {&"chunk": 6.0, &"bit": 3.0, &"gravel": 1.5}
## Share of iron ore that becomes iron; the rest is slag.
const ORE_IRON := 0.7
## Per second.
const POUR_RATE := 1.0
const SKIM_RATE := 0.5
const FREEZE_RATE := 0.3
const TILT_TICKS := 30
## How hard a tipping crucible throws out what was sitting in its mouth.
const THROW_SPEED := 140.0
## A tipped crucible pivots on its bottom corner on the pouring side by TILT_ANGLE radians
## (about 63°). Its lip then sits LIP_OUT pixels out past that corner and LIP_UP above it
## (32·sin and 32·cos of the angle, written out so no trig runs in the simulation).
const TILT_ANGLE := 1.1
const LIP_OUT := 28.52
const LIP_UP := 14.51
## Poured and skimmed material comes out as lumps of this size.
const LUMP_SIZE := &"bit"

## The crucible's top-left corner and width, in pixels.
var x0: float
var y0: float
var width: float
var intake: int
## The crucible's cup walls, switched off while it's tipped.
var walls := -1
## One entry per heating coil touching the crucible: how many bellows touch that coil.
var coils: Array[int] = []
var insulation := 0
var has_skimmer := false
## Where skimmed slag comes out (just outside the skimmer's far side), and which way.
var skim_x := 0.0
var skim_y := 0.0
var skim_dir := 1.0
## +1 pours out the right side, -1 the left, 0 if there's no tilter.
var pour_dir := 0

var temperature := AMBIENT
## Unmelted pieces: {"kind", "size", "left"} with left going from 1 to 0 as it melts.
var solids: Array[Dictionary] = []
## Molten amounts.
var iron := 0.0
var slag := 0.0
## 0 upright, 1 fully tipped.
var tilt := 0.0
var pouring := false
## The falling stream while pouring, for drawing: from (stream_x, stream_top) down to stream_y.
var stream_on := false
var stream_x := 0.0
var stream_top := 0.0
var stream_y := 0.0

var _pour_iron := 0.0
var _pour_slag := 0.0
var _skimmed := 0.0
var _frozen_iron := 0.0
var _frozen_slag := 0.0
var _lumps := 0


func _init(p_x0: float, p_y0: float, p_width: float, p_intake: int) -> void:
	x0 = p_x0
	y0 = p_y0
	width = p_width
	intake = p_intake


func solid_amount() -> float:
	var total := 0.0
	for piece in solids:
		total += ItemDefs.amount_of(piece["size"]) * piece["left"]
	return total


static func is_pumping(tick: int) -> bool:
	return tick % BELLOWS_CYCLE < BELLOWS_CYCLE / 2


func step(sim: Simulation) -> void:
	_heat(sim.tick)
	for type in sim.world.take_intake(intake):
		var info := Simulation.type_info(type)
		solids.append({"kind": info[0], "size": info[1], "left": 1.0})
	if temperature >= MELT_POINT:
		_melt()
	elif temperature < FREEZE_POINT:
		_freeze()
	if has_skimmer and tilt == 0.0 and temperature >= MELT_POINT:
		_skim(sim)
	_tilt_and_pour(sim)
	sim.world.set_intake_open(intake, tilt == 0.0 and solid_amount() + iron + slag < CAPACITY)


## The temperature eases toward where this setup settles: coils (doubled by pumping bellows)
## push it up, the crucible loses heat to the air, and insulation slows that loss.
func _heat(tick: int) -> void:
	var heat := 0.0
	for bellows in coils:
		heat += 1.0 + (BELLOWS_HEAT * bellows if is_pumping(tick) else 0.0)
	var loss := maxf(0.25, 1.0 - INSULATION_CUT * insulation)
	var target := AMBIENT + heat * DEGREES_PER_HEAT / loss
	temperature += (target - temperature) / HEAT_TICKS


func _melt() -> void:
	var speed := 1.0 + (temperature - MELT_POINT) / 250.0
	var kept: Array[Dictionary] = []
	for piece in solids:
		piece["left"] -= speed / (MELT_SECONDS[piece["size"]] * Simulation.TICK_RATE)
		if piece["left"] > 0.0:
			kept.append(piece)
			continue
		var amount := ItemDefs.amount_of(piece["size"])
		match piece["kind"]:
			&"iron_ore":
				iron += amount * ORE_IRON
				slag += amount * (1.0 - ORE_IRON)
			&"scrap_iron":
				iron += amount
			_:
				slag += amount
	solids = kept


## Too cold: whatever's molten slowly hardens back into solid lumps inside the crucible.
func _freeze() -> void:
	var rate := FREEZE_RATE / Simulation.TICK_RATE
	var lump := ItemDefs.amount_of(LUMP_SIZE)
	var take := minf(iron, rate)
	iron -= take
	_frozen_iron += take
	if _frozen_iron >= lump:
		_frozen_iron -= lump
		solids.append({"kind": &"scrap_iron", "size": LUMP_SIZE, "left": 1.0})
	take = minf(slag, rate)
	slag -= take
	_frozen_slag += take
	if _frozen_slag >= lump:
		_frozen_slag -= lump
		solids.append({"kind": &"slag", "size": LUMP_SIZE, "left": 1.0})


## The skimmer scrapes molten slag off the top and drops it out its far side.
func _skim(sim: Simulation) -> void:
	var take := minf(slag, SKIM_RATE / Simulation.TICK_RATE)
	slag -= take
	_skimmed += take
	if _skimmed >= ItemDefs.amount_of(LUMP_SIZE):
		_skimmed -= ItemDefs.amount_of(LUMP_SIZE)
		var type := Simulation.type_id(&"slag", LUMP_SIZE, _next_shape())
		var radius: float = sim.world.type_radius(type)
		sim.world.add_item(type, skim_x + skim_dir * (radius + 0.5), skim_y, 1.0, 0.0, skim_dir * 20.0, 0.0)


## Once everything has melted, the tilter tips the crucible and pours it out the far side,
## slag first (it floats on the iron), then rights it again when it's empty.
func _tilt_and_pour(sim: Simulation) -> void:
	stream_on = false
	if pour_dir == 0:
		return
	if not pouring and tilt == 0.0 and solids.is_empty() and iron + slag >= 1.0 and temperature >= MELT_POINT:
		pouring = true
		# Tipping dumps whatever was sitting in the mouth out over the lip.
		sim.world.set_group_enabled(walls, false)
		sim.world.push_items(x0, y0 - PartDefs.TILE * 0.5, x0 + width, y0 + PartDefs.TILE, pour_dir * THROW_SPEED, -THROW_SPEED * 0.5)
	if not pouring:
		tilt = maxf(0.0, tilt - 1.0 / TILT_TICKS)
		if tilt == 0.0:
			sim.world.set_group_enabled(walls, true)
		return
	tilt = minf(1.0, tilt + 1.0 / TILT_TICKS)
	if tilt < 1.0:
		return

	var pour := POUR_RATE / Simulation.TICK_RATE
	var from_slag := minf(slag, pour)
	slag -= from_slag
	_pour_slag += from_slag
	var from_iron := minf(iron, pour - from_slag)
	iron -= from_iron
	_pour_iron += from_iron

	stream_on = true
	stream_x = x0 + width + LIP_OUT if pour_dir > 0 else x0 - LIP_OUT
	stream_top = y0 + PartDefs.TILE - LIP_UP
	stream_y = sim.world.raycast_down(stream_x, stream_top, Machine.HEIGHT * PartDefs.TILE + 64.0)
	var lump := ItemDefs.amount_of(LUMP_SIZE)
	while _pour_slag >= lump:
		_pour_slag -= lump
		_drop_lump(sim, &"slag")
	while _pour_iron >= lump:
		_pour_iron -= lump
		_drop_lump(sim, &"scrap_iron")
	if iron + slag < 0.001:
		pouring = false
		iron = 0.0
		slag = 0.0


## Molten material landing where the stream hits, hardening into a lump.
func _drop_lump(sim: Simulation, kind: StringName) -> void:
	var type := Simulation.type_id(kind, LUMP_SIZE, _next_shape())
	var radius: float = sim.world.type_radius(type)
	var y := maxf(stream_top + radius, stream_y - radius - 0.5)
	sim.world.add_item(type, stream_x + float(_lumps % 3 - 1), y, 1.0, 0.0, 0.0, 0.0)


func _next_shape() -> int:
	_lumps += 1
	return _lumps % ItemDefs.SHAPES.size()
