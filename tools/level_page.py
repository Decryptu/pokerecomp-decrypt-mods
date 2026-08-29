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

THE UNIT IS THE WHOLE LEVEL, one walk cell, 16px. Half levels were offered and
withdrawn within the hour, for a reason worth keeping: these maps are not
consistent three-dimensional spaces. One lake has ground at different half
heights all the way round it, which no single water surface can meet. A half
step let a person write an impossibility down one cell at a time; whole levels
make them choose, which is the only thing that can be built.

WATER AND LEDGES ARE NOT PAINTED. Both live on single TILES, and a tile is a
quarter of a cell, which is why a cell can be half jumping ledge and half ground
or half water and half bank: the mesher resolves those tiles separately. The
paint says where the GROUND is and nothing else.

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
  <button id="brush">brush</button>
  <button id="rect">rectangle</button>
  <button id="fill">fill</button>
  <span class="grow"></span>
  <button id="reset">reset this map</button>
  <button id="save">SAVE levels.json</button>
</header>
<main>
  <div class="wrap"><canvas id="art"></canvas></div>
  <p class="hint">
    <b>Hold and drag to paint.</b> <kbd>B</kbd> brush, <kbd>R</kbd> rectangle,
    <kbd>F</kbd> fill,
    <kbd>0</kbd>-<kbd>5</kbd> pick a level, <kbd>-</kbd> and <kbd>=</kbd> step it,
    <kbd>W</kbd> the wall, <kbd>Ctrl</kbd>+<kbd>Z</kbd>
    undoes a whole stroke, <kbd>[</kbd> <kbd>]</kbd> zoom. Every cell shows its
    level and a colour; a cell you have changed carries a white dot. Painting a
    level over a wall clears the wall, which is how a wrong one is taken back.
  </p>
  <p class="hint">
    <b>Paint FLOORS only.</b> Paint the ground a thing stands ON and nothing
    about the thing: a house, a tree, a signpost and a cave entrance all take the
    level of the floor under them, because how tall they are is measured off
    their own drawing already.
  </p>
  <p class="hint">
    <b>A cell with a wave on it is water</b>, taken from the cartridge's own
    collision, so you never have to say which cells those are. What a level
    painted on one means is the level of the lake's SURFACE, and that is the one
    thing about a lake only you can settle: a lake with shores at different
    levels cannot exist, so you pick the one it sits at. The 8 pixels it is
    recessed by is a rendering choice of mine, not the cartridge's, and is not a
    level.
  </p>
  <p class="hint">
    <b>Whole levels only, and water and ledges are not painted.</b> A level is 16
    pixels. There is no half, because these maps are not consistent spaces: one
    lake has ground at different half heights all the way round it, and a half
    step only lets that impossibility be written down. Water, a jumping ledge and
    the little bank between water and ground are all single TILES, a quarter of a
    cell each, and the mesher gives each its own shape. Paint the level of the
    GROUND those things sit against and nothing else.
  </p>
  <p class="hint">
    <b>A wall is a TRANSITION, and it carries no level.</b> A hatched cell is
    where one level becomes another, so it has no number and cannot have one: a
    mass of wall stands at least as tall as the tallest floor it touches, which is how a
    cave&#39;s band becomes the cliff between its two storeys. A level and a wall
    are exclusive: painting either clears the other.
  </p>
  <p class="hint">
    <b>A tree or a house is not a wall.</b> It is a thing standing on a floor,
    and the floor under it is what you paint. Walls are pre-filled only from the
    cliff faces the mod already knows, which is why an outdoor map arrives with
    its rock wall marked and a CAVE arrives with nothing marked at all: whether a
    cave wall separates two levels is the question being asked. Use <kbd>F</kbd>
    to fill a whole rock mass in one click.
  </p>
</main>
<footer>
  <span class="chip" id="count"></span>
  <span class="grow"></span>
  <button id="save2">SAVE levels.json</button>
