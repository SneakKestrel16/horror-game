# Farming Horror Game: Design Concept

A multiplayer game where players grow and farm crops while being hunted. The combo works because farming naturally creates the tension horror needs: crops tie you to specific spots, the work is noisy and repetitive, and you can’t finish it all with everyone huddled together.

**Format:** 2 to 4 player co-op. The monster is AI-controlled, so every player is on the same side against it. The creature and the money targets scale with the number of players.

## The Core Loop

**Day (safe-ish, about 8 to 10 minutes):** Players glance at the shed pegboard, sweep for and disarm traps left overnight, plant, water, harvest, fix what the creature broke, and sell at the town stand. This is the cozy part, and it’s where you build up resources and stakes.

**Dusk (warning phase, about 1 minute):** The light fades, animals go quiet, and players rush to finish chores, get valuable crops harvested, and top up the generator.

**Night (the hunt, about 5 minutes):** The creature comes out of the corn, hunts, and sets traps for the next day. Moonflowers can only be harvested at night and are worth far more, and the generator needs refueling partway through. Nobody can sit safely in the barn all night (see Nights).

**Dawn:** Survivors cash in. Anyone who died loses what they were carrying, the medical bill is paid, and the farm takes damage where the creature roamed, more if nobody was outside to stop it.

The contrast between peaceful daytime farming and terrifying nights is the hook. The cozy part makes players care, and the horror part threatens what they built.

## The Creature: Something in the Corn

You never see it clearly. It lives in the wild corn that rings the farm, a field players can’t cut down, so it always has somewhere to hide. Corn the players plant extends its hunting ground: tall crops block your view, so the crops you plant literally shape where it can hunt. Corn is the best-paying day crop and the harvest festival demands it, so the team can’t simply refuse to grow it (see Crops). It hunts with two tools: players’ own voices and the traps it sets at night.

### How It Hunts

- **Hearing:** Its main sense. Tools, footsteps, doors and talking all make noise, and louder sounds carry further.
- **Sight:** Short range only. It spots players carrying light or standing in open ground, but tall corn blocks its view just as it blocks yours.
- **Scent:** It can track marked players and anything a player dropped during the day (see Daytime Threats).

### Behavior States

- **Lurk:** Moves through the corn, sets traps at night, and gathers voice clips.
- **Lure:** Plays a mimicked voice or sound from cover, usually near an armed trap or a player who is alone.
- **Stalk:** Follows one player from cover, getting closer. Animals nearby go quiet.
- **Chase (night only):** Breaks cover and runs a player down. It loses them if they reach a lit building or break its line of sight for a few seconds.
- **Retreat:** After a jumpscare, a kill, or a hit from the Hunter’s flare, it pulls back into the corn for a while.
- **By day:** It can only Lurk, Lure, Stalk and jumpscare. Chasing and killing are for the night.

### The Director

A simple tension meter decides how aggressive the creature is from moment to moment, in the spirit of Left 4 Dead’s AI Director. After a scare or a chase the meter drops and the creature backs off; after a long quiet stretch it rises and the creature pushes in. This keeps scares spaced out and makes the quiet stretches part of the design rather than downtime.

## Signature Mechanic: Voice Mimicry

The creature can copy players’ voices. Proximity voice chat becomes both the team’s best tool and its biggest weakness, because nobody can fully trust what they hear.

### How It Works

- **It listens:** The creature uses each player’s lobby voice lines and, once the full system is in, short clips of what they say over proximity chat. The more someone talks, the more material it has.
- **It copies sounds too:** It can fake a teammate’s footsteps, a watering can, or a hoe, so quiet players still give it something to use.
- **By day:** It calls a player’s name from the corn or the treeline in a teammate’s voice, luring people away from the group and toward armed traps.
- **At night:** It replays phrases like “come here” or “I found something” to pull players into the dark, then hunts them.
- **It favors the dead:** Once a player dies, the creature is more likely to use that player’s voice. Hearing a dead friend call from the corn is one of the game’s strongest scares.
- **Rarely your own voice:** The chance of the creature using a player’s own voice on that same player is kept low, since they would know it isn’t them talking.
- **It gets better:** Early in the season it only plays back exact clips. From day 4 it mixes clips together, so the lines sound more natural and harder to spot.

