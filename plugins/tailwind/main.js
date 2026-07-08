#!/usr/bin/env node
/*
 * Tailwind CSS plugin for the Tabame launcher.
 *
 * Long-lived child process speaking the launcher's newline-delimited JSON
 * protocol (see plugins/TABAME_PLUGIN_SKILL.md). Type the keyword `tw`
 * followed by a class name or CSS property (e.g. `tw p-4`, `tw flex`,
 * `tw bg-red-500`, `tw grid-cols`, `tw rounded`) to search the Tailwind utility
 * catalog and inspect the CSS each class generates, an example snippet, and a
 * link to the matching docs page.
 *
 * Runtime: Node 18+ or Bun. Plain JS, no dependencies, fully offline — the
 * catalog is generated in-process from Tailwind's default theme (v3.x).
 *
 *   Enter  → copy the class name
 *   Ctrl+K → copy class · copy generated CSS · open on tailwindcss.com
 */

"use strict";

const { spawn } = require("child_process");

const DOCS = (slug) => `https://tailwindcss.com/docs/${slug}`;

// ── stdout protocol ───────────────────────────────────────────────────────────
function send(frame) {
  process.stdout.write(JSON.stringify(frame) + "\n");
}
function render(rev, view, opts = {}) {
  send({ type: "render", rev, view, ...opts });
}
function detailFrame(rev, markdown) {
  render(rev, "detail", { detail: { markdown } });
}
function log(...a) {
  console.error(...a); // debug -> stderr only
}

// ── OS helpers (the plugin owns clipboard / browser) ──────────────────────────
function openUrl(url) {
  if (!url) return;
  spawn("cmd", ["/c", "start", "", url], {
    detached: true,
    stdio: "ignore",
  }).unref();
}
function copyToClipboard(text) {
  const clip = spawn("cmd", ["/c", "clip"], {
    stdio: ["pipe", "ignore", "ignore"],
  });
  clip.stdin.write(text == null ? "" : String(text));
  clip.stdin.end();
}

// ── Tailwind default theme scales ─────────────────────────────────────────────
const SPACING = {
  0: "0px",
  px: "1px",
  0.5: "0.125rem",
  1: "0.25rem",
  1.5: "0.375rem",
  2: "0.5rem",
  2.5: "0.625rem",
  3: "0.75rem",
  3.5: "0.875rem",
  4: "1rem",
  5: "1.25rem",
  6: "1.5rem",
  7: "1.75rem",
  8: "2rem",
  9: "2.25rem",
  10: "2.5rem",
  11: "2.75rem",
  12: "3rem",
  14: "3.5rem",
  16: "4rem",
  20: "5rem",
  24: "6rem",
  28: "7rem",
  32: "8rem",
  36: "9rem",
  40: "10rem",
  44: "11rem",
  48: "12rem",
  52: "13rem",
  56: "14rem",
  60: "15rem",
  64: "16rem",
  72: "18rem",
  80: "20rem",
  96: "24rem",
};
const FRACTIONS = {
  "1/2": "50%",
  "1/3": "33.333333%",
  "2/3": "66.666667%",
  "1/4": "25%",
  "2/4": "50%",
  "3/4": "75%",
  "1/5": "20%",
  "2/5": "40%",
  "3/5": "60%",
  "4/5": "80%",
  "1/6": "16.666667%",
  "2/6": "33.333333%",
  "3/6": "50%",
  "4/6": "66.666667%",
  "5/6": "83.333333%",
  full: "100%",
};

// Full Tailwind v3 default color palette.
const PALETTE = {
  slate: {
    50: "#f8fafc",
    100: "#f1f5f9",
    200: "#e2e8f0",
    300: "#cbd5e1",
    400: "#94a3b8",
    500: "#64748b",
    600: "#475569",
    700: "#334155",
    800: "#1e293b",
    900: "#0f172a",
    950: "#020617",
  },
  gray: {
    50: "#f9fafb",
    100: "#f3f4f6",
    200: "#e5e7eb",
    300: "#d1d5db",
    400: "#9ca3af",
    500: "#6b7280",
    600: "#4b5563",
    700: "#374151",
    800: "#1f2937",
    900: "#111827",
    950: "#030712",
  },
  zinc: {
    50: "#fafafa",
    100: "#f4f4f5",
    200: "#e4e4e7",
    300: "#d4d4d8",
    400: "#a1a1aa",
    500: "#71717a",
    600: "#52525b",
    700: "#3f3f46",
    800: "#27272a",
    900: "#18181b",
    950: "#09090b",
  },
  neutral: {
    50: "#fafafa",
    100: "#f5f5f5",
    200: "#e5e5e5",
    300: "#d4d4d4",
    400: "#a3a3a3",
    500: "#737373",
    600: "#525252",
    700: "#404040",
    800: "#262626",
    900: "#171717",
    950: "#0a0a0a",
  },
  stone: {
    50: "#fafaf9",
    100: "#f5f5f4",
    200: "#e7e5e4",
    300: "#d6d3d1",
    400: "#a8a29e",
    500: "#78716c",
    600: "#57534e",
    700: "#44403c",
    800: "#292524",
    900: "#1c1917",
    950: "#0c0a09",
  },
  red: {
    50: "#fef2f2",
    100: "#fee2e2",
    200: "#fecaca",
    300: "#fca5a5",
    400: "#f87171",
    500: "#ef4444",
    600: "#dc2626",
    700: "#b91c1c",
    800: "#991b1b",
    900: "#7f1d1d",
    950: "#450a0a",
  },
  orange: {
    50: "#fff7ed",
    100: "#ffedd5",
    200: "#fed7aa",
    300: "#fdba74",
    400: "#fb923c",
    500: "#f97316",
    600: "#ea580c",
    700: "#c2410c",
    800: "#9a3412",
    900: "#7c2d12",
    950: "#431407",
  },
  amber: {
    50: "#fffbeb",
    100: "#fef3c7",
    200: "#fde68a",
    300: "#fcd34d",
    400: "#fbbf24",
    500: "#f59e0b",
    600: "#d97706",
    700: "#b45309",
    800: "#92400e",
    900: "#78350f",
    950: "#451a03",
  },
  yellow: {
    50: "#fefce8",
    100: "#fef9c3",
    200: "#fef08a",
    300: "#fde047",
    400: "#facc15",
    500: "#eab308",
    600: "#ca8a04",
    700: "#a16207",
    800: "#854d0e",
    900: "#713f12",
    950: "#422006",
  },
  lime: {
    50: "#f7fee7",
    100: "#ecfccb",
    200: "#d9f99d",
    300: "#bef264",
    400: "#a3e635",
    500: "#84cc16",
    600: "#65a30d",
    700: "#4d7c0f",
    800: "#3f6212",
    900: "#365314",
    950: "#1a2e05",
  },
  green: {
    50: "#f0fdf4",
    100: "#dcfce7",
    200: "#bbf7d0",
    300: "#86efac",
    400: "#4ade80",
    500: "#22c55e",
    600: "#16a34a",
    700: "#15803d",
    800: "#166534",
    900: "#14532d",
    950: "#052e16",
  },
  emerald: {
    50: "#ecfdf5",
    100: "#d1fae5",
    200: "#a7f3d0",
    300: "#6ee7b7",
    400: "#34d399",
    500: "#10b981",
    600: "#059669",
    700: "#047857",
    800: "#065f46",
    900: "#064e3b",
    950: "#022c22",
  },
  teal: {
    50: "#f0fdfa",
    100: "#ccfbf1",
    200: "#99f6e4",
    300: "#5eead4",
    400: "#2dd4bf",
    500: "#14b8a6",
    600: "#0d9488",
    700: "#0f766e",
    800: "#115e59",
    900: "#134e4a",
    950: "#042f2e",
  },
  cyan: {
    50: "#ecfeff",
    100: "#cffafe",
    200: "#a5f3fc",
    300: "#67e8f9",
    400: "#22d3ee",
    500: "#06b6d4",
    600: "#0891b2",
    700: "#0e7490",
    800: "#155e75",
    900: "#164e63",
    950: "#083344",
  },
  sky: {
    50: "#f0f9ff",
    100: "#e0f2fe",
    200: "#bae6fd",
    300: "#7dd3fc",
    400: "#38bdf8",
    500: "#0ea5e9",
    600: "#0284c7",
    700: "#0369a1",
    800: "#075985",
    900: "#0c4a6e",
    950: "#082f49",
  },
  blue: {
    50: "#eff6ff",
    100: "#dbeafe",
    200: "#bfdbfe",
    300: "#93c5fd",
    400: "#60a5fa",
    500: "#3b82f6",
    600: "#2563eb",
    700: "#1d4ed8",
    800: "#1e40af",
    900: "#1e3a8a",
    950: "#172554",
  },
  indigo: {
    50: "#eef2ff",
    100: "#e0e7ff",
    200: "#c7d2fe",
    300: "#a5b4fc",
    400: "#818cf8",
    500: "#6366f1",
    600: "#4f46e5",
    700: "#4338ca",
    800: "#3730a3",
    900: "#312e81",
    950: "#1e1b4b",
  },
  violet: {
    50: "#f5f3ff",
    100: "#ede9fe",
    200: "#ddd6fe",
    300: "#c4b5fd",
    400: "#a78bfa",
    500: "#8b5cf6",
    600: "#7c3aed",
    700: "#6d28d9",
    800: "#5b21b6",
    900: "#4c1d95",
    950: "#2e1065",
  },
  purple: {
    50: "#faf5ff",
    100: "#f3e8ff",
    200: "#e9d5ff",
    300: "#d8b4fe",
    400: "#c084fc",
    500: "#a855f7",
    600: "#9333ea",
    700: "#7e22ce",
    800: "#6b21a8",
    900: "#581c87",
    950: "#3b0764",
  },
  fuchsia: {
    50: "#fdf4ff",
    100: "#fae8ff",
    200: "#f5d0fe",
    300: "#f0abfc",
    400: "#e879f9",
    500: "#d946ef",
    600: "#c026d3",
    700: "#a21caf",
    800: "#86198f",
    900: "#701a75",
    950: "#4a044e",
  },
  pink: {
    50: "#fdf2f8",
    100: "#fce7f3",
    200: "#fbcfe8",
    300: "#f9a8d4",
    400: "#f472b6",
    500: "#ec4899",
    600: "#db2777",
    700: "#be185d",
    800: "#9d174d",
    900: "#831843",
    950: "#500724",
  },
  rose: {
    50: "#fff1f2",
    100: "#ffe4e6",
    200: "#fecdd3",
    300: "#fda4af",
    400: "#fb7185",
    500: "#f43f5e",
    600: "#e11d48",
    700: "#be123c",
    800: "#9f1239",
    900: "#881337",
    950: "#4c0519",
  },
};
const SPECIAL_COLORS = {
  inherit: "inherit",
  current: "currentColor",
  transparent: "transparent",
  black: "#000000",
  white: "#ffffff",
};

