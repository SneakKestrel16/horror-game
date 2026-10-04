class_name Game
extends Node3D
## One day and one night on the farm (Phase 1). Hosts or joins (Net). The
## host owns everything but the players: the clock, the tools, the crops, the
## traps, the generator and the creature. Players ask the host to do things
## (pick up, water, disarm...) and the host tells every peer what changed.
## Each peer owns only its own player. The design doc is
## ../docs/Farming_Horror_Game_Concept.md; Phase 1 is in its Build Plan.

enum Stage { DRY, GROWING, RIPE, EMPTY }  ## A plot's turnips.
enum TrapState { HIDDEN, ARMED, SPRUNG, DISARMED }  ## HIDDEN: not set yet.

## Phase lengths in seconds. The design doc's day is 8 to 10 minutes; Phase 1
## has one small field, so its day is shorter. Net.short divides all by 6.
const DAY := 360.0
const DUSK := 60.0
const NIGHT := 300.0
const SHORT := 1.0 / 6.0

const GROW_TIME := 60.0  ## Seconds from watered to ripe (scaled like the phases).
const CAN_WATER := 4  ## Plots one watering can full waters.
const TURNIP_PRICE := 10  ## Design doc, Crops.
const FUEL_START := 0.4
const FUEL_PER_CAN := 0.5
const FUEL_LASTS := 0.6  ## A full tank lasts this share of the night.
const BEAR_REACH := 0.55  ## How close a foot must come to spring a trap (m).
const PIT_REACH := 0.65
const USE_RANGE := 2.0
const LOOK_ANGLE := 0.7  ## Radians (40°) either side of where a player faces.
const TRAP_LOOK_ANGLE := 0.45  ## Traps are only found by looking right at them (26°).
## Seconds to hold E. Prying is quicker with a friend (design doc, Night Traps).
const HOLD := {"disarm": 4.0, "fill": 3.0, "pry": 3.0, "help": 1.5}
## How far each action carries to the creature's ears (m).
const NOISE := {
	"water": 9.0,
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
}
const LURE_CHECK := 12.0  ## Seconds after a lure to see who walked toward it.
const LURE_HEARD := 40.0  ## Players this close to a lure count as having heard it.
const LURE_FOLLOWED := 4.0  ## Metres closer that count as walking toward it.
const ITEM_NAMES := {
	"watering_can": "watering can",
	"shovel": "shovel",
	"crowbar": "crowbar",
	"fuel_can": "fuel can",
	"turnip": "turnip",
}
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
	"skip_phase": KEY_F2,
}

var farm := Farm.new()
var clock := 0.0
var fuel := FUEL_START
var coins := 0
var ended := false
## {kind, holder (peer id, 0 on the ground, -1 gone), position, charge}.
var items: Array[Dictionary] = []
var plots: Array[int] = []
var traps: Array[Dictionary] = []  ## {kind, position, state, victim}.
var creature: Creature  ## Host only.

var _grow_left: Array[float] = []  ## Host only.
var _stats := {"deaths": 0, "bear": 0, "pit": 0, "lures": 0, "followed": 0}
var _lure_checks: Array[Dictionary] = []
var _log: FileAccess
var _tick_left := 0.0
var _last_phase := ""
var _fuel_warned := false
var _hold_key := ""
var _hold_time := 0.0

var _players: MultiplayerSpawner
var _creatures: MultiplayerSpawner
var _item_nodes: Array[Node3D] = []
var _plot_nodes: Array[Node3D] = []
var _trap_nodes: Array[Node3D] = []
var _daylight: Looks.Daylight
var _ambience: Sfx.Ambience

var _status: Label
var _info: Label
var _prompt: Label
var _message: Label
var _message_left := 0.0
var _overlay: Label


