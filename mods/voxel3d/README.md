# Voxel 3D

The overworld as a voxel diorama, and the fight staged on the map it started on.
The same map, the same collision, the same palettes: geometry extruded from what
the game already decoded, textured with the cartridge's own tileset art. No 3D
assets ship with this mod, and none could, because everything it draws comes out
of the player's own cartridge.

## Controls

Nine controls, DECLARED to the host rather than read as keycodes, so every one
of them is rebindable in the launcher's controls card and can be carried on the
on-screen pad. The defaults:

| Control | Key | Pad | Does |
| --- | --- | --- | --- |
| Zoom in / out | `E` / `Q`, or the wheel | shoulders | Zoom the lens, in both views |
| Camera up / down | `I` / `K` | right stick | Raise and lower the camera, in both views |
| Swing left / right | `J` / `L` | right stick | Battle: swing the shot around the arena |
| Push in / pull back | `=` / `-` | | Overworld: move the eye |
| Recentre | `O` | right stick press | Back to the framing the view opened at |

Turning this view on is one choice and the host owns it: the mod's own page in
the launcher carries a View switch, and choosing this mod there draws the
overworld and the fight alike, since both renderers are registered under the one
id. `V` does the same thing live where the game's development keys are enabled.

TAP FOR A NOTCH, HOLD TO GLIDE. A press moves the shot one rung and eases to it,
which is what a key wants; a stick is not a press, and stepping it a rung per
push is the one control here that felt wrong on a pad or a phone. Held past a
fifth of a second, a control moves the goal at the rate it is being pushed, so a
stick half over glides at half the speed and a key held down runs at full. Seven
rungs a second, which crosses the overworld's whole pitch range in under two.

Why declared and not read: a screen turns every bound event into one of the
cartridge's eight buttons and takes it before a renderer is offered anything, so
a mod key that is also a binding never arrives. These were `W`, `A`, `S` and `D`,
which are the d-pad's own defaults, and the pitch and the swing had therefore
never once fired. Nothing warned, because both sides were behaving correctly. A
declared default in that position is now dropped and REPORTED by the host
instead. The wheel stays an event, because pointer motion is exactly what the
screen has no opinion about, and its direction is the one part of the binding
that is a preference rather than a decision.

RECENTRE is also a press in the MODS menu, which is not a duplicate: an action
has to be bound to something before it exists, and the player most likely to have
lost the camera is the one who has never opened the controls card.

One binding, in `steering.gd`, and both views read it, so a control means one
thing in the mod. Both views zoom the LENS and never the distance: a rig
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

Four, in the start menu's MODS entry and on this mod's card in the launcher.
Both surfaces are built by the host out of one registration in `options.gd`, so
this mod writes no settings screen. Values are per installation and not per save:
a draw distance must not change when a slot is loaded.

| Setting | Rungs | Does |
| --- | --- | --- |
| DISTANCE | 12, 16, 24, FULL | How far out the map is meshed, in walk cells |
| WHEEL | NORMAL, INVERTED | Which way a wheel notch zooms |
| CAMERA | LOW, MID, HIGH | The pitch the overworld camera opens at |
| CAMERA | RECENTRE | A press, not a rung: put the shot back the way it opened |

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
there behind it. The overworld pans the shot up only where a box would actually
cover the player, who stands at the middle of the frame: the cartridge's own box
is the bottom third and reaches nowhere near, so an ordinary conversation moves
the camera not at all, and a box that does reach past the middle pushes the shot
just far enough to clear it. The battle never pans: each battler is pinned to its
own hardware picture slot, which is what makes a collision with the box
impossible in the first place.

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
perfectly walkable. Stamped models take part in that test at their model height,
not at the flat ground column beneath them, so a tree cannot be selected as the
camera's open foreground.

The eye breathes rather than sitting still, because a flat picture has no
parallax until something moves and a fight is the one place here where nothing
does: a one degree orbit with a smaller dolly under it, on a period of its own so
the two never come back into step. It rides the arm from what the lens is aimed
at, so the pair stays nailed to the middle of the frame and only what is behind
them moves. Small on purpose: the shot is a solve, so drifting it carries both
battlers off their marks, and this carries them about three hardware pixels.

