extends SceneTree

## Photographs one place on one map, the way the mod builds it.

const MOD := "user://mods/voxel3d"
const TILE: float = 8.0
const VIEW := Vector2i(880, 600)

var _stage: RefCounted = null
var _frame: SubViewport = null
var _out: String = ""
var _frames: int = 0
var _hold: int = 6


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 6:
		print("usage: <cache> <group> <number> <tile x> <tile y> <out.png>"
			+ " [pitch] [back] [time 0-3] [sky #rrggbb] [hold frames]"
			+ " [bearing east of south]")
		quit(1)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	_out = args[5]
	if Gen2ToolPath.refuses(_out):
		quit(2)
		return

	var map: Gen2WorldMap = null
	for candidate: Gen2WorldMap in data.world_maps():
		if candidate.group == int(args[1]) and candidate.number == int(args[2]):
			map = candidate
	if map == null:
		print("no map ", args[1], ",", args[2])
		quit(1)
		return
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)

	var atlas: RefCounted = (load("%s/shape/atlas.gd" % MOD) as GDScript).new()
	var mesher: RefCounted = (load("%s/shape/mesher.gd" % MOD) as GDScript).new()
	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var shape: RefCounted = (load("%s/shape/tile_shape.gd" % MOD) as GDScript).new(
		profile, map.tileset
	)
	var source: RefCounted = (load("%s/shape/map_source.gd" % MOD) as GDScript).new(
		null, map, tileset, data
	)
	_stage = (load("%s/world/diorama.gd" % MOD) as GDScript).new()
	_frame = SubViewport.new()
	_frame.size = VIEW
	_frame.transparent_bg = false
	_frame.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_frame)
	var holder := Control.new()
	holder.size = Vector2(VIEW)
	holder.add_child(_stage.container)
	_frame.add_child(holder)
	_stage.container.size = Vector2(VIEW)

	var time_of_day: int = clampi(int(args[8]) if args.size() > 8 else 1, 0, 3)
	_stage.set_time_of_day(time_of_day)
	var animation := Gen2WorldAnimation.new()
	animation.configure_tileset(data, tileset, time_of_day)
	if atlas.build(data, map, tileset, time_of_day, animation):
		_stage.set_texture(atlas.texture)
		if args.size() > 9 and not args[9].is_empty():
			_stage.set_background(Color(args[9]))
		elif source.outside():
			_stage.set_background(atlas.background(), true, atlas.sky_ramp())
		else:
			_stage.set_background(atlas.void_color(), false)
	_stage.set_terrain(mesher.build(source, shape, atlas))
	_stage.set_water(mesher.take_water())
	var shore: PackedColorArray = atlas.shore_colors()
	if shore.size() == 2:
		_stage.set_shore_colors(atlas.background(), shore[0], shore[1])
	_stage.set_bank(
		mesher.bank_field(), mesher.bank_world(), mesher.bank_origin(),
		mesher.bank_span()
	)
	_stage.set_tufts(mesher.take_tufts())
	_stage.set_models(mesher.take_models())
	_actors(data, map, mesher, time_of_day)

	var focus := Vector3((float(args[3]) + 0.5) * TILE, 0.0, (float(args[4]) + 0.5) * TILE)
	focus.y = float(mesher.surface_height_at_position(focus))
	_hold = maxi(int(args[10]) if args.size() > 10 else 6, 1)
	var pitch: float = deg_to_rad(float(args[6]) if args.size() > 6 else 32.0)
	var back: float = float(args[7]) if args.size() > 7 else 220.0
	var bearing: float = deg_to_rad(float(args[11]) if args.size() > 11 else 20.4)
	_stage.aim_camera(
		focus + Vector3(
			back * cos(pitch) * sin(bearing), back * sin(pitch), back * cos(pitch) * cos(bearing)
		),
		focus + Vector3(0.0, TILE, 0.0)
	)
	_stage.set_walker(focus)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < _hold:
		return false
	_frame.get_texture().get_image().save_png(_out)
	print(_out)
	return true


func _actors(
	data: GameData, map: Gen2WorldMap, mesher: RefCounted, time_of_day: int
) -> void:
	_stage.begin_cards()
	_stage.begin_shadow_casters()
	for event: Dictionary in (map.events.get("objects", []) as Array):
		var number: int = int(event.get("sprite", 0))
		var icon: int = Gen2WorldSprite.mon_icon_for_sprite(number)
		var sprite: Gen2WorldSprite = data.overworld_icon(icon) if icon > 0 \
			else data.overworld_sprite(number)
		if sprite == null:
			continue
		var image: Image = Gen2WorldSprite.image_for(
			sprite,
			data.overworld_icon_indices(sprite.icon_number) \
				if sprite.sprite_type == Gen2WorldSprite.TYPE_MON_ICON \
				else data.overworld_sprite_indices(sprite.number),
			data.overworld_sprite_palette(
				int(event.get("palette", 0)) if int(event.get("palette", 0)) != 0
				else sprite.default_palette,
				time_of_day
			),
			Gen2WorldSprite.FACING_DOWN,
			0,
		)
		if image == null:
			continue
		var at := Vector3(
			(float(event.get("x", 0)) + 0.5) * TILE * 2.0, 0.0,
			(float(event.get("y", 0)) + 0.5) * TILE * 2.0
		)
		at.y = float(mesher.surface_height_at_position(at))
		var texture: Texture2D = ImageTexture.create_from_image(image)
		_stage.add_standing_card(texture, at)
		_stage.add_shadow_caster(texture, at, 1.0)
	_stage.end_cards()
	_stage.end_shadow_casters()
