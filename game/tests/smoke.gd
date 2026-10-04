extends Node
## Headless smoke test, run by tools/check.sh. Hosts a session alone and plays
## through Phase 2 by script: the lobby holds the clock and the voice bank
## takes, blocks and picks recordings; the creature lures from the corn in a
## friend's recorded voice and following it is logged; chores work; traps
## spring, clear and go back on the pegboard; a player stuck alone in a bear
## trap can be killed by day; dusk lights the barn and the generator takes
## fuel; at night the creature takes traps from the pegboard and sets them, and
## an off-board trap vanishes; the lit barn keeps it out; it kills in the open,
## and the wipe brings morning, the medical bill and extra traps; day 2's night
## ends the run. By day the creature never leaves the corn unless it is coming
## for a trapped player. Exits 0 on pass, 1 on fail.

const SPEEDUP := 4.0
const FRIEND := 2  ## A pretend second player whose recordings the creature uses.

var _failed := false
var _game: Game
var _player: Player
var _dev: Dev
var _armed_before_wipe := 0  ## Armed traps just before the night's wipe.
var _left_corn := 0  ## Physics frames the creature spent out of the corn by day, not hunting.


func _ready() -> void:
	# Add the game beside this node rather than changing scene: a scene change
	# would free this node (the current scene) and the test would never quit.
	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate() as Game
	get_tree().root.add_child.call_deferred(_game)
	get_tree().set_deferred("current_scene", _game)
	await _frames(10)
	_player = _game.get_node_or_null("Players/1") as Player
	_check(_player != null, "host spawned a player")
	_check(_game.creature != null, "host spawned the creature")
	if _failed:
		_finish()
		return
	_player.set_physics_process(false)  # The test moves it.
	_dev = Dev.new()
	_dev.game = _game
	_game.add_child(_dev)
	await _check_lobby()
	_check_routes()
	Engine.time_scale = SPEEDUP
	await _check_lure()
	await _check_chores()
	await _check_traps()
	_check(_left_corn == 0, "the creature stayed in the corn by day (%d frames out)" % _left_corn)
	await _check_dusk()
	await _check_night()
	await _check_morning()
	await _check_day_prey()
	await _check_dev()
	Engine.time_scale = 1.0
	_finish()


func _physics_process(_delta: float) -> void:
	if _game and _game.creature and _game.phase() == "day":
		var at := _game.creature.global_position
		# The corn-only grid's cell centres sit up to half a cell inside the edge.
		var hunting := _game.creature.state == Creature.State.CHASE
		if maxf(absf(at.x), absf(at.z)) < Farm.CORN_IN - 1.0 and not hunting:
			_left_corn += 1


