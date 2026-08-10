extends SceneTree

## Photographs one real hedge three ways, so the reviewer can pick which is right.
##
## A bush is one walk cell and a hedge is several ranks of the same bush, each
## building its own round blob, which reads as corduroy rather than as foliage.
## The three ways out cannot be told apart in words, so this renders them: the
## same place, the same eye, the same light, one picture each.
##
##   Godot --path <gen2recomp> -s tools/hedge_shot.gd -- <cache> <out dir>
##
## Emits `hedge_<variant>.png`, `hedge_2d.png` and `hedge.json`.
## `tools/hedge_page.py` builds the page from them. Nothing here writes a pin.

const MOD := "user://mods/voxel3d"
const TILE: int = 8
const BLOCK_TILES: int = 4
const CELL: float = 16.0

## The class the question is about, and the tileset it is pinned in.
const TILESET: int = 3
const CLASS := &"bush"

## The shot: how far back the eye sits from the hedge and how far above the
## horizontal it looks down, chosen to frame about ten cells of ground, which is
## most of a Game Boy screen and the frame the drawing was composed for.
const BACK: float = 210.0
const PITCH: float = 34.0
const VIEW := Vector2i(720, 520)

var _data: GameData = null
var _out: String = ""
var _stage: RefCounted = null
var _atlas: RefCounted = null
var _mesher: RefCounted = null
var _profile: GDScript = null
var _tile_shape: GDScript = null
var _map_source: GDScript = null

var _queue: Array = []
var _pending: String = ""
var _frames: int = 0
var _map: Gen2WorldMap = null
var _tileset: Gen2WorldTileset = null
var _focus := Vector3.ZERO
var _records: Array = []


## What each variant changes, and the words the page asks the question in.
const VARIANTS: Array = [
	{
		"id": "leave",
		"label": "leave it",
		"depth": -1, "merged": false,
		"says": "Every bush is its own round blob, 14 px deep in a 16 px cell. "
			+ "This is what the mod builds today.",
	},
	{
		"id": "shallow",
		"label": "a shallower bush",
		"depth": 7, "merged": false,
		"says": "Still one blob per bush, but half as deep, so the ranks sit "
			+ "closer to a flat mass and the gaps between them are smaller.",
	},
	{
		"id": "hedge",
		"label": "one hedge",
		"depth": -1, "merged": true,
		"says": "A run of bush cells is detected as ONE hedge: it runs through at "
			+ "full depth wherever the next cell is bush too, and only the ends of "
			+ "the run are rounded.",
	},
]


## A shape that answers everything the real one does, with one class altered.
## Rendering a variant is otherwise a change to the profile, and the profile is
## the reviewer's answer rather than a knob a tool may turn.
class Overlay extends RefCounted:
	var _inner: RefCounted
	var _class: StringName
	var _depth: int
	var _merged: bool

	func _init(inner: RefCounted, shape_class: StringName, depth: int, merged: bool) -> void:
		_inner = inner
		_class = shape_class
		_depth = depth
		_merged = merged

	func at(tile: int, permission: int) -> StringName:
		return _inner.at(tile, permission)

	func is_pinned(tile: int) -> bool:
		return _inner.is_pinned(tile)

	func height(shape_class: StringName) -> int:
		return _inner.height(shape_class)

	func art(shape_class: StringName) -> StringName:
		return _inner.art(shape_class)

	func depth(shape_class: StringName) -> int:
		if shape_class == _class and _depth > 0:
			return _depth
		return _inner.depth(shape_class)

	func building_part(shape_class: StringName) -> StringName:
		return _inner.building_part(shape_class)

	func roof_drop(shape_class: StringName) -> int:
		return _inner.roof_drop(shape_class)

	func is_round(shape_class: StringName) -> bool:
		return _inner.is_round(shape_class)

	func is_filled(shape_class: StringName) -> bool:
		return _inner.is_filled(shape_class)

	func is_merged(shape_class: StringName) -> bool:
		if shape_class == _class:
			return _merged
		return _inner.is_merged(shape_class)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: <cache> <out dir>")
		quit(1)
		return
	_data = GameData.open_directory(args[0])
	if _data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	_out = args[1]
	DirAccess.make_dir_recursive_absolute(_out)

	_profile = load("%s/shape/profile.gd" % MOD)
	_tile_shape = load("%s/shape/tile_shape.gd" % MOD)
	_map_source = load("%s/shape/map_source.gd" % MOD)
	_atlas = (load("%s/shape/atlas.gd" % MOD) as GDScript).new()
	_mesher = (load("%s/shape/mesher.gd" % MOD) as GDScript).new()
	_stage = (load("%s/world/diorama.gd" % MOD) as GDScript).new()

	var holder := Control.new()
	holder.add_child(_stage.container)
	root.add_child(holder)
	_stage.container.size = Vector2(VIEW)
	_stage.viewport.size = VIEW

	if not _find():
		print("no run of %s cells found in tileset %d" % [CLASS, TILESET])
		quit(1)
		return
	_queue = VARIANTS.duplicate()


