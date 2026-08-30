# Voxel 3D

The overworld drawn in 3D, and the battle staged on the map it started on. Same
map, same collision, same palettes: geometry built out of what the game already
decoded, textured with the cartridge's own tile art. No 3D assets ship with this
mod, because everything it draws comes from the player's cartridge.

## Turning it on

One switch, reachable three ways: the VIEW row in the start menu's MODS entry,
the mod's page in the launcher, and `V` where development keys are enabled. Both
renderers are registered under one id, so choosing it draws overworld and battle.

Switching takes about a fifth of a second to resolve a map and build a mesh, so
the host hides it behind the cartridge's own battle-transition wipe.

## Controls

Nine controls, declared to the host rather than read as raw keys, so all of them
are rebindable in the launcher's controls card and can go on the on-screen pad.

| Control | Key | Pad | Does |
| --- | --- | --- | --- |
| Zoom in / out | `=` / `-`, or the wheel | shoulders | Zoom the lens, in both views |
| Camera up / down | `I` / `K` | right stick | Raise and lower the camera |
| Swing left / right | `J` / `L` | right stick | Battle: swing around the arena |
| Push in / pull back | `E` / `Q` | | Overworld: move the eye |
| Recentre | `0` | right stick press | Back to the framing the view opened at |

Zoom and recentre are the keys the game already zooms the 2D view with, so one
key means one thing in either view. RECENTRE is also a MODS menu row.

Tap for one step, hold to glide: past a fifth of a second a control moves at the
rate you push it, so a stick half over glides at half speed.

Both views zoom the lens and never the distance, since the rig works its field of
view out from where the eye sits. The dolly is the overworld's alone, the battle
camera being solved against the hardware's picture slots; it stops where the
composition does, left at the solved shot, right side-on, down at the rig's low
stance and up 45 degrees above it.

Movement and interaction keys never reach the mod, so the game is still played on
the grid it always was.

## Settings

Five rows, in the start menu's MODS entry and on the mod's page in the launcher,
all from one registration in `options.gd`. Values are per installation, not per
save: a draw distance must not change when a slot is loaded.

| Setting | Rungs | Does |
| --- | --- | --- |
| DISTANCE | 12, 16, 24, FULL | How far out the map is meshed, in walk cells |
| RES | FULL, 1/2, 1/3, 1/4 | How many window pixels the 3D pass draws one of |
| WHEEL | NORMAL, INVERTED | Which way a wheel notch zooms |
| ANGLE | LOW, MID, HIGH | The pitch the overworld camera opens at |
| CAMERA | RECENTRE | A press: put the shot back the way it opened |

**RES** is where the frame time is on a device that cannot afford its window. The
2D page is 160x144 whatever the window is; this view draws at the window's own
pixel count, a hundred times the area on a phone. The divisor is quadratic, so a
half is a quarter of the work, and it costs no art quality: the picture is Game
Boy texels and a divisor draws them larger rather than blurrier. Default FULL on
desktop, a half on phone or tablet.

**DISTANCE** is the other half. The dearest map in the game is 520 ms of
geometry whole and 300 ms at sixteen cells for the same picture, since at the
default pitch the eye frames about sixteen cells of ground. Measuring that map is
another 240 ms and is paid at any distance. A LOW camera reaches ninety cells
out, and FULL is for that.

## How a map is built

Maps are built in chunks of 16 tiles square, one mesh each, because the engine
culls per instance: as one mesh a map could only be accepted or rejected whole,
and at most camera angles half of it is behind the eye. Stamped models are
grouped on the same grid, which is where a filled window pays most: on the
largest shot in the game, 5.39M triangles in 116 draws becomes 1.26M in 166.

A build is spread over frames, since a town is 200 ms of geometry and that was a
visible stop on every warp; whatever is on screen keeps being drawn meanwhile.
Measuring the map is spread the same way, one pass of it a frame. A battle keeps
the map it resolved, so a second fight on a route pays for geometry alone.

Walking out of the middle of the window rebuilds it around you: the map is
resolved once and only the geometry emitted again, with a margin of a third of
the draw distance so this is not most steps. Chunks are cut to the map rather
than the window, making a chunk's rectangle a fact about the map instead of about
where the player stood, so a rebuild reuses four fifths of them: 3 to 30 ms
instead of 80 to 150.

A cached chunk may not depend on its neighbours, and a house, an object, a
staircase or a fence can each cross a chunk edge. Each structure has one owner,
the chunk that reached it first, and a chunk that shares one is never cached.
`tools/mesh_cache_probe.gd` proves a window reached by walking and a window built
by a reused mesher both draw what a fresh mesher draws, on every map.

## The 2D screens over the top

Over this view the text box is drawn with its field at 0.75 and its frame and
glyphs solid, so a prompt reads as well as ever and the map is visible behind it.
The overworld only pans up when a box would actually cover the player, which the
cartridge's bottom-third box never does. The battle never pans, since each
battler is pinned to its own hardware picture slot.

The pack, party, PC, dex, trainer card, evolutions, hatches, the day-care, the
slot machine, card flip and the encounter transition are laid out in 160x144 and
own the whole picture while up. A letterbox would crop a picture that had filled
the window, so the surround is closed in this mod's own final pass: black, to the
window edge.

A battle fills the window with the map it started on. Only the arena grows: the
panels, bars and text stay hardware pixels in the same centred rectangle.

