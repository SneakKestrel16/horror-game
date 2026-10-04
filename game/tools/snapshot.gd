extends Node
## Hosts a game, sets the clock, looks from a point and saves a PNG, so the
## farm can be checked without playing. Opens a window briefly:
##   godot --path game res://tools/snapshot.tscn -- --clock=430 --from=0,1.6,-3
##       --look=0,1,20 --out=shot.png [--creature=0,0,8] [--dev --panel] [--lobby] [--board=2]
## --clock is seconds into the day (day 0-360, dusk -420, night -720).

var _game: Game


func _ready() -> void:
	var clock := 30.0
	var from := Vector3(0, 1.6, -3)
	var look := Vector3(0, 1, 20)
	var out := "snapshot.png"
	var creature := Vector3.INF
	for arg in OS.get_cmdline_user_args():
		var value := arg.get_slice("=", 1)
		if arg.begins_with("--clock="):
			clock = value.to_float()
		elif arg.begins_with("--from="):
			from = _vector(value)
		elif arg.begins_with("--look="):
			look = _vector(value)
		elif arg.begins_with("--creature="):
			creature = _vector(value)
		elif arg.begins_with("--out="):
			out = value
	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate() as Game
	get_tree().root.add_child.call_deferred(_game)
	for i in 10:
		await get_tree().physics_frame
	for arg in OS.get_cmdline_user_args():  # --board=N: that many traps on the pegboard.
		if arg.begins_with("--board="):
			_game.traps.set_board(arg.trim_prefix("--board=").to_int())
	if "--lobby" not in OS.get_cmdline_user_args():  # --lobby: leave the lobby screen up.
		_game.start_day()
	_game.clock = clock
	var player := _game.local_player()
	player.set_physics_process(false)
	player.global_position = Vector3(from.x, from.y - Player.EYE_HEIGHT, from.z)
	player.look_at(Vector3(look.x, 0, look.z))
	player.pitch = atan2(look.y - from.y, Vector2(look.x - from.x, look.z - from.z).length())
	player.lantern = clock > 360.0
	if creature.is_finite():
		_game.creature.set_physics_process(false)
		_game.creature.global_position = creature
		_game.creature.look_at(Vector3(from.x, 0, from.z))
	if "--panel" in OS.get_cmdline_user_args():  # With --dev: show the developer panel.
		for dev in _game.find_children("*", "CanvasLayer", false, false):
			if dev is Dev:
				dev.call("_show", true)
	for i in 30:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	image.save_png(out)
	print("saved %s" % out)
	get_tree().quit()


static func _vector(text: String) -> Vector3:
	var parts := text.split(",")
	return Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
