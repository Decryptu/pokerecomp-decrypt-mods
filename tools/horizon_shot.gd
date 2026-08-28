extends SceneTree

## Photographs the HORIZON, through the game's own screen.

const WINDOW_SIZE := Vector2i(1600, 900)
const SETTLE_FRAMES: int = 60
const Steering: GDScript = preload("../mods/voxel3d/steering.gd")
const Staging: GDScript = preload("staging.gd")

var _staging: RefCounted = Staging.new()
var _screen: Gen2WorldScreen = null
var _renderer: Node = null
var _out: String = ""
var _label: String = ""
var _hold: int = 240
var _frames: int = 0
var _pitch: float = 18.0
var _distance: float = 480.0
var _zoom: float = 1.0
var _still: bool = false


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		print("usage: -- <game> <group> <number> [cell=x,y] [window=WxH] [pitch=]"
			+ " [distance=] [zoom=] [view=] [set=key:value,...] [static=name:value,...]"
			+ " [hold=] [label=] [out=]")
		quit(2)
		return
	var named: Dictionary = Staging.named(args)
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache for %s" % args[0])
		quit(1)
		return
	var group: int = int(args[1])
	var number: int = int(args[2])
	var map: Gen2WorldMap = data.world_map(group, number)
	if map == null:
		print("no map %d,%d" % [group, number])
		quit(1)
		return

	_out = String(named.get("out", "user://horizon.png"))
	if Gen2ToolPath.refuses(_out):
		quit(2)
		return
	_label = String(named.get("label", ""))
	_hold = maxi(int(named.get("hold", "240")), 1)
	_still = int(named.get("wind", "1")) == 0
	_pitch = float(named.get("pitch", "18"))
	_distance = float(named.get("distance", "480"))
	_zoom = float(named.get("zoom", "1.0"))
	var window: Vector2i = Staging.window_size(
		String(named.get("window", "")), WINDOW_SIZE
	)
	var wanted := Vector2i(map.collision_width / 2, map.collision_height / 2)
	if String(named.get("cell", "")).contains(","):
		var parts: PackedStringArray = String(named["cell"]).split(",")
		wanted = Vector2i(int(parts[0]), int(parts[1]))
	var start: Vector2i = Staging.open_ground(map, wanted)
	if start == Vector2i.MAX:
		print("no walkable room on map %d,%d" % [group, number])
		quit(1)
		return
	print("map        %d,%d at %s (asked %s), window %s" % [
		group, number, str(start), str(wanted), str(window),
	])

	var host: Gen2ModHost = Gen2ModHost.instance()
	if host.world_actors().is_empty():
		host.discover()
		host.load_discovered()
	var view := StringName(named.get("view", "voxel3d"))
	print("view       %s %s" % [String(view), str(host.select_view(view))])
	if named.has("static"):
		Staging.apply_statics(String(named["static"]))
	if named.has("set"):
		_staging.apply_options(host, view, String(named["set"]))
	if not host.failures().is_empty():
		print("failures   %s" % str(host.failures()))

	root.set_content_scale_size(window)
	root.size = window
	DisplayServer.window_set_size(window)
	_screen = (load("res://game/world/world_screen.tscn") as PackedScene).instantiate()
	_screen.map_group = group
	_screen.map_number = number
	_screen.start_cell = start
	_screen.encounter_seed = 1
	_screen.set_data(data)
	_screen.set_save(_save(data, group, number, start))
	root.add_child(_screen)
	current_scene = _screen


func _process(_delta: float) -> bool:
	if _screen == null:
		return true
	_frames += 1
	if _frames == 1:
		return false
	if _frames == 2:
		if Vector2i(_screen.world_snapshot().get("map", Vector2i(-1, -1))) == Vector2i(-1, -1):
			print("no world: is the starting cell inside the map?")
			quit(1)
			return true
		_screen.advance_frames(SETTLE_FRAMES)
		return false
	if _frames == 3:
		_renderer = Staging.find_renderer(_screen)
		if _renderer == null:
			print("no view renderer in the tree: was the view selected?")
			quit(1)
			return true
		_aim()
		return false
	if _still and _frames == _hold:
		_still_the_wind()
	if _frames < 3 + _hold:
		return false
	_report_foliage()
	_capture()
	quit(0)
	return true


func _report_foliage() -> void:
	var node: Node = _find_named(root, "FarFoliage")
	if node == null:
		print("foliage   none in the tree")
		return
	var groups: int = 0
	var cards: int = 0
	for child: Node in node.get_children():
		var multi: MultiMeshInstance3D = child as MultiMeshInstance3D
		if multi == null or not multi.visible or multi.multimesh == null:
			continue
		groups += 1
		cards += multi.multimesh.instance_count
	print("foliage    %d drawings, %d cards" % [groups, cards])
	var houses: Node = _find_named(root, "FarHouses")
	if houses == null:
		return
	var maps: int = 0
	var faces: int = 0
	for child: Node in houses.get_children():
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh == null or not mesh.visible or mesh.mesh == null:
			continue
		maps += 1
		for surface: int in mesh.mesh.get_surface_count():
			faces += (mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				as PackedVector3Array).size() / 3
	print("houses     %d maps, %d triangles" % [maps, faces])


