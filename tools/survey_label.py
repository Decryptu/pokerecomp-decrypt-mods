#!/usr/bin/env python3
"""Builds the page a reviewer labels the survey on.

`tools/survey.gd` renders every block a tileset places, twice. This turns those
renders into one local page that shows a single block at a time, cartridge art
beside the mod's build of it, with a box to say what the drawing IS. Enter files
the answer and moves on.

Written as a page rather than a list of files because the answer is worth about
two seconds and finding the next block on a contact sheet costs longer than that.
Everything is in one file except the renders, which stay PNGs beside it: they are
19 MB of cartridge art and do not belong inlined, in a repository, or anywhere a
browser has to be told to fetch them.

    tools/survey_label.py <survey dir>            # writes <survey dir>/label.html

SAVE writes `labels.txt`, one `ts<n> #<block> <words>` a line, and that file is
what pins are read from. Answers are also mirrored into the browser's storage as
they are typed, which is a comfort against a closed tab and not the contract: a
page opened straight off the disk has an opaque origin in some browsers and
cannot store at all.
"""

import json
import pathlib
import sys

# Offered as buttons with hotkeys, in the order the world is made of them. These
# are only a shortcut: anything typed is kept as written, and the words matter
# more than the list does.
QUICK = [
    "ground", "wall", "roof", "tree", "bush", "water",
    "fence", "sign", "flowers", "tall grass", "ledge", "stairs",
]

PAGE = """<!doctype html>
<meta charset="utf-8">
<title>voxel3d survey</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; background: #16161a; color: #e8e8ee;
         font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  header { display: flex; gap: 16px; align-items: baseline; flex-wrap: wrap;
           padding: 12px 20px; border-bottom: 1px solid #2c2c34; }
  header h1 { font-size: 15px; margin: 0; font-weight: 600; }
  header .grow { flex: 1; }
  select, button, input { font: inherit; color: inherit; background: #23232b;
      border: 1px solid #3a3a44; border-radius: 6px; padding: 6px 10px; }
  button { cursor: pointer; }
  button:hover { background: #2e2e38; }
  main { display: flex; gap: 28px; padding: 24px 20px; align-items: flex-start;
         flex-wrap: wrap; }
  .shot { background: #0f0f12; border: 1px solid #2c2c34; border-radius: 10px;
          padding: 12px; }
  .shot h2 { margin: 0 0 8px; font-size: 12px; letter-spacing: .08em;
             text-transform: uppercase; color: #8d8da0; font-weight: 600; }
  .frame { image-rendering: pixelated; background-repeat: no-repeat; }
  .side { flex: 1; min-width: 320px; }
  .chip { display: inline-block; background: #23232b; border: 1px solid #3a3a44;
          border-radius: 999px; padding: 3px 10px; font-size: 13px; color: #a8a8bb; }
  #answer { width: 100%; font-size: 20px; padding: 12px 14px; margin: 14px 0 10px; }
  .quick { display: flex; flex-wrap: wrap; gap: 8px; }
  .quick button { font-size: 13px; padding: 5px 10px; }
  .quick b { color: #7f7f95; font-weight: 600; margin-right: 6px; }
  .bar { height: 4px; background: #23232b; border-radius: 2px; overflow: hidden; }
  .bar div { height: 100%; background: #6ea8fe; }
  .done { color: #7ad07a; }
  p.hint { color: #8d8da0; font-size: 13px; }
  kbd { background: #23232b; border: 1px solid #3a3a44; border-radius: 4px;
        padding: 1px 5px; font-size: 12px; }
</style>
<header>
  <h1>voxel3d survey</h1>
  <select id="tileset"></select>
  <label><input type="checkbox" id="structures" checked> structures only</label>
  <span class="chip" id="count"></span>
  <span class="grow"></span>
  <button id="save">SAVE labels.txt</button>
</header>
<main>
  <div class="shot">
    <h2>the cartridge</h2>
    <div class="frame" id="art"></div>
  </div>
  <div class="shot">
    <h2>the mod, now</h2>
    <div class="frame" id="built"></div>
  </div>
  <div class="side">
    <div class="bar"><div id="progress"></div></div>
    <p><span class="chip" id="where"></span> <span class="chip" id="verdict"></span></p>
    <input id="answer" autocomplete="off" spellcheck="false"
           placeholder="what is it? e.g. single big tree">
    <div class="quick" id="quick"></div>
    <p class="hint">
      <kbd>Enter</kbd> files it and moves on. Empty <kbd>Enter</kbd> means this one
      is already right. <kbd>Shift</kbd>+<kbd>Enter</kbd> goes back.
      <kbd>&#8997;1</kbd>..<kbd>&#8997;9</kbd> fill in the buttons below.
      Say what the drawing IS, in your own words; the shape is worked out from it.
    </p>
  </div>
</main>
<script>
const DATA = __DATA__;
const QUICK = __QUICK__;
let sheet = DATA[0], list = [], at = 0, dirty = false;

// Answers live in memory and are MIRRORED to localStorage, never read from it
// as the source. A page opened straight off the disk has an opaque origin in
// some browsers and storing throws; an hour of typing is not worth betting on
// which browser this is, so SAVE is the contract and storage is only a comfort
// if a tab is closed by accident.
const answers = {};
const key = (t, b) => "voxel3d:" + t + ":" + b;
try {
  for (let i = 0; i < localStorage.length; i++) {
    const k = localStorage.key(i);
    if (k.startsWith("voxel3d:")) answers[k] = localStorage.getItem(k);
  }
} catch (e) { /* opaque origin: memory only */ }

const $ = (id) => document.getElementById(id);
const remember = (k, v) => {
  if (v) answers[k] = v; else delete answers[k];
  try { v ? localStorage.setItem(k, v) : localStorage.removeItem(k); } catch (e) {}
};

function build() {
  const picker = $("tileset");
  picker.innerHTML = DATA.map((t, i) =>
    `<option value="${i}">tileset ${t.tileset}: ${t.maps} maps, ${t.blocks.length} blocks</option>`
  ).join("");
  picker.onchange = () => { sheet = DATA[picker.value]; at = 0; requeue(); };
  $("structures").onchange = () => { at = 0; requeue(); };
  $("save").onclick = save;
  $("quick").innerHTML = QUICK.map((w, i) =>
    `<button data-w="${w}"><b>${i < 9 ? "\u2325" + (i + 1) : ""}</b>${w}</button>`
  ).join("");
  $("quick").onclick = (e) => {
    const b = e.target.closest("button");
    if (b) { $("answer").value = b.dataset.w; $("answer").focus(); }
  };
  document.onkeydown = (e) => {
    if (e.target === $("answer") && e.key === "Enter") {
      file(e.shiftKey ? -1 : 1);
      e.preventDefault();
    } else if (e.altKey && e.key >= "1" && e.key <= "9") {
      $("answer").value = QUICK[+e.key - 1] || "";
      e.preventDefault();
    }
  };
  requeue();
}

function requeue() {
  const only = $("structures").checked;
  list = sheet.blocks.filter((b) => !only || b.structure);
  show();
}

function file(step) {
  const b = list[at];
  if (b) {
    remember(key(sheet.tileset, b.block), $("answer").value.trim());
    dirty = true;
  }
  at = Math.max(0, Math.min(list.length - 1, at + step));
  show();
}

function show() {
  const b = list[at];
  if (!b) { $("where").textContent = "nothing to show"; return; }
  const g = sheet.grid, s = sheet.block_pixels, z = 7;
  $("art").style.cssText =
    `width:${s}px;height:${s}px;transform:scale(${z});transform-origin:top left;` +
    `background-image:url("ts${sheet.tileset}_2d.png");` +
    `background-position:${-(b.slot % g) * s}px ${-Math.floor(b.slot / g) * s}px;` +
    `margin-bottom:${s * (z - 1)}px;margin-right:${s * (z - 1)}px;`;
  const [cw, ch] = sheet.crop, [gx, gy] = sheet.crop_ground, zz = 1.6;
  $("built").style.cssText =
    `width:${cw}px;height:${ch}px;transform:scale(${zz});transform-origin:top left;` +
    `background-image:url("ts${sheet.tileset}_3d.png");` +
    `background-position:${-(Math.round(b.screen[0]) - gx)}px ` +
    `${-(Math.round(b.screen[1]) - gy)}px;` +
    `margin-bottom:${ch * (zz - 1)}px;margin-right:${cw * (zz - 1)}px;`;
  $("where").textContent = `tileset ${sheet.tileset} · block #${b.block} · ${at + 1} of ${list.length}`;
  $("verdict").textContent = "mod says: " + b.verdict;
  $("progress").style.width = (100 * (at + 1) / list.length) + "%";
  $("count").innerHTML = counted();
  $("answer").value = answers[key(sheet.tileset, b.block)] || "";
  $("answer").focus();
  $("answer").select();
}

function counted() {
  let n = 0;
  for (const t of DATA)
    for (const b of t.blocks)
      if (answers[key(t.tileset, b.block)]) n++;
  return n ? `<span class="done">${n} labelled</span>` : "nothing labelled yet";
}

function save() {
  const lines = [];
  for (const t of DATA)
    for (const b of t.blocks) {
      const said = answers[key(t.tileset, b.block)];
      if (said) lines.push(`ts${t.tileset} #${b.block} ${said}`);
    }
  const blob = new Blob([lines.join("\\n") + "\\n"], { type: "text/plain" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = "labels.txt";
  a.click();
  dirty = false;
}

window.onbeforeunload = () => dirty ? "Labels have not been saved yet." : undefined;

build();
</script>
"""


