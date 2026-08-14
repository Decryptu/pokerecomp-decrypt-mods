#!/usr/bin/env python3
"""The page a reviewer PAINTS the houses on, one PIXEL at a time.

A house is the one drawing in Generation II that packs different surfaces into
one flat picture: the wall, which you are looking AT, and the roof, which you
are either looking DOWN onto or looking at from the FRONT. Nothing measurable
tells them apart, so a person says which is which.

    tools/house_page.py <houses dir>      # writes <houses dir>/houses.html

The directory is what `tools/house_export.gd` wrote: one JSON, one picture of the
drawing and one picture of it RINGED where the cartridge places it, per drawing.

THE UNIT IS THE PIXEL, NOT THE TILE, and that is the whole difference from the
first version of this page. A hipped roof's end comes down as a DIAGONAL across
its tiles, so a tile there is part roof and part wall, and no answer at tile
resolution is right: "roof" lifts the wall's top onto the roof and "wall" cuts
the corner off the roof. The reviewer said so and they were right.

SO THE WAND DOES THE WORK, NOT THE HAND. Painting 3000 pixels a house is not a
job worth giving anybody. One click floods the drawing's own shape: it runs
through every pixel that is not part of the outline, which is how this mod
already cuts a drawing out of its background, and then swallows the outline
around it. A roof and its dither and its diagonal end come out in one click.

FOUR WORDS AND NO MORE, and each is a fact about the drawing rather than a term
of art:

    wall              you are looking AT it. It stands up.
    roof              you are looking DOWN onto it. It lies flat on the walls.
    roof, from front  the roof drawn face-on, so you see its planks edge-on
                      rather than its surface. It leans back over the house.
    not the house     the pavement, the shadow, the grass in the corner.

There is no word for a door and there deliberately is not: a door is a wall the
player walks through, and walking through is the collision's business, which
nothing here touches. It arrives painted as wall already, because the cartridge
names every door itself as a warp.

There is no word for a SLOPE either. How far a roof has fallen is already
measured from the drawing and pinned from the reviewer's own tileset 3
measurements, so asking for it again would be asking twice.

SAVE writes `houses.json`: per drawing, one string per pixel row, ready for
`tools/house_pins.gd`.
"""

