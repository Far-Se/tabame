from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from collections import deque
from pathlib import Path
from typing import Any

PLUGIN_NAME = "FFmpeg Video Converter"
BACKGROUND_GRACE_SECONDS = 300

SEND_LOCK = threading.Lock()
JOB_LOCK = threading.Lock()
UI_CLOSED = False
CURRENT_JOB: dict[str, Any] | None = None
LAST_RESULT: dict[str, Any] | None = None
LAST_FORM_VALUES: dict[str, Any] = {}
FFMPEG_PATH: str | None = None
FFPROBE_PATH: str | None = None
AVAILABLE_ENCODERS: set[str] = set()


def send(payload: dict[str, Any]) -> None:
    """Write one protocol message to stdout."""
    try:
        line = json.dumps(payload, ensure_ascii=False)
        with SEND_LOCK:
            sys.stdout.write(line + "\n")
            sys.stdout.flush()
    except (BrokenPipeError, OSError):
        pass


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def command(name: str, **fields: Any) -> None:
    send({"type": "command", "command": name, **fields})


def page(page_id: str, title: str, history: str = "none") -> dict[str, Any]:
    return {
        "id": page_id,
        "title": title,
        "history": history,
        "preserveState": True,
    }


def detect_tools() -> None:
    global FFMPEG_PATH, FFPROBE_PATH, AVAILABLE_ENCODERS
    if FFMPEG_PATH is not None:
        return

    FFMPEG_PATH = shutil.which("ffmpeg")
    FFPROBE_PATH = shutil.which("ffprobe")
    if not FFMPEG_PATH:
        return

    try:
        proc = subprocess.run(
            [FFMPEG_PATH, "-hide_banner", "-encoders"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=8,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
        )
        text = proc.stdout + "\n" + proc.stderr
        for name in (
            "libx264",
            "libx265",
            "libvpx-vp9",
            "h264_nvenc",
            "hevc_nvenc",
            "h264_qsv",
            "hevc_qsv",
            "h264_amf",
            "hevc_amf",
            "libmp3lame",
            "mp3",
            "aac",
            "libopus",
            "libvorbis",
            "gif",
        ):
            if re.search(rf"\b{re.escape(name)}\b", text):
                AVAILABLE_ENCODERS.add(name)
    except Exception as exc:
        log(f"Could not inspect FFmpeg encoders: {exc}")


def preset_options() -> list[dict[str, str]]:
    options: list[dict[str, str]] = []
    if "libx264" in AVAILABLE_ENCODERS:
        options.append({"value": "mp4-h264", "label": "MP4 · H.264 (compatible)"})
        options.append({"value": "mov-h264", "label": "MOV · H.264"})
    if "libx265" in AVAILABLE_ENCODERS:
        options.append({"value": "mp4-h265", "label": "MP4 · H.265 (smaller)"})
    if "libvpx-vp9" in AVAILABLE_ENCODERS:
        options.append({"value": "webm-vp9", "label": "WebM · VP9"})

    hardware = [
        ("h264_nvenc", "mp4-h264-nvenc", "MP4 · H.264 · NVIDIA NVENC"),
        ("hevc_nvenc", "mp4-h265-nvenc", "MP4 · H.265 · NVIDIA NVENC"),
        ("h264_qsv", "mp4-h264-qsv", "MP4 · H.264 · Intel Quick Sync"),
        ("hevc_qsv", "mp4-h265-qsv", "MP4 · H.265 · Intel Quick Sync"),
        ("h264_amf", "mp4-h264-amf", "MP4 · H.264 · AMD AMF"),
        ("hevc_amf", "mp4-h265-amf", "MP4 · H.265 · AMD AMF"),
    ]
    for encoder, value, label in hardware:
        if encoder in AVAILABLE_ENCODERS:
            options.append({"value": value, "label": label})

    if "libmp3lame" in AVAILABLE_ENCODERS or "mp3" in AVAILABLE_ENCODERS:
        options.append({"value": "audio-mp3", "label": "MP3 · Extract audio"})
    if "aac" in AVAILABLE_ENCODERS:
        options.append({"value": "audio-m4a", "label": "M4A · Extract audio"})
    if "gif" in AVAILABLE_ENCODERS:
        options.append({"value": "gif", "label": "GIF · Animated image"})
    options.append({"value": "mkv-copy", "label": "MKV · Remux without re-encoding"})
    return options


def default_preset() -> str:
    opts = preset_options()
    return str(opts[0]["value"]) if opts else "audio-mp3"


def render_missing_ffmpeg(rev: int = 0) -> None:
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "page": page("ffmpeg:missing", "FFmpeg not found"),
            "placeholder": "Install FFmpeg, then reopen Tabame…",
            "detail": {
                "wide": True,
                "markdown": (
                    "# FFmpeg was not found\n\n"
                    "Install **FFmpeg** and make sure `ffmpeg` and `ffprobe` are available on "
                    "the system `PATH`, then reopen the Tabame launcher.\n\n"
                    "On Windows, verify from a new terminal:\n\n"
                    "```powershell\nffmpeg -version\nffprobe -version\n```"
                ),
            },
            "actions": [
                {"id": "retry-tools", "title": "Check again", "icon": "refresh"},
            ],
            "floatingAction": {"id": "retry-tools", "title": "Check again", "icon": "refresh"},
        }
    )


