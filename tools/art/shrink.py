"""Shrink a full-detail SpriteCook image to an in-game pixel-art sprite.

SpriteCook returns ~100-200 px images regardless of the requested size, and a
nearest-neighbour shrink turns them into noise. This crops to content, area-
averages down to the target width, hardens the alpha edge and snaps colours to
a small palette so the result reads as clean pixel art.

Usage (from the project root):
    uv run --no-project --with pillow python tools/art/shrink.py SRC DEST WIDTH [--flip] [--colors N] [--preview]

--flip      mirror horizontally (e.g. a ship generated facing the wrong way)
--lift X    brighten by X (0.18 = +18%) with a little extra contrast, so dark
            sprites still read against the dark background
--preview   also write DEST with "_preview" at 5x over the game's background
"""
import argparse
from PIL import Image, ImageEnhance

BG = (10, 12, 26, 255)  # the starfield's background colour


def shrink(src: str, width: int, colors: int = 32, flip: bool = False, lift: float = 0.0) -> Image.Image:
    im = Image.open(src).convert("RGBA")
    im = im.crop(im.getbbox())
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    height = max(1, round(im.size[1] * width / im.size[0]))
    small = im.resize((width, height), Image.BOX)
    alpha = small.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    rgb = small.convert("RGB")
    if lift:
        rgb = ImageEnhance.Brightness(rgb).enhance(1.0 + lift)
        rgb = ImageEnhance.Contrast(rgb).enhance(1.0 + lift * 0.5)
    rgb = rgb.quantize(colors=colors, method=Image.Quantize.MEDIANCUT,
                                        dither=Image.Dither.NONE).convert("RGB")
    out = rgb.copy()
    out.putalpha(alpha)
    return out.crop(out.getbbox())


def preview(img: Image.Image, scale: int = 5) -> Image.Image:
    bg = Image.new("RGBA", img.size, BG)
    bg.alpha_composite(img)
    return bg.resize((img.size[0] * scale, img.size[1] * scale), Image.NEAREST)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dest")
    ap.add_argument("width", type=int)
    ap.add_argument("--colors", type=int, default=32)
    ap.add_argument("--flip", action="store_true")
    ap.add_argument("--lift", type=float, default=0.0)
    ap.add_argument("--preview", action="store_true")
    a = ap.parse_args()
    out = shrink(a.src, a.width, a.colors, a.flip, a.lift)
    out.save(a.dest)
    if a.preview:
        preview(out).save(a.dest.replace(".png", "_preview.png"))
    print(a.dest, out.size)
