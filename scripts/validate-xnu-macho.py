#!/usr/bin/env python3
import struct
import sys
from pathlib import Path

MH_MAGIC_64 = 0xFEEDFACF
MH_CIGAM_64 = 0xCFFAEDFE
FAT_MAGIC = 0xCAFEBABE
FAT_CIGAM = 0xBEBAFECA
LC_SEGMENT_64 = 0x19
LC_UNIXTHREAD = 0x5
LC_MAIN = 0x80000028
CPU_TYPES = {
    "amd64": 0x01000007,
    "arm64": 0x0100000C,
}


def u32(data, offset, endian="<"):
    return struct.unpack_from(f"{endian}I", data, offset)[0]


def range_ok(base, size, need):
    return base <= size and need <= size - base


def parse_slice(data, arch, offset, size):
    if not range_ok(offset, len(data), 32) or not range_ok(offset, len(data), size):
        raise SystemExit("Mach-O slice extends outside file")

    magic = u32(data, offset)
    if magic != MH_MAGIC_64:
        raise SystemExit(f"Mach-O slice is not little-endian 64-bit Mach-O: 0x{magic:08x}")

    header = struct.unpack_from("<IiiIIIII", data, offset)
    _, cputype, _, _, ncmds, sizeofcmds, _, _ = header
    if cputype != CPU_TYPES[arch]:
        raise SystemExit(f"Mach-O CPU type 0x{cputype:08x} does not match {arch}")
    if not range_ok(32, size, sizeofcmds):
        raise SystemExit("Mach-O load commands extend outside selected slice")

    cursor = offset + 32
    vm_min = None
    vm_max = 0
    entry = None
    entryoff = None
    segments = 0
    for _ in range(ncmds):
        if not range_ok(cursor, len(data), 8):
            raise SystemExit("Mach-O load command header extends outside file")
        cmd, cmdsize = struct.unpack_from("<II", data, cursor)
        if cmdsize < 8 or not range_ok(cursor - offset, size, cmdsize):
            raise SystemExit("Mach-O load command size is invalid")

        if cmd == LC_SEGMENT_64 and cmdsize >= 72:
            (
                _cmd,
                _cmdsize,
                _segname,
                vmaddr,
                vmsize,
                fileoff,
                filesize,
                _maxprot,
                _initprot,
                _nsects,
                _flags,
            ) = struct.unpack_from("<II16sQQQQIIII", data, cursor)
            segments += 1
            if vmsize:
                vm_min = vmaddr if vm_min is None else min(vm_min, vmaddr)
                vm_max = max(vm_max, vmaddr + vmsize)
            if filesize and not range_ok(offset + fileoff, len(data), filesize):
                raise SystemExit("Mach-O segment file range extends outside file")
        elif cmd == LC_MAIN and cmdsize >= 24:
            entryoff, _stacksize = struct.unpack_from("<QQ", data, cursor + 8)
        elif cmd == LC_UNIXTHREAD and cmdsize >= 16:
            flavor, count = struct.unpack_from("<II", data, cursor + 8)
            state = cursor + 16
            if arch == "amd64" and flavor == 4 and count >= 42:
                entry = struct.unpack_from("<Q", data, state + 16 * 8)[0]
            elif arch == "arm64" and flavor == 6 and count >= 68:
                entry = struct.unpack_from("<Q", data, state + 32 * 8)[0]

        cursor += cmdsize

    if segments == 0:
        raise SystemExit("Mach-O has no LC_SEGMENT_64 commands")
    if entry is None and entryoff is not None and vm_min is not None:
        entry = vm_min + entryoff
    if entry is None or entry == 0:
        raise SystemExit("Mach-O has no usable LC_MAIN or LC_UNIXTHREAD entry")

    print(
        f"arch={arch} slice_offset={offset} slice_size={size} "
        f"segments={segments} vm_min=0x{(vm_min or 0):x} vm_max=0x{vm_max:x} entry=0x{entry:x}"
    )


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in CPU_TYPES:
        raise SystemExit(f"usage: {sys.argv[0]} <amd64|arm64> <mach-o>")

    arch = sys.argv[1]
    path = Path(sys.argv[2])
    data = path.read_bytes()
    if len(data) < 4:
        raise SystemExit("Mach-O file is too small")

    magic = u32(data, 0)
    if magic in (MH_MAGIC_64, MH_CIGAM_64):
        parse_slice(data, arch, 0, len(data))
        return

    if magic not in (FAT_MAGIC, FAT_CIGAM):
        raise SystemExit(f"not a Mach-O or FAT Mach-O file: 0x{magic:08x}")

    endian = ">" if magic == FAT_MAGIC else "<"
    if len(data) < 8:
        raise SystemExit("FAT Mach-O header is truncated")
    nfat = u32(data, 4, endian)
    table_size = 8 + nfat * 20
    if not range_ok(0, len(data), table_size):
        raise SystemExit("FAT Mach-O architecture table is truncated")

    wanted = CPU_TYPES[arch]
    for index in range(nfat):
        entry = 8 + index * 20
        cputype, _subtype, offset, size, _align = struct.unpack_from(f"{endian}IIIII", data, entry)
        if cputype == wanted:
            parse_slice(data, arch, offset, size)
            return

    raise SystemExit(f"FAT Mach-O has no {arch} slice")


if __name__ == "__main__":
    main()
