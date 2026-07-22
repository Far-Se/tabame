# Stocks — Tabame plugin

Generates a dark, trading-app style price card — chart, volume, and a stats
row — for any ticker, over whatever period you ask for.

## Usage

Type `stock` followed by a ticker and, optionally, a period, then press
**Enter**:

```
stock AAPL          -> default period (1M, configurable)
stock AAPL 1d        -> 1 day (intraday, 5-min bars)
stock AAPL 5d        -> 5 days
stock AAPL 2w        -> 2 weeks
stock AAPL 2m        -> 2 months
stock AAPL 1y        -> 1 year
stock AAPL 5y        -> 5 years
stock AAPL ytd       -> year to date
stock AAPL max       -> full available history
stock watch 1m       -> one image containing every watched stock
```

Period suffixes: `d` = days, `w` = weeks, `m` = months, `y` = years.

Once a chart is showing, click one of the period chips (1D/5D/1M/6M/1Y/5Y)
to re-render the same ticker over a different range without retyping.

Use the **Add to watchlist** button at the bottom of a stock result to save that
ticker. Then use `stock watch`, optionally followed by any supported period, to
render one stacked image for every watched stock. The list is saved in Tabame's
plugin storage and persists between launches.

If you don't type a ticker, it falls back to `defaultTicker` in
`config.json` (see below), or shows quick instructions if none is set.

## Install

1. Copy this whole folder to:
   `%localappdata%\Tabame\plugins\stock\`
2. Open the Tabame launcher (it rescans plugins on open).
3. Type `stock aapl` and press Enter.

The first launch installs Pillow into the plugin's own `.pluginlibs` folder —
you'll see a short "Installing dependencies…" step once.

## Optional config

Rename `config.json.example` to `config.json` to set a default ticker and/or
default period:

```json
{
  "defaultTicker": "AAPL",
  "defaultPeriod": "1m"
}
```

## How it works

- Price and volume data come from Yahoo Finance's public chart endpoint —
  no API key needed. Chart resolution adapts to the period (5-min bars for
  1 day, up to weekly bars for multi-year ranges).
- The card is drawn with Pillow at 2x resolution then downscaled for clean
  anti-aliased lines and text: an area chart shaded green/red based on the
  change over the selected period, a volume strip colored per up/down bar,
  and a stats row (day high/low, previous close, volume, 52-week range).
- A tiny local HTTP server (bound to `127.0.0.1` only, random port, one per
  running plugin instance) serves the PNG so it can be embedded as a normal
  image in the result markdown — the launcher's protocol only allows
  `http(s)`/`file://` images, and `file://` isn't documented for markdown
  images, only icons.