def render_form(rev: int = 0, error: str | None = None, history: str = "none") -> None:
    detect_tools()
    if not FFMPEG_PATH:
        render_missing_ffmpeg(rev)
        return

    values = {
        "input": "",
        "output_dir": "",
        "output_name": "",
        "preset": default_preset(),
        "quality": "balanced",
        "speed": "balanced",
        "resolution": "keep",
        "fps": "keep",
        "audio_bitrate": "160k",
        "remove_audio": False,
        "overwrite": False,
        "open_when_done": False,
        **LAST_FORM_VALUES,
    }

    video_presets = [
        "mp4-h264",
        "mov-h264",
        "mp4-h265",
        "webm-vp9",
        "mp4-h264-nvenc",
        "mp4-h265-nvenc",
        "mp4-h264-qsv",
        "mp4-h265-qsv",
        "mp4-h264-amf",
        "mp4-h265-amf",
    ]
    quality_presets = video_presets + ["gif"]
    audio_presets = video_presets + ["audio-mp3", "audio-m4a"]

    form: dict[str, Any] = {
        "title": "Compress or convert media",
        "submitLabel": "Start conversion",
        "sections": [
            {
                "id": "files",
                "title": "Files",
                "description": "Choose the source and output destination.",
            },
            {
                "id": "encoding",
                "title": "Encoding",
                "description": "Presets are limited to encoders available in this FFmpeg build.",
            },
            {
                "id": "advanced",
                "title": "Advanced",
                "description": "Optional size, frame-rate, and output behavior.",
                "collapsible": True,
            },
        ],
        "fields": [
            {
                "id": "input",
                "type": "filepicker",
                "label": "Input media",
                "required": True,
                "value": values["input"],
                "section": "files",
            },
            {
                "id": "output_dir",
                "type": "folderpicker",
                "label": "Output folder",
                "description": "Leave empty to use the input file's folder.",
                "value": values["output_dir"],
                "section": "files",
            },
            {
                "id": "output_name",
                "type": "text",
                "label": "Output name",
                "placeholder": "Automatic name",
                "description": "File name without an extension. Leave empty for an automatic suffix.",
                "value": values["output_name"],
                "section": "files",
                "pattern": r"^[^<>:\"/\\|?*]*$",
                "validationMessage": "The file name contains an invalid Windows character.",
            },
            {
                "id": "preset",
                "type": "dropdown",
                "label": "Format and codec",
                "required": True,
                "value": values["preset"],
                "options": preset_options(),
                "section": "encoding",
            },
            {
                "id": "quality",
                "type": "dropdown",
                "label": "Quality / file size",
                "value": values["quality"],
                "options": [
                    {"value": "best", "label": "Best quality · largest file"},
                    {"value": "high", "label": "High quality"},
                    {"value": "balanced", "label": "Balanced"},
                    {"value": "small", "label": "Small file"},
                    {"value": "smallest", "label": "Smallest file · lower quality"},
                ],
                "visibleWhen": {"field": "preset", "in": quality_presets},
                "section": "encoding",
            },
            {
                "id": "speed",
                "type": "dropdown",
                "label": "Encoding speed",
                "description": "Slower encoding usually produces a smaller file at the same quality.",
                "value": values["speed"],
                "options": [
                    {"value": "slow", "label": "Slow · better compression"},
                    {"value": "balanced", "label": "Balanced"},
                    {"value": "fast", "label": "Fast"},
                ],
                "visibleWhen": {"field": "preset", "in": video_presets},
                "section": "encoding",
            },
            {
                "id": "resolution",
                "type": "dropdown",
                "label": "Maximum resolution",
                "description": "Smaller sources are never upscaled.",
                "value": values["resolution"],
                "options": [
                    {"value": "keep", "label": "Keep original"},
                    {"value": "2160", "label": "2160p · 4K"},
                    {"value": "1440", "label": "1440p"},
                    {"value": "1080", "label": "1080p"},
                    {"value": "720", "label": "720p"},
                    {"value": "480", "label": "480p"},
                ],
                "visibleWhen": {"field": "preset", "in": quality_presets},
                "section": "advanced",
            },
            {
                "id": "fps",
                "type": "dropdown",
                "label": "Maximum frame rate",
                "description": "Lower frame-rate sources are not increased.",
                "value": values["fps"],
                "options": [
                    {"value": "keep", "label": "Keep original"},
                    {"value": "60", "label": "60 fps"},
                    {"value": "30", "label": "30 fps"},
                    {"value": "24", "label": "24 fps"},
                    {"value": "15", "label": "15 fps"},
                ],
                "visibleWhen": {"field": "preset", "in": quality_presets},
                "section": "advanced",
            },
            {
                "id": "audio_bitrate",
                "type": "dropdown",
                "label": "Audio bitrate",
                "value": values["audio_bitrate"],
                "options": ["320k", "256k", "192k", "160k", "128k", "96k"],
                "visibleWhen": {"field": "preset", "in": audio_presets},
                "section": "advanced",
            },
            {
                "id": "remove_audio",
                "type": "checkbox",
                "label": "Remove audio",
                "value": values["remove_audio"],
                "visibleWhen": {"field": "preset", "in": video_presets},
                "section": "advanced",
            },
            {
                "id": "overwrite",
                "type": "checkbox",
                "label": "Overwrite an existing output file",
                "description": "When disabled, a numbered file name is created instead.",
                "value": values["overwrite"],
                "section": "advanced",
            },
            {
                "id": "open_when_done",
                "type": "checkbox",
                "label": "Open the output file when finished",
                "value": values["open_when_done"],
                "section": "advanced",
            },
        ],
    }
    if error:
        form["error"] = error

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "page": page("ffmpeg:convert", "Convert", history),
            "elementId": "conversion-form",
            "placeholder": "Configure the conversion below…",
            "form": form,
            "actions": [
                {"id": "check-tools", "title": "Show FFmpeg details", "icon": "info"},
            ],
        }
    )


