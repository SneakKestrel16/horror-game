class_name VoiceSpeaker
extends AudioStreamPlayer3D
## Plays one player's voice from their position in the world.
## Add it as a child of each remote player's character and set peer_id.
##
## Packets arrive unevenly over a network, and one that is late empties the
## player and leaves a gap with a click. So each phrase is held back by
## PREBUFFER before it starts, and the queue rides out late packets.

## Seconds of voice held back before a phrase starts playing.
const PREBUFFER := 0.06
## The queue is cut back to PREBUFFER past this, so the voice doesn't lag behind.
const QUEUE_MAX := 0.4

## The network id of the player whose voice this plays.
@export var peer_id := 0
## How far away (in meters) the voice can still be heard.
@export var hearing_range := 30.0

var _playback: AudioStreamGeneratorPlayback
var _queue := PackedFloat32Array()
var _flowing := false
var _since_packet := 0.0


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


func _process(delta: float) -> void:
	_since_packet += delta
	if _playback == null or _queue.is_empty():
		if _since_packet > PREBUFFER:
			_flowing = false  # The phrase is over; the next one buffers again.
		return
	if not _flowing:
		# Start once enough is queued, or the phrase was shorter than that.
		_flowing = _queue.size() >= PREBUFFER * VoiceCodec.RATE or _since_packet > PREBUFFER
		if not _flowing:
			return
	var count := mini(_playback.get_frames_available(), _queue.size())
	var frames := PackedVector2Array()
	frames.resize(count)
	for i in count:
		frames[i] = Vector2(_queue[i], _queue[i])
	_playback.push_buffer(frames)
	_queue = _queue.slice(count)


## Change which player this speaker belongs to.
func set_peer(new_peer_id: int) -> void:
	VoiceChat.unregister_speaker(peer_id, self)
	peer_id = new_peer_id
	if is_inside_tree():
		VoiceChat.register_speaker(peer_id, self)


## Called by VoiceChat with decoded VoiceCodec.RATE samples.
func play_samples(samples: PackedFloat32Array, through_static := false) -> void:
	bus = &"DeadVoice" if through_static else &"Master"
	_queue.append_array(samples)
	_since_packet = 0.0
	if _queue.size() > QUEUE_MAX * VoiceCodec.RATE:
		_queue = _queue.slice(_queue.size() - roundi(PREBUFFER * VoiceCodec.RATE))
