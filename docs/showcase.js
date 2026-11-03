// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Two instruments, both run by the library compiled to this page: the parser, on
// whatever text the reader pastes, and the bucket layouts, on the window the front
// plate draws. Nothing here parses a line itself.

const data = globalThis.moonp8s;
const parse = globalThis.moonp8sParse;
const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];

const input = $("#expo-input");
const status = $("#lab-status");
const out = $("#lab-out");

const PRESETS = {
  window: () => data?.exposition ?? "",
  openmetrics: () => data?.openmetrics ?? "",
  broken: () =>
    ["# TYPE jobs_running gauge", 'jobs_running{queue="email"} three', ""].join("\n"),
  labels: () =>
    [
      "# HELP jobs_processed_total Jobs finished.",
      "# TYPE jobs_processed_total counter",
      'jobs_processed_total{queue="email"} 12.0',
      'jobs_processed_total{queue="billing"} 3.0',
      "",
    ].join("\n"),
};

/* ------------------------------------------------------------ the parser */

function labelText(labels) {
  if (!labels.length) return "—";
  return labels.map(([key, value]) => `${key}="${value}"`).join(", ");
}

function render(result) {
  out.replaceChildren();
  if (!result?.ok) {
    status.classList.add("is-refused");
    status.innerHTML = `<b>refused</b> · ${result?.error ?? "the parser did not answer"}`;
    return;
  }
  status.classList.remove("is-refused");
  const families = result.families ?? [];
  const samples = families.reduce((sum, family) => sum + family.samples.length, 0);
  status.innerHTML =
    `<b>parsed</b> · ${families.length} famil${families.length === 1 ? "y" : "ies"} · ` +
    `${samples} sample${samples === 1 ? "" : "s"}`;

  for (const family of families) {
    const block = document.createElement("div");
    block.className = "family";
    const head = document.createElement("div");
    head.className = "family-head";
    const name = document.createElement("span");
    name.className = "family-name";
    name.textContent = family.name;
    const kind = document.createElement("span");
    kind.className = "family-kind";
    kind.textContent = family.kind;
    head.append(name, kind);
    block.append(head);

    for (const sample of family.samples.slice(0, 6)) {
      const row = document.createElement("div");
      row.className = "sample-row";
      const labels = document.createElement("span");
      labels.className = "labels";
      labels.textContent = labelText(sample.labels);
      const value = document.createElement("span");
      value.className = "value";
      value.textContent = sample.value;
      row.append(labels, value);
      block.append(row);
    }
    if (family.samples.length > 6) {
      const more = document.createElement("p");
      more.className = "sample-more";
      more.textContent = `+ ${family.samples.length - 6} more`;
      block.append(more);
    }
    out.append(block);
  }
  if (!families.length) {
    status.innerHTML = "<b>empty</b> · no families in that text";
  }
}

function read() {
  if (!parse) {
    status.classList.add("is-refused");
    status.innerHTML = "<b>no engine</b> · the parser did not load";
    return;
  }
  const text = input.value.trim();
  if (!text) {
    status.classList.add("is-refused");
    status.innerHTML = "<b>empty</b> · paste an exposition first";
    out.replaceChildren();
    return;
  }
  let result;
  try {
    result = parse(text);
  } catch (error) {
    result = { ok: false, error: String(error) };
  }
  render(result);
}

$("#lab-send")?.addEventListener("click", read);
input?.addEventListener("keydown", (event) => {
  // ⌘↵ / Ctrl-↵ runs it; a bare Enter is a newline, because this is a text box.
  if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
    event.preventDefault();
    read();
  }
});

for (const button of $$("[data-preset]")) {
  button.addEventListener("click", () => {
    const make = PRESETS[button.dataset.preset];
    if (!make) return;
    input.value = make();
    read();
  });
}

/* ------------------------------------------------------------ the edges */

let binning = 1;

function spell(bound) {
  if (bound >= 1) return bound.toFixed(1);
  if (bound >= 0.01) return bound.toFixed(3).replace(/0+$/, "").replace(/\.$/, "");
  return bound.toExponential(1);
}

function showBinning() {
  if (!data?.binnings?.length) return;
  const chosen = data.binnings[binning];
  $("#lab-n").textContent = String(chosen.width);
  $("#lab-edges").textContent = String(chosen.bounds.length + 1);
  $("#lab-median").textContent = `${spell(chosen.median)} s`;
  $("#lab-p90").textContent = `${spell(chosen.p90)} s`;
  $("#lab-hint").textContent =
    binning === 1
      ? "the edges the official clients share"
      : `${chosen.bounds.length + 1} edges · the count has not moved`;
  for (const stop of $$(".stop[data-binning]")) {
    stop.setAttribute("aria-pressed", String(Number(stop.dataset.binning) === binning));
  }
}

for (const stop of $$(".stop[data-binning]")) {
  stop.addEventListener("click", () => {
    binning = Number(stop.dataset.binning);
    showBinning();
  });
}

/* ------------------------------------------------------------ start */

if (data) {
  $("#lab-window").textContent = data.total.toLocaleString("en-US");
  if (input && !input.value) input.value = data.exposition ?? "";
  showBinning();
  read();
}
