class_name Creature
extends CharacterBody3D
## Something in the corn. Phase 1 fakes its mind with a few states and timers
## (design doc, Build Plan): it lurks in the corn, goes to look at noises, and
## calls out in a generic voice from cover. Each call is placed around where its
## target is now, out of their view and past an armed trap when it can, and
## never near its last few calls; if they walk toward it, it backs off and calls
## again from deeper in. It calls in a friend's recorded voice when it has one
## (VoiceBank), each listener hearing their own pick, with a random small tell.
## By day that is all it does, and it never leaves the corn, unless a player is
## stuck in a bear trap with nobody near (Game.day_prey). At night it takes bear
## traps from the shed's pegboard and sets them, digs pits, walks the farm,
## waits by the fuel run while everyone hides in the lit barn, chases any player
## it hears and then sees, and kills on reaching them. It will not enter the
## barn while the lights are on.
##
## The host runs it; clients see the replicated transform and state and only
## animate it and play its sounds.

## Host only: a lure was played here; heard is listener peer -> what they heard.
## tells: listener peer -> its tell ("echo", "pitch +6%" or "no tell"), for the log.
signal spoke(at: Vector3, heard: Dictionary, tells: Dictionary)

## ERRAND: trap work. STARE: watching a player from the rows (Director).
enum State { LURK, INVESTIGATE, LURE, CHASE, RETREAT, ERRAND, STARE }

const LURK_SPEED := 1.6
const INVESTIGATE_SPEED := {"day": 2.4, "night": 3.4}
const CHASE_SPEED := 5.4  ## Below sprint (6.3), above walking (3.6): run while stamina lasts.
const RETREAT_SPEED := 3.6
const GRAVITY := 14.0
const CATCH_RANGE := 1.3
const SIGHT := 10.0  ## Metres it sees a player in the open.
const LANTERN_SIGHT := 24.0
const CROUCH_SIGHT := 5.0
const CORN_COVER := 3.0  ## Metres of corn in the way that hide a player beyond arm's reach.
const LOSE_TIME := 4.0  ## Seconds out of sight before a chase is given up.
const RETREAT_TIME := 25.0
const SWITCH_MARGIN := 2.0  ## Metres nearer another player must be to turn on them.
const PROWL := 8.0  ## How near a player a night prowl takes it (m).
const TRAIL_FOLLOW := 0.7  ## Chance a night lurk follows a wounded player's trail. Guess.
const STARE_TIME := 3.0
const STARE_DISTANCE := 12.0  ## How far ahead of the player it stands to stare.
const STARE_DEPTH := 4.0  ## Metres into the corn, along the line of sight.
const LURE_SPEED := {"day": 4.0, "night": 3.4}  ## Moving to a calling spot, unseen in the corn.
const LURE_WAIT := 6.0  ## Seconds it stands still after calling, to see if anyone comes.
const LURE_GIVE_UP := 30.0  ## Calls from wherever it is if the lure spot takes longer.
## Seconds between lures (min, max), by phase. Short games divide by Game.short_factor().
const LURE_EVERY := {"day": Vector2(50.0, 80.0), "night": Vector2(30.0, 50.0)}
const LURE_RANGE := Vector2(9.0, 24.0)  ## How far from the target it calls (min, max metres).
const LURE_TRIES := 24  ## Candidate spots weighed for each call.
const LURE_RECENT := 4  ## It keeps away from this many of its last calling spots...
const LURE_SPREAD := 12.0  ## ...by this many metres.
const RETARGET := 8.0  ## Re-aims if the target moved this far while it crept into place.
const LEAD_ON := 2  ## Calls in a row leading someone deeper who keeps coming.
const LEAD_CLOSER := 3.0  ## Metres closer that count as coming.
## Chance a night lurk goes to the fuel run while every living player is in the lit barn.
const AMBUSH := 0.6
const DIG_TIME := 3.0  ## Seconds to dig a pit.
## Seconds an errand may take before it does the job where it stands (a spot
## against a wall can be impossible to step onto exactly).
const ERRAND_GIVE_UP := 40.0
const PITCH_TELL := 0.06  ## How far off a pitched voice is.
const VOICES := [
	"over_here", "come_here", "found_something", "help_me", "where_are_you", "this_way"
]
const SPEAKERS := ["david", "zira"]
const HEIGHT := 2.6