### How Players Fight Back

- **Tells:** Mimicked voices have small giveaways, such as a slight echo, a missing radio crackle, or the voice coming from somewhere the teammate can’t be.
- **Passwords:** Teams can agree on a code word, but the creature can pick that up too if someone says it near it.
- **Staying quiet:** Talking less gives it less to copy, but it also makes teamwork harder.
- **Walkie-talkies:** A craftable radio that the creature can’t fake, but it runs on limited batteries.
- **The lantern flicker:** A dead teammate’s one signal the creature can never fake (see Death and Respawning).

### Keeping Players on In-Game Voice

Groups of friends often talk on Discord or a party chat instead. The design gives in-game voice real jobs so it’s worth using, and makes sure the creature still has voices if a group doesn’t.

- **Lobby voice lines:** Before a match, each player can record a handful of short lines, such as “over here,” “help me,” “come look at this” and their teammates’ names. The creature always has clips to use. This is opt-in, and players can hear their recordings back.
- **Proximity chat carries position:** In-game voice is 3D, so it’s the only way to hear where a teammate is and how far away.
- **Radios run on in-game chat:** Long-range talk only works through craftable walkie-talkies, so coordinating across the farm needs the in-game system.
- **The dead are only heard in-game:** Dead players’ static voices exist only in proximity chat.
- **Fallback voices:** Players with no recordings and no live clips get generic pre-recorded voices, so the mechanic never fully switches off.
- **Say it up front:** The main menu and lobby recommend in-game voice chat as the intended way to play.
- **Accepted trade-off:** A group on Discord will see through the voices more easily. That weakens mimicry but doesn’t break the game, since traps, scares and the night still work.

### Build Notes

- **Lobby lines first:** Record lobby voice lines and replay them from the creature’s position. Live clips from proximity chat and splicing come later.
- **Fallback:** Players with mics off, or who opt out, get pre-recorded generic lines instead.
- **Consent:** Tell players up front that the game records their voice for this, keep the clips only for that match, and include an opt-out setting.

## Night Traps

While players work or hide through the night, the creature sets traps around the farm. Any trap still armed in the morning becomes a daytime chore, and a weapon for the voices.

### Trap Types

- **Bear traps:** The creature steals them from the farm’s tool shed and hides them in the corn.
- **Getting free:** A trapped player is pinned by the leg until they pry the jaws open themselves, which takes a few seconds. A teammate can help, but nobody is ever stuck waiting.
- **The slow:** After getting free, the player moves slower for a while (starting point: 40% slower for 60 seconds). By day that costs farming time; at night it makes them easy prey.
- **Small pits:** Shallow holes dug between the rows and covered with stalks and husks. A player who steps in stumbles and drops what they were carrying, and that’s it: no getting stuck and no slow.

### The Tool Shed

- **Pegboard:** Bear traps hang on a pegboard with painted outlines, so one glance through the shed door shows how many are missing. Every empty outline is a trap hidden somewhere on the farm.
- **Locking it:** Buying a lock or boarding up the shed keeps traps in, but costs money and time, and from day 5 the creature can break in anyway.
- **Returning traps:** Disarmed bear traps can be carried back to the shed, which takes time but stops the creature from reusing them.

### Finding and Disarming

- **Clues:** Fresh dirt near pits, bent stalks, or a glint of metal show where traps might be, but only to players who look closely.
- **Disarming:** Bear traps need a tool and a few seconds of kneeling still in the corn. Pits are filled in with a shovel.
- **Spotting:** Disarming is safer with a teammate watching, which pulls two players off farming.

### The Lure Combo

