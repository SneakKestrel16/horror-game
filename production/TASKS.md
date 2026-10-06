# Tasks

The task board. Only the Director creates or reassigns tasks; the owner moves a task to
`In progress` and then `Review`; only QA sets `Done`. Rules: [README.md](README.md).

Statuses: `Waiting` (blocked on a dependency or a question), `Ready`, `In progress`, `Review`,
`Done`.

## Stage 1: ready for the group playtest

From the open items in [phase2.md](../docs/phase2.md#checklist) and
[phase3.md](../docs/phase3.md#checklist) that don't need other people. Ends with a STOP: the user
runs the group playtest of Phases 2 and 3.

Every task's acceptance criteria also include: `bash tools/check.sh` passes, `prek run
--all-files` passes from Git Bash, the change was seen running (snapshot, showcase or a two-instance
launch, named in the handoff), a handoff is written, and nothing in the privacy rules is committed.

### Animations

**S1-01 Dig and set-trap poses for the creature** · Creature & Director · In progress · depends on: none
- The creature kneels and paws at the ground while digging a pit, and crouches over a bear trap
  while setting one, in `Creature._animate` (procedural, D-006).
- Driven by replicated state only (`state` is ERRAND; add a replicated errand kind if the pose
  needs it, through a CONTRACTS.md change approved first), so every peer sees the same pose.
- An errand no longer looks like staring (phase2.md checklist). A snapshot of each pose in the
  handoff.

**S1-02 Lunge and stare poses** · Creature & Director · Ready · depends on: S1-01
- The lunge: a fast forward reach with arms out when a chase closes the gap; the stare: still,
  head tilted, arms hanging, while `state` is STARE. Both procedural, both seen on a joining peer.
- The phase3.md checklist item's animation half can be ticked.

**S1-03 A knockdown the others can see** · Gameplay · In progress · depends on: none
- When a player stumbles (`stumble_left`), other peers see them fall and get up, not just the
  player's own camera dip. Replicate what's needed (a CONTRACTS.md change approved first: likely
  `stumble_left` or a `knocked` flag added to the player's Sync props).
- Two-instance launch: player A is knocked down, player B sees it. Smoke check added by QA.

**S1-04 Players' dig and set-trap poses** · Gameplay · Ready · depends on: none
- A player digging a crop plot, setting or prying a trap, or hanging one on the pegboard kneels and
  works with their arms, from replicated state (`kneeling` is already synced; add an action kind if
  needed, through CONTRACTS.md). Seen from a second instance.

### The shed

**S1-05 A shed door** · 3D Artist · In progress · depends on: none
- A door model in `tools/blender/` matching the shed (models.md naming, 1 unit = 1 m, pivot on
  the hinge edge), rebuilt with the Blender command and checked in the showcase.

**S1-06 Hang the shed door and make it work** · Level → Gameplay · Waiting · depends on: S1-05
- Neither building has a working door today, only open doorways (CONTRACTS.md, Scale and space),
  so this is the game's first door. Level places it in the shed's doorway in `farm.gd` with a
  collider that blocks players and the creature when shut. Gameplay makes it open and close on
  E: host-owned, replicated, in the late-join snapshot, logged, and coherent with the `shed_lock`
  upgrade (a locked door stays shut to the creature until it breaks the lock). The new RPC and
  state go into CONTRACTS.md first (Director approval). Technical Artist dresses it in `looks.gd`.
- Built so the barn can reuse it later (the creature tests the barn doors from day 6, Stage 4).
- Players can shut themselves in the shed; a joining peer sees its state; the walking grid and the
  creature's errand to the pegboard still work with it open or shut.

**S1-07 The shed scare** · Creature & Director · Waiting · depends on: S1-06
- The scare the phase3.md checklist names once the shed has a door, built as the design doc
  describes it, paced by the director like the other scares, and logged.
- Ticks the phase3.md item.

### Models and textures

**S1-08 Bear trap, pit and pegboard tool models** · 3D Artist · Ready · depends on: none
- Metal bear trap (open and sprung), a pit cover if the doc's pit needs one, and the pegboard tools
  (shovel, hoe, watering can or whatever `chores.gd` hangs) modelled and textured to models.md's
  style, replacing the primitives. Showcase screenshots in the handoff.

**S1-09 Swap the trap and tool models into the game** · Technical Artist · Waiting · depends on: S1-08
- `looks.gd` uses the new models; traps show open and sprung states; nothing else changes size or
  collision. Snapshot of the shed pegboard and a set trap in the handoff.

**S1-10 Crops at each growth stage** · 3D Artist → Technical Artist · Ready · depends on: none
- A model per growth stage for each crop the game has (turnip, pumpkin, moonflower), sharing the
  plot's footprint; the Technical Artist swaps them into `looks.gd` by growth fraction.
- Ticks the phase2.md textures item. Showcase `--set=plants` screenshots.

### Sounds

**S1-11 Missing sounds** · Audio · In progress · depends on: none
- For every unchecked item in phase2.md's Sounds list that doesn't need real people: creature
  footsteps, breathing, chase screech, digging and trap-setting; footsteps on grass; prying a trap;
  harvest and selling; generator sputter, dying and refuel; barn and shed doors (shed door after
  S1-06); ambience by time of day; crows and jumpscare stingers.
- Each synthesised in `sfx.gd` (D-013: FilmCow can't be reached from the cloud; recorded takes
  are S1-18). Anything from another source is listed with its licence in QUESTIONS.md and waits
  for the user. The handoff lists each sound and how it is made. No sound files committed.
- Ticks the phase3.md scare-sounds item and the phase2.md items it covers. Levels set by ear are a
  guess until the playtest (left unchecked: "listen in a playtest").

### Build and hosting

**S1-12 An exported Windows build with sounds** · Network & Voice (with Audio) · In progress · depends on: none (D-013)
- An `export_presets.cfg` that packs `textures.json` and the recorded sounds (they live in a folder
  Godot ignores today), without committing the sound files. Whatever packing step is needed is
  scripted so it's repeatable.
- The exported build, run from a folder outside the repo, hosts and joins another instance, and
  plays recorded sounds. In the cloud: a Linux export of the same preset proves the packing with
  stand-in sound files (never committed); the Windows build is checked by the user with the real
  library. Ticks the phase2.md export item once the user has.

**S1-13 Hosting and joining over the internet** · Network & Voice · Done · depends on: none
- `docs/hosting.md`, linked from docs/README.md: the port, how the host opens it (router port
  forward) or a virtual LAN (for example Tailscale or ZeroTier) as the simpler path, how a friend
  joins, and what to check when it fails. Short enough to send to a friend.
- Checked against what `net.gd` actually listens on.

### Review

**S1-14 QA pass and smoke additions** · QA · Waiting · depends on: S1-01 to S1-13
- Smoke checks for the replicated knockdown, the shed door state and the creature's poses.
- A two-instance run of the whole farm night with the exported build. A list of what only the
  group playtest can verify, for the STOP summary.

### Naming

**S1-16 Rename the scarecrow look to strawman** · 3D Artist · Ready · depends on: none
- Per D-008: the Blender function and model file (`strawman.glb`, old one and its `.import`
  removed), `Creature.LOOKS`, the showcase sets, models.md, phase2.md and the design doc's line on
  the four looks. `--monster=strawman` works and the log says "creature look: strawman".
- No `scarecrow` identifier left except the farm object's mentions.

### Docs

**S1-17 Stale lines in the design doc and phase2.md** · Game Designer · Review · depends on: none
- Corrections only, no design change: phase2.md's Phase 4 checklist says "the corn quota" (now
  the festival quota of pumpkins); the design doc's Dependencies section says the voice chat was
  never tested with a real microphone and has no lobby recording (both done in Phase 2); the
  Economy Check's corn row, "Corn can't help" and assumption 5's "per corn plot" wait for S1-15
  and are rewritten from its results.

**S1-18 Recorded takes for the new sounds** · Audio · Waiting · depends on: S1-11, a session on the user's machine
- From the FilmCow library through `tools/get_sfx.sh`: pick recorded takes for the sounds S1-11
  synthesised where the library has a fitting one, set levels by ear, keep synthesis as the
  fallback.

### Optional, if there's time before the STOP

**S1-15 Bring the simulator up to date** · Game Designer · Ready · depends on: none
- Remove corn as a crop; make the quota 8 plots of pumpkins (the design doc's stand-in). No other
  number changes. Records the 4-player best case against the 400 payment again. Needed for Stage 2
  anyway.