Two layers, because a battle is two things at once. The map is geometry at window
resolution; the panels, the bars and the text box stay hardware pixels, drawn at
whole-number scale over the top so a Game Boy pixel is still a square. Each panel
gets a light translucent backing, because the cartridge draws black glyphs
straight onto the white field and over a route they would be black on grass. What
is behind that backing is BLURRED as well as tinted, which is a different job: a
translucent rectangle over a dithered path shows every texel of the path through
the writing, so the two compete. Blurring separates them without making the
backing any more solid, and the world behind it is still visible, still the right
colour and still moving.

A battler is cut out of that field by region rather than by colour. The field is
colour index 0, and so is every white inside the drawing: an eye highlight, a
tooth, Marill's belly. The cut floods in from the border through index 0 alone
and stops at the drawing's own black outline, so what the outline encloses
survives and only the field is removed.

A move animation is drawn as the hardware drew it, on a layer of its own over
the top. That works for a reason worth stating: an animation is authored against
the two picture slots the cartridge puts its battlers in, and the camera is
solved to land both battlers in those very slots, so a beam aimed at the far slot
is already aimed at the far Pokemon and nothing has to be re-aimed. What the
breathing adds on top is corrected per sprite, lerped along the line between the
two, since an orbit carries the near battler one way and the far one the other
and a single offset for the whole layer would cancel itself.

An animation has a second half, and it is the one that reaches the whole screen.
The hardware flashes by rewriting its BACKGROUND palettes, one byte written
across all seven at once, and that byte is a permutation: colour i of every
palette drawn as colour `(byte >> i * 2) & 3`. So what it has is not an overlay,
it is a TONE CURVE over the four levels a Game Boy palette has, and a sixth of
every move played carries one. The diorama takes that curve read as a smooth line
through those four points, exact at each of the hardware's own levels, moving
luminance alone so a picture's colour survives everything but the ends. The two
battlers take the permutation exactly instead, because a pic really is four
palette entries and the map is a lookup among them.

A move has a third half, and it is the one a flat screen does that a diorama
cannot copy: eight of the game's animations scroll the background a different
distance on every scanline, which is a wobble. There are no scanlines here, and
warping the world row by row would move the cartridge's own texel off the pixel
it was drawn on, which is the one thing this view never does. So the whole list
of offsets is read as the single displacement it averages out to, and the camera
is shaken by it. The picture jumps, which is what the wobble MEANT, and both
battlers jump with it, because the shake is applied to the seat and the aim
together and the rig's whole point is that the pair stays where it put them.

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

## A jumping ledge comes out of the collision, not out of a drawing

Nothing in the tile layer says which way a ledge can be hopped, and no drawing
does either: the answer is in the collision byte, and `Gen2WorldCollision`
decodes it against the cartridge's own rule. The code sits on the cell the player
stands on, so the ledge is the blocked cell the hop passes over, and the lip is
drawn in the far half of it.

Those tiles are built as a wedge: a ramp rising a band toward the drop and a
vertical face at it. Which is the collision rule drawn as a shape. Going the way
the hop goes, the ground rises and falls away under you; coming back, there is a
small wall in front of you.

Where perpendicular ledge runs end around the same corner, their grid
intersection inherits both slopes. The corner is one continuous wedge rather
than the flat tile that neither individual hop crosses.

The player and a scripted NPC follow the host's own vertical jump offset while
crossing one. The card rises and lands; its shadow and the camera stay on the
ground, so a hop reads as movement rather than as a camera shake.

Before that they stood a full walk cell tall, because a blocked cell with no pin
is a wall like any other, and a route was fenced by 16px walls you could not see
over. 1380 cells of 72 maps are hopped over.

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

A roof tile's top is a quad with four corner heights, each the mean of the roof
tiles touching it, so a fall reads as a tilt rather than as a ziggurat. That is
continuous by construction: two roof tiles sharing an edge compute both of its
corners from the same neighbours, so their surfaces meet exactly whatever their
nominal heights are.

How far a tile has fallen is read two ways, and one map in the game is why. A
drop is a fall from the FLAT section of the same roof, which is what a gable is
drawn as: one band down beside the flat, two at the corner of the house. A great
roof has no flat section in the run at all. Its whole width is the pitch, twelve
tiles of it falling from a ridge to the eaves, and there the drop is read as a
RATE instead: each tile falls one more band than the tile before it. Which end of
such a run is the ridge is the one thing no drawing says, and what answers it is
what lies beyond, since a roof falls away from the floor a person stands on and
toward the void past the edge of the world.

