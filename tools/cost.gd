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
	if args.size() > 2 and Gen2ToolPath.refuses(args[2]):
		quit(2)
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
	var rasterised: int = 0
	var resolve_usec: int = 0
	var emit_usec: int = 0
	var by_tileset: Dictionary = {}
	for map: Gen2WorldMap in data.world_maps():
		if only >= 0 and map.tileset != only:
			continue
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		var atlas: RefCounted = atlas_script.new()
		# THE SEQUENCE, so this measures the mesh the game actually builds:
		# `atlas.gd:frame_count` spans every frame an animated tile is drawn as,
		# and without one here the union is never walked and the cost of it never
		# appears.
		var animation := Gen2WorldAnimation.new()
		animation.configure_tileset(data, tileset, 1)
		if not atlas.build(data, map, tileset, 1, animation):
			continue
		var shape: RefCounted = shape_script.new(profile, map.tileset)
		var source: RefCounted = source_script.new(null, map, tileset, data)
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
		#
		# THE WATER AND THE GRASS ARE ON THEIR OWN LISTS and have to be asked for
		# separately, or a sea route and a meadow both read as free: each is drawn
		# with its own material, so each is its own mesh, and `emit` answers the
		# terrain alone.
		var faces: int = 0
		for mesh: ArrayMesh in meshes + mesher.take_water() + mesher.take_tufts():
			for surface: int in mesh.get_surface_count():
				faces += (mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					as PackedVector3Array).size()
		# AND WHAT THEY COST TO DRAW, which is the other number and is not the same
		# one: geometry is stored once per drawing and rasterised once per stamp, so
		# a forest is one mesh to hold and two hundred trees to draw. A model built
		# at a finer voxel is nearly free in the first and multiplied in the second.
		#
		# AND ONE MESH IS HANDED OVER SEVERAL TIMES. `take_models` answers per
		# distinct drawing PER GROUP, because a MultiMesh spanning a whole window
		# has the window for a bounding box and can never be culled, so a forest
		# arrives as one mesh in a dozen entries. Counting its faces per entry
		# reported the whole game at 10.26M triangles the day the grouping landed,
		# against 7.23M for exactly the same geometry.
		var stamps: int = 0
		var drawn: int = 0
		var held: Dictionary = {}
		for model: Array in mesher.take_models():
			var mesh: ArrayMesh = model[0]
			var model_faces: int = 0
			for surface: int in mesh.get_surface_count():
				model_faces += (mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					as PackedVector3Array).size()
			if not held.has(mesh.get_instance_id()):
				held[mesh.get_instance_id()] = true
				faces += model_faces
			stamps += (model[1] as Array).size()
			drawn += model_faces * (model[1] as Array).size()
		@warning_ignore("integer_division")
		var count: int = faces / 3
		@warning_ignore("integer_division")
		var on_screen: int = (faces + drawn) / 3

		lines.append({
			"map": "%d,%d" % [map.group, map.number],
			"tileset": map.tileset,
			"cells": [map.width_blocks * 2, map.height_blocks * 2],
			"triangles": count,
			"drawn": on_screen,
			"models": stamps,
			"resolve_ms": float(resolved) / 1000.0,
			"emit_ms": float(emitted) / 1000.0,
		})
		triangles += count
		rasterised += on_screen
		resolve_usec += resolved
		emit_usec += emitted
		if not by_tileset.has(map.tileset):
			by_tileset[map.tileset] = [0, 0]
		(by_tileset[map.tileset] as Array)[0] += count
		(by_tileset[map.tileset] as Array)[1] += 1

	print("%d maps  %.2fM triangles  %.2fM drawn  %.2f s resolve  %.2f s emit" % [
		lines.size(), float(triangles) / 1000000.0, float(rasterised) / 1000000.0,
		float(resolve_usec) / 1000000.0, float(emit_usec) / 1000000.0,
	])
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["triangles"]) > int(b["triangles"]))
	print("dearest maps:")
	for index: int in mini(WORST, lines.size()):
		var line: Dictionary = lines[index]
		print("  %-7s ts%-3d %3dx%-3d %8d tri %8d drawn %5d models  %6.1f ms resolve  %7.1f ms emit" % [
			line["map"], line["tileset"], (line["cells"] as Array)[0],
			(line["cells"] as Array)[1], line["triangles"], line["drawn"],
			line["models"], line["resolve_ms"], line["emit_ms"],
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
			# CLOSED, or `quit()` takes the buffer with it: every per-map file this
			# tool wrote came out cut off at 72 KB, which is most of the way through
			# the game and looks like a complete run until it is parsed.
			file.close()
			print("wrote ", args[2])
	quit()