var game: Game  ## Set by the host: phase, players, traps, catches.
var farm: Farm
var state := State.LURK  ## Replicated, so clients can animate and play sounds.

var _route: Array[Vector3] = []
var _lure_after := false  ## Call out at the end of the route.
var _lure_target: Player
var _lure_aim := Vector3.ZERO  ## Where the target stood when the spot was picked.
var _retargets := 0
var _lead_ons := 0
var _spoke_distance := INF  ## From the target, when it last called.
var _recent: Array[Vector3] = []  ## Its last calling spots.
var _target: Player
var _unseen_for := 0.0
var _state_time := 0.0
var _lure_left := 20.0
var _replan_left := 0.0
var _switch_left := 0.0  ## Until it next looks for a nearer player mid-chase.
var _direct := false  ## Chasing straight at the target, nothing in the way.
var _stare_target: Player
var _best_distance := INF
var _stuck_for := 0.0
var _rng := RandomNumberGenerator.new()
var _errand := ""  ## "take" (from the pegboard) or "set", while in ERRAND.
var _dig_left := 0.0
var _voices: Array[AudioStream] = []
var _voice: AudioStreamPlayer3D
var _rustle: AudioStreamPlayer3D

# Animation runs on every peer from how far the replicated body moved.
var _last_position := Vector3.ZERO
var _phase := 0.0
var _time := 0.0
var _rustle_left := 0.0
var _arms: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _torso: Node3D
var _head: Node3D
var _last_state := State.LURK


func _ready() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 2.4
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = 1.2
	add_child(collision)
	collision_layer = 2
	collision_mask = 1
	_build_model()
	for speaker: String in SPEAKERS:
		for line: String in VOICES:
			_voices.append(load("res://assets/voices/%s_%s.wav" % [speaker, line]) as AudioStream)
	_voice = AudioStreamPlayer3D.new()
	_voice.bus = &"Lure"
	_voice.unit_size = 8.0
	_voice.max_distance = 70.0
	_voice.position.y = 1.8
	add_child(_voice)
	_rustle = AudioStreamPlayer3D.new()
	_rustle.stream = Sfx.get_sound("rustle")
	_rustle.unit_size = 5.0
	_rustle.max_distance = 35.0
	_rustle.position.y = 1.0
	add_child(_rustle)
	_last_position = position
	_rng.randomize()


