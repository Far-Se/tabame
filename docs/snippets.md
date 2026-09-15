# Snippets

Open **Text Snippets** from the quick menu or launcher quick actions. The library searches names, keywords, content, and tags. Use the arrow keys in search and Enter to paste the highlighted result; use the row's Copy button to stay in Tabame.

## Library and editor

- Name snippets independently of their optional expansion keywords.
- Organize with multiple tags and pinned items.
- Copy expanded text, paste into the previous application, or copy the original template.
- Edit, duplicate, pause keyword expansion, and delete with an Undo action.
- Create from the clipboard, including formatted text, or start with one of the built-in templates.
- Insert placeholders from the editor menu or the suggestions after typing `{`.
- See the rendered text and cursor position in the live preview.
- Fill in named inputs using text fields or choices, with optional defaults and repeated values.

Shortcuts: **Ctrl+N** creates a snippet, **Ctrl+F** focuses library search, **Ctrl+Enter** saves the editor or pastes from the input form, and **Escape** returns to the library.

Existing Tabame trigger/text entries keep their text literal and their original suffix matching behavior. Enable **Dynamic placeholders** on an older snippet to use the template syntax. Newly created templates have this enabled; clipboard captures start with literal text.

Clipboard formatting is retained for static snippets. Editing their text clears the captured HTML. Dynamic templates paste rendered plain text. The preview shows the plain-text representation.

## Templates

```text
Hi {argument name="customer"},

Your next update is scheduled for {date offset="+2d" format="EEEE, MMM d"}.

{cursor}
```

| Placeholder | Behavior |
| --- | --- |
| `{clipboard}` | Current clipboard text |
| `{clipboard offset=1}` | Previous clipboard item; requires Clipboard History |
| `{date}`, `{time}`, `{datetime}`, `{day}` | Current local date, time, combined timestamp, or weekday |
| `{date format="yyyy-MM-dd"}` | Custom date format |
| `{date locale="fr-FR"}` | Localized date; do not combine locale and format |
| `{time locale="en-US-u-hc-h23"}` | 24-hour time |
| `{date offset="+1M -2d"}` | Relative date with calendar-aware month/year adjustment |
| `{uuid}` | New UUID v4 on each use |
| `{cursor}` | Caret position after pasting |
| `{argument name="customer"}` | Required named input; `{customer}` is a shorthand |
| `{argument name="status" default="pending"}` | Optional input with a default |
| `{argument name="status" options="pending,ready"}` | Choice input |
| `{snippet name="Signature"}` | Insert another snippet by its exact name |
| `{calculator expression="144 / 12"}` | Evaluate an expression; without the attribute, use clipboard text |
| `{shell code="Get-Date -Format yyyy-MM-dd"}` | PowerShell output, when enabled for that snippet |

Modifiers are separated with `|`: `uppercase`, `lowercase`, `trim`, `percent-encode`, `json-stringify`, and `raw`. They can be chained. Values inserted from inputs, clipboard, and shell output are not interpreted again as template code.

Offsets support minutes (`m`), hours (`h`), days (`d`), weeks (`w`), months (`M`), and years (`y`). Date formats use Dart `intl`/ICU patterns; not every Qt-specific date token is interchangeable. The hour-cycle locale extension supports 24-hour formatting; other Unicode locale extensions are not implemented.

Repeated input names share one value. There is no three-input cap. Defaults and choices may be specified on the first occurrence; conflicting definitions are reported. Snippet references can nest up to eight levels, with cycle and missing-reference checks. Only one cursor marker is allowed across the expanded template. Escape a literal brace with `\{`, or disable **Dynamic placeholders** for code that should remain literal.

Shell previews never run commands. Actual use requires **Allow shell commands** on each snippet containing a shell placeholder. Up to 16 shell placeholders run concurrently, each with a two-second execution budget. Errors stop the expansion; the keyword stays in place. Imported snippets always start with shell execution disabled.

## Windows expansion

