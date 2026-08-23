extends RefCounted

## Registers the two renderers and returns. The host decides when to build one,
## so nothing here is a scene node and nothing here reads world or battle state.
##
## Each renderer preloads its own siblings, which is why only the two entry
## scripts are named here: registering one parses the tree behind it, so
## switching to that view costs no parsing at all.


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	host.register_world_renderer(
		manifest.id, load("%s/world/renderer.gd" % manifest.directory), "Voxel 3D"
	)
	host.register_battle_renderer(
		manifest.id, load("%s/battle/renderer.gd" % manifest.directory), "Voxel 3D"
	)
	# Described, not drawn: the host builds the start menu's MODS entry and this
	# mod's own page in the launcher out of these, and both renderers read the same
	# ladders back. `options.gd` is the one place they are written down.
	(load("%s/options.gd" % manifest.directory) as GDScript).register(host, manifest.id)
