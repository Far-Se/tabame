#!/usr/bin/env python3
"""
Tabame Image Converter Plugin
Keyword: img

Features:
- Convert between 20+ image formats
- Batch convert folders
- Resize with multiple modes
- Compress/optimize
- Rotate & flip
- Apply filters
- Add text watermark
- Social media presets
- Favicon generator
- Strip EXIF
"""

import sys
import json
import os
import re
import io
import base64
import threading
import subprocess
from pathlib import Path

# ── Pillow imports ──
try:
    from PIL import Image, ImageFilter, ImageEnhance, ImageOps, ImageDraw, ImageFont
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False

try:
    import pillow_avif
    AVIF_AVAILABLE = True
except ImportError:
    AVIF_AVAILABLE = False

# ── Constants ──
SUPPORTED_READ_FORMATS = {
    "png": "PNG", "jpg": "JPEG", "jpeg": "JPEG", "webp": "WEBP", "avif": "AVIF",
    "gif": "GIF", "bmp": "BMP", "tiff": "TIFF", "tif": "TIFF", "ico": "ICO",
    "heic": "HEIC", "heif": "HEIF", "ppm": "PPM", "pgm": "PGM", "pbm": "PBM",
    "pcx": "PCX", "tga": "TGA", "sgi": "SGI", "eps": "EPS", "pdf": "PDF",
    "psd": "PSD", "xpm": "XPM", "xbm": "XBM", "dds": "DDS", "icns": "ICNS",
}

SUPPORTED_WRITE_FORMATS = {
    "png": "PNG", "jpg": "JPEG", "jpeg": "JPEG", "webp": "WEBP", "avif": "AVIF",
    "gif": "GIF", "bmp": "BMP", "tiff": "TIFF", "tif": "TIFF", "ico": "ICO",
    "ppm": "PPM", "pgm": "PGM", "pbm": "PBM", "pcx": "PCX", "tga": "TGA",
    "pdf": "PDF", "eps": "EPS",
}

SOCIAL_SIZES = {
    "instagram_post": (1080, 1080), "instagram_story": (1080, 1920), "instagram_reel": (1080, 1920),
    "twitter_post": (1200, 675), "twitter_header": (1500, 500),
    "facebook_post": (1200, 630), "facebook_cover": (820, 312),
    "linkedin_post": (1200, 627), "linkedin_banner": (1584, 396),
    "youtube_thumbnail": (1280, 720), "youtube_banner": (2560, 1440),
    "pinterest_pin": (1000, 1500), "tiktok_video": (1080, 1920),
    "discord_avatar": (128, 128), "discord_banner": (600, 240),
    "twitch_profile": (800, 800), "twitch_banner": (1200, 480),
    "github_avatar": (420, 420),
    "favicon_16": (16, 16), "favicon_32": (32, 32), "favicon_48": (48, 48),
    "favicon_64": (64, 64), "favicon_128": (128, 128), "favicon_256": (256, 256), "favicon_512": (512, 512),
    "apple_touch_57": (57, 57), "apple_touch_72": (72, 72), "apple_touch_114": (114, 114),
    "apple_touch_144": (144, 144), "apple_touch_180": (180, 180),
    "hd_720": (1280, 720), "hd_1080": (1920, 1080), "hd_1440": (2560, 1440), "hd_4k": (3840, 2160),
    "a4_300dpi": (2480, 3508), "a4_150dpi": (1240, 1754), "a5_300dpi": (1748, 2480),
    "letter_300dpi": (2550, 3300), "passport_photo": (600, 600),
    "id_photo_35x45": (413, 531), "wallet_photo": (300, 400),
}

RESIZE_MODES = {
    "fit": "Fit inside (maintain aspect ratio)",
    "fill": "Fill/cover (crop to fit)",
    "stretch": "Stretch (ignore aspect ratio)",
    "crop_center": "Crop from center",
    "crop_top": "Crop from top",
    "crop_bottom": "Crop from bottom",
    "crop_left": "Crop from left",
    "crop_right": "Crop from right",
    "percent": "Percentage scale",
    "long_edge": "Fit long edge",
    "short_edge": "Fit short edge",
}

FILTERS = {
    "grayscale": "Grayscale", "sepia": "Sepia", "invert": "Invert colors",
    "blur": "Gaussian Blur", "sharpen": "Sharpen", "edge_enhance": "Edge Enhance",
    "emboss": "Emboss", "contour": "Contour",
    "brightness_up": "Brightness +30%", "brightness_down": "Brightness -30%",
    "contrast_up": "Contrast +30%", "contrast_down": "Contrast -30%",
    "saturation_up": "Saturation +30%", "saturation_down": "Saturation -30%",
    "posterize": "Posterize (reduce colors)", "solarize": "Solarize",
    "auto_contrast": "Auto Contrast", "auto_color": "Auto Color Balance",
}

ROTATE_OPTIONS = {
    "90cw": "Rotate 90 clockwise", "90ccw": "Rotate 90 counter-clockwise",
    "180": "Rotate 180", "flip_h": "Flip horizontal",
    "flip_v": "Flip vertical", "flip_both": "Flip both axes",
}

# ── State ──
state = {
    "screen": "root", "selected_files": [], "output_dir": "",
    "output_format": "png", "resize_mode": "fit", "resize_w": "", "resize_h": "",
    "resize_percent": "100", "quality": "85", "filter": "", "rotate": "",
    "watermark_text": "", "watermark_pos": "bottom_right", "watermark_size": "24",
    "watermark_color": "#FFFFFF", "watermark_opacity": "128", "dpi": "",
    "strip_exif": False, "preserve_structure": False, "batch_recursive": False,
    "social_preset": "", "last_error": "", "last_success": "", "config": {},
}

# ── Helpers ──

def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()

def log(*a):
    print(*a, file=sys.stderr, flush=True)

def load_config():
    cfg = {}
    try:
        if os.path.exists("config.json"):
            with open("config.json", "r", encoding="utf-8") as f:
                cfg = json.load(f)
    except Exception as e:
        log("Config load error:", e)
    return cfg

