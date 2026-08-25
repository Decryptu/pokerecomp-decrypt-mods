extends Control

## The fight staged on the map it was started on, shot over the player's
## shoulder, with the Game Boy's own panels over the top.
##
## `Gen2BattleScreen` owns the battle, the events and the text box and decides
## nothing about how any of it is drawn. It hands over display values and, once per
## battle, a `Gen2BattleWorldContext` saying where the encounter happened, which is
## all this needs: the same mesher the overworld uses rebuilds the map from its
## records and the battlers stand on it as cards.
##
## Two layers, because a battle is two things at once. The map is geometry at
## window resolution; the panels, bars and text box are hardware pixels at
## whole-number scale over the top. Answering `uses_hardware_viewport` false is what
## makes the first possible and the second this renderer's job.
##
## A battle started outside the world gets no context and is drawn on the flat
## field the panels already imply.

const Options: GDScript = preload("../options.gd")
const Steering: GDScript = preload("../steering.gd")
const Frost: GDScript = preload("panel.gd")
const Anim: GDScript = preload("anim.gd")

## Preloaded for the reason `world/renderer.gd` gives: nothing holds the shape
## tree between two battles, so loading it per fight re-parsed it per fight.
const Profile: GDScript = preload("../shape/profile.gd")
const TileShapeScript: GDScript = preload("../shape/tile_shape.gd")
const MapSourceScript: GDScript = preload("../shape/map_source.gd")
const AtlasScript: GDScript = preload("../shape/atlas.gd")
const MesherScript: GDScript = preload("../shape/mesher.gd")
const ArenaScript: GDScript = preload("arena.gd")
const DioramaScript: GDScript = preload("../world/diorama.gd")

const CELL: float = 16.0

## How opaque the screen draws the FIELD of its own text box over this view, and
## the same judgement the overworld makes: the frame's lines and the glyphs are
## ink and stay solid, so the prompt reads exactly as well and the fight is still
## visible behind it. Every prompt in a battle is that one box.
##
## The panels above it are this renderer's own and are tinted separately; see
## PANEL_TINT.
const FIELD_OPACITY: float = 0.75
## How tall the background map a scanline offset is measured into is, in
## hardware pixels. `Gen2Raster.scroll_rows` takes the same number.
const RASTER_WRAP: int = 256

var _data: GameData = null
var _view: Dictionary = {}
var _context: Gen2BattleWorldContext = null

var _stage: RefCounted = null
var _arena: RefCounted = null
## How long each held camera control has been held, which is what turns a stick
## from a step into a glide. See `steering.gd:Glide`.
var _held := Steering.Glide.new()
var _atlas: RefCounted = null
var _mesher: RefCounted = null
var _profile: GDScript = null
var _tile_shape_script: GDScript = null
var _map_source_script: GDScript = null

## The two HUD blocks, in hardware tiles, and how far past the drawing their
## backing reaches. Derived from `Gen2BattleHud`'s own positions: the enemy's
## name, level and bar sit between column 1 and its edge tile, the player's
## between its bottom-left corner and the right edge, with the exp bar sunk into
## the last row.
const ENEMY_PANEL := Rect2i(1, 0, 11, 4)
const PLAYER_PANEL := Rect2i(9, 7, 11, 5)
const PANEL_PAD: int = 2

## How solid the backing is over the world behind it.
##
## The cartridge draws its panels as black glyphs straight onto the white field:
## the field IS the backing. Take it away and put a route under it and the name,
## level and HP numbers are black on grass. So each block gets a light one, light
## because an opaque slab is the white field again under another name.
##
## What is behind it is blurred rather than merely tinted, which stops a dithered
## path competing with the writing without making the backing more solid.
## `panel.gd` is that pass.
const PANEL_TINT := Color(1.0, 1.0, 1.0, 0.52)

var _hud: Gen2BattleHud = null
var _panels_backing: Array[ColorRect] = []
var _frost: RefCounted = null
var _hud_layers: Array[TextureRect] = []
## The move animation's OAM layer, over everything: the hardware draws its
## objects above the background plane the panels and both pictures live in.
var _anim: RefCounted = null
var _anim_layer: TextureRect = null
## Where each battler actually landed against the hardware slot the rig was
## solved for, in HARDWARE pixels. Zero but for the drift, and it is what keeps
## an effect on the animal it was aimed at. See `_measure_anim_drift`.
var _anim_player_drift := Vector2.ZERO
var _anim_enemy_drift := Vector2.ZERO
## Both offsets the layer was last DRAWN at, rounded the way `anim.gd` rounds
## them, as player xy then enemy xy. A redraw is only worth doing when one of the
## four has moved a whole hardware pixel, since nothing finer reaches the
## picture.
var _anim_drawn_at := Vector4i(9999, 9999, 9999, 9999)
var _battlers: Array[TextureRect] = []
var _pic_textures: Dictionary = {}
var _native := Vector2i(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
## The hardware screen's own rectangle inside that surface, empty until a host
## pushes one. See [method _hud_scale].
var _screen_rect := Rect2i()
## How far out from the fight the map is meshed, in walk cells. Zero is all of
## it. The player's own DISTANCE setting, shared with the overworld.
var _draw_cells: int = 0


func _init() -> void:
	var modules: Dictionary = _load_modules()
	_stage = (modules["diorama"] as GDScript).new()
	add_child(_stage.container)
	# The backing goes in first, so both panels sit under every drawn layer. That
	# order is also what lets the frost read the world: a screen texture holds
	# what has been drawn so far, which here is the composited stage and nothing
	# of the HUD.
	_frost = Frost.new()
	for panel: Rect2i in [ENEMY_PANEL, PLAYER_PANEL]:
		var backing := ColorRect.new()
		backing.color = PANEL_TINT
		backing.material = _frost.material
		backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backing.set_meta(&"tiles", panel)
		add_child(backing)
		_panels_backing.append(backing)
	for index: int in HUD_LAYERS:
		var layer := TextureRect.new()
		# Nearest, or the hardware pixels stop being square on the last hop.
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(layer)
		_hud_layers.append(layer)
	# Last in, so the objects draw over the panels and both pictures, which is the
	# order the hardware draws them in. `hud_visible` is false for the length of a
	# move anyway, so mostly there is nothing under it but the fight.
	_anim_layer = TextureRect.new()
	_anim_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_anim_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_anim_layer)
	_read_options()
	Options.listen(_on_option_changed)
	Options.listen_actions(_on_action_changed)


