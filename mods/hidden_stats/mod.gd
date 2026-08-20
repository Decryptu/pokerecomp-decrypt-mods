extends RefCounted

## Registers one stats-screen page and returns. Nothing here is a scene node,
## nothing here draws: the page answers WHERE its strings go and the host writes
## them into the lower half with the screen's own font and dividers.

const Page := preload("page.gd")


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	host.register_stats_page(manifest.id, {"build": Page.build})
