class_name Player
extends CharacterBody3D
## A farmer. WASD to move, Shift to sprint (on stamina), Ctrl to crouch (slow
## and quiet), F for the lantern (see further, be seen further). What E does
## is up to game.gd, which knows what is nearby.
##
## Each player is driven by its own peer and replicated to the others. The
## host decides when a trap grabs a player or the creature kills one, and
## tells the owning peer by RPC.

signal stepped(at: Vector3, radius: float)  ## Owner only: a footstep the creature may hear.

const WALK_SPEED := 3.6
const SPRINT_SPEED := 6.3
const CROUCH_SPEED := 1.8
const GHOST_SPEED := 7.0
const GRAVITY := 14.0
const MOUSE_SENSITIVITY := 0.0025
const EYE_HEIGHT := 1.6
const CROUCH_EYE_HEIGHT := 1.0
const STAMINA := 6.0  ## Seconds of sprinting from full.
const STAMINA_REST := 1.0  ## Seconds after sprinting before it refills, at 1 s per s.
const SLOW := 0.6  ## Speed while hurt from a bear trap: 40% slower (design doc, Night Traps).
const SLOW_TIME := 60.0
const STUMBLE_TIME := 0.9
const STRIDE := 0.75  ## Metres per footstep.
## How far the creature hears a footstep (m), and how much further in the corn.
const STEP_NOISE := {"crouch": 2.0, "walk": 7.0, "sprint": 16.0}
const CORN_NOISE := 1.5
## Wounded by a day scare until dawn (design doc, Wounds): sprint runs out
## sooner and footsteps carry further. The night trail is the Director's.
const WOUND_STAMINA := 0.6  ## 40% less sprint.
const WOUND_NOISE := 1.5  ## Footsteps heard 50% further.
const KNOCKDOWN_TIME := 1.6
const LANTERN_LIGHT := 1.4
const LANTERN_RANGE := 10.0
const BRIGHT_LANTERN := Vector2(2.0, 16.0)  ## Energy and range with brighter lanterns (Store).

# Replicated from the owning peer.
var pitch := 0.0
var crouching := false
var sprinting := false
var kneeling := false  ## Holding still over a trap; game.gd sets it.
var lantern := false
var dead := false
var wounded := false  ## A day scare got them; until dawn.

var number := 0  ## Farmer 1 hosts; set from the spawn data on every peer.
var player_name := ""  ## From the main menu; also set from the spawn data.
var stamina := STAMINA
var pinned := false  ## Held by a bear trap.
var slowed_left := 0.0
var stumble_left := 0.0
var hand: Node3D  ## Where a carried item sits.

var _rest_left := 0.0
var _flicker_left := 0.0  ## A ghost is flickering this lantern (every peer).
var _stride := 0.0
var _last_position := Vector3.ZERO
var _head: Node3D
var _camera: Camera3D
var _body: Node3D  ## The farmer model (tools/blender/models.py); others see it.
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _neck: Node3D  ## The model's head joint, which follows pitch.
var _gait := 0.0  ## Walk cycle, in radians.
var _walked_from := Vector3.ZERO
var _light: OmniLight3D


