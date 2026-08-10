#!/usr/bin/env python3
"""Builds the page that asks what a TILE is, with the world around it.

The block page (`survey_label.py`) asks what a drawing is. This one asks about
the leftovers: the individual tiles that are still being stood up as walls
because nothing has claimed them. A tile on its own is unreadable, so each one
is shown where the cartridge actually uses it, ringed in red, with most of a
Game Boy screen around it.

Ends with the open questions that are not about any one tile, because the answer
to "should a bush be round" is worth more than fifty tile names and there is
nowhere else to put it.

    tools/survey_tiles.py <survey dir>       # writes <survey dir>/tiles.html

SAVE writes `tiles.txt`: `ts<n> <tile> <words>` a line, then `Q <id> <words>`
for the questions.
"""

import json
import pathlib
import sys

QUICK = [
    "grass", "rock", "ledge", "cliff", "water", "bridge",
    "tree", "bush", "fence", "sign", "part of a building", "roof",
]

# Asked once, at the end, in their own boxes. Each is something the geometry
# cannot decide and one sentence settles.
QUESTIONS = [
    ("sign", "The wooden route sign: its board is the same colour as the floor, "
             "so the cut-out ate it and only the letters survived. Describe the "
             "sign as you see it: how many pixels wide is the board, which rows "
             "are the board, which are the posts, and is there anything under it?"),
    ("round", "Bush, cuttable tree, bollard and wooden pole are to be made ROUND. "
              "Their outline is dark, so revolving them naively paints them dark "
              "all the way round. Is it better to keep the front face's own "
              "colours and only round the SILHOUETTE, or to accept a dark rim?"),
    ("tops", "The tops of the bushes read very dark, because the drawing's own "
             "black outline lands on every upward face. Lighten them, or leave?"),
    ("next", "Anything else you noticed that is wrong and I have not asked about."),
]

