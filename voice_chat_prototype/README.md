# Voice Chat for Godot 4

Proximity voice chat for the farming horror game, with voice clips saved for the creature to mimic. Written in plain GDScript with no plugins. Tested with Godot 4.7.2.

## What it does

- **Proximity voice:** each player's voice plays from their character and fades with distance (30 m by default).
- **Push-to-talk or voice activation:** hold **V** by default, or switch to automatic.
- **Dead players through static:** living players hear dead teammates as crackly radio.
- **Creature mimicry:** the host saves short clips of each player's speech (only with their consent). The creature can replay them, favoring dead players and rarely using a listener's own voice. Copies have a faint echo as a tell.
- **Consent built in:** nobody's voice is saved unless they tick "Let the creature copy my voice." Clips live only in memory and are cleared with `VoiceChat.clear_clips()`.

## Try the test scene

1. Open this folder in Godot 4.7 (Import > select `project.godot`).
2. Go to **Debug > Customize Run Instances**, enable multiple instances and set it to 2.
3. Press Play. In one window click **Host**, in the other click **Join**.
4. Move with **WASD**, hold **V** to talk. Walk away from the other player to hear the voice fade.
5. Tick the consent box, talk a few sentences, then click **Creature: speak** in the host window.
6. Click **Kill me** to hear your voice through static in the other window.

Use headphones. With two windows on one PC sharing one mic you'll hear yourself, which is expected.

On Windows, make sure apps are allowed to use the microphone in privacy settings, or capture returns silence.

## Using it in your game

1. Copy the `addons/voice_chat` folder into your project.
2. **Project Settings > Audio > Driver > Enable Input:** on.
3. **Project Settings > Autoload:** add `res://addons/voice_chat/voice_chat.gd` named `VoiceChat`.
4. On every **remote** player's character, add a `VoiceSpeaker` node and set `peer_id` to that player's network id.
5. Give your **local** player an `AudioListener3D` and call `make_current()`, so distance is measured from the character rather than the camera.
6. Add a `VoiceMimic` node to the creature. The creature must have the same node path on every player's game (for example spawned by a `MultiplayerSpawner`).

### Main calls

| Call | Where | What it does |
|---|---|---|
| `VoiceChat.set_recording_consent(true/false)` | each player | Allow or stop the creature copying your voice |
| `VoiceChat.mode = VoiceChat.Mode.VOICE_ACTIVATION` | each player | Switch from push-to-talk |
| `VoiceChat.mic_muted = true` | each player | Mute the mic |
| `VoiceChat.set_peer_dead(id, true)` | host | Mark a player dead (static on) or alive |
| `VoiceChat.clear_clips()` | host | Delete saved clips, e.g. at the end of a match |
| `$Creature/VoiceMimic.mimic()` | host | Creature speaks with a stolen voice |

`VoiceMimic` settings: `dead_weight`, `living_weight`, `own_voice_weight` control which voices get picked, and `fallback_lines` holds generic recordings used when no clips exist. Its `mimicked(listener_id, source_id)` signal tells the creature's AI who heard what, useful for steering lures toward traps.

## Tests

- Codec: `godot --headless --path . -s res://tests/test_codec.gd`
- Network (two terminals): `godot --headless --path . res://tests/net_test.tscn -- host`, then the same with `-- client`

## Known limits

- **Bandwidth:** about 16 KB/s per talking player. Fine for 4 players, but a compressed format such as Opus (via a plugin) would cut this a lot later.
- **No echo cancellation or noise suppression:** recommend headphones.
- **Direct IP only:** the test scene connects by IP address. Playing over the internet needs port forwarding or a service such as Steam networking.
- **Simple resampling:** good enough for voice, not for music.
