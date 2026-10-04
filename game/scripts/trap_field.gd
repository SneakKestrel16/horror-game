class_name TrapField
extends Node3D
## Every trap on the farm, and the shed's pegboard (Phase 2). Bear traps hang
## on the pegboard until the creature takes them at night and hides them; pits
## it digs. Disarmed bear traps can be carried back and hung up again, which
## stops it reusing them. Any bear trap not on the pegboard at nightfall is the
## creature's: it vanishes once nobody living is near enough to see, or by
## morning at the latest (design doc, The Tool Shed).
##
## The host owns all of it and tells every peer through RPCs on this node,
## which has the same path ("Traps") everywhere.

enum State { HIDDEN, ARMED, SPRUNG, DISARMED }  ## HIDDEN: gone (carried off or vanished).

const SLOTS := 4  ## Bear traps on the pegboard at the start.
## Traps set each night with 4 players, as (bear traps, pits): the design doc's
## Ramp-Up for days 1 and 2. Smaller teams scale it (Game.team_scale).
const RAMP: Array[Vector2i] = [Vector2i(2, 1), Vector2i(2, 2)]
const WIPE_EXTRA := Vector2i(1, 1)  ## More if everyone died: it had the farm to itself.
const SPACING := 5.0  ## Metres between traps.
## Chance a trap goes on a path instead of its usual place. Bear traps were 0.4
## like pits, and a playtest morning had both on paths (2026-10-04); the design
## doc wants them mostly in the corn.
const ON_PATH := {"bear": 0.15, "pit": 0.4}
const UNSEEN := 15.0  ## A claimed trap vanishes with no living player this close.
const BEAR_REACH := 0.55  ## How close a foot must come to spring a trap (m).
const PIT_REACH := 0.65

var game: Game
var traps: Array[Dictionary] = []  ## {kind, position, state, victim}.
var board := SLOTS  ## Bear traps hanging on the pegboard.

# Host only.
var stock := 0  ## Bear traps the creature has taken and not yet set.
var orders: Array[Dictionary] = []  ## Tonight's traps still to set: {kind, position}.
var _claimed_items: Array[int] = []
var _claimed_traps: Array[int] = []
var _claim_left := 0.0
var _rng := RandomNumberGenerator.new()

var _nodes: Array[Node3D] = []
var _board_node := Node3D.new()


func _ready() -> void:
	_rng.randomize()
	_board_node.position = Farm.PEGBOARD
	add_child(_board_node)
	Looks.pegboard(_board_node, board, SLOTS)


## Host only: night or not, checks the claimed traps each second.
func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or game == null or game.phase() != "night":
		return
	_claim_left -= delta
	if _claim_left <= 0.0:
		_claim_left = 1.0
		_claim_and_vanish()


func armed_positions() -> Array[Vector3]:
	var armed: Array[Vector3] = []
	for trap in traps:
		if trap["state"] == State.ARMED:
			armed.append(trap["position"])
	return armed


## Host only: a new armed trap at a point.
func arm(kind: String, at: Vector3) -> void:
	_set_trap.rpc(traps.size(), kind, Vector3(at.x, 0, at.z), State.ARMED, 0)


## Host only: changes trap index's state (victim: the trapped peer, or 0).
func set_state(index: int, state: State, victim := 0) -> void:
	var trap := traps[index]
	_set_trap.rpc(index, trap["kind"], trap["position"], state, victim)


## Host only.
func set_board(count: int) -> void:
	_set_board.rpc(clampi(count, 0, SLOTS))


## Host only: tonight's work for the creature, from the ramp for this night
## (0-based) scaled to the team. Off-board traps are claimed as the night goes;
## the pegboard supplies the rest.
func plan_night(night: int, team: float) -> void:
	var ramp := RAMP[mini(night, RAMP.size() - 1)]
	plan(maxi(1, roundi(ramp.x * team)), maxi(1, roundi(ramp.y * team)))


## Host only: replaces the creature's orders with this many traps to set.
func plan(bears: int, pits: int) -> void:
	orders.clear()
	for i in bears:
		_order("bear")
	for i in pits:
		_order("pit")
	_claim_left = 0.0
	game.log_event(
		(
			"the creature means to set %s and %s"
			% [Game.counted(bears, "bear trap"), Game.counted(pits, "pit")]
		)
	)


## Host only: the trap the creature should set next, the one nearest to
## from that it can set (a bear trap needs one in hand), or {}.
func next_order(from: Vector3) -> Dictionary:
	var best := {}
	for order in orders:
		if order["kind"] == "bear" and stock <= 0:
			continue
		var closer := (
			best.is_empty()
			or (from.distance_to(order["position"]) < from.distance_to(best["position"]))
		)
		if closer:
			best = order
	return best


## Host only: the creature reached the shed door. It takes what tonight needs.
func take_from_board() -> void:
	var needed := 0
	for order in orders:
		needed += 1 if order["kind"] == "bear" else 0
	var taken := mini(board, maxi(0, needed - stock))
	if taken > 0:
		stock += taken
		set_board(board - taken)
		game.log_event(
			(
				"the creature took %s from the pegboard (%d left)"
				% [Game.counted(taken, "bear trap"), board]
			)
		)


