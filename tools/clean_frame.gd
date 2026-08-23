extends RefCounted

## The cartridge screen alone, out of a world screen that is also a development
## harness.
##
## `world_screen.tscn` carries a dark `Background` panel, a `Caption` naming the
## map and cell, a `Hint` listing the keys and a `TouchPad`. All of them are
## wanted while a defect is being chased and none of them belongs in a picture
## of the game. Reading the window and cropping does not answer it either: the
## letterbox is drawn INSIDE `Gen2Screen`, so the node's own rect is the whole
## window. What is read here is that screen's own viewport, which holds the
## hardware picture and nothing around it.
##
## A view drawing at WINDOW resolution is not in that viewport at all, and for
## one the two halves here split: `hide_chrome` takes the furniture off and the
## caller captures the window itself. See [method capture].

## The Gen2Screen inside the world screen.
const SCREEN: String = "Frame/Screen"

## The harness's own furniture. Hiding it is what makes a WINDOW capture clean,
## which is the only capture a window-resolution view has.
const CHROME: Array[String] = ["Background", "Caption", "Hint", "Frame/TouchPad"]


## Takes the development harness off the screen, for a picture that is captured
## from the window rather than from the hardware buffer. Spent frames before the
## shutter, since nothing is hidden in the frame already drawn.
static func hide_chrome(world_screen: Control) -> void:
	for path: String in CHROME:
		var node: CanvasItem = world_screen.get_node_or_null(NodePath(path)) as CanvasItem
		if node != null:
			node.visible = false


## The hardware picture, scaled by whole pixels so the edges stay hard. Null if
## the screen has been renamed under this, or if the view is not drawn in the
## hardware buffer, which is the caller's cue to capture the window instead.
static func capture(world_screen: Control, scale: int = 1) -> Image:
	var screen: Node = world_screen.get_node_or_null(NodePath(SCREEN))
	if screen == null or not screen.has_method("viewport"):
		return null
	var viewport: SubViewport = screen.call("viewport") as SubViewport
	if viewport == null:
		return null
	# A VIEW THAT DECLINED THE HARDWARE BUFFER IS NOT DRAWN IN IT. voxel3d
	# answers `uses_hardware_viewport` false and is parented to `Gen2Screen`'s
	# native layer instead, so this viewport holds an empty field and a clean
	# capture of it was a white rectangle. Answering null sends the caller to the
	# window, which is where that picture is; `hide_chrome` is what makes it
	# clean there.
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
