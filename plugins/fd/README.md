# fd File Search for Tabame

Search several drives or folders from the Tabame launcher using
[`fd`](https://github.com/sharkdp/fd), with persistent include/exclude rules and
no plugin dependencies.

## Install

1. Install `fd` and make sure `fd --version` works. If it is missing, the plugin
   now offers **Install with Scoop**, **Install with Chocolatey**, and **Install
   with Winget** buttons. Each opens a visible command prompt, runs the selected
   command, and leaves the terminal open so you can review the result:

   ```powershell
   winget install sharkdp.fd
   # or: scoop install fd
   # or: choco install fd
   ```

2. Copy this folder to `%localappdata%\Tabame\plugins\fd\`.
3. Make sure Python 3 is on `PATH`.
4. Reopen the launcher and type **`fd`**. The first run opens Settings.

Tabame rescans plugins whenever the launcher opens, so no application restart is
needed.

## Search

Type `fd` followed by a filename fragment:

- `fd invoice` — smart-case literal substring search.
- `fd README` — uppercase makes fd's smart-case search case-sensitive.
- In **Glob** mode: `fd report*.pdf`.
- In **Regular expression** mode: `fd ^report.*\.pdf$`.

New keystrokes terminate the previous `fd` process. The plugin scans a bounded
candidate pool, ranks exact names and prefix matches first, and only then applies
the configured display limit.

### Result actions

- **Enter** — open the file/folder and dismiss Tabame.
- **Ctrl+K** — open its containing folder, copy its full/name/parent path, or
  paste the path into the previously focused app.
- **Ctrl+R** — rerun the current search.
- **Ctrl+Shift+S** — open Settings.

### File icons

On Windows, results use the shell icon for the file or folder instead of a
generic launcher icon. Icons are stored in `.cache/icons` inside this plugin:

- ordinary files share a cache entry by extension;
- packaged Windows associations, such as the default Media Player icon for
  `.mp3`, are resolved to their installed image asset;
- files whose icons can vary per path, such as `.exe`, `.dll`, `.lnk`, and
  `.url`, use a path-and-file-signature cache entry;
- **Ctrl+K -> Clear Icons Cache** removes the generated PNGs so associations or
  changed shortcut/executable icons can be picked up again.

Other platforms keep the existing extension-based fallback icons until native
file-icon extraction is implemented there.

## Settings

The settings page stores its data in Tabame's per-plugin storage. No config file
needs to be edited.

- **Search roots:** one folder or drive per line, plus a folder picker for quick
  additions. Environment variables such as `%USERPROFILE%` are expanded.
- **Include only:** optional OR rules. If any are set, a result matching at least
  one is kept.
- **Exclude:** rules are sent to `fd --exclude` so directories can be pruned
  before traversal; the plugin also checks them before rendering.
- **Rules:** `node_modules` matches a path segment, `.dll` matches an extension,
  and `*.generated.dart` is a glob.
- **Behavior:** literal/glob/regex queries, files/folders, hidden and ignored
  entries, symlink following, full-path matching, and a 20–500 result limit.

The initial excludes are `node_modules`, `.git`, `.dart_tool`, `.venv`, and
`__pycache__`. Remove any that you want searched.

## Notes

- Searches invoke `fd` directly without a shell. The three Windows installer
  buttons deliberately open `cmd.exe` for their fixed package-manager command.
- Paths are read using NUL-delimited output, so filenames containing newlines are
  handled safely.
- On Debian/Ubuntu the executable is often named `fdfind`; enter that name in
  the plugin's **fd executable** setting.