func _ready() -> void:
	add_to_group("players")
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = 0.9
	add_child(collision)

	_body = Dress.model("farmer")
	add_child(_body)
	# Golden-ratio hues give each peer distinct overalls.
	var hue := fmod(get_multiplayer_authority() * 0.618, 1.0)
	var overalls := Dress.material("denim", Color.from_hsv(hue, 0.45, 0.8), false, 0.9)
	for child in _body.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		for i in instance.mesh.get_surface_count():
			if instance.mesh.surface_get_material(i).resource_name.begins_with("denim"):
				instance.set_surface_override_material(i, overalls)
	for i in 2:
		_legs.append(_body.find_child("leg_%d" % i) as Node3D)
		_arms.append(_body.find_child("arm_%d" % i) as Node3D)
	_neck = _body.find_child("head") as Node3D

	_head = Node3D.new()
	_head.position.y = EYE_HEIGHT
	add_child(_head)
	hand = Node3D.new()
	hand.position = Vector3(0.32, -0.38, -0.55)
	_head.add_child(hand)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.75, 0.45)
	_light.light_energy = LANTERN_LIGHT
	_light.omni_range = LANTERN_RANGE
	_light.shadow_enabled = true
	_light.position = Vector3(-0.3, -0.3, -0.3)
	_light.visible = false
	_head.add_child(_light)

	_last_position = position
	if is_multiplayer_authority():
		_body.visible = false
		_camera = Camera3D.new()
		_camera.far = 300.0
		_head.add_child(_camera)
		_camera.make_current()
		if not get_tree().get_first_node_in_group("lobby"):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		# Their voice, from where they stand (proximity chat, addons/voice_chat).
		var speaker := VoiceSpeaker.new()
		speaker.peer_id = get_multiplayer_authority()
		_head.add_child(speaker)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var motion := event as InputEventMouseMotion
	if motion and captured:
		rotate_y(-motion.relative.x * MOUSE_SENSITIVITY)
		pitch = clampf(pitch - motion.relative.y * MOUSE_SENSITIVITY, -1.45, 1.45)
	var button := event as InputEventMouseButton
	if button and button.pressed and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("lantern") and not dead:
		lantern = not lantern


func _process(delta: float) -> void:
	_head.rotation.x = pitch
	var eye := CROUCH_EYE_HEIGHT if crouching or kneeling else EYE_HEIGHT
	if stumble_left > 0.0:
		eye = 0.6
	_head.position.y = move_toward(_head.position.y, eye, delta * 4.0)
	# A ghost's flicker blinks it off and on. Not by light_energy: setting that
	# every frame crashed Godot on quit (see docs/gotchas.md).
	_flicker_left = maxf(0.0, _flicker_left - delta)
	var blink := _flicker_left > 0.0 and fmod(_flicker_left, 0.2) < 0.1
	_light.visible = lantern and not dead and not blink
	var reach := BRIGHT_LANTERN.y if Store.owns("lanterns") else LANTERN_RANGE
	if _light.omni_range != reach:  # Only on a change: see the flicker note above.
		_light.omni_range = reach
		_light.light_energy = BRIGHT_LANTERN.x if reach > LANTERN_RANGE else LANTERN_LIGHT
	_body.visible = not dead and not is_multiplayer_authority()
	_footsteps()
	_walk_cycle(delta)


## Swings the model's legs and arms with how fast it moves, and tips its head
## with the camera's pitch, for the other players to see.
func _walk_cycle(delta: float) -> void:
	var moved := global_position - _walked_from
	moved.y = 0.0
	_walked_from = global_position
	var speed := moved.length() / maxf(delta, 0.001)
	if speed > SPRINT_SPEED * 2.0:  # A teleport.
		speed = 0.0
	_gait += minf(moved.length(), 1.0) * 2.4
	var swing := sin(_gait) * clampf(speed / WALK_SPEED, 0.0, 1.4) * 0.45
	for i in _legs.size():
		_legs[i].rotation.x = swing * (1.0 if i == 0 else -1.0)
		_arms[i].rotation.x = swing * (-0.8 if i == 0 else 0.8)
	_neck.rotation.x = pitch * 0.6


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if dead:
		_fly(delta)
		return
	slowed_left = maxf(0.0, slowed_left - delta)
	stumble_left = maxf(0.0, stumble_left - delta)
	crouching = Input.is_action_pressed("crouch")
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if pinned or stumble_left > 0.0 or kneeling:
		input = Vector2.ZERO
	var wants_sprint := (
		Input.is_action_pressed("sprint") and not crouching and input != Vector2.ZERO
	)
	sprinting = wants_sprint and stamina > 0.0
	if sprinting:
		stamina = maxf(0.0, stamina - delta / (WOUND_STAMINA if wounded else 1.0))
		_rest_left = STAMINA_REST
	else:
		_rest_left -= delta
		if _rest_left <= 0.0:
			stamina = minf(STAMINA, stamina + delta)
	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	if slowed_left > 0.0:
		speed *= SLOW
	var direction := transform.basis * Vector3(input.x, 0.0, input.y)
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()


