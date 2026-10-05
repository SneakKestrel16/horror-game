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
	for look: String in Creature.LOOKS:
		var model := Dress.model(look)
		var joints := ["leg_0", "leg_1", "arm_0", "arm_1", "head"].filter(
			func(joint: String) -> bool: return model.find_child(joint) != null
		)
		_check(joints.size() == 5, "the %s model has all five joints" % look)
		model.free()
	if _failed:
		_finish()
		return
	_player.set_physics_process(false)  # The test moves it.
	_dev = Dev.new()
	_dev.game = _game
	_game.add_child(_dev)
	await _check_lobby()
	_check_routes()
	_check_audio()
	_check_chase_sounds()
	Engine.time_scale = SPEEDUP
	await _check_lure()
	await _check_chores()
	await _check_store()
	await _check_traps()
	_check(_left_corn == 0, "the creature stayed in the corn by day (%d frames out)" % _left_corn)
	await _check_dusk()
	await _check_night()
	await _check_morning()
	await _check_day_prey()
	await _check_dev()
	await _check_phase3()
	Engine.time_scale = 1.0
	_finish()


func _physics_process(_delta: float) -> void:
	if _game and _game.creature and _game.phase() == "day":
		var at := _game.creature.global_position
		# Turning a corner it may cut a few centimetres across a cell's corner.
		var hunting := _game.creature.state == Creature.State.CHASE
		var near_corn := false
		for step: Vector3 in [
			Vector3.ZERO, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK
		]:
			near_corn = near_corn or Farm.in_corn(at + step * 0.5)
		if not near_corn and not hunting:
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
	# What a consenting player says over voice chat is kept, and the creature uses it.
	VoiceChat.call("_store_clip_samples", 1, tone)
	await _frames(40)
	_check(VoiceChat.get_clips(1).is_empty(), "nothing said over chat is kept without consent")
	VoiceChat.set_recording_consent(true)
	VoiceChat.call("_store_clip_samples", 1, tone)
	await _frames(40)
	_check(VoiceChat.get_clips(1).size() == 1, "with consent, a chat phrase is kept")
	VoiceChat.get("_consent")[FRIEND] = true
	VoiceChat.get("_clips")[FRIEND] = [tone]
	var live := 0
	for i in 40:
		live += 1 if voices.pick(1)["key"] == VoiceBank.LIVE else 0
	_check(live > 3, "it calls with what a friend said over chat (%d of 40)" % live)
	# The C panel's list: the host sends this player's phrases, and deletes on request.
	var listed := []
	var on_list := func(clips: Array) -> void: listed.assign(clips)
	voices.clips_arrived.connect(on_list)
	var silence := PackedFloat32Array()
	silence.resize(VoiceCodec.RATE)
	VoiceChat.call("_store_clip_samples", 1, silence)  # A muted mic.
	await _frames(40)
	var higher := tone.duplicate()  # Another phrase: same level, different pitch.
	for i in higher.size():
		higher[i] = 0.3 * sin(TAU * 330.0 * i / VoiceCodec.RATE)
	VoiceChat.call("_store_clip_samples", 1, higher)
	await _frames(40)
	voices.ask_my_clips()
	await _frames(3)
	_check(
		listed.size() == 2,
		"you can list your kept phrases, not the silent one (%d)" % listed.size()
	)
	var first: PackedByteArray = listed[0]
	VoiceChat.delete_clip(1, 0)  # The oldest drops off the end before the delete arrives.
	voices.delete_my_clip(first)
	await _frames(3)
	_check(listed.size() == 1, "deleting a phrase already gone deletes nothing else")
	voices.delete_my_clip(listed[0])
	await _frames(3)
	_check(listed.is_empty() and VoiceChat.get_clips(1).is_empty(), "you can delete one by one")
	VoiceChat.call("_store_clip_samples", 1, tone)
	await _frames(40)
	voices.delete_my_clip(PackedByteArray())
	await _frames(3)
	_check(listed.is_empty() and VoiceChat.get_clips(1).is_empty(), "and all of them")
	voices.clips_arrived.disconnect(on_list)
	VoiceChat.set_recording_consent(false)
	_check(VoiceChat.get_clips(1).is_empty(), "withdrawing consent deletes chat phrases")
	VoiceChat.clear_clips()
	_game.start_day()
	await _frames(3)
	_check(_game.phase() == "day" and _game.day_number() == 1, "the host started day 1")