func _ready() -> void:
	for action: String in CONTROLS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.physical_keycode = CONTROLS[action]
			InputMap.action_add_event(action, key)
	farm.build(self)
	_build_world_state()
	_daylight = Looks.Daylight.new(self)
	_ambience = Sfx.Ambience.new(self)
	_build_hud()
	_players = _spawner("Players", _spawn_player)
	_creatures = _spawner("Creatures", _spawn_creature)

	multiplayer.peer_connected.connect(func(id: int) -> void: print("[net] peer %d joined" % id))
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func() -> void: _client_ready.rpc_id(1))

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
		_creatures.spawn({"position": Vector3(0, 0, 30)})
		_players.spawn(_player_data(1))
		flash("Day one. Water the turnips, sell what's ripe. Be back in the barn by dark.", 6.0)
	else:
		flash("Connecting to %s:%d..." % [Net.address, Net.port], 10.0)


func _process(delta: float) -> void:
	_message_left -= delta
	_message.visible = _message_left > 0.0
	if not multiplayer.is_server():
		clock += delta  # Corrected by the host's ticks.
	var lit := lights_on()
	if farm.barn_lit() != lit:
		farm.set_barn_lit(lit)
	var factor := short_factor()
	var day := clampf(clock / (DAY * factor), 0.0, 1.0)
	var dusk := clampf((clock - DAY * factor) / (DUSK * factor), 0.0, 1.0)
	_daylight.apply(day, dusk, phase() == "night" or phase() == "dawn")
	_place_items()
	_update_sounds()
	_update_hud()
	var player := local_player()
	if player and not ended:
		_interact(player, delta)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or ended:
		return
	clock += delta
	var current := phase()
	if current != _last_phase:
		_enter_phase(current)
	if lights_on():
		fuel = maxf(0.0, fuel - delta / (FUEL_LASTS * NIGHT * short_factor()))
		if fuel < 0.15 and not _fuel_warned:
			_fuel_warned = true
			_announce.rpc("The generator is sputtering. It needs fuel.")
		if fuel <= 0.0:
			_announce.rpc("The barn lights went out!")
			log_event("generator ran dry")
	for i in plots.size():
		if plots[i] == Stage.GROWING:
			_grow_left[i] -= delta
			if _grow_left[i] <= 0.0:
				_set_plot.rpc(i, Stage.RIPE)
	_check_traps()
	_check_lures()
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = 0.2
		_tick.rpc(clock, fuel, coins)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Net.stop("")
	elif event.is_action_pressed("skip_phase") and Net.dev and multiplayer.is_server():
		skip_phase()
	elif event.is_action_pressed("drop") and local_player():
		_request.rpc_id(1, "drop", -1)


## "day", "dusk", "night" or "dawn" (over).
func phase() -> String:
	var factor := short_factor()
	if clock < DAY * factor:
		return "day"
	if clock < (DAY + DUSK) * factor:
		return "dusk"
	if clock < (DAY + DUSK + NIGHT) * factor:
		return "night"
	return "dawn"


## 1, or SHORT when testing with short phases.
func short_factor() -> float:
	return SHORT if Net.short else 1.0


## Seconds left in the current phase.
func phase_left() -> float:
	var factor := short_factor()
	var ends := {"day": DAY, "dusk": DAY + DUSK, "night": DAY + DUSK + NIGHT}
	return maxf(0.0, ends.get(phase(), 0.0) * factor - clock)


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


## Where the armed traps are (the creature lures players toward them).
func armed_traps() -> Array[Vector3]:
	var armed: Array[Vector3] = []
	for trap in traps:
		if trap["state"] == TrapState.ARMED:
			armed.append(trap["position"])
	return armed


## Host only: the creature reached player. Deadly at night; by day it never chases.
func creature_caught(player: Player) -> void:
	if phase() != "night" or player.dead:
		return
	_stats["deaths"] += 1
	log_event("creature killed %s at %s" % [player.label(), _where(player.global_position)])
	_drop_held(player.get_multiplayer_authority(), player.global_position)
	player.killed.rpc_id(player.get_multiplayer_authority())
	player.dead = true  # Now, not when the owner's next sync arrives.
	_sound.rpc("thud", player.global_position)
	_announce.rpc("Something took %s." % player.label())
	if living_players().is_empty():
		log_event("everyone died")
		clock = (DAY + DUSK + NIGHT) * short_factor()


