#!/usr/bin/env python3
"""Regenerate the RNP app icon set for the container app.

Recreates the RNP logo (the two overlapping circles with the teal lens and
the "rnp" wordmark from `icon.png` at the repo root) at icon-set resolution
on a macOS-style rounded tile, then writes every slot of

    Swift-Rnp/MailExtensionsContainer/Assets.xcassets/AppIcon.appiconset

Run from the repo root:

    python3 scripts/generate-app-icon.py

Requires Pillow (`python3 -m pip install --user Pillow`).
"""

import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONSET = os.path.join(
    REPO_ROOT,
    "Swift-Rnp/MailExtensionsContainer/Assets.xcassets/AppIcon.appiconset",
)

# Brand colors sampled from icon.png.
YELLOW = (255, 220, 74, 255)   # #FFDC4A
BLUE = (26, 123, 236, 255)     # #1A7BEC
TEAL = (0, 223, 183, 255)      # #00DFB7
NAVY = (46, 51, 73, 255)       # #2E3349

# Logo geometry in the original 280x280 artboard (measured from icon.png).
YELLOW_CENTER = (105.0, 75.0)
BLUE_CENTER = (173.0, 75.0)
CIRCLE_R = 50.0
LENS_KEYLINE_R = 58.0  # white outline around the teal lens
LENS_R = 52.0          # teal lens itself
TEXT_BOX = (30.0, 154.0, 268.0, 260.0)  # "rnp" ink bbox (x0, y0, x1, y1)

# Full logo block used for centering (circles + wordmark).
LOGO_BOX = (30.0, 24.0, 268.0, 260.0)
# Circles-only block used for small icon sizes (wordmark illegible < 128 px).
MARK_BOX = (54.0, 24.0, 224.0, 126.0)

FONT_CANDIDATES = [
    ("/System/Library/Fonts/SFCompactRounded.ttf", 0),
    ("/System/Library/Fonts/HelveticaNeue.ttc", 1),  # Bold face
    ("/System/Library/Fonts/Helvetica.ttc", 1),      # Bold face
]

TILE_RADIUS_RATIO = 0.2237  # macOS icon corner radius approximation


def load_font(size):
    for path, index in FONT_CANDIDATES:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size=size, index=index)
            except OSError:
                continue
    raise RuntimeError("no usable system font found for the wordmark")


def circle_mask(size, center, radius):
    """L-mode mask with a filled circle, drawn at the given (float) coords."""
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    x, y = center
    draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=255)
    return mask


def intersection(mask_a, mask_b):
    from PIL.ImageChops import multiply
    return multiply(mask_a, mask_b)


def draw_logo(canvas, origin, scale, with_wordmark):
    """Draw the RNP logo into `canvas`.

    `origin` is the pixel position of artboard coordinate (0, 0); `scale` is
    the artboard-to-pixel factor.
    """
    ox, oy = origin
    size = canvas.size

    def scaled(point):
        return (ox + point[0] * scale, oy + point[1] * scale)

    yellow = circle_mask(size, scaled(YELLOW_CENTER), CIRCLE_R * scale)
    blue = circle_mask(size, scaled(BLUE_CENTER), CIRCLE_R * scale)
    keyline = intersection(
        circle_mask(size, scaled(YELLOW_CENTER), LENS_KEYLINE_R * scale),
        circle_mask(size, scaled(BLUE_CENTER), LENS_KEYLINE_R * scale),
    )
    lens = intersection(
        circle_mask(size, scaled(YELLOW_CENTER), LENS_R * scale),
        circle_mask(size, scaled(BLUE_CENTER), LENS_R * scale),
    )

    canvas.paste(Image.new("RGBA", size, YELLOW), (0, 0), yellow)
    canvas.paste(Image.new("RGBA", size, BLUE), (0, 0), blue)
    canvas.paste(Image.new("RGBA", size, (255, 255, 255, 255)), (0, 0), keyline)
    canvas.paste(Image.new("RGBA", size, TEAL), (0, 0), lens)

    if with_wordmark:
        target_w = (TEXT_BOX[2] - TEXT_BOX[0]) * scale
        # Binary-search the font size so the wordmark ink matches the logo.
        lo, hi = 8, int(400 * scale)
        best = None
        while lo <= hi:
            mid = (lo + hi) // 2
            font = load_font(mid)
            bbox = font.getbbox("rnp")
            width = bbox[2] - bbox[0]
            if width < target_w:
                lo = mid + 1
            else:
                hi = mid - 1
            best = (mid, font, bbox)
        _, font, bbox = best
        x = ox + TEXT_BOX[0] * scale - bbox[0]
        y = oy + TEXT_BOX[1] * scale - bbox[1]
        ImageDraw.Draw(canvas).text((x, y), "rnp", font=font, fill=NAVY)


