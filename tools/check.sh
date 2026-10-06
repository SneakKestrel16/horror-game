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

# The full log is long (about 600 lines); it is printed only with CHECK_VERBOSE=1.
# Otherwise a pass prints one line and a failure prints the problem lines and the
# log's tail, and the log is kept at CHECK_LOG for a closer look.
log="${CHECK_LOG:-$(mktemp)}"
"$godot" --headless --import >"$log" 2>&1
status=$?
# Its own port, so a running game does not block it (SMOKE_PORT gives parallel
# checks, such as agents in separate worktrees, a port each). --quit-after caps the run
# (in frames) so a broken test fails instead of hanging.
# timeout too: a script that fails to compile leaves the test waiting forever.
timeout 240 "$godot" --headless --quit-after 400000 res://tests/smoke.tscn -- --port="${SMOKE_PORT:-7791}" >>"$log" 2>&1 || status=$?
[ -n "${CHECK_VERBOSE:-}" ] && cat "$log"
fail() {
	[ -z "${CHECK_VERBOSE:-}" ] && {
		grep -E -A2 '(^|[^A-Z_])(ERROR|WARNING):|SCRIPT ERROR|^FAIL' "$log" | head -60
		echo "--- last lines ---"
		tail -15 "$log"
	}
	echo "check.sh: $1 Full log: $log" >&2
	exit 1
}
if grep -Eq '(^|[^A-Z_])(ERROR|WARNING):' "$log"; then
	fail "Godot reported errors or warnings (treated as failures)."
fi
grep -q 'SMOKE PASS' "$log" || fail "smoke test did not pass."
[ "$status" -eq 0 ] || fail "Godot exited with $status."
echo "check.sh: SMOKE PASS, no errors or warnings ($(grep -c '^ok ' "$log") checks)."
[ -z "${CHECK_LOG:-}" ] && rm -f "$log"
exit 0
