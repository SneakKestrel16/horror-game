# Farming Horror Game: Design Concept

A multiplayer game where players grow and farm crops while being hunted. The combo works because farming naturally creates the tension horror needs: crops tie you to specific spots, the work is noisy and repetitive, and you can’t finish it all with everyone huddled together.

**The pitch:** a farm under siege. Traps, crops and the day/night economy are the hook; voice mimicry supports it rather than leading it, since other games already sell AI voice copying (see Resolved Issues).

**Format:** 2 to 4 player co-op. The monster is AI-controlled, so every player is on the same side against it. The creature and the money targets scale with the number of players.

## The Core Loop

**Day (safe-ish, about 8 to 10 minutes):** Players glance at the shed pegboard, sweep for and disarm traps left overnight, plant, water, harvest, fix what the creature broke, and sell at the town stand. This is the cozy part, and it’s where you build up resources and stakes.

**Dusk (warning phase, about 1 minute):** The light fades, animals go quiet, and players rush to finish chores, get valuable crops harvested, and top up the generator.

**Night (the hunt, about 5 minutes):** The creature comes out of the corn, hunts, and sets traps for the next day. Moonflowers can only be harvested at night and are worth far more, and the generator needs refueling partway through. Nobody can sit safely in the barn all night (see Nights).

**Dawn:** Survivors cash in. Anyone who died loses what they were carrying, the medical bill is paid, and the farm takes damage where the creature roamed, more if nobody was outside to stop it. After a full wipe the creature had the farm to itself: farm damage is doubled and it sets extra traps for the morning.

The contrast between peaceful daytime farming and terrifying nights is the hook. The cozy part makes players care, and the horror part threatens what they built.

## The Creature: Something in the Corn

You never see it clearly. It lives in the wild corn that rings the farm, a field players can’t cut down, so it always has somewhere to hide. Corn the players plant extends its hunting ground: tall crops block your view, so the crops you plant literally shape where it can hunt. Corn is the best-paying day crop and the harvest festival demands it, so the team can’t simply refuse to grow it (see Crops). It hunts with two tools: players’ own voices and the traps it sets at night.

**What players see of it:** by day only parts and motion: a head above the corn, an arm, stalks parting. A clear full view comes only at night during a chase, in the dark, and never for more than a second. Lunges cut to black or a knockdown before it is in full view, and the stare and hallucinations are distant silhouettes.

### How It Hunts

- **Hearing:** Its main sense. Tools, footsteps, doors and talking all make noise, and louder sounds carry further.
- **Sight:** Short range only. It spots players carrying light or standing in open ground, but tall corn blocks its view just as it blocks yours.
- **Scent:** It can track marked players and anything a player dropped during the day (see Daytime Threats).

### Behavior States

- **Lurk:** Moves through the corn, sets traps at night, and gathers voice clips.
- **Lure:** Plays a mimicked voice or sound from cover, usually near an armed trap or a player who is alone.
- **Stalk:** Follows one player from cover, getting closer. Animals nearby go quiet.
- **Chase (night, or a day kill):** Breaks cover and runs a player down. It loses them if they reach a lit building or break its line of sight for a few seconds.
- **Retreat:** After a jumpscare, a kill, or a hit from the Hunter’s flare, it pulls back into the corn for a while.
- **By day:** It Lurks, Lures, Stalks and jumpscares, and kills only in the rare cases below (see Day Deaths).

### Day Deaths

Deaths by day are rare, and always the player’s own mistake. The creature can kill by day only when one of these is true:

- A player is **alone, marked and deep in the corn**: no teammate within earshot, carrying a mark they didn’t wash off, and well inside the rows rather than at the edge.
- A player is **stuck in a bear trap with nobody nearby**: no teammate close enough to help pry them free.

Almost nobody will die by day, but everyone will know it can happen, and that is enough. A day death counts like a night one: out until dawn and on the medical bill.

### Wounds

A day scare hurts the night. A player who is jumpscared is **wounded** until dawn: their sprint runs out sooner, their footsteps carry further, and at night they leave a trail the creature can follow. The scare isn’t fatal, but it can kill them hours later. Starting values: 40% less sprint, footsteps heard 50% further, and the trail lasts until dawn. A second scare while wounded changes nothing, so one bad day doesn’t pile up.

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

