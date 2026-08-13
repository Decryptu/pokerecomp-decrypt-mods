#!/usr/bin/env python3
"""Builds the brief an agent reads a whole tileset from.

The human survey is expensive and the human is the only authority on what a
drawing IS, so it is spent on the tiles nobody can resolve. Everything else is
a picture-reading job, and the picture is the same one that made the human
rounds answerable: the tile ringed in red where the cartridge actually uses it.

So this writes, per tileset, a brief listing every tile the tileset places with
its picture, how often it is found in a walkable cell and in a blocked one, and
what the profile already pins it to. The agent answers in one line per tile.

The reviewer's own answers for a tileset are pasted in as EXAMPLES where there
are any: they are the calibration, in their own words, and they are what tells
an agent what a "separator wall in a building" or a "jumping ledge" looks like
in this game.

    tools/survey_context.gd <cache> <ts|all> <dir> all   # renders and lists
    tools/survey_pass.py <dir> [tileset...] [blind]      # writes brief_ts<n>.md

`blind` withholds the examples, which is only for measuring a pass against a
tileset the reviewer has already answered: agreement means nothing if the answer
key was in the brief.

Every answer file in the survey directory is calibration, whatever it is called:
`answers*.txt` from the human rounds and `verdict*.txt` from the reviewer's
verdicts on what a pass could not settle. They are the same shape and they are
read the same way.
"""

import json
import pathlib
import sys

# The vocabulary an agent answers in. Geometric, not semantic: what matters is
# which surface the drawing depicts and how it sits, because that is what the
# mesher builds. A human is never handed this list; an agent is, because a class
# is exactly what its answer has to become.
CLASSES = """
| word | means | geometry |
| --- | --- | --- |
| `floor` | ground the player walks on, or would if it were not fenced off | one flat quad at height 0 |
| `water` | water | one flat quad, recessed 8px |
| `void` | nothing: past the edge of a room, out of bounds | flat, black |
| `wall` | stands up and is drawn face-on. An interior wall, a rock face, a fence, a tree canopy, a counter front | a box, the drawing folded upright 8px band at a time |
| `facade` | the face-on wall of a BUILDING seen from outside: bricks, planks, windows in them, a door, a shop sign painted on | folded upright, and the building pass decides how tall from the rows above and below it |
| `roof_flat` | a roof seen from above, the flat part, including its straight edges and corners | lies flat on top of the facade under it |
| `roof_edge` | a sloped roof tile one step down from the flat part | flat, one 8px band lower |
| `roof_corner` | a sloped roof tile at the very corner of the building, two steps down | flat, two 8px bands lower |
| `ledge` | a low lip drawn from ABOVE, jumping ledge or not | a box 8px tall wearing its art on top. Where the collision says the lip can be hopped, the mesher builds a wedge there instead and this word costs nothing |
| `top` | a raised flat surface seen from above: a counter top, a table top, a bed | a box wearing its art on top |
| `stand` | a thing with its own outline standing on the ground: a post, a sign, a bush, a sapling, a tombstone, a statue | the drawing's own silhouette, cut out and stood up |
| `lie` | a low thing with its own outline: a flower bed, a planter, a basket | the silhouette, lying at the height of one cell |
| `on_top_of_furniture` | an object sitting ON a table, desk or counter: a radio, a television, a computer, a book | stands up like a wall, but starting at the top of whatever is in front of it rather than at the floor |
| `stairs` | a stair or a ladder, anything walked up or down | flat for now, and recorded as stairs so it can be built as a ramp later. Use it rather than `floor` |
| `unsure` | you cannot tell, or it is two things at once | goes to the human |
"""

