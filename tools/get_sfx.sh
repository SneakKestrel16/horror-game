#!/usr/bin/env bash
# Copies the recorded sound effects the game uses out of the FilmCow Recorded
# SFX zip (https://filmcow.itch.io/filmcow-sfx) into game/assets/sfx, which git
# ignores. Without them the game plays its synthesised stand-ins (Sfx).
#
#   tools/get_sfx.sh "path/to/FilmCow Recorded SFX.zip"
set -euo pipefail
zip="${1:?usage: tools/get_sfx.sh <FilmCow Recorded SFX.zip>}"
out="$(dirname "$0")/../game/assets/sfx"
mkdir -p "$out"
# The name prefixes Sfx.RECORDED asks for.
for name in "footstep dirt" "footstep grass and leaves" "bushes" "water splashing small" "metal hits metal" \
	"metal latches" "body fall" "ventilation hum"; do
	unzip -q -o -j "$zip" "FilmCow Recorded SFX/$name*" -d "$out"
done
ls "$out" | wc -l | xargs echo "sound files in $out:"
