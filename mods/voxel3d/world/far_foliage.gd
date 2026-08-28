extends RefCounted

## Trees on the maps past the mesh.

const BLOCK: float = 32.0
const BORDER_RUNGS: Array = [[600.0, 1], [1200.0, 2], [2400.0, 4], [4800.0, 8]]
const BORDER_STEP: float = 512.0
const MAP_LIMIT: int = 32

const FarDrawings: GDScript = preload("../shape/far_drawings.gd")
const MesherScript: GDScript = preload("../shape/mesher.gd")
const TileShapeScript: GDScript = preload("../shape/tile_shape.gd")
const Profile: GDScript = preload("../shape/profile.gd")

var root: Node3D = null
var _mesh: Mesh = null
var _material: ShaderMaterial = null
var _material_of: Callable = Callable()
var _dressed: Dictionary = {}
var _pool: Array[MultiMeshInstance3D] = []
var _used: int = 0
var _bordered: Dictionary = {}
var _border_multis: Array = []
var _border_at := Vector2.INF
var _border_blocked: Array = []


func _init() -> void:
	root = Node3D.new()
	root.name = "FarFoliage"


func set_tree(mesh: Mesh, material: ShaderMaterial) -> void:
	_mesh = mesh
	_material = material


func set_enabled(on: bool) -> void:
	root.visible = on


func set_material_maker(maker: Callable) -> void:
	_material_of = maker


func forget_cards() -> void:
	_dressed.clear()
	_bordered.clear()
	_border_multis = []
	_border_at = Vector2.INF


func begin() -> void:
	_used = 0


func place(
	map: Gen2WorldMap, origin: Vector2, sheet: RefCounted, drawings: Dictionary,
	clear: Rect2 = Rect2()
) -> void:
	if not root.visible or map == null or drawings.is_empty():
		return
	var dressing: Dictionary = _dressing(map, sheet, drawings)
	for drawing: String in dressing:
		var worn: Dictionary = dressing[drawing]
		if worn["mesh"] == null or worn["material"] == null:
			continue
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


func _border_ring(
	dressing: Dictionary, anchor: Vector2, covered: Dictionary
) -> Array:
	var blocks := PackedVector2Array()
	var inner: float = 0.0
	for rung: Array in BORDER_RUNGS:
		var outer: float = float(rung[0]) + BORDER_STEP
		var stride: int = int(rung[1])
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


static func _block_key(bx: int, by: int) -> int:
	return (by + 8192) * 65536 + (bx + 8192)


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


func _dressing(
	map: Gen2WorldMap, sheet: RefCounted, drawings: Dictionary
) -> Dictionary:
	var key: String = "%d,%d" % [map.group, map.number]
	if _dressed.has(key):
		return _dressed[key]
	if sheet == null or not _material_of.is_valid():
		return {}
	if _dressed.size() >= MAP_LIMIT:
		_dressed.clear()
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
			"multi": null,
			"at": Vector2.INF,
			"hole": Rect2(),
		}
	_dressed[key] = out
	return out
