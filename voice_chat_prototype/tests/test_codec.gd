extends SceneTree
## Run with: godot --headless --path . -s res://tests/test_codec.gd

func _init() -> void:
	var source_rate := 48000.0
	var frames := PackedVector2Array()
	for i in int(source_rate):  # one second of a 440 Hz tone
		var v := 0.5 * sin(TAU * 440.0 * i / source_rate)
		frames.append(Vector2(v, v))

	var codec := VoiceCodec.new(source_rate)
	var samples := codec.resample(frames)
	var data := VoiceCodec.encode(samples)
	var back := VoiceCodec.decode(data)

	var worst := 0.0
	for i in samples.size():
		worst = maxf(worst, absf(samples[i] - back[i]))

	var ok := samples.size() == 16000 and data.size() == 16000 and worst < 0.02
	ok = ok and is_equal_approx(VoiceCodec.decode(VoiceCodec.encode(PackedFloat32Array([0.0])))[0], 0.0)
	print("samples=%d bytes=%d worst_error=%.4f rms=%.3f" % [samples.size(), data.size(), worst, VoiceCodec.rms(back)])
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)
