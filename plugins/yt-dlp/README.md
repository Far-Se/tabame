# yt-dlp Downloader for Tabame

A dependency-free Tabame launcher plugin for downloading video, audio, playlists,
and search results through the `yt-dlp` command-line tool.

## Features

- Home dashboard with tool status, quick-start actions, activity chart, and a recent-download timeline
- Video, audio-only, and custom format modes
- Quality/container controls, metadata, thumbnails, chapters, subtitles, SponsorBlock, playlists, cookies-from-browser, rate limiting, fragment concurrency, output templates, and raw yt-dlp arguments
- Full settings form with file/folder pickers and persistent Tabame storage
- On open, checks yt-dlp and silently runs `yt-dlp -U` in a supervised background task by default; this can be disabled in Settings
- Multi-source sequential queue with live operation progress, per-source progress bars, queue state, and a follow-mode diagnostic log
- Cancel support through the native operation view
- `Download and hide` keeps the supervised worker running after the launcher closes
- Native completion notifications, output open/copy actions, history table filtering/sorting, bulk history removal, and optional output deletion
- Clipboard paste, deep-linkable pages, breadcrumbs, back navigation, rich empty/error/success states, and stable page/item ids

## Page map

| Page | View | Purpose |
| --- | --- | --- |
| `ytdlp:home` | Dashboard | Status, quick start, seven-day activity, and recent downloads |
| `ytdlp:download` | Form | Source URLs, format, post-processing, and queue behavior |
| `ytdlp:operation` | Dashboard | Native operation progress, queue state, and live log |
| `ytdlp:result` | Detail | Durable success, error, or cancellation summary |
| `ytdlp:history` | Table | Filter, sort, inspect, and bulk-remove attempts |
| `ytdlp:item:<id>` | Detail | One attempt with open, copy, retry, and delete actions |
| `ytdlp:settings` | Form | Tool paths, startup update behavior, defaults, notifications, and auto-open behavior |

## Requirements

- Python 3 available as `python` on PATH
- `yt-dlp` available as `yt-dlp` on PATH, or selected in Settings
- FFmpeg is optional but required by yt-dlp for merging separate video/audio streams, audio extraction, embedding thumbnails, and some subtitle workflows

The plugin does not install Python packages. It starts yt-dlp without a shell, so
URLs and custom arguments are passed as separate process arguments.

On startup, the plugin first checks the configured executable with `yt-dlp --version`.
By default it then runs `yt-dlp -U` in the background; yt-dlp decides
whether a newer release is available. Disable **Check and update yt-dlp when
opened** in Settings if updates should be manual. If yt-dlp was installed with
pip, use pip's update flow when the self-update command reports that it cannot
modify the installation.

## Install

Copy the complete `yt-dlp` folder to:

```text
%LOCALAPPDATA%\Tabame\plugins\yt-dlp\
```

Reopen the Tabame launcher and type:

```text
ytdlp
```

Typing `ytdlp https://...` creates a quick-start download item. Plain text in
the launcher query is treated as a YouTube search and becomes `ytsearch1:...`.

## Background behavior

Every started job requests Tabame's maximum five-minute background grace. Use
the operation view to watch progress, or choose **Download and hide** to close
the launcher immediately. When the worker finishes after the launcher closes,
Tabame receives a native notification. Very long downloads should be left open
or run directly in a terminal because the host grace period is finite.

## Settings and history

Settings and history are stored through Tabame's per-plugin storage command, so
no credentials or machine-specific paths are shipped in this folder. The
browser-cookie option only asks yt-dlp to read the selected local browser
profile; use it only when that is appropriate for the source.