func uses_hardware_viewport() -> bool:
	return false


## See FIELD_OPACITY. `set_text_box_rect` is deliberately not answered here: the
## rig pins each battler to its own hardware picture slot, which is what makes a
## collision with the box impossible, so there is nothing left for this view to
## compose around it.
func interface_opacity() -> float:
	return FIELD_OPACITY


## The fallback is the whole map, which is what a probe or a tool building this
## renderer outside the game wants.
func _read_options() -> void:
	_draw_cells = int(Options.value(Options.DISTANCE, 0))
	_stage.set_render_scale(int(Options.value(Options.SCALE, Options.default_scale())))
	_arena.set_wheel_sign(int(Options.value(Options.WHEEL, 1)))


func _on_option_changed(id: StringName, key: StringName, value: Variant) -> void:
	if id != Options.MOD_ID:
		return
	match key:
		Options.DISTANCE:
			_draw_cells = int(value)
			_build_arena()
		Options.SCALE:
			_stage.set_render_scale(int(value))
		Options.WHEEL:
			_arena.set_wheel_sign(int(value))
		Options.RECENTRE:
			# A button-kind setting carries no value: the press IS the message.
			_arena.steer(Steering.RESET)


## A control of this mod's own, arriving as the command it means rather than as
## an event. The same handler shape as the overworld's, because the binding is
## shared and only the rigs differ.
func _on_action_changed(id: StringName, key: StringName, pressed: bool) -> void:
	if id != Options.MOD_ID or not pressed:
		return
	_arena.steer(key)


## A control HELD rather than pressed, which is the half of the binding an edge
## cannot carry. The overworld's own wiring, and deliberately the same: what
## differs between the two views is the rig, never the binding.
func _glide(delta: float) -> void:
	var held: Dictionary = _held.notches(delta, Options.strength)
	for command: StringName in held:
		_arena.steer_by(command, float(held[command]))


func set_native_size(size_pixels: Vector2i) -> void:
	_native = size_pixels
	size = Vector2(size_pixels)
	_stage.container.size = Vector2(size_pixels)
	_layout_hud()


## Where the cartridge's own 160x144 screen sits inside this view's surface,
## beside every [method set_native_size]. See
## Gen2ModHost.RENDERER_SCREEN_RECT_METHOD and [method _hud_scale].
func set_screen_rect(rect: Rect2i) -> void:
	if rect == _screen_rect:
		return
	_screen_rect = rect
	_layout_hud()


func set_battle_data(data: GameData) -> bool:
	_data = data
	if data == null:
		return false
	_hud = Gen2BattleHud.from_data(data)
	_anim = Anim.new(data)
	return _hud != null


## Where the battle is being fought, handed over once, after set_battle_data and
## before the first view. Optional on both sides: a battle with no world behind
## it never calls this and the arena stays the flat field.
func set_world_context(context: Gen2BattleWorldContext) -> void:
	_context = context
	_build_arena()


func set_view(view: Dictionary) -> void:
	_view = view
	refresh()


func refresh() -> void:
	_frame_camera()
	# Before the battlers are placed, since it is what they are drawn through.
	_stage.set_flash(_view.get("bg_palette_maps", []))
	# `LostBattle`'s wash: the cartridge greys every background palette for the
	# length of the intro, so it is the STAGE that wears it here rather than the
	# two battlers, which are only two of the things inside it.
	_stage.set_grayscale(bool(_view.get("grayscale", false)))
	_place_battlers()
	_measure_anim_drift()
	_draw_hud()
	_draw_anim()


## Steering the shot. The battle screen claims its own keys first, so what
## arrives here is what the fight has no use for.
func handle_battle_input(event: InputEvent) -> bool:
	return _arena.handle_input(event)


## Framed every frame rather than only when the tween is running, so no ordering
## between the context, the first view and the tree can leave the shot stale.
func _process(delta: float) -> void:
	_glide(delta)
	_arena.advance(delta)
	_frame_camera()
	_place_battlers()
	# The OAM picture is a fact about the view and does not change here; where its
	# sprites SIT follows the drift, so it is redrawn only when that has moved a
	# whole hardware pixel.
	_measure_anim_drift()
	_follow_anim_drift()


func _load_modules() -> Dictionary:
	_profile = Profile
	_tile_shape_script = TileShapeScript
	_map_source_script = MapSourceScript
	_atlas = AtlasScript.new()
	_arena = ArenaScript.new()
	return {"diorama": DioramaScript}


