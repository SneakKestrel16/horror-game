class_name Sfx
extends RefCounted
## The game's sound effects. Recorded ones from the FilmCow Recorded SFX library
## when tools/get_sfx.sh has copied them into SFX_DIR (git ignores them: the
## licence allows using them in the game but says nothing of sharing the raw
## files in a public repo); otherwise stand-ins synthesised in code. Each sound
## is built once and cached.

const RATE := 22050
const SFX_DIR := "res://assets/sfx"
## Recorded sounds by name: the FilmCow file prefix ("<prefix> <n>.wav" or
## "<prefix>.wav"), a gain in dB from full scale, to sit them near the
## stand-ins' levels, and for some a length in seconds they are cut to (faded).
## Chosen by file name and measurement, not by ear; settle by listening.
##
## Footsteps were "footstep dirt" until a playtest found them wet and far too
## loud (2026-10-04). Measured, that set was the longest (0.46 s on average)
## and boomiest (47% of its energy under 250 Hz); "grass and leaves hard" is
## 0.08 s and drier. That the long low tail was the wet sound is inference.
const RECORDED := {
	"step": ["footstep grass and leaves hard", -18.0, 0.16],
	"corn_step": ["footstep grass and leaves", -15.0, 0.22],
	"rustle": ["bushes", -6.0],
	"splash": ["water splashing small", -8.0],
	"clank": ["metal hits metal", -6.0],
	"snap": ["metal latches", -1.0],
	"thud": ["body fall", -2.0],
	"hum": ["ventilation hum", -14.0],
}
const LOOPS: Array[String] = ["hum", "crickets", "wind", "chase"]
const CUT_FADE := 0.04  ## Seconds faded out where a recording is cut short.
## Synthesised sounds heard over and over come in this many takes, played at
## random, so a run of footsteps doesn't repeat one sample like a machine.
const VARIANTS := {"step": 4, "corn_step": 3, "rustle": 3, "snap": 2, "thud": 2}
## play_at varies each play's pitch and volume by up to this much.
const PITCH_SPREAD := 0.07
const VOLUME_SPREAD := 1.5  ## dB.

static var _cache := {}
static var _files := {}  ## Sound -> its recorded files, found once.


## The named sound: "step", "corn_step", "rustle", "snap", "thud", "splash",
## "clank", "coin", "screech", "caw", "hum" (loops), "crickets" (loops), "wind"
## (loops), "heartbeat" (loops). variant picks one of its takes(sound).
static func get_sound(sound: String, variant := 0) -> AudioStreamWAV:
	var key := "%s#%d" % [sound, variant]
	if not _cache.has(key):
		var files := _recorded(sound)
		var wav: AudioStreamWAV = null
		if not files.is_empty():
			var entry: Array = RECORDED[sound]
			var cut: float = entry[2] if entry.size() > 2 else 0.0
			wav = _load(files[variant % files.size()], entry[1], sound in LOOPS, cut)
		_cache[key] = wav if wav != null else _build(sound, variant)
	return _cache[key]


## Builds every take of every sound now (about 0.6 s with the recorded ones),
## so none is built mid-game with a hitch the first time it plays.
static func warm() -> void:
	for sound: String in VARIANTS.keys() + RECORDED.keys():
		for take in takes(sound):
			get_sound(sound, take)


## How many different takes of a sound there are.
static func takes(sound: String) -> int:
	var files := _recorded(sound)
	return files.size() if not files.is_empty() else VARIANTS.get(sound, 1)


## A one-shot sound from raw samples (-1 to 1) at a sample rate.
static func from_samples(samples: PackedFloat32Array, rate: int) -> AudioStreamWAV:
	var wav := _wav(samples, false)
	wav.mix_rate = rate
	return wav


## Drops the built sounds (they are rebuilt when next asked for).
static func clear_cache() -> void:
	_cache.clear()
	_files.clear()


## Plays sound once at a point under parent, then frees the player.
static func play_at(parent: Node, sound: String, at: Vector3, volume_db := 0.0) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = get_sound(sound, randi() % takes(sound))
	player.volume_db = volume_db + randf_range(-VOLUME_SPREAD, VOLUME_SPREAD)
	player.pitch_scale = 1.0 + randf_range(-PITCH_SPREAD, PITCH_SPREAD)
	player.unit_size = 6.0
	player.max_distance = 60.0
	parent.add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()


