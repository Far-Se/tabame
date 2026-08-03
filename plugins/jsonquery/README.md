# JSON Query — Tabame plugin

## Install
1. Copy the whole `jsonquery` folder into:
   `%localappdata%\Tabame\plugins\jsonquery\`
   (so `plugin.json` and `main.py` sit directly inside that folder)
2. Open the Tabame launcher and type `json`.

## Use
- **Load data**: "Open JSON File…" (file picker), "Load JSON from Clipboard",
  or "Paste JSON Manually".
- **Query** (typed after `json `, once something is loaded):
  - Filter: `"name":"George" and "money":>300 and "Location":!="Madrid"`
    (also works without quotes/colons: `name=George and money>300`)
  - Operators: `=`, `!=`, `>`, `<`, `>=`, `<=` — combine with `and` / `or`.
  - Project a single key from every entry: just type the key, e.g. `id`
  - Filter **and** project together: `money>300 | id`
  - Project with no filter: `| name`
- **View** an entry: Enter (or Ctrl+K → "View Full JSON").
- **Copy**: Ctrl+K on an item copies its JSON/value; frame-level Ctrl+K has
  "Copy All Results (JSON)" and (in projection mode) "Copy Values".
- **Export**: Ctrl+K → "Export Results…" opens a form to pick a folder,
  file name, and format (JSON array, or one value per line as text) — works
  for the whole result set or just the projected key.
- **Export Only**: Ctrl+K -> "Export Only" opens a key-selection page. Select
  top-level keys and nested paths such as `values.name`, then choose a folder
  and file name. The JSON shape is preserved and unselected keys are removed.
- **Preview**: Browsing results shows a split preview with the complete entry
  JSON and a **Copy JSON** button. This is available while browsing, not while
  selecting export keys.
