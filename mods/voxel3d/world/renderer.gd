extends Control

## The world drawn as a voxel diorama instead of a tile page.
##
## Nothing about the world requires the view to be 2D. Maps are node-free
## records, each tileset is one addressable atlas, animated tiles replace atlas
## slots rather than map rectangles, and collision is a permission byte per walk
## cell. This reads exactly what the built-in renderer reads and builds geometry
## out of it, textured from the same tileset art and coloured with the same
## palette rows, so a Johto route looks like a Johto route with no art shipped
## here at all.
##
## It answers [code]uses_hardware_viewport[/code] false, so it gets the screen's
## rectangle at window resolution rather than a 160x144 buffer. Text boxes and
## menus stay hardware pixels over the top: the world gains resolution, the
## interface stays a Game Boy.
##
## It reads the world and never writes it. That is what lets `V` swap the two
## views mid-step without either one being able to tell the other what changed.

const Options: GDScript = preload("../options.gd")
const Steering: GDScript = preload("../steering.gd")

## PRELOADED, NOT LOADED ON THE PRESS. Nothing holds these between two views, so
## a `load()` in `_init` re-parsed the whole shape tree every time the player
## switched to this one: 200 ms of parsing on the frame `V` was pressed, and
## again on the next press. The host holds this script from registration to
## shutdown, and a preload is held with it, so the parsing happens once at load
## and a switch pays for none of it.
const Profile: GDScript = preload("../shape/profile.gd")
const TileShapeScript: GDScript = preload("../shape/tile_shape.gd")
const MapSourceScript: GDScript = preload("../shape/map_source.gd")
const AtlasScript: GDScript = preload("../shape/atlas.gd")
const MesherScript: GDScript = preload("../shape/mesher.gd")
const CameraRigScript: GDScript = preload("camera_rig.gd")
const DioramaScript: GDScript = preload("diorama.gd")
const TransitionScript: GDScript = preload("transition.gd")

const CELL: float = 16.0
## A graphics tile, which is what a mesh window is measured in.
const TILE: float = 8.0

## How opaque the screen draws the FIELD of its own text box over this view.
##
## The cartridge draws that box opaque because the field behind it is opaque
## white; over a map it is a slab across the bottom third of the screen. The
## frame's lines and the glyphs are ink and stay solid whatever this asks for, so
## the text is exactly as readable and the map is still there behind it. See
## Gen2ModHost.RENDERER_INTERFACE_OPACITY_METHOD.
const FIELD_OPACITY: float = 0.75

var _world: Gen2WorldAPI = null
var _animation: Gen2WorldAnimation = null
var _time_of_day: int = Gen2WorldPalette.TIME_MORNING

var _stage: RefCounted = null
var _atlas: RefCounted = null
var _mesher: RefCounted = null
var _rig: RefCounted = null
## How long each held camera control has been held, which is what turns a stick
## from a step into a glide. See `steering.gd:Glide`.
var _held := Steering.Glide.new()
var _shape: RefCounted = null
var _profile: GDScript = null
var _tile_shape_script: GDScript = null
var _map_source_script: GDScript = null

var _actor_textures: Dictionary = {}
var _pulse_textures: Dictionary = {}
## The sprites other mods put in the world, resolved by the host into the same
## `Gen2WorldSprite` the map's own objects carry. Null where the host is older
## than the actor layer, which is the only reason this view checks for one.
var _mod_actors: Gen2WorldActors = null
## Visible populations already arrive above. This handle is only the live
## cartridge shiny animation that has to be placed in the 3D scene.
var _encounters: Gen2WorldEncounters = null
## The tileset the shape resolver was built for. A warp to a map sharing it still
## rebuilds the mesh, because the block grid is what changed; this only says
## whether the resolver has to be replaced too.
var _shape_tileset: int = -1

## How far out the mesh is built, in walk cells, and the cell the built window is
## centred on. Zero cells is the whole map and no window at all;
## [constant Vector2i.MAX] is nothing built yet.
var _draw_cells: int = 0
var _window_centre := Vector2i.MAX
## Whether the map being drawn is out of doors, which decides both how far the
## ground runs past its edge and whether there is a sky behind it at all.
var _outside: bool = true

