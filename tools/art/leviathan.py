"""Build the Salvage Leviathan and its beam drone from their SpriteCook sources.

  boss:   the source is a flat side-on disc 96 px across with a docking arm on
          top and a smaller one underneath. The top arm's boom is lengthened so
          its claw hangs past the hull's shoulder, with room for a drone below
          it, then the arm is mirrored onto the bottom so both docks match.
  drone:  cut from a sheet where SpriteCook drew the drones beside the boss, so
          they share its pixel size and line weight.
Both are then scaled 6/5 with nearest-neighbour, which keeps their hard pixels
and makes the disc 115 px: the boss's hit radius.
Usage: uv run --no-project --with pillow python tools/art/leviathan.py
"""
from PIL import Image, ImageEnhance

SRC = "art/source/bosses/"
OUT = "art/sprites/bosses/"
SCALE = 1.2
ARM_ROWS = 19  # source rows above the disc that hold the top arm
BOOM_ROWS = 8  # of those, the rows of the horizontal boom
BOOM_SPLIT = 40  # the boom is cut at this column, just left of its elbow...
BOOM_EXTRA = 14  # ...and this many columns of plain boom are added there
ARM_SHADE = 0.85  # the mirrored arm sits on the unlit underside
DRONE_BOX = (5, 88, 31, 119)  # the lower drone on the sheet


def _scaled(im: Image.Image) -> Image.Image:
    im.putalpha(im.getchannel("A").point(lambda v: 255 if v > 110 else 0))
    return im.resize((round(im.size[0] * SCALE), round(im.size[1] * SCALE)), Image.NEAREST)


def boss() -> Image.Image:
    im = Image.open(SRC + "salvage_leviathan_source.png").convert("RGBA")
    im = im.crop(im.getbbox())
    w, h = im.size
    arm = im.crop((0, 0, w, ARM_ROWS))
    longer = Image.new("RGBA", arm.size, (0, 0, 0, 0))
    longer.paste(arm.crop((BOOM_EXTRA, 0, BOOM_SPLIT, ARM_ROWS)), (0, 0))
    longer.paste(arm.crop((BOOM_SPLIT - BOOM_EXTRA, 0, BOOM_SPLIT, BOOM_ROWS)), (BOOM_SPLIT - BOOM_EXTRA, 0))
    longer.paste(arm.crop((BOOM_SPLIT, 0, w, ARM_ROWS)), (BOOM_SPLIT, 0))
    im.paste(longer, (0, 0))
    under = longer.transpose(Image.FLIP_TOP_BOTTOM)
    shaded = ImageEnhance.Brightness(under.convert("RGB")).enhance(ARM_SHADE)
    shaded.putalpha(under.getchannel("A"))
    im.paste(shaded, (0, h - ARM_ROWS))
    return _scaled(im)


def drone() -> Image.Image:
    sheet = Image.open(SRC + "leviathan_drone_sheet_source.png").convert("RGBA")
    return _scaled(sheet.crop(DRONE_BOX))


if __name__ == "__main__":
    for name, img in {"salvage_leviathan.png": boss(), "beam_drone.png": drone()}.items():
        img.save(OUT + name)
        print(OUT + name, img.size)
