# Quicklinks

Quicklinks save websites, search URLs, files, folders, and app deeplinks as named launcher results. This feature follows the personal shortcut workflow described in the [Raycast Quicklinks manual](https://manual.raycast.com/quicklinks).

## Getting started

Search **Create Quicklink** in the launcher. Enter a name and destination, then save with **Ctrl+Enter**. A valid URL or path on the clipboard prefills a new editor without replacing anything you type.

Find your link by name in normal launcher search, or type **ql** to browse quicklinks and their commands. **Search Quicklinks** opens the manager, also available at **Settings → Quickmenu → Launcher → Quicklinks → Manage**.

**Add from Library** offers Google, DuckDuckGo, YouTube, Wikipedia, GitHub, Stack Overflow, and Google Translate templates. Each opens in the editor before being saved.

An optional alias makes searches faster. For example:

```text
Name: Search Google
Alias: google
Link: https://www.google.com/search?q={argument name="Query"}
```

Type `google flutter widgets` and press Enter to search. Text after an alias or full quicklink name fills the first argument; an input form asks for any remaining required arguments. Opening the result without text asks for its inputs. Defaults can run immediately.

For a project folder, use a path such as `C:\Projects\My App`, optionally choosing your editor's executable under **Open With**. `~/Downloads` resolves under your Windows user folder. `file:` URLs and app deeplinks such as `spotify://…` are also supported. The system default application is used when Open With is empty.

## Managing links

Use **Ctrl+K** on a quicklink for Open, Open With, Edit, Duplicate, Pin/Unpin, Copy Name, Copy Link, Show/Hide in Root Search, and Delete. Deletion asks for confirmation. **Ctrl+C** on a launcher quicklink copies its original link template.

Tags are comma-separated in the editor. Search with `#work`, or select a tag in the manager. Pinned links sort first within the library. Hidden links remain available through `ql`, the manager, and their exact alias.

In the manager, use arrow keys and Enter from the search field, **Ctrl+F** for search, **Ctrl+P** for the tag selector, **Ctrl+N** to create, and **Ctrl+K** for actions.

Tabame's existing **Start Launcher with Prefix** hotkey action can use `ql ` or a quicklink alias as its pretext. This opens the relevant launcher results; Enter opens the link.

## Dynamic placeholders

The syntax is based on [Raycast's dynamic placeholders](https://manual.raycast.com/dynamic-placeholders).

| Syntax | Behavior |
| --- | --- |
| `{argument}` | A required input; each unnamed occurrence gets its own field |
| `{argument name="Query"}` or `{Query}` | A named input, shared across repeated occurrences |
| `{argument name="Language" default="en"}` | An optional input with a default |
| `{argument name="Sort" options="newest,oldest"}` | A choice input |
| `{clipboard}` | Current clipboard text |
| `{date}`, `{time}`, `{datetime}`, `{day}` | Local date, time, timestamp, or weekday |
| `{date format="yyyy-MM-dd" offset="+1M -2d"}` | Custom date format and calendar offsets |
| `{uuid}` | A new UUID when the quicklink runs |

Up to three distinct arguments are supported. Repeated names can define their defaults and options once; conflicting definitions are rejected. Date offsets accept minutes (`m`), hours (`h`), days (`d`), months (`M`), and years (`y`), with month/year changes clamped to the destination month's last day.

Modifiers can be chained with `|`: `trim`, `uppercase`, `lowercase`, `percent-encode`, `json-stringify`, and `raw`. Quoted attribute values can contain pipes and escaped quotes.

Inserted URL values are percent-encoded; local paths retain spaces and separators. `{clipboard | raw}` can insert an existing URL unchanged. Values are never interpreted again as template code or shell commands. The input form previews the resolved destination before opening.

## Import, export, and storage

Use **Import Quicklinks** or **Export Quicklinks**, also available from the manager's overflow menu. JSON files contain an array:

```json
[
  {
    "name": "Search DuckDuckGo",
    "link": "https://duckduckgo.com/?q={argument}",
    "alias": "ddg",
    "tags": ["research"]
  }
]
```

Raycast's `name`, `link`, `iconName`, and `openWith` fields are accepted. Tabame additionally preserves IDs, aliases, tags, pinning, and root-search visibility on export; imports assign fresh IDs. Unsupported icon names use a link icon. Applications imported from macOS may need a Windows executable selected in Open With.

An import is validated before any changes are written. Matching names and links are skipped as duplicates; conflicting aliases are cleared on the imported entries. Existing quicklinks remain intact.

The library lives in `quicklinks.json` alongside Tabame's settings (in the debug settings directory for debug builds). Writes use a separate process lock and replacement file, so launcher and settings windows merge changes into the latest collection.

Opening destinations currently supports Windows; Linux and macOS have explicit placeholders. Cloud/team sharing, direct per-link global execution hotkeys, selected-text capture, active-browser autofill, favicon discovery, existing-tab reuse, and clipboard-history/calculator/snippet placeholders are not implemented.
