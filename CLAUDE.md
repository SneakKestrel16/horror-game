# Horror Game: notes for Claude

- The design doc is `docs/Farming_Horror_Game_Concept.md`. Read it before designing or building anything. Keep it updated when design decisions change, and remove ideas that are no longer used rather than leaving them in.
- Engine: Godot 4.7, GDScript.
- Build in the order of the doc's Build Plan. Only move to the next phase once the current one is fun to play. Phase 1 uses scripted trap spots and simple timers instead of smart AI.
- `voice_chat_prototype/` is a separate test project. When the game needs voice chat (Phase 2), copy `addons/voice_chat` into the game project rather than building on the test scene.
- The owner prefers accuracy over speed: verify engine features, API names and other facts against the Godot docs before relying on them.
