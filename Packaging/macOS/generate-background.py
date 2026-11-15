"""Render original installer artwork at 1x/2x. Requires Pillow, not used in CI."""
from pathlib import Path
import math
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
FONT = Path("/System/Library/Fonts/SFNS.ttf")


def draw_arrow(canvas: Image.Image, scale: int) -> None:
    origin = (310, 204)
    size = (100, 52)
    samples = 4 * scale
    mask = Image.new("L", tuple(edge * samples for edge in size))
    stroke = ImageDraw.Draw(mask)
    left, tip = (324, 230), (396, 230)
    upper, lower = (379, 213), (379, 247)
    radius = 2

    def point(coordinates: tuple[int, int]) -> tuple[int, int]:
        x, y = coordinates
        return ((x - origin[0]) * samples, (y - origin[1]) * samples)

    for path in ((left, tip), (upper, tip, lower)):
        stroke.line([point(coordinates) for coordinates in path],
                    fill=255, width=2 * radius * samples, joint="curve")
    for coordinates in (left, upper, tip, lower):
        x, y = point(coordinates)
        r = radius * samples
        stroke.ellipse((x - r, y - r, x + r, y + r), fill=255)

    mask = mask.resize(tuple(edge * scale for edge in size), Image.Resampling.LANCZOS)
    arrow = Image.new("RGB", mask.size, "#FFC977")
    canvas.paste(arrow, tuple(edge * scale for edge in origin), mask)


def render(scale: int, target: Path) -> None:
    width, height = 720 * scale, 460 * scale
    canvas = Image.new("RGB", (width, height))
    pixels = canvas.load()
    # A quiet navy field with light concentrated behind the installation path.
    for y in range(height):
        for x in range(width):
            glow = math.exp(-(((x / scale - 360) / 410) ** 2
                              + ((y / scale - 240) / 300) ** 2))
            pixels[x, y] = tuple(round(base + glow * lift)
                                 for base, lift in zip((17, 20, 27), (17, 22, 32)))
    draw = ImageDraw.Draw(canvas)

    def box(bounds):
        return tuple(round(value * scale) for value in bounds)

    def text(value: str, y: int, size: int, color: str, weight: int = 400):
        font = ImageFont.truetype(str(FONT), size * scale)
        # SF's weight axis uses its own range. Select named instances when present.
        names = font.get_variation_names()
        desired = b"Bold" if weight >= 600 else b"Regular"
        if desired in names:
            font.set_variation_by_name(desired)
        draw.text((360 * scale, y * scale), value, font=font,
                  fill=color, anchor="mt")

    draw.rounded_rectangle(box((18, 18, 702, 442)), radius=22 * scale,
                           outline="#4B4D53", width=scale)
    text("Install Voxley", 48, 30, "#FFFFFF", 700)
    text("Drag Voxley to Applications to get started.", 95, 16, "#E7DCC8")

    # The real draggable Finder icons are placed over these two quiet wells.
    draw.rounded_rectangle(box((117, 154, 273, 316)), radius=22 * scale,
                           fill="#F4E2C6")
    draw.rounded_rectangle(box((447, 154, 603, 316)), radius=22 * scale,
                           fill="#F4E2C6", outline="#D7AE73", width=scale)
    # Rounded dotted outline: evenly spaced dots along four sides and corner arcs.
    left, top, right, bottom, radius = 110, 147, 280, 323, 29
    dots = []
    for start, stop, fixed, horizontal in (
        (left + radius, right - radius, top, True),
        (left + radius, right - radius, bottom, True),
        (top + radius, bottom - radius, left, False),
        (top + radius, bottom - radius, right, False),
    ):
        count = round((stop - start) / 9)
        for index in range(count + 1):
            value = start + (stop - start) * index / count
            dots.append((value, fixed) if horizontal else (fixed, value))
    for cx, cy, begin in ((left + radius, top + radius, 180),
                          (right - radius, top + radius, 270),
                          (right - radius, bottom - radius, 0),
                          (left + radius, bottom - radius, 90)):
        for angle in range(begin + 15, begin + 90, 20):
            dots.append((cx + radius * math.cos(math.radians(angle)),
                         cy + radius * math.sin(math.radians(angle))))
    for x, y in dots:
        draw.ellipse(box((x - 1.15, y - 1.15, x + 1.15, y + 1.15)), fill="#FFD792")

    draw_arrow(canvas, scale)
    draw.line(box((88, 355, 632, 355)), fill="#4B4D53", width=scale)
    text("Eject this disk image when copying is complete.", 378, 15, "#F6F3EB")
    text("Open Voxley from your Applications folder.", 410, 14, "#BBC2CE")
    canvas.save(target, dpi=(72 * scale, 72 * scale))


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="voxley-dmg-artwork-") as directory:
        normal = Path(directory) / "background.png"
        retina = Path(directory) / "background@2x.png"
        render(1, normal)
        render(2, retina)
        subprocess.run(["tiffutil", "-cathidpicheck", normal, retina, "-out",
                        ROOT / "background.tiff"], check=True)
