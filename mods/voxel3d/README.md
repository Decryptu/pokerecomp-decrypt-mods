# Voxel 3D

The overworld as a voxel diorama, and the fight staged on the map it started on.
The same map, the same collision, the same palettes: geometry extruded from what
the game already decoded, textured with the cartridge's own tileset art. No 3D
assets ship with this mod, and none could, because everything it draws comes out
of the player's own cartridge.

## Controls

| Key | Does |
| --- | --- |
| `V` | Switch between this and the Game Boy Color view. The host owns this key, in the overworld and in a battle alike |
| `Q` / `E`, or the wheel | Zoom the lens, in both views |
| `W` / `S` | Raise and lower the camera, in both views |
| `A` / `D` | Battle: swing the shot around the arena |
| `-` / `=` | Overworld: pull the camera back and push it in |

One binding, in `steering.gd`, and both views read it, so a wheel notch means
one thing in the mod. Both views zoom the LENS and never the distance: a rig
derives its field of view from where the eye sits, so moving the eye instead
would change the perspective without changing the framing. The dolly is the
overworld's alone, because the battle's seat is solved against the hardware's
own picture slots and moving it is what breaks them.

Both axes of the battle camera stop where the composition does. Left stops at the
shot the rig was solved for, because there is nothing to the left of it; right
ends side on, with both battlers the same distance away instead of one behind the
other. Down stops at the rig's own low stance and up is 45 degrees above it, taken
about what the lens is aimed at so the pair stays framed the whole way.

Movement and interaction keys never reach the mod: the world screen claims what
it needs and offers the rest, so the camera can be steered while the game is
still played on the grid it always was.

## Settings

Three, in the start menu's MODS entry and on this mod's card in the launcher.
Both surfaces are built by the host out of one registration in `options.gd`, so
this mod writes no settings screen. Values are per installation and not per save:
a draw distance must not change when a slot is loaded.

| Setting | Rungs | Does |
| --- | --- | --- |
| DISTANCE | 12, 16, 24, FULL | How far out the map is meshed, in walk cells |
| WHEEL | NORMAL, INVERTED | Which way a wheel notch zooms |
| CAMERA | LOW, MID, HIGH | The pitch the overworld camera opens at |

DISTANCE is where the frame time is. The biggest map meshes whole in 39 ms of
geometry and in 13 ms at sixteen cells, for the same picture: at the default
pitch the eye frames about sixteen cells of ground and no more. A LOW camera is
the case that sees past a window, because its top edge runs nearly level and
reaches ninety cells out, and there the cut edge shows. FULL is for that.

Walking out of the middle of the window rebuilds it around you. The map is
resolved once and only the geometry is emitted again, so a recentre is the cheap
two thirds of a build, and the margin is a third of the distance so it is not
most steps.

The map is built in CHUNKS of 16 tiles square, one mesh each, because the engine
culls per instance: as one mesh a map can only be accepted or rejected whole, and
at any camera angle most of it is behind the eye. Measured on the default shot,
about half the geometry falls outside the frustum on a town and on the largest
route alike.

A build is spread over frames rather than taken in one: a surveyed town is 200 ms
of geometry, which was a visible stop on every warp. Whatever is already on
screen keeps being drawn while the next map builds, so the map arrives a moment
late instead of the frame stopping. A battle also keeps the map it resolved, so a
second fight on the same route pays for the geometry alone.

## The text box

Over this view the screen's own text box is drawn with its FIELD at 0.75 and its
frame and glyphs solid, so a prompt reads exactly as well and the map is still
there behind it. The overworld also pans the shot up by half of what the box
covers, so the player stands in the middle of what is left rather than behind it.
The battle does not: each battler is pinned to its own hardware picture slot,
which is what makes a collision with the box impossible in the first place.

## The battle

`Gen2BattleScreen` hands over display values and, once per battle, a
`Gen2BattleWorldContext` saying where the encounter happened. That is enough to
rebuild the map from its records with the same mesher the overworld uses and
stand the two battlers on it.

The shot is a solve, not a taste. Each battler is pinned to its patch of ground
and drawn in hardware pixels at the size the cartridge drew it, wherever that
patch projects to, so the camera is what decides where the fight appears. It has
to land those two patches on the hardware's own picture slots, bottom centre of
the 6x6 for the player's and of the 7x7 for the foe's. Four coordinates, four
equations, and `battle/arena.gd`'s rig is their solution: a 23.6 degree lens from
about five cells back and two above the floor, with the two battlers three cells
apart.

