# FFmpeg Video Converter for Tabame

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

- Available hardware presets depend on the encoders compiled into your FFmpeg build.
- Hardware encoder availability does not guarantee that the matching GPU/driver is usable;
  FFmpeg will show the underlying error on the result page if initialization fails.
- Closing the launcher while converting requests Tabame's maximum 300-second background
  grace. Very long conversions should be left open or run directly in a terminal.
- When overwrite is disabled, the plugin creates `name (1).ext`, `name (2).ext`, and so on.