SOME HOUSES DRAW NO ROOF FROM ABOVE AT ALL. Every wooden house in Johto, and
every small brick one, draws the front PITCH of its roof face-on instead: four
rows of plank or of speckled tile over two rows of wall. Folded up square that is
a barn, a tall box with roof texture down its upper half and a flat lid, which is
what every house on the largest outdoor tileset in the game used to be. So the
profile names those tiles, and the bands they draw LEAN BACK over the building's
own footprint, a tile of depth per band of height. The total height does not
move: the topmost band stands where it did and each band below it steps down and
forward until the wall, so the pitch is redistributed inside the footprint the
fold already gave the house, and the tilt above turns the steps into one plane.

Two readings refuse it, and both are drawings rather than caution. A roof deck
standing on the run means the face-on band is that deck's fascia and belongs on
the wall where it is drawn. And a column drawing roof MORE THAN ONCE is a stack
of storeys rather than a house with a pitch on top: Ecruteak's dance hall is
seven galleries each with its own plank band, and read as one run its roof would
reach the ground.

## Past the edge of the map

Past its edge, the cartridge repeats the map's own BORDER BLOCK, and so does
this. It is stood up rather than flattened: eighteen maps end in a tree line,
sixteen in a hedge, twenty in open sea. The ring is not painted on afterwards
either. The map is resolved INSIDE it, so a tree out there is measured, masked,
modelled and stamped by the same code that does it inside the map, and the seam
between the two is skirted like any other change of height. The world is still
measured from the map's own corner.

How deep the ring goes is decided by what it buys. One block for most of them; a
flat border gains nothing from more, because the floor beyond is carried out to
the horizon anyway, and gains everything from one, because that floor is now the
BORDER's rather than the map's own edge, so a coast runs out as sea and not as
beach. Four blocks where the block is a stamped model, since a tree emits no
geometry at all and a route can really end in a wood. A carved drawing stays at
one block because of what repeating it costs: a hedge bush is about 170 triangles
a tile.

Beyond the ring the floor runs on for thirty-two tiles, so a route ends at a
horizon instead of at a cliff of nothing and a fight staged near an edge is not
shot against sky. That floor is the nearest flat tile inward, which is why a
shoreline carries the water out and not the beach, and where a column meets
nothing but structures it takes the commonest floor along the map's perimeter
rather than leaving a hole.

Out of doors only: a room ends at its walls and there is nothing past them, so
carrying a floor out of a house would lay its lino across the void it is drawn
against. `Gen2WorldPhoneHost.is_outside_environment` is the host's own answer to
which a map is.

At any draw distance short of FULL the window clips most of it. At FULL it is
paid for whole, and on a large route that is about as much geometry again as the
map itself.

## The sky and the hour

Above that horizon the sky is generated: a ramp of four bands, deepest overhead,
with a checkerboard of the next band down dithered into the bottom of each. That
dither is how a machine with four colours to a palette got a fifth and a sixth
out of them, and it is what makes four bands read as a gradient rather than as
four stripes. The colours are the map's own background colour taken down in
steps, the same colour the 2D view fills its margins with, so nothing here is
authored art.

The bands are pinned to ELEVATION rather than to the frame, so pitching the
camera slides the frame up a sky that stays put. How much elevation they span is
measured off the rig and not chosen: the eye looks down by its own pitch, so with
a 42 degree lens the shallowest shot in the ladder frames sixteen degrees of sky
and every steeper one frames none.

The sun moves with the hour, not just its colour. It rises in the east, climbs,
and sets in the west, so shadows swing about a hundred degrees between morning
and night and a still picture says what time it is. It stays in the SOUTHERN half
of the sky at every hour, which is not taste: a volume folds the artwork onto its
south face at full strength, so a sun crossing to the north would put every
drawing in the game into its own shadow. A low sun rakes, landing less light on
flat ground and more on the upright faces, so morning carries more energy than
day to stand the same ground up; all four rows are metered the same way the
energies are, and the frame still tops out just under 255.

## Water, and the sun in it

Everything else in this view is paint stood up and lit. Water is a MIRROR, and
the 2D view says so in the only way it can, by cycling the ripple art in place.
So the surface is lifted out of the terrain mesh and given three things the flat
drawing cannot carry. The sky in the lake is the sky over it, mixed in by
Fresnel, so the far water is bright and the near water keeps the cartridge's own
blue. The surface is not flat: two long waves cross it and their gradient is the
normal everything else is read through, done per fragment so no vertex moves and
the water cannot tear away from its own bank. And the sun is in it, hung by
ANGLE rather than by screen position, because the reflection of a sun most of the
way up the sky lands off the top of the frame at every hour: what is asked is how
nearly a piece of water is tilted to bounce the sun into the eye, which is a fact
about the swell, so the glitter rides the waves and goes out at night with the
light.

