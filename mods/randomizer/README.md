# Randomizer

A run generated from a seed. The same seed on the same cartridge is the same
game, on anyone's machine, every time: base stats, types, movesets, evolutions,
move power and accuracy, and every trainer's team are drawn from the seed and
from nothing else.

Nothing is invented and nothing is shipped. Every value written here came out of
the cartridge the player imported, rearranged.

## The seed

Four digits, dialled on four rows in the same MODS menu as everything else, so
a run is shared by saying a number: `0000` to `9999`. Leading zeros count, and
`0042` is not `4200`.

It is four rows because a setting is a ladder of values or a press, and neither
is a text field. That is an engine request rather than a limit worth working
around, and a longer seed will be one row when it lands.

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

Ten rows, in the start menu's MODS entry and on this mod's card in the launcher.
Both surfaces are built by the host out of one registration in `options.gd`, so
this mod writes no settings screen.

| Setting | Rungs | Does |
| --- | --- | --- |
| SEED 1 to 4 | 0 to 9 | The four digits of the run's code |
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

A randomizer nobody can finish is a bug, so each of the six is bounded by
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
promise.

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
base stat total order, so a gym leader gets a different team and not the top of
the table.

## What this deliberately does not touch

WILD ENCOUNTERS. Which Pokemon appear in the grass is the single most wanted
thing a randomizer does, and it is not here: the encounter tables are read
through `GameData.world_encounter` and no content kind patches them, so a mod
cannot change them. Scraping or mirroring those tables to get around that is
exactly the kind of private copy of host data this repository does not write, so
the fix is a host one and has been asked for.

TM AND HM COMPATIBILITY, and what each TM teaches, so the moves a run needs to
cross the map are the ones the cartridge always had. ITEMS, MARTS and what is
found on the ground. MOVE EFFECTS, since an effect is a list of steps and the
power beside it is what this mod moves. And no species is ADDED: mod content has
no art yet, and a Pokemon nothing can draw is not a Pokemon.

## Showing that it is deterministic

`tools/randomizer_probe.gd` builds the plan against a real cartridge cache and
prints what it changed, with no game running. It digests one seed built twice
and a second seed built once, and then asks every promise above of every row
rather than of a sample:

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
