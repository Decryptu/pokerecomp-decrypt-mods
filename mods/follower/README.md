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

## Petting it

Turn to face it and press A. It looks back at you, wears the cartridge's own
heart for a second and cries in its own voice.

The turn is the whole trick, and it is the cartridge's. A follower stands on a
cell the player can always walk into, so a second press in that direction would
step onto it; the first press only turns, spending four frames and a facing and
nothing else, which is what leaves the pair facing each other at all.

That branch is the INPUT path's alone. `applymovement` never reaches it, so a
scripted walk turns nothing and a follower driven by a script would never get
that frame.

The press reaches this mod only after the world had no answer of its own for
that cell: no object, no background event, no tile branch. So petting can never
shadow a sign, an NPC or a ledge, and it is not a setting, because it costs a
player nothing they did not turn around to do.

Nothing here is drawn or played by the mod. The heart is a POSE, asked for while
it should be up and drawn by the host two rows above the sprite exactly as
`SpawnEmote` puts one over an NPC; the cry is an EDGE, asked for once through
the actor's outbox and played by the host through the same player the Pokedex's
CRY button uses. A mod that composed either would be shipping art and audio, and
this repository ships none.

## Finding what is hidden

FINDS ITEMS, off by default. On, the follower picks up a hidden item it walks
over, and reaches ONE cardinal step into a cell it could not have walked into,
which is the item under a rock, inside a wall or across a ledge. A hidden item
on open floor beside it is left alone: the follower can walk over that one, and
reaching a cell out for it would empty a route from a distance.

It is off because the cartridge hides them to be looked for, and a Pokemon
quietly clearing every route is a different game from the one on the box.

The mod names a cell and never takes anything. Taking a hidden item writes the
bag, the site's event flag and the save, and runs its own `verbosegiveitem`
with the FOUND text, the fanfare and the pack-full branch: all of it the host's,
asked for the way a visible-encounter provider names the entry the host starts a
battle from. So the item, the text and the receipt are the cartridge's, and a
full pack refuses exactly as it refuses the player.

A cell the world refused is not asked for again until the map changes, which is
what keeps a full pack from being asked to hold one more item on every frame the
follower stands there. A cell it accepted answers `taken` forever after, so it
could not be asked for twice anyway.

## Settings and the control

Five rows in the start menu's MODS entry and on this mod's own page in the
launcher, built by the host out of one registration in `options.gd`.

| Setting | Rungs | Does |
| --- | --- | --- |
| WHO | LEAD, 2 to 6 | Which party slot walks |
| ON BIKE | OFF, ON | Whether it stays out while cycling |
| ON WATER | OFF, ON | Whether it stays out while surfing |
| FINDS ITEMS | OFF, ON | Whether it picks up hidden items it reaches |
| FOLLOWER | RECALL | Puts it away, and the next press calls it back |

Opening a healthy Pokemon's own party menu adds FOLLOW. Choosing it updates WHO
and closes the menu; opening that member again says FOLLOWING. Eggs get no row,
and neither does the battle party menu, because changing a world actor in the
middle of a turn is not a battle action.

Both movement rows are off by default: a Pokemon jogging beside a bicycle and
one walking on the sea are the two places the illusion breaks, and both are one
press away for anyone who wants them anyway.

RECALL is both, and deliberately. On `F` by default it is a control, DECLARED to
the host rather than read as a keycode, so it is rebindable in the launcher's
controls card and can be carried on the on-screen pad. The FOLLOWER row above is
the same press with no binding at all, because a control has to be bound to
something before it exists and the player who most needs to put a follower away
is the one on a pad, on a phone, or holding a key that no longer reaches. Both
paths toggle the one state, so the two can never disagree. It is per session: a mod's own save namespace exists, but an actor is
handed a world rather than a save, so a recall that outlives a reload is a thing
to ask the host for once anything wants it.

WHO STAYS IN ITS BALL whatever the settings say: an empty slot, an egg, a
fainted Pokemon, and a species the cartridge has no icon for, which is every mod
species. A Pokemon nothing can draw is not one to put on the map.

## How it is drawn

The host draws the world, and this mod draws nothing. It registers a world
ACTOR: `register_world_actor` hands the host an object it drives one frame at a
time, and each frame the follower answers with one sprite naming the cartridge's
own icon row for that species and where to put it, in walk cells. The host
resolves the strip, the palette, the time of day and the icon's own two frames,
and sorts it into the object pass by the row it stands on, so a follower a cell
below an NPC is drawn over it. No pixel is composed here and no art ships.

An actor's sprite is presentation, which is what lets it exist at all: world
state is the one thing a mod must not write. The three optional halves of that
contract are all here: `interact` for the press, a sprite entry's `emote` for
the heart, and `take_requests` for the cry. Picking an item up is not one of
them, and could not be: it is a request to the host and not something an actor
does.

The 3D view takes the same resolved actor through `set_actors` and stands it up
as a card with its own shadow. Pressing `V` swaps views without losing it.

## Seeing it, and showing that it walks

`tools/follower_shot.gd` photographs it on a real map through the game's own
world screen: a save with a party is injected, the player is walked, and the
picture is whatever the host drew. Rendering needs a display, and mods load in a
tool run only when they are asked for:

```bash
Godot --path <pokerecomp> --mods -s tools/follower_shot.gd -- \
	crystal 26 1 <out.png> [species] [steps] [view] [pet]
```

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
mod.gd       registers the settings, party row, control and follower
options.gd   the settings and the control, named once
party.gd     which Pokemon is out, read off the party the world mirrors
trail.gd     the player's steps -> the follower's pose, as one pure function
finder.gd    where it stands -> the hidden item it reaches, as another one
actor.gd     the object the host drives: a frame in, a sprite out, no writes
```

`trail.gd`, `party.gd` and `finder.gd` touch no host and no node, which is what
lets the probe walk the same route the game would and ask the reach rule of a
map it made up.