## Host only: the creature stands at an order's spot (the nearest it can set
## to at, or the first left at dawn) and sets it.
func fulfil(at: Vector3) -> void:
	var order := next_order(at)
	if order.is_empty():
		if orders.is_empty():
			return
		order = orders[0]  # A bear trap with none left: drop the order.
		orders.erase(order)
		return
	orders.erase(order)
	if order["kind"] == "bear":
		stock -= 1
	arm(order["kind"], order["position"])
	game.log_event("the creature set a %s at %s" % [order["kind"], Game._where(order["position"])])


## Host only: whether tonight needs more bear traps than the creature holds
## and the pegboard has some: then it goes to the shed first, once.
func needs_board() -> bool:
	var bears := 0
	for order in orders:
		bears += 1 if order["kind"] == "bear" else 0
	return bears > stock and board > 0


## Host only, at dawn: what the creature didn't get to, it did anyway, and
## every claimed trap is gone.
func finish_night() -> void:
	if needs_board():
		take_from_board()
	while not orders.is_empty():
		fulfil(Vector3.ZERO)
	_claim_and_vanish(true)
	_claimed_items.clear()
	_claimed_traps.clear()


## Host only: springs any armed trap a living player steps on.
func check(players: Array[Player]) -> void:
	for i in traps.size():
		var trap := traps[i]
		if trap["state"] != State.ARMED:
			continue
		var reach := BEAR_REACH if trap["kind"] == "bear" else PIT_REACH
		for player in players:
			if player.pinned or not Farm.near(player.global_position, trap["position"], reach):
				continue
			game.trap_sprung(i, player)
			break


## Host only: any off-board bear trap not in a player's hands becomes the
## creature's, and those nobody is near vanish (all of them, at dawn).
func _claim_and_vanish(all := false) -> void:
	for i in game.chores.items.size():
		var item: Dictionary = game.chores.items[i]
		if item["kind"] == "bear_trap" and item["holder"] == 0 and i not in _claimed_items:
			_claimed_items.append(i)
			stock += 1
	for i in traps.size():
		var trap := traps[i]
		if trap["kind"] == "bear" and trap["state"] == State.DISARMED and i not in _claimed_traps:
			_claimed_traps.append(i)
			stock += 1
	for i: int in _claimed_items.duplicate():
		var item: Dictionary = game.chores.items[i]
		if item["holder"] > 0:
			_claimed_items.erase(i)  # Picked up again before it went.
			stock = maxi(0, stock - 1)
		elif item["holder"] == 0 and (all or not _seen(item["position"])):
			game.chores.vanish_item(i)
			_claimed_items.erase(i)
			game.log_event(
				"a bear trap off the pegboard vanished from %s" % Game._where(item["position"])
			)
	for i: int in _claimed_traps.duplicate():
		var trap := traps[i]
		if trap["state"] != State.DISARMED:
			_claimed_traps.erase(i)
		elif all or not _seen(trap["position"]):
			set_state(i, State.HIDDEN)
			_claimed_traps.erase(i)
			game.log_event("a bear trap lying at %s vanished" % Game._where(trap["position"]))


func _seen(at: Vector3) -> bool:
	for player in game.living_players():
		if player.global_position.distance_to(at) < UNSEEN:
			return true
	return false


func _order(kind: String) -> void:
	var spot := _pick_spot(kind)
	if spot.is_finite():
		orders.append({"kind": kind, "position": spot})


## A spot for a new trap: bear traps mostly hidden just inside the corn, pits
## mostly between the rows and on the paths, never near another trap.
func _pick_spot(kind: String) -> Vector3:
	var spots := Farm.trap_spots()
	var first := "corn" if kind == "bear" else "rows"
	var groups: Array[String] = [first, "path", "corn" if kind == "pit" else "rows"]
	if _rng.randf() < ON_PATH[kind]:
		groups = ["path", first]
	var taken: Array[Vector3] = []
	for trap in traps:
		if trap["state"] == State.ARMED or trap["state"] == State.SPRUNG:
			taken.append(trap["position"])
	for order in orders:
		taken.append(order["position"])
	for group in groups:
		var options: Array = spots[group].duplicate()
		while not options.is_empty():
			var spot: Vector3 = options.pop_at(_rng.randi() % options.size())
			if taken.all(func(other: Vector3) -> bool: return other.distance_to(spot) > SPACING):
				return spot
	return Vector3.INF


func snapshot() -> Dictionary:
	return {"traps": traps, "board": board}


## Client: takes the host's traps and pegboard on joining.
func apply_snapshot(data: Dictionary) -> void:
	var host_traps: Array = data["traps"]
	for i in host_traps.size():
		var trap: Dictionary = host_traps[i]
		_set_trap(i, trap["kind"], trap["position"], trap["state"], trap["victim"])
	_set_board(data["board"])


@rpc("authority", "call_local", "reliable")
func _set_trap(index: int, kind: String, at: Vector3, state: int, victim: int) -> void:
	while traps.size() <= index:
		traps.append({"kind": kind, "position": at, "state": State.HIDDEN, "victim": 0})
		var node := Node3D.new()
		add_child(node)
		_nodes.append(node)
	traps[index] = {"kind": kind, "position": at, "state": state, "victim": victim}
	_nodes[index].position = at
	Looks.trap(_nodes[index], kind, state)


@rpc("authority", "call_local", "reliable")
func _set_board(count: int) -> void:
	board = count
	Looks.pegboard(_board_node, board, SLOTS)
