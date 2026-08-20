# Hidden Stats

A fourth page on a Pokemon's stats screen, carrying the two numbers Generation
II keeps and never shows: the DVs a Pokemon was born with, and the stat
experience it has trained since.

## The page

Turn to it the way the other three are turned, with LEFT and RIGHT or by
pressing A, and it has its own square on the indicator row. It draws in the
lower ten rows the cartridge's own pages draw in, in the blue page's shape: a
divider down column 10, names on the left of it and numbers right-aligned to
the last column, which is where every number on the cartridge's own pages
ends.

```
        DV  STAT EXP
HP      14     65535
ATTACK   9     63002
DEFENSE  3      1024
SPECIAL 12       320
SPEED   15     25600
```

Five rows, because five is what the hardware stores. A DV is four bits per stat
and HP's is not kept at all: it is assembled from the low bit of the other four,
which is the same reading that decides whether a Pokemon is shiny. Stat
experience is one counter for SPECIAL, read by both special stats. Printing six
rows would mean printing one number twice and inventing another.

A DV runs 0 to 15 and stat experience 0 to 65535, and 63002 is the last value
that changes anything: the contribution is the square root over four, and the
cartridge's own root is a table lookup that stops at 255, so the count keeps
rising past that and the stat does not.

An egg has no pages. `EggStatsScreen` replaces the whole screen rather than the
lower half, and this page is not offered there.

## What it needs

`api_version` 8. Nothing is drawn by this mod: the page answers with strings and
where they go, and the host writes them with the screen's own font, divider and
page indicator. Nothing is written either, on the save or in the world.