PAGE = """<!doctype html>
<meta charset="utf-8">
<title>voxel3d tiles</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; background: #16161a; color: #e8e8ee;
         font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  header { display: flex; gap: 16px; align-items: baseline; flex-wrap: wrap;
           padding: 12px 20px; border-bottom: 1px solid #2c2c34; position: sticky;
           top: 0; background: #16161a; z-index: 2; }
  header h1 { font-size: 15px; margin: 0; font-weight: 600; }
  header .grow { flex: 1; }
  select, button, input, textarea { font: inherit; color: inherit;
      background: #23232b; border: 1px solid #3a3a44; border-radius: 6px;
      padding: 6px 10px; }
  button { cursor: pointer; }
  button:hover { background: #2e2e38; }
  main { display: flex; gap: 28px; padding: 24px 20px; align-items: flex-start;
         flex-wrap: wrap; }
  .shot { background: #0f0f12; border: 1px solid #2c2c34; border-radius: 10px;
          padding: 12px; }
  .shot h2 { margin: 0 0 8px; font-size: 12px; letter-spacing: .08em;
             text-transform: uppercase; color: #8d8da0; font-weight: 600; }
  img { image-rendering: pixelated; display: block; }
  .side { flex: 1; min-width: 340px; }
  .chip { display: inline-block; background: #23232b; border: 1px solid #3a3a44;
          border-radius: 999px; padding: 3px 10px; font-size: 13px; color: #a8a8bb; }
  #answer { width: 100%; font-size: 20px; padding: 12px 14px; margin: 14px 0 10px; }
  .quick { display: flex; flex-wrap: wrap; gap: 8px; }
  .quick button { font-size: 13px; padding: 5px 10px; }
  .bar { height: 4px; background: #23232b; border-radius: 2px; overflow: hidden; }
  .bar div { height: 100%; background: #6ea8fe; }
  .done { color: #7ad07a; }
  p.hint { color: #8d8da0; font-size: 13px; }
  kbd { background: #23232b; border: 1px solid #3a3a44; border-radius: 4px;
        padding: 1px 5px; font-size: 12px; }
  section { border-top: 1px solid #2c2c34; padding: 20px; }
  section h2 { font-size: 14px; margin: 0 0 4px; }
  section p { color: #a8a8bb; margin: 0 0 8px; max-width: 70ch; }
  section textarea { width: 100%; max-width: 70ch; min-height: 90px; }
</style>
<header>
  <h1>voxel3d tiles</h1>
  <select id="tileset"></select>
  <span class="chip" id="count"></span>
  <span class="grow"></span>
  <button id="save">SAVE tiles.txt</button>
</header>
<main>
  <div class="shot">
    <h2>where the cartridge uses it</h2>
    <img id="context" width="480" height="480">
  </div>
  <div class="side">
    <div class="bar"><div id="progress"></div></div>
    <p><span class="chip" id="where"></span> <span class="chip" id="uses"></span></p>
    <input id="answer" autocomplete="off" spellcheck="false"
           placeholder="what is the thing in the red box?">
    <div class="quick" id="quick"></div>
    <p class="hint">
      <kbd>Enter</kbd> files it and moves on, empty <kbd>Enter</kbd> skips,
      <kbd>Shift</kbd>+<kbd>Enter</kbd> goes back. Only the red box matters;
      ignore the rest of the picture. Skip anything that is part of a building.
    </p>
  </div>
</main>
<div id="questions"></div>
<script>
const DATA = __DATA__;
const QUICK = __QUICK__;
const QUESTIONS = __QUESTIONS__;
let sheet = DATA[0], at = 0, dirty = false;

const answers = {};
const key = (t, x) => "voxel3dtile:" + t + ":" + x;
try {
  for (let i = 0; i < localStorage.length; i++) {
    const k = localStorage.key(i);
    if (k.startsWith("voxel3dtile:")) answers[k] = localStorage.getItem(k);
  }
} catch (e) {}

const $ = (id) => document.getElementById(id);
const remember = (k, v) => {
  if (v) answers[k] = v; else delete answers[k];
  try { v ? localStorage.setItem(k, v) : localStorage.removeItem(k); } catch (e) {}
};

function build() {
  $("tileset").innerHTML = DATA.map((t, i) =>
    `<option value="${i}">tileset ${t.tileset}: ${t.tiles.length} tiles</option>`).join("");
  $("tileset").onchange = () => { sheet = DATA[$("tileset").value]; at = 0; show(); };
  $("save").onclick = save;
  $("quick").innerHTML = QUICK.map((w) => `<button data-w="${w}">${w}</button>`).join("");
  $("quick").onclick = (e) => {
    const b = e.target.closest("button");
    if (b) { $("answer").value = b.dataset.w; $("answer").focus(); }
  };
  $("questions").innerHTML = QUESTIONS.map(([id, text]) => `
    <section>
      <h2>${id}</h2>
      <p>${text}</p>
      <textarea data-q="${id}"></textarea>
    </section>`).join("");
  for (const box of document.querySelectorAll("textarea")) {
    box.value = answers[key("Q", box.dataset.q)] || "";
    box.oninput = () => {
      remember(key("Q", box.dataset.q), box.value.trim());
      dirty = true;
    };
  }
  $("answer").onkeydown = (e) => {
    if (e.key !== "Enter") return;
    const t = sheet.tiles[at];
    remember(key(sheet.tileset, t.tile), $("answer").value.trim());
    dirty = true;
    at = Math.max(0, Math.min(sheet.tiles.length - 1, at + (e.shiftKey ? -1 : 1)));
    show();
    e.preventDefault();
  };
  show();
}

function show() {
  const t = sheet.tiles[at];
  if (!t) return;
  $("context").src = t.file;
  $("where").textContent = `tileset ${sheet.tileset} · tile ${t.tile} · ${at + 1} of ${sheet.tiles.length}`;
  $("uses").textContent = `placed ${t.count} times · map ${t.map[0]},${t.map[1]}`;
  $("progress").style.width = (100 * (at + 1) / sheet.tiles.length) + "%";
  let n = 0;
  for (const s of DATA)
    for (const x of s.tiles) if (answers[key(s.tileset, x.tile)]) n++;
  $("count").innerHTML = n ? `<span class="done">${n} named</span>` : "nothing named yet";
  $("answer").value = answers[key(sheet.tileset, t.tile)] || "";
  $("answer").focus();
  $("answer").select();
}

function save() {
  const lines = [];
  for (const s of DATA)
    for (const x of s.tiles) {
      const said = answers[key(s.tileset, x.tile)];
      if (said) lines.push(`ts${s.tileset} ${x.tile} ${said}`);
    }
  for (const [id] of QUESTIONS) {
    const said = answers[key("Q", id)];
    if (said) lines.push(`Q ${id} ${said.replace(/\\n/g, " ")}`);
  }
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([lines.join("\\n") + "\\n"], { type: "text/plain" }));
  a.download = "tiles.txt";
  a.click();
  dirty = false;
}

window.onbeforeunload = () => dirty ? "Not saved yet." : undefined;
build();
</script>
"""


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    directory = pathlib.Path(sys.argv[1])
    sheets = [json.loads(p.read_text()) for p in sorted(directory.glob("ask_ts*.json"))]
    if not sheets:
        print("no ask_ts*.json in %s: run tools/survey_context.gd first" % directory)
        return 1
    page = (PAGE.replace("__DATA__", json.dumps(sheets))
                .replace("__QUICK__", json.dumps(QUICK))
                .replace("__QUESTIONS__", json.dumps(QUESTIONS)))
    out = directory / "tiles.html"
    out.write_text(page)
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