func _process(delta: float) -> void:
	_animate(delta)
	if state == State.CHASE and _last_state != State.CHASE:
		Sfx.play_at(get_parent(), "screech", global_position + Vector3.UP * 2.0, 4.0)
	_last_state = state


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or game == null:
		return
	var phase := game.phase()
	_state_time += delta
	_lure_left -= delta
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	if phase == "dawn" or phase == "lobby":
		velocity = Vector3.ZERO
		return
	var night := phase == "night"
	if farm.barn_lit() and Farm.in_barn(global_position) and state != State.RETREAT:
		_retreat()
	if night and state != State.CHASE and state != State.RETREAT:
		var seen := _visible_player()
		if seen:
			_chase(seen)
	var prey := game.day_prey()
	if not night and prey and state != State.CHASE and state != State.RETREAT:
		game.log_event("creature comes for %s, trapped and alone" % prey.label())
		_chase(prey)
	if not night and state == State.CHASE and _target != prey:
		_lurk()
	if not night and state == State.ERRAND:
		_lurk()  # Day came before it finished; the trap field sets the rest.

	var speed := LURK_SPEED
	match state:
		State.LURK:
			if night and _start_errand():
				pass
			elif _lure_left <= 0.0:
				_plan_lure(night)
			elif _route.is_empty():
				_lurk()
		State.ERRAND:
			speed = LURE_SPEED["night"]
			if _route.is_empty() or _state_time > ERRAND_GIVE_UP:
				speed = 0.0
				_do_errand(delta)
		State.INVESTIGATE:
			var key := "night" if night else "day"
			speed = LURE_SPEED[key] if _lure_after else INVESTIGATE_SPEED[key]
			if _route.is_empty() or (_lure_after and _state_time > LURE_GIVE_UP):
				if not _lure_after:
					_lurk()
				elif _lure_moved() and _retargets < 2:
					_retargets += 1
					_aim_lure(_lure_target, night)
				else:
					_speak()
		State.LURE:
			speed = 0.0
			if _state_time > LURE_WAIT:
				if _coming() and _lead_ons < LEAD_ON:
					_lead_ons += 1
					_lead_on(night)
				else:
					_lurk()
		State.CHASE:
			speed = CHASE_SPEED
			_update_chase(delta)
		State.RETREAT:
			speed = RETREAT_SPEED
			if _state_time > RETREAT_TIME:
				_lurk()
			elif _route.is_empty():
				_route = _path(Farm.random_corn_point(_rng))
		State.STARE:
			speed = 0.0
			if _stare_target and is_instance_valid(_stare_target):
				var to := _stare_target.global_position - global_position
				to.y = 0.0
				if to.length() > 0.1:
					look_at(global_position + to)
			if _state_time > STARE_TIME:
				_retreat()  # Gone back into the rows.
	if state == State.CHASE and _target and _direct:
		_walk_toward(_target.global_position, speed, delta)
	elif not _route.is_empty():
		if _walk_toward(_route[0], speed, delta):
			_route.pop_front()
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()


## Host only: a noise reached it. By day it creeps to the corn's edge nearest
## the noise, or if a call is due, calls whoever made it; at night it goes to
## the noise itself.
func hear(at: Vector3, radius: float) -> void:
	if state == State.CHASE or state == State.RETREAT or state == State.LURE:
		return
	if global_position.distance_to(at) > radius:
		return
	var night := game.phase() == "night"
	if night:
		_go(at, false)
	elif state != State.INVESTIGATE:
		if _lure_left <= 0.0:
			_plan_lure(false, _nearest_player(at))
		else:
			_go(Farm.corn_edge_near(at, 3.0), false)


## Host only: heads off on the next trap job, if there is one: to the shed
## door for more traps, or to the next spot to set.
func _start_errand() -> bool:
	var traps := game.traps
	if traps.orders.is_empty():
		return false
	_set_state(State.ERRAND)
	_dig_left = DIG_TIME
	if traps.needs_board():
		_errand = "take"
		_route = _path(Farm.SHED_DOOR_OUT)
	else:
		var order := traps.next_order(global_position)
		if order.is_empty():
			traps.fulfil(global_position)  # Drops a bear trap it has none for.
			return false
		_errand = "set"
		_route = _path(order["position"])
	return true


## Host only: it has arrived: takes traps, or sets (or digs) the next one.
func _do_errand(delta: float) -> void:
	var order := game.traps.next_order(global_position)
	if _errand == "set" and not order.is_empty() and order["kind"] == "pit":
		_dig_left -= delta
		if _dig_left > 0.0:
			return
	if _errand == "take":
		game.traps.take_from_board()
	else:
		game.traps.fulfil(global_position)
	_lurk()


## Host only (dev panel): calls out from where it stands, now.
func speak_now() -> void:
	game.log_event("dev: creature calls now")
	_lure_target = null
	_speak()


## Host only (dev panel): starts a lure at target now, as if one were due.
func lure_now(target: Player) -> void:
	game.log_event("dev: creature lures %s" % target.label())
	_plan_lure(game.phase() == "night", target)


