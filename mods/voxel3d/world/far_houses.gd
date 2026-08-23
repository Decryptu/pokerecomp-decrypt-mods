extends RefCounted

## THE BUILDINGS ON THE MAPS PAST THE MESH.
##
## `far_field.gd` carries the ground out to the horizon and `far_foliage.gd`
## stands its woods on it, and until this was here a town out there was a flat
## page with roofs painted on it: the one thing in the distance that is not a
## plant, and the only thing left lying down.
##
## A BOX AND NOT A HOUSE. `shape/houses.gd` is a hundred hand-painted drawings
## read per PIXEL and matched by arrangement, and `shape/mesher.gd` spends a
## resolve on them; neither is available out here, where a map has to be stood up
## in milliseconds. What is available is the profile's own `facade` and `roof`,
## which is enough to say where a building is, how deep its roof is drawn and how
## tall its wall is. So it is built as what the cartridge draws: a roof laid over
## a footprint with a wall under the front of it.
##
## THE ART IS THE MAP'S OWN, tile for tile, off the same sheet the ground beside
## it is drawn from: the roof tiles on the lid and the wall tiles on the four
## sides. Nothing is invented and nothing is tinted; the sun shades it, as it
## shades the mesh.
##
## One mesh a map rather than one a building, because a town is a dozen of them
## and out there they are drawn or culled together.

const TILE: float = 8.0
## How many maps' worth of geometry is held at once. `far_field.gd:SHEET_LIMIT`'s
## rule and its number.
const MAP_LIMIT: int = 32

var root: Node3D = null
## Per map, keyed `group,number`: `[mesh, material, clear]`, the mesh null for a
## map whose buildings all state a flat drawing or all fall inside the clearance.
var _built: Dictionary = {}
var _pool: Array[MeshInstance3D] = []
var _used: int = 0


func _init() -> void:
	root = Node3D.new()
	root.name = "FarHouses"


## Whether the maps out there stand their buildings at all.
func set_enabled(on: bool) -> void:
	root.visible = on


## Drops every mesh, for an hour that repaints the sheets they are painted from.
func forget() -> void:
	_built.clear()


func begin() -> void:
	_used = 0


## One far map's buildings, standing at [param origin] in world pixels.
##
## [param clear] is ground somebody else is already standing on, and a building
## whose footprint touches it is left out. `far_foliage.gd:place` takes the same
## rectangle and for the same reasons.
func place(
	map: Gen2WorldMap, origin: Vector2, sheet: RefCounted, buildings: Array,
	clear: Rect2 = Rect2()
) -> void:
	if not root.visible or map == null or sheet == null or buildings.is_empty():
		return
	var made: Array = _mesh_of(map, sheet, buildings, clear, origin)
	if made.size() != 2:
		return
	var node: MeshInstance3D = _instance()
	node.mesh = made[0]
	node.material_override = made[1]
	node.position = Vector3(origin.x, 0.0, origin.y)
	node.visible = true


func end() -> void:
	for index: int in range(_used, _pool.size()):
		_pool[index].mesh = null
		_pool[index].visible = false


func _instance() -> MeshInstance3D:
	if _used >= _pool.size():
		var made := MeshInstance3D.new()
		# Flat art a long way off neither casts a shadow nor is worth one: the
		# sun's reach is held to the mesh window. See `far_field.gd:_instance`.
		made.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(made)
		_pool.append(made)
	var node: MeshInstance3D = _pool[_used]
	_used += 1
	return node


## One map's buildings as one mesh, built once and kept.
##
## KEYED ON THE CLEARANCE AS WELL, because the loaded map's own buildings past
## the window are in here and the window moves under them.
func _mesh_of(
	map: Gen2WorldMap, sheet: RefCounted, buildings: Array, clear: Rect2,
	origin: Vector2
) -> Array:
	var key: String = "%d,%d" % [map.group, map.number]
	var held: Array = _built.get(key, [])
	if held.size() == 3 and held[2] == clear:
		return [] if held[0] == null else [held[0], held[1]]
	if _built.size() >= MAP_LIMIT:
		_built.clear()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any: bool = false
	for building: Dictionary in buildings:
		var rect: Rect2i = building["rect"]
		var stood := Rect2(
			origin + Vector2(rect.position) * TILE, Vector2(rect.size) * TILE
		)
		if clear.has_area() and clear.intersects(stood):
			continue
		any = _box(surface, sheet, building) or any
	if not any:
		_built[key] = [null, null, clear]
		return []
	surface.generate_tangents()
	var mesh: ArrayMesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_texture = sheet.texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_built[key] = [mesh, material, clear]
	return [mesh, material]


