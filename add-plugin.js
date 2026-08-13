#!/usr/bin/env node

/**
 * Registers a Tabame plugin found under plugins/<PluginFolder> into
 * resources/plugins.json.
 *
 * Usage:
 *   node add-plugin.js <PluginFolder>
 *   node add-plugin.js missing
 *   node add-plugin.js check
 *
 * The "missing" command registers every repository plugin folder that is
 * not already present in resources/plugins.json. The "check" command lists
 * locally installed plugins that are not present in the registry.
 */

const fs = require("fs");
const path = require("path");

function fail(message) {
  console.error(`Error: ${message}`);
  process.exit(1);
}

function parseJson(raw, fileName) {
  // UTF-8 files created by some Windows tools can begin with a byte-order
  // mark. JSON.parse rejects that character, even though editors commonly
  // display the file as valid JSON.
  const withoutBom = raw.replace(/^\uFEFF/, "");
  try {
    return JSON.parse(withoutBom);
  } catch (err) {
    fail(`${fileName} is not valid JSON: ${err.message}`);
  }
}

const repoRoot = __dirname;
const branch = "main";
const pluginsPath = path.join(repoRoot, "plugins");
const registryPath = path.join(repoRoot, "resources", "plugins.json");

function readRegistry() {
  const registryRaw = fs.readFileSync(registryPath, "utf8");
  const registry = parseJson(registryRaw, "resources/plugins.json");

  if (
    !registry ||
    typeof registry !== "object" ||
    !Array.isArray(registry.plugins)
  ) {
    fail('resources/plugins.json is missing a "plugins" array.');
  }

  return registry;
}

function writeRegistry(registry) {
  // Write plain UTF-8, no BOM. This keeps special characters intact.
  fs.writeFileSync(registryPath, JSON.stringify(registry, null, 2), "utf8");
}

function validateManifest(manifest, pluginFolder) {
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) {
    fail("plugin.json must contain a JSON object.");
  }

  for (const field of [
    "name",
    "keyword",
    "description",
    "icon",
    "runtime",
    "entry",
    "version",
  ]) {
    const value = manifest[field];
    if (value === undefined || value === null || String(value).trim() === "") {
      fail(`plugin.json must contain a '${field}' value. ${pluginFolder}`);
    }
  }
}

function buildPluginRegistration(pluginFolder) {
  const pluginPath = path.join(pluginsPath, pluginFolder);
  const manifestPath = path.join(pluginPath, "plugin.json");

  if (!fs.existsSync(manifestPath) || !fs.statSync(manifestPath).isFile()) {
    fail(`No plugin.json found in plugins/${pluginFolder}.`);
  }

  // Always read as UTF-8 explicitly. This avoids the mangled special
  // character issue from the old PowerShell version.
  const manifestRaw = fs.readFileSync(manifestPath, "utf8");
  const manifest = parseJson(
    manifestRaw,
    `plugins/${pluginFolder}/plugin.json`,
  );
  validateManifest(manifest, pluginFolder);

  const pluginId = manifest.id || pluginFolder;
  const githubPath = `https://github.com/Far-Se/tabame/tree/${branch}/plugins/${pluginFolder}`;
  const rawPath = `https://raw.githubusercontent.com/Far-Se/tabame/${branch}/plugins/${pluginFolder}`;

  // Plain JS objects preserve insertion order for string keys.
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

  // Font assets can be organised into nested font-family directories, so
  // preserve their relative paths.
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

  return {
    pluginId,
    registration: {
      id: pluginId,
      name: manifest.name,
      keyword: manifest.keyword,
      description: manifest.description,
      icon: manifest.icon,
      runtime: manifest.runtime,
      author: "Far-Se",
      version: manifest.version ?? "1.0.0",
      homepage: githubPath,
      files,
    },
  };
}

function addPlugin(pluginFolder) {
  const registry = readRegistry();
  const { pluginId, registration } = buildPluginRegistration(pluginFolder);

  if (registry.plugins.some((plugin) => plugin && plugin.id === pluginId)) {
    fail(`A plugin with id '${pluginId}' is already registered.`);
  }

  registry.plugins.push(registration);
  writeRegistry(registry);

  console.log(`Added '${pluginId}' to resources/plugins.json.`);
}

