extends Node
## Two-process network test (no microphone needed).
## Host:   godot --headless --path . res://tests/net_test.tscn -- host
## Client: godot --headless --path . res://tests/net_test.tscn -- client

const PORT := 24599
var _role := ""
var _mimic: VoiceMimic
var _client_id := 0
var _results := {}


func _ready() -> void:
	_role = "host" if OS.get_cmdline_user_args().has("host") else "client"
	_mimic = VoiceMimic.new()
	_mimic.name = "Mimic"
	add_child(_mimic)
	var peer := ENetMultiplayerPeer.new()
	if _role == "host":
		peer.create_server(PORT, 4)
		multiplayer.multiplayer_peer = peer
		multiplayer.peer_connected.connect(func(id): _client_id = id)
		_run_host()
	else:
		peer.create_client("127.0.0.1", PORT)
		multiplayer.multiplayer_peer = peer
		multiplayer.connected_to_server.connect(_run_client)
	get_tree().create_timer(15.0).timeout.connect(func(): _finish(false, "timeout"))


func _run_host() -> void:
	VoiceChat.set_recording_consent(false)
	while _client_id == 0:
		await get_tree().process_frame
	# Wait for the client's consent and voice packets, then for the clip to close.
	await get_tree().create_timer(3.0).timeout
	var clips := VoiceChat.get_clips(_client_id)
	_results["clip_saved"] = clips.size() >= 1
	_results["host_not_saved_without_consent"] = VoiceChat.get_clips(1).is_empty()
	_results["client_consent_seen"] = VoiceChat.has_consent(_client_id)
	VoiceChat.set_peer_dead(_client_id, true)
	var heard := []
	_mimic.mimicked.connect(func(listener, source): heard.append([listener, source]))
	_mimic.mimic()
	_results["mimic_sent"] = heard.size() == 2
	await get_tree().create_timer(2.0).timeout
	_finish(_results.values().all(func(v): return v), str(_results))


func _run_client() -> void:
	VoiceChat.set_recording_consent(true)
	await get_tree().create_timer(0.5).timeout
	# One second of a 300 Hz tone, sent as 50 packets of 20 ms.
	for p in 50:
		var chunk := PackedFloat32Array()
		for i in VoiceChat.PACKET_SAMPLES:
			var n := p * VoiceChat.PACKET_SAMPLES + i
			chunk.append(0.4 * sin(TAU * 300.0 * n / VoiceCodec.RATE))
		VoiceChat._receive_voice.rpc(VoiceCodec.encode(chunk))
		await get_tree().create_timer(0.02).timeout
	var my_id := multiplayer.get_unique_id()
	while not VoiceChat.is_dead(my_id):
		await get_tree().process_frame
	_results["dead_flag_received"] = true
	var waited := 0.0
	while not _mimic.playing and waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	_results["mimic_clip_played"] = _mimic.playing
	_finish(_results.values().all(func(v): return v), str(_results))


func _finish(ok: bool, detail: String) -> void:
	print("%s %s %s" % [_role.to_upper(), "PASS" if ok else "FAIL", detail])
	get_tree().quit(0 if ok else 1)
