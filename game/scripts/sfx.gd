class_name Sfx
extends RefCounted
## Placeholder sound effects, synthesised in code so the prototype needs no
## audio files besides the voice lines. Each sound is built once and cached.
## Replace with recorded sounds once the game is worth dressing.

const RATE := 22050

static var _cache := {}


## The named sound: "step", "rustle", "snap", "thud", "splash", "clank",
## "coin", "screech", "caw", "hum" (loops), "crickets" (loops), "wind" (loops),
## "heartbeat" (loops).
static func get_sound(sound: String) -> AudioStreamWAV:
	if not _cache.has(sound):
		_cache[sound] = _build(sound)
	return _cache[sound]


## A one-shot sound from raw samples (-1 to 1) at a sample rate.
static func from_samples(samples: PackedFloat32Array, rate: int) -> AudioStreamWAV:
	var wav := _wav(samples, false)
	wav.mix_rate = rate
	return wav


## Drops the built sounds (they are rebuilt when next asked for).
static func clear_cache() -> void:
	_cache.clear()


## Plays sound once at a point under parent, then frees the player.
static func play_at(parent: Node, sound: String, at: Vector3, volume_db := 0.0) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = get_sound(sound)
	player.volume_db = volume_db
	player.unit_size = 6.0
	player.max_distance = 60.0
	parent.add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()


