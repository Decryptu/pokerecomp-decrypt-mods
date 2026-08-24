extends RefCounted

## Refuses an output path that would be written inside the game project.
##
## THESE TOOLS RUN WITH `--path <pokerecomp>`, SO THE GAME PROJECT IS WHAT A
## PATH RESOLVES AGAINST, not the directory the command was run from. A bare
## `out.png` lands in somebody else's checkout, and the editor then makes an
## `.import` file beside it; that happened once and left both behind.
##
## THE TEST IS WHERE THE PATH ENDS UP, NOT HOW IT IS SPELT. `res://out.png` is
## an absolute path by `is_absolute_path()` and lands in the game project just
## as a bare name does, so a guard written on prefixes lets through the one
## thing it exists to stop. Globalizing answers the question directly, and it
## also catches an absolute path that happens to point into the checkout.
##
## `user://` is allowed: it is the userdata directory, which is where a probe's
## own scratch belongs and is not the game project.


## True when `path` is refused, having said why. A tool quits on true.
static func refuses(path: String) -> bool:
	if path.is_empty():
		print("no output path given")
		return true
	var project: String = ProjectSettings.globalize_path("res://").simplify_path()
	var full: String = ProjectSettings.globalize_path(path).simplify_path()
	# A relative path globalizes unchanged, and Godot resolves it against the
	# project, so that is where it has to be measured.
	if not full.is_absolute_path():
		full = project.path_join(full)
	if full != project and not full.begins_with(project + "/"):
		return false
	print("refusing %s: it would be written to %s, inside the game project."
		% [path, full]
		+ " Give a path outside it, or a user:// one.")
	return true