def rounded_rect_mask(size, inset, radius):
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        [inset, inset, size[0] - inset - 1, size[1] - inset - 1],
        radius=radius,
        fill=255,
    )
    return mask


def render_icon(pixels, with_wordmark):
    """Render one icon slot at `pixels` x `pixels`."""
    ss = 4  # supersampling factor
    size = (pixels * ss, pixels * ss)
    tile = Image.new("RGBA", size, (0, 0, 0, 0))

    # White tile with a subtle vertical gradient, clipped to the squircle.
    inset = 0
    radius = int(size[0] * TILE_RADIUS_RATIO)
    mask = rounded_rect_mask(size, inset, radius)
    gradient_column = Image.new("RGBA", (1, size[1]))
    top = (255, 255, 255, 255)
    bottom = (241, 244, 250, 255)
    for y in range(size[1]):
        t = y / max(1, size[1] - 1)
        gradient_column.putpixel(
            (0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(4))
        )
    gradient = gradient_column.resize(size, Image.BILINEAR)
    tile.paste(gradient, (0, 0), mask)

    # Logo layer, scaled into the tile and clipped to the squircle.
    logo = Image.new("RGBA", size, (0, 0, 0, 0))
    box = LOGO_BOX if with_wordmark else MARK_BOX
    box_w = box[2] - box[0]
    box_h = box[3] - box[1]
    fill = 0.78 if with_wordmark else 0.62
    scale = size[0] * fill / box_w
    ox = (size[0] - box_w * scale) / 2 - box[0] * scale
    oy = (size[1] - box_h * scale) / 2 - box[1] * scale
    draw_logo(logo, (ox, oy), scale, with_wordmark)

    empty = Image.new("RGBA", size, (0, 0, 0, 0))
    tile.alpha_composite(Image.composite(logo, empty, mask))

    # 1 px inner hairline for definition against dark docks.
    hairline = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(hairline).rounded_rectangle(
        [inset + ss // 2, inset + ss // 2, size[0] - inset - ss // 2 - 1, size[1] - inset - ss // 2 - 1],
        radius=radius,
        outline=(30, 40, 60, 20),
        width=ss,
    )
    tile.alpha_composite(hairline)

    return tile.resize((pixels, pixels), Image.LANCZOS)


def main():
    os.makedirs(ICONSET, exist_ok=True)
    slots = [
        ("16x16", "1x", 16),
        ("16x16", "2x", 32),
        ("32x32", "1x", 32),
        ("32x32", "2x", 64),
        ("128x128", "1x", 128),
        ("128x128", "2x", 256),
        ("256x256", "1x", 256),
        ("256x256", "2x", 512),
        ("512x512", "1x", 512),
        ("512x512", "2x", 1024),
    ]
    images = []
    for slot, scale, pixels in slots:
        filename = "icon_%s%s.png" % (slot, "" if scale == "1x" else "@2x")
        icon = render_icon(pixels, with_wordmark=pixels >= 128)
        icon.save(os.path.join(ICONSET, filename))
        images.append({"idiom": "mac", "scale": scale, "size": slot, "filename": filename})
        print("wrote %s (%d px, %s)" % (filename, pixels, "wordmark" if pixels >= 128 else "mark only"))

    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    with open(os.path.join(ICONSET, "Contents.json"), "w") as fh:
        json.dump(contents, fh, indent=2, sort_keys=False)
        fh.write("\n")
    print("updated Contents.json")


if __name__ == "__main__":
    sys.exit(main())
