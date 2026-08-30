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
- `EXP RATE` multiplies every experience award: `x0.5`, `x1`, `x1.5`, `x2` or
  `x4`. `x1` is the cartridge's own and is what it ships at.

Running needs no item and no shoes to find: hold B on foot and a step takes the
bike's four frames instead of eight. It is a step either way, so nothing about
encounters, Repel or the map changes, and a follower keeps up. The bike is
already this fast and surfing is unaffected.

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
map names, so those are left alone. EXP. SHARE keeps its cartridge behaviour:
changing it would change team balance rather than remove friction.

Field moves still require the badge and the HM. The PC row is hidden until you
have your first Pokemon. Battle hints use the current battle state and what the
Pokedex already knows, and never reveal an unseen opponent.

## What it needs

`api_version` 26. Every changed transaction stays in the host: field moves,
Repel use, catch experience, the step's own duration, the experience award and
PC storage all run through the game's existing paths. The battle provider gets
read-only state and returns only text and 8x8 tiles on the cartridge grid, plus a
host-owned background where black text would otherwise be unreadable.
