# Crypto — Tabame plugin

Generates a dark, crypto-app style price card — logo, chart, volume, and a
stats row — for any coin, over whatever period you ask for.

## Usage

Type `crypto` followed by a ticker and, optionally, a period, then press
**Enter**:

```
crypto BTC          -> default period (1M, configurable)
crypto ETH 1d        -> 1 day
crypto SOL 5d        -> 5 days
crypto DOGE 2w        -> 2 weeks
crypto ADA 2m        -> 2 months
crypto BTC 1y        -> 1 year
crypto BTC 5y        -> 5 years
crypto BTC ytd       -> year to date
crypto BTC max       -> full available history
```

Period suffixes: `d` = days, `w` = weeks, `m` = months, `y` = years.

Once a chart is showing, click one of the period chips (1D/5D/1M/6M/1Y/5Y)
to re-render the same coin over a different range without retyping.

If you don't type a ticker, it falls back to `defaultTicker` in
`config.json` (see below), or shows quick instructions if none is set.

Works with any coin CoinGecko tracks — common tickers (BTC, ETH, SOL, DOGE,
SHIB, PEPE, and 40+ more) resolve instantly; anything else is looked up by
symbol automatically.

## Install

1. Copy this whole folder to:
   `%localappdata%\Tabame\plugins\crypto\`
2. Open the Tabame launcher (it rescans plugins on open).
3. Type `crypto btc` and press Enter.

The first launch installs Pillow into the plugin's own `.pluginlibs` folder —
you'll see a short "Installing dependencies…" step once.

## Optional config

Rename `config.json.example` to `config.json` to set a default ticker,
period, and/or quote currency:

```json
{
  "defaultTicker": "btc",
  "defaultPeriod": "1m",
  "currency": "usd"
}
```

`currency` can be any CoinGecko vs_currency code (`usd`, `eur`, `gbp`, `jpy`,
`cad`, `aud`, `chf`, ...).

## How it works

- Price, volume, and market data come from CoinGecko's public API — no key
  needed. Ticker-to-coin resolution uses a small built-in map for common
  coins (skips an extra lookup) and falls back to CoinGecko's search
  endpoint for anything else.
- The card is drawn with Pillow at 2x resolution then downscaled for clean
  anti-aliased lines and text: the coin's real logo (fetched at render
  time) in a circular badge, a shaded area chart colored by the change over
  the selected period, a volume strip colored per up/down bar, and a stats
  row (24h high/low, market cap, 24h volume, all-time high/low). Very
  small-value coins (e.g. SHIB, PEPE) get adaptive decimal precision so
  their price doesn't round to zero.
- A tiny local HTTP server (bound to `127.0.0.1` only, random port, one per
  running plugin instance) serves the PNG so it can be embedded as a normal
  image in the result markdown.