import base64
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
  header { display: flex; gap: 10px; align-items: center; flex-wrap: wrap;
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
  .wrap { border: 1px solid #2c2c34; border-radius: 8px; overflow: auto;
          display: inline-block; max-width: 96vw; }
  canvas, img.ctx { display: block; image-rendering: pixelated; }
  canvas { cursor: crosshair; }
  .paints { display: flex; gap: 6px; flex-wrap: wrap; align-items: center; }
  .pt { height: 32px; border-radius: 6px; border: 2px solid #3a3a44;
        display: flex; align-items: center; padding: 0 10px; font-weight: 600;
        cursor: pointer; color: #000; font-size: 13px; }
  .pt.on { border-color: #fff; box-shadow: 0 0 0 2px #6ea8fe; }
  .hint { color: #8d8da0; font-size: 13px; margin: 8px 0 0; max-width: 96ch; }
  .hint b { color: #c9c9d8; }
  kbd { background: #23232b; border: 1px solid #3a3a44; border-radius: 4px;
        padding: 1px 5px; font-size: 12px; }
  footer { position: fixed; bottom: 0; left: 0; right: 0; padding: 10px 18px;
           background: #16161af2; border-top: 1px solid #2c2c34;
           display: flex; gap: 14px; align-items: center; z-index: 5; }
  .chip { display: inline-block; background: #23232b; border: 1px solid #3a3a44;
          border-radius: 999px; padding: 3px 10px; font-size: 13px; color: #a8a8bb; }
  .cap { color: #8d8da0; font-size: 12px; padding: 4px 2px 0; }
  .on { border-color: #6ea8fe; }
</style>
<header>
  <h1>voxel3d houses</h1>
  <select id="pick"></select>
  <button id="prev">&#8592;</button>
  <button id="next">&#8594;</button>
  <span class="paints" id="palette"></span>
  <span class="grow"></span>
  <button id="reset">reset</button>
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
    <span id="tools"></span>
  </p>
  <p class="hint">
    <b>Use the wand.</b> One click floods the shape you clicked in, following the
    drawing's own outline, so a whole roof with its dither and its diagonal ends
    comes out in one go. If it takes too much or too little, undo with
    <kbd>Ctrl</kbd>+<kbd>Z</kbd> and use the brush. <kbd>1</kbd>-<kbd>4</kbd>
    pick a word, <kbd>W</kbd> wand, <kbd>B</kbd> brush, <kbd>R</kbd> rectangle,
    <kbd>[</kbd> <kbd>]</kbd> zoom, <kbd>,</kbd> <kbd>.</kbd> brush size,
    <kbd>X</kbd> hides the paint so the drawing can be seen bare,
    <kbd>G</kbd> hides the grid, <kbd>&#8592;</kbd> <kbd>&#8594;</kbd> the house
    before and after.
  </p>
  <p class="hint">
    <b>wall</b> is anything you are looking AT face-on. It stands straight up.
    <b>roof</b> is roof you are looking DOWN onto, lying flat on top of the
    walls.
    <b>roof, from the front</b> is the roof drawn face-on instead, the way a
    wooden house shows you its planks edge-on: it is roof, but it has to lean
    back over the house rather than stand up like a wall. Most houses do not
    have any.
    <b>not the house</b> is everything in the box that is not the building: the
    pavement, the shadow it throws, the grass left in the corner of a tile where
    the roof comes down diagonally.
  </p>
  <p class="hint">
    <b>There is no word for a door, and none for a slope.</b> A door is a wall
    the player walks through, and walking through is collision, which nothing
    here touches, so a door is just wall and arrives painted that way already.
    How far a roof has fallen is already measured from the drawing, and on
    tileset 3 it is measured from your own answers, so you are not asked twice.
  </p>
  <p class="hint">
    <b>Ordered by how much of the game they cover, so stop whenever you like.</b>
    One painting serves every placement, because a house is identified by its
    grid of tiles. The first twenty carry more than half the placements in the
    game. Anything left alone keeps the reading the mod already has.
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
// FOUR WORDS, each a fact about the drawing rather than a term of art. The first
// version of this page had nine, including "pitch" and four falling arrows, and
// the reviewer could not use any of them: a slope is measured already, and a
// door is a wall.
const PAINTS = [
  { k: "W", label: "wall",               color: "#5b8dd6", key: "1" },
  { k: "R", label: "roof",               color: "#d8934a", key: "2" },
  { k: "F", label: "roof, from the front", color: "#a878d8", key: "3" },
  { k: ".", label: "not the house",      color: "#6b7280", key: "4" },
];
const BY_KEY = {};
for (const p of PAINTS) BY_KEY[p.k] = p;
// LIGHT ON PURPOSE. The drawing is the thing being judged, so the paint has to
// be readable THROUGH: a wash heavy enough to name a region is heavy enough to
// hide what makes it one.
const TINT = 0.42;
let at = 0, kind = "W", scale = 8, tool = "wand", brush = 2;
let bare = false, grid = true;
const undo = [];

const $ = (id) => document.getElementById(id);
const KEY = "voxel3dhousepx:";
const store = {};
try {
  for (let i = 0; i < localStorage.length; i++) {
    const k = localStorage.key(i);
    if (k.startsWith(KEY)) store[k] = localStorage.getItem(k);
  }
} catch (e) {}

// WHICH PIXELS ARE THE DRAWING'S OUTLINE, which is all the wand needs to know.
// It is EXPORTED as data rather than read back off the canvas, and that is the
// fix for a real bug rather than a preference: reading pixels off a canvas is
// same-origin work, and a page opened as a LOCAL FILE cannot do it to a local
// image. The first version read the canvas, so it worked perfectly served over
// http and drew a blank rectangle the way a person actually opens it. Nothing
// here reads a pixel now, so there is no origin left to be wrong about.
let W = 0, H = 0, outline = null;

// The pre-fill, expanded from the tile reading the mod already has. A tile word
// covers all 64 of its pixels, which is exactly today's answer and therefore
// exactly the right thing to correct.
function guessOf(h) {
  const g = [];
  for (let y = 0; y < h.size[1] * TILE; y++) {
    const row = new Array(h.size[0] * TILE);
    for (let x = 0; x < h.size[0] * TILE; x++) {
      const t = h.paint[(y / TILE) | 0][(x / TILE) | 0];
      // A door is a wall the player walks through, so it arrives as wall; the
      // falling arrows the first page asked for are all just roof.
      row[x] = t === "D" ? "W" : (t === "P" ? "F"
        : (t === "W" || t === "." ? t : "R"));
    }
    g.push(row.join(""));
  }
  return g;
}

function state(i) {
  const h = HOUSES[i];
  if (!h._guess) h._guess = guessOf(h);
  if (!h._paint) {
    let saved = null;
    try { saved = store[KEY + h.id] ? JSON.parse(store[KEY + h.id]) : null; } catch (e) {}
    h._paint = (saved && saved.length === h._guess.length)
      ? saved.map((r) => r.split(""))
      : h._guess.map((r) => r.split(""));
  }
  return h;
}

function persist(h) {
  try {
    localStorage.setItem(KEY + h.id, JSON.stringify(h._paint.map((r) => r.join(""))));
  } catch (e) {}
  tally();
}

const img = new Image();

function draw() {
  const h = state(at);
  const c = $("art"), g = c.getContext("2d");
  const w = h.size[0] * TILE, t = h.size[1] * TILE;
  c.width = w * scale; c.height = t * scale;
  g.imageSmoothingEnabled = false;
  if (img.complete && img.naturalWidth) g.drawImage(img, 0, 0, c.width, c.height);
  if (!bare) {
    for (let y = 0; y < t; y++) {
      const row = h._paint[y];
      for (let x = 0; x < w; x++) {
        const p = BY_KEY[row[x]];
        if (!p || row[x] === ".") continue;
        g.globalAlpha = TINT;
        g.fillStyle = p.color;
        g.fillRect(x * scale, y * scale, scale, scale);
      }
    }
    g.globalAlpha = 1;
  }
  if (!grid) return;
  // The TILE is what the mesher folds a band at a time, and the walk CELL is
  // what the player moves on, so both lines are worth seeing while painting
  // something finer than either.
  g.strokeStyle = "rgba(0,0,0,0.30)"; g.lineWidth = 1;
  for (let x = 0; x <= h.size[0]; x++) {
    g.beginPath(); g.moveTo(x*TILE*scale, 0); g.lineTo(x*TILE*scale, c.height); g.stroke();
  }
  for (let y = 0; y <= h.size[1]; y++) {
    g.beginPath(); g.moveTo(0, y*TILE*scale); g.lineTo(c.width, y*TILE*scale); g.stroke();
  }
  g.strokeStyle = "rgba(255,255,255,0.40)"; g.lineWidth = 2;
  for (let x = 0; x <= h.size[0]; x += 2) {
    g.beginPath(); g.moveTo(x*TILE*scale, 0); g.lineTo(x*TILE*scale, c.height); g.stroke();
  }
  for (let y = 0; y <= h.size[1]; y += 2) {
    g.beginPath(); g.moveTo(0, y*TILE*scale); g.lineTo(c.width, y*TILE*scale); g.stroke();
  }
}

function moved(h) {
  for (let y = 0; y < h._paint.length; y++) {
    const a = h._paint[y], b = h._guess[y];
    for (let x = 0; x < a.length; x++) if (a[x] !== b[x]) return true;
  }
  return false;
}

function tally() {
  let touched = 0, covered = 0, total = 0;
  for (let i = 0; i < HOUSES.length; i++) {
    const h = state(i);
    total += h.placements;
    if (moved(h)) { touched++; covered += h.placements; }
  }
  $("count").textContent =
    `${touched} of ${HOUSES.length} drawings corrected, covering ` +
    `${covered} of ${total} placements`;
  options();
}

function options() {
  $("pick").innerHTML = HOUSES.map((h, i) => {
    const s = state(i);
    return `<option value="${i}"${i === at ? " selected" : ""}>` +
      `${moved(s) ? "\\u2713 " : ""}#${s.id} \\u00b7 tileset ${s.tileset} \\u00b7 ` +
      `${s.cells[0]}x${s.cells[1]} cells \\u00b7 ${s.placements} placements</option>`;
  }).join("");
}

function marks() {
  for (const el of document.querySelectorAll(".pt"))
    el.classList.toggle("on", el.dataset.k === kind);
  $("tools").innerHTML =
    ["wand", "brush", "rect"].map((k) =>
      `<button class="tool${tool === k ? " on" : ""}" data-t="${k}">${k}</button>`
    ).join(" ") + ` &nbsp; brush ${brush*2+1}px`;
  for (const el of document.querySelectorAll(".tool"))
    el.onclick = () => { tool = el.dataset.t; marks(); };
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

function put(x, y) {
  const h = state(at);
  if (x < 0 || y < 0 || y >= h._paint.length || x >= h._paint[0].length) return false;
  if (h._paint[y][x] === kind) return false;
  if (stroke) stroke.push([x, y, h._paint[y][x]]);
  h._paint[y][x] = kind;
  return true;
}

function box(a, b) {
  let n = 0;
  for (let y = Math.min(a[1], b[1]); y <= Math.max(a[1], b[1]); y++)
    for (let x = Math.min(a[0], b[0]); x <= Math.max(a[0], b[0]); x++)
      if (put(x, y)) n++;
  if (n) { persist(state(at)); draw(); }
}

// THE WAND IS THE TOOL. It floods the drawing's own shape rather than a region
// of one colour, because a Game Boy roof is a DITHER of two shades and a
// same-colour flood would take every other pixel of it. What bounds a shape here
// is the darkest shade, which is the outline the artist drew round it, and that
// is the same rule this mod cuts every silhouette with. The outline itself is
// then swallowed, or a painted roof would come back with a black fringe that
// belongs to nothing.
function wand(sx, sy) {
  const h = state(at);
  if (sx < 0 || sy < 0 || sx >= W || sy >= H) return;
  const inside = (x, y) => outline[y][x] === "0";
  const start = inside(sx, sy);
  const hit = new Uint8Array(W * H);
  const stack = [sy * W + sx];
  hit[sy * W + sx] = 1;
  // Clicking ON the outline can only mean the outline, so that floods the ink.
  const ok = (x, y) => inside(x, y) === start;
  while (stack.length) {
    const i = stack.pop();
    const x = i % W, y = (i / W) | 0;
    for (const [dx, dy] of [[1,0],[-1,0],[0,1],[0,-1]]) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue;
      const j = ny * W + nx;
      if (hit[j] || !ok(nx, ny)) continue;
      hit[j] = 1;
      stack.push(j);
    }
  }
  if (start) {
    // Swallow the outline around it, so the shape arrives with its own edge.
    const edge = [];
    for (let i = 0; i < W * H; i++) {
      if (hit[i]) continue;
      const x = i % W, y = (i / W) | 0;
      for (const [dx, dy] of [[1,0],[-1,0],[0,1],[0,-1]]) {
        const nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue;
        if (hit[ny * W + nx] === 1) { edge.push(i); break; }
      }
    }
    for (const i of edge) hit[i] = 2;
  }
  let n = 0;
  for (let i = 0; i < W * H; i++)
    if (hit[i] && put(i % W, (i / W) | 0)) n++;
  if (n) { persist(h); draw(); }
}

function load() {
  const h = state(at);
  scale = Math.max(2, Math.min(14, Math.floor(900 / (h.size[0] * TILE))));
  W = h.size[0] * TILE; H = h.size[1] * TILE;
  outline = h.outline;
  img.onload = draw;
  img.src = h.art;
  const ctx = $("ctx");
  ctx.onload = () => { ctx.style.width = ctx.naturalWidth * 2 + "px"; };
  ctx.src = h.context;
  $("cap").textContent =
    `#${h.id} \\u00b7 tileset ${h.tileset} \\u00b7 ${h.size[0]}x${h.size[1]} tiles ` +
    `(${h.cells[0]}x${h.cells[1]} cells) \\u00b7 placed ${h.placements} times on ` +
    `${h.maps.length} maps \\u00b7 first at ${h.where}`;
  options(); marks(); draw();
}

function go(step) {
  at = Math.max(0, Math.min(HOUSES.length - 1, at + step));
  load();
}

function build() {
  $("palette").innerHTML = PAINTS.map((p) =>
    `<span class="pt" data-k="${p.k}" style="background:${p.color}">${p.label}</span>`
  ).join("");
  $("palette").onclick = (e) => {
    const el = e.target.closest(".pt");
    if (el) { kind = el.dataset.k; marks(); }
  };
  $("pick").onchange = () => { at = +$("pick").value; load(); };
  $("prev").onclick = () => go(-1);
  $("next").onclick = () => go(1);
  $("reset").onclick = () => {
    const h = state(at);
    h._paint = h._guess.map((r) => r.split(""));
    persist(h); draw();
  };
  $("save").onclick = save;
  $("save2").onclick = save;
  document.onkeydown = (e) => {
    if (e.target.tagName === "SELECT") return;
    if (e.key === "z" && (e.ctrlKey || e.metaKey)) {
      const step = undo.pop();
      if (step) { step(); draw(); }
      return;
    }
    for (const p of PAINTS) if (e.key === p.key) { kind = p.k; marks(); }
    if (e.key === "w" || e.key === "W") { tool = "wand"; marks(); }
    if (e.key === "b" || e.key === "B") { tool = "brush"; marks(); }
    if (e.key === "r" || e.key === "R") { tool = "rect"; marks(); }
    if (e.key === "[") { scale = Math.max(2, scale - 1); draw(); }
    if (e.key === "]") { scale = Math.min(20, scale + 1); draw(); }
    if (e.key === ",") { brush = Math.max(0, brush - 1); marks(); }
    if (e.key === ".") { brush = Math.min(12, brush + 1); marks(); }
    if (e.key === "x" || e.key === "X") { bare = !bare; draw(); }
    if (e.key === "g" || e.key === "G") { grid = !grid; draw(); }
    if (e.key === "ArrowLeft") go(-1);
    if (e.key === "ArrowRight") go(1);
  };
  const c = $("art");
  let from = null;
  const pixelOf = (e) => {
    const r = c.getBoundingClientRect();
    return [Math.floor((e.clientX - r.left) / scale),
            Math.floor((e.clientY - r.top) / scale)];
  };
  const dab = (p) => box([p[0]-brush, p[1]-brush], [p[0]+brush, p[1]+brush]);
  c.onmousedown = (e) => {
    from = pixelOf(e);
    open_stroke();
    if (tool === "wand") wand(from[0], from[1]);
    if (tool === "brush") dab(from);
    e.preventDefault();
  };
  c.onmousemove = (e) => {
    if (!from || tool !== "brush") return;
    dab(pixelOf(e));
  };
  const finish = (e) => {
    if (!from) return;
    if (tool === "rect") box(from, pixelOf(e));
    from = null;
    close_stroke();
  };
  c.onmouseup = finish;
  c.onmouseleave = finish;
  load(); tally();
}

function save() {
  // The vocabulary and the UNIT travel with the painting, so nothing downstream
  // has to guess what a character is or how big it is.
  const out = {
    unit: "pixel",
    legend: Object.fromEntries(PAINTS.map((p) => [p.k, p.label])),
    houses: HOUSES.map((h, i) => {
      const s = state(i);
      return { id: s.id, tileset: s.tileset, size: s.size, tiles: s.tiles,
               placements: s.placements, maps: s.maps, where: s.where,
               guess: s._guess, paint: s._paint.map((r) => r.join("")) };
    }),
  };
  const a = document.createElement("a");
  a.href = URL.createObjectURL(
    new Blob([JSON.stringify(out)], { type: "application/json" }));
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
    # THE PAGE CARRIES ITS OWN PICTURES. The wand reads the drawing back pixel by
    # pixel off a canvas, which is same-origin work, and a page opened as a LOCAL
    # FILE cannot do that to a local image: the canvas is tainted and the read
    # throws. Loading them beside the page worked perfectly over http and drew a
    # blank rectangle the way a person actually opens it. A data URI has no origin
    # to be wrong about. Only the drawing needs it; the context picture is only
    # ever displayed, never read.
    for house in houses:
        house["art"] = "data:image/png;base64," + base64.b64encode(
            (directory / house["art"]).read_bytes()).decode()
    out = directory / "houses.html"
    out.write_text(PAGE.replace("__HOUSES__", json.dumps(houses)))
    print("%d drawings, %d placements, %d pixels to paint over" % (
        len(houses), sum(h["placements"] for h in houses),
        sum(h["size"][0] * h["size"][1] * 64 for h in houses)))
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
