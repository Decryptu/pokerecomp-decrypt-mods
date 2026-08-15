#!/usr/bin/env bash
# Parses every script in the mod, and says nothing when they all parse.
#
# THE MOD IS LIVE. `user://mods/<id>/` is a symlink to this checkout, so a file
# that does not compile is not a private mistake: the game boots against it, and
# another agent's smoke test on this machine fails on our half-written function
# with an error that names our file and none of theirs. That has happened twice.
#
# So run this after any edit that adds a call, and prefer writing the function
# before the line that calls it. It takes about a second per script and needs no
# cartridge, because parsing is all it does.
#
# Parsing resolves against the game project, so it needs a pokerecomp checkout:
# the first argument, else $POKERECOMP, else the read-only one in `.references`.
# The Godot binary is $GODOT, else `godot` on the path, else where the macOS
# installer puts it: a stock install leaves no `godot` on the path at all, so
# the one-word command this file's own instructions promise failed there.
#
#   tools/check.sh [pokerecomp path]

set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
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

status=0
for script in "$HERE"/mods/*/**/*.gd "$HERE"/mods/*/*.gd; do
	[ -e "$script" ] || continue
	# --check-only parses and resolves without running, and prints nothing at all
	# when the script is sound. The engine's own no-scene-tree noise is dropped.
	output="$("$GODOT" --headless --path "$HOST" --check-only -s "$script" 2>&1 \
		| grep -v "^Godot Engine\|get_node\|^ *at:\|scene tree\|^$")"
	if [ -n "$output" ]; then
		echo "${script#"$HERE"/}"
		echo "$output"
		status=1
	fi
done
exit $status
