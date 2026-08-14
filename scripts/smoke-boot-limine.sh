#!/usr/bin/env sh
set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <amd64|arm64> <efi-boot-image> <output-dir>" >&2
    exit 2
fi

arch=$1
boot_image=$2
out=$3

if [ ! -s "$boot_image" ]; then
    echo "missing EFI boot image: $boot_image" >&2
    exit 1
fi

mkdir -p "$out"
monitor="/tmp/os8-qemu-monitor-$$.sock"
screenshot="$out/limine-smoke.ppm"
boot_screenshot="$out/limine-booted.ppm"
report="$out/limine-smoke.txt"
serial_log="$out/serial.log"
vars="$out/uefi-vars.fd"
rm -f "$monitor" "$screenshot" "$boot_screenshot" "$report" "$serial_log" "$vars"
rm -f "$out"/limine-booted-*.ppm

find_qemu_file() {
    pattern=$1
    for root in \
        "$(brew --prefix qemu 2>/dev/null || true)/share/qemu" \
        "$(brew --prefix 2>/dev/null || true)/share/qemu" \
        /opt/homebrew/share/qemu \
        /usr/local/share/qemu \
        /usr/share/qemu
    do
        [ -n "$root" ] || continue
        [ -d "$root" ] || continue
        found=$(find "$root" -name "$pattern" -type f 2>/dev/null | head -n 1)
        if [ -n "$found" ]; then
            printf '%s\n' "$found"
            return 0
        fi
    done
    return 1
}

find_first_file() {
    for candidate in "$@"; do
        if [ -s "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

case "$arch" in
    amd64)
        qemu=qemu-system-x86_64
        firmware=$(find_qemu_file edk2-x86_64-code.fd || find_first_file \
            /usr/share/OVMF/OVMF_CODE_4M.fd \
            /usr/share/ovmf/OVMF.fd)
        vars_template=$(find_qemu_file edk2-i386-vars.fd || find_first_file \
            /usr/share/OVMF/OVMF_VARS_4M.fd \
            /usr/share/OVMF/OVMF_VARS.fd || true)
        machine_args="-machine q35 -device VGA"
        boot_args="-drive if=none,id=bootdisk,file=$boot_image,format=raw,readonly=on -device virtio-blk-pci,drive=bootdisk,bootindex=1"
        ;;
    arm64)
        qemu=qemu-system-aarch64
        firmware=$(find_qemu_file edk2-aarch64-code.fd || find_first_file \
            /usr/share/AAVMF/AAVMF_CODE.no-secboot.fd \
            /usr/share/qemu-efi-aarch64/QEMU_EFI.fd)
        vars_template=$(find_qemu_file edk2-arm-vars.fd || find_qemu_file edk2-aarch64-vars.fd || find_first_file \
            /usr/share/AAVMF/AAVMF_VARS.fd || true)
        machine_args="-machine virt -cpu cortex-a57 -device ramfb"
        boot_args="-drive if=none,id=bootdisk,file=$boot_image,format=raw,readonly=on -device virtio-blk-device,drive=bootdisk,bootindex=1"
        ;;
    *)
        echo "unsupported architecture: $arch" >&2
        exit 2
        ;;
esac

command -v "$qemu" >/dev/null 2>&1

if [ -z "$firmware" ] || [ ! -s "$firmware" ]; then
    echo "missing QEMU UEFI firmware for $arch" >&2
    exit 1
fi

if [ -n "$vars_template" ] && [ -s "$vars_template" ]; then
    cp "$vars_template" "$vars"
else
    dd if=/dev/zero of="$vars" bs=1m count=64 >/dev/null 2>&1
fi

set -- "$qemu" \
    $machine_args \
    -m 768M \
    -drive "if=pflash,format=raw,readonly=on,file=$firmware" \
    -drive "if=pflash,format=raw,file=$vars" \
    $boot_args \
    -boot menu=off \
    -display vnc=127.0.0.1:0,to=99 \
    -monitor "unix:$monitor,server,nowait" \
    -serial "file:$serial_log" \
    -net none \
    -no-reboot \
    -no-shutdown

"$@" >"$out/qemu.log" 2>&1 &
qemu_pid=$!

cleanup() {
    if kill -0 "$qemu_pid" 2>/dev/null; then
        kill "$qemu_pid" 2>/dev/null || true
        wait "$qemu_pid" 2>/dev/null || true
    fi
    rm -f "$monitor"
}
trap cleanup EXIT INT TERM

for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -S "$monitor" ] && break
    sleep 1
done

if [ ! -S "$monitor" ]; then
    echo "QEMU monitor did not become ready" >&2
    cat "$out/qemu.log" >&2 || true
    exit 1
fi

sleep "${QEMU_MENU_WAIT:-8}"

python3 - "$monitor" "$screenshot" "$boot_screenshot" <<'PY'
from pathlib import Path
import socket
import sys
import time
import os

