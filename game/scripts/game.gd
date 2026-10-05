class_name Game
extends Node3D
## Two days and two nights on the farm (Phase 2), after a lobby where players
## record their voices. Hosts or joins (Net). The host owns everything but the
## players: the clock, the tools, the crops, the traps, the generator, the
## recorded voices and the creature. Players ask the host to do things (pick
## up, water, disarm...) and the host tells every peer what changed. Each peer
## owns only its own player. The design doc is
## ../docs/Farming_Horror_Game_Concept.md; the phases are in its Build Plan.

## Phase lengths in seconds. The design doc's day is 8 to 10 minutes; the
## prototype has one small field, so its day is shorter. Net.short divides all by 6.
const DAY := 360.0
const DUSK := 60.0
const NIGHT := 300.0
const SHORT := 1.0 / 6.0
const DAYS := 2  ## Phase 2: enough for one morning after a night of trap setting.
## Payments, traps and disturbances scale with the team (design doc, Winning
## and Losing). One player plays as two.
const TEAM_SCALE := {1: 0.7, 2: 0.7, 3: 0.85, 4: 1.0}
## Medical bill (design doc, Medical Bill): the first death a night is cheaper,
## the night has a cap, and the bill never leaves less than a turnip seed pack.
const BILL_FIRST := 25
const BILL_EACH := 50
const BILL_CAP := 120
const BILL_FLOOR := 4
## By day the creature kills only a player stuck in a bear trap with nobody
## within ALONE_RANGE for a while (design doc, Day Deaths); how long, the
## Director decides each time (Director.ALONE_TIME).
const ALONE_RANGE := 20.0
const FUEL_START := 0.4
## A full tank lasts this share of the night (2 of its 5 minutes), and the lights
## burn from dusk, so even a tank filled at dusk runs dry early in the night:
## the barn is only safe for someone who goes out for fuel at least twice.
## A first playtest with 0.6 and half-tank cans left nobody a reason to go out.
const FUEL_LASTS := 0.4
const FUEL_PER_CAN := 1.0  ## A can fills the tank.
const FLICKER_BELOW := 0.15  ## The barn lights flicker under this much fuel.
## How far each action carries to the creature's ears (m).
const NOISE := {
	"water": 9.0,
	"water_quiet": 3.0,  # With the quiet watering can (Store). Guess.
	"harvest": 4.0,
	"pump": 12.0,
	"fuel": 5.0,
	"refuel": 12.0,
	"disarm": 3.0,
	"fill": 8.0,
	"pry": 10.0,
	"snap": 30.0,
	"pit": 10.0,
	"sell": 6.0,
	"hang": 6.0,
	"take": 4.0,
	"cut": 8.0,  # Cutting corn: stalks crack and fall. Guess.
	"lights_out": 80.0,  # The generator dying at night: the whole farm hears it.
	"lock": 40.0,  # The creature breaking the shed lock (Store). Guess.
}
const LURE_CHECK := 12.0  ## Seconds after a lure to see who walked toward it.
const LURE_HEARD := 40.0  ## Players this close to a lure count as having heard it.
const LURE_FOLLOWED := 4.0  ## Metres closer that count as walking toward it.
const CONTROLS := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"sprint": KEY_SHIFT,
	"crouch": KEY_CTRL,
	"jump": KEY_SPACE,
	"interact": KEY_E,
	"drop": KEY_G,
	"lantern": KEY_F,
	"my_clips": KEY_C,
	"store": KEY_B,
}

var farm := Farm.new()
var clock := 0.0
var fuel := FUEL_START
var coins := 0
var ended := false
var in_lobby := true  ## Before the host starts the first day; the clock waits.
var team_size := 1  ## Players when the day started.
## How fast the day runs: the clock, fuel and crops (dev panel; 1 in play).
var clock_rate := 1.0
var traps := TrapField.new()
var chores := Chores.new()
var voices := VoiceBank.new()
var store := Store.new()
var creature: Creature  ## Host only.
var director: Director  ## Tension and scares (Phase 3); the host drives it.
var hud := Hud.new()
var alone_for := {}  ## Host: trapped peer -> seconds with nobody near.
var fuel_warned := false  ## The low-fuel warning was given.

