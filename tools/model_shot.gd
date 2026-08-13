extends SceneTree

## Photographs the AUTHORED models on their own, one style per frame.
##
## A model is not carved from the drawing, so the survey tools cannot show it:
## this measures a real drawing off the cartridge, builds each style from those
## numbers and stands them in a row on a plain floor.
##
##   Godot --path <pokerecomp> -s tools/model_shot.gd -- <cache> <tileset> \
##       <w tiles> <h tiles> <out.png> <tile ids, row major>
##
## Needs a display, since it renders.

const MOD := "user://mods/voxel3d"
const VIEW := Vector2i(900, 380)

var _stage: RefCounted = null
var _out: String = ""
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 6:
		print("usage: <cache> <tileset> <w> <h> <out.png> <tile ids...>")
		quit(1)
		return
	var data: GameData = GameData.open_directory(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var number: int = int(args[1])
	var across := Vector2i(int(args[2]), int(args[3]))
	_out = args[4]
	var tiles: Array = []
	for index: int in range(5, args.size()):
		tiles.append(int(args[index]))

	var map: Gen2WorldMap = null
	for candidate: Gen2WorldMap in data.world_maps():
		if candidate.tileset == number and map == null:
			map = candidate
	if map == null:
		print("no map on tileset ", number)
		quit(1)
		return
	var atlas: RefCounted = (load("%s/shape/atlas.gd" % MOD) as GDScript).new()
	if not atlas.build(data, map, data.world_tileset(number), 1):
		print("no atlas")
		quit(1)
		return
	var mesher: RefCounted = (load("%s/shape/mesher.gd" % MOD) as GDScript).new()
	var mask: PackedByteArray = mesher._structure_mask(tiles, across, atlas, false, 1)
	var model_script: GDScript = load("%s/shape/model.gd" % MOD)
	var measured: RefCounted = model_script.measure(
		mask, across * 8, tiles, across, atlas
	)
	print("drawn %dx%d px, %d crown tones" % [
		measured.width, measured.height, measured.crown.size()
	])

	_stage = (load("%s/world/diorama.gd" % MOD) as GDScript).new()
	var holder := Control.new()
	holder.add_child(_stage.container)
	root.add_child(holder)
	_stage.container.size = Vector2(VIEW)
	_stage.viewport.size = VIEW
	_stage.set_time_of_day(1)
	_stage.set_texture(atlas.texture)
	_stage.set_background(atlas.background(), true)

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	var styles: Array = [model_script.BALL, model_script.BROAD, model_script.TIERED]
	var gap: float = float(measured.width) + 12.0
	var triangles: int = 0
	for index: int in styles.size():
		var builder: RefCounted = model_script.new()
		var mesh: ArrayMesh = builder.tree(measured, styles[index])
		for surface: int in mesh.get_surface_count():
			@warning_ignore("integer_division")
			triangles += mesh.surface_get_array_len(surface) / 3
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = material
		instance.position = Vector3((float(index) - 1.0) * gap, 0.0, 0.0)
		_stage.viewport.add_child(instance)
	print("three styles, %d triangles in all, %d each on average" % [
		triangles, triangles / 3
	])

	# A patch of floor under them, so the trees are seen standing rather than
	# floating: one quad wearing the map's own ground tile.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(gap * 4.0, gap * 3.0)
	ground.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.45, 0.72, 0.32)
	ground.material_override = floor_material
	_stage.viewport.add_child(ground)

	var focus := Vector3(0.0, float(measured.height) * 0.4, 0.0)
	var back: float = gap * 2.6
	var pitch: float = deg_to_rad(20.0)
	_stage.aim_camera(
		focus + Vector3(0.0, back * sin(pitch), back * cos(pitch)), focus
	)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 6:
		return false
	_stage.viewport.get_texture().get_image().save_png(_out)
	print(_out)
	return true
