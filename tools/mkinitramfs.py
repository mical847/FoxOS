#!/usr/bin/env python3
import argparse
import struct
from pathlib import Path

MAGIC = b"FOXFS001"
HEADER_SIZE = 16
ENTRY_SIZE = 48
MAX_FILES = 32
MAX_BYTES = 96 * 512
NAME_SIZE = 32


def build_archive(items: list[str]) -> bytes:
    if not items or len(items) > MAX_FILES:
        raise ValueError(f"archive must contain 1 to {MAX_FILES} files")

    files: list[tuple[bytes, bytes]] = []
    seen: set[bytes] = set()
    for item in items:
        if "=" not in item:
            raise ValueError(f"expected NAME=PATH, got {item!r}")
        name_text, path_text = item.split("=", 1)
        name = name_text.encode("ascii")
        if not name or len(name) >= NAME_SIZE or b"/" in name:
            raise ValueError(f"invalid root filename {name_text!r}")
        if name in seen:
            raise ValueError(f"duplicate filename {name_text!r}")
        seen.add(name)
        files.append((name, Path(path_text).read_bytes()))

    data_offset = HEADER_SIZE + len(files) * ENTRY_SIZE
    entries = bytearray()
    payload = bytearray()
    for name, content in files:
        offset = data_offset + len(payload)
        entries.extend(name.ljust(NAME_SIZE, b"\0"))
        entries.extend(struct.pack("<QQ", offset, len(content)))
        payload.extend(content)

    archive = bytearray(MAGIC)
    archive.extend(struct.pack("<II", len(files), data_offset + len(payload)))
    archive.extend(entries)
    archive.extend(payload)
    if len(archive) > MAX_BYTES:
        raise ValueError(f"archive is {len(archive)} bytes; maximum is {MAX_BYTES}")
    archive.extend(bytes(MAX_BYTES - len(archive)))
    return bytes(archive)


def main() -> None:
    parser = argparse.ArgumentParser(description="Build a FoxOS read-only initramfs")
    parser.add_argument("output", type=Path)
    parser.add_argument("files", nargs="+", metavar="NAME=PATH")
    args = parser.parse_args()
    args.output.write_bytes(build_archive(args.files))


if __name__ == "__main__":
    main()
