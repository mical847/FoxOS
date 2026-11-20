#!/usr/bin/env python3
import argparse
from pathlib import Path

SECTOR_SIZE = 512
MAGIC = b"FOXDISK1"
METADATA_SECTORS = 10


def build_filesystem() -> bytes:
    image = bytearray(METADATA_SECTORS * SECTOR_SIZE)
    image[:8] = MAGIC
    image[8:12] = (1).to_bytes(4, "little")
    image[12:16] = (128).to_bytes(4, "little")
    image[16:20] = (235).to_bytes(4, "little")
    image[20:24] = (2645).to_bytes(4, "little")
    return bytes(image)


def main() -> None:
    parser = argparse.ArgumentParser(description="Create an empty FoxOS disk filesystem")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.write_bytes(build_filesystem())


if __name__ == "__main__":
    main()
