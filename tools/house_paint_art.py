#!/usr/bin/env python3
"""Draws a house drawing's PAINTING onto its own art, as a picture.

The painting is per PIXEL and lives in the page's JSON. Any question about a
house has to show it, or the answer is about a picture nobody can see: the
geometry is built from these four words and from nothing else, so a render shown
without them cannot be argued with.

The hatches, the colours and the faint wash are `house_page.py`'s own, so what
comes out here is what the painting looked like under the hand that made it.

  house_paint_art.py <painted.json> <art dir> <id> <out.png> [scale]

Needs Pillow.
"""

import json
import sys

from PIL import Image, ImageDraw, ImageFont

# The page's own vocabulary, colour and ruling. Direction of ruling is what
# names a word; the wash only makes it a field rather than a set of lines.
PAINTS = [
    ("W", "wall (looking AT it)", (0x4D, 0x94, 0xFF), "up"),
    ("R", "roof (looking DOWN onto it)", (0xFF, 0x8C, 0x1A), "down"),
    ("F", "roof, from the front", (0xC8, 0x62, 0xFF), "cross"),
    (".", "not the house", (0x9A, 0xA0, 0xAD), "dot"),
]
TINT = 0.11
# In SCREEN pixels, so the ruling keeps its weight whatever the scale is.
HATCH = 11
GAP = 24
BAR = 34
PAD = 12


def hatch_tile(color, kind):
    """One repeating tile of a word's ruling, HATCH screen pixels square."""
    tile = Image.new("RGBA", (HATCH, HATCH), (0, 0, 0, 0))
    g = ImageDraw.Draw(tile)
    s = HATCH
    if kind == "dot":
        g.ellipse([s / 2 - 1.6, s / 2 - 1.6, s / 2 + 1.6, s / 2 + 1.6],
                  fill=color + (217,))
    ink = color + (255,)
    if kind in ("up", "cross"):
        for a, b in (((-1, 1), (1, -1)), ((-1, s + 1), (s + 1, -1)),
                     ((s - 1, s + 1), (s + 1, s - 1))):
            g.line([a, b], fill=ink, width=2)
    if kind in ("down", "cross"):
        for a, b in (((-1, s - 1), (1, s + 1)), ((-1, -1), (s + 1, s + 1)),
                     ((s - 1, -1), (s + 1, 1))):
            g.line([a, b], fill=ink, width=2)
    return tile


def tiled(tile, size):
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    for y in range(0, size[1], HATCH):
        for x in range(0, size[0], HATCH):
            out.paste(tile, (x, y), tile)
    return out


def font(px):
    for path in ("/System/Library/Fonts/Supplemental/Arial.ttf",
                 "/System/Library/Fonts/Helvetica.ttc",
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(path, px)
        except OSError:
            continue
    return ImageFont.load_default()


def painted(art, paint, scale):
    """The art at `scale`, with the painting washed and ruled over it."""
    w, h = art.size
    out = art.resize((w * scale, h * scale), Image.NEAREST).convert("RGBA")
    size = out.size
    for key, _label, color, kind in PAINTS:
        mask = Image.new("L", (w, h), 0)
        px = mask.load()
        for y in range(h):
            row = paint[y] if y < len(paint) else ""
            for x in range(w):
                if x < len(row) and row[x] == key:
                    px[x, y] = 255
        if not mask.getbbox():
            continue
        mask = mask.resize(size, Image.NEAREST)
        wash = Image.new("RGBA", size, color + (int(TINT * 255),))
        out = Image.composite(Image.alpha_composite(out, wash), out, mask)
        rule = tiled(hatch_tile(color, kind), size)
        rule.putalpha(Image.composite(rule.getchannel("A"),
                                      Image.new("L", size, 0), mask))
        out = Image.alpha_composite(out, rule)
    # The boundary between two words is drawn, rather than left to the eye to
    # find between two hatches.
    edge = ImageDraw.Draw(out)
    for y in range(h):
        row = paint[y] if y < len(paint) else ""
        for x in range(w):
            here = row[x] if x < len(row) else "."
            below = paint[y + 1][x] if y + 1 < len(paint) and x < len(paint[y + 1]) else here
            right = row[x + 1] if x + 1 < len(row) else here
            if below != here:
                edge.line([(x * scale, (y + 1) * scale - 1),
                           ((x + 1) * scale - 1, (y + 1) * scale - 1)],
                          fill=(255, 255, 255, 230), width=2)
            if right != here:
                edge.line([((x + 1) * scale - 1, y * scale),
                           ((x + 1) * scale - 1, (y + 1) * scale - 1)],
                          fill=(255, 255, 255, 230), width=2)
    return out


def main():
    if len(sys.argv) < 5:
        print(__doc__)
        return 1
    book = json.load(open(sys.argv[1]))
    art_dir = sys.argv[2].rstrip("/")
    ident = int(sys.argv[3])
    out_path = sys.argv[4]
    scale = int(sys.argv[5]) if len(sys.argv) > 5 else 8

    house = next((h for h in book["houses"] if h["id"] == ident), None)
    if house is None:
        print("no drawing %d" % ident)
        return 1
    art = Image.open("%s/house_%03d.png" % (art_dir, ident)).convert("RGBA")
    left = art.resize((art.width * scale, art.height * scale),
                      Image.NEAREST).convert("RGBA")
    right = painted(art, house["paint"], scale)

    face = font(15)
    small = font(13)
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    legend = sum(26 + probe.textlength(p[1], font=small) + 20 for p in PAINTS)
    body = left.width + GAP + right.width
    width = int(max(body, legend)) + PAD * 2
    sheet = Image.new("RGBA", (width, left.height + BAR * 2 + PAD * 2),
                      (22, 22, 26, 255))
    sheet.paste(left, (PAD, PAD))
    sheet.paste(right, (PAD + left.width + GAP, PAD))
    g = ImageDraw.Draw(sheet)
    y = PAD + left.height + 10
    g.text((PAD, y), "drawing %d, tileset %d, %d placements, painted per pixel"
           % (ident, house["tileset"], house["placements"]), font=face,
           fill=(232, 232, 238, 255))
    y += BAR - 6
    x = PAD
    for _key, label, color, kind in PAINTS:
        chip = Image.new("RGBA", (18, 18), (27, 27, 34, 255))
        chip = Image.alpha_composite(chip, tiled(hatch_tile(color, kind), (18, 18)))
        sheet.paste(chip, (int(x), y))
        g.rectangle([x, y, x + 17, y + 17], outline=color + (255,))
        g.text((x + 24, y + 2), label, font=small, fill=(200, 200, 216, 255))
        x += 26 + probe.textlength(label, font=small) + 20
    sheet.convert("RGB").save(out_path)
    print(out_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
