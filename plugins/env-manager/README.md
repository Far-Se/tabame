# Environment Variables

Manage user and system environment variables from the Tabame launcher. The PATH
editor supports adding, editing, removing, reordering, duplicate cleanup, and
removing missing entries. System changes use a Windows administrator prompt.

## Install

Copy this folder to:

```text
%localappdata%\Tabame\plugins\env-manager\
```

Reopen the launcher and type `env`.

## Pages and shortcuts

- `env` opens the user and system scopes and the current process PATH.
- `env user` or `env system` opens that registry scope.
- `env path`, `env user path`, or `env system path` opens a PATH editor.
- Enter a variable to inspect it. Use its actions to edit, copy, or remove it.
- On a PATH entry, use its actions to edit, move it up/down, open its folder,
  copy it, or remove it. `Alt+Up` and `Alt+Down` reorder the selected entry.
- The PATH page can clean duplicates and remove entries that are missing or are
  files rather than directories. Unresolved variables and paths that Windows
  cannot check are left in place.
- Scope pages can copy variables as JSON or as a `.reg` export. Exports include
  every stored value, including secrets.

After a write, the plugin broadcasts the Windows environment-change
notification. Existing processes keep their current environment; newly launched
processes read the updated values. The effective PATH page shows the environment
inherited by Tabame itself.

On Linux and macOS the plugin displays the same navigation with sample data.
Registry-backed edits are Windows-only for now.
