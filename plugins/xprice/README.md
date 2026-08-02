# xPrice Lookup — Tabame plugin

Paste a product link, get an xPrice price card: product photo, full price
history graph, and the cheapest stores — with the top 3 links right in the
metadata panel.

## How it works

1. You type `xprice <product url>` in the launcher.
2. The plugin asks Tabame (via `browserBridge`) to open `xprice.ro` in a
   temporary, inactive tab — it never opens its own WebSocket.
3. It pastes your link into `input[name="product_link"]` and submits the
   form, then waits for the redirect to the product's `/istoric-pret/...`
   page.
4. It reads the page's `Product` JSON-LD (name, image, all store offers)
   and the `.hist-graph .bar` elements (day-by-day price history), all
   validated in Python before use.
5. It closes the temporary tab (always, even on error) and renders a PNG
   price card with Pillow: photo, price-history line chart, and a ranked
   list of stores (cheapest highlighted).
6. The result screen shows the card plus the 3 cheapest offers as
   clickable metadata rows, with actions to open the cheapest offer or
   copy all three links.

## Install

1. Copy this folder to `%localappdata%\Tabame\plugins\xprice\`.
2. Make sure Python 3 is on `PATH`.
3. Reopen the launcher (Tabame rescans plugins on every open) — first run
   installs `Pillow` into `.pluginlibs` automatically.
4. Open **Launcher Plugins** and enable **Persistent browser connector**,
   then pair `tabame-extension` if it isn't connected yet (the plugin's
   error screen has a **Connection & pairing** shortcut for this).
5. Type `xprice <link to a product page>` and press Enter on the
   "Look up price on xPrice" item.

## Notes

- Only use this with sites/accounts you trust — the browser bridge runs
  plugin-owned JavaScript in a real, connected browser tab.
- Generated cards are cached under `cache/` inside the plugin folder,
  named by timestamp; safe to delete anytime.
- If xPrice doesn't recognize a link, or the redirect never happens, the
  error screen explains why and offers **Try again**.
