# Gotchas

Traps hit while building the game, with what fixed them.

## Godot

- **A script that fails to compile hangs the smoke test.** The test's `_ready` never runs, so
  nothing calls `quit()`. `tools/check.sh` runs Godot under `timeout` and prints the log only at
  the end, so on a timeout run the scene by hand with `--quit-after` to see the error.
- **`godot -s script.gd --check-only` reports autoloads as missing** ("Identifier not found:
  Net"). That is the `-s` mode, not the code; run the smoke test instead.
- **Quitting while sounds play leaks their playbacks**, and `check.sh` fails on the `WARNING`.
  The smoke test stops every sound player, frees the game and waits 10 frames before quitting;
  waiting 3 frames without stopping them still leaked now and then.
- **gdformat lengthens files.** Each call it cannot fit on one line becomes one argument per line,
  which pushed `game.gd` past gdlint's 1000-line limit. Data tables (`Looks.ITEM_PARTS`) keep
  repeated mesh calls short.
- **gdformat writes CRLF on Windows.** Run `sed -i 's/\r$//'` on what it touched (also noted in
  the sibling Sneak project).

## Pathfinding

- **A one-metre grid closes narrow doorways.** Growing the walls by 0.7 m for clearance left no
  open cell in the 3.2 m barn doorway. `Farm.CLEARANCE` is 0.3 m.
- **Toggling the barn's inside clears its walls.** Marking the inside walkable again when the
  lights go out also cleared wall cells it overlapped, so `Farm.set_barn_lit` re-blocks the walls
  afterwards.
- **By day the creature must route through the corn only.** A plain route between two points on
  the corn ring cuts across the farm. `Farm.route(..., corn_only = true)` uses a second grid with
  only corn cells open.

## Lighting

- **Fog greys out the day sky.** With `fog_sky_affect` at its default of 1, even light day fog
  turned the sky white-grey. It now follows the darkness: 0 by day, 1 at night.
