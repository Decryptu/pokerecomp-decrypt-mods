# Catch Combo

Catch the same species over and over and its wild Pokemon start being drawn with
more DV words, so a shiny comes sooner. It is the Let's Go games' Catch Combo,
on a cartridge that has fishing, trees and rocks for it to count.

## The combo

A catch of the species the combo is on makes it one longer. A catch of anything
else starts that species' own combo at one. Where the Pokemon came from does not
matter: grass, water, a rod, a Headbutt tree or a smashed rock all count, and so
does a static encounter, because every one of them is a wild Pokemon caught.

The catching tutorial and a Bug Contest catch do not, since neither is a Pokemon
you keep.

| | |
| --- | --- |
| Runs from a wild | Combo stands |
| Knocks it out, or loses to it | Combo stands |
| Walks to another map, saves, heals | Combo stands |
| The wild leaves under Roar, Whirlwind or its own Teleport | Combo broken |
| Closes the game, or opens another save | Combo gone |

Those are the later games' rules. A wild that got away is the one break they
have, and a combo is never written into a save there either.

## The odds

| Combo | Rolls | Odds | With the Shiny Charm |
| --- | --- | --- | --- |
| 1 to 10 | 1 | 1 in 8192 | 1 in 2731 |
| 11 to 20 | 4 | 1 in 2048 | 1 in 1365 |
| 21 to 30 | 8 | 1 in 1024 | 1 in 819 |
| 31 or more | 12 | 1 in 683 | 1 in 585 |

Shininess in Generation II is not a flag: it is the Pokemon's four DVs. The host
draws that many DV words, keeps the first `CheckShininess` accepts and otherwise
the last, and this mod only says how many to draw. Each column is what the same
combo is worth in the Let's Go games, roll for roll.

The boost belongs to the chained species alone, exactly as it does there, so the
Pidgey that interrupts a Rattata combo is drawn with one word. Pokemon whose
stats are already decided are untouched: gifts, trades, eggs, roaming
legendaries and the red GYARADOS.

[`shiny_charm`](../shiny_charm/) stacks with this, the way a charm stacks with a
combo in the later games: each is worth the extra rolls it is worth alone, and
the host adds them together. Neither mod needs the other.

## The box

After a catch the battle prints one more line, `Catch Combo 12!`, before the
nickname prompt. COMBO BOX in the start menu's MODS entry says how often:

| | |
| --- | --- |
| EVERY | After every catch. The default, and what the later games' counter does |
| RUNGS | Only at 11, 21 and 31, the catches the odds actually move on |
| OFF | Never |

Nothing announces a break, and nothing announces the combo you were on when you
put the game down. Neither do the games this is from.

## What it needs

`api_version` 20: the host reports a capture on the battle channel, lets a mod
add a line to the battle's own message run, and adds a mod's extra shiny rolls
to another mod's rather than taking the larger of the two.
