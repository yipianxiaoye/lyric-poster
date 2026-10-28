"""Derive platform launcher assets from the approved, unmodified raster design.

Requires Python 3 and Pillow. No network access or generated artwork is used.
Run from any working directory: python scripts/prepare-icons.py
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
from statistics import median

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets" / "icons"
RES = ROOT / "android" / "app" / "src" / "main" / "res"
REVIEW = ROOT / "work" / "icon-review"
BACKGROUND = (236, 232, 253)
SOURCE_SHA256 = "61e72b89ae844ad85b6f73f15b9b8b2d6caf42f663e9b99a17074789250b24b3"
SCALE = Image.Resampling.LANCZOS
ICO_SIZES = (16, 20, 24, 32, 40, 48, 64, 128, 256)
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def rounded_mask(size: int, radius: float, inset: float = 0) -> Image.Image:
    """Supersample masks, including those used by 16 px Windows icons."""
    quality = 4
    mask = Image.new("L", (size * quality, size * quality))
    ImageDraw.Draw(mask).rounded_rectangle(
        (inset * quality, inset * quality, (size - inset) * quality - 1,
         (size - inset) * quality - 1), radius=radius * quality, fill=255
    )
    return mask.resize((size, size), SCALE)


def windows_master(source: Image.Image) -> Image.Image:
    """Keep the approved tile; replace the matted white edge before masking."""
    size = source.width
    mask = rounded_mask(size, size * 170 / 1254)
    # The original exterior is an almost-white JPEG-like matte. Its antialiasing
    # must not survive under a transparent edge on a dark taskbar. The 12 px
    # interior transition preserves the original background texture everywhere
    # except the very outside of the tile.
    interior = mask.filter(ImageFilter.MinFilter(25))
    clean = Image.composite(source, Image.new("RGB", source.size, BACKGROUND), interior)
    clean.putalpha(mask)
    return clean.resize((1024, 1024), SCALE)


def extract_foreground(source: Image.Image) -> tuple[Image.Image, Image.Image]:
    """Remove only the lavender background, retaining paper and folded corner.

    Classification is restricted to the central motif. Edge colors are unmatted
    against the measured background using a nearby opaque foreground sample,
    so the light paper edge does not acquire a lavender or white fringe.
    """
    pixels = source.load()
    binary = Image.new("L", source.size)
    classified = binary.load()
    row_background = {}
    for y in range(205, 1048):
        row_background[y] = tuple(
            float(median(pixels[x, y][channel] for x in (160, 180, 200, 1040, 1070, 1100)))
            for channel in range(3)
        )
        bg = row_background[y]
        for x in range(270, 985):
            if max(abs(pixels[x, y][channel] - bg[channel]) for channel in range(3)) > 9:
                classified[x, y] = 255
    # Remove isolated classification noise and close one-pixel texture holes.
    binary = binary.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    solid = binary.filter(ImageFilter.MinFilter(7))
    nearby = binary.filter(ImageFilter.MaxFilter(7))
    opaque = solid.load()
    band = nearby.load()
    output = Image.new("RGBA", source.size)
    out = output.load()
    alpha = Image.new("L", source.size)
    alphas = alpha.load()
    offsets = sorted(
        ((dx, dy) for dy in range(-7, 8) for dx in range(-7, 8)),
        key=lambda point: point[0] ** 2 + point[1] ** 2,
    )
    for y in range(208, 1045):
        bg = row_background[y]
        for x in range(273, 982):
            if opaque[x, y]:
                out[x, y] = (*pixels[x, y], 255)
                alphas[x, y] = 255
            elif band[x, y]:
                reference = next(
                    (pixels[x + dx, y + dy] for dx, dy in offsets if opaque[x + dx, y + dy]),
                    None,
                )
                if reference is None:
                    continue
                direction = tuple(reference[channel] - bg[channel] for channel in range(3))
                denominator = sum(value * value for value in direction)
                a = min(1.0, max(0.0, sum(
                    (pixels[x, y][channel] - bg[channel]) * direction[channel]
                    for channel in range(3)
                ) / denominator)) if denominator else 0.0
                # Reject background texture well outside the antialiased edge.
                if a < 0.12:
                    continue
                color = tuple(min(255, max(0, round(
                    (pixels[x, y][channel] - (1 - a) * bg[channel]) / a
                ))) for channel in range(3))
                out[x, y] = (*color, round(a * 255))
                alphas[x, y] = round(a * 255)
    return output, alpha


def adaptive_layers(foreground: Image.Image, alpha: Image.Image) -> tuple[Image.Image, Image.Image, dict]:
    """Place the entire motif inside the Android 66/108 circular safe zone."""
    center = (627.0, 627.0)
    solid = alpha.load()
    bounds = alpha.getbbox()
    assert bounds
    radius = max(
        math.hypot(x - center[0], y - center[1])
        for y in range(bounds[1], bounds[3])
        for x in range(bounds[0], bounds[2])
        if solid[x, y] >= 32
    )
    # 32.5 dp radius leaves 0.5 dp clearance inside the 33 dp safe radius.
    factor = 325 / radius
    canvas = Image.new("RGBA", (1080, 1080))
    transformed = foreground.resize((round(foreground.width * factor),) * 2, SCALE)
    location = (round(540 - center[0] * factor), round(540 - center[1] * factor))
    canvas.alpha_composite(transformed, location)
    rendered_alpha = canvas.getchannel("A")
    rendered_pixels = rendered_alpha.load()
    rendered_bounds = rendered_alpha.getbbox()
    assert rendered_bounds
    rendered_radius = max(
        math.hypot(x - 540, y - 540)
        for y in range(rendered_bounds[1], rendered_bounds[3])
        for x in range(rendered_bounds[0], rendered_bounds[2])
        if rendered_pixels[x, y] >= 32
    )

    # Android 13 themed icon: the same paper outline, note and lyric strokes.
    # An outline preserves all three elements in a single ink color; a solid
    # paper silhouette would hide the musical content.
    outline = ImageChops.subtract(alpha, alpha.filter(ImageFilter.MinFilter(43)))
    ink = Image.new("L", foreground.size)
    ink_pixels = ink.load()
    original = foreground.load()
    for y in range(330, 930):
        for x in range(375, 885):
            r, g, b, a = original[x, y]
            if a and g < 220 and r < 225:
                ink_pixels[x, y] = round(min(1, max(0, (247 - g) / 75)) * a)
    themed = ImageChops.lighter(outline, ink)
    mono = Image.new("RGBA", foreground.size, (255, 255, 255, 0))
    mono.putalpha(themed)
    mono_canvas = Image.new("RGBA", canvas.size)
    mono_canvas.alpha_composite(mono.resize(transformed.size, SCALE), location)
    info = {
        "sourceMotifBounds": bounds,
        "sourceMaxRadius": round(radius, 3),
        "adaptiveScale": round(factor, 6),
        "adaptiveCanvasPixels": 1080,
        "safeCircleRadiusPixels": 330,
        "targetMotifRadiusPixels": 325,
        "renderedMotifRadiusPixelsAlpha32": round(rendered_radius, 3),
        "minimumSafeCircleClearancePixelsAlpha32": round(330 - rendered_radius, 3),
        "minimumSafeCircleClearanceDpAlpha32": round((330 - rendered_radius) / 10, 3),
        "backgroundRGB": BACKGROUND,
    }
    return canvas, mono_canvas, info


def android_mask(size: int, shape: str) -> Image.Image:
    quality = 4
    large = size * quality
    mask = Image.new("L", (large, large))
    draw = ImageDraw.Draw(mask)
    if shape == "circle":
        draw.ellipse((0, 0, large - 1, large - 1), fill=255)
    elif shape == "rounded-square":
        draw.rounded_rectangle((0, 0, large - 1, large - 1), large * .22, fill=255)
    elif shape == "squircle":
        points = []
        for step in range(721):
            angle = step / 720 * math.tau
            cosine, sine = math.cos(angle), math.sin(angle)
            points.append(((1 + math.copysign(abs(cosine) ** .5, cosine)) * (large - 1) / 2,
                           (1 + math.copysign(abs(sine) ** .5, sine)) * (large - 1) / 2))
        draw.polygon(points, fill=255)
    else:
        raise ValueError(shape)
    return mask.resize((size, size), SCALE)


def simulate_android(foreground: Image.Image, shape: str, size: int = 256, monochrome: bool = False) -> Image.Image:
    base = Image.new("RGBA", foreground.size, (*BACKGROUND, 255))
    if monochrome:
        ink = Image.new("RGBA", foreground.size, (98, 74, 153, 0))
        ink.putalpha(foreground.getchannel("A"))
        base.alpha_composite(ink)
    else:
        base.alpha_composite(foreground)
    # Adaptive layer 108dp; the normal launcher viewport is the central 72dp.
    base = base.crop((180, 180, 900, 900)).resize((size, size), SCALE)
    base.putalpha(android_mask(size, shape))
    return base


def preview(master: Image.Image, foreground: Image.Image, mono: Image.Image) -> None:
    sheet = Image.new("RGB", (1280, 1180), (242, 243, 248))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=19)
    small = ImageFont.load_default(size=16)
    draw.text((28, 18), "Windows ICO: actual pixel sizes on light / dark", fill=(40, 38, 55), font=font)
    x = 28
    for size in (16, 32, 48, 256):
        cell_width = max(180, size + 48)
        for row, color in enumerate(((255, 255, 255), (31, 33, 42))):
            top = 64 + row * 310
            draw.rounded_rectangle((x, top, x + cell_width - 16, top + 295), radius=10, fill=color)
            icon = master.resize((size, size), SCALE)
            sheet.paste(icon, (x + (cell_width - 16 - size) // 2, top + (270 - size) // 2), icon)
            label = (x + 10, top + 272)
            draw.text(label, f"{size} x {size}", fill=(122, 120, 135) if row == 0 else (219, 218, 229), font=small)
        x += cell_width
    draw.text((28, 704), "Android adaptive: circle / rounded square / squircle / themed", fill=(40, 38, 55), font=font)
    for index, shape in enumerate(("circle", "rounded-square", "squircle", "circle")):
        icon = simulate_android(mono if index == 3 else foreground, shape, 256, index == 3)
        x = 28 + index * 312
        sheet.paste(icon, (x, 750), icon)
        draw.text((x, 1017), "themed" if index == 3 else shape, fill=(80, 77, 96), font=small)
    draw.text((28, 1062), "Android circular launcher at 48px: actual size on light / dark", fill=(40, 38, 55), font=font)
    small_icon = simulate_android(foreground, "circle", 48)
    sheet.paste(small_icon, (28, 1100), small_icon)
    draw.rounded_rectangle((105, 1090, 175, 1160), radius=8, fill=(31, 33, 42))
    sheet.paste(small_icon, (116, 1101), small_icon)
    REVIEW.mkdir(parents=True, exist_ok=True)
    sheet.save(REVIEW / "platform-previews.png")


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    source_path = ASSETS / "approved-source.png"
    source_hash = hashlib.sha256(source_path.read_bytes()).hexdigest()
    if source_hash != SOURCE_SHA256:
        raise ValueError("The source does not match the user-approved design SHA256.")
    source = Image.open(source_path).convert("RGB")
    if source.size != (1254, 1254):
        raise ValueError("Expected the approved 1254 x 1254 source; do not substitute another design.")
    master = windows_master(source)
    master.save(ASSETS / "app_icon.png")
    print("Created assets/icons/app_icon.png", flush=True)
    foreground, alpha = extract_foreground(source)
    foreground.save(ASSETS / "motif.png")
    adaptive, mono, report = adaptive_layers(foreground, alpha)
    adaptive.save(ASSETS / "adaptive_foreground.png")
    mono.save(ASSETS / "adaptive_monochrome.png")
    Image.new("RGB", (1080, 1080), BACKGROUND).save(ASSETS / "adaptive_background.png")
    ico_path = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    master.save(ico_path, sizes=[(size, size) for size in ICO_SIZES])
    for density, factor in DENSITIES.items():
        directory = RES / f"mipmap-{density}"
        directory.mkdir(parents=True, exist_ok=True)
        legacy_size = round(48 * factor)
        master.resize((legacy_size, legacy_size), SCALE).save(directory / "ic_launcher.png")
        simulate_android(adaptive, "circle", legacy_size).save(directory / "ic_launcher_round.png")
        layer_size = round(108 * factor)
        adaptive.resize((layer_size, layer_size), SCALE).save(directory / "ic_launcher_foreground.png")
        mono.resize((layer_size, layer_size), SCALE).save(directory / "ic_launcher_monochrome.png")
    adaptive_xml = '<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n    <background android:drawable="@color/ic_launcher_background" />\n    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n{monochrome}</adaptive-icon>\n'
    for qualifier, monochrome in (("anydpi-v26", ""), ("anydpi-v33", '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n')):
        directory = RES / f"mipmap-{qualifier}"
        directory.mkdir(parents=True, exist_ok=True)
        for name in ("ic_launcher", "ic_launcher_round"):
            (directory / f"{name}.xml").write_text(adaptive_xml.format(monochrome=monochrome), encoding="utf-8")
    colors = RES / "values" / "icon_colors.xml"
    colors.write_text('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#ECE8FD</color>\n</resources>\n', encoding="utf-8")
    report["sourceSHA256"] = source_hash
    report["windowsIcoSizes"] = ICO_SIZES
    report["legacySizes"] = {density: round(48 * factor) for density, factor in DENSITIES.items()}
    report["adaptiveLayerSizes"] = {density: round(108 * factor) for density, factor in DENSITIES.items()}
    (ASSETS / "generation.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    preview(master, adaptive, mono)
    print(json.dumps(report, indent=2))
    print(f"Preview: {REVIEW / 'platform-previews.png'}")


if __name__ == "__main__":
    main()
