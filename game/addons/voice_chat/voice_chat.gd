extends Node
## Proximity voice chat for Godot 4 multiplayer. Register as an autoload named "VoiceChat".
##
## - Captures the microphone and sends 20 ms packets to every other peer.
## - Each player's voice plays from a VoiceSpeaker node on their character.
## - Dead players are heard through static by living players.
## - On the server, saves short clips of each player's speech for the creature
##   to mimic, but only for players who have agreed to it.

signal local_speaking_changed(is_speaking: bool)
signal peer_speaking_changed(peer_id: int, is_speaking: bool)
signal peer_dead_changed(peer_id: int, is_dead: bool)

enum Mode { PUSH_TO_TALK, VOICE_ACTIVATION }

const PTT_ACTION := &"voice_push_to_talk"
const PACKET_SAMPLES := 480  # 20 ms at 24 kHz
const TALK_FADE := 0.008  # seconds faded in and out as talking starts and stops: no click
const SPEAKING_TIMEOUT := 0.3
const CLIP_GAP := 0.4  # silence that ends a clip
const CLIP_MIN := 0.5  # seconds
const CLIP_MAX := 3.0  # seconds; design doc, Build Notes: live clips
const CLIPS_PER_PEER := 8
const CLIP_SILENT := 0.005  # RMS below this is a muted or switched-off mic: not kept

## Push-to-talk (hold V) or talk automatically when loud enough.
@export var mode: Mode = Mode.PUSH_TO_TALK
## How loud the mic must be to start sending in voice activation mode.
@export_range(0.0, 0.5, 0.005) var activation_threshold := 0.02
## How long to keep sending after the voice drops below the threshold.
@export var activation_hold := 0.35
## Amount of static on dead players' voices (0 to 1).
@export_range(0.0, 1.0, 0.01) var dead_static := 0.12

var mic_muted := false
## Save live speech for the creature (Phase 3). Off in Phase 2, which uses lobby
## lines recorded with start_take()/end_take() instead.
var keep_live_clips := false
## Walkie-talkies: living players beyond a speaker's hearing range hear each
## other over the radio instead (VoiceSpeaker), through the "Radio" bus.
var radio_enabled := false

var _capture: AudioEffectCapture
var _encoder: VoiceCodec
var _outgoing := PackedFloat32Array()
var _transmitting := false
var _hold_left := 0.0
var _my_consent := false
var _time := 0.0
var _take := PackedFloat32Array()
var _taking := false

var _speakers := {}       # peer_id -> VoiceSpeaker
var _consent := {}        # peer_id -> bool
var _dead := {}           # peer_id -> bool
var _last_heard := {}     # peer_id -> time of last packet
var _speaking := {}       # peer_id -> bool
var _clips := {}          # peer_id -> Array of PackedFloat32Array
var _clip_building := {}  # peer_id -> PackedFloat32Array
var _clip_last := {}      # peer_id -> time of last sample added


func _ready() -> void:
	if not InputMap.has_action(PTT_ACTION):
		InputMap.add_action(PTT_ACTION)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_V
		InputMap.action_add_event(PTT_ACTION, key)
	_setup_buses()
	_setup_microphone()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(reset)


func _process(delta: float) -> void:
	_time += delta
	_read_microphone(delta)
	_update_speaking()
	_finish_quiet_clips()


# --- Public API ---------------------------------------------------------------

## Tell everyone whether this player allows the creature to copy their voice.
func set_recording_consent(allowed: bool) -> void:
	_my_consent = allowed
	_consent[multiplayer.get_unique_id()] = allowed
	if _is_online():
		_receive_consent.rpc(allowed)
	if not allowed:
		_clips.erase(multiplayer.get_unique_id())


func has_consent(peer_id: int) -> bool:
	return _consent.get(peer_id, false)


## Server only: mark a player as dead or alive and tell everyone.
func set_peer_dead(peer_id: int, dead: bool) -> void:
	if not multiplayer.is_server():
		push_warning("VoiceChat.set_peer_dead() must be called on the server.")
		return
	_receive_dead.rpc(peer_id, dead)


func is_dead(peer_id: int) -> bool:
	return _dead.get(peer_id, false)


## True when this listener should hear the given player through static.
func should_add_static(peer_id: int) -> bool:
	return is_dead(peer_id) and not is_dead(multiplayer.get_unique_id())


func is_peer_speaking(peer_id: int) -> bool:
	return _speaking.get(peer_id, false)


