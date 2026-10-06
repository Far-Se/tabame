# GIF Search for Tabame

A dependency-free Node.js 18+ port of the Raycast extension in
`otherSources/gif-search`. Type `gif happy dance` to search, or `gif` to browse.

## Pages and actions

- **Browse:** animated media gallery, provider selector, trending, and scroll-to-load pagination.
  Choose GIPHY GIFs, GIPHY Clips, Klipy, Finer Gifs Club, Favorites, or Recent GIFs.
  Finer Gifs Club searches quotes from The Office and has no trending feed.
  Blank provider searches include saved favorites and recent GIFs ahead of trending results.
- **Details:** GIF preview, dimensions, file size where available, creator, tags,
  source link, and episode metadata. Escape returns to browsing.
- **Settings:** visible Settings button for the default Enter action, page size,
  search/trending column counts, provider languages, download folder, and anonymous filenames.

Enter copies the selected GIF file by default. Ctrl+K also offers favorite toggling,
copy/paste link or Markdown, copy source link, open in browser, details, downloads,
and removal from recents. File copy uses Tabame's Windows file-drop clipboard so
the original animation is retained; paste it into a compatible app with Ctrl+V.
GIPHY Clips download/copy the MP4 when supplied by the provider and have video
playback in the gallery, with a GIF preview in details.

The host currently supports automatic paste for text only: GIF **files** are copied
for manual paste. The Raycast macOS-only square GIF conversion is not included.
Native file clipboard support on Linux/macOS is left unimplemented; link actions
and downloads remain available.

## Install

Copy this folder to `%LOCALAPPDATA%\Tabame\plugins\gif-search\`, ensure `node`
is on PATH, and reopen the launcher. No npm install or Flutter changes are needed.
The plugin is also registered in the repository's plugin gallery.

## Providers and storage

The default endpoints match the supplied Raycast source, including its public
GIPHY and Klipy proxy endpoints. Their availability outside Raycast is not
guaranteed. Errors remain visible with a Retry action; saved library entries stay
available if a provider is offline. Optionally copy `config.example.json` to
`config.json` to use compatible replacement endpoints (same query and response
schema). Reopen the launcher after editing it. No API keys are bundled.

Settings, favorites, and the last 100 used GIF records live in Tabame's per-plugin
storage. Favorites retain metadata for browsing without a provider lookup; remote
previews still need the network. Downloaded files are reused from `.cache`.
Older cache files are pruned beyond 100 files / 256 MB, with a 24-hour grace period
for clipboard payloads. Individual downloads are limited to 50 MB. Download names
are sanitized and collisions get a numeric suffix; existing files are never overwritten.
Anonymous names use a short provider-specific hash instead of the title.

Typing debounces network requests and cancels obsolete searches. Provider errors,
timeouts, malformed responses and download failures are surfaced in the launcher.
