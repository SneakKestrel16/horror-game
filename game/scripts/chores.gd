class_name Chores
extends Node
## The farm's tools and crops, and everything the E key does: picking up and
## dropping, planting, watering, harvesting, selling, fuel, and the traps
## (disarming, filling, prying free, carrying a bear trap back to the
## pegboard). The local player's use prompt is worked out here; the request
## goes to the host, which checks it still makes sense (another player may have
## got there first) and tells every peer what changed. Same path ("Chores") on
## every peer. Seeds and upgrades come from the Store.

## A plot's crop. EMPTY: harvested, to replant from a seed pack. LOCKED:
## overgrown until the team buys the new plots (Store).
enum Stage { DRY, GROWING, RIPE, EMPTY, LOCKED }

const GROW_TIME := 60.0  ## Seconds from watered to ripe (scaled like the phases).
## Each crop's growing time in GROW_TIMEs, keeping the doc's ratios (Crops:
## turnips 1 day, pumpkins 2). Moonflowers grow only at night ("1 night") and
## wilt at dawn if not picked: the doc's "night harvest only".
const GROWTH := {"turnip": 1.0, "pumpkin": 2.0, "moonflower": 1.0}
const NIGHT_CROPS: Array[String] = ["moonflower"]
const CAN_WATER := 4  ## Plots one watering can full waters.
const BIG_CAN := 8  ## With the bigger watering can (Store).
## Per plot. Design doc, Crops.
const PRICES := {"turnip": 10, "pumpkin": 25, "corn": 45, "moonflower": 70}
const CROP_NAMES := {
	"turnip": "turnips", "pumpkin": "pumpkin", "corn": "corn", "moonflower": "moonflowers"
}
const USE_RANGE := 2.0
const LOOK_ANGLE := 0.7  ## Radians (40°) either side of where a player faces.
const TRAP_LOOK_ANGLE := 0.45  ## Traps are only found by looking right at them (26°).
## Seconds to hold E. Prying is quicker with a friend (design doc, Night Traps).
## Cutting corn and planting are guesses: the doc's "a hold of a few seconds".
const HOLD := {
	"disarm": 4.0, "fill": 3.0, "pry": 3.0, "help": 1.5, "refuel": 3.0, "cut": 3.0, "plant": 1.5
}
## Holds the upgrades change (Store): the oiled crowbar, the quiet watering can.
const UPGRADED_HOLD := {"disarm": 2.0, "pry": 2.0, "water": 1.5}
const ITEM_NAMES := {
	"watering_can": "watering can",
	"shovel": "shovel",
	"crowbar": "crowbar",
	"fuel_can": "fuel can",
	"turnip": "turnip",
	"pumpkin": "pumpkin",
	"corn": "corn",
	"moonflower": "moonflowers",
	"bear_trap": "bear trap",
	"turnip_seeds": "turnip seeds",
	"pumpkin_seeds": "pumpkin seeds",
	"moonflower_seeds": "moonflower seeds",
}

var game: Game
## {kind, holder (peer id, 0 on the ground, -1 gone), position, charge}.
var items: Array[Dictionary] = []
var plots: Array[int] = []
var crops: Array[String] = []  ## What each plot grows (or last grew).
var corn: Array[int] = []  ## Each planted corn plot's Stage: RIPE, or EMPTY once cut.
var _grow_left: Array[float] = []  ## Host only.
var _hold_key := ""
var _hold_time := 0.0
var _item_nodes: Array[Node3D] = []
var _plot_nodes: Array[Node3D] = []


func _process(delta: float) -> void:
	_place_items()
	var player := game.local_player()
	if player and not game.ended:
		_interact(player, delta)


## Host only: watered plots grow; moonflowers only at night.
func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or game.in_lobby or game.ended:
		return
	var night := game.phase() == "night"
	for i in plots.size():
		if plots[i] == Stage.GROWING and (night or crops[i] not in NIGHT_CROPS):
			_grow_left[i] -= delta * game.clock_rate
			if _grow_left[i] <= 0.0:
				_set_plot.rpc(i, Stage.RIPE, crops[i])


## Asks the host to do action (to item, plot or trap index).
func request(action: String, index: int) -> void:
	_request.rpc_id(1, action, index)


