class_name StorePanel
extends CanvasLayer
## The store's window (Store): B by the shipping crate shows or hides it, Esc
## or walking away hides it. Seed packs and upgrades, each with its price and
## a Buy button that stays greyed out while the team can't afford it, or once
## an upgrade is bought.

var game: Game

var _panel: PanelContainer
var _coins: Label
var _buttons := {}  ## Seed or upgrade id -> its Buy button.
var _refresh_left := 0.0


func _init(owner_game: Game) -> void:
	game = owner_game


func _ready() -> void:
	layer = 9
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(-260, -260)
	_panel.custom_minimum_size = Vector2(520, 0)
	_panel.visible = false
	add_child(_panel)
	var column := VBoxContainer.new()
	_panel.add_child(column)
	_heading(column, "FARM STORE  (B)", 18)
	_coins = Label.new()
	column.add_child(_coins)
	_heading(column, "Seeds: plant them in bare plots, then water", 15)
	for id: String in Store.SEEDS:
		var crop: String = Store.SEEDS[id][0]
		var detail := (
			"%d plots. Sells for %d a plot%s."
			% [
				Store.SEEDS_PER_PACK[id],
				Chores.PRICES[crop],
				", grows only at night, wilts at dawn" if crop in Chores.NIGHT_CROPS else ""
			]
		)
		_row(column, id, Store.SEEDS[id][2], detail)
	_heading(column, "Upgrades: for the whole team, for the rest of the run", 15)
	for id: String in Store.UPGRADES:
		_row(column, id, Store.UPGRADES[id][1], Store.UPGRADES[id][2])


func _process(delta: float) -> void:
	if not _panel.visible:
		return
	if not game.store.open_for(game.local_player()):
		_open(false)
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.25
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("store"):
		if _panel.visible:
			_open(false)
		elif game.store.open_for(game.local_player()):
			_open(true)
		elif not game.in_lobby and game.local_player():
			game.flash("The store is at the shipping crate, by day.", 2.5)
		get_viewport().set_input_as_handled()
	elif _panel.visible and event.is_action_pressed("ui_cancel"):
		_open(false)
		get_viewport().set_input_as_handled()


func _open(on: bool) -> void:
	_panel.visible = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	if on:
		_refresh()


func _refresh() -> void:
	_coins.text = "Coins: %d" % game.coins
	for id: String in _buttons:
		var button: Button = _buttons[id]
		var owned := game.store.owned.has(id)
		button.text = "Owned" if owned else "Buy %d" % Store.price(id)
		button.disabled = owned or game.coins < Store.price(id)


func _row(parent: Control, id: String, title: String, detail: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var name_label := Label.new()
	name_label.text = title
	text.add_child(name_label)
	var detail_label := Label.new()
	detail_label.text = detail
	detail_label.add_theme_font_size_override("font_size", 12)
	detail_label.modulate = Color(1, 1, 1, 0.7)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	text.add_child(detail_label)
	var button := Button.new()
	button.custom_minimum_size = Vector2(90, 0)
	button.focus_mode = Control.FOCUS_NONE  # Keys keep moving the player.
	button.pressed.connect(func() -> void: game.store.buy(id))
	row.add_child(button)
	_buttons[id] = button


func _heading(parent: Control, text: String, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.modulate = Color(1.0, 0.85, 0.45)
	parent.add_child(label)
