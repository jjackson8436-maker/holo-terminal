"""Turns TTF fonts into Garmin bitmap fonts (BMFont text .fnt + .png), white glyphs on transparent.

Usage: python gen_fonts.py   (writes into holoface/resources/fonts)
"""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "fonts-src")
OUT = os.path.join(HERE, "holoface", "resources", "fonts")

DIGITS = "0123456789:"
TEXT = "".join(chr(c) for c in range(32, 127)) + "°"

# name, ttf, pixel size, characters, variable-font weight (or None)
FONTS = [
    ("vt_time", "VT323-Regular.ttf", 130, DIGITS, None),
    ("vt_small", "VT323-Regular.ttf", 34, TEXT, None),
    ("orb_time", "Orbitronwght.ttf", 70, DIGITS, b"Black"),
    ("orb_small", "Orbitronwght.ttf", 20, TEXT, b"Bold"),
    ("orb_date", "Orbitronwght.ttf", 27, TEXT, b"Black"),
    ("orb_label", "Orbitronwght.ttf", 15, TEXT, b"Bold"),
    ("vt_label", "VT323-Regular.ttf", 24, TEXT, None),
]


def build(name, ttf, size, chars, weight):
    font = ImageFont.truetype(os.path.join(SRC, ttf), size)
    if weight:
        font.set_variation_by_name(weight)
    ascent, descent = font.getmetrics()
    line_h = ascent + descent
    pad = 2
    glyphs = []
    for ch in chars:
        l, t, r, b = font.getbbox(ch)
        w, h = max(r - l, 1), max(b - t, 1)
        glyphs.append((ch, l, t, w, h, round(font.getlength(ch))))
    # Pack in rows.
    sheet_w = 1024
    x = y = row_h = 0
    places = []
    for g in glyphs:
        w, h = g[3], g[4]
        if x + w + pad > sheet_w:
            x, y, row_h = 0, y + row_h + pad, 0
        places.append((x, y))
        x += w + pad
        row_h = max(row_h, h)
    sheet_h = y + row_h + pad
    img = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    lines = []
    for (ch, l, t, w, h, adv), (px, py) in zip(glyphs, places):
        draw.text((px - l, py - t), ch, font=font, fill=(255, 255, 255, 255))
        lines.append(f"char id={ord(ch)} x={px} y={py} width={w} height={h} "
                     f"xoffset={l} yoffset={t} xadvance={adv} page=0 chnl=15")
    img = img.crop((0, 0, max(px + w for (ch, l, t, w, h, adv), (px, py) in zip(glyphs, places)) + pad, sheet_h))
    img.save(os.path.join(OUT, name + ".png"))
    with open(os.path.join(OUT, name + ".fnt"), "w") as f:
        f.write(f'info face="{name}" size={size} bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=0,0\n')
        f.write(f"common lineHeight={line_h} base={ascent} scaleW={img.width} scaleH={img.height} pages=1 packed=0\n")
        f.write(f'page id=0 file="{name}.png"\n')
        f.write(f"chars count={len(lines)}\n")
        f.write("\n".join(lines) + "\n")
    # Height of the digit "0" as drawn, for layout.
    l, t, r, b = font.getbbox("0")
    print(f"{name}: sheet {img.width}x{img.height}, lineHeight {line_h}, digit top {t} height {b - t}")


os.makedirs(OUT, exist_ok=True)
for spec in FONTS:
    build(*spec)
