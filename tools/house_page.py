#!/usr/bin/env python3
"""The page a reviewer PAINTS the houses on.

A house is the one drawing in Generation II that packs three different surfaces
into one flat picture: a wall seen face-on, a roof seen from above, and the front
pitch of a roof drawn face-on as well. Nothing measurable tells them apart, which
is why every house in the game is either a barn or a block until a person says
which tiles are which. So it is painted, exactly as the ground levels are.

    tools/house_page.py <houses dir>      # writes <houses dir>/houses.html

The directory is what `tools/house_export.gd` wrote: one JSON, one picture of the
drawing and one picture of it RINGED where the cartridge places it, per drawing.

THE UNIT IS THE GRAPHICS TILE, 8px, because that is what a band of the fold is: a
facade stands up a tile row at a time and a roof falls a tile at a time. The
level page paints walk CELLS because a level is a cell; this one would be asking
one answer for four tiles.

PAINT PER DRAWING, NOT PER PLACEMENT. There are 112 drawings and 243 placements,
and the identity is the rectangle of tile ids: two placements of one house carry
the same rectangle, so one painting serves every one of them. Twenty drawings
carry more than half the placements, which is the order they are shown in.

PRE-FILLED with what the mod already resolves, so the job is correcting a
proposal rather than painting from blank, and the DOORS arrive named by the
cartridge itself: a door is a warp, and 72 of the 112 drawings hold one.

SAVE writes `houses.json`: per drawing, the tile grid and the painted grid, ready
for `tools/house_pins.gd` to turn into a checked-in table.
"""

import json
import pathlib
import sys

