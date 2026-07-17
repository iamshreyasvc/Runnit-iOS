#!/usr/bin/env python3
"""Regenerate the Runnit app icon: the journey-line 'S', restyled as thick
grainy-white strokes with mode-colored borders (blue flight, green road,
orange train), keeping the airplane. Doubled line thickness, less flat color."""
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 1024
BG = (16, 17, 22)
BLUE = (98, 181, 255)
GREEN = (62, 214, 126)
ORANGE = (255, 168, 23)

R_OUT = 52      # colored border radius (was ~half of this before -> doubled)
R_IN = 38       # grainy-white core radius

# --- S geometry (serpentine): flight top, road middle, train bottom ---
X_LEFT, X_RIGHT = 205, 815
TOP_Y, MID_Y, BOT_Y = 350, 552, 754
TOP_RIGHT = 655          # where the top line ends and the plane takes over
R_ARC = (MID_Y - TOP_Y) / 2


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def line_pts(x0, y0, x1, y1, c0, c1, step=3):
    n = max(2, int(np.hypot(x1 - x0, y1 - y0) / step))
    for i in range(n + 1):
        t = i / n
        yield (x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, lerp(c0, c1, t))


def left_arc(c0, c1, n=140):
    cy = (TOP_Y + MID_Y) / 2
    for i in range(n + 1):
        t = np.pi * i / n
        x = X_LEFT - R_ARC * np.sin(t)
        y = cy - R_ARC * np.cos(t)
        yield (x, y, lerp(c0, c1, i / n))


def right_arc(c0, c1, n=140):
    cy = (MID_Y + BOT_Y) / 2
    for i in range(n + 1):
        t = np.pi * i / n
        x = X_RIGHT + R_ARC * np.sin(t)
        y = cy - R_ARC * np.cos(t)
        yield (x, y, lerp(c0, c1, i / n))


def centerline():
    pts = []
    # top (flight) right -> left
    pts += list(line_pts(TOP_RIGHT, TOP_Y, X_LEFT, TOP_Y, BLUE, BLUE))
    pts += list(left_arc(BLUE, GREEN))
    pts += list(line_pts(X_LEFT, MID_Y, X_RIGHT, MID_Y, GREEN, GREEN))
    pts += list(right_arc(GREEN, ORANGE))
    pts += list(line_pts(X_RIGHT, BOT_Y, X_LEFT, BOT_Y, ORANGE, ORANGE))
    return pts


def disc(draw, x, y, r, fill):
    draw.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def airplane(tinted=False):
    """A top-view jet silhouette (grainy white with a blue border), angled
    up-right, as its own RGBA layer."""
    box = 460
    cx, cy = box / 2, box / 2
    # Top-half outline of a swept-wing airliner pointing +x (right).
    top = [
        (150, 0), (60, -15), (34, -15), (-52, -96), (-80, -93),
        (-16, -14), (-96, -12), (-134, -50), (-153, -47),
        (-118, -8), (-176, 0),
    ]
    poly = top + [(x, -y) for (x, y) in reversed(top[1:-1])]
    poly = [(cx + x, cy + y) for (x, y) in poly]

    def shrink(pts, k):
        return [(cx + (x - cx) * k, cy + (y - cy) * k) for (x, y) in pts]

    border_col = (210, 210, 210) if tinted else BLUE
    layer = Image.new("RGBA", (box, box), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.polygon(poly, fill=border_col + (255,))          # blue border
    d.polygon(shrink(poly, 0.80), fill=(245, 249, 255, 255))  # white body
    return layer.rotate(26, resample=Image.BICUBIC, expand=False)


def add_grain(img, mask=None, amt=14, key=None):
    """Add per-pixel noise, optionally only where mask>0."""
    arr = np.array(img).astype(np.int16)
    noise = np.random.default_rng(7).integers(-amt, amt + 1, arr.shape[:2])
    for c in range(3):
        if key is not None:
            base = np.array(img)[:, :, c].astype(np.int16)
            arr[:, :, c] = base + noise
        else:
            arr[:, :, c] = arr[:, :, c] + noise
    arr = np.clip(arr, 0, 255).astype(np.uint8)
    out = Image.fromarray(arr)
    if mask is not None:
        return Image.composite(out, img, mask)
    return out


def render(tinted=False):
    pts = centerline()

    # background with faint grain
    base = Image.new("RGB", (S, S), BG)
    base = add_grain(base, amt=6)

    # soft neon glow under the stroke
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for x, y, c in pts:
        disc(gd, x, y, R_OUT + 4, (c if not tinted else (200, 200, 200)) + (55,))
    glow = glow.filter(ImageFilter.GaussianBlur(22))
    base = Image.alpha_composite(base.convert("RGBA"), glow).convert("RGB")

    # colored border pass
    border = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bd = ImageDraw.Draw(border)
    for x, y, c in pts:
        disc(bd, x, y, R_OUT, (c if not tinted else (210, 210, 210)) + (255,))
    base = Image.alpha_composite(base.convert("RGBA"), border).convert("RGB")

    # grainy-white core: build a mask, fill with high-key noise
    coremask = Image.new("L", (S, S), 0)
    cd = ImageDraw.Draw(coremask)
    for x, y, _ in pts:
        disc(cd, x, y, R_IN, 255)
    white = Image.new("RGB", (S, S), (248, 250, 253))
    white = add_grain(white, amt=16)
    base = Image.composite(white, base, coremask)

    # airplane, flying up-right above the top line's right end
    plane = airplane(tinted=tinted)
    base = base.convert("RGBA")
    base.alpha_composite(plane, (S - 512, 40))
    return base.convert("RGB")


def main():
    import os
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "Runnit iOS/Assets.xcassets/AppIcon.appiconset")
    icon = render()
    icon.save(f"{out}/icon-light.png")
    icon.save(f"{out}/icon-dark.png")
    render(tinted=True).save(f"{out}/icon-tinted.png")
    print("wrote icons to", out)


if __name__ == "__main__":
    main()
