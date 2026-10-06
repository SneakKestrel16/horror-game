# Contracts

What more than one role depends on, recorded from the code as it stood at commit `91c5250`
(2026-10-05). This records what exists; it is not a redesign. Changing anything here needs a
Director-approved entry in [DECISIONS.md](DECISIONS.md) before dependent work starts.

## Contents

- [Ownership](#ownership)
- [Scale and space](#scale-and-space)
- [Authority](#authority)
- [Network messages](#network-messages)
- [Economy data](#economy-data)
- [Other tuning](#other-tuning)
- [Assets and naming](#assets-and-naming)
- [Animation](#animation)
- [Sounds](#sounds)
- [Logs](#logs)

## Ownership

One owner per file. Shared files are split by function, and an edit to one is coordinated through
the Director so two roles never have it in progress at once.

| Path | Owner |
|---|---|
| `docs/Farming_Horror_Game_Concept.md` (content), `docs/Farm_Economy_Simulator.xlsx`, `docs/store.md` | Game Designer |
| The doc's Build Plan order, `production/` (except handoffs) | Director |
| `game/scripts/creature.gd`, `director.gd` | Creature & Director Designer |
| `game/scripts/trap_field.gd`, AI side: `plan_night`, `plan`, `next_order`, `take_from_board`, `fulfil`, `needs_board`, `finish_night`, `RAMP`, `WIPE_EXTRA`, `SPACING`, `ON_PATH`, `UNSEEN` | Creature & Director Designer |
| `game/scripts/trap_field.gd`, player side: `check`, `arm`, `set_state`, `set_board`, `armed_positions`, `snapshot`/`apply_snapshot`, the RPCs, `SLOTS`, `BEAR_REACH`, `PIT_REACH` | Gameplay Programmer |
| `game/scripts/farm.gd`, `game/scenes/game.tscn` | Level Designer |
| `game/scripts/game.gd`, `player.gd`, `chores.gd`, `store.gd`, `store_panel.gd`, `hud.gd`, `ghosts.gd`, `main_menu.gd`, `dev.gd`, `game/scenes/main_menu.tscn` | Gameplay Programmer |
| `game/scripts/net.gd`, `lobby.gd`, `voice_bank.gd`, `clip_list.gd`, `game/addons/voice_chat/`, `game/export_presets.cfg` (new), `docs/hosting.md` (new) | Network & Voice Programmer |
| `tools/blender/`, `game/assets/models/`, `game/assets/textures/` (with `textures.json`), `docs/models.md` | 3D Artist |
| `game/scripts/looks.gd`, `dress.gd`, `game/assets/shaders/`, `game/tools/` (showcase, snapshot) | Technical Artist |
| `game/scripts/sfx.gd`, `tools/get_sfx.sh`, `game/assets/voices/`, the Sounds lists in the phase docs | Audio Designer |
| `game/tests/`, `tools/check.sh`, the Playtesting sections of the phase docs | QA / Reviewer |
| `CLAUDE.md`, `prek.toml`, `tools/requirements.txt`, `docs/README.md`, `docs/gotchas.md` | Director (anyone may add a gotcha) |

Not ours: `voice_chat_prototype/` (a separate test project, left alone).

## Scale and space

- 1 Godot unit = 1 metre; +y up. The farm spans ±52 m (`Farm.HALF`); the walking grid is one
  cell per metre over `Rect2i(-54, -54, 108, 108)`.
- Rects in `farm.gd` are `Rect2(x, z, width, depth)` on the ground plane.
- The barn's door faces +z; the player spawns inside it (`Farm.SPAWN`).
- No door opens or closes yet: `BARN_DOOR` and `SHED_DOOR` are the widths of open doorways in
  the walls `farm.gd` builds. The `shed_lock` upgrade is a timer at `SHED_DOOR_OUT`, not a door.
- Blender models face +Y in Blender, which becomes -Z in Godot (`docs/models.md`).
- Positions other roles read, and so contracts: `Farm.SPAWN`, `BARN`, `SHED`, `SHED_DOOR`,
  `SHED_DOOR_OUT`, `PEGBOARD`, `GENERATOR`, `FUEL_DRUM`, `PUMP`, `CRATE`, `PLOTS`,
  `LOCKED_PLOTS`, `PLOT_SIZE`, and the queries `in_corn`, `route`.

## Authority

The host owns the clock, fuel, coins, tools and items, crops, traps and the pegboard, the store,
the generator, the creature, the Director and the voice bank. Each peer owns only its `Player`
node (its multiplayer authority is its peer id) and asks the host to act.

- **Peer to host:** `@rpc("any_peer", "call_local", "reliable")`, and the body starts by
  returning unless `multiplayer.is_server()`. The player's chores go through `Chores._request`,
  game-level asks through the RPCs below.
- **Host to everyone:** `@rpc("authority", "call_local", "reliable")`, so the host runs the same
  code path.
- **Host to one player's node:** the host calls the player's `any_peer` RPC with `rpc_id(peer)`
  (`trapped`, `knocked_down`, `killed` and the rest); the owning peer applies it and its
  replicated properties carry the result.
- **Continuous state:** `Game._tick` (`authority`, `call_remote`, `unreliable_ordered`) sends
  clock, fuel, coins, the listening rate and team size. Players replicate through
  `Net.replicate` (a `MultiplayerSynchronizer` named `Sync`): `position`, `rotation`, `pitch`,
  `crouching`, `sprinting`, `kneeling`, `lantern`, `dead`, `wounded`. The creature replicates
  `position`, `rotation`, `state` (`Creature.State`: `LURK`, `INVESTIGATE`, `LURE`, `CHASE`,
  `RETREAT`, `ERRAND`, `STARE`).
- **Joining late:** the host sends `Game._snapshot(...)` after `_client_ready`; trap and chore
  state come from their `snapshot` functions.
- **Spawning:** `MultiplayerSpawner`s under `Game` spawn players and the creature from
  dictionaries (`_player_data`; the creature's `look`).
- Nodes with RPCs have the same path on every peer (`docs/gotchas.md`, Networking).

## Network messages

All RPCs as of `91c5250`. Adding, removing or changing one is a contract change.

| Node | RPC | Mode | Direction |
|---|---|---|---|
| Game | `_begin()`, `_sound(sound, at)`, `_announce(text)`, `_resume()`, `_end(summary)` | authority, call_local, reliable | host to all |
| Game | `_tick(host_clock, host_fuel, host_coins, rate, team)` | authority, call_remote, unreliable_ordered | host to all |
| Game | `_snapshot(...)` | authority, reliable | host to joiner |
| Game | `_step(at, radius)` | any_peer, call_local, unreliable | peer to host |
| Game | `_client_ready(player_name)` | any_peer, reliable | peer to host |
| Chores | `_request(action, index)` | any_peer, call_local, reliable | peer to host |
| Chores | `_set_item(index, kind, holder, at, charge)`, `_set_plot(index, stage, crop)` | authority, call_local, reliable | host to all |
| Store | `_buy(id)` | any_peer, call_local, reliable | peer to host |
| Store | `_set_owned(id)`, `_refused(reason)` | authority, call_local, reliable | host to all / one |
| TrapField | `_set_trap(index, kind, at, state, victim)`, `_set_board(count)` | authority, call_local, reliable | host to all |
| Player | `trapped(at)`, `released()`, `stumbled()`, `knocked_down()`, `healed()`, `killed()`, `revived(at)` | any_peer, call_local, reliable | host to owning peer |
| Creature | `_say(index, echo, pitch)`, `_say_clip(data, echo, pitch, hiss)` | authority, call_remote, reliable | host to all |
| Director | `_scare_effects()`, `_whisper(data, at)`, `_crow(at)` | authority, call_local, reliable | host to one / all |
| Ghosts | `_ask_flicker()`, `_ask_rustle()` | any_peer, call_local, reliable | ghost to host |
| Ghosts | `_flicker(kind, id)`, `_tell(text)`, `_rustle(at)` | authority, call_local, reliable | host to all / one |
| VoiceBank | `_send_my_clips()`, `_delete_my_clip(id)`, `_receive_take(key, data)`, `_receive_withdraw()`, `_receive_block(listeners)` | any_peer, call_local, reliable | peer to host |
| VoiceBank | `_receive_my_clips(clips)`, `_set_name(peer, name)`, `_set_count(peer, count)` | authority, call_local, reliable | host to one / all |
| VoiceChat | `_receive_voice(packet)` | any_peer, call_remote, unreliable_ordered, channel 2 | peer to peers |
| VoiceChat | `_receive_consent(allowed)` | any_peer, call_remote, reliable | peer to peers |
| VoiceChat | `_receive_dead(peer_id, dead)` | authority, call_local, reliable | host to all |
| VoiceMimic | `_play_clip(data, source_id)`, `_play_fallback(index)` | authority, call_remote, reliable | host to all |

**Consent:** a take reaches the host only from a player who opted in; `_receive_withdraw` deletes
that player's takes; blocks stop a player's voice being used against the listeners named; takes
live in memory for the match only. Nothing voice-related is written to `res://` or committed.

## Economy data

Today the economy is named constants in the scripts below, not a data file. The prompt asks for
"every number read from data": moving them into one file is a proposed decision (DECISIONS.md,
D-005), not yet made. Until then, this table is the data contract: each value, where it lives,
and the simulator's Inputs cell it must match. QA checks the two agree.

| Value | Code | Simulator Inputs | Agree? |
|---|---|---|---|
| Turnip: seed / price / grows | `Store.SEEDS` 4, `Chores.PRICES` 10, `Chores.GROWTH` 1 | C5 4, D5 10, B5 1 day | Yes, but code grows in `GROW_TIME` units (60 s), not days |
| Pumpkin: seed / price / grows / unlocks | 10, 25, 2, all on day 1 | C6 10, D6 25, B6 2, E6 day 2 | Unlock day differs |
| Moonflower: seed / price / unlocks | 25, 70, all on day 1 | C8 25, D8 70, E8 day 3 | Unlock day differs |
| Corn | not a crop (2026-10-05) | row 7 still a crop | Sheet out of date |
| Seeds per pack | `Store.SEEDS_PER_PACK` 4 / 4 / 2 | per plot | Code sells packs; sheet prices plots |
| Field plots | 16 in `Farm.PLOTS`, 12 open, `LOCKED_PLOTS` 4 bought with the `plots` upgrade | B12 16, up to 24 | Differs |
| Moonflower bed | none: moonflowers grow in any field plot (night only) | B13 4 | Differs; Stage 3 (Q-006) |
| Starting coins | `Game.coins := 0` | B18 60 | Differs |
| Debt, first payment, due night | not built | B19 1200, B20 400, B21 3 | Phase 4 |
| Festival quota | not built | B24 8 (corn) | Now 8 pumpkin plots (stand-in) |
| Medical bill | `BILL_EACH` 50, `BILL_FIRST` 25, `BILL_CAP` 120, `BILL_FLOOR` 4 | B27-B30 | Yes |
| Team scale | `TEAM_SCALE` {1: 0.7, 2: 0.7, 3: 0.85, 4: 1.0} | B34-B36 (no 1-player row) | Yes for 2-4 |
| Traps per night | `TrapField.RAMP` [(2,1), (2,2)], `WIPE_EXTRA` (1,1) | C41:D47 | Days 1-2 agree; days 3-7 not built |
| Season length | `Game.DAYS` 2, day 360 s, dusk 60 s, night 300 s | 7 days | Phase 4 |
| Watering | `CAN_WATER` 4, `BIG_CAN` 8 | | Code only |
| Upgrades | `Store.UPGRADES`: plots 60, big_can 20, quiet_can 30, crowbar 20, lanterns 25, shed_lock 40, radios 50 | | `docs/store.md` |

## Other tuning

Named constants with a comment saying doc, playtest or guess; the owner of the script owns them.
The phase docs' Numbers tables list them with sources. Main ones: `Game` clock and fuel
(`FUEL_START` 0.4, `FUEL_LASTS` 0.4, `FUEL_PER_CAN` 1.0), `Chores.HOLD`/`UPGRADED_HOLD`,
`Director` (`QUIET_TO_FULL` 150, `LUNGE_REACH` 4, `WHISPER_ALONE` 10, `CROW_REACH` 6,
`ALONE_TIME` 10-25), `Player` (`STAMINA` 6, `KNOCKDOWN_TIME` 1.6, `WOUND_*`, `LANTERN_*`).

## Assets and naming

- **Scripts:** one `class_name` per script in PascalCase matching the file (`trap_field.gd` →
  `TrapField`); autoloads `Net` and `VoiceChat` have none. Constants UPPER_SNAKE, private members
  `_lead`. gdformat and gdlint enforce the rest.
- **Models:** `game/assets/models/<name>.glb`, built by `tools/blender/build.py`; loaded by
  `Dress.model(name)`. Under the 500 KB hook limit.
- **Materials:** the Blender material name chooses the texture: `name+tint` uses
  `textures/<name>.jpg` (and `<name>_n.jpg`) tinted; `plain+` is untextured; `glow+` is emissive
  (`docs/models.md`). `textures.json` describes each texture and is read at run time by `Dress`.
- **Joints:** characters and creature looks have empties `leg_0`, `leg_1`, `arm_0`, `arm_1`,
  `head`; code finds them by name. `Creature.LOOKS` lists the creature bodies (`creature`,
  `strawman` (renamed from `scarecrow` by D-008, S1-16), `boar`, `husk`).
- **Items and crops** are strings shared by chores, store, looks and HUD: crops `turnip`,
  `pumpkin`, `moonflower`; upgrades are `Store.UPGRADES` keys; sounds are `Sfx` names.

## Animation

What exists: every animation is procedural, in code, rotating the named joints each frame
(`Player._walk_cycle`, `Creature._animate`); there are no AnimationPlayers or baked clips.
Approved (D-006): it stays that way. The owner of the script that moves a body writes
its poses (player poses in `player.gd`, the creature's in `creature.gd`), the 3D Artist adds any
joints a pose needs, and every pose another peer must see is driven by a replicated property.

## Sounds

- `Sfx.RECORDED` maps a sound name to a FilmCow file prefix, a level in dB and a cut length;
  `get_sfx.sh` copies the library into `game/assets/sfx/` (gitignored, with a `.gdignore`) and
  `Sfx` loads them at run time with `AudioStreamWAV.load_from_buffer`, falling back to synthesis.
- Callers use names only (`Sfx.play_at(parent, "snap", at)`, `Game._sound`), never file paths.
- No other audio source without the user's approval (QUESTIONS.md, with the licence).

## Logs

The host writes a timestamped log under `user://logs/`; `Game.log_event` is the one way to add a
line. Scares, calls with each listener's tell, lures that worked (`LURE WORKED`), deaths, dawn
summaries and ghost actions are logged; new systems log their events the same way so the user can
tune from them.