Automatic expansion starts disabled to retain the existing manual hotkey workflow. Enable it in the library footer or **Expansion settings**.

- Expand immediately, or after a space/punctuation delimiter, keeping or discarding that delimiter.
- Choose case matching and whole-keyword behavior per snippet.
- Restrict a keyword to selected executables, exclude selected executables, or require a matching window-title substring.
- Set global application exclusions, expansion delay, paste delay, clipboard restoration, and a completion sound.
- The existing **Insert snippet** hotkey still expands a typed keyword even with automatic expansion off.

Keywords allow up to 128 UTF-16 code units and cannot contain whitespace. Snippet text allows 65,536 code units; expanded output is capped at 256K. Enter and Tab remain navigation keys. The longest applicable keyword wins. Conflicting keywords are reported when saving or importing; identical keywords are allowed in disjoint application allowlists.

Required inputs are filled in from the library. Keyword expansion does not erase a trigger or insert blank input values when required inputs are missing.

Pasting uses the clipboard, retaining line breaks. The previous clipboard formats are restored unless another copy occurred in the meantime. Temporary expansion clipboard updates are excluded from Tabame's clipboard history. Restoration snapshots are bounded to 32 MB and 64 formats; if a snapshot cannot be captured, insertion is cancelled before deleting the keyword. Turning restoration off avoids the snapshot requirement.

**Escape** restores the keyword immediately after a plain-text, single-line expansion of up to 512 characters. Further input, mouse movement, or a focus change cancels this undo opportunity. Larger or formatted pastes use the target application's normal undo behavior.

The matcher checks the foreground window and focused control, cancels stale requests after input/focus changes, and ignores injected keystrokes. Native password edit controls and configured excluded applications do not receive expansions. Cursor positioning and input delivery still depend on the target editor; IME composition and unusual editors need application-specific verification.

## Import and export

The library menu imports JSON with a review before changes are saved. Accepted inputs include:

- Raycast-style arrays with `name`, `text`, and optional `keyword`.
- Objects with a `snippets` array.
- Tabame's old arrays of JSON-encoded strings and its new versioned library.
- `title`/`content` aliases, tags, pins, application rules, and static HTML when present.

Invalid entries, duplicate names, conflicting keywords, and broken references are shown as skipped. Existing data is retained. References to a rejected conflicting import are not silently redirected to unrelated existing content. Exports are JSON arrays with Raycast's core fields plus Tabame metadata.

## Research and scope

The implementation was informed by the documented library, template, and expansion features in the [Raycast Snippets manual](https://manual.raycast.com/snippets), [Raycast dynamic placeholder reference](https://manual.raycast.com/dynamic-placeholders), and [Vicinae Snippets documentation](https://github.com/vicinaehq/docs/blob/main/src/app/snippets/page.mdx).

| Area | Tabame implementation |
| --- | --- |
| Library organization | Search, tags, pins, duplicate, pause, delete/undo |
| Template authoring | Placeholder insertion, preview, named inputs, choices, defaults |
| Composition | Nested references with validation; no three-input limit |
| Dynamic values | Clipboard/history, dates/offsets/locales, UUID, calculator, shell, modifiers |
| Expansion | Windows hotkey and automatic modes, scoped app rules, delays, cursor, undo, sound |
| Transfer | Reviewed JSON import, export, legacy migration, static rich-text capture |

This is a local snippet library. Cloud/team sharing, proprietary non-JSON import formats, and dynamic rich-text authoring are not included. macOS system-snippet overrides are not applicable to this Windows implementation. Linux/macOS native expansion and shell execution retain explicit multiplatform TODO stubs; the library can still use the platform clipboard service.

Validation completed: `dart format` and `dart analyze` on the four changed Dart files, with no analyzer issues; the native plugin's MSBuild `ClCompile` target also passed. No desktop app was launched and no tests were run, per the repository instructions. Behavior in individual Windows editors remains unverified.

The source changes require an updated Windows native plugin alongside the Dart changes; hot reload alone cannot add the native methods.
