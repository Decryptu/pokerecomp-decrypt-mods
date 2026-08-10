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
| `ledge` | a jumping ledge or a low lip drawn from ABOVE | a box 8px tall wearing its art on top |
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

    ts{number} <tile> <word> <confidence> <what you think it is, in words>

`<word>` is from the table below. `<confidence>` is `sure`, `likely` or
`unsure`. Anything not `sure` goes in front of a human with your words already
filled in, so write the words for a person who is looking at the same picture:
say what the thing is and how it SITS in a real world, tall like a wall or low
and flat like a table.

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
they are the authority: where one of these covers a tile, copy its meaning
rather than second-guessing it.

{lines}
"""


def read_answers(directory):
    out = {}
    for path in sorted(directory.glob("answers*.txt")):
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
