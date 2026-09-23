#!/usr/bin/env bash
# Renders labelled 3D frames for a map selection.
# Usage: tools/pack.sh <out dir> [selection...] [pitch] [back] [time] [bearing]
# Selection: towns (default), all, outside, inside, ts<number>, or map pairs
# written group,number. Defaults: pitch 34, per-map distance, morning,
# bearing 20.4. CACHE, POKERECOMP and GODOT select the environment.
# Rendering requires a display.
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
# Commas distinguish map pairs from positional numeric options.
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
# Keep the map list across partial runs.
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
	# Remove stale output before checking whether this render succeeded.
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
