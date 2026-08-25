# Overworld Encounters

Wild Pokemon walk around on the map instead of appearing during random steps.
Each map holds a limited population drawn from its own active grass, cave and
surf tables. They only walk on cells where their encounter method applies, they
disappear on a map change, and meeting one starts the normal wild battle. A
Pokemon leaves the population once its battle ends, whatever the result, and the
map does not refill until the next time it is generated.

Each one moves at most one cell every 1.6 seconds, so you have time to walk
around them.

## Where they stand

A population is spread over the whole map: each Pokemon is placed uniformly among
every eligible cell, so a route with grass at both ends holds Pokemon at both
ends.

Nobody stands on anybody. A wild Pokemon is never placed on, and never steps
onto, a cell held by the player, another wild Pokemon, or one of the map's own
objects (NPCs and item balls). The host says who is standing where and the mod
does the refusing, so people walking around change where a wild Pokemon may go.
One that an NPC walks onto is left alone rather than pushed or removed, and it
steps clear on its own.

## Shinies and the gold glow

A shiny is visible before the battle: its overworld icon uses the shiny palette,
and the cartridge's own shiny animation and sound play when it spawns and every
ten seconds after.

A Pokemon whose four DVs total 50 or more out of 60 glows gold, so you can spot
one worth battling from across a route. About one in sixty-five has it.

The glow is the Pokemon's own four colours walked toward a light and back over
0.8 seconds, not something drawn on top, so it can never be confused with the
shiny sparkle, and both the 2D view and a 3D renderer draw it through the same
palette path.

A shiny never glows and cannot: shininess pins three DVs at 10 and caps ATTACK
at 15, so 45 is the highest total a shiny can have.
`tools/overworld_encounters_probe.gd` checks all 65536 DV words and proves it.

The glow changes nothing else. The DVs are the ones carried into the battle, and
a Pokemon caught without noticing its glow is the same Pokemon.

## Setting

`VISIBLE` caps a map at 2, 4, 6, 8, 12 or 16 Pokemon. Six is the default. The top
two rungs are for a screen that fills the window, where eight spread over a whole
route reads as empty.

## Cartridge rules

Species, levels, time-of-day rows, swarms, collision eligibility, DVs, palettes,
animation and audio all come from the cartridge through the host. This mod owns
only the population cap, the roaming rules and which Pokemon is worth a glow.
Fishing, Headbutt, Rock Smash, the Bug Catching Contest, scripted encounters and
stationary Pokemon keep their own paths.

The same seed entering the same map produces the same population, given the same
map state: who is standing where is part of the answer, since a Pokemon is never
placed on an occupied cell. Changing `VISIBLE` while standing on a map rebuilds
against wherever people have walked to.

`tools/overworld_encounters_probe.gd` prints two identical builds and a different
seed against a real cartridge cache, walks a population through a map with a
quarter of its cells occupied to prove nothing spawns or steps onto one, and
counts two hundred populations by eighth of the map to prove the placement is
spread out.
