"""Illustrative design-preview data. Never used by the launcher or as fallback."""

import math
from datetime import datetime, timedelta, timezone


def sample_forecast():
    city = {"name": "Bucharest", "admin1": "Bucharest", "country": "Romania",
            "latitude": 44.43225, "longitude": 26.10626}
    base = datetime(2026, 10, 29, tzinfo=timezone(timedelta(hours=2)))
    ts = lambda hour: int((base + timedelta(hours=hour)).timestamp())
    hourly = {key: [] for key in ("time", "temperature_2m", "precipitation_probability", "weather_code", "wind_speed_10m", "is_day")}
    for hour in range(168):
        clock = hour % 24
        temp = 13 + 6 * math.cos((clock - 15) * math.pi / 12)
        code = 2 if clock < 19 else 3
        if hour >= 30:
            code = 61 if clock < 11 else 3
        values = (ts(hour), round(temp, 1), 10 if hour < 26 else 65, code, 8 + hour % 11, int(7 <= clock < 18))
        for key, value in zip(hourly, values):
            hourly[key].append(value)
    daily = {
        "time": [ts(i * 24) for i in range(7)],
        "weather_code": [2, 61, 3, 0, 1, 80, 2],
        "temperature_2m_max": [19, 15, 16, 18, 20, 17, 18],
        "temperature_2m_min": [8, 9, 7, 6, 8, 10, 8],
        "sunrise": [ts(i * 24 + 6.85) for i in range(7)],
        "sunset": [ts(i * 24 + 17.1) for i in range(7)],
        "uv_index_max": [3, 1, 2, 3, 3, 2, 2],
        "precipitation_probability_max": [10, 75, 20, 0, 5, 65, 15],
        "precipitation_sum": [0, 4.2, 0.3, 0, 0, 2.8, 0.1],
        "wind_speed_10m_max": [14, 22, 18, 9, 12, 24, 16],
    }
    return city, {
        "timezone": "Europe/Bucharest", "utc_offset_seconds": 7200,
        "current": {"time": ts(14), "temperature_2m": 19, "apparent_temperature": 18,
                    "relative_humidity_2m": 54, "is_day": 1, "weather_code": 2,
                    "wind_speed_10m": 12, "wind_direction_10m": 225,
                    "wind_gusts_10m": 19, "precipitation": 0},
        "hourly": hourly, "daily": daily,
    }
