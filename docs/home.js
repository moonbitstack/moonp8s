// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Draws the front plate and the exhibition plate from what the library produced.
//
// Every count on this page arrives from `engine/moonp8s.js`, which is this library
// compiled to JavaScript: the plate below was observed into histograms, and the
// counts read back are the histograms'. This file lays them out and does nothing
// else — no sample is invented here, and no bucket is filled by arithmetic the
// library did not do.

const data = globalThis.moonp8s;
const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const thousands = (n) => n.toLocaleString("en-US");

/* ------------------------------------------------------------ the plate */

// One row per bucket, slowest at the top: the field reads like a histogram turned on
// its side, with the empty tail given the room it deserves.
function rowsOf(plate) {
  const rows = [{ bound: null, label: "+Inf" }];
  for (let i = plate.buckets.length - 1; i >= 0; i -= 1) {
    const bound = plate.buckets[i];
    rows.push({ bound, label: `le ${spell(bound)}` });
  }
  return rows;
}

// The bounds as the exposition spells them: `0.1`, `1.0`, `2.5`.
function spell(bound) {
  return String(bound);
}

// The population of a bucket is the difference between two cumulative counts — the
// counters the histogram keeps, read the way the field needs them.
function populations(plate) {
  return plate.seconds.map((cumulative) => {
    const out = [];
    let previous = 0;
    for (const value of cumulative) {
      out.push(value - previous);
      previous = value;
    }
    out.push(0); // the +Inf bucket: nothing in this plate is slower than the last bound
    return out;
  });
}

/* ------------------------------------------------------------ the field */

const plate = data ?? null;
const rows = plate ? rowsOf(plate) : [];
const pops = plate ? populations(plate) : [];
// Rows run slowest-first, buckets run fastest-first: the last row is the first
// bucket, and the +Inf row holds whatever is above the last bound.
const bucketOf = (row) => (row === 0 ? -1 : rows.length - 1 - row);
const rowTotals = rows.map((_, r) => {
  const b = bucketOf(r);
  return b < 0 ? 0 : pops.reduce((sum, second) => sum + second[b], 0);
});
const maxRow = Math.max(1, ...rowTotals);
const budgetRow = rows.findIndex((row) => row.bound === (plate?.budget ?? 0.1));

const cellAt = [];

function buildField() {
  const labels = $("#row-labels");
  const cells = $("#cells");
  const fold = $("#fold");
  if (!plate || !labels || !cells || !fold) return;

  labels.replaceChildren();
  cells.replaceChildren();
  fold.replaceChildren();

  rows.forEach((row, r) => {
    const span = document.createElement("span");
    span.textContent = row.label;
    if (row.bound === null) span.className = "is-edge";
    else if (row.bound === plate.budget) span.className = "is-budget";
    else if (row.bound >= 2.5) span.className = "is-edge";
    labels.append(span);
  });

  // one cell per second per bucket; the cell holds one hairline per sample
  for (let r = 0; r < rows.length; r += 1) {
    const line = [];
    for (let s = 0; s < plate.window; s += 1) {
      const cell = document.createElement("div");
      cell.className = "cell";
      cell.dataset.second = String(s);
      cell.dataset.row = String(r);
      const b = bucketOf(r);
      const n = b < 0 ? 0 : (pops[s]?.[b] ?? 0);
      cell.dataset.samples = String(n);
      const over = rows[r].bound !== null && rows[r].bound > plate.budget;
      for (let k = 0; k < n; k += 1) {
        const mark = document.createElement("i");
        if (over) mark.className = "is-over";
        cell.append(mark);
      }
      cells.append(cell);
      line.push(cell);
    }
    cellAt.push(line);
  }

  // the fold: each row summed, drawn as a bar on the same baseline
  rowTotals.forEach((n, r) => {
    const row = document.createElement("div");
    row.className = "fold-row";
    row.dataset.row = String(r);
    const bar = document.createElement("i");
    const over = rows[r].bound !== null && rows[r].bound > plate.budget;
    if (over) bar.className = "is-over";
    bar.style.setProperty("--w", `${(n / maxRow) * 78}%`);
    bar.style.setProperty("--i", String(14 - r));
    const value = document.createElement("span");
    value.textContent = n ? thousands(n) : "";
    row.append(bar, value);
    fold.append(row);
  });

  const ticks = $("#ticks");
  ticks.replaceChildren();
  for (let s = 0; s < plate.window; s += 1) {
    const tick = document.createElement("span");
    tick.textContent = String(s).padStart(2, "0");
    ticks.append(tick);
  }

  // the budget line, on the boundary above the last bucket inside it
  const rule = $("#budget-rule");
  if (rule && budgetRow >= 0) {
    const grid = $("#cells");
    rule.style.top = `${(budgetRow / rows.length) * grid.clientHeight}px`;
  }
  const scan = $("#scan");
  if (scan) scan.style.setProperty("--sweep", `${$("#cells").clientWidth}px`);
}

