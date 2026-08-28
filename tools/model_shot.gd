extends SceneTree

## Photographs the AUTHORED models, several drawings side by side on a plain
## floor, with each drawing's own 2D art above it.

const MOD := "user://mods/voxel3d"
const VIEW := Vector2i(1200, 460)

var _stage: RefCounted = null
var _out: String = ""
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		print("usage: <cache> <out.png> <ts,w,h,ids.ids.ids> ...")
		quit(1)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	_out = args[1]
	if Gen2ToolPath.refuses(_out):
		quit(2)
		return

	_stage = (load("%s/world/diorama.gd" % MOD) as GDScript).new()
	var holder := Control.new()
	holder.add_child(_stage.container)
	root.add_child(holder)
	_stage.container.size = Vector2(VIEW)
	_stage.set_time_of_day(1)

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	var model_script: GDScript = load("%s/shape/model.gd" % MOD)
	var mesher: RefCounted = (load("%s/shape/mesher.gd" % MOD) as GDScript).new()
	var placed: float = 0.0
	var tallest: float = 0.0
	var background: Color = Color("#8fd070")
	for index: int in range(2, args.size()):
		var spec: PackedStringArray = args[index].split(",")
		if spec.size() < 4:
			continue
		var number: int = int(spec[0])
		var across := Vector2i(int(spec[1]), int(spec[2]))
		var tiles: Array = []
		for piece: String in spec[3].split("."):
			tiles.append(int(piece))

		var map: Gen2WorldMap = null
		for candidate: Gen2WorldMap in data.world_maps():
			if candidate.tileset == number and map == null:
				map = candidate
		if map == null:
			print("no map on tileset ", number)
			continue
		var atlas: RefCounted = (load("%s/shape/atlas.gd" % MOD) as GDScript).new()
		if not atlas.build(data, map, data.world_tileset(number), 1):
			continue
		if index == 2:
			background = atlas.background()
		var kind: String = spec[4] if spec.size() > 4 else ""
		var mask: PackedByteArray = mesher._structure_mask(
			tiles, across, atlas, kind == "rock", 1
		)
		var measured: RefCounted = model_script.measure(
			mask, across * 8, tiles, across, atlas
		)
		measured.shrub = kind == "shrub" or kind == "rock"
		measured.rock = kind == "rock"
		var mesh: ArrayMesh = (model_script.new() as RefCounted).tree(measured)
		var triangles: int = 0
		for surface: int in mesh.get_surface_count():
			@warning_ignore("integer_division")
			triangles += mesh.surface_get_array_len(surface) / 3
		print("ts%-3d %2dx%2d px  trunk %dx%d  %d crown tones, %d bark  %d triangles" % [
			number, measured.width(), measured.height(),
			measured.trunk_width, measured.trunk_height,
			measured.tones.size(), measured.bark.size(), triangles
		])

		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = material
		placed += float(measured.width()) * 0.5 + 8.0
		instance.position = Vector3(placed, 0.0, 0.0)
		placed += float(measured.width()) * 0.5
		tallest = maxf(tallest, float(measured.height()))
		_stage.viewport.add_child(instance)

	_stage.set_background(background, true)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(placed * 2.0 + 80.0, 120.0)
	ground.mesh = plane
	ground.position = Vector3(placed * 0.5, 0.0, 0.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.55, 0.80, 0.38)
	floor_material.roughness = 1.0
	ground.material_override = floor_material
	_stage.viewport.add_child(ground)

	var focus := Vector3(placed * 0.5, tallest * 0.45, 0.0)
	var back: float = placed * 0.62 + 26.0
	var pitch: float = deg_to_rad(17.0)
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
