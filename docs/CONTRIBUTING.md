# Contributing

## Layout

```
mods/<id>/            one installable mod; the archive root
  mod.json            manifest, validated without running mod code
  mod.gd              entry: register() takes the host and returns
  icon.png            optional 32x32 icon, drawn beside the name in the launcher
  thumbnail.webp      optional 1280x720 thumbnail, shown on the mod library site
index.json            the published feed; one row per mod
tools/package.sh      mods/<id>/ -> dist/<id>-<version>.zip
tools/mod_icons.sh    repaints every icon from one cartridge; see icon_art.gd
```

`mods/<id>/` is copied verbatim into `user://mods/<id>/`, so nothing outside it
is on a player's machine. A mod's own docs live inside it.

## Art

Both files are optional and neither is declared anywhere: dropping them at the
mod root is the whole of it. `icon.webp` and `thumb.webp` are read too, and a
manifest may name another path with `"icon"` or `"thumbnail"` if the mod keeps
its art in a subdirectory.

| | Size | Format | Where it shows |
|---|---|---|---|
| Icon | 32x32, square | PNG | Launcher list row and mod page |
| Thumbnail | 1280x720, 16:9 | WebP | The mod library website |

An icon is 32x32 because the launcher draws it at a whole multiple with nearest
filtering, so cartridge pixels stay square. Anything up to 512 on a side is
accepted and drawn without stretching; past that it is ignored.

`tools/mod_icons.sh` paints the icons in this repository out of the cartridge's
own frame, font and sprites. It is one way to make one, not a requirement: an
icon can be any square picture.

A row in `index.json` carries `icon` and `thumbnail` as https URLs, which is how
the launcher gives a mod a face before it is installed and how the website finds
its picture without opening an archive. Both point at this repository's raw
files, so they are right the moment a commit lands rather than at the next
release.

## The local loop

Link the directory into the game's user data rather than copying it, so an edit
is one restart away:

```sh
GAME=~/Library/Application\ Support/Godot/app_userdata/pokerecomp
mkdir -p "$GAME/mods"
ln -sfn "$PWD/mods/voxel3d" "$GAME/mods/voxel3d"
```

`user://mods/` is `app_userdata/pokerecomp/mods` on desktop, the app's
`Documents/mods` on iOS, and internal app storage on Android. Only desktop can
be linked; the other two take a `.zip`.

Run the game from a pokerecomp checkout:

```bash
godot --path /path/to/pokerecomp
```

The launcher lists what loaded and names anything it refused. A mod that fails
is skipped and reported through `Gen2ModHost.failures()`; it never stops the
game or the other mods.

## The boundary

Read [`docs/MODS.md`](https://github.com/Decryptu/pokerecomp/blob/main/docs/MODS.md)
in the game repository first. It is the contract, and it is enforced.

- A mod is handed `Gen2ModHost`, registers what it provides, and returns. It
  never touches a scene node or an engine internal.
- Everything reachable is cartridge content through `GameData` or live world
  state through `Gen2WorldAPI`, both scene-free.
- A renderer **reads** world state and must not write it. Two views of one world
  have to agree, which is what makes `V` able to switch between them mid-step.
- iOS forbids JIT and loading native code at runtime, so a distributed mod is
  interpreted GDScript. No GDExtension, no compiled anything.
- `api_version` in a manifest must equal `Gen2ModManifest.API_VERSION`. A
  mismatch is refused before any mod code runs.

## Writing rules

- No em-dashes. Check with
  `grep -rn $'\\u2014' . --exclude-dir=.git --exclude-dir=.references`.
- State each fact once, in the place that owns it, and link instead of
  repeating. Comment non-obvious constraints and source references; do not
  restate the line below.
- Before committing: review the staged list, run `git diff --cached --check`,
  and confirm nothing cartridge-derived or local-only is staged.
