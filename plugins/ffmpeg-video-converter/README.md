# FFmpeg Video Converter for Tabame

## Built-in Quick Action

The converter is also available as **FFmpeg Video Converter** (`VideoConverterButton`)
in Tabame's Quick Actions. Add it to the quick menu bar from Quick Actions settings.
The built-in panel calls FFmpeg directly and does not require Python or this plugin.
It includes the same format presets and encoding controls, saves options in Tabame
settings, and keeps the active job and latest result when the panel is closed and
reopened while Tabame remains running. Hiding QuickMenu does not interrupt the job.
A desktop notification appears after a successful conversion; click it to open the
completed file. Tabame must stay running until conversion finishes. Plugin settings
are separate.

The **Trim & crop** card adds optional start/end times (seconds, `MM:SS`, or
`HH:MM:SS`, including fractions) and crop margins in pixels for each edge. End
times refer to the original media; a blank end keeps the rest of the file. Crop
margins apply to the displayed orientation before resizing and require ffprobe
to validate the dimensions. Video crops must leave even width and height.
Trimming also works for audio extraction and MKV remux; remux cuts are limited
to nearby keyframes. Cropping is available for video encoding and GIF presets.
Edit controls are saved with the other options and can be cleared with **Reset edits**.

FFmpeg must be on `PATH`; ffprobe enables duration-based progress and frame-rate
limits. Without usable ffprobe metadata, frame-rate changes are skipped. Failed or
cancelled jobs remove their temporary output without replacing existing files.
Native conversion is currently implemented for Windows.

## Launcher plugin

A form-based Tabame plugin for compressing and converting video, extracting audio,
creating GIFs, and remuxing media without re-encoding.

## Features

- MP4 H.264 and H.265 software encoding
- Hardware presets when FFmpeg exposes NVIDIA NVENC, Intel Quick Sync, or AMD AMF
- WebM VP9, MOV H.264, MP3, M4A, GIF, and MKV remuxing
- Quality, speed, maximum resolution, maximum frame rate, and audio bitrate controls
- No-upscale behavior for resolution and frame rate
- Live FFmpeg progress, elapsed time, encoding speed, and output size
- Native cancellation with partial-output cleanup
- Result page with before/after sizes, open/copy/delete actions, and error diagnostics
- Optional automatic opening of the completed file
- Automatically saves every form field as you edit and restores it when reopened,
  including file paths, encoding options, and output behavior (even without starting a conversion)
- Up to 5 minutes of background grace after the launcher closes

## Requirements

- Tabame with plugin protocol 11 support
- Python 3 available as `python` on `PATH`
- `ffmpeg` and ideally `ffprobe` on `PATH`

Verify in a fresh terminal:

```powershell
python --version
ffmpeg -version
ffprobe -version
```

## Install

Copy the entire `ffmpeg-video-converter` folder to:

```text
%LOCALAPPDATA%\Tabame\plugins\ffmpeg-video-converter\
```

Reopen the Tabame launcher and type:

```text
ffmpeg
```

Tabame rescans the plugins directory whenever the launcher opens.

## Notes

- Settings use Tabame's per-plugin storage (`.tabame-store.json` in the installed plugin folder).
- If a saved encoder is no longer available, the converter selects an available default.
- Available hardware presets depend on the encoders compiled into your FFmpeg build.
- Hardware encoder availability does not guarantee that the matching GPU/driver is usable;
  FFmpeg will show the underlying error on the result page if initialization fails.
- Closing the launcher while converting requests Tabame's maximum 300-second background
  grace. Very long conversions should be left open or run directly in a terminal.
- When overwrite is disabled, the plugin creates `name (1).ext`, `name (2).ext`, and so on.
