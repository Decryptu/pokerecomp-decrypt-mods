# Quality of Life

Small conveniences from later Pokemon games, fitted to Gold, Silver and Crystal.
Every feature has its own setting, and nothing is on until you turn it on.

## Features

- `FIELD MOVES` lets an owned HM and its badge stand in for a party member that
  knows Cut, Fly, Surf, Strength, Flash, Whirlpool or Waterfall.
- `AUTO REPEL` offers the weakest Repel in the pack when the active one runs out.
- `CATCH EXP` gives normal wild-battle experience after a successful catch.
- `PC ACCESS` puts Bill's PC in the start menu once you have a Pokemon.
- `RUN SHOES` walks you at bike speed while B is held.
- `MOVE GUIDE` marks super-effective, resisted and ineffective moves once you
  have seen the opponent.
- `STAT STAGES` shows the active battle stat changes beside the Pokemon they
  affect.
- `WEATHER` shows sun, rain or sandstorm in a corner of the battle screen.
- `MULTI EXP` pays every party member, not only the ones that fought: `HALF`
  is Generation VI's Exp. Share and `FULL` is Generation VIII's.
- `EXP RATE` multiplies every experience award: `x0.5`, `x1`, `x1.5`, `x2` or
  `x4`. `x1` is the cartridge's own and is what it ships at.

Running needs no item and no shoes to find: hold B on foot and a step takes the
bike's four frames instead of eight. It is a step either way, so nothing about
encounters, Repel or the map changes, and a follower keeps up. The bike is
already this fast and surfing is unaffected.

`MULTI EXP` needs a living party member to be holding an EXP. SHARE, any of them,
fighting or not. The item is still what turns it on, so the setting is not a
switch with nothing behind it, and a party carrying no Share is the cartridge.

The cartridge splits a defeat two ways: the beaten Pokemon's block is halved if
anyone alive holds a Share, divided among whoever fought, and divided again among
the holders. `MULTI EXP` adds a third payment, whatever fraction the rung names,
to every living member neither of those two paid, and stops the halving, since
neither later generation halves. So `FULL` pays the fighter what it would have
earned with no Share in the party at all, and pays everyone else the same. Stat
experience is the fighters' own share unchanged, for the reason below.

The holder itself is paid by the cartridge's own second pass rather than as a
bystander, so at `HALF` it earns a fighter's full award while the rest of the
bench earns half. Carrying the Share is what that pass is for.

`EXP RATE` scales the award itself, so the participant split, the Exp. Share
halving, level ups, moves learned and evolutions all follow from it, and a
capture with `CATCH EXP` on scales too. Stat experience is left alone, since it
is the cartridge's own hidden EV gain rather than a rate.

The move guide uses the spare cell at the right of each move row. Stat stages use
the empty lower-left command panel for the player and the space above the enemy
picture for the opponent, and they hide while the move list's type box needs that
panel. The player's panel holds five rows, so with more stat changes than that
active at once the last of them are not drawn. Enemy stages and weather get the
same light background as the battle's name cards so they stay readable over a 3D
arena.

## What it does not change

The game already animates an EXP bar, records seen and caught Pokemon and shows
map names, so those are left alone. EXP. SHARE keeps its cartridge behaviour
until `MULTI EXP` is turned on, which is off by default.

Field moves still require the badge and the HM. The PC row is hidden until you
have your first Pokemon. Battle hints use the current battle state and what the
Pokedex already knows, and never reveal an unseen opponent.

## What it needs

`api_version` 29. Every changed transaction stays in the host: field moves,
Repel use, catch experience, the step's own duration, the experience award and
PC storage and the share a bystander is paid all run through the game's existing
paths. The battle provider gets
read-only state and returns only text and 8x8 tiles on the cartridge grid, plus a
host-owned background where black text would otherwise be unreadable.