def parse_fraction(value: str | None) -> float | None:
    if not value or value in {"0/0", "N/A"}:
        return None
    try:
        if "/" in value:
            numerator, denominator = value.split("/", 1)
            denominator_f = float(denominator)
            return float(numerator) / denominator_f if denominator_f else None
        return float(value)
    except (TypeError, ValueError, ZeroDivisionError):
        return None


def probe_media(path: Path) -> dict[str, Any]:
    info: dict[str, Any] = {
        "duration": None,
        "size": path.stat().st_size if path.exists() else None,
        "width": None,
        "height": None,
        "fps": None,
        "video_codec": None,
        "audio_codec": None,
    }
    if not FFPROBE_PATH:
        return info

    try:
        proc = subprocess.run(
            [
                FFPROBE_PATH,
                "-v",
                "error",
                "-show_entries",
                "format=duration,size:stream=codec_type,codec_name,width,height,avg_frame_rate",
                "-of",
                "json",
                str(path),
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=20,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
        )
        data = json.loads(proc.stdout or "{}")
        fmt = data.get("format") or {}
        try:
            info["duration"] = float(fmt.get("duration"))
        except (TypeError, ValueError):
            pass
        try:
            info["size"] = int(fmt.get("size"))
        except (TypeError, ValueError):
            pass

        for stream in data.get("streams") or []:
            kind = stream.get("codec_type")
            if kind == "video" and info["video_codec"] is None:
                info["video_codec"] = stream.get("codec_name")
                info["width"] = stream.get("width")
                info["height"] = stream.get("height")
                info["fps"] = parse_fraction(stream.get("avg_frame_rate"))
            elif kind == "audio" and info["audio_codec"] is None:
                info["audio_codec"] = stream.get("codec_name")
    except Exception as exc:
        log(f"ffprobe failed for {path}: {exc}")
    return info


def human_size(value: int | float | None) -> str:
    if value is None:
        return "Unknown"
    size = float(value)
    units = ["B", "KB", "MB", "GB", "TB"]
    for unit in units:
        if abs(size) < 1024 or unit == units[-1]:
            return f"{size:.0f} {unit}" if unit == "B" else f"{size:.2f} {unit}"
        size /= 1024
    return f"{size:.2f} TB"


def human_duration(seconds: float | None) -> str:
    if seconds is None:
        return "Unknown"
    total = max(0, int(round(seconds)))
    hours, rem = divmod(total, 3600)
    minutes, secs = divmod(rem, 60)
    if hours:
        return f"{hours}:{minutes:02d}:{secs:02d}"
    return f"{minutes}:{secs:02d}"


def output_extension(preset: str) -> str:
    return {
        "mp4-h264": ".mp4",
        "mp4-h265": ".mp4",
        "mp4-h264-nvenc": ".mp4",
        "mp4-h265-nvenc": ".mp4",
        "mp4-h264-qsv": ".mp4",
        "mp4-h265-qsv": ".mp4",
        "mp4-h264-amf": ".mp4",
        "mp4-h265-amf": ".mp4",
        "mov-h264": ".mov",
        "webm-vp9": ".webm",
        "audio-mp3": ".mp3",
        "audio-m4a": ".m4a",
        "gif": ".gif",
        "mkv-copy": ".mkv",
    }.get(preset, ".mp4")


def output_suffix(preset: str) -> str:
    if preset == "mkv-copy":
        return "_remuxed"
    if preset.startswith("audio-"):
        return "_audio"
    if preset == "gif":
        return "_animated"
    return "_compressed"


def unique_output(path: Path) -> Path:
    if not path.exists():
        return path
    for number in range(1, 10_000):
        candidate = path.with_name(f"{path.stem} ({number}){path.suffix}")
        if not candidate.exists():
            return candidate
    raise RuntimeError("Could not find a free output file name.")


def quality_value(preset: str, quality: str) -> int:
    tables = {
        "h264": {"best": 17, "high": 20, "balanced": 23, "small": 27, "smallest": 31},
        "h265": {"best": 20, "high": 24, "balanced": 28, "small": 32, "smallest": 36},
        "vp9": {"best": 20, "high": 26, "balanced": 32, "small": 38, "smallest": 44},
        "hardware": {"best": 18, "high": 21, "balanced": 25, "small": 29, "smallest": 34},
        "gif": {"best": 256, "high": 192, "balanced": 128, "small": 96, "smallest": 64},
    }
    if preset == "gif":
        family = "gif"
    elif "vp9" in preset:
        family = "vp9"
    elif any(token in preset for token in ("nvenc", "qsv", "amf")):
        family = "hardware"
    elif "h265" in preset:
        family = "h265"
    else:
        family = "h264"
    return tables[family].get(quality, tables[family]["balanced"])


def build_output_path(values: dict[str, Any], input_path: Path) -> Path:
    preset = str(values.get("preset") or default_preset())
    extension = output_extension(preset)
    output_dir_text = str(values.get("output_dir") or "").strip()
    output_dir = Path(output_dir_text).expanduser() if output_dir_text else input_path.parent
    output_dir.mkdir(parents=True, exist_ok=True)

    requested_name = str(values.get("output_name") or "").strip()
    if requested_name:
        name = requested_name
        if name.lower().endswith(extension.lower()):
            name = name[: -len(extension)]
    else:
        name = input_path.stem + output_suffix(preset)
    if not name or name in {".", ".."}:
        raise ValueError("Choose a valid output file name.")
    if re.search(r'[<>:"/\\|?*]', name):
        raise ValueError("The output name contains an invalid Windows character.")

    output_path = output_dir / f"{name}{extension}"
    if output_path.resolve() == input_path.resolve():
        output_path = output_dir / f"{name}_output{extension}"
    if not bool(values.get("overwrite")):
        output_path = unique_output(output_path)
    return output_path


def build_video_filters(values: dict[str, Any], source: dict[str, Any]) -> list[str]:
    filters: list[str] = []
    resolution = str(values.get("resolution") or "keep")
    source_height = source.get("height")
    if resolution != "keep":
        target_height = int(resolution)
        if not isinstance(source_height, int) or source_height > target_height:
            filters.append(f"scale=-2:{target_height}:flags=lanczos")

    fps_value = str(values.get("fps") or "keep")
    source_fps = source.get("fps")
    if fps_value != "keep":
        target_fps = int(fps_value)
        if not isinstance(source_fps, (int, float)) or source_fps > target_fps + 0.01:
            filters.append(f"fps={target_fps}")
    return filters


def build_ffmpeg_command(
    values: dict[str, Any], input_path: Path, output_path: Path, source: dict[str, Any]
) -> list[str]:
    if not FFMPEG_PATH:
        raise RuntimeError("FFmpeg is not available.")

    preset = str(values.get("preset") or default_preset())
    quality = str(values.get("quality") or "balanced")
    speed = str(values.get("speed") or "balanced")
    audio_bitrate = str(values.get("audio_bitrate") or "160k")
    overwrite_flag = "-y" if bool(values.get("overwrite")) else "-n"

    args = [
        FFMPEG_PATH,
        "-hide_banner",
        "-loglevel",
        "warning",
        "-progress",
        "pipe:1",
        "-nostats",
        overwrite_flag,
        "-i",
        str(input_path),
    ]

    filters = build_video_filters(values, source)

    if preset == "mkv-copy":
        args += ["-map", "0", "-c", "copy"]
    elif preset == "audio-mp3":
        mp3_encoder = "libmp3lame" if "libmp3lame" in AVAILABLE_ENCODERS else "mp3"
        args += ["-vn", "-map", "0:a:0?", "-c:a", mp3_encoder, "-b:a", audio_bitrate]
    elif preset == "audio-m4a":
        args += ["-vn", "-map", "0:a:0?", "-c:a", "aac", "-b:a", audio_bitrate]
    elif preset == "gif":
        gif_filters = list(filters)
        if not any(item.startswith("fps=") for item in gif_filters):
            gif_filters.append("fps=15")
        colors = quality_value(preset, quality)
        chain = ",".join(gif_filters) if gif_filters else "null"
        filter_complex = (
            f"[0:v]{chain},split[gif_a][gif_b];"
            f"[gif_a]palettegen=max_colors={colors}[palette];"
            "[gif_b][palette]paletteuse=dither=sierra2_4a"
        )
        args += ["-filter_complex", filter_complex, "-an", "-loop", "0"]
    else:
        args += ["-map", "0:v:0?", "-map", "0:a:0?"]
        if filters:
            args += ["-vf", ",".join(filters)]

        q = quality_value(preset, quality)
        software_speed = {"slow": "slow", "balanced": "medium", "fast": "veryfast"}[speed]
        vp9_speed = {"slow": "1", "balanced": "2", "fast": "4"}[speed]
        nvenc_speed = {"slow": "p7", "balanced": "p5", "fast": "p3"}[speed]
        amf_speed = {"slow": "quality", "balanced": "balanced", "fast": "speed"}[speed]

        if preset in {"mp4-h264", "mov-h264"}:
            args += ["-c:v", "libx264", "-preset", software_speed, "-crf", str(q), "-pix_fmt", "yuv420p"]
        elif preset == "mp4-h265":
            args += ["-c:v", "libx265", "-preset", software_speed, "-crf", str(q), "-tag:v", "hvc1", "-pix_fmt", "yuv420p"]
        elif preset == "webm-vp9":
            args += ["-c:v", "libvpx-vp9", "-crf", str(q), "-b:v", "0", "-cpu-used", vp9_speed, "-row-mt", "1"]
        elif preset == "mp4-h264-nvenc":
            args += ["-c:v", "h264_nvenc", "-preset", nvenc_speed, "-tune", "hq", "-rc", "vbr", "-cq", str(q), "-b:v", "0", "-pix_fmt", "yuv420p"]
        elif preset == "mp4-h265-nvenc":
            args += ["-c:v", "hevc_nvenc", "-preset", nvenc_speed, "-tune", "hq", "-rc", "vbr", "-cq", str(q), "-b:v", "0", "-tag:v", "hvc1"]
        elif preset == "mp4-h264-qsv":
            args += ["-c:v", "h264_qsv", "-global_quality", str(q), "-preset", software_speed]
        elif preset == "mp4-h265-qsv":
            args += ["-c:v", "hevc_qsv", "-global_quality", str(q), "-preset", software_speed, "-tag:v", "hvc1"]
        elif preset == "mp4-h264-amf":
            args += ["-c:v", "h264_amf", "-quality", amf_speed, "-rc", "cqp", "-qp_i", str(q), "-qp_p", str(q)]
        elif preset == "mp4-h265-amf":
            args += ["-c:v", "hevc_amf", "-quality", amf_speed, "-rc", "cqp", "-qp_i", str(q), "-qp_p", str(q), "-tag:v", "hvc1"]
        else:
            raise ValueError(f"Unsupported preset: {preset}")

        if bool(values.get("remove_audio")):
            args += ["-an"]
        elif preset == "webm-vp9":
            if "libopus" in AVAILABLE_ENCODERS:
                args += ["-c:a", "libopus", "-b:a", audio_bitrate]
            elif "libvorbis" in AVAILABLE_ENCODERS:
                args += ["-c:a", "libvorbis", "-b:a", audio_bitrate]
            else:
                args += ["-an"]
        else:
            args += ["-c:a", "aac", "-b:a", audio_bitrate]

        if output_path.suffix.lower() in {".mp4", ".mov", ".m4a"}:
            args += ["-movflags", "+faststart"]

    args += ["-map_metadata", "0", str(output_path)]
    return args


def preset_label(value: str) -> str:
    for option in preset_options():
        if option["value"] == value:
            return option["label"]
    return value


def operation_frame(job: dict[str, Any], progress: float | None = None, speed: str | None = None) -> dict[str, Any]:
    output_path: Path = job["output_path"]
    elapsed = time.monotonic() - job["started_at"]
    detail_parts = [f"Output: {output_path.name}", f"Elapsed: {human_duration(elapsed)}"]
    if speed and speed != "N/A":
        detail_parts.append(f"Speed: {speed}")
    try:
        if output_path.exists():
            detail_parts.append(f"Written: {human_size(output_path.stat().st_size)}")
    except OSError:
        pass
    detail_parts.append("You may close the launcher; the job can continue in the background for up to 5 minutes.")

    operation: dict[str, Any] = {
        "id": job["id"],
        "title": "Converting media",
        "detail": " · ".join(detail_parts),
        "cancellable": True,
    }
    if progress is not None:
        operation["progress"] = max(0.0, min(1.0, progress))

    return {
        "type": "render",
        "rev": 0,
        "view": "operation",
        "page": page("ffmpeg:operation", "Converting", "replace"),
        "elementId": "conversion-operation",
        "placeholder": "Conversion in progress…",
        "operation": operation,
    }


def parse_out_time(value: str) -> float | None:
    try:
        hours, minutes, seconds = value.split(":", 2)
        return int(hours) * 3600 + int(minutes) * 60 + float(seconds)
    except (ValueError, TypeError):
        return None


def read_stderr(stream: Any, lines: deque[str]) -> None:
    try:
        for raw in stream:
            text = raw.rstrip()
            if text:
                lines.append(text)
    except Exception as exc:
        lines.append(f"Could not read FFmpeg diagnostics: {exc}")


def run_conversion(job: dict[str, Any]) -> None:
    global CURRENT_JOB, LAST_RESULT
    values: dict[str, Any] = job["values"]
    input_path: Path = job["input_path"]
    output_path: Path = job["output_path"]
    source: dict[str, Any] = job["source"]
    stderr_lines: deque[str] = deque(maxlen=80)
    process: subprocess.Popen[str] | None = None

    try:
        args = build_ffmpeg_command(values, input_path, output_path, source)
        log("Running: " + subprocess.list2cmdline(args))
        process = subprocess.Popen(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
        )
        with JOB_LOCK:
            job["process"] = process

        stderr_thread = threading.Thread(
            target=read_stderr,
            args=(process.stderr, stderr_lines),
            daemon=True,
        )
        stderr_thread.start()

        duration = source.get("duration")
        last_render = 0.0
        out_time = 0.0
        speed = None

        if process.stdout is not None:
            for raw in process.stdout:
                if job["cancel"].is_set():
                    break
                line = raw.strip()
                if "=" not in line:
                    continue
                key, value = line.split("=", 1)
                if key in {"out_time_us", "out_time_ms"}:
                    try:
                        out_time = int(value) / 1_000_000.0
                    except ValueError:
                        pass
                elif key == "out_time":
                    parsed = parse_out_time(value)
                    if parsed is not None:
                        out_time = parsed
                elif key == "speed":
                    speed = value

                now = time.monotonic()
                if now - last_render >= 0.25:
                    progress = None
                    if isinstance(duration, (int, float)) and duration > 0:
                        progress = out_time / duration
                    if not UI_CLOSED:
                        send(operation_frame(job, progress, speed))
                    last_render = now

        if job["cancel"].is_set() and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()

        return_code = process.wait()
        stderr_thread.join(timeout=1)
        elapsed = time.monotonic() - job["started_at"]

        if job["cancel"].is_set():
            try:
                if output_path.exists():
                    output_path.unlink()
            except OSError:
                pass
            result = {
                "status": "cancelled",
                "input_path": input_path,
                "output_path": output_path,
                "elapsed": elapsed,
                "values": values,
            }
        elif return_code != 0:
            diagnostics = "\n".join(stderr_lines).strip() or f"FFmpeg exited with code {return_code}."
            result = {
                "status": "error",
                "input_path": input_path,
                "output_path": output_path,
                "elapsed": elapsed,
                "values": values,
                "error": diagnostics,
            }
        elif not output_path.exists():
            result = {
                "status": "error",
                "input_path": input_path,
                "output_path": output_path,
                "elapsed": elapsed,
                "values": values,
                "error": "FFmpeg completed without creating the expected output file.",
            }
        else:
            output_info = probe_media(output_path)
            result = {
                "status": "success",
                "input_path": input_path,
                "output_path": output_path,
                "elapsed": elapsed,
                "values": values,
                "source": source,
                "output": output_info,
            }

        LAST_RESULT = result
        if UI_CLOSED:
            status_text = {
                "success": f"Finished: {output_path.name}",
                "cancelled": "Conversion cancelled.",
                "error": f"Conversion failed: {result.get('error', 'Unknown error')}",
            }[result["status"]]
            command("notify", title=PLUGIN_NAME, text=status_text[:400])
        else:
            if result["status"] == "cancelled":
                command("toast", text="Conversion cancelled.", style="info")
            elif result["status"] == "error":
                command("toast", text="Conversion failed.", style="error")
            render_result(result)
            if result["status"] == "success" and bool(values.get("open_when_done")):
                command("open", path=str(output_path))
    except Exception as exc:
        log(f"Conversion worker failed: {exc}")
        result = {
            "status": "error",
            "input_path": input_path,
            "output_path": output_path,
            "elapsed": time.monotonic() - job["started_at"],
            "values": values,
            "error": str(exc),
        }
        LAST_RESULT = result
        if UI_CLOSED:
            command("notify", title=PLUGIN_NAME, text=f"Conversion failed: {exc}"[:400])
        else:
            render_result(result)
    finally:
        with JOB_LOCK:
            CURRENT_JOB = None


def render_result(result: dict[str, Any]) -> None:
    status = result["status"]
    input_path: Path = result["input_path"]
    output_path: Path = result["output_path"]
    elapsed = result.get("elapsed")

    if status == "success":
        source = result.get("source") or {}
        output = result.get("output") or {}
        source_size = source.get("size")
        output_size = output.get("size")
        change_text = "Unknown"
        if isinstance(source_size, (int, float)) and source_size > 0 and isinstance(output_size, (int, float)):
            delta = (1 - output_size / source_size) * 100
            change_text = f"{delta:.1f}% smaller" if delta >= 0 else f"{-delta:.1f}% larger"

        markdown = (
            "# Conversion complete\n\n"
            f"Created `{output_path.name}` successfully.\n\n"
            f"**Input:** `{input_path}`\n\n"
            f"**Output:** `{output_path}`"
        )
        metadata = [
            {"label": "Preset", "text": preset_label(str(result["values"].get("preset")))},
            {"label": "Input size", "text": human_size(source_size)},
            {"label": "Output size", "text": human_size(output_size)},
            {"label": "Size change", "text": change_text},
            {"label": "Media duration", "text": human_duration(output.get("duration") or source.get("duration"))},
            {"label": "Conversion time", "text": human_duration(elapsed)},
        ]
        actions = [
            {"id": "open-output", "title": "Open output", "icon": "open"},
            {"id": "open-folder", "title": "Open output folder", "icon": "folder"},
            {"id": "copy-path", "title": "Copy output path", "icon": "copy"},
            {
                "id": "delete-output",
                "title": "Delete output file",
                "icon": "trash",
                "destructive": True,
                "confirm": {
                    "title": "Delete the converted file?",
                    "message": "This permanently deletes the output file.",
                    "confirmLabel": "Delete",
                },
            },
            {"id": "convert-another", "title": "Convert another file", "icon": "refresh"},
        ]
        floating = [
            {"id": "open-output", "title": "Open output", "icon": "open"},
            {"id": "convert-another", "title": "Convert another", "icon": "refresh"},
        ]
    elif status == "cancelled":
        markdown = (
            "# Conversion cancelled\n\n"
            "The FFmpeg process was stopped and any partial output was removed."
        )
        metadata = [
            {"label": "Input", "text": input_path.name},
            {"label": "Elapsed", "text": human_duration(elapsed)},
        ]
        actions = [{"id": "convert-another", "title": "Return to converter", "icon": "refresh"}]
        floating = {"id": "convert-another", "title": "Return to converter", "icon": "refresh"}
    else:
        error = str(result.get("error") or "Unknown FFmpeg error")
        if len(error) > 8000:
            error = error[-8000:]
        markdown = (
            "# Conversion failed\n\n"
            "FFmpeg could not complete the job. The latest diagnostics are below.\n\n"
            f"```text\n{error}\n```"
        )
        metadata = [
            {"label": "Input", "text": input_path.name},
            {"label": "Output", "text": output_path.name},
            {"label": "Elapsed", "text": human_duration(elapsed)},
        ]
        actions = [
            {"id": "open-folder", "title": "Open output folder", "icon": "folder"},
            {"id": "copy-error", "title": "Copy error", "icon": "copy"},
            {"id": "convert-another", "title": "Edit settings and retry", "icon": "refresh"},
        ]
        floating = {"id": "convert-another", "title": "Edit settings", "icon": "refresh"}

    send(
        {
            "type": "render",
            "rev": 0,
            "view": "detail",
            "page": page("ffmpeg:result", "Result", "replace"),
            "elementId": "conversion-result",
            "placeholder": "Conversion result…",
            "detail": {"wide": True, "markdown": markdown, "metadata": metadata},
            "actions": actions,
            "floatingAction": floating,
        }
    )


def show_tool_details() -> None:
    detect_tools()
    encoder_lines = "\n".join(f"- `{name}`" for name in sorted(AVAILABLE_ENCODERS)) or "- No known video encoders detected"
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "detail",
            "page": page("ffmpeg:tools", "FFmpeg details", "replace"),
            "detail": {
                "wide": True,
                "markdown": (
                    "# FFmpeg setup\n\n"
                    f"**ffmpeg:** `{FFMPEG_PATH or 'Not found'}`\n\n"
                    f"**ffprobe:** `{FFPROBE_PATH or 'Not found'}`\n\n"
                    "## Detected encoders\n\n"
                    f"{encoder_lines}"
                ),
            },
            "actions": [{"id": "convert-another", "title": "Back to converter", "icon": "refresh"}],
            "floatingAction": {"id": "convert-another", "title": "Back", "icon": "refresh"},
        }
    )


