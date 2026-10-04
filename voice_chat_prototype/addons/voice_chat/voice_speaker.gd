class_name VoiceSpeaker
extends AudioStreamPlayer3D
## Plays one player's voice from their position in the world.
## Add it as a child of each remote player's character and set peer_id.

## The network id of the player whose voice this plays.
@export var peer_id := 0
## How far away (in meters) the voice can still be heard.
@export var hearing_range := 30.0

var _playback: AudioStreamGeneratorPlayback


func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = VoiceCodec.RATE
	generator.buffer_length = 0.3
	stream = generator
	max_distance = hearing_range
	unit_size = 4.0
	play()
	_playback = get_stream_playback()
	if peer_id != 0:
		VoiceChat.register_speaker(peer_id, self)


func _exit_tree() -> void:
	VoiceChat.unregister_speaker(peer_id, self)


## Change which player this speaker belongs to.
func set_peer(new_peer_id: int) -> void:
	VoiceChat.unregister_speaker(peer_id, self)
	peer_id = new_peer_id
	if is_inside_tree():
		VoiceChat.register_speaker(peer_id, self)


## Called by VoiceChat with decoded 16 kHz samples.
func play_samples(samples: PackedFloat32Array, through_static := false) -> void:
	if _playback == null:
		return
	bus = &"DeadVoice" if through_static else &"Master"
	var count := mini(_playback.get_frames_available(), samples.size())
	var frames := PackedVector2Array()
	frames.resize(count)
	for i in count:
		frames[i] = Vector2(samples[i], samples[i])
	_playback.push_buffer(frames)