/* ------------------------------------------------------------ the reading */

function buildReadout() {
  const readout = $("#field-hover");
  const cells = $("#cells");
  if (!readout || !cells || !plate) return;

  const clear = () => {
    readout.textContent = "";
    for (const row of cellAt) for (const cell of row) cell.classList.remove("is-row");
    for (const row of $$(".fold-row")) row.classList.remove("is-row");
  };

  cells.addEventListener("pointermove", (event) => {
    const cell = event.target.closest(".cell");
    if (!cell) return clear();
    const s = Number(cell.dataset.second);
    const r = Number(cell.dataset.row);
    for (const row of cellAt) for (const other of row) other.classList.remove("is-row");
    for (const other of cellAt[r]) other.classList.add("is-row");
    for (const row of $$(".fold-row")) {
      row.classList.toggle("is-row", Number(row.dataset.row) === r);
    }
    const n = Number(cell.dataset.samples);
    const total = pops[s].reduce((sum, value) => sum + value, 0);
    readout.innerHTML =
      `<b>00:${String(s).padStart(2, "0")}</b> · ${rows[r].label} · ` +
      `<b>${n}</b> sample${n === 1 ? "" : "s"} of ${total} in that second`;
  });
  cells.addEventListener("pointerleave", clear);
}

/* ------------------------------------------------------------ the specimen */

let format = "text";

function specimenLine() {
  if (!plate) return "";
  const specimen = format === "text" ? plate.specimen : plate.specimen_om;
  return specimen?.line ?? "";
}

function buildSpecimen() {
  if (!plate) return;
  const specimen = format === "text" ? plate.specimen : plate.specimen_om;
  const node = $("#specimen");
  if (!specimen || !node) return;

  const name = specimen.name;
  const labels = specimen.labels.map(([key, value]) => `${key}="${value}"`).join(",");
  node.querySelector('[data-field="name"]').textContent = name;
  node.querySelector('[data-field="labels"]').textContent = labels ? `{${labels}}` : "";
  node.querySelector('[data-field="value"]').textContent = specimen.value;
  node.querySelector('[data-field="time"]').textContent = specimen.timestamp || "—";
  // What leaves the page is the line the encoder wrote, not the text nodes a reader
  // happens to drag over.
  node.dataset.copyText = specimen.line;

  $("#time-note").textContent =
    format === "text" ? "milliseconds in 0.0.4" : "seconds in 1.0";
  $("#content-type").textContent =
    format === "text"
      ? "text/plain; version=0.0.4; charset=utf-8"
      : "application/openmetrics-text; version=1.0.0; charset=utf-8";

  // The notes are measured, so they are measured again once the real face has
  // arrived: a fallback face is narrower, and the notes would keep its widths.
  placeAnnotations();
  if (document.fonts?.ready) document.fonts.ready.then(placeAnnotations);
}

