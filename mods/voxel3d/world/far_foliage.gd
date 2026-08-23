extends RefCounted

## TREES ON THE MAPS PAST THE MESH.
##
## `far_field.gd` carries the ground out to the horizon as one flat quad a map,
## folded on the GPU off the cartridge's own block data. It is the map seen from
## above and it is completely flat, so a route that is a wood on the ground reads
## out there as a green rug: the one thing a horizon is for, a skyline, is the
## one thing it cannot draw.
##
## This stands a tree on it. Not the turned solid, which is 700 to 1200 triangles
## and out of the question for tens of maps, and not the rebuilt silhouette
## either: the CUT-OUT DRAWING, four triangles, the same one a stamp inside the
## mesh wears once it is past the detail ring. So the near wood and the far wood
## are the same picture at the same size and the seam between mesh and page is
## one more place where nothing happens.
##
## WHICH CELLS GET ONE is asked of the tileset and not of the map: whether a tile
## is a model follows from the tile id and the cell's permission and nothing
## else, so a map is walked once, cell by cell, with no flood and no measure.
## That is milliseconds against the quarter of a second a real resolve costs, and
## it is why this can be done for every map on the horizon at all.
##
## EACH DRAWING WEARS ITS OWN CARD, CUT FROM ITS OWN MAP'S SHEET.
##
## `shape/far_drawings.gd` reads which drawing stands where off a map that was
## never resolved, naming it the way the mesher names it, and
## `shape/mesher.gd:far_card_for` cuts that drawing out of that map's own tile
## sheet, which `far_field.gd` has already painted to draw the ground. So a
## conifer is a conifer out there, a short tree is a short tree, a bush is a
## bush, and a map on another tileset is drawn in its own art rather than in
## this one's.
##
## THE THREE WAYS THIS HAS BEEN WRONG are worth keeping written down, because two
## of them were released. First every cell of every far map wore ONE card, the
## biggest drawing the loaded map turned: a bush was drawn as a tree and the
## horizon was a single mass of identical canopy. Then the card was looked up by
## the TILE a drawing starts at, which is one tile of the sixteen a tree is drawn
## over, so most far cells matched nothing and the few that matched picked up
## whatever other drawing began at the same id: the skyline went flat and came
## back as bushes. A drawing is named by its whole arrangement of tiles or it is
## not named at all. And third, naming it was still not enough while the cards
## were the LOADED map's: a quarter of the far foliage in the game is a drawing
## the loaded map does not hold, and another sixteenth is on another tileset
## entirely, and all of it wore the one tree.
##
## ONE CARD PER DRAWING and not per cell, which is what the mesh does with its
## own stamps: a conifer is drawn over two cells and stands one tree between
## them, near and far alike.
##
## ONE MAP A FRAME, walked and cut. See [method _dressing].
##
## One simplification is left and is deliberate: a drawing gets one card rather
## than its own bodies, so a cell of four sea rocks is one rock out there.

## World pixels across one block, which is the tile the world past the maps is
## paved with. `far_field.gd:BLOCK_PIXELS`.
const BLOCK: float = 32.0
## HOW FAR OUT OF BOUNDS A CARD STANDS AND HOW THICKLY, as reach in world pixels
## and the lattice it stands on, in blocks.
##
## THE RING HAS TO REACH THE HORIZON or it does nothing. The flat page and a
## standing wood are different TONES, not different shapes: seen from a walking
## camera the page shows mostly the light ground its trees are drawn on and the
## cards show mostly canopy, so a ring that stops short draws a pale band across
## the distance rather than a seam. On this camera the ground runs out at about
## ten thousand world pixels, and a card on every block of that is two hundred
## thousand of them.
##
## AND IT DOES NOT HAVE TO BE THICK OUT THERE. A card is 16 pixels tall and the
## eye sits about a hundred above the ground, so at three thousand pixels it is
## seen at two degrees and hides four hundred and fifty pixels of ground behind
## it. Every eighth block still closes the distance completely; what thins is the
## count and not the picture.
##
## Four rungs doubling out to 9600 comes to about 14000 blocks against 125000 for
## the same reach paved solid, and the first rung is 1200, which is 75 walk cells
## and well past anything the camera frames.
const BORDER_RUNGS: Array = [[600.0, 1], [1200.0, 2], [2400.0, 4], [4800.0, 8]]
## How far the eye may wander from where the ring was built before it is built
## again, in world pixels, and the margin the ring carries on top of its reach so
## that wandering changes nothing.
##
## A DRIFT AND NOT A LATTICE. Quantising the centre to a grid rebuilds every time
## the player steps back and forth across one of its lines, which on a walk that
## turns round is once a second; a circle round the last centre has no lines to
## cross.
const BORDER_STEP: float = 512.0
## How many maps' worth of cards and stamps are held at once. Past it the lot is
## dropped and cut again as they are asked for, one map a frame, which is
## `far_field.gd:SHEET_LIMIT`'s rule and its number.
const MAP_LIMIT: int = 32