Two whole-screen effects the cartridge draws are reproduced here. The encounter
transition blacks out 20x18 cells a few at a time with a Poke Ball stamped over
the top, drawn in the cartridge's own cells over the diorama and repainted only
where a cell moved. And a warp fade walks four palette orders two frames each,
read here as a curve over the four levels a Game Boy palette has: adding the
difference is right in the middle of the range and not at the ends, so the last
step is taken to the level flat rather than left at a saturated hue.

## The battle

`Gen2BattleScreen` hands over display values and, once per battle, a
`Gen2BattleWorldContext` saying where the encounter happened. That is enough to
rebuild the map with the same mesher the overworld uses and stand the battlers on
it.

**What happens to a battler.** Two trainers slide in from opposite sides, the
opponent sends out first, the player's picture walks off, and a ball puts a
Pokemon where each was standing. A faint sinks a picture, a Fly or a Dig takes it
off the field, a recall shrinks it into its ball, a Tackle lunges it. The host
resolves all of it the same way, as what each square holds, whether its picture
is on it, how far it stands from its rest and how much of itself it is. It is
spent in hardware pixels across the screen rather than as a walk over the ground,
because the cartridge moves a picture, not a person.

The whole picture is grey while the intro runs, which is the cartridge writing its
own grey over every background palette. Here it is both a pass over the diorama
and the palette the battlers are drawn in, since greying only the world left two
colour figures in a black and white one. An Unown is drawn as the letter it
actually is, and a Pokemon behind a substitute is the cartridge's own doll.

**The shot is solved, not chosen.** Each battler is pinned to its patch of ground
and drawn in hardware pixels at the size the cartridge drew it, so the camera
decides where the fight appears. It has to land those two patches on the
hardware's picture slots: bottom centre of the 6x6 for the player's and of the
7x7 for the foe's. Four coordinates, four equations, and `battle/arena.gd`'s rig
is the solution: a 23.6 degree lens about five cells back and two above the
floor, with the battlers three cells apart. Landing those marks is also what
keeps the panels and text box from colliding with a battler.

The arena's axis is the map's north with the foe at the north end and the eye to
the east, which decides who is on which side. Ground is chosen by the shape the
fight needs, three cells down a column with a one-cell apron, and every candidate
is tested down both sight lines: a fence or a building corner can hide a battler
on cells that are perfectly walkable. Stamped models take part at their model
height, so a tree cannot be picked as open foreground.

A pinned picture is not in the 3D scene, so each battler hands the sun an upright
card of the same drawing, drawn into the shadow pass only. The shadow is the
animal's own silhouette: it lands on the floor, climbs a wall and drapes over a
ledge. Overworld actor cards get theirs the same way.

The eye breathes rather than sitting still, since a flat picture has no parallax
until something moves: a one degree orbit with a smaller dolly under it, on a
different period so they never sync. It rides the arm from what the lens is aimed
at, so the battlers stay in the middle of the frame and only the background moves.

**Two layers.** The map is geometry at window resolution; the panels, bars and
text box stay hardware pixels at whole-number scale. Each panel gets a light
translucent backing, since the cartridge draws black glyphs straight onto white
and over a route they would be black on grass. What is behind it is blurred as
well as tinted, because a dithered path shows every texel through the writing and
the two compete.

A battler is cut out of its field by region, not by colour: the field is colour
index 0 and so is every white inside the drawing, so the cut floods in from the
border through index 0 alone and stops at the drawing's black outline.

**Move animations** are drawn as the hardware drew them, on their own layer. That
works because an animation is authored against the two picture slots the
cartridge puts its battlers in, and the camera is solved to land both battlers in
those slots, so a beam aimed at the far slot is already aimed at the far Pokemon.

An animation's second half reaches the whole screen: the hardware flashes by
rewriting its background palettes with one byte, and that byte is a permutation,
colour i drawn as colour `(byte >> i * 2) & 3`. That is a tone curve over four
levels, and a sixth of every move carries one. The diorama reads it as a smooth
line through those four points, moving luminance alone; the battlers take the
permutation exactly, since a pic really is four palette entries.

The third half is one a diorama cannot copy: eight animations scroll the
background a different distance on every scanline. There are no scanlines here,
and warping the world row by row would move a texel off the pixel it was drawn
on, so the whole list of offsets is read as the single displacement it averages
to and the camera is shaken by it.

## Turning flat art into solids

A Game Boy overworld drawing packs several facings into one flat image: roofs
seen from above, walls seen face-on. So voxelizing is not one operation but two:
classify each tile by the surface it depicts, then apply the matching geometry.

`shape/mesher.gd` builds three models:

| Model | Tiles | Geometry |
| --- | --- | --- |
| flat | ground, water | one quad. Water is recessed, so a shoreline shows a lip |
| top art | ledges, roofs, beds | a box wearing its art on the TOP face |
| volume | walls, canopies, facades | a box whose SOUTH face folds the art upright, 8px band by band |

The fold is the whole trick. Most of Generation II is drawn face-on, so standing
the drawing up is what turns a wall into a wall.

**Where a shape comes from.** `shape/tile_shape.gd` resolves every tile in this
order:

1. a pin in `shape/profile.gd`, unless it is a building pin in a walkable cell:
   one plain tile draws both a house wall and the pavement in front of it
2. the walk cell's collision says water, so the tile is water
3. the walk cell's collision says walkable, so the tile is ground
4. anything left is a volume

