# Phase 3

The third build, in `game/`. It adds what the
[Build Plan](Farming_Horror_Game_Concept.md#build-plan-four-phases) asks of Phase 3 on top of
[Phase 2](phase2.md). It was started before Phase 2's group playtest and Review 2, at the
player's request, so the questions Review 2 should settle have default answers here (see
[Review 2 defaults](#review-2-defaults)), each to revisit.

## Contents

- [Running it](#running-it)
- [What is new](#what-is-new)
- [Review 2 defaults](#review-2-defaults)
- [Numbers](#numbers)
- [Playtesting](#playtesting)
- [Not in Phase 3](#not-in-phase-3)
- [Checklist](#checklist)

## Running it

As in Phase 2 (see [Running it](phase2.md#running-it)). With `--dev`, the F2 panel has a
**Scares (Director)** section to spring each scare on yourself and fill the tension meter, and
shows the meter.

## What is new

- **The Director** (`scripts/director.gd`; design doc, The Director): a tension meter fills
  through quiet stretches (full after about 2.5 minutes) and drops after a scare, a chase, a
  kill, or a little after each call. Full by day, it springs a scare on someone it can reach,
  picked at random so the pattern can't be learned. The fuller it is, the shorter the gaps
  between calls and, at night, the more the creature prowls near players.
- **Jumpscares** (design doc, Scare Moments), each logged:
  - *The lunge*: at a player kneeling within 4 m of the corn (disarming a trap),
    the stalks part beside them. Their screen cuts to black before the creature is in full view,
    they are knocked down, drop what they carry, and are wounded until dawn; it pulls back.
  - *The stare*: a player caught in a bear trap looks up to see it standing in the rows ahead,
    4 m in, watching, for 3 seconds before it is gone.
  - *The whisper*: a teammate's voice (a lobby line or a chat phrase) speaks right behind a
    player who has nobody within 10 m.
  - *The crow*: from half tension, the corn near a player rustles and a crow bursts out, a
    fake-out between real scares.
- **Wounds** (design doc, Wounds): a wounded player's sprint runs out 40% sooner, their
  footsteps carry 50% further, and at night they leave a trail the creature follows, 8 seconds
  behind them, most of the time it has nothing better to do. The HUD says so. Dawn heals.
- **The dead-voice twist** (design doc, The Dead-Voice Twist): a dead player's voice is three
  times likelier to be picked for a call, and it comes through the same static as their real
  voice does, so a living player can't tell a dead friend's warning from the creature's lure by
  sound. The log marks such calls "through static".
- **Ghosts** (`scripts/ghosts.gd`; design doc, Dead Players Stay Involved): a dead player's
  **F** flickers the light nearest them, within 8 m, that a living teammate is within 10 m of:
  a teammate's lantern or a barn lamp. It is the one signal the creature can never fake, with a
  10 s cooldown. **E** in the corn rustles it, to point at something, which the creature can
  fake. Ghosts could already drift through anything, see the creature, and talk through static.
- **Day deaths are less exact**: how long a trapped player must be alone before the creature
  comes for them is drawn afresh each time, 10 to 25 s, instead of always 15.
- **Log**: each call names each listener's tell; the lunge, stare, whisper, crow, flicker and
  rustle are all logged.

## Review 2 defaults

Review 2 was to settle these before Phase 3. Without its playtest, these are the defaults built,
each a guess to check in the next group session.

| Issue | Default | Why |
|---|---|---|
| Placing teammates for the position tell | no extra hint, as before | Doc's choice; nobody has played with others yet |
| 5. The lantern flicker needs a light | any light: lanterns and the barn lamps | The doc's suggested fix; players hide in the dark |
| 6. Three tracking systems do the same job | only the wound trail is built, as one "tracked" state with one cue (the HUD line) | Marks and scent belong to Daytime Threats (Phase 4) |
| 7. The day-death rules are a checklist | the Director varies the alone time, 10-25 s | The doc's suggested fuzziness |
| Ghosts without trap sight | unchanged: ghosts don't see traps | Check in play whether flicker and rustle are enough |

## Numbers

| What | Value | Source |
|---|---|---|
| Quiet to a full meter | 150 s | Guess |
| Tension after a scare, kill / chase / fake-out | 0 / 0.2 / 0.25 | Guess |
| Fake-outs from | half tension, 6% a check (every 2 s) | Guess |
| Lunge reach | kneeling within 4 m of the corn | Guess |
| Stare | 3 s, 4 m into the rows | Guess |
| Whisper | nobody within 10 m; 1.2 m behind | Guess |
| Wound | 40% less sprint, steps 50% louder, until dawn | Doc, Wounds |
| Wound trail | a point every 2 s, followed 8 s behind, 70% of night lurks | Guess |
| Dead voice weight | 3 times | Guess |
| Lantern flicker | ghost within 8 m of the light, teammate within 10 m, 1.5 s, 10 s cooldown | Guess |
| Night prowl chance | 25% plus 60% of the tension | Guess |
| Lure gaps | 1.3 times at no tension to 0.7 times at full | Guess |
| Alone before a day kill | 10-25 s, drawn each time | Guess (Review 2, issue 7) |

## Playtesting

The Build Plan's test: **dead players stay engaged, and the living argue over whether to trust a
static voice.**

1. Two to four people on their own machines, everyone recording or talking so there are voices.
2. Play both days. Let someone die at night on purpose if nobody does.
3. Watch the dead: do they use the flicker and rustle, and keep talking?
4. In the host's log, calls "through static" are the creature using a dead player's voice; ask
   the living whether they trusted one, and whether a flicker settled it.
5. Ask whether the day scares were spaced well, and whether being wounded changed the night.

### Solo dev session (4 October 2026)

One person on two `--dev` windows on one machine, with the dev panel's skips (host log
`2026-10-04T21-26-19.log`).

- Every scare fired from the dev panel and logged: whisper, stare, crow, and a lunge that wounded
  Farmer 1 until dawn. The wounded farmer was caught 22 s into the first night.
- The ghost flickered a barn lamp and rustled the corn; both were logged.
- Both days and the dawn screen ran without an error; the medical bill (25) was counted.
- No call came "through static": nobody recorded a clip, so the creature had only the generic
  voices. Dead voices still need a session with recordings.
- Found: the fuel drum prompt read "E: fill the game.fuel can", a bad rename in Phase 2. Fixed.

Inference: one person on two windows can't test the Build Plan's question (do the living trust a
static voice?); that still needs the group playtest.

## Not in Phase 3

The shed scare (the creature inside the shed, or the door slamming) waits for a shed door; the
own-voice whisper happens only through the rare own-voice pick; hallucinations are late season
(Phase 4). The Stalk state and animals going quiet are not built. Marks and scent are part of
Daytime Threats (Phase 4).

## Checklist

- [x] The creature favours dead players' voices, through static
- [x] The Director: tension, scare timing, prowl and lure pace
- [x] Jumpscares: lunge, stare, whisper, crow fake-out
- [x] Wounds and the night trail
- [x] Ghost abilities: lantern flicker (any light), rustling the corn
- [ ] A group playtest of Phase 2 and Phase 3 together
- [ ] Review 2, checking the defaults above
- [ ] The shed scare, once the shed has a door
- [ ] Animations for the lunge and the stare, and a knockdown the others can see
- [ ] Sounds for the scares beyond the synthesised screech and caw
