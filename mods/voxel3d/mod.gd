extends RefCounted

## Registers the two renderers and returns. The host decides when to build one.
##
## Each renderer preloads its own siblings, so only the two entry scripts are
## named here and switching to that view costs no parsing.


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	host.register_world_renderer(
		manifest.id, load("%s/world/renderer.gd" % manifest.directory), "Voxel 3D"
	)
	host.register_battle_renderer(
		manifest.id, load("%s/battle/renderer.gd" % manifest.directory), "Voxel 3D"
	)
	# Described, not drawn: the host builds the MODS entry and the mod's page out
	# of these, and both renderers read the same ladders back.
	(load("%s/options.gd" % manifest.directory) as GDScript).register(host, manifest.id)
