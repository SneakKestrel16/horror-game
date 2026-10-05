class_name Director
extends Node
## Phase 3's pacing (design doc, The Director and Jumpscares): a tension meter
## that fills through quiet stretches and drops after a scare, a chase, a kill
## or a call. When it is full by day, it springs a scare on someone it can
## reach, picked at random so players can't learn the pattern:
## - a lunge at a player kneeling by the corn (disarming a trap): the
##   screen cuts to black before the creature is in full view, they drop what
##   they carry and are wounded until dawn;
## - a stare at a player in a bear trap: it stands in the rows, watching;
## - a friend's voice whispering right behind a player alone.
## From half full a crow may burst out of the corn instead, a fake-out.
## At night the fuller it is, the more the creature prowls near players, and it
## follows a wounded player's trail. By day it also blurs the day-death rule:
## how long a trapped player must be alone before the creature comes varies.
##
## The host runs it; the scares' sights and sounds reach peers by RPC from this
## node, which has the same path ("Director") everywhere.

const QUIET_TO_FULL := 150.0  ## Seconds of quiet that fill the meter. Guess.
const CHECK_EVERY := 2.0
const FAKE_OUT_AT := 0.5  ## A crow may burst out from this tension.
const FAKE_OUT_CHANCE := 0.06  ## Per check, when one is possible.
## Tension after each event, at most (a call takes some off instead).
const CALM := {"scare": 0.0, "fake_out": 0.25, "chase": 0.2, "kill": 0.0}
const CALL_CALM := 0.1
const LUNGE_REACH := 4.0  ## How near the corn a kneeling player must be.
const WHISPER_ALONE := 10.0  ## No teammate this close for a whisper.
const CROW_REACH := 6.0
## How long a trapped player must be alone before a day kill (design doc, Day
## Deaths), drawn afresh each time someone is caught: Review 2 default for
## issue 7, which asks the Director to blur the exact rule. Guess.
const ALONE_TIME := Vector2(10.0, 25.0)
const TRAIL_EVERY := 2.0  ## Seconds between a wounded player's trail points.
const TRAIL_BEHIND := 8.0  ## The creature follows the trail this far back.

var game: Game
var tension := 0.0  ## 0 calm to 1: a scare is due.

var _check_left := 0.0
var _trail_left := 0.0
var _trails := {}  ## Host: peer -> Array of [clock, Vector3], tonight's wounded steps.
var _alone_needed := {}  ## Host: trapped peer -> seconds alone before a day kill.
var _rng := RandomNumberGenerator.new()
var _blackout: ColorRect


func _init(owner_game: Game) -> void:
	game = owner_game
	name = "Director"


func _ready() -> void:
	_rng.randomize()
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_blackout = ColorRect.new()
	_blackout.color = Color.BLACK
	_blackout.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blackout.modulate.a = 0.0
	layer.add_child(_blackout)


func _process(delta: float) -> void:
	_blackout.modulate.a = maxf(0.0, _blackout.modulate.a - delta * 1.5)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or game.in_lobby or game.ended:
		return
	var phase := game.phase()
	tension = minf(1.0, tension + delta * game.clock_rate / QUIET_TO_FULL)
	_trail_left -= delta
	if phase == "night" and _trail_left <= 0.0:
		_trail_left = TRAIL_EVERY
		for player in game.living_players():
			if player.wounded:
				var steps: Array = _trails.get_or_add(player.get_multiplayer_authority(), [])
				steps.append([game.clock, player.global_position])
	for player in game.living_players():
		if not player.pinned:
			_alone_needed.erase(player.get_multiplayer_authority())
	_check_left -= delta
	if phase != "day" or _check_left > 0.0:
		return
	_check_left = CHECK_EVERY
	if tension >= 1.0:
		_try_scare()
	elif tension >= FAKE_OUT_AT and _rng.randf() < FAKE_OUT_CHANCE:
		var near := _players_where(
			func(player: Player) -> bool: return _corn_within(player, CROW_REACH)
		)
		if not near.is_empty():
			crow(near[_rng.randi() % near.size()])


## Host: something happened that spends the tension.
func calm(event: String) -> void:
	tension = minf(tension, CALM[event])


## Host: the creature called out; it takes the edge off a little.
func called() -> void:
	tension = maxf(0.0, tension - CALL_CALM)


## Chance a night lurk goes to prowl near a player: more as tension builds.
func prowl_chance() -> float:
	return 0.25 + 0.6 * tension


## Lure gaps are this times their usual length: shorter as tension builds.
func lure_scale() -> float:
	return lerpf(1.3, 0.7, tension)


## Host: seconds the trapped player must be alone before a day kill.
func alone_needed(player: Player) -> float:
	var peer := player.get_multiplayer_authority()
	if not _alone_needed.has(peer):
		_alone_needed[peer] = _rng.randf_range(ALONE_TIME.x, ALONE_TIME.y)
	return _alone_needed[peer]


## Host: a point on a wounded player's trail, TRAIL_BEHIND seconds old, for the
## creature to follow at night, or Vector3.INF if nobody left one.
func trail_point() -> Vector3:
	var peers := _trails.keys().filter(
		func(peer: int) -> bool:
			var player := game.get_node_or_null("Players/%d" % peer) as Player
			return player != null and not player.dead
	)
	if peers.is_empty():
		return Vector3.INF
	var steps: Array = _trails[peers[_rng.randi() % peers.size()]]
	for i in range(steps.size() - 1, -1, -1):
		if steps[i][0] <= game.clock - TRAIL_BEHIND:
			return steps[i][1]
	return steps[0][1]


