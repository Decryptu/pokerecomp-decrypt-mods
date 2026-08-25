extends SceneTree

## Photographs a BATTLE staged on a real map, the way the mod builds one.
##
## `tools/shot.gd` is the overworld's camera and there was no equivalent for the
## fight, so every claim about the arena, the panels, the bars and the battlers
## was argued from the code. Three open items want a picture of one: the frosted
## panels, the shot's drift, and the move animations.
##
## `Gen2BattleWorldContext` is a copy of where the fight started, with public
## fields and no handle on the world, so a tool fills one in exactly as the world
## screen does. The view is the display dictionary `Gen2BattleScreen` hands over,
## and only the keys the renderer reads are set here.
##
##   Godot --path <pokerecomp> -s tools/battle_shot.gd -- <cache> <group> \
##       <number> <cell x> <cell y> <out.png> [facing 0-3] [time 0-3] \
##       [player species] [enemy species] [hold frames] [hp 0-1] \
##       [anim index] [anim frame] [enemy turn 0-1] [background half 0-1] \
##       [moment] [doll none|enemy|player|both] [unown form 1-26] \
##       [shiny none|enemy|player|both]
##
## A MOMENT IS A STATE, not a frame count: `fight` is the settled pair and
## the default, `slide` is both pictures part way in, `stand` is both standing,
## `walkoff` is the player's picture leaving with the opponent's Pokemon already
## out, `sent` is the stretch with the opponent's square empty, and `faint`,
## `gone` and `recall` are the three states past the entrance: the sink of
## `MonFaintedAnimation`, the blank of `BattleBGEffect_HideMon` that a Fly or a
## Dig leaves, and the ball shrink of a resize script. See [method _battlers].
##
## A MOVE ANIMATION IS RUN HEADLESS rather than mocked up, which is what makes
## open work 7 checkable at all. `Gen2BattleAnimPlayer` is the cartridge's own
## interpreter and needs nothing but the anim data and a script index, so this
## creates one, steps it to the frame asked for, and puts whatever it left in
## `wShadowOAM` into the view. ANIM FRAME 0 means the busiest frame of the first
## ninety, which is the one worth photographing and is tedious to find by hand.
## `hud_visible` goes false with it, because `BattleAnimClearHud` takes the
## panels and both bars off the map for the length of a move.
##
## DOLL raises the substitute on one side or both, and UNOWN FORM puts Unown on
## both squares in the letter asked for. Both are pictures the renderer chooses
## between and neither is reachable by staging a wild Pidgey, so each is an
## argument rather than something to catch mid-battle.
##
## THE SHUTTER IS ON THE COMPOSITE and the reason is in `tools/shot.gd`: a pass
## over the finished picture lives on the stage container's material and only
## runs when that container is drawn into something else. The renderer is put
## inside a viewport of this tool's own and THAT is what is saved.
##
## Needs a display, since it renders.

const MOD := "user://mods/voxel3d"
const VIEW := Vector2i(880, 600)