var _stats := {"deaths": 0, "bear": 0, "pit": 0, "lures": 0, "followed": 0, "friend": 0, "bill": 0}
var _night_deaths := 0
var _lure_checks: Array[Dictionary] = []
var _log: FileAccess
var _tick_left := 0.0
var _last_phase := ""
var _was_lit := false  ## Host: the lights were on last physics step.

var _players: MultiplayerSpawner
var _creatures: MultiplayerSpawner
var _daylight: Looks.Daylight
var _ambience: Sfx.Ambience


## Recordings live for this match only.
func _exit_tree() -> void:
	VoiceChat.keep_live_clips = false
	VoiceChat.radio_enabled = false
	VoiceChat.clear_clips()


func _ready() -> void:
	for action: String in CONTROLS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.physical_keycode = CONTROLS[action]
			InputMap.action_add_event(action, key)
	farm.build(self)
	traps.name = "Traps"
	traps.game = self
	add_child(traps)
	voices.name = "Voices"
	add_child(voices)
	chores.name = "Chores"
	chores.game = self
	add_child(chores)
	store.name = "Store"
	store.game = self
	add_child(store)
	add_child(ClipList.new(self))
	add_child(StorePanel.new(self))
	director = Director.new(self)
	add_child(director)
	add_child(Ghosts.new(self))
	_daylight = Looks.Daylight.new(self)
	_ambience = Sfx.Ambience.new(self)
	add_child(hud)
	_players = _spawner("Players", _spawn_player)
	_creatures = _spawner("Creatures", _spawn_creature)

	multiplayer.peer_connected.connect(func(id: int) -> void: print("[net] peer %d joined" % id))
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(
		func() -> void: _client_ready.rpc_id(1, Net.player_name)
	)

	var error := Net.start()
	if error != OK:
		var reason := "Could not start the session (%s)." % error_string(error)
		if Net.hosting and error == ERR_CANT_CREATE:
			reason = "Port %d is already in use. Is another copy still running?" % Net.port
		Net.stop.call_deferred(reason)
		return
	if multiplayer.is_server():
		_open_log()
		log_event("host started (short: %s)" % Net.short)
		_creatures.spawn({"position": Vector3(0, 0, Farm.CORN_IN + 10.0)})
		var host := _player_data(1, Net.player_name)
		_players.spawn(host)
		voices.register(1, host["name"])
		# What consenting players say over proximity chat, for the creature to call with.
		VoiceChat.keep_live_clips = true
		if Net.dev:
			var dev := Dev.new()
			dev.game = self
			add_child(dev)
		add_child(Lobby.new(self))
		if "--start" in OS.get_cmdline_user_args():  # Skip the lobby (testing).
			start_day.call_deferred()
	else:
		flash("Connecting to %s:%d..." % [Net.address, Net.port], 10.0)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		clock += delta * clock_rate  # Corrected by the host's ticks.
	var lit := lights_on()
	if farm.barn_lit() != lit:
		farm.set_barn_lit(lit)
	farm.flicker(lit and fuel < FLICKER_BELOW)
	var factor := short_factor()
	var into := _into_day()
	var day := clampf(into / (DAY * factor), 0.0, 1.0)
	var dusk := clampf((into - DAY * factor) / (DUSK * factor), 0.0, 1.0)
	var night := clampf((into - (DAY + DUSK) * factor) / (NIGHT * factor), 0.0, 1.0)
	_daylight.apply(day, dusk, night, phase() == "dawn", clock, delta)
	_update_sounds(delta)
	hud.update(self)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or ended:
		return
	if in_lobby:
		_tick_left -= delta
		if _tick_left <= 0.0:
			_tick_left = 0.5
			sync_state()
		return
	clock += delta * clock_rate
	var current := "%s of day %d" % [phase(), day_number()]
	if current != _last_phase:
		_enter_phase(phase(), current)
	if lights_on():
		fuel = maxf(0.0, fuel - delta * clock_rate / (FUEL_LASTS * NIGHT * short_factor()))
		if fuel < FLICKER_BELOW and not fuel_warned:
			fuel_warned = true
			_announce.rpc("The generator is sputtering. It needs fuel.")
		if fuel <= 0.0:
			_announce.rpc("The barn lights went out!")
			log_event("generator ran dry")
	# However the fuel ran out (the dev panel too), the creature hears it and comes.
	if _was_lit and not lights_on() and phase() == "night":
		log_event("the barn went dark; the creature heard the generator die")
		make_noise("lights_out", Farm.GENERATOR, "clank")
	_was_lit = lights_on()
	traps.check(living_players())
	_watch_trapped(delta)
	if not ended:  # The dawn screen is written; a late check would miss it.
		_check_lures()
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = 0.2
		sync_state()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Net.stop("")
	elif event.is_action_pressed("drop") and local_player():
		chores.request("drop", -1)


