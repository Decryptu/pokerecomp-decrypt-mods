extends RefCounted

## Registers the two renderers and returns. The host decides when to build one,
## so nothing here is a scene node and nothing here reads world or battle state.
##
## Each renderer locates its own siblings off its `resource_path`, which is why
## only the two entry scripts are named here.


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	host.register_world_renderer(
		manifest.id, load("%s/world/renderer.gd" % manifest.directory), "Voxel 3D"
	)
	host.register_battle_renderer(
		manifest.id, load("%s/battle/renderer.gd" % manifest.directory), "Voxel 3D"
	)
