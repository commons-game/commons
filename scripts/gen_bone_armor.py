#!/usr/bin/env python3
"""
Generate bone_armor.png — 16×24px sprite for the Necromancer bone armor equipment.
Pure Python stdlib (struct + zlib), same pattern as tilesets/gen_tileset.py.

Design: dark bone-colored chest armor on transparent background.
  - Shoulder pads: off-white bone ridge on each side
  - Chest plate: ribcage pattern of horizontal bone ribs
  - Overall outline: dark gray/charcoal border for readability
"""
import struct, zlib, os

W = 16
H = 24

EMPTY       = (0x00, 0x00, 0x00, 0x00)  # transparent
BONE_BG     = (0xc8, 0xb8, 0x96, 0xff)  # main bone color (warm off-white)
BONE_DARK   = (0x7a, 0x6a, 0x50, 0xff)  # darker bone / shadow
BONE_LIGHT  = (0xe8, 0xdc, 0xc0, 0xff)  # highlight
OUTLINE     = (0x2a, 0x22, 0x18, 0xff)  # very dark outline
STRAP       = (0x3a, 0x28, 0x18, 0xff)  # leather strap (dark brown)

pixels = bytearray(W * H * 4)

def put(x, y, col):
    if 0 <= x < W and 0 <= y < H:
        i = (y * W + x) * 4
        pixels[i:i+4] = col

# Fill all pixels transparent first
for y in range(H):
    for x in range(W):
        put(x, y, EMPTY)

# ---------------------------------------------------------------------------
# Armor shape definition — col indices for each row (left, right inclusive)
# Armor covers rows 2..21, roughly hourglass / cuirass shaped.
# Format: row -> (x_left, x_right)
# ---------------------------------------------------------------------------
shape = {
    # Shoulder pads (wide)
    2:  (2, 13),
    3:  (1, 14),
    4:  (1, 14),
    5:  (2, 13),
    # Upper torso
    6:  (3, 12),
    7:  (3, 12),
    8:  (3, 12),
    9:  (3, 12),
    10: (3, 12),
    11: (3, 12),
    # Waist (slightly narrower)
    12: (4, 11),
    13: (4, 11),
    # Lower torso / skirt flare
    14: (3, 12),
    15: (3, 12),
    16: (3, 12),
    17: (2, 13),
    18: (2, 13),
    19: (2, 13),
    20: (3, 12),
    21: (3, 12),
}

# Fill armor background
for row, (xl, xr) in shape.items():
    for x in range(xl, xr + 1):
        put(x, row, BONE_BG)

# Outline
for row, (xl, xr) in shape.items():
    put(xl, row, OUTLINE)
    put(xr, row, OUTLINE)
# Top and bottom edge of each continuous block
for row in shape:
    xl, xr = shape[row]
    if row - 1 not in shape:
        for x in range(xl, xr + 1):
            put(x, row, OUTLINE)
    if row + 1 not in shape:
        for x in range(xl, xr + 1):
            put(x, row, OUTLINE)

# Shoulder pad ridge highlight (top of shoulder, rows 2-3)
for x in range(3, 13):
    put(x, 2, BONE_LIGHT)
put(2, 3, BONE_LIGHT)
put(13, 3, BONE_LIGHT)

# Rib lines — horizontal ribs across chest (rows 7, 9, 11)
for row in [7, 9, 11]:
    for x in range(4, 12):
        if x % 2 == 0:
            put(x, row, BONE_DARK)

# Central sternum line
for row in range(6, 12):
    put(7, row, BONE_DARK)
    put(8, row, BONE_DARK)

# Waist strap
for x in range(4, 12):
    put(x, 12, STRAP)
    put(x, 13, STRAP)
put(4, 12, OUTLINE)
put(11, 12, OUTLINE)
put(4, 13, OUTLINE)
put(11, 13, OUTLINE)

# Lower skirt rib lines (rows 15, 17, 19)
for row in [15, 17, 19]:
    for x in range(4, 12):
        if x % 2 == 1:
            put(x, row, BONE_DARK)

# ---------------------------------------------------------------------------
# PNG encoder (identical to gen_tileset.py)
# ---------------------------------------------------------------------------
def make_png(width, height, px):
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    ihdr = struct.pack(">II", width, height) + bytes([8, 6, 0, 0, 0])
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        rows.extend(px[y * width * 4:(y+1) * width * 4])
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
            + chunk(b"IEND", b""))

out = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "assets", "necromancer", "armor", "bone_armor.png"
)
out = os.path.normpath(out)
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "wb") as f:
    f.write(make_png(W, H, pixels))
print(f"Written {W}x{H} bone armor sprite → {out}")
