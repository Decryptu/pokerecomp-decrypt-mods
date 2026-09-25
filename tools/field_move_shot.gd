extends SceneTree

## Walks a PATH through the game's own screen and keeps a frame at every step,
## with the cell, the mode and the collision it drew the player on. Surfing and
## climbing happen over time and over height, and a still says neither.
##
##   -- <game> <group> <number> <out dir> path=Sdrrruu [cell=x,y]
##      [view=voxel3d] [window=WxH] [hold=] [every=] [party=155,...]
##
## A PATH is one letter a step: `u d l r` walk, `a` presses A, and a capital
## uses a field move where the player stands, `C` Cut, `F` Flash, `H` Headbutt,
## `S` Surf, `W` Waterfall, `P` Whirlpool, through the screen's own preview pair.
## `A` runs the S.S. Anne's departure from Vermilion Dock and `X` flashes a
## poison step, through the screen's own previews. `every=N` keeps a frame every N frames of a step, which is how
## a climb is watched rather than counted. ONE ACT A DRIVER FRAME, since the
## world and the mesh both move on real ones.

const WINDOW_SIZE := Vector2i(960, 540)
const SETTLE_FRAMES: int = 90
const STEP_FRAMES: int = 24
const SHUTTER: int = 8
const Staging: GDScript = preload("staging.gd")
const MOVES: Dictionary = {
	"C": &"field_move", "F": &"flash", "S": &"surf", "W": &"waterfall", "P": &"whirlpool",
}
const ROW_MOVES: Dictionary = {"H": Gen2WorldFieldMove.MOVE_HEADBUTT}
const EDITS: Dictionary = {"A": &"preview_ss_anne_leaves", "X": &"preview_poison_step"}
const STEPS: Dictionary = {
	"u": Vector2i.UP, "d": Vector2i.DOWN, "l": Vector2i.LEFT, "r": Vector2i.RIGHT,
}

var _screen: Gen2WorldScreen = null
var _named: Dictionary = {}
var _out: String = ""
var _path: String = ""
var _acts: Array = []
var _kept: int = 0
var _wait: int = SHUTTER


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 4:
		print("usage: -- <game> <group> <number> <out dir> path=Sdrrruu [cell=x,y]"
			+ " [view=] [window=WxH] [hold=] [every=] [party=155,...]")
		quit(2)
		return
	_out = args[3]
	if PokeToolPath.refuses(_out):
		quit(2)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache for %s" % args[0])
		quit(1)
		return
	_named = Staging.named(args)
	_path = String(_named.get("path", ""))
	DirAccess.make_dir_recursive_absolute(_out)
	_stage(data, int(args[1]), int(args[2]))
	_acts = _script()


func _stage(data: GameData, group: int, number: int) -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	print("mods       %s" % str(Staging.load_installed(host, data)))
	print("view       %s" % str(host.select_view(
		StringName(_named.get("view", "voxel3d"))
	)))
	var size: Vector2i = Staging.window_size(
		String(_named.get("window", "")), WINDOW_SIZE
	)
	DisplayServer.window_set_size(size)
	root.set_content_scale_size(size)
	root.size = size
	_screen = (load("res://game/world/world_screen.tscn") as PackedScene).instantiate()
	_screen.map_group = group
	_screen.map_number = number
	_screen.start_cell = _cell()
	_screen.encounter_seed = 1
	_screen.set_data(data)
	var save: Gen2SaveData = Staging.party_save(
		data, String(_named.get("party", ""))
	)
	if save != null:
		_screen.set_save(save)
	root.add_child(_screen)
	current_scene = _screen


func _script() -> Array:
	var out: Array = [["settle", SETTLE_FRAMES], ["keep", "stood"]]
	for step: int in _path.length():
		var letter: String = _path[step]
		if MOVES.has(letter) or ROW_MOVES.has(letter) or EDITS.has(letter):
			out.append(["move", letter])
		elif letter == "a":
			out.append(["press", letter])
		elif STEPS.has(letter):
			out.append(["step", letter])
		else:
			continue
		out.append(["keep", "%d %s" % [step + 1, letter]])
	return out


func _cell() -> Vector2i:
	var parts: PackedStringArray = String(_named.get("cell", "4,4")).split(",")
	if parts.size() != 2:
		return Vector2i(4, 4)
	return Vector2i(int(parts[0]), int(parts[1]))


func _hold() -> int:
	return int(_named.get("hold", str(STEP_FRAMES)))


func _process(_delta: float) -> bool:
	if _screen == null:
		return true
	_screen.set_process(false)
	if _wait > 0:
		_wait -= 1
		return false
	if _acts.is_empty():
		print("kept %d frames in %s" % [_kept, _out])
		quit()
		return true
	var act: Array = _acts.pop_front()
	match act[0]:
		"settle":
			_screen.advance_frames(int(act[1]))
		"step":
			print("   step %s  %s" % [
				act[1], "moved" if _screen.move_player(STEPS[act[1]]) else "REFUSED",
			])
			_spend(_hold())
		"move":
			_use(String(act[1]))
		"press":
			_screen.press_button(PokeButton.A)
			_spend(_hold())
		"tick":
			_screen.advance_frames(1)
		"keep":
			_keep(String(act[1]))
	_wait = SHUTTER if act[0] == "keep" else 0
	return false


func _use(letter: String) -> void:
	if EDITS.has(letter):
		_screen.call(EDITS[letter])
	elif ROW_MOVES.has(letter):
		_screen.preview_field_move_row(ROW_MOVES[letter])
		_screen.advance_frames(SHUTTER)
		_screen.preview_field_move_row_use(ROW_MOVES[letter])
	else:
		var pair: String = "preview_%s_use" % String(MOVES[letter])
		_screen.call(pair)
		_screen.advance_frames(SHUTTER)
		_screen.call(pair)
	_spend(_hold())
	print("   %s  cell %s" % [
		letter,
		str((_screen.world_snapshot() as Dictionary).get("player_cell")),
	])


## Frames, one a driver frame so the renderer moves with them. Spent inside a
## single frame they all photograph the same picture.
func _spend(frames: int) -> void:
	var every: int = int(_named.get("every", "0"))
	if every <= 0:
		_screen.advance_frames(frames)
		return
	var ticks: Array = []
	for frame: int in frames:
		ticks.append(["tick", ""])
		if frame % every == every - 1:
			ticks.append(["keep", "+%d" % (frame + 1)])
	_acts = ticks + _acts


func _keep(what: String) -> void:
	var snapshot: Dictionary = _screen.world_snapshot()
	print("%02d %-6s cell %s  mode %s  collision 0x%02X" % [
		_kept, what, str(snapshot.get("player_cell")),
		str(snapshot.get("movement_mode")), int(snapshot.get("collision", -1)),
	])
	var image: Image = PokeToolPath.capture(root)
	if image == null:
		quit(1)
		return
	image.save_png("%s/%02d.png" % [_out, _kept])
	_kept += 1