## The map the battle started on, rebuilt from its records.
##
## The context names the map and its tileset by number and deliberately hands
## over no handle on the world, so this resolves them through the GameData it was
## already given and meshes them exactly as the overworld does.
func _build_arena() -> void:
	if _data == null or _context == null:
		_stage.set_terrain([])
		_stage.set_water([])
		_stage.set_tufts([])
		_arena.stage(null)
		return
	var map: Gen2WorldMap = _data.world_map(_context.map_group(), _context.map_number())
	var tileset: Gen2WorldTileset = _data.world_tileset(_context.tileset)
	if map == null or tileset == null:
		_stage.set_terrain([])
		_stage.set_water([])
		_stage.set_tufts([])
		_arena.stage(null)
		return

	# The GameData with it, so the border ring past this map's edge can follow a
	# connection into the neighbouring map the way the overworld's does.
	var source: RefCounted = _map_source_script.new(null, map, tileset, _data)
	_stage.set_time_of_day(_context.time_of_day)
	if _atlas.build(_data, map, tileset, _context.time_of_day):
		_stage.set_texture(_atlas.texture)
		# A fight indoors is shot against the room's own walls, not against sky.
		if source.outside():
			_stage.set_background(_atlas.background(), true, _atlas.sky_ramp())
		else:
			_stage.set_background(_atlas.void_color(), false)
	# Resolved whole and emitted around the fight. A fight does not move, so the
	# window is built once and never recentred; the sight lines the arena is
	# chosen by read the resolved heights, which are the whole map's whatever is
	# drawn of it.
	_mesher = _resolved_for(map, tileset, source)
	_stage.set_view_distance(float(_draw_cells) * CELL)
	_stage.set_terrain(_mesher.emit(_atlas, _window(_context.player_cell)))
	# The water and the stamped models too, or a fight on a route is staged in a
	# clearing on a blue floor: neither is in the terrain mesh, a tree because it
	# is instanced and a lake because it is drawn with its own material.
	_stage.set_water(_mesher.take_water())
	_bank()
	_stage.set_tufts(_mesher.take_tufts())
	_stage.set_models(_mesher.take_models())
	# Staged AFTER the mesh, because choosing where the fight goes asks how tall
	# the things around it turned out to be, and only the mesh knows that.
	_arena.stage(_context, source, _mesher)
	# The arena has just moved, so the shot has to. Waiting for the next view
	# leaves the camera wherever it was last framed, which before any battle is
	# the map's own origin: a corner of the map with the fight nowhere in it.
	_frame_camera()
	_place_battlers()


## The map resolved, from a fight earlier in the same session. Resolving is the
## third of a build that does not depend on where anything is standing, and it is
## kept per installation of this script so it survives the renderer being rebuilt
## between fights.
##
## Only the battle caches. The overworld resolves from the live world, which
## `changeblock` rewrites under the player, and a cache with no word about that
## would draw a boulder that has been pushed away.
static var _resolved: Dictionary = {}
const RESOLVED_KEPT: int = 2


func _resolved_for(
	map: Gen2WorldMap, tileset: Gen2WorldTileset, source: RefCounted
) -> RefCounted:
	var key: String = "%d,%d,%d" % [map.group, map.number, tileset.number]
	if _resolved.has(key):
		return _resolved[key]
	var mesher: RefCounted = MesherScript.new()
	mesher.resolve(source, _tile_shape_script.new(_profile, tileset.number))
	if _resolved.size() >= RESOLVED_KEPT:
		_resolved.erase(_resolved.keys()[0])
	_resolved[key] = mesher
	return mesher


## The rectangle of map the fight is drawn out of, in TILES, or empty for the
## whole of it at FULL distance.
##
## The battle's lens is a 23.6 degree cone across a 46 pixel frame, so what it
## can see of a map is a narrow wedge and a window costs the shot far less than
## it costs the overworld's wide one.
func _window(cell: Vector2i) -> Rect2i:
	if _draw_cells <= 0:
		return Rect2i()
	var span: int = _draw_cells * 2 + 1
	return Rect2i(
		(cell - Vector2i(_draw_cells, _draw_cells)) * RomLayout.MAP_BLOCK_CELL_WIDTH,
		Vector2i(span, span) * RomLayout.MAP_BLOCK_CELL_WIDTH
	)


func _frame_camera() -> void:
	_arena.set_shake(_raster_shake())
	_stage.camera.fov = _arena.fov(_frame_stretch())
	_stage.aim_camera(_arena.eye(), _arena.target())


## A move animation's scanline wobble, read as one displacement.
##
## `raster_scy` is the background's vertical scroll, one value per scanline, asked
## for only by a battle animation. A flat screen answers it row by row; a diorama
## has no rows, so what is taken is how far the picture has moved, which the arena
## shakes the whole shot by.
##
## An offset is a distance to look down into a background map 256 pixels tall, so
## the top half of that range is a shift up and the rest wraps as a shift down. The
## mean over the rows the window covers is the displacement.
func _raster_shake() -> float:
	var rows: PackedInt32Array = PackedInt32Array(_view.get("raster_scy", []))
	if rows.is_empty():
		return 0.0
	var total: int = 0
	for row: int in rows:
		total += row if row < RASTER_WRAP / 2 else row - RASTER_WRAP
	return -float(total) / float(rows.size())


## How much taller the stage is than the hardware screen drawn over it.
##
## The stage fills the window; the panels fill a 160x144 rectangle at a whole
## number of window pixels per hardware pixel, centred in it. Stretching the lens
## by the difference is what makes one window pixel mean the same thing on both
## layers, so a battler pinned to its patch of ground lands in the hardware slot
## the rig was solved for at every window size instead of only at the ones where
## the two happen to coincide.
func _frame_stretch() -> float:
	return float(_native.y) / float(Gen2Screen.HEIGHT * _hud_scale())