## "lobby", "day", "dusk", "night", or "dawn" once the last night is over.
func phase() -> String:
	if in_lobby:
		return "lobby"
	if clock >= DAYS * _cycle():
		return "dawn"
	var into := _into_day()
	var factor := short_factor()
	if into < DAY * factor:
		return "day"
	if into < (DAY + DUSK) * factor:
		return "dusk"
	return "night"


## 1 for the first day and night, 2 for the second.
func day_number() -> int:
	return mini(floori(clock / _cycle()), DAYS - 1) + 1


## Seconds in one day, dusk and night.
func _cycle() -> float:
	return (DAY + DUSK + NIGHT) * short_factor()


## Seconds into the current day (the last day's dawn counts as its end).
func _into_day() -> float:
	if clock >= DAYS * _cycle():
		return _cycle()
	return fmod(clock, _cycle())


## 1, or SHORT when testing with short phases.
func short_factor() -> float:
	return SHORT if Net.short else 1.0


## Seconds left in the current phase.
func phase_left() -> float:
	var factor := short_factor()
	var ends := {"day": DAY, "dusk": DAY + DUSK, "night": DAY + DUSK + NIGHT}
	return maxf(0.0, ends.get(phase(), 0.0) * factor - _into_day())


## How much the team's size scales traps and payments.
func team_scale() -> float:
	return TEAM_SCALE.get(clampi(team_size, 1, 4), 1.0)


## Host only: ends the lobby and starts the first day.
func start_day() -> void:
	if not in_lobby:
		return
	team_size = get_tree().get_nodes_in_group("players").size()
	_begin.rpc()
	clock = 0.0
	_last_phase = ""
	log_event("the day starts with %s (scale %.2f)" % [counted(team_size, "player"), team_scale()])
	sync_state()


@rpc("authority", "call_local", "reliable")
func _begin() -> void:
	in_lobby = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	flash("Day one. Water the turnips, sell what's ripe. Be back in the barn by dark.", 6.0)


## The barn is lit from dusk while the generator has fuel.
func lights_on() -> bool:
	return fuel > 0.0 and (phase() == "dusk" or phase() == "night")


func local_player() -> Player:
	return get_node_or_null("Players/%d" % multiplayer.get_unique_id()) as Player


func living_players() -> Array[Player]:
	var living: Array[Player] = []
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as Player
		if not player.dead:
			living.append(player)
	return living


## Host only: a player stuck in a bear trap with nobody near for a while, the
## one player the creature may kill by day (design doc, Day Deaths), or null.
func day_prey() -> Player:
	for player in living_players():
		if alone_for.get(player.get_multiplayer_authority(), 0.0) >= director.alone_needed(player):
			return player
	return null


## Host only: counts how long each trapped player has had nobody near.
func _watch_trapped(delta: float) -> void:
	for player in living_players():
		var peer := player.get_multiplayer_authority()
		var alone := player.pinned
		for other in living_players():
			if (
				other != player
				and other.global_position.distance_to(player.global_position) < ALONE_RANGE
			):
				alone = false
		alone_for[peer] = alone_for.get(peer, 0.0) + delta if alone else 0.0


## Host only: the creature reached player. Deadly at night; by day only to the
## trapped and alone (day_prey).
func creature_caught(player: Player) -> void:
	if player.dead or (phase() != "night" and player != day_prey()):
		return
	_stats["deaths"] += 1
	director.calm("kill")
	_night_deaths += 1
	VoiceChat.set_peer_dead(player.get_multiplayer_authority(), true)
	log_event("creature killed %s at %s" % [player.label(), _where(player.global_position)])
	chores.drop_held(player.get_multiplayer_authority(), player.global_position)
	player.killed.rpc_id(player.get_multiplayer_authority())
	player.dead = true  # Now, not when the owner's next sync arrives.
	_sound.rpc("thud", player.global_position)
	_announce.rpc("Something took %s." % player.label())
	if living_players().is_empty():
		log_event("everyone died")
		clock = day_number() * _cycle()  # On to the morning.


