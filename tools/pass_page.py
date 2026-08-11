#!/usr/bin/env python3
"""Builds the page that asks the human only about what the pass could not settle.

A full pass reads every tile of every tileset from its picture and marks each
answer `sure`, `likely` or `unsure`. This puts the rest in front of the reviewer
with the pass's own description ALREADY IN THE BOX: their job is to validate or
correct a sentence rather than to write one from nothing, which is a different
and much cheaper act.

    tools/pass_page.py <pass dir> [likely]   # writes <pass dir>/verdict.html

By default only `unsure` is asked about. Add `likely` to include those too,
which is the thorough round.

SAVE writes `verdict.txt` in the shape every other answer file uses, so it feeds
straight back in and those tiles are never asked about again.
"""

import json
import pathlib
import sys

PAGE = """<!doctype html>
<meta charset="utf-8">
<title>voxel3d verdicts</title>
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
  .side { flex: 1; min-width: 380px; }
  .chip { display: inline-block; background: #23232b; border: 1px solid #3a3a44;
          border-radius: 999px; padding: 3px 10px; font-size: 13px; color: #a8a8bb; }
  .chip.unsure { border-color: #7a5030; color: #f0b070; }
  .chip.likely { border-color: #3a4a6a; color: #8ab0f0; }
  #answer { width: 100%; font-size: 17px; padding: 12px 14px; margin: 14px 0 6px; }
  .bar { height: 4px; background: #23232b; border-radius: 2px; overflow: hidden; }
  .bar div { height: 100%; background: #6ea8fe; }
  .done { color: #7ad07a; }
  p.hint { color: #8d8da0; font-size: 13px; }
  kbd { background: #23232b; border: 1px solid #3a3a44; border-radius: 4px;
        padding: 1px 5px; font-size: 12px; }
</style>
<header>
  <h1>voxel3d verdicts</h1>
  <select id="tileset"></select>
  <span class="chip" id="count"></span>
  <span class="grow"></span>
  <button id="save">SAVE verdict.txt</button>
</header>
<main>
  <div class="shot">
    <h2>where the cartridge uses it</h2>
    <img id="context" width="480" height="480">
  </div>
  <div class="side">
    <div class="bar"><div id="progress"></div></div>
    <p>
      <span class="chip" id="where"></span>
      <span class="chip" id="conf"></span>
      <span class="chip" id="uses"></span>
    </p>
    <input id="answer" autocomplete="off" spellcheck="false">
    <p class="hint">
      This is what the pass thinks it is, already written in. <kbd>Enter</kbd>
      accepts it as it stands and moves on; edit the line first if it is wrong.
      <kbd>Shift</kbd>+<kbd>Enter</kbd> goes back. Clear the box and press
      <kbd>Enter</kbd> to say "I do not know either".
    </p>
    <p class="hint">
      What matters most is how the thing SITS in a real world: tall like a wall,
      low and flat like a table, or lying on the ground. That is the one thing
      the picture cannot settle on its own.
    </p>
  </div>
</main>
<script>
const DATA = __DATA__;
const $ = (id) => document.getElementById(id);
let sheet = DATA[0], at = 0, dirty = false;

const answers = {};
const key = (t, x) => "voxel3dverdict:" + t + ":" + x;
try {
  for (let i = 0; i < localStorage.length; i++) {
    const k = localStorage.key(i);
    if (k.startsWith("voxel3dverdict:")) answers[k] = localStorage.getItem(k);
  }
} catch (e) {}

const remember = (k, v) => {
  if (v) answers[k] = v; else delete answers[k];
  try { v ? localStorage.setItem(k, v) : localStorage.removeItem(k); } catch (e) {}
};

$("tileset").innerHTML = DATA.map((t, i) =>
  `<option value="${i}">tileset ${t.tileset}: ${t.tiles.length}</option>`).join("");
$("tileset").onchange = () => { sheet = DATA[$("tileset").value]; at = 0; show(); };
$("save").onclick = save;
$("answer").onkeydown = (e) => {
  if (e.key !== "Enter") return;
  const t = sheet.tiles[at];
  remember(key(sheet.tileset, t.tile), $("answer").value.trim());
  dirty = true;
  at = Math.max(0, Math.min(sheet.tiles.length - 1, at + (e.shiftKey ? -1 : 1)));
  show();
  e.preventDefault();
};

function show() {
  const t = sheet.tiles[at];
  if (!t) return;
  $("context").src = t.file;
  $("where").textContent =
    `tileset ${sheet.tileset} · tile ${t.tile} · ${at + 1} of ${sheet.tiles.length}`;
  $("conf").textContent = t.word + " · " + t.confidence;
  $("conf").className = "chip " + t.confidence;
  $("uses").textContent = `placed ${t.count} times`;
  $("progress").style.width = (100 * (at + 1) / sheet.tiles.length) + "%";
  let n = 0;
  for (const s of DATA)
    for (const x of s.tiles) if (answers[key(s.tileset, x.tile)]) n++;
  $("count").innerHTML = n ? `<span class="done">${n} settled</span>` : "none settled yet";
  const said = answers[key(sheet.tileset, t.tile)];
  $("answer").value = said === undefined ? t.words : said;
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
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([lines.join("\\n") + "\\n"],
    { type: "text/plain" }));
  a.download = "verdict.txt";
  a.click();
  dirty = false;
}

window.onbeforeunload = () => dirty ? "Not saved yet." : undefined;
show();
</script>
"""


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    directory = pathlib.Path(sys.argv[1])
    wanted = {"unsure"}
    if "likely" in sys.argv[2:]:
        wanted.add("likely")

    # Never ask twice. A tile any answer file already names is settled, whether
    # the pass was sure of it or not.
    settled = set()
    for path in sorted(directory.parent.glob("answers*.txt")) + \
            sorted(directory.parent.glob("verdict*.txt")):
        for line in path.read_text().splitlines():
            words = line.split()
            if len(words) >= 3 and words[0].startswith("ts") and words[1].isdigit():
                settled.add((int(words[0][2:]), int(words[1])))

    placed = {}
    for path in sorted(directory.glob("pass_ts*.json")):
        sheet = json.loads(path.read_text())
        for tile in sheet["tiles"]:
            placed[(sheet["tileset"], tile["tile"])] = tile

    sheets = []
    files = [p for p in directory.glob("pass_ts*.txt") if p.stem[7:].isdigit()]
    for path in sorted(files, key=lambda p: int(p.stem[7:])):
        number = int(path.stem[7:])
        tiles = []
        for line in path.read_text().splitlines():
            fields = line.split(None, 4)
            if len(fields) < 4 or not fields[0].startswith("ts"):
                continue
            if fields[3] not in wanted and fields[2] != "unsure":
                continue
            if (number, int(fields[1])) in settled:
                continue
            known = placed.get((number, int(fields[1])), {})
            tiles.append({
                "tile": int(fields[1]),
                "word": fields[2],
                "confidence": fields[3],
                "words": fields[4] if len(fields) > 4 else "",
                "file": known.get("file", ""),
                "count": known.get("count", 0),
            })
        if tiles:
            sheets.append({"tileset": number, "tiles": tiles})

    if not sheets:
        print("nothing left over: every tile came back sure")
        return 0
    out = directory / "verdict.html"
    out.write_text(PAGE.replace("__DATA__", json.dumps(sheets)))
    print("%d tiles over %d tilesets" % (
        sum(len(s["tiles"]) for s in sheets), len(sheets)))
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