// ── catalog ───────────────────────────────────────────────────────────────────
// Each entry: { cls, css, cat, doc, hex? }. Built once at startup; searched
// linearly (a few thousand tiny objects — negligible).
const CATALOG = [];
const seen = new Set();
function add(cls, css, cat, doc, extra) {
  if (seen.has(cls)) return;
  seen.add(cls);
  CATALOG.push({ cls, css, cat, doc, ...(extra || {}) });
}
// Add a static utility list: [cls, css] pairs sharing a category/doc.
function addStatic(pairs, cat, doc) {
  for (const [cls, css] of pairs) add(cls, css, cat, doc);
}
// Expand a spacing-style family across concrete values.
function addScale(
  prefix,
  props,
  scale,
  cat,
  doc,
  { negatives = false, join = " " } = {},
) {
  for (const key of Object.keys(scale)) {
    const val = scale[key];
    const decls = props.map((p) => `${p}: ${val};`).join(join);
    add(`${prefix}-${key}`, decls, cat, doc);
    if (
      negatives &&
      val !== "0px" &&
      val !== "auto" &&
      !String(val).startsWith("-")
    ) {
      const neg = props.map((p) => `${p}: -${val};`).join(join);
      add(`-${prefix}-${key}`, neg, cat, doc);
    }
  }
}

// ---- Layout / display / position -------------------------------------------
addStatic(
  [
    ["block", "display: block;"],
    ["inline-block", "display: inline-block;"],
    ["inline", "display: inline;"],
    ["flex", "display: flex;"],
    ["inline-flex", "display: inline-flex;"],
    ["grid", "display: grid;"],
    ["inline-grid", "display: inline-grid;"],
    ["table", "display: table;"],
    ["inline-table", "display: inline-table;"],
    ["contents", "display: contents;"],
    ["flow-root", "display: flow-root;"],
    ["list-item", "display: list-item;"],
    ["hidden", "display: none;"],
  ],
  "Layout",
  "display",
);
addStatic(
  [
    ["static", "position: static;"],
    ["fixed", "position: fixed;"],
    ["absolute", "position: absolute;"],
    ["relative", "position: relative;"],
    ["sticky", "position: sticky;"],
  ],
  "Layout",
  "position",
);
addStatic(
  [
    ["visible", "visibility: visible;"],
    ["invisible", "visibility: hidden;"],
    ["collapse", "visibility: collapse;"],
  ],
  "Layout",
  "visibility",
);
addStatic(
  [
    ["overflow-auto", "overflow: auto;"],
    ["overflow-hidden", "overflow: hidden;"],
    ["overflow-clip", "overflow: clip;"],
    ["overflow-visible", "overflow: visible;"],
    ["overflow-scroll", "overflow: scroll;"],
    ["overflow-x-auto", "overflow-x: auto;"],
    ["overflow-y-auto", "overflow-y: auto;"],
    ["overflow-x-hidden", "overflow-x: hidden;"],
    ["overflow-y-hidden", "overflow-y: hidden;"],
    ["overflow-x-scroll", "overflow-x: scroll;"],
    ["overflow-y-scroll", "overflow-y: scroll;"],
  ],
  "Layout",
  "overflow",
);
addStatic(
  [
    ["object-contain", "object-fit: contain;"],
    ["object-cover", "object-fit: cover;"],
    ["object-fill", "object-fit: fill;"],
    ["object-none", "object-fit: none;"],
    ["object-scale-down", "object-fit: scale-down;"],
  ],
  "Layout",
  "object-fit",
);
addStatic(
  [
    ["box-border", "box-sizing: border-box;"],
    ["box-content", "box-sizing: content-box;"],
  ],
  "Layout",
  "box-sizing",
);
addStatic(
  [
    ["float-start", "float: inline-start;"],
    ["float-end", "float: inline-end;"],
    ["float-right", "float: right;"],
    ["float-left", "float: left;"],
    ["float-none", "float: none;"],
  ],
  "Layout",
  "float",
);
addStatic(
  [
    ["isolate", "isolation: isolate;"],
    ["isolation-auto", "isolation: auto;"],
  ],
  "Layout",
  "isolation",
);
addStatic(
  [
    ["z-0", "z-index: 0;"],
    ["z-10", "z-index: 10;"],
    ["z-20", "z-index: 20;"],
    ["z-30", "z-index: 30;"],
    ["z-40", "z-index: 40;"],
    ["z-50", "z-index: 50;"],
    ["z-auto", "z-index: auto;"],
  ],
  "Layout",
  "z-index",
);