Steps 2 and 3 work per cell because that is what collision has: one permission
byte per 2x2 walk cell. A tile in a walkable cell is ground whatever it is drawn
as, which keeps flowers, grass tufts and the gaps between fence posts from
extruding into pillars. Only a pin overrides that.

**How tall a thing is** is measured in walk cells. A run of volume cells up a
column takes the run's period: the shortest stretch at its southern end that the
cells behind it repeat. A house of three different cells has no repeat and stands
three cells; a fence line running north is one cell repeated twenty times and
stands one however far it runs. Reading raw length turns a town into a maze of
48px walls. A facade is measured the same way in tile rows. Connected cells then
flood into one structure and the height most of its cells measured caps all of
it, so a hedge T-junction does not stand three cells tall in a knee-high maze.

**Cutting a drawing out of its background.** Colour cannot say where a drawing
ends: a bollard is white on a pale path and a bush is green on grass. The border
can. The ground runs to the edge of the cell and the drawing does not, so the
indices making up most of the cell's border ring are the ground, and what the
flood cannot reach through them is the drawing.

That fails on tree canopies, drawn in the same two greens the grass under them is
dithered from, so those classes flood through every pixel that is not the
drawing's darkest shade, which is its outline. How many shades bound one is per
drawing: a tree rings itself in one, a drawing meeting the ground in a paler
shade needs two.

**A drawing bigger than one cell** is masked over the whole drawing, or the flood
runs along the seam between its cells. What the extra rows mean is the drawing's
business: the potted plant's four rows are leaves above a pot, so it stands as
tall as the drawing with every tile at the depth of the foot, while the long
flower bed's four rows are the same bed carrying on away from the eye, so each
cell stands its own two rows at its own depth. How big a drawing can be comes
from its class; whether a placement is that big comes from the map.

## Buildings

One house drawing packs the lot: the bottom rows are the facade seen face-on, the
rows above are the roof seen from above, and a taller section behind can put
another facade above that roof. The profile says only which of the two surfaces
each drawing is, and how far a sloped roof tile has fallen from the flat section
beside it.

Rows are read from the bottom of the map up, so a column knows what it stands on
before it is asked how high it reaches. A run of facade rows folds as one wall,
lifted by whatever is under it. A roof row lies flat at the height its own row
agrees on and passes that height up.

**A building is no deeper than it is wide.** The fold reads a drawing's height as
depth, which is a house for a drawing eight wide and six tall and a slab for a
tower eight wide and twenty-eight. The drawn height is a fact about the facade;
the other measurement the drawing gives is its width. Only the body is shortened,
and the rows behind it come out as the ground the building stands in.

The row agrees, not the column, because the columns carrying a gable have no wall
under them: the flat section knows how high the roof is, and a sloped tile is
that height less the band or two it has fallen. A roof tile's top is a quad with
four corner heights, each the mean of the roof tiles touching it, so a fall reads
as a tilt rather than a ziggurat, and two roof tiles sharing an edge compute both
its corners from the same neighbours.

A drop is normally a fall from the flat section of the same roof. A great roof
has no flat section at all, its whole twelve-tile width falling from ridge to
eaves, so there the drop is a rate: each tile falls one more band than the last.
Which end is the ridge is decided by what lies beyond, since a roof falls away
from the floor a person stands on and toward the void.

**Some houses draw no roof from above.** Every wooden house in Johto and every
small brick one draws the front pitch face-on: four rows of plank or tile over
two rows of wall. Folded square that is a barn, so the profile names those tiles
and their bands lean back over the building's footprint, a tile of depth per band
of height. The top band stays put and each band below steps down and forward.
Two readings refuse that: a roof deck standing on the run means the face-on band
is that deck's fascia, and a column drawing roof more than once is a stack of
storeys, like Ecruteak's seven-gallery dance hall.

`shape/houses.gd` holds 103 drawings painted per pixel and matched by
arrangement, produced with `tools/house_export.gd`, `house_page.py` and
`house_pins.gd`. 92 of them reach the game: 246 placements on 64 maps, standing
up 348 buildings. `tools/house_claim.gd` counts it.

## Ledges, doors and two levels of ground

**A ledge** comes out of the collision byte, not out of a drawing:
`Gen2WorldCollision` decodes it, and the ledge is the blocked cell the hop passes
over. Those tiles are built as a wedge, a ramp rising toward the drop and a
vertical face at it, so going the way the hop goes the ground falls away under
you and coming back there is a small wall in front of you. Where perpendicular
runs meet at a corner, their intersection inherits both slopes. The player and
scripted NPCs follow the host's own jump offset while crossing; the card rises
and lands while its shadow and the camera stay on the ground. 1380 cells on 72
maps are hopped over, and before this they were 16px walls you could not see
over.

**A door** is walkable, so a pass reading collision called it ground and the
doorway came out as a hole through the building. The cartridge is asked instead:
a cell whose collision is a door, its second door code or a cave takes the height
of the wall around it and the face machinery paints its drawing on. Warp carpets
are deliberately excluded, since a carpet is a floor you walk onto and every map
edge has one.

**A rock wall is two heights**, the wall and the stone floor standing on top of
it, and no measurement of a column reaches that, because the column through the
floor up there is drawn as plain ground. The cliff says so instead: its face is
named in the profile, and the run of face in each column says the flat ground
north of it is on top and the flat ground under its front band is the ground
plane. Under the FRONT rather than under the run, because a column at a corner
carries the front at the top and then runs on down the rim beside the plateau,
so what lies under the bottom of it is more plateau: read the other way, six
such columns told Cianwood that its rock was the ground its own wall stands on.
Both answers are carried across by flooding, because a plateau is a region and
not a strip, and a region that ends up with both is left alone: a plateau always
opens somewhere, so a leak is a contradiction rather than a wrong height.

