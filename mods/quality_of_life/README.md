# Quality of Life

Small conveniences from later Pokemon games, fitted to Gold, Silver and Crystal
without changing their rules unless the player asks for each change. Every
feature has its own switch and every switch defaults to OFF.

## Features

- `FIELD MOVES` lets an owned HM and its badge stand in for a party member that
  knows Cut, Fly, Surf, Strength, Flash, Whirlpool or Waterfall.
- `AUTO REPEL` offers the weakest Repel in the pack when the active one expires.
- `CATCH EXP` awards ordinary wild-battle experience after a successful catch.
- `PC ACCESS` puts Bill's Pokemon storage in the start menu once the player has
  a Pokemon.
- `MOVE GUIDE` marks super-effective, resisted and ineffective moves after the
  opponent has been seen.
- `STAT STAGES` shows only the active battle stat changes beside the Pokemon
  they affect.
- `WEATHER` shows the current sun, rain or sandstorm in one battle-screen corner.

The move guide uses the spare cell at the right of each move row. Stage summaries
use the empty lower-left command panel for the player and the space above the
enemy picture for the opponent; they yield while the move list's type box owns
that panel. Enemy stages and weather carry the same light interface field as the
battle's name cards, so they stay legible over a 3D arena.

## Vanilla boundaries

Generation II already animates an EXP bar, records seen and caught Pokemon, and
shows map names. Those are not duplicated. Its held EXP. SHARE also keeps its
cartridge behavior: changing that distribution would change team balance rather
than remove friction.

The field-move option does not waive badge or HM ownership. The PC row stays
hidden before the first Pokemon. Battle guidance uses the current battle state
and the save's existing Pokedex knowledge rather than revealing an unseen
opponent.

## What it needs

`api_version` 14, which keeps every changed transaction in the host: field
moves, Repel use, capture experience and PC storage all run through the game's
existing paths. The battle provider receives exact, read-only state and returns
only text and 8x8 tiles on the cartridge grid, with a host-owned interface field
where bare scenery would make black ink unreadable.