## Host only: something made a noise the creature may hear.
func noise(at: Vector3, radius: float) -> void:
	if creature:
		creature.hear(at, radius)


## Host only: prints a line and writes it to the session log, stamped with the
## phase and the time into it.
func log_event(text: String) -> void:
	var line := "[log] %6.1fs %-5s %s" % [clock, phase(), text]
	print(line)
	if _log:
		_log.store_line(line)
		_log.flush()


## Shows text in the middle of the screen for a few seconds.
func flash(text: String, seconds := 4.0) -> void:
	hud.flash(text, seconds)


func _open_log() -> void:
	DirAccess.make_dir_recursive_absolute("user://logs")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	_log = FileAccess.open("user://logs/%s.log" % stamp, FileAccess.WRITE)
	if _log:
		print("[log] writing %s" % ProjectSettings.globalize_path(_log.get_path()))


func _enter_phase(current: String, key: String) -> void:
	var was := _last_phase
	_last_phase = key
	log_event("%s begins (fuel %d%%, coins %d)" % [key, roundi(fuel * 100), coins])
	match current:
		"day":
			if day_number() > 1 and was != "":
				_morning()
		"dusk":
			_announce.rpc("The light is going. Top up the generator and get to the barn.")
		"night":
			_night_deaths = 0
			traps.plan_night(day_number() - 1, team_scale())
			_announce.rpc("Night. Stay in the light. Something is out there.")
		"dawn":
			var taken: Array[String] = []  # Before _morning() revives them.
			for node in get_tree().get_nodes_in_group("players"):
				if (node as Player).dead:
					taken.append((node as Player).label())
			_morning()
			_finish(taken)


## Host only, at each dawn: the creature finishes its traps; the dead come back
## at the barn and the medical bill is paid; after a full wipe it sets more.
## At the last dawn the run is over, so it sets nothing.
func _morning() -> void:
	var wiped := _night_deaths > 0 and living_players().is_empty()
	director.dawn()
	chores.dawn()
	store.dawn()
	if phase() != "dawn":
		traps.finish_night()
		if wiped:
			log_event("everyone died, so the creature sets extra traps")
			traps.plan(TrapField.WIPE_EXTRA.x, TrapField.WIPE_EXTRA.y)
			traps.finish_night()
	var bill := 0
	if _night_deaths > 0:
		bill = mini(BILL_CAP, BILL_FIRST + (_night_deaths - 1) * BILL_EACH)
		bill = mini(bill, maxi(0, coins - BILL_FLOOR))
		coins -= bill
		_stats["bill"] += bill
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as Player
		if player.dead:
			var at := Farm.SPAWN + Vector3(player.number * 1.5 - 3.0, 0, 0)
			player.revived.rpc_id(player.get_multiplayer_authority(), at)
			player.dead = false
			VoiceChat.set_peer_dead(player.get_multiplayer_authority(), false)
	var missing := TrapField.SLOTS - traps.board
	log_event(
		(
			"morning: %d died, bill %d, %s off the pegboard%s"
			% [_night_deaths, bill, counted(missing, "trap"), ", full wipe" if wiped else ""]
		)
	)
	if phase() != "dawn":
		_announce.rpc(
			(
				"Morning, day %d. Medical bill: %d. The pegboard is missing %s."
				% [day_number(), bill, counted(missing, "bear trap")]
			)
		)
	_night_deaths = 0
	sync_state()


func _finish(died: Array[String]) -> void:
	var survived: Array[String] = []
	for node in get_tree().get_nodes_in_group("players"):
		var label := (node as Player).label()
		if label not in died:
			survived.append(label)
	var summary := (
		(
			"DAWN\n\nSurvived the last night: %s\nTaken in it: %s\n\n"
			+ "Coins: %d (medical bills %d)\nBear traps sprung: %d · Pits: %d\n"
		)
		% [
			", ".join(survived) if survived else "nobody",
			", ".join(died) if died else "nobody",
			coins,
			_stats["bill"],
			_stats["bear"],
			_stats["pit"],
		]
	)
	summary += (
		"Voices from the corn: %d · Walked toward one: %d (a friend's voice: %d)\n\nEsc twice to leave."
		% [_stats["lures"], _stats["followed"], _stats["friend"]]
	)
	log_event("dawn: %s" % summary.replace("\n", " "))
	_end.rpc(summary)