## The lobby holds the clock and the creature; the voice bank keeps takes,
## honours blocks, and picks a friend's voice over your own.
func _check_lobby() -> void:
	_check(_game.phase() == "lobby", "the session opens in the lobby")
	var held := _game.creature.global_position
	await _frames(30)
	_check(_game.clock == 0.0, "the clock waits in the lobby")
	_check(_game.creature.global_position == held, "the creature waits in the lobby")
	var voices := _game.voices
	_check(voices.names.get(1, "") != "", "the host's name is known (%s)" % voices.names.get(1, ""))
	var tone := PackedFloat32Array()
	tone.resize(VoiceCodec.RATE)  # One second.
	for i in tone.size():
		tone[i] = 0.3 * sin(TAU * 220.0 * i / VoiceCodec.RATE)
	var loud := VoiceBank.normalized(tone)
	var faint := tone.slice(0, 100)
	for i in faint.size():
		faint[i] *= 0.001  # Peak about 0.0003.
	var hiss := VoiceBank.normalized(faint)
	_check(
		absf(_peak(loud) - VoiceBank.TAKE_PEAK) < 0.01 and _peak(hiss) < 0.01,
		"quiet takes are raised to full level, near-silence only so far"
	)
	voices.rpc_id(1, "_receive_take", "help_me", VoiceCodec.encode(tone))
	await _frames(2)
	_check(voices.counts.get(1, 0) == 1, "a recorded take reached the host")
	_check(voices.pick(1).get("source", 0) == 1, "with only your voice, you may hear your own")
	voices.rpc_id(1, "_receive_block", [1])
	await _frames(2)
	_check(voices.pick(1).is_empty(), "a blocked voice is never played to that player")
	voices.rpc_id(1, "_receive_block", [])
	# A friend who recorded "over here" and the host's name.
	voices.call("_set_name", FRIEND, "Bea")
	var friend_takes := {
		"over_here": [VoiceCodec.encode(tone)], "name_1": [VoiceCodec.encode(tone)]
	}
	voices.get("_takes")[FRIEND] = friend_takes
	var friend := 0
	var named := 0
	for i in 40:
		var pick := voices.pick(1)
		friend += 1 if pick["source"] == FRIEND else 0
		named += 1 if pick["key"] == "name_1" else 0
	_check(friend > 30, "a friend's voice is picked far more than your own (%d of 40)" % friend)
	_check(named > 5, "it sometimes calls you by name in a friend's voice (%d of 40)" % named)
	_game.start_day()
	await _frames(3)
	_check(_game.phase() == "day" and _game.day_number() == 1, "the host started day 1")


func _check_routes() -> void:
	var farm := _game.farm
	var across := farm.route(Vector3(0, 0, 40), Vector3(0, 0, 13))
	_check(not across.is_empty(), "a route leads from the corn to the field")
	var around := farm.route(Vector3(0, 0, 40), Vector3(40, 0, 0), true)
	var in_corn := around.all(func(point: Vector3) -> bool: return Farm.in_corn(point))
	_check(not around.is_empty() and in_corn, "a corn-only route goes round the ring")
	var barn := Vector3(0, 0, -17)
	_check(not farm.route(Vector3(0, 0, 10), barn).is_empty(), "the dark barn can be walked into")
	farm.set_barn_lit(true)
	var lit := farm.route(Vector3(0, 0, 10), barn)
	var outside := lit.all(func(point: Vector3) -> bool: return not Farm.in_barn(point))
	_check(outside, "no route enters the lit barn")
	farm.set_barn_lit(false)
	var spots := Farm.trap_spots()
	_check(
		spots["corn"].size() > 20 and spots["path"].size() > 10,
		"trap spots in the corn and on the paths"
	)
	var in_corn_bears := 0
	for i in 100:
		in_corn_bears += 1 if Farm.in_corn(_game.traps.call("_pick_spot", "bear")) else 0
	_check(in_corn_bears >= 70, "bear traps go mostly in the corn (%d of 100)" % in_corn_bears)


## Stands the player alone near the north corn, makes the creature due a lure,
## and walks the player toward the voice once it calls.
func _check_lure() -> void:
	_put(_player, Vector3(0, 0, 20))
	_game.creature.global_position = Vector3(-6, 0, 40)
	_game.creature.set("_lure_left", 0.0)
	var heard := false
	for i in 60 * 30:
		await get_tree().physics_frame
		if _game.get("_stats")["lures"] > 0:
			heard = true
			break
	_check(heard, "the creature called from the corn")
	var voice := _game.creature.global_position
	_check(Farm.in_corn(voice), "it called from inside the corn %s" % voice)
	_put(_player, _player.global_position.move_toward(voice, 7.0))
	await _game_seconds(Game.LURE_CHECK + 1.0)
	_check(_game.get("_stats")["followed"] > 0, "walking toward the voice was logged")
	_check(_game.get("_stats")["friend"] > 0, "it was a friend's recorded voice")
	var calls: int = _game.get("_stats")["lures"]
	_check(calls >= 2, "it backed off and called again (%d calls)" % calls)
	# Spots for calls in a row, all from the same player, should spread out.
	var spots: Array[Vector3] = []
	for i in 4:
		spots.append(_game.creature.pick_lure_spot(_player, false))
	var closest := INF
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			closest = minf(closest, spots[i].distance_to(spots[j]))
	_check(closest > 6.0, "calls in a row come from different spots (closest %.1f m)" % closest)


