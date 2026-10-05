class_name Ghosts
extends Node
## What dead players can do until dawn (Phase 3; design doc, Dead Players Stay
## Involved). F flickers the light nearest the ghost that a living teammate is
## near: the one signal the creature can never fake, so a static voice backed
## by a flicker is a real teammate. E rustles the corn the ghost floats in, to
## point at something; the creature can fake that.
##
## Any light counts, a lantern or one of the barn's lamps: the doc's lantern
## alone would leave nothing to flicker when players hide in the dark (Review 2
## default for issue 5, to revisit). The host checks each request and tells
## every peer; same path ("Ghosts") everywhere.

const FLICKER_REACH := 8.0  ## Metres from the ghost to the light.
const TEAMMATE_NEAR := 10.0  ## Metres from the light to a living teammate.
const FLICKER_TIME := 1.5
const FLICKER_COOLDOWN := 10.0  ## Seconds, so it stays meaningful. Guess.
const RUSTLE_COOLDOWN := 3.0

var game: Game

var _ready_at := {}  ## Host: "flicker:<peer>" or "rustle:<peer>" -> msec when allowed again.


func _init(owner_game: Game) -> void:
	game = owner_game
	name = "Ghosts"


func _unhandled_input(event: InputEvent) -> void:
	var me := game.local_player()
	if me == null or not me.dead or game.ended:
		return
	if event.is_action_pressed("lantern"):
		_ask_flicker.rpc_id(1)
	elif event.is_action_pressed("interact") and Farm.in_corn(me.global_position):
		_ask_rustle.rpc_id(1)


## Host: the light a ghost at this point may flicker, as {kind, id, at}, or {}.
## kind "lantern" (id: the holder's peer) or "barn" (id: the lamp's index).
func light_for(ghost_at: Vector3) -> Dictionary:
	var lights: Array[Dictionary] = []
	for player in game.living_players():
		if player.lantern:
			var peer := player.get_multiplayer_authority()
			lights.append({"kind": "lantern", "id": peer, "at": player.global_position})
	if game.farm.barn_lit():
		for i in game.farm.barn_lights.size():
			lights.append({"kind": "barn", "id": i, "at": game.farm.barn_lights[i].global_position})
	var best := {}
	var best_distance := FLICKER_REACH
	for light in lights:
		var at: Vector3 = light["at"]
		var distance := Vector2(at.x - ghost_at.x, at.z - ghost_at.z).length()
		var watched := game.living_players().any(
			func(player: Player) -> bool:
				return Farm.near(player.global_position, at, TEAMMATE_NEAR)
		)
		if distance <= best_distance and watched:
			best = light
			best_distance = distance
	return best


@rpc("any_peer", "call_local", "reliable")
func _ask_flicker() -> void:
	var ghost := _ghost(multiplayer.get_remote_sender_id())
	if ghost == null or not _off_cooldown("flicker", ghost, FLICKER_COOLDOWN):
		return
	var light := light_for(ghost.global_position)
	if light.is_empty():
		_tell.rpc_id(ghost.get_multiplayer_authority(), "No light near a teammate to flicker.")
		return
	_flicker.rpc(light["kind"], light["id"])
	var what := "barn lamp %d" % light["id"]
	if light["kind"] == "lantern":
		var holder := game.get_node_or_null("Players/%d" % light["id"]) as Player
		what = "%s's lantern" % (holder.label() if holder else "a")
	game.log_event("%s's ghost flickered %s" % [ghost.label(), what])


@rpc("any_peer", "call_local", "reliable")
func _ask_rustle() -> void:
	var ghost := _ghost(multiplayer.get_remote_sender_id())
	if ghost == null or not Farm.in_corn(ghost.global_position):
		return
	if _off_cooldown("rustle", ghost, RUSTLE_COOLDOWN):
		var at := Vector3(ghost.global_position.x, 0.0, ghost.global_position.z)
		_rustle.rpc(at)
		game.log_event("%s's ghost rustled the corn at %s" % [ghost.label(), Game._where(at)])


## The sender's player if it is a ghost, else null.
func _ghost(peer: int) -> Player:
	var player := game.get_node_or_null("Players/%d" % peer) as Player
	return player if player and player.dead and not game.ended else null


## Whether ghost may do what again now; if so, starts its cooldown.
func _off_cooldown(what: String, ghost: Player, cooldown: float) -> bool:
	var key := "%s:%d" % [what, ghost.get_multiplayer_authority()]
	var now := Time.get_ticks_msec()
	if _ready_at.get(key, 0) > now:
		_tell.rpc_id(ghost.get_multiplayer_authority(), "Not yet.")
		return false
	_ready_at[key] = now + roundi(cooldown * 1000.0)
	return true


@rpc("authority", "call_local", "reliable")
func _flicker(kind: String, id: int) -> void:
	if kind == "barn":
		game.farm.haunt(id, FLICKER_TIME)
	else:
		var player := game.get_node_or_null("Players/%d" % id) as Player
		if player:
			player.flicker_lantern(FLICKER_TIME)


@rpc("authority", "call_local", "reliable")
func _tell(text: String) -> void:
	game.flash(text, 2.0)


@rpc("authority", "call_local", "reliable")
func _rustle(at: Vector3) -> void:
	Sfx.play_at(game, "rustle", at)