const FarDrawings: GDScript = preload("../shape/far_drawings.gd")
const MesherScript: GDScript = preload("../shape/mesher.gd")
const TileShapeScript: GDScript = preload("../shape/tile_shape.gd")
const Profile: GDScript = preload("../shape/profile.gd")

var root: Node3D = null
## The drawing a map falls back on where its own cuts to nothing, and the
## material carrying it.
var _mesh: Mesh = null
var _material: ShaderMaterial = null
## How a cut-out becomes a material. The stage's own, so two drawings cut to the
## same texture share one. See [method set_material_maker].
var _material_of: Callable = Callable()
## Per map, keyed `group,number`: what stands on it and what each of those wears,
## as `drawing -> { spots, mesh, material }`. Built once and kept: a map's trees
## do not move and its sheet does not change but for the hour, which drops the
## lot. See [method _dressing].
var _dressed: Dictionary = {}
var _pool: Array[MultiMeshInstance3D] = []
var _used: int = 0
## Per map: what its BORDER BLOCK stands, the same shape `_dressed` holds. See
## [method place_border].
var _bordered: Dictionary = {}
## The ring as it was last built: `[multimesh, material]` a drawing, and the
## three things a rebuild answers to.
var _border_multis: Array = []
var _border_at := Vector2.INF
var _border_blocked: Array = []


func _init() -> void:
	root = Node3D.new()
	root.name = "FarFoliage"


## What a drawing falls back on where its own cuts to nothing, which is rare and
## is not nothing: a body under `mesher.MODEL_BODY_MIN` has no card to wear.
func set_tree(mesh: Mesh, material: ShaderMaterial) -> void:
	_mesh = mesh
	_material = material


## Whether the maps out there stand anything at all. Off is the whole pass off,
## which is what `renderer.gd:far_trees` prices.
func set_enabled(on: bool) -> void:
	root.visible = on


## How a cut-out becomes a material, which is the stage's own pool: see
## `diorama.gd:foliage_material`. Until this is set the fallback tree is all
## anything wears, since a card with no material cannot be drawn.
func set_material_maker(maker: Callable) -> void:
	_material_of = maker


## Drops every card, for an hour that repaints the sheets they were cut from.
## See `far_field.gd:set_time_of_day`.
func forget_cards() -> void:
	_dressed.clear()
	_bordered.clear()
	_border_multis = []
	_border_at = Vector2.INF


func begin() -> void:
	_used = 0


