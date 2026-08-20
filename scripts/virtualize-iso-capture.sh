#!/usr/bin/env sh
set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <amd64|arm64> <iso> <output-dir>" >&2
    exit 2
fi

arch=$1
iso=$2
out=$3

if [ ! -s "$iso" ]; then
    echo "missing ISO: $iso" >&2
    exit 1
fi

mkdir -p "$out"

monitor="/tmp/os8-iso-qemu-monitor-$$.sock"
serial_log="$out/serial.log"
qemu_log="$out/qemu.log"
qemu_trace_log="$out/qemu-trace.log"
monitor_log="$out/monitor.log"
summary="$out/virtualize-iso.txt"
vars="$out/uefi-vars.fd"
memory_dump="$out/guest-memory.elf"
register_dump="$out/registers.txt"

rm -f "$monitor" "$serial_log" "$qemu_log" "$qemu_trace_log" "$monitor_log" "$summary" "$vars"
rm -f "$memory_dump" "$register_dump" "$out"/screen-*.ppm

find_qemu_file() {
    pattern=$1
    for root in \
        "$(brew --prefix qemu 2>/dev/null || true)/share/qemu" \
        "$(brew --prefix 2>/dev/null || true)/share/qemu" \
        /opt/homebrew/share/qemu \
        /usr/local/share/qemu \
        /usr/share/qemu \
        /usr/share/edk2 \
        /usr/share/OVMF \
        /usr/share/AAVMF
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
        qemu=${QEMU:-qemu-system-x86_64}
        firmware=$(find_qemu_file edk2-x86_64-code.fd || find_first_file \
            /usr/share/OVMF/OVMF_CODE_4M.fd \
            /usr/share/OVMF/OVMF_CODE.fd \
            /usr/share/ovmf/OVMF.fd)
        vars_template=$(find_qemu_file edk2-i386-vars.fd || find_first_file \
            /usr/share/OVMF/OVMF_VARS_4M.fd \
            /usr/share/OVMF/OVMF_VARS.fd || true)
        machine_args="-machine q35 -device VGA"
        boot_args="-drive if=none,id=bootiso,file=$iso,format=raw,media=cdrom,readonly=on -device ahci,id=ahci -device ide-cd,drive=bootiso,bus=ahci.0,bootindex=1"
        ;;
    arm64)
        qemu=${QEMU:-qemu-system-aarch64}
        firmware=$(find_qemu_file edk2-aarch64-code.fd || find_first_file \
            /usr/share/AAVMF/AAVMF_CODE.no-secboot.fd \
            /usr/share/AAVMF/AAVMF_CODE.fd \
            /usr/share/qemu-efi-aarch64/QEMU_EFI.fd)
        vars_template=$(find_qemu_file edk2-arm-vars.fd || find_qemu_file edk2-aarch64-vars.fd || find_first_file \
            /usr/share/AAVMF/AAVMF_VARS.fd || true)
        machine_args="-machine virt -cpu cortex-a57 -device ramfb"
        boot_args="-drive if=none,id=bootiso,file=$iso,format=raw,media=cdrom,readonly=on -device virtio-blk-device,drive=bootiso,bootindex=1"
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
    dd if=/dev/zero of="$vars" bs=1m count="${QEMU_VARS_MB:-64}" >/dev/null 2>&1
fi

memory_mb=${QEMU_MEMORY_MB:-1024}
run_seconds=${QEMU_RUN_SECONDS:-60}
boot_delay=${QEMU_BOOT_DELAY:-2}
auto_enter=${QEMU_AUTO_ENTER:-1}
dump_memory=${QEMU_DUMP_GUEST_MEMORY:-1}
screenshot_interval=${QEMU_SCREENSHOT_INTERVAL:-10}
screenshot_count=${QEMU_SCREENSHOT_COUNT:-6}
qemu_trace=${QEMU_TRACE:-guest_errors,cpu_reset,unimp}
key_sequence=${QEMU_KEY_SEQUENCE:-}

set -- "$qemu" \
    $machine_args \
    -m "${memory_mb}M" \
    -drive "if=pflash,format=raw,readonly=on,file=$firmware" \
    -drive "if=pflash,format=raw,file=$vars" \
    $boot_args \
    -boot menu=off \
    -display vnc=127.0.0.1:0,to=99 \
    -monitor "unix:$monitor,server,nowait" \
    -serial "file:$serial_log" \
    -D "$qemu_trace_log" \
    -d "$qemu_trace" \
    -net none \
    -no-reboot \
    -no-shutdown

printf 'command=' > "$summary"
printf '%s ' "$@" >> "$summary"
printf '\narch=%s\niso=%s\nout=%s\nrun_seconds=%s\nmemory_mb=%s\nkey_sequence=%s\n' \
    "$arch" "$iso" "$out" "$run_seconds" "$memory_mb" "$key_sequence" >> "$summary"

"$@" >>"$qemu_log" 2>&1 &
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
    cat "$qemu_log" >&2 || true
    exit 1
fi

python3 - "$monitor" "$out" "$monitor_log" "$memory_dump" "$register_dump" <<'PY'
from pathlib import Path
import os
import socket
import sys
import time