- **Tells:** Each mimicked voice has at most one small giveaway, picked at random (a faint echo, a slightly wrong pitch, a missing radio crackle), and about a third have none. The one clue that never goes away is the voice coming from somewhere the teammate can’t be. Players place teammates by their real proximity voice, by sight and lanterns, and by radio; there is no extra hint, so a teammate who is far away and quiet can’t be placed, and the only way to be sure is to ask, which feeds the creature. Check this again after Phase 2’s playtest: if players can never use this tell, add a light hint such as a whistle or lanterns visible at a distance.
- **Passwords:** Teams can agree on a code word, but the creature can pick that up too if someone says it near it.
- **Staying quiet:** Talking less gives it less to copy, but it also makes teamwork harder.
- **Walkie-talkies:** A craftable radio that the creature can’t fake, but it runs on limited batteries and fills with static when the creature is near, so “was that you?” doesn’t always get through.
- **The lantern flicker:** A dead teammate’s one signal the creature can never fake (see Death and Respawning).

### Keeping Players on In-Game Voice

Groups of friends often talk on Discord or a party chat instead. The design gives in-game voice real jobs so it’s worth using, and makes sure the creature still has voices if a group doesn’t.

- **Lobby voice lines:** Before a match, each player can record a short fixed list of lines, such as “over here,” “help me,” “come look at this” and their teammates’ names, each two or three times with a prompt to say it urgently or scared, so they sound like the game and not the menu. The creature always has clips to use. This is opt-in, and players can hear their recordings back.
- **Proximity chat carries position:** In-game voice is 3D, so it’s the only way to hear where a teammate is and how far away.
- **Radios run on in-game chat:** Long-range talk only works through craftable walkie-talkies, so coordinating across the farm needs the in-game system.
- **The dead are only heard in-game:** Dead players’ static voices exist only in proximity chat.
- **Fallback voices:** Players with no recordings and no live clips get generic pre-recorded voices, so the mechanic never fully switches off.
- **Say it up front:** The main menu and lobby recommend in-game voice chat as the intended way to play.
- **Accepted trade-off:** A group on Discord will see through the voices more easily. That weakens mimicry but doesn’t break the game, since traps, scares and the night still work.

### Build Notes

- **Lobby lines first:** Record lobby voice lines and replay them from the creature’s position. Live clips from proximity chat followed in Phase 2, since lobby lines came out calm in its playtest and speech in the moment doesn’t; splicing comes later.
- **Live clips:** Only push-to-talk speech is kept, at most 3 seconds a clip. Each player can see and delete their kept clips from the pause menu, and the voice block from lobby lines applies. There is no word filter, since that would need speech-to-text.
- **Fallback:** Players with mics off, or who opt out, get pre-recorded generic lines instead.
- **Consent:** Tell players up front that the game records their voice for this, keep the clips only for that match, and include an opt-out setting. Any player can also block their voice from replay, entirely or to players they choose. Fixed lobby lines can’t carry slurs or private remarks; live clips can, which is still open.

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
- **Returning traps:** Disarmed bear traps can be carried back to the shed, which takes time but stops the creature from reusing them. Any bear trap not hanging on the pegboard at nightfall is the creature’s to take, wherever it is, so hoarding traps only hands them over. A trap kept inside a lit building is simply gone by morning, with no sign of how: the creature still never enters a lit building while anyone can see it.

### Finding and Disarming

- **Clues:** Fresh dirt near pits, bent stalks, or a glint of metal show where traps might be, but only to players who look closely.
- **Disarming:** Bear traps need a tool and a few seconds of kneeling still in the corn. Pits are filled in with a shovel.
- **Spotting:** Disarming is safer with a teammate watching, which pulls two players off farming.

### The Lure Combo

During the day, the creature uses a teammate’s voice to call players toward rows where traps are still armed. A player who checked that row in the morning knows it’s safe; a player who didn’t gets caught. This rewards teams that split up their trap sweeps and talk about which rows are clear, which in turn gives the creature more voice clips to use.