## Host only (dev mode, smoke test): jumps to the start of the next phase.
func skip_phase() -> void:
	var factor := short_factor()
	for start: float in [DAY, DAY + DUSK, DAY + DUSK + NIGHT]:
		if clock < start * factor:
			clock = start * factor
			return


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
	_message.text = text
	_message_left = seconds


func _open_log() -> void:
	DirAccess.make_dir_recursive_absolute("user://logs")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	_log = FileAccess.open("user://logs/%s.log" % stamp, FileAccess.WRITE)
	if _log:
		print("[log] writing %s" % ProjectSettings.globalize_path(_log.get_path()))


func _enter_phase(current: String) -> void:
	_last_phase = current
	log_event("%s begins (fuel %d%%, coins %d)" % [current, roundi(fuel * 100), coins])
	match current:
		"dusk":
			for i in traps.size():
				if Farm.TRAPS[i]["armed"] == "dusk":
					_set_trap.rpc(i, TrapState.ARMED, 0)
			_announce.rpc("The light is going. Top up the generator and get to the barn.")
		"night":
			_announce.rpc("Night. Stay in the light. Something is out there.")
		"dawn":
			_finish()


func _finish() -> void:
	var survived: Array[String] = []
	var died: Array[String] = []
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as Player
		(died if player.dead else survived).append(player.label())
	var summary := (
		"DAWN\n\nSurvived: %s\nTaken in the night: %s\n\nCoins: %d\nBear traps sprung: %d · Pits: %d\n"
		% [
			", ".join(survived) if survived else "nobody",
			", ".join(died) if died else "nobody",
			coins,
			_stats["bear"],
			_stats["pit"],
		]
	)
	summary += (
		"Voices from the corn: %d · Walked toward one: %d\n\nEsc twice to leave."
		% [_stats["lures"], _stats["followed"]]
	)
	log_event("dawn: %s" % summary.replace("\n", " "))
	_end.rpc(summary)


func _build_world_state() -> void:
	for item in Farm.ITEMS:
		var charge := CAN_WATER if item["kind"] == "watering_can" else 0
		items.append(
			{"kind": item["kind"], "holder": 0, "position": item["position"], "charge": charge}
		)
		_item_nodes.append(Looks.item(self, item["kind"]))
	items[3]["charge"] = 1  # The fuel can starts full.
	for i in Farm.PLOTS.size():
		plots.append(Stage.RIPE if i < 4 else Stage.DRY)
		_grow_left.append(0.0)
		var node := Node3D.new()
		node.position = Farm.PLOTS[i]
		add_child(node)
		_plot_nodes.append(node)
		Looks.plot(node, plots[i])
	for spot in Farm.TRAPS:
		var state := TrapState.ARMED if spot["armed"] == "start" else TrapState.HIDDEN
		traps.append(
			{"kind": spot["kind"], "position": spot["position"], "state": state, "victim": 0}
		)
		var node := Node3D.new()
		node.position = spot["position"]
		add_child(node)
		_trap_nodes.append(node)
		Looks.trap(node, spot["kind"], state)


## What E would do for player right now: {text, action, index, hold}, or an
## empty text when nothing is in reach. First match wins, so a trapped player
## sees the way out before anything else.
func _find_action(player: Player) -> Dictionary:
	var me := player.get_multiplayer_authority()
	var held := _held_index(me)
	var kind: String = items[held]["kind"] if held >= 0 else ""
	var charge: int = items[held]["charge"] if held >= 0 else 0
	for found: Dictionary in [
		_pry_action(player, me),
		_trap_action(player, kind),
		_item_action(player),
		_plot_action(player, kind, charge),
		_place_action(player, kind, charge),
	]:
		if found["text"] != "":
			return found
	return _act("", "", -1, 0.0)