## Host only: makes a sound every peer hears and the creature may.
func make_noise(what: String, at: Vector3, sound: String) -> void:
	_sound.rpc(sound, at)
	noise(at, NOISE[what])


@rpc("authority", "call_local", "reliable")
func _sound(sound: String, at: Vector3) -> void:
	Sfx.play_at(self, sound, at)


@rpc("authority", "call_local", "reliable")
func _announce(text: String) -> void:
	flash(text)


## Host only: sends the clock, fuel, coins and clock rate to every client.
func sync_state() -> void:
	_tick.rpc(clock, fuel, coins, clock_rate, team_size)


@rpc("authority", "call_remote", "unreliable_ordered")
func _tick(host_clock: float, host_fuel: float, host_coins: int, rate: float, team: int) -> void:
	clock = host_clock
	fuel = host_fuel
	coins = host_coins
	clock_rate = rate
	team_size = team


## Dev panel: back from the dawn screen to play on.
@rpc("authority", "call_local", "reliable")
func _resume() -> void:
	ended = false
	hud.summary("")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


@rpc("authority", "call_local", "reliable")
func _end(summary: String) -> void:
	ended = true
	hud.summary(summary)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Host only: player stepped on armed trap index (TrapField.check). A bear
## trap holds them; a pit trips them and takes what they carry.
func trap_sprung(index: int, player: Player) -> void:
	var trap := traps.traps[index]
	var peer := player.get_multiplayer_authority()
	var where := _where(trap["position"])
	if trap["kind"] == "bear":
		_stats["bear"] += 1
		traps.set_state(index, TrapField.State.SPRUNG, peer)
		player.trapped.rpc_id(peer, trap["position"])
		player.pinned = true  # Now, for day_prey; the owner's own copy follows.
		make_noise("snap", trap["position"], "snap")
		_announce.rpc("%s is caught in a bear trap!" % player.label())
		log_event("%s stepped in bear trap %d at %s" % [player.label(), index, where])
	else:
		_stats["pit"] += 1
		traps.set_state(index, TrapField.State.SPRUNG)
		player.stumbled.rpc_id(peer)
		chores.drop_held(peer, trap["position"])
		make_noise("pit", trap["position"], "thud")
		log_event("%s fell in pit %d at %s" % [player.label(), index, where])


## Host only: the creature called out. Remember who could hear it and how far
## away they were, and check again in LURE_CHECK seconds.
## heard: what each listener heard, peer -> description ("Ana's 'help_me'").
func _on_creature_spoke(at: Vector3, heard: Dictionary, tells: Dictionary) -> void:
	_stats["lures"] += 1
	director.called()
	var distances := {}
	var lines: Array[String] = []
	for player in living_players():
		var peer := player.get_multiplayer_authority()
		var distance := at.distance_to(player.global_position)
		if distance <= LURE_HEARD:
			distances[peer] = distance
			lines.append(
				"%s heard %s (%s)" % [player.label(), heard.get(peer, "?"), tells.get(peer, "?")]
			)
	_lure_checks.append(
		{"due": clock + LURE_CHECK, "at": at, "distances": distances, "heard": heard}
	)
	log_event(
		"creature called from %s: %s" % [_where(at), "; ".join(lines) if lines else "nobody near"]
	)


func _check_lures() -> void:
	while not _lure_checks.is_empty() and _lure_checks[0]["due"] <= clock:
		var check: Dictionary = _lure_checks.pop_front()
		var at: Vector3 = check["at"]
		for peer: int in check["distances"]:
			var player := get_node_or_null("Players/%d" % peer) as Player
			if player == null:
				continue
			var before: float = check["distances"][peer]
			var after := at.distance_to(player.global_position)
			if before - after >= LURE_FOLLOWED:
				_stats["followed"] += 1
				var heard: String = check["heard"].get(peer, "")
				var own := heard.begins_with("%s's '" % player.label())
				if heard.ends_with("'") and not heard.begins_with("a generic") and not own:
					_stats["friend"] += 1
				log_event(
					(
						"LURE WORKED: %s walked toward %s (%.0f m -> %.0f m)"
						% [player.label(), check["heard"].get(peer, "the voice"), before, after]
					)
				)


## "Farmer N" for a peer's player.
func _who(peer: int) -> String:
	var player := get_node_or_null("Players/%d" % peer) as Player
	return player.label() if player else "peer %d" % peer