### Rules

- **Rarely lethal by day:** A trap sprung during the day holds, slows, marks, or costs you items. It only kills if the player is stuck in it with nobody nearby (see Day Deaths).
- **Deadly at night:** Traps that are still armed when night falls become far more dangerous, since a trapped player is easy prey.
- **Ramp up:** A few traps on night one, more and better-hidden ones as the season goes on (see Season and Numbers).

## Nights

Hiding in the barn all night is never fully safe and never free. Nights are short so fear doesn’t turn into boredom, and there is always a reason for someone to go out.

- **The generator:** The barn and farmhouse lights run on a generator, and the creature won’t enter a lit building. Fuel runs low partway through the night, and the fuel drum is outside by the shed. Someone has to go.
- **The unattended farm:** The longer nobody is outside, the more freely the creature roams, and the more crops and fences are wrecked by dawn.
- **Moonflowers:** The most valuable crop only opens at night and can only be harvested in the dark. They glow faintly, so whoever picks them is easy to see.
- **It tests the doors:** From day 6, if every player stays inside, the creature starts working at the barn doors, so staying put stops being safe.

## Jumpscares

The creature almost never kills during the day (see Day Deaths), but it can still terrify. The game never tells players the day is safe; they learn it, and doubt it. A daytime jumpscare knocks the player down, makes them drop what they’re carrying, and leaves them wounded until dawn (see Wounds), then the creature vanishes back into the corn.

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
- **Make them cost something:** Dropping items and the wound until dawn mean a scare matters for the game, not just for the moment, and dropped items leave a scent for the night.
- **Let the Director time them:** The tension meter decides when a scare is due and randomizes where, so players can’t learn the pattern.

## Death and Respawning

Death should matter without leaving anyone bored for long.

### Out Until Dawn

- **Respawn at dawn:** A player killed at night stays dead for the rest of that night and comes back at dawn with the survivors.
- **Medical bill:** Each death costs the team money at dawn, so protecting each other directly protects the farm. To stop a death spiral, the first death each night is cheaper, the bill has a cap per night, and it never takes the bank below the price of a turnip seed pack, so the team can always plant the next day (numbers in Season and Numbers).

### Dead Players Stay Involved

- **Ghost spectating:** Dead players can follow their teammates and see the creature, but not traps: a ghost who saw every trap could read out the whole morning sweep. This may need reworking once Phase 3 shows how engaged ghosts stay; options then include ghosts pointing at a trap with the lantern flicker, or seeing only traps set after they died.
- **The lantern flicker:** A dead player can make a lantern near a living teammate flicker. It’s the one signal the creature can never fake. It has a short cooldown so it stays meaningful.
- **Rustling the corn:** Dead players can also rustle stalks to point at something, but the creature can fake that.
- **Static voices:** Living players can still hear dead teammates in proximity chat, but only through heavy static.

### The Dead-Voice Twist

Once a player dies, the creature is more likely to mimic their voice. Combined with the static, this means a dead teammate’s real warning and the creature’s fake one can sound alike. The flicker is the tiebreaker: a static voice backed by a flickering lantern is a real teammate, and a voice with no flicker might be the creature. The dead player is trying to help, the creature is trying to lure, and the living have to decide who to trust.

## Daytime Threats

The monster rarely kills during the day (see Day Deaths), but it can still do harm. Traps, voice lures and jumpscares already fill most of the day, so other daytime harm is kept to a small pool. The creature gets a daily disturbance budget, a fixed number of these it can spend each day, rising over the season.

### Sabotage Pool

- **Trampled crops:** A few plants are destroyed where it roamed overnight, more if nobody was outside at night.
- **Stolen tools:** A watering can or hoe goes missing and turns up somewhere creepy, like the edge of the treeline, often next to an armed trap.
- **Broken fences and gates:** Animals escape, so someone has to round them up far from the group. Animals matter because they go quiet when the creature is near.

### Setting Up the Night

