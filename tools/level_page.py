#!/usr/bin/env python3
"""The page a reviewer PAINTS a map's ground levels on.

Every other question in this project is answered in words. Height cannot be:
"the floor behind that wall is one up" is true of a region, not of a thing, and
naming the region is harder than pointing at it. So this one is painted. The
reviewer drags a rectangle over the map's own art and says what level it is, and
what comes back is a matrix rather than a sentence.

    tools/level_page.py <levels dir>      # writes <levels dir>/levels.html

The directory is what `tools/level_export.gd` wrote, with each map's own art
from `tools/map_art.gd` beside it.

THE UNIT IS THE WALK CELL, 16x16 pixels, because that is what a level step is:
one level is one cell of height, and a wall or a flight of stairs is drawn 2x2
tiles, which is one cell.

PRE-FILLED with what the mod already measures, so the job is correcting a
proposal rather than painting a map from blank. Outdoors the cliff pass is
mostly right already; the caves are the ones that come out flat and wrong.

SAVE writes `levels.json`: per map, the level matrix and the wall matrix, ready
to be read straight back.
"""

import json
import pathlib
import sys

PAGE = """<!doctype html>
<meta charset="utf-8">
<title>voxel3d levels</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; background: #16161a; color: #e8e8ee;
         font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  header { display: flex; gap: 14px; align-items: center; flex-wrap: wrap;
           padding: 10px 18px; border-bottom: 1px solid #2c2c34;
           position: sticky; top: 0; background: #16161af2; z-index: 5; }
  header h1 { font-size: 15px; margin: 0; font-weight: 600; }
  .grow { flex: 1; }
  select, button { font: inherit; color: inherit; background: #23232b;
      border: 1px solid #3a3a44; border-radius: 6px; padding: 6px 10px;
      cursor: pointer; }
  button:hover { background: #2e2e38; }
  main { padding: 16px 18px 90px; }
  .wrap { position: relative; display: inline-block;
          border: 1px solid #2c2c34; border-radius: 8px; overflow: hidden; }
  canvas { display: block; image-rendering: pixelated; cursor: crosshair; }
  .levels { display: flex; gap: 6px; flex-wrap: wrap; align-items: center; }
  .lv { width: 40px; height: 34px; border-radius: 6px; border: 2px solid #3a3a44;
        display: flex; align-items: center; justify-content: center;
        font-weight: 600; cursor: pointer; color: #000; }
  .lv.on { border-color: #fff; box-shadow: 0 0 0 2px #6ea8fe; }
  .hint { color: #8d8da0; font-size: 13px; margin: 8px 0 0; max-width: 90ch; }
  kbd { background: #23232b; border: 1px solid #3a3a44; border-radius: 4px;
        padding: 1px 5px; font-size: 12px; }
  footer { position: fixed; bottom: 0; left: 0; right: 0; padding: 10px 18px;
           background: #16161af2; border-top: 1px solid #2c2c34;
           display: flex; gap: 14px; align-items: center; z-index: 5; }
  .chip { display: inline-block; background: #23232b; border: 1px solid #3a3a44;
          border-radius: 999px; padding: 3px 10px; font-size: 13px; color: #a8a8bb; }
</style>
<header>
  <h1>voxel3d levels</h1>
  <select id="map"></select>
  <span class="levels" id="palette"></span>
  <button id="wallmode">walls: off</button>
  <span class="grow"></span>
  <button id="reset">reset this map</button>
  <button id="save">SAVE levels.json</button>
</header>
<main>
  <div class="wrap"><canvas id="art"></canvas></div>
  <p class="hint">
    <b>Drag a rectangle</b> to paint every cell in it with the selected level.
    <kbd>0</kbd>-<kbd>6</kbd> pick a level, <kbd>-</kbd> and <kbd>=</kbd> step it,
    <kbd>Shift</kbd> while dragging paints the WALL flag instead,
    <kbd>Ctrl</kbd>+<kbd>Z</kbd> undoes.
  </p>
  <p class="hint">
    One level is 16 pixels, one walk cell. The colours start from what the mod
    already measures, so most of an outdoor map should be right and you are only
    fixing what is wrong. A cave starts flat because there is nothing outdoors
    for it to read.
  </p>
  <p class="hint">
    A <b>wall</b> is a cell that belongs to both levels at once, which is the
    transition itself: the rock face, the 45 degree bank, the flight of stairs.
    Mark those rather than trying to give them a level. They are drawn with a
    hatch.
  </p>
</header>
<footer>
  <span class="chip" id="count"></span>
  <span class="grow"></span>
  <button id="save2">SAVE levels.json</button>
</footer>
<script>
const MAPS = __MAPS__;
const CELL = 16;
// A ramp a person can tell apart at a glance, low to high. Level 0 is
// deliberately the only one with no tint at all: an untouched map should look
// like the map.
const COLORS = {
  "-2": "#3b2a6b", "-1": "#4a63c8", "0": null, "1": "#7ad07a",
  "2": "#d8c95a", "3": "#e09a4a", "4": "#d4603c", "5": "#c04a8a",
  "6": "#9a4ad4",
};
let at = 0, level = 1, wallMode = false, scale = 3;
const undo = [];

const $ = (id) => document.getElementById(id);
const store = {};
const KEY = "voxel3dlevels:";
try {
  for (let i = 0; i < localStorage.length; i++) {
    const k = localStorage.key(i);
    if (k.startsWith(KEY)) store[k] = localStorage.getItem(k);
  }
} catch (e) {}

function state(i) {
  const m = MAPS[i];
  const k = KEY + m.group + "," + m.number;
  if (!m._levels) {
    let saved = null;
    try { saved = store[k] ? JSON.parse(store[k]) : null; } catch (e) {}
    m._levels = saved ? saved.levels : m.levels.map((r) => r.slice());
    m._walls = saved ? saved.walls : m.walls.map((r) => r.slice());
  }
  return m;
}

function persist(m) {
  try {
    localStorage.setItem(KEY + m.group + "," + m.number,
      JSON.stringify({ levels: m._levels, walls: m._walls }));
  } catch (e) {}
  tally();
}

const img = new Image();

function draw() {
  const m = state(at);
  const c = $("art"), g = c.getContext("2d");
  const w = m.cells[0] * CELL, h = m.cells[1] * CELL;
  c.width = w * scale; c.height = h * scale;
  g.imageSmoothingEnabled = false;
  if (img.complete && img.naturalWidth) g.drawImage(img, 0, 0, c.width, c.height);
  for (let cy = 0; cy < m.cells[1]; cy++) {
    for (let cx = 0; cx < m.cells[0]; cx++) {
      const x = cx * CELL * scale, y = cy * CELL * scale, s = CELL * scale;
      const tint = COLORS[String(m._levels[cy][cx])];
      if (tint) {
        g.globalAlpha = 0.42; g.fillStyle = tint; g.fillRect(x, y, s, s);
        g.globalAlpha = 1;
      }
      if (m._walls[cy][cx]) {
        g.strokeStyle = "rgba(255,255,255,0.55)"; g.lineWidth = 1;
        g.beginPath();
        for (let d = -s; d < s; d += 6) {
          g.moveTo(x + d, y); g.lineTo(x + d + s, y + s);
        }
        g.save(); g.rect(x, y, s, s); g.clip(); g.stroke(); g.restore();
      }
      g.strokeStyle = "rgba(0,0,0,0.30)"; g.lineWidth = 1;
      g.strokeRect(x + 0.5, y + 0.5, s - 1, s - 1);
    }
  }
}

function tally() {
  let painted = 0, walls = 0;
  for (let i = 0; i < MAPS.length; i++) {
    const m = state(i);
    for (let cy = 0; cy < m.cells[1]; cy++)
      for (let cx = 0; cx < m.cells[0]; cx++) {
        if (m._levels[cy][cx] !== m.levels[cy][cx]) painted++;
        if (m._walls[cy][cx] !== m.walls[cy][cx]) walls++;
      }
  }
  $("count").textContent =
    `${painted} cells changed from the guess, ${walls} wall flags changed`;
}

function build() {
  $("map").innerHTML = MAPS.map((m, i) =>
    `<option value="${i}">map ${m.group},${m.number} · tileset ${m.tileset} · ` +
    `${m.cells[0]}x${m.cells[1]} cells${m.outside ? "" : " · inside"}</option>`
  ).join("");
  $("map").onchange = () => { at = +$("map").value; load(); };
  $("palette").innerHTML = Object.keys(COLORS).map((k) =>
    `<span class="lv" data-l="${k}" style="background:${COLORS[k] || "#8d8da0"}">${k}</span>`
  ).join("");
  $("palette").onclick = (e) => {
    const el = e.target.closest(".lv");
    if (el) { level = +el.dataset.l; marks(); }
  };
  $("wallmode").onclick = () => {
    wallMode = !wallMode;
    $("wallmode").textContent = "walls: " + (wallMode ? "ON" : "off");
  };
  $("reset").onclick = () => {
    const m = state(at);
    m._levels = m.levels.map((r) => r.slice());
    m._walls = m.walls.map((r) => r.slice());
    persist(m); draw();
  };
  $("save").onclick = save;
  $("save2").onclick = save;
  document.onkeydown = (e) => {
    if (e.key === "z" && (e.ctrlKey || e.metaKey)) {
      const step = undo.pop();
      if (step) { step(); draw(); }
      return;
    }
    if (e.key === "-") { level--; marks(); }
    if (e.key === "=" || e.key === "+") { level++; marks(); }
    if (/^[0-6]$/.test(e.key)) { level = +e.key; marks(); }
    if (e.key === "[") { scale = Math.max(1, scale - 1); draw(); }
    if (e.key === "]") { scale = Math.min(6, scale + 1); draw(); }
  };
  const c = $("art");
  let from = null;
  const cellOf = (e) => {
    const r = c.getBoundingClientRect();
    return [
      Math.floor((e.clientX - r.left) / (CELL * scale)),
      Math.floor((e.clientY - r.top) / (CELL * scale)),
    ];
  };
  c.onmousedown = (e) => { from = cellOf(e); e.preventDefault(); };
  c.onmouseup = (e) => {
    if (!from) return;
    paint(from, cellOf(e), e.shiftKey || wallMode);
    from = null;
  };
  load();
}

function marks() {
  level = Math.max(-2, Math.min(6, level));
  for (const el of document.querySelectorAll(".lv"))
    el.classList.toggle("on", +el.dataset.l === level);
}

function paint(a, b, wall) {
  const m = state(at);
  const x0 = Math.max(0, Math.min(a[0], b[0]));
  const x1 = Math.min(m.cells[0] - 1, Math.max(a[0], b[0]));
  const y0 = Math.max(0, Math.min(a[1], b[1]));
  const y1 = Math.min(m.cells[1] - 1, Math.max(a[1], b[1]));
  if (x1 < x0 || y1 < y0) return;
  const before = [];
  for (let y = y0; y <= y1; y++)
    for (let x = x0; x <= x1; x++)
      before.push([x, y, m._levels[y][x], m._walls[y][x]]);
  undo.push(() => {
    for (const [x, y, lv, w] of before) { m._levels[y][x] = lv; m._walls[y][x] = w; }
    persist(m);
  });
  for (let y = y0; y <= y1; y++)
    for (let x = x0; x <= x1; x++) {
      if (wall) m._walls[y][x] = m._walls[y][x] ? 0 : 1;
      else m._levels[y][x] = level;
    }
  persist(m); draw();
}

function load() {
  const m = state(at);
  // Fit the map to the window rather than fixing a zoom: these run from 20 cells
  // across to 40, and a cell has to stay big enough to hit with a drag.
  scale = Math.max(1, Math.min(4, Math.floor(1400 / (m.cells[0] * CELL))));
  img.onload = draw;
  img.src = m.art;
  marks(); draw();
}

function save() {
  const out = { maps: MAPS.map((m, i) => {
    const s = state(i);
    return { group: s.group, number: s.number, tileset: s.tileset,
             cells: s.cells, levels: s._levels, walls: s._walls };
  }) };
  const a = document.createElement("a");
  a.href = URL.createObjectURL(
    new Blob([JSON.stringify(out, null, 1)], { type: "application/json" }));
  a.download = "levels.json";
  a.click();
}

build();
</script>
"""


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    directory = pathlib.Path(sys.argv[1])
    maps = [json.loads(p.read_text())
            for p in sorted(directory.glob("level_*_*.json"))]
    if not maps:
        print("no level_*.json in %s: run tools/level_export.gd first" % directory)
        return 1
    missing = [m["art"] for m in maps if not (directory / m["art"]).exists()]
    if missing:
        print("missing map art beside the page: %s" % ", ".join(missing))
        print("run tools/map_art.gd for each, at scale 1")
        return 1
    out = directory / "levels.html"
    out.write_text(PAGE.replace("__MAPS__", json.dumps(maps)))
    print("%d maps, %d cells to paint over" % (
        len(maps), sum(m["cells"][0] * m["cells"][1] for m in maps)))
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
