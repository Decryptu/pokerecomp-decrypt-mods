# Linking Cord

Ten Pokemon evolve only by being traded, which is impossible with nobody on the
other end of the cable. Use the cord on one of them and it evolves on the spot.

## Using it

An ordinary item in the ITEM pocket with an evolution stone's submenu: USE,
GIVE, TOSS, QUIT. USE opens the party list under `Use on which #MON?` and the
cord is spent on the Pokemon you pick. On anything else it says
`It won't have any effect.` and is not spent, exactly like a stone.

The ten it works on, and the held items six of them need, come from the
cartridge's own table:

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

The held item is consumed, the way a trade consumes it. An EVERSTONE blocks the
cord, the way it blocks a trade. The result is registered in the Pokedex, and a
Pokemon that was never nicknamed takes its new species name. Both message boxes
name it by what it was before, so an unnicknamed ALAKAZAM is congratulated as
KADABRA.

## Buying it

Goldenrod Dept Store 2F, at the counter that sells the ESCAPE ROPE, the REPEL
and the POKe DOLL, for 2100: the price of every evolution stone here, and what
the later games charge for this item. One shelf on all three cartridges.

## There is no item picture

Generation II draws no item sprites at all. The pack is a list of names over a
picture of the pack itself. So the cord is a name, a quantity and a description
line in the cartridge's font, exactly like a MOON STONE.

## What it needs

`api_version` 9, for an item row that names an evolution method. The mod draws
nothing and writes nothing: it names the method, and the host runs the same
check a trade would, so the species, the consumed held item, the EVERSTONE
refusal, the HP carried across and the new moves are all decided where the
cartridge's own stones decide them.