## A bear trap holding this player, or a friend.
func _pry_action(player: Player, me: int) -> Dictionary:
	for i in traps.size():
		var trap := traps[i]
		if trap["state"] == TrapState.SPRUNG and trap["kind"] == "bear":
			if trap["victim"] == me:
				return _act("Hold E to pry the jaws open", "pry", i, HOLD["pry"])
			if trap["victim"] != 0 and _near(player.global_position, trap["position"], USE_RANGE):
				return _act("Hold E to help pry them free", "pry", i, HOLD["help"])
	return _act("", "", -1, 0.0)


func _trap_action(player: Player, kind: String) -> Dictionary:
	for i in traps.size():
		var trap := traps[i]
		if trap["state"] != TrapState.ARMED or not _looking_at(player, trap["position"], true):
			continue
		var bear: bool = trap["kind"] == "bear"
		if bear and kind == "crowbar":
			return _act("Hold E to disarm the bear trap", "disarm", i, HOLD["disarm"])
		if bear:
			return _act("A bear trap. You need the crowbar from the shed.", "", i, 0.0)
		if kind == "shovel":
			return _act("Hold E to fill in the covered pit", "fill", i, HOLD["fill"])
		return _act("Loose ground... a covered pit. Fill it with the shovel.", "", i, 0.0)
	return _act("", "", -1, 0.0)


func _item_action(player: Player) -> Dictionary:
	for i in items.size():
		if items[i]["holder"] == 0 and _looking_at(player, items[i]["position"]):
			return _act("E: pick up the %s" % ITEM_NAMES[items[i]["kind"]], "pickup", i, 0.0)
	return _act("", "", -1, 0.0)


func _plot_action(player: Player, kind: String, charge: int) -> Dictionary:
	for i in plots.size():
		if not _looking_at(player, Farm.PLOTS[i]):
			continue
		var text := ""
		var action := ""
		match plots[i]:
			Stage.DRY:
				text = "Dry. Needs the watering can."
				if kind == "watering_can":
					text = (
						"E: water the turnips"
						if charge > 0
						else "The can is empty. Fill it at the pump."
					)
					action = "water" if charge > 0 else ""
			Stage.GROWING:
				text = "Growing..."
			Stage.RIPE:
				text = "E: pull the turnips" if kind == "" else "Ripe. Hands full (G to drop)."
				action = "harvest" if kind == "" else ""
		if text != "":
			return _act(text, action, i, 0.0)
	return _act("", "", -1, 0.0)


## The pump, the shipping crate, the fuel drum and the generator.
func _place_action(player: Player, kind: String, charge: int) -> Dictionary:
	var text := ""
	var action := ""
	if _looking_at(player, Farm.PUMP) and kind == "watering_can":
		text = "E: fill the watering can"
		action = "pump"
	elif _looking_at(player, Farm.CRATE):
		text = "Shipping crate. Bring turnips here."
		if kind == "turnip":
			text = "E: sell the turnips (+%d)" % TURNIP_PRICE
			action = "sell"
	elif _looking_at(player, Farm.FUEL_DRUM) and kind == "fuel_can" and charge == 0:
		text = "E: fill the fuel can"
		action = "fuel"
	elif _looking_at(player, Farm.GENERATOR):
		text = "Generator: %d%% fuel" % roundi(fuel * 100)
		if kind == "fuel_can" and charge > 0:
			text = "E: refuel the generator"
			action = "refuel"
	return _act(text, action, -1, 0.0)


static func _act(text: String, action: String, index: int, hold: float) -> Dictionary:
	return {"text": text, "action": action, "index": index, "hold": hold}


