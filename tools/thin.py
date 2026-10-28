"""Keeps only the arm64 slice of a universal Mach-O binary (in place)."""
import struct
import sys

CPU_ARM64 = 0x0100000C

path = sys.argv[1]
data = open(path, "rb").read()
magic, count = struct.unpack(">II", data[:8])
if magic != 0xCAFEBABE:
    sys.exit(f"{path}: not a universal binary")
for i in range(count):
    cpu, _sub, off, size, _align = struct.unpack(">iiIII", data[8 + i * 20: 28 + i * 20])
    if cpu == CPU_ARM64:
        open(path, "wb").write(data[off:off + size])
        print(f"{path}: kept arm64 ({size >> 20} MB of {len(data) >> 20} MB)")
        break
else:
    sys.exit(f"{path}: no arm64 slice")