During the day, the creature uses a teammate’s voice to call players toward rows where traps are still armed. A player who checked that row in the morning knows it’s safe; a player who didn’t gets caught. This rewards teams that split up their trap sweeps and talk about which rows are clear, which in turn gives the creature more voice clips to use.

### Rules

- **Non-lethal by day:** A trap sprung during the day holds, slows, marks, or costs you items, but never kills.
- **Deadly at night:** Traps that are still armed when night falls become far more dangerous, since a trapped player is easy prey.
- **Ramp up:** A few traps on night one, more and better-hidden ones as the season goes on (see Season and Numbers).

## Nights

Hiding in the barn all night is never fully safe and never free. Nights are short so fear doesn’t turn into boredom, and there is always a reason for someone to go out.

- **The generator:** The barn and farmhouse lights run on a generator, and the creature won’t enter a lit building. Fuel runs low partway through the night, and the fuel drum is outside by the shed. Someone has to go.
- **The unattended farm:** The longer nobody is outside, the more freely the creature roams, and the more crops and fences are wrecked by dawn.
- **Moonflowers:** The most valuable crop only opens at night and can only be harvested in the dark. They glow faintly, so whoever picks them is easy to see.
- **It tests the doors:** From day 6, if every player stays inside, the creature starts working at the barn doors, so staying put stops being safe.

## Jumpscares

The creature can’t kill during the day, but it can still terrify. A daytime jumpscare knocks the player down, makes them drop what they’re carrying, and leaves them shaken, then the creature vanishes back into the corn.

### Scare Moments

- **The disarm lunge:** While a player kneels to disarm a bear trap, the stalks part and the creature lunges at them, then pulls back into the rows.
- **The trap:** A player prying themselves out of a bear trap looks up to see the creature standing in the rows, watching, before it disappears.
- **The shed:** A player opens the shed to check the pegboard and the creature is inside, or the door slams shut behind them.
- **The whisper:** A teammate’s voice speaks right behind a player, even though that teammate is across the field.
- **Your own voice:** On rare occasions, a player hears their own voice whispering their name from the corn. It won’t fool them, but because it almost never happens, it’s deeply unsettling when it does.
- **Fake-outs:** The corn rustles and something bursts out, but it’s only a crow. These keep players from relaxing between real scares.
- **Hallucinations (late season, optional):** From day 5, a player sometimes sees the creature standing in the field or at the edge of the corn for a moment, and then it’s gone. Nobody else sees it. It’s a minor scare: no knockdown and no dropped items. Marked players see them more often.

### Making Them Land

- **Keep them rare:** Too many jumpscares and players get used to them. Long quiet stretches make each one hit harder.
- **Build up first:** Silence, animals going quiet, or a voice calling from nearby before the scare works better than a scare out of nowhere.
- **Make them cost something:** Dropping items means a scare matters for the game, not just for the moment, and dropped items leave a scent for the night.
- **Let the Director time them:** The tension meter decides when a scare is due and randomizes where, so players can’t learn the pattern.

## Death and Respawning

Death should matter without leaving anyone bored for long.

### Out Until Dawn

- **Respawn at dawn:** A player killed at night stays dead for the rest of that night and comes back at dawn with the survivors.
- **Medical bill:** Each death costs the team money at dawn, so protecting each other directly protects the farm. To stop a death spiral, the first death each night is cheaper, the bill has a cap per night, and it never takes the bank below the price of a turnip seed pack, so the team can always plant the next day (numbers in Season and Numbers).

### Dead Players Stay Involved

- **Ghost spectating:** Dead players can follow their teammates and see the creature and any armed traps.
- **The lantern flicker:** A dead player can make a lantern near a living teammate flicker. It’s the one signal the creature can never fake. It has a short cooldown so it stays meaningful.
- **Rustling the corn:** Dead players can also rustle stalks to point at something, but the creature can fake that.
- **Static voices:** Living players can still hear dead teammates in proximity chat, but only through heavy static.