</footer>
<script>
const MAPS = __MAPS__;
const CELL = 16;
// WHOLE LEVELS ONLY, one walk cell of 16px each. Half levels were offered and
// withdrawn: these maps are not consistent three-dimensional spaces, and one
// lake has ground at different half heights all the way round it. A half step
// let a person write an impossibility down one cell at a time. Whole levels make
// them choose, which is the only thing that can be built.
// Up to 13, because a cave is two storeys and the wall between them is as many
// levels tall as the waterfall down it. Most maps use three of these.
const BANDS = [-1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13];
// A ramp a person can tell apart at a glance, low to high. EVERY level is
// tinted, including zero: leaving zero untinted was the first version and the
// reviewer could not see which cells they had painted, because most of a map is
// zero and an untinted cell reads as an unanswered one.
const COLORS = {
  "-1": "#4a63c8", "0": "#6b7280", "1": "#4fae4f", "2": "#d8c95a",
  "3": "#e09a4a", "4": "#d4603c", "5": "#c04a8a", "6": "#8f57c8",
  "7": "#3f8fd0", "8": "#2f9c8c", "9": "#7fb040", "10": "#b8a030",
  "11": "#b06a2c", "12": "#a03f3f", "13": "#8c3f70",
};
const WALL = "wall";
const TINT = 0.55;
let at = 0, band = 1, paintWall = false, scale = 3, tool = "brush";
const undo = [];

