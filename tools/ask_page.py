#!/usr/bin/env python3
"""Builds a page of MIXED questions: named tiles and judgement calls together.

`survey_label.py` asks what a block is and `survey_tiles.py` asks what a tile
is. Both ask one shape of question over and over. This one takes a written spec
and asks whatever a round actually needs: a handful of leftover tiles to name,
and beside them the calls that no measurement can settle, each with the pictures
that make it answerable and a set of options where there is one.

Written because the fast tile loop and the considered judgement are different
jobs and were being run as separate sittings. A round is now one page: the tiles
first, two seconds each, then the questions, and one SAVE for both.

    tools/ask_page.py <survey dir> <spec.json>   # writes <survey dir>/ask.html

The spec is a dict with `title`, `out` and `items`. An item is one of:

    {"kind": "tile", "tileset": 9, "tile": 66, "image": "ctx_ts9_66.png",
     "note": "what the pass said about it"}
    {"kind": "question", "id": "stairs", "title": "...", "body": "...",
     "images": [{"src": "a.png", "caption": "..."}],
     "choices": [{"value": "flat", "label": "...", "note": "..."}]}

SAVE writes the spec's `out` file: `ts<n> <tile> <words>` for a tile, so the
answer joins the record every other round is read from and is never asked for
twice, and `Q <id> <choice> <words>` for a question.
"""

import json
import pathlib
import sys

