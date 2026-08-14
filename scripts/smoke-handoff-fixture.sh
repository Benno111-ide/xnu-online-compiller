#!/usr/bin/env sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <amd64|arm64> <output-dir>" >&2
    exit 2
fi

arch=$1
out=$2
root="$out/efi-root"
image="$out/efiboot.img"
bootstub="$out/bootloader.sys"
macho="$out/xnu-kernel.macho"
limine_dir="${LIMINE_DIR:-build/limine}"

case "$arch" in
    amd64)
        efi_boot_name=BOOTX64.EFI
        ;;
    arm64)
        efi_boot_name=BOOTAA64.EFI
        ;;
    *)
        echo "unsupported architecture: $arch" >&2
        exit 2
        ;;
esac

if [ ! -s "$limine_dir/$efi_boot_name" ]; then
    if [ -s build/limine.tmp/"$efi_boot_name" ]; then
        limine_dir=build/limine.tmp
    else
        sh scripts/fetch-limine.sh "$limine_dir"
    fi
fi

rm -rf "$out"
mkdir -p "$root/EFI/BOOT" "$root/boot" "$root/boot/limine"

sh scripts/build-limine-bootstub.sh "$arch" "$out/bootstub" "$bootstub"

python3 - "$arch" "$macho" <<'PY'
import struct
import sys
from pathlib import Path

arch, out = sys.argv[1:3]
if arch == "amd64":
    cputype = 0x01000007
    flavor = 4
    count = 42
    entry_word_index = 32
elif arch == "arm64":
    cputype = 0x0100000C
    flavor = 6
    count = 68
    entry_word_index = 64
else:
    raise SystemExit(f"unsupported arch: {arch}")

MH_MAGIC_64 = 0xfeedfacf
CPU_SUBTYPE_ALL = 3
MH_EXECUTE = 2
LC_SEGMENT_64 = 0x19
LC_UNIXTHREAD = 0x5

vmaddr = 0x100000
vmsize = 0x1000
fileoff = 0x1000
filesize = 0x100
entry = vmaddr

segment = struct.pack(
    "<II16sQQQQIIII",
    LC_SEGMENT_64,
    72,
    b"__TEXT\0" + b"\0" * 9,
    vmaddr,
    vmsize,
    fileoff,
    filesize,
    7,
    5,
    0,
    0,
)

state = [0] * count
state[entry_word_index] = entry & 0xffffffff
state[entry_word_index + 1] = entry >> 32
thread = struct.pack("<IIII", LC_UNIXTHREAD, 16 + count * 4, flavor, count)
thread += b"".join(struct.pack("<I", value & 0xffffffff) for value in state)

cmds = segment + thread
header = struct.pack(
    "<IiiIIIII",
    MH_MAGIC_64,
    cputype,
    CPU_SUBTYPE_ALL,
    MH_EXECUTE,
    2,
    len(cmds),
    0,
    0,
)

payload = bytearray(fileoff + filesize)
payload[: len(header)] = header
payload[len(header) : len(header) + len(cmds)] = cmds
payload[fileoff : fileoff + 4] = b"OS8!"
Path(out).write_bytes(payload)
PY

cp "$limine_dir/$efi_boot_name" "$root/EFI/BOOT/$efi_boot_name"
cp "$bootstub" "$root/boot/bootloader.sys"
cp "$macho" "$root/boot/xnu-kernel.macho"
cat > "$root/limine.conf" <<'CONF'
timeout: 30
interface_resolution: 800x600
interface_branding: OS8 handoff fixture
interface_branding_colour: ff00ff
interface_branding_color: ff00ff

/OS8 handoff fixture
    protocol: limine
    kernel_path: boot():/boot/bootloader.sys
    module_path: boot():/boot/xnu-kernel.macho
    module_string: xnu-kernel
    cmdline: -v
    resolution: 800x600x32
CONF
cp "$root/limine.conf" "$root/boot/limine/limine.conf"

if command -v truncate >/dev/null 2>&1; then
    truncate -s 128M "$image"
else
    dd if=/dev/zero of="$image" bs=1024 count=131072 >/dev/null 2>&1
fi
mformat -i "$image" ::
mmd -i "$image" ::/EFI ::/EFI/BOOT ::/boot ::/boot/limine
mcopy -i "$image" "$root/EFI/BOOT/$efi_boot_name" "::/EFI/BOOT/$efi_boot_name"
mcopy -i "$image" "$root/limine.conf" "::/limine.conf"
mcopy -i "$image" "$root/limine.conf" "::/boot/limine/limine.conf"
mcopy -i "$image" "$root/boot/bootloader.sys" "::/boot/bootloader.sys"
mcopy -i "$image" "$root/boot/xnu-kernel.macho" "::/boot/xnu-kernel.macho"

QEMU_MENU_WAIT="${QEMU_MENU_WAIT:-14}" sh scripts/smoke-boot-limine.sh "$arch" "$image" "$out/qemu"