## Host only (dev panel): runs at a living target. By day it gives up at once.
func chase(target: Player) -> void:
	if not target.dead:
		game.log_event("dev: creature sent after %s" % target.label())
		_chase(target)


## Host only (dev panel): sends it back into the corn for a while.
func drive_off() -> void:
	game.log_event("dev: creature driven off")
	_retreat()


## Host only (Director): the stalks part beside player and it lunges, then
## pulls back into the rows. The victim's screen has already cut to black.
func lunge_at(player: Player) -> void:
	var spot := Farm.corn_edge_near(player.global_position, 0.5)
	global_position = Vector3(spot.x, 0.0, spot.z)
	var to := player.global_position - global_position
	to.y = 0.0
	if to.length() > 0.1:
		look_at(global_position + to)
	Sfx.play_at(get_parent(), "rustle", global_position, 6.0)
	_retreat()


## Host only (Director): stands in the rows ahead of player, watching, for a
## few seconds, then is gone (design doc, Scare Moments: the trap).
func stare_at(player: Player) -> void:
	var look := player.look_direction() * Vector3(1, 0, 1)
	look = look.normalized() if look.length() > 0.1 else Vector3.FORWARD
	# Where the corn starts along their line of sight, then deeper in, so the
	# stalks hide most of it (design doc, The Creature: by day only parts).
	var spot := Farm.corn_edge_near(player.global_position + look * STARE_DISTANCE, STARE_DEPTH)
	for step in range(1, 40):
		var at := player.global_position + look * step
		if Farm.in_corn(at):
			spot = at + look * STARE_DEPTH
			break
	global_position = Vector3(spot.x, 0.0, spot.z)
	_set_state(State.STARE)
	_stare_target = player
	_route.clear()


## Host only (dev panel): puts it at a point and has it lurk from there.
func place(at: Vector3) -> void:
	game.log_event("dev: creature moved to %s" % Game._where(at))
	global_position = Vector3(at.x, 0.0, at.z)
	_lurk()


## The current state's name, for the dev panel.
func state_name() -> String:
	return State.keys()[state]


## Host only: it has just killed someone or been driven off.
func _retreat() -> void:
	_set_state(State.RETREAT)
	_target = null
	_route = _path(Farm.random_corn_point(_rng))


func _lurk() -> void:
	_set_state(State.LURK)
	_target = null
	_lure_after = false
	var night := game.phase() == "night"
	var goal := Farm.random_corn_point(_rng)
	var hiding := game.living_players().all(
		func(player: Player) -> bool:
			return farm.barn_lit() and Farm.in_barn(player.global_position)
	)
	var living := game.living_players()
	var in_the_dark := living.filter(
		func(player: Player) -> bool:
			return not farm.barn_lit() and Farm.in_barn(player.global_position)
	)
	var trail := game.director.trail_point() if night else Vector3.INF
	if night and not in_the_dark.is_empty():
		# The lights are out: the barn is where they hide.
		goal = (in_the_dark[_rng.randi() % in_the_dark.size()] as Player).global_position
	elif trail.is_finite() and _rng.randf() < TRAIL_FOLLOW:
		goal = trail  # A wounded player's trail (design doc, Wounds).
	elif night and hiding and _rng.randf() < AMBUSH:
		# Somebody will have to fetch fuel: wait in the dark along the way.
		var along := Farm.FUEL_DRUM.lerp(Farm.GENERATOR, _rng.randf())
		goal = along + Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(2, 8))
	elif night and not living.is_empty() and _rng.randf() < game.director.prowl_chance():
		# Prowls near someone: a quiet player isn't safe, only harder to find.
		var near: Player = living[_rng.randi() % living.size()]
		var off := Vector3.FORWARD.rotated(Vector3.UP, _rng.randf() * TAU) * _rng.randf() * PROWL
		goal = near.global_position + off
	_route = _path(goal)


