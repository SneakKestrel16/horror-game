# Production

How the team of agents building *Something in the Corn* works. The main session is the
**Director**; every other role is an agent in `.claude/agents/`. Agents coordinate through these
files, not memory: read the relevant ones before starting a task, update them when it ends.

| File | What it holds | Who writes it |
|---|---|---|
| [TASKS.md](TASKS.md) | The task board: ID, owner, status, dependencies, acceptance criteria | Only the Director creates or reassigns tasks; the owner updates status; QA marks Done |
| [CONTRACTS.md](CONTRACTS.md) | What more than one role depends on: ownership, data, naming, scale, network messages, authority | Director approves every change, logged in DECISIONS.md first |
| [DECISIONS.md](DECISIONS.md) | Every decision that affects another role: date, who, why | Anyone records; the Director approves |
| [QUESTIONS.md](QUESTIONS.md) | Blocking questions, addressed to a role | Anyone asks; the Director routes; the addressee answers |
| [handoffs/](handoffs/README.md) | One file per finished task | The task's owner |

The design doc ([docs/Farming_Horror_Game_Concept.md](../docs/Farming_Horror_Game_Concept.md))
is the source of truth for tone, pillars and scope. Phase notes, playtest results and checklists
stay in `docs/` (a `phase4.md` when Phase 4 starts); traps go in
[docs/gotchas.md](../docs/gotchas.md); [docs/README.md](../docs/README.md) stays the index.

## Rules every role follows

1. **Read first:** `CLAUDE.md`, the user's global rules it inherits, the design doc's sections
   your task touches, CONTRACTS.md, and your task in TASKS.md with its dependencies' handoffs.
2. **Edit only the files you own** (CONTRACTS.md, Ownership). A change needed elsewhere is a
   question in QUESTIONS.md addressed to the owner, or a task the Director creates.
3. **One task in progress per agent.** Set it to `In progress` when you start, `Review` when you
   hand it to QA. Only QA sets `Done`.
4. **Host authority:** the host owns the clock, tools, crops, traps, generator, store and
   creature; a peer owns only its player and asks the host to act (`Game._request` and the RPCs
   in CONTRACTS.md). Anything new follows the same pattern.
5. **Verify before relying:** Godot 4.7 API names and engine behaviour against the Godot docs;
   mark guesses as guesses in code and docs, and say what would settle them.
6. **Checks:** `bash tools/check.sh` passes (warnings are errors), and `prek run --all-files`
   from Git Bash. Never `--no-verify`. If a change affects what the game shows or does, run it
   and look (snapshot, showcase, or a two-instance launch) instead of reasoning from the diff.
7. **Conflicts with the design doc** go to the Director in QUESTIONS.md; don't improvise.
8. **Contracts:** don't change a contract (a shared name, data format, RPC, or ownership) without
   a Director-approved DECISIONS.md entry, before any dependent work starts.
9. **Commits:** only after QA passes the task. Commit to `main` and push (in a cloud session,
   to the session's branch instead: D-010). A plain sentence
   subject saying what changed, an explanatory body as in the git log, and the task ID in the
   body (`Task: S1-04`). No model names in commits.
10. **Privacy and consent:** the repo is public. Never commit secrets, personal data, voice
    recordings or the FilmCow sound files (`game/assets/sfx/` is gitignored). Voice mimicry stays
    consent-based: no voice is captured, kept or replayed without the player opting in, players
    can review and delete their clips, and recorded voices never get committed.
11. **Audio sources:** only FilmCow (through `tools/get_sfx.sh`) and synthesis in `sfx.gd`.
    Anything else is listed with its licence in QUESTIONS.md for the user's approval first.
12. **Numbers:** tuning changes are tested in the simulator first, made in both the sheet and the
    game, and logged in DECISIONS.md. Nobody quietly changes the economy.
13. **The fourth role** (Hunter or Tracker) stays open; build role code so either can be added.
14. **When a task ends:** write `handoffs/<task-id>.md`, add any trap to `docs/gotchas.md`, update
    the phase doc's checklist if an item is finished, and set the task to `Review`.

## Cloud sessions (D-010, D-012)

In the cloud container the checkout is `/home/user/horror-game` and these replace the Windows
commands in CLAUDE.md (the tools live in the session's scratch space and are reinstalled by the
Director if a session restarts):

| Job | Command |
|---|---|
| Checks | `GODOT=/tmp/claude-0/godot/Godot_v4.7-stable_linux.x86_64 SMOKE_PORT=<yours> bash tools/check.sh` |
| Format and lint | `/tmp/claude-0/venv/bin/gdformat --check game/scripts game/tests game/tools` and `/tmp/claude-0/venv/bin/gdlint game/scripts game/tests game/tools` (prek's hooks point at `.venv/Scripts/`, Windows only) |
| Snapshot | `xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path game --rendering-driver opengl3 res://tools/snapshot.tscn -- <args>` (OpenGL, not the game's Vulkan: lighting can differ slightly) |
| Showcase | the same, with `res://tools/showcase.tscn -- --set=...` |
| Blender | `/tmp/claude-0/venv/bin/python tools/blender/build.py -- [name ...]` (Blender 5.2.2 as the `bpy` module from PyPI) |
| Two instances | the CLAUDE.md launch lines under `xvfb-run -a`, each with `--rendering-driver opengl3`, or `--headless` when nothing needs seeing |

Not reachable from the cloud: blender.org and itch.io (FilmCow). Recorded sounds can't be fetched,
picked or heard there, so sound work is synthesis only until the user's machine (D-013). There
is no microphone and no speaker: voice and listening checks are for the user.

## Keeping usage down

Every agent run costs tokens and session time. Keep revisiting this list and add to it when a
cheaper way is found.

- **Read narrowly.** `grep -n` first, then read the lines you need (offset and limit), not whole
  files. The design doc (44 KB), phase2.md (22 KB) and CONTRACTS.md (13 KB) are read by section.
  Don't re-read a file you've already read in the task.
- **Quiet commands.** `tools/check.sh` prints one line on a pass (`CHECK_VERBOSE=1` for the full
  log). Send other long output (Blender, exports, two-instance runs) to a log file and show
  `tail`, or grep it for `ERROR|WARNING`.
- **Look once.** One snapshot or showcase picture per thing to check, at a size that shows it.
  Don't render the same view again without a change.
- **Short write-ups.** Handoffs under about 40 lines; final reports to the Director under 200
  words (branch, commit, what was done, how it was seen, what's open). The handoff carries the
  detail; don't repeat it in the report.
- **Stop early on a question.** If a contract change or a design call is needed, stop and ask
  before building, rather than building twice.
- **Director:** batch small tasks for one role into one run; give each agent a self-contained
  prompt so it needn't explore; review with `git diff --stat` and targeted diffs; QA reviews
  several finished tasks in one run; merge, push and remove a worktree (`git worktree remove`,
  `git branch -d`) as soon as its task is merged; don't start agents for work that can wait for a
  dependency.
- **Worktrees start from `main`,** not the session branch: the agent's first step is
  `git merge --ff-only <session branch>` (the Director names it in the prompt).

