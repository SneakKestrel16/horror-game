class_name Store
extends Node
## The farm store, at the shipping crate (design doc, Upgrades): seed packs to
## replant harvested plots, and upgrades the whole team keeps for the run. B by
## the crate opens it (StorePanel), by day or at dusk; the host takes the coins
## and hands over the seeds or turns the upgrade on for everyone. Same path
## ("Store") on every peer.
##
## The design doc names the upgrades only as examples (a quiet watering can, a
## shed lock, walkie-talkies, brighter lanterns, new plots) and prices none, so
## every price and effect here is a first guess to tune from playtests. Seed
## prices are the doc's per plot (Crops); a pack plants SEEDS_PER_PACK plots.

## Seed packs: item kind -> [crop, price per plot, label].
const SEEDS := {
	"turnip_seeds": ["turnip", 4, "Turnip seeds"],
	"pumpkin_seeds": ["pumpkin", 10, "Pumpkin seeds"],
	"moonflower_seeds": ["moonflower", 25, "Moonflower seeds"],
}
const SEEDS_PER_PACK := {"turnip_seeds": 4, "pumpkin_seeds": 4, "moonflower_seeds": 2}
## Upgrades: id -> [price, name, what it does].
const UPGRADES := {
	"plots": [60, "Four new plots", "Clears the overgrown plots west of the field."],
	"big_can": [20, "Bigger watering can", "Waters 8 plots a fill instead of 4."],
	"quiet_can":
	[
		30,
		"Quiet watering can",
		"Watering carries 3 m instead of 9, but takes a 1.5 s hold.",
	],
	"crowbar": [20, "Oiled crowbar", "Disarming takes 2 s instead of 4; prying free 2 s."],
	"lanterns":
	[
		25,
		"Brighter lanterns",
		"Lanterns light 16 m instead of 10. The creature sees them from further too.",
	],
	"shed_lock":
	[
		40,
		"Shed lock",
		"The creature must break it to take traps: 15 s at the door, loud. Mended each dawn.",
	],
	"radios":
	[
		50,
		"Walkie-talkies",
		"Hear living teammates anywhere, over the radio. The creature can't use it.",
	],
}
const REACH := 4.0  ## Metres from the crate the store opens.

## The store in the running game, for the static checks (null between games).
static var current: Store

var game: Game
var owned := {}  ## Upgrade id -> true, on every peer.
var lock_broken := false  ## Host: the creature broke the shed lock tonight.


func _ready() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


## Whether the team owns an upgrade (false with no game running).
static func owns(id: String) -> bool:
	return current != null and current.owned.has(id)


## Whether player may shop now: alive, by the crate, by day or at dusk.
func open_for(player: Player) -> bool:
	return (
		player != null
		and not player.dead
		and (game.phase() == "day" or game.phase() == "dusk")
		and Farm.near(player.global_position, Farm.CRATE, REACH)
	)


## The price of a seed pack or an upgrade.
static func price(id: String) -> int:
	if SEEDS.has(id):
		return SEEDS[id][1] * SEEDS_PER_PACK[id]
	return UPGRADES[id][0]


## Asks the host to buy a seed pack or an upgrade.
func buy(id: String) -> void:
	_buy.rpc_id(1, id)


## Host only: tells a peer that just joined what the team owns.
func welcome(peer: int) -> void:
	for id: String in owned:
		_set_owned.rpc_id(peer, id)


## Host only, at dawn: the shed lock is mended.
func dawn() -> void:
	if lock_broken:
		lock_broken = false
		game.log_event("the shed lock was mended")


## Host only: the creature broke into the shed.
func break_lock() -> void:
	lock_broken = true
	game.make_noise("lock", Farm.SHED_DOOR_OUT, "clank")
	game.log_event("the creature broke the shed lock")


@rpc("any_peer", "call_local", "reliable")
func _buy(id: String) -> void:
	if not multiplayer.is_server() or game.ended or game.in_lobby:
		return
	var peer := multiplayer.get_remote_sender_id()
	var player := game.get_node_or_null("Players/%d" % peer) as Player
	if not open_for(player) or not (SEEDS.has(id) or UPGRADES.has(id)) or owned.has(id):
		return
	var cost := price(id)
	if game.coins < cost:
		_refused.rpc_id(peer, "Not enough coins: %d needed." % cost)
		return
	game.coins -= cost
	game.sync_state()
	game.make_noise("sell", Farm.CRATE, "coin")
	if SEEDS.has(id):
		game.chores.give(peer, id, SEEDS_PER_PACK[id], Farm.CRATE + Vector3(0, 0, -0.9))
		game.log_event(
			"%s bought %s (coins %d)" % [player.label(), SEEDS[id][2].to_lower(), game.coins]
		)
	else:
		_set_owned.rpc(id)
		game.log_event("%s bought %s (coins %d)" % [player.label(), UPGRADES[id][1], game.coins])
		if id == "plots":
			game.chores.unlock_plots()


@rpc("authority", "call_local", "reliable")
func _set_owned(id: String) -> void:
	owned[id] = true
	if id == "radios":
		VoiceChat.radio_enabled = true
	if not game.in_lobby and UPGRADES.has(id):
		game.flash("Bought: %s. %s" % [UPGRADES[id][1], UPGRADES[id][2]])


@rpc("authority", "call_local", "reliable")
func _refused(reason: String) -> void:
	game.flash(reason, 3.0)