## One far map's worth, standing at [param origin] in world pixels, wearing the
## cards cut from [param sheet], which is the tile sheet `far_field.gd` painted
## to draw that map's ground.
##
## [param clear] is ground somebody else is already standing on, in world pixels,
## and nothing stands inside it. For the LOADED map it is the hole the mesh cut,
## since its own ground carries on past the window for most of a route and a card
## where a solid already stands is the same tree drawn twice. For a NEIGHBOUR it
## is everything the mesh can stamp into, which its map overlaps: the loaded map's
## border ring is the neighbour's own ground and the mesh has already built it.
##
## THE MULTIMESHES ARE KEPT, not rebuilt. Filling one is a transform, a colour
## and a wind phase per card, and a wood on the horizon is two thousand of them:
## doing that every frame for every map in view cost about 0.7 ms of a 4.2 ms
## frame on route 26. Nothing in one moves unless the map is placed somewhere
## else or the mesh window recentres under it, so both are what they are rebuilt
## on.
func place(
	map: Gen2WorldMap, origin: Vector2, sheet: RefCounted, drawings: Dictionary,
	clear: Rect2 = Rect2()
) -> void:
	if not root.visible or map == null or drawings.is_empty():
		return
	# One MultiMesh per DRAWING, which is what lets each of them wear its own.
	var dressing: Dictionary = _dressing(map, sheet, drawings)
	for drawing: String in dressing:
		var worn: Dictionary = dressing[drawing]
		if worn["mesh"] == null or worn["material"] == null:
			continue
		# On the PLACEMENT and not on the answer: a drawing the clearance swallows
		# whole answers null, and testing that instead rebuilt it every frame.
		if worn["at"] != origin or worn["hole"] != clear:
			worn["at"] = origin
			worn["hole"] = clear
			worn["multi"] = _multi(worn["mesh"], worn["spots"], origin, clear)
		var multi: MultiMesh = worn["multi"]
		if multi == null:
			continue
		var node: MultiMeshInstance3D = _instance()
		node.multimesh = multi
		node.material_override = worn["material"]
		node.visible = true


## The stamps of one drawing on one map, or null where the hole swallowed them
## all. See [method place] for what is rebuilt and when.
func _multi(
	mesh: Mesh, spots: PackedVector2Array, origin: Vector2, clear: Rect2
) -> MultiMesh:
	var stood := PackedVector2Array()
	for spot: Vector2 in spots:
		if not clear.has_area() or not clear.has_point(origin + spot):
			stood.push_back(spot)
	if stood.is_empty():
		return null
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	# The wind phase and the instance colour the foliage shader expects, on the
	# same contract `diorama.gd:set_models` fills for the near ones.
	multi.use_custom_data = true
	multi.use_colors = true
	multi.mesh = mesh
	multi.instance_count = stood.size()
	for index: int in stood.size():
		var at: Vector2 = origin + stood[index]
		multi.set_instance_transform(index, Transform3D(
			Basis.IDENTITY, Vector3(at.x, 0.0, at.y)
		))
		multi.set_instance_custom_data(index, Color(_phase(at), 0.0, 0.0, 0.0))
		multi.set_instance_color(index, Color.WHITE)
	return multi


## THE WORLD PAST THE MAPS, which is one block repeated for ever.
##
## `far_field.gd` fills everything the camera can reach with the loaded map's
## border block, and on forty of the seventy-seven outdoor maps every tile of
## that block is a tree. So the game's own maps stood a skyline and the ground
## all round them was a flat page with tree art smeared across it, which is the
## one thing a horizon is for read the other way round.
##
## A RING, for the reason `BORDER_RUNGS` gives. [param blocked] is every
## rectangle a map is already drawn on, in world pixels, the loaded one grown to
## everything the mesh can stamp into: nothing stands on any of them, since the
## maps stand their own trees and the mesh stands solids.
func place_border(
	data: GameData, map: Gen2WorldMap, sheet: RefCounted, focus: Vector2,
	blocked: Array
) -> void:
	if not root.visible or data == null or map == null:
		return
	var dressing: Dictionary = _border_dressing(data, map, sheet)
	if dressing.is_empty():
		return
	if focus.distance_squared_to(_border_at) > BORDER_STEP * BORDER_STEP \
			or blocked != _border_blocked:
		_border_at = focus
		_border_blocked = blocked.duplicate()
		_border_multis = _border_ring(dressing, focus, _covered(blocked))
	for worn: Array in _border_multis:
		var node: MultiMeshInstance3D = _instance()
		node.multimesh = worn[0]
		node.material_override = worn[1]
		node.visible = true


