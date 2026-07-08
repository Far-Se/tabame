# Can I Use plugin for the Tabame launcher

Search [caniuse.com](https://caniuse.com) for web-platform feature browser
compatibility straight from the launcher — no API key, no config.

## Install

1. Copy this folder to `%localappdata%\Tabame\plugins\caniuse\`.
2. Make sure `node` (Node 18+) is on your PATH. To use Bun instead, set
   `"runtime": "bun"` in `plugin.json`.
3. Open the launcher and type the keyword **`ciu`**.

The first search downloads the full caniuse dataset
(`fulldata-json/data-2.0.json`) and caches it to `caniuse-cache.json` next to
`main.js`. The cache is refreshed automatically once a week; if the network is
down, a stale cache is used rather than failing.

## Usage

Type the keyword **`ciu`** followed by a feature name:

- `ciu grid` — CSS Grid Layout
- `ciu :has` — the `:has()` selector
- `ciu webp` — the WebP image format
- `ciu container queries`
- `ciu dialog`

Results are ranked by relevance and then by global support. Each row shows:

- the feature title,
- a trailing chip with the **global support %** (e.g. `94%`, or `88%+6` when
  there is additional partial support),
- the current-stable status for the main desktop browsers as the subtitle,
- a preview pane with the full desktop **and** mobile breakdown, spec status,
  usage numbers and any caveat notes.

### Symbols

| Symbol | Meaning |
|---|---|
| ✅ | Full support |
| 🟡 | Supported, but needs a vendor prefix or is behind a flag |
| 🟠 | Partial support |
| ❌ | Not supported (or polyfill only) |
| ❔ | Unknown |

### Keys

- **Enter** — open the highlighted feature on caniuse.com.
- **Ctrl+K** — per-item action menu (open, copy URL, copy feature name).
- **Esc** — leave the plugin.

## Notes

- Data comes from the public caniuse dataset mirrored on jsdelivr, with raw
  GitHub as a fallback. No npm dependencies — plain JS using the runtime's
  global `fetch`.
- Clipboard and "open in browser" are handled by the plugin itself (via `clip`
  and `start`), so they work without any extra launcher support.
- "Current stable" support is read from each browser's `era: 0` release in the
  dataset, so figures track whatever the latest mirror snapshot reports.
