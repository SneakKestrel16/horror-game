# Phase 2

The second build, in `game/`. It adds what the
[Build Plan](Farming_Horror_Game_Concept.md#build-plan-four-phases) asks of Phase 2, with the
decisions settled in Review 1, on top of the [Phase 1 prototype](phase1.md).

## Contents

- [Running it](#running-it)
- [What is new](#what-is-new)
- [Numbers](#numbers)
- [Playtesting](#playtesting)
- [Playtest results](#playtest-results)
- [Checklist](#checklist)
- [Not in Phase 2](#not-in-phase-2)

## Running it

As in Phase 1 (see [Running it](phase1.md#running-it)), with two more options:

- `-- --name=Ana` sets your name; the main menu has a box for it too. Teammates record it.
- `-- --start` skips the lobby and starts the day at once (testing).
- `-- --monster=scarecrow` picks the creature's look (`creature`, `scarecrow`, `boar`, `husk`); otherwise the host picks one at random and logs it.

Up to four players can join. Hold **V** to talk to whoever is near you. On Windows, apps must be
allowed to use the microphone (Settings > Privacy > Microphone) or recordings come out silent.
The voice addon has not been tested with a real microphone yet, so the first session should
check that recording and proximity chat work before anything else.

## What is new

- **Lobby** (`scripts/lobby.gd`): before the first day, everyone sees who is here. Ticking
  "Let the creature copy my voice" lets a player record a fixed list of lines ("Over here!",
  "Help me!", "Come look at this.", "Where are you?") and each teammate's name, up to three takes
  each, with a prompt to say it scared, and play them back. Unticking deletes their takes. A
  player can keep their voice from being played to chosen teammates. The host starts the day.
- **Voice bank** (`scripts/voice_bank.gd`): the host keeps the takes for this match only. When
  the creature calls, each listener hears their own pick: a teammate's recorded line (their own
  voice only rarely), half the time their own name in a friend's voice if a friend recorded it,
  or a generic line when nobody recorded anything. Each call gets at most one random tell, a
  faint echo or a voice slightly off pitch, and a third get none.
- **Live clips** (brought forward from Phase 3 after the calm lobby takes): the consent tick also
  lets the host keep what the player says over proximity chat, push to talk only, up to 3 s a
  phrase and their last 8, for this match only. The creature calls with a chat phrase 70% of the
  time when it has one (unless it calls the listener's name), so lobby lines are now optional.
  The voice block applies; withdrawing consent deletes them. **C** in game opens a list of your
  kept phrases (`scripts/clip_list.gd`), asked from the host, to play back or delete one by one
  or all at once (design doc, Build Notes).
- **Proximity voice chat** (`addons/voice_chat`, copied from `voice_chat_prototype/`): push to
  talk on V, heard from where the speaker stands, through static from the dead.
- **Two days and two nights.** The second morning matters: whatever the creature set at night
  is waiting. The run ends at the second dawn.
- **The pegboard and stolen traps** (`scripts/trap_field.gd`): four bear traps hang on a
  pegboard in the shed, with painted outlines showing any that are missing. Each night the
  creature walks to the shed, takes what it needs, and hides them, mostly just inside the corn,
  and digs pits, mostly between the field's rows and on the paths. A spent bear trap can be picked
  up and hung back on the pegboard. Any bear trap off the pegboard at nightfall is the
  creature's: it vanishes once no living player is within 15 m, by morning at the latest.
  There are no traps on day 1 now; the first ones arrive the first night.
- **Death, respawn and the bill:** a player taken at night is a ghost until dawn, then comes
  back at the barn. Each morning the medical bill is paid: 25 for the first death of the night
  and 50 for each after, at most 120 a night, never leaving less than 4 coins. If everyone died,
  the night ends at once and the creature sets an extra bear trap and pit.
- **Day deaths:** by day the creature can kill only a player stuck in a bear trap with nobody
  within 20 m for 15 s (design doc, Day Deaths). It leaves the corn to do it.
- **Up to four players**, with trap counts scaled to the team (70% for one or two players, 85%
  for three).
- **Logs** say what each listener heard when the creature called, and `LURE WORKED` lines say
  whose voice a player followed. The dawn screen counts lures followed in a friend's voice.
- **Code layout:** the farm's tools, crops and use actions moved from `game.gd` to
  `scripts/chores.gd`; the developer panel's helpers moved to `scripts/dev.gd`, which also gains
  "Start the day", "Creature takes and sets tonight's traps now", "Call me with a recorded
  voice" and "Skip to the next morning".
- **Corn that reaches in, and corn worth cutting** (`scripts/farm.gd`, added after the solo
  playtest): the wild corn is a map of one-metre cells, not a square ring. Ragged strips reach
  in from the ring toward the generator, behind the barn, west of the field and behind it, and
  east of the field into a patch of four planted corn plots. A band between the barn and the
  field, and a screen between the barn and the shed, put corn across every way out of the barn. The planted corn starts ripe (it
  takes 3 days to grow, longer than Phase 2 lasts), is cut with a 3 s hold that the creature
  can hear, and sells for 45 against a turnip plot's 10. Bear traps hide in it like any corn.
  Cut corn is open ground for good: no cover, and no way through for the creature by day.

## Numbers

Phase 1's numbers still hold ([Numbers](phase1.md#numbers)); new ones:

| What | Value | Source |
|---|---|---|
| Days | 2 | Choice for Phase 2: one morning after a night of trap setting |
| Bear traps on the pegboard | 4 | Guess |
| Traps set per night (4 players) | 2 bear traps and 1 pit, then 2 and 2 | Doc, Ramp-Up days 1 and 2 |
| Team scaling | 70% (1-2 players), 85% (3), 100% (4) | Doc, Winning and Losing |
| Medical bill | 25 first, 50 each after, cap 120, floor 4 | Doc, Medical Bill (Review 1) |
| Extra traps after a wipe | 1 bear trap, 1 pit | Guess (doc: "extra traps") |
| Trapped and alone before a day kill | nobody within 20 m for 15 s | Guess |
| Recorded lines | 4 fixed lines plus each teammate's name, 3 takes each, 0.4-3 s | Guess |
| Own voice weight | 5% of a teammate's | Guess |
| Off-board trap vanishes | no living player within 15 m | Guess |
| Trap on a path instead of its usual place | bear trap 15%, pit 40% | Guess; bear traps were 40% until the solo playtest |
| Planted corn | 4 plots of 3 × 3 m, ripe at the start, 45 coins each | Price: doc, Crops; the rest a guess |
| Cutting corn | 3 s hold, heard 8 m away | Guess (doc: harvesting is "a hold of a few seconds") |
| Corn strips | 7 strips, 4-6 m wide; edges moved up to 2.5 m by noise | Guess |

## Playtesting

The Build Plan's test: **hearing a friend's recorded voice from the corn fools someone, and trap
sweeps feel worth doing.**

1. Two to four people, with headphones and in-game voice. First check that recording and
   proximity chat work; the addon has never met a real microphone.
2. In the lobby, everyone who agrees records their lines. Don't explain what the creature does
   with them.
3. Play both days. On day 2, notice whether people check the pegboard, sweep for traps, and
   hang spent ones back up.
4. In the host's log, `LURE WORKED: X walked toward Y's '...'` lines are friends' voices that
   fooled someone; the dawn screen counts them.
5. Ask whether trap sweeps felt worth the time, and whether anyone was fooled.

Then run Review 2 in the Build Plan, including its check that players could place a teammate.

## Playtest results

### 2026-10-04, solo session (one person, both windows, `--dev`)

From the host's log (`2026-10-04T15-02-56.log`) and the player's report. With one person and the
second window idle, it could not test the Phase 2 goal: every call was forced from the dev panel
and nobody walked toward one.

- **Both nights ended in a wipe.** The idle window's player was caught by the barn door each
  night; the other was caught after the generator went out (dev panel). The bill took coins down
  to the floor of 4 both mornings, as designed.
- **The dawn screen named both dead players as survivors.** The last dawn revived everyone before
  it was written. Fixed; the smoke test checks it.
- **The creature was stuck in the barn on day 2.** It killed inside the dark barn, and by day it
  routes through the corn only, so its first step from the barn led through the back wall. It
  now walks out to the corn first. Fixed; the smoke test checks it.
- **It stood and stared before chasing after the lights went out on night 2.** The log shows it
  fetching a bear trap and digging a pit at (-10, -6) for those 10 s, about 10 m from the player,
  which is its sight range in the open; it did not react to the lights at all. The generator
  dying now makes a noise the whole farm hears, and the creature drops its errand to go and look.
  Inference: digging has no animation, so it reads as staring; a digging pose would show it.
- **Voice chat errored when the host left** (`get_unique_id` after the peer was gone). Fixed.
- **Players came back outside the barn,** at (0, -9), 3 m from the door, where the idle player
  was caught both nights. Players now spawn and respawn inside it, at (0, -15).
- **Neither wipe morning put a trap in the corn:** both bear traps went on paths, a 16% chance
  when each had a 40% chance of a path. Bear traps now take a path 15% of the time.
- **At the last dawn the creature still set the wipe's extra traps,** after the run had ended.
  It no longer does.
- **The log read badly after a wipe:** the extra traps printed a second "means to set" line
  like a duplicate, and said "1 bear traps". It now says why, and counts in the singular.
- **Untested:** no bear trap was sprung or hung back on the pegboard, and one call in nine used
  the listener's own voice (expected with only one person recording).
- **Nothing drew anyone into the corn.** With bear traps moved into it, they only mattered if a
  voice lured someone in. Planted corn in the field would not have helped alone: the wild corn
  was a plain ring, so the creature could not have reached it by day without crossing open
  ground. The corn now reaches into the farm in ragged strips, one joining a planted corn patch
  worth 45 a plot (see [What is new](#what-is-new)). The next session should check that the
  corn is worth the risk and the strips make the day feel less safe.

### 2026-10-04, earlier solo run (recording voice lines)

From the player's report; no log was kept of it.

- **Recording works with a real microphone:** takes recorded, played back in the lobby, and were
  heard when the creature called.
- **People record in a neutral tone,** not scared, whatever the prompt asks. The player's view: a
  bigger, more chaotic farm would make a calm "Come look at this." believable, so the lines can
  work as recorded if the game around them gives a reason to say them calmly. To be weighed in
  Review 2 against processing the takes to sound strained.
- **Takes were very quiet.** They were kept at the microphone's level, well below the stock
  lines. Each take is now raised to a 0.9 peak when saved, at most 16 times louder so a
  near-silent one doesn't become hiss (`VoiceBank.normalized`). The next session should check the
  level; if takes then sound hissy, the cause is the chat codec they go through (16 kHz, 8-bit
  mu-law, `addons/voice_chat/voice_codec.gd`). The codec is now 24 kHz 16-bit PCM, filtered
  before resampling, and each voice is buffered 60 ms against late packets (after Phase 3).

### 2026-10-04, solo session with the new corn (one window, `--dev`)

From the host's log (`2026-10-04T16-14-13.log`); mostly dev-panel skips, so no deaths.

- **The planted corn pays at once:** two plots cut and sold within 20 s of the day starting,
  100 coins by 26 s, with the creature calling from far off. Inference: by day, alone, cutting
  corn costs nothing yet; with the bill the only use for coins, 4 plots (180) cover most of a
  run's bills. Worth watching with more players before changing the price or the plot count.
- **The strips are in use:** the creature called from the generator strip at (18, -16) on the
  morning of day 2, and a pit on the fuel run caught the player.
- **Lures worked at dusk,** leading the player from 29 m to 1 m and on again, in their own voice,
  since nobody else had recorded.
- **The dawn screen counted those as a friend's voice.** Own-voice lures no longer count.
- **A lure check was logged after the dawn screen,** so the screen missed it. Checks stop at the
  end of the run.
- **Log wording:** "1 players" and "1 traps off the pegboard" now count in the singular, as does
  the morning's "missing 1 bear trap".

### 2026-10-04, playtest 2 (one person, both windows, `--dev`)

From the host's log (`2026-10-04T17-16-08.log`) and the player's report. Live chat clips, the
corn strips and the C list were new.

- **Chat clips reach the creature:** the idle window heard "words from voice chat" in the other
  player's voice four times. Three lures worked, led 17 m to 6 m and 25 m to 5 m.
- **The C list worked;** once it seemed not to, most likely with the mic off. Hardened anyway:
  phrases a muted mic records (near silence) are no longer kept, the open list refreshes after
  you speak, and Delete names the phrase rather than its place in the list, which could shift.
- **The creature ran past the nearer player** to stay on its target. Mid-chase it now turns on a
  player it can see who is at least 2 m nearer.
- **It never went for the other player** after the kill: it retreated, then wandered the corn
  while the idle player stood still and made no sound. At night it now prowls within 8 m of a
  random player half the time, and goes into a dark barn where someone hides.
- **It got stuck on things.** The hay, generator, pump and crate are solid but were missing from
  its walking grid, and a chase ran straight at the target through anything not tall enough to
  hide them. Routes now go round them, and a chase goes straight only with nothing in the way.
- **Its walking still looked wrong** (2026-10-05): it zig-zagged from one grid cell to the next,
  and on any walk longer than a couple of waypoints it re-planned every 2 s, because its stuck
  check never reset between waypoints. Routes are now pulled straight wherever a creature-wide
  strip is open on the grid, and end on the goal rather than its cell's centre; it re-plans only
  after 1.5 s without moving half a metre. In a headless bench of six trips (three over the
  open grid, three corn-only) it went from 22–120 waypoints a trip and 115 re-plans, with two
  trips ending 9–13 m off and one never arriving, to 1–5 waypoints, no re-plans, and every
  trip ending at its goal. The smoke test's stays-in-the-corn check still passes.
- **The walk to the field and the shed was all open ground** (2026-10-05, the player's request):
  the creature only felt close at the corn's edge. A 5 m band of corn now runs from x = -18 to
  the ring in the east between the barn door and the field, and a 4 m screen from z = -20 to the
  band stands between the barn and the shed and fuel drum, so leaving the barn for either means
  crossing corn, where the creature can be by day. Fuel runs now cross it too.
- **The in-game copy sounded off at the start,** next to the recording. Every call has a tell
  (an echo, or pitch 6% off) two times in three, by design, but the log didn't say which this
  was; it does now. Inference: the start also carries the push-to-talk key's click and can begin
  mid-wave, so chat phrases now lose their first 0.1 s and fade in and out over 20 ms.
- **Corn money again:** 155 coins by 84 s from three corn plots and two turnip sales. Still to
  judge with real players.
- **Log wording:** "Farmer 1 pried Farmer 1 free" now reads "pried themselves free".

## Checklist

What is still to build or check, from the
[Build Plan](Farming_Horror_Game_Concept.md#build-plan-four-phases), this phase's playtests, and
the art and sound the prototype fakes.

### Phase 2 (to pass)

- [x] Dawn screen names the night's dead
- [x] Creature walks out of the barn by day
- [x] Creature reacts to the barn going dark
- [ ] A playtest with 2-4 real people, each on their own machine
- [x] Recording with a real microphone
- [ ] Proximity chat between two machines with real microphones
- [x] Recorded takes raised to full level
- [ ] Check the new take level in a playtest
- [x] Neutral-tone takes: the creature now mostly uses live chat clips
- [x] A way to review and delete your kept chat clips (C in game)
- [ ] Check in a playtest that chat clips sound right from the corn
- [ ] A friend's recorded voice fools someone (`LURE WORKED` in the log)
- [ ] Trap sweeps and rehanging traps on the pegboard feel worth doing
- [ ] Digging and trap-setting animations, so an errand doesn't look like staring
- [ ] Review 2: placing teammates, lantern flicker (issue 5), one tracked state (6), day-death
  rules (7), whether ghosts will have enough to do

### Phase 3

- [x] Live clips from proximity chat (brought into Phase 2)
Built ahead of Review 2; see [Phase 3](phase3.md) and its checklist.

- [x] The creature favours dead players' voices
- [x] The Director (pacing)
- [x] Jumpscares: lunge, stare, whisper, crow fake-out (the shed scare waits for a door)
- [x] Wounds after a day scare (less sprint, louder steps, a night trail)
- [x] Ghost abilities, including the lantern flicker

### Phase 4

- [ ] The 7-day season, saving between days, the corn quota and payments
- [x] Seed packs, pumpkins and moonflowers, and a first set of upgrades (built early: [The farm store](store.md))
- [ ] The economy around them: payments, the corn quota, prices tuned
- [ ] Roles
- [ ] The sabotage pool and the unattended farm (wrecked crops and fences)
- [ ] The farmhouse, animals, fences and scarecrows
- [ ] The creature testing the barn doors from day 6

### Sounds

`scripts/sfx.gd` plays recorded sounds from the
[FilmCow Recorded SFX](https://filmcow.itch.io/filmcow-sfx) library where it has one, and
synthesises the rest. The recordings are not in git: their licence allows any game use without
credit but doesn't say the raw files may be shared in a public repo, so `tools/get_sfx.sh <zip>`
copies them into `game/assets/sfx/` (ignored), and without them every sound falls back to its
synthesised stand-in. The generic calls are Windows text-to-speech (`assets/voices/`, David and
Zira).

Recorded now, chosen by file name and not yet heard in the game (`Sfx.RECORDED`): footsteps on
dirt and in the corn, the corn rustle, water, metal clanks, the bear trap, falls and the
generator's hum. Each plays one of several takes at a slightly random pitch and level.

- [ ] Listen to the recorded sounds in a playtest; swap any that don't fit and set their levels
- [ ] Exported builds: the recorded sounds sit in a folder Godot ignores, so an export needs
  them packed some other way
- [ ] Recorded generic voice lines from real people, to replace the text-to-speech ones
- [ ] The creature: footsteps, breathing, the chase screech, digging, setting a trap
- [x] Footsteps on dirt and in the corn; corn rustle. The first recorded steps ("footstep dirt") sounded wet and far too loud (2026-10-04 playtest); now the short, dry "grass and leaves hard" set, 13 dB quieter, cut to 0.16 s
- [ ] Footsteps on grass
- [x] Traps: bear trap snap, falling into a pit
- [ ] Traps: prying open
- [x] Tools and chores: watering, pump, the pegboard (water and metal sounds)
- [ ] Tools and chores: harvest, selling (still synthesised)
- [x] Generator running
- [ ] Generator: sputtering when low, dying, refuelling
- [ ] Barn and shed doors
- [ ] Ambience: day birds and insects, animals going quiet at dusk, night crickets and wind
- [x] Heartbeat when hunted: faster (72 to 168 bpm) and louder the closer a chasing creature is, still pounding about 12 s after; a low dissonant drone swells in under a chase (2026-10-04, synthesised)
- [ ] Crows for fake-outs (synthesised caw only), stingers for jumpscares

### Textures

Baked in Blender and put on models built there (2026-10-04); see [Models and textures](models.md).

- [x] Ground: grass, dirt paths, tilled soil in the field
- [x] Corn stalks and leaves
- [x] Barn and shed: weathered wood, roof, doors
- [x] Metal: generator, fuel drum, pump
- [ ] Metal: bear traps, pegboard tools (still primitives in `looks.gd`)
- [ ] Crops at each growth stage
- [x] The creature's skin, and player models
- [x] Night sky and moon: a sky shader (`assets/shaders/sky.gdshader`) with a palette for each
  time of day, from morning through sunset and night to the last dawn, driven by `Looks.Daylight`

## Not in Phase 2

The creature favouring dead players' voices, the Director,
jumpscares, ghost abilities (Phase 3); the season, economy, upgrades, roles and payments
(Phase 4). Coins have no use yet beyond the medical bill.
