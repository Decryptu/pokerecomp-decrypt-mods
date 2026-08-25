# Shiny Charm

Generation II gives you nothing for finishing the Pokedex but a certificate. The
GAME designer on the top floor of the Celadon Condominiums prints your name on a
diploma, congratulates you, and that is the whole of the reward. This mod has him
hand something over with it: a charm that makes a rare colour three times as
likely for as long as you carry it.

## Earning it

Fill the Pokedex, go to Celadon and talk to the GAME designer. He shows the
diploma the way he always did, and the charm follows it in the same breath, with
the fanfare and the `<PLAYER> received SHINY CHARM!` box any found item gets. It
lands in the KEY ITEMS pocket.

The diploma script is the cartridge's own, and so is the test in front of it, so
what counts as a finished Pokedex is exactly what counted before. A save that
finished its dex before this mod was installed is not left out: the designer
offers to print the certificate again on every later visit, and the charm is
handed over the first time you take him up on it.

## Carrying it

| | Wild Pokemon | Roughly |
| --- | --- | --- |
| Without the charm | one roll at the DV word | 1 in 8192 |
| With it | three rolls, the first rare one kept | 1 in 2731 |

Three rolls is the later games' own charm rather than a multiplier invented here,
and at these odds three tries barely overlap, so it lands within a hundredth of a
percent of three times the chance.

What a roll is, is the hardware's: shininess in Generation II is not a flag but
four numbers, an ATTACK DV carrying its second bit over DEFENSE, SPEED and
SPECIAL all at ten. Nothing here decides it. The host rolls the word off the
encounter's own generator and tests it the way `CheckShininess` does; this mod
answers one question, which is how many times to roll.

It applies wherever a wild Pokemon is rolled, which is grass, water, fishing,
Headbutt, Rock Smash and the Bug Contest. It does not apply to a Pokemon that
arrives with its numbers already decided: a gift, a trade, an egg, a static
encounter, a roaming legendary, or the red GYARADOS, which is shiny because the
script says so and would be with or without a charm.

## It is a key item and nothing else

No USE, no SELECT, no TOSS, the CLEAR BELL's own row: an item that is worth
something by being owned has no field effect at all. Generation II draws no item
sprites either, so the charm is a name, a quantity and a two-line description in
the cartridge's font, which is exactly what a SILVER WING is.

## What it needs

A host that rolls a wild Pokemon's DVs, a policy seam for how many times to roll
one, a way for a mod to ask the host to hand an item over, and a bag it can read.
Everything the charm does is the host's own transaction: the mod names an item
number and a roll count and writes nothing.
