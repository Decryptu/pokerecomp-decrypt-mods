#!/usr/bin/env bash
# Parses every mod script and says nothing when they all parse, then runs
# tools/bloat.py over them. Run it after any edit: six seconds, no cartridge.
#
#   tools/check.sh [mods|tools|all|warnings] [pokerecomp path]
#
# `tools` reads the probes and shot drivers instead, half a minute; `all` is
# both. `warnings` runs the game's own analyser through its editor, about a
# minute, and is a pre-release check rather than a per-edit one.
#
# The host is the first argument, else $POKERECOMP, else `.references`. The
# binary is $GODOT, else `godot`, else where the macOS installer puts it.
#
# A FAILURE NAMING A `game/` FILE IS NOT A MOD FAULT: parsing resolves against
# the game's class index, which is a build cache, so a `class_name` added since
# the last editor scan does not resolve yet. One scan clears it:
#
#   godot --headless --editor --path /path/to/pokerecomp --quit

set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WHAT="mods"
case "${1:-}" in
	mods|tools|all|warnings) WHAT="$1"; shift ;;
esac
HOST="${1:-${POKERECOMP:-$HERE/.references/pokerecomp}}"
if [ ! -d "$HOST" ]; then
	echo "no pokerecomp checkout at $HOST; pass one or set POKERECOMP" >&2
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

if [ "$WHAT" = "warnings" ]; then
	# The mods are reached as `user://`, where they are installed; the tools have
	# no project path and are given as they sit.
	mods=()
	for mod in "$HERE"/mods/*/; do
		mods+=("user://mods/$(basename "$mod")")
	done
	exec "$GODOT" --headless --editor --path "$HOST" -- --warning-scan \
		"${mods[@]}" "$HERE/tools"
fi

scripts=()
if [ "$WHAT" != "tools" ]; then
	# `find` and not a glob: without `globstar` a glob reaches one directory down,
	# so anything nested deeper would be skipped in silence.
	while IFS= read -r found; do
		scripts+=("$found")
	done < <(find "$HERE/mods" -name '*.gd' | sort)
fi
if [ "$WHAT" != "mods" ]; then
	scripts+=("$HERE"/tools/*.gd)
fi

status=0
for script in "${scripts[@]}"; do
	[ -e "$script" ] || continue
	output="$("$GODOT" --headless --path "$HOST" --check-only -s "$script" 2>&1 \
		| grep -v "^Godot Engine\|get_node\|^ *at:\|scene tree\|^$")"
	if [ -n "$output" ]; then
		echo "${script#"$HERE"/}"
		echo "$output"
		status=1
	fi
done

python3 "$HERE/tools/bloat.py" "${scripts[@]}" || status=1
exit $status
