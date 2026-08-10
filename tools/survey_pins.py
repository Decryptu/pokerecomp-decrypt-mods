#!/usr/bin/env python3
"""Turns what a reviewer said about blocks into what the profile pins: tiles.

A reviewer answers about BLOCKS, because a block is what a drawing looks like.
`shape/profile.gd` pins TILES, because a tile id is what a shape resolves for.
The step between them is not a parse of the sentence, it is a set problem, and
the labels solve it by accident of being many: the four tiles of a bollard are
exactly the tiles that appear in blocks called bollard and in no other, and 22
such blocks pin them beyond argument.

So a tile is claimed by a word when EVERY labelled block it appears in used that
word. A tile that appears in one bollard block and one bush block is claimed by
neither and is left alone, which is the right answer: it is probably ground.

Ambiguity between two words that always travel together (a bush and the cuttable
tree share their blocks) is broken by exclusivity: whichever word has blocks the
other does not gets the tiles that only appear there.

    tools/survey_pins.py <labels.txt> <survey dir> [tileset ...]

Prints the proposal and writes `pins_ts<n>.png`, a picture of every tile each
word claimed, which is the thing to put back in front of the reviewer. Nothing
is written to the mod: a pin is still a human's answer.
"""

import collections
import json
import pathlib
import re
import sys

from PIL import Image, ImageDraw

# What a reviewer's words are taken to mean. The left side is the shape class a
# pin carries; the right side is what people actually type. Order matters only
# in that a longer phrase should be listed before a word it contains.
WORDS = {
    "post": ["bollard", "wooden pole", "wood pole", "wooden poll", "wood poll"],
    "sign": ["sign"],
    "cut tree": ["tree you can cut"],
    "bush": ["bush"],
    "tree": ["big tree", "tree"],
    "flowers": ["flower bed", "flower pot", "flower"],
    "plant": ["plant in a pot", "potted plant"],
    "water": ["water", "watter"],
    "ledge": ["ledge"],
    "roof": ["roof"],
    "cave": ["cave"],
    "tombstone": ["tombstone"],
    "bookshelf": ["librar", "bookshelf", "bookcase"],
    "counter": ["kitchen counter", "counter"],
    "table": ["table", "desk"],
    "stool": ["stool"],
    "statue": ["statue"],
    "window": ["window"],
    "grass": ["grass"],
    "floor": ["floor", "ground"],
}
# Words that describe where a thing is rather than what it is, and that no tile
# should ever be claimed by.
PLACES = ("floor", "ground", "grass")

# The permissions a claim has to be consistent with. Collision is the one fact
# about a tile the reviewer did not have to supply and cannot be wrong about, so
# it is what throws out a claim the words alone let through: a bollard standing
# in a walkable cell is the path beside the bollard, and a rock the reviewer
# mentioned while describing a lake is not water.
LAND, WATER, WALL = 0x00, 0x01, 0x0F
SOLID = ("post", "sign", "bush", "tree", "cut tree", "roof", "cave", "bookshelf",
         "tombstone", "statue", "window", "counter", "table", "stool", "plant")

TILE = 8
ZOOM = 7


def read_labels(path):
    out = collections.defaultdict(dict)
    for line in pathlib.Path(path).read_text().splitlines():
        found = re.match(r"ts(\d+) #(\d+) (.*)", line.strip())
        if found:
            out[int(found.group(1))][int(found.group(2))] = found.group(3).lower()
    return out


def words_in(text):
    return {name for name, keys in WORDS.items() if any(k in text for k in keys)}


def claim(said, tiles, permissions):
    """tile id -> the one word every block it appears in agreed on."""
    seen = collections.defaultdict(list)
    stands_on = collections.defaultdict(set)
    for block, text in said.items():
        words = words_in(text)
        for at, tile in enumerate(tiles.get(block, [])):
            # Four tiles to a cell, four cells to a block: the tile's row and
            # column halved is the cell it stands in.
            stands_on[tile].add(permissions[block][(at // 8) * 2 + (at % 4) // 2])
        for tile in set(tiles.get(block, [])):
            seen[tile].append(words)

    # How many labelled blocks each word covers: a word covering fewer blocks is
    # the more specific claim when two of them agree on a tile.
    spread = collections.Counter()
    for text in said.values():
        for name in words_in(text):
            spread[name] += 1

    out = {}
    for tile, votes in seen.items():
        agreed = set.intersection(*votes) if votes else set()
        agreed -= set(PLACES)
        where = stands_on[tile]
        agreed = {name for name in agreed
                  if not (name in SOLID and where == {LAND})
                  and not (name == "water" and WATER not in where)}
        if not agreed:
            continue
        out[tile] = min(agreed, key=lambda name: spread[name])
    return out


def picture(directory, number, groups, tiles_of, slot_of, grid, size):
    """Every claimed tile drawn under the word that claimed it."""
    art = Image.open(directory / ("ts%d_2d.png" % number)).convert("RGB")

    def tile_image(tile):
        for block, tiles in tiles_of.items():
            if tile in tiles:
                at = tiles.index(tile)
                slot = slot_of[block]
                left = (slot % grid) * size + (at % 4) * TILE
                top = (slot // grid) * size + (at // 4) * TILE
                return art.crop((left, top, left + TILE, top + TILE))
        return Image.new("RGB", (TILE, TILE))

    rows = sorted(groups.items())
    step = TILE * ZOOM + 10
    width = max(len(v) for _, v in rows) * step + 190
    out = Image.new("RGB", (width, len(rows) * (step + 14) + 16), (24, 24, 28))
    pen = ImageDraw.Draw(out)
    for row, (name, claimed) in enumerate(rows):
        y = 16 + row * (step + 14)
        pen.text((10, y + step // 2 - 6), name, fill=(236, 236, 240))
        for column, tile in enumerate(sorted(claimed)):
            x = 180 + column * step
            out.paste(tile_image(tile).resize((TILE * ZOOM,) * 2, Image.NEAREST), (x, y))
            pen.text((x, y + step - 6), str(tile), fill=(150, 150, 160))
    path = directory / ("pins_ts%d.png" % number)
    out.save(path)
    return path


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    labels = read_labels(sys.argv[1])
    directory = pathlib.Path(sys.argv[2])
    numbers = [int(n) for n in sys.argv[3:]] or sorted(labels)
    for number in numbers:
        meta = json.loads((directory / ("ts%d.json" % number)).read_text())
        tiles_of = {b["block"]: b["tiles"] for b in meta["blocks"]}
        slot_of = {b["block"]: b["slot"] for b in meta["blocks"]}
        where_of = {b["block"]: b["permissions"] for b in meta["blocks"]}
        said = {b: t for b, t in labels[number].items() if b in tiles_of}
        claimed = claim(said, tiles_of, where_of)
        groups = collections.defaultdict(list)
        for tile, name in claimed.items():
            groups[name].append(tile)
        print("tileset %d: %d blocks read, %d tiles claimed" % (
            number, len(said), len(claimed)))
        for name, tiles in sorted(groups.items()):
            print("  %-10s %s" % (name, sorted(tiles)))
        print(" ", picture(directory, number, groups, tiles_of, slot_of,
                           meta["columns"], meta["block_pixels"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