## A ghost drifts where it looks, through anything, until dawn.
func _fly(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := _camera.global_basis * Vector3(input.x, 0.0, input.y)
	direction.y += Input.get_axis("crouch", "jump")
	global_position += direction.limit_length(1.0) * GHOST_SPEED * delta
	global_position.y = maxf(global_position.y, 0.0)


## Plays footsteps on every peer from how far the body moved; the owner also
## tells the creature (through game.gd) how far each one carried.
func _footsteps() -> void:
	var moved := global_position - _last_position
	moved.y = 0.0
	_last_position = global_position
	if dead or moved.length() > 3.0:  # A teleport is not a step.
		return
	_stride += moved.length()
	if _stride < STRIDE:
		return
	_stride = 0.0
	var gait := "crouch" if crouching else ("sprint" if sprinting else "walk")
	var in_corn := Farm.in_corn(global_position)
	var volume := {"crouch": -14.0, "walk": -6.0, "sprint": 0.0}[gait] as float
	Sfx.play_at(get_parent(), "corn_step" if in_corn else "step", global_position, volume)
	if is_multiplayer_authority():
		var radius: float = STEP_NOISE[gait] * (CORN_NOISE if in_corn else 1.0)
		radius *= WOUND_NOISE if wounded else 1.0
		stepped.emit(global_position, radius)


## The point a dropped item lands on: just in front of the feet.
func drop_point() -> Vector3:
	return global_position - global_basis.z * 0.6


## The player's name ("Farmer N" without one), for messages and logs.
func label() -> String:
	return player_name if player_name != "" else "Farmer %d" % number


## Where the eyes are, in world space.
func eye_position() -> Vector3:
	return _head.global_position


## The direction the camera looks (the body's facing for remote players).
func look_direction() -> Vector3:
	return -_head.global_basis.z


## Sent by the host: a bear trap has this player by the leg.
@rpc("any_peer", "call_local", "reliable")
func trapped(at: Vector3) -> void:
	pinned = true
	position = at
	velocity = Vector3.ZERO


## Sent by the host: pried free, and limping for a minute.
@rpc("any_peer", "call_local", "reliable")
func released() -> void:
	pinned = false
	slowed_left = SLOW_TIME


## Sent by the host: stepped into a covered pit.
@rpc("any_peer", "call_local", "reliable")
func stumbled() -> void:
	stumble_left = STUMBLE_TIME


## Sent by the host: a day scare knocked this player down and wounded them
## until dawn (Director). Wounded is replicated from here.
@rpc("any_peer", "call_local", "reliable")
func knocked_down() -> void:
	stumble_left = KNOCKDOWN_TIME
	kneeling = false
	wounded = true


## Sent by the host at dawn: the wound has healed.
@rpc("any_peer", "call_local", "reliable")
func healed() -> void:
	wounded = false


## Every peer: a ghost flickers this player's lantern for a moment.
func flicker_lantern(seconds: float) -> void:
	_flicker_left = seconds


## Sent by the host: the creature got this player. A ghost until dawn.
@rpc("any_peer", "call_local", "reliable")
func killed() -> void:
	dead = true
	pinned = false
	kneeling = false
	lantern = false
	collision_layer = 0
	collision_mask = 0


## Sent by the host: back from the dead at a point (dawn, or the dev panel).
@rpc("any_peer", "call_local", "reliable")
func revived(at: Vector3) -> void:
	dead = false
	pinned = false
	slowed_left = 0.0
	collision_layer = 1
	collision_mask = 1
	global_position = Vector3(at.x, 0.05, at.z)
