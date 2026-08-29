#!/usr/bin/env python3
"""Tabame launcher plugin for sharkdp/fd.

The plugin is dependency-free. It keeps Tabame's stdin loop responsive while a
background worker owns the current fd process; a new keystroke cancels the old
process and its stale render frame.
"""

from __future__ import annotations

import copy
import ctypes
from ctypes import wintypes
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
from typing import Any
from urllib.parse import unquote
import zlib


SEND_LOCK = threading.Lock()
STATE_LOCK = threading.RLock()
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
SETTINGS_KEY = "settings"
SETTINGS_REQUEST_ID = "fd-settings-load"
INSTALL_COMMANDS = {
    "install_scoop": ("Scoop", "scoop install fd"),
    "install_chocolatey": ("Chocolatey", "choco install fd"),
    "install_winget": ("Winget", "winget install sharkdp.fd"),
}
ICON_CACHE_DIR = Path(__file__).resolve().parent / ".cache" / "icons"
ICON_CACHE_VERSION = "v3"
ICON_CACHE_LOCK = threading.RLock()

# These file types can carry an icon per file rather than using the Windows
# association for their extension. Keep their cache keys path-specific.
DYNAMIC_ICON_EXTENSIONS = frozenset(
    {
        ".ani",
        ".appref-ms",
        ".appx",
        ".appxbundle",
        ".application",
        ".bat",
        ".cur",
        ".cpl",
        ".com",
        ".deskthemepack",
        ".dll",
        ".exe",
        ".ico",
        ".library-ms",
        ".lnk",
        ".msc",
        ".msi",
        ".msix",
        ".msixbundle",
        ".msp",
        ".mst",
        ".ocx",
        ".pif",
        ".scf",
        ".scr",
        ".search-ms",
        ".settingcontent-ms",
        ".theme",
        ".themepack",
        ".url",
        ".website",
    }
)

TEXT_PREVIEW_CHARACTER_LIMIT = 5000
TEXT_PREVIEW_READ_BYTE_LIMIT = 64 * 1024
# Let the pointer settle before doing file I/O for a newly highlighted row.
PREVIEW_HOVER_DELAY_SECONDS = 0.12
IMAGE_PREVIEW_EXTENSIONS = frozenset(
    {
        ".bmp",
        ".gif",
        ".jfif",
        ".jpeg",
        ".jpg",
        ".png",
        ".svg",
        ".wbmp",
        ".webp",
    }
)
BINARY_PREVIEW_EXTENSIONS = frozenset(
    {
        ".7z",
        ".aac",
        ".avi",
        ".bin",
        ".bz2",
        ".class",
        ".com",
        ".dll",
        ".dmg",
        ".doc",
        ".docx",
        ".exe",
        ".flac",
        ".gz",
        ".iso",
        ".m4a",
        ".mkv",
        ".mov",
        ".mp3",
        ".mp4",
        ".msi",
        ".ogg",
        ".pdf",
        ".rar",
        ".so",
        ".tar",
        ".wav",
        ".webm",
        ".xz",
        ".zip",
    }
)


class _WindowsShFileInfo(ctypes.Structure):
    _fields_ = [
        ("hIcon", ctypes.c_void_p),
        ("iIcon", ctypes.c_int),
        ("dwAttributes", wintypes.DWORD),
        ("szDisplayName", wintypes.WCHAR * 260),
        ("szTypeName", wintypes.WCHAR * 80),
    ]


class _WindowsIconInfo(ctypes.Structure):
    _fields_ = [
        ("fIcon", wintypes.BOOL),
        ("xHotspot", wintypes.DWORD),
        ("yHotspot", wintypes.DWORD),
        ("hbmMask", ctypes.c_void_p),
        ("hbmColor", ctypes.c_void_p),
    ]


class _WindowsBitmap(ctypes.Structure):
    _fields_ = [
        ("bmType", wintypes.LONG),
        ("bmWidth", wintypes.LONG),
        ("bmHeight", wintypes.LONG),
        ("bmWidthBytes", wintypes.LONG),
        ("bmPlanes", wintypes.WORD),
        ("bmBitsPixel", wintypes.WORD),
        ("bmBits", ctypes.c_void_p),
    ]


class _WindowsBitmapInfoHeader(ctypes.Structure):
    _fields_ = [
        ("biSize", wintypes.DWORD),
        ("biWidth", wintypes.LONG),
        ("biHeight", wintypes.LONG),
        ("biPlanes", wintypes.WORD),
        ("biBitCount", wintypes.WORD),
        ("biCompression", wintypes.DWORD),
        ("biSizeImage", wintypes.DWORD),
        ("biXPelsPerMeter", wintypes.LONG),
        ("biYPelsPerMeter", wintypes.LONG),
        ("biClrUsed", wintypes.DWORD),
        ("biClrImportant", wintypes.DWORD),
    ]


class _WindowsRgbQuad(ctypes.Structure):
    _fields_ = [
        ("rgbBlue", wintypes.BYTE),
        ("rgbGreen", wintypes.BYTE),
        ("rgbRed", wintypes.BYTE),
        ("rgbReserved", wintypes.BYTE),
    ]


class _WindowsBitmapInfo(ctypes.Structure):
    _fields_ = [
        ("bmiHeader", _WindowsBitmapInfoHeader),
        ("bmiColors", _WindowsRgbQuad * 1),
    ]