## Host only (dev panel): every plot that isn't overgrown ripe.
func ripen_all() -> void:
	game.log_event("dev: ripened every plot")
	for i in plots.size():
		if plots[i] != Stage.LOCKED:
			_set_plot.rpc(i, Stage.RIPE, crops[i])


## Host only: a new item of kind with charge, in peer's hands if they are
## empty, else on the ground at at (a seed pack from the Store).
func give(peer: int, kind: String, charge: int, at: Vector3) -> void:
	var holder := peer if _held_index(peer) < 0 else 0
	_sync_item(items.size(), holder, at, charge, kind)


## Host only: the overgrown plots are cleared, ready to plant (Store).
func unlock_plots() -> void:
	for i in plots.size():
		if plots[i] == Stage.LOCKED:
			_set_plot.rpc(i, Stage.EMPTY, crops[i])


## Host only, at dawn: moonflowers left unpicked wilt.
func dawn() -> void:
	var wilted := 0
	for i in plots.size():
		if crops[i] == "moonflower" and plots[i] in [Stage.RIPE, Stage.GROWING]:
			_set_plot.rpc(i, Stage.EMPTY, crops[i])
			wilted += 1
	if wilted > 0:
		game.log_event("%s wilted at dawn" % Game.counted(wilted, "moonflower plot"))


## Plots a full watering can waters, with or without the bigger can (Store).
static func can_size() -> int:
	return BIG_CAN if Store.owns("big_can") else CAN_WATER


## Seconds to hold E for action, with the upgrades the team owns (Store).
static func hold_for(action: String) -> float:
	var upgrade := {"disarm": "crowbar", "pry": "crowbar", "water": "quiet_can"}
	if UPGRADED_HOLD.has(action) and Store.owns(upgrade[action]):
		return UPGRADED_HOLD[action]
	return HOLD.get(action, 0.0)


func snapshot() -> Dictionary:
	return {"items": items, "plots": plots, "crops": crops, "corn": corn}


## Client: takes the host's tools and crops on joining.
func apply_snapshot(data: Dictionary) -> void:
	var host_items: Array = data["items"]
	for i in host_items.size():
		var item: Dictionary = host_items[i]
		_set_item(i, item["kind"], item["holder"], item["position"], item["charge"])
	var host_plots: Array = data["plots"]
	var host_crops: Array = data["crops"]
	for i in host_plots.size():
		_set_plot(i, host_plots[i], host_crops[i])
	var host_corn: Array = data["corn"]
	for i in host_corn.size():
		_set_corn(i, host_corn[i])


func _ready() -> void:
	_build_world_state()


## The tools where Farm puts them, the first four plots ripe, the rest of the
## field dry and the new plots (Farm.LOCKED_PLOTS) overgrown.
func _build_world_state() -> void:
	for item in Farm.ITEMS:
		var charge := CAN_WATER if item["kind"] == "watering_can" else 0
		items.append(
			{"kind": item["kind"], "holder": 0, "position": item["position"], "charge": charge}
		)
		_item_nodes.append(Looks.item(game, item["kind"]))
	items[3]["charge"] = 1  # The fuel can starts full.
	var first_locked := Farm.PLOTS.size() - Farm.LOCKED_PLOTS
	for i in Farm.PLOTS.size():
		var stage := Stage.RIPE if i < 4 else Stage.DRY
		plots.append(Stage.LOCKED if i >= first_locked else stage)
		crops.append("turnip")
		_grow_left.append(0.0)
		var node := Node3D.new()
		node.position = Farm.PLOTS[i]
		game.add_child(node)
		_plot_nodes.append(node)
		Looks.plot(node, plots[i], crops[i])
	for i in Farm.CORN_PLOTS.size():
		corn.append(Stage.RIPE)


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
	for i in game.traps.traps.size():
		var trap := game.traps.traps[i]
		if trap["state"] == TrapField.State.SPRUNG and trap["kind"] == "bear":
			if trap["victim"] == me:
				return _act("Hold E to pry the jaws open", "pry", i, hold_for("pry"))
			if (
				trap["victim"] != 0
				and Farm.near(player.global_position, trap["position"], USE_RANGE)
			):
				return _act("Hold E to help pry them free", "pry", i, HOLD["help"])
	return _act("", "", -1, 0.0)


