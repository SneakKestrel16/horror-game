class_name ClipList
extends CanvasLayer
## What the host keeps of this player's voice-chat phrases for the creature to
## call with, to hear and delete (design doc, Build Notes: live clips are
## reviewable and deletable). C shows or hides it, Esc hides it. The list comes
## from the host each time it opens and after each delete.

var game: Game

var _panel: PanelContainer
var _rows: VBoxContainer
var _note: Label
var _playback := AudioStreamPlayer.new()


func _init(owner_game: Game) -> void:
	game = owner_game


func _ready() -> void:
	layer = 9
	add_child(_playback)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.position = Vector2(-376, 180)  # Below the announcements.
	_panel.custom_minimum_size = Vector2(360, 0)
	_panel.visible = false
	add_child(_panel)
	var column := VBoxContainer.new()
	_panel.add_child(column)
	var heading := Label.new()
	heading.text = "YOUR VOICE  (C)"
	heading.add_theme_font_size_override("font_size", 16)
	heading.modulate = Color(1.0, 0.85, 0.45)
	column.add_child(heading)
	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 13)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(_note)
	_rows = VBoxContainer.new()
	column.add_child(_rows)
	game.voices.clips_arrived.connect(_show_clips)
	VoiceChat.local_speaking_changed.connect(_on_talking)


## While the list is open, a phrase you just said shows up once the host has
## closed it (VoiceChat.CLIP_GAP of quiet).
func _on_talking(talking: bool) -> void:
	if not talking and _panel.visible:
		await get_tree().create_timer(VoiceChat.CLIP_GAP + 0.3).timeout
		if _panel.visible:
			game.voices.ask_my_clips()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("my_clips"):
		_open(not _panel.visible)
		get_viewport().set_input_as_handled()
	elif _panel.visible and event.is_action_pressed("ui_cancel"):
		_open(false)
		get_viewport().set_input_as_handled()


func _open(on: bool) -> void:
	_panel.visible = on
	_playback.stop()
	if not game.in_lobby:  # The lobby keeps the mouse free.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	if on:
		_note.text = "Asking the host..."
		game.voices.ask_my_clips()


func _show_clips(clips: Array) -> void:
	for row in _rows.get_children():
		row.queue_free()
	if clips.is_empty():
		_note.text = (
			"Nothing of yours is kept. Only what you say while holding V is kept, only if"
			+ " you ticked consent in the lobby, and not if your mic picked up nothing."
		)
		return
	_note.text = "The creature may call your friends with these. Deleted when the match ends."
	for i in clips.size():
		var data: PackedByteArray = clips[i]
		var row := HBoxContainer.new()
		_rows.add_child(row)
		var label := Label.new()
		label.text = "Phrase %d  (%.1f s)" % [i + 1, data.size() / float(VoiceCodec.RATE)]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		_button(row, "Play", _play.bind(data))
		_button(row, "Delete", game.voices.delete_my_clip.bind(data))
	_button(_rows, "Delete all", game.voices.delete_my_clip.bind(PackedByteArray()))


## As the creature plays it to your friends (VoiceBank.chat_phrase), minus the tell.
func _play(data: PackedByteArray) -> void:
	var samples := VoiceCodec.decode(data)
	_playback.stream = Sfx.from_samples(samples, VoiceCodec.RATE)
	_playback.play()


func _button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE  # Keys keep moving the player.
	button.pressed.connect(action)
	parent.add_child(button)