def start_conversion(values: dict[str, Any]) -> None:
    global CURRENT_JOB, LAST_FORM_VALUES
    detect_tools()
    if not FFMPEG_PATH:
        render_missing_ffmpeg()
        return
    with JOB_LOCK:
        if CURRENT_JOB is not None:
            command("toast", text="A conversion is already running.", style="info")
            send(operation_frame(CURRENT_JOB))
            return

    LAST_FORM_VALUES = dict(values)
    input_text = str(values.get("input") or "").strip()
    if not input_text:
        render_form(error="Choose an input media file.")
        return

    input_path = Path(input_text).expanduser()
    if not input_path.exists() or not input_path.is_file():
        render_form(error="The selected input file does not exist or is not a file.")
        return

    try:
        output_path = build_output_path(values, input_path)
        source = probe_media(input_path)
        preset = str(values.get("preset") or default_preset())
        if preset not in {str(option["value"]) for option in preset_options()}:
            raise ValueError("The selected encoder is no longer available in this FFmpeg build.")
        if preset.startswith("audio-") and source.get("audio_codec") is None:
            raise ValueError("The input does not contain an audio stream.")
        if preset not in {"audio-mp3", "audio-m4a", "mkv-copy"} and source.get("video_codec") is None:
            raise ValueError("The input does not contain a video stream.")
    except Exception as exc:
        render_form(error=str(exc))
        return

    job: dict[str, Any] = {
        "id": f"ffmpeg-{int(time.time() * 1000)}",
        "values": dict(values),
        "input_path": input_path,
        "output_path": output_path,
        "source": source,
        "started_at": time.monotonic(),
        "cancel": threading.Event(),
        "process": None,
    }
    with JOB_LOCK:
        CURRENT_JOB = job

    # Allow a conversion to finish after the launcher is closed, up to the host limit.
    command("background", timeout=BACKGROUND_GRACE_SECONDS)
    send(operation_frame(job, 0.0 if source.get("duration") else None))
    worker = threading.Thread(target=run_conversion, args=(job,), daemon=False)
    job["thread"] = worker
    worker.start()


