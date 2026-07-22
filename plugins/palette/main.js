"use strict";

/**
 * Color Palette — a Tabame launcher plugin.
 *
 * Keyword: "palette"
 *   palette                 -> list of your saved palettes
 *   palette <search>        -> filters palettes by name
 *   Enter on a palette      -> opens it (grid of color swatches)
 *   inside a palette:
 *     Enter on a color      -> copies its HEX and shows a toast
 *     Ctrl+K on a color     -> Copy RGB / Copy HSL / Edit / Delete
 *     Ctrl+K (frame)        -> Add Color / Rename Palette / Copy All / Delete Palette
 *   Ctrl+K on root          -> New Palette
 *
 * Data is kept in Tabame's per-plugin `storage` (key "palettes"), so it
 * survives restarts without us managing a file by hand.
 */

const crypto = require("crypto");

// ---------------------------------------------------------------------------
// stdout / stderr helpers
// ---------------------------------------------------------------------------

function send(frame) {
  process.stdout.write(JSON.stringify(frame) + "\n");
}

function log(...args) {
  console.error(...args); // debug only — never print non-protocol lines to stdout
}

function cmd(command, fields = {}) {
  send({ type: "command", command, ...fields });
}

function toast(text, style) {
  cmd("toast", { text, style });
}

// ---------------------------------------------------------------------------
// color helpers
// ---------------------------------------------------------------------------

function rgbToHex(r, g, b) {
  const clamp = (n) => Math.max(0, Math.min(255, n));
  return (
    "#" +
    [clamp(r), clamp(g), clamp(b)]
      .map((n) => n.toString(16).padStart(2, "0"))
      .join("")
      .toUpperCase()
  );
}

function hexToRgb(hex) {
  const h = hex.replace("#", "");
  const bigint = parseInt(h, 16);
  return { r: (bigint >> 16) & 255, g: (bigint >> 8) & 255, b: bigint & 255 };
}

function rgbToHslString(r, g, b) {
  r /= 255;
  g /= 255;
  b /= 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  let h = 0;
  let s = 0;
  const l = (max + min) / 2;
  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    switch (max) {
      case r:
        h = (g - b) / d + (g < b ? 6 : 0);
        break;
      case g:
        h = (b - r) / d + 2;
        break;
      default:
        h = (r - g) / d + 4;
    }
    h /= 6;
  }
  return `hsl(${Math.round(h * 360)}, ${Math.round(s * 100)}%, ${Math.round(l * 100)}%)`;
}

// Accepts "#RRGGBB", "RRGGBB", "#RGB", "RGB", "r,g,b", or "rgb(r,g,b)".
// Returns a normalized "#RRGGBB" string, or null if it can't be parsed.
function parseColor(input) {
  if (!input) return null;
  let s = String(input).trim();

  const rgbMatch = s.match(
    /^(?:rgba?\()?\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})/i,
  );
  if (rgbMatch) {
    const [r, g, b] = [1, 2, 3].map((i) => parseInt(rgbMatch[i], 10));
    if ([r, g, b].some((n) => Number.isNaN(n) || n < 0 || n > 255)) return null;
    return rgbToHex(r, g, b);
  }

  if (s.startsWith("#")) s = s.slice(1);
  if (/^[0-9A-Fa-f]{3}$/.test(s)) {
    s = s
      .split("")
      .map((ch) => ch + ch)
      .join("");
  }
  if (/^[0-9A-Fa-f]{6}$/.test(s)) {
    return "#" + s.toUpperCase();
  }
  return null;
}

function genId() {
  return crypto.randomUUID();
}

// ---------------------------------------------------------------------------
// WCAG contrast helpers
// ---------------------------------------------------------------------------

