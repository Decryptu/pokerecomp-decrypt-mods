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

## The Gen2Screen inside the world screen.
const SCREEN: String = "Frame/Screen"


## The hardware picture, scaled by whole pixels so the edges stay hard, or null
## if the screen has been renamed under this.
static func capture(world_screen: Control, scale: int = 1) -> Image:
	var screen: Node = world_screen.get_node_or_null(NodePath(SCREEN))
	if screen == null or not screen.has_method("viewport"):
		return null
	var viewport: SubViewport = screen.call("viewport") as SubViewport
	if viewport == null:
		return null
	var image: Image = viewport.get_texture().get_image()
	if image != null and scale > 1:
		image.resize(
			image.get_width() * scale, image.get_height() * scale,
			Image.INTERPOLATE_NEAREST
		)
	return image
