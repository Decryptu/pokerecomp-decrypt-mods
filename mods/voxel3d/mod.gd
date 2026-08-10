extends RefCounted

## Registers the world renderer and returns. The host decides when to build one,
## so nothing here is a scene node and nothing here reads world state.
##
## The renderer locates its own siblings off its `resource_path`, which is why
## only the one script is named here.


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	host.register_world_renderer(
		manifest.id, load("%s/world/renderer.gd" % manifest.directory), "Voxel 3D"
	)