const label = (b) => String(b);

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
  g.textAlign = "center"; g.textBaseline = "middle";
  g.font = Math.floor(CELL * scale * 0.5) + "px -apple-system, sans-serif";
  for (let cy = 0; cy < m.cells[1]; cy++) {
    for (let cx = 0; cx < m.cells[0]; cx++) {
      const x = cx * CELL * scale, y = cy * CELL * scale, s = CELL * scale;
      const lv = m._levels[cy][cx];
      const isWall = m._walls[cy][cx] === 1;
      g.globalAlpha = TINT;
      g.fillStyle = isWall ? "#1a1a20" : (COLORS[String(lv)] || "#6b7280");
      g.fillRect(x, y, s, s); g.globalAlpha = 1;
      if (isWall) {
        g.strokeStyle = "rgba(255,255,255,0.6)"; g.lineWidth = 1;
        g.save(); g.beginPath(); g.rect(x, y, s, s); g.clip(); g.beginPath();
        for (let d = -s; d < s; d += 5) {
          g.moveTo(x + d, y); g.lineTo(x + d + s, y + s);
        }
        g.stroke(); g.restore();
      }
      // The number, so a level is readable and not only comparable. Drawn with
      // its own shadow because it sits over the cartridge's own art.
      // A wall carries NO number, because it carries no level: its height comes
      // from the floors either side of it. A number there is one that means
      // nothing and reads as though it does.
      if (s >= 22 && !isWall && lv !== null) {
        g.fillStyle = "rgba(0,0,0,0.75)";
        g.fillText(label(lv), x + s / 2 + 1, y + s / 2 + 1);
        g.fillStyle = "#fff";
        g.fillText(label(lv), x + s / 2, y + s / 2);
      }
      // Changed from the guess, so what you have touched is never in doubt.
      if (lv !== m.levels[cy][cx] || m._walls[cy][cx] !== m.walls[cy][cx]) {
        g.fillStyle = "#fff";
        g.beginPath();
        g.arc(x + s - Math.max(3, s * 0.14), y + Math.max(3, s * 0.14),
              Math.max(2, s * 0.075), 0, 6.284);
        g.fill();
      }
      // Water, marked and never asked for: the cartridge's own collision says
      // which cells these are. A level painted on one is the level of the lake's
      // SURFACE, which is the one thing about a lake a person has to choose.
      if (m.water && m.water[cy][cx]) {
        g.strokeStyle = "rgba(130,200,255,0.85)"; g.lineWidth = Math.max(1, s / 16);
        g.beginPath();
        const my = y + s * 0.78;
        for (let i = 0; i <= 4; i++) {
          const px = x + s * (0.18 + 0.16 * i);
          if (i === 0) g.moveTo(px, my);
          else g.quadraticCurveTo(px - s * 0.08, my + (i % 2 ? s * 0.07 : -s * 0.07), px, my);
        }
        g.stroke();
      }
      g.strokeStyle = "rgba(0,0,0,0.35)"; g.lineWidth = 1;
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
  // The wall is one more button on the same row, not a mode with a state to
  // remember. A mode you can leave switched on is a mode you paint fifty cells
  // through by mistake.
  $("palette").innerHTML = BANDS.map((b) =>
    `<span class="lv" data-l="${b}" style="background:${COLORS[String(b)]}">${label(b)}</span>`
  ).join("") +
    `<span class="lv" data-l="${WALL}" style="background:#2c2c34;color:#e8e8ee">wall</span>`;
  $("palette").onclick = (e) => {
    const el = e.target.closest(".lv");
    if (!el) return;
    if (el.dataset.l === WALL) { paintWall = true; }
    else { paintWall = false; band = +el.dataset.l; }
    marks();
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
    if (e.key === "-") { paintWall = false; band--; marks(); }
    if (e.key === "=" || e.key === "+") { paintWall = false; band++; marks(); }
    if (/^[0-5]$/.test(e.key)) { paintWall = false; band = +e.key; marks(); }
    if (e.key === "w" || e.key === "W") { paintWall = true; marks(); }
    if (e.key === "[") { scale = Math.max(1, scale - 1); draw(); }
    if (e.key === "]") { scale = Math.min(6, scale + 1); draw(); }
    if (e.key === "b" || e.key === "B") { tool = "brush"; tools(); }
    if (e.key === "r" || e.key === "R") { tool = "rect"; tools(); }
    if (e.key === "f" || e.key === "F") { tool = "fill"; tools(); }
  };
  $("brush").onclick = () => { tool = "brush"; tools(); };
  $("rect").onclick = () => { tool = "rect"; tools(); };
  $("fill").onclick = () => { tool = "fill"; tools(); };
  const c = $("art");
  let from = null;
  const cellOf = (e) => {
    const r = c.getBoundingClientRect();
    return [
      Math.floor((e.clientX - r.left) / (CELL * scale)),
      Math.floor((e.clientY - r.top) / (CELL * scale)),
    ];
  };
  c.onmousedown = (e) => {
    from = cellOf(e);
    open_stroke();
    if (tool === "brush") { paint(from, from, paintWall); }
    if (tool === "fill") { flood(from, paintWall); }
    e.preventDefault();
  };
  // Hold and drag. A brush paints every cell it crosses; a rectangle only
  // previews, and lands on release.
  c.onmousemove = (e) => {
    if (!from || tool !== "brush") return;
    const to = cellOf(e);
    paint(to, to, paintWall);
  };
  const finish = (e) => {
    if (!from) return;
    if (tool === "rect") paint(from, cellOf(e), paintWall);
    from = null;
    close_stroke();
  };
  c.onmouseup = finish;
  c.onmouseleave = finish;
  load();
}


function tools() {
  for (const k of ["brush", "rect", "fill"])
    $(k).style.borderColor = tool === k ? "#6ea8fe" : "#3a3a44";
}


// Everything joined to the cell clicked that reads the same as it does now. A
// cave is one rock mass and four hundred cells, and painting it a cell at a time
// is not a job worth giving a person.
function flood(seed, wall) {
  const m = state(at);
  const [sx, sy] = seed;
  if (sx < 0 || sy < 0 || sx >= m.cells[0] || sy >= m.cells[1]) return;
  const same = (x, y) =>
    m._walls[y][x] === m._walls[sy][sx] && m._levels[y][x] === m._levels[sy][sx];
  if (m._walls[sy][sx] === (wall ? 1 : 0)
      && (wall || m._levels[sy][sx] === band)) return;
  const seen = new Set();
  const stack = [[sx, sy]];
  seen.add(sy * m.cells[0] + sx);
  const hit = [];
  while (stack.length) {
    const [x, y] = stack.pop();
    hit.push([x, y]);
    for (const [dx, dy] of [[1,0],[-1,0],[0,1],[0,-1]]) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= m.cells[0] || ny >= m.cells[1]) continue;
      const key = ny * m.cells[0] + nx;
      if (seen.has(key) || !same(nx, ny)) continue;
      seen.add(key);
      stack.push([nx, ny]);
    }
  }
  for (const [x, y] of hit) paint([x, y], [x, y], wall);
}


