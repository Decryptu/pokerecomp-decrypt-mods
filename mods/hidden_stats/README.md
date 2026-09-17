# Hidden Stats

One more page on a Pokemon's stats screen, showing the two numbers the first
two generations keep and never display: the DVs it was born with, and the stat
experience it has trained. The fourth page on Gold, Silver and Crystal; the
third on Red, Blue and Yellow.

## The page

On Gold, Silver and Crystal, turn to it with LEFT and RIGHT or by pressing A,
like the other three pages. It has its own square on the indicator row and
uses the blue page's layout: a divider down column 10, names on the left,
numbers right-aligned.

On Red, Blue and Yellow the screen turns with A alone and has no indicators,
so the page comes after the moves and A on it leaves the screen, the way A on
the moves did before.

```
        DV  STAT EXP
HP      14     65535
ATTACK   9     63002
DEFENSE  3      1024
SPECIAL 12       320
SPEED   15     25600
```

Five rows, because the hardware stores five. HP has no DV of its own: it is
built from the low bit of the other four, which on Generation II is also what
decides shininess. SPECIAL has one stat experience counter, read by both
special stats on Generation II and by the one SPECIAL on Generation I.

A DV runs 0 to 15 and stat experience 0 to 65535. 63002 is the highest value
that still changes anything: the contribution is the square root over four, and
the cartridge's square root table stops at 255.

Eggs have no pages. `EggStatsScreen` replaces the whole screen rather than the
lower half, so the page is not offered there.

## What it needs

A stats screen that turns to a registered page on every cartridge. The mod
draws nothing: it returns strings and where they go, and the host writes them
with the screen's own font and divider. It writes nothing to the save or the
world.
