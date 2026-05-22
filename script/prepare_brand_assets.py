#!/usr/bin/env python3
from __future__ import annotations

import argparse
import collections
import subprocess
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ICON = Path("/Users/eminganbarov/Downloads/ChatGPT Image 22 мая 2026 г., 11_30_38 (1).png")
DEFAULT_LOGO = Path("/Users/eminganbarov/Downloads/ChatGPT Image 22 мая 2026 г., 11_30_38 (2).png")
ICONSET_SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def remove_light_edge_background(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    queue: collections.deque[tuple[int, int]] = collections.deque()
    visited: set[tuple[int, int]] = set()

    for x in range(width):
        queue.append((x, 0))
        queue.append((x, height - 1))
    for y in range(height):
        queue.append((0, y))
        queue.append((width - 1, y))

    def is_background(pixel: tuple[int, int, int, int]) -> bool:
        r, g, b, a = pixel
        if a == 0:
            return True
        light = min(r, g, b) >= 212
        low_chroma = max(r, g, b) - min(r, g, b) <= 18
        return light and low_chroma

    while queue:
        x, y = queue.popleft()
        if (x, y) in visited or x < 0 or y < 0 or x >= width or y >= height:
            continue
        visited.add((x, y))
        if not is_background(pixels[x, y]):
            continue
        pixels[x, y] = (255, 255, 255, 0)
        queue.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))

    return rgba


def trim_transparent(image: Image.Image, padding: int = 24) -> Image.Image:
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        return image
    left, top, right, bottom = bbox
    left = max(0, left - padding)
    top = max(0, top - padding)
    right = min(image.width, right + padding)
    bottom = min(image.height, bottom + padding)
    return image.crop((left, top, right, bottom))


def save_icon(icon_source: Path) -> None:
    brand_dir = ROOT / "Resources" / "Brand"
    iconset_dir = ROOT / "Resources" / "AppIcon.iconset"
    brand_dir.mkdir(parents=True, exist_ok=True)
    iconset_dir.mkdir(parents=True, exist_ok=True)

    icon = remove_light_edge_background(Image.open(icon_source))
    icon = icon.resize((1024, 1024), Image.Resampling.LANCZOS)
    icon.save(brand_dir / "vestor-app-icon-1024.png")
    icon.save(brand_dir / "vestor-app-icon-source-transparent.png")
    icon.save(brand_dir / "VestorAppIcon.png")

    for filename, size in ICONSET_SIZES.items():
        icon.resize((size, size), Image.Resampling.LANCZOS).save(iconset_dir / filename)

    subprocess.run(
        ["iconutil", "-c", "icns", str(iconset_dir), "-o", str(ROOT / "Resources" / "AppIcon.icns")],
        check=True,
    )


def save_logo(logo_source: Path) -> None:
    brand_dir = ROOT / "Resources" / "Brand"
    docs_assets = ROOT / "docs" / "assets"
    brand_dir.mkdir(parents=True, exist_ok=True)
    docs_assets.mkdir(parents=True, exist_ok=True)

    logo = trim_transparent(remove_light_edge_background(Image.open(logo_source)), padding=32)
    logo.save(brand_dir / "VestorLogo.png")
    logo.save(brand_dir / "vestor-logo-board-02.png")
    logo.save(docs_assets / "vestor-logo.png")


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare Vestor icon and logo assets.")
    parser.add_argument("--icon", type=Path, default=DEFAULT_ICON)
    parser.add_argument("--logo", type=Path, default=DEFAULT_LOGO)
    args = parser.parse_args()

    save_icon(args.icon)
    save_logo(args.logo)


if __name__ == "__main__":
    main()
