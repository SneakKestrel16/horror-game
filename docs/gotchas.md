# Gotchas

Traps hit while building the game, with what fixed them.

## Godot

- **A script that fails to compile hangs the smoke test.** The test's `_ready` never runs, so
  nothing calls `quit()`. `tools/check.sh` runs Godot under `timeout` and prints the log only at
  the end, so on a timeout run the scene by hand with `--quit-after` to see the error.
- **`godot -s script.gd --check-only` reports autoloads as missing** ("Identifier not found:
  Net"). That is the `-s` mode, not the code; run the smoke test instead. It does find a parse
  error in a class with no autoloads, such as `farm.gd`. For a throwaway script that needs the
  game (a screenshot, say), make a temporary `.tscn` whose root node runs it, as the smoke test
  does; under `-s` even `game.gd` fails to compile.
- **Wait by time, not frames, in a windowed run.** A windowed game runs far faster than the smoke
  test's physics frames, so 40 frames was under VoiceChat's 0.4 s phrase gap and no phrase was
  ever finished. Use `get_tree().create_timer(...)`.
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
- **A segfault after `SMOKE PASS` still fails the hook** (exit 139), and grepping the output for
  `FAIL` misses it: check the exit code. Phase 3's test crashed Godot on quit in most runs once a
  test-only player (a peer that never connected) had had its lantern flickered by a ghost. Not
  the light: turning the lantern off, or flickering by visibility instead of energy, still
  crashed. Freeing every player 10 frames before the game stopped it (8 clean runs of 8).
  Inference: whether a real game can crash the same way on quit is untested.
- **Bisect a flaky crash with 8 runs a variant, not 3.** At a 40% crash rate, 0 of 3 happens one
  time in five, and two 3-run "clean" variants here were wrong. And cut a test short with
  `if _game != null: return`: a bare `return` makes the rest unreachable, a compile error that
  hangs each run until the 240 s timeout.
- **`timeout` doesn't always kill Godot on Windows.** A killed bisect left two headless runs
  holding the test port, and later runs hung. Stop them with
  `Get-Process Godot_v4*_console | Stop-Process` before rerunning.
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
- **`sed -i "${n}a ..."` with an empty `$n` appends after every line.** A `grep` that found
  nothing left `n` empty and copied four lines all through `farm.gd` (2,700 lines added). Use the
  Edit tool for insertions, or check `n` first. `git checkout -- <file>` put it back, since the file
  had no other changes.
- **A very long Bash heredoc failed to parse** ("unexpected EOF while looking for matching `'`")
  and nothing past it ran. The 600-line half of `models.py` went in through the Write tool and
  `cat >>` instead. A `cat > file` with no heredoc waits on stdin until the tool's timeout.
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

## Audio

- **Each read of `AudioStreamWAV.data` copies the whole buffer.** Calling
  `wav.data.decode_s16(i)` in a loop took 100 s for one 14 s file; read it into a local once.
  A loop that never finishes shows up as the smoke test hitting its 240 s timeout.
- **Some FilmCow WAVs declare a RIFF size a few bytes short of the file,** and Godot's loader
  warns (which `check.sh` fails on). `Sfx._load` sets the size field to the true size first.
- **Recorded sound effects stay out of git** (`game/assets/sfx/`, filled by `tools/get_sfx.sh`).
  The folder has a `.gdignore`, so the editor doesn't import them (no `.import` files) and
  `Sfx` loads them at run time with `AudioStreamWAV.load_from_buffer`. The smoke test passes
  with them or without them; run it both ways after touching `Sfx`.
- **Voice is 48 KB/s per talker** since the codec went to 24 kHz 16-bit (it was 16 KB/s). The
  host relays every voice to everyone else, so with four people talking at once the host sends
  about 0.45 MB/s (its own voice to three, each other voice to two). Fine on a LAN; inference:
  may be tight on a slow home upload. Lower `VoiceCodec.RATE` before going back to mu-law.

## Models and textures

- **Godot imports a JPEG without mipmaps and lossless,** which shimmers on tiled ground. Each map's
  `.import` turns mipmaps and VRAM compression on, and the `_n` maps' normal-map compression.
  A new texture needs the same `[params]`.
- **A MultiMesh's instance colours did not tint the glTF corn** until the mesh was given white
  vertex colours (`Dress.mesh`); every stalk drew the texture's own pale colour. Seen in two
  snapshots, not traced in Godot's source.
- **check-added-large-files allows 500 KB**, and the first barn (627 KB) and creature (701 KB)
  were over. Hay bales with one bevel segment, and a coarser metaball resolution on the creature's
  body and limbs, brought them to 440 and 430 KB. Check `ls -la game/assets/models` after a
  rebuild.
- **A metaball chain is fatter than its radii.** `models._taper` lays balls 3 cm apart and their
  fields add, so limbs come out thicker than the numbers say. Judge them in the showcase, not by
  the radii.
- **Blender's Math node has no smootherstep;** Map Range does (`Graph.band`).
- **A light inside a mesh is shadowed by it.** The barn lamps' bulbs sat round Farm's lights at
  first. The lamps are now raised 0.12 m so the light is below the bulb and the shade.

## Lighting

- **Fog greys out the sky.** With `fog_sky_affect` at its default of 1, even light day fog
  turned the sky white-grey, and night fog hid the stars and moon. It is now 0: the sky shader
  fades to the horizon colour, which is also the fog colour, so far ground still meets the sky.
- **A sky shader that reads `TIME` redraws its radiance every frame.** `sky.gdshader` takes twinkle,
  star turn and cloud drift as uniforms from the clock instead, and the sky uses
  `PROCESS_MODE_INCREMENTAL` to spread each redraw. Draw the sun disc and stars only when
  `AT_CUBEMAP_PASS` is false, or they leak into the farm's ambient light.
- **The last dawn has no clock.** The host stops the clock when the game ends, so `Daylight`
  counts the final dawn itself from `delta`.
