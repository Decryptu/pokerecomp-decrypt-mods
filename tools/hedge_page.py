#!/usr/bin/env python3
"""Builds the page that asks how a HEDGE should be built.

One question, three pictures of the same place, and a box. A bush is one walk
cell and a hedge is several ranks of the same bush, so each cell building its
own round blob makes a hedge read as corduroy. Which of the three is right is a
judgement about the drawing and nobody but the reviewer can make it.

    tools/hedge_shot.gd <cache> <survey dir>   # renders the three
    tools/hedge_page.py <survey dir>           # writes <survey dir>/hedge.html

SAVE writes `hedge.txt`: the chosen variant id, then any words.
"""

import json
import pathlib
import sys

PAGE = """<!doctype html>
<meta charset="utf-8">
<title>voxel3d hedge</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0 auto; max-width: 1100px; padding: 24px 20px 80px;
         background: #16161a; color: #e8e8ee;
         font: 15px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  h1 { font-size: 18px; margin: 0 0 6px; }
  p.lede { color: #a8a8bb; max-width: 76ch; margin: 0 0 8px; }
  img { image-rendering: pixelated; display: block; max-width: 100%;
        border-radius: 8px; }
  .art { width: 240px; border: 1px solid #2c2c34; }
  .row { display: flex; gap: 20px; align-items: flex-start; flex-wrap: wrap;
         margin: 18px 0; }
  label.pick { display: block; background: #0f0f12; border: 2px solid #2c2c34;
               border-radius: 12px; padding: 12px; cursor: pointer; flex: 1;
               min-width: 320px; }
  label.pick:hover { border-color: #4a4a58; }
  label.pick.on { border-color: #6ea8fe; }
  label.pick h2 { font-size: 14px; margin: 0 0 2px; }
  label.pick p { color: #a8a8bb; font-size: 13px; margin: 0 0 10px; max-width: 60ch; }
  input[type=radio] { margin-right: 8px; }
  textarea { width: 100%; min-height: 110px; font: inherit; color: inherit;
             background: #23232b; border: 1px solid #3a3a44; border-radius: 8px;
             padding: 10px 12px; }
  button { font: inherit; color: inherit; background: #23232b; cursor: pointer;
           border: 1px solid #3a3a44; border-radius: 8px; padding: 8px 16px; }
  button:hover { background: #2e2e38; }
  h3 { font-size: 13px; letter-spacing: .08em; text-transform: uppercase;
       color: #8d8da0; margin: 28px 0 6px; }
</style>
<h1>How should a hedge be built?</h1>
<p class="lede">
  A bush is one walk cell. A hedge is several ranks of the same bush, and each
  cell currently builds its own round blob, so a hedge reads as corduroy. Below
  is the same place in the game, built three ways. Pick the one that looks most
  like what the drawing means, and say why in a line if you can. Nothing will be
  tuned before this comes back.
</p>
<h3>what the cartridge draws there</h3>
<img class="art" src="hedge_2d.png" width="240">
<div id="picks"></div>
<h3>anything else</h3>
<textarea id="notes" placeholder="anything else wrong in these pictures"></textarea>
<p><button id="save">SAVE hedge.txt</button></p>
<script>
const DATA = __DATA__;
const $ = (id) => document.getElementById(id);
let chosen = localStorage.getItem("voxel3dhedge:pick") || "";

$("picks").innerHTML = DATA.variants.map((v) => `
  <div class="row">
    <label class="pick" data-id="${v.id}">
      <h2><input type="radio" name="pick" value="${v.id}">${v.label}</h2>
      <p>${v.says}</p>
      <img src="hedge_${v.id}.png" width="640">
    </label>
  </div>`).join("");

function paint() {
  for (const el of document.querySelectorAll("label.pick"))
    el.classList.toggle("on", el.dataset.id === chosen);
  for (const el of document.querySelectorAll("input[name=pick]"))
    el.checked = el.value === chosen;
}
$("picks").onchange = (e) => {
  chosen = e.target.value;
  localStorage.setItem("voxel3dhedge:pick", chosen);
  paint();
};
$("notes").value = localStorage.getItem("voxel3dhedge:notes") || "";
$("notes").oninput = () =>
  localStorage.setItem("voxel3dhedge:notes", $("notes").value);
$("save").onclick = () => {
  const lines = ["hedge " + (chosen || "(nothing picked)")];
  const said = $("notes").value.trim();
  if (said) lines.push("notes " + said.replace(/\\n/g, " "));
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([lines.join("\\n") + "\\n"],
    { type: "text/plain" }));
  a.download = "hedge.txt";
  a.click();
};
paint();
</script>
"""


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    directory = pathlib.Path(sys.argv[1])
    record = directory / "hedge.json"
    if not record.exists():
        print("no hedge.json in %s: run tools/hedge_shot.gd first" % directory)
        return 1
    out = directory / "hedge.html"
    out.write_text(PAGE.replace("__DATA__", json.dumps(json.loads(record.read_text()))))
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