var _frame: SubViewport = null
var _renderer: Control = null
## Handed over on the first FRAME rather than during setup. `set_view` frames the
## camera and pins both battlers, and `unproject_position` on a camera whose
## viewport has not drawn yet answers with an engine error per call. Nothing is
## lost by waiting: `_process` re-frames and re-pins every frame anyway.
var _view: Dictionary = {}
var _out: String = ""
var _frames: int = 0
## Enough for the viewport to have drawn, the atlas to have landed and the
## arena's ease to have settled on its solved seat.
var _hold: int = 12


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 6:
		print("usage: <cache> <group> <number> <cell x> <cell y> <out.png>"
			+ " [facing 0-3] [time 0-3] [player species] [enemy species]"
			+ " [hold frames] [hp 0-1] [anim index] [anim frame]"
			+ " [enemy turn 0-1] [background half 0-1] [moment]"
			+ " [doll none|enemy|player|both] [unown form 1-26]")
		quit(1)
		return
	var data: GameData = GameData.open_directory(args[0])
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

	var context := Gen2BattleWorldContext.new()
	context.map_id = Vector2i(map.group, map.number)
	context.tileset = map.tileset
	context.player_cell = Vector2i(int(args[3]), int(args[4]))
	context.player_facing = clampi(int(args[6]) if args.size() > 6 else 0, 0, 3)
	context.time_of_day = clampi(int(args[7]) if args.size() > 7 else 1, 0, 3)

	_frame = SubViewport.new()
	_frame.size = VIEW
	_frame.transparent_bg = false
	_frame.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_frame)

	_renderer = (load("%s/battle/renderer.gd" % MOD) as GDScript).new()
	_frame.add_child(_renderer)
	_renderer.set_native_size(VIEW)
	if not _renderer.set_battle_data(data):
		print("no battle hud in ", args[0])
		quit(1)
		return
	_renderer.set_world_context(context)

	# The health is an argument because the bars are drawn from it and their
	# palette turns on how much of the bar is lit, so a full bar and a red one are
	# two different pictures of the same panel.
	var share: float = clampf(float(args[11]) if args.size() > 11 else 1.0, 0.0, 1.0)
	_view = {
		"battle_kind": &"wild",
		"enemy_species": int(args[9]) if args.size() > 9 else 16,
		"enemy_name": "PIDGEY",
		"enemy_level": 7,
		"enemy_hp": int(round(22.0 * share)),
		"enemy_max_hp": 22,
		"player_species": int(args[8]) if args.size() > 8 else 155,
		"player_name": "CYNDAQUIL",
		"player_level": 9,
		"player_hp": int(round(27.0 * share)),
		"player_max_hp": 27,
		"hud_visible": true,
		"exp_pixels": 20,
	}
	_hold = maxi(int(args[10]) if args.size() > 10 else 12, 2)

	var doll: String = args[17] if args.size() > 17 else "none"
	_view["enemy_substitute"] = doll == "enemy" or doll == "both"
	_view["player_substitute"] = doll == "player" or doll == "both"

	var shiny: String = args[19] if args.size() > 19 else "none"
	_view["enemy_shiny"] = shiny == "enemy" or shiny == "both"
	_view["player_shiny"] = shiny == "player" or shiny == "both"

	var form: int = clampi(int(args[18]) if args.size() > 18 else 0, 0, 26)
	if form > 0:
		_view["enemy_species"] = RomLayout.UNOWN_SPECIES
		_view["player_species"] = RomLayout.UNOWN_SPECIES
		_view["enemy_name"] = "UNOWN"
		_view["player_name"] = "UNOWN"
	_view["enemy_unown_form"] = form
	_view["player_unown_form"] = form

	var moment: String = args[16] if args.size() > 16 else "fight"
	var battlers: Dictionary = _battlers(moment, data)
	if battlers.is_empty():
		print("no battler moment ", moment)
		quit(1)
		return
	_view["battlers"] = battlers
	# The intro's own staging, and only the intro's: a state past the entrance is
	# a fight in colour with nobody standing behind the opponent's square.
	if moment in INTRO_MOMENTS:
		# True for the whole of the intro, which is what the screen answers.
		_view["grayscale"] = true
		_view["battle_kind"] = &"trainer"
		_view["trainer_class"] = TRAINER_CLASS
		_view["player_backpic_palette"] = PLAYER_BACKPIC
		# The two panels arrive with the Pokemon they describe, so neither is up
		# while a trainer is still standing on the square.
		_view["enemy_hud_visible"] = \
			StringName(battlers["enemy"]["kind"]) == &"mon"
		_view["player_hud_visible"] = \
			StringName(battlers["player"]["kind"]) == &"mon"
		# `BattleStart_TrainerHuds`, which is up for the whole opening of a
		# trainer fight and empty the moment it starts.
		_view["trainer_hud_balls"] = _hud_balls()
		_view["trainer_hud_border"] = _hud_border()

	var anim_index: int = int(args[12]) if args.size() > 12 else 0
	if anim_index > 0:
		_load_anim(
			data, anim_index,
			int(args[13]) if args.size() > 13 else 0,
			bool(int(args[14])) if args.size() > 14 else false,
			bool(int(args[15])) if args.size() > 15 else true
		)


## The player's own picture, and a class to stand opposite it. Neither is read
## off a save here: this tool builds a view rather than running a battle.
const PLAYER_BACKPIC: String = "chris"
## The moments `Gen2BattleScreen` runs before the fight starts.
const INTRO_MOMENTS: PackedStringArray = ["slide", "stand", "sent", "walkoff"]
const TRAINER_CLASS: int = 1


## `BattleStart_TrainerHuds`' party balls and the frame they hang in, off
## `Gen2BattleScreen`'s own constants rather than a second copy of them. A full
## team of six a side, since a tool has no party to count.
func _hud_balls() -> Array:
	var out: Array = []
	for player_side: bool in [false, true]:
		var at: Vector2i = Gen2BattleScreen.HUD_BALL_AT[player_side]
		var step: int = int(Gen2BattleScreen.HUD_BALL_STEP[player_side])
		for slot: int in Gen2Party.MAX_SIZE:
			out.append({
				"x": at.x + slot * step, "y": at.y,
				"tile": Gen2BattleScreen.HUD_BALL_NORMAL,
			})
	return out