Landing those marks is also what keeps the fight readable. The panels and the
text box are drawn where the hardware draws them, and a composition that puts
each battler in its own hardware slot cannot collide with either.

A pinned picture is not in the 3D scene and has nothing to cast, so each battler
also hands the sun an upright card of the same drawing at the same size, drawn
into the shadow pass and nowhere else. The shadow that falls is the animal's own
silhouette, and being a real shadow it lands on the floor, climbs a wall behind
it and drapes over a ledge from the light the terrain already casts by. Actor
cards in the overworld are given theirs the same way.

The arena's axis is the map's own north, the foe at the north end, and the eye
sits east of it: east is what decides which battler is on which side, and it is
the hardware's layout arrived at by standing in the right place rather than by
mirroring anything. Ground is chosen by the shape the fight needs, three cells
down a column with a one-cell apron, and every candidate is tested down both
sight lines, because walkable is not the same question as visible: a fence or a
building corner hides a battler completely while the cells it stands on are
perfectly walkable.

Two layers, because a battle is two things at once. The map is geometry at window
resolution; the panels, the bars and the text box stay hardware pixels, drawn at
whole-number scale over the top so a Game Boy pixel is still a square. Each panel
gets a light translucent backing, because the cartridge draws black glyphs
straight onto the white field and over a route they would be black on grass.

A battler is cut out of that field by region rather than by colour. The field is
colour index 0, and so is every white inside the drawing: an eye highlight, a
tooth, Marill's belly. The cut floods in from the border through index 0 alone
and stops at the drawing's own black outline, so what the outline encloses
survives and only the field is removed.

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

## A building is several of those at once

One house drawing packs the lot: the bottom rows are the facade seen face-on,
the rows above are the roof seen from above, and a taller section behind can put
another facade above that roof again. So no single model covers a building, and
a tile id is not a band. The profile says only which of the two surfaces each
drawing is, and how far a sloped roof tile has fallen from the flat section
beside it; where it ends up is measured off the building's own grid.

Rows are read from the bottom of the map up, so a column knows what it stands on
before it is asked how high it reaches. A run of facade rows folds face-on as one
wall, lifted by whatever is under it. A roof row lies flat at the height its own
row agrees on and passes that height up to whatever stands on it.

The row agrees, not the column, because the columns carrying a gable have no wall
under them at all: the flat section is what knows how high the roof is, and a
sloped tile is that height less the band or two its drawing has fallen. A run
breaks at every column that is not roof, so two buildings never agree with each
other.

## Past the edge of the map

Out of doors, the ground runs on for another thirty-two tiles rather than
stopping dead, so a route ends at a horizon instead of at a cliff of nothing, and a fight staged near
an edge is not shot against sky. What is carried out is the FLOOR at that edge
and nothing else: the tree line or the fence a map ends in is a thing standing on
the floor, and repeating it outward would build a wall around the world. The
floor is the nearest flat tile inward from the edge, which is why a shoreline
carries the water out and not the beach.

Out of doors only: a room ends at its walls and there is nothing past them, so
carrying a floor out of a house would lay its lino across the void it is drawn
against. `Gen2WorldPhoneHost.is_outside_environment` is the host's own answer to
which a map is.

At any draw distance short of FULL the window clips most of it. At FULL it is
paid for whole, and on a large route that is about as much geometry again as the
map itself.

## A drawing bigger than one cell

A cutout stands the drawing's own silhouette up, and some drawings are bigger
than the cell they start in. The mask is cut over the whole drawing, or the flood
runs along the seam between its cells: a cell in the middle of a flower bed has
no ground on its own border for the flood to come in through, and would be eaten
whole.

What those extra rows MEAN is the drawing's own business, and two drawings of the
same size mean opposite things. The potted plant's four rows are leaves above a
pot, so it stands as tall as the drawing and every tile of it sits at the depth
of the foot; giving each row its own depth would leave the leaves beside the pot.
The long flower bed's four rows are the same bed carrying on away from the eye,
so it is no taller than the short bed beside it and each of its cells stands its
own two rows at its own depth.

How big a drawing can be comes from the class; whether a given placement is that
big comes from the map, because the short bed and the long one are drawn out of
the same top and bottom tiles.

## Where a shape comes from

`shape/tile_shape.gd` resolves every tile, in this order:

1. a pin in `shape/profile.gd`, except a building pin in a walkable cell: one
   plain tile draws both a house wall and the pavement in front of it, and a
   building is never walked on
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

