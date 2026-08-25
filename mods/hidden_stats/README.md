# Hidden Stats

A fourth page on a Pokemon's stats screen, showing the two numbers Generation II
keeps and never displays: the DVs it was born with, and the stat experience it
has trained.

## The page

Turn to it with LEFT and RIGHT or by pressing A, like the other three pages. It
has its own square on the indicator row and uses the blue page's layout: a
divider down column 10, names on the left, numbers right-aligned.

```
        DV  STAT EXP
HP      14     65535
ATTACK   9     63002
DEFENSE  3      1024
SPECIAL 12       320
SPEED   15     25600
```

Five rows, because the hardware stores five. HP has no DV of its own: it is
built from the low bit of the other four, which is also what decides shininess.
SPECIAL has one stat experience counter, read by both special stats.

A DV runs 0 to 15 and stat experience 0 to 65535. 63002 is the highest value
that still changes anything: the contribution is the square root over four, and
the cartridge's square root table stops at 255.

Eggs have no pages. `EggStatsScreen` replaces the whole screen rather than the
lower half, so the page is not offered there.

## What it needs

`api_version` 8. The mod draws nothing: it returns strings and where they go,
and the host writes them with the screen's own font and divider. It writes
nothing to the save or the world.
