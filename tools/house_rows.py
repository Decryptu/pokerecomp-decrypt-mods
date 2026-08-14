#!/usr/bin/env python3
"""A house drawing's rows, numbered, with the word each row is painted.

WHICH ROWS ARE THE EAVE is the one thing about a painting that a person has to
answer, and a question that does not say WHICH PIXELS it means cannot be
answered. So this crops the courses around the top of the wall, blows them up,
numbers every row and prints the word the painting gives it. Five drawings were
settled in one round from this picture and drawing 11's own crop beside it.

  house_rows.py <painted.json> <art dir> <id> <out.png> [first last] [scale]

With no row range it takes the ten courses above the topmost WALL row and three
below it, and rules that row in red. Give a range for a drawing whose wall
reaches the top of the page, which is what the Radio Tower does.

Needs Pillow.
"""

import json
import sys

from PIL import Image, ImageDraw, ImageFont

GUTTER = 150
PAD = 10
HEAD = 30
# The page's own colours, so a word means the same thing here as it does there.
WORDS = {"W": (0x4D, 0x94, 0xFF), "R": (0xFF, 0x8C, 0x1A),
         "F": (0xC8, 0x62, 0xFF), ".": (0x9A, 0xA0, 0xAD)}


def font(px):
    for path in ("/System/Library/Fonts/Supplemental/Arial.ttf",
                 "/System/Library/Fonts/Helvetica.ttc",
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(path, px)
        except OSError:
            continue
    return ImageFont.load_default()


def main():
    if len(sys.argv) < 5:
        print(__doc__)
        return 1
    book = json.load(open(sys.argv[1]))
    art_dir = sys.argv[2].rstrip("/")
    ident = int(sys.argv[3])
    out_path = sys.argv[4]
    rest = sys.argv[5:]
    span = [int(rest[0]), int(rest[1])] if len(rest) >= 2 else None
    scale = int(rest[-1]) if len(rest) in (1, 3) else 14

    house = next((h for h in book["houses"] if h["id"] == ident), None)
    if house is None:
        print("no drawing %d" % ident)
        return 1
    paint = house["paint"]
    art = Image.open("%s/house_%03d.png" % (art_dir, ident)).convert("RGB")
    top = min((y for y in range(len(paint)) if "W" in paint[y]), default=0)
    first, last = span if span else (max(0, top - 10), min(len(paint) - 1, top + 2))

    body = art.crop((0, first, art.width, last + 1)).resize(
        (art.width * scale, (last + 1 - first) * scale), Image.NEAREST)
    out = Image.new("RGB", (GUTTER + body.width + PAD * 2,
                            HEAD + body.height + PAD * 2 + 26), (14, 16, 20))
    out.paste(body, (GUTTER + PAD, HEAD + PAD))
    pen = ImageDraw.Draw(out)
    pen.text((PAD, 8), "drawing %d, tileset %d: rows %d to %d"
             % (ident, house["tileset"], first, last), font=font(17),
             fill=(235, 238, 245))
    small = font(13)
    for row in range(first, last + 1):
        y = HEAD + PAD + (row - first) * scale
        if scale < 10 and row % 2:
            continue
        words = sorted(set(paint[row]))
        ink = WORDS[words[0]] if len(words) == 1 else (235, 238, 245)
        pen.text((PAD, y + max(scale // 2 - 8, -6)),
                 "row %3d  %s" % (row, "".join(words)), font=small, fill=ink)
        pen.line([(GUTTER + PAD, y), (GUTTER + PAD + body.width, y)],
                 fill=(60, 66, 78), width=1)
    if first <= top <= last:
        y = HEAD + PAD + (top - first) * scale
        pen.line([(GUTTER + PAD, y), (GUTTER + PAD + body.width, y)],
                 fill=(255, 80, 80), width=3)
        pen.text((PAD, HEAD + PAD + body.height + 6),
                 "red line: the first row the painting calls WALL (row %d)" % top,
                 font=small, fill=(235, 238, 245))
    out.save(out_path)
    print(out_path)


if __name__ == "__main__":
    sys.exit(main())
