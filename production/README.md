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
9. **Commits:** only after QA passes the task. Commit to `main` and push. A plain sentence
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
