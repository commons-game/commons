#!/usr/bin/env python3
"""
Generate placeholder_tileset.png — pure Python stdlib, no Pillow needed.

Tile layout (16×16 px each, 128×128 total):
  Row 0 — ground:  (0,0) grass  (1,0) dirt  (2,0) stone  (3,0) water
  Row 1 — objects: (0,1) tree   (1,1) rock
  (remaining slots transparent)

Design goals: distinct at a glance, 1-px dark border on every tile so the
grid is always visible, internal pattern that names the type without text.
"""
import struct, zlib, os

TILE = 16          # px per tile
COLS = 8           # columns in sheet
ROWS = 8           # rows in sheet
W = COLS * TILE
H = ROWS * TILE

# ---------------------------------------------------------------------------
# Colour palette
# ---------------------------------------------------------------------------
GRASS_BG   = (0x3a, 0x7d, 0x44, 0xff)   # forest green
GRASS_FG   = (0x22, 0x55, 0x28, 0xff)   # dark green blades
DIRT_BG    = (0x8b, 0x60, 0x14, 0xff)   # warm brown
DIRT_FG    = (0x5a, 0x3a, 0x08, 0xff)   # dark brown dots
STONE_BG   = (0x6e, 0x7b, 0x8b, 0xff)   # slate gray
STONE_FG   = (0x4a, 0x55, 0x62, 0xff)   # crack lines
WATER_BG   = (0x18, 0x5a, 0xb0, 0xff)   # deep blue
WATER_FG   = (0x40, 0x90, 0xd8, 0xff)   # wave highlight
TREE_BG    = (0x14, 0x4a, 0x14, 0xff)   # dark canopy green
TREE_FG    = (0x0a, 0x2a, 0x0a, 0xff)   # deep shadow
TREE_TRUNK = (0x5a, 0x32, 0x14, 0xff)   # brown trunk
ROCK_BG    = (0x44, 0x44, 0x50, 0xff)   # charcoal
ROCK_FG    = (0xcc, 0xcc, 0xcc, 0xff)   # highlight
BORDER     = (0x00, 0x00, 0x00, 0x80)   # semi-transparent black border
EMPTY      = (0x00, 0x00, 0x00, 0x00)   # transparent

# ---------------------------------------------------------------------------
# Pixel helpers
# ---------------------------------------------------------------------------
pixels = bytearray(W * H * 4)

def put(px, py, col):
    if 0 <= px < W and 0 <= py < H:
        i = (py * W + px) * 4
        pixels[i:i+4] = col

def fill_tile(col, row, c):
    ox, oy = col * TILE, row * TILE
    for dy in range(TILE):
        for dx in range(TILE):
            put(ox + dx, oy + dy, c)

def border_tile(col, row):
    ox, oy = col * TILE, row * TILE
    for dx in range(TILE):
        put(ox + dx, oy,          BORDER)
        put(ox + dx, oy + TILE-1, BORDER)
    for dy in range(TILE):
        put(ox,          oy + dy, BORDER)
        put(ox + TILE-1, oy + dy, BORDER)

def hline(col, row, y, x0, x1, c):
    ox, oy = col * TILE, row * TILE
    for dx in range(x0, x1+1):
        put(ox + dx, oy + y, c)

def vline(col, row, x, y0, y1, c):
    ox, oy = col * TILE, row * TILE
    for dy in range(y0, y1+1):
        put(ox + x, oy + dy, c)

def dot(col, row, x, y, c, r=1):
    ox, oy = col * TILE, row * TILE
    for dy in range(-r, r+1):
        for dx in range(-r, r+1):
            if dx*dx + dy*dy <= r*r:
                put(ox + x + dx, oy + y + dy, c)

# ---------------------------------------------------------------------------
# Grass (0,0) — green base + 5 blade marks
# ---------------------------------------------------------------------------
fill_tile(0, 0, GRASS_BG)
for bx in (2, 5, 8, 11, 14):
    for dy in range(3):                     # blade: 3-px tall dark stroke
        put(0*TILE + bx, 0*TILE + 2 + dy, GRASS_FG)
    put(0*TILE + bx - 1, 0*TILE + 3, GRASS_FG)   # lean left
    put(0*TILE + bx + 1, 0*TILE + 3, GRASS_FG)   # lean right
border_tile(0, 0)

