// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The furniture every plate shares: the theme switch, the measuring scale that is
// also the scrollbar, and the copy captions. What the front plate does with a window
// lives in `home.js`; this file knows nothing about buckets.

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];

/* ------------------------------------------------------------ the plate */

const THEME_KEY = "p8s-plate";

function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  const button = $("#theme");
  if (!button) return;
  button.textContent = theme === "dark" ? "paper" : "ink";
  button.setAttribute(
    "aria-label",
    theme === "dark" ? "Print this sheet on paper" : "Print this sheet on the dark plate",
  );
}

applyTheme(document.documentElement.dataset.theme === "light" ? "light" : "dark");

// The version comes from `moon.mod` through `scripts/gen_version.py`; no page spells
// it, so a release cannot leave a stale number behind.
if (globalThis.MOONP8S_VERSION) {
  for (const element of $$("[data-version]")) {
    element.textContent = globalThis.MOONP8S_VERSION;
  }
}

$("#theme")?.addEventListener("click", () => {
  const next = document.documentElement.dataset.theme === "dark" ? "light" : "dark";
  localStorage.setItem(THEME_KEY, next);
  applyTheme(next);
});

/* ------------------------------------------------------------ the scale */

// The scrollbar, drawn as the sheet's measuring scale. It is a real scrollbar: the
// thumb can be dragged, the track can be pressed, the arrow keys work when it has
// focus, and it reports its position to assistive technology. Hiding the native
// scrollbar is only safe because this one does everything the native one did.
const ruler = $("#ruler");
const thumb = $("#ruler-thumb");
const readoutWindow = $("#readout-window");
const readoutLine = $("#readout-line");
const sections = $$("[data-ruler-section]");
const windowMode = document.body.dataset.ruler === "window";

let thumbHeight = 68;
let dragging = false;

const clamp = (value, low = 0, high = 1) => Math.min(high, Math.max(low, value));
const MAX_SCROLL = () => Math.max(0, document.documentElement.scrollHeight - innerHeight);

function layoutThumb() {
  // A scrollbar's thumb is proportional to what is visible; a fixed 68px thumb next
  // to a 6000px sheet would be a lie about how much is left.
  const room = document.documentElement.scrollHeight;
  thumbHeight = Math.round(
    Math.min(innerHeight * 0.42, Math.max(46, (innerHeight * innerHeight) / room)),
  );
  thumb.style.height = `${thumbHeight}px`;
}

function progress() {
  const room = MAX_SCROLL();
  return room > 0 ? clamp(scrollY / room) : 0;
}

function follow() {
  if (!ruler || !thumb) return;
  const ratio = progress();
  thumb.style.transform = `translateY(${ratio * (innerHeight - thumbHeight)}px)`;
  ruler.classList.toggle("is-top", scrollY < 8);
  ruler.setAttribute("aria-valuenow", String(Math.round(ratio * 100)));
  ruler.setAttribute("aria-valuetext", `${Math.round(ratio * 100)} per cent of the sheet`);

  if (!readoutWindow || !readoutLine) return;
  if (windowMode) {
    // One window, read: the seconds run with the sheet, and the scrape keeps its
    // number because it is one scrape.
    readoutWindow.textContent = "window 15 s";
    readoutLine.textContent = `#0127 · T+${(ratio * 15).toFixed(1)} s`;
    return;
  }
  // An inner plate is a page, not a scrape: the readout names the plate and how far
  // through the sheet the reader is.
  let current = 1;
  const middle = scrollY + innerHeight * 0.32;
  sections.forEach((section, index) => {
    if (section.offsetTop <= middle) current = index + 1;
  });
  readoutWindow.textContent = `plate ${String(current).padStart(2, "0")} / ${String(
    Math.max(sections.length, 1),
  ).padStart(2, "0")}`;
  readoutLine.textContent = `${Math.round(ratio * 100)}%`;
}

function scrollToPointer(clientY) {
  const travel = innerHeight - thumbHeight;
  const ratio = clamp((clientY - thumbHeight / 2) / travel);
  scrollTo(0, ratio * MAX_SCROLL());
}

ruler?.addEventListener("pointerdown", (event) => {
  if (event.button !== 0 && event.pointerType === "mouse") return;
  event.preventDefault();
  dragging = true;
  ruler.setPointerCapture?.(event.pointerId);
  document.body.classList.add("is-dragging");
  scrollToPointer(event.clientY);
  ruler.focus({ preventScroll: true });
});

ruler?.addEventListener("pointermove", (event) => {
  if (dragging) scrollToPointer(event.clientY);
});

function endDrag(event) {
  if (!dragging) return;
  dragging = false;
  if (event?.pointerId !== undefined) ruler.releasePointerCapture?.(event.pointerId);
  document.body.classList.remove("is-dragging");
}

ruler?.addEventListener("pointerup", endDrag);
ruler?.addEventListener("pointercancel", endDrag);
ruler?.addEventListener("lostpointercapture", endDrag);

ruler?.addEventListener("keydown", (event) => {
  const room = MAX_SCROLL();
  const page = innerHeight * 0.9;
  const step = 48;
  switch (event.key) {
    case "ArrowDown":
    case "ArrowRight":
      scrollBy({ top: step });
      break;
    case "ArrowUp":
    case "ArrowLeft":
      scrollBy({ top: -step });
      break;
    case "PageDown":
    case " ":
      scrollBy({ top: page });
      break;
    case "PageUp":
      scrollBy({ top: -page });
      break;
    case "Home":
      scrollTo({ top: 0 });
      break;
    case "End":
      scrollTo({ top: room });
      break;
    default:
      return;
  }
  event.preventDefault();
});

addEventListener("scroll", follow, { passive: true });
addEventListener("resize", () => {
  layoutThumb();
  follow();
});
// The sheet grows when fonts arrive and when `home.js` builds the field.
new ResizeObserver(() => {
  layoutThumb();
  follow();
}).observe(document.body);

layoutThumb();
follow();

/* ------------------------------------------------------------ copy captions */

// A caption that copies: the one place on the sheet where selecting text with the
// pointer is the wrong gesture, so it is offered as a button instead.
for (const button of $$("[data-copy]")) {
  const target = document.querySelector(button.dataset.copy);
  if (!target) continue;
  const resting = button.textContent;
  button.addEventListener("click", async () => {
    const text = target.dataset.copyText || target.textContent.trim();
    let copied = false;
    try {
      await navigator.clipboard.writeText(text);
      copied = true;
    } catch {
      // A page served from the file system, or a browser that wants a gesture it can
      // see: fall back to the oldest trick there is.
      const area = document.createElement("textarea");
      area.value = text;
      area.setAttribute("readonly", "");
      area.style.position = "fixed";
      area.style.top = "-1000px";
      document.body.append(area);
      area.select();
      copied = document.execCommand("copy");
      area.remove();
      if (!copied) {
        // Clipboard blocked and the old trick refused: leave the text selected, so
        // the caption can say what to press instead of pretending the copy worked.
        const range = document.createRange();
        range.selectNodeContents(target);
        const selection = getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
      }
    }
    button.textContent = copied ? "copied" : "selected · press ⌘C";
    button.classList.add("is-copied");
    setTimeout(() => {
      button.textContent = resting;
      button.classList.remove("is-copied");
    }, 1600);
  });
}
