extends RefCounted

## Registers the two renderers and returns.


func register(host: Gen2ModHost, manifest: PokeModManifest) -> void:
	host.register_world_renderer(
		manifest.id, load("%s/world/renderer.gd" % manifest.directory), "Voxel 3D"
	)
	host.register_battle_renderer(
		manifest.id, load("%s/battle/renderer.gd" % manifest.directory), "Voxel 3D"
	)
	(load("%s/options.gd" % manifest.directory) as GDScript).register(host, manifest.id)