def save_config(cfg):
    try:
        with open("config.json", "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2)
    except Exception as e:
        log("Config save error:", e)

def format_bytes(n):
    for unit in ["B", "KB", "MB", "GB"]:
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"

def get_image_info(path):
    try:
        with Image.open(path) as img:
            fmt = img.format or "Unknown"
            mode = img.mode
            w, h = img.size
            dpi = img.info.get("dpi", (None, None))
            dpi_str = f"{int(dpi[0])}" if dpi[0] else "—"
            file_size = os.path.getsize(path)
            exif_count = 0
            try:
                exif = img._getexif()
                if exif: exif_count = len(exif)
            except: pass
            return {"format": fmt, "mode": mode, "width": w, "height": h,
                    "dpi": dpi_str, "size": format_bytes(file_size), "exif_count": exif_count, "path": str(path)}
    except Exception as e:
        return {"error": str(e), "path": str(path)}

def apply_resize(img, mode, w, h, percent=100):
    orig_w, orig_h = img.size
    if mode == "percent":
        factor = percent / 100.0
        return img.resize((int(orig_w * factor), int(orig_h * factor)), Image.LANCZOS)
    if mode == "stretch":
        return img.resize((w, h), Image.LANCZOS)
    if mode == "fit":
        img.thumbnail((w, h), Image.LANCZOS)
        return img
    if mode == "fill":
        orig_ratio, target_ratio = orig_w / orig_h, w / h
        if orig_ratio > target_ratio:
            new_w, new_h = int(h * orig_ratio), h
        else:
            new_w, new_h = w, int(w / orig_ratio)
        img = img.resize((new_w, new_h), Image.LANCZOS)
        left, top = (new_w - w) // 2, (new_h - h) // 2
        return img.crop((left, top, left + w, top + h))
    if mode == "long_edge":
        max_dim = max(orig_w, orig_h)
        if max_dim <= w: return img
        factor = w / max_dim
        return img.resize((int(orig_w * factor), int(orig_h * factor)), Image.LANCZOS)
    if mode == "short_edge":
        min_dim = min(orig_w, orig_h)
        factor = w / min_dim
        return img.resize((int(orig_w * factor), int(orig_h * factor)), Image.LANCZOS)
    if mode.startswith("crop"):
        orig_ratio, target_ratio = orig_w / orig_h, w / h
        if orig_ratio > target_ratio:
            new_w, new_h = int(h * orig_ratio), h
        else:
            new_w, new_h = w, int(w / orig_ratio)
        img = img.resize((new_w, new_h), Image.LANCZOS)
        if mode == "crop_center": left, top = (new_w - w) // 2, (new_h - h) // 2
        elif mode == "crop_top": left, top = (new_w - w) // 2, 0
        elif mode == "crop_bottom": left, top = (new_w - w) // 2, new_h - h
        elif mode == "crop_left": left, top = 0, (new_h - h) // 2
        elif mode == "crop_right": left, top = new_w - w, (new_h - h) // 2
        else: left, top = (new_w - w) // 2, (new_h - h) // 2
        return img.crop((left, top, left + w, top + h))
    return img

def apply_filter(img, filter_name):
    if filter_name == "grayscale":
        if img.mode in ("RGBA", "P"): img = img.convert("RGB")
        return ImageOps.grayscale(img).convert("RGB")
    if filter_name == "sepia":
        if img.mode in ("RGBA", "P"): img = img.convert("RGB")
        gray = ImageOps.grayscale(img)
        sepia = Image.new("RGB", gray.size)
        pixels, sepia_pixels = gray.load(), sepia.load()
        for y in range(gray.size[1]):
            for x in range(gray.size[0]):
                r = g = b = pixels[x, y]
                sepia_pixels[x, y] = (min(255, int(r * 1.08)), min(255, int(g * 0.94)), min(255, int(b * 0.82)))
        return sepia
    if filter_name == "invert":
        if img.mode in ("RGBA", "P"): img = img.convert("RGB")
        return ImageOps.invert(img)
    if filter_name == "blur": return img.filter(ImageFilter.GaussianBlur(radius=2))
    if filter_name == "sharpen": return img.filter(ImageFilter.SHARPEN)
    if filter_name == "edge_enhance": return img.filter(ImageFilter.EDGE_ENHANCE)
    if filter_name == "emboss": return img.filter(ImageFilter.EMBOSS)
    if filter_name == "contour": return img.filter(ImageFilter.CONTOUR)
    if filter_name == "brightness_up": return ImageEnhance.Brightness(img).enhance(1.3)
    if filter_name == "brightness_down": return ImageEnhance.Brightness(img).enhance(0.7)
    if filter_name == "contrast_up": return ImageEnhance.Contrast(img).enhance(1.3)
    if filter_name == "contrast_down": return ImageEnhance.Contrast(img).enhance(0.7)
    if filter_name == "saturation_up": return ImageEnhance.Color(img).enhance(1.3)
    if filter_name == "saturation_down": return ImageEnhance.Color(img).enhance(0.7)
    if filter_name == "posterize":
        if img.mode in ("RGBA", "P"): img = img.convert("RGB")
        return ImageOps.posterize(img, 4)
    if filter_name == "solarize":
        if img.mode in ("RGBA", "P"): img = img.convert("RGB")
        return ImageOps.solarize(img, threshold=128)
    if filter_name == "auto_contrast":
        if img.mode in ("RGBA", "P"): img = img.convert("RGB")
        return ImageOps.autocontrast(img)
    if filter_name == "auto_color":
        if img.mode in ("RGBA", "P"): img = img.convert("RGB")
        return ImageOps.equalize(img)
    return img

def apply_rotate(img, rotate_option):
    if rotate_option == "90cw": return img.rotate(-90, expand=True)
    if rotate_option == "90ccw": return img.rotate(90, expand=True)
    if rotate_option == "180": return img.rotate(180, expand=True)
    if rotate_option == "flip_h": return img.transpose(Image.FLIP_LEFT_RIGHT)
    if rotate_option == "flip_v": return img.transpose(Image.FLIP_TOP_BOTTOM)
    if rotate_option == "flip_both": return img.transpose(Image.FLIP_LEFT_RIGHT).transpose(Image.FLIP_TOP_BOTTOM)
    return img

def apply_watermark(img, text, position, size, color, opacity):
    if not text: return img
    overlay = img.copy().convert("RGBA")
    draw = ImageDraw.Draw(overlay)
    try:
        font = ImageFont.truetype("arial.ttf", size)
    except:
        try:
            font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", size)
        except:
            font = ImageFont.load_default()
    if color.startswith("#"):
        color = color.lstrip("#")
        if len(color) == 6:
            r, g, b = int(color[0:2], 16), int(color[2:4], 16), int(color[4:6], 16)
        elif len(color) == 3:
            r, g, b = int(color[0]*2, 16), int(color[1]*2, 16), int(color[2]*2, 16)
        else: r, g, b = 255, 255, 255
    else: r, g, b = 255, 255, 255
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    iw, ih = img.size
    padding = 10
    if position == "top_left": x, y = padding, padding
    elif position == "top_right": x, y = iw - tw - padding, padding
    elif position == "bottom_left": x, y = padding, ih - th - padding
    elif position == "bottom_right": x, y = iw - tw - padding, ih - th - padding
    elif position == "center": x, y = (iw - tw) // 2, (ih - th) // 2
    elif position == "top_center": x, y = (iw - tw) // 2, padding
    elif position == "bottom_center": x, y = (iw - tw) // 2, ih - th - padding
    else: x, y = iw - tw - padding, ih - th - padding
    alpha = int(opacity)
    draw.text((x, y), text, fill=(r, g, b, alpha), font=font)
    if img.mode != "RGBA": img = img.convert("RGBA")
    result = Image.alpha_composite(img, overlay)
    if img.mode == "RGB": result = result.convert("RGB")
    return result

def convert_image(src_path, dst_path, options):
    with Image.open(src_path) as img:
        try: img = ImageOps.exif_transpose(img)
        except: pass
        out_fmt = options.get("format", "PNG")
        if out_fmt in ("JPEG", "JPG") and img.mode in ("RGBA", "P", "LA"):
            background = Image.new("RGB", img.size, (255, 255, 255))
            if img.mode == "P": img = img.convert("RGBA")
            if img.mode in ("RGBA", "LA"):
                background.paste(img, mask=img.split()[-1] if img.mode in ("RGBA", "LA") else None)
                img = background
            else: img = img.convert("RGB")
        elif out_fmt == "PNG" and img.mode not in ("RGB", "RGBA", "P", "L", "LA"): img = img.convert("RGB")
        elif out_fmt == "WEBP" and img.mode not in ("RGB", "RGBA", "P", "L"): img = img.convert("RGB")
        elif out_fmt == "GIF" and img.mode not in ("P", "L"): img = img.convert("P", palette=Image.ADAPTIVE, colors=256)
        elif out_fmt == "ICO":
            if img.mode not in ("RGB", "RGBA"): img = img.convert("RGBA")
        elif out_fmt == "AVIF":
            if img.mode not in ("RGB", "RGBA"): img = img.convert("RGB")
        elif out_fmt == "TIFF":
            if img.mode not in ("RGB", "RGBA", "L", "CMYK"): img = img.convert("RGB")
        resize_mode = options.get("resize_mode", "")
        if resize_mode and resize_mode != "none":
            w = options.get("resize_w", 0)
            h = options.get("resize_h", 0)
            percent = options.get("resize_percent", 100)
            if resize_mode == "percent": img = apply_resize(img, "percent", 0, 0, percent)
            elif w > 0 and h > 0: img = apply_resize(img, resize_mode, w, h)
        social_preset = options.get("social_preset", "")
        if social_preset and social_preset in SOCIAL_SIZES:
            w, h = SOCIAL_SIZES[social_preset]
            img = apply_resize(img, "fill", w, h)
        filter_name = options.get("filter", "")
        if filter_name: img = apply_filter(img, filter_name)
        rotate_opt = options.get("rotate", "")
        if rotate_opt: img = apply_rotate(img, rotate_opt)
        wm_text = options.get("watermark_text", "")
        if wm_text:
            img = apply_watermark(img, wm_text, options.get("watermark_pos", "bottom_right"),
                                  options.get("watermark_size", 24), options.get("watermark_color", "#FFFFFF"),
                                  options.get("watermark_opacity", 128))
        dpi = options.get("dpi", None)
        save_kwargs = {}
        if dpi and dpi > 0: save_kwargs["dpi"] = (dpi, dpi)
        if options.get("strip_exif", False): save_kwargs["exif"] = b""
        quality = options.get("quality", 85)
        if out_fmt in ("JPEG", "WEBP"):
            save_kwargs["quality"] = quality
            save_kwargs["optimize"] = True
        elif out_fmt == "PNG": save_kwargs["optimize"] = True
        elif out_fmt == "GIF": save_kwargs["optimize"] = True
        elif out_fmt == "TIFF": save_kwargs["compression"] = "tiff_lzw"
        elif out_fmt == "AVIF": save_kwargs["quality"] = quality
        if out_fmt == "ICO":
            sizes = [(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
            valid_sizes = [s for s in sizes if s[0] <= img.size[0] and s[1] <= img.size[1]]
            if not valid_sizes: valid_sizes = [img.size]
            icons = []
            for s in valid_sizes:
                icon = img.copy()
                icon.thumbnail(s, Image.LANCZOS)
                final = Image.new("RGBA", s, (0, 0, 0, 0))
                x, y = (s[0] - icon.size[0]) // 2, (s[1] - icon.size[1]) // 2
                final.paste(icon, (x, y))
                icons.append(final)
            icons[0].save(dst_path, format="ICO", sizes=[(i.size[0], i.size[1]) for i in icons])
            return
        img.save(dst_path, format=out_fmt, **save_kwargs)

def find_images_in_folder(folder, recursive=False):
    exts = set(SUPPORTED_READ_FORMATS.keys())
    images = []
    if recursive:
        for root, dirs, files in os.walk(folder):
            for f in files:
                ext = f.lower().rsplit(".", 1)[-1] if "." in f else ""
                if ext in exts: images.append(os.path.join(root, f))
    else:
        for f in os.listdir(folder):
            ext = f.lower().rsplit(".", 1)[-1] if "." in f else ""
            if ext in exts: images.append(os.path.join(folder, f))
    return sorted(images)

def get_unique_path(path):
    if not os.path.exists(path): return path
    base, ext = os.path.splitext(path)
    i = 1
    while True:
        new_path = f"{base}_{i}{ext}"
        if not os.path.exists(new_path): return new_path
        i += 1

def build_output_path(src_path, output_dir, out_format, preserve_structure=False, base_dir=""):
    src_name = os.path.basename(src_path)
    name_without_ext = os.path.splitext(src_name)[0]
    ext = out_format.lower()
    if ext == "jpeg": ext = "jpg"
    elif ext == "tiff": ext = "tif"
    out_name = f"{name_without_ext}.{ext}"
    if preserve_structure and base_dir:
        rel_path = os.path.relpath(os.path.dirname(src_path), base_dir)
        out_dir = os.path.join(output_dir, rel_path)
        os.makedirs(out_dir, exist_ok=True)
        return os.path.join(out_dir, out_name)
    else:
        os.makedirs(output_dir, exist_ok=True)
        return get_unique_path(os.path.join(output_dir, out_name))


# ── Render Functions ──

def render_root(rev, text):
    items = []
    text_lower = text.strip().lower()

    # Keep the primary image actions together in the Ctrl+K menu when `img`
    # is opened without an additional query.
    items.append({
        "id": "pick_image",
        "title": "📂 Image input",
        "subtitle": "Pick an image, batch-convert a folder, or use a copied path",
        "icon": "folder",
        "actions": [
            {"id": "pick_image_file", "title": "Pick image file", "icon": "file"},
            {"id": "batch_convert", "title": "Batch Convert a folder", "icon": "folder"},
            {"id": "use_clipboard_path", "title": "Use path from clipboard", "icon": "clipboard"},
        ],
    })

    if text and (os.path.isfile(text) or os.path.isdir(text)):
        if os.path.isfile(text):
            ext = text.lower().rsplit(".", 1)[-1] if "." in text else ""
            if ext in SUPPORTED_READ_FORMATS:
                info = get_image_info(text)
                if "error" not in info:
                    items.append({
                        "id": "file_selected",
                        "title": f"📁 {os.path.basename(text)}",
                        "subtitle": f"{info['format']} • {info['width']}×{info['height']} • {info['size']} • {info['mode']}",
                        "icon": "image",
                        "accessories": [{"text": info["format"], "color": "#63A0EA"}],
                        "actions": [
                            {"id": "convert_this", "title": "Convert this file", "icon": "refresh"},
                            {"id": "copy_path", "title": "Copy path", "icon": "copy"},
                        ],
                        "preview": {
                            "markdown": f"""## {os.path.basename(text)}

**Format:** {info['format']}
**Dimensions:** {info['width']}×{info['height']} px
**Mode:** {info['mode']}
**DPI:** {info['dpi']}
**File size:** {info['size']}
**EXIF entries:** {info['exif_count']}
**Path:** `{text}`""",
                        },
                    })
            else:
                items.append({
                    "id": "not_image",
                    "title": "Not a supported image file",
                    "subtitle": f"Extension: .{ext}" if ext else "No extension found",
                    "icon": "warning",
                })
        elif os.path.isdir(text):
            images = find_images_in_folder(text, state.get("batch_recursive", False))
            items.append({
                "id": "folder_selected",
                "title": f"📂 {os.path.basename(text)}",
                "subtitle": f"{len(images)} image(s) found in folder",
                "icon": "folder",
                "accessories": [{"text": f"{len(images)} images", "color": "#22C55E"}],
                "actions": [
                    {"id": "batch_convert", "title": "Batch convert folder", "icon": "refresh"},
                    {"id": "batch_resize", "title": "Batch resize", "icon": "image"},
                ],
            })

    menu_items = [
        {"id": "convert_file", "title": "Convert a file", "subtitle": "Convert a single image to another format", "icon": "refresh", "section": "Quick Actions"},
        {"id": "batch_convert", "title": "Batch convert folder", "subtitle": "Convert all images in a folder", "icon": "folder", "section": "Quick Actions"},
        {"id": "resize", "title": "Resize image", "subtitle": "Resize with fit, fill, crop, or percentage", "icon": "image", "section": "Transform"},
        {"id": "compress", "title": "Compress / Optimize", "subtitle": "Reduce file size with quality control", "icon": "download", "section": "Transform"},
        {"id": "filters", "title": "Apply filters", "subtitle": "Grayscale, sepia, blur, sharpen, and more", "icon": "palette", "section": "Transform"},
        {"id": "rotate", "title": "Rotate & Flip", "subtitle": "Rotate 90, 180, flip horizontal/vertical", "icon": "refresh", "section": "Transform"},
        {"id": "watermark", "title": "Add watermark", "subtitle": "Add text watermark with position and style", "icon": "label", "section": "Transform"},
        {"id": "social_presets", "title": "Social media presets", "subtitle": "Instagram, Twitter, YouTube, and more sizes", "icon": "globe", "section": "Presets"},
        {"id": "favicon", "title": "Generate favicon set", "subtitle": "Create favicon.ico with multiple sizes", "icon": "star", "section": "Presets"},
        {"id": "settings", "title": "Settings", "subtitle": "Configure default output folder, quality, etc.", "icon": "settings", "section": "Options"},
        {"id": "help", "title": "Help & Supported formats", "subtitle": "View all supported formats and usage tips", "icon": "help", "section": "Options"},
    ]

    if text.strip():
        filtered = []
        for item in menu_items:
            if text_lower in item["title"].lower() or text_lower in item["subtitle"].lower():
                filtered.append(item)
        items.extend(filtered)
    else:
        items.extend(menu_items)

    if not PIL_AVAILABLE:
        items.insert(0, {
            "id": "error_pil",
            "title": "⚠️ Pillow not installed",
            "subtitle": "Image processing unavailable. Check plugin.json pip dependencies.",
            "icon": "error",
        })

    send({
        "type": "render",
        "rev": rev,
        "view": "list",
        "preview": {"enabled": True},
        "placeholder": "Type a file path, folder path, or search features...",
        "emptyText": "Type a file/folder path or search for a feature",
        "items": items,
    })

def render_image_input(rev, text):
    send({
        "type": "render",
        "rev": rev,
        "view": "list",
        "canGoBack": True,
        "items": [
            {
                "id": "input_pick_image",
                "title": "Pick image file",
                "subtitle": "Choose one or more image files",
                "icon": "file",
                "actions": [{"id": "pick_image_file", "title": "Pick image file", "icon": "file"}],
            },
            {
                "id": "input_batch_convert",
                "title": "Batch Convert a folder",
                "subtitle": "Choose a folder containing images",
                "icon": "folder",
                "actions": [{"id": "batch_convert", "title": "Batch Convert a folder", "icon": "folder"}],
            },
            {
                "id": "input_clipboard_path",
                "title": "Use path from clipboard",
                "subtitle": "Use an image file or folder path copied to the clipboard",
                "icon": "clipboard",
                "actions": [{"id": "use_clipboard_path", "title": "Use path from clipboard", "icon": "clipboard"}],
            },
        ],
    })

def render_convert_file(rev, text):
    items = []
    if state.get("selected_files"):
        for f in state["selected_files"][:5]:
            info = get_image_info(f)
            items.append({
                "id": f"file:{f}",
                "title": os.path.basename(f),
                "subtitle": f"{info.get('format', '?')} • {info.get('width', '?')}×{info.get('height', '?')} • {info.get('size', '?')}" if "error" not in info else str(info.get("error")),
                "icon": "image",
            })
        if len(state["selected_files"]) > 5:
            items.append({"id": "more_files", "title": f"... and {len(state['selected_files']) - 5} more", "subtitle": "", "icon": "file"})

    items.append({
        "id": "section_format",
        "title": "Output Format",
        "subtitle": f"Currently: {state.get('output_format', 'png').upper()}",
        "icon": "tag",
        "section": "Settings",
    })

    formats = ["png", "jpg", "webp", "avif", "gif", "bmp", "tiff", "ico"]
    for fmt in formats:
        is_current = state.get("output_format", "png").lower() == fmt
        items.append({
            "id": f"format:{fmt}",
            "title": fmt.upper(),
            "subtitle": SUPPORTED_WRITE_FORMATS.get(fmt, ""),
            "icon": "check" if is_current else "tag",
            "tileColor": "#22C55E" if is_current else None,
            "accessories": [{"text": "selected", "color": "#22C55E"}] if is_current else [],
        })

    items.append({
        "id": "section_quality",
        "title": "Quality",
        "subtitle": f"Currently: {state.get('quality', '85')}%",
        "icon": "settings",
        "section": "Settings",
    })

    for q in ["100", "95", "90", "85", "80", "75", "70", "60", "50"]:
        is_current = state.get("quality", "85") == q
        items.append({
            "id": f"quality:{q}",
            "title": f"{q}%",
            "subtitle": "Maximum" if q == "100" else "High" if q == "90" else "Good" if q == "85" else "Medium" if q == "75" else "Low",
            "icon": "check" if is_current else "settings",
            "accessories": [{"text": "selected", "color": "#22C55E"}] if is_current else [],
        })

    out_dir = state.get("output_dir", "")
    items.append({
        "id": "section_output",
        "title": "Output Directory",
        "subtitle": out_dir if out_dir else "Same as source (default)",
        "icon": "folder",
        "section": "Settings",
    })

    items.append({
        "id": "toggle_exif",
        "title": "Strip EXIF data",
        "subtitle": "Remove metadata from output" + (" ✓" if state.get("strip_exif") else ""),
        "icon": "shield",
        "accessories": [{"text": "ON", "color": "#22C55E"}] if state.get("strip_exif") else [{"text": "OFF", "color": "#6B7280"}],
    })

    if state.get("selected_files"):
        items.append({
            "id": "do_convert",
            "title": "▶ Convert Now",
            "subtitle": f"Convert {len(state['selected_files'])} file(s) to {state.get('output_format', 'png').upper()}",
            "icon": "run",
            "section": "Action",
            "actions": [{"id": "default", "title": "Convert", "icon": "run"}],
        })

    if state.get("last_error"):
        items.insert(0, {"id": "error_msg", "title": "❌ Error", "subtitle": state["last_error"][:100], "icon": "error"})
    if state.get("last_success"):
        items.insert(0, {"id": "success_msg", "title": "✅ Success", "subtitle": state["last_success"][:100], "icon": "check"})

    send({
        "type": "render",
        "rev": rev,
        "view": "list",
        "canGoBack": True,
        "placeholder": "Select options above or type a file path...",
        "items": items,
    })

def render_resize(rev, text):
    items = []
    if state.get("selected_files"):
        for f in state["selected_files"][:3]:
            info = get_image_info(f)
            items.append({
                "id": f"file:{f}",
                "title": os.path.basename(f),
                "subtitle": f"{info.get('width', '?')}×{info.get('height', '?')} px" if "error" not in info else "",
                "icon": "image",
                "section": "Source",
            })

    items.append({
        "id": "section_mode",
        "title": "Resize Mode",
        "subtitle": RESIZE_MODES.get(state.get("resize_mode", "fit"), ""),
        "icon": "settings",
        "section": "Settings",
    })

    for mode_id, mode_desc in RESIZE_MODES.items():
        is_current = state.get("resize_mode", "fit") == mode_id
        items.append({
            "id": f"mode:{mode_id}",
            "title": mode_desc,
            "subtitle": "",
            "icon": "check" if is_current else "settings",
            "accessories": [{"text": "selected", "color": "#22C55E"}] if is_current else [],
        })

    items.append({
        "id": "section_size",
        "title": "Dimensions",
        "subtitle": "Type width x height, a preset, or percentage",
        "icon": "calculator",
        "section": "Settings",
    })

    presets = [("1920x1080", "Full HD"), ("1280x720", "HD"), ("1080x1080", "Instagram Square"),
               ("1200x675", "Twitter"), ("50%", "Half size"), ("25%", "Quarter size"), ("200%", "Double size")]
    for preset, desc in presets:
        items.append({"id": f"preset_size:{preset}", "title": preset, "subtitle": desc, "icon": "tag"})

    items.append({
        "id": "current_size",
        "title": f"Width: {state.get('resize_w', '—')}  Height: {state.get('resize_h', '—')}",
        "subtitle": f"Percent: {state.get('resize_percent', '100')}%",
        "icon": "info",
    })

    items.append({
        "id": "section_outfmt",
        "title": "Output Format",
        "subtitle": state.get("output_format", "png").upper(),
        "icon": "tag",
        "section": "Output",
    })

    for fmt in ["png", "jpg", "webp", "avif", "bmp", "tiff"]:
        is_current = state.get("output_format", "png") == fmt
        items.append({"id": f"format:{fmt}", "title": fmt.upper(), "subtitle": "", "icon": "check" if is_current else "tag"})

    if state.get("selected_files"):
        items.append({
            "id": "do_resize",
            "title": "▶ Resize Now",
            "subtitle": f"Resize {len(state['selected_files'])} file(s)",
            "icon": "run",
            "section": "Action",
        })

    send({
        "type": "render",
        "rev": rev,
        "view": "list",
        "canGoBack": True,
        "placeholder": "Type dimensions (e.g. 1920x1080, 50%, 1080p)...",
        "items": items,
    })

def render_filters(rev, text):
    items = []
    if state.get("selected_files"):
        for f in state["selected_files"][:3]:
            items.append({"id": f"file:{f}", "title": os.path.basename(f), "subtitle": "", "icon": "image", "section": "Source"})

    items.append({"id": "section_filters", "title": "Choose a filter", "subtitle": "", "icon": "palette", "section": "Filters"})

    for fid, fdesc in FILTERS.items():
        is_current = state.get("filter", "") == fid
        items.append({
            "id": f"filter:{fid}",
            "title": fdesc,
            "subtitle": "",
            "icon": "check" if is_current else "palette",
            "accessories": [{"text": "selected", "color": "#22C55E"}] if is_current else [],
        })

    items.append({"id": "section_outfmt", "title": "Output Format", "subtitle": state.get("output_format", "png").upper(), "icon": "tag", "section": "Output"})
    for fmt in ["png", "jpg", "webp", "avif", "bmp", "tiff"]:
        is_current = state.get("output_format", "png") == fmt
        items.append({"id": f"format:{fmt}", "title": fmt.upper(), "subtitle": "", "icon": "check" if is_current else "tag"})

    if state.get("selected_files") and state.get("filter", ""):
        items.append({
            "id": "do_filter",
            "title": "▶ Apply Filter",
            "subtitle": f"Apply {FILTERS.get(state['filter'], state['filter'])} to {len(state['selected_files'])} file(s)",
            "icon": "run",
            "section": "Action",
        })

    send({"type": "render", "rev": rev, "view": "list", "canGoBack": True, "placeholder": "Select a filter...", "items": items})

def render_rotate(rev, text):
    items = []
    if state.get("selected_files"):
        for f in state["selected_files"][:3]:
            items.append({"id": f"file:{f}", "title": os.path.basename(f), "subtitle": "", "icon": "image", "section": "Source"})

    items.append({"id": "section_rotate", "title": "Rotate & Flip", "subtitle": "", "icon": "refresh", "section": "Options"})

    for rid, rdesc in ROTATE_OPTIONS.items():
        is_current = state.get("rotate", "") == rid
        items.append({
            "id": f"rotate:{rid}",
            "title": rdesc,
            "subtitle": "",
            "icon": "check" if is_current else "refresh",
            "accessories": [{"text": "selected", "color": "#22C55E"}] if is_current else [],
        })

    items.append({"id": "section_outfmt", "title": "Output Format", "subtitle": state.get("output_format", "png").upper(), "icon": "tag", "section": "Output"})
    for fmt in ["png", "jpg", "webp", "avif", "bmp", "tiff"]:
        is_current = state.get("output_format", "png") == fmt
        items.append({"id": f"format:{fmt}", "title": fmt.upper(), "subtitle": "", "icon": "check" if is_current else "tag"})

    if state.get("selected_files") and state.get("rotate", ""):
        items.append({
            "id": "do_rotate",
            "title": "▶ Apply Rotation",
            "subtitle": f"Apply to {len(state['selected_files'])} file(s)",
            "icon": "run",
            "section": "Action",
        })

    send({"type": "render", "rev": rev, "view": "list", "canGoBack": True, "placeholder": "Select rotation or flip...", "items": items})


def render_watermark(rev, text):
    items = []
    if state.get("selected_files"):
        for f in state["selected_files"][:3]:
            items.append({"id": f"file:{f}", "title": os.path.basename(f), "subtitle": "", "icon": "image", "section": "Source"})

    items.append({
        "id": "section_wm_text",
        "title": "Watermark Text",
        "subtitle": f"Current: '{state.get('watermark_text', '')}'" if state.get("watermark_text") else "No text set",
        "icon": "label",
        "section": "Settings",
    })

    positions = [("top_left", "Top Left"), ("top_center", "Top Center"), ("top_right", "Top Right"),
                 ("center", "Center"), ("bottom_left", "Bottom Left"), ("bottom_center", "Bottom Center"), ("bottom_right", "Bottom Right")]
    for pos_id, pos_name in positions:
        is_current = state.get("watermark_pos", "bottom_right") == pos_id
        items.append({
            "id": f"wm_pos:{pos_id}",
            "title": pos_name,
            "subtitle": "",
            "icon": "check" if is_current else "location",
            "accessories": [{"text": "selected", "color": "#22C55E"}] if is_current else [],
        })

    items.append({
        "id": "section_wm_size",
        "title": "Font Size",
        "subtitle": f"Current: {state.get('watermark_size', '24')}px",
        "icon": "settings",
        "section": "Style",
    })
    for size in ["12", "18", "24", "36", "48", "64", "96"]:
        is_current = state.get("watermark_size", "24") == size
        items.append({"id": f"wm_size:{size}", "title": f"{size}px", "subtitle": "", "icon": "check" if is_current else "settings"})

    colors = [("#FFFFFF", "White"), ("#000000", "Black"), ("#FF0000", "Red"), ("#00FF00", "Green"),
              ("#0000FF", "Blue"), ("#FFFF00", "Yellow"), ("#FF8800", "Orange"), ("#8800FF", "Purple")]
    items.append({
        "id": "section_wm_color",
        "title": "Color",
        "subtitle": f"Current: {state.get('watermark_color', '#FFFFFF')}",
        "icon": "palette",
        "section": "Style",
    })
    for color, name in colors:
        is_current = state.get("watermark_color", "#FFFFFF") == color
        items.append({"id": f"wm_color:{color}", "title": name, "subtitle": "", "icon": color if not is_current else "check", "tileColor": color})

    items.append({
        "id": "section_wm_opacity",
        "title": "Opacity",
        "subtitle": f"Current: {state.get('watermark_opacity', '128')}/255",
        "icon": "settings",
        "section": "Style",
    })
    for op in ["255", "200", "150", "128", "100", "75", "50", "25"]:
        is_current = state.get("watermark_opacity", "128") == op
        items.append({"id": f"wm_opacity:{op}", "title": f"{op}/255", "subtitle": f"{int(int(op)/255*100)}%", "icon": "check" if is_current else "settings"})

    items.append({"id": "section_outfmt", "title": "Output Format", "subtitle": state.get("output_format", "png").upper(), "icon": "tag", "section": "Output"})
    for fmt in ["png", "jpg", "webp", "avif", "bmp", "tiff"]:
        is_current = state.get("output_format", "png") == fmt
        items.append({"id": f"format:{fmt}", "title": fmt.upper(), "subtitle": "", "icon": "check" if is_current else "tag"})

    if state.get("selected_files") and state.get("watermark_text"):
        items.append({
            "id": "do_watermark",
            "title": "▶ Add Watermark",
            "subtitle": f"Apply to {len(state['selected_files'])} file(s)",
            "icon": "run",
            "section": "Action",
        })

    send({"type": "render", "rev": rev, "view": "list", "canGoBack": True, "placeholder": "Type watermark text...", "items": items})

def render_social_presets(rev, text):
    items = []
    if state.get("selected_files"):
        for f in state["selected_files"][:3]:
            info = get_image_info(f)
            items.append({
                "id": f"file:{f}",
                "title": os.path.basename(f),
                "subtitle": f"{info.get('width', '?')}×{info.get('height', '?')} px" if "error" not in info else "",
                "icon": "image",
                "section": "Source",
            })

    categories = {
        "Social Media": ["instagram_post", "instagram_story", "twitter_post", "twitter_header", "facebook_post", "facebook_cover", "linkedin_post", "linkedin_banner"],
        "Video Platforms": ["youtube_thumbnail", "youtube_banner", "tiktok_video"],
        "Gaming/Community": ["discord_avatar", "discord_banner", "twitch_profile", "twitch_banner", "github_avatar"],
        "Favicons": ["favicon_16", "favicon_32", "favicon_48", "favicon_64", "favicon_128", "favicon_256", "favicon_512"],
        "Apple Touch": ["apple_touch_57", "apple_touch_72", "apple_touch_114", "apple_touch_144", "apple_touch_180"],
        "Resolutions": ["hd_720", "hd_1080", "hd_1440", "hd_4k"],
        "Print": ["a4_300dpi", "a4_150dpi", "a5_300dpi", "letter_300dpi"],
        "Documents": ["passport_photo", "id_photo_35x45", "wallet_photo"],
    }

    for cat_name, presets in categories.items():
        for preset in presets:
            w, h = SOCIAL_SIZES[preset]
            is_current = state.get("social_preset", "") == preset
            items.append({
                "id": f"social:{preset}",
                "title": preset.replace("_", " ").title(),
                "subtitle": f"{w} × {h} px",
                "icon": "check" if is_current else "globe",
                "section": cat_name,
                "accessories": [{"text": "selected", "color": "#22C55E"}] if is_current else [],
            })

    items.append({"id": "section_outfmt", "title": "Output Format", "subtitle": state.get("output_format", "png").upper(), "icon": "tag", "section": "Output"})
    for fmt in ["png", "jpg", "webp", "avif"]:
        is_current = state.get("output_format", "png") == fmt
        items.append({"id": f"format:{fmt}", "title": fmt.upper(), "subtitle": "", "icon": "check" if is_current else "tag"})

    if state.get("selected_files") and state.get("social_preset"):
        preset = state["social_preset"]
        w, h = SOCIAL_SIZES[preset]
        items.append({
            "id": "do_social",
            "title": "▶ Apply Preset",
            "subtitle": f"Resize to {w}×{h} ({preset.replace('_', ' ').title()})",
            "icon": "run",
            "section": "Action",
        })

    send({"type": "render", "rev": rev, "view": "list", "canGoBack": True, "placeholder": "Search social media presets...", "items": items})

def render_favicon(rev, text):
    items = []
    if state.get("selected_files"):
        for f in state["selected_files"][:3]:
            items.append({"id": f"file:{f}", "title": os.path.basename(f), "subtitle": "", "icon": "image", "section": "Source"})

    items.append({
        "id": "info_favicon",
        "title": "Generate Favicon Set",
        "subtitle": "Creates .ico with 16, 32, 48, 64, 128, 256 px sizes",
        "icon": "info",
        "section": "Info",
    })

    items.append({
        "id": "do_favicon",
        "title": "▶ Generate Favicon.ico",
        "subtitle": "Convert source image to multi-size favicon" if state.get("selected_files") else "Select an image first",
        "icon": "run",
        "section": "Action",
        "actions": [{"id": "default", "title": "Generate", "icon": "run"}] if state.get("selected_files") else [],
    })

    send({"type": "render", "rev": rev, "view": "list", "canGoBack": True, "placeholder": "Select a source image...", "items": items})

def render_settings(rev, text):
    items = []
    cfg = state.get("config", {})

    items.append({
        "id": "set_default_output",
        "title": "Default Output Folder",
        "subtitle": cfg.get("default_output", "Same as source (not set)"),
        "icon": "folder",
        "section": "General",
    })

    items.append({
        "id": "set_default_format",
        "title": "Default Output Format",
        "subtitle": cfg.get("default_format", "png").upper(),
        "icon": "tag",
        "section": "General",
    })

    items.append({
        "id": "set_default_quality",
        "title": "Default Quality",
        "subtitle": f"{cfg.get('default_quality', 85)}%",
        "icon": "settings",
        "section": "General",
    })

    items.append({
        "id": "toggle_preserve",
        "title": "Preserve Folder Structure",
        "subtitle": "Maintain subfolder hierarchy in batch operations" + (" ✓" if cfg.get("preserve_structure") else ""),
        "icon": "folder",
        "section": "Batch",
        "accessories": [{"text": "ON", "color": "#22C55E"}] if cfg.get("preserve_structure") else [{"text": "OFF", "color": "#6B7280"}],
    })

    items.append({
        "id": "toggle_recursive",
        "title": "Recursive Batch Processing",
        "subtitle": "Include subfolders in batch operations" + (" ✓" if cfg.get("recursive") else ""),
        "icon": "folder",
        "section": "Batch",
        "accessories": [{"text": "ON", "color": "#22C55E"}] if cfg.get("recursive") else [{"text": "OFF", "color": "#6B7280"}],
    })

    items.append({
        "id": "clear_recent",
        "title": "Clear Recent Files",
        "subtitle": "Remove recently used file paths from memory",
        "icon": "delete",
        "section": "Maintenance",
        "actions": [{"id": "default", "title": "Clear", "icon": "delete", "destructive": True, "confirm": True}],
    })

    send({"type": "render", "rev": rev, "view": "list", "canGoBack": True, "placeholder": "Configure plugin settings...", "items": items})

def render_help(rev, text):
    read_list = ", ".join(sorted(set(SUPPORTED_READ_FORMATS.keys())))
    write_list = ", ".join(sorted(set(SUPPORTED_WRITE_FORMATS.keys())))

    markdown = f"""# Image Converter Help

## Quick Start
1. Type a **file path** or **folder path** directly in the launcher
2. Or click **Pick an image or folder** to browse
3. Configure output format, quality, and options
4. Hit **Enter** or **Convert Now** to process

## Supported Input Formats
`{read_list}`

## Supported Output Formats
`{write_list}`

## Resize Syntax
You can type dimensions directly:
- `1920x1080` — exact width x height
- `50%` — scale to 50%
- `1080p` / `720p` / `4k` — resolution presets
- Single number like `800` — fit long edge to 800px

## Tips
- **Batch mode**: Select a folder to convert all images at once
- **Quality**: Lower quality = smaller file size (great for web)
- **Strip EXIF**: Remove GPS, camera info, and other metadata
- **Social presets**: One-click resize for Instagram, Twitter, YouTube, etc.
- **Favicon**: Generate multi-resolution .ico files for websites
- **Preserve structure**: Maintains subfolder layout in batch operations

## Shortcuts
- **Enter** — Execute the highlighted action
- **Ctrl+K** — View available actions for selected item
- **Escape** — Go back or exit
- **Tab** — Autocomplete (when available)
"""

    send({
        "type": "render",
        "rev": rev,
        "view": "detail",
        "canGoBack": True,
        "detail": {"markdown": markdown, "wide": True},
    })


# ── Action Handlers ──

def handle_do_convert():
    files = state.get("selected_files", [])
    if not files:
        state["last_error"] = "No files selected"
        return
    out_fmt = SUPPORTED_WRITE_FORMATS.get(state.get("output_format", "png"), "PNG")
    out_dir = state.get("output_dir", "")
    preserve = state.get("preserve_structure", False) or state["config"].get("preserve_structure", False)
    success_count = 0
    errors = []
    for src_path in files:
        try:
            if out_dir:
                base_dir = os.path.dirname(files[0]) if len(files) == 1 else os.path.commonpath(files) if len(files) > 1 else ""
                dst_path = build_output_path(src_path, out_dir, out_fmt, preserve, base_dir)
            else:
                base = os.path.splitext(src_path)[0]
                ext = out_fmt.lower()
                if ext == "jpeg": ext = "jpg"
                elif ext == "tiff": ext = "tif"
                dst_path = get_unique_path(f"{base}.{ext}")
            options = {
                "format": out_fmt,
                "quality": int(state.get("quality", "85")),
                "strip_exif": state.get("strip_exif", False),
            }
            convert_image(src_path, dst_path, options)
            success_count += 1
        except Exception as e:
            errors.append(f"{os.path.basename(src_path)}: {e}")
            log("Convert error:", e)
    if errors:
        state["last_error"] = f"{len(errors)} error(s): {errors[0][:60]}"
        state["last_success"] = f"Converted {success_count}/{len(files)} files"
    else:
        state["last_error"] = ""
        state["last_success"] = f"Converted {success_count} file(s) to {out_fmt}"
    if success_count > 0:
        send({"type": "command", "command": "toast", "text": state["last_success"], "style": "success"})

def handle_do_resize():
    files = state.get("selected_files", [])
    if not files:
        state["last_error"] = "No files selected"
        return
    mode = state.get("resize_mode", "fit")
    out_fmt = SUPPORTED_WRITE_FORMATS.get(state.get("output_format", "png"), "PNG")
    out_dir = state.get("output_dir", "")
    preserve = state.get("preserve_structure", False) or state["config"].get("preserve_structure", False)
    text = state.get("_last_text", "")
    parsed = None
    if text:
        text_clean = text.strip().lower()
        if text_clean.endswith("%"):
            try: parsed = ("percent", float(text_clean[:-1]))
            except: pass
        else:
            m = re.match(r"^(\d+)\s*[x×]\s*(\d+)$", text_clean)
            if m: parsed = ("fit", int(m.group(1)), int(m.group(2)))
            else:
                m = re.match(r"^(\d+)$", text_clean)
                if m: parsed = ("long_edge", int(m.group(1)), int(m.group(1)))
    w = int(state.get("resize_w", "0") or 0)
    h = int(state.get("resize_h", "0") or 0)
    percent = float(state.get("resize_percent", "100") or 100)
    if parsed:
        if parsed[0] == "percent":
            mode = "percent"
            percent = parsed[1]
        else:
            mode = parsed[0]
            w, h = parsed[1], parsed[2]
    success_count = 0
    errors = []
    for src_path in files:
        try:
            if out_dir:
                base_dir = os.path.dirname(files[0]) if len(files) == 1 else os.path.commonpath(files) if len(files) > 1 else ""
                dst_path = build_output_path(src_path, out_dir, out_fmt, preserve, base_dir)
            else:
                base = os.path.splitext(src_path)[0]
                ext = out_fmt.lower()
                if ext == "jpeg": ext = "jpg"
                elif ext == "tiff": ext = "tif"
                dst_path = get_unique_path(f"{base}_resized.{ext}")
            options = {
                "format": out_fmt,
                "quality": int(state.get("quality", "85")),
                "resize_mode": mode,
                "resize_w": w,
                "resize_h": h,
                "resize_percent": percent,
            }
            convert_image(src_path, dst_path, options)
            success_count += 1
        except Exception as e:
            errors.append(f"{os.path.basename(src_path)}: {e}")
            log("Resize error:", e)
    if errors:
        state["last_error"] = f"{len(errors)} error(s): {errors[0][:60]}"
        state["last_success"] = f"Resized {success_count}/{len(files)} files"
    else:
        state["last_error"] = ""
        state["last_success"] = f"Resized {success_count} file(s)"
    if success_count > 0:
        send({"type": "command", "command": "toast", "text": state["last_success"], "style": "success"})

def handle_do_filter():
    files = state.get("selected_files", [])
    if not files:
        state["last_error"] = "No files selected"
        return
    filter_name = state.get("filter", "")
    if not filter_name:
        state["last_error"] = "No filter selected"
        return
    out_fmt = SUPPORTED_WRITE_FORMATS.get(state.get("output_format", "png"), "PNG")
    out_dir = state.get("output_dir", "")
    preserve = state.get("preserve_structure", False) or state["config"].get("preserve_structure", False)
    success_count = 0
    errors = []
    for src_path in files:
        try:
            if out_dir:
                base_dir = os.path.dirname(files[0]) if len(files) == 1 else os.path.commonpath(files) if len(files) > 1 else ""
                dst_path = build_output_path(src_path, out_dir, out_fmt, preserve, base_dir)
            else:
                base = os.path.splitext(src_path)[0]
                ext = out_fmt.lower()
                if ext == "jpeg": ext = "jpg"
                elif ext == "tiff": ext = "tif"
                dst_path = get_unique_path(f"{base}_{filter_name}.{ext}")
            options = {
                "format": out_fmt,
                "quality": int(state.get("quality", "85")),
                "filter": filter_name,
            }
            convert_image(src_path, dst_path, options)
            success_count += 1
        except Exception as e:
            errors.append(f"{os.path.basename(src_path)}: {e}")
            log("Filter error:", e)
    if errors:
        state["last_error"] = f"{len(errors)} error(s): {errors[0][:60]}"
        state["last_success"] = f"Filtered {success_count}/{len(files)} files"
    else:
        state["last_error"] = ""
        state["last_success"] = f"Applied {FILTERS.get(filter_name, filter_name)} to {success_count} file(s)"
    if success_count > 0:
        send({"type": "command", "command": "toast", "text": state["last_success"], "style": "success"})

def handle_do_rotate():
    files = state.get("selected_files", [])
    if not files:
        state["last_error"] = "No files selected"
        return
    rotate_opt = state.get("rotate", "")
    if not rotate_opt:
        state["last_error"] = "No rotation selected"
        return
    out_fmt = SUPPORTED_WRITE_FORMATS.get(state.get("output_format", "png"), "PNG")
    out_dir = state.get("output_dir", "")
    preserve = state.get("preserve_structure", False) or state["config"].get("preserve_structure", False)
    success_count = 0
    errors = []
    for src_path in files:
        try:
            if out_dir:
                base_dir = os.path.dirname(files[0]) if len(files) == 1 else os.path.commonpath(files) if len(files) > 1 else ""
                dst_path = build_output_path(src_path, out_dir, out_fmt, preserve, base_dir)
            else:
                base = os.path.splitext(src_path)[0]
                ext = out_fmt.lower()
                if ext == "jpeg": ext = "jpg"
                elif ext == "tiff": ext = "tif"
                dst_path = get_unique_path(f"{base}_rotated.{ext}")
            options = {
                "format": out_fmt,
                "quality": int(state.get("quality", "85")),
                "rotate": rotate_opt,
            }
            convert_image(src_path, dst_path, options)
            success_count += 1
        except Exception as e:
            errors.append(f"{os.path.basename(src_path)}: {e}")
            log("Rotate error:", e)
    if errors:
        state["last_error"] = f"{len(errors)} error(s): {errors[0][:60]}"
        state["last_success"] = f"Rotated {success_count}/{len(files)} files"
    else:
        state["last_error"] = ""
        state["last_success"] = f"Applied rotation to {success_count} file(s)"
    if success_count > 0:
        send({"type": "command", "command": "toast", "text": state["last_success"], "style": "success"})

def handle_do_watermark():
    files = state.get("selected_files", [])
    if not files:
        state["last_error"] = "No files selected"
        return
    wm_text = state.get("watermark_text", "")
    if not wm_text:
        state["last_error"] = "No watermark text set"
        return
    out_fmt = SUPPORTED_WRITE_FORMATS.get(state.get("output_format", "png"), "PNG")
    out_dir = state.get("output_dir", "")
    preserve = state.get("preserve_structure", False) or state["config"].get("preserve_structure", False)
    success_count = 0
    errors = []
    for src_path in files:
        try:
            if out_dir:
                base_dir = os.path.dirname(files[0]) if len(files) == 1 else os.path.commonpath(files) if len(files) > 1 else ""
                dst_path = build_output_path(src_path, out_dir, out_fmt, preserve, base_dir)
            else:
                base = os.path.splitext(src_path)[0]
                ext = out_fmt.lower()
                if ext == "jpeg": ext = "jpg"
                elif ext == "tiff": ext = "tif"
                dst_path = get_unique_path(f"{base}_watermarked.{ext}")
            options = {
                "format": out_fmt,
                "quality": int(state.get("quality", "85")),
                "watermark_text": wm_text,
                "watermark_pos": state.get("watermark_pos", "bottom_right"),
                "watermark_size": int(state.get("watermark_size", "24")),
                "watermark_color": state.get("watermark_color", "#FFFFFF"),
                "watermark_opacity": int(state.get("watermark_opacity", "128")),
            }
            convert_image(src_path, dst_path, options)
            success_count += 1
        except Exception as e:
            errors.append(f"{os.path.basename(src_path)}: {e}")
            log("Watermark error:", e)
    if errors:
        state["last_error"] = f"{len(errors)} error(s): {errors[0][:60]}"
        state["last_success"] = f"Watermarked {success_count}/{len(files)} files"
    else:
        state["last_error"] = ""
        state["last_success"] = f"Added watermark to {success_count} file(s)"
    if success_count > 0:
        send({"type": "command", "command": "toast", "text": state["last_success"], "style": "success"})

def handle_do_social():
    files = state.get("selected_files", [])
    if not files:
        state["last_error"] = "No files selected"
        return
    preset = state.get("social_preset", "")
    if not preset or preset not in SOCIAL_SIZES:
        state["last_error"] = "No preset selected"
        return
    out_fmt = SUPPORTED_WRITE_FORMATS.get(state.get("output_format", "png"), "PNG")
    out_dir = state.get("output_dir", "")
    preserve = state.get("preserve_structure", False) or state["config"].get("preserve_structure", False)
    w, h = SOCIAL_SIZES[preset]
    success_count = 0
    errors = []
    for src_path in files:
        try:
            if out_dir:
                base_dir = os.path.dirname(files[0]) if len(files) == 1 else os.path.commonpath(files) if len(files) > 1 else ""
                dst_path = build_output_path(src_path, out_dir, out_fmt, preserve, base_dir)
            else:
                base = os.path.splitext(src_path)[0]
                ext = out_fmt.lower()
                if ext == "jpeg": ext = "jpg"
                elif ext == "tiff": ext = "tif"
                dst_path = get_unique_path(f"{base}_{preset}.{ext}")
            options = {
                "format": out_fmt,
                "quality": int(state.get("quality", "85")),
                "social_preset": preset,
            }
            convert_image(src_path, dst_path, options)
            success_count += 1
        except Exception as e:
            errors.append(f"{os.path.basename(src_path)}: {e}")
            log("Social error:", e)
    if errors:
        state["last_error"] = f"{len(errors)} error(s): {errors[0][:60]}"
        state["last_success"] = f"Resized {success_count}/{len(files)} files"
    else:
        state["last_error"] = ""
        state["last_success"] = f"Resized {success_count} file(s) to {preset.replace('_', ' ').title()} ({w}x{h})"
    if success_count > 0:
        send({"type": "command", "command": "toast", "text": state["last_success"], "style": "success"})

def handle_do_favicon():
    files = state.get("selected_files", [])
    if not files:
        state["last_error"] = "No files selected"
        return
    src_path = files[0]
    out_dir = state.get("output_dir", "")
    try:
        if out_dir:
            dst_path = os.path.join(out_dir, "favicon.ico")
        else:
            dst_path = os.path.join(os.path.dirname(src_path), "favicon.ico")
        dst_path = get_unique_path(dst_path)
        options = {"format": "ICO"}
        convert_image(src_path, dst_path, options)
        state["last_error"] = ""
        state["last_success"] = f"Generated favicon.ico with multiple sizes"
        send({"type": "command", "command": "toast", "text": state["last_success"], "style": "success"})
    except Exception as e:
        state["last_error"] = str(e)[:100]
        log("Favicon error:", e)


# ── Main Router ──

def render_screen(rev, text):
    screen = state.get("screen", "root")
    state["_last_text"] = text
    if screen == "root":
        render_root(rev, text)
    elif screen == "image_input":
        render_image_input(rev, text)
    elif screen == "convert_file":
        render_convert_file(rev, text)
    elif screen == "resize":
        render_resize(rev, text)
    elif screen == "filters":
        render_filters(rev, text)
    elif screen == "rotate":
        render_rotate(rev, text)
    elif screen == "watermark":
        render_watermark(rev, text)
    elif screen == "social_presets":
        render_social_presets(rev, text)
    elif screen == "favicon":
        render_favicon(rev, text)
    elif screen == "settings":
        render_settings(rev, text)
    elif screen == "help":
        render_help(rev, text)
    else:
        render_root(rev, text)

def handle_action(item_id, action):
    log("Action:", item_id, action)

    input_actions = {
        "input_pick_image": "pick_image_file",
        "input_batch_convert": "batch_convert",
        "input_clipboard_path": "use_clipboard_path",
    }
    if item_id in input_actions:
        input_item_id = item_id
        item_id = "pick_image"
        if action == "default":
            action = input_actions[input_item_id]

    if item_id == "pick_image" and action == "default" and state.get("screen") == "root":
        state["screen"] = "image_input"
        render_screen(0, "")
        return

    if item_id == "pick_image" and action == "default":
        action = "pick_image_file"

    if item_id == "pick_image" and action == "use_clipboard_path":
        send({
            "type": "command",
            "command": "clipboardRead",
            "requestId": "image-input-path",
        })
        return

    # The root shortcut should open the folder picker, not navigate to an
    # unimplemented "batch_convert" screen.
    if item_id == "batch_convert" and state.get("screen") == "root":
        item_id = "pick_image"
        action = "batch_convert"

    # Pick image - open native Windows dialogs in an STA PowerShell process.
    # The old implementation declared only part of IFileDialog, which makes
    # GetResult/GetResults call the wrong COM vtable slots and silently fail.
    if item_id == "pick_image":
        picked = []
        folder = None
        if action == "pick_image_file":
            try:
                ps = """Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Multiselect = $true
$dialog.Filter = 'Image files|*.png;*.jpg;*.jpeg;*.webp;*.avif;*.gif;*.bmp;*.tif;*.tiff;*.ico;*.heic;*.heif|All files|*.*'
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $dialog.FileNames }
"""
                result = subprocess.run(["powershell", "-NoProfile", "-STA", "-Command", ps],
                                        capture_output=True, text=True, timeout=30)
                if result.returncode == 0 and result.stdout.strip():
                    picked = [p.strip() for p in result.stdout.splitlines()
                              if p.strip() and os.path.isfile(p.strip())]
            except Exception as e:
                log("File picker error:", e)
        elif action == "batch_convert":
            try:
                ps = """Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
$dialog.Description = 'Choose a folder containing images'
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $dialog.SelectedPath }
"""
                result = subprocess.run(["powershell", "-NoProfile", "-STA", "-Command", ps],
                                        capture_output=True, text=True, timeout=30)
                if result.returncode == 0 and result.stdout.strip():
                    folder = result.stdout.strip()
            except Exception as e:
                log("Folder picker error:", e)

        if picked:
            state["selected_files"] = picked
            state["screen"] = "convert_file"
            state["last_error"] = ""
            state["last_success"] = f"Selected {len(picked)} file(s)"
        elif folder:
            images = find_images_in_folder(folder, state["config"].get("recursive", False))
            if images:
                state["selected_files"] = images[:50]
                state["screen"] = "convert_file"
                state["last_error"] = ""
                state["last_success"] = f"Loaded {len(images)} images from folder"
            else:
                state["last_error"] = "No images found in selected folder"
        elif action == "batch_convert":
            state["last_error"] = "No folder selected"
        else:
            state["last_error"] = "No file selected"

        render_screen(0, "")
        return

    # Navigation actions
    if item_id in ("convert_file", "batch_convert", "resize", "filters", "rotate", "watermark",
                   "social_presets", "favicon", "settings", "help"):
        state["screen"] = item_id
        state["last_error"] = ""
        state["last_success"] = ""
        render_screen(0, "")
        return

    if item_id == "file_selected" and action == "convert_this":
        state["screen"] = "convert_file"
        render_screen(0, "")
        return

    if item_id == "file_selected" and action == "copy_path":
        if state.get("selected_files"):
            send({"type": "command", "command": "copy", "text": state["selected_files"][0]})
        return

    if item_id == "folder_selected" and action == "batch_convert":
        state["screen"] = "convert_file"
        render_screen(0, "")
        return

    if item_id == "folder_selected" and action == "batch_resize":
        state["screen"] = "resize"
        render_screen(0, "")
        return

    # Format selection
    if item_id.startswith("format:"):
        state["output_format"] = item_id.split(":", 1)[1]
        render_screen(0, "")
        return

    # Quality selection
    if item_id.startswith("quality:"):
        state["quality"] = item_id.split(":", 1)[1]
        render_screen(0, "")
        return

    # Resize mode
    if item_id.startswith("mode:"):
        state["resize_mode"] = item_id.split(":", 1)[1]
        render_screen(0, "")
        return

    # Preset size
    if item_id.startswith("preset_size:"):
        preset = item_id.split(":", 1)[1]
        if preset.endswith("%"):
            state["resize_mode"] = "percent"
            state["resize_percent"] = preset[:-1]
        else:
            m = re.match(r"^(\d+)[x×](\d+)$", preset)
            if m:
                state["resize_mode"] = "fit"
                state["resize_w"] = m.group(1)
                state["resize_h"] = m.group(2)
        render_screen(0, "")
        return

    # Filter selection
    if item_id.startswith("filter:"):
        state["filter"] = item_id.split(":", 1)[1]
        render_screen(0, "")
        return

    # Rotate selection
    if item_id.startswith("rotate:"):
        state["rotate"] = item_id.split(":", 1)[1]
        render_screen(0, "")
        return

    # Watermark settings
    if item_id.startswith("wm_pos:"):
        state["watermark_pos"] = item_id.split(":", 1)[1]
        render_screen(0, "")
        return
    if item_id.startswith("wm_size:"):
        state["watermark_size"] = item_id.split(":", 1)[1]
        render_screen(0, "")
        return
    if item_id.startswith("wm_color:"):
        state["watermark_color"] = item_id.split(":", 1)[1]
        render_screen(0, "")
        return
    if item_id.startswith("wm_opacity:"):
        state["watermark_opacity"] = item_id.split(":", 1)[1]
        render_screen(0, "")
        return

    # Social preset
    if item_id.startswith("social:"):
        state["social_preset"] = item_id.split(":", 1)[1]
        render_screen(0, "")
        return

    # Toggle EXIF
    if item_id == "toggle_exif":
        state["strip_exif"] = not state.get("strip_exif", False)
        render_screen(0, "")
        return

    # Settings toggles
    if item_id == "toggle_preserve":
        state["config"]["preserve_structure"] = not state["config"].get("preserve_structure", False)
        save_config(state["config"])
        render_screen(0, "")
        return
    if item_id == "toggle_recursive":
        state["config"]["recursive"] = not state["config"].get("recursive", False)
        save_config(state["config"])
        render_screen(0, "")
        return

    # Clear recent
    if item_id == "clear_recent":
        state["selected_files"] = []
        state["last_success"] = "Recent files cleared"
        render_screen(0, "")
        return

    # Do actions
    if item_id == "do_convert":
        handle_do_convert()
        render_screen(0, "")
        return
    if item_id == "do_resize":
        handle_do_resize()
        render_screen(0, "")
        return
    if item_id == "do_filter":
        handle_do_filter()
        render_screen(0, "")
        return
    if item_id == "do_rotate":
        handle_do_rotate()
        render_screen(0, "")
        return
    if item_id == "do_watermark":
        handle_do_watermark()
        render_screen(0, "")
        return
    if item_id == "do_social":
        handle_do_social()
        render_screen(0, "")
        return
    if item_id == "do_favicon":
        handle_do_favicon()
        render_screen(0, "")
        return

    # Default: just re-render
    render_screen(0, "")

def handle_back():
    state["screen"] = "root"
    state["last_error"] = ""
    state["last_success"] = ""
    render_screen(0, "")

def handle_query(rev, text):
    if text and (os.path.isfile(text) or os.path.isdir(text)):
        if os.path.isfile(text):
            ext = text.lower().rsplit(".", 1)[-1] if "." in text else ""
            if ext in SUPPORTED_READ_FORMATS:
                if text not in state["selected_files"]:
                    state["selected_files"].insert(0, text)
                    state["selected_files"] = state["selected_files"][:10]
        elif os.path.isdir(text):
            images = find_images_in_folder(text, state["config"].get("recursive", False))
            if images:
                state["selected_files"] = images[:50]
    if state.get("screen") == "watermark" and text.strip():
        if not text.startswith("/") and not text.startswith("\\") and ":" not in text[:3]:
            if not any(text.lower().endswith(f".{ext}") for ext in SUPPORTED_READ_FORMATS):
                state["watermark_text"] = text.strip()
    if text and os.path.isdir(text) and state.get("screen") != "root":
        state["output_dir"] = text
    render_screen(rev, text)

def main():
    state["config"] = load_config()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            log("Invalid JSON:", line[:100])
            continue
        t = msg.get("type")
        if t == "close":
            break
        elif t in ("init", "query"):
            handle_query(msg.get("rev", 0), msg.get("text", msg.get("query", "")))
        elif t == "action":
            handle_action(msg.get("id", ""), msg.get("action", "default"))
        elif t == "clipboard" and msg.get("requestId") == "image-input-path":
            clipboard_path = msg.get("text", "").strip().strip('"')
            if clipboard_path:
                send({"type": "command", "command": "setQuery", "text": clipboard_path})
            else:
                state["last_error"] = "Clipboard does not contain a path"
                render_screen(0, "")
        elif t == "back":
            handle_back()

if __name__ == "__main__":
    main()
