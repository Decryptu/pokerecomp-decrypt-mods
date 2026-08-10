#!/usr/bin/env python3
"""Pairs one tileset's survey renders into the sheet a reviewer marks up.

`tools/survey.gd` emits, per tileset, the cartridge's own drawing of every block
it places, the same grid meshed and shot, and what the mod resolved each block
to. This puts them side by side under one number.

The number is the whole point. A reviewer reads down the sheet and writes a
list, `12 tree, 13 sign, 27 flowers`, and that list is what becomes pins in
`mods/voxel3d/shape/profile.gd`. So the layout is built around being able to
name a block in a glance and never having to describe it in words.

    tools/survey_sheet.py <survey dir> [tileset ...]
"""

import json
import pathlib
import sys

from PIL import Image, ImageDraw

# The 2D art is 32px a block and is shown at this multiple, which lands it at
# the same size as the 3D crop beside it.
ART_ZOOM = 3
PAD = 8
LABEL = 22
COLUMNS = 6
BACK = (24, 24, 28)
INK = (236, 236, 240)
DIM = (150, 150, 160)


def verdict(block):
    """The mod's own answer for one block, in as few words as fit."""
    classes = sorted(block["classes"].items(), key=lambda kv: -kv[1])
    named = " ".join("%s%d" % (name, count) for name, count in classes)
    heights = sorted({int(h) for h in block["heights"]})
    return "%s  h%s" % (named, "/".join(str(h) for h in heights))


def sheet(directory, number):
    meta = json.loads((directory / ("ts%d.json" % number)).read_text())
    art = Image.open(directory / ("ts%d_2d.png" % number)).convert("RGB")
    shot = Image.open(directory / ("ts%d_3d.png" % number)).convert("RGB")
    blocks = meta["blocks"]
    grid = meta["columns"]
    size = meta["block_pixels"]
    crop_w, crop_h = meta["crop"]
    ground_x, ground_y = meta["crop_ground"]

    art_w, art_h = size * ART_ZOOM, size * ART_ZOOM
    cell_w = art_w + PAD + crop_w
    cell_h = max(art_h, crop_h) + LABEL
    rows = (len(blocks) + COLUMNS - 1) // COLUMNS
    out = Image.new(
        "RGB",
        (COLUMNS * (cell_w + PAD) + PAD, rows * (cell_h + PAD) + PAD + LABEL),
        BACK,
    )
    pen = ImageDraw.Draw(out)
    pen.text((PAD, 6), "tileset %d  -  %d blocks  -  2D | 3D" % (number, len(blocks)), fill=INK)

    for index, block in enumerate(blocks):
        slot = block["slot"]
        column, row = index % COLUMNS, index // COLUMNS
        x = PAD + column * (cell_w + PAD)
        y = LABEL + PAD + row * (cell_h + PAD)

        left = (slot % grid) * size
        top = (slot // grid) * size
        piece = art.crop((left, top, left + size, top + size))
        out.paste(piece.resize((art_w, art_h), Image.NEAREST), (x, y))

        sx, sy = block["screen"]
        box = (
            int(sx) - ground_x,
            int(sy) - ground_y,
            int(sx) - ground_x + crop_w,
            int(sy) - ground_y + crop_h,
        )
        out.paste(shot.crop(box), (x + art_w + PAD, y))

        pen.text((x, y + cell_h - LABEL + 4), "#%d" % block["block"], fill=INK)
        pen.text((x + 34, y + cell_h - LABEL + 4), verdict(block), fill=DIM)

    path = directory / ("sheet_ts%d.png" % number)
    out.save(path)
    return path


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    directory = pathlib.Path(sys.argv[1])
    numbers = [int(n) for n in sys.argv[2:]] or sorted(
        int(p.stem[2:]) for p in directory.glob("ts*.json")
    )
    for number in numbers:
        print(sheet(directory, number))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
