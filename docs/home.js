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
const rowTotals = rows.map((_, r) => pops.reduce((sum, second) => sum + second[r], 0));
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
      const n = pops[s]?.[r] ?? 0;
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
    format === "text" ? "milliseconds since the epoch" : "seconds, as a float";
  $("#content-type").textContent =
    format === "text"
      ? "text/plain; version=0.0.4; charset=utf-8"
      : "application/openmetrics-text; version=1.0.0; charset=utf-8";

  placeAnnotations();
}

// The notes hang under the field they name: measuring the fields after the text is
// set is the only way they stay aligned. Two notes that would collide are stacked on
// two levels, the way a drawing labels a narrow part, and each gets a rule of its own
// reaching up to the specimen.
function placeAnnotations() {
  const specimen = $("#specimen");
  const host = $("#annotations");
  if (!specimen || !host) return;
  for (const tick of host.querySelectorAll(".tick")) tick.remove();
  const notes = [...host.querySelectorAll(".annotation")];
  const ticks = [];
  let previousRight = -Infinity;
  let level = 0;
  for (const note of notes) {
    const field = specimen.querySelector(`[data-field="${note.dataset.for}"]`);
    if (!field) continue;
    note.style.left = `${field.offsetLeft}px`;
    if (field.offsetLeft < previousRight + 12) level = level === 0 ? 1 : 0;
    else level = 0;
    note.classList.toggle("is-lifted", level === 1);
    const tick = document.createElement("span");
    tick.className = "tick";
    tick.style.left = `${field.offsetLeft}px`;
    tick.style.height = level === 1 ? "46px" : "8px";
    ticks.push(tick);
    previousRight = field.offsetLeft + Math.max(40, note.offsetWidth);
  }
  for (const tick of ticks) host.append(tick);

  // On a narrow sheet the notes become a list and carry their own names; the rules
  // would point nowhere, so they are left out.
  if (innerWidth <= 760) for (const tick of ticks) tick.remove();
}

/* ------------------------------------------------------------ the facts */

function fillFacts() {
  if (!plate) return;
  $("#fact-samples").textContent = thousands(plate.total);
  $("#fact-plate").textContent = plate.window.toFixed(3);
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

/* ------------------------------------------------------------ start */

if (plate && !plate.error) {
  buildField();
  buildReadout();
  buildSpecimen();
  fillFacts();
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
  });
});
