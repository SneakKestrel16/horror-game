extends Node3D
## Test scene for the voice chat system.
## Run two copies (Debug > Customize Run Instances), host on one and join on the other.
## Move with WASD, hold V to talk. The red box is the creature.

const PORT := 24565
const MAX_PLAYERS := 4

var _players := {}  # peer_id -> Node3D
var _status: Label
var _ip: LineEdit
var _consent: CheckBox
var _mode: OptionButton
var _dead_button: Button
var _mimic_button: Button
var _camera: Camera3D
var _creature: Node3D
var _mimic: VoiceMimic


func _ready() -> void:
	_build_world()
	_build_ui()
	multiplayer.peer_connected.connect(_add_player)
	multiplayer.peer_disconnected.connect(_remove_player)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _status.text = "Could not connect.")
	multiplayer.server_disconnected.connect(_on_server_lost)
	VoiceChat.local_speaking_changed.connect(func(_on): _refresh_labels())
	VoiceChat.peer_speaking_changed.connect(func(_id, _on): _refresh_labels())
	VoiceChat.peer_dead_changed.connect(func(_id, _dead): _refresh_labels())
	_mimic.mimicked.connect(_on_mimicked)


func _process(delta: float) -> void:
	var me: Node3D = _players.get(multiplayer.get_unique_id())
	if me == null or _ip.has_focus():
		return
	var move := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): move.z -= 1
	if Input.is_physical_key_pressed(KEY_S): move.z += 1
	if Input.is_physical_key_pressed(KEY_A): move.x -= 1
	if Input.is_physical_key_pressed(KEY_D): move.x += 1
	if move != Vector3.ZERO:
		me.position += move.normalized() * 6.0 * delta
		_sync_position.rpc(me.position)
	_camera.position = me.position + Vector3(0, 18, 12)
	_camera.look_at(me.position)


# --- Connecting ------------------------------------------------------------------

func _host() -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_PLAYERS) != OK:
		_status.text = "Could not host on port %d." % PORT
		return
	multiplayer.multiplayer_peer = peer
	_add_player(1)
	_on_joined()
	_mimic_button.disabled = false
	_status.text = "Hosting on port %d. Hold V to talk." % PORT


func _join() -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(_ip.text.strip_edges(), PORT) != OK:
		_status.text = "Could not start connecting."
		return
	multiplayer.multiplayer_peer = peer
	_status.text = "Connecting..."


func _on_connected() -> void:
	_add_player(multiplayer.get_unique_id())
	_on_joined()
	_status.text = "Connected as player %d. Hold V to talk." % multiplayer.get_unique_id()


func _on_joined() -> void:
	VoiceChat.set_recording_consent(_consent.button_pressed)
	_dead_button.disabled = false


func _on_server_lost() -> void:
	for id in _players.keys():
		_remove_player(id)
	multiplayer.multiplayer_peer = null
	_status.text = "Host left."


# --- Players ---------------------------------------------------------------------

func _add_player(id: int) -> void:
	if _players.has(id):
		return
	var player := Node3D.new()
	player.name = "Player%d" % id
	player.position = Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
	var body := MeshInstance3D.new()
	body.mesh = CapsuleMesh.new()
	body.position.y = 1.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.from_hsv(fmod(id * 0.137, 1.0), 0.6, 0.9)
	body.material_override = material
	player.add_child(body)
	var label := Label3D.new()
	label.name = "Label"
	label.position.y = 2.6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	player.add_child(label)
	if id == multiplayer.get_unique_id():
		var ears := AudioListener3D.new()
		ears.position.y = 1.6
		player.add_child(ears)
		ears.make_current.call_deferred()
	else:
		var speaker := VoiceSpeaker.new()
		speaker.peer_id = id
		speaker.position.y = 1.6
		player.add_child(speaker)
	add_child(player)
	_players[id] = player
	_refresh_labels()
	if id != multiplayer.get_unique_id():
		var me: Node3D = _players.get(multiplayer.get_unique_id())
		if me:
			_sync_position.rpc_id(id, me.position)


func _remove_player(id: int) -> void:
	if _players.has(id):
		_players[id].queue_free()
		_players.erase(id)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _sync_position(pos: Vector3) -> void:
	var player: Node3D = _players.get(multiplayer.get_remote_sender_id())
	if player:
		player.position = pos