// Inset (top / right / bottom / left)
const INSET = {
  ...SPACING,
  auto: "auto",
  "1/2": "50%",
  "1/3": "33.333333%",
  "2/3": "66.666667%",
  "1/4": "25%",
  "3/4": "75%",
  full: "100%",
};
addScale("inset", ["inset"], INSET, "Layout", "top-right-bottom-left", {
  negatives: true,
});
addScale(
  "inset-x",
  ["left", "right"],
  INSET,
  "Layout",
  "top-right-bottom-left",
  { negatives: true },
);
addScale(
  "inset-y",
  ["top", "bottom"],
  INSET,
  "Layout",
  "top-right-bottom-left",
  { negatives: true },
);
addScale("top", ["top"], INSET, "Layout", "top-right-bottom-left", {
  negatives: true,
});
addScale("right", ["right"], INSET, "Layout", "top-right-bottom-left", {
  negatives: true,
});
addScale("bottom", ["bottom"], INSET, "Layout", "top-right-bottom-left", {
  negatives: true,
});
addScale("left", ["left"], INSET, "Layout", "top-right-bottom-left", {
  negatives: true,
});

// ---- Flexbox & Grid ---------------------------------------------------------
addStatic(
  [
    ["flex-row", "flex-direction: row;"],
    ["flex-row-reverse", "flex-direction: row-reverse;"],
    ["flex-col", "flex-direction: column;"],
    ["flex-col-reverse", "flex-direction: column-reverse;"],
  ],
  "Flexbox & Grid",
  "flex-direction",
);
addStatic(
  [
    ["flex-wrap", "flex-wrap: wrap;"],
    ["flex-wrap-reverse", "flex-wrap: wrap-reverse;"],
    ["flex-nowrap", "flex-wrap: nowrap;"],
  ],
  "Flexbox & Grid",
  "flex-wrap",
);
addStatic(
  [
    ["flex-1", "flex: 1 1 0%;"],
    ["flex-auto", "flex: 1 1 auto;"],
    ["flex-initial", "flex: 0 1 auto;"],
    ["flex-none", "flex: none;"],
  ],
  "Flexbox & Grid",
  "flex",
);
addStatic(
  [
    ["grow", "flex-grow: 1;"],
    ["grow-0", "flex-grow: 0;"],
  ],
  "Flexbox & Grid",
  "flex-grow",
);
addStatic(
  [
    ["shrink", "flex-shrink: 1;"],
    ["shrink-0", "flex-shrink: 0;"],
  ],
  "Flexbox & Grid",
  "flex-shrink",
);
addStatic(
  [
    ["justify-normal", "justify-content: normal;"],
    ["justify-start", "justify-content: flex-start;"],
    ["justify-end", "justify-content: flex-end;"],
    ["justify-center", "justify-content: center;"],
    ["justify-between", "justify-content: space-between;"],
    ["justify-around", "justify-content: space-around;"],
    ["justify-evenly", "justify-content: space-evenly;"],
    ["justify-stretch", "justify-content: stretch;"],
  ],
  "Flexbox & Grid",
  "justify-content",
);
addStatic(
  [
    ["justify-items-start", "justify-items: start;"],
    ["justify-items-end", "justify-items: end;"],
    ["justify-items-center", "justify-items: center;"],
    ["justify-items-stretch", "justify-items: stretch;"],
  ],
  "Flexbox & Grid",
  "justify-items",
);
addStatic(
  [
    ["justify-self-auto", "justify-self: auto;"],
    ["justify-self-start", "justify-self: start;"],
    ["justify-self-end", "justify-self: end;"],
    ["justify-self-center", "justify-self: center;"],
    ["justify-self-stretch", "justify-self: stretch;"],
  ],
  "Flexbox & Grid",
  "justify-self",
);
addStatic(
  [
    ["items-start", "align-items: flex-start;"],
    ["items-end", "align-items: flex-end;"],
    ["items-center", "align-items: center;"],
    ["items-baseline", "align-items: baseline;"],
    ["items-stretch", "align-items: stretch;"],
  ],
  "Flexbox & Grid",
  "align-items",
);
addStatic(
  [
    ["self-auto", "align-self: auto;"],
    ["self-start", "align-self: flex-start;"],
    ["self-end", "align-self: flex-end;"],
    ["self-center", "align-self: center;"],
    ["self-stretch", "align-self: stretch;"],
    ["self-baseline", "align-self: baseline;"],
  ],
  "Flexbox & Grid",
  "align-self",
);
addStatic(
  [
    ["content-normal", "align-content: normal;"],
    ["content-center", "align-content: center;"],
    ["content-start", "align-content: flex-start;"],
    ["content-end", "align-content: flex-end;"],
    ["content-between", "align-content: space-between;"],
    ["content-around", "align-content: space-around;"],
    ["content-evenly", "align-content: space-evenly;"],
    ["content-stretch", "align-content: stretch;"],
  ],
  "Flexbox & Grid",
  "align-content",
);
addStatic(
  [
    ["place-items-start", "place-items: start;"],
    ["place-items-end", "place-items: end;"],
    ["place-items-center", "place-items: center;"],
    ["place-items-stretch", "place-items: stretch;"],
    ["place-content-center", "place-content: center;"],
    ["place-content-start", "place-content: start;"],
    ["place-content-end", "place-content: end;"],
    ["place-content-between", "place-content: space-between;"],
    ["place-content-around", "place-content: space-around;"],
    ["place-content-evenly", "place-content: space-evenly;"],
    ["place-content-stretch", "place-content: stretch;"],
  ],
  "Flexbox & Grid",
  "place-content",
);
// grid columns / rows
for (let n = 1; n <= 12; n++)
  add(
    `grid-cols-${n}`,
    `grid-template-columns: repeat(${n}, minmax(0, 1fr));`,
    "Flexbox & Grid",
    "grid-template-columns",
  );
add(
  "grid-cols-none",
  "grid-template-columns: none;",
  "Flexbox & Grid",
  "grid-template-columns",
);
add(
  "grid-cols-subgrid",
  "grid-template-columns: subgrid;",
  "Flexbox & Grid",
  "grid-template-columns",
);
for (let n = 1; n <= 6; n++)
  add(
    `grid-rows-${n}`,
    `grid-template-rows: repeat(${n}, minmax(0, 1fr));`,
    "Flexbox & Grid",
    "grid-template-rows",
  );
add(
  "grid-rows-none",
  "grid-template-rows: none;",
  "Flexbox & Grid",
  "grid-template-rows",
);
for (let n = 1; n <= 12; n++)
  add(
    `col-span-${n}`,
    `grid-column: span ${n} / span ${n};`,
    "Flexbox & Grid",
    "grid-column",
  );
add("col-auto", "grid-column: auto;", "Flexbox & Grid", "grid-column");
add("col-span-full", "grid-column: 1 / -1;", "Flexbox & Grid", "grid-column");
for (let n = 1; n <= 13; n++)
  add(
    `col-start-${n}`,
    `grid-column-start: ${n};`,
    "Flexbox & Grid",
    "grid-column",
  );
