extends Node
## Headless smoke test, run by tools/check.sh. Hosts a session alone and plays
## through Phase 1 by script: the creature lures from the corn and the lure is
## logged as followed, chores work, traps spring and clear, dusk arms more
## traps and lights the barn, the generator burns and takes fuel, the lit barn
## keeps the creature out, and at night it kills a player in the open, which
## (alone) brings dawn. By day the creature must never leave the corn.
## Exits 0 on pass, 1 on fail.

const SPEEDUP := 4.0

var _failed := false
var _game: Game
var _player: Player
var _left_corn := 0  ## Physics frames the creature spent out of the corn by day.


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
	_check_routes()
	Engine.time_scale = SPEEDUP
	await _check_lure()
	await _check_chores()
	await _check_traps()
	_check(_left_corn == 0, "the creature stayed in the corn by day (%d frames out)" % _left_corn)
	await _check_dusk()
	await _check_night()
	Engine.time_scale = 1.0
	_finish()


func _physics_process(_delta: float) -> void:
	if _game and _game.creature and _game.phase() == "day":
		var at := _game.creature.global_position
		# The corn-only grid's cell centres sit up to half a cell inside the edge.
		if maxf(absf(at.x), absf(at.z)) < Farm.CORN_IN - 1.0:
			_left_corn += 1


func _check_routes() -> void:
	var farm := _game.farm
	var across := farm.route(Vector3(0, 0, 30), Vector3(0, 0, 8))
	_check(not across.is_empty(), "a route leads from the corn to the field")
	var around := farm.route(Vector3(0, 0, 30), Vector3(30, 0, 0), true)
	var in_corn := around.all(func(point: Vector3) -> bool: return Farm.in_corn(point))
	_check(not around.is_empty() and in_corn, "a corn-only route goes round the ring")
	var barn := Vector3(0, 0, -11)
	_check(not farm.route(Vector3(0, 0, 10), barn).is_empty(), "the dark barn can be walked into")
	farm.set_barn_lit(true)
	var lit := farm.route(Vector3(0, 0, 10), barn)
	var outside := lit.all(func(point: Vector3) -> bool: return not Farm.in_barn(point))
	_check(outside, "no route enters the lit barn")
	farm.set_barn_lit(false)


## Stands the player alone near the north corn, makes the creature due a lure,
## and walks the player toward the voice once it calls.
func _check_lure() -> void:
	_put(_player, Vector3(0, 0, 14))
	_game.creature.global_position = Vector3(-6, 0, 30)
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
	_put(_player, Farm.ITEMS[0]["position"] + Vector3(0, 0, 1))
	await _ask("pickup", 0)
	_check(_held() == "watering_can", "picked up the watering can")
	_put(_player, Farm.PLOTS[4] + Vector3(0, 0, -1.5))
	await _ask("water", 4)
	_check(_game.plots[4] == Game.Stage.GROWING, "watered a plot")
	_game.get("_grow_left")[4] = 0.05
	await _frames(5)
	_check(_game.plots[4] == Game.Stage.RIPE, "the watered plot ripened")
	await _ask("drop", -1)
	await _ask("harvest", 0)
	_check(_held() == "turnip", "pulled turnips")
	await _ask("sell", -1)
	_check(_game.coins == Game.TURNIP_PRICE and _held() == "", "sold them for %d" % _game.coins)


func _check_traps() -> void:
	_put(_player, Farm.TRAPS[0]["position"])
	await _frames(3)
	_check(_game.traps[0]["state"] == Game.TrapState.SPRUNG, "stepping on a bear trap springs it")
	_check(_player.pinned, "the bear trap holds the player")
	await _ask("pry", 0)
	_check(not _player.pinned and _player.slowed_left > 0.0, "prying free leaves a limp")
	_check(_game.traps[0]["state"] == Game.TrapState.DISARMED, "the sprung trap is spent")

	_put(_player, Farm.ITEMS[2]["position"] + Vector3(0, 0, 1))
	await _ask("pickup", 2)
	_put(_player, Farm.TRAPS[2]["position"])
	await _frames(3)
	_check(_game.traps[2]["state"] == Game.TrapState.SPRUNG, "stepping on a covered pit opens it")
	_check(
		_held() == "" and _player.stumble_left > 0.0,
		"the pit tripped the player and took the crowbar"
	)
	await _ask("pickup", 2)
	_put(_player, Farm.TRAPS[3]["position"] + Vector3(1.2, 0, 0))
	await _ask("disarm", 3)
	_check(
		_game.traps[3]["state"] == Game.TrapState.DISARMED, "disarmed a bear trap with the crowbar"
	)


func _check_dusk() -> void:
	_game.skip_phase()
	await _frames(3)
	_check(_game.phase() == "dusk", "dusk came")
	_check(_game.traps[5]["state"] == Game.TrapState.ARMED, "dusk armed the next traps")
	_check(_game.farm.barn_lit(), "the barn lights came on")
	await _ask("drop", -1)
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


func _check_night() -> void:
	_game.skip_phase()
	await _frames(3)
	_check(_game.phase() == "night", "night came")
	# In the lit barn, with the creature at the door: it must not get in.
	_put(_player, Vector3(0, 0, -13))
	_game.creature.global_position = Vector3(0, 0, -2)
	await _game_seconds(8.0)
	_check(not _player.dead, "the lit barn kept the creature out")
	_check(
		not Farm.in_barn(_game.creature.global_position), "the creature stayed outside the lit barn"
	)
	# In the open with a lantern: it should come.
	_put(_player, Vector3(0, 0, 14))
	_player.lantern = true
	_game.creature.global_position = Vector3(0, 0, 21)
	_game.creature.call("_lurk")
	for i in 60 * 15:
		await get_tree().physics_frame
		if _player.dead:
			break
	_check(_player.dead, "the creature killed a player in the open at night")
	await _frames(5)
	_check(_game.ended, "with everyone dead, dawn came")


## Sends a request to the host as the player would (the host is this process).
func _ask(action: String, index: int) -> void:
	_game.rpc_id(1, "_request", action, index)
	await _frames(2)


func _held() -> String:
	for item in _game.items:
		if item["holder"] == 1:
			return item["kind"]
	return ""


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
	if _game:
		for kind: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
			for sound in _game.find_children("*", kind, true, false):
				sound.call("stop")
		_game.queue_free()
	await _frames(10)
	Sfx.clear_cache()
	get_tree().quit(1 if _failed else 0)