func is_local_speaking() -> bool:
	return _transmitting


func register_speaker(peer_id: int, speaker: Node) -> void:
	_speakers[peer_id] = speaker


func unregister_speaker(peer_id: int, speaker: Node) -> void:
	if _speakers.get(peer_id) == speaker:
		_speakers.erase(peer_id)


## Start recording one take of a lobby line from the local microphone, whatever
## push-to-talk is doing. Nothing is sent to other players.
func start_take() -> void:
	_take = PackedFloat32Array()
	_taking = true


## Stop recording and return the take (VoiceCodec.RATE mono samples).
func end_take() -> PackedFloat32Array:
	_taking = false
	return _take


func is_taking() -> bool:
	return _taking


## Server only: saved voice clips for a player (VoiceCodec.RATE mono samples).
func get_clips(peer_id: int) -> Array:
	return _clips.get(peer_id, [])


## Server only: players who have at least one saved clip.
func get_peers_with_clips() -> Array:
	var result := []
	for peer_id in _clips.keys():
		if not _clips[peer_id].is_empty() and has_consent(peer_id):
			result.append(peer_id)
	return result


## Server only: delete one of a player's saved clips, or all of them (index -1).
func delete_clip(peer_id: int, index: int) -> void:
	var list: Array = _clips.get(peer_id, [])
	if index < 0:
		_clips.erase(peer_id)
	elif index < list.size():
		list.remove_at(index)


## Delete every saved clip. Call this when a match ends.
func clear_clips() -> void:
	_clips.clear()
	_clip_building.clear()
	_clip_last.clear()


## Forget everything about other players, for example after leaving a match.
func reset() -> void:
	clear_clips()
	_consent.clear()
	_dead.clear()
	_last_heard.clear()
	_speaking.clear()
	if _is_online():  # Not after the host left: get_unique_id() errors then.
		_consent[multiplayer.get_unique_id()] = _my_consent


# --- Microphone -----------------------------------------------------------------

func _setup_microphone() -> void:
	var bus := AudioServer.get_bus_index(&"VoiceCapture")
	_capture = AudioServer.get_bus_effect(bus, 0) as AudioEffectCapture
	_encoder = VoiceCodec.new(AudioServer.get_mix_rate())
	var mic_player := AudioStreamPlayer.new()
	mic_player.stream = AudioStreamMicrophone.new()
	mic_player.bus = &"VoiceCapture"
	add_child(mic_player)
	mic_player.play()


func _read_microphone(delta: float) -> void:
	if _capture == null:
		return
	var available := _capture.get_frames_available()
	if available == 0:
		return
	var samples := _encoder.resample(_capture.get_buffer(available))
	if _taking:
		_take.append_array(samples)
	var wants := _wants_to_talk(samples, delta)
	var fade := roundi(TALK_FADE * VoiceCodec.RATE)
	if wants != _transmitting:
		_transmitting = wants
		local_speaking_changed.emit(wants)
		if wants:
			VoiceCodec.fade(samples, fade, 0)
		elif _is_online() and not _outgoing.is_empty():
			# The last part-packet goes too, faded out, rather than cut off.
			VoiceCodec.fade(_outgoing, 0, fade)
			_send_voice(_outgoing)
	if not _transmitting or not _is_online():
		_outgoing.clear()
		return
	_outgoing.append_array(samples)
	while _outgoing.size() >= PACKET_SAMPLES:
		var chunk := _outgoing.slice(0, PACKET_SAMPLES)
		_outgoing = _outgoing.slice(PACKET_SAMPLES)
		_send_voice(chunk)


func _send_voice(chunk: PackedFloat32Array) -> void:
	_receive_voice.rpc(VoiceCodec.encode(chunk))
	if multiplayer.is_server():
		_store_clip_samples(multiplayer.get_unique_id(), chunk)


func _wants_to_talk(samples: PackedFloat32Array, delta: float) -> bool:
	if mic_muted:
		return false
	if mode == Mode.PUSH_TO_TALK:
		return Input.is_action_pressed(PTT_ACTION)
	if VoiceCodec.rms(samples) >= activation_threshold:
		_hold_left = activation_hold
	else:
		_hold_left = maxf(_hold_left - delta, 0.0)
	return _hold_left > 0.0


