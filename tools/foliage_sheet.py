#!/usr/bin/env python3
"""Numbers `tools/foliage.gd`'s two strips and reflows them into sheets.

The strips come out one slot per drawing in a single row, which is the layout
the renderer wants and not the layout a reader wants: eighteen drawings in a row
is 4320 pixels, and on any screen that fits it the labels are gone. This cuts
the row into bands of a few columns, puts the same number under the same drawing
in both sheets, and says what each one is.

The number is the whole point, as it is on the survey sheet: an answer is
"3 is too dark", never a description of which bush was meant.

    foliage_sheet.py <foliage dir> [columns]

Reads `foliage.json` and writes `foliage_2d_sheet.png` and
`foliage_3d_sheet.png` beside it. Needs Pillow.
"""

import json
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

COLUMNS = 6
LABEL = 52
PAD = 6
BACK = (24, 24, 28)
INK = (236, 236, 240)
DIM = (150, 150, 160)
RULE = (52, 52, 62)


def font(px):
    for path in ("/System/Library/Fonts/Supplemental/Arial.ttf",
                 "/System/Library/Fonts/Helvetica.ttc",
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(path, px)
        except OSError:
            continue
    return ImageFont.load_default()


def caption(slot):
    """What a drawing is, in as few words as fit under it."""
    ids = ".".join(str(n) for n in slot["ids"])
    if len(ids) > 34:
        ids = ids[:33] + "…"
    return ("ts%d  %s" % (slot["tileset"], slot["class"]),
            "%d tiles, %d maps" % (slot["tiles"], slot["maps"]),
            ids)


def sheet(strip, manifest, columns, title):
    slots = manifest["slots"]
    width = manifest["slot_pixels"]
    height = manifest["sheet_height"]
    rows = (len(slots) + columns - 1) // columns
    band = height + LABEL
    out = Image.new("RGB", (columns * width, rows * band + LABEL), BACK)
    g = ImageDraw.Draw(out)
    number = font(19)
    face = font(14)
    small = font(12)
    for index, slot in enumerate(slots):
        column = index % columns
        row = index // columns
        x = column * width
        y = row * band
        out.paste(strip.crop((index * width, 0, (index + 1) * width, height)), (x, y))
        g.line([(x, y), (x, y + band)], fill=RULE)
        head, count, ids = caption(slot)
        g.text((x + PAD, y + height + 3), str(index), font=number, fill=INK)
        g.text((x + PAD + 28, y + height + 6), head, font=face, fill=INK)
        g.text((x + PAD + 28, y + height + 23), count, font=small, fill=DIM)
        g.text((x + PAD + 28, y + height + 36), ids, font=small, fill=DIM)
    g.text((PAD, rows * band + 12), title, font=face, fill=INK)
    g.text((columns * width - PAD, rows * band + 12),
           "same number is the same drawing in both sheets", font=small,
           anchor="ra", fill=DIM)
    return out


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    here = pathlib.Path(argv[1])
    columns = int(argv[2]) if len(argv) > 2 else COLUMNS
    manifest = json.loads((here / "foliage.json").read_text())
    for kind, title in (
        ("2d", "the cartridge's own drawing"),
        ("3d", "what the mod turns out of it, at %d degrees of tilt and %d of turn"
         % (round(manifest["pitch"]), round(manifest["bearing"]))),
    ):
        strip = Image.open(here / ("foliage_%s.png" % kind)).convert("RGB")
        out = here / ("foliage_%s_sheet.png" % kind)
        sheet(strip, manifest, columns, title).save(out)
        print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
