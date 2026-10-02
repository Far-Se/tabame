# FX Atlas

A standalone Tabame currency converter with a data-driven, 1440 × 740 PNG:
conversion receipt, dated reference rate, inverse rate, history chart, period
change, low and high. Dark and light palettes follow the launcher's initial theme.

## Install

Copy this folder to `%LOCALAPPDATA%\Tabame\plugins\fx-atlas\` and reopen the
launcher. Python must be available on PATH; Tabame installs the declared Pillow
dependency automatically. The required files are `plugin.json`, `main.py`, and
`render.py`. No API key is needed. Existing currency plugins are independent.

## Use

| Query | Result |
| --- | --- |
| `fxa` | 100 EUR to USD, 30-day history |
| `fxa 250 USD to RON` | Convert 250 US dollars to Romanian lei |
| `fxa EUR/GBP` | Convert one euro to pounds |
| `fxa 1,250.50 EUR JPY 90d` | Convert with a 90-day history |

The amount accepts a decimal point, optional grouped thousands, and up to eight
decimal places. Zero and negative amounts are supported. The absolute maximum
is one trillion. Output respects zero-, three-, and four-decimal currencies.
Currencies use three-letter codes supported by the provider; cryptocurrencies
are not supported. Swap preserves the input amount and reverses the currencies.

The range selector offers 7, 30, 90, and 365 days. Enter or **Copy value** copies
the converted number without separators. **Swap** is also available as
Ctrl+Shift+S. Ctrl+K offers **Copy chart image**, **Open chart image**, a dated
text summary, theme switching, and **Refresh rates** (Ctrl+R). Clicking the image
opens Tabame's image viewer. Image clipboard support follows the host platform.

## Data and accuracy

Rates and history come from [Frankfurter API v2](https://frankfurter.dev/), a
daily reference-rate service. These are dated reference rates, not intraday
quotes or executable bank prices. Transfer fees and spreads are excluded.
Rates are blended across the provider's sources. The source's date is always
visible, including weekends and publication delays. Periods end on that date.

The chart spaces observations by calendar date and joins actual observations
with straight segments. It does not generate synthetic market data. Period
change compares the first and last available observation; it describes the
currency pair, including when the amount is zero or negative. If history fails,
the conversion still works and the chart reports that history is unavailable.
Identity conversions use a rate of one and have no market history.

Rate responses are cached for one hour under `.cache`; Refresh bypasses the
cache. A network failure may use older cached data with a visible **Cached rate**
label and date. A history failure retries after one minute. Requests
have a 12-second timeout; typing is debounced and obsolete results are discarded.
The plugin keeps at most 40 generated chart images. Amounts are calculated
locally using Decimal and never sent to the rate provider.

## Page map

`fx-atlas:converter` is one focused detail page. The query edits the conversion;
the range toolbar edits the chart window. Copy and Swap are visible primary
actions; image and source actions live in Ctrl+K. Loading and error states stay
on this page, with an example action for recovery. Escape exits normally.

## Generate a standalone image

From this folder, with Pillow installed:

```powershell
python main.py --snapshot "100 EUR USD 30d" --output preview.png
python main.py --snapshot "250 USD RON 90d" --light --output preview-light.png
```

This fetches actual rates and creates the same image used by the launcher.
Windows uses Segoe UI and Georgia; a Pillow font fallback is used when these
fonts are unavailable. No native platform APIs are required by the script.
