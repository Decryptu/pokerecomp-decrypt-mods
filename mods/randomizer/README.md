# Randomizer

A run generated from a seed. The same seed on the same cartridge is the same
game, on anyone's machine, every time: what walks out of the grass, base stats,
types, movesets, evolutions, move power and accuracy, and every trainer's team
are drawn from the seed and from nothing else.

Nothing is invented and nothing is shipped. Every value written here came out of
the cartridge the player imported, rearranged.

## The seed

Four digits, one field in the same MODS menu as everything else, typed in the
launcher and stepped in the game, so a run is shared by saying a number: `0000`
to `9999`. Leading zeros count, and `0042` is not `4200`. Four digits rather
than more because a code is worth having when it can be said out loud.

A host built before number settings existed gets the same seed as four
one-digit ladders instead. Nothing else changes, and a code dialled on one is
the code dialled on the other.

WHAT A SEED GUARANTEES, and the part that took the care: the same seed and the
same cartridge produce the same game. It does not depend on the order a
Dictionary handed its keys over, on the clock, on the system's randomness, or on
which settings were changed in which order. Chance comes from one written-down
generator in `rng.gd` rather than from the engine's, because a shared seed that
stops agreeing after an engine update is the one bug a randomizer cannot
survive. Each thing decided opens its own stream, keyed by what is being decided
and which row it is for, so turning one setting off does not move what another
one produced: species 43's stats are the same whether or not moves were
randomized.

WHAT A SEED DOES NOT CARRY is the cartridge. Gold, Silver and Crystal do not
have the same tables, so seed `1234` is three different runs on the three games,
each of them reproducible.

## Settings

Eight rows, in the start menu's MODS entry and on this mod's own page in the
launcher, which is reached by pressing its row in the mods list. Both surfaces
are built by the host out of one registration in `options.gd`, so this mod
writes no settings screen.

| Setting | Rungs | Does |
| --- | --- | --- |
| SEED | 0 to 9999 | The run's code |
| WILD | OFF, ON | Redraw what appears in the grass, the water and on a rod |
| STATS | OFF, ON | Shuffle each species' six base stats |
| TYPES | OFF, ON | Redraw each evolution line's types |
| MOVESETS | OFF, ON | Redraw every level-up move, keeping every level |
| EVOLVES | OFF, ON | Redraw what each species evolves into |
| MOVES | OFF, ON | Rearrange move power and accuracy, redraw move types |
| TRAINERS | OFF, ON | Replace every trainer's Pokemon |

A change applies at once, and it applies to the tables rather than to what is
already alive: a Pokemon in the party keeps the stats it was created with, the
way the cartridge's own numbers work. Switching a setting off puts its rows back
to the cartridge's own values rather than leaving the last seed's behind.

Values are per installation and not per save, which is right for this mod as
well as convenient: a run is what a seed generated, and a seed that changed when
a slot was loaded would not be that run any more.

## Sane by default

A randomizer nobody can finish is a bug, so each of the seven is bounded by
something the cartridge already said.

BASE STATS are PERMUTED, not redrawn. A species keeps its total exactly, so
nothing becomes strong or weak, it becomes strong at something else. Every
species in one evolution line takes the SAME permutation, which is what keeps a
line CLIMBING: both ends move the same stat into the same slot, so every gap the
cartridge drew between a species and what it evolves into is still there. Rolling
per species instead is what puts a first stage's Attack above its final form's.

TYPES are drawn per LINE rather than per species, so a Pokemon does not change
type by evolving. The pool is the set of type numbers this cartridge's own
species carry, which is how the unused slots between the physical and the special
runs stay out of it without any table of type numbers being written down here.

MOVESETS keep every level and replace every move. The opening is guarded: a
species' first entry, and every entry at level five or below, is drawn from moves
that do damage, land four times in five and are not overwhelming. A starter can
always attack at level five, which is the one thing a randomized learnset has to
promise. A species does not repeat a move while an unused eligible one remains.

EVOLUTIONS keep their method and their parameter, so a stone evolution is still
that stone at that level for that happiness, and only the target changes. A
target is drawn from strictly above its source in the base stat total order, so
evolving is never a downgrade. That one rule also makes a loop impossible rather
than merely unlikely: every edge climbs the order, and a cycle would have to come
back down.

MOVE POWER and ACCURACY are permuted among the moves that do damage, rather than
drawn. A permutation keeps the game's own spread: the same number of weak moves,
the same number of unreliable ones, none of it invented. Types are drawn, since a
type is a label rather than a budget. A STATUS MOVE IS LEFT ALONE entirely: its
type and its effect are entangled, so retyping THUNDERWAVE changes which Pokemon
it cannot paralyse, and giving it a power turns it into something else.

TRAINER PARTIES keep their levels, their held items and the moves a trainer's own
record carries. Each Pokemon is replaced by one from the band around it in the
base stat total order, excluding itself while another candidate exists, so a gym
leader gets a different team and not the top of the table.

WILD ENCOUNTERS keep every slot in its place, at the level and the rate the
cartridge gave it, and change only which Pokemon stands in it, drawn from the
same band and excluding the original while another candidate exists. A route
stays as easy or as dangerous as it was, and the first grass
in the game cannot hand out something that ends the run there. Grass, surfing,
both swarm tables and all three rods go the same way.

## What this deliberately does not touch

THE WILD TABLES THE HOST DOES NOT PATCH YET, and they are named rather than
faked: the headbutt and rock-smash trees, the Bug Contest's own list, the three
roaming Pokemon, and the day-and-night substitutions a rod entry defers to
instead of naming a species. Each is read straight off the cartridge, so each is
left exactly as it was rather than half rewritten. Mirroring them inside the mod
to get around that is the private copy of host data this repository does not
write.

TM AND HM COMPATIBILITY, and what each TM teaches, so the moves a run needs to
cross the map are the ones the cartridge always had. ITEMS, MARTS and what is
found on the ground. MOVE EFFECTS, since an effect is a list of steps and the
power beside it is what this mod moves. And no species is ADDED: mod content has
no art yet, and a Pokemon nothing can draw is not a Pokemon.

## Showing that it is deterministic

`tools/randomizer_probe.gd` builds the plan against a real cartridge cache and
prints what it changed, with no game running. It digests one seed built twice
and a second seed built once, and then asks every promise above of every row
rather than of a sample, down to a wild slot keeping its level and its place:

```bash
Godot --headless --path <pokerecomp> -s tools/randomizer_probe.gd -- \
	"user://rom_cache/<cache>"
```

It exits non-zero if any of them fails.

## Layout

```
mod.gd       registers the settings, reads the cartridge, carries the patches
options.gd   the settings, named once, registered and read back here
plan.gd      cartridge plus seed -> the patches, as one pure function
rng.gd       the written-down generator, and the streams drawn off a seed
```

`plan.gd` touches no host and no node, which is what lets the probe build the
same plan the game does.