def cancel_conversion() -> None:
    with JOB_LOCK:
        job = CURRENT_JOB
    if not job:
        return
    job["cancel"].set()
    process = job.get("process")
    if process is not None and process.poll() is None:
        try:
            process.terminate()
        except OSError:
            pass
    command("toast", text="Stopping FFmpeg…", style="progress")


def handle_action(message: dict[str, Any]) -> None:
    global FFMPEG_PATH, FFPROBE_PATH, AVAILABLE_ENCODERS, LAST_RESULT
    action = str(message.get("action") or "default")

    if action in {"retry-tools", "check-tools"}:
        if action == "retry-tools":
            FFMPEG_PATH = None
            FFPROBE_PATH = None
            AVAILABLE_ENCODERS = set()
            detect_tools()
            render_form()
        else:
            show_tool_details()
        return

    if action == "convert-another":
        render_form(history="replace")
        return

    result = LAST_RESULT
    if not result:
        return
    output_path: Path = result["output_path"]

    if action == "open-output" and output_path.exists():
        command("open", path=str(output_path))
    elif action == "open-folder":
        command("open", path=str(output_path.parent))
    elif action == "copy-path":
        command("copy", text=str(output_path))
    elif action == "copy-error":
        command("copy", text=str(result.get("error") or "Unknown FFmpeg error"))
    elif action == "delete-output":
        try:
            if output_path.exists():
                output_path.unlink()
            LAST_RESULT = {
                **result,
                "status": "cancelled",
                "elapsed": result.get("elapsed", 0),
            }
            send(
                {
                    "type": "render",
                    "rev": 0,
                    "view": "detail",
                    "page": page("ffmpeg:deleted", "Deleted", "replace"),
                    "detail": {"markdown": f"# Output deleted\n\n`{output_path.name}` was deleted."},
                    "floatingAction": {"id": "convert-another", "title": "Convert another", "icon": "refresh"},
                    "actions": [{"id": "convert-another", "title": "Convert another", "icon": "refresh"}],
                }
            )
        except OSError as exc:
            command("toast", text=f"Could not delete file: {exc}", style="error")


