#!/usr/bin/env bash
# ONE 3D FRAME OF EACH OF MANY MAPS, into a directory, for a reviewer to pick
# the worst one out of.
#
# This is how a survey round starts. `tools/shot.gd` photographs ONE place and
# is what every close reading uses; the round before it is the opposite job, a
# wide shot of a dozen maps at once, sent as a pack so a person can say "that
# one" without reading anything. Doing that by hand is a shell loop rewritten
# every round, and the aim point is the one thing easy to get wrong: it is the
# map's own centre and `tools/maps.gd` prints it.
#
#   tools/pack.sh <out dir> [selection...] [pitch] [back] [time] [bearing]
#
# SELECTION is anything `tools/maps.gd` takes, `all`, `towns`, `outside`,
# `inside`, `ts<number>`, or an explicit list of `group,number` separated by
# spaces. Default `towns`, which is the twenty-three maps the cartridge files as
# a town or a city and is the right size for one pack.
#
# The defaults stand the eye back far enough to hold each map WHOLE: pitch 34,
# back `auto`, morning, and the survey bearing rather than due south, since what
# a pack is for is showing a face and a flank at once. `auto` is per map, off
# `maps.gd`, because one distance cannot frame a city and a village alike: 320
# holds a village and shows one corner of Saffron. Give a number to override it.
#
# Files are named `<group>_<number>.png`, and each frame carries its own map
# and the cartridge's own name for it BURNED IN, through `tools/label.py`: a
# reviewer sent a picture does not see what it is called, so a pack whose only
# labels are filenames is a pack nobody can point at. A LOG is written beside
# them naming every map as well, for the agent's own side of the round.
#
# The cartridge cache is $CACHE, else the Crystal one. The pokerecomp checkout
# is $POKERECOMP, else the read-only one in `.references`. The Godot binary is
# $GODOT, else `godot` on the path, else where the macOS installer puts it.
#
# THIS RENDERS, so it needs a display: no `--headless`. Reckon four seconds a
# map, which is Godot starting, not the mesh.

set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${POKERECOMP:-$HERE/.references/pokerecomp}"
CACHE="${CACHE:-user://rom_cache/crystal_f2f52230}"

OUT="${1:-}"
if [ -z "$OUT" ]; then
	echo "usage: tools/pack.sh <out dir> [selection...] [pitch] [back] [time] [bearing]" >&2
	exit 2
fi
shift
SELECT="${1:-towns}"
[ $# -gt 0 ] && shift
# AN EXPLICIT LIST MAY BE GIVEN AS SEPARATE WORDS, so keep taking map pairs
# before reading the options: the options are all plain numbers and none of
# them holds a comma, so the first word without one ends the list. Without
# this the pitch, the distance, the hour and the bearing each swallowed a map
# and the pack came back shot at midnight with three maps missing.
while [ $# -gt 0 ]; do
	case "$1" in
		[0-9]*,[0-9]*)
			SELECT="$SELECT $1"
			shift
			;;
		*) break ;;
	esac
done
PITCH="${1:-34}"
[ $# -gt 0 ] && shift
BACK="${1:-auto}"
[ $# -gt 0 ] && shift
TIME_OF_DAY="${1:-1}"
[ $# -gt 0 ] && shift
BEARING="${1:-20.4}"

if [ ! -d "$HOST" ]; then
	echo "no pokerecomp checkout at $HOST; set POKERECOMP" >&2
	exit 2
fi
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
LOG="$OUT/pack.txt"
# KEPT ACROSS RUNS, because a pack shot in two goes keeps every picture and
# truncating here left two thirds of them unnamed. A map re-shot replaces its
# own line rather than gaining a second one.
touch "$LOG"

# An explicit list is anything holding a comma that is not one of the words, and
# it is taken as given. Everything else is asked of `maps.gd`, whose own last
# line is a count rather than a map and is dropped.
rows=""
case "$SELECT" in
	all|towns|outside|inside|ts*)
		rows=$("$GODOT" --headless --path "$HOST" -s "$HERE/tools/maps.gd" \
			-- "$CACHE" "$SELECT" 2>/dev/null \
			| awk -F'\t' 'NF >= 8 && $1 ~ /^[0-9]+,[0-9]+$/ \
				{ print $1 "\t" $6 "\t" $7 "\t" $8 }')
		;;
	*)
		# An explicit list carries no centre and no distance, so ask the one
		# thing that knows, ONCE and before the loop rather than once per map:
		# twenty maps meant twenty-one Godot starts for one table, and a map
		# missing from it was reported halfway through the render instead of
		# before the first frame.
		table=$("$GODOT" --headless --path "$HOST" -s "$HERE/tools/maps.gd" \
			-- "$CACHE" all 2>/dev/null)
		for pair in $SELECT; do
			case "$pair" in
				*,*) ;;
				*) continue ;;
			esac
			row=$(printf '%s\n' "$table" \
				| awk -F'\t' -v m="$pair" \
					'$1 == m { print $1 "\t" $6 "\t" $7 "\t" $8 }')
			if [ -z "$row" ]; then
				echo "no map $pair" >&2
				continue
			fi
			rows="$rows$row\n"
		done
		rows=$(printf "%b" "$rows")
		;;
esac

if [ -z "$rows" ]; then
	echo "no maps matched '$SELECT'" >&2
	exit 1
fi

printf '%s\n' "$rows" | while IFS="$(printf '\t')" read -r map centre fit name; do
	[ -n "$map" ] || continue
	group="${map%%,*}"
	number="${map##*,}"
	[ -n "$centre" ] || { echo "no map $map" >&2; continue; }
	x="${centre%%,*}"
	y="${centre##*,}"
	stand="$BACK"
	[ "$stand" = "auto" ] && stand="$fit"
	file="$OUT/${group}_${number}.png"
	# The old picture goes first, or a render that fails leaves the last one
	# standing: the check below then passes, the log calls it fresh, and the
	# label is burned on top of the label it already wears.
	rm -f "$file"
	"$GODOT" --path "$HOST" -s "$HERE/tools/shot.gd" -- "$CACHE" \
		"$group" "$number" "$x" "$y" "$file" \
		"$PITCH" "$stand" "$TIME_OF_DAY" "" 6 "$BEARING" \
		< /dev/null > /dev/null 2>&1
	if [ -f "$file" ]; then
		python3 "$HERE/tools/label.py" "$file" "$file" "MAP $map" "$name" \
			> /dev/null
		leaf="${group}_${number}.png"
		if grep -q "^$leaf	" "$LOG" 2> /dev/null; then
			grep -v "^$leaf	" "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
		fi
		printf '%s\tmap %s\t%s\taimed at %s from %s\n' \
			"$leaf" "$map" "$name" "$centre" "$stand" >> "$LOG"
		echo "${group}_${number}.png"
	else
		echo "${group}_${number}.png FAILED" >&2
	fi
done

echo "pack in $OUT, listed in $LOG"
