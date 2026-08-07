"""Generate dark/tinted app-icon variants and launch-screen logo assets from
the existing flat-color AppIcon.png (WS4-02). The icon has exactly two flat
colors — background and rings — so a chroma-key distance mask deterministically
separates them, including anti-aliased edges.
"""
import math
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPICON_DIR = os.path.join(ROOT, "ios/PT-Helper/COIL/Assets.xcassets/AppIcon.appiconset")
LAUNCHLOGO_DIR = os.path.join(ROOT, "ios/PT-Helper/COIL/Assets.xcassets/LaunchLogo.imageset")
SRC = os.path.join(APPICON_DIR, "AppIcon.png")

BG = (15, 181, 176)
RING = (14, 28, 34)


def dist(a, b):
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(3)))


BG_RING_DIST = dist(BG, RING)


def ring_alpha_mask(src: Image.Image) -> Image.Image:
    """Per-pixel alpha: 0 at background color, 255 at ring color."""
    px = src.load()
    mask = Image.new("L", src.size)
    mpx = mask.load()
    for y in range(src.height):
        for x in range(src.width):
            r, g, b = px[x, y][:3]
            t = dist((r, g, b), BG) / BG_RING_DIST
            t = max(0.0, min(1.0, t))
            mpx[x, y] = round(255 * t)
    return mask


def solid_with_mask(size, color, mask: Image.Image) -> Image.Image:
    out = Image.new("RGBA", size, color + (0,))
    out.putalpha(mask)
    return out


def main():
    src = Image.open(SRC).convert("RGB")
    mask = ring_alpha_mask(src)

    dark = solid_with_mask(src.size, (44, 199, 194), mask)
    dark.save(os.path.join(APPICON_DIR, "AppIcon-dark.png"))

    tinted = solid_with_mask(src.size, (230, 230, 230), mask)
    tinted.save(os.path.join(APPICON_DIR, "AppIcon-tinted.png"))

    os.makedirs(LAUNCHLOGO_DIR, exist_ok=True)
    small_mask = mask.resize((512, 512), Image.LANCZOS)

    logo_light = solid_with_mask((512, 512), (11, 122, 120), small_mask)
    logo_light.save(os.path.join(LAUNCHLOGO_DIR, "LaunchLogo.png"))

    logo_dark = solid_with_mask((512, 512), (44, 199, 194), small_mask)
    logo_dark.save(os.path.join(LAUNCHLOGO_DIR, "LaunchLogo-dark.png"))

    print("OK")


if __name__ == "__main__":
    main()