static func _build(sound: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = sound.hash()  # The same sound on every run.
	var samples := PackedFloat32Array()
	var loop := false
	match sound:
		"step":
			samples = _noise(rng, 0.09, 0.35, 0.6)
			_envelope(samples, 0.004, 0.08)
		"rustle":
			samples = _noise(rng, 0.7, 0.55, 0.2)
			for i in samples.size():  # Crackle: leaves knocking.
				samples[i] *= 0.5 + 0.5 * absf(sin(i * 0.004 + sin(i * 0.0011) * 4.0))
			_envelope(samples, 0.15, 0.35)
		"snap":
			samples = _noise(rng, 0.9, 1.0, 0.8)
			_envelope(samples, 0.001, 0.03)
			_add_tones(samples, [1240.0, 2710.0, 3930.0], 0.35, 6.0)
		"thud":
			samples = _noise(rng, 0.3, 0.6, 0.97)
			_add_tones(samples, [70.0, 110.0], 0.7, 14.0)
			_envelope(samples, 0.002, 0.25)
		"splash":
			samples = _noise(rng, 0.8, 0.35, 0.3)
			_envelope(samples, 0.05, 0.6)
		"clank":
			samples = PackedFloat32Array()
			samples.resize(roundi(RATE * 0.5))
			_add_tones(samples, [520.0, 1330.0, 2210.0], 0.4, 9.0)
		"coin":
			samples.resize(roundi(RATE * 0.5))
			_add_tones(samples, [1318.5, 1975.5], 0.3, 7.0)
		"screech":
			samples = _noise(rng, 1.4, 0.25, 0.4)
			var phase := 0.0
			for i in samples.size():
				var t := float(i) / RATE
				phase += TAU * lerpf(900.0, 260.0, t / 1.4) / RATE
				samples[i] += 0.5 * (sin(phase) + 0.4 * sin(phase * 2.03) + 0.25 * sin(phase * 3.1))
			_envelope(samples, 0.08, 0.6)
		"caw":  # Two harsh croaks: a buzzing tone through a rough envelope.
			samples.resize(roundi(RATE * 0.75))
			for i in samples.size():
				var t := float(i) / RATE
				var croak := fmod(t, 0.38)
				var shape := sin(PI * minf(croak / 0.26, 1.0)) * float(croak < 0.26)
				var buzz := sin(TAU * 620.0 * t + 3.0 * sin(TAU * 90.0 * t))
				samples[i] = 0.55 * shape * (buzz + rng.randf_range(-0.35, 0.35))
		"hum":
			loop = true
			samples.resize(RATE)  # One second: 60 Hz harmonics fit it exactly.
			_add_tones(samples, [60.0, 120.0, 180.0, 240.0], 0.18, 0.0)
		"crickets":
			loop = true
			samples.resize(RATE * 2)
			for i in samples.size():
				var t := float(i) / RATE
				var chirp := maxf(0.0, sin(TAU * 18.0 * t)) * float(fmod(t, 0.5) < 0.18)
				samples[i] = 0.12 * chirp * sin(TAU * 4500.0 * t)
		"wind":
			loop = true
			samples = _noise(rng, 4.0, 0.25, 0.985)
			for i in samples.size():
				samples[i] *= 0.6 + 0.4 * sin(TAU * i / samples.size())
		"heartbeat":
			loop = true
			samples.resize(roundi(RATE * 0.8))
			for i in samples.size():
				var t := float(i) / RATE
				var beat := (
					exp(-t * 30.0) + 0.7 * exp(-maxf(0.0, t - 0.22) * 30.0) * float(t > 0.22)
				)
				samples[i] = 0.9 * beat * sin(TAU * 52.0 * t)
	return _wav(samples, loop)


## White noise at amplitude, smoothed by a one-pole low-pass (0 = none, near
## 1 = rumble).
static func _noise(
	rng: RandomNumberGenerator, seconds: float, amplitude: float, smooth: float
) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(roundi(RATE * seconds))
	var last := 0.0
	var gain := 1.0 / (1.0 - smooth * 0.9)  # Low-passing quietens it; roughly undo that.
	for i in samples.size():
		last = lerpf(rng.randf_range(-1.0, 1.0), last, smooth)
		samples[i] = clampf(last * amplitude * gain, -1.0, 1.0)
	return samples


## Decaying sine tones mixed in (decay per second; 0 = steady).
static func _add_tones(
	samples: PackedFloat32Array, tones: Array, amplitude: float, decay: float
) -> void:
	for i in samples.size():
		var t := float(i) / RATE
		var sum := 0.0
		for tone: float in tones:
			sum += sin(TAU * tone * t)
		samples[i] += amplitude * sum / tones.size() * exp(-decay * t)


static func _envelope(samples: PackedFloat32Array, attack: float, release: float) -> void:
	var count := samples.size()
	for i in count:
		var t := float(i) / RATE
		var left := float(count - i) / RATE
		samples[i] *= minf(1.0, t / attack) * minf(1.0, left / release)


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, roundi(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples.size()
	return wav


## The farm's background sound: wind by day; crickets by night that go quiet
## when the creature is near the listener (the warning the design doc gives
## animals); a heartbeat while it chases nearby; the generator's hum while it
## runs. Also makes the "Lure" bus the creature's voice plays on.
class Ambience:
	const QUIET_NEAR := 18.0  ## Crickets stop with the creature this close (m).
	const HEARTBEAT_NEAR := 22.0

	var _wind: AudioStreamPlayer
	var _crickets: AudioStreamPlayer
	var _heartbeat: AudioStreamPlayer
	var _hum := AudioStreamPlayer3D.new()

	func _init(parent: Node3D) -> void:
		if AudioServer.get_bus_index(&"Lure") == -1:
			# The creature's voice has a faint echo: the tell (design doc, How Players Fight Back).
			AudioServer.add_bus()
			var bus := AudioServer.bus_count - 1
			AudioServer.set_bus_name(bus, &"Lure")
			var echo := AudioEffectReverb.new()
			echo.room_size = 0.5
			echo.wet = 0.22
			echo.dry = 0.9
			AudioServer.add_bus_effect(bus, echo)
		_wind = _loop(parent, "wind", -16.0)
		_crickets = _loop(parent, "crickets", -20.0)
		_heartbeat = _loop(parent, "heartbeat", -4.0)
		_hum.stream = Sfx.get_sound("hum")
		_hum.unit_size = 3.0
		_hum.max_distance = 30.0
		_hum.position = Farm.GENERATOR + Vector3.UP * 0.5
		parent.add_child(_hum)

	## creature_distance is INF with no creature or no listener.
	func update(dark: bool, over: bool, creature_distance: float, chased: bool, lit: bool) -> void:
		_set_playing(_wind, not dark and not over)
		_set_playing(_crickets, dark and not over and creature_distance > QUIET_NEAR)
		_set_playing(_heartbeat, chased and creature_distance < HEARTBEAT_NEAR)
		_set_playing(_hum, lit)

	static func _loop(parent: Node, sound: String, volume_db: float) -> AudioStreamPlayer:
		var player := AudioStreamPlayer.new()
		player.stream = Sfx.get_sound(sound)
		player.volume_db = volume_db
		parent.add_child(player)
		return player

	static func _set_playing(player: Node, on: bool) -> void:
		var playing: bool = player.get("playing")
		if on and not playing:
			player.call("play")
		elif not on and playing:
			player.call("stop")
