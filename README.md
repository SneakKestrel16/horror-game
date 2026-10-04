# Horror Game

A 2–4 player co-op horror game where you farm by day and get hunted by night. Something lives in the corn. It sets bear traps and pits around the farm, and it copies your friends' voices to lure you into them.

Built in **Godot 4.7**.

## What's in this repo

| Folder | What it is |
|---|---|
| `docs/Farming_Horror_Game_Concept.md` | The full design doc: core loop, creature, voice mimicry, traps, economy, season numbers, build plan and open issues. |
| `voice_chat_prototype/` | Working Godot voice chat project: proximity voice, push-to-talk, static for dead players, and consent-based clips the creature can mimic. See its own README. |

## Status

Design is settled for now. Next up is **Phase 1**, the first playable prototype:

- One small field and the tool shed
- One day and one night
- 2 players
- The creature wandering and chasing by sound
- Bear traps and small pits in scripted spots
- The generator
- Generic pre-recorded voice lines from the corn

**Done when:** the day feels safe, the night feels tense, and a generic voice from the corn makes a playtester walk toward it at least once.

The voice chat prototype isn't needed until Phase 2. It doesn't record lobby voice lines yet, which Phase 2 needs.

## Testing multiplayer on one PC

In Godot, use **Debug > Customize Run Instances** to run 2–4 copies of the game at once.
