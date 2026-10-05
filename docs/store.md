# The farm store

Seeds and upgrades, built ahead of Phase 4 (2026-10-04) at the owner's request, so that coins have
a use beyond the medical bill. The [design doc](Farming_Horror_Game_Concept.md#upgrades) names
upgrades only as examples and prices none. Every price and effect below is a first guess to tune
from playtest logs, apart from the seed prices, which are the doc's own (Crops).

## Using it

- **Opening it.** Press B within 4 m of the shipping crate, by day or at dusk. The store window
  lists seed packs and upgrades, each with a Buy button. The window closes if you walk off or night
  falls. The host takes the coins (the team's shared purse) and logs each purchase.
- **Seed packs.** A pack lands in your hands, or on the ground by the crate if your hands are full.
  Hold E (1.5 s) on a bare plot to plant one seed, then water the plot as before.
- **Crop plots stay bare once picked.** That is new: before the store, a picked plot stayed empty
  for the rest of the run.

## Seeds

A pack plants several plots. The price is the doc's seed cost per plot times the plots per pack.

| Pack | Plots | Price | Grows | Sells for (per plot) |
| --- | --- | --- | --- | --- |
| Turnip seeds | 4 | 16 | 1 grow time (60 s) | 10 |
| Pumpkin seeds | 4 | 40 | 2 grow times | 25 |
| Moonflower seeds | 2 | 50 | 1 grow time, counted only at night | 70 |

- **Moonflowers** follow the doc's "night harvest only". They grow only while it is night, glow once
  ripe (and when carried), and wilt at dawn if nobody picked them. So the 70 coins mean a trip out
  in the dark.
- **Grow times** keep the doc's ratios (turnips 1 day, pumpkins 2) on the prototype's 60-second
  grow time (`Chores.GROWTH`).
- **Unlock days are not built.** The doc unlocks pumpkins on day 2 and moonflowers on day 3, but
  the run is two days, so everything is on sale from day 1.

## Upgrades

Each upgrade is for the whole team, for the rest of the run, and is bought once (`Store.UPGRADES`).

| Upgrade | Price | Effect |
| --- | --- | --- |
| Four new plots | 60 | Clears the four overgrown plots at the far end of each field (`Farm.LOCKED_PLOTS`). |
| Bigger watering can | 20 | A fill waters 8 plots instead of 4. |
| Quiet watering can | 30 | Watering carries 3 m instead of 9 (`Game.NOISE`), but takes a 1.5 s hold: the doc's "slower, but the creature can't hear it as far". |
| Oiled crowbar | 20 | Disarming a bear trap takes 2 s instead of 4, and prying yourself free 2 s instead of 3. |
| Brighter lanterns | 25 | Lanterns light 16 m instead of 10. The creature also sees a lit lantern from 30 m instead of 24, the doc's "be seen further". |
| Shed lock | 40 | At the shed door for traps, the creature first spends 15 s breaking the lock, then the break carries 40 m. The lock is mended each dawn. |
| Walkie-talkies | 50 | A living teammate out of earshot is heard over the radio: flat, phone-band, after a burst of squelch. The creature never speaks on it, and the dead are never on it. |

- **The walkie-talkies make the radio a voice to trust.** The creature can only copy voices from the
  corn, so a call heard over the radio is always a real teammate. Inference, untested: this may
  make lures too easy to see through once the team owns radios. Batteries (in the doc) are not
  built.
- **The shed lock** is the doc's "a shed lock", with the creature breaking it. The doc's ramp-up has
  it able to break the lock only from day 5 of 7; with two days, it breaks it every night, and the
  lock buys time and a warning.

## Playtests

### 2026-10-04, solo (one window, `--dev`)

From the host's log (`2026-10-04T23-00-55.log`).

- **One purchase, the walkie-talkies,** with dev-panel coins. They need a second player to hear, so
  nothing about them was tested.
- **No seeds bought or planted.** Seeds, the other upgrades and the shed lock are still untried in
  play; only the smoke test has exercised them.
- **No errors** in the engine log.
- **Not the store:** "Fill the tension meter" was pressed 15 times and no scare followed. A full meter
  only lets a scare fire once its own condition is met: kneeling by the corn for a lunge, caught in a
  trap for a stare, alone with a friend's recording for a whisper, and the crow by chance. Solo,
  with no friend's voice, the whisper can never fire. Inference: the button reads as "scare me
  now", which it isn't; the Scares buttons below it are the direct ones.

## Not built yet

- **Scarecrows,** from the doc's list: there are none on the farm yet.
- **Batteries** for the walkie-talkies.
- **Upgrades carrying into the next season:** seasons don't exist yet.

## Code

- `scripts/store.gd`: the catalogue, buying (host), what the team owns.
- `scripts/store_panel.gd`: the window.
- `scripts/chores.gd`: planting, crops per plot, moonflower growth and wilting, upgraded hold times.
- The upgrades' effects are read through `Store.owns(id)` where they apply: `Chores`, `Creature`
  (lantern sight, the lock), `Player` (lantern) and `VoiceChat.radio_enabled` (radios).

The smoke test buys every seed and upgrade and checks each effect, the lock included.
