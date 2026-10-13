"""Draws modrinth/icon.png (512x512 pixel art): an isometric Minecraft-style block in Pizzaplex neon, with a stun spark.
Original art, no game assets.  python modrinth/make_icon.py"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

N = 32  # art pixels
S = 16  # upscale
OUT = Path(__file__).resolve().parent / "icon.png"

BG_TOP, BG_BOTTOM = (24, 6, 40), (6, 2, 14)
TOP_A, TOP_B = (236, 72, 168), (190, 40, 150)      # neon pink checker (the block's top)
LEFT_A, LEFT_B = (92, 30, 120), (70, 20, 98)       # purple side
RIGHT_A, RIGHT_B = (40, 150, 150), (26, 112, 120)  # teal side
EDGE = (255, 230, 250)
SPARK = (255, 236, 90)


def iso_block(px):
    """An isometric cube: top diamond rows 6..13, sides down to row 27, centred on column 16."""
    cx, top, half, side = 16, 6, 11, 13
    for y in range(N):
        for x in range(N):
            dx, dy = x - cx + 0.5, y - top + 0.5
            # top face: |dx| / half + |dy - half/2| / (half/2) <= 1
            if abs(dx) / half + abs(dy - half / 2) / (half / 2) <= 1.0:
                checker = ((x // 2) + (y // 2)) % 2
                px[x, y] = TOP_A if checker else TOP_B
                continue
            # sides: below the top diamond's lower edges, down by `side` rows
            low = half / 2 + (half / 2) * (1 - abs(dx) / half)  # the top face's lower edge at this column
            if abs(dx) <= half and low <= dy <= low + side:
                band = int(dy - low) // 3 % 2
                if dx < 0:
                    px[x, y] = LEFT_A if (band + (x // 3)) % 2 else LEFT_B
                else:
                    px[x, y] = RIGHT_A if (band + (x // 3)) % 2 else RIGHT_B


def main():
    img = Image.new("RGB", (N, N))
    px = img.load()
    for y in range(N):
        t = y / (N - 1)
        c = tuple(int(BG_TOP[i] * (1 - t) + BG_BOTTOM[i] * t) for i in range(3))
        for x in range(N):
            px[x, y] = c
    iso_block(px)
    # the cube's front edge and silhouette highlights
    for y in range(17, 30):
        px[16, y] = EDGE
    # a stun spark (zig-zag) over the top-right
    for x, y in [(25, 2), (24, 3), (25, 4), (26, 4), (25, 5), (24, 6), (25, 7), (26, 8), (27, 7)]:
        px[x, y] = SPARK
    big = img.resize((N * S, N * S), Image.NEAREST)
    # a soft neon glow behind the block
    glow = big.filter(ImageFilter.GaussianBlur(28))
    out = Image.blend(glow, big, 0.82)
    out = Image.composite(big, out, Image.eval(big.convert("L"), lambda v: 255 if v > 40 else 0))
    out.save(OUT)
    print(f"wrote {OUT} {out.size}")


if __name__ == "__main__":
    main()
