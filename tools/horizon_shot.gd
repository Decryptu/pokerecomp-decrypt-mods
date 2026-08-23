extends SceneTree

## Photographs the HORIZON, through the game's own screen.
##
## `tools/shot.gd` builds a diorama by hand and `tools/stage_bench.gd` walks one,
## and neither has a horizon in it: `world/far_field.gd` folds the maps around
## this one off a live [Gen2WorldAPI], and there is none without a world screen.
## So every claim about what stands past the mesh has been argued off the game
## played by hand, and one of them was wrong for a release.
##
## This stands the player still on a real map, dollies the camera out to where
## the far ground fills the frame, holds until the mesh window has finished
## building, and saves the picture.
##
## Needs a display, and mods only load when they are asked for:
##
##   Godot --path <pokerecomp> --mods -s tools/horizon_shot.gd -- \
##       <game> <group> <number> [key=value ...]
##
##   cell=19,33      where the player stands, in walk cells; the map's centre
##                   otherwise, moved to open ground the way `walk_bench` does
##   window=1600x900 the window the picture is drawn at
##   pitch=18        the camera's own pitch, in degrees above the horizon. Low is
##                   the whole point: at the opening 50 the far ground is a strip
##                   at the top of the frame
##   distance=480    how far the eye stands back, in world pixels.
##                   `camera_rig.gd:DISTANCE_LIMITS` caps it, and the cap is
##                   where a horizon is read
##   zoom=1.0        the lens, as `camera_rig.gd:fov` takes it
##   view=voxel3d    the registered view
##   set=distance:16 the view's own settings, put back when the run ends
##   static=far_trees:0  the view's own tuning statics
##   hold=240        frames held before the shutter. The mesh is built in slices
##                   and the far maps' sheets one a frame, so a shot taken early
##                   is a picture of a world still arriving
##   wind=1          0 stills the sway, which is the only way two shots of this
##                   view can be compared: the foliage bends on the shader's own
##                   TIME, so two runs of one configuration differ on forty
##                   thousand pixels and a real change can hide under that
##   label=BEFORE    burnt into the top-left corner of the picture. A reviewer
##                   gets no filenames, so a plate that does not name itself is
##                   a plate that cannot be argued about
##   out=horizon.png where the picture is saved
##
## The camera is aimed due south, which is where the overworld's own is: a shot
## off to one side shows more of the skyline and less of what a player sees.

const WINDOW_SIZE := Vector2i(1600, 900)
## Frames spent before the player is even looked for, so the map's own entry
## script has run.
const SETTLE_FRAMES: int = 60
## The mod script the tuning statics live on. See `walk_bench.gd`.
const RENDERER := "user://mods/voxel3d/world/renderer.gd"
const Steering: GDScript = preload("../mods/voxel3d/steering.gd")

var _screen: Gen2WorldScreen = null
var _renderer: Node = null
var _out: String = ""
var _label: String = ""
var _hold: int = 240
var _frames: int = 0
var _pitch: float = 18.0
var _distance: float = 480.0
var _zoom: float = 1.0
## Whether the sway is stilled for the shot. See the `wind` option.
var _still: bool = false
var _restore: Dictionary = {}
var _restore_id: StringName = &""


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		print("usage: -- <game> <group> <number> [cell=x,y] [window=WxH] [pitch=]"
			+ " [distance=] [zoom=] [view=] [set=key:value,...] [static=name:value,...]"
			+ " [hold=] [label=] [out=]")
		quit(2)
		return
	var named: Dictionary = _named(args)
	var data: GameData = GameData.open(StringName(args[0]))
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

	_out = String(named.get("out", "horizon.png"))
	_label = String(named.get("label", ""))
	_hold = maxi(int(named.get("hold", "240")), 1)
	_still = int(named.get("wind", "1")) == 0
	_pitch = float(named.get("pitch", "18"))
	_distance = float(named.get("distance", "480"))
	_zoom = float(named.get("zoom", "1.0"))
	var window: Vector2i = _size(String(named.get("window", "")))
	var wanted := Vector2i(map.collision_width / 2, map.collision_height / 2)
	if String(named.get("cell", "")).contains(","):
		var parts: PackedStringArray = String(named["cell"]).split(",")
		wanted = Vector2i(int(parts[0]), int(parts[1]))
	var start: Vector2i = _open_ground(map, wanted)
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
		_apply_statics(String(named["static"]))
	if named.has("set"):
		_apply_options(host, view, String(named["set"]))
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
		_renderer = _find_renderer(_screen)
		if _renderer == null:
			print("no view renderer in the tree: was the view selected?")
			quit(1)
			return true
		_aim()
		return false
	# LATE, and not with the aim: the horizon cuts a card and pools a material for
	# it as each map comes into view, so a pool stilled on the first frame is a
	# pool with almost nothing in it yet.
	if _still and _frames == _hold:
		_still_the_wind()
	# The window is built in slices and the far maps are painted one sheet a
	# frame, so the hold is what the picture is waiting for and not a courtesy.
	if _frames < 3 + _hold:
		return false
	_report_foliage()
	_capture()
	quit(0)
	return true


## WHAT THE HORIZON IS ACTUALLY STANDING, because a picture of a distant wood and
## a picture of a bare page differ by very little on a thumbnail and by
## everything in the frame. `far_foliage.gd` and `far_houses.gd` pool their
## instances and hide the ones they did not use this frame, so the visible ones
## are this frame's answer.
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