func _check_chores() -> void:
	var chores := _game.chores
	_put(_player, Farm.ITEMS[0]["position"] + Vector3(0, 0, 1))
	await _ask("pickup", 0)
	_check(_held() == "watering_can", "picked up the watering can")
	_put(_player, Farm.PLOTS[4] + Vector3(0, 0, -1.5))
	await _ask("water", 4)
	_check(chores.plots[4] == Chores.Stage.GROWING, "watered a plot")
	chores.get("_grow_left")[4] = 0.05
	await _frames(5)
	_check(chores.plots[4] == Chores.Stage.RIPE, "the watered plot ripened")
	await _ask("drop", -1)
	await _ask("harvest", 0)
	_check(_held() == "turnip", "pulled turnips")
	await _ask("sell", -1)
	_check(_game.coins == Chores.TURNIP_PRICE and _held() == "", "sold them for %d" % _game.coins)


func _check_traps() -> void:
	var traps := _game.traps
	var bear := _arm("bear", Vector3(10, 0, 20))
	_put(_player, Vector3(10, 0, 20))
	await _frames(3)
	_check(
		traps.traps[bear]["state"] == TrapField.State.SPRUNG, "stepping on a bear trap springs it"
	)
	_check(_player.pinned, "the bear trap holds the player")
	await _ask("pry", bear)
	_check(not _player.pinned and _player.slowed_left > 0.0, "prying free leaves a limp")
	_check(traps.traps[bear]["state"] == TrapField.State.DISARMED, "the sprung trap is spent")
	await _ask("take_trap", bear)
	_check(_held() == "bear_trap", "picked up the spent bear trap")
	traps.set_board(TrapField.SLOTS - 1)  # As if the creature had taken one.
	await _frames(2)
	_put(_player, Vector3(Farm.PEGBOARD.x, 0, Farm.PEGBOARD.z + 1.0))
	await _ask("hang", -1)
	_check(traps.board == TrapField.SLOTS and _held() == "", "hung it back on the pegboard")

	_put(_player, Farm.ITEMS[2]["position"] + Vector3(0, 0, 1))
	await _ask("pickup", 2)
	var pit := _arm("pit", Vector3(-10, 0, 20))
	_put(_player, Vector3(-10, 0, 20))
	await _frames(3)
	_check(
		traps.traps[pit]["state"] == TrapField.State.SPRUNG, "stepping on a covered pit opens it"
	)
	_check(
		_held() == "" and _player.stumble_left > 0.0,
		"the pit tripped the player and took the crowbar"
	)
	await _ask("pickup", 2)
	var second := _arm("bear", Vector3(-14, 0, 20))
	_put(_player, Vector3(-12.8, 0, 20))
	await _ask("disarm", second)
	_check(
		traps.traps[second]["state"] == TrapField.State.DISARMED,
		"disarmed a bear trap with the crowbar"
	)
	await _ask("drop", -1)


## Day 2: stuck in a bear trap with nobody near, the creature comes and kills.
func _check_day_prey() -> void:
	var trap := _arm("bear", Vector3(0, 0, 24))
	_put(_player, Vector3(0, 0, 24))
	# Placed afresh: after the night's kill it would still be retreating.
	_game.creature.place(Vector3(0, 0, 36))
	var traps_before := _game.traps.traps.size()
	var killed := false
	for i in roundi((Game.ALONE_TIME + 20.0) * 60 / SPEEDUP):
		await get_tree().physics_frame
		if _player.dead:
			killed = true
			break
	_check(
		_game.traps.traps[trap]["state"] == TrapField.State.SPRUNG, "the day trap held the player"
	)
	_check(killed, "trapped and alone by day, the creature came and killed")
	await _frames(5)
	# Alone, that was a wipe on the last day: the run is over.
	_check(_game.ended and _game.phase() == "dawn", "a wipe on the last day ends the run")
	_check(_game.traps.traps.size() == traps_before, "no traps are set once the run is over")
	_check(
		("Taken in it: %s" % _player.label()) in _game.hud._overlay.text,
		"the dawn screen lists the player taken, not as a survivor"
	)


