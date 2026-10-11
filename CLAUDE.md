# Mini Machinist

Side-view 2D machine-building game in Godot 4.7.2 (GDScript, GL Compatibility renderer).

## Layout
- `scripts/sim/` — deterministic item physics (`Simulation`, `Item`, `Segment`). No Nodes; pure RefCounted so it runs headless.
- `scripts/machine/` — the player's build (`Machine`, `Part`), part catalog (`PartDefs`), part -> collision shapes (`PartGeometry`), starter layout (`DemoMachine`).
- `scripts/view/world_view.gd` — all drawing. Placeholder shapes at final sizes; swap in art per part here.
- `scripts/ui/hud.gd` — toolbar and labels, built in code.
- `scripts/main.gd` — input, edit/play modes, camera, autosave to `user://machine.json`.

## Determinism rules (the simulation must give identical results every run)
- Advance only via `Simulation.step()` (fixed 60 Hz tick, fixed substeps).
- Iterate in fixed order; never let Dictionary key order affect physics.
- Item math uses plain 64-bit floats with only + - * / and sqrt. No Vector2, trig or randomness in `scripts/sim/`.

## Tests
Godot console binary: `C:/Users/Joe/Desktop/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`
```
godot --headless --path . --import                                  # first time / after adding class_name scripts
godot --headless --path . --script res://tests/determinism_test.gd  # must print "Deterministic: YES"
godot --headless --path . --script res://tests/stress_test.gd       # perf with ~480 items
```
