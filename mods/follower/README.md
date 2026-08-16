# Follower

One of your Pokemon out of its ball, walking the cell you just left. It is drawn
with the cartridge's own party icon for its species, so nothing ships with this
mod and nothing could: the picture comes out of the player's own cartridge, like
everything else in this repository.

## What it does

THE RULE IS ONE LINE: the follower stands on the cell the player has just left.
The player's logical cell commits at the start of a step, so the moment a step
begins the cell behind them is free and the follower begins its own step into
it. Both steps are drawn with the same fraction, which is what keeps the pair
exactly one cell apart at rest and never more than one cell apart mid-step. The
follower counts no frames of its own and cannot drift ahead of or behind the
player.

A warp, a fly and the first frame of a session all put it back under the player,
and it walks out from there rather than crossing the new map to find you. A
ledge hop, and any script that commits a path in one go, is not a walk it can
follow a cell at a time, so it is taken at once.

It is presentation and nothing else. It occupies no cell, blocks nothing, is
talked to by nobody and is seen by no trainer. The world stays exactly the world
the cartridge describes.

## Settings and the control

Three rows in the start menu's MODS entry and on this mod's own page in the
launcher, built by the host out of one registration in `options.gd`.

| Setting | Rungs | Does |
| --- | --- | --- |
| WHO | LEAD, 2 to 6 | Which party slot walks |
| ON BIKE | OFF, ON | Whether it stays out while cycling |
| ON WATER | OFF, ON | Whether it stays out while surfing |

Both movement rows are off by default: a Pokemon jogging beside a bicycle and
one walking on the sea are the two places the illusion breaks, and both are one
press away for anyone who wants them anyway.

RECALL, on `F` by default, puts it away and calls it back. A control rather than
a setting, DECLARED to the host rather than read as a keycode, so it is
rebindable in the launcher's controls card and can be carried on the on-screen
pad. It is per session: a mod's own save namespace exists, but an actor is
handed a world rather than a save, so a recall that outlives a reload is a thing
to ask the host for once anything wants it.

WHO STAYS IN ITS BALL whatever the settings say: an empty slot, an egg, a
fainted lead, and a species the cartridge has no icon for, which is every mod
species. A Pokemon nothing can draw is not one to put on the map.

## What it is waiting for

The host draws the world, and a mod cannot put a sprite in it. `mod.gd`
registers the follower through `register_world_actor`, the seam that hands a mod
one call a frame and draws what it asks for; until that lands the settings and
the control register, the follower decides where it would stand, and nothing is
drawn. The seam is asked for in the game repository. Nothing here works
around it: a mod that drew its own sprite would have to replace the whole world
renderer to do it, which is a second view of the same world and not a follower.

## Showing that it walks

`tools/follower_probe.gd` walks a route past the follower against a real
cartridge cache and prints where it stood, with no game running:

```bash
Godot --headless --path <pokerecomp> -s tools/follower_probe.gd -- \
	"user://rom_cache/<cache>"
```

It prints the icon row each party slot is drawn from, then one line per frame,
then asks the four promises above of every frame of two routes rather than of a
sample. One route walked twice digests to the same number and a different route
does not, which is what a pure function of the player's own steps means. It
exits non-zero if any of them fails.

## Layout

```
mod.gd       registers the settings, the control and the follower
options.gd   the settings and the control, named once
party.gd     which Pokemon is out, read off the party the world mirrors
trail.gd     the player's steps -> the follower's pose, as one pure function
actor.gd     the object the host drives: a frame in, a sprite out, no writes
```

`trail.gd` and `party.gd` touch no host and no node, which is what lets the
probe walk the same route the game would.