class _WindowsIconExtractor:
    """Small dependency-free bridge from a Windows shell icon to PNG bytes."""

    SHGFI_ICON = 0x000000100
    SHGFI_LARGEICON = 0x000000000
    DIB_RGB_COLORS = 0
    BI_RGB = 0

    def __init__(self) -> None:
        if os.name != "nt":
            raise OSError("Windows shell icons are unavailable on this platform")

        self.shell32 = ctypes.WinDLL("shell32", use_last_error=True)
        self.user32 = ctypes.WinDLL("user32", use_last_error=True)
        self.gdi32 = ctypes.WinDLL("gdi32", use_last_error=True)

        self.shell32.SHGetFileInfoW.argtypes = [
            ctypes.c_wchar_p,
            wintypes.DWORD,
            ctypes.POINTER(_WindowsShFileInfo),
            wintypes.UINT,
            wintypes.UINT,
        ]
        self.shell32.SHGetFileInfoW.restype = ctypes.c_void_p
        self.shell32.ExtractIconExW.argtypes = [
            ctypes.c_wchar_p,
            ctypes.c_int,
            ctypes.POINTER(ctypes.c_void_p),
            ctypes.POINTER(ctypes.c_void_p),
            wintypes.UINT,
        ]
        self.shell32.ExtractIconExW.restype = wintypes.UINT
        self.user32.DestroyIcon.argtypes = [ctypes.c_void_p]
        self.user32.DestroyIcon.restype = wintypes.BOOL
        self.user32.GetIconInfo.argtypes = [ctypes.c_void_p, ctypes.POINTER(_WindowsIconInfo)]
        self.user32.GetIconInfo.restype = wintypes.BOOL
        self.gdi32.CreateCompatibleDC.argtypes = [ctypes.c_void_p]
        self.gdi32.CreateCompatibleDC.restype = ctypes.c_void_p
        self.gdi32.DeleteDC.argtypes = [ctypes.c_void_p]
        self.gdi32.DeleteDC.restype = wintypes.BOOL
        self.gdi32.DeleteObject.argtypes = [ctypes.c_void_p]
        self.gdi32.DeleteObject.restype = wintypes.BOOL
        self.gdi32.GetObjectW.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
        self.gdi32.GetObjectW.restype = ctypes.c_int
        self.gdi32.GetDIBits.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            wintypes.UINT,
            wintypes.UINT,
            ctypes.c_void_p,
            ctypes.POINTER(_WindowsBitmapInfo),
            wintypes.UINT,
        ]
        self.gdi32.GetDIBits.restype = ctypes.c_int

    def extract(self, path: str) -> bytes | None:
        file_info = _WindowsShFileInfo()
        result = self.shell32.SHGetFileInfoW(
            path,
            0,
            ctypes.byref(file_info),
            ctypes.sizeof(file_info),
            self.SHGFI_ICON | self.SHGFI_LARGEICON,
        )
        if not result or not file_info.hIcon:
            return None

        try:
            return self._icon_handle_to_png(file_info.hIcon)
        finally:
            self.user32.DestroyIcon(file_info.hIcon)

    def extract_icon_location(self, path: str, icon_index: int) -> bytes | None:
        """Extract an icon from a registry DefaultIcon path and index."""

        large_icon = ctypes.c_void_p()
        small_icon = ctypes.c_void_p()
        try:
            count = self.shell32.ExtractIconExW(
                path,
                icon_index,
                ctypes.byref(large_icon),
                ctypes.byref(small_icon),
                1,
            )
            if count == 0:
                return None
            hicon = large_icon.value or small_icon.value
            return self._icon_handle_to_png(hicon) if hicon else None
        finally:
            if large_icon.value:
                self.user32.DestroyIcon(large_icon)
            if small_icon.value and small_icon.value != large_icon.value:
                self.user32.DestroyIcon(small_icon)

    def _icon_handle_to_png(self, hicon: ctypes.c_void_p) -> bytes | None:
        device_context = self.gdi32.CreateCompatibleDC(None)
        if not device_context:
            return None

        icon_info = _WindowsIconInfo()
        color_bitmap = None
        mask_bitmap = None
        try:
            if not self.user32.GetIconInfo(hicon, ctypes.byref(icon_info)):
                return None
            color_bitmap = icon_info.hbmColor
            mask_bitmap = icon_info.hbmMask
            if not color_bitmap:
                return None

            dimensions = _bitmap_dimensions(self.gdi32, color_bitmap)
            if dimensions is None:
                return None
            width, height = dimensions
            if width <= 0 or height <= 0 or width > 512 or height > 512:
                return None

            color_info = _bitmap_info(width, height, 32)
            color_size = width * height * 4
            color_pixels = (ctypes.c_ubyte * color_size)()
            if (
                self.gdi32.GetDIBits(
                    device_context,
                    color_bitmap,
                    0,
                    height,
                    color_pixels,
                    ctypes.byref(color_info),
                    self.DIB_RGB_COLORS,
                )
                == 0
            ):
                return None

            mask_pixels, mask_stride = self._read_mask(device_context, mask_bitmap, width, height)
            return _png_from_bgra(
                width,
                height,
                bytes(color_pixels),
                mask_pixels,
                mask_stride,
            )
        finally:
            if color_bitmap:
                self.gdi32.DeleteObject(color_bitmap)
            if mask_bitmap:
                self.gdi32.DeleteObject(mask_bitmap)
            self.gdi32.DeleteDC(device_context)

    def _read_mask(
        self,
        device_context: ctypes.c_void_p,
        mask_bitmap: ctypes.c_void_p,
        width: int,
        height: int,
    ) -> tuple[bytes | None, int]:
        if not mask_bitmap:
            return None, 0

        mask_dimensions = _bitmap_dimensions(self.gdi32, mask_bitmap)
        if mask_dimensions is None:
            return None, 0
        mask_height = min(height, mask_dimensions[1])
        if mask_height <= 0:
            return None, 0

        stride = ((width + 31) // 32) * 4
        mask_info = _bitmap_info(width, mask_height, 1)
        mask_size = stride * mask_height
        mask_pixels = (ctypes.c_ubyte * mask_size)()
        if (
            self.gdi32.GetDIBits(
                device_context,
                mask_bitmap,
                0,
                mask_height,
                mask_pixels,
                ctypes.byref(mask_info),
                self.DIB_RGB_COLORS,
            )
            == 0
        ):
            return None, 0
        return bytes(mask_pixels), stride


def _bitmap_dimensions(gdi32: Any, bitmap: ctypes.c_void_p) -> tuple[int, int] | None:
    info = _WindowsBitmap()
    if gdi32.GetObjectW(bitmap, ctypes.sizeof(info), ctypes.byref(info)) == 0:
        return None
    return abs(info.bmWidth), abs(info.bmHeight)


def _bitmap_info(width: int, height: int, bits_per_pixel: int) -> _WindowsBitmapInfo:
    info = _WindowsBitmapInfo()
    info.bmiHeader.biSize = ctypes.sizeof(_WindowsBitmapInfoHeader)
    info.bmiHeader.biWidth = width
    # A negative height asks GetDIBits for top-down rows, which keeps the icon
    # orientation intact when the bytes are converted to PNG.
    info.bmiHeader.biHeight = -height
    info.bmiHeader.biPlanes = 1
    info.bmiHeader.biBitCount = bits_per_pixel
    info.bmiHeader.biCompression = _WindowsIconExtractor.BI_RGB
    info.bmiHeader.biSizeImage = 0
    return info


def _png_chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def _png_from_bgra(
    width: int,
    height: int,
    bgra: bytes,
    mask: bytes | None,
    mask_stride: int,
) -> bytes:
    alpha_present = any(bgra[offset + 3] != 0 for offset in range(0, len(bgra), 4))
    rgba = bytearray(width * height * 4)
    for y in range(height):
        for x in range(width):
            source_offset = (y * width + x) * 4
            target_offset = source_offset
            blue, green, red, alpha = bgra[source_offset : source_offset + 4]
            if mask is not None and (mask[y * mask_stride + x // 8] & (0x80 >> (x % 8))):
                alpha = 0
            elif not alpha_present:
                alpha = 255
            rgba[target_offset : target_offset + 4] = bytes((red, green, blue, alpha))

    rows = bytearray()
    row_size = width * 4
    for offset in range(0, len(rgba), row_size):
        rows.append(0)
        rows.extend(rgba[offset : offset + row_size])
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", header)
        + _png_chunk(b"IDAT", zlib.compress(bytes(rows), 9))
        + _png_chunk(b"IEND", b"")
    )


_WINDOWS_ICON_EXTRACTOR: _WindowsIconExtractor | None = None
_WINDOWS_ICON_EXTRACTOR_FAILED = False


def _windows_icon_extractor() -> _WindowsIconExtractor | None:
    global _WINDOWS_ICON_EXTRACTOR, _WINDOWS_ICON_EXTRACTOR_FAILED
    if os.name != "nt" or _WINDOWS_ICON_EXTRACTOR_FAILED:
        return None
    if _WINDOWS_ICON_EXTRACTOR is not None:
        return _WINDOWS_ICON_EXTRACTOR
    try:
        _WINDOWS_ICON_EXTRACTOR = _WindowsIconExtractor()
    except Exception as exc:
        _WINDOWS_ICON_EXTRACTOR_FAILED = True
        log("Windows file icons are unavailable:", repr(exc))
    return _WINDOWS_ICON_EXTRACTOR


def _association_icon_locations(path: str) -> list[str]:
    """Return the Windows registry icon locations for a file extension."""

    extension = os.path.splitext(path)[1].casefold()
    if not extension:
        return []

    try:
        import winreg
    except ImportError:
        return []

    locations: list[str] = []
    seen_locations: set[str] = set()
    prog_ids: list[str] = []
    seen_prog_ids: set[str] = set()

    def add_location(value: Any) -> None:
        if not isinstance(value, str):
            return
        normalized = value.strip()
        key = normalized.casefold()
        if normalized and key not in seen_locations:
            seen_locations.add(key)
            locations.append(normalized)

    def add_prog_id(value: Any) -> None:
        if not isinstance(value, str):
            return
        normalized = value.strip()
        key = normalized.casefold()
        if normalized and key not in seen_prog_ids:
            seen_prog_ids.add(key)
            prog_ids.append(normalized)

    def read_default(subkey: str) -> Any:
        try:
            with winreg.OpenKey(winreg.HKEY_CLASSES_ROOT, subkey) as key:
                value, _ = winreg.QueryValueEx(key, "")
                return value
        except OSError:
            return None

    try:
        user_choice_key = (
            "Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\FileExts\\"
            f"{extension}\\UserChoice"
        )
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, user_choice_key) as key:
            user_choice, _ = winreg.QueryValueEx(key, "ProgId")
            add_prog_id(user_choice)
    except OSError:
        pass

    add_prog_id(read_default(extension))
    for prog_id in prog_ids:
        add_location(read_default(f"{prog_id}\\DefaultIcon"))

    # A few applications put DefaultIcon directly below the extension key.
    add_location(read_default(f"{extension}\\DefaultIcon"))
    return locations


def _parse_icon_location(value: str) -> tuple[str, int] | None:
    """Parse a registry DefaultIcon value into an image path and icon index."""

    location = value.strip()
    if not location or location.startswith("@{"):
        return None

    if location.startswith('"'):
        closing_quote = location.find('"', 1)
        if closing_quote < 0:
            return None
        icon_path = location[1:closing_quote]
        index_text = location[closing_quote + 1 :].strip()
        if index_text.startswith(","):
            index_text = index_text[1:].strip()
    else:
        icon_path, separator, index_text = location.rpartition(",")
        if not separator:
            icon_path, index_text = location, ""
        icon_path = icon_path.strip()

    icon_path = os.path.expandvars(icon_path.strip().strip('"'))
    if icon_path.startswith("@"):
        icon_path = icon_path[1:]
    if not icon_path or "%" in icon_path:
        return None

    try:
        icon_index = int(index_text) if index_text else 0
    except ValueError:
        return None
    return icon_path, icon_index


def _packaged_icon_asset(value: str) -> Path | None:
    """Resolve a packaged Windows ms-resource icon to its PNG asset."""

    location = value.strip()
    if not (location.startswith("@{") and location.endswith("}")):
        return None

    package_name, separator, resource_uri = location[2:-1].partition("?ms-resource://")
    if not separator or not package_name or "/" not in resource_uri:
        return None

    _, _, resource_path = resource_uri.partition("/")
    resource_path = unquote(resource_path).replace("\\", "/")
    if resource_path.casefold().startswith("files/"):
        resource_path = resource_path[6:]
    if not resource_path or any(part == ".." for part in resource_path.split("/")):
        return None

    program_files = os.environ.get("ProgramW6432") or os.environ.get("ProgramFiles")
    if not program_files:
        return None
    windows_apps = Path(program_files) / "WindowsApps"
    package_roots: list[Path] = [windows_apps / package_name]
    if not package_roots[0].is_dir():
        try:
            package_prefix = package_name.casefold()
            package_roots = [
                child
                for child in windows_apps.iterdir()
                if child.is_dir()
                and (
                    child.name.casefold() == package_prefix
                    or child.name.casefold().startswith(f"{package_prefix}_")
                )
            ]
        except OSError:
            return None

    relative_parts = [part for part in resource_path.split("/") if part]
    preferred_variants = (
        "targetsize-64",
        "targetsize-48",
        "targetsize-32",
        "targetsize-96",
        "targetsize-128",
        "targetsize-256",
        "scale-200",
        "scale-100",
    )
    for package_root in package_roots:
        candidate = package_root.joinpath(*relative_parts)
        candidates = [candidate]
        if candidate.suffix.casefold() == ".png":
            candidates.extend(
                candidate.with_name(f"{candidate.stem}.{variant}{candidate.suffix}")
                for variant in preferred_variants
            )
            try:
                candidates.extend(
                    sorted(
                        candidate.parent.glob(f"{candidate.stem}.*{candidate.suffix}"),
                        key=lambda item: item.name.casefold(),
                    )
                )
            except OSError:
                pass
        for icon_file in candidates:
            try:
                if icon_file.is_file():
                    return icon_file
            except OSError:
                continue
    return None


def _associated_icon_bytes(path: str, extractor: _WindowsIconExtractor) -> bytes | None:
    """Resolve an extension's association, including packaged app icons."""

    for location in _association_icon_locations(path):
        packaged_asset = _packaged_icon_asset(location)
        if packaged_asset is not None:
            try:
                icon_bytes = packaged_asset.read_bytes()
            except OSError:
                icon_bytes = None
            if icon_bytes and icon_bytes.startswith(b"\x89PNG\r\n\x1a\n"):
                return icon_bytes
            continue

        parsed_location = _parse_icon_location(location)
        if parsed_location is None:
            continue
        icon_path, icon_index = parsed_location
        if not os.path.isfile(icon_path):
            continue
        try:
            icon_bytes = extractor.extract_icon_location(icon_path, icon_index)
        except Exception as exc:
            log("Could not extract associated file icon:", icon_path, repr(exc))
            continue
        if icon_bytes:
            return icon_bytes
    return None


def _icon_cache_file(path: str, is_dir: bool) -> Path:
    if is_dir:
        cache_key = "folder"
        prefix = "extension"
    else:
        extension = os.path.splitext(path)[1].casefold()
        if extension in DYNAMIC_ICON_EXTENSIONS:
            try:
                stat = os.stat(path, follow_symlinks=False)
                signature = f"{stat.st_size}:{stat.st_mtime_ns}"
            except OSError:
                signature = "missing"
            normalized_path = os.path.normcase(os.path.abspath(path))
            cache_key = f"{normalized_path}|{signature}"
            prefix = "file"
        else:
            cache_key = extension or "no-extension"
            prefix = "extension"

    digest = hashlib.sha256(f"{ICON_CACHE_VERSION}|{cache_key}".encode("utf-8", "surrogatepass")).hexdigest()[:24]
    return ICON_CACHE_DIR / f"{prefix}_{digest}.png"


def _cached_icon_uri(path: str, is_dir: bool) -> str | None:
    cache_file = _icon_cache_file(path, is_dir)
    try:
        if cache_file.is_file() and cache_file.stat().st_size > 32:
            return cache_file.resolve().as_uri()
    except OSError:
        pass
    return None


def _write_icon_cache(cache_file: Path, icon_bytes: bytes) -> bool:
    temporary_path: Path | None = None
    try:
        cache_file.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            mode="wb",
            prefix=f".{cache_file.stem}-",
            suffix=".tmp",
            dir=cache_file.parent,
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)
            temporary.write(icon_bytes)
            temporary.flush()
        os.replace(temporary_path, cache_file)
        return True
    except OSError as exc:
        log("Could not cache file icon:", repr(exc))
        return False
    finally:
        if temporary_path is not None:
            try:
                temporary_path.unlink(missing_ok=True)
            except OSError:
                pass