## How much of a frame the geometry may take while a build is in flight, in
## microseconds. A town is 200 ms whole, which is a visible stop on every warp
## and at the start of every fight; spread over a few frames at four milliseconds
## it is a build nobody can point at. What is already on screen keeps being drawn
## while it runs, so the cost of slicing is that the new map arrives a moment
## late rather than that anything flickers.
const BUILD_BUDGET_USEC: int = 4000
## And what it may take while there is NOTHING on screen yet, which is the frame
## `V` was pressed on and the first frames of a warp. The budget protects a
## picture that is already being drawn; where there is none, a smooth frame rate
## over an empty stage is worth nothing and the map arriving three times sooner
## is worth the whole of it.
const FIRST_BUILD_BUDGET_USEC: int = 12000
## Whether a slice is in flight, the chunks it has finished so far, and whether
## anything at all is on screen to keep drawing meanwhile. A warp has nothing, so
## a warp shows each chunk as it lands and the map fills in rather than showing a
## hole.
var _building: bool = false
var _standing: bool = false
var _chunks: Array = []
## The water chunks of the same slice, kept apart because they are drawn with
## their own material: see `mesher.gd:take_water`.
var _water: Array = []
var _tufts: Array = []
## The live text box in HARDWARE pixels and the hardware screen's own rectangle
## in this surface's, which are the two halves of one question: see
## [method _apply_text_box]. The screen's rectangle is empty until a host pushes
## one, which is what a probe, a tool and a framed screen all leave it at.
var _text_box := Rect2i()
var _screen_rect := Rect2i()
## Whether a screen laid out in 160x144 owns the picture.
var _interface_masked: bool = false
## `DoBattleTransition` over the map. See `world/transition.gd`.
var _transition: RefCounted = null
## Which of the map's sprites the transition is still drawing, and the object it
## names when that is the battlers alone. `RespawnPlayerAndOpponent` at each
## outro's setup leaves the player and whoever `hLastTalked` names in OAM and
## nothing else, and the two views have to agree about that.
var _transition_sprites: int = Gen2BattleTransition.SPRITES_ALL
var _transition_opponent: int = -1
## The two palette orders that can be in force at once: a map or script fade,
## and the transition's own flash. See [method _apply_flash].
var _fade_order: int = Gen2WorldPalette.FADE_IDENTITY
var _transition_order: int = Gen2BattleTransition.IDENTITY
## The ground the slice in flight will cover, in world pixels, handed to the far
## field only when that slice is published: see `_advance_build`. Until then the
## mesh on screen is the one the OLD hole was cut for.
var _pending_hole := Rect2()


func _init() -> void:
	var modules: Dictionary = _load_modules()
	_stage = (modules["diorama"] as GDScript).new()
	add_child(_stage.container)
	# After the stage, so the cartridge's own cells are over the world they are
	# closing on.
	_transition = TransitionScript.new()
	add_child(_transition.layer)
	_read_options()
	# On the press rather than by polling: the host owns the surfaces the player
	# changes a setting on, and says so.
	Options.listen(_on_option_changed)
	Options.listen_actions(_on_action_changed)


## This view is not made of hardware pixels, so it asks for the layer that is not
## either. See Gen2ModHost.RENDERER_SURFACE_METHOD.
func uses_hardware_viewport() -> bool:
	return false


## The field of the screen's own text box, drawn through rather than over the
## map. See FIELD_OPACITY.
func interface_opacity() -> float:
	return FIELD_OPACITY


## Where that box is, in HARDWARE pixels, on every change and empty when none is
## up. A box covers the bottom third of the screen and the player stands in the
## middle of it, so the shot is pushed up the frame by half of what the box takes
## and the player is in the middle of what is left. The pan eases like any other
## steer. See Gen2ModHost.RENDERER_TEXT_BOX_METHOD.
##
## Kept, because where a hardware pixel LANDS moves with the surface: see
## [method set_screen_rect].
func set_text_box_rect(rect: Rect2i) -> void:
	_text_box = rect
	_apply_text_box()


## Where the cartridge's own 160x144 screen sits inside this view's surface, in
## that surface's pixels, beside every [method set_native_size]. See
## Gen2ModHost.RENDERER_SCREEN_RECT_METHOD.
##
## FRAMED, THE SURFACE WAS THE SCREEN: it was a whole multiple of 160x144, so a
## hardware pixel landed at a fixed scale from its own corner and nothing had to
## say where. A surface that fills the window is not, and every hardware-pixel
## number handed over is a number about that rectangle rather than about this
## one.
func set_screen_rect(rect: Rect2i) -> void:
	_screen_rect = rect
	_transition.place(_screen_place())
	_apply_text_box()
	_apply_interface_mask()


## One frame of `DoBattleTransition`. See `world/transition.gd` for the picture
## and Gen2ModHost's own notes for the rest of what arrives with it.
##
## [param order] is `StartTrainerBattle_Flash` writing `wBGP` and calling
## `DmgToCgbBGPals` alone, which is a permutation over the background's four
## levels and exactly what `frame.gd` already restates for a move animation's
## whole-screen flash. The seven backgrounds carry one byte between them here, so
## the same pass answers both.
func set_transition(
	cells: PackedByteArray, tiles: PackedByteArray, palette: PackedColorArray,
	sprites: int = Gen2BattleTransition.SPRITES_ALL, opponent: int = -1,
	order: int = Gen2BattleTransition.IDENTITY
) -> void:
	_transition_sprites = sprites
	_transition_opponent = opponent
	_transition.place(_screen_place())
	## The ball's own colours take the order too. `StartTrainerBattle_Flash`
	## writes one `wBGP` across the background, so what the flash does to the
	## world under this layer has to happen to the layer as well or the ball is
	## the one thing on screen the flash never reaches. The stage's own pass
	## cannot do it: `frame.gd` runs on the container, and this is drawn over it.
	_transition.set_frame(
		cells, tiles, Gen2WorldPalette.fade_palette(palette, order)
	)
	_transition_order = order
	_apply_flash()