## The recorded files for a sound in SFX_DIR, sorted; none if not copied in.
static func _recorded(sound: String) -> Array[String]:
	if not _files.has(sound):
		var found: Array[String] = []
		if RECORDED.has(sound) and DirAccess.dir_exists_absolute(SFX_DIR):
			var prefix: String = RECORDED[sound][0]
			for file in DirAccess.get_files_at(SFX_DIR):
				var stem := file.trim_suffix(".wav")
				var number := stem.trim_prefix(prefix + " ")
				if file.ends_with(".wav") and (stem == prefix or number.is_valid_int()):
					found.append(SFX_DIR.path_join(file))
		found.sort()
		_files[sound] = found
	return _files[sound]


## A recorded file, trimmed of silence, peak at gain_db, cut to max_seconds if
## that is above 0, as 16-bit PCM (made seamless if it loops); null if it won't
## load.
static func _load(path: String, gain_db: float, loop: bool, max_seconds := 0.0) -> AudioStreamWAV:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44:
		return null
	# Some FilmCow files' RIFF size is a few bytes short of the file, which
	# Godot warns about (and check.sh fails on); it is set to the true size.
	bytes.encode_u32(4, bytes.size() - 8)
	var options := {"compress/mode": 0, "edit/trim": true, "edit/normalize": true}
	options["force/mono"] = true
	var wav := AudioStreamWAV.load_from_buffer(bytes, options)
	if wav == null or wav.format != AudioStreamWAV.FORMAT_16_BITS:
		return null
	var gain := db_to_linear(gain_db)
	var pcm := wav.data  # Read once: each read of .data copies the whole buffer.
	var samples := PackedFloat32Array()
	samples.resize(floori(pcm.size() / 2.0))
	for i in samples.size():
		samples[i] = pcm.decode_s16(i * 2) / 32768.0 * gain
	if max_seconds > 0.0 and samples.size() > roundi(max_seconds * wav.mix_rate):
		samples.resize(roundi(max_seconds * wav.mix_rate))
		var fade := roundi(CUT_FADE * wav.mix_rate)
		for i in fade:
			samples[samples.size() - 1 - i] *= float(i) / fade
	if loop:
		samples = _seamless(samples, 0.5, wav.mix_rate)
	var out := _wav(samples, loop)
	out.mix_rate = wav.mix_rate
	return out