def _system_icon_for(path: str, is_dir: bool) -> str | None:
    if os.name != "nt":
        # //TODO: Implement multiplatform
        return None

    with ICON_CACHE_LOCK:
        cached = _cached_icon_uri(path, is_dir)
        if cached is not None:
            return cached

        extractor = _windows_icon_extractor()
        if extractor is None:
            return None

        icon_bytes: bytes | None = None
        extension = os.path.splitext(path)[1].casefold() if not is_dir else ""
        if not is_dir and extension not in DYNAMIC_ICON_EXTENSIONS:
            try:
                icon_bytes = _associated_icon_bytes(path, extractor)
            except Exception as exc:
                log("Could not resolve associated file icon:", path, repr(exc))
        try:
            if icon_bytes is None:
                icon_bytes = extractor.extract(path)
        except Exception as exc:
            log("Could not extract file icon:", path, repr(exc))
            icon_bytes = None
        if icon_bytes is None and not is_dir:
            try:
                icon_bytes = _associated_icon_bytes(path, extractor)
            except Exception as exc:
                log("Could not resolve associated file icon:", path, repr(exc))
        if not icon_bytes or not _write_icon_cache(_icon_cache_file(path, is_dir), icon_bytes):
            return None
        return _cached_icon_uri(path, is_dir)


def clear_icon_cache() -> int:
    removed = 0
    with ICON_CACHE_LOCK:
        if not ICON_CACHE_DIR.exists():
            return 0
        try:
            for child in ICON_CACHE_DIR.iterdir():
                if not child.is_file() and not child.is_symlink():
                    continue
                if child.suffix.casefold() not in {".png", ".tmp"}:
                    continue
                try:
                    child.unlink()
                    removed += 1
                except OSError as exc:
                    log("Could not remove cached icon:", child, repr(exc))
        except OSError as exc:
            log("Could not enumerate icon cache:", repr(exc))
    return removed


def default_settings() -> dict[str, Any]:
    return {
        "configured": False,
        "executable": "fd",
        "roots": [str(Path.home())],
        "includes": [],
        "excludes": ["node_modules", ".git", ".dart_tool", ".venv", "__pycache__"],
        "mode": "literal",
        "item_type": "files",
        "max_results": 150,
        "hidden": False,
        "ignored": False,
        "follow": False,
        "full_path": False,
    }


STATE: dict[str, Any] = {
    "loaded": False,
    "screen": "loading",
    "settings": default_settings(),
    "current_query": "",
    "results": [],
    "items": {},
    "active_process": None,
    "search_serial": 0,
    "results_limited": False,
    "base_item_payloads": {},
    "preview_serial": 0,
    "preview_cache": {},
    "preview_timer": None,
    "preview_requested_id": None,
    "preview_rendered_id": None,
    "closing": False,
}


def send(message: dict[str, Any]) -> None:
    with SEND_LOCK:
        sys.stdout.write(json.dumps(message, ensure_ascii=False) + "\n")
        sys.stdout.flush()


def command(name: str, **fields: Any) -> None:
    send({"type": "command", "command": name, **fields})


def log(*parts: Any) -> None:
    print(*parts, file=sys.stderr, flush=True)


def page(page_id: str, title: str, history: str = "none", *, root: bool = False) -> dict[str, Any]:
    result: dict[str, Any] = {
        "id": page_id,
        "title": title,
        "history": history,
        "preserveState": True,
    }
    if not root:
        result["breadcrumbs"] = [{"id": "fd:search", "label": "Search"}]
    return result


SEARCH_ACTIONS = [
    {"id": "refresh", "title": "Run search again", "icon": "refresh", "shortcut": "ctrl+r"},
    {"id": "settings", "title": "Search settings", "icon": "settings", "shortcut": "ctrl+shift+s"},
    {"id": "clear_icons_cache", "title": "Clear Icons Cache", "icon": "trash"},
    {"id": "help", "title": "How this search works", "icon": "help", "shortcut": "ctrl+shift+h"},
]


def split_rules(value: Any) -> list[str]:
    if isinstance(value, list):
        candidates = value
    else:
        candidates = str(value or "").splitlines()
    result: list[str] = []
    seen: set[str] = set()
    for candidate in candidates:
        rule = str(candidate).strip().strip('"')
        key = rule.casefold()
        if rule and key not in seen:
            seen.add(key)
            result.append(rule)
    return result


def normalize_root(value: str) -> str:
    expanded = os.path.expanduser(os.path.expandvars(value.strip().strip('"')))
    if os.name == "nt" and len(expanded) == 2 and expanded[1] == ":":
        expanded += "\\"
    return os.path.abspath(expanded)


