# Randomizer

A playthrough generated from a seed. The same seed on the same cartridge gives
the same game, on anyone's machine, every time. Wild encounters, gifts, static
Pokemon, starters, trades, item and badge rewards, shops, base stats, types,
movesets, evolutions, move power and accuracy, and every trainer's team are all
drawn from the seed.

Nothing is invented and nothing ships with the mod. Every value comes out of the
cartridge the player imported, rearranged.

## The seed

Four digits, `0000` to `9999`, in the same MODS menu as everything else. You can
type it in the launcher and step it in the game, so a run is shared by saying a
number. Leading zeros count: `0042` is not `4200`.

A host built before number settings existed shows the seed as four one-digit
rows instead. Nothing else changes.

The same seed and the same cartridge always produce the same game. It does not
depend on dictionary ordering, the clock, the system's randomness, or the order
settings were changed in. Randomness comes from one written-down generator in
`rng.gd` rather than the engine's, so an engine update cannot change what a seed
means. Each decision opens its own stream, keyed by what is being decided and
which row it is for, so turning one setting off does not move what another
produced.

A seed does not carry the cartridge. Gold, Silver and Crystal have different
tables, so seed `1234` is three different runs.

## A run belongs to its save

The launcher settings describe the next new run. When a save is created, the
seed, every toggle and an algorithm version are written into that save's own mod
namespace. Loading it rebuilds the run from those inputs before gameplay reads
the cartridge. Changing a setting cannot reroll a save already in progress, two
slots cannot leak into each other, and an older save with no snapshot stays
vanilla.

A development run has no save file, so it uses the current settings for that
session.

## Settings

Fourteen rows, in the start menu's MODS entry and on the mod's page in the
launcher, all from one registration in `options.gd`.

| Setting | Rungs | Does |
| --- | --- | --- |
| SEED | 0 to 9999 | The run's code |
| WILD | OFF, ON | Redraw every random wild encounter |
| GIFTS/STATIC | OFF, ON | Redraw gifts, static battles and Pokemon prizes |
| STARTERS | OFF, ON | Redraw the three starters |
| TRADES | OFF, ON | Redraw both sides of every in-game trade |
| ITEMS | OFF, ON | Rearrange item rewards |
| BADGES | OFF, ON | Rearrange badge rewards |
| SHOPS | OFF, ON | Rearrange the items sold in shops |
| STATS | OFF, ON | Shuffle each species' six base stats |
| TYPES | OFF, ON | Redraw each evolution line's types |
| MOVESETS | OFF, ON | Redraw every level-up move, keeping every level |
| EVOLVES | OFF, ON | Redraw what each species evolves into |
| MOVES | OFF, ON | Rearrange move power and accuracy, redraw move types |
| TRAINERS | OFF, ON | Replace every trainer's Pokemon |

A change applies to the next save created. It never rewrites the active one.

## Kept beatable

A randomizer nobody can finish is a bug, so each category is bounded by something
the cartridge already said.

**Base stats** are shuffled, not redrawn, so a species keeps its total: it does
not get stronger or weaker, it gets strong at something else. Every species in an
evolution line gets the same shuffle, so a line still climbs.

**Types** are drawn per line rather than per species, so a Pokemon does not change
type by evolving. The pool is the set of types this cartridge's species actually
carry, which keeps unused type slots out of it.

**Movesets** keep every level and replace every move. The opening is guarded: the
first entry, and every entry at level 5 or below, is drawn from moves that do
damage, land four times in five and are not overwhelming, so a starter can always
attack at level 5. A species does not repeat a move while an unused eligible one
remains.

**Evolutions** keep their method and their parameter, so a stone evolution is
still that stone at that level for that happiness, and only the target changes. A
target is always higher in base stat total than its source, so evolving is never
a downgrade and a loop is impossible.

**Move power and accuracy** are shuffled among damaging moves rather than drawn,
which keeps the game's own spread of weak and unreliable moves. Types are drawn,
since a type is a label rather than a budget. Status moves are left alone
entirely: their type and effect are entangled.

**Trainer parties** keep their levels, held items and recorded moves. Each
Pokemon is replaced by one from the band around it in base stat total order, so a
gym leader gets a different team and not the top of the table.

**Wild encounters** keep every slot at its level and rate and change only which
Pokemon stands in it, drawn from the same strength band. So a route stays as easy
or as dangerous as it was. Grass, surfing, both swarm tables, all three rods,
day/night substitutions, Headbutt and Rock Smash sets, the Bug Contest and
roaming Pokemon all go the same way, and their weights, thresholds, level bounds
and live roaming positions are untouched.

**Gifts and static Pokemon** change species only. Levels, held items, prices,
scripts and completion flags stay put.

**Starters** are distinct and strength-banded. The host changes the ball's
picture and the Pokemon it gives as one transaction.

**Trades** redraw both sides in the same strength bands, on the trade site the
host owns, so a second script naming the same trade is not changed by accident.

**Item rewards** are shuffled with their quantities, so the cartridge's whole item
budget is preserved. **Badges** are shuffled by reward group. **Shops** get one
cartridge-wide remapping of item ids, keeping shelf sizes and prices.

Every candidate item and badge placement is checked by the host's progression
proof before use. The first check decodes and caches the script corpus and can
take several seconds. If no candidate passes, those three categories stay vanilla
rather than shipping a placement the host rejected. A pass proves there is no
self-lock visible to the host's map-level model, not that every cell and story
state is beatable.

## What it deliberately leaves alone

TM and HM compatibility and what each TM teaches, so the moves you need to cross
the map are the ones the cartridge always had. Move effects, since an effect is a
list of steps and only the power beside it is moved here. And no species is
added: mod content has no art, and a Pokemon nothing can draw is not a Pokemon.

## Tools

`tools/randomizer_probe.gd` builds the plan against a real cartridge cache and
prints what changed, with no game running. It digests one seed built twice and a
second seed built once, then checks every promise above on every row:

```bash
Godot --headless --path <pokerecomp> -s tools/randomizer_probe.gd -- \
	"user://rom_cache/<cache>"
```

It exits non-zero on failure. `tools/randomizer_lifecycle_probe.gd` separately
proves that saved settings reproduce the same run and that installation settings
cannot reroll it.

## Layout

```
mod.gd       snapshots each run and carries its saved plan to the host
options.gd   the settings, named once, registered and read back here
plan.gd      cartridge plus seed -> the patches, as one pure function
rng.gd       the written-down generator, and the streams drawn off a seed
```

`plan.gd` touches no host and no node, which lets the probe build the same plan
the game does.
