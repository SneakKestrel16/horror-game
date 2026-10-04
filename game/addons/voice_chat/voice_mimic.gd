class_name VoiceMimic
extends AudioStreamPlayer3D
## Lets the creature speak with players' saved voices.
## Add it as a child of the creature and call mimic() on the server.
##
## Each listener can hear a different voice from the same call:
## - Voices of dead players are chosen more often.
## - A listener rarely hears their own voice, since they'd know it isn't them.
## - Players who haven't agreed to voice recording are never copied.
##   If no clips are available, a generic line from fallback_lines is used.
##
## The node must have the same path on every peer (for example, a creature
## spawned with a MultiplayerSpawner), because the clip is sent by RPC.

## Emitted on the server for each listener: which voice they heard (-1 = generic line).
signal mimicked(listener_id: int, source_id: int)

## How likely each kind of voice is to be picked, relative to each other.
@export var dead_weight := 3.0
@export var living_weight := 1.0
@export var own_voice_weight := 0.05
## Generic lines used when no saved clips are available.
@export var fallback_lines: Array[AudioStream] = []
## Static added when copying a dead player, matching how their real voice sounds.
@export_range(0.0, 1.0, 0.01) var dead_static := 0.12

var _fallback_player: AudioStreamPlayer3D


func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = VoiceCodec.RATE
	generator.buffer_length = VoiceChat.CLIP_MAX + 0.5
	stream = generator
	max_distance = 40.0
	unit_size = 4.0
	bus = &"MimicVoice"
	_fallback_player = AudioStreamPlayer3D.new()
	_fallback_player.max_distance = max_distance
	_fallback_player.unit_size = unit_size
	_fallback_player.bus = &"MimicVoice"
	add_child(_fallback_player)


## Server only: play a stolen voice for every player in range.
func mimic() -> void:
	if not multiplayer.is_server():
		push_warning("VoiceMimic.mimic() must be called on the server.")
		return
	var listeners := Array(multiplayer.get_peers())
	listeners.append(multiplayer.get_unique_id())
	for listener in listeners:
		var source := _pick_source(listener)
		if source == -1:
			if fallback_lines.is_empty():
				continue
			_send(listener, &"_play_fallback", [randi() % fallback_lines.size()])
		else:
			var clip: PackedFloat32Array = VoiceChat.get_clips(source).pick_random()
			_send(listener, &"_play_clip", [VoiceCodec.encode(clip), source])
		mimicked.emit(listener, source)


func _pick_source(listener: int) -> int:
	var candidates := VoiceChat.get_peers_with_clips()
	var weights := []
	var total := 0.0
	for peer_id in candidates:
		var weight := living_weight
		if peer_id == listener:
			weight = own_voice_weight
		elif VoiceChat.is_dead(peer_id):
			weight = dead_weight
		weights.append(weight)
		total += weight
	if total <= 0.0:
		return -1
	var roll := randf() * total
	for i in candidates.size():
		roll -= weights[i]
		if roll <= 0.0:
			return candidates[i]
	return candidates[-1]


func _send(listener: int, method: StringName, args: Array) -> void:
	if listener == multiplayer.get_unique_id():
		callv(method, args)
	else:
		callv(&"rpc_id", [listener, method] + args)


@rpc("authority", "call_remote", "reliable")
func _play_clip(data: PackedByteArray, source_id: int) -> void:
	var samples := VoiceCodec.decode(data)
	var through_static := VoiceChat.should_add_static(source_id)
	if through_static:
		samples = VoiceCodec.add_static(samples, dead_static)
	bus = &"DeadVoice" if through_static else &"MimicVoice"
	play()
	var playback := get_stream_playback() as AudioStreamGeneratorPlayback
	var count := mini(playback.get_frames_available(), samples.size())
	var frames := PackedVector2Array()
	frames.resize(count)
	for i in count:
		frames[i] = Vector2(samples[i], samples[i])
	playback.push_buffer(frames)


@rpc("authority", "call_remote", "reliable")
func _play_fallback(index: int) -> void:
	if index < 0 or index >= fallback_lines.size():
		return
	_fallback_player.stream = fallback_lines[index]
	_fallback_player.play()
