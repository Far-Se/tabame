"use strict";

const { pathToFileURL } = require("url");
const fs = require("fs");
const os = require("os");
const path = require("path");

function send(frame) {
  process.stdout.write(JSON.stringify(frame) + "\n");
}

const cache = new Map();

// Forecast graphs are written as SVG files into the OS temp dir and referenced
// from the detail markdown via file:// URLs. Unique names per write dodge the
// host's image caches; leftovers from earlier runs are swept on startup.
const GRAPH_PREFIX = "tabame-weather-graph-";

try {
  for (const f of fs.readdirSync(os.tmpdir())) {
    if (f.startsWith(GRAPH_PREFIX) && f.endsWith(".svg")) {
      try {
        fs.unlinkSync(path.join(os.tmpdir(), f));
      } catch {
        /* in use */
      }
    }
  }
} catch {
  /* best effort */
}

// 7-day forecast graph: max/min temperature lines over rain-probability bars.
function forecastGraphSvg(daily) {
  const n = daily.time.length;
  const maxs = daily.temperature_2m_max;
  const mins = daily.temperature_2m_min;
  const rain = daily.precipitation_probability_max;

  const W = 320,
    H = 180;
  const left = 16,
    right = 16;
  const tempTop = 30,
    tempBottom = 100;
  const rainTop = 128,
    rainBottom = 158;

  const MAXC = "#e34948",
    MINC = "#3987e5",
    INK = "#898781";

  const xs = (i) =>
    n === 1 ? W / 2 : left + (i * (W - left - right)) / (n - 1);

  const lo = Math.min(...mins);
  const span = Math.max(Math.max(...maxs) - lo, 1);
  const ty = (v) => tempBottom - ((v - lo) / span) * (tempBottom - tempTop);

  const parts = [];

  parts.push(
    `<circle cx="17" cy="12" r="3" fill="${MAXC}"/>`,
    `<text x="24" y="15" font-size="9" fill="${INK}">Max</text>`,
    `<circle cx="60" cy="12" r="3" fill="${MINC}"/>`,
    `<text x="67" y="15" font-size="9" fill="${INK}">Min</text>`,
    `<rect x="101" y="8.5" width="7" height="7" rx="2" fill="${MINC}" opacity="0.45"/>`,
    `<text x="112" y="15" font-size="9" fill="${INK}">Rain %</text>`,
  );

  for (const [vals, color] of [
    [maxs, MAXC],
    [mins, MINC],
  ]) {
    const pts = vals
      .map((v, i) => `${xs(i).toFixed(1)},${ty(v).toFixed(1)}`)
      .join(" ");
    parts.push(
      `<polyline points="${pts}" fill="none" stroke="${color}" stroke-width="2" ` +
        `stroke-linecap="round" stroke-linejoin="round"/>`,
    );
    for (let i = 0; i < n; i++) {
      const x = xs(i).toFixed(1);
      const y = ty(vals[i]);
      const labelY = color === MAXC ? y - 7 : y + 13;
      parts.push(
        `<circle cx="${x}" cy="${y.toFixed(1)}" r="3" fill="${color}"/>`,
        `<text x="${x}" y="${labelY.toFixed(1)}" font-size="9" font-weight="600" ` +
          `fill="${INK}" text-anchor="middle">${Math.round(vals[i])}°</text>`,
      );
    }
  }

  for (let i = 0; i < n; i++) {
    const p = rain[i] ?? 0;
    const x = xs(i);
    const top = rainBottom - (Math.max(p, 0) / 100) * (rainBottom - rainTop);
    const h = rainBottom - top;
    if (h >= 1) {
      const w = 16,
        r = Math.min(2, h / 2);
      const x0 = (x - w / 2).toFixed(1),
        x1 = (x + w / 2).toFixed(1);
      parts.push(
        `<path d="M ${x0},${rainBottom} V ${(top + r).toFixed(1)} Q ${x0},${top.toFixed(1)} ` +
          `${(x - w / 2 + r).toFixed(1)},${top.toFixed(1)} H ${(x + w / 2 - r).toFixed(1)} ` +
          `Q ${x1},${top.toFixed(1)} ${x1},${(top + r).toFixed(1)} V ${rainBottom} Z" ` +
          `fill="${MINC}" opacity="0.45"/>`,
      );
    }
    parts.push(
      `<text x="${x.toFixed(1)}" y="${(top - 3).toFixed(1)}" font-size="8" fill="${INK}" ` +
        `text-anchor="middle">${Math.round(p)}%</text>`,
    );
  }

  parts.push(
    `<line x1="${left - 8}" y1="${rainBottom}" x2="${W - right + 8}" y2="${rainBottom}" ` +
      `stroke="${INK}" stroke-width="1" opacity="0.3"/>`,
  );

  for (let i = 0; i < n; i++) {
    const day =
      i === 0
        ? "Today"
        : new Date(daily.time[i] + "T00:00:00").toLocaleDateString("en-US", {
            weekday: "short",
          });
    parts.push(
      `<text x="${xs(i).toFixed(1)}" y="172" font-size="9" fill="${INK}" ` +
        `text-anchor="middle">${day}</text>`,
    );
  }

  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" ` +
    `viewBox="0 0 ${W} ${H}" font-family="Segoe UI, sans-serif">${parts.join("")}</svg>`
  );
}

