extends SceneTree

## Every distinct FOLIAGE drawing in the game, laid out twice: the cartridge's
## own art in a row, and the models the mod turns out of them in the same row,
## under a slightly isometric eye.
##
## The survey sheet pairs a BLOCK with what the mod built from it, which is the
## right unit for naming a tile and the wrong one for judging a shape: a tree is
## shown once per block it appears in, at whatever angle its slot fell at, beside
## thirty blocks of path. This gathers one of each instead, so every tree and
## every bush in the game is in one picture and can be compared with the next.
##
## The classes are an argument, so the same tool lays out the boulders or the
## stools when they are the question.
##
##   Godot --path <pokerecomp> -s tools/foliage.gd -- <cache> <out dir> \
##       [classes] [pitch] [bearing]
##
## Writes `foliage_2d.png`, `foliage_3d.png` and `foliage.json`, whose slots are
## the same width in both, so `tools/foliage_sheet.py` can number one column
## across the pair. Needs a display, since it renders.

const MOD := "user://mods/voxel3d"
const TILE: int = 8
## One slot, in SCREEN pixels, and the same in both sheets: what makes a column
## mean the same thing in the art and in the render.
const SLOT: int = 240
const SHEET_HEIGHT: int = 348
## What the 3D frame covers vertically, in world pixels. Chosen so that the
## frame is exactly ART_ZOOM screen pixels to the world pixel, which is the art's
## own scale: the tilt then foreshortens height by its own cosine and nothing
## else does. The tallest thing here is a conifer at about 45.
const FRAME_WORLD: float = float(SHEET_HEIGHT) / float(ART_ZOOM)
## How far up the frame the floor sits, so a model's foot is not on the edge.
const FLOOR_WORLD: float = 8.0
const ART_ZOOM: int = 6
const BACK := Color(0.094, 0.094, 0.110)

var _stage: RefCounted = null
var _out: String = ""
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: <cache> <out dir> [classes] [pitch] [bearing]")
		quit(1)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	_out = args[1].trim_suffix("/")
	if Gen2ToolPath.refuses(_out):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	var wanted: Dictionary = {}
	for word: String in (args[2] if args.size() > 2 else "tree,canopy,bush").split(","):
		wanted[StringName(word.strip_edges())] = true
	var pitch: float = deg_to_rad(float(args[3]) if args.size() > 3 else 30.0)
	var bearing: float = deg_to_rad(float(args[4]) if args.size() > 4 else 35.0)

	var found: Array = _census(data, wanted)
	if found.is_empty():
		print("nothing wearing ", wanted.keys())
		quit(1)
		return
	print(found.size(), " drawings")

	# A slot's own width in WORLD pixels is what the frame projects into SLOT
	# screen pixels. The row is laid along the camera's own RIGHT vector rather
	# than along world x, which is what keeps it level: a line along x under a
	# turned and tilted eye climbs the frame by the sine of both angles, and
	# eighteen slots of that walks the row off the picture.
	var spacing: float = FRAME_WORLD * float(SLOT) / float(SHEET_HEIGHT)
	# The models first: building one is what opens the drawing's own atlas, and
	# the art sheet is cut out of the same atlas so the pair cannot drift apart
	# by an hour or a palette.
	_stand_3d(data, found, spacing, pitch, bearing)
	_paint_2d(found).save_png("%s/foliage_2d.png" % _out)

	var slots: Array = []
	for index: int in found.size():
		var record: Dictionary = found[index]
		slots.append({
			"slot": index,
			"tileset": record["tileset"],
			"class": str(record["class"]),
			"tiles": record["tiles"],
			"maps": record["maps"],
			"across": [record["across"].x, record["across"].y],
			"ids": record["ids"],
			"where": record["where"],
		})
	var manifest: Dictionary = {
		"slot_pixels": SLOT,
		"sheet_height": SHEET_HEIGHT,
		"pitch": rad_to_deg(pitch),
		"bearing": rad_to_deg(bearing),
		"slots": slots,
	}
	var file: FileAccess = FileAccess.open("%s/foliage.json" % _out, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  "))
	file.close()


## Every distinct drawing in the game that RESOLVES to one of the wanted classes
## and is built as a model, with where the first one of it stands.
##
## The drawing is the SPAN BOX rather than the tile, which is the whole reason
## this cannot be read off a tile list: the tall conifer and the short one share
## every tile id they are drawn from and differ only in the box.
func _census(data: GameData, wanted: Dictionary) -> Array:
	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var shape_script: GDScript = load("%s/shape/tile_shape.gd" % MOD)
	var source_script: GDScript = load("%s/shape/map_source.gd" % MOD)
	var mesher_script: GDScript = load("%s/shape/mesher.gd" % MOD)
	var seen: Dictionary = {}
	for map: Gen2WorldMap in data.world_maps():
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		if tileset == null:
			continue
		var shape: RefCounted = shape_script.new(profile, map.tileset)
		# THE CARTRIDGE IS PASSED, so a drawing that straddles a map boundary is
		# the drawing the game builds. See `tools/shot.gd` for what happens without.
		var source: RefCounted = source_script.new(null, map, tileset, data)
		var mesher: RefCounted = mesher_script.new()
		mesher.resolve(source, shape)
		var size: Vector2i = mesher._size
		var names: Dictionary = {}
		for entry: StringName in mesher._class_ids:
			names[int(mesher._class_ids[entry])] = entry
		for ty: int in size.y:
			for tx: int in size.x:
				var at: int = ty * size.x + tx
				if mesher._modelled[at] != 1:
					continue
				var shape_class: StringName = names.get(mesher._klass[at], &"")
				if not wanted.has(shape_class):
					continue
				var box: Rect2i = mesher._span_box(at, tx, ty)
				var ids: Array = []
				for row: int in box.size.y:
					for column: int in box.size.x:
						ids.append(
							mesher._tile_at(box.position.x + column, box.position.y + row)
						)
				var key: String = "ts%d %s %s" % [map.tileset, shape_class, str(ids)]
				if not seen.has(key):
					seen[key] = {
						"tileset": map.tileset, "class": shape_class, "ids": ids,
						"across": box.size, "tiles": 0, "maps": {},
						"map": map, "at": at,
						"where": "%d,%d @ %d,%d" % [map.group, map.number, tx, ty],
					}
				var record: Dictionary = seen[key]
				record["tiles"] = int(record["tiles"]) + 1
				(record["maps"] as Dictionary)["%d,%d" % [map.group, map.number]] = true
	var out: Array = seen.values()
	for record: Dictionary in out:
		record["maps"] = (record["maps"] as Dictionary).size()
	# By CLASS and then by how much of the game wears it, so the row reads as the
	# trees, then the canopies, then the bushes, commonest first.
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if str(a["class"]) != str(b["class"]):
			return str(a["class"]) < str(b["class"])
		return int(a["tiles"]) > int(b["tiles"]))
	for index: int in out.size():
		var record: Dictionary = out[index]
		print("%2d  %6d tiles %3d maps  ts%-3d %-8s %s  %s" % [
			index, record["tiles"], record["maps"], record["tileset"],
			record["class"], str(record["ids"]), record["where"],
		])
	return out