## The ring itself, as `[multimesh, material]` per drawing.
##
## THE BLOCKS ARE GATHERED ONCE and every drawing is stamped off that one list,
## rather than each drawing walking the ring for itself: the walk is the dear
## part and the border block holds one or two drawings.
func _border_ring(
	dressing: Dictionary, anchor: Vector2, covered: Dictionary
) -> Array:
	var blocks := PackedVector2Array()
	var inner: float = 0.0
	for rung: Array in BORDER_RUNGS:
		var outer: float = float(rung[0]) + BORDER_STEP
		var stride: int = int(rung[1])
		# THE LATTICE IS THE WORLD'S AND NOT THE ANCHOR'S: snapped to absolute
		# blocks, a tree keeps its place as the ring is rebuilt under it, and only
		# the density changes as the eye comes nearer.
		var from := Vector2i(
			floori((anchor.x - outer) / BLOCK), floori((anchor.y - outer) / BLOCK)
		)
		var to := Vector2i(
			ceili((anchor.x + outer) / BLOCK), ceili((anchor.y + outer) / BLOCK)
		)
		from -= Vector2i(posmod(from.x, stride), posmod(from.y, stride))
		var near: float = inner * inner
		var far: float = outer * outer
		for by: int in range(from.y, to.y, stride):
			for bx: int in range(from.x, to.x, stride):
				var at := Vector2(float(bx) * BLOCK, float(by) * BLOCK)
				var away: float = at.distance_squared_to(anchor)
				if away > far or away <= near:
					continue
				if covered.has(_block_key(bx, by)):
					continue
				blocks.push_back(at)
		inner = outer
	var out: Array = []
	for drawing: String in dressing:
		var worn: Dictionary = dressing[drawing]
		if worn["mesh"] == null or worn["material"] == null:
			continue
		var offsets: PackedVector2Array = worn["spots"]
		if offsets.is_empty() or blocks.is_empty():
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_custom_data = true
		multi.use_colors = true
		multi.mesh = worn["mesh"]
		multi.instance_count = blocks.size() * offsets.size()
		var index: int = 0
		for block: Vector2 in blocks:
			for offset: Vector2 in offsets:
				var at: Vector2 = block + offset
				multi.set_instance_transform(index, Transform3D(
					Basis.IDENTITY, Vector3(at.x, 0.0, at.y)
				))
				multi.set_instance_custom_data(index, Color(_phase(at), 0.0, 0.0, 0.0))
				multi.set_instance_color(index, Color.WHITE)
				index += 1
		out.append([multi, worn["material"]])
	return out


## Every block a map is already drawn on, as a set. Asked once per
## rebuild and read once per block, where testing each block against a dozen
## rectangles is a quarter of a million rectangle tests.
static func _covered(blocked: Array) -> Dictionary:
	var out: Dictionary = {}
	for rect: Rect2 in blocked:
		var from := Vector2i(
			floori(rect.position.x / BLOCK), floori(rect.position.y / BLOCK)
		)
		var to := Vector2i(ceili(rect.end.x / BLOCK), ceili(rect.end.y / BLOCK))
		for by: int in range(from.y, to.y):
			for bx: int in range(from.x, to.x):
				out[_block_key(bx, by)] = true
	return out


## A block position as one number, which a dictionary is faster keyed on than on
## a Vector2i. The offset is what keeps a block west or north of the origin from
## colliding with one east or south of it.
static func _block_key(bx: int, by: int) -> int:
	return (by + 8192) * 65536 + (bx + 8192)