func _refresh_labels() -> void:
	var my_id := multiplayer.get_unique_id()
	for id in _players.keys():
		var text := "You" if id == my_id else "Player %d" % id
		if VoiceChat.is_dead(id):
			text += " (dead)"
		var talking := VoiceChat.is_local_speaking() if id == my_id else VoiceChat.is_peer_speaking(id)
		if talking:
			text += "\n[talking]"
		_players[id].get_node("Label").text = text
	if _dead_button:
		_dead_button.text = "Revive me" if VoiceChat.is_dead(my_id) else "Kill me (test static)"


# --- Death and the creature --------------------------------------------------------

func _toggle_dead() -> void:
	var my_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		VoiceChat.set_peer_dead(my_id, not VoiceChat.is_dead(my_id))
	else:
		_request_dead.rpc_id(1, not VoiceChat.is_dead(my_id))


@rpc("any_peer", "call_remote", "reliable")
func _request_dead(dead: bool) -> void:
	if multiplayer.is_server():
		VoiceChat.set_peer_dead(multiplayer.get_remote_sender_id(), dead)


func _creature_speak() -> void:
	var spot := Vector3(randf_range(-12, 12), 0, randf_range(-12, 12))
	_move_creature.rpc(spot)
	_mimic.mimic()


@rpc("authority", "call_local", "reliable")
func _move_creature(spot: Vector3) -> void:
	_creature.position = spot


func _on_mimicked(listener_id: int, source_id: int) -> void:
	var voice := "a generic line" if source_id == -1 else "player %d's voice" % source_id
	print("Creature used %s for player %d" % [voice, listener_id])
	if listener_id == multiplayer.get_unique_id():
		_status.text = "Creature spoke with %s. Talk more (with consent on) to give it clips." % voice


# --- Scene building --------------------------------------------------------------

func _build_world() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.35, 0.28, 0.18)
	ground.material_override = ground_mat
	add_child(ground)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)

	_camera = Camera3D.new()
	_camera.position = Vector3(0, 18, 12)
	add_child(_camera)
	_camera.look_at(Vector3.ZERO)

	_creature = Node3D.new()
	_creature.name = "Creature"
	_creature.position = Vector3(8, 0, -8)
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.scale = Vector3(1, 2.4, 1)
	box.position.y = 1.2
	var creature_mat := StandardMaterial3D.new()
	creature_mat.albedo_color = Color(0.7, 0.05, 0.05)
	box.material_override = creature_mat
	_creature.add_child(box)
	_mimic = VoiceMimic.new()
	_mimic.name = "Mimic"
	_mimic.position.y = 1.8
	_creature.add_child(_mimic)
	add_child(_creature)


func _build_ui() -> void:
	var panel := VBoxContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(320, 0)
	add_child(_wrap_in_layer(panel))

	_status = Label.new()
	_status.text = "Host or join a game."
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(_status)

	_ip = LineEdit.new()
	_ip.text = "127.0.0.1"
	_ip.placeholder_text = "Host IP address"
	panel.add_child(_ip)

	var buttons := HBoxContainer.new()
	panel.add_child(buttons)
	var host_button := Button.new()
	host_button.text = "Host"
	host_button.pressed.connect(_host)
	buttons.add_child(host_button)
	var join_button := Button.new()
	join_button.text = "Join"
	join_button.pressed.connect(_join)
	buttons.add_child(join_button)

	_consent = CheckBox.new()
	_consent.text = "Let the creature copy my voice"
	_consent.toggled.connect(func(on): VoiceChat.set_recording_consent(on))
	panel.add_child(_consent)

	_mode = OptionButton.new()
	_mode.add_item("Push to talk (hold V)", VoiceChat.Mode.PUSH_TO_TALK)
	_mode.add_item("Voice activation", VoiceChat.Mode.VOICE_ACTIVATION)
	_mode.item_selected.connect(func(index): VoiceChat.mode = _mode.get_item_id(index))
	panel.add_child(_mode)

	_dead_button = Button.new()
	_dead_button.text = "Kill me (test static)"
	_dead_button.disabled = true
	_dead_button.pressed.connect(_toggle_dead)
	panel.add_child(_dead_button)

	_mimic_button = Button.new()
	_mimic_button.text = "Creature: speak (host only)"
	_mimic_button.disabled = true
	_mimic_button.pressed.connect(_creature_speak)
	panel.add_child(_mimic_button)


func _wrap_in_layer(control: Control) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.add_child(control)
	return layer
