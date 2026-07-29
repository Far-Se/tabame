# BC Uninstaller — Tabame plugin

Ported from the "List Applications" BCUninstaller extension for Raycast.
Search installed software, queue several apps, and batch-uninstall them
(quietly where possible) through [BC Uninstaller](https://github.com/Klocman/BulkCrapUninstaller)'s
`BCU-console.exe`.

## Install

1. Copy this folder to `%localappdata%\Tabame\plugins\bcuninstaller\`.
2. Open the Tabame launcher and type `uninstall`.
3. First run: pick **Settings** (`Ctrl+S`) and set the path to
   `BCU-console.exe`, `BCUninstaller.exe`, or the BC Uninstaller install
   folder — Tabame resolves any of the three the same way the original
   Raycast extension did.

BC Uninstaller always launches elevated (`Start-Process -Verb RunAs`), so
expect a UAC prompt on the first export of a session and on every uninstall.

## Using it

- Type after the keyword to filter by name, publisher, version, uninstall
  kind, or BCU identifiers.
- **Enter** on an app toggles it into the queue (shown as the first row,
  "N queued apps").
- **Ctrl+K** on an app: *Copy BCU Identifier*.
- **Ctrl+Enter**: uninstall everything in the queue (confirmation dialog
  shows the quiet vs. non-quiet split and whether leftover-junk cleanup is
  enabled).
- **Ctrl+Shift+Delete**: clear the queue.
- **Ctrl+F**: change visibility (default / include updates / include system
  / include protected / show all) — mirrors the Raycast dropdown.
- **Ctrl+D**: toggle the split preview pane (publisher, version, install
  location, rating/registry identifiers, etc.).
- **Ctrl+R**: force a refresh (re-runs the elevated export).

## Notes on the port

- The XML export/uninstall-list handling, stable app IDs, and match-target
  fallback logic (`RatingId` → `RegistryKeyName` → display name/publisher/
  version) are ported line-for-line from the original TypeScript.
- No third-party packages are needed — XML parsing uses Python's stdlib
  `xml.etree.ElementTree`, so there's nothing for Tabame to `pip install`.
- Settings (`bcu_path`, auto-cleanup flag, visibility, preview-pane state)
  and the last exported app list are persisted via Tabame's `storage`
  command instead of Raycast's `Cache`/preferences, so they survive
  between launcher sessions without a settings file to hand-edit.
- Clipboard/open/toast/hide are done through Tabame protocol commands
  instead of Node's `Clipboard`/`open`/shell calls.