## What the border block stands and what each of it wears, built once per map.
func _border_dressing(
	data: GameData, map: Gen2WorldMap, sheet: RefCounted
) -> Dictionary:
	var key: String = "%d,%d" % [map.group, map.number]
	if _bordered.has(key):
		return _bordered[key]
	if sheet == null or not _material_of.is_valid():
		return {}
	if _bordered.size() >= MAP_LIMIT:
		_bordered.clear()
	# NOT COUNTED AGAINST THE FRAME'S ONE MAP. This walks sixteen tiles and cuts
	# the one or two drawings they hold, where a map is thousands and a dozen.
	var cutter: RefCounted = MesherScript.new()
	var shape: RefCounted = TileShapeScript.new(Profile, map.tileset)
	var out: Dictionary = {}
	var walked: Dictionary = FarDrawings.of_border(data, map, Profile)
	for drawing: String in walked:
		var found: Dictionary = walked[drawing]
		var card: Array = cutter.far_card_for(
			found["tiles"], found["across"], shape, found["class"], sheet
		)
		out[drawing] = {
			"spots": found["spots"],
			"mesh": card[0] if card.size() == 2 else _mesh,
			"material": _material_of.call(card[1]) if card.size() == 2 else _material,
		}
	_bordered[key] = out
	return out


func end() -> void:
	for index: int in range(_used, _pool.size()):
		_pool[index].multimesh = null
		_pool[index].visible = false


## A settled number in 0 to 1 for a spot, so a far wood bends tree by tree and
## the same tree bends the same way every frame. `mesher.gd:_hash_spot`'s rule.
static func _phase(at: Vector2) -> float:
	var value: float = sin(at.x * 127.1 + at.y * 311.7) * 43758.5453
	return value - floorf(value)


func _instance() -> MultiMeshInstance3D:
	if _used >= _pool.size():
		var made := MultiMeshInstance3D.new()
		root.add_child(made)
		_pool.append(made)
	var node: MultiMeshInstance3D = _pool[_used]
	_used += 1
	return node


## WHAT EACH OF ONE MAP'S DRAWINGS WEARS, cut once and kept.
##
## The walk that found them is `far_field.gd`'s, budgeted there a map a frame,
## because the buildings come off the same pass. What is paid here is the CUTTING:
## a mask, a flood and a turned card per drawing, about three milliseconds a map.
##
## A map with no sheet yet is not dressed: `far_field.gd` pays for one sheet a
## frame as well, and a map whose ground has not been painted has nothing for its
## trees to stand on.
func _dressing(
	map: Gen2WorldMap, sheet: RefCounted, drawings: Dictionary
) -> Dictionary:
	var key: String = "%d,%d" % [map.group, map.number]
	if _dressed.has(key):
		return _dressed[key]
	if sheet == null or not _material_of.is_valid():
		return {}
	# Kept between maps for `far_field.gd:SHEET_LIMIT`'s reason and bounded for
	# it too: a card and its stamps are the dearest thing here to hold.
	if _dressed.size() >= MAP_LIMIT:
		_dressed.clear()
	# A FACTORY PER MAP AND NOT ONE FOR THE RUN. The mesher caches a drawing's
	# mask under its tile ids, and `resolve` drops that cache on every map for
	# the stated reason: a tile id means nothing without the tileset it came
	# from, and an outline is read against the map's own palette. Nothing here
	# resolves, so nothing would drop it. One is a few bytes and the cutting is
	# three milliseconds a map either way.
	var cutter: RefCounted = MesherScript.new()
	var shape: RefCounted = TileShapeScript.new(Profile, map.tileset)
	var out: Dictionary = {}
	for drawing: String in drawings:
		var found: Dictionary = drawings[drawing]
		var card: Array = cutter.far_card_for(
			found["tiles"], found["across"], shape, found["class"], sheet
		)
		out[drawing] = {
			"spots": found["spots"],
			"mesh": card[0] if card.size() == 2 else _mesh,
			"material": _material_of.call(card[1]) if card.size() == 2 else _material,
			# Filled on the first frame this map is in view, and again only when
			# it is placed elsewhere or the window recentres: see [method place].
			"multi": null,
			"at": Vector2.INF,
			"hole": Rect2(),
		}
	_dressed[key] = out
	return out