### The Dead-Voice Twist

Once a player dies, the creature is more likely to mimic their voice. Combined with the static, this means a dead teammate’s real warning and the creature’s fake one can sound alike. The flicker is the tiebreaker: a static voice backed by a flickering lantern is a real teammate, and a voice with no flicker might be the creature. The dead player is trying to help, the creature is trying to lure, and the living have to decide who to trust.

## Daytime Threats

The monster can’t kill during the day, but it can still do harm. Traps, voice lures and jumpscares already fill most of the day, so other daytime harm is kept to a small pool. The creature gets a daily disturbance budget, a fixed number of these it can spend each day, rising over the season.

### Sabotage Pool

- **Trampled crops:** A few plants are destroyed where it roamed overnight, more if nobody was outside at night.
- **Stolen tools:** A watering can or hoe goes missing and turns up somewhere creepy, like the edge of the treeline, often next to an armed trap.
- **Broken fences and gates:** Animals escape, so someone has to round them up far from the group. Animals matter because they go quiet when the creature is near.

### Setting Up the Night

- **Marks:** Touching something it left behind (a dead crow, a strange seed) marks you. Marked players are easier for it to find that night unless they wash at the well, which takes time.
- **Scent:** Anything a player drops, from a pit or a jumpscare, stays in the field and leads the creature to them that night unless they go back for it.
- **Clues:** Footprints, claw marks, or a moved scarecrow hint at where it will hunt tonight, but only if someone notices.

### Keeping It Fair

- Daytime harm should be annoying or costly, never instantly fatal, so the day still feels like a break.
- Every disturbance has a fix, like repairing, rounding up, or washing, so it feels like a task and not just bad luck.
- Day 1 might have one broken fence; by day 6 the whole pool is in play.

The core trade-off: the more players investigate and fix during the day, the safer the night is, but that time comes out of farming.

## Crops

Prices are in coins per plot. All values are starting numbers to tune from playtest logs.

| Crop | Grows in | Seed cost | Sells for | Notes |
|---|---|---|---|---|
| Turnips | 1 day | 4 | 10 | Short and safe. Low value, steady money. |
| Pumpkins | 2 days | 10 | 25 | Low and sprawling. Unlocks on day 2. |
| Corn | 3 days | 15 | 45 | Tall from day 2, giving the creature cover. Needed for the festival. |
| Moonflowers | 1 night | 25 | 70 | Night harvest only, and they glow. Unlocks on day 3. |

- **The wild corn ring:** It’s always there and can’t be cleared, so growing no corn never removes the creature’s home. Planted corn just brings its cover closer to the house.
- **The festival quota:** The harvest festival buys corn, and delivering 8 plots of corn by the end of the season is part of winning.
- **Harvesting opens the field:** Cutting a corn patch removes that cover, so when to harvest is a choice too.

## Season and Numbers

A season is 7 days. Night 7 is the Harvest Moon, the final night. All numbers here are starting values to tune from playtest logs.

### Winning and Losing

- **The debt:** The farm owes the bank 1,200 coins. The team starts with 60 coins.
- **First payment:** 400 coins due at dawn after night 3.
- **Final payment:** The remaining 800 coins and the 8-plot corn quota, due at dawn after the Harvest Moon.
- **Win:** Make both payments and meet the quota, with at least one player alive at dawn after the Harvest Moon.
- **Lose:** Miss a payment and the bank takes the farm, ending the season. If everyone dies during the Harvest Moon, the season is also lost. A full wipe on any earlier night isn’t a loss, it just costs medical bills and farm damage.
- **Player count:** With 2 or 3 players, payments, trap counts and the disturbance budget scale down (starting point: 70% for 2 players, 85% for 3).

### Medical Bill

- 25 coins per death, but the first death each night costs 10.
- No more than 50 coins per night in total.
- The bill never takes the bank below 4 coins, the price of a turnip seed pack.

