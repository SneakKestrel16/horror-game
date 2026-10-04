class_name VoiceBank
extends Node
## Players' recorded lines, kept by the host for the creature to call with
## (Phase 2; design doc, Keeping Players on In-Game Voice and Build Notes).
## Before the day, a player who ticks consent records a short fixed list of
## lines, each a few times with a prompt to sound scared, plus each teammate's
## name. Takes go to the host and live only for this match. A player can keep
## their voice from being replayed to chosen teammates; withdrawing consent
## deletes their takes.
##
## Every peer keeps the names and how many takes each player has recorded, for
## the lobby. Same path ("Voices") on every peer, for its RPCs.

signal changed  ## Names, counts or blocks changed.

const LINES: Array[Dictionary] = [
	{
		"key": "over_here",
		"text": "Over here!",
		"prompt": "Shout it, like you've spotted something."
	},
	{"key": "help_me", "text": "Help me!", "prompt": "Panicked, like something has your leg."},
	{"key": "come_look", "text": "Come look at this.", "prompt": "Quiet and urgent."},
	{"key": "where_are_you", "text": "Where are you?", "prompt": "Scared and out of breath."},
]
const NAME_PROMPT := "Call their name like you need them, now."
const TAKES := 3  ## Takes kept per line; a new one replaces the oldest.
const TAKE_MAX := 3.0  ## Seconds.
const TAKE_MIN := 0.4
## Takes are raised to this peak, as loud as the stock lines; mics record quietly
## (2026-10-04 playtest). The gain is capped so a near-silent take stays quiet
## rather than turning into hiss.
const TAKE_PEAK := 0.9
const TAKE_GAIN_MAX := 16.0
const NAME_CHANCE := 0.5  ## How often it calls the listener's own name when it has it.
## Your own voice is rarely used on you (design doc, How It Works).
const OWN_WEIGHT := 0.05

var names := {}  ## peer -> name.
var counts := {}  ## peer -> takes recorded.

var _takes := {}  ## Host: peer -> {key: Array of PackedByteArray (VoiceCodec)}.
var _blocked := {}  ## Host: peer -> Array of listeners its voice is kept from.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


## The line's words for a key ("name_<peer>" is that teammate's name).
func line_text(key: String) -> String:
	if key.begins_with("name_"):
		return "%s!" % names.get(key.trim_prefix("name_").to_int(), "?")
	for line in LINES:
		if line["key"] == key:
			return line["text"]
	return key


## This peer's lines to record: the fixed list and each teammate's name.
func keys_for(peer: int) -> Array[String]:
	var keys: Array[String] = []
	for line in LINES:
		keys.append(line["key"])
	for other: int in names:
		if other != peer:
			keys.append("name_%d" % other)
	return keys


## samples raised to TAKE_PEAK, by at most TAKE_GAIN_MAX.
static func normalized(samples: PackedFloat32Array) -> PackedFloat32Array:
	var peak := 0.0
	for sample in samples:
		peak = maxf(peak, absf(sample))
	if peak <= 0.0:
		return samples
	var gain := minf(TAKE_PEAK / peak, TAKE_GAIN_MAX)
	var out := samples.duplicate()
	for i in out.size():
		out[i] *= gain
	return out


## Sends one recorded take to the host.
func upload(key: String, samples: PackedFloat32Array) -> void:
	_receive_take.rpc_id(1, key, VoiceCodec.encode(samples))


## Deletes this player's takes on the host (consent withdrawn).
func withdraw() -> void:
	_receive_withdraw.rpc_id(1)


## Keeps this player's voice from being replayed to these listeners.
func block(listeners: Array[int]) -> void:
	_receive_block.rpc_id(1, listeners)


## Host only: a player's name, told to everyone.
func register(peer: int, player_name: String) -> void:
	_set_name.rpc(peer, player_name)
	_set_count.rpc(peer, counts.get(peer, 0))


## Host only: sends everything known to a peer that just joined.
func welcome(peer: int) -> void:
	for other: int in names:
		_set_name.rpc_id(peer, other, names[other])
		_set_count.rpc_id(peer, other, counts.get(other, 0))


## Host only: forgets a player who left.
func forget(peer: int) -> void:
	_takes.erase(peer)
	_blocked.erase(peer)
	_set_name.rpc(peer, "")


## Host only: which recorded take the creature plays to listener, as
## {source, key, data}, or {} for a generic line. Picks a speaker (rarely the
## listener), then the listener's name half the time if that speaker said it.
func pick(listener: int) -> Dictionary:
	var speakers: Array[int] = []
	var weights: Array[float] = []
	var total := 0.0
	for peer: int in _takes:
		if listener in _blocked.get(peer, []) or _usable_keys(peer, listener).is_empty():
			continue
		var weight := OWN_WEIGHT if peer == listener else 1.0
		speakers.append(peer)
		weights.append(weight)
		total += weight
	if speakers.is_empty():
		return {}
	var roll := _rng.randf() * total
	var source := speakers[-1]
	for i in speakers.size():
		roll -= weights[i]
		if roll <= 0.0:
			source = speakers[i]
			break
	var keys := _usable_keys(source, listener)
	var name_key := "name_%d" % listener
	var key: String = keys[_rng.randi() % keys.size()]
	if name_key in keys and _rng.randf() < NAME_CHANCE:
		key = name_key
	var takes: Array = _takes[source][key]
	return {"source": source, "key": key, "data": takes[_rng.randi() % takes.size()]}


## Generic lines source has recorded, plus listener's name if it said it.
func _usable_keys(source: int, listener: int) -> Array[String]:
	var keys: Array[String] = []
	for key: String in _takes.get(source, {}):
		if not key.begins_with("name_") or key == "name_%d" % listener:
			keys.append(key)
	return keys


@rpc("any_peer", "call_local", "reliable")
func _receive_take(key: String, data: PackedByteArray) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or key not in keys_for(peer):
		return
	if data.size() > TAKE_MAX * VoiceCodec.RATE * 1.2:
		return
	var lines: Dictionary = _takes.get_or_add(peer, {})
	var takes: Array = lines.get_or_add(key, [])
	takes.append(data)
	while takes.size() > TAKES:
		takes.pop_front()
	var total := 0
	for line: String in lines:
		total += (lines[line] as Array).size()
	_set_count.rpc(peer, total)


@rpc("any_peer", "call_local", "reliable")
func _receive_withdraw() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if multiplayer.is_server():
		_takes.erase(peer)
		_set_count.rpc(peer, 0)


@rpc("any_peer", "call_local", "reliable")
func _receive_block(listeners: Array) -> void:
	if multiplayer.is_server():
		_blocked[multiplayer.get_remote_sender_id()] = listeners


@rpc("authority", "call_local", "reliable")
func _set_name(peer: int, player_name: String) -> void:
	if player_name == "":
		names.erase(peer)
		counts.erase(peer)
	else:
		names[peer] = player_name
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _set_count(peer: int, count: int) -> void:
	counts[peer] = count
	changed.emit()
