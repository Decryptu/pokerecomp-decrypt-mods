extends RefCounted

## Registers one stats-screen page and returns. Nothing here draws: the page
## answers with strings and where they go, and the host writes them with the
## screen's own font and dividers.

const Page := preload("page.gd")


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	host.register_stats_page(manifest.id, {"build": Page.build})
