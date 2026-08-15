#!/usr/bin/env python3
"""Numbers `tools/foliage.gd`'s two strips and reflows them into sheets.

The strips come out one slot per drawing in a single row, which is the layout
the renderer wants and not the layout a reader wants: eighteen drawings in a row
is 4320 pixels, and on any screen that fits it the labels are gone. This cuts
the row into bands of a few columns, puts the same number under the same drawing
in both sheets, and says what each one is.

The number is the whole point, as it is on the survey sheet: an answer is
"3 is too dark", never a description of which bush was meant.

    foliage_sheet.py <foliage dir> [more dirs ...] [--columns N] [--slots a,b,c]

Reads `foliage.json` and writes `foliage_2d_sheet.png` and
`foliage_3d_sheet.png` beside it.

GIVEN MORE THAN ONE DIRECTORY it writes `foliage_compare.png` instead: the
cartridge's own drawing on the top row and each directory's render under it,
one row per colour style, the same drawing down each column. That is the form
a question about colour has to take, since every one of these is defensible on
its own and only the comparison decides. Needs Pillow.
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


BAR = 30


def compare(dirs, slots_wanted):
    """One drawing down each column, the art on top and a style per row."""
    first = json.loads((dirs[0] / "foliage.json").read_text())
    width = first["slot_pixels"]
    height = first["sheet_height"]
    slots = first["slots"]
    picked = slots_wanted or list(range(len(slots)))
    rows = [("the cartridge's own drawing",
             Image.open(dirs[0] / "foliage_2d.png").convert("RGB"))]
    for at in dirs:
        manifest = json.loads((at / "foliage.json").read_text())
        # The directory's own name is the caption, so the comparison needs no
        # table of what is being compared and cannot go stale when one wins.
        rows.append((manifest.get("style", at.name.upper()),
                     Image.open(at / "foliage_3d.png").convert("RGB")))
    band = height + BAR
    out = Image.new("RGB", (len(picked) * width, len(rows) * band + BAR), BACK)
    g = ImageDraw.Draw(out)
    face = font(14)
    small = font(12)
    number = font(19)
    for row, (title, strip) in enumerate(rows):
        y = row * band
        g.text((PAD, y + 8), title, font=face, fill=INK)
        for column, at in enumerate(picked):
            x = column * width
            out.paste(strip.crop((at * width, 0, (at + 1) * width, height)),
                      (x, y + BAR))
            g.line([(x, y), (x, y + band)], fill=RULE)
    for column, at in enumerate(picked):
        slot = slots[at]
        x = column * width
        g.text((x + PAD, len(rows) * band + 4), str(at), font=number, fill=INK)
        g.text((x + PAD + 26, len(rows) * band + 8),
               "ts%d  %s" % (slot["tileset"], slot["class"]), font=small, fill=DIM)
    return out


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    dirs = []
    columns = COLUMNS
    picked = []
    rest = argv[1:]
    while rest:
        word = rest.pop(0)
        if word == "--columns":
            columns = int(rest.pop(0))
        elif word == "--slots":
            picked = [int(n) for n in rest.pop(0).split(",")]
        elif word.isdigit():
            # A bare number is a column count and never a directory, which is
            # what this took before the flags existed.
            columns = int(word)
        else:
            dirs.append(pathlib.Path(word))
    if len(dirs) > 1:
        out = dirs[0] / "foliage_compare.png"
        compare(dirs, picked).save(out)
        print(out)
        return 0
    here = dirs[0]
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
