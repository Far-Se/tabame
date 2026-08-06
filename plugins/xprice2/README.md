# xPrice Dashboard

xprice2 uses the same xPrice browser lookup flow as xprice, but renders the
result as a native Tabame dashboard instead of a generated image.

The result contains:

- a product overview with name, description, current best price, and metadata;
- a native price-history chart;
- a comparison table with store prices and links;
- actions to open an offer, copy links, refresh the lookup, or open the xPrice page.

## Install

1. Copy this folder to %localappdata%\Tabame\plugins\xprice2\.
2. Make sure Python 3 is on PATH.
3. Reopen the launcher so Tabame rescans plugins.
4. Enable and pair the persistent browser connector if needed.
5. Type xprice2 <link to a product page> and press Enter.