## "1 pit", "2 pits".
static func counted(count: int, thing: String) -> String:
	return "%d %s%s" % [count, thing, "" if count == 1 else "s"]


static func _where(at: Vector3) -> String:
	return "(%.0f, %.0f)%s" % [at.x, at.z, " in the corn" if Farm.in_corn(at) else ""]


func _player_data(id: int, player_name: String) -> Dictionary:
	var row := _players.get_parent().get_child_count() - 1  # Minus the spawner.
	var at := Farm.SPAWN + Vector3(row * 1.5 - 2.25, 0, 0)
	var number := row + 1
	if player_name.strip_edges() == "":
		player_name = "Farmer %d" % number
	return {"id": id, "position": at, "number": number, "name": player_name.left(16)}


func _spawner(container_name: String, spawn: Callable) -> MultiplayerSpawner:
	var container := Node3D.new()
	container.name = container_name
	add_child(container)
	var spawner := MultiplayerSpawner.new()
	# Explicit name: auto-generated ones differ between peers and replication matches by path.
	spawner.name = "Spawner"
	spawner.spawn_function = spawn
	container.add_child(spawner)
	spawner.spawn_path = NodePath("..")
	return spawner


func _spawn_player(data: Dictionary) -> Node:
	var id: int = data["id"]
	var player := Player.new()
	player.name = str(id)
	player.position = data["position"]
	player.number = data["number"]
	player.player_name = data["name"]
	Net.replicate(
		player,
		[
			"position",
			"rotation",
			"pitch",
			"crouching",
			"sprinting",
			"kneeling",
			"lantern",
			"dead",
			"wounded"
		]
	)
	player.set_multiplayer_authority(id)
	if id == multiplayer.get_unique_id():
		player.stepped.connect(
			func(at: Vector3, radius: float) -> void: _step.rpc_id(1, at, radius)
		)
	print("[spawn] player %d" % id)
	return player


func _spawn_creature(data: Dictionary) -> Node:
	var spawned := Creature.new()
	spawned.name = "Creature"
	spawned.position = data["position"]
	spawned.farm = farm
	Net.replicate(spawned, ["position", "rotation", "state"])
	if multiplayer.is_server():
		spawned.game = self
		spawned.spoke.connect(_on_creature_spoke)
		creature = spawned
	return spawned


## A player's own footstep, sent to the host for the creature's ears.
@rpc("any_peer", "call_local", "unreliable")
func _step(at: Vector3, radius: float) -> void:
	if multiplayer.is_server():
		noise(at, radius)


## Joining, step 1: the client asks for its player and the farm as it stands.
@rpc("any_peer", "reliable")
func _client_ready(player_name: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	_snapshot.rpc_id(id, chores.snapshot(), traps.snapshot(), clock, fuel, coins, in_lobby)
	var data := _player_data(id, player_name)
	_players.spawn(data)
	voices.welcome(id)
	store.welcome(id)
	voices.register(id, data["name"])
	log_event("%s joined (peer %d)" % [_who(id), id])


## Step 2: the client takes the host's farm.
@rpc("authority", "reliable")
func _snapshot(
	host_chores: Dictionary,
	host_traps: Dictionary,
	host_clock: float,
	host_fuel: float,
	host_coins: int,
	lobby: bool
) -> void:
	chores.apply_snapshot(host_chores)
	traps.apply_snapshot(host_traps)
	_tick(host_clock, host_fuel, host_coins, 1.0, 1)
	in_lobby = lobby
	if lobby:
		add_child(Lobby.new(self))
	else:
		flash("Joined mid-day. Water the turnips, sell what's ripe. Back in the barn by dark.", 6.0)


func _on_peer_disconnected(id: int) -> void:
	print("[net] peer %d left" % id)
	var player := get_node_or_null("Players/%d" % id)
	if multiplayer.is_server() and player:
		chores.drop_held(id, (player as Player).global_position)
		voices.forget(id)
		player.queue_free()
		log_event("%s left" % (player as Player).label())


## Feeds the ambience what the local player is close to.
func _update_sounds(delta: float) -> void:
	var player := local_player()
	var distance := INF
	var chased := false
	var seen := get_node_or_null("Creatures/Creature") as Creature
	if seen and player and not player.dead:
		distance = seen.global_position.distance_to(player.global_position)
		chased = seen.state == Creature.State.CHASE
	_ambience.update(delta, phase() != "day", ended, distance, chased, lights_on())
