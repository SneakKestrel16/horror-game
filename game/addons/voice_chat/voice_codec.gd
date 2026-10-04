class_name VoiceCodec
extends RefCounted
## Turns microphone audio into small network packets and back again.
##
## Audio is mixed to mono, resampled to 16 kHz and stored as 8-bit mu-law,
## which is about 16 KB per second of speech for each talking player.

const RATE := 16000
const _BIAS := 0x84
const _CLIP := 32635

static var _decode_table := _build_decode_table()

var _ratio: float
var _pending := PackedFloat32Array()


func _init(source_rate: float = 48000.0) -> void:
	_ratio = source_rate / RATE


## Feed stereo frames from an AudioEffectCapture. Returns 16 kHz mono samples.
## Leftover frames are kept and used on the next call.
func resample(frames: PackedVector2Array) -> PackedFloat32Array:
	for frame in frames:
		_pending.append((frame.x + frame.y) * 0.5)
	var out_count := int(floor(_pending.size() / _ratio))
	var out := PackedFloat32Array()
	out.resize(out_count)
	for i in out_count:
		var start := int(i * _ratio)
		var end := int((i + 1) * _ratio)
		var total := 0.0
		for j in range(start, end):
			total += _pending[j]
		out[i] = total / maxi(1, end - start)
	_pending = _pending.slice(int(out_count * _ratio))
	return out


## Compress 16 kHz samples (-1.0 to 1.0) into one byte per sample.
static func encode(samples: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples.size())
	for i in samples.size():
		out[i] = _mulaw_encode(samples[i])
	return out


## Expand bytes made by encode() back into samples.
static func decode(data: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(data.size())
	for i in data.size():
		out[i] = _decode_table[data[i]]
	return out


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


static func _mulaw_encode(sample: float) -> int:
	var s := int(clampf(sample, -1.0, 1.0) * 32767.0)
	var sign_bit := 0
	if s < 0:
		sign_bit = 0x80
		s = -s
	if s > _CLIP:
		s = _CLIP
	s += _BIAS
	var exponent := 7
	var mask := 0x4000
	while (s & mask) == 0 and exponent > 0:
		exponent -= 1
		mask >>= 1
	var mantissa := (s >> (exponent + 3)) & 0x0F
	return ~(sign_bit | (exponent << 4) | mantissa) & 0xFF


static func _mulaw_decode(byte: int) -> float:
	var b := ~byte & 0xFF
	var exponent := (b >> 4) & 0x07
	var mantissa := b & 0x0F
	var s := (((mantissa << 3) + _BIAS) << exponent) - _BIAS
	if b & 0x80:
		s = -s
	return s / 32768.0


static func _build_decode_table() -> PackedFloat32Array:
	var table := PackedFloat32Array()
	table.resize(256)
	for i in 256:
		table[i] = _mulaw_decode(i)
	return table