## The two battlers, and the opposing trainer behind theirs.
##
## Each picture is pinned to its patch of ground and drawn in hardware pixels where
## that patch projects to, at the size the cartridge drew it. That keeps a battler
## crisp, and the rig was solved to land those patches in the hardware's own picture
## slots, so nothing here wanders under a panel.
##
## What stands on each square is the host's answer: see [method _place_entrance].
## A view built by a probe or a tool carries no entrance and takes the settled
## pair.
func _place_battlers() -> void:
	_stage.begin_shadow_casters()
	var entrance: Variant = _view.get("entrance", null)
	var slot: int = _place_entrance(entrance as Dictionary) \
		if entrance is Dictionary else _place_settled()
	for index: int in range(slot, _battlers.size()):
		_battlers[index].visible = false
	_stage.end_shadow_casters()


## The fight does not open with two Pokemon on the field, and for one release this
## view opened with exactly that.
##
## Two trainers slide in from opposite sides, the opponent sends out first, the
## player's picture walks off, and a ball puts a Pokemon where each was standing.
## `view["entrance"]` is that state resolved for a renderer with no background plane
## to read it off: what each square holds and how far the picture stands from its
## resting place. See `docs/MODS.md` in pokerecomp.
##
## The displacement is spent in hardware pixels across the screen rather than as a
## walk over the ground: the cartridge slides a picture, not a person.
##
## The opponent standing behind their Pokemon for the rest of the fight is this
## view's own staging and waits for the send-out, since during the entrance the
## class picture is on the square the Pokemon will take.
func _place_entrance(entrance: Dictionary) -> int:
	var enemy: Dictionary = entrance.get("enemy", {})
	var player: Dictionary = entrance.get("player", {})
	var slot: int = 0
	if StringName(enemy.get("kind", ENTRANCE_NONE)) == ENTRANCE_MON \
			and StringName(_view.get("battle_kind", &"wild")) == &"trainer":
		slot = _pin(
			slot, _trainer_pic(int(_view.get("trainer_class", 0))),
			_arena.enemy_trainer_ground()
		)
	slot = _pin(
		slot, _entrance_pic(enemy, false), _arena.enemy_ground(),
		Vector2(enemy.get("offset_pixels", Vector2.ZERO))
	)
	return _pin(
		slot, _entrance_pic(player, true), _arena.player_ground(),
		Vector2(player.get("offset_pixels", Vector2.ZERO))
	)


## Both Pokemon on their squares and the opponent behind theirs, which is every
## frame of a fight past its entrance and the whole of what a hand-built view
## from `tools/battle_shot.gd` ever asks for.
func _place_settled() -> int:
	var slot: int = 0
	if StringName(_view.get("battle_kind", &"wild")) == &"trainer":
		slot = _pin(
			slot, _trainer_pic(int(_view.get("trainer_class", 0))),
			_arena.enemy_trainer_ground()
		)
	slot = _pin(slot, _battler_pic(false), _arena.enemy_ground())
	return _pin(slot, _battler_pic(true), _arena.player_ground())


## What one side's square holds. `none` is the stretch between a trainer walking
## off and the ball arriving, and it is a state only the opponent's side reaches
## at a frame boundary: `SendOutMonText` ends in `done`, so the player's last
## slide column and the stamp land in one frame.
const ENTRANCE_NONE: StringName = &"none"
const ENTRANCE_TRAINER: StringName = &"trainer"
const ENTRANCE_MON: StringName = &"mon"


## `entrance` is in every view of a live fight, so this is the path a settled
## frame takes as well and the doll has to be reachable from it: `species` here
## is the same field the substitute flag is keyed against.
func _entrance_pic(side: Dictionary, back: bool) -> Texture2D:
	match StringName(side.get("kind", ENTRANCE_NONE)):
		ENTRANCE_MON:
			return _battler_pic(back) if int(side.get("species", 0)) > 0 else null
		ENTRANCE_TRAINER:
			if back:
				return _backpic(String(side.get("backpic", "")))
			return _trainer_pic(int(side.get("trainer_class", 0)))
	return null


## The player's own picture, which is a person and not a species: `chris`,
## `kris` or the catching tutorial's `dude`.
##
## The colours are a field of their own, because the Dude has none: the
## cartridge draws him in the player's, which is what `player_backpic_palette`
## carries and why it is not simply the pic's own name.
func _backpic(kind: String) -> Texture2D:
	if _data == null or kind.is_empty():
		return null
	var colors: String = String(_view.get("player_backpic_palette", kind))
	var dmg: int = _palette_map(PAL_BG_PLAYER)
	return _texture(
		"b%s:%s:%d:%d" % [kind, colors, dmg, 1 if _graying() else 0],
		_data.player_backpic(kind),
		_battler_palette(_data.player_palette(colors), dmg),
	)


## One picture standing on [param ground], its feet at that point and its middle
## over it, at a whole-number scale so a Game Boy pixel stays square.
##
## The place is the stage's and not the panels': a pinned picture belongs to the
## patch of ground under it. Both layers are centred on the same window and the rig
## frames the same world height, so a battler landing on its ground point also lands
## in the hardware slot the rig was solved for.
##
## [param offset] is how far the picture stands from that patch, in hardware pixels
## across the screen, and is zero outside an entrance. A picture part way off the
## field casts nothing, since the sun sees a card standing on the ground.
func _pin(
	slot: int, texture: Texture2D, ground: Vector3, offset: Vector2 = Vector2.ZERO
) -> int:
	if texture == null:
		return slot
	var at: Vector2 = _stage.camera.unproject_position(ground)
	var drawn := Vector2(texture.get_size()) * float(_hud_scale())
	var rect: TextureRect = _battler(slot)
	rect.texture = texture
	rect.size = drawn
	rect.position = at - Vector2(drawn.x * 0.5, drawn.y) + offset * float(_hud_scale())
	rect.visible = true
	if offset.is_zero_approx():
		_stage.add_shadow_caster(texture, ground, _caster_scale(ground, texture.get_height()))
	return slot + 1