## Sprites another mod puts in the world

A mod can register a world ACTOR: one sprite the host drives a frame at a time
and resolves into the same `Gen2WorldSprite` the map's own objects carry. A
Pokemon following the player is one. This view takes them through `set_actors`
and stands each one up as a card on the cell it names, with its own shadow, so
the same follower is behind the player in both views and `V` swaps between them
without either one losing it.

Nothing about them is this mod's to decide. The host resolves the art, the
palette, the hour and, for a party icon, its own two frames; a card is drawn
here from that and from nothing else.

Visible wild Pokemon use the same actor path. Their host-resolved four colours
override the ordinary icon row so shininess remains visible, and the optional
encounter handle stands each tile of the cartridge's shiny sparkle around the
Pokemon's centre. The built-in view and the diorama therefore share the same
population, palette and live animation rather than approximating either one.

## The one thing here the cartridge does not draw

Everything else in this view is the cartridge's own drawing restated. Every
shape, every colour and every height is read out of what the host decoded from
the cartridge, and where a judgement was needed a person made it about a picture
that was already there.

Two things are not. A flower is drawn looked down on, so the cartridge draws the
bloom and no stem at all, and a bloom carved where it is drawn hangs in the air:
the stem under it is drawn by hand rather than guessed at as a thickness, because
a stem is thin and it bends and no number says either.

And leaves drift across the daylight while fireflies come out at night. Forty
motes ride a box around wherever the camera is aimed, each on three drift cycles
that share no factor, and the fireflies pulse. Nothing is simulated and nothing
is stored between frames. It is the one piece of atmosphere in the frame that is
invented, it is one file and four lines, and it comes out again as easily as it
went in.

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

And a drawing is a whole number of TILES, where a cell is two of them. A potted
plant three tiles tall fills one cell and the top half of the next, so the bottom
row of its box is the floor it stands on: the box is cut back to the rows the
drawing uses rather than given up on, which is what stands a plant on its own pot
instead of beside it.

## A thing that is not a tile at all

Everything above resolves a tile and stands it up where that tile sits, and for a
wall, a roof or a canopy that is right, because the cartridge draws those tile by
tile. Some things are not drawn that way. A chair is drawn as four corners across
four tiles and no one of them is a chair: one tile is the desk's bottom-left leg,
the chair's top-left corner and the floor between the two at once, so every
possible answer for that tile is wrong.

So an OBJECT is identified by the ARRANGEMENT OF TILE IDS it is drawn out of,
which finds it wherever the map places it and whatever block boundary it
straddles. Every tile the arrangement covers goes back to being floor, and one
thing of the whole object's size is stood up at the drawing's own position. Two
objects may cover the same tile and both are drawn, which a desk and the chair
tucked under it do.

A 2.5D drawing is a TOP AND A FRONT STACKED, and that is the whole reading: the
first rows are the surface seen from above and are laid across the object's depth,
the rest are the face and hang down its height. Where a drawing has a top band at
all, those two row counts ARE the depth and the height. Where it has none, which
is a chair drawn face on, the depth is not in the picture and has to be given.

How TALL a thing is, though, is not the drawing's to say. A chair's twelve drawn
rows stood up as twelve pixels is a cabinet beside a desk half its height. What a
face-on drawing states honestly is its width.

WHERE it stands is the collision's to say, and the drawing and the collision
disagree. A drawing puts its front-bottom corner at its own bottom row, so
everything else stands behind it; the cartridge draws a free-standing bench's
apron on the walk cell IN FRONT of the one the bench blocks. Read at its word the
box came out half a cell into open floor, which is a player walking into the
front of a desk and the starters' Pokeballs left off the back edge of Elm's
bench, floating behind it rather than standing on it. So a box that stands on
floor a body can stand on is pulled back to the near edge of the last cell the
drawing covers that is blocked the whole way across, and the move is kept only
where it clears the box entirely. Over the whole game fourteen placements move,
by six to sixteen pixels, and the ship does not: no placement of a hull ringed in
sea stands on rock alone. A chair, a stool and a ladder stand on cells the
cartridge lets you walk onto, which is its answer and not a placement to correct.

