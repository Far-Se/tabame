# Font Sniffer

A Tabame launcher plugin that loads a website in **headless Chrome (Puppeteer)**
and lists every font the page **actually renders**, ranked by how many glyphs
each one painted — so you see the real fonts, including which fallback got used,
not just the declared `font-family` stacks.

Type the keyword **`fonts`**, enter a URL, press **Enter**.

## What you get

- **Ranked font list** — each row is a font family with its usage (`%` of glyphs
  + a progress bar) and a `web font` / `system` badge.
- **Preview font** (Ctrl+K) — renders a full specimen sheet **in the actual font**
  and shows it inside the launcher. Web fonts are rendered from their real file
  (inlined, so it's exactly what the site uses); system fonts render from your OS.
  **Esc** returns to the list.
- **Download font** (Ctrl+K, web fonts) — saves the font file to your **Downloads**
  folder and reveals it. It downloads the exact file the browser loaded, so
  content-hashed CDN URLs resolve correctly.
- **Font files section** — every font file the page actually fetched (from CSS
  `@font-face` or a `<link rel="preload" as="font">`, any origin) is listed under
  a **Font files** group, each with Download / Preview / Open / Copy URL. This
  catches web fonts whose internal name doesn't match their `@font-face` family,
  so nothing loaded is left un-downloadable.
- **Web-font details** — the preview pane shows the source URL(s) and format
  (woff2, …); Ctrl+K can also open or copy the font file URL.
- **Copy actions** — Enter copies the font name; Ctrl+K adds "Copy CSS
  `font-family`".
- **Filter** — after a scan, keep typing to filter the results; **Esc** goes back
  to the URL prompt.

The accurate rendered-font data comes from Chrome DevTools Protocol's
`CSS.getPlatformFontsForNode`, aggregated across the page's text nodes. Source
URLs are recovered by reading every stylesheet's text over CDP (cross-origin
included) and preferring the font file the page actually fetched — then matched
to rendered names with a normalized key (so `Mona Sans VF` finds `@font-face`
family `Mona Sans`).

## Install

1. Copy this folder to `%localappdata%\Tabame\plugins\font-sniffer\`.
2. Make sure **Node.js 18+** is on your PATH.
3. Open the launcher and type **`fonts stripe.com`**, then press Enter.

On the **first** run Tabame sees the `package.json`, shows "Installing
dependencies…", and runs `npm install` in the plugin folder for you — which also
downloads the Chromium that Puppeteer drives (a one-time ~150 MB download, so the
first scan takes a bit). After that it's instant.

> Prefer to do it yourself? Run `npm install` in the plugin folder before opening
> the launcher — Node resolves `require('puppeteer')` from the local
> `node_modules` either way.

## Notes

- The first scan launches a headless browser (a second or two); it's reused for
  subsequent scans, and results are cached per URL for the session.
- Some sites block or serve different content to headless browsers. If a scan
  shows no fonts, that's usually why.
- To use an existing Chrome instead of Puppeteer's bundled Chromium, install
  `puppeteer-core` and set `executablePath` in `launch()` — left out here to keep
  install a single `npm install`.