static func _build(sound: String, variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s#%d" % [sound, variant]).hash()  # The same sound on every run.
	var samples := PackedFloat32Array()
	var loop := false
	match sound:
		"step":
			samples = _footstep(rng)
		"corn_step":  # A step through dry stalks: a short burst of crackle.
			samples = _noise(rng, rng.randf_range(0.25, 0.35), 0.6, 0.25)
			_grains(rng, samples, 90.0, 0.012)
			_envelope(samples, 0.02, 0.15)
		"rustle":  # Dry leaves: a swell of short crackles, not a hiss.
			samples = _noise(rng, rng.randf_range(0.55, 0.8), 0.6, 0.25)
			_grains(rng, samples, 70.0, 0.018)
			_envelope(samples, 0.12, 0.3)
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
		"caw":
			samples = _caw(rng)
		"hum":
			loop = true
			samples.resize(RATE)  # One second: 60 Hz harmonics fit it exactly.
			_add_tones(samples, [60.0, 120.0, 180.0, 240.0], 0.18, 0.0)
		"crickets":
			loop = true
			samples.resize(RATE * 4)
			# Three crickets out of step, near and far. Each chirp is a few
			# quick pulses; every period and pitch fits the 4 s loop whole.
			for cricket: Array in [
				[4300.0, 0.5, 0.0, 0.11], [4750.0, 0.8, 0.31, 0.06], [5150.0, 0.4, 0.17, 0.04]
			]:
				for i in samples.size():
					var t := float(i) / RATE
					var into := fmod(t + cricket[2], cricket[1])
					if into < 0.12:
						var pulse := pow(sin(PI * fmod(into, 0.03) / 0.03), 2.0)
						samples[i] += cricket[3] * pulse * sin(TAU * cricket[0] * t)
		"wind":
			loop = true
			# Gusts: the noise's pitch and loudness drift together.
			var seconds := 8.0
			samples.resize(roundi(RATE * (seconds + 0.5)))
			var last := 0.0
			for i in samples.size():
				var t := float(i) / RATE
				var gust := 0.5 + 0.3 * sin(TAU * t / seconds) + 0.2 * sin(TAU * 3.0 * t / seconds)
				var smooth := lerpf(0.993, 0.975, gust)
				last = lerpf(rng.randf_range(-1.0, 1.0), last, smooth)
				samples[i] = last * lerpf(3.0, 2.0, gust) * lerpf(0.5, 1.0, gust)
			samples = _seamless(samples, 0.5)
		"heartbeat":  # One lub-dub; Ambience plays it faster as the creature closes in.
			samples.resize(roundi(RATE * 0.34))
			for i in samples.size():
				var t := float(i) / RATE
				var dub := t - 0.15
				var lub := exp(-t * 26.0) * sin(TAU * (50.0 - 14.0 * t) * t)
				var second := 0.0
				if dub > 0.0:
					second = 0.75 * exp(-dub * 32.0) * sin(TAU * 58.0 * dub)
				var body := lub + second
				# An octave up, so it carries on small speakers too.
				samples[i] = 0.8 * body + 0.25 * body * sin(TAU * 100.0 * t)
			_envelope(samples, 0.004, 0.03)
		"chase":  # Dread under a chase: a low dissonant cluster that swells, a thin whine.
			loop = true
			var seconds := 8.0
			samples.resize(roundi(RATE * (seconds + 0.5)))
			var rumble := 0.0
			for i in samples.size():
				var t := float(i) / RATE
				var swell := 0.75 + 0.25 * sin(TAU * t / 4.0)
				var low := (
					sin(TAU * 41.2 * t)
					+ 0.8 * sin(TAU * 43.65 * t)
					+ 0.6 * sin(TAU * 61.74 * t)
					+ 0.3 * sin(TAU * 82.4 * t)
				)
				var wobble := 1.0 + sin(TAU * 5.5 * t) * 0.004
				var high := (
					sin(TAU * 466.2 * t * wobble)
					+ sin(TAU * 493.9 * t / wobble)
					+ 0.6 * sin(TAU * 698.5 * t)
				)
				rumble = lerpf(rng.randf_range(-1.0, 1.0), rumble, 0.97)
				samples[i] = (
					tanh(low * 0.9) * 0.3 * swell
					+ high * 0.025 * (0.6 + 0.4 * sin(TAU * t * 3.0 / seconds))
					+ rumble * 0.6
				)
			samples = _seamless(samples, 0.5)
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


## A step on packed dirt: a dull heel thump, then a gritty toe a beat later.
static func _footstep(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(roundi(RATE * 0.22))
	var heel := _noise(rng, 0.08, 0.5, 0.88)
	_envelope(heel, 0.003, 0.07)
	var thump := rng.randf_range(70.0, 100.0)
	for i in heel.size():
		var t := float(i) / RATE
		heel[i] += 0.3 * sin(TAU * thump * t) * exp(-t * 45.0)
	var toe := _noise(rng, 0.11, 0.3, 0.5)
	_grains(rng, toe, 260.0, 0.004)
	_envelope(toe, 0.004, 0.08)
	var toe_at := roundi(RATE * rng.randf_range(0.04, 0.07))
	for i in heel.size():
		samples[i] += heel[i]
	for i in mini(toe.size(), samples.size() - toe_at):
		samples[toe_at + i] += toe[i]
	return samples


## A crow: three harsh "kaaw"s, each a buzzy sawtooth sliding down in pitch,
## with every other cycle louder (the rasp of a crow's voice is that doubled
## period) and breath noise, through two nasal formants. Shaped from what a
## crow's caw is described as, not from a recording; settle by listening.
static func _caw(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var calls := [0.0, 0.42, 0.86]
	var length := 0.3
	var source := PackedFloat32Array()
	source.resize(roundi(RATE * (calls[-1] + length + 0.05)))
	for k in calls.size():
		var start := roundi(RATE * float(calls[k]))
		var phase := 0.0
		var drift := 0.0
		var high := 780.0 - 40.0 * k  # Each call a little lower and wearier.
		for i in roundi(RATE * length):
			var u := float(i) / (RATE * length)
			drift = clampf(drift + rng.randf_range(-6.0, 6.0), -40.0, 40.0)
			phase += (lerpf(high, high * 0.7, u) + drift) / RATE
			var saw := 2.0 * fposmod(phase, 1.0) - 1.0
			var rasp := 1.0 if int(phase) % 2 == 0 else 0.55
			var shape := minf(1.0, u / 0.06) * pow(1.0 - u, 0.7)
			source[start + i] = shape * (saw * rasp + rng.randf_range(-0.4, 0.4))
	var samples := _bandpass(source, 1400.0, 1.8)
	var upper := _bandpass(source, 2500.0, 2.5)
	var peak := 0.0
	for i in samples.size():
		samples[i] += 0.7 * upper[i]
		peak = maxf(peak, absf(samples[i]))
	for i in samples.size():
		samples[i] *= 0.7 / peak
	return samples


## A resonant band-pass (the RBJ cookbook biquad, 0 dB at the centre).
static func _bandpass(samples: PackedFloat32Array, centre: float, q: float) -> PackedFloat32Array:
	var w := TAU * centre / RATE
	var alpha := sin(w) / (2.0 * q)
	var a0 := 1.0 + alpha
	var b0 := alpha / a0
	var a1 := -2.0 * cos(w) / a0
	var a2 := (1.0 - alpha) / a0
	var out := PackedFloat32Array()
	out.resize(samples.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in samples.size():
		var y := b0 * samples[i] - b0 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = samples[i]
		y2 = y1
		y1 = y
		out[i] = y
	return out


## Breaks steady noise into crackles: rate short grains a second at random,
## each dying away over decay seconds.
static func _grains(
	rng: RandomNumberGenerator, samples: PackedFloat32Array, rate: float, decay: float
) -> void:
	var level := 0.0
	var fall := exp(-1.0 / (decay * RATE))
	for i in samples.size():
		if rng.randf() < rate / RATE:
			level = rng.randf_range(0.4, 1.0)
		level *= fall
		samples[i] *= 0.15 + level


## A loop with no click where it wraps: the last overlap seconds are faded
## into the start and cut off.
static func _seamless(
	samples: PackedFloat32Array, overlap: float, rate := RATE
) -> PackedFloat32Array:
	var count := roundi(rate * overlap)
	var keep := samples.size() - count
	for i in count:
		var mix := float(i) / count
		samples[i] = samples[i] * mix + samples[keep + i] * (1.0 - mix)
	return samples.slice(0, keep)


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
## animals); the generator's hum while it runs. In a chase, a low dissonant
## drone swells in, and the listener's heart beats faster and louder the
## closer the creature gets, and keeps pounding a while after it gives up.
## Also makes the "Lure" bus the creature's voice plays on.
class Ambience:
	const QUIET_NEAR := 18.0  ## Crickets stop with the creature this close (m).
	const HEARTBEAT_NEAR := 25.0  ## The heart races with a chasing creature this close.
	const CHASE_NEAR := 45.0  ## The chase drone plays with a chasing creature this close.
	const BPM := Vector2(72.0, 168.0)  ## Heart rate barely scared, and at its worst.
	const CALM_DOWN := 0.08  ## Fear lost a second once it's over: about 12 s to calm.
	const DREAD_DB := -6.0  ## The chase drone at full.

	var _wind: AudioStreamPlayer
	var _crickets: AudioStreamPlayer
	var _chase: AudioStreamPlayer
	var _heart := AudioStreamPlayer.new()
	var _hum := AudioStreamPlayer3D.new()
	var _fear := 0.0  ## 0 calm to 1 terrified: the heart's rate and loudness.
	var _beat_left := 0.0
	var _dread := -60.0  ## The chase drone's volume, faded in and out.

	func _init(parent: Node3D) -> void:
		Sfx.warm()
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
		_chase = _loop(parent, "chase", _dread)
		_heart.stream = Sfx.get_sound("heartbeat")
		parent.add_child(_heart)
		_hum.stream = Sfx.get_sound("hum")
		_hum.unit_size = 3.0
		_hum.max_distance = 30.0
		_hum.position = Farm.GENERATOR + Vector3.UP * 0.5
		parent.add_child(_hum)

	## creature_distance is INF with no creature or no listener.
	func update(
		delta: float, dark: bool, over: bool, creature_distance: float, chased: bool, lit: bool
	) -> void:
		_set_playing(_wind, not dark and not over)
		_set_playing(_crickets, dark and not over and creature_distance > QUIET_NEAR)
		_set_playing(_hum, lit)
		var hunted := chased and not over
		var fear := 0.0
		if hunted and creature_distance < HEARTBEAT_NEAR:
			fear = 0.3 + 0.7 * (1.0 - creature_distance / HEARTBEAT_NEAR)
		_fear = move_toward(_fear, fear, delta * (0.6 if fear > _fear else CALM_DOWN))
		if over:
			_fear = 0.0
		_beat_left -= delta
		if _fear > 0.05 and _beat_left <= 0.0:
			_beat_left = 60.0 / lerpf(BPM.x, BPM.y, _fear)
			_heart.volume_db = lerpf(-18.0, 0.0, _fear)
			_heart.play()
		var dread := DREAD_DB if hunted and creature_distance < CHASE_NEAR else -60.0
		_dread = move_toward(_dread, dread, delta * (30.0 if dread > _dread else 12.0))
		_chase.volume_db = _dread
		_set_playing(_chase, _dread > -59.0)

	## The heart rate now, in beats a minute (0 when calm).
	func heart_rate() -> float:
		return lerpf(BPM.x, BPM.y, _fear) if _fear > 0.05 else 0.0

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
