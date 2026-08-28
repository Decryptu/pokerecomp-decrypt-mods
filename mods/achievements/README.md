# Achievements

Thirty things a Johto run is remembered by, awarded as you reach them. A banner
over the map says which one you just got, and a page in the start menu says which
are left.

## The thirty

Sixteen are badges, one for each gym in Johto and Kanto. The other fourteen are
the rest of what a playthrough is.

| | |
| --- | --- |
| ZEPHYRBADGE to RISINGBADGE | The eight JOHTO gyms |
| BOULDERBADGE to EARTHBADGE | The eight KANTO gyms |
| JOHTO CLEARED | All eight JOHTO badges |
| CHAMPION | The ELITE FOUR and LANCE |
| KANTO CLEARED | All sixteen badges |
| MT.SILVER | RED, at the top |
| FIRST CATCH | One POKéMON caught |
| 100 CAUGHT | A hundred species |
| POKéDEX | All 251 |
| UNOWN | All 26 letters |
| FULL PARTY | Six carried at once |
| LEVEL 100 | One raised the whole way |
| SHINY | One owned |
| RICH | A hundred thousand in cash |
| HIGH ROLLER | A thousand Game Corner coins |
| ONE DAY | Twenty-four hours played |

Each wears cartridge art. A Johto badge wears its own drawing off the trainer
card, which is the only place the game ever draws one. The Kanto eight have no
drawing at all: the card's Kanto page is unreachable on the cartridge and reuses
the Johto pictures, so those wear the gym's own type instead, and the rest wear a
Pokemon that belongs to what they are about.

## Every one is a state, not a moment

An achievement asks what a save has, never what just happened: "eight badges",
not "a badge was awarded". That is the whole of why installing the mod on a save
you have already played works. A state a run reached is still there to read; a
moment is gone.

So a save that was at the Elite Four before the mod existed is awarded everything
it had earned under **one line**, not thirty. From then on each new one is
announced as you reach it.

The set lives in the save rather than in the installation, so two slots are two
runs and neither can see the other's. Closing the game and opening it again finds
the same set and says nothing about it a second time. Turning the notice off
still awards them, so a player who wanted quiet does not come back to an empty
list.

A version of this mod that adds achievements to a save that already earned them
summarises rather than firing one notice each, by the same rule.

## The notice

A banner over the map, drawn the way the cartridge draws the sign that names a
town you have just walked into, which is the only thing this game ever puts over
a live map. It carries the achievement's own icon, `ACHIEVEMENT`, and its name.

A badge rings with the fanfare a badge rings with. The POKéDEX and UNOWN ring
like a key item. Everything else takes the jingle a found item plays. None of
them borrows the shiny sparkle: that sound means a shiny Pokemon and nothing
else, and a mod firing it for something ordinary teaches you to distrust it.

The banner waits for a moment it can be read in. A battle, a menu, a text box, a
warp or a running script all hold it until they are done, so it never lands on
top of something you were reading.

Gold and Silver ship neither that sign nor its frame, so the notice wears the
ordinary text box there.

## The page

**ACHIEVEMENTS** in the start menu. The count is the first row, then the thirty,
eight at a time, scrolled with the d-pad and left with B.

A locked one reads `?`, the way the Pokedex draws an entry you have not seen.
That is the cartridge's own answer to the question, and it is the one this mod
takes: what is left is a thing to find out rather than a list to tick off.

## Settings

In the start menu's MODS entry, and on the mod's launcher page.

| | |
| --- | --- |
| NOTICE | Whether an unlock raises the banner. ON by default |
| NOTICE SOUND | Whether the banner makes a sound. ON by default |

## What it needs

`api_version` 21: the host answers what the run has achieved and says when a
field of it moves, raises a mod's banner over the map, and keeps a mod's page
behind a start-menu row. The mod draws none of that itself. It reads no world and
no battle state, holds no scene node and composes no pixel.