func _go(at: Vector3, lure: bool) -> void:
	_set_state(State.INVESTIGATE)
	_lure_after = lure
	_route = _path(at)


func _chase(player: Player) -> void:
	_set_state(State.CHASE)
	_target = player
	_unseen_for = 0.0
	_route.clear()
	game.director.calm("chase")
	game.log_event("creature chases %s" % player.label())


func _update_chase(delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or _target.dead:
		_lurk()
		return
	if farm.barn_lit() and Farm.in_barn(_target.global_position):
		game.log_event("%s reached the lit barn" % _target.label())
		_retreat()
		return
	_unseen_for = 0.0 if _can_see(_target) else _unseen_for + delta
	_switch_left -= delta
	if _switch_left <= 0.0:
		_switch_left = 0.5
		_turn_on_nearest()
	# Straight at them only with nothing solid between; else round it (a low
	# generator hides nobody but still blocks the way).
	_direct = _unseen_for == 0.0 and farm.clear_line(global_position, _target.global_position)
	_replan_left -= delta
	if not _direct and (_route.is_empty() or _replan_left <= 0.0):
		_route = _path(_target.global_position)
		_replan_left = 0.5
	if _unseen_for > LOSE_TIME:
		game.log_event("creature lost %s" % _target.label())
		_go(_target.global_position, false)
		return
	if global_position.distance_to(_target.global_position) < CATCH_RANGE:
		game.creature_caught(_target)
		_retreat()


## Mid-chase, goes for a player it can see who is clearly nearer than its
## target, rather than running past them (2026-10-04 playtest).
func _turn_on_nearest() -> void:
	var nearest := _visible_player()
	if nearest == null or nearest == _target:
		return
	if farm.barn_lit() and Farm.in_barn(nearest.global_position):
		return
	var current := global_position.distance_to(_target.global_position)
	if global_position.distance_to(nearest.global_position) < current - SWITCH_MARGIN:
		game.log_event("creature turns on %s" % nearest.label())
		_target = nearest
		_unseen_for = 0.0
		_route.clear()


## Starts a call: at target, or whoever is most alone. Resets the timer.
func _plan_lure(night: bool, target: Player = null) -> void:
	var timing: Vector2 = LURE_EVERY["night" if night else "day"]
	var factor := game.short_factor()
	factor *= game.director.lure_scale()
	_lure_left = maxf(12.0, _rng.randf_range(timing.x, timing.y) * factor)
	var players := game.living_players()
	if players.is_empty():
		return
	if target == null:
		var loneliest := -1.0
		for player in players:
			var nearest := INF
			for other in players:
				if other != player:
					nearest = minf(
						nearest, player.global_position.distance_to(other.global_position)
					)
			if nearest > loneliest:
				loneliest = nearest
				target = player
	_retargets = 0
	_lead_ons = 0
	_aim_lure(target, night)


## Picks a spot round where target stands now and creeps there to call.
func _aim_lure(target: Player, night: bool) -> void:
	_lure_target = target
	_lure_aim = target.global_position
	_go(pick_lure_spot(target, night), true)


## Where to call target from, and remembers it. Weighs LURE_TRIES spots round
## them: away from its recent calls, out of their view, past an armed trap on
## the way to it, not too far to creep to, with some chance mixed in. By day
## only spots in the corn.
func pick_lure_spot(target: Player, night: bool) -> Vector3:
	var from := target.global_position
	var facing := target.look_direction()
	facing.y = 0.0
	var traps := game.traps.armed_positions()
	var best := Farm.corn_edge_near(from, 3.0)
	var best_score := -INF
	for i in LURE_TRIES:
		var reach := _rng.randf_range(LURE_RANGE.x, LURE_RANGE.y)
		var spot := from + Vector3.FORWARD.rotated(Vector3.UP, _rng.randf() * TAU) * reach
		if not night:
			spot = Farm.corn_edge_near(spot, _rng.randf_range(2.0, 5.0))
		var limit := Farm.CORN_OUT - 1.0
		spot = Vector3(clampf(spot.x, -limit, limit), 0, clampf(spot.z, -limit, limit))
		var distance := from.distance_to(spot)
		if distance < LURE_RANGE.x * 0.7 or distance > LURE_RANGE.y * 1.3:
			continue
		if farm.barn_lit() and Farm.in_barn(spot):
			continue
		var score := _rng.randf() * 0.6 - global_position.distance_to(spot) / 50.0
		for old in _recent:
			var near := spot.distance_to(old)
			if near < LURE_SPREAD:
				# Outweighs every bonus: only if nowhere else will do, and then
				# the least close (by day the reachable corn is a narrow strip).
				score -= 10.0 + LURE_SPREAD - near
		var away := facing.angle_to(spot - from)
		score += 0.8 if away > 1.9 else (0.4 if away > 1.2 else 0.0)  # Behind, or to the side.
		for trap in traps:
			var on_way := Geometry3D.get_closest_point_to_segment(trap, from, spot)
			if trap.distance_to(on_way) < 1.5 and (night or Farm.in_corn(trap)):
				score += 0.9
				break
		if score > best_score:
			best_score = score
			best = spot
	_recent.append(best)
	if _recent.size() > LURE_RECENT:
		_recent.pop_front()
	return best


## The lure's target has moved far from where the calling spot was aimed.
func _lure_moved() -> bool:
	return _lure_alive() and _lure_target.global_position.distance_to(_lure_aim) > RETARGET


## The lure's target came toward the call.
func _coming() -> bool:
	if not _lure_alive():
		return false
	var now := global_position.distance_to(_lure_target.global_position)
	return now < _spoke_distance - LEAD_CLOSER


func _lure_alive() -> bool:
	return _lure_target != null and is_instance_valid(_lure_target) and not _lure_target.dead


## They are coming: back off further in, a little to one side, and call again.
func _lead_on(night: bool) -> void:
	var from := _lure_target.global_position
	var away := global_position - from
	away.y = 0.0
	away = away.normalized().rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6))
	var spot := global_position + away * _rng.randf_range(6.0, 10.0)
	if not night:
		spot = Farm.corn_edge_near(spot, 3.0)
	_lure_aim = from
	game.log_event("creature leads %s deeper" % _lure_target.label())
	_go(spot, true)