func _trap_action(player: Player, kind: String) -> Dictionary:
	for i in game.traps.traps.size():
		var trap := game.traps.traps[i]
		var lying: bool = trap["state"] == TrapField.State.DISARMED and trap["kind"] == "bear"
		if lying and _looking_at(player, trap["position"]):
			return _act("E: pick up the bear trap (hang it back in the shed)", "take_trap", i, 0.0)
		if (
			trap["state"] != TrapField.State.ARMED
			or not _looking_at(player, trap["position"], true)
		):
			continue
		var bear: bool = trap["kind"] == "bear"
		if bear and kind == "crowbar":
			return _act("Hold E to disarm the bear trap", "disarm", i, hold_for("disarm"))
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
		var hold := 0.0
		var crop: String = CROP_NAMES[crops[i]]
		match plots[i]:
			Stage.LOCKED:
				text = "Overgrown. The store's new plots would clear it."
			Stage.EMPTY:
				text = "Bare soil. Buy seeds at the store (B by the shipping crate)."
				if Store.SEEDS.has(kind):
					text = "Hold E to plant the %s" % ITEM_NAMES[kind]
					action = "plant"
					hold = HOLD["plant"]
			Stage.DRY:
				text = "Dry %s. Needs the watering can." % crop
				if kind == "watering_can":
					text = (
						"E: water the %s" % crop
						if charge > 0
						else "The can is empty. Fill it at the pump."
					)
					action = "water" if charge > 0 else ""
					hold = hold_for("water")
					if hold > 0.0:
						text = "Hold E to water the %s quietly" % crop
			Stage.GROWING:
				text = "Growing..."
				if crops[i] in NIGHT_CROPS and game.phase() != "night":
					text = "Moonflowers. They only grow at night."
			Stage.RIPE:
				text = "E: pick the %s" % crop if kind == "" else "Ripe. Hands full (G to drop)."
				action = "harvest" if kind == "" else ""
		if text != "":
			return _act(text, action, i, hold)
	for i in corn.size():
		if corn[i] == Stage.RIPE and _looking_at(player, Farm.CORN_PLOTS[i]):
			if kind != "":
				return _act("Ripe corn. Hands full (G to drop).", "", i, 0.0)
			return _act("Hold E to cut the corn", "cut", i, HOLD["cut"])
	return _act("", "", -1, 0.0)


## The pump, the shipping crate, the fuel drum and the generator.
func _place_action(player: Player, kind: String, charge: int) -> Dictionary:
	var text := ""
	var action := ""
	var hold := 0.0
	if _looking_at(player, Farm.PEGBOARD):
		text = "Pegboard: %d of %d bear traps" % [game.traps.board, TrapField.SLOTS]
		if kind == "bear_trap":
			text = "E: hang the bear trap on the pegboard"
			action = "hang"
	elif _looking_at(player, Farm.PUMP) and kind == "watering_can":
		text = "E: fill the watering can"
		action = "pump"
	elif _looking_at(player, Farm.CRATE):
		text = "Shipping crate. Bring crops here. B: the store."
		if kind in PRICES:
			text = "E: sell the %s (+%d)" % [CROP_NAMES[kind], PRICES[kind]]
			action = "sell"
	elif _looking_at(player, Farm.FUEL_DRUM) and kind == "fuel_can" and charge == 0:
		text = "E: fill the fuel can"
		action = "fuel"
	elif _looking_at(player, Farm.GENERATOR):
		text = "Generator: %d%% fuel" % roundi(game.fuel * 100)
		if kind == "fuel_can" and charge > 0:
			text = "Hold E to refuel the generator"
			action = "refuel"
			hold = HOLD["refuel"]
	return _act(text, action, -1, hold)


static func _act(text: String, action: String, index: int, hold: float) -> Dictionary:
	return {"text": text, "action": action, "index": index, "hold": hold}


## The local player's E key: instant actions on press, held ones once held long enough.
func _interact(player: Player, delta: float) -> void:
	if player.dead:
		game.hud.prompt(
			"Dead until dawn. F: flicker a light near a teammate · E in the corn: rustle it"
		)
		return
	if game.in_lobby:
		game.hud.prompt("")
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
	game.hud.prompt(text)
	if found["action"] == "":
		return
	if hold > 0.0 and _hold_time >= hold:
		_hold_time = 0.0
		player.kneeling = false
		_request.rpc_id(1, found["action"], found["index"])
	elif hold == 0.0 and Input.is_action_just_pressed("interact"):
		_request.rpc_id(1, found["action"], found["index"])