for (let n = 1; n <= 13; n++)
  add(
    `col-end-${n}`,
    `grid-column-end: ${n};`,
    "Flexbox & Grid",
    "grid-column",
  );
for (let n = 1; n <= 6; n++)
  add(
    `row-span-${n}`,
    `grid-row: span ${n} / span ${n};`,
    "Flexbox & Grid",
    "grid-row",
  );
add("row-auto", "grid-row: auto;", "Flexbox & Grid", "grid-row");
add("row-span-full", "grid-row: 1 / -1;", "Flexbox & Grid", "grid-row");
addStatic(
  [
    ["grid-flow-row", "grid-auto-flow: row;"],
    ["grid-flow-col", "grid-auto-flow: column;"],
    ["grid-flow-dense", "grid-auto-flow: dense;"],
    ["grid-flow-row-dense", "grid-auto-flow: row dense;"],
    ["grid-flow-col-dense", "grid-auto-flow: column dense;"],
  ],
  "Flexbox & Grid",
  "grid-auto-flow",
);
addStatic(
  [
    ["order-first", "order: -9999;"],
    ["order-last", "order: 9999;"],
    ["order-none", "order: 0;"],
  ],
  "Flexbox & Grid",
  "order",
);
for (let n = 1; n <= 12; n++)
  add(`order-${n}`, `order: ${n};`, "Flexbox & Grid", "order");
// gap / space-between
addScale("gap", ["gap"], SPACING, "Flexbox & Grid", "gap");
addScale("gap-x", ["column-gap"], SPACING, "Flexbox & Grid", "gap");
addScale("gap-y", ["row-gap"], SPACING, "Flexbox & Grid", "gap");
for (const key of Object.keys(SPACING)) {
  add(
    `space-x-${key}`,
    `> :not([hidden]) ~ :not([hidden]) { margin-left: ${SPACING[key]}; }`,
    "Flexbox & Grid",
    "space",
  );
  add(
    `space-y-${key}`,
    `> :not([hidden]) ~ :not([hidden]) { margin-top: ${SPACING[key]}; }`,
    "Flexbox & Grid",
    "space",
  );
}

// ---- Spacing (padding / margin) --------------------------------------------
const PAD_SIDES = {
  "": ["padding"],
  x: ["padding-left", "padding-right"],
  y: ["padding-top", "padding-bottom"],
  t: ["padding-top"],
  r: ["padding-right"],
  b: ["padding-bottom"],
  l: ["padding-left"],
  s: ["padding-inline-start"],
  e: ["padding-inline-end"],
};
for (const s of Object.keys(PAD_SIDES))
  addScale(`p${s}`, PAD_SIDES[s], SPACING, "Spacing", "padding");
const MAR = { ...SPACING, auto: "auto" };
const MAR_SIDES = {
  "": ["margin"],
  x: ["margin-left", "margin-right"],
  y: ["margin-top", "margin-bottom"],
  t: ["margin-top"],
  r: ["margin-right"],
  b: ["margin-bottom"],
  l: ["margin-left"],
  s: ["margin-inline-start"],
  e: ["margin-inline-end"],
};
for (const s of Object.keys(MAR_SIDES))
  addScale(`m${s}`, MAR_SIDES[s], MAR, "Spacing", "margin", {
    negatives: true,
  });

// ---- Sizing (width / height) ------------------------------------------------
const W = {
  ...SPACING,
  ...FRACTIONS,
  auto: "auto",
  screen: "100vw",
  svw: "100svw",
  lvw: "100lvw",
  dvw: "100dvw",
  min: "min-content",
  max: "max-content",
  fit: "fit-content",
};
addScale("w", ["width"], W, "Sizing", "width");
const H = {
  ...SPACING,
  "1/2": "50%",
  "1/3": "33.333333%",
  "2/3": "66.666667%",
  "1/4": "25%",
  "3/4": "75%",
  full: "100%",
  auto: "auto",
  screen: "100vh",
  svh: "100svh",
  lvh: "100lvh",
  dvh: "100dvh",
  min: "min-content",
  max: "max-content",
  fit: "fit-content",
};
addScale("h", ["height"], H, "Sizing", "height");
const SIZE = {
  ...SPACING,
  ...FRACTIONS,
  auto: "auto",
  min: "min-content",
  max: "max-content",
  fit: "fit-content",
};
addScale("size", ["width", "height"], SIZE, "Sizing", "size");
addScale(
  "min-w",
  ["min-width"],
  {
    0: "0px",
    full: "100%",
    min: "min-content",
    max: "max-content",
    fit: "fit-content",
  },
  "Sizing",
  "min-width",
);
addScale(
  "min-h",
  ["min-height"],
  {
    0: "0px",
    full: "100%",
    screen: "100vh",
    svh: "100svh",
    lvh: "100lvh",
    dvh: "100dvh",
    min: "min-content",
    max: "max-content",
    fit: "fit-content",
  },
  "Sizing",
  "min-height",
);
const MAXW = {
  0: "0rem",
  none: "none",
  xs: "20rem",
  sm: "24rem",
  md: "28rem",
  lg: "32rem",
  xl: "36rem",
  "2xl": "42rem",
  "3xl": "48rem",
  "4xl": "56rem",
  "5xl": "64rem",
  "6xl": "72rem",
  "7xl": "80rem",
  full: "100%",
  min: "min-content",
  max: "max-content",
  fit: "fit-content",
  prose: "65ch",
};
addScale("max-w", ["max-width"], MAXW, "Sizing", "max-width");
addScale(
  "max-h",
  ["max-height"],
  {
    ...SPACING,
    none: "none",
    full: "100%",
    screen: "100vh",
    min: "min-content",
    max: "max-content",
    fit: "fit-content",
  },
  "Sizing",
  "max-height",
);

