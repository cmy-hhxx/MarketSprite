#!/usr/bin/env python3

from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = Path(__file__).resolve().parent
WIDTH = 840
HEIGHT = 600

INK = "#20242A"
CREAM = "#FFF8EE"
ARROW_BLUE = "#009CF0"
DATA_BLUE = "#68AFCB"


def font(size: int, scale: int, *, bold: bool = False) -> ImageFont.FreeTypeFont:
    path = "/System/Library/Fonts/Hiragino Sans GB.ttc"
    return ImageFont.truetype(path, size=size * scale, index=1 if bold else 0)


def mono_font(size: int, scale: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", size=size * scale)


def centered_text(
    draw: ImageDraw.ImageDraw,
    y: int,
    text: str,
    text_font: ImageFont.FreeTypeFont,
    fill: str,
    scale: int,
) -> None:
    left, _, right, _ = draw.textbbox((0, 0), text, font=text_font)
    draw.text(((WIDTH * scale - (right - left)) / 2, y * scale), text, font=text_font, fill=fill)


def paste_mascot(
    canvas: Image.Image,
    path: Path,
    center_x: int,
    top: int,
    size: int,
    opacity: float,
    scale: int,
) -> None:
    mascot = Image.open(path).convert("RGBA")
    mascot.thumbnail((size * scale, size * scale), Image.Resampling.LANCZOS)
    alpha = mascot.getchannel("A")
    alpha = ImageEnhance.Brightness(alpha).enhance(opacity)
    mascot.putalpha(alpha)
    canvas.alpha_composite(mascot, (center_x * scale - mascot.width // 2, top * scale))


def draw_background(scale: int) -> Image.Image:
    width = WIDTH * scale
    height = HEIGHT * scale
    canvas = Image.new("RGBA", (width, height), CREAM)
    pixels = canvas.load()
    for y in range(height):
        for x in range(width):
            logical_x = x / scale
            logical_y = y / scale
            mint_weight = max(0.0, 1.0 - ((logical_x - WIDTH) ** 2 + logical_y**2) ** 0.5 / 820)
            coral_weight = max(0.0, 1.0 - (logical_x**2 + (logical_y - HEIGHT) ** 2) ** 0.5 / 900)
            base = (255, 248, 238)
            rgb = tuple(
                int(
                    base[i] * (1 - 0.06 * mint_weight - 0.035 * coral_weight)
                    + (99, 211, 183)[i] * 0.06 * mint_weight
                    + (255, 115, 95)[i] * 0.035 * coral_weight
                )
                for i in range(3)
            )
            pixels[x, y] = (*rgb, 255)

    glow = Image.new("RGBA", canvas.size, (255, 255, 255, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse(tuple(value * scale for value in (296, 194, 544, 442)), fill=(255, 255, 255, 96))
    glow = glow.filter(ImageFilter.GaussianBlur(42 * scale))
    canvas.alpha_composite(glow)

    draw = ImageDraw.Draw(canvas)
    centered_text(draw, 58, "把行情，安静地放进 Mac。", font(27, scale, bold=True), INK, scale)

    arrow_art = [
        "                          # # #",
        "01 10 11 01 10 11 01  · · ·  # # #",
        "# # # #HAPPY_TRADING!# # # # # # #",
        "10 01 00 11 01 10 11  · · ·  # # #",
        "                          # # #",
    ]
    arrow_font = mono_font(11, scale)
    arrow_layer = Image.new("RGBA", canvas.size, (255, 255, 255, 0))
    arrow_draw = ImageDraw.Draw(arrow_layer)
    cell_width = arrow_draw.textlength("#", font=arrow_font)
    arrow_width = max(len(row) for row in arrow_art) * cell_width
    start_x = (WIDTH * scale - arrow_width) / 2
    start_y = 243 * scale
    for row_index, row in enumerate(arrow_art):
        for column, character in enumerate(row):
            if character != " ":
                arrow_draw.text(
                    (start_x + column * cell_width, start_y + row_index * 18 * scale),
                    character,
                    font=arrow_font,
                    fill=DATA_BLUE if character in "01·" else ARROW_BLUE,
                )

    arrow_glow = arrow_layer.filter(ImageFilter.GaussianBlur(5 * scale))
    arrow_glow.putalpha(arrow_glow.getchannel("A").point(lambda alpha: alpha // 2))
    canvas.alpha_composite(arrow_glow)
    canvas.alpha_composite(arrow_layer)

    bull_path = ROOT / "MarketSprite/Resources/Assets.xcassets/BullMascot.imageset/bull-mascot.png"
    bear_path = ROOT / "MarketSprite/Resources/Assets.xcassets/BearMascot.imageset/bear-mascot.png"
    paste_mascot(canvas, bull_path, 328, 430, 112, 0.92, scale)
    paste_mascot(canvas, bear_path, 512, 430, 112, 0.92, scale)

    return canvas.convert("RGB")


def main() -> None:
    draw_background(1).save(OUTPUT_DIR / "background.png", optimize=True)
    draw_background(2).save(OUTPUT_DIR / "background@2x.png", optimize=True)


if __name__ == "__main__":
    main()
