class_name Lobby
extends CanvasLayer
## Before the first day: who is here, and recording the lines the creature may
## call with (design doc, Keeping Players on In-Game Voice). Recording is
## opt-in: nothing is recorded until the player ticks consent, and unticking it
## deletes their takes. Each line can be recorded a few times, with a prompt to
## say it scared, and played back. A player can keep their voice from being
## played to chosen teammates. The host starts the day; the lobby then closes.

var game: Game

var _consent: CheckBox
var _lines: VBoxContainer
var _blocks: VBoxContainer
var _players: Label
var _status: Label
var _recording := ""  ## The key being recorded, or "".
var _record_left := 0.0
var _takes := {}  ## key -> Array of PackedFloat32Array, this player's own.
var _playback := AudioStreamPlayer.new()
var _blocked: Array[int] = []


func _init(owner_game: Game) -> void:
	game = owner_game


func _ready() -> void:
	add_to_group("lobby")
	layer = 5
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	add_child(_playback)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 680)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)

	_label(column, "BEFORE THE DAY", 28)
	_players = _label(column, "", 16)
	var about := _label(
		column,
		(
			"Something in the corn copies voices. If you agree, record the lines below: it may"
			+ " call your friends with them. Recordings stay in this match only. Hold V in game"
			+ " to talk to whoever is near you."
		),
		14
	)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD
	_consent = CheckBox.new()
	_consent.text = "Let the creature copy my voice (kept for this match only)"
	_consent.toggled.connect(_on_consent)
	column.add_child(_consent)
	_lines = VBoxContainer.new()
	column.add_child(_lines)
	_label(column, "Never play my voice to:", 16)
	_blocks = VBoxContainer.new()
	column.add_child(_blocks)

	_status = _label(column, "", 16)
	if multiplayer.is_server():
		var start := Button.new()
		start.text = "Start the day"
		start.pressed.connect(func() -> void: game.start_day())
		column.add_child(start)
	game.voices.changed.connect(_rebuild)
	_rebuild()


func _process(delta: float) -> void:
	if not game.in_lobby:
		if _recording != "":
			VoiceChat.end_take()
		queue_free()
		return
	if _recording != "":
		_record_left -= delta
		_status.text = "Recording... %.1f s left. Click Stop when done." % maxf(0.0, _record_left)
		if _record_left <= 0.0:
			_stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Lines to record (the fixed list and each teammate's name), the players and
## their takes, and the block boxes; redrawn when someone joins or records.
func _rebuild() -> void:
	var me := multiplayer.get_unique_id()
	var who: Array[String] = []
	for peer: int in game.voices.names:
		var count: int = game.voices.counts.get(peer, 0)
		who.append("%s (%d takes)" % [game.voices.names[peer], count])
	_players.text = "Here: " + ", ".join(who)
	if not multiplayer.is_server():
		_status.text = "Waiting for the host to start the day."
	for child in _lines.get_children():
		child.queue_free()
	for key in game.voices.keys_for(me):
		_line_row(key)
	for child in _blocks.get_children():
		child.queue_free()
	for peer: int in game.voices.names:
		if peer == me:
			continue
		var box := CheckBox.new()
		box.text = game.voices.names[peer]
		box.button_pressed = peer in _blocked
		box.toggled.connect(_on_block.bind(peer))
		_blocks.add_child(box)


func _line_row(key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_lines.add_child(row)
	var words := Label.new()
	words.text = game.voices.line_text(key)
	words.custom_minimum_size.x = 170
	row.add_child(words)
	var prompt := Label.new()
	prompt.text = _prompt(key)
	prompt.modulate = Color(1, 1, 1, 0.6)
	prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD
	row.add_child(prompt)
	var takes: Array = _takes.get(key, [])
	var count := Label.new()
	count.text = "%d/%d" % [takes.size(), VoiceBank.TAKES]
	row.add_child(count)
	var record := Button.new()
	record.text = "Stop" if _recording == key else "Record"
	record.disabled = not _consent.button_pressed or (_recording != "" and _recording != key)
	record.pressed.connect(_on_record.bind(key))
	row.add_child(record)
	var play := Button.new()
	play.text = "Play"
	play.disabled = takes.is_empty()
	play.pressed.connect(func() -> void: _play(key))
	row.add_child(play)


func _prompt(key: String) -> String:
	if key.begins_with("name_"):
		return VoiceBank.NAME_PROMPT
	for line in VoiceBank.LINES:
		if line["key"] == key:
			return line["prompt"]
	return ""


func _on_consent(on: bool) -> void:
	if not on:
		_takes.clear()
		game.voices.withdraw()
	_rebuild()


func _on_record(key: String) -> void:
	if _recording == key:
		_stop()
		return
	_recording = key
	_record_left = VoiceBank.TAKE_MAX
	VoiceChat.start_take()
	_rebuild()


func _stop() -> void:
	var samples := VoiceChat.end_take()
	var key := _recording
	_recording = ""
	if samples.size() < VoiceBank.TAKE_MIN * VoiceCodec.RATE:
		_status.text = "Too short; try again. (Is your microphone allowed in Windows privacy settings?)"
	elif VoiceCodec.rms(samples) < 0.005:
		_status.text = "That take was silent. Check your microphone."
	else:
		var takes: Array = _takes.get_or_add(key, [])
		takes.append(samples)
		while takes.size() > VoiceBank.TAKES:
			takes.pop_front()
		game.voices.upload(key, samples)
		_status.text = "Saved. Record it again for a different take, or play it back."
	_rebuild()


func _play(key: String) -> void:
	var takes: Array = _takes.get(key, [])
	if not takes.is_empty():
		_playback.stream = Sfx.from_samples(takes[-1], VoiceCodec.RATE)
		_playback.play()


func _on_block(on: bool, peer: int) -> void:
	if on and peer not in _blocked:
		_blocked.append(peer)
	elif not on:
		_blocked.erase(peer)
	game.voices.block(_blocked)


func _label(parent: Control, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label
