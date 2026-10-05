# Horror Game

A 2–4 player co-op horror game where you farm by day and get hunted by night. Something lives in the corn. It sets bear traps and pits around the farm, and it copies your friends' voices to lure you into them.

Built in **Godot 4.7**.

## What's in this repo

| Folder | What it is |
|---|---|
| `game/` | The game itself (Godot project). Phases 2 and 3 are built; see `docs/phase2.md` and `docs/phase3.md`. |
| `docs/` | The design doc, each phase's notes and playtest results, and gotchas; start at `docs/README.md`. |
| `voice_chat_prototype/` | The voice chat project the game's `addons/voice_chat` was copied from: proximity voice, push-to-talk, static for dead players, and consent-based clips the creature can mimic. See its own README. |

## Status

**Phase 1** ([notes](docs/phase1.md)) passed its playtests: one small field, one day and night, the creature hunting by sound, traps, the generator, and generic voices from the corn.

**Phase 2** ([notes](docs/phase2.md)) is built and has had solo playtests; it still needs one with 2–4 people on their own machines. It adds:

- A lobby where players agree to let the creature copy their voice and can record lines
- The creature calling with what players said over proximity chat, or their lobby lines
- Proximity voice chat, and a list (C) to play back or delete what is kept of your voice
- Two days and two nights, death with respawn at dawn, and the medical bill
- The pegboard: the creature steals bear traps from the shed and hides them
- Corn that reaches into the farm in ragged strips, and a planted corn patch worth cutting
- Up to 4 players

**Done when:** hearing a friend's voice from the corn fools someone, and trap sweeps feel worth doing. What is left is the checklist in [Phase 2](docs/phase2.md#checklist).

**Phase 3** ([notes](docs/phase3.md)) is built on top, ahead of Phase 2's group playtest and Review 2, with default answers for what that review should settle. It adds:

- The Director: a tension meter that spaces out scares and sets how hard the creature pushes
- Day jumpscares: a lunge at a player kneeling by the corn, a stare from the rows, a friend's voice whispering behind you, a crow bursting out
- Wounds from a lunge: less sprint, louder steps, and a trail the creature follows at night
- The dead-voice twist: dead players' voices are used more, through the same static as their real voice
- Ghosts can flicker a light near a teammate (the one signal the creature can't fake) and rustle the corn

**Done when:** dead players stay engaged, and the living argue over whether to trust a static voice. One group playtest can cover Phases 2 and 3 together.

## Testing multiplayer on one PC

In Godot, use **Debug > Customize Run Instances** to run 2–4 copies of the game at once, or run it twice from the command line with `-- --host` and `-- --join=127.0.0.1` (add `--dev` to both for the F2 developer panel).