// ---- Typography -------------------------------------------------------------
const FONT_SIZE = {
  xs: ["0.75rem", "1rem"],
  sm: ["0.875rem", "1.25rem"],
  base: ["1rem", "1.5rem"],
  lg: ["1.125rem", "1.75rem"],
  xl: ["1.25rem", "1.75rem"],
  "2xl": ["1.5rem", "2rem"],
  "3xl": ["1.875rem", "2.25rem"],
  "4xl": ["2.25rem", "2.5rem"],
  "5xl": ["3rem", "1"],
  "6xl": ["3.75rem", "1"],
  "7xl": ["4.5rem", "1"],
  "8xl": ["6rem", "1"],
  "9xl": ["8rem", "1"],
};
for (const key of Object.keys(FONT_SIZE)) {
  const [fs, lh] = FONT_SIZE[key];
  add(
    `text-${key}`,
    `font-size: ${fs}; line-height: ${lh};`,
    "Typography",
    "font-size",
  );
}
addStatic(
  [
    ["font-thin", "font-weight: 100;"],
    ["font-extralight", "font-weight: 200;"],
    ["font-light", "font-weight: 300;"],
    ["font-normal", "font-weight: 400;"],
    ["font-medium", "font-weight: 500;"],
    ["font-semibold", "font-weight: 600;"],
    ["font-bold", "font-weight: 700;"],
    ["font-extrabold", "font-weight: 800;"],
    ["font-black", "font-weight: 900;"],
  ],
  "Typography",
  "font-weight",
);
addStatic(
  [
    [
      "font-sans",
      'font-family: ui-sans-serif, system-ui, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji";',
    ],
    [
      "font-serif",
      'font-family: ui-serif, Georgia, Cambria, "Times New Roman", Times, serif;',
    ],
    [
      "font-mono",
      'font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;',
    ],
  ],
  "Typography",
  "font-family",
);
addStatic(
  [
    ["italic", "font-style: italic;"],
    ["not-italic", "font-style: normal;"],
  ],
  "Typography",
  "font-style",
);
addStatic(
  [
    ["text-left", "text-align: left;"],
    ["text-center", "text-align: center;"],
    ["text-right", "text-align: right;"],
    ["text-justify", "text-align: justify;"],
    ["text-start", "text-align: start;"],
    ["text-end", "text-align: end;"],
  ],
  "Typography",
  "text-align",
);
addStatic(
  [
    ["underline", "text-decoration-line: underline;"],
    ["overline", "text-decoration-line: overline;"],
    ["line-through", "text-decoration-line: line-through;"],
    ["no-underline", "text-decoration-line: none;"],
  ],
  "Typography",
  "text-decoration",
);
addStatic(
  [
    ["uppercase", "text-transform: uppercase;"],
    ["lowercase", "text-transform: lowercase;"],
    ["capitalize", "text-transform: capitalize;"],
    ["normal-case", "text-transform: none;"],
  ],
  "Typography",
  "text-transform",
);
addStatic(
  [
    [
      "truncate",
      "overflow: hidden; text-overflow: ellipsis; white-space: nowrap;",
    ],
    ["text-ellipsis", "text-overflow: ellipsis;"],
    ["text-clip", "text-overflow: clip;"],
  ],
  "Typography",
  "text-overflow",
);
addStatic(
  [
    ["whitespace-normal", "white-space: normal;"],
    ["whitespace-nowrap", "white-space: nowrap;"],
    ["whitespace-pre", "white-space: pre;"],
    ["whitespace-pre-line", "white-space: pre-line;"],
    ["whitespace-pre-wrap", "white-space: pre-wrap;"],
  ],
  "Typography",
  "whitespace",
);
addStatic(
  [
    ["break-normal", "overflow-wrap: normal; word-break: normal;"],
    ["break-words", "overflow-wrap: break-word;"],
    ["break-all", "word-break: break-all;"],
    ["break-keep", "word-break: keep-all;"],
  ],
  "Typography",
  "word-break",
);
addStatic(
  [
    ["list-none", "list-style-type: none;"],
    ["list-disc", "list-style-type: disc;"],
    ["list-decimal", "list-style-type: decimal;"],
    ["list-inside", "list-style-position: inside;"],
    ["list-outside", "list-style-position: outside;"],
  ],
  "Typography",
  "list-style-type",
);
addStatic(
  [
    ["tracking-tighter", "letter-spacing: -0.05em;"],
    ["tracking-tight", "letter-spacing: -0.025em;"],
    ["tracking-normal", "letter-spacing: 0em;"],
    ["tracking-wide", "letter-spacing: 0.025em;"],
    ["tracking-wider", "letter-spacing: 0.05em;"],
    ["tracking-widest", "letter-spacing: 0.1em;"],
  ],
  "Typography",
  "letter-spacing",
);
addStatic(
  [
    ["leading-none", "line-height: 1;"],
    ["leading-tight", "line-height: 1.25;"],
    ["leading-snug", "line-height: 1.375;"],
    ["leading-normal", "line-height: 1.5;"],
    ["leading-relaxed", "line-height: 1.625;"],
    ["leading-loose", "line-height: 2;"],
  ],
  "Typography",
  "line-height",
);
for (const n of [3, 4, 5, 6, 7, 8, 9, 10])
  add(
    `leading-${n}`,
    `line-height: ${SPACING[n]};`,
    "Typography",
    "line-height",
  );
addStatic(
  [
    ["align-baseline", "vertical-align: baseline;"],
    ["align-top", "vertical-align: top;"],
    ["align-middle", "vertical-align: middle;"],
    ["align-bottom", "vertical-align: bottom;"],
    ["align-text-top", "vertical-align: text-top;"],
    ["align-text-bottom", "vertical-align: text-bottom;"],
  ],
  "Typography",
  "vertical-align",
);
addStatic(
  [
    ["decoration-solid", "text-decoration-style: solid;"],
    ["decoration-double", "text-decoration-style: double;"],
    ["decoration-dotted", "text-decoration-style: dotted;"],
    ["decoration-dashed", "text-decoration-style: dashed;"],
    ["decoration-wavy", "text-decoration-style: wavy;"],
  ],
  "Typography",
  "text-decoration-style",
);

// ---- Colors (bg / text / border / ring / …) --------------------------------
const COLOR_PREFIXES = {
  bg: ["background-color", "background-color"],
  text: ["color", "color"],
  border: ["border-color", "border-color"],
  ring: ["--tw-ring-color", "ring color"],
  divide: ["border-color", "divide color (between children)"],
  outline: ["outline-color", "outline-color"],
  decoration: ["text-decoration-color", "text-decoration-color"],
  caret: ["caret-color", "caret-color"],
  accent: ["accent-color", "accent-color"],
  fill: ["fill", "fill"],
  stroke: ["stroke", "stroke"],
  from: ["--tw-gradient-from", "gradient start"],
  via: ["--tw-gradient-via", "gradient middle"],
  to: ["--tw-gradient-to", "gradient end"],
  shadow: ["--tw-shadow-color", "colored shadow"],
};
const COLOR_DOC = {
  bg: "background-color",
  text: "text-color",
  border: "border-color",
  ring: "ring-color",
  divide: "divide-color",
  outline: "outline-color",
  decoration: "text-decoration-color",
  caret: "caret-color",
  accent: "accent-color",
  fill: "fill",
  stroke: "stroke",
  from: "gradient-color-stops",
  via: "gradient-color-stops",
  to: "gradient-color-stops",
  shadow: "box-shadow-color",
};
function colorCat(prefix) {
  if (prefix === "bg") return "Backgrounds";
  if (prefix === "text" || prefix === "decoration") return "Typography";
  if (prefix === "fill" || prefix === "stroke") return "SVG";
  return "Borders";
}
function addColor(prefix, name, hex) {
  const [prop] = COLOR_PREFIXES[prefix];
  const css = `${prop}: ${hex};`;
  add(`${prefix}-${name}`, css, colorCat(prefix), COLOR_DOC[prefix], {
    hex: hex.startsWith("#") ? hex : undefined,
  });
}
for (const prefix of Object.keys(COLOR_PREFIXES)) {
  for (const [name, hex] of Object.entries(SPECIAL_COLORS))
    addColor(prefix, name, hex);
  for (const color of Object.keys(PALETTE)) {
    for (const shade of Object.keys(PALETTE[color]))
      addColor(prefix, `${color}-${shade}`, PALETTE[color][shade]);
  }
}
// text-color also owns the font-size classes above; opacity helpers:
for (const o of [0, 5, 10, 20, 25, 30, 40, 50, 60, 70, 75, 80, 90, 95, 100])
  add(`opacity-${o}`, `opacity: ${o / 100};`, "Effects", "opacity");