// The notes hang under the field they name: measuring the fields after the text is
// set is the only way they stay aligned. Notes are packed into lanes — the first
// lane whose last note has ended before this one starts — so three notes over a
// narrow specimen stack instead of overprinting, and each gets a rule of its own
// reaching up to the specimen.
function placeAnnotations() {
  const specimen = $("#specimen");
  const host = $("#annotations");
  if (!specimen || !host) return;
  for (const tick of host.querySelectorAll(".tick")) tick.remove();
  if (innerWidth <= 760) {
    for (const note of host.querySelectorAll(".annotation")) note.style.top = "";
    return;
  }
  const lanes = [];
  const ticks = [];
  for (const note of host.querySelectorAll(".annotation")) {
    const field = specimen.querySelector(`[data-field="${note.dataset.for}"]`);
    if (!field) continue;
    const left = field.offsetLeft;
    let lane = lanes.findIndex((right) => left >= right + 14);
    if (lane < 0) {
      lane = lanes.length;
      lanes.push(0);
    }
    lanes[lane] = left + Math.max(44, note.offsetWidth);
    note.style.left = `${left}px`;
    note.style.top = `${lane * 46}px`;
    // A note on the first lane hangs from the specimen; a lifted one carries a short
    // mark above itself instead, so the rule never crosses the note it passed.
    const tick = document.createElement("span");
    tick.className = "tick";
    tick.style.left = `${left}px`;
    tick.style.top = `${lane ? lane * 46 - 14 : 0}px`;
    tick.style.height = `${lane ? 10 : 8}px`;
    ticks.push(tick);
  }
  for (const tick of ticks) host.append(tick);
}

/* ------------------------------------------------------------ the facts */

function fillFacts() {
  if (!plate) return;
  $("#fact-samples").textContent = thousands(plate.total);
  $("#fact-window").textContent = plate.window.toFixed(3);
  $("#fact-rate").textContent = plate.rate.toFixed(1);
  $("#fact-over").textContent = thousands(plate.over);
  $("#fact-p90").textContent = plate.p90.toFixed(3);
  $("#end-line").textContent = `${thousands(plate.total)} samples, one plate.`;
  $("#colophon-count").textContent =
    `${thousands(plate.total)} samples · ${plate.buckets.length + 1} buckets · ` +
    `${thousands(plate.over)} over budget`;
}

/* ------------------------------------------------------------ the entrance */

// One pass, once: the scan crosses the field when it first comes into view. A field
// that replayed this on every scroll would be showing off, not measuring.
function enter() {
  const field = $("#field");
  if (!field) return;
  if (reduceMotion) {
    field.classList.add("is-drawn");
    return;
  }
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          field.classList.add("is-drawn");
          observer.disconnect();
        }
      }
    },
    { threshold: 0.25 },
  );
  observer.observe(field);
}

/* ------------------------------------------------------------ the switch */

for (const stop of $$(".stop[data-format]")) {
  stop.addEventListener("click", () => {
    const next = stop.dataset.format;
    if (next === format) return;
    format = next;
    for (const other of $$(".stop[data-format]")) {
      other.setAttribute("aria-pressed", String(other.dataset.format === format));
    }
    buildSpecimen();
  });
}


/* ------------------------------------------------------------ the aggregation */

// One window, three sets of edges. Every staircase here is a snapshot the library
// produced: the page picks which one to draw, and prints the median that snapshot
// answers with.
let binning = Math.min(1, (plate?.binnings?.length ?? 1) - 1);

function spellBound(bound) {
  if (bound >= 100) return bound.toFixed(0);
  if (bound >= 1) return bound.toFixed(1);
  if (bound >= 0.01) return bound.toFixed(3).replace(/0+$/, "").replace(/\.$/, "");
  return bound.toExponential(1);
}

