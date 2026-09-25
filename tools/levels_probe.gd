extends SceneTree

## Every painting in `shape/levels.gd` still finds the drawing it was painted on.
## A painting is keyed by its drawing, so a change in how the host imports a
## map's blocks or tiles would silently leave every painted cave flat; neither
## the played run nor another probe reads a painted height.
##   -- <cartridge>

var _failures: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: -- <cartridge>")
		quit(2)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache for %s" % args[0])
		quit(1)
		return
	var levels: GDScript = load("user://mods/voxel3d/shape/levels.gd")
	var checked: int = 0
	for drawing: String in levels.PAINTINGS:
		var painting: Dictionary = levels.PAINTINGS[drawing]
		var where: PackedStringArray = String(painting["painted_on"]).split(" ")
		if where[0] != String(data.id):
			continue
		var at: PackedStringArray = where[1].split(",")
		var map: Gen2WorldMap = data.world_map(int(at[0]), int(at[1]))
		var tileset: Gen2WorldTileset = null if map == null \
			else data.world_tileset(map.tileset)
		_report("%s wears its painting" % painting["painted_on"],
			levels.rows_of(map, tileset) == painting["rows"])
		checked += 1
	print("%d paintings made on %s" % [checked, data.id])
	quit(int(_failures > 0))


func _report(what: String, passed: bool) -> void:
	print("%s %s" % ["ok   " if passed else "FAIL ", what])
	if not passed:
		_failures += 1