## ONE BUILDING, as the cartridge draws it: the top rows are the roof seen from
## above and are therefore its DEPTH, and the rows under them are the wall seen
## face on and are therefore its HEIGHT.
##
## THE RUN AND NOT THE COUNT. A flood joins two buildings that touch, so a
## rectangle can hold roof rows, wall rows, roof rows again; what is built is the
## leading run of roof and the run of wall under it, and anything past that is
## left lying. A rectangle with no roof over a wall states no box at all and is
## left where it lies, which is what the page already draws.
func _box(surface: SurfaceTool, sheet: RefCounted, building: Dictionary) -> bool:
	var rect: Rect2i = building["rect"]
	var rows: PackedByteArray = building["rows"]
	var tiles: Array = building["tiles"]
	if rect.size.x <= 0:
		return false
	var roof: int = 0
	while roof < rows.size() and rows[roof] == 2:
		roof += 1
	var wall: int = 0
	while roof + wall < rows.size() and rows[roof + wall] == 1:
		wall += 1
	if roof <= 0 or wall <= 0:
		return false
	var west: float = float(rect.position.x) * TILE
	var east: float = float(rect.position.x + rect.size.x) * TILE
	var north: float = float(rect.position.y) * TILE
	var south: float = north + float(roof) * TILE
	var high: float = float(wall) * TILE

	# THE LID wears the roof rows, north row first, which is how they are drawn.
	for row: int in roof:
		for column: int in rect.size.x:
			var tile: int = int(tiles[row * rect.size.x + column])
			var x: float = west + float(column) * TILE
			var z: float = north + float(row) * TILE
			_quad(surface, sheet, tile, Vector3.UP, [
				Vector3(x, high, z), Vector3(x + TILE, high, z),
				Vector3(x + TILE, high, z + TILE), Vector3(x, high, z + TILE),
			])
	# THE FRONT wears the wall rows, top row first, on the south face, which is
	# the one the overworld's camera is always looking at.
	for row: int in wall:
		for column: int in rect.size.x:
			var tile: int = int(tiles[(roof + row) * rect.size.x + column])
			var x: float = west + float(column) * TILE
			var top: float = high - float(row) * TILE
			_quad(surface, sheet, tile, Vector3.BACK, [
				Vector3(x, top, south), Vector3(x + TILE, top, south),
				Vector3(x + TILE, top - TILE, south), Vector3(x, top - TILE, south),
			])
			# And the back, which is the same wall seen from the other side. It is
			# in frame whenever the eye is north of a building, which out there is
			# most of the time.
			_quad(surface, sheet, tile, Vector3.FORWARD, [
				Vector3(x + TILE, top, north), Vector3(x, top, north),
				Vector3(x, top - TILE, north), Vector3(x + TILE, top - TILE, north),
			])
	# THE FLANKS take the wall's own end column, since the cartridge draws no side
	# of a house at all: one tile per row of roof and per row of wall.
	for row: int in wall:
		var top: float = high - float(row) * TILE
		for side: int in 2:
			var column: int = 0 if side == 0 else rect.size.x - 1
			var tile: int = int(tiles[(roof + row) * rect.size.x + column])
			var x: float = west if side == 0 else east
			for deep: int in roof:
				var z: float = north + float(deep) * TILE
				if side == 0:
					_quad(surface, sheet, tile, Vector3.LEFT, [
						Vector3(x, top, z), Vector3(x, top, z + TILE),
						Vector3(x, top - TILE, z + TILE), Vector3(x, top - TILE, z),
					])
				else:
					_quad(surface, sheet, tile, Vector3.RIGHT, [
						Vector3(x, top, z + TILE), Vector3(x, top, z),
						Vector3(x, top - TILE, z), Vector3(x, top - TILE, z + TILE),
					])
	return true


## One tile's worth of face, wound so the named normal faces out. The corners are
## given top-left first and run round the face.
func _quad(
	surface: SurfaceTool, sheet: RefCounted, tile: int, normal: Vector3,
	corners: Array
) -> void:
	var box: Rect2 = sheet.uv(tile)
	if box.size == Vector2.ZERO:
		return
	var uvs: Array = [
		box.position, box.position + Vector2(box.size.x, 0.0),
		box.position + box.size, box.position + Vector2(0.0, box.size.y),
	]
	for index: int in [0, 1, 2, 0, 2, 3]:
		surface.set_normal(normal)
		surface.set_color(Color.WHITE)
		surface.set_uv(uvs[index])
		surface.add_vertex(corners[index])