func clear_transition() -> void:
	_transition_sprites = Gen2BattleTransition.SPRITES_ALL
	_transition_opponent = -1
	_transition.clear()
	_transition_order = Gen2BattleTransition.IDENTITY
	_apply_flash()


## ONE STEP OF A MAP FADE, which is the warp's own white or black and the five
## script specials beside it. See Gen2ModHost.RENDERER_FADE_METHOD.
##
## The same permutation over the background's four levels the transition writes,
## through the same pass: `FADE_OUT_ORDERS` ends at `$00`, every level taken to
## the brightest, and `FADE_TO_BLACK_ORDERS` at `$FF`, every level to the
## darkest, so the curve carries a fade to white and a fade to black without a
## case for either.
##
## [param white_fill] is `FillWhiteBGColor`, which flattens the tile page's
## colour 0 on the way out. A diorama has no colour 0 to flatten: it has a lit
## picture, and the order above has already taken every level of it to white by
## the step that runs. Nothing here to do, and reading it would only be a second
## answer to the same question.
func set_fade(order: int, white_fill: bool = false) -> void:
	if order == _fade_order:
		return
	_fade_order = order
	_apply_flash()


## The two orders that can be in force at once, spent as one. The 2D view
## composes them exactly this way in `flood_palette`: the fade first and the
## transition over it.
func _apply_flash() -> void:
	_stage.set_flash(_flash_bytes(_compose_orders(_fade_order, _transition_order)))


## Applying [param first] and then [param second], as one order. Each is a
## permutation of the four background levels packed two bits to a level, so the
## composition takes level i to `first[second[i]]`.
static func _compose_orders(first: int, second: int) -> int:
	if first == Gen2BattleTransition.IDENTITY:
		return second
	if second == Gen2BattleTransition.IDENTITY:
		return first
	var out: int = 0
	for level: int in 4:
		var through: int = (second >> (level * 2)) & 3
		out |= ((first >> (through * 2)) & 3) << (level * 2)
	return out


