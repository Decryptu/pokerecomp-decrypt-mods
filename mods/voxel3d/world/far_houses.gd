extends RefCounted

## The buildings on the maps past the mesh, so a town out there is not a flat
## page with roofs painted on it.

const TILE: float = 8.0
const MAP_LIMIT: int = 32

var root: Node3D = null
var _built: Dictionary = {}
var _pool: Array[MeshInstance3D] = []
var _used: int = 0


func _init() -> void:
	root = Node3D.new()
	root.name = "FarHouses"


func set_enabled(on: bool) -> void:
	root.visible = on


func forget() -> void:
	_built.clear()


func begin() -> void:
	_used = 0


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
		made.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(made)
		_pool.append(made)
	var node: MeshInstance3D = _pool[_used]
	_used += 1
	return node


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

	for row: int in roof:
		for column: int in rect.size.x:
			var tile: int = int(tiles[row * rect.size.x + column])
			var x: float = west + float(column) * TILE
			var z: float = north + float(row) * TILE
			_quad(surface, sheet, tile, Vector3.UP, [
				Vector3(x, high, z), Vector3(x + TILE, high, z),
				Vector3(x + TILE, high, z + TILE), Vector3(x, high, z + TILE),
			])
	for row: int in wall:
		for column: int in rect.size.x:
			var tile: int = int(tiles[(roof + row) * rect.size.x + column])
			var x: float = west + float(column) * TILE
			var top: float = high - float(row) * TILE
			_quad(surface, sheet, tile, Vector3.BACK, [
				Vector3(x, top, south), Vector3(x + TILE, top, south),
				Vector3(x + TILE, top - TILE, south), Vector3(x, top - TILE, south),
			])
			_quad(surface, sheet, tile, Vector3.FORWARD, [
				Vector3(x + TILE, top, north), Vector3(x, top, north),
				Vector3(x, top - TILE, north), Vector3(x + TILE, top - TILE, north),
			])
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
