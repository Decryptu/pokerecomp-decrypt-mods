# Overworld Encounters

Wild Pokemon live on the map instead of interrupting a random step. Each map
holds a bounded population drawn from its own active grass, cave and surf tables.
They roam only across cells where that encounter method belongs, disappear on a
map change and start the ordinary wild battle when met.

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

The same run seed entering the same map generation produces the same population.
`tools/overworld_encounters_probe.gd` prints two equal builds and a different
seed against a real cartridge cache.
