# Weather Board

A weather image for your launcher: current conditions, 24 individual hourly forecasts, and a seven-day outlook. The image includes custom day/night weather illustrations, hourly temperature curves, precipitation probabilities, wind, weekly temperature ranges, precipitation amounts, UV, and local sunrise/sunset times.

## Use

1. Type **`weatherboard Bucharest`** (or another city / postal code).
2. Select the correct location and press **Enter**. Add a country or region to disambiguate, such as `weatherboard Paris, France`.
3. Choose **Celsius · °C** or **Freedom Unit · °F** from the visible **Units** selector. Fahrenheit also uses mph and inches.
4. Next time, type just **`weatherboard`**. Your selected city and units are restored automatically.

Click the forecast image to zoom. Use **Refresh** / **Ctrl+R** to fetch new data, or **Copy image** to share the PNG. **Ctrl+K → Open forecast image** opens it in your default image viewer. Search above the image to change city; Back returns to the saved city.

## Install

Copy `plugin.json`, `main.py`, `forecast.py`, `render.py`, and `sample.py` into:

```text
%LOCALAPPDATA%\Tabame\plugins\weather-board\
```

Reopen the launcher to discover the plugin. Python 3.10+ must be on PATH. Tabame installs Pillow, tzdata, and certifi from the manifest on first launch. Both weather and city-search HTTPS requests use certifi's Mozilla CA bundle with certificate and hostname verification enabled. No API key is required. The independent keyword `weatherboard` avoids changing any other weather plugin.

If you have configured a custom plugins directory in Tabame, use its `weather-board` subfolder instead. `preview.png` in this source folder is an illustrative design preview, not a live forecast.

## Pages and behavior

| Page | View | Typing / primary action |
| --- | --- | --- |
| Welcome | Detail | Search a city; pick units in the toolbar |
| City matches | List | Debounced search; Enter saves a location and opens its forecast |
| Forecast | Wide detail with PNG | Typing searches another city; Refresh fetches data; Copy image shares it |
| Error / offline | Detail or saved forecast with banner | Retry, return to the saved city, or search again |

Preferences and one forecast snapshot use Tabame's per-plugin storage (`.tabame-store.json`). Generated images live in `.cache/`; the plugin retains the latest eight. Successful forecasts are reused for ten minutes. Refresh bypasses that cache. If a request fails, a snapshot less than 24 hours old can be shown with a warning and a dated **SAVED FORECAST** label; older snapshots are not displayed. Cached forecasts keep their original observation time and hourly window rather than implying that old conditions are current.

City searches are debounced; a single background worker handles network and rendering work. Superseded requests cannot replace the current view or save an unwanted city. Close and stdin EOF terminate immediately. Missing data is displayed as a dash. Hourly times use the forecast location's IANA timezone, including DST transitions, independently of the computer's timezone.

## Export a PNG directly

With Pillow, tzdata, and certifi available in your Python environment:

```text
python main.py --preview "Bucharest, Romania" --output forecast.png
python main.py --preview "New York, US" --units fahrenheit --output forecast-f.png
python main.py --demo --output preview.png
```

`--preview` fetches real weather and chooses the first geocoding match. `--demo` generates an explicitly labeled illustrative preview without network access. Neither changes your saved launcher preferences. Sample data is never used by the launcher or as an offline forecast.

## Sources

Weather: [Open-Meteo Forecast API](https://open-meteo.com/en/docs), under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Location search: [Open-Meteo Geocoding API](https://open-meteo.com/en/docs/geocoding-api), based on GeoNames. Attribution is included in the image and launcher. The public API is for non-commercial use and has usage limits; commercial redistribution should use the appropriate Open-Meteo service plan.
