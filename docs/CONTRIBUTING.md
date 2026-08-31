# Contributing

## Layout

```
mods/<id>/            one installable mod; the archive root
  mod.json            manifest, validated without running mod code
  mod.gd              entry: register() takes the host and returns
  icon.png            optional 32x32 icon, shown beside the name in the launcher
  thumbnail.webp      optional 1280x720 thumbnail, shown on the mod library site
index.json            the published feed; one row per mod
tools/package.sh      mods/<id>/ -> dist/<id>-<version>.zip
tools/check.sh        parses every script and gates its size; `tools` and `all`
                      widen what it reads, `warnings` runs the analyser
tools/bloat.py        the size gate: complexity and length per function, and
                      comment ratio per file
tools/walk_bench.gd   what a frame costs while the player walks, in the game
tools/stage_bench.gd  the same for the diorama alone, with each part priceable
tools/motion_bench.gd how far a 3D view's camera moves per drawn frame, walking
tools/horizon_shot.gd photographs the horizon through the game's own screen
tools/far_drawings.gd checks the horizon's drawings and cards against a resolve
tools/mod_icons.sh    repaints every icon from one cartridge; see icon_art.gd
docs/icons_4x/<id>.png  the same icon at 4x, for the README table only
.github/workflows/    announce.yml posts a published release to Discord
```

`mods/<id>/` is copied verbatim into `user://mods/<id>/`, so nothing outside it
reaches a player's machine. A mod's own docs live inside it.

## Art

Both files are optional and neither is declared anywhere: dropping them at the
mod root is all it takes. `icon.webp` and `thumb.webp` are read too, and a
manifest may name another path with `"icon"` or `"thumbnail"`.

| | Size | Format | Where it shows |
|---|---|---|---|
| Icon | 32x32, square | PNG | Launcher list row and mod page |
| Thumbnail | 1280x720, 16:9 | WebP | The mod library website |

An icon is 32x32 because the launcher draws it at a whole multiple with nearest
filtering, so cartridge pixels stay square. Anything up to 512 a side is accepted
and drawn without stretching; past that it is ignored.

`tools/mod_icons.sh` paints this repository's icons out of the cartridge's own
frame, font and sprites. It is one way to make one, not a requirement.

`docs/icons_4x/` holds each icon again at 4x, drawn at 64 in the README table.
GitHub honours an `<img>` width but strips the `image-rendering` that would stop
a browser smoothing the upscale, so the sharp copy is a file rather than a style.
They live outside `mods/` so they stay out of the archives.

## Releasing

A release is made by hand, one mod at a time: `tools/package.sh <id>` builds the
archive, the release is created for the tag `<id>-<version>` with that archive
on it, and the `index.json` row naming it goes in last, since a row pointing at
a tag that does not exist advertises a download that 404s.

Publishing the release posts its URL to the project's Discord through
`.github/workflows/announce.yml`, which reads the `DISCORD_RELEASE_WEBHOOK`
repository secret. The game's own repository announces itself the same way, so
the two read alike in the channel. A fork has no such secret, and the workflow
says so and fails rather than posting nowhere quietly.

A row in `index.json` repeats the manifest's `games`, so the launcher's mod page
and the library site know which cartridges a mod is for before it is installed.
Keep the two lists the same when either changes. A row also carries `icon` and
`thumbnail` as https URLs pointing at this repository's raw files, so a mod has a
face before it is installed and the pictures are right the moment a commit lands.

Package a mod **after** its art is added. Art added after a package is art
nobody gets: the launcher resolves an icon against the installed directory.

## The local loop

Link the directory into the game's user data rather than copying it, so an edit
is one restart away:

```sh
GAME=~/Library/Application\ Support/Godot/app_userdata/pokerecomp
mkdir -p "$GAME/mods"
ln -sfn "$PWD/mods/voxel3d" "$GAME/mods/voxel3d"
```

`user://mods/` is `app_userdata/pokerecomp/mods` on desktop, the app's
`Documents/mods` on iOS, and internal app storage on Android. Only desktop can be
linked; the other two take a `.zip`.

Run the game from a pokerecomp checkout:

```bash
godot --path /path/to/pokerecomp
```

The launcher lists what loaded and names anything it refused. A mod that fails is
skipped and reported through `Gen2ModHost.failures()`; it never stops the game or
the other mods.

## What a tool is given

A tool takes the cartridge as its first argument, written `<cartridge>`, and
either form works: a cache directory such as `user://rom_cache/crystal_...`, or
a registry id such as `crystal`. `GameData.open_argument` is what answers which
of the two it was handed, so no tool sniffs it and none of them can disagree.

## Where a tool writes

A tool runs with `--path <pokerecomp>`, so a relative path resolves against the
game project, not the directory the command was run from. A bare `out.png` is
written into that checkout.

Every tool that takes an output path checks it before doing any work:

```gdscript
if Gen2ToolPath.refuses(_out):
	quit(2)
	return
```

The test is where the path ends up rather than how it is spelt, because
`res://out.png` reads as absolute and lands in the game project all the same.
Give an absolute path outside the checkout, or a `user://` one.

## The boundary

Read [`docs/MODS.md`](https://github.com/Decryptu/pokerecomp/blob/main/docs/MODS.md)
in the game repository first. It is the contract, and it is enforced.

- A mod is handed `Gen2ModHost`, registers what it provides, and returns. It
  never touches a scene node or an engine internal.
- Everything reachable is cartridge content through `GameData` or live world
  state through `Gen2WorldAPI`, both scene-free.
- A renderer **reads** world state and must not write it. Two views of one world
  have to agree, which is what lets `V` switch between them mid-step.
- iOS forbids JIT and loading native code at runtime, so a distributed mod is
  interpreted GDScript. No GDExtension, no compiled anything.
- `api_version` is the oldest host a mod works against, not a number to keep
  current. The host accepts `Gen2ModManifest.MIN_API_VERSION` to `API_VERSION`,
  1 to 21 today, and refuses a mod asking for more than it provides. Raise it
  when the mod starts using something newer, not with every release.

## Writing rules

- **Do not comment.** A name, a guard clause or a small function says it better
  and cannot go stale. The exceptions are a file header of a line or two, a fact
  from outside the file (a cartridge value, a host contract, a source reference)
  and an invariant the code does not show. One or two lines each, and never a
  paragraph defending a workaround: if a line needs one, fix the line.
- **Guard clauses, named helpers, lookup tables and early returns**, not nested
  conditions or one-liners that hide a branch. `tools/check.sh` holds every
  function to complexity 10 and 60 lines and every file to 8% comments; what was
  already over is in `tools/bloat_debt.txt`, which may only shrink.
- State each fact once, in the place that owns it, and link instead of repeating.
  Delete superseded text rather than appending to it.
- No em-dashes. Check with
  `grep -rn $'\\u2014' . --exclude-dir=.git --exclude-dir=.references`.
- No path from your own machine in a tracked file: a tool takes the location as
  an argument or an environment variable and documents a placeholder.
- Before committing: review the staged list, run `git diff --cached --check`, and
  confirm nothing cartridge-derived or local-only is staged.
