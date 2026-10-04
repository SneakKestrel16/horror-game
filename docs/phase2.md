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
  mu-law, `addons/voice_chat/voice_codec.gd`).

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
- [ ] Neutral-tone takes: make the farm busy enough that calm lines fit, or process them
- [ ] A friend's recorded voice fools someone (`LURE WORKED` in the log)
- [ ] Trap sweeps and rehanging traps on the pegboard feel worth doing
- [ ] Digging and trap-setting animations, so an errand doesn't look like staring
- [ ] Review 2: placing teammates, lantern flicker (issue 5), one tracked state (6), day-death
  rules (7), whether ghosts will have enough to do

### Phase 3

- [ ] Live clips from proximity chat for the creature to use
- [ ] The creature favours dead players' voices
- [ ] The Director (pacing)
- [ ] Jumpscares (disarm lunge, shed, whisper, own voice, crow fake-outs)
- [ ] Wounds after a day scare (less sprint, louder steps, a night trail)
- [ ] Ghost abilities, including the lantern flicker

### Phase 4

- [ ] The 7-day season, saving between days, the corn quota and payments
- [ ] Crops and moonflowers, the economy and upgrades
- [ ] Roles
- [ ] The sabotage pool and the unattended farm (wrecked crops and fences)
- [ ] The farmhouse, animals, fences and scarecrows
- [ ] The creature testing the barn doors from day 6

### Sounds

Every sound is synthesised in `scripts/sfx.gd`, and the generic calls are Windows text-to-speech
(`assets/voices/`, David and Zira).

- [ ] Recorded generic voice lines from real people, to replace the text-to-speech ones
- [ ] The creature: footsteps, breathing, the chase screech, digging, setting a trap
- [ ] Footsteps on dirt, grass and in the corn; corn rustle
- [ ] Traps: bear trap snap, prying open, falling into a pit
- [ ] Tools and chores: watering, pump, harvest, selling, the pegboard
- [ ] Generator: running, sputtering when low, dying, refuelling
- [ ] Barn and shed doors
- [ ] Ambience: day birds and insects, animals going quiet at dusk, night crickets and wind
- [ ] Crows for fake-outs, stingers for jumpscares, heartbeat when hunted

### Textures

There are none yet: every surface is a flat colour.

- [ ] Ground: grass, dirt paths, tilled soil in the field
- [ ] Corn stalks and leaves
- [ ] Barn and shed: weathered wood, roof, doors
- [ ] Metal: bear traps, generator, fuel drum, pegboard tools
- [ ] Crops at each growth stage
- [ ] The creature's skin, and player models
- [ ] Night sky and moon

## Not in Phase 2

Live clips from proximity chat, the creature favouring dead players' voices, the Director,
jumpscares, ghost abilities (Phase 3); the season, economy, upgrades, roles and payments
(Phase 4). Coins have no use yet beyond the medical bill.