## How big a card standing on [param ground] has to be for the sun to see the same
## silhouette the player does: the world height whose projection is the
## [param height] hardware pixels the picture is drawn at.
##
## Measured through the camera rather than derived, since the answer moves with
## every zoom, climb and swing, and solved twice because a pitched camera changes
## depth up the card's own length. One correction is enough at these sizes.
func _caster_scale(ground: Vector3, height: int) -> float:
	var wanted: float = float(height * _hud_scale())
	var per_pixel: float = 1.0
	for _step: int in 2:
		var top: Vector3 = ground + Vector3(0.0, float(height) * per_pixel, 0.0)
		var projected: float = _stage.camera.unproject_position(ground).y \
			- _stage.camera.unproject_position(top).y
		if projected < 0.001:
			return per_pixel
		per_pixel *= wanted / projected
	return per_pixel


func _battler(slot: int) -> TextureRect:
	while slot >= _battlers.size():
		var rect := TextureRect.new()
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Under the panels, over the map: the hardware draws its pictures into
		# the same background layer the panels sit on top of.
		add_child(rect)
		move_child(rect, 1 + _battlers.size())
		_battlers.append(rect)
	return _battlers[slot]


## The DMG palette byte a move animation last left on one side of the field.
##
## The cartridge draws both battler pictures on the background layer, out of
## `bg_map`, so what permutes a pic is a background palette map and not an object
## one: slot 0 is the player's and slot 1 the enemy's. `BattleAnim_SetBGPals`
## writes one byte across all seven and flashes the whole screen, where
## `BGEffects_LoadPlayerPals` writes only this slot. Over the cartridge's own
## animations the one-sided case is 1463 frames of 20956, half as much again as the
## whole-screen flash.
##
## Exact rather than restated, because a pic IS four palette entries and the
## permutation is a lookup among them. Only the world is approximated: see
## `world/frame.gd`.
const PAL_BG_PLAYER: int = 0
const PAL_BG_ENEMY: int = 1
const PALETTE_IDENTITY: int = 0xE4


func _palette_map(slot: int) -> int:
	var maps: Variant = _view.get("bg_palette_maps", null)
	if maps is PackedByteArray:
		var bytes: PackedByteArray = maps
		return bytes[slot] if slot < bytes.size() else PALETTE_IDENTITY
	if maps is Array:
		var list: Array = maps
		return int(list[slot]) if slot < list.size() else PALETTE_IDENTITY
	return PALETTE_IDENTITY


## What a battler's picture is actually drawn in: `_CGB_BattleGrayscale`'s own
## four levels for the length of the intro, and the pristine palette permuted by
## the animation's last `BattleAnimRequestPals` byte after it. The stage wears
## the grey as a pass over the whole picture; the cards are a layer above that
## pass and so carry it in their own colours instead.
func _battler_palette(pristine: PackedColorArray, dmg: int) -> PackedColorArray:
	if _graying():
		return _data.battle_grayscale_palette()
	return _remap(pristine, dmg)


func _graying() -> bool:
	return bool(_view.get("grayscale", false)) and _data != null


## `CopyPals`: colour i of the result is colour `(byte >> i * 2) & 3` of the
## pristine palette, which is why a remap never compounds.
static func _remap(palette: PackedColorArray, dmg: int) -> PackedColorArray:
	if dmg == PALETTE_IDENTITY or palette.is_empty():
		return palette
	var out := PackedColorArray()
	for index: int in palette.size():
		out.append(palette[mini((dmg >> (index * 2)) & 3, palette.size() - 1)])
	return out


## One battler's picture, cropped to what it fills and cut out of its field, so
## it stands on the map rather than in a white box.
##
## The permutation is part of the cache KEY, not applied over the texture: a
## remap is a different set of four colours and cutting the field out of it is
## the same work either way, and a move plays through a handful of distinct bytes
## rather than a new one per frame.
func _pic(species: int, back: bool) -> Texture2D:
	if _data == null or species <= 0:
		return null
	var form: int = int(_view.get("player_unown_form" if back else "enemy_unown_form", 0))
	var dmg: int = _palette_map(PAL_BG_PLAYER if back else PAL_BG_ENEMY)
	# `_GetFrontpic`'s own branch: Unown is drawn out of its own atlas by letter
	# and everything else out of the species table. That atlas counts from zero
	# and a letter counts from one, which is the subtraction.
	var unown: bool = species == RomLayout.UNOWN_SPECIES and form > 0
	var shiny: bool = _shiny(back)
	return _texture(
		"%d:%d:%d:%d:%d:%d" % [
			species, form, 1 if back else 0, dmg,
			1 if _graying() else 0, 1 if shiny else 0,
		],
		_data.unown_pic(form - 1, back) if unown else _data.species_pic(species, back),
		_battler_palette(_data.palette(species, shiny), dmg),
	)


## `CGB_BattleColors` reads `CheckShininess` on both sides, so a shiny is drawn
## in its own palette rather than the species table's.
func _shiny(back: bool) -> bool:
	return bool(_view.get("player_shiny" if back else "enemy_shiny", false))


## One side's picture, which is the doll rather than the animal while a
## substitute is up. `SPRITE_MONSTER`'s own overworld strip is what the cartridge
## builds that doll out of, so the battle draws a walking sprite.
func _battler_pic(back: bool) -> Texture2D:
	var species: int = int(_view.get("player_species" if back else "enemy_species", 0))
	if bool(_view.get("player_substitute" if back else "enemy_substitute", false)):
		return _substitute_pic(species, back)
	return _pic(species, back)


