# Overworld Encounters

Wild Pokemon live on the map instead of interrupting a random step. Each map
holds a bounded population drawn from its own active grass, cave and surf tables.
They roam only across cells where that encounter method belongs, disappear on a
map change and start the ordinary wild battle when met. An encounter leaves the
population after its battle ends, whatever the battle result; the map does not
refill until its next generation.
Each moves at most one cell every 1.6 seconds, leaving time to route around it.

A population is spread over the whole of a map. Where a wild is put is drawn
uniformly from every eligible cell the map has, so a route with grass at both
ends holds Pokemon at both ends rather than a crowd in whichever patch the
collision walk reached first.

Nobody stands on anybody. A wild is never put on, and never steps onto, a cell
someone else holds: the player, another wild, or one of the map's own objects,
which is every NPC and every item ball. The host answers who is standing where
and this mod does the refusing, so a person walking about changes where a wild
may go from one step to the next. A wild an NPC walks onto is left alone rather
than shoved or removed, and it steps clear of them on its own.

A shiny is shiny before the battle starts: its overworld icon uses the shiny
palette and the cartridge's own shiny animation and sound play over it on spawn,
then every ten seconds while it remains on the map.

## The glow

A wild whose four stored DVs total 50 or more of 60 breathes gold, so one worth
a battle can be told from across a route. About one wild in sixty-five has it.

The mark is the Pokemon's own four colours walked toward a light and back over
eight tenths of a second, not anything drawn over it, which is why it can never
be mistaken for the shiny sparkle and why both the pixel view and a mod's own
renderer draw it through the palette path a shiny already takes.

A shiny never wears it. Shininess pins three DVs at ten and caps ATTACK at
fifteen, so forty-five is the most a shiny can total and the two marks are
disjoint by the cartridge's own arithmetic rather than by a rule on top of it.
`tools/overworld_encounters_probe.gd` reads all 65536 DV words and proves it.

The glow changes nothing else. The DVs are the ones carried into the battle,
the roll that made them is untouched, and a Pokemon caught without noticing its
glow is the same Pokemon.

## Setting

`VISIBLE` caps one map at 2, 4, 6, 8, 12 or 16 Pokemon. Six is the default. The
top two rungs are for a screen that fills the window: eight spread over a whole
route was more than a Game Boy screen ever showed at once and reads as an empty
route when the whole of it is drawn.

## Cartridge rules

Species, levels, time-of-day rows, swarms, collision eligibility, DVs, palettes,
animation and audio all come from the cartridge through the host. This mod owns
only the deterministic population cap, the roaming policy, and which Pokemon is
worth a glow; how far a glow is allowed to walk the colours is the host's, which
is what bounds the sprite textures one costs. Fishing, headbutt,
rock smash, the Bug Catching Contest, scripted encounters and stationary
Pokemon keep their own paths.

The same run seed entering the same map generation produces the same population,
given the same map: who is standing where is part of the answer now, since a
wild is not put where somebody already is, and that is the cartridge's own
deterministic state at the moment the map is entered. Changing `VISIBLE` while
standing on a map rebuilds against wherever people have walked to.
`tools/overworld_encounters_probe.gd` prints two equal builds and a different
seed against a real cartridge cache, walks a population through a map with a
quarter of its cells held to prove that neither a spawn nor a move lands on one,
and counts two hundred populations by eighth of the map to prove the placement
is spread rather than gathered.
