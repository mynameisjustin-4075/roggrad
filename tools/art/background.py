"""Build World 1 background pieces from SpriteCook sources.

  backdrop:  stretch to 736x360, then cross-fade its last 96 px into its first
             96 px so it tiles seamlessly as a 640x360 loop
  debris:    cut each 3x2 debris sheet into pieces; bake a small and a medium
             size, darkened and desaturated so they read as background
  wrecks:    the giant derelict sections, darkened a little, at 3/4 size
Usage: uv run --no-project --with pillow python tools/art/background.py
"""
from PIL import Image, ImageEnhance

SRC = "art/source/background/"
OUT = "art/sprites/background/"
BLEND = 96


def seamless(img: Image.Image, blend: int) -> Image.Image:
    w, h = img.size
    n = w - blend
    out = Image.new("RGB", (n, h))
    src = img.load(); dst = out.load()
    for i in range(n):
        for y in range(h):
            a = src[i + blend, y]
            if i >= n - blend:
                t = (i - (n - blend)) / blend
                b = src[i - (n - blend), y]
                a = tuple(round(a[k] * (1 - t) + b[k] * t) for k in range(3))
            dst[i, y] = a
    return out


def as_background(p: Image.Image, scale: float, brightness: float) -> Image.Image:
    p = p.resize((max(1, round(p.size[0] * scale)), max(1, round(p.size[1] * scale))), Image.BOX)
    alpha = p.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    rgb = ImageEnhance.Brightness(p.convert("RGB")).enhance(brightness)
    rgb = ImageEnhance.Color(rgb).enhance(0.5)
    rgb = rgb.quantize(colors=24, dither=Image.Dither.NONE).convert("RGB")
    rgb.putalpha(alpha)
    return rgb.crop(rgb.getbbox())


if __name__ == "__main__":
    bd = Image.open(SRC + "debris_belt_backdrop_source.png").convert("RGB").resize((640 + BLEND, 360), Image.BOX)
    seamless(bd, BLEND).save(OUT + "debris_belt_backdrop.png")
    count = 0
    for sheet in ("debris_sheet_a.png", "debris_sheet_b.png"):
        im = Image.open(SRC + sheet).convert("RGBA"); w, h = im.size
        for r in range(2):
            for c in range(3):
                cell = im.crop((c * w // 3, r * h // 2, (c + 1) * w // 3, (r + 1) * h // 2))
                if not cell.getbbox():
                    continue
                cell = cell.crop(cell.getbbox())
                for size, scale, bright in (("s", 0.4, 0.4), ("m", 0.65, 0.5)):
                    as_background(cell, scale, bright).save(f"{OUT}debris_{count:02d}_{size}.png")
                count += 1
    for n in "abcd":
        wreck = Image.open(f"{SRC}wreck_{n}_source.png").convert("RGBA")
        as_background(wreck, 0.75, 0.7).save(f"{OUT}wreck_{n}.png")
    print("backdrop + debris pieces:", count, "+ 4 wrecks")