An object may also be TURNED rather than stood up, because a drawing that is
round wants the model below rather than a slab: the park's tiered stone fountain
is 18 px wide across three tiles and centred on the seam between two of them, so
nothing keyed to the cell grid reaches it at all. Its window is what keeps the
paving either side of it out of the profile the turn is read from, and how tall
it stands is the declaration's, since a turned body is as deep as it is wide.

Fourteen things are declared this way: a desk, five chairs, a ship, a stone
vessel, a ticket gate, a fountain, the ridge along a great roof, a parked
bicycle, a television and a low padded seat. The last three are what a fallback
that REVOLVES a drawing cannot do: a bicycle drawn side-on is a portrait three
tiles wide, and turned it came out as a row of bollards.

The largest of them is the ship at the port, fifteen tiles by six, and it added
the one rule the smaller ones did not need: a bounding box is not a footprint. The
box around something that is not rectangular holds tiles that are not the object,
and here they are open sea, so they are declared as outside it and keep being sea.
They stay part of the rectangle the mask is cut over, and that is the point of
naming them rather than cropping the box down: a mask is cut by flooding in from
the border, and the border of the hull's own rectangle is half hull. Ringed in one
tile of open water the flood stops at the paint, and what is left is the ship.

A staircase is found the same way and is its own shape. Generation II draws a
flight as a perspective view over four tiles, and stepping onto one leaves the
floor entirely rather than climbing anything, so a down flight is a HOLE: put the
cell's floor a walk cell below the ground and everything around it skirts down to
it, which is the same code that draws a cliff. A ladder in a shaft is that with
the steps taken out.

## Cutting a drawing that is painted in the ground's own colours

The mask asks where a drawing ends, and colour cannot say: a bollard is white on
a pale path and a bush is green on grass. What can say it is the border. The
ground runs to the edge of the cell and the drawing does not, so the indices
making up most of the cell's border ring are the ground and everything the flood
cannot reach through them is the drawing.

That fails on one family of drawings, and it fails completely. A tree canopy is a
ball drawn in the SAME two greens the grass under it is dithered from. Put those
greens in the ground set and the flood eats the lit half of the tree; leave them
out and it keeps half the lawn. No set of indices exists that separates them,
which only shows if you look at the mask as a picture.

What bounds such a drawing is its own outline, and an outline is the darkest
shade in the tile. So those classes flood through every pixel that is NOT that
shade, and what the flood cannot reach is the tree. How MANY shades bound one is
the drawing's own business rather than the rule's: a tree draws a ring in one,
and a case that meets the ground in a paler shade needs two. The shadow pooled under a
canopy is dark but is not enclosed by the outline, so it floods away with the
grass, which is what should happen to it.

## Tall grass lies flat and stands up at the same time

The cartridge draws the tufts on the ground and then draws them again over the
player as they walk through. That overdraw is the whole statement: the grass is
taller than they are, and a flat tile page can only say so by drawing it twice.

A diorama says it with geometry. The floor keeps the drawing and a thin slab of
the same drawing stands out of it, one slab per tile at that tile's own depth, so
the player walks between the two rows of a cell exactly as the 2D view meant.
Only the blades stand: whatever index the tile spends most of itself on is the
ground they are drawn on.

The blades are cut into the largest rectangles that fit inside the drawing rather
than into one box per row of pixels, which is the same cut a carved drawing gets
and keeps the picture texel for texel. Down the column first and then across,
because a blade is a vertical thing, and the sway is read off each vertex: the
bend goes by the square of how far up its own clump a point stands, so a box
several rows tall has to lean more at its top than at its foot.

## Some things are MODELLED, not carved

A tree is where standing the drawing up stops working, and it is worth saying
why. A Game Boy sprite of a tree is a portrait of one at a fixed angle: the crown
is drawn flat and wide so it reads against the grass, and the trunk is mostly
hidden behind it. That is a picture of a tree, not a plan of one. Six ways of
carving that silhouette were built and measured, and every one came out a drum, a
stack of plates or a black hedge.

So the tree is modelled. `shape/model.gd` builds a voxel trunk and crown from
three authored proportions, and everything else still comes off the cartridge:
how big the thing is, and what colours to paint it, taken from the drawing's own
palette with the dark outline left out. An outline is how a drawing separates
itself from a flat background; a solid standing in a real light does not need
one, and reusing it is what painted every carved attempt black.

