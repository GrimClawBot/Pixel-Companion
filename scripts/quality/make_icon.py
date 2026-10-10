"""Draw the original Pixel Companion blob as a PNG with only Python stdlib."""
import struct
import sys
import zlib
from pathlib import Path

SIZE = 1024

def blob(x, y, cx, cy, rx, ry):
    return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1

def png_chunk(name, payload):
    return (
        struct.pack(">I", len(payload)) + name + payload
        + struct.pack(">I", zlib.crc32(name + payload) & 0xFFFFFFFF)
    )

scanlines = []
for y in range(SIZE):
    row = bytearray(b"\x00")
    for x in range(SIZE):
        rgba = (22, 30, 48, 255)
        if blob(x, y, 512, 512, 445, 445):
            rgba = (39, 51, 79, 255)
        if blob(x, y, 512, 520, 280, 280):
            rgba = (231, 238, 252, 255)
        if blob(x, y, 413, 490, 29, 45) or blob(x, y, 611, 490, 29, 45):
            rgba = (29, 41, 67, 255)
        if blob(x, y, 512, 622, 51, 21):
            rgba = (97, 132, 206, 255)
        if blob(x, y, 322, 670, 54, 38) or blob(x, y, 702, 670, 54, 38):
            rgba = (115, 167, 250, 255)
        row.extend(rgba)
    scanlines.append(bytes(row))
header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
image = b"\x89PNG\r\n\x1a\n"
image += png_chunk(b"IHDR", header)
image += png_chunk(b"IDAT", zlib.compress(b"".join(scanlines), level=6))
image += png_chunk(b"IEND", b"")
Path(sys.argv[1]).write_bytes(image)