## Host, each dawn: wounds heal and trails go cold.
func dawn() -> void:
	_trails.clear()
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as Player
		if player.wounded:
			player.healed.rpc_id(player.get_multiplayer_authority())
			player.wounded = false


## Host: springs a scare on someone it can reach, if anyone.
func _try_scare() -> void:
	var options: Array[Callable] = []
	for player in _players_where(_can_lunge):
		options.append(lunge.bind(player))
	for player in _players_where(func(player: Player) -> bool: return player.pinned):
		options.append(stare.bind(player))
	for player in _players_where(_alone):
		if _whisper_clip(player).size() > 0:
			options.append(whisper.bind(player))
	if not options.is_empty():
		options[_rng.randi() % options.size()].call()


## Host (and dev panel): the stalks part and the creature lunges at player.
func lunge(player: Player) -> void:
	var peer := player.get_multiplayer_authority()
	game.creature.lunge_at(player)
	game.chores.drop_held(peer, player.global_position)
	player.knocked_down.rpc_id(peer)
	player.wounded = true  # Now, for the host; the owner's copy follows.
	_scare_effects.rpc_id(peer)
	game.log_event("the creature lunged at %s: knocked down, wounded until dawn" % player.label())
	calm("scare")


## Host (and dev panel): it stands in the rows, watching player, then is gone.
func stare(player: Player) -> void:
	game.creature.stare_at(player)
	game.log_event("the creature stares at %s from the corn" % player.label())
	calm("scare")


## Host (and dev panel): a friend's voice right behind player. Returns whether
## anyone had a voice to whisper with.
func whisper(player: Player) -> bool:
	var pick := _whisper_clip(player)
	if pick.is_empty():
		return false
	var behind := player.global_position + player.global_basis.z * 1.2 + Vector3.UP * 1.6
	_whisper.rpc_id(player.get_multiplayer_authority(), pick["data"], behind)
	var who: String = game.voices.names.get(pick["source"], "someone")
	var line := game.voices.line_text(pick["key"])
	game.log_event("a whisper behind %s: %s's '%s'" % [player.label(), who, line])
	calm("scare")
	return true


## Host (and dev panel): something bursts out of the corn near player. A crow.
func crow(player: Player) -> void:
	var at := Farm.corn_edge_near(player.global_position, 1.0)
	_crow.rpc(at)
	game.log_event("a crow burst out of the corn near %s" % player.label())
	calm("fake_out")


func _players_where(test: Callable) -> Array[Player]:
	var found: Array[Player] = []
	for player in game.living_players():
		if test.call(player):
			found.append(player)
	return found


func _can_lunge(player: Player) -> bool:
	return player.kneeling and not player.pinned and _corn_within(player, LUNGE_REACH)


func _corn_within(player: Player, reach: float) -> bool:
	var edge := Farm.corn_edge_near(player.global_position, 1.0)
	return edge.distance_to(player.global_position) <= reach


func _alone(player: Player) -> bool:
	return game.living_players().all(
		func(other: Player) -> bool:
			return (
				other == player
				or not Farm.near(other.global_position, player.global_position, WHISPER_ALONE)
			)
	)


## A recording of someone else for a whisper behind player, or {}.
func _whisper_clip(player: Player) -> Dictionary:
	# A few tries: the pick is random and now and then rolls the player's own
	# voice, which never whispers (a smoke run failed on that, 2026-10-04).
	for attempt in 6:
		var pick := game.voices.pick(player.get_multiplayer_authority())
		if pick.is_empty():
			return {}
		if pick["source"] != player.get_multiplayer_authority():
			return pick
	return {}


## The victim: the screen cuts to black, so the lunge is never seen in full
## (design doc, The Creature: glimpse rules).
@rpc("authority", "call_local", "reliable")
func _scare_effects() -> void:
	_blackout.modulate.a = 1.0
	Sfx.play_at(game, "screech", game.local_player().global_position, 6.0)


@rpc("authority", "call_local", "reliable")
func _whisper(data: PackedByteArray, at: Vector3) -> void:
	var voice := AudioStreamPlayer3D.new()
	voice.stream = Sfx.from_samples(VoiceCodec.decode(data), VoiceCodec.RATE)
	voice.unit_size = 2.0
	voice.volume_db = -6.0
	game.add_child(voice)
	voice.global_position = at
	voice.finished.connect(voice.queue_free)
	voice.play()


## Every peer: a crow flaps up out of the corn at a point and away.
@rpc("authority", "call_local", "reliable")
func _crow(at: Vector3) -> void:
	Sfx.play_at(game, "rustle", at, 4.0)
	Sfx.play_at(game, "caw", at + Vector3.UP * 2.0, 2.0)
	var bird := Looks.item(game, "crow")
	bird.global_position = at + Vector3.UP * 1.2
	var away := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 12.0
	var flight := bird.create_tween()
	flight.tween_property(bird, "global_position", at + away + Vector3.UP * 9.0, 1.8)
	flight.tween_callback(bird.queue_free)