One mesh is built per distinct tree and stamped wherever that tree stands, so a
forest of two hundred is one tree of geometry drawn two hundred times and culled
as a single instance. It is cheaper than the flat wall it replaces.

The silhouette is read down from its WIDEST row, which is what lets the same
recipe turn a conifer. A fir is pointed: its top row is two pixels across, and a
reading that starts at the top mistakes that point for the trunk and comes out a
disc on a stump. How TALL a tree is drawn is the drawing's business too, so the
one class covers both the conifer drawn in a single cell and the one drawn in
two, and the placement is what says which.

The crown is ragged rather than lathed, and the jitter that does it is a fact
about a DIRECTION rather than about a voxel. Rolled per voxel it draws no
surface at all: what comes back is a speckle a couple of voxels thick with as
many gaps as leaves in it, and the ground behind a bush is visible through the
middle of it. Rolled per direction there is one radius per ray, everything
inside it is solid, and the silhouette is as ragged as before. It only ever cuts
IN, because the drawing states the width and a crown wider than its own cell is
a hedge standing on the road beside it.

Bushes, saplings and boulders go the same way, and the differences between them
are the interesting part. A bush is not a small tree: a tree's sprite is
foreshortened and its trunk is drawn behind its crown, so reading a bush that way
stands it on a stalk. The small tree that can be Cut is the opposite and needs
both corrections taken off: it draws its own stem, so it stands on one, and it
draws its own height, so nothing stretches it. A boulder is not a plant at all: it takes one world pixel per voxel
rather than two, because a 16px stone six voxels across is a pillow; it does not
sway; and its colour is read in horizontal BANDS off the drawing, since a stone
is drawn pale where the sky reaches it and dark underneath.

The stone's reading is also what puts a drawing back that was not being built at
all. The National Park's bin stands on paving dithered in the same greys the bin
itself is drawn in, so the rule that cuts a drawing out of the ground around it
had nothing to cut on and the flood ate the whole thing: on that paving the mod
drew no bin. Read as a stone it is cut on its own dark outline instead, and one
of the few things in this game that costs more than leaving it wrong, since
nothing at all is cheap.

The notice cabinet beside it is the same fault answered the other way. It is flat
and face-on rather than round, so it is carved rather than turned: a board in a
frame on two posts, standing the rows it is drawn. What it needed was TWO shades
of outline instead of one. A drawing's own dark frame is what bounds it, and this
one closes round the top and the sides but meets the paving in a paler shade, so
cutting on one shade let the flood up through its foot and took a slot out of the
middle of the case.

A round stool takes the stone's reading and adds the one thing none of the others
needs. Everything above can take its own DRAWN height, because a tree, a bush and
a rock are all drawn standing. Half of a stool's drawing is the seat seen from
ABOVE, which is depth on the page and no height at all, so read literally a
knee-high seat stands a full walk cell and comes out a barrel. How tall a
modelled thing stands is therefore authored, per class, against how tall it is
drawn.

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
world/sky.gd         the banded, dithered sky and the shader that paints it
world/water.gd       the water surface: the sky by Fresnel, the swell, the sun
world/wind.gd        what makes grass and foliage bend, and part around a walker
world/motes.gd       the drifting leaves and the fireflies
world/frame.gd       the pass over the finished picture, and the hour's tint in it
world/camera_rig.gd  pitch, distance, lens and the ease between settings
battle/renderer.gd   the battle Node: the arena, the battlers and the panels
battle/arena.gd      where the fight is staged and where it is shot from
battle/panel.gd      the frost behind a panel, over whatever the world drew there
battle/anim.gd       a move's own OAM layer, blitted the way the hardware drew it
shape/atlas.gd       the tileset as a texture, palettes and tile animation
shape/map_source.gd  the map, live from the world or read from its records
shape/tile_shape.gd  tile -> shape class
shape/profile.gd     hand-authored pins, the objects, the staircases, the classes
shape/profile_pass.gd  the generated second table, one pin per tile of the game
shape/levels.gd      the ground levels a person painted, where one has
shape/model.gd       a sprite TURNED into a model: trees, bushes, boulders
shape/stems.gd       the flower's stem, drawn by hand because nothing draws one
shape/mesher.gd      map -> one static mesh
```

## Credits

The voxelization approach follows
[DramaticShapeVoxelMod](https://github.com/DramaticShape/DramaticShapeVoxelMod),
which worked out how to turn Generation I's flat tile art into geometry without
authoring any. That mod is for a different game on a different engine; what is
borrowed is the method, not the code.
