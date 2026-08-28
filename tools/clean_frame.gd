extends RefCounted

## The cartridge screen alone, out of a world screen that is also a development
## harness.

const SCREEN: String = "Frame/Screen"

const CHROME: Array[String] = ["Background", "Caption", "Hint", "Frame/TouchPad"]


static func hide_chrome(world_screen: Control) -> void:
	for path: String in CHROME:
		var node: CanvasItem = world_screen.get_node_or_null(NodePath(path)) as CanvasItem
		if node != null:
			node.visible = false


static func capture(world_screen: Control, scale: int = 1) -> Image:
	var screen: Node = world_screen.get_node_or_null(NodePath(SCREEN))
	if screen == null or not screen.has_method("viewport"):
		return null
	var viewport: SubViewport = screen.call("viewport") as SubViewport
	if viewport == null:
		return null
	var native: Node = screen.get_node_or_null(^"%Native")
	if native != null and native.get_child_count() > 0:
		return null
	var image: Image = viewport.get_texture().get_image()
	if image != null and scale > 1:
		image.resize(
			image.get_width() * scale, image.get_height() * scale,
			Image.INTERPOLATE_NEAREST
		)
	return image