# --- Network --------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _receive_voice(packet: PackedByteArray) -> void:
	if packet.is_empty() or packet.size() > PACKET_SAMPLES * VoiceCodec.BYTES_PER_SAMPLE * 2:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var samples := VoiceCodec.decode(packet)
	_last_heard[peer_id] = _time
	if not _speaking.get(peer_id, false):
		_speaking[peer_id] = true
		peer_speaking_changed.emit(peer_id, true)
	var speaker = _speakers.get(peer_id)
	if speaker != null:
		var to_play := samples
		if should_add_static(peer_id):
			to_play = VoiceCodec.add_static(samples, dead_static)
		speaker.play_samples(to_play, should_add_static(peer_id))
	if multiplayer.is_server():
		_store_clip_samples(peer_id, samples)


@rpc("any_peer", "call_remote", "reliable")
func _receive_consent(allowed: bool) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	_consent[peer_id] = allowed
	if not allowed:
		_clips.erase(peer_id)
		_clip_building.erase(peer_id)


@rpc("authority", "call_local", "reliable")
func _receive_dead(peer_id: int, dead: bool) -> void:
	_dead[peer_id] = dead
	peer_dead_changed.emit(peer_id, dead)


func _on_peer_connected(peer_id: int) -> void:
	_receive_consent.rpc_id(peer_id, _my_consent)
	if multiplayer.is_server():
		for dead_peer in _dead.keys():
			_receive_dead.rpc_id(peer_id, dead_peer, _dead[dead_peer])


func _on_peer_disconnected(peer_id: int) -> void:
	for table in [_consent, _dead, _last_heard, _speaking, _clips, _clip_building, _clip_last]:
		table.erase(peer_id)


func _is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer) \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _update_speaking() -> void:
	for peer_id in _last_heard.keys():
		if _speaking.get(peer_id, false) and _time - _last_heard[peer_id] > SPEAKING_TIMEOUT:
			_speaking[peer_id] = false
			peer_speaking_changed.emit(peer_id, false)


# --- Voice clips for the creature (server only) ---------------------------------

func _store_clip_samples(peer_id: int, samples: PackedFloat32Array) -> void:
	if not keep_live_clips or not has_consent(peer_id):
		return
	var building: PackedFloat32Array = _clip_building.get(peer_id, PackedFloat32Array())
	if building.size() < int(CLIP_MAX * VoiceCodec.RATE):
		building.append_array(samples)
	_clip_building[peer_id] = building
	_clip_last[peer_id] = _time


func _finish_quiet_clips() -> void:
	for peer_id in _clip_last.keys():
		if _time - _clip_last[peer_id] < CLIP_GAP:
			continue
		var clip: PackedFloat32Array = _clip_building.get(peer_id, PackedFloat32Array())
		var heard := VoiceCodec.rms(clip) >= CLIP_SILENT
		if clip.size() >= int(CLIP_MIN * VoiceCodec.RATE) and heard and has_consent(peer_id):
			var list: Array = _clips.get(peer_id, [])
			list.append(clip)
			while list.size() > CLIPS_PER_PEER:
				list.pop_front()
			_clips[peer_id] = list
		_clip_building.erase(peer_id)
		_clip_last.erase(peer_id)


# --- Audio buses ----------------------------------------------------------------

func _setup_buses() -> void:
	# Muted bus that only exists so the microphone can be captured.
	_ensure_bus(&"VoiceCapture", [AudioEffectCapture.new()], true)

	# Dead players: thin, crackly radio sound.
	var band := AudioEffectBandPassFilter.new()
	band.cutoff_hz = 1600.0
	var crunch := AudioEffectDistortion.new()
	crunch.drive = 0.35
	_ensure_bus(&"DeadVoice", [band, crunch])

	# Walkie-talkies: a narrow phone band, a little crackle.
	var low_cut := AudioEffectHighPassFilter.new()
	low_cut.cutoff_hz = 350.0
	var high_cut := AudioEffectLowPassFilter.new()
	high_cut.cutoff_hz = 3200.0
	var crackle := AudioEffectDistortion.new()
	crackle.drive = 0.2
	_ensure_bus(&"Radio", [low_cut, high_cut, crackle])

	# The creature's copies: a faint echo as a tell.
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.35
	reverb.wet = 0.22
	_ensure_bus(&"MimicVoice", [reverb])


func _ensure_bus(bus_name: StringName, effects: Array, muted := false) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_mute(index, muted)
	for effect in effects:
		AudioServer.add_bus_effect(index, effect)