## `GetSubstitutePic`: four tiles of the monster sprite in an otherwise blank
## box. The doll is drawn in whichever battler palette its box sits in, since
## the cartridge writes none of its own for it, so the species it stands in for
## is part of the key.
func _substitute_pic(species: int, back: bool) -> Texture2D:
	if _data == null:
		return null
	var dmg: int = _palette_map(PAL_BG_PLAYER if back else PAL_BG_ENEMY)
	var shiny: bool = _shiny(back)
	var key: String = "sub:%d:%d:%d:%d:%d" % [
		species, 1 if back else 0, dmg, 1 if _graying() else 0, 1 if shiny else 0
	]
	if _pic_textures.has(key):
		return _pic_textures[key]

	var side: int = Gen2BattleScreenMap.PLAYER_SIDE if back \
		else Gen2BattleScreenMap.ENEMY_SIDE
	var box: int = side * SUBSTITUTE_TILE
	var pixels: PackedByteArray = Gen2BattleRenderer.substitute_pixels(
		_data.overworld_sprite_indices(SUBSTITUTE_SPRITE), back
	)
	if pixels.size() < box * box:
		return null
	var image: Image = _image(
		pixels, box, box, _battler_palette(_data.palette(species, shiny), dmg)
	)
	if image == null:
		return null
	var texture: Texture2D = ImageTexture.create_from_image(image)
	_pic_textures[key] = texture
	return texture


## `SPRITE_MONSTER` in `constants/sprite_constants.asm`, the same number in both
## pins, and the tile the doll's box is measured in.
const SUBSTITUTE_SPRITE: int = 0x4C
const SUBSTITUTE_TILE: int = 8


## The opposing trainer's own picture, in the cartridge's art. A class number is
## what the pic and the palette are both keyed on, and a wild battle carries
## class 0, which is what makes this answer nothing there.
func _trainer_pic(trainer_class: int) -> Texture2D:
	if _data == null or trainer_class <= 0:
		return null
	var dmg: int = _palette_map(PAL_BG_ENEMY)
	return _texture(
		"t%d:%d:%d" % [trainer_class, dmg, 1 if _graying() else 0],
		_data.trainer_pic(trainer_class),
		_battler_palette(_data.trainer_palette(trainer_class), dmg),
	)


func _texture(key: String, pic: Dictionary, palette: PackedColorArray) -> Texture2D:
	if _pic_textures.has(key):
		return _pic_textures[key]
	var image: Image = _cut_out(pic, palette)
	if image == null:
		return null
	var texture: Texture2D = ImageTexture.create_from_image(image)
	_pic_textures[key] = texture
	return texture


## The pic with its field removed, rather than its background colour.
##
## A battle pic is drawn on the white field, and the field is colour index 0. So is
## every white inside the drawing: an eye highlight, a tooth, a Marill's belly. So
## making index 0 transparent wherever it appears punches holes through the animal.
##
## What is outside is not a colour but a region: the index 0 connected to the edge
## of the picture. Flooding in from the border through index 0 alone stops at the
## drawing's own black outline, so highlights sealed inside it survive. A drawing
## whose silhouette touches the border keeps the corner the flood cannot reach.
func _cut_out(pic: Dictionary, palette: PackedColorArray) -> Image:
	if pic.is_empty() or not pic.has("atlas"):
		return null
	var sheet: String = String(pic["atlas"])
	var atlas: Dictionary = _data.atlas(sheet)
	var indices: PackedByteArray = _data.atlas_indices(sheet)
	var cell: int = int(atlas.get("cell", 0))
	var columns: int = int(atlas.get("columns", 0))
	var atlas_width: int = int(atlas.get("width", 0))
	var slot: int = int(pic.get("slot", -1))
	if cell <= 0 or columns <= 0 or atlas_width <= 0 or slot < 0:
		return null
	var width: int = mini(int(pic.get("width", cell)), cell)
	var height: int = mini(int(pic.get("height", cell)), cell)
	if width <= 0 or height <= 0:
		return null

	var left: int = (slot % columns) * cell
	@warning_ignore("integer_division")
	var top: int = (slot / columns) * cell
	var pixels := PackedByteArray()
	pixels.resize(width * height)
	for y: int in height:
		var from: int = (top + y) * atlas_width + left
		if from + width > indices.size():
			break
		for x: int in width:
			pixels[y * width + x] = indices[from + x]

	return _image(pixels, width, height, palette)


## An index buffer coloured, its field cut away and the result trimmed to what
## is actually drawn. A pic sits in the top-left of a cell sized for the largest
## of its kind, and the doll sits in the middle of a box that is otherwise
## empty, so a card standing on its cell would stand on blank rows and the
## figure would float above the ground.
func _image(
	pixels: PackedByteArray, width: int, height: int, palette: PackedColorArray
) -> Image:
	var field: PackedByteArray = _field(pixels, width, height)
	var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y: int in height:
		for x: int in width:
			var at: int = y * width + x
			var index: int = int(pixels[at])
			var color: Color = palette[index] if index < palette.size() else Color.MAGENTA
			if field[at] == 1:
				color.a = 0.0
			image.set_pixel(x, y, color)

	var used: Rect2i = image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return null
	return image.get_region(used)


