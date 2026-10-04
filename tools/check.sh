#!/usr/bin/env bash
# Imports the game project headless, then runs game/tests/smoke.tscn. Fails on a
# non-zero exit or on any ERROR/WARNING/SCRIPT ERROR line, because Godot prints
# most script problems and keeps going with exit code 0.
set -u
cd "$(dirname "$0")/../game"
godot="${GODOT:-$(command -v godot_console || true)}"
if [ -z "$godot" ]; then
	# winget's install location; set GODOT to override.
	godot=$(ls "$LOCALAPPDATA"/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_*/Godot_v4*_console.exe 2>/dev/null | tail -1)
fi
[ -x "$godot" ] || { echo "Godot console executable not found; set GODOT." >&2; exit 1; }

log=$(mktemp)
trap 'rm -f "$log"' EXIT
"$godot" --headless --import >"$log" 2>&1
status=$?
# Its own port, so a running game does not block it. --quit-after caps the run
# (in frames) so a broken test fails instead of hanging.
# timeout too: a script that fails to compile leaves the test waiting forever.
timeout 240 "$godot" --headless --quit-after 400000 res://tests/smoke.tscn -- --port=7791 >>"$log" 2>&1 || status=$?
cat "$log"
if grep -Eq '(^|[^A-Z_])(ERROR|WARNING):' "$log"; then
	echo "check.sh: Godot reported errors or warnings (treated as failures)." >&2
	exit 1
fi
grep -q 'SMOKE PASS' "$log" || { echo "check.sh: smoke test did not pass." >&2; exit 1; }
exit "$status"