## Within reach and in front: within LOOK_ANGLE of where the body faces, or
## for a trap, within TRAP_LOOK_ANGLE of where the eyes look.
func _looking_at(player: Player, point: Vector3, closely := false) -> bool:
	if not Farm.near(player.global_position, point, USE_RANGE):
		return false
	if closely:
		return player.look_direction().angle_to(point - player.eye_position()) < TRAP_LOOK_ANGLE
	var facing := -player.global_basis.z
	var to_point := point - player.global_position
	to_point.y = 0.0
	return to_point.length() < 0.6 or Vector3(facing.x, 0, facing.z).angle_to(to_point) < LOOK_ANGLE


## The item peer carries ({kind, holder, position, charge}), or {}.
func held_item(peer: int) -> Dictionary:
	var held := _held_index(peer)
	return items[held] if held >= 0 else {}


func _held_index(peer: int) -> int:
	for i in items.size():
		if items[i]["holder"] == peer:
			return i
	return -1


## A player asks the host to do something. The host checks it still makes
## sense (another player may have got there first) and applies it.
@rpc("any_peer", "call_local", "reliable")
func _request(action: String, index: int) -> void:
	if not multiplayer.is_server() or game.ended or game.in_lobby:
		return
	var peer := multiplayer.get_remote_sender_id()
	var player := game.get_node_or_null("Players/%d" % peer) as Player
	if player == null or player.dead:
		return
	var held := _held_index(peer)
	var kind: String = items[held]["kind"] if held >= 0 else ""
	var at := player.global_position
	match action:
		"drop":
			drop_held(peer, player.drop_point())
		"pickup":
			if index < 0 or index >= items.size() or items[index]["holder"] != 0:
				return
			drop_held(peer, items[index]["position"])
			_sync_item(index, peer, items[index]["position"], items[index]["charge"])
		"plant":
			if Store.SEEDS.has(kind) and _plot_is(index, Stage.EMPTY):
				var crop: String = Store.SEEDS[kind][0]
				var left: int = items[held]["charge"] - 1
				_sync_item(held, peer if left > 0 else -1, at, left)
				_set_plot.rpc(index, Stage.DRY, crop)
				game.make_noise("harvest", Farm.PLOTS[index], "step")
				game.log_event("%s planted %s in plot %d" % [player.label(), crop, index + 1])
		"water":
			if kind == "watering_can" and items[held]["charge"] > 0 and _plot_is(index, Stage.DRY):
				_sync_item(held, peer, at, items[held]["charge"] - 1)
				_grow_left[index] = GROW_TIME * GROWTH[crops[index]] * game.short_factor()
				_set_plot.rpc(index, Stage.GROWING, crops[index])
				var quiet := Store.owns("quiet_can")
				game.make_noise("water_quiet" if quiet else "water", Farm.PLOTS[index], "splash")
		"harvest":
			if held < 0 and _plot_is(index, Stage.RIPE):
				_set_plot.rpc(index, Stage.EMPTY, crops[index])
				_sync_item(items.size(), peer, at, 0, crops[index])
				game.make_noise("harvest", Farm.PLOTS[index], "step")
		"pump":
			if kind == "watering_can":
				_sync_item(held, peer, at, can_size())
				game.make_noise("pump", Farm.PUMP, "splash")
		"cut":
			if held < 0 and index >= 0 and index < corn.size() and corn[index] == Stage.RIPE:
				_set_corn.rpc(index, Stage.EMPTY)
				_sync_item(items.size(), peer, at, 0, "corn")
				game.make_noise("cut", Farm.CORN_PLOTS[index], "rustle")
				game.log_event("%s cut corn plot %d" % [player.label(), index + 1])
		"sell":
			if kind in PRICES:
				_sync_item(held, -1, at, 0)
				game.coins += PRICES[kind]
				game.sync_state()
				game.make_noise("sell", Farm.CRATE, "coin")
				var crop: String = CROP_NAMES[kind]
				game.log_event("%s sold %s (coins %d)" % [player.label(), crop, game.coins])
		"fuel":
			if kind == "fuel_can":
				_sync_item(held, peer, at, 1)
				game.make_noise("fuel", Farm.FUEL_DRUM, "splash")
		"refuel":
			if kind == "fuel_can" and items[held]["charge"] > 0:
				_sync_item(held, peer, at, 0)
				game.fuel = minf(1.0, game.fuel + Game.FUEL_PER_CAN)
				game.fuel_warned = false
				game.sync_state()
				game.make_noise("refuel", Farm.GENERATOR, "clank")
				game.log_event(
					"%s refuelled the generator (%d%%)" % [player.label(), roundi(game.fuel * 100)]
				)
		"hang":
			if kind == "bear_trap" and game.traps.board < TrapField.SLOTS:
				_sync_item(held, -1, at, 0)
				game.traps.set_board(game.traps.board + 1)
				game.make_noise("hang", Farm.PEGBOARD, "clank")
				game.log_event(
					(
						"%s hung a bear trap back up (%d on the pegboard)"
						% [player.label(), game.traps.board]
					)
				)
		_:
			_trap_request(action, index, player, held, kind)