How tall a face stands is read per connected structure, off the runs of front its
columns draw. A structure that draws no front anywhere is a rim seen from the
side and has nothing in it to measure, so it keeps what the column pass made of
it, capped at the tallest face the map does draw: without the cap a rim sixteen
tiles long came out sixteen tiles tall.

What stands beside a tile is read at the edge the two share. A box is one height
and a rim is four, one per corner, so a face closed against a rim's single
measured height is closed against nothing. The lower of the two shared corners is
what a face reaches down to, which can only add face and never take one away.

## Objects that are not tiles

A chair is drawn as four corners across four tiles, and one tile is the desk's
bottom-left leg, the chair's top-left corner and the floor between them at once,
so every possible per-tile answer is wrong.

An object is therefore identified by the arrangement of tile ids it is drawn out
of, which finds it wherever the map places it and whatever block boundary it
straddles. Every tile the arrangement covers goes back to floor and one thing of
the object's size is stood up. Two objects may cover one tile and both are drawn,
which is a desk and the chair tucked under it.

A 2.5D drawing is a top and a front stacked: the first rows lie across the
object's depth, the rest hang down its height. Where a drawing has a top band
those two row counts are the depth and the height; where it has none, which is a
chair drawn face-on, the depth has to be given. Height is not the drawing's to
say either, since a chair's twelve drawn rows stood up as twelve pixels is a
cabinet beside a desk half its height. What a face-on drawing states honestly is
its width.

**Where it stands** is the collision's to say. A drawing puts its front-bottom
corner at its own bottom row, and the cartridge draws a free-standing bench's
apron on the walk cell in front of the one the bench blocks, so read literally the
box came out half a cell into open floor. A box standing on floor a body can stand
on is pulled back to the near edge of the last cell the drawing covers that is
blocked all the way across, and only where that clears the box entirely. Fourteen
placements move over the whole game. A chair, a stool and a ladder stand on cells
the cartridge lets you walk onto, which is its answer and not a placement to
correct: an object with a height gives its cells a walkable top, and the walker
and its shadow both read that, so all 585 seats are stood on rather than stood
inside.

An object may be **turned** rather than stood up, because a round drawing wants a
lathed model. Sixteen things are declared this way: a desk, five chairs, a ship, a
stone vessel, a ticket gate, a fountain, a great roof's ridge, a parked bicycle, a
television, a low padded seat, an open bin and a park bench. Three of them are
what a fallback that revolves a drawing cannot do: a bicycle drawn side-on is a
portrait three tiles wide, and turned it came out as a row of bollards.

The bench is the one with a back, and it is why objects have their own builder:
its three drawn rows are the back, the seat and a leg at each end, so what is
authored is the depth and the three heights.

A **kerb** is terrain rather than an object: one course of masonry standing half a
cell, which rings a flower bed and holds the water in a fountain. A **sea rock**
is stone drawn in the water rather than standing on it, so the tile stays flat
water and the stone stands out of it; read as a boulder it goes looking for a
floor and always finds one.

The largest is the ship at the port, fifteen tiles by six, and it added one rule:
a bounding box is not a footprint. The tiles in the box that are not the object
are open sea, so they are declared as outside it and stay sea, while remaining
part of the rectangle the mask is cut over, because a mask floods in from the
border and the border of the hull's rectangle is half hull.

A **staircase** is found the same way. Generation II draws a flight as a
perspective view over four tiles, and stepping onto one leaves the floor rather
than climbing it, so a down flight is a hole: the cell's floor goes a walk cell
below the ground and everything skirts down to it, which is the same code that
draws a cliff. A ladder in a shaft is that with the steps taken out.

## Past the edge of the map

Past its edge the cartridge repeats the map's own border block, and so does this,
stood up rather than flattened: eighteen maps end in a tree line, sixteen in a
hedge, twenty in open sea. The map is resolved inside the ring, so a tree out
there is measured, masked, modelled and stamped by the same code that does it
inside the map.

How deep the ring goes is decided by what it buys. One block for most, which is
what makes a coast run out as sea and not as beach. Four blocks where the block
is a stamped model, since a tree emits no geometry at all and a route can really
end in a wood. A carved drawing stays at one block, since a hedge bush is about
170 triangles a tile.

Then a SIDE grows, a walk cell at a time and at most two blocks, while its own
outer edge would cut a drawing in half. A ring that ends in the middle of a house
stands the half it can see up as though it were whole, roofless and wearing its
own wall on the lid; Saffron ends four tiles short of the roof of Route 5's gate.
Per side, because the grid is what costs: clearing that one gate by deepening
every side is a fifth of the game's resolve and deepening the north alone is a
twenty-fifth of Saffron's. Sixteen maps grow one.

**The ring is the map next door** wherever there is one, since the host places
the whole neighbouring map on the connection graph: 1977 blocks on 68 of
Crystal's 77 outdoor maps. It is the difference between a tree line at a seam
being a skyline with gaps and being one flat mass of canopy. A neighbour on
another tileset is refused and takes the border block, since its blocks are
numbered in its own tileset.