def roots_from_values(roots_text: Any, quick_root: Any = "") -> list[str]:
    values = split_rules(roots_text)
    if str(quick_root or "").strip():
        values.append(str(quick_root))
    roots: list[str] = []
    seen: set[str] = set()
    for value in values:
        root = normalize_root(value)
        key = os.path.normcase(root)
        if key not in seen:
            seen.add(key)
            roots.append(root)
    return roots


def sanitized_settings(raw: Any) -> dict[str, Any]:
    settings = default_settings()
    if not isinstance(raw, dict):
        return settings

    executable = str(raw.get("executable", settings["executable"])).strip().strip('"')
    settings["executable"] = executable or "fd"
    try:
        settings["roots"] = roots_from_values(raw.get("roots", settings["roots"]))
    except (OSError, ValueError):
        settings["roots"] = default_settings()["roots"]
    if not settings["roots"]:
        settings["roots"] = default_settings()["roots"]
    settings["includes"] = split_rules(raw.get("includes", []))
    settings["excludes"] = split_rules(raw.get("excludes", settings["excludes"]))
    settings["mode"] = raw.get("mode") if raw.get("mode") in {"literal", "glob", "regex"} else "literal"
    settings["item_type"] = (
        raw.get("item_type") if raw.get("item_type") in {"files", "folders", "both"} else "files"
    )
    try:
        settings["max_results"] = max(20, min(500, int(raw.get("max_results", 150))))
    except (TypeError, ValueError):
        settings["max_results"] = 150
    for key in ("hidden", "ignored", "follow", "full_path"):
        settings[key] = bool(raw.get(key, settings[key]))
    settings["configured"] = bool(raw.get("configured", True))
    return settings


def save_settings() -> None:
    payload = json.dumps(STATE["settings"], ensure_ascii=False)
    command("storage", op="set", key=SETTINGS_KEY, value=payload)


def resolve_executable(value: str) -> str | None:
    expanded = os.path.expanduser(os.path.expandvars(value))
    if os.path.isfile(expanded):
        return os.path.abspath(expanded)
    return shutil.which(expanded)


def render_boot(rev: int = 0) -> None:
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": page("fd:search", "fd File Search", root=True),
            "loading": True,
            "loadingText": "Loading your search settings…",
            "items": [],
        }
    )


def settings_fields(settings: dict[str, Any], errors: dict[str, str] | None = None) -> list[dict[str, Any]]:
    errors = errors or {}

    def field(data: dict[str, Any]) -> dict[str, Any]:
        if data["id"] in errors:
            data["error"] = errors[data["id"]]
        return data

    executable = resolve_executable(settings["executable"])
    executable_hint = f"Found: {executable}" if executable else "Not found on PATH yet. Install fd or choose fd.exe."
    return [
        field(
            {
                "id": "roots",
                "type": "textarea",
                "label": "Search roots",
                "value": "\n".join(settings["roots"]),
                "required": True,
                "section": "locations",
                "description": "One drive or folder per line. Examples: C:\\, D:\\Work, %USERPROFILE%\\Documents.",
            }
        ),
        {
            "id": "quick_root",
            "type": "folderpicker",
            "label": "Add another root",
            "section": "locations",
            "description": "Optional: pick a folder and it will be merged into the list above when you save.",
        },
        {
            "id": "includes",
            "type": "textarea",
            "label": "Include only",
            "value": "\n".join(settings["includes"]),
            "section": "filters",
            "description": "Optional OR rules. Use path names (src), extensions (.dart), or globs (*.md), one per line.",
        },
        {
            "id": "excludes",
            "type": "textarea",
            "label": "Exclude",
            "value": "\n".join(settings["excludes"]),
            "section": "filters",
            "description": "Skip noisy path names, extensions, or globs. These are passed to fd for fast pruning.",
        },
        {
            "id": "mode",
            "type": "dropdown",
            "label": "Query mode",
            "value": settings["mode"],
            "section": "behavior",
            "options": [
                {"value": "literal", "label": "Smart literal · safe substring"},
                {"value": "glob", "label": "Glob · e.g. report*.pdf"},
                {"value": "regex", "label": "Regular expression"},
            ],
        },
        {
            "id": "item_type",
            "type": "dropdown",
            "label": "Result type",
            "value": settings["item_type"],
            "section": "behavior",
            "options": [
                {"value": "files", "label": "Files only"},
                {"value": "folders", "label": "Folders only"},
                {"value": "both", "label": "Files and folders"},
            ],
        },
        field(
            {
                "id": "max_results",
                "type": "number",
                "label": "Maximum results",
                "value": settings["max_results"],
                "min": 20,
                "max": 500,
                "section": "behavior",
                "description": "The plugin scans a larger candidate pool, ranks exact and prefix matches, then shows this many.",
            }
        ),
        {
            "id": "full_path",
            "type": "checkbox",
            "label": "Match the query against the full path",
            "value": settings["full_path"],
            "section": "behavior",
        },
        {
            "id": "hidden",
            "type": "checkbox",
            "label": "Search hidden files and folders",
            "value": settings["hidden"],
            "section": "behavior",
        },
        {
            "id": "ignored",
            "type": "checkbox",
            "label": "Search entries ignored by .gitignore/.fdignore",
            "value": settings["ignored"],
            "section": "behavior",
        },
        {
            "id": "follow",
            "type": "checkbox",
            "label": "Follow symbolic links",
            "value": settings["follow"],
            "section": "behavior",
        },
        field(
            {
                "id": "executable",
                "type": "text",
                "label": "fd executable",
                "value": settings["executable"],
                "required": True,
                "section": "advanced",
                "description": executable_hint,
            }
        ),
    ]


def render_settings(
    rev: int = 0,
    *,
    history: str = "push",
    errors: dict[str, str] | None = None,
    first_run: bool = False,
) -> None:
    STATE["screen"] = "settings"
    settings = STATE["settings"]
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "page": page("fd:settings", "Set up fd Search", "none" if first_run else history, root=first_run),
            "elementId": "fd-settings-form",
            "placeholder": "Configure where fd should search",
            "actions": [{"id": "help", "title": "Settings help", "icon": "help"}],
            "form": {
                "title": "Where should fd search?",
                **({"error": "Fix the highlighted settings before saving."} if errors else {}),
                "sections": [
                    {"id": "locations", "title": "Locations", "description": "Search one folder, several drives, or both."},
                    {"id": "filters", "title": "Path filters", "description": "Keep useful trees and prune noisy ones."},
                    {"id": "behavior", "title": "Search behavior", "collapsible": True},
                    {"id": "advanced", "title": "Executable", "collapsible": True},
                ],
                "submitLabel": "Save and search",
                "fields": settings_fields(settings, errors),
            },
        }
    )


def root_summary(settings: dict[str, Any]) -> str:
    roots = settings["roots"]
    noun = "root" if len(roots) == 1 else "roots"
    return f"{len(roots)} {noun} · {settings['mode']} mode · up to {settings['max_results']} results"


def render_search_prompt(rev: int, *, history: str = "none") -> None:
    STATE["screen"] = "search"
    settings = STATE["settings"]
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": page("fd:search", "fd File Search", history, root=True),
            "elementId": "fd-results",
            "placeholder": f"Search filenames across {len(settings['roots'])} configured location(s)…",
            "wide": False,
            "empty": {
                "icon": "search",
                "title": "Start typing a filename",
                "hint": root_summary(settings),
                "action": {"id": "settings", "title": "Review search locations", "icon": "settings"},
            },
            "actions": SEARCH_ACTIONS,
            "floatingAction": {"id": "settings", "title": "Settings", "icon": "settings"},
            "items": [],
        }
    )


def render_loading(rev: int, query: str, *, history: str = "none") -> None:
    STATE["screen"] = "search"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": page("fd:search", "fd File Search", history, root=True),
            "elementId": "fd-results",
            "placeholder": "Keep typing to refine…",
            "loading": True,
            "loadingText": f"fd is searching for “{query}”…",
            "wide": False,
            "actions": SEARCH_ACTIONS,
            "items": [],
        }
    )


def render_search_error(rev: int, title: str, hint: str) -> None:
    STATE["screen"] = "search"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": page("fd:search", "fd Search Error", root=True),
            "elementId": "fd-results",
            "placeholder": "Edit the query or open Settings",
            "empty": {
                "icon": "error",
                "title": title,
                "hint": hint[:500],
                "action": {"id": "settings", "title": "Open settings", "icon": "settings"},
            },
            "actions": SEARCH_ACTIONS,
            "floatingAction": {"id": "settings", "title": "Settings", "icon": "settings"},
            "items": [],
        }
    )


