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
        qemu_boot_wait="${QEMU_BOOT_WAIT:-18}"
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

python3 - "$arch" "$macho" <<'PY'
import os
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
if arch == "arm64":
    filesize = 0x400
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
if arch == "arm64":
    words = []
    labels = {}
    fixups = []

    def emit(word):
        words.append(word)

    def label(name):
        labels[name] = len(words)

    def bcond_label(cond, target):
        fixups.append((len(words), cond, target, "bcond"))
        emit(0)

    def branch_label(target):
        fixups.append((len(words), 0, target, "branch"))
        emit(0)

    emit(0xEB00029F)  # cmp x20, x0
    emit(0x5280000B)  # mov w11, #0
    bcond_label(1, "fail")  # b.ne fail if x20 does not mirror boot_args phys
    emit(0xEB1F02BF)  # cmp x21, xzr
    emit(0x5280002B)  # mov w11, #1
    bcond_label(1, "fail")  # b.ne fail if x21 is not clear
    emit(0xF940100F)  # ldr x15, [x0, #32] ; boot_args->topOfKernelData
    emit(0xEB0001FF)  # cmp x15, x0
    emit(0x5280020B)  # mov w11, #0x10
    bcond_label(9, "fail")  # b.ls fail if topOfKernelData <= boot_args phys
    emit(0xF9400C06)  # ldr x6, [x0, #24] ; boot_args->memSize
    emit(0xEB1F00DF)  # cmp x6, xzr
    emit(0x5280040B)  # mov w11, #0x20
    bcond_label(0, "fail")  # b.eq fail if memSize is zero
    emit(0xD2B00007)  # mov x7, #0x80000000 ; 2 GiB
    emit(0xEB0600FF)  # cmp x7, x6
    emit(0x5280060B)  # mov w11, #0x30
    bcond_label(3, "fail")  # b.lo fail if fixture memSize is implausibly large
    emit(0xB9406804)  # ldr w4, [x0, #104] ; boot_args->deviceTreeLength
    emit(0x6B1F009F)  # cmp w4, wzr
    emit(0x5280068B)  # mov w11, #0x34
    bcond_label(0, "fail")  # b.eq fail if deviceTreeLength is zero
    emit(0x52820005)  # mov w5, #0x1000
    emit(0x6B0400BF)  # cmp w5, w4
    emit(0x5280070B)  # mov w11, #0x38
    bcond_label(3, "fail")  # b.lo fail if deviceTreeLength exceeds allocation
    emit(0xF9423C07)  # ldr x7, [x0, #1144] ; boot_args->memSizeActual
    emit(0xEB0600FF)  # cmp x7, x6
    emit(0x5280078B)  # mov w11, #0x3c
    bcond_label(1, "fail")  # b.ne fail if memSizeActual differs from memSize
    emit(0xF9400410)  # ldr x16, [x0, #8]  ; boot_args->virtBase
    emit(0xF9400811)  # ldr x17, [x0, #16] ; boot_args->physBase
    emit(0xF9403012)  # ldr x18, [x0, #96] ; boot_args->deviceTreeP
    emit(0xEB10025F)  # cmp x18, x16
    emit(0x5280080B)  # mov w11, #0x40
    bcond_label(3, "fail")  # b.lo fail if deviceTreeP is below virtBase
    emit(0xCB100253)  # sub x19, x18, x16 ; deviceTreeP - virtBase
    emit(0x8B110273)  # add x19, x19, x17 ; derived device tree phys
    emit(0xEB1301FF)  # cmp x15, x19
    emit(0x52800A0B)  # mov w11, #0x50
    bcond_label(9, "fail")  # b.ls fail if topOfKernelData <= device tree phys

    emit(0xB9400264)  # ldr w4, [x19]      ; root n_properties
    emit(0x52800085)  # mov w5, #4
    emit(0x6B05009F)  # cmp w4, w5
    emit(0x52800C0B)  # mov w11, #0x60
    bcond_label(1, "fail")  # b.ne
    emit(0xB9400664)  # ldr w4, [x19, #4]  ; root n_children
    emit(0x52800065)  # mov w5, #3
    emit(0x6B05009F)  # cmp w4, w5
    emit(0x52800E0B)  # mov w11, #0x70
    bcond_label(1, "fail")
    emit(0xB9413E64)  # ldr w4, [x19, #316] ; cpu0 n_properties
    emit(0x528000C5)  # mov w5, #6
    emit(0x6B05009F)  # cmp w4, w5
    emit(0x5280100B)  # mov w11, #0x80
    bcond_label(1, "fail")
    emit(0xB941C664)  # ldr w4, [x19, #452] ; cpu0 "reg" property name
    emit(0x528CAE45)  # mov w5, #0x6572
    emit(0x72A00CE5)  # movk w5, #0x67, lsl #16
    emit(0x6B05009F)  # cmp w4, w5
    emit(0x5280120B)  # mov w11, #0x90
    bcond_label(1, "fail")
    emit(0xB9423E64)  # ldr w4, [x19, #572] ; chosen n_properties
    emit(0x52800105)  # mov w5, #8
    emit(0x6B05009F)  # cmp w4, w5
    emit(0x5280140B)  # mov w11, #0xa0
    bcond_label(1, "fail")
    emit(0xB9434E64)  # ldr w4, [x19, #844] ; "dram-base" starts with "dram"
    emit(0x528E4C85)  # mov w5, #0x7264
    emit(0x72ADAC25)  # movk w5, #0x6d61, lsl #16
    emit(0x6B05009F)  # cmp w4, w5
    emit(0x5280160B)  # mov w11, #0xb0
    bcond_label(1, "fail")
    emit(0xB9437A64)  # ldr w4, [x19, #888] ; "dram-size" starts with "dram"
    emit(0x6B05009F)  # cmp w4, w5
    emit(0x5280180B)  # mov w11, #0xc0
    bcond_label(1, "fail")
    emit(0xB943DE64)  # ldr w4, [x19, #988] ; product n_properties
    emit(0x52800045)  # mov w5, #2
    emit(0x6B05009F)  # cmp w4, w5
    emit(0x52801A0B)  # mov w11, #0xd0
    bcond_label(1, "fail")
    emit(0xB9441264)  # ldr w4, [x19, #1040] ; "chip-role" starts with "chip"
    emit(0x528D0C65)  # mov w5, #0x6863
    emit(0x72AE0D25)  # movk w5, #0x7069, lsl #16
    emit(0x6B05009F)  # cmp w4, w5
    emit(0x52801C0B)  # mov w11, #0xe0
    bcond_label(1, "fail")

    emit(0xF9401409)  # ldr x9, [x0, #40]  ; boot_args->Video.v_baseAddr
    emit(0xF9401C0A)  # ldr x10, [x0, #56] ; boot_args->Video.v_rowBytes
    emit(0x529FE00B)  # mov w11, #0xff00   ; green pixel
    emit(0x5280080C)  # mov w12, #64
    label("y_loop")
    emit(0x5280080D)  # mov w13, #64
    emit(0xAA0903EE)  # mov x14, x9
    label("x_loop")
    emit(0xB90001CB)  # str w11, [x14]
    emit(0x910011CE)  # add x14, x14, #4
    emit(0x710005AD)  # subs w13, w13, #1
    bcond_label(1, "x_loop")  # b.ne
    emit(0x8B0A0129)  # add x9, x9, x10
    emit(0x7100058C)  # subs w12, w12, #1
    bcond_label(1, "y_loop")  # b.ne
    label("hang")
    branch_label("hang")
    label("fail")
    emit(0xF9401409)  # ldr x9, [x0, #40]
    emit(0xF9401C0A)  # ldr x10, [x0, #56]
    branch_label("y_loop")  # paint failure marker

    for index, cond, target, kind in fixups:
        target_index = labels[target]
        if kind == "bcond":
            imm19 = (target_index - index) & 0x7ffff
            words[index] = 0x54000000 | (imm19 << 5) | cond
        else:
            imm26 = (target_index - index) & 0x3ffffff
            words[index] = 0x14000000 | imm26

    payload[fileoff : fileoff + len(words) * 4] = b"".join(
        struct.pack("<I", word) for word in words
    )