## The background palette order as the seven-entry map `frame.gd` reads, since
## a fade and a transition each write one byte across the lot.
static func _flash_bytes(order: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(7)
	out.fill(order & 0xFF)
	return out


## A screen laid out in 160x144 has taken the picture, or given it back: the
## pack, the party, the PC, the dex, an evolution, and `DoBattleTransition`. The
## host does not paint its own letterbox over this layer, deliberately, so the
## surround is this view's to close. See
## Gen2ModHost.RENDERER_INTERFACE_MASK_METHOD and `world/frame.gd`.
func set_interface_masked(masked: bool) -> void:
	_interface_masked = masked
	_apply_interface_mask()


func _apply_interface_mask() -> void:
	_stage.set_interface_mask(_screen_rect, _interface_masked)


## The hardware screen's rectangle on this surface, or the whole surface where no
## host has said: a renderer built outside the game has one surface and it is the
## screen. The mask reads [member _screen_rect] itself, because a surround with
## nothing outside it is nothing to close.
func _screen_place() -> Rect2i:
	if _screen_rect.size.x > 0 and _screen_rect.size.y > 0:
		return _screen_rect
	return Rect2i(Vector2i.ZERO, Vector2i(_stage.container.size))


## The pan the live text box asks for, in the SURFACE'S own pixels, since that is
## what the camera frames. Framed, the screen is the surface and this is the
## fraction it always was.
## WHETHER THERE IS A BOX TO PAN FOR IS A HARDWARE QUESTION and is answered
## here rather than in the rig: no box at all and a box whose top row is the
## screen's own are both nothing to move for, and both are `position.y` at zero
## in the cartridge's coordinates whatever surface they land on.
func _apply_text_box() -> void:
	var height: float = _stage.container.size.y
	if _text_box.size.y <= 0 or _text_box.position.y <= 0:
		_rig.pan_for_text_box(0.0, float(Gen2Screen.HEIGHT))
		return
	if _screen_rect.size.y <= 0 or height <= 0.0:
		_rig.pan_for_text_box(float(_text_box.position.y), float(Gen2Screen.HEIGHT))
		return
	var per_pixel: float = float(_screen_rect.size.y) / float(Gen2Screen.HEIGHT)
	_rig.pan_for_text_box(
		float(_screen_rect.position.y) + float(_text_box.position.y) * per_pixel,
		height, per_pixel
	)


func set_native_size(size_pixels: Vector2i) -> void:
	size = Vector2(size_pixels)
	_stage.container.size = Vector2(size_pixels)
	_transition.place(_screen_place())
	_apply_text_box()
	_apply_interface_mask()


## The sprites registered world actors ask for, handed over once when the view
## is created. A follower is one of these, and it is drawn as a card on the cell
## it names like everything else standing on the map.
func set_actors(actors: Gen2WorldActors) -> void:
	_mod_actors = actors


func set_encounters(encounters: Gen2WorldEncounters) -> void:
	_encounters = encounters


func set_world(world: Gen2WorldAPI, animation: Gen2WorldAnimation = null) -> void:
	_world = world
	_animation = animation
	_actor_textures.clear()
	_pulse_textures.clear()
	_rebuild()


func set_time_of_day(time_of_day: int) -> void:
	_time_of_day = clampi(time_of_day, 0, 3)
	_actor_textures.clear()
	_stage.set_time_of_day(_time_of_day)
	_stage.far_field().set_time_of_day(_time_of_day)
	# The atlas carries the palette rows, so the whole sheet moves with the clock
	# and the geometry is not touched.
	if _build_atlas():
		_stage.set_texture(_atlas.texture)


## A tileset animation command rewrote one or two atlas slots. Repainting them
## moves every instance of that tile across the whole mesh at once, which is what
## the hardware does; the 2D view's per-cell overdraw is the port's answer to the
## same problem, not the cartridge's.
func refresh_animation() -> void:
	if _world == null:
		return
	if _atlas.refresh_animation(
		_world.data, _world.current_map, _world.current_tileset,
		_time_of_day, _animation
	):
		_apply_background()


func refresh() -> void:
	_frame_camera()
	_rebuild_actors()


## Camera pitch and distance, which is input the world screen has no use for and
## therefore hands over. See Gen2ModHost.RENDERER_INPUT_METHOD.
##
## Implemented here rather than in `_input`: a node in the tree is offered events
## before the screen decides what it needs, so reading them directly would race
## the gameplay keys instead of taking what is left of them.
func handle_world_input(event: InputEvent) -> bool:
	return _rig.handle_input(event)


## The camera is framed every frame rather than only on refresh, because the
## player's position carries a fractional in-flight step, and the actors are
## rebuilt with it so a walk frame advances while a step is being drawn.
func _process(delta: float) -> void:
	_glide(delta)
	_rig.advance(delta)
	_advance_build()
	_recentre_window()
	_frame_camera()
	_rebuild_actors()


## The fallbacks are what a renderer built outside the game gets: a probe or a
## survey tool never ran the entry script, and wants the whole map rather than a
## window around a player it does not have.
func _read_options() -> void:
	_draw_cells = int(Options.value(Options.DISTANCE, 0))
	_stage.set_render_scale(int(Options.value(Options.SCALE, Options.default_scale())))
	_rig.set_wheel_sign(int(Options.value(Options.WHEEL, 1)))
	_rig.set_default_pitch(float(Options.value(Options.CAMERA, Options.CAMERA_VALUES[1])))
	_stage.set_depth_of_field(dof_mode, dof_radius, dof_near, dof_far)


func _on_option_changed(id: StringName, key: StringName, value: Variant) -> void:
	if id != Options.MOD_ID:
		return
	match key:
		Options.DISTANCE:
			_draw_cells = int(value)
			# Straight to the emit: how far the mesh reaches is the only thing
			# that changed, and what a tile is was resolved once for this map.
			_window_centre = Vector2i.MAX
			_recentre_window()
		Options.SCALE:
			_stage.set_render_scale(int(value))
		Options.WHEEL:
			_rig.set_wheel_sign(int(value))
		Options.CAMERA:
			_rig.set_default_pitch(float(value))
		Options.RECENTRE:
			# A button-kind setting carries no value: the press IS the message.
			_rig.steer(Steering.RESET)


## A control of this mod's own, arriving as the command it means rather than as
## an event. Whether a key, a pad button, a stick past its deadzone or a finger
## on the on-screen pad produced it is the host's business.
func _on_action_changed(id: StringName, key: StringName, pressed: bool) -> void:
	if id != Options.MOD_ID or not pressed:
		return
	_rig.steer(key)


## A control HELD rather than pressed, which is the half of the binding an edge
## cannot carry. `steering.gd` owns how far a hold is worth and the rig owns what
## the command means; this is only the wiring between them.
func _glide(delta: float) -> void:
	var held: Dictionary = _held.notches(delta, Options.strength)
	for command: StringName in held:
		_rig.steer_by(command, float(held[command]))


func _load_modules() -> Dictionary:
	_profile = Profile
	_tile_shape_script = TileShapeScript
	_map_source_script = MapSourceScript
	_atlas = AtlasScript.new()
	_mesher = MesherScript.new()
	_rig = CameraRigScript.new()
	return {"diorama": DioramaScript}


func _build_atlas() -> bool:
	if _world == null or _world.current_map == null or _world.current_tileset == null:
		return false
	if not _atlas.build(
		_world.data, _world.current_map, _world.current_tileset,
		_time_of_day, _animation
	):
		return false
	_apply_background()
	return true


## Out of doors the void is sky, banded from the palette's own background. Inside
## it is what lies past a wall, which is not air: see `atlas.gd:void_color`.
func _apply_background() -> void:
	if _outside:
		_stage.set_background(_atlas.background(), true)
	else:
		_stage.set_background(_atlas.void_color(), false)


func _rebuild() -> void:
	# Whatever is on screen belongs to the map being left, so it is not something
	# to keep drawing over: the next build publishes each slice as it lands.
	_building = false
	_standing = false
	if _world == null or _world.current_map == null or _world.current_tileset == null:
		_stage.set_terrain([])
		_stage.set_water([])
		_stage.set_tufts([])
		_stage.far_field().configure(null, _time_of_day, true)
		return
	var tileset: int = _world.current_tileset.number
	if _shape == null or tileset != _shape_tileset:
		_shape = _tile_shape_script.new(_profile, tileset)
		_shape_tileset = tileset
	# Asked before the atlas, because what is behind a wall depends on it.
	var source: RefCounted = _map_source_script.new(_world)
	_outside = source.outside()
	if _build_atlas():
		_stage.set_texture(_atlas.texture)
	# After the atlas, which is the sheet the far field draws the loaded map and
	# its own border block with.
	_stage.far_field().configure(_world, _time_of_day, _outside, _atlas)
	_stage.set_time_of_day(_time_of_day)
	# Resolved once per map, emitted per window: what a tile is and how tall it
	# stands is a fact about the map, and measuring it through the window would
	# make a structure's height depend on where the player was standing.
	_mesher.resolve(source, _shape)
	_window_centre = Vector2i.MAX
	_recentre_window()
	refresh()


## Rebuilds the mesh around the player when they have walked out of the middle of
## what was built, and does nothing at all at FULL distance.
##
## The margin is what keeps this off most steps: a window rebuilt every cell
## would cost more than the whole map does. Emitting is about two thirds of a
## build and resolving is the other third, so a recentre inside one map is the
## cheap part of it, and it is spread over frames on top of that: see
## `_advance_build`.
func _recentre_window() -> void:
	if _world == null or _building or _mesher.size_tiles() == Vector2i.ZERO:
		return
	if _draw_cells <= 0:
		if _window_centre == Vector2i.MAX:
			_window_centre = Vector2i.ZERO
			_stage.set_view_distance(0.0)
			_ring_on(_world.player_position_cells())
			_begin_terrain(Rect2i())
		return
	var at := Vector2i(_world.player_position_cells().floor())
	var margin: int = maxi(4, _draw_cells / 3)
	if _window_centre != Vector2i.MAX \
			and absi(at.x - _window_centre.x) <= margin \
			and absi(at.y - _window_centre.y) <= margin:
		return
	_window_centre = at
	_ring_on(_world.player_position_cells())
	var span: int = _draw_cells * 2 + 1
	_stage.set_view_distance(float(_draw_cells) * CELL, true)
	_begin_terrain(Rect2i(
		(at - Vector2i(_draw_cells, _draw_cells)) * RomLayout.MAP_BLOCK_CELL_WIDTH,
		Vector2i(span, span) * RomLayout.MAP_BLOCK_CELL_WIDTH
	))


## HOW FAR OUT A STAMPED MODEL IS STILL A SOLID, in walk cells.
##
## Past it a tree is the flat impostor, which is a tenth of the triangles: see
## `shape/mesher.gd:set_detail_ring`. Ten cells is a little past what the default
## camera frames, so everything the player is actually walking among is turned
## and what the swap can be seen happening to is already small in the frame.
##
## THIRTY FIVE, chosen off a sweep: at 20 the swap is close enough to notice
## when the camera is low, at 50 the saving is down to a third, and 35 keeps
## everything the default camera frames as a turned solid while still drawing
## two thirds less. Zero is no ring at all, which is what shipped before this.
##
## STATIC so a tool can sweep it over one scene. It is a setting when the rung
## is offered to a player.
static var solid_cells: float = 35.0

## Whether the maps on the horizon stand trees as well as ground. See
## `world/far_foliage.gd`. Measured at four per cent of the frame's triangles on
## the widest horizon in the game, against a flat page for a landscape.
static var far_trees: bool = true

## THE DEPTH OF FIELD, which is a look and not a saving: see
## `world/frame.gd:set_depth_of_field`. Coarser pixels with distance, lightly:
## enough to take the edge off a flat drawing standing where a solid stood, and
## not enough to read as a modern blur laid over a Game Boy. A soft blur was the
## other candidate and it smears along the horizon line, where the ground's
## distance runs away and the sky is sampled into it.
##
## Static for the same reason `solid_cells` is, and a setting when it lands.
static var dof_mode: int = 1
static var dof_radius: float = 4.0
static var dof_near: float = 900.0
static var dof_far: float = 2600.0


## Stands this map's own tree on the maps out past the mesh, once there is a
## mesh to take one from. See `world/far_foliage.gd`.
func _dress_far_field() -> void:
	var far: RefCounted = _stage.far_field()
	if far == null:
		return
	if not far_trees:
		far.set_far_tree(null, null)
		return
	var tree: Array = _mesher.far_tree()
	far.set_far_tree(
		tree[0] as Mesh, _stage.foliage_material(tree[1] as Texture2D)
	) if tree.size() == 2 else far.set_far_tree(null, null)


## Centres the detail ring on the EYE and not on the player.
##
## Level of detail is a fact about how far a thing is from the person looking at
## it, and the eye stands back from the player: a ring drawn round the player
## spends half of itself behind the camera, where there is nothing to see, and
## runs out close in front, which is the half of the frame that is actually
## being looked at.
##
## Only x and z matter, since the ring is a circle on the ground.
##
## IT MOVES WHEN THE WINDOW DOES and not when the camera turns, because a rebuild
## is dear and a swing is cheap and constant. So a hard swing leaves the ring
## where the last step put it until the next one. That is a real edge and it is
## why the radius wants to be generous rather than tight.
func _ring_on(cells: Vector2) -> void:
	var here := Vector3(cells.x * CELL, 0.0, cells.y * CELL)
	_mesher.set_detail_ring(here + _rig.offset(), solid_cells * CELL)


## Starts a sliced build of [param window], and finishes it in `_process`.
func _begin_terrain(window: Rect2i) -> void:
	_pending_hole = _hole_pixels(window)
	_chunks = []
	_water = []
	_tufts = []
	if not _mesher.begin_emit(_atlas, window):
		_stage.set_terrain([])
		_stage.set_water([])
		_stage.set_tufts([])
		_stage.far_field().set_hole(Rect2())
		_standing = false
		return
	_building = true
	_advance_build()


func _advance_build() -> void:
	if not _building:
		return
	var done: bool = _mesher.emit_step(
		BUILD_BUDGET_USEC if _standing else FIRST_BUILD_BUDGET_USEC
	)
	_chunks.append_array(_mesher.take_chunks())
	_water.append_array(_mesher.take_water())
	_tufts.append_array(_mesher.take_tufts())
	# Mid-build the new chunks are shown only when there is nothing else to look
	# at, because a half-built map swapped in over a whole one is a hole opening
	# in the middle of the frame rather than a map arriving.
	if done or not _standing:
		_stage.far_field().set_hole(_pending_hole)
		_stage.set_terrain(_chunks)
		_stage.set_water(_water)
		_stage.set_tufts(_tufts)
		_stage.set_models(_mesher.take_models())
	if done:
		_building = false
		_standing = true
		_dress_far_field()


func _frame_camera() -> void:
	if _world == null:
		return
	var here: Vector3 = _ground(_world.player_position_cells())
	# The grass is parted by whoever stands in it, and the position it is parted
	# around carries the in-flight fraction of a step like the camera does, so the
	# meadow opens as the player walks rather than a cell at a time.
	_stage.set_walker(here)
	_stage.camera.fov = _rig.fov()
	# A pan moves the eye and what it looks at together, so the picture slides up
	# the frame without the horizon swinging.
	var pan: Vector3 = _rig.pan()
	_stage.aim_camera(here + pan + _rig.offset(), here + pan)
	# After the aim, because where the eye looks is what decides which maps out
	# there are worth drawing at all.
	_stage.advance_far_field(here + pan)


## The ground the mesh covers, in WORLD PIXELS, which the far field leaves
## alone. An empty window is FULL distance, where the mesh emits everything it
## has: the map, its border ring and the skirt past that.
func _hole_pixels(window: Rect2i) -> Rect2:
	var bounds: Rect2i = _mesher.drawn_bounds_tiles()
	if window.size.x > 0 and window.size.y > 0:
		bounds = bounds.intersection(window)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return Rect2()
	return Rect2(Vector2(bounds.position) * TILE, Vector2(bounds.size) * TILE)


## The committed cell plus any in-flight step, so the view eases into a new cell
## instead of snapping. The logical cell still commits at the start of the step;
## the fraction is presentation only.
##
## The offset is no longer bounded to one cell: an `applymovement` commits every
## cell of its path at once, so while the trail is being drawn an actor is as
## many cells behind as it has left to walk.
func _ground(cells: Vector2) -> Vector3:
	var at := Vector3(cells.x * CELL + CELL * 0.5, 0.0, cells.y * CELL + CELL * 0.5)
	# ON WHAT IS THERE, not on the floor plane. An actor used to stand at y 0
	# whatever it was standing on, so the three Pokeballs on Elm's bench sat at the
	# lino with the bench in front of them, which reads as behind it. A bench is a
	# declared OBJECT and its tiles resolve back to the floor, so the column alone
	# cannot answer this: see `mesher.gd:surface_height_at_position`.
	if _mesher != null:
		at.y = float(_mesher.surface_height_at_position(at))
	return at


## The map's live objects, rebuilt on each frame because a script can hide, move
## or delete one between two steps, and because a walking actor changes frame
## four times a step.
func _rebuild_actors() -> void:
	if _world == null:
		return
	_stage.begin_cards()
	_stage.begin_shadow_casters()
	## A TRANSITION EMPTIES OAM AND THEN PUTS TWO SPRITES BACK, and the begin and
	## end above and below are what leaves the pool with nothing in it. See
	## [method _drawn_in_transition].
	if _transition_sprites == Gen2BattleTransition.SPRITES_NONE:
		_stage.end_cards()
		_stage.end_shadow_casters()
		return
	for object: Gen2WorldObject in _world.visible_objects():
		if not _drawn_in_transition(object.index):
			continue
		_add_actor(
			object.sprite, object.palette, object.facing, object.frame,
			Vector2(object.cell) + object.step_offset_cells(), PackedColorArray(),
			object.height_offset_pixels()
		)
	_add_actor(
		_world.player_sprite(), _world.player_palette(),
		_world.player_facing, _world.player_walk_frame(),
		_world.player_position_cells(), PackedColorArray(),
		_world.player_height_offset_pixels()
	)
	# A mod's own sprites, after the map's and the player's. Depth is the stage's
	# to decide here rather than a row order's, which is the one thing this view
	# does not have to copy from the tile page.
	if _mod_actors != null and _transition_sprites == Gen2BattleTransition.SPRITES_ALL:
		for entry: Dictionary in _mod_actors.sprites():
			_add_actor(
				entry["sprite"], 0, int(entry["facing"]), int(entry["frame"]),
				entry["position_cells"], entry.get("colors", PackedColorArray())
			)
	if _transition_sprites == Gen2BattleTransition.SPRITES_ALL:
		_add_connected_actors()
	_add_encounter_pulse()
	_stage.end_cards()
	_stage.end_shadow_casters()


## Whether a map object is still in OAM this frame. `RespawnPlayerAndOpponent`
## at each outro's setup leaves the player and whoever `hLastTalked` names and
## takes everything else off, and the built-in view obeys the same three values.
func _drawn_in_transition(index: int) -> bool:
	if _transition_sprites == Gen2BattleTransition.SPRITES_BATTLERS:
		return index == _transition_opponent
	return _transition_sprites != Gen2BattleTransition.SPRITES_NONE


## How far a person on the map next door is drawn from, in world pixels. Past
## this they are a pixel in the haze and the card costs the same as one in front
## of you.
const CONNECTED_REACH: float = 2400.0


## The people standing on the maps around this one.
##
## The host places them and marks them inert: `ReadObjectEvents` fills
## `wMapObjects` from the loaded map alone, so on the cartridge a connected
## map's people do not exist until its own load builds them. They take no step,
## run no script, answer no collision and are not talked to. They are drawn
## because the 2D view draws them and two views of one world have to agree about
## what is standing over there.
##
## Feature-detected: `api_version` gates a mod built for an older host, not a
## host older than the mod, so this is the mod's to check.
func _add_connected_actors() -> void:
	if _world == null or not _outside \
			or not _world.has_method(&"connected_map_objects"):
		return
	var here: Vector2 = _world.player_position_cells() * CELL
	for entry: Dictionary in _world.connected_map_objects():
		var object: Gen2WorldObject = entry["object"]
		var cells := Vector2(object.cell + (entry["offset"] as Vector2i))
		if here.distance_squared_to(cells * CELL) > CONNECTED_REACH * CONNECTED_REACH:
			continue
		_add_actor(object.sprite, object.palette, object.facing, object.frame, cells)


func _add_actor(
	sprite: Gen2WorldSprite, palette: int, facing: int, frame: int, cells: Vector2,
	colors: PackedColorArray = PackedColorArray(), height_offset: float = 0.0
) -> void:
	var texture: Texture2D = _actor_texture(sprite, palette, facing, frame, colors)
	if texture != null:
		var ground: Vector3 = _ground(cells)
		_stage.add_standing_card(texture, _actor_position(ground, height_offset))
		# The same drawing again, at the same size, for the sun alone: an actor
		# turns to the camera and cannot be its own caster. A jumping actor's
		# shadow stays on the ground, which is why the offset is not applied here.
		_stage.add_shadow_caster(texture, ground, 1.0)


## The host's jump offset is already in world pixels, the same unit as this
## stage. Kept separate from the ground so the shadow and camera do not rise.
func _actor_position(ground: Vector3, height_offset: float) -> Vector3:
	return ground + Vector3(0.0, height_offset, 0.0)


func _actor_texture(
	sprite: Gen2WorldSprite, palette_override: int, facing: int, frame: int,
	colors: PackedColorArray = PackedColorArray()
) -> Texture2D:
	if sprite == null or _world == null or _world.data == null:
		return null
	var palette: int = palette_override if palette_override != 0 else sprite.default_palette
	# The type is part of the key: a mon icon's row and an OverworldSprites row
	# are numbered separately, so two different drawings share a number.
	var key: String = "%d:%d:%d:%d:%d:%d:%s" % [
		sprite.sprite_type, sprite.number, palette, facing, frame, _time_of_day, str(colors),
	]
	if _actor_textures.has(key):
		return _actor_textures[key]
	# image_for applies the mirror itself, including frame 3 of down and up,
	# which frame_is_mirrored is the public answer for.
	var image: Image = Gen2WorldSprite.image_for(
		sprite,
		_world.data.overworld_icon_indices(sprite.icon_number) \
			if sprite.sprite_type == Gen2WorldSprite.TYPE_MON_ICON \
			else _world.data.overworld_sprite_indices(sprite.number),
		colors if colors.size() >= 4 \
		else _world.data.overworld_sprite_palette(palette, _time_of_day),
		facing,
		frame,
	)
	var texture: Texture2D = ImageTexture.create_from_image(image)
	_actor_textures[key] = texture
	return texture


const BATTLER_CENTRE := Vector2(
	(Gen2BattleScreenMap.ENEMY_AT.x + 0.5 * Gen2BattleScreenMap.ENEMY_SIDE) * Gen2Tiles.TILE_WIDTH,
	(Gen2BattleScreenMap.ENEMY_AT.y + 0.5 * Gen2BattleScreenMap.ENEMY_SIDE) * Gen2Tiles.TILE_HEIGHT
)


## Places each cartridge animation object around the wild Pokemon's centre. The
## 2D host uses the same battler-centre translation; screen Y becomes world Y in
## the opposite direction because height rises in the diorama.
func _add_encounter_pulse() -> void:
	if _encounters == null or _world == null or _world.data == null:
		return
	var anchor: Variant = _encounters.pulse_anchor()
	if not anchor is Vector2:
		return
	var centre: Vector3 = _ground((anchor as Vector2) / CELL) + Vector3(0.0, CELL * 0.5, 0.0)
	var window: Array = _encounters.pulse_tiles()
	var pair: Array = _encounters.pulse_battler_pair()
	for value: Variant in _encounters.pulse_sprites():
		if not value is Dictionary:
			continue
		var sprite: Dictionary = value
		var at: int = int(sprite.get("tile", 0)) - Gen2BattleAnimObject.BASE_TILE
		if at < 0 or at >= window.size() or not window[at] is Dictionary:
			continue
		var slot: Dictionary = window[at]
		if not slot.has("gfx"):
			continue
		var attributes: int = int(sprite.get("attributes", 0))
		var texture: Texture2D = _pulse_texture(
			int(slot["gfx"]), int(slot["tile"]), attributes, pair
		)
		if texture == null:
			continue
		var offset := Vector2(
			float(int(sprite.get("x", 0)) - 8),
			float(int(sprite.get("y", 0)) - 16)
		) - BATTLER_CENTRE + Vector2(4.0, 4.0)
		_stage.add_centred_card(texture, centre + Vector3(offset.x, -offset.y, 0.0))


func _pulse_texture(
	gfx: int, tile: int, attributes: int, pair: Array
) -> Texture2D:
	var key: String = "%d:%d:%d:%s" % [
		gfx, tile, attributes & (Gen2BattleAnimObject.OAM_SHARED_FLAGS
			| Gen2BattleAnimObject.OAM_PALETTE), str(pair),
	]
	if _pulse_textures.has(key):
		return _pulse_textures[key]
	var strip: PackedByteArray = _world.data.battle_anim_gfx_indices(gfx)
	@warning_ignore("integer_division")
	var width: int = strip.size() / Gen2Tiles.TILE_HEIGHT
	if width <= 0 or (tile + 1) * Gen2Tiles.TILE_WIDTH > width:
		return null
	var pixels := PackedByteArray()
	pixels.resize(Gen2Tiles.TILE_PIXELS)
	for row: int in Gen2Tiles.TILE_HEIGHT:
		var from: int = row * width + tile * Gen2Tiles.TILE_WIDTH
		for column: int in Gen2Tiles.TILE_WIDTH:
			pixels[row * Gen2Tiles.TILE_WIDTH + column] = strip[from + column]
	var image: Image = Gen2PicImage.from_indices(
		pixels, Gen2Tiles.TILE_WIDTH, Gen2Tiles.TILE_HEIGHT,
		_world.data.battle_object_palette(
			attributes & Gen2BattleAnimObject.OAM_PALETTE, pair
		), true
	)
	if (attributes & Gen2BattleAnimObject.OAM_XFLIP) != 0:
		image.flip_x()
	if (attributes & Gen2BattleAnimObject.OAM_YFLIP) != 0:
		image.flip_y()
	var texture: Texture2D = ImageTexture.create_from_image(image)
	_pulse_textures[key] = texture
	return texture