## Stands the eye where the arguments asked, through the rig's own commands: a
## held steer moves the value and its goal together, so nothing is left easing
## when the shutter opens.
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


## A sway period of an hour is a still frame for as long as a shot lasts, and it
## leaves the geometry and the shader exactly as they are: nothing is switched
## off, the clock is slowed. `tools/stage_bench.gd` does the same, and the SPRITE
## pool is the addition: the horizon's cards each wear their own material out of
## it, so stilling only the two named ones leaves the whole distance swaying.
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


## THE PLATE NAMES ITSELF. A reviewer is handed pictures and no filenames, so a
## before and an after that are only told apart by the order they arrive in are
## two pictures of nothing. Drawn as blocks a pixel row at a time, because a font
## needs a whole scene tree and this is eight glyphs on a corner.
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


func _named(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for index: int in range(3, args.size()):
		var pair: String = args[index]
		var at: int = pair.find("=")
		if at <= 0:
			continue
		out[pair.substr(0, at)] = pair.substr(at + 1)
	return out


func _size(text: String) -> Vector2i:
	var parts: PackedStringArray = text.split("x")
	if parts.size() != 2 or int(parts[0]) <= 0 or int(parts[1]) <= 0:
		return WINDOW_SIZE
	return Vector2i(int(parts[0]), int(parts[1]))


func _apply_statics(spec: String) -> void:
	var script: GDScript = load(RENDERER)
	if script == null:
		print("no renderer script at %s" % RENDERER)
		return
	for pair: String in spec.split(",", false):
		var parts: PackedStringArray = pair.split(":")
		if parts.size() != 2:
			continue
		var name: String = parts[0].strip_edges()
		var text: String = parts[1].strip_edges()
		var value: Variant = float(text) if text.contains(".") else int(text)
		if script.get(name) is bool:
			value = bool(value)
		script.set(name, value)
		print("static     %s = %s" % [name, str(script.get(name))])


func _apply_options(host: Gen2ModHost, id: StringName, spec: String) -> void:
	for pair: String in spec.split(",", false):
		var parts: PackedStringArray = pair.split(":")
		if parts.size() != 2:
			continue
		var key := StringName(parts[0].strip_edges())
		var text: String = parts[1].strip_edges()
		var value: Variant = float(text) if text.contains(".") else int(text)
		_restore[key] = host.option(id, key)
		print("option     %s = %s %s" % [
			String(key), str(value), str(host.set_option(id, key, value)),
		])
	_restore_id = id


## The settings go back whatever happened, for `walk_bench.gd`'s reason: a tool
## that only tidies up when it succeeds leaves the player's file wrong.
func _finalize() -> void:
	if _restore.is_empty():
		return
	var host: Gen2ModHost = Gen2ModHost.instance()
	for key: StringName in _restore:
		if _restore[key] != null:
			host.set_option(_restore_id, key, _restore[key])


func _find_renderer(node: Node) -> Node:
	var script: Script = node.get_script() as Script
	if script != null and script.resource_path.begins_with("user://mods/") \
			and node.has_method("refresh"):
		return node
	for child: Node in node.get_children():
		var found: Node = _find_renderer(child)
		if found != null:
			return found
	return null


## `walk_bench.gd`'s save, with the encounters always off: a battle owning the
## world is a picture of a battle.
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


## The nearest cell to [param wanted] standing in a room worth photographing.
## `walk_bench.gd`'s rule and for its reason: a map's centre is a building on
## most towns and a wall on several routes.
const ROOM_CELLS: int = 24
const SEARCH_CELLS: int = 40


func _open_ground(map: Gen2WorldMap, wanted: Vector2i) -> Vector2i:
	var refused: Dictionary = {}
	for radius: int in SEARCH_CELLS:
		for offset: Vector2i in _ring(radius):
			var cell: Vector2i = wanted + offset
			if refused.has(cell) or not _walkable(map, cell):
				continue
			var region: Dictionary = _region(map, cell)
			if region.size() >= ROOM_CELLS:
				return cell
			refused.merge(region)
	return Vector2i.MAX


func _ring(radius: int) -> Array:
	if radius == 0:
		return [Vector2i.ZERO]
	var out: Array = []
	for offset: int in range(-radius, radius + 1):
		out.append(Vector2i(offset, -radius))
		out.append(Vector2i(offset, radius))
		if offset != -radius and offset != radius:
			out.append(Vector2i(-radius, offset))
			out.append(Vector2i(radius, offset))
	return out


func _region(map: Gen2WorldMap, from: Vector2i) -> Dictionary:
	var seen: Dictionary = {from: true}
	var stack: Array = [from]
	while not stack.is_empty() and seen.size() < ROOM_CELLS:
		var at: Vector2i = stack.pop_back()
		for way: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = at + way
			if seen.has(next) or not _walkable(map, next):
				continue
			seen[next] = true
			stack.append(next)
	return seen


func _walkable(map: Gen2WorldMap, cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 \
			or cell.x >= map.collision_width or cell.y >= map.collision_height:
		return false
	return Gen2WorldCollision.is_walkable(map.collision[cell.y * map.collision_width + cell.x])