func _check_routes() -> void:
	var farm := _game.farm
	var across := farm.route(Vector3(0, 0, 40), Farm.PLOTS[0])
	_check(not across.is_empty(), "a route leads from the corn to the field")
	var around := farm.route(Vector3(0, 0, 40), Vector3(40, 0, 0), true)
	var in_corn := around.all(func(point: Vector3) -> bool: return Farm.in_corn(point))
	_check(not around.is_empty() and in_corn, "a corn-only route goes round the ring")
	# By day the creature can reach the middle rows and the generator unseen.
	for goal: Vector3 in [Vector3(-2, 0, 14), Vector3(14, 0, -16)]:
		var covered := farm.route(Vector3(40, 0, 0), goal, true)
		var ends_there := not covered.is_empty() and covered[-1].distance_to(goal) < 1.5
		_check(
			ends_there and covered.all(func(point: Vector3) -> bool: return Farm.in_corn(point)),
			"a corn-only route reaches %s from the ring" % goal
		)
	_check(not Farm.in_corn(Farm.GENERATOR), "the generator stands in the open")
	var past := farm.route(Farm.GENERATOR + Vector3(-3, 0, 0), Farm.GENERATOR + Vector3(3, 0, 0))
	var generator: Rect2 = Farm.props()[2]
	var through := past.filter(
		func(point: Vector3) -> bool: return generator.has_point(Vector2(point.x, point.z))
	)
	_check(not past.is_empty() and through.is_empty(), "routes go round the generator")
	_check(
		not farm.clear_line(Farm.GENERATOR + Vector3(-3, 0, 0), Farm.GENERATOR + Vector3(3, 0, 0)),
		"a straight run through the generator is blocked"
	)
	for building: Rect2 in [Farm.BARN, Farm.SHED]:
		var clear := true
		for x in range(floori(building.position.x), ceili(building.end.x)):
			for z in range(floori(building.position.y), ceili(building.end.y)):
				clear = clear and not Farm.in_corn(Vector3(x + 0.5, 0, z + 0.5))
		_check(clear, "no corn grows in the %s" % ("barn" if building == Farm.BARN else "shed"))
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
	# The creature can use the player's own voice (5% of a friend's weight), which
	# does not count as a friend's, so check whichever voice it picked.
	var checks: Array = _game.get("_lure_checks")
	var me := _player.get_multiplayer_authority()
	var heard_as: String = checks[0]["heard"].get(me, "") if checks else ""
	var own := heard_as.begins_with("%s's '" % _player.label())
	_put(_player, _player.global_position.move_toward(voice, 7.0))
	await _game_seconds(Game.LURE_CHECK + 1.0)
	_check(_game.get("_stats")["followed"] > 0, "walking toward the voice was logged")
	var friend: int = _game.get("_stats")["friend"]
	if own:
		_check(friend == 0, "the player's own voice did not count as a friend's")
	else:
		_check(friend > 0, "it was a friend's recorded voice (%s)" % heard_as)
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
	_check(
		_game.coins == Chores.PRICES["turnip"] and _held() == "", "sold them for %d" % _game.coins
	)
	# Corn is cover, not a crop: none grows on the fields, and rows fill the middle.
	for plot in Farm.PLOTS:
		_check(not Farm.in_corn(plot), "no corn on plot %s" % plot)
	_check(Farm.in_corn(Vector3(-2, 0, 14)), "corn rows where the old field was")


