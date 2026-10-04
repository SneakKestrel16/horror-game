# Horror Game: notes for Claude

- The design doc is `docs/Farming_Horror_Game_Concept.md`. Read it before designing or building anything. Keep it updated when design decisions change, and remove ideas that are no longer used rather than leaving them in.
- Engine: Godot 4.7, GDScript.
- Build in the order of the doc's Build Plan. Only move to the next phase once the current one is fun to play and the review between them is done (new problems added to Open Issues, the ones the next phase depends on settled). Phase 1 uses scripted trap spots and simple timers instead of smart AI.
- `voice_chat_prototype/` is a separate test project. When the game needs voice chat (Phase 2), copy `addons/voice_chat` into the game project rather than building on the test scene.
- The game is the Godot project in `game/`; `docs/README.md` indexes the docs, and `docs/phase1.md` describes the prototype. Record traps in `docs/gotchas.md`.
- Model: the host owns the clock, tools, crops, traps, generator and creature; each peer owns only its player and asks the host to act (`Game._request`).
- Set up tools: `uv venv --python 3.13.16 .venv` then `uv pip install --python .venv/Scripts/python.exe -r tools/requirements.txt`, then `prek install`.
- `bash tools/check.sh` imports `game/` headless and runs `game/tests/smoke.tscn`; `prek run --all-files` (from Git Bash) runs it with gdformat and gdlint. Warnings are errors.
- See it without playing: `godot --path game res://tools/snapshot.tscn -- --clock=N --from=x,y,z --look=x,y,z --out=<png>`.
- The owner prefers accuracy over speed: verify engine features, API names and other facts against the Godot docs before relying on them.