function drawAggregation() {
  const host = $(".agg-plot");
  const svg = $("#agg-svg");
  if (!host || !svg || !plate?.binnings?.length) return;
  const chosen = plate.binnings[binning];
  const w = host.clientWidth;
  const h = host.clientHeight || 300;
  if (!w) return;
  svg.setAttribute("viewBox", `0 0 ${w} ${h}`);
  svg.replaceChildren();
  const ns = "http://www.w3.org/2000/svg";
  const make = (name, attrs) => {
    const node = document.createElementNS(ns, name);
    for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
    return node;
  };
  const top = 12;
  const bottom = h - 22;
  const total = chosen.width || 1;
  const n = chosen.bounds.length;
  const x = (i) => (i / n) * w;
  const y = (count) => bottom - (count / total) * (bottom - top);

  // the beat: one rule per quarter of the window's count
  for (let k = 0; k <= 4; k += 1) {
    const yy = y((total / 4) * k);
    svg.append(make("line", {
      x1: 0, y1: yy, x2: w, y2: yy,
      stroke: k === 0 ? "var(--rule-strong)" : "var(--grid)",
      "stroke-width": 1,
    }));
  }

  // the staircase: a tread per bucket, a rise per count
  let d = `M 0 ${bottom}`;
  chosen.cum.forEach((count, i) => {
    d += ` L ${x(i)} ${y(count)} L ${x(i + 1)} ${y(count)}`;
  });
  svg.append(make("path", { d, fill: "none", stroke: "var(--ink)", "stroke-width": 1.2 }));

  // the budget, at the first edge at or above it
  const at = chosen.bounds.findIndex((bound) => bound >= (plate.budget ?? 0.1));
  if (at >= 0) {
    svg.append(make("line", {
      x1: x(at), y1: top, x2: x(at), y2: bottom,
      stroke: "var(--accent-dim)", "stroke-width": 1,
    }));
  }

  // the edges, written under the step they close
  const every = Math.ceil(n / 12);
  chosen.bounds.forEach((bound, i) => {
    if (i % every !== 0) return;
    const label = make("text", {
      x: Math.min(w - 2, x(i + 1)),
      y: h - 6,
      "text-anchor": "end",
      fill: bound === (plate.budget ?? 0.1) ? "var(--accent)" : "var(--ink-faint)",
    });
    label.setAttribute("style", "font-family:var(--mono);font-size:8px;letter-spacing:.02em");
    label.textContent = spellBound(bound);
    svg.append(label);
  });

  const defaultMedian = plate.binnings[1]?.median ?? chosen.median;
  $("#agg-n").textContent = thousands(chosen.width);
  $("#agg-sum").textContent = `${plate.sum.toFixed(3)} s`;
  $("#agg-median").textContent = `${spellBound(chosen.median)} s`;
  $("#agg-p90").textContent = `${spellBound(chosen.p90)} s`;
  $("#agg-median").classList.toggle("is-moved", Math.abs(chosen.median - defaultMedian) > 1e-9);
  $("#agg-hint").textContent =
    binning === 1
      ? "the edges the official clients share"
      : `${n} edges · ${thousands(chosen.width)} samples · same sum`;
}

for (const stop of $$(".stop[data-binning]")) {
  stop.addEventListener("click", () => {
    const next = Number(stop.dataset.binning);
    if (next === binning) return;
    binning = next;
    for (const other of $$(".stop[data-binning]")) {
      other.setAttribute("aria-pressed", String(Number(other.dataset.binning) === binning));
    }
    drawAggregation();
  });
}

/* ------------------------------------------------------------ start */

if (plate && !plate.error) {
  buildField();
  buildReadout();
  buildSpecimen();
  fillFacts();
  drawAggregation();
  enter();
} else {
  document.body.dataset.engine = "missing";
}

let resizeFrame = 0;
addEventListener("resize", () => {
  cancelAnimationFrame(resizeFrame);
  resizeFrame = requestAnimationFrame(() => {
    const rule = $("#budget-rule");
    if (rule && budgetRow >= 0) {
      rule.style.top = `${(budgetRow / rows.length) * $("#cells").clientHeight}px`;
    }
    const scan = $("#scan");
    if (scan) scan.style.setProperty("--sweep", `${$("#cells").clientWidth}px`);
    placeAnnotations();
    drawAggregation();
  });
});
