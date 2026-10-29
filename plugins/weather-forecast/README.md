# Weather Forecast

Type `forecast London`, choose the correct city, and press Enter. The city is
saved automatically. Next time, just type `forecast` to load its weather.
Type a new city at any time to search again; country qualifiers such as
`forecast Paris, France` help distinguish places with the same name.

The full-width PNG includes current conditions, feels-like temperature, wind,
humidity, UV, sunrise/sunset, 24 individual hourly forecasts with temperature
curves and precipitation probabilities, and seven daily forecasts with high/low
range bars, precipitation probability/amount and maximum wind. Times belong to
the selected city, including daylight-saving transitions.

Open **Ctrl+K** and choose **Use Freedom Unit (°F)** / **Use Celsius (°C)** to switch.
The choice is saved immediately. Freedom Unit uses °F, mph, and inches; Celsius
uses °C, km/h, and mm. Click the image to zoom. **Ctrl+K** also offers Refresh,
Copy forecast image, Open forecast image, Change city, and Weather data source.

## Pages

| Page | View | Query / primary action | Navigation |
| --- | --- | --- | --- |
| `weather:search` | List | Search city names; Enter selects and saves a city | Forecast; Back returns to saved forecast |
| `weather:forecast` | Wide detail image | Typing searches for another city; Ctrl+K for unit switch and refresh | Search; image zoom / copy / open |

Loading, no-match, first-use, and network error states provide explicit feedback.
Search is debounced and outdated requests cannot replace newer results. Weather
is cached for ten minutes; Refresh bypasses it. If the network fails, a cached
forecast is clearly marked with its age and a warning, never presented as live.

## Install

Copy this folder to `%LOCALAPPDATA%\Tabame\plugins\weather-forecast\`, then reopen
the launcher. Python 3.10+ must be on PATH. Tabame installs Pillow, tzdata, and certifi from
the manifest on first launch. No API key is needed for the public non-commercial
Open-Meteo API. Other plugins are independent and are not changed.

HTTPS requests use certifi's maintained certificate bundle with certificate and
hostname verification enabled, matching the other weather plugins.

Preferences use Tabame's per-plugin storage (`.tabame-store.json`); weather data
and generated PNGs live in `.cache/`. Clearing the cache does not clear preferences.
The PNG is drawn from forecast data using Pillow, so it does not require an image
generation service. Windows uses Segoe UI; other platforms use available fonts.

Data: [Open-Meteo](https://open-meteo.com/),
[forecast API](https://open-meteo.com/en/docs), and
[geocoding API](https://open-meteo.com/en/docs/geocoding-api).
Weather data is [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