A facade is measured the same way, in tile rows rather than in cells: a plaza's
brick pavement is eight rows of the one tile, and its length would stand a
monolith where there is a low wall.

Then the structure as a whole agrees. A period is a fact about one column, and a
hedge meeting another hedge at a T-junction has no repeat in the column through
the junction, so that one column stood three cells tall in the middle of a
knee-high maze. Connected cells are flooded into one structure and the height
most of its cells measured caps all of it. It can only bring a column down: one
that measured short measured short off its own drawing, which is evidence rather
than an accident.

## Two levels of ground

A rock wall is not one height, it is two: the wall, and the stone floor behind it
standing on top of the wall. No measurement of a column can reach that, because
the column through the floor up there is drawn as plain ground.

The cliff itself is what says so. Its face is named in the profile, and the run
of face in each column gives two answers: the flat ground north of the run is up
on top of it, the flat ground south of it is where the ground plane is. Both are
carried across the floor by flooding it, because a plateau is a region and not a
strip, and a region that ends up with both answers is left alone rather than
guessed at. A plateau always opens somewhere, round a diagonal corner or at a way
up, and a leak through one of those reaches ground the cliff is standing on, so
the answer is a contradiction and not a wrong height.

The plateau's far edge is one flat row with the seam drawn inside it and the low
ground carrying on immediately above; it ends the region and then takes the
height of what is south of it. A pool with nothing but raised floor around it
rises with the floor and keeps its recess.

## Surveying a tileset

The measurement is right for most of the world and wrong for the drawings that
depict something other than a wall. Finding those is a loop, and its unit is the
BLOCK: 4x4 tiles on 2x2 walk cells, which is what Generation II authors the world
out of. A tree, a sign, a fence corner or a stretch of path is one block.

```bash
Godot --path <pokerecomp> -s <this checkout>/tools/survey.gd -- <cache> all out/
python3 tools/survey_sheet.py out/
```

That lays every block a tileset places beside the mod's own build of it, numbered,
one sheet per tileset and about eight seconds for the whole game.

1. Read the sheet. The cartridge's drawing is the authority for what a thing IS.
2. Write the failures as a list: `#4 bookcase, #6 planter, #22 bed`.
3. Pin them in `shape/profile.gd` under the tileset's number, with the class whose
   art mode matches what the drawing depicts.
4. Re-shoot the whole tileset, not the blocks that were pinned: heights are
   measured per column, so a pin changes what its neighbours measure.
5. Every map sharing that tileset inherits the pins.

A pin is presentational and can only ever be. Collision, warps, triggers and
scripts read the same data they always did, and a fix that seems to need a
collision change is the wrong fix.

## Two tables of pins

`shape/profile.gd` is hand-authored from the reviewer's own measurements off the
drawing. `shape/profile_pass.gd` is generated from a full pass over every tileset
in the game, where the same ringed picture that makes a tileset answerable by a
person is read tile by tile, and the answers become pins. The hand table wins
wherever both name a tile, and the generated one can be thrown away and rebuilt.
All thirty-five tilesets are covered: 3618 tiles read, 2168 of them pinned, the
rest left to the automatic resolution because it already stands a wall up and
measures its height off the drawing where a pin would force one.

The pass is measured rather than trusted: run blind against a tileset the
reviewer had already answered, it agreed on 63 of the 67 tiles they had settled,
and every miss was one it had marked short of sure. What it cannot settle goes
back to a person with its own description already written in.

## Layout

```
mod.gd               registers both renderers and the settings, and returns
options.gd           the settings, named once, registered and read back here
steering.gd          what a key or a wheel notch means, in either view
world/renderer.gd    the overworld Node the host builds
world/diorama.gd     the 3D stage both views share: viewport, daylight, cards
world/camera_rig.gd  pitch, distance, lens and the ease between settings
battle/renderer.gd   the battle Node: the arena, the battlers and the panels
battle/arena.gd      where the fight is staged and where it is shot from
shape/atlas.gd       the tileset as a texture, palettes and tile animation
shape/map_source.gd  the map, live from the world or read from its records
shape/tile_shape.gd  tile -> shape class
shape/profile.gd     hand-authored pins and the class table
shape/profile_pass.gd  the generated second table, one pin per tile of the game
shape/mesher.gd      map -> one static mesh
```

## Credits

The voxelization approach follows
[DramaticShapeVoxelMod](https://github.com/DramaticShape/DramaticShapeVoxelMod),
which worked out how to turn Generation I's flat tile art into geometry without
authoring any. That mod is for a different game on a different engine; what is
borrowed is the method, not the code.
