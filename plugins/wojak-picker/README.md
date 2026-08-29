# Wojak Picker

Type `wojak` in the Tabame launcher to browse the bundled Wojak library.

This is the Tabame port of the MIT-licensed Raycast extension in
`otherSources/wojak-picker`.

- Search by name, filename, or category with fuzzy matching.
- Filter by category from the gallery toolbar.
- Press Enter to download and copy the selected image to the Windows clipboard.
- Use Ctrl+Shift+C to copy the source URL, Ctrl+O to open the image, or
  Ctrl+Shift+O to open its Wojak Land category page.
- Use Ctrl+K → Refresh Library to check the public manifest for new entries.

The plugin ships with `wojaks.json`, so browsing works without a network
connection. When a category or search page is shown, only the currently
visible thumbnails are downloaded in the background and cached under
`thumbnail-cache/<category>`; the full library is never prefetched. Downloaded
full-size images are cached in `image-cache` when copied.
Pillow is installed into the plugin's private dependency folder by Tabame and
is used to decode PNG, JPEG, and WebP images before placing them on the Windows
clipboard.