## The cartridge's own art for each drawing, one per slot, standing on the same
## baseline. Taken out of the ATLAS the model is textured from rather than
## painted again, so the two sheets cannot drift apart by an hour or a palette.
func _paint_2d(found: Array) -> Image:
	var sheet: Image = Image.create(
		found.size() * SLOT, SHEET_HEIGHT, false, Image.FORMAT_RGBA8
	)
	sheet.fill(BACK)
	var floor_row: int = SHEET_HEIGHT - int(FLOOR_WORLD) * ART_ZOOM
	for index: int in found.size():
		var record: Dictionary = found[index]
		if not record.has("atlas"):
			continue
		var atlas: RefCounted = record["atlas"]
		var across: Vector2i = record["across"]
		var art: Image = Image.create(
			across.x * TILE, across.y * TILE, false, Image.FORMAT_RGBA8
		)
		var page: Image = atlas.texture.get_image()
		for row: int in across.y:
			for column: int in across.x:
				var tile: int = int((record["ids"] as Array)[row * across.x + column])
				# The atlas is 16 tiles to the row, which is `atlas.gd:TILES_PER_ROW`.
				@warning_ignore("integer_division")
				var origin := Vector2i((tile % 16) * TILE, (tile / 16) * TILE)
				art.blit_rect(
					page, Rect2i(origin, Vector2i(TILE, TILE)),
					Vector2i(column * TILE, row * TILE)
				)
		art.resize(
			art.get_width() * ART_ZOOM, art.get_height() * ART_ZOOM, Image.INTERPOLATE_NEAREST
		)
		var corner := Vector2i(
			index * SLOT + (SLOT - art.get_width()) / 2, floor_row - art.get_height()
		)
		sheet.blit_rect(art, Rect2i(Vector2i.ZERO, art.get_size()), corner)
	return sheet


