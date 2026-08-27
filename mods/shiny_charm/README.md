# Shiny Charm

Generation II gives you nothing for completing the Pokedex but a diploma. This
mod has the GAME designer hand you a Shiny Charm with it, like the later games.
While the charm is in your bag, wild Pokemon are three times more likely to be
shiny.

## Getting it

Complete the Pokedex, go to the top floor of the Celadon Condominiums and talk
to the GAME designer. He shows the diploma as usual, then gives you the charm
with the normal fanfare and `<PLAYER> received SHINY CHARM!` box. It goes in the
KEY ITEMS pocket.

The diploma script and its Pokedex check are the cartridge's own, so what counts
as a complete Pokedex has not changed. A save that completed its dex before the
mod was installed still gets the charm: the designer offers to print the
certificate again on any later visit, and the charm comes with that.

## Carrying it

| | Rolls | Odds |
| --- | --- | --- |
| Without the charm | 1 | 1 in 8192 |
| With it | 3, keeping the first shiny | 1 in 2731 |

Three rolls is what the later games' charm does. At these odds the rolls barely
overlap, so it works out to almost exactly three times the chance.

The charm is worth its two extra rolls on top of whatever else a mod is worth,
the way it stacks with a Catch Combo in the later games. The host adds them
rather than taking the larger, so with [`catch_combo`](../catch_combo/) at 31 a
wild is drawn with fourteen words. Neither mod needs the other.

Shininess in Generation II is not a flag: it is the Pokemon's four DVs. The host
rolls them and tests them exactly as `CheckShininess` does. This mod only says
how many times to roll.

It applies to grass, water, fishing, Headbutt, Rock Smash and the Bug Contest.
It does not apply to a Pokemon whose stats are already decided: gifts, trades,
eggs, static encounters, roaming legendaries, or the red GYARADOS, which is
shiny because its script says so.

## It is a key item

No USE, no SELECT, no TOSS, the same row the CLEAR BELL has. Generation II draws
no item sprites, so the charm is a name, a quantity and a two-line description
in the cartridge's font, exactly like the SILVER WING.

## What it needs

`api_version` 16: the host rolls each wild Pokemon's DVs, takes a roll count
from a mod, can hand an item to the player, and can be asked what is in the bag.
The mod names an item number and a roll count and writes nothing itself.
