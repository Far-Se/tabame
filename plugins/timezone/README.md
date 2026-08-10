# Timezone Converter — Tabame plugin

Convert a time between local time, named regions, city aliases, and IANA
timezone identifiers from the Tabame launcher.

The plugin keyword is `tz`.

## Install

1. Make sure Python 3 is available on `PATH`.
2. Copy this folder to:

   ```text
   %localappdata%\Tabame\plugins\timezone\
   ```

3. Reopen the Tabame launcher. Tabame rescans plugins whenever the launcher is
   opened.
4. Type `tz` followed by a query.

The manifest declares `tzdata>=2024.1`. Tabame installs it into the plugin's
private dependency directory on first launch so Windows receives the full IANA
rules and current/future daylight-saving transitions. If dependency installation
is unavailable, the plugin still works with the offsets in `timezones.json`, but
some regions may not have complete DST behavior.

## Query syntax

Queries are case-insensitive and update as you type:

| Query | Result |
| --- | --- |
| `tz 3 PM` | Show the local 3 PM across the bundled world region catalog. |
| `tz 11:30 PM PT` | Interpret the time in Pacific Time, then compare it with local and world regions. |
| `tz 9 AM ET to CET` | Convert 9 AM from Eastern Time to Central European Time. |
| `tz now in Tokyo` | Convert the current local time to Tokyo. |
| `tz noon UTC` | Show noon interpreted as UTC. |
| `tz Los Angeles` | Convert the current local time to Los Angeles. |
| `tz Kathmandu` | Convert the current local time to Kathmandu, including its UTC+05:45 offset. |
| `tz Central Asia Standard Time` | Convert the current local time to a multi-word catalog region. |
| `tz America/Sao_Paulo` | Use an IANA timezone identifier directly. |

A query containing only a timezone name is treated as a destination. The source
is the current local time, so typing `Los Angeles` does not turn Los Angeles into
the source of a full world comparison. The requested destination appears first;
local time is also shown when its current offset differs from the destination.

Supported timezone names come from the bundled `timezones.json` catalog. It
contains 108 Windows timezone entries, which are deduplicated into 104 region
results. Catalog entries also expose their IANA identifiers and city labels, so
names such as `Cairo`, `Fiji`, `Brasilia`, and `South Africa` are available.

The existing short aliases remain available:

```text
PT  MT  CT  ET  UTC  UK  CET  EET  IST  JST  AEST  NZ
```

Common city aliases include `New York`, `Los Angeles`, `London`, `Paris`,
`Bucharest`, `Dubai`, `Tokyo`, `Sydney`, `Cairo`, and `Kathmandu`.

## Results and actions

Each result shows the converted time, timezone abbreviation, UTC offset, and a
day-shift badge when the conversion crosses midnight. Select a result to open
its preview. Use **Enter** or the **Copy time** action to copy a compact time
string to the Windows clipboard.

## Data and accuracy

- `timezones.json` is the display and alias catalog.
- Python's standard-library `zoneinfo` provides the actual IANA timezone rules.
- The `tzdata` package supplies those rules on Windows systems without a system
  timezone database.
- If IANA data cannot be loaded, the catalog's listed offset is used as a safe
  fixed-offset fallback.
- No web request or API key is required.

## Development

Run the focused tests from the repository root:

```text
python -m unittest plugins.timezone.test_main -v
python -m py_compile plugins/timezone/main.py plugins/timezone/test_main.py
```

The plugin communicates with Tabame using newline-delimited JSON over stdin and
stdout. Render frames are written to stdout; diagnostics should go to stderr.