Beyond the ring the floor runs on for thirty-two tiles, so a route ends at a
horizon instead of a cliff of nothing. That floor is the nearest flat tile
inward, which is why a shoreline carries the water out and not the beach. A
doorway is passed over on the way in: it is flat art standing at the height of
the wall around it, and taken for floor it ran a wall of the building's own
drawing sixteen tiles out into open country on eight maps.

**Indoors the ring is a room.** A Game Boy camera never stands outside a room, so
the cartridge draws only the wall the player looks at, which from any bearing but
due north read as furniture on a floor with no room around it. So the map is
ringed one cell deep and two cells tall with the blank wall course that tileset
is drawn with, and the wall the cartridge does draw is raised to meet it.
Twenty-nine tilesets name that course, covering 308 of the game's 311 interiors.
A cavern gets a ring cut from its own rock face. The three interiors with no
shell are a gym whose perimeter the cartridge really does draw, and two maps the
game files as caves and paints as forest.

The floor out there is a solid and not a lid: it is read per column, so two
columns of one edge answer at two heights wherever the perimeter steps, and each
skirt tile closes down to whatever stands beside it.

## The far field

Past the mesh the ground carries on, flat, one quad a map, folded on the GPU the
way the game folds its own 2D page: block byte, metatile slot, tile, texel. Where
those maps go is the connection graph the 2D view uses, so the two agree about
what is over the hill, and the map header's border block fills whatever no map
covers. Nothing is baked, and the loaded map shares the sheet the tile animation
repaints, so flowers past the window open with the ones inside it.

It is also the level of detail, and that is the part worth having: where the
window cuts, what carries on is the same map with its height thrown away, which
is what a Game Boy drew in the first place. Ten draws and three thousand
triangles on the largest shot in the game, against tens of maps of geometry for
the same picture.

The people on those maps come with it, because the 2D view draws them. They are
the game's own read-only copies: no step, no script, no collision, and they
cannot be talked to.

**Aerial perspective** is what makes a flat far field read as distance rather
than a page laid beside the diorama. Its colour is the sky's own horizon rather
than a chosen grey, so the ground fades into what is above it and the hour
carries both. It starts nine hundred world pixels out, past everything a player
is playing in. Indoors the far field is off entirely: carrying a floor out of a
house would lay its lino across the void.

**Trees and buildings stand on it.** A far map is walked once, tile by tile,
asking the tileset which drawing stands where, which costs about 13 ms a map
against the quarter of a second a real resolve takes. The map under the player is
walked over the mesher's own grid, `stamped_bounds_tiles`, since that ring is
grown a side at a time and one margin cannot say where the walk ends. Each
drawing wears a card cut from its own map's sheet by
`shape/mesher.gd:far_card_for`, named by its whole arrangement of tiles through
`shape/far_drawings.gd`, so a neighbour's conifers are its own and not this
map's. `tools/far_drawings.gd` checks that against a real resolve over all 77
outdoor maps: every card is the mesh's own pixel for pixel, and every drawing
stands on the same spots. One simplification is deliberate: a drawing gets one
card rather than its own bodies, so a cell of four sea rocks is one rock out
there. `world/far_houses.gd` stands a far building as a roof over a footprint
with a wall under the front, painted off that map's sheet: a box and not a house,
since out here a map has to be stood up in milliseconds.

**Past every map** the cartridge fills everything with one border block repeated
to the horizon, and on forty of the seventy-seven outdoor maps every tile of it
is a tree. The same cards stand on a ring round the eye. The ring has to reach
the horizon or it does nothing, since the page and a standing wood differ in tone
rather than shape and a short ring draws a pale band across the distance. It does
not have to be thick: a 16px card at three thousand pixels hides 450 pixels of
ground behind it, so every eighth block closes the distance and four doubling
rungs out to 4800 pixels cost about 12700 cards against 624000 for the same reach
paved solid. It is rebuilt when the eye has drifted 512 world pixels, measured as
a circle rather than a lattice, since a grid rebuilds every time the player steps
back and forth over one of its lines.

## Near it is turned, far it is the drawing again

A stamped model is 700 to 1200 triangles and a route wears hundreds, so models
are 87 per cent of all outdoor geometry. That is worth paying where the player is
standing and nowhere else.

Past a ring 35 cells from the eye, a stamp becomes the cartridge's own drawing
stood up: two crossed quads wearing the tileset's pixels with everything that is
not the thing cut away. The mask is the one the solid is carved from, so what
stands out there is exactly what would have been turned, at the same height,
width and wind phase, and a tree crossing the ring does not change size or step
out of time. Route 32, the thickest wood in the game, goes from 1,096,319
triangles to 470,943 at the same camera.

The ring is on the eye and not the player, because a ring round the player spends
half itself behind the shot. It moves when the window rebuilds rather than when
the camera swings.

## The sky, the hour and the sun

The sky is generated: a ramp of six bands, deepest overhead, with a checkerboard
of the next band down dithered into the bottom of each. That dither is how a
machine with four colours to a palette got a fifth and a sixth out of them, and
it is what makes the bands read as a gradient rather than stripes. Six bands
rather than four, because four between two hues shows every step and lands one on
the muddy middle.

**The ramp's two ends are the hour's own.** Generation II has no sky palette, but
it keeps a blue pair in one of its background slots at every hour, and reading
that pair from the row itself, before the map loader hands those slots to a
town's roof colours, gives a sky that follows the clock and that nothing here
authored. Morning is the exception, because its pair is byte for byte day's: its
horizon is the sunrise colour from the row beside it and its deep end is the blue
the water is drawn with at that hour. A caller with no hour, which is a room and
the model turntable, gets a ramp made from the background colour alone.

