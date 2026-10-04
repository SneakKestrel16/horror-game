# Gotchas

Traps hit while building the game, with what fixed them.

## Godot

- **A script that fails to compile hangs the smoke test.** The test's `_ready` never runs, so
  nothing calls `quit()`. `tools/check.sh` runs Godot under `timeout` and prints the log only at
  the end, so on a timeout run the scene by hand with `--quit-after` to see the error.
- **`godot -s script.gd --check-only` reports autoloads as missing** ("Identifier not found:
  Net"). That is the `-s` mode, not the code; run the smoke test instead. It does find a parse
  error in a class with no autoloads, such as `farm.gd`.
- **One parse error shows up as dozens of "Could not resolve class".** Every script using the
  broken class reports it, and the real error is not among them. A static var and a function
  with the same name (`_corn`) did it; `--check-only -s` on the broken script names the cause.
- **The corn map is static,** shared by everything that asks `Farm.in_corn`. Each new `Farm`
  regrows it, and cutting planted corn changes it, so a test that cuts corn changes the map for
  the rest of the run.
- **Quitting while sounds play leaks their playbacks**, and `check.sh` fails on the `WARNING`.
  The smoke test stops every sound player, frees the game and waits 10 frames before quitting;
  waiting 3 frames without stopping them still leaked now and then.
- **The VoiceChat autoload's microphone player leaks if it is playing at quit.** The smoke test
  stops every sound player in the whole tree, not just the game scene, before quitting.
- **gdlint allows 20 public methods a class.** `game.gd` passed it in Phase 2, so the farm work
  moved to `chores.gd` and the dev-only helpers to `dev.gd`. Split by job when it trips, rather
  than raising the limit.
- **gdformat lengthens files.** Each call it cannot fit on one line becomes one argument per line,
  which pushed `game.gd` past gdlint's 1000-line limit. Data tables (`Looks.ITEM_PARTS`) keep
  repeated mesh calls short.
- **gdformat writes CRLF on Windows.** Run `sed -i 's/\r$//'` on what it touched (also noted in
  the sibling Sneak project).

## Gameplay

- **A creature that just killed retreats for 25 s and ignores everything**, including a player
  trapped and alone by day. A test that sets up a scene right after a kill must put the creature
  back first (`Creature.place`), or it fails at random.
- **Setting traps in planned order took longer than the night.** Spots spread round the whole
  ring, so walking them in order (and back to the shed for each bear trap) left traps unset after
  200 s. The creature now takes every bear trap it needs in one shed visit and sets the nearest
  spot next. A spot jammed against a wall could never be reached exactly and stalled it for good,
  so an errand gives up after 40 s and does the job where it stands (`ERRAND_GIVE_UP`).
- **The last living player dying ends the night, or the day.** By day too: alone, a day death
  skips to the next morning, and on the last day it ends the run. Tests that kill the only
  player must expect that.

## Tooling

- **Non-ASCII text piped into Python through a Bash heredoc gets mangled.** A `·` in a pattern
  stopped matching. Write the editing script to a file with the Write tool and run that.
- **Two local instances share one `godot.log`.** Host and joiner use the same user folder, so
  `logs/godot.log` interleaves both, with lines cut mid-word. Read the host's own timestamped log
  (`logs/<date>T<time>.log`, the `log_event` lines) instead.

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