func _hud_border() -> Array:
	var out: Array = []
	for player_side: bool in [false, true]:
		var at: Vector2i = Gen2BattleScreen.HUD_BORDER_AT[player_side]
		var tiles: Array = Gen2BattleScreen.HUD_BORDER_TILES[player_side]
		var direction: int = 1 if player_side else -1
		var edge: int = Gen2BattleScreen.HUD_BORDER_EDGE
		out.append({"x": at.x, "y": at.y, "tile": int(tiles[0])})
		out.append({"x": at.x, "y": at.y + 1, "tile": int(tiles[1])})
		for index: int in edge:
			out.append({
				"x": at.x - (index + 1) * direction, "y": at.y + 1,
				"tile": int(tiles[3]),
			})
		out.append({
			"x": at.x - (edge + 1) * direction, "y": at.y + 1, "tile": int(tiles[2]),
		})
	return out


## One settled side of the block, which every moment builds from.
func _mon_side(species: int) -> Dictionary:
	return {
		"kind": &"mon", "backpic": "", "trainer_class": 0, "species": species,
		"visible": true, "offset_pixels": Vector2.ZERO, "scale": Vector2.ONE,
	}


## One named moment of `view["battlers"]`, which is `Gen2BattleScreen`'s own
## shape. The slide's displacement comes from `Gen2BattleIntro` rather than from
## a number chosen here, so a picture is where the cartridge would have put it.
func _battlers(moment: String, data: GameData) -> Dictionary:
	var trainer := {
		"kind": &"trainer", "backpic": PLAYER_BACKPIC, "trainer_class": 0,
		"species": 0, "offset_pixels": Vector2.ZERO,
	}
	var foe := {
		"kind": &"trainer", "backpic": "", "trainer_class": TRAINER_CLASS,
		"species": 0, "offset_pixels": Vector2.ZERO,
	}
	var mon := {
		"kind": &"mon", "backpic": "", "trainer_class": 0,
		"species": int(_view["enemy_species"]), "offset_pixels": Vector2.ZERO,
	}
	match moment:
		"fight":
			# Every view of a live fight carries a battlers block, settled or
			# not, so this is the default: photographing the pair any other way
			# takes a path the game never reaches.
			return {
				"player": _mon_side(int(_view["player_species"])),
				"enemy": mon,
			}
		"slide":
			var intro: Gen2BattleIntro = Gen2BattleIntro.for_data(data)
			for _step: int in intro.frames() / 2:
				intro.advance_frame()
			trainer["offset_pixels"] = Vector2(intro.player_offset(), 0.0)
			foe["offset_pixels"] = Vector2(intro.enemy_offset(), 0.0)
			return {"player": trainer, "enemy": foe}
		"stand":
			return {"player": trainer, "enemy": foe}
		"sent":
			return {
				"player": trainer,
				"enemy": {
					"kind": &"none", "backpic": "", "trainer_class": 0,
					"species": 0, "offset_pixels": Vector2.ZERO,
				},
			}
		"faint":
			# `MonFaintedAnimation`: seven steps of one tile row, and the whole
			# sink is the picture's own seven rows.
			mon["offset_pixels"] = Vector2(
				0.0, float(Gen2BattleScreenMap.FAINT_ROWS * Gen2Tiles.TILE_WIDTH) * 0.5
			)
			return {"player": _mon_side(int(_view["player_species"])), "enemy": mon}
		"gone":
			# `BattleBGEffect_HideMon`, which is what a Fly or a Dig leaves behind.
			var hidden: Dictionary = _mon_side(int(_view["player_species"]))
			hidden["visible"] = false
			return {"player": hidden, "enemy": mon}
		"recall":
			# `BattleBGEffect_RunPicResizeScript` part way through a return.
			var shrinking: Dictionary = _mon_side(int(_view["player_species"]))
			shrinking["scale"] = Vector2(0.4, 0.4)
			return {"player": shrinking, "enemy": mon}
		"walkoff":
			trainer["offset_pixels"] = Vector2(
				-float(Gen2Tiles.TILE_WIDTH * 4), 0.0
			)
			return {"player": trainer, "enemy": mon}
	return {}


