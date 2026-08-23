# Search by Image

Tabame launcher plugin inspired by `otherSources/search-by-image`.

Keyword: `sbi`

## Windows capture flow

1. Type `sbi` in the Tabame launcher.
2. Press Enter on **Capture an area**.
3. The plugin opens the Windows screen snipping overlay through `ms-screenclip:`.
4. Select an area. The screenshot is read from the Windows image clipboard and saved as a temporary PNG.
5. Choose a reverse-image engine.

Google Images, Bing, Yandex, Pinterest, and Unsplash use upload flows based on the reference extension. The other engines open their upload page. The captured image remains in the clipboard, so engines that support paste can be completed with `Ctrl+V`; the saved PNG path is shown in the plugin and can be copied for a file picker.

The screenshot is uploaded only when an engine is selected. Uploads go directly from the plugin to the selected service; this plugin does not proxy or store them remotely.

## Configuration

`config.example.json` contains the full engine catalog. Copy it to `config.json` beside `main.py` to customize the enabled engine list, the capture timeout, or the Yandex host. If no `config.json` exists, all catalog entries are shown.

## Install

Copy this folder to:

```text
%localappdata%\Tabame\plugins\search-by-image\
```

Re-open the launcher after copying it. Tabame installs Pillow into the plugin's private dependency directory on first launch.
