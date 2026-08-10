# Voxel 3D

The overworld as a voxel diorama. The same map, the same collision, the same
palettes: geometry extruded from what the game already decoded, textured with the
cartridge's own tileset art. No 3D assets ship with this mod, and none could,
because everything it draws comes out of the player's own cartridge.

## Controls

| Key | Does |
| --- | --- |
| `V` | Switch between this and the Game Boy Color view. The host owns this key |
| `Q` / `E` | Lower and raise the camera |
| `-` / `=`, or the wheel | Pull the camera back and push it in |

Movement and interaction keys never reach the mod: the world screen claims what
it needs and offers the rest, so the camera can be steered while the game is
still played on the grid it always was.

## How a flat drawing becomes a solid

A Game Boy overworld drawing is a fake-3D projection: it packs several facings
into one flat image. Roofs are drawn seen from above, walls seen face-on. So
voxelizing is not one operation. It is classifying each tile by which surface it
depicts, then applying the matching geometry.

Three models come out of that, and `shape/mesher.gd` builds them:

| Model | Tiles | Geometry |
| --- | --- | --- |
| flat | ground, water | one quad. Water is recessed, so a shoreline shows a lip |
| top art | ledges, roofs, beds | a box wearing its own art on the TOP face |
| volume | walls, canopies, facades | a box whose SOUTH face folds the artwork upright, 8px band by band, band k sampling the map row k tiles north of the structure's base |

The fold is the whole trick. Most of Generation II is drawn face-on, so standing
the drawing up is what turns a wall into a wall.

## Where a shape comes from

`shape/tile_shape.gd` resolves every tile, in this order:

1. a pin in `shape/profile.gd`
2. the walk cell's collision permission is water, so the tile is water
3. the walk cell's collision permission is walkable, so the tile is ground
4. anything left is a volume

Steps 2 and 3 work at CELL granularity because that is the granularity collision
has: Generation II stores one permission byte per 2x2 walk cell. A tile in a
walkable cell is ground the player is standing on whatever it is drawn as, which
is what keeps flowers, grass tufts and the gaps between fence posts from
extruding into pillars. Only a pin overrides that.

## How tall a thing is

An unpinned volume's height is measured, not assumed, and measured in walk cells
because that is what the world is built out of.

Every run of volume cells up a column takes the run's PERIOD: the shortest
stretch at the run's southern end that the cells behind it immediately repeat. A
house of three different cells has no repeat and stands three cells tall. A fence
line running north is one cell repeated twenty times, and stands one cell tall
however far it runs. Reading the run's raw length instead is what turns a town
into a maze of 48px walls.

## Surveying a tileset

The measurement is right for most of the world and wrong for the drawings that
depict something other than a wall. Finding those is a loop:

1. Stand somewhere and compare the diorama against the 2D view at several camera
   pitches. The 2D view is the authority for what an object IS.
2. Name the failure. Furniture at wall height, a prop lying flat, a bed standing
   upright, a house wearing its own elevation as a cube.
3. Pin the tiles in `shape/profile.gd` under the tileset's number, with the class
   whose art mode matches what the drawing depicts.
4. Re-check, and check the neighbours too: heights are measured per column, so a
   pin changes what the columns beside it measure.
5. Every map sharing that tileset inherits the pins. Check one other.

A pin is presentational and can only ever be. Collision, warps, triggers and
scripts read the same data they always did, and a fix that seems to need a
collision change is the wrong fix.

## Layout

```
mod.gd              registers the renderer and returns
world/renderer.gd   the Node the host builds: viewport, camera, lights, actors
world/camera_rig.gd pitch, distance and the ease between settings
shape/atlas.gd      the tileset as a texture, palettes and tile animation
shape/tile_shape.gd tile -> shape class
shape/profile.gd    hand-authored pins and the class table
shape/mesher.gd     map -> one static mesh
```

## Credits

The voxelization approach follows
[DramaticShapeVoxelMod](https://github.com/DramaticShape/DramaticShapeVoxelMod),
which worked out how to turn Generation I's flat tile art into geometry without
authoring any. That mod is for a different game on a different engine; what is
borrowed is the method, not the code.
