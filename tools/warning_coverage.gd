extends SceneTree

## Says which of a mod's scripts the host's own load actually pulls in.
##
##   Godot --headless --path <pokerecomp> -s tools/warning_coverage.gd [-- <id>]
##
## THE EDITOR'S GDSCRIPT WARNINGS ARE THE ONLY ONES THERE ARE. The analyzer runs
## nowhere else: `--check-only` suppresses them, a running game prints none, and
## the game repository's `tools/dump_editor_errors.gd` scrapes the Debugger panel
## because scraping is the only way to read them. That dump reports on the
## scripts the editor has analysed, and a script it never loaded is silent in it
## for the same reason a sound one is.
##
## SO A CLEAN DUMP MEANS NOTHING WITHOUT THIS. It loads the mods the way the
## launcher does, through `discover` and `load_discovered`, and then asks which
## files that left uncached. A file listed here is a file the dump did not cover,
## whatever the dump said. Run it beside the dump, not instead of it.

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var only: String = args[0] if args.size() > 0 else ""

	var host: Gen2ModHost = Gen2ModHost.instance()
	host.discover()
	host.load_discovered()

	var failures: Array = host.failures()
	if not failures.is_empty():
		print("refused by the host, so nothing below covers them:")
		for failure: Variant in failures:
			print("  ", failure)

	var loaded := PackedStringArray()
	for entry: Dictionary in host.loaded_mods():
		loaded.append(String(entry["id"]))

	var uncovered: int = 0
	for manifest: Gen2ModManifest in host.manifests():
		if not only.is_empty() and String(manifest.id) != only:
			continue
		var scripts: PackedStringArray = _scripts(manifest.directory)
		# A mod the launcher did not load is a different question from a file its
		# load missed, so it is said plainly rather than counted as a gap.
		if not loaded.has(String(manifest.id)):
			print("%-22s %2d scripts, not loaded" % [manifest.id, scripts.size()])
			continue
		var missed := PackedStringArray()
		for path: String in scripts:
			if not ResourceLoader.has_cached(path):
				missed.append(path.trim_prefix(manifest.directory + "/"))
		uncovered += missed.size()
		print("%-22s %2d scripts, %2d not reached%s" % [
			manifest.id, scripts.size(), missed.size(),
			"" if missed.is_empty() else ": " + ", ".join(missed)
		])
	if uncovered > 0:
		print("%d script(s) an editor sweep would not have analysed" % uncovered)
	quit(1 if uncovered > 0 else 0)


func _scripts(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			out.append("%s/%s" % [dir, file])
	for sub: String in DirAccess.get_directories_at(dir):
		out.append_array(_scripts("%s/%s" % [dir, sub]))
	return out