**The camera has to be low enough to see any of it.** The eye looks down by its
own pitch, so with a 42 degree lens the top of the frame sits at 21 degrees minus
the pitch, and at the default 50 that edge is 29 degrees below the horizon. The
ANGLE row's lowest rung at 14 degrees is what frames any sky at all. The bands
are pinned to elevation rather than to the frame, so pitching the camera slides
the frame up a sky that stays put.

**Everything follows that clock**, including the things carrying their own
colours. The terrain is textured from the sheet, so repainting the sheet moves
it; a tree, a bush and every other stamped drawing read their colours when they
were measured and carry them in their vertices, so `mesher.gd:begin_recolour` and
`recolour_step` measure every cached model again against the repainted sheet and
rewrite the mesh, the cut-out and the far twin in place. It is spread over
frames, since it is 15.1 ms on a wooded route and a dropped frame on the hour
would be the largest stall this view has.

**The sun moves with the hour.** It rises in the east, climbs and sets in the
west, so shadows swing about a hundred degrees between morning and night and a
still picture says what time it is. It stays in the southern half of the sky at
every hour, which is not taste: a volume folds its art onto its south face, so a
sun crossing to the north would put every drawing in the game into its own
shadow. A low sun rakes, landing less light on flat ground and more on upright
faces, so morning carries more energy than day to stand the same ground up.

Its shadow is not split into cascades, and that is a third of the frame. A
parallel-split shadow draws the scene once per cascade, which is the answer to a
shadow that has to reach a landscape; this one reaches 600 world pixels at most
and DISTANCE caps it again at the mesh window. Measured on route 26,1 at the
lowest camera, one split against four: 0.64% of pixels differ at DISTANCE 12,
which is run-to-run noise, 1.17% at 16, then 8.50% at 24 and 12.40% at FULL. At
the default that is 4.55 ms a frame down to 3.03 at 2560x1440.

The cartridge's DARK palette row outdoors is near black with the standing cards
bright, and that is the cartridge: `frame.gd` skips tinting that row because its
texels are already black, and a card carries the hour's sprite palette, which is
what the 2D view draws in an unlit cave.

## Water

Everything else in this view is paint stood up and lit. Water is a mirror, and
the 2D view says so in the only way it can, by cycling the ripple art in place.
So the surface is lifted out of the terrain mesh and given three things a flat
drawing cannot carry.

The sky in the lake is the sky over it, mixed by Fresnel, so far water is bright
and near water keeps the cartridge's blue. The surface is not flat: two long
waves cross it and their gradient is the normal everything else is read through,
done per fragment so no vertex moves and the water cannot tear from its bank.

**The swell belongs to the lake, not to the player.** It is worked out from where
each piece of water is in the world, so a crest sits over the same patch of sea
however you walk around it. Read from where the fragment is on the screen
instead, which is what a fragment shader is handed by default, the whole sea
slides with the camera. The sun is hung by angle rather than screen position,
because the reflection of a sun high in the sky lands off the top of the frame at
every hour: what is asked is how nearly a piece of water is tilted to bounce the
sun into the eye, so the glitter rides the waves and goes out at night.

**The bank is baked, because a fragment cannot see it.** A piece of water knows
where it is and what the sheet paints there, and both say the same thing in the
middle of a lake as a tile from the beach. So `mesher.gd:_measure_bank` walks
outward from every piece of land at the end of the resolve and hands
`world/water.gd` one texel a tile of distance, over six tiles.

Foam is a white line where that distance is about 0.6 tiles, riding the swell's
crest so it runs up the beach and back. It is thresholded against a checkerboard
rather than faded, because the hardware has two colours to put on a waterline and
so does this. The same number takes the water toward the palest colour of its own
row near the bank and the deepest away from it, at 45% over 1.5 tiles and 60%
past 2.5. The half strengths are the point: at full strength every canal and
river in the game is shallow across its whole width and turns to sand. Foam is
the hour's own white, so it is cream at sunrise and violet at night.

The lookup is clamped, and past the field is open water. A camera standing
outside the mesh sees water whose coordinates are off the field, and a wrapping
sampler answers the far side of the map, which on 26,3 is land, so the entire sea
behind the camera foamed over.

The far sea takes the same sky the near sea does: `far_field.gd`'s page shader
grades a texel matching that map's own water row toward the sky's horizon, so the
two do not meet at a hard line. A far map keeps its own row, so a distant lake is
graded in the colours the cartridge painted it with. It gets no waterline, no
swell and no glint, since those maps are drawings rather than surfaces.

**Water is stood in, not on.** It lies eight pixels below the land it is recessed
from, and everything standing on it, a surfing player, a swimmer, a wild Pokemon
on a surf cell, sat at the height of the land instead: a whole band clear of the
surface with daylight in the gap. On a Game Boy screen that was a few pixels;
drawn at window resolution it is a boat in the air. They now stand on the surface
and two pixels into it, so the waterline crosses the drawing. Two rather than
more, because the cartridge's art already draws the waterline: a swimmer is a
head and shoulders and the surf blob is half sunk.

## Grass, trees and the things that bend

