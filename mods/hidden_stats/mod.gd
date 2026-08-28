extends RefCounted

## Registers one stats-screen page and returns.

const Page := preload("page.gd")


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	host.register_stats_page(manifest.id, {"build": Page.build})
