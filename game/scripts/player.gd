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

# Replicated from the owning peer.
var pitch := 0.0
var crouching := false
var sprinting := false
var kneeling := false  ## Holding still over a trap; game.gd sets it.
var lantern := false
var dead := false

var number := 0  ## Farmer 1 hosts; set from the spawn data on every peer.
var player_name := ""  ## From the main menu; also set from the spawn data.
var stamina := STAMINA
var pinned := false  ## Held by a bear trap.
var slowed_left := 0.0
var stumble_left := 0.0
var hand: Node3D  ## Where a carried item sits.

var _rest_left := 0.0
var _stride := 0.0
var _last_position := Vector3.ZERO
var _head: Node3D
var _camera: Camera3D
var _body: Node3D
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

	_body = Node3D.new()
	add_child(_body)
	# Golden-ratio hues give each peer distinct overalls.
	var overalls := Color.from_hsv(fmod(get_multiplayer_authority() * 0.618, 1.0), 0.5, 0.6)
	_part(CapsuleMesh.new(), Vector3(0, 0.75, 0), Vector3(0.7, 0.75, 0.7), overalls)
	_part(SphereMesh.new(), Vector3(0, 1.65, 0), Vector3(0.36, 0.4, 0.36), Color(0.85, 0.68, 0.55))
	_part(CylinderMesh.new(), Vector3(0, 1.88, 0), Vector3(0.75, 0.06, 0.75), Color(0.8, 0.7, 0.4))

	_head = Node3D.new()
	_head.position.y = EYE_HEIGHT
	add_child(_head)
	hand = Node3D.new()
	hand.position = Vector3(0.32, -0.38, -0.55)
	_head.add_child(hand)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.75, 0.45)
	_light.light_energy = 1.4
	_light.omni_range = 10.0
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
	_light.visible = lantern and not dead
	_body.visible = not dead and not is_multiplayer_authority()
	_footsteps()


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
		stamina = maxf(0.0, stamina - delta)
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
	Sfx.play_at(get_parent(), "rustle" if in_corn else "step", global_position, volume)
	if is_multiplayer_authority():
		var radius: float = STEP_NOISE[gait] * (CORN_NOISE if in_corn else 1.0)
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


func _part(mesh: PrimitiveMesh, at: Vector3, size: Vector3, colour: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.scale = size
	_body.add_child(instance)