## The trap actions of _request: disarm, fill, pry, take_trap.
func _trap_request(action: String, index: int, player: Player, held: int, kind: String) -> void:
	if index < 0 or index >= game.traps.traps.size():
		return
	var trap := game.traps.traps[index]
	var at: Vector3 = trap["position"]
	match action:
		"disarm", "fill":
			var tool := "crowbar" if action == "disarm" else "shovel"
			if trap["state"] == TrapField.State.ARMED and kind == tool:
				game.traps.set_state(index, TrapField.State.DISARMED)
				game.make_noise(action, at, "clank" if tool == "crowbar" else "thud")
				game.log_event("%s cleared %s trap %d" % [player.label(), trap["kind"], index])
		"pry":
			if trap["state"] == TrapField.State.SPRUNG:
				var victim: int = trap["victim"]
				var trapped := game.get_node_or_null("Players/%d" % victim) as Player
				game.traps.set_state(index, TrapField.State.DISARMED)
				game.make_noise("pry", at, "clank")
				game.alone_for.erase(victim)
				if trapped and not trapped.dead:
					trapped.released.rpc_id(victim)
				game.log_event(
					(
						"%s pried themselves free" % player.label()
						if trapped == player
						else (
							"%s pried %s free"
							% [player.label(), trapped.label() if trapped else "someone"]
						)
					)
				)
		"take_trap":
			if trap["state"] == TrapField.State.DISARMED and trap["kind"] == "bear":
				var peer := player.get_multiplayer_authority()
				if held >= 0:
					drop_held(peer, at)
				game.traps.set_state(index, TrapField.State.HIDDEN)
				_sync_item(items.size(), peer, at, 0, "bear_trap")
				game.make_noise("take", at, "clank")


## Host only: an item is gone for good (sold, or taken by the creature).
func vanish_item(index: int) -> void:
	_sync_item(index, -1, items[index]["position"], 0)


func drop_held(peer: int, at: Vector3) -> void:
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
		_item_nodes.append(Looks.item(game, kind))
	items[index] = {"kind": kind, "holder": holder, "position": at, "charge": charge}


@rpc("authority", "call_local", "reliable")
func _set_plot(index: int, stage: int, crop: String) -> void:
	plots[index] = stage
	crops[index] = crop
	Looks.plot(_plot_nodes[index], stage, crop)


## Whether index is a plot at stage (a request may name any index).
func _plot_is(index: int, stage: int) -> bool:
	return index >= 0 and index < plots.size() and plots[index] == stage


## Cut corn is open ground for good: no cover, and the creature can't walk it by day.
@rpc("authority", "call_local", "reliable")
func _set_corn(index: int, stage: int) -> void:
	if corn[index] != stage and stage == Stage.EMPTY:
		game.farm.cut_corn(index)
	corn[index] = stage


func _place_items() -> void:
	for i in items.size():
		var node := _item_nodes[i]
		var holder: int = items[i]["holder"]
		node.visible = holder != -1
		if holder > 0:
			var player := game.get_node_or_null("Players/%d" % holder) as Player
			if player and player.hand:
				node.global_transform = player.hand.global_transform.scaled_local(Vector3.ONE * 0.6)
				node.visible = not player.dead
				continue
		node.transform = Transform3D(Basis(), items[i]["position"])
