"use strict";

// Font Sniffer — a Tabame launcher plugin.
//
// The user types a website URL after the `fonts` keyword and presses Enter.
// We load the page in a headless Chromium (Puppeteer) and report the fonts the
// browser *actually rendered*, ranked by how many glyphs each one painted. The
// rendered-font data comes from Chrome DevTools Protocol's
// `CSS.getPlatformFontsForNode`, which is what tells apart "declared in a
// font-family stack" from "the font that really got used" (including fallbacks).
//
// Protocol: newline-delimited JSON over stdin/stdout (see TABAME_PLUGIN_SKILL.md).

// Puppeteer is loaded lazily (inside getBrowser) so the URL prompt still works
// even before dependencies exist — Tabame auto-installs them on first run, but if
// that ever fails we show a friendly hint instead of crashing on a missing module.

const os = require("os");
const path = require("path");
const fs = require("fs");
const crypto = require("crypto");
const { pathToFileURL } = require("url");

// ── stdout: protocol messages only; stderr: debug ───────────────────────────
function send(frame) {
  process.stdout.write(JSON.stringify(frame) + "\n");
}
function log(...a) {
  console.error(...a);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ── State machine ────────────────────────────────────────────────────────────
// screen: 'input'   → the URL prompt (root; Escape exits the plugin)
//         'results' → the ranked font list for the last scanned URL
//         'preview' → a full specimen image of one font; Escape returns to results
//         'error'   → a scan failed; Escape goes back to input
let screen = "input";
let lastText = ""; // latest post-keyword query text
let scannedText = ""; // the URL text that kicked off the current scan
let resultsFilter = ""; // the filter applied to the results list (restored after a preview)
let currentUrl = null; // normalized URL of the current results
let scanning = false; // guards against overlapping scans
let busy = false; // guards against overlapping preview/download work
let theme = {}; // { accent, text, background, dark } from the init handshake

const cache = new Map(); // normalizedUrl -> scan result (so re-scans are instant)
const specimenCache = new Map(); // font family -> generated specimen PNG path
let browserPromise = null; // lazily-launched, reused across scans

// ── URL helpers ──────────────────────────────────────────────────────────────
function normalizeUrl(text) {
  const trimmed = (text || "").trim();
  if (!trimmed || /\s/.test(trimmed)) return null;
  const candidate = /^https?:\/\//i.test(trimmed)
    ? trimmed
    : "https://" + trimmed;
  try {
    const u = new URL(candidate);
    // Require a dotted hostname so bare words ("hello") aren't treated as sites.
    if (!u.hostname || !u.hostname.includes(".")) return null;
    return u.href;
  } catch {
    return null;
  }
}

function hostOf(url) {
  try {
    return new URL(url).host;
  } catch {
    return url;
  }
}

function shortUrl(url) {
  try {
    const u = new URL(url);
    const file = u.pathname.split("/").filter(Boolean).pop() || u.host;
    return `${u.host}/…/${file}`;
  } catch {
    return url.length > 48 ? url.slice(0, 47) + "…" : url;
  }
}

// ── Puppeteer ────────────────────────────────────────────────────────────────
function loadPuppeteer() {
  try {
    return require("puppeteer");
  } catch {
    throw new Error(
      "Puppeteer isn't available. Tabame installs it on first run; if that failed, open a " +
        "terminal in this plugin folder and run `npm install` (it downloads a headless Chromium).",
    );
  }
}

function getBrowser() {
  if (!browserPromise) {
    const puppeteer = loadPuppeteer();
    browserPromise = puppeteer
      .launch({
        headless: true,
        protocolTimeout: 120000,
        args: [
          "--no-sandbox",
          "--disable-setuid-sandbox",
          "--hide-scrollbars",
          "--mute-audio",
        ],
      })
      .catch((error) => {
        browserPromise = null; // allow a retry on the next scan
        throw error;
      });
  }
  return browserPromise;
}

// Walks the (pierced) DOM for text nodes and asks CDP which platform font each
// one rendered with, aggregating glyph counts per family.
async function collectRenderedFonts(page) {
  const client = await page.target().createCDPSession();
  try {
    await client.send("DOM.enable");
    await client.send("CSS.enable");
    const { root } = await client.send("DOM.getDocument", {
      depth: -1,
      pierce: true,
    });

    const textNodeIds = [];
    (function walk(node) {
      if (!node) return;
      if (
        node.nodeType === 3 &&
        node.nodeValue &&
        node.nodeValue.trim().length
      ) {
        textNodeIds.push(node.nodeId);
      }
      if (node.children) for (const child of node.children) walk(child);
      if (node.contentDocument) walk(node.contentDocument); // iframes (pierce: true)
    })(root);

    const agg = new Map(); // family -> { family, glyphCount, isCustom }
    const CAP = 1200; // plenty to capture the dominant fonts without stalling
    for (const nodeId of textNodeIds.slice(0, CAP)) {
      let res;
      try {
        res = await client.send("CSS.getPlatformFontsForNode", { nodeId });
      } catch {
        continue; // node may have been detached; skip it
      }
      for (const f of res.fonts || []) {
        const family = (f.familyName || "").trim();
        if (!family) continue;
        const cur = agg.get(family) || {
          family,
          glyphCount: 0,
          isCustom: false,
        };
        cur.glyphCount += f.glyphCount || 0;
        cur.isCustom = cur.isCustom || !!f.isCustomFont;
        agg.set(family, cur);
      }
    }
    return [...agg.values()].sort((a, b) => b.glyphCount - a.glyphCount);
  } finally {
    await client.detach().catch(() => {});
  }
}

// A loose family key for matching a rendered platform-font name to an @font-face
// family: lowercased, with VF/variable/weight/style/width tokens and punctuation
// removed. "Mona Sans VF" and "Mona Sans" both collapse to "monasans".
function normFamily(name) {
  return String(name)
    .toLowerCase()
    .replace(
      /\b(vf|variable|roman|regular|italic|oblique|thin|extralight|ultralight|light|medium|semibold|demibold|bold|extrabold|ultrabold|black|heavy|book|condensed|expanded|narrow|wide)\b/g,
      " ",
    )
    .replace(/[^a-z0-9]+/g, "");
}

// Parses `@font-face` blocks out of raw CSS text, resolving relative `url()`s
// against the stylesheet's location, and appends them to `out`.
function parseFontFaces(cssText, baseUrl, out) {
  const faceRe = /@font-face\s*\{([^}]*)\}/gi;
  const urlRe =
    /url\(\s*['"]?([^'")]+)['"]?\s*\)(?:\s*format\(\s*['"]?([^'")]+)['"]?\s*\))?/gi;
  let block;
  while ((block = faceRe.exec(cssText))) {
    const body = block[1];
    const famM = body.match(/font-family\s*:\s*([^;]+);?/i);
    const srcM = body.match(/src\s*:\s*([^;]+);?/i);
    if (!famM || !srcM) continue;
    const family = famM[1].replace(/['"]/g, "").trim();
    if (!family) continue;
    const urls = [];
    let u;
    urlRe.lastIndex = 0;
    while ((u = urlRe.exec(srcM[1]))) {
      let href = u[1];
      if (!/^data:/i.test(href)) {
        try {
          href = new URL(href, baseUrl || undefined).href;
        } catch {
          /* keep raw */
        }
      }
      urls.push({ url: href, format: (u[2] || "").trim() });
    }
    if (!urls.length) continue;
    const weightM = body.match(/font-weight\s*:\s*([^;]+);?/i);
    out.push({ family, urls, weight: weightM ? weightM[1].trim() : "normal" });
  }
}

// Reads every stylesheet's text via CDP — including cross-origin sheets that the
// page's own JS can't touch (CORS) — and extracts their @font-face sources. This
// is what lets us attach real font-file URLs for CDN-hosted web fonts.
async function collectFontFaces(page, pageUrl) {
  const client = await page.target().createCDPSession();
  const sheets = []; // { id, sourceURL }
  try {
    client.on("CSS.styleSheetAdded", (e) => {
      sheets.push({
        id: e.header.styleSheetId,
        sourceURL: e.header.sourceURL || "",
      });
    });
    await client.send("DOM.enable");
    await client.send("CSS.enable"); // replays styleSheetAdded for existing sheets
    await sleep(300); // let the events flush

    const faces = [];
    for (const sheet of sheets) {
      let text;
      try {
        ({ text } = await client.send("CSS.getStyleSheetText", {
          styleSheetId: sheet.id,
        }));
      } catch {
        continue;
      }
      if (text && text.includes("@font-face"))
        parseFontFaces(text, sheet.sourceURL || pageUrl, faces);
    }
    return faces;
  } finally {
    await client.detach().catch(() => {});
  }
}

async function scan(url) {
  const browser = await getBrowser();
  const page = await browser.newPage();
  // Record the font files the browser actually fetched (any origin). These are
  // the ground-truth URLs — pages often declare several @font-face sources but
  // only one resolves, so we prefer a URL we saw load over a parsed guess.
  const loadedFontUrls = new Set();
  page.on("response", (res) => {
    try {
      const u = res.url();
      const ct = (res.headers()["content-type"] || "").toLowerCase();
      if (/\.(woff2?|ttf|otf|eot)(?:[?#]|$)/i.test(u) || ct.includes("font"))
        loadedFontUrls.add(u);
    } catch {
      /* ignore */
    }
  });
  try {
    await page.setViewport({ width: 1366, height: 900 });
    await page.setUserAgent(
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36",
    );
    try {
      await page.goto(url, { waitUntil: "load", timeout: 45000 });
    } catch (navError) {
      // Slow/never-idle pages still render enough to sniff — press on unless the
      // navigation produced no document at all.
      log("goto warning:", navError.message);
    }
    // Give web fonts a chance to download and apply.
    await page
      .evaluate(() =>
        document.fonts && document.fonts.ready
          ? document.fonts.ready.then(() => {})
          : null,
      )
      .catch(() => {});
    await sleep(500);

    const title = await page.title().catch(() => "");
    const rendered = await collectRenderedFonts(page);
    const faces = await collectFontFaces(page, page.url() || url).catch(
      () => [],
    );

    // Attach a downloadable source to each rendered font. Rendered names come
    // from the font's internal name table (e.g. "Mona Sans VF"), while @font-face
    // declares a shorter family ("Mona Sans"), so we match exactly first, then on
    // a normalized key that strips VF/weight/style tokens. Among a family's
    // candidate sources we prefer one the browser actually loaded, then woff2.
    const byExact = new Map(); // lower family -> rec[]
    const byNorm = new Map(); // normalized family -> rec[]
    const push = (map, key, rec) => {
      if (!key) return;
      const list = map.get(key);
      if (list) list.push(rec);
      else map.set(key, [rec]);
    };
    for (const face of faces) {
      for (const u of face.urls) {
        if (!/^https?:\/\//i.test(u.url) && !/^data:/i.test(u.url)) continue;
        const rec = { url: u.url, format: u.format, weight: face.weight };
        push(byExact, face.family.toLowerCase(), rec);
        push(byNorm, normFamily(face.family), rec);
      }
    }
    const isWoff2 = (r) =>
      /woff2/i.test(r.format) || /\.woff2(?:[?#]|$)/i.test(r.url);
    const chooseUrl = (cands) => {
      if (!cands.length) return null;
      return (
        cands.find((r) => loadedFontUrls.has(r.url) && isWoff2(r)) ||
        cands.find((r) => loadedFontUrls.has(r.url)) ||
        cands.find(isWoff2) ||
        cands[0]
      );
    };
    let total = 0;
    for (const font of rendered) {
      total += font.glyphCount;
      const cands = [
        ...(byExact.get(font.family.toLowerCase()) || []),
        ...(byNorm.get(normFamily(font.family)) || []),
      ];
      const pick = chooseUrl(cands);
      if (pick) {
        font.urls = [{ url: pick.url, format: pick.format }];
        font.weight = pick.weight;
      }
    }
    // Every font file the browser fetched (any origin, any referencing method —
    // CSS @font-face or a <link rel=preload as=font>). This is the ground-truth
    // download source, independent of whether we matched a file to a family.
    const files = [...loadedFontUrls].filter((u) => /^https?:\/\//i.test(u));
    return { url, title, rendered, totalGlyphs: total || 1, files };
  } finally {
    await page.close().catch(() => {});
  }
}

// ── Rendering ────────────────────────────────────────────────────────────────
function renderInput(rev, text) {
  const url = normalizeUrl(text);
  let items;
  if (!(text || "").trim()) {
    items = [
      {
        id: "hint",
        title: "Type a website URL",
        subtitle: "e.g. `stripe.com` — then press Enter to scan its fonts",
        icon: "globe",
      },
    ];
  } else if (!url) {
    items = [
      {
        id: "hint",
        title: "Enter a valid website URL",
        subtitle: `"${text.trim()}" doesn't look like a URL`,
        icon: "warning",
      },
    ];
  } else {
    items = [
      {
        id: "scan",
        title: `Scan ${hostOf(url)}`,
        subtitle:
          "Loads the page in headless Chrome and lists every font it renders",
        icon: "search",
        actions: [{ id: "default", title: "Scan fonts", icon: "search" }],
      },
    ];
  }
  send({
    type: "render",
    rev,
    view: "list",
    placeholder: "Website URL…",
    items,
  });
}

function fontPreview(font, pct) {
  const isWeb = font.isCustom;
  const md = [
    `## ${font.family}`,
    "",
    isWeb
      ? "_Custom web font, loaded via `@font-face`._"
      : "_System / locally-installed font (a fallback or an OS font)._",
  ].join("\n");
  const metadata = [
    {
      label: "Type",
      text: isWeb ? "Web font" : "System font",
      color: isWeb ? "#63A0EA" : "#8A8F98",
      icon: isWeb ? "globe" : "app",
    },
    {
      label: "Usage",
      text: `${pct}%  ·  ${font.glyphCount.toLocaleString()} glyphs`,
    },
    { label: "Preview", text: `Press Ctrl+K and Select Preview.` },
  ];
  if (font.weight)
    metadata.push({ label: "Weight", text: String(font.weight) });
  if (font.urls && font.urls.length) {
    metadata.push({ separator: true });
    for (const u of font.urls) {
      metadata.push({
        label: u.format || "source",
        text: shortUrl(u.url),
        url: u.url,
        icon: "link",
      });
    }
  }
  return { markdown: md, metadata };
}

// ── Download & preview ───────────────────────────────────────────────────────
function escapeHtml(s) {
  return String(s).replace(
    /[&<>"]/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c],
  );
}
function safeFile(name) {
  return (
    String(name)
      .replace(/[^a-z0-9._-]+/gi, "_")
      .replace(/^_+|_+$/g, "") || "font"
  );
}
function uniquePath(p) {
  if (!fs.existsSync(p)) return p;
  const ext = path.extname(p);
  const stem = ext ? p.slice(0, -ext.length) : p;
  let i = 1;
  let candidate;
  do {
    candidate = `${stem} (${i})${ext}`;
    i++;
  } while (fs.existsSync(candidate));
  return candidate;
}
async function fetchBytes(url) {
  const res = await fetch(url, { redirect: "follow" });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return Buffer.from(await res.arrayBuffer());
}
function mimeForFormat(format, url) {
  const key = (
    format ||
    (url.match(/\.([a-z0-9]+)(?:[?#]|$)/i) || [])[1] ||
    ""
  ).toLowerCase();
  if (key.includes("woff2")) return "font/woff2";
  if (key.includes("woff")) return "font/woff";
  if (key === "ttf" || key === "truetype") return "font/ttf";
  if (key === "otf" || key === "opentype") return "font/otf";
  return "application/octet-stream";
}
function extFromUrl(url) {
  return (url.match(/\.(woff2?|ttf|otf|eot)(?:[?#]|$)/i) || [])[1] || "";
}
// A sensible download filename for a font URL: the URL's own basename when it has
// an extension, otherwise the host (or a given fallback) plus a guessed extension.
function fileNameForUrl(url, fallbackBase, format) {
  let base = "";
  try {
    base = decodeURIComponent(
      new URL(url).pathname.split("/").filter(Boolean).pop() || "",
    );
  } catch {
    /* fall through */
  }
  if (base && /\.[a-z0-9]{2,5}$/i.test(base)) return safeFile(base);
  const ext = format
    ? "." + format.replace(/[^a-z0-9]/gi, "")
    : extFromUrl(url)
      ? "." + extFromUrl(url).toLowerCase()
      : ".font";
  return safeFile(fallbackBase || hostOf(url) || "font") + ext;
}

// Fetches a URL and saves it to the user's Downloads folder, toasting progress
// and revealing the folder. `label` is what the toast names (a family or file).
async function saveUrlToDownloads(url, filename, label) {
  send({
    type: "command",
    command: "toast",
    text: `Downloading ${label || filename}…`,
  });
  try {
    const bytes = await fetchBytes(url);
    const downloads = path.join(os.homedir(), "Downloads");
    fs.mkdirSync(downloads, { recursive: true });
    const dest = uniquePath(path.join(downloads, safeFile(filename)));
    fs.writeFileSync(dest, bytes);
    send({
      type: "command",
      command: "toast",
      text: `Saved ${path.basename(dest)} to Downloads`,
    });
    send({ type: "command", command: "open", url: downloads }); // reveal it
  } catch (error) {
    log("download failed:", error && error.stack ? error.stack : error);
    send({
      type: "command",
      command: "toast",
      text: `Download failed: ${String((error && error.message) || error)}`,
    });
  }
}

// Downloads a rendered font's attributed file. System fonts have no file.
async function doDownload(font) {
  const first = font.urls && font.urls.length ? font.urls[0] : null;
  if (!first) {
    send({
      type: "command",
      command: "toast",
      text: `${font.family} is a system font — nothing to download`,
    });
    return;
  }
  await saveUrlToDownloads(
    first.url,
    fileNameForUrl(first.url, font.family, first.format),
    font.family,
  );
}

// Renders a specimen sheet and returns a PNG path. When `srcUrl` is given we
// inline the actual font bytes as a data: URL so the specimen is guaranteed to
// use the real face (no CORS/network surprises); otherwise it renders from the
// OS (system fonts). `kindLabel` is the small caption after the name.
async function renderSpecimenFor(family, srcUrl, format, kindLabel) {
  const cacheKey = `${family}|${srcUrl || ""}`;
  const cached = specimenCache.get(cacheKey);
  if (cached && fs.existsSync(cached)) return cached;

  const safeFamily = String(family).replace(/["\\]/g, "");
  let face = "";
  let stack = `'${safeFamily}', sans-serif`;
  if (srcUrl) {
    try {
      const bytes = await fetchBytes(srcUrl);
      const mime = mimeForFormat(format, srcUrl);
      const fmt = format ? ` format('${format}')` : "";
      face = `@font-face{font-family:'Specimen';src:url('data:${mime};base64,${bytes.toString("base64")}')${fmt};}`;
      stack = `'Specimen', '${safeFamily}', sans-serif`;
    } catch (error) {
      log(
        "specimen font fetch failed, falling back to family name:",
        error && error.message,
      );
    }
  }

  const bg = theme.background || "#1B1D23";
  const fg = theme.text || "#E8E8E8";
  const accent = theme.accent || "#63A0EA";
  const html = `<!doctype html><html><head><meta charset="utf-8"><style>
    ${face}
    html,body{margin:0}
    #sheet{background:${bg};color:${fg};width:860px;box-sizing:border-box;padding:40px 44px;font-family:${stack}}
    .label{color:${accent};font-size:13px;letter-spacing:.16em;text-transform:uppercase;margin-bottom:22px}
    .big{font-size:52px;line-height:1.12;margin:0 0 20px}
    .mid{font-size:30px;line-height:1.2;margin:0 0 12px}
    .row{font-size:22px;margin:0 0 12px}
    .weights{font-size:26px;margin:8px 0 0}
    .weights span{margin-right:18px}
    .w300{font-weight:300}.w400{font-weight:400}.w600{font-weight:600}.w700{font-weight:700}
    .small{font-size:15px;opacity:.65;margin-top:24px}
  </style></head><body><div id="sheet">
    <div class="label">${escapeHtml(family)}${kindLabel ? " · " + escapeHtml(kindLabel) : ""}</div>
    <div class="big">The quick brown fox jumps over the lazy dog</div>
    <div class="mid">ABCDEFGHIJKLMNOPQRSTUVWXYZ</div>
    <div class="mid">abcdefghijklmnopqrstuvwxyz</div>
    <div class="row">0123456789 &nbsp; &amp; ! ? @ # $ % ^ * ( ) [ ] { } / \\ &lt; &gt;</div>
    <div class="weights"><span class="w300">Light</span><span class="w400">Regular</span><span class="w600">Semibold</span><span class="w700">Bold</span></div>
    <div class="small">Pack my box with five dozen liquor jugs — Sphinx of black quartz, judge my vow.</div>
  </div></body></html>`;

  const browser = await getBrowser();
  const page = await browser.newPage();
  try {
    await page.setViewport({ width: 900, height: 700, deviceScaleFactor: 2 });
    await page.setContent(html, { waitUntil: "load" });
    await page
      .evaluate(() =>
        document.fonts && document.fonts.ready
          ? document.fonts.ready.then(() => {})
          : null,
      )
      .catch(() => {});
    await sleep(150);
    const el = await page.$("#sheet");
    const dir = path.join(os.tmpdir(), "tabame-font-sniffer");
    fs.mkdirSync(dir, { recursive: true });
    const hash = crypto
      .createHash("md5")
      .update(cacheKey)
      .digest("hex")
      .slice(0, 8);
    const file = path.join(dir, `${safeFile(family)}-${hash}.png`);
    await el.screenshot({ path: file });
    specimenCache.set(cacheKey, file);
    return file;
  } finally {
    await page.close().catch(() => {});
  }
}

function specimenLoadingFrame(name) {
  send({
    type: "render",
    rev: 0,
    view: "list",
    loading: true,
    items: [],
    loadingText: `Rendering ${name} specimen…`,
  });
}
function specimenErrorFrame(error) {
  send({
    type: "render",
    rev: 0,
    view: "detail",
    canGoBack: true,
    detail: {
      markdown: `# Couldn't render specimen\n\n\`\`\`\n${String((error && error.message) || error)}\n\`\`\``,
    },
  });
}

// Ctrl+K "Preview font": render the specimen, then show it full-width in a
// detail view. Escape returns to the results list (see handleBack).
async function doPreview(font) {
  if (busy) return;
  busy = true;
  screen = "preview";
  specimenLoadingFrame(font.family);
  try {
    const first =
      font.isCustom && font.urls && font.urls.length ? font.urls[0] : null;
    const kind = font.isCustom ? "web font" : "system font";
    const file = await renderSpecimenFor(
      font.family,
      first && first.url,
      first && first.format,
      kind,
    );
    const data = cache.get(currentUrl);
    const pct = data
      ? Math.round((font.glyphCount / data.totalGlyphs) * 100)
      : 0;
    send({
      type: "render",
      rev: 0,
      view: "detail",
      canGoBack: true,
      placeholder: "Esc to go back to the font list",
      detail: {
        markdown: `## ${font.family}\n\n![specimen](${pathToFileURL(file).href})`,
        wide: true,
        metadata: fontPreview(font, pct).metadata,
      },
    });
  } catch (error) {
    log("preview failed:", error && error.stack ? error.stack : error);
    specimenErrorFrame(error);
  } finally {
    busy = false;
  }
}

// Ctrl+K "Preview font" on a loaded font file — renders it straight from its URL.
async function doPreviewFile(url) {
  if (busy) return;
  busy = true;
  screen = "preview";
  const name = fileNameForUrl(url);
  specimenLoadingFrame(name);
  try {
    const format = extFromUrl(url);
    const file = await renderSpecimenFor(name, url, format, "font file");
    send({
      type: "render",
      rev: 0,
      view: "detail",
      canGoBack: true,
      placeholder: "Esc to go back to the font list",
      detail: {
        markdown: `## ${name}\n\n![specimen](${pathToFileURL(file).href})`,
        wide: true,
        metadata: [
          {
            label: "Type",
            text: (format ? format.toUpperCase() + " " : "") + "font file",
            color: "#63A0EA",
            icon: "download",
          },
          { label: "URL", text: shortUrl(url), url, icon: "link" },
        ],
      },
    });
  } catch (error) {
    log("file preview failed:", error && error.stack ? error.stack : error);
    specimenErrorFrame(error);
  } finally {
    busy = false;
  }
}

function fontItem(font, total) {
  const pct = Math.round((font.glyphCount / total) * 100);
  const isWeb = font.isCustom;
  const src = font.urls && font.urls.length ? font.urls[0].url : null;

  const accessories = [
    isWeb
      ? { text: "web font", icon: "globe", color: "#63A0EA" }
      : { text: "system", color: "#8A8F98" },
  ];
  if (font.urls && font.urls[0] && font.urls[0].format)
    accessories.push({ text: font.urls[0].format });

  const actions = [
    { id: "preview", title: "Preview font", icon: "image" },
    { id: "copy", title: "Copy font name", icon: "copy" },
    { id: "copy-css", title: "Copy CSS font-family", icon: "code" },
  ];
  if (src) {
    actions.push({
      id: "download",
      title: "Download font file",
      icon: "download",
    });
    actions.push({ id: "open-src", title: "Open font file", icon: "open" });
    actions.push({ id: "copy-src", title: "Copy font file URL", icon: "link" });
  }

  return {
    id: "font:" + font.family,
    title: font.family,
    subtitle: `${pct}% · ${font.glyphCount.toLocaleString()} glyphs`,
    icon: "label",
    progress: Math.min(1, font.glyphCount / total),
    accessories,
    actions,
    preview: fontPreview(font, pct),
  };
}

// A downloadable font-file row (network resource), used for files the page
// loaded that aren't already attributed to a rendered font above.
function fileItem(url) {
  const name = fileNameForUrl(url);
  const ext = extFromUrl(url) || (name.match(/\.([a-z0-9]+)$/i) || [])[1] || "";
  return {
    id: "file:" + url,
    title: name,
    subtitle: hostOf(url),
    icon: "download",
    section: "Font files",
    accessories: ext ? [{ text: ext.toLowerCase() }] : [],
    actions: [
      { id: "download", title: "Download to Downloads", icon: "download" },
      { id: "preview", title: "Preview font", icon: "image" },
      { id: "open", title: "Open in browser", icon: "open" },
      { id: "copy", title: "Copy file URL", icon: "link" },
    ],
    preview: {
      markdown: `## ${name}`,
      metadata: [
        {
          label: "Type",
          text: ext ? ext.toUpperCase() + " font file" : "Font file",
          color: "#63A0EA",
          icon: "download",
        },
        { label: "Host", text: hostOf(url) },
        { label: "URL", text: shortUrl(url), url, icon: "link" },
      ],
    },
  };
}

function renderResults(rev, filter) {
  const data = cache.get(currentUrl);
  if (!data) return renderInput(rev, scannedText);
  const q = (filter || "").trim().toLowerCase();

  // Font files already shown as a rendered font's source aren't repeated below.
  const attributed = new Set(
    data.rendered.filter((f) => f.urls && f.urls[0]).map((f) => f.urls[0].url),
  );
  const extraFiles = (data.files || []).filter((u) => !attributed.has(u));
  const hasFiles = extraFiles.length > 0;

  const fonts = q
    ? data.rendered.filter((f) => f.family.toLowerCase().includes(q))
    : data.rendered;
  const files = q
    ? extraFiles.filter((u) => u.toLowerCase().includes(q))
    : extraFiles;

  const items = [
    ...fonts.map((f) => {
      const item = fontItem(f, data.totalGlyphs);
      if (hasFiles) item.section = "Rendered fonts";
      return item;
    }),
    ...files.map((u) => fileItem(u)),
  ];

  send({
    type: "render",
    rev,
    view: "list",
    preview: { enabled: true },
    canGoBack: true,
    placeholder: `Filter ${data.rendered.length} fonts on ${hostOf(currentUrl)}…`,
    items,
    empty: q
      ? {
          icon: "search",
          title: "No matching fonts",
          hint: "Clear the filter to see them all",
        }
      : {
          icon: "warning",
          title: "No fonts detected",
          hint: "The page may have blocked the headless browser",
        },
  });
}

async function doScan() {
  if (scanning) return;
  const url = normalizeUrl(lastText);
  if (!url) return;
  scanning = true;
  scannedText = lastText;
  currentUrl = url;
  screen = "results";
  send({
    type: "render",
    rev: 0,
    view: "list",
    loading: true,
    items: [],
    loadingText: `Loading ${hostOf(url)} in headless Chrome…`,
  });
  try {
    if (!cache.has(url)) cache.set(url, await scan(url));
    // Clear the URL out of the box so typing now filters the font list.
    send({ type: "command", command: "setQuery", text: "" });
    renderResults(0, "");
  } catch (error) {
    log("scan failed:", error && error.stack ? error.stack : error);
    screen = "error";
    const message = String((error && error.message) || error);
    send({
      type: "render",
      rev: 0,
      view: "detail",
      canGoBack: true,
      detail: {
        markdown: `# Couldn't scan ${hostOf(url)}\n\n\`\`\`\n${message}\n\`\`\`\n\nCheck the URL and your connection, then press **Esc** to try another.\n\nIf this is the first run, make sure you ran \`npm install\` in the plugin folder so Puppeteer and its Chromium are present.`,
      },
    });
  } finally {
    scanning = false;
  }
}

// ── Action handling ──────────────────────────────────────────────────────────
function handleAction(id, action) {
  if (screen === "input") {
    if (id === "scan") void doScan();
    return;
  }
  if (screen !== "results") return;

  // A loaded font file (network resource) — download / preview / open / copy.
  if (id.startsWith("file:")) {
    const url = id.slice("file:".length);
    switch (action) {
      case "preview":
        void doPreviewFile(url);
        break;
      case "open":
        send({ type: "command", command: "open", url });
        break;
      case "copy":
        send({ type: "command", command: "copy", text: url });
        break;
      case "default":
      case "download":
      default:
        void saveUrlToDownloads(url, fileNameForUrl(url), fileNameForUrl(url));
        break;
    }
    return;
  }

  if (!id.startsWith("font:")) return;
  const family = id.slice("font:".length);
  const data = cache.get(currentUrl);
  const font = data && data.rendered.find((f) => f.family === family);
  const src = font && font.urls && font.urls.length ? font.urls[0].url : null;

  if (!font) return;

  switch (action) {
    case "preview":
      void doPreview(font);
      break;
    case "download":
      void doDownload(font);
      break;
    case "copy-css":
      send({
        type: "command",
        command: "copy",
        text: `font-family: "${family}";`,
      });
      break;
    case "open-src":
      if (src) send({ type: "command", command: "open", url: src });
      break;
    case "copy-src":
      if (src) send({ type: "command", command: "copy", text: src });
      break;
    case "default":
    case "copy":
    default:
      send({ type: "command", command: "copy", text: family });
      break;
  }
}

function handleBack() {
  if (screen === "preview") {
    // Return to the font list with the filter the user had before previewing.
    screen = "results";
    send({ type: "command", command: "setQuery", text: resultsFilter });
    renderResults(0, resultsFilter);
    return;
  }
  // From results or an error screen, go back to the URL prompt.
  screen = "input";
  send({ type: "command", command: "setQuery", text: scannedText });
  renderInput(0, scannedText);
}

// ── Event loop ───────────────────────────────────────────────────────────────
function handleMessage(msg) {
  switch (msg.type) {
    case "init":
    case "query": {
      if (msg.theme) theme = msg.theme;
      const text = msg.text != null ? msg.text : msg.query || "";
      lastText = text;
      const rev = msg.rev || 0;
      if (screen === "results") {
        resultsFilter = text;
        renderResults(rev, text);
      } else if (screen === "preview" || screen === "error") {
        return; // sub-screens own the view until Back/Esc
      } else {
        renderInput(rev, text);
      }
      break;
    }
    case "action":
      handleAction(msg.id || "", msg.action || "default");
      break;
    case "back":
      handleBack();
      break;
    case "close":
      void shutdown();
      break;
    // 'select' / 'tab' / 'submit': not used by this plugin.
  }
}

async function shutdown() {
  try {
    if (browserPromise) {
      const browser = await browserPromise.catch(() => null);
      if (browser) await browser.close().catch(() => {});
    }
  } finally {
    process.exit(0);
  }
}

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
    } catch {
      continue;
    }
    try {
      handleMessage(msg);
    } catch (error) {
      log("handler error:", error && error.stack ? error.stack : error);
    }
  }
});
process.stdin.on("end", () => void shutdown());