func _check_dusk() -> void:
	_dev.skip_phase()
	await _frames(3)
	_check(_game.phase() == "dusk", "dusk came")
	_check(_game.farm.barn_lit(), "the barn lights came on")
	_put(_player, Farm.ITEMS[3]["position"] + Vector3(0, 0, 1))
	await _ask("pickup", 3)
	_put(_player, Farm.GENERATOR + Vector3(0, 0, 1.2))
	var before := _game.fuel
	await _ask("refuel", -1)
	_check(
		_game.fuel > before + 0.4, "refuelled the generator (%.2f -> %.2f)" % [before, _game.fuel]
	)
	await _game_seconds(5.0)
	_check(_game.fuel < 1.0, "the generator burns fuel")
	await _ask("drop", -1)


func _check_night() -> void:
	var traps := _game.traps
	# A spent bear trap left lying far from anyone: the creature's at nightfall.
	var lying := _arm("bear", Vector3(25, 0, -20))
	traps.set_state(lying, TrapField.State.DISARMED)
	_put(_player, Vector3(0, 0, -19))  # In the lit barn.
	var armed_before := traps.armed_positions().size()
	_dev.skip_phase()
	await _frames(3)
	_check(_game.phase() == "night", "night came")
	_check(not traps.orders.is_empty(), "the creature has traps to set tonight")
	await _game_seconds(3.0)
	_check(traps.traps[lying]["state"] == TrapField.State.HIDDEN, "an off-board trap vanished")
	_check(traps.stock >= 1, "vanished traps become the creature's to set (%d)" % traps.stock)
	traps.plan(3, 1)  # More bear traps than it holds, so it needs the pegboard.
	_game.creature.global_position = Farm.SHED_DOOR_OUT + Vector3(0, 0, 6)
	for i in roundi(200.0 * 60 / SPEEDUP):
		await get_tree().physics_frame
		if traps.orders.is_empty():
			break
	_check(
		traps.board < TrapField.SLOTS,
		"it took bear traps from the pegboard (%d left)" % traps.board
	)
	var placed := traps.armed_positions().size() - armed_before
	_check(placed >= 2 and traps.orders.is_empty(), "it set tonight's traps (%d)" % placed)
	_check(not _player.dead, "the lit barn kept the creature out")
	# The lights going out draws it from across the farm, even mid-errand.
	traps.plan(0, 1)
	_game.creature.global_position = Vector3(-40, 0, 40)
	_game.creature.call("_lurk")
	await _frames(3)
	_dev.set_fuel(0.0)
	await _frames(3)
	var far := _game.creature.global_position.distance_to(Farm.GENERATOR)
	_check(
		_game.creature.state == Creature.State.INVESTIGATE,
		"the generator dying draws the creature (%s)" % _game.creature.state_name()
	)
	await _game_seconds(5.0)
	var nearer := _game.creature.global_position.distance_to(Farm.GENERATOR)
	_check(nearer < far - 10.0, "it heads for the barn (%.0f m -> %.0f m)" % [far, nearer])
	_dev.set_fuel(1.0)
	# In the open with a lantern: it should come.
	_armed_before_wipe = traps.armed_positions().size()
	_put(_player, Vector3(0, 0, 20))
	_player.lantern = true
	_game.creature.global_position = Vector3(0, 0, 27)
	_game.creature.call("_lurk")
	for i in 60 * 15:
		await get_tree().physics_frame
		if _player.dead:
			break
	_check(_player.dead, "the creature killed a player in the open at night")