def render_fd_installer(rev: int = 0, *, launch_error: str = "") -> None:
    STATE["screen"] = "install"
    windows = os.name == "nt"
    metadata: list[dict[str, Any]] = []
    if windows:
        metadata = [
            {
                "label": "Scoop",
                "text": "scoop install fd",
                "icon": "terminal",
                "actions": [{"id": "install_scoop", "title": "Install with Scoop", "icon": "download"}],
            },
            {
                "label": "Chocolatey",
                "text": "choco install fd",
                "icon": "terminal",
                "actions": [
                    {"id": "install_chocolatey", "title": "Install with Chocolatey", "icon": "download"}
                ],
            },
            {
                "label": "Winget",
                "text": "winget install sharkdp.fd",
                "icon": "terminal",
                "actions": [{"id": "install_winget", "title": "Install with Winget", "icon": "download"}],
            },
        ]

    if launch_error:
        intro = f"## Could not open the installer terminal\n\n```\n{launch_error}\n```\n\n"
    elif windows:
        intro = (
            "Choose the package manager already available on this PC. The button opens a **visible command "
            "prompt**, runs the command shown, and keeps the terminal open so you can review the result.\n\n"
        )
    else:
        intro = (
            "Automatic installers are currently available on Windows only. Install `fd` with your platform's "
            "package manager, or use **Settings** to select an existing `fd`/`fdfind` executable.\n\n"
        )

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "page": page("fd:install", "Install fd", root=True),
            "elementId": "fd-installer",
            "placeholder": "Install fd to begin searching",
            "actions": [
                {"id": "check_fd", "title": "Check for fd again", "icon": "refresh", "shortcut": "ctrl+r"},
                {"id": "settings", "title": "Choose an executable", "icon": "settings"},
                {"id": "open_fd_docs", "title": "Open fd installation guide", "icon": "globe"},
            ],
            "floatingAction": [
                {"id": "check_fd", "title": "Check again", "icon": "refresh"},
                {"id": "settings", "title": "Settings", "icon": "settings"},
            ],
            "detail": {
                "wide": False,
                "markdown": (
                    "# `fd` is required\n\n"
                    "The plugin itself is ready, but the `fd` executable was not found.\n\n"
                    f"{intro}"
                    "After installation, reopen Tabame and type **`fd`** again."
                ),
                "metadata": metadata,
            },
        }
    )


def launch_visible_installer(action: str) -> None:
    installer = INSTALL_COMMANDS.get(action)
    if installer is None:
        return
    if os.name != "nt":
        # //TODO: Implement multiplatform
        command("toast", text="Automatic fd installation is currently available on Windows only.", style="error")
        return

    manager, install_command = installer
    try:
        command_prompt = os.path.expandvars(r"%SystemRoot%\System32\cmd.exe")
        os.startfile(
            command_prompt,
            "open",
            arguments=f'/d /k "{install_command}"',
            cwd=os.path.expandvars(r"%USERPROFILE%"),
            show_cmd=1,
        )
        command("hide")
    except OSError as exc:
        log(f"Could not launch {manager} installer:", exc)
        render_fd_installer(0, launch_error=str(exc))


def render_help(rev: int = 0, *, history: str = "push") -> None:
    STATE["screen"] = "help"
    settings = STATE["settings"]
    include_text = ", ".join(settings["includes"]) or "none"
    exclude_text = ", ".join(settings["excludes"]) or "none"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "page": page("fd:help", "Using fd File Search", history),
            "elementId": "fd-help",
            "placeholder": "fd search help",
            "actions": [{"id": "settings", "title": "Search settings", "icon": "settings"}],
            "floatingAction": {"id": "settings", "title": "Settings", "icon": "settings"},
            "detail": {
                "wide": False,
                "markdown": (
                    "# Fast file search with `fd`\n\n"
                    "Type **`fd`**, a space, then part of a filename. Searches are cancelled and restarted "
                    "as you type, so old results never replace a newer query.\n\n"
                    "## Result keys\n\n"
                    "- **Enter** opens the selected file or folder and closes the launcher.\n"
                    "- **Ctrl+K** offers Open folder, Copy path, Copy name, and Paste path.\n"
                    "- **Ctrl+R** reruns the current search.\n"
                    "- **Ctrl+Shift+S** opens settings.\n\n"
                    "## Filter rules\n\n"
                    "A simple name such as `node_modules` matches that path segment. An extension such as "
                    "`.dll` matches files ending in it. Globs such as `*.generated.dart` are also accepted. "
                    "Include rules use **OR** semantics; excludes always win.\n\n"
                    "Literal mode uses fd's smart-case substring matching. Glob and regular-expression modes "
                    "pass the query through to fd unchanged."
                ),
                "metadata": [
                    {"label": "Search roots", "text": str(len(settings["roots"])), "icon": "folder"},
                    {"label": "Query mode", "text": settings["mode"], "icon": "search"},
                    {"label": "Include rules", "text": include_text, "icon": "check"},
                    {"label": "Exclude rules", "text": exclude_text, "icon": "close"},
                    {"separator": True},
                    {"label": "fd project", "text": "github.com/sharkdp/fd", "url": "https://github.com/sharkdp/fd"},
                ],
            },
        }
    )


def fd_exclude_rule(rule: str) -> str:
    if rule.startswith(".") and not any(char in rule for char in "*/?[]\\"):
        return f"*{rule}"
    return rule.replace("\\", "/")


def include_extensions(rules: list[str]) -> list[str]:
    """Return extension names when every include rule is extension-only."""
    extensions: list[str] = []
    for rule in rules:
        candidate = rule.strip()
        if candidate.startswith("*.") and not any(char in candidate[2:] for char in "*/?[]\\"):
            candidate = candidate[1:]
        if not candidate.startswith(".") or len(candidate) == 1:
            return []
        if any(char in candidate[1:] for char in "*/?[]\\"):
            return []
        extensions.append(candidate[1:].casefold())
    return extensions


def matches_filter(path: str, rule: str) -> bool:
    normalized = path.replace("\\", "/").casefold()
    filename = normalized.rsplit("/", 1)[-1]
    candidate = rule.strip().replace("\\", "/").casefold()
    if not candidate:
        return False
    if candidate.startswith(".") and not any(char in candidate for char in "*/?[]"):
        return filename.endswith(candidate)
    if any(char in candidate for char in "*?["):
        return (
            fnmatch.fnmatchcase(filename, candidate)
            or fnmatch.fnmatchcase(normalized, candidate)
            or fnmatch.fnmatchcase(normalized, f"*/{candidate}")
        )
    if "/" in candidate:
        needle = candidate.strip("/")
        return f"/{needle}/" in f"/{normalized.strip('/')}/" or normalized.endswith(f"/{needle}")
    return candidate in [part for part in normalized.split("/") if part]


def path_root(path: str, roots: list[str]) -> str:
    best = roots[0]
    best_length = -1
    for root in roots:
        try:
            common = os.path.normcase(os.path.commonpath([path, root]))
            if common == os.path.normcase(os.path.commonpath([root])):
                length = len(os.path.normcase(root))
                if length > best_length:
                    best = root
                    best_length = length
        except ValueError:
            continue
    return best


def root_label(root: str) -> str:
    drive, _ = os.path.splitdrive(root)
    name = os.path.basename(os.path.normpath(root))
    if not name:
        return drive + os.sep if drive else root
    return f"{name} · {drive}" if drive else name


def _fallback_icon_for(path: str, is_dir: bool) -> str:
    if is_dir:
        return "folder"
    extension = Path(path).suffix.casefold()
    if extension in {".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg", ".ico"}:
        return "image"
    if extension in {".mp3", ".wav", ".flac", ".aac", ".ogg", ".m4a"}:
        return "music"
    if extension in {".mp4", ".mkv", ".avi", ".mov", ".webm"}:
        return "video"
    if extension in {".py", ".js", ".ts", ".dart", ".rs", ".go", ".java", ".cpp", ".c", ".h", ".cs"}:
        return "code"
    if extension in {".md", ".txt", ".pdf", ".doc", ".docx", ".rtf"}:
        return "document"
    if extension in {".zip", ".7z", ".rar", ".tar", ".gz"}:
        return "download"
    return "file"


def icon_for(path: str, is_dir: bool) -> str:
    return _system_icon_for(path, is_dir) or _fallback_icon_for(path, is_dir)


def markdown_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace("`", "\\`").replace("*", "\\*").replace("_", "\\_")


