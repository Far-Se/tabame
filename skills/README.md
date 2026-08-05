# Tabame QuickLaunch Skills by Workflow

These skills are derived from the full Tabame plugin authoring skill. Each
is standalone and should be supplied to an AI only when its workflow matches the
plugin being requested.

## 1. Search & Browse

Use `TABAME_SKILL_SEARCH_BROWSE.md` for:

- list/grid/table/tree/gallery result plugins;
- split preview and detail pages;
- live filtering, Tab autocomplete, paging;
- item and frame Ctrl+K actions;
- contacts, bookmarks, docs, packages, files, media, commands, API search.

## 2. Forms & Record Management

Use `TABAME_SKILL_FORMS_CRUD.md` for:

- list/table/kanban/calendar plus create/edit forms;
- task managers, issue trackers, settings and CRUD tools;
- validation, watched fields, conditional inputs;
- Ctrl+K, floating actions, confirmation and bulk selection;
- persistent normal state and secrets.

## 3. Live, Async & Connected

Use `TABAME_SKILL_LIVE_CONNECTED.md` for:

- dashboards, charts, timelines and logs;
- long-running/cancellable operations and diff results;
- streamed chat/detail output;
- OAuth, browser bridge, secure storage;
- background completion and Windows notifications;
- service monitors, deployments, AI assistants, sync/upload tools.

## 4. Browser Connector Extension

Use `TABAME_SKILL_BROWSER_EXTENSION.md` for:

- the Manifest V3 Chromium connector extension;
- WebSocket pairing, authentication, heartbeat, and reconnection;
- the browser bridge tab-method allowlist;
- trusted plugin-supplied `javascript.execute`;
- tab-change events, MV3 lifecycle, popup pairing, and connector security;
- browser-specific Firefox packaging.

This is an extension-authoring skill, not a launcher-plugin workflow skill. Use it
when changing the browser connector itself. A browser-backed launcher plugin will
usually use **Live, Async & Connected** instead.

## Choosing one

Choose the smallest skill that contains the plugin's main workflow. A plugin
that primarily searches records but has one tiny action parameter should use
Search & Browse. A plugin that creates/edits records should use Forms & Record
Management. A plugin centered on external live work, streaming, authentication,
or browser automation should use Live, Async & Connected.

For a plugin that genuinely spans two categories, provide the AI with both
relevant plugin skills rather than the original all-in-one skill. Provide the
Browser Connector Extension skill only when the connector extension itself is
being created or modified.
