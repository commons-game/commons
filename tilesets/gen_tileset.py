#!/usr/bin/env python3
"""Generate placeholder_tileset.png using only Python stdlib (struct + zlib)."""
import struct
import zlib

WIDTH = 128
HEIGHT = 128

# Define tile colors (col, row): (R, G, B, A)
TILE_COLORS = {
    (0, 0): (34,  139,  34, 255),   # grass
    (1, 0): (139,  90,  43, 255),   # dirt
    (2, 0): (128, 128, 128, 255),   # stone
    (3, 0): (30,  144, 255, 255),   # water
    (4, 0): (0,     0,   0,   0),   # empty/transparent
    (0, 1): (0,   100,   0, 255),   # tree
    (1, 1): (64,   64,  64, 255),   # rock
}
TILE_SIZE = 16


def make_png(width: int, height: int, pixels: bytearray) -> bytes:
    """Build a minimal valid PNG from raw RGBA pixel data (row-major)."""

    def chunk(tag: bytes, data: bytes) -> bytes:
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    # IHDR
    ihdr_data = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    # PNG uses bit depth 8, colour type 6 (RGBA) — wait, colour type 2 is RGB.
    # We need RGBA so use colour type 6.
    ihdr_data = struct.pack(">II", width, height) + bytes([8, 6, 0, 0, 0])

    # Build raw scanlines (filter byte 0 = None prepended to each row)
    raw_rows = bytearray()
    for y in range(height):
        raw_rows.append(0)  # filter type None
        raw_rows.extend(pixels[y * width * 4:(y + 1) * width * 4])

    idat_data = zlib.compress(bytes(raw_rows), 9)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", ihdr_data)
    png += chunk(b"IDAT", idat_data)
    png += chunk(b"IEND", b"")
    return png


def get_tile_color(col: int, row: int) -> tuple:
    return TILE_COLORS.get((col, row), (0, 0, 0, 0))


# Build pixel array (RGBA)
pixels = bytearray(WIDTH * HEIGHT * 4)
for py in range(HEIGHT):
    for px in range(WIDTH):
        tile_col = px // TILE_SIZE
        tile_row = py // TILE_SIZE
        r, g, b, a = get_tile_color(tile_col, tile_row)
        idx = (py * WIDTH + px) * 4
        pixels[idx]     = r
        pixels[idx + 1] = g
        pixels[idx + 2] = b
        pixels[idx + 3] = a

png_bytes = make_png(WIDTH, HEIGHT, pixels)

import os
out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "placeholder_tileset.png")
with open(out_path, "wb") as f:
    f.write(png_bytes)
print(f"Written {len(png_bytes)} bytes to {out_path}")