def _decode_text_preview(raw: bytes) -> str | None:
    if not raw:
        return ""

    encodings: list[tuple[bytes, str, int]] = [
        (b"\xff\xfe\x00\x00", "utf-32-le", 4),
        (b"\x00\x00\xfe\xff", "utf-32-be", 4),
        (b"\xff\xfe", "utf-16-le", 2),
        (b"\xfe\xff", "utf-16-be", 2),
        (b"\xef\xbb\xbf", "utf-8", 3),
    ]
    for marker, encoding, offset in encodings:
        if raw.startswith(marker):
            try:
                return raw[offset:].decode(encoding)
            except UnicodeDecodeError:
                return None

    binary_signatures = (b"MZ", b"PK\x03\x04", b"\x7fELF", b"%PDF-", b"ID3", b"OggS", b"RIFF")
    if raw.startswith(binary_signatures):
        return None

    if b"\x00" in raw:
        pair_count = max(1, len(raw) // 2)
        even_nulls = sum(1 for index in range(0, len(raw), 2) if raw[index] == 0)
        odd_nulls = sum(1 for index in range(1, len(raw), 2) if raw[index] == 0)
        if odd_nulls > pair_count * 0.6 and even_nulls < pair_count * 0.1:
            try:
                return raw.decode("utf-16-le")
            except UnicodeDecodeError:
                return None
        if even_nulls > pair_count * 0.6 and odd_nulls < pair_count * 0.1:
            try:
                return raw.decode("utf-16-be")
            except UnicodeDecodeError:
                return None
        return None

    suspicious_bytes = sum(
        1 for byte in raw if byte < 0x09 or (0x0D < byte < 0x20) or byte == 0x7F
    )
    if suspicious_bytes > max(2, len(raw) // 100):
        return None

    try:
        return raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        try:
            return raw.decode("cp1252")
        except UnicodeDecodeError:
            return None


def _markdown_code_fence(text: str) -> str:
    longest_run = 0
    current_run = 0
    for character in text:
        if character == "`":
            current_run += 1
            longest_run = max(longest_run, current_run)
        else:
            current_run = 0
    return "`" * max(3, longest_run + 1)


def _image_preview_uri(path: str, extension: str) -> str | None:
    is_image = extension in IMAGE_PREVIEW_EXTENSIONS
    if not is_image:
        try:
            with open(path, "rb") as handle:
                header = handle.read(16)
            is_image = header.startswith(
                (
                    b"\x89PNG\r\n\x1a\n",
                    b"\xff\xd8\xff",
                    b"GIF87a",
                    b"GIF89a",
                    b"BM",
                )
            ) or (header[:4] == b"RIFF" and header[8:12] == b"WEBP")
        except OSError:
            return None
    if not is_image:
        return None
    try:
        return Path(path).resolve().as_uri()
    except (OSError, ValueError):
        return None


def _file_preview_signature(path: str) -> tuple[int, int] | None:
    try:
        stat = os.stat(path, follow_symlinks=False)
    except OSError:
        return None
    return stat.st_size, stat.st_mtime_ns


def _load_file_preview(record: dict[str, Any]) -> str | None:
    path = record["path"]
    if record["is_dir"]:
        return None

    signature = _file_preview_signature(path)
    cache_key = os.path.normcase(os.path.abspath(path))
    if signature is not None:
        with STATE_LOCK:
            cached = STATE["preview_cache"].get(cache_key)
        if cached is not None and cached[0] == signature:
            return cached[1]

    extension = Path(path).suffix.casefold()
    preview: str | None = None
    image_uri = _image_preview_uri(path, extension)
    if image_uri is None and extension == ".ico":
        cached_icon = _system_icon_for(path, False)
        if cached_icon is not None:
            image_uri = cached_icon
    if image_uri is not None:
        preview = (
            f"### {markdown_escape(record['name'])}\n\n"
            f"![Image preview]({image_uri})\n\n"
            "Press **Enter** to open this file."
        )
    elif signature is not None and extension not in BINARY_PREVIEW_EXTENSIONS:
        try:
            with open(path, "rb") as handle:
                raw = handle.read(TEXT_PREVIEW_READ_BYTE_LIMIT)
            decoded = _decode_text_preview(raw)
            if decoded is not None:
                truncated = signature[0] > len(raw) or len(decoded) > TEXT_PREVIEW_CHARACTER_LIMIT
                text = decoded[:TEXT_PREVIEW_CHARACTER_LIMIT]
                if text:
                    fence = _markdown_code_fence(text)
                    body = f"{fence}text\n{text}\n{fence}"
                else:
                    body = "_(empty text file)_"
                if truncated:
                    body += "\n\n> Preview truncated to 5,000 characters."
                preview = (
                    f"### {markdown_escape(record['name'])}\n\n"
                    f"{body}\n\n"
                    "Press **Enter** to open this file."
                )
        except OSError as exc:
            log("Could not read file preview:", path, repr(exc))

    if signature is not None:
        with STATE_LOCK:
            STATE["preview_cache"][cache_key] = (signature, preview)
    return preview


def _load_selected_preview(
    serial: int,
    rev: int,
    item_id: str,
    record: dict[str, Any],
) -> None:
    try:
        preview = _load_file_preview(record)
    except Exception as exc:
        with STATE_LOCK:
            if serial == STATE["preview_serial"]:
                STATE["preview_requested_id"] = None
        log("Could not prepare file preview:", record.get("path", ""), repr(exc))
        return
    with STATE_LOCK:
        if serial != STATE["preview_serial"] or STATE["closing"] or STATE["screen"] != "search":
            return
        current_record = STATE["items"].get(item_id)
        if current_record is None or current_record["path"] != record["path"]:
            return
        if preview is None:
            STATE["preview_requested_id"] = None
            STATE["preview_rendered_id"] = item_id
            return
        records = list(STATE["results"])
        query = STATE["current_query"]
        limited = STATE["results_limited"]
        try:
            render_results(
                rev,
                query,
                records,
                limited,
                selected_id=item_id,
                selected_preview=preview,
                reuse_items=True,
            )
        except Exception as exc:
            STATE["preview_requested_id"] = None
            log("Could not render file preview:", record.get("path", ""), repr(exc))
            return
        STATE["preview_requested_id"] = None
        STATE["preview_rendered_id"] = item_id


def _start_selected_preview(
    serial: int,
    rev: int,
    item_id: str,
    record: dict[str, Any],
) -> None:
    with STATE_LOCK:
        if (
            serial != STATE["preview_serial"]
            or STATE["closing"]
            or STATE["screen"] != "search"
        ):
            return
        STATE["preview_timer"] = None
    _load_selected_preview(serial, rev, item_id, record)


def request_file_preview(rev: int, item_id: str) -> None:
    with STATE_LOCK:
        if STATE["screen"] != "search" or not item_id:
            return
        record = STATE["items"].get(item_id)
        if record is None:
            return
        requested_id = STATE.get("preview_requested_id")
        if item_id == requested_id:
            return
        if item_id == STATE.get("preview_rendered_id"):
            previous_timer = STATE.get("preview_timer")
            if previous_timer is not None:
                previous_timer.cancel()
            STATE["preview_timer"] = None
            if requested_id is not None:
                STATE["preview_serial"] += 1
                STATE["preview_requested_id"] = None
            return
        previous_timer = STATE.get("preview_timer")
        if previous_timer is not None:
            previous_timer.cancel()
        STATE["preview_serial"] += 1
        serial = STATE["preview_serial"]
        STATE["preview_requested_id"] = item_id
        record = dict(record)
        timer = threading.Timer(
            PREVIEW_HOVER_DELAY_SECONDS,
            _start_selected_preview,
            args=(serial, rev, item_id, record),
        )
        timer.name = f"fd-preview-delay-{serial}"
        timer.daemon = True
        STATE["preview_timer"] = timer

    timer.start()


def result_rank(record: dict[str, Any], query: str, mode: str) -> tuple[Any, ...]:
    name = record["name"].casefold()
    stem = Path(record["name"]).stem.casefold()
    q = query.casefold()
    if mode != "literal":
        return (len(name), name, record["path"].casefold())
    if name == q:
        bucket = 0
    elif stem == q:
        bucket = 1
    elif name.startswith(q):
        bucket = 2
    elif any(part.startswith(q) for part in name.replace("-", " ").replace("_", " ").split()):
        bucket = 3
    else:
        bucket = 4
    return (bucket, len(name), name, len(record["path"]), record["path"].casefold())


def item_from_record(record: dict[str, Any], *, selected_preview: str | None = None) -> dict[str, Any]:
    path = record["path"]
    name = record["name"]
    parent = os.path.dirname(path)
    is_dir = record["is_dir"]
    extension = Path(name).suffix[1:] if Path(name).suffix else ""
    accessories = [{"text": "Folder" if is_dir else (extension.upper() if extension else "File")}]
    instruction = (
        f"Press **Enter** to open this {'folder' if is_dir else 'file'}."
        if is_dir
        else "Hover to load an inline preview, or press **Enter** to open this file."
    )
    preview_markdown = f"### {markdown_escape(name)}\n\n{instruction}"
    if selected_preview is not None:
        preview_markdown = selected_preview
    return {
        "id": path,
        "title": name,
        "subtitle": parent,
        "icon": icon_for(path, is_dir),
        "section": root_label(record["root"]),
        "lines": 1,
        "accessories": accessories,
        "actions": [
            {"id": "default", "title": "Open", "icon": "open"},
            {"id": "open_parent", "title": "Open containing folder", "icon": "folder", "shortcut": "ctrl+shift+o"},
            {"id": "copy_path", "title": "Copy full path", "icon": "copy", "shortcut": "ctrl+shift+c"},
            {"id": "copy_name", "title": "Copy file name", "icon": "document"},
            {"id": "copy_parent", "title": "Copy containing folder", "icon": "folder"},
            {"id": "paste_path", "title": "Paste path into previous app", "icon": "paste"},
        ],
        "preview": {
            "markdown": preview_markdown,
            "metadata": [
                {"label": "Full path", "text": path, "icon": "file" if not is_dir else "folder"},
                {"label": "Containing folder", "text": parent, "icon": "folder"},
                {"label": "Type", "text": "Folder" if is_dir else (f".{extension} file" if extension else "File")},
                {"label": "Search root", "text": record["root"], "icon": "search"},
            ],
        },
    }


def _apply_selected_preview(
    items: list[dict[str, Any]],
    selected_id: str | None,
    selected_preview: str | None,
) -> None:
    if selected_id is None or selected_preview is None:
        return
    for index, item in enumerate(items):
        if item["id"] != selected_id:
            continue
        updated_item = dict(item)
        updated_preview = dict(item.get("preview") or {})
        updated_preview["markdown"] = selected_preview
        updated_item["preview"] = updated_preview
        items[index] = updated_item
        return


def render_results(
    rev: int,
    query: str,
    records: list[dict[str, Any]],
    limited: bool,
    *,
    selected_id: str | None = None,
    selected_preview: str | None = None,
    reuse_items: bool = False,
) -> None:
    if not records:
        with STATE_LOCK:
            STATE["results"] = []
            STATE["items"] = {}
            STATE["results_limited"] = False
            STATE["base_item_payloads"] = {}
        settings = STATE["settings"]
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "list",
                "page": page("fd:search", "fd · No matches", root=True),
                "elementId": "fd-results",
                "placeholder": "Try a shorter filename or different filters",
                "empty": {
                    "icon": "search",
                    "title": f"No matches for “{query}”",
                    "hint": root_summary(settings),
                    "action": {"id": "settings", "title": "Review filters", "icon": "settings"},
                },
                "actions": SEARCH_ACTIONS,
                "floatingAction": {"id": "settings", "title": "Settings", "icon": "settings"},
                "items": [],
            }
        )
        return

    items: list[dict[str, Any]] | None = None
    if reuse_items:
        # Preview updates should not repeat icon extraction for every result.
        with STATE_LOCK:
            cached_items = STATE["base_item_payloads"]
            if len(cached_items) == len(records) and all(record["path"] in cached_items for record in records):
                items = [dict(cached_items[record["path"]]) for record in records]

    if items is None:
        items = [item_from_record(record) for record in records]
        base_item_payloads = {item["id"]: item for item in items}
    else:
        base_item_payloads = None
    _apply_selected_preview(items, selected_id, selected_preview)

    with STATE_LOCK:
        STATE["results"] = records
        STATE["items"] = {item["id"]: record for item, record in zip(items, records)}
        STATE["results_limited"] = limited
        if base_item_payloads is not None:
            STATE["base_item_payloads"] = base_item_payloads
    count_text = f"{len(items)}+ matches" if limited else f"{len(items)} match{'es' if len(items) != 1 else ''}"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": page("fd:search", f"fd · {count_text}", root=True),
            "elementId": "fd-results",
            "placeholder": "Search filenames…",
            "preview": {"enabled": True, "wide": False},
            "actions": SEARCH_ACTIONS,
            "floatingAction": {"id": "settings", "title": "Settings", "icon": "settings"},
            "items": items,
        }
    )


