# Decisions

Every decision that affects another role: date, who decided, why. Design decisions also go into
the design doc. Proposed decisions wait for the Director's (and, where the design or numbers are
concerned, the user's) approval before dependent work starts.

## D-001 · 2026-10-05 · Director · Team set-up

The team is the Director plus nine agents in `.claude/agents/`, coordinating through
`production/`. Approved.

## D-002 · 2026-10-05 · Director · File ownership

The split in [CONTRACTS.md](CONTRACTS.md#ownership), drawn from the code as it is. Points that
weren't obvious: `trap_field.gd` is split (the creature's choice of where to set traps belongs to
Creature & Director; arming, springing, state and its RPCs to Gameplay); `dev.gd` goes to Gameplay;
`game/tools/` to the Technical Artist; the export preset and `docs/hosting.md` to Network & Voice;
tests and `tools/check.sh` to QA; `CLAUDE.md`, the prek config, `docs/README.md` and
`docs/gotchas.md` to the Director. Approved.

## D-003 · 2026-10-05 · Director · Contracts record the code

CONTRACTS.md records what the code does today, including where it disagrees with the design doc
or the simulator; nothing was redesigned. Approved.

## D-004 · 2026-10-05 · Director · Stage 1 list

The tasks in [TASKS.md](TASKS.md), from the open phase2.md and phase3.md checklist items that
don't need other people. Recorded generic voice lines from real people stay out (they need other
people and raise consent questions). Approved, pending the user's go-ahead.

## D-005 · 2026-10-05 · Director · Proposed: economy in a data file

The prompt says every number is read from data, but the prices, seeds, grow times, bill and ramp
are constants in the scripts today. Proposal: move them into one data file (format in
CONTRACTS.md, Economy data) that the game reads and the simulator's Inputs sheet matches, as a
pure move with no number changed. **Proposed**; Stage 3 work, not Stage 1.

## D-006 · 2026-10-05 · Director · Proposed: animation stays procedural

The prompt gives animations to the 3D Artist, but the characters are animated in code
(`Player._animate`, `Creature._animate` rotating named joints; no AnimationPlayer, no rigs). Proposal:
keep it procedural. The script's owner writes the poses (Creature & Director for the creature,
Gameplay for players), driven by replicated properties so every peer sees them; the 3D Artist
keeps the joint names and pivots that the code relies on. **Proposed**; Stage 1 tasks S1-01 to
S1-04 assume it.