- **Marks:** Touching something it left behind (a dead crow, a strange seed) marks you. Marked players are easier for it to find that night unless they wash at the well, which takes time.
- **Scent:** Anything a player drops, from a pit or a jumpscare, stays in the field and leads the creature to them that night unless they go back for it.
- **Clues:** Footprints, claw marks, or a moved scarecrow hint at where it will hunt tonight, but only if someone notices.

### Keeping It Fair

- Daytime harm should be annoying or costly, and only fatal through the player’s own mistakes (see Day Deaths), so the day still feels like a break.
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

- **Plots and labor:** The farm starts with 16 plots, and upgrades add up to 24. Planting, watering and harvesting are each a hold of a few seconds, so one player tends about 6 plots a day and nobody can work the whole farm alone. Moonflowers only grow in a 4-plot moonflower bed. Plots are the bottleneck, which makes corn the best crop per plot.
- **The wild corn ring:** It’s always there and can’t be cleared, so growing no corn never removes the creature’s home. Ragged strips of it reach in toward the buildings and the fields, so planted corn joins it and brings its cover closer to the house; planted corn cut off from every strip would be an island the creature can’t reach by day (Phase 2 playtest).
- **The festival quota:** The harvest festival buys corn, and delivering 8 plots of corn by the end of the season is part of winning.
- **Harvesting opens the field:** Cutting a corn patch removes that cover, so when to harvest is a choice too.

## Season and Numbers

A season is 7 days. Night 7 is the Harvest Moon, the final night. All numbers here are starting values to tune from playtest logs.

### Winning and Losing

- **The debt:** The farm owes the bank 1,200 coins. The team starts with 60 coins.
- **First payment:** 400 coins due at dawn after night 3.
- **Final payment:** The remaining 800 coins, due at dawn after the Harvest Moon.
- **The festival cart:** On the Harvest Moon the corn quota leaves by cart. The team loads 8 plots of corn onto the festival cart and gets it out the farm gate before dawn, under attack all night.
- **Win:** Make both payments and get the festival cart out the gate, with at least one player alive at dawn after the Harvest Moon.
- **Lose:** Miss a payment and the bank takes the farm, ending the season. If everyone dies during the Harvest Moon, the season is also lost. A full wipe on any earlier night isn’t a loss, it just costs medical bills and farm damage.
- **Player count:** With 2 or 3 players, payments, trap counts and the disturbance budget scale down (starting point: 70% for 2 players, 85% for 3).

### Medical Bill

- 50 coins per death, but the first death each night costs 25.
- No more than 120 coins per night in total (10% of the debt).
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
| 7 | 4 | Harvest Moon: hunts all night | Spliced clips | Load and run the festival cart; final payment at dawn |

### Length and Saving

- **Dawn saves:** The host’s game saves at every dawn, so a season can be played over several evenings.
- **Short season:** A 3-day option for a single sitting, with the debt and corn quota scaled down.

### The Next Season

Upgrades and plots carry into the next season. The debt grows, and each new season the creature gains one new trait, for example copying tools better or setting more pits, so the farm players built is worth defending again.

### Economy Check

The [Farm Economy Simulator](Farm_Economy_Simulator.xlsx) spreadsheet tests the money side of this doc: crops, plots, labor, payments, the medical bill and the corn quota. Its sheets are **Inputs** (every number here, to change), **Season Plan** (plan seven days of planting and deaths; it flags broken rules and says whether the season is won), **Crop Value** and **Player Scaling**.

It has to assume what this doc doesn’t pin down:

1. “Grows in 1 day” means plant today, harvest and sell tomorrow.
2. Moonflowers are planted by day in the 4-plot bed, harvested that night and sold at dawn, so they count toward a payment due that dawn.
3. A harvested plot can be replanted the same day; crops not ready by day 7 earn nothing.
4. Each planted field plot and each moonflower costs one unit of labor (6 per player per day); trap sweeps cost nothing extra.
5. The festival pays 45 per corn plot on the cart (the doc gives no price), paid before the final payment.
6. Payments, traps and disturbances scale with team size; the moonflower bed and the medical bill don’t.

What it shows:

| Crop | Profit per harvest | Profit per plot per day |
|---|---|---|
| Turnips | 6 | 6 |
| Pumpkins | 15 | 7.5 |
| Corn | 30 | 10 |
| Moonflowers | 45 | 45 (per night, 4 plots only) |

