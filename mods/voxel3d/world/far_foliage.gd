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
## EACH CELL WEARS ITS OWN DRAWING where the map is on this tileset, which is
## most of them: `shape/mesher.gd:far_cards` hands over the card each drawing
## was cut to, keyed by the tile it starts at, and the walk below groups the
## spots by card. Before that every cell of every far map wore ONE card, the
## biggest drawing the loaded map turned, so a bush was drawn as a tree and the
## whole horizon read as a single mass of identical canopy. That was written
## down as invisible at the distance it is drawn, and it is not: dollying the
## camera out to the rig's own limit is all it takes.
##
## A map on ANOTHER TILESET still wears the one tree, and that is not laziness:
## a tile id is numbered in its own tileset and means nothing in another, which
## is the same reason `shape/map_source.gd` refuses a neighbour's block. Nine of
## the seventy-seven outdoor maps have such a neighbour.
##
## One simplification is left and is deliberate: a cell that holds a drawing gets
## one card rather than the drawing's own bodies, so a cell of four sea rocks is
## one rock out there.

const CELL: float = 16.0
## Cells across and down one block, which is what the cartridge's map data is
## stored in. See `far_field.gd:BLOCK_PIXELS`.
const CELLS_PER_BLOCK: int = 2
## Tiles across one cell.
const TILES_PER_CELL: int = 2
## The most trees one map may stand, so a pathological tileset cannot fill
## memory. Route 32, which is the thickest wood in the game, comes out near 1200.
const SPOT_LIMIT: int = 4096

const MapSourceScript: GDScript = preload("../shape/map_source.gd")
const TileShapeScript: GDScript = preload("../shape/tile_shape.gd")
const Profile: GDScript = preload("../shape/profile.gd")

var root: Node3D = null
## The drawing a map on another tileset wears, and the material carrying it.
var _mesh: Mesh = null
var _material: ShaderMaterial = null
## `[mesh, material]` per tile id, and the tileset those ids are numbered in.
## See [method set_cards].
var _cards: Dictionary = {}
var _cards_tileset: int = -1
## Per map, keyed `group,number`: where its trees stand in that map's own pixels.
## Walked once and kept, since a map's trees do not move.
var _spots: Dictionary = {}
var _pool: Array[MultiMeshInstance3D] = []
var _used: int = 0


func _init() -> void:
	root = Node3D.new()
	root.name = "FarFoliage"


## The tree every far map is dressed with. Until this is set nothing is drawn,
## which is what makes the whole pass opt in.
func set_tree(mesh: Mesh, material: ShaderMaterial) -> void:
	_mesh = mesh
	_material = material


## The card each drawing wears, keyed by the tile it starts at, and the tileset
## those tiles are numbered in. Empty is what this did before it took any: one
## tree everywhere. See [method set_tree].
func set_cards(cards: Dictionary, tileset: int) -> void:
	_cards = cards
	_cards_tileset = tileset


func set_visible(visible: bool) -> void:
	root.visible = visible


func begin() -> void:
	_used = 0


## One far map's worth, standing at [param origin] in world pixels.
func place(data: GameData, map: Gen2WorldMap, origin: Vector2) -> void:
	if _mesh == null or _material == null or data == null or map == null:
		return
	# Grouped by the card the cells wear, one MultiMesh each, which on a map of
	# this tileset is one per DRAWING and on any other is the single tree.
	var by_tile: Dictionary = _spots_of(data, map)
	for tile: int in by_tile:
		var spots: PackedVector2Array = by_tile[tile]
		if spots.is_empty():
			continue
		var card: Array = _card(map, tile)
		if card.is_empty():
			continue
		var node: MultiMeshInstance3D = _instance()
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		# The wind phase and the instance colour the foliage shader expects, on
		# the same contract `diorama.gd:set_models` fills for the near ones.
		multi.use_custom_data = true
		multi.use_colors = true
		multi.mesh = card[0]
		multi.instance_count = spots.size()
		for index: int in spots.size():
			var at: Vector2 = origin + spots[index]
			multi.set_instance_transform(index, Transform3D(
				Basis.IDENTITY, Vector3(at.x, 0.0, at.y)
			))
			multi.set_instance_custom_data(index, Color(
				_phase(at), 0.0, 0.0, 0.0
			))
			multi.set_instance_color(index, Color.WHITE)
		node.multimesh = multi
		node.material_override = card[1]
		node.visible = true


## What one far cell stands: its own drawing where the map is numbered in the
## tileset the cards came from, and the single tree everywhere else.
func _card(map: Gen2WorldMap, tile: int) -> Array:
	if map.tileset == _cards_tileset and _cards.has(tile):
		return _cards[tile]
	return [_mesh, _material] if _mesh != null and _material != null else []


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


## Where one map's trees stand, in that map's own pixels, GROUPED BY THE TILE the
## drawing starts at so each group can wear its own card. Walked once per map.
func _spots_of(data: GameData, map: Gen2WorldMap) -> Dictionary:
	var key: String = "%d,%d" % [map.group, map.number]
	if _spots.has(key):
		return _spots[key]
	var found: Dictionary = {}
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
	if tileset == null:
		_spots[key] = found
		return found
	var shape: RefCounted = TileShapeScript.new(Profile, map.tileset)
	var source: RefCounted = MapSourceScript.new(null, map, tileset, data)
	# Whether a tile is a model depends on the tile and the permission and on
	# nothing else, so the pair is asked once however often the map repeats it.
	var known: Dictionary = {}
	var across: int = map.width_blocks * CELLS_PER_BLOCK
	var down: int = map.height_blocks * CELLS_PER_BLOCK
	var placed: int = 0
	for cy: int in down:
		for cx: int in across:
			var tile: int = source.tile_at(cx * TILES_PER_CELL, cy * TILES_PER_CELL)
			if tile < 0:
				continue
			var permission: int = source.permission_at(Vector2i(cx, cy))
			var pair: int = tile * 256 + permission + 1
			var modelled: bool = known.get(pair, false)
			if not known.has(pair):
				modelled = shape.is_model(shape.at(tile, permission))
				known[pair] = modelled
			if not modelled:
				continue
			if not found.has(tile):
				found[tile] = PackedVector2Array()
			(found[tile] as PackedVector2Array).push_back(
				Vector2((float(cx) + 0.5) * CELL, (float(cy) + 0.5) * CELL)
			)
			placed += 1
			if placed >= SPOT_LIMIT:
				break
		if placed >= SPOT_LIMIT:
			break
	_spots[key] = found
	return found