else:
    payload[fileoff : fileoff + 4] = b"OS8!"
if os.environ.get("XNU_FIXTURE_FAT") == "1" or os.environ.get("XNU_FIXTURE_FAT64") == "1":
    fat_offset = 0x1000
    if os.environ.get("XNU_FIXTURE_FAT64") == "1":
        fat = struct.pack(">II", 0xCAFEBABF, 1)
        fat += struct.pack(">IIQQII", cputype, CPU_SUBTYPE_ALL, fat_offset, len(payload), 12, 0)
    else:
        fat = struct.pack(">II", 0xCAFEBABE, 1)
        fat += struct.pack(">IIIII", cputype, CPU_SUBTYPE_ALL, fat_offset, len(payload), 12)
    fat_payload = bytearray(fat_offset + len(payload))
    fat_payload[: len(fat)] = fat
    fat_payload[fat_offset : fat_offset + len(payload)] = payload
    payload = fat_payload

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

expect_jump_marker=0
if [ "$arch" = "arm64" ]; then
    expect_jump_marker=1
fi
QEMU_MENU_WAIT="${QEMU_MENU_WAIT:-14}" QEMU_BOOT_WAIT="$qemu_boot_wait" QEMU_EXPECT_JUMP_MARKER="$expect_jump_marker" sh scripts/smoke-boot-efi.sh "$arch" "$image" "$out/qemu"