func _nearest_player(at: Vector3) -> Player:
	var nearest: Player = null
	var best := INF
	for player in game.living_players():
		var distance := at.distance_to(player.global_position)
		if distance < best:
			best = distance
			nearest = player
	return nearest


## Calls out; every listener hears it from here, each their own pick: a
## friend's recorded line when the voice bank has one for them, a generic line
## otherwise. Each gets at most one random tell: a faint echo, or a voice a
## little off pitch; a third get none (design doc, How Players Fight Back).
func _speak() -> void:
	_set_state(State.LURE)
	_lure_after = false
	var generic := _rng.randi() % _voices.size()
	var heard := {}
	var tells := {}
	var listeners := Array(multiplayer.get_peers())
	listeners.append(multiplayer.get_unique_id())
	for listener: int in listeners:
		var tell := _rng.randi() % 3
		var echo := tell == 1
		var pitch := 1.0
		if tell == 2:
			pitch += PITCH_TELL if _rng.randf() < 0.5 else -PITCH_TELL
		tells[listener] = ["no tell", "echo", "pitch %+d%%" % roundi((pitch - 1.0) * 100)][tell]
		var pick := game.voices.pick(listener)
		if pick.is_empty():
			_say_to(listener, &"_say", [generic, echo, pitch])
			heard[listener] = "a generic '%s'" % _generic_name(generic)
		else:
			# A dead player's voice comes through static, as their real one does
			# (design doc, The Dead-Voice Twist): only the flicker tells them apart.
			var hiss := VoiceChat.is_dead(pick["source"]) and not VoiceChat.is_dead(listener)
			_say_to(listener, &"_say_clip", [pick["data"], echo, pitch, hiss])
			var who: String = game.voices.names.get(pick["source"], "someone")
			heard[listener] = "%s's '%s'" % [who, game.voices.line_text(pick["key"])]
			if hiss:
				tells[listener] += ", through static"
	if _lure_alive():
		_spoke_distance = global_position.distance_to(_lure_target.global_position)
	spoke.emit(global_position, heard, tells)


