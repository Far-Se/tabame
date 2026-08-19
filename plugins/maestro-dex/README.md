# Maestro DEX for Tabame

Search the Romanian dictionary database installed with Maestro DEX directly
from Tabame's launcher.

## Use

1. Open the launcher and type `mdex`.
2. If Maestro DEX is not detected automatically, choose **Set installation**.
3. Select the Maestro DEX installation folder (the folder containing `dex` and
   normally `MaestroDEX.exe`).
4. Type a Romanian lemma or inflected form, such as `casă`, `casa`, `merge`, or
   `merg`.

The result list includes an inline definition preview. Press **Enter** for the
complete entry, or use **Ctrl+K** to copy the lemma or all definitions. Settings
also lets you choose a result limit between 10 and 200.

## Pages

- **Search** (`maestro:search`, list + preview): typing searches lemmas and
  inflected forms; Enter opens the selected dictionary entry.
- **Entry** (`maestro:entry:<id>`, wide detail): shows every definition and its
  source, with copy actions and native back navigation.
- **Settings** (`maestro:settings`, form): uses Tabame's native folder picker,
  validates the database, and stores the installation path in plugin storage.

## Install

Copy this folder to:

`%LOCALAPPDATA%\Tabame\plugins\maestro-dex\`

Reopen the launcher after copying it; Tabame rescans plugins every time the
launcher opens. Python 3 must be available on `PATH`.

The database is opened read-only. The plugin has no third-party dependencies.
It is adapted from the MIT-licensed Raycast source in
`otherSources/maestro-dex`.