## The store at the crate: refuses the broke, sells seed packs into empty
## hands (else onto the ground), and seeds plant a bare plot. Moonflowers grow
## only at night and wilt at dawn. Upgrades: the new plots clear the overgrown
## ones, the can grows, the crowbar quickens, lanterns brighten, the radios
## come on, and the shed lock holds the creature off the pegboard until broken.
func _check_store() -> void:
	var store := _game.store
	var chores := _game.chores
	var spent := _game.coins
	_put(_player, Farm.CRATE + Vector3(0, 0, -1.5))
	_check(store.open_for(_player), "the store opens by the crate")
	_game.coins = 0
	store.buy("turnip_seeds")
	await _frames(2)
	_check(_held() == "" and _game.coins == 0, "the store turns away the broke")
	_game.coins = 1000
	store.buy("turnip_seeds")
	await _frames(2)
	var pack := chores.held_item(1)
	_check(
		_held() == "turnip_seeds" and pack["charge"] == 4 and _game.coins == 1000 - 16,
		"bought turnip seeds into empty hands (coins %d)" % _game.coins
	)
	var on_ground := chores.items.size()
	store.buy("pumpkin_seeds")
	await _frames(2)
	_check(
		chores.items.size() == on_ground + 1 and chores.items[-1]["holder"] == 0,
		"with full hands, a seed pack is left at the crate"
	)
	_check(chores.plots[0] == Chores.Stage.EMPTY, "a harvested plot is bare")
	_put(_player, Farm.PLOTS[0] + Vector3(0, 0, -1.5))
	await _ask("plant", 0)
	_check(
		chores.plots[0] == Chores.Stage.DRY and chores.held_item(1)["charge"] == 3,
		"planted turnip seeds in the bare plot"
	)
	chores.call("_set_plot", 0, Chores.Stage.GROWING, "moonflower")
	chores.get("_grow_left")[0] = 0.05
	await _frames(5)
	_check(chores.plots[0] == Chores.Stage.GROWING, "moonflowers don't grow by day")
	chores.dawn()
	await _frames(2)
	_check(chores.plots[0] == Chores.Stage.EMPTY, "unpicked moonflowers wilt at dawn")

	var locked := Farm.PLOTS.size() - Farm.LOCKED_PLOTS
	_check(chores.plots[locked] == Chores.Stage.LOCKED, "the new plots start overgrown")
	var clear := true
	for i in range(locked, Farm.PLOTS.size()):
		clear = clear and not Farm.in_corn(Farm.PLOTS[i])
	_check(clear, "no corn grows on the new plots")
	_put(_player, Farm.CRATE + Vector3(0, 0, -1.5))
	for id: String in Store.UPGRADES:
		store.buy(id)
	await _frames(3)
	_check(store.owned.size() == Store.UPGRADES.size(), "bought every upgrade")
	_check(chores.plots[locked] == Chores.Stage.EMPTY, "the new plots are cleared")
	_check(Chores.can_size() == Chores.BIG_CAN, "the watering can holds more")
	_check(Chores.hold_for("disarm") == 2.0, "the oiled crowbar disarms faster")
	_check(VoiceChat.radio_enabled, "the walkie-talkies are on")
	await _frames(2)
	var lantern := _player.get("_light") as OmniLight3D
	_check(lantern.omni_range == Player.BRIGHT_LANTERN.y, "lanterns are brighter")
	store.buy("radios")
	await _frames(2)
	_check(_game.coins == 1000 - 16 - 40 - _upgrades_cost(), "an upgrade is bought only once")

	var creature := _game.creature
	var board := _game.traps.board
	creature.set("_errand", "take")
	creature.set("_lock_left", Creature.LOCK_TIME)
	creature.call("_do_errand", 1.0)
	_check(_game.traps.board == board and not store.lock_broken, "the shed lock holds the creature")
	creature.set("_errand", "take")
	creature.call("_do_errand", Creature.LOCK_TIME)
	_check(store.lock_broken, "the creature breaks the shed lock in time")
	store.dawn()
	_check(not store.lock_broken, "the lock is mended at dawn")
	_game.traps.set_board(board)
	creature.place(Vector3(0, 0, Farm.CORN_IN + 10.0))
	chores.drop_held(1, _player.global_position)
	_game.coins = spent
	_game.sync_state()


func _upgrades_cost() -> int:
	var total := 0
	for id: String in Store.UPGRADES:
		total += Store.price(id)
	return total


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
	for i in roundi((Director.ALONE_TIME.y + 20.0) * 60 / SPEEDUP):
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
	# Mid-chase it turns on a nearer player it can see, not running past them.
	var players: MultiplayerSpawner = _game.get("_players")
	var other := players.spawn(_game.call("_player_data", FRIEND, "Bea")) as Player
	other.set_physics_process(false)
	await _frames(2)
	_put(_player, Vector3(18, 0, 4))
	_put(other, Vector3(18, 0, -1))
	_game.creature.place(Vector3(18, 0, -6))
	_game.creature.chase(_player)
	await _game_seconds(0.6)
	var chasing: Player = _game.creature.get("_target")
	_check(chasing == other, "mid-chase it turns on the nearer player")
	_game.creature.place(Vector3(0, 0, 40))
	other.queue_free()
	await _frames(2)
	# In the open with a lantern: it should come.
	_armed_before_wipe = traps.armed_positions().size()
	_game.coins = 10  # Less than the bill, so the morning tests the floor.
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