## The same drawings built the way the game builds them, standing in the same
## slots under an ORTHOGRAPHIC eye, so every slot is the same size and a column
## in one sheet is the column in the other.
func _stand_3d(
	data: GameData, found: Array, spacing: float, pitch: float, bearing: float
) -> void:
	var view := Vector2i(found.size() * SLOT, SHEET_HEIGHT)
	_stage = (load("%s/world/diorama.gd" % MOD) as GDScript).new()
	var holder := Control.new()
	holder.add_child(_stage.container)
	root.add_child(holder)
	# Only the container is sized: it stretches, so it owns its SubViewport.
	_stage.container.size = Vector2(view)
	_stage.set_time_of_day(1)
	_stage.set_background(BACK, false)

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	var right := Vector3(cos(bearing), 0.0, -sin(bearing))
	var mesher_script: GDScript = load("%s/shape/mesher.gd" % MOD)
	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var shape_script: GDScript = load("%s/shape/tile_shape.gd" % MOD)
	var source_script: GDScript = load("%s/shape/map_source.gd" % MOD)
	for index: int in found.size():
		var record: Dictionary = found[index]
		var map: Gen2WorldMap = record["map"]
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		var atlas: RefCounted = (load("%s/shape/atlas.gd" % MOD) as GDScript).new()
		if not atlas.build(data, map, tileset, 1):
			continue
		record["atlas"] = atlas
		# Resolved again on the drawing's own map, because everything the turn
		# reads beyond the mask is a fact this map settled: whether it sits on the
		# ground, whether it is stone, how tall it stands and what its ring is cut
		# on. Building the model any other way is building a different model.
		var mesher: RefCounted = mesher_script.new()
		mesher.resolve(
			source_script.new(null, map, tileset, data),
			shape_script.new(profile, map.tileset)
		)
		var across: Vector2i = record["across"]
		var span := Vector2(across * TILE)
		var bodies: Array = mesher._model_bodies_of(
			record["ids"], across, int(record["at"]), atlas
		)
		var triangles: int = 0
		for body: Array in bodies:
			var mesh: ArrayMesh = mesher._model_meshes[body[0]]
			for surface: int in mesh.get_surface_count():
				@warning_ignore("integer_division")
				triangles += mesh.surface_get_array_len(surface) / 3
			var instance := MeshInstance3D.new()
			instance.mesh = mesh
			instance.material_override = material
			# Each body where it is drawn ACROSS the drawing, so a cell holding two
			# things stands two, the way the map does. The turn, the nudge and the
			# wind phase a placement carries are left off: they exist to break the
			# rows out of a forest, and a row of one of each is what this is.
			instance.position = right * (
				(float(index) + 0.5) * spacing + float(body[1].x) - span.x * 0.5
			)
			_stage.viewport.add_child(instance)
		record["triangles"] = triangles

	var middle: Vector3 = right * (float(found.size()) * spacing * 0.5)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	# Square, because the row runs across the world's axes rather than along one.
	var reach: float = float(found.size() + 2) * spacing
	plane.size = Vector2(reach, reach)
	ground.mesh = plane
	ground.position = middle
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.55, 0.80, 0.38)
	floor_material.roughness = 1.0
	ground.material_override = floor_material
	_stage.viewport.add_child(ground)

	_stage.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_stage.camera.size = FRAME_WORLD
	var focus: Vector3 = middle + Vector3(0.0, FRAME_WORLD * 0.5 - FLOOR_WORLD, 0.0)
	# Far enough back that the whole row is in front of the near plane, which an
	# orthographic camera cares about and a perspective one placed here would not.
	var arm: float = float(found.size()) * spacing + 200.0
	_stage.aim_camera(
		focus + Vector3(
			arm * cos(pitch) * sin(bearing), arm * sin(pitch), arm * cos(pitch) * cos(bearing)
		),
		focus
	)


## Six frames is `tools/shot.gd`'s own number and it is enough for the viewport
## to have drawn, EXCEPT WHEN THE MACHINE IS BUSY: two of four styles came back
## as a pure black frame, with no error anywhere, while another process was
## importing a cartridge. A blank sheet is not a picture of anything and it looks
## exactly like a rendering fault in the thing being judged, so the shutter waits
## for the frame to have something in it rather than for a count of frames.
const HOLD: int = 6
const GIVE_UP: int = 240


func _process(_delta: float) -> bool:
	if _stage == null:
		return true
	_frames += 1
	if _frames < HOLD:
		return false
	var shot: Image = _stage.viewport.get_texture().get_image()
	if _frames < GIVE_UP and _blank(shot):
		return false
	shot.save_png("%s/foliage_3d.png" % _out)
	print("%s/foliage_3d.png" % _out, " after ", _frames, " frames")
	return true


## Whether nothing has been drawn yet. The stage is never black: the floor fills
## the frame and the void behind it is this tool's own dark field.
func _blank(shot: Image) -> bool:
	for at: Vector2i in [
		Vector2i(2, 2), shot.get_size() / 2, shot.get_size() - Vector2i(3, 3)
	]:
		var pixel: Color = shot.get_pixel(at.x, at.y)
		if pixel.r + pixel.g + pixel.b > 0.02:
			return false
	return true