def terminate_process(process: subprocess.Popen[bytes] | None) -> None:
    if process is None or process.poll() is not None:
        return
    try:
        process.terminate()
    except OSError:
        pass


def cancel_search() -> int:
    with STATE_LOCK:
        STATE["search_serial"] += 1
        serial = STATE["search_serial"]
        process = STATE.get("active_process")
        STATE["active_process"] = None
        preview_timer = STATE.get("preview_timer")
        STATE["preview_timer"] = None
        STATE["preview_serial"] += 1
        STATE["preview_requested_id"] = None
        STATE["preview_rendered_id"] = None
    if preview_timer is not None:
        preview_timer.cancel()
    terminate_process(process)
    return serial


def build_fd_command(executable: str, query: str, settings: dict[str, Any]) -> list[str]:
    args = [executable, "--absolute-path", "--color=never", "--print0"]
    if settings["mode"] == "literal":
        args.append("--fixed-strings")
    elif settings["mode"] == "glob":
        args.append("--glob")
    if settings["item_type"] == "files":
        args.extend(["--type", "file"])
    elif settings["item_type"] == "folders":
        args.extend(["--type", "directory"])
    if settings["hidden"]:
        args.append("--hidden")
    if settings["ignored"]:
        args.append("--no-ignore")
    if settings["follow"]:
        args.append("--follow")
    if settings["full_path"]:
        args.append("--full-path")
    for extension in include_extensions(settings["includes"]):
        args.extend(["--extension", extension])
    for rule in settings["excludes"]:
        args.extend(["--exclude", fd_exclude_rule(rule)])
    args.extend(["--", query, *settings["roots"]])
    return args


def run_search(serial: int, rev: int, query: str, settings: dict[str, Any], executable: str) -> None:
    process: subprocess.Popen[bytes] | None = None
    stopped_for_limit = False
    try:
        args = build_fd_command(executable, query, settings)
        log("fd search:", args)
        process = subprocess.Popen(
            args,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            creationflags=NO_WINDOW,
        )
        with STATE_LOCK:
            if serial != STATE["search_serial"] or STATE["closing"]:
                terminate_process(process)
                return
            STATE["active_process"] = process

        assert process.stdout is not None
        assert process.stderr is not None
        stderr_buffer = bytearray()

        def drain_stderr() -> None:
            while True:
                chunk = process.stderr.read(8192)
                if not chunk:
                    return
                # Keep the UI error useful without retaining unbounded diagnostics.
                if len(stderr_buffer) < 65536:
                    stderr_buffer.extend(chunk[: 65536 - len(stderr_buffer)])

        stderr_thread = threading.Thread(target=drain_stderr, name=f"fd-stderr-{serial}", daemon=True)
        stderr_thread.start()
        accepted: list[dict[str, Any]] = []
        seen: set[str] = set()
        pending = b""
        display_limit = settings["max_results"]
        scan_limit = min(3000, max(display_limit * 5, display_limit + 400))

        while True:
            with STATE_LOCK:
                current = serial == STATE["search_serial"] and not STATE["closing"]
            if not current:
                terminate_process(process)
                return
            chunk = process.stdout.read(65536)
            if not chunk:
                break
            pending += chunk
            parts = pending.split(b"\0")
            pending = parts.pop()
            for raw_path in parts:
                if not raw_path:
                    continue
                path = os.path.normpath(os.fsdecode(raw_path))
                key = os.path.normcase(path)
                if key in seen:
                    continue
                if settings["includes"] and not any(matches_filter(path, rule) for rule in settings["includes"]):
                    continue
                if any(matches_filter(path, rule) for rule in settings["excludes"]):
                    continue
                seen.add(key)
                if settings["item_type"] == "folders":
                    is_dir = True
                elif settings["item_type"] == "files":
                    is_dir = False
                else:
                    is_dir = os.path.isdir(path)
                accepted.append(
                    {
                        "path": path,
                        "name": os.path.basename(path) or path,
                        "root": path_root(path, settings["roots"]),
                        "is_dir": is_dir,
                    }
                )
                if len(accepted) >= scan_limit:
                    stopped_for_limit = True
                    terminate_process(process)
                    break
            if stopped_for_limit:
                break

        return_code = process.wait()
        stderr_thread.join(timeout=1)
        error_text = bytes(stderr_buffer).decode("utf-8", errors="replace").strip()

        with STATE_LOCK:
            current = serial == STATE["search_serial"] and not STATE["closing"]
            if STATE.get("active_process") is process:
                STATE["active_process"] = None
        if not current:
            return
        if return_code != 0 and not stopped_for_limit:
            with STATE_LOCK:
                if serial == STATE["search_serial"] and not STATE["closing"]:
                    render_search_error(
                        rev,
                        "fd could not run this search",
                        error_text or f"fd exited with code {return_code}.",
                    )
            return
        if error_text:
            log("fd warning:", error_text)

        accepted.sort(key=lambda record: result_rank(record, query, settings["mode"]))
        limited = len(accepted) > display_limit or stopped_for_limit
        with STATE_LOCK:
            if serial == STATE["search_serial"] and not STATE["closing"]:
                render_results(rev, query, accepted[:display_limit], limited)
    except FileNotFoundError:
        with STATE_LOCK:
            if serial == STATE["search_serial"] and not STATE["closing"]:
                render_fd_installer(rev)
    except Exception as exc:
        log("search failed:", repr(exc))
        with STATE_LOCK:
            if serial == STATE["search_serial"] and not STATE["closing"]:
                render_search_error(rev, "The search failed", str(exc))
    finally:
        with STATE_LOCK:
            if STATE.get("active_process") is process:
                STATE["active_process"] = None