### Ramp-Up (4 Players)

| Day | Daytime disturbances | Traps set that night | Voice | New this day |
|---|---|---|---|---|
| 1 | 1 | 2 bear traps, 1 pit | Exact clips | Turnips and corn |
| 2 | 1 | 2 bear traps, 2 pits | Exact clips | Pumpkins |
| 3 | 2 | 3 bear traps, 2 pits | Exact clips | Moonflowers; marks start; first payment at dawn |
| 4 | 2 | 3 bear traps, 3 pits | Spliced clips | Mimicry gets more convincing |
| 5 | 3 | 4 bear traps, 3 pits | Spliced clips | It can break the shed lock; hallucination scares start |
| 6 | 3 | 5 bear traps, 4 pits | Spliced clips | It tests the barn doors |
| 7 | 4 | Harvest Moon: hunts all night | Spliced clips | Final payment and quota at dawn |

### Upgrades

Over the season, players unlock new seeds, upgrade tools, and expand the farm. Examples: a quiet watering can (slower, but the creature can’t hear it as far), a shed lock, walkie-talkies and batteries, brighter lanterns, more scarecrows, and new plots.

## Mechanics That Tie Farming and Horror Together

- **Noise:** Tractors, watering cans, and the barn door all make sound. Fast tools are loud; quiet tools are slow.
- **Light:** Lanterns help you work at night but make you visible from far away.
- **Crop risk vs. reward:** Moonflowers pay the most but have to be picked in the dark, and corn pays well but gives the creature cover.
- **Fences and scarecrows as defense:** You build up your farm’s protection over time, like a light tower-defense layer.
- **Splitting up:** One player waters the far field, one checks the traps, one sells at the stand. The farm is too big for a group to stay together.

## Roles (Optional, Good for 4 Players)

Still open: both the Hunter and the Tracker are candidates for the fourth role, to be decided after playtesting.

- **Farmer:** grows faster, harvests more
- **Rancher:** handles animals, which act as early warning when the creature is near
- **Mechanic:** fixes the tractor, generator, and lights, and refuels the generator faster
- **Hunter:** has a lantern or flare gun that can briefly scare the creature off but not kill it
- **Tracker:** spots trap clues like fresh dirt and glinting metal more easily, and disarms bear traps faster

## Build Plan: Four Phases

Only move on once the current phase is fun to play. Each phase has a test for “fun.”

- **Phase 1 (prototype):** One small field and the shed, one day and one night, 2 players, the creature wandering and chasing by sound, bear traps and small pits in scripted spots, the generator, and the creature playing generic pre-recorded voice lines. Done when: the day feels safe, the night feels tense, and a generic voice from the corn makes a playtester walk toward it at least once.
- **Phase 2:** Lobby voice-line recording, the creature stealing bear traps from the shed and the pegboard, death with respawn at dawn and the medical bill, and up to 4 players. Done when: hearing a friend’s recorded voice from the corn fools someone, and trap sweeps feel worth doing.
- **Phase 3:** Live clips from proximity chat, the creature favoring dead players’ voices, the Director and jumpscares, and dead players’ ghost abilities including the lantern flicker. Done when: dead players stay engaged, and the living argue over whether to trust a static voice.
- **Phase 4:** The full 7-day season with crops, the economy, upgrades, roles, payments and the corn quota. Done when: teams sometimes win and sometimes lose, and the logs show the numbers are close.
- **Fake it first:** Scripted trap spots and simple timers can stand in for smart AI until the core loop is proven.

## Engine: Godot

Decided: the game is built in Godot 4.7.

- **Cost:** Free and open source under the MIT license, with no royalties ever.
- **Testing multiplayer:** Debug > Customize Run Instances runs several copies of the game at once from the editor, which covers most solo multiplayer testing.
- **Voice chat:** Not built into Godot, but the game’s own voice chat prototype already exists (see Dependencies).

## Testing Solo