## The deepest run of this class anywhere the tileset is used, which is the worst
## case of the thing being asked about and so the one worth photographing.
func _find() -> bool:
	var tileset: Gen2WorldTileset = _data.world_tileset(TILESET)
	if tileset == null:
		return false
	var best_run: int = 0
	for map: Gen2WorldMap in _data.world_maps():
		if map.tileset != TILESET:
			continue
		var tiles := Vector2i(map.width_blocks, map.height_blocks) * BLOCK_TILES
		for tx: int in tiles.x:
			var run: int = 0
			for ty: int in tiles.y:
				if _is_class(map, tileset, tx, ty):
					run += 1
					if run > best_run:
						best_run = run
						_map = map
						_tileset = tileset
						_focus = Vector3(
							(float(tx) + 0.5) * TILE, 0.0,
							(float(ty) - float(run) * 0.5 + 0.5) * TILE
						)
				else:
					run = 0
	return _map != null


func _is_class(map: Gen2WorldMap, tileset: Gen2WorldTileset, tx: int, ty: int) -> bool:
	@warning_ignore("integer_division")
	var block: int = map.block_at(tx / BLOCK_TILES, ty / BLOCK_TILES)
	var tile: int = tileset.tile_index(block, (ty & 3) * BLOCK_TILES + (tx & 3))
	return _profile.pinned_class(TILESET, tile) == CLASS


func _build(variant: Dictionary) -> void:
	_stage.set_time_of_day(Gen2WorldPalette.TIME_DAY)
	if _atlas.build(_data, _map, _tileset, Gen2WorldPalette.TIME_DAY):
		_stage.set_texture(_atlas.texture)
		_stage.set_background(Color(0.36, 0.55, 0.78))
	var shape := Overlay.new(
		_tile_shape.new(_profile, TILESET), CLASS,
		int(variant["depth"]), bool(variant["merged"])
	)
	_stage.set_terrain(_mesher.build(_map_source.new(null, _map, _tileset), shape, _atlas))

	# South-east of the hedge and looking back down at it, which is the stance the
	# overworld camera takes and the one a rank of blobs shows up worst in.
	var pitch: float = deg_to_rad(PITCH)
	var eye: Vector3 = _focus + Vector3(
		BACK * cos(pitch) * 0.35, BACK * sin(pitch), BACK * cos(pitch) * 0.94
	)
	_stage.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_stage.aim_camera(eye, _focus + Vector3(0.0, CELL * 0.5, 0.0))


func _process(_delta: float) -> bool:
	if _pending == "":
		if _queue.is_empty():
			_finish()
			return true
		var variant: Dictionary = _queue.pop_front()
		_build(variant)
		_pending = String(variant["id"])
		_records.append(variant)
		_frames = 0
		return false

	_frames += 1
	if _frames < 6:
		return false
	_stage.viewport.get_texture().get_image().save_png(
		"%s/hedge_%s.png" % [_out, _pending]
	)
	print("shot %s" % _pending)
	_pending = ""
	return false


func _finish() -> void:
	_paint_2d().save_png("%s/hedge_2d.png" % _out)
	var file: FileAccess = FileAccess.open("%s/hedge.json" % _out, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"map": [_map.group, _map.number],
		"tileset": TILESET,
		"variants": _records,
	}, "  "))
	file.close()
	print("done")


## The same place as the cartridge draws it, so the question can be answered
## against the drawing rather than against three renders of each other.
func _paint_2d() -> Image:
	var indices: PackedByteArray = _data.world_tileset_indices(_tileset.number)
	var palettes: Array = Gen2WorldPalette.tile_palettes(
		_data, _map, _tileset, Gen2WorldPalette.TIME_DAY
	)
	var stride: int = _tileset.tile_count * TILE
	var tiles := Vector2i(_map.width_blocks, _map.height_blocks) * BLOCK_TILES
	var window: int = 15
	var origin := Vector2i(
		clampi(int(_focus.x / TILE) - window / 2, 0, maxi(tiles.x - window, 0)),
		clampi(int(_focus.z / TILE) - window / 2, 0, maxi(tiles.y - window, 0))
	)
	var across := Vector2i(mini(window, tiles.x), mini(window, tiles.y))
	var image: Image = Image.create(
		across.x * TILE, across.y * TILE, false, Image.FORMAT_RGBA8
	)
	for ty: int in across.y:
		for tx: int in across.x:
			@warning_ignore("integer_division")
			var block: int = _map.block_at(
				(origin.x + tx) / BLOCK_TILES, (origin.y + ty) / BLOCK_TILES
			)
			var tile: int = _tileset.tile_index(
				block, ((origin.y + ty) & 3) * BLOCK_TILES + ((origin.x + tx) & 3)
			)
			var palette: PackedColorArray = palettes[tile] if tile < palettes.size() \
				else PackedColorArray()
			for y: int in TILE:
				var row: int = y * stride + tile * TILE
				for x: int in TILE:
					var index: int = int(indices[row + x]) if row + x < indices.size() else 0
					image.set_pixel(
						tx * TILE + x, ty * TILE + y,
						palette[index] if index < palette.size() else Color.MAGENTA
					)
	return image
