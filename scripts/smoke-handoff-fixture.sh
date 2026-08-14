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
        qemu_boot_wait="${QEMU_BOOT_WAIT:-8}"
        ;;
    arm64)
        efi_boot_name=BOOTAA64.EFI
        qemu_boot_wait="${QEMU_BOOT_WAIT:-34}"
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

python3 - "$arch" "$macho" "${XNU_HANDOFF_JUMP:-0}" <<'PY'
import struct
import sys
from pathlib import Path

arch, out, handoff_jump = sys.argv[1:4]
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
if arch == "arm64" and handoff_jump == "1":
    def bcond(cond, current_index, target_index):
        imm19 = (target_index - current_index) & 0x7ffff
        return 0x54000000 | (imm19 << 5) | cond

    def branch(current_index, target_index):
        imm26 = (target_index - current_index) & 0x3ffffff
        return 0x14000000 | imm26

    words = [
        0xF940100F,  # ldr x15, [x0, #32] ; boot_args->topOfKernelData
        0xEB0001FF,  # cmp x15, x0
        bcond(9, 2, 26),  # b.ls fail if topOfKernelData <= boot_args phys
        0xF9400410,  # ldr x16, [x0, #8]  ; boot_args->virtBase
        0xF9400811,  # ldr x17, [x0, #16] ; boot_args->physBase
        0xF9403012,  # ldr x18, [x0, #96] ; boot_args->deviceTreeP
        0xEB10025F,  # cmp x18, x16
        bcond(3, 7, 26),  # b.lo fail if deviceTreeP is below virtBase
        0xCB100253,  # sub x19, x18, x16 ; deviceTreeP - virtBase
        0x8B110273,  # add x19, x19, x17 ; derived device tree phys
        0xEB1301FF,  # cmp x15, x19
        bcond(9, 11, 26),  # b.ls fail if topOfKernelData <= device tree phys
        0xF9401409,  # ldr x9, [x0, #40]  ; boot_args->Video.v_baseAddr
        0xF9401C0A,  # ldr x10, [x0, #56] ; boot_args->Video.v_rowBytes
        0x529FE00B,  # mov w11, #0xff00   ; green pixel
        0x5280080C,  # mov w12, #64
        0x5280080D,  # mov w13, #64
        0xAA0903EE,  # mov x14, x9
        0xB90001CB,  # str w11, [x14]
        0x910011CE,  # add x14, x14, #4
        0x710005AD,  # subs w13, w13, #1
        bcond(1, 21, 18),  # b.ne x-loop
        0x8B0A0129,  # add x9, x9, x10
        0x7100058C,  # subs w12, w12, #1
        bcond(1, 24, 16),  # b.ne y-loop
        0x14000000,  # b .
        0xF9401409,  # fail: ldr x9, [x0, #40]
        0xF9401C0A,  # ldr x10, [x0, #56]
        0x52801FEB,  # mov w11, #0xff     ; non-green failure pixel
        branch(29, 15),  # paint failure marker
    ]
    payload[fileoff : fileoff + len(words) * 4] = b"".join(
        struct.pack("<I", word) for word in words
    )
else:
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

QEMU_MENU_WAIT="${QEMU_MENU_WAIT:-14}" QEMU_BOOT_WAIT="$qemu_boot_wait" QEMU_EXPECT_JUMP_MARKER="${XNU_HANDOFF_JUMP:-0}" sh scripts/smoke-boot-limine.sh "$arch" "$image" "$out/qemu"
