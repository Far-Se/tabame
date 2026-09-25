# Home Assistant for Tabame

Search and control Home Assistant entities from Tabame's QuickMenu launcher. The
plugin uses the Home Assistant REST API and does not require npm packages.

## Install

Copy this folder to `%localappdata%\Tabame\plugins\home_assistant\`. Node.js 18+
must be available on `PATH`. Reopen the launcher, type `home`, and enter your
Home Assistant URL and Long-Lived Access Token. The token is saved with Tabame's
secret storage command (Windows Credential Manager). The settings form shows a
masked placeholder once the token is saved. No token is written to a plugin
config file.

The plugin is also registered in Tabame's plugin gallery. Gallery installation
copies all JavaScript files alongside the manifest.

## Use

- `home` shows favorites, recent entities, and domain categories.
- `home desk` searches names, entity IDs, domains, rooms, and device names.
- `home scenes` lists scenes; `home lights bedroom` filters lights by room/name.
- Enter toggles a light or switch, activates a scene, or opens details for
  entities without an obvious default action.
- Ctrl+K exposes supported controls, Details, Favorites, Refresh Entities,
  Test Connection, and Settings. Details also has visible action buttons.
- Settings has Save, Test Connection, and Refresh Entities buttons. Leave the
  password field blank to keep the saved token.

The state list is fetched when the plugin opens, on manual refresh, and after a
60-second cache timeout. Typing searches the local cache. After a control action,
the plugin requests that entity's current state. Home Assistant's template REST
endpoint supplies room and device names in one optional batch request; state
search still works if the endpoint is unavailable.

An unavailable or unknown entity can be inspected but cannot be controlled.
Favorites and recent entities stay in Tabame's per-plugin storage, independent
of Home Assistant.