// ---- Backgrounds (non-color) ------------------------------------------------
addStatic(
  [
    ["bg-none", "background-image: none;"],
    [
      "bg-gradient-to-t",
      "background-image: linear-gradient(to top, var(--tw-gradient-stops));",
    ],
    [
      "bg-gradient-to-tr",
      "background-image: linear-gradient(to top right, var(--tw-gradient-stops));",
    ],
    [
      "bg-gradient-to-r",
      "background-image: linear-gradient(to right, var(--tw-gradient-stops));",
    ],
    [
      "bg-gradient-to-br",
      "background-image: linear-gradient(to bottom right, var(--tw-gradient-stops));",
    ],
    [
      "bg-gradient-to-b",
      "background-image: linear-gradient(to bottom, var(--tw-gradient-stops));",
    ],
    [
      "bg-gradient-to-bl",
      "background-image: linear-gradient(to bottom left, var(--tw-gradient-stops));",
    ],
    [
      "bg-gradient-to-l",
      "background-image: linear-gradient(to left, var(--tw-gradient-stops));",
    ],
    [
      "bg-gradient-to-tl",
      "background-image: linear-gradient(to top left, var(--tw-gradient-stops));",
    ],
  ],
  "Backgrounds",
  "background-image",
);
addStatic(
  [
    ["bg-fixed", "background-attachment: fixed;"],
    ["bg-local", "background-attachment: local;"],
    ["bg-scroll", "background-attachment: scroll;"],
    ["bg-cover", "background-size: cover;"],
    ["bg-contain", "background-size: contain;"],
    ["bg-auto", "background-size: auto;"],
    ["bg-repeat", "background-repeat: repeat;"],
    ["bg-no-repeat", "background-repeat: no-repeat;"],
    ["bg-repeat-x", "background-repeat: repeat-x;"],
    ["bg-center", "background-position: center;"],
    ["bg-top", "background-position: top;"],
    ["bg-bottom", "background-position: bottom;"],
  ],
  "Backgrounds",
  "background-size",
);

// ---- Borders ----------------------------------------------------------------
const RADIUS = {
  none: "0px",
  sm: "0.125rem",
  "": "0.25rem",
  md: "0.375rem",
  lg: "0.5rem",
  xl: "0.75rem",
  "2xl": "1rem",
  "3xl": "1.5rem",
  full: "9999px",
};
const RADIUS_SIDES = {
  "": ["border-radius"],
  t: ["border-top-left-radius", "border-top-right-radius"],
  r: ["border-top-right-radius", "border-bottom-right-radius"],
  b: ["border-bottom-right-radius", "border-bottom-left-radius"],
  l: ["border-top-left-radius", "border-bottom-left-radius"],
  tl: ["border-top-left-radius"],
  tr: ["border-top-right-radius"],
  br: ["border-bottom-right-radius"],
  bl: ["border-bottom-left-radius"],
};
for (const side of Object.keys(RADIUS_SIDES)) {
  for (const key of Object.keys(RADIUS)) {
    const base = side ? `rounded-${side}` : "rounded";
    const cls = key === "" ? base : `${base}-${key}`;
    const css = RADIUS_SIDES[side]
      .map((p) => `${p}: ${RADIUS[key]};`)
      .join(" ");
    add(cls, css, "Borders", "border-radius");
  }
}
const BW = { "": "1px", 0: "0px", 2: "2px", 4: "4px", 8: "8px" };
const BW_SIDES = {
  "": ["border-width"],
  x: ["border-left-width", "border-right-width"],
  y: ["border-top-width", "border-bottom-width"],
  t: ["border-top-width"],
  r: ["border-right-width"],
  b: ["border-bottom-width"],
  l: ["border-left-width"],
  s: ["border-inline-start-width"],
  e: ["border-inline-end-width"],
};
for (const side of Object.keys(BW_SIDES)) {
  for (const key of Object.keys(BW)) {
    const base = side ? `border-${side}` : "border";
    const cls = key === "" ? base : `${base}-${key}`;
    const css = BW_SIDES[side].map((p) => `${p}: ${BW[key]};`).join(" ");
    add(cls, css, "Borders", "border-width");
  }
}
addStatic(
  [
    ["border-solid", "border-style: solid;"],
    ["border-dashed", "border-style: dashed;"],
    ["border-dotted", "border-style: dotted;"],
    ["border-double", "border-style: double;"],
    ["border-hidden", "border-style: hidden;"],
    ["border-none", "border-style: none;"],
  ],
  "Borders",
  "border-style",
);
addStatic(
  [
    ["outline-none", "outline: 2px solid transparent; outline-offset: 2px;"],
    ["outline", "outline-style: solid;"],
    ["outline-dashed", "outline-style: dashed;"],
    ["outline-dotted", "outline-style: dotted;"],
    ["outline-double", "outline-style: double;"],
    ["outline-0", "outline-width: 0px;"],
    ["outline-1", "outline-width: 1px;"],
    ["outline-2", "outline-width: 2px;"],
    ["outline-4", "outline-width: 4px;"],
    ["outline-8", "outline-width: 8px;"],
  ],
  "Borders",
  "outline-width",
);
addStatic(
  [
    ["ring", "box-shadow: 0 0 0 3px var(--tw-ring-color);"],
    ["ring-0", "box-shadow: 0 0 0 0px var(--tw-ring-color);"],
    ["ring-1", "box-shadow: 0 0 0 1px var(--tw-ring-color);"],
    ["ring-2", "box-shadow: 0 0 0 2px var(--tw-ring-color);"],
    ["ring-4", "box-shadow: 0 0 0 4px var(--tw-ring-color);"],
    ["ring-8", "box-shadow: 0 0 0 8px var(--tw-ring-color);"],
    ["ring-inset", "--tw-ring-inset: inset;"],
  ],
  "Borders",
  "ring-width",
);

// ---- Effects ----------------------------------------------------------------
addStatic(
  [
    ["shadow-sm", "box-shadow: 0 1px 2px 0 rgb(0 0 0 / 0.05);"],
    [
      "shadow",
      "box-shadow: 0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1);",
    ],
    [
      "shadow-md",
      "box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1);",
    ],
    [
      "shadow-lg",
      "box-shadow: 0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1);",
    ],
    [
      "shadow-xl",
      "box-shadow: 0 20px 25px -5px rgb(0 0 0 / 0.1), 0 8px 10px -6px rgb(0 0 0 / 0.1);",
    ],
    ["shadow-2xl", "box-shadow: 0 25px 50px -12px rgb(0 0 0 / 0.25);"],
    ["shadow-inner", "box-shadow: inset 0 2px 4px 0 rgb(0 0 0 / 0.05);"],
    ["shadow-none", "box-shadow: 0 0 #0000;"],
  ],
  "Effects",
  "box-shadow",
);
addStatic(
  [
    ["mix-blend-normal", "mix-blend-mode: normal;"],
    ["mix-blend-multiply", "mix-blend-mode: multiply;"],
    ["mix-blend-screen", "mix-blend-mode: screen;"],
    ["mix-blend-overlay", "mix-blend-mode: overlay;"],
  ],
  "Effects",
  "mix-blend-mode",
);

// ---- Filters ----------------------------------------------------------------
addStatic(
  [
    ["blur-none", "filter: blur(0);"],
    ["blur-sm", "filter: blur(4px);"],
    ["blur", "filter: blur(8px);"],
    ["blur-md", "filter: blur(12px);"],
    ["blur-lg", "filter: blur(16px);"],
    ["blur-xl", "filter: blur(24px);"],
    ["blur-2xl", "filter: blur(40px);"],
    ["blur-3xl", "filter: blur(64px);"],
  ],
  "Filters",
  "blur",
);
addStatic(
  [
    ["grayscale-0", "filter: grayscale(0);"],
    ["grayscale", "filter: grayscale(100%);"],
    ["invert-0", "filter: invert(0);"],
    ["invert", "filter: invert(100%);"],
    ["sepia-0", "filter: sepia(0);"],
    ["sepia", "filter: sepia(100%);"],
    ["backdrop-blur", "backdrop-filter: blur(8px);"],
    ["backdrop-blur-sm", "backdrop-filter: blur(4px);"],
    ["backdrop-blur-md", "backdrop-filter: blur(12px);"],
    ["backdrop-blur-lg", "backdrop-filter: blur(16px);"],
  ],
  "Filters",
  "grayscale",
);
for (const b of [0, 50, 75, 90, 95, 100, 105, 110, 125, 150, 200])
  add(
    `brightness-${b}`,
    `filter: brightness(${b / 100});`,
    "Filters",
    "brightness",
  );