## Voice audio comes through the codec intact; the resampler keeps speech and
## filters out what would fold into hiss; every sound effect builds, and loops
## wrap without a click.
func _check_audio() -> void:
	var tone := PackedFloat32Array()
	tone.resize(VoiceCodec.RATE)
	for i in tone.size():
		tone[i] = 0.5 * sin(TAU * 1000.0 * i / VoiceCodec.RATE)
	var data := VoiceCodec.encode(tone)
	var back := VoiceCodec.decode(data)
	var error := 0.0
	for i in tone.size():
		error = maxf(error, absf(back[i] - tone[i]))
	_check(error < 0.0001, "the voice codec round trip is near exact (error %.6f)" % error)
	_check(is_equal_approx(VoiceCodec.seconds(data), 1.0), "encoded voice knows its length")
	for source_rate: float in [48000.0, 44100.0]:
		var kept := _resampled_rms(source_rate, 1000.0)
		var folded := _resampled_rms(source_rate, 20000.0)
		_check(
			absf(kept - 0.5 / sqrt(2.0)) < 0.02 and folded < 0.01,
			(
				"resampling from %d Hz keeps 1 kHz (rms %.3f) and cuts 20 kHz (rms %.4f)"
				% [source_rate, kept, folded]
			)
		)
	var faded := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
	VoiceCodec.fade(faded, 2, 2)
	_check(faded[0] == 0.0 and faded[3] == 0.0 and faded[1] > 0.0, "voice fades in and out")
	Sfx.clear_cache()
	var sounds: Array[String] = [
		"step",
		"corn_step",
		"rustle",
		"snap",
		"thud",
		"splash",
		"clank",
		"coin",
		"screech",
		"caw",
		"heartbeat",
	]
	var built := true
	for sound in sounds + Sfx.LOOPS:
		for take in Sfx.takes(sound):
			built = built and Sfx.get_sound(sound, take).data.size() > 0
	_check(built, "every sound effect builds (%d recorded steps)" % Sfx._recorded("step").size())
	_check(
		Sfx.get_sound("step", 0).data != Sfx.get_sound("step", 1).data,
		"footsteps come in different takes"
	)
	for sound in Sfx.LOOPS:
		var loop := Sfx.get_sound(sound)
		var first := loop.data.decode_s16(0) / 32768.0
		var last := loop.data.decode_s16(loop.data.size() - 2) / 32768.0
		_check(absf(first - last) < 0.05, "%s loops without a click (%.3f)" % [sound, last - first])


## In a chase the heart races faster the closer the creature, the drone swells
## in, and the heart is still pounding a little after the chase ends.
func _check_chase_sounds() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var ambience := Sfx.Ambience.new(holder)
	ambience.update(2.0, true, false, 20.0, true, false)
	var far := ambience.heart_rate()
	for i in 4:
		ambience.update(1.0, true, false, 3.0, true, false)
	var near := ambience.heart_rate()
	var drone: AudioStreamPlayer = ambience.get("_chase")
	_check(
		near > far and near > 140.0 and drone.volume_db > -10.0,
		"a chase races the heart (%.0f bpm at 20 m, %.0f at 3 m) and swells the drone" % [far, near]
	)
	ambience.update(3.0, true, false, INF, false, false)
	var after := ambience.heart_rate()
	for i in 20:
		ambience.update(1.0, true, false, INF, false, false)
	_check(
		after > 0.0 and ambience.heart_rate() == 0.0 and not drone.playing,
		"the heart calms after the chase (%.0f bpm 3 s on, then still)" % after
	)
	for player in holder.find_children("*", "AudioStreamPlayer*", true, false):
		player.call("stop")
	holder.queue_free()


