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

IT IS A BRUSH AND NOTHING CLEVERER. A wand was built first, flooding the
drawing's own shape through everything that was not its outline, and it was
refused: a Game Boy drawing is not sealed the way a wand needs, so it took a
whole house as often as it took a roof, and a tool that has to be undone half
the time is slower than one that never surprises you. So: hold and drag, a brush
whose size is SHOWN at the cursor, a rectangle, and a fill that spreads only
through what is already painted the same word. Nothing guesses.

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
  .stack { position: relative; line-height: 0; }
  /* The brush preview rides over the picture on its own layer, so moving the
     mouse never repaints the drawing underneath it. */
  #over { position: absolute; left: 0; top: 0; pointer-events: none; }
  .paints { display: flex; gap: 6px; flex-wrap: wrap; align-items: center; }
  .pt { height: 32px; border-radius: 6px; border: 2px solid #3a3a44;
        display: flex; align-items: center; padding: 0 8px; font-weight: 700;
        cursor: pointer; font-size: 13px; }
  .pt .lbl { background: #1b1b22e6; padding: 1px 6px; border-radius: 4px; }
  .pt.on { box-shadow: 0 0 0 3px #fff; }
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
      <div class="wrap"><div class="stack">
        <canvas id="art"></canvas><canvas id="over"></canvas>
      </div></div>
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
    <b>Hold and drag to paint.</b> The square at the cursor is the brush and is
    exactly what it will cover. <kbd>1</kbd>-<kbd>4</kbd> pick a word,
    <kbd>B</kbd> brush, <kbd>R</kbd> rectangle, <kbd>F</kbd> fill,
    <kbd>,</kbd> <kbd>.</kbd> brush size, <kbd>[</kbd> <kbd>]</kbd> zoom,
    <kbd>Ctrl</kbd>+<kbd>Z</kbd> undoes a whole stroke,
    <kbd>X</kbd> hides the paint so the drawing can be seen bare,
    <kbd>G</kbd> hides the grid, <kbd>&#8592;</kbd> <kbd>&#8594;</kbd> the house
    before and after. <b>fill</b> spreads through everything already painted the
    same word as the pixel you click, so it is never a surprise.
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
// EACH WORD HAS ITS OWN HATCH, not just its own colour. A flat wash light enough
// to see the drawing through is too light to tell two words apart, and one heavy
// enough to tell them apart hides the drawing: the reviewer hit both ends of that
// and was right. A pattern is legible at any opacity, because what names it is
// the direction of the lines rather than the strength of the tint.
const PAINTS = [
  { k: "W", label: "wall",                 color: "#4d94ff", key: "1", hatch: "up" },
  { k: "R", label: "roof",                 color: "#ff8c1a", key: "2", hatch: "down" },
  { k: "F", label: "roof, from the front", color: "#c862ff", key: "3", hatch: "cross" },
  { k: ".", label: "not the house",        color: "#9aa0ad", key: "4", hatch: "dot" },
];
const BY_KEY = {};
for (const p of PAINTS) BY_KEY[p.k] = p;
// The wash under the hatch, kept faint: the hatch is what names the region and
// the wash only makes it a field rather than a set of lines.
const TINT = 0.11;
// The hatch tile, in SCREEN pixels, so the lines stay the same weight whatever
// the zoom is. Hatching in drawing pixels turns into a solid block at 14x.
const HATCH = 11;
let at = 0, kind = "W", scale = 8, tool = "brush", brush = 4;
let bare = false, grid = true;
const undo = [];

// One repeating hatch per word, built once and anchored to the canvas rather
// than to each rectangle, so a region comes out as continuous ruling instead of
// a grid of little patches.
const HATCHES = {};
function buildHatches() {
  for (const p of PAINTS) {
    const c = document.createElement("canvas");
    c.width = c.height = HATCH;
    const g = c.getContext("2d");
    g.strokeStyle = p.color; g.fillStyle = p.color;
    g.lineWidth = 2.0; g.lineCap = "square";
    const s = HATCH;
    if (p.hatch === "dot") {
      g.globalAlpha = 0.85;
      g.beginPath(); g.arc(s/2, s/2, 1.4, 0, 6.284); g.fill();
    }
    if (p.hatch === "up" || p.hatch === "cross") {
      g.beginPath();
      g.moveTo(-1, 1); g.lineTo(1, -1);
      g.moveTo(-1, s+1); g.lineTo(s+1, -1);
      g.moveTo(s-1, s+1); g.lineTo(s+1, s-1);
      g.stroke();
    }
    if (p.hatch === "down" || p.hatch === "cross") {
      g.beginPath();
      g.moveTo(-1, s-1); g.lineTo(1, s+1);
      g.moveTo(-1, -1); g.lineTo(s+1, s+1);
      g.moveTo(s-1, -1); g.lineTo(s+1, 1);
      g.stroke();
    }
    HATCHES[p.k] = c;
  }
}

const $ = (id) => document.getElementById(id);
const KEY = "voxel3dhousepx:";
const store = {};
try {
  for (let i = 0; i < localStorage.length; i++) {
    const k = localStorage.key(i);
    if (k.startsWith(KEY)) store[k] = localStorage.getItem(k);
  }
} catch (e) {}

let W = 0, H = 0;
// Where the cursor is, so the brush can be SEEN before it is used. Drawn on an
// overlay rather than into the picture, or every mouse move would repaint the
// drawing under it.
let hover = null;

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
  const o = $("over");
  o.width = c.width; o.height = c.height;
  g.imageSmoothingEnabled = false;
  if (img.complete && img.naturalWidth) g.drawImage(img, 0, 0, c.width, c.height);
  if (!bare) {
    // Runs first, so a region is a few wide fills rather than three thousand
    // little ones, and so the hatch inside it is unbroken.
    for (const p of PAINTS) {
      const wash = g.createPattern(HATCHES[p.k], "repeat");
      for (let y = 0; y < t; y++) {
        const row = h._paint[y];
        let x = 0;
        while (x < w) {
          if (row[x] !== p.k) { x++; continue; }
          let end = x;
          while (end + 1 < w && row[end + 1] === p.k) end++;
          const rx = x * scale, rw = (end - x + 1) * scale;
          if (p.k !== ".") {
            g.globalAlpha = TINT; g.fillStyle = p.color;
            g.fillRect(rx, y * scale, rw, scale);
          }
          g.globalAlpha = 1; g.fillStyle = wash;
          g.fillRect(rx, y * scale, rw, scale);
          x = end + 1;
        }
      }
    }
    // THE EDGE BETWEEN TWO WORDS is what a person is actually looking for, so it
    // is drawn as a line rather than left to the eye to find between two hatches.
    g.globalAlpha = 1; g.strokeStyle = "rgba(255,255,255,0.9)"; g.lineWidth = 1.5;
    g.beginPath();
    for (let y = 0; y < t; y++) {
      for (let x = 0; x < w; x++) {
        const k = h._paint[y][x];
        if (x + 1 < w && h._paint[y][x+1] !== k) {
          g.moveTo((x+1)*scale, y*scale); g.lineTo((x+1)*scale, (y+1)*scale);
        }
        if (y + 1 < t && h._paint[y+1][x] !== k) {
          g.moveTo(x*scale, (y+1)*scale); g.lineTo((x+1)*scale, (y+1)*scale);
        }
      }
    }
    g.stroke();
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

function sized(step) {
  brush = Math.max(1, Math.min(32, brush + step));
  marks(); cursor();
}

function zoomed(step) {
  scale = Math.max(2, Math.min(20, scale + step));
  marks(); draw(); cursor();
}

function marks() {
  for (const el of document.querySelectorAll(".pt"))
    el.classList.toggle("on", el.dataset.k === kind);
  $("tools").innerHTML =
    ["brush", "rect", "fill"].map((k) =>
      `<button class="tool${tool === k ? " on" : ""}" data-t="${k}">${k}</button>`
    ).join(" ") +
    ` &nbsp; <button class="size" data-d="-1">&#8722;</button>` +
    ` <b>brush ${brush}px</b> ` +
    `<button class="size" data-d="1">+</button>` +
    ` &nbsp; <button class="zoom" data-d="-1">&#8722;</button>` +
    ` <b>zoom ${scale}x</b> ` +
    `<button class="zoom" data-d="1">+</button>`;
  for (const el of document.querySelectorAll(".tool"))
    el.onclick = () => { tool = el.dataset.t; marks(); cursor(); };
  for (const el of document.querySelectorAll(".size"))
    el.onclick = () => { sized(+el.dataset.d); };
  for (const el of document.querySelectorAll(".zoom"))
    el.onclick = () => { zoomed(+el.dataset.d); };
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

// The square of drawing pixels a brush of the current size covers at p.
function span(p) {
  const half = (brush - 1) >> 1;
  return [[p[0] - half, p[1] - half],
          [p[0] - half + brush - 1, p[1] - half + brush - 1]];
}

// A DRAG PAINTS A LINE, not a row of dots. A mouse move skips pixels whenever
// the hand is quick or the zoom is high, and a brush that only marks where the
// events landed leaves gaps through the middle of a stroke.
function stroke_to(a, b) {
  const steps = Math.max(Math.abs(b[0]-a[0]), Math.abs(b[1]-a[1]));
  for (let i = 0; i <= steps; i++) {
    const t = steps === 0 ? 0 : i / steps;
    const s = span([Math.round(a[0] + (b[0]-a[0]) * t),
                    Math.round(a[1] + (b[1]-a[1]) * t)]);
    box(s[0], s[1]);
  }
}

// Everything joined to the pixel clicked that carries the SAME WORD it does.
// Not the drawing's shape and not a colour: what it spreads through is the
// painting, so it can never surprise you with a region you cannot see.
function fill(sx, sy) {
  const h = state(at);
  if (sx < 0 || sy < 0 || sx >= W || sy >= H) return;
  const from = h._paint[sy][sx];
  if (from === kind) return;
  const seen = new Uint8Array(W * H);
  const stack = [[sx, sy]];
  seen[sy * W + sx] = 1;
  while (stack.length) {
    const [x, y] = stack.pop();
    put(x, y);
    for (const [dx, dy] of [[1,0],[-1,0],[0,1],[0,-1]]) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue;
      if (seen[ny * W + nx] || h._paint[ny][nx] !== from) continue;
      seen[ny * W + nx] = 1;
      stack.push([nx, ny]);
    }
  }
  persist(h); draw();
}

// THE BRUSH IS SHOWN AT THE CURSOR, which is the difference between choosing a
// size and guessing one. Drawn on its own layer over the picture, in the colour
// of the word about to be painted.
function cursor() {
  const c = $("over"), g = c.getContext("2d");
  g.clearRect(0, 0, c.width, c.height);
  if (!hover) return;
  const p = BY_KEY[kind];
  if (tool === "brush") {
    const s = span(hover);
    g.fillStyle = p.color; g.globalAlpha = 0.30;
    g.fillRect(s[0][0]*scale, s[0][1]*scale, brush*scale, brush*scale);
    g.globalAlpha = 1;
    g.strokeStyle = "#fff"; g.lineWidth = 2;
    g.strokeRect(s[0][0]*scale, s[0][1]*scale, brush*scale, brush*scale);
    g.strokeStyle = p.color; g.lineWidth = 1;
    g.strokeRect(s[0][0]*scale+1, s[0][1]*scale+1, brush*scale-2, brush*scale-2);
  } else {
    g.strokeStyle = "#fff"; g.lineWidth = 1;
    g.beginPath();
    g.moveTo(hover[0]*scale + scale/2, 0);
    g.lineTo(hover[0]*scale + scale/2, c.height);
    g.moveTo(0, hover[1]*scale + scale/2);
    g.lineTo(c.width, hover[1]*scale + scale/2);
    g.stroke();
  }
}

function load() {
  const h = state(at);
  scale = Math.max(2, Math.min(14, Math.floor(900 / (h.size[0] * TILE))));
  W = h.size[0] * TILE; H = h.size[1] * TILE;
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
  buildHatches();
  // THE BUTTON WEARS ITS OWN HATCH, or the legend and the picture are two things
  // to hold in your head instead of one.
  $("palette").innerHTML = PAINTS.map((p) => {
    const bar = HATCHES[p.k].toDataURL();
    return `<span class="pt" data-k="${p.k}" style="color:${p.color};` +
      `border-color:${p.color};background:#1b1b22 url(${bar}) repeat">` +
      `<span class="lbl">${p.label}</span></span>`;
  }).join("");
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
    for (const p of PAINTS) if (e.key === p.key) { kind = p.k; marks(); cursor(); }
    if (e.key === "b" || e.key === "B") { tool = "brush"; marks(); cursor(); }
    if (e.key === "r" || e.key === "R") { tool = "rect"; marks(); cursor(); }
    if (e.key === "f" || e.key === "F") { tool = "fill"; marks(); cursor(); }
    if (e.key === "[") zoomed(-1);
    if (e.key === "]") zoomed(1);
    if (e.key === ",") sized(-1);
    if (e.key === ".") sized(1);
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
  let last = null;
  c.onmousedown = (e) => {
    from = pixelOf(e);
    last = from;
    open_stroke();
    if (tool === "brush") stroke_to(from, from);
    if (tool === "fill") fill(from[0], from[1]);
    e.preventDefault();
  };
  c.onmousemove = (e) => {
    const p = pixelOf(e);
    hover = p;
    if (from && tool === "brush") { stroke_to(last, p); last = p; }
    cursor();
  };
  // A drag that ends off the canvas still has to land, or a stroke run off the
  // edge of a drawing is silently lost.
  const finish = (e) => {
    if (!from) return;
    if (tool === "rect") box(from, pixelOf(e));
    from = null; last = null;
    close_stroke();
  };
  c.onmouseup = finish;
  c.onmouseleave = (e) => { finish(e); hover = null; cursor(); };
  window.addEventListener("mouseup", () => {
    if (from) { from = null; last = null; close_stroke(); }
  });
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
    # THE PAGE CARRIES ITS OWN PICTURES, so it is one file with nothing beside it
    # to find and nothing to go missing if it is moved or sent on. The context
    # picture stays a path: there are 112 of them and they are the big half.
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