func _generic_name(index: int) -> String:
	return "%s_%s" % [SPEAKERS[floori(index / float(VOICES.size()))], VOICES[index % VOICES.size()]]


func _say_to(listener: int, method: StringName, args: Array) -> void:
	if listener == multiplayer.get_unique_id():
		callv(method, args)
	else:
		callv(&"rpc_id", [listener, method] + args)


@rpc("authority", "call_remote", "reliable")
func _say(index: int, echo: bool, pitch: float) -> void:
	if index >= 0 and index < _voices.size():
		_play(_voices[index], echo, pitch)


@rpc("authority", "call_remote", "reliable")
func _say_clip(data: PackedByteArray, echo: bool, pitch: float, hiss: bool) -> void:
	if data.size() <= VoiceBank.TAKE_MAX * VoiceCodec.RATE * 1.2:
		var samples := VoiceCodec.decode(data)
		if hiss:
			samples = VoiceCodec.add_static(samples, VoiceChat.dead_static)
		_play(Sfx.from_samples(samples, VoiceCodec.RATE), echo, pitch)


func _play(stream: AudioStream, echo: bool, pitch: float) -> void:
	_voice.stream = stream
	_voice.bus = &"Lure" if echo else &"Master"
	_voice.pitch_scale = clampf(pitch, 0.8, 1.2)
	_voice.play()


func _set_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	_best_distance = INF
	_stuck_for = 0.0


## Waypoints to point round the buildings; by day (and dusk) only through
## the corn, which it never leaves in daylight unless it is coming for prey.
## Caught outside the corn at daybreak (after a kill in the barn, say), it first
## walks out to the nearest corn by any way, since the corn-only grid has no
## cells where it stands and would aim it straight through a wall.
func _path(point: Vector3) -> Array[Vector3]:
	if game.phase() == "night" or state == State.CHASE:
		return farm.route(global_position, point)
	if Farm.in_corn(global_position):
		return farm.route(global_position, point, true)
	var edge := Farm.corn_edge_near(global_position, 2.0)
	var out := farm.route(global_position, edge)
	out.append_array(farm.route(edge, point, true))
	return out


## Steps toward point; true once there. Re-plans if it stops getting closer.
func _walk_toward(point: Vector3, speed: float, delta: float) -> bool:
	var to_point := point - global_position
	to_point.y = 0.0
	var distance := to_point.length()
	if distance < 0.5:
		return true
	if distance < _best_distance - 0.3:
		_best_distance = distance
		_stuck_for = 0.0
	else:
		_stuck_for += delta
	if _stuck_for > 2.0 and not _route.is_empty():
		_route = _path(_route[-1])
		_best_distance = INF
		_stuck_for = 0.0
	var direction := to_point / distance
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	look_at(global_position + direction)
	move_and_slide()
	return false


## The nearest living player it can see, or null.
func _visible_player() -> Player:
	var best: Player = null
	var best_distance := INF
	var players := game.living_players()
	for player in players:
		var distance := global_position.distance_to(player.global_position)
		if distance < best_distance and _can_see(player):
			best = player
			best_distance = distance
	return best