## The index 0 reachable from the border, four-connected: everything the drawing
## does not enclose.
func _field(pixels: PackedByteArray, width: int, height: int) -> PackedByteArray:
	var field := PackedByteArray()
	field.resize(width * height)
	var stack := PackedInt32Array()
	for x: int in width:
		stack.append(x)
		stack.append((height - 1) * width + x)
	for y: int in height:
		stack.append(y * width)
		stack.append(y * width + width - 1)

	while not stack.is_empty():
		var at: int = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		if field[at] == 1 or pixels[at] != 0:
			continue
		field[at] = 1
		@warning_ignore("integer_division")
		var y: int = at / width
		var x: int = at % width
		if x > 0:
			stack.append(at - 1)
		if x < width - 1:
			stack.append(at + 1)
		if y > 0:
			stack.append(at - width)
		if y < height - 1:
			stack.append(at + width)
	return field


## The panels and the three bars, each in its own palette because the hardware
## gives every background tile one: a green HP bar sits inside a panel of black
## text without either being a separate rectangle.
##
## `hud_visible` is false for the length of a move animation, which is
## `BattleAnimClearHud` taking all four off the map.
##
## The two panels arrive one at a time, which is why each has its own layer: an
## entrance puts the opponent's panel up on the send-out and the player's only once
## the ball has landed. `enemy_hud_visible` and `player_hud_visible` are the host's
## answer per side, against `hud_visible`'s summary of both. A view carrying neither
## is a settled fight and takes both.
const HUD_ENEMY_PANEL: int = 0
const HUD_PLAYER_PANEL: int = 1
const HUD_ENEMY_BAR: int = 2
const HUD_PLAYER_BAR: int = 3
const HUD_EXP_BAR: int = 4
const HUD_LAYERS: int = 5


func _draw_hud() -> void:
	if _hud == null:
		return
	var up: bool = bool(_view.get("hud_visible", true))
	var enemy_up: bool = up and bool(_view.get("enemy_hud_visible", true))
	var player_up: bool = up and bool(_view.get("player_hud_visible", true))
	_panels_backing[0].visible = enemy_up
	_panels_backing[1].visible = player_up

	var enemy_hp: int = int(_view.get("enemy_hp", 0))
	var enemy_max_hp: int = int(_view.get("enemy_max_hp", 0))
	var player_hp: int = int(_view.get("player_hp", 0))
	var player_max_hp: int = int(_view.get("player_max_hp", 0))
	var ink: PackedColorArray = Gen2Palette.pic_palette(
		PackedColorArray([Color.WHITE, Color.BLACK])
	)

	if enemy_up:
		var panel: PackedByteArray = _buffer()
		_hud.draw_enemy(
			panel, Gen2Screen.WIDTH, String(_view.get("enemy_name", "")),
			int(_view.get("enemy_level", 0))
		)
		_show(HUD_ENEMY_PANEL, panel, ink)
		var enemy_bar: PackedByteArray = _buffer()
		_hud.draw_hp_bar(
			enemy_bar, Gen2Screen.WIDTH, Gen2BattleHud.ENEMY_BAR, enemy_hp, enemy_max_hp
		)
		_show(HUD_ENEMY_BAR, enemy_bar, _hp_palette(enemy_hp, enemy_max_hp))
	else:
		_hud_layers[HUD_ENEMY_PANEL].texture = null
		_hud_layers[HUD_ENEMY_BAR].texture = null

	if player_up:
		var panel: PackedByteArray = _buffer()
		_hud.draw_player(
			panel, Gen2Screen.WIDTH, String(_view.get("player_name", "")),
			int(_view.get("player_level", 0)), player_hp, player_max_hp
		)
		_show(HUD_PLAYER_PANEL, panel, ink)
		var player_bar: PackedByteArray = _buffer()
		_hud.draw_hp_bar(
			player_bar, Gen2Screen.WIDTH, Gen2BattleHud.PLAYER_BAR, player_hp, player_max_hp
		)
		_show(HUD_PLAYER_BAR, player_bar, _hp_palette(player_hp, player_max_hp))
		var gained: PackedByteArray = _buffer()
		_hud.draw_exp_bar(gained, Gen2Screen.WIDTH, int(_view.get("exp_pixels", 0)))
		_show(HUD_EXP_BAR, gained, _data.bar_palette("exp"))
	else:
		_hud_layers[HUD_PLAYER_PANEL].texture = null
		_hud_layers[HUD_PLAYER_BAR].texture = null
		_hud_layers[HUD_EXP_BAR].texture = null


## The move animation, over everything. `anim.gd` turns the view's OAM into one
## hardware-sized picture and this lays it on at the same whole-number scale the
## panels are drawn at, so an animation pixel and a panel pixel are the same
## size.
##
## The drift correction is inside the picture rather than on the layer, so the
## layer itself always sits on the hardware screen's own origin. See `anim.gd`
## for why one offset for the whole layer would be no offset at all.
func _draw_anim() -> void:
	if _anim_layer == null:
		return
	var image: Image = null
	if _anim != null:
		image = _anim.image(_view, _anim_player_drift, _anim_enemy_drift)
	if image == null:
		_anim_layer.texture = null
		_anim_drawn_at = Vector4i(9999, 9999, 9999, 9999)
		return
	_anim_layer.texture = ImageTexture.create_from_image(image)
	_anim_drawn_at = _anim_rounded()
	_layout_anim()


func _layout_anim() -> void:
	if _anim_layer == null:
		return
	var factor: int = _hud_scale()
	_anim_layer.size = Vector2(Gen2Screen.WIDTH * factor, Gen2Screen.HEIGHT * factor)
	_anim_layer.position = _hud_origin()


