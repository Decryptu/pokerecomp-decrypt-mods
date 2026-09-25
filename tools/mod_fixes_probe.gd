extends SceneTree


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: -- <cache directory>")
		quit(2)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at %s" % args[0])
		quit(1)
		return
	var ok: bool = _ledge_corner(data)
	ok = _cards_stand_on_ground(data) and ok
	quit(0 if ok else 1)


func _ledge_corner(data: GameData) -> bool:
	var repo: String = (get_script() as Script).resource_path.get_base_dir().get_base_dir()
	var voxel: String = repo.path_join("mods/voxel3d")
	if data.generation == RomRegistry.GEN1:
		print("ledge corner: Route 29 is a Generation 2 map, skipped")
		return true
	var map: Gen2WorldMap = data.world_map(24, 3)
	if map == null:
		print("ledge map 24,3 missing")
		return false
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
	var shape: RefCounted = (load(voxel.path_join("shape/tile_shape.gd")) as GDScript).new(
		(load(voxel.path_join("shape/profiles.gd")) as GDScript).of(data), tileset.name
	)
	var source: RefCounted = (load(voxel.path_join("shape/map_source.gd")) as GDScript).new(
		null, map, tileset, data
	)
	var mesher: RefCounted = (load(voxel.path_join("shape/mesher.gd")) as GDScript).new()
	mesher.resolve(source, shape)
	var rows: Array[String] = []
	for ty: int in range(17, 21):
		var values: PackedStringArray = PackedStringArray()
		for tx: int in range(15, 20):
			var at: int = mesher.grid_index(Vector2i(tx, ty))
			values.append(str(int(mesher._ledge[at])))
		rows.append(" ".join(values))
	print("map 24,3 ledges around cell 7,8:\n%s" % "\n".join(rows))
	var corner: int = int(mesher._ledge[mesher.grid_index(Vector2i(16, 19))])
	var joined: bool = corner == mesher.LEDGE_WEST | mesher.LEDGE_SOUTH
	print("perpendicular ledges form one corner wedge: %s" % ("yes" if joined else "NO"))
	var model_checked: bool = false
	for ty: int in mesher._map_size.y:
		for tx: int in mesher._map_size.x:
			var at: int = mesher.grid_index(Vector2i(tx, ty))
			if int(mesher._modelled[at]) == 0:
				continue
			var position := Vector3((float(tx) + 0.5) * 8.0, 0.0, (float(ty) + 0.5) * 8.0)
			var column: int = mesher.height_at_position(position)
			var occlusion: int = mesher.occlusion_height_at_position(position)
			model_checked = occlusion > column
			print("stamped model occlusion %d exceeds its column %d: %s" % [
				occlusion, column, "yes" if model_checked else "NO",
			])
			break
		if model_checked:
			break
	return joined and model_checked


## The player's card is its 16x16 picture with the draw list's `ground` at the
## bottom centre, which is where the diorama stands it on the cell.
func _cards_stand_on_ground(data: GameData) -> bool:
	var repo: String = (get_script() as Script).resource_path.get_base_dir().get_base_dir()
	var map: Gen2WorldMap = data.world_maps()[0]
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, map.group, map.number, Vector2i(2, 2), Gen2WorldState.new()
	)
	var cards: RefCounted = (load(repo.path_join("mods/voxel3d/world/sprite_cards.gd")) as GDScript).new()
	var player: Dictionary = {}
	for card: Dictionary in cards.cards(Gen2WorldDrawList.new(world)):
		if int(card["owner"]) == Gen2WorldDrawList.OWNER_PLAYER:
			player = card
	var ok: bool = not player.is_empty() \
		and (player["texture"] as Texture2D).get_size() == Vector2(16, 16) \
		and Vector2(player["anchor"]) == Vector2(8, 16)
	print("the player's card stands its bottom centre on the ground: %s" % ("yes" if ok else "NO"))
	return ok