for (const c of [0, 50, 75, 100, 125, 150, 200])
  add(`contrast-${c}`, `filter: contrast(${c / 100});`, "Filters", "contrast");

// ---- Transitions & animation ------------------------------------------------
addStatic(
  [
    ["transition-none", "transition-property: none;"],
    [
      "transition-all",
      "transition-property: all; transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1); transition-duration: 150ms;",
    ],
    [
      "transition",
      "transition-property: color, background-color, border-color, text-decoration-color, fill, stroke, opacity, box-shadow, transform, filter, backdrop-filter; transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1); transition-duration: 150ms;",
    ],
    [
      "transition-colors",
      "transition-property: color, background-color, border-color, text-decoration-color, fill, stroke; transition-duration: 150ms;",
    ],
    [
      "transition-opacity",
      "transition-property: opacity; transition-duration: 150ms;",
    ],
    [
      "transition-shadow",
      "transition-property: box-shadow; transition-duration: 150ms;",
    ],
    [
      "transition-transform",
      "transition-property: transform; transition-duration: 150ms;",
    ],
  ],
  "Transitions & Animation",
  "transition-property",
);
for (const d of [0, 75, 100, 150, 200, 300, 500, 700, 1000])
  add(
    `duration-${d}`,
    `transition-duration: ${d}ms;`,
    "Transitions & Animation",
    "transition-duration",
  );
for (const d of [0, 75, 100, 150, 200, 300, 500, 700, 1000])
  add(
    `delay-${d}`,
    `transition-delay: ${d}ms;`,
    "Transitions & Animation",
    "transition-delay",
  );
addStatic(
  [
    ["ease-linear", "transition-timing-function: linear;"],
    ["ease-in", "transition-timing-function: cubic-bezier(0.4, 0, 1, 1);"],
    ["ease-out", "transition-timing-function: cubic-bezier(0, 0, 0.2, 1);"],
    [
      "ease-in-out",
      "transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);",
    ],
  ],
  "Transitions & Animation",
  "transition-timing-function",
);
addStatic(
  [
    ["animate-none", "animation: none;"],
    ["animate-spin", "animation: spin 1s linear infinite;"],
    ["animate-ping", "animation: ping 1s cubic-bezier(0, 0, 0.2, 1) infinite;"],
    [
      "animate-pulse",
      "animation: pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;",
    ],
    ["animate-bounce", "animation: bounce 1s infinite;"],
  ],
  "Transitions & Animation",
  "animation",
);

// ---- Transforms -------------------------------------------------------------
for (const s of [0, 50, 75, 90, 95, 100, 105, 110, 125, 150]) {
  add(`scale-${s}`, `transform: scale(${s / 100});`, "Transforms", "scale");
  add(`scale-x-${s}`, `transform: scaleX(${s / 100});`, "Transforms", "scale");
  add(`scale-y-${s}`, `transform: scaleY(${s / 100});`, "Transforms", "scale");
}
for (const r of [0, 1, 2, 3, 6, 12, 45, 90, 180]) {
  add(`rotate-${r}`, `transform: rotate(${r}deg);`, "Transforms", "rotate");
  add(`-rotate-${r}`, `transform: rotate(-${r}deg);`, "Transforms", "rotate");
}
const TRANSLATE = { ...SPACING, ...FRACTIONS };
for (const key of Object.keys(TRANSLATE)) {
  add(
    `translate-x-${key}`,
    `transform: translateX(${TRANSLATE[key]});`,
    "Transforms",
    "translate",
  );
  add(
    `translate-y-${key}`,
    `transform: translateY(${TRANSLATE[key]});`,
    "Transforms",
    "translate",
  );
  if (TRANSLATE[key] !== "0px") {
    add(
      `-translate-x-${key}`,
      `transform: translateX(-${TRANSLATE[key]});`,
      "Transforms",
      "translate",
    );
    add(
      `-translate-y-${key}`,
      `transform: translateY(-${TRANSLATE[key]});`,
      "Transforms",
      "translate",
    );
  }
}
for (const sk of [0, 1, 2, 3, 6, 12]) {
  add(`skew-x-${sk}`, `transform: skewX(${sk}deg);`, "Transforms", "skew");
  add(`skew-y-${sk}`, `transform: skewY(${sk}deg);`, "Transforms", "skew");
}
addStatic(
  [
    ["origin-center", "transform-origin: center;"],
    ["origin-top", "transform-origin: top;"],
    ["origin-bottom", "transform-origin: bottom;"],
    ["origin-left", "transform-origin: left;"],
    ["origin-right", "transform-origin: right;"],
    ["origin-top-left", "transform-origin: top left;"],
    ["transform-gpu", "transform: translate3d(0,0,0);"],
    ["transform-none", "transform: none;"],
  ],
  "Transforms",
  "transform-origin",
);

// ---- Interactivity ----------------------------------------------------------
addStatic(
  [
    ["cursor-auto", "cursor: auto;"],
    ["cursor-default", "cursor: default;"],
    ["cursor-pointer", "cursor: pointer;"],
    ["cursor-wait", "cursor: wait;"],
    ["cursor-text", "cursor: text;"],
    ["cursor-move", "cursor: move;"],
    ["cursor-help", "cursor: help;"],
    ["cursor-not-allowed", "cursor: not-allowed;"],
    ["cursor-none", "cursor: none;"],
    ["cursor-grab", "cursor: grab;"],
    ["cursor-grabbing", "cursor: grabbing;"],
  ],
  "Interactivity",
  "cursor",
);
addStatic(
  [
    ["pointer-events-none", "pointer-events: none;"],
    ["pointer-events-auto", "pointer-events: auto;"],
  ],
  "Interactivity",
  "pointer-events",
);
addStatic(
  [
    ["select-none", "user-select: none;"],
    ["select-text", "user-select: text;"],
    ["select-all", "user-select: all;"],
    ["select-auto", "user-select: auto;"],
  ],
  "Interactivity",
  "user-select",
);
addStatic(
  [
    ["resize-none", "resize: none;"],
    ["resize-y", "resize: vertical;"],
    ["resize-x", "resize: horizontal;"],
    ["resize", "resize: both;"],
  ],
  "Interactivity",
  "resize",
);
addStatic(
  [
    ["scroll-smooth", "scroll-behavior: smooth;"],
    ["scroll-auto", "scroll-behavior: auto;"],
    ["snap-start", "scroll-snap-align: start;"],
    ["snap-center", "scroll-snap-align: center;"],
    ["snap-end", "scroll-snap-align: end;"],
    ["snap-x", "scroll-snap-type: x var(--tw-scroll-snap-strictness);"],
    ["snap-y", "scroll-snap-type: y var(--tw-scroll-snap-strictness);"],
    ["snap-mandatory", "--tw-scroll-snap-strictness: mandatory;"],
    ["snap-none", "scroll-snap-type: none;"],
  ],
  "Interactivity",
  "scroll-behavior",
);
addStatic(
  [
    ["appearance-none", "appearance: none;"],
    ["appearance-auto", "appearance: auto;"],
    ["will-change-auto", "will-change: auto;"],
    ["will-change-scroll", "will-change: scroll-position;"],
    ["will-change-transform", "will-change: transform;"],
    [
      "sr-only",
      "position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0,0,0,0); white-space: nowrap; border-width: 0;",
    ],
    [
      "not-sr-only",
      "position: static; width: auto; height: auto; padding: 0; margin: 0; overflow: visible; clip: auto; white-space: normal;",
    ],
    [
      "antialiased",
      "-webkit-font-smoothing: antialiased; -moz-osx-font-smoothing: grayscale;",
    ],
    [
      "subpixel-antialiased",
      "-webkit-font-smoothing: auto; -moz-osx-font-smoothing: auto;",
    ],
    ["aspect-auto", "aspect-ratio: auto;"],
    ["aspect-square", "aspect-ratio: 1 / 1;"],
    ["aspect-video", "aspect-ratio: 16 / 9;"],
    [
      "container",
      "width: 100%; /* + responsive max-widths at each breakpoint */",
    ],
  ],
  "Interactivity",
  "appearance",
);

