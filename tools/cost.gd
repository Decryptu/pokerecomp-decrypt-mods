extends SceneTree

## What every map in the game COSTS to resolve and to emit, in one run.
##
## Every claim in this repository about triangles and milliseconds is a claim
## about the whole game rather than about one route, because a feature that is
## free on a town can be most of the bill on a forest. Written because the emit
## grew sevenfold between two measurements and nothing recorded which change did
## it: run this before and after anything that touches the mesher and the
## difference is the answer.
##
##   Godot --headless --path <pokerecomp> -s tools/cost.gd -- <cache> \
##       [tileset|all] [out.json]
##
## Prints the totals, the dearest maps, and the per-tileset split. With an output
## path it writes every map's own line, which is what makes two runs comparable
## map by map rather than in aggregate.
##
## Headless: it resolves and emits, and never renders.

const MOD := "user://mods/voxel3d"
## How many of the dearest maps to name.
const WORST: int = 8


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: <cache> [tileset|all] [out.json]")
		quit(1)
		return
	var data: GameData = GameData.open_directory(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var only: int = -1
	if args.size() > 1 and args[1] != "all":
		only = int(args[1])

	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var atlas_script: GDScript = load("%s/shape/atlas.gd" % MOD)
	var mesher_script: GDScript = load("%s/shape/mesher.gd" % MOD)
	var shape_script: GDScript = load("%s/shape/tile_shape.gd" % MOD)
	var source_script: GDScript = load("%s/shape/map_source.gd" % MOD)

	var lines: Array = []
	var triangles: int = 0
	var resolve_usec: int = 0
	var emit_usec: int = 0
	var by_tileset: Dictionary = {}
	for map: Gen2WorldMap in data.world_maps():
		if only >= 0 and map.tileset != only:
			continue
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		var atlas: RefCounted = atlas_script.new()
		if not atlas.build(data, map, tileset, 1):
			continue
		var shape: RefCounted = shape_script.new(profile, map.tileset)
		var source: RefCounted = source_script.new(null, map, tileset)
		var mesher: RefCounted = mesher_script.new()

		var at: int = Time.get_ticks_usec()
		mesher.resolve(source, shape)
		var resolved: int = Time.get_ticks_usec() - at
		at = Time.get_ticks_usec()
		var meshes: Array = mesher.emit(atlas)
		var emitted: int = Time.get_ticks_usec() - at

		# A model is built once per distinct drawing and STAMPED, so its triangles
		# are counted once and the stamps are counted as what they cost, which is
		# one instance each and not one mesh each.
		var faces: int = 0
		for mesh: ArrayMesh in meshes:
			for surface: int in mesh.get_surface_count():
				faces += (mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					as PackedVector3Array).size()
		var stamps: int = 0
		for model: Array in mesher.take_models():
			for surface: int in (model[0] as ArrayMesh).get_surface_count():
				faces += ((model[0] as ArrayMesh).surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					as PackedVector3Array).size()
			stamps += (model[1] as PackedVector3Array).size()
		@warning_ignore("integer_division")
		var count: int = faces / 3

		lines.append({
			"map": "%d,%d" % [map.group, map.number],
			"tileset": map.tileset,
			"cells": [map.width_blocks * 2, map.height_blocks * 2],
			"triangles": count,
			"models": stamps,
			"resolve_ms": float(resolved) / 1000.0,
			"emit_ms": float(emitted) / 1000.0,
		})
		triangles += count
		resolve_usec += resolved
		emit_usec += emitted
		if not by_tileset.has(map.tileset):
			by_tileset[map.tileset] = [0, 0]
		(by_tileset[map.tileset] as Array)[0] += count
		(by_tileset[map.tileset] as Array)[1] += 1

	print("%d maps  %.2fM triangles  %.2f s resolve  %.2f s emit" % [
		lines.size(), float(triangles) / 1000000.0,
		float(resolve_usec) / 1000000.0, float(emit_usec) / 1000000.0,
	])
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["triangles"]) > int(b["triangles"]))
	print("dearest maps:")
	for index: int in mini(WORST, lines.size()):
		var line: Dictionary = lines[index]
		print("  %-7s ts%-3d %3dx%-3d %8d tri  %5d models  %6.1f ms resolve  %7.1f ms emit" % [
			line["map"], line["tileset"], (line["cells"] as Array)[0],
			(line["cells"] as Array)[1], line["triangles"], line["models"],
			line["resolve_ms"], line["emit_ms"],
		])
	var tilesets: Array = by_tileset.keys()
	tilesets.sort_custom(func(a: int, b: int) -> bool:
		return by_tileset[a][0] > by_tileset[b][0])
	print("by tileset:")
	for number: int in tilesets:
		print("  ts%-3d %2d maps %8d tri" % [
			number, by_tileset[number][1], by_tileset[number][0]
		])
	if args.size() > 2:
		var file: FileAccess = FileAccess.open(args[2], FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(lines, "  "))
			print("wrote ", args[2])
	quit()
