#!/usr/bin/env node

/**
 * Registers a Tabame plugin found under plugins/<PluginFolder> into
 * resources/plugins.json.
 *
 * Usage:
 *   node add-plugin.js <PluginFolder>
 *
 * This is a Node.js port of the original PowerShell script. The garbled
 * special characters (e.g. "—") in the old script came from PowerShell's
 * Get-Content/Set-Content defaulting to lossy encodings (Windows-1252 on
 * read, UTF-8-with-BOM on write) unless you're careful. Node's fs API
 * reads/writes plain UTF-8 by default with no BOM, so as long as every
 * read/write below explicitly uses 'utf8', text round-trips cleanly.
 */

const fs = require("fs");
const path = require("path");

function fail(message) {
  console.error(`Error: ${message}`);
  process.exit(1);
}

const pluginFolder = process.argv[2];
if (!pluginFolder) {
  fail("Usage: node add-plugin.js <PluginFolder>");
}

const repoRoot = __dirname;
const pluginPath = path.join(repoRoot, "plugins", pluginFolder);
const manifestPath = path.join(pluginPath, "plugin.json");

if (!fs.existsSync(manifestPath) || !fs.statSync(manifestPath).isFile()) {
  fail(`No plugin.json found in plugins/${pluginFolder}.`);
}

// Always read as 'utf8' explicitly — this is what avoids the mangled
// special-character issue from the PowerShell version.
const manifestRaw = fs.readFileSync(manifestPath, "utf8");
let manifest;
try {
  manifest = JSON.parse(manifestRaw);
} catch (err) {
  fail(`plugin.json is not valid JSON: ${err.message}`);
}

for (const field of [
  "name",
  "keyword",
  "description",
  "icon",
  "runtime",
  "entry",
]) {
  const value = manifest[field];
  if (value === undefined || value === null || String(value).trim() === "") {
    fail(`plugin.json must contain a '${field}' value.`);
  }
}

const pluginId = manifest.id || pluginFolder;
const branch = "main";
const githubPath = `https://github.com/Far-Se/tabame/tree/${branch}/plugins/${pluginFolder}`;
const rawPath = `https://raw.githubusercontent.com/Far-Se/tabame/${branch}/plugins/${pluginFolder}`;

// Preserve insertion order like the PowerShell [ordered]@{} did — plain JS
// objects keep insertion order for string keys, so this "just works".
const files = {
  "plugin.json": `${rawPath}/plugin.json`,
};

for (const entry of fs.readdirSync(pluginPath, { withFileTypes: true })) {
  if (!entry.isFile()) continue;
  const ext = path.extname(entry.name);
  if (ext === ".py" || ext === ".js") {
    files[entry.name] = `${rawPath}/${entry.name}`;
  }
}

// Bundle font assets when present. Unlike source files, these may be
// organised into nested font-family directories, so preserve their
// relative paths.
const fontsPath = path.join(pluginPath, "fonts");
if (fs.existsSync(fontsPath) && fs.statSync(fontsPath).isDirectory()) {
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else if (entry.isFile()) {
        const relativePath = path
          .relative(pluginPath, full)
          .split(path.sep)
          .join("/");
        files[relativePath] = `${rawPath}/${relativePath}`;
      }
    }
  };
  walk(fontsPath);
}

for (const file of ["config.example.json", "README.md"]) {
  const filePath = path.join(pluginPath, file);
  if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
    files[file] = `${rawPath}/${file}`;
  }
}

const registryPath = path.join(repoRoot, "resources", "plugins.json");
const registryRaw = fs.readFileSync(registryPath, "utf8");
let registry;
try {
  registry = JSON.parse(registryRaw);
} catch (err) {
  fail(`resources/plugins.json is not valid JSON: ${err.message}`);
}

if (!Array.isArray(registry.plugins)) {
  fail('resources/plugins.json is missing a "plugins" array.');
}

if (registry.plugins.some((p) => p.id === pluginId)) {
  fail(`A plugin with id '${pluginId}' is already registered.`);
}

registry.plugins.push({
  id: pluginId,
  name: manifest.name,
  keyword: manifest.keyword,
  description: manifest.description,
  icon: manifest.icon,
  runtime: manifest.runtime,
  author: "Far-Se",
  version: "1.0.0",
  homepage: githubPath,
  files,
});

// Write plain UTF-8, no BOM — this keeps special characters intact.
fs.writeFileSync(registryPath, JSON.stringify(registry, null, 2), "utf8");

console.log(`Added '${pluginId}' to resources/plugins.json.`);