function relativeLuminance(hex) {
  const { r, g, b } = hexToRgb(hex);
  const [R, G, B] = [r, g, b].map((c) => {
    c /= 255;
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * R + 0.7152 * G + 0.0722 * B;
}

function contrastRatio(hexA, hexB) {
  const lA = relativeLuminance(hexA);
  const lB = relativeLuminance(hexB);
  const lighter = Math.max(lA, lB);
  const darker = Math.min(lA, lB);
  return (lighter + 0.05) / (darker + 0.05);
}

// ---------------------------------------------------------------------------
// Dominant color extraction (image import)
// ---------------------------------------------------------------------------

// Lazy-required so a plugin folder without node_modules installed yet still
// starts up fine for every other feature; only image import needs Jimp.
async function extractDominantColors(filePath, count) {
  const Jimp = require("jimp");
  const image = await Jimp.read(filePath);
  image.resize(120, Jimp.AUTO); // downscale first — keeps the pixel scan fast
  const { data } = image.bitmap; // RGBA buffer

  const step = 32; // quantize each channel into 8 buckets (256 / 32)
  const buckets = new Map();
  for (let i = 0; i < data.length; i += 4) {
    const alpha = data[i + 3];
    if (alpha < 128) continue; // skip transparent pixels
    const r = data[i];
    const g = data[i + 1];
    const b = data[i + 2];
    const key = `${r >> 5},${g >> 5},${b >> 5}`;
    let bucket = buckets.get(key);
    if (!bucket) {
      bucket = { count: 0, r: 0, g: 0, b: 0 };
      buckets.set(key, bucket);
    }
    bucket.count++;
    bucket.r += r;
    bucket.g += g;
    bucket.b += b;
  }

  const sorted = [...buckets.values()]
    .map((b) => ({
      count: b.count,
      hex: rgbToHex(
        Math.round(b.r / b.count),
        Math.round(b.g / b.count),
        Math.round(b.b / b.count),
      ),
    }))
    .sort((a, b) => b.count - a.count);

  // Greedily pick visually-distinct colors first, then top up with whatever
  // is left if the image didn't have enough spread.
  const picked = [];
  const minDistance = 28;
  for (const c of sorted) {
    if (picked.length >= count) break;
    const rgb = hexToRgb(c.hex);
    const tooClose = picked.some((p) => {
      const pRgb = hexToRgb(p.hex);
      const d = Math.sqrt(
        (pRgb.r - rgb.r) ** 2 + (pRgb.g - rgb.g) ** 2 + (pRgb.b - rgb.b) ** 2,
      );
      return d < minDistance;
    });
    if (!tooClose) picked.push(c);
  }
  if (picked.length < count) {
    for (const c of sorted) {
      if (picked.length >= count) break;
      if (!picked.find((p) => p.hex === c.hex)) picked.push(c);
    }
  }
  return picked.slice(0, count).map((c) => c.hex);
}

// ---------------------------------------------------------------------------
// state
// ---------------------------------------------------------------------------

const state = {
  screen: "root",
  // 'root' | 'palette'
  // | 'form:newPalette' | 'form:addColor' | 'form:editColor' | 'form:renamePalette'
  // | 'form:contrast' | 'detail:contrast'
  // | 'form:imageImport'
  historyStack: [],
  currentPaletteId: null,
  editingColorId: null,
  query: "",
  lastRev: 0,
  palettes: null, // null until loaded from storage
  loaded: false,
  contrastPrefill: { bg: "#FFFFFF", fg: "#000000" }, // last-used values for the contrast form
  contrastResult: null, // { bg, fg } once computed
  imageTarget: "new", // 'new' -> create a palette, 'current' -> add into the open palette
};

function getCurrentPalette() {
  return state.palettes.find((p) => p.id === state.currentPaletteId) || null;
}

function pushAndGo(newScreen) {
  state.historyStack.push({
    screen: state.screen,
    currentPaletteId: state.currentPaletteId,
  });
  state.screen = newScreen;
}

function popToPrevious() {
  const prev = state.historyStack.pop();
  if (prev) {
    state.screen = prev.screen;
    state.currentPaletteId = prev.currentPaletteId;
  } else {
    state.screen = "root";
    state.currentPaletteId = null;
  }
}

function resetToRoot() {
  state.historyStack = [];
  state.screen = "root";
  state.currentPaletteId = null;
  state.editingColorId = null;
}

function savePalettes() {
  cmd("storage", {
    op: "set",
    key: "palettes",
    value: JSON.stringify(state.palettes),
  });
}

// ---------------------------------------------------------------------------
// loading
// ---------------------------------------------------------------------------

function requestLoad() {
  cmd("storage", { op: "get", key: "palettes", requestId: "load-palettes" });
  // Defensive fallback: if a fresh install has never written the key, some
  // hosts may not reply at all rather than replying with an empty value.
  setTimeout(() => {
    if (!state.loaded) {
      state.palettes = [];
      state.loaded = true;
      render(state.lastRev, undefined, state.query);
    }
  }, 1500);
}

function renderLoading(rev) {
  send({
    type: "render",
    rev,
    view: "list",
    loading: true,
    loadingText: "Loading your palettes…",
    items: [],
  });
}

// ---------------------------------------------------------------------------
// render: root (palette list)
// ---------------------------------------------------------------------------

function renderRoot(rev, selectId, query = "") {
  const q = query.trim().toLowerCase();
  const filtered = q
    ? state.palettes.filter((p) => p.name.toLowerCase().includes(q))
    : state.palettes;

  const items = filtered.map((p) => ({
    id: p.id,
    title: p.name,
    subtitle: `${p.colors.length} color${p.colors.length === 1 ? "" : "s"}`,
    icon: p.colors[0] ? p.colors[0].hex : "palette",
    // accessories: p.colors.slice(0, 4).map((c) => ({
    //   text: c.hex.replace("#", ""),
    //   color: c.hex,
    // })),
    actions: [
      { id: "rename", title: "Rename Palette", icon: "edit" },
      {
        id: "delete",
        title: "Delete Palette",
        icon: "trash",
        destructive: true,
        confirm: {
          title: `Delete "${p.name}"?`,
          message: "This removes all of its colors. This cannot be undone.",
          confirmLabel: "Delete",
        },
      },
    ],
    preview: {
      markdown: `## ${p.name}\n\n${p.colors.length} color${p.colors.length === 1 ? "" : "s"}`,
      wide: false,
      metadata: [
        {
          label: "Colors",
          text: `${p.colors.length}`,
          actions: [{ id: "addColor", title: "Add Color", icon: "add" }],
        },
        { separator: true },
        ...(p.colors.length
          ? p.colors.map((c) => ({
              label: c.name || "Color",
              text: c.hex,
              color: c.hex,
              // actions: [{ id: `edit:${c.id}`, title: "Edit", icon: "edit" }],
            }))
          : [{ label: "Empty", text: "No colors yet" }]),
      ],
    },
  }));

  send({
    type: "render",
    rev,
    view: "list",
    preview: { enabled: true, wide: false },
    canGoBack: false,
    placeholder: "Search palettes, or Ctrl+K for more actions",
    actions: [
      { id: "new", title: "New Palette", icon: "add", shortcut: "ctrl+n" },
      {
        id: "fromImage",
        title: "New Palette from Image",
        icon: "image",
        shortcut: "alt+i",
      },
      {
        id: "contrast",
        title: "Contrast Checker",
        icon: "chart",
        shortcut: "alt+c",
      },
    ],
    empty: {
      icon: "palette",
      title: state.palettes.length ? "No matching palettes" : "No palettes yet",
      hint: state.palettes.length
        ? "Try a different search"
        : "Create a palette to start saving colors",
      action: { id: "new", title: "New Palette", icon: "add" },
    },
    selectId,
    items,
  });
}

// ---------------------------------------------------------------------------
// render: palette contents (grid of colors)
// ---------------------------------------------------------------------------

function renderPalette(rev, selectId, query = "") {
  const palette = getCurrentPalette();
  if (!palette) {
    resetToRoot();
    return renderRoot(rev, undefined, "");
  }

  const q = query.trim().toLowerCase();
  const filtered = q
    ? palette.colors.filter(
        (c) =>
          c.hex.toLowerCase().includes(q) ||
          (c.name || "").toLowerCase().includes(q),
      )
    : palette.colors;

  // Quick-add: if what's typed in the search box parses as a color that
  // isn't already saved, offer a tile to add it directly — no form needed.
  const quickAddHex = parseColor(query.trim());
  const alreadySaved =
    quickAddHex && palette.colors.some((c) => c.hex === quickAddHex);
  const quickAddItems =
    quickAddHex && !alreadySaved
      ? [
          {
            id: `quickadd:${quickAddHex}`,
            title: `Add ${quickAddHex}`,
            subtitle: "Press Enter to add",
            tileColor: quickAddHex,
            actions: [{ id: "default", title: "Add to palette", icon: "add" }],
          },
        ]
      : [];

  const items = quickAddItems.concat(
    filtered.map((c) => {
      const { r, g, b } = hexToRgb(c.hex);
      const rgbStr = `rgb(${r}, ${g}, ${b})`;
      const hslStr = rgbToHslString(r, g, b);
      return {
        id: c.id,
        title: c.name || c.hex,
        subtitle: c.hex,
        tileColor: c.hex,
        actions: [
          { id: "copyRgb", title: "Copy RGB", icon: "copy" },
          { id: "copyHsl", title: "Copy HSL", icon: "copy" },
          { id: "edit", title: "Edit Color", icon: "edit" },
          { id: "contrast", title: "Check Contrast", icon: "chart" },
          {
            id: "delete",
            title: "Delete Color",
            icon: "trash",
            destructive: true,
            confirm: { title: `Delete ${c.hex}?`, confirmLabel: "Delete" },
          },
        ],
        preview: {
          markdown: `## ${c.name || "Color"}\n\n\`${c.hex}\``,
          wide: false,
          metadata: [
            {
              label: "HEX",
              text: c.hex,
              color: c.hex,
              actions: [{ id: "default", title: "Copy", icon: "copy" }],
            },
            {
              label: "RGB",
              text: rgbStr,
              actions: [{ id: "copyRgb", title: "Copy", icon: "copy" }],
            },
            {
              label: "HSL",
              text: hslStr,
              actions: [{ id: "copyHsl", title: "Copy", icon: "copy" }],
            },
            { separator: true },
            {
              label: "Label",
              text: c.name || "—",
              actions: [{ id: "edit", title: "Edit", icon: "edit" }],
            },
            {
              label: "Contrast",
              text: "vs. white/black",
              actions: [{ id: "contrast", title: "Check", icon: "chart" }],
            },
          ],
        },
      };
    }),
  );

  send({
    type: "render",
    rev,
    view: "grid",
    grid: { columns: 5, aspectRatio: 1.1 },
    preview: { enabled: true, wide: false },
    canGoBack: true,
    placeholder: `Search or type a hex to quick-add — ${palette.name}`,
    actions: [
      { id: "addColor", title: "Add Color", icon: "add", shortcut: "ctrl+n" },
      {
        id: "colorsFromImage",
        title: "Add Colors from Image",
        icon: "image",
        shortcut: "alt+i",
      },
      { id: "renamePalette", title: "Rename Palette", icon: "edit" },
      { id: "copyAll", title: "Copy All Hex Codes", icon: "copy" },
      {
        id: "deletePalette",
        title: "Delete Palette",
        icon: "trash",
        destructive: true,
        confirm: {
          title: `Delete "${palette.name}"?`,
          message: "This removes all of its colors. This cannot be undone.",
          confirmLabel: "Delete",
        },
      },
    ],
    empty: {
      icon: "color",
      title: palette.colors.length ? "No matching colors" : "No colors yet",
      hint: palette.colors.length
        ? "Try a different search"
        : "Add a color to this palette",
      action: { id: "addColor", title: "Add Color", icon: "add" },
    },
    selectId,
    items,
  });
}

// ---------------------------------------------------------------------------
// render: forms
// ---------------------------------------------------------------------------

function renderNewPaletteForm(rev, errors = {}) {
  send({
    type: "render",
    rev,
    view: "form",
    canGoBack: true,
    form: {
      title: "New Palette",
      submitLabel: "Create",
      fields: [
        {
          id: "name",
          type: "text",
          label: "Palette name",
          placeholder: "e.g. Brand Colors",
          required: true,
          error: errors.name,
        },
      ],
    },
  });
}

function renderAddColorForm(rev, errors = {}) {
  const palette = getCurrentPalette();
  send({
    type: "render",
    rev,
    view: "form",
    canGoBack: true,
    form: {
      title: `Add Color — ${palette.name}`,
      submitLabel: "Add",
      fields: [
        {
          id: "hex",
          type: "text",
          label: "Color",
          placeholder: "#FF8800, FF8800, or 255,136,0",
          required: true,
          description: 'Hex (#RRGGBB) or "r,g,b"',
          error: errors.hex,
        },
        {
          id: "name",
          type: "text",
          label: "Label (optional)",
          placeholder: "e.g. Primary",
        },
      ],
    },
  });
}

function renderEditColorForm(rev, errors = {}) {
  const palette = getCurrentPalette();
  const color =
    palette && palette.colors.find((c) => c.id === state.editingColorId);
  if (!color) {
    popToPrevious();
    return render(rev);
  }
  send({
    type: "render",
    rev,
    view: "form",
    canGoBack: true,
    form: {
      title: "Edit Color",
      submitLabel: "Save",
      fields: [
        {
          id: "hex",
          type: "text",
          label: "Color",
          value: color.hex,
          required: true,
          description: 'Hex (#RRGGBB) or "r,g,b"',
          error: errors.hex,
        },
        {
          id: "name",
          type: "text",
          label: "Label (optional)",
          value: color.name || "",
        },
      ],
    },
  });
}

function renderRenamePaletteForm(rev, errors = {}) {
  const palette = getCurrentPalette();
  send({
    type: "render",
    rev,
    view: "form",
    canGoBack: true,
    form: {
      title: "Rename Palette",
      submitLabel: "Save",
      fields: [
        {
          id: "name",
          type: "text",
          label: "Palette name",
          value: palette.name,
          required: true,
          error: errors.name,
        },
      ],
    },
  });
}

// ---------------------------------------------------------------------------
// dispatcher
// ---------------------------------------------------------------------------

function render(rev, selectId, query) {
  const q = query !== undefined ? query : state.query;
  switch (state.screen) {
    case "root":
      return renderRoot(rev, selectId, q);
    case "palette":
      return renderPalette(rev, selectId, q);
    case "form:newPalette":
      return renderNewPaletteForm(rev);
    case "form:addColor":
      return renderAddColorForm(rev);
    case "form:editColor":
      return renderEditColorForm(rev);
    case "form:renamePalette":
      return renderRenamePaletteForm(rev);
    default:
      return renderRoot(rev, selectId, q);
  }
}

// ---------------------------------------------------------------------------
// action handling
// ---------------------------------------------------------------------------

function handleAction(id, action) {
  if (state.screen === "root") {
    if (id === "") {
      if (action === "new") {
        pushAndGo("form:newPalette");
        render(0);
      }
      return;
    }
    const palette = state.palettes.find((p) => p.id === id);
    if (!palette) return;

    if (action === "default") {
      pushAndGo("palette");
      state.currentPaletteId = id;
      state.query = "";
      render(0, undefined, "");
      cmd("setQuery", { text: "" });
    } else if (action === "rename") {
      pushAndGo("form:renamePalette");
      state.currentPaletteId = id;
      render(0);
    } else if (action === "delete") {
      state.palettes = state.palettes.filter((p) => p.id !== id);
      savePalettes();
      resetToRoot();
      render(0);
      toast(`Deleted "${palette.name}"`);
    } else if (action === "addColor") {
      pushAndGo("form:addColor");
      state.currentPaletteId = id;
      render(0);
    } else if (action.startsWith("edit:")) {
      const colorId = action.slice("edit:".length);
      const color = palette.colors.find((c) => c.id === colorId);
      if (!color) return;
      pushAndGo("form:editColor");
      state.currentPaletteId = id;
      state.editingColorId = colorId;
      render(0);
    }
    return;
  }

  if (state.screen === "palette") {
    const palette = getCurrentPalette();
    if (!palette) {
      resetToRoot();
      render(0);
      return;
    }

    if (id === "") {
      if (action === "addColor") {
        pushAndGo("form:addColor");
        render(0);
      } else if (action === "renamePalette") {
        pushAndGo("form:renamePalette");
        render(0);
      } else if (action === "deletePalette") {
        state.palettes = state.palettes.filter((p) => p.id !== palette.id);
        savePalettes();
        resetToRoot();
        render(0);
        toast(`Deleted "${palette.name}"`);
      } else if (action === "copyAll") {
        const text = palette.colors.map((c) => c.hex).join("\n");
        cmd("copy", { text });
        toast(
          `Copied ${palette.colors.length} color${palette.colors.length === 1 ? "" : "s"}`,
        );
      }
      return;
    }

    const color = palette.colors.find((c) => c.id === id);
    if (!color) return;

    if (action === "default") {
      cmd("copy", { text: color.hex });
      toast(`Copied ${color.hex}`);
    } else if (action === "copyRgb") {
      const { r, g, b } = hexToRgb(color.hex);
      cmd("copy", { text: `rgb(${r}, ${g}, ${b})` });
      toast("Copied RGB");
    } else if (action === "copyHsl") {
      const { r, g, b } = hexToRgb(color.hex);
      cmd("copy", { text: rgbToHslString(r, g, b) });
      toast("Copied HSL");
    } else if (action === "edit") {
      state.editingColorId = id;
      pushAndGo("form:editColor");
      render(0);
    } else if (action === "delete") {
      palette.colors = palette.colors.filter((c) => c.id !== id);
      savePalettes();
      render(0);
      toast(`Deleted ${color.hex}`);
    }
    return;
  }
}

function handleSubmit(values) {
  if (state.screen === "form:newPalette") {
    const name = (values.name || "").trim();
    if (!name) {
      renderNewPaletteForm(0, { name: "Name is required" });
      return;
    }
    const palette = { id: genId(), name, colors: [] };
    state.palettes.push(palette);
    savePalettes();
    resetToRoot();
    render(0, palette.id);
    toast(`Created "${name}"`);
    return;
  }

  if (state.screen === "form:addColor") {
    const hex = parseColor(values.hex);
    if (!hex) {
      renderAddColorForm(0, { hex: 'Enter a valid hex (#RRGGBB) or "r,g,b"' });
      return;
    }
    const palette = getCurrentPalette();
    const paletteId = palette.id;
    const color = { id: genId(), hex, name: (values.name || "").trim() };
    palette.colors.push(color);
    savePalettes();
    popToPrevious();
    render(0, state.screen === "palette" ? color.id : paletteId);
    toast(`Added ${hex}`);
    return;
  }

  if (state.screen === "form:editColor") {
    const hex = parseColor(values.hex);
    if (!hex) {
      renderEditColorForm(0, { hex: 'Enter a valid hex (#RRGGBB) or "r,g,b"' });
      return;
    }
    const palette = getCurrentPalette();
    const paletteId = palette ? palette.id : null;
    const color =
      palette && palette.colors.find((c) => c.id === state.editingColorId);
    if (color) {
      color.hex = hex;
      color.name = (values.name || "").trim();
      savePalettes();
    }
    const colorId = state.editingColorId;
    state.editingColorId = null;
    popToPrevious();
    render(0, state.screen === "palette" ? colorId : paletteId);
    toast("Color updated");
    return;
  }

  if (state.screen === "form:renamePalette") {
    const name = (values.name || "").trim();
    if (!name) {
      renderRenamePaletteForm(0, { name: "Name is required" });
      return;
    }
    const palette = getCurrentPalette();
    palette.name = name;
    savePalettes();
    const paletteId = palette.id;
    popToPrevious();
    render(0, paletteId);
    toast("Palette renamed");
    return;
  }
}

function handleBack(rev) {
  popToPrevious();
  render(rev, undefined, state.screen === "root" ? "" : undefined);
  if (state.screen === "root") {
    cmd("setQuery", { text: "" });
  }
}

// ---------------------------------------------------------------------------
// stdin loop
// ---------------------------------------------------------------------------

function handleMessage(msg) {
  switch (msg.type) {
    case "init": {
      state.query = msg.text !== undefined ? msg.text : msg.query || "";
      state.lastRev = msg.rev || 0;
      if (!state.loaded) {
        renderLoading(state.lastRev);
        requestLoad();
      } else {
        render(state.lastRev, undefined, state.query);
      }
      break;
    }
    case "query": {
      state.query = msg.text || "";
      state.lastRev = msg.rev || 0;
      if (!state.loaded) {
        renderLoading(state.lastRev);
      } else if (!state.screen.startsWith("form:")) {
        render(state.lastRev, undefined, state.query);
      }
      break;
    }
    case "action":
      handleAction(msg.id || "", msg.action || "default");
      break;
    case "submit":
      handleSubmit(msg.values || {});
      break;
    case "back":
      handleBack(msg.rev || 0);
      break;
    case "storage":
      if (msg.requestId === "load-palettes" && !state.loaded) {
        try {
          state.palettes = msg.value ? JSON.parse(msg.value) : [];
          if (!Array.isArray(state.palettes)) state.palettes = [];
        } catch (e) {
          state.palettes = [];
        }
        state.loaded = true;
        render(state.lastRev, undefined, state.query);
      }
      break;
    case "select":
    case "change":
    case "loadMore":
    case "tab":
      // Not used by this plugin — previews/actions cover the needed cases.
      break;
    case "close":
      process.exit(0);
      break;
    default:
      break;
  }
}

function main() {
  let buf = "";
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (chunk) => {
    buf += chunk;
    let i;
    while ((i = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, i).trim();
      buf = buf.slice(i + 1);
      if (!line) continue;
      let msg;
      try {
        msg = JSON.parse(line);
      } catch (e) {
        continue;
      }
      try {
        handleMessage(msg);
      } catch (err) {
        log("error handling message", err);
        send({
          type: "render",
          rev: 0,
          view: "detail",
          detail: {
            markdown: `# Error\n\n\`\`\`\n${err && err.stack ? err.stack : err}\n\`\`\``,
          },
        });
      }
    }
  });
  process.stdin.on("end", () => process.exit(0));
}

main();
