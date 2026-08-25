# Quality of Life

Small conveniences from later Pokemon games, fitted to Gold, Silver and Crystal.
Every feature has its own switch and every switch is OFF by default.

## Features

- `FIELD MOVES` lets an owned HM and its badge stand in for a party member that
  knows Cut, Fly, Surf, Strength, Flash, Whirlpool or Waterfall.
- `AUTO REPEL` offers the weakest Repel in the pack when the active one runs out.
- `CATCH EXP` gives normal wild-battle experience after a successful catch.
- `PC ACCESS` puts Bill's PC in the start menu once you have a Pokemon.
- `MOVE GUIDE` marks super-effective, resisted and ineffective moves once you
  have seen the opponent.
- `STAT STAGES` shows the active battle stat changes beside the Pokemon they
  affect.
- `WEATHER` shows sun, rain or sandstorm in a corner of the battle screen.

The move guide uses the spare cell at the right of each move row. Stat stages use
the empty lower-left command panel for the player and the space above the enemy
picture for the opponent, and they hide while the move list's type box needs that
panel. The player's panel holds five rows, so with more stat changes than that
active at once the last of them are not drawn. Enemy stages and weather get the same light background as the battle's
name cards so they stay readable over a 3D arena.

## What it does not change

The game already animates an EXP bar, records seen and caught Pokemon and shows
map names, so those are left alone. EXP. SHARE keeps its cartridge behaviour:
changing it would change team balance rather than remove friction.

Field moves still require the badge and the HM. The PC row is hidden until you
have your first Pokemon. Battle hints use the current battle state and what the
Pokedex already knows, and never reveal an unseen opponent.

## What it needs

`api_version` 14. Every changed transaction stays in the host: field moves,
Repel use, catch experience and PC storage all run through the game's existing
paths. The battle provider gets read-only state and returns only text and 8x8
tiles on the cartridge grid, plus a host-owned background where black text would
otherwise be unreadable.