## How far each battler landed from its OWN mark, in HARDWARE pixels.
##
## Measured through the camera rather than assumed zero. It IS zero on a still
## shot, to within the hundredth of a pixel the rig solves to, and that is the
## whole reason an animation can be drawn at the hardware's own coordinates in
## the first place: this only tracks what the drift adds afterwards. Measured
## over a whole period of both drift terms, neither exceeds 1.2 px.
func _measure_anim_drift() -> void:
	if _arena == null or _stage == null or _stage.camera == null:
		return
	var factor: float = float(_hud_scale())
	var origin: Vector2 = _hud_origin()
	_anim_enemy_drift = (_stage.camera.unproject_position(_arena.enemy_ground()) - origin) \
		/ factor - _arena.ENEMY_MARK
	_anim_player_drift = (_stage.camera.unproject_position(_arena.player_ground()) - origin) \
		/ factor - _arena.PLAYER_MARK


## A redraw costs forty eight-pixel blits, so it is spent only when the drift has
## actually moved the picture: rounded to hardware pixels, nothing finer reaches
## it. Nothing at all happens on a frame with no animation up, which is every
## frame outside a move.
func _follow_anim_drift() -> void:
	if _anim_layer == null or _anim_layer.texture == null:
		return
	if _anim_rounded() != _anim_drawn_at:
		_draw_anim()


func _anim_rounded() -> Vector4i:
	var player: Vector2 = _anim_player_drift.round()
	var enemy: Vector2 = _anim_enemy_drift.round()
	return Vector4i(int(player.x), int(player.y), int(enemy.x), int(enemy.y))


func _buffer() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(Gen2Screen.WIDTH * Gen2Screen.HEIGHT)
	return out


## Index 0 is transparent on every layer: a panel is a shape over the map, not a
## rectangle of white across it.
func _show(index: int, indices: PackedByteArray, palette: PackedColorArray) -> void:
	_hud_layers[index].texture = ImageTexture.create_from_image(
		Gen2PicImage.from_indices(
			indices, Gen2Screen.WIDTH, Gen2Screen.HEIGHT, palette, true
		)
	)
	_layout_layer(_hud_layers[index])


## The hardware screen at the largest whole-number scale that fits, centred. A
## fractional scale would put a Game Boy pixel across a screen pixel boundary and
## the panels would shimmer as the window resized.
func _layout_hud() -> void:
	for layer: TextureRect in _hud_layers:
		_layout_layer(layer)
	_layout_anim()
	# The frost reaches the same number of HARDWARE pixels at every window size,
	# so it does not sharpen as the window grows.
	if _frost != null:
		_frost.set_scale(_hud_scale())
	for backing: ColorRect in _panels_backing:
		var tiles: Rect2i = backing.get_meta(&"tiles")
		var factor: int = _hud_scale()
		var pad: float = float(PANEL_PAD * factor)
		backing.size = Vector2(tiles.size * Gen2BattleHud.TILE * factor) + Vector2(pad, pad) * 2.0
		backing.position = _hud_origin() \
			+ Vector2(tiles.position * Gen2BattleHud.TILE * factor) - Vector2(pad, pad)


func _layout_layer(layer: TextureRect) -> void:
	var factor: int = _hud_scale()
	layer.size = Vector2(Gen2Screen.WIDTH * factor, Gen2Screen.HEIGHT * factor)
	layer.position = _hud_origin()


## Window pixels per hardware pixel, and where the hardware screen's corner sits on
## this surface. Everything laid out in the cartridge's coordinates goes through
## these two: the panels, both bars, the text, the battlers and the OAM layer.
##
## The host owns both. A fight staged on the map fills the window, so the surface is
## no longer a whole multiple of 160x144 and centring the hardware screen in it is
## not this renderer's arithmetic: the host centres it in a buffer built out of whole
## map blocks and pushes the answer. Working it out here put the panels at seven
## window pixels per hardware pixel where the host's text box was drawn at six.
##
## The fallback is what a renderer built outside the game gets: a probe and
## `tools/battle_shot.gd` push no rectangle, and there the surface IS the screen.
func _hud_scale() -> int:
	if _screen_rect.size.y >= Gen2Screen.HEIGHT:
		@warning_ignore("integer_division")
		return maxi(1, _screen_rect.size.y / Gen2Screen.HEIGHT)
	@warning_ignore("integer_division")
	return maxi(1, mini(
		_native.x / Gen2Screen.WIDTH, _native.y / Gen2Screen.HEIGHT
	))


func _hud_origin() -> Vector2:
	if _screen_rect.size.y >= Gen2Screen.HEIGHT:
		return Vector2(_screen_rect.position)
	var factor: int = _hud_scale()
	var drawn := Vector2(Gen2Screen.WIDTH * factor, Gen2Screen.HEIGHT * factor)
	return ((Vector2(_native) - drawn) * 0.5).floor()


## An HP bar is green, yellow or red by how much of it is lit rather than by the
## hit points behind it, which is the rule the games use.
func _hp_palette(hp: int, max_hp: int) -> PackedColorArray:
	var lit: int = Gen2BattleHud.bar_pixels(
		hp, max_hp, Gen2BattleHud.HP_BAR_TILES * Gen2BattleHud.TILE
	)
	return _data.bar_palette(GameData.hp_bar_palette_name(lit))


## The bank and the shore's colours, handed over together because they are one
## look: `world/water.gd` is where they are read and `shape/mesher.gd:bank_field`
## is where the field is baked, with the resolve rather than per frame. This costs
## a texture handle and three colours.
func _bank() -> void:
	var shore: PackedColorArray = _atlas.shore_colors()
	if shore.size() == 2:
		_stage.set_shore_colors(_atlas.background(), shore[0], shore[1])
	_stage.set_bank(
		_mesher.bank_field(), _mesher.bank_world(), _mesher.bank_origin(),
		_mesher.bank_span()
	)