| | 2 players | 3 players | 4 players |
|---|---|---|---|
| Field plots the team can tend (after the moonflower bed) | 8 | 14 | 16 |
| Moonflower profit per night | 180 | 180 | 180 |
| Total owed | 840 | 1,020 | 1,200 |
| Share of the debt moonflowers alone can cover | 107% | 88% | 75% |

- **The best case misses the first payment.** With 4 players and no deaths, turnips on every plot for days 1 to 3 and moonflowers from day 3, the team has about 362 coins at dawn after night 3, against 400 owed. Corn can’t help: anything planted on day 1 isn’t ready until day 4. The same plan then makes the final payment with 426 to spare, and moonflowers bring in 57% of all its income.
- These results are open issues 2 to 4 below.

### Upgrades

Over the season, players unlock new seeds, upgrade tools, and expand the farm (up to 24 plots). Examples: a quiet watering can (slower, but the creature can’t hear it as far), a shed lock, walkie-talkies and batteries, brighter lanterns, more scarecrows, and new plots.

A first set is built ahead of Phase 4: a store at the shipping crate selling seed packs and seven of these upgrades, with prices still to tune ([The farm store](store.md)). Walkie-talkies carry only real teammates’ voices, since the creature copies voices only from the corn.

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

A review sits between each phase and the next. It starts once the phase passes its test:

1. Read the phase’s playtest logs and notes.
2. Add every new problem they show to Open Issues.
3. Settle the open issues the next phase depends on (listed in each review below), and any others that are now answerable. Move each settled one to Resolved Issues and update the sections it touches.
4. Start the next phase only when nothing it depends on is still open.

