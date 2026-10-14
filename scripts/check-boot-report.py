#!/usr/bin/env python3
"""Validate ISO boot captures without mistaking loader progress for an OS boot."""
from pathlib import Path
import re
import subprocess
import sys


def assess(serial, screen, qemu, trace):
    guest = serial + "\n" + screen
    failures = []
    if re.search(r"X64 Exception Type|ExceptionData\s*-|General Protection|"
                 r"\btriple fault\b|\bpanic\s*\(|\bkernel panic\b|"
                 r"\bpanic\(cpu|Synchronous Exception", guest, re.I):
        failures.append("guest panic or firmware exception detected")
    if re.search(r"\btriple fault\b", trace, re.I):
        failures.append("QEMU reported a triple fault")
    if re.search(r"qemu-system[^\n]*: (?:error:|Could not|failed|invalid)", qemu, re.I):
        failures.append("QEMU reported a startup or device error")
    kernel = bool(re.search(r"Darwin Kernel Version", guest, re.I))
    loader = kernel or bool(re.search(r"OpenCore|\bOC[BS]?:|XNU EFI fallback loader", guest, re.I))
    if not loader:
        failures.append("no recognizable loader or XNU output in serial log or screenshots")
    return loader, kernel, failures


def main():
    out = Path(sys.argv[1])
    def read(name):
        path = out / name
        return path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""

    screen_text = []
    for screen in sorted(out.glob("screen-*.ppm")):
        result = subprocess.run(["tesseract", str(screen), "stdout"],
                                capture_output=True, text=True, check=True)
        screen_text.append(f"--- {screen.name} ---\n{result.stdout}")
    screen = "\n".join(screen_text)
    (out / "screen-text.txt").write_text(screen, encoding="utf-8")
    serial = read("serial.log")
    loader, kernel, failures = assess(serial, screen, read("qemu.log"), read("qemu-trace.log"))
    report = (f"result={'FAIL' if failures else 'PASS'}\n"
              f"loader_output_detected={int(loader)}\n"
              f"xnu_output_detected={int(kernel)}\n"
              f"serial_log_bytes={(out / 'serial.log').stat().st_size if (out / 'serial.log').exists() else 0}\n"
              "scope=UEFI loader boot; XNU output does not prove userspace startup\n"
              + "".join(f"failure={failure}\n" for failure in failures))
    (out / "boot-test.txt").write_text(report, encoding="utf-8")
    print(report, end="")
    return int(bool(failures))


if __name__ == "__main__":
    sys.exit(main())
