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
## Two simplifications, both deliberate and both visible only if looked for:
## every far map wears the CURRENT map's tree rather than its own, and a cell
## that holds a drawing gets one tree rather than the drawing's own bodies. At
## the distance this is drawn, neither reads.

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
## The drawing every far map's trees wear, and the material carrying it.
var _mesh: Mesh = null
var _material: ShaderMaterial = null
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


func set_visible(visible: bool) -> void:
	root.visible = visible


func begin() -> void:
	_used = 0


## One far map's worth, standing at [param origin] in world pixels.
func place(data: GameData, map: Gen2WorldMap, origin: Vector2) -> void:
	if _mesh == null or _material == null or data == null or map == null:
		return
	var spots: PackedVector2Array = _spots_of(data, map)
	if spots.is_empty():
		return
	var node: MultiMeshInstance3D = _instance()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	# The wind phase and the instance colour the foliage shader expects, on the
	# same contract `diorama.gd:set_models` fills for the near ones.
	multi.use_custom_data = true
	multi.use_colors = true
	multi.mesh = _mesh
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
	node.material_override = _material
	node.visible = true


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


## Where one map's trees stand, in that map's own pixels. Walked once per map.
func _spots_of(data: GameData, map: Gen2WorldMap) -> PackedVector2Array:
	var key: String = "%d,%d" % [map.group, map.number]
	if _spots.has(key):
		return _spots[key]
	var found := PackedVector2Array()
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
			found.push_back(Vector2((float(cx) + 0.5) * CELL, (float(cy) + 0.5) * CELL))
			if found.size() >= SPOT_LIMIT:
				break
		if found.size() >= SPOT_LIMIT:
			break
	_spots[key] = found
	return found
