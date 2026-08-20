# Overworld Encounters

Wild Pokemon live on the map instead of interrupting a random step. Each map
holds a bounded population drawn from its own active grass, cave and surf tables.
They roam only across cells where that encounter method belongs, disappear on a
map change and start the ordinary wild battle when met. An encounter leaves the
population after its battle ends, whatever the battle result; the map does not
refill until its next generation.
Each moves at most one cell every 1.6 seconds, leaving time to route around it.

Nobody stands on anybody. A wild is never put on, and never steps onto, a cell
someone else holds: the player, another wild, or one of the map's own objects,
which is every NPC and every item ball. The host answers who is standing where
and this mod does the refusing, so a person walking about changes where a wild
may go from one step to the next. A wild an NPC walks onto is left alone rather
than shoved or removed, and it steps clear of them on its own.

A shiny is shiny before the battle starts: its overworld icon uses the shiny
palette and the cartridge's own shiny animation and sound play over it on spawn,
then every ten seconds while it remains on the map.

## Setting

`VISIBLE` caps one map at 2, 4, 6 or 8 Pokemon. Six is the default.

## Cartridge rules

Species, levels, time-of-day rows, swarms, collision eligibility, DVs, palettes,
animation and audio all come from the cartridge through the host. This mod owns
only the deterministic population cap and roaming policy. Fishing, headbutt,
rock smash, the Bug Catching Contest, scripted encounters and stationary
Pokemon keep their own paths.

The same run seed entering the same map generation produces the same population,
given the same map: who is standing where is part of the answer now, since a
wild is not put where somebody already is, and that is the cartridge's own
deterministic state at the moment the map is entered. Changing `VISIBLE` while
standing on a map rebuilds against wherever people have walked to.
`tools/overworld_encounters_probe.gd` prints two equal builds and a different
seed against a real cartridge cache, and walks a population through a map with a
quarter of its cells held to prove that neither a spawn nor a move lands on
one.