## Short sight: further for a lit lantern, less for a crouching player, and
## blocked by walls and by corn (design doc, How It Hunts).
func _can_see(player: Player) -> bool:
	var distance := global_position.distance_to(player.global_position)
	var reach := SIGHT
	if player.lantern:
		reach = LANTERN_SIGHT
	elif player.crouching:
		reach = CROUCH_SIGHT
	if distance > reach:
		return false
	if distance > CATCH_RANGE * 2.0:
		if Farm.corn_between(global_position, player.global_position) > CORN_COVER:
			return false
	var eye := global_position + Vector3.UP * 2.3
	var chest := player.global_position + Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(eye, chest, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).get("collider") == player


## A tall, thin, hunched dark shape. You are not meant to see it clearly.
func _build_model() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.03, 0.03, 0.025)
	skin.roughness = 1.0
	var model := Node3D.new()
	add_child(model)
	for side: float in [-1.0, 1.0]:
		var leg := _limb(model, Vector3(0.18 * side, 1.3, 0), 1.3, 0.07, skin)
		_legs.append(leg)
	_torso = Node3D.new()
	_torso.position.y = 1.3
	_torso.rotation.x = -0.35  # Hunched forward (-z is its front).
	model.add_child(_torso)
	var chest := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.2
	capsule.height = 1.1
	capsule.material = skin
	chest.mesh = capsule
	chest.position.y = 0.55
	_torso.add_child(chest)
	for side: float in [-1.0, 1.0]:
		_arms.append(_limb(_torso, Vector3(0.28 * side, 1.0, 0), 1.55, 0.05, skin))
	_head = Node3D.new()
	_head.position = Vector3(0, 1.2, -0.12)
	_torso.add_child(_head)
	var skull := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.42
	sphere.material = skin
	skull.mesh = sphere
	_head.add_child(skull)
	var glint := StandardMaterial3D.new()
	glint.albedo_color = Color(0.0, 0.0, 0.0)
	glint.emission_enabled = true
	glint.emission = Color(0.75, 0.78, 0.6)
	glint.emission_energy_multiplier = 0.6
	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var dot := SphereMesh.new()
		dot.radius = 0.018
		dot.height = 0.036
		dot.material = glint
		eye.mesh = dot
		eye.position = Vector3(0.06 * side, 0.04, -0.14)
		_head.add_child(eye)


## A limb hanging down from a joint at top; returns the joint to swing.
func _limb(parent: Node3D, top: Vector3, length: float, radius: float, skin: Material) -> Node3D:
	var joint := Node3D.new()
	joint.position = top
	parent.add_child(joint)
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius * 0.6
	cylinder.height = length
	cylinder.material = skin
	mesh.mesh = cylinder
	mesh.position.y = -length / 2.0
	joint.add_child(mesh)
	return joint


func _animate(delta: float) -> void:
	_time += delta
	var moved := global_position - _last_position
	moved.y = 0.0
	_last_position = global_position
	var speed := moved.length() / maxf(delta, 0.001)
	_phase += moved.length() * 2.0
	var walk := clampf(speed / CHASE_SPEED, 0.0, 1.0)
	for i in _legs.size():
		_legs[i].rotation.x = sin(_phase + PI * i) * 0.6 * walk
	for i in _arms.size():
		var sway := sin(_time * 1.2 + i) * 0.06 + sin(_phase + PI * (1 - i)) * 0.4 * walk
		_arms[i].rotation.x = lerpf(sway, 1.3, clampf((speed - 3.5) / 2.0, 0.0, 1.0))
	_head.rotation = Vector3(
		sin(_time * 0.6) * 0.1, sin(_time * 0.37) * 0.35, sin(_time * 0.9) * 0.1
	)
	if state == State.LURE:
		_head.rotation.z = 0.5  # Head cocked while it calls.
	_rustle_left -= delta
	if speed > 0.5 and Farm.in_corn(global_position) and _rustle_left <= 0.0:
		_rustle_left = clampf(1.2 - speed * 0.15, 0.35, 1.0)
		_rustle.play()
