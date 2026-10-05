class_name VoiceSpeaker
extends AudioStreamPlayer3D
## Plays one player's voice from their position in the world.
## Add it as a child of each remote player's character and set peer_id.
##
## Packets arrive unevenly over a network, and one that is late empties the
## player and leaves a gap with a click. So each phrase is held back by
## PREBUFFER before it starts, and the queue rides out late packets.
##
## With VoiceChat.radio_enabled (walkie-talkies), a living speaker further than
## hearing_range from the listener is heard over the radio instead: flat, on
## the "Radio" bus, after a burst of squelch. The dead are never on it.

## Seconds of voice held back before a phrase starts playing.
const PREBUFFER := 0.06
## The queue is cut back to PREBUFFER past this, so the voice doesn't lag behind.
const QUEUE_MAX := 0.4
const SQUELCH := 0.05  ## Seconds of hiss as a radio phrase starts.

## The network id of the player whose voice this plays.
@export var peer_id := 0
## How far away (in meters) the voice can still be heard.
@export var hearing_range := 30.0

var _playback: AudioStreamGeneratorPlayback
var _radio := AudioStreamPlayer.new()
var _radio_playback: AudioStreamGeneratorPlayback
var _queue := PackedFloat32Array()
var _flowing := false
var _on_radio := false  ## This phrase goes over the radio.
var _since_packet := 0.0


func _ready() -> void:
	stream = _generator()
	max_distance = hearing_range
	unit_size = 4.0
	play()
	_playback = get_stream_playback()
	_radio.stream = _generator()
	_radio.bus = &"Radio"
	add_child(_radio)
	_radio.play()
	_radio_playback = _radio.get_stream_playback()
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
		_on_radio = _wants_radio()
		if _on_radio:
			var hiss := PackedFloat32Array()
			hiss.resize(roundi(SQUELCH * VoiceCodec.RATE))
			_push(_radio_playback, VoiceCodec.add_static(hiss, 0.25))
	var target := _radio_playback if _on_radio else _playback
	var count := mini(target.get_frames_available(), _queue.size())
	_push(target, _queue.slice(0, count))
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


## Over the radio: walkie-talkies on, speaker and listener alive, and the
## speaker out of earshot.
func _wants_radio() -> bool:
	if not VoiceChat.radio_enabled or VoiceChat.is_dead(peer_id):
		return false
	if VoiceChat.is_dead(multiplayer.get_unique_id()):
		return false
	var camera := get_viewport().get_camera_3d()
	return camera != null and camera.global_position.distance_to(global_position) > hearing_range


static func _generator() -> AudioStreamGenerator:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = VoiceCodec.RATE
	generator.buffer_length = 0.3
	return generator


static func _push(playback: AudioStreamGeneratorPlayback, samples: PackedFloat32Array) -> void:
	var count := mini(playback.get_frames_available(), samples.size())
	var frames := PackedVector2Array()
	frames.resize(count)
	for i in count:
		frames[i] = Vector2(samples[i], samples[i])
	playback.push_buffer(frames)