def handle_message(message: dict[str, Any]) -> bool:
    global UI_CLOSED
    msg_type = message.get("type")

    if msg_type == "close":
        UI_CLOSED = True
        # A non-daemon worker keeps the process alive during the requested background grace.
        return False

    if msg_type in {"init", "query"}:
        UI_CLOSED = False
        rev = int(message.get("rev") or 0)
        with JOB_LOCK:
            job = CURRENT_JOB
        if job:
            send(operation_frame(job))
        elif LAST_RESULT:
            render_result(LAST_RESULT)
        else:
            render_form(rev=rev)
    elif msg_type == "submit":
        start_conversion(dict(message.get("values") or {}))
    elif msg_type == "cancel":
        cancel_conversion()
    elif msg_type == "action":
        handle_action(message)
    elif msg_type in {"back", "navigate"}:
        target = message.get("toPageId") or message.get("targetPageId")
        if target == "ffmpeg:convert" or not target:
            render_form(history="replace")
    return True


def main() -> None:
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        try:
            message = json.loads(raw)
            if not isinstance(message, dict):
                continue
            if not handle_message(message):
                break
        except json.JSONDecodeError as exc:
            log(f"Invalid JSON from host: {exc}")
        except Exception as exc:
            log(f"Unhandled message error: {exc}")
            send(
                {
                    "type": "render",
                    "rev": 0,
                    "view": "detail",
                    "detail": {"markdown": f"# Plugin error\n\n```text\n{exc}\n```"},
                }
            )


if __name__ == "__main__":
    main()
