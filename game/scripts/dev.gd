class_name Dev
extends CanvasLayer
## Developer panel, for playtesting without playing a whole day. Speed up the
## clock or jump to any phase; make the creature call, lure, chase, come over
## or back off; fill or drain the generator; arm or clear the traps; ripen the
## field; die and come back.
##
## Only with `-- --dev`, and only on the host, which owns everything it changes.
## F2 shows or hides it and frees the mouse; Esc hides it. Later phases add
## their triggers (jumpscares, recorded voices, marks...) under "Events".

const SPEEDS: Array[float] = [1.0, 2.0, 5.0, 10.0, 30.0]

var game: Game  ## Set before this is added.

var _panel: PanelContainer
var _status: Label
var _status_left := 0.0


func _ready() -> void:
	layer = 10
	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 110)
	_panel.visible = false
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(340, 700)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	_heading(column, "DEVELOPER PANEL  (F2)")
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(_status)

	_heading(column, "Time")
	var speeds := HBoxContainer.new()
	column.add_child(speeds)
	for speed in SPEEDS:
		_button(speeds, "x%d" % speed, _set_speed.bind(speed))
	var phases := HBoxContainer.new()
	column.add_child(phases)
	for target: String in ["day", "dusk", "night", "dawn"]:
		_button(phases, target.capitalize(), func() -> void: game.jump_to(target))
	_button(column, "Skip to the next phase", func() -> void: game.skip_phase())

	_heading(column, "Creature")
	_button(column, "Call out now (a voice line from where it is)", _call_now)
	_button(
		column,
		"Lure me (pick a spot round me and call)",
		func() -> void: _creature().lure_now(_me())
	)
	_button(column, "Chase me (night only)", func() -> void: _creature().chase(_me()))
	_button(column, "Bring it 15 m behind me", _bring)
	_button(column, "Drive it off into the corn", func() -> void: _creature().drive_off())
	_toggle(column, "Freeze it", func(on: bool) -> void: _creature().set_physics_process(not on))

	_heading(column, "Events")
	var later := Label.new()
	later.text = "Jumpscares, recorded voices and marks arrive in later phases."
	later.add_theme_font_size_override("font_size", 12)
	later.modulate = Color(1, 1, 1, 0.6)
	later.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(later)

	_heading(column, "Farm")
	var fuel := HBoxContainer.new()
	column.add_child(fuel)
	_button(fuel, "Fuel full", func() -> void: game.set_fuel(1.0))
	_button(fuel, "Fuel 10%", func() -> void: game.set_fuel(0.1))
	_button(fuel, "Fuel empty", func() -> void: game.set_fuel(0.0))
	var traps := HBoxContainer.new()
	column.add_child(traps)
	_button(traps, "Arm all traps", func() -> void: game.set_all_traps(true))
	_button(traps, "Clear all traps", func() -> void: game.set_all_traps(false))
	_button(column, "Ripen every plot", func() -> void: game.ripen_all())

	_heading(column, "Me")
	_button(column, "Die", _die)
	_button(column, "Come back to life", func() -> void: game.revive(_me()))
	_button(column, "Teleport to the barn", func() -> void: _teleport(Farm.SPAWN))


func _process(delta: float) -> void:
	_status_left -= delta
	if not _panel.visible or _status_left > 0.0:
		return
	_status_left = 0.25
	var me := _me()
	var creature := _creature()
	if me == null or creature == null:
		return
	_status.text = (
		"%s · %d:%02d left · time x%d · %d fps\nfuel %d%% · coins %d\ncreature: %s, %.0f m away%s"
		% [
			game.phase(),
			floori(game.phase_left() / 60.0),
			floori(fmod(game.phase_left(), 60.0)),
			game.clock_rate,
			Engine.get_frames_per_second(),
			roundi(game.fuel * 100),
			game.coins,
			creature.state_name(),
			creature.global_position.distance_to(me.global_position),
			" (in the corn)" if Farm.in_corn(creature.global_position) else "",
		]
	)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_F2:
		_show(not _panel.visible)
		get_viewport().set_input_as_handled()
	elif _panel.visible and event.is_action_pressed("ui_cancel"):
		_show(false)
		get_viewport().set_input_as_handled()


func _show(on: bool) -> void:
	_panel.visible = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	_status_left = 0.0


func _me() -> Player:
	return game.local_player()


func _creature() -> Creature:
	return game.creature


func _set_speed(speed: float) -> void:
	game.clock_rate = speed
	game.sync_state()
	game.log_event("dev: time x%d" % speed)


func _call_now() -> void:
	_creature().speak_now()


## Puts the creature behind the player, out of view; it lurks from there.
func _bring() -> void:
	var me := _me()
	var behind := me.global_position - me.look_direction() * Vector3(15, 0, 15)
	_creature().place(behind)


func _die() -> void:
	var me := _me()
	if not me.dead:
		me.killed.rpc_id(me.get_multiplayer_authority())
		game.log_event("dev: %s died" % me.label())


func _teleport(at: Vector3) -> void:
	var me := _me()
	me.global_position = Vector3(at.x, 0.05, at.z)
	me.velocity = Vector3.ZERO


func _heading(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.modulate = Color(1.0, 0.85, 0.45)
	parent.add_child(label)


func _button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE  # Keys keep moving the player.
	button.pressed.connect(action)
	parent.add_child(button)


func _toggle(parent: Control, text: String, action: Callable) -> void:
	var box := CheckBox.new()
	box.text = text
	box.focus_mode = Control.FOCUS_NONE
	box.toggled.connect(action)
	parent.add_child(box)
