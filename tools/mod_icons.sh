#!/bin/sh
# Paints icons from a cartridge.
# Usage: sh tools/mod_icons.sh <out directory> [cache] [scale]
# Native 32x32 icons ship; scaled copies are for review.
set -e

OUT=${1:?usage: mod_icons.sh <out directory> [cache] [scale]}
CACHE=${2:-user://rom_cache/crystal_f2f52230}
SCALE=${3:-6}
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
POKERECOMP=${POKERECOMP:?set POKERECOMP to the game project directory}

HERE=$(cd "$(dirname "$0")/.." && pwd)
export ICON_ART_DIR="$HERE/tools/icon_art"
mkdir -p "$OUT"

# The border every icon wears. Style 0 is the game's own default text box.
FRAME=frame:0

paint() {
	name=$1
	shift
	"$GODOT" --headless --path "$POKERECOMP" -s "$HERE/tools/icon_art.gd" -- \
		"$CACHE" "$OUT/$name.png" "$FRAME" "$@" --scale 1 >/dev/null
	if [ "$SCALE" -gt 1 ]; then
		"$GODOT" --headless --path "$POKERECOMP" -s "$HERE/tools/icon_art.gd" -- \
			"$CACHE" "$OUT/$name@${SCALE}x.png" "$FRAME" "$@" --scale "$SCALE" >/dev/null
	fi
	echo "$name"
}

paint voxel3d art:cube_wire
paint follower "species:25@6,12" "effect:heart@13,3"
paint hidden_stats "text:DV"
paint linking_cord art:cord
paint randomizer effect:question
paint overworld_encounters "world:1:12:4,4,4,4:2" "species:19@8,6"
paint quality_of_life effect:happy
# One bold sparkle out of the battle animations' own SHINE sheet, with the
# smaller twinkles trailing off it.
paint shiny_charm "anim:17:0@13,9" "anim:15:0@8,16"
# The item ball off the ground, three of them climbing: one catch after another
# and each one worth more than the last.
paint catch_combo "sprite:84@2,11" "sprite:84@8,7" "sprite:84@14,3"
# The ZEPHYRBADGE off the trainer card's own badge sheet, four tiles of it. A
# badge is what this cartridge already means by an achievement.
paint achievements "tiles:card_badges:0,1,2,3:2"