- **Phase 1 (prototype):** One small field and the shed, one day and one night, 2 players, the creature wandering and chasing by sound, bear traps and small pits in scripted spots, the generator, and the creature playing generic pre-recorded voice lines. Done when: the day feels safe, the night feels tense, and a generic voice from the corn makes a playtester walk toward it at least once. Passed after two playtests, which led to reworked lures, fuel runs and a more spread-out farm; it uses a 6-minute day because it has only one small field (see [Phase 1 prototype](phase1.md)).
- **Review 1 (done):** Before Phase 2 adds recorded voices, the pegboard and the medical bill, it settled mimicry as a supporting hook, lobby recording, voice tells, bear trap hoarding and the cost of death (see Resolved Issues).
- **Phase 2:** Lobby voice-line recording and live clips from proximity chat (brought forward from Phase 3 after its first solo playtest), the creature stealing bear traps from the shed and the pegboard, death with respawn at dawn and the medical bill, and up to 4 players. Done when: hearing a friend’s recorded voice from the corn fools someone, and trap sweeps feel worth doing. Built in `game/` over two days and two nights. Solo playtests added corn strips reaching into the farm and a planted corn patch (see Resolved Issues); it still needs a playtest with 2-4 people on their own machines, and what is left before Review 2 is the checklist in [Phase 2](phase2.md#checklist).
- **Review 2:** Before Phase 3 adds ghosts and jumpscares, settle what Phase 2 turned up, check whether players could place a teammate well enough to use the position tell (see How Players Fight Back), the lantern flicker’s light (issue 5), one tracked state (6) and fuzzier day-death rules (7), and check from its playtest whether ghosts without trap sight will have enough to do. Not yet held: Phase 3 was built first on default answers to these (see [Phase 3](phase3.md#review-2-defaults)), so the review checks those defaults instead.
- **Phase 3:** The creature favoring dead players’ voices, the Director and jumpscares, and dead players’ ghost abilities including the lantern flicker. Done when: dead players stay engaged, and the living argue over whether to trust a static voice. Built in `game/` ahead of Phase 2’s group playtest, at the player’s request; one group session can test both (see [Phase 3](phase3.md)).
- **Review 3:** Before Phase 4 builds the season, settle what Phase 3 turned up, what “grows in” means and the first payment (issue 2), moonflowers’ share (3), player scaling (4) and the Harvest Moon’s length (8), testing each in the Farm Economy Simulator.
- **Phase 4:** The full 7-day season with crops, the economy, upgrades, roles, payments and the corn quota. Done when: teams sometimes win and sometimes lose, and the logs show the numbers are close.
- **Review 4:** Tune the numbers from the Phase 4 logs (issue 9), pick the fourth role once teams have tried both (10), and settle whatever is still open before calling the game feature-complete.
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
- **Death cost too little** (Review 1): a bill of 50 per death (first 25, cap 120 a night) and, after a full wipe, double farm damage and extra traps. See Medical Bill and The Core Loop.
- **Bear traps could be hoarded** (Review 1): any trap off the pegboard at nightfall is the creature’s, wherever it is. See The Tool Shed.
- **Voice tells could be learned** (Review 1): random, subtle tells, some fakes with none, and radios that jam near the creature. See How Players Fight Back.
- **Mimicry was not a unique hook** (Review 1): MIMESIS (ReLU Games, published by KRAFTON) already sells AI voice copying, so the farm under siege is the pitch and mimicry supports it. See the opening.
- **Lobby recordings sounded calm and could carry anything** (Review 1): a fixed list of lines, each recorded a few times with an urgent prompt, and a block on replaying your voice. See Build Notes. Live clips are still open.
- **There was no limit on plots or labor:** 16 plots growing to 24, chores that take time, and a 4-plot moonflower bed. See Crops.
- **Little was at stake until the Harvest Moon:** a higher medical bill, a day the game never calls safe, rare day deaths from the player’s own mistakes, day scares that wound until dawn, and a final night spent running the festival cart out the gate. See Season and Numbers and Jumpscares.
- **A season was long with no save:** dawn saves and a 3-day short season. See Length and Saving.
- **Live clips could carry anything:** push-to-talk only, 3 seconds at most, reviewable and deletable, and blockable. See Build Notes.
- **The creature was seen too often:** glimpse rules for every scare. See The Creature.
- **There was no reason to play a second season:** the farm carries over, the debt grows, and the creature gains a trait. See The Next Season.
- **Traps in a lit building contradicted “never enters a lit building”:** a trap kept in one is simply gone by morning, unexplained. See The Tool Shed.
- **Placing a teammate for the position tell:** no extra hint; proximity voice, sight, lanterns and radios do it, and a quiet teammate far away is meant to be uncertain. To be checked again in Review 2. See How Players Fight Back.
- **Dead players saw every trap:** ghosts no longer see traps, for now; it may need reworking after Phase 3. See Ghost spectating.
- **Lures repeated from one spot** (Phase 1 playtest): calls now move with the target, avoid recent spots and lead on whoever approaches. See [Phase 1 prototype](phase1.md).
- **The lit barn was a sure refuge** (Phase 1 playtest): fuel lasts too little to hide all night, and the creature waits along the fuel run. See Nights and [Phase 1 prototype](phase1.md).
- **Lobby lines came out calm** (Phase 2 solo playtest): people read them in a neutral voice whatever the prompt. The creature now mostly calls with live clips of what players said over voice chat, brought forward from Phase 3; lobby lines are optional. See Build Notes and [Phase 2](phase2.md).
- **Nothing drew players into the corn** (Phase 2 solo playtest): the wild corn was a plain ring, and planted corn in the field would have been an island the creature couldn't reach by day. Ragged strips now join the ring to the buildings and the planted corn, which sells for far more than turnips. See Crops and [Phase 2](phase2.md).
- **The creature ignored the lights going out** (Phase 2 solo playtest): it kept digging a pit 10 m away. The generator dying is now a noise the whole farm hears, and it comes to look. See Nights and [Phase 2](phase2.md).

## Open Issues

Problems that still need solving, most important first.

### 1. Scope is large for a first build

Voice recording and playback, a trap-setting AI that lures players, the Director, jumpscares, a farming economy and online multiplayer add up to a lot. Addressed by the four-phase Build Plan; still worth watching as features are added.

### 2. The first payment may be out of reach, and “grows in” is undefined

The doc never says whether “grows in 1 day” means plant today and sell tomorrow, or plant in the morning and sell that evening. Under the first reading the best possible 4-player start reaches about 362 coins by dawn after night 3, short of the 400 payment (see Economy Check). Under the second, the numbers change completely. Settle the reading first, then check the first payment against it. Needs settling before Phase 4.

### 3. Moonflowers carry the whole economy

Moonflowers earn about 45 per plot per night, against 10 for corn and 6 for turnips, and over a season they can cover about three-quarters of a 4-player debt on their own. Daytime farming, the cozy part meant to build stakes, then matters little for money. That may be intended, as a strong push to go out at night; if not, cut moonflower profit or raise day-crop value. Needs settling before Phase 4.

### 4. Player-count scaling runs backwards

Payments scale down for smaller teams but the 4-plot moonflower bed doesn’t, so 2 players get the same 280 coins a night from it while owing only 280 for the first payment. On paper a 2-player team makes the first payment more easily than 4 players do, and moonflowers alone can cover 107% of a 2-player debt. Scale the bed, its price or the payments differently. Needs settling before Phase 4.

### 5. A few rules contradict each other

- **The lantern flicker needs a light:** a dead player can only flicker a lantern near a living one, but carrying a light makes you visible, so the one unfakeable signal is missing exactly when players go dark to hide. Letting it work on any light (barn bulbs, porch lights, the moonflower glow) would fix that. Needs settling before Phase 3.

### 6. Three tracking systems do the same job

Marks, scent from dropped items and the wound trail all mean “the creature finds you more easily tonight.” Players won’t keep them apart; they’ll just feel “it found me.” Merge them into one “tracked” state with several causes and one visible cue, such as a smell or a stain on your character’s hands. Needs settling before Phase 3, which brings marks and wounds.

### 7. The day-death rules are a checklist

A day death needs a player alone, marked and deep in the corn, or stuck in a bear trap with nobody near. That is fair, but exact: someone will post it within a week of launch, and the day goes from “never called safe” to provably safe. Keep the rule, but let the Director bend it now and then: some fuzziness about how deep “deep” is, or a rare exception after a very long quiet stretch. The fear lives in what players aren’t sure of. Needs settling before Phase 3, which brings the Director.

### 8. The night may be too short for everything in it

A refuel run, moonflower harvesting, door testing from day 6 and, on the last night, the whole festival cart run all have to fit in 5 minutes. Short nights suit days 1 to 3; the Harvest Moon could run longer, or end when the cart gets out rather than on a timer. Needs settling before Phase 4.

### 9. The numbers are untested

Every price, payment and trap count is a first guess. They should be tuned from the logs once Phase 4 is playable.

### 10. The fourth role

Hunter or Tracker. To be decided after playtesting, once the team can try both. If ghosts are ever given sight of traps again (see Ghost spectating), the Tracker gets much weaker, since dead players would do its job. And if the Tracker wins, the team has nothing that drives the creature off except lit buildings, since the Hunter’s flare goes with it.

## Dependencies

Files this design relies on. They live in the horror-game GitHub repo (github.com/SneakKestrel16/horror-game).

### Voice chat prototype (voice_chat_prototype/)

- **What it is:** The game’s voice chat system as a Godot project: proximity voice, push-to-talk or voice activation, static for dead players, and consent-based voice clips the creature can mimic.
- **Engine:** Godot 4.7 (tested on 4.7.2).
- **Main files:** addons/voice_chat/voice_chat.gd (autoload named VoiceChat), voice_speaker.gd (on each remote player), voice_mimic.gd (on the creature), voice_codec.gd (audio compression), plus a test scene, automated tests and a README.
- **Setup:** Copy the addons/voice_chat folder into the project, turn on Project Settings > Audio > Driver > Enable Input, and add voice_chat.gd as an autoload named VoiceChat. The README has full steps.
- **Used in:** Phase 2 (dead-player static) and Phase 3 (live voice clips and creature mimicry). Phase 1 uses generic pre-recorded lines instead.
- **Status:** Prototype. The audio compression and host-client network tests pass; it has not yet been tested with a real microphone. It does not yet include lobby voice-line recording, which Phase 2 needs.
