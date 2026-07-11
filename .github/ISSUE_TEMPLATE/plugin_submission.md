---
name: Plugin submission
about: Submit a launcher plugin for review, so it can be added to the community gallery
title: '[Plugin] '
labels: plugin
assignees: ''

---

<!--
Thanks for contributing a Tabame launcher plugin!

A plugin is an external script (Python / Node / Bun) that Tabame runs when the
user types your keyword in the launcher. It talks newline-delimited JSON over
stdin/stdout — see plugins/TABAME_PLUGIN_SKILL.md for the full protocol.

I will manually review submissions before adding them to resources/plugins.json
so they appear in everyone's Plugin Gallery. Please fill in everything below and
paste your source files. If your plugin is already on GitHub, a link to the repo
is enough for the source sections.
-->

## Plugin details

- **Name:**
- **Keyword** (what the user types in the launcher, e.g. `weather`):
- **Short description:**
- **Runtime:** <!-- python / node / bun -->
- **Author** (name or GitHub handle):
- **Version:** <!-- e.g. 1.0.0 -->
- **Homepage / repo** (optional):
- **Icon** (a Material icon name like `clock`, or a `file://` / `https://` URL — optional):

## plugin.json

<!-- Paste the full contents of your plugin.json. Example:

{
  "name": "Timezone Converter",
  "keyword": "tz",
  "runtime": "python",
  "entry": "main.py",
  "icon": "clock",
  "description": "Convert times between timezones."
}
-->

```json

```

## Entry script (main.py / main.js)

<!-- Paste your main.py or main.js here (or link to it in your repo). -->

```

```

## Dependencies

<!--
Python: paste your requirements.txt (or the "pip" array from plugin.json), or write "none".
Node / Bun: paste your package.json (or write "none").
-->

```

```

## Checklist

- [ ] The plugin runs locally by dropping the folder into `%localappdata%\Tabame\plugins`.
- [ ] `plugin.json` has a unique `keyword` that doesn't collide with common commands.
- [ ] No secrets/API keys are hard-coded in the source (ask the user for them at runtime instead).
- [ ] Dependencies are declared (`pip` / `requirements.txt` for Python, `package.json` for Node/Bun).
- [ ] I'm okay with this plugin being distributed through Tabame's community gallery.

## Anything else

<!-- Notes for the reviewer: what it does, permissions it needs, screenshots, etc. -->
