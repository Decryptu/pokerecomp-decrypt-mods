#!/usr/bin/env bash
# Photographs one PLACE both ways at once: the map's own 2D art, ruled and
# numbered, beside the same map as this mod builds it.
#
# The two pictures are only useful together, and only at bearing 0. `map_art.gd`
# rings a rectangle, which is how a question about a drawing is asked; the
# numbered art is the other direction, a picture a reader can name any tile on.
# The numbering is worth nothing beside a shot taken from anywhere but due
# south, which is the one bearing whose columns line up with the art.
#
# So the three settings that hold the pair together are not arguments here: the
# art at scale 1, so the ruling can find its tiles, the same zoom on both
# pictures of a round, and bearing 0. Set by hand they are three chances to send
# a pair nobody can read against each other, and each of the three has been got
# wrong that way.
#
#   tools/place.sh <group> <number> <out dir> [tile x] [tile y] [pitch] [back]
#
# The aim defaults to the middle of the map and the arm to something that holds
# a town. Everything the two underlying tools take that is not on that line is
# deliberate rather than missing: `map_art.gd` rings a rectangle and `shot.gd`
# takes an hour, a hold and a bearing, and either is the right tool the moment
# the question is narrower than a place.
#
# The cartridge cache is $CACHE, else the Crystal one every tool here defaults
# to. The pokerecomp checkout is $POKERECOMP, else the read-only one in
# `.references`; the Godot binary is $GODOT, else where the macOS installer puts
# it. Rendering needs a display, so this cannot run headless.

set -u
if [ "$#" -lt 3 ]; then
	sed -n "2,28p" "$0" | cut -c 3-
	exit 2
fi
GROUP="$1"
NUMBER="$2"
OUT="$3"
AIM_X="${4:-}"
AIM_Y="${5:-}"
PITCH="${6:-40}"
BACK="${7:-900}"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${POKERECOMP:-$HERE/.references/pokerecomp}"
if [ ! -d "$HOST" ]; then
	echo "no pokerecomp checkout at $HOST; set POKERECOMP" >&2
	exit 2
fi
CACHE="${CACHE:-user://rom_cache/crystal_f2f52230}"
for candidate in "${GODOT:-godot}" \
		/Applications/Godot.app/Contents/MacOS/Godot \
		"$HOME/Applications/Godot.app/Contents/MacOS/Godot"; do
	GODOT=""
	if command -v "$candidate" > /dev/null 2>&1; then
		GODOT="$candidate"
		break
	fi
done
if [ -z "$GODOT" ]; then
	echo "no Godot found; set GODOT to the binary" >&2
	exit 2
fi

mkdir -p "$OUT"
NAME="map${GROUP}_${NUMBER}"
ART="$OUT/$NAME.art.png"
GRID="$OUT/$NAME.grid.png"
SHOT="$OUT/$NAME.3d.png"

# Scale 1, because `map_grid.py` rules the art in TILES and needs one pixel per
# world pixel to find them.
"$GODOT" --headless --path "$HOST" -s "$HERE/tools/map_art.gd" -- \
	"$CACHE" "$GROUP" "$NUMBER" "$ART" 1 || exit 1
python3 "$HERE/tools/map_grid.py" "$ART" "$GRID" 4 \
	--title "map $GROUP,$NUMBER" || exit 1

# The middle of the map, in tiles, off the art the first tool just wrote: the
# map's own size is the one number neither tool takes on its command line.
if [ -z "$AIM_X" ] || [ -z "$AIM_Y" ]; then
	read -r AIM_X AIM_Y <<< "$(python3 -c '
import sys
from PIL import Image
w, h = Image.open(sys.argv[1]).size
print(w // 16, h // 16)' "$ART")"
fi

# Bearing 0 is the whole point: see the note at the top. The old picture goes
# first, or a render that failed leaves the last one standing and the check
# below passes on a shot of somewhere else.
rm -f "$SHOT"
"$GODOT" --path "$HOST" -s "$HERE/tools/shot.gd" -- \
	"$CACHE" "$GROUP" "$NUMBER" "$AIM_X" "$AIM_Y" "$SHOT" \
	"$PITCH" "$BACK" 1 "" 8 0 > /dev/null 2>&1
[ -e "$SHOT" ] || { echo "no shot written; is there a display?" >&2; exit 1; }

echo "$GRID"
echo "$SHOT  aimed at tile $AIM_X,$AIM_Y"