## With everyone dead the night ends: morning of day 2, back at the barn, the
## bill paid (never below a seed pack), and the wipe's extra traps set.
func _check_morning() -> void:
	var armed_before := _armed_before_wipe
	await _frames(5)
	_check(_game.day_number() == 2 and _game.phase() == "day", "a wipe brings the morning of day 2")
	_check(
		not _player.dead and Farm.in_barn(_player.global_position),
		"the dead came back inside the barn"
	)
	_check(
		_game.coins == Game.BILL_FLOOR,
		"the medical bill left a seed pack's worth (%d)" % _game.coins
	)
	var extra := _game.traps.armed_positions().size() - armed_before
	_check(extra >= 1, "after the wipe it set extra traps (%d)" % extra)


## The developer panel's controls reach the game.
func _check_dev() -> void:
	_dev.jump_to("day")
	await _frames(3)
	_check(not _game.ended and _game.phase() == "day", "dev: back to day from the dawn screen")
	var before := _game.clock
	_dev.call("_set_speed", 10.0)
	await _game_seconds(1.0)
	_check(_game.clock - before > 5.0, "dev: time x10 (%.1f s in 1 s)" % (_game.clock - before))
	_dev.call("_set_speed", 1.0)
	var calls: int = _game.get("_stats")["lures"]
	_dev.call("_call_now")
	_check(_game.get("_stats")["lures"] == calls + 1, "dev: the creature called on demand")
	_dev.set_all_traps(true)
	var armed := _game.traps.traps.all(
		func(trap: Dictionary) -> bool:
			return trap["state"] in [TrapField.State.ARMED, TrapField.State.HIDDEN]
	)
	_check(armed, "dev: armed every trap")
	_dev.set_fuel(0.1)
	_check(is_equal_approx(_game.fuel, 0.1), "dev: set the fuel")
	# Day can find it in the barn after a night kill there; it must walk out.
	_game.creature.place(Vector3(0, 0, -17))
	await _game_seconds(20.0)
	var at := _game.creature.global_position
	_check(not Farm.in_barn(at), "by day the creature walks out of the barn (at %s)" % at)


func _arm(kind: String, at: Vector3) -> int:
	_game.traps.arm(kind, at)
	return _game.traps.traps.size() - 1


## Sends a request to the host as the player would (the host is this process).
func _ask(action: String, index: int) -> void:
	_game.chores.request(action, index)
	await _frames(2)


func _held() -> String:
	return _game.chores.held_item(1).get("kind", "")


func _peak(samples: PackedFloat32Array) -> float:
	var peak := 0.0
	for sample in samples:
		peak = maxf(peak, absf(sample))
	return peak


func _put(body: Node3D, at: Vector3) -> void:
	body.global_position = Vector3(at.x, 0.05, at.z)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## Waits this much game time (Engine.time_scale stretches each physics step).
func _game_seconds(seconds: float) -> void:
	await _frames(ceili(seconds * Engine.physics_ticks_per_second / Engine.time_scale))


func _check(ok: bool, what: String) -> bool:
	print(("ok   " if ok else "FAIL ") + what)
	_failed = _failed or not ok
	return ok


## Stops every sound and frees the game before quitting: quitting with
## sounds still playing leaks their playbacks, which check.sh fails on.
func _finish() -> void:
	print("SMOKE FAIL" if _failed else "SMOKE PASS")
	# The whole tree: the VoiceChat autoload's microphone player counts too.
	for kind: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for sound in get_tree().root.find_children("*", kind, true, false):
			sound.call("stop")
	if _game:
		_game.queue_free()
	await _frames(10)
	Sfx.clear_cache()
	get_tree().quit(1 if _failed else 0)