BRIEF = """# Tileset {number}: name every tile

{count} tiles. For each one there is a picture, `{sample}`, showing most of a
Game Boy screen of a REAL map with that tile ringed in red where the cartridge
places it. Only the ringed tile is being asked about; the rest of the picture is
there because an 8x8 tile on its own is unreadable, which was proved three times
over on tiles that turned out to be a table corner and a book.

## What to answer

One line per tile, in this exact shape, into `{out}`:

    ts{number} <tile> <word> <confidence> <the description>

`<word>` is from the table below. `<confidence>` is `sure`, `likely` or
`unsure`.

### The description is the deliverable, not the leftover

The word is a class the mesher takes. The description is what everything AFTER
this pass reads: the next agent deciding a height, the shape of a cutout, or
whether a pin was wrong. So write it for an agent to act on, not for a person to
enjoy. Four things, in this order, in one plain sentence or two:

1. **Name the object.** Not "a brown thing", but "a wooden desk", "a rock face",
   "the lower-right quarter of a doorway".
2. **Say which surface the drawing depicts.** Generation II packs several
   facings into one flat image: seen from ABOVE, seen FACE-ON, or its own
   silhouette cut out. This is the question the geometry turns on.
3. **Say how it sits in a real world.** Tall like a wall, low and flat like a
   table top, lying on the floor, recessed. Give its extent when the picture
   shows it: "the desk is 4 tiles wide and 2 tall", "two tiles high, then flat
   ground behind".
4. **Say what it stands on.** The floor, a table top, a roof below it, the top
   of a wall, the water. `on_top_of_furniture` is not the only class with
   something under it, and a thing whose base is unknown builds from the ground.

### Answer from the pictures you were given, and from nothing else

Every claim in your file has to be traceable to a crop listed below. Do not use
recalled knowledge of this game: not map names, not tile numbering, not a
disassembly, not what a place is "known" to contain. A previous run reported
reading tileset graphics and metatile binaries that do not exist on this
machine, and when it was re-run under this rule the two passes agreed on 39% of
their words. If a crop does not settle a tile, that tile is `unsure`; naming the
map it is on is not evidence and is not wanted.

Any answer can be checked by cropping what the red ring encloses and blowing it
up, and one that cannot be seen in the ring is not an answer.

{classes}

## How to read one

1. Look at the whole picture first and work out what the PLACE is: a town, a
   shop, a cave, a route.
2. Find the red ring. What is the ring drawn around, as part of that place?
3. Ask which surface it depicts. Generation II draws roofs and floors from
   ABOVE and walls FACE-ON in the same picture, so the question is never "what
   colour is it" but "if this were real, which way is this surface facing".
4. The collision counts below are strong evidence and not proof. A tile found
   in walkable cells is almost always floor. A tile only ever found in blocked
   cells is standing up as something. A tile found in both is usually floor with
   something else in the cell beside it.

Judge the drawing, not the counts, when the two disagree, and say so in your
words.

## The tiles

{tiles}
{examples}"""

EXAMPLES = """
## The reviewer's own words, for tiles of this tileset they have already named

These are the calibration. They are a person looking at these same pictures, and
their MEANING is the authority: where one covers a tile, you do not overturn it.

Their prose is the source, not the output. Rewrite it into the four things
above, keeping every fact they state, adding what the picture shows and they did
not bother to write, and dropping nothing. Their words were written to get a
meaning across to you; yours are written for the next agent to act on.

Where one of these describes a tile you were not asked about, it still tells you
what this tileset's world is made of, so read all of them before you start.

If a line and the picture genuinely disagree, say so in your description and
mark that tile `unsure`.

{lines}
"""


def read_answers(directory):
    out = {}
    paths = sorted(directory.glob("answers*.txt")) + \
        sorted(directory.glob("verdict*.txt"))
    for path in paths:
        for line in path.read_text().splitlines():
            words = line.split()
            if len(words) >= 3 and words[0].startswith("ts") and words[1].isdigit():
                out.setdefault(int(words[0][2:]), {})[int(words[1])] = \
                    " ".join(words[2:])
    return out


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    directory = pathlib.Path(sys.argv[1])
    blind = "blind" in sys.argv[2:]
    wanted = [int(n) for n in sys.argv[2:] if n.isdigit()]
    answers = read_answers(directory.parent if directory.name == "pass" else directory)

    for path in sorted(directory.glob("pass_ts*.json")):
        sheet = json.loads(path.read_text())
        number = sheet["tileset"]
        if wanted and number not in wanted:
            continue
        rows = ["| tile | picture | placed | in walkable cells | in blocked cells | in water | pinned now |",
                "| --- | --- | --- | --- | --- | --- | --- |"]
        for tile in sorted(sheet["tiles"], key=lambda t: -t["count"]):
            rows.append("| %d | `%s` | %d | %d | %d | %d | %s |" % (
                tile["tile"], tile["file"], tile["count"], tile.get("walkable", 0),
                tile.get("blocked", 0), tile.get("water", 0),
                tile.get("pinned") or "-",
            ))
        known = {} if blind else answers.get(number, {})
        examples = ""
        if known:
            examples = EXAMPLES.format(lines="\n".join(
                "- tile %d: %s" % (tile, words) for tile, words in sorted(known.items())
            ))
        out = directory / ("brief_ts%d.md" % number)
        out.write_text(BRIEF.format(
            number=number, count=len(sheet["tiles"]),
            sample=sheet["tiles"][0]["file"], out="pass_ts%d.txt" % number,
            classes=CLASSES, tiles="\n".join(rows), examples=examples,
        ))
        print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
