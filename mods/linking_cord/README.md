# Linking Cord

The item the later games sell instead of asking for a friend. Ten of the
cartridge's Pokemon evolve only by being traded, and a cartridge with nobody on
the other end of the cable is a cartridge where those ten evolutions do not
exist. Use the cord on one of them and it evolves where it stands.

## Using it

It is an ordinary item in the ITEM pocket, with an evolution stone's own
submenu: USE, GIVE, TOSS, QUIT. USE opens the party list under
`Use on which #MON?`, and the cord is spent on the Pokemon picked. On anything
else it says `It won't have any effect.` and is not spent, which is what a
stone says to a Pokemon it cannot evolve.

The ten it works on, and the four items six of them want to be holding, are
the cartridge's own table rather than a list kept here:

| Evolves | Into | Holding |
| --- | --- | --- |
| POLIWHIRL | POLITOED | KING'S ROCK |
| SLOWPOKE | SLOWKING | KING'S ROCK |
| ONIX | STEELIX | METAL COAT |
| SCYTHER | SCIZOR | METAL COAT |
| SEADRA | KINGDRA | DRAGON SCALE |
| PORYGON | PORYGON2 | UP-GRADE |
| KADABRA | ALAKAZAM | |
| MACHOKE | MACHAMP | |
| GRAVELER | GOLEM | |
| HAUNTER | GENGAR | |

A held item the evolution asked for is consumed by it, the way a trade consumes
it. An EVERSTONE refuses the cord the way it refuses a trade. What comes out is
entered in the Pokedex, and a Pokemon that was never nicknamed takes its new
species' name; one that was keeps what you called it. Both boxes name it by
what it came in as, so an ALAKAZAM that was never nicknamed is congratulated as
the KADABRA it was.

## Buying it

Goldenrod Dept Store 2F, at the counter that already sells the ESCAPE ROPE, the
REPEL and the POKé DOLL, for 2100: what every evolution stone costs here, and
what the later games price this item at. One shelf on all three cartridges.

## There is no picture, and that is the vanilla answer

Generation II draws no item sprites. The pack is a list of names over a picture
of the pack itself, one per pocket, and the cable club's own art belongs to a
room rather than to an item. So the cord is a name, a quantity and a
description line, drawn with the cartridge's font, which is exactly what a MOON
STONE is.

## What it needs

`api_version` 9, for an item row that names an evolution method. Nothing is
drawn by this mod and nothing is written by it: the row NAMES the method, and
the host runs the same predicate a trade would, so the species, the held item
it consumes, the EVERSTONE refusal, the HP carried across and the moves the new
species learns are decided where the cartridge's own stones decide them.
