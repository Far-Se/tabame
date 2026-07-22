# Weather — Tabame plugin

Generates a nice weather image (today's forecast, or a 7-day strip) and shows
it right in the launcher.

## Usage

Type `weather` followed by a city, then press **Enter**:

```
weather Iasi              -> today's weather for Iasi
weather Iasi weekly        -> 7-day forecast
weather Iasi w              -> same as "weekly" (short form)
weather Iasi f              -> today's weather in Fahrenheit
weather Iasi weekly f       -> 7-day forecast in Fahrenheit
```

If you don't type a city, it falls back to `defaultCity` in `config.json`
(see below), or shows quick instructions if none is set.

While a result is showing, press **Ctrl+T** to flip between today/weekly for
the same city without retyping.

## Install

1. Copy this whole folder to:
   `%localappdata%\Tabame\plugins\weather\`
2. Open the Tabame launcher (it rescans plugins on open).
3. Type `weather <your city>` and press Enter.

The first launch installs Pillow into the plugin's own `.pluginlibs` folder —
you'll see a short "Installing dependencies…" step once.

## Optional config

Rename `config.json.example` to `config.json` to set a default city and/or
switch to Fahrenheit:

```json
{
  "defaultCity": "Iasi",
  "units": "celsius"
}
```

`units` can be `"celsius"` or `"fahrenheit"`. Adding `f` to the end of a
query temporarily switches that result to Fahrenheit.

## How it works

- Geocoding + forecast data come from the free [Open-Meteo](https://open-meteo.com)
  API — no API key needed.
- The weather card is drawn with Pillow (vector-style icons, gradient
  background, a bundled Lato font) and saved as a PNG next to the plugin.
- A tiny local HTTP server (bound to `127.0.0.1` only, random port, one per
  running plugin instance) serves that PNG so it can be embedded as a normal
  image in the result markdown.
