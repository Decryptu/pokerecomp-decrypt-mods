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

The same seed and the same cartridge always produce the same game. It does not
depend on dictionary ordering, the clock, the system's randomness, or the order
settings were changed in. Randomness comes from one written-down generator in
`rng.gd` rather than the engine's. Each decision opens its own stream, keyed by
what is being decided and which row it is for, so turning one setting off does
not move what another produced.

A seed does not carry the cartridge. Each of the six games has its own tables,
so seed `1234` is six different runs.

## A run belongs to its save

The launcher settings describe the next new run. When a save is created, the
seed, every toggle, an algorithm version and the resolved item and badge
placement are written into that save's own mod namespace, under 9 KB on every
cartridge. Loading it rebuilds the run from those before gameplay reads the
cartridge. Changing a setting cannot reroll a save already in progress, a later
host whose reachability answers differently cannot move its items or badges, and
two slots cannot leak into each other. A save with no snapshot, or one made by an
earlier algorithm version, stays vanilla.

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
evolution line gets the same shuffle, so a line still climbs. Red, Blue and
Yellow have five stats, and the one SPECIAL stays one number.

**Types** are drawn per line rather than per species, so a Pokemon does not change
type by evolving. The pool is the set of types this cartridge's species actually
carry, which keeps unused type slots out of it.

**Movesets** keep every level and replace every move. The opening is guarded: the
first entry, and every entry at level 5 or below, is drawn from moves that do
damage, land four times in five and are not overwhelming, so a starter can always
attack at level 5. A species does not repeat a move while an unused eligible one
remains. On Red, Blue and Yellow the moves a species is born with are its level 1
entries and are drawn the same way.

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
and live roaming positions are untouched. On Red, Blue and Yellow that is grass,
surfing, every Super Rod table, the Old Rod's one slot and the Good Rod's two.

**Gifts and static Pokemon** change species only. Levels, held items, prices,
scripts and completion flags stay put. A Game Corner prize that is a TM has no
species and is left alone; on Red, Blue and Yellow the fossil revival takes its
species from the fossil and is not a site.

**Starters** are distinct and strength-banded. The host changes the ball's
picture and the Pokemon it gives as one transaction, and on Red and Blue the
rival's pick still follows the table. Yellow's one starter is its Pikachu.

**Trades** redraw both sides in the same strength bands, on the trade site the
host owns, so a second script naming the same trade is not changed by accident.

**Item rewards** move with their quantities, so the cartridge's whole item budget
is preserved. **Badges** move by reward group: the sites that gave one badge
give one other. **Shops** get one cartridge-wide remapping of item ids, keeping
shelf sizes and prices. Shops gate nothing and take no part in the placement.

Items and badges are placed by assumed fill over the host's reachability. The
badges, and the items the story reads or a field move needs, are placed one at
a time, those with the fewest possible sites first and the seed's order
otherwise. Each goes to a random empty site the host reaches with every reward
still waiting in hand and every empty site handing nothing. The other items are
then dealt into the sites left. The host's reachability covers the story's
gates, such as OAK'S PARCEL before the Pokedex, and the cell each item lies on,
so a placement built this way finishes by construction. The host's
`validate_placement` checks it once more, and a rejection is logged as a warning.

Badges are filled around the cartridge's own items, and items around both the
cartridge's badges and the filled ones, so ITEMS and BADGES finish in every
combination and turning one off moves nothing the other placed. A fill can spend
the one site a later reward needed, and then starts over with new choices. About
two badge attempts in three do on Gold, Silver and Crystal, and no fill of the
first ten seeds on Red, Blue and Yellow. A category still unplaced after 64
attempts, far rarer than one seed in a billion, stays vanilla with a warning.

Creating a save runs the fill once: about one second on Red, Blue and Yellow and
three to seven on Gold, Silver and Crystal. The host's model errs
toward passing, so a placement proves there is no lock the model can see, not
that every story state is beatable. On Red, Blue and Yellow no item site hands
HM05 or the POKé DOLL, so the fill never moves them.

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

It then turns ITEMS, BADGES and SHOPS off one at a time to show the other two
unmoved, and places seeds 0 to 9 at the defaults, timing each and asking the
host to accept it. It exits non-zero on failure.

`tools/randomizer_lifecycle_probe.gd <cache>` separately proves, through the
real host, that a save reproduces its run, plays the placement it stored rather
than a fresh fill, and stays vanilla with no snapshot or an earlier algorithm.
`tools/randomizer_shot.gd <game> <out.png> <seed> [page]` photographs one party
member's stats page under a seed, or vanilla for a seed below zero, and
`tools/randomizer_shop_shot.gd <game> <out.png> <seed>` a shop's shelf through
its counter, so a run can be seen as well as counted.

The mod needs `api_version` 44, the first host that answers
`reachable_checks`, lists `progression_items()` and takes `{"item": 0}` and
`{"badge": -1}` as a site that hands nothing.

## Layout

```
mod.gd        snapshots each run and its placement, and carries them to the host
options.gd    the settings, named once, registered and read back here
placement.gd  assumed fill of items and badges, shop remapping, the saved form
plan.gd       cartridge, seed and placement -> the patches, one pure function
rng.gd        the written-down generator, and the streams drawn off a seed
```

`plan.gd` and `placement.gd` touch no host and no node, the fill asking
reachability through a callable, which lets the probe build the same plan the
game does.