function writeGraph(place, daily, isFahrenheit) {
  try {
    const slug = place.name.toLowerCase().replace(/[^a-z0-9]+/g, "-");
    const fSuffix = isFahrenheit ? "-f" : "-c";
    const file = path.join(
      os.tmpdir(),
      `${GRAPH_PREFIX}${slug}${fSuffix}-${Date.now()}.svg`,
    );
    fs.writeFileSync(file, forecastGraphSvg(daily), "utf8");
    return pathToFileURL(file).href;
  } catch (err) {
    process.stderr.write(`graph: ${err.message}\n`);
    return null;
  }
}

async function geocode(location) {
  const url = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(location)}&count=1&language=en&format=json`;

  const res = await fetch(url);

  if (!res.ok) throw new Error("Unable to search location.");

  const json = await res.json();

  if (!json.results || json.results.length === 0) return null;

  return json.results[0];
}

async function weather(lat, lon, isFahrenheit) {
  const unitParam = isFahrenheit ? "&temperature_unit=fahrenheit" : "";
  const url =
    `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}` +
    `&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m` +
    `&hourly=temperature_2m,weather_code` +
    `&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max` +
    `&timezone=auto${unitParam}`;

  const res = await fetch(url);

  if (!res.ok) throw new Error("Unable to fetch weather.");

  return await res.json();
}

function weatherText(code) {
  const map = {
    0: "Clear sky",
    1: "Mainly clear",
    2: "Partly cloudy",
    3: "Overcast",
    45: "Fog",
    48: "Fog",
    51: "Light drizzle",
    53: "Drizzle",
    55: "Heavy drizzle",
    61: "Light rain",
    63: "Rain",
    65: "Heavy rain",
    71: "Snow",
    73: "Snow",
    75: "Heavy snow",
    77: "Snow grains",
    80: "Rain showers",
    81: "Rain showers",
    82: "Heavy showers",
    85: "Snow showers",
    86: "Heavy snow showers",
    95: "Thunderstorm",
    96: "Thunderstorm + hail",
    99: "Severe thunderstorm",
  };
  return map[code] || "Unknown";
}

async function render(rev, query) {
  const trimmed = query.trim();
  if (!trimmed) {
    send({
      type: "render",
      rev,
      view: "detail",
      detail: {
        markdown: `# Weather\n\nType a city. Append \` f\` for Fahrenheit.\n\nExamples:\n- weather London\n- weather Paris f\n- weather Tokyo`,
      },
    });
    return;
  }

  // Parse fahrenheit setting
  const isFahrenheit = /[\s]+f$/i.test(trimmed);
  const cleanQuery = isFahrenheit
    ? trimmed.replace(/[\s]+f$/i, "").trim()
    : trimmed;
  const unitLabel = isFahrenheit ? "°F" : "°C";

  send({
    type: "render",
    rev,
    loading: true,
    view: "list",
    emptyText: "Loading...",
    items: [],
  });

  try {
    const cacheKey = `${cleanQuery.toLowerCase()}_${isFahrenheit ? "f" : "c"}`;
    let entry = cache.get(cacheKey);

    if (!entry) {
      const place = await geocode(cleanQuery);

      if (!place) {
        send({
          type: "render",
          rev,
          view: "detail",
          detail: {
            markdown: `# No location found\n\nCouldn't find **${cleanQuery}**.`,
          },
        });
        return;
      }

      const forecast = await weather(
        place.latitude,
        place.longitude,
        isFahrenheit,
      );
      entry = {
        place,
        forecast,
        graphUrl: writeGraph(place, forecast.daily, isFahrenheit),
      };
      cache.set(cacheKey, entry);
    }

    const { place, forecast, graphUrl } = entry;
    const cur = forecast.current;
    const daily = forecast.daily;
    const hourly = forecast.hourly;

    // 1. Prepare Hourly Data (Next 12 Hours)
    const currentHourStr = cur.time.substring(0, 13) + ":00";
    let startIndex = hourly.time.indexOf(currentHourStr);
    if (startIndex === -1)
      startIndex = hourly.time.findIndex((t) => t >= currentHourStr) || 0;

    const hourlyData = [];
    for (
      let i = startIndex;
      i < Math.min(startIndex + 12, hourly.time.length);
      i++
    ) {
      const hrTime = new Date(hourly.time[i]);
      const displayTime = hrTime.toLocaleTimeString("en-US", {
        hour: "numeric",
        hour12: true,
      });
      hourlyData.push({
        hour: displayTime,
        temp: `**${hourly.temperature_2m[i]}${unitLabel}**`,
        cond: weatherText(hourly.weather_code[i]),
      });
    }

    // 2. Prepare Daily Data (7 Days)
    const dayName = (i) =>
      i === 0
        ? "Today"
        : new Date(daily.time[i] + "T00:00:00").toLocaleDateString("en-US", {
            weekday: "short",
            month: "short",
            day: "numeric",
          });

    const dailyData = daily.time.map((_, i) => ({
      day: dayName(i),
      cond: weatherText(daily.weather_code[i]),
      high: `**${daily.temperature_2m_max[i]}°**`,
      low: `${daily.temperature_2m_min[i]}°`,
      rain: `${daily.precipitation_probability_max[i]}%`,
    }));

    // 3. Combine into a Single Unified Table Row-by-Row
    const totalRows = Math.max(hourlyData.length, dailyData.length);
    const tableRows = [];

    // Header & Divider lines
    tableRows.push(
      `| Hour | Temp | Condition | | Day | Condition | High | Low | Rain |`,
    );
    tableRows.push(
      `| :--- | :--- | :--- | :---: | :--- | :--- | :--- | :--- | :--- |`,
    );

    for (let i = 0; i < totalRows; i++) {
      const h = hourlyData[i];
      const d = dailyData[i];

      // Current Conditions summary mapping for row 0 hourly rain column
      let hourlyRain = "-";
      if (
        i === 0 &&
        daily.precipitation_probability_max &&
        daily.precipitation_probability_max.length > 0
      ) {
        hourlyRain = `${daily.precipitation_probability_max[0]}%`;
      }

      // Build left side (Hourly) data or blanks
      const leftSide = h ? `| ${h.hour} | ${h.temp} | ${h.cond} |` : `| | | |`;

      // Build right side (Daily) data or blanks
      const rightSide = d
        ? ` | ${d.day} | ${d.cond} | ${d.high} | ${d.low} | ${d.rain} |`
        : ` | | | | | |`;

      tableRows.push(leftSide + rightSide);
    }

    const unifiedTableMd = tableRows.join("\n");
    const graphMd = graphUrl ? `\n\n![7-day forecast](${graphUrl})` : "";

    send({
      type: "render",
      rev,
      view: "detail",
      detail: {
        wide: false,
        markdown: `# ${place.name}${place.country ? `, ${place.country}` : ""}

### Current Overview & Forecast

${unifiedTableMd}${graphMd}

---
Data: [open-meteo.com](https://open-meteo.com/)`,
      },
    });
  } catch (err) {
    send({
      type: "render",
      rev,
      view: "detail",
      detail: {
        markdown: `# Error\n\n\`\`\`\n${err.message}\n\`\`\``,
      },
    });
  }
}

let buffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buffer += chunk;
  let idx;
  while ((idx = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, idx).trim();
    buffer = buffer.slice(idx + 1);
    if (!line) continue;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      continue;
    }

    switch (msg.type) {
      case "close":
        process.exit(0);
      case "init":
      case "query":
        render(msg.rev || 0, msg.text ?? msg.query ?? "");
        break;
    }
  }
});
process.stdin.on("end", () => process.exit(0));
