#!/usr/bin/env python3
"""Burns a label onto a picture, because a filename is not one.

A reviewer sent a picture does not see what it is called and cannot follow a
caption that names six of them by position. Their words: "I dont see the name
file when you send them", and "label each screenshot separately so I understand
what is what". So the label goes IN the picture, in a strip above it, and every
plate sent from here carries one.

  label.py <in.png> <out.png> <state> [detail] [--of "1 of 3"]

STATE is the large line and is what the picture is: `BEFORE`, `AFTER`,
`MAP 3,15`. DETAIL is the small line under it and says what that state means.
`--of` puts a counter at the right hand end, so a set read in any order still
says how many are in it.

Writes in place safely: the output may be the input. Needs Pillow.
"""

import sys

from PIL import Image, ImageDraw, ImageFont

# The ruling in `map_grid.py`'s colours, so a plate and a grid sent together
# read as one set.
BACK = (24, 24, 28)
INK = (236, 236, 240)
DIM = (150, 150, 160)
STATE = 40
DETAIL = 26
PAD = 14


def font(px, bold):
    faces = ("Arial Bold.ttf", "Arial.ttf") if bold else ("Arial.ttf",)
    for name in faces:
        for root in ("/System/Library/Fonts/Supplemental/",
                     "/Library/Fonts/", "/usr/share/fonts/truetype/dejavu/"):
            try:
                return ImageFont.truetype(root + name, px)
            except OSError:
                continue
    for path in ("/System/Library/Fonts/Helvetica.ttc",
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(path, px)
        except OSError:
            continue
    return ImageFont.load_default()


def labelled(art, state, detail, counter):
    """The picture with a strip above it carrying its own name."""
    big = font(STATE, True)
    small = font(DETAIL, False)
    bar = PAD * 2 + STATE + (DETAIL + PAD // 2 if detail else 0)
    out = Image.new("RGB", (art.size[0], art.size[1] + bar), BACK)
    out.paste(art.convert("RGB"), (0, bar))
    g = ImageDraw.Draw(out)
    g.text((PAD, PAD), state, font=big, fill=INK, anchor="la")
    if detail:
        g.text((PAD, PAD + STATE + PAD // 2), detail, font=small, fill=DIM,
               anchor="la")
    if counter:
        g.text((art.size[0] - PAD, PAD), counter, font=small, fill=DIM,
               anchor="ra")
    return out


def main(argv):
    words = [a for a in argv[1:] if a != "--of"]
    counter = ""
    if "--of" in argv:
        at = argv.index("--of")
        if at + 1 >= len(argv):
            print("--of takes a counter, like \"1 of 3\"", file=sys.stderr)
            return 2
        counter = argv[at + 1]
        words.remove(counter)
    if len(words) < 3:
        print(__doc__.strip().splitlines()[8].strip(), file=sys.stderr)
        return 2
    source, out, state = words[0], words[1], words[2]
    detail = words[3] if len(words) > 3 else ""
    # Read whole and closed before writing, since the output is allowed to be
    # the input and a tool that labels a picture in place is the common case.
    with Image.open(source) as art:
        plate = labelled(art, state, detail, counter)
    plate.save(out)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