def verdict(block):
    classes = sorted(block["classes"].items(), key=lambda kv: -kv[1])
    named = " ".join("%s%d" % (name, count) for name, count in classes)
    heights = sorted({int(h) for h in block["heights"]})
    return "%s, %s px tall" % (named, "/".join(str(h) for h in heights))


def structure(block):
    """Whether the block is worth a human's two seconds.

    Flat walkable ground is the majority of every tileset and is the one answer
    the detector cannot get wrong, so it goes behind a toggle rather than into
    the queue. Everything that rose, recessed, or resolved to anything but plain
    ground is asked about.
    """
    if any(int(h) != 0 for h in block["heights"]):
        return True
    return any(name != "ground" for name in block["classes"])


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    directory = pathlib.Path(sys.argv[1])
    sheets = []
    for path in sorted(directory.glob("ts*.json")):
        meta = json.loads(path.read_text())
        sheets.append({
            "tileset": meta["tileset"],
            "grid": meta["columns"],
            "block_pixels": meta["block_pixels"],
            "crop": meta["crop"],
            "crop_ground": meta["crop_ground"],
            "maps": meta.get("maps_using", 0),
            "blocks": [{
                "block": b["block"],
                "slot": b["slot"],
                "screen": b["screen"],
                "verdict": verdict(b),
                "structure": structure(b),
            } for b in meta["blocks"]],
        })
    sheets.sort(key=lambda s: (-s["maps"], s["tileset"]))
    page = PAGE.replace("__DATA__", json.dumps(sheets)).replace("__QUICK__", json.dumps(QUICK))
    out = directory / "label.html"
    out.write_text(page)
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
