#!/usr/bin/env python3
"""Rules a map's own 2D art into TILES and numbers them, so a place can be
pointed at rather than described.

`tools/map_art.gd` rings ONE rectangle, which is the form a question about a
drawing takes. This is the other half of the same need: a picture a reader can
name any tile on, so that "the roof at 21,8" and `map_art.gd`'s own ring
arguments and `shot.gd`'s own aim are all the same two numbers.

The unit is the TILE, 8 world pixels, because that is what every tool here
takes. The ruling says the other two units without needing a second picture: a
walk cell is 2 tiles and a block is 4.

  map_grid.py <art.png> <out.png> [zoom] [--origin x,y] [--title text]
      [--mark x,y[,w,h]]...

The art must be `map_art.gd` at scale 1. `--origin` is the tile the art's own
top-left corner is, which is what a cropped art needs to keep the map's
numbering. Needs Pillow.
"""

import sys

from PIL import Image, ImageDraw, ImageFont

TILE = 8
CELL = 2
BLOCK = 4
# Over pastel terrain art, so ink rather than colour, and thin enough that the
# drawing under it stays readable: the ruling is for pointing, not for looking.
RULE = (16, 16, 24, 55)
RULE_CELL = (16, 16, 24, 140)
RULE_BLOCK = (255, 64, 220, 190)
# The block rule is already magenta, so a mark in it is a mark nobody can see.
# Ringed twice for `map_art.gd`'s own reason, in the two colours left over.
MARK = ((255, 255, 255, 255), (255, 32, 32, 255))
BACK = (24, 24, 28)
INK = (236, 236, 240)
DIM = (150, 150, 160)
GUTTER = 30
PAD = 8
BAR = 26


def font(px):
    for path in ("/System/Library/Fonts/Supplemental/Arial.ttf",
                 "/System/Library/Fonts/Helvetica.ttc",
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(path, px)
        except OSError:
            continue
    return ImageFont.load_default()


def ruled(art, zoom, origin):
    """The art at `zoom` with a line on every tile edge, cell and block picked
    out. Returns the picture and the tile it starts at."""
    tiles = (art.size[0] // TILE, art.size[1] // TILE)
    step = TILE * zoom
    out = art.resize((tiles[0] * step, tiles[1] * step), Image.NEAREST).convert("RGBA")
    over = Image.new("RGBA", out.size, (0, 0, 0, 0))
    g = ImageDraw.Draw(over)
    for x in range(tiles[0] + 1):
        at = origin[0] + x
        g.line([(x * step, 0), (x * step, out.size[1])],
               fill=weight(at), width=2 if at % BLOCK == 0 else 1)
    for y in range(tiles[1] + 1):
        at = origin[1] + y
        g.line([(0, y * step), (out.size[0], y * step)],
               fill=weight(at), width=2 if at % BLOCK == 0 else 1)
    return Image.alpha_composite(out, over), tiles


def weight(at):
    if at % BLOCK == 0:
        return RULE_BLOCK
    if at % CELL == 0:
        return RULE_CELL
    return RULE


def marked(picture, zoom, origin, marks):
    """A box round each named rectangle of tiles, drawn OUTSIDE them so it
    covers none of the drawing being pointed at."""
    g = ImageDraw.Draw(picture)
    step = TILE * zoom
    for tx, ty, tw, th in marks:
        x = (tx - origin[0]) * step
        y = (ty - origin[1]) * step
        for ring, color in enumerate(MARK):
            inset = 1 + ring * 2
            g.rectangle([x - inset, y - inset,
                         x + tw * step + inset - 1, y + th * step + inset - 1],
                        outline=color, width=2)
    return picture


def numbered(picture, tiles, zoom, origin, title):
    """The ruled art in its gutters. Every tile is numbered on all four sides,
    since a reader counting in from the far edge of a large map miscounts."""
    step = TILE * zoom
    face = font(min(15, max(9, step // 2)))
    small = font(13)
    size = (picture.size[0] + GUTTER * 2, picture.size[1] + GUTTER * 2 + BAR)
    out = Image.new("RGB", size, BACK)
    out.paste(picture, (GUTTER, GUTTER), picture)
    g = ImageDraw.Draw(out)
    for x in range(tiles[0]):
        at = origin[0] + x
        mid = GUTTER + x * step + step / 2
        for row in (GUTTER - 4, GUTTER + picture.size[1] + 4):
            g.text((mid, row), str(at), font=face, anchor="md" if row < GUTTER else "ma",
                   fill=INK if at % BLOCK == 0 else DIM)
    for y in range(tiles[1]):
        at = origin[1] + y
        mid = GUTTER + y * step + step / 2
        for col in (GUTTER - 5, GUTTER + picture.size[0] + 5):
            g.text((col, mid), str(at), font=face, anchor="rm" if col < GUTTER else "lm",
                   fill=INK if at % BLOCK == 0 else DIM)
    g.text((GUTTER, size[1] - BAR + 4), title, font=small, fill=INK)
    g.text((size[0] - GUTTER, size[1] - BAR + 4),
           "x right, y down, in TILES of 8px. Line every tile, "
           "darker every walk cell (2), magenta every block (4).",
           font=small, anchor="ra", fill=DIM)
    return out


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    zoom = 4
    origin = (0, 0)
    title = argv[1]
    marks = []
    rest = argv[3:]
    while rest:
        word = rest.pop(0)
        if word == "--origin":
            origin = tuple(int(n) for n in rest.pop(0).split(","))
        elif word == "--title":
            title = rest.pop(0)
        elif word == "--mark":
            box = [int(n) for n in rest.pop(0).split(",")]
            marks.append(tuple(box + [1, 1][len(box) - 2:]))
        else:
            zoom = int(word)
    art = Image.open(argv[1])
    picture, tiles = ruled(art, zoom, origin)
    picture = marked(picture, zoom, origin, marks)
    numbered(picture, tiles, zoom, origin, title).save(argv[2])
    print(argv[2], "%dx%d tiles at zoom %d" % (tiles[0], tiles[1], zoom))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