**Tall grass.** The cartridge draws the tufts on the ground and then draws them
again over the player walking through, which is how a flat tile page says the
grass is taller than they are. A diorama says it with geometry: the floor keeps
the drawing and a thin slab of the same drawing stands out of it, one slab per
tile, so the player walks between the two rows of a cell exactly as the 2D view
meant. The blades are cut into the largest rectangles that fit inside the drawing
rather than one box per row of pixels, and the sway is read off each vertex, going
by the square of how far up its clump a point stands so a tall box leans more at
its top than its foot.

**A tree is modelled, not carved.** A Game Boy sprite of a tree is a portrait at a
fixed angle: the crown is drawn flat and wide so it reads against the grass, and
the trunk is mostly hidden behind it. That is a picture of a tree, not a plan of
one, and six ways of carving that silhouette all came out a drum, a stack of
plates or a black hedge.

So `shape/model.gd` builds a voxel trunk and crown from three authored
proportions, and everything else comes off the cartridge: how big the thing is
and what colours to paint it, taken from the drawing's own palette with the dark
outline left out. An outline is how a drawing separates itself from a flat
background; a solid in a real light does not need one, and reusing it is what
painted every carved attempt black. One mesh is built per distinct tree and
stamped wherever that tree stands, so a forest of two hundred is one tree of
geometry drawn two hundred times.

The silhouette is read down from its widest row, which is what lets the same
recipe turn a conifer: a fir's top row is two pixels across, and reading from the
top mistakes that point for the trunk. The crown is ragged, and the jitter that
does it is a fact about a direction rather than a voxel: rolled per voxel it
draws a speckle with the ground visible through it, while rolled per direction
there is one radius per ray and the silhouette is as ragged as before. It only
ever cuts in, since a crown wider than its own cell is a hedge standing on the
road.

Bushes, saplings and boulders go the same way, and the differences are the
interesting part. A bush is not a small tree: a tree's sprite is foreshortened
and its trunk is drawn behind its crown, so reading a bush that way stands it on
a stalk. The small tree that can be Cut needs both corrections taken off, since
it draws its own stem and its own height. A boulder is not a plant at all: one
world pixel per voxel rather than two, because a 16px stone six voxels across is
a pillow; it does not sway; and its colour is read in horizontal bands, since a
stone is drawn pale where the sky reaches it and dark underneath. A round stool
adds the one thing none of the others needs: half its drawing is the seat seen
from above, which is depth and no height, so its height is authored per class.

**The flower's stem** is the one thing here the cartridge does not draw. A flower
is drawn looked down on, so there is a bloom and no stem, and a bloom carved
where it is drawn hangs in the air. The stem is drawn by hand in
`shape/stems.gd` rather than guessed at as a thickness, because a stem is thin
and it bends and no number says either. It goes to the same sink the standing
tufts do, hinged at the soil rather than at the stem's head.

**Motes** are the other invention: leaves drift across the daylight and
fireflies come out at night. Forty of them ride a box around wherever the camera
is aimed, on three drift cycles that share no factor. Nothing is simulated and
nothing is stored between frames. It is one file and four lines.

## Depth of field

The frame's finishing pass coarsens toward the horizon: the same picture sampled
on a grid that grows with distance, four pixels at the far end. Not a blur. The
one soft focus a Game Boy could have had is a bigger pixel, and a gaussian over
this art reads as a photograph of a screen.

The distance is worked out rather than sampled. A canvas pass has no depth
buffer, but it has a camera looking down at a world that is mostly a plane, so
where the eye stands, how far it is tilted and how wide it sees give every row of
the picture a distance across the ground.

It is a look and not a saving: drawing the whole frame at a quarter resolution,
sixteen times fewer fragments, changes the frame time by nothing at all.
Fragments are free here and triangles are not. The pass runs at the mesh's
resolution rather than the container's, so the hour's tint, the depth of field,
the grey and the mask are all quadratic in RES like everything else.

## Tile animation

The cartridge rewrites one or two tiles of its sheet every frame: the water
ripples, the flowers open and shut, a whirlpool turns. This view repaints those
tiles on the one sheet every mesh samples, so a change moves every instance of
that tile at once, which is what the hardware does.

A drawing that animates is cut from all of its frames and not from one. The sheet
only ever shows one frame, so cutting from whichever frame the map loaded on left
the geometry short where a later frame drew further out and standing empty where
only an earlier one drew. The mask is the union of every frame the tile is ever
shown as, and the texture trims the rest. It shows most in a bed of meadow
flowers.

## Sprites another mod puts in the world

A mod can register a world actor: one sprite the host drives a frame at a time
and resolves into the same `Gen2WorldSprite` the map's own objects carry. A
Pokemon following the player is one. This view takes them through `set_actors`
and stands each one up as a card on the cell it names, with its own shadow, so
the same follower is behind the player in both views and `V` swaps between them
without losing it. The host resolves the art, the palette, the hour and, for a
party icon, its own two frames.

A step it is taking comes with the two cells it runs between, so a follower
crossing a ledge or a fold is put through the same geometry the player is, and
a hop is stood on the arc the host reads off the movement's own name.

Visible wild Pokemon use the same path. Their host-resolved four colours override
the ordinary icon row so shininess stays visible, and the optional encounter
handle stands each tile of the cartridge's shiny sparkle around the Pokemon.

## One grid under the whole picture

SMOOTH SCROLL hands this view a position between two hardware pixels, which is
what lets a step be drawn a fraction of a cartridge pixel at a time instead of
two whole ones a pass. Drawn raw, every card and quad lands on a sub-pixel phase
of its own, and art sampled nearest crawls under a phase that drifts: a column of
a 16 px drawing widens and narrows frame by frame. On a wall nobody sees it; on a
follower's face, where a party icon's own two frames already move the head, it
reads as a blur whenever the player walks.