// One undo entry per STROKE, not per cell: a brush drag touches a hundred cells
// and undoing them one at a time is not undo.
let stroke = null;

function open_stroke() { stroke = []; }

function close_stroke() {
  if (stroke && stroke.length) {
    const m = state(at), done = stroke;
    undo.push(() => {
      for (const [x, y, lv, w] of done) { m._levels[y][x] = lv; m._walls[y][x] = w; }
      persist(m);
    });
  }
  stroke = null;
}

function marks() {
  band = Math.max(BANDS[0], Math.min(BANDS[BANDS.length - 1], band));
  for (const el of document.querySelectorAll(".lv"))
    el.classList.toggle("on",
      paintWall ? el.dataset.l === WALL : +el.dataset.l === band);
}

function paint(a, b, wall) {
  const m = state(at);
  const x0 = Math.max(0, Math.min(a[0], b[0]));
  const x1 = Math.min(m.cells[0] - 1, Math.max(a[0], b[0]));
  const y0 = Math.max(0, Math.min(a[1], b[1]));
  const y1 = Math.min(m.cells[1] - 1, Math.max(a[1], b[1]));
  if (x1 < x0 || y1 < y0) return;
  let moved = false;
  for (let y = y0; y <= y1; y++)
    for (let x = x0; x <= x1; x++) {
      // A LEVEL AND A WALL ARE EXCLUSIVE. A cell is a floor at some level or it
      // is the transition between two, never both, and letting it be both put a
      // number under a wall that nothing would ever read. A wall PAINTS rather
      // than toggles, or a brush crossing one cell twice would set it and unset
      // it again; painting a level over a wall is how a wrong one is taken back.
      const lv = wall ? null : band;
      const w = wall ? 1 : 0;
      if (lv === m._levels[y][x] && w === m._walls[y][x]) continue;
      if (stroke) stroke.push([x, y, m._levels[y][x], m._walls[y][x]]);
      m._levels[y][x] = lv;
      m._walls[y][x] = w;
      moved = true;
    }
  if (!moved) return;
  persist(m); draw();
}

function load() {
  const m = state(at);
  // Fit the map to the window rather than fixing a zoom: these run from 20 cells
  // across to 40, and a cell has to stay big enough to hit with a drag.
  scale = Math.max(1, Math.min(4, Math.floor(1400 / (m.cells[0] * CELL))));
  img.onload = draw;
  img.src = m.art;
  marks(); tools(); draw();
}

function save() {
  // The unit travels WITH the numbers, so nothing downstream has to guess what
  // a 2 counts.
  const out = { unit: "level16", pixels_per_level: 16, maps: MAPS.map((m, i) => {
    const s = state(i);
    return { group: s.group, number: s.number, tileset: s.tileset,
             cells: s.cells, levels: s._levels, walls: s._walls };
  })};
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
        # Named rather than described: `map_art.gd` writes whatever path it is
        # given, and the name this page looks for is not the one that tool's own
        # examples use, so "run map_art.gd" on its own has sent two sessions
        # round the loop again with the file sitting right there under the other
        # name.
        print("run tools/map_art.gd at scale 1, writing each to that exact name")
        return 1
    out = directory / "levels.html"
    out.write_text(PAGE.replace("__MAPS__", json.dumps(maps)))
    print("%d maps, %d cells to paint over" % (
        len(maps), sum(m["cells"][0] * m["cells"][1] for m in maps)))
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