## The local player's E key: instant actions on press, held ones once held long enough.
func _interact(player: Player, delta: float) -> void:
	if player.dead:
		_prompt.text = "You are dead. Drift until dawn. (WASD, Space up, Ctrl down)"
		return
	var found := _find_action(player)
	var key := "%s:%d" % [found["action"], found["index"]]
	var hold: float = found["hold"]
	var text: String = found["text"]
	var holding: bool = Input.is_action_pressed("interact") and found["action"] != ""
	if hold > 0.0 and holding and key == _hold_key:
		_hold_time += delta
	else:
		_hold_time = 0.0
	_hold_key = key
	player.kneeling = hold > 0.0 and holding and found["action"] != "pry"
	if hold > 0.0 and _hold_time > 0.0:
		var bars := roundi(_hold_time / hold * 10.0)
		text += "\n[%s%s]" % ["#".repeat(bars), "-".repeat(maxi(0, 10 - bars))]
	_prompt.text = text
	if found["action"] == "":
		return
	if hold > 0.0 and _hold_time >= hold:
		_hold_time = 0.0
		player.kneeling = false
		_request.rpc_id(1, found["action"], found["index"])
	elif hold == 0.0 and Input.is_action_just_pressed("interact"):
		_request.rpc_id(1, found["action"], found["index"])


