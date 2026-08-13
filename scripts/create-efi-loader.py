#!/usr/bin/env python3
import argparse
import struct
from pathlib import Path


def align(value, alignment):
    return (value + alignment - 1) & ~(alignment - 1)


def make_pe(machine, code):
    file_alignment = 0x200
    section_alignment = 0x1000
    pe_offset = 0x80
    optional_header_size = 0xF0
    section_table_offset = pe_offset + 4 + 20 + optional_header_size
    size_of_headers = align(section_table_offset + 40, file_alignment)
    text_rva = section_alignment
    text_raw_size = align(len(code), file_alignment)
    size_of_image = align(text_rva + len(code), section_alignment)

    dos = bytearray(pe_offset)
    dos[0:2] = b"MZ"
    struct.pack_into("<I", dos, 0x3C, pe_offset)

    coff = struct.pack(
        "<HHIIIHH",
        machine,
        1,
        0,
        0,
        0,
        optional_header_size,
        0x0222,
    )

    optional = bytearray()
    optional += struct.pack("<HBBIIIII", 0x20B, 0, 0, text_raw_size, 0, 0, text_rva, text_rva)
    optional += struct.pack("<Q", 0x400000)
    optional += struct.pack("<II", section_alignment, file_alignment)
    optional += struct.pack("<HHHHHH", 0, 0, 0, 0, 2, 70)
    optional += struct.pack("<IIIIHH", 0, size_of_image, size_of_headers, 0, 10, 0)
    optional += struct.pack("<QQQQ", 0x100000, 0x1000, 0x100000, 0x1000)
    optional += struct.pack("<II", 0, 16)
    optional += b"\0" * (16 * 8)
    if len(optional) != optional_header_size:
        raise AssertionError(f"optional header is {len(optional)} bytes")

    section = struct.pack(
        "<8sIIIIIIHHI",
        b".text\0\0\0",
        len(code),
        text_rva,
        text_raw_size,
        size_of_headers,
        0,
        0,
        0,
        0,
        0x60000020,
    )

    image = bytes(dos) + b"PE\0\0" + coff + bytes(optional) + section
    image += b"\0" * (size_of_headers - len(image))
    image += code
    image += b"\0" * (text_raw_size - len(code))
    return image


def main():
    parser = argparse.ArgumentParser(description="Create a tiny PE32+ UEFI boot application.")
    parser.add_argument("arch", choices=["amd64", "arm64"])
    parser.add_argument("output")
    args = parser.parse_args()

    if args.arch == "amd64":
        machine = 0x8664
        code = b"\x48\x31\xc0\xc3"
    else:
        machine = 0xAA64
        code = bytes.fromhex("000080d2c0035fd6")

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(make_pe(machine, code))


if __name__ == "__main__":
    main()
