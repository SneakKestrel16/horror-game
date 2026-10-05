class_name Hud
extends CanvasLayer
## The on-screen text: phase and time left, coins, fuel, what you carry and
## how you are, the use prompt, passing messages, and the dawn summary.

var _status: Label
var _info: Label
var _prompt: Label
var _message: Label
var _message_left := 0.0
var _overlay: Label


func _ready() -> void:
	_status = _label(Vector2(24, 18), 26)
	_info = _label(Vector2(24, 60), 20)

	var crosshair := Label.new()
	crosshair.text = "·"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.add_theme_font_size_override("font_size", 32)
	add_child(crosshair)

	_message = _centred(Control.PRESET_CENTER_TOP, 30)
	_message.position.y = 110
	_message.visible = false
	_prompt = _centred(Control.PRESET_CENTER, 22)
	_prompt.position.y += 40

	var hint := _centred(Control.PRESET_CENTER_BOTTOM, 16)
	hint.text = (
		"E use (hold for traps) · G drop · F lantern · V talk · Shift sprint · Ctrl crouch"
		+ " · C your voice · B store · Esc mouse / leave"
	)
	hint.position.y -= 40
	hint.modulate = Color(1, 1, 1, 0.5)

	_overlay = _centred(Control.PRESET_FULL_RECT, 30)
	_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var shade := StyleBoxFlat.new()
	shade.bg_color = Color(0, 0, 0, 0.8)
	_overlay.add_theme_stylebox_override("normal", shade)
	_overlay.visible = false


func _process(delta: float) -> void:
	_message_left -= delta
	_message.visible = _message_left > 0.0


## Shows text in the middle of the screen for a few seconds.
func flash(text: String, seconds := 4.0) -> void:
	_message.text = text
	_message_left = seconds


## The hint under the crosshair ("" hides it).
func prompt(text: String) -> void:
	_prompt.text = text


## The dawn summary over everything, or "" to take it away.
func summary(text: String) -> void:
	_overlay.text = text
	_overlay.visible = text != ""


func update(game: Game) -> void:
	var left := game.phase_left()
	var phase := game.phase().to_upper()
	_status.text = (
		"DAY %d · %s · %d:%02d left"
		% [game.day_number(), phase, floori(left / 60.0), floori(fmod(left, 60.0))]
	)
	if game.phase() == "lobby":
		_status.text = "LOBBY"
	if VoiceChat.is_local_speaking():
		_status.text += "   (talking)"
	var player := game.local_player()
	var lines: Array[String] = ["Coins: %d" % game.coins]
	if game.phase() != "day" or game.fuel < 0.3:
		var out := "" if game.fuel > 0.0 else " (OUT)"
		lines.append("Generator: %d%%%s" % [roundi(game.fuel * 100), out])
	if player:
		var held := game.chores.held_item(player.get_multiplayer_authority())
		if not held.is_empty():
			var extra := ""
			if held["kind"] == "watering_can":
				extra = " (%d/%d)" % [held["charge"], Chores.CAN_WATER]
			elif held["kind"] == "fuel_can":
				extra = " (full)" if held["charge"] > 0 else " (empty)"
			lines.append("Carrying: %s%s" % [Chores.ITEM_NAMES[held["kind"]], extra])
		if player.stamina < Player.STAMINA:
			var bars := roundi(player.stamina / Player.STAMINA * 10.0)
			lines.append("Stamina: %s" % "|".repeat(bars))
		if player.pinned:
			lines.append("TRAPPED")
		elif player.slowed_left > 0.0:
			lines.append("Limping: %ds" % ceili(player.slowed_left))
		if player.dead:
			lines.append("DEAD until dawn")
		elif player.wounded:
			lines.append("Hurt until dawn: short of breath, loud on your feet, easy to track")
	_info.text = "\n".join(lines)


func _label(at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)
	return label


func _centred(preset: Control.LayoutPreset, font_size: int) -> Label:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(preset)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)
	return label
