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
keeps the joint names and pivots that the code relies on. **Approved by the user** (Q-001).

## D-007 · 2026-10-05 · User · The season numbers wait for Stage 3

The game keeps its 2 days, every seed from day 1, 60-second growth and 0 starting coins until
Stage 3 builds the 7-day season; nobody changes them in Stage 1 (Q-002).

## D-008 · 2026-10-05 · User, Director · The scarecrow look becomes the strawman

"Scarecrow" stays the name of the Phase 4 farm object; the creature look is renamed `strawman`
everywhere it is an identifier (the model, `Creature.LOOKS`, `--monster=`, the showcase, the log
line, models.md, phase2.md) and in the design doc's description of the looks (Q-003). Task S1-16.
The 3D Artist does the whole rename, including the one-word edits in `creature.gd`,
`game/tools/showcase.gd` and the docs, which is approved here as a one-off exception to ownership.

## D-009 · 2026-10-05 · Director · Agents work in separate worktrees

Agents run in parallel, each in its own git worktree, and commit their task on the worktree's
branch (never `main`, never pushed). The Director merges a branch into `main` and pushes after QA
passes it. `tools/check.sh` takes `SMOKE_PORT` so parallel checks don't fight over port 7791.
Worktrees have no `.venv` and no recorded sounds: agents call the main checkout's
`.venv/Scripts/gdformat` and `gdlint`, and the Director runs prek when merging.

## D-010 · 2026-10-06 · Director · Cloud sessions work on a branch

Some sessions run in a cloud container rather than on the user's Windows machine. There the
checkout is `/home/user/horror-game`, work is committed to the session's assigned branch (not
`main`) and pushed for the user to merge, Godot 4.7 is a downloaded Linux binary passed to
`tools/check.sh` through `GODOT`, and gdformat and gdlint come from a venv's `bin/` (prek.toml's
`.venv/Scripts/` paths are Windows-only, so prek's gdformat and gdlint hooks are run by hand
there). Blender is not available in the cloud: 3D Artist tasks that rebuild models wait for a
session on the user's machine, or the user runs the build command. Nothing else in the rules
changes.

## D-011 · 2026-10-06 · Director · The shed door is the game's first door

S1-06 assumed it would open and close "like the barn doors", but neither building has a door, only
an open doorway. The task now builds the first door (and is written so the barn can reuse it in
Stage 4) and must sit with the `shed_lock` upgrade. Its RPC and state are a contract change the
Gameplay Programmer proposes in CONTRACTS.md before building.

## D-012 · 2026-10-06 · Director · Blender runs in the cloud through bpy

blender.org is blocked in the cloud, but Blender 5.2.2 installs from PyPI as the `bpy` module and
runs `tools/blender/build.py` unchanged. Checked: the shed and generator rebuild byte-identical to
the committed files, and the iron texture rebakes to a mean pixel difference of 0.02 (JPEG noise).
The barn differs between two runs of its own (randomness in its script, not the cloud). This
replaces D-010's note that Blender tasks wait for the user's machine. Commands in README.md.

## D-013 · 2026-10-06 · User, Director · Stage 1 goes ahead in the cloud; sounds split

The user approved D-011 and the start of Stage 1, and asked that GitHub be kept up to date: every
task that passes QA is merged into the session branch and pushed at once. FilmCow can't be
reached from the cloud, so S1-11 covers the missing sounds by synthesis, and choosing recorded
FilmCow takes for them is a new task, S1-18, for a session on the user's machine. S1-12 builds the
packing step now and is tested with stand-in files; the user checks it with the real library.