Most testing can be done alone, with group playtests at the end of each phase.

- **Multiple copies on one computer:** Use Godot’s Customize Run Instances to run two to four copies of the game at once and check that multiplayer stays in sync.
- **Bot teammates:** Simple stand-in players that walk to fields, do chores, play voice clips and can be killed. They give the creature targets and voices, so mimicry, lures and deaths can be tested without other people.
- **Recorded voices:** Your own recordings, plus a few voice lines from friends who agree to it, so the creature has more than one voice to copy.
- **Logging:** The game records each day and night: who died where, which traps were sprung, which voice lures worked, how long chores took, how much money was made, and how long players stayed inside at night. This captures much of what you would learn from watching other players, and it’s what the numbers get tuned from.
- **Debug view:** A top-down view showing the creature, its current behavior state, the Director’s tension meter, traps and players, to check the AI is behaving fairly.
- **Group playtests:** Solo testing can’t show whether the scares and voice confusion work on real people, so play with friends at the end of each phase and log those sessions too.

## Resolved Issues

How the earlier open issues were settled, and where to find each answer.

- **Players might not use in-game voice chat:** Lobby voice lines, sound mimicry, and giving in-game voice jobs Discord can’t do. Discord groups weaken mimicry but don’t break the game. See Keeping Players on In-Game Voice.
- **The day was getting crowded:** Daytime Threats was cut down to a small pool with a daily budget, and the shed check is now a one-glance pegboard. See Daytime Threats.
- **Players could just not plant corn:** A permanent wild corn ring, corn as the best day crop, and a festival corn quota. See Crops.
- **Nights needed a reason to go out:** The generator, farm damage when nobody is outside, Moonflowers, and the creature testing the barn doors late in the season. See Nights.
- **Dead players’ help might be useless:** The lantern flicker, a signal the creature can never fake. See Death and Respawning.
- **The medical bill could cause a death spiral:** A cheaper first death, a per-night cap, and a floor that always leaves seed money. See Season and Numbers.
- **A trapped player alone was stuck:** Players can now free themselves from bear traps at the cost of a slow, and pits are now small and only make you drop items. See Night Traps.
- **The win and lose conditions were vague:** A 7-day season, two debt payments and a corn quota. See Season and Numbers.

## Open Issues

Problems that still need solving, most important first.

### 1. Scope is large for a first build

Voice recording and playback, a trap-setting AI that lures players, the Director, jumpscares, a farming economy and online multiplayer add up to a lot. Addressed by the four-phase Build Plan; still worth watching as features are added.

### 2. The numbers are untested

Every price, payment and trap count is a first guess. They should be tuned from the logs once Phase 4 is playable.

### 3. The fourth role

Hunter or Tracker. To be decided after playtesting, once the team can try both.

## Dependencies

Files this design relies on. They live in the horror-game GitHub repo (github.com/SneakKestrel16/horror-game).

### Voice chat prototype (voice_chat_prototype/)

- **What it is:** The game’s voice chat system as a Godot project: proximity voice, push-to-talk or voice activation, static for dead players, and consent-based voice clips the creature can mimic.
- **Engine:** Godot 4.7 (tested on 4.7.2).
- **Main files:** addons/voice_chat/voice_chat.gd (autoload named VoiceChat), voice_speaker.gd (on each remote player), voice_mimic.gd (on the creature), voice_codec.gd (audio compression), plus a test scene, automated tests and a README.
- **Setup:** Copy the addons/voice_chat folder into the project, turn on Project Settings > Audio > Driver > Enable Input, and add voice_chat.gd as an autoload named VoiceChat. The README has full steps.
- **Used in:** Phase 2 (dead-player static) and Phase 3 (live voice clips and creature mimicry). Phase 1 uses generic pre-recorded lines instead.
- **Status:** Prototype. The audio compression and host-client network tests pass; it has not yet been tested with a real microphone. It does not yet include lobby voice-line recording, which Phase 2 needs.
