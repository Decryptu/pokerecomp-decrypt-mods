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
## Whether a map has already been dressed this frame. See [method _dressing].
var _built: bool = false


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


func begin() -> void:
	_used = 0
	_built = false


## One far map's worth, standing at [param origin] in world pixels, wearing the
## cards cut from [param sheet], which is the tile sheet `far_field.gd` painted
## to draw that map's ground.
##
## [param hole] is the ground the MESH is drawing, in world pixels, and nothing
## stands inside it. Empty for a neighbour, which the mesh never reaches; the
## LOADED map is the one that needs it, and it needs it badly: its own ground
## carries on past the window for most of a route, and a card standing where a
## turned solid already stands is the same tree drawn twice.
##
## THE MULTIMESHES ARE KEPT, not rebuilt. Filling one is a transform, a colour
## and a wind phase per card, and a wood on the horizon is two thousand of them:
## doing that every frame for every map in view cost about 0.7 ms of a 4.2 ms
## frame on route 26. Nothing in one moves unless the map is placed somewhere
## else or the mesh window recentres under it, so both are what they are rebuilt
## on.
func place(
	data: GameData, map: Gen2WorldMap, origin: Vector2, sheet: RefCounted,
	hole: Rect2 = Rect2()
) -> void:
	if not root.visible or data == null or map == null:
		return
	# One MultiMesh per DRAWING, which is what lets each of them wear its own.
	var dressing: Dictionary = _dressing(data, map, sheet)
	for drawing: String in dressing:
		var worn: Dictionary = dressing[drawing]
		if worn["mesh"] == null or worn["material"] == null:
			continue
		# On the PLACEMENT and not on the answer: a drawing the hole swallows
		# whole answers null, and testing that instead rebuilt it every frame.
		if worn["at"] != origin or worn["hole"] != hole:
			worn["at"] = origin
			worn["hole"] = hole
			worn["multi"] = _multi(worn["mesh"], worn["spots"], origin, hole)
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
	mesh: Mesh, spots: PackedVector2Array, origin: Vector2, hole: Rect2
) -> MultiMesh:
	var stood := PackedVector2Array()
	for spot: Vector2 in spots:
		if not hole.has_area() or not hole.has_point(origin + spot):
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


## WHAT STANDS ON ONE MAP AND WHAT EACH OF IT WEARS, built once and kept.
##
## ONE MAP A FRAME, which is `far_field.gd`'s own rule for painting a sheet and
## is here for the same reasons: the walk is about eleven milliseconds on a route
## and the cutting three more, a mask, a flood and a turned card per drawing, and
## a warp can bring a dozen maps into view on one frame. A map that has not been
## dressed yet simply stands nothing this frame and is dressed on the next.
##
## A map with no sheet yet is not dressed either, and is not counted against the
## frame's one: `far_field.gd` pays for one sheet a frame as well, and a map
## whose ground has not been painted has nothing for its trees to stand on.
func _dressing(data: GameData, map: Gen2WorldMap, sheet: RefCounted) -> Dictionary:
	var key: String = "%d,%d" % [map.group, map.number]
	if _dressed.has(key):
		return _dressed[key]
	if _built or sheet == null or not _material_of.is_valid():
		return {}
	_built = true
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
	var walked: Dictionary = FarDrawings.of_map(data, map, Profile)
	for drawing: String in walked:
		var found: Dictionary = walked[drawing]
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
