# Audio Tag Transformer — Tabame plugin

Keyword: `atag`

## Installation

Copy the complete `audio-tag-transformer` folder to:

```text
%localappdata%\Tabame\plugins\audio-tag-transformer\
```

Tabame installs the declared Python dependency, `mutagen`, into the plugin's
local dependency directory on first launch. Reopen the launcher after copying
the folder and type `atag`.

## Workflow

1. On **Load**, drop or choose multiple `.mp3` and `.flac` files, or choose a
   folder. Enable recursive scanning when subfolders should be included.
2. **Files** deduplicates by canonical absolute path. Filter the table with the
   launcher query, open a row for details, exclude a file, remove it from the
   batch, or add more files later.
3. **Recipe** contains ordered rules. Add, edit, duplicate, delete, or move
   rules up and down. Each rule's output is available to the final template as
   `{1}`, `{2}`, and so on.
4. **Output settings** chooses the final template, target, whitespace cleanup,
   no-value policy, and filename collision behavior.
5. **Preview** is a mandatory dry run. It evaluates every included file from an
   immutable load-time snapshot. Open a row for all source values, rule outputs,
   the expanded template, and the exact old/new target value.
6. **Apply** is explicitly confirmation-gated, shows determinate progress, and
   can be cancelled between files. The result page reports changed, skipped,
   failed, and cancelled files individually.

Named recipes are saved through Tabame's non-secret `storage` command. Only the
recipe rules and output settings are saved; loaded file paths are not persisted.

## Sources

Rules can read these case-insensitive source fields:

`{FileName}`, `{FileStem}`, `{Extension}`, `{FullPath}`, `{Directory}`,
`{ParentFolder}`, `{FileSize}`, `{Created}`, `{Modified}`, `{Title}`,
`{Artist}`, `{Album}`, `{AlbumArtist}`, `{TrackNumber}`, `{DiscNumber}`,
`{Date}`, `{Genre}`, `{Composer}`, and `{Comment}`.

`{Extension}` is the lowercase extension without its dot (`mp3` or `flac`).
`{ParentFolder}` is the containing folder's name. Filesystem timestamps are
local ISO-style timestamps, and file size is bytes. Multiple audio-tag values
are joined with `; ` for transformations.

MP3 values use ID3 frames. FLAC values use Vorbis comments. Writing an audio
tag changes only the selected target and preserves unrelated tags, embedded
cover art, and other metadata.

## Regex and replacement syntax

Patterns may be plain Python-compatible regexes or JavaScript-style notation:

```text
/ft\.(.*?)\W/i
(\w+)\s+(\w+)
```

The supported flags are `i` (case-insensitive), `m` (multiline), and `s`
(dot matches newlines). Rules run in order and support:

- **Extract** — find the first match and return only the expanded replacement.
- **Replace first** — replace the first match in the complete source string.
- **Replace all** — replace every match in the complete source string.

Replacement expressions use familiar syntax: `$0` is the complete match,
`$1`–`$99` are numbered capture groups, `$<name>` is a named capture group,
and `$$` is a literal dollar sign. Invalid patterns, flags, capture references,
and replacements are shown as validation errors in the rule form.

Named captures may use either Python's `(?P<name>...)` spelling or the
JavaScript-style `(?<name>...)` spelling.

`$1` belongs to the current rule's regex. `{1}` is the final output of rule 1
and is used only in the final template. Direct fields such as `{Album}` and
`{Artist}` may be combined with rule tokens and literal text. Placeholder names
are case-insensitive. Use `{{` and `}}` for literal braces.

For example:

```text
Rule 1: source FileName, pattern /ft\.(.*?)\W/i, replacement $1
Rule 2: source Title,    pattern /(\w+)\s+(\w+)/, replacement $1 $2
Template: {1} {2} {Album}
```

## Filename safety

Filename output is treated as a new file stem and keeps the original `.mp3` or
`.flac` extension. Windows-invalid characters are replaced with `_`; reserved
names such as `CON`, `NUL`, `COM1`, and `LPT1` are rejected, as are trailing
dots and spaces. Files never move to another directory.

The preview detects duplicate proposed names and existing-file collisions. You
can skip a collision or append a numeric suffix such as ` (1)`. Collision
checks run again immediately before each rename, and no unrelated file is ever
overwritten.
