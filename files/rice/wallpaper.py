"""Procedural Catppuccin Mocha wallpaper: aurora blobs + flowing contour lines + grain."""
import math
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

W, H = (int(v) for v in sys.argv[1].split("x"))
OUT = sys.argv[2]
SEED = int(sys.argv[3]) if len(sys.argv) > 3 else 46
SS = 2  # supersample for anti-aliased lines
random.seed(SEED)
j = lambda v, d=0.08: v + random.uniform(-d, d)

CRUST, MANTLE, BASE = (17, 17, 27), (24, 24, 37), (30, 30, 46)
MAUVE, PINK, BLUE, LAVENDER, SAPPHIRE = (203, 166, 247), (245, 194, 231), (137, 180, 250), (180, 190, 254), (116, 199, 236)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


# 1. vertical gradient crust -> base -> mantle
bg = Image.new("RGB", (1, H))
for y in range(H):
    t = y / (H - 1)
    bg.putpixel((0, y), lerp(CRUST, BASE, t * 2) if t < 0.5 else lerp(BASE, MANTLE, (t - 0.5) * 2))
bg = bg.resize((W, H))

# 2. aurora blobs, heavily blurred, screened on
glow = Image.new("RGB", (W, H), (0, 0, 0))
gd = ImageDraw.Draw(glow)
for cx, cy, r, col, k in [
    (j(0.82), j(0.78), 0.42, MAUVE, 0.55),
    (j(0.62), j(0.95), 0.30, PINK, 0.35),
    (j(0.95), j(0.40), 0.28, BLUE, 0.40),
    (j(0.10), j(0.12), 0.30, LAVENDER, 0.22),
]:
    c = tuple(int(v * k) for v in col)
    R = r * W
    gd.ellipse([cx * W - R, cy * H - R * 0.8, cx * W + R, cy * H + R * 0.8], fill=c)
glow = glow.filter(ImageFilter.GaussianBlur(W * 0.11))
img = ImageChops.screen(bg, glow)

# 3. flowing contour lines (supersampled), tinted mauve -> blue across the screen
lines = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
ld = ImageDraw.Draw(lines)
N = 34
phase = [random.uniform(0, math.tau) for _ in range(3)]
for i in range(N):
    t = i / (N - 1)
    base_y = H * (0.30 + 0.75 * t)
    amp = H * (0.05 + 0.06 * t)
    pts = []
    for xs in range(0, W * SS + 1, 6):
        x = xs / SS
        u = x / W
        y = (base_y
             - H * 0.35 * u * u  # sweep upward toward the right
             + amp * math.sin(u * 5.2 + phase[0] + t * 1.3)
             + amp * 0.45 * math.sin(u * 11.0 + phase[1] - t * 2.1)
             + amp * 0.20 * math.sin(u * 23.0 + phase[2]))
        pts.append((xs, y * SS))
    col = lerp(MAUVE, SAPPHIRE, t)
    alpha = int(18 + 70 * math.sin(math.pi * t) ** 2)
    ld.line(pts, fill=col + (alpha,), width=SS * 2 if i % 6 == 0 else SS)
lines = lines.resize((W, H), Image.LANCZOS)
img = img.convert("RGBA")
img.alpha_composite(lines)

# 4. vignette
vig = Image.new("L", (W, H), 0)
ImageDraw.Draw(vig).ellipse([-W * 0.25, -H * 0.25, W * 1.25, H * 1.25], fill=255)
vig = vig.filter(ImageFilter.GaussianBlur(W * 0.12))
dark = Image.new("RGBA", (W, H), CRUST + (255,))
img = Image.composite(img, dark, vig)

# 5. film grain
noise = Image.effect_noise((W, H), 22).convert("RGBA")
noise.putalpha(10)
img.alpha_composite(noise)

img.convert("RGB").save(OUT, optimize=True)
print("wrote", OUT, img.size)