func _near(a: Vector3, b: Vector3, reach: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() <= reach


## Within reach and in front: within LOOK_ANGLE of where the body faces, or
## for a trap, within TRAP_LOOK_ANGLE of where the eyes look.
func _looking_at(player: Player, point: Vector3, closely := false) -> bool:
	if not _near(player.global_position, point, USE_RANGE):
		return false
	if closely:
		return player.look_direction().angle_to(point - player.eye_position()) < TRAP_LOOK_ANGLE
	var facing := -player.global_basis.z
	var to_point := point - player.global_position
	to_point.y = 0.0
	return to_point.length() < 0.6 or Vector3(facing.x, 0, facing.z).angle_to(to_point) < LOOK_ANGLE


func _held_index(peer: int) -> int:
	for i in items.size():
		if items[i]["holder"] == peer:
			return i
	return -1


## A player asks the host to do something. The host checks it still makes
## sense (another player may have got there first) and applies it.
@rpc("any_peer", "call_local", "reliable")
func _request(action: String, index: int) -> void:
	if not multiplayer.is_server() or ended:
		return
	var peer := multiplayer.get_remote_sender_id()
	var player := get_node_or_null("Players/%d" % peer) as Player
	if player == null or player.dead:
		return
	var held := _held_index(peer)
	var kind: String = items[held]["kind"] if held >= 0 else ""
	var at := player.global_position
	match action:
		"drop":
			_drop_held(peer, player.drop_point())
		"pickup":
			if index < 0 or index >= items.size() or items[index]["holder"] != 0:
				return
			_drop_held(peer, items[index]["position"])
			_sync_item(index, peer, items[index]["position"], items[index]["charge"])
		"water":
			if kind == "watering_can" and items[held]["charge"] > 0 and plots[index] == Stage.DRY:
				_sync_item(held, peer, at, items[held]["charge"] - 1)
				_grow_left[index] = GROW_TIME * short_factor()
				_set_plot.rpc(index, Stage.GROWING)
				_make_noise("water", Farm.PLOTS[index], "splash")
		"harvest":
			if held < 0 and plots[index] == Stage.RIPE:
				_set_plot.rpc(index, Stage.EMPTY)
				_sync_item(items.size(), peer, at, 0, "turnip")
				_make_noise("harvest", Farm.PLOTS[index], "step")
		"pump":
			if kind == "watering_can":
				_sync_item(held, peer, at, CAN_WATER)
				_make_noise("pump", Farm.PUMP, "splash")
		"sell":
			if kind == "turnip":
				_sync_item(held, -1, at, 0)
				coins += TURNIP_PRICE
				_tick.rpc(clock, fuel, coins)
				_make_noise("sell", Farm.CRATE, "coin")
				log_event("%s sold turnips (coins %d)" % [player.label(), coins])
		"fuel":
			if kind == "fuel_can":
				_sync_item(held, peer, at, 1)
				_make_noise("fuel", Farm.FUEL_DRUM, "splash")
		"refuel":
			if kind == "fuel_can" and items[held]["charge"] > 0:
				_sync_item(held, peer, at, 0)
				fuel = minf(1.0, fuel + FUEL_PER_CAN)
				_fuel_warned = false
				_tick.rpc(clock, fuel, coins)
				_make_noise("refuel", Farm.GENERATOR, "clank")
				log_event(
					"%s refuelled the generator (%d%%)" % [player.label(), roundi(fuel * 100)]
				)
		"disarm", "fill":
			var tool := "crowbar" if action == "disarm" else "shovel"
			if index >= 0 and index < traps.size() and traps[index]["state"] == TrapState.ARMED:
				if kind == tool:
					_set_trap.rpc(index, TrapState.DISARMED, 0)
					_make_noise(
						action, traps[index]["position"], "clank" if tool == "crowbar" else "thud"
					)
					log_event(
						"%s cleared %s trap %d" % [player.label(), traps[index]["kind"], index]
					)
		"pry":
			if index >= 0 and index < traps.size() and traps[index]["state"] == TrapState.SPRUNG:
				var victim: int = traps[index]["victim"]
				var trapped := get_node_or_null("Players/%d" % victim) as Player
				_set_trap.rpc(index, TrapState.DISARMED, 0)
				_make_noise("pry", traps[index]["position"], "clank")
				if trapped and not trapped.dead:
					trapped.released.rpc_id(victim)
				log_event("%s pried %s free" % [player.label(), _who(victim)])


## Host only: makes a sound every peer hears and the creature may.
func _make_noise(what: String, at: Vector3, sound: String) -> void:
	_sound.rpc(sound, at)
	noise(at, NOISE[what])


func _drop_held(peer: int, at: Vector3) -> void:
	var held := _held_index(peer)
	if held >= 0:
		_sync_item(held, 0, Vector3(at.x, 0, at.z), items[held]["charge"])


func _sync_item(index: int, holder: int, at: Vector3, charge: int, kind := "") -> void:
	if kind == "":
		kind = items[index]["kind"]
	_set_item.rpc(index, kind, holder, at, charge)


@rpc("authority", "call_local", "reliable")
func _set_item(index: int, kind: String, holder: int, at: Vector3, charge: int) -> void:
	while items.size() <= index:
		items.append({"kind": kind, "holder": -1, "position": at, "charge": 0})
		_item_nodes.append(Looks.item(self, kind))
	items[index] = {"kind": kind, "holder": holder, "position": at, "charge": charge}


@rpc("authority", "call_local", "reliable")
func _set_plot(index: int, stage: int) -> void:
	plots[index] = stage
	Looks.plot(_plot_nodes[index], stage)


@rpc("authority", "call_local", "reliable")
func _set_trap(index: int, state: int, victim: int) -> void:
	traps[index]["state"] = state
	traps[index]["victim"] = victim
	Looks.trap(_trap_nodes[index], traps[index]["kind"], state)


@rpc("authority", "call_local", "reliable")
func _sound(sound: String, at: Vector3) -> void:
	Sfx.play_at(self, sound, at)


@rpc("authority", "call_local", "reliable")
func _announce(text: String) -> void:
	flash(text)


@rpc("authority", "call_remote", "unreliable_ordered")
func _tick(host_clock: float, host_fuel: float, host_coins: int) -> void:
	clock = host_clock
	fuel = host_fuel
	coins = host_coins


@rpc("authority", "call_local", "reliable")
func _end(summary: String) -> void:
	ended = true
	_overlay.text = summary
	_overlay.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Host only: springs any armed trap a living player steps on.
func _check_traps() -> void:
	for i in traps.size():
		var trap := traps[i]
		if trap["state"] != TrapState.ARMED:
			continue
		var reach := BEAR_REACH if trap["kind"] == "bear" else PIT_REACH
		for player in living_players():
			if not _near(player.global_position, trap["position"], reach) or player.pinned:
				continue
			var peer := player.get_multiplayer_authority()
			var where := _where(trap["position"])
			if trap["kind"] == "bear":
				_stats["bear"] += 1
				_set_trap.rpc(i, TrapState.SPRUNG, peer)
				player.trapped.rpc_id(peer, trap["position"])
				_make_noise("snap", trap["position"], "snap")
				_announce.rpc("%s is caught in a bear trap!" % player.label())
				log_event("%s stepped in bear trap %d at %s" % [player.label(), i, where])
			else:
				_stats["pit"] += 1
				_set_trap.rpc(i, TrapState.SPRUNG, 0)
				player.stumbled.rpc_id(peer)
				_drop_held(peer, trap["position"])
				_make_noise("pit", trap["position"], "thud")
				log_event("%s fell in pit %d at %s" % [player.label(), i, where])
			break


## Host only: the creature called out. Remember who could hear it and how far
## away they were, and check again in LURE_CHECK seconds.
func _on_creature_spoke(at: Vector3, line: String) -> void:
	_stats["lures"] += 1
	var distances := {}
	for player in living_players():
		var distance := at.distance_to(player.global_position)
		if distance <= LURE_HEARD:
			distances[player.get_multiplayer_authority()] = distance
	_lure_checks.append({"due": clock + LURE_CHECK, "at": at, "distances": distances})
	log_event("creature called '%s' from %s, heard by %s" % [line, _where(at), distances.keys()])


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
				log_event(
					(
						"LURE WORKED: %s walked toward the voice (%.0f m -> %.0f m)"
						% [player.label(), before, after]
					)
				)


## "Farmer N" for a peer's player.
func _who(peer: int) -> String:
	var player := get_node_or_null("Players/%d" % peer) as Player
	return player.label() if player else "peer %d" % peer


static func _where(at: Vector3) -> String:
	return "(%.0f, %.0f)%s" % [at.x, at.z, " in the corn" if Farm.in_corn(at) else ""]


func _player_data(id: int) -> Dictionary:
	var row := _players.get_parent().get_child_count() - 1  # Minus the spawner.
	var at := Farm.SPAWN + Vector3(row * 1.5 - 0.75, 0, 0)
	return {"id": id, "position": at, "number": row + 1}


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
	Net.replicate(
		player,
		["position", "rotation", "pitch", "crouching", "sprinting", "kneeling", "lantern", "dead"]
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
func _client_ready() -> void:
	var id := multiplayer.get_remote_sender_id()
	_snapshot.rpc_id(id, items, plots, traps, clock, fuel, coins)
	_players.spawn(_player_data(id))
	log_event("%s joined (peer %d)" % [_who(id), id])


## Step 2: the client takes the host's farm.
@rpc("authority", "reliable")
func _snapshot(
	host_items: Array,
	host_plots: Array,
	host_traps: Array,
	host_clock: float,
	host_fuel: float,
	host_coins: int
) -> void:
	for i in host_items.size():
		var item: Dictionary = host_items[i]
		_set_item(i, item["kind"], item["holder"], item["position"], item["charge"])
	for i in host_plots.size():
		_set_plot(i, host_plots[i])
	for i in host_traps.size():
		_set_trap(i, host_traps[i]["state"], host_traps[i]["victim"])
	_tick(host_clock, host_fuel, host_coins)
	flash("Joined. Water the turnips, sell what's ripe. Be back in the barn by dark.", 6.0)


func _on_peer_disconnected(id: int) -> void:
	print("[net] peer %d left" % id)
	var player := get_node_or_null("Players/%d" % id)
	if multiplayer.is_server() and player:
		_drop_held(id, (player as Player).global_position)
		player.queue_free()
		log_event("%s left" % (player as Player).label())


func _place_items() -> void:
	for i in items.size():
		var node := _item_nodes[i]
		var holder: int = items[i]["holder"]
		node.visible = holder != -1
		if holder > 0:
			var player := get_node_or_null("Players/%d" % holder) as Player
			if player and player.hand:
				node.global_transform = player.hand.global_transform.scaled_local(Vector3.ONE * 0.6)
				node.visible = not player.dead
				continue
		node.transform = Transform3D(Basis(), items[i]["position"])


## Feeds the ambience what the local player is close to.
func _update_sounds() -> void:
	var player := local_player()
	var distance := INF
	var chased := false
	var seen := get_node_or_null("Creatures/Creature") as Creature
	if seen and player and not player.dead:
		distance = seen.global_position.distance_to(player.global_position)
		chased = seen.state == Creature.State.CHASE
	_ambience.update(phase() != "day", ended, distance, chased, lights_on())


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	_status = Label.new()
	_status.position = Vector2(24, 18)
	_status.add_theme_font_size_override("font_size", 26)
	hud.add_child(_status)

	_info = Label.new()
	_info.position = Vector2(24, 60)
	_info.add_theme_font_size_override("font_size", 20)
	hud.add_child(_info)

	var crosshair := Label.new()
	crosshair.text = "·"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.add_theme_font_size_override("font_size", 32)
	hud.add_child(crosshair)

	_message = Label.new()
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_message.position.y = 110
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_font_size_override("font_size", 30)
	_message.visible = false
	hud.add_child(_message)

	_prompt = Label.new()
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.position.y += 40
	_prompt.add_theme_font_size_override("font_size", 22)
	hud.add_child(_prompt)

	var hint := Label.new()
	hint.text = (
		"E use (hold for traps) · G drop · F lantern · Shift sprint · Ctrl crouch"
		+ " · Esc mouse / leave"
	)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.position.y -= 40
	hint.modulate = Color(1, 1, 1, 0.5)
	hud.add_child(hint)

	_overlay = Label.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay.add_theme_font_size_override("font_size", 30)
	var shade := StyleBoxFlat.new()
	shade.bg_color = Color(0, 0, 0, 0.8)
	_overlay.add_theme_stylebox_override("normal", shade)
	_overlay.visible = false
	hud.add_child(_overlay)


func _update_hud() -> void:
	var left := phase_left()
	_status.text = (
		"%s · %d:%02d left" % [phase().to_upper(), floori(left / 60.0), floori(fmod(left, 60.0))]
	)
	var player := local_player()
	var lines: Array[String] = ["Coins: %d" % coins]
	if phase() != "day" or fuel < 0.3:
		lines.append("Generator: %d%%%s" % [roundi(fuel * 100), "" if fuel > 0.0 else " (OUT)"])
	if player:
		var held := _held_index(player.get_multiplayer_authority())
		if held >= 0:
			var item := items[held]
			var extra := ""
			if item["kind"] == "watering_can":
				extra = " (%d/%d)" % [item["charge"], CAN_WATER]
			elif item["kind"] == "fuel_can":
				extra = " (full)" if item["charge"] > 0 else " (empty)"
			lines.append("Carrying: %s%s" % [ITEM_NAMES[item["kind"]], extra])
		if player.stamina < Player.STAMINA:
			var bars := roundi(player.stamina / Player.STAMINA * 10.0)
			lines.append("Stamina: %s" % "|".repeat(bars))
		if player.pinned:
			lines.append("TRAPPED")
		elif player.slowed_left > 0.0:
			lines.append("Limping: %ds" % ceili(player.slowed_left))
		if player.dead:
			lines.append("DEAD until dawn")
	_info.text = "\n".join(lines)