PAGE = """<!doctype html>
<meta charset="utf-8">
<title>__TITLE__</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; background: #16161a; color: #e8e8ee;
         font: 15px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  header { display: flex; gap: 16px; align-items: baseline; flex-wrap: wrap;
           padding: 12px 20px; border-bottom: 1px solid #2c2c34; position: sticky;
           top: 0; background: #16161ae8; backdrop-filter: blur(8px); z-index: 3; }
  header h1 { font-size: 15px; margin: 0; font-weight: 600; }
  header .grow { flex: 1; }
  select, button, input, textarea { font: inherit; color: inherit;
      background: #23232b; border: 1px solid #3a3a44; border-radius: 6px;
      padding: 6px 10px; }
  button { cursor: pointer; }
  button:hover { background: #2e2e38; }
  img { image-rendering: pixelated; display: block; max-width: 100%; border-radius: 6px; }
  .chip { display: inline-block; background: #23232b; border: 1px solid #3a3a44;
          border-radius: 999px; padding: 3px 10px; font-size: 13px; color: #a8a8bb; }
  .done { color: #7ad07a; }
  kbd { background: #23232b; border: 1px solid #3a3a44; border-radius: 4px;
        padding: 1px 5px; font-size: 12px; }
  main { padding: 24px 20px 80px; max-width: 1180px; margin: 0 auto; }
  .tiles { display: flex; gap: 28px; align-items: flex-start; flex-wrap: wrap;
           background: #0f0f12; border: 1px solid #2c2c34; border-radius: 12px;
           padding: 18px; }
  .tiles .side { flex: 1; min-width: 330px; }
  .bar { height: 4px; background: #23232b; border-radius: 2px; overflow: hidden;
         margin-bottom: 10px; }
  .bar div { height: 100%; background: #6ea8fe; transition: width .15s; }
  #answer { width: 100%; font-size: 19px; padding: 11px 13px; margin: 12px 0 8px; }
  p.hint { color: #8d8da0; font-size: 13px; margin: 6px 0; }
  .note { color: #a8a8bb; font-size: 13.5px; background: #1c1c22; padding: 10px 12px;
          border-radius: 8px; border-left: 3px solid #3a3a44; }
  section { background: #0f0f12; border: 1px solid #2c2c34; border-radius: 12px;
            padding: 20px; margin: 22px 0; }
  section h2 { font-size: 17px; margin: 0 0 2px; }
  section > p.body { color: #c9c9d6; max-width: 78ch; white-space: pre-wrap; }
  .shots { display: flex; gap: 16px; flex-wrap: wrap; margin: 14px 0; }
  .shots figure { margin: 0; max-width: 520px; }
  .shots figcaption { color: #8d8da0; font-size: 12.5px; margin-top: 6px; }
  .choices { display: flex; flex-direction: column; gap: 10px; margin: 6px 0 14px; }
  .choice { display: flex; gap: 10px; align-items: flex-start; padding: 11px 13px;
            border: 1px solid #3a3a44; border-radius: 9px; cursor: pointer; }
  .choice:hover { background: #1c1c22; }
  .choice.on { border-color: #6ea8fe; background: #1a2331; }
  .choice input { margin: 4px 0 0; }
  .choice b { font-weight: 600; }
  .choice span { color: #a8a8bb; font-size: 13.5px; }
  section textarea { width: 100%; min-height: 84px; }
  footer { position: fixed; bottom: 0; left: 0; right: 0; padding: 10px 20px;
           background: #16161ae8; backdrop-filter: blur(8px);
           border-top: 1px solid #2c2c34; display: flex; gap: 14px;
           align-items: center; z-index: 3; }
</style>
<header>
  <h1>__TITLE__</h1>
  <span class="chip" id="count"></span>
  <span class="grow"></span>
  <button id="save">SAVE __OUT__</button>
</header>
<main id="main"></main>
<footer>
  <span class="chip" id="count2"></span>
  <span class="grow" style="flex:1"></span>
  <button id="save2">SAVE __OUT__</button>
</footer>
<script>
const SPEC = __SPEC__;
const TILES = SPEC.items.filter((i) => i.kind === "tile");
const QUESTIONS = SPEC.items.filter((i) => i.kind === "question");
let at = 0, dirty = false;

const answers = {};
const PREFIX = "voxel3dask:" + SPEC.out + ":";
try {
  for (let i = 0; i < localStorage.length; i++) {
    const k = localStorage.key(i);
    if (k.startsWith(PREFIX)) answers[k] = localStorage.getItem(k);
  }
} catch (e) {}

const $ = (id) => document.getElementById(id);
const key = (a, b) => PREFIX + a + ":" + b;
const remember = (k, v) => {
  if (v) answers[k] = v; else delete answers[k];
  try { v ? localStorage.setItem(k, v) : localStorage.removeItem(k); } catch (e) {}
  dirty = true;
  tally();
};
const esc = (s) => String(s == null ? "" : s).replace(/[&<>"]/g,
  (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

function build() {
  const parts = [];
  if (TILES.length) parts.push(`
    <div class="tiles">
      <div>
        <img id="context" width="470">
      </div>
      <div class="side">
        <div class="bar"><div id="progress"></div></div>
        <p><span class="chip" id="where"></span></p>
        <div class="note" id="note"></div>
        <input id="answer" autocomplete="off" spellcheck="false"
               placeholder="what is the thing in the ringed box?">
        <p class="hint"><kbd>Enter</kbd> files it and moves on, empty
          <kbd>Enter</kbd> skips, <kbd>Shift</kbd>+<kbd>Enter</kbd> goes back.</p>
        <p class="hint">Only the ringed box matters. Say what it is in your own
          words, and if it is a thing rather than floor, say how it SITS in a real
          world: tall like a wall, or low and flat like a table.</p>
        <p class="hint">Three things worth more than a name, when they apply:<br>
          &middot; <b>Name the OBJECT, not the fragment.</b> If this is a corner of
          a stool, say "stool", and say "stool" again on its other corners. Same
          word each time is what lets me group them into one thing.<br>
          &middot; <b>Say when it is the SEAM.</b> If the ring is mostly the floor
          between two objects rather than part of either, that is the answer, and
          it is one I cannot work out on my own.<br>
          &middot; <b>Size in pixels, once per object.</b> Wide &times; deep &times;
          tall. I can measure wide and tall off the drawing; DEEP is invisible in
          a flat picture and only you can give it to me.</p>
      </div>
    </div>`);
  for (const q of QUESTIONS) {
    const shots = (q.images || []).map((s) => `
      <figure><img src="${esc(s.src)}"><figcaption>${esc(s.caption)}</figcaption></figure>`
    ).join("");
    const choices = (q.choices || []).map((c) => `
      <label class="choice" data-q="${esc(q.id)}" data-v="${esc(c.value)}">
        <input type="radio" name="q_${esc(q.id)}" value="${esc(c.value)}">
        <span><b>${esc(c.label)}</b><br>${esc(c.note || "")}</span>
      </label>`).join("");
    parts.push(`
      <section>
        <h2>${esc(q.title)}</h2>
        <p class="body">${esc(q.body)}</p>
        <div class="shots">${shots}</div>
        <div class="choices">${choices}</div>
        <textarea data-q="${esc(q.id)}"
          placeholder="in your own words, and anything else you notice in these pictures"></textarea>
      </section>`);
  }
  $("main").innerHTML = parts.join("");

  for (const box of document.querySelectorAll("textarea")) {
    box.value = answers[key("Qtext", box.dataset.q)] || "";
    box.oninput = () => remember(key("Qtext", box.dataset.q), box.value.trim());
  }
  for (const label of document.querySelectorAll(".choice")) {
    const picked = answers[key("Q", label.dataset.q)];
    if (picked === label.dataset.v) {
      label.classList.add("on");
      label.querySelector("input").checked = true;
    }
    label.onclick = () => {
      remember(key("Q", label.dataset.q), label.dataset.v);
      for (const other of document.querySelectorAll(
        `.choice[data-q="${label.dataset.q}"]`)) other.classList.remove("on");
      label.classList.add("on");
    };
  }
  if (TILES.length) {
    $("answer").onkeydown = (e) => {
      if (e.key !== "Enter") return;
      remember(key("T", at), $("answer").value.trim());
      at = Math.max(0, Math.min(TILES.length - 1, at + (e.shiftKey ? -1 : 1)));
      show();
      e.preventDefault();
    };
    show();
  }
  $("save").onclick = save;
  $("save2").onclick = save;
  tally();
}

function show() {
  const t = TILES[at];
  if (!t) return;
  $("context").src = t.image;
  $("where").textContent =
    `tileset ${t.tileset} · tile ${t.tile} · ${at + 1} of ${TILES.length}`;
  $("note").textContent = t.note || "";
  $("progress").style.width = (100 * (at + 1) / TILES.length) + "%";
  $("answer").value = answers[key("T", at)] || "";
  $("answer").focus();
  $("answer").select();
}

function tally() {
  let n = 0;
  for (let i = 0; i < TILES.length; i++) if (answers[key("T", i)]) n++;
  let q = 0;
  for (const x of QUESTIONS)
    if (answers[key("Q", x.id)] || answers[key("Qtext", x.id)]) q++;
  const text = `${n} of ${TILES.length} tiles · ${q} of ${QUESTIONS.length} questions`;
  for (const id of ["count", "count2"]) {
    const el = $(id);
    if (el) el.innerHTML = `<span class="${n + q ? "done" : ""}">${text}</span>`;
  }
}

function save() {
  const lines = [];
  for (let i = 0; i < TILES.length; i++) {
    const said = answers[key("T", i)];
    if (said) lines.push(`ts${TILES[i].tileset} ${TILES[i].tile} ${said}`);
  }
  for (const x of QUESTIONS) {
    const picked = answers[key("Q", x.id)] || "-";
    const said = (answers[key("Qtext", x.id)] || "").replace(/\\s*\\n\\s*/g, " ");
    if (picked !== "-" || said) lines.push(`Q ${x.id} ${picked} ${said}`.trim());
  }
  const a = document.createElement("a");
  a.href = URL.createObjectURL(
    new Blob([lines.join("\\n") + "\\n"], { type: "text/plain" }));
  a.download = SPEC.out;
  a.click();
  dirty = false;
}

window.onbeforeunload = () => dirty ? "Not saved yet." : undefined;
build();
</script>
"""


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    directory = pathlib.Path(sys.argv[1])
    spec = json.loads(pathlib.Path(sys.argv[2]).read_text())
    missing = [
        name for name in (
            [i["image"] for i in spec["items"] if i["kind"] == "tile"]
            + [s["src"] for i in spec["items"] if i["kind"] == "question"
               for s in i.get("images", [])]
        ) if not (directory / name).exists()
    ]
    if missing:
        print("missing beside the page: %s" % ", ".join(missing))
        return 1
    page = (PAGE.replace("__SPEC__", json.dumps(spec))
                .replace("__TITLE__", spec.get("title", "voxel3d"))
                .replace("__OUT__", spec["out"]))
    out = directory / "ask.html"
    out.write_text(page)
    tiles = sum(1 for i in spec["items"] if i["kind"] == "tile")
    questions = sum(1 for i in spec["items"] if i["kind"] == "question")
    print("%d tiles and %d questions" % (tiles, questions))
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
