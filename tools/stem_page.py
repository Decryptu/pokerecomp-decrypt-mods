#!/usr/bin/env python3
"""The page a person DRAWS A STEM on, under the flower it has to hold up.

`tools/stem_export.gd` writes the flower as it stands in 3D seen flat from the
front, which is its own mask wearing the tile's own texels. This lays that out
on a pixel grid with empty rows under it and lets a person paint the stem into
them, one world pixel a cell, at the same scale the geometry is built at.

WHAT IS PAINTED IS A SHAPE AND NOT A HEIGHT. The stem may bend, lean or taper:
the mesher stands one box per painted pixel and CENTRES the whole shape under
the middle of the bloom, so what matters is the shape and where it sits left to
right, not which column of the page it was drawn in.

  stem_page.py <stem.json> <out.html> [--rows N]

SAVE writes `stem.txt` to the browser's downloads, one line per row, `#` for a
pixel of stem and `.` for nothing. Read it back with `tools/stem_pins.py`.
"""

import json
import sys

CELL = 26
PAINT_ROWS = 10


def page(art, rows):
    bloom = art["bloom"]
    wide = len(bloom[0])
    tall = len(bloom) + rows
    colour = art["stem_colour"]
    cells = []
    for y, row in enumerate(bloom):
        for x, hex_colour in enumerate(row):
            if hex_colour is None:
                continue
            cells.append(
                '<div class="px bloom" style="left:%dpx;top:%dpx;background:%s"></div>'
                % (x * CELL, y * CELL, hex_colour)
            )
    return TEMPLATE % {
        "wide": wide,
        "tall": tall,
        "width": wide * CELL,
        "height": tall * CELL,
        "cell": CELL,
        "bloom_rows": len(bloom),
        "cells": "\n".join(cells),
        "colour": colour,
        "grass": art["grass"],
        "title": "%s, tileset %d tile %d, on map %s"
        % (art["class"], art["tileset"], art["tile"], art["map"]),
    }


TEMPLATE = """<!doctype html>
<meta charset="utf-8">
<title>stem</title>
<style>
  body { background:#17171b; color:#e8e8ee; font:14px/1.5 system-ui, sans-serif;
         margin:0; padding:24px; }
  h1 { font-size:15px; font-weight:600; margin:0 0 4px; }
  p { color:#a0a0ac; margin:0 0 18px; max-width:44em; }
  #board { position:relative; width:%(width)dpx; height:%(height)dpx;
           background:#26262c; box-shadow:0 0 0 1px #3a3a44; }
  .px { position:absolute; width:%(cell)dpx; height:%(cell)dpx; }
  .grid { position:absolute; inset:0;
          background-image:linear-gradient(to right,#ffffff14 1px,transparent 1px),
                           linear-gradient(to bottom,#ffffff14 1px,transparent 1px);
          background-size:%(cell)dpx %(cell)dpx; pointer-events:none; }
  #split { position:absolute; left:0; right:0; height:2px; background:#ff40dc;
           pointer-events:none; }
  #paint { position:absolute; inset:0; cursor:crosshair; }
  .on { background:%(colour)s; }
  button { font:inherit; background:#31313a; color:#e8e8ee; border:1px solid #4a4a56;
           border-radius:6px; padding:7px 14px; margin:18px 8px 0 0; cursor:pointer; }
  button:hover { background:#3d3d48; }
  code { color:#ffb0e8; }
</style>
<h1>%(title)s</h1>
<p>The flower as it stands, seen flat from the front, one world pixel a cell.
Paint the stem in the empty rows under it: drag to draw, drag with the right
button or hold Shift to rub out. It may bend and it may be a single pixel wide.
The shape is centred under the bloom when it is built, so its own column on this
page does not matter. Then <b>save</b> and hand over <code>stem.txt</code>.</p>
<div id="board">
  %(cells)s
  <div class="grid"></div>
  <div id="split"></div>
  <div id="paint"></div>
</div>
<button id="save">save stem.txt</button>
<button id="clear">clear</button>
<script>
const WIDE = %(wide)d, TALL = %(tall)d, CELL = %(cell)d, BLOOM = %(bloom_rows)d;
const paint = document.getElementById("paint");
const on = new Set();

document.getElementById("split").style.top = (BLOOM * CELL - 1) + "px";

function key(x, y) { return y * WIDE + x; }

function draw(x, y, add) {
  if (x < 0 || y < 0 || x >= WIDE || y >= TALL || y < BLOOM) return;
  const k = key(x, y);
  if (add === on.has(k)) return;
  if (add) {
    const d = document.createElement("div");
    d.className = "px on";
    d.style.left = (x * CELL) + "px";
    d.style.top = (y * CELL) + "px";
    d.dataset.k = k;
    paint.appendChild(d);
    on.add(k);
  } else {
    const d = paint.querySelector('[data-k="' + k + '"]');
    if (d) d.remove();
    on.delete(k);
  }
}

let down = false, adding = true, last = null;
function at(e) {
  const r = paint.getBoundingClientRect();
  return [Math.floor((e.clientX - r.left) / CELL), Math.floor((e.clientY - r.top) / CELL)];
}

// A pointer moves further than a cell between two events, so a quick stroke
// would come out as beads. Walk the line between the last cell and this one.
function stroke(x, y, add) {
  if (last) {
    const steps = Math.max(Math.abs(x - last[0]), Math.abs(y - last[1]));
    for (let i = 1; i < steps; i++) {
      draw(Math.round(last[0] + (x - last[0]) * i / steps),
           Math.round(last[1] + (y - last[1]) * i / steps), add);
    }
  }
  draw(x, y, add);
  last = [x, y];
}
paint.addEventListener("contextmenu", e => e.preventDefault());
paint.addEventListener("pointerdown", e => {
  down = true;
  adding = e.button === 0 && !e.shiftKey;
  last = null;
  const [x, y] = at(e);
  stroke(x, y, adding);
  paint.setPointerCapture(e.pointerId);
});
paint.addEventListener("pointermove", e => {
  if (!down) return;
  const [x, y] = at(e);
  stroke(x, y, adding);
});
addEventListener("pointerup", () => { down = false; last = null; });

document.getElementById("clear").onclick = () => {
  on.clear();
  paint.replaceChildren();
};

document.getElementById("save").onclick = () => {
  const lines = [];
  for (let y = BLOOM; y < TALL; y++) {
    let line = "";
    for (let x = 0; x < WIDE; x++) line += on.has(key(x, y)) ? "#" : ".";
    lines.push(line);
  }
  const blob = new Blob([lines.join("\\n") + "\\n"], { type: "text/plain" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = "stem.txt";
  a.click();
};
</script>
"""


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    rows = PAINT_ROWS
    if "--rows" in argv:
        rows = int(argv[argv.index("--rows") + 1])
    art = json.load(open(argv[1]))
    html = page(art, rows)
    open(argv[2], "w").write(html)
    print(argv[2], "%d x %d cells" % (len(art["bloom"][0]), len(art["bloom"]) + rows))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