def start_search(rev: int, text: str, *, history: str = "none") -> None:
    query = text.strip()
    STATE["current_query"] = text
    serial = cancel_search()
    with STATE_LOCK:
        STATE["results"] = []
        STATE["items"] = {}
        STATE["results_limited"] = False
        STATE["base_item_payloads"] = {}
        STATE["preview_cache"].clear()
    if not query:
        render_search_prompt(rev, history=history)
        return

    settings = copy.deepcopy(STATE["settings"])
    executable = resolve_executable(settings["executable"])
    if executable is None:
        render_fd_installer(rev)
        return
    missing_roots = [root for root in settings["roots"] if not os.path.isdir(root)]
    if missing_roots:
        render_search_error(rev, "A search root is unavailable", missing_roots[0])
        return

    render_loading(rev, query, history=history)
    threading.Thread(
        target=run_search,
        args=(serial, rev, query, settings, executable),
        name=f"fd-search-{serial}",
        daemon=True,
    ).start()


def validate_form(values: dict[str, Any]) -> tuple[dict[str, Any] | None, dict[str, str]]:
    errors: dict[str, str] = {}
    try:
        roots = roots_from_values(values.get("roots", ""), values.get("quick_root", ""))
    except (OSError, ValueError) as exc:
        roots = []
        errors["roots"] = str(exc)
    if not roots:
        errors["roots"] = "Add at least one drive or folder."
    else:
        missing = [root for root in roots if not os.path.isdir(root)]
        if missing:
            errors["roots"] = f"Folder does not exist or is unavailable: {missing[0]}"

    executable_value = str(values.get("executable", "fd")).strip().strip('"') or "fd"
    if resolve_executable(executable_value) is None:
        errors["executable"] = "fd was not found. Install it or select the full path to fd.exe."
    try:
        max_results = int(values.get("max_results", 150))
        if not 20 <= max_results <= 500:
            raise ValueError
    except (TypeError, ValueError):
        max_results = 150
        errors["max_results"] = "Choose a value from 20 to 500."

    if errors:
        return None, errors
    settings = sanitized_settings(
        {
            "configured": True,
            "executable": executable_value,
            "roots": roots,
            "includes": split_rules(values.get("includes", "")),
            "excludes": split_rules(values.get("excludes", "")),
            "mode": values.get("mode", "literal"),
            "item_type": values.get("item_type", "files"),
            "max_results": max_results,
            "hidden": values.get("hidden", False),
            "ignored": values.get("ignored", False),
            "follow": values.get("follow", False),
            "full_path": values.get("full_path", False),
        }
    )
    return settings, {}


def handle_settings_submit(values: dict[str, Any]) -> None:
    settings, errors = validate_form(values)
    if errors:
        preview = copy.deepcopy(STATE["settings"])
        preview.update(
            {
                "executable": str(values.get("executable", preview["executable"])),
                "includes": split_rules(values.get("includes", "")),
                "excludes": split_rules(values.get("excludes", "")),
                "mode": values.get("mode", preview["mode"]),
                "item_type": values.get("item_type", preview["item_type"]),
                "hidden": bool(values.get("hidden", False)),
                "ignored": bool(values.get("ignored", False)),
                "follow": bool(values.get("follow", False)),
                "full_path": bool(values.get("full_path", False)),
            }
        )
        try:
            preview["roots"] = roots_from_values(values.get("roots", ""), values.get("quick_root", ""))
        except (OSError, ValueError):
            pass
        try:
            preview["max_results"] = int(values.get("max_results", preview["max_results"]))
        except (TypeError, ValueError):
            pass
        old_settings = STATE["settings"]
        STATE["settings"] = preview
        render_settings(0, history="none", errors=errors, first_run=not old_settings.get("configured", False))
        STATE["settings"] = old_settings
        return

    assert settings is not None
    STATE["settings"] = settings
    save_settings()
    command("toast", text="fd search settings saved", style="success")
    start_search(0, STATE["current_query"], history="replace")


def handle_action(item_id: str, action: str) -> None:
    if not item_id:
        if action in INSTALL_COMMANDS:
            launch_visible_installer(action)
        elif action == "settings":
            cancel_search()
            render_settings(0, first_run=not STATE["settings"].get("configured", False))
        elif action == "help":
            cancel_search()
            render_help()
        elif action == "refresh":
            start_search(0, STATE["current_query"])
        elif action == "clear_icons_cache":
            # Cancel first so a result renderer cannot hold STATE_LOCK while
            # this action owns ICON_CACHE_LOCK.
            cancel_search()
            removed = clear_icon_cache()
            message = "No cached file icons to clear" if removed == 0 else f"Cleared {removed} cached file icon(s)"
            command("toast", text=message, style="success")
            start_search(0, STATE["current_query"])
        elif action == "check_fd":
            check_fd_again()
        elif action == "open_fd_docs":
            command("open", url="https://github.com/sharkdp/fd#installation")
        return

    record = STATE["items"].get(item_id)
    if not record:
        return
    path = record["path"]
    parent = os.path.dirname(path)
    if action == "default":
        command("open", path=path)
        command("hide")
    elif action == "open_parent":
        command("open", path=parent)
        command("hide")
    elif action == "copy_path":
        command("copy", text=path)
    elif action == "copy_name":
        command("copy", text=record["name"])
    elif action == "copy_parent":
        command("copy", text=parent)
    elif action == "paste_path":
        command("paste", text=path)


def return_to_search(rev: int = 0) -> None:
    start_search(rev, STATE["current_query"])


def check_fd_again() -> None:
    settings = STATE["settings"]
    if resolve_executable(settings["executable"]) is None:
        render_fd_installer(0)
    elif settings.get("configured", False):
        command("toast", text="fd is ready", style="success")
        start_search(0, STATE["current_query"])
    else:
        command("toast", text="fd is ready — choose your search locations", style="success")
        render_settings(0, history="replace", first_run=True)


def handle_storage(message: dict[str, Any]) -> None:
    if message.get("requestId") != SETTINGS_REQUEST_ID:
        return
    raw_value = message.get("value")
    settings = default_settings()
    if raw_value:
        try:
            decoded = json.loads(raw_value) if isinstance(raw_value, str) else raw_value
            settings = sanitized_settings(decoded)
        except (json.JSONDecodeError, TypeError, ValueError) as exc:
            log("Could not decode stored settings:", exc)
    STATE["settings"] = settings
    STATE["loaded"] = True
    if resolve_executable(settings["executable"]) is None:
        render_fd_installer(0)
    elif settings["configured"]:
        start_search(0, STATE["current_query"])
    else:
        render_settings(0, history="none", first_run=True)


def handle_message(message: dict[str, Any]) -> bool:
    kind = message.get("type")
    if kind == "close":
        with STATE_LOCK:
            STATE["closing"] = True
        cancel_search()
        return False
    if kind == "init":
        STATE["current_query"] = str(message.get("query", ""))
        render_boot(0)
        command("storage", op="get", key=SETTINGS_KEY, requestId=SETTINGS_REQUEST_ID)
    elif kind == "query":
        STATE["current_query"] = str(message.get("text", ""))
        if STATE["loaded"] and STATE["screen"] == "search":
            start_search(int(message.get("rev", 0)), STATE["current_query"])
    elif kind == "select":
        request_file_preview(int(message.get("rev", 0)), str(message.get("id", "")))
    elif kind == "storage":
        handle_storage(message)
    elif kind == "submit" and STATE["screen"] == "settings":
        handle_settings_submit(message.get("values") or {})
    elif kind == "action":
        handle_action(str(message.get("id", "")), str(message.get("action", "default")))
    elif kind == "back":
        target = message.get("toPageId")
        if target == "fd:settings":
            render_settings(int(message.get("rev", 0)), history="none")
        elif target == "fd:help":
            render_help(int(message.get("rev", 0)), history="none")
        else:
            return_to_search(int(message.get("rev", 0)))
    elif kind == "navigate":
        target = message.get("targetPageId")
        if target == "fd:settings":
            render_settings(int(message.get("rev", 0)), history="none")
        elif target == "fd:help":
            render_help(int(message.get("rev", 0)), history="none")
        else:
            return_to_search(int(message.get("rev", 0)))
    return True


def main() -> None:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
            if isinstance(message, dict) and not handle_message(message):
                break
        except json.JSONDecodeError:
            log("Ignored malformed JSON from host")
        except Exception as exc:
            log("Message handler failed:", repr(exc))
            send(
                {
                    "type": "render",
                    "rev": int(message.get("rev", 0)) if isinstance(message, dict) else 0,
                    "view": "detail",
                    "detail": {"markdown": f"# fd plugin error\n\n```\n{exc}\n```"},
                }
            )
    with STATE_LOCK:
        STATE["closing"] = True
    cancel_search()


if __name__ == "__main__":
    main()
