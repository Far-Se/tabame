# Image Converter — Tabame plugin

Keyword: `img`

## Install
Copy this whole folder to:
```
%localappdata%\Tabame\plugins\img-converter\
```
Reopen the Tabame launcher. On first run it auto-installs Pillow (shows an
"Installing dependencies…" spinner once).

## Use
- `img` — shows recent conversions and quick actions (pick file, pick folder,
  paste path from clipboard, settings).
- `img C:\path\to\photo.png` — shows the file; Enter to choose an output
  format (PNG, JPEG, WebP, BMP, GIF, TIFF, ICO, PDF).
- `img C:\some\folder` — browse a folder; Enter on a subfolder to go deeper,
  Enter on an image to convert it, or Ctrl+K → "Batch convert all images in
  this folder" to convert everything at once.
- Shorthand: `img photo.png to webp` converts instantly with your default
  quality setting, no menus.
- After picking a format you get an options screen: resize (%, or custom
  width/height with aspect-ratio lock), rotate, flip, grayscale, plus
  format-specific options (JPEG/WebP quality, PNG compression, ICO sizes,
  TIFF compression, combine-to-multi-page-PDF for batches), output folder,
  overwrite, filename suffix.
- Batch jobs run in the background — the launcher hides and you get a
  Windows notification when it's done.
- Result screen shows before/after size and dimensions, with actions to open
  the file, reveal it in Explorer, copy its path, delete the original, or
  convert another.

## Notes
- Animated GIFs are converted from their first frame only.
- HEIC/HEIF is not supported out of the box (would need the optional
  `pillow-heif` package added to `plugin.json`'s `pip` list).
- Set `"dev": true` in `plugin.json` while tweaking the script for hot reload
  and an on-screen debug console; set it back to `false` before sharing.