PAGE = """<!doctype html>
<meta charset="utf-8">
<title>voxel3d houses</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; background: #16161a; color: #e8e8ee;
         font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  header { display: flex; gap: 12px; align-items: center; flex-wrap: wrap;
           padding: 10px 18px; border-bottom: 1px solid #2c2c34;
           position: sticky; top: 0; background: #16161af2; z-index: 5; }
  header h1 { font-size: 15px; margin: 0; font-weight: 600; }
  .grow { flex: 1; }
  select, button { font: inherit; color: inherit; background: #23232b;
      border: 1px solid #3a3a44; border-radius: 6px; padding: 6px 10px;
      cursor: pointer; }
  button:hover { background: #2e2e38; }
  main { padding: 16px 18px 90px; }
  .row { display: flex; gap: 22px; align-items: flex-start; flex-wrap: wrap; }
  .wrap { border: 1px solid #2c2c34; border-radius: 8px; overflow: hidden;
          display: inline-block; }
  canvas, img.ctx { display: block; image-rendering: pixelated; }
  canvas { cursor: crosshair; }
  .paints { display: flex; gap: 6px; flex-wrap: wrap; align-items: center; }
  .pt { height: 34px; border-radius: 6px; border: 2px solid #3a3a44;
        display: flex; align-items: center; justify-content: center; gap: 6px;
        padding: 0 10px; font-weight: 600; cursor: pointer; color: #000;
        font-size: 13px; }
  .pt.on { border-color: #fff; box-shadow: 0 0 0 2px #6ea8fe; }
  .hint { color: #8d8da0; font-size: 13px; margin: 8px 0 0; max-width: 92ch; }
  .hint b { color: #c9c9d8; }
  kbd { background: #23232b; border: 1px solid #3a3a44; border-radius: 4px;
        padding: 1px 5px; font-size: 12px; }
  footer { position: fixed; bottom: 0; left: 0; right: 0; padding: 10px 18px;
           background: #16161af2; border-top: 1px solid #2c2c34;
           display: flex; gap: 14px; align-items: center; z-index: 5; }
  .chip { display: inline-block; background: #23232b; border: 1px solid #3a3a44;
          border-radius: 999px; padding: 3px 10px; font-size: 13px; color: #a8a8bb; }
  .cap { color: #8d8da0; font-size: 12px; padding: 4px 2px 0; }
</style>
<header>
  <h1>voxel3d houses</h1>
  <select id="pick"></select>
  <button id="prev">&#8592;</button>
  <button id="next">&#8594;</button>
  <span class="paints" id="palette"></span>
  <button id="brush">brush</button>
  <button id="rect">rectangle</button>
  <button id="fill">fill</button>
  <span class="grow"></span>
  <button id="reset">reset this house</button>
  <button id="save">SAVE houses.json</button>
</header>
<main>
  <div class="row">
    <div>
      <div class="wrap"><canvas id="art"></canvas></div>
      <div class="cap" id="cap"></div>
    </div>
    <div>
      <div class="wrap"><img class="ctx" id="ctx"></div>
      <div class="cap">where the cartridge puts it, ringed</div>
    </div>
  </div>
  <p class="hint">
    <b>Hold and drag to paint.</b> <kbd>B</kbd> brush, <kbd>R</kbd> rectangle,
    <kbd>F</kbd> fill, <kbd>Ctrl</kbd>+<kbd>Z</kbd> undoes a whole stroke,
    <kbd>X</kbd> takes the paint off so the drawing can be seen bare,
    <kbd>[</kbd> <kbd>]</kbd> zoom, <kbd>&#8592;</kbd> <kbd>&#8594;</kbd> the
    house before and after. Every square is one 8-pixel graphics tile; the
    heavier lines are the walk cells the player moves on. A tile you have changed
    from the guess carries a white dot.
  </p>
  <p class="hint">
    <b>wall</b> is the front of the house, drawn face-on. It stands straight up
    out of the ground.
    <b>roof</b> is the roof drawn from above, lying flat on top of the walls.
    <b>roof falling</b> is roof from above that slopes down toward the arrow, so
    paint the arrow pointing the way the water would run off; how steep it is
    comes from how many tiles you paint, not from a number.
    <b>pitch</b> is the roof drawn from the FRONT rather than from above, the way
    a wooden house shows you its planks: it leans back over the house instead of
    standing up like a wall.
    <b>door</b> is the doorway: it stands up wearing its own drawing like the
    wall around it, and the player still walks straight through it, because
    nothing here touches collision.
    <b>not the house</b> is anything in the rectangle that is not the building at
    all: the pavement, the shadow it throws, the grass beside it.
  </p>
  <p class="hint">
    <b>One painting serves every placement.</b> A house is identified by its grid
    of tiles, so painting this one paints all of them, however many towns it
    stands in. The count beside the name is how many times the game places it.
  </p>
</main>
<footer>
  <span class="chip" id="count"></span>
  <span class="grow"></span>
  <button id="save2">SAVE houses.json</button>
</footer>
<script>
const HOUSES = __HOUSES__;
const TILE = 8;
// THE VOCABULARY IS WHAT THE MESHER CAN BUILD and nothing else. A word with no
// geometry behind it is a question nobody can answer with a mesh.
const PAINTS = [
  { k: ".", label: "not the house", color: "#6b7280", key: "0" },
  { k: "W", label: "wall",          color: "#5b8dd6", key: "1" },
  { k: "R", label: "roof",          color: "#d8934a", key: "2" },
  { k: "<", label: "falling",       color: "#e0c04a", key: "3", arrow: "\\u2190" },
  { k: ">", label: "falling",       color: "#e0c04a", key: "4", arrow: "\\u2192" },
  { k: "^", label: "falling",       color: "#e0c04a", key: "5", arrow: "\\u2191" },
  { k: "v", label: "falling",       color: "#e0c04a", key: "6", arrow: "\\u2193" },
  { k: "P", label: "pitch",         color: "#a878d8", key: "7" },
  { k: "D", label: "door",          color: "#57b86b", key: "8" },
];
const BY_KEY = {};
for (const p of PAINTS) BY_KEY[p.k] = p;
// LIGHT ON PURPOSE. The first version washed each tile at half opacity with a
// letter across it and the cartridge's own drawing could not be read underneath,
// which defeats the page: a person can only say what a tile depicts if they can
// see it. The colour is carried by a border and a small glyph instead, and X
// takes the paint off entirely.
const TINT = 0.24;
let at = 0, paint_kind = "W", scale = 6, tool = "brush", bare = false;
const undo = [];

const $ = (id) => document.getElementById(id);
const KEY = "voxel3dhouses:";
const store = {};
try {
  for (let i = 0; i < localStorage.length; i++) {
    const k = localStorage.key(i);
    if (k.startsWith(KEY)) store[k] = localStorage.getItem(k);
  }
} catch (e) {}

function state(i) {
  const h = HOUSES[i];
  if (!h._paint) {
    let saved = null;
    try { saved = store[KEY + h.id] ? JSON.parse(store[KEY + h.id]) : null; } catch (e) {}
    h._paint = saved ? saved : h.paint.map((r) => r.slice());
  }
  return h;
}

function persist(h) {
  try { localStorage.setItem(KEY + h.id, JSON.stringify(h._paint)); } catch (e) {}
  tally();
}

const img = new Image();

function draw() {
  const h = state(at);
  const c = $("art"), g = c.getContext("2d");
  const w = h.size[0], t = h.size[1];
  c.width = w * TILE * scale; c.height = t * TILE * scale;
  g.imageSmoothingEnabled = false;
  if (img.complete && img.naturalWidth) g.drawImage(img, 0, 0, c.width, c.height);
  const s = TILE * scale;
  g.textAlign = "center"; g.textBaseline = "middle";
  g.font = "700 " + Math.floor(s * 0.38) + "px -apple-system, sans-serif";
  if (bare) return;
  for (let ty = 0; ty < t; ty++) {
    for (let tx = 0; tx < w; tx++) {
      const x = tx * s, y = ty * s;
      const k = h._paint[ty][tx];
      const p = BY_KEY[k] || BY_KEY["."];
      g.globalAlpha = k === "." ? TINT * 0.5 : TINT;
      g.fillStyle = p.color;
      g.fillRect(x, y, s, s);
      g.globalAlpha = 1;
      // The colour rides on the BORDER rather than on the fill, so the drawing
      // stays readable through it.
      if (k !== ".") {
        g.strokeStyle = p.color; g.lineWidth = 2;
        g.strokeRect(x + 1, y + 1, s - 2, s - 2);
        const glyph = p.arrow || k;
        g.fillStyle = "rgba(0,0,0,0.85)";
        g.fillText(glyph, x + s / 2 + 1, y + s / 2 + 1);
        g.fillStyle = p.color;
        g.fillText(glyph, x + s / 2, y + s / 2);
      }
      if (k !== h.paint[ty][tx]) {
        g.fillStyle = "#fff";
        g.beginPath();
        g.arc(x + s - Math.max(3, s * 0.13), y + Math.max(3, s * 0.13),
              Math.max(2, s * 0.07), 0, 6.284);
        g.fill();
      }
      g.strokeStyle = "rgba(0,0,0,0.30)"; g.lineWidth = 1;
      g.strokeRect(x + 0.5, y + 0.5, s - 1, s - 1);
    }
  }
  // The walk CELL is two tiles, and it is the grid the player moves on: a door
  // is a whole cell and so is a step of height, so the heavier line is what says
  // whether a painted band lines up with anything the world can do.
  g.strokeStyle = "rgba(255,255,255,0.45)"; g.lineWidth = 2;
  for (let cx = 0; cx <= w; cx += 2) {
    g.beginPath(); g.moveTo(cx * s, 0); g.lineTo(cx * s, c.height); g.stroke();
  }
  for (let cy = 0; cy <= t; cy += 2) {
    g.beginPath(); g.moveTo(0, cy * s); g.lineTo(c.width, cy * s); g.stroke();
  }
}

function tally() {
  let touched = 0, placements = 0, total = 0;
  for (let i = 0; i < HOUSES.length; i++) {
    const h = state(i);
    total += h.placements;
    let moved = false;
    for (let y = 0; y < h.size[1]; y++)
      for (let x = 0; x < h.size[0]; x++)
        if (h._paint[y][x] !== h.paint[y][x]) moved = true;
    if (moved) { touched++; placements += h.placements; }
  }
  $("count").textContent =
    `${touched} of ${HOUSES.length} drawings corrected, covering ` +
    `${placements} of ${total} placements`;
  options();
}

function options() {
  $("pick").innerHTML = HOUSES.map((h, i) => {
    const s = state(i);
    let moved = false;
    for (let y = 0; y < s.size[1]; y++)
      for (let x = 0; x < s.size[0]; x++)
        if (s._paint[y][x] !== s.paint[y][x]) moved = true;
    return `<option value="${i}"${i === at ? " selected" : ""}>` +
      `${moved ? "\\u2713 " : ""}#${s.id} \\u00b7 tileset ${s.tileset} \\u00b7 ` +
      `${s.cells[0]}x${s.cells[1]} cells \\u00b7 ${s.placements} placements` +
      `</option>`;
  }).join("");
}

function marks() {
  for (const el of document.querySelectorAll(".pt"))
    el.classList.toggle("on", el.dataset.k === paint_kind);
}

function tools() {
  for (const k of ["brush", "rect", "fill"])
    $(k).style.borderColor = tool === k ? "#6ea8fe" : "#3a3a44";
}

let stroke = null;
function open_stroke() { stroke = []; }
function close_stroke() {
  if (stroke && stroke.length) {
    const h = state(at), done = stroke;
    undo.push(() => {
      for (const [x, y, k] of done) h._paint[y][x] = k;
      persist(h);
    });
  }
  stroke = null;
}

function apply(a, b) {
  const h = state(at);
  const x0 = Math.max(0, Math.min(a[0], b[0]));
  const x1 = Math.min(h.size[0] - 1, Math.max(a[0], b[0]));
  const y0 = Math.max(0, Math.min(a[1], b[1]));
  const y1 = Math.min(h.size[1] - 1, Math.max(a[1], b[1]));
  if (x1 < x0 || y1 < y0) return;
  let moved = false;
  for (let y = y0; y <= y1; y++)
    for (let x = x0; x <= x1; x++) {
      if (h._paint[y][x] === paint_kind) continue;
      if (stroke) stroke.push([x, y, h._paint[y][x]]);
      h._paint[y][x] = paint_kind;
      moved = true;
    }
  if (!moved) return;
  persist(h); draw();
}

// Everything joined to the tile clicked that reads the same as it does now. A
// roof is forty tiles of one word and painting it a tile at a time is not a job
// worth giving a person.
function flood(seedx, seedy) {
  const h = state(at);
  if (seedx < 0 || seedy < 0 || seedx >= h.size[0] || seedy >= h.size[1]) return;
  const from = h._paint[seedy][seedx];
  if (from === paint_kind) return;
  const seen = new Set([seedy * h.size[0] + seedx]);
  const stack = [[seedx, seedy]];
  while (stack.length) {
    const [x, y] = stack.pop();
    apply([x, y], [x, y]);
    for (const [dx, dy] of [[1,0],[-1,0],[0,1],[0,-1]]) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= h.size[0] || ny >= h.size[1]) continue;
      const key = ny * h.size[0] + nx;
      if (seen.has(key) || h._paint[ny][nx] !== from) continue;
      seen.add(key);
      stack.push([nx, ny]);
    }
  }
}

function load() {
  const h = state(at);
  scale = Math.max(3, Math.min(12, Math.floor(760 / (h.size[0] * TILE))));
  img.onload = draw;
  img.src = h.art;
  // Doubled, because the street around the ring is what makes the drawing
  // readable and 8px tiles at natural size are not.
  const ctx = $("ctx");
  ctx.onload = () => { ctx.style.width = ctx.naturalWidth * 2 + "px"; };
  ctx.src = h.context;
  $("cap").textContent =
    `#${h.id} \\u00b7 tileset ${h.tileset} \\u00b7 ${h.size[0]}x${h.size[1]} tiles ` +
    `(${h.cells[0]}x${h.cells[1]} cells) \\u00b7 placed ${h.placements} times on ` +
    `${h.maps.length} maps \\u00b7 first at ${h.where}`;
  options(); marks(); tools(); draw();
}

function go(step) {
  at = Math.max(0, Math.min(HOUSES.length - 1, at + step));
  load();
}

function build() {
  $("palette").innerHTML = PAINTS.map((p) =>
    `<span class="pt" data-k="${p.k}" style="background:${p.color}">` +
    `${p.arrow || ""}${p.arrow ? " " : ""}${p.label}</span>`).join("");
  $("palette").onclick = (e) => {
    const el = e.target.closest(".pt");
    if (!el) return;
    paint_kind = el.dataset.k;
    marks();
  };
  $("pick").onchange = () => { at = +$("pick").value; load(); };
  $("prev").onclick = () => go(-1);
  $("next").onclick = () => go(1);
  $("reset").onclick = () => {
    const h = state(at);
    h._paint = h.paint.map((r) => r.slice());
    persist(h); draw();
  };
  $("save").onclick = save;
  $("save2").onclick = save;
  $("brush").onclick = () => { tool = "brush"; tools(); };
  $("rect").onclick = () => { tool = "rect"; tools(); };
  $("fill").onclick = () => { tool = "fill"; tools(); };
  document.onkeydown = (e) => {
    if (e.target.tagName === "SELECT") return;
    if (e.key === "z" && (e.ctrlKey || e.metaKey)) {
      const step = undo.pop();
      if (step) { step(); draw(); }
      return;
    }
    for (const p of PAINTS) if (e.key === p.key) { paint_kind = p.k; marks(); }
    if (e.key === "[") { scale = Math.max(2, scale - 1); draw(); }
    if (e.key === "]") { scale = Math.min(14, scale + 1); draw(); }
    if (e.key === "x" || e.key === "X") { bare = !bare; draw(); }
    if (e.key === "b" || e.key === "B") { tool = "brush"; tools(); }
    if (e.key === "r" || e.key === "R") { tool = "rect"; tools(); }
    if (e.key === "f" || e.key === "F") { tool = "fill"; tools(); }
    if (e.key === "ArrowLeft") go(-1);
    if (e.key === "ArrowRight") go(1);
  };
  const c = $("art");
  let from = null;
  const tileOf = (e) => {
    const r = c.getBoundingClientRect();
    return [
      Math.floor((e.clientX - r.left) / (TILE * scale)),
      Math.floor((e.clientY - r.top) / (TILE * scale)),
    ];
  };
  c.onmousedown = (e) => {
    from = tileOf(e);
    open_stroke();
    if (tool === "brush") apply(from, from);
    if (tool === "fill") flood(from[0], from[1]);
    e.preventDefault();
  };
  // A brush paints every tile it crosses; a rectangle lands on release.
  c.onmousemove = (e) => {
    if (!from || tool !== "brush") return;
    const to = tileOf(e);
    apply(to, to);
  };
  const finish = (e) => {
    if (!from) return;
    if (tool === "rect") apply(from, tileOf(e));
    from = null;
    close_stroke();
  };
  c.onmouseup = finish;
  c.onmouseleave = finish;
  load(); tally();
}

function save() {
  // The vocabulary travels WITH the painting, so nothing downstream has to guess
  // what a symbol means.
  const out = {
    unit: "tile8",
    legend: Object.fromEntries(PAINTS.map((p) =>
      [p.k, p.arrow ? p.label + " " + p.arrow : p.label])),
    houses: HOUSES.map((h, i) => {
      const s = state(i);
      // The GUESS travels with the painting, because what makes a table an
      // override is knowing which drawings a person actually changed: one left
      // exactly as it came is one the mod already reads correctly, and writing
      // it down would only pin today's behaviour for no reason.
      return { id: s.id, tileset: s.tileset, size: s.size, tiles: s.tiles,
               placements: s.placements, maps: s.maps, where: s.where,
               guess: s.paint, paint: s._paint };
    }),
  };
  const a = document.createElement("a");
  a.href = URL.createObjectURL(
    new Blob([JSON.stringify(out, null, 1)], { type: "application/json" }));
  a.download = "houses.json";
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
    houses = [json.loads(p.read_text())
              for p in sorted(directory.glob("house_*.json"))]
    if not houses:
        print("no house_*.json in %s: run tools/house_export.gd first" % directory)
        return 1
    houses.sort(key=lambda h: h["id"])
    missing = [h["art"] for h in houses if not (directory / h["art"]).exists()]
    missing += [h["context"] for h in houses if not (directory / h["context"]).exists()]
    if missing:
        print("missing pictures beside the page: %s" % ", ".join(missing[:6]))
        return 1
    out = directory / "houses.html"
    out.write_text(PAGE.replace("__HOUSES__", json.dumps(houses)))
    print("%d drawings, %d placements, %d tiles to paint over" % (
        len(houses), sum(h["placements"] for h in houses),
        sum(h["size"][0] * h["size"][1] for h in houses)))
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