function addMissingPlugins() {
  const registry = readRegistry();
  if (!fs.existsSync(pluginsPath) || !fs.statSync(pluginsPath).isDirectory()) {
    fail("The repository plugins folder does not exist.");
  }

  const registeredIds = new Set(
    registry.plugins
      .filter(
        (plugin) => plugin && plugin.id !== undefined && plugin.id !== null,
      )
      .map((plugin) => String(plugin.id)),
  );
  const additions = [];

  const pluginFolders = fs
    .readdirSync(pluginsPath, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .sort((left, right) => left.name.localeCompare(right.name));

  for (const entry of pluginFolders) {
    const manifestPath = path.join(pluginsPath, entry.name, "plugin.json");
    if (!fs.existsSync(manifestPath) || !fs.statSync(manifestPath).isFile()) {
      console.warn(`Skipping '${entry.name}': no plugin.json found.`);
      continue;
    }

    const { pluginId, registration } = buildPluginRegistration(entry.name);
    if (registeredIds.has(String(pluginId))) continue;

    registeredIds.add(String(pluginId));
    additions.push({ folder: entry.name, pluginId, registration });
  }

  if (additions.length === 0) {
    console.log("No missing plugins found.");
    return;
  }

  for (const addition of additions) {
    registry.plugins.push(addition.registration);
  }
  writeRegistry(registry);

  console.log(
    `Added ${additions.length} missing plugin(s) to resources/plugins.json:`,
  );
  for (const addition of additions) {
    console.log(`- ${addition.pluginId} (plugins/${addition.folder})`);
  }
}

function normalizeIdentity(value) {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
}

function addIdentityFromUrl(identities, value) {
  if (typeof value !== "string") return;

  const match = value.match(/\/plugins\/([^/?#]+)/i);
  if (!match) return;

  try {
    identities.add(normalizeIdentity(decodeURIComponent(match[1])));
  } catch {
    identities.add(normalizeIdentity(match[1]));
  }
}

function getRegistryIdentities(registry) {
  const identities = new Set();

  for (const plugin of registry.plugins) {
    if (!plugin || typeof plugin !== "object") continue;
    if (plugin.id !== undefined && plugin.id !== null) {
      identities.add(normalizeIdentity(plugin.id));
    }
    addIdentityFromUrl(identities, plugin.homepage);
    if (plugin.files && typeof plugin.files === "object") {
      addIdentityFromUrl(identities, plugin.files["plugin.json"]);
    }
  }

  return identities;
}

function readLocalPluginInfo(pluginPath, folder) {
  const manifestPath = path.join(pluginPath, "plugin.json");
  if (!fs.existsSync(manifestPath) || !fs.statSync(manifestPath).isFile()) {
    return { id: folder };
  }

  try {
    const manifest = JSON.parse(
      fs.readFileSync(manifestPath, "utf8").replace(/^\uFEFF/, ""),
    );
    return {
      id:
        manifest &&
        manifest.id !== undefined &&
        manifest.id !== null &&
        String(manifest.id).trim() !== ""
          ? String(manifest.id)
          : folder,
    };
  } catch {
    return { id: folder, invalidManifest: true };
  }
}

function checkLocalPlugins() {
  const localAppData = process.env.LOCALAPPDATA;
  if (!localAppData) {
    fail("The LOCALAPPDATA environment variable is not set.");
  }

  const localPluginsPath = path.join("E:\\Resources\\Backup", "tabame-plugins");
  if (
    !fs.existsSync(localPluginsPath) ||
    !fs.statSync(localPluginsPath).isDirectory()
  ) {
    console.log(`Local plugins folder not found: ${localPluginsPath}`);
    return;
  }

  const registry = readRegistry();
  const registeredIdentities = getRegistryIdentities(registry);
  const localPlugins = fs
    .readdirSync(localPluginsPath, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .sort((left, right) => left.name.localeCompare(right.name))
    .map((entry) => {
      const info = readLocalPluginInfo(
        path.join(localPluginsPath, entry.name),
        entry.name,
      );
      return {
        folder: entry.name,
        id: info.id,
        invalidManifest: info.invalidManifest,
      };
    });

  const missing = localPlugins.filter((plugin) => {
    const identities = [plugin.folder, plugin.id].map(normalizeIdentity);
    return !identities.some((identity) => registeredIdentities.has(identity));
  });

  if (missing.length === 0) {
    console.log("All local plugins are registered in resources/plugins.json.");
    return;
  }

  console.log("Local plugins not registered in resources/plugins.json:");
  for (const plugin of missing) {
    if (["atm"].includes(plugin.folder)) continue;
    const details = plugin.id !== plugin.folder ? ` (id: ${plugin.id})` : "";
    const manifestWarning = plugin.invalidManifest
      ? " [invalid plugin.json]"
      : "";
    console.log(`- ${plugin.folder}${details}${manifestWarning}`);
  }
}

const command = process.argv[2];
if (!command) {
  fail(
    "Usage: node add-plugin.js <PluginFolder>\n" +
      "       node add-plugin.js missing\n" +
      "       node add-plugin.js check",
  );
}

if (command === "missing") {
  addMissingPlugins();
} else if (command === "check") {
  checkLocalPlugins();
} else {
  addPlugin(command);
}