monitor, menu_screenshot, boot_screenshot = sys.argv[1:4]
boot_wait = float(os.environ.get("QEMU_BOOT_WAIT", "8"))
boot_dumps = max(1, int(os.environ.get("QEMU_BOOT_DUMPS", "1")))
boot_dump_interval = float(os.environ.get("QEMU_BOOT_DUMP_INTERVAL", "5"))
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(5)
sock.connect(monitor)
time.sleep(0.2)
sock.recv(4096)
sock.sendall(f"screendump {menu_screenshot}\n".encode())
time.sleep(0.5)
sock.sendall(b"sendkey ret\n")
for index in range(boot_dumps):
    time.sleep(boot_wait if index == 0 else boot_dump_interval)
    target = boot_screenshot if index == boot_dumps - 1 else str(Path(boot_screenshot).with_name(f"limine-booted-{index + 1}.ppm"))
    sock.sendall(f"screendump {target}\n".encode())
    time.sleep(0.5)
sock.sendall(b"quit\n")
sock.close()
PY

wait "$qemu_pid" 2>/dev/null || true
trap - EXIT INT TERM

python3 - "$screenshot" "$boot_screenshot" "$report" <<'PY'
from pathlib import Path
import os
import sys

menu_ppm = Path(sys.argv[1])
boot_ppm = Path(sys.argv[2])
report = Path(sys.argv[3])
serial_log = report.with_name("serial.log")
expect_jump_marker = os.environ.get("QEMU_EXPECT_JUMP_MARKER") == "1"
allow_any_boot = os.environ.get("QEMU_ALLOW_ANY_BOOT") == "1"

def read_ppm(ppm):
    if not ppm.exists() or ppm.stat().st_size == 0:
        raise SystemExit(f"QEMU did not produce framebuffer dump: {ppm}")

    data = ppm.read_bytes()

    def token(offset):
        while data[offset:offset + 1].isspace():
            offset += 1
        if data[offset:offset + 1] == b"#":
            while data[offset:offset + 1] not in (b"\n", b""):
                offset += 1
            return token(offset)
        end = offset
        while end < len(data) and not data[end:end + 1].isspace():
            end += 1
        return data[offset:end], end

    magic, pos = token(0)
    if magic != b"P6":
        raise SystemExit(f"unsupported screenshot format: {magic!r}")

    width_b, pos = token(pos)
    height_b, pos = token(pos)
    maxval_b, pos = token(pos)
    width = int(width_b)
    height = int(height_b)
    maxval = int(maxval_b)
    if maxval != 255:
        raise SystemExit(f"unsupported max pixel value: {maxval}")
    while data[pos:pos + 1].isspace():
        pos += 1
    return width, height, data[pos:]

menu_width, menu_height, menu_pixels = read_ppm(menu_ppm)
boot_width, boot_height, boot_pixels = read_ppm(boot_ppm)

menu_magenta = 0
menu_bright = 0
for i in range(0, len(menu_pixels) - 2, 3):
    r, g, b = menu_pixels[i], menu_pixels[i + 1], menu_pixels[i + 2]
    if r > 160 or g > 160 or b > 160:
        menu_bright += 1
    if r >= 180 and g <= 90 and b >= 180:
        menu_magenta += 1

boot_handoff_green = 0
boot_handoff_panel = 0
boot_handoff_success = 0
boot_jump_marker = 0
boot_magenta = 0
for y in range(boot_height):
    row = y * boot_width * 3
    for x in range(boot_width):
        i = row + x * 3
        r, g, b = boot_pixels[i], boot_pixels[i + 1], boot_pixels[i + 2]
        if r <= 80 and g >= 160 and b <= 140:
            boot_handoff_green += 1
            if x < 80 and y < 80:
                boot_jump_marker += 1
        if r <= 40 and 25 <= g <= 80 and 35 <= b <= 95:
            boot_handoff_panel += 1
        if r <= 60 and g >= 170 and b >= 190:
            boot_handoff_success += 1
        if r >= 180 and g <= 90 and b >= 180:
            boot_magenta += 1

report.write_text(
    f"menu_width={menu_width}\nmenu_height={menu_height}\n"
    f"menu_bright_pixels={menu_bright}\n"
    f"menu_magenta_branding_pixels={menu_magenta}\n"
    f"boot_width={boot_width}\nboot_height={boot_height}\n"
    f"boot_handoff_green_pixels={boot_handoff_green}\n"
    f"boot_handoff_panel_pixels={boot_handoff_panel}\n"
    f"boot_handoff_success_pixels={boot_handoff_success}\n"
    f"boot_jump_marker_pixels={boot_jump_marker}\n"
    f"serial_log_bytes={serial_log.stat().st_size if serial_log.exists() else 0}\n"
    f"boot_magenta_marker_pixels={boot_magenta}\n",
    encoding="ascii",
)
print(report.read_text(encoding="ascii"), end="")

preflight_ok = (
    boot_handoff_green >= 1000
    and boot_handoff_panel >= 1000
    and boot_handoff_success >= 1000
)
jump_ok = boot_jump_marker >= 1000

if menu_magenta < 20 and not preflight_ok and not (expect_jump_marker and jump_ok):
    raise SystemExit("Limine branding colour was not visible; Limine menu likely did not load")
if allow_any_boot:
    raise SystemExit(0)
if expect_jump_marker:
    if not jump_ok:
        raise SystemExit("XNU handoff jump marker was not visible after entering the staged module")
    raise SystemExit(0)
if not preflight_ok:
    raise SystemExit("Limine did not load the XNU handoff preflight screen after selecting the menu entry")
PY