# ---------------------------------------------------------------------------
# Dirt (1,0) — brown base + scattered dots
# ---------------------------------------------------------------------------
fill_tile(1, 0, DIRT_BG)
for (dx, dy) in ((3,3),(7,2),(11,4),(5,8),(9,7),(13,11),(3,12),(10,13),(6,6),(13,5)):
    dot(1, 0, dx, dy, DIRT_FG, 1)
border_tile(1, 0)

# ---------------------------------------------------------------------------
# Stone (2,0) — gray base + 2 horizontal crack lines
# ---------------------------------------------------------------------------
fill_tile(2, 0, STONE_BG)
hline(2, 0, 5,  2, 9,  STONE_FG)   # crack 1
hline(2, 0, 6,  5, 13, STONE_FG)   # crack 1 lower
hline(2, 0, 10, 1, 8,  STONE_FG)   # crack 2
hline(2, 0, 11, 4, 11, STONE_FG)   # crack 2 lower
border_tile(2, 0)

# ---------------------------------------------------------------------------
# Water (3,0) — blue base + 2 sine-ish wave arcs
# ---------------------------------------------------------------------------
fill_tile(3, 0, WATER_BG)
wave1 = [6,5,4,4,5,6,7,7,6,5,4,4,5,6,7,7]   # y-offsets for wave 1
wave2 = [12,11,10,10,11,12,13,13,12,11,10,10,11,12,13,13]
for dx in range(TILE):
    put(3*TILE + dx, 0*TILE + wave1[dx], WATER_FG)
    put(3*TILE + dx, 0*TILE + wave1[dx]-1, WATER_FG)
    put(3*TILE + dx, 0*TILE + wave2[dx], WATER_FG)
    put(3*TILE + dx, 0*TILE + wave2[dx]-1, WATER_FG)
border_tile(3, 0)

# ---------------------------------------------------------------------------
# Tree (0,1) — dark canopy circle + brown trunk strip at bottom
# ---------------------------------------------------------------------------
fill_tile(0, 1, EMPTY)           # transparent background
# canopy: filled circle centred at (8,6) r=5
cx, cy = 8, 6
for dy in range(-5, 6):
    for dx in range(-5, 6):
        if dx*dx + dy*dy <= 25:
            put(0*TILE + cx+dx, 1*TILE + cy+dy, TREE_BG)
# shadow arc inside canopy
for dy in range(-3, 1):
    for dx in range(-3, 4):
        if dx*dx + dy*dy <= 9 and dy < 0:
            put(0*TILE + cx+dx, 1*TILE + cy+dy, TREE_FG)
# trunk: 2px wide, 4px tall at bottom
for ty in range(12, 16):
    put(0*TILE + 7, 1*TILE + ty, TREE_TRUNK)
    put(0*TILE + 8, 1*TILE + ty, TREE_TRUNK)
border_tile(0, 1)

# ---------------------------------------------------------------------------
# Rock (1,1) — irregular polygon + white highlight dot
# ---------------------------------------------------------------------------
fill_tile(1, 1, EMPTY)
# rough boulder: fill an irregular oval via row-by-row spans
spans = {
    3: (6, 10), 4: (4, 11), 5: (3, 12), 6: (3, 13),
    7: (4, 12), 8: (5, 12), 9: (6, 11), 10: (7, 10),
}
for ty, (x0, x1) in spans.items():
    for dx in range(x0, x1+1):
        put(1*TILE + dx, 1*TILE + ty, ROCK_BG)
# highlight
dot(1, 1, 6, 5, ROCK_FG, 1)
border_tile(1, 1)

# ---------------------------------------------------------------------------
# Remaining tiles — transparent
# ---------------------------------------------------------------------------
for tc in range(4, COLS):
    fill_tile(tc, 0, EMPTY)
for tc in range(2, COLS):
    fill_tile(tc, 1, EMPTY)
for tr in range(2, ROWS):
    for tc in range(COLS):
        fill_tile(tc, tr, EMPTY)

# ---------------------------------------------------------------------------
# PNG encoder
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

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "placeholder_tileset.png")
with open(out, "wb") as f:
    f.write(make_png(W, H, pixels))
print(f"Written {W}x{H} tileset → {out}")
print("Tile layout:")
print("  (0,0) grass   (1,0) dirt   (2,0) stone  (3,0) water")
print("  (0,1) tree    (1,1) rock")