## The RMS of a sine at hz after the voice resampler, from source_rate, fed in
## 20 ms pieces as the microphone would; the first 0.1 s (filters settling) is
## left out.
func _resampled_rms(source_rate: float, hz: float) -> float:
	var codec := VoiceCodec.new(source_rate)
	var out := PackedFloat32Array()
	var piece := roundi(source_rate * 0.02)
	for start in range(0, roundi(source_rate), piece):
		var frames := PackedVector2Array()
		frames.resize(piece)
		for i in piece:
			var value := 0.5 * sin(TAU * hz * (start + i) / source_rate)
			frames[i] = Vector2(value, value)
		out.append_array(codec.resample(frames))
	return VoiceCodec.rms(out.slice(roundi(0.1 * VoiceCodec.RATE)))


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
		# Players first: test-only ones stand for peers that never connected, and
		# freeing them with the game crashed Godot on quit now and then.
		for player in get_tree().get_nodes_in_group("players"):
			player.queue_free()
		await _frames(10)
		_game.queue_free()
	await _frames(10)
	Sfx.clear_cache()
	get_tree().quit(1 if _failed else 0)


## Phase 3: the Director's scares and wounds, the night trail, the dead-voice
## twist and the ghosts' lantern flicker.
func _check_phase3() -> void:
	var director := _game.director
	var creature := _game.creature
	# A full meter springs a scare (a lunge or a whisper here, picked at random).
	var edge := Farm.corn_edge_near(Vector3(0, 0, 20), 1.0)
	_put(_player, edge - Vector3(0, 0, 2.5))
	_player.kneeling = true
	director.tension = 1.0
	director.call("_try_scare")  # Not by waiting: a call meanwhile takes some tension off.
	_check(director.tension < 0.5, "a full meter sprang a scare (%.2f left)" % director.tension)
	# A lunge at a player kneeling by the corn: knocked down, wounded, it pulls back.
	director.lunge(_player)
	_player.kneeling = false
	await _frames(2)
	_check(_player.wounded and _player.stumble_left > 0.0, "the lunge knocked down and wounded")
	_check(creature.state == Creature.State.RETREAT, "after the lunge it pulled back")
	# Wounded at night: it leaves a trail the creature can follow; dawn heals it.
	_dev.jump_to("night")
	await _game_seconds(Director.TRAIL_BEHIND + Director.TRAIL_EVERY * 2.0)
	_check(director.trail_point().is_finite(), "a wounded player leaves a trail at night")
	director.dawn()
	await _frames(2)
	_check(not _player.wounded, "dawn heals the wound")
	_dev.jump_to("day")
	await _frames(3)
	# The stare: it stands in the rows watching, then is gone.
	director.stare(_player)
	_check(creature.state == Creature.State.STARE, "it stares from the rows")
	await _game_seconds(Creature.STARE_TIME + 0.5)
	_check(creature.state == Creature.State.RETREAT, "then pulls back into the corn")
	_check(director.whisper(_player), "a friend's voice can whisper behind a player")
	director.crow(_player)
	_check(director.tension == 0.0, "the crow fake-out left the tension down")
	# The dead-voice twist: a dead friend's voice is played through static.
	var tells := {}
	var on_spoke := func(_at: Vector3, _heard: Dictionary, told: Dictionary) -> void:
		tells.merge(told, true)
	creature.spoke.connect(on_spoke)
	VoiceChat.get("_dead")[FRIEND] = true
	for i in 10:
		creature.speak_now()
	VoiceChat.get("_dead")[FRIEND] = false
	creature.spoke.disconnect(on_spoke)
	_check(
		str(tells.get(1, "")).ends_with("through static"),
		"a dead friend's voice comes through static"
	)
	# The lantern flicker: a ghost flickers a living teammate's lantern.
	var players: MultiplayerSpawner = _game.get("_players")
	var other := players.spawn(_game.call("_player_data", FRIEND, "Bea")) as Player
	other.set_physics_process(false)
	await _frames(2)
	_put(other, Vector3(-10, 0, 0))
	other.lantern = true
	_player.killed()
	_put(_player, Vector3(-14, 0, 0))
	var ghosts := _game.get_node("Ghosts") as Ghosts
	var light := ghosts.light_for(_player.global_position)
	_check(light.get("kind", "") == "lantern", "a ghost near a teammate's lantern can flicker it")
	ghosts.rpc_id(1, "_ask_flicker")  # From the host's own player, the ghost.
	await _frames(2)
	_check(other.get("_flicker_left") > 0.0, "the lantern flickered")
	_put(_player, Vector3(-40, 0, 0))
	_check(ghosts.light_for(_player.global_position).is_empty(), "but not from far away")
	await _game_seconds(Ghosts.FLICKER_TIME + 0.5)  # Let the flicker end first.
	other.queue_free()
	await _frames(2)
	_dev.revive(_player)
