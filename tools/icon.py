"""Draws the Nami app icon (1024x1024 PNG) without external libraries."""
import math
import struct
import sys
import zlib

N = 1024
TOP, BOTTOM = (22, 30, 70), (70, 40, 140)
WAVE = (120, 190, 255)


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def wave_y(x, phase, amp, base):
    return base + amp * math.sin(x / N * 2 * math.pi * 1.2 + phase)


waves = [(0.0, 70, 520, 34, 1.0), (1.3, 55, 640, 26, 0.7), (2.6, 40, 750, 18, 0.45)]
rows = []
for y in range(N):
    row = bytearray([0])
    bg = mix(TOP, BOTTOM, y / N)
    for x in range(N):
        c = bg
        for phase, amp, base, width, alpha in waves:
            d = abs(y - wave_y(x, phase, amp, base))
            if d < width:
                t = alpha * min(1.0, (width - d) / 3)
                c = mix(c, WAVE if alpha == 1.0 else (255, 255, 255), t)
        row += bytes(c)
    rows.append(bytes(row))


def chunk(kind, payload):
    out = struct.pack(">I", len(payload)) + kind + payload
    return out + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)


png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", N, N, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
png += chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