monitor, out_dir, monitor_log, memory_dump, register_dump = sys.argv[1:6]
out = Path(out_dir)
log = Path(monitor_log)
memory_dump = Path(memory_dump)
register_dump = Path(register_dump)

run_seconds = float(os.environ.get("QEMU_RUN_SECONDS", "60"))
boot_delay = float(os.environ.get("QEMU_BOOT_DELAY", "2"))
auto_enter = os.environ.get("QEMU_AUTO_ENTER", "1") != "0"
dump_memory = os.environ.get("QEMU_DUMP_GUEST_MEMORY", "1") != "0"
screenshot_interval = max(1.0, float(os.environ.get("QEMU_SCREENSHOT_INTERVAL", "10")))
screenshot_count = max(1, int(os.environ.get("QEMU_SCREENSHOT_COUNT", "6")))
key_sequence = os.environ.get("QEMU_KEY_SEQUENCE", "")

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(5)
sock.connect(monitor)

def recv_available(timeout=0.25):
    chunks = []
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            data = sock.recv(65536)
        except socket.timeout:
            break
        if not data:
            break
        chunks.append(data)
        if data.endswith(b"(qemu) "):
            break
    return b"".join(chunks).decode("utf-8", errors="replace")

def hmp(command, settle=0.25):
    sock.sendall((command + "\n").encode("utf-8"))
    time.sleep(settle)
    output = recv_available()
    with log.open("a", encoding="utf-8") as handle:
        handle.write(f"\n(qemu) {command}\n")
        handle.write(output)
    return output

log.write_text(recv_available(1.0), encoding="utf-8")
start = time.monotonic()
key_events = []
if key_sequence:
    for item in key_sequence.split(","):
        item = item.strip()
        if not item:
            continue
        if ":" in item:
            delay_s, key = item.split(":", 1)
            delay = float(delay_s.strip())
            key = key.strip()
        else:
            delay = boot_delay
            key = item
        key_events.append((start + delay, key))
elif auto_enter:
    key_events.append((start + boot_delay, "ret"))
key_events.sort(key=lambda event: event[0])

deadline = start + run_seconds
next_shot = time.monotonic()
shot_index = 1

while time.monotonic() < deadline:
    now = time.monotonic()
    while key_events and now >= key_events[0][0]:
        _, key = key_events.pop(0)
        hmp(f"sendkey {key}")
        now = time.monotonic()
    if shot_index <= screenshot_count and time.monotonic() >= next_shot:
        hmp(f"screendump {out / f'screen-{shot_index:02d}.ppm'}")
        shot_index += 1
        next_shot += screenshot_interval
    time.sleep(0.5)

hmp("stop")
hmp("info status")
hmp("info registers", settle=0.5)
register_dump.write_text(log.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
hmp("info cpus")
hmp("info mtree")
if dump_memory:
    hmp(f"dump-guest-memory -p {memory_dump}", settle=2.0)
hmp("quit")
sock.close()
PY

wait "$qemu_pid" 2>/dev/null || true
trap - EXIT INT TERM
rm -f "$monitor"

python3 - "$summary" "$serial_log" "$qemu_log" "$qemu_trace_log" "$monitor_log" "$memory_dump" "$register_dump" "$out" <<'PY'
from pathlib import Path
import sys

summary, serial_log, qemu_log, qemu_trace_log, monitor_log, memory_dump, register_dump, out = map(Path, sys.argv[1:9])

def size(path):
    return path.stat().st_size if path.exists() else 0

screens = sorted(out.glob("screen-*.ppm"))
serial_text = serial_log.read_text(encoding="utf-8", errors="replace") if serial_log.exists() else ""
qemu_text = qemu_log.read_text(encoding="utf-8", errors="replace") if qemu_log.exists() else ""
trace_text = qemu_trace_log.read_text(encoding="utf-8", errors="replace") if qemu_trace_log.exists() else ""
combined = (serial_text + "\n" + qemu_text + "\n" + trace_text).lower()
markers = ["panic", "fault", "exception", "triple fault", "cpu reset", "guest_errors"]
hits = [marker for marker in markers if marker in combined]

with summary.open("a", encoding="utf-8") as handle:
    handle.write(f"serial_log={serial_log}\nserial_log_bytes={size(serial_log)}\n")
    handle.write(f"qemu_log={qemu_log}\nqemu_log_bytes={size(qemu_log)}\n")
    handle.write(f"qemu_trace_log={qemu_trace_log}\nqemu_trace_log_bytes={size(qemu_trace_log)}\n")
    handle.write(f"monitor_log={monitor_log}\nmonitor_log_bytes={size(monitor_log)}\n")
    handle.write(f"register_dump={register_dump}\nregister_dump_bytes={size(register_dump)}\n")
    handle.write(f"guest_memory_dump={memory_dump}\n")
    handle.write(f"guest_memory_dump_bytes={size(memory_dump)}\n")
    handle.write("screenshots=" + ",".join(str(p) for p in screens) + "\n")
    handle.write("crash_markers=" + ",".join(hits) + "\n")

print(summary.read_text(encoding="utf-8"), end="")
PY