func _find_named(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found: Node = _find_named(child, wanted)
		if found != null:
			return found
	return null


func _aim() -> void:
	var rig: RefCounted = _renderer.get("_rig")
	if rig == null:
		print("no camera rig on the renderer")
		return
	rig.steer_by(Steering.PITCH_UP, (_pitch - rig.pitch()) / 6.0)
	rig.steer_by(Steering.DOLLY_OUT, (_distance - rig.distance()) / 24.0)
	rig.steer_by(Steering.ZOOM_OUT, (_zoom - rig.zoom()) / Steering.ZOOM_STEP)
	print("camera     pitch %.1f, distance %.0f, zoom %.2f" % [
		rig.pitch(), rig.distance(), rig.zoom(),
	])


func _still_the_wind() -> void:
	var stage: RefCounted = _renderer.get("_stage")
	if stage == null:
		return
	var wind: RefCounted = stage.get("_wind")
	if wind == null:
		return
	var materials: Array = [wind.grass, wind.foliage]
	materials.append_array((wind.get("_sprites") as Dictionary).values())
	for material: ShaderMaterial in materials:
		if material != null:
			material.set_shader_parameter("period", 3600.0)
	print("wind       stilled on %d materials" % materials.size())


func _capture() -> void:
	var image: Image = root.get_texture().get_image()
	if image == null:
		print("no frame to save")
		return
	if not _label.is_empty():
		_burn(image, _label)
	if image.save_png(_out) != OK:
		print("could not write %s" % _out)
		return
	print("shot       %s" % _out)

const GLYPHS: Dictionary = {
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"B": ["11110", "10001", "11110", "10001", "10001", "10001", "11110"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "11110", "10000", "10000", "10000", "11111"],
	"F": ["11111", "10000", "11110", "10000", "10000", "10000", "10000"],
	"G": ["01111", "10000", "10000", "10011", "10001", "10001", "01111"],
	"H": ["10001", "10001", "11111", "10001", "10001", "10001", "10001"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	"J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
	"K": ["10001", "10010", "11100", "10010", "10010", "10001", "10001"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10001", "10001", "10001", "10001"],
	"N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"P": ["11110", "10001", "11110", "10000", "10000", "10000", "10000"],
	"Q": ["01110", "10001", "10001", "10001", "10101", "10011", "01111"],
	"R": ["11110", "10001", "11110", "10010", "10010", "10001", "10001"],
	"S": ["01111", "10000", "01110", "00001", "00001", "10001", "01110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
	"W": ["10001", "10001", "10001", "10001", "10101", "11011", "10001"],
	"X": ["10001", "01010", "00100", "00100", "00100", "01010", "10001"],
	"Y": ["10001", "01010", "00100", "00100", "00100", "00100", "00100"],
	"Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00110", "01000", "10000", "11111"],
	"3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
	"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	"5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
	"6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
	"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
	"9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
	",": ["00000", "00000", "00000", "00000", "00110", "00100", "01000"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
}
const GLYPH_SCALE: int = 4
const GLYPH_MARGIN: int = 12


func _burn(image: Image, text: String) -> void:
	var upper: String = text.to_upper()
	var wide: int = upper.length() * 6 * GLYPH_SCALE + GLYPH_MARGIN
	var high: int = 7 * GLYPH_SCALE + GLYPH_MARGIN
	for y: int in high:
		for x: int in mini(wide, image.get_width()):
			if y < image.get_height():
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 1.0))
	var at: int = GLYPH_MARGIN / 2
	for index: int in upper.length():
		var rows: Array = GLYPHS.get(upper[index], GLYPHS[" "])
		for row: int in rows.size():
			var line: String = rows[row]
			for column: int in line.length():
				if line[column] != "1":
					continue
				for dy: int in GLYPH_SCALE:
					for dx: int in GLYPH_SCALE:
						var px: int = at + column * GLYPH_SCALE + dx
						var py: int = GLYPH_MARGIN / 2 + row * GLYPH_SCALE + dy
						if px < image.get_width() and py < image.get_height():
							image.set_pixel(px, py, Color.WHITE)
		at += 6 * GLYPH_SCALE


func _finalize() -> void:
	_staging.restore()


func _save(data: GameData, group: int, number: int, cell: Vector2i) -> Gen2SaveData:
	var mon := Gen2SaveMon.new()
	mon.species = 155
	mon.level = 5
	mon.hp = 20
	mon.nickname = String(data.species(155).get("name", ""))
	var save := Gen2SaveData.new()
	save.game_id = data.id
	save.player_name = "SHOT"
	save.party = [mon]
	var snapshot := Gen2WorldSnapshot.new()
	snapshot.map_id = Vector2i(group, number)
	snapshot.player_cell = cell
	snapshot.world_state.set_wild_encounters_off(true)
	save.world = snapshot
	return save

const ROOM_CELLS: int = 24
const SEARCH_CELLS: int = 40