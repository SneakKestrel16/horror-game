class_name VoiceCodec
extends RefCounted
## Turns microphone audio into network packets and back again.
##
## Audio is mixed to mono, filtered, resampled to 24 kHz and stored as 16-bit
## PCM: about 48 KB per second for each talking player. It was 16 kHz 8-bit
## mu-law (16 KB/s); the 2026-10-04 playtests found voice quality poor. That
## mu-law's hiss and the 8 kHz top end were the cause is inference.

const RATE := 24000
const BYTES_PER_SAMPLE := 2
## Rumble under this is cut: mic handling, desk thumps, a DC offset.
const HIGH_PASS_HZ := 80.0
## The anti-aliasing low-pass, as a fraction of RATE (under its 0.5 limit).
const LOW_PASS := 0.45
## Q of the two biquads that make a 4th-order Butterworth low-pass.
const _BUTTERWORTH_Q: Array[float] = [0.5412, 1.3066]

var _ratio: float
var _position := 0.0  ## Next read point into _pending, in source frames.
var _pending := PackedFloat32Array()
## Filter stages, high-pass first, five numbers each: b0, b1, b2, a1, a2 (a0
## divided out).
var _stages := PackedFloat64Array()
var _state := PackedFloat64Array()  ## Four numbers a stage: x1, x2, y1, y2.


func _init(source_rate: float = 48000.0) -> void:
	_ratio = source_rate / RATE
	_stages.append_array(_biquad(source_rate, HIGH_PASS_HZ, 0.7071, true))
	if LOW_PASS * RATE < 0.45 * source_rate:  # Nothing to cut when not downsampling.
		for q in _BUTTERWORTH_Q:
			_stages.append_array(_biquad(source_rate, LOW_PASS * RATE, q, false))
	_state.resize(roundi(_stages.size() * 0.8))  # Four state numbers for five coefficients.


## Feed stereo frames from an AudioEffectCapture. Returns RATE mono samples.
## Leftover frames are kept and used on the next call.
##
## Filtered before it is resampled, so high sounds don't fold down into hiss
## (the old version averaged blocks of frames, a poor filter, and dropped
## frames when the rates didn't divide evenly).
func resample(frames: PackedVector2Array) -> PackedFloat32Array:
	var mono := PackedFloat32Array()
	mono.resize(frames.size())
	for i in frames.size():
		mono[i] = (frames[i].x + frames[i].y) * 0.5
	for stage in roundi(_state.size() * 0.25):
		_filter(mono, stage)
	_pending.append_array(mono)
	var count := maxi(0, ceili((_pending.size() - 1 - _position) / _ratio))
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var at := int(_position)
		out[i] = lerpf(_pending[at], _pending[at + 1], _position - at)
		_position += _ratio
	var used := int(_position)
	_pending = _pending.slice(used)
	_position -= used
	return out


## Compress RATE samples (-1.0 to 1.0) into BYTES_PER_SAMPLE bytes each.
static func encode(samples: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples.size() * BYTES_PER_SAMPLE)
	for i in samples.size():
		out.encode_s16(i * BYTES_PER_SAMPLE, roundi(clampf(samples[i], -1.0, 1.0) * 32767.0))
	return out


## Expand bytes made by encode() back into samples.
static func decode(data: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(floori(data.size() / float(BYTES_PER_SAMPLE)))
	for i in out.size():
		out[i] = data.decode_s16(i * BYTES_PER_SAMPLE) / 32768.0
	return out


## How long encoded audio lasts, in seconds.
static func seconds(data: PackedByteArray) -> float:
	return data.size() / float(BYTES_PER_SAMPLE * RATE)


## Loudness of a chunk of samples, used for voice activation.
static func rms(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var total := 0.0
	for s in samples:
		total += s * s
	return sqrt(total / samples.size())


## Returns a copy of the samples with radio-style static mixed in.
static func add_static(samples: PackedFloat32Array, amount: float) -> PackedFloat32Array:
	var out := samples.duplicate()
	for i in out.size():
		out[i] = clampf(out[i] + randf_range(-amount, amount), -1.0, 1.0)
	return out


## Fades the first fade_in and last fade_out samples, in place, so a phrase
## neither starts nor stops on a click.
static func fade(samples: PackedFloat32Array, fade_in: int, fade_out: int) -> void:
	fade_in = mini(fade_in, samples.size())
	fade_out = mini(fade_out, samples.size())
	for i in fade_in:
		samples[i] *= float(i) / fade_in
	for i in fade_out:
		samples[samples.size() - 1 - i] *= float(i) / fade_out


## One biquad's coefficients (RBJ Audio EQ Cookbook), divided by a0.
static func _biquad(rate: float, cutoff: float, q: float, high: bool) -> PackedFloat64Array:
	var w := TAU * cutoff / rate
	var alpha := sin(w) / (2.0 * q)
	var c := cos(w)
	var b0 := (1.0 + c) / 2.0 if high else (1.0 - c) / 2.0
	var b1 := -(1.0 + c) if high else 1.0 - c
	var a0 := 1.0 + alpha
	return PackedFloat64Array([b0 / a0, b1 / a0, b0 / a0, -2.0 * c / a0, (1.0 - alpha) / a0])


## Runs samples through one biquad stage in place, carrying its state between
## calls.
func _filter(samples: PackedFloat32Array, stage: int) -> void:
	var k := stage * 5
	var b0 := _stages[k]
	var b1 := _stages[k + 1]
	var b2 := _stages[k + 2]
	var a1 := _stages[k + 3]
	var a2 := _stages[k + 4]
	var s := stage * 4
	var x1 := _state[s]
	var x2 := _state[s + 1]
	var y1 := _state[s + 2]
	var y2 := _state[s + 3]
	for i in samples.size():
		var x := samples[i]
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		samples[i] = y
	_state[s] = x1
	_state[s + 1] = x2
	_state[s + 2] = y1
	_state[s + 3] = y2