So the camera and every card go on one grid, `world/grid.gd`: the finest step the
surface can draw, measured in the camera's own two screen axes, which is the same
answer the host's 2D view reaches in `world_renderer.gd:_camera_pixels`. At a 540
pixel surface that step is a sixth of a cartridge pixel, so the smoothing is kept
and the phase is not. Terrain needs nothing of its own: it does not move, so a
camera on the grid is enough for it.

Every walker rides the same option. The player's step is asked for as its two
cells and a progress across them, which the host spends the world's own fraction
on; an object's takes that fraction as an argument, and a sprite another mod
puts in the world carries a span of its own. Walking New Bark Town at 120 Hz,
500 drawn frames of where the camera stood:

| Scrolling | Frames that moved the picture not at all | The rest |
| --- | --- | --- |
| Hardware pixels | 374 of 500 | 2 world pixels at a time |
| SMOOTH | 0 of 500 | half a world pixel a frame |

`tools/voxel_view_probe.gd` checks the arithmetic with no display: that two
positions inside one surface pixel are the same drawn frame, that every snapped
point stands a whole number of steps from every other, that both hold at every
pitch and bearing the view can be steered to, and that a step moves on every
drawn frame. `tools/motion_bench.gd` is the table above, measured through the
game.

## Surveying a tileset

The height measurement is right for most of the world and wrong for drawings that
depict something other than a wall. Finding those is a loop, and its unit is the
block: 4x4 tiles on 2x2 walk cells, which is what Generation II authors the world
out of. A tree, a sign, a fence corner or a stretch of path is one block.

```bash
Godot --path <pokerecomp> -s <this checkout>/tools/survey.gd -- <cache> all out/
python3 tools/survey_sheet.py out/
```

That lays every block a tileset places beside the mod's own build of it,
numbered, one sheet per tileset, about eight seconds for the whole game.

1. Read the sheet. The cartridge's drawing is the authority for what a thing is.
2. Write the failures as a list: `#4 bookcase, #6 planter, #22 bed`.
3. Pin them in `shape/profile.gd` under the tileset's number, with the class
   whose art mode matches what the drawing depicts.
4. Re-shoot the whole tileset, not just the blocks that were pinned: heights are
   measured per column, so a pin changes what its neighbours measure.
5. Every map sharing that tileset inherits the pins.

A pin is presentational and can only ever be. Collision, warps, triggers and
scripts read the same data they always did, and a fix that seems to need a
collision change is the wrong fix.

`shape/profile.gd` is hand-authored from measurements off the drawing.
`shape/profile_pass.gd` is generated from a full pass over every tileset, where
the same ringed pictures are read tile by tile and the answers become pins. The
hand table wins wherever both name a tile, and the generated one can be thrown
away and rebuilt. All thirty-five tilesets are covered: 3618 tiles read, 2168
pinned, the rest left to automatic resolution. Run blind against a tileset that
had already been answered by hand, the pass agreed on 63 of the 67 settled tiles,
and every miss was one it had marked short of sure.

## Layout

```
mod.gd               registers both renderers and the settings, and returns
options.gd           the settings, named once, registered and read back here
steering.gd          what a key or a wheel notch means, in either view
world/renderer.gd    the overworld Node the host builds
world/diorama.gd     the 3D stage both views share: viewport, daylight, cards
world/sky.gd         the banded, dithered sky and the shader that paints it
world/water.gd       the water surface: the sky by Fresnel, the swell, the sun
world/wind.gd        what makes grass and foliage bend, and part around a walker
world/motes.gd       the drifting leaves and the fireflies
world/far_field.gd   the ground past the mesh: the maps around this one, flat
world/far_foliage.gd the trees and bushes standing on those maps
world/far_houses.gd  the buildings on those maps, as boxes
world/frame.gd       the pass over the finished picture: tint, focus, the bars
world/transition.gd  DoBattleTransition's own cells, over the map it closes on
world/camera_rig.gd  pitch, distance, lens and the ease between settings
world/grid.gd        the surface pixel the camera and every card are put on
battle/renderer.gd   the battle Node: the arena, the battlers and the panels
battle/arena.gd      where the fight is staged and where it is shot from
battle/panel.gd      the frost behind a panel, over whatever the world drew there
battle/anim.gd       a move's own OAM layer, blitted the way the hardware drew it
shape/atlas.gd       the tileset as a texture, palettes and tile animation
shape/map_source.gd  the map, live from the world or read from its records
shape/tile_shape.gd  tile -> shape class
shape/profile.gd     hand-authored pins, the objects, the staircases, the classes
shape/profile_pass.gd  the generated second table, one pin per tile of the game
shape/far_drawings.gd  what stands on a far map, read without resolving it
shape/houses.gd      the houses painted per pixel
shape/levels.gd      the ground levels a person painted, where one has
shape/model.gd       a sprite turned into a model: trees, bushes, boulders
shape/stems.gd       the flower's stem, drawn by hand because nothing draws one
shape/mesher.gd      map -> one static mesh
```

## Credits

The voxelization approach follows
[DramaticShapeVoxelMod](https://github.com/DramaticShape/DramaticShapeVoxelMod),
which worked out how to turn Generation I's flat tile art into geometry without
authoring any. That mod is for a different game on a different engine; what is
borrowed is the method, not the code.
