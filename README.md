# pokerecomp mods

Mods for [pokerecomp](https://github.com/Decryptu/pokerecomp), the Pokemon Gold,
Silver and Crystal recompilation. Each one is interpreted GDScript under
`mods/<id>/` and installs as a `.zip` on every platform the game runs on.

## The mods

| | Mod | Version | What it does |
| --- | --- | --- | --- |
| <img src="docs/icons/voxel3d.png" alt="" width="64" height="64"> | [`voxel3d`](mods/voxel3d/) | 0.3.18 | The overworld as a voxel diorama, textured from the cartridge's own tileset and drawn at the window's resolution, and the fight staged on the map it started on with a steerable over-the-shoulder camera. One switch on its page turns it on for both. |
| <img src="docs/icons/randomizer.png" alt="" width="64" height="64"> | [`randomizer`](mods/randomizer/) | 0.3.0 | A save-bound run generated from a four-digit seed: Pokemon, wild sources, items, badges, shops, species, moves and trainer teams, with host-validated critical placements. |
| <img src="docs/icons/follower.png" alt="" width="64" height="64"> | [`follower`](mods/follower/) | 0.3.0 | One of your Pokemon out of its ball, walking one cell behind you. Choose it directly from that Pokemon's party menu, configure cycling and surfing, and put it away with one press. Face it and press A to pet it, and let it find hidden items if you want it to. |
| <img src="docs/icons/overworld_encounters.png" alt="" width="64" height="64"> | [`overworld_encounters`](mods/overworld_encounters/) | 0.1.3 | A bounded population of wild Pokemon roaming where random grass, cave and surf encounters used to be. Shiny Pokemon are visible before battle and announce themselves with the cartridge's own animation and sound. |
| <img src="docs/icons/hidden_stats.png" alt="" width="64" height="64"> | [`hidden_stats`](mods/hidden_stats/) | 0.1.0 | A fourth page on a Pokemon's stats screen, in the cartridge's own two-column shape: the DVs it was born with and the stat experience each stat has trained. |
| <img src="docs/icons/linking_cord.png" alt="" width="64" height="64"> | [`linking_cord`](mods/linking_cord/) | 0.1.0 | An item that evolves a Pokemon which otherwise only evolves by being traded. Buy it on Goldenrod Dept Store's second floor, use it from the pack, pick who it is for. |

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

The result lands in `dist/`, with `icon.png` and `thumbnail.webp` inside it if
the mod has them.

## Developing

See [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) for the local loop: linking a
mod directory into the game's `user://mods/` so an edit is one restart away, and
the boundary a mod is allowed to reach through.

## License

MIT, in [`LICENSE`](LICENSE). No cartridge data, artwork or audio is included in
this repository or in any mod it publishes: geometry, colour and text all come
from what the host game decoded from the player's own cartridge.