log(`tailwind plugin: catalog ready with ${CATALOG.length} utilities`);

// ── category icons (must be names from spec §11) ──────────────────────────────
const CAT_ICON = {
  Layout: "window",
  "Flexbox & Grid": "grid",
  Spacing: "grid",
  Sizing: "grid",
  Typography: "label",
  Backgrounds: "palette",
  Borders: "window",
  Effects: "star",
  Filters: "brush",
  "Transitions & Animation": "bolt",
  Transforms: "refresh",
  Interactivity: "app",
  SVG: "image",
};
function catIcon(cat) {
  return CAT_ICON[cat] || "code";
}

// ── search ────────────────────────────────────────────────────────────────────
function score(entry, term) {
  const cls = entry.cls.toLowerCase();
  if (cls === term) return 100;
  if (cls.startsWith(term)) return 80;
  if (cls.includes(term)) return 55;
  if (entry.css.toLowerCase().includes(term)) return 30;
  if (entry.doc.toLowerCase().includes(term)) return 20;
  if (entry.cat.toLowerCase().includes(term)) return 12;
  return 0;
}
function searchCatalog(rawTerm) {
  const term = rawTerm.trim().toLowerCase();
  const scored = [];
  for (const entry of CATALOG) {
    const s = term ? score(entry, term) : 0;
    if (term && s === 0) continue;
    scored.push({ entry, s });
  }
  scored.sort((a, b) =>
    b.s !== a.s
      ? b.s - a.s
      : a.entry.cls.length - b.entry.cls.length ||
        a.entry.cls.localeCompare(b.entry.cls),
  );
  return scored.slice(0, 60).map((x) => x.entry);
}

// A short list shown when the query is empty, so the plugin is browsable.
const STARTER = [
  "flex",
  "grid",
  "hidden",
  "block",
  "items-center",
  "justify-center",
  "gap-4",
  "p-4",
  "px-4",
  "m-4",
  "mx-auto",
  "w-full",
  "h-screen",
  "text-center",
  "text-sm",
  "font-bold",
  "text-white",
  "bg-blue-500",
  "rounded-lg",
  "border",
  "shadow-md",
  "transition",
  "cursor-pointer",
  "absolute",
  "relative",
  "overflow-hidden",
  "grid-cols-3",
  "space-y-2",
];

// ── rendering ─────────────────────────────────────────────────────────────────
const itemsById = {}; // id -> { cls, css, url }

function previewMarkdown(entry) {
  const cssPretty = entry.css
    .split(/;\s+(?=[a-z-]+:)/)
    .map((d) =>
      d.trim().endsWith(";") ||
      d.trim().startsWith(">") ||
      d.trim().startsWith("/")
        ? d.trim()
        : `${d.trim()};`,
    )
    .join("\n  ");
  const swatch = entry.hex ? `\n**Color:** \`${entry.hex}\`\n` : "";
  return [
    `## \`${entry.cls}\``,
    "",
    `**Category:** ${entry.cat}${swatch}`,
    "",
    "**Generated CSS**",
    "",
    "```css",
    `.${cssEscape(entry.cls)} {`,
    `  ${cssPretty}`,
    "}",
    "```",
    "",
    "**Example**",
    "",
    "```html",
    `<div class="${entry.cls}">…</div>`,
    "```",
    "",
    `[Open docs → tailwindcss.com/docs/${entry.doc}](${DOCS(entry.doc)})`,
  ].join("\n");
}
// Tailwind escapes special chars in the generated selector; approximate it.
function cssEscape(cls) {
  return cls.replace(/([.:/[\]])/g, "\\$1");
}

function toItem(entry) {
  const id = `tw:${entry.cls}`;
  const item = {
    id,
    title: entry.cls,
    subtitle: entry.css,
    icon: entry.hex ? "palette" : catIcon(entry.cat),
    accessories: [{ text: entry.cat }],
    actions: [
      { id: "default", title: "Copy Class Name", icon: "copy" },
      { id: "copy_css", title: "Copy Generated CSS", icon: "code" },
      { id: "open_docs", title: "Open on tailwindcss.com", icon: "open" },
    ],
    preview: { markdown: previewMarkdown(entry) },
  };
  itemsById[id] = { cls: entry.cls, css: entry.css, url: DOCS(entry.doc) };
  return item;
}

function renderQuery(rev, text) {
  const term = (text || "").trim();
  // Empty query → a curated starter list so the plugin is browsable; otherwise
  // rank the catalog against the term.
  const entries = term
    ? searchCatalog(term)
    : STARTER.map((c) => CATALOG.find((e) => e.cls === c)).filter(Boolean);
  render(rev, "list", {
    items: entries.map(toItem),
    preview: { enabled: true },
    emptyText: term
      ? `No Tailwind utility matches “${term}”`
      : "Type a class name or CSS property",
  });
}

// ── action handling ───────────────────────────────────────────────────────────
function handleAction(id, action) {
  const it = itemsById[id];
  if (!it) return;
  switch (action) {
    case "copy_css":
      return copyToClipboard(it.css);
    case "open_docs":
      return openUrl(it.url);
    default:
      return copyToClipboard(it.cls);
  }
}

// ── stdin loop ─────────────────────────────────────────────────────────────────
let buffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buffer += chunk;
  let idx;
  while ((idx = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, idx).trim();
    buffer = buffer.slice(idx + 1);
    if (line) handleLine(line);
  }
});
process.stdin.on("end", () => process.exit(0));

function handleLine(line) {
  let msg;
  try {
    msg = JSON.parse(line);
  } catch (_) {
    return;
  }
  try {
    switch (msg.type) {
      case "close":
        process.exit(0);
        break;
      case "init":
      case "query":
        renderQuery(
          msg.rev || 0,
          msg.text != null ? msg.text : msg.query || "",
        );
        break;
      case "action":
        handleAction(msg.id, msg.action || "default");
        break;
      // 'select' needs no work — previews are provided per item.
    }
  } catch (err) {
    detailFrame(
      msg && msg.rev ? msg.rev : 0,
      `# Error\n\n\`\`\`\n${err && err.stack ? err.stack : err}\n\`\`\``,
    );
  }
}
