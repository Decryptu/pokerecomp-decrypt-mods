# pokerecomp mods

Mods for [pokerecomp](https://github.com/Decryptu/pokerecomp), the Pokemon Gold,
Silver and Crystal recompilation. Each one is interpreted GDScript under
`mods/<id>/` and installs as a `.zip` on every platform the game runs on.

## The mods

| Mod | Version | What it does |
| --- | --- | --- |
| [`voxel3d`](mods/voxel3d/) | 0.3.5 | The overworld as a voxel diorama, textured from the cartridge's own tileset and drawn at the window's resolution, and the fight staged on the map it started on with a steerable over-the-shoulder camera. `V` switches views. |
| [`randomizer`](mods/randomizer/) | 0.1.0 | A run generated from a four-digit seed: what appears in the grass, base stats, types, movesets, evolutions, move power and accuracy, and every trainer's team. The same seed on the same cartridge is the same game, on anyone's machine. Each of the seven is its own setting. |
| [`follower`](mods/follower/) | 0.1.0 | One of your Pokemon out of its ball, walking the cell you just left, drawn with the cartridge's own party icon for its species. Pick the slot, whether it stays out on a bike and on the water, and put it away with one press. |

## Installing

Two routes, both ending in the same installer:

**Follow this index.** In the game's launcher, on its mods page, add:

```
Decryptu/pokerecomp-decrypt-mods
```

The launcher resolves that to the feed itself, which can be pasted instead and
means the same thing:

```
https://decryptu.github.io/pokerecomp-decrypt-mods/index.json
```

Either lists everything above; picking one downloads and installs it. A mod
listed here is grouped under this index in the launcher, so uninstalling it
leaves the row behind and the download is one press away again.

**Or install a `.zip` by hand.** Take an archive from
[Releases](https://github.com/Decryptu/pokerecomp-decrypt-mods/releases) and use
**Install** on the same page, or drop it on the window where the OS offers that.
A copy installed this way belongs to no index, so the launcher files it under
"Installed from a file" and removing it deletes it.

Following an index is trusting whoever publishes it, so the game follows none
until you add one. Nothing here asks for a permission a hand-picked `.zip` would
not.

## Building an archive

An archive holds one mod, at its root or in a single folder, and the manifest id
inside has to match what the index advertised:

```sh
sh tools/package.sh voxel3d
```

The result lands in `dist/`.

## Developing

See [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) for the local loop: linking a
mod directory into the game's `user://mods/` so an edit is one restart away, and
the boundary a mod is allowed to reach through.

## License

MIT, in [`LICENSE`](LICENSE). No cartridge data, artwork or audio is included in
this repository or in any mod it publishes: geometry, colour and text all come
from what the host game decoded from the player's own cartridge.
