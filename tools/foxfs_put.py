#!/usr/bin/env python3
import argparse
from pathlib import Path

SECTOR_SIZE = 512
HEADER_SECTOR = 225
ENTRY_COUNT = 128
ENTRY_SIZE = 32
TABLE_SECTOR = HEADER_SECTOR + 1
BITMAP_SECTOR = HEADER_SECTOR + 9
DATA_START = 235
DATA_SECTORS = 2645
DIRECTORY = 1
FILE = 2


def fail(message: str) -> None:
    raise SystemExit(message)


def get_entry(table: bytearray, parent_id: int, name: bytes) -> int | None:
    for index in range(ENTRY_COUNT):
        offset = index * ENTRY_SIZE
        entry = table[offset:offset + ENTRY_SIZE]
        if entry[20] and int.from_bytes(entry[29:31], "little") == parent_id:
            if entry[:20].split(b"\0", 1)[0] == name:
                return index
    return None


def bitmap_get(bitmap: bytearray, sector: int) -> bool:
    return bool(bitmap[sector // 8] & (1 << (sector % 8)))


def bitmap_set(bitmap: bytearray, sector: int, allocated: bool) -> None:
    mask = 1 << (sector % 8)
    if allocated:
        bitmap[sector // 8] |= mask
    else:
        bitmap[sector // 8] &= ~mask


def find_extent(bitmap: bytearray, count: int) -> int:
    if count == 0:
        return 0
    for start in range(DATA_SECTORS - count + 1):
        if all(not bitmap_get(bitmap, sector)
               for sector in range(start, start + count)):
            return start
    fail("FoxFS has no contiguous extent large enough for this file")


def install(image: bytearray, target: str, source: Path) -> None:
    try:
        components = [part.encode("ascii") for part in target.split("/")]
    except UnicodeEncodeError:
        fail(f"{target!r}: FoxFS names must be ASCII")
    if target.startswith("/"):
        components = components[1:]
    if not components or any(
        not part or part in (b".", b"..") or len(part) > 19
        for part in components
    ):
        fail(f"{target!r}: invalid FoxFS path (each name must be 1-19 characters)")

    header = image[HEADER_SECTOR * SECTOR_SIZE:
                   (HEADER_SECTOR + 1) * SECTOR_SIZE]
    if (header[:8] != b"FOXDISK1"
            or int.from_bytes(header[8:12], "little") != 1
            or int.from_bytes(header[12:16], "little") != ENTRY_COUNT
            or int.from_bytes(header[16:20], "little") != DATA_START
            or int.from_bytes(header[20:24], "little") != DATA_SECTORS):
        fail("disk image has no valid FoxFS; build it and run `make format`")

    table_offset = TABLE_SECTOR * SECTOR_SIZE
    bitmap_offset = BITMAP_SECTOR * SECTOR_SIZE
    table = bytearray(image[table_offset:table_offset + ENTRY_COUNT * ENTRY_SIZE])
    bitmap = bytearray(image[bitmap_offset:bitmap_offset + SECTOR_SIZE])
    parent_id = 0
    for component in components[:-1]:
        parent_index = get_entry(table, parent_id, component)
        if parent_index is None:
            fail(f"parent directory {component.decode('ascii')!r} does not exist")
        parent = table[parent_index * ENTRY_SIZE:(parent_index + 1) * ENTRY_SIZE]
        if parent[20] != DIRECTORY:
            fail(f"{component.decode('ascii')!r} is not a directory")
        parent_id = parent_index + 1

    filename = components[-1]
    slot = get_entry(table, parent_id, filename)
    if slot is not None:
        old = table[slot * ENTRY_SIZE:(slot + 1) * ENTRY_SIZE]
        if old[20] != FILE:
            fail(f"{target!r} names a directory")
        old_start = int.from_bytes(old[21:23], "little")
        old_count = int.from_bytes(old[23:25], "little")
        for sector in range(old_start, old_start + old_count):
            bitmap_set(bitmap, sector, False)
    else:
        slot = next((index for index in range(ENTRY_COUNT)
                     if table[index * ENTRY_SIZE + 20] == 0), None)
        if slot is None:
            fail("FoxFS directory table is full")

    content = source.read_bytes()
    if len(content) > DATA_SECTORS * SECTOR_SIZE:
        fail(f"{source}: file exceeds FoxFS capacity")
    sector_count = (len(content) + SECTOR_SIZE - 1) // SECTOR_SIZE
    start = find_extent(bitmap, sector_count)
    for sector in range(start, start + sector_count):
        bitmap_set(bitmap, sector, True)

    entry = bytearray(ENTRY_SIZE)
    entry[:len(filename)] = filename
    entry[20] = FILE
    entry[21:23] = start.to_bytes(2, "little")
    entry[23:25] = sector_count.to_bytes(2, "little")
    entry[25:29] = len(content).to_bytes(4, "little")
    entry[29:31] = parent_id.to_bytes(2, "little")
    table[slot * ENTRY_SIZE:(slot + 1) * ENTRY_SIZE] = entry

    padded = content.ljust(sector_count * SECTOR_SIZE, b"\0")
    data_offset = (DATA_START + start) * SECTOR_SIZE
    image[data_offset:data_offset + len(padded)] = padded
    image[table_offset:table_offset + len(table)] = table
    image[bitmap_offset:bitmap_offset + len(bitmap)] = bitmap


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Install host files into a FoxOS disk image without rebuilding the OS"
    )
    parser.add_argument("image", type=Path)
    parser.add_argument("files", nargs="+", metavar="DISK_PATH=HOST_FILE")
    args = parser.parse_args()

    image = bytearray(args.image.read_bytes())
    if len(image) < (DATA_START + DATA_SECTORS) * SECTOR_SIZE:
        fail(f"{args.image}: disk image is too small")
    for item in args.files:
        if "=" not in item:
            fail(f"expected DISK_PATH=HOST_FILE, got {item!r}")
        target, source_text = item.split("=", 1)
        source = Path(source_text)
        if not source.is_file():
            fail(f"{source}: not a regular file")
        install(image, target, source)

    args.image.write_bytes(image)


if __name__ == "__main__":
    main()
