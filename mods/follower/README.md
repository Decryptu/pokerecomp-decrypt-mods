# Follower

One of your Pokemon out of its ball, walking one cell behind you. It is drawn
with the cartridge's own party icon for its species, so the mod ships no art.

## How it moves

The follower stands on the cell you have just left. Your logical cell commits at
the start of a step, so the moment you step the cell behind you is free and the
follower steps into it. Both steps are drawn at the same fraction, which keeps
the pair exactly one cell apart at rest and never more than one cell apart
mid-step. It counts no frames of its own and cannot drift.

Walking off the edge of one map into the next renumbers every cell behind you,
so the follower is carried into the new map's numbering and keeps walking: it
crosses a town boundary a cell behind you, standing on the strip of the map you
just left, rather than being put back under you and walking out again. A warp, a
Fly and the first frame of a session do put it back under you, and it walks out
from there. A script that commits a whole path at once is taken at once.

A ledge is not. It is one move of two cells, so the follower takes the ledge
itself a move behind you: it walks up to the edge while you sail over, then
crosses it when you walk on. What it is doing is drawn as the two cells it runs
between, so a view that stands the world up in 3D takes the ledge through its
own geometry rather than reading a fractional cell across the drop.

It is presentation only. It occupies no cell, blocks nothing, cannot be talked
to and is not seen by trainers.

## Petting it

Turn to face it and press A. It looks back, shows the cartridge's own heart for a
second and plays its cry.

The turn is the cartridge's own behaviour: the first press in a direction only
turns you, so you end up facing each other. That branch is on the input path
only, so a scripted walk never triggers it.

The press reaches the mod only after the world had no answer for that cell: no
object, no background event, no tile branch. So petting can never shadow a sign,
an NPC or a ledge, and it needs no setting.

Nothing here is drawn or played by the mod. The heart is a pose the host draws
two rows above the sprite, the same way `SpawnEmote` does over an NPC, and the
cry is played by the host through the same player the Pokedex uses.

## Finding hidden items

`FINDS ITEMS`, off by default. When on, the follower picks up a hidden item it
walks over, and reaches one cardinal step into a cell it could not have walked
into: the item under a rock, inside a wall or across a ledge. A hidden item on
open floor beside it is left alone, since the follower can simply walk over that
one and reaching for it would clear a route from a distance.

It is off by default because the cartridge hides these to be looked for.

The mod names a cell and never takes anything. The host writes the bag, the
event flag and the save, and runs its own `verbosegiveitem` with the FOUND text,
the fanfare and the pack-full branch.

It asks once each time the follower arrives somewhere, which is the cartridge's
own unit: one attempt per step. So an item it found while the pack was full is
found again the next time the follower walks there, rather than being lost for
the rest of the map.

## Settings and the control

Five rows in the start menu's MODS entry and on the mod's page in the launcher,
all from one registration in `options.gd`.

| Setting | Rungs | Does |
| --- | --- | --- |
| WHO | LEAD, 2 to 6 | Which party slot walks |
| ON BIKE | OFF, ON | Whether it stays out while cycling |
| ON WATER | OFF, ON | Whether it stays out while surfing |
| FINDS ITEMS | OFF, ON | Whether it picks up hidden items |
| FOLLOWER | RECALL | Puts it away; the next press calls it back |

Opening a healthy Pokemon's own party menu adds a FOLLOW row. Choosing it sets
WHO and closes the menu; opening that Pokemon again says FOLLOWING. Eggs get no
row, and neither does the battle party menu.

Both movement rows are off by default: a Pokemon jogging beside a bicycle and one
walking on the sea are where the illusion breaks, and both are one press away.

RECALL is both a menu row and a key. On `F` by default it is declared to the
host rather than read as a keycode, so it is rebindable in the launcher's
controls card and can go on the on-screen pad. The FOLLOWER menu row is the same
action with no binding, for a player on a pad or a phone. Both paths toggle the
same state. It lasts for the session only.

Some Pokemon stay in the ball whatever the settings say: an empty slot, an egg, a
fainted Pokemon, and any species the cartridge has no icon for.

It also goes back in its ball for the frames the party is not physically with
you: over a healing machine, at the Hall of Fame's, over either Day Care counter
and in the trade cable. The host answers which of those has it, so the follower
is put away for exactly those frames and is out again on the frame the scene
ends, standing where it was rather than under you.

## How it is drawn

The host draws the world and this mod draws nothing. `register_world_actor`
hands the host an object it drives one frame at a time, and each frame the
follower answers with one sprite naming the cartridge's icon row for that species
and where to put it, in walk cells. The host resolves the strip, the palette, the
time of day and the icon's two frames, and sorts it into the object pass by the
row it stands on.

The 3D view takes the same resolved actor through `set_actors` and stands it up
as a card with its own shadow. Pressing `V` swaps views without losing it.

## Tools

`tools/follower_shot.gd` photographs it on a real map through the game's own
world screen. Rendering needs a display, and mods load in a tool run only when
asked for:

```bash
Godot --path <pokerecomp> --mods -s tools/follower_shot.gd -- \
	crystal 26 1 <out.png> [species] [steps] [view] [pet]
```

`tools/follower_probe.gd` walks a route past the follower against a real
cartridge cache with no game running:

```bash
Godot --headless --path <pokerecomp> -s tools/follower_probe.gd -- \
	"user://rom_cache/<cache>"
```

It prints the icon row for each party slot, then one line per frame, then checks
every frame of two routes. One route walked twice digests to the same number and
a different route does not. It exits non-zero on failure.

## Layout

```
mod.gd       registers the settings, party row, control and follower
options.gd   the settings and the control, named once
party.gd     which Pokemon is out, read off the party the world mirrors
trail.gd     the player's steps -> the follower's pose, as one pure function
finder.gd    where it stands -> the hidden item it reaches
actor.gd     the object the host drives: a frame in, a sprite out, no writes
```

`trail.gd`, `party.gd` and `finder.gd` touch no host and no node, which is what
lets the probe walk the same route the game would.