## Runs one of the cartridge's own move animations to a chosen frame and puts
## what it left in OAM into the view, which is exactly what `Gen2BattleScreen`
## does with the same two calls on every frame of a move.
##
## FRAME 0 finds the busiest frame itself, by running the script once and
## keeping where the sprite count peaked, then running a fresh player back to
## that point. A player cannot be rewound, which is why it is built twice.
## [param background] is the animation's BACKGROUND half, the whole-screen flash
## the seven palette maps carry. It is on by default and switching it off is what
## makes a before and after of the same frame exact, since a flash lasts a frame
## or two and no neighbouring frame is the same picture.
func _load_anim(
	data: GameData, index: int, frame: int, enemy_turn: bool, background: bool = true
) -> void:
	var anim_data: Gen2BattleAnimData = Gen2BattleAnimData.from_game_data(data)
	if anim_data == null:
		print("no battle anim data in this cache")
		return
	const SEARCH: int = 90
	if frame <= 0:
		var scout: Gen2BattleAnimPlayer = Gen2BattleAnimPlayer.create(
			anim_data, index, enemy_turn, 0
		)
		if scout == null:
			print("no anim script ", index)
			return
		var best: int = 0
		for step: int in SEARCH:
			if not scout.advance_frame():
				break
			if (scout.sprites() as Array).size() > best:
				best = (scout.sprites() as Array).size()
				frame = step + 1
		if frame <= 0:
			print("anim ", index, " draws no sprites in ", SEARCH, " frames")
			return

	var player: Gen2BattleAnimPlayer = Gen2BattleAnimPlayer.create(
		anim_data, index, enemy_turn, 0
	)
	if player == null:
		print("no anim script ", index)
		return
	for _step: int in frame:
		if not player.advance_frame():
			break
	_view["anim_sprites"] = player.sprites()
	_view["anim_tiles"] = player.tiles()
	# The BACKGROUND half of the same frame. Seven palettes carrying one byte is
	# the whole-screen flash, and about a sixth of every move's frames have one:
	# without this the view says the screen is never flashing and the pass over
	# the picture cannot be photographed at all.
	var maps: PackedByteArray = player.background().bg_palette_maps
	if background:
		_view["bg_palette_maps"] = maps
		_view["ob_palette_maps"] = player.background().ob_palette_maps
	# THE SCANLINE WOBBLE, built the way `battle_screen.gd:_anim_raster` builds
	# it: the animation's own `hSCX` and `hSCY` on every line, replaced by the
	# scanline table wherever it has opened a window on that register. Without it
	# the view says no move ever wobbles, and the camera shake this drives cannot
	# be checked at all. A still cannot SHOW a shake; what it can show is that the
	# shot moved between two frames of the same move, which is the whole of what
	# there is to verify.
	#
	# Both axes, because most of the screen shakes are sideways: `WobbleScreen`,
	# `Tackle` and `BodySlam` write `hSCX` and leave `hSCY` alone.
	var scene: Gen2BattleAnimBackground = player.background()
	var across: PackedInt32Array = _wobble(scene, Gen2BattleAnimBackground.LCDC_SCX)
	var down: PackedInt32Array = _wobble(scene, Gen2BattleAnimBackground.LCDC_SCY)
	_view["raster_scx"] = across
	_view["raster_scy"] = down
	var shake := Vector2(_shake_of(across), _shake_of(down))
	# `BattleAnimClearHud` takes the panels and both bars off for the length of a
	# move, so a shot of one that leaves them up is not a picture of the game.
	_view["hud_visible"] = false
	var written: String = ""
	for slot: int in maps.size():
		written += "%02x " % maps[slot]
	print("anim ", index, " frame ", frame, ": ",
		(player.sprites() as Array).size(), " sprites, bg pals ", written,
		", shake ", "%.2f, %.2f" % [shake.x, shake.y], " hardware px")


## One register's scanline table: the animation's own scroll on every line,
## replaced by the window wherever it has opened one on that register.
func _wobble(scene: Gen2BattleAnimBackground, register: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var base: int = scene.scx if register == Gen2BattleAnimBackground.LCDC_SCX \
		else scene.scy
	var windowed: bool = scene.lcdc_pointer == register
	if base == 0 and not windowed:
		return out
	out.resize(Gen2BattleAnimBackground.SCREEN_LINES)
	for line: int in Gen2BattleAnimBackground.SCREEN_LINES:
		out[line] = int(scene.ly_overrides[line]) if windowed else base
	return out


## The same mean the renderer takes, so the number printed here is the number the
## camera is shaken by.
func _shake_of(rows: PackedInt32Array) -> float:
	if rows.is_empty():
		return 0.0
	var total: float = 0.0
	for row: int in rows:
		total += float(row if row < 128 else row - 256)
	return -total / float(rows.size())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_renderer.set_view(_view)
	if _frames < _hold:
		return false
	_frame.get_texture().get_image().save_png(_out)
	print(_out)
	return true
