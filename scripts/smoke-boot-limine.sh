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
monitor="$out/qemu-monitor.sock"
screenshot="$out/limine-smoke.ppm"
boot_screenshot="$out/limine-booted.ppm"
report="$out/limine-smoke.txt"
vars="$out/uefi-vars.fd"
rm -f "$monitor" "$screenshot" "$boot_screenshot" "$report" "$vars"

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

case "$arch" in
    amd64)
        qemu=qemu-system-x86_64
        firmware=$(find_qemu_file edk2-x86_64-code.fd)
        vars_template=$(find_qemu_file edk2-i386-vars.fd || true)
        machine_args="-machine q35 -device VGA"
        boot_args="-drive if=none,id=bootdisk,file=$boot_image,format=raw,readonly=on -device virtio-blk-pci,drive=bootdisk,bootindex=1"
        ;;
    arm64)
        qemu=qemu-system-aarch64
        firmware=$(find_qemu_file edk2-aarch64-code.fd)
        vars_template=$(find_qemu_file edk2-arm-vars.fd || find_qemu_file edk2-aarch64-vars.fd || true)
        machine_args="-machine virt -cpu cortex-a57 -device ramfb"
        boot_args="-drive if=none,id=bootdisk,file=$boot_image,format=raw,readonly=on -device virtio-blk-device,drive=bootdisk,bootindex=1"
        ;;
    *)
        echo "unsupported architecture: $arch" >&2
        exit 2
        ;;
esac

command -v "$qemu" >/dev/null 2>&1

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
    -serial none \
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

sleep 8

python3 - "$monitor" "$screenshot" "$boot_screenshot" <<'PY'
import socket
import sys
import time

monitor, menu_screenshot, boot_screenshot = sys.argv[1:4]
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(5)
sock.connect(monitor)
time.sleep(0.2)
sock.recv(4096)
sock.sendall(f"screendump {menu_screenshot}\n".encode())
time.sleep(0.5)
sock.sendall(b"sendkey ret\n")
time.sleep(8)
sock.sendall(f"screendump {boot_screenshot}\n".encode())
time.sleep(0.5)
sock.sendall(b"quit\n")
sock.close()
PY

wait "$qemu_pid" 2>/dev/null || true
trap - EXIT INT TERM

python3 - "$screenshot" "$boot_screenshot" "$report" <<'PY'
from pathlib import Path
import sys

menu_ppm = Path(sys.argv[1])
boot_ppm = Path(sys.argv[2])
report = Path(sys.argv[3])

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

boot_green = 0
boot_magenta = 0
for i in range(0, len(boot_pixels) - 2, 3):
    r, g, b = boot_pixels[i], boot_pixels[i + 1], boot_pixels[i + 2]
    if r <= 80 and g >= 160 and b <= 140:
        boot_green += 1
    if r >= 180 and g <= 90 and b >= 180:
        boot_magenta += 1

report.write_text(
    f"menu_width={menu_width}\nmenu_height={menu_height}\n"
    f"menu_bright_pixels={menu_bright}\n"
    f"menu_magenta_branding_pixels={menu_magenta}\n"
    f"boot_width={boot_width}\nboot_height={boot_height}\n"
    f"boot_green_marker_pixels={boot_green}\n"
    f"boot_magenta_marker_pixels={boot_magenta}\n",
    encoding="ascii",
)
print(report.read_text(encoding="ascii"), end="")

if menu_magenta < 20:
    raise SystemExit("Limine branding colour was not visible; Limine menu likely did not load")
if boot_green < 1000:
    raise SystemExit("Limine did not load the boot stub marker after selecting the menu entry")
PY
