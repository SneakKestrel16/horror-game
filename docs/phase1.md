# Phase 1 prototype

The first playable build, in `game/`. It covers what the
[Build Plan](Farming_Horror_Game_Concept.md#build-plan-four-phases) asks of Phase 1, and
nothing from later phases. This page lists what was built, the numbers it uses, and how to run
the playtest that decides whether Phase 1 is done.

## Contents

- [Running it](#running-it)
- [What is in it](#what-is-in-it)
- [Numbers](#numbers)
- [Playtesting](#playtesting)
- [Not in Phase 1](#not-in-phase-1)

## Running it

Godot 4.7.2 from winget. From the repo root:

- Two players on one PC: run the game twice, once with `-- --host` and once with
  `-- --join=127.0.0.1`. In the editor, Debug > Customize Run Instances does the same.
- `--short` runs the day, dusk and night at a sixth of their length for quick checks;
  `--dev` lets the host press F2 to skip to the next phase.
- `bash tools/check.sh` imports the project headless and plays through the smoke test
  (`game/tests/smoke.gd`).
- `godot --path game res://tools/snapshot.tscn -- --clock=500 --from=0,1.6,8 --look=0,1.6,14
  --creature=1,0,13 --out=shot.png` saves a screenshot at a time of day, with the creature
  placed, without playing.

Controls: WASD, Shift sprint, Ctrl crouch, E use (hold for traps), G drop, F lantern, Esc frees
the mouse and a second Esc leaves.

## What is in it

- **The farm** (`scripts/farm.gd`): one field of 12 turnip plots, the barn (the lit building),
  the tool shed with the crowbar and shovel, the generator, the fuel drum, the pump and the
  shipping crate, all ringed by wild corn players walk through and cannot clear.
- **Day chores:** water the dry plots (the can holds 4 waterings; refill at the pump), pull ripe
  turnips and sell them at the crate. One tool or crop is carried at a time.
- **Day, dusk, night, dawn** (`scripts/game.gd`): one of each. Dawn shows who survived, the coins,
  the traps sprung and how many lures were followed.
- **The creature** (`scripts/creature.gd`), faked with states and timers as the Build Plan
  allows: it lurks in the corn, goes to look at noises, and calls out with a generic voice line.
  By day it stays inside the corn and never chases. At night it walks the whole farm, chases a
  player it sees (sight is short, longer for a lit lantern, shorter for crouching, blocked by
  walls and corn), kills on contact, and backs off into the corn afterwards. It will not enter the
  barn while the lights are on; while everyone hides there it mostly waits in the dark along the
  fuel run between the drum and the generator.
- **Noise:** footsteps (crouch 2 m, walk 7 m, sprint 16 m, half again in the corn), chores, and
  traps springing all reach the creature. Footsteps and chores are also played as sounds.
- **Traps in scripted spots:** five set at the start, as if left overnight, and three more armed
  at dusk. Bear traps hold a player until they hold E to pry free (a friend helps, faster), then
  slow them 40% for 60 s. Pits trip the player and drop what they carry. Bear traps are disarmed
  with the crowbar, pits filled with the shovel. Both are hard to see, and a trap's prompt shows
  only when looking right at it.
- **The generator:** the barn lights run from dusk while it has fuel. A full tank lasts 40% of
  the night and dusk burns half a tank, so the night needs at least two trips with the fuel can
  from the drum by the shed. Refuelling is a noisy 3 s hold, and the lights flicker under 15%.
- **Voice lures:** the creature calls a generic line from cover at whoever is most alone, or
  whoever just made a noise. It weighs 24 spots 9-24 m around where they stand: away from its last
  four calling spots, behind or beside them rather than in front, past an armed trap when one lies
  on the way, and not too far to creep to. If they move off before it gets there it re-aims. If
  they walk toward the call it backs off 6-10 m deeper and calls again, up to twice. A faint
  reverb on its voice is the tell. The lines are Windows text-to-speech placeholders (voices David and Zira) in
  `game/assets/voices/`; replace them with real recordings.
- **Atmosphere:** a sun that lowers into an orange dusk, a dark night with fog and a weak moon,
  wind by day, crickets by night that fall silent when the creature is within 18 m of you, a
  heartbeat when it chases near you, and the generator's hum. Sound effects are synthesised in
  code (`scripts/sfx.gd`) as placeholders.
- **Logging:** the host writes every event to `user://logs/<date>.log` (on Windows,
  `%APPDATA%\Godot\app_userdata\Something in the Corn\logs`) and prints it.

## Numbers

Starting values, to be tuned from playtest logs. The ones the design doc gives are cited there;
the rest are first guesses made for this prototype.

| What | Value | Source |
|---|---|---|
| Day / dusk / night | 6 min / 1 min / 5 min | Doc says day 8-10 min; shortened because Phase 1 has one small field |
| Bear trap slow | 40% for 60 s | Doc, Night Traps |
| Turnip price | 10 | Doc, Crops |
| Walk / sprint / crouch | 3.6 / 6.3 / 1.8 m/s; 6 s of sprint | Guess |
| Creature lurk / investigate / chase | 1.6 / 2.4 (day), 3.4 (night) / 5.4 m/s | Guess: chase is between walking and sprinting |
| Creature sight | 10 m; 24 m at a lantern; 5 m at a crouch | Guess |
| Chase given up | 4 s out of sight, or the target reaches the lit barn | Guess |
| Lures | every 50-80 s by day, 30-50 s at night; 9-24 m from the target | Guess |
| Generator | starts at 40%; a can fills it; full lasts 40% of the night | Guess, after the first playtest |
| Pry free | 3 s alone, 1.5 s with help; disarm 4 s; fill a pit 3 s; refuel 3 s | Guess |

## Playtesting

The Build Plan's test: **the day feels safe, the night feels tense, and a generic voice from the
corn makes a playtester walk toward it at least once.**

1. Two people, one host and one joining, with headphones. Don't tell them what the voices are.
2. Play one full day and night at normal length.
3. Read the host's log. `LURE WORKED` lines count the lures a player walked toward (4 m closer
   within 12 s, among players within 40 m of the voice). The dawn screen shows the totals too.
4. Ask each player whether the day felt safe and the night felt tense, and note anything that
   felt unfair: a trap they could not have seen, a death they could not have escaped.

Once this passes and the session was fun, run Review 1 in the [Build Plan](Farming_Horror_Game_Concept.md#build-plan-four-phases) before starting Phase 2.

## Not in Phase 1

Left for later phases, as the Build Plan orders them: voice chat and lobby voice lines, the
creature stealing traps from the pegboard, respawning at dawn and the medical bill, 3-4 players,
the Director, jumpscares, ghost abilities, crops other than turnips, the economy and the
season. A dead player in Phase 1 is a ghost that drifts until dawn.

## Playtest results

### 2026-10-04, first session (two players, normal length)

From the host's log and the players' report:

- **A lure worked:** Farmer 2 walked from 32 m to 24 m toward "where are you?" 2:31 into the day.
  That meets the voice part of the Phase 1 test.
- **Both died at night.** Farmer 2 was caught in the open at the field 25 s into the night.
  Farmer 1 was taken inside the barn 14 s after the generator ran dry (1:42 into the night),
  which is the intended failure.
- **Voices were heard by both players,** but the mimicry feels basic, as expected from generic
  placeholder lines.
- **Lures repeat from one spot:** 5 of 9 calls came from (-23, -3), beside bear trap 3, which
  nobody cleared. Aiming at the nearest armed trap keeps choosing it. Inference: some variety in
  spots would make the calls harder to learn; worth watching in the next session.
- **Rejoining works:** Farmer 2 left with Esc and rejoined mid-day with the farm as it stood.
- **Players' verdict:** the calls felt basic, with no horror to them, and a powered generator
  made the barn a sure refuge with no reason to leave.
- **Changed after it:** calls now move with the player and avoid repeating spots, lead on
  whoever approaches, and the generator needs at least two fuel runs a night, which the creature
  waits along. The next session should check whether the calls feel like a hunt and whether
  the fuel runs are tense rather than tedious.
