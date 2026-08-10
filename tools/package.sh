#!/bin/sh
# Packs one mod directory into the archive the game's installer takes.
#
# The archive holds a single mod folder at its root, which is one of the two
# layouts Gen2ModInstaller accepts, and is named for the version in the
# manifest so a release asset and an index row cannot drift apart.
#
#   sh tools/package.sh voxel3d

set -e

id="$1"
[ -n "$id" ] || { echo "usage: sh tools/package.sh <mod id>" >&2; exit 2; }

root=$(cd "$(dirname "$0")/.." && pwd)
src="$root/mods/$id"
[ -f "$src/mod.json" ] || { echo "no mods/$id/mod.json" >&2; exit 1; }

manifest_id=$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$src/mod.json" | head -1)
[ "$manifest_id" = "$id" ] || { echo "mod.json id is '$manifest_id', not '$id'" >&2; exit 1; }
version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$src/mod.json" | head -1)
[ -n "$version" ] || { echo "mod.json has no version" >&2; exit 1; }

out="$root/dist/$id-$version.zip"
mkdir -p "$root/dist"
rm -f "$out"

# -x drops what only matters in the checkout: Godot writes a .uid beside a
# script it has imported, and it addresses a resource in the editing project
# rather than in a player's mod folder.
(cd "$root/mods" && zip -rq "$out" "$id" -x '*.DS_Store' -x '*.uid')

echo "$out"
