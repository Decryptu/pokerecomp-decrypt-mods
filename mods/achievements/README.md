# Achievements

Thirty things a Johto run is remembered by, awarded as you reach them. A notice
says which one you just got, and a list says which are left.

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
the Johto pictures, so those wear the gym's own type instead, and the rest wear
a Pokemon that belongs to what they are about.

## Every one is a state, not a moment

An achievement asks what a save has, never what just happened: "eight badges",
not "a badge was awarded". That is the whole of why installing the mod on a save
you have already played works. A state a run reached is still there to read; a
moment is gone.

So a save that was at the Elite Four before the mod existed is awarded
everything it had earned, **in silence**. It is not news, and thirty notices in
a row would be worse than none. From then on each new one is announced as you
reach it.

The set lives in the save rather than in the installation, so two slots are two
runs and neither can see the other's. Closing the game and opening it again
finds the same set and says nothing about it a second time. Turning the notice
off still awards them, so a player who wanted quiet does not come back to an
empty list.

A version of this mod that adds achievements to a save that already earned them
summarises rather than firing one notice each, by the same rule.

## Settings

In the start menu's MODS entry, and on the mod's launcher page.

| | |
| --- | --- |
| NOTICE | Whether an unlock says so on screen. ON by default |
| NOTICE SOUND | Whether it makes a sound. ON by default |

## What it needs

`api_version` 20 for the save lifecycle it keeps its ledger in.

The notice and the list are drawn by the host rather than by the mod, which is
the contract: a mod is handed no scene node and draws no pixel. Three host
seams carry them, and the mod awards nothing until the first of them lands.

| | |
| --- | --- |
| The run's progress | What a save has: badges, the Hall of Fame, the dex counts, the party, money, coins, play time. Read once when a slot opens, which is the late install, and again whenever one of them moves |
| A notice | One line and one icon over the map, with a sound, drawn the way the map name sign is |
| A list | A page the achievements are read on, reached from the start menu |
